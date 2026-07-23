#!/usr/bin/env python3
"""Claude Code statusline for Linux / macOS / WSL2 - mirror of statusline.ps1."""
import json
import sys
from datetime import datetime, timezone

ESC = "\x1b"
RESET = f"{ESC}[0m"
GREEN = f"{ESC}[32m"   # <50% threshold
YELLOW = f"{ESC}[33m"  # 50-80% threshold (green -> yellow -> red warning gradient)
RED = f"{ESC}[31m"     # >=80% threshold
LBLUE = f"{ESC}[96m"   # light blue: reset countdown
DIM = f"{ESC}[2m"

FILL = "█"   # full block
EMPTY = "░"  # light shade


def bar_color(pct):
    if pct < 50:
        return GREEN
    if pct < 80:
        return YELLOW
    return RED


def parse_reset_epoch(resets_at):
    if resets_at is None:
        return None
    try:
        return float(resets_at)  # epoch seconds
    except (TypeError, ValueError):
        pass
    try:  # ISO 8601 timestamp
        dt = datetime.fromisoformat(str(resets_at).replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except ValueError:
        return None


def countdown(resets_at, fmt):
    reset_epoch = parse_reset_epoch(resets_at)
    if reset_epoch is None:
        return None
    diff = max(0.0, reset_epoch - datetime.now(timezone.utc).timestamp())
    total_minutes = int(diff // 60)
    hours, minutes = total_minutes // 60, total_minutes % 60
    if fmt == "dh":
        # days + hours (no minutes); fall back to hours under a day, minutes under an hour
        days, rem_hours = hours // 24, hours % 24
        if days >= 1:
            return f"reset {days}d {rem_hours}h"
        if hours >= 1:
            return f"reset {hours}h"
        return f"reset {minutes}m"
    if hours >= 1:
        return f"reset {hours}h {minutes}m"
    return f"reset {minutes}m"


def segment(label, pct, resets_at=None, fmt="hm"):
    if pct is None:
        return None
    val = min(100.0, max(0.0, float(pct)))
    color = bar_color(val)
    filled = min(10, max(0, int((val + 5) // 10)))
    bar = color + FILL * filled + DIM + EMPTY * (10 - filled) + RESET
    pct_text = f"{color}{int(val + 0.5)}%{RESET}"
    seg = f"{label} {bar} {pct_text}"
    if resets_at is not None:
        cd = countdown(resets_at, fmt)
        if cd is not None:
            seg += f" {LBLUE}{cd}{RESET}"
    return seg


def main():
    data = json.loads(sys.stdin.read().lstrip("\ufeff"))  # tolerate a stray BOM
    ctx = (data.get("context_window") or {}).get("used_percentage")
    rl = data.get("rate_limits") or {}
    fh = rl.get("five_hour") or {}
    sd = rl.get("seven_day") or {}

    segments = [
        segment("ctx", ctx),
        segment("5h", fh.get("used_percentage"), fh.get("resets_at")),
        segment("7d", sd.get("used_percentage"), sd.get("resets_at"), "dh"),
    ]
    sep = f"  {DIM}|{RESET}  "
    print(sep.join(s for s in segments if s is not None))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("")  # never break the statusline
