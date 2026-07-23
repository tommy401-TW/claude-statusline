#!/usr/bin/env bash
# Preview the three statusline threshold colors (green <50% / yellow 50-80% / red >=80%)
now=$(date -u +%s)
r5=$((now + 98 * 60))
r7=$((now + 2 * 24 * 3600 + 2 * 3600))
sl="$HOME/.claude/statusline.py"

demo() {
    printf '%-16s' "$2"
    printf '{"context_window":{"used_percentage":%s},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' \
        "$1" "$1" "$r5" "$1" "$r7" | python3 "$sl"
}

demo 32 'GREEN  (<50%)'
demo 65 'YELLOW (50-80%)'
demo 91 'RED    (>=80%)'
