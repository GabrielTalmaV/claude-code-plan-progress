# Claude Code Plan Progress

A status line for [Claude Code](https://claude.com/claude-code) that shows how far along Claude is on the plan it's currently implementing:

```
Sonnet 5 | 📋 Task 3/5 - Implementing UI (60%) ██████░░░░
```

## How it works

Claude Code already tracks the steps of a plan internally via its `TodoWrite` tool - the same task list rendered in the CLI UI while Claude works. The status line command receives a JSON payload on stdin that includes `transcript_path`, the path to the session's JSONL transcript. This script reads that transcript, finds the most recent `TodoWrite` call, and renders it as a progress bar.

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

Every setting can also be overridden per-invocation with an environment variable (handy for scripting, or if you'd rather not persist anything to disk): `PLAN_PROGRESS_BAR_WIDTH`, `PLAN_PROGRESS_COLOR`, `PLAN_PROGRESS_FILLED_CHAR`, `PLAN_PROGRESS_EMPTY_CHAR`, `PLAN_PROGRESS_NO_EMOJI`, `PLAN_PROGRESS_NO_COLOR`, `PLAN_PROGRESS_ENABLED`, `PLAN_PROGRESS_LOCALE`. Env vars always win over the config file.

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

## License

MIT
