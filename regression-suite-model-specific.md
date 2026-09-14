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
a note appended here. No agent may delete, weaken, or rewrite
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
metrics: paid form only — the job's `started_at`→`finished_at` in seconds (`latency`,
`condition: paid`, two shots), logged to `regression-perf/M-F001.jsonl` and compared against the
`derived` quote it was given as well as its own history. A run that drifts well past its quote is
a finding even if it succeeds — the quote is what a caller budgets on.
cleanup: the free form writes nothing. For the paid form, delete the run's outputs; keep no
fixtures beyond the portrait/voice assets the case needs, which belong in Fixtures if this becomes
a regular run.
source: tester, found while running TESTER_TASK.md on 2026-09-13 (episode 7, job `48000580aec1`,
894.1 s against a 16.8 min `derived` quote, two shots, every reference `from_file`), filed as #109;
paid form re-run the same day as episode 8, job `2df5f1ff06f2`, 756 s. Model `opus` via provider
`anthropic`.

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

### M-F003 — every H3 template's step count matches whether it carries the turbo LoRA
The `lightx2v/Minimax-h3-Turbo` LoRA (`minimax_h3_fl2v_turbo_8step_v1.0_bf16.safetensors`) is
distilled against the **base** MiniMax-H3 transformer, so it is only valid where that transformer is
loaded. The six templates that condition on references alone load the *reference* transformer and
therefore carry no LoRA and run 20 steps; the five that keep the turbo LoRA run 9. All eleven render
at 960x544. This pairing — LoRA, step count, resolution — is a three-way invariant stated in the
`dw:minimax-h3` skill's hard rules ("change one, change all three"), and it is the kind of thing a
template edit breaks silently: a turbo LoRA left on a 20-step reference template, or a reference
template quietly dropped to 9 steps, produces a job that *runs* and delivers visibly worse video for
full price. Nothing else in the suite checks it, and it is free to check.
Free (run this one every pass): `get_workflow(name=..., variables_only=true)` on each of the eleven
`templates/minimax/*` H3 templates and compare `num_inference_steps`, `width`/`height` and the
presence of the `lora_*` variables.
expected:
- **No LoRA, `num_inference_steps: 20`** — `reference-to-video`, `composable-references`,
  `voice-timbre-reference`, `generated-subject-reference`, `chain-matched-to-audio`,
  `chain-video-continuity`. No `lora_model_name` / `lora_weight_name` / `lora_adapter_name` /
  `lora_scale` variable on any of them.
- **Turbo LoRA, `num_inference_steps: 9`** — `video-with-audio`, `storyboard`, `dialogue-short`,
  `music-video`, `chain-matched-and-aligned`.
- `width: 960`, `height: 544` on all eleven.
Note the one asymmetry, so a future run doesn't read it as a failure: `chain-matched-and-aligned`
exposes only `lora_scale` as a variable (1.0) — its LoRA model/weight/adapter names are inline in the
step rather than variables. The other four turbo templates expose all four `lora_*` variables. A
template moving a name between inline and variable is not a finding; a step count that stops matching
the LoRA's presence is.
It is a **finding** if any template's step count and LoRA presence stop agreeing (20 with a LoRA, 9
without), if a template changes canvas away from 960x544 without the step/LoRA pair changing with it,
or if the `dw:minimax-h3` skill's hard-rules block stops naming the same split — the skill is how a
caller learns which number to quote, and the split going quietly stale there is as bad as the
templates going wrong.
cleanup: none — reads only, writes nothing.
source: regression agent, model `opus` via provider `anthropic`, found while running M-F001 on
2026-09-13 (server 0.4.0-beta.3). All eleven templates matched the expectation above on that pass.

### M-F004 — `validate_workflow` enforces H3's Ref2VA reference limits before the checkpoint loads
MiniMax-H3's Ref2VA workflow refuses four reference-set shapes — more than 9 images, more than 3
videos, more than 3 audio clips, more than 12 references total, and an audio reference with no image
or video beside it. diffusers enforces them inside the pipeline, i.e. after the H3 checkpoint is up,
so before #136 the free `validate_workflow` call said `valid: true` and quoted 8.4 minutes for a
shot that could only ever fail minutes into a paid run. The engine now checks the same rules at
validation, reading the ceilings off the diffusers block's own constructor defaults rather than
writing numbers into engine code — which is why this case asserts the *shape* of each answer and the
family name in the message, not a specific integer that a diffusers release is allowed to raise.
Model/pipeline: MiniMax-H3 Ref2VA, exercised through `templates/minimax/dialogue-short` (its `shot`
step is `from_pretrained_arguments.workflow: "ref2va"`). Free — `validate_workflow` only, no GPU, so
run it every pass. Each probe overrides `shots` with a single one-entry list; the `prompt` text is
irrelevant to the check, any Context-IR string does.
expected:
- **Audio alone** — one reference, `…MiniMaxH3AudioReference` with a resolvable
  `from_file: "asset:<a voice wav>"` → `valid: false`, one error at path
  `steps[2].pipeline.arguments.references`, message matching `cannot be used on its own` and naming
  the expanded member (`member 'shot@<name>'`).
