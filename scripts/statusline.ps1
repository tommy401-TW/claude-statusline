param([switch]$Rescan)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ESC   = [char]27
$RESET = "$ESC[0m"
$GREEN = "$ESC[32m"   # <50% threshold
$YELLOW = "$ESC[33m"  # yellow: 50-80% threshold (green -> yellow -> red warning gradient)
$RED   = "$ESC[31m"   # >=80% threshold
$LBLUE = "$ESC[96m"   # light blue: reset countdown
$DIM   = "$ESC[2m"

# ---- Token usage settings ------------------------------------------------
# Which usage components count toward the D/M/Y totals
$COUNT_INPUT          = $true   # input_tokens
$COUNT_CACHE_CREATION = $true   # cache_creation_input_tokens
$COUNT_CACHE_READ     = $true   # cache_read_input_tokens
$COUNT_OUTPUT         = $true   # output_tokens

$CLAUDE_DIR  = Join-Path $env:USERPROFILE '.claude'
$USAGE_CACHE = Join-Path $CLAUDE_DIR 'statusline-usage.json'
$USAGE_LOCK  = Join-Path $CLAUDE_DIR 'statusline-usage.lock'
$CACHE_TTL_SEC   = 300   # rescan when the cache is older than this
$LOCK_STALE_SEC  = 600   # ignore a lock older than this (crashed rescan)
# --------------------------------------------------------------------------

function Get-Props($o) {
    # Uniform name/value iteration over hashtables and ConvertFrom-Json objects
    if ($null -eq $o) { return }
    if ($o -is [hashtable]) {
        foreach ($k in $o.Keys) { [pscustomobject]@{ Name = $k; Value = $o[$k] } }
    } else {
        foreach ($p in $o.PSObject.Properties) { [pscustomobject]@{ Name = $p.Name; Value = $p.Value } }
    }
}

