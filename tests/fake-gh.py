#!/usr/bin/env python3
"""A fake `gh` for the harness's offline tests, backed by a JSON board.

    FAKE_GH_BOARD=<file>   {"<owner/repo>": [<issue>, ...], ...}; each issue
                           in `gh --json` shape plus "state" and "comments".
                           Edits, comments and closes are written back, so a
                           driver run changes the board the way GitHub would.
    FAKE_GH_FAIL=1         every call but `auth status` fails, as in an outage
    FAKE_GH_AUTHOR=<login> author of comments added by `issue comment` (default dkackman)
    FAKE_GH_FAIL_AFTER=<n> every call after the nth fails (counted across calls in <board>.count)
    FAKE_GH_LOG=<file>     every call is appended, one line each
    FAKE_GH_FAIL_MATCH=<re> a call whose arguments (space-joined) match the regex fails

`issue list` answers like gh: newest first, at most --limit rows (default
30), filtered by --search (see matches()); comments, creates and closes are
stamped with the current UTC time.

Covers what the drivers call: issue list/view/edit/comment/close/create,
api (events, from an issue's "events" list, and the comment PATCH), and auth status. --json projects the
fields asked for, and --jq is applied with the real jq.
"""

import datetime
import json
import os
import re
import shlex
import subprocess
import sys

args = sys.argv[1:]
if os.environ.get("FAKE_GH_LOG"):
    with open(os.environ["FAKE_GH_LOG"], "a") as f:
        f.write("gh " + " ".join(args) + "\n")
if args[:2] == ["auth", "status"]:
    sys.exit(0)
if os.environ.get("FAKE_GH_FAIL") == "1":
    print("gh: simulated outage", file=sys.stderr)
    sys.exit(1)

if os.environ.get("FAKE_GH_FAIL_MATCH"):
    if re.search(os.environ["FAKE_GH_FAIL_MATCH"], " ".join(args)):
        print("gh: simulated failure of this call", file=sys.stderr)
        sys.exit(1)

path = os.environ["FAKE_GH_BOARD"]
if os.environ.get("FAKE_GH_FAIL_AFTER"):
    cf = path + ".count"
    n = (int(open(cf).read()) if os.path.exists(cf) else 0) + 1
    open(cf, "w").write(str(n))
    if n > int(os.environ["FAKE_GH_FAIL_AFTER"]):
        print("gh: simulated outage after %s calls" % os.environ["FAKE_GH_FAIL_AFTER"], file=sys.stderr)
        sys.exit(1)
board = json.load(open(path))


def opt(name, many=False):
    vals = [args[i + 1] for i, a in enumerate(args[:-1]) if a == name]
    return vals if many else (vals[-1] if vals else None)


def out(data):
    text = json.dumps(data)
    jq = opt("--jq") or opt("-q")
    if jq:
        r = subprocess.run(["jq", "-r", jq], input=text, capture_output=True, text=True)
        sys.stdout.write(r.stdout)
        sys.exit(r.returncode)
    print(text)


def project(issue):
    fields = (opt("--json") or "").split(",")
    view = dict(issue)
    view.setdefault("parent", None)
    view.setdefault("blockedBy", {"nodes": []})
    view.setdefault("subIssuesSummary", {"total": 0, "completed": 0})
    view.setdefault("comments", [])
    view.setdefault("body", "")
    view.setdefault("title", "t%d" % issue["number"])
    view.setdefault("author", {"login": "dkackman"})
    view["stateReason"] = issue.get("stateReason", "")
    return {f: view.get(f) for f in fields if f}


repo = opt("--repo") or opt("-R") or os.environ.get("TICKET_REPO", "")
issues = board.setdefault(repo, [])
labels = lambda i: [l["name"] for l in i.get("labels", [])]


def repo_of_api(argv):
    """owner/repo out of a `gh api repos/<owner>/<repo>/...` path."""
    for a in argv[1:]:
        if a.startswith("repos/"):
            return "/".join(a.split("/")[1:3])
    return repo


def find(n):
    for i in issues:
        if str(i["number"]) == str(n).lstrip("#"):
            return i
    print("issue not found", file=sys.stderr)
    sys.exit(1)


def save():
    json.dump(board, open(path, "w"), indent=1)


def now():
    return datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


QUALIFIERS = {"closed", "created", "updated", "merged", "author", "reason", "in", "is", "label", "state", "sort"}


