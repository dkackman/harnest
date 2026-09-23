#!/usr/bin/env bash
# shellcheck disable=SC2034  # MODEL_ENV / MODEL_LABEL / MODEL_CONTEXT_TOKENS / CO_AUTHOR* are read by the sourcing driver
# providers.sh — model/provider resolution and the small set of helpers all
# three drivers (run-loop.sh, run-regression.sh, run-research.sh) would
# otherwise duplicate. Sourced, never executed.
#
# Claude Code takes its model from --model, and *where that model lives* from
# ANTHROPIC_BASE_URL. Any endpoint that speaks the Anthropic Messages API
# (/v1/messages) can back a session, so this file is the single place that
# knows what each provider needs in the environment. Adding a provider means
# adding a case here, not editing both drivers.
#
# Functions (contracts in full above each definition):
#
#   is_anthropic_model <model>                  → 0/1
#   resolve_model_env <provider> <model>        sets MODEL_ENV, MODEL_LABEL,
#                                               MODEL_CONTEXT_TOKENS
#   validate_fallback_model <provider> <model>  → 0/1 (stderr on failure)
#   fallback_model_flags <provider> <model>     prints "--fallback-model X"
#   co_author_for <provider> <model>            sets CO_AUTHOR, CO_AUTHOR_EMAIL
#   runtime_note <role> <provider> <model>      prints the "Runtime:" paragraph
#   resolved_model <log-name> <fallback>        the model id the last session
#                                               logged actually ran on
#   refresh_plugin_tree <src> <tree>            detached origin/develop worktree
#                                               the consumer roles load dw from
#   acquire_driver_lock <name>                  one lem-touching driver at a time
#   audit_issue <n> <role>                      [audit] WARNING on a broken
#                                               owner/close invariant
#   commit_suite_changes <msg> [name] [email]   commits regression-suite-*.md
#                                               and regression-perf/ (warns if
#                                               the commit removed lines)
#   park_external_issues                        relabels issues filed by a
#                                               non-owner login to owner:don +
#                                               status:needs-approval
#   STREAM_FLAGS                                 array: claude output flags every
#                                               driver passes (stream-json)
#   render_stream <name>                        stdin: claude stream-json →
#                                               $LOGS/<name>.jsonl + readable
#                                               text with per-turn/-session usage
#   CONSUMER_PERMISSION_FLAGS                    array: permission flags for the
#                                               consumer-only roles (tester, regression)
#   RESEARCHER_PERMISSION_FLAGS                  array: permission flags for the
#                                               read-only-source researcher role
#
# Providers, and why each is more than just a base URL:
#   anthropic  Native Claude Code models, alias or full id. The default. Sets
#              nothing *positive*, but it does scrub ambient routing variables
#              (see the branch) so the label can't lie about where the model
#              was served from.
#   ollama     A model served by Ollama — local, or an Ollama-cloud tag.
#              Ollama serves the Anthropic Messages API at /v1/messages, so
#              nothing needs to sit in front of it. Ollama's own
#              `ollama launch claude` sets a subset of what follows.
#   gateway    Anything else speaking that same API — LiteLLM,
#              claude-code-router, a corporate proxy.
#
# NOTE: these drivers run under the bash 3.2 that macOS ships, so no bash-4
# features, and an empty array must be expanded as ${arr[@]+"${arr[@]}"} or
# `set -u` aborts on it.

KNOWN_PROVIDERS="anthropic ollama gateway"

# The values CO_AUTHOR / CO_AUTHOR_EMAIL had when this file was sourced, i.e.
# what the *user* set. co_author_for consults these, not the live variables,
# so a driver can call it once per role without the first call's derived
# value being mistaken for a user override on the second.
_USER_CO_AUTHOR="${CO_AUTHOR:-}"
_USER_CO_AUTHOR_EMAIL="${CO_AUTHOR_EMAIL:-}"

# is_anthropic_model <model>
# True (0) for anything that names a Claude model: a Claude Code alias
# (opus, sonnet, haiku, fable, default, best, opusplan), an alias with a
# context suffix (opus[1m]), a full id (claude-opus-4-1-20250805), or a
# Bedrock/Vertex id (anthropic.claude-*, us.anthropic.claude-*). Structural on
# purpose — a hand-maintained allowlist went stale the first time a new alias
# or id format appeared.
is_anthropic_model() {
  case "$1" in
    *claude*|opus*|sonnet*|haiku*|fable*|default|best) return 0 ;;
    *) return 1 ;;
  esac
}

