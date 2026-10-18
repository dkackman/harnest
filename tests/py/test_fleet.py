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

    def test_a_case_line_starting_with_hash_is_not_a_heading(self):
        Path(self.d.name, "s.md").write_text(
            "### S-F001 — one\n#338: an issue reference opens the text\n```json\n# a comment in an example\n```\n"
            "cleanup: S-F002 reads it.\n#### a sub-heading ends it\n### S-F002 — two\nsteps\n"
        )
        b = r.case_blocks(Path(self.d.name, "s.md"))
        self.assertEqual(["S-F001", "S-F002"], list(b))
        self.assertIn("#338: an issue reference", b["S-F001"])
        self.assertIn("cleanup: S-F002 reads it.", b["S-F001"])
        self.assertNotIn("sub-heading", b["S-F001"])
        self.assertEqual([["S-F001", "S-F002"]], [g.cases for g in r.groups(Path(self.d.name, "s.md"), {})])

    def test_every_real_case_has_a_body(self):
        for f in sorted(Path(__file__).resolve().parents[2].glob("regression-suite-*.md")):
            for c, text in r.case_blocks(f).items():
                self.assertGreater(len(text.splitlines()), 2, f"{f.name} {c}")

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
        # one that can't be validated bare says nothing; the listed models decide
        self.assertEqual((True, ""), r.eligible(need, srv("mac"), fx("mac", workflows=broken), {}))
        with_model = r.Need(workflows=need.workflows, models=("ltx",), known=True)
        self.assertEqual(
            (False, "ltx is not cached"), r.eligible(with_model, srv("mac"), fx("mac", workflows=broken), {})
        )
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
            where = {c: l.name for l in p.lanes for _, g in l.groups for c in g.cases}
            self.assertEqual(["lem-1", "lem-2", "mini-ai-1", "minid-1"], [l.name for l in p.lanes])
            self.assertTrue(where["S-F004"].startswith("lem-"), "H3 stays on lem")
            self.assertTrue(where["S-F005"].startswith("lem-"), "no entry: primary only")
            self.assertEqual(where["S-F002"], where["S-F003"], "a group shares a lane")
            self.assertEqual(5, len(where))
            # a server's first lane works in the level's own workspace; a second gets its own
            self.assertEqual("regression-x", p.lanes[3].workspace("regression-x"))
            self.assertEqual("regression-x-lem-2", p.lanes[1].workspace("regression-x"))

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


