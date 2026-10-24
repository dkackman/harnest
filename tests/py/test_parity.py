"""The harness/ modules against the bash they replace (R8). Each test runs
the providers.sh function and the Python one on the same input and wants
the same answer, so a drift in either shows up here; when providers.sh is
deleted these become plain fixture tests.

    python3 -m unittest discover -s tests/py -t .
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from harness import REPO, outcome, prompts, providers, session, stream, suite
from harness.profile import ProfileError, load, load_env_file, resolve_token, resolve_url, short_host, url_host

FIXTURES = REPO / "tests" / "fixtures"


def bash(script, _unset=(), **env):
    """Runs <script> with providers.sh sourced; stdout, or None on failure."""
    e = {k: v for k, v in os.environ.items() if k not in _unset}
    e.update(LOGS=tempfile.gettempdir(), **env)
    p = subprocess.run(
        ["bash", "-c", f'. "{REPO}/providers.sh" >/dev/null 2>&1; {script}'], capture_output=True, text=True, env=e
    )
    return p.stdout if p.returncode == 0 else None


def bash_words(script, _unset=(), **env):
    out = bash("{ " + script + '; } || exit 1; printf "%s\\0" "${W[@]}"', _unset, **env)
    return None if out is None else out.split("\0")[:-1]


class Stream(unittest.TestCase):
    def test_golden(self):
        lines = (FIXTURES / "stream.jsonl").read_text().splitlines()
        want = (FIXTURES / "stream.expected").read_text().splitlines()
        self.assertEqual(want, list(stream.render_lines(lines)))

    def test_matches_jq_on_edge_cases(self):
        events = [
            {
                "type": "assistant",
                "message": {
                    "id": "a",
                    "usage": {"input_tokens": 123456},
                    "content": [
                        {"type": "tool_use", "name": "mcp__dw__run_workflow", "input": {"x": "é" * 300, "n": 1.0}},
                        {"type": "text", "text": "two\nlines"},
                    ],
                },
            },
            {"type": "assistant", "message": {"id": "b", "usage": None, "content": None}},
            {"type": "user", "message": {"content": [{"type": "tool_result", "content": {"a": 1}}]}},
            {"type": "user", "message": {"content": "a string"}},
            {
                "type": "rate_limit_event",
                "rate_limit_info": {"status": "allowed", "isUsingOverage": True, "resetsAt": 5},
            },
            {
                "type": "result",
                "subtype": "error_max_turns",
                "num_turns": 9,
                "duration_ms": 2500,
                "total_cost_usd": 1.005,
                "usage": {"input_tokens": 999, "output_tokens": 1950},
                "modelUsage": {"m1": {"inputTokens": 1, "costUSD": 0.5}, "m2": {"outputTokens": 1500, "costUSD": 0.25}},
            },
            123,
            "null",
            [1],
        ]
        lines = [json.dumps(e, ensure_ascii=False) if not isinstance(e, str) else e for e in events] + ["", "not json"]
        prog = bash('printf "%s" "$_STREAM_RENDER_JQ"')
        p = subprocess.run(["jq", "-Rn", "-r", prog], input="\n".join(lines) + "\n", capture_output=True, text=True)
        got = list(stream.render_lines(lines))
        want = p.stdout.splitlines()
        # jq's own error messages aren't reproduced, only that one is printed
        norm = lambda ls: ["render-error:" if x.startswith("render-error:") else x for x in ls]
        self.assertEqual(norm(want), norm("\n".join(got).splitlines()))

    def test_resolved_model(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as f:
            f.write(
                '{"type":"system","subtype":"init","model":"claude-opus-5-5"}\nnoise\n'
                '{"type":"system","subtype":"init","model":"claude-sonnet-5-5"}\n'
            )
        self.assertEqual("claude-sonnet-5-5", stream.resolved_model(f.name, "sonnet"))
        self.assertEqual("sonnet", stream.resolved_model(f.name + ".missing", "sonnet"))
        os.unlink(f.name)


class Outcome(unittest.TestCase):
    CASES = {
        "ok": "model: m\nusage: turns=1 duration=1s cost=$0 ctx_peak=0 in=0 cache_read=0 cache_write=0 out=0\n",
        "budget": "usage: turns=1 duration=1s cost=$0\nresult: error_max_budget_usd x\n",
        "rejected": "rate-limit: status=rejected type=five_hour overage=false resets=x resets_epoch=100\nusage: turns=1\n",
        "died": "model: m\n> Bash {}\n",
        "abort": "usage: turns=1\nREGRESSION-ABORT: unreachable\n- REGRESSION-SKIP: S-F001 fixture x\n"
        "`REGRESSION-SKIP: none\nREGRESSION-DIFFERS: C-F002 basis: expected a got b\n",
    }

    def test_against_bash(self):
        for name, text in self.CASES.items():
            with tempfile.NamedTemporaryFile("w", delete=False) as f:
                f.write(text)
            for fn in ("died", "ran", "ok"):
                want = bash(f'session_{fn} "{f.name}" && echo y || echo n').strip() == "y"
                self.assertEqual(want, getattr(outcome, fn)(f.name), f"{fn} on {name}")
            os.unlink(f.name)

    def test_regression_lines(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write(self.CASES["abort"])
        self.assertTrue(outcome.aborted(f.name))
        self.assertEqual((1, 1), outcome.regression_counts(f.name))
        os.unlink(f.name)

    def test_rate_limit_sleep(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write(self.CASES["rejected"])
        said, slept = [], []
        outcome.sleep_if_rate_limited(f.name, said.append, now=lambda: 50, sleep=slept.append)
        self.assertEqual([110], slept)
        self.assertIn("sleeping 110s until ", said[0])
        os.unlink(f.name)

    def test_rate_limit_without_reset_sleeps_the_fallback(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("rate-limit: status=rejected type=x overage=false resets=1970 resets_epoch=0\nusage: turns=1\n")
        said, slept = [], []
        os.environ["RATE_LIMIT_FALLBACK_SECS"] = "7"
        try:
            self.assertTrue(outcome.sleep_if_rate_limited(f.name, said.append, sleep=slept.append))
        finally:
            del os.environ["RATE_LIMIT_FALLBACK_SECS"]
        self.assertEqual([7], slept)
        self.assertFalse(outcome.sleep_if_rate_limited(os.devnull, said.append, sleep=slept.append))
        os.unlink(f.name)


class Providers(unittest.TestCase):
    PAIRS = [
        ("anthropic", "opus"),
        ("anthropic", "claude-sonnet-5-5"),
        ("anthropic", "qwen3:32b"),
        ("ollama", "qwen3:32b"),
        ("ollama", "sonnet"),
        ("gateway", "x"),
        ("nosuch", "opus"),
    ]
    ENV = {"OLLAMA_CONTEXT_TOKENS": "65536", "GW_BASE_URL": "http://gw", "GW_TOKEN": "t", "GW_CONTEXT_TOKENS": "100000"}

    def test_model_env_against_bash(self):
        for provider, model in self.PAIRS:
            want = bash_words(
                f'resolve_model_env "{provider}" "{model}" && W=("$MODEL_LABEL" "$MODEL_CONTEXT_TOKENS" '
                '${MODEL_ENV[@]+"${MODEL_ENV[@]}"})',
                **self.ENV,
            )
            try:
                me = providers.resolve_model_env(provider, model, environ=self.ENV)
            except providers.ProviderError:
                self.assertIsNone(want, f"{provider}/{model}")
                continue
            words = [x for k in me.unset for x in ("-u", k)] + [f"{k}={v}" for k, v in me.set.items()]
            self.assertEqual(want, [me.label, me.context_tokens, *words], f"{provider}/{model}")

    def test_session_flags_against_bash(self):
        for provider, model, effort, budget, fb in [
            ("anthropic", "opus", "high", "6", "sonnet"),
            ("ollama", "q:1", "medium", "0", ""),
            ("anthropic", "opus", "huge", "6", ""),
        ]:
            want = bash_words(
                f'session_flags "{provider}" "{model}" "{effort}" "{budget}" && W=("${{SESSION_FLAGS[@]}}")',
                FALLBACK_MODEL=fb,
                AUTOCOMPACT_TOKENS="90000",
            )
            try:
                got = providers.session_flags(provider, model, effort, budget, fb, "90000")
            except providers.ProviderError:
                got = None
            self.assertEqual(want, got)

    def test_co_author_against_bash(self):
        for provider, model in [("anthropic", "claude-opus-5-5"), ("gateway", "opus"), ("ollama", "qwen3:32b")]:
            want = bash_words(f'co_author_for {provider} {model}; W=("$CO_AUTHOR" "$CO_AUTHOR_EMAIL")')
            self.assertEqual(want, list(providers.co_author_for(provider, model)))


class Session(unittest.TestCase):
    def test_consumer_flags_against_bash(self):
        self.assertEqual(bash_words('W=("${CONSUMER_PERMISSION_FLAGS[@]}")'), session.consumer_permission_flags())
        self.assertEqual(
            bash_words('W=("${ISOLATION_FLAGS[@]}" "$CONSUMER_TOOLS")'),
            [*session.ISOLATION_FLAGS, session.CONSUMER_TOOLS],
        )
        self.assertEqual(bash_words('W=("${STREAM_FLAGS[@]}")'), session.STREAM_FLAGS)


class Prompts(unittest.TestCase):
    def test_role_prompt_against_bash(self):
        with tempfile.TemporaryDirectory() as d:
            for kind in ("whole", "chunk", "sweep"):
                bash(f'role_prompt regression {kind} "{d}/b.md"')
                prompts.role_prompt("regression", kind, Path(d) / "p.md")
                self.assertEqual(Path(d, "b.md").read_bytes(), Path(d, "p.md").read_bytes(), kind)
        with self.assertRaises(prompts.PromptError):
            prompts.role_prompt("regression", "nosuch", "/dev/null")

    def test_runtime_note_against_bash(self):
        for role, sfx in [("regression", ""), ("regression", ".mini-ai"), ("tester", ""), ("lead", "")]:
            for model in ("claude-opus-5-5", "qwen3:32b"):
                want = bash(f'TARGET_SUFFIX="{sfx}"; runtime_note {role} anthropic {model}').rstrip("\n")
                self.assertEqual(want, prompts.runtime_note(role, "anthropic", model, secondary=bool(sfx)))

    def test_target_note_against_bash(self):
        want = bash(
            'DW_TARGET=mini-ai; resolve_target; target_note regression "mps on mini-ai.lan"', DW_TARGET="mini-ai"
        )
        from harness import deploy

        s = load().server("mini-ai")
        got = prompts.target_note(
            "regression",
            {
                "TARGET": s.name,
                "SERVER": "mps on mini-ai.lan",
                "URL": resolve_url(s),
                "DEPLOY": deploy.deploy_cmd(s),
                "HOST": s.host,
                "SERVER_DIR": s.dir,
            },
        )
        self.assertEqual(want, got)


class Profile(unittest.TestCase):
    def test_servers_match_target_row(self):
        p = load()
        loop = [s for s in p.servers if s.loop]  # the bash drivers know only these
        for s in loop:
            row = bash(f"target_row {s.name}").split()
            self.assertEqual(row, [s.host, s.dir, s.backend])
        self.assertEqual(bash('echo "$TARGETS"').strip(), " ".join(s.name for s in loop))
        self.assertIsNone(bash("target_row minid"))
        self.assertTrue(p.server("minid").local and p.server("minid").suffix == ".minid")
        self.assertTrue(p.servers[0].primary and p.servers[0].suffix == "")
        self.assertEqual(".mini-ai", p.server("mini-ai").suffix)

    def test_resolve_url(self):
        p = load()
        lem, mini = p.server("lem"), p.server("mini-ai")
        self.assertEqual("http://lem:8765/mcp", resolve_url(lem))
        self.assertEqual("http://tunnel:1/mcp", resolve_url(lem, "http://tunnel:1/mcp"))
        self.assertEqual("http://mini-ai:8765/mcp", resolve_url(mini))
        with self.assertRaises(ProfileError):
            resolve_url(mini, "http://lem:8765/mcp")
        self.assertEqual("::1", url_host("http://[::1]:8765/mcp"))
        self.assertEqual("mac-mini", short_host("Mac-mini.lan"))
        with self.assertRaises(ProfileError):
            p.server("local")

    def test_tokens_come_from_the_environment_only(self):
        p = load()
        lem, mini = p.server("lem"), p.server("mini-ai")
        self.assertEqual(("DW_TOKEN_LEM", "DW_TOKEN_MINI_AI"), (lem.token_env, mini.token_env))
        self.assertEqual("m", resolve_token(mini, {"DW_TOKEN_MINI_AI": "m", "DW_TOKEN": "d"}))
        self.assertEqual("d", resolve_token(lem, {"DW_TOKEN_MINI_AI": "m", "DW_TOKEN": "d"}))
        with self.assertRaises(ProfileError):
            resolve_token(lem, {"DW_TOKEN_MINI_AI": "m"})
        self.assertNotIn("token =", (REPO / "targets" / "dw" / "profile.toml").read_text())

    ENV_FILE = (
        "# a comment\n\n  DW_TOKEN_LEM = 'quoted lem'  \nexport DW_TOKEN_MINI_AI=\"mini\"\r\n"
        "DW_TOKEN=plain=with=equals\nPROVIDER=ollama\nDW_TOKEN_X-Y=bad\nnot a pair\nDW_TOKEN_SET=from-file\n"
        "DW_TOKEN_EMPTY="
    )

    def test_env_file_against_bash(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write(self.ENV_FILE)
        keys = ("DW_TOKEN", "DW_TOKEN_LEM", "DW_TOKEN_MINI_AI", "DW_TOKEN_SET", "DW_TOKEN_EMPTY", "PROVIDER")
        clean = {k: v for k, v in os.environ.items() if k not in keys}
        want = bash_words(
            "load_env_file; W=(" + " ".join(f'"${{{k}-unset}}"' for k in keys) + ")",
            keys,
            HARNEST_ENV_FILE=f.name,
            DW_TOKEN_SET="from-env",
        )
        env, warned = dict(clean, DW_TOKEN_SET="from-env"), []
        load_env_file(f.name, env, warned.append)
        self.assertEqual(want, [env.get(k, "unset") for k in keys])
        self.assertEqual(["plain=with=equals", "quoted lem", "mini", "from-env", "", "unset"], want)
        self.assertEqual(2, len(warned))
        os.unlink(f.name)

    def test_token_var_matches_profile(self):
        p = load()
        for s in p.servers:  # the name providers.sh derives is the one the profile names
            self.assertEqual(bash("token_var", DW_TARGET=s.name).strip(), s.token_env)


class Suite(unittest.TestCase):
    def test_helpers(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d, "regression-suite-x.md")
            f.write_text(
                "# x\n### S-F001 — a\nrunner: script\n### S-F002 — b\nrunner: script \n### bad heading\n"
                "runner: script\n### C-P010 c\n"
            )
            Path(d, "cases").mkdir()
            Path(d, "cases", "S-F001.json").write_text("{}")
            self.assertEqual(["S-F001", "S-F002", "C-P010"], suite.case_ids(f))
            self.assertEqual(["S-F001"], suite.script_cases(f, Path(d, "cases")))
            self.assertEqual("regression-x", suite.workspace_for_suite_file(f))
            self.assertEqual("regression-mine", suite.workspace_for_suite_file("/a/mine.md"))
        p = load()
        self.assertEqual(
            ["regression-suite-*.md", "regression-perf", "regression-results"], suite.commit_paths(p.server("lem"))
        )
        self.assertEqual(
            ["regression-perf/mini-ai", "regression-results/mini-ai"], suite.commit_paths(p.server("mini-ai"))
        )

    def test_commit_warns_on_removed_lines(self):
        with tempfile.TemporaryDirectory() as d:
            g = lambda *a: subprocess.run(["git", "-C", d, *a], capture_output=True, check=True)
            g("init", "-q")
            Path(d, "regression-suite-a.md").write_text("one\ntwo\npending: #12\n")
            Path(d, "other.md").write_text("x\n")
            Path(d, "regression-perf").mkdir()
            Path(d, "regression-perf", "S-P001.jsonl").write_text("{}\n")
            g("add", "-A")
            g("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "seed")
            Path(d, "regression-suite-a.md").write_text("one\n")
            Path(d, "other.md").write_text("y\n")
            said = []
            env = dict(
                os.environ,
                GIT_AUTHOR_NAME="t",
                GIT_AUTHOR_EMAIL="t@t",
                GIT_COMMITTER_NAME="t",
                GIT_COMMITTER_EMAIL="t@t",
            )
            old = os.environ.copy()
            os.environ.update(env)
            try:
                suite.commit_changes(d, d, ["regression-suite-*.md", "regression-perf"], "msg", "N", "n@x", said.append)
            finally:
                os.environ.clear()
                os.environ.update(old)
            self.assertEqual("msg", said[0])
            self.assertIn("regression-suite-a.md(-1) - cases", said[1])
            log = subprocess.run(["git", "-C", d, "log", "-1", "--format=%B"], capture_output=True, text=True).stdout
            self.assertIn("Co-Authored-By: N <n@x>", log)
            status = subprocess.run(["git", "-C", d, "status", "--porcelain"], capture_output=True, text=True).stdout
            self.assertEqual(" M other.md\n", status)


if __name__ == "__main__":
    unittest.main()
