"""harness/drivers/loop.py: the loop driver's choices, without sessions (R17).
The end-to-end runs are tests/test-loop-py.sh."""

import os
import tempfile
import time
import unittest
from pathlib import Path

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
        self.assertEqual(r.argv(Item("lead:decompose", 4, "lem"))[2:], ["features", "4"])
        self.assertEqual(r.argv(Item("tester:closures", None, "lem"))[2:], ["tester-closures"])
        self.assertEqual(r.argv(Item("reviewer:arch", 3, "lem"))[2:], ["reviewer-arch", "3"])

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
            (3, 60, 30, 300, 8100, 0),
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
