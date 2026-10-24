"""The regression fleet: levels split across every server's lanes, each case
once, on a lane that can run it (docs/superpowers/specs/
2026-10-18-regression-fleet.md).

    python3 -m harness.drivers.fleet [level|all]          # run it
    python3 -m harness.drivers.fleet --plan [level|all]   # where each case would run; runs nothing
    FLEET_SERVERS="lem minid" python3 -m harness.drivers.fleet smoke
    python3 -m harness.drivers.fleet --allow-failures smoke  # exit 0 when cases fail

It exits 1 when a case fails (unless --allow-failures) and when the run
lost a case: a lane crashed, or a case ended with no answer (finish
records the run "failed" then).

Every server is preflighted and asked for its facts (workers, cached
models, assets, what each named workflow lacks), and the plan is checked
against its profile policy. A run then takes each server's driver lock and
runs one thread per lane:

- a lane runs its dependency groups in order, as chunk sessions of
  CASES_PER_SESSION cases (8) on its server, in its own workspace
  (`regression-smoke-lem-1`), with its own state files;
- groups are placed, stolen and re-queued by estimated time, from the case
  times past runs recorded (harness/durations.py);
- an idle lane steals an unstarted group it may run from the busiest lane;
- an `exclusive` case runs alone in its session, under a gate that waits
  for its server's other lanes to finish theirs, so only that case idles
  the box;
- a case a lane skips (REGRESSION-SKIP) is queued on an eligible lane of
  another server; a server that reports REGRESSION-ABORT hands its queue
  to the others;
- each lane sweeps its workspaces at the end, and the suites and perf
  history are committed once.

Progress is logs/fleet/state.json, rewritten on every change (the
dashboard's /regression page reads it), and each finished run is kept in
logs/fleet/runs/. Agents report each case as they start it
(REGRESSION-CASE) and its outcome at the end (REGRESSION-RESULT); see
agents/regression/run-cases.md, step 6.

Knobs: FLEET_SERVERS (every server), CASES_PER_SESSION (8), FLEET_MIN_BATCH
(3: the fewest cases a session or a steal is worth, given a session's setup cost),
REGRESSION_MODEL / REGRESSION_PROVIDER / REGRESSION_EFFORT /
REGRESSION_BUDGET_USD, AUTOCOMPACT_TOKENS, FALLBACK_MODEL, TICKET_REPO,
and each server's token (DW_TOKEN_<SERVER>, or .env).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path

from .. import REPO, deploy, durations, facts, lock, outcome, prompts, providers, requirements, session, suite
from ..gitops import refresh_plugin_tree
from ..log import Log, err, ts
from ..profile import ProfileError, load, resolve_token, resolve_url
from ..stream import resolved_model
from . import regression as reg

_ID = r"([A-Z]+-[A-Z][0-9]+)"
RESULT_RE = re.compile(
    r"^[-*` ]*REGRESSION-RESULT:[ \t]*" + _ID + r"[ \t]+(pass|fail|skip|pending)\b[ \t]*(#\d+)?", re.M
)
CASE_RE = re.compile(r"^[-*` ]*REGRESSION-CASE:[ \t]*" + _ID)
SKIP_RE = re.compile(r"^[-*` ]*REGRESSION-SKIP:[ \t]*" + _ID, re.M)
COST_RE = re.compile(r"^usage: .*?cost=\$([0-9.]+)", re.M)
FLEET_DIR = REPO / "logs" / "fleet"
# outcomes a case still has when nothing ever answered for it: a run that ends with one failed
UNRESOLVED = ("queued", "running", "next", "unreported", "not run")


def env(name, default=""):
    return os.environ.get(name) or default


# --- the plan --------------------------------------------------------------


@dataclass
class Lane:
    server: object
    slot: int
    facts: object
    groups: list = field(default_factory=list)  # [(level, Group)]
    load: float = 0.0  # assigned work, in primary-lane seconds (durations.Estimates)
    batch: list = field(default_factory=list)  # the Items its session is running now

    @property
    def name(self):
        return f"{self.server.name}-{self.slot}"

    def workspace(self, base):
        """A server's first lane works in the level's own workspace, as a
        one-server run does, fixtures and all; another lane on the same
        server gets its own, seeded from it (Fleet.seed)."""
        return base if self.slot == 1 else f"{base}-{self.name}"


@dataclass
class Plan:
    level: str
    suite_file: object
    lanes: list
    unplaced: list = field(default_factory=list)  # (group, {server: why})
    script_cases: list = field(default_factory=list)


def gather_all(
    profile,
    names,
    workflows=(),
    environ=os.environ,
    gather=facts.gather,
    validate=facts.validate_workflows,
    workspaces=(),
):
    """{server: facts} for <names>, each having validated <workflows>;
    ProfileError listing every server that can't take part (no token, not
    answering, policy the facts can't meet)."""
    out, problems = {}, []
    for name in names:
        s = profile.server(name)
        try:
            url = resolve_url(s, environ.get("DW_URL", "") if len(names) == 1 else "")
            token = resolve_token(s, None if environ is os.environ else environ)
            f = gather(s, url, token, workspaces=workspaces) if workspaces else gather(s, url, token)
            f.workflows = validate(url, token, list(workflows))
        except (ProfileError, facts.FactsError) as e:
            problems.append(f"{name}: {e}")
            continue
        problems += facts.check(s, f)
        out[name] = f
    if problems:
        raise ProfileError("the fleet can't start:\n  " + "\n  ".join(problems))
    return out