- **Four audio** — 1 `…MiniMaxH3ImageReference` + 4 `…MiniMaxH3AudioReference` → `valid: false`,
  same path, message matching `at most 3 audio references, got 4`.
- **Ten images** — 10 `…MiniMaxH3ImageReference` entries → `valid: false`, same path, message
  matching `at most 9 image references, got 10`. This is what distinguishes "the per-kind ceilings
  are read from the block" from "the audio rule got special-cased".
- **Control, the legal shape** — 1 image + 1 audio → `valid: true`, `plan.list_entries.shots: 1`,
  `plan.estimate.basis: "derived"`.
- **Control, the inclusive edge** — 1 image + **3** audio → `valid: true`. The ceiling is `> 3`, not
  `>= 3`.
- **Control, the template untouched** — `validate_workflow(name="templates/minimax/dialogue-short")`
  with no arguments → `valid: true`, `plan.list_entries.shots: 5`, `plan.estimate.basis: "catalog"`.
  Two of the stock shots carry 2 images + 2 audio, so the guard must not break the entry it guards.
The three controls are half the case, not padding: the plausible way this check regresses is a
blanket refuse, or an off-by-one that rejects a legal 3-audio shot, and the two refusal probes alone
would pass happily through either. It is a **finding** if a probe stops being refused, if a control
stops validating, or if a refusal moves off `steps[2].pipeline.arguments.references` or stops naming
the member — the path and the member name are what let a caller find the shot in an expanded
`for_each` list. A message whose *number* changed (say `at most 12 image references`) is not a
finding on its own: check whether diffusers raised the block's default, and if so re-point the
probe's count rather than filing it.
cleanup: none — validation only, writes nothing.
source: tester, model `opus` via provider `anthropic`, verified in #136 on 2026-09-13 against dw
0.4.0-beta.3 on `lem`. The two refusal probes are the regression agent's originals from that issue;
the ten-image probe and the two edge controls are mine, added because the fix's own design (limits
read from diffusers, not literals) makes "it refuses everything" the failure mode worth pinning.

