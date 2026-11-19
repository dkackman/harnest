"""When the scheduler deploys a server. A verify is runnable now when the
commit its fix landed in is already in the deployed head; the scheduler
deploys only when ready GPU work exists, none of it is runnable, and develop
differs from the deployed head outside the plugin tree. One deploy then
serves a whole burst of merges.
"""

from __future__ import annotations

import re
import time

from .gitops import git

# The plugin tree refresh_plugin_tree serves; it follows origin/develop with
# no restart. Extend only from docs/harness/permissions.md's two deploy paths.
PLUGIN_ONLY = ("plugins/",)


def head_sha(deployed: str) -> str | None:
    """Bare sha from deploy.run_deploy / deployed_head output ("<branch> @ <sha>",
    last line), or from a bare sha. None for "unknown" or anything unparseable."""
    lines = (deployed or "").strip().splitlines()
    if not lines:
        return None
    tok = lines[-1].rsplit("@", 1)[-1].strip()
    return tok if re.fullmatch(r"[0-9a-f]{4,40}", tok) else None


def _newest_match(source_dir: str, issue: int, *extra: str, timeout=None) -> str | None:
    # git ERE has no portable \b on macOS; the group is the same word-end test.
    p = git(
        "-C", source_dir, "log", "origin/develop", *extra, "-E",
        f"--grep=#{issue}([^0-9A-Za-z_]|$)", "-n", "1", "--format=%H", timeout=timeout,
    )  # fmt: skip
    sha = p.stdout.strip()
    return sha if p.returncode == 0 and sha else None


def fix_commit(source_dir: str, issue: int, timeout=None) -> str | None:
    """Newest commit on origin/develop whose message names #<issue>, or None.
    Non-merge commits win; a merge (whose (#N) is often a PR number) is used only
    when no non-merge commit matches. The caller must `git fetch` first."""
    return _newest_match(source_dir, issue, "--no-merges", timeout=timeout) or _newest_match(
        source_dir, issue, timeout=timeout
    )


def runnable_now(source_dir: str, issue: int, deployed: str, timeout=None) -> bool:
    """deployed is a bare sha or run_deploy's "<branch> @ <sha>". timeout
    bounds each git call (a timed-out one is "not runnable")."""
    sha = head_sha(deployed)
    if sha is None:
        return False
    fix = fix_commit(source_dir, issue, timeout=timeout)
    if sha is None or fix is None:
        return False
    return git("-C", source_dir, "merge-base", "--is-ancestor", fix, sha, timeout=timeout).returncode == 0


def server_paths_changed(source_dir: str, deployed: str, develop: str, timeout=None) -> bool:
    """deployed is a bare sha or run_deploy's "<branch> @ <sha>". timeout
    bounds the git call (a timed-out one is "changed")."""
    sha = head_sha(deployed)
    if sha is None:
        return True  # cannot tell: deploying is the safe side
    p = git("-C", source_dir, "diff", "--name-only", f"{sha}..{develop}", timeout=timeout)
    if p.returncode != 0:
        return True  # cannot tell: deploying is the safe side
    return any(f and not f.startswith(PLUGIN_ONLY) for f in p.stdout.splitlines())


STATES = ("idle", "waiting", "draining", "deploying", "failed")


class DeployGate:
    def __init__(self, retry_secs: int, clock=time.monotonic):
        self.retry_secs = retry_secs
        self.clock = clock
        self.fails = 0
        self.retry_at: float | None = None
        self.parked = False
        self.state = "idle"  # the driver sets waiting/draining/deploying

    def set_state(self, state: str) -> None:
        if state not in STATES:
            raise ValueError(f"deploy state {state!r} not in {STATES}")
        self.state = state

    def wanted(self, ready_gpu_issues: list[int], runnable: dict[int, bool], changed: bool) -> bool:
        if self.parked:
            return False
        if self.retry_at is not None and self.clock() < self.retry_at:
            return False
        if not ready_gpu_issues or any(runnable.get(i) for i in ready_gpu_issues):
            return False
        return changed

    def failed(self) -> str:
        self.fails += 1
        self.state = "failed"
        if self.fails == 1:
            self.retry_at = self.clock() + self.retry_secs
            return "retry"
        self.parked = True
        return "park"

    def succeeded(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.fails = 0
        self.retry_at = None
        self.parked = False
        self.state = "idle"
