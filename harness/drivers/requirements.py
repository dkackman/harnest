"""Generates regression-requirements.json: what each regression case needs
to run (workflows, models, assets, load), for the fleet's dispatch
(docs/superpowers/specs/2026-10-18-regression-fleet.md).

    python3 -m harness.drivers.requirements [level|all] [--force] [--cases ID ...] [--dry-run]

One read-only session per chunk of cases, against the primary server, which
holds every model the suites use. The session is given the cases' text in
its prompt and only read-only dw tools (no shell, no files, no runs), and
answers one `REQUIREMENT: {...}` line per case. The driver hashes each case
from the very text it sent, merges the answers, and commits the file. By
default only cases without a current entry are asked about, so a rerun
after a suite edit costs only what changed. An answer of `unknown`, or no
answer, leaves the case without an entry: it then runs on the primary only.

Knobs: REQUIREMENTS_MODEL (claude-sonnet-5-5), REQUIREMENTS_PROVIDER
(PROVIDER), REQUIREMENTS_EFFORT (EFFORT), REQUIREMENTS_BUDGET_USD (2 per
session, 0 = none), REQUIREMENTS_CASES_PER_SESSION (12), AUTOCOMPACT_TOKENS.
It takes no driver lock: every call it makes is read-only.
"""

import argparse
import json
import os
import re
import sys
import time

from .. import REPO, deploy, facts, providers, session, suite
from .. import requirements as req
from ..log import Log, err, ts
from ..profile import ProfileError, load, resolve_token, resolve_url
from ..stream import resolved_model

READ_ONLY_TOOLS = (
    "list_workflows",
    "get_workflow",
    "list_models",
    "list_assets",
    "list_tasks",
    "get_task",
    "list_pipelines",
    "get_pipeline_signature",
    "get_guide",
    "list_guides",
    "get_server_info",
)
_LINE = re.compile(r"^[-*` ]*REQUIREMENT:\s*(\{.*\})\s*`?\s*$")
KEYS = ("case", "workflows", "models", "assets", "load", "note")


def env(name, default=""):
    return os.environ.get(name) or default


def parse_answers(text, asked):
    """{case: entry fields} from a session's REQUIREMENT lines, for cases in
    <asked> only; and the problems found, one message each."""
    got, problems = {}, []
    for line in text.splitlines():
        m = _LINE.match(line)
        if not m:
            continue
        try:
            a = json.loads(m.group(1))
        except ValueError:
            problems.append(f"unparseable: {line[:120]}")
            continue
        if not isinstance(a, dict) or a.get("case") not in asked:
            problems.append(f"not a case this session was given: {line[:120]}")
            continue
        lists = {k: a.get(k, []) for k in ("workflows", "models", "assets")}
        if any(not isinstance(v, list) or not all(isinstance(x, str) and x for x in v) for v in lists.values()):
            problems.append(f"{a['case']}: workflows, models and assets must be lists of names")
            continue
        load_ = a.get("load")
        if load_ == "unknown":
            problems.append(f"{a['case']}: unknown ({a.get('note') or 'no reason given'}); primary only")
            continue
        if load_ not in req.LOADS:
            problems.append(f"{a['case']}: load '{load_}' is not one of {', '.join(req.LOADS)}")
            continue
        assets = [x[len("asset:") :] if x.startswith("asset:") else x for x in lists["assets"]]
        got[a["case"]] = {
            "workflows": lists["workflows"],
            "models": lists["models"],
            "assets": assets,
            "load": load_,
            **({"note": a["note"]} if isinstance(a.get("note"), str) and a["note"] else {}),
        }
    for c in asked:
        if c not in got and not any(p.startswith(f"{c}:") for p in problems):
            problems.append(f"{c}: no answer; primary only")
    return got, problems


def write_sidecar(path, entries):
    """The whole file, cases sorted, so a diff shows only what changed."""
    data = {"version": 1, "cases": {k: entries[k] for k in sorted(entries)}}
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def todo(level_files, sidecar, force=False, only=()):
    """[(level, [(case, block)])] still to ask about."""
    out = []
    for level, path in level_files:
        blocks = req.case_blocks(path)
        cases = [
            (c, b)
            for c, b in blocks.items()
            if (not only or c in only) and (force or not req.need_for(c, b, sidecar).known)
        ]
        if cases:
            out.append((level, cases))
    return out


def prompt_for(level, cases, server_text):
    body = "\n".join(f'<case id="{c}">\n{b.rstrip()}\n</case>' for c, b in cases)
    return (
        f"These {len(cases)} cases are from the '{level}' regression suite. For each, say what a dw server "
        f"must have to run it, as your system prompt describes. The server you can query is {server_text}, "
        "which holds every model the suites use. Run nothing.\n\n"
        + body
        + f"\n\nAnswer with exactly {len(cases)} REQUIREMENT lines, one per case, in this order: "
        + " ".join(c for c, _ in cases)
        + ". Then stop."
    )


