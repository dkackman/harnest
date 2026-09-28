#!/usr/bin/env python3
"""A local, read-only dashboard of what the harness drivers are doing.

    python3 dashboard/serve.py [--port 8780]     # then open http://127.0.0.1:8780
    python3 dashboard/serve.py --host 0.0.0.0    # also from the LAN, never beyond it

Standard library only. It reads what the drivers already write - the
processes, the driver locks, the `=== ... ===` session headers and `[tag]`
lines in logs/loop.log and logs/loop.local.log, the `usage:` line that
closes each session, and a release's gates.out - and never writes, calls
ssh, or touches a lock. Its one outside call is read-only `gh` for what
waits on Don (Attention), made once the loops settle after a session
starts or ends, no more than once a minute, and at least every
ATTN_MAX_SECS. The page polls /api/state and
/api/log.
"""

import argparse
import ipaddress
import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / "logs"
PAGE = Path(__file__).resolve().parent / "index.html"

# The script must be what runs (`bash ./run-loop.sh …` or `./run-loop.sh …`),
# not an argument: test-lint's shellcheck names every driver on one line
DRIVER_RE = re.compile(
    r"^(?:(?:\S*/)?(?:ba|z)?sh\s+)?"
    r"(\S*run-(loop|regression|features|release|curate|retro|digest|bench)\.sh)(\s.*)?$"
)
HEADER_RE = re.compile(r"^=== (\d\d:\d\d:\d\d) (.*?) ===$")
TAG_RE = re.compile(r"^\[([^\]]+)\] (.*)$")
USAGE_RE = re.compile(
    r"turns=(\d+) duration=(\d+)s cost=\$([\d.]+) ctx_peak=([\d.]+k?)"
)
CTX_RE = re.compile(r"· ctx=([\d.]+k?)")

# The two combined streams, one per server target
STREAMS = {"lem": "loop.log", "mac": "loop.local.log"}
LOCKS = {"lem": ".driver.lock", "mac": ".driver.lock.local"}
LOG_TAIL_BYTES = 64 * 1024

TICKET_REPO = os.environ.get("TICKET_REPO", "dkackman/diffusers-workflow")
HARNESS_REPO = os.environ.get("HARNESS_REPO", "dkackman/harnest")
# Each fetch is four gh calls (GraphQL and REST). The loops share the
# account's rate limit, so this stays well under 5% of it.
ATTN_SETTLE_SECS = 20  # debounce: the loops must be quiet this long after a transition
ATTN_MIN_SECS = 60  # never re-ask GitHub sooner than this
ATTN_FORCE_MIN_SECS = 15  # the refresh link's floor
ATTN_MAX_SECS = 300  # and never go longer, loops or not
ATTN_LIMITED_SECS = 900  # after a rate-limit answer, leave GitHub alone this long
ISSUE_FIELDS = "number,title,labels,updatedAt,url,blockedBy"


class StreamIndex:
    """What a combined log says, read incrementally: only the bytes added
    since the last poll are parsed, so a 13 MB loop.log costs one full read
    at startup and a few KB after that."""

    def __init__(self, path):
        self.path = path
        self.offset = 0
        self.inode = None
        self.partial = b""
        self.sessions = []  # dicts, oldest first; the last is the latest
        self.by_tag = {}  # tag -> its latest session dict
        self.run_header = None

    def _session(self, when, label, tag):
        s = {
            "time": when,
            "label": label,
            "tag": tag,
            "turns": 0,
            "ctx": None,
            "last_tool": None,
            "last_line": None,
            "model": None,
            "usage": None,
        }
        self.sessions.append(s)
        del self.sessions[:-300]
        self.by_tag[tag] = s
        return s

    def _line(self, line):
        m = HEADER_RE.match(line)
        if m:
            when, label = m.groups()
            if label.startswith("cycle ") or " run (" in label:
                # A cycle or run banner: context for the sessions under it,
                # whose tags ([implementer], [tester:#N]) start afresh
                self.run_header = {"time": when, "label": label}
                self.by_tag = {}
            else:
                self._session(when, label, label.split(" (")[0])
            return
        m = TAG_RE.match(line)
        if not m:
            return
        tag, rest = m.groups()
        s = self.by_tag.get(tag)
        if s is None:
            # a session with no header of its own (implementer:#N in a cycle)
            when = self.run_header["time"] if self.run_header else "--:--:--"
            s = self._session(when, tag, tag)
        if rest.startswith("usage: "):
            u = USAGE_RE.search(rest)
            if u:
                s["usage"] = {
                    "turns": int(u.group(1)),
                    "duration": int(u.group(2)),
                    "cost": float(u.group(3)),
                    "ctx_peak": u.group(4),
                }
            return
        if rest.startswith("model: "):
            s["model"] = rest[7:].strip()
            return
        c = CTX_RE.match(rest)
        if c:
            s["turns"] += 1
            s["ctx"] = c.group(1)
            return
        if rest.startswith("> "):
            s["last_tool"] = rest[2:200]
        elif not rest.startswith("< "):
            s["last_line"] = rest[:300]

    def refresh(self):
        try:
            st = self.path.stat()
        except FileNotFoundError:
            return
        if st.st_ino != self.inode or st.st_size < self.offset:
            self.__init__(self.path)
            self.inode = st.st_ino
        if st.st_size == self.offset:
            return
        with open(self.path, "rb") as f:
            f.seek(self.offset)
            data = self.partial + f.read()
            self.offset = f.tell()
        lines = data.split(b"\n")
        self.partial = lines.pop()
        for raw in lines:
            self._line(raw.decode("utf-8", "replace"))


