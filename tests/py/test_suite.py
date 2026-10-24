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
