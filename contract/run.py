#!/usr/bin/env python3
"""Executable contract cases (HARNESS-ROADMAP.md R6).

    contract/run.py [--url URL] [--token T] [--level smoke] [--cases-dir DIR] [CASE_ID ...]

Runs the mechanical regression cases in contract/cases/<ID>.json (or in DIR,
for drafts kept elsewhere) against the live dw MCP server and prints one JSON
report on stdout:

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

Capture: a step may keep values from its result for later steps,

    {"call": "validate_workflow", "args": {...},
     "capture": {"fp": "plan.fingerprint", "ids": "jobs[*].id"}}

each name a path as above ("" is the whole result; a [*] path captures the
list). "${fp}" is then replaced in any later step's `args`, at any depth, and
in the comparison value of any assertion (never in a `path` or a key):

    {"path": "plan.fingerprint", "eq": "${fp}"}        the same as step 1's
    {"path": "plan.fingerprint", "ne": "${fp}"}        and its negation
    "args": {"job_id": "${job}", "note": "rerun of ${job}"}

A string that is exactly "${name}" becomes the captured value with its type
(a number stays a number, a list a list); inside a longer string it is
spliced in as text. A step's captures are taken before its own `expect`, so
that step may use them too. "$${name}" sends a literal "${name}"; a "${...}"
that is not a plain name ("${7*7}") is left alone. A name no step captured,
or a capture whose path does not resolve, fails the case at that step, and a
step whose args cannot be filled in is not sent.

A case stops at its first failed step, and the report says how many steps
were not run. A step that expected a tool error and was handed a job_id
instead has that job cancelled.
"""

import argparse
import json
import os
import re
import sys
import time

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
    """x as the text an assertion searches and a failure shows. A fanned-out
    value can hold MISSING, which is not JSON."""
    return x if isinstance(x, str) else json.dumps(x, default=lambda o: "<missing>")


class CaseFailure(Exception):
    """The case cannot go on, for a reason its report gives as an ordinary
    failure: an uncaptured name, a capture that found nothing."""


REF = re.compile(r"\$(\$?)\{([A-Za-z_][A-Za-z0-9_]*)\}")


def substitute(value, captured):
    """value with every ${name} replaced from captured, at any depth. Dict
    keys are left alone."""
    if isinstance(value, dict):
        return {k: substitute(v, captured) for k, v in value.items()}
    if isinstance(value, list):
        return [substitute(v, captured) for v in value]
    if not isinstance(value, str):
        return value

    def lookup(name):
        if name not in captured:
            known = ", ".join(sorted(captured)) or "nothing"
            raise CaseFailure(f"${{{name}}} is used, but no step has captured it (captured so far: {known})")
        return captured[name]

    whole = REF.fullmatch(value)
    if whole and not whole.group(1):
        return lookup(whole.group(2))
    return REF.sub(lambda m: "${%s}" % m.group(2) if m.group(1) else text(lookup(m.group(2))), value)


def capture(result, wanted, captured):
    """Adds each {name: path} of a step's "capture" to captured."""
    for name, path in wanted.items():
        if not REF.fullmatch("${%s}" % name):
            raise MCPError("capture name %r is not a plain name (letters, digits, _)" % (name,))
        vals = resolve(result, path)
        if any(v is MISSING for v in vals):
            raise CaseFailure(f"capture {name!r}: path {path!r} not found (got {text(result)[:300]})")
        captured[name] = vals if "*" in tokens(path) else vals[0]


ASSERTIONS = frozenset(
    ("eq", "ne", "exists", "len", "contains", "contains_any", "not_contains", "any_contains", "none_contains")
)


def check(result, a):
    unknown = sorted(set(a) - ASSERTIONS - {"path"})
    if unknown:
        raise MCPError("unknown assertion %r" % unknown[0])
    if not set(a) & ASSERTIONS:
        raise MCPError("assertion %r asserts nothing" % (a,))
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
    if len(present) != len(vals) and set(a) & {"eq", "ne", "len", "contains", "contains_any"}:
        # Some elements of a fanned-out path lack the key: not a value to compare.
        return fail(f"path not found in {len(vals) - len(present)} of {len(vals)} elements")
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


