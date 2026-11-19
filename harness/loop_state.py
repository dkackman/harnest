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
import threading
import time

from harness.scheduler import needs

SERIES_MAX = 720  # 6 h of samples at 30 s
PARKED = "(parked) "  # status_board's mark on a parked issue's title
AGENT_OWNERS = frozenset({"owner:implementer", "owner:tester", "owner:reviewer", "owner:lead"})


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

    def queues(self, server, queues):
        with self._lock:
            self._servers[server]["queues"] = {k: list(v) for k, v in queues.items()}

    def workers(self, server, workers):
        """The server's per-card list: [{"device", "busy", "job"}]."""
        with self._lock:
            self._servers[server]["workers"] = list(workers)

    def status(self, s):
        with self._lock:
            self._status = s

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
            owners = ["parked" if str(r[3]).startswith(PARKED) else r[2] for r in rows]
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
                if res != "free" and sv == server:
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
                v["slots"] = self._slots(name)
                servers[name] = v
            shared = []
            for item, sv, session in self._sessions:
                try:
                    if "free" in needs(item, sv):
                        shared.append({"resource": "free", "session": dict(session)})
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
            }

    def write(self):
        data = json.dumps(self.snapshot())
        with self._lock:  # one writer at a time: the tmp name is shared
            tmp = self.path + ".tmp"
            with open(tmp, "w") as f:
                f.write(data)
            os.replace(tmp, self.path)
