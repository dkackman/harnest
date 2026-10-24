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


class Failures(unittest.TestCase):
    def test_failures_link_recorded_and_open_issues(self):
        calls = []

        def gh(args):
            calls.append(args)
            if args[:2] == ["issue", "list"] and "dkackman/harnest" in args:
                return [{"number": 130, "title": "suite: C-F091 - stale", "url": "h130", "state": "OPEN", "labels": []}]
            if args[:2] == ["issue", "list"]:
                return [
                    {
                        "number": 935,
                        "title": "C-F408 [minid]: catalog empty",
                        "url": "u935",
                        "state": "OPEN",
                        "labels": [],
                    },
                    {
                        "number": 940,
                        "title": "C-F408 and C-F091: same root",
                        "url": "u940",
                        "state": "OPEN",
                        "labels": [],
                    },
                ]
            return {
                "number": 12,
                "title": "C-F001 old",
                "url": "u12",
                "state": "CLOSED",
                "labels": [{"name": "owner:x"}],
            }

        cases = {
            "C-F408": {"level": "complete", "lane": "minid-1", "outcome": "fail", "issue": "#935"},
            "C-F091": {"level": "complete", "lane": "lem-1", "outcome": "fail"},
            "C-F001": {"level": "complete", "lane": "lem-2", "outcome": "fail", "issue": "#12"},
            "C-F002": {"level": "complete", "lane": "lem-2", "outcome": "pass", "issue": "#99"},
        }
        old, serve._gh = serve._gh, gh
        try:
            ri = serve.RegressionIssues()
            ri.failures(cases)  # starts the fetch
            for _ in range(100):
                if ri.fetched:
                    break
                serve.time.sleep(0.02)
            got = {r["case"]: [(i["number"], i.get("state")) for i in r["issues"]] for r in ri.failures(cases)["rows"]}
        finally:
            serve._gh = old
        self.assertEqual(
            {
                "C-F001": [(12, "closed")],
                "C-F091": [(940, "open"), (130, "open")],
                "C-F408": [(935, "open"), (940, "open")],
            },
            got,
        )
        self.assertEqual([["issue", "view", "12"]], [c[:3] for c in calls if c[0] == "issue" and c[1] == "view"])


class StreamIndexLock(unittest.TestCase):
    def test_concurrent_refreshes_count_each_session_once(self):
        import threading

        with tempfile.TemporaryDirectory() as d:
            log = Path(d) / "loop.log"
            log.write_text("".join(f"=== 09:00:{i % 60:02d} session {i} ===\n" for i in range(150)))
            idx = serve.StreamIndex(log)
            line = idx._line
            idx._line = lambda raw: (serve.time.sleep(0.001), line(raw))[1]  # a slow parse
            # a refresh that finds the lock held waits for it, then sees the other's work done
            idx.lock.acquire()
            ts = [threading.Thread(target=idx.refresh) for _ in range(2)]
            for t in ts:
                t.start()
            serve.time.sleep(0.1)
            self.assertEqual(0, len(idx.sessions), "a refresh ran without the lock")
            idx.lock.release()
            for t in ts:
                t.join()
            self.assertEqual(150, len(idx.sessions))
            self.assertEqual(log.stat().st_size, idx.offset)


if __name__ == "__main__":
    unittest.main()
