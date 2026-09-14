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

### M-F003 — every H3 template's turbo LoRA checkpoint agrees with its canvas, shifts, alpha and step count
Every `templates/minimax/*` H3 template carries a `lightx2v/Minimax-h3-Turbo` LoRA and runs
`num_inference_steps: 9`; what differs is *which* checkpoint, and a checkpoint comes with a canvas, a
sigma-shift pair and an alpha that move together. The `dw:minimax-h3` skill's hard rules state this
as "change one, change all" and name exactly three tested combinations. It is the kind of thing a
template edit breaks silently: #149 found four reference templates had carried the FL2VA checkpoint
(distilled for the base transformer, not `transformer_ref`) for a month, and #147 found the 768p
FL2VA LoRA on the wrong shift/alpha — both produced jobs that *ran* and delivered worse video for
full price. Nothing else in the suite checks it, and it is free to check.
Free (run this one every pass): `list_workflows(shape="shot")` and `list_workflows(shape="sequence")`
to enumerate every `templates/minimax/*` entry that exposes `lora_weight_name` (18 as of
2026-09-14), then `get_workflow(name=..., variables_only=true)` on each and compare
`lora_weight_name`, `width`/`height`, `video_shift`/`audio_shift`, `lora_alpha` and
`num_inference_steps` against the three rows below. Every template also has
`lora_model_name: "lightx2v/Minimax-h3-Turbo"`, `lora_adapter_name: "turbo"`, `lora_scale: 1.0`.
expected:
- **544p FL2VA turbo** — `lora_weight_name: minimax_h3_fl2v_turbo_8step_v1.0_bf16.safetensors`,
  `video_shift: 12.0`, `audio_shift: 3.0`, `lora_alpha: null`, 9 steps. Templates:
  `video-with-audio`, `image-to-video`, `chained-segments`, `enhance-prompt`,
  `enhance-prompt-with-image` (all 960x544); `first-and-last-frame`, `last-frame-only` (544x544 —
  same 544 short edge, square because they pin a square still).
- **768p FL2VA turbo** — `lora_weight_name: minimax_h3_fl2v_turbo_8step_v1.0_768p_bf16.safetensors`,
  1344x768, `video_shift: 6.0`, `audio_shift: 3.0`, `lora_alpha: 128`, 9 steps. Template:
  `video-with-audio-768p` only. This is the one row whose shift and alpha differ; the skill says
  so explicitly ("the two 768p LoRAs differ in shift; do not generalise").
- **768p Ref2VA turbo** — `lora_weight_name: minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors`,
  960x544, `video_shift: 12.0`, `audio_shift: 3.0`, `lora_alpha: null`, 9 steps. Every template
  whose H3 step takes references (`transformer_ref`): `reference-to-video`, `composable-references`,
  `voice-timbre-reference`, `generated-subject-reference`, `chain-matched-to-audio`,
  `chain-video-continuity`, `chain-matched-and-aligned`, `storyboard`, `dialogue-short`,
  `music-video`. Note the canvas: a 768p-trained *Ref2VA* checkpoint on a 960x544 canvas at the
  544p shift is the tested combination, not a mismatch — the skill ties canvas to the FL2VA rows only.
- `num_inference_steps: 9` on all of them; `denoise_total_steps` reporting 8 in a manifest is the
  scheduler counting grid points and is expected (skill hard rules).
