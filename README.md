# claude-statusline

A colored progress-bar statusline for Claude Code — Windows / Linux / macOS / WSL2.

<p align="center"><img src="assets/demo.svg" alt="claude-statusline preview"></p>

## Features

- Three segments: **ctx** (context window), **5h** (5-hour usage), **7d** (7-day usage)
- 🟢 green (`<50%`) → 🟡 yellow (`50–80%`) → 🔴 red (`>=80%`)

## Install

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts/install.ps1 | iex
```

Linux / macOS / WSL2:

```bash
curl -fsSL https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts/install.sh | bash
```
