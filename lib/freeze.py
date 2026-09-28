#!/usr/bin/env python3
"""dw's stabilization freeze, read from the dw checkout (stage A; stage B's
permanent guardrails replace it at dw's Phase 4 gate).

    python3 lib/freeze.py active <checkout>   exit 0 while frozen, 1 otherwise

The switch is dw's, not the harness's: frozen while
docs/stabilization/FREEZE exists on origin/develop, and lifted by deleting
it there. Always read through git, never the working tree, which may be on
any branch (or stale): a branch cannot unfreeze itself by deleting the file.
The driver (dw_frozen in providers.sh) and guard.py both call freeze_state,
so there is one check.
"""
import subprocess, sys

REF = "origin/develop"
FREEZE = "docs/stabilization/FREEZE"
HOT_ZONE = "docs/stabilization/hot-zone.txt"
# A new file under one of these is new surface.
SURFACE = ("dw/", "dw_mcp/", "workflows/", "prompts/", "plugins/")


def _git(checkout, *args):
    return subprocess.run(["git", "-C", checkout, *args], capture_output=True, text=True)


def freeze_state(checkout, fetch=True):
    """None when not frozen (or origin/develop can't be read: no guessing),
    else the hot-zone entries on origin/develop, one path or dir/ prefix each."""
    if fetch:
        _git(checkout, "fetch", "-q", "origin", "develop")  # a failed fetch keeps the last ref
    if _git(checkout, "rev-parse", "-q", "--verify", REF + "^{commit}").returncode != 0:
        return None
    if _git(checkout, "cat-file", "-e", "%s:%s" % (REF, FREEZE)).returncode != 0:
        return None
    text = _git(checkout, "show", "%s:%s" % (REF, HOT_ZONE)).stdout
    return [l.split("#", 1)[0].strip() for l in text.splitlines() if l.split("#", 1)[0].strip()]


def own_changes(checkout, src="HEAD", added=False):
    """Paths src's own commits change: three dots, from the merge base with
    origin/develop, so a develop merged into the branch isn't counted as its
    own. No rename detection: a move is a delete plus an add."""
    args = ["diff", "--name-only", "--no-renames"] + (["--diff-filter=A"] if added else [])
    return _git(checkout, *args, "%s...%s" % (REF, src)).stdout.split()


def violations(checkout, src="HEAD", hot_zone=()):
    """(rule, path) pairs for src's own commits: 'new-surface' or 'hot-zone'."""
    out = [("new-surface", p) for p in own_changes(checkout, src, added=True) if p.startswith(SURFACE)]
    for p in own_changes(checkout, src):
        if any(p == h or (h.endswith("/") and p.startswith(h)) for h in hot_zone):
            out.append(("hot-zone", p))
    return out


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "active":
        sys.exit(0 if freeze_state(sys.argv[2]) is not None else 1)
    sys.exit("usage: freeze.py active <checkout>")
