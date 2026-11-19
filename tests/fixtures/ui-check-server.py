"""The fixture server for tests/test-ui-check.sh: http.server over tests/fixtures/ui-check
on 127.0.0.1 (a random port, printed as "port N"). With a token argument, every
/api/* request must carry "Authorization: Bearer <token>" (401 otherwise), as a dw
started with an API token does. POST and the other writes answer 501 once past it.
/api/fetch/* are built here, for the fetch step: json, problem (+json), bad-json,
big (a JSON body over 256 KB), echo (the Authorization header it got, as JSON),
redirect (302 to /api/fetch/json?from=redirect) and redirect-off (302 to localhost).

    python3 -u ui-check-server.py <dir> [token]
"""

import functools
import http.server
import json
import sys

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

    def fetch_route(self):
        route = self.path.split("?")[0]
        if route == "/api/fetch/json":
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
