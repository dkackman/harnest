"""harness/delegate_replay.py: R19's replay cases (no network)."""

import unittest

from harness import delegate_replay as dr


def c(body, t, who="dkackman"):
    return {"author": {"login": who}, "createdAt": t, "body": body}


ISSUE = {
    "number": 7,
    "title": "t7",
    "body": "the plan",
    "comments": [
        c("**Decision for Don:** build it?", "2026-11-01T10:00:00Z"),
        c("**Ruling (Don, 2026-11-01): approved at the defaults.**", "2026-11-01T11:00:00Z"),
        c("<!-- harnest:decomposed v1 --> stages", "2026-11-01T12:00:00Z"),
        c("**Ruling on plan v2 (delegate for Don, 2026-11-02): approved.**", "2026-11-02T10:00:00Z"),
        c("Don's ruling: **hand back**.", "2026-11-03T10:00:00Z"),
    ],
}

EVENTS = [
    {"__typename": "LabeledEvent", "createdAt": "2026-11-01T09:00:00Z", "label": {"name": "owner:lead"}},
    {"__typename": "UnlabeledEvent", "createdAt": "2026-11-01T10:00:00Z", "label": {"name": "owner:lead"}},
    {"__typename": "LabeledEvent", "createdAt": "2026-11-01T10:00:00Z", "label": {"name": "owner:don"}},
    {"__typename": "LabeledEvent", "createdAt": "2026-11-01T10:00:01Z", "label": {"name": "status:plan-review"}},
    {"__typename": "UnlabeledEvent", "createdAt": "2026-11-01T11:00:00Z", "label": {"name": "owner:don"}},
    {"__typename": "LabeledEvent", "createdAt": "2026-11-01T11:00:00Z", "label": {"name": "status:plan-approved"}},
]


class RulingTest(unittest.TestCase):
    def test_finds_dons_rulings_not_the_delegates(self):
        self.assertEqual(dr.rulings(ISSUE), [1, 4])

    def test_ruling_shapes(self):
        for body in (
            "**Don's ruling (2026-11-17): approve.**",
            "Ruling: option 2.",
            "Approved, all four items",
            "**Don approved (2026-11-16, in session):**",
            "**Ruling carried out:** x",
        ):
            self.assertTrue(dr.is_ruling(body), body)
        for body in ("<!-- harnest:specced v1 -->", "Close-out of #1577", "**Decision for Don:** x"):
            self.assertFalse(dr.is_ruling(body), body)

    def test_overnight_delegation_is_not_dons(self):
        self.assertTrue(dr.is_delegated("Ruling (for Don, under his overnight delegation): the default."))
        self.assertTrue(
            dr.is_delegated(
                "**Ruling: retarget to lem (the default).** x\n\n— ruled by the lead session under Don's delegation"
            )
        )
        self.assertFalse(dr.is_delegated("**Don's ruling: the default.** This ruling approves it."))


class CutTest(unittest.TestCase):
    def test_the_case_holds_nothing_from_the_ruling_on(self):
        case = dr.cut(ISSUE, 1, EVENTS, "dkackman/diffusers-workflow", "abc123")
        self.assertEqual([x["body"][:10] for x in case["comments"]], ["**Decision"])
        self.assertEqual(case["asked_before"], "2026-11-01T11:00:00Z")
        self.assertEqual(case["id"], "diffusers-workflow-7-1")
        self.assertNotIn("approved at the defaults", repr(case))

    def test_labels_are_as_of_the_ask(self):
        case = dr.cut(ISSUE, 1, EVENTS, "dkackman/diffusers-workflow", None)
        self.assertEqual(case["labels"], ["owner:don", "status:plan-review"])

    def test_a_plan_that_already_holds_the_ruling_is_leaked(self):
        self.assertFalse(dr.cut(ISSUE, 1, EVENTS, "dkackman/diffusers-workflow", None)["leaked"])
        folded = dict(
            ISSUE,
            comments=[c("**Q1** [scope] x. **Ruled: otherwise.**", "2026-11-01T10:00:00Z")] + ISSUE["comments"][1:],
        )
        self.assertTrue(dr.cut(folded, 1, EVENTS, "dkackman/diffusers-workflow", None)["leaked"])

    def test_answer_is_the_ruling(self):
        self.assertEqual(dr.answer(ISSUE, 4)["first_line"], "Don's ruling: **hand back**.")


class RunTest(unittest.TestCase):
    def test_render_holds_the_ask_not_the_answer(self):
        text = dr.render_case(dr.cut(ISSUE, 1, EVENTS, "dkackman/diffusers-workflow", None))
        self.assertIn("**Decision for Don:** build it?", text)
        self.assertIn("owner:don", text)
        self.assertNotIn("approved at the defaults", text)

    def test_parse_answer_takes_the_last_object(self):
        reply = 'I read {"a": 1}.\n\n{"outcome": "pass", "verdict": "default", "kinds": ["taste"]}'
        self.assertEqual(dr.parse_answer(reply)["outcome"], "pass")
        self.assertIsNone(dr.parse_answer("no json here"))

    def test_budget_stops_before_the_session_that_would_cross_it(self):
        self.assertFalse(dr.would_exceed(0, [], 100))
        self.assertTrue(dr.would_exceed(97.0, [], 100))
        self.assertFalse(dr.would_exceed(97.0, [1.0, 2.0, 2.5], 100))
        self.assertTrue(dr.would_exceed(98.5, [1.0, 2.0, 2.5], 100))


if __name__ == "__main__":
    unittest.main()
