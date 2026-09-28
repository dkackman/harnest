# Harness code inventory for R13 step 1 (target profile) and R8 (Agent SDK port)

Read-only inventory of /Users/don/testing/harnest at HEAD be9a72e (2026-09-27). Line numbers are
from the working tree at the time of reading. The only uncommitted change was
regression-suite-model-specific.md, which is out of scope.

Scope: providers.sh, run-*.sh (loop, regression, features, curate, retro, digest, bench, release),
lib/classify.jq, lib/release.sh, agent-settings/hooks/guard.py, agent-settings/implementer{,.local}.json,
dashboard/serve.py, measure-base-ctx.sh, scripts/*.sh, contract/*.py, bench/snapshot.py, and
tests/{lib.sh,test-drivers.sh,test-providers.sh,fake-gh.py} for the test seams.

For the SDK columns I also read the installed claude-agent-sdk 0.2.152 at
~/.claude/security/agent-sdk-venv/.../claude_agent_sdk. It is outside the repo, and I only read it.
Where that source didn't settle a question, the entry says "unknown".

**The SDK columns here are from 0.2.152. `sdk.md` read 0.2.160 and is the authority on the SDK;
its line numbers differ from the ones here.**

Classes used below:
- **framework**: generic loop machinery. It stays in the Python package.
- **dw-target**: a value or rule that belongs to the dw target. It goes to the profile or the pack.
- **per-server-target**: the lem/local axis (harnest#15). It becomes the profile's servers table.
- **test-only**: read only by the tests or fakes.

---

## 1. ENV KNOBS (the port's compatibility contract)

### 1a. How the list was derived

tests/test-lint.sh:19-26 runs the extraction below and then excludes `SESSION_HEADER` and
`TMPDIR` as internal:

    grep -ohE '\$\{[A-Z][A-Z0-9_]+:-' run-*.sh providers.sh | sed 's/\${//; s/:-//' | sort -u

It returns 122 names, listed in 1b. That extraction misses the following, which 1c adds:
- reads in scripts/*.sh, which lint doesn't scan;
- reads in the Python files: guard.py, dashboard, contract and bench/snapshot;
- `${X:?}` reads;
- `${!bvar}` indirect reads (run-curate.sh:106);
- plain `$X` reads of variables a driver exports for its children (the `HARNEST_*` family).

**Port consequence:** once the drivers are Python, the lint's knob check finds zero `${X:-}` reads
in the drivers and passes vacuously. It has to be reimplemented, for example by scanning for
`os.environ.get("X"` or reading a central knob table.

### 1b. Knobs read as `${NAME:-default}`

The file:line references are every `${NAME:-` read. `tsfx` is `-mps` when `DW_TARGET != lem`,
otherwise empty (run-loop.sh:79, run-features.sh:41).

| name | default | default depends on | read at (file:line) | controls | class |
|---|---|---|---|---|---|
| AUTOCOMPACT_TOKENS | 120000 | - | run-loop:182 run-regression:97 run-features:59 run-curate:41 run-retro:27 run-release:57 run-bench:57 providers:1138 | `--autocompact` per session | framework |
| BENCH_BUDGET_USD | 4 | - | run-bench:49 | replay session `--max-budget-usd` (0 = none, :133) | framework (bench) |
| BENCH_JOBS | 1 | - | run-bench:58 | parallel cases via `xargs -P` (:334) | framework (bench) |
| BENCH_LABEL | `$IMPLEMENTER_PROVIDER/$IMPLEMENTER_MODEL@$PROMPT_ID` | the prompt rev | run-bench:112 (exported :333) | results grouping key | framework (bench) |
| BENCH_PROMPT_REV | "" (working tree) | - | run-bench:59 | which implementer prompt is replayed | framework (bench) |
| BENCH_RESCORE | 0 | - | run-bench:169,225 | 1 = rescore a kept session; judge = re-judge only | framework (bench) |
| BENCH_WORK | `${TMPDIR:-/tmp}/harnest-bench` | TMPDIR | run-bench:39 | work dir for replay clones | framework (bench) |
| CASES_PER_SESSION | "" | "" means 3 if MODEL_CONTEXT_TOKENS < 120000, else 8 (run-regression:196-202); 0 means one session per level | run-regression:91 | regression chunk size | framework |
| CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS | 1800000 | - | providers:498 (exported) | how long the claude child waits for background subagents | framework (child env) |
| CO_AUTHOR / CO_AUTHOR_EMAIL | derived by co_author_for | captured at source time (providers:76-77) | providers:76,77,912 | Co-Authored-By trailer on suite commits | framework |
| CURATE_BUDGET_USD | 6 | - | run-curate:37 | audit session cap | framework |
| CURATE_BUDGET_SMOKE / _COMPLETE / _MODEL_SPECIFIC / _SECURITY | "65 16" / "60 20" / "60 12" / "15 6" | - | run-curate:45-48, read indirectly via `${!bvar}` at :106 | per-level minutes and USD budget stated to the curator | dw-target (level names are dw's suite levels) |
| CURATE_EFFORT | $EFFORT | EFFORT | run-curate:57 | --effort | framework |
| CURATE_EVERY_DAYS | 7 | - | run-curate:38 | re-curation interval (stamp `logs/.curated-<level>`) | framework |
| CURATE_FORCE | 0 | - | run-curate:39 | ignore the stamp and any open request | framework |
| CURATE_MODEL | claude-opus-5-5 | - | run-curate:35 | audit model | framework |
| CURATE_PROVIDER | $PROVIDER | PROVIDER | run-curate:36 | | framework |
| CURATE_RUNS | 3 | - | run-curate:40 | runs in the chunk cost table | framework |
| CURATOR_EFFORT | $EFFORT | EFFORT | run-loop:245 | curator review sessions | framework |
| CURATOR_MODEL | $TESTER_MODEL | TESTER_MODEL | run-loop:154 | | framework |
| CURATOR_PROVIDER | $TESTER_PROVIDER | | run-loop:155 | | framework |
| CURATOR_REVIEW_BUDGET_USD | 3 | - | run-loop:156 | | framework |
| DEPLOY_ON_MISMATCH | 1 | - | run-loop:427 | driver redeploys develop when the server is behind | framework (mechanism) |
| DIGEST_BUDGET_USD | 1 | - | run-digest:28 | | framework |
| DIGEST_CURATOR_DAYS | 7 | - | run-digest:35 | window of the curator-rulings section | framework |
| DIGEST_ISSUE | "" | - | run-digest:30 | also post the digest to this issue | framework |
| DIGEST_MODEL | sonnet | - | run-digest:26 | | framework |
| DIGEST_PROVIDER | $PROVIDER | | run-digest:27 | | framework |
| DW_LOCAL_DIR | $HOME/src/dkackman/dw-mps-serve | - | providers:598 (also scripts/setup-mac-loop.sh:60 through providers) | serving clone of the local server | per-server-target |
| DW_LOCAL_WORKSPACE | $HOME/dw-mps-workspace | - | providers:599; scripts/sync-fixtures.sh:31 (default there: asked of the server) | local server's `--workspace` | per-server-target (dw) |
| DW_TARGET | lem | - | providers:596,606,701,719,735,753,1288; run-loop:79; run-features:41 | which server: lem or local | per-server-target |
| DW_TOKEN | xyz; `${DW_TOKEN:-}` (empty) at providers:670 | - | run-loop:191 run-features:61 run-regression:105 providers:670; scripts/sync-fixtures:30; contract/run.py:152 | MCP bearer token | dw-target |
| DW_URL | "", filled by resolve_target | lem: http://lem:8765/mcp; local: http://localhost:8765/mcp (providers:622,626). contract/run.py:151 defaults to lem's; sync-fixtures:29 defaults to localhost | run-loop:190 run-features:60 run-regression:98 providers:622,626 | MCP endpoint | per-server-target |
| EFFORT | medium | - | providers:511 | default for every *_EFFORT | framework |
| FALLBACK_MODEL | "" | - | run-loop:164 run-regression:90 run-features:54 run-curate:42 run-release:56 providers:1134 | `--fallback-model` | framework |
| GW_BASE_URL | required for gateway | - | providers:205 | provider env | framework (provider) |
| GW_CONTEXT_TOKENS | "" | - | providers:217 | declared context window | framework (provider) |
| GW_TOKEN | "" | - | providers:213 | gateway auth | framework (provider) |
| HARNESS_REPO | dkackman/harnest | - | run-loop:91 run-curate:29 run-digest:31 run-retro:20 run-release:44; dashboard/serve.py:53 | where suite and harness proposals go | dw-target (value) |
| HARNEST_HELD_LOCK | "" | set by run-loop:818 (nightly, through env) and run-release:307 | providers:833 | child driver runs under the parent's lock | framework (internal) |
| IMPLEMENTER_BUDGET_USD | 8 | - | run-loop:168 | | framework |
| IMPLEMENTER_EFFORT | $EFFORT | | run-loop:241 run-bench:66 | | framework |
| IMPLEMENTER_ESCALATE_AFTER | 2 | - | run-loop:135 | bounces before the tester's model takes over | framework |
| IMPLEMENTER_MODEL | sonnet | - | run-loop:117 run-bench:41 | | framework |
| IMPLEMENTER_PARK_AFTER | 4 | - | run-loop:136 | bounces before parking with owner:don (also used for lead stages and close-outs, :557,590) | framework |
| IMPLEMENTER_PROVIDER | $PROVIDER | | run-loop:119 run-bench:42 | | framework |
| JUDGE_BUDGET_USD | 1 | - | run-bench:50 | | framework (bench) |
| JUDGE_EFFORT | high | - | run-bench:56 | passed as `--effort` unconditionally (:294) | framework (bench) |
| JUDGE_MODEL | claude-opus-5-5 | - | run-bench:45 | | framework (bench) |
| JUDGE_PROVIDER | anthropic | not $PROVIDER | run-bench:46 | | framework (bench) |
| JUDGE_TIMEOUT_SECS | 150 | - | run-bench:51 | `perl -e alarm` wrapper (:294) | framework (bench) |
| JUDGE_TRIES | 3 | - | run-bench:52 | | framework (bench) |
| LEAD_CLOSEOUT_BUDGET_USD | 3 | - | run-loop:180 | | framework |
| LEAD_DECOMPOSE_BUDGET_USD | 4 | - | run-features:58 | | framework |
| LEAD_DESIGN_BUDGET_USD | 6 | - | run-features:57 | | framework |
| LEAD_DESIGN_IN_LOOP | 1 | - | run-loop:179 | features_pass runs run-features.sh | framework |
| LEAD_EFFORT | $EFFORT | | run-loop:244 run-features:73 | | framework |
| LEAD_MODEL | $TESTER_MODEL (loop); `${TESTER_MODEL:-claude-opus-5-5}` (features) | TESTER_MODEL | run-loop:143 run-features:52 | | framework |
| LEAD_PROVIDER | $TESTER_PROVIDER / `${TESTER_PROVIDER:-$PROVIDER}` | | run-loop:144 run-features:53 | | framework |
| LEAD_STAGES_PER_CYCLE | 1 | - | run-loop:149 | | framework |
| LEAD_STAGE_BUDGET_USD | 15 | - | run-loop:176 | | framework |
| LEAD_TREE | $HOME/src/dkackman/dw-agent-lead$tsfx | DW_TARGET via tsfx | run-loop:88 run-features:43 | the lead's read-only worktree at origin/develop | dw-target value plus per-server suffix |
| LEAD_WORKER_MODEL | sonnet | - | run-loop:145 | model named in the build prompt for code subagents | framework |
| MAX_CYCLES | 0 (forever) | - | run-loop:94 | | framework |
| NO_PROGRESS_PARK_AFTER | 2 | - | providers:1384 | no-progress ledger threshold | framework |
| OLLAMA_BASE_URL | http://127.0.0.1:11434 | - | providers:165 | | framework (provider) |
| OLLAMA_CONTEXT_TOKENS | required for ollama | - | providers:152 | | framework (provider) |
| OLLAMA_STRICT_SUPPRESS | "" | - | providers:192 | | framework (provider) |
| OLLAMA_TOKEN | ollama | - | providers:169,170 | | framework (provider) |
| ONLY_ISSUES | "" | - | run-loop:108 run-features:47 providers:1319 | narrows every queue | framework |
| PLUGIN_TREE | $HOME/src/dkackman/dw-agent-plugin$tsfx (loop); **no tsfx** in run-regression | DW_TARGET in loop only | run-loop:86 run-regression:77 | consumer plugin worktree at origin/develop; `$PLUGIN_TREE/plugins/dw` is the plugin dir (loop:196, reg:170) | dw-target value plus per-server suffix |
| PROVIDER | anthropic | - | all 8 drivers (run-loop:109 run-regression:80 run-features:48 run-curate:32 run-retro:23 run-digest:25 run-release:46 run-bench:40) | | framework |
| REGRESSION_BUDGET_USD | 6 | - | run-regression:96 | | framework |
| REGRESSION_EFFORT | $EFFORT | | run-regression:182 | | framework |
| REGRESSION_MODEL | sonnet | - | run-regression:88 | | framework |
| REGRESSION_NIGHTLY_AT | "" (off) | - | run-loop:101 | hour for the nightly regression | framework |
| REGRESSION_NIGHTLY_LEVEL | all | - | run-loop:102 | run-regression.sh arguments | dw-target (level names) |
| REGRESSION_PROVIDER | $PROVIDER | | run-regression:89 | | framework |
| RELEASE_EFFORT | $EFFORT | | run-release:80 | | framework |
| RELEASE_FORCE | 0 | - | run-release:311,347 | rerun a gate or review that already passed | framework |
| RELEASE_MODEL | `${TESTER_MODEL:-claude-opus-5-5}` | TESTER_MODEL | run-release:49 | | framework |
| RELEASE_NOTES_BUDGET_USD | 3 | - | run-release:53 | | framework |
| RELEASE_PROVIDER | `${TESTER_PROVIDER:-$PROVIDER}` | | run-release:50 | | framework |
| RELEASE_REGRESSION_LEVELS | "security complete" | - | run-release:55 | levels of the regression gate | dw-target (level names) |
| RELEASE_REVIEW_BUDGET_USD | 8 | - | run-release:52 | per review area | framework |
| RELEASE_TREE | $HOME/src/dkackman/dw-agent-release | - | run-release:41 | release worktree | dw-target value |
| RETRO_BUDGET_USD | 5 | - | run-retro:26 | | framework |
| RETRO_EFFORT | $EFFORT | | run-retro:36 | | framework |
| RETRO_EVIDENCE_ONLY | 0 | - | run-retro:138 | print the digest only | framework |
| RETRO_MODEL | claude-opus-5-5 | - | run-retro:24 | | framework |
| RETRO_PROVIDER | $PROVIDER | | run-retro:25 | | framework |
| REVIEWER_BUDGET_USD | 2 | - | run-loop:163 | | framework |
| REVIEWER_EFFORT | $TESTER_EFFORT | | run-loop:246 | | framework |
| REVIEWER_MODEL | $TESTER_MODEL | | run-loop:161 | | framework |
| REVIEWER_PROVIDER | $TESTER_PROVIDER | | run-loop:162 | | framework |
| SESSION_HEADER | label | set inline per call: run-loop:356, run-curate:127, run-release:330 | providers:1159 | the `=== ... ===` header text (lint treats it as internal) | framework (internal) |
| SESSION_RETRY_PAUSE_SECS | 30 | tests set 0 | providers:1106 | pause before retrying a died session | framework |
| SHARED_PASSES | "" (auto) | lem always; other targets only while lem's loop isn't running | run-loop:195 (read :828) | server-free passes (features, reviewer, curator) | per-server-target |
| SLEEP_SECS | 120 | - | run-loop:93 | idle sleep between unchanged cycles | framework |
| SOURCE_DIR | $HOME/src/dkackman/dw-agent$tsfx (loop, features); $HOME/src/dkackman/dw-agent with **no tsfx** (regression, release, bench); ...-mps (setup-mac-loop:27) | DW_TARGET inconsistently | run-loop:83 run-features:42 run-regression:76 run-release:37 run-bench:35; scripts/file-advisory.sh:22; bench/snapshot.py:11 | the agents' source clone | dw-target value plus per-server suffix |
| TARGET_SKIP_CASES | "S-F079 C-F005 C-F007 C-F023 C-F047" | used only when TARGET_SUFFIX is set | run-regression:104 | cases never handed out on a non-lem server | per-server-target (dw case IDs) |
| TESTER_BUDGET_USD | 5 on lem, 8 elsewhere | DW_TARGET (tsfx) | run-loop:170 | | framework, per-server default |
| TESTER_EFFORT | $EFFORT | | run-loop:242 | | framework |
| TESTER_MODEL | claude-opus-5-5 | - | run-loop:118 (also read as a fallback by run-features:52 and run-release:49) | | framework |
| TESTER_PROVIDER | $PROVIDER | | run-loop:120 (also features:53, release:50) | | framework |
| TESTER_SPEC_BUDGET_USD | 8 | - | run-loop:181 | | framework |
| TESTER_TASK_EVERY | 4 | - | run-loop:189 | standing-task cadence | framework |
| TICKET_OWNER | dkackman | - | run-loop:90 run-features:45 run-digest:23 run-release:43 (**not** set by run-regression, run-curate or run-retro) | trusted login; others' comments are withheld | dw-target (value) |
| TICKET_REPO | dkackman/diffusers-workflow | - | run-loop:89 run-regression:78 run-features:44 run-curate:28 run-retro:19 run-digest:22 run-release:42; scripts/file-advisory.sh:20; dashboard/serve.py:52; bench/snapshot.py:12; tests/fake-gh.py:60 | ticket repo | dw-target (value) |
| TMPDIR | /tmp | - | run-bench:39 run-release:429 | (lint treats it as internal) | framework |
| TRIAGE_BUDGET_USD | 3 | - | run-loop:171 | | framework |
| TRIAGE_EFFORT | $TESTER_EFFORT | | run-loop:243 | | framework |
| TRIAGE_MODEL | $TESTER_MODEL | | run-loop:125 | | framework |
| TRIAGE_PROVIDER | $TESTER_PROVIDER | | run-loop:126 | | framework |

### 1c. Knobs and env reads the lint extraction misses

| name | default | read at | set by | controls | class |
|---|---|---|---|---|---|
| HARNEST_BASE_COMMIT | "" | guard.py:254 | run-loop:459-460 `set_base_commit`, which exports it into the **driver's** environment | base for the hand-off gate's relative test comparison | framework (child env) |
| HARNEST_SESSION_KIND | unset | guard.py:493 | run-loop:354 (SESSION_ENV) only | a tester handoff session may close without an MCP call | framework (child env) |
| HARNEST_TARGET | "lem" in guard | guard.py:363 | run-loop:354, run-regression:162 | target-specific guard rules | per-server-target (child env) |
| HARNEST_ROLE | "regression" in guard | guard.py:404 | run-loop:354, run-regression:162 | tester or regression for the Edit/Write rule | framework (child env) |
| HARNEST_TICKET_REPO | "" | guard.py:428 | run-loop:355, run-regression:162 | the only repo a non-lem consumer may file on | dw-target value (child env) |
| HARNEST_HARNESS_REPO | dkackman/harnest, **hard-coded fallback** | guard.py:357,429 | **nothing sets it** | the exception for suite requests | dw-target value (see Surprises) |
| HARNEST_ROOT | "" | guard.py:381; the prompts mention `$HARNEST_ROOT/scripts/file-advisory.sh` (guard.py:453) | exported at providers:319-320 | harness checkout | framework (child env) |
| HARNEST_HOOKS | - | expanded by the hook's shell inside the settings command strings (providers:333, implementer.json:27) | exported at providers:315-316 | where guard.py lives | framework (child env) |
| HARNEST_LIB, HARNEST_AGENTS | - | providers:1295,1422 | computed | path constants, not env | framework |
| SUITE_EDITS | 0 (providers:602) | providers:948 | run-loop:230 `export SUITE_EDITS=1` | a non-lem loop may commit suite files | per-server-target |
| LOGS | `$REPO/logs` is **hard-assigned** in every driver (loop:92 reg:79 features:46 curate:31 retro:22 digest:24 release:45; bench:37 uses `$REPO/logs/bench`), so an env value is ignored | scripts/setup-mac-loop.sh:22 `${LOGS:-...}`; tests/lib.sh:17 exports it for providers-level tests | - | state and log root | framework |
| CURATE_BUDGET_* (indirect) | see 1b | run-curate:106 `${!bvar}` | - | - | dw-target |
| DASHBOARD_PORT | 8780 | dashboard/serve.py:538 | - | dashboard port | framework |
| ADVISORY_PACKAGE | diffusers-workflow | scripts/file-advisory.sh:21 | - | pip package named in draft advisories | dw-target |
| DW_ORIGIN_URL | https://github.com/dkackman/diffusers-workflow.git | scripts/setup-mac-loop.sh:26 | - | clone source | dw-target |
| FIXTURE_SOURCE | lem:diffusers-workspace/common/assets | scripts/sync-fixtures.sh:27 | - | rsync source | dw-target / per-server-target |
| FIXTURE_BWLIMIT_KBPS | 20000 | scripts/sync-fixtures.sh:28 | - | | dw-target |
| DW_DIR | required (`:?`) | scripts/deploy-local.sh:15 | deploy_cmd (providers:741) | serving clone | per-server-target (child env) |
| DEPLOY_RECORD | $REPO/logs/.deployed.local | scripts/deploy-local.sh:17 | deploy_cmd (providers:741) | where the local deploy writes its head | per-server-target |
| DW_URL, DW_TOKEN in Python | http://lem:8765/mcp, xyz | contract/run.py:151-152 | run-regression passes `--url`/`--token` (:317) | contract runner | per-server-target |
| SOURCE_DIR, TICKET_REPO in Python | ~/src/dkackman/dw-agent, dkackman/diffusers-workflow | bench/snapshot.py:11-12 | - | bench case freezing | dw-target |
| TICKET_REPO, HARNESS_REPO in Python | as in 1b | dashboard/serve.py:52-53 | - | dashboard's Attention card | dw-target |
| HOME | - | every `$HOME/src/dkackman/...` default | - | | - |
| FAKE_GH_BOARD, FAKE_GH_FAIL, FAKE_GH_LOG, FAKE_GH_ON_EDIT_<n> | - | tests/fake-gh.py:4-9,106 | tests | fake gh behaviour | test-only |
| FAKE_CLAUDE_LOG, FAKE_CLAUDE_DO, FAKE_PROMPT | - | tests/test-drivers.sh:26-33 (the stub) | tests | fake claude behaviour | test-only |
| GH_CALLS, T, HARNEST | - | tests/lib.sh:15-19 | tests | stub_gh call log | test-only |

### 1d. Environment a driver builds for a child process

These are not user knobs. The port has to reproduce them exactly.

| child | variables | built at |
|---|---|---|
| local deploy (`bash -c "$(deploy_cmd)"`) | `DW_DIR=$DW_LOCAL_DIR DW_WORKSPACE=$DW_LOCAL_WORKSPACE DW_HOST=127.0.0.1 DW_PORT=<from DW_URL, default 8765> DEPLOY_RECORD=$LOGS/.deployed.local` | providers:741, run at :746 |
| run-features.sh from features_pass | `LEAD_MODEL LEAD_PROVIDER LEAD_EFFORT PROVIDER SOURCE_DIR LEAD_TREE DW_TARGET TICKET_REPO TICKET_OWNER DW_URL DW_TOKEN FALLBACK_MODEL AUTOCOMPACT_TOKENS ONLY_ISSUES` | run-loop:542 |
| run-regression.sh from nightly_regression_pass | `HARNEST_HELD_LOCK="$$ run-loop" DW_TARGET TICKET_REPO TICKET_OWNER SOURCE_DIR PLUGIN_TREE PROVIDER DW_URL DW_TOKEN FALLBACK_MODEL AUTOCOMPACT_TOKENS` | run-loop:818-821 |
| run-regression.sh from gate_regression | the inherited env, plus `HARNEST_HELD_LOCK` exported at run-release:307 | run-release:269 |
| preflight | `PATH="$SOURCE_DIR/venv/bin:$PATH" DW_E2E_PYTHON="$SOURCE_DIR/venv/bin/python"` | run-release:251 |
| file-advisory.sh from release | `TICKET_REPO SOURCE_DIR` | run-release:371 |
| pytest in bench and in the guard | `PYTHONPATH=<clone or tree>` | run-bench:141,182; guard.py:294 |
| the claude child | see 2b | |

---

## 2. CLAUDE CLI FLAGS

### 2a. Flags passed to `claude`

SDK mapping is against claude-agent-sdk 0.2.152, `_internal/transport/subprocess_cli.py:_build_command`.

| flag | example value | roles / session kinds | where built | SDK mapping |
|---|---|---|---|---|
| `-p <prompt>` | the per-session prompt, passed as positional argv `$2` | every session | providers:1161 (run_claude_session); run-bench:182 (replay), :294 (judge); run-digest:171; measure-base-ctx:17 | **none**. The SDK never passes `-p`. It always adds `--input-format stream-json` (subprocess_cli.py:783) and sends the prompt over stdin after an `initialize` control request (`_internal/query.py:231-281`). |
| `--append-system-prompt-file <file>` | `$LOGS/.prompt.<role><sfx>.<kind>.md` (role_prompt output, plus the target note appended) | every run_claude_session session; bench replay (:192) | providers:1161; run-bench:192 | **no typed option**. Candidates: `system_prompt={"type":"preset","preset":"claude_code","append":<text>}`, which emits `--append-system-prompt <text>` (:576-578), or `extra_args={"append-system-prompt-file": path}`. **Trap:** `system_prompt=None` emits `--system-prompt ""` (:568-569), which replaces Claude Code's default prompt. |
| `--output-format stream-json --verbose` | - | every run_claude_session session (STREAM_FLAGS); bench replay; measure | providers:1010; run-bench:195; measure-base-ctx:18 | always emitted by the SDK (:566) |
| `--output-format json` | - | bench judge | run-bench:296 | n/a. The SDK is always stream-json; use ResultMessage. |
| (default text output) | - | digest | run-digest:171-179 | n/a |
| `--model` | sonnet, claude-opus-5-5, haiku (measure) | all | session_flags providers:1133; run-bench:190,294; run-digest:178; measure:17 | typed `model` |
| `--fallback-model` | FALLBACK_MODEL | every session_flags user | fallback_model_flags providers:272, via session_flags :1134 | typed `fallback_model` |
| `--effort` | medium | anthropic only through effort_flags (providers:522); bench replay (EFFORT_WORDS :131); bench judge **always**, even for a non-anthropic JUDGE_PROVIDER (:294) | session_flags :1136 | typed `effort` |
| `--autocompact` | 120000 | every session_flags user; bench replay | providers:1138; run-bench:191 | **no typed option found**: extra_args |
| `--max-budget-usd` | 8 / 5 / 3 ... (omitted at 0) | every session_flags user; bench BENCH_LIMIT/JUDGE_LIMIT (:133-134); digest DIGEST_LIMIT (:29) | providers:1139 | typed `max_budget_usd` |
| `--mcp-config '<json>'` | `{"mcpServers":{"dw":{"type":"http","url":"$DW_URL","headers":{"Authorization":"Bearer $DW_TOKEN"}}}}` | implementer, tester, lead build/closeout, reviewer, curator review (MCP_FLAGS); regression; lead design/decompose | run-loop:276; run-regression:236; run-features:82 | typed `mcp_servers` (dict, str or Path) |
| `--mcp-config '{"mcpServers":{}}'` | - | release review/notes | providers:421 (RELEASE_PERMISSION_FLAGS) | typed `mcp_servers={}` |
| `--strict-mcp-config` | - | all of the above, plus curate (:64), retro (:153), digest (:179), bench replay and judge (:193,:295) | as listed | typed `strict_mcp_config` |
| `--plugin-dir` | `$PLUGIN_TREE/plugins/dw`, or `$DW_LOCAL_DIR/plugins/dw` for a local regression run | tester (TESTER_FLAGS), regression | run-loop:286; run-regression:238 | typed `plugins=[{"type":"local","path":...}]` |
| `--setting-sources project,local` | - | tester, implementer, lead build (IMPLEMENTER_FLAGS), lead design, curator review/audit, regression, retro, digest, bench | ISOLATION_FLAGS providers:484 | typed `setting_sources`. The SDK emits the `=` form, and `_apply_skills_defaults` (:595) can change it: check. |
| `--setting-sources local` | - | reviewer (run-loop:765); release (ISOLATION_FLAGS_RELEASE providers:428) | | same |
| `--tools <csv>` | CONSUMER_TOOLS `Bash,Read,Edit,Write,Glob,Grep,ToolSearch,Skill,TodoWrite` | per role: CONSUMER_TOOLS/IMPLEMENTER_TOOLS/LEAD_DESIGN_TOOLS (providers:503-505), REVIEWER_TOOLS (:406), RELEASE_TOOLS (:427), CURATOR_REVIEW_TOOLS (:448), CURATOR_AUDIT_TOOLS (:453), RETRO_TOOLS (:461); `--tools ""` in digest (:179) and bench judge (:295) | | typed `tools` (a list; `[]` emits `--tools ""`) |
| `--settings <file>` | `agent-settings/implementer$TARGET_SUFFIX.json`; bench: a generated `$WORK/.implementer-settings.$$.json` with `.permissions.deny` added (run-bench:118-122) | implementer, lead build/closeout; bench replay | run-loop:302; run-bench:194 | typed `settings: str` (path or JSON string) |
| `--settings '<inline json>'` | `guard_settings <role>` → `{"hooks":{"PreToolUse":[{"matcher":"Bash" or "Bash\|Edit\|Write","hooks":[{"type":"command","command":"python3 \"$HARNEST_HOOKS/guard.py\" <role>","timeout":30}]}]}}` | consumer (tester, regression), lead (design, and release sessions), reviewer, curator review | providers:329-334, used at :337,368,396,419,439 | typed `settings` (string). The SDK could also take guard.py as a Python `hooks` callback, but the guard reads `transcript_path` and env, so keeping the command hook is simpler. |
| `--permission-mode dontAsk` | - | consumer, lead design, reviewer, release, curator review/audit, retro | providers:338,369,397,420,440,455,463 | typed `permission_mode` (the Literal includes "dontAsk", types.py:25-27) |
| `--permission-mode auto` | - | implementer, lead build/closeout; bench replay | run-loop:303; run-bench:194 | typed (the Literal includes "auto") |
| `--allowedTools <word> <word> ...` | `"mcp__dw__*" "ToolSearch" ... "Bash(gh issue *)" ...` as **separate argv words** | consumer (:339-344), lead design (:370-381), reviewer (:398-404), release (:422-425), curator review (:441-446), curator audit (:456), retro (:464-465) | providers | typed `allowed_tools`. The SDK **joins with ","** into one word (:598). Harmless today (no rule has a comma) but it is a difference. |
| `--disallowedTools` | `"mcp__dw__delete_model" "mcp__dw__update_diffusers"` | consumer | providers:345-346 | typed `disallowed_tools` (comma-joined) |
| `--no-session-persistence` | - | measure-base-ctx only | measure:18 | extra_args |
| `--resume`, `--continue`, `--session-id`, `--max-turns`, `--add-dir` | **not used anywhere** | - | grep: no hits | - |

Composite flag sets per session kind, for the port's role table:

| session | cwd | flags (in order) | built at |
|---|---|---|---|
| implementer fix/triage; lead build/closeout | SOURCE_DIR | SESSION_FLAGS + MCP_FLAGS + ISOLATION_FLAGS + `--tools IMPLEMENTER_TOOLS` + `--settings agent-settings/implementer$sfx.json` + `--permission-mode auto` | run-loop:298-304, 481-489, 518-526, 565-577, 600-610 |
| tester spec/verify/handoff/answer/task/closures | REPO (harness) | SESSION_FLAGS + MCP_FLAGS + `--plugin-dir` + ISOLATION + `--tools CONSUMER_TOOLS` + CONSUMER_PERMISSION_FLAGS | run-loop:284-290 |
| reviewer docs | PLUGIN_TREE | SESSION_FLAGS + MCP_FLAGS + `--setting-sources local` + `--tools REVIEWER_TOOLS` + REVIEWER_PERMISSION_FLAGS | run-loop:765 |
| curator review | REPO | SESSION_FLAGS + MCP_FLAGS + ISOLATION + `--tools CURATOR_REVIEW_TOOLS` + CURATOR_REVIEW_PERMISSION_FLAGS | run-loop:798 |
| regression whole/chunk/sweep | REPO | SESSION_FLAGS + REGRESSION_FLAGS (mcp, strict, plugin-dir, isolation, tools, consumer perms) | run-regression:235-242, 263 |
| lead design/decompose | LEAD_TREE | SESSION_FLAGS + LEAD_DESIGN_FLAGS | run-features:81-87, 106 |
| curator audit | REPO | SESSION_FLAGS + `--strict-mcp-config` (no config) + ISOLATION + `--tools` + CURATOR_AUDIT_PERMISSION_FLAGS (**no guard hook**) | run-curate:63-68 |
| retro | REPO | SESSION_FLAGS + `--strict-mcp-config` + ISOLATION + `--tools RETRO_TOOLS` + RETRO_PERMISSION_FLAGS (**no guard hook**); the system prompt file is agents/RETRO.agent.md directly, not role_prompt | run-retro:146-153 |
| release review/notes | RELEASE_TREE | SESSION_FLAGS + `--setting-sources local` + `--tools RELEASE_TOOLS` + RELEASE_PERMISSION_FLAGS (guard_settings **lead**) | run-release:330-334 |
| digest | REPO (driver cwd) | `--model` [`--max-budget-usd`] `--strict-mcp-config` ISOLATION `--tools ""`, text output, **no** STREAM_FLAGS, effort, autocompact or system prompt file | run-digest:171-179 |
| bench replay | clone | `--model` [effort] `--autocompact` [budget] `--append-system-prompt-file` `--strict-mcp-config` ISOLATION `--tools IMPLEMENTER_TOOLS` `--settings <gen>` `--permission-mode auto` STREAM_FLAGS | run-bench:182-195 |
| bench judge | out dir | `--model --effort` [budget] `--strict-mcp-config` ISOLATION `--tools "" --output-format json` under `perl alarm` | run-bench:294-296 |

### 2b. Environment exported to the claude child

| var | value | who | set at |
|---|---|---|---|
| provider env (MODEL_ENV) | see the next table | every session | resolve_model_env providers:108-230, applied as `env ${MODEL_ENV[@]} ...` at providers:1160, run-bench:182,294, run-digest:171 |
| CLAUDE_CODE_DISABLE_AUTO_MEMORY | 1 | every driver that sources providers.sh | providers:492 (export) |
| CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS | 1800000 unless set | same | providers:498 |
| HARNEST_HOOKS | `<repo>/agent-settings/hooks` | same | providers:315-316 |
| HARNEST_ROOT | `<repo>` | same | providers:319-320 |
| HARNEST_SESSION_KIND, HARNEST_TARGET, HARNEST_ROLE, HARNEST_TICKET_REPO | kind, DW_TARGET, role, TICKET_REPO | run-loop run_agent only (SESSION_ENV, a local array) | run-loop:354-355 |
| HARNEST_TARGET, HARNEST_ROLE=regression, HARNEST_TICKET_REPO | | run-regression (SESSION_ENV, global) | run-regression:162 |
| HARNEST_BASE_COMMIT | origin/develop sha | exported into the driver env by set_base_commit before implementer and lead sessions, so it is **inherited by every later session in the process**, testers included | run-loop:457-463 |
| SUITE_EDITS | 1 | exported by run-loop, so every loop child inherits it | run-loop:230 |
| HARNEST_HELD_LOCK | "<pid> run-release" | exported for the whole release stage | run-release:307 |
| PYTHONPATH | the clone | bench replay | run-bench:182 |
| none | - | no `GH_*` or `GITHUB_*` variable is set anywhere; gh uses ambient auth | - |

Provider env from resolve_model_env (providers:108-230):

| provider | MODEL_ENV words | MODEL_CONTEXT_TOKENS |
|---|---|---|
| anthropic | `-u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_DEFAULT_OPUS_MODEL -u ANTHROPIC_DEFAULT_SONNET_MODEL -u ANTHROPIC_DEFAULT_HAIKU_MODEL` (these are **unsets**) | "" |
| ollama | `ANTHROPIC_BASE_URL=${OLLAMA_BASE_URL:-http://127.0.0.1:11434}`; `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_API_KEY` = `${OLLAMA_TOKEN:-ollama}`; `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL=$model`; `CLAUDE_CODE_SUBAGENT_MODEL=$model`; `CLAUDE_CODE_MAX_CONTEXT_TOKENS=$OLLAMA_CONTEXT_TOKENS`; `CLAUDE_CODE_ATTRIBUTION_HEADER=0`; `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off`; `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1`; `ENABLE_TOOL_SEARCH=true`; with OLLAMA_STRICT_SUPPRESS also `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 MAX_THINKING_TOKENS=0 DISABLE_PROMPT_CACHING=1` | OLLAMA_CONTEXT_TOKENS |
| gateway | `ANTHROPIC_BASE_URL=$GW_BASE_URL`; `[ANTHROPIC_AUTH_TOKEN, ANTHROPIC_API_KEY = $GW_TOKEN]`; `ENABLE_TOOL_SEARCH=true`; `[CLAUDE_CODE_MAX_CONTEXT_TOKENS=$GW_CONTEXT_TOKENS]` | GW_CONTEXT_TOKENS |

**SDK note:** `ClaudeAgentOptions.env` merges **over** `os.environ` (subprocess_cli.py:809-813). There is no unset, so the anthropic branch's `-u` scrub can't be expressed through `env=`. The port has to remove those keys from its own `os.environ` before connecting, or pass them as empty strings, whose effect on the CLI is unknown. The SDK also always sets `CLAUDE_CODE_ENTRYPOINT=sdk-py` (:812). Whether anything depends on the current entrypoint value is unknown.

---

## 3. STREAM/LOG CONTRACT

### 3a. What render_stream consumes

render_stream (providers:1060-1063) runs `tee -a $LOGS/<name>.jsonl | jq -Rn -r --unbuffered "$_STREAM_RENDER_JQ"`. The jq program is at providers:1013-1058.

| input event | fields read | renderer state |
|---|---|---|
| any line | `fromjson?`. A non-JSON line becomes `{type:"raw", line}`, and a jq exception becomes `render-error: <line>` | - |
| `{"type":"system","subtype":"init"}` | `.model` | - |
| `{"type":"assistant"}` | `.message.id` (a new id starts a new turn), `.message.usage.{input_tokens, cache_creation_input_tokens, cache_read_input_tokens, output_tokens}`, `.message.content[]` with `.type` text (`.text`) or tool_use (`.name`, `.input`); thinking blocks are dropped | `.id`, and `.max` = the peak ctx |
| `{"type":"user"}` | `.message.content[]`, where `.type=="tool_result"` has `.is_error` and `.content` (a string, an array of `{text}`, or anything else, measured with `tojson`) | - |
| `{"type":"rate_limit_event"}` | `.rate_limit_info.{status, rateLimitType, isUsingOverage, resetsAt}`. It emits a line only when `status != "allowed"` or overage is in use | - |
| `{"type":"result"}` | `.num_turns`, `.duration_ms`, `.total_cost_usd`, `.usage.{input_tokens, cache_read_input_tokens, cache_creation_input_tokens, output_tokens}`, `.subtype`, `.result`, `.modelUsage{<model>: {inputTokens, cacheReadInputTokens, cacheCreationInputTokens, outputTokens, costUSD}}` (printed only when there are two or more models) | uses `.max` |

The SDK equivalents (message_parser.py) are AssistantMessage, UserMessage, SystemMessage(init), ResultMessage and RateLimitEvent (`rate_limit_event` is parsed at message_parser.py:356). The SDK hands back parsed objects, not raw lines, so the `.jsonl` passthrough has to be re-serialized. See the compact-JSON note in 3d.

### 3b. Exact lines emitted

The renderer output goes to `$LOGS/<logname>.log` and to `$LAST_SESSION`. In loop.log (or `$LOOP_LOG`) each line is prefixed `[<label>] ` by `sed -u` (providers:1163-1165).

| line (exact format) | source |
|---|---|
| `=== HH:MM:SS <SESSION_HEADER or label> (<MODEL_LABEL>)[ retry] ===` | run_claude_session providers:1159. MODEL_LABEL is `provider/model`. run_agent's header is `cycle N: role:tag` (run-loop:356); curate's is `curate: <level>` (:127); release's is `release <v>: <tag>` (:330). |
| `=== HH:MM:SS regression run (<MODEL_LABEL>, level=<level><sfx>, suite=<path>, workspace=<ws>, target=<t>, head=<head>[, N cases in sessions of K]) ===` | run-regression:344,358 |
| `--- HH:MM:SS <level><sfx> session N: <ids...> ---` and `--- ... session N: final sweep ---` | run-regression:363,374 |
| `=== HH:MM:SS feature run (<label>): design ...; decompose ... ===` | run-features:129 |
| `=== HH:MM:SS bench: <label>, N case(s), jobs=J, work=W ===` (stdout only) | run-bench:327 |
| `--- HH:MM:SS cycle N tickets ---` followed by `  #NN  status  owner  title` rows | run-loop:899, status_board :834-844 |
| `model: <id>` | jq :1034 |
| `· ctx=<k> out=<n>` (a middle dot) | jq :1036; `k` formats at or above 1000 as `x.yk` |
| `<text>` (assistant text, verbatim) | jq :1038 |
| `> <tool name> <input json, truncated to 200 with …>` | jq :1039 |
| `< [ERROR ]<N> chars` | jq :1045 |
| `rate-limit: status=<s> type=<t> overage=<bool> resets=<iso> resets_epoch=<secs>` | jq :1050 |
| `usage: turns=<n> duration=<s>s cost=$<usd 2dp> ctx_peak=<k> in=<k> cache_read=<k> cache_write=<k> out=<k>` | jq :1053 |
| `result: <subtype> <result truncated 300>` (only when subtype != success) | jq :1054 |
| `  <model>: in=.. cache_read=.. cache_write=.. out=.. cost=$..` (two or more models) | jq :1056 |
| `render-error: ...` | jq :1031,1057 |
| `[<label>] session failed, continuing` | providers:1166; run-loop:332 |
| `[<label>] session ended without a result; retrying once in Ns` | providers:1170 |
| `[loop] rate limit rejected; sleeping Ns until HH:MM:SS + 60s` | providers:1118 |
| `[audit] WARNING: ...` (three kinds, plus the suite shrink) | providers:883,888,894,983 |
| `[lock] ...` (waiting, taking over, runs under) | providers:834,849,859 |
| `[loop] ...`, `[loop:deploy] <last 3 lines>`, `[implementer:#N] ...`, `[lead:#N] ...`, `[tester:task] ...`, `[curator] ...`, `[nightly] ...`, `[features] ...`, `[reviewer] ...` | run-loop passim; providers:747 |
| `[<RPFX>:<level>] script cases: P passed, F failed, E errored` / `REGRESSION-SKIP: <id> memory (...)` / `N case(s) skipped, M expectation(s) differ ...` / `session N aborted (MCP unreachable)...` / `[<RPFX>] stopping: MCP unreachable` | run-regression:318,340,368,381,387 |
| `[curate:<level>] ...` | run-curate:111,118,121 (written to `$LOGS/loop.log`) |
| `[retro] session ended without a result; window not advanced` | run-retro:155 (written to `$LOGS/loop.log`) |
| `[release <v>] ...` | run-release:86 say() (written to `$LOGS/loop.log`) |
| the commit subject (echoed) | providers:982 |

Lines that **agents** emit and drivers grep from LAST_SESSION. These are part of the contract, and live in the regression role prompt:

| pattern | where |
|---|---|
| `^REGRESSION-ABORT:` | run-regression:277 (session_aborted) |
| `^[-*\` ]*REGRESSION-SKIP:[[:space:]]*[A-Z]+-[A-Z][0-9]` (counted) | run-regression:267 |
| `^[-*\` ]*REGRESSION-DIFFERS:[[:space:]]*[A-Z]+-[A-Z][0-9]` (counted) | run-regression:268 |

### 3c. State files next to the logs

| file | written | read |
|---|---|---|
| `$LOGS/<logname>.jsonl` (raw events, append) | render_stream :1062; bench `tee $out/session.jsonl` (run-bench:195) | resolved_model providers:584; run-retro glob `*.jsonl` (:88); bench :204,309 |
| `$LOGS/<logname>.log` | run_claude_session :1163 | dashboard log viewer |
| `$LOGS/loop.log` / `loop.local.log` (LOOP_LOG) | everything tee'd | dashboard, curate, retro |
| `.last-session.<driver>`: `loop$sfx` (run-loop:233), `regression$sfx` (run-regression:168), `features` (run-features:78, **no sfx**), `curate` (run-curate:61), `retro` (run-retro:39), `release` (run-release:82) | truncated and rewritten per attempt (providers:1158) | session_died/ran/ok, sleep_if_rate_limited, session_aborted, REGRESSION-SKIP/DIFFERS counts |
| `.prompt.<role><sfx>.<kind>.md` (loop), `.prompt.regression<sfx>.<kind>.md`, `.prompt.lead.<kind>.md` (**no sfx**), `.prompt.curator.audit.md`, `.prompt.release.<kind>.md` | role_prompt | claude `--append-system-prompt-file`; tests assert on `.prompt.regression.local.whole.md` and `.prompt.implementer.local.fix.md` |
| `.driver.lock$sfx/owner` (`<pid> <name>`) | acquire_driver_lock :863 | lem_loop_running :784; run-release loop_holder :158; dashboard lock() :387 |
| `.suite-commit.lock` | commit_suite_changes :927 | same |
| `progress$sfx.tsv` (key, fingerprint, count) | note_progress :1386-1399 | same |
| `closures-seen$sfx` | mark_closures_seen run-loop:408 | pending_closures :392 |
| `.deployed.local` | scripts/deploy-local.sh:19 | deployed_head :704 |
| `.deploy$sfx.out` | deploy_target :746 | tail -3 into the log |
| `.nightly-regression$sfx` (date stamp) | run-loop:815 | :812 |
| `.curated-<level>` (mtime stamp) | run-curate:142 | :109 |
| `retro-seen.json` {at, offsets{basename: byte offset}}, `.retro-seen.next.json` | run-retro python :133, mv :157 | :45-47 |
| `stop-after-cycle$sfx` | Don (touch) | run-loop:914; run-release:479,551; dashboard :433 |
| `digest.md` | run-digest:148,198 | Don |
| `release-<v>/` (review-*.json, findings.json, notes.md, preflight-*.log, regression-*.log, closed-since-*, security-unfiled.json, advisory.md) | run-release | run-release, dashboard `release-*/*.log` |
| `release-*/gates.out` | **nothing in scope writes it** | dashboard/serve.py:406 (it must be a manual `> gates.out` redirect by Don) |
| `bench/` (`logs/bench/<logname>.jsonl`, `baseline-<prefix>.txt`) | run-bench | run-bench |

### 3d. Consumers of the log format

| consumer | what it parses | exact regex / code |
|---|---|---|
| dashboard/serve.py | driver processes | `DRIVER_RE = r"^(?:(?:\S*/)?(?:ba\|z)?sh\s+)?(\S*run-(loop\|regression\|features\|release\|curate\|retro\|digest\|bench)\.sh)(\s.*)?$"` (:36-39). **The port changes process names**, so this must learn the Python entry points. |
| dashboard | session header | `HEADER_RE = r"^=== (\d\d:\d\d:\d\d) (.*?) ===$"` (:40). A label starting `cycle ` or containing ` run (` is a run banner (:99), so **loop session headers (`cycle N: role:tag`) are treated as banners on purpose**, and loop sessions are built from `[tag]` lines (:111-115). The header text is load-bearing. |
| dashboard | tagged lines | `TAG_RE = r"^\[([^\]]+)\] (.*)$"` (:41); then `rest.startswith("usage: ")`, `"model: "`, `CTX_RE = r"· ctx=([\d.]+k?)"` (:45, **match** at the start of rest), `"> "` for the last tool, and anything but `"< "` as the last line |
| dashboard | usage | `USAGE_RE = r"turns=(\d+) duration=(\d+)s cost=\$([\d.]+) ctx_peak=([\d.]+k?)"` (:42-44) |
| dashboard | streams and locks | `STREAMS = {"lem": "loop.log", "mac": "loop.local.log"}`, `LOCKS = {"lem": ".driver.lock", "mac": ".driver.lock.local"}` (:48-49), `ps` output containing `DW_TARGET=local` (:307,382), `claude` processes `r"(^\|/)claude\s.*(-p\|--print)\b"` (:300). **An SDK child has no `-p`**, so the claude-session count becomes 0. |
| dashboard | release gates | `LOGS.glob("release-*/gates.out")`, lines starting `[release ` (:406-412) |
| run-curate.sh chunk_table (:76-97) | loop.log only (hard-coded `$LOGS/loop.log`) | run start: `index($0, "regression run (") && index($0, "level=" L ",")`; chunk: `$0 ~ "^--- [0-9:]+ " L " session [0-9]+: "`; usage: `index($0, "[regression:" L ".") == 1 && index($0, "] usage:")`, then `sub(".* cost=\\$", ...)`, `duration=`, `turns=`. It depends on the regression label shape `regression:<level>.<n\|sweep>` (run-regression:259), and a local run's tag `smoke.local` / `regression-local:` is deliberately excluded. |
| run-retro.sh evidence (:42-135, embedded Python) | loop.log only, from its byte offset | `^\[([a-z-]+):([^\]]+)\] usage: turns=(\d+) duration=(\d+)s cost=\$([0-9.]+) ctx_peak=([0-9.]+)k` (:62), which misses a ctx_peak under 1000 (no `k`) and labels without a colon (`[retro]`, `[bench]`); `^.*\[audit\] WARNING.*$` (:80); `^.*Blocked by the harness guard.*$` (:83, the guard's stderr as a tool result); `*.jsonl` tool_use/tool_result pairs, `"has been denied"` in the result (:88-109). It reads loop.log but **not loop.local.log**; its `*.jsonl` glob does include the `.local` files. |
| providers resolved_model (:582-586) | `$LOGS/<name>.jsonl` | `grep '"subtype":"init"'` then `jq -r .model`. This needs **compact JSON with no spaces**. |
| run-bench (:199-204, 309) | session.log and session.jsonl | `grep '^usage: '`, `sed 's/.* cost=\$?([0-9.]+).*/'`, `turns=`, `ctx_peak=([0-9.]+)k`; `jq -Rr 'fromjson? \| select(.type=="result") \| .subtype'`; `select(.subtype=="init") \| .model` |
| guard.py session_called_mcp (:322-327) | the transcript (Claude Code's own, via `transcript_path`, not the harness jsonl) | `'"name":"mcp__dw__' in l.replace(" ", "")`. Space-insensitive, and it reads Claude Code's transcript, not the harness jsonl. |
| session_died / session_ran / session_ok (providers:1083-1105) | LAST_SESSION (rendered) | died: no `^usage: `; ran: `^usage: ` and no `rate-limit: status=rejected`; ok: `^usage: `, no `^result: `, no `rate-limit: status=rejected` |
| sleep_if_rate_limited (:1108-1121) | LAST_SESSION | `grep 'rate-limit: status=rejected' \| tail -1`, then `sed -n 's/.*resets_epoch=\([0-9][0-9]*\).*/\1/p'`; sleeps `epoch+60-now` using BSD `date -r` |
| run-regression session_aborted / SKIP / DIFFERS | LAST_SESSION | see 3b |
| run-curate stamp | `session_died "$LAST_SESSION" \|\| touch stamp` (:142) | |
| run-retro window | `session_died` decides whether the offsets advance (:154-158) | |
| tests/fixtures/stream.jsonl → stream.expected | golden renderer test (tests/test-providers.sh:25-27) | exact equality with the 12 lines quoted below |
| tests/test-drivers.sh | loop.log and driver stdout | `grep '^=== '`, `has "[regression:smoke.2] usage:"`, `"[regression-local:smoke] usage:"`, `"target=lem, head=develop @ "`, `"level=smoke.local,"`, `"run-regression runs under"`, `"[tester:task] held: release freeze #30 Release 0.5.0"`, and others. **Every one of these is a string the Python port must reproduce byte for byte.** |
| "$0 session" detection | - | **no code checks `cost=$0`.** A session turned away by the rate limit is detected only by the `rate-limit: status=rejected` line, in session_ran, session_ok and sleep_if_rate_limited. A died session is detected only by a missing `^usage: ` line. |

The golden contract, tests/fixtures/stream.expected, in full:

    model: claude-opus-5-5
    · ctx=2.5k out=7
    Reading the issue.
    > Bash {"command":"gh issue view 5"}
    < 11 chars
    < ERROR 3 chars
    rate-limit: status=rejected type=five_hour overage=false resets=2026-09-24T03:50:00Z resets_epoch=1790221800
    rate-limit: status=rejected type=five_hour overage=false resets=1970-01-01T00:00:00Z resets_epoch=0
    render-error: {"type":"assistant","message":"not an object"}
    plain stderr line
    usage: turns=3 duration=4s cost=$0.12 ctx_peak=2.5k in=20 cache_read=4k cache_write=500 out=14
    result: error_max_budget_usd budget

Port implications:
- Keep the raw `.jsonl` as the CLI's own bytes, or re-serialize with `json.dumps(obj, separators=(",",":"))`. With default separators, `resolved_model` (while still bash), retro's grep-free parse (which is fine) and the `grep '"subtype":"init"'` all break silently.
- The SDK's ResultMessage and friends are parsed dataclasses. The renderer can be rebuilt from them, but its exact text is the dashboard/curate/retro/bench/tests contract above.

---

## 4. DW-SPECIFIC HITS

### 4a. Method

The term set, case-insensitive, is the one the brief listed:

    (\bdw\b|mcp__dw|\blem\b|diffusers|qa-|deploy\.sh|deployed_head|ruff|pytest|\bnpm\b|ui/|dkackman|\bmps\b|cuda|backend:|target:|workspace|SOURCE_DIR|PLUGIN_TREE|DW_)

- **lines**: lines matching at least one term.
- **code / comment**: whether the line starts with `#`. Python docstrings count as "code" in this column, but are tagged `prose` in the appendix.
- **occurrences**: every term occurrence, from `grep -o`.

Every code-line hit is listed with file:line in **Appendix A**. Each is tagged by ordered pattern rules (listed there), then three manual corrections were applied to the rows (also listed there). The counts below are after those corrections. Comment-line hits are **not** listed one by one: they are tagged in bulk as prose, which goes to the docs and the pack, since a comment carries no behaviour.

How the tags map onto the brief's vocabulary:

| tag here | brief's tag | destination |
|---|---|---|
| value | framework-mechanism-with-dw-value | a profile field (the mechanism stays in the framework) |
| dw-logic | dw-only logic | target code, a plug-in or a pack |
| prose | dw-only logic, as text | the prompt pack or target docs (docstrings, the autoMode environment text) |
| (none) | generic | **the rules never assign "generic"**, so the zero here reflects the rules, not the code. In practice some "value" rows are generic words that happen to match: `workspace` as a parameter name, `lem` inside a local variable name in run-release (:166-175), and the `target:` claim plumbing, which is a generic multi-server mechanism with dw's server names in it. |

| file | lines | code | comment | occurrences | code tags: value / dw-logic / prose |
|---|---|---|---|---|---|
| providers.sh | 119 | 51 | 68 | 218 | 48 / 3 / 0 |
| run-loop.sh | 82 | 55 | 27 | 145 | 54 / 1 / 0 |
| run-regression.sh | 66 | 37 | 29 | 105 | 37 / 0 / 0 |
| run-release.sh | 63 | 51 | 12 | 93 | 47 / 4 / 0 |
| agent-settings/hooks/guard.py | 67 | 64 | 3 | 93 | 24 / 18 / 22 (docstring) |
| scripts/setup-mac-loop.sh | 19 | 14 | 5 | 43 | 10 / 4 / 0 |
| scripts/sync-fixtures.sh | 21 | 11 | 10 | 38 | 3 / 8 / 0 |
| run-features.sh | 14 | 12 | 2 | 31 | 12 / 0 / 0 |
| lib/classify.jq | 18 | 12 | 6 | 30 | 6 / 6 / 0 |
| agent-settings/implementer.json | 10 | 10 | 0 | 22 | 0 / 0 / 10 |
| agent-settings/implementer.local.json | 9 | 9 | 0 | 18 | 0 / 0 / 9 |
| run-bench.sh | 15 | 9 | 6 | 18 | 1 / 8 / 0 |
| scripts/deploy-local.sh | 8 | 3 | 5 | 15 | 3 / 0 / 0 |
| dashboard/serve.py | 7 | 7 | 0 | 8 | 7 / 0 / 0 |
| scripts/file-advisory.sh | 4 | 4 | 0 | 8 | 4 / 0 / 0 |
| contract/run.py | 4 | 4 | 0 | 5 | 2 / 0 / 2 |
| bench/snapshot.py | 2 | 2 | 0 | 5 | 2 / 0 / 0 |
| run-curate.sh | 3 | 2 | 1 | 4 | 2 / 0 / 0 |
| run-retro.sh | 3 | 2 | 1 | 4 | 2 / 0 / 0 |
| run-digest.sh | 3 | 3 | 0 | 4 | 3 / 0 / 0 |
| contract/mcp_client.py | 2 | 2 | 0 | 2 | 0 / 0 / 2 |
| lib/release.sh | 0 | 0 | 0 | 0 | - |
| measure-base-ctx.sh | 0 | 0 | 0 | 0 | - |

### 4b. Comparison with R13's 2026-09-24 counts

R13 doesn't record its term list, so its numbers can't be reproduced exactly. This is the same term set run against the last commit before 2026-09-25, ff2c65f:

| file | R13 (09-24) | ff2c65f lines | ff2c65f occurrences | now lines | now occurrences | size then → now |
|---|---|---|---|---|---|---|
| run-loop.sh | 107 | 67 | 112 | 82 | 145 | 818 → 929 |
| providers.sh | 46 | 38 | 66 | 119 | 218 | 1147 → 1454 |
| guard.py | 22 | 14 | 17 | 67 | 93 | 297 → 500 |
| run-features.sh | 4-7 | 13 | - | 14 | 31 | |
| curate / retro / digest | 4-7 | 3 / 3 / 3 | - | 3 / 3 / 3 | 4 / 4 / 4 | |
| classify.jq | 4-7 | 0 | - | 18 | 30 | |

R13's run-loop figure of 107 is close to the ff2c65f occurrence count of 112, so it probably counted occurrences. On any method, **providers.sh has roughly tripled (66 → 218) and guard.py has grown about fivefold (17 → 93) since R13 was written.** Nearly all of that growth is harnest#15, the local/mps server:
- `resolve_target`, `deploy_cmd` and `claim_issue` in providers.sh;
- the target rules in guard.py;
- the target post-filter in classify.jq.

That work built a second **server** without a profile, so the servers table below is already the largest profile field.

### 4c. The profile slice that already exists in bash

These functions in providers.sh, plus a few in run-loop.sh, are already an implicit two-row servers table. Its full shape:

| field | lem | local | where it lives today |
|---|---|---|---|
| name (DW_TARGET) | `lem` (the default) | `local` | providers:596, validated in resolve_target :617-642 |
| suffix for logs, state and locks (TARGET_SUFFIX) | "" | `.local` | providers:620,624 |
| clone suffix (tsfx) | "" | `-mps` (named after the **backend**, not the target) | run-loop:79, run-features:41 (**not** run-regression:76-77, run-release, run-bench) |
| loop log (LOOP_LOG) | `$LOGS/loop.log` | `$LOGS/loop.local.log` | providers:621,625; dashboard STREAMS :48 (key "mac") |
| lock | `$LOGS/.driver.lock` | `$LOGS/.driver.lock.local` | providers:832; dashboard LOCKS :49; run-release loop_holder :158 and lem_loop_running providers:784 **hard-code the lem name** |
| MCP URL default (DW_URL) | `http://lem:8765/mcp` | `http://localhost:8765/mcp`, which must be loopback or this host's name (:633-637) | providers:622,626; contract/run.py:151 |
| MCP token | `DW_TOKEN` (xyz) | same | run-loop:191, etc. |
| backend label it serves | `cuda` (and shared) | `mps` (and shared) | `serves()` in lib/classify.jq:65 **hard-codes the lem↔cuda and local↔mps pairs** |
| verification label | none | `verified-on:mps` is required with status:verified | guard.py:421-426 (hard-coded `mps`); label created at run-loop:214 |
| health check | none (no preflight) | `GET ${DW_URL%/mcp}/api/health` with Bearer; JSON `{status:"ok", device, hostname}`; hostname must equal this host (short, lowercase) | target_health :667-672, target_preflight :681-687 |
| deploy command | `ssh -o ConnectTimeout=8 -o BatchMode=yes lem '~/diffusers-workflow/scripts/deploy.sh develop'` | `DW_DIR=$DW_LOCAL_DIR DW_WORKSPACE=$DW_LOCAL_WORKSPACE DW_HOST=127.0.0.1 DW_PORT=<port> DEPLOY_RECORD=$LOGS/.deployed.local $HARNEST_ROOT/scripts/deploy-local.sh`, which runs `$DW_DIR/scripts/deploy.sh develop` and records the head | deploy_cmd :734-743; deploy_target :744-749 |
| "what's deployed" command | `ssh ... lem 'cd ~/diffusers-workflow && echo "$(git branch --show-current) @ $(git rev-parse --short HEAD)"'`; "unknown" on failure | `head -1 $LOGS/.deployed.local`, or "unknown" | deployed_head :700-710 |
| head format contract | `<branch> @ <short sha>`, compared to origin/develop as a **prefix** | same | check_target_on_develop run-loop:432-450; run-release lem_at :165-176 |
| display name | `lem` | `the local server (<device> on <host>)` | server_name :752-754 |
| serving clone | on lem: `~/diffusers-workflow` | DW_LOCAL_DIR `~/src/dkackman/dw-mps-serve` | :598, :708 |
| server workspace | (lem's own) | DW_LOCAL_WORKSPACE `~/dw-mps-workspace` | :599 |
| plugin dir for consumers | `$PLUGIN_TREE/plugins/dw` (the refreshed worktree) | loop: `$PLUGIN_TREE` (the -mps worktree); regression: `$DW_LOCAL_DIR/plugins/dw` | run-loop:196; run-regression:169-178 |
| implementer settings file | agent-settings/implementer.json | agent-settings/implementer.local.json | run-loop:302 (`implementer$TARGET_SUFFIX.json`) |
| prompt addendum | none | `agents/<role>/target.md`, with `{{TARGET}} {{SERVER}} {{URL}} {{DEPLOY}} {{SERVER_DIR}}` substituted | target_note :718-724 |
| claim label | `target:lem` | `target:local` | claim_issue :766-778; guard claim_rule :367-376 |
| tie-break holder | lem wins | - | classify.jq `holder` :64 |
| queues it may run | all | not tester:spec, lead:build or lead:closeout; unclaimed hand-offs go to lem | classify.jq:150-161 |
| standing task | runs | never | run-loop:715-719 |
| shared passes (features, reviewer, curator) | always | only while lem's loop is down (SHARED_PASSES) | run-loop:827-830 |
| suite commit paths | `regression-suite-*.md regression-perf` | `regression-perf/local` (plus the suite files if SUITE_EDITS and lem's loop is down) | suite_commit_paths :947-959 |
| perf dir | `regression-perf/` | `regression-perf/local/` | run-regression:158; guard target_file_rule :379-392 |
| skip list | none | TARGET_SKIP_CASES | run-regression:104,335-342 |
| `all` level set | smoke, complete, model-specific, security | smoke, complete, security | run-regression:153 |
| tester budget default | 5 | 8 | run-loop:170 |
| guard rules | - | no ssh/scp/rsync or deploy scripts for the implementer; consumer filing rules; no comment on target:lem | guard.py:410-448 |
| release support | yes | refused | run-release:78 |
| the guard's view of the server | HARNEST_TARGET=lem | HARNEST_TARGET=local | SESSION_ENV run-loop:354, run-regression:162 |

### 4d. Proposed PROFILE fields, grouped from the hits

Each field lists its current value and where the value lives. Items marked **logic** are dw-only code, not values: they need a hook, callable or pack entry, not just a string.

| profile field | dw value today | sources |
|---|---|---|
| `ticket_repo` | dkackman/diffusers-workflow | 7 drivers (1b), file-advisory:20, dashboard:52, bench/snapshot:12 |
| `harness_repo` | dkackman/harnest | 5 drivers, dashboard:53, guard.py:357,429 (a hard-coded fallback) |
| `ticket_owner` | dkackman | loop:90, features:45, digest:23, release:43. It is also in the park comment text (providers:1213) and in marker authorship (:1282). |
| `product_name` / advisory package | "diffusers-workflow"; ADVISORY_PACKAGE; the prompt text "a detached worktree of the diffusers-workflow source" | run-features:98, run-release:331, file-advisory:21 |
| `mcp_server.name` | `dw`. It drives `mcp__dw__*` in CONSUMER/LEAD_DESIGN/REVIEWER/CURATOR_REVIEW allowlists (providers:340,371-376,399-401,442-443), the `--disallowedTools` pair (:346), guard `session_called_mcp` `"name":"mcp__dw__"` (guard:325), the `{"mcpServers":{"dw":...}}` key (loop:276, reg:236, features:82), and `plugins/dw` | one field; the tool **lists** are a per-role profile field |
| `mcp_server.read_only_tools` per role | the lead-design, reviewer and curator-review lists | providers:371-376, 399-401, 442-443 |
| `mcp_server.deny_tools` | delete_model, update_diffusers | providers:346 |
| `mcp_server.config` | http transport, URL per server, Bearer DW_TOKEN | loop:276, reg:236, features:82 |
| `mcp_server.health` | `/api/health` → `{status, device, hostname}` | providers:667-672 |
| `source_clone` | `~/src/dkackman/dw-agent{,-mps}`; clone URL and install (`bash ./install.sh`) | 1b SOURCE_DIR; run-loop:198 error text; setup-mac-loop |
| `plugin_tree` | `~/src/dkackman/dw-agent-plugin{,-mps}`, subdir `plugins/dw`; ref `origin/develop` | loop:86,196; reg:77,170 |
| `lead_tree`, `release_tree` | `~/src/dkackman/dw-agent-lead{,-mps}`, `~/src/dkackman/dw-agent-release` | loop:88, features:43, release:41 |
| `integration_branch` / `release_branch` | develop / master (hard-coded throughout: refresh_plugin_tree, check_target_on_develop, set_base_commit, guard git_push_problem master, release) | providers:801,807,809; loop:434,458-459; guard:235; release passim |
| `servers[]` | 4c | 4c |
| `deploy_cmd`, `head_cmd`, `health` per server | 4c | 4c |
| `handoff_gate` (**logic**) | a clean tree; `venv/bin/python -m ruff check` and `ruff format --check` on changed `*.py` under `dw/ dw_mcp/ tests/`; `npm run check/lint/test` in `ui/` when `ui/` changed and `ui/node_modules` exists; `venv/bin/python -m pytest -q -rfE -p no:cacheprovider` with `PYTHONPATH=root`, compared to a base worktree | guard.py:240-319 |
| `bench.score` (**logic**) | `venv/bin/python -m pytest -q -rfE -p no:cacheprovider` under `PYTHONPATH`; a venv symlink from SOURCE_DIR; `tests/` as the hidden-test prefix; the judge prompt mentions "MCP interface" | run-bench:139-154, 219, 240-250, 254-284; bench/snapshot.py:50 `tests/` |
| `release.preflight` (**logic**) | `scripts/preflight.sh` in the release tree, with the venv and `ui/node_modules` symlinked, port 8971 killed first, and ruff-dirty detection | run-release:241-261 |
| `release.ci_workflows` | ci.yml, codeql.yml | run-release:221 |
| `release.cut_script` | `scripts/release.sh <v> --next <n>` in a master worktree | run-release:534 |
| `release.notes_file` | docs/RELEASING.md, with `## Unreleased` / `### <v>` | run-release:431,476,495-497; lib/release.sh:196-230 |
| `release.review_areas` | security engine mcp-and-docs templates-ui-packaging | run-release:337 |
| `release.regression_levels` | security complete | run-release:55 |
| `suite.levels` (**pack**) | smoke/complete/model-specific/security → file `regression-suite-<level>.md`, workspace `regression-<level>`, ID prefix S/C/M/SE, `complete` implies smoke, `all` = four (three off lem) | run-regression:114-127,210-228; run-curate:101-103; curate budgets :45-48 |
| `suite.case_id_regex` | `[A-Z]+-[A-Z][0-9]+` (`S-F001`, `SE-P001`) | run-regression:288,356,267-268 |
| `suite.target_skip_cases` | S-F079 C-F005 C-F007 C-F023 C-F047 | run-regression:104 |
| `contract.runner` | contract/run.py + contract/cases/<ID>.json, called with --url --token | run-regression:287-291,317 |
| `labels` | `backend:{shared,cuda,mps}`, `target:{lem,local}`, `verified-on:mps` (created at startup) | run-loop:214-216; run-regression:156-157 |
| `role_prompts` (**pack**) | agents/<role>/*.md, target.md, standing-task.md, RETRO.agent.md | providers:1422-1454; target_note; run-retro:146 |
| `implementer.auto_mode_environment` (**pack prose**) | agent-settings/implementer{,.local}.json autoMode.environment (it names lem, the repo, the xyz token, pip/uv, Hugging Face) | implementer.json:2-19 |
| `fixtures.sync` (dw-only script) | rsync `lem:diffusers-workspace/common/assets` qa-cast/cast/uploads/reference_sheet.jpg | scripts/sync-fixtures.sh |
| `standing_task` (**pack**) | lem-only; qa-bible.md | run-loop:713-719 |

### 4e. dw-only logic inside supposedly generic code (the short list)

- **guard.py handoff_gate** (240-319): ruff, pytest, npm, the paths `dw/`, `dw_mcp/`, `tests/` and `ui/`, and `venv/bin/python`. This is the largest dw-logic block in generic code.
- **guard.py target rules**: `verified-on:mps` and `backend:mps|shared` are hard-coded (421-448).
- **classify.jq `serves()`** (:65) and `holder` (:64): the lem↔cuda and local↔mps mapping, and lem as the tie winner and legacy default (:88,154,160-161).
- **run-regression.sh**: the level table, workspace derivation, case-ID regexes, the `### ` heading contract, `runner: script`, TARGET_SKIP_CASES, and "model-specific is never run under all off lem" (:153).
- **run-bench.sh**: pytest scoring, the venv symlink, and the `tests/` convention.
- **run-release.sh**: preflight.sh, ci.yml/codeql.yml, port 8971, docs/RELEASING.md, scripts/release.sh, and the pip package. The whole driver is dw's release process. It would be a target plug-in, not framework.
- **providers.sh**: `deployed_head`'s ssh one-liner, `deploy_cmd`, and `runtime_note`'s example text are generic, but `target_note` substitutes dw paths.
- **run-loop.sh**: the standing task is lem-only by name (:717), the label bootstrap list (:214), and error text that names `install.sh` (:198).
- **dashboard/serve.py**: STREAMS/LOCKS keyed "lem"/"mac", and the `DW_TARGET=local` process sniffing (:307,382).

---

## 5. FUNCTION MAP

Proposed package layout: `harness/` with the following modules:
- `profile.py`: target profile, servers table, repos, paths.
- `providers.py`: model/provider env and validation.
- `session.py`: builds claude/SDK options and runs one session.
- `stream.py`: renderer and jsonl.
- `outcome.py`: died/ran/ok and rate limit.
- `lock.py`.
- `gh.py`: the gh subprocess seam.
- `git.py`: the git subprocess seam.
- `board.py`: snapshot, classify, queues.
- `ledger.py`: no-progress ledger, closures ledger, handoff count.
- `audit.py`.
- `deploy.py`: servers, deploy, head, health.
- `prompts.py`: role_prompt, runtime_note, target_note, issue_context.
- `suite.py`: suite commits, levels, case IDs.
- `release.py`.
- `drivers/{loop,regression,features,curate,retro,digest,bench,release}.py`.
- `guard/` (guard.py, kept as a command hook).

In the "seams" column, a subprocess to an external tool is a place the tests fake: **gh** (fake-gh.py), **ssh**, **curl**, **claude** (bash stubs on PATH), and **git** (a real git on throwaway repos). **jq** is local and deterministic, so it is not a seam, but any call to it must be ported or kept.

### providers.sh

| function | line | what it does | dest | seams |
|---|---|---|---|---|
| is_anthropic_model | 86 | structural check for a Claude model name | providers.py | - |
| resolve_model_env | 108 | sets MODEL_ENV (set/unset words), MODEL_LABEL and MODEL_CONTEXT_TOKENS per provider; validates | providers.py | - |
| validate_fallback_model | 238 | fallback suits the provider | providers.py | - |
| fallback_model_flags | 268 | `--fallback-model X` | providers.py/session.py | - |
| guard_settings | 329 | inline `--settings` JSON installing guard.py for a role | session.py (roles) | jq |
| effort_flags | 516 | `--effort` for anthropic only; validates | providers.py | - |
| co_author_for | 526 | commit trailer identity | suite.py | - |
| runtime_note | 548 | the per-role "Runtime:" prompt paragraph | prompts.py | - |
| resolved_model | 582 | model id from the last init event in `<log>.jsonl` | stream.py | grep, jq |
| target_default | 606 | lem-or-other default. **No caller outside tests** (test-providers:155) | profile.py (or drop) | - |
| resolve_target | 617 | validates DW_TARGET; sets TARGET_SUFFIX, LOOP_LOG, DW_URL | profile.py | **git** (rev-parse DW_LOCAL_DIR), hostname |
| url_host / short_host | 648/657 | host parsing | profile.py | tr |
| target_health | 667 | GET /api/health | deploy.py | **curl** |
| target_preflight | 681 | health, and host == this machine | deploy.py | curl, hostname |
| deployed_head | 700 | what the server runs | deploy.py | **ssh** (lem) / file (local) |
| target_note | 718 | fills agents/<role>/target.md | prompts.py | sed |
| deploy_cmd | 734 | deploy command string | deploy.py (profile value) | - |
| deploy_target | 744 | runs the deploy and logs the last 3 lines | deploy.py | **bash -c → ssh / deploy.sh** |
| server_name | 752 | display name | profile.py | - |
| claim_issue | 766 | target:<t> claim with a read-back tie-break | board.py | **gh** issue view/edit |
| lem_loop_running | 782 | lem's lock holder is a live run-loop | lock.py | kill -0 |
| refresh_plugin_tree | 799 | detached worktree at origin/develop | git.py | **git** fetch/worktree/checkout |
| acquire_driver_lock | 831 | mkdir lock, stale takeover by rename, HARNEST_HELD_LOCK passthrough, EXIT trap | lock.py | find -mmin (BSD), kill -0 |
| audit_issue | 875 | [audit] warnings: owner count, completed-close role, stranded | audit.py | **gh** issue view; classify |
| commit_suite_changes | 911 | mkdir-locked commit of suite/perf paths | suite.py | **git**, find |
| suite_commit_paths | 947 | which paths per target | suite.py | - |
| commit_suite_changes_locked | 961 | add, detect removed lines (awk), commit, audit warning | suite.py | **git** |
| render_stream | 1060 | tee jsonl, jq render | stream.py | tee, jq |
| session_died / session_ran / session_ok | 1083/1092/1101 | outcome from the rendered log | outcome.py | grep |
| sleep_if_rate_limited | 1108 | sleep until resets_epoch + 60 | outcome.py (ratelimit) | date -r (BSD), sleep |
| session_flags | 1130 | model, fallback, effort, autocompact, budget | session.py | - |
| run_claude_session | 1153 | one session: env, header, render, tee to 3 sinks, rate-limit sleep, retry once if died | session.py | **claude** |
| park_external_issues | 1189 | parks non-owner filings | board.py | **gh** list/edit/comment |
| issue_context | 1232 | issue text for a prompt; withholds other logins | prompts.py | **gh** issue view; jq |
| plan_text | 1257 | the `<!-- harnest:plan` comment | board.py | **gh** |
| issue_snapshot | 1275 | the classify.jq input: 4 gh calls, markers | board.py | **gh** ×4; jq |
| classify_issues | 1296 | runs classify.jq → TSV | board.py (classify.py) | jq -f lib/classify.jq |
| release_freeze | 1308 | "#n title" of the release freeze | board.py | - |
| only_issues_filter | 1318 | ONLY_ISSUES by number or parent | board.py | awk |
| queue_issues / still_ready | 1329/1341 | one queue's rows; re-check before a session | board.py | (classify) |
| handoff_count | 1356 | fixed-pending-verify labels since the last reopen | ledger.py | **gh api** events |
| issue_fingerprint | 1368 | state, labels and marker heads | ledger.py | **gh** |
| note_progress | 1385 | no-progress ledger; parks with Don | ledger.py | **gh** edit/comment; file |
| role_prompt | 1423 | core plus kind fragments → file | prompts.py | cat |
| (globals) CONSUMER/LEAD_DESIGN/REVIEWER/RELEASE/CURATOR_*/RETRO_*_PERMISSION_FLAGS, *_TOOLS, ISOLATION_FLAGS, STREAM_FLAGS, KNOWN_PROVIDERS | 336-505, 1010 | role option tables | session.py `ROLES` table plus profile tool lists | - |

### run-loop.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| (startup) | 72-304 | knobs, preflight, label bootstrap, lock, plugin tree, validation, MCP/TESTER/IMPLEMENTER flag sets | drivers/loop.py + profile | gh label create, gh auth status, command -v |
| ts | 267 | HH:MM:SS | util | date |
| run_agent | 319 | role prompt, target note, SESSION_ENV, fingerprint, run, audit, ledger | drivers/loop.py (or session.py) | via run_claude_session |
| pending_closures | 391 | closed owner:tester wontfix/duplicate not yet seen, target-filtered | ledger.py | **gh** issue list ×2 |
| mark_closures_seen | 407 | appends to closures-seen | ledger.py | file |
| check_target_on_develop | 432 | head vs origin/develop prefix; redeploy | deploy.py | **git ls-remote**, deploy_target |
| set_base_commit | 457 | exports HARNEST_BASE_COMMIT | git.py/session env | **git** fetch/rev-parse |
| implementer_pass | 466 | claim, triage (2 or more), per-issue fix with escalate/park | drivers/loop.py | gh edit/comment (park) |
| features_pass | 538 | runs run-features.sh as a subprocess | drivers/loop.py → drivers/features.py (call directly) | subprocess |
| lead_pass | 549 | stage builds (with a cap), close-outs, park on bounces | drivers/loop.py | gh edit/comment |
| tester_pass | 619 | spec, verify, handoff, answer, task or closures | drivers/loop.py | **gh** issue view subIssues (:636) |
| reviewer_pass | 750 | docs review in the plugin tree | drivers/loop.py | git rev-parse |
| curator_pass | 774 | suite requests on the harness repo, then commit | drivers/loop.py | **gh** issue list |
| nightly_regression_pass | 807 | daily run-regression under the held lock | drivers/loop.py | subprocess |
| shared_passes_here | 827 | SHARED_PASSES logic | profile.py | - |
| status_board | 834 | board text; also the "changed" detector | board.py | **gh** issue list |
| step | 852 | log-and-continue wrapper | drivers/loop.py | - |
| main | 861 | the cycle loop, stop file, advisory count, idle sleep | drivers/loop.py | **gh api** security-advisories |

### run-regression.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| (startup) | 73-242 | level → RUN_SPECS, target preflight, label, SESSION_ENV, lock, plugin, chunk size, flags | drivers/regression.py + suite.py | gh label create |
| default_suite_file | 210 | level → file | suite.py (profile.suite.levels) | - |
| workspace_for_suite_file | 222 | file → workspace | suite.py (pack) | - |
| run_session | 250 | role prompt, target note, run, count SKIP/DIFFERS | drivers/regression.py | claude |
| session_aborted | 276 | REGRESSION-ABORT | outcome.py | grep |
| script_cases | 287 | `runner: script` IDs with JSON | suite.py | awk |
| run_level | 293 | script cases (contract/run.py), head, chunking, sweep, commit, abort | drivers/regression.py | **python3 contract/run.py** (MCP), deployed_head (ssh) |
| main | 395 | unknown-origin commit, then levels | drivers/regression.py | git |

### run-features.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| run_session | 90 | a design/decompose session with plan text, audit and ledger | drivers/features.py | claude, gh |
| main | 115 | park, refresh LEAD_TREE, queue reads, sessions | drivers/features.py | gh, git |

### run-curate.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| chunk_table | 76 | per-chunk cost table from loop.log | drivers/curate.py (reads the stream contract) | awk |
| run_level | 99 | stamp, open-request check, audit session | drivers/curate.py | **gh** issue list |
| main | 152 | levels loop (after an idempotent label create at :146-147) | drivers/curate.py | gh label create |

### run-retro.sh

| piece | line | what | dest | seams |
|---|---|---|---|---|
| embedded Python evidence builder (new_text, gh) | 42-135 | byte-offset windows, usage table, audit/guard/denial counts, hand-off flow, bench summary | drivers/retro.py (already Python: lift it out) | **gh** issue list and api events; **run-bench.sh --summary** subprocess |
| session and window advance | 146-158 | one session; mv next→seen unless it died | drivers/retro.py | claude |

### run-digest.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| parked_since | 45 | when owner:don was last added | board.py | **gh api** events; date |
| curator_section | 54 | curator rulings | drivers/digest.py | **gh**; `date -v` (BSD) or `-d` |
| stranded_section | 75 | from the board | drivers/digest.py | - |
| harness_section | 84 | harness proposals | drivers/digest.py | **gh** |
| commands | 95 | Don's approve/reject gh commands per state | drivers/digest.py | **gh** view |
| advisories_section | 128 | draft advisories | drivers/digest.py | **gh api** |
| days_of | 153 | lookup | - | - |
| (main body) | 136-202 | context build, **direct claude -p (text output)**, table, post | drivers/digest.py | **claude**, gh comment |

### run-bench.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| summary | 68 | jq aggregation of results.jsonl | drivers/bench.py | jq |
| (prompt/settings build) | 91-134 | prompt at a rev; settings with deny rules | drivers/bench.py | git show |
| pytest_failures | 139 | failing test ids | bench scoring (**profile.bench.score**) | venv python pytest |
| make_clone | 146 | history-limited clone with a venv symlink | drivers/bench.py | git |
| cap | 156 | head -c | - | - |
| run_case | 158 | replay, score, judge (perl alarm, retries), result row | drivers/bench.py | **claude** ×2, git, pytest, perl |
| (main) | 321-336 | --one, xargs -P parallelism | drivers/bench.py | xargs |

### run-release.sh and lib/release.sh

| function | line | what | dest | seams |
|---|---|---|---|---|
| usage/ts/say/die | 59,85-87 | | drivers/release.py | - |
| release_issue / need_release_issue | 90/95 | find the release issue (with retry) | release.py | **gh** |
| develop_sha | 102 | origin/develop | git.py | **git** fetch |
| gate_results / record | 106/110 | read and write marker comments | release.py | **gh** view/comment |
| carry_forward | 119 | record `carried` if allowed | release.py | **gh**, **git** log/diff-tree/merge-base |
| tree_at | 143 | RELEASE_TREE at a sha | git.py | **git** worktree |
| loop_holder | 156 | lem lock holder, if alive and not this process | lock.py | kill -0 |
| lem_at | 165 | head == sha, else deploy if no loop is running | deploy.py | deployed_head, deploy_target |
| stage_freeze / check / gates / review / notes / accept / status / cut | 178-555 | the stages | drivers/release.py | **gh** (issue, pr, run, workflow, release, api), **git**, **scripts/file-advisory.sh**, **scripts/preflight.sh**, **scripts/release.sh**, lsof, kill, **run-regression.sh** |
| gate_ci / gate_preflight / gate_regression | 219/241/263 | the gates | release.py (dw plug-in) | gh run/workflow, preflight.sh, run-regression.sh |
| run_release_session | 325 | a review/notes session | drivers/release.py | claude |
| main | 559 | stage dispatch | drivers/release.py | - |
| lib/release.sh: release_marker, release_gate_results, release_gate_ok, release_waive_marker, release_waivers, release_drop_waived, release_carry_ok, release_missing_gates, release_board_problems, release_open_with_commits, release_closing_comments, release_findings_valid, release_insert_notes (already Python inside), release_notes_section | 30-230 | pure functions over stdin (jq, awk, sed) | release.py (pure; port test-release.sh's cases as pytest) | jq, awk, python3 |

### Python files

| file / function | what | dest |
|---|---|---|
| guard.py main and helpers (segments, flag_values, owner_rule, closes_completed, adds_verified, still_parked, label_lookup, git_push_problem, handoff_gate, session_called_mcp, carries_release_marker, suite_request, other_target, claim_rule, target_file_rule) | PreToolUse command hook | keep as a standalone hook (`harness/guard/`), since the SDK hooks-as-callbacks alternative loses the hook's isolation from the driver process. Move `handoff_gate` behind `profile.handoff_gate`. Seams: **gh** issue view (still_parked, label_lookup), **git**, venv ruff/pytest, npm. |
| dashboard/serve.py | reads logs, locks and processes; gh Attention | stays a separate tool; its regexes are a consumer of the stream contract. Seams: gh, ps, lsof. |
| contract/mcp_client.py, run.py | stdlib MCP client and case runner | already Python: `harness/contract/`; the URL and token defaults go to the profile |
| bench/snapshot.py | freezes bench cases | drivers/bench.py helper; seams: gh (issue view, api events, graphql), git |

---

## 6. TEST SEAMS

### 6a. How each external tool is faked

| tool | fake | mechanism | what it reads | what it produces |
|---|---|---|---|---|
| `claude` | bash stub written to `$T/bin/claude` (tests/test-drivers.sh:26-33), found **by name on PATH** (tests/lib.sh:18 puts `$T/bin` first) | argv only; **stdin is never read** (drivers pass `< /dev/null`) | `$*`, truncated to 200 chars, is logged to `$FAKE_CLAUDE_LOG` ("claude -p <prompt>..."). If `FAKE_CLAUDE_DO` is set it is `eval`'d first; scripts match on `case "$*" in *"fix session"*`, `*"VERIFY session"*`, `*"DOCS REVIEW session"*`, `*"BUILD session"*`, and read `$2` as the prompt (the positional after `-p`: test-drivers:258,389,393) and `"$@"` for the args (`--plugin-dir\n<path>` adjacency asserted at :279; `agent-settings/implementer.local.json` at :342); `HARNEST_TARGET` and `HARNEST_ROLE` come from its env (:258,:335) | exactly two stream-json lines: `{"type":"system","subtype":"init","model":"claude-fake"}` and `{"type":"result","subtype":"success","num_turns":2,"duration_ms":1000,"total_cost_usd":0.01,"usage":{...}}`. There are no assistant, user or rate_limit events. |
| `gh` | `tests/fake-gh.py` symlinked as `$T/bin/gh` (test-drivers:22); `stub_gh <bash body>` in tests/lib.sh:29-32 for unit tests | argv | `FAKE_GH_BOARD` JSON `{"owner/repo":[issues], "owner/repo#advisories":[...]}`; supports issue list/view/edit/comment/create/close, `api` for security-advisories (GET/POST/PATCH), any other `api` → `[]`; `--json` projection and `--jq` through real jq; `FAKE_GH_FAIL=1` makes every call but auth fail; `FAKE_GH_ON_EDIT_<n>` injects another loop's claim | writes the board back. **Unsupported subcommands exit 1** (`label create` fails silently in the drivers; `pr`, `run`, `workflow` and `release` are unfaked, so release ci/preflight/cut are untested). |
| `ssh` | `$T/bin/ssh` echoing `develop @ <sha>` (test-drivers:23), later a variant that simulates deploy.sh (:125-126) | argv | - | deployed_head's output |
| `curl` | `$T/bin/curl` echoing health JSON, or `exit 7` (test-drivers:227,290; test-providers:111-121) | argv | - | `/api/health` JSON |
| `rsync` | $T/bin/rsync recording args (test-sync.sh) | argv | - | - |
| `deploy.sh` (local) | `$T/serve/scripts/deploy.sh` stub (test-drivers:292-293) | argv | - | exit code; `$T/deploys` log |
| `git` | **real git** on throwaway bare origin, clones, and a copy of the harness as its own repo (test-drivers:9-20) | - | - | - |
| `jq`, `python3`, `awk`, `date`, `hostname` | real | - | - | - |

### 6b. Which tests survive a Python port invoked the same way

| test file | what it drives | survives the port? |
|---|---|---|
| tests/test-classify.sh | `jq -f lib/classify.jq` over tests/classify-cases.json | **yes** while classify.jq stays. If it is ported to Python, the JSON fixtures carry over unchanged as parametrized cases. |
| tests/test-guard.sh | `python3 guard.py <role>` with hook JSON on stdin, table-driven; stub_gh for the owner:don lookup | **yes** while guard stays a command hook. It would be broken by moving the guard into SDK callbacks. |
| tests/test-drivers.sh | the **real drivers by path** (`./run-loop.sh`, `./run-features.sh`, `./run-regression.sh`, `./run-curate.sh`, `./run-retro.sh`, `./run-release.sh`) against fake gh/ssh/claude/curl | **conditionally.** It survives if (a) the Python drivers keep these entry-point names, or thin shims do; (b) they still shell out to `gh` (so fake-gh.py applies) and to `ssh`/`curl`; (c) every asserted log string (3d) is identical; (d) state file names are identical (`.prompt.implementer.local.fix.md`, `.deployed.local`, `.driver.lock*/owner`, `stop-after-cycle`, `.nightly-regression`); and (e) **the claude fake still works**, which the SDK breaks: see 6c. |
| tests/test-providers.sh | `. providers.sh` and calls bash functions directly (session_died, render_stream, resolve_model_env, only_issues_filter, note_progress, handoff_count, park_external_issues, acquire_driver_lock, resolve_target, target_note, deploy_cmd, claim_issue, lem_loop_running, commit_suite_changes) | **no: bash-internal.** Its fixtures port directly to pytest: canned rendered logs (:11-14), `tests/fixtures/stream.jsonl` → `stream.expected` (the golden renderer test), the gh stub scripts, the lock scenarios, and the claim tie-break read-back sequences. |
| tests/test-release.sh | `. lib/release.sh` pure functions | **no: bash-internal**, but pure stdin→stdout. The cases port one-to-one to pytest. |
| tests/test-lint.sh | bash -n, shellcheck on run-*.sh, Python ast.parse, the **README knob check** by grep of `${X:-` | **no:** the knob check becomes vacuous (it finds no reads and passes). The Python-parse loop would still run. |
| tests/test-setup.sh / test-sync.sh | scripts/setup-mac-loop.sh and sync-fixtures.sh by path | yes, as long as the scripts stay bash. setup-mac-loop **sources providers.sh** (:25), so porting providers.sh breaks it. |

### 6c. The claude seam under the Agent SDK (checked in claude-agent-sdk 0.2.152)

- **CLI discovery: the first test risk.** `_find_cli` (subprocess_cli.py:247-260) prefers the **bundled** `claude_agent_sdk/_bundled/claude`, which exists in the installed package, over `shutil.which("claude")`. So the PATH stub is **bypassed** unless the port sets `ClaudeAgentOptions(cli_path=...)` explicitly.
  - This is worse than a broken test. test-drivers.sh doesn't set `DW_URL`, so `resolve_target` fills in `http://lem:8765/mcp` (providers:622).
  - A port that leaves `cli_path` unset would have `tests/run.sh`, documented as offline, launch the **real, authenticated bundled claude**: billed sessions, with live MCP calls to lem, and gh calls that still go to the fake board.
  - The port must resolve `cli_path` from PATH (or a `HARNEST_CLAUDE` override) in every session, and a test should assert that the stub was the process that ran.
- **Prompt transport.** The command is `claude --output-format stream-json --verbose ... --input-format stream-json` (:566, :783). There is **no `-p`**, and the prompt goes over **stdin** after an `initialize` control request (`_internal/query.py:231-281`, 60 s timeout). The current stub ignores stdin, never answers `initialize`, and its `case "$*"` matches on prompt text that is no longer in argv. **Every `FAKE_CLAUDE_DO` scenario in test-drivers.sh breaks.** A new fake is needed, one that:
  - reads stream-json from stdin;
  - answers the control request;
  - exposes the prompt to the scenario scripts, for example as `$FAKE_PROMPT_TEXT`;
  - emits init and result.
- **System prompt.** The SDK has no `--append-system-prompt-file` option. `system_prompt=None` sends `--system-prompt ""`. The tests that read `.prompt.*.md` files keep working only if the port still writes them.
- **Environment.** The SDK merges `options.env` over `os.environ` and adds `CLAUDE_CODE_ENTRYPOINT=sdk-py`. The stub's reads of `HARNEST_TARGET` and `HARNEST_ROLE` still work if the port puts SESSION_ENV into `options.env`.
- **Option to defer.** An alternative that keeps every driver test: port the drivers to Python but keep **invoking the `claude` CLI directly** (subprocess, `-p`, stream-json, the same argv) in the first phase. Adopt the SDK transport later, behind `session.py`. That keeps the fake and the whole argv contract, including `--append-system-prompt-file`.

---

## Surprises and risks

1. **HARNEST_HARNESS_REPO is never set.** guard.py:357,429 reads it, and nothing exports it, so the guard always compares against the literal `dkackman/harnest`. The drivers' `HARNESS_REPO` (tests use `h/r`) never reaches the guard. A second target, or a renamed harness repo, would have its suite-request exception silently refused.
2. **HARNEST_BASE_COMMIT and SUITE_EDITS leak to every later session.** set_base_commit exports into the driver's own environment (run-loop:460), so testers and reviewers later in the cycle inherit a stale base commit. It is harmless today (only the implementer's guard reads it), but the port must scope it per session. `HARNEST_HELD_LOCK` (release:307) and `SUITE_EDITS` (loop:230) are process-wide the same way.
3. **Some sessions set no SESSION_ENV. No effect today.** run-features, run-curate, run-retro and run-release don't set it, so their guard would see `HARNEST_TARGET` as unset (lem) and no role or kind. But this changes no decision:
   - the `lead`, `curator` and `reviewer` guard roles never read those values (guard.py:400 `target = server if role == "consumer"`, and `claim_rule` gets a server only for consumer or implementer, :420);
   - curate audit and retro load no guard hook at all.

   It matters only if those roles gain target rules. Set SESSION_ENV uniformly in the port anyway.
4. **Per-target naming is inconsistent.**
   - The `-mps` clone suffix (tsfx) is applied in run-loop and run-features but **not** in run-regression (:76-77), run-release, run-bench or file-advisory.
   - run-features writes `.last-session.features` and `.prompt.lead.<kind>.md` with **no TARGET_SUFFIX** (:78,93), so a lem and a local features run would clobber each other. Today they are serialized only by the SHARED_PASSES convention.
   - The `-mps` suffix is named after the backend, while `.local` is named after the target.
5. **Direct writes to `$LOGS/loop.log`, and a probable retro bug.** curate (:111,118,121), retro (:155) and release (say, :86) write to `$LOGS/loop.log` instead of `$LOOP_LOG`, so their lines always land in lem's stream. Both readers of the log read only `loop.log`:
   - **Curate:** the exclusion is **on purpose**. run-regression:330-332 tags local levels `smoke.local` so that `chunk_table` neither counts nor mixes them.
   - **Retro:** the exclusion **contradicts a test's stated intent**. test-drivers asserts `"regression local: sessions are labelled for retro" "[regression-local:smoke] usage:"`, and that label fits retro's `^\[([a-z-]+):` regex. But retro's evidence builder opens only `loop.log` (run-retro:61), and local sessions write to `loop.local.log`. So local and Mac-loop session costs, audit warnings and guard refusals never reach the retro. It does pick up `*.local.jsonl` for denials. **Probably a bug.**
6. **run-digest.sh bypasses the whole session path** (:171-179). It calls `claude -p` directly with text output: no stream-json, no render, no jsonl, no `usage:` line, no rate-limit sleep, no retry, no effort, no autocompact. Its cost is invisible to retro and the dashboard. The bench judge likewise uses `--output-format json` and a `perl alarm` timeout, and passes `--effort` even for a non-anthropic JUDGE_PROVIDER.
7. **Compact-JSON dependency.** `resolved_model` does `grep '"subtype":"init"'`, and `session_called_mcp` checks `"name":"mcp__dw__` (space-stripped, so robust). A Python re-serializer with default separators breaks `resolved_model` silently: commit trailers would fall back to the alias.
8. **dashboard/serve.py is coupled to process shapes.** `DRIVER_RE` matches `run-*.sh` command lines. The claude-session count matches `claude ... -p|--print`, which SDK children lack. `STREAMS`/`LOCKS` hard-code "lem" and "mac". It reads `release-*/gates.out`, which **nothing in the repo writes**: it is a manual redirect convention and should be documented or written by run-release.
9. **`target_default` has no caller** outside test-providers:155 (dead code). providers.sh's own header comment (:588-595) says "Only run-regression.sh accepts `local` so far ... run-loop.sh and run-release.sh refuse any other target". That is stale and **contradicts the code and CLAUDE.md**: run-loop and run-features accept `local`, and only run-release refuses it (:78). The header function list (:13-52) also omits several functions, among them session_flags, run_claude_session, claim_issue, deploy_cmd, target_preflight, issue_snapshot, classify_issues, queue_issues, note_progress and role_prompt.
10. **BSD-only calls:** `date -r <epoch>` (providers:1118), `find -mmin/-mtime` (providers:842,930; curate:110), `date -v` (digest:56, with a GNU fallback), `sed -u`, `lsof`, and `perl alarm`. The port removes them for free, but a Linux run of the bash today would break at the rate-limit sleep.
11. **The SDK can't unset.** The anthropic provider branch relies on `env -u ANTHROPIC_BASE_URL ...`, and `ClaudeAgentOptions.env` can only add or override. The port must scrub its own `os.environ`, and must not set the key to an empty string without checking what the CLI does with that.
12. **SDK default system prompt.** Leaving `system_prompt` unset sends `--system-prompt ""`, which drops Claude Code's own system prompt: tool guidance, and the exact model id that runtime_note tells agents to cite. Use the `claude_code` preset with `append`, or `extra_args`.
13. **The SDK's `allowed_tools` is comma-joined into one argv word**, where the harness passes separate words today. Equivalent as long as no rule contains a comma. `_apply_skills_defaults` may also rewrite allowed tools and setting sources: unverified.
14. **guard.py is the most dw-coupled "generic" file** (93 occurrences):
    - the hand-off gate hard-codes ruff, pytest, npm, venv and `dw/`, `dw_mcp/`, `tests/`, `ui/`;
    - the target rules hard-code `mps`;
    - the MCP name `mcp__dw__` is hard-coded.

    R13 step 1 needs a `handoff_gate` hook in the profile, plus env-passed MCP-name, backend and harness-repo values. **classify.jq's `serves()`** hard-codes the lem/cuda and local/mps mapping, which is exactly the servers table's "backend" column.
15. **run-release.sh is a dw release process, not framework.** It covers preflight.sh, ci.yml/codeql.yml, port 8971, docs/RELEASING.md, scripts/release.sh and pip advisories. Treat it as a target plug-in, and port lib/release.sh's pure functions as generic.
16. **Error handling depends on bash semantics.** It is built on set -e exemptions (`step`, "always returns 0" functions, `|| true` after gh). CLAUDE.md warns about editing live drivers, and every driver now ends with `main "$@"; exit` (run-loop:929, etc.) for that reason. A Python port removes the byte-offset hazard, but has to reproduce "one gh blip never stops the loop", pass by pass.
17. **The `harnest#N` tag form is parsed** in run_agent (run-loop:339-342) to pick the harness repo for the ledger. The tag text is load-bearing.
18. **The fake `gh` returns `[]` for any unknown `gh api` path.** So `handoff_count` and `parked_since` are always 0 in the driver tests: escalation and parking by bounce count are covered only by the stubbed unit test (test-providers:61-64), never end to end.

---

## Appendix A: every code-line hit, tagged

The tags come from ordered pattern rules on the lowercased line, applied first match wins:
1. `guard.py` lines up to 98, `contract/*` docstrings, and `implementer*.json` → **prose** (pack).
2. `ruff|pytest|npm|ui/|ui_dir|dw_mcp|"dw/"|venv` → **dw-logic** handoff_gate.
3. `qa-|workspace` → **dw-logic** suite levels/workspaces (pack).
4. `serves(|verified-on:mps|backend:mps|backend:cuda|cuda|"mps"` → **dw-logic** servers.backend.
5. Everything else → **value**, with the profile field chosen by keyword:
   - mcp__dw → mcp_server.name;
   - plugins/dw or plugin_tree → plugin_tree;
   - harness_repo;
   - ticket_repo;
   - ticket_owner;
   - deploy.sh or deploy_cmd → servers.deploy_cmd;
   - deployed_head or lem_at → servers.head_cmd;
   - api/health → servers.health;
   - target:, backend:, TARGET_SUFFIX, DW_TARGET or lock → servers table;
   - SOURCE_DIR or the other trees → clones;
   - DW_URL or DW_TOKEN → mcp_server.config;
   - bare lem or ssh → servers.lem;
   - DW_LOCAL → servers.local;
   - diffusers → product name;
   - bare dw → mcp_server.name or product.

Manual corrections, **applied to the rows below and to the 4a counts**:
- run-regression's 12 workspace rows were retagged from dw-logic to **value**, field `suite_levels/workspaces (pack)`. They pass a workspace name through; the level → workspace rule itself is pack data.
- run-bench's 8 `venv`/pytest rows keep dw-logic, with the field changed to **`bench.score`**.
- `lib/classify.jq:64,88,154,160` (lem as holder, default or the lem-only queues) were retagged from value to **dw-logic**, field `servers table (lem as holder/default)`.

Comment-line hits (the "comment" column in 4a) are omitted and count as prose.

| file:line | tag | profile field | text (first 100 chars) |
|---|---|---|---|
| providers.sh:340 | value | mcp_server.name (tool allowlist) | `"mcp__dw__*" "ToolSearch" "Skill" "TodoWrite"` |
| providers.sh:346 | value | mcp_server.name (tool allowlist) | `"mcp__dw__delete_model" "mcp__dw__update_diffusers"` |
| providers.sh:371 | value | mcp_server.name (tool allowlist) | `"mcp__dw__list_workflows" "mcp__dw__list_guides" "mcp__dw__list_pipelines"` |
| providers.sh:372 | value | mcp_server.name (tool allowlist) | `"mcp__dw__list_classes" "mcp__dw__list_tasks" "mcp__dw__get_server_info"` |
| providers.sh:373 | value | mcp_server.name (tool allowlist) | `"mcp__dw__get_schema" "mcp__dw__get_guide" "mcp__dw__get_class" "mcp__dw__get_task"` |
| providers.sh:374 | value | mcp_server.name (tool allowlist) | `"mcp__dw__get_pipeline_signature" "mcp__dw__get_workflow"` |
| providers.sh:375 | dw-logic | suite_levels/workspaces (pack) | `"mcp__dw__list_workspaces" "mcp__dw__list_jobs" "mcp__dw__get_job"` |
| providers.sh:376 | value | mcp_server.name (tool allowlist) | `"mcp__dw__list_gallery" "mcp__dw__get_gallery_metadata" "mcp__dw__list_assets"` |
| providers.sh:399 | value | mcp_server.name (tool allowlist) | `"mcp__dw__get_server_info" "mcp__dw__list_guides" "mcp__dw__get_guide"` |
| providers.sh:400 | value | mcp_server.name (tool allowlist) | `"mcp__dw__get_schema" "mcp__dw__list_tasks" "mcp__dw__get_task"` |
| providers.sh:401 | value | mcp_server.name (tool allowlist) | `"mcp__dw__list_workflows" "mcp__dw__get_workflow"` |
| providers.sh:442 | value | mcp_server.name (tool allowlist) | `"mcp__dw__get_schema" "mcp__dw__list_tasks" "mcp__dw__get_task"` |
| providers.sh:443 | value | mcp_server.name (tool allowlist) | `"mcp__dw__list_workflows" "mcp__dw__get_guide" "mcp__dw__list_guides"` |
| providers.sh:596 | value | servers table (name/claims/suffix) | `DW_TARGET="${DW_TARGET:-lem}"` |
| providers.sh:598 | value | servers.local | `DW_LOCAL_DIR="${DW_LOCAL_DIR:-$HOME/src/dkackman/dw-mps-serve}"` |
| providers.sh:599 | dw-logic | suite_levels/workspaces (pack) | `DW_LOCAL_WORKSPACE="${DW_LOCAL_WORKSPACE:-$HOME/dw-mps-workspace}"` |
| providers.sh:600 | value | servers table (name/claims/suffix) | `TARGET_SUFFIX=""   # set by resolve_target; lem's names until then` |
| providers.sh:606 | value | servers table (name/claims/suffix) | `target_default() { if [ "${DW_TARGET:-lem}" = lem ]; then printf '%s\n' "$1"; else printf '%s\n' "$2` |
| providers.sh:618 | value | servers table (name/claims/suffix) | `case "$DW_TARGET" in` |
| providers.sh:619 | value | servers.lem (name in text) | `lem)` |
| providers.sh:622 | value | mcp_server.config | `DW_URL="${DW_URL:-http://lem:8765/mcp}" ;;` |
| providers.sh:626 | value | mcp_server.config | `DW_URL="${DW_URL:-http://localhost:8765/mcp}"` |
| providers.sh:627 | value | servers.local | `git -C "$DW_LOCAL_DIR" rev-parse --git-dir >/dev/null 2>&1 \` |
| providers.sh:628 | value | servers.local | `\|\| { echo "DW_LOCAL_DIR is not a git checkout: $DW_LOCAL_DIR (the checkout the local server runs f` |
| providers.sh:633 | value | mcp_server.config | `case "$(url_host "$DW_URL")" in` |
| providers.sh:635 | value | mcp_server.config | `*) [ "$(short_host "$(url_host "$DW_URL")")" = "$(short_host "$(hostname)")" ] \` |
| providers.sh:636 | value | servers table (name/claims/suffix) | `\|\| { echo "DW_TARGET=local needs a DW_URL on this machine, got $DW_URL (unset DW_URL for the defau` |
| providers.sh:639 | value | servers table (name/claims/suffix) | `echo "DW_TARGET must be lem or local, got '$DW_TARGET'" >&2` |
| providers.sh:668 | value | mcp_server.config | `local base="${DW_URL%/}" h` |
| providers.sh:670 | value | servers.health | `h="$(curl -s -m 5 -H "Authorization: Bearer ${DW_TOKEN:-}" "$base/api/health" 2>/dev/null)" \|\| ret` |
| providers.sh:683 | value | servers table (name/claims/suffix) | `\|\| { echo "no dw server answering at $DW_URL (DW_TARGET=$DW_TARGET): start it from $DW_LOCAL_DIR f` |
| providers.sh:686 | value | servers table (name/claims/suffix) | `\|\| { echo "the server at $DW_URL is $host, not this machine ($(hostname)): DW_TARGET=$DW_TARGET ru` |
| providers.sh:700 | value | servers.head_cmd | `deployed_head() {` |
| providers.sh:701 | value | servers table (name/claims/suffix) | `if [ "${DW_TARGET:-lem}" = local ]; then` |
| providers.sh:707 | value | servers.lem (name in text) | `ssh -o ConnectTimeout=8 -o BatchMode=yes lem \` |
| providers.sh:708 | value | servers.head_cmd | `'cd ~/diffusers-workflow && echo "$(git branch --show-current) @ $(git rev-parse --short HEAD)"' 2>/` |
| providers.sh:719 | value | servers table (name/claims/suffix) | `[ "${DW_TARGET:-lem}" = lem ] && return 0` |
| providers.sh:722 | value | servers table (name/claims/suffix) | `sed -e "s\|{{TARGET}}\|$DW_TARGET\|g" -e "s\|{{SERVER}}\|$2\|g" -e "s\|{{URL}}\|$DW_URL\|g" \` |
| providers.sh:723 | value | servers.deploy_cmd | `-e "s\|{{DEPLOY}}\|$(deploy_cmd)\|g" -e "s\|{{SERVER_DIR}}\|$DW_LOCAL_DIR\|g" "$f"` |
| providers.sh:735 | value | servers table (name/claims/suffix) | `if [ "${DW_TARGET:-lem}" = lem ]; then` |
| providers.sh:737 | value | servers.deploy_cmd | `echo "ssh -o ConnectTimeout=8 -o BatchMode=yes lem '~/diffusers-workflow/scripts/deploy.sh develop'"` |
| providers.sh:740 | value | mcp_server.config | `port="$(printf '%s' "${DW_URL#*://}" \| sed -n 's\|^[^/]*:\([0-9][0-9]*\).*\|\1\|p')"` |
| providers.sh:741 | dw-logic | suite_levels/workspaces (pack) | `echo "DW_DIR=$DW_LOCAL_DIR DW_WORKSPACE=$DW_LOCAL_WORKSPACE DW_HOST=127.0.0.1 DW_PORT=${port:-8765} ` |
| providers.sh:753 | value | servers.health | `if [ "${DW_TARGET:-lem}" = lem ]; then echo lem; else echo "the $DW_TARGET server ($TARGET_HEALTH)";` |
| providers.sh:767 | value | servers table (name/claims/suffix) | `local n="$1" labels mine="target:$DW_TARGET"` |
| providers.sh:770 | value | servers table (name/claims/suffix) | `printf '%s\n' "$labels" \| grep -q '^target:' && return 1` |
| providers.sh:774 | value | servers table (name/claims/suffix) | `if printf '%s\n' "$labels" \| grep '^target:' \| grep -vqx "$mine"; then` |
| providers.sh:799 | value | plugin_tree | `refresh_plugin_tree() {` |
| providers.sh:953 | value | servers table (name/claims/suffix) | `echo "regression-suite-*.md regression-perf/$DW_TARGET"` |
| providers.sh:955 | value | servers table (name/claims/suffix) | `echo "regression-perf/$DW_TARGET"` |
| providers.sh:1288 | value | ticket_owner | `\| jq -s --arg me "$TICKET_OWNER" --arg target "${DW_TARGET:-lem}" '.[1] as $m \| {owner: $me, targe` |
| run-loop.sh:79 | value | servers table (name/claims/suffix) | `tsfx="$( [ "${DW_TARGET:-lem}" = lem ] \|\| echo -mps )"` |
| run-loop.sh:83 | value | clones (source/lead/release) | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent$tsfx}"` |
| run-loop.sh:86 | value | plugin_tree | `PLUGIN_TREE="${PLUGIN_TREE:-$HOME/src/dkackman/dw-agent-plugin$tsfx}"` |
| run-loop.sh:88 | value | clones (source/lead/release) | `LEAD_TREE="${LEAD_TREE:-$HOME/src/dkackman/dw-agent-lead$tsfx}"` |
| run-loop.sh:89 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| run-loop.sh:90 | value | ticket_owner | `TICKET_OWNER="${TICKET_OWNER:-dkackman}"   # GitHub login whose issues the agents may act on unasked` |
| run-loop.sh:91 | value | harness_repo | `HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"   # this repo: where suite-change requests are file` |
| run-loop.sh:190 | value | mcp_server.config | `DW_URL="${DW_URL:-}"            # resolve_target fills in the target's` |
| run-loop.sh:191 | value | mcp_server.config | `DW_TOKEN="${DW_TOKEN:-xyz}"     # dev token; the server is LAN-only` |
| run-loop.sh:196 | value | plugin_tree | `PLUGIN_DIR="$PLUGIN_TREE/plugins/dw"` |
| run-loop.sh:198 | value | ticket_repo | `[ -d "$SOURCE_DIR" ] \|\| { echo "SOURCE_DIR not found: $SOURCE_DIR (clone it: git clone -b develop ` |
| run-loop.sh:214 | dw-logic | servers.backend | `for l in target:lem target:local backend:shared backend:cuda backend:mps verified-on:mps; do` |
| run-loop.sh:217 | value | servers table (name/claims/suffix) | `if [ "$DW_TARGET" != lem ]; then` |
| run-loop.sh:222 | value | mcp_server.config | `echo "[loop] no server answering at $DW_URL; deploying the serving clone" \| tee -a "$LOOP_LOG"` |
| run-loop.sh:234 | value | plugin_tree | `refresh_plugin_tree "$SOURCE_DIR" "$PLUGIN_TREE" >/dev/null \` |
| run-loop.sh:235 | value | plugin_tree | `\|\| { echo "could not create/refresh the plugin worktree $PLUGIN_TREE from $SOURCE_DIR" >&2; exit 1` |
| run-loop.sh:236 | value | plugin_tree | `[ -d "$PLUGIN_DIR" ] \|\| { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }` |
| run-loop.sh:276 | value | mcp_server.config | `--mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authoriz` |
| run-loop.sh:354 | value | servers table (name/claims/suffix) | `local -a SESSION_ENV=(HARNEST_SESSION_KIND="$kind" HARNEST_TARGET="$DW_TARGET" HARNEST_ROLE="$role"` |
| run-loop.sh:392 | value | servers table (name/claims/suffix) | `local out seen="$LOGS/closures-seen$TARGET_SUFFIX" l mine="target:$DW_TARGET"` |
| run-loop.sh:396 | value | servers table (name/claims/suffix) | `--jq ".[] \| select([.labels[].name \| select(startswith(\"target:\"))] as \$c \| (\$c \| index(\"$m` |
| run-loop.sh:434 | value | clones (source/lead/release) | `want="$(git -C "$SOURCE_DIR" ls-remote -q origin refs/heads/develop 2>/dev/null \| cut -f1 \|\| true` |
| run-loop.sh:436 | value | servers.head_cmd | `case "$DEPLOYED_HEAD" in` |
| run-loop.sh:438 | value | servers.head_cmd | `head_sha="${DEPLOYED_HEAD#develop @ }"` |
| run-loop.sh:441 | value | servers.head_cmd | `echo "[loop] WARNING: $SERVER_NAME is on '$DEPLOYED_HEAD' but origin/develop is ${want:0:10} — the` |
| run-loop.sh:445 | value | servers.head_cmd | `DEPLOYED_HEAD="$(deployed_head)"` |
| run-loop.sh:446 | value | servers.head_cmd | `echo "[loop] $SERVER_NAME is running: $DEPLOYED_HEAD (after driver deploy)" \| tee -a "$LOOP_LOG"` |
| run-loop.sh:448 | value | servers.head_cmd | `echo "[loop] driver deploy of develop failed; the tester runs against '$DEPLOYED_HEAD'" \| tee -a "$` |
| run-loop.sh:458 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" fetch -q origin develop 2>/dev/null \|\| true` |
| run-loop.sh:459 | value | clones (source/lead/release) | `HARNEST_BASE_COMMIT="$(git -C "$SOURCE_DIR" rev-parse -q --verify origin/develop 2>/dev/null \|\| tr` |
| run-loop.sh:481 | value | clones (source/lead/release) | `run_agent implementer triage "$TRIAGE_BUDGET_USD" "$SOURCE_DIR" "$TRIAGE_PROVIDER" "$TRIAGE_MODEL" "` |
| run-loop.sh:484 | value | servers.head_cmd | `$SERVER_NAME is running: $DEPLOYED_HEAD (as of $(ts)).` |
| run-loop.sh:518 | value | clones (source/lead/release) | `run_agent implementer "#$n" "$IMPLEMENTER_BUDGET_USD" "$SOURCE_DIR" "$provider" "$model" "$IMPLEMENT` |
| run-loop.sh:521 | value | servers.head_cmd | `$SERVER_NAME is running: $DEPLOYED_HEAD (as of $(ts)).` |
| run-loop.sh:540 | value | servers table (name/claims/suffix) | `shared_passes_here \|\| { echo "[features] skipping: lem's loop runs it" \| tee -a "$LOOP_LOG"; retu` |
| run-loop.sh:542 | value | ticket_repo | `env LEAD_MODEL="$LEAD_MODEL" LEAD_PROVIDER="$LEAD_PROVIDER" LEAD_EFFORT="$LEAD_EFFORT"     PROVIDER=` |
| run-loop.sh:565 | value | clones (source/lead/release) | `run_agent lead "#$n" "$LEAD_STAGE_BUDGET_USD" "$SOURCE_DIR" "$LEAD_PROVIDER" "$LEAD_MODEL" "$LEAD_EF` |
| run-loop.sh:568 | value | servers.head_cmd | `$SERVER_NAME is running: $DEPLOYED_HEAD (as of $(ts)).` |
| run-loop.sh:600 | value | clones (source/lead/release) | `run_agent lead "#$n" "$LEAD_CLOSEOUT_BUDGET_USD" "$SOURCE_DIR" "$LEAD_PROVIDER" "$LEAD_MODEL" "$LEAD` |
| run-loop.sh:651 | value | servers.head_cmd | `$SERVER_NAME is running: $DEPLOYED_HEAD (as of $(ts)).` |
| run-loop.sh:672 | value | servers.head_cmd | `$SERVER_NAME is running: $DEPLOYED_HEAD (as of $(ts)).` |
| run-loop.sh:690 | value | servers.head_cmd | `$SERVER_NAME is running: $DEPLOYED_HEAD (as of $(ts)).` |
| run-loop.sh:717 | value | servers.lem (name in text) | `echo "[tester:task] standing task: lem only (its bible and fixtures are lem's)" \| tee -a "$LOOP_LOG` |
| run-loop.sh:752 | value | servers table (name/claims/suffix) | `shared_passes_here \|\| { echo "[reviewer] skipping: lem's loop runs it" \| tee -a "$LOOP_LOG"; retu` |
| run-loop.sh:757 | value | plugin_tree | `run_agent reviewer "#$n" "$REVIEWER_BUDGET_USD" "$PLUGIN_TREE" "$REVIEWER_PROVIDER" "$REVIEWER_MODEL` |
| run-loop.sh:760 | value | plugin_tree | `Your working directory is the merged tree at origin/develop @ $(git -C "$PLUGIN_TREE" rev-parse --sh` |
| run-loop.sh:776 | value | servers table (name/claims/suffix) | `shared_passes_here \|\| { echo "[curator] skipping: lem's loop runs it" \| tee -a "$LOOP_LOG"; retur` |
| run-loop.sh:818 | value | ticket_repo | `env HARNEST_HELD_LOCK="$$ run-loop" DW_TARGET="$DW_TARGET" TICKET_REPO="$TICKET_REPO" TICKET_OWNER="` |
| run-loop.sh:819 | value | plugin_tree | `SOURCE_DIR="$SOURCE_DIR" PLUGIN_TREE="$PLUGIN_TREE" PROVIDER="$PROVIDER" DW_URL="$DW_URL" DW_TOKEN="` |
| run-loop.sh:829 | value | servers table (name/claims/suffix) | `[ "$DW_TARGET" = lem ] \|\| ! lem_loop_running` |
| run-loop.sh:867 | value | servers.head_cmd | `DEPLOYED_HEAD="$(deployed_head)"` |
| run-loop.sh:868 | value | servers.head_cmd | `echo "[loop] $SERVER_NAME is running: $DEPLOYED_HEAD" \| tee -a "$LOOP_LOG"` |
| run-loop.sh:875 | value | servers.head_cmd | `DEPLOYED_HEAD="$(deployed_head)"` |
| run-loop.sh:876 | value | servers.head_cmd | `echo "[loop] $SERVER_NAME is running: $DEPLOYED_HEAD (after implementer pass)" \| tee -a "$LOOP_LOG"` |
| run-loop.sh:879 | value | plugin_tree | `if plugin_at="$(refresh_plugin_tree "$SOURCE_DIR" "$PLUGIN_TREE")"; then` |
| run-regression.sh:76 | value | clones (source/lead/release) | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"          # the agents' clone (see run-loop.s` |
| run-regression.sh:77 | value | plugin_tree | `PLUGIN_TREE="${PLUGIN_TREE:-$HOME/src/dkackman/dw-agent-plugin}"  # origin/develop, shared with run-` |
| run-regression.sh:78 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| run-regression.sh:98 | value | mcp_server.config | `DW_URL="${DW_URL:-}"           # empty: the target's own (resolve_target)` |
| run-regression.sh:105 | value | mcp_server.config | `DW_TOKEN="${DW_TOKEN:-xyz}"` |
| run-regression.sh:129 | value | clones (source/lead/release) | `[ -d "$SOURCE_DIR" ] \|\| { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }` |
| run-regression.sh:144 | value | servers table (name/claims/suffix) | `RPFX="regression${TARGET_SUFFIX:+-$DW_TARGET}"` |
| run-regression.sh:145 | value | servers.health | `SERVER="lem" TARGET_HEALTH=""` |
| run-regression.sh:146 | value | servers table (name/claims/suffix) | `if [ "$DW_TARGET" != lem ]; then` |
| run-regression.sh:150 | value | servers.health | `SERVER="the $DW_TARGET server ($TARGET_HEALTH)"` |
| run-regression.sh:156 | value | ticket_repo | `gh label create "target:$DW_TARGET" --repo "$TICKET_REPO" --force --color 5319e7 \` |
| run-regression.sh:157 | value | servers table (name/claims/suffix) | `--description "Found against a non-lem server (DW_TARGET=$DW_TARGET); Don triages" >/dev/null 2>&1 \` |
| run-regression.sh:158 | value | servers table (name/claims/suffix) | `mkdir -p "$REPO/regression-perf/$DW_TARGET"` |
| run-regression.sh:162 | value | ticket_repo | `SESSION_ENV=(HARNEST_TARGET="$DW_TARGET" HARNEST_ROLE=regression HARNEST_TICKET_REPO="$TICKET_REPO")` |
| run-regression.sh:169 | value | servers table (name/claims/suffix) | `if [ "$DW_TARGET" = lem ]; then` |
| run-regression.sh:170 | value | plugin_tree | `PLUGIN_DIR="$PLUGIN_TREE/plugins/dw"` |
| run-regression.sh:171 | value | plugin_tree | `refresh_plugin_tree "$SOURCE_DIR" "$PLUGIN_TREE" >/dev/null \` |
| run-regression.sh:172 | value | plugin_tree | `\|\| { echo "could not create/refresh the plugin worktree $PLUGIN_TREE from $SOURCE_DIR" >&2; exit 1` |
| run-regression.sh:177 | value | plugin_tree | `PLUGIN_DIR="$DW_LOCAL_DIR/plugins/dw"` |
| run-regression.sh:179 | value | plugin_tree | `[ -d "$PLUGIN_DIR" ] \|\| { echo "dw plugin source not found: $PLUGIN_DIR" >&2; exit 1; }` |
| run-regression.sh:222 | value | suite_levels/workspaces (pack) | `workspace_for_suite_file() {` |
| run-regression.sh:236 | value | mcp_server.config | `--mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authoriz` |
| run-regression.sh:251 | value | suite_levels/workspaces (pack) | `local level="$1" suite_file="$2" workspace="$3" tag="$4" kind="$5" instructions="$6" prompt_file` |
| run-regression.sh:259 | value | servers table (name/claims/suffix) | `run_claude_session "regression${TARGET_SUFFIX:+-$DW_TARGET}:$level$tag" "$LOGNAME_REGRESSION" "$REPO` |
| run-regression.sh:260 | value | suite_levels/workspaces (pack) | `"Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to file/comment on them. Your role instru` |
| run-regression.sh:294 | value | suite_levels/workspaces (pack) | `local level="$1" suite_arg="$2" suite_file workspace` |
| run-regression.sh:305 | value | suite_levels/workspaces (pack) | `workspace="$(workspace_for_suite_file "$suite_file")"` |
| run-regression.sh:317 | value | mcp_server.config | `report="$(python3 "$REPO/contract/run.py" --url "$DW_URL" --token "$DW_TOKEN" "${script_ids[@]}" 2>&` |
| run-regression.sh:329 | value | servers.head_cmd | `head="$(deployed_head)"` |
| run-regression.sh:344 | value | suite_levels/workspaces (pack) | `echo "=== $(ts) regression run ($MODEL_LABEL, level=$tag, suite=$suite_file, workspace=$workspace, t` |
| run-regression.sh:345 | value | suite_levels/workspaces (pack) | `run_session "$level" "$suite_file" "$workspace" "" whole \` |
| run-regression.sh:346 | value | suite_levels/workspaces (pack) | `"Exercise every case in the suite file against the $workspace workspace, file or comment on issues f` |
| run-regression.sh:358 | value | suite_levels/workspaces (pack) | `echo "=== $(ts) regression run ($MODEL_LABEL, level=$tag, suite=$suite_file, workspace=$workspace, t` |
| run-regression.sh:364 | value | suite_levels/workspaces (pack) | `run_session "$level" "$suite_file" "$workspace" ".$session" chunk \` |
| run-regression.sh:375 | value | suite_levels/workspaces (pack) | `run_session "$level" "$suite_file" "$workspace" ".sweep" sweep \` |
| run-regression.sh:376 | value | suite_levels/workspaces (pack) | `"This is the final sweep of a chunked run: every case was already exercised in earlier sessions. Do ` |
| run-regression.sh:384 | value | servers table (name/claims/suffix) | `commit_suite_changes "regression: update $level suite from $(ts) run ($MODEL_LABEL${TARGET_SUFFIX:+,` |
| run-features.sh:41 | value | servers table (name/claims/suffix) | `tsfx="$( [ "${DW_TARGET:-lem}" = lem ] \|\| echo -mps )"` |
| run-features.sh:42 | value | clones (source/lead/release) | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent$tsfx}"` |
| run-features.sh:43 | value | clones (source/lead/release) | `LEAD_TREE="${LEAD_TREE:-$HOME/src/dkackman/dw-agent-lead$tsfx}"` |
| run-features.sh:44 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| run-features.sh:45 | value | ticket_owner | `TICKET_OWNER="${TICKET_OWNER:-dkackman}"` |
| run-features.sh:60 | value | mcp_server.config | `DW_URL="${DW_URL:-}"            # resolve_target fills in the target's` |
| run-features.sh:61 | value | mcp_server.config | `DW_TOKEN="${DW_TOKEN:-xyz}"` |
| run-features.sh:63 | value | clones (source/lead/release) | `[ -d "$SOURCE_DIR" ] \|\| { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }` |
| run-features.sh:82 | value | mcp_server.config | `--mcp-config "{\"mcpServers\":{\"dw\":{\"type\":\"http\",\"url\":\"$DW_URL\",\"headers\":{\"Authoriz` |
| run-features.sh:98 | value | ticket_repo | `"Tickets are GitHub Issues on $TICKET_REPO; use the gh CLI to read/act on them. The repo owner is @$` |
| run-features.sh:117 | value | plugin_tree | `refresh_plugin_tree "$SOURCE_DIR" "$LEAD_TREE" >/dev/null \` |
| run-features.sh:118 | value | clones (source/lead/release) | `\|\| { echo "could not create/refresh the lead worktree $LEAD_TREE from $SOURCE_DIR" >&2; exit 1; }` |
| run-curate.sh:28 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"   # searched for case history` |
| run-curate.sh:29 | value | harness_repo | `HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"            # where proposals are filed` |
| run-retro.sh:19 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| run-retro.sh:20 | value | harness_repo | `HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"` |
| run-digest.sh:22 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| run-digest.sh:23 | value | ticket_owner | `TICKET_OWNER="${TICKET_OWNER:-dkackman}"` |
| run-digest.sh:31 | value | harness_repo | `HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"` |
| run-release.sh:37 | value | clones (source/lead/release) | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"` |
| run-release.sh:41 | value | clones (source/lead/release) | `RELEASE_TREE="${RELEASE_TREE:-$HOME/src/dkackman/dw-agent-release}"` |
| run-release.sh:42 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| run-release.sh:43 | value | ticket_owner | `TICKET_OWNER="${TICKET_OWNER:-dkackman}"` |
| run-release.sh:44 | value | harness_repo | `HARNESS_REPO="${HARNESS_REPO:-dkackman/harnest}"   # where suite-drift requests go` |
| run-release.sh:67 | value | clones (source/lead/release) | `[ -d "$SOURCE_DIR" ] \|\| { echo "SOURCE_DIR not found: $SOURCE_DIR" >&2; exit 1; }` |
| run-release.sh:78 | value | servers table (name/claims/suffix) | `[ "$DW_TARGET" = lem ] \|\| { echo "run-release.sh runs against lem only; DW_TARGET=$DW_TARGET is fo` |
| run-release.sh:103 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" fetch -q origin master develop >/dev/null 2>&1 \|\| true` |
| run-release.sh:104 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" rev-parse origin/develop` |
| run-release.sh:128 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" merge-base --is-ancestor "$from" "$sha" 2>/dev/null \|\| continue` |
| run-release.sh:129 | value | clones (source/lead/release) | `lines="$(git -C "$SOURCE_DIR" log --format='%H%x09%P%x09%s' "$from..$sha" \| while IFS=$'\t' read -r` |
| run-release.sh:131 | value | clones (source/lead/release) | `"$(git -C "$SOURCE_DIR" diff-tree --no-commit-id --name-only -r "$c" \| tr '\n' ' ' \| sed 's/ $//')` |
| run-release.sh:145 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" worktree add --detach "$RELEASE_TREE" "$1" >/dev/null 2>&1 \` |
| run-release.sh:166 | value | servers.lem (name in text) | `local sha="$1" lem` |
| run-release.sh:167 | value | servers.head_cmd | `lem="$(deployed_head)"` |
| run-release.sh:168 | value | servers.lem (name in text) | `case "$lem" in *" @ "*) [ "${sha#"${lem##* @ }"}" = "$sha" ] \|\| { echo "$lem"; return 0; } ;; esac` |
| run-release.sh:170 | value | servers.lem (name in text) | `say "lem runs $lem, not origin/develop ${sha:0:10}: deploying develop" >&2` |
| run-release.sh:172 | value | servers.head_cmd | `lem="$(deployed_head)"` |
| run-release.sh:173 | value | servers.lem (name in text) | `case "$lem" in *" @ "*) [ "${sha#"${lem##* @ }"}" = "$sha" ] \|\| { echo "$lem"; return 0; } ;; esac` |
| run-release.sh:175 | value | servers.lem (name in text) | `echo "$lem"; return 1` |
| run-release.sh:191 | value | servers.lem (name in text) | `local sha problems="" board lem started unfinished waived` |
| run-release.sh:198 | value | clones (source/lead/release) | `unfinished="$(git -C "$SOURCE_DIR" log --format='%h %s' origin/master..origin/develop \` |
| run-release.sh:206 | value | servers.head_cmd | `lem="$(lem_at "$sha")" \` |
| run-release.sh:207 | value | servers.lem (name in text) | `\|\| problems="$problems${problems:+$'\n'}lem runs $lem, not origin/develop ${sha:0:10}"` |
| run-release.sh:208 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" merge-tree --write-tree origin/master origin/develop >/dev/null 2>&1 \` |
| run-release.sh:211 | value | servers.lem (name in text) | `record check "$sha" pass "Board clear, lem on develop, and master merges cleanly.${waived:+ Waived: ` |
| run-release.sh:244 | dw-logic | handoff_gate | `ln -sfn "$SOURCE_DIR/venv" "$RELEASE_TREE/venv"` |
| run-release.sh:245 | dw-logic | handoff_gate | `ln -sfn "$SOURCE_DIR/ui/node_modules" "$RELEASE_TREE/ui/node_modules"` |
| run-release.sh:251 | dw-logic | handoff_gate | `(cd "$RELEASE_TREE" && PATH="$SOURCE_DIR/venv/bin:$PATH" DW_E2E_PYTHON="$SOURCE_DIR/venv/bin/python"` |
| run-release.sh:258 | dw-logic | handoff_gate | `record preflight "$sha" fail "exit $rc$([ -n "$dirty" ] && printf '; ruff rewrote files:\n%s' "$dirt` |
| run-release.sh:264 | value | servers.lem (name in text) | `local sha="$1" lem start level filed drift rc=0` |
| run-release.sh:265 | value | servers.head_cmd | `lem="$(lem_at "$sha")" \|\| { record regression "$sha" fail "lem runs $lem, not ${sha:0:10}, and dep` |
| run-release.sh:285 | value | servers.lem (name in text) | `record regression "$sha" pass "Levels: $RELEASE_REGRESSION_LEVELS, lem $lem. No tickets filed.$drift` |
| run-release.sh:287 | value | servers.lem (name in text) | `record regression "$sha" fail "Levels: $RELEASE_REGRESSION_LEVELS, lem $lem, exit $rc. Filed:` |
| run-release.sh:301 | value | servers.lem (name in text) | `die "the driver lock is held by '${holder#* }' (pid ${holder%% *}): the regression gate needs lem to` |
| run-release.sh:331 | value | ticket_repo | `"Tickets are GitHub Issues on $TICKET_REPO. $instructions Your working directory is a detached workt` |
| run-release.sh:344 | value | clones (source/lead/release) | `base="$(git -C "$SOURCE_DIR" merge-base origin/master "$sha")"` |
| run-release.sh:371 | value | ticket_repo | `adv_url="$(TICKET_REPO="$TICKET_REPO" SOURCE_DIR="$SOURCE_DIR" "$REPO/scripts/file-advisory.sh" \` |
| run-release.sh:407 | value | clones (source/lead/release) | `tag="$(git -C "$SOURCE_DIR" describe --tags --abbrev=0 origin/master)"` |
| run-release.sh:412 | value | clones (source/lead/release) | `\|\| since="$(git -C "$SOURCE_DIR" log -1 --format=%cI "$tag")"` |
| run-release.sh:422 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" log --format='%h %s' "$tag..$sha" \` |
| run-release.sh:430 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" worktree add -q --detach "$wt" "$sha"` |
| run-release.sh:434 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" worktree remove --force "$wt"` |
| run-release.sh:476 | value | clones (source/lead/release) | `printf '  %-11s %s\n' notes "$(git -C "$SOURCE_DIR" show "$sha:docs/RELEASING.md" 2>/dev/null \| gre` |
| run-release.sh:495 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" show "$sha:docs/RELEASING.md" > "$WORK/RELEASING.md"` |
| run-release.sh:501 | value | clones (source/lead/release) | `if git -C "$SOURCE_DIR" merge-base --is-ancestor "$sha" origin/master; then` |
| run-release.sh:523 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" fetch -q origin master` |
| run-release.sh:527 | value | clones (source/lead/release) | `if git -C "$SOURCE_DIR" ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then` |
| run-release.sh:531 | value | clones (source/lead/release) | `[ -e "$master_wt/.git" ] \|\| git -C "$SOURCE_DIR" worktree add -q "$master_wt" master 2>/dev/null \` |
| run-release.sh:532 | value | clones (source/lead/release) | `\|\| git -C "$SOURCE_DIR" worktree add -q -B master "$master_wt" origin/master` |
| run-release.sh:535 | value | clones (source/lead/release) | `git -C "$SOURCE_DIR" worktree remove --force "$master_wt" \|\| true` |
| run-bench.sh:35 | dw-logic | bench.score | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"   # only its venv and object store are read` |
| run-bench.sh:139 | dw-logic | bench.score | `pytest_failures() {` |
| run-bench.sh:141 | dw-logic | bench.score | `(cd "$dir" && PYTHONPATH="$dir" venv/bin/python -m pytest -q -rfE -p no:cacheprovider "$@" 2>&1 \|\|` |
| run-bench.sh:149 | value | clones (source/lead/release) | `git -C "$dir" fetch -q --no-tags "$SOURCE_DIR" "$prefix"` |
| run-bench.sh:152 | dw-logic | bench.score | `ln -s "$SOURCE_DIR/venv" "$dir/venv"` |
| run-bench.sh:177 | dw-logic | bench.score | `echo "$tag $(ts) baseline pytest at ${prefix:0:10}"` |
| run-bench.sh:178 | dw-logic | bench.score | `pytest_failures "$dir" > "$base.tmp" && mv "$base.tmp" "$base"` |
| run-bench.sh:233 | dw-logic | bench.score | `newfail="$(comm -13 "$base" <(pytest_failures "$dir") \| tee "$out/new-failures.txt" \| wc -l \| tr ` |
| run-bench.sh:247 | dw-logic | bench.score | `comm -13 "$base" <(pytest_failures "$dir" "${present[@]}") > "$out/hidden-failures.txt" \|\| true` |
| lib/classify.jq:62 | value | servers table (name/claims/suffix) | `def claims: names \| map(select(startswith("target:")) \| ltrimstr("target:"));` |
| lib/classify.jq:63 | value | servers table (name/claims/suffix) | `def backend: (names \| map(select(startswith("backend:")) \| ltrimstr("backend:")) \| .[0]) // "";` |
| lib/classify.jq:64 | dw-logic | servers table (lem as holder/default) | `def holder: claims \| if index("lem") != null then "lem" else .[0] end;` |
| lib/classify.jq:65 | dw-logic | servers.backend | `def serves($t; $b): ($b == "" or $b == "shared") or ($b == "cuda" and $t == "lem") or ($b == "mps" a` |
| lib/classify.jq:88 | dw-logic | servers table (lem as holder/default) | `\| (.target // "lem") as $target` |
| lib/classify.jq:153 | value | servers table (name/claims/suffix) | `.reason = "target:\($i \| holder) on a backend:\($i \| backend) issue" \| .queue = "stranded"` |
| lib/classify.jq:154 | dw-logic | servers table (lem as holder/default) | `elif (.queue \| IN("tester:spec", "lead:build", "lead:closeout")) and $target != "lem" then` |
| lib/classify.jq:155 | value | servers table (name/claims/suffix) | `.reason = "target: \(.queue) runs on lem only" \| .queue = "wait"` |
| lib/classify.jq:157 | value | servers table (name/claims/suffix) | `if ($i \| holder) == $target then . else .reason = "target:\($i \| holder) holds it" \| .queue = "wa` |
| lib/classify.jq:159 | dw-logic | servers.backend | `if serves($target; $i \| backend) then . else .reason = "target: backend:\($i \| backend) is not ser` |
| lib/classify.jq:160 | dw-logic | servers table (lem as holder/default) | `elif $target == "lem" then .` |
| lib/classify.jq:161 | value | servers table (name/claims/suffix) | `else .reason = "target: handed off before claims existed, so deployed to lem" \| .queue = "wait" end` |
| agent-settings/hooks/guard.py:23 | prose | pack (docstring / auto-mode environment text) | `ruff clean on the changed files, the UI's check/lint/test passing when` |
| agent-settings/hooks/guard.py:24 | prose | pack (docstring / auto-mode environment text) | `ui/ changed, and no pytest failure that isn't also failing on` |
| agent-settings/hooks/guard.py:49 | prose | pack (docstring / auto-mode environment text) | `- may close as completed with no `mcp__dw__` call: it verifies a fix` |
| agent-settings/hooks/guard.py:57 | prose | pack (docstring / auto-mode environment text) | ``mcp__dw__*` call earlier in the session ("only from a real MCP call").` |
| agent-settings/hooks/guard.py:62 | prose | pack (docstring / auto-mode environment text) | `every role, claims (harnest#15 part 2): `target:<server>` labels are the` |
| agent-settings/hooks/guard.py:64 | prose | pack (docstring / auto-mode environment text) | `somewhere other than lem:` |
| agent-settings/hooks/guard.py:65 | prose | pack (docstring / auto-mode environment text) | `- no adding a `target:` label, except the hand-over to lem from another` |
| agent-settings/hooks/guard.py:66 | prose | pack (docstring / auto-mode environment text) | `server's session: `--remove-label target:<this> --add-label target:lem`` |
| agent-settings/hooks/guard.py:68 | prose | pack (docstring / auto-mode environment text) | `implementer on a server other than lem (HARNEST_TARGET, set by run-loop.sh):` |
| agent-settings/hooks/guard.py:69 | prose | pack (docstring / auto-mode environment text) | `- no `ssh`, `scp` or `rsync`: lem is off limits` |
| agent-settings/hooks/guard.py:70 | prose | pack (docstring / auto-mode environment text) | `- no running a deploy script (`deploy.sh`, `deploy-local.sh`): the driver` |
| agent-settings/hooks/guard.py:73 | prose | pack (docstring / auto-mode environment text) | `consumer on a server other than lem (HARNEST_TARGET and HARNEST_ROLE, set` |
| agent-settings/hooks/guard.py:76 | prose | pack (docstring / auto-mode environment text) | `- no Edit/Write to lem's perf history (a top-level` |
| agent-settings/hooks/guard.py:80 | prose | pack (docstring / auto-mode environment text) | `case runs on lem. The loop's tester may add one (a verified` |
| agent-settings/hooks/guard.py:81 | prose | pack (docstring / auto-mode environment text) | `backend:shared fix; its prompt says when)` |
| agent-settings/hooks/guard.py:82 | prose | pack (docstring / auto-mode environment text) | `- `gh issue create` carries exactly one `backend:mps` or `backend:shared`` |
| agent-settings/hooks/guard.py:83 | prose | pack (docstring / auto-mode environment text) | `(a cuda bug can't be observed here), at most one `owner:*`, and no` |
| agent-settings/hooks/guard.py:84 | prose | pack (docstring / auto-mode environment text) | ``target:` label` |
| agent-settings/hooks/guard.py:87 | prose | pack (docstring / auto-mode environment text) | `(HARNEST_HARNESS_REPO, default dkackman/harnest) labeled exactly `suite`` |
| agent-settings/hooks/guard.py:90 | prose | pack (docstring / auto-mode environment text) | `- no `gh issue comment N` on an issue lem's loop holds (`target:lem`;` |
| agent-settings/hooks/guard.py:92 | prose | pack (docstring / auto-mode environment text) | `comments while verifying on lem` |
| agent-settings/hooks/guard.py:93 | prose | pack (docstring / auto-mode environment text) | `- adding `status:verified` also adds `verified-on:mps`` |
| agent-settings/hooks/guard.py:241 | dw-logic | handoff_gate | `"""No new pytest failures and no new ruff findings on HEAD, relative to` |
| agent-settings/hooks/guard.py:245 | dw-logic | handoff_gate | `2026-09-22 it failed two tests and ruff after a run of hand-offs each` |
| agent-settings/hooks/guard.py:269 | dw-logic | handoff_gate | `if f.startswith(("dw/", "dw_mcp/", "tests/"))]` |
| agent-settings/hooks/guard.py:272 | dw-logic | handoff_gate | `r = subprocess.run([py, "-m", "ruff", *args, *changed], cwd=top, capture_output=True, text=True)` |
| agent-settings/hooks/guard.py:273 | dw-logic | handoff_gate | `if r.returncode != 0 and "No module named ruff" not in r.stderr:` |
| agent-settings/hooks/guard.py:274 | dw-logic | handoff_gate | `deny("`ruff %s` fails on files this work changed, as CI would:\n%s"` |
| agent-settings/hooks/guard.py:283 | dw-logic | handoff_gate | `ui_changed = git("diff", "--name-only", "--diff-filter=d", base, "HEAD", "--", "ui/")` |
| agent-settings/hooks/guard.py:285 | dw-logic | handoff_gate | `if ui_changed and os.path.isdir(os.path.join(ui_dir, "node_modules")) and shutil.which("npm"):` |
| agent-settings/hooks/guard.py:287 | dw-logic | handoff_gate | `r = subprocess.run(["npm", "run", "--silent", script], cwd=ui_dir, capture_output=True, text=True)` |
| agent-settings/hooks/guard.py:289 | dw-logic | handoff_gate | `deny("`npm run %s` fails in ui/ on files this work changed, as CI would:\n%s"` |
| agent-settings/hooks/guard.py:293 | dw-logic | handoff_gate | `r = subprocess.run([py, "-m", "pytest", "-q", "-rfE", "-p", "no:cacheprovider"], cwd=root,` |
| agent-settings/hooks/guard.py:312 | dw-logic | handoff_gate | `deny("pytest did not complete on HEAD (exit %d):\n%s" % (r.returncode, r.stdout[-2000:]))` |
| agent-settings/hooks/guard.py:325 | value | mcp_server.name (tool allowlist) | `return any('"name":"mcp__dw__' in l.replace(" ", "") for l in fh)` |
| agent-settings/hooks/guard.py:357 | value | harness_repo | `and repo[-1] == os.environ.get("HARNEST_HARNESS_REPO", "dkackman/harnest") \` |
| agent-settings/hooks/guard.py:362 | value | servers.lem (name in text) | `"""The server this session's loop or run targets, when it isn't lem."""` |
| agent-settings/hooks/guard.py:363 | value | servers table (name/claims/suffix) | `t = os.environ.get("HARNEST_TARGET", "lem")` |
| agent-settings/hooks/guard.py:364 | value | servers table (name/claims/suffix) | `return "" if t in ("", "lem") else t` |
| agent-settings/hooks/guard.py:368 | value | servers table (name/claims/suffix) | `"""target: labels are the driver's claims; the one an agent adds is the` |
| agent-settings/hooks/guard.py:369 | value | servers.lem (name in text) | `hand-over from another server to lem."""` |
| agent-settings/hooks/guard.py:370 | value | servers table (name/claims/suffix) | `claims = [l for l in flag_values(words, "--add-label") if l.startswith("target:")]` |
| agent-settings/hooks/guard.py:373 | value | servers table (name/claims/suffix) | `if target and claims == ["target:lem"] and "target:" + target in flag_values(words, "--remove-label"` |
| agent-settings/hooks/guard.py:375 | value | servers table (name/claims/suffix) | `deny("target: labels are the loop driver's claims. The one change a session makes is "` |
| agent-settings/hooks/guard.py:376 | value | servers table (name/claims/suffix) | `"the hand-over to lem: --remove-label target:<this server> --add-label target:lem.")` |
| agent-settings/hooks/guard.py:380 | value | servers.lem (name in text) | `"""Refuse a write to lem's suite or perf files from a non-lem session."""` |
| agent-settings/hooks/guard.py:388 | value | servers.lem (name in text) | `deny("on the %s server the suite files are read-only: every case in them runs on lem, "` |
| agent-settings/hooks/guard.py:402 | value | servers table (name/claims/suffix) | `if target:` |
| agent-settings/hooks/guard.py:413 | value | servers.lem (name in text) | `deny("this loop runs against the %s server: no ssh, scp or rsync; lem is off "` |
| agent-settings/hooks/guard.py:415 | value | servers.deploy_cmd | `if any(os.path.basename(w) in ("deploy.sh", "deploy-local.sh") for w in cmdw):` |
| agent-settings/hooks/guard.py:421 | value | servers table (name/claims/suffix) | `if any(l.startswith("verified-on:") for l in flag_values(words, "--add-label")) and not target:` |
| agent-settings/hooks/guard.py:424 | dw-logic | servers.backend | `and "verified-on:mps" not in flag_values(words, "--add-label"):` |
| agent-settings/hooks/guard.py:425 | dw-logic | servers.backend | `deny("on the %s server a verification adds verified-on:mps with status:verified, so lem "` |
| agent-settings/hooks/guard.py:426 | dw-logic | servers.backend | `"can tell CUDA hasn't re-verified it." % target)` |
| agent-settings/hooks/guard.py:429 | value | harness_repo | `harness_repo = os.environ.get("HARNEST_HARNESS_REPO", "dkackman/harnest")` |
| agent-settings/hooks/guard.py:436 | value | servers table (name/claims/suffix) | `if target and is_gh_issue(words, "comment") and label_lookup(words, "target:lem") is not False:` |
| agent-settings/hooks/guard.py:437 | value | servers table (name/claims/suffix) | `deny("from the %s server, no comment on an issue lem's loop holds (target:lem), or one "` |
| agent-settings/hooks/guard.py:438 | value | servers table (name/claims/suffix) | `"that couldn't be checked: file your own with a backend: label and reference it."` |
| agent-settings/hooks/guard.py:442 | value | servers table (name/claims/suffix) | `backends = [l for l in labels if l.startswith("backend:")]` |
| agent-settings/hooks/guard.py:443 | dw-logic | servers.backend | `if backends not in (["backend:mps"], ["backend:shared"]) \` |
| agent-settings/hooks/guard.py:444 | value | servers table (name/claims/suffix) | `or any(l.startswith("target:") for l in labels) \` |
| agent-settings/hooks/guard.py:446 | dw-logic | servers.backend | `deny("an issue from the %s server carries exactly one backend:mps or backend:shared "` |
| agent-settings/hooks/guard.py:447 | dw-logic | servers.backend | `"(a cuda bug can't be seen here), one owner, and no target: label (claims are "` |
| agent-settings/hooks/guard.py:497 | value | mcp_server.name / product name | `"session, and this session has made none. Re-run the repro over the dw tools first.")` |
| agent-settings/implementer.json:5 | prose | pack (docstring / auto-mode environment text) | `"- **Organization**: dkackman (personal GitHub account); one maintainer",` |
| agent-settings/implementer.json:6 | prose | pack (docstring / auto-mode environment text) | `"- **Repository visibility**: dkackman/diffusers-workflow is PUBLIC on GitHub. Issue comments and co` |
| agent-settings/implementer.json:7 | prose | pack (docstring / auto-mode environment text) | `"- **Source control**: the trusted repo is the diffusers-workflow checkout this session starts in an` |
| agent-settings/implementer.json:9 | prose | pack (docstring / auto-mode environment text) | `"- **CI/CD deploy targets**: none. Deployment is a manual restart of the dw server on the LAN host `` |
| agent-settings/implementer.json:10 | prose | pack (docstring / auto-mode environment text) | `"- **Sensitive remote targets**: the host `lem` is the only remote box. `ssh lem` for git pull / ser` |
| agent-settings/implementer.json:11 | prose | pack (docstring / auto-mode environment text) | `"- **Network posture**: LAN only. Outbound network is expected for `gh` (GitHub API), `git` to origi` |
| agent-settings/implementer.json:12 | prose | pack (docstring / auto-mode environment text) | `"- **Secrets management**: none configured. The dw server dev token is `xyz` and not secret; anythin` |
| agent-settings/implementer.json:13 | prose | pack (docstring / auto-mode environment text) | `"- **Sensitive data locations**: none in this repo. Generated media under dw workspaces is test outp` |
| agent-settings/implementer.json:15 | prose | pack (docstring / auto-mode environment text) | `"- **Primary use of Claude Code**: this session is the unattended implementer agent of an implemente` |
| agent-settings/implementer.json:16 | prose | pack (docstring / auto-mode environment text) | `"- **Routine and approved**: editing source in the checkout, `git add/commit/push` on a feature bran` |
| agent-settings/implementer.local.json:5 | prose | pack (docstring / auto-mode environment text) | `"- **Organization**: dkackman (personal GitHub account); one maintainer",` |
| agent-settings/implementer.local.json:6 | prose | pack (docstring / auto-mode environment text) | `"- **Repository visibility**: dkackman/diffusers-workflow is PUBLIC on GitHub. Issue comments and co` |
| agent-settings/implementer.local.json:7 | prose | pack (docstring / auto-mode environment text) | `"- **Source control**: the trusted repo is the diffusers-workflow checkout this session starts in an` |
| agent-settings/implementer.local.json:9 | prose | pack (docstring / auto-mode environment text) | `"- **CI/CD deploy targets**: none that this session runs. The dw server runs on THIS machine from th` |
| agent-settings/implementer.local.json:10 | prose | pack (docstring / auto-mode environment text) | `"- **Sensitive remote targets**: none. This loop runs against the local server only: `ssh`, `scp` or` |
| agent-settings/implementer.local.json:12 | prose | pack (docstring / auto-mode environment text) | `"- **Secrets management**: none configured. The dw server dev token is `xyz` and not secret; anythin` |
| agent-settings/implementer.local.json:13 | prose | pack (docstring / auto-mode environment text) | `"- **Sensitive data locations**: none in this repo. Generated media under dw workspaces is test outp` |
| agent-settings/implementer.local.json:15 | prose | pack (docstring / auto-mode environment text) | `"- **Primary use of Claude Code**: this session is the unattended implementer agent of an implemente` |
| agent-settings/implementer.local.json:16 | prose | pack (docstring / auto-mode environment text) | `"- **Routine and approved**: editing source in the checkout, `git add/commit/push` on a feature bran` |
| dashboard/serve.py:48 | value | servers table (name/claims/suffix) | `STREAMS = {"lem": "loop.log", "mac": "loop.local.log"}` |
| dashboard/serve.py:49 | value | servers table (name/claims/suffix) | `LOCKS = {"lem": ".driver.lock", "mac": ".driver.lock.local"}` |
| dashboard/serve.py:52 | value | ticket_repo | `TICKET_REPO = os.environ.get("TICKET_REPO", "dkackman/diffusers-workflow")` |
| dashboard/serve.py:53 | value | harness_repo | `HARNESS_REPO = os.environ.get("HARNESS_REPO", "dkackman/harnest")` |
| dashboard/serve.py:239 | value | ticket_repo | `issues(TICKET_REPO, "dw", ["owner:don"])` |
| dashboard/serve.py:307 | value | servers table (name/claims/suffix) | `"local": "DW_TARGET=local" in cmd, "cmd": cmd,` |
| dashboard/serve.py:382 | value | servers table (name/claims/suffix) | `return "DW_TARGET=local" in out` |
| scripts/deploy-local.sh:15 | value | servers.deploy_cmd | `: "${DW_DIR:?deploy-local.sh: DW_DIR (the serving clone) must be set}"` |
| scripts/deploy-local.sh:16 | value | servers.deploy_cmd | `"$DW_DIR/scripts/deploy.sh" develop` |
| scripts/deploy-local.sh:19 | value | servers.head_cmd | `echo "$(git -C "$DW_DIR" branch --show-current) @ $(git -C "$DW_DIR" rev-parse --short HEAD)" > "$re` |
| scripts/file-advisory.sh:20 | value | ticket_repo | `TICKET_REPO="${TICKET_REPO:-dkackman/diffusers-workflow}"` |
| scripts/file-advisory.sh:21 | value | product name / package | `ADVISORY_PACKAGE="${ADVISORY_PACKAGE:-diffusers-workflow}"` |
| scripts/file-advisory.sh:22 | value | clones (source/lead/release) | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent}"` |
| scripts/file-advisory.sh:60 | value | clones (source/lead/release) | `latest="$(git -C "$SOURCE_DIR" describe --tags --abbrev=0 origin/master 2>/dev/null \|\| true)"` |
| scripts/setup-mac-loop.sh:23 | value | servers table (name/claims/suffix) | `DW_TARGET=local` |
| scripts/setup-mac-loop.sh:26 | value | ticket_repo | `DW_ORIGIN_URL="${DW_ORIGIN_URL:-https://github.com/dkackman/diffusers-workflow.git}"` |
| scripts/setup-mac-loop.sh:27 | value | clones (source/lead/release) | `SOURCE_DIR="${SOURCE_DIR:-$HOME/src/dkackman/dw-agent-mps}"` |
| scripts/setup-mac-loop.sh:42 | value | clones (source/lead/release) | `echo "$what: would clone $DW_ORIGIN_URL (develop) into $dir and run install.sh"` |
| scripts/setup-mac-loop.sh:47 | value | clones (source/lead/release) | `git clone -q -b develop "$DW_ORIGIN_URL" "$dir"` |
| scripts/setup-mac-loop.sh:59 | value | clones (source/lead/release) | `clone "$SOURCE_DIR" "implementer clone"` |
| scripts/setup-mac-loop.sh:60 | value | servers.local | `clone "$DW_LOCAL_DIR" "serving clone"` |
| scripts/setup-mac-loop.sh:61 | dw-logic | suite_levels/workspaces (pack) | `if [ -d "$DW_LOCAL_WORKSPACE" ]; then` |
| scripts/setup-mac-loop.sh:62 | dw-logic | suite_levels/workspaces (pack) | `echo "workspace: already there ($DW_LOCAL_WORKSPACE)"` |
| scripts/setup-mac-loop.sh:64 | dw-logic | suite_levels/workspaces (pack) | `echo "workspace: would create $DW_LOCAL_WORKSPACE"` |
| scripts/setup-mac-loop.sh:66 | dw-logic | suite_levels/workspaces (pack) | `mkdir -p "$DW_LOCAL_WORKSPACE"; echo "workspace: created $DW_LOCAL_WORKSPACE"` |
| scripts/setup-mac-loop.sh:72 | value | mcp_server.name / product name | `1. Stop a dw server you started by hand (what listens on the port:` |
| scripts/setup-mac-loop.sh:75 | value | servers.deploy_cmd | `DW_TARGET=local LOGS="$PWD/logs" bash -c '. ./providers.sh; resolve_target; deploy_target'` |
| scripts/setup-mac-loop.sh:77 | value | servers table (name/claims/suffix) | `DW_TARGET=local SHARED_PASSES=1 MAX_CYCLES=1 ./run-loop.sh` |
| scripts/sync-fixtures.sh:27 | dw-logic | suite_levels/workspaces (pack) | `FIXTURE_SOURCE="${FIXTURE_SOURCE:-lem:diffusers-workspace/common/assets}"` |
| scripts/sync-fixtures.sh:29 | value | mcp_server.config | `DW_URL="${DW_URL:-http://localhost:8765/mcp}"` |
| scripts/sync-fixtures.sh:30 | value | mcp_server.config | `DW_TOKEN="${DW_TOKEN:-xyz}"` |
| scripts/sync-fixtures.sh:31 | dw-logic | suite_levels/workspaces (pack) | `root="${DW_LOCAL_WORKSPACE:-}"` |
| scripts/sync-fixtures.sh:41 | value | mcp_server.config | `base="${DW_URL%/}"; base="${base%/mcp}"` |
| scripts/sync-fixtures.sh:44 | dw-logic | suite_levels/workspaces (pack) | `root="$(curl -s -m 5 -H "Authorization: Bearer $DW_TOKEN" "$base/api/server?workspace=default" 2>/de` |
| scripts/sync-fixtures.sh:45 | dw-logic | suite_levels/workspaces (pack) | `\| jq -er '.directories.workspace // empty' 2>/dev/null)" \` |
| scripts/sync-fixtures.sh:46 | dw-logic | suite_levels/workspaces (pack) | `\|\| { echo "could not ask the server at $DW_URL for its workspace root: start it, or set DW_LOCAL_W` |
| scripts/sync-fixtures.sh:48 | dw-logic | suite_levels/workspaces (pack) | `[ -d "$root" ] \|\| { echo "not a directory on this machine: $root (the local server's --workspace r` |
| scripts/sync-fixtures.sh:59 | dw-logic | suite_levels/workspaces (pack) | `--include='/qa-cast/***' \` |
| scripts/sync-fixtures.sh:60 | dw-logic | suite_levels/workspaces (pack) | `--include='/uploads/' --include='/uploads/qa-cast/***' \` |
| contract/mcp_client.py:5 | prose | pack (docstring / auto-mode environment text) | `consumer of the dw server exactly as the tester is, with no source or` |
| contract/mcp_client.py:6 | prose | pack (docstring / auto-mode environment text) | ``lem` access beyond the MCP endpoint.` |
| contract/run.py:7 | prose | pack (docstring / auto-mode environment text) | `live dw MCP server and prints one JSON report on stdout:` |
| contract/run.py:15 | prose | pack (docstring / auto-mode environment text) | `filing. It is a pure MCP consumer, like the tester: no source, no lem.` |
| contract/run.py:151 | value | mcp_server.config | `ap.add_argument("--url", default=os.environ.get("DW_URL", "http://lem:8765/mcp"))` |
| contract/run.py:152 | value | mcp_server.config | `ap.add_argument("--token", default=os.environ.get("DW_TOKEN", "xyz"))` |
| bench/snapshot.py:11 | value | clones (source/lead/release) | `SRC = os.environ.get("SOURCE_DIR", os.path.expanduser("~/src/dkackman/dw-agent"))` |
| bench/snapshot.py:12 | value | ticket_repo | `REPO = os.environ.get("TICKET_REPO", "dkackman/diffusers-workflow")` |
