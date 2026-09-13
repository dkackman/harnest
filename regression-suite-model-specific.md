# Regression suite — dw MCP server — model-specific level

Niche checks tied to a particular model, pipeline, or LoRA/adapter quirk —
not general-purpose behavior any model could hit (see
[`regression-suite-smoke.md`](regression-suite-smoke.md) for the exact line
between general-purpose and niche). Opt-in only: `./run-regression.sh
model-specific` (or `all`, which also runs the other three files). Expect
these to be slower and more expensive — a model load, a specific
checkpoint, a particular sampler/scheduler combination — which is exactly
why they're kept out of the default cadence.

Workspace: `regression-model-specific` — kept separate from the other
levels' workspaces so a model-heavy run never skews their timings or
clutters their fixtures. Case IDs in this file use the `M-` prefix
(`M-F001`, `M-P001`, ...) so they never collide with the `S-`/`C-`/`SE-` IDs in
the sibling suites — the regression agent's duplicate-issue search is keyed
on the full prefixed ID. Full run mechanics (fixtures vs. outputs, cleanup,
the final sweep) live in `agents/REGRESSION_AGENT.md`, not here.

Maintained by the regression agent, run via `run-regression.sh`, and grown
by the implementer/tester too (see "Adding a case" below). Each case is
intent + expected result, not a pinned tool/param name — confirm the exact
call shape against the live tool schema each run, since the server evolves.
This file only ever grows with new cases and fixtures; it holds the durable
test, never a log of runs. A case that passes gets no edit — status for a
failure lives on the GitHub Issue it produced, and a measurement — a `-P`
case's timing, or anything a case's `metrics:` line names — lives in
`regression-perf/<case>.jsonl` (see `regression-perf/README.md`); neither is
a note appended here (`last run:` lines already in this file predate that
policy and are kept as history, not a model to continue). No agent may delete, weaken, or rewrite
an existing case, including one it thinks has become too expensive or not
worth what it costs — see "Removing a case" below.

## Adding a case

The implementer and the tester both grow these suites, not just the
regression agent — see `regression-suite-smoke.md`'s "Where a case
belongs" for which file. Use the existing case format (intent + `expected:`
+ `cleanup:`, plus `metrics:` when a number the case yields — a size, a count
— matters as a trend and should be logged in `regression-perf/`; seed that
file with the reading you just took, and do the same for a new `M-P` case's
timing), the next unused `M-Fnnn`/`M-Pnnn` ID, and a `source:` line
naming who added it and why (e.g. `source: implementer, fix for #42` or
`source: tester, found while running TESTER_TASK.md`). Name the
model/pipeline/checkpoint the case depends on explicitly in its body — a
model-specific case that doesn't say which model it needs is useless to a
future run. No separate approval step — the regression agent already grows
these files unsupervised when it notices gaps; a case either of you adds is
the same kind of edit.

## Removing a case

None of the three agents may remove or rewrite an existing case on their
own judgment. If a case looks too expensive, too flaky against things
outside the server's control, or no longer meaningful, propose dropping or
changing it with a GitHub Issue naming the case id and the reasoning,
labeled `owner:don` + `status:needs-approval` — the regression agent and
tester file this directly; the implementer uses its usual needs-approval
path (it has no suite files checked out to edit anyway). Leave the case
exactly as written until a human acts on it.

## Fixtures

Durable contents of `regression-model-specific` that persist across runs.
Add a line when a case starts relying on one; remove the line (and the
fixture) when nothing uses it anymore.

- (none yet)

## Functional

