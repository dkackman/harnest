#!/usr/bin/env python3
"""Sign and verify run-release.sh's markers on the release issue (harnest#140).

    python3 lib/release_mac.py sign <message>             print the MAC, making the key if missing
    python3 lib/release_mac.py ledger <issue> <marker>    record a marker run-release.sh posted
    python3 lib/release_mac.py gate-results <issue>       stdin: gh's comments JSON
    python3 lib/release_mac.py waivers <issue>            stdin: gh's comments JSON

Every agent posts as the same login as run-release.sh, so marker text alone
proves nothing: guard.py refusing it was eight review rounds of spellings,
never complete. A marker counts only with an HMAC-SHA256 under a key that
lives in a 0600 file outside both repos (RELEASE_KEY_FILE), read here and
never exported, so no session the driver starts inherits it. No agent role
may read or write that directory (RELEASE_KEY_RULES in providers.sh), and
guard.py refuses a shell command naming it or this script; `sign` and
`ledger` also refuse inside an agent session.

What is signed:
    release-gate <issue> <gate> <sha> <result> <ts>
    release-waive <issue> <n>
The issue number keeps one release's markers from counting on another's
issue. The gate marker's latest result is chosen by its signed `ts`, not by
comment order, so re-posting an old signed `pass` does not undo a later
`fail`; a `ts` in the future is ignored. A marker that is unsigned,
mis-signed or read without a sound key does not count: every gate fails
closed.

Deleting or editing a comment could still drop a `fail`, so every marker
run-release.sh posts is also written to a ledger beside the key. A reader
that finds a ledger marker missing from the issue exits 3 and names it:
the release stops until Don looks.
"""

import hashlib
import hmac
import json
import os
import re
import secrets
import sys
import time

KEY_FILE = os.path.expanduser(os.environ.get("RELEASE_KEY_FILE") or "~/.config/harnest/release.key")
LEDGER = os.path.join(os.path.dirname(KEY_FILE), "release-ledger.jsonl")
SKEW_SECS = 300

GATE = re.compile(r"^<!-- harnest:release-gate ([a-z-]+) ([0-9a-f]+) ([a-z]+) ([0-9]+) ([0-9a-f]{64}) -->", re.M)
WAIVE = re.compile(r"<!-- harnest:release-waive ([0-9]+) ([0-9a-f]{64}) -->")


def _fail(msg):
    print(f"release_mac: {msg}", file=sys.stderr)


def _key(create):
    """The key, or None when it is missing or unsound (fails closed)."""
    try:
        fd = os.open(KEY_FILE, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except FileNotFoundError:
        if not create:
            _fail(f"no key at {KEY_FILE}; no marker verifies")
            return None
        os.makedirs(os.path.dirname(KEY_FILE), mode=0o700, exist_ok=True)
        key = secrets.token_hex(32).encode()
        fd = os.open(KEY_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(key + b"\n")
        return key
    except OSError as e:
        _fail(f"cannot open {KEY_FILE} ({e}); no marker verifies")
        return None
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        key = f.read().strip()
    if st.st_uid != os.getuid() or st.st_mode & 0o077 or len(key) < 32:
        _fail(f"{KEY_FILE} is not a 0600 file of yours with at least 32 bytes; no marker verifies")
        return None
    return key


def _agent_session():
    """Set by run_agent for every claude session the drivers start."""
    return bool(os.environ.get("HARNEST_SESSION_KIND") or os.environ.get("HARNEST_ROLE"))


def mac(key, message):
    return hmac.new(key, message.encode(), hashlib.sha256).hexdigest()


def _bodies(stream):
    return [c.get("body") or "" for c in (json.load(stream).get("comments") or [])]


def gate_results(issue, bodies, key, now=None):
    """[(gate, sha, result)], one per gate and commit in first-seen order, the
    latest signed ts winning (comment order breaks a tie)."""
    limit = (now if now is not None else time.time()) + SKEW_SECS
    latest, order = {}, []
    for i, body in enumerate(bodies):
        for gate, sha, result, ts, tag in GATE.findall(body):
            if int(ts) > limit:
                continue
            if not hmac.compare_digest(tag, mac(key, f"release-gate {issue} {gate} {sha} {result} {ts}")):
                continue
            k = (gate, sha)
            if k not in latest:
                order.append(k)
            if k not in latest or (int(ts), i) >= latest[k][0]:
                latest[k] = ((int(ts), i), result)
    return [(g, s, latest[(g, s)][1]) for g, s in order]


def waivers(issue, bodies, key):
    return sorted(
        {
            int(n)
            for body in bodies
            for n, tag in WAIVE.findall(body)
            if hmac.compare_digest(tag, mac(key, f"release-waive {issue} {n}"))
        }
    )


def ledger_missing(issue, bodies):
    """The markers the ledger says were posted on <issue> that it no longer carries."""
    try:
        with open(LEDGER) as f:
            rows = [json.loads(line) for line in f if line.strip()]
    except FileNotFoundError:
        return []
    text = "\n".join(bodies)
    return [r["marker"] for r in rows if str(r.get("issue")) == str(issue) and r.get("marker", "") not in text]


def main(argv):
    cmds = {"sign": 3, "ledger": 4, "gate-results": 3, "waivers": 3}
    if len(argv) < 2 or cmds.get(argv[1]) != len(argv):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    cmd = argv[1]
    if cmd in ("sign", "ledger"):
        if _agent_session():
            _fail("refused inside an agent session: only run-release.sh, which Don runs, signs a marker")
            return 1
        if cmd == "ledger":
            fd = os.open(LEDGER, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            with os.fdopen(fd, "a") as f:
                f.write(json.dumps({"issue": argv[2], "marker": argv[3].strip()}) + "\n")
            return 0
        key = _key(create=True)
        if key is None:
            return 1
        print(mac(key, argv[2]))
        return 0
    issue = argv[2]
    bodies = _bodies(sys.stdin)
    missing = ledger_missing(issue, bodies)
    if missing:
        _fail(f"{len(missing)} marker(s) run-release.sh posted on #{issue} are gone or edited: " + "; ".join(missing))
        return 3
    key = _key(create=False)
    if key is None:
        return 0
    if cmd == "gate-results":
        for row in gate_results(issue, bodies, key):
            print(" ".join(row))
    else:
        print(" ".join(str(n) for n in waivers(issue, bodies, key)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
