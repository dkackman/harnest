# Escalation lanes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ask Don only the questions that are Don's kind, batch the plan approvals that aren't, and take deferred and follow-through work out of his queue.

**Architecture:** A `parked` state in `lib/classify.jq`; a `lane:batch` label that the lead sets and the digest reads; `scripts/approve-batch.sh`, which Don runs to approve a batch; prompt rules for the kinds, the ask block, pending-case follow-through and curator dedupe.

**Tech Stack:** bash 3.2, jq, `gh`, Markdown role prompts; the offline tests in `tests/`.

**Spec:** `docs/superpowers/specs/2026-11-01-escalation-lanes.md`

## Global Constraints

- Bash 3.2: no `source <(…)`, and no apostrophe in a comment inside `<( )`.
- Only Don adds `status:plan-approved`; `guard.py` is unchanged.
- Every knob read is named in the README (`test-lint.sh`). No new knobs.
- Keep the `owner:*` / `status:*` prefixes. Add a `classify-cases.json` board for each new state.
- State each prompt rule once per role, in the core if more than one kind needs it.
- `tests/run.sh` passes before the commit.
- The loop runs from the main checkout: work on branch `escalation-lanes` in `../harnest-escalation`, and merge only while the loop is stopped.

## Review Focus

- A `parked` issue with **no** blockers must never route to a session (it would run every cycle): `wait`.
- A `parked` stage whose parent isn't building stays `wait`, even with its blockers closed (the existing parent check).
- `approve-batch.sh` given an issue that lost `lane:batch` or `status:plan-review`, or isn't `owner:don`, must refuse that issue and change nothing on it, while still approving the valid ones.
- The digest's batch issues must not also appear in the model table, or Don sees them twice.
- A release freeze still holds a parked issue's routed session at `wait` (the freeze filter comes after).

---

### Task 1: `parked` in the state machine

**Files:**
- Modify: `lib/classify.jq` (header comment; the `owner:lead` branch)
- Test: `tests/classify-cases.json` (one new board)

**Interfaces:**
- Produces: reason strings `"parked: waiting on its triggers"` (wait) and `"parked: every blocker closed, recheck the triggers"` (routed).

- [ ] **Step 1:** Add the board `"parked features and stages"` to `tests/classify-cases.json`:
  - #1: `owner:lead` + `feature` + `parked`, no blockers → `wait`
  - #2: the same with one OPEN blocker → `wait`
  - #3: the same with one CLOSED blocker → `lead:design`
  - #4: a `stage` + `parked` + `owner:lead` with a CLOSED blocker, parent #6 building (`owner:lead`, `feature`, `status:plan-approved`, markers plan v1, decomposed v1, specced v1, sub-issues 1/0) → `lead:build`
  - #5: `owner:don` + `feature` + `parked` → `don`
  - #6 → `wait`
- [ ] **Step 2:** Run `tests/run.sh classify`. Expect FAIL on #1, #2 and #3.
- [ ] **Step 3:** In the `owner:lead` branch, before `has("stage")`: when `has("parked")` and the issue has no blockers, or any blocker is OPEN → `{queue: "wait", reason: "parked: waiting on its triggers"}`. Otherwise fall through to the existing routing, with a feature or idea sent to `lead:design` (not `parent_phase`), and prefix the reason with `parked: every blocker closed, recheck the triggers`. A stage keeps its own routing.
- [ ] **Step 4:** Run `tests/run.sh classify`. Expect PASS.

### Task 2: `scripts/approve-batch.sh`

**Files:**
- Create: `scripts/approve-batch.sh`
- Test: `tests/test-approve-batch.sh`

**Interfaces:**
- `scripts/approve-batch.sh [-y] <n>...`, using `TICKET_REPO` (default `dkackman/diffusers-workflow`). Exit 0 if every issue was approved, 1 if any was refused.
- Per issue: it requires `owner:don`, `status:plan-review` and `lane:batch`, or prints `#n: not a batch plan (<labels>), skipped`. It prints `#n plan vN: <title>`, and asks one `approve these N? [y/N]` unless `-y` is given. It posts a comment starting `Approved with the batch: plan vN, its defaults.`, then runs `gh issue edit n --remove-label owner:don,status:plan-review,lane:batch --add-label owner:lead,status:plan-approved`, and appends `{"at","issue","plan","lane":"batch"}` to `logs/approvals.jsonl`.

