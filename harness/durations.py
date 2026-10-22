"""How long a regression case takes, from the fleet's own past runs, so the
plan weighs work in time rather than in cases: on the 2026-10-18 `complete`
run a lane of eight validate-only cases and a lane of eight renders counted
the same.

Each finished run is kept in logs/fleet/runs/<id>.json, and every case a
session reported carries `secs` (from its REGRESSION-CASE marker to the
next one, or to the session's end) and the server it ran on. A reading is
normalised to primary-lane seconds by that server's `speed`, and a case's
estimate is the median of its last HISTORY readings. A case with no reading
gets the median of every case that has one, so with no history at all each
case weighs the same, as a plain count did.
"""

import json
import statistics
from pathlib import Path

HISTORY = 5
OUTCOMES = ("pass", "fail")  # a skip or a case not run took no case time


def readings(runs_dir, speeds):
    """{case: [primary-lane seconds, oldest first]} from every kept run.
    <speeds> is {server: speed}; a reading from a server not in it is dropped,
    since it can't be normalised."""
    out = {}
    for path in sorted(Path(runs_dir).glob("*.json")):  # ids are timestamps: oldest first
        try:
            cases = json.loads(path.read_text()).get("cases", {})
        except (OSError, ValueError, AttributeError):
            continue
        for case, d in cases.items():
            secs, speed = d.get("secs"), speeds.get(d.get("server"))
            if d.get("outcome") in OUTCOMES and isinstance(secs, (int, float)) and secs > 0 and speed:
                out.setdefault(case, []).append(secs * speed)
    return out


class Estimates:
    def __init__(self, by_case=None):
        self.by_case = {c: statistics.median(r[-HISTORY:]) for c, r in (by_case or {}).items() if r}
        self.default = statistics.median(self.by_case.values()) if self.by_case else 1.0

    @classmethod
    def load(cls, runs_dir, profile):
        return cls(readings(runs_dir, {s.name: s.speed for s in profile.servers}))

    def __call__(self, case):
        return self.by_case.get(case, self.default)

    def of(self, cases):
        return sum(self(c) for c in cases)

    @property
    def known(self):
        return len(self.by_case)
