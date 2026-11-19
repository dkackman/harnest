"""git, as a subprocess (the test seam is a real git on throwaway repos)."""

import contextlib
import os
import signal
import subprocess

# A fetch over ssh must fail, not wait for a password or a dead host.
SSH_COMMAND = "ssh -o ConnectTimeout=10 -o BatchMode=yes"


def git(*args, cwd=None, check=False, timeout=None):
    """git <args>. With a timeout it runs in its own process group (with ssh
    told to give up and never to prompt), and past the timeout the group is
    killed and the result is exit 124, stderr saying so."""
    argv = ["git", *args]
    if timeout is None:
        return subprocess.run(argv, cwd=cwd, stdin=subprocess.DEVNULL, capture_output=True, text=True, check=check)
    env = os.environ.copy()
    env.setdefault("GIT_SSH_COMMAND", SSH_COMMAND)
    env["GIT_TERMINAL_PROMPT"] = "0"
    p = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors="replace",
        start_new_session=True,
    )
    try:
        out, errs = p.communicate(timeout=timeout)
        rc = p.returncode
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(p.pid, signal.SIGKILL)
        try:
            out, errs = p.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            out, errs = "", ""
        rc = 124
        errs = (errs or "") + f"git {' '.join(args[:3])}: timed out after {timeout}s\n"
    cp = subprocess.CompletedProcess(argv, rc, out or "", errs or "")
    if check:
        cp.check_returncode()
    return cp


def refresh_plugin_tree(src, tree, branch="develop", timeout=None):
    """A detached worktree of <src> at origin/<branch>, reset hard: the
    plugin the consumer roles load is the commit the server deploys, never
    whatever branch <src> has checked out. Returns its short commit, or
    None (leaving any existing tree alone) when the fetch fails. timeout
    bounds each git call."""
    src, tree = str(src), str(tree)
    if git("-C", src, "fetch", "-q", "origin", branch, timeout=timeout).returncode != 0:
        return None
    if not os.path.exists(os.path.join(tree, ".git")):
        # A tree deleted by hand stays registered, and `worktree add` then
        # refuses the path for good; prune forgets it.
        git("-C", src, "worktree", "prune", timeout=timeout)
        os.makedirs(os.path.dirname(tree) or ".", exist_ok=True)
        if (
            git("-C", src, "worktree", "add", "-q", "--detach", tree, f"origin/{branch}", timeout=timeout).returncode
            != 0
        ):
            return None
    if git("-C", tree, "checkout", "-q", "--detach", "--force", f"origin/{branch}", timeout=timeout).returncode != 0:
        return None
    return git("-C", tree, "rev-parse", "--short", "HEAD", timeout=timeout).stdout.strip()