def cancel_stray_job(client, result):
    """A step that expected a refusal and got a job instead: cancel it, so a
    regression in the server costs no GPU time from an unattended script."""
    job = result.get("job_id") if isinstance(result, dict) else None
    if not job:
        return ""
    try:
        refused, answer = client.call("cancel_job", {"job_id": job})
    except (MCPError, OSError) as e:
        return f"; it queued job {job} and cancelling it failed: {e}"
    if refused:
        return f"; it queued job {job} and cancelling it failed: {text(answer)[:200]}"
    return f"; it queued job {job}, now cancelled"


def run_case(client, case):
    """A case stops at its first failed step: a later step may assume what
    the failed one established (a run_workflow that is only safe to send
    once validate has refused the same arguments), so it is reported as not
    run instead."""
    failures = []
    captured = {}
    started = time.time()
    steps = case["steps"]
    for i, step in enumerate(steps):
        label = step.get("label") or f"step {i + 1} ({step['call']})"
        try:
            args = substitute(step.get("args", {}), captured)
            is_error, result = client.call(step["call"], args)
            if is_error != step.get("is_error", False):
                stray = cancel_stray_job(client, result) if step.get("is_error", False) else ""
                failures.append(f"{label}: tool error flag was {is_error}: {text(result)[:300]}{stray}")
            else:
                capture(result, step.get("capture", {}), captured)
                for a in step.get("expect", []):
                    why = check(result, {k: v if k == "path" else substitute(v, captured) for k, v in a.items()})
                    if why:
                        failures.append(f"{label}: {why}")
        except CaseFailure as e:
            failures.append(f"{label}: {e}")
        if failures:
            if i + 1 < len(steps):
                failures.append(f"{len(steps) - i - 1} later step(s) not run: an earlier step failed")
            break
    return {
        "id": case["id"],
        "status": "fail" if failures else "pass",
        "failures": failures,
        "seconds": round(time.time() - started, 2),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("DW_URL", "http://lem:8765/mcp"))
    ap.add_argument("--token", default=os.environ.get("DW_TOKEN", ""))
    ap.add_argument("--level")
    ap.add_argument("--timeout", type=float, default=600, help="seconds one MCP request may take (default 600)")
    ap.add_argument(
        "--cases-dir",
        default=os.path.join(HERE, "cases"),
        help="where the <ID>.json cases are (default contract/cases)",
    )
    ap.add_argument("ids", nargs="*")
    args = ap.parse_args()
    if not os.path.isdir(args.cases_dir):
        ap.error(f"--cases-dir {args.cases_dir}: not a directory")
    if not args.token:
        ap.error("no MCP token: pass --token or set DW_TOKEN; no token is kept in the repo")

    cases = []
    broken = []  # cases that can't run: reported as errors, never dropped
    for f in sorted(os.listdir(args.cases_dir)):
        if f.endswith(".json"):
            stem = f[: -len(".json")]
            try:
                c = json.load(open(os.path.join(args.cases_dir, f)))
                cid = c["id"]
            except (OSError, ValueError, KeyError, TypeError) as e:
                broken.append(
                    {"id": stem, "status": "error", "failures": [f"{f}: unreadable case: {e}"], "seconds": None}
                )
                continue
            if cid != stem:
                broken.append(
                    {
                        "id": stem,
                        "status": "error",
                        "failures": [f"{f}: case id {cid!r} is not the filename"],
                        "seconds": None,
                    }
                )
            elif (not args.ids or cid in args.ids) and (not args.level or c.get("level") == args.level):
                cases.append(c)

    report = {"server": args.url, "cases": []}
    try:
        client = MCPClient(args.url, args.token, timeout=args.timeout)
        info = client.initialize()
        report["server_info"] = info.get("serverInfo")
    except (MCPError, OSError) as e:
        report["error"] = f"server unreachable: {e}"
        print(json.dumps(report, indent=1))
        return 2
    for c in cases:
        try:
            report["cases"].append(run_case(client, c))
        except (MCPError, OSError) as e:
            report["cases"].append({"id": c["id"], "status": "error", "failures": [str(e)], "seconds": None})
        except Exception as e:  # a malformed case, or a bug here: this case errors and the rest still run
            why = f"{type(e).__name__}: {e}"
            report["cases"].append({"id": c["id"], "status": "error", "failures": [why], "seconds": None})
    report["cases"].extend(b for b in broken if not args.ids or b["id"] in args.ids)
    for k in ("pass", "fail", "error"):
        report[{"pass": "passed", "fail": "failed", "error": "errors"}[k]] = sum(
            r["status"] == k for r in report["cases"]
        )
    print(json.dumps(report, indent=1))
    return 2 if report["errors"] else 1 if report["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
