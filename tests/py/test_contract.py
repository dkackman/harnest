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


class StubClient:
    """Answers each call from a table of (is_error, result); records calls."""

    def __init__(self, answers):
        self.answers = answers
        self.calls = []

    def call(self, tool, args=None):
        self.calls.append((tool, args or {}))
        return self.answers[tool]


class StopAtFirstFailure(unittest.TestCase):
    def test_a_failed_step_keeps_the_later_ones_from_running(self):
        case = {
            "id": "X",
            "steps": [
                {"call": "validate_workflow", "expect": [{"path": "valid", "eq": False}]},
                {"call": "run_workflow", "is_error": True},
                {"call": "list_jobs"},
            ],
        }
        c = StubClient({"validate_workflow": (False, {"valid": True})})
        r = run.run_case(c, case)
        self.assertEqual("fail", r["status"])
        self.assertEqual(["validate_workflow"], [t for t, _ in c.calls])  # run_workflow was never sent
        self.assertIn("2 later step(s) not run", r["failures"][-1])

    def test_a_job_queued_where_a_refusal_was_expected_is_cancelled(self):
        case = {"id": "X", "steps": [{"call": "run_workflow", "is_error": True}]}
        c = StubClient({"run_workflow": (False, {"job_id": "j-9"}), "cancel_job": (False, {})})
        r = run.run_case(c, case)
        self.assertEqual([("run_workflow", {}), ("cancel_job", {"job_id": "j-9"})], c.calls)
        self.assertIn("it queued job j-9, now cancelled", r["failures"][0])

    def test_a_cancel_the_server_refuses_is_not_reported_as_cancelled(self):
        case = {"id": "X", "steps": [{"call": "run_workflow", "is_error": True}]}
        c = StubClient({"run_workflow": (False, {"job_id": "j-9"}), "cancel_job": (True, "no such job")})
        r = run.run_case(c, case)
        self.assertIn("it queued job j-9 and cancelling it failed: no such job", r["failures"][0])
        self.assertNotIn("now cancelled", r["failures"][0])

    def test_a_passing_case_runs_every_step_and_cancels_nothing(self):
        case = {"id": "X", "steps": [{"call": "a"}, {"call": "b", "is_error": True}]}
        c = StubClient({"a": (False, {}), "b": (True, "refused")})
        self.assertEqual("pass", run.run_case(c, case)["status"])
        self.assertEqual(["a", "b"], [t for t, _ in c.calls])

    def test_every_failed_assertion_of_the_failing_step_is_reported(self):
        case = {
            "id": "X",
            "steps": [
                {"call": "a", "expect": [{"path": "n", "eq": 2}, {"path": "m", "exists": True}]},
                {"call": "b"},
            ],
        }
        r = run.run_case(StubClient({"a": (False, {"n": 1})}), case)
        self.assertEqual(3, len(r["failures"]), r["failures"])
        self.assertTrue(r["failures"][0].startswith("step 1 (a): n: expected == 2"), r["failures"][0])
        self.assertIn("1 later step(s) not run", r["failures"][2])


class Paths(unittest.TestCase):
    DOC = {"a": {"b": [10, 20, 30]}, "items": [{"k": 1}, {"k": 2}], "repo/x.y": {"gb": 5}, "s": "text"}

    def test_paths_resolve(self):
        for path, want in (
            ("", [self.DOC]),
            ("a.b", [[10, 20, 30]]),
            ("a.b[1]", [20]),
            ("a.b[2]", [30]),
            ("items[*].k", [1, 2]),
            ("items[1].k", [2]),
            ('["repo/x.y"].gb', [5]),
            ("a.b[*]", [10, 20, 30]),
        ):
            self.assertEqual(want, run.resolve(self.DOC, path), path)

    def test_a_path_that_does_not_resolve_is_missing_not_an_exception(self):
        for path in ("nope", "a.nope", "a.b[9]", "s.x", "s[0]", "a[*]", "items[*].nope", "a.b.c"):
            vals = run.resolve(self.DOC, path)
            self.assertTrue(vals and all(v is run.MISSING for v in vals), path)

    def test_a_fan_out_over_an_empty_list_is_no_values(self):
        self.assertEqual([], run.resolve({"items": []}, "items[*].k"))


