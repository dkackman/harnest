"""The regression fleet's dispatch, offline: dependency groups, requirements
entries, eligibility against a server's facts and policy, and the plan.
Facts are made up here; facts.gather and validate_workflows are what read
them from a live server."""

import tempfile
import unittest
from pathlib import Path

from harness import facts
from harness import requirements as r
from harness.drivers import fleet
from harness.profile import Server, load

SUITE = """# suite
## Fixtures
none
### S-F001 — validate only
steps
cleanup: none (read-only).

### S-F002 — makes an image
steps
cleanup: S-F003 inspects this output first; delete it after.

### S-F003 — reads S-F002's image
Same probe as S-F001, on the image.
cleanup: delete both.

### S-F004 — H3 shot
steps

### S-F005 — LTX shot
steps
"""


def srv(name, primary=False, **kw):
    return Server(name=name, host=name, dir="~/dw", backend="mps", port=8765, primary=primary, **kw)


def fx(name, models=(), workflows=None, assets=(), workers=1):
    return facts.ServerFacts(
        server=name,
        hostname=f"{name}.lan",
        device="mps",
        workers=[{"device": "mps", "vram_gb": 18}] * workers,
        models={m: gb for m, gb in models},
        assets=set(assets),
        workflows=workflows or {},
    )


class Groups(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory()
        self.suite = Path(self.d.name, "regression-suite-x.md")
        self.suite.write_text(SUITE)

    def tearDown(self):
        self.d.cleanup()

    def test_linked_by_cleanup_and_setup_only(self):
        g = r.groups(self.suite, {})
        self.assertEqual([["S-F001"], ["S-F002", "S-F003"], ["S-F004"], ["S-F005"]], [x.cases for x in g])

    def test_skipped_cases_drop_out_with_their_links(self):
        g = r.groups(self.suite, {}, skip=("S-F003",))
        self.assertEqual([["S-F001"], ["S-F002"], ["S-F004"], ["S-F005"]], [x.cases for x in g])

    def test_entries_and_staleness(self):
        b = r.case_blocks(self.suite)
        side = {
            "S-F001": {"load": "none", "hash": r.block_hash(b["S-F001"])},
            "S-F002": {"load": "light", "models": ["sd15"], "hash": "stale"},
            "S-F004": {"load": "huge", "hash": r.block_hash(b["S-F004"])},
        }
        self.assertTrue(r.need_for("S-F001", b["S-F001"], side).known)
        self.assertEqual("the case changed since its entry", r.need_for("S-F002", b["S-F002"], side).why_unknown)
        self.assertEqual("no requirements entry", r.need_for("S-F003", b["S-F003"], side).why_unknown)
        self.assertEqual("unknown load 'huge'", r.need_for("S-F004", b["S-F004"], side).why_unknown)
        # reflowing a case's text keeps its entry current
        self.assertEqual(r.block_hash("a  b\nc"), r.block_hash("a b c"))

    def test_a_group_needs_what_all_its_cases_need(self):
        b = r.case_blocks(self.suite)
        side = {
            c: {"load": l, "models": m, "hash": r.block_hash(b[c])}
            for c, l, m in [("S-F002", "light", ["sd15"]), ("S-F003", "heavy", ["ltx"])]
        }
        g = [x for x in r.groups(self.suite, side) if "S-F002" in x.cases][0]
        self.assertEqual((("ltx", "sd15"), "heavy", True), (g.need.models, g.need.load, g.need.known))


class Eligible(unittest.TestCase):
    REF = {"sd15": 5, "ltx": 160, "h3": 196}

    def test_unknown_needs_go_to_the_primary_only(self):
        n = r.Need(why_unknown="no requirements entry")
        self.assertEqual((True, ""), r.eligible(n, srv("lem", primary=True), fx("lem"), self.REF))
        self.assertEqual((False, "primary only: no requirements entry"), r.eligible(n, srv("mac"), fx("mac"), self.REF))

    def test_policy_and_facts(self):
        minid = srv("minid", heavy=False, max_model_gb=8)
        mini = srv("mini-ai", deny_models=("h3*",))
        lem = srv("lem", primary=True, downloads=True)
        cases = [
            (r.Need(load="none", known=True), minid, fx("minid"), True, ""),
            (r.Need(models=("sd15",), known=True), minid, fx("minid", [("sd15", 5)]), True, ""),
            (r.Need(models=("sd15",), known=True), minid, fx("minid"), False, "sd15 is not cached"),
            (
                r.Need(models=("ltx",), load="heavy", known=True),
                minid,
                fx("minid", [("ltx", 160)]),
                False,
                "heavy load",
            ),
            (r.Need(models=("ltx",), known=True), minid, fx("minid", [("ltx", 160)]), False, "ltx is 160 GB, over 8"),
            # a partial cache looks present: the deny list is what keeps H3 off
            (
                r.Need(models=("h3",), load="heavy", known=True),
                mini,
                fx("mini-ai", [("h3", 50)]),
                False,
                "h3 is denied here",
            ),
            (r.Need(models=("h3",), load="heavy", known=True), lem, fx("lem"), True, ""),
            (
                r.Need(assets=("qa-cast/a.wav",), known=True),
                minid,
                fx("minid"),
                False,
                "asset qa-cast/a.wav is not here",
            ),
        ]
        for need, s, f, ok, why in cases:
            self.assertEqual((ok, why), r.eligible(need, s, f, self.REF), (need, s.name))

    def test_the_server_says_what_a_workflow_lacks(self):
        need = r.Need(workflows=("templates/ltx2/two-stage",), known=True)
        missing = {
            "templates/ltx2/two-stage": {"missing": [{"repo": "ltx", "gb": 162.5, "blocked": False}], "error": ""}
        }
        blocked = {
            "templates/ltx2/two-stage": {"missing": [{"repo": "ltx", "gb": 162.5, "blocked": True}], "error": ""}
        }
        broken = {"templates/ltx2/two-stage": {"missing": [], "error": "workflow_path must name a workflow"}}
        ok = {"templates/ltx2/two-stage": {"missing": [], "error": ""}}
        self.assertEqual(
            (False, "ltx is not cached (162 GB to download)"),
            r.eligible(need, srv("mac"), fx("mac", workflows=missing), {}),
        )
        self.assertEqual(
            (True, ""), r.eligible(need, srv("lem", primary=True, downloads=True), fx("lem", workflows=missing), {})
        )
        self.assertIn(
            "licence-gated",
            r.eligible(need, srv("lem", primary=True, downloads=True), fx("lem", workflows=blocked), {})[1],
        )
        self.assertIn("doesn't validate here", r.eligible(need, srv("mac"), fx("mac", workflows=broken), {})[1])
        self.assertEqual((True, ""), r.eligible(need, srv("mac"), fx("mac", workflows=ok), {}))
        # validate's full size wins over a partial cache's
        self.assertEqual(162.5, r.reference_sizes([fx("a", [("ltx", 50)], workflows=missing)])["ltx"])


class Policy(unittest.TestCase):
    def test_facts_must_meet_policy(self):
        self.assertEqual([], facts.check(srv("lem", lanes=2), fx("lem", workers=2)))
        self.assertIn("2 lanes but 1 worker(s)", facts.check(srv("mac", lanes=2), fx("mac"))[0])
        bad = facts.check(Server(name="lem", host="lem", dir="~", backend="cuda", port=1, primary=True), fx("lem"))
        self.assertIn("the profile says cuda, the server says mps", bad[0])

    def test_gather_refuses_another_host(self):
        s = srv("minid")
        with self.assertRaises(facts.FactsError):
            facts.gather(
                s, "u", "t", health=lambda *_: {"status": "ok", "hostname": "lem"}, inventory=lambda *_: ({}, set())
            )
        with self.assertRaises(facts.FactsError):
            facts.gather(s, "u", "t", health=lambda *_: None)
        f = facts.gather(
            s,
            "u",
            "t",
            health=lambda *_: {"status": "ok", "hostname": "minid.lan", "device": "mps", "workers": [{"name": "M4"}]},
            inventory=lambda *_: ({"sd15": 5.1}, {"qa-cast/a.wav"}),
        )
        self.assertEqual((1, {"sd15": 5.1}), (len(f.workers), f.models))

    def test_the_profile_servers(self):
        p = load()
        lem, mini, minid = (p.server(n) for n in ("lem", "mini-ai", "minid"))
        self.assertEqual((2, True), (lem.lanes, lem.downloads))
        self.assertIn("MiniMaxAI/MiniMax-H3*", mini.deny_models)
        self.assertEqual((False, 8.0, False, True), (minid.heavy, minid.max_model_gb, minid.loop, minid.local))


class Plan(unittest.TestCase):
    def test_assignment(self):
        with tempfile.TemporaryDirectory() as d:
            suite_file = Path(d, "regression-suite-x.md")
            suite_file.write_text(SUITE)
            b = r.case_blocks(suite_file)
            entry = lambda c, **kw: {**kw, "hash": r.block_hash(b[c])}
            side = {
                "S-F001": entry("S-F001", load="none"),
                "S-F002": entry("S-F002", load="light", models=["sd15"]),
                "S-F003": entry("S-F003", load="light", models=["sd15"]),
                "S-F004": entry("S-F004", load="heavy", models=["h3"]),
            }
            profile = load()
            profile.levels = [type(profile.levels[0])(name="x", file=str(suite_file))]
            sf = {
                "lem": fx("lem", [("sd15", 5), ("h3", 196)], workers=2),
                "mini-ai": fx("mini-ai", [("sd15", 5), ("h3", 50)]),
                "minid": fx("minid", [("sd15", 5)]),
            }
            p = fleet.plan_level(profile, "x", sf, side)
            where = {c: l.name for l in p.lanes for g in l.groups for c in g.cases}
            self.assertEqual(["lem-1", "lem-2", "mini-ai-1", "minid-1"], [l.name for l in p.lanes])
            self.assertTrue(where["S-F004"].startswith("lem-"), "H3 stays on lem")
            self.assertTrue(where["S-F005"].startswith("lem-"), "no entry: primary only")
            self.assertEqual(where["S-F002"], where["S-F003"], "a group shares a lane")
            self.assertEqual(5, len(where))
            self.assertEqual("regression-x.minid-1", p.lanes[3].workspace("regression-x"))

    def test_gather_all_reports_every_server_that_cant_join(self):
        profile = load()

        def gather(s, url, token):
            if s.name == "mini-ai":
                raise facts.FactsError("no dw server answering")
            return fx(s.name, workers=1)

        with self.assertRaises(Exception) as e:
            fleet.gather_all(
                profile, ["lem", "mini-ai", "minid"], environ={"DW_TOKEN": "t"}, gather=gather, validate=lambda *a: {}
            )
        msg = str(e.exception)
        self.assertIn("mini-ai: no dw server answering", msg)
        self.assertIn("lem: 2 lanes but 1 worker(s)", msg)
        self.assertNotIn("minid", msg)


if __name__ == "__main__":
    unittest.main()
