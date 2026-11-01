# Escalation lanes: ask Don only what Don decides (2026-11-01)

Roadmap R15. This spec says why Don's queue changes and what changes. The implementation plan is
`docs/superpowers/plans/2026-11-01-escalation-lanes.md`.

## Why

Don asked whether the protocol had become too bureaucratic. He said he was approving a lot of
escalations with their defaults, and he wanted to stay in the loop on the calls he actually
makes. Every hand-off to `owner:don` on both repos was pulled: 342 since September, and the 99
since 2026-10-13 were read by hand.

| What reached Don (since 10-13) | How he ruled | Verdict |
|---|---|---|
| Plan reviews | Of about 17 rulings since 10-26, 13 took the defaults ("approve defaults"; #1091–#1095 approved by an interactive session "unless controversial"). 4 changed something. | mostly a formality |
| Curator escalations (~30) | He changed about 12: #120 ruled a bug, #127 caught wording that would pass a false claim, #155/#156 widened retirements, #157 kept a finding | worth it |
| …of which: `pending:` cases following a plan he'd already approved (13) | "Approved, exactly as the curator's review states them" (#159, #160, #164, #165) | a second approval of one decision |
| Deferred features | All 11 open dw `owner:don` issues carry `parked`. They wait on triggers, and Don checks those triggers himself (#1033) | the wrong queue |
| Implementer parks, triage escalations, listening and visual verdicts | Real choices between options, or Don's own eyes and ears | keep |

Every ruling where Don departed from the agent's default was one of these kinds: taste,
a default a user sees, spend, a trust boundary, a loosened expectation, scope, or a record the agent got
wrong. None of the defaults he accepted was. Those were about names, files, helpers, test shape,
and following through on an earlier ruling.

What is not bureaucratic and stays as it is:
- the single owner baton;
- `lib/classify.jq` as the one state machine;
- the tester/implementer asymmetry;
- the feature cost (a one-stage plugin feature: 6 sessions, about $9);
- curator escalations for loosening, security and ambiguous evidence;
- implementer engine/syntax parks.

## The decision kinds

Every question an agent puts to Don carries one kind. The first seven are Don's to decide:

| Kind | It is this kind when… | Example |
|---|---|---|
| `taste` | the answer is a perception: a listening or visual verdict | #1096 stems, #1047 A/B |
| `default` | a default or behaviour that a user of dw sees changes | #1058 Q3, the default TTS model |
| `spend` | lem GPU time beyond verifying the stages (a probe or A/B over ~30 min), a new model download, or a recurring cost | #1043's zero-build pre-gate |
| `trust` | a security boundary, third-party code or a new dependency, credentials | #1124 Q1, running upstream code |
| `loosen` | an acceptance intent or a suite expectation gets weaker, including a re-plan after a failed verify | #120, #127, #157 |
| `scope` | build or not, cut or add stages, new MCP/REST/workflow-syntax surface, a breaking change | #548's scope, #1122 "build smaller" |
| `record` | the record conflicts, or the agent couldn't settle a fact it needed | #154 (#1069 was already closed) |
| `none` | internal shape: names, files, helpers, test layout, or following through on an earlier ruling | most of the defaults Don took |

## What changes

1. **One ask block.** Every comment that hands an issue to Don ends with:

       **Decision for Don:** <one line>
       **Kind:** <kind>   **Default:** <what happens if Don just approves>
       **If otherwise:** <what changes>   **Reversible:** yes | no | with a breaking-change

   A plan tags each `**Qn**` with `[kind]` instead, and ends with one ask block for the whole plan.
   Driver-written parks (no-progress, bounce, external) keep their own fixed text.

2. **Two lanes for plan reviews.** A plan goes in the **batch lane** only when every question is
   `[none]`, its verdict is build or build smaller, and it names no new MCP tool or parameter, REST
   route, workflow syntax, breaking change, dependency or download. The lead then adds `lane:batch`
   in the same command that hands the plan to Don. Any other plan blocks, as today.
   - The digest lists batch plans in a section of their own, and leaves them out of the table. Each
     row shows the title, the plan version, the verdict line and each Q with its default. The section
     ends with one command: `scripts/approve-batch.sh <n> <n> ...`.
   - **Don still approves every plan.** The script runs in his shell, as him. It re-checks each
     issue's labels, prints what it will approve, and asks once. Then it posts "Approved with the
     batch: plan vN, its defaults" and swaps the issue to `owner:lead` + `status:plan-approved`. No
     agent ever adds `status:plan-approved`.
   - To look closer at one plan, Don leaves it out of the batch and rules on it as before. The lead
     treats a batch approval like any other approval.
   - Silence as consent (the driver approving after a hold) is **not** built. It is a later step,
     taken only if the batch lane's override rate stays near zero.

3. **`pending:` cases follow the approved plan.** The curator may approve and apply an amendment or
   retirement of a `pending: #N` case when all of these hold:
   - the case still says `pending:`;
   - stage #N's parent feature carries `status:plan-approved`;
   - the edit matches the current plan version's text.

   The 3-case cap doesn't apply to this kind. The curator must `Grep` every `pending: #N` for the
   affected stages and include the ones the request missed. That gap is what Don's widening on
   #155 and #156 closed. If the edit is weaker than the plan text, it is `loosen`, and it escalates.

4. **`parked` is a state.** `parked` + `owner:lead` means waiting on triggers. `classify.jq` holds it
   at `wait` while it has no blockers or any blocker is open. Once every blocker is closed, it goes
   to `lead:design` (a feature or idea) or `lead:build` (a stage), and that session rechecks the
   triggers.
   - When Don defers a feature, the lead comments the triggers, links each trigger that is an
     issue with `gh issue edit --add-blocked-by`, adds `parked`, and keeps `owner:lead`.
   - If no trigger is an issue, nothing could wake it, so it goes to `owner:don` + `parked` as
     today. The digest lists those in a "Deferred" section of their own, apart from what's waiting
     on Don.
   - Don brings a parked issue back by removing `parked`.

5. **The curator rules on duplicates together.** Before escalating, the curator searches the open
   `suite` requests for the same case IDs and rules on all of them in one comment. It closes the
   others as `duplicate of #N`. 10 of Don's suite rulings were "superseded by" or "covered by".

6. **Record the rulings, so the lanes can be tuned.** `approve-batch.sh` appends one JSON line per
   approval to `logs/approvals.jsonl`. When a design session folds in Don's answers, its "changed
   since" comment carries a line `Don changed: <Qn [kind], ...>` or `Don changed: nothing`. After two
   weeks, count overrides by kind and lane, and move a kind between lanes if the data says so.

## Invariants kept

- Only Don adds `status:plan-approved`. `approve-batch.sh` runs as Don, outside every agent's
  session, and `guard.py` still refuses the label from every role.
- The owner label is the only signal. `parked` holds an issue at `wait` and never hands it to
  another owner.
- Suite cases stay add-only for every graduated case. Change 3 only covers cases that still say
  `pending:`, whose stage hasn't shipped, and only to match a plan Don approved.

## Go-live

- Create the `lane:batch` label on `dkackman/diffusers-workflow`.
- Land the branch only while the loop is stopped (bash resumes a running driver at its old offset).
- Optionally, move the existing `owner:don` + `parked` issues whose triggers are issues to
  `owner:lead` + `parked`, with blockers. That is a hand-run relabel Don approves.
