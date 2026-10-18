#!/usr/bin/env python3
"""A fake dw server for the offline tests: /api/health and just enough MCP
(initialize, list_models, list_assets, validate_workflow) over plain JSON,
on several ports at once, each answering as a different server.

    tests/fake-mcp.py <spec.json>

spec.json: {"<port>": {"hostname": "alpha", "device": "cuda", "workers": 2,
            "models": {"repo/id": 5.0}, "assets": ["qa-cast/a.wav"]}, ...}
Prints "ready" once every port listens; runs until killed.
"""

import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GB = 1024**3


def handler_for(spec):
    class H(BaseHTTPRequestHandler):
        def _json(self, obj):
            body = json.dumps(obj).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Mcp-Session-Id", "fake")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path != "/api/health":
                self.send_error(404)
                return
            workers = [{"device": spec["device"], "name": "fake", "vram_gb": 24, "alive": False}] * spec["workers"]
            self._json({"status": "ok", "hostname": spec["hostname"], "device": spec["device"], "workers": workers})

        def do_POST(self):
            msg = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
            if "id" not in msg:  # a notification
                self.send_response(202)
                self.end_headers()
                return
            if msg.get("method") == "initialize":
                result = {"protocolVersion": "2025-06-18", "capabilities": {}, "serverInfo": {"name": "fake"}}
            else:
                name = msg.get("params", {}).get("name")
                if name == "list_models":
                    value = {
                        "repos": [{"repo_id": r, "size_on_disk": int(gb * GB)} for r, gb in spec["models"].items()]
                    }
                elif name == "list_assets":
                    value = {"assets": [{"name": a, "reference": f"asset:{a}"} for a in spec.get("assets", [])]}
                elif name == "validate_workflow":
                    value = {"valid": True, "plan": {"downloads_required": []}}
                else:
                    value = {}
                result = {"content": [], "structuredContent": value, "isError": False}
            self._json({"jsonrpc": "2.0", "id": msg["id"], "result": result})

        def log_message(self, *a):
            pass

    return H


def main():
    spec = json.load(open(sys.argv[1]))
    for port, s in spec.items():
        srv = ThreadingHTTPServer(("127.0.0.1", int(port)), handler_for(s))
        threading.Thread(target=srv.serve_forever, daemon=True).start()
    print("ready", flush=True)
    threading.Event().wait()


if __name__ == "__main__":
    main()