INDEXES = {name: StreamIndex(LOGS / f) for name, f in STREAMS.items()}


def _gh(args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=60)
    if r.returncode:
        said = (r.stderr or r.stdout).strip().splitlines()
        raise RuntimeError(said[-1] if said else f"gh exit {r.returncode}")
    return json.loads(r.stdout or "[]")


def _issues(repo, *labels):
    args = ["issue", "list", "--repo", repo, "--state", "open", "--limit", "100", "--json", ISSUE_FIELDS]
    for label in labels:
        args += ["--label", label]
    return _gh(args)


class Attention:
    """What waits on Don, from GitHub: owner:don on both repos, harness
    proposals awaiting approval, and draft security advisories. Fetched in a
    background thread when the loops move (a session starts or ends), so a
    poll of /api/state never waits on gh."""

    def __init__(self):
        self.mu = threading.Lock()
        self.items, self.errors = [], []
        self.fetched = 0.0
        self.key = None  # the loop state the last fetch saw
        self.seen, self.changed = None, 0.0  # the latest loop state, and when it last moved
        self.hold_until = 0.0
        self.busy = False

    def poke(self, key, force=False):
        """Called on every /api/state poll; fetches only when a rule says so.
        A burst of transitions (a session ending, the next starting) is one
        fetch, ATTN_SETTLE_SECS after the last of them."""
        with self.mu:
            now = time.time()
            if key != self.seen:
                self.seen, self.changed = key, now
            if self.busy or now < self.hold_until:
                return
            since = now - self.fetched
            settled = key != self.key and now - self.changed >= ATTN_SETTLE_SECS
            if not (
                since >= ATTN_MAX_SECS
                or (settled and since >= ATTN_MIN_SECS)
                or (force and since >= ATTN_FORCE_MIN_SECS)
            ):
                return
            self.busy, self.key = True, key
        threading.Thread(target=self._fetch, daemon=True).start()

    def _fetch(self):
        items, errors = [], []

        def issues(repo, name, *queries):
            seen = set()
            for labels in queries:
                try:
                    for i in _issues(repo, *labels):
                        if i["number"] in seen:
                            continue
                        seen.add(i["number"])
                        names = [lb["name"] for lb in i["labels"]]
                        items.append({
                            "repo": name, "number": i["number"], "title": i["title"], "url": i["url"],
                            "updated": i["updatedAt"],
                            "tags": [n for n in names if not n.startswith("owner:")],
                            # open blockers: nothing to decide until they close
                            "waiting": [
                                {"number": b["number"], "url": b["url"]}
                                for b in (i.get("blockedBy") or {}).get("nodes") or []
                                if b.get("state") == "OPEN"
                            ],
                        })
                except Exception as e:  # noqa: BLE001 - shown on the card
                    errors.append(f"{name}: {e}")

        issues(TICKET_REPO, "dw", ["owner:don"])
        issues(HARNESS_REPO, "harnest", ["owner:don"], ["harness", "status:needs-approval"])
        try:
            for a in _gh(["api", f"repos/{TICKET_REPO}/security-advisories?state=draft&per_page=100"]):
                items.append({
                    "repo": "advisory", "number": a["ghsa_id"], "title": a.get("summary") or "",
                    "url": a["html_url"], "updated": a.get("updated_at") or "",
                    "tags": [a.get("severity") or "no severity"],
                    "waiting": [],
                })
        except Exception as e:  # noqa: BLE001
            errors.append(f"advisories: {e}")
        with self.mu:
            now = time.time()
            if any("rate limit" in e.lower() for e in errors):
                self.hold_until = now + ATTN_LIMITED_SECS
                errors.append(f"GitHub rate limit: not asking again for {ATTN_LIMITED_SECS // 60} min")
                items = items or self.items  # keep showing the last good list
            self.items, self.errors = items, errors
            self.fetched, self.busy = now, False

    def snapshot(self):
        with self.mu:
            return {
                "items": self.items, "errors": self.errors, "fetched": self.fetched or None, "busy": self.busy,
                "held_until": self.hold_until if self.hold_until > time.time() else None,
            }


