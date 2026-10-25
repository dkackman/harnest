"""scripts/perf-check.py: the perf regression rule of
agents/regression/run-cases.md step 3, in code."""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from harness import REPO

SCRIPT = REPO / "scripts" / "perf-check.py"


def history(d, case, values, metric="latency", condition="cold"):
    with open(Path(d, f"{case}.jsonl"), "a", encoding="utf-8") as f:
        for v in values:
            f.write(
                json.dumps(
                    {
                        "ts": "2026-10-20T10:00:00Z",
                        "level": "smoke",
                        "case": case,
                        "metric": metric,
                        "condition": condition,
                        "value": v,
                        "unit": "s",
                        "server": None,
                        "model": "m",
                        "provider": "anthropic",
                        "ref": "job x",
                    }
                )
                + "\n"
            )


def check(d, *args):
    p = subprocess.run(
        [sys.executable, str(SCRIPT), *args, "--perf-dir", str(d)], capture_output=True, text=True, check=False
    )
    return p.returncode, p.stdout.strip()


class Wrapper(unittest.TestCase):
    def test_wrapper_runs_the_script(self):
        d = tempfile.mkdtemp()
        wrapper = REPO / "scripts" / "perf-check.sh"
        run = lambda *a: subprocess.run(
            [str(wrapper), *a, "--perf-dir", d], capture_output=True, text=True, check=False, cwd=d
        )  # noqa: E731
        self.assertEqual("insufficient history (0 prior)", run("S-P001", "latency", "cold", "9").stdout.strip())
        history(d, "S-P001", [10, 10, 10, 10, 10])
        p = run("S-P001", "latency", "cold", "16")
        self.assertEqual((3, True), (p.returncode, p.stdout.startswith("regression:")))
        self.assertEqual("ok", run("S-P001", "latency", "cold", "10").stdout.strip())


class PerfCheck(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def test_fifty_percent_over_recent_median_is_a_regression(self):
        history(self.d, "S-P001", [10, 10, 10, 10, 10])
        self.assertEqual((0, "ok"), check(self.d, "S-P001", "latency", "cold", "15"))  # exactly 50%: not over
        rc, out = check(self.d, "S-P001", "latency", "cold", "16")
        self.assertEqual(3, rc)
        self.assertEqual("regression: 16 is 60% over the median of the last 5 (10)", out)

    def test_creep_is_caught_by_the_all_time_median(self):
        # an old, fast history, then a slow creep the last 5 have absorbed
        history(self.d, "S-P001", [10] * 10 + [14, 15, 15, 16, 16])
        rc, out = check(self.d, "S-P001", "latency", "cold", "16")
        self.assertEqual(3, rc)
        self.assertEqual("regression: 16 is 60% over the median of all (10)", out)

    def test_two_prior_entries_record_only(self):
        history(self.d, "S-P001", [10, 10])
        self.assertEqual((0, "insufficient history (2 prior)"), check(self.d, "S-P001", "latency", "cold", "100"))
        self.assertEqual((0, "insufficient history (0 prior)"), check(self.d, "S-P404", "latency", "cold", "1"))

    def test_only_the_same_metric_and_condition_are_compared(self):
        history(self.d, "S-P001", [100] * 5, condition="warm")
        history(self.d, "S-P001", [10] * 2, condition="cold")
        history(self.d, "S-P001", [1] * 5, metric="bytes", condition="cold")
        self.assertEqual((0, "insufficient history (2 prior)"), check(self.d, "S-P001", "latency", "cold", "50"))

    def test_a_baseline_is_a_hard_ceiling(self):
        history(self.d, "S-P001", [10] * 5)
        rc, out = check(self.d, "S-P001", "latency", "cold", "12", "--baseline", "11")
        self.assertEqual(3, rc)
        self.assertEqual("regression: 12 is over the baseline (11)", out)
        self.assertEqual((0, "ok"), check(self.d, "S-P001", "latency", "cold", "11", "--baseline", "11"))
        history(self.d, "S-P002", [10])
        self.assertEqual(3, check(self.d, "S-P002", "latency", "cold", "12", "--baseline", "11")[0])

    def test_unparseable_lines_are_skipped(self):
        history(self.d, "S-P001", [10] * 3)
        with open(Path(self.d, "S-P001.jsonl"), "a") as f:
            f.write("not json\n")
        self.assertEqual((0, "ok"), check(self.d, "S-P001", "latency", "cold", "11"))


if __name__ == "__main__":
    unittest.main()