class Running(unittest.TestCase):
    def test_the_gate_runs_an_exclusive_session_alone(self):
        import threading
        import time as t

        g, log = fleet.Gate(), []

        def ordinary(name):
            g.enter(False)
            log.append(f"{name}+")
            t.sleep(0.05)
            log.append(f"{name}-")
            g.leave(False)

        def exclusive():
            g.enter(True)
            log.append("X+")
            t.sleep(0.05)
            log.append("X-")
            g.leave(True)

        a = threading.Thread(target=ordinary, args=("a",))
        a.start()
        t.sleep(0.01)
        x = threading.Thread(target=exclusive)
        x.start()
        t.sleep(0.01)
        b = threading.Thread(target=ordinary, args=("b",))  # arrives while X waits: X goes first
        b.start()
        for th in (a, x, b):
            th.join()
        self.assertEqual(["a+", "a-", "X+", "X-", "b+", "b-"], log)

    def test_batches_split_at_exclusive_cases_and_levels(self):
        f = fleet.Fleet.__new__(fleet.Fleet)
        import threading

        f.mu, f.per, f.started_gids = threading.RLock(), 3, set()
        f.cv, f.busy, f.idle, f.min_batch = threading.Condition(f.mu), 0, 0, 1
        lane = fleet.Lane(server=srv("lem", primary=True), slot=1, facts=fx("lem"))
        f.lanes = [lane]
        f.servers = {"lem": type("S", (), {"down": False})()}
        it = lambda lv, c, x=False: fleet.Item(level=lv, case=c, gid=f"{lv}:{c}", exclusive=x)
        f.queues = {
            lane.name: [
                it("s", "A"),
                it("s", "B"),
                it("s", "P", True),
                it("s", "Q", True),  # exclusive cases share one exclusive session
                it("s", "C"),
                it("s", "D"),
                it("s", "E"),
                it("s", "F"),
                it("c", "G"),
            ]
        }
        batches = []
        while (b := f.take(lane)) is not None:
            batches.append([i.case for i in b])
            f.done()  # as a lane does after each batch
        self.assertEqual([["A", "B"], ["P", "Q"], ["C", "D", "E"], ["F"], ["G"]], batches)

    def fleet3(self, min_batch=3, queues=None, speeds=(1.0, 1.0, 0.25)):
        """lem-1, lem-2 and a slow mac lane, with single-case groups queued as given."""
        import threading

        f = fleet.Fleet.__new__(fleet.Fleet)
        f.mu = threading.RLock()
        f.cv, f.busy, f.idle, f.per, f.min_batch, f.started_gids = threading.Condition(f.mu), 0, 0, 8, min_batch, set()
        lem1 = fleet.Lane(server=srv("lem", primary=True, speed=speeds[0]), slot=1, facts=fx("lem"))
        lem2 = fleet.Lane(server=srv("lem", primary=True, speed=speeds[1]), slot=2, facts=fx("lem"))
        mac = fleet.Lane(server=srv("mac", speed=speeds[2]), slot=1, facts=fx("mac"))
        f.lanes = [lem1, lem2, mac]
        f.servers = {n: type("S", (), {"down": False})() for n in ("lem", "mac")}
        f.queues = {l.name: [] for l in f.lanes}
        f.case_need, f.group_need, f.ref = {}, {}, {}
        f.case_state = f.event = lambda *a, **k: None
        for name, cases in (queues or {}).items():
            for c in cases:
                gid = f"smoke:{c}"
                f.case_need[c] = r.Need(load="none", known=True)
                f.group_need[gid] = ("smoke", r.Group(cases=[c], need=f.case_need[c]))
                f.queues[name].append(fleet.Item(level="smoke", case=c, gid=gid, exclusive=False))
        return f, lem1, lem2, mac

    def test_a_requeued_case_can_be_stolen(self):
        """On the first live fleet run a re-queued case's new group id was
        never registered, and every idle lane that looked for work to steal
        died on a KeyError."""
        f, lem1, lem2, mac = self.fleet3(min_batch=1)
        for c in ("S-F027", "S-F124"):
            f.case_need[c] = r.Need(load="none", known=True)
            self.assertTrue(f.requeue(fleet.Item(level="smoke", case=c, gid=f"smoke:{c}", exclusive=False), mac))
        owner = lem1 if f.queues[lem1.name] else lem2
        thief = lem2 if owner is lem1 else lem1
        self.assertEqual(1, len(f._take(thief) or []), "the other lem lane steals one")

    def test_steals_are_worth_a_session(self):
        ids = [f"S-F{n:03d}" for n in range(1, 8)]
        # an equally fast victim keeps a full batch: 5 unstarted is under two batches of 3
        f, lem1, lem2, mac = self.fleet3(queues={"lem-1": ids[:5]})
        self.assertIsNone(f._take(lem2))
        # with 6 it gives up a full batch, from the end of its queue
        f, lem1, lem2, mac = self.fleet3(queues={"lem-1": ids[:6]})
        self.assertEqual(["S-F004", "S-F005", "S-F006"], [i.case for i in f._take(lem2)])
        self.assertEqual(ids[:3], [i.case for i in f.queues["lem-1"]])
        # a slower victim gives up one batch's worth
        f, lem1, lem2, mac = self.fleet3(queues={"mac-1": ids[:3]})
        self.assertEqual(3, len(f._take(lem1)))
        f, lem1, lem2, mac = self.fleet3(queues={"mac-1": ids[:2]})
        self.assertIsNone(f._take(lem1), "two cases aren't worth a session's setup")
        # started groups stay put
        f, lem1, lem2, mac = self.fleet3(queues={"lem-1": ids[:7]})
        f.started_gids = {f"smoke:{c}" for c in ids}
        self.assertIsNone(f._take(lem2))

    def test_batch_size_follows_speed_and_shrinks_while_lanes_idle(self):
        f = fleet.Fleet.__new__(fleet.Fleet)
        f.per, f.idle, f.min_batch = 8, 0, 3
        fast = fleet.Lane(server=srv("lem", primary=True), slot=1, facts=fx("lem"))
        slow = fleet.Lane(server=srv("minid", speed=0.25), slot=1, facts=fx("minid"))
        self.assertEqual((8, 3), (f.batch_cap(fast, 20), f.batch_cap(slow, 20)), "a slow lane: never under 3")
        f.idle = 3  # three lanes waiting: a lane takes its share of what's left, not under 3
        self.assertEqual((4, 3, 3), (f.batch_cap(fast, 16), f.batch_cap(fast, 7), f.batch_cap(fast, 1)))

    def test_results_and_skips_are_read_from_the_session(self):
        text = (
            "REGRESSION-RESULT: S-F001 pass\n- REGRESSION-RESULT: S-F002 fail #812\n"
            "REGRESSION-SKIP: S-F003 fixture qa-cast/x.wav\nREGRESSION-RESULT: S-F003 skip\n"
        )
        self.assertEqual(
            [("S-F001", "pass", ""), ("S-F002", "fail", "#812"), ("S-F003", "skip", "")], fleet.RESULT_RE.findall(text)
        )
        self.assertEqual(["S-F003"], fleet.SKIP_RE.findall(text))
        self.assertEqual("S-F004", fleet.CASE_RE.match("REGRESSION-CASE: S-F004").group(1))


