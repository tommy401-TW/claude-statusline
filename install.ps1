# =============================================================
#  Claude Code Statusline - one-line installer
#  Usage A (one-liner)   : irm https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/install.ps1 | iex
#  Usage B (from a clone): powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
#  Compatible with Windows PowerShell 5.1
# =============================================================
$ErrorActionPreference = 'Stop'

$repoRawBase = 'https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main'
$claudeDir   = Join-Path $env:USERPROFILE '.claude'
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }

# ---- Install script files (copy local files when run from a clone, download from GitHub when run via irm) ----
$files = @('statusline.ps1', 'color_demo.ps1')
foreach ($f in $files) {
    $dest  = Join-Path $claudeDir $f
    $local = $null
    if ($PSScriptRoot) { $local = Join-Path $PSScriptRoot $f }

    if ($null -ne $local -and (Test-Path $local)) {
        $content = [IO.File]::ReadAllText($local, [Text.Encoding]::UTF8)
    } else {
        $content = Invoke-RestMethod -Uri "$repoRawBase/$f"
    }

    # Strip any BOM char left at the start of the string, then write as UTF-8 WITH BOM --
    # without a BOM, Windows PowerShell 5.1 decodes .ps1 files as ANSI, and non-ASCII
    # comments can swallow line breaks and comment out the next line of code
    $content = $content.TrimStart([char]0xFEFF)
    [IO.File]::WriteAllText($dest, $content, (New-Object System.Text.UTF8Encoding($true)))
    Write-Host "OK  $dest"
}

# ---- Merge the statusLine block into settings.json (all other settings are preserved) ----
$settingsPath = Join-Path $claudeDir 'settings.json'
$cmdPath = ($claudeDir -replace '\\', '/') + '/statusline.ps1'
$statusLine = [pscustomobject]@{
    type            = 'command'
    command         = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $cmdPath + '"'
    refreshInterval = 10
}

if (Test-Path $settingsPath) {
    $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
} else {
    $settings = New-Object PSObject
}

if ($null -ne $settings.PSObject.Properties['statusLine']) {
    $settings.statusLine = $statusLine
} else {
    $settings | Add-Member -MemberType NoteProperty -Name statusLine -Value $statusLine
}

$json = $settings | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK  $settingsPath (statusLine updated)"

Write-Host ''
Write-Host 'Done! Claude Code statusline installed.'
Write-Host 'A running session refreshes within ~10s; otherwise restart Claude Code.'
Write-Host 'Preview the threshold colors: powershell -NoProfile -ExecutionPolicy Bypass -File "' -NoNewline
Write-Host (Join-Path $claudeDir 'color_demo.ps1') -NoNewline
Write-Host '"'