# resolve_model_env <provider> <model>
#
# Sets, for the caller:
#   MODEL_ENV    array of words to hand `env` before `claude` — VAR=value
#                assignments and/or `-u VAR` unsets. Consumed as
#                  env ${MODEL_ENV[@]+"${MODEL_ENV[@]}"} claude ...
#   MODEL_LABEL  "<provider>/<model>" — for logs, prompts, commit trailers
#   MODEL_CONTEXT_TOKENS
#                the context window declared to Claude Code for this pair
#                (OLLAMA_CONTEXT_TOKENS / GW_CONTEXT_TOKENS), or empty when
#                the model's native window applies. Drivers use it to decide
#                whether a session's working set needs splitting.
# Returns 1, with a message on stderr naming the knob to fix, when the pair is
# invalid or a provider's required setting is missing. Call it once per role
# at startup so a bad pair fails before the first cycle, not three minutes in.
resolve_model_env() {
  local provider="$1" model="$2"

  MODEL_ENV=()
  MODEL_LABEL="$provider/$model"
  MODEL_CONTEXT_TOKENS=""

  case "$provider" in
    anthropic)
      if ! is_anthropic_model "$model"; then
        echo "run: model '$model' is not an Anthropic model name, but its provider is 'anthropic'." >&2
        echo "     Either set <ROLE>_MODEL to a Claude alias/id, or set PROVIDER" >&2
        echo "     (or <ROLE>_PROVIDER) to ollama|gateway for that model." >&2
        return 1
      fi
      # --model passes straight through and the ambient auth decides the
      # account. But an ANTHROPIC_BASE_URL (or auth token, or per-tier model
      # override) already exported in the shell — say, one left behind by
      # `ollama launch claude` — would silently route every "anthropic/opus"
      # agent somewhere else while the label and the log say Anthropic. So
      # the anthropic branch *unsets* those for the child: the label is then
      # true by construction, and the user's own ANTHROPIC_API_KEY / OAuth
      # login is untouched.
      MODEL_ENV=(
        -u ANTHROPIC_BASE_URL
        -u ANTHROPIC_AUTH_TOKEN
        -u ANTHROPIC_DEFAULT_OPUS_MODEL
        -u ANTHROPIC_DEFAULT_SONNET_MODEL
        -u ANTHROPIC_DEFAULT_HAIKU_MODEL
      )
      ;;

    ollama)
      if is_anthropic_model "$model"; then
        echo "run: model '$model' is an Anthropic model name, which Ollama does not serve." >&2
        echo "     Set <ROLE>_MODEL to the Ollama tag, e.g. gemma4:31b-it-q4_K_M." >&2
        return 1
      fi
      # Ollama has no /v1/messages/count_tokens, and Claude Code otherwise
      # assumes 200k and auto-compacts against a window the model may not
      # have. There is no sane default: too small and the tester's working
      # set doesn't fit, too large and it silently overruns the server-side
      # num_ctx. So the window is declared explicitly, and the Ollama server
      # (OLLAMA_CONTEXT_LENGTH / num_ctx) must be at least this large.
      if [ -z "${OLLAMA_CONTEXT_TOKENS:-}" ]; then
        echo "run: provider 'ollama' needs OLLAMA_CONTEXT_TOKENS — the model's context window in tokens." >&2
        echo "     It must not exceed the Ollama server's own window (OLLAMA_CONTEXT_LENGTH / num_ctx);" >&2
        echo "     Ollama's Claude Code guidance uses 64k, e.g. OLLAMA_CONTEXT_TOKENS=65536." >&2
        return 1
      fi
      case "$OLLAMA_CONTEXT_TOKENS" in
        ''|*[!0-9]*)
          echo "run: OLLAMA_CONTEXT_TOKENS must be a whole number of tokens, got '$OLLAMA_CONTEXT_TOKENS'." >&2
          return 1 ;;
      esac
      MODEL_CONTEXT_TOKENS="$OLLAMA_CONTEXT_TOKENS"
      MODEL_ENV=(
        "ANTHROPIC_BASE_URL=${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"
        # Both, and deliberately overriding rather than inheriting: a real
        # ANTHROPIC_API_KEY exported in the shell would otherwise ride along to
        # Ollama, and in -p mode a present key is always used.
        "ANTHROPIC_AUTH_TOKEN=${OLLAMA_TOKEN:-ollama}"
        "ANTHROPIC_API_KEY=${OLLAMA_TOKEN:-ollama}"
        # Every tier of the model picker points at the same tag, so
        # background/haiku-class calls don't head for api.anthropic.com with a
        # model Ollama has never heard of. Same as `ollama launch claude`.
        "ANTHROPIC_DEFAULT_OPUS_MODEL=$model"
        "ANTHROPIC_DEFAULT_SONNET_MODEL=$model"
        "ANTHROPIC_DEFAULT_HAIKU_MODEL=$model"
        "CLAUDE_CODE_SUBAGENT_MODEL=$model"
        "CLAUDE_CODE_MAX_CONTEXT_TOKENS=$OLLAMA_CONTEXT_TOKENS"
        # No billing to report, no survey worth answering, and the attribution
        # block only misleads a model that didn't write the request.
        "CLAUDE_CODE_ATTRIBUTION_HEADER=0"
        "CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off"
        "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1"
        # A non-first-party base URL turns MCP tool search off by default.
        # This harness is almost entirely MCP calls, so turn it back on.
        "ENABLE_TOOL_SEARCH=true"
      )
      # Off by default: Claude Code already retries without thinking /
      # cache_control when an upstream rejects them, and a reasoning-capable
      # Ollama model should keep its thinking. Set this for a model that errors
      # on those fields rather than ignoring them.
      if [ -n "${OLLAMA_STRICT_SUPPRESS:-}" ]; then
        MODEL_ENV+=(
          "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1"
          "MAX_THINKING_TOKENS=0"
          "DISABLE_PROMPT_CACHING=1"
        )
      fi
      ;;

    gateway)
      # GW_BASE_URL only — deliberately not falling back to an ambient
      # ANTHROPIC_BASE_URL, which would make this error unreachable and the
      # gateway's identity an accident of the launching shell.
      if [ -z "${GW_BASE_URL:-}" ]; then
        echo "run: provider 'gateway' needs GW_BASE_URL — the endpoint that speaks /v1/messages." >&2
        return 1
      fi
      MODEL_ENV=("ANTHROPIC_BASE_URL=$GW_BASE_URL")
      # Without GW_TOKEN the ambient ANTHROPIC_API_KEY is what the gateway
      # receives — set it if that key belongs to Anthropic and not to the
      # gateway.
      if [ -n "${GW_TOKEN:-}" ]; then
        MODEL_ENV+=("ANTHROPIC_AUTH_TOKEN=$GW_TOKEN" "ANTHROPIC_API_KEY=$GW_TOKEN")
      fi
      MODEL_ENV+=("ENABLE_TOOL_SEARCH=true")
      if [ -n "${GW_CONTEXT_TOKENS:-}" ]; then
        MODEL_CONTEXT_TOKENS="$GW_CONTEXT_TOKENS"
        MODEL_ENV+=("CLAUDE_CODE_MAX_CONTEXT_TOKENS=$GW_CONTEXT_TOKENS")
      fi
      ;;

    *)
      echo "run: unknown provider '$provider' (known: $KNOWN_PROVIDERS)" >&2
      return 1
      ;;
  esac

  return 0
}