It is a **finding** if any template's `lora_weight_name`, canvas, shift pair, alpha or step count
stops matching the row it belongs to; if an `fl2v` weight appears on a reference-taking template
(the skill says `validate_workflow` refuses this — a template that ships that way and validates is a
double finding); if a new `templates/minimax/*` H3 template appears whose values fit none of the
three rows (a fourth combination is either a skill update or a mistake — check the skill, then file
either way so the row gets recorded here); or if the `dw:minimax-h3` skill's hard-rules block stops
naming these three combinations — the skill is how a caller learns which numbers to quote, and it
going quietly stale is as bad as the templates going wrong. A template moving a `lora_*` value
between inline and variable is not a finding, nor is a new template landing on one of the three
rows (add it to the list above).
cleanup: none — reads only, writes nothing.
source: regression agent, model `opus` via provider `anthropic`, found while running M-F001 on
2026-09-13 (server 0.4.0-beta.3), as a LoRA-present/no-LoRA vs 9/20-step split. Rewritten
2026-09-14 (Don, via #156, model `opus` via provider `anthropic`) after #147/#148/#149 put a turbo
LoRA on every template and the skill's rule became checkpoint-canvas-shift-alpha; all 18 templates
matched the three rows above over MCP on that date. Related: #147, #148, #149, #156.

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

### M-F007 — an H3 checkpoint swap is three numbers, and the catalog says so
The turbo LoRAs for MiniMax-H3 are trained at a canvas *and* a sigma schedule *and* an alpha, and
the three move together. `lightx2v/Minimax-h3-Turbo`'s 544p FL2VA checkpoints are trained at shift
12/3 with the file's own `alpha: 8`; its 768p FL2VA checkpoints are trained at **shift 6**/3 with
upstream passing `--lora-alpha 128`, a sixteenfold difference from the file's recorded alpha rather
than a nudge. Before #147 no H3 template mentioned `shift` or `alpha` at all, so a caller reaching
for 768p could only override `lora_weight_name` — which would have run the 768p LoRA on the 544p
sigma schedule at a sixteenth of its trained strength, and produced a clip that looks merely
mediocre rather than misconfigured. This case pins the *pairing* in the catalog: the point is not
that any one number is right but that the templates state enough for a caller to see that a
checkpoint swap is not a one-argument change. Note the asymmetry deliberately — the Ref2VA 768p
checkpoint is shift **12**/3, not 6, so 768p does not imply shift 6.
Model/pipeline: MiniMax-H3, `lightx2v/Minimax-h3-Turbo` LoRA family. Free — `get_workflow` only, no
GPU, so run it every pass.
expected: `get_workflow(name=..., variables_only=true)` on each, checking `video_shift`,
`audio_shift` and `lora_alpha` are all **declared** (`lora_alpha: null` is a declaration — it means
"use the file's own" — while a *missing* `lora_alpha` key is the regression):
- `templates/minimax/video-with-audio` — `video_shift: 12.0`, `audio_shift: 3.0`, `lora_alpha: null`,
  960x544, an FL2VA (`fl2v`) weight name.
- `templates/minimax/video-with-audio-768p` — `video_shift: 6.0`, `audio_shift: 3.0`,
  `lora_alpha: 128`, 1344x768, a `768p` FL2VA weight name.
- `templates/minimax/reference-to-video` — `video_shift: 12.0`, `audio_shift: 3.0`,
  `lora_alpha: null`, 960x544, a **`ref2v`** weight name. This is the asymmetry control: a run that
  "helpfully" normalised every 768p-trained checkpoint to shift 6 would break it.
It is a **finding** if any of the three keys stops being declared on any of the three templates, if
the 544p/768p pair stops differing in `video_shift` and `lora_alpha` (the pair is the whole case —
two templates that agree on all three numbers mean the distinction has been flattened), or if the
Ref2VA row moves to shift 6. A number changing in step with a checkpoint change named in an issue is
not a finding on its own: check which weight file the template now pins, and whether upstream's
specs table gives that file a different shift/alpha, before filing.
cleanup: none — reads only, writes nothing.
metrics: none — this case yields no measurement, only declarations.
source: tester, model `opus` via provider `anthropic`, verified in #147 on 2026-09-14 against dw
0.4.0-beta.4 on `lem`, workspace `qa-verify`. All three templates matched the above on that pass.
The runtime half — that these numbers reach the scheduler rather than merely being declared — is
M-F002's territory (`num_inference_steps: 9` producing an 8-evaluation schedule), confirmed again
the same day by job `b4b5959424d3`. Deliberately kept separate: this case is free and that one
costs a render, and the catalog going stale is the failure worth catching on every pass.

### M-F008 — the 768p H3 path renders at its trained canvas on its trained schedule
`templates/minimax/video-with-audio-768p` pins a combination rather than leaving it to arguments:
the `minimax_h3_fl2v_turbo_8step_v1.0_768p_bf16` checkpoint, 1344x768, `video_shift: 6.0`,
`lora_alpha: 128`, `num_inference_steps: 9`. Every one of those has to reach a different part of
the stack — the canvas to the pipeline, the shift to the scheduler, the alpha to the peft layers
after load — and none of them fails loudly if it doesn't. A 768p LoRA run on the 544p sigma
schedule at the file's own `alpha: 8` (a sixteenth of what upstream passes) produces a clip that
completes, saves, and simply looks mediocre. M-F007 pins that the catalog *declares* these
numbers; this case is the other half — that a render on them actually happens. The two together
are why a checkpoint swap can be trusted to be three numbers rather than one.
Model/pipeline: MiniMax-H3 T2VA with `lightx2v/Minimax-h3-Turbo`'s **768p FL2VA** 8-step
checkpoint. Costs one real run, ~13 min cold on a 3090 — model-specific is opt-in, which is where
a render this size belongs.
expected: `run_workflow("templates/minimax/video-with-audio-768p")` on defaults, then
`wait_for_job` / `get_job_events` / `get_gallery_metadata` on the output:
- **`status: "succeeded"`, `warnings: []`.** Completion is itself the assertion here — see above.
- **`denoise_total_steps: 8`** from `num_inference_steps: 9`, i.e. the turbo schedule, not a
  silent fallback to the base model's step count.
- **The deliverable is `width: 1344`, `height: 768`**, `frame_count: 124`, `fps: 24.0`, with audio:
  `sample_rate: 32000`, `channels: 2`, and `mean_dbfs` above -40 (a soundtrack that generated
  rather than a silent track beside a good picture).
- **`host_memory_peak_rss_mb` stays under `host_memory_total_mb`** on the closing `memory` event.
  This box runs at ~96% of host RAM on H3 and the original 768p attempt was OOM-killed at 345
  frames, so the headroom is the thing to watch, not an abstract pass.
It is a **finding** if the run fails or OOMs at the *default* 124 frames, if the canvas comes back
anything but 1344x768, if `denoise_total_steps` stops being 8, or if wall clock moves well outside
the trend in `regression-perf/M-F008.jsonl` (the shift or the alpha silently not being applied
would most likely show up as a step count or a timing change, since nobody in this loop can judge
the picture). A failure at a frame count *above* the default is not this case's business — 345
frames at this canvas is a known OOM and deliberately out of scope.
cleanup: delete the run's output (sweeps its run directory). Nothing durable is produced.
metrics: `latency`, condition `cold`, unit `s` — the job's own `started_at`->`finished_at`, logged
to `regression-perf/M-F008.jsonl` pass or fail. This template shipped with **no curated `cost`**
because nothing had measured it, so this log is currently the only cost history it has.
source: tester, model `opus` via provider `anthropic`, verified in #148 on 2026-09-14 against dw
0.4.0-beta.4 on `lem`, workspace `qa-verify` — the template's first ever run (job `b6ecc7877346`,
786.0 s, 1344x768/124 f, peak RSS 61548.9 of 64208.6 MB). Proposed by the implementer; the memory
bullet and the audio half of the metadata bullet are mine. Note for a future run: the **first**
denoise step took ~232 s against ~40-57 s for steps 2-8 — warm-up, not a stall, and the same
pattern C-F023 records after a reload.

