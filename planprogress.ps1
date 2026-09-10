# Source: https://github.com/GabrielTalmaV/claude-code-plan-progress
# Renders plan-implementation progress as a Claude Code statusLine segment,
# and doubles as a CLI to configure/enable/disable/install itself.
#
# See planprogress.sh for how rendering works (reads the latest TodoWrite
# call from the session transcript referenced by stdin's transcript_path;
# the plan title comes from the most recent ExitPlanMode call's heading).
#
# CLI usage:
#   planprogress.ps1 enable
#   planprogress.ps1 disable
#   planprogress.ps1 status
#   planprogress.ps1 config -Width 20 -Color cyan -FilledChar "=" -EmptyChar "-"
#   planprogress.ps1 config -NoTitle -TitleMaxLen 30
#   planprogress.ps1 config -Show
#   planprogress.ps1 config -Reset
#   planprogress.ps1 install [-Settings <path>]
#   planprogress.ps1 sessions          # list every plan in this project's sessions
#   planprogress.ps1 use <number>      # pin the status line to one of them
#   planprogress.ps1 next              # cycle the pin to the next session
#   planprogress.ps1 unpin             # back to automatic

param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(Position = 1)]
    [string]$Arg,
    [int]$Width,
    [string]$Color,
    [string]$FilledChar,
    [string]$EmptyChar,
    [string]$Locale,
    [switch]$Emoji,
    [switch]$NoEmoji,
    [switch]$Title,
    [switch]$NoTitle,
    [int]$TitleMaxLen,
    [switch]$CrossSession,
    [switch]$NoCrossSession,
    [int]$CrossSessionMaxAge,
    [switch]$Show,
    [switch]$Reset,
    [string]$Settings,
    [string]$Dir,
    [string]$Cwd
)

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config"

function Load-Config {
    $cfg = @{
        ENABLED     = "1"
        BAR_WIDTH   = "10"
        COLOR_MODE  = "auto"
        FILLED_CHAR = "█"
        EMPTY_CHAR  = "░"
        NO_EMOJI    = "0"
        SHOW_TITLE    = "1"
        TITLE_MAX_LEN = "40"
        CROSS_SESSION = "1"
        CROSS_SESSION_MAX_AGE_MIN = "180"
        PINNED_SESSION = ""
        LOCALE_CFG  = ""
    }
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile | ForEach-Object {
            if ($_ -match "^([A-Z_]+)=(.*)$") {
                $cfg[$matches[1]] = $matches[2]
            }
        }
    }
    if ($env:PLAN_PROGRESS_BAR_WIDTH) { $cfg.BAR_WIDTH = $env:PLAN_PROGRESS_BAR_WIDTH }
    if ($env:PLAN_PROGRESS_COLOR) { $cfg.COLOR_MODE = $env:PLAN_PROGRESS_COLOR }
    if ($env:PLAN_PROGRESS_FILLED_CHAR) { $cfg.FILLED_CHAR = $env:PLAN_PROGRESS_FILLED_CHAR }
    if ($env:PLAN_PROGRESS_EMPTY_CHAR) { $cfg.EMPTY_CHAR = $env:PLAN_PROGRESS_EMPTY_CHAR }
    if ($env:PLAN_PROGRESS_NO_EMOJI) { $cfg.NO_EMOJI = $env:PLAN_PROGRESS_NO_EMOJI }
    if ($env:PLAN_PROGRESS_ENABLED) { $cfg.ENABLED = $env:PLAN_PROGRESS_ENABLED }
    if ($env:PLAN_PROGRESS_LOCALE) { $cfg.LOCALE_CFG = $env:PLAN_PROGRESS_LOCALE }
    if ($env:PLAN_PROGRESS_SHOW_TITLE) { $cfg.SHOW_TITLE = $env:PLAN_PROGRESS_SHOW_TITLE }
    if ($env:PLAN_PROGRESS_TITLE_MAX_LEN) { $cfg.TITLE_MAX_LEN = $env:PLAN_PROGRESS_TITLE_MAX_LEN }
    if ($env:PLAN_PROGRESS_CROSS_SESSION) { $cfg.CROSS_SESSION = $env:PLAN_PROGRESS_CROSS_SESSION }
    if ($env:PLAN_PROGRESS_CROSS_SESSION_MAX_AGE_MIN) { $cfg.CROSS_SESSION_MAX_AGE_MIN = $env:PLAN_PROGRESS_CROSS_SESSION_MAX_AGE_MIN }
    if ($env:PLAN_PROGRESS_PINNED_SESSION) { $cfg.PINNED_SESSION = $env:PLAN_PROGRESS_PINNED_SESSION }

    $loc = $cfg.LOCALE_CFG
    if (-not $loc) {
        $loc = if (($env:LANG -like "es*") -or ($env:LC_ALL -like "es*")) { "es" } else { "en" }
    }
    $cfg.LOCALE = $loc
    return $cfg
}