- [ ] **Step 1:** Write `tests/test-approve-batch.sh`. Use a fake-gh board with #1 valid (plan comment `<!-- harnest:plan v3 -->`), #2 missing `lane:batch`, and #3 `owner:lead`. Run `-y 1 2 3`, then assert:
  - exit code 1;
  - #1's labels are `lane`-free, with `owner:lead,status:plan-approved`;
  - #1 has the comment, naming `plan v3`;
  - #2 and #3 are unchanged, and the output says `skipped` twice;
  - `approvals.jsonl` has 1 line.
- [ ] **Step 2:** Run `tests/run.sh approve-batch`. Expect FAIL (no script).
- [ ] **Step 3:** Implement the script in the style of `scripts/file-advisory.sh`.
- [ ] **Step 4:** Run `tests/run.sh approve-batch`. Expect PASS.

### Task 3: digest sections

**Files:**
- Modify: `run-digest.sh`
- Test: `tests/test-drivers.sh` (after 9a)

- [ ] **Step 1:** Add test 9a2. The board has #10 `owner:don`, `feature`, `status:plan-review` and `lane:batch`, with a plan comment holding `**Q1** [none] ... default: x`. #11 is `owner:don`, `feature` and `parked`. #12 is `owner:don` + `status:needs-approval`. Assert the output:
  - has `## Batch: plans with no question for you`;
  - has `scripts/approve-batch.sh 10`;
  - has `**Q1** [none]`;
  - has `## Deferred: waiting on a trigger, not on you` with `#11`;
  - has no `| #10 |` and no `| #11 |` table row.
- [ ] **Step 2:** Run it. Expect FAIL.
- [ ] **Step 3:** In `run-digest.sh`, split the `don` rows by label:
  - `lane:batch` + `status:plan-review` go to `batch_section`. That is no model call: the title, `plan vN`, the plan's verdict line (the first line matching `Verdict`), and every line matching `\*\*Q[0-9]+\*\*`, each cut to 160 chars.
  - `parked` goes to `deferred_section`, as `- #n (d days): title`.
  - The rest go to the table as today. The parked-count line counts all three.
- [ ] **Step 4:** Run `tests/run.sh drivers`. Expect PASS.

### Task 4: role prompts

**Files:**
- Modify: `agents/lead/core.md`, `agents/lead/design.md`, `agents/lead/build.md`, `agents/implementer/core.md`, `agents/implementer/triage.md`, `agents/curator/core.md`, `agents/curator/review.md`, `agents/tester/core.md`

- [ ] **Step 1:** Write the kinds table and the ask block (spec, "The decision kinds" and change 1) once in each of the four cores, as a section "Asking Don". It gets one line per kind; the implementer, curator and tester cores carry only what their parks need, and point at the lead's table for the full set.
- [ ] **Step 2:** Changes to `design.md`:
  - Step 6: tag each Q `[kind]`, end the plan with the ask block, and add `lane:batch` to the hand-off when the batch-lane test holds.
  - Step 1:
    - "Don deferred it" becomes the `parked` + blockers flow.
    - A new turn, "A parked feature whose blockers closed": met → remove `parked` and go on; not met → hand to `owner:don`, keeping `parked`.
    - "Don answered" requires the `Don changed:` line.
    - A batch approval is an approval.
- [ ] **Step 3:** Changes to `build.md`: a parked stage whose blockers closed rechecks its gate. Met → remove `parked` and build; not met → comment and hand to `owner:don`, keeping `parked`.
- [ ] **Step 4:** Changes to `curator/review.md` and `curator/core.md`:
  - the pending-follows-plan approvable kind, exempt from the 3-case cap, with the mandatory `pending:` grep;
  - the dedupe step before escalating;
  - **Kind** added to the escalated item's bullets.
- [ ] **Step 5:** Run `tests/run.sh lint`. Expect PASS.

### Task 5: docs, roadmap, full suite, commit

**Files:**
- Modify: `README.md` ("The ticket protocol", "Your moves", "Curation…"), `docs/harness/ticket-protocol.md`, `docs/harness/components.md`, `docs/harness/tests.md`, `HARNESS-ROADMAP.md` (status row R15 plus a section)

- [ ] **Step 1:** Add these rows to "Your moves":
  - Approve a batch: run the digest's `scripts/approve-batch.sh` line.
  - Defer one: comment the triggers and swap to `owner:lead`; the lead parks it.
  - Bring a parked issue back: remove `parked`.

  Add `lane:batch` and `parked` to the protocol bullets.
- [ ] **Step 2:** Run `tests/run.sh`. Expect `all test files passed`.
- [ ] **Step 3:** Commit on `escalation-lanes`.
