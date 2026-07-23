#!/usr/bin/env python3
"""Claude Code statusline for Linux / macOS - mirror of statusline.ps1."""
import glob
import json
import os
import subprocess
import sys
import time
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

# ---- Token usage settings ------------------------------------------------
# Which usage components count toward the D/M/Y totals
COUNT_INPUT = True           # input_tokens
COUNT_CACHE_CREATION = True  # cache_creation_input_tokens
COUNT_CACHE_READ = True      # cache_read_input_tokens
COUNT_OUTPUT = True          # output_tokens

CLAUDE_DIR = os.path.join(os.path.expanduser("~"), ".claude")
USAGE_CACHE = os.path.join(CLAUDE_DIR, "statusline-usage.json")
USAGE_LOCK = os.path.join(CLAUDE_DIR, "statusline-usage.lock")
CACHE_TTL_SEC = 300   # rescan when the cache is older than this
LOCK_STALE_SEC = 600  # ignore a lock older than this (crashed rescan)
# --------------------------------------------------------------------------


def lock_fresh():
    try:
        return time.time() - os.path.getmtime(USAGE_LOCK) < LOCK_STALE_SEC
    except OSError:
        return False


def rescan():
    if lock_fresh():
        return
    with open(USAGE_LOCK, "w") as fh:
        fh.write(str(os.getpid()))
    try:
        files_map = {}
        if os.path.exists(USAGE_CACHE):
            try:
                with open(USAGE_CACHE, encoding="utf-8") as fh:
                    files_map = json.load(fh).get("files", {})
            except Exception:
                files_map = {}

        seen = set()
        proj = os.path.join(CLAUDE_DIR, "projects")
        for path in glob.glob(os.path.join(proj, "**", "*.jsonl"), recursive=True):
            try:
                st = os.stat(path)
            except OSError:
                continue
            stored = files_map.get(path)
            if stored and stored.get("mtime") == int(st.st_mtime) and stored.get("size") == st.st_size:
                continue

            days = {}
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        # Cheap prefilter; tool results may embed usage-like JSON, hence the type check
                        if '"usage":{' not in line or '"type":"assistant"' not in line:
                            continue
                        try:
                            obj = json.loads(line)
                        except Exception:
                            continue
                        if obj.get("type") != "assistant":
                            continue
                        msg = obj.get("message") or {}
                        usage = msg.get("usage")
                        ts = obj.get("timestamp")
                        if not usage or not ts:
                            continue
                        key = (msg.get("id"), obj.get("requestId"))
                        if key[0] and key[1]:
                            if key in seen:
                                continue  # duplicate message
                            seen.add(key)
                        try:
                            day = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d")
                        except ValueError:
                            continue
                        d = days.setdefault(day, {"in": 0, "cc": 0, "cr": 0, "out": 0})
                        d["in"] += usage.get("input_tokens") or 0
                        d["cc"] += usage.get("cache_creation_input_tokens") or 0
                        d["cr"] += usage.get("cache_read_input_tokens") or 0
                        d["out"] += usage.get("output_tokens") or 0
            except OSError:
                continue
            files_map[path] = {"mtime": int(st.st_mtime), "size": st.st_size, "days": days}

        # Aggregate per-day totals across all files, including files that no
        # longer exist on disk -- their stored contribution keeps the history
        # alive after Claude Code cleans old transcripts up.
        agg = {}
        for entry in files_map.values():
            for day, d in (entry.get("days") or {}).items():
                a = agg.setdefault(day, {"in": 0, "cc": 0, "cr": 0, "out": 0})
                for k in a:
                    a[k] += int(d.get(k, 0))

        payload = {"updated": int(time.time()), "files": files_map, "days": agg}
        tmp = USAGE_CACHE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh)
        os.replace(tmp, USAGE_CACHE)
    finally:
        try:
            os.remove(USAGE_LOCK)
        except OSError:
            pass


def start_rescan():
    if lock_fresh():
        return
    kwargs = {"start_new_session": True} if os.name == "posix" else {}
    subprocess.Popen(
        [sys.executable or "python3", os.path.abspath(__file__), "--rescan"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        **kwargs,
    )


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


def format_tokens(n):
    for div, suffix in ((1e9, "B"), (1e6, "M"), (1e3, "k")):
        if n >= div:
            s = f"{n / div:.1f}".rstrip("0").rstrip(".")
            return s + suffix
    return str(int(n))


def day_total(d):
    t = 0
    if COUNT_INPUT:
        t += int(d.get("in", 0))
    if COUNT_CACHE_CREATION:
        t += int(d.get("cc", 0))
    if COUNT_CACHE_READ:
        t += int(d.get("cr", 0))
    if COUNT_OUTPUT:
        t += int(d.get("out", 0))
    return t


def token_segment():
    cache = None
    if os.path.exists(USAGE_CACHE):
        try:
            with open(USAGE_CACHE, encoding="utf-8") as fh:
                cache = json.load(fh)
        except Exception:
            cache = None
    stale = cache is None or time.time() - cache.get("updated", 0) > CACHE_TTL_SEC
    if stale:
        try:
            start_rescan()
        except Exception:
            pass
    if cache is None:
        return None  # nothing to show yet

    today = datetime.now().strftime("%Y-%m-%d")
    month, year = today[:7], today[:4]
    dsum = msum = ysum = 0
    for day, d in (cache.get("days") or {}).items():
        t = day_total(d)
        if day == today:
            dsum += t
        if day.startswith(month):
            msum += t
        if day.startswith(year):
            ysum += t

    return (f"{DIM}Token{RESET} {DIM}D{RESET} {format_tokens(dsum)}"
            f"  {DIM}M{RESET} {format_tokens(msum)}"
            f"  {DIM}Y{RESET} {format_tokens(ysum)}")


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
    try:
        segments.append(token_segment())
    except Exception:
        pass
    sep = f"  {DIM}|{RESET}  "
    print(sep.join(s for s in segments if s is not None))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--rescan":
        try:
            rescan()
        except Exception:
            pass
        sys.exit(0)
    try:
        main()
    except Exception:
        print("")  # never break the statusline