# validate_fallback_model <provider> <fallback_model>
# Returns 0 when <fallback_model> is empty (no fallback) or is a model the
# provider could actually serve: for anthropic it must satisfy
# is_anthropic_model; for ollama it must NOT (Ollama can't serve "opus");
# gateway accepts anything. Returns 1 with a stderr message otherwise. Call
# it at startup, once per role, next to resolve_model_env.
validate_fallback_model() {
  local provider="$1" fallback="$2"
  [ -n "$fallback" ] || return 0
  case "$provider" in
    anthropic)
      if ! is_anthropic_model "$fallback"; then
        echo "run: FALLBACK_MODEL '$fallback' is not an Anthropic model name, but the provider is 'anthropic'." >&2
        return 1
      fi ;;
    ollama)
      if is_anthropic_model "$fallback"; then
        echo "run: FALLBACK_MODEL '$fallback' is an Anthropic model name, which Ollama does not serve." >&2
        return 1
      fi ;;
    gateway) ;;
    *)
      echo "run: unknown provider '$provider' (known: $KNOWN_PROVIDERS)" >&2
      return 1 ;;
  esac
  return 0
}

# fallback_model_flags <provider> <fallback_model>
# Prints the words to splice into the claude command line — "--fallback-model
# <fallback_model>" — or nothing when <fallback_model> is empty. Validates via
# validate_fallback_model first and returns 1 (printing nothing) on failure.
# Typical use (an array, so a name like opus[1m] is never glob-expanded):
#   fb_words="$(fallback_model_flags "$P" "$FALLBACK_MODEL")" || exit 1
#   fb=(); [ -z "$fb_words" ] || read -r -a fb <<<"$fb_words"
#   claude ... ${fb[@]+"${fb[@]}"} ...
fallback_model_flags() {
  local provider="$1" fallback="$2"
  validate_fallback_model "$provider" "$fallback" || return 1
  [ -n "$fallback" ] || return 0
  printf -- '--fallback-model %s\n' "$fallback"
}

