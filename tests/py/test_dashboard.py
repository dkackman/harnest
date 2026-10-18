"""The dashboard's regression progress, read from a loop log the way
run-regression.sh and harness.drivers.regression write it."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("dash_serve", HERE / "dashboard" / "serve.py")
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)

LOG = """\
=== 09:00:00 regression run (anthropic/claude-sonnet-5-5, level=smoke, suite=/h/s.md, workspace=regression-smoke, target=lem, head=develop @ abc1234, 3 cases in sessions of 2) ===
--- 09:00:01 smoke session 1 of 2: S-F001 S-F002 ---
=== 09:00:01 regression:smoke.1 of 2 (anthropic/claude-sonnet-5-5) ===
[regression:smoke.1 of 2] model: claude-sonnet-5-5
[regression:smoke.1 of 2] REGRESSION-RESULT: S-F001 pass
[regression:smoke.1 of 2] REGRESSION-RESULT: S-F002 fail #12
[regression:smoke.1 of 2] usage: turns=9 duration=60s cost=$1.25 ctx_peak=40k in=1 cache_read=1 cache_write=1 out=1
--- 09:01:01 smoke session 2 of 2: S-F003 ---
[regression:smoke.2 of 2] REGRESSION-SKIP: S-F003 fixture x
[regression:smoke.2 of 2] usage: turns=3 duration=20s cost=$0.50 ctx_peak=20k in=1 cache_read=1 cache_write=1 out=1
--- 09:01:30 smoke session 3: final sweep ---
[regression:smoke.lem-1.4] usage: turns=1 duration=1s cost=$9.00 ctx_peak=1k in=1 cache_read=1 cache_write=1 out=1
[regression:smoke.sweep] usage: turns=2 duration=10s cost=$0.25 ctx_peak=10k in=1 cache_read=1 cache_write=1 out=1
=== 10:00:00 regression run (anthropic/claude-sonnet-5-5, level=complete, suite=/h/c.md, workspace=regression-complete, target=lem, head=develop @ def5678, 20 cases in sessions of 8) ===
--- 10:00:01 complete session 1 of 3: C-F001 C-F002 ---
[regression:complete.1 of 3] usage: turns=3 duration=20s cost=$0.50 ctx_peak=20k in=1 cache_read=1 cache_write=1 out=1
[regression:complete] session 1 aborted (MCP unreachable); skipping the rest of this level and the sweep
=== 11:00:00 regression run (anthropic/claude-sonnet-5-5, level=security.mini-ai, suite=/h/x.md, workspace=regression-security, target=mini-ai, head=develop @ 1) ===
=== 11:00:01 regression-mini-ai:security (anthropic/claude-sonnet-5-5) ===
[regression-mini-ai:security] usage: turns=30 duration=600s cost=$4.00 ctx_peak=90k in=1 cache_read=1 cache_write=1 out=1
"""


class Progress(unittest.TestCase):
    def test_runs_read_from_the_log(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "loop.log")
            p.write_text(LOG)
            idx = serve.StreamIndex(p)
            idx.refresh()
        smoke, complete, whole = idx.regression_runs
        self.assertEqual(("smoke", "lem", "develop @ abc1234"), (smoke["level"], smoke["target"], smoke["head"]))
        self.assertEqual(
            (3, 3, 3, "done"), (smoke["total"], smoke["cases_done"], smoke["sessions_done"], smoke["status"])
        )
        self.assertEqual({"S-F001": "pass", "S-F002": "fail"}, smoke["results"])
        self.assertEqual(1, smoke["skips"])
        self.assertEqual(2.0, smoke["cost"], "a fleet lane's session is not this run's")
        self.assertEqual((2, "aborted"), (complete["cases_done"], complete["status"]))
        self.assertEqual(
            ("security.mini-ai", None, "done", 4.0), (whole["level"], whole["total"], whole["status"], whole["cost"])
        )

    def test_a_newer_run_ends_an_unfinished_one(self):
        log = (
            LOG.split("[regression:smoke.1 of 2] model")[0]
            + LOG.split("--- 09:01:30 smoke session 3: final sweep ---\n")[1]
        )
        with tempfile.TemporaryDirectory() as d:
            p = Path(d, "loop.log")
            p.write_text(log)
            idx = serve.StreamIndex(p)
            idx.refresh()
        self.assertEqual("interrupted", idx.regression_runs[0]["status"])

    def test_python_drivers_are_drivers(self):
        m = serve.PY_DRIVER_RE.search(
            "/Library/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/"
            "Contents/MacOS/Python -m harness.drivers.fleet all"
        )
        self.assertEqual(("fleet", " all"), m.groups())
        self.assertIsNone(serve.PY_DRIVER_RE.search("python3 -m unittest discover"))


if __name__ == "__main__":
    unittest.main()
