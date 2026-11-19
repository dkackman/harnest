"""The fixture server for tests/test-ui-check.sh: http.server over tests/fixtures/ui-check
on 127.0.0.1 (a random port, printed as "port N"). With a token argument, every
/api/* request must carry "Authorization: Bearer <token>" (401 otherwise), as a dw
started with an API token does. POST and the other writes answer 501 once past it.
/api/fetch/* are built here, for the fetch step: json, problem (+json), bad-json,
big (a JSON body over 256 KB), echo (the Authorization header it got, as JSON),
redirect (302 to /api/fetch/json?from=redirect), redirect-off (302 to localhost),
plain (text), deep (JSON nested past JSON.stringify), drip (a body that never ends),
stream (a chunked body with no end in sight), and, with a token, cut-token (the token
where the 256 KB cap cuts it) and leaky (the token in Location and the content type).
/openapi.json is built too.

    python3 -u ui-check-server.py <dir> [token]
"""

import functools
import http.server
import json
import sys
import time

TOKEN = sys.argv[2] if len(sys.argv) > 2 else ""


class Handler(http.server.SimpleHTTPRequestHandler):
    def authorized(self):
        if not TOKEN or not self.path.startswith("/api/"):
            return True
        if self.headers.get("Authorization") == "Bearer " + TOKEN:
            return True
        self.send_error(401, "no or wrong bearer token")
        return False

    def answer(self, status, ctype, body, location=None):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        if location:
            self.send_header("Location", location)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def chunked(self, ctype, pieces):
        # HTTP/1.1 chunked framing for this one response; the connection closes after it.
        self.protocol_version = "HTTP/1.1"
        self.close_connection = True
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            for piece in pieces:
                self.wfile.write(b"%x\r\n%s\r\n" % (len(piece), piece))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass

    def fetch_route(self):
        route = self.path.split("?")[0]
        cap = 262144
        if route == "/openapi.json":
            self.answer(200, "application/json", json.dumps({"openapi": "3.1.0", "paths": {}}))
        elif route == "/api/fetch/plain":
            self.answer(200, "text/plain; charset=utf-8", "plain text, not a page\n")
        elif route == "/api/fetch/deep":
            self.answer(200, "application/json", "[" * 120000 + "]" * 120000)
        elif route == "/api/fetch/drip":
            self.chunked("text/plain", (time.sleep(0.5) or b"tick\n" for _ in range(90)))
        elif route == "/api/fetch/stream":
            self.chunked("text/plain", (b"s" * 65536 for _ in range(128)))
        elif route == "/api/fetch/cut-token" and TOKEN:
            self.answer(200, "text/plain", "x" * (cap - (len(TOKEN) - 1)) + TOKEN + "tail")
        elif route == "/api/fetch/leaky" and TOKEN:
            pad = "a" * (200 - len("text/plain; p=") - (len(TOKEN) - 2))
            self.answer(302, "text/plain; p=" + pad + TOKEN, "moved", "/api/fetch/json?t=" + TOKEN)
        elif route == "/api/fetch/json":
            items = [{"name": "lora-a", "rank": 16, "tags": ["x"]}]
            self.answer(200, "application/json", json.dumps({"items": items, "query": self.path}))
        elif route == "/api/fetch/problem":
            self.answer(404, "application/problem+json; charset=utf-8", '{"detail": "no such lora"}')
        elif route == "/api/fetch/bad-json":
            self.answer(200, "application/json", '{"items": [1, 2')
        elif route == "/api/fetch/big":
            self.answer(200, "application/json", json.dumps({"pad": "a" * 300000}))
        elif route == "/api/fetch/echo":
            got = self.headers.get("Authorization", "")
            self.answer(200, "application/json", json.dumps({"you_sent": got}))
        elif route == "/api/fetch/redirect":
            self.answer(302, "text/plain", "moved", "/api/fetch/json?from=redirect")
        elif route == "/api/fetch/redirect-off":
            port = self.server.server_address[1]
            self.answer(302, "text/plain", "moved", "http://localhost:%d/elsewhere" % port)
        else:
            return False
        return True

    def do_GET(self):
        if self.authorized() and not self.fetch_route():
            super().do_GET()

    def do_HEAD(self):
        if self.authorized() and not self.fetch_route():
            super().do_HEAD()

    def write(self):
        if self.authorized():
            self.send_error(501, "unsupported method")

    do_POST = do_PUT = do_PATCH = do_DELETE = write


handler = functools.partial(Handler, directory=sys.argv[1])
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
print("serving on 127.0.0.1 port %d" % srv.server_address[1], flush=True)
srv.serve_forever()
