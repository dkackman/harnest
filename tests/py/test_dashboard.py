"""The dashboard's regression progress, read from a loop log the way
run-regression.sh and harness.drivers.regression write it."""

import importlib.util
import json
import os
import sys
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


FIXTURES = HERE / "tests" / "fixtures" / "loop-state"
PAGE = (HERE / "dashboard" / "index.html").read_text()
DEAD_PID = 2**22 + 12345  # above the default pid_max on macOS and Linux


class LoopCard(unittest.TestCase):
    """The loop card's server half: state.json (written by harness.loop_state,
    see tests/fixtures/loop-state/generate.py) plus liveness."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name, "state.json")

    def put(self, name, pid=None, heartbeat_age=None, now=None):
        """Copy a fixture with a pid and a heartbeat `heartbeat_age` s before `now`."""
        d = json.loads((FIXTURES / f"{name}.json").read_text())
        now = now or 2_000_000_000.0
        d["pid"] = pid if pid is not None else os.getpid()
        if heartbeat_age is not None:
            d["heartbeat"] = now - heartbeat_age
        self.path.write_text(json.dumps(d))
        return now

    def loop(self, now):
        return serve.loop_state(self.path, now)

    def test_loop_live(self):
        now = self.put("running", heartbeat_age=10)
        lp = self.loop(now)
        self.assertEqual((True, False, "live"), (lp["live"], lp["stalled"], lp["health"]))
        self.assertEqual(("running", os.getpid()), (lp["status"], lp["pid"]))

    def test_loop_live_edge_is_twice_poll_secs(self):
        self.assertTrue(self.loop(self.put("running", heartbeat_age=120))["live"])  # poll_secs 60
        self.assertFalse(self.loop(self.put("running", heartbeat_age=121))["live"])

    def test_loop_stalled_old_heartbeat(self):
        now = self.put("stalled", heartbeat_age=600)
        lp = self.loop(now)
        self.assertEqual((False, True, "stalled"), (lp["live"], lp["stalled"], lp["health"]))
        self.assertEqual(now - 600, lp["heartbeat"], "the page says stalled since this time")

    def test_loop_stalled_dead_pid(self):
        now = self.put("running", pid=DEAD_PID, heartbeat_age=5)  # fresh heartbeat, nobody home
        lp = self.loop(now)
        self.assertEqual((False, True, "gone"), (lp["live"], lp["stalled"], lp["health"]))

    def test_stopped_is_neither_live_nor_stalled(self):
        for pid in (os.getpid(), DEAD_PID):
            lp = self.loop(self.put("stopped", pid=pid, heartbeat_age=86400))
            self.assertEqual((False, False, "stopped"), (lp["live"], lp["stalled"], lp["health"]), pid)

    def test_stopping_with_old_heartbeat_is_stopping_not_stalled(self):
        # SIGTERM wait_deploys: the heartbeat stops while the driver drains
        lp = self.loop(self.put("stopping", heartbeat_age=900))
        self.assertEqual(("stopping", False, False), (lp["health"], lp["stalled"], lp["live"]))
        # a dead pid mid-stop is a dead driver
        lp = self.loop(self.put("stopping", pid=DEAD_PID, heartbeat_age=900))
        self.assertEqual(("gone", True), (lp["health"], lp["stalled"]))

    def test_rate_limited_is_live(self):
        lp = self.loop(self.put("rate-limited", heartbeat_age=3))
        self.assertEqual(("live", "paused-rate-limit"), (lp["health"], lp["status"]))

    def test_loop_failed_deploy_passthrough(self):
        lp = self.loop(self.put("failed", heartbeat_age=3))
        self.assertEqual("failed", lp["servers"]["lem"]["deploy"]["state"])
        self.assertEqual([1452], lp["servers"]["lem"]["deploy"]["waiting"])
        self.assertEqual("stranded", lp["suite"]["problems"][0]["result"])

    def test_released_server_passthrough(self):
        lp = self.loop(self.put("deploying", heartbeat_age=3))
        self.assertTrue(lp["servers"]["mini-ai"]["released"])
        self.assertEqual("draining", lp["servers"]["lem"]["deploy"]["state"])

    def test_no_state_file(self):
        self.assertIsNone(serve.loop_state(self.path, 1.0))

    def test_unreadable_state_file_is_none(self):
        for junk in ("{not json", "[]", ""):
            self.path.write_text(junk)
            self.assertIsNone(serve.loop_state(self.path, 1.0), junk)

    def test_state_carries_loop_and_keeps_old_streams(self):
        old = serve.LOOP_STATE
        serve.LOOP_STATE = self.path
        try:
            self.assertIsNone(serve.state()["loop"])
            self.put("running", heartbeat_age=0, now=serve.time.time())
            st = serve.state()
        finally:
            serve.LOOP_STATE = old
        self.assertTrue(st["loop"]["live"])
        for k in ("drivers", "streams", "attention", "release"):
            self.assertIn(k, st)
        self.assertIn("loop_run", st["streams"]["lem"])
        self.assertIn("looping", st["streams"]["lem"])

    def test_fixtures_have_the_producers_shape(self):
        """A snapshot from LoopState today has the keys the committed files have."""
        spec = importlib.util.spec_from_file_location("gen", FIXTURES / "generate.py")
        gen = importlib.util.module_from_spec(spec)
        sys.path.insert(0, str(HERE))
        try:
            spec.loader.exec_module(gen)
        finally:
            sys.path.remove(str(HERE))
        st, clock = gen.build("shape")
        gen.running(st, clock)
        fresh = st.snapshot()
        files = sorted(FIXTURES.glob("*.json"))
        self.assertGreaterEqual(len(files), 6)
        for f in files:
            d = json.loads(f.read_text())
            self.assertEqual(sorted(fresh), sorted(d), f.name)
            for name, srv in d["servers"].items():
                want = set(fresh["servers"][name]) | ({"released"} if srv.get("released") else set())
                self.assertEqual(want, set(srv), f"{f.name} {name}")


class LoopPage(unittest.TestCase):
    """What can be checked without a browser: the page reads the new fields."""

    def test_page_reads_the_loop_fields(self):
        for needle in (
            "st.loop",
            "stalled since",
            "cost_so_far",
            "slot_busy",
            "worker_busy",
            "series",
            "waiting",
            "deploy",
            "queues",
            "problems",
            "released",
            "history",
            "totals",
            "heartbeat",
            "per close",
            "paused-rate-limit",
        ):
            self.assertIn(needle, PAGE, needle)

    def test_old_stream_views_stay(self):
        for needle in ("progress(name, s.loop_run, s.looping)", "drawBurn", "pollLog"):
            self.assertIn(needle, PAGE)


if __name__ == "__main__":
    unittest.main()
