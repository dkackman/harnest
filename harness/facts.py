"""What a server *is*, asked of it at startup: its workers (from
/api/health) and what it holds (list_models, list_assets over MCP). The
profile says what a server may do; these say what it can, and check() is
where the two must agree.

The MCP client is contract/mcp_client.py, the stdlib client the contract
runner uses: a pure consumer, like the tester.
"""
import importlib.util
import json
import subprocess
from dataclasses import dataclass, field

from . import REPO
from .profile import short_host

GB = 1024 ** 3


def _client_class():
    spec = importlib.util.spec_from_file_location("harnest_mcp_client", REPO / "contract" / "mcp_client.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.MCPClient, mod.MCPError


class FactsError(Exception):
    pass


@dataclass
class ServerFacts:
    server: str
    hostname: str
    device: str
    workers: list                                 # [{"device", "name", "vram_gb", ...}]
    models: dict = field(default_factory=dict)    # repo id -> size in GB
    assets: set = field(default_factory=set)      # names, as `asset:<name>` takes them
    # workflow -> what validate_workflow says this server lacks for it:
    # {"missing": [{"repo", "gb", "blocked"}], "error": "" or why it can't validate}
    workflows: dict = field(default_factory=dict)

    @property
    def summary(self):
        w = ", ".join(f"{x.get('name', '?')} {x.get('vram_gb', '?')} GB" for x in self.workers) or "no workers"
        return (f"{self.server}: {self.device} on {self.hostname}, {len(self.workers)} worker(s) ({w}), "
                f"{len(self.models)} model(s) cached, {len(self.assets)} asset(s)")


def health_json(url, token):
    """/api/health, through curl (the test seam), or None. The token goes in on
    stdin (-H @-), never on the command line, where ps would show it."""
    base = url.rstrip("/")
    if base.endswith("/mcp"):
        base = base[:-4]
    try:
        p = subprocess.run(["curl", "-s", "-m", "5", "-H", "@-", f"{base}/api/health"],
                           input=f"Authorization: Bearer {token}\n", capture_output=True, text=True, timeout=30)
        h = json.loads(p.stdout) if p.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return h if isinstance(h, dict) and h.get("status") == "ok" else None


def mcp_inventory(url, token, asset_limit=5000):
    """(models {repo: GB}, asset names) from list_models and list_assets."""
    MCPClient, MCPError = _client_class()
    try:
        c = MCPClient(url, token, timeout=60)
        c.initialize()
        err, models = c.call("list_models", {})
        if err or not isinstance(models, dict):
            raise FactsError(f"list_models failed: {str(models)[:200]}")
        err, assets = c.call("list_assets", {"limit": asset_limit})
        if err or not isinstance(assets, dict):
            raise FactsError(f"list_assets failed: {str(assets)[:200]}")
    except (MCPError, OSError) as e:
        raise FactsError(str(e)) from e
    sizes = {r["repo_id"]: r.get("size_on_disk", 0) / GB for r in models.get("repos", []) if r.get("repo_id")}
    names = set()
    for a in assets.get("assets", []):
        for key in ("name", "reference"):
            v = a.get(key)
            if isinstance(v, str) and v:
                names.add(v[len("asset:"):] if v.startswith("asset:") else v)
    return sizes, names


def validate_workflows(url, token, names):
    """{workflow: {"missing": [...], "error": ...}} from validate_workflow,
    which is free: the server's own answer to "what would running this
    need that you don't have?" (plan.downloads_required, with each repo's
    full size and whether this box's Hugging Face token may fetch it)."""
    MCPClient, MCPError = _client_class()
    out = {}
    if not names:
        return out
    try:
        c = MCPClient(url, token, timeout=60)
        c.initialize()
        for name in names:
            try:
                err, v = c.call("validate_workflow", {"workflow_path": name})
            except MCPError as e:
                out[name] = {"missing": [], "error": str(e)[:200]}
                continue
            if err or not isinstance(v, dict) or not isinstance(v.get("plan"), dict):
                out[name] = {"missing": [], "error": (str(v) if err else "no plan")[:200]}
                continue
            out[name] = {"missing": [{"repo": d.get("repo"), "gb": d.get("gb") or 0,
                                      "blocked": bool(d.get("access_blocked"))}
                                     for d in v["plan"].get("downloads_required") or [] if d.get("repo")],
                         "error": ""}
    except (MCPError, OSError) as e:
        raise FactsError(str(e)) from e
    return out


def gather(server, url, token, health=health_json, inventory=mcp_inventory):
    """Every fact the dispatcher needs from one server. FactsError when it
    doesn't answer, or answers as another host."""
    h = health(url, token)
    if h is None:
        raise FactsError(f"no dw server answering at {url} (DW_TARGET={server.name})")
    host = h.get("hostname") or ""
    if short_host(host) != short_host(server.host):
        raise FactsError(f"the server at {url} is {host}, not {server.host}")
    models, assets = inventory(url, token)
    return ServerFacts(server=server.name, hostname=host, device=h.get("device") or "",
                       workers=[w for w in h.get("workers") or [] if isinstance(w, dict)],
                       models=models, assets=assets)


def check(server, facts):
    """Policy the facts can't meet, as messages (empty: they agree)."""
    problems = []
    if facts.device and server.backend and facts.device != server.backend:
        problems.append(f"{server.name}: the profile says {server.backend}, the server says {facts.device}")
    if server.lanes > max(1, len(facts.workers)):
        problems.append(f"{server.name}: {server.lanes} lanes but {len(facts.workers)} worker(s); "
                        "a lane is one job at a time on its own worker")
    return problems