### M-F001 — an H3 shot takes its cast from files, not only from a previous step
`templates/minimax/dialogue-short` is the recurring-cast template, and the only way to keep a cast
across episodes is for a shot's `references` to name **files** rather than the run's own
`draw_character_*` steps. That the image references accept `from_file` (the way the voice
references visibly do) is undocumented — so it is exactly the kind of capability that could be
removed by a refactor with nobody noticing until a series stops matching itself.
Free form (run this one every pass): `validate_workflow(name="templates/minimax/dialogue-short",
arguments=...)` with a two-entry `shots` list whose every reference is
`{"reference_type": "…MiniMaxH3ImageReference" | "…MiniMaxH3AudioReference",
"from_file": "asset:<a portrait / a voice wav in this workspace>"}` and **no**
`from_previous_result` anywhere.
expected: `valid: true`, `checked_arguments` includes `shots`, `plan.list_entries.shots: 2`, and
`plan.estimate.basis: "derived"` with a `minutes` re-priced for two entries rather than the
catalog's five-shot figure. An `asset:` that names nothing must still come back as an error at the
shot's reference path — the check being exercised is that a file reference is *resolved*, not that
validation waves it through.
Paid form (opt-in, ~15 min on an RTX 3090, run it when the template or the H3 pipeline changed):
actually run it. The job succeeds; the concatenated `episode` output is stereo at the shots' own
sample rate with the expected frame count (2 x `num_frames`), and each shot visibly carries the
referenced cast.
It becomes a **finding** if the free form stops validating, or if the run fails on a reference the
validator accepted.
Also assert, from 2026-09-13: `get_workflow("templates/minimax/dialogue-short")`'s **description**
mentions `from_file` with an `asset:` path for a subject reference, *and* says the two Z-Image steps
still run and their portraits are discarded. The capability being documented is half of what #109
bought; a refactor that keeps the behaviour but drops the sentence puts the next reader back where
this case started, which is why the text is asserted and not just the behaviour. The `dw:minimax-h3`
skill carries the same thing in its `shots` entry description.
Record rather than assert, until **#122** is decided (it is `status:needs-approval`, parked with
Don; #109 itself is closed): the manifest still contains `draw_character_a`/`draw_character_b`
entries whose portraits nothing references (~55 s of Z-Image per run). **If #122 is approved this
case changes** — those manifest entries should disappear and a run warning should name each elided
step. Read that as the approved change, not as a regression.
cleanup: the free form writes nothing. For the paid form, delete the run's outputs; keep no
fixtures beyond the portrait/voice assets the case needs, which belong in Fixtures if this becomes
a regular run.
source: tester, found while running TESTER_TASK.md on 2026-09-13 (episode 7, job `48000580aec1`,
894.1 s against a 16.8 min `derived` quote, two shots, every reference `from_file`), filed as #109.
Model `opus` via provider `anthropic`.
last run: (not yet run by the regression agent — first observed 2026-09-13 on 0.4.0-beta.3.)

2026-09-13 later, paid form, PASS (opus/anthropic) — episode 8, job `2df5f1ff06f2`, **756 s**
against the same 16.8 min `derived` quote, two shots, every reference `from_file`
(`asset:qa-cast/priya-portrait.jpg`, `asset:qa-cast/hal-portrait.jpg`, and the two voice wavs).
`final/…episode.4-0.0.mp4`: 10.35 s, 248 frames (2 x 124), 24 fps, 960x544, 32 kHz stereo, peak
−2.6 dBFS, mean −23.2 dBFS. No job warnings. Both `draw_character_*` entries present in the
manifest under `intermediate/` and unreferenced, as recorded above. The documentation assertion
passes on both surfaces.

### M-F002 — H3 reports one fewer denoise step than `num_inference_steps`, and that is correct
The MiniMaxH3 scheduler counts sigma **grid points**, terminal zero included: the grid is
`linspace(1, 0, num_inference_steps)` with consecutive duplicates collapsed, and it drives
`num_inference_steps - 1` model evaluations, exposed as `timesteps = 1 - sigmas[:-1]`. H3's denoise
block sizes its progress bar on `len(timesteps)` and dw reports that verbatim. So a requested 9
reports 8 and a requested 20 reports 19.
This case exists to record **expected behaviour with its reason**, so the next tester finds the
explanation before they find the anomaly. It was filed as a suspected dropped step or off-by-one
(#110) and cost a cycle to resolve.
expected: run any H3 template with `num_inference_steps: 9` (or leave `dialogue-short`'s default)
and poll `wait_for_job` → `progress.denoise_total_steps == 8`, with `denoise_step` reaching 8
before `phase: "decoding"`. With `num_inference_steps: 20` → `denoise_total_steps == 19`. In a
`for_each` shot step every member reports the same total.
It is a **finding** if the offset is anything other than exactly one, if it varies between members
of one run, or — the hypothesis that was ruled out and is the one with a real consequence — if
`denoise_total_steps` **stops tracking** `num_inference_steps` and pins at 8 regardless. That last
would mean the 8-step turbo LoRA is fixing the schedule and a caller raising the step count to buy
quality is paying for nothing. It is not happening today: 20 → 19 is what rules it out.
`denoise_total_steps` is the correct denominator for pacing a run; `num_inference_steps` is not
the step count.
Documented on the consumer surface in `wait_for_job`'s tool description and in the `dw:minimax-h3`
skill's hard-rules block, and pinned server-side by
`tests/test_plugin_skills.py::TestMiniMaxH3Skill::test_the_denoise_step_count_is_the_scheduler_s`.
Assert the skill sentence too — the two are indistinguishable from outside, so the documentation
going quietly wrong is the failure mode this case guards.
cleanup: none beyond the host run's own (this rides along on any H3 run; do not spend a run on it
alone).
source: tester, verified in #110 on 2026-09-13 over MCP as model `opus` via provider `anthropic` —
job `2df5f1ff06f2` (`dialogue-short`, `num_inference_steps: 9`, workspace `qa-ep8`), both
`shot@padlock` and `shot@key` reporting `denoise_total_steps: 8`. The 20 → 19 leg is from the
earlier ep6 `ref2va` run recorded in #110, not re-run here.

## Performance