def make_lanes(profile, server_facts):
    return [
        Lane(server=profile.server(n), slot=i + 1, facts=f)
        for n, f in server_facts.items()
        for i in range(profile.server(n).lanes)
    ]


def why_not(group, server, server_facts, ref):
    held = [c for c in group.cases if c in server.regression_skip_cases]
    if held:
        return f"{held[0]} is held back here"
    ok, reason = requirements.eligible(group.need, server, server_facts, ref)
    return "" if ok else reason


def plan_level(profile, level, server_facts, sidecar, level_servers=None, lanes=None, est=None):
    """Assigns <level>'s dependency groups to lanes, longest first, each to
    the eligible lane that would finish it soonest. A group's length is its
    cases' estimated time (<est>, from past runs; every case the same without
    one). <lanes> carries load across levels, so `all` balances as one pool."""
    est = est or durations.Estimates()
    lv = profile.level(level)
    suite_file = REPO / lv.file
    script = suite.script_cases(suite_file, REPO / profile.get("suite.contract_cases", "contract/cases"))
    lanes = lanes if lanes is not None else make_lanes(profile, server_facts)
    usable = [l for l in lanes if level_servers is None or l.server.name in level_servers]
    ref = requirements.reference_sizes(server_facts.values())
    p = Plan(level=level, suite_file=suite_file, lanes=usable, script_cases=script)
    for g in sorted(requirements.groups(suite_file, sidecar, skip=script), key=lambda g: -est.of(g.cases)):
        why, best = {}, None
        for lane in usable:
            reason = why_not(g, lane.server, lane.facts, ref)
            if reason:
                why[lane.server.name] = reason
                continue
            finish = lane.load + est.of(g.cases) / lane.server.speed
            if best is None or finish < best[0]:
                best = (finish, lane)
        if best is None:
            p.unplaced.append((g, why))
            continue
        best[1].groups.append((level, g))
        best[1].load = best[0]
    return p


def render(p, workspace, timed=False):
    lane_cases = lambda l: [c for lv, g in l.groups if lv == p.level for c in g.cases]
    out = [f"== {p.level}: {sum(len(lane_cases(l)) for l in p.lanes)} cases on {len(p.lanes)} lane(s)"]
    if p.script_cases:
        out.append(f"   script cases (contract/run.py, on the primary): {' '.join(p.script_cases)}")
    for lane in p.lanes:
        cases = lane_cases(lane)
        excl = [c for lv, g in lane.groups if lv == p.level and g.need.load == "exclusive" for c in g.cases]
        took = f"  ~{lane.load / 60:4.0f} min" if timed else ""  # with `all`, the levels so far
        out.append(f"   {lane.name:10} {len(cases):4} cases{took}  workspace {lane.workspace(workspace)}")
        if excl:
            out.append(f"   {'':10} in exclusive groups: {' '.join(excl)}")
    for g, why in p.unplaced:
        out.append(f"   unplaced {' '.join(g.cases)}: " + "; ".join(f"{s}: {w}" for s, w in why.items()))
    reasons = {}
    for lane in p.lanes:
        for lv, g in lane.groups:
            if lv == p.level and not g.need.known:
                reasons[g.need.why_unknown] = reasons.get(g.need.why_unknown, 0) + len(g.cases)
    for r, n in sorted(reasons.items(), key=lambda x: -x[1]):
        out.append(f"   {n} case(s) primary only: {r}")
    return "\n".join(out)


# --- running it ------------------------------------------------------------


class Gate:
    """One server's sessions: many at once, or one exclusive session alone.
    An exclusive session waiting holds off new ordinary ones, so it can't
    starve."""

    def __init__(self):
        self.cv = threading.Condition()
        self.active = 0
        self.exclusive = False
        self.waiting = 0

    def enter(self, exclusive):
        with self.cv:
            if exclusive:
                self.waiting += 1
                self.cv.wait_for(lambda: self.active == 0 and not self.exclusive)
                self.waiting -= 1
                self.exclusive = True
            else:
                self.cv.wait_for(lambda: not self.exclusive and self.waiting == 0)
            self.active += 1

    def leave(self, exclusive):
        with self.cv:
            self.active -= 1
            if exclusive:
                self.exclusive = False
            self.cv.notify_all()


@dataclass
class Item:
    level: str
    case: str
    gid: str
    exclusive: bool
    tried: set = field(default_factory=set)  # servers that skipped it
    retried: bool = False  # sent again once after a session ended without its answer


