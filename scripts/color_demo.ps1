# Preview the statusline threshold colors (green <50% / yellow 50-80% / red >=80%)
# and the Token usage segment (D today / M this month / Y this year)
$now = [DateTimeOffset]::UtcNow
$r5  = $now.AddMinutes(98).ToUnixTimeSeconds()
$r7  = $now.AddDays(2).AddHours(2).ToUnixTimeSeconds()
$sl  = Join-Path $env:USERPROFILE '.claude\statusline.ps1'

function Demo([double]$pct, [string]$label) {
    $json = '{"context_window":{"used_percentage":' + $pct + '},"rate_limits":{"five_hour":{"used_percentage":' + $pct + ',"resets_at":' + $script:r5 + '},"seven_day":{"used_percentage":' + $pct + ',"resets_at":' + $script:r7 + '}}}'
    Write-Host $label.PadRight(16) -NoNewline
    $json | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:sl
}

Demo 32 'GREEN  (<50%)'
Demo 65 'YELLOW (50-80%)'
Demo 91 'RED    (>=80%)'

# Fixed sample of the Token segment, so it also shows on machines with no usage cache yet
$ESC = [char]27; $DIM = "$ESC[2m"; $RESET = "$ESC[0m"
Write-Host ('TOKEN (sample)'.PadRight(16) +
    $DIM + 'Token' + $RESET + ' ' + $DIM + 'D' + $RESET + ' 6.8M' +
    '  ' + $DIM + 'M' + $RESET + ' 170.8M' +
    '  ' + $DIM + 'Y' + $RESET + ' 1.2B')
