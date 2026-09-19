#!/usr/bin/env bash
# measure-base-ctx.sh <label> [claude flags...]
# Prints the turn-1 context (input + cache read + cache write tokens), the
# number of tools and the number of skills a `claude -p` session starts with
# under the given flags. Runs a one-word prompt on haiku, so it costs well
# under a cent. This is how the driver flag sets are tuned: the number that
# matters for cost is what every turn of a session carries, and this is it.
# It runs on haiku, which does not load auto-memory, and it does not source
# providers.sh - so a sonnet/opus session in the source checkout starts
# higher than this says: that checkout's CLAUDE.md, and (without
# CLAUDE_CODE_DISABLE_AUTO_MEMORY=1) its auto-memory, come on top.
#
#   ./measure-base-ctx.sh baseline
#   ./measure-base-ctx.sh lean --setting-sources project,local --tools "Bash,Read"
set -euo pipefail
label="$1"; shift
claude -p "Reply with the single word ok." --model haiku \
  --output-format stream-json --verbose --no-session-persistence "$@" \
  2>/dev/null < /dev/null | python3 -c '
import sys, json
label = sys.argv[1]; tools = skills = None
for line in sys.stdin:
    try: e = json.loads(line)
    except ValueError: continue
    if e.get("type") == "system" and e.get("subtype") == "init":
        tools = len(e.get("tools", [])); skills = len(e.get("slash_commands", []))
    if e.get("type") == "assistant":
        u = e["message"].get("usage", {})
        ctx = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
        print(f"{label}: turn1 ctx={ctx/1000:.1f}k tools={tools} skills={skills}")
        break
' "$label"
