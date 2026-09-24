#!/usr/bin/env bash
# Retro (HARNESS-ROADMAP.md R7): reads what the loop recorded about itself
# since the last retro and files at most three evidenced, unapplied
# proposals as issues on the harness repo (dkackman/harnest), labeled
# harness + status:needs-approval. Read-only everywhere else.
#
#   ./run-retro.sh                    # since the last retro (first run: the last 7 days of issues, all of the logs)
#   RETRO_EVIDENCE_ONLY=1 ./run-retro.sh   # print the evidence digest, no session, no state change
#
# "Since the last retro" is byte offsets into each log (logs are
# append-only), kept in logs/retro-seen.json and only advanced after a
# session that finished, so a failed retro doesn't skip its window.
# Harness proposals live on the harness repo, not the ticket repo: there
# they can't enter the implementer's queue or the status board.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"
HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"
AGENTS="$REPO/agents"
LOGS="$REPO/logs"
PROVIDER="${PROVIDER:-anthropic}"
RETRO_MODEL="${RETRO_MODEL:-claude-opus-5-5}"   # judgment over noisy evidence; runs rarely
RETRO_PROVIDER="${RETRO_PROVIDER:-$PROVIDER}"
RETRO_BUDGET_USD="${RETRO_BUDGET_USD:-5}"
AUTOCOMPACT_TOKENS="${AUTOCOMPACT_TOKENS:-120000}"
SEEN="$LOGS/retro-seen.json"

command -v claude >/dev/null || { echo "claude CLI not on PATH" >&2; exit 1; }
command -v gh >/dev/null     || { echo "gh CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null     || { echo "jq not on PATH" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh CLI not authenticated" >&2; exit 1; }
mkdir -p "$LOGS"
. "$REPO/providers.sh"
RETRO_EFFORT="${RETRO_EFFORT:-$EFFORT}"
resolve_model_env "$RETRO_PROVIDER" "$RETRO_MODEL" || exit 1
session_flags "$RETRO_PROVIDER" "$RETRO_MODEL" "$RETRO_EFFORT" "$RETRO_BUDGET_USD" || exit 1
LAST_SESSION="$LOGS/.last-session.retro"

NEXT_SEEN="$LOGS/.retro-seen.next.json"
EVIDENCE="$(python3 - "$LOGS" "$SEEN" "$NEXT_SEEN" "$TICKET_REPO" <<'PY'
import collections, glob, json, os, re, statistics, subprocess, sys, time
logs, seen_path, next_path, ticket_repo = sys.argv[1:5]
seen = json.load(open(seen_path)) if os.path.exists(seen_path) else {}
offsets = seen.get("offsets", {})
since = seen.get("at") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 7 * 86400))

def new_text(path):
    size = os.path.getsize(path)
    start = offsets.get(os.path.basename(path), 0)
    if start > size:  # rotated or truncated: read it all
        start = 0
    with open(path, "rb") as fh:
        fh.seek(start)
        data = fh.read().decode("utf-8", "ignore")
    offsets[os.path.basename(path)] = size
    return data

out = []
loop = new_text(os.path.join(logs, "loop.log")) if os.path.exists(os.path.join(logs, "loop.log")) else ""
usage = re.findall(r"^\[([a-z-]+):([^\]]+)\] usage: turns=(\d+) duration=(\d+)s cost=\$([0-9.]+) ctx_peak=([0-9.]+)k", loop, re.M)
out.append(f"## Sessions since {since} (loop.log)\n")
by = collections.defaultdict(list)
for role, tag, turns, dur, cost, ctx in usage:
    kind = role + (":" + re.sub(r"[#0-9.]+", "", tag) if not tag.startswith("#") else ":issue")
    by[kind].append((float(cost), int(turns), float(ctx)))
if by:
    out.append("| role:kind | sessions | total $ | median $ | max $ | median turns | max ctx k |\n|---|---|---|---|---|---|---|")
    for k, v in sorted(by.items(), key=lambda kv: -sum(x[0] for x in kv[1])):
        c = [x[0] for x in v]
        out.append(f"| {k} | {len(v)} | {sum(c):.2f} | {statistics.median(c):.2f} | {max(c):.2f} | "
                   f"{statistics.median([x[1] for x in v]):.0f} | {max(x[2] for x in v):.0f} |")
    out.append("\nMost expensive sessions:")
    for role, tag, turns, dur, cost, ctx in sorted(usage, key=lambda u: -float(u[4]))[:5]:
        out.append(f"- [{role}:{tag}] ${cost}, {turns} turns, {int(dur)//60} min, ctx peak {ctx}k")
