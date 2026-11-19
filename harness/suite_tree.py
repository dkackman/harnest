"""A session's own harnest worktree for suite edits (R17 "Suite edits").

Every session that may edit a suite file (tester of any kind, curator) runs
in a detached checkout of `main` made by make(), outside the harnest checkout
(<dirname(harnest)>/.harnest-worktrees/<basename(harnest)>/<session>), so no
path in one session's tree is under HARNEST_ROOT or another session's tree.
make() records the `main` tip it checked out (Tree.base); the driver hands it
to the session as HARNEST_SESSION_BASE (the guard's add-only baseline) and to
land().

After the session the driver lands it under the one `suite` lock. A session
never commits: a tree whose HEAD is not its base is stranded whole. Otherwise
the landing commit is built only from the working-tree changes to <paths>
(suite.commit_changes: trailer and removed-lines audit), checked to touch only
<paths>, rebased onto the current `main` and fast-forwarded there. Anything
else the session left in its tree is stranded. Nothing is ever dropped:
stranded work goes on a `suite-stranded/<session>` branch, a rebase conflict
on `suite-conflict/<session>` (never overwritten: -2, -3... when taken), and
each says an `[audit] WARNING`.
"""

import fnmatch
import os
import shutil
import subprocess
import tempfile
from typing import NamedTuple

from . import suite
from .gitops import git

BASE = "main"
# What a tester or curator session may leave in its tree for the commit: the
# loop's commit paths on lem (providers.sh suite_commit_paths, suite.commit_paths).
DEFAULT_PATHS = ("regression-suite-*.md", "regression-perf", "regression-results")
# A rebase that lost the race to another writer of main is tried again.
FF_TRIES = 3
# Who commits a stranded snapshot (a branch for Don, never main).
STRAND_ENV = {
    "GIT_AUTHOR_NAME": "harnest driver",
    "GIT_AUTHOR_EMAIL": "harnest@localhost",
    "GIT_COMMITTER_NAME": "harnest driver",
    "GIT_COMMITTER_EMAIL": "harnest@localhost",
}


class Tree(NamedTuple):
    path: str
    base: str  # the main sha make() checked out: HARNEST_SESSION_BASE


def default_base_dir(harnest):
    harnest = os.path.realpath(str(harnest))
    return os.path.join(os.path.dirname(harnest), ".harnest-worktrees", os.path.basename(harnest))


def _sid(tree):
    return os.path.basename(os.path.normpath(tree))


def make(harnest, session_id, base_dir=None, say=print):
    """`git worktree add --detach <base_dir>/<session_id> main`; returns Tree(path, base).
    <base_dir> defaults to default_base_dir(harnest), outside the checkout. A tree left there
    by a session that died is stranded (its commits and changes kept on suite-stranded/<id>),
    then replaced."""
    harnest = str(harnest)
    tree = os.path.join(os.path.realpath(base_dir or default_base_dir(harnest)), session_id)
    if os.path.exists(tree):
        if git("-C", tree, "rev-parse", "--git-dir").returncode == 0:
            _strand(tree, "suite-stranded", "a stale tree from a session that did not land", say)
        remove(harnest, tree)
    git("-C", harnest, "worktree", "prune")
    os.makedirs(os.path.dirname(tree), exist_ok=True)
    base = git("-C", harnest, "rev-parse", "--verify", f"{BASE}^{{commit}}").stdout.strip()
    r = git("-C", harnest, "worktree", "add", "-q", "--detach", tree, base or BASE)
    if r.returncode != 0 or not base:
        raise RuntimeError(f"suite_tree.make: worktree add {tree} {BASE}: {r.stderr.strip()}")
    return Tree(tree, base)


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


def _dirty(tree):
    return bool(git("-C", tree, "status", "--porcelain").stdout.strip())


def _snapshot(tree):
    """A commit of the tree's whole working state (tracked, staged and untracked, not ignored)
    on top of its HEAD, built in a temporary index; HEAD itself when nothing is dirty."""
    head = git("-C", tree, "rev-parse", "HEAD").stdout.strip()
    if not _dirty(tree):
        return head
    fd, index = tempfile.mkstemp(prefix="suite-tree-index-")
    os.close(fd)
    try:
        env = {**os.environ, **STRAND_ENV, "GIT_INDEX_FILE": index}

        def run(*a):
            return subprocess.run(["git", "-C", tree, *a], env=env, capture_output=True, text=True)

        run("read-tree", "HEAD")
        run("add", "-A")
        obj = run("write-tree").stdout.strip()
        msg = f"stranded: what session {_sid(tree)} left in its tree"
        sha = run("commit-tree", obj, "-p", head, "-m", msg).stdout.strip()
        return sha or head
    finally:
        os.unlink(index)


