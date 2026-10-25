"""One claude session, the way every driver runs one: a port of
providers.sh's run_claude_session, plus the per-role flag tables it is
handed (CONSUMER_PERMISSION_FLAGS and friends).

The argv is the bash drivers' argv, word for word (`claude -p <prompt>
--append-system-prompt-file <file> --output-format stream-json --verbose
<session flags> <role flags>`), so the offline stub and every flag
assertion keep working; tests/py/test_session.py checks it against the
bash it replaces. The Agent SDK would be a second implementation of
run() behind this module (R8 phase 7), not a change to its callers.

Unlike the bash, the session runs in its own process group, and a driver
that is stopped takes the whole group down with it: a SIGTERM to a bash
driver waits on its foreground pipeline, and a `claude -p` it started could
outlive it, reparented.
"""

import atexit
import json
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time

from . import REPO, outcome
from .log import ts
from .stream import Renderer

HOOKS = REPO / "agent-settings" / "hooks"
STREAM_FLAGS = ["--output-format", "stream-json", "--verbose"]
ISOLATION_FLAGS = ["--setting-sources", "project,local"]
CONSUMER_TOOLS = "Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite"


def base_env(environ=None):
    """What sourcing providers.sh exports to every driver's children."""
    e = dict(os.environ if environ is None else environ)
    e["HARNEST_HOOKS"] = str(HOOKS)
    e["HARNEST_ROOT"] = str(REPO)
    e["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
    # ${X:-default}: an empty value takes the default too.
    for k, default in (
        ("MCP_TOOL_TIMEOUT", "1900000"),
        ("CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT", "1900000"),
        ("CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS", "1800000"),
    ):
        e[k] = e.get(k) or default
    # providers.sh resets SUITE_EDITS on every source; only run-loop.sh sets it.
    e["SUITE_EDITS"] = "0"
    return e


def guard_settings(role):
    """The --settings JSON installing guard.py for <role>, as jq -nc prints
    it. `$HARNEST_HOOKS` stays literal: the hook's shell expands it."""
    matcher = "Bash|Edit|Write" if role == "consumer" else "Bash"
    return json.dumps(
        {
            "hooks": {
                "PreToolUse": [
                    {
                        "matcher": matcher,
                        "hooks": [
                            {"type": "command", "command": f'python3 "$HARNEST_HOOKS/guard.py" {role}', "timeout": 30}
                        ],
                    }
                ]
            }
        },
        separators=(",", ":"),
    )


def consumer_permission_flags(mcp_name="dw", deny=("delete_model", "update_diffusers")):
    """CONSUMER_PERMISSION_FLAGS: the tester's and the regression agent's
    fence (providers.sh says why each entry is there)."""
    return [
        "--settings",
        guard_settings("consumer"),
        "--permission-mode",
        "dontAsk",
        "--allowedTools",
        f"mcp__{mcp_name}__*",
        "ToolSearch",
        "Skill",
        "TodoWrite",
        "Read",
        "Glob",
        "Grep",
        "Edit",
        "Write",
        "Bash(gh issue *)",
        "Bash(date *)",
        "Bash(file *)",
        "Bash(git log *)",
        "Bash(git status*)",
        "Bash(git diff *)",
        "Bash(git show *)",
        "Bash(./scripts/file-advisory.sh *)",
        'Bash(python3 -I "$HARNEST_ROOT"/scripts/perf-check.py *)',
        "--disallowedTools",
        *[f"mcp__{mcp_name}__{t}" for t in deny],
        "Write(scripts/**)",
        "Edit(scripts/**)",
    ]


def mcp_config(name, url, token):
    """--mcp-config for one HTTP MCP server with a Bearer token: the path of a
    0600 file, logs/.mcp.<pid>.<random>.json (one per call: a fleet builds one
    per server in a single process). The token is in the file, never in argv,
    where ps shows it; mkstemp creates it O_EXCL, and it is removed at exit."""
    logs = REPO / "logs"
    logs.mkdir(exist_ok=True)
    fd, path = tempfile.mkstemp(dir=logs, prefix=".mcp.%d." % os.getpid(), suffix=".json")
    doc = {"mcpServers": {name: {"type": "http", "url": url, "headers": {"Authorization": "Bearer " + token}}}}
    with os.fdopen(fd, "w") as f:
        f.write(json.dumps(doc, separators=(",", ":")) + "\n")
    atexit.register(_rm_quiet, path)
    return path


def _rm_quiet(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def _kill_group(proc):
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        return
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        proc.wait()


# Every claude process a session in this driver has running. Threads run
# sessions in parallel (the fleet's lanes), and only the main thread gets
# SIGTERM: kill_all() at exit takes every one of them down, not just the
# main thread's.
_LIVE = set()
_LIVE_LOCK = threading.Lock()


def kill_all():
    with _LIVE_LOCK:
        procs = list(_LIVE)
    for p in procs:
        if p.poll() is None:
            _kill_group(p)


atexit.register(kill_all)


class Watchdog:
    """Kills a session that has gone quiet, so the driver's own recovery
    (sleep through a rejected rate limit, retry a died session) runs. A
    session can stall without exiting: on 2026-10-18 a fleet lane's session
    got a rejected five-hour limit mid-run (overage=true) and sat silent,
    holding the run, until it was killed by hand. How long is too quiet
    depends on what the session is doing:
    - after a rejected rate limit: SESSION_REJECTED_STALL_SECS (120);
    - with a tool call in flight: SESSION_TOOL_STALL_SECS (2400), since
      dw's wait_for_job blocks up to 1800 s with nothing to say;
    - otherwise (the model's own turn): SESSION_STALL_SECS (900).
    0 turns a limit off."""

    def __init__(self, proc, say, clock=time.monotonic, limits=None, kill=None, watch=True):
        self.proc, self.say, self.clock = proc, say, clock
        self.kill = kill or _kill_group
        self.last = clock()
        self.open_tools = 0
        self.rejected = False
        self.killed = None
        self.limits = limits or {
            k: int(os.environ.get(k) or d)
            for k, d in (
                ("SESSION_STALL_SECS", 900),
                ("SESSION_TOOL_STALL_SECS", 2400),
                ("SESSION_REJECTED_STALL_SECS", 120),
            )
        }
        self.stop = threading.Event()
        if watch:
            threading.Thread(target=self._watch, daemon=True).start()

    def saw(self, line):
        self.last = self.clock()
        if line.startswith("> "):
            self.open_tools += 1
        elif line.startswith("< ") and self.open_tools:
            self.open_tools -= 1
        elif line.startswith("rate-limit: status=rejected"):
            self.rejected = True
        elif line.startswith("· ctx="):
            self.rejected = False  # the model answered after all

    def limit(self):
        if self.rejected:
            return "SESSION_REJECTED_STALL_SECS", "after a rejected rate limit"
        if self.open_tools:
            return "SESSION_TOOL_STALL_SECS", "with a tool call in flight"
        return "SESSION_STALL_SECS", "on the model's turn"

    def check(self):
        """Kills the session when it has been quiet too long; True if it did."""
        knob, what = self.limit()
        secs = self.limits[knob]
        quiet = self.clock() - self.last
        if not secs or quiet < secs or self.proc.poll() is not None:
            return False
        self.killed = f"no output for {int(quiet)}s {what} ({knob}={secs}); stopping it"
        self.say(self.killed)
        self.kill(self.proc)
        return True

    def _watch(self):
        while not self.stop.wait(5):
            if self.check():
                return


def _attempt(argv, cwd, env, label, jsonl, logfile, last, log, on_line=None):
    """One claude process: raw events to <jsonl>, the rendering to
    <logfile> and <last>, and prefixed [label] to the loop log and stdout.
    <on_line>, if given, sees each rendered line as it arrives (the fleet's
    live progress). Returns claude's exit status."""
    r = Renderer()
    prefix = f"[{label}] "
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    with _LIVE_LOCK:
        _LIVE.add(proc)
    dog = Watchdog(proc, lambda m: log.say(f"[{label}] {m}"))
    try:
        with (
            open(jsonl, "ab") as jf,
            open(logfile, "a", encoding="utf-8") as lf,
            open(last, "a", encoding="utf-8") as sf,
        ):
            for raw in proc.stdout:
                jf.write(raw)
                jf.flush()
                line = raw.decode("utf-8", errors="replace")
                if line.endswith("\n"):
                    line = line[:-1]
                for out in r.feed(line):
                    dog.saw(out)
                    lf.write(out + "\n")
                    sf.write(out + "\n")
                    lf.flush()
                    sf.flush()
                    tagged = "".join(prefix + part + "\n" for part in out.split("\n"))
                    log.append(tagged)
                    sys.stdout.write(tagged)
                    sys.stdout.flush()
                    if on_line:
                        on_line(out)
        return proc.wait()
    finally:
        dog.stop.set()
        if proc.poll() is None:
            _kill_group(proc)
        with _LIVE_LOCK:
            _LIVE.discard(proc)


def stop_on_sigterm():
    """SIGTERM becomes a normal exit (status 143), so the finally that
    takes a running session's process group down with the driver runs.
    Python's default SIGTERM ends the process without it, and the session,
    in its own group, would outlive the driver: a stopped requirements run
    left one going on 2026-10-18. Called by run(); a handler a driver set
    itself is left alone."""
    try:
        if signal.getsignal(signal.SIGTERM) is signal.SIG_DFL:
            signal.signal(signal.SIGTERM, _sigterm)
    except ValueError:  # not the main thread: the caller owns signals
        pass


def _sigterm(*_):
    sys.exit(143)


def run(
    label,
    logname,
    cwd,
    prompt_file,
    prompt,
    flags,
    *,
    model_env,
    session_env,
    logs,
    last,
    log,
    header=None,
    retry_pause=None,
    sleep=time.sleep,
    on_line=None,
    clock=time.time,
):
    """run_claude_session: one fresh `claude -p` session, retried once if it
    died before its result, asleep through a rejected rate limit. Never
    raises on the session's own failure; the outcome is read from <last>
    (outcome.ok / ran / died), as the bash callers do. Returns each
    attempt's (start, end) by <clock>: the retry pause and a rate-limit
    sleep fall between them, in neither."""
    stop_on_sigterm()
    if retry_pause is None:
        retry_pause = int(os.environ.get("SESSION_RETRY_PAUSE_SECS") or 30)
    argv = ["claude", "-p", prompt, "--append-system-prompt-file", str(prompt_file), *STREAM_FLAGS, *flags]
    env = model_env.apply(base_env())
    env.update(session_env)
    attempts = []
    for attempt in (1, 2):
        open(last, "w").close()
        log.say(f"=== {ts()} {header or label} ({model_env.label}){' retry' if attempt > 1 else ''} ===")
        start = clock()
        try:
            rc = _attempt(
                argv,
                cwd,
                env,
                label,
                os.path.join(logs, f"{logname}.jsonl"),
                os.path.join(logs, f"{logname}.log"),
                last,
                log,
                on_line,
            )
        except OSError as e:
            log.say(f"[{label}] {e}")
            rc = 1
        attempts.append((start, clock()))
        if rc != 0:
            log.say(f"[{label}] session failed, continuing")
        if outcome.sleep_if_rate_limited(last, log.say):
            if attempt == 2:
                break
            log.say(f"[{label}] the rate limit turned the session away; running it again")
            continue
        if not outcome.died(last) or attempt == 2:
            break
        log.say(f"[{label}] session ended without a result; retrying once in {retry_pause}s")
        sleep(retry_pause)
    return attempts