class State:
    """logs/fleet/state.json: what the dashboard shows. Rewritten whole,
    atomically, on every change."""

    def __init__(self, path, data):
        self.path = Path(path)
        self.lock = threading.RLock()
        self.data = data
        self.write()

    def write(self):
        with self.lock:
            self.data["updated"] = time.time()
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data, indent=1))
            os.replace(tmp, self.path)

    def update(self, fn):
        with self.lock:
            fn(self.data)
            self.write()


class ServerRun:
    """What sessions on one server need: endpoint, flags, logs, gate."""

    def __init__(self, fleet, server, server_facts):
        self.server = server
        self.facts = server_facts
        self.log = Log(fleet.logs / f"loop{server.suffix}.log")
        self.url = resolve_url(server)
        self.token = resolve_token(server)
        self.health = f"{server_facts.device} on {server_facts.hostname}"
        self.text = "lem" if server.primary else f"the {server.name} server ({self.health})"
        self.rpfx = "regression" + ("" if server.primary else f"-{server.name}")
        self.gate = Gate()
        self.down = False
        self.head = "unknown"
        mcp = fleet.profile.get("mcp.name", "dw")
        self.plugin_tree = Path(os.path.expanduser(fleet.profile.get("clones.plugin") + server.clone_suffix))
        self.flags = [
            "--mcp-config",
            session.mcp_config(mcp, self.url, self.token),
            "--strict-mcp-config",
            "--plugin-dir",
            str(self.plugin_tree / fleet.profile.get("clones.plugin_subdir", "plugins/dw")),
            *session.ISOLATION_FLAGS,
            "--tools",
            session.CONSUMER_TOOLS,
            *session.consumer_permission_flags(mcp, fleet.profile.get("mcp.deny_tools", ())),
        ]
        self.session_env = {
            "HARNEST_TARGET": server.name,
            "HARNEST_ROLE": "regression",
            "HARNEST_TICKET_REPO": fleet.ticket_repo,
        }


