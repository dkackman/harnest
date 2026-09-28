# R13 step 2 inventory: role prompts, core vs pack

Read-only inventory of every prompt file under `agents/`, `bench/replay-note.md` and the
framing sections of the four `regression-suite-*.md` files. The source tree is the working
tree on 2026-09-27 (`be9a72e`, plus uncommitted edits to `regression-suite-model-specific.md`
cases, which are out of scope). Byte counts are `wc -c` per section: a heading line through
the line before the next heading, with a fragment's leading blank line folded into its
first heading.

Classes:
- **core**: generic to any "MCP server + source repo + deploy + GitHub Issues" target.
  Such a section may still need profile placeholders, which the table lists.
- **pack**: dw domain.
- **mixed**: the table says which sentences or bullets go to the pack, and gives an estimate
  of the pack bytes.
- **per-server**: lem vs the Mac (harnest#15), which is a server of the same dw target.

---

## 0. Naming collision: "target" means two things

| Where | "target" means | Examples |
|---|---|---|
| harnest#15 (built) | **one dw server** out of several (lem or the Mac) | `agents/<role>/target.md`, `target_note`, `DW_TARGET`, `TARGET_SUFFIX`, `resolve_target`, `target_preflight`, `deploy_target`, `HARNEST_TARGET` (guard), `{{TARGET}}`, labels `target:lem`/`target:local`, "Target section" (implementer/core.md:61, regression/core.md:48,62, tester/target.md:54), "Backend and target labels" (implementer/core.md:49), `regression-perf/{{TARGET}}/` |
| R13 (planned) | **a product under test** (dw, then the second MCP server), with its profile and pack | "target profile", "target pack", `targets/<name>/` |

In R13 terms, every harnest#15 "target" is a **server** (a deployment) of the dw target. A
port that keeps both words will produce `targets/dw/agents/tester/target.md`, and that name
means a server note, not a target pack.

Recommendation: rename the harnest#15 concept to **server** in code and prompt filenames, for
example `agents/<role>/server.md` (or `targets/dw/servers/<name>/<role>.md`),
`server_note`, `HARNEST_SERVER` and `{{SERVER_NAME}}`. Keep "target" for R13. The GitHub
label prefix `target:` is live on dw issues, so rename it in code first
(`claim_label_prefix` in the profile) and migrate the labels separately.

The collision also sits inside the per-server files themselves. "target" there already means
the server, and "Target: the {{TARGET}} server, not lem" hard-codes `lem` as the primary
server, which should be a profile field (`servers.primary`).

---

## 1. Assembly table: what each session's prompt is built from

`role_prompt` (providers.sh:1423-1453) cats `agents/<role>/<p>.md` in the order below into
`$LOGS/.prompt.<role>[.local].<kind>.md`. That file goes to `--append-system-prompt-file`.
Then:
- **`target_note <role> <server>`** (providers.sh:718-724) is appended to that system-prompt
  file only when `DW_TARGET != lem` and `agents/<role>/target.md` exists (run-loop.sh:351-353,
  run-regression.sh:256). It seds in `{{TARGET}} {{SERVER}} {{URL}} {{DEPLOY}}
  {{SERVER_DIR}}`.
- **`runtime_note <role> <provider> <model>`** (providers.sh:548-575) goes in the **user
  prompt**, after the driver's own paragraph, not in the system prompt (run-loop.sh:357-359,
  run-features.sh:105, run-regression.sh:262, run-curate.sh:140, run-release.sh:333,
  run-retro.sh:151, run-bench.sh:189). It is generic apart from its per-role "examples"
  string (core).

| role:kind | files, in order (system prompt) | bytes | + server note (Mac) | driver |
|---|---|---:|---|---|
| implementer:fix | implementer/core, fix | 15,732 | implementer/target.md (2,350) | run-loop.sh `run_agent` |
| implementer:triage | implementer/core, triage | 10,874 | implementer/target.md | run-loop.sh |
| tester:verify | tester/core, verify, cases | 13,707 | tester/target.md (3,419) | run-loop.sh |
| tester:handoff | tester/core, handoff, cases | 11,486 | tester/target.md | run-loop.sh |
| tester:answer | tester/core, answer | 9,696 | tester/target.md | run-loop.sh |
| tester:closures | tester/core, closures | 9,508 | tester/target.md | run-loop.sh |
| tester:task | tester/core, closures, task, cases, standing-task | 17,084 | tester/target.md (the task itself stays on lem) | run-loop.sh |
| tester:spec | tester/core, spec, cases | 14,209 | tester/target.md (spec stays on lem) | run-loop.sh |
| lead:design | lead/core, design | 14,720 | none (no lead/target.md) | run-features.sh |
| lead:decompose | lead/core, decompose | 9,979 | none | run-features.sh |
| lead:build | lead/core, build | 11,895 | none | run-loop.sh `lead_pass` |
| lead:closeout | lead/core, closeout | 10,027 | none | run-loop.sh `lead_pass` |
| curator:audit | curator/core, audit | 7,009 | none | run-curate.sh |
| curator:review | curator/core, review | 8,949 | none | run-loop.sh `curator_pass` |
| reviewer:docs | reviewer/core, docs | 4,654 | none | run-loop.sh `reviewer_pass` |
| release:review | release/core, review | 4,373 | none (run-release refuses non-lem) | run-release.sh |
| release:notes | release/core, notes | 3,386 | none | run-release.sh |
| regression:whole | regression/core, run-cases, sweep | 15,473 | regression/target.md (6,069) | run-regression.sh `run_session` |
| regression:chunk | regression/core, run-cases, chunk | 16,071 | regression/target.md | run-regression.sh |
| regression:sweep | regression/core, sweep | 11,549 | regression/target.md | run-regression.sh |
| retro (no role_prompt) | agents/RETRO.agent.md passed whole as the system-prompt file | 3,103 | none | run-retro.sh:146 |
| bench (implementer fix) | `role_prompt implementer fix`, then `bench/replay-note.md` appended | 15,732 + 1,337 | none | run-bench.sh:107-111 (a `BENCH_PROMPT_REV` before R10 uses `agents/IMPLEMENTER.agent.md`) |

Notes:
- `tester:spec` is a real kind (providers.sh:1437) that CLAUDE.md's kind list omits.
- The implementer's and tester's cores are loaded on every server, but they hold
  per-server text of their own: implementer/core.md "Backend and target labels", tester/core.md:57-62,
  regression/core.md:47-50,61-62. So the per-server split is only partly in the per-server files.
- `runtime_note`'s role list (providers.sh:550-561) has a regression branch that drops "a
  suite-file edit" when `TARGET_SUFFIX` is set. That per-server rule lives in bash, not in
  `target.md`.

---

## 2. Proposed profile fields (used as placeholders below)

