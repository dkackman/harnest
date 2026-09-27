#!/usr/bin/env python3
"""A local, read-only dashboard of what the harness drivers are doing.

    python3 dashboard/serve.py [--port 8780]     # then open http://127.0.0.1:8780

Standard library only. It reads what the drivers already write - the
processes, the driver locks, the `=== ... ===` session headers and `[tag]`
lines in logs/loop.log and logs/loop.local.log, the `usage:` line that
closes each session, and a release's gates.out - and never writes, calls
gh or ssh, or touches a lock. The page polls /api/state and /api/log.
"""

import argparse
import json
import os
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / "logs"
PAGE = Path(__file__).resolve().parent / "index.html"

DRIVER_RE = re.compile(
    r"run-(loop|regression|features|release|curate|retro|digest|bench)\.sh(\s.*)?$"
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
        if m and "grep" not in cmd:
            rows[pid] = {
                "pid": int(pid), "ppid": ppid, "elapsed": etime.strip(),
                "driver": m.group(1), "args": (m.group(2) or "").strip(),
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
    return {
        "now": time.time(),
        "drivers": procs,
        "claude_sessions": claude,
        "streams": streams,
        "stop_flags": flags,
        "release": release(),
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

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/":
                self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
            elif u.path == "/api/state":
                self._json(state())
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
