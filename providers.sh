#!/usr/bin/env bash
# shellcheck disable=SC2034  # MODEL_ENV / MODEL_LABEL / MODEL_CONTEXT_TOKENS / CO_AUTHOR* are read by the sourcing driver
# providers.sh — model/provider resolution and the small set of helpers both
# drivers (run-loop.sh, run-regression.sh) would otherwise duplicate. Sourced,
# never executed.
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
#   commit_suite_changes <msg> [name] [email]   commits regression-suite-*.md
#                                               and regression-perf/
#   CONSUMER_PERMISSION_FLAGS                    array: permission flags for the
#                                               consumer-only roles (tester, regression)
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
        echo "     Either set MODEL (or <ROLE>_MODEL) to a Claude alias/id, or set PROVIDER" >&2
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
        echo "     Set MODEL (or <ROLE>_MODEL) to the Ollama tag, e.g. gemma4:31b-it-q4_K_M." >&2
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
CONSUMER_PERMISSION_FLAGS=(
  --permission-mode dontAsk
  --allowedTools
    "mcp__dw__*" "ToolSearch" "Skill" "Agent" "TodoWrite"
    "Read" "Glob" "Grep" "Edit" "Write"
    "Bash(gh *)" "Bash(date *)" "Bash(file *)"
    "Bash(git log *)" "Bash(git status*)" "Bash(git diff *)" "Bash(git show *)"
)

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
# Roles: implementer, tester, regression. Returns 1 on any other role.
runtime_note() {
  local role="$1" provider="$2" model="$3" examples
  case "$role" in
    implementer) examples="a ticket hand-off comment, a wontfix or needs-info reason, a regression case you propose in a hand-off" ;;
    tester)      examples="a verification comment, a bounce, a new issue, a regression-suite edit" ;;
    regression)  examples="an issue body, a comment on an existing issue, a suite-file edit" ;;
    *) echo "run: runtime_note: unknown role '$role' (implementer|tester|regression)" >&2; return 1 ;;
  esac
  printf '%s\n' \
    "Runtime: you are the $role agent, running as model '$model' via the '$provider'" \
    "provider. Whenever you record something durable that rests on your own" \
    "judgment — $examples —" \
    "name that model and provider in it, so a later reader can tell which model" \
    "produced it."
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
  git -C "$REPO" commit -q -m "$msg" -m "Co-Authored-By: $name <$email>" -- "${paths[@]}"
  echo "$msg" | tee -a "$LOGS/loop.log"
}
