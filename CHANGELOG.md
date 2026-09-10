# Changelog

## 1.3.1

- Fix: a TodoWrite call rejected by the backend (the tool disabled for a session/account) could still log a well-formed `.input.todos` array even though it was never actually applied - it's now excluded by correlating each TodoWrite call with its tool_result and skipping rejected ones, instead of only checking whether the value happened to parse as an array.
- When no plan is found because of exactly this (TodoWrite disabled), the status line now says "TodoWrite disabled for this session" / "TodoWrite deshabilitada en esta sesión" instead of the generic "No active plan" - detected precisely from a matching `tool_result` error, so a chat message that merely mentions the phrase doesn't trigger a false positive.

## 1.3.0

- Fix: a rejected/malformed `TodoWrite` call could log `.input.todos` as a raw JSON string instead of an array; the script now validates it's actually an array before reading it, instead of silently misinterpreting the string's character count as a task count (which showed a bogus, frozen-looking "Task 1/291 - Plan complete" readout).
- Fix: when neither an `in_progress` nor a `pending` task can be found but the plan isn't actually complete, stop misleadingly showing "Plan complete" - show a neutral "in progress"/"en curso" label instead.
- The cross-session fallback now ignores sessions that haven't been touched in the last 3 hours by default (`config --cross-session-max-age <minutes>`), so an old abandoned plan can't get picked up and look permanently stuck.
- Add `next`, which cycles the pinned session forward through a project's sessions - quicker than looking up a number with `sessions` every time you want to check a different plan.

## 1.2.0

- Append a short plan name to the status line, taken from the first heading of the most recent approved plan (`ExitPlanMode` call). Configurable with `config --title` / `--no-title` / `--title-max-len`.
- Add a cross-session fallback: when the current session has no plan of its own, show the most recently active plan from another session in the same project, tagged `(other session)`. Toggle with `config --cross-session` / `--no-cross-session`.
- Add `sessions` (list every plan across a project's sessions with progress), `use <n>` (pin the status line to one of them), and `unpin`, so multiple concurrent plans can be inspected and switched between.

## 1.0.0

- Initial release: renders `Task N/M - title (X%) [bar]` by reading the latest `TodoWrite` call from the session transcript Claude Code passes via `transcript_path`.
- Ships for bash (macOS/Linux) and PowerShell (Windows).
- Self-contained CLI: `enable`, `disable`, `status`, `config` (width, color, bar characters, emoji, locale).
- `install` command that detects any status line already configured and chains with it (via a generated wrapper) instead of overwriting it.
