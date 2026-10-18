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
        "--disallowedTools",
        *[f"mcp__{mcp_name}__{t}" for t in deny],
    ]


def mcp_config(name, url, token):
    """--mcp-config for one HTTP MCP server with a Bearer token, as the bash
    interpolates it."""
    return '{"mcpServers":{"%s":{"type":"http","url":"%s","headers":{"Authorization":"Bearer %s"}}}}' % (
        name,
        url,
        token,
    )


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
):
    """run_claude_session: one fresh `claude -p` session, retried once if it
    died before its result, asleep through a rejected rate limit. Never
    raises on the session's own failure; the outcome is read from <last>
    (outcome.ok / ran / died), as the bash callers do."""
    stop_on_sigterm()
    if retry_pause is None:
        retry_pause = int(os.environ.get("SESSION_RETRY_PAUSE_SECS") or 30)
    argv = ["claude", "-p", prompt, "--append-system-prompt-file", str(prompt_file), *STREAM_FLAGS, *flags]
    env = model_env.apply(base_env())
    env.update(session_env)
    for attempt in (1, 2):
        open(last, "w").close()
        log.say(f"=== {ts()} {header or label} ({model_env.label}){' retry' if attempt > 1 else ''} ===")
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
        if rc != 0:
            log.say(f"[{label}] session failed, continuing")
        outcome.sleep_if_rate_limited(last, log.say)
        if not outcome.died(last) or attempt == 2:
            break
        log.say(f"[{label}] session ended without a result; retrying once in {retry_pause}s")
        sleep(retry_pause)
