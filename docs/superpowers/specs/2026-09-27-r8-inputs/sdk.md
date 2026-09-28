# Claude Agent SDK (Python) vs the harnest bash drivers: an inventory

**Source.** `claude-agent-sdk` **0.2.160**, the macOS arm64 wheel (`python3 -m pip download claude-agent-sdk --no-deps`), unpacked at
a scratch directory (`python3 -m pip download claude-agent-sdk==0.2.160 --no-deps` reproduces it). Its bundled CLI is **2.1.283** (`_cli_version.py`).
Local CLI: `/Users/don/.local/bin/claude`, **2.1.283**. Local Python: **3.13.1**, with only `python3 -m pip` (no `pip` on PATH).
Harness files read, none modified: `providers.sh`, `run-loop.sh`, `run-features.sh`, `run-regression.sh`, `run-digest.sh`, `run-bench.sh`, `tests/test-drivers.sh`, `tests/fixtures/stream.jsonl`, `HARNESS-ROADMAP.md` §R8. No driver or `claude` session was run; only `claude --help`.

**Citation key.**
- `T:` is `_internal/transport/subprocess_cli.py`, `Q:` is `_internal/query.py`, `C:` is `_internal/client.py`, `P:` is `_internal/message_parser.py`, `Y:` is `types.py`.
- **[code]** means read in the SDK source. **[docs]** means code.claude.com/docs/en/agent-sdk/permissions (fetched 2026-09-27). **[help]** means local `claude --help`. **[unverified]** needs a live run.

---

## 0. Traps to fix before anything else

| # | Trap | Evidence | What to do |
|---|---|---|---|
| 1 | **The default system prompt is empty.** `system_prompt=None` emits `--system-prompt ""`, which wipes Claude Code's own prompt. `SystemPromptFile` maps to `--system-prompt-file`, which *replaces* the prompt; it does not append. | T:576-589 [code] | Pass `system_prompt={"type":"preset","preset":"claude_code"}` with **no** `append` key; T:586 then emits nothing. Add `extra_args={"append-system-prompt-file": path}`. The other option is `preset` + `append=<file text>`, which puts the text in argv. |
| 2 | **`setting_sources=None` passes no flag, so the CLI loads user settings.** That brings back the user plugins, hooks and memory that `ISOLATION_FLAGS` removed. **Setting `skills=` quietly defaults `setting_sources` to `["user","project"]`.** | T:543-568, 729-730; Y:2297-2308 [code] | Always set `setting_sources=["project","local"]`, or `["local"]` for the reviewer and release roles. Never use `skills=`; keep `"Skill"` in `allowed_tools` the way the harness does today. The SDK calls that deprecated but still passes it (T:543, 607-608). |
| 3 | **The bundled binary wins over PATH.** `_find_cli` checks `_bundled/claude` (225 MB) first, then `which claude`. A stub on PATH is ignored, and so is every auto-update of `~/.local/bin/claude`. The versions match today only by coincidence. | T:255-260, 341-354 [code] | Always pass `cli_path=shutil.which("claude")` in production, and the stub's path in tests. |
| 4 | **`-p` is never passed.** The prompt goes over stdin as a stream-json `user` message after `initialize`. The CLI is headless because stdout isn't a TTY ([help]: "-p, or when stdout is not a TTY"). | T:574, 791-793; C:180-198 [code] | Nothing to do for behaviour. It does break every test that greps argv for `claude -p` (§2a). |

---

## 1. Flag and env map

"Native" names the `ClaudeAgentOptions` field. Option field lines are in `types.py`; the argv emission lines are in `T:`.

