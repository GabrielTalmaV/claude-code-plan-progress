# Claude Code Plan Progress

A status line for [Claude Code](https://claude.com/claude-code) that shows how far along Claude is on the plan it's currently implementing:

```
Sonnet 5 | 📋 Task 3/5 - Implementing UI (60%) ██████░░░░ - Empresas feature
```

**Ask Claude Code:**

> Clone https://github.com/GabrielTalmaV/claude-code-plan-progress to ~/.claude/plan-progress/ (or `%USERPROFILE%\.claude\plan-progress\` on Windows) and set it up as my status bar by following its INSTALL.md.

Claude will clone the repo to that path, pick the right script for your OS, and run its `install` command - which detects any status line you already have configured and chains with it instead of overwriting it (see [Coexisting with another status line](#coexisting-with-another-status-line)). Full step-by-step instructions Claude follows live in [INSTALL.md](INSTALL.md).

Restart Claude Code after Claude saves the configuration.

## How it works

Claude Code already tracks the steps of a plan internally via its `TodoWrite` tool - the same task list rendered in the CLI UI while Claude works. The status line command receives a JSON payload on stdin that includes `transcript_path`, the path to the session's JSONL transcript. This script reads that transcript, finds the most recent `TodoWrite` call, and renders it as a progress bar. The plan's name comes from the most recent `ExitPlanMode` call (the plan-approval step) - its first heading line.

No separate progress file, no extra instructions to add to `CLAUDE.md` - it reads state Claude Code already maintains. Ask Claude for a plan, approve it, and watch the status line update as each task flips from `pending` → `in_progress` → `completed`.

## Install

See [INSTALL.md](INSTALL.md). The installer (`planprogress.sh install`, or `planprogress.ps1 install` on Windows) automatically detects and coexists with any status line you already have configured - see [Coexisting with another status line](#coexisting-with-another-status-line) below.

## Enabling / disabling the bar

The script doubles as its own CLI (run it directly from a terminal, with arguments - Claude Code itself always calls it with no arguments):

```bash
# macOS / Linux
~/.claude/plan-progress/planprogress.sh disable   # hides the segment (prints nothing) without touching settings.json
~/.claude/plan-progress/planprogress.sh enable    # turns it back on
~/.claude/plan-progress/planprogress.sh status    # shows enabled/disabled + current config
```

```powershell
# Windows
pwsh ~/.claude/plan-progress/planprogress.ps1 disable
pwsh ~/.claude/plan-progress/planprogress.ps1 enable
pwsh ~/.claude/plan-progress/planprogress.ps1 status
```

## Editing the bar's appearance (color, width, characters)

Same CLI, `config` subcommand. Settings persist to a small `config` file next to the script (`~/.claude/plan-progress/config`), so you only need to run this once:

```bash
# macOS / Linux
~/.claude/plan-progress/planprogress.sh config --width 20 --color purple --filled-char "=" --empty-char "-"
~/.claude/plan-progress/planprogress.sh config --no-emoji     # drop the 📋
~/.claude/plan-progress/planprogress.sh config --locale es    # force Spanish labels ("Tarea", "Plan completo"...)
~/.claude/plan-progress/planprogress.sh config --show         # print current settings
~/.claude/plan-progress/planprogress.sh config --reset        # back to defaults
```

```powershell
# Windows
pwsh ~/.claude/plan-progress/planprogress.ps1 config -Width 20 -Color purple -FilledChar "=" -EmptyChar "-"
pwsh ~/.claude/plan-progress/planprogress.ps1 config -NoEmoji
pwsh ~/.claude/plan-progress/planprogress.ps1 config -Locale es
pwsh ~/.claude/plan-progress/planprogress.ps1 config -Show
pwsh ~/.claude/plan-progress/planprogress.ps1 config -Reset
```

`--color` (or `-Color`) accepts `auto` (default - green at 100%, cyan mid-progress, yellow early) or a fixed name: `red`, `green`, `yellow`, `blue`, `cyan`, `purple`, `orange`, `white`, `dim`, `none`.

Every setting can also be overridden per-invocation with an environment variable (handy for scripting, or if you'd rather not persist anything to disk): `PLAN_PROGRESS_BAR_WIDTH`, `PLAN_PROGRESS_COLOR`, `PLAN_PROGRESS_FILLED_CHAR`, `PLAN_PROGRESS_EMPTY_CHAR`, `PLAN_PROGRESS_NO_EMOJI`, `PLAN_PROGRESS_NO_COLOR`, `PLAN_PROGRESS_ENABLED`, `PLAN_PROGRESS_LOCALE`, `PLAN_PROGRESS_SHOW_TITLE`, `PLAN_PROGRESS_TITLE_MAX_LEN`, `PLAN_PROGRESS_CROSS_SESSION`, `PLAN_PROGRESS_CROSS_SESSION_MAX_AGE_MIN`, `PLAN_PROGRESS_PINNED_SESSION`. Env vars always win over the config file.

## The plan name

By default the segment ends with a short name for the plan, taken from the first heading of the most recent approved plan (the `ExitPlanMode` call). Turn it off or change how much of it shows:

```bash
~/.claude/plan-progress/planprogress.sh config --no-title           # drop the plan name entirely
~/.claude/plan-progress/planprogress.sh config --title-max-len 25   # shorter/longer before truncating with "…"
```

```powershell
pwsh ~/.claude/plan-progress/planprogress.ps1 config -NoTitle
pwsh ~/.claude/plan-progress/planprogress.ps1 config -TitleMaxLen 25
```

If Claude implemented a plan without ever presenting one for approval (skip-permissions / non-plan-mode flows), there's no `ExitPlanMode` call to read a name from, so the segment just omits the trailing name.

## Multiple plans across sessions

Each Claude Code session (tab/window) has its own transcript, so by default the status line only knows about **its own** session's plan. Two things build on top of that:

**Automatic fallback.** If the current session has no plan of its own, the script looks at other sessions in the same project (same working directory) modified within the last 3 hours by default and shows the most recently active one with an incomplete plan, tagged `(other session)` / `(otra sesión)` so it's clear it's not this tab's own work. The time window keeps an old, abandoned plan from getting picked up and looking permanently "stuck" - tune it with `config --cross-session-max-age <minutes>` (`-CrossSessionMaxAge` on Windows), or turn the whole fallback off with `--no-cross-session` / `-NoCrossSession` if you'd rather just see "No active plan".

**Picking a specific plan.** When several sessions in a project have plans running at once, list them and pin the status line to whichever one you want to watch:

```bash
~/.claude/plan-progress/planprogress.sh sessions        # list every session's plan + progress
~/.claude/plan-progress/planprogress.sh use 2           # pin the status line to session #2
~/.claude/plan-progress/planprogress.sh next            # cycle the pin to the next session
~/.claude/plan-progress/planprogress.sh unpin           # back to automatic behavior
```

```powershell
pwsh ~/.claude/plan-progress/planprogress.ps1 sessions
pwsh ~/.claude/plan-progress/planprogress.ps1 use 2
pwsh ~/.claude/plan-progress/planprogress.ps1 next
pwsh ~/.claude/plan-progress/planprogress.ps1 unpin
```

`next` is the quickest way to flip through plans without looking up numbers first - each call pins the following session in the list (most recently modified first), wrapping back to the top after the last one.

A pinned session shows `(pinned)` / `(fijado)` in the status line as a reminder it isn't following the current tab. `sessions`/`use`/`next` guess the project's transcript folder from your current directory; pass `--dir <path>` (`-Dir` on Windows) to point at it directly if that guess is off (project folders live under `~/.claude/projects/`).

## Coexisting with another status line

This is a common case - you may already have a status line for context/token/git info (e.g. [ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine)) and just want to add plan progress as an extra line, not replace it.

Run the installer and it figures this out for you:

```bash
~/.claude/plan-progress/planprogress.sh install
```

- If `settings.json` has no `statusLine` configured yet, it's installed directly.
- If a different `statusLine.command` is already configured, the installer leaves it untouched, generates `combined-statusline.sh` next to this script that calls **both** commands and joins their output with a newline (skipping the plan-progress line entirely when there's no active plan or it's disabled), and points `statusLine.command` at that wrapper instead. Your original command keeps running exactly as before, on its own line.
- `settings.json` is backed up (`settings.json.bak.<timestamp>`) before it's touched.

Re-run `install` any time (e.g. after changing your other status line's command) to regenerate the wrapper. On Windows, use `pwsh ~/.claude/plan-progress/planprogress.ps1 install` - it works the same way with a `combined-statusline.ps1`.

Claude Code renders multi-line status lines natively - each `\n`-separated line is its own row.

## What it shows when there's no active plan

If Claude hasn't called `TodoWrite` yet in the session, the status line falls back to just the model name plus a "No active plan" / "Sin plan activo" hint, so it's never blank or broken.

## Requirements

- Claude Code
- macOS / Linux: `jq` in `PATH` (`brew install jq` / `apt install jq`)
- Windows: PowerShell 5.1+ (default on Windows 10/11)

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

MIT