function Get-ColorCode($name) {
    $esc = [char]27
    switch ($name) {
        "red"    { return "$esc[38;2;255;85;85m" }
        "green"  { return "$esc[38;2;0;160;0m" }
        "yellow" { return "$esc[38;2;230;200;0m" }
        "blue"   { return "$esc[38;2;0;153;255m" }
        "cyan"   { return "$esc[38;2;46;149;153m" }
        "purple" { return "$esc[38;2;167;139;250m" }
        "orange" { return "$esc[38;2;255;176;85m" }
        "white"  { return "$esc[38;2;220;220;220m" }
        "dim"    { return "$esc[2m" }
        default  { return "" }
    }
}

function Colorize($text, $name) {
    if ($env:PLAN_PROGRESS_NO_COLOR -eq "1" -or $name -eq "none") { return $text }
    $code = Get-ColorCode $name
    if (-not $code) { return $text }
    $esc = [char]27
    return "$code$text$esc[0m"
}

function Get-TodosFromTranscript($path) {
    # Two passes: first collect ids of any tool_result that came back as an
    # error (e.g. TodoWrite disabled for this session), then read TodoWrite
    # calls - skipping ones whose call was rejected (even if its
    # .input.todos looks like a valid array, it was never actually applied)
    # and ones whose .input.todos wasn't parsed into an array at all.
    $rejectedIds = New-Object System.Collections.Generic.HashSet[string]
    $lines = Get-Content -LiteralPath $path -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ($entry.type -ne "user") { continue }
        foreach ($block in $entry.message.content) {
            if ($block.type -eq "tool_result" -and $block.is_error -eq $true) {
                [void]$rejectedIds.Add($block.tool_use_id)
            }
        }
    }

    $todos = $null
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ($entry.type -ne "assistant") { continue }
        foreach ($block in $entry.message.content) {
            if ($block.type -eq "tool_use" -and $block.name -eq "TodoWrite") {
                if ($rejectedIds.Contains($block.id)) { continue }
                if ($block.input.todos -is [array]) { $todos = $block.input.todos }
            }
        }
    }
    return $todos
}

# Detects a genuinely rejected TodoWrite call (the tool disabled for this
# session/account) so "no plan" can be reported accurately. Scoped to
# actual tool_result blocks (is_error + the exact rejection text) rather
# than a plain text search, so a chat message merely mentioning this error
# doesn't produce a false positive.
function Test-TodoWriteDisabled($path) {
    Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return }
        try { $entry = $_ | ConvertFrom-Json } catch { return }
        if ($entry.type -ne "user") { return }
        foreach ($block in $entry.message.content) {
            if ($block.type -eq "tool_result" -and $block.is_error -eq $true -and $block.content -is [string] -and $block.content -match "TodoWrite is disabled") {
                return $true
            }
        }
    } | Where-Object { $_ -eq $true } | Select-Object -First 1
}