### M-F009 — an H3 adapter trained against the wrong partition is refused, and an unknown one is not
This is the one H3 misconfiguration that never shows up in the output. MiniMax-H3's
`ref2va` workflow denoises against the `transformer_ref` partition; a `fl2v` turbo
checkpoint is trained against `transformer`. Loading the wrong one raises nothing —
H3 accepts it, the run succeeds, the clip saves, and the only symptom is that it
looks worse than it should. Nobody in this loop can judge a picture, so if validate
does not catch it, nothing does; that is why it is worth a case even though the
refusal is free (#155).
The second half is what keeps the rule from becoming a cage. The `ref2v`/`fl2v`
naming is MiniMax's own file-naming convention, not a symbol anything declares, so a
checkpoint whose name says neither cannot be classified — and a validator that refused
what it could not classify would block every future adapter the day it shipped. An
unrecognised name has to stay **valid**, with a warning. That bullet is the
load-bearing one: if it ever starts failing, the escape hatch has closed and the rule
has become a whitelist.
Model/pipeline: MiniMax-H3 Ref2VA with `lightx2v/Minimax-h3-Turbo`'s 8-step turbo
checkpoints. Free — three `validate_workflow` calls, no GPU, nothing loaded.
expected:
- **The mismatch is refused.** `validate_workflow(name=
  "templates/minimax/reference-to-video", arguments={"lora_weight_name":
  "minimax_h3_fl2v_turbo_8step_v1.0_bf16.safetensors"})` → `valid: false`, exactly one
  error at **`arguments.lora_weight_name`** (the path points at what the caller wrote),
  its text naming both partitions (`transformer` and `transformer_ref`) and saying the
  run would otherwise succeed. Path and both partition names matter: an error that
  only says "incompatible adapter" does not tell a caller which way round it is.
- **An unrecognised name stays valid.** Same call with
  `"my-new-ref-lora.safetensors"` → **`valid: true`**, with a warning naming the
  `ref2v`/`fl2v` convention and this step's `ref2va` workflow. `valid: false` here is
  the regression, and it is the one that would quietly break the next checkpoint
  release.
- **The template's own default is clean.** Same call with no `arguments` (default
  `minimax_h3_ref2v_turbo_8step_v1.0_768p_bf16.safetensors`) → `valid: true` with no
  adapter warning at all. This is the control: a rule that warns on the catalog's own
  correct pairing is noise, and the catalog is swept in the dw repo's own tests for
  exactly that reason.