def _free_branch(tree, prefix):
    """<prefix>/<session>, or -2, -3... when that is taken: a kept branch is never overwritten."""
    name = f"{prefix}/{_sid(tree)}"
    n = 1
    while (
        git("-C", tree, "show-ref", "--verify", "--quiet", f"refs/heads/{name if n == 1 else f'{name}-{n}'}").returncode
        == 0
    ):
        n += 1
    return name if n == 1 else f"{name}-{n}"


def _strand(tree, prefix, why, say, sha=None):
    """Keeps <sha> (default: a snapshot of the whole tree) on a new <prefix>/<session> branch
    and says an [audit] WARNING. Returns the branch."""
    sha = sha or _snapshot(tree)
    branch = _free_branch(tree, prefix)
    git("-C", tree, "branch", branch, sha)
    say(
        f"[audit] WARNING: suite work {sha[:9]} from session {_sid(tree)} did not land on {BASE} ({why}); "
        f"it is kept on branch {branch} for Don to merge"
    )
    return branch


def _in_paths(name, paths):
    for p in paths:
        if ("*" in p and fnmatch.fnmatchcase(name, p)) or name == p or name.startswith(p.rstrip("/") + "/"):
            return True
    return False


def land(harnest, tree, msg, name, email, say, suite_lock, paths=DEFAULT_PATHS, logs=None, kind="", base=None):
    """Under <suite_lock> (any context manager; the driver's `suite` token) lands what the
    session changed under <paths> in <tree> (a Tree, or a path with <base>) onto main.

    Returns one of:
      "landed"   the paths commit is on main; nothing else was left in the tree
      "clean"    nothing to land and nothing left over
      "conflict" the paths commit did not rebase (or main's checkout refused it): it is on
                 suite-conflict/<session>; leftovers, if any, were stranded too
      "stranded" something went on suite-stranded/<session> ([audit] WARNING said): the
                 session committed in its tree (nothing lands), the paths commit touched more
                 than <paths> (nothing lands), or files outside <paths> were left over (the
                 paths commit, if any, still lands)
    <kind> is the session kind ("curator:review" logs an approved removal at info level)."""
    harnest = str(harnest)
    if isinstance(tree, Tree):
        path, base = tree.path, base or tree.base
    else:
        path = str(tree)
    if not base:
        raise ValueError("suite_tree.land: no base sha (pass the Tree make() returned)")
    paths = list(paths)
    logs = logs or os.path.join(harnest, "logs")
    os.makedirs(logs, exist_ok=True)
    with suite_lock:
        head = git("-C", path, "rev-parse", "HEAD").stdout.strip()
        if head != base:
            _strand(
                path, "suite-stranded", f"the session committed in its tree (HEAD {head[:9]}, base {base[:9]})", say
            )
            return "stranded"
        suite.commit_changes(path, logs, paths, msg, name, email, say, kind=kind)
        sha = git("-C", path, "rev-parse", "HEAD").stdout.strip()
        stranded = False
        if _dirty(path):
            _strand(path, "suite-stranded", f"files outside {' '.join(paths)} were left in the tree", say)
            git("-C", path, "reset", "-q", "--hard", sha)
            git("-C", path, "clean", "-qfd")
            stranded = True
        if sha == base:
            return "stranded" if stranded else "clean"
        parent = git("-C", path, "rev-parse", f"{sha}^").stdout.strip()
        touched = git("-C", path, "diff", "--name-only", "--no-renames", base, sha).stdout.split("\n")
        stray = [f for f in touched if f and not _in_paths(f, paths)]
        if parent != base or stray:
            why = f"the landing commit touched {' '.join(stray) or 'more than one commit'} outside {' '.join(paths)}"
            _strand(path, "suite-stranded", why, say, sha=sha)
            return "stranded"
        done = "stranded" if stranded else "landed"
        new = sha
        for _ in range(FF_TRIES):
            tip = git("-C", path, "rev-parse", BASE).stdout.strip()
            if git("-C", path, "rebase", "-q", tip).returncode != 0:
                git("-C", path, "rebase", "--abort")
                git("-C", path, "reset", "-q", "--hard", sha)
                _strand(path, "suite-conflict", "rebase conflict", say, sha=sha)
                return "conflict"
            new = git("-C", path, "rev-parse", "HEAD").stdout.strip()
            if _fast_forward(harnest, new, tip):
                return done
            if git("-C", path, "rev-parse", BASE).stdout.strip() == tip:
                # main did not move: the checkout of main refused (local changes over these files)
                _strand(path, "suite-conflict", f"the checkout of {BASE} has local changes", say, sha=new)
                return "conflict"
        _strand(path, "suite-conflict", f"{BASE} kept moving", say, sha=new)
        return "conflict"
