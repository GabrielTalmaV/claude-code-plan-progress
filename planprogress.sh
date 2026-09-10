#!/bin/bash
# Source: https://github.com/GabrielTalmaV/claude-code-plan-progress
#
# Renders plan-implementation progress as a Claude Code statusLine segment,
# AND doubles as its own CLI to configure/enable/disable/install itself.
#
# How rendering works: Claude Code's statusLine command receives a JSON blob
# on stdin that includes `transcript_path`, the path to the session's JSONL
# transcript. Every time Claude updates its todo list (the TodoWrite tool,
# the same list rendered in the CLI UI), that call is recorded in the
# transcript. This script reads the *latest* TodoWrite call and renders it
# as "Task 3/5 - title (60%) [bar] - Plan name". No separate progress-state
# file needed - the plan name itself comes from the most recent
# ExitPlanMode call (the plan approval step): its first heading line.
#
# CLI usage (run this script directly, with arguments, from a terminal):
#   planprogress.sh enable
#   planprogress.sh disable
#   planprogress.sh status
#   planprogress.sh config --width 20 --color cyan --filled-char "=" --empty-char "-"
#   planprogress.sh config --no-title --title-max-len 30
#   planprogress.sh config --show
#   planprogress.sh config --reset
#   planprogress.sh install [--settings <path>]
#   planprogress.sh sessions                    # list every plan in this project's sessions
#   planprogress.sh use <number>                # pin the status line to one of them
#   planprogress.sh next                        # cycle the pin to the next session
#   planprogress.sh unpin                       # back to automatic (current session, or most recent other one)

set -f  # disable globbing
VERSION="1.3.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config"

# ===== Color palette (plain case/switch - bash 3.2 on macOS has no assoc arrays) =====
reset='\033[0m'

palette_code() {
    case "$1" in
        red) printf '\033[38;2;255;85;85m' ;;
        green) printf '\033[38;2;0;160;0m' ;;
        yellow) printf '\033[38;2;230;200;0m' ;;
        blue) printf '\033[38;2;0;153;255m' ;;
        cyan) printf '\033[38;2;46;149;153m' ;;
        purple) printf '\033[38;2;167;139;250m' ;;
        orange) printf '\033[38;2;255;176;85m' ;;
        white) printf '\033[38;2;220;220;220m' ;;
        dim) printf '\033[2m' ;;
        *) printf '' ;;
    esac
}

# ===== Config file helpers (KEY=VALUE lines) =====
set_config_key() {
    local key="$1" value="$2"
    touch "$CONFIG_FILE"
    if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
        # Portable in-place edit (avoids GNU/BSD sed -i flag differences)
        awk -v k="$key" -v v="$value" -F'=' 'BEGIN{OFS="="} $1==k{$0=k"="v} {print}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        echo "${key}=${value}" >> "$CONFIG_FILE"
    fi
}