# co_author_for <provider> <model>
# Sets CO_AUTHOR and CO_AUTHOR_EMAIL — the Co-Authored-By trailer used by
# commit_suite_changes. That trailer is the one durable record of which model
# edited the suite, so it has to be honest: a non-Anthropic model is never
# attributed to Anthropic, and no address claims a domain it has nothing to
# do with. Whether the model is Claude is decided by is_anthropic_model, not
# by the provider string alone (a gateway can front a Claude id).
#   Claude model:         CO_AUTHOR="Claude (<model>)"            noreply@anthropic.com
#                         (plus " (via <provider>)" when provider != anthropic)
#   anything else:        CO_AUTHOR="<model> (via <provider>)"    noreply@localhost
# A CO_AUTHOR the user exported before sourcing overrides only the name; a
# user-exported CO_AUTHOR_EMAIL overrides only the email. Neither is inferred
# from the other. No alias→version table: the alias is the honest label, and
# a table is wrong the day the alias moves.
# Permission flags for the roles that talk to the MCP server *only* as a
# protocol consumer (tester, regression). Their legitimate surface is small
# and known, so it is enumerated: dw over MCP (ToolSearch loads the deferred
# schemas), the dw skills, the ticket CLI, file tools for the suite files and
# qa-bible, and a couple of read-only shell helpers the prompts mention. Under
# --permission-mode dontAsk anything outside the list is denied outright — a
# headless session never prompts — so this is the fence that makes the
# consumer-only isolation enforced rather than honor-system: no ssh, no curl,
# no python, no git writes (the drivers commit suite edits themselves). Read /
# Edit / Write are unscoped by path, so a read of the source checkout by
# absolute path is still on the honor system; the role prompts cover that.
# The implementer needs open-ended shell (git, gh, ssh lem, pytest, uv, ...)
# and gets --permission-mode auto in run-loop.sh instead.
#
# gh is `gh issue` only. `Bash(gh *)` let a consumer read the whole source
# tree (`gh api repos/.../contents`, `gh search code`, `gh repo clone`) and
# delete things (`gh api -X DELETE` - the researcher did, on a comment); every
# logged consumer call was `gh issue ...`. The two dw tools denied outright
# act on the whole server and no suite case or task needs them; the other
# destructive ones (delete_workspace, clear_memory, download_model) are
# exercised by suite cases, so they stay on the prompts' honor system.
#
# agent-settings/consumer.json adds the R3 guard hook (agent-settings/hooks/
# guard.py): closing as completed or adding status:verified is refused in a
# session that has made no mcp__dw__ call, and an owner:* label can only be
# swapped, never stacked. The hook finds the script via HARNEST_HOOKS.
export HARNEST_HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent-settings/hooks"
CONSUMER_PERMISSION_FLAGS=(
  --settings "$HARNEST_HOOKS/../consumer.json"
  --permission-mode dontAsk
  --allowedTools
    "mcp__dw__*" "ToolSearch" "Skill" "TodoWrite"
    "Read" "Glob" "Grep" "Edit" "Write"
    "Bash(gh issue *)" "Bash(date *)" "Bash(file *)"
    "Bash(git log *)" "Bash(git status*)" "Bash(git diff *)" "Bash(git show *)"
  --disallowedTools
    "mcp__dw__delete_model" "mcp__dw__update_diffusers"
)

# Permission flags for the researcher: read-only against the source
# checkout (Read/Glob/Grep/git-read only — no Edit/Write, no git writes, no
# ssh, no curl), read-only dw MCP discovery calls, and gh for issue
# management. Distinct from CONSUMER_PERMISSION_FLAGS (which allows Edit/
# Write for the suite files the tester/regression agent maintain) and from
# the implementer's --permission-mode auto: the researcher assesses, it
# never implements, and it has no durable file of its own to edit.
RESEARCHER_PERMISSION_FLAGS=(
  --permission-mode dontAsk
  --allowedTools
    "mcp__dw__list_workflows" "mcp__dw__list_guides" "mcp__dw__list_pipelines"
    "mcp__dw__list_classes" "mcp__dw__list_tasks" "mcp__dw__get_server_info"
    "mcp__dw__get_schema" "mcp__dw__get_guide" "mcp__dw__get_class"
    "mcp__dw__get_pipeline_signature" "ToolSearch" "WebFetch" "TodoWrite"
    "Read" "Glob" "Grep"
    "Bash(gh issue *)" "Bash(date *)" "Bash(file *)"
    "Bash(git log *)" "Bash(git status*)" "Bash(git diff *)" "Bash(git show *)" "Bash(git blame *)"
)

# Context every session carries on every turn, and doesn't need. Measured
# 2026-09-19 (measure-base-ctx.sh): a session started with ~42k tokens
# before its first tool call, ~20k of it built-in tool schemas the role is
# denied anyway (Artifact, Workflow, Agent, Monitor, ...), plus ~12 KB from
# user-level SessionStart hooks - the superpowers preamble and the remember
# plugin's dump of Don's own session memory, which was also *capturing* the
# agents' sessions back into .remember/ and re-injecting them everywhere.
# Cost here is cache_read = context x turns, so this is ~25k tokens off
# every turn of a 30-100 turn session.
#
# --setting-sources project,local: no user-level settings, so no user
# plugins, hooks, memory or MCP servers reach an unattended agent. The dw
# plugin still arrives via --plugin-dir; project settings (the source
# checkout's .claude/) still apply to the implementer. Two things the user
# level used to supply are now passed explicitly: effort (effort_flags) and
# the implementer's auto-mode environment (run-loop.sh, --settings).
ISOLATION_FLAGS=(--setting-sources project,local)

# Auto-memory is not a settings source, so --setting-sources doesn't touch
# it: a sonnet/opus session in the source checkout still loaded
# ~/.claude/projects/<checkout>/memory/MEMORY.md (9.7 KB, ~8k tokens with
# the memory instructions), and the implementer had been *writing* there
# too (implementer-cycle-*.md files in Don's project memory). Every
# driver inherits this from sourcing providers.sh.
export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

