"""harness/board.py: the loop driver's view of lib/classify.jq's rows (R17)."""

import unittest

from harness import board
from harness.board import Row
from harness.scheduler import Item


def r(n, q, holder=None, parent=None):
    return Row(n, q, parent, "why", holder)


class ParseTest(unittest.TestCase):
    def test_parse(self):
        rows = board.parse("1\timplementer:fix\t-\tready\t-\n2\ttester:verify\t7\thanded off\tmini-ai\nbad line\n")
        self.assertEqual(
            rows, [Row(1, "implementer:fix", None, "ready", None), Row(2, "tester:verify", 7, "handed off", "mini-ai")]
        )

    def test_parse_four_columns(self):
        self.assertEqual(board.parse("3\tdon\t-\tparked"), [Row(3, "don", None, "parked", None)])

    def test_status_rows(self):
        text = "  #12   status:fixed-pending-verify owner:tester       [lem] a title here\n  #3    open                     unowned            \n"
        self.assertEqual(
            board.status_rows(text),
            [[12, "status:fixed-pending-verify", "owner:tester", "[lem] a title here"], [3, "open", "unowned", ""]],
        )

    def test_numbers(self):
        self.assertEqual(board.numbers("4\n 9\nx\n"), [4, 9])
        self.assertEqual(board.numbers(None), [])


class ItemsTest(unittest.TestCase):
    def test_one_server(self):
        got = board.items({"lem": [r(1, "implementer:fix"), r(2, "wait"), r(3, "don"), r(4, "tester:verify")]})
        self.assertEqual(got, [Item("implementer:fix", 1, "lem"), Item("tester:verify", 4, "lem")])

    def test_claimed_goes_to_its_server(self):
        rows = {"lem": [r(5, "wait", "mini-ai")], "mini-ai": [r(5, "tester:verify", "mini-ai")]}
        self.assertEqual(board.items(rows), [Item("tester:verify", 5, "mini-ai")])

    def test_unclaimed_fix_offered_by_both_gets_candidates(self):
        rows = {"lem": [r(6, "implementer:fix")], "mini-ai": [r(6, "implementer:fix")]}
        self.assertEqual(board.items(rows), [Item("implementer:fix", 6, None, ("lem", "mini-ai"))])

    def test_shared_unclaimed_goes_to_the_first_server(self):
        rows = {
            "lem": [r(8, "reviewer:docs"), r(9, "tester:spec")],
            "mini-ai": [r(8, "reviewer:docs"), r(9, "tester:spec")],
        }
        self.assertEqual(board.items(rows), [Item("reviewer:docs", 8, "lem"), Item("tester:spec", 9, "lem")])

    def test_unclaimed_design_and_decompose_get_candidates(self):
        rows = {
            "lem": [r(7, "lead:design"), r(6, "lead:decompose")],
            "mini-ai": [r(7, "lead:design"), r(6, "lead:decompose")],
        }
        self.assertEqual(
            board.items(rows),
            [Item("lead:design", 7, None, ("lem", "mini-ai")), Item("lead:decompose", 6, None, ("lem", "mini-ai"))],
        )

    def test_shared_moves_when_the_first_server_is_gone(self):
        rows = {"mini-ai": [r(7, "lead:design")]}
        self.assertEqual(board.items(rows), [Item("lead:design", 7, "mini-ai")])

    def test_stranded(self):
        rows = {
            "lem": [r(9, "stranded"), r(10, "stranded", "mini-ai"), r(11, "stranded", "nowhere")],
            "mini-ai": [r(9, "stranded"), r(10, "stranded", "mini-ai"), r(11, "stranded", "nowhere")],
        }
        self.assertEqual(board.items(rows), [Item("implementer:fix", 9, "lem"), Item("implementer:fix", 10, "mini-ai")])

    def test_not_board_queues(self):
        rows = {"lem": [r(1, "external"), r(2, "curator"), r(3, "tester:task"), r(4, "lead:build")]}
        self.assertEqual(board.items(rows), [Item("lead:build", 4, "lem")])

    def test_unreadable_target_offers_nothing(self):
        self.assertEqual(
            board.items({"lem": None, "mini-ai": [r(1, "lead:closeout")]}), [Item("lead:closeout", 1, "mini-ai")]
        )