load_config() {
    ENABLED=1
    BAR_WIDTH=10
    COLOR_MODE="auto"
    FILLED_CHAR="█"
    EMPTY_CHAR="░"
    NO_EMOJI=0
    SHOW_TITLE=1
    TITLE_MAX_LEN=40
    CROSS_SESSION=1
    CROSS_SESSION_MAX_AGE_MIN=180
    PINNED_SESSION=""
    LOCALE_CFG=""

    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi

    # Env vars always win over the config file, for one-off overrides.
    BAR_WIDTH="${PLAN_PROGRESS_BAR_WIDTH:-$BAR_WIDTH}"
    COLOR_MODE="${PLAN_PROGRESS_COLOR:-$COLOR_MODE}"
    FILLED_CHAR="${PLAN_PROGRESS_FILLED_CHAR:-$FILLED_CHAR}"
    EMPTY_CHAR="${PLAN_PROGRESS_EMPTY_CHAR:-$EMPTY_CHAR}"
    [ -n "${PLAN_PROGRESS_NO_EMOJI:-}" ] && NO_EMOJI="$PLAN_PROGRESS_NO_EMOJI"
    [ -n "${PLAN_PROGRESS_ENABLED:-}" ] && ENABLED="$PLAN_PROGRESS_ENABLED"
    [ -n "${PLAN_PROGRESS_SHOW_TITLE:-}" ] && SHOW_TITLE="$PLAN_PROGRESS_SHOW_TITLE"
    TITLE_MAX_LEN="${PLAN_PROGRESS_TITLE_MAX_LEN:-$TITLE_MAX_LEN}"
    [ -n "${PLAN_PROGRESS_CROSS_SESSION:-}" ] && CROSS_SESSION="$PLAN_PROGRESS_CROSS_SESSION"
    CROSS_SESSION_MAX_AGE_MIN="${PLAN_PROGRESS_CROSS_SESSION_MAX_AGE_MIN:-$CROSS_SESSION_MAX_AGE_MIN}"
    PINNED_SESSION="${PLAN_PROGRESS_PINNED_SESSION:-$PINNED_SESSION}"
    LOCALE="${PLAN_PROGRESS_LOCALE:-$LOCALE_CFG}"

    if [ -z "$LOCALE" ]; then
        case "${LANG:-}${LC_ALL:-}" in
            es*) LOCALE="es" ;;
            *) LOCALE="en" ;;
        esac
    fi

    if [ "$LOCALE" = "es" ]; then
        LABEL_TASK="Tarea"; LABEL_DONE="Plan completo"; LABEL_NONE="Sin plan activo"; LABEL_OTHER_SESSION="otra sesión"; LABEL_PINNED="fijado"; LABEL_WORKING="en curso"; LABEL_TODOWRITE_DISABLED="TodoWrite deshabilitada en esta sesión"
    else
        LABEL_TASK="Task"; LABEL_DONE="Plan complete"; LABEL_NONE="No active plan"; LABEL_OTHER_SESSION="other session"; LABEL_PINNED="pinned"; LABEL_WORKING="in progress"; LABEL_TODOWRITE_DISABLED="TodoWrite disabled for this session"
    fi
}

# ===== CLI subcommands =====
cmd_enable() {
    set_config_key "ENABLED" "1"
    echo "Plan progress bar enabled."
}

cmd_disable() {
    set_config_key "ENABLED" "0"
    echo "Plan progress bar disabled (status line will print nothing for this segment)."
}

cmd_config() {
    local show=0 do_reset=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --width) set_config_key "BAR_WIDTH" "$2"; shift 2 ;;
            --color) set_config_key "COLOR_MODE" "$2"; shift 2 ;;
            --filled-char) set_config_key "FILLED_CHAR" "$2"; shift 2 ;;
            --empty-char) set_config_key "EMPTY_CHAR" "$2"; shift 2 ;;
            --locale) set_config_key "LOCALE_CFG" "$2"; shift 2 ;;
            --emoji) set_config_key "NO_EMOJI" "0"; shift ;;
            --no-emoji) set_config_key "NO_EMOJI" "1"; shift ;;
            --title) set_config_key "SHOW_TITLE" "1"; shift ;;
            --no-title) set_config_key "SHOW_TITLE" "0"; shift ;;
            --title-max-len) set_config_key "TITLE_MAX_LEN" "$2"; shift 2 ;;
            --cross-session) set_config_key "CROSS_SESSION" "1"; shift ;;
            --no-cross-session) set_config_key "CROSS_SESSION" "0"; shift ;;
            --cross-session-max-age) set_config_key "CROSS_SESSION_MAX_AGE_MIN" "$2"; shift 2 ;;
            --show) show=1; shift ;;
            --reset) do_reset=1; shift ;;
            *) echo "Unknown flag: $1" >&2; exit 1 ;;
        esac
    done

    if [ "$do_reset" = "1" ]; then
        rm -f "$CONFIG_FILE"
        echo "Config reset to defaults."
        return
    fi

    if [ "$show" = "1" ]; then
        load_config
        echo "ENABLED=$ENABLED"
        echo "BAR_WIDTH=$BAR_WIDTH"
        echo "COLOR_MODE=$COLOR_MODE"
        echo "FILLED_CHAR=$FILLED_CHAR"
        echo "EMPTY_CHAR=$EMPTY_CHAR"
        echo "NO_EMOJI=$NO_EMOJI"
        echo "SHOW_TITLE=$SHOW_TITLE"
        echo "TITLE_MAX_LEN=$TITLE_MAX_LEN"
        echo "CROSS_SESSION=$CROSS_SESSION"
        echo "CROSS_SESSION_MAX_AGE_MIN=$CROSS_SESSION_MAX_AGE_MIN"
        echo "PINNED_SESSION=${PINNED_SESSION:-(none)}"
        echo "LOCALE=$LOCALE"
        echo "Config file: $CONFIG_FILE"
    fi
}

