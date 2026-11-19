"""harness/drivers/loop.py: the loop driver's choices, without sessions (R17).
The end-to-end runs are tests/test-loop-py.sh."""

import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from harness import loop_state
from harness.deploy_policy import DeployGate
from harness.drivers import loop
from harness.log import Log
from harness.scheduler import Item, Pool, Scheduler


def mk(servers=("lem",), **env):
    old = {k: os.environ.get(k) for k in env}
    os.environ.update({k: str(v) for k, v in env.items()})
    try:
        lp = loop.Loop(["--servers", ",".join(servers)])
    finally:
        for k, v in old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
    d = tempfile.mkdtemp()
    for s in lp.servers_cfg:
        lp.srv[s.name] = loop.Srv(
            server=s,
            log=Log(os.path.join(d, f"loop{s.suffix}.log")),
            lock=os.path.join(d, f".driver.lock{s.suffix}"),
            source_dir=d,
            plugin_tree=d,
            lead_tree=d,
            url="http://x/mcp",
            token="t",
            gate=DeployGate(1),
        )
    lp.logs = Path(d)
    lp.state = loop_state.LoopState(os.path.join(d, "state.json"), list(lp.srv), poll_secs=lp.poll)
    lp.sched = Scheduler(Pool({s: 1 for s in lp.srv}, lp.free_slots))
    lp.hk_ready = True
    lp.task_last = time.time() - 1  # a gap of 0 has passed, any other has not
    return lp


