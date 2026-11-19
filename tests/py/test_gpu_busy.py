"""scripts/gpu-busy.py: the pre-R17 baseline (slot busy %, cadence, cost per close)."""

import datetime
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("gpu_busy", ROOT / "scripts" / "gpu-busy.py")
gb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gb)

FIXTURE = ROOT / "tests" / "fixtures" / "gpu-busy" / "loop.log"
ANCHOR = datetime.date(2026, 11, 18)


def usage(label, dur, cost):
    return f"[{label}] usage: turns=3 duration={dur}s cost=${cost} ctx_peak=1k in=1 cache_read=1k cache_write=1k out=1k"


class GpuBusy(unittest.TestCase):
    def test_rollover_assigns_days(self):
        sessions = gb.parse_sessions(FIXTURE.read_text().splitlines(), ANCHOR)
        self.assertEqual([s["date"] for s in sessions], [datetime.date(2026, 11, 17), datetime.date(2026, 11, 18)])
        self.assertEqual([s["role"] for s in sessions], ["tester", "regression"])

    def test_slot_busy_counts_tester_and_regression_only(self):
        lines = [
            "=== 01:00:00 cycle 1: tester:#1 (a/b) ===",
            usage("tester:#1", 600, "1.0"),
            "=== 02:00:00 regression run (opus) ===",
            usage("regression:smoke", 300, "1.0"),
            "=== 03:00:00 lead:#2 (a/b) ===",
            usage("lead:#2", 900, "1.0"),
        ]
        sessions = gb.parse_sessions(lines, ANCHOR)
        day = gb.per_day(sessions, {}, day_secs=3600)[ANCHOR]
        self.assertEqual(day["gpu_slot_busy_pct"], 25.0)
        self.assertEqual(day["cost"], 3.0)

    def test_standing_task_interval(self):
        lines = []
        for h in (1, 2, 3):
            lines += [f"=== 0{h}:00:00 cycle {h}: tester:task (a/b) ===", usage("tester:task", 20, "0.1")]
        day = gb.per_day(gb.parse_sessions(lines, ANCHOR), {})[ANCHOR]
        self.assertEqual(day["standing_task_interval_secs"], 3600)

    def test_partial_last_day_uses_elapsed_seconds(self):
        lines = [
            "=== 01:00:00 cycle 1: tester:#1 (a/b) ===",
            usage("tester:#1", 1800, "1.0"),
            "=== 02:00:00 cycle 2: tester:#2 (a/b) ===",
            usage("tester:#2", 1800, "1.0"),
        ]
        # first header 01:00 to the end of the last session 02:30 = 5400 s; busy 3600 s
        day = gb.per_day(gb.parse_sessions(lines, ANCHOR), {})[ANCHOR]
        self.assertEqual(day["gpu_slot_busy_pct"], 66.7)

    def test_earlier_days_keep_the_full_day(self):
        lines = [
            "=== 23:00:00 cycle 1: tester:#1 (a/b) ===",
            usage("tester:#1", 864, "1.0"),
            "=== 01:00:00 cycle 2: tester:#2 (a/b) ===",
            usage("tester:#2", 60, "1.0"),
        ]
        days = gb.per_day(gb.parse_sessions(lines, ANCHOR), {})
        self.assertEqual(days[datetime.date(2026, 11, 17)]["gpu_slot_busy_pct"], 1.0)

    def test_totals_count_closes_on_days_without_sessions_and_pool_gaps(self):
        import contextlib
        import io
        import json
        import os
        import tempfile
        from unittest import mock

        lines = []
        for h in (1, 2, 4):  # gaps 3600, 7200
            lines += [f"=== 0{h}:00:00 cycle {h}: tester:task (a/b) ===", usage("tester:task", 20, "0.1")]
        for hm in ("00:30:00", "00:40:00"):  # next day, gap 600
            lines += [f"=== {hm} cycle 9: tester:task (a/b) ===", usage("tester:task", 20, "0.1")]
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "loop.log")
            with open(log, "w") as f:
                f.write("\n".join(lines) + "\n")
            closes = {datetime.date(2000, 1, 1): 5, datetime.date.fromtimestamp(os.path.getmtime(log)): 2}
            out = io.StringIO()
            with mock.patch.object(gb, "fetch_closes", return_value=closes), contextlib.redirect_stdout(out):
                gb.main(["--log", log, "--repo", "x/y", "--json", "--days", "2"])
        t = json.loads(out.getvalue())["totals"]
        self.assertEqual(t["closes"], 2, "the 2000 close is outside the window")
        self.assertEqual(t["standing_task_interval_secs"], 3800, "pooled mean of 3600, 7200, 600")

    def test_cost_per_close(self):
        self.assertEqual(gb.cost_per_close(30.0, 6), 5.0)
        self.assertIsNone(gb.cost_per_close(30.0, 0))


if __name__ == "__main__":
    unittest.main()
