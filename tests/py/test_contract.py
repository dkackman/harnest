"""contract/run.py: a case asserts something or fails, ids match filenames,
and importing the runner does not run it."""

import importlib.util
import json
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(HERE / "contract"))


def load():
    spec = importlib.util.spec_from_file_location("contract_run", HERE / "contract" / "run.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


run = load()


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class FakeServer:
    """tests/fake-mcp.py on one port."""

    def __enter__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.port = free_port()
        spec = Path(self.tmp.name) / "spec.json"
        spec.write_text(json.dumps({str(self.port): {"hostname": "alpha", "device": "cuda", "workers": 1}}))
        self.proc = subprocess.Popen(
            [sys.executable, str(HERE / "tests" / "fake-mcp.py"), str(spec)], stdout=subprocess.PIPE, text=True
        )
        self.proc.stdout.readline()  # "ready"
        self.url = f"http://127.0.0.1:{self.port}/mcp"
        return self

    def __exit__(self, *exc):
        self.proc.kill()
        self.proc.wait()
        self.proc.stdout.close()
        self.tmp.cleanup()


class Contract(unittest.TestCase):
    def test_unknown_assertion_key_fails_the_case(self):
        with FakeServer() as srv:
            client = run.MCPClient(srv.url, "t")
            client.initialize()
            for bad in ({"path": "valid", "equals": True}, {"path": "valid"}, {}):
                case = {"id": "X-1", "steps": [{"call": "validate_workflow", "expect": [bad]}]}
                with self.assertRaises(run.MCPError, msg=repr(bad)):
                    run.run_case(client, case)
            ok = {"id": "X-2", "steps": [{"call": "validate_workflow", "expect": [{"path": "valid", "eq": True}]}]}
            self.assertEqual("pass", run.run_case(client, ok)["status"])

    def test_id_must_match_filename(self):
        with FakeServer() as srv, tempfile.TemporaryDirectory() as d:
            cases = Path(d) / "cases"
            cases.mkdir()
            step = [{"call": "validate_workflow", "expect": [{"path": "valid", "eq": True}]}]
            (cases / "X-1.json").write_text(json.dumps({"id": "X-1", "steps": step}))
            (cases / "X-2.json").write_text(json.dumps({"id": "X-9", "steps": step}))
            runner = Path(d) / "contract"
            runner.mkdir()
            for f in ("run.py", "mcp_client.py"):
                (runner / f).write_text((HERE / "contract" / f).read_text())
            (runner / "cases").symlink_to(cases)
            r = subprocess.run(
                [sys.executable, str(runner / "run.py"), "--url", srv.url, "--token", "t"],
                capture_output=True,
                text=True,
            )
            report = json.loads(r.stdout)
            by_id = {c["id"]: c for c in report["cases"]}
            self.assertEqual("pass", by_id["X-1"]["status"])
            self.assertEqual("error", by_id["X-2"]["status"])
            self.assertIn("X-9", by_id["X-2"]["failures"][0])
            self.assertEqual(2, r.returncode)

    def test_import_does_not_run_main(self):
        r = subprocess.run(
            [sys.executable, "-c", "import sys; sys.path.insert(0, 'contract'); import run; print('imported')"],
            capture_output=True,
            text=True,
            cwd=HERE,
            env={"PATH": "/usr/bin:/bin"},
        )
        self.assertEqual(("imported\n", 0), (r.stdout, r.returncode), r.stderr)


if __name__ == "__main__":
    unittest.main()