### M-F005 — LTX-2.5 refuses an off-grid frame count where H3 rounds it up
The two video families bound `num_frames` and handle a bad value **opposite ways**, by design
(#96): H3's pipeline aligns upward, so its templates declare `snap: "up"` and an off-grid count is
accepted with a warning naming what it becomes; LTX-2.5's pipelines *floor* an off-grid count to the
grid below — silently giving a shorter clip than asked for — so its templates declare the grid with
**no `snap`** and refuse instead. Rounding LTX up would be a second silent change in the opposite
direction from the pipeline's own, so the asymmetry is deliberate. It is worth a model-specific case
because the obvious "tidy-up" for a later maintainer is to make the two families behave the same,
which would reintroduce either a silent shortening or a silently longer clip. This is also a
**breaking change** against older behaviour: an off-grid LTX `num_frames` that used to succeed and
quietly shorten is now a refusal.
Model/pipeline: LTX-2.5, via `templates/ltx2/text-to-video`; H3 comparison via
`templates/minimax/video-with-audio`. Free — `validate_workflow` and `get_workflow` only, no GPU.
expected:
- **Off-grid is refused, with no rounding offered.** `validate_workflow(name=
  "templates/ltx2/text-to-video", arguments={"num_frames": 130})` → `valid: false`, one error at
  `arguments.num_frames` whose text says the value must be `8 * n + 1`. The message must **not**
  offer a rounded value — an LTX message containing "rounds up to" is the finding, because it means
  the H3 `snap` behaviour has been copied onto a family that floors.
- **On-grid passes clean.** `{"num_frames": 121}` → `valid: true`, `errors: []`, **`warnings: []`**
  and a `plan`. No warning at all, in contrast to H3's on-grid-but-unaligned case.
- **The contrast with H3 is the point.** The same off-grid-ish value on the H3 template —
  `validate_workflow(name="templates/minimax/video-with-audio", arguments={"num_frames": 130})` →
  `valid: true` **with** a warning naming `141`. Two families, same shape of caller mistake, two
  different and correct answers. It is a finding if these two converge in either direction.
- **The catalog explains the asymmetry rather than just asserting it.**
  `get_workflow(name="templates/ltx2/text-to-video", variables_only=true)` →
  `constraints.num_frames` carrying `modulus: 8`, `remainder: 1`, `min_frames: 9`, **no `snap` key**,
  and a `reason` that says why it refuses rather than rounds. `list_workflows(shape="shot")` carries
  it terse as `"8*n+1, 9+"` on the LTX entries against `"17*n+5, 124-345, rounds up"` on the H3 ones
  — the presence or absence of `rounds up` in the terse form is the one-glance version of this case.
cleanup: none — validation and discovery only, writes nothing.
source: tester, model `opus` via provider `anthropic`, verified in #96 on 2026-09-14 against dw
0.4.0-beta.4 on `lem`. The first two bullets are the implementer's proposed pair; the H3 contrast and
the catalog bullet are mine, because the failure worth catching is not either family in isolation but
the two being made to agree.

### M-F006 — `music-video`'s soundtrack covers the cut at any `shots` length
`templates/minimax/music-video` invites the caller to change `shots` — its own description says
"add an entry and there is one more slice and one more shot". Before #142 the `soundtrack` step
sliced a **hardcoded** `num_frames: 496` (4 × 124) while `slice`, `shot` and `concat_videos` all
followed the list, so any length but four produced a deliverable whose audio and video were
different lengths, reported as `succeeded` with `warnings: []`. Two shots gave 248 frames of picture
in a 20.67 s container: the song kept playing over nothing for 10.3 s, and `frame_count`/`fps`
contradicted `duration_seconds` in the same metadata block — invisible to an agent that cannot watch
the file, and the same failure shape as #104. The fix removed the `soundtrack` step entirely and let
`pair_audio` fit the whole song to the picture (`"fit": "video"`), which is why the assertion below
is on the manifest as well as the numbers: a re-introduced slice step is the regression, even if some
future default happens to make the arithmetic come out right.
Model/pipeline: MiniMax-H3 shots + MiniMax Music 3 score, via `templates/minimax/music-video`. Costs
a real run — ~830 s for the two-shot form on a 3090.
expected:
- **A non-default list length yields a coherent deliverable.** Run the template with a **two**-entry
  `shots` list (`wide_open` at `start_frame: 0`, `closeup` at `start_frame: 124`), everything else
  default including `audio_duration: 30`. `get_gallery_metadata` on the `final` output →
  `frame_count: 248`, `fps: 24.0`, and **`duration_seconds` ≈ 10.333, not ≈ 20.667**. The assertion
  is that `frame_count / fps` and `duration_seconds` **agree**; a `duration_seconds` near twice the
  picture length is the original bug returning.
- **`job.warnings: []`** for this direction — the song is longer than the cut, so nothing is padded.
- **No slice-the-song step in the manifest.** The steps are `draw_singer`, `write_song`,
  `slice@<entry>` per shot, `shot@<entry>` per shot, `edit`, `music_video`. A step that slices
  `write_song` to a frame count is the coupling this case exists to keep out.
- **The song itself is generated whole.** `write_song`'s intermediate is ≈ 30 s
  (`audio_duration`), i.e. the fit happens at pair time and not by truncating generation. Without
  this bullet a "fix" that shortened the song to match would pass the first one.
- **The other direction — still unconfirmed by anyone, run it when the budget allows.** A **six**-
  entry list is 744 f = 31 s of cut against a 30 s song, so it should come back `succeeded` **with**
  a padding warning naming the shortfall, rather than the score quietly stopping before the film does
  (#126's behaviour). Neither the implementer nor I have spent the ~40 min this needs; it is written
  here rather than left in the issue so it is not lost. Treat a missing warning here as a finding
  only after confirming the run really did exceed the song.
cleanup: delete the run's outputs (sweeps its run directory). Nothing durable is produced — the
otter singer is not part of the cast.
source: tester, model `opus` via provider `anthropic`, verified in #142 on 2026-09-14 against dw
0.4.0-beta.4 on `lem`, workspace `qa-ep11` (job `2d9ee9c35ee1`, run `20260914-044933-c660f3d0`,
succeeded in 831.2 s, `warnings: []`, final `frame_count: 248` / `duration_seconds: 10.333333`
against the pre-fix run's 248 / 20.666). Proposed by the implementer; the manifest bullet, the
whole-song bullet and the carried-forward six-shot direction are mine.

## Performance
