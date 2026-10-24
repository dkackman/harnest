"""regression-results/: one append-only JSONL per case, one line per
session that was handed it, saying how it ended and how long it took
(regression-results/README.md). The regression drivers and the fleet write
it after every session; nothing edits it.

    python3 -m harness.results record <dir> <server> <level> <label> <head> <model> [case...] < session.log

(scripts/record-results.sh) reads a session's rendered log on stdin.
"""

import json
import sys
import time
from pathlib import Path

from .outcome import RESULT_RE, SKIP_RE

KEYS = ("ts", "level", "case", "outcome", "issue", "secs", "session", "head", "model", "server")


def results_dir(root, server):
    """<root> on the primary; <root>/<server> elsewhere, as regression-perf/ is
    split: one server's times are not another's."""
    return Path(root) if server.primary else Path(root) / server.name


def record(results_dir, server, level, case, outcome, issue, secs, session_label, head, model):
    """Appends one line to <results_dir>/<case>.jsonl, keys in KEYS order.
    <issue> is a number or None; <secs> seconds or None (not timed)."""
    d = Path(results_dir)
    d.mkdir(parents=True, exist_ok=True)
    row = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "level": level,
        "case": case,
        "outcome": outcome,
        "issue": issue,
        "secs": None if secs is None else round(float(secs), 1),
        "session": session_label,
        "head": head,
        "model": model,
        "server": server,
    }
    with open(d / f"{case}.jsonl", "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def session_outcomes(text, cases=()):
    """[(case, outcome, issue)] for one session's rendered log: each
    REGRESSION-RESULT line's outcome (the last for a case named twice), else
    `skip` for a REGRESSION-SKIP line, else, for a case the session was
    handed (<cases>), `not run` when it died before its usage line or
    reported its server unreachable (REGRESSION-ABORT), and
    `unreported` when it ended without answering. Handed cases first, in
    order, then any other case the log answered for."""
    said = {}
    for case, o, issue in RESULT_RE.findall(text):
        said[case] = (o, int(issue[1:]) if issue else None)
    for case in SKIP_RE.findall(text):
        said.setdefault(case, ("skip", None))
    lines = text.splitlines()
    died = not any(line.startswith("usage: ") for line in lines)
    aborted = any(line.startswith("REGRESSION-ABORT:") for line in lines)  # its server is unreachable
    order = list(dict.fromkeys([*cases, *said]))
    return [(c, *said.get(c, ("not run" if died or aborted else "unreported", None))) for c in order]


def record_session(results_dir, server, level, label, head, model, text, cases=(), secs=None):
    """Records every case <text> answered for or was handed; returns
    [(case, outcome)]. <secs>: {case: seconds} for the cases that were timed."""
    secs = secs or {}
    out = []
    for case, o, issue in session_outcomes(text, cases):
        record(results_dir, server, level, case, o, issue, secs.get(case), label, head, model)
        out.append((case, o))
    return out


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if len(args) < 7 or args[0] != "record":
        print(
            "usage: python3 -m harness.results record <dir> <server> <level> <label> <head> <model> [case...] < log",
            file=sys.stderr,
        )
        return 2
    d, server, level, label, head, model, *cases = args[1:]
    record_session(d, server, level, label, head, model, sys.stdin.read(), cases)
    return 0


if __name__ == "__main__":
    sys.exit(main())
