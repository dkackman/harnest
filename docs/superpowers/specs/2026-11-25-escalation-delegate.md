# The escalation delegate: rule on Don's queue, pass through what is his (2026-11-25)

Roadmap R19. This spec builds on R15 (`2026-11-01-escalation-lanes.md`): R15 tagged every ask
with a kind and split plan reviews into lanes; this adds a role that rules on the asks for Don and
hands him only the ones he decides.

## Why

Don works his queue by asking an Opus session for a recommendation and approving it. Sometimes that
session amends the logged default first. From 2026-11-21 to 11-23 an hourly Opus session ruled
as "delegate for Don" under his delegation. This spec turns that trial into a harness role.

**The record (2026-11-25), from closed escalated issues updated since 2026-11-01:** 256 ruling
comments across dw and harnest. A keyword pass over each ruling's first line gives rough counts,
not a hand count:

- about half take the default outright ("approved at defaults", "the plan's verdict");
- about a quarter depart from it, and the departures are a short list:
  - narrowing scope ("stage A only", "step 1, then back to Don", "build smaller") — the most common, and usually what the advising session recommended;
  - deferring or parking;
  - withdrawing an approval after a failed gate;
  - taste verdicts from watching output (#1344/#1316: "Pika H3 Flex is an option, not the default");
  - releasing resources or trust (#1339's 57.8 GB re-download, `DW_EXPERIMENTAL_REFINE_WINDOWS` on lem);
  - direction ("no new scope after the long-form merge", #1230);
- the rest are operational ("deployed; to the tester", "unblocked", routing a stranded issue).

**The trial:** 16 dw rulings (#1516, #1525–#1527, #1534, #1536, #1564, #1568, #1575–#1578,
#1591, #1066, #1188) and about 15 harnest curator rulings ("via his plan-review delegate":
#271–#293). Three amended the plan ("approved with one amendment", "build smaller"). No later
comment reverses any of them. It escalated the right way at least once: on #1066 it approved
stage C and wrote "Q6 is not pre-ruled and returns to Don if C fails"; C failed and Don ruled
Q6 himself.

**The queue now:** 23 dw `owner:don` issues, of which 16 are parked deferrals, 1 is Don's own
(#1523), and about 7 are live asks; harnest has 2 (#296, #297).

## What changes

### 1. A `delegate` role and queue

- `agents/delegate/core.md` plus one `rule.md` fragment (`role_prompt` in `providers.sh`).
- `lib/classify.jq` gains the queue `delegate:rule`, which selects an open issue that has:
  - `owner:don`, with `status:needs-approval`, `status:plan-review` or `status:needs-info`;
  - no `parked` without a live ask (R15's deferred rule stands), no `release`, no
    `release-blocker` ruling, no security advisory (those aren't issues), and not the external
    queue (a third party's filing stays Don's: only a human hands one in);
  - no `delegate:passed` label (it has already been handed to Don);
  - no comment from Don's own session in the last `DELEGATE_QUIET_HOURS` (default 2), so
    the delegate never races Don while he is working an issue. Don's sessions mark their comments
    `in Don's session`; the snapshot's `markers` carries that.
- The driver runs it as a server-free session (`free`, priority after `curator`), on the
  primary server's checkout. On harnest it selects `suite` issues only (see 4).

Add boards to `tests/classify-cases.json` for each selection and exclusion.

### 2. Rule, amend, or pass through

The delegate reads the ask block (R15), the thread and the records it cites, and does one of three things:

- **Rule at the default.** It writes the ruling comment, applies the labels the default names
  and swaps the owner, as Don's session does today.
- **Amend, then rule.** It can amend a default when the record supports the amendment: scope
  narrowed, a stage cut, a gate tightened, a deferral. It names the change in a `Delegate
  changed:` line, so the lead folds it in the way it folds in `Don changed:` today.
- **Pass through.** It adds `delegate:passed`, leaves `owner:don`, and posts a short
  recommendation in the ask-block shape, so Don still gets a pre-read recommendation (how he
  works the queue now). The digest lists these under **Needs you**.

It **passes through** any ask that is one of these:

| Pass through when | R15 kind | Why it is Don's |
|---|---|---|
| A verdict on generated media no metric settles | `taste` | his eyes and ears |
| A security boundary, third-party code or a new dependency, credentials | `trust` | always his |
| New MCP, REST or workflow-syntax surface; a breaking change; a user-visible default that changes direction rather than tuning | `scope`, `default` | architecture and direction |
| GPU time over `DELEGATE_GPU_HOURS` (default 2) on one ruling, or a new download over `DELEGATE_DOWNLOAD_GB` (default 20) | `spend` | measured from #1339 and the trial's ~40 min arms |
| A weaker acceptance expectation the record doesn't settle | `loosen` | the curator's existing escalation line |
| The ruling would contradict one of Don's own earlier rulings on the issue or its parent | `record` | he ruled it; only he changes it |
| `Reversible: no` | any | can't be undone |
| The delegate's own confidence is low, or it would amend in a way Don might find controversial | any | the delegate says why in one line |

It rules on the rest: `none`, `scope` that narrows or defers, `default` tuning within an
approved design, `spend` under the thresholds, `loosen` that the record settles, `record`
that the record resolves, and operational asks (unblock, hand back, apply by hand).

### 3. `status:plan-approved`: Don or his delegate

The rule today is "only Don adds `status:plan-approved`" (`guard.py`, R11, R15). **Don's
ruling (2026-11-25): the delegate may add it.** The new rule:

- `guard_settings delegate` allows `status:plan-approved` on a dw issue only together with a
  ruling comment from the same session that starts `**Ruling` and names `delegate for Don`.
- The delegate never adds it to a plan whose ask block has a pass-through kind.
- Every other role is still refused, as today.
- `docs/harness/permissions.md`, the lead's prompt and the R15 text say "Don or his delegate".

### 4. What the delegate never rules on

- Changes to the harness itself (prompts, drivers, hooks, `classify.jq`, the guard):
  "agents propose changes to the harness; a human approves them" stands. On harnest the
  delegate rules on `suite` + `status:needs-approval` curator escalations only (as the trial
  did) and passes through `harness` issues.
- Anything that touches its own role, prompt or permissions.
- Releases, release-blockers and security advisories.

### 5. Audit and reversal

- Each ruling appends one line to `logs/delegate.jsonl`: issue, kind, verdict (`default`,
  `amended`, `passed`), model, cost.
- The daily digest gets a **Delegate rulings** section: every ruling since the last digest, one
  line each, with links.
- Don reverses a ruling by commenting `overrule: <what instead>`. The next delegate pass sees it,
  restores `owner:don` with his instruction applied by the lead, and logs an override. The
  override count by kind is the tuning signal.

## Model

Fable 5.2 (`claude-fable-5-2`, $8/$40 per MTok) at effort `high`, unless the replay below
shows Opus 5.5 (`claude-opus-5-5`, $4/$20) matches Don as often. The reasons to start there:
- this role stands in for Don's judgment, so mistakes reach builds directly;
- nearly every ask is written by an Opus lead, so a different model gives an independent read
  instead of Opus agreeing with Opus;
- the volume is small (about 10–20 rulings a day), so the price gap is small in dollars.

Pin it by exact id (`DELEGATE_MODEL`), never an alias, like the tester.

## Before it goes live: a replay

The closed rulings are a labelled set. Replay a sample through both models:
- **Input:** the issue thread up to the ask, with Don's ruling and everything after it removed.
- **Output:** the delegate's verdict (default, amended or passed) and its ruling text.
- **Scored against Don's actual ruling:**
  - agreement on the verdict;
  - pass-through recall on the asks where Don departed in a pass-through kind (the number that
    matters: a miss there is the delegate deciding something that was Don's);
  - pass-through precision (how much it still sends him).

**Sample:** every ruling where Don departed (about 60) plus 40 that took the default, stratified by
kind. The cost isn't measured yet; size it with Don before running, since every replay is billed.

## Rollout

1. The replay; pick the model, adjust the thresholds.
2. Live, with the digest section and `overrule:`. Retire the ad-hoc hourly session.
3. After two weeks, count overrides by kind. A kind with an override moves to pass-through; a
   pass-through kind Don always ruled the delegate's way is a candidate to delegate.

**Done when:** two weeks live with overrides under 5% of delegate rulings and no override in a
pass-through kind the delegate ruled on.

## Not built

- Silence as consent on the passed-through items: those stay Don's until he rules.
- The delegate ruling on harness changes (see 4).