| Harness today (where) | SDK mapping | Kind | Citation / note |
|---|---|---|---|
| `-p "$prompt"` (`run_claude_session`, providers.sh:1161) | `query(prompt=str)`: written to stdin as a `user` frame | native (different wire) | C:180-198. No `-p` in argv. |
| `--append-system-prompt-file F` (providers.sh:1161, run-bench.sh) | `system_prompt={"type":"preset","preset":"claude_code"}` + `extra_args={"append-system-prompt-file": F}` | **extra_args** (plus a required preset) | Trap 1. `--append-system-prompt-file` isn't in `--help` but is referenced there under `--bare` ("--append-system-prompt[-file]"). |
| `--output-format stream-json --verbose` (`STREAM_FLAGS`) | always emitted | native, forced | T:574 |
| (none) | `--input-format stream-json` always added | forced | T:793 |
| `--output-format json` (bench judge, run-bench.sh:296) | no equivalent; read `ResultMessage.result` | gap, not needed | the transport forces stream-json |
| `--include-partial-messages` | `include_partial_messages` | native, **unused by the harness** | T:694-695 |
| `--model M` (`session_flags`) | `model` | native | Y:2070, T:622-623 |
| `--fallback-model M` | `fallback_model` | native | Y:2076, T:625-626 |
| `--effort L` (`effort_flags`, anthropic only) | `effort` (`Literal low/medium/high/xhigh/max`) | native | Y:37, Y:2372, T:777-778. Same set the harness validates. |
| `--autocompact N` (`session_flags`) | `extra_args={"autocompact": "120000"}` | **extra_args** | No field; the [help] shows `--autocompact <auto\|tokens>`. |
| `--max-budget-usd X` (omitted when 0) | `max_budget_usd: float` | native | Y:2056, T:613-614 |
| (DIGEST_LIMIT / BENCH_LIMIT / JUDGE_LIMIT arrays) | whatever they expand to; the budget via `max_budget_usd` | native | |
| `--tools "Bash,Read,..."` / `--tools ""` | `tools: list[str]`; `[]` emits `--tools ""` | native | Y:1974, T:592-601. Distinct from `allowed_tools` (see the docstring at Y:1975-1983). |
| `--allowedTools a b "Bash(gh issue *)"` | `allowed_tools: list[str]`, comma-joined | native | Y:1985, T:607-608. The CLI tokenizer splits on commas and spaces outside parentheses, so `Bash(gh issue *)` survives. |
| `--disallowedTools ...` | `disallowed_tools` | native | Y:2063, T:616-617 |
| `--permission-mode dontAsk` / `auto` | `permission_mode` | native | `PermissionMode = Literal["default","acceptEdits","plan","bypassPermissions","dontAsk","auto"]` (Y:25-27); T:636-637 |
| `--mcp-config '<json string>'` | `mcp_servers: dict \| str \| Path`; a str is passed verbatim | native | Y:2010, T:667-692. **An empty dict emits nothing** (T:667), so RELEASE's `'{"mcpServers":{}}'` has to be passed as that *string*. |
| `--strict-mcp-config` | `strict_mcp_config=True` | native | Y:2018, T:700-701 |
| `--plugin-dir D` | `plugins=[{"type":"local","path":D}]` | native | Y:2343, T:733-738 |
| `--settings <json or file>` (`guard_settings`, `agent-settings/implementer*.json`) | `settings: str`, passed verbatim when no `sandbox` | native | Y:2105-2117, T:473-489, 657-660 |
| `--setting-sources project,local` / `local` | `setting_sources=[...]`, emitted as `--setting-sources=a,b` | native | Y:2297, T:729-730. Trap 2. |
| cwd (`cd "$dir"` in a subshell) | `cwd`; the SDK also sets `PWD` | native | Y:2096, T:867-878 |
| `< /dev/null` | n/a: stdin is the control pipe | n/a | T:873-876 |
| `2>&1 \| render_stream` | stderr is piped only if you pass a `stderr=callable` (per line); otherwise it is inherited | native (different shape) | Y:2152, T:870-871, 917-960 |
| `tee -a $LOGS/<role>.jsonl` (raw events) | no raw hook: `query()` yields parsed objects, and **unknown types are dropped** | **gap** | P:391-395. Needs a transport subclass that tees `read_messages()` (§3). |
| `perl -e 'alarm ...'` (judge timeout) | `anyio.fail_after(...)` around the iteration | Python-side | |
| `export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` | inherited from `os.environ`, or put it in `env={...}` | native (env) | T:819-825 |
| `export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=1800000` | inherited, **and the SDK reads it too** to bound its own wait for "idle" | native | Q:55-80, `run_end_ceiling_ms` |
| `SESSION_ENV`: `HARNEST_SESSION_KIND/TARGET/ROLE/TICKET_REPO` (for guard.py) | `env={...}`, merged over `os.environ` | native | Y:2124-2137, T:820-825 |
| `MODEL_ENV` sets: `ANTHROPIC_BASE_URL=…`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_DEFAULT_*_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, `ENABLE_TOOL_SEARCH`, … (ollama/gateway) | `env={...}` | native | same |
| `MODEL_ENV` unsets: `env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL` (anthropic branch) | **no unset**: `env` is `dict[str,str]` merged over the full `os.environ` | **gap** | T:819-825. Workarounds in §2e. |
| (added by the SDK, not by the harness) | `CLAUDE_CODE_ENTRYPOINT=sdk-py` (overridable), `CLAUDE_AGENT_SDK_VERSION` (not overridable), `CLAUDE_CODE_SDK_READS_SESSION_STATE=1`, `PWD`; `CLAUDECODE` is stripped | new | T:819-868. Whether the `sdk-py` entrypoint changes any CLI behaviour, such as auto-mode availability, is **[unverified]**. |
| `--agents` (unused) | `agents` goes over the initialize request, not argv | native | T:726-727, Q:342-343 |
| version probe (none today) | the SDK runs `<cli> -v` with a 2 s timeout before every connect; skip it with `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK=1` | new | T:809-810, 1164-1210 |