class Assertions(unittest.TestCase):
    R = {
        "valid": False,
        "n": 3,
        "msg": "must be at most 345",
        "tags": ["a", "b"],
        "errors": [{"path": "arguments.x", "message": "too big"}, {"path": "arguments.y", "message": "unknown"}],
    }
    # (assertion, passes)
    TABLE = (
        ({"path": "valid", "eq": False}, True),
        ({"path": "valid", "eq": True}, False),
        ({"path": "n", "ne": 4}, True),
        ({"path": "n", "ne": 3}, False),
        ({"path": "msg", "exists": True}, True),
        ({"path": "plan", "exists": True}, False),
        ({"path": "plan", "exists": False}, True),
        ({"path": "msg", "exists": False}, False),
        ({"path": "errors", "len": 2}, True),
        ({"path": "errors", "len": 1}, False),
        ({"path": "n", "len": 1}, False),
        ({"path": "msg", "contains": ["at most", "345"]}, True),
        ({"path": "msg", "contains": ["at most", "999"]}, False),
        ({"path": "tags", "contains": "a"}, True),
        ({"path": "tags", "contains": ["a", "c"]}, False),
        ({"path": "tags", "contains_any": ["c", "b"]}, True),
        ({"path": "tags", "contains_any": ["c", "d"]}, False),
        ({"path": "msg", "contains_any": ["nope", "345"]}, True),
        ({"path": "msg", "not_contains": "job_id"}, True),
        ({"path": "msg", "not_contains": ["job_id", "345"]}, False),
        ({"path": "tags", "not_contains": "c"}, True),
        ({"path": "tags", "not_contains": "b"}, False),
        ({"path": "errors", "any_contains": ['"path": "arguments.y"', "unknown"]}, True),
        ({"path": "errors", "any_contains": ['"path": "arguments.y"', "too big"]}, False),
        ({"path": "errors[*].message", "any_contains": "too"}, True),
        ({"path": "errors", "none_contains": "arguments.z"}, True),
        ({"path": "errors", "none_contains": "arguments.x"}, False),
        ({"path": "errors[*].path", "eq": ["arguments.x", "arguments.y"]}, True),
        ({"path": "errors[*].path", "contains": "arguments.y"}, True),
        ({"path": "nope", "eq": 1}, False),
        ({"path": "nope", "ne": 1}, False),  # absent is not "different"
        ({"path": "n", "eq": 3, "ne": 4}, True),  # several keys: all must hold
        ({"path": "n", "eq": 3, "ne": 3}, False),
    )

    def test_each_kind_passes_and_fails(self):
        for a, passes in self.TABLE:
            why = run.check(self.R, a)
            self.assertEqual(passes, why is None, f"{a}: {why}")
            if why:
                self.assertTrue(why.startswith(a["path"] + ": "), why)

    def test_the_whole_result_is_the_empty_path(self):
        self.assertIsNone(run.check("Unknown workflow: x", {"path": "", "contains": "Unknown workflow"}))
        self.assertIn("got Unknown workflow: x", run.check("Unknown workflow: x", {"path": "", "eq": "y"}))