class Watchdog(unittest.TestCase):
    LIMITS = {"SESSION_STALL_SECS": 900, "SESSION_TOOL_STALL_SECS": 2400, "SESSION_REJECTED_STALL_SECS": 120}

    def dog(self, **limits):
        from harness import session

        class Proc:
            killed = False

            def poll(self):
                return 0 if self.killed else None

        now = [0.0]
        d = session.Watchdog(
            Proc(),
            lambda m: None,
            clock=lambda: now[0],
            limits={**self.LIMITS, **limits},
            kill=lambda p: setattr(p, "killed", True),
            watch=False,
        )
        return d, now

    def test_quiet_limits_depend_on_what_the_session_is_doing(self):
        d, now = self.dog()
        d.saw("> mcp__dw__wait_for_job {}")
        now[0] = 1900
        self.assertFalse(d.check(), "a tool call may block for 30 minutes")
        d.saw("< 120 chars")
        now[0] = 1900 + 800
        self.assertFalse(d.check())
        now[0] = 1900 + 901
        self.assertTrue(d.check(), "the model's turn, quiet for 15 minutes: stalled")
        self.assertIn("on the model's turn", d.killed)
        self.assertTrue(d.proc.killed)

    def test_a_rejected_limit_then_silence_is_stopped_soon(self):
        d, now = self.dog()
        d.saw("rate-limit: status=rejected type=five_hour overage=true resets=x resets_epoch=1")
        now[0] = 119
        self.assertFalse(d.check())
        now[0] = 121
        self.assertTrue(d.check(), "stopped, so the driver sleeps until the reset and retries")
        d, now = self.dog()
        d.saw("rate-limit: status=rejected type=five_hour overage=true resets=x resets_epoch=1")
        d.saw("· ctx=1k out=1")  # the model answered after all
        now[0] = 500
        self.assertFalse(d.check())

    def test_zero_turns_a_limit_off(self):
        d, now = self.dog(SESSION_STALL_SECS=0)
        now[0] = 10**6
        self.assertFalse(d.check())


if __name__ == "__main__":
    unittest.main()
