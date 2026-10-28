"""The regression driver in Python (R8): run-regression.sh, ported.

    python3 -m harness.drivers.regression [level] [suite-file]

Same levels, knobs, log lines, state files and prompts as run-regression.sh,
whose header documents them; this module keeps its behaviour and says only
where the port differs. Until the live side-by-side run (R8 plan, phase 4)
the bash driver stays the one cron, the nightly pass and run-release.sh
call; this one is run by hand.

Where it differs:
- the session runs in its own process group, and stopping the driver
  stops the session (harness/session.py);
- tool-result sizes are counted on the decoded text: jq 1.7.1's raw-input
  reader splits a multibyte character at a buffer boundary now and then,
  and the bash renderer counted it twice.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

from .. import REPO, deploy, lock, outcome, prompts, providers, requirements, results, session, suite
from ..gitops import refresh_plugin_tree
from ..log import Log, err, ts
from ..profile import ProfileError, load, resolve_token, resolve_url
from ..stream import resolved_model


class Abort(Exception):
    """Stop the run with this exit status; the message has been printed."""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


def env(name, default=""):
    """${NAME:-default}: an empty value takes the default too."""
    return os.environ.get(name) or default


def system_prompt(kind, out, server, health, url):
    """The role prompt for a <kind> session, with a secondary server's own
    rules (agents/regression/target.md) appended last, so they read as the
    last word. Raises prompts.PromptError."""
    prompts.role_prompt("regression", kind, out)
    if not server.primary:
        note = prompts.target_note(
            "regression",
            {
                "TARGET": server.name,
                "SERVER": health,
                "URL": url,
                "DEPLOY": deploy.deploy_cmd(server),
                "HOST": server.host,
                "SERVER_DIR": server.dir,
            },
        )
        with open(out, "a", encoding="utf-8") as f:
            f.write("\n" + note)
    return out


def session_prompt(
    ticket_repo, suite_file, level, workspace, server_text, head, instructions, provider, model, secondary
):
    """The prompt every regression session gets: the run's specifics, then
    the kind's instructions, then the runtime note."""
    target_clause = (
        " The Target section at the end of your system prompt applies to this whole run." if secondary else ""
    )
    return (
        f"Tickets are GitHub Issues on {ticket_repo}; use the gh CLI to file/comment on them. "
        "Your role instructions for this kind of session are in your system prompt; follow them exactly, "
        f"with these specifics: suite file is {suite_file}; level is '{level}'; workspace is {workspace}; "
        f"{server_text} is running {head or 'unknown'} - name that commit in anything you file or comment."
        f"{target_clause} {instructions} Then stop.\n\n"
        + prompts.runtime_note("regression", provider, model, secondary)
    )


def chunk_instructions(chunk, text):
    """<text>: suite.case_text for <chunk>, which the session reads in place of the suite file."""
    return (
        "This is one chunk of a chunked run: this session exercises ONLY these cases, in "
        f"this order: {' '.join(chunk)}. The Fixtures section and these cases' full text follow; "
        "do not read the suite file for them (read it only if a case points elsewhere in it). "
        "Skip the final sweep; a separate session does it after every case has run."
        f"\n\n{text}\n\n(End of the suite text.)"
    )


def sweep_instructions(workspace, script_note="", fixtures=""):
    """<fixtures>: suite.case_text with no cases: the Fixtures section, what the sweep keeps."""
    return (
        "This is the final sweep of a chunked run: every case was already exercised in "
        f"earlier sessions. Do only the final sweep against the {workspace} workspace. The "
        "suite file's Fixtures section follows; do not read the suite file for it, nor the "
        f"cases.{script_note}\n\n{fixtures}\n\n(End of the suite text.)"
    )


