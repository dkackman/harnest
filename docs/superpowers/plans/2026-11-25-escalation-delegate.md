# Escalation delegate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A role that rules on Don's `owner:don` asks (at the default, amended, or passed through to him), chosen and tuned against his own closed rulings before it goes live.

**Architecture:**
- **Phase 1:** an offline replay over closed rulings (`scripts/delegate-replay.py`), read-only and capped at $100. It stops at a Don decision.
- **Phase 2:** the role (`agents/delegate/`), a `delegate:rule` queue in `lib/classify.jq`, a scheduler entry, the guard change for `status:plan-approved`, `logs/delegate.jsonl`, a digest section, and `overrule:`.

**Tech Stack:** Python 3 stdlib (`harness/`), jq, bash 3.2, `gh`, `claude -p`, Markdown role prompts; the offline tests in `tests/`.

**Spec:** `docs/superpowers/specs/2026-11-25-escalation-delegate.md` (roadmap R19).

## Global Constraints

- Bash 3.2: no `source <(…)`, and no apostrophe in a comment inside `<( )`.
- Every knob read is named in the README (`test-lint.sh`). New knobs:
  - `DELEGATE_MODEL`;
  - `DELEGATE_EFFORT`;
  - `DELEGATE_QUIET_HOURS` (2);
  - `DELEGATE_GPU_HOURS` (2);
  - `DELEGATE_DOWNLOAD_GB` (20);
  - `DELEGATE_REPLAY_BUDGET_USD` (100);
  - `DELEGATE_IN_LOOP` (0 until phase 2's last task).
- `lib/classify.jq` is the state machine: the queue is added there, with a `classify-cases.json` board for each selection and exclusion.
- Keep the `owner:*` / `status:*` prefixes.
- No `--dangerously-skip-permissions`: the delegate's allowlist goes in `providers.sh`.
- State each prompt rule once. A rule enforced by `guard.py` gets a one-line pointer in the core.
- `tests/run.sh` passes before each commit that touches a driver, `providers.sh`, `classify.jq` or the guard.
- The loop runs from the main checkout and its Python driver is loaded at start. Work on branch `r19-delegate` in `../harnest-delegate`, merge with the loop stopped or restart it after.

## Review Focus

- **Answer-key leakage:** a replay case must contain nothing written at or after Don's ruling: no later comments, no labels from after it, and a dw tree no newer than the ask.
- **The trial delegate's rulings are not ground truth:** they are excluded from the replay sample.
- **The guard:**
  - the delegate adds `status:plan-approved` only in the same session as its `**Ruling … delegate for Don` comment on that issue;
  - every other role is still refused;
  - no route lets the delegate approve a plan with a pass-through kind in its ask block.
- **Never in the queue:** parked deferrals, release issues, external filings, harnest `harness` issues, issues labelled `delegate:passed`, and issues Don's session commented on within `DELEGATE_QUIET_HOURS`.
- **`overrule:`** must restore `owner:don`'s decision and log an override, never loop the issue back to the delegate.

---

## Phase 1: the replay pilot (≤ $100)

### Task 1: Build the case set

**Files:**
- Create: `scripts/delegate-replay.py` (subcommand `cases`);
- Create: `logs/delegate-replay/cases/<repo>-<n>-<k>.json`;
- Create: `logs/delegate-replay/key.json`;
- Test: `tests/py/test_delegate_replay.py`.

- [ ] Pull closed issues on both repos updated since 2026-10-15 (`gh issue list --state closed --json number,title,labels,body,comments`).
- [ ] Find ruling comments: the first line starts `**Ruling`, `Ruling`, `Don's ruling`, `Don approved` or `Approved`. Drop any that name `delegate` or `delegation`.
- [ ] For each ruling, build the case:
  - the issue body;
  - every comment before the ruling;
  - the labels as of the ask, rebuilt from the `LabeledEvent`/`UnlabeledEvent` timeline before the ruling (`gh api graphql`);
  - the dw `develop` commit as of the ask (`git rev-list -1 --before=<ask time> origin/develop`).
- [ ] Hand-label the pilot's 20 cases in `key.json`:
  - `verdict` (`default`, `amended`, `declined`, `deferred`, `operational`);
  - `kind` (R15);
  - `pass_through_expected` (true when Don departed in a pass-through kind of the spec's table, or the ask was taste/trust);
  - a one-line summary of what Don ruled.

  Pick 12 departures and 8 defaults, spread over kinds and both repos. The keyword pass is too rough for this; a person (the implementing session, then Don) checks each label.
- [ ] Unit tests (pure functions):
  - the cut drops the ruling and everything after it;
  - delegate rulings are excluded;
  - the label rebuild matches a fixture timeline.
- [ ] Commit `delegate: replay case builder (R19 phase 1)`.

### Task 2: The draft delegate prompt

**Files:** Create: `agents/delegate/core.md`, `agents/delegate/rule.md`.

- [ ] Write the core from the spec's sections 2–4:
  - the three outcomes;
  - the pass-through table;
  - what it never rules on;
  - the ruling comment shape (`**Ruling (delegate for Don, <date>): …**`, a `Delegate changed:` line when it amends, or the pass-through recommendation in the R15 ask-block shape).
- [ ] `rule.md` covers the live session. For the replay the script appends one instruction: answer with a JSON object `{verdict, kinds, pass_through, reason, ruling_text}` and touch nothing.
- [ ] One prompt serves the replay and live, so phase 1 tests what phase 2 ships.

### Task 3: Run the pilot

**Files:**
- Modify: `scripts/delegate-replay.py` (subcommand `run`);
- Create: `logs/delegate-replay/runs/<model>/<case>.json`.

- [ ] For each case and each model (`claude-fable-5-2`, then `claude-opus-5-5`, effort `high`):
  - check out the dw tree at the case's commit (`git worktree add --detach`);
  - run `claude -p` with the delegate prompt, the case as the user message, and read-only tools only (`Read`, `Glob`, `Grep` in that tree; no `gh`, no `Bash`);
  - record the JSON answer and the session's `usage:` cost.
- [ ] Keep a running total. Stop before a session that would take it past `DELEGATE_REPLAY_BUDGET_USD`; the projection uses the median cost so far. Alternate models case by case, so a stop leaves both models with the same cases.
- [ ] Commit the script change (not the logs).

### Task 4: Score and report

**Files:**
- Modify: `scripts/delegate-replay.py` (subcommand `score`);
- Create: `docs/superpowers/specs/2026-11-25-escalation-delegate-pilot.md`.

- [ ] Per model, report:
  - verdict agreement with Don;
  - pass-through recall on `pass_through_expected` cases (the headline: each miss is a call that was Don's);
  - pass-through precision;
  - median and p90 cost per ruling;
  - projected daily cost at 10–15 rulings.
- [ ] List every disagreement with the case, Don's ruling and the delegate's, so Don can judge whether it was wrong or only different.
- [ ] **Stop here. Don decides:** which model; whether to run the remaining ~80 cases; any change to the thresholds or the pass-through table.

---

## Phase 2: the live role (after Don's decision)

### Task 5: The queue in `classify.jq`

**Files:** Modify: `lib/classify.jq`, `tests/classify-cases.json`, `tests/test-classify.sh` if new fields are needed.

- [ ] `owner:don` with `status:needs-approval|plan-review|needs-info` → `delegate:rule`, unless one of these applies; each gets its own board:
  - `parked` with no live ask (stays `don`, deferred);
  - `release` / `release-blocker`;
  - the external queue;
  - `delegate:passed`;
  - a `<!-- harnest:don-session -->` marker within `DELEGATE_QUIET_HOURS`. The snapshot gives the marker's time; Don's sessions write the marker, so add it to their comment helper.
  - on the harnest snapshot, anything but `suite` + `status:needs-approval`.
- [ ] The `don` queue keeps the passed-through and excluded issues, so the digest and dashboard are unchanged for them.

### Task 6: Prompt map, permissions and scheduler

**Files:**
- Modify: `providers.sh` (`role_prompt` map; a new `DELEGATE_PERMISSION_FLAGS`: `gh issue view/comment/edit` on the two repos, `Read`/`Glob`/`Grep` on the lead tree, read-only `git`);
- Modify: `harness/scheduler.py` (`delegate:rule` in `PRIORITY` after `curator`, needs `free`);
- Modify: `harness/board.py` (`SHARED`);
- Modify: `lib/run-item.sh` (the session kind);
- Modify: `harness/drivers/loop.py` (offer it only when `DELEGATE_IN_LOOP=1`);
- Tests: `tests/py/test_board.py`, `test_loop.py`, `tests/test-providers.sh`.

### Task 7: The guard

**Files:** Modify: `agent-settings/hooks/guard.py`, `tests/test-guard.sh`, `docs/harness/permissions.md`.

- [ ] Add `guard_settings delegate`. In that role, allow adding `status:plan-approved` on a dw issue only when this session has already posted a comment on the same issue whose first line starts `**Ruling` and contains `delegate for Don`. Track it in the session's guard state, as the hand-off gate does.
- [ ] Refuse it when that ruling comment carries a pass-through kind. The delegate's ruling names its kinds on a `Kinds:` line; the guard reads that line.
- [ ] Every other role: unchanged refusal. Update the refusal text to "Don's or his delegate's to add".
- [ ] The delegate can't edit files under `agents/`, `agent-settings/`, `lib/` or `harness/` in either repo. Its allowlist already gives it no write tool there; the guard refuses it too.
- [ ] Tests:
  - the allowed sequence;
  - adding the label before the comment;
  - a comment on another issue;
  - a pass-through kind;
  - every other role refused;
  - the existing bypass cases from R16 (quote splitting, heredocs) run against the new allowance.

### Task 8: Audit, digest and `overrule:`

**Files:**
- Modify: `harness/drivers/loop.py` (append to `logs/delegate.jsonl` on a delegate session's end, from its ruling comment);
- Modify: `run-digest.sh` (a **Delegate rulings** section);
- Modify: `lib/classify.jq` (an `overrule:` comment by the owner after a delegate ruling → back to `don` with reason `overruled`, and never `delegate:rule` again for that issue);
- Modify: `agents/lead/core.md` (fold a `Delegate changed:` line like `Don changed:`);
- Tests: `tests/test-drivers.sh`, `tests/classify-cases.json`.

### Task 9: Docs, then switch it on

- [ ] Update the docs:
  - README: every new knob, and "Your moves" gains `overrule:`;
  - `docs/harness/ticket-protocol.md`: the delegate in the status flow;
  - `docs/harness/components.md`;
  - the R15 and R19 roadmap rows.
- [ ] Run `tests/run.sh` in full. Merge, restart the loop with `DELEGATE_IN_LOOP=1`.
- [ ] Retire the ad-hoc hourly session.
- [ ] Two weeks on: count overrides by kind from `logs/delegate.jsonl` against the spec's done-when, and move kinds between ruled and passed-through on that evidence.
