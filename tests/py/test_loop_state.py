"""harness/loop_state.py: the loop's state.json writer (R17)."""

import json
import os
import tempfile
import threading
import unittest

from harness import loop_state as ls
from harness.scheduler import Item


class Clock:
    def __init__(self, t=1000.0):
        self.t = t

    def __call__(self):
        return self.t


def row(n, owner="owner:tester", title="t", status="status:fixed-pending-verify"):
    return [n, status, owner, title]


class LoopStateTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.path = os.path.join(self.dir.name, "state.json")
        self.clock = Clock()
        self.st = ls.LoopState(self.path, ["lem", "mini"], clock=self.clock)

    def read(self):
        self.st.write()
        with open(self.path) as f:
            return json.load(f)

    def test_write_is_atomic(self):
        self.st.board([row(i) for i in range(300)], True)
        self.st.write()
        stop = threading.Event()
        errors = []

        def reader():
            while not stop.is_set():
                try:
                    with open(self.path) as f:
                        json.load(f)
                except json.JSONDecodeError as e:
                    errors.append(e)
                except FileNotFoundError as e:
                    errors.append(e)

        t = threading.Thread(target=reader)
        t.start()
        for i in range(300):
            self.st.closed(i)
            self.st.write()
        stop.set()
        t.join()
        self.assertEqual(errors, [])
        self.assertEqual([f for f in os.listdir(self.dir.name)], ["state.json"])

    def test_board_history_only_on_change(self):
        self.st.board([row(1), row(2)], True)
        self.st.board([row(1), row(2)], True)
        self.assertEqual(len(self.read()["board"]["history"]), 1)
        self.clock.t += 5
        self.st.board([row(1), row(3, "owner:don")], True)
        h = self.read()["board"]["history"]
        self.assertEqual(len(h), 2)
        self.assertEqual(h[1]["closed"], 1)
        self.assertEqual(h[1]["agents"], 1)
        self.assertEqual(h[1]["don"], 1)
        self.assertEqual(h[1]["arrived"], 1)
        self.assertEqual(h[1]["time"], 1005.0)

    def test_parked_counts_as_parked(self):
        self.st.board([row(1, title="(parked) later"), row(2)], True)
        p = self.read()["board"]["history"][0]
        self.assertEqual((p["parked"], p["agents"]), (1, 1))

    def test_parked_behind_a_claim_mark_counts_as_parked(self):
        # status_board writes "[<loop>] (parked) <title>" on a claimed, parked issue
        rows = [row(1, "owner:don", title="[lem] (parked) idea"), row(2, "owner:don", title="[mini-ai] (parked) idea")]
        self.st.board(rows + [row(3, "owner:don", title="[lem] [docs] (parked) is in the title")], True)
        p = self.read()["board"]["history"][0]
        self.assertEqual((p["parked"], p["don"]), (2, 1))

    def test_unreadable_board_keeps_rows(self):
        self.st.board([row(1)], True)
        self.st.board([], False)
        b = self.read()
        self.assertFalse(b["board_readable"])
        self.assertEqual(len(b["board"]["rows"]), 1)
        self.assertEqual(len(b["board"]["history"]), 1)
        self.st.board([row(1)], True)
        self.assertTrue(self.read()["board_readable"])

    def test_gpu_integration(self):
        self.st.gpu_sample("lem", True, True)
        self.clock.t += 30
        self.st.gpu_sample("lem", True, False)
        self.clock.t += 30
        self.st.gpu_sample("lem", False, False)
        g = self.read()["gpu"]["lem"]
        self.assertEqual((g["slot_busy"], g["wall"], g["worker_busy"]), (60, 60, 30))
        self.assertEqual(g["series"][-1], {"t": 1060.0, "slot": 0, "worker": 0})

    def test_gpu_unknown_worker(self):
        self.st.gpu_sample("lem", True, None)
        self.clock.t += 30
        self.st.gpu_sample("lem", True, None)
        g = self.read()["gpu"]["lem"]
        self.assertEqual((g["slot_busy"], g["worker_busy"]), (30, 0))
        self.assertIsNone(g["series"][-1]["worker"])

    def test_gpu_series_capped(self):
        for _ in range(800):
            self.st.gpu_sample("lem", True, True)
            self.clock.t += 30
        self.assertEqual(len(self.read()["gpu"]["lem"]["series"]), 720)

    def test_cost_per_close(self):
        a, b = Item("tester:verify", 1, "lem"), Item("tester:verify", 2, "lem")
        for it in (a, b):
            self.st.session_started(it, "lem", "tester:#%d" % it.issue, "m", "loop.log")
            self.st.session_ended(it, "lem", 3.0)
        self.st.closed(2)
        t = self.read()["totals"]
        self.assertEqual((t["sessions"], t["cost"], t["closed"]), (2, 6.0, 2))

    def test_unknown_cost_not_added(self):
        a = Item("tester:verify", 1, "lem")
        self.st.session_started(a, "lem", "tester:#1", "m", "l")
        self.st.session_ended(a, "lem", None)
        t = self.read()["totals"]
        self.assertEqual((t["sessions"], t["cost"]), (1, 0))

    def test_slots(self):
        a = Item("implementer:fix", 7, "lem")
        c = Item("curator", None, None)
        self.st.session_started(a, "lem", "implementer:#7", "claude-x", "loop.log")
        self.st.session_started(c, None, "curator", "claude-y", "c.log")
        d = self.read()
        slots = {s["resource"]: s["session"] for s in d["servers"]["lem"]["slots"]}
        self.assertEqual(slots["gpu:lem"], None)
        self.assertEqual(
            slots["src:lem"],
            {
                "label": "implementer:#7",
                "kind": "implementer:fix",
                "issue": 7,
                "model": "claude-x",
                "started": 1000.0,
                "log": "loop.log",
                "cost_so_far": None,
            },
        )
        shared = d["shared"]["slots"]
        self.assertEqual({s["resource"] for s in shared}, {"free"})
        self.assertEqual(len(shared), 2)  # implementer holds free too, plus curator
        self.st.session_ended(a, "lem", 1.0)
        d = self.read()
        self.assertEqual(len(d["shared"]["slots"]), 1)
        self.assertTrue(all(s["session"] is None for s in d["servers"]["lem"]["slots"]))

    def test_deploy_heads_queues_status(self):
        self.st.deploy("lem", "waiting", [3, 4], {"at": 1, "head": "abc", "ok": True, "secs": 9})
        self.st.heads("lem", "a1", "b2")
        self.st.queues("lem", {"tester:verify": [3]})
        self.st.status("draining")
        d = self.read()
        s = d["servers"]["lem"]
        self.assertEqual(s["deploy"]["state"], "waiting")
        self.assertEqual(s["deploy"]["waiting"], [3, 4])
        self.assertTrue(s["deploy"]["last"]["ok"])
        self.assertEqual((s["deployed"], s["develop"]), ("a1", "b2"))
        self.assertEqual(s["queues"], {"tester:verify": [3]})
        self.assertEqual(d["status"], "draining")
        self.assertEqual(d["poll_secs"], 60)
        self.assertEqual(d["pid"], os.getpid())
        self.assertEqual(d["heartbeat"], 1000.0)
        self.assertEqual(d["started"], 1000.0)

    def test_suite_problems(self):
        self.assertEqual(self.read()["suite"], {"problems": []})
        self.st.suite_problem({"label": "tester:#4", "result": "conflict", "branch": "suite-conflict/item-s1"})
        self.assertEqual(self.read()["suite"]["problems"][0]["branch"], "suite-conflict/item-s1")
        for i in range(60):
            self.st.suite_problem({"label": str(i), "result": "stranded"})
        self.assertEqual(len(self.read()["suite"]["problems"]), ls.SUITE_MAX)

    def test_stopped_status(self):
        self.st.status("stopped")
        self.assertEqual(self.read()["status"], "stopped")

    def test_unknown_status_refused(self):
        with self.assertRaises(ValueError):
            self.st.status("sleeping")

    def test_snapshot_taken_under_the_write_lock(self):
        held = []
        st = self.st
        real = st.snapshot

        def probe():
            # another thread can't take the lock while write() snapshots
            t = threading.Thread(target=lambda: held.append(not st._lock.acquire(blocking=False) or st._lock.release()))
            t.start()
            t.join()
            return real()

        st.snapshot = probe
        st.write()
        self.assertEqual(held, [True])

    def test_deploy_keeps_last_when_omitted(self):
        self.st.deploy("lem", "idle", [], {"at": 1, "head": "x", "ok": False, "secs": 1})
        self.st.deploy("lem", "deploying", [])
        self.assertFalse(self.read()["servers"]["lem"]["deploy"]["last"]["ok"])

    def test_poll_secs_kwarg(self):
        s = ls.LoopState(self.path, ["lem"], clock=self.clock, poll_secs=15)
        s.write()
        with open(self.path) as f:
            self.assertEqual(json.load(f)["poll_secs"], 15)


class WorkersBusy(unittest.TestCase):
    # shaped like dw's /api/health (dw/server/api_models.py WorkerInfo)
    def w(self, job, device="cuda:0"):
        return {"device": device, "name": "RTX 4090", "vram_gb": 24.0, "current_job": job, "alive": True}

    def test_busy(self):
        self.assertIs(ls.workers_busy({"status": "ok", "workers": [self.w(None), self.w("j1", "cuda:1")]}), True)

    def test_idle(self):
        self.assertIs(ls.workers_busy({"status": "ok", "workers": [self.w(None)]}), False)

    def test_unknown_shape(self):
        for bad in (None, [], {}, {"workers": None}, {"workers": [{"device": "cuda:0"}]}, {"workers": ["x"]}):
            self.assertIsNone(ls.workers_busy(bad), bad)

    def test_empty_workers_unknown(self):
        self.assertIsNone(ls.workers_busy({"workers": []}))


if __name__ == "__main__":
    unittest.main()
