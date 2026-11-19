#!/usr/bin/env python3
"""Baseline for R17: how busy is the GPU slot under the bash loop?

Per day: gpu_slot_busy_pct (tester + regression session seconds over wall
seconds), standing_task_interval_secs (mean gap between tester:task headers),
closes (dw issues closed `completed`), cost (sum of usage: cost). Window
totals include cost_per_close.

The log carries HH:MM:SS only. A header earlier than the previous one means
the next day; the log file's mtime date is the last header's date.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys

HEADER = re.compile(r"^=== (\d\d):(\d\d):(\d\d) (.*?) ===\s*$")
USAGE = re.compile(r"^\[([^\]]*)\] usage: .*?duration=(\d+)s cost=\$([0-9.]+)")
GPU_ROLES = ("tester", "regression")


def _role(label):
    return re.split(r"[:# (]", label.strip(), maxsplit=1)[0]


def _header_label(rest):
    return re.sub(r" \(.*$", "", re.sub(r"^cycle \d+: ", "", rest))


def parse_sessions(lines, anchor):
    """Sessions in log order: date, secs (of day), role, label, duration, cost.
    A usage line fills the newest header's session; headers without one keep
    duration 0 (they still count for cadence)."""
    raw, day, prev = [], 0, None
    for line in lines:
        m = HEADER.match(line)
        if m:
            secs = int(m[1]) * 3600 + int(m[2]) * 60 + int(m[3])
            if prev is not None and secs < prev:  # same rule as dashboard _clock_epoch
                day += 1
            prev = secs
            label = _header_label(m[4])
            raw.append({"day": day, "secs": secs, "role": _role(label), "label": label,
                        "duration": 0, "cost": 0.0, "_filled": False})
            continue
        m = USAGE.match(line)
        if m and raw and not raw[-1]["_filled"]:
            s = raw[-1]
            s.update(role=_role(m[1]), duration=int(m[2]), cost=float(m[3]), _filled=True)
    last = raw[-1]["day"] if raw else 0
    for s in raw:
        s["date"] = anchor - datetime.timedelta(days=last - s.pop("day"))
        del s["_filled"]
    return raw


def cost_per_close(cost, closes):
    return round(cost / closes, 4) if closes else None


def per_day(sessions, closes, day_secs=86400):
    """{date: metrics}; closes is {date: n}."""
    days = {}
    for s in sessions:
        d = days.setdefault(s["date"], {"busy": 0, "cost": 0.0, "task": []})
        if s["role"] in GPU_ROLES:
            d["busy"] += s["duration"]
        d["cost"] += s["cost"]
        if s["label"].startswith("tester:task"):
            d["task"].append(s["secs"])
    out = {}
    for date, d in days.items():
        t = d["task"]
        gaps = [b - a for a, b in zip(t, t[1:])]
        out[date] = {
            "gpu_slot_busy_pct": round(100.0 * d["busy"] / day_secs, 1),
            "standing_task_interval_secs": round(sum(gaps) / len(gaps)) if gaps else None,
            "closes": closes.get(date, 0),
            "cost": round(d["cost"], 2),
        }
    return out


def fetch_closes(repo, since):
    out = subprocess.run(
        ["gh", "issue", "list", "--repo", repo, "--state", "closed", "--limit", "1000",
         "--search", f"closed:>={since}", "--json", "number,closedAt,stateReason"],
        capture_output=True, text=True, check=True).stdout
    closes = {}
    for i in json.loads(out):
        if (i.get("stateReason") or "").lower() == "completed" and i.get("closedAt"):
            d = datetime.date.fromisoformat(i["closedAt"][:10])
            closes[d] = closes.get(d, 0) + 1
    return closes


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--days", type=int, default=14)
    ap.add_argument("--log", default="logs/loop.log")
    ap.add_argument("--repo", help="gh repo for closes; omitted means closes are 0")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    anchor = datetime.date.fromtimestamp(os.path.getmtime(a.log))
    since = anchor - datetime.timedelta(days=a.days - 1)
    with open(a.log, errors="replace") as f:
        sessions = [s for s in parse_sessions(f, anchor) if s["date"] >= since]
    closes = fetch_closes(a.repo, since.isoformat()) if a.repo else {}
    days = per_day(sessions, closes)
    cost = round(sum(d["cost"] for d in days.values()), 2)
    n = sum(d["closes"] for d in days.values())
    busy = [d["gpu_slot_busy_pct"] for d in days.values()]
    gaps = [d["standing_task_interval_secs"] for d in days.values() if d["standing_task_interval_secs"]]
    totals = {"days": len(days), "cost": cost, "closes": n, "cost_per_close": cost_per_close(cost, n),
              "gpu_slot_busy_pct": round(sum(busy) / len(busy), 1) if busy else None,
              "standing_task_interval_secs": round(sum(gaps) / len(gaps)) if gaps else None}
    res = {"anchor": anchor.isoformat(), "days": {k.isoformat(): v for k, v in sorted(days.items())},
           "totals": totals}
    if a.json:
        print(json.dumps(res, indent=2))
    else:
        for k, v in res["days"].items():
            print(k, *(f"{n}={x}" for n, x in v.items()))
        print("TOTAL", *(f"{n}={x}" for n, x in totals.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