Not covered here: the symmetric refusal (a `ref2v` adapter on a `t2va`/`fl2va` step).
The implementer reports it is implemented, but every H3 template reachable from
`list_workflows(shape="shot", traits="identity-referenced")` runs `ref2va`, so a
consumer-only agent has no step to exercise it against — `chain-video-continuity`
looks like a candidate and is not (`get_workflow` shows `workflow: "ref2va"`, so a
`ref2v` adapter there is correct and validating clean is the right answer, not a miss).
If a `t2va`/`fl2va` template ever enters the catalog, that half belongs in a new case
beside this one.
cleanup: none — all three calls are free and write nothing.
source: tester, model `opus` via provider `anthropic`, verified in #155 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`. Proposed by the implementer;
the "not covered" note is mine, recorded so a future reader does not read the gap as
an oversight and does not repeat the `chain-video-continuity` false lead.

### M-F010 — an elided step says which variable replaced it, and a typo is refused as a typo
`templates/minimax/music-video` draws its singer with a `draw_singer` step unless the
caller supplies `singer_reference`, in which case nothing reads that step's result and
it does not run. Two very different things produce that same "nothing reads it" state:
the caller deliberately supplied a portrait, or something upstream broke and the step
went unread by accident. The engine used to report both with the same wording — a
diagnosis suggesting a misspelling — so the happy path of supplying a standing cast
member came back looking like a mistake (#157). The fix compares the definition as
**written** against the substituted steps, so an override is recorded as an override.
The trap in the third bullet is what makes the second one safe to trust. If a
misspelled variable name were silently accepted, a typo'd `singer_reference` would be
indistinguishable from a successful one — the step would elide, the plan would look
right, and the render would use whatever the workflow drew instead of the cast member
the caller asked for. Refusing the unknown name outright is what closes that.
Model/pipeline: MiniMax-H3 `music-video`. Free — three `validate_workflow` calls, no
GPU. The `job.warnings` bullet costs nothing extra because it rides on whatever
`music-video` run happens next; do not render for it.
expected:
- **The override is named.** `validate_workflow(name="templates/minimax/music-video",
  arguments={"singer_reference": {"reference_type": "variable:image_reference_type",
  "from_file": "asset:qa-cast/priya-portrait.jpg"}})` → `plan.elided_steps` is exactly
  one entry: `step: "draw_singer"`, `overridden_by: "singer_reference"`, and a `reason`
  naming that variable. The word **"misspelled" must not appear anywhere in the
  answer** — that is the literal regression. `plan.steps` is 11.
- **No override, no elision.** The same call with no `arguments` → `elided_steps: []`
  and `plan.steps` 12. The count moving by exactly one is the cheap cross-check that
  the elision is real and not just a label.
- **A typo is refused, not absorbed.** `arguments={"singer_refrence": {...}}` →
  `valid: false`, one error at `arguments.singer_refrence` reading "Unknown variable
  'singer_refrence'" and listing the declared variable names. A misspelling that comes
  back `valid: true` with `draw_singer` elided is the dangerous failure: it is a silent
  wrong render, not an error.
- **The run-time wording follows the same record.** On the next real `music-video` run
  that supplies `singer_reference`, `job.warnings` carries "Step 'draw_singer' did not
  run: 'singer_reference' was supplied, so nothing reads its result." — the saving
  stated, the misspelling diagnosis absent. Check it when a run happens; it does not
  justify one.
cleanup: none for the three validate calls. The run-time bullet adds nothing to clean
up beyond whatever that run already cleans up.
source: tester, model `opus` via provider `anthropic`, verified in #157 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep13` (the portrait is a shared asset,
so any workspace reaches it). Proposed by the implementer; the typo bullet is mine —
they described the trap as covered and it is, but it was not in the case they proposed,
and it is the bullet that makes the override bullet worth anything.

