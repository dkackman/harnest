"""R17 loop state file: logs/loop/state.json, the dashboard's view of the loop.

The driver feeds it through the methods below on every event; write() renders
the whole file to a temp name and renames it, so a reader never sees a partial
file. A heartbeat calls write() every LOOP_POLL_SECS so "fresh" means "alive".
Pure stdlib; the lock lets the heartbeat thread write while the driver mutates.
"""

from __future__ import annotations

import copy
import json
import os
import re
import threading
import time

from harness.scheduler import needs

SERIES_MAX = 720  # 6 h of samples at 30 s
SUITE_MAX = 50  # suite landings kept for Don
# status_board's mark on a parked issue's title, after the "[<loop>] " claim mark when it has one
PARKED = re.compile(r"(\[[\w.-]+\] )?\(parked\) ")
AGENT_OWNERS = frozenset({"owner:implementer", "owner:tester", "owner:reviewer", "owner:lead"})
# "stopped" is the last word of a driver that exited cleanly; the dashboard
# tells it from a dead one (a stale heartbeat with another status).
STATUSES = ("running", "draining", "stopping", "paused-rate-limit", "paused-day-budget", "stopped")


def workers_busy(health):
    """True when any worker in /api/health's `workers` runs a job (its
    `current_job` is set), False when none does, None when the shape is unknown
    (no list, no entries, or an entry without the `current_job` key)."""
    if not isinstance(health, dict):
        return None
    workers = health.get("workers")
    if not isinstance(workers, list) or not workers:
        return None
    busy = False
    for w in workers:
        if not isinstance(w, dict) or "current_job" not in w:
            return None
        if w["current_job"]:
            busy = True
    return busy