# Pulls a short name for the plan out of the most recent ExitPlanMode call
# (the plan-approval step) in a transcript - its first non-blank line,
# usually the markdown heading.
function Get-PlanTitle($path, [int]$maxLen) {
    $planText = $null
    Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return }
        try { $entry = $_ | ConvertFrom-Json } catch { return }
        if ($entry.type -ne "assistant") { return }
        foreach ($block in $entry.message.content) {
            if ($block.type -eq "tool_use" -and $block.name -eq "ExitPlanMode") { $planText = $block.input.plan }
        }
    }
    if (-not $planText) { return $null }
    $line = ($planText -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1)
    if (-not $line) { return $null }
    $line = $line.Trim() -replace '^[#\*\s]+', '' -replace '\s+$', ''
    if ($line.Length -gt $maxLen) { $line = $line.Substring(0, $maxLen) + "…" }
    return $line
}

# Other sessions in the same project write their transcripts into the same
# directory as this session's transcript. When this session has no plan of
# its own, check up to 5 sibling transcripts (most recently modified first)
# for one with an incomplete TodoWrite list - e.g. a plan running in
# another open tab.
function Find-OtherActivePlan($currentPath, [int]$maxAgeMinutes) {
    $dir = Split-Path -Parent $currentPath
    $cutoff = (Get-Date).AddMinutes(-$maxAgeMinutes)
    $siblings = Get-ChildItem -Path $dir -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $currentPath -and $_.LastWriteTime -ge $cutoff } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 5

    foreach ($f in $siblings) {
        $todos = Get-TodosFromTranscript $f.FullName
        if (-not $todos -or $todos.Count -eq 0) { continue }
        $completed = ($todos | Where-Object { $_.status -eq "completed" }).Count
        if ($completed -lt $todos.Count) {
            return @{ Path = $f.FullName; Todos = $todos }
        }
    }
    return $null
}

# Best-effort mirror of how Claude Code names a project's transcript folder
# under ~/.claude/projects/ (cwd with "/" or "\" replaced by "-"). Override
# with -Dir on 'sessions'/'use' if a project's real folder doesn't match.
function Resolve-ProjectDir($cwdPath) {
    $projectId = ($cwdPath -replace '[\\/]', '-')
    return Join-Path (Join-Path $env:USERPROFILE ".claude") (Join-Path "projects" $projectId)
}

function Set-ConfigKey($key, $value) {
    $lines = @()
    if (Test-Path $ConfigFile) { $lines = Get-Content $ConfigFile }
    $found = $false
    $lines = $lines | ForEach-Object {
        if ($_ -match "^$key=") { $found = $true; "$key=$value" } else { $_ }
    }
    if (-not $found) { $lines += "$key=$value" }
    $lines | Set-Content $ConfigFile
}

