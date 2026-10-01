#!/usr/bin/env python3
"""The curator's weekly consolidation cadence (stage C).

    python3 lib/consolidation.py run --tree <dw tree> --python <py> --state <json> --repo <owner/repo>
                                     [--every-days 7] [--max 3]

Once every --every-days, runs dw's `scripts/arch_report.py HEAD=HEAD` in the
tree (the driver passes its worktree at origin/develop) and reads two of its
tables: change coupling (file pairs that change together, over a window
fixed in the script) and hotspots. It compares them with last week's, kept
in --state, and files at most --max issues on --repo, labelled
`consolidation` + `owner:don`, one per coupled pair that is new to the top
ten or whose shared commits rose by five or more, with both weeks' numbers.
Nothing moved, nothing filed; the first report only becomes next week's
baseline. A pair with an open consolidation issue is not filed again. It
fixes nothing: consolidation is designed, by Don, not done drive-by.

Off (silently) while the tree has no scripts/arch_report.py. A report that
fails is logged and retried a day later.
"""
import argparse, json, os, subprocess, sys, time

REPORT = "scripts/arch_report.py"
RISE = 5
DAY = 86400


def tables(text):
    """{'coupling': [[shared, degree, a, b], ...], 'hotspots': [[score, commits, complexity, file], ...]}
    from the report's markdown, by section heading."""
    out, key, rows = {"coupling": [], "hotspots": []}, None, None
    for line in text.splitlines():
        if line.startswith("#### "):
            key = "coupling" if line.startswith("#### Change coupling") else "hotspots" if line.startswith("#### Hotspots") else None
            rows = out[key] if key else None
            continue
        if rows is None or not line.startswith("|") or set(line) <= set("|- "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4 or not cells[0].isdigit():  # the header row, or not this table's shape
            continue
        rows.append([int(c) if c.isdigit() else c for c in cells])
    return out


def moved(prev, cur):
    """(pair, why, before-row or None, after-row) for each pair worth a look,
    rises first (largest first), then pairs new to the top ten."""
    before = {(r[2], r[3]): r for r in prev}
    rises, new = [], []
    for r in cur:
        old = before.get((r[2], r[3]))
        if old is None:
            new.append(((r[2], r[3]), "new to the top ten", None, r))
        elif r[0] - old[0] >= RISE:
            rises.append(((r[2], r[3]), "shared commits rose by %d" % (r[0] - old[0]), old, r))
    rises.sort(key=lambda m: -(m[3][0] - m[2][0]))
    new.sort(key=lambda m: -m[3][0])
    return rises + new


def body(pair, why, old, new, last, this):
    def hot(week, f):
        row = next((r for r in week["hotspots"] if r[3] == f), None)
        return "score %d (%d commits x complexity %d)" % tuple(row[:3]) if row else "not in the top ten"
    def cell(row, i):
        return str(row[i]) if row else "not in the top ten"
    lines = [
        "Filed by the curator's weekly consolidation cadence: dw's `scripts/arch_report.py HEAD=HEAD`, "
        "compared with last week's run. Why: %s." % why,
        "",
        "`%s` and `%s` change together:" % pair,
        "",
        "| | last week (%s, `%s`) | this week (%s, `%s`) |" % (last["date"], last["head"][:8], this["date"], this["head"][:8]),
        "| --- | --- | --- |",
        "| Shared commits | %s | %s |" % (cell(old, 0), cell(new, 0)),
        "| Degree %% | %s | %s |" % (cell(old, 1), cell(new, 1)),
    ]
    lines += ["| Hotspot `%s` | %s | %s |" % (f, hot(last, f), hot(this, f)) for f in pair]
    lines += ["", "Consolidation is designed, not drive-by: decide whether these two hold one concept between "
              "them (`docs/ARCHITECTURE.md` names each one's owner), and plan it if so. No agent works this issue."]
    return "\n".join(lines)


def open_titles(repo):
    r = subprocess.run(["gh", "issue", "list", "--repo", repo, "--state", "open", "--label", "consolidation",
                        "--limit", "200", "--json", "title", "--jq", ".[].title"], capture_output=True, text=True)
    return None if r.returncode else r.stdout.splitlines()


def run(a):
    script = os.path.join(a.tree, REPORT)
    if not os.path.exists(script):
        return 0
    try:
        state = json.load(open(a.state))
    except (OSError, ValueError):
        state = {}
    now = int(time.time())
    if now - state.get("ran_at", 0) < a.every_days * DAY or now - state.get("failed_at", 0) < DAY:
        return 0
    env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
    r = subprocess.run([a.python, REPORT, "HEAD=HEAD"], cwd=a.tree, capture_output=True, text=True, env=env)
    this = tables(r.stdout)
    if r.returncode or not this["coupling"]:
        print("arch_report.py failed (exit %d), retrying in a day: %s" % (r.returncode, (r.stderr or r.stdout)[-300:].strip()))
        state["failed_at"] = now
        json.dump(state, open(a.state, "w"), indent=1)
        return 0
    head = subprocess.run(["git", "-C", a.tree, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    this.update(ran_at=now, date=time.strftime("%Y-%m-%d", time.localtime(now)), head=head)
    filed, skipped = [], []
    if "coupling" not in state:
        print("first report (%s @ %s): kept as next week's baseline, nothing filed" % (this["date"], head[:8]))
    else:
        found = moved(state["coupling"], this["coupling"])
        titles = open_titles(a.repo) if found else []
        if titles is None:
            print("could not list open consolidation issues; retrying in a day")
            state["failed_at"] = now
            json.dump(state, open(a.state, "w"), indent=1)
            return 0
        for pair, why, old, new in found:
            title = "consolidation: %s and %s change together" % pair
            if title in titles:
                skipped.append(title)
                continue
            if len(filed) >= a.max:
                break
            c = subprocess.run(["gh", "issue", "create", "--repo", a.repo, "--title", title, "--label", "consolidation",
                                "--label", "owner:don", "--body", body(pair, why, old, new, state, this)],
                               capture_output=True, text=True)
            filed.append(c.stdout.strip().rsplit("/", 1)[-1] if c.returncode == 0 else "failed: " + title)
        print("week of %s @ %s against %s: %d pair(s) moved, filed %s%s" % (
            this["date"], head[:8], state.get("date", "?"), len(found), ", ".join("#" + f if f.isdigit() else f for f in filed) or "nothing",
            "; %d already open" % len(skipped) if skipped else ""))
    json.dump(this, open(a.state, "w"), indent=1)
    return 0


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["run"])
    p.add_argument("--tree", required=True)
    p.add_argument("--python", default=sys.executable)
    p.add_argument("--state", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--every-days", type=float, default=7)
    p.add_argument("--max", type=int, default=3)
    sys.exit(run(p.parse_args()))