ATTENTION = Attention()


def _loop_key():
    """Changes when a session starts or ends, or a cycle begins, in either loop."""
    key = []
    for idx in INDEXES.values():
        last = idx.sessions[-1] if idx.sessions else None
        key.append((
            idx.run_header and idx.run_header["time"],
            last and (last["time"], last["label"], last["usage"] is not None),
        ))
    return tuple(key)


def processes():
    """Running drivers, one row per driver. A driver's own subshells share
    its command line and are left out; a driver another started (release
    gates running run-regression.sh) is listed with its parent's pid."""
    try:
        out = subprocess.run(
            ["ps", "-axo", "pid=,ppid=,etime=,command="],
            capture_output=True, text=True, timeout=5,
        ).stdout
    except Exception:
        return [], 0
    rows, claude = {}, 0
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        pid, ppid, etime, cmd = parts
        if re.search(r"(^|/)claude\s.*(-p|--print)\b", cmd):
            claude += 1
        m = DRIVER_RE.search(cmd)
        if m and _is_ours(pid, m.group(1)):
            rows[pid] = {
                "pid": int(pid), "ppid": ppid, "elapsed": etime.strip(),
                "driver": m.group(2), "args": (m.group(3) or "").strip(),
                "local": "DW_TARGET=local" in cmd, "cmd": cmd,
            }

    def outer(r):
        # climb past subshells of the same command
        while r["ppid"] in rows and rows[r["ppid"]]["cmd"] == r["cmd"]:
            r = rows[r["ppid"]]
        return r

    top = [r for r in rows.values() if outer(r) is r]
    for r in top:
        p = rows.get(r["ppid"])
        r["parent"] = outer(p)["pid"] if p else None
    # a driver started from a shell's subshell: find its driver ancestor
    for r in top:
        if r["parent"] is None:
            r["parent"] = _driver_ancestor(r["ppid"], {x["pid"] for x in top})
    for r in top:
        del r["cmd"]
    for r in top:
        r["local"] = r["local"] or _env_says_local(r["pid"])
    return sorted(top, key=lambda r: r["pid"]), claude


_OURS = {}


def _is_ours(pid, script):
    """True when the script is this checkout's: tests/test-drivers.sh runs
    the real drivers from a copy of the harness in a temp dir."""
    key = (pid, script)
    if key not in _OURS:
        path = Path(script)
        if not path.is_absolute():
            cwd = _cwd(pid)
            path = Path(cwd) / path if cwd else None
        try:
            _OURS[key] = bool(path) and path.resolve().parent == ROOT
        except OSError:
            _OURS[key] = False
        if len(_OURS) > 2000:
            _OURS.clear()
    return _OURS[key]


def _cwd(pid):
    try:
        out = subprocess.run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"],
                             capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return None
    return next((l[1:] for l in out.splitlines() if l.startswith("n")), None)


def _driver_ancestor(ppid, drivers):
    """The nearest driver above a process, through at most six parents."""
    for _ in range(6):
        if not ppid or ppid in ("0", "1"):
            return None
        if int(ppid) in drivers:
            return int(ppid)
        try:
            ppid = subprocess.run(["ps", "-o", "ppid=", "-p", str(ppid)],
                                  capture_output=True, text=True, timeout=3).stdout.strip()
        except Exception:
            return None
    return None


def _env_says_local(pid):
    try:
        out = subprocess.run(
            ["ps", "eww", "-o", "command=", "-p", str(pid)],
            capture_output=True, text=True, timeout=3,
        ).stdout
        return "DW_TARGET=local" in out
    except Exception:
        return False


def lock(name):
    owner = LOGS / name / "owner"
    try:
        text = owner.read_text().strip()
    except (FileNotFoundError, NotADirectoryError):
        return None
    pid = text.split()[0] if text else ""
    alive = False
    if pid.isdigit():
        try:
            os.kill(int(pid), 0)
            alive = True
        except OSError:
            pass
    return {"owner": text, "alive": alive}


