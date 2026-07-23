# claude-statusline

A custom Claude Code statusline for Windows: colored progress bars for context window and Pro/Max usage, with rate-limit reset countdowns.

```
ctx ███░░░░░░░ 34%  |  5h ███████░░░ 65% reset 1h 38m  |  7d █████████░ 90% reset 2d 2h
```

## Features

- Three segments: **ctx** (context window usage), **5h** (5-hour usage), **7d** (7-day usage)
- Each segment renders a 10-cell progress bar (`█`/`░`) plus a percentage, colored by usage:
  - 🟢 green (`<50%`) → 🟡 yellow (`50–80%`) → 🔴 red (`>=80%`)
- Light-blue reset countdown after the 5h / 7d bars:
  - 5h: `reset 1h 38m` (falls back to `reset 38m` under one hour)
  - 7d: `reset 2d 2h` (days + hours; falls back to hours / minutes when under a day)
- Segments separated by a dim half-width `|`
- `rate_limits` only appears for Pro/Max subscriptions after the session's first response — missing segments are silently skipped, never shown as errors
- `resets_at` accepts both epoch seconds and ISO 8601 strings

## One-line install

Run in PowerShell:

```powershell
irm https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/install.ps1 | iex
```

Or clone and install:

```powershell
git clone https://github.com/tommy401-TW/claude-statusline.git
cd claude-statusline
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

The installer:

1. Copies `statusline.ps1` and `color_demo.ps1` to `%USERPROFILE%\.claude\` (forced to UTF-8 with BOM, required by Windows PowerShell 5.1)
2. Updates the `statusLine` block in `%USERPROFILE%\.claude\settings.json` (`refreshInterval: 10`) — **all other existing settings are preserved**

A running Claude Code session picks up the change within ~10 seconds; otherwise restart Claude Code.

## Preview the colors

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\color_demo.ps1"
```

## Customization

Edit the ANSI color codes at the top of `%USERPROFILE%\.claude\statusline.ps1`:

| Variable  | Default   | Used for           |
| --------- | --------- | ------------------ |
| `$GREEN`  | `ESC[32m` | `<50%` threshold   |
| `$YELLOW` | `ESC[33m` | `50–80%` threshold |
| `$RED`    | `ESC[31m` | `>=80%` threshold  |
| `$LBLUE`  | `ESC[96m` | reset countdown    |
| `$DIM`    | `ESC[2m`  | separator, empty bar cells |

Bar characters live in `Get-Segment` (`0x2588` = `█`, `0x2591` = `░`); change the `10` constants there to resize the bar.

> **Note**: keep `statusline.ps1` saved as **UTF-8 with BOM** if you add non-ASCII comments — without a BOM, Windows PowerShell 5.1 decodes the file as ANSI, which can swallow line breaks and comment out the following line of code.

## Requirements

- Windows + Windows PowerShell 5.1 (built in)
- Claude Code CLI
