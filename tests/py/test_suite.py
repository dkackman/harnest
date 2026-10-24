"""harness/suite.py: the text a chunk session is handed (case_text)."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from harness import REPO, suite

SUITE_TEXT = """\
# A suite

Opening paragraphs a chunk is not handed.

## Adding a case

How to add one.

## Fixtures

- `fixture-a`: a durable workflow.

## Functional

### S-F001 — first

steps, with an example:

```
### S-F999 — not a case, an example inside a fence
```

cleanup: none

### S-F002 — second

steps two

### S-F003 — third

steps three
"""


class CaseText(unittest.TestCase):
    def setUp(self):
        d = tempfile.mkdtemp()
        self.suite = Path(d, "regression-suite-t.md")
        self.suite.write_text(SUITE_TEXT, encoding="utf-8")

    def test_case_text_skips_a_fenced_heading(self):
        text = suite.case_text(self.suite, ["S-F001"])
        self.assertIn("### S-F001", text)
        self.assertIn("cleanup: none", text)  # the block runs past its fenced example
        self.assertNotIn("### S-F002", text)

    def test_case_text_carries_fixtures_only_from_the_header(self):
        text = suite.case_text(self.suite, ["S-F001"])
        self.assertIn("## Fixtures", text)
        self.assertIn("fixture-a", text)
        self.assertNotIn("## Adding a case", text)
        self.assertNotIn("Opening paragraphs", text)
        self.assertNotIn("## Functional", text)

    def test_case_text_keeps_the_order_given(self):
        text = suite.case_text(self.suite, ["S-F003", "S-F001"])
        self.assertLess(text.index("### S-F003"), text.index("### S-F001"))
        self.assertNotIn("### S-F002", text)
        self.assertFalse(text.endswith("\n"))

    def test_case_ids_skip_a_fenced_heading(self):
        self.assertEqual(["S-F001", "S-F002", "S-F003"], suite.case_ids(self.suite))

    def test_case_ids_script_is_the_same_list(self):
        out = subprocess.run(
            ["python3", "-m", "harness.suite", "case-ids", str(self.suite)],
            capture_output=True,
            text=True,
            check=True,
            cwd=REPO,
        ).stdout
        self.assertEqual("S-F001\nS-F002\nS-F003\n", out)

    def test_case_text_of_a_fenced_heading_is_the_fixtures_alone(self):
        self.assertEqual(suite.fixtures_section(self.suite), suite.case_text(self.suite, ["S-F999"]))

    def test_case_text_carries_the_security_opening(self):
        sec = Path(self.suite.parent, "regression-suite-security.md")
        sec.write_text(SUITE_TEXT.replace("Opening paragraphs", "Refused too late is a failure. Opening"))
        text = suite.case_text(sec, ["S-F001"])
        self.assertTrue(text.startswith("# A suite\n\nRefused too late is a failure."))
        self.assertLess(text.index("too late"), text.index("## Fixtures"))
        self.assertNotIn("## Adding a case", text)
        self.assertNotIn("Opening paragraphs", suite.case_text(self.suite, ["S-F001"]))  # smoke-shaped: no opening

    def test_case_text_hands_every_security_slice_its_gate(self):
        sec = Path(self.suite.parent, "regression-suite-security.md")
        sec.write_text(SUITE_TEXT.replace("S-F00", "SE-F00"))
        text = suite.case_text(sec, ["SE-F003"])
        self.assertLess(text.index("### SE-F001"), text.index("### SE-F003"))
        self.assertEqual(1, suite.case_text(sec, ["SE-F002", "SE-F001"]).count("### SE-F001 "))
        self.assertNotIn("### SE-F001", suite.case_text(sec, []))  # the sweep: no case

    def test_case_text_script_is_the_same_bytes(self):
        out = subprocess.run(
            [str(REPO / "scripts" / "case-text.sh"), str(self.suite), "S-F002", "S-F001"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertEqual(suite.case_text(self.suite, ["S-F002", "S-F001"]) + "\n", out)


class Commit(unittest.TestCase):
    def test_a_directory_not_written_yet_does_not_stop_the_commit(self):
        d = tempfile.mkdtemp()
        g = lambda *a: subprocess.run(["git", "-C", d, *a], capture_output=True, text=True, check=True)
        g("init", "-q")
        g("config", "user.name", "t")
        g("config", "user.email", "t@t")
        Path(d, "regression-suite-a.md").write_text("x\n")
        g("add", "-A")
        g("commit", "-qm", "init")
        Path(d, "regression-suite-a.md").write_text("x\ny\n")
        said = []
        suite.commit_changes(
            d,
            d,
            ["regression-suite-*.md", "regression-perf", "regression-results"],
            "suite: y",
            "N",
            "n@x",
            said.append,
        )
        self.assertEqual("suite: y", g("log", "-1", "--format=%s").stdout.strip())


if __name__ == "__main__":
    unittest.main()