# --tools: the built-in tools a role gets *schemas* for. Everything a role
# actually used across every logged session, and nothing else. MCP tools
# are unaffected (they come from --mcp-config as deferred names).
CONSUMER_TOOLS="Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite"
RESEARCHER_TOOLS="Bash,Read,Glob,Grep,ToolSearch,WebFetch,TodoWrite"
IMPLEMENTER_TOOLS="Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,Agent,WebFetch,WebSearch,TodoWrite"

# Effort was inherited from ~/.claude/settings.json (effortLevel: medium)
# until ISOLATION_FLAGS cut that off; `medium` is therefore the default that
# preserves what every logged session ran at. One knob per role in the
# drivers (IMPLEMENTER_EFFORT etc.), all defaulting to this.
EFFORT="${EFFORT:-medium}"

# effort_flags <provider> <effort>
# The --effort words for a session, or nothing: the flag is an Anthropic
# request parameter and a non-anthropic provider gets nothing it can't take.
effort_flags() {
  local provider="$1" effort="$2"
  case "$effort" in
    low|medium|high|xhigh|max) ;;
    *) echo "run: effort must be one of low|medium|high|xhigh|max, got '$effort'" >&2; return 1 ;;
  esac
  [ "$provider" = anthropic ] && printf -- '--effort %s' "$effort"
  return 0
}

co_author_for() {
  local provider="$1" model="$2" name email
  if is_anthropic_model "$model"; then
    name="Claude ($model)"
    [ "$provider" = anthropic ] || name="$name (via $provider)"
    email="noreply@anthropic.com"
  else
    name="$model (via $provider)"
    email="noreply@localhost"
  fi
  CO_AUTHOR="${_USER_CO_AUTHOR:-$name}"
  CO_AUTHOR_EMAIL="${_USER_CO_AUTHOR_EMAIL:-$email}"
}

# runtime_note <role> <provider> <model>
# Prints the "Runtime:" paragraph a driver appends to an agent's prompt. Each
# agent is a fresh session, so its model is otherwise unrecorded — a later
# reader can't tell an Opus verification from a 31B one. The list of durable
# things is per role, and matches what each role prompt actually permits: the
# implementer only *proposes* regression cases in a hand-off comment (it has
# no checkout of this repo), so it is not told it edits the suite.
# Roles: implementer, tester, regression, researcher. Returns 1 on any other role.
runtime_note() {
  local role="$1" provider="$2" model="$3" examples
  case "$role" in
    implementer) examples="a ticket hand-off comment, a wontfix or needs-info reason, a regression case you propose in a hand-off" ;;
    tester)      examples="a verification comment, a bounce, a new issue, a regression-suite edit" ;;
    regression)  examples="an issue body, a comment on an existing issue, a suite-file edit" ;;
    researcher)  examples="a research/proposal comment, a reject reason, a question parked for Don" ;;
    *) echo "run: runtime_note: unknown role '$role' (implementer|tester|regression|researcher)" >&2; return 1 ;;
  esac
  # An alias (`opus`) moves when a new model ships, so a comment that says
  # "opus" can't later be told apart from the next Opus. Claude Code's own
  # system prompt states the exact model id; the note points the agent at
  # it. A non-Claude model name is already exact.
  local id_hint=""
  is_anthropic_model "$model" \
    && id_hint=" Use the exact model id your system prompt states (e.g. claude-opus-5), not the alias."
  printf '%s\n' \
    "Runtime: you are the $role agent, running as model '$model' via the '$provider'" \
    "provider. Whenever you record something durable that rests on your own" \
    "judgment — $examples —" \
    "name that model and provider in it, so a later reader can tell which model" \
    "produced it.$id_hint"
}

# resolved_model <log-name> <fallback>
# The model id the most recent session logged to $LOGS/<log-name>.jsonl
# actually ran on (its init event), or <fallback> when there is none - so a
# commit trailer says claude-opus-5 rather than the alias that was asked for.
resolved_model() {
  local id
  id="$(grep '"subtype":"init"' "$LOGS/$1.jsonl" 2>/dev/null | tail -n 1 | jq -r '.model // empty' 2>/dev/null)"
  printf '%s\n' "${id:-$2}"
}

# refresh_plugin_tree <source_dir> <plugin_tree>
# The dw plugin the consumer roles load (--plugin-dir) comes from a detached
# worktree of <source_dir> pinned to origin/develop - the same commit lem
# deploys - never from <source_dir>'s own working tree, which is on whatever
# branch the last implementer session (or a human) left checked out. That
# gap is the plugin-side twin of the lem one fixed by "always deploy
# develop": on 2026-09-22 the tester was loading skills from a feature
# branch committed eight minutes earlier. The worktree is driver-owned and
# never edited, so it is reset hard every time. Prints the commit it is on;
# returns 1 (and leaves any existing tree alone) if the fetch fails.
refresh_plugin_tree() {
  local src="$1" tree="$2"
  git -C "$src" fetch -q origin develop 2>/dev/null || return 1
  if [ ! -e "$tree/.git" ]; then
    mkdir -p "$(dirname "$tree")"
    git -C "$src" worktree add -q --detach "$tree" origin/develop >/dev/null 2>&1 || return 1
  fi
  git -C "$tree" checkout -q --detach --force origin/develop 2>/dev/null || return 1
  git -C "$tree" rev-parse --short HEAD
}