class FanOutOverMissingKeys(unittest.TestCase):
    """The 2026-11-26 pilot's crash: a fanned-out path whose element lacks the
    key put MISSING into the value a failure prints, and json.dumps raised."""

    HOLES = {"assets": [{"reference": "asset:a"}, {"name": "b"}]}

    def test_a_fan_out_under_a_missing_key_fails_as_not_found(self):
        for a in ({"contains": "x"}, {"eq": []}, {"none_contains": "x"}, {"any_contains": "x"}, {"exists": True}):
            why = run.check({}, dict(a, path="assets[*].reference"))
            self.assertIsInstance(why, str, a)
            self.assertIn("assets[*].reference: ", why)
        self.assertIn("path not found", run.check({}, {"path": "assets[*].reference", "contains": "x"}))
        self.assertIsNone(run.check({}, {"path": "assets[*].reference", "exists": False}))

    def test_an_element_without_the_key_fails_a_comparison(self):
        for a in (
            {"eq": ["asset:a"]},
            {"ne": ["asset:a"]},
            {"len": 2},
            {"contains": "asset:a"},
            {"contains_any": ["asset:a"]},
            {"exists": True},
        ):
            why = run.check(self.HOLES, dict(a, path="assets[*].reference"))
            self.assertIsInstance(why, str, a)
            self.assertIn("<missing>", why, a)
        why = run.check(self.HOLES, {"path": "assets[*].reference", "eq": ["asset:a"]})
        self.assertIn("path not found in 1 of 2 elements", why)

    def test_the_element_wise_kinds_look_at_the_elements_that_have_it(self):
        path = "assets[*].reference"
        self.assertIsNone(run.check(self.HOLES, {"path": path, "any_contains": "asset:a"}))
        self.assertIsNone(run.check(self.HOLES, {"path": path, "none_contains": "asset:z"}))
        self.assertIsNone(run.check(self.HOLES, {"path": path, "not_contains": "asset:z"}))
        self.assertIsInstance(run.check(self.HOLES, {"path": path, "none_contains": "asset:a"}), str)

    def test_the_case_fails_and_the_run_goes_on(self):
        case = {"id": "X", "steps": [{"call": "list_assets", "expect": [{"path": "assets[*].reference", "len": 2}]}]}
        r = run.run_case(StubClient({"list_assets": (False, self.HOLES)}), case)
        self.assertEqual("fail", r["status"])
        self.assertIn("path not found in 1 of 2 elements", r["failures"][0])


class Script:
    """Answers the calls in order from a list of (is_error, result)."""

    def __init__(self, *answers):
        self.answers = list(answers)
        self.calls = []

    def call(self, tool, args=None):
        self.calls.append((tool, args or {}))
        return self.answers[len(self.calls) - 1]