class OfferTest(unittest.TestCase):
    def queues(self, lp):
        return [(i.queue, i.issue, i.server) for i in lp.offer()]

    def test_standing_task_when_lem_is_idle_and_nothing_is_queued(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        self.assertEqual(self.queues(lp), [("tester:task", None, "lem")])

    def test_no_task_while_anything_is_queued_for_lem(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.items = [Item("lead:design", 4, "lem")]
        self.assertNotIn("tester:task", [q for q, *_ in self.queues(lp)])

    def test_a_verify_waiting_for_a_deploy_counts_as_queued(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.items = [Item("tester:verify", 4, "lem")]
        lp.srv["lem"].waiting = [4]
        self.assertEqual(self.queues(lp), [])

    def test_no_task_before_the_gap(self):
        lp = mk(TESTER_TASK_GAP_SECS=3600)
        lp.task_last = time.time()
        self.assertEqual(self.queues(lp), [])

    def test_no_task_while_held(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.hold(lp.srv["lem"], "deploy")
        self.assertEqual(self.queues(lp), [])

    def test_closures_and_task_never_both(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.srv["lem"].closures = [7]
        self.assertEqual(self.queues(lp), [("tester:closures", None, "lem")])

    def test_no_closures_while_the_task_runs(self):
        lp = mk(TESTER_TASK_GAP_SECS=999999)
        lp.srv["lem"].closures = [7]
        lp.running["s1"] = loop.Running(Item("tester:task", None, "lem"), "lem", "s1", None, 0, Path("x"), Path("y"))
        self.assertEqual(self.queues(lp), [])

    def test_nothing_before_the_first_housekeeping(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.hk_ready = False
        lp.srv["lem"].closures = [7]
        lp.curator = [3]
        self.assertEqual(self.queues(lp), [])

    def test_curator_held_by_a_release_freeze(self):
        lp = mk()
        lp.curator = [3]
        self.assertEqual(self.queues(lp), [("curator", 3, "lem")])
        lp.srv["lem"].freeze = "#9 0.6.0"
        self.assertEqual(self.queues(lp), [])

    def test_design_held_by_dw_freeze(self):
        lp = mk()
        lp.items = [Item("lead:design", 4, "lem"), Item("implementer:fix", 5, "lem")]
        lp.srv["lem"].frozen = "1"
        self.assertEqual(self.queues(lp), [("implementer:fix", 5, "lem")])

    def test_unreadable_board_offers_nothing(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.readable = False
        self.assertEqual(self.queues(lp), [])

    def test_a_stopping_server_leaves_the_candidates(self):
        lp = mk(servers=("lem", "mini-ai"))
        lp.items = [Item("implementer:fix", 5, None, ("lem", "mini-ai")), Item("tester:verify", 6, "mini-ai")]
        lp.srv["lem"].stopping = True
        got = lp.offer()
        self.assertEqual(got, [Item("implementer:fix", 5, None, ("mini-ai",)), Item("tester:verify", 6, "mini-ai")])

    def test_cooldown(self):
        lp = mk(LOOP_POLL_SECS=60)
        lp.items = [Item("implementer:fix", 5, "lem")]
        lp.last_finish[("implementer:fix", 5)] = time.monotonic()
        self.assertEqual(self.queues(lp), [])
        lp.last_finish[("implementer:fix", 5)] = time.monotonic() - 61
        self.assertEqual(self.queues(lp), [("implementer:fix", 5, "lem")])
        # an issue-less item waits longer: nothing parks a closures session that keeps failing
        lp.srv["lem"].closures = [7]
        lp.last_finish[("tester:closures", None, "lem")] = time.monotonic() - 61
        self.assertNotIn("tester:closures", [q for q, *_ in self.queues(lp)])

    def test_only(self):
        lp = loop.Loop(["--servers", "lem", "--only", "lead:design"])
        self.assertEqual(lp.only, {"lead:design"})
        with self.assertRaises(loop.ProfileError):
            loop.Loop(["--only", "bogus"])


class PauseTest(unittest.TestCase):
    def test_rate_limit_pauses_until_the_reset_plus_a_minute(self):
        lp = mk()
        epoch = int(time.time()) + 30
        lp.rate_limited(epoch)
        self.assertEqual(lp.paused_until, epoch + 60)
        self.assertEqual(lp.sched.next_dispatches(), [])

    def test_a_reset_already_past_does_not_pause(self):
        lp = mk()
        lp.rate_limited(int(time.time()) - 120)
        self.assertEqual(lp.paused_until, 0.0)

    def test_no_reset_named_pauses_the_fallback(self):
        lp = mk(RATE_LIMIT_FALLBACK_SECS=300)
        t = time.time()
        lp.rate_limited(None)
        self.assertGreaterEqual(lp.paused_until, t + 299)


class HelpersTest(unittest.TestCase):
    def test_label(self):
        self.assertEqual(loop.label_of(Item("tester:verify", 4, "lem")), "tester:#4")
        self.assertEqual(loop.label_of(Item("curator", 9, "lem")), "curator:harnest#9")
        self.assertEqual(loop.label_of(Item("tester:task", None, "lem")), "tester:task")

    def test_argv(self):
        r = loop.Runner()
        self.assertEqual(r.argv(Item("lead:decompose", 4, "lem"))[2:], ["features", "lead:decompose", "4"])
        self.assertEqual(r.argv(Item("tester:closures", None, "lem"))[2:], ["tester-closures"])
        self.assertEqual(r.argv(Item("reviewer:arch", 3, "lem"))[2:], ["reviewer-arch", "reviewer:arch", "3"])
        self.assertEqual(r.argv(Item("tester:spec", 40, "lem"))[2:], ["tester", "tester:spec", "40"])
        self.assertEqual(r.argv(Item("curator", 8, "lem"))[2:], ["curator", "curator", "8"])

    def test_cost(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("x\nusage: turns=2 duration=1s cost=$0.25 ctx_peak=1k\nusage: turns=1 cost=$1.50\n")
        self.assertAlmostEqual(loop.cost_of(f.name), 1.75)
        self.assertIsNone(loop.cost_of("/nonexistent"))

    def test_knob(self):
        os.environ["LOOP_FREE_SLOTS"] = "x"
        try:
            with self.assertRaises(loop.ProfileError):
                loop.Loop(["--servers", "lem"])
        finally:
            del os.environ["LOOP_FREE_SLOTS"]
        lp = loop.Loop(["--servers", "lem"])
        self.assertEqual(
            (lp.free_slots, lp.poll, lp.health_secs, lp.retry_secs, lp.task_gap, lp.max_sessions),
            (3, 60, 30, 300, 5400, 0),
        )

    def test_suite_paths(self):
        lp = mk(servers=("lem", "mini-ai"))
        self.assertEqual(
            lp.suite_paths(lp.srv["lem"]), ["regression-suite-*.md", "regression-perf", "regression-results"]
        )
        self.assertEqual(
            lp.suite_paths(lp.srv["mini-ai"]),
            ["regression-suite-*.md", "regression-perf/mini-ai", "regression-results/mini-ai"],
        )


def stub_git(sleep_on="fetch", secs=30):
    """A git on PATH that hangs on <sleep_on> and runs the real git otherwise."""
    real = __import__("shutil").which("git")
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "git"), "w") as f:
        f.write(f'#!/bin/bash\ncase " $* " in *" {sleep_on} "*) sleep {secs}; exit 0 ;; esac\nexec {real} "$@"\n')
    os.chmod(os.path.join(d, "git"), 0o755)
    return mock.patch.dict(os.environ, {"PATH": d + os.pathsep + os.environ["PATH"]})


class FailedDeployTest(unittest.TestCase):
    """A failed deploy keeps gpu:S held through the retry window and the retry,
    and after a park until the server passes a preflight again."""

    def failing(self, lp, head="develop @ def5678"):
        srv = lp.srv["lem"]
        srv.deployed = "develop @ abc1234"
        lp.hold(srv, "deploy")
        srv.gate.set_state("deploying")
        srv.deploying = True
        lp.deployed(srv, False, head, 3)
        return srv

    def test_a_failed_deploy_keeps_the_gpu_held_and_forgets_the_head(self):
        lp = mk()
        srv = self.failing(lp)
        self.assertIn("deploy", srv.holds)
        self.assertEqual(srv.deployed, "unknown")
        lp.sched.offer([Item("tester:verify", 4, "lem")])
        self.assertEqual(lp.sched.next_dispatches(), [])

    def test_the_retry_runs_while_still_held(self):
        lp = mk()
        srv = self.failing(lp)
        srv.gate.retry_at = time.monotonic() - 1
        started = []
        lp._deploy = started.append
        lp.deploy_check()
        time.sleep(0.2)
        self.assertEqual(srv.gate.state, "deploying")
        self.assertEqual(started, [srv])
        self.assertIn("deploy", srv.holds)

    def test_no_retry_before_the_window(self):
        lp = mk()
        srv = self.failing(lp)
        srv.gate.retry_at = time.monotonic() + 60
        lp._deploy = lambda s: self.fail("deployed inside the retry window")
        lp.deploy_check()
        self.assertEqual(srv.gate.state, "failed")
        self.assertFalse(lp.quiet())  # a retry is due: --once waits for it
        self.assertIn("deploy", srv.holds)

    def test_ok_deploy_with_an_unreadable_head_is_a_failure(self):
        lp = mk()
        srv = lp.srv["lem"]
        with (
            mock.patch.object(loop.deploy, "run_deploy", return_value=(True, "unknown")),
            mock.patch.object(loop.deploy, "preflight", return_value="cuda on lem"),
        ):
            lp._deploy(srv)
        ev = lp.q.get_nowait()
        self.assertFalse(ev[2])
        lp.hold(srv, "deploy")
        srv.gate.set_state("deploying")
        lp.deployed(*ev[1:])
        self.assertIn("deploy", srv.holds)
        self.assertEqual(srv.gate.state, "failed")

    def test_the_hk_head_is_not_adopted_while_the_deploy_failed(self):
        lp = mk()
        srv = self.failing(lp)
        lp.apply_hk(hk(lp, deployed="develop @ def5678", gen=srv.deploy_gen))
        self.assertEqual(srv.deployed, "unknown")

    def test_parked_stays_held_until_a_preflight_passes(self):
        lp = mk()
        srv = self.failing(lp)
        srv.gate.set_state("deploying")
        lp.deployed(srv, False, "develop @ def5678", 3)  # the second failure parks
        self.assertTrue(srv.gate.parked)
        self.assertIn("deploy", srv.holds)
        lp.apply_hk(hk(lp, deployed="develop @ def5678", gen=srv.deploy_gen, preflight="no dw server answering"))
        self.assertIn("deploy", srv.holds)
        self.assertEqual(srv.deployed, "unknown")
        self.assertTrue(lp.quiet())  # parked: nothing comes by itself
        lp.apply_hk(hk(lp, deployed="develop @ def5678", gen=srv.deploy_gen, preflight=""))
        self.assertNotIn("deploy", srv.holds)
        self.assertEqual(srv.gate.state, "idle")
        self.assertEqual(srv.deployed, "develop @ def5678")
        lp.sched.offer([Item("tester:closures", None, "lem")])
        self.assertEqual(len(lp.sched.next_dispatches()), 1)

    def test_a_parked_server_is_preflighted_by_housekeeping(self):
        lp = mk()
        srv = self.failing(lp)
        srv.gate.set_state("deploying")
        lp.deployed(srv, False, "develop @ def5678", 3)
        lp.item_pass = lambda *a, **k: (0, "")
        with (
            mock.patch.object(loop.board, "query", return_value=""),
            mock.patch.object(loop.deploy, "deployed_head", return_value="develop @ def5678"),
            mock.patch.object(loop.deploy, "preflight", side_effect=loop.deploy.PreflightError("down")),
        ):
            res = lp.housekeeping()
        self.assertEqual(res["servers"]["lem"]["preflight"], "down")


def hk(lp, deployed=None, gen=0, preflight=None, freeze=None):
    r = {"frozen": None, "freeze": freeze, "closures": None, "gen": gen, "deployed": deployed}
    if preflight is not None:
        r["preflight"] = preflight
    return {"servers": {"lem": r}, "curator": None, "status": None}


class AnswerTriggersDeployTest(unittest.TestCase):
    def test_an_answer_waits_for_a_deploy_like_a_verify(self):
        lp = mk()
        srv = lp.srv["lem"]
        srv.deployed = "unknown"  # cannot tell: deploying is the safe side
        lp.items = [Item("tester:answer", 4, "lem")]
        started = []
        lp._deploy = started.append
        lp.deploy_check()
        self.assertEqual(srv.waiting, [4])
        self.assertIn("deploy", srv.holds)
        self.assertEqual([i.queue for i in lp.offer()], [])


class FakeRunner:
    def __init__(self):
        self.started = []

    def start(self, item, server, slot, env):
        self.started.append((item.queue, env["PLUGIN_TREE"]))
        return mock.MagicMock(stdout=[], wait=lambda: 0, returncode=0)


class PluginTreeTest(unittest.TestCase):
    def launch(self, lp, item, refresh):
        lp.runner = FakeRunner()
        lp._wait = lambda rec: None
        calls = []

        def fake(src, tree, branch="develop", timeout=None):
            calls.append(tree)
            return refresh(tree)

        with (
            mock.patch.object(loop, "refresh_plugin_tree", fake),
            mock.patch.object(loop.suite_tree, "make", return_value=mock.MagicMock(path="/t", base="b")),
        ):
            lp.sched.offer([item])
            for it, server in lp.sched.next_dispatches():
                lp.launch(it, server)
        return calls

    def test_free_tester_kinds_use_their_own_tree(self):
        lp = mk()
        calls = self.launch(lp, Item("tester:spec", 4, "lem"), lambda t: "abc")
        self.assertEqual(calls, [lp.srv["lem"].plugin_tree + "-free"])
        self.assertEqual(lp.runner.started, [("tester:spec", lp.srv["lem"].plugin_tree + "-free")])

    def test_a_verify_beside_a_running_spec_still_refreshes(self):
        lp = mk()
        self.launch(lp, Item("tester:spec", 4, "lem"), lambda t: "abc")
        calls = self.launch(lp, Item("tester:verify", 5, "lem"), lambda t: "def")
        self.assertEqual(calls, [lp.srv["lem"].plugin_tree])
        self.assertEqual(lp.runner.started, [("tester:verify", lp.srv["lem"].plugin_tree)])

    def test_a_parents_spec_and_its_stages_verify_are_separate_items(self):
        # the spec item runs only the spec (run-item.sh's exact filter); the
        # stage's verify is its own item, on the gpu slot, with its own argv
        from harness import board

        rows = board.parse("40\ttester:spec\t-\tneeds spec\t-\n41\ttester:verify\t40\thanded off\t-\n")
        items = board.items({"lem": rows})
        self.assertEqual([(i.queue, i.issue) for i in items], [("tester:spec", 40), ("tester:verify", 41)])
        lp = mk()
        lp.runner = FakeRunner()
        lp._wait = lambda rec: None
        argvs = []
        real = loop.Runner()
        with (
            mock.patch.object(loop, "refresh_plugin_tree", return_value="abc"),
            mock.patch.object(loop.suite_tree, "make", return_value=mock.MagicMock(path="/t", base="b")),
        ):
            lp.sched.offer(items)
            for it, server in lp.sched.next_dispatches():
                argvs.append(real.argv(it)[2:])
                lp.launch(it, server)
        self.assertEqual(sorted(argvs), [["tester", "tester:spec", "40"], ["tester", "tester:verify", "41"]])
        self.assertEqual(
            sorted(lp.runner.started),
            [("tester:spec", lp.srv["lem"].plugin_tree + "-free"), ("tester:verify", lp.srv["lem"].plugin_tree)],
        )
        self.assertFalse(lp.sched.gpu_idle("lem"))  # the verify holds gpu:lem

    def test_a_failed_refresh_defers_the_verify(self):
        lp = mk()
        calls = self.launch(lp, Item("tester:verify", 5, "lem"), lambda t: None)
        self.assertEqual(len(calls), 1)
        self.assertEqual(lp.runner.started, [])
        self.assertEqual(lp.running, {})
        self.assertTrue(lp.sched.gpu_idle("lem"))
        self.assertNotIn(("tester:verify", 5), lp.last_finish)  # offered again at the next wake
        self.assertIn("could not refresh", Path(lp.srv["lem"].log.path).read_text())
        calls = self.launch(lp, Item("tester:verify", 5, "lem"), lambda t: "def")
        self.assertEqual(lp.runner.started, [("tester:verify", lp.srv["lem"].plugin_tree)])


def _g(d, *a):
    import subprocess

    return subprocess.run(["git", "-C", str(d), *a], capture_output=True, text=True, check=True).stdout.strip()


class ReviewerTreeTest(unittest.TestCase):
    """Each reviewer item reads a tree of its own at origin/develop."""

    def setUp(self):
        d = Path(tempfile.mkdtemp())
        self.origin, self.src = d / "origin.git", d / "src"
        _g(d, "init", "-q", "--bare", str(self.origin))
        _g(d, "clone", "-q", str(self.origin), str(self.src))
        _g(self.src, "config", "user.email", "t@t")
        _g(self.src, "config", "user.name", "t")
        _g(self.src, "checkout", "-q", "-b", "develop")
        self.push("one")
        self.lp = mk()
        srv = self.lp.srv["lem"]
        srv.source_dir = str(self.src)
        srv.plugin_tree = str(d / "plugin")
        self.lp.runner = FakeRunner()
        self.lp._wait = lambda rec: None

    def push(self, what):
        (self.src / "f").write_text(what)
        _g(self.src, "add", "f")
        _g(self.src, "commit", "-q", "-m", what)
        _g(self.src, "push", "-q", "origin", "develop")
        return _g(self.src, "rev-parse", "HEAD")

    def start(self, item):
        self.lp.sched.offer([item])
        for it, server in self.lp.sched.next_dispatches():
            self.assertTrue(self.lp.launch(it, server))
        return [r for r in self.lp.running.values() if r.item == item][0]

    def test_overlapping_reviews_each_read_their_own_fresh_head(self):
        a = self.start(Item("reviewer:arch", 4, "lem"))
        head2 = self.push("two")
        b = self.start(Item("reviewer:docs", 5, "lem"))
        ta, tb = self.lp.runner.started[0][1], self.lp.runner.started[1][1]
        self.assertNotEqual(ta, tb)
        self.assertEqual((a.own_tree, b.own_tree), (ta, tb))
        self.assertEqual(_g(tb, "rev-parse", "HEAD"), head2)
        self.assertNotEqual(_g(ta, "rev-parse", "HEAD"), head2)  # a's tree is not reset under it
        a.proc.returncode = 0
        self.lp.ended(a)
        self.assertFalse(os.path.exists(ta))  # removed when its item ends
        self.assertEqual(_g(tb, "rev-parse", "HEAD"), head2)
        b.proc.returncode = 0
        self.lp.ended(b)
        self.assertFalse(os.path.exists(tb))
        self.assertNotIn(ta, _g(self.src, "worktree", "list"))

    def test_a_failed_fetch_defers_the_review(self):
        shutil_rm = __import__("shutil").rmtree
        shutil_rm(self.origin)
        item = Item("reviewer:arch", 4, "lem")
        self.lp.sched.offer([item])
        for it, server in self.lp.sched.next_dispatches():
            self.assertFalse(self.lp.launch(it, server))
        self.assertEqual(self.lp.runner.started, [])


class NightlyTest(unittest.TestCase):
    def setUp(self):
        self.lp = mk(REGRESSION_NIGHTLY_AT=23)
        self.ran = []
        self.lp.start_regression = self.ran.append
        self.busy = Item("tester:verify", 1, "lem")
        self.lp.sched.pool.take(self.busy, "lem")

    def at(self, stamp):
        self.lp.localtime = lambda: time.strptime(stamp, "%Y-%m-%d %H:%M")

    def test_due_before_midnight_runs_after_it(self):
        lp, srv = self.lp, self.lp.srv["lem"]
        self.at("2026-11-18 23:10")
        lp.nightly_check()
        self.assertTrue(srv.nightly_due)
        self.assertIn("regression", srv.holds)
        self.at("2026-11-19 00:20")
        lp.nightly_check()
        self.assertTrue(srv.nightly_due)
        self.assertEqual(self.ran, [])
        lp.sched.pool.release(self.busy, "lem")
        lp.nightly_check()
        self.assertEqual(self.ran, [srv])
        self.assertEqual((lp.logs / ".nightly-regression").read_text().strip(), "2026-11-18")

    def test_a_freeze_after_due_lets_go(self):
        lp, srv = self.lp, self.lp.srv["lem"]
        self.at("2026-11-18 23:10")
        lp.nightly_check()
        self.assertIn("regression", srv.holds)
        srv.freeze = "#9 0.6.0"
        lp.nightly_check()
        self.assertFalse(srv.nightly_due)
        self.assertNotIn("regression", srv.holds)
        lp.sched.pool.release(self.busy, "lem")
        lp.nightly_check()
        self.assertEqual(self.ran, [])


class StallTest(unittest.TestCase):
    def test_git_has_a_timeout(self):
        from harness.gitops import git

        with stub_git("status", 30):
            t = time.monotonic()
            p = git("status", timeout=1)
        self.assertLess(time.monotonic() - t, 10)
        self.assertEqual(p.returncode, 124)

    def test_a_hung_fetch_does_not_hang_the_deploy_check(self):
        lp = mk()
        lp.git_timeout = 1
        lp.items = [Item("tester:verify", 4, "lem")]
        lp._deploy = lambda s: None
        with stub_git("fetch", 30):
            t = time.monotonic()
            lp.deploy_check()
        self.assertLess(time.monotonic() - t, 10)

    def test_a_hung_plugin_refresh_is_bounded(self):
        from harness.gitops import refresh_plugin_tree

        with stub_git("fetch", 30):
            t = time.monotonic()
            self.assertIsNone(refresh_plugin_tree(tempfile.mkdtemp(), tempfile.mkdtemp() + "/t", timeout=1))
        self.assertLess(time.monotonic() - t, 10)

    def test_the_heartbeat_stops_when_the_main_loop_stalls(self):
        lp = mk(LOOP_POLL_SECS=1)
        lp.last_wake = time.monotonic()
        lp.wake_interval = 1
        lp.heartbeat_tick()
        self.assertTrue(os.path.exists(lp.state.path))
        os.unlink(lp.state.path)
        lp.hb_last_write = 0.0
        lp.last_wake = time.monotonic() - 10  # more than 3 polls without a wake
        lp.heartbeat_tick()
        self.assertFalse(os.path.exists(lp.state.path))
        self.assertIn("stalled", Path(lp.srv["lem"].log.path).read_text())

    def test_an_idle_backoff_is_not_a_stall(self):
        lp = mk(LOOP_POLL_SECS=1)
        lp.wake_interval = 60  # backed off while only Don's decisions are left
        lp.last_wake = time.monotonic() - 10
        lp.heartbeat_tick()
        self.assertTrue(os.path.exists(lp.state.path))


class MinorTest(unittest.TestCase):
    def test_a_cooling_closures_does_not_block_the_task(self):
        lp = mk(TESTER_TASK_GAP_SECS=0)
        lp.srv["lem"].closures = [7]
        lp.last_finish[("tester:closures", None, "lem")] = time.monotonic()
        self.assertEqual([(i.queue, i.server) for i in lp.offer()], [("tester:task", "lem")])

    def test_a_rejection_with_no_reset_pauses_once(self):
        lp = mk(RATE_LIMIT_FALLBACK_SECS=300)
        lp.rate_limited(None)
        first = lp.paused_until
        time.sleep(0.05)
        lp.rate_limited(None)
        self.assertEqual(lp.paused_until, first)
        self.assertEqual(Path(lp.srv["lem"].log.path).read_text().count("rate limit rejected"), 1)

    def test_a_released_server_shows_released(self):
        lp = mk(servers=("lem", "mini-ai"))
        lp.state.queues("mini-ai", {"tester:verify": [4]})
        lp.release(lp.srv["mini-ai"], "stop-after-cycle")
        lp.state.write()
        import json

        servers = json.loads(Path(lp.state.path).read_text())["servers"]
        s = servers["mini-ai"]
        self.assertEqual((s.get("released"), s["queues"], s["slots"]), (True, {}, []))
        self.assertNotIn("released", servers["lem"])

    def test_each_run_has_its_own_output_file(self):
        lp = mk()
        lp.runner = FakeRunner()
        lp._wait = lambda rec: None
        with mock.patch.object(loop, "refresh_plugin_tree", return_value="abc"):
            outs = []
            for n in (4, 5):
                lp.sched.offer([Item("implementer:fix", n, "lem")])
                for it, server in lp.sched.next_dispatches():
                    lp.launch(it, server)
                rec = lp.running.pop("s1")
                lp.sched.finished(rec.item, "lem", True)
                outs.append(rec.out)
        self.assertNotEqual(outs[0], outs[1])