---

## 2. The decisive questions

| Q | Answer | Evidence |
|---|---|---|
| **a. Handshake: would today's stub work?** | **No.** | See below. |
| **b. Rate-limit events, cost, per-model usage?** | **Yes**, all surfaced. | See below. |
| **c. Are `dontAsk` and `auto` native?** | **Yes.** | `PermissionMode` Literal includes both (Y:25-27), emitted as `--permission-mode` (T:636-637). The CLI [help] lists `acceptEdits, auto, bypassPermissions, manual, dontAsk, plan`; note the SDK says `default` where the CLI says `manual`. |
| **d. Does the settings-file `guard.py` hook still run?** | **Yes**, as far as the SDK is concerned. | See below. |
| **e. Can env be scrubbed?** | **Not natively.** | See below. |
| **f. Native `max_budget_usd`, `autocompact`, `effort`, `tools`?** | `max_budget_usd` **yes** (Y:2056). `effort` **yes** (Y:2372). `tools` **yes**, as a base-set whitelist separate from `allowed_tools` (Y:1974). `autocompact` **no**: use `extra_args` (§1). | |
| **g. CLI version and bundling** | The wheel **bundles its own CLI** (`_bundled/claude`, 225 MB, 2.1.283) and prefers it over PATH (T:257-260). The minimum external CLI is 2.0.0 (T:37); `verbatim_prompts` needs 2.1.248 (T:40). On this machine: bundled 2.1.283 vs `~/.local/bin/claude` 2.1.283, identical today. The drivers run `~/.local/bin/claude`, which auto-updates; the bundled one moves only with the wheel. **Pin `cli_path`.** | |
| **h. Python and dependencies** | `Requires-Python >=3.10`, and the local 3.13.1 is fine. **A venv is needed.** | Direct deps: `anyio>=4`, `jsonschema`, `mcp>=1.23,<3`, `sniffio`. `mcp` 2.2.0 in turn pulls `pydantic>=2.12`, `httpx2`, `starlette`, `sse-starlette`, `uvicorn`, `pyjwt[crypto]`, `python-multipart`, `opentelemetry-api`, `mcp-types`, `typing-inspection`. None of these are installed in the system python3: `import anyio` and `import mcp` both fail. Each wheel is platform-specific because it carries a 225 MB CLI. |