def release():
    """The newest release's gate log, if one ran in the last day."""
    dirs = sorted(LOGS.glob("release-*/gates.out"), key=lambda p: p.stat().st_mtime)
    if not dirs:
        return None
    p = dirs[-1]
    if time.time() - p.stat().st_mtime > 86400:
        return None
    lines = [l for l in p.read_text(errors="replace").splitlines() if l.startswith("[release ")]
    return {"file": str(p.relative_to(LOGS)), "lines": lines[-12:], "mtime": p.stat().st_mtime}


def state():
    procs, claude = processes()
    streams = {}
    for name, idx in INDEXES.items():
        idx.refresh()
        try:
            mtime = idx.path.stat().st_mtime
        except FileNotFoundError:
            mtime = None
        recent = [dict(s) for s in idx.sessions[-40:]]
        streams[name] = {
            "file": STREAMS[name],
            "mtime": mtime,
            "lock": lock(LOCKS[name]),
            "run": idx.run_header,
            "sessions": recent,
        }
    flags = sorted(p.name for p in LOGS.glob("stop-after-cycle*"))
    ATTENTION.poke(_loop_key())
    return {
        "now": time.time(),
        "drivers": procs,
        "claude_sessions": claude,
        "streams": streams,
        "stop_flags": flags,
        "release": release(),
        "attention": ATTENTION.snapshot(),
    }


def log_files():
    files = []
    for p in list(LOGS.glob("*.log")) + list(LOGS.glob("*.out")) + list(LOGS.glob("release-*/*.out")) + list(LOGS.glob("release-*/*.log")):
        st = p.stat()
        files.append({"name": str(p.relative_to(LOGS)), "size": st.st_size, "mtime": st.st_mtime})
    return sorted(files, key=lambda f: -f["mtime"])


def read_log(name, offset):
    """Bytes of logs/<name> from <offset>, or its last 64 KB when offset is
    -1. Only files log_files() lists are served."""
    allowed = {f["name"] for f in log_files()}
    if name not in allowed:
        return None
    p = LOGS / name
    size = p.stat().st_size
    tail = not 0 <= offset <= size
    start = max(0, size - LOG_TAIL_BYTES) if tail else offset
    with open(p, "rb") as f:
        f.seek(start)
        data = f.read(min(size - start, 2 * 1024 * 1024))
    if tail and start > 0:
        # started mid-line: drop the fragment
        nl = data.find(b"\n") + 1
        data, start = data[nl:], start + nl
    # whole lines only; a partial last line arrives with the next poll
    cut = data.rfind(b"\n") + 1
    return {"offset": start + cut, "text": data[:cut].decode("utf-8", "replace"), "size": size}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj).encode(), "application/json")

    def _local_only(self):
        """Refuse anyone off the local network, whatever --host binds to:
        a router port-forward must not make this page public. The Host
        check stops DNS rebinding (a web page's own domain pointed here),
        so only an IP, localhost or a .local name reaches the page."""
        try:
            peer = ipaddress.ip_address(self.client_address[0])
        except ValueError:
            peer = None
        if peer and getattr(peer, "ipv4_mapped", None):
            peer = peer.ipv4_mapped
        host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]").lower()
        try:
            ipaddress.ip_address(host)
            host_ok = True
        except ValueError:
            host_ok = host == "localhost" or host.endswith(".local")
        if peer and (peer.is_loopback or peer.is_private or peer.is_link_local) and host_ok:
            return True
        self._send(403, b"local network only", "text/plain")
        return False

    def do_GET(self):
        if not self._local_only():
            return
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/":
                self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            elif u.path == "/api/state":
                self._json(state())
            elif u.path == "/api/attention":
                ATTENTION.poke(_loop_key(), force=True)
                self._json(ATTENTION.snapshot())
            elif u.path == "/api/logs":
                self._json(log_files())
            elif u.path == "/api/log":
                res = read_log(q.get("file", [""])[0], int(q.get("offset", ["-1"])[0]))
                self._json(res) if res else self._json({"error": "no such log"}, 404)
            else:
                self._send(404, b"not found", "text/plain")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=int(os.environ.get("DASHBOARD_PORT", "8780")))
    ap.add_argument("--host", default="127.0.0.1")
    args = ap.parse_args()
    for idx in INDEXES.values():
        idx.refresh()
    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"harnest dashboard on http://{args.host}:{args.port}  (logs: {LOGS})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
