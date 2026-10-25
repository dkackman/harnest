#!/usr/bin/env python3
"""Compares one performance reading against its case's history in
regression-perf/<case>.jsonl (format in regression-perf/README.md), by the
rule in agents/regression/run-cases.md step 3:

- only prior entries with the same metric and condition count;
- with --baseline (a human-set `baseline:`), a value over it is a
  regression, whatever the history: a hard ceiling;
- fewer than 3 prior entries: record only, no comparison;
- otherwise a regression when the value is more than 50% over the median
  of the last 5 entries, or more than 50% over the median of all of them
  (the second catches slow creep the last 5 have absorbed).

Prints one line and exits 0 (ok, or insufficient history) or 3 (regression):

    ok
    regression: <value> is N% over the median of the last 5 (<m5>)
    regression: <value> is N% over the median of all (<mall>)
    regression: <value> is over the baseline (<X>)
    insufficient history (<n> prior)

It reads only; appending the reading is still the caller's job.

    ./scripts/perf-check.sh <case> <metric> <condition> <value>
                                  [--perf-dir regression-perf] [--baseline X]
"""

import argparse
import json
import statistics
import sys
from pathlib import Path

MIN_PRIOR = 3
RECENT = 5
OVER = 1.5  # "more than ~50% over"


def prior(perf_dir, case, metric, condition):
    """The values of <case>'s entries with this metric and condition, in file
    order. A missing file is no history; a line that doesn't parse is skipped."""
    f = Path(perf_dir) / f"{case}.jsonl"
    if not f.is_file():
        return []
    out = []
    for line in f.read_text(encoding="utf-8").splitlines():
        try:
            row = json.loads(line)
            if row.get("metric") == metric and row.get("condition") == condition:
                out.append(float(row["value"]))
        except (ValueError, TypeError, KeyError, AttributeError):
            continue
    return out


def _n(x):
    return f"{x:g}"


def verdict(values, value, baseline=None):
    """(regression?, line) for <value> against the prior <values>."""
    if baseline is not None and value > baseline:
        return True, f"regression: {_n(value)} is over the baseline ({_n(baseline)})"
    if len(values) < MIN_PRIOR:
        return False, f"insufficient history ({len(values)} prior)"
    for label, m in (("the last 5", statistics.median(values[-RECENT:])), ("all", statistics.median(values))):
        if m > 0 and value > OVER * m:
            pct = round((value / m - 1) * 100)
            return True, f"regression: {_n(value)} is {pct}% over the median of {label} ({_n(m)})"
    return False, "ok"


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0], epilog=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("case")
    p.add_argument("metric")
    p.add_argument("condition")
    p.add_argument("value", type=float)
    p.add_argument("--perf-dir", default="regression-perf")
    p.add_argument("--baseline", type=float)
    a = p.parse_args(argv)
    bad, line = verdict(prior(a.perf_dir, a.case, a.metric, a.condition), a.value, a.baseline)
    print(line)
    return 3 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
