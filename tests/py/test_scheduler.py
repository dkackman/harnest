import unittest

from harness.scheduler import Item, Pool, Scheduler, needs


class Clock:
    def __init__(self, t=0.0):
        self.t = t

    def __call__(self):
        return self.t


def mk(free=3, servers=None, clock=None):
    pool = Pool(servers or {"lem": 1, "mini-ai": 1}, free)
    return Scheduler(pool, clock=clock or Clock()), pool


def it(queue, issue=1, server="lem", **kw):
    return Item(queue, issue, server, **kw)


class NeedsTest(unittest.TestCase):
    def test_map(self):
        self.assertEqual(needs(it("tester:verify"), "lem"), {"gpu:lem"})
        self.assertEqual(needs(it("tester:task", None), "lem"), {"gpu:lem"})
        self.assertEqual(needs(it("tester:spec"), "lem"), {"free"})
        self.assertEqual(needs(it("implementer:fix"), "lem"), {"src:lem", "free"})
        self.assertEqual(needs(it("lead:closeout"), "lem"), {"src:lem", "free"})
        self.assertEqual(needs(it("lead:design"), "lem"), {"leadtree:lem", "free"})
        self.assertEqual(needs(it("reviewer:arch", server=None), "lem"), {"free"})
        self.assertEqual(needs(it("curator", None, None), "lem"), {"free"})
        self.assertEqual(needs(it("regression", None), "lem"), {"gpu:lem"})

    def test_unknown_raises(self):
        with self.assertRaises(ValueError):
            needs(it("bogus"), "lem")
        with self.assertRaises(ValueError):
            needs(it("deploy"), "lem")

    def test_key(self):
        self.assertEqual(it("tester:verify", 5).key, ("tester:verify", 5))

    def test_issueless_items_are_one_per_server(self):
        a, b = it("tester:closures", None, "lem"), it("tester:closures", None, "mini-ai")
        self.assertNotEqual(a.key, b.key)
        s, _ = mk()
        s.offer([a, b])
        self.assertEqual(len(s.next_dispatches()), 2)


