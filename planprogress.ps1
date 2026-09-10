# Source: https://github.com/GabrielTalmaV/claude-code-plan-progress
# Renders plan-implementation progress as a Claude Code statusLine segment,
# and doubles as a CLI to configure/enable/disable/install itself.
#
# See planprogress.sh for how rendering works (reads the latest TodoWrite
# call from the session transcript referenced by stdin's transcript_path).
#
# CLI usage:
#   planprogress.ps1 enable
#   planprogress.ps1 disable
#   planprogress.ps1 status
#   planprogress.ps1 config -Width 20 -Color cyan -FilledChar "=" -EmptyChar "-"
#   planprogress.ps1 config -Show
#   planprogress.ps1 config -Reset
#   planprogress.ps1 install [-Settings <path>]

param(
    [Parameter(Position = 0)]
    [string]$Command,
    [int]$Width,
    [string]$Color,
    [string]$FilledChar,
    [string]$EmptyChar,
    [string]$Locale,
    [switch]$Emoji,
    [switch]$NoEmoji,
    [switch]$Show,
    [switch]$Reset,
    [string]$Settings
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
            $labelTask = "Tarea"; $labelDone = "Plan completo"; $labelNone = "Sin plan activo"
        } else {
            $labelTask = "Task"; $labelDone = "Plan complete"; $labelNone = "No active plan"
        }

        $data = $input_json | ConvertFrom-Json
        $modelName = if ($data.model.display_name) { $data.model.display_name } else { "Claude" }
        $transcriptPath = $data.transcript_path

        if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
            Write-Output $modelName
            return
        }

        $todos = $null
        Get-Content -LiteralPath $transcriptPath -ErrorAction SilentlyContinue | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_)) { return }
            try { $entry = $_ | ConvertFrom-Json } catch { return }
            if ($entry.type -ne "assistant") { return }
            foreach ($block in $entry.message.content) {
                if ($block.type -eq "tool_use" -and $block.name -eq "TodoWrite") { $todos = $block.input.todos }
            }
        }

        if (-not $todos -or $todos.Count -eq 0) {
            Write-Output "$modelName | $labelNone"
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
            $currentTitle = if ($pending) { $pending.content } else { $labelDone }
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

        Write-Output "$modelName | $emoji$labelTask $currentIndex/$total - $currentTitle ($pctStr) $barStr"
    }
}
