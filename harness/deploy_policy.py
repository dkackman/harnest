"""When the scheduler deploys a server. A verify is runnable now when the
commit its fix landed in is already in the deployed head; the scheduler
deploys only when ready GPU work exists, none of it is runnable, and develop
differs from the deployed head outside the plugin tree. One deploy then
serves a whole burst of merges.
"""

from __future__ import annotations

import time

from .gitops import git

# The plugin tree refresh_plugin_tree serves; it follows origin/develop with
# no restart. Extend only from docs/harness/permissions.md's two deploy paths.
PLUGIN_ONLY = ("plugins/",)


def fix_commit(source_dir: str, issue: int) -> str | None:
    """Newest commit on origin/develop whose message names #<issue>, or None."""
    # git ERE has no portable \b on macOS; the group is the same word-end test.
    p = git(
        "-C", source_dir, "log", "origin/develop", "-E", f"--grep=#{issue}([^0-9A-Za-z_]|$)", "-n", "1", "--format=%H"
    )
    sha = p.stdout.strip()
    return sha if p.returncode == 0 and sha else None


def runnable_now(source_dir: str, issue: int, deployed: str) -> bool:
    fix = fix_commit(source_dir, issue)
    if fix is None:
        return False
    return git("-C", source_dir, "merge-base", "--is-ancestor", fix, deployed).returncode == 0


def server_paths_changed(source_dir: str, deployed: str, develop: str) -> bool:
    p = git("-C", source_dir, "diff", "--name-only", f"{deployed}..{develop}")
    if p.returncode != 0:
        return True  # cannot tell: deploying is the safe side
    return any(f and not f.startswith(PLUGIN_ONLY) for f in p.stdout.splitlines())


class DeployGate:
    def __init__(self, retry_secs: int, clock=time.monotonic):
        self.retry_secs = retry_secs
        self.clock = clock
        self.fails = 0
        self.retry_at: float | None = None

    def wanted(self, ready_gpu_issues: list[int], runnable: dict[int, bool], changed: bool) -> bool:
        if self.retry_at is not None and self.clock() < self.retry_at:
            return False
        if not ready_gpu_issues or any(runnable.get(i) for i in ready_gpu_issues):
            return False
        return changed

    def failed(self) -> str:
        self.fails += 1
        if self.fails == 1:
            self.retry_at = self.clock() + self.retry_secs
            return "retry"
        return "park"

    def succeeded(self) -> None:
        self.fails = 0
        self.retry_at = None