### a. Why the current stub fails under the SDK

1. **The SDK always performs a control-protocol handshake.**
   - `query()` spawns the CLI with `--input-format stream-json`, writes `{"type":"control_request","request_id":…,"request":{"subtype":"initialize",…}}` to stdin, and waits up to 60 s for a matching `control_response` (C:175-178, Q:309-363, Q:706-751).
   - Only after that does it write the user message (C:180-198).
2. **The stub never answers.**
   - The stub in `tests/test-drivers.sh:26-31` ignores stdin, prints two lines and exits 0.
   - With exit 0 the reader finishes normally. Pending control requests are failed early only on the exception path (Q:505-553), so `initialize` sits for the **full 60 s**.
   - It then raises `Exception("Control request timeout: initialize")` (Q:748-751).
   - Depending on timing, the later `write()` of the user message can also hit a dead pipe and raise `CLIConnectionError` (T:1063-1087).
3. **The canned lines also fail strict parsing.**
   - The stub's `result` lacks `is_error`, `duration_api_ms` and `session_id`, which are required (P:308-330).
   - The `rate_limit_event` lines in `tests/fixtures/stream.jsonl` lack `uuid` and `session_id`, which are required (P:356-375).
   - Both raise `MessageParseError` and end the session.
   - Also, `tests/fixtures/stream.jsonl` line 9 (`"message":"not an object"`) and its plain-text line cannot be replayed through the SDK as they are through `render_stream`. The non-JSON line is skipped (T:213-215); the bad assistant frame raises.
4. **Argv assertions break.**
   - The SDK first runs `<cli> -v` (an extra stub call; T:1164+).
   - It never passes `-p`, and the prompt isn't in argv.
   - So every `grep -c 'claude -p' "$FAKE_CLAUDE_LOG"` in test-drivers.sh (lines 58, 67, 79, 90, 101, 197, 246, 266, 298, 308, 340, 357, 417) must change, for example to count `--input-format stream-json` launches.

