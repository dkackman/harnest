"""The R17 loop driver: one process drives every loop server (lem, mini-ai).

    python3 -m harness.drivers.loop [--servers lem,mini-ai] [--only QUEUE[,QUEUE]] [--once]

It replaces run-loop.sh's serial cycle with an event loop
(docs/superpowers/specs/2026-11-18-loop-scheduler-design.md). Each wake it
reads every server's board (lib/board.sh, lib/classify.jq), turns the ready
rows into work items (harness/board.py) and starts what harness/scheduler.py
says may run now: GPU sessions (verify, answer, closures, the standing task)
on the server's gpu slot, code and review sessions on minid's `free` slots,
side by side. Each item is one pass of run-loop.sh for one issue
(lib/run-item.sh, phase 1a), started by Runner, the seam phase 1b replaces
pass by pass. The driver:

- holds each server's .driver.lock<sfx> (owner "run-loop", which the bash
  passes and the other drivers read) and releases it when that server stops;
- owns every deploy: when a verify waits on a fix the server doesn't run
  (harness/deploy_policy.py), it stops handing out that server's gpu slot,
  waits for the running gpu sessions, deploys, preflights, and goes on;
- runs the nightly regression the same way, holding every gpu slot;
- gives each suite writer (tester, curator) its own harnest tree
  (harness/suite_tree.py) and lands it after the session;
- pauses every dispatch on a rejected rate limit, since every session shares
  the account;
- writes logs/loop/state.json (harness/loop_state.py) on every event, and from
  a heartbeat thread every LOOP_POLL_SECS.

Wakes: a child's exit, a deploy's end, a rate-limit line, a signal, or every
LOOP_POLL_SECS. Stops: SIGTERM/INT/HUP (sessions killed), logs/stop-after-
cycle<sfx> (that server, once its sessions end), DRAIN=1 (when drain_left
says done), MAX_SESSIONS (after that many, then drain), --once (each item at
most once, then exit when nothing more can start).
"""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from .. import REPO, board, deploy, lock, loop_state, outcome, session, suite_tree
from ..deploy_policy import DeployGate, head_sha, runnable_now, server_paths_changed
from ..gitops import git, refresh_plugin_tree
from ..log import Log, err, ts
from ..profile import ProfileError, load, resolve_token, resolve_url
from ..scheduler import PRIORITY, Item, Pool, Scheduler

RUN_ITEM = REPO / "lib" / "run-item.sh"
LOCK_NAME = "run-loop"  # shared_passes_here (lem_loop_running) and HARNEST_HELD_LOCK read it

# queue -> lib/run-item.sh pass
PASS = {
    "implementer:fix": "implementer",
    "lead:build": "lead",
    "lead:closeout": "lead",
    "lead:design": "features",
    "lead:decompose": "features",
    "tester:verify": "tester",
    "tester:answer": "tester",
    "tester:spec": "tester",
    "tester:handoff": "tester",
    "reviewer:arch": "reviewer-arch",
    "reviewer:docs": "reviewer-docs",
    "curator": "curator",
    "tester:closures": "tester-closures",
    "tester:task": "tester-task",
}
# The sessions that may edit a suite file run in a tree of their own.
SUITE_WRITERS = frozenset(q for q in PASS if q.startswith("tester:") or q == "curator")
# The tester loads the plugin tree (--plugin-dir); a reviewer reads a merged
# tree as its cwd. Each family has its own tree per server, refreshed to
# origin/develop before an item only while no other item of that family on
# the server runs (a refresh under a running session would change what it reads).
TREE_FAMILY = {
    q: ("tester" if q.startswith("tester:") else "reviewer") for q in PASS if q.startswith(("tester:", "reviewer:"))
}
# One closures-seen ledger per server: never both at once (task-5 report).
CLOSURE_KINDS = frozenset({"tester:closures", "tester:task"})
# A per-issue item that ended waits this long before it may run again (its
# session may have left it where it was: the no-progress ledger parks it);
# an issue-less one (closures, task) waits longer, since nothing parks it.
ISSUELESS_COOLDOWN = 900
# What a land of a session with no land note (its item failed) is committed as.
NO_NOTE = ("unknown (a loop item that left no land note)", "noreply@localhost")


def knob(name, default):
    v = os.environ.get(name)
    if v is None or v == "":
        return default
    try:
        n = int(v)
    except ValueError:
        raise ProfileError(f"{name} must be a whole number, got '{v}'") from None
    if n < 0:
        raise ProfileError(f"{name} must be a whole number, got '{v}'")
    return n


def role_model(role):
    tester = os.environ.get("TESTER_MODEL") or "claude-opus-5-5"
    return {
        "implementer": os.environ.get("IMPLEMENTER_MODEL") or "claude-sonnet-5-5",
        "tester": tester,
        "lead": os.environ.get("LEAD_MODEL") or tester,
        "reviewer": os.environ.get("REVIEWER_MODEL") or tester,
        "curator": os.environ.get("CURATOR_MODEL") or tester,
        "regression": os.environ.get("REGRESSION_MODEL") or "claude-sonnet-5-5",
    }.get(role, "")


def label_of(item):
    role = item.queue.split(":", 1)[0]
    if item.queue == "curator":
        return f"curator:harnest#{item.issue}"
    if item.issue is None:
        return f"{role}:{item.queue.split(':', 1)[-1]}"
    return f"{role}:#{item.issue}"


def cost_of(path):
    """The session's cost from its usage: line, or None."""
    try:
        text = Path(path).read_text(errors="replace")
    except OSError:
        return None
    cost = None
    for line in text.splitlines():
        i = line.find("usage: ")
        if i < 0:
            continue
        for tok in line[i:].split():
            if tok.startswith("cost=$"):
                try:
                    cost = (cost or 0) + float(tok[6:])
                except ValueError:
                    pass
    return cost


@dataclass
class Srv:
    """One loop server as the driver keeps it."""

    server: object
    log: Log
    lock: str
    source_dir: str
    plugin_tree: str
    lead_tree: str
    url: str
    token: str
    gate: DeployGate
    deployed: str = "unknown"
    develop: str = ""
    frozen: str | None = None  # "0"/"1" once read
    freeze: str | None = None  # release_freeze's output once read
    closures: list = field(default_factory=list)
    holds: set = field(default_factory=set)
    active: bool = True
    stopping: bool = False
    deploying: bool = False
    waiting: list = field(default_factory=list)
    last_deploy: dict | None = None
    parked_develop: str = ""
    nightly_due: bool = False
    regression: object = None
    deploy_gen: int = 0  # bumped at each deploy's start and end: an older head read is stale

    @property
    def name(self):
        return self.server.name

    @property
    def sfx(self):
        return self.server.suffix


