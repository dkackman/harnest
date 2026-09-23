"""Minimal MCP client over streamable HTTP, standard library only.

Enough for the contract runner: initialize, list tools, call a tool. The
harness has no Python dependencies and this keeps it that way; it is a
consumer of the dw server exactly as the tester is, with no source or
`lem` access beyond the MCP endpoint.
"""
import json
import urllib.error
import urllib.request


class MCPError(Exception):
    pass


class MCPClient:
    def __init__(self, url, token=None, timeout=600):
        self.url = url
        self.token = token
        self.timeout = timeout
        self.session = None
        self._id = 0

    def _post(self, payload, want_reply=True):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers, method="POST")
        try:
            resp = urllib.request.urlopen(req, timeout=self.timeout)
        except urllib.error.HTTPError as e:
            raise MCPError(f"HTTP {e.code}: {e.read()[:500].decode(errors='ignore')}") from None
        with resp:
            self.session = resp.headers.get("Mcp-Session-Id") or self.session
            if not want_reply:
                return None
            ctype = resp.headers.get("Content-Type", "")
            if "text/event-stream" in ctype:
                # Read events until the one answering our request id.
                data = []
                for raw in resp:
                    line = raw.decode("utf-8", "ignore").rstrip("\r\n")
                    if line.startswith("data:"):
                        data.append(line[5:].lstrip())
                    elif line == "" and data:
                        msg = json.loads("\n".join(data))
                        data = []
                        if msg.get("id") == payload.get("id"):
                            return msg
                raise MCPError("event stream ended without a reply")
            return json.loads(resp.read() or b"null")

    def request(self, method, params=None):
        self._id += 1
        msg = self._post({"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}})
        if msg is None:
            raise MCPError(f"{method}: no reply")
        if "error" in msg:
            raise MCPError(f"{method}: {msg['error']}")
        return msg.get("result")

    def initialize(self):
        result = self.request("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "harnest-contract", "version": "1"},
        })
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"}, want_reply=False)
        return result

    def list_tools(self):
        return self.request("tools/list").get("tools", [])

    def call(self, tool, arguments=None):
        """Returns (is_error, value). value is the structured content when the
        server sends it, else the text content parsed as JSON when it parses,
        else the raw text."""
        res = self.request("tools/call", {"name": tool, "arguments": arguments or {}})
        is_error = bool(res.get("isError"))
        if res.get("structuredContent") is not None:
            value = res["structuredContent"]
            # FastMCP wraps non-object returns as {"result": ...}
            if isinstance(value, dict) and set(value) == {"result"}:
                value = value["result"]
            return is_error, value
        text = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        try:
            return is_error, json.loads(text)
        except ValueError:
            return is_error, text