class Capture(unittest.TestCase):
    FIRST = (False, {"job_id": "j-1", "plan": {"fingerprint": "abc", "frames": 49}, "jobs": [{"id": "x"}, {"id": "y"}]})
    CAP = {"job": "job_id", "fp": "plan.fingerprint", "frames": "plan.frames", "ids": "jobs[*].id", "plan": "plan"}

    def run_two(self, second_step, second_answer=(False, {}), capture=None):
        c = Script(self.FIRST, second_answer)
        case = {"id": "X", "steps": [{"call": "first", "capture": capture or self.CAP}, second_step]}
        return run.run_case(c, case), c

    def test_a_captured_value_is_used_in_later_args(self):
        r, c = self.run_two({"call": "get_job", "args": {"job_id": "${job}"}})
        self.assertEqual("pass", r["status"], r["failures"])
        self.assertEqual(("get_job", {"job_id": "j-1"}), c.calls[1])

    def test_anywhere_in_the_structure_and_inside_longer_strings(self):
        args = {
            "note": "rerun of ${job} at ${frames} frames",
            "arguments": {"shots": [{"num_frames": "${frames}", "refs": ["output:${job}/a.png", "${ids}"]}]},
            "plan": "${plan}",
            "${job}": "a key is not a value",
        }
        r, c = self.run_two({"call": "run_workflow", "args": args})
        self.assertEqual("pass", r["status"], r["failures"])
        self.assertEqual(
            {
                "note": "rerun of j-1 at 49 frames",
                "arguments": {"shots": [{"num_frames": 49, "refs": ["output:j-1/a.png", ["x", "y"]]}]},
                "plan": {"fingerprint": "abc", "frames": 49},
                "${job}": "a key is not a value",
            },
            c.calls[1][1],
        )

    def test_the_case_itself_is_not_changed_by_a_run(self):
        step = {"call": "get_job", "args": {"job_id": "${job}"}, "expect": [{"path": "id", "eq": "${job}"}]}
        self.run_two(step, (False, {"id": "j-1"}))
        self.assertEqual({"job_id": "${job}"}, step["args"])
        self.assertEqual([{"path": "id", "eq": "${job}"}], step["expect"])

    def test_a_captured_value_is_the_comparison_value_of_an_assertion(self):
        same = (False, {"plan": {"fingerprint": "abc"}, "msg": "job j-1 queued", "ids": ["x", "y"]})
        for a, passes in (
            ({"path": "plan.fingerprint", "eq": "${fp}"}, True),
            ({"path": "plan.fingerprint", "ne": "${fp}"}, False),
            ({"path": "plan.fingerprint", "eq": "${job}"}, False),
            ({"path": "plan.fingerprint", "ne": "${job}"}, True),
            ({"path": "msg", "contains": "${job}"}, True),
            ({"path": "msg", "contains": ["job ${job} queued"]}, True),
            ({"path": "msg", "not_contains": "${fp}"}, True),
            ({"path": "msg", "not_contains": ["nope", "${job}"]}, False),
            ({"path": "ids", "eq": "${ids}"}, True),
            ({"path": "ids", "len": "${frames}"}, False),
            ({"path": "ids", "contains_any": ["${job}", "x"]}, True),
        ):
            r, _ = self.run_two({"call": "second", "expect": [a]}, same)
            self.assertEqual("pass" if passes else "fail", r["status"], f"{a}: {r['failures']}")

    def test_a_failed_comparison_shows_the_captured_value(self):
        r, _ = self.run_two(
            {"call": "second", "expect": [{"path": "plan.fingerprint", "eq": "${fp}"}]},
            (False, {"plan": {"fingerprint": "zzz"}}),
        )
        self.assertEqual(["step 2 (second): plan.fingerprint: expected == abc (got zzz)"], r["failures"])

    def test_a_path_is_never_substituted(self):
        r, _ = self.run_two({"call": "second", "expect": [{"path": "${job}", "eq": 1}]}, (False, {"${job}": 1}))
        self.assertEqual("pass", r["status"], r["failures"])

    def test_a_step_may_use_its_own_captures(self):
        case = {
            "id": "X",
            "steps": [
                {
                    "call": "list",
                    "capture": {"first": "items[0].size"},
                    "expect": [{"path": "items[1].size", "eq": "${first}"}],
                }
            ],
        }
        self.assertEqual("pass", run.run_case(Script((False, {"items": [{"size": 4}, {"size": 4}]})), case)["status"])
        self.assertEqual("fail", run.run_case(Script((False, {"items": [{"size": 4}, {"size": 5}]})), case)["status"])

    def test_a_later_capture_replaces_an_earlier_one(self):
        c = Script((False, {"n": 1}), (False, {"n": 2}), (False, {}))
        steps = [{"call": "a", "capture": {"n": "n"}}, {"call": "b", "capture": {"n": "n"}}]
        run.run_case(c, {"id": "X", "steps": [*steps, {"call": "c", "args": {"n": "${n}"}}]})
        self.assertEqual({"n": 2}, c.calls[2][1])

    def test_the_whole_result_and_a_tool_error_text_can_be_captured(self):
        c = Script((True, "Unknown workflow: x"), (True, "Error executing tool: Unknown workflow: x"))
        case = {
            "id": "X",
            "steps": [
                {"call": "get_workflow", "is_error": True, "capture": {"msg": ""}},
                {"call": "validate_workflow", "is_error": True, "expect": [{"path": "", "contains": "${msg}"}]},
            ],
        }
        self.assertEqual("pass", run.run_case(c, case)["status"])

    def test_a_name_nothing_captured_fails_the_case_and_the_step_is_not_sent(self):
        r, c = self.run_two(
            {"call": "cancel_job", "args": {"job_id": "${jbo}"}}, capture={"job": "job_id", "fp": "plan.fingerprint"}
        )
        self.assertEqual("fail", r["status"])
        self.assertEqual(["first"], [t for t, _ in c.calls])
        self.assertEqual(
            ["step 2 (cancel_job): ${jbo} is used, but no step has captured it (captured so far: fp, job)"],
            r["failures"],
        )

    def test_a_name_nothing_captured_in_an_assertion_fails_the_case(self):
        c = Script((False, {"a": 1}), (False, {}))
        case = {"id": "X", "steps": [{"call": "a", "expect": [{"path": "a", "eq": "${nope}"}]}, {"call": "b"}]}
        r = run.run_case(c, case)
        self.assertEqual("fail", r["status"])
        self.assertIn("${nope} is used, but no step has captured it (captured so far: nothing)", r["failures"][0])
        self.assertIn("1 later step(s) not run", r["failures"][1])
        self.assertEqual(1, len(c.calls))

    def test_a_capture_whose_path_does_not_resolve_fails_the_case(self):
        for path in ("plan.nope", "jobs[*].nope", "jobs[7].id", "nope[*]"):
            r, c = self.run_two({"call": "second"}, capture={"v": path})
            self.assertEqual("fail", r["status"], path)
            self.assertIn(f"step 1 (first): capture 'v': path {path!r} not found (got ", r["failures"][0])
            self.assertIn("1 later step(s) not run", r["failures"][1])
            self.assertEqual(1, len(c.calls), path)

    def test_a_fan_out_over_an_empty_list_captures_an_empty_list(self):
        c = Script((False, {"jobs": []}), (False, {"jobs": []}))
        case = {
            "id": "X",
            "steps": [
                {"call": "list_jobs", "capture": {"before": "jobs[*].id"}},
                {"call": "list_jobs", "args": {"seen": "${before}"}},
            ],
        }
        self.assertEqual("pass", run.run_case(c, case)["status"])
        self.assertEqual({"seen": []}, c.calls[1][1])

    def test_nothing_is_captured_from_a_step_whose_error_flag_is_wrong(self):
        c = Script((True, "refused"), (False, {}))
        case = {"id": "X", "steps": [{"call": "a", "capture": {"job": "job_id"}}, {"call": "b"}]}
        r = run.run_case(c, case)
        self.assertEqual(2, len(r["failures"]), r["failures"])
        self.assertIn("tool error flag was True", r["failures"][0])

    def test_an_escaped_reference_and_a_non_name_are_sent_as_written(self):
        args = {"a": "$${job}", "b": "{{7*7}} ${7*7}", "c": "${}", "d": "$job {job}", "e": "x $${job} ${job}"}
        _, c = self.run_two({"call": "second", "args": args})
        self.assertEqual(
            {"a": "${job}", "b": "{{7*7}} ${7*7}", "c": "${}", "d": "$job {job}", "e": "x ${job} j-1"}, c.calls[1][1]
        )

    def test_a_capture_name_that_could_never_be_used_is_an_error(self):
        with self.assertRaises(run.MCPError):
            run.run_case(Script((False, {"a": 1})), {"id": "X", "steps": [{"call": "a", "capture": {"my-job": "a"}}]})