@dataclass
class Running:
    item: Item
    server: str
    slot: str
    proc: subprocess.Popen
    started: float
    last: Path
    out: Path
    tree: object = None
    label: str = ""


class Runner:
    """Starts one work item as `lib/run-item.sh <pass> [<issue>]`, in its own
    process group, stdout and stderr on a pipe. The seam phase 1b replaces
    pass by pass with Python sessions."""

    def argv(self, item):
        args = ["bash", str(RUN_ITEM), PASS[item.queue]]
        if item.issue is not None:
            args.append(str(item.issue))
        return args

    def start(self, item, server, slot, env):
        return subprocess.Popen(
            self.argv(item),
            cwd=str(REPO),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )


class SuiteLock:
    """The `suite` token: one landing at a time in this process, and none at
    the same time as another driver's suite commit (logs/.suite-commit.lock,
    the protocol providers.sh and harness/suite.py use)."""

    def __init__(self, logs):
        self.path = os.path.join(logs, ".suite-commit.lock")
        self._mx = threading.Lock()

    def __enter__(self):
        self._mx.acquire()
        tries = 0
        while True:
            try:
                os.mkdir(self.path)
                return self
            except FileExistsError:
                tries += 1
                try:
                    old = time.time() - os.stat(self.path).st_mtime > 120
                except OSError:
                    old = False
                if tries >= 120 or old:
                    with contextlib.suppress(OSError):
                        os.rmdir(self.path)
                    tries = 0
                time.sleep(1)

    def __exit__(self, *exc):
        with contextlib.suppress(OSError):
            os.rmdir(self.path)
        self._mx.release()


def _descendants(pid):
    """Every live descendant of <pid> (ps), deepest last."""
    try:
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid="], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    kids = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) == 2 and f[0].isdigit() and f[1].isdigit():
            kids.setdefault(int(f[1]), []).append(int(f[0]))
    found, todo = [], [pid]
    while todo:
        for c in kids.get(todo.pop(), ()):
            found.append(c)
            todo.append(c)
    return found


def _alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _kill_hard(pid):
    with contextlib.suppress(ProcessLookupError, PermissionError):
        os.killpg(os.getpgid(pid), signal.SIGKILL)
    with contextlib.suppress(ProcessLookupError, PermissionError):
        os.kill(pid, signal.SIGKILL)


