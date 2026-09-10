# Installation

This document is the authoritative install guide. It is written to be executed step-by-step by Claude Code when a user asks to install or update this status line.

## 1. Detect the operating system

- **macOS or Linux** → use `planprogress.sh`
- **Windows** (PowerShell, CMD, Git Bash, or WSL) → use `planprogress.ps1`

## 2. Clone the repo

Clone to `~/.claude/plan-progress/` on Unix, or `%USERPROFILE%\.claude\plan-progress\` on Windows. If that directory already exists and is a git clone of this repo, run `git pull` in it instead of re-cloning.

**macOS / Linux**

```bash
git clone https://github.com/GabrielTalmaV/claude-code-plan-progress ~/.claude/plan-progress
chmod +x ~/.claude/plan-progress/planprogress.sh
```

**Windows (PowerShell)**

```powershell
git clone https://github.com/GabrielTalmaV/claude-code-plan-progress "$env:USERPROFILE\.claude\plan-progress"
```

## 3. Configure `settings.json`

Preferred: let the script do it. It auto-detects any `statusLine` already configured and chains with it instead of overwriting it (see README.md's "Coexisting with another status line" section), and it backs up `settings.json` first.

**macOS / Linux**

```bash
~/.claude/plan-progress/planprogress.sh install
```

**Windows (PowerShell)**

```powershell
pwsh ~/.claude/plan-progress/planprogress.ps1 install
```

If `pwsh` (PowerShell 7+) is not installed, use `powershell` instead.

### Manual alternative

If you'd rather edit `settings.json` yourself: add (or merge into) the `statusLine` key in `~/.claude/settings.json` (Unix) or `%USERPROFILE%\.claude\settings.json` (Windows).

**macOS / Linux**

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/plan-progress/planprogress.sh"
  }
}
```

**Windows**

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -ExecutionPolicy Bypass -File ~/.claude/plan-progress/planprogress.ps1"
  }
}
```

If PowerShell 7+ (`pwsh`) is not installed, fall back to Windows PowerShell 5.1:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/plan-progress/planprogress.ps1"
  }
}
```

> `-ExecutionPolicy Bypass` is **process-scoped** - it does not change your machine's PowerShell policy. Without it, a default `Restricted` or `AllSigned` policy (common on locked-down corporate machines) silently rejects the unsigned script and Claude Code shows no status line with no error.
>
> `~` is expanded by Claude Code v2.1.47+ on both Unix and Windows. On older Claude Code versions, replace `~/.claude/plan-progress/planprogress.ps1` with `%USERPROFILE%\.claude\plan-progress\planprogress.ps1` (CMD / PowerShell) or `$USERPROFILE\.claude\plan-progress\planprogress.ps1` (Git Bash / WSL) - `%VAR%` expands only in CMD/PowerShell, `$VAR` only in bash shells.

## 4. Restart Claude Code

The status line is loaded at startup. After saving `settings.json`, tell the user to restart Claude Code (or start a new session) for the change to take effect.

## Try it out

1. Ask Claude for a plan for some task and approve it.
2. As Claude works through the plan (using `TodoWrite` to track steps, which it does automatically), the status line should update to show `Task N/M - <current step> (X%)`.
3. If nothing changes, confirm the current session actually produced a `TodoWrite` call - simple one-shot requests that don't need a task list won't show progress.

## Updating

```bash
git -C ~/.claude/plan-progress pull
```

No `settings.json` changes are needed - the command path is stable across versions.

## Uninstalling

1. Remove the `statusLine` block from `settings.json` (or restore your previous one).
2. Delete the clone: `rm -rf ~/.claude/plan-progress` (or the Windows equivalent).

## Requirements

- Claude Code
- macOS / Linux: `jq` in `PATH`
- Windows: PowerShell 5.1+ (default on Windows 10/11)

If `jq` is missing on macOS/Linux, install it with the system package manager (`brew install jq`, `apt install jq`, etc.).
