#!/usr/bin/env python3
"""Sign and verify run-release.sh's markers on the release issue (harnest#140).

    python3 lib/release_mac.py sign <message>          print the MAC, making the key if missing
    python3 lib/release_mac.py gate-results <issue>    stdin: gh's comments JSON
    python3 lib/release_mac.py waivers <issue>         stdin: gh's comments JSON

Every agent posts as the same login as run-release.sh, so marker text alone
proves nothing: guard.py refusing it was eight review rounds of spellings,
never complete. A marker counts only with an HMAC-SHA256 under a key that
lives in a 0600 file outside both repos (RELEASE_KEY_FILE), read here and
never exported, so no session the driver starts inherits it.

What is signed:
    release-gate <issue> <gate> <sha> <result> <ts>
    release-waive <issue> <n>
The issue number keeps one release's markers from counting on another's
issue. The gate marker's latest result is chosen by its signed `ts`, not by
comment order, so re-posting an old signed `pass` does not undo a later
`fail`. A marker that is unsigned, mis-signed or read without the key does
not count: every gate fails closed.
"""

import hashlib
import hmac
import json
import os
import re
import secrets
import sys

KEY_FILE = os.path.expanduser(os.environ.get("RELEASE_KEY_FILE") or "~/.config/harnest/release.key")

GATE = re.compile(r"^<!-- harnest:release-gate ([a-z-]+) ([0-9a-f]+) ([a-z]+) ([0-9]+) ([0-9a-f]{64}) -->", re.M)
WAIVE = re.compile(r"<!-- harnest:release-waive ([0-9]+) ([0-9a-f]{64}) -->")


def _key(create):
    try:
        with open(KEY_FILE, "rb") as f:
            return f.read().strip()
    except FileNotFoundError:
        if not create:
            print(f"release_mac: no key at {KEY_FILE}; no marker verifies", file=sys.stderr)
            return None
    os.makedirs(os.path.dirname(KEY_FILE), mode=0o700, exist_ok=True)
    key = secrets.token_hex(32).encode()
    fd = os.open(KEY_FILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(key + b"\n")
    return key


def mac(key, message):
    return hmac.new(key, message.encode(), hashlib.sha256).hexdigest()


def _bodies(stream):
    return [c.get("body") or "" for c in (json.load(stream).get("comments") or [])]


def gate_results(issue, bodies, key):
    """[(gate, sha, result)], one per gate and commit in first-seen order, the
    latest signed ts winning (comment order breaks a tie)."""
    latest, order = {}, []
    for i, body in enumerate(bodies):
        for gate, sha, result, ts, tag in GATE.findall(body):
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


def main(argv):
    if len(argv) != 3 or argv[1] not in ("sign", "gate-results", "waivers"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    cmd, arg = argv[1], argv[2]
    if cmd == "sign":
        print(mac(_key(create=True), arg))
        return 0
    key = _key(create=False)
    bodies = _bodies(sys.stdin)
    if key is None:
        return 0
    if cmd == "gate-results":
        for row in gate_results(arg, bodies, key):
            print(" ".join(row))
    else:
        print(" ".join(str(n) for n in waivers(arg, bodies, key)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