function Invoke-UsageRescan {
    if (Test-Path $USAGE_LOCK) {
        $age = ((Get-Date) - (Get-Item $USAGE_LOCK).LastWriteTime).TotalSeconds
        if ($age -lt $LOCK_STALE_SEC) { return }
    }
    Set-Content -Path $USAGE_LOCK -Value $PID -Encoding ASCII
    try {
        $filesMap = @{}
        if (Test-Path $USAGE_CACHE) {
            try {
                $old = [IO.File]::ReadAllText($USAGE_CACHE, [Text.Encoding]::UTF8) | ConvertFrom-Json
                foreach ($f in Get-Props $old.files) { $filesMap[$f.Name] = $f.Value }
            } catch {}
        }

        $seen = New-Object 'System.Collections.Generic.HashSet[string]'
        $projDir = Join-Path $CLAUDE_DIR 'projects'
        if (Test-Path $projDir) {
            foreach ($fi in Get-ChildItem $projDir -Recurse -Filter *.jsonl -File) {
                $key = $fi.FullName
                $mt  = $fi.LastWriteTimeUtc.Ticks
                $sz  = $fi.Length
                $stored = $filesMap[$key]
                $unchanged = ($null -ne $stored -and [long]$stored.mtime -eq $mt -and [long]$stored.size -eq $sz)
                if ($unchanged) { continue }

                $days = @{}
                foreach ($line in [IO.File]::ReadLines($key)) {
                    if (-not $line.Contains('"usage":{')) { continue }
                    if (-not $line.Contains('"type":"assistant"')) { continue }   # tool results may embed usage-like JSON
                    $mIn = [regex]::Match($line, '"input_tokens":(\d+)')
                    $mTs = [regex]::Match($line, '"timestamp":"([^"]+)"')
                    if (-not $mIn.Success -or -not $mTs.Success) { continue }
                    $mId  = [regex]::Match($line, '"id":"(msg_[^"]+)"')
                    $mReq = [regex]::Match($line, '"requestId":"([^"]+)"')
                    if ($mId.Success -and $mReq.Success) {
                        $dk = $mId.Groups[1].Value + '|' + $mReq.Groups[1].Value
                        if (-not $seen.Add($dk)) { continue }   # duplicate message
                    }
                    try {
                        $day = [DateTimeOffset]::Parse($mTs.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture).ToLocalTime().ToString('yyyy-MM-dd')
                    } catch { continue }
                    $mCc  = [regex]::Match($line, '"cache_creation_input_tokens":(\d+)')
                    $mCr  = [regex]::Match($line, '"cache_read_input_tokens":(\d+)')
                    $mOut = [regex]::Match($line, '"output_tokens":(\d+)')
                    if (-not $days.ContainsKey($day)) { $days[$day] = @{ in = [long]0; cc = [long]0; cr = [long]0; out = [long]0 } }
                    $d = $days[$day]
                    $d.in  += [long]$mIn.Groups[1].Value
                    if ($mCc.Success)  { $d.cc  += [long]$mCc.Groups[1].Value }
                    if ($mCr.Success)  { $d.cr  += [long]$mCr.Groups[1].Value }
                    if ($mOut.Success) { $d.out += [long]$mOut.Groups[1].Value }
                }
                $filesMap[$key] = @{ mtime = $mt; size = $sz; days = $days }
            }
        }

        # Aggregate per-day totals across all files, including files that no
        # longer exist on disk -- their stored contribution keeps the history
        # alive after Claude Code cleans old transcripts up.
        $agg = @{}
        foreach ($f in Get-Props $filesMap) {
            foreach ($dv in Get-Props $f.Value.days) {
                if (-not $agg.ContainsKey($dv.Name)) { $agg[$dv.Name] = @{ in = [long]0; cc = [long]0; cr = [long]0; out = [long]0 } }
                $a = $agg[$dv.Name]
                $a.in  += [long]$dv.Value.in
                $a.cc  += [long]$dv.Value.cc
                $a.cr  += [long]$dv.Value.cr
                $a.out += [long]$dv.Value.out
            }
        }

        $payload = @{
            updated = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            files   = $filesMap
            days    = $agg
        } | ConvertTo-Json -Depth 10 -Compress
        $tmp = $USAGE_CACHE + '.tmp'
        [IO.File]::WriteAllText($tmp, $payload, (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -Path $tmp -Destination $USAGE_CACHE -Force
    } finally {
        Remove-Item $USAGE_LOCK -Force -ErrorAction SilentlyContinue
    }
}

if ($Rescan) { Invoke-UsageRescan; exit }

# ==========================================================================
#  Render mode (stdin JSON -> one statusline)
# ==========================================================================

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

function Format-Tokens([double]$n) {
    if ($n -ge 1e9) { return ('{0:0.#}B' -f ($n / 1e9)) }
    if ($n -ge 1e6) { return ('{0:0.#}M' -f ($n / 1e6)) }
    if ($n -ge 1e3) { return ('{0:0.#}k' -f ($n / 1e3)) }
    return [string][long]$n
}

function Start-UsageRescan {
    if (Test-Path $USAGE_LOCK) {
        $age = ((Get-Date) - (Get-Item $USAGE_LOCK).LastWriteTime).TotalSeconds
        if ($age -lt $LOCK_STALE_SEC) { return }
    }
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Rescan') `
        -WindowStyle Hidden
}

function Get-DayTotal($dayObj) {
    $t = [long]0
    if ($COUNT_INPUT)          { $t += [long]$dayObj.in }
    if ($COUNT_CACHE_CREATION) { $t += [long]$dayObj.cc }
    if ($COUNT_CACHE_READ)     { $t += [long]$dayObj.cr }
    if ($COUNT_OUTPUT)         { $t += [long]$dayObj.out }
    return $t
}

function Get-TokenSegment {
    $cache = $null
    if (Test-Path $USAGE_CACHE) {
        try { $cache = [IO.File]::ReadAllText($USAGE_CACHE, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch {}
    }
    $stale = $true
    if ($null -ne $cache) {
        $ageSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$cache.updated
        $stale = ($ageSec -gt $CACHE_TTL_SEC)
    }
    if ($stale) { Start-UsageRescan }
    if ($null -eq $cache) { return $null }   # nothing to show yet

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $month = $today.Substring(0, 7)
    $year  = $today.Substring(0, 4)
    $dSum = [long]0; $mSum = [long]0; $ySum = [long]0
    foreach ($dv in Get-Props $cache.days) {
        $t = Get-DayTotal $dv.Value
        if ($dv.Name -eq $today)         { $dSum += $t }
        if ($dv.Name.StartsWith($month)) { $mSum += $t }
        if ($dv.Name.StartsWith($year))  { $ySum += $t }
    }

    return ($DIM + 'Token' + $RESET +
        ' ' + $DIM + 'D' + $RESET + ' ' + (Format-Tokens $dSum) +
        '  ' + $DIM + 'M' + $RESET + ' ' + (Format-Tokens $mSum) +
        '  ' + $DIM + 'Y' + $RESET + ' ' + (Format-Tokens $ySum))
}

$segments = New-Object System.Collections.Generic.List[string]

$ctxSeg = Get-Segment 'ctx' $data.context_window.used_percentage $null
if ($null -ne $ctxSeg) { $segments.Add($ctxSeg) }

$fiveHourSeg = Get-Segment '5h' $data.rate_limits.five_hour.used_percentage $data.rate_limits.five_hour.resets_at
if ($null -ne $fiveHourSeg) { $segments.Add($fiveHourSeg) }

$sevenDaySeg = Get-Segment '7d' $data.rate_limits.seven_day.used_percentage $data.rate_limits.seven_day.resets_at 'dh'
if ($null -ne $sevenDaySeg) { $segments.Add($sevenDaySeg) }

$tokenSeg = $null
try { $tokenSeg = Get-TokenSegment } catch {}
if ($null -ne $tokenSeg) { $segments.Add($tokenSeg) }

$separator = "  " + $DIM + [char]0x7C + $RESET + "  "

Write-Output ($segments -join $separator)