# Best-effort mirror of how Claude Code names a project's transcript folder
# under ~/.claude/projects/ (cwd with "/" replaced by "-"). Override with
# --dir on 'sessions'/'use' if a project's real folder doesn't match.
resolve_project_dir() {
    local cwd="${1:-$PWD}" project_id
    project_id=$(printf '%s' "$cwd" | sed 's/\//-/g')
    printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$project_id"
}

# Lists every session transcript for the current project (most recently
# modified first) with its plan title and task progress, so you can see
# every plan in flight and pick which one 'use' should pin the status line to.
cmd_sessions() {
    local dir="" cwd="$PWD"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir) dir="$2"; shift 2 ;;
            --cwd) cwd="$2"; shift 2 ;;
            *) echo "Unknown flag: $1" >&2; exit 1 ;;
        esac
    done
    [ -z "$dir" ] && dir=$(resolve_project_dir "$cwd")

    if [ ! -d "$dir" ]; then
        echo "No Claude Code project directory found at $dir" >&2
        echo "Pass --dir <path> if this guess is wrong (project folders live under ~/.claude/projects/)." >&2
        exit 1
    fi

    load_config
    echo "Sessions in $dir:"
    local i=0 f todos total completed title marker
    while IFS= read -r f; do
        i=$((i + 1))
        todos=$(extract_todos "$f")
        marker=""
        [ "$f" = "$PINNED_SESSION" ] && marker=" [pinned]"
        if [ -z "$todos" ] || [ "$todos" = "null" ]; then
            printf "  %d) %s - no plan\n" "$i" "$(basename "$f" .jsonl)"
            continue
        fi
        total=$(echo "$todos" | jq 'length')
        completed=$(echo "$todos" | jq '[.[] | select(.status == "completed")] | length')
        title=$(get_plan_title "$f")
        [ -z "$title" ] && title="(untitled plan)"
        printf "  %d) %s - %d/%d tasks - %s%s\n" "$i" "$(basename "$f" .jsonl)" "$completed" "$total" "$title" "$marker"
    done < <(set +f; ls -t "$dir"/*.jsonl 2>/dev/null)

    [ "$i" -eq 0 ] && echo "  (no sessions found)"
    echo
    echo "Run 'planprogress.sh use <number>' to pin the status line to one, or 'planprogress.sh unpin' for automatic mode."
}

cmd_use() {
    local index="" dir="" cwd="$PWD"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir) dir="$2"; shift 2 ;;
            --cwd) cwd="$2"; shift 2 ;;
            *) index="$1"; shift ;;
        esac
    done
    if [ -z "$index" ]; then
        echo "Usage: planprogress.sh use <number>   (run 'planprogress.sh sessions' to see the list)" >&2
        exit 1
    fi
    [ -z "$dir" ] && dir=$(resolve_project_dir "$cwd")
    [ -d "$dir" ] || { echo "Project directory not found: $dir" >&2; exit 1; }

    local i=0 f chosen=""
    while IFS= read -r f; do
        i=$((i + 1))
        if [ "$i" -eq "$index" ]; then chosen="$f"; break; fi
    done < <(set +f; ls -t "$dir"/*.jsonl 2>/dev/null)

    if [ -z "$chosen" ]; then
        echo "No session #$index found. Run 'planprogress.sh sessions' first." >&2
        exit 1
    fi

    set_config_key "PINNED_SESSION" "$chosen"
    echo "Pinned the status line to: $(basename "$chosen" .jsonl)"
}

cmd_unpin() {
    set_config_key "PINNED_SESSION" ""
    echo "Unpinned. Status line will follow the current session (falling back to other open sessions) automatically again."
}

# Cycles the pin forward through the project's sessions (wrapping around) -
# quicker than looking up a number with 'sessions' each time you want to
# check a different plan.
cmd_next() {
    local dir="" cwd="$PWD"
    while [ $# -gt 0 ]; do
        case "$1" in
            --dir) dir="$2"; shift 2 ;;
            --cwd) cwd="$2"; shift 2 ;;
            *) echo "Unknown flag: $1" >&2; exit 1 ;;
        esac
    done
    [ -z "$dir" ] && dir=$(resolve_project_dir "$cwd")
    [ -d "$dir" ] || { echo "Project directory not found: $dir" >&2; exit 1; }

    load_config

    local files=() f
    while IFS= read -r f; do files+=("$f"); done < <(set +f; ls -t "$dir"/*.jsonl 2>/dev/null)

    local count=${#files[@]}
    if [ "$count" -eq 0 ]; then
        echo "No sessions found in $dir." >&2
        exit 1
    fi

    local current_index=-1 i
    for i in "${!files[@]}"; do
        [ "${files[$i]}" = "$PINNED_SESSION" ] && current_index=$i
    done

    local next_index=$(( (current_index + 1) % count ))
    local chosen="${files[$next_index]}"
    set_config_key "PINNED_SESSION" "$chosen"
    echo "Pinned the status line to: $(basename "$chosen" .jsonl)  ($((next_index + 1))/$count)"
}

cmd_status() {
    load_config
    if [ "$ENABLED" != "1" ]; then
        echo "Status: disabled"
    else
        echo "Status: enabled"
    fi
    cmd_config --show
}

# Detect any existing statusLine command and chain with it instead of
# clobbering it, so this coexists with other status line tools (e.g.
# ClaudeCodeStatusLine or any other command-based statusLine).
cmd_install() {
    local settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
    while [ $# -gt 0 ]; do
        case "$1" in
            --settings) settings_file="$2"; shift 2 ;;
            *) echo "Unknown flag: $1" >&2; exit 1 ;;
        esac
    done

    command -v jq >/dev/null 2>&1 || { echo "jq is required for 'install'." >&2; exit 1; }

    mkdir -p "$(dirname "$settings_file")"
    [ -f "$settings_file" ] || echo '{}' > "$settings_file"

    local existing_cmd this_cmd
    existing_cmd=$(jq -r '.statusLine.command // empty' "$settings_file")
    this_cmd="$SCRIPT_DIR/planprogress.sh"

    cp "$settings_file" "$settings_file.bak.$(date +%s)"

    if [ -z "$existing_cmd" ] || [[ "$existing_cmd" == *"planprogress.sh"* ]] || [[ "$existing_cmd" == *"combined-statusline.sh"* && ! -s "$SCRIPT_DIR/combined-statusline.sh" ]]; then
        jq --arg cmd "$this_cmd" '.statusLine = {type:"command", command:$cmd}' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"
        echo "Installed as the sole status line in $settings_file"
        return
    fi

    local wrapper="$SCRIPT_DIR/combined-statusline.sh"
    cat > "$wrapper" <<WRAPPER_EOF
#!/bin/bash
# Auto-generated by planprogress.sh install - chains the previous status
# line command with the plan-progress segment. Safe to regenerate by
# re-running 'planprogress.sh install'.
input=\$(cat)
line1=\$(printf '%s' "\$input" | $existing_cmd)
line2=\$(printf '%s' "\$input" | "$this_cmd")
if [ -n "\$line2" ]; then
    printf '%s\n%s' "\$line1" "\$line2"
else
    printf '%s' "\$line1"
fi
WRAPPER_EOF
    chmod +x "$wrapper"

    jq --arg cmd "$wrapper" '.statusLine = {type:"command", command:$cmd}' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"
    echo "Found existing status line command: $existing_cmd"
    echo "Chained it with plan-progress into: $wrapper"
    echo "Updated $settings_file (backup saved alongside it)."
}

# ===== Status line render mode (invoked by Claude Code, no args, JSON on stdin) =====
render() {
    local input model_name transcript_path
    input=$(cat)

    if [ -z "$input" ]; then
        printf "Claude"
        exit 0
    fi

    command -v jq >/dev/null 2>&1 || { printf "Claude (jq missing)"; exit 0; }

    load_config

    if [ "$ENABLED" != "1" ]; then
        # Disabled: print nothing so a chaining wrapper can skip this segment cleanly.
        exit 0
    fi

    model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
    transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

    if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
        printf "%s" "$model_name"
        exit 0
    fi

    local todos_json source_path other_session=0 pinned_marker=0

    if [ -n "$PINNED_SESSION" ] && [ -f "$PINNED_SESSION" ]; then
        todos_json=$(extract_todos "$PINNED_SESSION")
        source_path="$PINNED_SESSION"
        [ "$PINNED_SESSION" != "$transcript_path" ] && pinned_marker=1
    else
        todos_json=$(extract_todos "$transcript_path")
        source_path="$transcript_path"

        if { [ -z "$todos_json" ] || [ "$todos_json" = "null" ]; } && [ "$CROSS_SESSION" = "1" ]; then
            local found
            found=$(find_other_active_plan "$transcript_path")
            if [ -n "$found" ]; then
                source_path="${found%%$'\t'*}"
                todos_json="${found#*$'\t'}"
                other_session=1
            fi
        fi
    fi

    if [ -z "$todos_json" ] || [ "$todos_json" = "null" ]; then
        local none_label="$LABEL_NONE"
        todowrite_disabled "$transcript_path" && none_label="$LABEL_TODOWRITE_DISABLED"
        printf "%s | %s" "$model_name" "$(colorize "$none_label" "dim")"
        exit 0
    fi

    local total completed current_title current_index pct
    total=$(echo "$todos_json" | jq 'length')
    if [ "$total" -eq 0 ] 2>/dev/null; then
        printf "%s" "$model_name"
        exit 0
    fi

    completed=$(echo "$todos_json" | jq '[.[] | select(.status == "completed")] | length')
    current_title=$(echo "$todos_json" | jq -r '(.[] | select(.status == "in_progress") | (.activeForm // .content)) // empty' | head -1)
    current_index=$((completed + 1))

    if [ -z "$current_title" ]; then
        if [ "$completed" -ge "$total" ] 2>/dev/null; then
            current_title="$LABEL_DONE"
            current_index=$total
        else
            current_title=$(echo "$todos_json" | jq -r '(.[] | select(.status == "pending") | .content) // empty' | head -1)
            # completed < total but neither an in_progress nor a pending task
            # was found: don't claim the plan is done, that would be wrong.
            [ -z "$current_title" ] && current_title="$LABEL_WORKING"
        fi
    fi

    pct=$(( total > 0 ? completed * 100 / total : 0 ))

    local filled empty bar i
    filled=$(( BAR_WIDTH * completed / total ))
    [ "$filled" -gt "$BAR_WIDTH" ] && filled=$BAR_WIDTH
    empty=$((BAR_WIDTH - filled))
    bar=""
    for ((i = 0; i < filled; i++)); do bar="${bar}${FILLED_CHAR}"; done
    for ((i = 0; i < empty; i++)); do bar="${bar}${EMPTY_CHAR}"; done

    local color_name
    if [ "$COLOR_MODE" = "auto" ]; then
        if [ "$pct" -ge 100 ]; then color_name="green"
        elif [ "$pct" -ge 50 ]; then color_name="cyan"
        else color_name="yellow"
        fi
    else
        color_name="$COLOR_MODE"
    fi

    local emoji=""
    [ "$NO_EMOJI" != "1" ] && emoji="📋 "

    local pct_str bar_str
    pct_str=$(colorize "${pct}%" "$color_name")
    bar_str=$(colorize "$bar" "$color_name")

    local output
    output=$(printf "%s | %s%s %d/%d - %s (%s) %s" \
        "$model_name" "$emoji" "$LABEL_TASK" "$current_index" "$total" "$current_title" "$pct_str" "$bar_str")

    if [ "$SHOW_TITLE" = "1" ]; then
        local plan_title
        plan_title=$(get_plan_title "$source_path")
        [ -n "$plan_title" ] && output="$output - $plan_title"
    fi

    if [ "$pinned_marker" = "1" ]; then
        output="$output $(colorize "($LABEL_PINNED)" "dim")"
    elif [ "$other_session" = "1" ]; then
        output="$output $(colorize "($LABEL_OTHER_SESSION)" "dim")"
    fi

    printf "%s" "$output"
}

# Grabs the todos array from the most recent TodoWrite call in a transcript file.
extract_todos() {
    # Two defenses against a rejected TodoWrite call (e.g. the tool disabled
    # for this session) polluting the reading:
    #  - exclude any TodoWrite tool_use whose matching tool_result came back
    #    as an error (its `.input.todos` may look perfectly valid but was
    #    never actually applied - showing it would be stale/misleading);
    #  - `select(type == "array")` as a second guard for the case where the
    #    rejected call's .input.todos wasn't even parsed into an array (e.g.
    #    logged as a raw JSON string) - without it, jq's `length`/`.[]` on
    #    that value silently misbehaves (string length instead of item
    #    count) instead of erroring, producing a bogus progress readout.
    # Requires slurping the file (-s) to correlate tool_use/tool_result
    # pairs by id across lines.
    jq -c -s '
        ( [.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result" and .is_error == true) | .tool_use_id] ) as $rejected |
        [
            .[] |
            select(.type == "assistant") |
            .message.content[]? |
            select(.type == "tool_use" and .name == "TodoWrite") |
            select(.id as $tid | ($rejected | index($tid)) == null) |
            .input.todos |
            select(type == "array")
        ] | last
    ' "$1" 2>/dev/null
}

# Detects a genuinely rejected TodoWrite call (the tool disabled for this
# session/account) so "no plan" can be reported accurately instead of
# implying Claude simply hasn't tracked one yet. Scoped to actual
# tool_result blocks (is_error + the exact rejection text) rather than a
# plain text search, so a chat message merely mentioning this error
# doesn't produce a false positive.
todowrite_disabled() {
    jq -e '
        select(.type == "user") |
        .message.content[]? |
        select(.type == "tool_result" and .is_error == true) |
        select(.content | type == "string" and test("TodoWrite is disabled"))
    ' "$1" >/dev/null 2>&1
}

# Sessions in the same project (same cwd) write their transcripts into the
# same directory as this session's transcript_path. When THIS session has no
# plan of its own, check sibling transcripts (most recently modified first,
# capped so a busy project doesn't slow the status line down) for one with
# an incomplete TodoWrite list - e.g. a plan running in another open tab.
find_other_active_plan() {
    local current="$1" dir other t tot comp checked=0
    dir=$(dirname "$current")

    while IFS= read -r other; do
        [ "$other" = "$current" ] && continue
        checked=$((checked + 1))
        [ "$checked" -gt 5 ] && break

        # Skip sessions that haven't been touched recently - an old,
        # abandoned plan shouldn't get picked up and look "frozen" forever.
        if [ -n "$(find "$other" -mmin +"$CROSS_SESSION_MAX_AGE_MIN" 2>/dev/null)" ]; then
            continue
        fi

        t=$(extract_todos "$other")
        [ -z "$t" ] || [ "$t" = "null" ] && continue
        tot=$(echo "$t" | jq 'length')
        [ "$tot" -eq 0 ] 2>/dev/null && continue
        comp=$(echo "$t" | jq '[.[] | select(.status == "completed")] | length')
        if [ "$comp" -lt "$tot" ] 2>/dev/null; then
            printf '%s\t%s' "$other" "$t"
            return
        fi
    done < <(set +f; ls -t "$dir"/*.jsonl 2>/dev/null)
}

# Pulls a short name for the plan currently being implemented out of the
# most recent ExitPlanMode call (the tool used when a plan is presented for
# approval) - its `plan` input is the markdown plan text; we take the first
# non-blank line (usually the heading) as the title.
get_plan_title() {
    local transcript_path="$1" raw line
    # jq -c (not -r) keeps each matched plan as one escaped-JSON-string line
    # (embedded newlines become literal \n) so `tail -1` grabs the *last
    # whole record* instead of just the last physical line of plan text.
    raw=$(jq -c '
        select(.type == "assistant") |
        .message.content[]? |
        select(.type == "tool_use" and .name == "ExitPlanMode") |
        .input.plan
    ' "$transcript_path" 2>/dev/null | tail -1 | jq -r '.' 2>/dev/null)

    [ -z "$raw" ] && return

    line=$(printf '%s' "$raw" | awk 'NF{print; exit}')
    line=$(printf '%s' "$line" | sed -E 's/^[#\*[:space:]]+//; s/[[:space:]]+$//')

    if [ "${#line}" -gt "$TITLE_MAX_LEN" ]; then
        line="${line:0:$TITLE_MAX_LEN}…"
    fi

    printf '%s' "$line"
}

colorize() {
    local text="$1" name="$2" code
    code=$(palette_code "$name")
    if [ "${PLAN_PROGRESS_NO_COLOR:-0}" = "1" ] || [ "$name" = "none" ] || [ -z "$code" ]; then
        printf "%s" "$text"
    else
        printf "%b%s%b" "$code" "$text" "$reset"
    fi
}

# ===== Entry point (skipped when the script is sourced, e.g. for testing) =====
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        enable) cmd_enable ;;
        disable) cmd_disable ;;
        status) cmd_status ;;
        config) shift; cmd_config "$@" ;;
        install) shift; cmd_install "$@" ;;
        sessions) shift; cmd_sessions "$@" ;;
        use) shift; cmd_use "$@" ;;
        unpin) cmd_unpin ;;
        next) shift; cmd_next "$@" ;;
        "") render ;;
        *) echo "Unknown command: $1. Try: enable, disable, status, config, install, sessions, use, next, unpin" >&2; exit 1 ;;
    esac
fi