# acquire_driver_lock <name>
# One driver at a time against lem. run-loop's implementer restarts the
# server mid-cycle (deploy.sh), and a regression run measures timings and
# expects the server to stay up; each driver also keeps per-session state
# under $LOGS. mkdir is atomic, and macOS ships no flock(1). Waits for a
# holder whose pid is alive; takes over a lock whose holder is gone. The
# lock is released on exit by the trap this sets.
acquire_driver_lock() {
  local lock="$LOGS/.driver.lock" holder waited=0
  while ! mkdir "$lock" 2>/dev/null; do
    holder="$(cat "$lock/owner" 2>/dev/null || true)"
    if [ -n "$holder" ] && ! kill -0 "${holder%% *}" 2>/dev/null; then
      echo "[lock] taking over a stale lock from '$holder'" | tee -a "$LOGS/loop.log"
      rm -rf "$lock"
      continue
    fi
    [ "$waited" -eq 0 ] && echo "[lock] $1 waiting for '$holder' to finish" | tee -a "$LOGS/loop.log"
    waited=1
    sleep 30
  done
  echo "$$ $1" > "$lock/owner"
  # shellcheck disable=SC2064  # expand $lock now
  trap "rm -rf '$lock'" EXIT
}

# audit_issue <n> <role>
# Invariants the role prompts state but nothing else checks, read straight
# off the issue after a session touched it. A violation is logged loudly
# ([audit] WARNING in loop.log), not repaired - the fix is a human call, and
# the log is what shows a model drifting from its prompt (a model swap is
# exactly when it would). Checks: an open issue carries exactly one owner:*
# label; only the tester closes an issue as completed.
audit_issue() {
  local n="$1" role="$2" facts state reason owners
  # "|"-separated, not @tsv: stateReason is empty on an open issue, and read
  # collapses consecutive tabs (whitespace IFS), shifting owners into reason.
  facts="$(gh issue view "$n" --repo "$TICKET_REPO" --json state,stateReason,labels \
    --jq '[.state, (.stateReason // ""), ([.labels[].name | select(startswith("owner:"))] | join(","))] | join("|")' 2>/dev/null)" || return 0
  IFS='|' read -r state reason owners <<<"$facts"
  if [ "$state" = OPEN ] && { [ -z "$owners" ] || [ "$owners" != "${owners%%,*}" ]; }; then
    echo "[audit] WARNING: #$n is open with owner labels '${owners:-none}' after a session as $role; exactly one is the invariant" | tee -a "$LOGS/loop.log"
  fi
  if [ "$state" = CLOSED ] && [ "$reason" = COMPLETED ] && [ "$role" != tester ]; then
    echo "[audit] WARNING: #$n was closed as completed after a session as $role; only the tester may, from a real MCP call" | tee -a "$LOGS/loop.log"
  fi
  return 0
}

# commit_suite_changes <msg> [co_author] [co_author_email]
# Commits any pending changes to regression-suite-*.md and regression-perf/
# (the per-case measurement log the suite files point at) in $REPO — from any
# source: the tester adding a case this cycle, the regression agent's run
# just now, or an edit made by hand between runs — with <msg> as the subject
# and a Co-Authored-By trailer built from the name/email given (defaulting to
# CO_AUTHOR / CO_AUTHOR_EMAIL, i.e. whatever co_author_for last set). Nothing
# else in the tree is staged. A no-op (returning 0) when nothing is dirty, so
# it is safe to call before and after every run. Echoes <msg> to the terminal
# and $LOGS/loop.log when a commit was made. Needs REPO and LOGS from the
# driver; the driver should call co_author_for for the role that just ran
# *before* this, so the trailer names the model that made the edit.
commit_suite_changes() {
  local msg="$1" name="${2:-${CO_AUTHOR:-}}" email="${3:-${CO_AUTHOR_EMAIL:-}}"
  : "${REPO:?commit_suite_changes: REPO must be set by the driver}"
  : "${LOGS:?commit_suite_changes: LOGS must be set by the driver}"
  if [ -z "$name" ] || [ -z "$email" ]; then
    echo "run: commit_suite_changes: no co-author name/email — call co_author_for <provider> <model> first" >&2
    return 1
  fi
  local paths=("regression-suite-*.md" "regression-perf")
  ( cd "$REPO" && git diff HEAD --quiet -- "${paths[@]}" \
      && [ -z "$(git ls-files --others --exclude-standard -- "${paths[@]}")" ] ) && return 0
  git -C "$REPO" add -- "${paths[@]}"
  # Suites only grow and regression-perf/ is append-only, except for an edit
  # a human approved (a tester HANDOFF session applying one). Removed lines
  # are therefore worth a look, not a refusal: the commit goes ahead so the
  # tree stays clean, and the warning names it for review.
  local shrunk
  shrunk="$(git -C "$REPO" diff --cached --numstat -- "${paths[@]}" | awk '$2 > 0 { printf "%s(-%s) ", $3, $2 }')"
  git -C "$REPO" commit -q -m "$msg" -m "Co-Authored-By: $name <$email>" -- "${paths[@]}"
  echo "$msg" | tee -a "$LOGS/loop.log"
  [ -z "$shrunk" ] || echo "[audit] WARNING: $(git -C "$REPO" rev-parse --short HEAD) removed lines from ${shrunk}- cases and readings are add-only unless a human approved the change; review it" | tee -a "$LOGS/loop.log"
}

