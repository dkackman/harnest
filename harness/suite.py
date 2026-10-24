"""The regression suites as files: case IDs, script-run cases, workspaces,
and committing what a run changed. A port of run-regression.sh's helpers
and providers.sh's commit_suite_changes.
"""

import os
import re
import sys
import time
from pathlib import Path

from .gitops import git

# `### <ID> <title>`: the shape every suite's headings use (S-F001, SE-P001).
CASE_HEADING = re.compile(r"^### ([A-Z]+-[A-Z][0-9]+) ")


def case_ids(suite_file):
    """Case IDs in file order, outside code fences: a `### ` heading in a
    case's fenced example is not a case (requirements.case_blocks)."""
    from .requirements import case_blocks  # requirements imports this module

    return list(case_blocks(suite_file))


def has_cases(suite_file):
    with open(suite_file, encoding="utf-8") as f:
        return any(line.startswith("### ") for line in f)


def script_cases(suite_file, cases_dir):
    """IDs whose block carries a `runner: script` line and that have a
    <cases_dir>/<ID>.json: those run through contract/run.py (R6), not an
    agent. The suite line is what makes a case script-run, so which cases
    graduate is a suite edit, under the same approval as any other."""
    out, cur = [], ""
    with open(suite_file, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("### "):
                m = CASE_HEADING.match(line)
                cur = m.group(1) if m else ""
            if cur and re.fullmatch(r"runner: script\s*", line):
                out.append(cur)
                cur = ""
    return [i for i in out if (Path(cases_dir) / f"{i}.json").is_file()]


_FENCE = ("```", "~~~")
_SECTION_END = re.compile(r"#{1,3}\s")  # a heading at the Fixtures section's level or above


def fixtures_section(suite_file):
    """The header's Fixtures section, from `## Fixtures` to the next heading
    at its level or above, outside a code fence; "" when there is none."""
    out, fence, inside = [], False, False
    for line in Path(suite_file).read_text(encoding="utf-8").splitlines(keepends=True):
        if line.lstrip().startswith(_FENCE):
            fence = not fence
        if not fence and _SECTION_END.match(line):
            if inside or CASE_HEADING.match(line):
                break
            inside = re.match(r"## Fixtures\b", line) is not None
        if inside:
            out.append(line)
    return "".join(out).rstrip()


def opening(suite_file):
    """Everything above the suite's first `## ` section (fence-aware)."""
    out, fence = [], False
    for line in Path(suite_file).read_text(encoding="utf-8").splitlines(keepends=True):
        if line.lstrip().startswith(_FENCE):
            fence = not fence
        if not fence and _SECTION_END.match(line) and not line.startswith("# "):
            break
        out.append(line)
    return "".join(out).rstrip()


# Suites whose opening is a rule for running every case, not background,
# and the case every session runs first: the security suite's says a refusal
# that came too late is a failure and that SE-F001 (the server's trust
# posture) gates the rest, in every slice of a chunked run.
OPENING_SUITES = {"regression-suite-security.md": "SE-F001"}


def case_text(suite_file, ids):
    """What a chunk session is handed instead of reading the suite: the
    security suite's opening (OPENING_SUITES), the Fixtures section, its
    gating case when <ids> lacks it, then each case's block in the order
    given (fence-aware,
    requirements.case_blocks). An id with no block is left out; the prompt
    still names it. No trailing newline, so `$(scripts/case-text.sh ...)`
    and this are the same bytes."""
    from .requirements import case_blocks  # requirements imports this module

    blocks = case_blocks(suite_file)
    gate = OPENING_SUITES.get(Path(suite_file).name)
    head = [opening(suite_file)] if gate else []
    first = [gate] if gate and ids and gate not in ids else []
    parts = head + [fixtures_section(suite_file)] + [blocks[i].rstrip() for i in [*first, *ids] if i in blocks]
    return "\n\n".join(p for p in parts if p)


def workspace_for_suite_file(path):
    """A suite file's own workspace, from its name, so an override file
    never shares fixtures with the canonical suite of its level."""
    base = Path(path).name
    if base.endswith(".md"):
        base = base[:-3]
    if base.startswith("regression-suite-"):
        return "regression-" + base[len("regression-suite-") :]
    return "regression-" + base


def commit_paths(server, perf_dir="regression-perf", results_dir="regression-results"):
    """What a regression run may commit: on the primary, the suites, the
    perf history and the results ledger; elsewhere only that server's own
    perf and results directories. (The loop's SUITE_EDITS widening doesn't
    apply: a regression run never sets it.)"""
    if server.primary:
        return ["regression-suite-*.md", perf_dir, results_dir]
    return [f"{perf_dir}/{server.name}", f"{results_dir}/{server.name}"]


def _dirty(repo, paths):
    if git("diff", "HEAD", "--quiet", "--", *paths, cwd=repo).returncode != 0:
        return True
    return bool(git("ls-files", "--others", "--exclude-standard", "--", *paths, cwd=repo).stdout.strip())


def _shrunk(repo, paths):
    """ "file(-N) ..." for staged removed lines, not counting the `pending:
    #NN` lines the tester drops when a feature stage verifies."""
    diff = git("-C", str(repo), "diff", "--cached", "-U0", "--", *paths).stdout
    counts, f = {}, ""
    for line in diff.splitlines():
        if line.startswith("+++ "):
            f = line.split(" ", 2)[1][2:] if len(line.split(" ")) > 1 else ""
            continue
        if line.startswith("-") and not line.startswith("--- ") and not re.fullmatch(r"-pending: #[0-9]+\s*", line):
            counts[f] = counts.get(f, 0) + 1
    return "".join(f"{k}(-{n}) " for k, n in counts.items())


def commit_changes(repo, logs, paths, msg, name, email, say, sleep=time.sleep):
    """Commits pending changes under <paths> with <msg> and a Co-Authored-By
    trailer; a no-op when nothing is dirty. Serialized with every other
    driver's suite commit by logs/.suite-commit.lock (git refuses a second
    writer). Removed lines are committed but warned about: suites only grow
    and perf history is append-only unless a human approved the change."""
    if not name or not email:
        raise ValueError(
            "run: commit_suite_changes: no co-author name/email — call co_author_for <provider> <model> first"
        )
    repo = str(repo)
    if not _dirty(repo, paths):
        return
    lock, tries = os.path.join(logs, ".suite-commit.lock"), 0
    while True:
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            tries += 1
            try:
                old = time.time() - os.stat(lock).st_mtime > 120
            except OSError:
                old = False
            if tries >= 120 or old:
                try:
                    os.rmdir(lock)
                except OSError:
                    pass
                tries = 0
            sleep(1)
    try:
        if not _dirty(repo, paths):
            return
        # a directory nothing has written yet is no pathspec git add or commit will take
        paths = [
            p
            for p in paths
            if "*" in p or os.path.exists(os.path.join(repo, p)) or git("-C", repo, "ls-files", "--", p).stdout.strip()
        ]
        git("-C", repo, "add", "--", *paths)
        shrunk = _shrunk(repo, paths)
        git("-C", repo, "commit", "-q", "-m", msg, "-m", f"Co-Authored-By: {name} <{email}>", "--", *paths)
        say(msg)
        if shrunk:
            head = git("-C", repo, "rev-parse", "--short", "HEAD").stdout.strip()
            say(
                f"[audit] WARNING: {head} removed lines from {shrunk}- cases and readings are add-only "
                "unless a human approved the change; review it"
            )
    finally:
        try:
            os.rmdir(lock)
        except OSError:
            pass


def main(argv=None):
    """python3 -m harness.suite case-text <suite-file> <id>...   (scripts/case-text.sh)
    python3 -m harness.suite case-ids <suite-file>             (run-regression.sh)"""
    args = sys.argv[1:] if argv is None else argv
    if len(args) >= 2 and args[0] == "case-text":
        print(case_text(args[1], args[2:]))
        return 0
    if len(args) == 2 and args[0] == "case-ids":
        for i in case_ids(args[1]):
            print(i)
        return 0
    print("usage: python3 -m harness.suite case-text <suite-file> <id>... | case-ids <suite-file>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
