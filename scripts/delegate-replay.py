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

    scripts/delegate-replay.py run [--models M,M] [--limit N]
        Runs each case in key.json through each model (alternating, so a
        stop leaves every model with the same cases): `claude -p` with the
        delegate's core plus the replay instructions, the case as the
        message, read-only tools in a detached tree of the case's repo as of
        the ask, no MCP. Writes logs/delegate-replay/runs/<model>/<id>.json
        and skips a run already there. Stops before the session that would
        take the total past DELEGATE_REPLAY_BUDGET_USD (default 100),
        counting the runs already on disk.

    scripts/delegate-replay.py score [--out FILE]
        Scores every model's runs against key.json (harness.delegate_replay
        .score) and writes the tables and every disagreement, side by side,
        to FILE (default logs/delegate-replay/score.md).

SOURCE_DIR (the README's) names the dw clone whose origin/develop gives each
case's dw commit.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
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


MODELS = ("claude-fable-5-2", "claude-opus-5-5")


def _tree(repo: str, when: str, commit: str | None, work: Path) -> Path:
    """A detached checkout of the case's repo as of the ask."""
    if repo.endswith("diffusers-workflow"):
        src = os.path.expanduser(os.environ.get("SOURCE_DIR") or "~/src/dkackman/dw-agent")
        ref = commit or dr.develop_at(src, when)
    else:
        src = str(REPO)
        ref = subprocess.run(
            ["git", "-C", src, "rev-list", "-1", f"--before={when}", "HEAD"], capture_output=True, text=True
        ).stdout.strip()
    path = work / (Path(src).name + "-" + (ref or "head")[:12])
    if not path.exists():
        subprocess.run(["git", "-C", src, "worktree", "add", "-q", "--detach", str(path), ref or "HEAD"], check=True)
    return path


def _drop_tree(path: Path) -> None:
    for src in (os.path.expanduser(os.environ.get("SOURCE_DIR") or "~/src/dkackman/dw-agent"), str(REPO)):
        subprocess.run(["git", "-C", src, "worktree", "remove", "--force", str(path)], capture_output=True)
    shutil.rmtree(path, ignore_errors=True)


def _session(model: str, effort: str, system: Path, message: str, cwd: Path) -> dict:
    p = subprocess.run(
        [
            "claude",
            "-p",
            message,
            "--model",
            model,
            "--effort",
            effort,
            "--append-system-prompt-file",
            str(system),
            "--output-format",
            "json",
            "--permission-mode",
            "dontAsk",
            "--allowedTools",
            "Read",
            "Glob",
            "Grep",
            "--strict-mcp-config",
        ],
        cwd=str(cwd),
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=3600,
    )
    try:
        out = json.loads(p.stdout)
    except ValueError:
        out = {"result": p.stdout, "is_error": True}
    out["returncode"] = p.returncode
    out["stderr"] = p.stderr[-2000:]
    return out


def run(args) -> int:
    key = json.loads((OUT / "key.json").read_text())["cases"]
    ids = list(key)[: args.limit] if args.limit else list(key)
    models = [m for m in args.models.split(",") if m]
    budget = float(os.environ.get("DELEGATE_REPLAY_BUDGET_USD") or 100)
    effort = os.environ.get("DELEGATE_EFFORT") or "high"
    spent, costs = 0.0, []
    for m in models:
        for f in (OUT / "runs" / m).glob("*.json"):
            c = json.loads(f.read_text()).get("total_cost_usd") or 0.0
            spent += c
            costs.append(c)
    core = (REPO / "agents" / "delegate" / "core.md").read_text()
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        system = work / "system.md"
        system.write_text(core + "\n" + dr.REPLAY_INSTRUCTIONS)
        for cid in ids:
            case = json.loads((OUT / "cases" / f"{cid}.json").read_text())
            tree = None
            for m in models:
                dest = OUT / "runs" / m / f"{cid}.json"
                if dest.exists():
                    continue
                if dr.would_exceed(spent, costs, budget):
                    print(f"stopping: ${spent:.2f} spent, the next session would pass ${budget:.0f}")
                    return 0
                tree = tree or _tree(case["repo"], case["asked_before"], case.get("dw_commit"), work)
                out = _session(m, effort, system, dr.render_case(case), tree)
                out["answer"] = dr.parse_answer(out.get("result") or "")
                out["model"], out["case"], out["effort"] = m, cid, effort
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(json.dumps(out, indent=1))
                c = out.get("total_cost_usd") or 0.0
                spent += c
                costs.append(c)
                a = out["answer"] or {}
                print(f"{cid} {m}: {a.get('outcome', '?')}/{a.get('verdict', '?')} ${c:.2f} (total ${spent:.2f})")
            if tree:
                _drop_tree(tree)
    print(f"done: ${spent:.2f}")
    return 0


def score(args) -> int:
    key = json.loads((OUT / "key.json").read_text())["cases"]
    lines = [
        "| Model | Answered | Verdict agreement | Pass-through recall | Pass-through precision |"
        " Cost total | Median | p90 | 10-15 rulings/day |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    detail = []
    for mdir in sorted((OUT / "runs").glob("*")):
        runs = {f.stem: json.loads(f.read_text()) for f in mdir.glob("*.json")}
        s = dr.score(key, runs)
        med = s["cost_median"] or 0.0
        lines.append(
            f"| {mdir.name} | {s['answered']}/{s['runs']} | {s['verdict_agreement_pct']}% | "
            f"{s['pass_recall_pct']}% | {s['pass_precision_pct']}% | ${s['cost_total']:.2f} | "
            f"${med:.2f} | ${s['cost_p90'] or 0:.2f} | ${10 * med:.0f}-{15 * med:.0f} |"
        )
        detail += ["", f"## {mdir.name}", ""]
        if s["unparsed"]:
            detail.append(f"No JSON answer: {', '.join(s['unparsed'])}")
        for title, ids in (
            ("Missed pass-throughs (it ruled on a call that was Don's)", s["missed_passes"]),
            ("Extra pass-throughs (it sent Don a call it could have made)", s["extra_passes"]),
            ("Verdict differs from Don's", s["verdict_disagreements"]),
        ):
            detail += [f"### {title}: {len(ids)}", ""]
            for cid in ids:
                a, k = runs[cid]["answer"], key[cid]
                detail += [
                    f"- **{cid}** ({k['kind']}). Don: {k['verdict']}, {'his call' if k['pass_through_expected'] else 'delegable'}."
                    f" {k['summary']}",
                    f"  Delegate: {a.get('outcome')}/{a.get('verdict')}, kinds {', '.join(a.get('kinds') or [])}."
                    f" {a.get('reason', '')}",
                ]
            detail.append("")
    out = Path(args.out) if args.out else OUT / "score.md"
    out.write_text("# R19 pilot replay: scores\n\n" + "\n".join(lines) + "\n" + "\n".join(detail) + "\n")
    print("\n".join(lines))
    print(f"written: {out}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="delegate-replay.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("cases")
    c.add_argument("--since", default="2026-10-15")
    r = sub.add_parser("run")
    r.add_argument("--models", default=",".join(MODELS))
    r.add_argument("--limit", type=int, default=0)
    sc = sub.add_parser("score")
    sc.add_argument("--out", default="")
    args = ap.parse_args(argv)
    return {"cases": cases, "run": run, "score": score}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
