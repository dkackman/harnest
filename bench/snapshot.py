#!/usr/bin/env python3
"""Freeze bench cases: bench/cases/<n>/{meta.json,issue.md,verify.md,fix.patch,tests.patch}.

Run once per entry added to entries.tsv (existing cases are left alone unless
--force). Everything a replay or its judge needs is written here so a bench
run never calls gh and never reads the source repo past the pre-fix commit.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.environ.get("SOURCE_DIR", os.path.expanduser("~/src/dkackman/dw-agent"))
REPO = os.environ.get("TICKET_REPO", "dkackman/diffusers-workflow")


def run(*a, cwd=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, check=True).stdout


def git(*a):
    return run("git", "-C", SRC, *a)


def handoffs(n):
    ev = run("gh", "api", "--paginate", f"repos/{REPO}/issues/{n}/events", "--jq",
             '.[] | select(.event=="labeled" and .label.name=="status:fixed-pending-verify") | .event')
    return len(ev.split())


def main():
    force = "--force" in sys.argv
    git("fetch", "-q", "origin")
    log = [l.split("\t", 2) for l in git("log", "origin/develop", "--no-merges",
                                          "--format=%H%x09%at%x09%s").splitlines()]
    for line in open(os.path.join(HERE, "entries.tsv")):
        if not line.strip() or line.startswith("#"):
            continue
        n, kind, note = line.rstrip("\n").split("\t", 2)
        out = os.path.join(HERE, "cases", n)
        if os.path.exists(os.path.join(out, "meta.json")) and not force:
            continue
        os.makedirs(out, exist_ok=True)
        pat = re.compile(r"#%s(?!\d)" % n)
        fix = sorted(((int(t), h) for h, t, s in log if pat.search(s)))
        if not fix:
            print(f"#{n}: no fix commits on develop, skipped", file=sys.stderr)
            continue
        shas = [h for _, h in fix]
        prefix = git("rev-parse", shas[0] + "^").strip()
        files = sorted({f for h in shas for f in git("show", "--format=", "--name-only", h).split()})
        tests = [f for f in files if f.startswith("tests/")]
        with open(os.path.join(out, "fix.patch"), "w") as fh:
            for h in shas:
                fh.write(git("show", "--format=commit %H%n%s%n", h))
        with open(os.path.join(out, "tests.patch"), "w") as fh:
            for h in shas:
                if tests:
                    fh.write(git("show", "--format=", h, "--", *tests))
        iss = json.loads(run("gh", "issue", "view", n, "--repo", REPO, "--json",
                             "number,title,body,author,labels,createdAt,closedAt,comments"))
        owner_, name_ = REPO.split("/")
        edited = run("gh", "api", "graphql", "-f", "query={repository(owner:\"%s\",name:\"%s\"){issue(number:%s){lastEditedAt}}}" % (owner_, name_, n),
                     "--jq", ".data.repository.issue.lastEditedAt").strip()
        # What the real fixing session's prompt carried (run-loop.sh's
        # issue_context): the body plus the comments before the first
        # hand-off - triage notes, and Don's approval on an issue that was
        # parked first. Body-only replays of parked issues re-escalated
        # instead of fixing. Other logins are withheld, as in issue_context.
        first_handoff = run("gh", "api", "--paginate", f"repos/{REPO}/issues/{n}/events", "--jq",
                            '[.[] | select(.event=="labeled" and .label.name=="status:fixed-pending-verify") | .created_at] | first // ""').strip()
        before = [c for c in iss["comments"] if first_handoff and c["createdAt"] < first_handoff]
        with open(os.path.join(out, "issue.md"), "w") as fh:
            fh.write(f"## #{n}: {iss['title']}\nfiled by: @{iss['author']['login']}\n\n{iss['body']}\n")
            for c in before:
                who = c["author"]["login"]
                if who == iss["author"]["login"]:
                    fh.write(f"\n--- comment by @{who} at {c['createdAt']} ---\n{c['body']}\n")
                else:
                    fh.write(f"\n--- comment by @{who} at {c['createdAt']}: withheld (not the repo owner) ---\n")
        owner = [c for c in iss["comments"] if c["author"]["login"] == iss["author"]["login"]]
        with open(os.path.join(out, "verify.md"), "w") as fh:
            fh.write(owner[-1]["body"] if owner else "")
        meta = dict(issue=int(n), kind=kind, note=note, title=iss["title"], prefix=prefix,
                    fix_commits=shas, fix_files=files, test_files=tests, handoffs=handoffs(n),
                    context="body + owner comments before the first hand-off", comments_before_handoff=len(before),
                    body_edited_after_filing=edited not in ("", "null"))
        json.dump(meta, open(os.path.join(out, "meta.json"), "w"), indent=1)
        print(f"#{n}: prefix {prefix[:10]}, {len(shas)} fix commit(s), {len(files)} files")


main()
