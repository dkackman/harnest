"""R17 loop scheduler core: resources, priority, reserved free slot, gpu hold.

Pure: no I/O, no subprocesses. The driver offers one board snapshot at a time,
asks for dispatches, starts the sessions, and reports back with finished().
lib/classify.jq decides who acts on what; this module decides when and where.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass

# Highest priority first (Global Constraints).
PRIORITY = (
    "reviewer:arch",
    "tester:verify",
    "tester:answer",
    "implementer:fix",
    "lead:build",
    "lead:closeout",
    "tester:spec",
    "lead:decompose",
    "lead:design",
    "reviewer:docs",
    "tester:handoff",
    "curator",
    "delegate:rule",
    "delegate:suite",
    "tester:closures",
    "tester:task",
)

# Work that feeds the GPU queue may use the reserved last `free` unit.
GPU_FEEDERS = frozenset({"reviewer:arch", "implementer:fix", "lead:build"})

_GPU = frozenset({"tester:verify", "tester:answer", "tester:task", "tester:closures", "regression"})
_FREE = frozenset({"tester:spec", "tester:handoff", "reviewer:arch", "reviewer:docs", "curator"})
# R19's escalation delegate reads only GitHub and a merged tree: it has a pool
# of its own (DELEGATE_SLOTS), so it neither waits for nor holds up the loops'
# free slots.
_DELEGATE = frozenset({"delegate:rule", "delegate:suite"})
_SRC = frozenset({"implementer:fix", "lead:build", "lead:closeout"})
_LEADTREE = frozenset({"lead:design", "lead:decompose"})


@dataclass(frozen=True)
class Item:
    queue: str
    issue: int | None
    server: str | None
    candidates: tuple = ()

    @property
    def key(self) -> tuple:
        # An item with no issue (closures, the standing task) is one per server.
        if self.issue is None:
            return (self.queue, None, self.server)
        return (self.queue, self.issue)


def needs(item: Item, server: str | None) -> frozenset:
    """Resource names the item needs on `server`.

    "regression" returns just gpu:<server> but Pool takes every gpu unit of it.
    "deploy" is not dispatched through the scheduler and raises ValueError.
    """
    q = item.queue
    if q in _DELEGATE:
        return frozenset({"delegate"})
    if q in _FREE:
        return frozenset({"free"})
    if q in _GPU or q in _SRC or q in _LEADTREE:
        if server is None:
            raise ValueError("queue %r needs a server" % q)
        if q in _GPU:
            return frozenset({"gpu:" + server})
        if q in _SRC:
            return frozenset({"src:" + server, "free"})
        return frozenset({"leadtree:" + server, "free"})
    raise ValueError("unknown queue %r" % q)


class Pool:
    def __init__(self, servers: dict, free_slots: int, delegate_slots: int = 0):
        self.cap = {"free": free_slots, "delegate": delegate_slots}
        self._reserve = free_slots >= 2
        for name, slots in servers.items():
            self.cap["gpu:" + name] = slots
            self.cap["src:" + name] = 1
            self.cap["leadtree:" + name] = 1
        self.servers = tuple(servers)
        self._holders = {}  # resource -> [(item, units)]

    def _used(self, res: str) -> int:
        return sum(u for _, u in self._holders.get(res, ()))

    def _units(self, item: Item, res: str) -> int:
        # regression takes every unit of the gpu resource
        if item.queue == "regression" and res.startswith("gpu:"):
            return self.cap[res]
        return 1

    def can_take(self, item: Item, server: str | None) -> bool:
        try:
            req = needs(item, server)
        except ValueError:
            return False
        for res in req:
            if res not in self.cap:
                return False
            units = self._units(item, res)
            avail = self.cap[res] - self._used(res)
            if item.queue == "regression" and res.startswith("gpu:"):
                if self._used(res):
                    return False
            if avail < units:
                return False
            if self._reserve and res == "free" and item.queue not in GPU_FEEDERS and avail < 2:
                return False
        return True

    def take(self, item: Item, server: str | None) -> None:
        if not self.can_take(item, server):
            raise ValueError("cannot take %r on %r" % (item.key, server))
        for res in needs(item, server):
            self._holders.setdefault(res, []).append((item, self._units(item, res)))

    def release(self, item: Item, server: str | None) -> None:
        for res in needs(item, server):
            held = self._holders.get(res, [])
            for i, (h, _) in enumerate(held):
                if h == item:
                    del held[i]
                    break
            if not held:
                self._holders.pop(res, None)

    def busy(self) -> dict:
        return {r: [i for i, _ in h] for r, h in self._holders.items() if h}


class Scheduler:
    def __init__(self, pool: Pool, clock: Callable[[], float] = time.monotonic):
        self.pool = pool
        self.clock = clock
        self._ready = []
        self._running = {}  # key -> (item, server)
        self._spent = set()  # keys finished since the last offer
        self._held = {}  # server -> reason
        self._pause = None

    def offer(self, items: list) -> None:
        self._ready = list(items)
        self._spent = set()

    @staticmethod
    def _rank(item: Item) -> tuple:
        if item.queue == "regression":
            return (-1, item.issue or 0)
        try:
            idx = PRIORITY.index(item.queue)
        except ValueError:
            idx = len(PRIORITY)
        return (idx, item.issue if item.issue is not None else 0)

    def _servers(self, item: Item) -> tuple:
        if item.server is not None:
            return (item.server,)
        return tuple(item.candidates) or self.pool.servers or (None,)

    def next_dispatches(self) -> list:
        if self._pause is not None and self.clock() < self._pause:
            return []
        out = []
        for item in sorted(self._ready, key=self._rank):
            if item.key in self._running or item.key in self._spent:
                continue
            for server in self._servers(item):
                if server in self._held and any(r.startswith("gpu:") for r in self._safe_needs(item, server)):
                    continue
                if self.pool.can_take(item, server):
                    self.pool.take(item, server)
                    self._running[item.key] = (item, server)
                    out.append((item, server))
                    break
        return out

    @staticmethod
    def _safe_needs(item: Item, server) -> frozenset:
        try:
            return needs(item, server)
        except ValueError:
            return frozenset()

    def finished(self, item: Item, server: str | None, ok: bool) -> None:
        if item.key in self._running:
            held, recorded = self._running.pop(item.key)
            self.pool.release(held, recorded)
        self._spent.add(item.key)

    def hold(self, server: str, reason: str) -> None:
        self._held[server] = reason

    def unhold(self, server: str) -> None:
        self._held.pop(server, None)

    def gpu_idle(self, server: str) -> bool:
        return not self.pool.busy().get("gpu:" + server)

    def pause_until(self, t: float) -> None:
        self._pause = t
