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
        self.tmp = os.path.realpath(tmp.name)
        self.h = str(Path(self.tmp) / "harnest")
        os.makedirs(self.h)
        g(self.h, "init", "-q", "-b", "main")
        g(self.h, "config", "user.name", "t")
        g(self.h, "config", "user.email", "t@t")
        Path(self.h, ".gitignore").write_text("logs/\n")
        Path(self.h, "regression-suite-complete.md").write_text(SUITE)
        g(self.h, "add", "-A")
        g(self.h, "commit", "-qm", "init")
        self.said = []
        self.lock = threading.Lock()

    def land(self, tree, msg="tester: add case", **kw):
        return suite_tree.land(
            self.h, tree, msg, "Claude Opus 5.5", "noreply@anthropic.com", self.said.append, self.lock, **kw
        )

    def append(self, tree, text="\n### C-F003 — third\ncleanup: none.\n"):
        with open(os.path.join(tree.path, "regression-suite-complete.md"), "a") as f:
            f.write(text)

    def warned(self, *needles):
        return any(s.startswith("[audit] WARNING") and all(n in s for n in needles) for s in self.said)

    def main_suite(self):
        return g(self.h, "show", "main:regression-suite-complete.md")

    def edit(self, tree, old, new):
        p = Path(tree.path, "regression-suite-complete.md")
        p.write_text(p.read_text().replace(old, new, 1))

    def test_make_is_a_detached_checkout_of_main_outside_the_root(self):
        tree = suite_tree.make(self.h, "s1")
        self.assertEqual(os.path.join(self.tmp, ".harnest-worktrees", "harnest", "s1"), tree.path)
        self.assertEqual(g(self.h, "rev-parse", "main"), tree.base)
        self.assertEqual(tree.base, g(tree.path, "rev-parse", "HEAD"))
        self.assertEqual(
            "",
            subprocess.run(
                ["git", "-C", tree.path, "symbolic-ref", "-q", "HEAD"], capture_output=True, text=True
            ).stdout,
        )

    def test_make_base_dir(self):
        d = os.path.join(self.tmp, "elsewhere")
        tree = suite_tree.make(self.h, "s1", base_dir=d)
        self.assertEqual(os.path.join(d, "s1"), tree.path)

    def test_land_clean(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree.path, "regression-suite-complete.md"), "a") as f:
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
        with open(os.path.join(b.path, "regression-suite-complete.md"), "a") as f:
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
        self.assertFalse(os.path.exists(g(b.path, "rev-parse", "--git-path", "rebase-merge")))

    def test_land_dirty_primary_is_a_conflict(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree.path, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F003 — third\ncleanup: none.\n")
        Path(self.h, "regression-suite-complete.md").write_text(SUITE + "hand edit\n")
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("conflict", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertIn("C-F003", g(self.h, "show", "suite-conflict/s1:regression-suite-complete.md"))
        self.assertIn("hand edit", Path(self.h, "regression-suite-complete.md").read_text())

    def test_land_retries_when_main_moves_under_it(self):
        tree = suite_tree.make(self.h, "s1")
        with open(os.path.join(tree.path, "regression-suite-complete.md"), "a") as f:
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
        with open(os.path.join(tree.path, "regression-suite-complete.md"), "a") as f:
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
        Path(tree.path, "regression-suite-complete.md").write_text("dirty\n")
        suite_tree.remove(self.h, tree.path)
        self.assertFalse(os.path.exists(tree.path))
        self.assertNotIn(tree.path, g(self.h, "worktree", "list"))

    def test_make_strands_a_stale_tree(self):
        tree = suite_tree.make(self.h, "s1")
        Path(tree.path, "regression-suite-complete.md").write_text("stale\n")
        with open(os.path.join(self.h, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F009 — newer\n")
        g(self.h, "commit", "-qam", "newer")
        tree = suite_tree.make(self.h, "s1", say=self.said.append)
        self.assertEqual(g(self.h, "rev-parse", "main"), g(tree.path, "rev-parse", "HEAD"))
        self.assertIn("C-F009", Path(tree.path, "regression-suite-complete.md").read_text())
        # the stale tree's edit is kept, not dropped
        self.assertEqual("stale", g(self.h, "show", "suite-stranded/s1:regression-suite-complete.md"))
        self.assertTrue(self.warned("suite-stranded/s1"), self.said)

    # --- fix round 1: never land session commits, strand rather than drop

    def test_session_commit_is_stranded_not_landed(self):
        tree = suite_tree.make(self.h, "s1")
        Path(tree.path, "evil.sh").write_text("rm -rf /\n")
        g(tree.path, "add", "evil.sh")
        g(tree.path, "commit", "-qm", "sneak")
        self.append(tree)
        head = g(tree.path, "rev-parse", "HEAD")
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertEqual(head, g(self.h, "rev-parse", "suite-stranded/s1~1"))
        self.assertIn("C-F003", g(self.h, "show", "suite-stranded/s1:regression-suite-complete.md"))
        self.assertTrue(self.warned("suite-stranded/s1"), self.said)

    def test_session_commit_on_a_plain_path_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        self.append(tree)
        g(tree.path, "commit", "-qam", "session committed its own case")
        head = g(tree.path, "rev-parse", "HEAD")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(head, g(self.h, "rev-parse", "suite-stranded/s1"))
        self.assertNotIn("C-F003", self.main_suite())

    def test_leftovers_outside_paths_are_stranded_suite_change_lands(self):
        tree = suite_tree.make(self.h, "s1")
        self.append(tree)
        Path(tree.path, "scripts").mkdir()
        Path(tree.path, "scripts", "x.sh").write_text("echo hi\n")
        Path(tree.path, ".gitignore").write_text("logs/\nextra/\n")  # tracked file changed too
        self.assertEqual("stranded", self.land(tree))
        self.assertIn("C-F003", self.main_suite())  # the suite paths landed
        self.assertNotIn("scripts", g(self.h, "ls-tree", "--name-only", "main"))
        self.assertEqual("logs/", g(self.h, "show", "main:.gitignore"))
        self.assertEqual("echo hi", g(self.h, "show", "suite-stranded/s1:scripts/x.sh"))
        self.assertIn("extra/", g(self.h, "show", "suite-stranded/s1:.gitignore"))
        self.assertTrue(self.warned("suite-stranded/s1"), self.said)

    def test_staged_file_outside_paths_is_not_in_the_landing_commit(self):
        tree = suite_tree.make(self.h, "s1")
        self.append(tree)
        Path(tree.path, "other.txt").write_text("x\n")
        g(tree.path, "add", "other.txt")
        self.assertEqual("stranded", self.land(tree))
        self.assertNotIn("other.txt", g(self.h, "ls-tree", "--name-only", "main"))
        self.assertEqual("x", g(self.h, "show", "suite-stranded/s1:other.txt"))

    def test_only_leftovers_is_stranded_and_main_untouched(self):
        tree = suite_tree.make(self.h, "s1")
        Path(tree.path, "other.txt").write_text("x\n")
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertEqual("x", g(self.h, "show", "suite-stranded/s1:other.txt"))

    def test_landing_commit_touching_more_than_paths_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        self.append(tree)
        real = suite_tree.suite.commit_changes

        def sloppy(repo, logs, paths, msg, name, email, say, **kw):
            Path(repo, "extra.txt").write_text("x\n")
            g(repo, "add", "-A")
            g(repo, "commit", "-qm", msg)

        before = g(self.h, "rev-parse", "main")
        with mock.patch.object(suite_tree.suite, "commit_changes", sloppy):
            self.assertEqual("stranded", self.land(tree))
        self.assertIs(real, suite_tree.suite.commit_changes)
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertEqual("x", g(self.h, "show", "suite-stranded/s1:extra.txt"))

    def test_stranded_branches_never_overwrite(self):
        g(self.h, "branch", "suite-stranded/s1", "main")
        first = g(self.h, "rev-parse", "suite-stranded/s1")
        tree = suite_tree.make(self.h, "s1")
        Path(tree.path, "other.txt").write_text("x\n")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(first, g(self.h, "rev-parse", "suite-stranded/s1"))
        self.assertEqual("x", g(self.h, "show", "suite-stranded/s1-2:other.txt"))

    def test_conflict_branches_never_overwrite(self):
        g(self.h, "branch", "suite-conflict/b", "main")
        a, b = suite_tree.make(self.h, "a"), suite_tree.make(self.h, "b")
        self.edit(a, "### C-F002 — second\n", "### C-F002 — second\nnote: from a\n")
        self.edit(b, "### C-F002 — second\n", "### C-F002 — second\nnote: from b\n")
        self.assertEqual("landed", self.land(a))
        self.assertEqual("conflict", self.land(b))
        self.assertEqual(g(self.h, "rev-parse", "main~1"), g(self.h, "rev-parse", "suite-conflict/b"))
        self.assertIn("note: from b", g(self.h, "show", "suite-conflict/b-2:regression-suite-complete.md"))

    def test_curator_removal_is_logged_not_warned(self):
        for kw, msg in (({"kind": "curator:review"}, "suite: apply #5"), ({}, "curator: apply #5")):
            self.said.clear()
            tree = suite_tree.make(self.h, "c" + str(len(msg)) + str(len(kw)))
            self.edit(tree, "expected: two.\n", "")
            self.assertEqual("landed", self.land(tree, msg=msg, **kw))
            self.assertFalse(self.warned(), self.said)
            self.assertTrue(
                any(
                    s.startswith("[audit] curator removed lines from regression-suite-complete.md(-1) in ")
                    and s.endswith("(an approved suite change)")
                    for s in self.said
                ),
                self.said,
            )
            g(self.h, "reset", "-q", "--hard", "main~1")

    def test_tester_removal_still_warns_with_a_kind(self):
        tree = suite_tree.make(self.h, "s1")
        self.edit(tree, "expected: two.\n", "")
        self.assertEqual("landed", self.land(tree, kind="verify"))
        self.assertTrue(self.warned("removed lines from regression-suite-complete.md"), self.said)

    # --- Task 5 step 0: no symlink or gitlink lands; the base is refs/heads/main, never a
    # same-named tag

    def test_symlink_suite_entry_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        os.symlink("/etc/passwd", os.path.join(tree.path, "regression-suite-evil.md"))
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertTrue(self.warned("suite-stranded/s1", "symlink"), self.said)

    def test_suite_file_turned_into_a_symlink_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        p = os.path.join(tree.path, "regression-suite-complete.md")
        os.unlink(p)
        os.symlink("/etc/passwd", p)
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))

    def test_symlink_under_a_perf_dir_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        os.makedirs(os.path.join(tree.path, "regression-perf"))
        os.symlink("/etc/passwd", os.path.join(tree.path, "regression-perf", "S-P001.jsonl"))
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))

    def test_gitlink_entry_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        self.append(tree)
        real = suite_tree.suite.commit_changes

        def gitlink(repo, logs, paths, msg, name, email, say, **kw):
            real(repo, logs, paths, msg, name, email, say, **kw)
            head = g(repo, "rev-parse", "HEAD")
            g(repo, "update-index", "--add", "--cacheinfo", f"160000,{head},regression-perf/sub")
            g(repo, "commit", "-q", "--amend", "--no-edit")

        before = g(self.h, "rev-parse", "main")
        with mock.patch.object(suite_tree.suite, "commit_changes", gitlink):
            self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertTrue(self.warned("suite-stranded/s1", "gitlink"), self.said)

    def test_symlinked_allowed_dir_is_stranded(self):
        tree = suite_tree.make(self.h, "s1")
        out = os.path.join(self.tmp, "outside")
        os.makedirs(out)
        os.symlink(out, os.path.join(tree.path, "regression-perf"))
        self.append(tree)
        before = g(self.h, "rev-parse", "main")
        self.assertEqual("stranded", self.land(tree))
        self.assertEqual(before, g(self.h, "rev-parse", "main"))
        self.assertTrue(self.warned("suite-stranded/s1", "regression-perf", "symlink"), self.said)

    def test_a_tag_named_main_is_not_the_base(self):
        old = g(self.h, "rev-parse", "main")
        with open(os.path.join(self.h, "regression-suite-complete.md"), "a") as f:
            f.write("\n### C-F009 — newer\ncleanup: none.\n")
        g(self.h, "commit", "-qam", "newer")
        g(self.h, "update-ref", "refs/tags/main", old)
        tree = suite_tree.make(self.h, "s1")
        self.assertEqual(g(self.h, "rev-parse", "refs/heads/main"), tree.base)
        self.assertRegex(tree.base, r"^[0-9a-f]{40}$")
        self.append(tree)
        self.assertEqual("landed", self.land(tree))
        text = g(self.h, "show", "refs/heads/main:regression-suite-complete.md")
        self.assertIn("C-F009", text)
        self.assertIn("C-F003", text)
        self.assertEqual(old, g(self.h, "rev-parse", "refs/tags/main"))

    def test_land_needs_the_base(self):
        tree = suite_tree.make(self.h, "s1")
        with self.assertRaises(ValueError):
            self.land(tree.path)
        self.assertEqual("clean", self.land(tree.path, base=tree.base))


if __name__ == "__main__":
    unittest.main()
