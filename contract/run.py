#!/usr/bin/env python3
"""Executable contract cases (HARNESS-ROADMAP.md R6).

    contract/run.py [--url URL] [--token T] [--level smoke] [CASE_ID ...]

Runs the mechanical regression cases in contract/cases/<ID>.json against the
live dw MCP server and prints one JSON report on stdout:

    {"server": ..., "cases": [{"id", "status": "pass"|"fail"|"error",
      "failures": [...], "seconds"}], "passed", "failed", "errors"}

Exit status 0 when every case passed, 1 when any failed, 2 when any errored
(the server was unreachable, or a call raised). No LLM, no cost, and the same
result every time: the regression agent reads this report and does only the
filing. It is a pure MCP consumer, like the tester: no source, no lem.

A case is data, so the tester adds one the way it adds a prose case:

    {"id": "S-F028", "level": "smoke", "title": "...",
     "steps": [{"call": "validate_workflow", "args": {...},
                "expect": [{"path": "valid", "eq": false}, ...]}]}

Assertions, each on `path` into the call's result (dots and [n]; [*] fans out
over a list; ["key"] for a key containing dots or slashes):
    eq, ne              equal / not equal
    exists              true: the path resolves; false: it doesn't
    len                 length equals
    contains            string: every listed substring is in it;
                        list: every listed item is an element
    contains_any        at least one listed item is an element / substring
    not_contains        the opposite of contains, for any listed item
    any_contains        over a fanned-out or list value: some element (as
                        text) contains every listed substring
    none_contains       no element contains the substring
A step may also say "is_error": true|false (default false) for the tool-level
error flag.
"""
import argparse, json, os, re, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mcp_client import MCPClient, MCPError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
MISSING = object()


def tokens(path):
    if isinstance(path, list):
        return path
    out = []
    for m in re.finditer(r'\["([^"]+)"\]|\[(\*|\d+)\]|([^.\[\]]+)', path):
        key, idx, name = m.groups()
        out.append(key if key is not None else ("*" if idx == "*" else int(idx)) if idx is not None else name)
    return out


def resolve(value, path):
    """A list of values (fan-out on [*]); MISSING where a step fails."""
    vals = [value]
    for t in tokens(path):
        nxt = []
        for v in vals:
            if t == "*":
                nxt.extend(v if isinstance(v, list) else [MISSING])
            elif isinstance(t, int):
                nxt.append(v[t] if isinstance(v, list) and -len(v) <= t < len(v) else MISSING)
            else:
                nxt.append(v.get(t, MISSING) if isinstance(v, dict) else MISSING)
        vals = nxt
    return vals


def as_list(x):
    return x if isinstance(x, list) else [x]


def text(x):
    return x if isinstance(x, str) else json.dumps(x)


def check(result, a):
    path = a.get("path", "")
    vals = resolve(result, path)
    fan = "*" in tokens(path) if not isinstance(path, list) else "*" in path
    one = vals[0] if len(vals) == 1 and not fan else vals
    present = [v for v in vals if v is not MISSING]

    def fail(why):
        shown = text(one if one is not MISSING else None)
        return f"{path}: {why} (got {shown[:300]})"

    if "exists" in a:
        ok = bool(present) and len(present) == len(vals)
        return None if ok == bool(a["exists"]) else fail("expected to exist" if a["exists"] else "expected absent")
    if one is MISSING or (fan and not present):
        return fail("path not found")
    if "eq" in a and one != a["eq"]:
        return fail(f"expected == {text(a['eq'])}")
    if "ne" in a and one == a["ne"]:
        return fail(f"expected != {text(a['ne'])}")
    if "len" in a and (not hasattr(one, "__len__") or len(one) != a["len"]):
        return fail(f"expected length {a['len']}")
    if "contains" in a:
        for want in as_list(a["contains"]):
            if isinstance(one, list) and not fan:
                if want not in one:
                    return fail(f"expected element {text(want)}")
            elif want not in text(one):
                return fail(f"expected to contain {text(want)}")
    if "contains_any" in a:
        opts = as_list(a["contains_any"])
        hit = any((o in one) if isinstance(one, list) and not fan else (o in text(one)) for o in opts)
        if not hit:
            return fail(f"expected at least one of {text(opts)}")
    if "not_contains" in a:
        for bad in as_list(a["not_contains"]):
            hit = (bad in one) if isinstance(one, list) else (bad in text(one))
            if hit:
                return fail(f"expected not to contain {text(bad)}")
    if "any_contains" in a:
        items = present if fan else as_list(one)
        wants = as_list(a["any_contains"])
        if not any(all(w in text(i) for w in wants) for i in items):
            return fail(f"expected some element containing {text(wants)}")
    if "none_contains" in a:
        items = present if fan else as_list(one)
        if any(a["none_contains"] in text(i) for i in items):
            return fail(f"expected no element containing {text(a['none_contains'])}")
    return None


def run_case(client, case):
    failures = []
    started = time.time()
    for i, step in enumerate(case["steps"]):
        label = step.get("label") or f"step {i + 1} ({step['call']})"
        is_error, result = client.call(step["call"], step.get("args", {}))
        if is_error != step.get("is_error", False):
            failures.append(f"{label}: tool error flag was {is_error}: {text(result)[:300]}")
            continue
        for a in step.get("expect", []):
            why = check(result, a)
            if why:
                failures.append(f"{label}: {why}")
    return {"id": case["id"], "status": "fail" if failures else "pass", "failures": failures,
            "seconds": round(time.time() - started, 2)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("DW_URL", "http://lem:8765/mcp"))
    ap.add_argument("--token", default=os.environ.get("DW_TOKEN", "xyz"))
    ap.add_argument("--level")
    ap.add_argument("ids", nargs="*")
    args = ap.parse_args()

    cases = []
    for f in sorted(os.listdir(os.path.join(HERE, "cases"))):
        if f.endswith(".json"):
            c = json.load(open(os.path.join(HERE, "cases", f)))
            if (not args.ids or c["id"] in args.ids) and (not args.level or c.get("level") == args.level):
                cases.append(c)

    report = {"server": args.url, "cases": []}
    try:
        client = MCPClient(args.url, args.token)
        info = client.initialize()
        report["server_info"] = info.get("serverInfo")
    except (MCPError, OSError) as e:
        report["error"] = f"server unreachable: {e}"
        print(json.dumps(report, indent=1))
        sys.exit(2)
    for c in cases:
        try:
            report["cases"].append(run_case(client, c))
        except (MCPError, OSError) as e:
            report["cases"].append({"id": c["id"], "status": "error", "failures": [str(e)], "seconds": None})
    for k in ("pass", "fail", "error"):
        report[{"pass": "passed", "fail": "failed", "error": "errors"}[k]] = sum(r["status"] == k for r in report["cases"])
    print(json.dumps(report, indent=1))
    sys.exit(2 if report["errors"] else 1 if report["failed"] else 0)


main()
