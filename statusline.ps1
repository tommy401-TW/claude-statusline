[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ESC   = [char]27
$RESET = "$ESC[0m"
$GREEN = "$ESC[32m"
$YELLOW = "$ESC[33m"  # yellow: 50-80% threshold (green -> yellow -> red warning gradient)
$LBLUE  = "$ESC[96m"  # light blue: reset countdown
$RED   = "$ESC[31m"
$DIM   = "$ESC[2m"

$rawInput = [Console]::In.ReadToEnd()
$data = $rawInput | ConvertFrom-Json

function Get-BarColor([double]$pct) {
    if ($pct -lt 50) { return $GREEN }
    elseif ($pct -lt 80) { return $YELLOW }
    else { return $RED }
}

function Get-Segment([string]$label, $pct, $resetsAt, [string]$fmt = 'hm') {
    if ($null -eq $pct) { return $null }

    $val = [double]$pct
    if ($val -lt 0) { $val = 0 }
    if ($val -gt 100) { $val = 100 }

    $color  = Get-BarColor $val
    $filled = [int][math]::Floor(($val + 5) / 10)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt 10) { $filled = 10 }
    $empty  = 10 - $filled

    $fillCh  = [string][char]0x2588   # full block
    $emptyCh = [string][char]0x2591   # light shade
    $bar = $color + ($fillCh * $filled) + $DIM + ($emptyCh * $empty) + $RESET

    $displayPct = [int][math]::Floor($val + 0.5)
    $pctText = $color + $displayPct.ToString() + '%' + $RESET

    $seg = "$label $bar $pctText"

    if ($null -ne $resetsAt) {
        $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $resetEpoch = $null
        $numVal = 0.0
        if ([double]::TryParse([string]$resetsAt, [ref]$numVal)) {
            # epoch seconds
            $resetEpoch = $numVal
        } else {
            # ISO 8601 timestamp
            try {
                $resetEpoch = [DateTimeOffset]::Parse([string]$resetsAt, [System.Globalization.CultureInfo]::InvariantCulture).ToUnixTimeSeconds()
            } catch { $resetEpoch = $null }
        }
        if ($null -eq $resetEpoch) { return $seg }
        $diff = $resetEpoch - $nowEpoch
        if ($diff -lt 0) { $diff = 0 }
        $totalMinutes = [int][math]::Floor($diff / 60)
        $hours = [int][math]::Floor($totalMinutes / 60)
        $minutes = $totalMinutes % 60

        if ($fmt -eq 'dh') {
            # days + hours (no minutes); fall back to hours under a day, minutes under an hour
            $days = [int][math]::Floor($hours / 24)
            $remHours = $hours % 24
            if ($days -ge 1) {
                $countdown = "reset ${days}d ${remHours}h"
            } elseif ($hours -ge 1) {
                $countdown = "reset ${hours}h"
            } else {
                $countdown = "reset ${minutes}m"
            }
        } elseif ($hours -ge 1) {
            $countdown = "reset ${hours}h ${minutes}m"
        } else {
            $countdown = "reset ${minutes}m"
        }

        $seg = "$seg $LBLUE$countdown$RESET"
    }

    return $seg
}

$segments = New-Object System.Collections.Generic.List[string]

$ctxSeg = Get-Segment 'ctx' $data.context_window.used_percentage $null
if ($null -ne $ctxSeg) { $segments.Add($ctxSeg) }

$fiveHourSeg = Get-Segment '5h' $data.rate_limits.five_hour.used_percentage $data.rate_limits.five_hour.resets_at
if ($null -ne $fiveHourSeg) { $segments.Add($fiveHourSeg) }

$sevenDaySeg = Get-Segment '7d' $data.rate_limits.seven_day.used_percentage $data.rate_limits.seven_day.resets_at 'dh'
if ($null -ne $sevenDaySeg) { $segments.Add($sevenDaySeg) }

$separator = "  " + $DIM + [char]0x7C + $RESET + "  "

Write-Output ($segments -join $separator)
