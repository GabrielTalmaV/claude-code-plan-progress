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
# as "Task 3/5 - title (60%) [bar]". No separate progress-state file needed.
#
# CLI usage (run this script directly, with arguments, from a terminal):
#   planprogress.sh enable
#   planprogress.sh disable
#   planprogress.sh status
#   planprogress.sh config --width 20 --color cyan --filled-char "=" --empty-char "-"
#   planprogress.sh config --show
#   planprogress.sh config --reset
#   planprogress.sh install [--settings <path>]

set -f  # disable globbing
VERSION="1.1.0"

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
    LOCALE="${PLAN_PROGRESS_LOCALE:-$LOCALE_CFG}"

    if [ -z "$LOCALE" ]; then
        case "${LANG:-}${LC_ALL:-}" in
            es*) LOCALE="es" ;;
            *) LOCALE="en" ;;
        esac
    fi

    if [ "$LOCALE" = "es" ]; then
        LABEL_TASK="Tarea"; LABEL_DONE="Plan completo"; LABEL_NONE="Sin plan activo"
    else
        LABEL_TASK="Task"; LABEL_DONE="Plan complete"; LABEL_NONE="No active plan"
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
        echo "LOCALE=$LOCALE"
        echo "Config file: $CONFIG_FILE"
    fi
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

    local todos_json
    todos_json=$(jq -c '
        select(.type == "assistant") |
        .message.content[]? |
        select(.type == "tool_use" and .name == "TodoWrite") |
        .input.todos
    ' "$transcript_path" 2>/dev/null | tail -1)

    if [ -z "$todos_json" ] || [ "$todos_json" = "null" ]; then
        printf "%s | %s" "$model_name" "$(colorize "$LABEL_NONE" "dim")"
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
            [ -z "$current_title" ] && current_title="$LABEL_DONE"
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

    printf "%s | %s%s %d/%d - %s (%s) %s" \
        "$model_name" "$emoji" "$LABEL_TASK" "$current_index" "$total" "$current_title" "$pct_str" "$bar_str"
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

# ===== Entry point =====
case "${1:-}" in
    enable) cmd_enable ;;
    disable) cmd_disable ;;
    status) cmd_status ;;
    config) shift; cmd_config "$@" ;;
    install) shift; cmd_install "$@" ;;
    "") render ;;
    *) echo "Unknown command: $1. Try: enable, disable, status, config, install" >&2; exit 1 ;;
esac