class Fleet:
    def __init__(self, profile, levels, names, sidecar, server_facts):
        self.profile = profile
        self.levels = levels
        self.sidecar = sidecar
        self.server_facts = server_facts
        self.logs = REPO / "logs"
        self.ticket_repo = env("TICKET_REPO", profile.get("ticket_repo"))
        self.model = env("REGRESSION_MODEL", "claude-sonnet-5-5")
        self.provider = env("REGRESSION_PROVIDER", env("PROVIDER", "anthropic"))
        self.per = int(env("CASES_PER_SESSION", "8"))
        self.min_batch = max(1, int(env("FLEET_MIN_BATCH", "3")))
        if self.per < 1:
            raise ProfileError("CASES_PER_SESSION must be at least 1 in a fleet run")
        self.model_env = providers.resolve_model_env(self.provider, self.model)
        self.session_flags = providers.session_flags(
            self.provider,
            self.model,
            env("REGRESSION_EFFORT", env("EFFORT", "medium")),
            env("REGRESSION_BUDGET_USD", "6"),
            env("FALLBACK_MODEL"),
            env("AUTOCOMPACT_TOKENS", "120000"),
        )
        self.servers = {n: ServerRun(self, profile.server(n), f) for n, f in server_facts.items()}
        self.lanes = make_lanes(profile, server_facts)
        self.est = durations.Estimates.load(FLEET_DIR / "runs", profile)
        self.ref = requirements.reference_sizes(server_facts.values())
        self.mu = threading.RLock()
        # A lane is busy from taking a batch until its skips are re-queued:
        # an idle lane exits only when no lane is busy, since a busy one can
        # still hand it work (a skipped case re-queued onto its server).
        self.cv = threading.Condition(self.mu)
        self.busy = 0
        self.idle = 0  # lanes waiting with nothing to take: batches shrink so they can help
        self.queues = {l.name: [] for l in self.lanes}
        self.started_gids = set()
        self.group_need = {}
        self.case_need = {}
        self.suite_files = {}
        self.script = {}
        self.unplaced = []
        self.stamp = time.strftime("%Y%m%d-%H%M%S")

    # -- setup

    def plan(self):
        for lv in self.levels:
            servers = [n for n in self.servers if len(self.levels) == 1 or lv in self.profile.server(n).regression_all]
            p = plan_level(self.profile, lv, self.server_facts, self.sidecar, servers, self.lanes, self.est)
            self.suite_files[lv] = p.suite_file
            self.script[lv] = p.script_cases
            blocks = requirements.case_blocks(p.suite_file)
            for c, b in blocks.items():
                self.case_need[c] = requirements.need_for(c, b, self.sidecar)
            self.unplaced += [(lv, g, why) for g, why in p.unplaced]
        for lane in self.lanes:
            for lv, g in lane.groups:
                gid = f"{lv}:{g.cases[0]}"
                self.group_need[gid] = (lv, g)
                for c in g.cases:
                    excl = self.case_need[c].load == "exclusive"
                    self.queues[lane.name].append(Item(level=lv, case=c, gid=gid, exclusive=excl))

    def initial_state(self):
        cases = {}
        for lane in self.lanes:
            for it in self.queues[lane.name]:
                cases[it.case] = {
                    "level": it.level,
                    "lane": lane.name,
                    "server": lane.server.name,
                    "load": self.case_need[it.case].load if self.case_need[it.case].known else "unknown",
                    "outcome": "queued",
                }
        for lv, ids in self.script.items():
            for c in ids:
                cases[c] = {
                    "level": lv,
                    "lane": "script",
                    "server": self.lanes[0].server.name,
                    "load": "none",
                    "outcome": "queued",
                }
        for lv, g, _why in self.unplaced:
            for c in g.cases:
                cases[c] = {"level": lv, "lane": None, "server": None, "load": "?", "outcome": "unplaced"}
        return {
            "id": self.stamp,
            "status": "starting",
            "started": time.time(),
            "finished": None,
            "levels": self.levels,
            "model": self.model_env.label,
            "cases_per_session": self.per,
            "servers": {
                n: {"summary": s.facts.summary, "head": s.head, "down": False} for n, s in self.servers.items()
            },
            "lanes": [
                {
                    "name": l.name,
                    "server": l.server.name,
                    "status": "queued",
                    "level": None,
                    "batch": [],
                    "live_case": None,
                    "since": None,
                    "sessions": 0,
                    "cost": 0.0,
                }
                for l in self.lanes
            ],
            "cases": cases,
            "unplaced": [{"level": lv, "cases": g.cases, "why": why} for lv, g, why in self.unplaced],
            "events": [],
        }

    def event(self, text):
        def f(d):
            d["events"].append({"time": time.time(), "text": text})
            del d["events"][:-200]

        self.state.update(f)

    def lane_state(self, lane, **kw):
        def f(d):
            for l in d["lanes"]:
                if l["name"] == lane.name:
                    l.update(kw)

        self.state.update(f)

    def case_state(self, case, **kw):
        self.state.update(lambda d: d["cases"].setdefault(case, {}).update(kw))

    def setup(self):
        FLEET_DIR.mkdir(parents=True, exist_ok=True)
        (FLEET_DIR / "runs").mkdir(exist_ok=True)
        primary_log = self.servers[self.lanes[0].server.name].log
        src = Path(os.path.expanduser(self.profile.get("clones.source")))
        for name, s in self.servers.items():
            lock.acquire(str(self.logs / f".driver.lock{s.server.suffix}"), "run-fleet", s.log.say)
            if refresh_plugin_tree(src, s.plugin_tree, self.profile.get("integration_branch", "develop")) is None:
                raise ProfileError(f"could not create/refresh the plugin worktree {s.plugin_tree} from {src}")
            s.head = deploy.deployed_head(s.server)
            if not s.server.primary:
                (REPO / self.profile.get("suite.perf_dir", "regression-perf") / name).mkdir(parents=True, exist_ok=True)
                subprocess.run(
                    [
                        "gh",
                        "label",
                        "create",
                        f"target:{name}",
                        "--repo",
                        self.ticket_repo,
                        "--force",
                        "--color",
                        "5319e7",
                        "--description",
                        f"Found against a non-lem server (DW_TARGET={name}); Don triages",
                    ],
                    capture_output=True,
                )
        self.state = State(FLEET_DIR / "state.json", self.initial_state())
        self.seed()
        self.state.update(lambda d: [d["servers"][n].update(head=s.head) for n, s in self.servers.items()])
        total = sum(len(q) for q in self.queues.values())
        for s in self.servers.values():
            s.log.say(
                f"=== {ts()} regression fleet run ({self.model_env.label}, levels={','.join(self.levels)}, "
                f"{total} cases on {len(self.lanes)} lanes, server={s.server.name}, head={s.head}, id={self.stamp}) ==="
            )
        primary_log.say(
            "[fleet] lanes: "
            + ", ".join(f"{l.name} {len(self.queues[l.name])}" for l in self.lanes)
            + (f"; unplaced: {sum(len(g.cases) for _, g, _ in self.unplaced)}" if self.unplaced else "")
        )

    def seed(self):
        """A second lane on a server works in its own workspace: create it
        and copy the level workspace's own assets into it, once per run (it
        persists, so later runs find it ready)."""
        for lane in self.lanes:
            if lane.slot == 1:
                continue
            s = self.servers[lane.server.name]
            for lv in sorted({it.level for it in self.queues[lane.name]}):
                base = suite.workspace_for_suite_file(self.suite_files[lv])
                said = facts.seed_workspace(s.url, s.token, base, lane.workspace(base))
                s.log.say(f"[fleet] {lane.workspace(base)}: {said}")

    # -- the shared queue

    def _steal_plan(self, lane):
        """(victim, [gids]) worth stealing for <lane>, or None. A session has
        a fixed setup cost (system prompt, suite header, tool schemas: 30-40k
        tokens of context before its first case), so a steal must move at
        least FLEET_MIN_BATCH cases, taken from the end of the victim's
        unstarted groups. From a lane as fast as this one, only when the
        victim has two batches' worth unstarted, so it keeps a full one; from
        a slower lane, one batch's worth is enough, since moving it saves real
        time. On the first live fleet run, one-case steals put mini-ai at 18
        sessions for its share and the run at 65% over a one-server run."""
        best = None
        for other in self.lanes:
            if other is lane:
                continue
            q = self.queues[other.name]
            tail = []  # this lane's takeable groups, last first, with their sizes
            unstarted, left = 0, 0.0
            seen = set()
            for it in reversed(q):
                if it.gid in self.started_gids:
                    break
                unstarted += 1
                left += self.est(it.case)
                if it.gid in seen or it.gid not in self.group_need:
                    continue
                seen.add(it.gid)
                _lv, g = self.group_need[it.gid]
                if any(lane.server.name in i.tried for i in q if i.gid == it.gid):
                    continue
                if why_not(g, lane.server, lane.facts, self.ref):
                    continue
                tail.append((it.gid, sum(1 for i in q if i.gid == it.gid)))
            slower = other.server.speed < lane.server.speed
            if unstarted < self.min_batch * (1 if slower else 2) or not tail:
                continue
            take, n = [], 0
            for gid, size in tail:
                if n >= self.min_batch:
                    break
                take.append(gid)
                n += size
            if n < self.min_batch and not slower:
                continue
            weight = left / other.server.speed  # time the victim would need for it
            if best is None or weight > best[0]:
                best = (weight, other, take)
        return None if best is None else (best[1], best[2])

    def take(self, lane):
        """The next batch for <lane>: consecutive cases of one level, up to
        CASES_PER_SESSION, exclusive cases only with each other. Waits while
        another lane is busy and this one has nothing; None once there is
        nothing it can run and no lane is busy. A batch taken makes the lane
        busy until done()."""
        with self.cv:
            marked = False
            while True:
                batch = self._take(lane)
                if batch:
                    self.busy += 1
                    return batch
                if self.busy == 0 or self.servers[lane.server.name].down:
                    self.cv.notify_all()
                    return None
                self.idle += 1
                if not marked:
                    self.lane_state(lane, status="idle — waiting for work", batch=[], live_case=None)
                    marked = True
                try:
                    self.cv.wait(1.0)
                finally:
                    self.idle -= 1

    def batch_cap(self, lane, queued):
        """How many cases <lane> takes into one session. A slow lane takes
        fewer (CASES_PER_SESSION x its speed), so it never sits on a long
        run of cases the others can't reach. While any lane is idle, a
        lane takes only its share of what's left, so the rest stays
        stealable: on 2026-10-18 minid took all 7 of its cases into one
        session and the three faster lanes went idle while it ran them."""
        floor = min(self.min_batch, self.per)  # never under a session's worth of cases
        cap = max(floor, round(self.per * lane.server.speed))
        if self.idle:
            cap = min(cap, max(floor, -(-queued // (self.idle + 1))))
        return cap

    def done(self):
        with self.cv:
            self.busy -= 1
            self.cv.notify_all()

    def _take(self, lane):
        with self.mu:
            q = self.queues[lane.name]
            if not q:
                plan = self._steal_plan(lane)
                if plan is None:
                    return None
                victim, gids = plan
                vq = self.queues[victim.name]
                moved = [it for it in vq if it.gid in gids]
                self.queues[victim.name] = [it for it in vq if it.gid not in gids]
                q.extend(moved)
                for it in moved:
                    self.case_state(it.case, lane=lane.name, server=lane.server.name)
                self.event(f"{lane.name} took {' '.join(i.case for i in moved)} from {victim.name}")
            # A batch is consecutive cases of one level that are all exclusive or
            # all not: exclusivity is having the box to itself, so exclusive
            # cases can share one exclusive session rather than one each.
            first = q[0]
            cap = self.batch_cap(lane, len(q))
            batch = []
            while q and len(batch) < cap and q[0].level == first.level and q[0].exclusive == first.exclusive:
                batch.append(q.pop(0))
            for it in batch:
                self.started_gids.add(it.gid)
            return batch

    def requeue(self, item, from_lane, why="skipped", same_server=False):
        """A case <from_lane>'s server skipped goes to an eligible lane of a
        server that hasn't tried it; False when there is none. <same_server>
        (a retry after a session that died) lets its own server take it again."""
        if not same_server:
            item.tried.add(from_lane.server.name)
        need = self.case_need[item.case]
        group = requirements.Group(cases=[item.case], need=need)
        with self.mu:
            options = [
                l
                for l in self.lanes
                if l.server.name not in item.tried
                and not self.servers[l.server.name].down
                and not why_not(group, l.server, l.facts, self.ref)
            ]
            if not options:
                return False
            target = min(options, key=lambda l: self.est.of(i.case for i in self.queues[l.name]) / l.server.speed)
            # its own one-case group now, which another lane may steal
            item.gid = f"{item.gid}+{target.name}"
            self.group_need[item.gid] = (item.level, group)
            self.queues[target.name].append(item)
            self.cv.notify_all()
        self.case_state(item.case, lane=target.name, server=target.server.name, outcome="queued")
        self.event(f"{item.case} {why} on {from_lane.server.name}; queued on {target.name}")
        return True

    def server_down(self, server_name):
        """Its lanes' queues go to the other servers, where eligible."""
        with self.mu:
            self.servers[server_name].down = True
            stranded = []
            for l in self.lanes:
                if l.server.name == server_name:
                    stranded += self.queues[l.name]
                    self.queues[l.name] = []
        self.state.update(lambda d: d["servers"][server_name].update(down=True))
        self.event(f"{server_name} is unreachable (REGRESSION-ABORT); handing its {len(stranded)} case(s) on")
        from_lane = next(l for l in self.lanes if l.server.name == server_name)
        for it in stranded:
            if not self.requeue(it, from_lane):
                self.case_state(it.case, outcome="not run", note=f"{server_name} went down; no other server may run it")

    # -- a lane

    def run_session(self, lane, kind, level, instructions, label, on_line=None):
        s = self.servers[lane.server.name]
        suite_file = self.suite_files[level]
        base = suite.workspace_for_suite_file(suite_file)
        logname = f"regression.fleet.{lane.name}"
        last = self.logs / f".last-session.{logname}"
        prompt_file = self.logs / f".prompt.{logname}.{kind}.md"
        reg.system_prompt(kind, prompt_file, s.server, s.health, s.url)
        prompt = reg.session_prompt(
            self.ticket_repo,
            suite_file,
            level,
            lane.workspace(base),
            s.text,
            s.head,
            instructions,
            self.provider,
            self.model,
            not s.server.primary,
        )
        session.run(
            label,
            logname,
            str(REPO),
            prompt_file,
            prompt,
            [*self.session_flags, *s.flags],
            model_env=self.model_env,
            session_env=s.session_env,
            logs=str(self.logs),
            last=str(last),
            log=s.log,
            on_line=on_line,
        )
        text = last.read_text(encoding="utf-8", errors="replace") if last.exists() else ""
        cost = sum(float(c) for c in COST_RE.findall(text))
        return text, cost, last

    def lane_main(self, lane):
        s = self.servers[lane.server.name]
        n = 0
        while not s.down:
            batch = self.take(lane)
            if not batch:
                break
            lane.batch = batch  # until it settles: a crash in between leaves it to _guard
            try:
                aborted = self.run_batch(lane, batch, n := n + 1)
            finally:
                self.done()
            lane.batch = []
            if aborted:
                break
        self.lane_state(lane, status="cases done", batch=[], live_case=None)

    def run_batch(self, lane, batch, n):
        """One chunk session for <batch>; True when the server reported itself unreachable."""
        s = self.servers[lane.server.name]
        level, excl = batch[0].level, batch[0].exclusive
        label = f"{s.rpfx}:{level}.{lane.name}.{n}"
        cases = [it.case for it in batch]
        for c in cases:
            self.case_state(c, outcome="running" if c == cases[0] else "next", lane=lane.name)
        self.lane_state(
            lane,
            status="waiting for the server" if excl else "running",
            level=level,
            batch=cases,
            live_case=None,
            since=time.time(),
        )
        s.gate.enter(excl)
        try:
            self.lane_state(lane, status="exclusive" if excl else "running")

            # a case's time runs from its REGRESSION-CASE line to the next one, or to the session's end
            secs, live = {}, [None, 0.0]

            def on_line(out, cases=cases):
                for line in out.split("\n"):  # one rendered event may be a whole message
                    m = CASE_RE.match(line)
                    if not m or m.group(1) not in cases or m.group(1) == live[0]:
                        continue
                    now = time.time()
                    if live[0]:
                        secs[live[0]] = secs.get(live[0], 0.0) + now - live[1]
                    live[:] = [m.group(1), now]
                    self.lane_state(lane, live_case=m.group(1))
                    self.case_state(m.group(1), outcome="running")

            text, cost, last = self.run_session(lane, "chunk", level, reg.chunk_instructions(cases), label, on_line)
            if live[0]:
                secs[live[0]] = secs.get(live[0], 0.0) + time.time() - live[1]
        finally:
            s.gate.leave(excl)
        self.settle(lane, batch, text, cost, last, secs)
        if outcome.aborted(last):
            self.server_down(lane.server.name)
            return True
        return False

    def settle(self, lane, batch, text, cost, last, secs=None):
        """Each case's outcome from the session's REGRESSION-RESULT lines, and
        for a pass or fail its time (<secs>), which later plans weigh it by
        (harness/durations.py)."""
        secs = secs or {}
        results = {c: (o, issue) for c, o, issue in RESULT_RE.findall(text)}
        skipped = set(SKIP_RE.findall(text))
        died = outcome.died(last)
        for it in batch:
            o, issue = results.get(it.case, (None, ""))
            if it.case in skipped or o == "skip":
                if not self.requeue(it, lane):
                    self.case_state(it.case, outcome="skip")
                continue
            if o is None and died and not it.retried:
                # the session went away before answering: once more, anywhere it may run
                it.retried = True
                if self.requeue(it, lane, why="had no answer (the session ended)", same_server=True):
                    continue
            if o is None:
                o = "not run" if died else "unreported"
            extra = {"issue": issue} if issue else {}
            if o in durations.OUTCOMES and it.case in secs:
                extra["secs"] = round(secs[it.case], 1)
            self.case_state(it.case, outcome=o, **extra)
        self.state.update(
            lambda d: [
                l.update(sessions=l["sessions"] + 1, cost=round(l["cost"] + cost, 4))
                for l in d["lanes"]
                if l["name"] == lane.name
            ]
        )

    def sweep_main(self, lane, notes):
        s = self.servers[lane.server.name]
        if s.down:
            return
        levels = sorted({it_level for it_level in self.levels_run.get(lane.name, ())})
        for level in levels:
            self.lane_state(lane, status="sweep", level=level, batch=[], since=time.time())
            base = suite.workspace_for_suite_file(self.suite_files[level])
            label = f"{s.rpfx}:{level}.{lane.name}.sweep"
            _, cost, _ = self.run_session(
                lane,
                "sweep",
                level,
                reg.sweep_instructions(lane.workspace(base), notes.get((lane.name, level), "")),
                label,
            )
            self.state.update(
                lambda d, cost=cost: [
                    l.update(sessions=l["sessions"] + 1, cost=round(l["cost"] + cost, 4))
                    for l in d["lanes"]
                    if l["name"] == lane.name
                ]
            )
        self.lane_state(lane, status="done", level=None)

    # -- the run

    def script_cases(self):
        """Script cases on the primary, once per level; their report goes to
        the primary's first lane's sweep, which files their failures."""
        notes = {}
        primary = self.lanes[0]
        s = self.servers[primary.server.name]
        runner = REPO / self.profile.get("suite.contract_runner", "contract/run.py")
        for lv, ids in self.script.items():
            if not ids:
                continue
            p = subprocess.run(
                ["python3", str(runner), "--url", s.url, *ids],
                env={**os.environ, "DW_TOKEN": s.token},  # not argv, where ps shows it
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            report = p.stdout.rstrip("\n")
            try:
                r = json.loads(report)
                by = {c.get("id"): c.get("status") for c in r.get("cases", [])}
            except (ValueError, AttributeError):
                by = {}
            for c in ids:
                st = by.get(c)
                self.case_state(c, outcome={"pass": "pass", "fail": "fail"}.get(st, "unreported"), lane="script")
            s.log.say(f"[{s.rpfx}:{lv}] script cases: " + ", ".join(f"{c} {by.get(c, '?')}" for c in ids))
            notes[(primary.name, lv)] = (
                "\n\nThese cases ran as scripts before this session (contract/run.py, a plain MCP client; see "
                f"'runner: script' on each): {' '.join(ids)}. Do not execute them. Their report:\n{report}\n"
                "For each case whose status is fail or error, report it ('Reporting a failure' in the role "
                "instructions) exactly as for a case you ran yourself, quoting its failures; a pass needs nothing. "
                "An error with 'server unreachable' is the MCP-unreachable case, not a per-case failure."
            )
            self.levels_run.setdefault(primary.name, set()).add(lv)
        return notes

    def run(self):
        self.levels_run = {}
        for lane in self.lanes:
            self.levels_run[lane.name] = {it.level for it in self.queues[lane.name]}
        self.state.update(lambda d: d.update(status="running"))
        notes = self.script_cases()
        threads = [
            threading.Thread(target=self._guard, args=(self.lane_main, lane), daemon=True) for lane in self.lanes
        ]
        self._join(threads)
        # a stolen or re-queued case changes which workspaces a lane used
        for d in self.state.data["cases"].values():
            if d.get("lane") and d["lane"] != "script":
                self.levels_run.setdefault(d["lane"], set()).add(d["level"])
        self.state.update(lambda d: d.update(status="sweeping"))
        threads = [
            threading.Thread(target=self._guard, args=(self.sweep_main, lane, notes), daemon=True)
            for lane in self.lanes
        ]
        self._join(threads)
        primary = self.servers[self.lanes[0].server.name]
        name, email = providers.co_author_for(
            self.provider, resolved_model(self.logs / f"regression.fleet.{self.lanes[0].name}.jsonl", self.model)
        )
        suite.commit_changes(
            REPO,
            str(self.logs),
            suite.commit_paths(self.lanes[0].server, self.profile.get("suite.perf_dir", "regression-perf")),
            f"regression: update {','.join(self.levels)} from {ts()} fleet run ({self.model_env.label})",
            name,
            email,
            primary.log.say,
        )
        return self.finish("done")

    def _guard(self, fn, *args):
        try:
            fn(*args)
        except Exception as e:  # a lane's failure is logged, never the fleet's end
            lane = args[0]
            self.servers[lane.server.name].log.say(f"[fleet] {lane.name} stopped: {type(e).__name__}: {e}")
            self.lane_state(lane, status=f"failed: {e}"[:200])
            # what it held goes unrun: its batch (cases still on this lane with no answer) and its queue
            with self.mu:
                held = [*lane.batch, *self.queues[lane.name]]
                lane.batch, self.queues[lane.name] = [], []
            note = f"{lane.name} stopped: {type(e).__name__}"
            for it in held:
                c = self.state.data["cases"].get(it.case, {})
                if c.get("lane") == lane.name and c.get("outcome") in ("queued", "running", "next"):
                    self.case_state(it.case, outcome="not run", note=note)

    @staticmethod
    def _join(threads):
        for t in threads:
            t.start()
        while any(t.is_alive() for t in threads):  # a join with a timeout keeps SIGTERM deliverable
            for t in threads:
                t.join(0.5)

    def finish(self, status):
        """Record the run's end and return the status recorded: a run that
        would be "done" is "failed" while any case has no answer (UNRESOLVED),
        since a lost case is not a passing one."""
        if self.state.data.get("finished"):
            return self.state.data["status"]
        if status == "done" and any(c.get("outcome") in UNRESOLVED for c in self.state.data["cases"].values()):
            status = "failed"
        self.state.update(lambda d: d.update(status=status, finished=time.time()))
        runs = self.state.path.parent / "runs"  # FLEET_DIR/runs, beside state.json
        runs.mkdir(exist_ok=True)
        shutil.copyfile(self.state.path, runs / f"{self.stamp}.json")
        counts = {}
        for c in self.state.data["cases"].values():
            counts[c.get("outcome")] = counts.get(c.get("outcome"), 0) + 1
        cost = sum(l["cost"] for l in self.state.data["lanes"])
        self.servers[self.lanes[0].server.name].log.say(
            f"[fleet] {status}: "
            + ", ".join(f"{n} {o}" for o, n in sorted(counts.items(), key=lambda x: -x[1]))
            + f"; ${cost:.2f}"
        )
        return status


def main(argv=None):
    ap = argparse.ArgumentParser(prog="python3 -m harness.drivers.fleet")
    ap.add_argument("--plan", action="store_true", help="print the assignment; run nothing")
    ap.add_argument("--json", action="store_true", help="the plan as JSON (with --plan)")
    ap.add_argument(
        "--allow-failures", action="store_true", help="exit 0 when cases fail (a run that lost cases still exits 1)"
    )
    ap.add_argument("level", nargs="?", default="smoke")
    a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    session.stop_on_sigterm()
    try:
        profile = load()
        names = (env("FLEET_SERVERS") or " ".join(s.name for s in profile.servers)).split()
        levels = [lv.name for lv in profile.levels] if a.level == "all" else [a.level]
        for lv in levels:
            if profile.level(lv) is None:
                raise ProfileError(f"unknown level '{lv}' (expected: {', '.join(l.name for l in profile.levels)}, all)")
        sidecar = requirements.load_sidecar()
        workspaces = [suite.workspace_for_suite_file(REPO / profile.level(lv).file) for lv in levels]
        sf = gather_all(profile, names, requirements.workflow_names(sidecar), workspaces=workspaces)
    except (ProfileError, ValueError) as e:
        err(str(e))
        return 1
    for f in sf.values():
        print(f.summary)
    if a.plan:
        lanes, plans = make_lanes(profile, sf), []
        est = durations.Estimates.load(FLEET_DIR / "runs", profile)
        if not a.json:
            print(f"case times: {est.known} case(s) measured in {FLEET_DIR / 'runs'}; others {est.default:.0f}s")
        for lv in levels:
            servers = [n for n in names if len(levels) == 1 or lv in profile.server(n).regression_all]
            p = plan_level(profile, lv, sf, sidecar, servers, lanes, est)
            plans.append(p)
            if not a.json:
                print(render(p, suite.workspace_for_suite_file(p.suite_file), timed=est.known > 0))
        if a.json:
            print(
                json.dumps(
                    [
                        {
                            "level": p.level,
                            "lanes": {
                                l.name: [c for lv, g in l.groups if lv == p.level for c in g.cases] for l in p.lanes
                            },
                            "unplaced": [{"cases": g.cases, "why": w} for g, w in p.unplaced],
                        }
                        for p in plans
                    ],
                    indent=1,
                )
            )
        return 0
    try:
        fleet = Fleet(profile, levels, names, sidecar, sf)
        fleet.plan()
        fleet.setup()
    except (ProfileError, providers.ProviderError, prompts.PromptError) as e:
        err(str(e))
        return 1
    try:
        status = fleet.run()
    except SystemExit:
        fleet.finish("stopped")
        raise
    except Exception as e:
        fleet.finish("failed")
        err(f"fleet: {type(e).__name__}: {e}")
        return 1
    if status == "failed":
        return 1
    failing = any(c.get("outcome") == "fail" for c in fleet.state.data["cases"].values())
    return 1 if failing and not a.allow_failures else 0


if __name__ == "__main__":
    sys.exit(main())
