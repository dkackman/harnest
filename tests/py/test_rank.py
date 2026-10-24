"""scripts/rank-cases.py: one row per case from regression-results/, ranked
for the curator."""

import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from harness import REPO

SCRIPT = REPO / "scripts" / "rank-cases.py"
_spec = importlib.util.spec_from_file_location("rank_cases", SCRIPT)
rank = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rank)


def write(d, case, rows, level="smoke"):
    with open(Path(d, f"{case}.jsonl"), "a", encoding="utf-8") as f:
        for r in rows:
            row = {
                "ts": "2026-10-20T10:00:00Z",
                "level": level,
                "case": case,
                "outcome": "pass",
                "issue": None,
                "secs": None,
                "session": "regression:smoke.1 of 2",
                "head": "h",
                "model": "m",
                "server": "lem",
            }
            row.update(r)
            f.write(json.dumps(row) + "\n")


def run(d, *args, env=None):
    out = io.StringIO()
    old = dict(os.environ)
    os.environ.update(env or {})
    try:
        with redirect_stdout(out):
            rc = rank.main(["--results-dir", str(d), *args])
    finally:
        os.environ.clear()
        os.environ.update(old)
    return rc, out.getvalue()


class Rank(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def test_one_row_per_case_with_runs_fails_and_cost(self):
        write(
            self.d,
            "S-F001",
            [{"secs": 10}, {"secs": 30}, {"outcome": "fail", "issue": 9, "ts": "2026-10-21T00:00:00Z"}],
        )
        rows = rank.rank(rank.load(self.d))
        self.assertEqual(1, len(rows))
        r = rows[0]
        self.assertEqual(
            ["case", "runs", "fails", "last_fail", "median_secs", "est_cost"],
            list(r),
        )
        self.assertEqual(("S-F001", 3, 1, "2026-10-21T00:00:00Z", 20.0), tuple(list(r.values())[:5]))
        self.assertAlmostEqual(0.60, r["est_cost"])

    def test_failing_cases_first_then_slowest_then_most_run(self):
        write(self.d, "S-F001", [{"secs": 100}] * 2)
        write(self.d, "S-F002", [{"secs": 900}])
        write(self.d, "S-F003", [{"outcome": "fail", "secs": 5}])
        write(self.d, "S-F004", [{"secs": 100}] * 5)
        order = [r["case"] for r in rank.rank(rank.load(self.d))]
        self.assertEqual(["S-F003", "S-F002", "S-F004", "S-F001"], order)

    def test_untimed_rows_do_not_count_toward_the_median(self):
        write(self.d, "S-F001", [{"secs": None}] * 4 + [{"secs": 400}])
        self.assertEqual(400.0, rank.rank(rank.load(self.d))[0]["median_secs"])
        write(self.d, "S-F002", [{"secs": None}] * 4)
        self.assertIsNone([r for r in rank.rank(rank.load(self.d)) if r["case"] == "S-F002"][0]["median_secs"])

    def test_times_from_another_server_are_not_pooled(self):
        write(self.d, "S-F001", [{"secs": 100, "server": "lem"}] * 3 + [{"secs": 5000, "server": "mini-ai"}])
        self.assertEqual(100.0, rank.rank(rank.load(self.d))[0]["median_secs"])
        rows = rank.rank(rank.load(self.d), server="mini-ai")
        self.assertEqual(5000.0, rows[0]["median_secs"])

    def test_only_runs_that_executed_count(self):
        write(self.d, "S-F001", [{}, {"outcome": "skip"}, {"outcome": "unreported"}, {"outcome": "not run"}])
        self.assertEqual(1, rank.rank(rank.load(self.d))[0]["runs"])

    def test_the_security_gate_case_is_left_out(self):
        write(self.d, "SE-F001", [{"secs": 600}] * 9, level="security")
        write(self.d, "SE-F002", [{"secs": 600}] * 9, level="security")
        self.assertEqual(["SE-F002"], [r["case"] for r in rank.rank(rank.load(self.d))])

    def test_level_and_since_filter_rows(self):
        write(self.d, "S-F001", [{"ts": "2020-01-01T00:00:00Z"}, {}])
        write(self.d, "C-F001", [{}], level="complete")
        rows = rank.rank(rank.load(self.d, level="smoke", since_days=30, now=rank.parse_ts("2026-10-24T00:00:00Z")))
        self.assertEqual([("S-F001", 1)], [(r["case"], r["runs"]) for r in rows])

    def test_candidates_need_runs_no_failures_and_time(self):
        write(self.d, "S-F001", [{"secs": 400}] * 4)  # candidate
        write(self.d, "S-F002", [{"secs": 400}] * 3)  # too few runs
        write(self.d, "S-F003", [{"secs": 400}] * 4 + [{"outcome": "fail"}])  # failed
        write(self.d, "S-F004", [{"secs": 200}] * 4)  # fast
        write(self.d, "S-F005", [{"secs": None}] * 6)  # never timed
        rc, out = run(self.d, "--candidates", "--json")
        self.assertEqual(0, rc)
        self.assertEqual(["S-F001"], [r["case"] for r in json.loads(out)])
        rc, out = run(self.d, "--candidates", "--json", env={"MIN_RUNS": "3", "MIN_SECS": "100"})
        self.assertEqual(["S-F001", "S-F002", "S-F004"], [r["case"] for r in json.loads(out)])

    def test_cost_per_case_knob(self):
        write(self.d, "S-F001", [{}] * 4)
        rc, out = run(self.d, "--json", env={"COST_PER_CASE_USD": "0.5"})
        self.assertEqual(2.0, json.loads(out)[0]["est_cost"])

    def test_table_output_and_top(self):
        write(self.d, "S-F001", [{"secs": 10}])
        write(self.d, "S-F002", [{"secs": 20}])
        rc, out = run(self.d, "--top", "1")
        lines = out.splitlines()
        self.assertEqual("case\truns\tfails\tlast_fail\tmedian_secs\test_cost", lines[0])
        self.assertEqual(["S-F002\t1\t0\t-\t20.0\t0.20"], lines[1:])

    def test_no_candidates_says_so(self):
        rc, out = run(self.d, "--candidates")
        self.assertEqual(0, rc)
        self.assertIn("no case", out)

    def test_runs_as_a_script(self):
        write(self.d, "S-F001", [{}])
        p = subprocess.run(
            [sys.executable, str(SCRIPT), "--results-dir", self.d, "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(0, p.returncode, p.stderr)
        self.assertEqual("S-F001", json.loads(p.stdout)[0]["case"])


if __name__ == "__main__":
    unittest.main()