class Loop:
    def __init__(self, argv):
        ap = argparse.ArgumentParser(prog="python3 -m harness.drivers.loop")
        ap.add_argument("--servers", default="", help="comma-separated loop servers (default: every loop server)")
        ap.add_argument("--only", default="", help="comma-separated queues to dispatch (default: all)")
        ap.add_argument("--once", action="store_true", help="run each ready item at most once, then exit")
        a = ap.parse_args(argv)
        self.once = a.once
        self.only = frozenset(q for q in a.only.split(",") if q)
        bad = self.only - set(PASS)
        if bad:
            raise ProfileError(f"--only: unknown queue(s) {' '.join(sorted(bad))}; one of: {' '.join(PRIORITY)}")
        self.profile = load()
        loop_servers = [s for s in self.profile.servers if s.loop]
        if a.servers:
            names = [n for n in a.servers.split(",") if n]
            known = {s.name: s for s in loop_servers}
            for n in names:
                if n not in known:
                    raise ProfileError(f"--servers: '{n}' is not a loop server (one of: {' '.join(known)})")
            loop_servers = [known[n] for n in names]
        if not loop_servers:
            raise ProfileError("no loop server to drive")
        self.servers_cfg = loop_servers
        self.free_slots = knob("LOOP_FREE_SLOTS", 3)
        self.poll = max(1, knob("LOOP_POLL_SECS", 60))
        self.health_secs = max(1, knob("LOOP_HEALTH_SECS", 30))
        self.retry_secs = knob("DEPLOY_RETRY_SECS", 300)
        self.task_gap = knob("TESTER_TASK_GAP_SECS", 8100)
        self.max_sessions = knob("MAX_SESSIONS", 0)
        self.sleep_max = knob("SLEEP_MAX_SECS", 1800)
        self.session_kill = knob("SESSION_KILL_SECS", 10)
        self.child_kill = knob("CHILD_DRIVER_KILL_SECS", 30)
        self.rl_fallback = knob("RATE_LIMIT_FALLBACK_SECS", 300)
        self.drain = os.environ.get("DRAIN") or "0"
        if self.drain not in ("0", "1"):
            raise ProfileError(f"DRAIN must be 0 or 1, got '{self.drain}'")
        self.nightly_at = os.environ.get("REGRESSION_NIGHTLY_AT") or ""
        if self.nightly_at and not self.nightly_at.isdigit():
            raise ProfileError(f"REGRESSION_NIGHTLY_AT must be an hour 0-23, got '{self.nightly_at}'")
        self.nightly_level = (os.environ.get("REGRESSION_NIGHTLY_LEVEL") or "all").split()
        self.only_issues = {x for x in (os.environ.get("ONLY_ISSUES") or "").replace(",", " ").split() if x}
        self.logs = REPO / "logs"
        self.q = queue.Queue()
        self.running: dict[str, Running] = {}  # slot -> item
        self.srv: dict[str, Srv] = {}
        self.sessions = 0
        self.stop_signal = None
        self.last_finish = {}  # key -> time it ended
        self.done_keys = set()  # --once: keys that ran
        self.task_last = time.time()
        self.paused_until = 0.0
        self.hk_busy = False
        self.hk_last = 0.0
        self.snap_last = 0.0
        self.need_snapshot = True
        self.rows = {}
        self.items = []
        self.readable = True
        self.board_rows = None
        self.seen = set()
        self.idle_secs = self.poll
        self.prev_rows = None
        self.curator = []
        self.hk_ready = False
        self.gpu_busy = {}
        self.suite_problems = []
        self.runner = Runner()
        self._children = set()  # housekeeping and board processes running now
        self._children_mx = threading.Lock()

    # -- output ---------------------------------------------------------------
    def say(self, line, srv=None):
        (srv or self.primary_srv()).log.say(line)

    def primary_srv(self):
        for s in self.srv.values():
            if s.active:
                return s
        return next(iter(self.srv.values()))

    def active(self):
        return [s for s in self.srv.values() if s.active]

    # -- subprocesses ------------------------------------------------------------
    def env_for(self, srv, last=None):
        e = os.environ.copy()
        e.update(
            DW_TARGET=srv.name,
            DW_URL=srv.url,
            SOURCE_DIR=srv.source_dir,
            PLUGIN_TREE=srv.plugin_tree,
            LEAD_TREE=srv.lead_tree,
            DEPLOYED_HEAD=srv.deployed,
        )
        if srv.frozen in ("0", "1"):
            e["HARNEST_DW_FROZEN"] = srv.frozen
        else:
            e.pop("HARNEST_DW_FROZEN", None)
        if last:
            e["HARNEST_LAST_SESSION"] = last
        for k in ("HARNEST_SESSION_TREE", "HARNEST_SESSION_BASE", "HARNEST_HELD_LOCK", "HARNEST_ITEM"):
            e.pop(k, None)
        return e

    def sync(self, argv, env, timeout=600):
        """A short child (a housekeeping pass, a park): run to its end, in its
        own group, killed with the driver."""
        try:
            p = subprocess.Popen(
                argv,
                cwd=str(REPO),
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                text=True,
                errors="replace",
            )
        except OSError as e:
            return 127, str(e)
        with self._children_mx:
            self._children.add(p)
        try:
            out, _ = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(p.pid, signal.SIGKILL)
            out, _ = p.communicate()
            return 124, out
        finally:
            with self._children_mx:
                self._children.discard(p)
        return p.returncode, out

    def item_pass(self, srv, *args, slot="hk"):
        """A run-item.sh pass that runs no session (housekeeping, park,
        labels), to its end: (rc, output)."""
        last = f"logs/.last-session.item.{slot}{srv.sfx}"
        return self.sync(["bash", str(RUN_ITEM), *args], self.env_for(srv, last))

    def board_env(self, srv):
        return self.env_for(srv)

    # -- startup ---------------------------------------------------------------
    def start(self):
        for tool in ("claude", "gh", "jq"):
            if not shutil.which(tool):
                err(f"{tool} CLI not on PATH")
                return 1
        if subprocess.run(["gh", "auth", "status"], capture_output=True).returncode != 0:
            err("gh CLI not authenticated")
            return 1
        self.logs.mkdir(exist_ok=True)
        (self.logs / "loop").mkdir(exist_ok=True)
        dw_url = os.environ.get("DW_URL") or ""
        for s in self.servers_cfg:
            src = self._tree("SOURCE_DIR", self.profile.get("clones.source"), s)
            plug = self._tree("PLUGIN_TREE", self.profile.get("clones.plugin"), s)
            lead = self._tree("LEAD_TREE", "~/src/dkackman/dw-agent-lead", s)
            if not os.path.isdir(src):
                err(f"SOURCE_DIR not found for {s.name}: {src}")
                return 1
            try:
                url = resolve_url(s, dw_url if len(self.servers_cfg) == 1 else "")
                token = resolve_token(s)
            except ProfileError as e:
                err(str(e))
                return 1
            self.srv[s.name] = Srv(
                server=s,
                log=Log(str(self.logs / f"loop{s.suffix}.log")),
                lock=str(self.logs / f".driver.lock{s.suffix}"),
                source_dir=src,
                plugin_tree=plug,
                lead_tree=lead,
                url=url,
                token=token,
                gate=DeployGate(self.retry_secs),
            )
            self.gpu_busy[s.name] = False
        for srv in self.srv.values():
            lock.acquire(srv.lock, LOCK_NAME, srv.log.say, held="")
        for srv in self.srv.values():
            at = refresh_plugin_tree(srv.source_dir, srv.plugin_tree, self.branch())
            if at is None and not os.path.isdir(os.path.join(srv.plugin_tree, ".git")):
                err(f"could not create/refresh the plugin worktree {srv.plugin_tree} from {srv.source_dir}")
                return 1
            # the claim and backend labels, once (items no longer make them)
            rc, out = self.item_pass(srv, "labels")
            if rc != 0:
                srv.log.say(
                    f"[loop] WARNING: run-item.sh labels exited {rc}: {' | '.join(out.strip().splitlines()[-3:])}"
                )
            srv.deployed = deploy.deployed_head(srv.server)
            if not self.preflight(srv, startup=True):
                self.release(srv, "its preflight failed")
        if not self.active():
            err("no loop server passed its preflight")
            return 1
        self.state = loop_state.LoopState(
            str(self.logs / "loop" / "state.json"), [s.name for s in self.active()], poll_secs=self.poll
        )
        names = " ".join(s.name for s in self.active())
        self.say(
            f"[loop] {ts()} the R17 loop driver (pid {os.getpid()}) drives: {names}; "
            f"free slots {self.free_slots}, poll {self.poll}s{' --once' if self.once else ''}"
            + (f", only {','.join(sorted(self.only))}" if self.only else "")
        )
        self.sched = Scheduler(
            Pool({s.name: s.server.loop_gpu_slots for s in self.active()}, self.free_slots), clock=time.monotonic
        )
        return 0

    def branch(self):
        return self.profile.get("integration_branch", "develop")

    def _tree(self, knob_name, default, s):
        """A clone's path: the knob names lem's (the primary's), and another
        server's takes its clone suffix (-mini-ai), as run-loop.sh's tsfx."""
        v = os.environ.get(knob_name)
        if v:
            return os.path.expanduser(v + ("" if s.primary else s.clone_suffix))
        return os.path.expanduser(default + s.clone_suffix)

    def preflight(self, srv, startup=False):
        """harness.deploy.preflight for the server. At startup a secondary that
        doesn't answer gets develop deployed once first (a test bed left
        stopped), as run-loop.sh did; a primary that fails only warns there."""
        why = self._preflight(srv)
        if why and startup and not srv.server.primary and deploy.health(srv.url, srv.token) is None:
            srv.log.say(f"[loop] no server answering at {srv.url}; deploying develop to {srv.server.host}")
            deploy.run_deploy(srv.server, srv.log.say, self.branch(), str(self.logs))
            srv.deployed = deploy.deployed_head(srv.server)
            why = self._preflight(srv)
        if not why:
            return True
        srv.log.say(f"[loop] WARNING: {srv.name} preflight: {why}")
        return startup and srv.server.primary

    def _preflight(self, srv):
        try:
            srv.log.say(f"[loop] {srv.name} preflight: {deploy.preflight(srv.server, srv.url, srv.token)}")
            return ""
        except deploy.PreflightError as e:
            return str(e)

    def release(self, srv, why):
        srv.active = False
        lock.release(srv.lock)
        srv.log.say(f"[loop] {srv.name}: no longer driven ({why}); its lock is released")

    # -- the board ---------------------------------------------------------------
    def snapshot(self):
        rows = {}
        for srv in self.active():
            if srv.stopping:
                continue
            rows[srv.name] = board.snapshot(srv.name, self.board_env(srv))
        self.rows = rows
        was = self.readable
        self.readable = bool(rows) and all(r is not None for r in rows.values())
        if not self.readable and was:
            bad = " ".join(n for n, r in rows.items() if r is None)
            self.say(f"[loop] could not read the issue board ({bad}); nothing new starts until it reads")
        elif self.readable and not was:
            self.say("[loop] the issue board reads again")
        items = board.items(rows)
        if self.only_issues:
            parents = {r.number: r.parent for rs in rows.values() for r in rs or ()}
            items = [
                i for i in items if str(i.issue) in self.only_issues or str(parents.get(i.issue)) in self.only_issues
            ]
        self.items = items
        self.snap_last = time.monotonic()
        self.need_snapshot = False
        if self.prev_rows is not None and rows != self.prev_rows:
            self.idle_secs = self.poll
        self.prev_rows = rows

    # -- housekeeping (a thread: gh calls and bash, never on the dispatch path) --
    def housekeeping(self):
        """Once a poll, in a thread: park_external_issues, unpark_pass and
        consolidation_pass on the first server (they are shared); per server
        dw_frozen, release_freeze, pending_closures and the deployed head; on
        the first, curator_requests and the status board for state.json."""
        srvs = [s for s in self.active() if not s.stopping]
        if not srvs:
            return {"servers": {}, "curator": None, "status": None}
        lead = srvs[0]
        rc, out = self.item_pass(lead, "housekeeping")
        if rc != 0:
            lead.log.say(f"[loop] WARNING: housekeeping exited {rc}: {' | '.join(out.strip().splitlines()[-3:])}")
        res = {"servers": {}, "curator": None, "status": None}
        for srv in srvs:
            gen = srv.deploy_gen
            r = {"frozen": None, "freeze": None, "closures": None, "gen": gen}
            text = board.query("hk", srv.name, self.board_env(srv), *(["lead"] if srv is lead else []))
            if text is not None:
                status, unreadable = [], False
                for line in text.splitlines():
                    k, _, v = line.partition("\t")
                    if k in ("frozen", "freeze", "closures") or (k == "curator" and srv is lead):
                        r[k] = v.strip()
                    elif k == "status":
                        status.append(v)
                    elif k == "status-unreadable":
                        unreadable = True
                if srv is lead:
                    res["curator"] = r.pop("curator", None)
                    res["status"] = None if unreadable else "\n".join(status)
            r["deployed"] = None if srv.deploying else deploy.deployed_head(srv.server)
            res["servers"][srv.name] = r
        return res

    def start_hk(self):
        self.hk_busy = True
        self.hk_last = time.monotonic()
        self.hk_thread = threading.Thread(target=self._hk_thread, daemon=True)
        self.hk_thread.start()

    def _hk_thread(self):
        try:
            self.q.put(("hk", self.housekeeping()))
        except Exception as e:  # noqa: BLE001 - the loop runs unattended
            self.q.put(("hk-error", repr(e)))

    def apply_hk(self, res):
        self.hk_busy = False
        self.hk_ready = True
        for name, r in res["servers"].items():
            srv = self.srv.get(name)
            if srv is None or not srv.active:
                continue
            if r["frozen"] in ("0", "1"):
                if srv.frozen != r["frozen"] and r["frozen"] == "1":
                    srv.log.say("[loop] dw stabilization freeze: docs/stabilization/FREEZE is on develop")
                srv.frozen = r["frozen"]
            if r["freeze"] is not None:
                fz = r["freeze"].strip()
                if fz != (srv.freeze or "") and fz:
                    srv.log.say(
                        "[loop] board unreadable: a release freeze is possible"
                        if fz == "UNKNOWN"
                        else f"[loop] release freeze {fz}: only release-blocker issues move"
                    )
                srv.freeze = fz
            if r["closures"] is not None:
                srv.closures = board.numbers(r["closures"])
            if r["deployed"] and not srv.deploying and r["gen"] == srv.deploy_gen and head_sha(r["deployed"]):
                srv.deployed = r["deployed"]
        if res["curator"] is not None:
            self.curator = board.numbers(res["curator"])
        if res["status"] is not None:
            rows = board.status_rows(res["status"])
            if rows != self.board_rows:
                self.print_board(rows)
            self.board_rows = rows
            for r in rows:
                self.seen.add(r[0])
            self.state.board(rows, True)
            self.state.closed(len(self.seen - {r[0] for r in rows}))

    def print_board(self, rows):
        srv = self.primary_srv()
        lines = [f"--- {ts()} tickets, {' '.join(s.name for s in self.active())} ---"]
        lines += [f"  #{n:<4} {st:<24} {ow:<18} {t}" for n, st, ow, t in rows]
        for rs in list(self.rows.values())[:1]:
            for r in rs or ():
                if r.queue == "stranded":
                    lines.append(f"  STRANDED #{r.number}: {r.reason}")
        for p in self.suite_problems[-5:]:
            lines.append(f"  SUITE {p['result'].upper()} {p['label']}: kept on {p.get('branch') or 'a branch'} for Don")
        for line in lines:
            srv.log.say(line)

    # -- what to offer -----------------------------------------------------------
    def cooling(self, key):
        t = self.last_finish.get(key)
        if t is None:
            return False
        wait = ISSUELESS_COOLDOWN if key[1] is None else self.poll
        return time.monotonic() - t < wait

    def offer(self):
        """The items the scheduler may start now, in board order."""
        if not self.readable:
            return []
        out = []
        verify_wait = set()
        for srv in self.active():
            verify_wait.update((srv.name, n) for n in srv.waiting)
        running_kinds = {(r.server, r.item.queue) for r in self.running.values()}
        stopping = {s.name for s in self.srv.values() if s.stopping or not s.active}
        lem_queued = False
        for it in self.items:
            if it.queue == "tester:verify" and (it.server, it.issue) in verify_wait:
                continue  # waits for a deploy
            if it.queue in ("lead:design", "lead:decompose"):
                srv = self.srv.get(it.server) if it.server else None
                if srv is not None and srv.frozen == "1":
                    continue  # features_pass holds them in a stabilization freeze
            if it.server in stopping:
                continue
            if it.server is None:
                cands = tuple(c for c in it.candidates if c not in stopping)
                if not cands:
                    continue
                it = Item(it.queue, it.issue, None, cands)
            out.append(it)
        primary = self.profile.servers[0].name
        for it in self.items:  # waiting for a deploy counts: it is queued
            if it.server == primary or primary in it.candidates:
                lem_queued = True
        for srv in self.active():
            if srv.stopping or not self.hk_ready:
                continue
            if srv.closures and (srv.name, "tester:task") not in running_kinds:
                if not self.only_issues or any(str(n) in self.only_issues for n in srv.closures):
                    out.append(Item("tester:closures", None, srv.name))
        lead = self.primary_srv()
        if self.hk_ready and self.curator and not lead.stopping and not (lead.freeze or ""):
            for n in self.curator:
                if not self.only_issues or str(n) in self.only_issues:
                    out.append(Item("curator", n, lead.name))
        lemsrv = self.srv.get(primary)
        if (
            lemsrv is not None
            and lemsrv.active
            and not lemsrv.stopping
            and self.hk_ready
            and not (lemsrv.freeze or "")
            and not lem_queued
            and not lemsrv.holds
            and self.sched.gpu_idle(primary)
            and (primary, "tester:closures") not in running_kinds
            and not any(i.queue == "tester:closures" and i.server == primary for i in out)
            and time.time() - self.task_last >= self.task_gap
        ):
            out.append(Item("tester:task", None, primary))
        out = [i for i in out if not self.only or i.queue in self.only]
        out = [i for i in out if not self.cooling(i.key) and i.key not in self.done_keys]
        return out

    # -- dispatch ----------------------------------------------------------------
    def free_slot(self):
        n = 1
        while f"s{n}" in self.running:
            n += 1
        return f"s{n}"

    def dispatch(self):
        if self.max_sessions and self.sessions >= self.max_sessions:
            return 0
        if self.stop_signal:
            return 0
        self.sched.offer(self.offer())
        started = 0
        for item, server in self.sched.next_dispatches():
            if self.max_sessions and self.sessions >= self.max_sessions:
                self.sched.finished(item, server, False)
                continue
            if self.launch(item, server):
                started += 1
        return started

    def launch(self, item, server):
        srv = self.srv[server]
        slot = self.free_slot()
        last = f"logs/.last-session.item.{slot}"
        env = self.env_for(srv, last)
        fam = TREE_FAMILY.get(item.queue)
        if fam:
            tree_dir = srv.plugin_tree if fam == "tester" else srv.plugin_tree + "-review"
            env["PLUGIN_TREE"] = tree_dir
            others = [r for r in self.running.values() if r.server == server and TREE_FAMILY.get(r.item.queue) == fam]
            if not others:
                at = refresh_plugin_tree(srv.source_dir, tree_dir, self.branch())
                if at:
                    srv.log.say(f"[loop] {fam} tree: origin/{self.branch()} @ {at}")
                else:
                    srv.log.say(
                        f"[loop] WARNING: could not refresh the {fam} tree {tree_dir}; the session reads the previous one"
                    )
        tree = None
        if item.queue in SUITE_WRITERS:
            try:
                tree = suite_tree.make(REPO, f"item-{slot}", say=srv.log.say)
            except Exception as e:  # noqa: BLE001 - a git failure must not take the loop down
                srv.log.say(f"[loop] WARNING: no suite tree for {label_of(item)} ({e}); not started")
                self.sched.finished(item, server, False)
                self.last_finish[item.key] = time.monotonic()
                return False
            env["HARNEST_SESSION_TREE"] = tree.path
            env["HARNEST_SESSION_BASE"] = tree.base
        out = self.logs / f".item.{slot}.out"
        try:
            proc = self.runner.start(item, server, slot, env)
        except OSError as e:
            srv.log.say(f"[loop] WARNING: could not start {label_of(item)}: {e}")
            if tree is not None:
                suite_tree.remove(REPO, tree.path)
            self.sched.finished(item, server, False)
            self.last_finish[item.key] = time.monotonic()
            return False
        rec = Running(item, server, slot, proc, time.time(), REPO / last, out, tree, label_of(item))
        self.running[slot] = rec
        self.sessions += 1
        if self.once:
            self.done_keys.add(item.key)
        if item.queue == "tester:task":
            self.task_last = time.time()
        srv.log.say(f"[loop] {ts()} start {rec.label} ({item.queue}) on {server}, slot {slot}")
        self.state.session_started(
            item, server, rec.label, role_model(item.queue.split(":")[0]), Path(srv.log.path).name
        )
        threading.Thread(target=self._wait, args=(rec,), daemon=True).start()
        self._gpu_flags()
        return True

    def _read(self, rec):
        rejected = False
        try:
            with open(rec.out, "wb") as f:
                for line in rec.proc.stdout:
                    f.write(line)
                    f.flush()
                    if not rejected and b"rate-limit: status=rejected" in line:
                        rejected = True
                        self.q.put(("ratelimit", rec, line.decode("utf-8", "replace")))
        except (OSError, ValueError):
            pass

    def _wait(self, rec):
        # The item's end is its exit, not its pipe's: a straggler that keeps
        # the pipe open must not hold the slot.
        reader = threading.Thread(target=self._read, args=(rec,), daemon=True)
        reader.start()
        rec.proc.wait()
        reader.join(timeout=10)
        self.q.put(("exit", rec))

    def ended(self, rec):
        srv = self.srv[rec.server]
        rc = rec.proc.returncode
        self.running.pop(rec.slot, None)
        cost = cost_of(rec.last)
        self.state.session_ended(rec.item, rec.server, cost)
        if rc != 0:
            tail = ""
            with contextlib.suppress(OSError):
                tail = " | ".join(Path(rec.out).read_text(errors="replace").strip().splitlines()[-3:])
            srv.log.say(f"[loop] WARNING: {rec.label} item exited {rc}: {tail}")
        if outcome.rejected(rec.last) or outcome.rejected(rec.out):
            self.rate_limited(outcome.rejected_until(rec.out) or outcome.rejected_until(rec.last))
        if rec.tree is not None:
            self.land(rec, srv)
        self.sched.finished(rec.item, rec.server, rc == 0)
        self.last_finish[rec.item.key] = time.monotonic()
        if rec.item.queue in CLOSURE_KINDS:
            srv.closures = []  # read again at the next housekeeping
        srv.log.say(
            f"[loop] {ts()} end {rec.label} on {rec.server} (exit {rc}"
            + (f", ${cost:.2f}" if cost is not None else "")
            + f", {int(time.time() - rec.started)}s)"
        )
        self.need_snapshot = True
        self._gpu_flags()

    def suite_paths(self, srv):
        if srv.server.primary:
            return list(suite_tree.DEFAULT_PATHS)
        perf = self.profile.get("suite.perf_dir", "regression-perf")
        res = self.profile.get("suite.results_dir", "regression-results")
        return ["regression-suite-*.md", f"{perf}/{srv.name}", f"{res}/{srv.name}"]

    def land(self, rec, srv):
        note = {}
        try:
            note = json.loads(Path(str(rec.last) + ".land").read_text())
        except (OSError, ValueError):
            note = {}
        msg = note.get("msg") or f"suite: {rec.label} left suite edits and no land note"
        name = note.get("name") or NO_NOTE[0]
        email = note.get("email") or NO_NOTE[1]
        branch = []

        def say(line):
            srv.log.say(line)
            if "kept on branch " in line:
                branch.append(line.split("kept on branch ", 1)[1].split()[0])

        try:
            result = suite_tree.land(
                REPO,
                rec.tree,
                msg,
                name,
                email,
                say,
                SuiteLock(str(self.logs)),
                paths=self.suite_paths(srv),
                logs=str(self.logs / ".land"),
                kind=note.get("kind", ""),
            )
        except Exception as e:  # noqa: BLE001 - nothing is dropped: the tree stays for make() to strand
            srv.log.say(
                f"[audit] WARNING: could not land {rec.label}'s suite tree {rec.tree.path}: {e!r}; it is left in place"
            )
            result = "error"
        if result in ("conflict", "stranded", "error"):
            srv.log.say(
                f"[audit] WARNING: {rec.label}'s suite edits did not land cleanly ({result})"
                + (f"; kept on branch {branch[-1]}" if branch else "")
            )
            p = {"at": time.time(), "label": rec.label, "issue": rec.item.issue, "server": rec.server, "result": result}
            if branch:
                p["branch"] = branch[-1]
            self.suite_problems.append(p)
            self.state.suite_problem(p)
        if result != "error":
            suite_tree.remove(REPO, rec.tree.path)
        with contextlib.suppress(OSError):
            os.unlink(str(rec.last) + ".land")

    def rate_limited(self, epoch):
        now = time.time()
        until = epoch + 60 if epoch else now + self.rl_fallback
        if until <= now or until <= self.paused_until:
            return
        self.paused_until = until
        self.sched.pause_until(time.monotonic() + (until - now))
        self.state.status("paused-rate-limit")
        self.say(
            f"[loop] rate limit rejected: no session starts until {time.strftime('%H:%M:%S', time.localtime(until))}"
        )

    def _gpu_flags(self):
        for name in self.srv:
            try:
                self.gpu_busy[name] = not self.sched.gpu_idle(name)
            except Exception:  # noqa: BLE001
                pass

    # -- holds -------------------------------------------------------------------
    def hold(self, srv, reason):
        srv.holds.add(reason)
        self.sched.hold(srv.name, ",".join(sorted(srv.holds)))

    def unhold(self, srv, reason):
        srv.holds.discard(reason)
        if srv.holds:
            self.sched.hold(srv.name, ",".join(sorted(srv.holds)))
        else:
            self.sched.unhold(srv.name)

    def gpu_running(self, srv):
        return (
            any(
                r.server == srv.name
                and r.item.queue in ("tester:verify", "tester:answer", "tester:task", "tester:closures")
                for r in self.running.values()
            )
            or srv.regression is not None
        )

    # -- deploys -----------------------------------------------------------------
    def deploy_check(self):
        for srv in self.active():
            if srv.stopping:
                continue
            verifies = [i.issue for i in self.items if i.queue == "tester:verify" and i.server == srv.name]
            if self.only and "tester:verify" not in self.only:
                verifies = []
            runnable = {}
            changed = False
            if verifies or srv.gate.state in ("draining", "deploying"):
                git("-C", srv.source_dir, "fetch", "-q", "origin", self.branch())
                dev = git("-C", srv.source_dir, "rev-parse", "--short", f"origin/{self.branch()}").stdout.strip()
                if dev and dev != srv.develop:
                    if srv.gate.parked and srv.parked_develop and dev != srv.parked_develop:
                        srv.log.say(f"[loop:deploy] develop moved to {dev}: deploys to {srv.name} are tried again")
                        srv.gate.reset()
                    srv.develop = dev
                changed = server_paths_changed(srv.source_dir, srv.deployed, f"origin/{self.branch()}")
                for n in verifies:
                    runnable[n] = (not changed) or runnable_now(srv.source_dir, n, srv.deployed)
            srv.waiting = [n for n in verifies if not runnable.get(n)]
            st = srv.gate.state
            if st in ("idle", "failed") and srv.regression is None and not srv.nightly_due:
                if srv.gate.wanted(verifies, runnable, changed):
                    self.hold(srv, "deploy")
                    srv.gate.set_state("draining")
                    srv.log.say(
                        f"[loop:deploy] {srv.name} runs {srv.deployed}, develop is {srv.develop}: "
                        f"{' '.join('#%d' % n for n in srv.waiting)} wait for it; draining gpu:{srv.name}"
                    )
            if srv.gate.state == "draining" and not self.gpu_running(srv) and self.sched.gpu_idle(srv.name):
                srv.gate.set_state("deploying")
                srv.deploying = True
                srv.deploy_gen += 1
                code = [r.label for r in self.running.values() if r.server == srv.name]
                srv.log.say(
                    f"[loop:deploy] {ts()} deploying {self.branch()} to {srv.name}"
                    + (f" (code sessions running through it: {' '.join(code)})" if code else "")
                )
                threading.Thread(target=self._deploy, args=(srv,), daemon=True).start()
            self.state.deploy(srv.name, srv.gate.state, srv.waiting, srv.last_deploy)
            self.state.heads(srv.name, head_sha(srv.deployed) or srv.deployed, srv.develop or None)

    def _deploy(self, srv):
        t0 = time.time()
        try:
            ok, head = deploy.run_deploy(srv.server, srv.log.say, self.branch(), str(self.logs))
            if ok:
                try:
                    deploy.preflight(srv.server, srv.url, srv.token)
                except deploy.PreflightError as e:
                    srv.log.say(f"[loop:deploy] preflight after the deploy failed: {e}")
                    ok = False
        except Exception as e:  # noqa: BLE001
            srv.log.say(f"[loop:deploy] deploy raised {e!r}")
            ok, head = False, "unknown"
        self.q.put(("deploy", srv, ok, head, time.time() - t0))

    def deployed(self, srv, ok, head, secs):
        srv.deploying = False
        srv.deploy_gen += 1
        if head and head_sha(head):
            srv.deployed = head
        srv.last_deploy = {"at": time.time(), "head": head_sha(head) or head, "ok": ok, "secs": int(secs)}
        self.unhold(srv, "deploy")
        if ok:
            srv.gate.succeeded()
            srv.log.say(f"[loop:deploy] {srv.name} is running: {srv.deployed} (after driver deploy, {int(secs)}s)")
        else:
            what = srv.gate.failed()
            if what == "retry":
                srv.log.say(f"[loop:deploy] deploy to {srv.name} failed; trying again in {self.retry_secs}s")
            else:
                srv.parked_develop = srv.develop
                srv.log.say(f"[loop:deploy] deploy to {srv.name} failed twice; parking the verifies that wait for it")
                for n in srv.waiting:
                    rc, out = self.item_pass(
                        srv, "park", str(n), f"environment: the driver's deploy of develop to {srv.name} failed twice"
                    )
                    if rc != 0:
                        srv.log.say(f"[loop:deploy] could not park #{n}: {out.strip()[-200:]}")
                srv.waiting = []
        self.need_snapshot = True
        self._gpu_flags()

    # -- nightly regression ------------------------------------------------------
    def nightly_check(self):
        if not self.nightly_at or self.only:
            return
        for srv in self.active():
            if srv.stopping or srv.regression is not None:
                continue
            stamp = self.logs / f".nightly-regression{srv.sfx}"
            today = time.strftime("%Y-%m-%d")
            if int(time.strftime("%H")) < int(self.nightly_at):
                continue
            try:
                if stamp.read_text().strip() == today:
                    continue
            except OSError:
                pass
            if not self.hk_ready:
                continue
            if srv.freeze:
                if not srv.nightly_due:
                    srv.log.say(
                        "[nightly] board unreadable; holding under a possible release freeze"
                        if srv.freeze == "UNKNOWN"
                        else f"[nightly] held: release freeze {srv.freeze}"
                    )
                continue
            if not srv.nightly_due:
                srv.nightly_due = True
                self.hold(srv, "regression")
                srv.log.say(f"[nightly] {srv.name}: due; draining gpu:{srv.name} for it")
            if (
                srv.gate.state in ("draining", "deploying")
                or self.gpu_running(srv)
                or not self.sched.gpu_idle(srv.name)
            ):
                continue
            stamp.write_text(today + "\n")
            self.start_regression(srv)

    def start_regression(self, srv):
        item = Item("regression", None, srv.name)
        env = self.env_for(srv)
        env["HARNEST_HELD_LOCK"] = f"{os.getpid()} {LOCK_NAME}"
        log = self.logs / f"nightly-regression{srv.sfx}.log"
        srv.log.say(f"[nightly] run-regression.sh {' '.join(self.nightly_level)} (log logs/{log.name})")
        try:
            with open(log, "ab") as f:
                proc = subprocess.Popen(
                    ["bash", str(REPO / "run-regression.sh"), *self.nightly_level],
                    cwd=str(REPO),
                    env=env,
                    stdin=subprocess.DEVNULL,
                    stdout=f,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
        except OSError as e:
            srv.log.say(f"[nightly] could not start: {e}")
            srv.nightly_due = False
            self.unhold(srv, "regression")
            return
        self.sched.pool.take(item, srv.name)
        rec = Running(item, srv.name, "regression", proc, time.time(), Path(os.devnull), Path(os.devnull))
        srv.regression = rec
        self.state.session_started(
            item, srv.name, f"regression:{' '.join(self.nightly_level)}", role_model("regression"), log.name
        )
        threading.Thread(target=lambda: (proc.wait(), self.q.put(("regression", srv))), daemon=True).start()
        self._gpu_flags()

    def regression_ended(self, srv):
        rec = srv.regression
        srv.regression = None
        srv.nightly_due = False
        self.sched.pool.release(rec.item, srv.name)
        self.state.session_ended(rec.item, srv.name, None)
        self.unhold(srv, "regression")
        srv.log.say(f"[nightly] done (exit {rec.proc.returncode}); what it filed is on the board")
        self.need_snapshot = True
        self._gpu_flags()

    # -- stopping ----------------------------------------------------------------
    def stop_flags(self):
        for srv in self.active():
            flag = self.logs / f"stop-after-cycle{srv.sfx}"
            if not srv.stopping and flag.exists():
                srv.stopping = True
                self.hold(srv, "stop")
                srv.log.say(f"[loop] stop-after-cycle{srv.sfx} found: {srv.name} takes no new work, then stops")
            if srv.stopping and not self.busy_on(srv):
                with contextlib.suppress(OSError):
                    flag.unlink()
                self.release(srv, "stop-after-cycle")
                self.need_snapshot = True

    def busy_on(self, srv):
        return srv.deploying or srv.regression is not None or any(r.server == srv.name for r in self.running.values())

    def kill_children(self):
        """TERM every item and child driver's group, wait for them (the items
        stop their own sessions, within SESSION_KILL_SECS), KILL what is left
        past CHILD_DRIVER_KILL_SECS, and any descendant that outlived its item."""
        procs = [r.proc for r in self.running.values()]
        procs += [s.regression.proc for s in self.srv.values() if s.regression is not None]
        with self._children_mx:
            procs += list(self._children)
        tree = {p.pid: _descendants(p.pid) for p in procs}
        for p in procs:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(p.pid, signal.SIGTERM)
        deadline = time.monotonic() + max(self.child_kill, self.session_kill)
        while time.monotonic() < deadline and any(p.poll() is None for p in procs):
            time.sleep(0.1)
        for p in procs:
            if p.poll() is None:
                self.say(f"[driver] child {p.pid} ignored TERM for {self.child_kill}s; killing it")
                _kill_hard(p.pid)
        time.sleep(0.2)
        for pid in (d for ds in tree.values() for d in ds):
            if _alive(pid):
                _kill_hard(pid)
        session.kill_all()

    # -- the heartbeat -------------------------------------------------------------
    def heartbeat(self, stop):
        last_write = last_sample = 0.0
        while not stop.wait(1):
            now = time.monotonic()
            try:
                if now - last_sample >= self.health_secs:
                    last_sample = now
                    for srv in self.active():
                        h = deploy.health_json(srv.url, srv.token)
                        workers = []
                        if isinstance(h, dict) and isinstance(h.get("workers"), list):
                            for w in h["workers"]:
                                if isinstance(w, dict):
                                    workers.append(
                                        {
                                            "device": w.get("device"),
                                            "busy": bool(w.get("current_job")),
                                            "job": w.get("current_job"),
                                        }
                                    )
                        self.state.workers(srv.name, workers)
                        self.state.gpu_sample(srv.name, self.gpu_busy.get(srv.name, False), loop_state.workers_busy(h))
                if now - last_write >= self.poll:
                    last_write = now
                    self.state.write()
            except Exception as e:  # noqa: BLE001 - a heartbeat never takes the driver down
                with contextlib.suppress(Exception):
                    self.say(f"[loop] heartbeat: {e!r}")

    def write_state(self):
        try:
            for srv in self.active():
                qs = {}
                for i in self.items:
                    if i.server == srv.name or (i.server is None and srv.name in i.candidates):
                        qs.setdefault(i.queue, []).append(i.issue)
                self.state.queues(srv.name, qs)
            if not self.readable:
                self.state.board([], False)
            self.state.write()
        except Exception as e:  # noqa: BLE001
            with contextlib.suppress(Exception):
                self.say(f"[loop] could not write state.json: {e!r}")

    # -- the loop ------------------------------------------------------------------
    def on_signal(self, signum, _frame):
        # Nothing that takes a lock here (the main thread may hold it): a
        # thread wakes the loop and stops the short children it waits on.
        self.stop_signal = signum
        threading.Thread(target=self._signalled, args=(signum,), daemon=True).start()

    def _signalled(self, signum):
        self.q.put(("signal", signum))
        with self._children_mx:
            kids = list(self._children)
        for p in kids:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(p.pid, signal.SIGTERM)

    def interval(self):
        """The poll interval: LOOP_POLL_SECS, backed off (to SLEEP_MAX_SECS)
        while nothing runs and only Don's decisions are left."""
        return self.poll if self.running else self.idle_secs

    def quiet(self):
        """Nothing running, and nothing waiting that will start by itself."""
        if self.running or not self.hk_ready:
            return False  # the first housekeeping may offer closures, the curator, the task
        for srv in self.active():
            if srv.deploying or srv.regression is not None or srv.gate.state == "draining" or srv.nightly_due:
                return False
            if srv.gate.state == "failed" and not srv.gate.parked and srv.waiting:
                return False  # a retry is due
        if time.time() < self.paused_until:
            return False
        return True

    def run(self):
        hb_stop = threading.Event()
        threading.Thread(target=self.heartbeat, args=(hb_stop,), daemon=True).start()
        # the first housekeeping runs beside the first dispatch; what needs it
        # (closures, the standing task, the curator, the nightly) waits for it
        self.start_hk()
        rc = 0
        crashed = False
        try:
            rc = self.loop()
        except BaseException as e:
            crashed = not isinstance(e, SystemExit)
            if crashed:
                import traceback

                self.say(f"[loop] FATAL: {e!r}\n{traceback.format_exc()}")
            rc = 1 if crashed else (e.code if isinstance(e.code, int) else 1)
        finally:
            hb_stop.set()
            if crashed and not self.stop_signal:
                self.stop_signal = "crash"
            if self.stop_signal:
                self.state.status("stopping")
                self.write_state()
                self.say(f"[loop] {ts()} signal {self.stop_signal}: stopping every session")
                for srv in self.active():
                    self.hold(srv, "signal")
                self.kill_children()
                for rec in list(self.running.values()):
                    if rec.tree is not None:
                        self.say(
                            f"[loop] {rec.label} was stopped: its suite tree {rec.tree.path} is kept (the next make() strands it)"
                        )
                rc = 1 if crashed else 143
            else:
                # a housekeeping pass may be mid-edit on the board: let it end
                t = getattr(self, "hk_thread", None)
                if t is not None:
                    t.join(timeout=60)
            if not crashed:  # a crash leaves "stopping": the dashboard shows it stalled, not stopped
                self.state.status("stopped")
            for rec in list(self.running.values()):
                self.state.session_ended(rec.item, rec.server, None)
            self.write_state()
            for srv in self.srv.values():
                if srv.active:
                    lock.release(srv.lock)
            self.say(f"[loop] {ts()} the loop driver exits ({rc})")
        return rc

    def loop(self):
        while True:
            interval = self.interval()
            timeout = max(0.05, interval - (time.monotonic() - self.snap_last))
            if self.paused_until:
                timeout = min(timeout, max(0.05, self.paused_until - time.time()))
            for srv in self.active():
                left = (srv.gate.retry_at or 0) - time.monotonic()
                if srv.gate.state == "failed" and left > 0:
                    timeout = min(timeout, max(0.05, left))  # wake for the retry
            events = []
            try:
                events.append(self.q.get(timeout=timeout))
                while True:
                    events.append(self.q.get_nowait())
            except queue.Empty:
                pass
            for ev in events:
                kind = ev[0]
                if kind == "exit":
                    self.ended(ev[1])
                elif kind == "deploy":
                    self.deployed(*ev[1:])
                elif kind == "regression":
                    self.regression_ended(ev[1])
                elif kind == "ratelimit":
                    self.rate_limited(outcome.rejected_until_line(ev[2]))
                elif kind == "hk":
                    self.apply_hk(ev[1])
                elif kind == "hk-error":
                    self.hk_busy = False
                    self.hk_ready = True
                    self.say(f"[loop] WARNING: housekeeping failed: {ev[1]}")
            if self.stop_signal:
                return 143
            if self.paused_until and time.time() >= self.paused_until:
                self.paused_until = 0.0
                self.say("[loop] rate limit pause over")
            self.stop_flags()
            if not self.active():
                self.say("[loop] no server left to drive")
                return 0
            interval = self.interval()
            polled = False
            if self.need_snapshot or time.monotonic() - self.snap_last >= interval:
                self.snapshot()
                polled = True
            if time.monotonic() - self.hk_last >= interval and not self.hk_busy:
                self.start_hk()
            self.deploy_check()
            self.nightly_check()
            dispatched = self.dispatch()
            status = "running"
            if self.paused_until:
                status = "paused-rate-limit"
            elif (self.max_sessions and self.sessions >= self.max_sessions) or any(s.stopping for s in self.active()):
                status = "draining"
            self.state.status(status)
            self.write_state()
            if dispatched or self.running:
                continue
            if self.max_sessions and self.sessions >= self.max_sessions and self.quiet():
                self.say(f"[loop] reached MAX_SESSIONS={self.max_sessions}, exiting")
                return 0
            if self.once and self.quiet():
                self.say("[loop] --once: nothing more to start, exiting")
                return 0
            if polled and self.quiet() and self.readable:
                left = [(board.query("drain", s.name, self.board_env(s)) or "unknown").strip() for s in self.active()]
                if self.drain == "1" and left and all(x == "done" for x in left):
                    self.say("[loop] drain: nothing left but deferred issues, exiting")
                    return 0
                if left and all(x in ("don", "away", "done") for x in left) and any(x != "done" for x in left):
                    self.idle_secs = min(max(self.poll, self.idle_secs * 2), max(self.poll, self.sleep_max))
                else:
                    self.idle_secs = self.poll


def main(argv=None):
    try:
        lp = Loop(sys.argv[1:] if argv is None else argv)
    except ProfileError as e:
        err(str(e))
        return 1
    # Until the loop runs, a signal just exits (the lock's atexit releases it).
    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(s, lambda *_: sys.exit(143))
    try:
        rc = lp.start()
    except ProfileError as e:
        err(str(e))
        return 1
    if rc:
        return rc
    for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(s, lp.on_signal)
    return lp.run()


if __name__ == "__main__":
    sys.exit(main())
