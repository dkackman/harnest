"""The target profile (targets/<target>/profile.toml) and the server a run
talks to.

R8's vocabulary: a *target* is the product under test (dw), a *server* one
deployment of it (lem, mini-ai). harnest#15 called a server a "target", and
that name survives where it is a contract: the DW_TARGET knob, the
HARNEST_TARGET env the guard reads, the `target:` labels, and every state
file name.
"""
import os
import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from . import REPO

DEFAULT_TARGET = "dw"


class ProfileError(Exception):
    """A bad profile, or a knob that doesn't fit it. The message is what the
    bash drivers print on stderr for the same mistake."""


@dataclass(frozen=True)
class Server:
    name: str
    host: str
    dir: str            # the checkout on the host, ~-relative for the remote shell
    backend: str
    port: int
    primary: bool
    token_env: str = ""
    regression_all: tuple = ()
    regression_skip_cases: tuple = ()

    @property
    def suffix(self):
        """Appended to state files and the driver lock: "" for the primary,
        so every name a running lem loop holds is unchanged."""
        return "" if self.primary else f".{self.name}"

    @property
    def clone_suffix(self):
        """Appended to the agents' clones (dw-agent-mini-ai, ...)."""
        return "" if self.primary else f"-{self.name}"


@dataclass(frozen=True)
class Level:
    name: str
    file: str
    implies: str = ""


@dataclass
class Profile:
    raw: dict
    servers: list = field(default_factory=list)
    levels: list = field(default_factory=list)

    def get(self, dotted, default=None):
        cur = self.raw
        for part in dotted.split("."):
            if not isinstance(cur, dict) or part not in cur:
                return default
            cur = cur[part]
        return cur

    def server(self, name):
        for s in self.servers:
            if s.name == name:
                return s
        names = " ".join(s.name for s in self.servers)
        raise ProfileError(f"DW_TARGET must be one of: {names} (got '{name}')")

    def level(self, name):
        for lv in self.levels:
            if lv.name == name:
                return lv
        return None


def load(target=None, path=None):
    """The profile for <target> (HARNEST_PROFILE names a file instead, for
    tests and a second target)."""
    if path is None:
        path = os.environ.get("HARNEST_PROFILE") or REPO / "targets" / (target or DEFAULT_TARGET) / "profile.toml"
    path = Path(path)
    try:
        raw = tomllib.loads(path.read_text())
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise ProfileError(f"profile {path}: {e}") from e
    servers = []
    for i, s in enumerate(raw.get("servers", [])):
        try:
            servers.append(Server(
                name=s["name"], host=s["host"], dir=s["dir"], backend=s["backend"],
                port=int(s.get("port", 8765)), primary=(i == 0),
                token_env=s.get("token_env") or "DW_TOKEN_" + re.sub(r"[^A-Z0-9]", "_", s["name"].upper()),
                regression_all=tuple(s.get("regression_all", ())),
                regression_skip_cases=tuple(s.get("regression_skip_cases", ())),
            ))
        except KeyError as e:
            raise ProfileError(f"profile {path}: server {i} has no {e}") from e
    if not servers:
        raise ProfileError(f"profile {path}: no [[servers]]")
    levels = [Level(name=lv["name"], file=lv["file"], implies=lv.get("implies", ""))
              for lv in raw.get("suite", {}).get("levels", [])]
    return Profile(raw=raw, servers=servers, levels=levels)


_ENV_KEY = re.compile(r"DW_TOKEN(_[A-Z0-9_]*)?")


def load_env_file(path=None, environ=None, warn=None):
    """The secrets file into <environ> (os.environ by default), the way
    providers.sh's load_env_file reads it: HARNEST_ENV_FILE, default .env at
    the harness root; `KEY=value` lines, an optional `export `, `#` comments,
    one pair of matching quotes stripped; only DW_TOKEN and DW_TOKEN_* keys,
    any other ignored with a warning; a variable already set wins."""
    e = os.environ if environ is None else environ
    if path is None:
        path = e.get("HARNEST_ENV_FILE") or REPO / ".env"
    if warn is None:
        warn = lambda m: print(m, file=__import__("sys").stderr)
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return
    for line in text.split("\n"):
        line = line.rstrip("\r").lstrip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        key, val = key.rstrip(), val.strip()
        if not key.startswith("DW_TOKEN") or not (key == "DW_TOKEN" or key.startswith("DW_TOKEN_")):
            warn(f"{path}: '{key}' ignored: only DW_TOKEN and DW_TOKEN_* are read from it")
            continue
        if not _ENV_KEY.fullmatch(key):
            warn(f"{path}: '{key}' ignored: not a variable name")
            continue
        if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
            val = val[1:-1]
        if not e.get(key):
            e[key] = val


def resolve_token(server, environ=None):
    """The server's Bearer token, from the environment (after the secrets
    file, load_env_file): its own variable (token_env, e.g.
    DW_TOKEN_MINI_AI), else DW_TOKEN. No token is read from the profile."""
    e = os.environ if environ is None else environ
    if environ is None:
        load_env_file()
    token = e.get(server.token_env) or e.get("DW_TOKEN")
    if not token:
        raise ProfileError(f"no MCP token for DW_TARGET={server.name}: set {server.token_env} "
                           "(or DW_TOKEN) in the environment; no token is kept in the repo")
    return token


def url_host(url):
    """The host part of a URL ([::1] unbracketed)."""
    h = url.split("://", 1)[1] if "://" in url else url
    h = h.split("/", 1)[0]
    if h.startswith("["):
        return h[1:].split("]", 1)[0]
    return h.split(":", 1)[0]


def short_host(name):
    """A hostname lowercased and cut at its first dot: /api/health says
    "Mac-mini.lan", hostname(1) may say "Mac-mini" or "mac-mini.local"."""
    return name.split(".", 1)[0].lower()


def resolve_url(server, dw_url=""):
    """The server's MCP endpoint: DW_URL when set, else its own. A DW_URL
    naming another host is refused on a secondary server: one left over
    from a lem run would send this server's run at lem, under this
    server's lock, while lem's loop deploys to it."""
    url = dw_url or f"http://{server.host}:{server.port}/mcp"
    if not server.primary and short_host(url_host(url)) != short_host(server.host):
        raise ProfileError(f"DW_TARGET={server.name} needs a DW_URL on {server.host}, "
                           f"got {url} (unset DW_URL for the default)")
    return url
