#!/usr/bin/env python3
"""A fake `gh` for the harness's offline tests, backed by a JSON board.

    FAKE_GH_BOARD=<file>   {"<owner/repo>": [<issue>, ...], ...}; each issue
                           in `gh --json` shape plus "state" and "comments".
                           Edits, comments and closes are written back, so a
                           driver run changes the board the way GitHub would.
    FAKE_GH_FAIL=1         every call but `auth status` fails, as in an outage
    FAKE_GH_LOG=<file>     every call is appended, one line each

Covers what the drivers call: issue list/view/edit/comment/close/create,
api (events, and the comment PATCH), and auth status. --json projects the
fields asked for, and --jq is applied with the real jq.
"""
import json, os, subprocess, sys

args = sys.argv[1:]
if os.environ.get("FAKE_GH_LOG"):
    with open(os.environ["FAKE_GH_LOG"], "a") as f:
        f.write("gh " + " ".join(args) + "\n")
if args[:2] == ["auth", "status"]:
    sys.exit(0)
if os.environ.get("FAKE_GH_FAIL") == "1":
    print("gh: simulated outage", file=sys.stderr)
    sys.exit(1)

path = os.environ["FAKE_GH_BOARD"]
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


def find(n):
    for i in issues:
        if str(i["number"]) == str(n).lstrip("#"):
            return i
    print("issue not found", file=sys.stderr)
    sys.exit(1)


def save():
    json.dump(board, open(path, "w"), indent=1)


cmd = args[:2]
if cmd == ["issue", "list"]:
    state = (opt("--state") or "open").upper()
    want = opt("--label", many=True)
    search = opt("--search") or ""
    rows = [i for i in issues
            if (state == "ALL" or i.get("state", "OPEN") == state)
            and all(l in labels(i) for l in want)
            and not (search.startswith("-author:") and i.get("author", {}).get("login") == search[8:])]
    out([project(i) for i in rows])
elif cmd == ["issue", "view"]:
    out(project(find(args[2])))
elif cmd == ["issue", "edit"]:
    i = find(args[2])
    have = labels(i)
    for l in sum((v.split(",") for v in opt("--remove-label", many=True)), []):
        have = [x for x in have if x != l]
    for l in sum((v.split(",") for v in opt("--add-label", many=True)), []):
        have.append(l) if l not in have else None
    i["labels"] = [{"name": l} for l in have]
    save()
elif cmd == ["issue", "comment"]:
    i = find(args[2])
    body = opt("--body") or (open(opt("--body-file")).read() if opt("--body-file") else "")
    i.setdefault("comments", []).append({"author": {"login": "dkackman"}, "body": body, "createdAt": "2026-01-01T00:00:00Z"})
    save()
elif cmd == ["issue", "create"]:
    n = max([i["number"] for i in issues] + [0]) + 1
    names = sum((v.split(",") for v in opt("--label", many=True)), [])
    issues.append({"number": n, "state": "OPEN", "title": opt("--title") or "", "body": opt("--body") or "",
                   "labels": [{"name": l} for l in names], "comments": []})
    save()
    print("https://github.com/%s/issues/%d" % (repo, n))
elif cmd == ["issue", "close"]:
    i = find(args[2])
    i["state"] = "CLOSED"
    i["stateReason"] = "NOT_PLANNED" if (opt("--reason") or "").lower() == "not planned" else "COMPLETED"
    save()
elif cmd[0] == "api":
    out([])
else:
    print("fake gh: unsupported: " + " ".join(args), file=sys.stderr)
    sys.exit(1)