# STREAM_FLAGS / render_stream <name>
# Every driver runs `claude -p ... "${STREAM_FLAGS[@]}" 2>&1 | render_stream
# <name>` instead of letting claude print plain text. stream-json is the only
# output mode that reports token usage, and usage is what decides whether a
# cycle is affordable: a 3-cycle loop was eating a whole 5-hour allocation
# with no way to tell which role, which turn, or which tool result did it.
# render_stream keeps the raw events in $LOGS/<name>.jsonl (append-only; the
# occasional non-JSON stderr line is kept verbatim, so analyse it with
# `fromjson?`) and prints a readable rendering for <name>.log / loop.log:
#   · ctx=142.3k out=512        one per model turn: the prompt size that turn
#                               (input + cache read + cache write) and output
#   > tool_name {"arg":..}      each tool call, input truncated
#   < 38211 chars               each tool result's size (ERROR when is_error),
#                               which is how an oversized MCP result shows up
#   model: claude-opus-5        once, from the init event: the id an alias
#                               like `opus` resolved to for this session
#   rate-limit: ...             only when the session is throttled / in overage;
#                               carries resets=<iso> for a reader and
#                               resets_epoch=<secs> for sleep_if_rate_limited
#   usage: turns=.. duration=.. cost=.. ctx_peak=.. in=.. cache_read=..
#          cache_write=.. out=..  once, from the final result event
# Thinking blocks are dropped. Needs LOGS from the driver.
STREAM_FLAGS=(--output-format stream-json --verbose)

