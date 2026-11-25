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


# -- the run ------------------------------------------------------------------

# Appended to the delegate's core for a replay: the live session's actions
# (rule.md) are replaced by one JSON answer, and nothing is written anywhere.
REPLAY_INSTRUCTIONS = """
# Session: replay (no actions)

This is a replay of an ask Don has already answered. The issue below is
exactly as it stood when he was asked; you don't see his answer. Decide as
the core says, but do not run `gh`, post, label or edit anything. Your
working directory is the repo as it was at that moment: read what the ask
cites there with `Read`, `Glob` and `Grep`.

End your reply with one JSON object and nothing after it:

{"outcome": "rule" | "amend" | "pass",
 "verdict": "default" | "amended" | "declined" | "deferred" | "decided",
 "kinds": ["<kind>", ...],
 "reason": "<one line: why this outcome>",
 "ruling_text": "<the comment you would post, in the core's shape>"}

`verdict` is what you rule, or for a pass-through what you recommend:
`default` (the ask's default), `amended` (the default with a change),
`declined` (don't build or close), `deferred` (park with triggers), `decided`
(no default was offered and you pick an option).
"""


def render_case(case: dict) -> str:
    """The case as the user message: the issue as it stood at the ask."""
    parts = [
        f"# {case['repo']}#{case['number']}: {case['title']}",
        f"Labels when asked: {', '.join(case['labels']) or '(none)'}",
        "",
        "## Issue body",
        case["body"],
    ]
    for c in case["comments"]:
        parts += ["", f"## Comment ({c['createdAt']})", c["body"]]
    return "\n".join(parts)


def parse_answer(text: str) -> dict | None:
    """The last JSON object in the reply, or None."""
    end = text.rfind("}")
    while end != -1:
        start = text.rfind("{", 0, end)
        while start != -1:
            try:
                obj = json.loads(text[start : end + 1])
                if isinstance(obj, dict) and "outcome" in obj:
                    return obj
            except ValueError:
                pass
            start = text.rfind("{", 0, start)
        end = text.rfind("}", 0, end)
    return None


# A ruling's cost before any is measured (the lead's p90 on Opus is $3.29).
FIRST_GUESS_USD = 3.5


def would_exceed(spent: float, costs: list[float], budget: float) -> bool:
    """True when the next session, at the median cost so far, would take the
    total past the budget."""
    nxt = sorted(costs)[len(costs) // 2] if costs else FIRST_GUESS_USD
    return spent + nxt > budget