def matches(issue, search):
    """gh's --search, for the qualifiers the drivers use: closed:/created:/
    updated: with >=, >, <=, < or a bare date; author:/-author:; reason:;
    in:title (free words match the title only, else title or body). Free
    words and quoted phrases match case-insensitively; other qualifiers
    (is:, label:, ...) are ignored."""
    words, title_only = [], False
    for term in shlex.split(search):
        neg = term.startswith("-")
        key, _, val = term.lstrip("-").partition(":")
        if key not in QUALIFIERS:  # a word, or a quoted phrase that holds a colon
            words.append(term.lower())
        elif key in ("closed", "created", "updated"):
            have = issue.get(key + "At") or ""
            m = re.match(r"(>=|<=|>|<)?(.*)", val)
            op, d = m.group(1) or "=", m.group(2)
            have = have[: len(d)]
            ok = (
                bool(have)
                and {
                    ">=": have >= d,
                    ">": have > d,
                    "<=": have <= d,
                    "<": have < d,
                    "=": have == d,
                }[op]
            )
            if ok == neg:
                return False
        elif key == "author":
            if (issue.get("author", {"login": "dkackman"}).get("login") == val) == neg:
                return False
        elif key == "reason":
            want = val.replace(" ", "_").upper()
            if (issue.get("stateReason", "") == want) == neg:
                return False
        elif key == "in" and val == "title":
            title_only = True
    hay = issue.get("title", "") + ("" if title_only else "\n" + issue.get("body", ""))
    return all(w in hay.lower() for w in words)


cmd = args[:2]
if cmd == ["issue", "list"]:
    state = (opt("--state") or "open").upper()
    want = opt("--label", many=True)
    search = opt("--search") or ""
    rows = [
        i
        for i in issues
        if (state == "ALL" or i.get("state", "OPEN") == state)
        and all(l in labels(i) for l in want)
        and matches(i, search)
    ]
    # gh lists newest first and returns at most --limit rows (default 30)
    rows.sort(key=lambda i: -i["number"])
    out([project(i) for i in rows[: int(opt("--limit") or opt("-L") or 30)]])
elif cmd == ["issue", "view"]:
    out(project(find(args[2])))
elif cmd == ["issue", "edit"]:
    i = find(args[2])
    have = labels(i)
    for l in sum((v.split(",") for v in opt("--remove-label", many=True)), []):
        have = [x for x in have if x != l]
    for l in sum((v.split(",") for v in opt("--add-label", many=True)), []):
        have.append(l) if l not in have else None
    # FAKE_GH_ON_EDIT_<n>=<label>: another loop's claim lands on <n> at the
    # moment this one edits it (the claim race)
    other = os.environ.get("FAKE_GH_ON_EDIT_%s" % args[2])
    if other and other not in have:
        have.append(other)
    i["labels"] = [{"name": l} for l in have]
    save()
elif cmd == ["issue", "comment"]:
    i = find(args[2])
    body = opt("--body") or (open(opt("--body-file")).read() if opt("--body-file") else "")
    i.setdefault("comments", []).append(
        {
            "author": {"login": os.environ.get("FAKE_GH_AUTHOR", "dkackman")},
            "body": body,
            "createdAt": now(),
        }
    )
    save()
elif cmd == ["issue", "create"]:
    n = max([i["number"] for i in issues] + [0]) + 1
    names = sum((v.split(",") for v in opt("--label", many=True)), [])
    issues.append(
        {
            "number": n,
            "state": "OPEN",
            "title": opt("--title") or "",
            "body": opt("--body") or "",
            "labels": [{"name": l} for l in names],
            "comments": [],
            "createdAt": now(),
            "updatedAt": now(),
        }
    )
    save()
    print("https://github.com/%s/issues/%d" % (repo, n))
elif cmd == ["issue", "close"]:
    i = find(args[2])
    i["state"] = "CLOSED"
    i["closedAt"] = i["updatedAt"] = now()
    i["stateReason"] = "NOT_PLANNED" if (opt("--reason") or "").lower() == "not planned" else "COMPLETED"
    save()
elif cmd[0] == "api" and "security-advisories" in " ".join(args):
    # Draft advisories live beside the issues, under "<repo>#advisories"
    advs = board.setdefault(repo_of_api(args) + "#advisories", [])
    path_arg = next(a for a in args[1:] if "security-advisories" in a)
    method = (opt("-X") or opt("--method") or "GET").upper()
    ghsa = path_arg.split("security-advisories")[1].strip("/").split("?")[0]
    if method == "POST":
        body = json.load(sys.stdin) if opt("--input") == "-" else {}
        adv = dict(body, ghsa_id="GHSA-fake-%04d" % (len(advs) + 1), state="draft")
        adv["html_url"] = "https://github.com/%s/security/advisories/%s" % (repo_of_api(args), adv["ghsa_id"])
        advs.append(adv)
        save()
        out(adv)
    elif ghsa:
        adv = next(a for a in advs if a["ghsa_id"] == ghsa)
        if method == "PATCH":
            adv.update(json.load(sys.stdin) if opt("--input") == "-" else {})
            save()
        out(adv)
    else:
        out([a for a in advs if a.get("state") == "draft"])
elif cmd[0] == "api" and any(a.startswith("repos/") and a.split("?")[0].endswith("/events") for a in args):
    # an issue's label history: the board issue's own "events", if it has any
    path_arg = next(a for a in args if a.startswith("repos/") and a.split("?")[0].endswith("/events"))
    repo, n = repo_of_api(args), path_arg.split("/")[-2]
    issues = board.setdefault(repo, [])
    out(next((i.get("events", []) for i in issues if str(i["number"]) == n), []))
elif cmd[0] == "api":
    out([])
else:
    print("fake gh: unsupported: " + " ".join(args), file=sys.stderr)
    sys.exit(1)