# shellcheck disable=SC2016  # jq program: the \(...) interpolations are jq's, not the shell's
_STREAM_RENDER_JQ='
  def k: if . == null then "0" elif . >= 1000 then ((. / 100 | round) / 10 | tostring) + "k" else tostring end;
  def usd: ((. // 0) * 100 | round) / 100;
  def ctx: (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0);
  def trunc($n): if length > $n then .[:$n] + "…" else . end;
  def result_len: if type == "string" then length
    elif type == "array" then (map((.text // "") | length) | add) // 0
    else (tojson | length) end;
  foreach inputs as $line ({id: null, max: 0};
    (($line | fromjson?) // {type: "raw", line: $line}) as $j
    | .j = $j
    | .newmsg = ($j.type == "assistant" and $j.message.id != .id)
    | if $j.type == "assistant" then
        .id = $j.message.id
        | .max = ([.max, ($j.message.usage | ctx)] | max)
      else . end;
    .j as $j
    | if $j.type == "raw" then $j.line
      elif $j.type == "system" and $j.subtype == "init" then "model: \($j.model)"
      elif $j.type == "assistant" then
        (if .newmsg then "· ctx=\($j.message.usage | ctx | k) out=\($j.message.usage.output_tokens // 0)" else empty end),
        ($j.message.content[]
          | if .type == "text" then .text
            elif .type == "tool_use" then "> \(.name) \(.input | tojson | trunc(200))"
            else empty end)
      elif $j.type == "user" then
        ($j.message.content
          | if type == "array" then
              .[] | select(.type == "tool_result")
              | "< \(if .is_error then "ERROR " else "" end)\(.content | result_len) chars"
            else empty end)
      elif $j.type == "rate_limit_event" then
        ($j.rate_limit_info
          | if .status != "allowed" or .isUsingOverage then
              "rate-limit: status=\(.status) type=\(.rateLimitType) overage=\(.isUsingOverage) resets=\(.resetsAt | todate) resets_epoch=\(.resetsAt)"
            else empty end)
      elif $j.type == "result" then
        "usage: turns=\($j.num_turns) duration=\(($j.duration_ms // 0) / 1000 | round)s cost=$\($j.total_cost_usd | usd) ctx_peak=\(.max | k) in=\($j.usage.input_tokens | k) cache_read=\($j.usage.cache_read_input_tokens | k) cache_write=\($j.usage.cache_creation_input_tokens | k) out=\($j.usage.output_tokens | k)",
        (if $j.subtype != "success" then "result: \($j.subtype) \($j.result // "" | tostring | trunc(300))" else empty end),
        ($j.modelUsage // {} | select(length > 1) | to_entries[]
          | "  \(.key): in=\(.value.inputTokens | k) cache_read=\(.value.cacheReadInputTokens | k) cache_write=\(.value.cacheCreationInputTokens | k) out=\(.value.outputTokens | k) cost=$\(.value.costUSD | usd)")
      else empty end)
'

render_stream() {
  : "${LOGS:?render_stream: LOGS must be set by the driver}"
  tee -a "$LOGS/$1.jsonl" | jq -Rn -r --unbuffered "$_STREAM_RENDER_JQ"
}

# sleep_if_rate_limited <rendered-session-log>
# A session that starts while the account's rate limit is rejected returns
# in under a second with turns=1 cost=$0, and a driver that just "continues"
# spins: 2026-09-21 02:50-08:30 the loop launched ~37 such sessions against
# a rejected five-hour window because the ticket board kept reading as
# changed. So after every session the driver hands its rendered output here;
# if the session was rejected, sleep until the reset the event named (plus
# a minute of slack) and log it. A rejection on resume just names the next
# reset, so this can't spin either. Nothing to do when the session wasn't
# rejected.
# session_died <rendered-session-log>
# True when a session ended without a final `usage:` line - the claude
# process went away before its result event (2026-09-21 17:26 three
# regression sessions in a row did, in a four-second window, with nothing on
# stderr; the next launch four seconds later was fine). A budget cut-off or
# an autocompact still emits `usage:`, so those are not "died". A rejected
# rate limit does emit it too, and sleep_if_rate_limited owns that case.
# The drivers retry a died session once, after a short pause.
session_died() {
  [ -r "$1" ] && ! grep -q '^usage: ' "$1"
}
SESSION_RETRY_PAUSE_SECS="${SESSION_RETRY_PAUSE_SECS:-30}"

sleep_if_rate_limited() {
  local f="$1" line epoch now wait
  [ -r "$f" ] || return 0
  line="$(grep 'rate-limit: status=rejected' "$f" | tail -n 1)" || return 0
  [ -n "$line" ] || return 0
  epoch="$(printf '%s\n' "$line" | sed -n 's/.*resets_epoch=\([0-9][0-9]*\).*/\1/p')"
  [ -n "$epoch" ] || return 0
  now="$(date +%s)"
  wait=$((epoch + 60 - now))
  if [ "$wait" -gt 0 ]; then
    echo "[loop] rate limit rejected; sleeping ${wait}s until $(date -r "$epoch" '+%H:%M:%S') + 60s" | tee -a "$LOGS/loop.log"
    sleep "$wait"
  fi
}

# park_external_issues
# Guardrail: an open issue filed by anyone other than TICKET_OWNER is parked
# with the human (owner:don + status:needs-approval) before any driver's
# agent sees it. Every unattended role runs as TICKET_OWNER's gh login, so
# its own filings pass; what this catches is a third party filing on the
# public repo, which no unattended agent may pick up as ordinary work.
# role-specific triage steps (e.g. the implementer's) repeat the check for
# anything filed mid-run; this is the enforced copy, shared by every driver
# that calls it. Already-parked issues are left alone. Needs TICKET_REPO,
# TICKET_OWNER, and LOGS set by the caller.
park_external_issues() {
  : "${TICKET_REPO:?park_external_issues: TICKET_REPO must be set by the driver}"
  : "${TICKET_OWNER:?park_external_issues: TICKET_OWNER must be set by the driver}"
  : "${LOGS:?park_external_issues: LOGS must be set by the driver}"
  gh issue list --repo "$TICKET_REPO" --state open --limit 200 \
    --json number,author,labels \
  | jq -r --arg me "$TICKET_OWNER" '.[]
      | select(.author.login != $me)
      | select(([.labels[].name] | index("status:needs-approval")) == null)
      | [(.number|tostring), .author.login,
         ([.labels[].name | select(startswith("owner:") or startswith("status:"))] | join(","))]
      | @tsv' \
  | while IFS=$'\t' read -r n author labels; do
      remove=()
      IFS=',' read -ra present <<< "$labels"
      for l in "${present[@]+"${present[@]}"}"; do
        [ -n "$l" ] && [ "$l" != "owner:don" ] && remove+=(--remove-label "$l")
      done
      gh issue edit "$n" --repo "$TICKET_REPO" ${remove[@]+"${remove[@]}"} \
        --add-label owner:don --add-label status:needs-approval >/dev/null \
      && gh issue comment "$n" --repo "$TICKET_REPO" --body "Parked for human review: filed by @$author, not by @$TICKET_OWNER. The agent loop only acts on issues from @$TICKET_OWNER unasked; a human will triage this and hand it off (\`owner:implementer\`, drop \`status:needs-approval\`) if it should enter the loop." >/dev/null \
      && echo "[loop] parked #$n (filed by @$author) as owner:don + status:needs-approval" | tee -a "$LOGS/loop.log" \
      || echo "[loop] failed to park #$n (filed by @$author)" | tee -a "$LOGS/loop.log"
    done
}
