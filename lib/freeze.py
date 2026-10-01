#!/usr/bin/env python3
"""dw's two stabilization switches, read from the dw checkout's origin/develop.

    python3 lib/freeze.py active <checkout>   exit 0 while frozen, 1 otherwise

- FREEZE (stage A): frozen while docs/stabilization/FREEZE exists, lifted by
  deleting it there. While frozen, the lead designs, decomposes and builds
  nothing, and a new file under SURFACE needs Don's `arch-approved`.
- The hot zone (stage C keeps it after the freeze): the paths
  docs/stabilization/hot-zone.txt lists, which no session's own commits may
  change, for as long as the file exists. dw uses it for whatever a refactor
  is restructuring.

Both are read through git from origin/develop, never the working tree or
the session's commit: a branch cannot unfreeze itself, and a branch cut
before a hot zone went live still sees it. The driver (dw_frozen in
providers.sh) and guard.py both call these, so there is one check per switch.
"""
import subprocess, sys

REF = "origin/develop"
FREEZE = "docs/stabilization/FREEZE"
HOT_ZONE = "docs/stabilization/hot-zone.txt"
# A new file under one of these is new surface (while frozen only).
SURFACE = ("dw/", "dw_mcp/", "workflows/", "prompts/", "plugins/")


def _git(checkout, *args):
    return subprocess.run(["git", "-C", checkout, *args], capture_output=True, text=True)


def _readable(checkout, fetch):
    if fetch:
        _git(checkout, "fetch", "-q", "origin", "develop")  # a failed fetch keeps the last ref
    return _git(checkout, "rev-parse", "-q", "--verify", REF + "^{commit}").returncode == 0


def frozen(checkout, fetch=True):
    """True while FREEZE is on origin/develop. False when it isn't, or
    origin/develop can't be read (no guessing)."""
    return _readable(checkout, fetch) and _git(checkout, "cat-file", "-e", "%s:%s" % (REF, FREEZE)).returncode == 0


def hot_zone(checkout, fetch=True):
    """The hot-zone entries on origin/develop, one path or dir/ prefix each,
    FREEZE or not; [] when the file (or origin/develop) isn't there."""
    if not _readable(checkout, fetch):
        return []
    text = _git(checkout, "show", "%s:%s" % (REF, HOT_ZONE)).stdout
    return [l.split("#", 1)[0].strip() for l in text.splitlines() if l.split("#", 1)[0].strip()]


def own_changes(checkout, src="HEAD", added=False):
    """Paths src's own commits change: three dots, from the merge base with
    origin/develop, so a develop merged into the branch isn't counted as its
    own. No rename detection: a move is a delete plus an add."""
    args = ["diff", "--name-only", "--no-renames"] + (["--diff-filter=A"] if added else [])
    return _git(checkout, *args, "%s...%s" % (REF, src)).stdout.split()


def violations(checkout, src="HEAD", hot=(), is_frozen=False):
    """(rule, path) pairs for src's own commits: 'hot-zone' always,
    'new-surface' only while frozen."""
    out = [("new-surface", p) for p in own_changes(checkout, src, added=True) if p.startswith(SURFACE)] if is_frozen else []
    for p in own_changes(checkout, src):
        if any(p == h or (h.endswith("/") and p.startswith(h)) for h in hot):
            out.append(("hot-zone", p))
    return out


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "active":
        sys.exit(0 if frozen(sys.argv[2]) else 1)
    sys.exit("usage: freeze.py active <checkout>")
