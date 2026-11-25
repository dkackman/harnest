#!/usr/bin/env python3
"""R19 phase 1: the delegate replay (docs/superpowers/plans/2026-11-25-escalation-delegate.md).

    scripts/delegate-replay.py cases [--since 2026-10-15]
        Pulls closed issues on both repos, finds Don's own rulings (not the
        trial delegate's), and writes one case per ruling to
        logs/delegate-replay/cases/<id>.json plus its answer to
        logs/delegate-replay/answers/<id>.json, and an index of every
        candidate to logs/delegate-replay/index.tsv (id, date, leaked|clean,
        first line of the ruling). A leaked case has Don's ruling already
        folded into the plan before it; it is never picked. The pilot's 20 cases and their labels go in
        logs/delegate-replay/key.json by hand.

SOURCE_DIR (the README's) names the dw clone whose origin/develop gives each
case's dw commit.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from harness import REPO  # noqa: E402
from harness import delegate_replay as dr  # noqa: E402

OUT = REPO / "logs" / "delegate-replay"


def cases(args) -> int:
    source = os.path.expanduser(os.environ.get("SOURCE_DIR") or "~/src/dkackman/dw-agent")
    (OUT / "cases").mkdir(parents=True, exist_ok=True)
    (OUT / "answers").mkdir(parents=True, exist_ok=True)
    index = []
    for repo in dr.REPOS:
        for issue in dr.closed_issues(repo, args.since):
            ks = dr.rulings(issue)
            if not ks:
                continue
            events = dr.label_events(repo, issue["number"])
            for k in ks:
                when = issue["comments"][k]["createdAt"]
                commit = dr.develop_at(source, when) if repo.endswith("diffusers-workflow") else None
                case = dr.cut(issue, k, events, repo, commit)
                (OUT / "cases" / f"{case['id']}.json").write_text(json.dumps(case, indent=1))
                (OUT / "answers" / f"{case['id']}.json").write_text(json.dumps(dr.answer(issue, k), indent=1))
                index.append(
                    (
                        case["id"],
                        when[:10],
                        "leaked" if case["leaked"] else "clean",
                        dr.first_line(issue["comments"][k]["body"])[:200],
                    )
                )
    index.sort()
    (OUT / "index.tsv").write_text("".join("\t".join(row) + "\n" for row in index))
    print(f"{len(index)} cases in {OUT}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="delegate-replay.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cases")
    c.add_argument("--since", default="2026-10-15")
    args = ap.parse_args(argv)
    return {"cases": cases}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
