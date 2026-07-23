# CLAUDE-STATUSLINE

A colored progress-bar statusline for Claude Code — Windows / Linux / macOS.

<p align="center"><img src="assets/demo.svg" alt="claude-statusline preview"></p>

## Features

- Three segments: **ctx** (context window), **5h** (5-hour usage), **7d** (7-day usage)
- 🟢 green (`<50%`) → 🟡 yellow (`50–80%`) → 🔴 red (`>=80%`)

## Install

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts/install.ps1 | iex
```

Windows (cmd):

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts/install.ps1 | iex"
```

Linux / macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts/install.sh | bash
```
