"""The regression fleet: one level split across every server's lanes, each
case once, on a lane that can run it (docs/superpowers/specs/
2026-10-18-regression-fleet.md).

    python3 -m harness.drivers.fleet --plan [level]     # where each case would run
    FLEET_SERVERS="lem minid" python3 -m harness.drivers.fleet --plan smoke

--plan preflights every server, reads its facts (workers, cached models,
assets), checks them against its profile policy, and prints the
assignment. It runs no session and takes no lock. Running the plan is the
next step; until then run-regression.sh / harness.drivers.regression run
one server at a time.
"""
import argparse
import json
import os
import sys
from dataclasses import dataclass, field

from .. import REPO, facts, requirements, suite
from ..log import err
from ..profile import ProfileError, load, resolve_token, resolve_url


@dataclass
class Lane:
    server: object
    slot: int
    facts: object
    groups: list = field(default_factory=list)
    load: float = 0.0          # assigned work, in primary-lane case units

    @property
    def name(self):
        return f"{self.server.name}-{self.slot}"

    def workspace(self, base):
        return f"{base}.{self.name}"


@dataclass
class Plan:
    level: str
    suite_file: object
    lanes: list
    unplaced: list = field(default_factory=list)   # (group, {server: why})
    script_cases: list = field(default_factory=list)


def gather_all(profile, names, workflows=(), environ=os.environ, gather=facts.gather,
               validate=facts.validate_workflows):
    """{server: facts} for <names>, each having validated <workflows>;
    ProfileError listing every server that can't take part (no token, not
    answering, policy the facts can't meet)."""
    out, problems = {}, []
    for name in names:
        s = profile.server(name)
        try:
            url = resolve_url(s, environ.get("DW_URL", "") if len(names) == 1 else "")
            token = resolve_token(s, None if environ is os.environ else environ)
            f = gather(s, url, token)
            f.workflows = validate(url, token, list(workflows))
        except (ProfileError, facts.FactsError) as e:
            problems.append(f"{name}: {e}")
            continue
        problems += facts.check(s, f)
        out[name] = f
    if problems:
        raise ProfileError("the fleet can't start:\n  " + "\n  ".join(problems))
    return out


def plan_level(profile, level, server_facts, sidecar, level_servers=None):
    """Assigns <level>'s dependency groups to lanes, longest first, each to
    the eligible lane that would finish it soonest."""
    lv = profile.level(level)
    suite_file = REPO / lv.file
    script = suite.script_cases(suite_file, REPO / profile.get("suite.contract_cases", "contract/cases"))
    lanes = [Lane(server=profile.server(n), slot=i + 1, facts=f)
             for n, f in server_facts.items() if level_servers is None or n in level_servers
             for i in range(profile.server(n).lanes)]
    ref = requirements.reference_sizes(server_facts.values())
    p = Plan(level=level, suite_file=suite_file, lanes=lanes, script_cases=script)
    for g in sorted(requirements.groups(suite_file, sidecar, skip=script), key=lambda g: -g.weight):
        why, best = {}, None
        for lane in lanes:
            s = lane.server
            held = [c for c in g.cases if c in s.regression_skip_cases]
            ok, reason = (False, f"{held[0]} is held back here") if held else \
                requirements.eligible(g.need, s, lane.facts, ref)
            if not ok:
                why[s.name] = reason
                continue
            finish = lane.load + g.weight / s.speed
            if best is None or finish < best[0]:
                best = (finish, lane)
        if best is None:
            p.unplaced.append((g, why))
            continue
        best[1].groups.append(g)
        best[1].load = best[0]
    return p


def render(p, workspace):
    out = [f"== {p.level}: {sum(len(g.cases) for l in p.lanes for g in l.groups)} cases on {len(p.lanes)} lane(s)"]
    if p.script_cases:
        out.append(f"   script cases (contract/run.py, on the primary): {' '.join(p.script_cases)}")
    for lane in p.lanes:
        cases = [c for g in lane.groups for c in g.cases]
        excl = [c for g in lane.groups if g.need.load == "exclusive" for c in g.cases]
        out.append(f"   {lane.name:10} {len(cases):4} cases  ~{lane.load:6.1f} units  workspace {lane.workspace(workspace)}")
        if excl:
            out.append(f"   {'':10} exclusive (its server's other lanes idle): {' '.join(excl)}")
    for g, why in p.unplaced:
        out.append(f"   unplaced {' '.join(g.cases)}: " + "; ".join(f"{s}: {w}" for s, w in why.items()))
    reasons = {}
    for lane in p.lanes:
        for g in lane.groups:
            if not g.need.known:
                reasons[g.need.why_unknown] = reasons.get(g.need.why_unknown, 0) + len(g.cases)
    for r, n in sorted(reasons.items(), key=lambda x: -x[1]):
        out.append(f"   {n} case(s) primary only: {r}")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="python3 -m harness.drivers.fleet")
    ap.add_argument("--plan", action="store_true", help="print the assignment; run nothing")
    ap.add_argument("--json", action="store_true", help="the plan as JSON")
    ap.add_argument("level", nargs="?", default="smoke")
    a = ap.parse_args(sys.argv[1:] if argv is None else argv)
    if not a.plan:
        err("only --plan exists yet: running the plan is the next step")
        return 2
    try:
        profile = load()
        names = (os.environ.get("FLEET_SERVERS") or " ".join(s.name for s in profile.servers)).split()
        levels = [lv.name for lv in profile.levels] if a.level == "all" else [a.level]
        for lv in levels:
            if profile.level(lv) is None:
                raise ProfileError(f"unknown level '{lv}' (expected: {', '.join(l.name for l in profile.levels)}, all)")
        sidecar = requirements.load_sidecar()
        sf = gather_all(profile, names, requirements.workflow_names(sidecar))
    except (ProfileError, ValueError) as e:
        err(str(e))
        return 1
    for f in sf.values():
        print(f.summary)
    plans = []
    for lv in levels:
        servers = [n for n in names if a.level != "all" or lv in profile.server(n).regression_all]
        p = plan_level(profile, lv, sf, sidecar, servers)
        plans.append(p)
        if not a.json:
            print(render(p, suite.workspace_for_suite_file(p.suite_file)))
    if a.json:
        print(json.dumps([{"level": p.level, "lanes": {l.name: [c for g in l.groups for c in g.cases] for l in p.lanes},
                           "unplaced": [{"cases": g.cases, "why": w} for g, w in p.unplaced]} for p in plans], indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
