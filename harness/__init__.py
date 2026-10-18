"""The harness drivers in Python (roadmap R8).

Stdlib only, no venv: every external tool (claude, gh, git, ssh, curl)
stays a subprocess, so the offline suite's stubs on PATH keep working.
REPO is the harness checkout this package sits in.
"""
import os
from pathlib import Path


def _repo():
    """The checkout as the shell names it: bash's `cd "$(dirname ...)" &&
    pwd` keeps the logical path ($PWD), not the resolved one (/var, not
    /private/var on macOS), and that path is in log lines and prompts."""
    here = Path(os.path.abspath(__file__)).parent.parent
    pwd = os.environ.get("PWD", "")
    if pwd and os.path.realpath(pwd) == os.path.realpath(here):
        return Path(pwd)
    return here


REPO = _repo()