def main(argv=None):
    ap = argparse.ArgumentParser(prog="python3 -m harness.drivers.requirements")
    ap.add_argument("level", nargs="?", default="smoke")
    ap.add_argument("--force", action="store_true", help="ask about every case, current entry or not")
    ap.add_argument("--cases", nargs="*", default=(), help="only these case IDs")
    ap.add_argument("--dry-run", action="store_true", help="print the sessions it would run; run none")
    a = ap.parse_args(sys.argv[1:] if argv is None else argv)

    try:
        profile = load()
        levels = profile.levels if a.level == "all" else [profile.level(a.level)]
        if None in levels:
            raise ProfileError(
                f"unknown level '{a.level}' (expected: {', '.join(l.name for l in profile.levels)}, all)"
            )
        sidecar_path = os.environ.get("HARNEST_REQUIREMENTS") or str(req.SIDECAR)
        entries = req.load_sidecar(sidecar_path)
        per = int(env("REQUIREMENTS_CASES_PER_SESSION", "12"))
        if per < 1:
            raise ProfileError("REQUIREMENTS_CASES_PER_SESSION must be at least 1")
    except (ProfileError, ValueError) as e:
        err(str(e))
        return 1
    work = todo([(lv.name, REPO / lv.file) for lv in levels], entries, a.force, set(a.cases))
    chunks = [(lv, cases[i : i + per]) for lv, cases in work for i in range(0, len(cases), per)]
    total = sum(len(c) for _, c in chunks)
    if a.dry_run or not chunks:
        print(f"{total} case(s) to ask about, in {len(chunks)} session(s) of up to {per}")
        for lv, c in chunks:
            print(f"  {lv}: {' '.join(x for x, _ in c)}")
        return 0

    server = profile.servers[0]
    logs = REPO / "logs"
    logs.mkdir(exist_ok=True)
    log = Log(logs / "loop.log")
    model = env("REQUIREMENTS_MODEL", "claude-sonnet-5-5")
    provider = env("REQUIREMENTS_PROVIDER", env("PROVIDER", "anthropic"))
    try:
        url = resolve_url(server, env("DW_URL"))
        token = resolve_token(server)
        h = facts.health_json(url, token)
        if h is None:
            raise facts.FactsError(f"no dw server answering at {url} (the primary, {server.name})")
        if facts.short_host(h.get("hostname") or "") != facts.short_host(server.host):
            raise facts.FactsError(f"the server at {url} is {h.get('hostname')}, not {server.host}")
        model_env = providers.resolve_model_env(provider, model)
        flags = providers.session_flags(
            provider,
            model,
            env("REQUIREMENTS_EFFORT", env("EFFORT", "medium")),
            env("REQUIREMENTS_BUDGET_USD", "2"),
            env("FALLBACK_MODEL"),
            env("AUTOCOMPACT_TOKENS", "120000"),
        )
    except (ProfileError, facts.FactsError, providers.ProviderError) as e:
        err(str(e))
        return 1
    mcp = profile.get("mcp.name", "dw")
    flags += [
        "--mcp-config",
        session.mcp_config(mcp, url, token),
        "--strict-mcp-config",
        *session.ISOLATION_FLAGS,
        "--tools",
        "ToolSearch",
        "--permission-mode",
        "dontAsk",
        "--allowedTools",
        "ToolSearch",
        *[f"mcp__{mcp}__{t}" for t in READ_ONLY_TOOLS],
    ]
    prompt_file = logs / ".prompt.requirements.md"
    prompt_file.write_text((REPO / "agents" / "regression" / "requirements.md").read_text(encoding="utf-8"))
    last = logs / ".last-session.requirements"
    head = deploy.deployed_head(server)
    server_text = f"{server.name} ({h.get('device')}, running {head})"
    log.say(
        f"=== {ts()} requirements run ({model_env.label}, {a.level}, {total} cases in {len(chunks)} sessions "
        f"of up to {per}, server={server.name}, head={head}) ==="
    )
    added = unknown = 0
    for n, (lv, cases) in enumerate(chunks, 1):
        label = f"requirements:{lv}.{n} of {len(chunks)}"
        session.run(
            label,
            "requirements",
            str(REPO),
            prompt_file,
            prompt_for(lv, cases, server_text),
            flags,
            model_env=model_env,
            session_env={"HARNEST_ROLE": "requirements"},
            logs=str(logs),
            last=str(last),
            log=log,
        )
        text = last.read_text(encoding="utf-8", errors="replace") if last.exists() else ""
        got, problems = parse_answers(text, {c for c, _ in cases})
        by = resolved_model(logs / "requirements.jsonl", model)
        day = time.strftime("%Y-%m-%d")
        for c, b in cases:
            if c in got:
                entries[c] = {**got[c], "hash": req.block_hash(b), "by": f"{provider}/{by}", "on": day}
        write_sidecar(sidecar_path, entries)
        added += len(got)
        unknown += len(cases) - len(got)
        for p in problems:
            log.say(f"[{label}] {p}")
        log.say(f"[{label}] {len(got)} of {len(cases)} case(s) recorded")
    log.say(f"[requirements] {added} entr{'y' if added == 1 else 'ies'} written, {unknown} case(s) left primary only")
    if os.path.realpath(sidecar_path) == os.path.realpath(req.SIDECAR):
        name, email = providers.co_author_for(provider, resolved_model(logs / "requirements.jsonl", model))
        suite.commit_changes(
            REPO,
            str(logs),
            ["regression-requirements.json"],
            f"requirements: {a.level} from {ts()} run ({model_env.label})",
            name,
            email,
            log.say,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
