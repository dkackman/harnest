"""The spend record and the day budget (harness/spend.py), the dry-round
rule's read side (harness/task_dry.py), and what the loop driver does with
both."""

import os
import tempfile
import time
import unittest

from harness import spend, task_dry
from harness.scheduler import Item
from tests.py.test_loop import mk


def session(d, text, name="last"):
    p = os.path.join(d, name)
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)
    return p


class SpendTest(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()

    def test_a_session_with_a_usage_line_is_recorded(self):
        last = session(
            self.d, "hello\nusage: turns=3 duration=4s cost=$1.25 ctx_peak=1k\n  claude-x: in=1 cost=$9.99\n"
        )
        self.assertEqual(1.25, spend.record(self.d, "tester:#1", last, day="2026-11-22", clock=lambda: 5))
        with open(os.path.join(self.d, spend.NAME), encoding="utf-8") as fh:
            self.assertEqual("2026-11-22\t5\t1.25\ttester:#1\n", fh.read())

    def test_a_session_that_died_records_nothing(self):
        self.assertIsNone(spend.record(self.d, "x", session(self.d, "hello\n")))
        self.assertIsNone(spend.record(self.d, "x", os.path.join(self.d, "missing")))
        self.assertFalse(os.path.exists(os.path.join(self.d, spend.NAME)))

    def test_today_sums_one_day_and_skips_what_it_cannot_read(self):
        with open(os.path.join(self.d, spend.NAME), "w", encoding="utf-8") as fh:
            fh.write(
                "2026-11-21\t1\t50.00\told\n2026-11-22\t2\t1.25\ta\n2026-11-22\t3\tx\tbad\nshort\n2026-11-22\t4\t2.00\tb\n"
            )
        self.assertEqual(3.25, spend.today(self.d, "2026-11-22"))
        self.assertEqual(0.0, spend.today(self.d, "2026-11-23"))
        self.assertEqual(0.0, spend.today(os.path.join(self.d, "none"), "2026-11-22"))

    def test_reached(self):
        with open(os.path.join(self.d, spend.NAME), "w", encoding="utf-8") as fh:
            fh.write("2026-11-22\t2\t3.00\ta\n")
        self.assertFalse(spend.reached(self.d, 0, "2026-11-22"))  # 0 is uncapped
        self.assertFalse(spend.reached(self.d, 3.01, "2026-11-22"))
        self.assertTrue(spend.reached(self.d, 3, "2026-11-22"))

    def test_budget(self):
        self.assertEqual(0.0, spend.budget({}))
        self.assertEqual(40.5, spend.budget({"DAY_BUDGET_USD": "40.5"}))
        self.assertEqual(0.5, spend.budget({"DAY_BUDGET_USD": ".5"}))
        # what run-loop.sh refuses is refused here too: an item's bash pass would exit on it
        for bad in ("x", "-1", "nan", "inf", "+5", "1e3", " 5", "1_0", ".", "1.2.3"):
            with self.assertRaises(ValueError):
                spend.budget({"DAY_BUDGET_USD": bad})


class TaskDryTest(unittest.TestCase):
    def factor(self, dry, rounds=2, most=4):
        d = tempfile.mkdtemp()
        if dry is not None:
            with open(os.path.join(d, task_dry.NAME), "w", encoding="utf-8") as fh:
                fh.write(f"{dry}\n")
        return task_dry.factor(d, rounds, most)

    def test_the_factor_doubles_from_the_threshold_up_to_the_cap(self):
        # the same table as task_dry_factor in run-loop.sh
        self.assertEqual([1, 1, 1, 2, 4, 4], [self.factor(n) for n in (None, 0, 1, 2, 3, 9)])
        self.assertEqual([1, 2, 4, 8], [self.factor(n, rounds=1, most=8) for n in (0, 1, 2, 3)])
        self.assertEqual(3, self.factor(9, most=3))

    def test_zero_rounds_turns_it_off_and_junk_reads_as_no_dry_round(self):
        self.assertEqual(1, self.factor(9, rounds=0))
        self.assertEqual(1, self.factor("junk"))


class LoopBrakesTest(unittest.TestCase):
    def spent(self, lp, day, dollars):
        with open(lp.logs / spend.NAME, "a", encoding="utf-8") as fh:
            fh.write(f"{day}\t1\t{dollars:.2f}\ttester:#1\n")

    def test_dry_rounds_stretch_the_standing_tasks_gap(self):
        lp = mk(TESTER_TASK_GAP_SECS=100)
        lp.task_last = time.time() - 150
        self.assertEqual(["tester:task"], [i.queue for i in lp.offer()])
        (lp.logs / task_dry.NAME).write_text("2\n")  # two dry rounds: twice the gap
        self.assertEqual([], lp.offer())
        lp.task_last = time.time() - 250
        self.assertEqual(["tester:task"], [i.queue for i in lp.offer()])

    def test_dry_rounds_off(self):
        lp = mk(TESTER_TASK_GAP_SECS=100, TESTER_TASK_DRY_ROUNDS=0)
        (lp.logs / task_dry.NAME).write_text("9\n")
        lp.task_last = time.time() - 150
        self.assertEqual(["tester:task"], [i.queue for i in lp.offer()])

    def test_nothing_is_dispatched_once_the_day_budget_is_spent(self):
        lp = mk(DAY_BUDGET_USD=5)
        day = [time.strptime("2026-11-22 10:00", "%Y-%m-%d %H:%M")]
        lp.localtime = lambda: day[0]
        launched = []
        lp.launch = lambda item, server: launched.append(item.queue) or True
        lp.items = [Item("lead:design", 4, "lem")]
        self.spent(lp, "2026-11-22", 4.99)
        self.assertEqual(1, lp.dispatch())
        self.spent(lp, "2026-11-22", 0.01)
        lp.sched.finished(Item("lead:design", 4, "lem"), "lem", True)
        self.assertEqual(0, lp.dispatch())
        self.assertEqual(0, lp.dispatch())
        with open(lp.srv["lem"].log.path, encoding="utf-8") as fh:
            said = fh.read()
        self.assertEqual(1, said.count("day budget reached ($5.00 of DAY_BUDGET_USD=$5 today)"))  # once a day
        self.assertEqual("2026-11-22", lp.budget_said)
        day[0] = time.strptime("2026-11-23 00:01", "%Y-%m-%d %H:%M")  # the day turns
        self.assertEqual(1, lp.dispatch())
        self.assertEqual("", lp.budget_said)

    def test_the_nightly_gives_the_gpu_back_when_the_budget_goes_while_it_waits(self):
        lp = mk(REGRESSION_NIGHTLY_AT=23, DAY_BUDGET_USD=5)
        srv, ran = lp.srv["lem"], []
        lp.start_regression = ran.append
        busy = Item("tester:verify", 1, "lem")
        lp.sched.pool.take(busy, "lem")
        lp.localtime = lambda: time.strptime("2026-11-18 23:10", "%Y-%m-%d %H:%M")
        lp.nightly_check()
        self.assertTrue(srv.nightly_due)  # due, waiting for the gpu session to end
        self.spent(lp, "2026-11-18", 5)  # which spends the rest of the day's budget
        lp.sched.pool.release(busy, "lem")
        lp.nightly_check()
        self.assertEqual([], ran)
        self.assertFalse(srv.nightly_due)
        self.assertNotIn("regression", srv.holds)
        self.assertFalse((lp.logs / ".nightly-regression").exists())  # not stamped: it comes due again
        lp.localtime = lambda: time.strptime("2026-11-19 23:10", "%Y-%m-%d %H:%M")
        lp.nightly_check()  # a new day, the gpu idle: due and started in one pass
        self.assertEqual([srv], ran)

    def test_one_session_per_issue(self):
        from harness.drivers import loop

        lp = mk(TESTER_TASK_GAP_SECS=99999)
        fix = Item("implementer:fix", 7, "lem")
        lp.running["s1"] = loop.Running(fix, "lem", "s1", None, 0.0, None, None)
        lp.items = [Item("tester:verify", 7, "lem"), Item("tester:verify", 8, "lem")]
        self.assertEqual([8], [i.issue for i in lp.offer()])  # 7 waits for its fix item to end
        lp.running.clear()
        self.assertEqual([7, 8], [i.issue for i in lp.offer()])
        # a curator item's number is the harness repo's: it never blocks a dw issue
        lp.running["s1"] = loop.Running(Item("curator", 7, "lem"), "lem", "s1", None, 0.0, None, None)
        self.assertEqual([7, 8], [i.issue for i in lp.offer()])

    def test_no_budget_is_uncapped(self):
        lp = mk()
        self.spent(lp, time.strftime("%Y-%m-%d"), 9999)
        self.assertFalse(lp.over_budget())

    def test_a_bad_budget_is_refused_at_startup(self):
        from harness.profile import ProfileError

        with self.assertRaises(ProfileError):
            mk(DAY_BUDGET_USD="lots")


if __name__ == "__main__":
    unittest.main()
