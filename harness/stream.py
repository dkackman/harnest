"""claude's stream-json, rendered: a port of providers.sh's render_stream
(the jq program in _STREAM_RENDER_JQ), line for line.

Its output is a contract (spec, "The log format is a contract"): the
dashboard, the curator's chunk cost table, the retro, the bench and the
driver tests all parse it, and tests/fixtures/stream.expected is the golden
test. So jq's own formatting is reproduced here: numbers print the way jq
1.7 prints them, `round` rounds half away from zero, `tojson` is compact
and keeps key order, and a null interpolates as "null".

An event the renderer can't handle prints a `render-error:` line instead of
stopping, as the jq does: a renderer that died would take claude's output
with it mid-session.
"""

import json
import math
import time


class _JqError(Exception):
    pass


def _idx(obj, key):
    """jq's .key: null on null, an error on anything but an object."""
    if obj is None:
        return None
    if isinstance(obj, dict):
        return obj.get(key)
    raise _JqError(f'Cannot index {_jtype(obj)} with "{key}"')


def _iter(obj):
    """jq's .[]."""
    if isinstance(obj, list):
        return list(obj)
    if isinstance(obj, dict):
        return list(obj.values())
    raise _JqError(f"Cannot iterate over {_jtype(obj)}" + ("" if obj is None else f" ({tojson(obj)})"))


