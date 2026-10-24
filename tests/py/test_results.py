"""harness/results.py: the per-case outcome ledger in regression-results/."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from harness import REPO, results

KEYS = ["ts", "level", "case", "outcome", "issue", "secs", "session", "head", "model", "server"]

SESSION = """\
model: claude-fake
REGRESSION-CASE: S-F001
- REGRESSION-RESULT: S-F001 pass
REGRESSION-RESULT: S-F002 fail #812
REGRESSION-SKIP: S-F003 fixture x missing
usage: turns=3 duration=4s cost=$0.12 ctx_peak=2.5k in=20 cache_read=4k cache_write=500 out=14
"""


def lines(d, case):
    return [json.loads(l) for l in Path(d, f"{case}.jsonl").read_text().splitlines()]


class Record(unittest.TestCase):
    def test_record_appends_in_key_order(self):
        d = tempfile.mkdtemp()
        results.record(
            d, "lem", "smoke", "S-F001", "pass", None, 12.34, "regression:smoke.1 of 2", "develop @ abc", "m"
        )
        results.record(d, "lem", "smoke", "S-F001", "fail", 812, None, "regression:smoke.1 of 2", "develop @ abc", "m")
        got = lines(d, "S-F001")
        self.assertEqual(2, len(got))
        self.assertEqual(KEYS, list(got[0]))
        self.assertEqual(
            ["smoke", "S-F001", "pass", None, 12.3, "regression:smoke.1 of 2", "develop @ abc", "m", "lem"],
            [got[0][k] for k in KEYS[1:]],
        )
        self.assertRegex(got[0]["ts"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertEqual(("fail", 812), (got[1]["outcome"], got[1]["issue"]))

    def test_session_records_each_case_once(self):
        d = tempfile.mkdtemp()
        said = results.record_session(
            d, "lem", "smoke", "regression:smoke.1", "h", "m", SESSION, cases=["S-F001", "S-F002", "S-F003", "S-F004"]
        )
        self.assertEqual([("S-F001", "pass"), ("S-F002", "fail"), ("S-F003", "skip"), ("S-F004", "unreported")], said)
        self.assertEqual(812, lines(d, "S-F002")[0]["issue"])
        self.assertEqual(4, len(list(Path(d).glob("*.jsonl"))))

    def test_a_died_session_did_not_run_what_it_never_answered(self):
        d = tempfile.mkdtemp()
        said = results.record_session(d, "lem", "smoke", "l", "h", "m", "model: x\n", cases=["S-F001"])
        self.assertEqual([("S-F001", "not run")], said)

    def test_secs_only_for_cases_that_were_timed(self):
        d = tempfile.mkdtemp()
        results.record_session(d, "lem", "smoke", "l", "h", "m", SESSION, cases=["S-F001"], secs={"S-F001": 61.04})
        self.assertEqual(61.0, lines(d, "S-F001")[0]["secs"])
        self.assertIsNone(lines(d, "S-F002")[0]["secs"])

    def test_script_reads_the_session_from_stdin(self):
        d = tempfile.mkdtemp()
        subprocess.run(
            [str(REPO / "scripts" / "record-results.sh"), d, "mini-ai", "smoke", "l", "h", "m", "S-F004"],
            input=SESSION,
            text=True,
            check=True,
        )
        self.assertEqual(["S-F001", "S-F002", "S-F003", "S-F004"], sorted(p.stem for p in Path(d).glob("*.jsonl")))
        self.assertEqual("mini-ai", lines(d, "S-F004")[0]["server"])


if __name__ == "__main__":
    unittest.main()