switch ($Command) {
    "enable" {
        Set-ConfigKey "ENABLED" "1"
        Write-Output "Plan progress bar enabled."
        return
    }
    "disable" {
        Set-ConfigKey "ENABLED" "0"
        Write-Output "Plan progress bar disabled (status line will print nothing for this segment)."
        return
    }
    "config" {
        if ($Reset) { Remove-Item -ErrorAction SilentlyContinue $ConfigFile; Write-Output "Config reset to defaults."; return }
        if ($PSBoundParameters.ContainsKey('Width')) { Set-ConfigKey "BAR_WIDTH" $Width }
        if ($Color) { Set-ConfigKey "COLOR_MODE" $Color }
        if ($FilledChar) { Set-ConfigKey "FILLED_CHAR" $FilledChar }
        if ($EmptyChar) { Set-ConfigKey "EMPTY_CHAR" $EmptyChar }
        if ($Locale) { Set-ConfigKey "LOCALE_CFG" $Locale }
        if ($Emoji) { Set-ConfigKey "NO_EMOJI" "0" }
        if ($NoEmoji) { Set-ConfigKey "NO_EMOJI" "1" }
        if ($Title) { Set-ConfigKey "SHOW_TITLE" "1" }
        if ($NoTitle) { Set-ConfigKey "SHOW_TITLE" "0" }
        if ($PSBoundParameters.ContainsKey('TitleMaxLen')) { Set-ConfigKey "TITLE_MAX_LEN" $TitleMaxLen }
        if ($CrossSession) { Set-ConfigKey "CROSS_SESSION" "1" }
        if ($NoCrossSession) { Set-ConfigKey "CROSS_SESSION" "0" }
        if ($PSBoundParameters.ContainsKey('CrossSessionMaxAge')) { Set-ConfigKey "CROSS_SESSION_MAX_AGE_MIN" $CrossSessionMaxAge }
        if ($Show) {
            $cfg = Load-Config
            $cfg.Keys | ForEach-Object { Write-Output "$_=$($cfg[$_])" }
            Write-Output "Config file: $ConfigFile"
        }
        return
    }
    "status" {
        $cfg = Load-Config
        Write-Output ("Status: " + $(if ($cfg.ENABLED -eq "1") { "enabled" } else { "disabled" }))
        $cfg.Keys | ForEach-Object { Write-Output "$_=$($cfg[$_])" }
        return
    }
    "sessions" {
        $projectDir = if ($Dir) { $Dir } else { Resolve-ProjectDir (if ($Cwd) { $Cwd } else { (Get-Location).Path }) }
        if (-not (Test-Path $projectDir)) {
            Write-Output "No Claude Code project directory found at $projectDir"
            Write-Output "Pass -Dir <path> if this guess is wrong (project folders live under ~/.claude/projects/)."
            return
        }
        $cfg = Load-Config
        Write-Output "Sessions in $projectDir`:"
        $files = Get-ChildItem -Path $projectDir -Filter "*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        $i = 0
        foreach ($f in $files) {
            $i++
            $todos = Get-TodosFromTranscript $f.FullName
            $marker = if ($f.FullName -eq $cfg.PINNED_SESSION) { " [pinned]" } else { "" }
            if (-not $todos -or $todos.Count -eq 0) {
                Write-Output "  $i) $($f.BaseName) - no plan"
                continue
            }
            $total = $todos.Count
            $completed = ($todos | Where-Object { $_.status -eq "completed" }).Count
            $title = Get-PlanTitle $f.FullName 60
            if (-not $title) { $title = "(untitled plan)" }
            Write-Output "  $i) $($f.BaseName) - $completed/$total tasks - $title$marker"
        }
        if ($i -eq 0) { Write-Output "  (no sessions found)" }
        Write-Output ""
        Write-Output "Run 'planprogress.ps1 use <number>' to pin the status line to one, or 'planprogress.ps1 unpin' for automatic mode."
        return
    }
    "use" {
        if (-not $Arg) {
            Write-Output "Usage: planprogress.ps1 use <number>   (run 'planprogress.ps1 sessions' to see the list)"
            return
        }
        $projectDir = if ($Dir) { $Dir } else { Resolve-ProjectDir (if ($Cwd) { $Cwd } else { (Get-Location).Path }) }
        if (-not (Test-Path $projectDir)) {
            Write-Output "Project directory not found: $projectDir"
            return
        }
        $files = Get-ChildItem -Path $projectDir -Filter "*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        $index = [int]$Arg
        if ($index -lt 1 -or $index -gt $files.Count) {
            Write-Output "No session #$index found. Run 'planprogress.ps1 sessions' first."
            return
        }
        $chosen = $files[$index - 1]
        Set-ConfigKey "PINNED_SESSION" $chosen.FullName
        Write-Output "Pinned the status line to: $($chosen.BaseName)"
        return
    }
    "unpin" {
        Set-ConfigKey "PINNED_SESSION" ""
        Write-Output "Unpinned. Status line will follow the current session (falling back to other open sessions) automatically again."
        return
    }
    "next" {
        $projectDir = if ($Dir) { $Dir } else { Resolve-ProjectDir (if ($Cwd) { $Cwd } else { (Get-Location).Path }) }
        if (-not (Test-Path $projectDir)) {
            Write-Output "Project directory not found: $projectDir"
            return
        }
        $cfg = Load-Config
        $files = Get-ChildItem -Path $projectDir -Filter "*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        if ($files.Count -eq 0) {
            Write-Output "No sessions found in $projectDir."
            return
        }
        $currentIndex = -1
        for ($i = 0; $i -lt $files.Count; $i++) {
            if ($files[$i].FullName -eq $cfg.PINNED_SESSION) { $currentIndex = $i }
        }
        $nextIndex = ($currentIndex + 1) % $files.Count
        $chosen = $files[$nextIndex]
        Set-ConfigKey "PINNED_SESSION" $chosen.FullName
        Write-Output "Pinned the status line to: $($chosen.BaseName)  ($($nextIndex + 1)/$($files.Count))"
        return
    }
    "install" {
        $settingsFile = if ($Settings) { $Settings } else { Join-Path $env:USERPROFILE ".claude\settings.json" }
        if (-not (Test-Path $settingsFile)) { "{}" | Set-Content $settingsFile }
        Copy-Item $settingsFile "$settingsFile.bak.$([DateTimeOffset]::Now.ToUnixTimeSeconds())"

        $data = Get-Content $settingsFile -Raw | ConvertFrom-Json
        $existingCmd = $null
        if ($data.statusLine -and $data.statusLine.command) { $existingCmd = $data.statusLine.command }
        $thisCmd = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\planprogress.ps1`""

        if (-not $existingCmd -or $existingCmd -like "*planprogress.ps1*") {
            if (-not $data.statusLine) { $data | Add-Member -NotePropertyName statusLine -NotePropertyValue @{} }
            $data.statusLine = @{ type = "command"; command = $thisCmd }
            $data | ConvertTo-Json -Depth 10 | Set-Content $settingsFile
            Write-Output "Installed as the sole status line in $settingsFile"
            return
        }

        $wrapper = Join-Path $ScriptDir "combined-statusline.ps1"
        @"
# Auto-generated by planprogress.ps1 install - chains the previous status
# line command with the plan-progress segment.
`$input_json = [Console]::In.ReadToEnd()
`$line1 = `$input_json | $existingCmd
`$line2 = `$input_json | pwsh -NoProfile -ExecutionPolicy Bypass -File "$ScriptDir\planprogress.ps1"
if (`$line2) { Write-Output "`$line1``n`$line2" } else { Write-Output `$line1 }
"@ | Set-Content $wrapper

        $data.statusLine = @{ type = "command"; command = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$wrapper`"" }
        $data | ConvertTo-Json -Depth 10 | Set-Content $settingsFile
        Write-Output "Found existing status line command: $existingCmd"
        Write-Output "Chained it with plan-progress into: $wrapper"
        Write-Output "Updated $settingsFile (backup saved alongside it)."
        return
    }
    default {
        # ===== Status line render mode =====
        $input_json = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($input_json)) { Write-Output "Claude"; return }

        $cfg = Load-Config
        if ($cfg.ENABLED -ne "1") { return }  # disabled: print nothing

        if ($cfg.LOCALE -eq "es") {
            $labelTask = "Tarea"; $labelDone = "Plan completo"; $labelNone = "Sin plan activo"; $labelOtherSession = "otra sesión"; $labelPinned = "fijado"; $labelWorking = "en curso"; $labelTodoWriteDisabled = "TodoWrite deshabilitada en esta sesión"
        } else {
            $labelTask = "Task"; $labelDone = "Plan complete"; $labelNone = "No active plan"; $labelOtherSession = "other session"; $labelPinned = "pinned"; $labelWorking = "in progress"; $labelTodoWriteDisabled = "TodoWrite disabled for this session"
        }

        $data = $input_json | ConvertFrom-Json
        $modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
        $transcriptPath = $data.transcript_path

        if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
            Write-Output $modelName
            return
        }

        $todos = $null
        $sourcePath = $transcriptPath
        $otherSession = $false
        $pinnedMarker = $false

        if ($cfg.PINNED_SESSION -and (Test-Path $cfg.PINNED_SESSION)) {
            $todos = Get-TodosFromTranscript $cfg.PINNED_SESSION
            $sourcePath = $cfg.PINNED_SESSION
            if ($cfg.PINNED_SESSION -ne $transcriptPath) { $pinnedMarker = $true }
        } else {
            $todos = Get-TodosFromTranscript $transcriptPath
            $sourcePath = $transcriptPath

            if ((-not $todos -or $todos.Count -eq 0) -and $cfg.CROSS_SESSION -eq "1") {
                $found = Find-OtherActivePlan $transcriptPath ([int]$cfg.CROSS_SESSION_MAX_AGE_MIN)
                if ($found) {
                    $todos = $found.Todos
                    $sourcePath = $found.Path
                    $otherSession = $true
                }
            }
        }

        if (-not $todos -or $todos.Count -eq 0) {
            $noneLabel = $labelNone
            if (Test-TodoWriteDisabled $transcriptPath) { $noneLabel = $labelTodoWriteDisabled }
            Write-Output "$modelName | $noneLabel"
            return
        }

        $total = $todos.Count
        $completed = ($todos | Where-Object { $_.status -eq "completed" }).Count
        $inProgress = $todos | Where-Object { $_.status -eq "in_progress" } | Select-Object -First 1

        $currentIndex = $completed + 1
        $currentTitle = $null
        if ($inProgress) {
            $currentTitle = if ($inProgress.activeForm) { $inProgress.activeForm } else { $inProgress.content }
        } elseif ($completed -ge $total) {
            $currentTitle = $labelDone
            $currentIndex = $total
        } else {
            $pending = $todos | Where-Object { $_.status -eq "pending" } | Select-Object -First 1
            # completed < total but neither an in_progress nor a pending task
            # was found: don't claim the plan is done, that would be wrong.
            $currentTitle = if ($pending) { $pending.content } else { $labelWorking }
        }

        $barWidth = [int]$cfg.BAR_WIDTH
        $pct = if ($total -gt 0) { [math]::Floor(($completed * 100) / $total) } else { 0 }
        $filled = [math]::Min($barWidth, [math]::Floor(($barWidth * $completed) / $total))
        $bar = ($cfg.FILLED_CHAR * $filled) + ($cfg.EMPTY_CHAR * ($barWidth - $filled))
        $emoji = if ($cfg.NO_EMOJI -eq "1") { "" } else { "📋 " }

        $colorName = $cfg.COLOR_MODE
        if ($colorName -eq "auto") {
            if ($pct -ge 100) { $colorName = "green" } elseif ($pct -ge 50) { $colorName = "cyan" } else { $colorName = "yellow" }
        }
        $pctStr = Colorize "$pct%" $colorName
        $barStr = Colorize $bar $colorName

        $line = "$modelName | $emoji$labelTask $currentIndex/$total - $currentTitle ($pctStr) $barStr"

        if ($cfg.SHOW_TITLE -eq "1") {
            $planTitle = Get-PlanTitle $sourcePath ([int]$cfg.TITLE_MAX_LEN)
            if ($planTitle) { $line = "$line - $planTitle" }
        }

        if ($pinnedMarker) {
            $line = "$line $(Colorize "($labelPinned)" 'dim')"
        } elseif ($otherSession) {
            $line = "$line $(Colorize "($labelOtherSession)" 'dim')"
        }

        Write-Output $line
    }
}
