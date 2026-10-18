"""git, as a subprocess (the test seam is a real git on throwaway repos)."""

import os
import subprocess


def git(*args, cwd=None, check=False):
    return subprocess.run(
        ["git", *args], cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=check
    )


def refresh_plugin_tree(src, tree, branch="develop"):
    """A detached worktree of <src> at origin/<branch>, reset hard: the
    plugin the consumer roles load is the commit the server deploys, never
    whatever branch <src> has checked out. Returns its short commit, or
    None (leaving any existing tree alone) when the fetch fails."""
    src, tree = str(src), str(tree)
    if git("-C", src, "fetch", "-q", "origin", branch).returncode != 0:
        return None
    if not os.path.exists(os.path.join(tree, ".git")):
        # A tree deleted by hand stays registered, and `worktree add` then
        # refuses the path for good; prune forgets it.
        git("-C", src, "worktree", "prune")
        os.makedirs(os.path.dirname(tree) or ".", exist_ok=True)
        if git("-C", src, "worktree", "add", "-q", "--detach", tree, f"origin/{branch}").returncode != 0:
            return None
    if git("-C", tree, "checkout", "-q", "--detach", "--force", f"origin/{branch}").returncode != 0:
        return None
    return git("-C", tree, "rev-parse", "--short", "HEAD").stdout.strip()