def _jtype(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    return "object"


def _truthy(v):
    return v is not None and v is not False


def _alt(v, default):
    """jq's //: the default for null and false."""
    return v if _truthy(v) else default


def _num(x):
    """A number as jq 1.7 prints it: integral values without a decimal
    point, others in shortest round-trip form."""
    if isinstance(x, bool):
        return "true" if x else "false"
    if isinstance(x, int):
        return str(x)
    if isinstance(x, float):
        if math.isfinite(x) and x.is_integer() and abs(x) < 1e17:
            return str(int(x))
        if x != x:
            return "null"
        if math.isinf(x):
            return "1.7976931348623157e+308" if x > 0 else "-1.7976931348623157e+308"
        return repr(x)
    raise _JqError(f"{_jtype(x)} is not a number")


def _round(x):
    """jq's round: half away from zero."""
    if not isinstance(x, (int, float)) or isinstance(x, bool):
        raise _JqError(f"{_jtype(x)} ({tojson(x)}) number required")
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def _add(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if (
        isinstance(a, (int, float))
        and isinstance(b, (int, float))
        and not isinstance(a, bool)
        and not isinstance(b, bool)
    ):
        return a + b
    raise _JqError(f"{_jtype(a)} and {_jtype(b)} cannot be added")


def _jstr(s):
    return json.dumps(s, ensure_ascii=False).replace("\x7f", "\\u007f")


def tojson(v):
    """jq's tojson: compact, key order kept."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return _num(v)
    if isinstance(v, str):
        return _jstr(v)
    if isinstance(v, list):
        return "[" + ",".join(tojson(x) for x in v) + "]"
    return "{" + ",".join(_jstr(k) + ":" + tojson(x) for k, x in v.items()) + "}"


def _tostring(v):
    """jq's string interpolation / tostring: a string as itself, else tojson."""
    return v if isinstance(v, str) else tojson(v)


def _k(x):
    if x is None:
        return "0"
    if isinstance(x, (int, float)) and not isinstance(x, bool) and x >= 1000:
        return _num(_round(x / 100) / 10) + "k"
    return _tostring(x)


def _usd(x):
    x = _alt(x, 0)
    if not isinstance(x, (int, float)) or isinstance(x, bool):
        raise _JqError(f"{_jtype(x)} ({tojson(x)}) and number cannot be multiplied")
    return _round(x * 100) / 100


def _ctx(usage):
    total = 0
    for key in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
        total = _add(total, _alt(_idx(usage, key), 0))
    return total


def _trunc(s, n):
    if not isinstance(s, str):
        raise _JqError(f"{_jtype(s)} cannot be truncated")
    return s[:n] + "…" if len(s) > n else s


def _result_len(c):
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        total = None
        for x in c:
            t = _alt(_idx(x, "text"), "")
            if not isinstance(t, str):
                raise _JqError(f"{_jtype(t)} has no length")
            total = _add(total, len(t))
        return _alt(total, 0)
    return len(tojson(c))


def _todate(epoch):
    if not isinstance(epoch, (int, float)) or isinstance(epoch, bool):
        raise _JqError("strftime/1 requires parsed datetime inputs")
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(math.floor(epoch)))


class Renderer:
    """Feed it one raw output line at a time; each call returns the rendered
    lines for it (possibly none)."""

    def __init__(self):
        self.id = None
        self.max = 0

    def feed(self, line):
        prev = (self.id, self.max)
        try:
            j = self._parse(line)
            newmsg = False
            if _idx(j, "type") == "assistant":
                msg = _idx(j, "message")
                newmsg = _idx(msg, "id") != self.id
                self.id = _idx(msg, "id")
                c = _ctx(_idx(msg, "usage"))
                if not isinstance(c, (int, float)):
                    raise _JqError("max of mixed types")
                self.max = max(self.max, c)
            elif not isinstance(j, dict) and j is not None:
                _idx(j, "type")  # raises, as jq's .type would
        except _JqError:
            self.id, self.max = prev
            j, newmsg = {"type": "raw", "line": "render-error: " + line}, False
        out = []
        try:
            self._render(j, newmsg, out)
        except _JqError as e:
            out.append(f"render-error: {e}")
        return out

    @staticmethod
    def _parse(line):
        try:
            j = json.loads(line)
        except ValueError:
            j = None
        return _alt(j, {"type": "raw", "line": line})

    def _render(self, j, newmsg, out):
        t = _idx(j, "type")
        if t == "raw":
            out.append(_tostring(_idx(j, "line")))
        elif t == "system" and _idx(j, "subtype") == "init":
            out.append(f"model: {_tostring(_idx(j, 'model'))}")
        elif t == "assistant":
            msg = _idx(j, "message")
            usage = _idx(msg, "usage")
            if newmsg:
                out.append(f"· ctx={_k(_ctx(usage))} out={_tostring(_alt(_idx(usage, 'output_tokens'), 0))}")
            for c in _iter(_idx(msg, "content")):
                ct = _idx(c, "type")
                if ct == "text":
                    out.append(_tostring(_idx(c, "text")))
                elif ct == "tool_use":
                    out.append(f"> {_tostring(_idx(c, 'name'))} {_trunc(tojson(_idx(c, 'input')), 200)}")
        elif t == "user":
            content = _idx(_idx(j, "message"), "content")
            if isinstance(content, list):
                for c in content:
                    if _idx(c, "type") == "tool_result":
                        err = "ERROR " if _truthy(_idx(c, "is_error")) else ""
                        out.append(f"< {err}{_tostring(_result_len(_idx(c, 'content')))} chars")
        elif t == "rate_limit_event":
            info = _idx(j, "rate_limit_info")
            status, overage = _idx(info, "status"), _idx(info, "isUsingOverage")
            if status != "allowed" or _truthy(overage):
                resets = _alt(_idx(info, "resetsAt"), 0)
                out.append(
                    f"rate-limit: status={_tostring(status)} type={_tostring(_idx(info, 'rateLimitType'))} "
                    f"overage={_tostring(overage)} resets={_todate(resets)} resets_epoch={_tostring(resets)}"
                )
        elif t == "result":
            u = _idx(j, "usage")
            ms = _alt(_idx(j, "duration_ms"), 0)
            out.append(
                f"usage: turns={_tostring(_idx(j, 'num_turns'))} duration={_num(_round(ms / 1000))}s "
                f"cost=${_num(_usd(_idx(j, 'total_cost_usd')))} ctx_peak={_k(self.max)} "
                f"in={_k(_idx(u, 'input_tokens'))} cache_read={_k(_idx(u, 'cache_read_input_tokens'))} "
                f"cache_write={_k(_idx(u, 'cache_creation_input_tokens'))} out={_k(_idx(u, 'output_tokens'))}"
            )
            if _idx(j, "subtype") != "success":
                out.append(
                    f"result: {_tostring(_idx(j, 'subtype'))} {_trunc(_tostring(_alt(_idx(j, 'result'), '')), 300)}"
                )
            mu = _alt(_idx(j, "modelUsage"), {})
            if isinstance(mu, dict) and len(mu) > 1:
                for name, v in mu.items():
                    out.append(
                        f"  {name}: in={_k(_idx(v, 'inputTokens'))} cache_read={_k(_idx(v, 'cacheReadInputTokens'))} "
                        f"cache_write={_k(_idx(v, 'cacheCreationInputTokens'))} out={_k(_idx(v, 'outputTokens'))} "
                        f"cost=${_num(_usd(_idx(v, 'costUSD')))}"
                    )


def render_lines(lines):
    """Every rendered line for an iterable of raw lines (no newlines)."""
    r = Renderer()
    for line in lines:
        yield from r.feed(line)


def resolved_model(jsonl_path, fallback):
    """The model id the last session logged to <jsonl> ran on (its init
    event), or <fallback>: providers.sh's resolved_model."""
    found = ""
    try:
        with open(jsonl_path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"subtype":"init"' in line:
                    found = line
    except OSError:
        return fallback
    if not found:
        return fallback
    try:
        model = json.loads(found).get("model")
    except (ValueError, AttributeError):
        return fallback
    return model if _truthy(model) and isinstance(model, str) and model else fallback


def main():
    """`python3 -m harness.stream < events`: render stdin, for checking a log
    by hand and for the golden test."""
    import sys

    r = Renderer()
    for raw in sys.stdin.buffer:
        line = raw.decode("utf-8", errors="replace").rstrip("\n")
        for out in r.feed(line):
            sys.stdout.write(out + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
