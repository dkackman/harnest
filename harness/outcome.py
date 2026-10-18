"""What a session's rendered log says about how it ended: providers.sh's
session_died / session_ran / session_ok and sleep_if_rate_limited, plus
run-regression.sh's REGRESSION-* lines. They read the rendered text, not the
events, because that file ($LAST_SESSION) is the contract both the bash and
the Python drivers write, and a died session has no events to read.
"""

import re
import time

_SKIP_RE = re.compile(r"^[-*` ]*REGRESSION-SKIP:[ \t\f\v]*[A-Z]+-[A-Z][0-9]", re.M)
_DIFFERS_RE = re.compile(r"^[-*` ]*REGRESSION-DIFFERS:[ \t\f\v]*[A-Z]+-[A-Z][0-9]", re.M)


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def _has_line(text, prefix):
    return any(line.startswith(prefix) for line in text.splitlines())


def died(path):
    """Ended without a final `usage:` line: the claude process went away
    before its result event. A budget cut-off still has one."""
    t = _read(path)
    return t is not None and not _has_line(t, "usage: ")


def ran(path):
    """Reached its result and was not turned away by a rejected rate limit."""
    t = _read(path)
    return t is not None and _has_line(t, "usage: ") and "rate-limit: status=rejected" not in t


def ok(path):
    """Ran to its own end: a usage line, no non-success result, no rejection."""
    t = _read(path)
    return (
        t is not None
        and _has_line(t, "usage: ")
        and not _has_line(t, "result: ")
        and "rate-limit: status=rejected" not in t
    )


def aborted(path):
    """The regression role prompt's abort line: the MCP server is unreachable."""
    t = _read(path)
    return t is not None and _has_line(t, "REGRESSION-ABORT:")


def regression_counts(path):
    """(skips, differs) lines the agent listed, each naming a case ID."""
    t = _read(path) or ""
    return len(_SKIP_RE.findall(t)), len(_DIFFERS_RE.findall(t))


def rejected_until(path):
    """The resets_epoch of the last rejected rate limit in the log, or None."""
    t = _read(path)
    if not t:
        return None
    last = None
    for line in t.splitlines():
        if "rate-limit: status=rejected" in line:
            last = line
    if last is None:
        return None
    m = re.search(r"resets_epoch=([0-9]+)", last)
    return int(m.group(1)) if m else None


def sleep_if_rate_limited(path, say, now=time.time, sleep=time.sleep):
    """A session started while the account's limit is rejected returns in
    under a second at $0; sleep until the reset it named, plus a minute,
    instead of relaunching (37 such sessions spun on 2026-09-21)."""
    epoch = rejected_until(path)
    if epoch is None:
        return
    wait = epoch + 60 - int(now())
    if wait > 0:
        say(
            f"[loop] rate limit rejected; sleeping {wait}s until {time.strftime('%H:%M:%S', time.localtime(epoch))} + 60s"
        )
        sleep(wait)