| Field | Today's dw value |
|---|---|
| `{ticket_repo}` | `dkackman/diffusers-workflow` |
| `{harness_repo}` | `dkackman/harnest` |
| `{ticket_owner}` | `dkackman` |
| `{human}` | `Don`. This is the framework operator, not strictly target-level, but every prompt names him: 150+ occurrences |
| `{product}` | `diffusers-workflow` (source repo / product name) |
| `{mcp_server}` / `{mcp_tool_prefix}` | `dw` / `mcp__dw__` |
| `{plugin}` / `{plugin_path}` | the `dw` plugin / `plugins/dw/` (optional: "plugin tree, if any") |
| `servers.primary` / `{server}` | `lem` |
| `{deploy_command}` | `ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'` (already `deploy_cmd()`) |
| `{deploy_notes}` | quoting `~`, what deploy.sh does, no hand-rolled `git pull`/`pgrep`/`kill`/`screen`, never `kill -9` |
| `{server_log}` | `journalctl --user -u dw-serve` / `~/dw-serve.log` |
| `{box_access}` | "control over the `lem` box (SSH)", "SSH in, check logs, run the server locally" |
| `{integration_branch}` / `{release_branch}` | `develop` / `master` |
| `{handoff_gate_desc}` | "`ruff` on changed files, UI `npm run check/lint/test` if `ui/` changed, no new pytest failures" (guard.py handoff_gate) |
| `{test_command}` / `{lint_command}` | `venv/bin/python -m pytest` / `ruff` |
| `{commit_example}` | `fix(mcp): #42 - correct param validation for generate_image` |
| `{caller_warning_channel}` | `dw.events.emit_warning` (vs `logger.warning`) |
| `{served_text_rule}` | "the README or a `docs/` page that isn't a guide in the `GUIDES` table of `dw/server/guides.py`; skill, template, guide, docstring or error message is served" |
| `{design_docs}` | `docs/proposals/`, `docs/proposals/complete/<slug>-complete.md`, `docs/proposals/declined/`, `docs/proposals/todo.md` |
| `{release_notes_file}` | `docs/RELEASING.md` |
| `{issue_template}` | `mcp-ticket.md` |
| `{backend_labels}` + guidance | `backend:shared|cuda|mps` ("a CUDA-only path, MPS memory or dtype behavior, a device-specific kernel") |
| `{claim_labels}` | `target:lem|local` (the harnest#15 claim; see §0) |
| `{verified_on_label}` | `verified-on:mps` |
| `{suite_levels}` | table: level, file, workspace, ID prefix, one-line "belongs here" test: smoke/`S-`, complete/`C-`, model-specific/`M-`, security/`SE-` |
| `{fixture_namespace}` | "workspace" per level; `qa-` scratch prefix; shared library `qa-cast/` (`keep_output(shared=true)`) |
| `{tester_memory_file}` | `qa-bible.md` |
| `{mcp_efficiency_tips}` | `run_workflow(..., wait_seconds=55)` / `wait_for_job` / `delete_output(job_id=)` |
| `{readonly_discovery_calls}` | `get_schema`, `list_tasks`, `get_task`, `list_workflows`, `get_guide`, `get_server_info`, `get_gallery_metadata` |
| `{history_calls}` | `get_job` / `list_jobs` / `get_job_events` |
| `{orphan_cleanup}` | `list_gallery(only_orphans=true)`, `delete_output(name="<workflow>/<run id>")` |
| `{perf_timing_source}` | "the job's own `started_at`→`finished_at`" |
| `{costly_action}` | "spends GPU time" / `acknowledged_cost` |
| `{security_precondition_case}` | `SE-F001` (`trust_workflows`) |
| `{discovery_contract_case}` | `S-F015` |
| `{demand_evidence}` | `field-report` label, `list_workspaces`/`list_jobs`/`list_gallery`, excluding `qa-*`/`regression-*` |
| `{surface_kinds}` / `{inertia_examples}` | "engine, MCP, REST and syntax surface", `tests/test_mcp_server.py` surface budget |
| `{park_triggers}` / `{escalation_surface}` | "engine or syntax change, new concept, breaking beyond a rename"; "a new task/command, a new `validate_workflow` rule, a wider argument matrix" |
| `{release_review_areas}` | security / engine / mcp-and-docs / templates-ui-packaging, with their contents |
| `{unreachable_issue_title}` | "MCP unreachable" (generic enough to stay core) |
| `{worker_models}` | `sonnet` (code) / `haiku` (sweeps). A harness knob, not target; move it to driver config |

---

## 3. Section inventory

### implementer (20,368 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 1 | implementer/core.md | `# Role: Implementer Agent — diffusers-workflow MCP` | 1-13 | 724 | mixed (~150 pack) | Asymmetry and trust rule are core. Pack: "its own `venv`", and "control over the `lem` box (SSH), where the MCP server actually runs" → `{box_access}`. `{product}` in the title. |
| 2 | implementer/core.md | `## Tickets` | 14-48 | 2011 | core | Label scheme, ownership, filed-by-someone-else park, only the tester closes completed, name the model. Placeholders: `{ticket_repo}`, `{ticket_owner}` (l.35). |
| 3 | implementer/core.md | `### Backend and target labels` | 49-63 | 720 | per-server (in core) | The claim mechanism (`target:*`, "never add/remove except the hand-over") is framework once multi-server is. The backend taxonomy (shared/cuda/mps and the accelerator examples) is pack `{backend_labels}`. Loaded on lem too. The name collides with §0. |
| 4 | implementer/core.md | `## A security hole you find` | 64-76 | 542 | core | Private advisory via the harness's `$HARNEST_ROOT/scripts/file-advisory.sh`. |
| 5 | implementer/core.md | `## Dispositions other than a fix` | 77-111 | 2053 | mixed (~80) | Duplicate/rejected/needs-info/wontfix/park are protocol. Pack: the "Park for Don" trigger list ("an engine or syntax change, a new concept consumers would have to learn") → `{park_triggers}`. |
| 6 | implementer/core.md | `## Checks before any fix` | 112-128 | 847 | core | Placeholders: `develop` → `{integration_branch}`, "deployed on `lem`" → `{server}`. |
| 7 | implementer/core.md | `## Sessions` | 129-143 | 751 | core | Per-issue sessions, spend cap, no polling. "commit `lem` is running" → `{server}`. |
| 8 | implementer/core.md | `## Enforced by the harness` | 144-160 | 940 | mixed (~120) | Guard one-liners (see §6). Pack: "`ruff` passes …, the UI's check/lint/test pass if you changed `ui/`" → `{handoff_gate_desc}`. "master" → `{release_branch}`. |
| 9 | implementer/fix.md | `## This session: fix one issue` | 1-11 | 552 | core | Batch semantics from triage. |
| 10 | implementer/fix.md | `### Checks` | 12-19 | 365 | core | Points at core "Backend and target labels" and "Checks before any fix". |
| 11 | implementer/fix.md | `### Reproduce` | 20-25 | 213 | mixed (~110) | "using the code and the logs on `lem` (SSH in, check logs, run the server locally if needed)" → `{box_access}`. "Don't rely solely on the tester's repro" is core. |
| 12 | implementer/fix.md | `### Fix` | 26-67 | 2604 | mixed (~700) | Core: branch and commit, resumable trail, diff-vs-issue checklist items 1, 2 and 4, merge to develop before deploy ("server can only be on one commit"), never master. Pack: `{commit_example}` (l.29-30); bullet 3 "What the tester is meant to see reaches MCP … `dw.events.emit_warning`" (l.47-49) → `{caller_warning_channel}` (the principle is core, the API is pack); the plugin bullet (l.60-63) → `{plugin_path}`, optional; `docs/proposals/` (l.65) → `{design_docs}`. |
| 13 | implementer/fix.md | `### Deploy` | 68-92 | 1322 | mixed (~870) | Core, about 450 B: one call, last, after pushing; if it fails, no hand-off, needs-info + owner:don, and why (a status label strands the issue); a plugin-only fix skips the deploy. Pack: the command (l.74), the quoting of `~`, what deploy.sh does, the forbidden `git pull`/`pgrep`/`kill`/`screen`, `kill -9`, the log locations (l.76-85) → `{deploy_command}`, `{deploy_notes}`, `{server_log}`. |
| 14 | implementer/fix.md | `### Hand off` | 93-125 | 2088 | mixed (~450) | Core: label swap, the shipped comment, breaking-change, *propose* a case without writing it, a suite change is a harness-repo request. Pack: the docs-review served-text rule (l.101-106) → `{served_text_rule}`; the four suite files and their one-line tests (l.112-116) → `{suite_levels}`. `dkackman/harnest` → `{harness_repo}`. |
| 15 | implementer/triage.md | `## This session: triage` | 1-41 | 2286 | mixed (~250) | Triage protocol and the `triage:` comment forms are core. Pack: step 5's examples of "new engine or validation surface (a new task/command, a new `validate_workflow` rule, a wider argument matrix)" → `{escalation_surface}`. Step 3 depends on the backend labels (pack/per-server). |
| 16 | implementer/target.md | `## Target: the {{TARGET}} server, not lem` | 1-9 | 443 | per-server | Mac vs lem hardware. `lem` hard-coded as the primary server. |
| 17 | implementer/target.md | `### Deploy` | 10-25 | 836 | per-server | The driver deploys after the session (the MCP connection holds the old server); never commit in `{{SERVER_DIR}}`. Mechanism is framework, content dw. |
| 18 | implementer/target.md | `### No lem` | 26-33 | 308 | per-server | No ssh; `~/dw-serve.log` → `{server_log}` per server. |
| 19 | implementer/target.md | `### Which issues are yours` | 34-46 | 537 | per-server | CUDA → hand to lem via `target:` swap (guard claim_rule). |
| 20 | implementer/target.md | `### Timing` | 47-51 | 226 | per-server | `wait_for_job`/`still_running` (pack tool names) on a slow server. |

### tester (30,637 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 21 | tester/core.md | `# Role: Tester Agent — diffusers-workflow MCP (consumer only)` | 1-23 | 1200 | mixed (~250) | The consumer fence is the core of the design. Pack: `qa-bible.md` in the carve-out (l.15) → `{tester_memory_file}`; the plugin paragraph (l.18-22: "`dw` plugin skills … loaded from `develop`, the same commit `lem` runs") → `{plugin}`, optional. `{product}`, `{server}`. |
| 22 | tester/core.md | `## Tickets` | 24-76 | 3328 | mixed (~300) | Labels, trust, only close from a real MCP call, a hole is an advisory, name the model: all core. Pack: `--template mcp-ticket.md` → `{issue_template}`; the `backend:` label choice (l.59-61) → `{backend_labels}`. Per-server: "no `target:` label (claims are the driver's)" (l.61-62). `{ticket_repo}` l.26. |
| 23 | tester/core.md | `## The regression suites` | 77-93 | 935 | core | Never edit a case; request via `{harness_repo}` (l.83); the `pending:` exception. Points at the verify fragment's "Verifying a feature". |
| 24 | tester/core.md | `## Sessions` | 94-110 | 942 | core | `lem` → `{server}` (l.100). |
| 25 | tester/core.md | `## Working the MCP` | 111-131 | 1279 | mixed (~600) | Core: spend context deliberately, read suites by section, the MCP-unreachable issue, finish in-flight calls before exit. Pack: bullet 1 (`run_workflow(..., wait_seconds=55)`, `delete_output(job_id=)`) → `{mcp_efficiency_tips}`; "the guide's index, one schema section, the summary catalog" → `{readonly_discovery_calls}`. |
| 26 | tester/core.md | `## Your shell` | 132-141 | 477 | core | Mirrors `CONSUMER_PERMISSION_FLAGS` (framework). |
| 27 | tester/core.md | `## Enforced by the harness` | 142-153 | 533 | core | Guard one-liners; `mcp__dw__` → `{mcp_tool_prefix}`. |
| 28 | tester/verify.md | `## This session: VERIFY one issue` | 1-35 | 1889 | mixed (~100) | Verify protocol is core. Pack: "Nothing to observe … a `docs/` page `list_guides` doesn't index" (l.22-24) → `{served_text_rule}`. |
| 29 | tester/verify.md | `### Verifying a feature` | 36-65 | 1728 | core | Stage/parent acceptance via `pending:` cases; bounce to lead. |
| 30 | tester/handoff.md | `## This session: HANDOFF one issue` | 1-25 | 1396 | core | Applies a harness-side edit; points at core "The regression suites". |
| 31 | tester/answer.md | `## This session: ANSWER one issue` | 1-19 | 1002 | mixed (~150) | Answer, then hand back or pass to Don: core. Pack: `get_job/list_jobs/get_job_events` → `{history_calls}`; `qa-bible.md` → `{tester_memory_file}`. |
| 32 | tester/closures.md | `## Closures: wontfix and duplicate` | 1-17 | 814 | core | Accept, or reopen once. |
| 33 | tester/task.md | `## This session: TASK` | 1-9 | 455 | core | The generic wrapper for the standing task; `qa-bible.md` → `{tester_memory_file}`. Stays core, and the standing task under it becomes pack. |
| 34 | tester/cases.md | `## Adding a regression case` | 1-24 | 1396 | mixed (~650) | Core: add only what you ran, follow the file's "Adding a case", measurements go in `regression-perf/`, a `source:` line. Pack: the four-file level list with one-line tests (l.6-13) → `{suite_levels}`; the legacy source string `TESTER_TASK.agent.md` (l.17-18), which is dw history. |
| 35 | tester/spec.md | `## This session: SPEC one feature` | 1-26 | 1293 | core | Spec from the plan alone; source fence; re-plan handling. |
| 36 | tester/spec.md | `### 1. Write the cases` | 27-66 | 1938 | mixed (~500) | Core: positive, refusal and edge cases; `pending:`/`source:` format; runnable later; `contract/` stays agent-run; scope. Pack: "Most feature cases are `regression-suite-complete.md`… security" (l.38-40) → `{suite_levels}`; the media-setup examples (`upload_asset`, `run_workflow` over a template, a `gain_audio` step; l.52-54); the read-only call list (l.62-63) → `{readonly_discovery_calls}`; "spends GPU time" → `{costly_action}`. |
| 37 | tester/spec.md | `### 2. Hand back` | 67-85 | 888 | core | `harnest:specced`/`spec-questions` markers are framework. |
| 38 | tester/standing-task.md | `## The standing task — a test vehicle, not a deliverable` | 1-9 | 463 | mixed (~150) | "Exercise the MCP as a real consumer; process not output" is a generic contract. "Shared library" is pack. R13 names the standing task as pack content; keep a ~300 B generic contract in core or task.md. |
| 39 | tester/standing-task.md | `### Workspace rules` | 10-30 | 1265 | pack | `qa-` workspaces, default workspace, `keep_output(shared=true)`/`upload_asset(shared=true)` under `qa-cast/`. |
| 40 | tester/standing-task.md | `### The exercise` | 31-66 | 2101 | pack | Series/episodes/cast, `dialogue-short`/`music-video` templates, inline `for_each`, `validate_workflow` plan, #478/#479, `TESTER_TASK_EVERY` (a harness knob named here). |
| 41 | tester/standing-task.md | `### The bible` | 67-94 | 1531 | mixed (~600) | Core: a memory file that is a snapshot, not a journal, capped at ~12 KB, condensed rather than overflowed, with no per-cycle narrative. Pack: the fixed section list (Cast, Shared assets `common/assets`, Workspaces `qa-*`, Episodes) and the file name. |
| 42 | tester/standing-task.md | `### Guardrails` | 95-102 | 365 | mixed (~150) | "Don't polish", "don't repeat a step with an open ticket" and "no source, no SSH, MCP only" are core. "One or two workflow runs per cycle" is pack. |
| 43 | tester/target.md | `## Target: the {{TARGET}} server, not lem` | 1-11 | 567 | per-server | lem = 24 GB RTX 3090 with hand-made assets; the Mac is slower. |
| 44 | tester/target.md | `### Verifying here` | 12-29 | 963 | per-server | `verified-on:mps`; hand to lem when a fixture only lem has (`qa-cast/…`) is needed. |
| 45 | tester/target.md | `### Timing` | 30-37 | 326 | per-server | Absolute times are lem's. |
| 46 | tester/target.md | `### Filing` | 38-45 | 341 | per-server | `backend:mps`/`shared`; no comment on `target:lem`. |
| 47 | tester/target.md | `### Suite cases` | 46-61 | 812 | per-server | Shared-fix cases only; mps cases go in the comment (harnest#16); suite request to `dkackman/harnest` (l.55); C-F029/#454 anecdote. |
| 48 | tester/target.md | `### Security probes` | 62-69 | 410 | per-server | Linux probe paths vs macOS. Duplicated verbatim in regression/target.md:99-105. |

### regression (23,092 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 49 | regression/core.md | `# Role: Regression Agent — diffusers-workflow MCP (consumer only)` | 1-32 | 1653 | mixed (~750) | Core: runs one level, standalone, the consumer fence, trust. Pack: the level→file→workspace list (l.8-18) → `{suite_levels}`; the security-level gloss (l.14-18: "hostile-input probes…never escalate") is half generic. `diffusers-workflow`, `lem` placeholders (l.24-25). |
| 50 | regression/core.md | `## Tickets` | 33-51 | 1078 | core | Labels, the `regression`/`performance` labels, the only write actions. Per-server hook (l.47-50: "When it isn't `lem`, a Target section…") → framework `server_note` wording. `{ticket_repo}`. |
| 51 | regression/core.md | `### Reporting a failure` | 52-94 | 2674 | mixed (~250) | Dedupe search, comment vs new issue, suite drift as a harness request, name the model: core. Pack: the ID-prefix list `S-`/`C-`/`M-`/`SE-` (l.57) → `{suite_levels}`; the backend label (l.68-69). Per-server: "On lem, every open issue… On another server, your Target section" (l.61-62). `dkackman/harnest` ×3 (l.77-80) → `{harness_repo}`. |
| 52 | regression/core.md | `### A boundary that didn't hold` | 95-116 | 1158 | core | The private advisory flow; the categories (a type, path or URL through, a disclosure, destructive without ack, refused too late) are generic to MCP servers. |
| 53 | regression/core.md | `## The suite files` | 117-134 | 960 | core | Durable tests; no edits on pass; request route (`{harness_repo}` l.128); append-only readings. |
| 54 | regression/core.md | `## Workspace rules` | 135-163 | 1695 | mixed (~1000) | Core, about 700 B: leave the server as found; fixtures only if listed in the suite's "Fixtures"; generated artifacts deleted per `cleanup:`; a repro artifact kept and named in the issue. Pack: one workspace per level, `create_workspace`, the default workspace, `qa-` workspaces, `delete_workspace`, and the `model-specific` vs `smoke` skew (l.137-143) → `{fixture_namespace}`; the efficiency-tips paragraph (l.156-162) → `{mcp_efficiency_tips}`, duplicated with tester/core.md:113-119. |
| 55 | regression/core.md | `## Your shell` | 164-173 | 480 | core | Mirrors the allowlist. |
| 56 | regression/core.md | `## Guardrails` | 174-188 | 899 | core | MCP unreachable → `REGRESSION-ABORT` (a driver contract); read the suite by section; one pass. |
| 57 | regression/run-cases.md | `## Running cases` | 1-47 | 2967 | mixed (~350) | Core: header first; the live schema is ground truth; skip `pending:`; run every case every run; the perf median rule; cleanup. Pack: "the guide's index, one schema section, the summary catalog — S-F015 describes the contract" (l.11-12) → `{readonly_discovery_calls}`, `{discovery_contract_case}`; "the job's own `started_at`→`finished_at` whenever the case yields a job" (l.27-29) → `{perf_timing_source}`. |
| 58 | regression/run-cases.md | `### Growing the suite` | 48-62 | 957 | core | Points at the suite header's "Where a case belongs" (suite-owned, pack). "a template" in the examples is harmless. |
| 59 | regression/chunk.md | `## This session: one chunk of a chunked run` | 1-26 | 1550 | mixed (~700) | Core: run only your slice; follow `cleanup:` across the slice boundary; re-create a missing hold. Pack: the whole-file precondition example (SE-F001, trust posture; l.16-20) → `{security_precondition_case}` (the rule "run the header's precondition case first" is core); orphan cleanup with `list_gallery(only_orphans=true)`/`delete_output(name=…)` and "most `security` cases pass by refusal" (l.21-26) → `{orphan_cleanup}`. |
| 60 | regression/sweep.md | `## Final sweep` | 1-18 | 952 | mixed (~350) | Core: anything left must be a listed fixture or a repro named in an open issue; chunk leftovers deferred by `cleanup:` are expected. Pack: orphan run dirs "(manifest/workflow/job, no media)", `list_gallery(only_orphans=true)`, `delete_output(name=…)`. |
| 61 | regression/target.md | `## Target: the {{TARGET}} server, not lem` | 1-10 | 547 | per-server | lem hardware and history. |
| 62 | regression/target.md | `### What you file` | 11-39 | 1724 | per-server | Comment vs file across servers; `backend:mps`; `[{{TARGET}}]` advisory tag; `dkackman/harnest` (l.28). |
| 63 | regression/target.md | `### What you may not edit` | 40-50 | 558 | per-server | Suites read-only; `regression-perf/{{TARGET}}/` (guard target_file_rule). |
| 64 | regression/target.md | `### Timing` | 51-62 | 624 | per-server | Judge only against this server's own history. |
| 65 | regression/target.md | `### Skipped, not failed` | 63-88 | 1482 | per-server | `REGRESSION-SKIP` driver contract (framework) with dw reasons: `qa-cast` fixtures, CUDA, MiniMax H3 / LTX-2.5 memory (pack). |
| 66 | regression/target.md | `### Differs on this server` | 89-98 | 466 | per-server | `REGRESSION-DIFFERS` (framework contract); the dw fields `basis`, `measured_on`, `cuda_version`. |
| 67 | regression/target.md | `### Security probes` | 99-108 | 505 | per-server | Duplicates tester/target.md:62-69, plus `trust_workflows`. |
| 68 | regression/target.md | `### Sweep` | 109-112 | 163 | per-server | Keep only repros from issues that aren't `target:lem`. |

### lead (28,582 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 69 | lead/core.md | `# Role: Feature Lead — diffusers-workflow` | 1-24 | 1340 | core | Role, fence, and "a label swap, not a comment author, tells you Don spoke". `{product}` l.1, l.11. |
| 70 | lead/core.md | `## Tickets and labels` | 25-48 | 1227 | core | feature/stage/idea, the plan-review/approved/needs-spec labels. |
| 71 | lead/core.md | `## The plan comment` | 49-68 | 1105 | core | `harnest:plan vN`, PATCH by comment id. Framework. |
| 72 | lead/core.md | `## Phase markers` | 69-84 | 723 | core | `decomposed`/`specced`/`spec-questions vN`, read by classify.jq. |
| 73 | lead/core.md | `## Enforced by the harness` | 85-105 | 799 | core | Guard one-liners; "(clean tree, `ruff`, no new test failures)" → `{handoff_gate_desc}`; `master` → `{release_branch}`. |
| 74 | lead/core.md | `## Sessions` | 106-120 | 819 | core | Foreground subagents, one session per step. The "stage A's first build, 2026-09-23" anecdote is dw history; drop it or leave it in dw docs. |
| 75 | lead/design.md | `## This session: DESIGN one feature` | 1-9 | 389 | core | "read-only `dw` MCP calls" → `{mcp_server}`. |
| 76 | lead/design.md | `### 1. Which turn is this?` | 10-60 | 2753 | core | Don's replies, decline/defer, spec questions, idea triage. |
| 77 | lead/design.md | `### 2. Read, then check the design against the code` | 61-76 | 872 | core | One Explore sweep for every consumer. "REST routes, the MCP client, the UI" → `{surface_kinds}`. The proposal-staleness anecdote is dw history but harmless. |
| 78 | lead/design.md | `### 3. Measure demand` | 77-94 | 919 | mixed (~700) | Core, about 200 B: the evidence ladder and "same-class issues". Pack: "dw is a one-person project with two kinds of user"; the `field-report` label; `list_workspaces`/`list_jobs`/`list_gallery`; excluding `qa-*`/`regression-*` → `{demand_evidence}`. |
| 79 | lead/design.md | `### 4. The verdict: whether to build it at all` | 95-127 | 1627 | mixed (~300) | The axes and the verdict set are core. Pack: "Recent server fixes… $2–6 per session"; the Inertia examples (MCP/REST/syntax surface, `tests/test_mcp_server.py` surface budget, "a concept added to how dw works") → `{inertia_examples}`. |
| 80 | lead/design.md | `### 5. The design and its stages` | 128-159 | 1397 | core | "engine, MCP, REST and syntax surface" → `{surface_kinds}`; "`lem` runs one commit" → `{server}`; deploy path "(server, or plugin-only)". |
| 81 | lead/design.md | `### 6. Questions, then hand to Don` | 160-174 | 750 | core | |
| 82 | lead/decompose.md | `## This session: DECOMPOSE an approved plan` | 1-16 | 759 | core | Points at build's "Stop and re-plan". |
| 83 | lead/decompose.md | `### 0. What exists already` | 17-33 | 905 | core | Sub-issue reconcile. |
| 84 | lead/decompose.md | `### 1. File the stages` | 34-61 | 1436 | core | `gh issue create --parent --blocked-by`. The `385,376` example numbers are cosmetic. |
| 85 | lead/decompose.md | `### 2. Hand the parent to the tester` | 62-78 | 866 | core | Points at core "Phase markers". |
| 86 | lead/build.md | `## This session: BUILD one stage` | 1-12 | 587 | core | |
| 87 | lead/build.md | `### 0. Where does this stage stand?` | 13-22 | 465 | core | |
| 88 | lead/build.md | `### 1. Build, fanning out code-only work` | 23-53 | 1448 | core | Placeholders: "No subagent… calls a `dw` MCP tool. Only this session touches `lem`" → `{mcp_server}`, `{server}`; "full `pytest` and `ruff`" → `{test_command}`, `{lint_command}`; `sonnet`/`haiku` → `{worker_models}` (a harness knob). |
| 89 | lead/build.md | `### 2. Before merging, check the diff against the plan` | 54-68 | 708 | mixed (~120) | Same checklist as fix.md; `dw.events.emit_warning`/`logger.warning` → `{caller_warning_channel}`. |
| 90 | lead/build.md | `### 3. Merge, deploy, hand off` | 69-94 | 1402 | mixed (~350) | Core: merge to develop, deploy last, a failed deploy goes to Don, hand off, verifier override, breaking-change, no suite cases. Pack: `ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'`, the quoting, "never `kill` the server", plugin tree → `{deploy_command}`, `{deploy_notes}`, `{plugin}`. |
| 91 | lead/build.md | `### Stop and re-plan` | 95-119 | 1272 | core | |
| 92 | lead/closeout.md | `## Close-out` | 1-6 | 140 | core | `develop`/`master` placeholders. |
| 93 | lead/closeout.md | `### Declined` | 7-32 | 1401 | mixed (~600) | Core: close the open stages, the retire request on `{harness_repo}` (l.26), close not planned. Pack: `git mv` to `docs/proposals/declined/<slug>.md`, the `todo.md` "Declined" section → `{design_docs}`. |
| 94 | lead/closeout.md | `### Built: which turn is this?` | 33-44 | 565 | core | |
| 95 | lead/closeout.md | `### Built, the first time` | 45-64 | 1038 | mixed (~350) | Core: the design record (what was built, deferred, cost per stage, bounces), commit, hand to the tester. Pack: `docs/proposals/complete/<slug>-complete.md`, `todo.md` → `{design_docs}`. |
| 96 | lead/closeout.md | `### Back from a failed final check` | 65-78 | 870 | core | Fix-forward stages. |

### curator (13,482 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 97 | curator/core.md | `# Role: Curator Agent — regression suites` | 1-10 | 486 | core | `(dkackman)` → `{ticket_owner}`. |
| 98 | curator/core.md | `## Who decides a suite change` | 11-38 | 1414 | core | Needs one pack value: "anything in the security suite beyond a stale reference" → a per-level `escalate: true` flag in `{suite_levels}`. |
| 99 | curator/core.md | `## Enforced by the harness` | 39-50 | 576 | core | Guard one-liners plus the driver's `[audit]` removal warning. |
| 100 | curator/audit.md | `## This session: AUDIT one suite level` | 1-11 | 481 | core | Points at core "Who decides a suite change". |
| 101 | curator/audit.md | `## What you are given` | 12-31 | 963 | core | The chunk table and `regression-perf/` are framework. |
| 102 | curator/audit.md | `## What to look for` | 32-55 | 1342 | core | Relies on the suite header's "Where a case belongs" (pack-owned text, generic reference). |
| 103 | curator/audit.md | `## The issue you file` | 56-90 | 1747 | core | |
| 104 | curator/review.md | `## This session: REVIEW one suite request` | 1-13 | 530 | core | |
| 105 | curator/review.md | `### 0. Has Don already spoken on this?` | 14-29 | 711 | core | |
| 106 | curator/review.md | `### 1. Check the evidence yourself` | 30-46 | 881 | mixed (~200) | Last bullet: "a read-only `dw` call (`get_schema`, `list_tasks`, `get_task`, `list_workflows`, `get_guide`)" → `{readonly_discovery_calls}`. |
| 107 | curator/review.md | `### 2. Rule on each item` | 47-85 | 1986 | core | `regression-suite-security.md` (l.79) → the per-level escalate flag. |
| 108 | curator/review.md | `### 3. Apply what you approved` | 86-97 | 422 | core | |
| 109 | curator/review.md | `### 4. Record it and set the issue's state` | 98-137 | 1943 | mixed (~450) | The comment shape is core. The worked example (l.108-115: SE-F031, `dkackman/diffusers-workflow#409`, #407 plan v2, the dtype key) is dw content; swap in a neutral example. |

### reviewer (4,654 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 110 | reviewer/core.md | `# Role: Docs Reviewer — fixes the tester can't observe` | 1-14 | 744 | core | "neither the MCP server nor the dw plugin serves" → `{plugin}`, `{served_text_rule}`. |
| 111 | reviewer/core.md | `## Tickets` | 15-32 | 879 | core | `dkackman/diffusers-workflow` (l.17) and `dkackman` (l.24) placeholders. |
| 112 | reviewer/core.md | `## Enforced by the harness` | 33-44 | 580 | core | "no dw call that runs or deletes" → `{mcp_server}`. |
| 113 | reviewer/docs.md | `## This session: REVIEW one docs-only fix` | 1-41 | 2451 | mixed (~300) | Core: find what shipped, "not yours", check against the issue, the three outcomes. Pack: the served-file list "code, `plugins/dw/` (skills), templates, or a guide file (the `GUIDES` table in `dw/server/guides.py`)" (l.9-11) → `{served_text_rule}`; "`get_server_info`, `get_schema`, `get_guide`, `list_tasks`" (l.22-23) → `{readonly_discovery_calls}`. |

### release (6,095 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 114 | release/core.md | `# Role: Release reviewer — the whole candidate, once, before a release` | 1-12 | 663 | mixed (~350) | Core: the release as one diff, read-only worktree. Pack or history: the 0.4.0 findings (`subprocess.Popen`, leaked server paths, the stock-template warning). `{product}` l.3. |
| 115 | release/core.md | `## What you produce` | 13-19 | 287 | core | |
| 116 | release/core.md | `## Trust` | 20-25 | 227 | core | `(dkackman)` → `{ticket_owner}`. |
| 117 | release/core.md | `## Your runtime` | 26-30 | 118 | core | |
| 118 | release/core.md | `## Enforced by the harness` | 31-38 | 369 | core | |
| 119 | release/notes.md | `## This session: draft the release NOTES` | 1-33 | 1722 | core | `docs/RELEASING.md` → `{release_notes_file}`; "server, the MCP tools, the templates or the UI" is a mild `{user_surfaces}`. |
| 120 | release/review.md | `## This session: REVIEW one area of the release` | 1-9 | 418 | core | "master...develop" → branch placeholders. |
| 121 | release/review.md | `### Areas` | 10-32 | 1297 | pack | All dw: the untrusted-workflow gate (dotted types, `constant:`, `pre_load_modules`, `trust_remote_code`, `custom_pipeline`), `acknowledged_cost`, the `/api/` and `/mcp` token gate, the step cache, `templates/`, `workflows/`, `ui/`, `pyproject.toml`, `install.sh` → `{release_review_areas}` (area names must match run-release.sh's list). |
| 122 | release/review.md | `### Each finding` | 33-43 | 524 | core | |
| 123 | release/review.md | `### The file` | 44-56 | 470 | core | JSON schema consumed by run-release.sh. |

### retro (3,103 B) and bench (1,337 B)

| # | file | heading | lines | B | class | reason / split / placeholders |
|---|---|---|---|---:|---|---|
| 124 | RETRO.agent.md | `# Role: Retro Agent — the harness looking at itself` | 1-13 | 646 | core | Points at "Principles" in `HARNESS-ROADMAP.md` (framework docs). |
| 125 | RETRO.agent.md | `## What you are given` | 14-29 | 627 | core | |
| 126 | RETRO.agent.md | `## What makes a proposal` | 30-53 | 1435 | core | "source or `lem` access" (l.46) → `{server}`. |
| 127 | RETRO.agent.md | `## Filing` | 54-63 | 395 | core | |
| 128 | bench/replay-note.md | `## Replay session (benchmark)` | 1-23 | 1337 | mixed (~250) | Core: replay semantics, skip Checks/Deploy/Hand off, write HANDOFF.md. Pack: `lem` (l.7, 13), `venv/bin/python -m pytest` (l.17) → `{test_command}`, and "some worker tests fail on this machine" → the profile's "bench scoring command" (R13 step 1). It names fix.md's sections Checks, Deploy, Hand off, Reproduce and Fix, and "Park for Don". |

### regression-suite framing sections (suite-owned; out of `agents/` but loaded by agents via Read)

| file | heading | lines | B | class | reason / split |
|---|---|---|---:|---|---|
| smoke | header (preamble) | 1-42 | 2544 | mixed (~1500 pack) | Pack: the level description, **"Where a case belongs"** (l.10-22; the four-level test that tester/cases.md, tester/spec.md, run-cases.md and curator/audit.md point at by name), workspace `regression-smoke`, the `S-` prefix. Core: the "maintained by… durable test, never a log… no agent may delete" paragraph (l.30-41). |
| smoke | `## Adding a case` | 43-64 | 1291 | mixed (~500) | Core: the format (intent/`expected:`/`cleanup:`/`metrics:`/`source:`), seeding perf, no approval to add. Pack: `S-Fnnn` and the "No case may depend on chance" generative-seed paragraph (the rule is generic, the examples are dw). Legacy `TESTER_TASK.agent.md`. |
| smoke | `## Removing a case` | 65-90 | 1364 | core | The request route and the curator rulings. `dkackman/harnest`. **Verbatim in all four files.** |
| smoke | `## Fixtures` | 91-121 | 1986 | pack | `qa-cast/*` shared assets. |
| complete | header | 1-35 | 2089 | mixed (~1000) | Level, workspace, `C-`; same core paragraph as smoke. |
| complete | `## Adding a case` | 36-57 | 1316 | mixed (~500) | Same as smoke, with `C-`. |
| complete | `## Removing a case` | 58-83 | 1364 | core | Verbatim duplicate. |
| complete | `## Fixtures` | 84-241 | 11230 | pack | 20+ `qa-cast` media assets with frame counts and loudness; the largest framing block anywhere. |
| model-specific | header | 1-32 | 1969 | mixed (~1000) | Level, workspace, `M-`; same core paragraph. |
| model-specific | `## Adding a case` | 33-57 | 1486 | mixed (~600) | Plus "name the model/pipeline/checkpoint", which is pack. |
| model-specific | `## Removing a case` | 58-83 | 1364 | core | Verbatim duplicate. |
| model-specific | `## Fixtures` | 84-118 | 2230 | pack | ffmpeg/LTX recipes for off-box fixtures; `upload_asset`, `keep_output`. |
| security | header | 1-64 | 4074 | mixed (~2600) | Pack: the `--trust-workflows`/`DW_TRUST_WORKFLOWS` posture, SE-F001 gating, dw boundaries. Core-ish: the "how to read a result" two-failure-mode rule (refused too late) is generic to any security level, and so is the advisory pointer. Same core paragraph as the others. |
| security | `## Adding a case` | 65-90 | 1577 | mixed (~600) | Core: harmless probes, state both failure modes. Pack: `/tmp`, loopback, stock system file, `SE-` IDs. |
| security | `## Removing a case` | 91-116 | 1364 | core | Verbatim duplicate. |
| security | `## Not covered here` | 117-147 | 1959 | pack | Bearer token/Origin, `--trust-workflows` on, symlinks, decoder bombs, SSRF targets, SE-F022; dated history. |
| security | `## Fixtures` | 148-165 | 639 | pack | None yet; dated repro notes. |
| security | `## Code execution gate (default: untrusted)` intro | 166-177 | 700 | pack | Category intro (the other category intros, l.423/674/842/878, are the same kind; not inventoried as they're case-area text). |

Framework note: three paragraphs repeat verbatim in every suite file (the "Maintained by…"
paragraph, `## Removing a case`, and "No case may depend on chance"), about 2.7 KB × 4, or 10.9 KB. They
are the framework's suite-format contract. Under R13 they belong in one framework file,
leaving each pack's suite file to hold only level description, workspace, prefix and
Fixtures.

---

## 4. Hard-coded values that should come from the profile

| Value | files:lines | Proposed field |
|---|---|---|
| `dkackman/diffusers-workflow` | implementer/core.md:16; tester/core.md:26; regression/core.md:35; reviewer/core.md:17; curator/review.md:111 (example) | `ticket_repo` (the prompt already says "the repo name is given in your prompt": use a placeholder, or drop the literal) |
| `dkackman/harnest` | implementer/fix.md:124; tester/core.md:83; tester/target.md:55; regression/core.md:77,78,80,128; regression/target.md:28; lead/closeout.md:26; 4× suite `## Removing a case`; guard.py:357,429 default | `harness_repo` |
| `dkackman` (login) | implementer/core.md:35; curator/core.md:8; reviewer/core.md:24; release/core.md:23 | `ticket_owner` |
| `Don` (human) | ~150 lines in every role (`grep -rn "Don" agents/`) | `human` (framework install, not target) |
| `diffusers-workflow` (product) | implementer/core.md:1,3; tester/core.md:1,3,5,11; regression/core.md:1,24; lead/core.md:1,11; release/core.md:3 | `product` |
| `lem` | implementer/core.md:5,59,61,118,135; implementer/fix.md:22,56,74; tester/core.md:6,21,100; regression/core.md:25,47,61; lead/build.md:46,73; lead/design.md:136; RETRO.agent.md:46; bench/replay-note.md:7,13; all three target.md (≈40 lines) | `servers.primary` (and `{server}` at runtime) |
| `mcp__dw__` | tester/core.md:145; guard.py:325 (`session_called_mcp`) | `mcp_tool_prefix` (derive from `mcp_server`) |
| `dw` (server/plugin name) | implementer/fix.md:60; lead/design.md:7; lead/build.md:45; curator/review.md:44; reviewer/core.md:3,38; reviewer/docs.md:10; tester/core.md:18; regression/core.md:3; bench/replay-note.md:8 | `mcp_server`, `plugin` |
| `~/diffusers-workflow/scripts/deploy.sh develop` over `ssh lem` | implementer/fix.md:74; lead/build.md:73 | `deploy_command` (already `deploy_cmd()` in providers.sh; target.md uses `{{DEPLOY}}` but the lem prompts hard-code it) |
| `journalctl --user -u dw-serve`, `~/dw-serve.log` | implementer/fix.md:83; implementer/target.md:30 | `server_log` (per server) |
| `develop` / `master` | implementer/core.md:117,122,149,153; implementer/fix.md:16,54,59,61,62,70,74,77; implementer/triage.md:11,31; lead/build.md:66,71,73,77; lead/closeout.md:4,5,19,56; lead/design.md:64,136; lead/core.md:97; release/review.md:5; release/notes.md:6; reviewer/core.md:7; reviewer/docs.md:7; tester/core.md:20; tester/target.md:28; implementer/target.md:13,14,18,22 | `integration_branch`, `release_branch` |
| `ruff`, `pytest`, UI `npm` checks, `ui/` | implementer/core.md:151-152; lead/core.md:96; lead/build.md:43,51-52; bench/replay-note.md:17; guard.py handoff_gate | `handoff_gate` (commands), `test_command`, `lint_command` |
| `venv` | implementer/core.md:4; bench/replay-note.md:17 | `test_command` / `source_env` |
| `fix(mcp): #42 - … generate_image` | implementer/fix.md:29-30 | `commit_example` |
| `dw.events.emit_warning` / `logger.warning` | implementer/fix.md:48-49; lead/build.md:64-65 | `caller_warning_channel` |
| `GUIDES` table of `dw/server/guides.py`, `plugins/dw/`, "`docs/` page `list_guides` doesn't index" | implementer/fix.md:60,102-103; reviewer/docs.md:10-11; tester/verify.md:23-24; release/review.md:27 | `served_text_rule`, `plugin_path` |
| `docs/proposals/`, `complete/`, `declined/`, `todo.md` | implementer/fix.md:65; lead/closeout.md:13,17,48,55 | `design_docs` |
| `docs/RELEASING.md` | release/notes.md:9,12 | `release_notes_file` |
| `mcp-ticket.md` | tester/core.md:58 | `issue_template` |
| `backend:shared/cuda/mps` | implementer/core.md:53-56; implementer/fix.md:14; implementer/triage.md:13; tester/core.md:60; regression/core.md:68-69; tester/target.md:40-51; regression/target.md:14-25; implementer/target.md:37,40; guard.py:446 | `backend_labels` (+ which one a secondary server files) |
| `target:lem/local` | implementer/core.md:59; tester/core.md:62; regression/core.md:70; all target.md files; guard.py claim_rule | `claim_label_prefix` + server names (see §0) |
| `verified-on:mps` | tester/target.md:16; guard.py:421-426 | `servers.<name>.verified_on_label` |
| suite file names / levels / workspaces / prefixes | regression/core.md:8-18,57; implementer/fix.md:112-116; tester/cases.md:6-12; tester/spec.md:39-40; curator/review.md:79; regression/run-cases.md:55 | `suite_levels` table |
| `qa-` workspaces, `qa-cast/`, `common/assets` | tester/standing-task.md:12-25,76; lead/design.md:91; regression/core.md:141; tester/target.md:21; regression/target.md:73 | `fixture_namespace` (pack) |
| `qa-bible.md` | tester/core.md:15; tester/answer.md:9; tester/task.md:8; tester/standing-task.md:54,69 | `tester_memory_file` |
| `TESTER_TASK.agent.md` (legacy source string) | tester/cases.md:17; tester/standing-task.md:51 (`TESTER_TASK_EVERY` knob); 3 suite `Adding a case` | pack history; keep for grep-ability in dw only |
| `run_workflow(wait_seconds=55)`, `wait_for_job`, `delete_output(job_id=)` | tester/core.md:114-118; regression/core.md:157-161; tester/target.md:33-35; regression/target.md:59-61; implementer/target.md:49 | `mcp_efficiency_tips` |
| read-only discovery tool names | curator/review.md:44-45; reviewer/docs.md:22-23; tester/spec.md:62-63; lead/design.md:89; tester/answer.md:8; regression/run-cases.md:11-12 | `readonly_discovery_calls`, `history_calls` |
| `list_gallery(only_orphans=true)`, `delete_output(name=…)` | regression/chunk.md:21-22; regression/sweep.md:5,11 | `orphan_cleanup` |
| `create_workspace`, `delete_workspace`, `keep_output`, `upload_asset` | regression/core.md:42,137,142; tester/standing-task.md:13,22; tester/spec.md:53 | `fixture_namespace` ops |
| `SE-F001`, `S-F015`, `S-F007`, `C-F029` | regression/chunk.md:17; regression/run-cases.md:12; suite `Adding a case` ×4; tester/target.md:59 | `security_precondition_case`, `discovery_contract_case` (pack) |
| `field-report` | lead/design.md:83-84 | `demand_evidence` |
| `tests/test_mcp_server.py` | lead/design.md:106 | `inertia_examples` |
| `acknowledged_cost`, "spends GPU time" | release/review.md:18; tester/spec.md:64 | `costly_action` |
| `sonnet` / `haiku` | lead/build.md:41-42 | `worker_models` (driver knob, not target) |
| RTX 3090 / 24 GB / 64 GB / MiniMax H3 / LTX-2.5 | tester/target.md:4-5,23; regression/target.md:4,76-80 | `servers.<name>.hardware` notes (per-server pack) |
| dated anecdotes (0.4.0, 2026-09-23, #478/#479, #454, #409) | release/core.md:5-8; lead/core.md:113; tester/standing-task.md:45; tester/target.md:59; curator/review.md:111-112 | move to dw pack or drop |

Driver-side bash also bakes dw into the prompts, outside `agents/`. Example: `runtime_note`'s
regression branch (providers.sh:553-555) encodes the rule that a non-lem server has no
suite-file edit.

---

## 5. Cross-file references by section name (break if the section moves)

| From (file:line) | Reference | Target section (file) | Risk under the split |
|---|---|---|---|
| implementer/fix.md:14 | "Backend and target labels" | implementer/core.md `### Backend and target labels` | That section is per-server/pack. If it leaves core, fix and triage point at nothing on a pack that has no backends. |
| implementer/fix.md:15 | "Checks before any fix" above | implementer/core.md | core → core: safe. |
| implementer/fix.md:64 | "Park for Don" | implementer/core.md `## Dispositions…` bullet | The trigger list is pack; if it moves, the bullet name must stay in core. |
| implementer/triage.md:9 | "Filed by someone else" | implementer/core.md `## Tickets` bullet | safe (core). |
| implementer/triage.md:9-10 | "Checks before any fix" | implementer/core.md | safe. |
| implementer/triage.md:13 | "Backend and target labels" | implementer/core.md | as for fix.md:14. |
| implementer/triage.md:20,36 | "Park for Don" | implementer/core.md | as above. |
| implementer/target.md:38 | "Backend and target labels" | implementer/core.md | per-server → core. |
| implementer/core.md:61 | "your Target section" | agents/implementer/target.md | Name collision (§0). |
| bench/replay-note.md:11-13 | "Checks, Deploy and Hand off", "Reproduce", "Fix" | implementer/fix.md `###` headings | Deploy becomes mostly pack; keep the heading names in the core fragment. |
| bench/replay-note.md:22 | "Park for Don" | implementer/core.md | as above. |
| tester/core.md:90 | "Verifying a feature" | **tester/verify.md** (a fragment, not core) | A core → fragment reference, and verify.md isn't loaded in task/answer/closures/handoff/spec. A latent R10-rule violation today, independent of R13. |
| tester/handoff.md:12 | core, "The regression suites" | tester/core.md | safe. |
| tester/task.md:4 | "the Closures section above" | tester/closures.md | Depends on the load order core, closures, task. |
| tester/task.md:5 | "the standing task below" | tester/standing-task.md | Becomes pack, so the order core → closures → task → cases → **pack** standing-task must hold. |
| tester/standing-task.md:55 | "The bible" below | same file | mixed section. |
| tester/standing-task.md:102 | "the tester core still applies" | tester/core.md | pack → core: fine. |
| tester/cases.md:12, tester/spec.md:38, regression/run-cases.md:55, curator/audit.md:37 | "Where a case belongs" | regression-suite-smoke.md header (pack) | The core points at pack-owned suite text by name. The framework must require every pack's first suite file to carry that section, or move the level test into the profile's `suite_levels`. |
| tester/cases.md:19, suite headers | "Adding a case" | each suite file | Contract heading every pack suite must have. |
| tester/spec.md:51, regression/core.md:148,183, regression/sweep.md:8 | "Fixtures" section | each suite file | Contract heading. regression/core.md:183 also asserts "the header… ends with the Fixtures section", which is false for security (Fixtures, then a category intro at l.166-177, then the first `###`). |
| tester/target.md:54 | your core, "The regression suites" | tester/core.md | per-server → core. |
| regression/core.md:39 | "A boundary that didn't hold" | same file | safe. |
| regression/core.md:48,62 | "Target" section / "your Target section" | regression/target.md | Collision (§0). |
| regression/run-cases.md:4 | "(see Guardrails)" | regression/core.md `## Guardrails` | safe. |
| regression/run-cases.md:23 | "Reporting a failure" | regression/core.md | safe. |
| regression/target.md:27 | core, "Suite drift is a suite request" | regression/core.md bullet inside "Reporting a failure" | safe if that bullet stays core. |
| regression-suite-security.md:45-46 | "A boundary that didn't hold" in `agents/regression/core.md` | regression/core.md | **pack → core by file path**: breaks if agents/ moves to a framework package path. |
| suite headers (all 4) l.27-28 etc. | "Full run mechanics … live in `agents/regression/`" | directory | pack → framework path. |
| lead/build.md:31 | core, "Sessions" | lead/core.md | safe. |
| lead/build.md:110, lead/design.md:36,169 | core, "The plan comment" | lead/core.md | safe. |
| lead/decompose.md:14-15, lead/closeout.md:78 | build fragment's "Stop and re-plan" | lead/build.md (not loaded in decompose or closeout) | A fragment → other-fragment reference. The reader can't see it, and it violates the R10 rule. |
| lead/decompose.md:68 | core, "Phase markers" | lead/core.md | safe. |
| lead/decompose.md:31 | step 2's "One exception" | same file | safe. |
| curator/audit.md:8 | core, "Who decides a suite change" | curator/core.md | safe. |
| reviewer/core.md:12 | "Not yours" | reviewer/docs.md step 2 | core → fragment, but docs is the only kind: fine. |
| RETRO.agent.md:9 | "Principles" in `HARNESS-ROADMAP.md` | harness doc | framework. |

---

## 6. Rules duplicated between guard.py and the prompts ("Enforced by the harness")

These stay tied to the guard: when a guard rule becomes profile-driven, its prompt line must
come from the same source.

| Rule | guard.py | Prompt one-liners |
|---|---|---|
| no `completed` close (implementer, lead) | 470-472 | implementer/core.md:42-44,147; lead/core.md:89; release/core.md:33 |
| no `status:verified` except the tester | 474-475 (impl/lead), 468-469 (reviewer) | implementer/core.md:147; lead/core.md:90; reviewer/core.md:35-36; release/core.md:33 |
| no lifting an `owner:don` / `needs-approval` park | 476-481; curator 459-460 | implementer/core.md:148; lead/core.md:91-92; reviewer/core.md:36; release/core.md:33 |
| exactly one `owner:*` per edit | 147-155 (all but curator); curator too per curator/core.md:41 | implementer/core.md:148-149; lead/core.md:93; curator/core.md:41; reviewer/core.md:37; release/core.md:34; tester/core.md:47-48 (prose) |
| no push to `master`, no force push/mirror/delete | 216-237 (`git_push_problem`, implementer role, incl. lead build) | implementer/core.md:149-150; lead/core.md:96-97; implementer/fix.md:59; lead/build.md:71 |
| hand-off gate (clean tree, ruff, UI checks, relative pytest) | 240-320 (`handoff_gate`) | implementer/core.md:150-154; lead/core.md:95-96. **Pack values** (ruff/npm/pytest, `ui/`) are hard-wired here and in the prompt text. |
| consumer verify needs an `mcp__dw__` call; handoff kind exempt from close only | 322-327, 487-497 | tester/core.md:52-53,144-147; tester/handoff.md:24-25 |
| `status:plan-approved` is Don's | 461-463 | lead/core.md:37-38,88; lead/design.md:170-172; curator/core.md:41; reviewer/core.md:37; release/core.md:34; tester/core.md:38 |
| `release` / `release-blocker` are Don's | 464-466 | implementer/core.md:156-157; tester/core.md:149-150; lead/core.md:100-101; curator/core.md:46-47; reviewer/core.md:40-41; release/core.md:34 |
| no `security` label (use file-advisory.sh) | 450-453 | implementer/core.md:159-160; tester/core.md:152-153; lead/core.md:103-104; curator/core.md:49-50; reviewer/core.md:43-44; release/core.md:37-38; regression/core.md:39,115 |
| no release-gate marker in issue text | 334-347, 454-455 | release/core.md:35 |
| `target:` labels are the driver's; only the hand-over to lem | 367-376 (`claim_rule`) | implementer/core.md:59-62; tester/core.md:61-62; regression/core.md:70; implementer/target.md:42; tester/target.md:27,43; regression/target.md:22 |
| Mac implementer: no ssh/scp/rsync, no deploy scripts | 410-418 | implementer/target.md:7-8,17,28 |
| Mac verify adds `verified-on:mps`; `verified-on:` only off-lem | 421-426 | tester/target.md:15-17 |
| Mac consumer files only on ticket repo, except a suite request | 427-434 (`suite_request` 350-358) | tester/target.md:54-57; regression/target.md:27-29 |
| Mac: no comment on a `target:lem` issue | 435-438 | tester/target.md:43-44; regression/target.md:15; tester/target.md:25 |
| Mac new issue: exactly one `backend:mps|shared`, one owner, no `target:` | 439-447 | tester/target.md:40-43; regression/target.md:19-22 |
| Mac: suites read-only (tester excepted), perf only under `regression-perf/<server>/` | 379-392 (`target_file_rule`) | regression/target.md:42-49; tester/target.md:48-53 |

The shared "release" and "security" one-liners are pasted identically into six cores: two
paragraphs, about 250 B each. They are framework-generated text, and a port can emit them
from the guard's rule table instead of six copies.

---

## 7. Per-role totals

Bytes are from `wc -c`. "Mixed→pack est." is my per-section estimate of the part that moves
to a pack. "After split" = core + (mixed − est.) vs pack + est. "Generic %" = core after
split ÷ (total − per-server).

| role | total | core | pack | mixed | per-server | mixed→pack est. | core after split | pack after split | generic % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| implementer | 20,368 | 5,068 | 0 | 12,230 | 3,070 | 2,730 | 14,568 | 2,730 | 84% |
| tester | 30,637 | 9,461 | 3,366 | 14,391 | 3,419 | 3,450 | 20,402 | 6,816 | 75% |
| regression | 23,092 | 5,532 | 0 | 11,491 | 6,069 | 3,400 | 13,623 | 3,400 | 80% |
| lead | 28,582 | 21,487 | 0 | 7,095 | 0 | 2,420 | 26,162 | 2,420 | **92%** |
| curator | 13,482 | 10,658 | 0 | 2,824 | 0 | 650 | 12,832 | 650 | **95%** |
| reviewer | 4,654 | 2,203 | 0 | 2,451 | 0 | 300 | 4,354 | 300 | 94% |
| release | 6,095 | 4,135 | 1,297 | 663 | 0 | 350 | 4,448 | 1,647 | 73% |
| retro | 3,103 | 3,103 | 0 | 0 | 0 | 0 | 3,103 | 0 | 100% |
| bench note | 1,337 | 0 | 0 | 1,337 | 0 | 250 | 1,087 | 250 | 81% |
| suite framing (4 files) | 40,546 | 5,456 (Removing ×4) | 18,744 | 16,346 | 0 | ~8,300 | ~13,500 (of which ~10,900 is 3 paragraphs ×4) | ~27,000 | — |

(The implementer's per-server figure includes core.md's "Backend and target labels", 720 B.)

**Answer to R13's open question: do the lead and the curator need a pack?**
- **The curator doesn't.** 95% is generic. Its ~650 B of dw text is:
  - one list of read-only `dw` discovery calls (curator/review.md:44-45), which
    `{readonly_discovery_calls}` covers;
  - one worked example that cites SE-F031 and dw#409 (review.md:108-115), which should be
    rewritten neutrally;
  - the name `regression-suite-security.md` as the "always escalate" level, which becomes a
    per-level `escalate` flag in `suite_levels`.

  All three are profile values or a rewrite, not a pack file.
- **The lead doesn't need a pack file either,** but it needs more profile fields. It is 92%
  generic. The ~2.4 KB of dw is concentrated in four places:
  - design step 3 "Measure demand" (the dw user model, `field-report`, workspace counts);
  - the Inertia and cost examples in step 4;
  - the deploy command in build step 3;
  - the `docs/proposals/{complete,declined,todo.md}` layout in close-out.

  Of these, `{demand_evidence}` is the only real judgment text. It could be one optional
  pack fragment (`lead/demand.md`), or a profile paragraph that the core includes. Everything
  else is a placeholder: `{deploy_command}`, `{design_docs}`, `{caller_warning_channel}`,
  `{inertia_examples}`, `{test_command}`/`{lint_command}`.
- **Reviewer, release and retro** are likewise profile-only, except release/review.md
  `### Areas` (1.3 KB), which is wholly pack. It should be a pack file keyed by the area
  names run-release.sh passes.
- **The packs that matter** are the tester's (standing task ~4 KB, efficiency and discovery
  tips, levels, memory file) and the regression agent's (the level list, workspace rules,
  orphan cleanup, perf timing source), plus the suite files' framing, which is already
  target-owned. The implementer's pack is small (~2.7 KB) but high-stakes: deploy,
  served-text rule, warning channel, gate commands.
- **per-server** (the three `target.md` files, 11.8 KB, plus the backend/claim text in the
  cores) is a third axis. It is dw content (lem/Mac hardware, `backend:mps`, `qa-cast`
  fixtures) delivered through a framework mechanism (server notes, claim labels, guard
  rules). It belongs in the dw pack as `servers/<name>/<role>.md`, not in the framework core.
