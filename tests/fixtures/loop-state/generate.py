"""Writes the loop-state fixtures by driving harness.loop_state.LoopState itself,
so they carry the producer's real shape. Run from the repo root:

    python3 tests/fixtures/loop-state/generate.py

Times are absolute (T0 = the clock at the last write); the dashboard tests and
the page check shift them to "now" instead of editing the files by hand.
"""

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2]))

from harness import loop_state as ls  # noqa: E402
from harness.scheduler import Item  # noqa: E402

T0 = 1763520000 + 6 * 3600


class Clock:
    t = 1763520000.0

    def __call__(self):
        return self.t


def build(name, servers=("lem", "mini-ai")):
    clock = Clock()
    st = ls.LoopState(str(HERE / (name + ".json")), list(servers), clock=clock, poll_secs=60)
    for s in servers:
        st.heads(s, "a1b2c3d", "a1b2c3d")
    # 6 h of samples every 30 s, busier in the middle
    for i in range(0, 721):
        clock.t = 1763520000.0 + i * 30
        for s in servers:
            slot = (i // 9) % 4 != 3
            worker = None if s == "mini-ai" else (slot and (i % 5) != 0)
            st.gpu_sample(s, slot, worker)
    clock.t = float(T0)
    st.board(
        [
            [1450, "status:fixed-pending-verify", "owner:tester", "t1"],
            [1449, "status:in-progress", "owner:implementer", "t2"],
        ],
        True,
    )
    clock.t = T0 + 1
    st.board([[1449, "status:in-progress", "owner:implementer", "t2"]], True)
    st.closed(3)
    st.status("running")
    return st, clock


def running(st, clock, live=True):
    clock.t = T0 - 12 * 60
    t1 = Item("tester:verify", 1450, "lem")
    st.session_started(t1, "lem", "tester:#1450", "claude-opus-5-5", "loop.log")
    clock.t = T0 - 6 * 60
    i1 = Item("implementer:fix", 1449, "lem")
    st.session_started(i1, "lem", "implementer:#1449", "claude-sonnet-5-5", "loop.log")
    clock.t = T0 - 4 * 60
    ld = Item("lead:decompose", 1448, None, ("lem", "mini-ai"))
    st.session_started(ld, "lem", "lead:#1448 decompose", "claude-opus-5-5", "loop.log")
    rv = Item("reviewer:arch", 1447, None, ("lem",))
    st.session_started(rv, "lem", "reviewer:#1447 arch", "claude-opus-5-5", "loop.log")
    for n in range(31):
        st.session_ended(Item("tester:verify", 1000 + n, "lem"), "lem", 58.4 / 31)  # no match: only totals move
    if not live:
        st._sessions.clear()  # a clean exit: its sessions ended
    st.queues(
        "lem", {"tester:verify": [1450], "implementer:fix": [1449, 1451], "lead:build": [], "lead:design": [1452]}
    )
    st.queues("mini-ai", {"tester:verify": [], "implementer:fix": [1460]})
    st.workers("lem", [{"device": "cuda:0", "busy": True, "job": "j1"}])
    clock.t = T0
    st.closed(6)


def finish(st, clock, name):
    clock.t = T0
    st.path = str(HERE / (name + ".json"))
    st.write()


def main():
    # the state file records the writer's pid; the tests substitute their own
    os.environ.setdefault("TZ", "UTC")
    for name in ("idle", "running", "deploying", "failed", "stalled", "rate-limited", "stopping", "stopped"):
        st, clock = build(name)
        if name != "idle":
            running(st, clock, live=name != "stopped")
        if name == "deploying":
            st.heads("lem", "a1b2c3d", "e4f5a6b7c8d9")
            st.deploy("lem", "draining", [1450, 1452])
            st.released("mini-ai")
        if name == "failed":
            st.heads("lem", "a1b2c3d", "e4f5a6b7c8d9")
            st.deploy("lem", "failed", [1452], {"at": T0 - 300, "head": "e4f5a6b", "ok": False, "secs": 212})
            st.suite_problem(
                {
                    "at": T0 - 600,
                    "label": "tester:#1450",
                    "issue": 1450,
                    "server": "lem",
                    "result": "stranded",
                    "branch": "suite/1450",
                }
            )
            st.suite_problem(
                {
                    "at": T0 - 500,
                    "label": "tester:#1444",
                    "issue": 1444,
                    "server": "mini-ai",
                    "result": "conflict",
                    "branch": "suite/1444",
                }
            )
        if name in ("running", "stalled"):
            st.deploy("lem", "idle", [], {"at": T0 - 3600, "head": "a1b2c3d", "ok": True, "secs": 95})
        if name == "rate-limited":
            st.status("paused-rate-limit")
        if name == "stopping":
            st.status("stopping")
        if name == "stopped":
            st.status("stopped")
        finish(st, clock, name)
    print("wrote", len(list(HERE.glob("*.json"))), "fixtures")


if __name__ == "__main__":
    main()