class Regression:
    def __init__(self, argv):
        self.profile = load()
        self.level = argv[0] if argv else "smoke"
        self.override = argv[1] if len(argv) > 1 else ""
        self.target = env("DW_TARGET", self.profile.servers[0].name)
        self.ticket_repo = env("TICKET_REPO", self.profile.get("ticket_repo"))
        self.logs = REPO / "logs"
        self.provider = env("PROVIDER", "anthropic")
        self.model = env("REGRESSION_MODEL", "claude-sonnet-5-5")
        self.model_provider = env("REGRESSION_PROVIDER", self.provider)
        self.fallback = env("FALLBACK_MODEL")
        self.cases_per_session = env("CASES_PER_SESSION")
        self.cases = env("REGRESSION_CASES", "").split()  # empty: every case
        self.budget = env("REGRESSION_BUDGET_USD", "6")
        self.autocompact = env("AUTOCOMPACT_TOKENS", "120000")
        self.mcp_name = self.profile.get("mcp.name", "dw")
        self.run_specs = self._run_specs()

    # --- startup, in run-regression.sh's order

    def _run_specs(self):
        """[(level, override)]: a level's prerequisite runs first, and the
        override applies only to the level named on the command line."""
        names = [lv.name for lv in self.profile.levels]
        if self.level == "all":
            if self.override:
                err(
                    "a suite-file override is ambiguous with level 'all' — run one level at a time to override its file"
                )
                raise Abort(1)
            return [(n, "") for n in names]
        lv = self.profile.level(self.level)
        if lv is None:
            err(f"unknown level '{self.level}' (expected: {', '.join(names)}, all)")
            raise Abort(1)
        # Named cases run in the level named alone: its prerequisite's file
        # would match its own cases of the same ID prefix.
        pre = [(lv.implies, "")] if lv.implies and not self.cases else []
        return pre + [(lv.name, self.override)]

    def start(self):
        try:
            self.server = self.profile.server(self.target)
        except ProfileError:
            self.server = None
        clone_sfx = self.server.clone_suffix if self.server else f"-{self.target}"
        # A regression-only server (no loop) has no agents' clone of its own:
        # its plugin worktree comes from the primary's.
        source_sfx = clone_sfx if not self.server or self.server.loop else ""
        self.source_dir = Path(os.path.expanduser(env("SOURCE_DIR", self.profile.get("clones.source") + source_sfx)))
        self.plugin_tree = Path(os.path.expanduser(env("PLUGIN_TREE", self.profile.get("clones.plugin") + clone_sfx)))
        if not self.source_dir.is_dir():
            err(f"SOURCE_DIR not found: {self.source_dir}")
            raise Abort(1)
        for tool in ("claude", "gh"):
            if not shutil.which(tool):
                err(f"{tool} CLI not on PATH")
                raise Abort(1)
        if subprocess.run(["gh", "auth", "status"], capture_output=True).returncode != 0:
            err("gh CLI not authenticated")
            raise Abort(1)
        self.logs.mkdir(exist_ok=True)
        if self.server is None:
            err(f"DW_TARGET must be one of: {' '.join(s.name for s in self.profile.servers)} (got '{self.target}')")
            raise Abort(1)
        sfx = self.server.suffix
        self.log = Log(self.logs / f"loop{sfx}.log")
        try:
            self.url = resolve_url(self.server, env("DW_URL"))
            self.token = resolve_token(self.server)
        except ProfileError as e:
            err(str(e))
            raise Abort(1) from None
        self.logname = f"regression{sfx}"
        self.rpfx = "regression" + (f"-{self.target}" if sfx else "")
        self.server_text, self.health = "lem", ""
        if not self.server.primary:
            try:
                self.health = deploy.preflight(self.server, self.url, self.token)
            except deploy.PreflightError as e:
                err(str(e))
                raise Abort(1) from None
            self.server_text = f"the {self.target} server ({self.health})"
            if self.level == "all":
                self.run_specs = [(n, "") for n in self.server.regression_all]
            # What the agent files must carry this label, and gh refuses one
            # that doesn't exist.
            subprocess.run(
                [
                    "gh",
                    "label",
                    "create",
                    f"target:{self.target}",
                    "--repo",
                    self.ticket_repo,
                    "--force",
                    "--color",
                    "5319e7",
                    "--description",
                    f"Found against a non-lem server (DW_TARGET={self.target}); Don triages",
                ],
                capture_output=True,
            )
            (REPO / self.profile.get("suite.perf_dir", "regression-perf") / self.target).mkdir(
                parents=True, exist_ok=True
            )
        # Each case's outcome per session, split by server as regression-perf/ is.
        self.results_dir = results.results_dir(
            REPO / self.profile.get("suite.results_dir", "regression-results"), self.server
        )
        # guard.py reads these.
        self.session_env = {
            "HARNEST_TARGET": self.target,
            "HARNEST_ROLE": "regression",
            "HARNEST_TICKET_REPO": self.ticket_repo,
        }
        lock.acquire(str(self.logs / f".driver.lock{sfx}"), "run-regression", self.log.say)
        self.last = self.logs / f".last-session.{self.logname}"
        plugin_dir = self.plugin_tree / self.profile.get("clones.plugin_subdir", "plugins/dw")
        if (
            refresh_plugin_tree(self.source_dir, self.plugin_tree, self.profile.get("integration_branch", "develop"))
            is None
        ):
            err(f"could not create/refresh the plugin worktree {self.plugin_tree} from {self.source_dir}")
            raise Abort(1)
        if not plugin_dir.is_dir():
            err(f"dw plugin source not found: {plugin_dir}")
            raise Abort(1)
        effort = env("REGRESSION_EFFORT", env("EFFORT", "medium"))
        try:
            self.model_env = providers.resolve_model_env(self.model_provider, self.model)
            self.session_flags = providers.session_flags(
                self.model_provider, self.model, effort, self.budget, self.fallback, self.autocompact
            )
        except providers.ProviderError as e:
            err(str(e))
            raise Abort(1) from None
        if not self.cases_per_session:
            ctx = self.model_env.context_tokens
            self.cases_per_session = "3" if ctx and int(ctx) < 120000 else "8"
        if not self.cases_per_session.isdigit():
            err(f"CASES_PER_SESSION must be a whole number, got '{self.cases_per_session}'")
            raise Abort(1)
        self.cases_per_session = int(self.cases_per_session)
        skip = os.environ.get("TARGET_SKIP_CASES")
        self.skip_cases = skip.split() if skip is not None else list(self.server.regression_skip_cases)
        self.flags = [
            "--mcp-config",
            session.mcp_config(self.mcp_name, self.url, self.token),
            "--strict-mcp-config",
            "--plugin-dir",
            str(plugin_dir),
            *session.ISOLATION_FLAGS,
            "--tools",
            session.CONSUMER_TOOLS,
            *session.consumer_permission_flags(self.mcp_name, self.profile.get("mcp.deny_tools", ())),
        ]

    # --- sessions

    def run_session(self, level, suite_file, workspace, tag, kind, instructions, head, cases=()):
        prompt_file = self.logs / f".prompt.{self.logname}.{kind}.md"
        try:
            system_prompt(kind, prompt_file, self.server, self.health, self.url)
        except prompts.PromptError:
            self.log.say(f"[{self.rpfx}:{level}{tag}] no role prompt for '{kind}'")
            return
        prompt = session_prompt(
            self.ticket_repo,
            suite_file,
            level,
            workspace,
            self.server_text,
            head,
            instructions,
            self.model_provider,
            self.model,
            not self.server.primary,
        )
        session.run(
            f"{self.rpfx}:{level}{tag}",
            self.logname,
            str(REPO),
            prompt_file,
            prompt,
            [*self.session_flags, *self.flags],
            model_env=self.model_env,
            session_env=self.session_env,
            logs=str(self.logs),
            last=str(self.last),
            log=self.log,
        )
        skips, differs = outcome.regression_counts(self.last)
        self.level_skips += skips
        self.level_differs += differs
        # Every case this session was handed or answered for: its outcome, one
        # line each (harness/results.py). A lost line is not worth the run.
        label = f"{self.rpfx}:{level}{tag}"
        try:
            results.record_session(
                self.results_dir,
                self.target,
                level,
                label,
                head or "unknown",
                resolved_model(self.logs / f"{self.logname}.jsonl", self.model),
                self.last.read_text(encoding="utf-8", errors="replace"),
                cases,
            )
        except OSError:
            self.log.say(f"[{label}] could not record its results in {self.results_dir}")

    def script_report(self, ids):
        runner = REPO / self.profile.get("suite.contract_runner", "contract/run.py")
        p = subprocess.run(
            ["python3", str(runner), "--url", self.url, *ids],
            env={**os.environ, "DW_TOKEN": self.token},  # not argv, where ps shows it
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        report = p.stdout.rstrip("\n")
        try:
            r = json.loads(report)
            summary = (
                f"{_jq_num(r.get('passed'))} passed, {_jq_num(r.get('failed'))} failed, "
                f"{_jq_num(r.get('errors'))} errored" + (f" - {r['error']}" if r.get("error") else "")
            )
        except (ValueError, AttributeError):
            summary = "report unreadable"
        return report, summary

    def suite_file(self, level, override):
        if override:
            return Path(override) if override.startswith("/") else REPO / override
        return REPO / self.profile.level(level).file

    def check_cases(self):
        """Every REGRESSION_CASES ID is in one of this run's suite files."""
        found = set()
        for level, override in self.run_specs:
            try:
                found.update(suite.case_ids(self.suite_file(level, override)))
            except (OSError, ValueError):
                pass  # its level says so when it runs
        for cid in self.cases:
            if cid not in found:
                err(f"REGRESSION_CASES: {cid} is in none of this run's suite files")
                raise Abort(1)

    def run_level(self, level, override):
        suite_file = self.suite_file(level, override)
        if not suite_file.is_file():
            err(f"suite file not found: {suite_file}")
            raise Abort(1)
        workspace = suite.workspace_for_suite_file(suite_file)
        sfx = self.server.suffix
        if not suite.has_cases(suite_file):
            self.log.say(f"{ts()} {level}{sfx}: {suite_file.name} has no cases yet, skipping")
            return
        chosen = None
        if self.cases:
            try:
                chosen = requirements.select(suite_file, self.cases)
            except (OSError, ValueError):
                self.log.say(f"[{self.rpfx}:{level}] could not read case ids from {suite_file}")
                raise Abort(1) from None
            if not chosen:
                self.log.say(f"{ts()} {level}{sfx}: none of REGRESSION_CASES in {suite_file.name}, skipping")
                return

        script_ids = suite.script_cases(suite_file, REPO / self.profile.get("suite.contract_cases", "contract/cases"))
        if chosen is not None:
            script_ids = [i for i in script_ids if i in chosen]
        script_note = ""
        if script_ids:
            report, summary = self.script_report(script_ids)
            self.log.say(f"[{self.rpfx}:{level}] script cases: {summary}")
            script_note = (
                "\n\nThese cases ran as scripts before this session (contract/run.py, a plain MCP client; see "
                f"'runner: script' on each): {' '.join(script_ids)}. Do not execute them. Their report:\n{report}\n"
                "For each case whose status is fail or error, report it ('Reporting a failure' in the role "
                "instructions) exactly as for a case you ran yourself, quoting its failures; a pass needs nothing. "
                "An error with 'server unreachable' is the MCP-unreachable case, not a per-case failure."
            )

        head = deploy.deployed_head(self.server)
        # Another server's header and session lines carry its tag
        # (smoke.mini-ai), so the curator's per-chunk cost table, which reads
        # lem's runs out of loop.log, neither counts nor mixes them.
        tag = f"{level}{sfx}"
        self.level_skips = self.level_differs = 0
        # read first, and checked: an empty list from a file with headings would run nothing and say nothing
        try:
            ids_in_file = chosen if chosen is not None else suite.case_ids(suite_file)
        except (OSError, ValueError):
            ids_in_file = []
        if not ids_in_file:
            self.log.say(f"[{self.rpfx}:{level}] could not read case ids from {suite_file}")
            raise Abort(1)
        held = []
        if sfx:
            for cid in self.skip_cases:
                if cid not in ids_in_file:
                    continue
                held.append(cid)
                self.level_skips += 1
                self.log.say(
                    f"[{self.rpfx}:{level}] REGRESSION-SKIP: {cid} memory (TARGET_SKIP_CASES: not run on this server)"
                )
        held_clause = (
            (
                " Never run these cases on this server, whatever the suite says; the driver already counted "
                "them as skipped:" + "".join(f" {c}" for c in held) + "."
            )
            if held
            else ""
        )
        header = (
            f"=== {ts()} regression run ({self.model_env.label}, level={tag}, suite={suite_file}, "
            f"workspace={workspace}, target={self.target}, head={head}"
        )
        ids = [i for i in ids_in_file if i not in script_ids and i not in held]
        if self.cases_per_session == 0:
            self.log.say(header + ") ===")
            self.run_session(
                level,
                suite_file,
                workspace,
                "",
                "whole",
                f"Exercise every case in the suite file against the {workspace} workspace, file or "
                "comment on issues for failures and performance regressions, add any cases worth "
                f"adding, then do the final sweep.{held_clause}{script_note}",
                head,
                ids,
            )
        else:
            total, n = len(ids), self.cases_per_session
            nchunks = (total + n - 1) // n
            self.log.say(header + f", {total} cases in sessions of {n}) ===")
            session_no = 0
            for start in range(0, total, n):
                chunk = ids[start : start + n]
                session_no += 1
                self.log.say(f"--- {ts()} {tag} session {session_no} of {nchunks}: {' '.join(chunk)} ---")
                self.run_session(
                    level,
                    suite_file,
                    workspace,
                    f".{session_no} of {nchunks}",
                    "chunk",
                    chunk_instructions(chunk, suite.case_text(suite_file, chunk, level)),
                    head,
                    chunk,
                )
                if outcome.aborted(self.last):
                    self.log.say(
                        f"[{self.rpfx}:{level}] session {session_no} aborted (MCP unreachable); "
                        "skipping the rest of this level and the sweep"
                    )
                    break
            if not outcome.aborted(self.last):
                self.log.say(f"--- {ts()} {tag} session {session_no + 1}: final sweep ---")
                self.run_session(
                    level,
                    suite_file,
                    workspace,
                    ".sweep",
                    "sweep",
                    sweep_instructions(workspace, script_note, suite.case_text(suite_file, [], level)),
                    head,
                )

        if sfx:
            self.log.say(
                f"[{self.rpfx}:{level}] {self.level_skips} case(s) skipped, {self.level_differs} expectation(s) "
                "differ on this server (REGRESSION-SKIP / REGRESSION-DIFFERS lines above)"
            )
        name, email = providers.co_author_for(
            self.model_provider, resolved_model(self.logs / f"{self.logname}.jsonl", self.model)
        )
        target_clause = f", target {self.target}" if sfx else ""
        self.commit(
            f"regression: update {level} suite from {ts()} run ({self.model_env.label}{target_clause})", name, email
        )
        if outcome.aborted(self.last):
            self.log.say(f"[{self.rpfx}] stopping: MCP unreachable")
            raise Abort(1)

    def commit(self, msg, name, email):
        suite.commit_changes(
            REPO,
            str(self.logs),
            suite.commit_paths(
                self.server,
                self.profile.get("suite.perf_dir", "regression-perf"),
                self.profile.get("suite.results_dir", "regression-results"),
            ),
            msg,
            name,
            email,
            self.log.say,
        )

    def main(self):
        self.check_cases()
        # Fallback only: anything still dirty is of unknown origin (a hand
        # edit between runs, or a cycle that died before committing), so it
        # is committed under a neutral name, never the regression model's.
        # On another server this would take lem's files, which a run there
        # never writes, and the loop's tester may be mid-edit in them.
        if self.server.primary:
            self.commit(
                "regression: capture suite edits of unknown origin made outside a regression run",
                "unknown (edited outside a regression run)",
                "noreply@localhost",
            )
        for level, override in self.run_specs:
            self.run_level(level, override)


def _jq_num(v):
    """`.x // 0` interpolated."""
    if v is None or v is False:
        return "0"
    return str(v) if not isinstance(v, float) or not v.is_integer() else str(int(v))


def main(argv=None):
    # A stopped driver runs its exit handlers (the lock) and takes its
    # session down with it (harness/session.py).
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    try:
        r = Regression(sys.argv[1:] if argv is None else argv)
        r.start()
        r.main()
    except Abort as a:
        return a.code
    except ProfileError as e:
        err(str(e))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
