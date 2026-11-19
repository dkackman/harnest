"""harness/deploy_policy.py: when the scheduler deploys, and run_deploy."""

import os
import pathlib
import subprocess
import tempfile
import time
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

    def test_head_sha_parses_deployed_head(self):
        self.assertEqual(dp.head_sha("develop @ abc1234"), "abc1234")
        self.assertEqual(dp.head_sha("noise\ndevelop @ abc1234\n"), "abc1234")
        self.assertEqual(dp.head_sha("abc1234"), "abc1234")
        self.assertIsNone(dp.head_sha("unknown"))
        self.assertIsNone(dp.head_sha("develop @ unknown"))
        self.assertIsNone(dp.head_sha(""))

    def test_policy_accepts_deployed_head_string(self):
        self.commit("fix: #5 in")
        sha = dp.git("-C", self.src, "rev-parse", "--short", "HEAD").stdout.strip()
        head = f"develop @ {sha}"
        self.commit("fix: #6 later", "dw/a.py")
        develop = dp.git("-C", self.src, "rev-parse", "HEAD").stdout.strip()
        self.assertTrue(dp.runnable_now(self.src, 5, head))
        self.assertFalse(dp.runnable_now(self.src, 6, head))
        self.assertFalse(dp.runnable_now(self.src, 5, "unknown"))
        self.assertTrue(dp.server_paths_changed(self.src, head, develop))
        self.assertTrue(dp.server_paths_changed(self.src, "unknown", develop))

    def test_parked_gate_wants_nothing_until_reset(self):
        g = dp.DeployGate(60, clock=lambda: 1000.0)
        g.failed()
        self.assertEqual(g.failed(), "park")
        self.assertFalse(g.wanted([1], {1: False}, True))
        g.reset()
        self.assertTrue(g.wanted([1], {1: False}, True))
        g.failed()
        g.failed()
        g.succeeded()
        self.assertTrue(g.wanted([1], {1: False}, True))

    def test_gate_state(self):
        g = dp.DeployGate(60, clock=lambda: 0.0)
        self.assertEqual(g.state, "idle")
        for s in ("waiting", "draining", "deploying"):
            g.set_state(s)
            self.assertEqual(g.state, s)
        with self.assertRaises(ValueError):
            g.set_state("bogus")
        g.failed()
        self.assertEqual(g.state, "failed")
        g.succeeded()
        self.assertEqual(g.state, "idle")
        g.set_state("draining")
        g.failed()
        g.reset()
        self.assertEqual(g.state, "idle")

    def test_fix_commit_prefers_non_merge(self):
        direct = self.commit("fix: #12 real")
        sh("git", "checkout", "-q", "-b", "side", cwd=self.src)
        self.commit("side work", "side.txt")
        sh("git", "checkout", "-q", "develop", cwd=self.src)
        sh("git", "merge", "-q", "--no-ff", "side", "-m", "Merge pull request (#12) from x", cwd=self.src)
        sh("git", "push", "-q", "origin", "develop", cwd=self.src)
        self.assertEqual(dp.fix_commit(self.src, 12), direct)

    def test_fix_commit_falls_back_to_merge(self):
        sh("git", "checkout", "-q", "-b", "side", cwd=self.src)
        self.commit("side work", "side.txt")
        sh("git", "checkout", "-q", "develop", cwd=self.src)
        self.commit("other", "o.txt")
        sh("git", "merge", "-q", "--no-ff", "side", "-m", "Merge (#13)", cwd=self.src)
        sh("git", "push", "-q", "origin", "develop", cwd=self.src)
        merge = dp.git("-C", self.src, "rev-parse", "HEAD").stdout.strip()
        self.assertEqual(dp.fix_commit(self.src, 13), merge)

    def test_deploy_takes_newest_develop_once(self):
        server = SimpleNamespace(host="lem", dir="~/dw", local=False, name="lem")
        self.commit("fix: #9 server", "dw/a.py")
        g = dp.DeployGate(60)
        self.assertTrue(g.wanted([9], {9: False}, True))
        self.commit("fix: #10 server", "dw/b.py")  # develop moves during the drain
        calls = []

        def fake_run(argv, **kw):
            calls.append(argv)
            return subprocess.CompletedProcess(argv, 0, stdout="develop @ abc1234\n", stderr="")

        def fake_proc(argv, timeout=None):
            calls.append(argv)
            return 0, "a\nb\nc\nd\n"

        said = []
        with (
            mock.patch.object(deploy.subprocess, "run", fake_run),
            mock.patch.object(deploy, "_deploy_proc", fake_proc),
        ):
            ok, head = deploy.run_deploy(server, said.append)
        g.succeeded()
        deploys = [c for c in calls if "deploy.sh" in " ".join(c)]
        self.assertEqual(len(deploys), 1)
        self.assertIn("deploy.sh develop", deploys[0][2])
        self.assertTrue(ok)
        self.assertEqual(head, "develop @ abc1234")
        self.assertEqual([s for s in said], ["[loop:deploy] b", "[loop:deploy] c", "[loop:deploy] d"])
        self.assertFalse(g.wanted([], {}, True))


class DeploySessionTest(unittest.TestCase):
    def test_the_deploy_runs_in_a_session_of_its_own(self):
        seen = {}
        real = subprocess.Popen

        def spy(argv, **kw):
            seen.update(kw)
            return real(
                ["bash", "-c", "echo sid=$(ps -o sess= -p $$ 2>/dev/null); echo pgid=$(ps -o pgid= -p $$)"], **kw
            )

        with mock.patch.object(deploy.subprocess, "Popen", spy):
            rc, out = deploy._deploy_proc(["bash", "-c", "true"])
        self.assertTrue(seen.get("start_new_session"))
        self.assertEqual(rc, 0)
        pgid = int(out.split("pgid=")[1].split()[0])
        self.assertNotEqual(pgid, os.getpgrp())  # a Ctrl-C to the driver's group misses it

    def test_a_timeout_kills_the_group(self):
        t = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            deploy._deploy_proc(["bash", "-c", "sleep 30 & wait"], timeout=1)
        self.assertLess(time.monotonic() - t, 10)

    def test_each_server_has_its_own_out_file(self):
        logs = tempfile.mkdtemp()
        for name, sfx in (("lem", ""), ("mini-ai", ".mini-ai")):
            server = SimpleNamespace(host=name, dir="~/dw", local=False, name=name, suffix=sfx)
            with (
                mock.patch.object(deploy, "_deploy_proc", return_value=(0, f"deployed {name}\n")),
                mock.patch.object(deploy, "deployed_head", return_value="develop @ abc"),
            ):
                deploy.run_deploy(server, lambda s: None, logs=logs)
        self.assertEqual(pathlib.Path(logs, ".deploy.out").read_text(), "deployed lem\n")
        self.assertEqual(pathlib.Path(logs, ".deploy.mini-ai.out").read_text(), "deployed mini-ai\n")


if __name__ == "__main__":
    unittest.main()