**Cheapest fake: keep a bash or python stub and pass `cli_path=<stub>`, but make it speak about five lines of protocol.**
- `-v` → print `2.1.283 (Claude Code)` and exit. Or export `CLAUDE_AGENT_SDK_SKIP_VERSION_CHECK=1`.
- Read the first stdin line (the initialize request), extract `request_id`, and print `{"type":"control_response","response":{"subtype":"success","request_id":"<id>","response":{}}}`.
- Read the next line (the user message; the stub can log its `.message.content` in place of `$*`'s prompt).
- Run `FAKE_CLAUDE_DO`, then print a complete `system/init` frame and a complete `result` frame:
  - required: `subtype, duration_ms, duration_api_ms, is_error, num_turns, session_id`
  - plus: `total_cost_usd, usage, modelUsage`
  - plus: a `rate_limit_event` with `uuid` and `session_id` when a test needs one.
- Exit 0. For an error result, exit 1; the SDK then raises `ResultError`.

This keeps the real argv, so flag assertions still work.

**A custom `Transport` class** is simpler to write, but options become CLI flags only inside `SubprocessCLITransport._build_command`. The query.py docstring says command-line options "are not applied to a custom transport" (query.py:63-70). You would lose every flag assertion, so this is only good for unit tests of message handling.

**Where the handshake could bite in production.** Each session now pays one extra `claude -v` spawn and an `initialize` round trip. `initialize` waits for MCP servers to start; its timeout is max(60 s, `CLAUDE_CODE_STREAM_CLOSE_TIMEOUT`) (C:131-135). A slow `dw` server connect over the tailnet should fit inside that. **[unverified]**

### b. Rate-limit events, cost and per-model usage

- `rate_limit_event` becomes a typed `RateLimitEvent(rate_limit_info=RateLimitInfo(status, resets_at, rate_limit_type, utilization, overage_status, …, raw), uuid, session_id)` (P:356-375, Y:1398-1434).
- The fields `render_stream` uses (render_stream in providers.sh ~1040-1044):
  - `.status` → `status`
  - `.resetsAt` → `resets_at`
  - `.rateLimitType` → `rate_limit_type`
  - `.isUsingOverage` is **not a typed field**; read it from `info.raw["isUsingOverage"]`.
- A real event from `logs/*.jsonl` carries `uuid` and `session_id`, so it parses.
- `ResultMessage` has `total_cost_usd`, `usage`, `num_turns`, `duration_ms`, `model_usage` (from `modelUsage`), `permission_denials`, `terminal_reason`, `api_error_status`, `stop_reason` and `errors` (Y:1340-1379, P:308-341).
- Per turn, `AssistantMessage.usage` and `.message_id` exist (Y:1139-1150), so `ctx=` and `ctx_peak` can be computed as today.
- `system/init` arrives as `SystemMessage(subtype="init", data=…)`; the model is `data["model"]` (P:285-288).

### d. The settings-file guard hook

- `settings=` passes the harness's JSON or file straight to `--settings` (T:473-489, 657-660). The CLI loads it into the flag-settings layer, which is independent of `--setting-sources` (Y:2115-2116). That is the same flag the drivers pass today, so the `PreToolUse` command hook `python3 "$HARNEST_HOOKS/guard.py" <role>` keeps running.
- `HARNEST_HOOKS` and `HARNEST_SESSION_KIND` reach it via the inherited env or `env=`.
- SDK callback hooks (`hooks=`) travel separately, as `hookCallbackIds` in the `initialize` request (Q:318-340). The SDK does nothing to settings hooks. Whether both sets fire on the same call is decided CLI-side. Hooks are merged by source, so both should fire, but this is **[unverified]**: one live run with both would settle it.
- Side effect: any SDK hook or `can_use_tool` makes the SDK hold stdin open until the CLI reports "idle" (Q:1053-1091, `_has_bidirectional_needs`).
- Under `dontAsk`, **`can_use_tool` is never called** [docs]. So for the consumer, lead, reviewer and curator roles, hooks (settings or SDK) are the only programmatic gate. Hooks run first, before deny/allow rules [docs].

### e. Scrubbing env

- The child env is `{**os.environ minus CLAUDECODE, "CLAUDE_CODE_ENTRYPOINT":"sdk-py", **options.env, "CLAUDE_AGENT_SDK_VERSION":…}` (T:819-825).
- `options.env` is `dict[str,str]`, so a key can't be removed through it. Setting `ANTHROPIC_BASE_URL=""` is **not** the same as unset; whether the CLI treats empty as unset is **[unverified]**.
- Workarounds, in order of preference:
  1. **`cli_path` → a wrapper** doing `exec env -u ANTHROPIC_BASE_URL … /path/to/claude "$@"`. Per-session, and the drivers are sequential anyway.
  2. **Pop the keys from `os.environ`** right before `connect()` and restore them after. It works because the drivers are sequential, but it's process-global.
  3. **Subclass `SubprocessCLITransport` and override `connect`.** This means copying roughly 100 lines, since env is built inline.

---

## 3. What the SDK gives, and what the port loses

### Gains relevant to this harness

| Feature | Use here | Evidence |
|---|---|---|
| Typed `ResultMessage` / `RateLimitEvent` / `AssistantMessage.usage` | replaces the jq renderer, and the grep on rendered text in `session_ok`/`session_ran`/`session_died`/`sleep_if_rate_limited` (providers.sh 1083-1128) | P:308-375 |
| `ResultError` with `.subtype`, `.terminal_reason`, `.errors` | a budget cut-off, max turns or an API error becomes a typed branch, not a grep for `^result:` | `_errors.py:56+`, Q:505-535 |
| SDK hooks (Python callbacks: PreToolUse, PostToolUse, Stop, PreCompact, SubagentStart, PermissionRequest, …) | guard.py logic could run in-process with driver state (session kind, whether an MCP call was seen) instead of env vars and a stamp file. Keep the settings hook until parity is proven. | Y:285-294, 594-620 |
| `can_use_tool` | only for the implementer's `auto` mode (never called under `dontAsk`) | Y:278-280, 1926-1949 [docs] |
| `ClaudeSDKClient.interrupt()`, `set_model()`, `set_permission_mode()`, `get_context_usage()`, `get_mcp_status()`, `stop_task()` | abort a runaway session on a driver-side condition, check that `dw` connected before spending a turn, and read context size | client.py:308-566 |
| `resume` / `session_id` / `fork_session` | pick up a budget-cut session by id rather than by the GitHub-comment trail (optional) | Y:2040-2043, T:647-655 |
| `output_format={"type":"json_schema",…}` → `structured_output` | digest rows and judge verdicts without tab/regex parsing | T:782-789, Y:1352 |
| `stderr` per-line callback | clean stderr capture (today it's `2>&1` mixed into the jsonl) | T:917-960 |
| Orphan cleanup: `atexit` SIGTERM of live children, and bounded close (5 s → SIGTERM → SIGKILL) | a crashed Python driver doesn't leave `claude` running | T:54-68, 962-1061 |

### Losses and behaviour changes the port must handle

| Change | Consequence | Evidence |
|---|---|---|
| **An `is_error` result becomes a raised `ResultError`** after the `ResultMessage` is yielded. The CLI exits non-zero, and the SDK swaps the ProcessError for a ResultError. | A budget cut-off (`error_max_budget_usd`) or a rejected-rate-limit session reaches the driver as an exception. Catch it, and still classify the session as "ran" and "not ok", as `session_ran`/`session_ok` do now. | Q:505-535, `_errors.py:56-81` |
| **Parse failures are fatal**: a missing required field or a malformed frame raises `MessageParseError` | The jq renderer's "a bad event prints `render-error:` and the pipe keeps going" tolerance is gone. One odd frame kills the session iterator. | P:50-95, 308-375 |
| **Unknown message types are dropped silently** | `<role>.jsonl` can't be rebuilt from parsed messages. Future CLI frame types vanish. | P:391-395 |
| No raw-event hook | Keep `<role>.jsonl` by subclassing `SubprocessCLITransport` and overriding `read_messages()` to tee each raw dict before yielding. Pass the subclass instance as `transport=`. If `can_use_tool` is ever used, build it with `_configure_can_use_tool(options)` applied, since a supplied transport skips that step (C:81, 88-95). | T:1097-1162 |
| JSON line size limit: 1 MB per stdout line by default, then `CLIJSONDecodeError` | A very large MCP tool result echoed in a `user` frame could exceed it. Set `max_buffer_size` (e.g. 16 MB). | T:36, 1110-1127, Y:2146 |
| A version probe and an `initialize` round trip per session | a small latency, and a 60 s+ failure mode if the CLI stalls before init | T:809-810, C:131-135 |
| `sdk-py` entrypoint instead of print mode | Behaviour should match headless `-p`, but auto mode's availability and the classifier's context under the SDK entrypoint are **[unverified]**. Check one implementer session. | T:822 |
| Bundled CLI by default | silent CLI version skew from what the bash drivers ran | Trap 3 |
| A venv and about 15 packages plus a 225 MB wheel | the drivers are no longer "bash + jq + python3 stdlib" | §2h |

### Nothing is lost on

`--tools`, `--allowedTools`, `--disallowedTools`, `--permission-mode dontAsk|auto`, `--mcp-config`, `--strict-mcp-config`, `--plugin-dir`, `--settings`, `--setting-sources`, `--effort`, `--fallback-model`, `--model`, `--max-budget-usd` and cwd. All are native fields. Only `--append-system-prompt-file` and `--autocompact` need `extra_args` (T:740-755 emits `--flag value`, or `--flag=value` when the value starts with `-`), and env unsetting needs a workaround.
