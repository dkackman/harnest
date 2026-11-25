"""R19 phase 1: replay Don's closed rulings through a draft delegate.

A case is an issue as it stood when Don was asked: its body, the comments
before his ruling, its labels at that moment and the dw develop commit of
that moment. Nothing written at or after the ruling goes in (the answer key
would leak). Rulings written by the trial delegate are not Don's and are
never cases.

The spec is docs/superpowers/specs/2026-11-25-escalation-delegate.md; the
plan, docs/superpowers/plans/2026-11-25-escalation-delegate.md.
"""

from __future__ import annotations

import json
import re
import subprocess

REPOS = ("dkackman/diffusers-workflow", "dkackman/harnest")

# A ruling comment's first line, after any bold markers.
_RULING = re.compile(r"^(Don's ruling|Don's answers?|Ruling|Don ruled|Don approved|Approved)\b")
# The trial delegate, and a session ruling under Don's overnight delegation:
# not Don's own call.
_DELEGATED = re.compile(r"delegate|delegation", re.I)


# A lead that folded Don's in-session ruling into the plan before his ruling
# comment was posted: the answer is already in the case.
_LEAK = re.compile(r"\*\*Ruled[: ]|\bRuled: |Ruled otherwise|^Don changed:", re.M)


def leaked(case: dict) -> bool:
    texts = [case.get("body") or ""] + [c["body"] for c in case.get("comments") or []]
    return any(_LEAK.search(t) for t in texts[-2:])


def first_line(body: str) -> str:
    return (body or "").strip().split("\n", 1)[0].strip()


def is_ruling(body: str) -> bool:
    line = first_line(body).lstrip("*_ ").strip()
    return bool(_RULING.match(line))


# Anywhere in the body: a session that ruled under Don's delegation says so
# in its sign-off, not always in the first line.
_DELEGATED_BODY = re.compile(r"under (Don's|his)( overnight)? delegation|delegate for Don|plan-review delegate", re.I)


def is_delegated(body: str) -> bool:
    return bool(_DELEGATED.search(first_line(body)) or _DELEGATED_BODY.search(body or ""))


def rulings(issue: dict) -> list[int]:
    """Indexes of the comments that are Don's own rulings."""
    return [
        k
        for k, c in enumerate(issue.get("comments") or [])
        if is_ruling(c.get("body")) and not is_delegated(c.get("body"))
    ]


def labels_at(events: list[dict], when: str) -> list[str]:
    """The issue's labels just before `when` (ISO 8601, as GitHub gives it),
    replayed from its LabeledEvent/UnlabeledEvent timeline."""
    held: dict[str, bool] = {}
    for e in sorted(events, key=lambda e: e["createdAt"]):
        if e["createdAt"] >= when:
            break
        name = (e.get("label") or {}).get("name")
        if not name:
            continue
        if e["__typename"] == "LabeledEvent":
            held[name] = True
        elif e["__typename"] == "UnlabeledEvent":
            held.pop(name, None)
    return sorted(held)


def cut(issue: dict, k: int, events: list[dict], repo: str, commit: str | None) -> dict:
    """The case for ruling comment k: everything before it, nothing after."""
    comments = issue["comments"]
    ruling = comments[k]
    when = ruling["createdAt"]
    out = {
        "id": f"{repo.split('/')[1]}-{issue['number']}-{k}",
        "repo": repo,
        "number": issue["number"],
        "title": issue["title"],
        "asked_before": when,
        "labels": labels_at(events, when),
        "dw_commit": commit,
        "leaked": False,
        "body": issue.get("body") or "",
        "comments": [
            {"author": (c.get("author") or {}).get("login"), "createdAt": c["createdAt"], "body": c.get("body") or ""}
            for c in comments[:k]
        ],
    }
    out["leaked"] = leaked(out)
    return out


def answer(issue: dict, k: int) -> dict:
    """What Don actually ruled: kept out of the case, for the key."""
    c = issue["comments"][k]
    return {"createdAt": c["createdAt"], "first_line": first_line(c["body"]), "body": c["body"]}


# -- I/O --------------------------------------------------------------------


def _gh(args: list[str]) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def closed_issues(repo: str, since: str) -> list[dict]:
    out = _gh(
        [
            "issue",
            "list",
            "-R",
            repo,
            "--state",
            "closed",
            "--limit",
            "1000",
            "--search",
            f"updated:>={since}",
            "--json",
            "number,title,labels,body,comments",
        ]
    )
    return json.loads(out)


_TIMELINE = """query($o:String!,$n:String!,$i:Int!){repository(owner:$o,name:$n){issue(number:$i){
timelineItems(first:250,itemTypes:[LABELED_EVENT,UNLABELED_EVENT]){nodes{__typename
... on LabeledEvent{createdAt label{name}} ... on UnlabeledEvent{createdAt label{name}}}}}}}"""


def label_events(repo: str, number: int) -> list[dict]:
    owner, name = repo.split("/")
    out = _gh(
        ["api", "graphql", "-f", f"query={_TIMELINE}", "-F", f"o={owner}", "-F", f"n={name}", "-F", f"i={number}"]
    )
    return json.loads(out)["data"]["repository"]["issue"]["timelineItems"]["nodes"]


def develop_at(source_dir: str, when: str) -> str | None:
    p = subprocess.run(
        ["git", "-C", source_dir, "rev-list", "-1", f"--before={when}", "origin/develop"],
        capture_output=True,
        text=True,
    )
    return p.stdout.strip() or None
