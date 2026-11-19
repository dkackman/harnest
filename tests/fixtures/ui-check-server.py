"""The fixture server for tests/test-ui-check.sh: http.server over tests/fixtures/ui-check
on 127.0.0.1 (a random port, printed as "port N"). With a token argument, every
/api/* request must carry "Authorization: Bearer <token>" (401 otherwise), as a dw
started with an API token does. POST and the other writes answer 501 once past it.

    python3 -u ui-check-server.py <dir> [token]
"""

import functools
import http.server
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

    def do_GET(self):
        if self.authorized():
            super().do_GET()

    def do_HEAD(self):
        if self.authorized():
            super().do_HEAD()

    def write(self):
        if self.authorized():
            self.send_error(501, "unsupported method")

    do_POST = do_PUT = do_PATCH = do_DELETE = write


handler = functools.partial(Handler, directory=sys.argv[1])
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
print("serving on 127.0.0.1 port %d" % srv.server_address[1], flush=True)
srv.serve_forever()
