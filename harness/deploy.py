"""A server's state as the driver sees it: what it runs, whether it answers,
and how it is deployed. ssh and curl stay subprocesses (the test seams).
A port of providers.sh's deployed_head, target_health, target_preflight
and deploy_cmd.
"""

import json
import os
import subprocess

from .profile import short_host

SSH_OPTS = ["-o", "ConnectTimeout=8", "-o", "BatchMode=yes"]


def deployed_head(server):
    """ "<branch> @ <sha>" the server's checkout is on, or "unknown". The
    checkout is what the server runs: only deploy.sh moves it."""
    cmd = f'cd {server.dir} && echo "$(git branch --show-current) @ $(git rev-parse --short HEAD)"'
    # A local server's checkout is read here; ~ is the remote shell's on ssh.
    argv = (
        ["bash", "-c", cmd.replace("~", os.path.expanduser("~"), 1)]
        if server.local
        else ["ssh", *SSH_OPTS, server.host, cmd]
    )
    try:
        p = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"
    out = p.stdout.rstrip("\n")
    if p.returncode != 0:
        return (out + "\nunknown") if out else "unknown"
    return out


def deploy_cmd(server, branch="develop"):
    """The line prompts and the log show for a deploy."""
    return f"ssh -o ConnectTimeout=8 -o BatchMode=yes {server.host} '{server.dir}/scripts/deploy.sh {branch}'"


def health(url, token):
    """ "<device> on <hostname>" from the server's /api/health, or None when
    nothing answers ok."""
    base = url.rstrip("/")
    if base.endswith("/mcp"):
        base = base[:-4]
    try:
        p = subprocess.run(
            ["curl", "-s", "-m", "5", "-H", "@-", f"{base}/api/health"],
            input=f"Authorization: Bearer {token}\n",
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    try:
        h = json.loads(p.stdout)
    except ValueError:
        return None
    if not isinstance(h, dict) or h.get("status") != "ok":
        return None

    def s(v):
        return "null" if v is None else (v if isinstance(v, str) else json.dumps(v))

    return f"{s(h.get('device'))} on {s(h.get('hostname'))}"


class PreflightError(Exception):
    pass


def preflight(server, url, token):
    """For a secondary server: "<device> on <host>" when a server answers at
    <url> and names the server's own host. A tunnel or a stale DW_URL that
    reaches another box would otherwise run every level there."""
    got = health(url, token)
    if got is None:
        raise PreflightError(
            f"no dw server answering at {url} (DW_TARGET={server.name}): scripts/testbed.sh {server.name} start"
        )
    host = got.rsplit(" on ", 1)[-1]
    if short_host(host) != short_host(server.host):
        raise PreflightError(
            f"the server at {url} is {host}, not {server.host}: DW_TARGET={server.name} runs only against that host"
        )
    return got
