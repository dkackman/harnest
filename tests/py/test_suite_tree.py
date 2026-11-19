"""harness/suite_tree.py: a session's own harnest worktree for suite edits,
landed onto main under one suite lock (R17 "Suite edits")."""

import os
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

from harness import suite_tree

SUITE = "### C-F001 — first\nexpected: one.\ncleanup: none.\n\n### C-F002 — second\nexpected: two.\ncleanup: none.\n"


def g(d, *a):
    return subprocess.run(["git", "-C", str(d), *a], capture_output=True, text=True, check=True).stdout.strip()


class Tree(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.h = str(Path(tmp.name) / "harnest")
        os.makedirs(self.h)
        g(self.h, "init", "-q", "-b", "main")
        g(self.h, "config", "user.name", "t")
        g(self.h, "config", "user.email", "t@t")
        Path(self.h, ".gitignore").write_text(".worktrees/\nlogs/\n")
        Path(self.h, "regression-suite-complete.md").write_text(SUITE)
        g(self.h, "add", "-A")
        g(self.h, "commit", "-qm", "init")
        self.said = []
        self.lock = threading.Lock()

    def land(self, tree, msg="tester: add case"):
        return suite_tree.land(
            self.h, tree, msg, "Claude Opus 5.5", "noreply@anthropic.com", self.said.append, self.lock
        )

    def main_suite(self):
        return g(self.h, "show", "main:regression-suite-complete.md")

    def edit(self, tree, old, new):
        p = Path(tree, "regression-suite-complete.md")
        p.write_text(p.read_text().replace(old, new, 1))

    def test_make_is_a_detached_checkout_of_main(self):
        tree = suite_tree.make(self.h, "s1")
        self.assertEqual(os.path.join(self.h, ".worktrees", "s1"), tree)
        self.assertEqual(g(self.h, "rev-parse", "main"), g(tree, "rev-parse", "HEAD"))
        self.assertEqual(
            "", subprocess.run(["git", "-C", tree, "symbolic-ref", "-q", "HEAD"], capture_output=True, text=True).stdout
        )

    def test_land_clean(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F003 — third\nexpected: three.\ncleanup: none.\n")
        self.assertEqual("landed", self.land(tree))
        self.assertIn("### C-F003 — third", self.main_suite())
        self.assertIn(
            "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>", g(self.h, "log", "-1", "--format=%B", "main")
        )
        # the primary checkout has main checked out: its working tree follows
        self.assertIn("C-F003", Path(self.h, "regression-suite-complete.md").read_text())
        self.assertEqual("", g(self.h, "status", "--porcelain"))

    def test_land_nothing_changed_is_clean(self):
        tree = suite_tree.make(self.h, "s1")
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("clean", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))

    def test_land_concurrent_appends(self):
        a, b = suite_tree.make(self.h, "a"), suite_tree.make(self.h, "b")
        self.edit(
            a,
            "expected: one.\ncleanup: none.\n",
            "expected: one.\ncleanup: none.\n\n### C-F010 — from a\ncleanup: none.\n",
        )
        with open(os.path.join(b, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F020 — from b\ncleanup: none.\n")
        self.assertEqual("landed", self.land(a))
        self.assertEqual("landed", self.land(b))
        text = self.main_suite()
        self.assertIn("C-F010 — from a", text)
        self.assertIn("C-F020 — from b", text)
        self.assertEqual("2", g(self.h, "rev-list", "--count", "main~2..main"))

    def test_land_conflict_keeps_branch(self):
        a, b = suite_tree.make(self.h, "a"), suite_tree.make(self.h, "b")
        self.edit(a, "### C-F002 — second\n", "### C-F002 — second\nnote: from a\n")
        self.edit(b, "### C-F002 — second\n", "### C-F002 — second\nnote: from b\n")
        self.assertEqual("landed", self.land(a))
        after_a = g(self.h, "rev-parse", "main")
        self.said.clear()
        self.assertEqual("conflict", self.land(b))
        self.assertEqual(after_a, g(self.h, "rev-parse", "main"))
        kept = g(self.h, "show", "suite-conflict/b:regression-suite-complete.md")
        self.assertIn("note: from b", kept)
        self.assertNotIn("from b", self.main_suite())
        self.assertTrue(any(s.startswith("[audit] WARNING") and "suite-conflict/b" in s for s in self.said), self.said)
        # the tree is not left mid-rebase
        self.assertFalse(os.path.exists(g(b, "rev-parse", "--git-path", "rebase-merge")))

    def test_land_dirty_primary_is_a_conflict(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F003 — third\ncleanup: none.\n")
        Path(self.h, "regression-suite-complete.md").write_text(SUITE + "hand edit\n")
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("conflict", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertIn("C-F003", g(self.h, "show", "suite-conflict/s1:regression-suite-complete.md"))
        self.assertIn("hand edit", Path(self.h, "regression-suite-complete.md").read_text())

    def test_land_retries_when_main_moves_under_it(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F003 — third\ncleanup: none.\n")
        real, calls = suite_tree._fast_forward, []

        def racing(harnest, new, old):
            calls.append(new)
            if len(calls) == 1:  # another writer lands on main first
                Path(self.h, "other.txt").write_text("x\n")
                g(self.h, "add", "other.txt")
                g(self.h, "commit", "-qm", "other writer")
                return False
            return real(harnest, new, old)

        with mock.patch.object(suite_tree, "_fast_forward", racing):
            self.assertEqual("landed", self.land(tree))
        self.assertEqual(2, len(calls))
        self.assertEqual("other writer", g(self.h, "log", "-1", "--format=%s", "main~1"))
        self.assertIn("C-F003", self.main_suite())

    def test_land_refuses_removal(self):
        tree = suite_tree.make(self.h, "s1")
        self.edit(tree, "expected: two.\n", "")
        self.assertEqual("landed", self.land(tree))
        self.assertTrue(
            any(
                s.startswith("[audit] WARNING") and "removed lines from regression-suite-complete.md" in s
                for s in self.said
            ),
            self.said,
        )

    def test_land_holds_the_lock(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F003 — third\ncleanup: none.\n")
        seen = []

        class Spy:
            def __enter__(s):
                seen.append("in")

            def __exit__(s, *a):
                seen.append("out")

        suite_tree.land(self.h, tree, "m", "N", "n@x", self.said.append, Spy())
        self.assertEqual(["in", "out"], seen)

    def test_remove(self):
        tree = suite_tree.make(self.h, "s1")
        Path(tree, "regression-suite-complete.md").write_text("dirty\n")
        suite_tree.remove(self.h, tree)
        self.assertFalse(os.path.exists(tree))
        self.assertNotIn(tree, g(self.h, "worktree", "list"))

    def test_make_replaces_a_stale_tree(self):
        tree = suite_tree.make(self.h, "s1")
        Path(tree, "regression-suite-complete.md").write_text("stale\n")
        with open(os.path.join(self.h, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F009 — newer\n")
        g(self.h, "commit", "-qam", "newer")
        tree = suite_tree.make(self.h, "s1")
        self.assertEqual(g(self.h, "rev-parse", "main"), g(tree, "rev-parse", "HEAD"))
        self.assertIn("C-F009", Path(tree, "regression-suite-complete.md").read_text())


if __name__ == "__main__":
    unittest.main()
