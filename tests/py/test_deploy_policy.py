"""harness/deploy_policy.py: when the scheduler deploys, and run_deploy."""

import pathlib
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

from harness import deploy
from harness import deploy_policy as dp


def sh(*args, cwd):
    subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)


class Policy(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = pathlib.Path(self.tmp.name)
        origin, self.src = root / "origin.git", str(root / "src")
        sh("git", "init", "-q", "--bare", "-b", "develop", str(origin), cwd=root)
        sh("git", "clone", "-q", str(origin), self.src, cwd=root)
        for k, v in (("user.email", "t@t"), ("user.name", "t")):
            sh("git", "config", k, v, cwd=self.src)
        self.n = 0
        self.commit("init", "README")

    def commit(self, msg, path="server.py"):
        self.n += 1
        p = pathlib.Path(self.src) / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(f"{self.n}\n")
        sh("git", "add", "-A", cwd=self.src)
        sh("git", "commit", "-q", "-m", msg, cwd=self.src)
        sh("git", "push", "-q", "origin", "develop", cwd=self.src)
        return dp.git("-C", self.src, "rev-parse", "HEAD").stdout.strip()

    def test_fix_commit_newest_match(self):
        self.commit("fix: #12 first")
        newest = self.commit("fix: #12 again")
        self.commit("fix: #120 other")
        self.assertEqual(dp.fix_commit(self.src, 12), newest)
        self.assertIsNone(dp.fix_commit(self.src, 99))

    def test_runnable_now_ancestor(self):
        self.commit("fix: #5 in")
        deployed = dp.git("-C", self.src, "rev-parse", "HEAD").stdout.strip()
        self.commit("fix: #6 later")
        self.assertTrue(dp.runnable_now(self.src, 5, deployed))
        self.assertFalse(dp.runnable_now(self.src, 6, deployed))
        self.assertFalse(dp.runnable_now(self.src, 7, deployed))

    def test_plugin_only_change_needs_no_deploy(self):
        deployed = self.commit("base")
        self.commit("skill #1", "plugins/dw/skills/x.md")
        develop = self.commit("skill #2", "plugins/dw/skills/y.md")
        self.assertFalse(dp.server_paths_changed(self.src, deployed, develop))
        develop = self.commit("code #3", "dw/engine.py")
        self.assertTrue(dp.server_paths_changed(self.src, deployed, develop))

    def test_wanted_only_when_nothing_runnable(self):
        g = dp.DeployGate(60)
        self.assertFalse(g.wanted([1, 2], {1: True, 2: False}, True))
        self.assertTrue(g.wanted([2], {2: False}, True))
        self.assertFalse(g.wanted([], {}, True))
        self.assertFalse(g.wanted([2], {2: False}, False))

    def test_failed_retry_then_park(self):
        now = [0.0]
        g = dp.DeployGate(60, clock=lambda: now[0])
        self.assertEqual(g.failed(), "retry")
        self.assertFalse(g.wanted([1], {1: False}, True))
        now[0] = 59
        self.assertFalse(g.wanted([1], {1: False}, True))
        now[0] = 61
        self.assertTrue(g.wanted([1], {1: False}, True))
        self.assertEqual(g.failed(), "park")

    def test_succeeded_clears_failures(self):
        g = dp.DeployGate(60, clock=lambda: 0.0)
        g.failed()
        g.succeeded()
        self.assertEqual(g.failed(), "retry")

    def test_deploy_takes_newest_develop_once(self):
        server = SimpleNamespace(host="lem", dir="~/dw", local=False, name="lem")
        self.commit("fix: #9 server", "dw/a.py")
        g = dp.DeployGate(60)
        self.assertTrue(g.wanted([9], {9: False}, True))
        self.commit("fix: #10 server", "dw/b.py")  # develop moves during the drain
        calls = []

        def fake_run(argv, **kw):
            calls.append(argv)
            if argv[:2] == ["bash", "-c"] and "deploy.sh" in argv[2]:
                return subprocess.CompletedProcess(argv, 0, stdout="a\nb\nc\nd\n", stderr="")
            return subprocess.CompletedProcess(argv, 0, stdout="develop @ abc1234\n", stderr="")

        said = []
        with mock.patch.object(deploy.subprocess, "run", fake_run):
            ok, head = deploy.run_deploy(server, said.append)
        g.succeeded()
        deploys = [c for c in calls if "deploy.sh" in " ".join(c)]
        self.assertEqual(len(deploys), 1)
        self.assertIn("deploy.sh develop", deploys[0][2])
        self.assertTrue(ok)
        self.assertEqual(head, "develop @ abc1234")
        self.assertEqual([s for s in said], ["[loop:deploy] b", "[loop:deploy] c", "[loop:deploy] d"])
        self.assertFalse(g.wanted([], {}, True))


if __name__ == "__main__":
    unittest.main()