class ShippedCases(unittest.TestCase):
    def test_every_case_is_well_formed_and_uses_only_what_an_earlier_step_captured(self):
        files = sorted((HERE / "contract" / "cases").glob("*.json"))
        self.assertTrue(files)
        for f in files:
            case = json.loads(f.read_text())
            self.assertEqual(f.stem, case["id"])
            captured = {}
            for step in case["steps"]:
                self.assertIsInstance(step["call"], str, f.name)
                run.substitute(step.get("args", {}), captured)  # raises on a name not yet captured
                for name in step.get("capture", {}):
                    self.assertRegex(name, r"^[A-Za-z_][A-Za-z0-9_]*$", f.name)
                    captured[name] = "x"
                for a in step.get("expect", []):
                    run.substitute({k: v for k, v in a.items() if k != "path"}, captured)
                    run.check({}, a)  # an unknown assertion key raises


class CommandLine(unittest.TestCase):
    """run.py as a program against tests/fake-mcp.py: --cases-dir, exit codes."""

    PASS = {"call": "validate_workflow", "expect": [{"path": "valid", "eq": True}]}
    FAIL = {"call": "validate_workflow", "expect": [{"path": "valid", "eq": False}]}

    def run_py(self, url, *argv, env=None):
        r = subprocess.run(
            [sys.executable, str(HERE / "contract" / "run.py"), "--url", url, *argv],
            capture_output=True,
            text=True,
            env={"PATH": "/usr/bin:/bin", "DW_TOKEN": "t", **(env or {})},
        )
        return r, (json.loads(r.stdout) if r.stdout.strip() else None)

    def write(self, d, **cases):
        for cid, steps in cases.items():
            (Path(d) / f"{cid}.json").write_text(json.dumps({"id": cid, "level": "smoke", "steps": steps}))

    def test_cases_dir_runs_the_cases_kept_elsewhere(self):
        with FakeServer() as srv, tempfile.TemporaryDirectory() as d:
            self.write(d, **{"X-1": [self.PASS], "X-2": [self.PASS]})
            r, report = self.run_py(srv.url, "--cases-dir", d)
            self.assertEqual(0, r.returncode, r.stderr)
            self.assertEqual(["X-1", "X-2"], [c["id"] for c in report["cases"]])
            self.assertEqual((2, 0, 0), (report["passed"], report["failed"], report["errors"]))
            r, report = self.run_py(srv.url, "--cases-dir", d, "X-2")
            self.assertEqual(["X-2"], [c["id"] for c in report["cases"]])

    def test_the_default_is_contract_cases(self):
        with FakeServer() as srv:
            r, report = self.run_py(srv.url, "S-F002")
            self.assertEqual(["S-F002"], [c["id"] for c in report["cases"]])
            self.assertEqual(1, r.returncode)  # the fake server's catalog is not dw's

    def test_a_cases_dir_that_is_not_there_is_a_usage_error(self):
        with tempfile.TemporaryDirectory() as d:
            r, report = self.run_py("http://127.0.0.1:1/mcp", "--cases-dir", str(Path(d) / "nope"))
            self.assertEqual((2, None), (r.returncode, report))
            self.assertIn("not a directory", r.stderr)

    def test_exit_status_is_0_all_passed_1_any_failed_2_any_errored(self):
        with FakeServer() as srv, tempfile.TemporaryDirectory() as d:
            self.write(d, **{"X-1": [self.PASS]})
            self.assertEqual(0, self.run_py(srv.url, "--cases-dir", d)[0].returncode)
            self.write(d, **{"X-2": [self.FAIL, self.PASS]})
            r, report = self.run_py(srv.url, "--cases-dir", d)
            self.assertEqual(1, r.returncode)
            self.assertEqual((1, 1, 0), (report["passed"], report["failed"], report["errors"]))
            self.write(d, **{"X-3": [{"call": "validate_workflow", "expect": [{"path": "valid", "equals": 1}]}]})
            r, report = self.run_py(srv.url, "--cases-dir", d)
            self.assertEqual(2, r.returncode)
            self.assertEqual((1, 1, 1), (report["passed"], report["failed"], report["errors"]))

    def test_an_unreachable_server_is_2_with_a_report(self):
        with tempfile.TemporaryDirectory() as d:
            self.write(d, **{"X-1": [self.PASS]})
            r, report = self.run_py(f"http://127.0.0.1:{free_port()}/mcp", "--cases-dir", d)
            self.assertEqual(2, r.returncode)
            self.assertIn("server unreachable", report["error"])

    def test_no_token_is_a_usage_error(self):
        r, report = self.run_py("http://127.0.0.1:1/mcp", env={"DW_TOKEN": ""})
        self.assertEqual((2, None), (r.returncode, report))
        self.assertIn("no MCP token", r.stderr)

    def test_a_case_the_runner_chokes_on_errors_and_the_others_still_run(self):
        with FakeServer() as srv, tempfile.TemporaryDirectory() as d:
            self.write(d, **{"X-1": [{"expect": []}], "X-2": [self.PASS], "X-3": "not steps"})
            r, report = self.run_py(srv.url, "--cases-dir", d)
            self.assertEqual(2, r.returncode, r.stderr)
            by_id = {c["id"]: c for c in report["cases"]}
            self.assertEqual(["error", "pass", "error"], [by_id[i]["status"] for i in ("X-1", "X-2", "X-3")])
            self.assertIn("KeyError", by_id["X-1"]["failures"][0])

    def test_capture_works_over_the_wire(self):
        with FakeServer() as srv, tempfile.TemporaryDirectory() as d:
            steps = [
                {"call": "validate_workflow", "capture": {"plan": "plan", "ok": "valid"}},
                {
                    "call": "validate_workflow",
                    "args": {"arguments": {"seen": "${plan}"}},
                    "expect": [{"path": "plan", "eq": "${plan}"}, {"path": "valid", "eq": "${ok}"}],
                },
                {"call": "list_assets", "capture": {"job": "job_id"}},
            ]
            self.write(d, **{"X-1": steps[:2], "X-2": steps})
            r, report = self.run_py(srv.url, "--cases-dir", d)
            self.assertEqual(1, r.returncode, r.stdout)
            self.assertEqual(["pass", "fail"], [c["status"] for c in report["cases"]])
            self.assertIn("capture 'job': path 'job_id' not found", report["cases"][1]["failures"][0])


if __name__ == "__main__":
    unittest.main()