class LoopState:
    def __init__(self, path: str, servers: list[str], clock=time.time, poll_secs: int = 60):
        self.path = path
        self.clock = clock
        self.poll_secs = poll_secs
        self._lock = threading.RLock()
        now = clock()
        self._started = now
        self._status = "running"
        self._servers = {
            s: {
                "deployed": None,
                "develop": None,
                "deploy": {"state": "idle", "waiting": [], "last": None},
                "workers": [],
                "queues": {},
            }
            for s in servers
        }
        self._sessions = []  # (item, server, session dict)
        self._rows = []
        self._readable = True
        self._history = []
        self._baseline = None
        self._seen = {}
        self._totals = {"sessions": 0, "cost": 0, "closed": 0}
        self._gpu = {}
        self._gpu_last = {}  # server -> (t, slot_busy, worker_busy)
        self._suite = []  # landings that left work on a branch for Don

    # -- sessions ---------------------------------------------------------
    def session_started(self, item, server, label, model, log):
        session = {
            "label": label,
            "kind": item.queue,
            "issue": item.issue,
            "model": model,
            "started": self.clock(),
            "log": log,
            "cost_so_far": None,
        }
        with self._lock:
            self._sessions.append((item, server, session))

    def session_ended(self, item, server, cost):
        with self._lock:
            for i, (it, sv, _) in enumerate(self._sessions):
                if it == item and sv == server:
                    del self._sessions[i]
                    break
            self._totals["sessions"] += 1
            if cost is not None:
                self._totals["cost"] = round(self._totals["cost"] + cost, 6)

    # -- per-server facts -------------------------------------------------
    def deploy(self, server, state, waiting, last=None):
        with self._lock:
            d = self._servers[server]["deploy"]
            d["state"] = state
            d["waiting"] = list(waiting)
            if last is not None:
                d["last"] = dict(last)

    def heads(self, server, deployed, develop):
        with self._lock:
            self._servers[server]["deployed"] = deployed
            self._servers[server]["develop"] = develop

    def released(self, server):
        """The driver no longer drives <server> (stop-after-cycle, a failed
        preflight): it shows as released, with nothing queued or held."""
        with self._lock:
            if server in self._servers:
                self._servers[server]["released"] = True
                self._servers[server]["queues"] = {}

    def queues(self, server, queues):
        with self._lock:
            self._servers[server]["queues"] = {k: list(v) for k, v in queues.items()}

    def workers(self, server, workers):
        """The server's per-card list: [{"device", "busy", "job"}]."""
        with self._lock:
            self._servers[server]["workers"] = list(workers)

    def status(self, s):
        if s not in STATUSES:
            raise ValueError(f"loop status {s!r} not in {STATUSES}")
        with self._lock:
            self._status = s

    def suite_problem(self, p):
        """A suite landing that did not land cleanly (suite_tree.land's
        "conflict" or "stranded"): {at, label, issue, server, result, branch}."""
        with self._lock:
            self._suite.append(dict(p))
            del self._suite[:-SUITE_MAX]

    def closed(self, n):
        with self._lock:
            self._totals["closed"] = n

    # -- board ------------------------------------------------------------
    def board(self, rows, readable):
        """rows: [number, status, owner, title]. An unreadable board keeps the
        last rows and adds no history (an empty read is not "all closed")."""
        with self._lock:
            self._readable = bool(readable)
            if not readable:
                return
            rows = [list(r) for r in rows]
            if self._baseline is None:
                self._baseline = {r[0] for r in rows}
            for r in rows:
                self._seen[r[0]] = r[3]
            if rows == self._rows and self._history:
                return
            self._rows = rows
            owners = ["parked" if PARKED.match(str(r[3])) else r[2] for r in rows]
            self._history.append(
                {
                    "time": self.clock(),
                    "closed": len(self._seen) - len(rows),
                    "agents": sum(o in AGENT_OWNERS for o in owners),
                    "don": owners.count("owner:don"),
                    "parked": owners.count("parked"),
                    "arrived": len(self._seen.keys() - self._baseline),
                }
            )
            del self._history[:-400]

    # -- gpu --------------------------------------------------------------
    def gpu_sample(self, server, slot_busy, worker_busy):
        """Integrates the previous sample's state over the time since it."""
        with self._lock:
            now = self.clock()
            g = self._gpu.setdefault(server, {"wall": 0, "slot_busy": 0, "worker_busy": 0, "series": []})
            last = self._gpu_last.get(server)
            if last is not None:
                dt = max(0, now - last[0])
                g["wall"] += dt
                if last[1]:
                    g["slot_busy"] += dt
                if last[2]:
                    g["worker_busy"] += dt
            self._gpu_last[server] = (now, bool(slot_busy), worker_busy)
            g["series"].append(
                {
                    "t": now,
                    "slot": int(bool(slot_busy)),
                    "worker": None if worker_busy is None else int(bool(worker_busy)),
                }
            )
            del g["series"][:-SERIES_MAX]

    # -- output -----------------------------------------------------------
    def _slots(self, server):
        held = {}
        for item, sv, session in self._sessions:
            try:
                resources = sorted(needs(item, sv))
            except ValueError:
                resources = []
            for res in resources:
                if res not in ("free", "delegate") and sv == server:
                    held.setdefault(res, []).append({"resource": res, "session": dict(session)})
        slots = []
        for res in ("gpu:" + server, "src:" + server):
            slots.extend(held.pop(res, None) or [{"resource": res, "session": None}])
        for res in sorted(held):
            slots.extend(held[res])
        return slots

    def snapshot(self):
        with self._lock:
            servers = {}
            for name, s in self._servers.items():
                v = copy.deepcopy(s)
                v["slots"] = [] if s.get("released") else self._slots(name)
                servers[name] = v
            shared = []
            for item, sv, session in self._sessions:
                try:
                    need = needs(item, sv)
                    if "free" in need:
                        shared.append({"resource": "free", "session": dict(session)})
                    elif "delegate" in need:
                        shared.append({"resource": "delegate", "session": dict(session)})
                except ValueError:
                    pass
            return {
                "pid": os.getpid(),
                "started": self._started,
                "heartbeat": self.clock(),
                "poll_secs": self.poll_secs,
                "status": self._status,
                "board_readable": self._readable,
                "servers": servers,
                "shared": {"slots": shared},
                "board": {"rows": copy.deepcopy(self._rows), "history": copy.deepcopy(self._history)},
                "totals": dict(self._totals),
                "gpu": copy.deepcopy(self._gpu),
                "suite": {"problems": copy.deepcopy(self._suite)},
            }

    def write(self):
        # One writer at a time (the tmp name is shared), and the snapshot is
        # taken under the same lock, so a heartbeat's older snapshot can never
        # land after the driver's newer one.
        with self._lock:
            data = json.dumps(self.snapshot())
            tmp = self.path + ".tmp"
            with open(tmp, "w") as f:
                f.write(data)
            os.replace(tmp, self.path)