else:
    out.append("(no sessions)")

audits = re.findall(r"^.*\[audit\] WARNING.*$", loop, re.M)
out.append(f"\n## [audit] warnings: {len(audits)}")
out += ["- " + a[:200] for a in audits[:10]]
guards = re.findall(r"^.*Blocked by the harness guard.*$", loop, re.M)
out.append(f"\n## Guard refusals: {len(guards)}")
out += ["- " + g[:200] for g in guards[:10]]

denied = collections.Counter(); examples = {}
for path in glob.glob(os.path.join(logs, "*.jsonl")):
    role = os.path.basename(path)[:-6]
    cmds = {}
    for line in new_text(path).splitlines():
        try:
            j = json.loads(line)
        except ValueError:
            continue
        m = j.get("message") if isinstance(j, dict) else None
        if not isinstance(m, dict) or not isinstance(m.get("content"), list):
            continue
        for b in m["content"]:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "tool_use":
                inp = b.get("input") or {}
                cmds[b.get("id")] = (b.get("name"), inp.get("command") or inp.get("file_path") or "")
            elif b.get("type") == "tool_result" and "has been denied" in json.dumps(b.get("content")):
                name, arg = cmds.get(b.get("tool_use_id"), ("?", ""))
                key = (role, name, " ".join(str(arg).split()[:2]))
                denied[key] += 1
                examples.setdefault(key, " ".join(str(arg).split())[:160])
out.append(f"\n## Permission denials: {sum(denied.values())}")
for (role, name, head), n in denied.most_common(15):
    out.append(f"- {n}x {role} {name} `{head}` e.g. `{examples[(role, name, head)]}`")

def gh(*a):
    return subprocess.run(["gh", *a], capture_output=True, text=True).stdout
nums = gh("issue", "list", "--repo", ticket_repo, "--state", "all", "--limit", "300",
          "--search", "updated:>=" + since[:10], "--json", "number", "--jq", ".[].number").split()
handoffs = bounced = 0; rows = []
for n in nums:
    ev = gh("api", "--paginate", f"repos/{ticket_repo}/issues/{n}/events", "--jq",
            f'.[] | select(.created_at >= "{since}") | select(.event == "reopened" or (.event == "labeled" and .label.name == "status:fixed-pending-verify")) | .event').split()
    h = ev.count("labeled"); handoffs += h
    if h >= 2 or "reopened" in ev:
        bounced += 1; rows.append(f"- #{n}: {h} hand-offs{', reopened' if 'reopened' in ev else ''} in the window")
out.append(f"\n## Ticket flow since {since[:10]} ({len(nums)} issues touched)")
out.append(f"{handoffs} hand-offs; {bounced} issues handed off more than once or reopened")
out += rows[:15]

bench = subprocess.run([os.path.join(os.path.dirname(logs), "run-bench.sh"), "--summary"],
                       capture_output=True, text=True).stdout.strip()
out.append("\n## Replay benchmark (all labels, bench/results/results.jsonl)\n" + (bench or "(no results)"))

json.dump({"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "offsets": offsets}, open(next_path, "w"))
print("\n".join(out))
PY
)"

if [ "${RETRO_EVIDENCE_ONLY:-0}" = 1 ]; then
  printf '%s\n' "$EVIDENCE"; rm -f "$NEXT_SEEN"; exit 0
fi

# The labels the proposals carry; idempotent.
gh label create harness --repo "$HARNESS_REPO" --color 5319e7 --description "Change to the harness itself" --force >/dev/null 2>&1 || true
gh label create status:needs-approval --repo "$HARNESS_REPO" --color d93f0b --description "Waiting for Don" --force >/dev/null 2>&1 || true

run_claude_session retro retro "$REPO" "$AGENTS/RETRO.agent.md" \
"Your role instructions are in your system prompt (the contents of $AGENTS/RETRO.agent.md). Harness repo: $HARNESS_REPO. Ticket repo: $TICKET_REPO. File at most three proposals, then stop.

$EVIDENCE

$(runtime_note retro "$RETRO_PROVIDER" "$RETRO_MODEL")" \
  "${SESSION_FLAGS[@]}" \
  --strict-mcp-config "${ISOLATION_FLAGS[@]}" --tools "$RETRO_TOOLS" "${RETRO_PERMISSION_FLAGS[@]}"
if session_died "$LAST_SESSION"; then
  rm -f "$NEXT_SEEN"; echo "[retro] session ended without a result; window not advanced" | tee -a "$LOGS/loop.log"
else
  mv "$NEXT_SEEN" "$SEEN"
fi
