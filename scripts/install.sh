#!/usr/bin/env bash
# =============================================================
#  Claude Code Statusline - installer for Linux / macOS / WSL2
#  Usage A (one-liner)   : curl -fsSL https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts/install.sh | bash
#  Usage B (from a clone): bash ./install.sh
#  Requires: python3
# =============================================================
set -euo pipefail

REPO_RAW_BASE="https://raw.githubusercontent.com/tommy401-TW/claude-statusline/main/scripts"
CLAUDE_DIR="$HOME/.claude"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required. Install it first (e.g. sudo apt install python3)." >&2
    exit 1
fi

mkdir -p "$CLAUDE_DIR"

# Clone mode when the script's own directory contains statusline.py; otherwise download from GitHub
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

for f in statusline.py color_demo.sh; do
    dest="$CLAUDE_DIR/$f"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$f" ]; then
        cp "$SCRIPT_DIR/$f" "$dest"
    else
        curl -fsSL "$REPO_RAW_BASE/$f" -o "$dest"
    fi
    echo "OK  $dest"
done

# Merge the statusLine block into settings.json (all other settings are preserved)
python3 - "$CLAUDE_DIR" <<'PYEOF'
import json, os, sys

claude_dir = sys.argv[1]
path = os.path.join(claude_dir, "settings.json")
settings = {}
if os.path.exists(path):
    with open(path, encoding="utf-8-sig") as fh:
        settings = json.load(fh)

script = os.path.join(claude_dir, "statusline.py")
settings["statusLine"] = {
    "type": "command",
    "command": 'python3 "' + script + '"',
    "refreshInterval": 10,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
print("OK  " + path + " (statusLine updated)")
PYEOF

echo ""
echo "Done! Claude Code statusline installed."
echo "A running session refreshes within ~10s; otherwise restart Claude Code."
echo "Preview the threshold colors: bash \"$CLAUDE_DIR/color_demo.sh\""
