"""A session's own harnest worktree for suite edits (R17 "Suite edits").

Every session that may edit a suite file (tester of any kind, curator) runs
in a detached checkout of `main` under <harnest>/.worktrees/<session>. After
the session the driver lands it: under the one `suite` lock it commits the
tree's suite changes (suite.commit_changes: trailer and removed-lines audit),
rebases that commit onto the current `main` and fast-forwards `main` to it.
A rebase that conflicts leaves the commit on `suite-conflict/<session>` and
says an `[audit] WARNING`; nothing is dropped.
"""

import os
import shutil

from . import suite
from .gitops import git

BASE = "main"
# What a tester or curator session may leave in its tree for the commit: the
# loop's commit paths on lem (providers.sh suite_commit_paths, suite.commit_paths).
DEFAULT_PATHS = ("regression-suite-*.md", "regression-perf", "regression-results")
# A rebase that lost the race to another writer of main is tried again.
FF_TRIES = 3


def make(harnest, session_id):
    """`git worktree add --detach <harnest>/.worktrees/<session_id> main`; returns its path.
    A tree left there by a session that died is replaced."""
    harnest = str(harnest)
    tree = os.path.join(harnest, ".worktrees", session_id)
    if os.path.exists(tree):
        remove(harnest, tree)
    git("-C", harnest, "worktree", "prune")
    os.makedirs(os.path.dirname(tree), exist_ok=True)
    r = git("-C", harnest, "worktree", "add", "-q", "--detach", tree, BASE)
    if r.returncode != 0:
        raise RuntimeError(f"suite_tree.make: worktree add {tree} {BASE}: {r.stderr.strip()}")
    return tree


def remove(harnest, tree):
    """Drops the worktree, its changes with it (land it first)."""
    harnest, tree = str(harnest), str(tree)
    git("-C", harnest, "worktree", "remove", "--force", tree)
    if os.path.exists(tree):
        shutil.rmtree(tree, ignore_errors=True)
    git("-C", harnest, "worktree", "prune")


def _main_checkout(harnest):
    """The worktree that has `main` checked out, or "" when none does."""
    out = git("-C", harnest, "worktree", "list", "--porcelain").stdout
    path = ""
    for line in out.splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree ") :]
        elif line == f"branch refs/heads/{BASE}":
            return path
    return ""


def _fast_forward(harnest, new, old):
    """Moves main from <old> to <new>. A checkout of main has its working tree moved with it
    (merge --ff-only refuses over conflicting local changes); with none, the ref moves alone."""
    where = _main_checkout(harnest)
    if where:
        return git("-C", where, "merge", "-q", "--ff-only", new).returncode == 0
    return git("-C", harnest, "update-ref", f"refs/heads/{BASE}", new, old).returncode == 0


def _strand(tree, sha, why, say):
    sid = os.path.basename(os.path.normpath(tree))
    branch = f"suite-conflict/{sid}"
    git("-C", tree, "branch", "-f", branch, sha)
    say(
        f"[audit] WARNING: suite commit {sha[:9]} from session {sid} did not land on {BASE} ({why}); "
        f"it is kept on branch {branch} for Don to merge"
    )
    return "conflict"


def land(harnest, tree, msg, name, email, say, suite_lock, paths=DEFAULT_PATHS, logs=None):
    """Under <suite_lock> (any context manager; the driver's `suite` token): commits the tree's
    suite changes, rebases the commit onto main and fast-forwards main to it.
    Returns "landed", "clean" (nothing to commit) or "conflict" (the commit is left on
    branch suite-conflict/<session_id> and an [audit] WARNING is said)."""
    harnest, tree = str(harnest), str(tree)
    logs = logs or os.path.join(harnest, "logs")
    os.makedirs(logs, exist_ok=True)
    with suite_lock:
        before = git("-C", tree, "rev-parse", "HEAD").stdout.strip()
        suite.commit_changes(tree, logs, list(paths), msg, name, email, say)
        sha = git("-C", tree, "rev-parse", "HEAD").stdout.strip()
        if sha == before:
            return "clean"
        for _ in range(FF_TRIES):
            base = git("-C", tree, "rev-parse", BASE).stdout.strip()
            if git("-C", tree, "rebase", "-q", base).returncode != 0:
                git("-C", tree, "rebase", "--abort")
                git("-C", tree, "reset", "-q", "--hard", sha)
                return _strand(tree, sha, "rebase conflict", say)
            new = git("-C", tree, "rev-parse", "HEAD").stdout.strip()
            if _fast_forward(harnest, new, base):
                return "landed"
            if git("-C", tree, "rev-parse", BASE).stdout.strip() == base:
                # main did not move: the checkout of main refused (local changes over these files)
                return _strand(tree, new, f"the checkout of {BASE} has local changes", say)
        return _strand(tree, new, f"{BASE} kept moving", say)