### M-F011 — a clipped soundtrack is warned about and reported as clipped, by both halves at once
Music 3 writes tracks at or over full scale as a matter of course, and a lossy encode
of a waveform with no headroom decodes above 0 dBFS and clips. Two independent things
are supposed to notice: a `job.warnings` entry when the file is written, and
`get_gallery_metadata`'s `media.peak_dbfs` when the file is read back. The regression
to catch is **the two disagreeing** — a deliverable at full scale reported as clean, or
a warning about a file that is fine (#158). Neither number alone is the assertion; the
agreement is.
There is a subtlety that makes this case worth more than it looks. The warning measures
the waveform **as written**; `get_gallery_metadata` measures the **decoded** file, which
overshoots by a few tenths legitimately. So the two are not the same measurement and
must not be asserted equal — what has to hold is that the warning is present whenever
the source has no headroom, and that the metadata hint tells a reader how to interpret
the overshoot rather than leaving them to guess. On the verifying run the decoded figure
was +0.76 dBFS, inside the band the hint itself calls legitimate, while the source was
+0.0 — a check built only on the decoded number would have shrugged at it.
Model/pipeline: MiniMax Music 3, and any workflow that muxes a soundtrack into a video.
Costs nothing of its own: ride it on whatever Music 3 or `music-video` run the suite or
an episode does next.
expected: after any run that writes a soundtrack —
- **If the source has no headroom, `job.warnings` says so.** One entry per saved file,
  naming that file and its peak, at or above **-0.5 dBFS** (not 0 — a waveform peaking
  at exactly full scale is "0 dBFS" by its own metadata and still decodes above it,
  which is the case that started this). A workflow whose saving step is fed an
  un-normalized Music 3 track fires this; `templates/minimax/music` and
  `templates/minimax/music-video` no longer do, because #159 put a `normalize_audio`
  step in both, and their **absence** of a warning is checked by M-F012 rather than
  here.
- **`get_gallery_metadata`'s `media.peak_dbfs` agrees.** A file the run warned about
  reads at or above 0 decoded; a file it did not warn about reads below. The two
  pointing opposite ways is the finding, in either direction.
- **The hint teaches both ends of the range.** The `next` text carries `mean_dbfs`
  below -40 as the near-silent failure **and** `peak_dbfs` at or above 0 as the
  no-headroom one, with the caveat that a decoded lossy file overshoots by a few tenths
  and that +1 or more is the real signal. A hint that teaches only the quiet end is a
  regression — an agent that cannot listen has nothing else to read.
- **It covers the muxed deliverable, not only the audio file.** On a `music-video` or
  `assemble-and-score` run the warning names the final mp4's soundtrack as well as the
  saved audio. Source and deliverable is the useful pair: #158 was filed because the
  mp4 was the thing at +3.26 and nothing had mentioned it. Confirmed in job
  `089b1e2945d2`: `raw_mux` warned naming the mp4 at +0.8 dBFS and decoded at +0.776,
  `balanced_mux` did not warn and decoded at -0.626.
cleanup: none of its own — it reads a run another case or episode already paid for.
Delete nothing beyond what that run's own cleanup says.
source: tester, model `opus` via provider `anthropic`, verified in #158 on 2026-09-14;
stale-case edit approved by Don on 2026-09-14 (#160)
against dw 0.4.0-beta.4 on `lem`. Job `66f9db65a603` (`templates/minimax/music`,
`audio_duration: 30`, workspace `qa-ep15`, 91.1 s) covered the first three bullets:
warning at +0.0 dBFS on the written mp3, `peak_dbfs: 0.758` / `mean_dbfs: -18.24`
decoded, hint carrying both ends. The fourth bullet — the muxed mp4 — is **written from
the implementer's description and not yet confirmed over MCP**; it costs a ~25 min
render and the next `music-video` run should be the one to settle it. No `metrics:`
line deliberately: a dBFS figure hovering around zero is not something the
median-and-50% rule in `regression-perf/` can say anything useful about.

### M-F012 — the Music 3 templates deliver headroom without being asked
Music 3 lands at or over full scale on this box every time, so until #159 the default
path shipped a deliverable that clipped and a caller had to know to add a gain step.
`templates/minimax/music` now writes through a `balanced` (`normalize_audio`, -1.0 dBFS)
step with the pipeline step at `save: false`, and `templates/minimax/music-video` puts
the same step between `edit` and the `pair_audio` mux. This case pins the *default*
path — no arguments beyond a duration, nothing the caller has to know.
Two things about it are easy to get wrong, and both are the point:
**Do not assert the absence of the warning alone.** `audio_no_headroom` measures the
waveform as written, so it goes quiet the moment a gain step exists — and it would also
go quiet if the check itself broke. The level is the assertion; the warning is
corroboration.
**Do not assert a target level.** The deliverable is mp3, and a lossy encode overshoots
the -1.0 the waveform was normalized to. Measured on the verifying runs, that overshoot
was **0.93 dB and 0.59 dB** on two Music 3 tracks — near enough to eat the whole -1.0.
An assertion of `<= -0.9 dBFS` fails against a fix that is working correctly. Assert
strictly below 0, which is what "does not clip" means.
Model/pipeline: MiniMax Music 3. One ~90 s run at `audio_duration: 30`; the
`music-video` half rides on whatever `music-video` render the suite or an episode does
next rather than paying 35 min of its own.
expected: `run_workflow("templates/minimax/music", arguments={"audio_duration": 30})` —
- **The catalog still carries the gain step.** `get_workflow("templates/minimax/music")`
  shows two steps: `generate_music` with `result.save: false`, then `balanced`, a
  `normalize_audio` task at `peak_dbfs: -1.0` whose `result` is what gets written. A
  template that has quietly lost the step is the regression this case exists for.
- **The deliverable is the `balanced` step's file**, named `MiniMaxMusic-balanced.*`
  (not `MiniMaxMusic-generate_music.*`). The old name no longer resolves as an
  `output:` reference; `keep_output` is the stable form. Note this is a `.1-0.0.mp3`
  suffix, not the `.0-0.mp3` the implementer predicted in #159 — read the manifest,
  don't compose the name.
- **No `audio_no_headroom` entry in `job.warnings`.** Corroboration only; see above.
- **`get_gallery_metadata(<the mp3>).media.peak_dbfs` is strictly below 0** and
  `mean_dbfs` is above -40 (a run normalized into near-silence is the opposite failure
  and would also satisfy "below 0").
- **`music-video`'s mux is wired the same way and only there.** On the next
  `music-video` run: `get_workflow` shows `balanced` reading
  `"previous_result:write_song"` and `music_video`'s `pair_audio` reading
  `"previous_result:balanced"`, while every `slice` step still reads
  `"previous_result:write_song"` — the slices condition the picture, so normalizing
  them would change what is generated, not just how loud it is. The final mp4's
  `peak_dbfs` is strictly below 0. A `slice` step reading `balanced` is a finding even
  if the deliverable's level looks right.
metrics: `peak_dbfs` of the delivered mp3, condition `music`, unit `dBFS`, logged to
`regression-perf/M-F012.jsonl`; add condition `music-video` from the muxed mp4 whenever
a `music-video` run settles that bullet. Logged pass or fail. As with S-F031 the
median-and-50% rule says nothing useful about a figure near zero — what a reader is
watching for is the number creeping up toward 0 across encoder or template changes.
cleanup: delete the run's output folder. Nothing here is a fixture.
source: tester, model `opus` via provider `anthropic`, verified in #159 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`. Two runs: `6d2de49d1849`
(`audio_duration: 30`, 84.2 s, `peak_dbfs: -0.072`) and `9cd731db7c00`
(`audio_duration: 45`, 110.5 s, `peak_dbfs: -0.413`), both with empty `job.warnings`.
`normalize_audio` itself was checked separately in jobs `04fed6350543` / `5364d68417c5`
(-1 -> -0.73 decoded, -6 -> -5.85; -1 -> -0.53, -6 -> -5.90 on the second track), which
is what established the overshoot figures above rather than guessing at them. The
`music-video` bullet is written from the deployed template's JSON read over MCP and is
**not yet confirmed from a run**.

## Performance
