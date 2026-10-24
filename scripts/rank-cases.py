#!/usr/bin/env python3
"""Ranks regression cases from the results ledger (regression-results/,
one JSONL per case; its README has the format), one row per case:

    case  runs  fails  last_fail  median_secs  est_cost

- runs: rows whose outcome is pass or fail (the case executed); a skip,
  pending, unreported or not-run row is not a run.
- fails: rows whose outcome is fail; last_fail is the latest one's ts.
- median_secs: the median of the timed rows only. Only fleet rows carry
  seconds (the level drivers write "secs": null), so untimed rows are
  dropped, and only one server's times are used, never pooled across
  hardware: --server's, else the server most of the case's timed rows name.
  null when no row was timed.
- est_cost: runs x COST_PER_CASE_USD (default 0.20, the measured chunk
  median per case).

Sorted by (fails == 0, -median_secs, -runs): cases that fail first, then the
slowest, then the most run.

A level's gating case (harness.suite.OPENING_LEVELS, SE-F001 on security) is
left out: it is inlined into every chunk of its level, so its runs count
chunks rather than runs, and it is never a candidate to move or retire.

--candidates prints only cases with runs >= MIN_RUNS (default 4), no
failures, and median_secs >= MIN_SECS (default 300): the ones worth a
curator's look as slow and never failing. Evidence, not a verdict.

    python3 scripts/rank-cases.py [--level L] [--since DAYS] [--top N] [--json]
                                  [--candidates] [--server NAME] [--results-dir DIR]
"""

import argparse
import calendar
import json
import os
import statistics
import sys
import time
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO))

from harness.suite import OPENING_LEVELS  # noqa: E402

COLUMNS = ("case", "runs", "fails", "last_fail", "median_secs", "est_cost")
RAN = ("pass", "fail")


def parse_ts(ts):
    return calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))


def load(results_dir, level=None, since_days=None, now=None):
    """Every row of every <results_dir>/*.jsonl (one server's ledger; a
    subdirectory is another server's and is not read), filtered by level and
    age. A line that doesn't parse is skipped."""
    now = time.time() if now is None else now
    cutoff = None if since_days is None else now - float(since_days) * 86400
    rows = []
    for f in sorted(Path(results_dir).glob("*.jsonl")):
        for line in f.read_text(encoding="utf-8").splitlines():
            try:
                row = json.loads(line)
            except ValueError:
                continue
            if not isinstance(row, dict) or not row.get("case"):
                continue
            if level and row.get("level") != level:
                continue
            if cutoff is not None:
                try:
                    if parse_ts(row.get("ts", "")) < cutoff:
                        continue
                except (TypeError, ValueError):
                    continue
            rows.append(row)
    return rows


def _median_secs(rows, server):
    timed = [r for r in rows if r.get("secs") is not None]
    if not timed:
        return None
    if server is None:
        counts = Counter(r.get("server") for r in timed)
        server = sorted(counts, key=lambda s: (-counts[s], str(s)))[0]
    secs = [float(r["secs"]) for r in timed if r.get("server") == server]
    return round(statistics.median(secs), 1) if secs else None


def rank(rows, server=None, cost_per_case=None):
    cost = float(os.environ.get("COST_PER_CASE_USD") or 0.20) if cost_per_case is None else cost_per_case
    gates = set(OPENING_LEVELS.values())
    by_case = {}
    for r in rows:
        if r["case"] not in gates:
            by_case.setdefault(r["case"], []).append(r)
    out = []
    for case, rs in by_case.items():
        ran = [r for r in rs if r.get("outcome") in RAN]
        fails = [r for r in ran if r.get("outcome") == "fail"]
        out.append(
            {
                "case": case,
                "runs": len(ran),
                "fails": len(fails),
                "last_fail": max((r.get("ts", "") for r in fails), default=None),
                "median_secs": _median_secs(ran, server),
                "est_cost": round(len(ran) * cost, 2),
            }
        )
    out.sort(key=lambda r: (r["fails"] == 0, -(r["median_secs"] or 0), -r["runs"], r["case"]))
    return out


def candidates(rows, min_runs=None, min_secs=None):
    min_runs = int(os.environ.get("MIN_RUNS") or 4) if min_runs is None else min_runs
    min_secs = float(os.environ.get("MIN_SECS") or 300) if min_secs is None else min_secs
    return [
        r
        for r in rows
        if r["runs"] >= min_runs and r["fails"] == 0 and r["median_secs"] is not None and r["median_secs"] >= min_secs
    ]


def _cell(k, v):
    if v is None:
        return "-"
    if k == "est_cost":
        return f"{v:.2f}"
    return str(v)


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0], epilog=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--level")
    p.add_argument("--since", type=float, metavar="DAYS")
    p.add_argument("--top", type=int, metavar="N")
    p.add_argument("--json", action="store_true")
    p.add_argument("--candidates", action="store_true")
    p.add_argument("--server", help="read <results-dir>/<server>/ and use only that server's times")
    p.add_argument("--results-dir", default=str(REPO / "regression-results"))
    a = p.parse_args(argv)

    d = Path(a.results_dir)
    if a.server and (d / a.server).is_dir():
        d = d / a.server
    rows = rank(load(d, a.level, a.since), server=a.server)
    if a.candidates:
        rows = candidates(rows)
    if a.top is not None:
        rows = rows[: a.top]
    if a.json:
        print(json.dumps(rows))
        return 0
    if not rows and a.candidates:
        print(
            "no case has run MIN_RUNS times without a failure at a median of MIN_SECS or more"
            f" (MIN_RUNS={os.environ.get('MIN_RUNS') or 4}, MIN_SECS={os.environ.get('MIN_SECS') or 300};"
            " only fleet runs are timed)"
        )
        return 0
    print("\t".join(COLUMNS))
    for r in rows:
        print("\t".join(_cell(k, r[k]) for k in COLUMNS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