class SchedulerTest(unittest.TestCase):
    def test_code_item_runs_while_gpu_busy(self):
        s, pool = mk()
        v = it("tester:verify", 1)
        s.offer([v])
        self.assertEqual(s.next_dispatches(), [(v, "lem")])
        self.assertFalse(s.gpu_idle("lem"))
        f = it("implementer:fix", 2)
        s.offer([f])
        self.assertEqual(s.next_dispatches(), [(f, "lem")])

    def test_gpu_slot_exclusive(self):
        s, _ = mk()
        a, b = it("tester:verify", 1), it("tester:answer", 2)
        s.offer([a, b])
        self.assertEqual(s.next_dispatches(), [(a, "lem")])

    def test_priority_order(self):
        s, _ = mk(free=2)
        d, a = it("lead:design", 1), it("reviewer:arch", 2, None, candidates=("lem",))
        s.offer([d, a])
        first = s.next_dispatches()
        self.assertEqual(first[0][0], a)

    def test_reserve_blocks_non_feeder_at_one_free_unit(self):
        s, _ = mk(free=1)
        d, a = it("lead:design", 1), it("reviewer:arch", 2, None, candidates=("lem",))
        s.offer([d, a])
        self.assertEqual([i for i, _ in s.next_dispatches()], [a])

    def test_single_free_slot_does_not_starve_non_feeders(self):
        s, _ = mk(free=1)
        d = it("lead:design", 1)
        s.offer([d])
        self.assertEqual(s.next_dispatches(), [(d, "lem")])

    def test_finished_releases_recorded_server(self):
        s, pool = mk()
        t = it("tester:task", 1, None, candidates=("lem",))
        s.offer([t])
        self.assertEqual(s.next_dispatches(), [(t, "lem")])
        s.finished(t, "mini-ai", True)
        self.assertTrue(s.gpu_idle("lem"))

    def test_reserve_under_feeder_load(self):
        s, _ = mk(free=3)
        f1, f2 = it("implementer:fix", 1, "lem"), it("implementer:fix", 2, "mini-ai")
        d = it("lead:design", 3, "lem")
        s.offer([f1, f2, d])
        self.assertEqual([i for i, _ in s.next_dispatches()], [f1, f2])
        s.finished(f1, "lem", True)
        s.offer([d])
        self.assertEqual([i for i, _ in s.next_dispatches()], [d])

    def test_reserved_free_slot(self):
        s, _ = mk(free=3)
        ds = [it("lead:design", n, "lem" if n == 1 else "mini-ai") for n in (1, 2)]
        d3 = it("reviewer:docs", 3, None, candidates=("lem",))
        s.offer(ds + [d3])
        got = s.next_dispatches()
        self.assertEqual(len(got), 2)
        f = it("implementer:fix", 9)
        s.offer([f])
        self.assertEqual(s.next_dispatches(), [(f, "lem")])

    def test_src_serializes_fix_and_build(self):
        s, _ = mk()
        f, b = it("implementer:fix", 1), it("lead:build", 2)
        s.offer([f, b])
        got = s.next_dispatches()
        self.assertEqual(got, [(f, "lem")])
        s.finished(f, "lem", True)
        s.offer([b])
        self.assertEqual(s.next_dispatches(), [(b, "lem")])

    def test_leadtree_serializes_design_and_decompose(self):
        s, _ = mk()
        d, c = it("lead:design", 1), it("lead:decompose", 2)
        s.offer([d, c])
        self.assertEqual(s.next_dispatches(), [(c, "lem")])

    def test_hold_blocks_gpu_only(self):
        s, _ = mk()
        v, f = it("tester:verify", 1), it("implementer:fix", 2)
        s.hold("lem", "deploy")
        s.offer([v, f])
        self.assertEqual(s.next_dispatches(), [(f, "lem")])
        s.unhold("lem")
        self.assertEqual(s.next_dispatches(), [(v, "lem")])

    def test_pause_until(self):
        clk = Clock(10)
        s, _ = mk(clock=clk)
        v = it("tester:verify", 1)
        s.pause_until(100)
        s.offer([v])
        self.assertEqual(s.next_dispatches(), [])
        clk.t = 100
        self.assertEqual(s.next_dispatches(), [(v, "lem")])

    def test_item_dispatched_once_across_servers(self):
        s, _ = mk()
        a = it("reviewer:arch", 1, None, candidates=("lem", "mini-ai"))
        s.offer([a])
        self.assertEqual(len(s.next_dispatches()), 1)
        s.offer([a])
        self.assertEqual(s.next_dispatches(), [])

    def test_candidates_fall_through(self):
        s, _ = mk()
        v1 = it("tester:verify", 1)
        v2 = it("tester:verify", 2, None, candidates=("lem", "mini-ai"))
        s.offer([v1, v2])
        self.assertEqual(s.next_dispatches(), [(v1, "lem"), (v2, "mini-ai")])

    def test_failed_item_waits_for_next_snapshot(self):
        s, _ = mk()
        v = it("tester:verify", 1)
        s.offer([v])
        s.next_dispatches()
        s.finished(v, "lem", False)
        self.assertEqual(s.next_dispatches(), [])
        s.offer([v])
        self.assertEqual(s.next_dispatches(), [(v, "lem")])

    def test_standing_task_last(self):
        s, _ = mk()
        t, v = it("tester:task", None), it("tester:verify", 1)
        s.offer([t, v])
        self.assertEqual(s.next_dispatches(), [(v, "lem")])

    def test_regression_needs_idle_gpu_and_takes_all(self):
        s = Scheduler(Pool({"lem": 2}, 3))
        r = it("regression", None)
        s.offer([r])
        self.assertEqual(s.next_dispatches(), [(r, "lem")])
        s.offer([it("tester:verify", 1)])
        self.assertEqual(s.next_dispatches(), [])
        s.finished(r, "lem", True)
        self.assertTrue(s.gpu_idle("lem"))

    def test_regression_waits_for_busy_gpu(self):
        s, _ = mk(servers={"lem": 2})
        v = it("tester:verify", 1)
        r = it("regression", None)
        s.offer([v])
        s.next_dispatches()
        s.offer([r])
        self.assertEqual(s.next_dispatches(), [])

    def test_pool_release_and_busy(self):
        pool = Pool({"lem": 1}, 3)
        f = it("implementer:fix", 1)
        pool.take(f, "lem")
        self.assertEqual(pool.busy()["free"], [f])
        self.assertFalse(pool.can_take(it("lead:build", 2), "lem"))
        pool.release(f, "lem")
        self.assertEqual(pool.busy(), {})


if __name__ == "__main__":
    unittest.main()
