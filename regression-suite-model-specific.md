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
the final sweep) live in `agents/regression/`, not here.

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
`source: tester, found while running TESTER_TASK.agent.md`). Name the
model/pipeline/checkpoint the case depends on explicitly in its body — a
model-specific case that doesn't say which model it needs is useless to a
future run. No separate approval step — the regression agent already grows
these files unsupervised when it notices gaps; a case either of you adds is
the same kind of edit.

**No case may depend on chance.** A generative model with no seed draws a
different take each run, so a case never asserts what an unseeded output
*contains*: its loudness, its content, what a judge scores it. Pin `seed`,
or assert only what the server owes on every take, such as a shape, a
duration, or a warning when the take is unusable (S-F007 is the model). A
case that fails one run in ten teaches every agent to ignore it, and a
release gate can't tell that from a regression.

## Removing a case

No agent may remove or rewrite an existing case on its own judgment. If a
case looks too expensive, too flaky against things outside the server's
control, or no longer meaningful, or its `expected:` predates a verified
fix, propose dropping or changing it with a GitHub Issue on the harness
repo, `dkackman/harnest` (where this file lives, not the ticket repo),
naming the case id, the reasoning and the evidence (the issue that changed
the behavior), labeled `suite` + `status:needs-approval`. Every agent files
this directly, the implementer included (it has no suite files checked out
to edit anyway), and so does the curator's audit (`run-curate.sh`). Leave
the case exactly as written until it's ruled on.

A curator review session (`run-loop.sh`) rules on each request:
- it **applies** what the record settles: a stale reference, or an
  expectation that a verified or `breaking-change` issue changed on
  purpose;
- it **denies** an edit that would make a failing case pass with no such
  record;
- it **escalates** judgment calls to Don (`owner:don`): cost against
  coverage, moves and merges, retirements from an audit, the security
  suite beyond a stale reference, and anything touching more than 3 cases.

The one edit made without a request is the tester removing a feature
stage's `pending: #NN` line when that stage verifies.

## Fixtures

Durable contents of `regression-model-specific` that persist across runs.
Add a line when a case starts relying on one; remove the line (and the
fixture) when nothing uses it anymore.

- `asset:upscale/src-480x272.mp4`, `asset:upscale/src-480x272-silent.mp4`,
  `asset:upscale/src-640x360.mp4` (M-F060, M-F061; `pending: #548`). No dw task resizes
  a video, and LTX can't render 272 rows, so these are made off-box, once, from the shared
  `asset:qa-cast/ep3-shot1-incident.mp4` (960×544, 24 fps, stereo). Download that file with
  `download_output`, then:
  - `ffmpeg -i in.mp4 -vf scale=480:272 -r 24 -frames:v 121 -c:v libx264 -c:a aac -shortest src-480x272.mp4`
  - the same command with `-an` in place of `-c:a aac -shortest`, giving `src-480x272-silent.mp4`
  - the first command with `scale=640:360` (16:9), giving `src-640x360.mp4`

  Put each in the workspace's own asset library, `upscale/` under the `workspace`-origin
  root `list_assets(workspace="regression-model-specific")` reports (on lem,
  `~/diffusers-workspace/regression-model-specific/assets/upscale/`), and confirm with
  `get_gallery_metadata("asset:upscale/<file>")`. Not `upload_asset`: an upload always
  lands under `uploads/`, so `asset_name="upscale/<file>"` gives `asset:uploads/upscale/<file>`,
  which no case names. Made this way on 2026-10-01 for #548 (480×272 and 640×360, 24 fps,
  121 frames, 5.04 s, 32 kHz stereo at −16.42 LUFS, the silent one with no audio stream).
  Until they exist, M-F060 and M-F061 record "fixture missing" and skip. That is a note for
  Don, not an issue.

- `asset:refine/src-512x288.mp4` and `asset:refine/src-384x288.mp4` (M-F064, M-F065).
  These are LTX-2.5 clips with their own soundtracks, made on-box. The
  first is 512×288 (16:9, the refine-clip default size) and the second 384×288 (4:3, the
  wrong aspect). For each one:
  1. Run `templates/ltx2/text-to-video` in workspace `regression-model-specific` with
     `arguments={"width": 512, "height": 288, "num_frames": 121, "seed": 543}`, or `"width": 384`
     for the second. Quote its `plan.estimate` as `acknowledged_cost`.
  2. `keep_output` its final mp4 as asset `refine/src-512x288.mp4` (or `refine/src-384x288.mp4`)
     in the same workspace, then `delete_output(job_id=<id>)`.
  3. Confirm with `get_gallery_metadata` that the asset is the stated size, has 121 frames at
     24 fps, and has an audio stream.

  M-F066 also needs a source with **no** audio stream. It uses `asset:refine/src-512x288-silent.mp4`,
  made on-box with an inline `loop_frames` workflow (as in #549's verify) in workspace
  `regression-model-specific`, then `keep_output` of its mp4 as that asset. Confirm with
  `get_gallery_metadata` that it is 512×288, has 121 frames and has no audio stream. The M-F061
  fixture `asset:upscale/src-480x272-silent.mp4`, or any mp4 whose `get_gallery_metadata` shows no
  audio stream, will also do. If none exists, M-F066 records "fixture missing" and skips.
- `asset:h3-hold/vwa-seed42-baseline.mp4`: a seed-42 render of `templates/minimax/video-with-audio`
  at its defaults, which **must be made before #618 deploys**. It is M-F077's reference for
  "no `hold_audio` gives the same output as before". To make it:
  1. In workspace `regression-model-specific`, run
     `run_workflow("templates/minimax/video-with-audio", arguments={"seed": 42}, acknowledged_cost=true)`.
  2. `keep_output` its mp4 as that asset, then `delete_output(job_id=<id>)`.
  A stand-in is a job that `list_jobs` shows completing before #618's deploy, whose
  `get_job_workflow` resolves to the same template, defaults and seed: `keep_output` its mp4. Once
  #618 is on lem, the fixture can't be made honestly, so M-F077 records "fixture missing" and skips.
- `asset:h3-hold/sung-10s.wav`: about 10 s of sung vocals cut from `asset:song/la-vela.mp3`
  (161 s, 44.1 kHz stereo), for M-F081. To make it:
  1. Run a one-step `transcribe_audio` over the song to find a span of about 10 s that is sung
     throughout, with no instrumental gap.
  2. Run an inline `slice_audio` workflow over that span.
  3. `keep_output` the result as that asset, then `delete_output(job_id=<id>)`.
  4. Confirm with `get_gallery_metadata` that it is 9.5–10.5 s long, and with `transcribe_audio`
     that it has words throughout.
- `asset:qa-guides/ep6-22f.mp4` and `asset:qa-guides/ep6-30f.mp4`: 22- and 30-frame, 24 fps
  cuts of `asset:qa-cast/ep6-cold-open.mp4` (shared: 124 frames, 960×544, 24 fps, with audio),
  for the #694 guide-VRAM cases (M-F118 to M-F125 from plan v2). They are the same clips as
  `regression-complete`'s C-F296 fixtures, made again in this workspace so the levels don't share.
  If `list_assets` in `regression-model-specific` lacks either one, make them CPU-only:
  1. `save_workflow(name="m-guide-clips", ...)`, a task-only workflow with two steps:
     - `v22`: `loop_frames(video="asset:qa-cast/ep6-cold-open.mp4", num_frames=22)`;
     - `v30`: `loop_frames(video="asset:qa-cast/ep6-cold-open.mp4", num_frames=30)`.
     Each step writes a 24 fps video file.
  2. `run_workflow(workflow_path="m-guide-clips", acknowledged_cost=true, wait_seconds=55)`.
  3. `keep_output` each mp4 under its asset name.
  4. Confirm with `get_gallery_metadata` that they have 22 and 30 frames at 24 fps.
  5. `delete_output(job_id=<id>)`, then `delete_workflow("m-guide-clips")`.
  The 124-frame guide in those cases is `asset:qa-cast/ep6-cold-open.mp4` itself.

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
`plan.estimate` re-priced for two entries rather than the catalog's five-shot figure — `basis:
"observed"` on this box, `"catalog"` where no comparable run history exists. An `asset:` that
names nothing must still come back as an error at the shot's reference path — the check being
exercised is that a file reference is *resolved*, not that validation waves it through.
Paid form: asserted on M-F020's step 1 job; do not run separately.
It becomes a **finding** if the free form stops validating, or if the run fails on a reference the
validator accepted.
Also assert, from 2026-09-13: `get_workflow("templates/minimax/dialogue-short")`'s **description**
mentions `from_file` with an `asset:` path for a subject reference, *and* (per #122) says an
episode cast entirely from files does not pay for the two Z-Image steps — they save nothing, so
once no shot references them the engine drops them from the run and warns that it did. The
capability being documented is half of what #109 bought; a refactor that keeps the behaviour but
drops the sentence puts the next reader back where this case started, which is why the text is
asserted and not just the behaviour. The `dw:minimax-h3` skill carries the same thing in its
`shots` entry description.
Since #122 landed: the two-entry validate's `plan.elided_steps` names both `draw_character_a` and
`draw_character_b`, each with `overridden_by: "shots"`, and `plan.steps` is reduced accordingly —
the manifest no longer contains portrait entries nothing references.
metrics: paid form only — the job's `started_at`→`finished_at` in seconds (`latency`,
`condition: paid`, two shots), logged to `regression-perf/M-F001.jsonl` and compared against the
`derived` quote it was given as well as its own history. A run that drifts well past its quote is
a finding even if it succeeds — the quote is what a caller budgets on.
cleanup: the free form writes nothing. For the paid form, delete the run's outputs; keep no
fixtures beyond the portrait/voice assets the case needs, which belong in Fixtures if this becomes
a regular run.
source: tester, found while running TESTER_TASK.agent.md on 2026-09-13 (episode 7, job `48000580aec1`,
894.1 s against a 16.8 min `derived` quote, two shots, every reference `from_file`), filed as #109;
paid form re-run the same day as episode 8, job `2df5f1ff06f2`, 756 s. Model `opus` via provider
`anthropic`.

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
`video_shift`, `audio_shift` and `lora_alpha` must all be **declared** keys, not just correctly
valued — `lora_alpha: null` is a declaration (it means "use the file's own"), while a *missing*
`lora_alpha` key is a regression a caller reaching for a checkpoint override would hit silently.
expected:
- **544p FL2VA turbo** — `lora_weight_name: minimax_h3_fl2v_turbo_8step_v1.0_bf16.safetensors`,
  `video_shift: 12.0`, `audio_shift: 3.0`, `lora_alpha: null`, 9 steps. Templates:
  `video-with-audio`, `image-to-video`, `chained-segments`, `enhance-prompt`,
  `enhance-prompt-with-image`, `shots-batch` (all 960x544); `first-and-last-frame`, `last-frame-only` (544x544 —
  same 544 short edge, square because they pin a square still).
- **768p FL2VA turbo** — `lora_weight_name: minimax_h3_fl2v_turbo_8step_v1.0_768p_bf16.safetensors`,
  1344x768, `video_shift: 6.0`, `audio_shift: 3.0`, `lora_alpha: null`, 9 steps. Template:
  `video-with-audio-768p` only. This is the one row whose shift differs; the skill says
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
- Note the asymmetry deliberately, on `reference-to-video` and the rest of the Ref2VA row: a
  768p-trained *Ref2VA* checkpoint stays at shift **12**, not 6 — a run that "helpfully" normalised
  every 768p-trained checkpoint to shift 6 would break it, since 768p does not imply shift 6.
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
matched the three rows above over MCP on that date. Related: #147, #148, #149, #156. Merged with
M-F007 during the 2026-09-22 suite audit — both compared the same three templates' `video_shift`/
`lora_alpha` pairing against the same canonical rows; M-F007's "declared vs. missing key" nuance
and its explicit Ref2VA-asymmetry framing (verified in #147 on that date, workspace `qa-verify`,
all three templates matching) are folded into the bullets above. M-F008 covers the runtime half —
that these numbers actually reach the scheduler, not just the catalog.

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
- **No padding warning** for this direction — the song is longer than the cut, so nothing is padded.
  Headroom warnings naming the raw `write_song` mp3 or a `shot@<entry>` intermediate are expected
  (an un-normalized Music 3 track reaching a saving step is M-F011's `audio_no_headroom` case firing
  as designed) and are M-F011's business, not this case's; only a padding warning here is a finding.
- **No slice-the-song step in the manifest.** The steps are `draw_singer`, `write_song`,
  `slice@<entry>` per shot, `shot@<entry>` per shot, `edit`, `balanced`, `music_video`. A step
  that slices `write_song` to a frame count is the coupling this case exists to keep out.
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

### M-F008 — the 768p H3 path renders at its trained canvas on its trained schedule
`templates/minimax/video-with-audio-768p` pins a combination rather than leaving it to arguments:
the `minimax_h3_fl2v_turbo_8step_v1.0_768p_bf16` checkpoint, 1344x768, `video_shift: 6.0`,
`lora_alpha: null`, `num_inference_steps: 9`. Every one of those has to reach a different part of
the stack — the canvas to the pipeline, the shift to the scheduler, the alpha to the peft layers
after load — and none of them fails loudly if it doesn't. A 768p LoRA run on the 544p sigma
schedule at a stated `alpha: 128` (16x the file's own `alpha: 8`, #468) produces a clip that
completes, saves, and simply looks mediocre. M-F003 pins that the catalog *declares* these
numbers; this case is the other half — that a render on them actually happens. The two together
are why a checkpoint swap can be trusted to be three numbers rather than one.
Model/pipeline: MiniMax-H3 T2VA with `lightx2v/Minimax-h3-Turbo`'s **768p FL2VA** 8-step
checkpoint. Costs one real run, ~13 min cold on a 3090 — model-specific is opt-in, which is where
a render this size belongs.
expected: `run_workflow("templates/minimax/video-with-audio-768p")` on defaults, then
`wait_for_job` / `get_job_events` / `get_gallery_metadata` on the output:
- **`status: "succeeded"`.** Completion is itself the assertion here — see above. `warnings`
  carries **no** headroom entry on a clean run: since the #174 amendment (bbe4adb) the
  pre-encode `audio_no_headroom` check is deferred on a video mux until the post-encode
  probe answers, and this family's mux has always come back clean. It **is** a finding if
  `audio_clipped` appears, if `audio_no_headroom` *and* `audio_clipped` both appear (the
  deferral regressed), or if `get_gallery_metadata`'s `peak_dbfs` on the written file is at
  or above 0 dBFS without `audio_clipped` having fired for it. A lone `audio_no_headroom` is
  worth a note but not a failure — it was the pre-amendment shape.
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
bullet and the audio half of the metadata bullet are mine. `warnings` assertion loosened per Don's
#174 disposition on 2026-09-16 (fix (1)'s post-encode probe is add-only, not replace — the
pre-encode `audio_no_headroom` warning still fires on this family's stock defaults even though the
mux always comes back clean; re-architecting `warn_without_headroom`'s timing to satisfy a strict
`warnings: []` was declined as disproportionate to the actual defect); superseded by the bbe4adb
amendment, see #305. Note for a future run: the **first**
denoise step took ~232 s against ~40-57 s for steps 2-8 — warm-up, not a stall, and the same
pattern C-F023 records after a reload.

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
- **An unwarned file reads below 0 decoded.** That half is the one that catches a clipping
  deliverable reported as clean, and must hold in one direction only. A **warned** file's decoded
  level is not asserted either way: the warning measures the source waveform, and the encode moves
  it by up to ~2 dB in either direction depending on the mux (`regression-perf/M-F012.jsonl` has AAC
  landing under target by -0.92 and -1.11 dB against the +1.94 dB over that #161 first measured on an
  mp3). What must hold on the warned side is only that the warning fires whenever the *source* is at
  or above the -0.5 dBFS threshold, not a sign on the decoded number.
- **A level problem is listed in `findings`.** When a file's level is a problem,
  `get_gallery_metadata` lists it in `findings` with its threshold and fix, without
  restating numbers; a clean file returns `findings: []`.
- **It covers the muxed deliverable, not only the audio file.** On a `music-video` or
  `assemble-and-score` run the warning names the final mp4's soundtrack as well as the
  saved audio. Source and deliverable is the useful pair: #158 was filed because the
  mp4 was the thing at +3.26 and nothing had mentioned it. Confirmed in job
  `089b1e2945d2`: `raw_mux` warned naming the mp4 at +0.8 dBFS and decoded at +0.776,
  `balanced_mux` did not warn and decoded at -0.626.
cleanup: none of its own — it reads a run another case or episode already paid for.
Delete nothing beyond what that run's own cleanup says.
source: tester, model `opus` via provider `anthropic`, verified in #158 on 2026-09-14;
stale-case edit approved by Don on 2026-09-14 (#160); the warned-side direction was dropped
per approval on 2026-09-16 (#173, item 7) once AAC mux measurements showed it unsound
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
`templates/minimax/music` now writes through a `balanced` (`normalize_audio`, -3.0 dBFS
— -1.0 until #362) step with the pipeline step at `save: false`, and
`templates/minimax/music-video` puts the same step between `edit` and the `pair_audio`
mux, also at -3.0. This case pins the *default* path — no arguments beyond a duration,
nothing the caller has to know.
Two things about it are easy to get wrong, and both are the point:
**Do not assert the absence of the warning alone.** `audio_no_headroom` measures the
waveform as written, so it goes quiet the moment a gain step exists — and it would also
go quiet if the check itself broke. The level is the assertion; the warning is
corroboration.
**Do not assert a target level.** The deliverable is mp3, and a lossy encode overshoots
the -3.0 the waveform is normalized to. Measured overshoot has run **0.93 dB and 0.59 dB**
on two Music 3 tracks against the old -1.0 target, and 1.56 dB against -1.0 on the run
that prompted #362 — already most of a -1.0 margin, and enough to clip outright at 1.56.
The -3.0 target moved for exactly that reason; a verifying run at -3.0 still overshot by
~0.96 dB (#362), so the margin is doing its job rather than eliminating overshoot. An
assertion of a specific ceiling below 0 fails against a fix that is working correctly.
Assert strictly below 0, which is what "does not clip" means.
Model/pipeline: MiniMax Music 3. One ~90 s run at `audio_duration: 30`; the
`music-video` half rides on whatever `music-video` render the suite or an episode does
next rather than paying 35 min of its own.
expected: `run_workflow("templates/minimax/music", arguments={"audio_duration": 30})` —
- **The catalog still carries the gain step.** `get_workflow("templates/minimax/music")`
  shows two steps: `generate_music` with `result.save: false`, then `balanced`, a
  `normalize_audio` task at `peak_dbfs: -3.0` whose `result` is what gets written. A
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
a `music-video` run settles that bullet. Logged pass or fail. As with C-F078 the
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
`music-video` bullet was confirmed from a run in #161 (tester, model `opus` via provider
`anthropic`): job `34b5aaa510e5`, 2 shots at `audio_duration: 12`, deliverable at
`peak_dbfs: -3.921`. That fix moved `music-video`'s `balanced` step to **-3.0 dBFS**
(`music` stayed at -1.0 at the time) because the AAC mux overshoots where an mp3 encode
barely does — by 1.94 dB on #161's material, while the same mux landed 0.92 dB *under*
the target on this run's. Material-dependent in both directions, which is why the bullet
asserts strictly below 0 and no target level. #362 (2026-09-23) brought `music` to the
same -3.0 after a 1.56 dB mp3 overshoot against -1.0 nearly clipped a default run;
verified at -3.0 with job `7acc0d169072` (`audio_duration: 60`, `peak_dbfs: -2.04`,
`warnings: []`) — both templates now normalize to -3.0, for the same reason.

### M-F013 — the Ingredients IC-LoRA is named as a download, and a short reference sheet is refused before the weights load
`templates/ltx2/reference-sheet` is LTX-2.5's only reference/identity route (#151), and it is built
on the `Lightricks/LTX-2.5-22b-IC-LoRA-Ingredients` adapter, which the box may or may not hold.
Two things about it are easy to break silently and cheap to check:
1. **The adapter shows up in the plan.** A `loras` entry carries its repo under `model_name`
   directly rather than under `from_pretrained_arguments`, and `_collect_sources` originally walked
   only the latter — so `plan.downloads_required` answered `[]` for exactly the box the field exists
   to warn: one holding every base weight and not the 1.3 GB adapter, which would then be pulled
   mid-run. Fixed in `b599cf3`; the shape of that bug survives any future refactor of the plan
   walker.
2. **The 121-frame reference bucket is enforced at validate.** The Ingredients card requires the
   static sheet to be looped to **at least 121 frames** — shorter breaks the reference encoding
   rather than shortening it, and would otherwise surface as a bad generation after the checkpoint
   is resident.
Model/pipeline: LTX-2.5 + `Lightricks/LTX-2.5-22b-IC-LoRA-Ingredients` (weight 0.9, a preview), via
`templates/ltx2/reference-sheet`. Free — `validate_workflow`, `get_workflow`, `list_models` only,
no GPU.
expected:
- **The adapter is named when absent.** `validate_workflow(name="templates/ltx2/reference-sheet",
  arguments={"reference_sheet": "asset:<any image in the workspace>"})` →
  `valid: true`, and `plan.downloads_required` contains an entry whose `repo` is
  `Lightricks/LTX-2.5-22b-IC-LoRA-Ingredients` — **on a box whose `list_models()` does not list that
  repo**. Check `list_models` first: if the box has since pulled the adapter, an empty
  `downloads_required` is correct and this bullet cannot be exercised, so record that and move on
  rather than filing it.
- **And not named when present.** `validate_workflow(name="templates/ltx2/generative-upscale")` →
  `downloads_required: []` on a box whose `list_models()` *does* list
  `Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler`. This is the pair that distinguishes a
  working walker from one that reports every `loras` entry unconditionally — a fix for the first
  bullet that makes this one non-empty has traded one wrong answer for another.
- **The bound holds on both sides.** `arguments={"reference_sheet": "asset:<any image in the
  workspace>", "reference_frames": 120}` → `valid: false`, one error at `arguments.reference_frames`
  whose text names 121. The same with `"reference_frames": 121` → `valid: true` with
  `checked_arguments` including `reference_frames`. Inclusive at 121; a 121 that refuses is as much a
  finding as a 120 that passes.
- **The catalog carries the rule, not just the validator.**
  `get_workflow(name="templates/ltx2/reference-sheet", variables_only=true)` →
  `constraints.reference_frames.min_frames: 121` with a `reason` mentioning the Ingredients bucket,
  and the defaults are the trained bucket: `width` 768, `height` 448, `num_frames` 121,
  `frame_rate` 24, `lora_scale` 1.0. A default that drifts off that bucket is a finding — the
  weights are trained for it.
- **A missing reference sheet is refused, not silently accepted.**
  `validate_workflow(name="templates/ltx2/reference-sheet",
  arguments={"reference_sheet": "asset:m-f013-never-uploaded.png"})` → `valid: false`, one error
  at `arguments.reference_sheet` naming `m-f013-never-uploaded.png` (#166). An answer of
  `valid: true` here is that bug back. (A bare call with no `arguments` is now `valid: true`: the
  default `asset:reference_sheet.jpg` exists in the common library, dw#450, harnest#47.)
Not covered here: an actual generation. It needs a real reference sheet (a composite panel sheet is
an authoring job, not a fixture this suite can synthesise), and the adapter is an 0.9 preview whose
output quality is a judgement call rather than a pass/fail.
cleanup: none — validation and discovery only, writes nothing.
source: tester, model `opus` via provider `anthropic`, verified in #151 on 2026-09-14 against dw
0.4.0-beta.4 on `lem`. The first and third bullets are the implementer's proposed pair; the
present-adapter contrast and the catalog bullet are mine, because a walker that names every LoRA
unconditionally would pass the proposed pair. The bare-call bullet was added once #166 (the missing
default asset) verified on 2026-09-16; until then it was deliberately left unasserted either way.

### M-F014 — the two restoration IC-LoRAs stay two, and each names its own weight
`templates/ltx2/restore-deblur` and `templates/ltx2/restore-decompression` (#152) are the family's
only non-re-rendering route: the caller's own clip goes in as an in-context reference at
`reference_downscale_factor: 1` and only the defect changes. They are the first templates here whose
reference is a file dw did not generate. Both vendor cards are emphatic that the two are **not**
interchangeable — Deblur is spatial defocus only (it explicitly rules out compression repair), and
Decompression rules out defocus — so the failure this case exists to catch is the two collapsing onto
one adapter, or onto each other, in a refactor. Nothing in a *run* would say so plainly: the wrong
adapter still produces a plausible clip.
Model/pipeline: LTX-2.5 + `Lightricks/LTX-2.5-22b-IC-LoRA-Deblur` and
`…-IC-LoRA-Decompression` (both weight 0.9, previews). Free — `list_workflows`,
`validate_workflow`, `get_workflow`, `get_prompt` only, no GPU.
expected:
- **Both are in the catalog, as shots that need media.** `list_workflows(shape="shot",
  traits="needs-input-media")` lists both. Each carries `constraints.num_frames: "8*n+1, 9+"` and
  traits including `has-audio` + `needs-input-media` but **not** `image-conditioned` — the reference
  is a clip, and a template that claims `image-conditioned` here is mislabelled for a caller
  filtering on it.
- **Each names its own adapter, and only its own.** With a real video asset supplied —
  `validate_workflow(name="templates/ltx2/restore-deblur", arguments={"source_video":
  "asset:<any video in the asset list>"})` → `valid: true`, `checked_arguments` includes
  `source_video`, and `plan.downloads_required` is exactly one entry, repo
  `Lightricks/LTX-2.5-22b-IC-LoRA-Deblur`. The same call against `restore-decompression` →
  exactly one entry, repo `…-IC-LoRA-Decompression`. The cross-product is the finding: either
  template naming the other's repo, naming both, or naming neither. As in M-F013, check
  `list_models()` first — once the box has pulled an adapter an empty `downloads_required` is
  correct for it and that half cannot be exercised; record that rather than filing it.
- **The placeholder default is a guard, not decoration.** `arguments={"source_video":
  "asset:blurry.mp4"}` → `valid: false`, one error at `arguments.source_video` reading "Asset
  'blurry.mp4' not found in …". A caller who ships the template without pointing it at their own
  footage must be stopped at validate, not after the weights load.
- **The trained bucket is on the workflow.** `get_workflow(name="templates/ltx2/restore-deblur",
  variables_only=true)` → `width` 960, `height` 544, `num_frames` 121, `frame_rate` 24.0,
  `lora_scale` 1.0, `prompt` `prompt:ltx2/deblur_dual_panel`, and
  `constraints.num_frames` `{modulus 8, remainder 1, min_frames 9}`. Both cards warn that generating
  far above the bucket weakens the effect, so a default that drifts off it is a finding.
- **The dual-panel prompts exist and keep their trained shape.**
  `get_prompt("ltx2/deblur_dual_panel")` and `get_prompt("ltx2/decompression_dual_panel")` both
  resolve, `intended_model: ltx-2.5`, and each text keeps the two-panel form: a "Reference shows …"
  half, its "DEBLUR" / "ENHANCE QUALITY" instruction, and a closing clause asserting identity,
  framing and background geometry are identical and only the named defect differs. A prompt that
  loses that closing clause is the one way this silently becomes a general re-render.
- **The bare call is refused, not silently accepted.**
  `validate_workflow(name="templates/ltx2/restore-deblur")` with no `arguments` → `valid: false`,
  one error naming the missing default `asset:blurry.mp4` (#166, same behaviour as M-F013).
Not covered here: an actual restoration pass, or the comparison against `templates/ltx2/two-stage`
that #152 originally asked for. Both weights are 0.9 previews and "did it look better per minute" is
a judgement about output, not a pass/fail — that measurement wants a named source clip and committed
GPU time, which no one has assigned.
cleanup: none — validation and discovery only, writes nothing.
source: tester, model `opus` via provider `anthropic`, verified in #152 on 2026-09-14 against dw on
`lem`. Bullets one through three are the implementer's proposed set, tightened: they proposed
checking only that Deblur names Deblur, and a template naming *both* adapters would pass that. The
`8n+1` refusal they also proposed is deliberately **not** repeated here — M-F016 and M-F022 already assert that
rule for LTX-2.5. The bare-call bullet was added once #166 verified on 2026-09-16, same treatment
as M-F013.

### M-F016 — an unsatisfiable Hub-kernel processor is refused at validate time, not 88s into the load
`templates/ltx2/diffusion-decode` is the one LTX-2.5 template whose decoder is
`LTX2VideoVaeNeighborhoodNattenProcessor`, which fetches a prebuilt `na3d` kernel from
`shi-labs/natten` in its constructor. Whether that kernel exists is a property of the box, not of
the workflow: published natten wheels are built per torch version, and `lem` runs a torch the
published set does not cover. The durable rule is not "this template fails" — it is **the answer
arrives before anything loads, whichever way it goes**. Before the #178 fix the template validated
clean and then failed ~88s in, after the transformer and text encoder were already on the GPU.
This is the LTX-2.5-specific instance of the repo's "refuse before cost" convention (#166's
missing-asset refusal, #174's headroom warning), and it is written as source-level (any processor
whose `__init__` calls `get_kernel(`), so a future Hub-kernel-backed processor is covered by the
same check.
Model/pipeline: LTX-2.5 via `templates/ltx2/diffusion-decode` (step index 1, component
`diffusion_decoder`), against `shi-labs/natten`'s published build variants and whatever torch the
server runs. Free — three `validate_workflow` calls plus one `run_workflow` that must never queue.
**This case is box-dependent by design.** Read the outcome, don't assume it:
- **Unsatisfied box** (what `lem` gave on 2026-09-16, torch 2.14 / x86_64 / CUDA):
  `validate_workflow(name="templates/ltx2/diffusion-decode")` → `valid: false` in seconds, with an
  error whose `path` is **`steps[1].pipeline.configuration.components.diffusion_decoder.attn_processor_type`**
  and whose `message` names the processor class, contains **`cannot be used on this machine`**, and
  lists the rejected build variants with the reason per variant (torch-version mismatch, CPU-arch
  mismatch). The variant list is what makes the error self-diagnosing rather than just a refusal —
  a message that drops it is a regression in its own right.
- **Satisfied box** (natten ships a matching build, or the server's torch moves back into range):
  the same call → `valid: true`. That is a pass, not a failure — the check is allowed to say yes.
expected:
- **The verdict is reached without loading weights.** Either branch above must come back in seconds.
  A call that takes ~88s, or that returns `valid: true` and *then* fails inside a run with a natten
  build-variant error, is the original bug back.
- **The run path refuses too, not just the validate tool.** On an unsatisfied box,
  `run_workflow(workflow_path="templates/ltx2/diffusion-decode", acknowledged_cost=true)` → an
  immediate tool error carrying the same message and the same JSON path, **no job queued** (nothing
  new in `list_jobs`), no GPU time spent. Load-bearing: the 88s cost this case exists to prevent was
  paid by callers who skipped `validate_workflow`, so a fix wired only into the validate tool would
  leave the reported bug live.
- **No false positives on the conv-VAE siblings.** `validate_workflow` on
  `templates/ltx2/text-to-video` and on `templates/ltx2/two-stage` → **`valid: true`** both, each
  with a `plan.estimate`. These are the same LTX-2.5 family and the same checkpoints; only the
  diffusion decoder is natten-backed. A check that refuses these has stopped discriminating and has
  taken the whole LTX-2.5 catalog out with it.
- **It doesn't short-circuit the rest of validation.** `validate_workflow(name=
  "templates/ltx2/diffusion-decode", arguments={"num_frames": 10})` → `valid: false` with **two**
  errors present, one at `arguments.num_frames` (the 8*n+1 grid rule) and one at the
  `attn_processor_type` path. The server's "every schema error comes back at once" contract has to
  survive a check that constructs objects; one error swallowing the other is a finding.
It is a **finding** if the verdict starts costing a model load either way, if the run path stops
refusing on an unsatisfied box, if a sibling LTX-2.5 template starts failing this check, if the two
errors stop co-reporting, or if the refusal message loses the class name or the build-variant list.
A `valid: true` on the diffusion-decode template is **not** by itself a finding — check the run
path and the timing before filing, since natten shipping a matching wheel produces exactly that.
cleanup: none — the three validate calls write nothing, and the `run_workflow` call must be refused
before a job exists. If it *does* queue a job, cancel it (`cancel_job`) and file that as the finding.
source: tester, verified in #178, model `opus` via provider `anthropic`, on 2026-09-16 against
`lem`. All four bullets passed on that date with `lem` in the unsatisfied branch (`valid: false`,
torch 2.14 vs natten's 2.11/2.12/2.13 builds). Proposed by the implementer in its hand-off comment;
added here only after running it over MCP. Related: #178, and #153 (the FlexAttention VRAM issue,
which is a different failure in the same template family and not this).

### M-F017 — an in-memory LTX-2.5 audio+video save fits its audio to the frame count, standalone and chained
LTX-2.5 generates its soundtrack alongside the picture and hands the engine both as in-memory
pipeline output (the audio still a torch tensor on the generating device). Two things have gone
wrong on that path in turn: first (#197 as filed) the codec-padding fit applied to file-decoded
audio was never applied to in-memory shots, so a `previous_result:` chain of shots accumulated a
few samples of drift per seam; then the fix for that called a numpy-only pad on the CUDA tensor and
**every** in-memory LTX-2.5 audio+video save crashed — including the stock
`templates/ltx2/text-to-video` alone — with `can't convert cuda:0 device type tensor to numpy`.
This case pins both: the save succeeds, and the muxed audio sits exactly on the frame count.
Model/pipeline: LTX-2.5 (`Lightricks/LTX-2.5-Diffusers` via `LTX2Pipeline`, `output_type "{np}"`),
sdnq uint4 transformer / int8 Gemma as in `templates/ltx2/text-to-video`. Two runs, ~1.5 min and
~2 min warm at 512×320.
1. `run_workflow(workflow_path="templates/ltx2/text-to-video", arguments={"width": 512,
   "height": 320, "num_frames": 49})` (validate first and bind the fingerprint).
2. An inline workflow with **two** `LTX2Pipeline` steps copied from that template's step
   (`shot_a` with `num_frames: 49`, `shot_b` with `num_frames: 65` — different lengths on
   purpose), same 512×320 / `frame_rate 24.0` / seed 7, each with `result: {content_type:
   "video/mp4", fps: 24, subfolder: "intermediate"}`, followed by `cut`: `{"task": {"command":
   "concat_videos", "arguments": {"videos": ["previous_result:shot_a", "previous_result:shot_b"],
   "trim_frames": 0, "fps": 24}}, "result": {"content_type": "video/mp4", "fps": 24, "subfolder":
   "final"}}`. The shots must reach the concat via `previous_result:`, not `output:` — a file
   round-trip takes the decode path and would not exercise the in-memory fit at all.
3. `get_gallery_metadata` on every file in both manifests.
expected:
- Both jobs **succeed** with a full manifest (1 file, then 3 files). A `failed` job whose error
  mentions `numpy.pad`, `Tensor.cpu()` or "can't convert … tensor to numpy" is the #197 regression
  back; an empty manifest on the standalone template is the catalog's main T2V entry broken.
- For every output, `media.duration_seconds` equals `media.frame_count / media.fps` to the
  reported precision: standalone 49 → `2.041667`; `shot_a` 49 → `2.041667`; `shot_b` 65 →
  `2.708333`; `cut` 114 → `4.750000`, with `frame_count` 114 (= 49 + 65, `trim_frames 0`). A
  duration that overshoots the frame count by tens of milliseconds on a shot, or a cut longer than
  the sum of its shots, is the original drift back.
- `media.sample_rate` 48000, `channels` 2 on each — the mux kept the pipeline's native track,
  it didn't resample it to hit the length.
Headroom warnings (`peaks at +0.0 dBFS` / `decodes at +0.27 dBFS`) on `shot_a` and `cut` are the
`fox_dawn_choir` prompt running hot and are expected; they are not part of this case.
cleanup: `delete_output` on both run directories (all four files) — nothing here is a fixture.
source: tester, verified in #197, model `opus` via provider `anthropic`, on 2026-09-17 against
dw `0.4.0-beta.6` on `lem` (jobs `1fdfe227500e` standalone, `bbbe46872e83` chain; all four
durations landed exactly on frames/24). Proposed by the implementer in its hand-off comment;
added here only after running it over MCP.

### M-F018 — every consumer of an in-memory LTX-2.5 shot gets the fitted audio, not just the muxer
M-F017 measures saved mp4s, and a saved mp4's `duration_seconds` is derived from its frame count —
it passed while the in-memory chain still drifted. The third and fourth rounds of #197 were that
gap: the codec-padding fit was computed inside the save and reached only the file (round 3) or
only whichever consumer happened to share the object instance the save had extracted (round 4:
`concat_videos` saw a fitted track while a `gain_audio` reading the *same* `previous_result:shot`
re-extracted the raw, short waveform). This case measures the audio each in-memory consumer is
actually handed, by tapping it with a zero-gain `gain_audio` written as wav — a wav's
`duration_seconds` is sample-derived, so it can't be flattered by a frame count.
Model/pipeline: LTX-2.5 (`Lightricks/LTX-2.5-Diffusers` via `LTX2Pipeline`, `output_type "{np}"`),
sdnq uint4 transformer / int8 Gemma as in `templates/ltx2/text-to-video`. One run, ~2.5 min warm
at 512×320.
1. An inline workflow with **three** `LTX2Pipeline` steps copied from that template's step
   (`shot_a` 49 frames, `shot_b` 65, `shot_c` 33 — different lengths on purpose), 512×320 /
   `frame_rate 24` / seed 11, each with `result: {content_type: "video/mp4", fps: 24, subfolder:
   "intermediate"}`; then `cut`: `concat_videos` over `["previous_result:shot_a",
   "previous_result:shot_b", "previous_result:shot_c"]`, `trim_frames 0`, `fps 24`, saved
   `video/mp4` to `final`; then four taps `tap_a`/`tap_b`/`tap_c`/`tap_cut`, each `{"task":
   {"command": "gain_audio", "arguments": {"audio": "previous_result:<shot_a|shot_b|shot_c|cut>",
   "gain_db": 0, "start_frame": 0, "num_frames": 1, "fps": 24}}, "result": {"content_type":
   "audio/wav", "subfolder": "intermediate"}}`. Every reference must be `previous_result:`, never
   `output:` — a file round-trip takes the decode path and masks exactly what this case checks.
   Use a seed the step cache has not seen (a cached shot is re-read from disk, same masking).
2. `validate_workflow`, bind the fingerprint, `run_workflow`, `wait_for_job`.
3. `get_gallery_metadata` on the four tap wavs and on the `cut` mp4.
expected:
- The job **succeeds** with 8 manifest entries.
- Each tap wav's `media.duration_seconds` equals its source's frames/24 **exactly** at the reported
  precision: `tap_a` `2.041667`, `tap_b` `2.708333`, `tap_c` `1.375`, `tap_cut` `6.125`
  (`sample_rate` 48000, `channels` 2). A per-shot tap a few hundredths short (round 4 read
  `2.01` / `2.69` / `1.33` against those) while `tap_cut` is exact is the object-identity
  regression back: the muxer/concat got the fit and the audio tasks did not.
- The `cut` mp4 reports `frame_count` 147 (= 49 + 65 + 33) and `duration_seconds` `6.125`. Note
  that this line alone proves nothing about the seams — the cut's own save fits the *sum* to 147
  frames — which is why the per-shot taps are the check, not the cut.
Headroom warnings (`peaks at +0.0 dBFS`) on `shot_c`, `cut` and their taps are the
`fox_dawn_choir` prompt running hot and are expected; they are not part of this case.
cleanup: `delete_output` on the run directory (3 shot mp4s, 1 cut mp4, 4 tap wavs) — nothing
here is a fixture.
source: tester, verified in #197 (round 4), model `opus` via provider `anthropic`, on 2026-09-18
against dw `0.4.0-beta.6` on `lem` (job `cda8a63386c8`, run `20260918-183942-cb5722ed`; all four
taps landed exactly on frames/24, where job `04ab218e7640` the round before had the three
per-shot taps short). Proposed by the implementer in its hand-off comment for `complete`;
placed here because it needs LTX-2.5's in-memory audio+video output shape.

### M-F019 — SpeechT5 speaks in the voice of an `asset:` reference clip, on a half-precision pipe
`generate_speech`'s `speaker_embedding` (#223) reduces a reference wav to a speechbrain x-vector
and hands it to SpeechT5 as `speaker_embeddings`. It failed twice before it ever produced audio on
`lem`: first on tensor shape (`(512,)` where the decoder wants `(1, 512)`), then on dtype — the
x-vector was built float32 while the pipe loads fp16 on CUDA, and the decoder prenet's `F.linear`
refused `Float × Half` (job `54c1edef2d04`). Both are silent to a unit test that asserts float32,
so this case runs the real thing and checks that the embedding actually conditions the output.
Model/pipeline: `microsoft/speecht5_tts` via `TextToAudioPipeline`, x-vector encoder
`speechbrain/spkrec-xvect-voxceleb`; needs `device: cuda` (the dtype bug is CUDA-only: a cpu pipe
is float32 and would pass regardless). Reference clips: the shared cast assets
`asset:qa-cast/hal-voice.wav` and `asset:qa-cast/priya-voice.wav` (both in `common/assets`,
reachable from every workspace). ~12 s warm for two steps.
1. An inline workflow with two `generate_speech` steps, identical except for the clip: `{"text":
   "The quick brown fox jumps over the lazy dog near the river bank.", "model_name":
   "microsoft/speecht5_tts", "device": "cuda", "speaker_embedding": "asset:qa-cast/hal-voice.wav"}`
   as `hal`, the same with `asset:qa-cast/priya-voice.wav` as `priya`, each saved `audio/wav` to
   `final`. No top-level seed (SpeechT5's prenet samples anyway).
2. `validate_workflow`, `run_workflow`, `wait_for_job`; `get_gallery_metadata(envelope=true)` on
   both wavs.
3. Adjacent: a one-step workflow with `model_name: "suno/bark-small"` and the same
   `speaker_embedding`; run it and read the job's `error`.
expected:
- Step 1's job **succeeds** with two manifest entries; both wavs report `sample_rate` 16000,
  `channels` 1, `duration_seconds` between 5 and 9, `mean_dbfs` above -35 (speech, not silence).
  A `RuntimeError: mat1 and mat2 must have the same dtype` in the traceback is the dtype bug back;
  a `speaker_embeddings` dimension error at `modeling_speecht5.py` is the shape bug back.
- The two wavs differ in a way a run-to-run resample does not: `peak_dbfs` apart by ≥ 1 dB, or
  `mean_dbfs` apart by ≥ 1.5 dB, or the second-by-second `rms_dbfs` profile places its deepest
  pause in a different second. (On 2026-09-18: hal -6.0 / -27.4 with the pause at s2, priya -7.8
  / -24.9 with the pause at s1–s2; a second hal take landed at -5.8 / -27.6, pause at s2 — the
  same voice is self-consistent to within ~0.3 dB on both figures.) Two wavs that match each other
  as closely as two takes of one voice means the embedding is being ignored.
- Step 3's job **fails** before any model loads (≤ 5 s) with `error` naming the model and the
  argument: `suno/bark-small takes no 'speaker_embedding' - only a SpeechT5 model conditions on an
  x-vector`. A Bark job that *succeeds* with the argument present is the guard gone.
cleanup: `delete_output` on both run directories. The two voice clips are shared cast fixtures
owned by the tester's `qa-cast`, not this suite — leave them.
source: tester, verified in #223, model `opus` via provider `anthropic`, on 2026-09-18 against dw
`0.4.0-beta.6` / transformers 5.16.1 on `lem` (jobs `47a9022d296f` two voices, `aefa805e32ed` hal
control, `c3525c29b650` Bark rejection). Placed here rather than `smoke` because it is tied to one
checkpoint and one encoder and needs a CUDA box for the dtype half to mean anything.

### M-F020 — editing one shot of an identity-referenced H3 `for_each` list re-renders only that shot
The step cache's whole value on a seeded, list-driven template is that fixing one line of one shot
does not pay for the others. Before #253 it never did for any step carrying an image/audio/video
reference: the `MiniMaxH3*Reference` / `LTX2ReferenceCondition` dataclasses are rebuilt fresh from
the source file on every run, wrap `PIL.Image`/array/tensor fields with no value equality, and the
cache's `deep_equal` turned the comparison error into "unequal" — an unconditional miss for exactly
the steps that cost the most. A unit test on the equality helper can pass while a real reference
still misses (the realized value is what matters), so this case runs the real thing.
Model/pipeline: `MiniMaxAI/MiniMax-H3` via `templates/minimax/dialogue-short` (stored `seed` 42),
`device: cuda`. Cast: the shared assets `asset:qa-cast/{priya,hal}-portrait.jpg` and
`asset:qa-cast/{priya,hal}-voice.wav` (in `common/assets`). Paid, ~15 min + ~5 min on an RTX 3090
— opt-in, run it when the step cache, `for_each` expansion, `realize_args`, or the H3 reference
adapters change. Both runs must land on the same worker process (nothing between them, no restart),
since the cache is in-memory and #244 (persistence across a restart) is a separate, parked question.
1. `validate_workflow(name="templates/minimax/dialogue-short", workspace=<this suite's>,
   arguments=A)` where `A` = `character_a_voice`/`character_b_voice` as the two voice assets,
   `seam_fade_ms: 80`, and a two-entry `shots` list — `accuse` (124 frames, both portraits as
   `variable:subject_reference_type` `from_file` refs + both voices as `variable:voice_reference_type`
   refs from the two variables) and `deflect` (124 frames, hal's portrait + `character_b_voice`),
   each with a `subject_definitions:`/`summary:` prompt. Then `run_workflow` with the bound ack;
   `wait_for_job`.
2. Change **only** the spoken line inside `deflect`'s prompt. `validate_workflow` again, same
   name/workspace; then `run_workflow`, `wait_for_job`, `get_job_events(after=-1, limit=14)`.
3. Adjacent: `validate_workflow` a third time with step 2's arguments unchanged.
expected:
- Step 1: `plan.cached_steps: 0`; the job succeeds with no `reused` on any manifest entry.
  - M-F001's paid form, on this job: the concatenated `episode` output is stereo at the shots' own
    sample rate with the expected frame count (2 x `num_frames`), and each shot visibly carries the
    referenced cast. Log its latency to `regression-perf/M-F001.jsonl` per M-F001's `metrics:`.
- Step 2: `plan.cached_steps: 1`. The job succeeds in roughly a third of step 1's time; events show
  `step_start shot@accuse` → `step_end … reused: true` within the first second, its `files`
  naming **step 1's** run dir (`<run-1>/intermediate/…shot@accuse.0-0.0.mp4`), then `shot@deflect`
  through its full denoise and `episode` re-run. `get_job`'s manifest carries `reused: true` on
  `shot@accuse` **only**. `shot@accuse` going through `iteration_start` → `generating` → denoise
  steps is the bug back — and note `phase: cached` at 0.1 s on every step is the *pipeline*
  residency, not step reuse; only `reused` on `step_end`/the manifest counts.
- Step 3: `plan.cached_steps: 3` — every member and the join are held.
- (#255, verified: the cached estimate is `plan.estimate.cached_minutes`; `minutes` is unchanged
  by design. Not asserted here.)
metrics: step 2's job `started_at`→`finished_at` in seconds (`latency`, `condition:
one-shot-cached`), logged to `regression-perf/M-F020.jsonl`. A reading near step 1's full time is
the miss back even if `reused` somehow survived.
cleanup: `delete_output` on both run directories. The cast assets are the tester's `qa-cast`
fixtures — leave them.
source: tester, verified in #253, model `opus` via provider `anthropic`, on 2026-09-20 against dw
`0.4.0-beta.6` on `lem` (jobs `410af2dcc1aa` cold, 877 s; `2493b23f555f` one shot cached, 285 s;
third validate `cached_steps: 3`). Implementer proposed the case in its hand-off; placed here
because it depends on the H3 reference dataclasses and a CUDA box.

### M-F021 — a hot intermediate that a normalizer consumes is not warned about; one nothing re-levels still is
Music 3 always lands at or over full scale, and `templates/minimax/music-video` saves that raw
mp3 (`write_song`, `subfolder: intermediate`) before `balanced` (`normalize_audio`, -3.0 dBFS)
re-levels it into the only deliverable. Until #286 the `audio_no_headroom` check fired on that
intermediate save on every stock run — a warning for a designed-in condition, which trains a
reader to ignore `job.warnings` (the thing #161 was fixing). The fix suppresses the pre-write
(`audio_no_headroom`) and post-write (`audio_clipped`) checks on a save whose result a later
`normalize_audio` or `match_levels` step consumes — and *only* those two tasks: a step that
merely reads the result (a `slice_audio` conditioning read) does not suppress it. This case
pins both halves, because a suppression that widened to "any consumer" would silence the
warning on a genuinely un-normalized clipped save and look identical on the template run.
**Measure the intermediate.** The template half is only evidence if the raw mp3 really is
over -0.5 dBFS — a quieter render would pass the warning check for the wrong reason.
Model/pipeline: MiniMax Music 3 (write_song) + MiniMax H3 `ref2va` (shots). The template half
rides on whatever `music-video` render the suite does for M-F006/M-F012 rather than paying for
its own; the two inline halves are utility-only and take seconds, but need a hot mp3 to read —
use that render's `write_song` intermediate via `output:`.
expected:
- **Template half.** On a `music-video` run (any `shots`/`audio_duration`), `job.warnings`
  carries no entry naming `write_song` — neither `audio_no_headroom` ("peaks at … leaves no
  headroom") nor `audio_clipped`. Corroborate with
  `get_gallery_metadata(<write_song intermediate mp3>).media.peak_dbfs` **at or above -0.5**
  (it was +0.31 on the verifying run) — if it isn't, the half proves nothing; say so and rely
  on the inline halves. The final mp4's `peak_dbfs` stays strictly below 0 (M-F012's bullet).
- **Negative half — a reader is not a normalizer.** Inline workflow, two `task` steps:
  `resave` = `slice_audio(audio: "output:<that write_song mp3>", start_seconds: 0,
  duration_seconds: <the full audio_duration>, sample_rate: 44100)` with
  `result: {content_type: "audio/mp3", sample_rate: 44100, subfolder: "intermediate"}`;
  `reader` = `slice_audio(audio: "previous_result:resave", start_seconds: 0,
  duration_seconds: 2, sample_rate: 44100)`, no `result`. `job.warnings` **must** carry
  `resave: The soundtrack written to … peaks at +N dBFS, which leaves no headroom …`. An empty
  list here is the regression — check the slice's own `peak_dbfs` first (a slice that misses
  the hot part is correctly unwarned; take the whole track).
- **Positive half — a normalizer is.** Same `resave`, then `balanced` =
  `normalize_audio(audio: "previous_result:resave", peak_dbfs: -3.0, sample_rate: 44100)` with
  `result: {content_type: "audio/mp3", sample_rate: 44100, subfolder: "final"}`.
  `job.warnings` is empty; both files are in the manifest.
cleanup: `delete_output` on the two inline runs' folders. The `music-video` render belongs to
whichever case ran it.
source: tester, verified in #286, model `opus` via provider `anthropic`, on 2026-09-21 against dw
`0.4.0-beta.6` on `lem`, workspace `qa-ep28`. Template run `0d21109872ee` (2 shots,
`audio_duration: 12`, 13.0 min): warnings = elision note + #246 fit-trim only; intermediate
`peak_dbfs: +0.305`, deliverable `-4.737`. Negative `37bea958364b` warned (`+0.3 dBFS`); a
first attempt slicing only 6 s (`84a617565b28`, `-1.91 dBFS`) was correctly silent, which is
where the "take the whole track" note comes from. Positive `495f91d39f78`: `warnings: []`.
Implementer proposed the case in its hand-off; placed here because it needs a Music 3 track.

### M-F022 — LTX-2.5 text-to-video refuses a (width, height, num_frames) that cannot fit VAE decode, at validate time
`templates/ltx2/text-to-video` declares a top-level `vram_estimate` (`base_gb` + `bytes_per_voxel`
over `width * height * num_frames`) that `validate_workflow` checks against the template's
`cost[].vram_gb` (24 GB, RTX 3090). Before #265 the frame-count grid rule (`8*n+1`, also M-F016) was the
only bound, so `num_frames: 345` validated clean, ran all eight denoise steps (~5 min of GPU) and
then died in the VAE decoder's conv3d. The ceiling is the "refuse before cost" counterpart to that
rule: a voxel count the decode can't fit is an **error**, not a warning, before anything loads.
Model/pipeline: LTX-2.5 via `templates/ltx2/text-to-video`, RTX 3090's 24 GB `cost` entry. Free —
four `validate_workflow` calls, nothing runs. The calibration numbers (`base_gb`, `bytes_per_voxel`)
are the implementer's to move; this case pins the far side of the ceiling and a known-safe point,
not the exact breakpoint, so a recalibration doesn't turn it into a false finding.
expected:
- `validate_workflow(name="templates/ltx2/text-to-video", arguments={"num_frames": 345})` →
  **`valid: true`**, `checked_arguments: ["num_frames"]`, a `plan.estimate`. 345 is the original
  repro and a confirmed post-#266 pass; a ceiling that refuses it has been recalibrated too tight.
- `validate_workflow(name="templates/ltx2/text-to-video", arguments={"num_frames": 900})` →
  **`valid: false`** with **two** errors: one at `arguments.num_frames` (the `8 * n + 1` grid rule)
  and one at **`arguments`** whose message names the product (`960*544*900`), the projected figure
  (`projects to 28.32 GB VRAM` at the 2026-09-21 calibration — the number may move, the shape
  must not), the declared ceiling (`above the 24 GB declared for RTX 3090`) and `#265`. Both
  errors must co-report; one swallowing the other is the "every schema error at once" contract
  broken.
- `validate_workflow(name="templates/ltx2/text-to-video", arguments={"num_frames": 121, "width": 1920, "height": 1088})`
  → **`valid: false`** with the `arguments` ceiling error and *no* `arguments.num_frames` error —
  the ceiling reads width and height, not only the frame count, and a grid-clean count doesn't
  mask it.
- `validate_workflow(name="templates/ltx2/text-to-video", arguments={"num_frames": 121})` (the
  default) → `valid: true`, no warnings. The check must not touch the template's own default.
It is a **finding** if 900 frames or 1920x1088 validates clean, if the refusal degrades to a
warning, if 345 or the default starts being refused, if the two errors at 900 stop co-reporting, or
if the message loses the product, the projected GB, the declared ceiling or the issue reference.
Covered elsewhere: the `run_workflow` refusal is M-F024 (#265); the H3 templates' declared
ceilings are M-F026 (#324).
cleanup: none — four validate calls, nothing written.
source: tester, verified in #265 (partial verify — this half passed, the run-path and H3 halves
bounced), model `opus` via provider `anthropic`, on 2026-09-21 against `lem` `develop @ d5e3725`.
All four bullets passed on that date (345 → true; 900 → 28.32 GB refusal + grid error; 1920x1088x121
→ 25.08 GB refusal; 121 → true). Implementer proposed the 900/345 pair in its hand-off; added here
only after running it over MCP. Related: #266 (the offload change the calibration rests on).

### M-F023 — LTX-2.5 text-to-video's transformer leaves VRAM before VAE decode, so a 345-frame clip fits a 24 GB card
`templates/ltx2/text-to-video` runs its 12.44 GB transformer under `group_offload` (`block_level`,
one group, streamed) rather than pinning it to `cuda` with `preserve_device_placement`. Before #266
the transformer stayed resident through the decode, and #265's 345-frame repro OOM'd in the VAE's
conv3d with ~11.7 GB free for a decode that needed ~13 GB. This case is the run-path counterpart to
M-F022: M-F022 pins that the ceiling admits 345 frames, this one pins that 345 frames actually
completes — and *why*, so a template edit that quietly re-pins the transformer is caught by the
memory event rather than by a later OOM. Model/pipeline: LTX-2.5 (`Lightricks/LTX-2.5-Diffusers`)
via `templates/ltx2/text-to-video`, RTX 3090 (24.1 GB). **Paid** — ~4 min of GPU cold; the
transformer load dominates, so run it before anything else that would evict it, not after.
expected:
- `run_workflow(workflow_path="templates/ltx2/text-to-video", arguments={"num_frames": 345}, acknowledged_cost=true, wait_seconds=55)`
  then `wait_for_job` until done → `status: succeeded`, one `final/*.mp4` in the manifest, no
  `warnings`, no `error`. An OOM here is the original #265 failure back.
- In `get_job_events`, the `memory` event that immediately follows the `phase: decoding` event
  (right after `pipeline_step` 8/8) has **`gpu_memory_allocated_mb` under 4000** — the transformer
  is off the card going into decode. The 2026-09-21 reading was 2163 MB; ~14 GB at that point means
  the transformer is resident again, which is the bug, even if the run happens to survive.
- The eight `pipeline_step` events are evenly spaced: the gap between consecutive ones is within
  ~10% of the 13.1–13.2 s baseline (2026-09-21, uint4 transformer). A large jump means the
  group_offload has turned into per-step leaf streaming (`num_blocks_per_group` collapsed) — the
  throughput cost the whole-transformer group was chosen to avoid.
- The post-`workflow_end` `memory` event shows allocated back near the idle floor (~1.75 GB on
  2026-09-21), not the transformer's 12 GB — nothing leaks past the job.
It is a **finding** if the run fails with OOM, if the decode-entry `gpu_memory_allocated_mb` is
above ~4000, if a denoise gap exceeds the baseline by more than ~10% without a diffusers/torch
upgrade explaining it, or if the transformer is still resident after `workflow_end`.
metrics: `denoise_step_seconds`, condition `uint4`, unit `s` — the mean gap between consecutive
`pipeline_step` events (steps 1→8), from the job's own `at` timestamps; and `decode_entry_allocated`,
condition `-`, unit `MB` — `gpu_memory_allocated_mb` from the `memory` event following
`phase: decoding`. Both logged to `regression-perf/M-F023.jsonl`, pass or fail.
cleanup: `delete_output(job_id=<the run's job id>)` — the run directory goes whole; keep it only
if the run failed and an issue needs the traceback.
source: tester, verified in #266, model `opus` via provider `anthropic`, on 2026-09-21 against
`lem` `develop @ d5e3725`: job `cb2f0aeb0609` succeeded in 243 s; decode-entry allocated 2163 MB
(free 12759 MB); steps at 13.1–13.2 s; post-job allocated 1750 MB. Implementer proposed the
345-frame run in its hand-off; the memory-event bullets are the tester's, added only after reading
them over MCP. Related: #265 (M-F022, the validate-time ceiling).

### M-F024 — LTX-2.5 text-to-video refuses an over-ceiling (width, height, num_frames) on `run_workflow` too, before anything loads
The `vram_estimate` ceiling M-F022 pins at validate time is also enforced at run time, beside
`apply_constraints` in the workflow's prepare step — so a caller that skips `validate_workflow`
(or folds its arguments differently) is refused on submission, not 5 minutes later in the VAE.
Before the second half of #265 landed, `run_workflow` with the same arguments `validate_workflow`
refused returned `status: running` and began loading the transformer. This case pins that the run
path and the validate path refuse the same thing with the same message, and that the refusal
happens before a run directory or a load phase exists. Model/pipeline: LTX-2.5 via
`templates/ltx2/text-to-video`, RTX 3090's 24 GB `cost` entry. Effectively free — the two refused
submissions fail in under 3 s with no model load; the one accepted submission is cancelled during
its load phase (~90 s wall, a cooperative cancel waits for the load to reach a boundary).
expected:
- `run_workflow(workflow_path="templates/ltx2/text-to-video", arguments={"num_frames": 353}, acknowledged_cost=true, wait_seconds=20)`
  → **`status: failed`** within the wait, **`run_id: null`**, an empty `manifest`, and `job.error`
  beginning `Workflow execution error:` followed by the *same* ceiling message `validate_workflow`
  reports for these arguments (the product `960*544*353`, `projects to … GB VRAM`, `above the
  24 GB declared for RTX 3090`, `#265`). `progress.phase` must be null — no `loading` ever began.
  353 is the first grid point past the confirmed-safe 345, so it sits just over the ceiling at the
  2026-09-21 calibration; if a recalibration admits it, move to the next refused grid point rather
  than calling this a finding.
- `run_workflow(workflow_path="templates/ltx2/text-to-video", arguments={"num_frames": 121, "width": 1920, "height": 1088}, acknowledged_cost=true, wait_seconds=15)`
  → **`status: failed`**, `run_id: null`, the `1920*1088*121` ceiling message — the run-time gate
  reads width and height, not only frames, same as the validate-time one.
- `run_workflow(workflow_path="templates/ltx2/text-to-video", arguments={"num_frames": 345}, acknowledged_cost=true, wait_seconds=6)`
  → **`status: running`**, a non-null `run_id`, `progress.phase: "loading"` — the confirmed-safe
  point is *not* over-refused by the run-time gate. Then `cancel_job(job_id)` and `wait_for_job`
  until `status: cancelled`; the job isn't meant to finish (M-F023 is the case that runs it out).
It is a **finding** if 353 or 1920x1088 comes back `running`/`queued` (or reaches a `loading`
phase, or gets a `run_id`) before failing, if the run-time error text differs from the
validate-time text for the same arguments, if it degrades to a `warnings` entry on a running job,
or if 345 is refused on submission.
cleanup: `delete_output(job_id=<the 345-frame job's id>)` — the cancelled run leaves a run
directory; the two refused jobs have none (`run_id: null`), nothing to delete for them.
source: tester, verified in #265 (the run-path half; the H3 half split to #324), model `opus` via
provider `anthropic`, on 2026-09-21 against `lem` `develop @ 7e1a1a5`: job `1ba74592fb81` (353)
failed in 2.9 s and `872838db5cb7` (1920x1088x121) in 0.3 s, both `run_id: null` with the
validate-time message verbatim; `c84504466b5c` (345) entered `loading` and was cancelled.
Related: M-F022 (the same ceiling at validate time), M-F023 (345 frames running to completion).

### M-F025 — the unquantized FLUX templates offload, so they load on the 24 GB card they ship for
`templates/prompt-weighting` (FLUX.1-schnell, bf16) and `templates/step-caching` (FLUX.1-dev, bf16)
are the two catalog templates that load a full-precision FLUX pipeline without quantizing it. Before
#318 neither carried an `offload` key, so `place_component` moved the whole pipeline onto the GPU in
one piece and OOM'd ~26 s in, still in `phase: loading`, on lem's RTX 3090 (23.56 GiB) — a stock
template that could never run on the box it ships with. The fix gave both `offload: model`, the
pattern the sibling FLUX templates (`lora`, `lora-styles`, `ip-adapter`, `image-variation`,
`image-to-image`) already use. This case pins that both templates get through `loading` and produce
an image; a template edit that drops the offload (or a `place_component` change that ignores it)
comes back as the OOM. Model/pipeline: `black-forest-labs/FLUX.1-schnell` and
`black-forest-labs/FLUX.1-dev` via `FluxPipeline`, RTX 3090 (24 GB). **Paid** — ~80 s of GPU each,
cold; run with the card otherwise idle so a leftover from an earlier case can't be mistaken for
the regression.
expected:
- `run_workflow(workflow_path="templates/prompt-weighting", arguments={"prompt": "a (red:1.4) apple on a wooden table"}, acknowledged_cost=true, wait_seconds=55)`
  then `wait_for_job` until done → `status: succeeded`, no `error`, no `warnings`, one
  `final/*.jpg` in the manifest. The `still_running` reply at 55 s should already show
  `phase: generating` with `denoise_step` moving — `loading` is where the bug lived.
- `run_workflow(workflow_path="templates/step-caching", acknowledged_cost=true, wait_seconds=55)`
  with its defaults, then `wait_for_job` until done → `status: succeeded`, no `error`, no
  `warnings`, one `final/*.jpg`.
It is a **finding** if either job fails with `CUDA out of memory` (in any phase, but `loading`
is the original), if either fails to leave `phase: loading` within ~55 s while the card is
otherwise idle, or if either finishes with a non-empty `warnings` about device placement.
cleanup: `delete_output(job_id=<each run's job id>)` — both run directories go whole; keep one
only if it failed and an issue needs the traceback.
source: tester, verified in #318, model `opus` via provider `anthropic`, on 2026-09-21 against
`lem` `develop @ 7e1a1a5`: job `0f82bac02a68` (prompt-weighting) succeeded in ~78 s and
`0e4e39a8a70d` (step-caching) in ~75 s, both cold, no OOM. The implementer proposed the case in
its hand-off; both runs were confirmed over MCP before it was added.

### M-F026 — the 768p H3 template refuses a frame count its VRAM ceiling cannot fit, and declares a cost
The H3 counterpart to M-F022. Before #324 none of the MiniMax H3 `shot` templates carried a `cost`
array or a `vram_estimate`, so `templates/minimax/video-with-audio-768p` at `num_frames: 345` (the
family's own grid ceiling, LTX-style `17*n+5`) validated clean and OOM'd mid-denoise on lem's
RTX 3090 (job `282172105da1`: 20.25 GiB allocated + a refused 5.57 GiB). The fix declared
`cost: [{cuda, RTX 3090, vram_gb: 24, minutes: 9.87}]` and a `vram_estimate` (`base_gb` +
`bytes_per_voxel` over `width * height * num_frames`, fitted from that OOM and the 960x544x124
image-to-video point) on five templates: `video-with-audio-768p`, `video-with-audio`,
`reference-to-video`, `enhance-prompt` (cost + estimate) and `storyboard` (estimate only, cost was
already curated). Model/pipeline: MiniMax H3 via `templates/minimax/video-with-audio-768p` at its
1344x768 canvas. Free — validate calls only. As in M-F022, the calibration constants are the
implementer's to move; this pins the far side of the ceiling and a known-safe point, not the
breakpoint (which sat between 277 and 294 frames at the 2026-09-21 calibration).
expected:
- `validate_workflow(name="templates/minimax/video-with-audio-768p", arguments={"num_frames": 345})`
  → **`valid: false`**, one error at path **`arguments`** whose message names the product
  (`1344*768*345`), the projected figure (`projects to 25.82 GB VRAM` at the 2026-09-21
  calibration — the number may move, the shape must not), the declared ceiling (`above the 24 GB
  declared for RTX 3090`) and `#324`. No `arguments.num_frames` grid error — 345 is on-grid.
- `validate_workflow(name="templates/minimax/video-with-audio-768p")` (the 124-frame default)
  → `valid: true`, no warnings, a `plan.estimate` with `minutes` set. The check must not touch
  the template's own default.
- `validate_workflow(name="templates/minimax/video-with-audio-768p", arguments={"num_frames": 243})`
  → `valid: true` — a mid-range count well under the ceiling must not be refused.
- `list_workflows(shape="shot", traits="has-audio")` → `details["templates/minimax/video-with-audio-768p"].cost`
  is a one-entry list with `device: "cuda"`, `vram_gb: 24` and a numeric `minutes`; the same for
  `video-with-audio`, `reference-to-video`, `enhance-prompt` and `storyboard` (`cost` not null on
  any of the five).
It is a **finding** if 345 validates clean on the 768p template, if the refusal degrades to a
warning or lands at `arguments.num_frames` instead of `arguments`, if the default or 243 starts
being refused, if the message loses the product, the projected GB, the ceiling or the issue
reference, or if any of the five templates' `cost` goes back to null. The 11 H3 shot templates left
undeclared in #324 (`image-to-video`, `first-and-last-frame`, `chained-segments`, …) validating
clean at 345 is *not* a finding of this case — add them here when they get declared and verified.
cleanup: none — validate/list calls only, nothing written.
source: tester, verified in #324, model `opus` via provider `anthropic`, on 2026-09-21 against
`lem` `develop @ 8459606` (cd34174 deployed). All four bullets passed on that date (345 → 25.82 GB
refusal; default, 124, 243, 260, 277 → true; 294 → 24.41 GB refusal; five `cost` entries present).
The implementer proposed the 345 bullet in its hand-off; added only after running it over MCP.
Related: #265 (LTX2 half, M-F022), #266.

### M-F027 — `dialogue-short` releases MiniMax-H3 after its last shot, before `concat_videos` assembles the cut
In `templates/minimax/dialogue-short` the `shot` step (a `for_each` over `variable:shots`, MiniMax-H3
via ModularPipeline) sets `"release_pipeline": true`. `for_each` carries that onto the last member
only, so H3 loads once, is reused by every later member, and is freed before `episode`
(`concat_videos`, `gather:shot`) runs. Before #344 the ~50 GB H3 stayed resident through the
assembly and a long `shots` list was OOM-killed. Model/pipeline: MiniMax-H3 via
`templates/minimax/dialogue-short` (Z-Image for the two `draw_character_*` steps). **Paid**: about
15 min of GPU for two 124-frame shots.
expected:
- `get_workflow("templates/minimax/dialogue-short")` → the `shot` step has `"release_pipeline": true`.
- `run_workflow(workflow_path="templates/minimax/dialogue-short", arguments={"num_inference_steps": 8,
  "shots": <two entries in the shape the listing's `lists` declares, one per character reference>},
  acknowledged_cost=true, wait_seconds=55)`, then `wait_for_job` until done → `status: succeeded`,
  one `final/*.mp4`, no `error`. A non-default `num_inference_steps` keeps a step-cache hit from
  serving the shots without loading H3.
- In `get_job_events`, the second `shot@` member reports phase `cached`, meaning H3 was reused, not
  reloaded.
- There is exactly one `pipeline_released` event for `shot`, on the **last** member. It comes
  **before** `episode`'s `step_start`, and the `memory` event right after it shows
  `gpu_memory_allocated_mb` in the tens of MB (10.7 MB on 2026-09-22). If no release happens, or it
  happens after `episode` starts or on the first member, that is the #344 bug back.
It is a **finding** if the run is OOM-killed, if `release_pipeline` is gone from the template, if
the release is missing or out of order, or if a later member reloads H3.
Host RSS is asserted by M-F030 on the same job (#368, verified).
cleanup: after M-F030 has read this job, `delete_output(job_id=<the run's job id>)` removes the run directory whole. Keep it only if
the run failed and an issue needs it.
source: tester, verified in #344, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-22
against `lem` `develop @ e5bfb9e`: job `41e3ced1c3ce` succeeded in ~867 s. `shot@react` was
`cached`; `pipeline_released` (seq 121, +863.9 s, GPU allocated 257.8 → 10.7 MB) preceded
`episode` `step_start` (seq 127, +864.9 s). Related: #368 (host RSS).

### M-F028 — `restore-faces` runs on its defaults, with no `low_cpu_mem_usage: false` in its `generate` step
`templates/restore-faces` generates with Z-Image Turbo (`Tongyi-MAI/Z-Image-Turbo`, `ZImagePipeline`,
bf16), then runs the `restore_faces` task (GFPGAN, `leonelhs/gfpgan` / `GFPGANv1.4.pth`). Before #346
its `generate` step's `from_pretrained_arguments` carried `"low_cpu_mem_usage": false`, which diffusers
refuses when parallel loading is on (dw's server default). The job died ~6 s in with `Parallel loading
is not supported when not using low_cpu_mem_usage.`, and validate passed it. It was the only catalog
template with that key, so a template author copying its old form would bring the failure back.
**Paid**: about 40 s of GPU, warm.
expected:
- `get_workflow("templates/restore-faces")` → `steps[0].pipeline.from_pretrained_arguments` has no
  `low_cpu_mem_usage` key, or has it set to `true`.
- `validate_workflow(name="templates/restore-faces", arguments={})` → `valid: true` (the no-seed
  step-cache warning is expected).
- `run_workflow(workflow_path="templates/restore-faces", arguments={}, acknowledged_cost=<bound plan>,
  wait_seconds=55)`, then `wait_for_job` if still running → `status: succeeded`, `warnings: []`, no
  `error`. The manifest has two steps: `generate` (one `intermediate/*.jpg`) and `restore` (one
  `final/*.jpg`).
It is a **finding** if the run fails with the parallel-loading `NotImplementedError` or any load-time
error, or if `low_cpu_mem_usage: false` reappears in the template.
cleanup: `delete_output(job_id=<the run's job id>)` removes the run directory whole.
source: tester, verified in #346, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-22
against `lem` `develop @ e5bfb9e`: job `ef9c0e9cc3ff` succeeded in ~40 s. The implementer proposed
the case in its hand-off, and it was added only after that run.

### M-F029 — a resident H3 `for_each`'s host-memory projection fits base + marginal, not whole peak × entries
Depends on MiniMax H3 (t2va, 544p turbo LoRA) history, not on a fixture in this suite's workspace:
`acorn-wars/shots-batch` in workspace `acorn-wars` is a resident `for_each: "variable:shots"` over
one H3 step, and its runs cover two list lengths (1 and 5 entries; 7 runs as of 2026-09-22). Before
#348, `validate_workflow` divided the whole observed peak by entry count, then multiplied it back out,
so 5 entries projected ~305 GB against a measured ~62 GB. **Free**: validation only, no run.
`use_workspace("acorn-wars")` (the `workspace=` argument on `validate_workflow` does not resolve a
workspace-stored workflow name), then:
1. `validate_workflow(name="acorn-wars/shots-batch", arguments={shots: [5 entries of {name, prompt,
   num_frames: 158}]})`;
2. the same call with 12 entries.
expected: both return `valid: true` and exactly one warning each, beginning `Projected host memory
for this run (~N MB at <5|12> entries, extrapolated from runs of 1 and 5 entries)`. N at 5 entries
should be within ~10% of the largest single 5-entry run's peak (~61.6 GB on lem, 2026-09-22). It must
not be near 5 × the per-entry figure (~300 GB), and the text must not say `held resident together`.
N at 12 entries must stay bounded by the base + slope fit. On 2026-09-22 it was flat at ~61.6 GB,
nowhere near 12 × 12 GB. It is a **finding** if either N is several times the measured single-run
peak, if the old wording comes back, or if `valid: false` (warn became refuse). If `acorn-wars`
history is gone, or no longer spans two list lengths, the case can't run. Report it as skipped, not
failed.
metrics: `projected_mb_5` (N from call 1).
cleanup: none (validation only); `use_workspace` back to this suite's workspace.
source: tester, verified in #348, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-22
against `lem` `develop @ e5bfb9e`.

### M-F030 — releasing a pipeline mid-job returns its host memory, not only at job end
Uses the same run as M-F027: `templates/minimax/dialogue-short` with MiniMax-H3 via ModularPipeline,
Z-Image Turbo for the two `draw_character_*` steps, two 124-frame `shots`, and
`num_inference_steps: 8`. Run this on M-F027's job; do not start a second one. `release_pipeline` frees the GPU, but
before #368 the host side (torch's pinned-host cache and glibc malloc arenas) was returned only by
`clear_memory`, and later only at job end. So `episode` (`concat_videos`) assembled the cut with
~10–15 GB of dead H3 residue still resident, and a released Z-Image left ~4 GB under the H3 load.
**Paid**: about 12–15 min of GPU.
expected (all readings are `host_memory_rss_mb` on `get_job_events` `memory` events; no
`clear_memory` call anywhere in the case):
- Take the `memory` event at `shot@<first>` start (phase `loading`, before H3 loads) as the
  baseline B. That event comes right after `draw_character_b`'s `pipeline_released`, so B is
  already post-Z-Image-release, and it should be a few GB at most (1,906 MB on 2026-09-23).
- The `memory` event right after `pipeline_released` for the **last** `shot@` member is within
  ~2 GB of B (+210 MB on 2026-09-23). The `memory` events during `episode` (phase `task`
  `concat_videos`, then `saving`) stay at that level.
- Idle `get_memory` after the job (`live: true`, `run_count` ≥ 1) is also within ~2 GB of B.
- The second member's generating-start and decode-start readings are not materially above the
  first member's (no per-member accumulation).
It is a **finding** if RSS after the last release, or during `episode`, sits ≥ 5 GB above B (the
#368 residue coming back, 16.8 GB on the unfixed server). It is also a finding if the drop only
appears after `workflow_end`, or if idle RSS after the job stays high until a `clear_memory`.
metrics: `rss_after_release_delta_mb` (RSS right after the last `shot@` `pipeline_released`, minus B).
cleanup: `delete_output(job_id=<the run's job id>)` removes the run directory whole (shared with
M-F027 if run together).
source: tester, verified in #368, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-23
against `lem` `develop @ 8e90e32`: job `66256e4ffbea` succeeded in 743 s. B = 1,906 MB (seq 47);
after `shot@react` release 2,116 MB (seq 114); `episode` 2,434–2,440 MB; idle after job 2,119 MB.
The implementer proposed the case in its hand-off, and it was added only after that run.

### M-F031 — a chained-segments LTX run records one shot per segment
source: tester, spec for #385 from #378's plan v2
Output assessment, stage A: the `AudioVideo.shots` that `run_chain` fills. A
chained-segments run has one shot per segment, and the shots' frame counts sum to the
frames in the file. It needs GPU time on LTX-2. Keep it small:
`run_workflow(workflow="templates/ltx2/chained-segments", arguments={"width": 512,
"height": 320, "num_frames": 25, "segments": 3, "seed": 7}, acknowledged_cost=true,
wait_seconds=55)`, then `wait_for_job` until it finishes. `num_frames` must be 8n+1.
Run `validate_workflow` first and quote its estimate. Keep the template's own `image`
and `prompt`.
expected:
- `succeeded`. `get_gallery_metadata(<final video>)` has `media.shots` with exactly 3
  entries (one per segment), in order, with rising starts. Their frame counts sum to the
  file's `frame_count`, however much the chain overlaps or trims its segments.
- `get_output_frames(name=<final video>, seams=true)` with no `boundaries` returns 2
  seams, at the recorded shot starts 2 and 3. It is not a 400.
It is a **finding** if `shots` is missing or its count isn't 3, if the frame counts
don't sum to the file's frames, or if `seams=true` still needs `boundaries`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### M-F032 — casting an H3 short from files actually skips the portrait steps
`templates/minimax/dialogue-short` can be cast from portraits that already exist: a
shot entry's subject reference takes `from_file: "asset:..."` exactly as its voice
references do. Before #122 the two Z-Image `draw_character_a` / `draw_character_b`
steps still ran and their output was discarded — about 55 s and two model loads
bought and thrown away on every episode, with no argument a caller could pass to
avoid it. A recurring cast is the headline use of this template, so the saving is the
feature, and it is invisible from the deliverable: a cast run and an uncast run
produce the same kind of file. S-F027 pins the *engine's* elision cheaply; this case
pins that this template is actually wired to benefit, which takes a real run.
expected:
- **Before the run, which is the part the cost acknowledgement depends on.**
  `validate_workflow(name="templates/minimax/dialogue-short", workspace=<one that can
  reach the cast>, arguments={<voices>, "shots": [entries whose subject references use
  `from_file: "asset:<portrait>"`]})` → a `plan` whose `elided_steps` names
  **both** `draw_character_a` and `draw_character_b`, each with a reason, and whose
  `steps` is reduced accordingly (2 for a one-entry `shots` list, against 8 for the
  stock five-shot default). The count a caller acknowledges must be the count that runs.
- **The run.** That workflow run for real → `succeeded`, with both draw steps named in
  the job's **`warnings`** as not having run, each naming the argument that overrode them
  (`overridden_by`, and `kind: "step_elided"` on the matching `warning` event). Per #157
  the wording must **not** suggest a misspelled reference or a missing `result` when the
  step was elided because an argument was supplied — that is the happy path, not a
  suspected fault.
- **Neither portrait is written.** The manifest contains only the shot(s) under
  `intermediate/` and the assembled episode under `final/` — no Z-Image output.
- **No Z-Image is ever loaded.** `progress` / `get_job_events` go straight to the first
  shot step with `phase_detail` naming the H3 pipeline. There must be no `loading`
  phase for the portrait model at all: a run that loads the weights and then discards
  the image has not saved the expensive half.
- **Control — the uncast default is unchanged.** `validate_workflow` on the same
  template with **no** `shots` override → `steps: 8`, `elided_steps: []`,
  `list_entries.shots: 5`. Both draw steps still run for a caller who did not supply
  portraits, because the stock shots reference them. This control is the whole safety
  margin: elision that fired here would silently break the default deliverable.
- The template's `save: false` on the two draw steps is what lets elision reach them
  (the engine keeps any step that saves — S-F027 guardrail 1), so the cast validate
  above is itself the check that the template half is still in place.
cleanup: delete the cast run's outputs (sweeps its run directory). Keep the cast
assets — portraits and voice clips are durable fixtures.
source: tester, model `opus` via provider `anthropic`, verified in #122 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep11` (job `af59273620ae`, run
`20260914-044007-369fdaf5`, one-entry `shots` cast from
`asset:qa-cast/{priya,hal}-portrait.jpg`, succeeded in 535.8 s against an 8.4 min
`derived` estimate; both draw steps warned, manifest two entries, first `loading`
phase was `pipeline: MiniMaxAI/MiniMax-H3`). Proposed by the implementer in that
issue; the one-entry `shots` list is mine, to buy the same evidence for a quarter of
the five-shot price.
source: moved from C-F021 (curation 2026-09-24)

### M-F033 — each LTX-2.5 chained segment's audio spans its own frames, so sync doesn't drift per segment
source: tester (`claude-opus-5-5` via `anthropic`), verified in #408
The `chain:` pipeline-processor route behind `templates/ltx2/chained-segments` fits each
segment's generated audio to that segment's frame count before trimming, joining or
spilling it. Before #408, each segment came out ~31.7 ms short (48480 samples against
25 frames), and the shortfall added up once per segment (-95 ms over 3). The job
raised no warning. Only `assess_output` saw it. It needs GPU time on LTX-2, about
20-40 s at this size. Keep it small:
`run_workflow(workflow_path="templates/ltx2/chained-segments", arguments={"width": 512,
"height": 320, "num_frames": 25, "segments": 3, "seed": 7}, acknowledged_cost=true,
wait_seconds=55)`, then `wait_for_job` until it finishes. `num_frames` must be 8n+1.
Keep the template's own `image` and `prompt`. Then call
`assess_output(name=<final video>, probe="analyze_sync_drift")`.
expected:
- `succeeded`, no `warnings`. Each manifest `shots` entry's `num_samples` equals
  `num_frames` × 48000 / 24: 25 → 50000 and 23 → 46000 (twice).
- `analyze_sync_drift`: every shot's `end_offset_ms` is within 1 ms of 0,
  `|length_delta_ms|` < 1, and `findings` is empty (no `sync_drift`, no `sync_length`).
It is a **finding** if any segment's samples fall short of its frames, or if the offsets
grow from segment to segment.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### M-F034 — `templates/ltx2/keyframes` runs on its own default keyframe images
`templates/ltx2/keyframes` builds two `LTX2VideoCondition(frames=...)` via `from_arguments`. `frames`
is image-or-video, so key-based media auto-loading never applies to it. Before #431 the template's
`first_image`/`last_image` defaults were bare `{"location": ...}` dicts. They reached diffusers
unloaded, so every run failed with `Unsupported \`frames\` type for condition 0: <class 'dict'>`,
while validate reported the plan clean. The fix made the variables plain strings and wrapped each
condition's `frames` as `{"media_type": "image", "location": "variable:..."}`.
**Paid**: about 100 s of GPU cold (LTX-2.5 load), ~10 s warm.
expected:
- `validate_workflow(name="templates/ltx2/keyframes", arguments={"num_frames": 9})` → `valid: true`.
- `run_workflow(workflow_path="templates/ltx2/keyframes", arguments={"num_frames": 9},
  acknowledged_cost=<bound plan>, wait_seconds=55)`, then `wait_for_job` if still running →
  `status: succeeded`, no `error`, and the manifest has one `keyframes_to_video` step with one
  `final/*.mp4`.
It is a **finding** if the run fails with an `Unsupported \`frames\` type` error or any other error
before the mp4 is written.
cleanup: `delete_output(job_id=<the run's job id>)` removes the run directory whole.
source: tester, verified in #431, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-25
against `lem` `develop @ 5f2a766`: job `6e21948f98d7` succeeded cold in ~96 s. The implementer proposed
the case for smoke. It lives here because it loads LTX-2.5.
metrics: none.

### M-F035 — `LTX2InContextPipeline` refuses an unknown component name at validate time, and the IC-LoRA templates carry none
Before #442, `restore-decompression`, `restore-deblur` and `reference-sheet` configured a `duration_head`
component that `LTX2InContextPipeline` (LTX-2.5 IC-LoRA) does not register. Each validated clean and then
died about 2 minutes into `loading` with `LTX2InContextPipeline has no component 'duration_head'`. The fix
removed the entry and made validate check `configuration.components` names against the pipeline class.
**Free**: validate only.
expected:
- `validate_workflow(workflow={"id": "m-f035-probe", "steps": [{"name": "restored", "pipeline":
  {"configuration": {"component_type": "LTX2InContextPipeline", "components": {"vae": {"device": "cuda"},
  "duration_head": {"device": "cuda"}}}, "from_pretrained_arguments": {"model_name":
  "Lightricks/LTX-2.5-Diffusers", "torch_dtype": "torch.bfloat16"}, "arguments": {"prompt": "a cat",
  "num_frames": 9}}, "result": {"content_type": "video/mp4"}}]})` → `valid: false`, with exactly one error at
  `steps[0].pipeline.configuration.components.duration_head` naming `LTX2InContextPipeline` and
  `duration_head`. `vae` is not flagged.
- `validate_workflow(name=...)` with default arguments, for each of `templates/ltx2/restore-decompression`,
  `templates/ltx2/restore-deblur` and `templates/ltx2/reference-sheet`: no error under
  `steps[*].pipeline.configuration.components`. An error about a default `asset:` input missing from the
  workspace is not a finding.
It is a **finding** if the probe validates clean, or if any of the three templates reports a component error.
cleanup: none (nothing is queued or written).
source: tester, verified in #442, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-25 against
`lem` `develop @ f66edcd`. The implementer proposed the template half. The probe half covers the new
validate rule.
metrics: none.

### M-F036 — `templates/ltx2/reference-sheet` runs on its own default sheet and renders a picture, not blocky mush
Before #444, `loop_frames` handed `LTX2ReferenceCondition.frames` a uint8 `[0,255]` array. Diffusers
normalizes that as `2*x-1` without a `/255`, so the LTX-2.5 Ingredients IC-LoRA encoded garbage. Every run
"succeeded" with `warnings: []`, but each frame was ~32 px blocks of dark blue and orange. The template's
default `asset:reference_sheet.png` also did not exist, so it could not run stock. The fix scales
`loop_frames` to float `[0,1]` and ships a stock sheet as `asset:reference_sheet.jpg` in `common/assets`.
**Paid**: about 2.5 min of GPU (LTX-2.5 + Ingredients IC-LoRA load).
expected:
- `validate_workflow(name="templates/ltx2/reference-sheet", arguments={"seed": 72})` → `valid: true`, with
  no asset-not-found error.
- `run_workflow(workflow_path="templates/ltx2/reference-sheet", arguments={"seed": 72},
  acknowledged_cost=<bound plan>, wait_seconds=55)`, then `wait_for_job` until finished → `status:
  succeeded`, and one `final/*.mp4` from the `shot` step.
- `get_output_frames(name=<that mp4>, at=[0.5, 2.5, 4.5])` → each frame is a recognisable scene: a
  woman at a workshop bench, matching the stock sheet's woman / pocket-watch / workshop panels.
It is a **finding** if validate can't resolve the default sheet, or if the frames are blocky, abstract
colour fields with no recognisable figure or setting, whatever `status` and `warnings` say.
cleanup: `delete_output(job_id=<the run's job id>)` removes the run directory whole.
source: tester, verified in #444, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-25 against
`lem` `develop @ 3a28146`: job `432477f376e6` succeeded in ~2.4 min with coherent frames.
metrics: none.

### M-F037 — `templates/ltx2/extend-clip` extends an existing clip passed as `clip`, with `opening` elided
Before #446, extend-clip always generated its opening, and no variable took an input clip. The first
fix added `clip` (default `previous_result:opening`), and supplying it elided `opening`. The run then
died at once with `Cannot reuse component 'transformer' - no earlier step shared it`, because
`extended` reused components from the step that had just been elided. The second fix made `extended`
load its own components. Model: LTX-2.5 (`Lightricks/LTX-2.5-Diffusers`, SDNQ transformer/text encoder).
**Paid**: one LTX-2.5 load plus 8 denoise steps for 241 frames at 960×544. On MPS this took ~9 min.
The clip is `asset:qa-cast/ep63-shot-ltx-priya.mp4` (121 f, 960×544, 24 fps, from
`templates/ltx2/image-to-video`). If the workspace can't reach it, that is a setup gap, not a finding. Any
121-frame 960×544 LTX-2.5 clip the workspace can reference may stand in.
expected:
- `validate_workflow(name="templates/ltx2/extend-clip")` with no arguments → `valid: true`, `plan.steps: 3`,
  `plan.elided_steps: []` (the generate-then-extend default is unchanged).
- `validate_workflow(name="templates/ltx2/extend-clip", arguments={"clip": "asset:qa-cast/ep63-shot-ltx-priya.mp4",
  "width": 960, "height": 544, "clip_frames": 121, "num_frames": 241, "prompt": "A woman stands in an office, calm.",
  "continuation_prompt": "She folds her arms and looks at the camera."})` → `valid: true`, `plan.steps: 2`, and
  `plan.elided_steps` holds one entry with `step: "opening"` and `overridden_by: "clip"`.
- `run_workflow` with the same arguments, `acknowledged_cost=<bound plan>`, `wait_seconds=55`, then
  `wait_for_job` until finished → `status: succeeded`, no `error`. The only warning is that `opening` did not
  run. The manifest has one `extended` `final/*.mp4`.
- `get_output_frames(name=<that mp4>, at=["frame:120", "frame:121", "frame:240"])` → `frame_count: 241`.
  Frames 120 and 121 show the same subject and framing, with no jump where the source clip ends.
It is a **finding** if the clip-supplied run fails, especially with a `Cannot reuse component` error, if
`opening` is not elided, or if the default plan loses its `opening` step.
cleanup: `delete_output(job_id=<the run's job id>)` removes the run directory whole.
source: tester, verified in #446, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-26 against the
local server (mps on Mac-mini.lan) `develop @ eb482ba`: job `880d989470b3` succeeded in ~8.9 min, 241 frames,
seamless at 120→121. The implementer proposed the case for smoke. It lives here because it loads LTX-2.5.
metrics: none.

### M-F038 — a null `lora_model_name` turns an H3 template's turbo LoRA off, and validate says so
Before #469, nulling the `lora_*` variables of a MiniMax H3 template (`MiniMaxAI/MiniMax-H3`, turbo LoRA
`lightx2v/Minimax-h3-Turbo`) validated clean. The job then loaded H3 for minutes and died in `load_loras`
with `float() argument must be ... not 'NoneType'`. The fix treats a null `model_name` as the off switch: the
entry is skipped, and a null scale or adapter name on a LoRA that does load falls back to its default.
**Free**: validate only (the paid half, a 28-step no-LoRA run, was confirmed once in #469).
expected:
- `validate_workflow(name="templates/minimax/video-with-audio", arguments={"lora_model_name": null})` →
  `valid: true`, with exactly one warning, which starts `arguments.lora_model_name:` and says the lora is not
  loaded. `plan.downloads_required` does not list `lightx2v/Minimax-h3-Turbo`.
- The same call with all five of `lora_model_name`, `lora_weight_name`, `lora_adapter_name`, `lora_scale`,
  `lora_alpha` set to null → `valid: true`, with the same single warning and no error.
- The same call with no arguments → `valid: true`, `warnings: []`.
It is a **finding** if a nulled call returns an error or no warning, or if the default call warns.
cleanup: none (nothing is queued or written).
source: tester, verified in #469, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-26 against
`lem` `develop @ 3e8bf8d`. Job `6e865a125fe1` (all nulls, 28 steps) succeeded in ~9.9 min with a
`lora_disabled` warning and no `LoRA:` phase. The defaults job `e3d9dd9d3d21` loaded the LoRA with no warning.
metrics: none.

### M-F039 — `upscale_h3_latents` and `decode_h3_latents` are listed and documented, and the documented workflow validates
source: tester, spec for #499 from #471's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 (`LBH-123-AI/Minimax_h3_latent_Upscaler` for the upscaler).
Stage 1 of #471 adds two tasks and ships an inline workflow that composes them (in a
WORKFLOW_GUIDE paragraph or a task docstring). This case is free: discovery and validation only.
Steps:
1. `list_tasks`. Then `get_task("upscale_h3_latents")` and `get_task("decode_h3_latents")`.
2. Find the documented workflow: `list_guides`, then `get_guide` on the section naming
   `upscale_h3_latents`. If no guide section names it, use the task description from step 1.
3. `validate_workflow` the documented workflow's JSON exactly as printed. Put it in workspace
   `regression-model-specific`, with no edits except any `num_frames` the docs say to set.
expected:
- `list_tasks` lists both tasks.
- `upscale_h3_latents` documents these arguments:
  - `latents`;
  - `width` and `height`, described as target pixels and multiples of 16;
  - optional `model_name` and `weight_name`.

  Its description or default names `LBH-123-AI/Minimax_h3_latent_Upscaler`.
- `decode_h3_latents` documents `latents` and an optional `model_name`.
- The documented workflow has these steps, in order:
  - an H3 base step with `latents` in its `output` list;
  - an `upscale_h3_latents` step at 1344×768;
  - a `decode_h3_latents` step;
  - a `pair_audio` step taking `sample_rate` from `previous_result:<base>.sampling_rate`, with
    `fit: "video"`.
- It validates `valid: true` with no errors. `plan.estimate` is present.
It is a **finding** if either task is missing from `list_tasks`, or an argument the plan
names is missing from its schema. It is also a finding if the documented workflow can't be
found through `list_guides`/`get_guide` or `get_task`, or doesn't validate as printed.
cleanup: none (nothing is queued or written).
metrics: none.

### M-F040 — `upscale_h3_latents` refuses a bad target or non-latent input by naming the argument; boundary scales are accepted
source: tester, spec for #499 from #471's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 + `upscale_h3_latents`.
The plan's refusals are these:
- an input that isn't a 5-D, 24-channel latent;
- a target that isn't a multiple of 16;
- a per-axis scale outside 1.0–4.0;
- a target over the 768×1344 canvas cap.

Each must come back as an error naming the argument, not as a raw tensor-shape error or an OOM
from deep in the model. The base is 960×544 (a 60×34 latent grid).
Setup: in workspace `regression-model-specific`, `save_workflow` a case workflow
`m-f040-h3-upscale`. Start from the documented workflow (M-F039), then make these edits:
- `num_frames` = the smallest 17n+5 value the base's `variable_constraints` allow;
- the `up` step's `width`/`height` become `variable:width` / `variable:height`, defaulting to
  1344 / 768;
- the `up` step's `latents` becomes `variable:latents`, defaulting to
  `previous_result:base.latents`. Probe (f) overrides it.

Probes. Validate each with `validate_workflow(name=..., arguments={...})`. Run it only when
validation passes it:
- (a) `width: 0`;
- (b) `width: -16`;
- (c) `width: 1350`, which isn't a multiple of 16;
- (d) `width: 4000`, which is over 4× and over the cap;
- (e) `width: 944, height: 544`, which is a downscale (scale 0.98 < 1.0);
- (f) `latents` = an image: any still image asset from the Fixtures of
  `regression-suite-complete.md` (`asset:qa-cast/...`). If a variable can't carry a reference
  there, edit the `up` step's `latents` in an inline copy instead;
- (g) `width: 1920, height: 1088`, which is inside 4× but over the 768×1344 cap.

Accepted boundaries, which must run to success:
- (h) `width: 960, height: 544`, scale 1.0 on both axes;
- (i) `width: 960, height: 768`, one axis at 1.0 and the other at about 1.41.

Before (h) and (i), `validate_workflow` must show the base step in `plan.cached_steps` when an
earlier run of this saved workflow already produced it. Only the `up` arguments changed, so the
plan's step cache should serve `base`. Run with
`run_workflow(..., acknowledged_cost=true, wait_seconds=55)`.
expected:
- (a) and (b) are `valid: false` at validate. `task_domains` require >0.
- Each of (c)–(g) is refused, at validate or when the `up` step runs. The error names the
  argument (`width`, `height` or `latents`) and says why: a multiple of 16, a scale range or
  the canvas cap, or not a 5-D 24-channel latent. A refusal at run time must fail the job
  before `decode`, with that message in `get_job`'s error.
- (h) and (i) succeed. The mp4 is 960×544 for (h) and 960×768 for (i), with the base's frame
  count.
- The second and later runs show `base` in `plan.cached_steps` and don't re-run it. Check
  `get_job_events`: there are no base denoise events.
It is a **finding** if:
- any of (c)–(g) queues and fails with a raw shape error, a CUDA OOM or a message that
  doesn't name the argument;
- any of (c)–(g) succeeds;
- (h) or (i) is refused;
- a re-run with only `up`'s arguments changed re-denoises `base`.
cleanup: `delete_output(job_id=...)` for every job; `delete_workflow("m-f040-h3-upscale")`.
metrics: none.

### M-F041 — the documented base → upscale → decode → pair_audio workflow renders 1344×768 with the base's frames, colour and audio
source: tester, spec for #499 from #471's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va at 960×544 + `upscale_h3_latents` +
`decode_h3_latents` + `pair_audio`.
This is the stage's positive run. It checks two things:
- the upscale is real: 1344×768, not 960×544 resized;
- decode normalization is right. A wrong one shows up as a colour cast or a washed-out
  picture.

Steps:
1. In workspace `regression-model-specific`, `save_workflow` the documented workflow (M-F039)
   as `m-f041-h3-upscale`, with `num_frames` 124.
2. Add a second output from the base: a saved mp4 of the base's own `videos`, with its
   audio. This is the reference.
3. Add a step `ident` that runs `decode_h3_latents` on `previous_result:base.latents`
   directly, without the upscale.
4. `run_workflow(name="m-f041-h3-upscale", acknowledged_cost=true, wait_seconds=55)`, then
   `wait_for_job` until it is done.
5. Look at both videos with `get_output_frames` at the same 3–4 moments (start, 1/3, 2/3,
   end). Look at `ident`'s output too. Compare the audio with `get_output_audio`.
6. Note decode peak VRAM from `get_job_events` (the `decode` step's memory reading), or from
   `get_memory` right after the job if events don't carry one.
expected:
- The job succeeds.
- The upscaled mp4 is 1344×768, has a `frame_count` equal to the base mp4's (124 at 24 fps),
  and has 32000 Hz audio.
- Its audio duration matches the base's to within one video frame, and it sounds the same:
  the same speech or sound, at the same level.
- Its frames show the base's content, sharper or equal. Colours match the base's, with no
  cast. Contrast and black level match, and nothing is washed out.
- `ident` gives a 960×544 video whose frames match the base's own decode.
It is a **finding** if:
- the dimensions or frame count differ;
- the audio is missing, silent, or shifted by more than one frame;
- either decode shows a colour cast, a washed-out or grey picture, or noise;
- `ident` differs visibly from the base's decode, which means denormalization is wrong
  regardless of the upscaler.
cleanup: `delete_output(job_id=...)`; `delete_workflow("m-f041-h3-upscale")`.
metrics: `latency_s` (the whole job, from `get_job`), `upscale_s` and `decode_s` (per-step
durations from `get_job_events`), `decode_peak_vram_gb`. Record them in
`regression-perf/M-F041.jsonl` with condition `124f-960x544-to-1344x768`. The first run seeds
the file. Flag a reading more than 50% over the median.

### M-F043 — the Ref2VA VRAM ceiling adds a per-reference term: every non-null reference costs, of any kind, and a null one doesn't
source: tester, spec for #501 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA (`ModularPipeline`, `MiniMaxAI/MiniMax-H3`, `workflow: "ref2va"`)
via `templates/minimax/reference-to-video`, against its RTX 3090 24 GB `cost` entry.
Before #479 the template's ceiling (`base_gb` + `bytes_per_voxel` over width × height ×
num_frames) ignored references, so a shot that OOMs with three references validated clean. Plan v1
recalibrates it to `base_gb` 16.0, `bytes_per_voxel` 28.71 and a new `gb_per_reference` 1.0, and
counts each non-null `from_file`/`from_previous_result` reference as 1.0 GB, whatever its kind.
At 1344x768 its projections are:

| shot | projected | verdict |
|---|---|---|
| 209 frames × 2 refs | ~23.8 GB | valid |
| 175 × 3 | ~23.8 GB | valid |
| 209 × 3 | ~24.8 GB | refused |
| 260 × 1 | ~24.2 GB | refused |

The margins are ~0.2 GB, so this case pins the verdicts at those four points. A recalibration that
flips one is a finding, even if the new numbers are defensible, because the four points are the
measured OOM/pass evidence the plan fitted to. The exact GB may move by a few hundredths.

The template's `references` list is not a variable: it holds one image reference
(`from_file: variable:subject`) and one audio reference (`from_file: variable:voice`). A third
reference needs an inline copy. Free: validate calls only.
Setup: `get_workflow("templates/minimax/reference-to-video")`. Take its definition as
**R3**: the same JSON with a third entry appended to the step's `arguments.references`:
`{"reference_type": "diffusers.modular_pipelines.minimax_h3.MiniMaxH3ImageReference", "from_file": "variable:subject"}`.
Leave R3's `vram_estimate` and `cost` exactly as the template has them.
Steps (all `validate_workflow`, workspace `regression-model-specific`):
1. `name="templates/minimax/reference-to-video"`, `arguments={"width": 1344, "height": 768, "num_frames": 209}`
   (2 refs).
2. `workflow=R3`, the same arguments (3 refs).
3. `workflow=R3`, `arguments={"width": 1344, "height": 768, "num_frames": 175}`.
4. `name="templates/minimax/reference-to-video"`, `arguments={"width": 1344, "height": 768, "num_frames": 260, "voice": null}`
   (1 ref, the image).
5. The same as step 4 but `{"subject": null}` in place of `"voice": null`, with `voice` left at
   its default (1 ref, the audio).
6. `name="templates/minimax/reference-to-video"`, `arguments={"width": 1344, "height": 768, "num_frames": 260}`
   (2 refs).
7. `get_workflow("templates/minimax/reference-to-video")`.
expected:
- Steps 1 and 3 are `valid: true`, with no error and no warning about VRAM.
- Step 2 is `valid: false` with exactly **one** VRAM error, at path `arguments`. Its message
  names:
  - the product `1344*768*209`;
  - the reference count (3);
  - the formula, or at least the per-reference term;
  - the projected figure (`~24.8 GB`, to within 0.1);
  - `above the 24 GB declared for RTX 3090`;
  - `#479`.
- Steps 4 and 5 are each `valid: false` with the same shape of error: 1 reference, ~24.2 GB. The
  two projections are **equal**, since an audio reference costs what an image reference costs.
- Step 6 is `valid: false` (2 refs, ~25.2 GB).
- Step 7: `vram_estimate` has `gb_per_reference: 1.0` and `base_gb: 16.0`, and its `reason`
  cites `#479`.
It is a **finding** if:
- any of the four table points flips verdict;
- step 2 reports more or fewer than one VRAM error, or the message omits the reference count or
  the issue;
- steps 4 and 5 project different figures (a kind weighted differently, or a null reference
  counted);
- step 6 passes, since nulling a reference must be what brings 260 frames down, not something
  else.
cleanup: none (nothing is queued or written).
metrics: none.

### M-F044 — a `for_each` Ref2VA template is checked per member after expansion, and reports one error, for the largest member
source: tester, spec for #501 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA via `templates/minimax/dialogue-short`, a `for_each` step `shot`
over `variable:shots`. Each entry has `name`, `num_frames`, `prompt` and `references`.
Today the template's default `shots` are:

| name | frames | refs |
|---|---|---|
| `cold_open` | 124 | 4 |
| `deflect`, `react`, `button` | 124 | 2 each |
| `tag` | 141 | 4 |

The 4-ref shots carry two portraits (`from_previous_result`) plus the two voices
(`variable:character_a_voice`/`character_b_voice`), which default to null.

Before #479 the ceiling was checked against the unexpanded definition, so it never saw a member.
Plan v1 moves the check after expansion. Each member is checked with its own frames and its own
non-null reference count. Only one error is reported, for the largest member. Its path is
`arguments.shots[i]` when the caller supplied `shots`, else `variables.shots[i]`. Its message
names `shot@<name>`, the frames, the size, the reference count and the formula.

Free: validate calls only. The GB figures below are at the plan v1 calibration: base 16.0,
28.71 bytes per voxel, 1.0 GB per reference.
Setup:
1. `get_workflow("templates/minimax/dialogue-short", variables_only=true)`, and take its `shots`
   array as **S**.
2. Take the template's `voice` default URL from `get_workflow("templates/minimax/reference-to-video", variables_only=true)`
   as **V**.
3. Build:
   - **S1**: S with `cold_open.num_frames` set to 209. The rest are unchanged.
   - **S2**: S1 with `tag.num_frames` also set to 226, which is on the 17n+5 grid.
Steps (all `validate_workflow`, `name="templates/minimax/dialogue-short"`, workspace
`regression-model-specific`; every call also passes `"width": 1344, "height": 768`):
1. Arguments `{"shots": S1, "character_a_voice": V}`. `cold_open` then has 3 non-null refs at 209
   frames (~24.8 GB). `tag` has 3 at 141 frames (~22.9). The others are 124 frames with 2 or
   fewer refs.
2. Arguments `{"shots": S1}`, with voices at their null defaults. `cold_open` then has 2 refs at
   209 frames (~23.8).
3. Arguments `{"shots": S2, "character_a_voice": V}`. `cold_open` is ~24.8 and `tag` is 3 refs
   at 226 frames (~25.2).
4. The same shape at the template's own defaults, with only the size overridden:
   `{"character_a_voice": V, "character_b_voice": V}`.
5. An inline copy of the whole template (`get_workflow` definition) whose `shots` variable
   default is S1. Validate it as `workflow=<copy>` with `{"character_a_voice": V}`, and with no
   `shots` argument.
expected:
- Step 1 is `valid: false` with exactly **one** VRAM error, at path `arguments.shots[0]`. Its
  message names:
  - `shot@cold_open`;
  - 209 frames and 1344x768 (or the product `1344*768*209`);
  - 3 references;
  - ~24.8 GB and the 24 GB RTX 3090 ceiling;
  - `#479`.
- Step 2 is `valid: true`, so nulling one reference in the heavy shot clears it.
- Step 3 is `valid: false` with exactly one VRAM error, at `arguments.shots[4]`, naming
  `shot@tag` and 226 frames. That is the largest member, even though `cold_open` is also over.
- Step 4 is `valid: true`, since `tag` at 141 × 4 is ~23.9.
- Step 5 is `valid: false` with the one error at **`variables.shots[0]`**, naming `shot@cold_open`.
It is a **finding** if:
- any over-ceiling member validates clean;
- more than one VRAM error is reported for one workflow;
- the error names a member other than the largest;
- the path is not the `arguments.`/`variables.` form the caller's input dictates;
- a null voice is counted, which step 2 or 4 refuses;
- the message lacks the member name or reference count.
cleanup: none (nothing is queued or written).
metrics: none.

### M-F045 — the ceiling reads a step's own substituted arguments before the workflow's variables
source: tester, spec for #501 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, via an inline copy of `templates/minimax/reference-to-video`.
Plan v1 reads `voxel_variables` (width, height, num_frames) from each step's substituted
`arguments` first, and falls back to the workflow's variables. So a step that hard-codes
its frame count is judged by that count, not by the variable, which may no longer feed it.
Free: validate calls only.
Setup: `get_workflow("templates/minimax/reference-to-video")`. Build two inline copies with
`vram_estimate` and `cost` untouched:
- **L260**: the step's `arguments.num_frames` (today `variable:num_frames`) replaced by the literal
  `260`.
- **L124**: the same with the literal `124`.
Steps (`validate_workflow`, workspace `regression-model-specific`):
1. `workflow=L260`, `arguments={"width": 1344, "height": 768, "voice": null}`. The variable
   `num_frames` stays at its default, 124.
2. `workflow=L124`, `arguments={"width": 1344, "height": 768, "num_frames": 260, "voice": null}`.
expected:
- Step 1 is `valid: false` with one VRAM error whose message names 260 frames (the product
  `1344*768*260`), 1 reference and ~24.2 GB.
- Step 2 is `valid: true` with no VRAM error. The step runs at 124 frames, whatever the unused
  variable says.
It is a **finding** if step 1 passes, since that means the variable was read and the literal
ignored. It is also a finding if step 2 is refused, which is the same mistake the other way. An
error path of `arguments` or one naming the step both meet step 1. What matters is the number
judged.
cleanup: none.
metrics: none.

### M-F046 — `run_workflow` refuses a Ref2VA shot over its ceiling before a job exists, `for_each` members included
source: tester, spec for #501 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA via `templates/minimax/reference-to-video` and
`templates/minimax/dialogue-short`.
Plan v1 moves the run-time backstop after expansion too, so the refusal validate gives is also
what `run_workflow` gives, before anything queues. M-F024 pins the LTX form of that refusal.
Free if the refusal holds. If a step queues instead, that is the finding: cancel it at once.
Steps (workspace `regression-model-specific`):
1. `list_jobs` and note the newest job id.
2. `run_workflow(name="templates/minimax/reference-to-video", arguments={"width": 1344, "height": 768, "num_frames": 260, "voice": null}, acknowledged_cost=true)`.
3. `run_workflow(name="templates/minimax/dialogue-short", arguments=<step 1 of M-F044: S1 + character_a_voice V, 1344x768>, acknowledged_cost=true)`.
4. `list_jobs` again.
expected:
- Steps 2 and 3 each return a refusal:
  - `status: failed`, `run_id: null`;
  - an error carrying the same ceiling message `validate_workflow` gives for the same input
    (M-F043 step 4, M-F044 step 1), including `shot@cold_open` for step 3.
- Step 4 shows no new queued or running job, and nothing loaded a model.
It is a **finding** if either call queues a job. It is also one if the refusal comes only after
the job starts (a loading phase, a job id with events), or if its message differs from
validate's.
cleanup: if a job was created, `cancel_job` it at once, then `delete_output(job_id=...)`.
Otherwise none.
metrics: none.

### M-F047 — every H3 template still validates at its defaults, the Ref2VA templates declare the per-reference term, and the LTX ceiling is untouched
source: tester, spec for #501 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: every `templates/minimax/*` entry, plus LTX-2.5 `templates/ltx2/text-to-video`.
Plan v1 gives `vram_estimate` blocks to:
- `dialogue-short`, `music-video` and `composable-references`, which had none;
- `reference-to-video`, which it recalibrates.

It leaves the T2VA/FL2VA templates as they were. A tighter ceiling that refuses a template's
own defaults would break the catalog. Free: listing, `get_workflow` and validate calls only.
Steps:
1. `list_workflows()`, and collect every `templates/minimax/*` name.
2. For each one, `validate_workflow(name=<it>)` with no arguments.
3. `get_workflow` on `templates/minimax/reference-to-video`, `dialogue-short`, `music-video`
   and `composable-references`.
4. `get_workflow("templates/minimax/video-with-audio")` and
   `get_workflow("templates/minimax/video-with-audio-768p")`.
5. `validate_workflow(name="templates/ltx2/text-to-video", arguments={"num_frames": 900})` and
   `arguments={"num_frames": 121}`.
expected:
- Step 2: every H3 template is `valid: true` with no VRAM error. Existing unrelated warnings,
  such as no seed, are fine.
- Step 3: all four carry a `vram_estimate` with a `gb_per_reference` (1.0 at the plan v1
  calibration) and `voxel_variables` covering width, height and num_frames.
  `composable-references` counts its `motion` video reference like any other.
- Step 4: the T2VA templates' `vram_estimate` is unchanged from before #479. Per M-F026 that
  means no `gb_per_reference` is required, and the 768p breakpoint is between 277 and 294
  frames.
- Step 5: 900 frames is still `valid: false`, with the two co-reported errors M-F022 pins. 121
  is still `valid: true`.
It is a **finding** if any H3 template's defaults are refused, if one of the four lacks the
per-reference term, or if the T2VA or LTX ceilings moved.
cleanup: none.
metrics: none.

### M-F048 — `vram_estimate.gb_per_reference` is an optional non-negative number in the schema, and omitting it means no per-reference term
source: tester, spec for #501 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, using R3 from M-F043: the inline reference-to-video copy with
three references.
Plan v1 adds `gb_per_reference` as an optional schema field, a number ≥ 0. The edges are the
field's absence, zero, and a negative value. Free: schema and validate calls only.
Steps:
1. `get_schema` (the section covering a workflow's `vram_estimate`).
2. `validate_workflow(workflow=R3 with vram_estimate.gb_per_reference: -1, arguments={"width": 1344, "height": 768, "num_frames": 209})`.
3. The same with `gb_per_reference: 0`.
4. The same with the `gb_per_reference` key removed.
5. The same with `gb_per_reference: "1.0"` (a string).
expected:
- Step 1 lists `gb_per_reference` under `vram_estimate`: optional, numeric, minimum 0.
- Step 2 is `valid: false` with a schema error at a path ending `vram_estimate.gb_per_reference`.
- Steps 3 and 4 are `valid: true` with no VRAM error: 16.0 + ~5.8 GB is ~21.8 GB, under 24.
- Step 5 is `valid: false` with a type error at the same path.
It is a **finding** if:
- a negative value or a string is accepted;
- an absent or zero term still adds per-reference GB (step 3 or 4 refused);
- the schema doesn't document the field.
cleanup: none.
metrics: none.

### M-F049 — a copied Ref2VA workflow with no ceiling of its own inherits the catalog's, as a warning naming the source template
source: tester, spec for #502 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, via an inline copy of `templates/minimax/reference-to-video`
with no `vram_estimate` and no `cost`.
This is how #478's author worked: copy a template, drop its cost block, and validate clean
into an OOM. Plan v1 indexes the catalog by pipeline identity: pipeline type, plus
`from_pretrained_arguments.model_name`, plus `.workflow`. A workflow with no `vram_estimate`
whose step matches an identity gets a **warning**, never an error. The warning (e.g.
`vram_projection_inherited`) names the source template, gives the projection, and says the
config may differ.

Free: validate calls only.
Setup: build **N3** from R3 (M-F043: the inline copy with 3 references) by deleting its
top-level `vram_estimate` and `cost`.
Steps (`validate_workflow(workflow=N3, ...)`, workspace `regression-model-specific`):
1. `arguments={"width": 1344, "height": 768, "num_frames": 209}` (3 refs, ~24.8 GB).
2. `arguments={"width": 1344, "height": 768, "num_frames": 175}` (~23.8 GB).
3. `arguments={"num_frames": 124}` (960x544, the template's size).
4. `arguments={"width": 1344, "height": 768, "num_frames": 260, "voice": null}` (2 refs, ~25.2).
expected:
- Step 1 is **`valid: true`** with exactly one inherited-ceiling warning. It names:
  - `templates/minimax/reference-to-video`;
  - the projected GB (~24.8), the 24 GB it is over, and the reference count;
  - that the copy's config may differ from the template's.

  Any other warning, such as no seed, stays as it is today.
- Steps 2 and 3 carry no inherited-ceiling warning.
- Step 4 carries the warning at ~25.2 GB.
It is a **finding** if:
- step 1 is refused, since an inherited ceiling must never be an error;
- step 1 has no warning, or its warning doesn't name the source template;
- an under-ceiling point warns;
- the warning ignores references (step 1 silent while step 4 warns).
cleanup: none.
metrics: none.

### M-F050 — the inherited-ceiling warning on a `for_each` Ref2VA workflow names the heavy member
source: tester, spec for #502 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, via an inline copy of `templates/minimax/dialogue-short` with
no `vram_estimate` and no `cost`. It is shaped like the #478 repro: a `for_each` over
`variable:shots` with `"references": "item:references"`.
Plan v1's warning follows stage A's expansion: each member is judged, and the warning names the
member.

Free: validate calls only.
Setup: `get_workflow("templates/minimax/dialogue-short")`. Build **ND** by deleting the top-level
`vram_estimate` and `cost`. S1 and V are as in M-F044.
Steps (`validate_workflow(workflow=ND, ...)`):
1. `arguments={"width": 1344, "height": 768, "shots": S1, "character_a_voice": V}`.
2. `arguments={"width": 1344, "height": 768, "shots": S1}`, with the voices null.
expected:
- Step 1 is `valid: true` with exactly one inherited-ceiling warning:
  - it names `shot@cold_open` (or sits at path `arguments.shots[0]`), and 209 frames, 3
    references and ~24.8 GB;
  - it names a catalog template with the ref2va identity as its source. The plan names
    `reference-to-video` for the single-shot copy. Any `templates/minimax/*` Ref2VA template
    meets this, as long as its ceiling is the one the figure was computed from.
- Step 2 carries no inherited-ceiling warning.
It is a **finding** if step 1 is refused, carries no warning, warns without naming the member,
or warns more than once. It is also one if step 2 warns.
cleanup: none.
metrics: none.

### M-F051 — an inherited ceiling comes only from the same pipeline identity: T2VA copies get T2VA's, other models get none
source: tester, spec for #502 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA (`workflow: "t2va"`) and Ref2VA, via inline copies.
Plan v1 keys the index on pipeline type + `model_name` + `workflow`. So a T2VA workflow never
borrows the Ref2VA ceiling or its per-reference term, and an identity no template shares gets
nothing. Free: validate calls only.
Setup:
- **NT**: `get_workflow("templates/minimax/video-with-audio-768p")` with its top-level
  `vram_estimate` and `cost` deleted.
- **NM**: N3 (M-F049) with the step's `from_pretrained_arguments.model_name` changed to
  `"example-org/not-a-catalog-model"`.
Steps:
1. `validate_workflow(workflow=NT, arguments={"num_frames": 345})`. M-F026's template refuses
   this at its own ceiling.
2. `validate_workflow(workflow=NT)` with no arguments.
3. `validate_workflow(workflow=NM, arguments={"width": 1344, "height": 768, "num_frames": 209})`.
expected:
- Step 1 is `valid: true` with one inherited-ceiling warning. It names a T2VA template
  (`templates/minimax/video-with-audio-768p` or `video-with-audio`), **never**
  `reference-to-video`, and its figure counts no references.
- Step 2 has no inherited-ceiling warning.
- Step 3 has no inherited-ceiling warning. Any error or warning about the unknown model itself is
  outside this case.
It is a **finding** if a T2VA copy's warning names a Ref2VA template or counts references. It is
also one if NM inherits any ceiling, or if step 1 is refused or silent.
cleanup: none.
metrics: none.

### M-F052 — a workflow's own `vram_estimate` wins over the inherited one, stricter or looser
source: tester, spec for #502 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, via inline copies of `templates/minimax/reference-to-video`.
Plan v1: an inherited ceiling applies only where the workflow declares none. A declared one is
judged as in stage A (an error), and brings no inherited warning alongside it. Free: validate
calls only.
Setup:
- R3, as in M-F043: its own `vram_estimate` and `cost` are the template's.
- **RL**: R3 with `vram_estimate.base_gb` set to `1.0`, so its own ceiling is far looser than the
  catalog's.
Steps (`arguments={"width": 1344, "height": 768, "num_frames": 209}` for both):
1. `validate_workflow(workflow=R3, ...)`.
2. `validate_workflow(workflow=RL, ...)`.
expected:
- Step 1 is `valid: false` with the one stage A VRAM error (M-F043 step 2), and **no**
  inherited-ceiling warning.
- Step 2 is `valid: true` with **no** inherited-ceiling warning. The workflow's own looser
  estimate is what counts.
It is a **finding** if either step carries an inherited warning, or if step 2 is refused (the
catalog ceiling applied over a declared one).
cleanup: none.
metrics: none.

### M-F053 — an inherited-ceiling warning never blocks `run_workflow`
source: tester, spec for #502 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, N3 from M-F049.
Plan v1 has no run-time backstop for inherited ceilings. The warning informs, and the run queues.
**Paid, briefly:** the job is queued and cancelled at once, so a model load may start. Run it
only in a full regression pass.
Steps (workspace `regression-model-specific`):
1. `run_workflow(workflow=N3, arguments={"width": 1344, "height": 768, "num_frames": 209}, acknowledged_cost=true)`,
   with no `wait_seconds`.
2. `cancel_job(job_id=<step 1's>)` immediately.
expected:
- Step 1 returns a queued (or running) job with a job id and a `run_id`, not a refusal.
- Step 2 cancels it.
It is a **finding** if step 1 is refused on VRAM grounds.
cleanup: `cancel_job` if still live, then `delete_output(job_id=...)`.
metrics: none.

### M-F054 — the authoring guidance tells an agent that validate warns with an inherited ceiling
source: tester, spec for #502 from #479's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 (the feature's scope), via the server's docs.
Plan v1 extends the MCP instructions' sentence "A workflow you wrote has no measured cost: quote
the `models/` entry ...". It now says validate will warn with an inherited ceiling. The
`workflows` guide's authoring section says the same. Free: docs calls only.
Steps:
1. Read the `dw` server's MCP instructions, which a session receives at connect.
2. `get_guide("workflows", section="Authoring a workflow from an agent")`.
expected:
- Both texts state that a workflow with no `vram_estimate` of its own gets a validate
  **warning** carrying the ceiling inherited from the catalog template with the same pipeline,
  and that the config may differ.
- Neither calls it an error or a refusal.
It is a **finding** if either text is missing the point, or describes it as blocking.
cleanup: none.
metrics: none.

### M-F055 — an H3 `for_each` entry's own `references` resolve an item-level `step@entry` ref, and validate's elision of the unread member holds at run
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA, inline `for_each` workflow (ep74 shape). Paid: one job, ~26 min
(≈6 min load + two shots ≈8 min each).
Setup: workspace `regression-model-specific`. Inline workflow, `id` `m_f055`, `"seed": 55`,
variable `shots` = two entries, each with `name`, `num_frames`, `source`, `references`, `prompt`:
- `accuse`: 124 f, `source={"location":"asset:qa-cast/ep62-shot1-accuse.mp4"}`, references =
  `[{"reference_type": <MiniMaxH3ImageReference>, "from_file": "asset:qa-cast/priya-portrait.jpg"},
  {"reference_type": <image>, "from_previous_result": "still@deflect"},
  {"reference_type": <MiniMaxH3AudioReference>, "from_file": "asset:qa-cast/priya-voice.wav"}]`.
- `deflect`: 141 f, `source=…ep62-shot2-deflect.mp4`, references = `still@deflect` (image) +
  `asset:qa-cast/hal-voice.wav` (audio).
Steps: `still` — `for_each` over `shots`, task `get_last_frame(video="item:source")`, result
`image/jpeg`, `save: false`. `shot` — `for_each`, the H3 pipeline block copied from
`templates/minimax/dialogue-short` (read it with `get_workflow`; int4, turbo LoRA, 960×544),
with `prompt`/`references`/`num_frames` from `item:`, result `video/mp4` fps 24 intermediate.
`episode` — `concat_videos(videos="gather:shot", fps=24, match_levels="rms", audio_bleed_ms=0,
seam_fade_ms=30)`, final. `validate_workflow` → bind cost → `run_workflow` → wait.
expected:
- validate is `valid: true`, and its plan elides `still@accuse` (nothing reads it, it saves
  nothing) while keeping `still@deflect`.
- The job succeeds. `job.warnings` carries the `still@accuse` "did not run" warning, and the
  manifest lists `still@deflect` (no files), `shot@accuse`, `shot@deflect`, `episode`.
- The episode (`get_gallery_metadata`) is 265 f at 24 fps, 32 kHz stereo, with
  `audio_stream_seconds` equal to `duration_seconds` and `media.shots` 124 + 141 at start frame 124.
It is a **finding** if validate passes and the run fails on resolving `still@deflect` from an
entry's `references`, if `still@deflect` is elided too, or if the frame counts drift.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `2shot-inline`, to
`regression-perf/M-F055.jsonl`.

### M-F056 — an LTX-2.5 width/height not divisible by 32 is refused at validate, not after the pipeline load
Before #505, `templates/ltx2/two-stage` with `height: 272` validated clean. The run then failed about 80 s
in, inside diffusers' own `check_inputs` ("have to be divisible by 32"). The fix declared the rule as a
variable constraint on every LTX-2.5 template that takes `width`/`height`.
**Free**: validate and get_workflow only.
expected:
- `get_workflow("templates/ltx2/two-stage", variables_only=true)` → `constraints.width` and
  `constraints.height` each have `modulus: 32`, `remainder: 0`.
- `validate_workflow(name="templates/ltx2/two-stage", arguments={"prompt": "a lighthouse at dusk",
  "seed": 75, "width": 480, "height": 272})` → `valid: false`, with exactly one error, at
  `arguments.height`, naming the 32 rule.
- The same call with `height: 288` → `valid: true`.
- `validate_workflow(name="templates/ltx2/text-to-video", arguments={"width": 950})` → `valid: false`,
  with the error at `arguments.width`.
It is a **finding** if an off-grid size validates clean, or if an on-grid size is refused.
cleanup: none (nothing is queued or written).
source: tester, verified in #505, model `claude-opus-5-5` via provider `anthropic`, on 2026-09-27 against
`lem` `develop @ 6a5cbd5`.
metrics: none.

### M-F057 — an LTX-2.5 `for_each` entry's own `image` given as a `previous_result:` string reaches the pipeline, with per-entry `num_frames`
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic), ep76, job `39d59595d6fb`
Model/pipeline: LTX-2.5 `LTX2ImageToVideoPipeline`, inline `for_each` workflow. Paid: one job, ~3.5 min.
This differs from M-F055: the item-level reference is a bare `"previous_result:still@deflect"` string in an
entry field, passed whole through `item:image` as a pipeline argument, not a `from_previous_result` reference dict.
Setup: workspace `regression-model-specific`. Inline workflow, `id` `m_f057`, `"seed": 76`,
variable `shots` = two entries, each with `name`, `num_frames`, `source`, `image`, `prompt`:
- `accuse`: 97 f, `source={"location":"asset:qa-cast/ep63-shot-ltx-priya.mp4"}`,
  `image={"location":"asset:qa-cast/priya-portrait.jpg"}`, a one-line PRIYA prompt with the line quoted.
- `deflect`: 121 f, `source={"location":"asset:qa-cast/ep64-shot-ltx-hal.mp4"}`,
  `image="previous_result:still@deflect"`, a one-line HAL prompt with the line quoted.
Steps: `still` — `for_each` over `shots`, task `get_last_frame(video="item:source")`, result
`image/jpeg`, `save: false`. `shot` — `for_each`, the pipeline block copied from
`templates/ltx2/image-to-video` (read it with `get_workflow`; its `variable:` refs replaced by
`{uint4}`/`{int8}` literals), with `prompt`/`image`/`num_frames` from `item:`, `width: 960`,
`height: 544`, `frame_rate: 24.0`, result `video/mp4` fps 24 intermediate. `episode` —
`concat_videos(videos="gather:shot", fps=24, match_levels="rms", match_levels_dbfs=-24,
audio_bleed_ms=0, seam_fade_ms=30)`, final. `validate_workflow` → bind cost → `run_workflow` → wait.
expected:
- validate is `valid: true`, `warnings: []`, and its plan has `steps: 4` and elides only `still@accuse`.
- The job succeeds. `job.warnings` holds only the `still@accuse` "did not run" warning. The manifest
  lists `still@deflect` (no files), `shot@accuse`, `shot@deflect` and `episode`.
- `get_output_frames(shot@deflect, at=["frame:0"])` matches
  `get_output_frames("asset:qa-cast/ep64-shot-ltx-hal.mp4", at=["frame:120"])`, so the reference resolved to that still.
- Each shot is 960×544 at 24 fps with the entry's own frame count (97, 121). The episode is 218 f,
  48 kHz stereo, with `media.shots` 97 + 121 and the second starting at frame 97, sample 194000.
It is a **finding** if validate passes and the run fails resolving the string reference, if the
string reaches the pipeline unresolved, if `still@deflect` is elided, or if an entry's frame count drifts.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `2shot-inline`, to
`regression-perf/M-F057.jsonl`.

### M-F058 — `templates/ltx2/upscale-clip` is in the catalog as a shot that reads the caller's clip, with its bucket rules and trade-offs stated
source: tester, spec for #548 from #542's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: LTX-2.5 `LTX2InContextPipeline` with `Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler`
(`ltx-2.5-22b-ic-lora-pixel-spatial-upscaler-x2-1.0.safetensors`), via `templates/ltx2/upscale-clip`.
Free: discovery calls and a skill read only, no GPU.
expected:
- `list_workflows(shape="shot")` lists `templates/ltx2/upscale-clip`. Its traits include `needs-input-media`
  and `has-audio`, and do not include `image-conditioned` (the siblings `restore-deblur` and
  `restore-decompression` carry the same two). The compact constraints read `32*n+0` for width and
  height and `8*n+1, 9+` for `num_frames`, the form the siblings show.
- `get_workflow(name="templates/ltx2/upscale-clip", variables_only=true)` gives these defaults:
  - `source_video` `asset:clip.mp4`, `width` 960, `height` 544, `num_frames` 121, `frame_rate` 24.0, `lora_scale` 1.0;
  - a `prompt`, a `negative_prompt` and a `seed`.
- Its `constraints` are:
  - `width` and `height`: `modulus: 32, remainder: 0`;
  - `num_frames`: `modulus: 8, remainder: 1, min_frames: 9`, with no snap.

  Each has a non-empty `reason`, matching `restore-deblur`'s text for the same variable.
- The workflow's description (from `get_workflow` without `variables_only`, or the full `list_workflows`
  entry) says four things:
  1. a source whose aspect differs from width×height is center-cropped, and a source larger than half the
     target is downscaled first;
  2. `num_frames` must not exceed the source's length;
  3. to call `get_gallery_metadata` on the source first, for its size, frame count and fps;
  4. that it is a re-render (generative, not a pixel-exact upscale).

  Its `cost_drivers` name `num_frames`, `width` and `height`. A description missing any of the four is a finding.
- In `get_workflow`'s full document:
  - step `upscaled` uses `reference_downscale_factor: 2`, a reference of `{"media_type": "video",
    "location": "variable:source_video"}` and the Pixel-Spatial-Upscaler LoRA above, and its result is
    intermediate;
  - step `with_source_audio` is `pair_audio(video=previous_result:upscaled, audio=variable:source_video,
    fit="video")`, and its result is final.
- The `dw` plugin's LTX-2.5 skill names `upscale-clip` in two places: its "Repairing the user's own
  footage" guidance, and next to `generative-upscale` as the route for a clip dw didn't make.
It is a **finding** if the template is missing from `shape="shot"`, if a trait or constraint above is
absent or differs from the siblings' form, or if the skill still sends a user's own clip only to
`generative-upscale`.
cleanup: none. Discovery only, writes nothing.
metrics: none.

### M-F059 — `upscale-clip` validates a real clip, names its adapter only when absent, and refuses off-bucket sizes and the bare call
source: tester, spec for #548 from #542's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F058. Free: `validate_workflow` and `list_models` only, no GPU. `A` below is
`asset:qa-cast/ep3-shot1-incident.mp4` (shared, 960×544, 124 frames).
expected:
- **A real clip is clean.** `validate_workflow(name="templates/ltx2/upscale-clip", arguments={"source_video": A})`
  gives `valid: true` and `warnings: []`, with `checked_arguments` including `source_video`.
- **The adapter is named only when it's absent.** Check `list_models()` first, as M-F013 does:
  - If it does not list `Lightricks/LTX-2.5-22b-IC-LoRA-Pixel-Spatial-Upscaler`, the call above has an
    entry in `plan.downloads_required` whose `repo` is that repo.
  - If it does list it (the box already serves `generative-upscale`), `downloads_required` is `[]`.
    A non-empty list naming it here is the "every `loras` entry reported" bug.

  Record which arm ran.
- **`num_frames` is bounded both ways.** With `source_video: A`:
  - `num_frames: 120` → `valid: false`, one error at `arguments.num_frames` naming the 8n+1 rule;
  - `num_frames: 1` → `valid: false` at `arguments.num_frames`, since 1 is below the minimum of 9;
  - `num_frames: 121` and `num_frames: 9` → `valid: true`, since both are on the bucket and the minimum is inclusive;
  - `num_frames: 161` → `valid: true`. Validate can't know the source length, and M-F061 covers the run.
- **Width and height are bounded.** With `source_video: A`:
  - `width: 970` → `valid: false`, one error at `arguments.width` naming 32;
  - `height: 550` → `valid: false` at `arguments.height`;
  - `width: 960` and `height: 544` → `valid: true`.
- **The bare call is refused.** `validate_workflow(name="templates/ltx2/upscale-clip")` with no `arguments` gives
  `valid: false`, with an error at `variables.source_video` naming the missing default `asset:clip.mp4`, as M-F013 and
  M-F014 do (#166).
It is a **finding** if an off-bucket value passes, an on-bucket boundary is refused, an error lands at a
different path, or the bare call answers `valid: true`.
cleanup: none. Validation only, writes nothing.
metrics: none.

### M-F060 — `upscale-clip` doubles a 480×272 clip to 960×544 at the same length and rate, carrying the source's own soundtrack
source: tester, spec for #548 from #542's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F058. Paid: one LTX-2.5 job at 960×544×121 frames (the shape of M-F014's
restore runs). Setup: fixture `asset:upscale/src-480x272.mp4` (see Fixtures: 480×272, 121 frames, 24 fps,
with audio). If it's missing, record "fixture missing" and skip.
Steps:
1. `get_gallery_metadata("asset:upscale/src-480x272.mp4", workspace="regression-model-specific")` to pin the
   source's size, frame count, fps, sample rate, channels and duration.
2. `validate_workflow(name="templates/ltx2/upscale-clip", arguments={"source_video": "asset:upscale/src-480x272.mp4",
   "seed": 548})` gives `valid: true`. Bind cost from `plan.estimate`.
3. `run_workflow` with the same arguments in workspace `regression-model-specific`, `wait_seconds=55`, then
   `wait_for_job` to the end.
expected:
- The job succeeds with no warning except, at most, `pair_audio`'s `audio_padded_to_video` or
  `audio_trimmed_to_video` from `pair_audio` for an off-by-a-few-ms audio length.
- The manifest has:
  - the `upscaled` file under `intermediate/`, 960×544 and 121 frames;
  - one `with_source_audio` file under `final/`, 960×544, **121 frames, 24 fps**, according to
    `get_gallery_metadata` on it.
- **The soundtrack is the source's.** On the final file, `get_output_audio` has the source's sample rate and
  channel count, and a duration within one frame (≈42 ms) of the source's. Its RMS and peak are within 1 dB
  of `get_output_audio` on the source. Generated LTX audio would differ.
- `assess_output` on the final file has no sync-drift (audio/video length mismatch) finding.
- **Same framing.** `get_output_frames` at `frame:0`, `frame:60` and `frame:120` on the final file shows the same
  composition as the source at the same frames: same subject, same position, no crop or stretch. The detail may
  differ, since this is a re-render.
It is a **finding** if the output isn't 960×544×121 at 24 fps, if the final carries generated rather than source
audio, if sync drifts, if the framing shifts, or if the upscale isn't kept in `intermediate/`.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `480x272-121f`, to `regression-perf/M-F060.jsonl`.
The first run seeds the file.

### M-F061 — `upscale-clip` on off-shape sources: larger is downscaled, wider is center-cropped, too long a `num_frames` runs past the source, and a silent source fails at the audio step
source: tester, spec for #548 from #542's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F058. Paid: up to four LTX-2.5 jobs, run one at a time. The plan records these as behavior,
not refusals: validate passes each one (M-F059). Each arm uses `"seed": 548` in workspace
`regression-model-specific`, with a `get_gallery_metadata` on its source first. If a fixture is missing,
record "fixture missing" for that arm and skip it.
expected:
- **Larger source, downscaled.** `source_video: "asset:qa-cast/ep3-shot1-incident.mp4"` (960×544, 124 frames) with
  the default `num_frames` 121:
  - the job succeeds, and the final is 960×544, 121 frames, 24 fps, carrying the source's audio;
  - frames `0` and `120` show the source's framing at the same frames, uncropped, since the aspect already matches.
- **16:9 source, center-cropped.** `source_video: "asset:upscale/src-640x360.mp4"`:
  - the final is 960×544, 121 frames;
  - its `frame:60` matches the source's `frame:60` with a thin equal band trimmed left and right (1.778 → 1.765),
    and is not squeezed. A stretched subject or a one-sided crop is a finding.
- **`num_frames` past the source.** `source_video: "asset:upscale/src-480x272.mp4"` (121 frames), `num_frames: 161`:
  - the job succeeds, and the final is 161 frames at 24 fps;
  - frames 0–120 follow the source;
  - `frame:160` is not a frame of the source, which is the tail the description warns of;
  - with `fit: "video"`, the source audio is padded to the video, so an `audio_padded_to_video` warning is
    expected and is not a finding;
  - the final's audio duration is within a frame of 161/24 s.
- **Silent source.** `source_video: "asset:upscale/src-480x272-silent.mp4"`:
  - the job **fails at step `with_source_audio`**, not at `upscaled` and not at validate;
  - its error names the missing audio: the source has no audio stream;
  - the `upscaled` output is already saved under `intermediate/` at 960×544, 121 frames, so the GPU work
    isn't lost.

  A job that succeeds with silent or generated audio in `final/` is a finding. So is an error that doesn't say
  the audio is what's missing.
It is a **finding** if an arm's behavior differs from the above in the direction the plan rules out: a refusal
where it promises a run, a stretch where it promises a crop, a truncation at 121 where 161 was asked, or a silent
success.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` for each arm's job, the failed one included.
metrics: `latency` (s) per arm, conditions `larger-960x544`, `crop-640x360`, `long-161f`, `silent-fail`, to
`regression-perf/M-F061.jsonl`. The first run seeds the file.

### M-F062 — `templates/ltx2/refine-clip` is a catalog shot with a curated cost, built from the upsampler's own `video=` encode, and `two-stage` is untouched
source: tester, spec for #549 from #543's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: LTX-2.5, with `LTX2LatentUpsamplePipeline` (fed `video=`) followed by `LTX2Pipeline` refine
on the stage-two sigmas, via `templates/ltx2/refine-clip`. Free: discovery calls and a skill read only,
no GPU.
expected:
- `list_workflows(shape="shot")` lists `templates/ltx2/refine-clip` with:
  - traits that include `needs-input-media` and `has-audio`, and do not include `image-conditioned`
    or `chained`;
  - a non-null curated `cost`, which is the mark that it has been run on a real device;
  - compact constraints of `32*n+0` for `width` and `height`, and `8*n+1, 9+` for `num_frames`.
    This is the same form `templates/ltx2/two-stage` shows.
- `get_workflow(name="templates/ltx2/refine-clip", variables_only=true)` gives these defaults:
  - `source_video` `asset:clip.mp4`;
  - `width` 512, `height` 288, `num_frames` 121, `frame_rate` 24.0;
  - `negative_prompt` `constant:diffusers.pipelines.ltx2.utils.DEFAULT_NEGATIVE_PROMPT`;
  - a `prompt`, a `seed`, and the two weight dtypes `transformer_weights_dtype` and
    `text_encoder_weights_dtype`.

  Its `constraints` are `width`/`height` with `modulus: 32, remainder: 0`, and `num_frames` with
  `modulus: 8, remainder: 1, min_frames: 9` and no snap. Each has a `reason` matching `two-stage`'s
  text for the same variable. The plan says they are copied.
- In `get_workflow`'s full document:
  - Step `source_audio` is `normalize_audio` of `variable:source_video` to a −3 dBFS peak, and saves
    nothing. It is also the silent-source check (M-F066).
  - Step `source_frames` is `loop_frames(video=variable:source_video, num_frames=variable:num_frames)`,
    `save: false`. It trims (or laps) the source to `num_frames` before the upsampler.
  - Step `upscale` is `LTX2LatentUpsamplePipeline`. Its `video` argument reads `previous_result:source_frames`,
    and it has no `latents`. It passes `height`/`width`/`num_frames` from the variables and
    `output_type: "latent"`, is `save: false`, and publishes `shared_components` with `vae`.
  - Step `refine` has these values:
    - `latents` is `previous_result:upscale.frames`;
    - there is **no** `audio_latents` key;
    - `noise_scale` is `0.909375` (`STAGE_2_DISTILLED_SIGMA_VALUES[0]`);
    - `sigmas` is `constant:diffusers.pipelines.ltx2.utils.STAGE_2_DISTILLED_SIGMA_VALUES`;
    - `reused_components` includes `vae`;
    - its result is intermediate.

    Its width/height are the source size (the `width`/`height` variables), not 2×; the output comes
    out at 2× that. M-F064 checks the real output size.
  - Step `with_source_audio` is `pair_audio(video=previous_result:refine, audio=previous_result:source_audio,
    fit="video")`, and its result is final.
  - `cost_drivers` names `num_frames`, `width` and `height`, and there is no `vram_estimate`.
- The description (from the full `get_workflow` document or the full `list_workflows` entry) says five
  things:
  1. The output is exactly 2× `width`×`height`.
  2. Set `width`/`height` to the source's size. A source of a different aspect is *resized*
     (stretched), not cropped.
  3. `num_frames` must not exceed the source's length.
  4. The soundtrack is the source's own, not generated.
  5. A source with no soundtrack is refused.

  If `templates/ltx2/upscale-clip` (#542) is in the catalog at run time, the description or summary
  also contrasts the two routes.
- **`two-stage` is unchanged** (a non-goal). `get_workflow(name="templates/ltx2/two-stage",
  variables_only=true)` still gives `width` 768, `height` 448, `num_frames` 121, `frame_rate` 24.0,
  `seed` 42 and `prompt` `prompt:ltx2/fox_dawn_choir`, with the same three constraints.
- The `dw` plugin's `ltx-2-5` skill names `refine-clip`:
  - as a route for a clip dw did not make ("only templates that read a clip dw did not make");
  - beside the `two-stage` entry;
  - in its audio lines, where it says refine-clip carries the source's soundtrack.
It is a **finding** if the template is missing from `shape="shot"`, if its `cost` is null, or if a
trait, constraint or pinned value above is absent or different. It is also a finding if the
description misses any of the five points, if `two-stage` changed, or if the skill doesn't mention
refine-clip.
cleanup: none. Discovery only, writes nothing.
metrics: none.

### M-F063 — `refine-clip` validates a real clip with an estimate, and refuses a missing asset, off-grid sizes and frame counts, and the bare call before anything queues
source: tester, spec for #549 from #543's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F062. Free: `validate_workflow`, plus `run_workflow` calls that must be refused
before a job exists. No GPU. `A` below is `asset:qa-cast/ep3-shot1-incident.mp4` (shared, 960×544,
124 frames, with audio). The plan puts no source probe at validate (non-goal), so validation reads only
that the asset exists.
expected:
- **A real clip is clean.** `validate_workflow(name="templates/ltx2/refine-clip",
  arguments={"source_video": A})` gives `valid: true` with no errors. `checked_arguments` includes
  `source_video`, and there is a `plan` whose `estimate` has a non-null minutes figure (curated or
  observed, which one is recorded). A `warnings` entry is recorded but is not a finding unless it is
  an error in disguise.
- **A missing asset.** `source_video: "asset:refine/no-such-clip.mp4"` gives `valid: false`, with an
  error at `arguments.source_video` that names the missing asset.
- **`num_frames` bounds.** With `source_video: A`:
  - `num_frames: 120` → `valid: false`, with one error at `arguments.num_frames` naming the 8n+1 rule;
  - `num_frames: 1` → `valid: false` at `arguments.num_frames`, below the minimum of 9;
  - `num_frames: 9` and `num_frames: 121` → `valid: true`. Both are on the grid, and the minimum is
    inclusive.
- **`width`/`height` bounds.** With `source_video: A`:
  - `width: 500` → `valid: false`, with one error at `arguments.width` naming 32;
  - `height: 300` → `valid: false` at `arguments.height`;
  - `width: 480, height: 256` → `valid: true`. Both are multiples of 32 other than the defaults.
- **Refused before anything queues.** `run_workflow` with `source_video: A` and `num_frames: 120`,
  passing the `acknowledged_cost` from the clean call above, is refused. It returns no `job_id`, and
  `list_jobs` shows no new `refine-clip` job. Do the same for `width: 500`.
- **The bare call is refused.** `validate_workflow(name="templates/ltx2/refine-clip")` with no
  `arguments` gives `valid: false`, with an error at `variables.source_video` naming the placeholder
  default `asset:clip.mp4`. M-F059 checks the same for `upscale-clip`.
It is a **finding** if an off-grid value or a missing asset passes, if an on-grid boundary is refused,
if an error lands at a different path, if a refused `run_workflow` creates a job, if the clean call has
no estimate, or if the bare call answers `valid: true`.
cleanup: none. Nothing is written. If a refused `run_workflow` created a job anyway, `cancel_job` and
`delete_output` it, and record that as the finding.
metrics: none.

### M-F064 — `refine-clip` doubles a 512×288 clip to 1024×576, keeping its composition, its motion and its own soundtrack at −3 dBFS
source: tester, spec for #549 from #543's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F062. Paid: one LTX-2.5 refine job at the defaults (512×288 → 1024×576, 121 frames).
Setup: fixture `asset:refine/src-512x288.mp4` (see Fixtures). Make it first if it is missing.
Steps:
1. `get_gallery_metadata("asset:refine/src-512x288.mp4", workspace="regression-model-specific")` pins the
   source's size, frame count, fps, sample rate, channels and duration. Also take
   `get_output_audio` on it for its envelope.
2. `validate_workflow(name="templates/ltx2/refine-clip", arguments={"source_video":
   "asset:refine/src-512x288.mp4", "seed": 543})` gives `valid: true`. Bind the cost from `plan.estimate`.
3. `run_workflow` with the same arguments in workspace `regression-model-specific`, with
   `wait_seconds=55`, then `wait_for_job` to the end.
expected:
- The job succeeds. It has no `audio_no_headroom` or `audio_clipped` warning, from `pair_audio` or
  anywhere else. `pair_audio`'s `audio_padded_to_video`/`audio_trimmed_to_video` for an off-by-a-few-ms
  length is not a finding.
- The manifest has:
  - one `with_source_audio` file under `final/`, which `get_gallery_metadata` reads as exactly
    **1024×576, 121 frames, 24 fps**;
  - the `refine` file under `intermediate/`;
  - no saved file from `upscale`, which is `save: false`.
- **The soundtrack is the source's.** `get_output_audio` on the final file has the source's sample rate
  and channel count. Its duration is within one frame (≈42 ms) of 121/24 s, and `peak_dbfs` ≤ −3.0.
  Its per-second envelope follows the source's: loud and quiet seconds fall in the same places, offset
  by roughly one constant gain. A track denoised from noise would not follow it.
- **Same scene, not a new one.** `get_output_frames` at `frame:0`, `frame:60` and `frame:120` on the
  final file shows the source's composition at the same frames: same subjects, same positions, same
  framing. Motion runs the same direction between those frames. Finer texture may differ, since σ≈0.91
  regenerates it. `assess_output` on the final file has no sync-drift finding.
It is a **finding** if the final is not exactly 1024×576×121 at 24 fps, if its audio is generated rather
than the source's, if the peak is above −3 dBFS or a headroom/clipping warning fires, if the scene or
framing changes, or if the refine isn't kept in `intermediate/`.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`. Keep the fixture.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `512x288-121f`, to
`regression-perf/M-F064.jsonl`. The first run seeds the file.

### M-F065 — `refine-clip` stretches a source of the wrong aspect instead of refusing it, and a `num_frames` shorter than the source cuts picture and soundtrack together
source: tester, spec for #549 from #543's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F062. Paid: two LTX-2.5 refine jobs, run one at a time. Validation passes both
(the plan documents this behavior and does not refuse it). Each arm uses `"seed": 543` in workspace
`regression-model-specific`, with `get_gallery_metadata` on its source first. Fixtures:
`asset:refine/src-384x288.mp4` and `asset:refine/src-512x288.mp4` (see Fixtures). Make them if they
are missing.
expected:
- **Wrong aspect, stretched.** Run `source_video: "asset:refine/src-384x288.mp4"` (4:3) at the default
  `width` 512 / `height` 288:
  - validate is `valid: true` and gives no refusal, and the job succeeds;
  - the final is **1024×576**, 121 frames, 24 fps, carrying the source's soundtrack, as in M-F064;
  - its `frame:60`, next to the source's `frame:60`, shows the whole source picture widened by about
    4/3: content at the source's left and right edges is still there (not center-cropped), and round
    shapes read as wider.

  A crop, a letterbox/pillarbox, or a refusal is a finding.
- **Shorter than the source.** Run `source_video: "asset:refine/src-512x288.mp4"` (121 frames) with
  `num_frames: 97`:
  - the job succeeds, and the final is 1024×576, **97 frames**, 24 fps;
  - frames 0 and 96 follow the source's frames 0 and 96;
  - the final's audio lasts within one frame of 97/24 s (≈4.04 s), and its envelope follows the
    source's first ≈4 s. The plan says "cut to the video's length".
  - A `pair_audio` `audio_trimmed_to_video` warning is expected with `fit: "video"`, and is not a
    finding. `peak_dbfs` is ≤ −3.0.
It is a **finding** if either arm is refused, if the aspect arm crops instead of stretching, if the output
is not 2× the stated size, or if the short arm's picture and audio lengths disagree.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` for each arm's job. Keep the
fixtures.
metrics: `latency` (s) per arm, conditions `aspect-384x288` and `short-97f`, to
`regression-perf/M-F065.jsonl`. The first run seeds the file.

### M-F066 — `refine-clip` refuses a silent source before the pipeline load, naming the missing soundtrack
source: tester, spec for #549 from #543's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F062. At most one job, which must fail fast. The plan's Q2 decision is "refuse
early, before the ~80s pipeline load". It does not say whether that happens at validate or as a
first-step check, so either counts. Fixture: `asset:refine/src-512x288-silent.mp4` (or
`asset:upscale/src-480x272-silent.mp4`, or any mp4 with no audio stream; see Fixtures). Confirm with `get_gallery_metadata` that it has no audio stream. If none
exists, record "fixture missing" and skip. Pass `width: 512, height: 288`, so the size isn't what gets
refused.
Steps:
1. `validate_workflow(name="templates/ltx2/refine-clip", arguments={"source_video": <silent>, "width": 512,
   "height": 288, "seed": 543})`.
2. If that is `valid: true`, `run_workflow` with the same arguments and the quoted `acknowledged_cost`,
   `wait_seconds=55`, then `wait_for_job` to the end. Then read `get_job` and `get_job_events`.
expected, either one:
- **(a) Refused at validate.** `valid: false`, with an error at `arguments.source_video` saying the
  source has no soundtrack or audio stream. `run_workflow` with the same arguments is refused too, with
  no `job_id`.
- **(b) Refused as the job's first act.** The job **fails**, and its error names the missing soundtrack
  or audio stream in the source:
  - `get_job_events` shows no load of `LTX2LatentUpsamplePipeline` or `LTX2Pipeline` before the
    failure;
  - job `started_at`→`finished_at` is well under the ~80 s load (under 60 s);
  - the manifest has no `final/` file and no `refine` output.
In either case, a success, or a failure at `with_source_audio` after the refine has run (the late
failure `upscale-clip`'s M-F061 accepts, and this plan's Q2 rules out), is a **finding**. So is an
error that doesn't say the soundtrack is what's missing.
cleanup: if a job ran, `delete_output(job_id=<id>, workspace="regression-model-specific")`. Keep the
fixture.
metrics: none.

### M-F067 — a declared `vram_estimate` is checked against the device's capacity when the workflow has no `cost` block
source: tester, verified in #552 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 Ref2VA (plus Z-Image and MiniMax-Music3 steps), via an inline trimmed copy
of `templates/minimax/music-video`. Free: validate calls only.
Setup: **W** is `templates/minimax/music-video` (read with `get_workflow`) with its top-level `cost`
array **deleted**. Keep `vram_estimate` exactly as the template has it. Keep the steps `draw_singer`,
`write_song`, `slice` and `shot` (both references), and drop `edit`, `balanced` and `music_video`.
`shots` is one entry, `{"name": "one", "start_frame": 0, "prompt": "the otter sings"}`. You may drop
the `shot` step's quantization, offload and LoRA configuration, and the variables only they use.
Steps:
1. `validate_workflow(workflow=W, arguments={"num_frames": 345, "width": 4096, "height": 4096})`.
2. The same call, with `inline_workflow=W` in place of `workflow=W`.
3. `validate_workflow(workflow=W)`, with no arguments (the defaults 960x544x124 project to about 20 GB).
expected:
- Steps 1 and 2 are each `valid: false`, with an error at `variables.shots[0]` naming `shot@one`, the
  projected VRAM (172.76 GB with 2 references), and the device's own ceiling it exceeds.
- Step 3 is `valid: true` with no VRAM error or warning.
It is a **finding** if step 1 or step 2 is `valid: true`. A missing `cost` must not skip the check.
cleanup: none.
metrics: none.

### M-F068 — inserting an entry mid-list in a named `for_each` leaves the other members cached, and validate's `cached_steps` predicts it
source: tester, found while running TESTER_TASK.agent.md (ep86), claude-opus-5-5 via anthropic
The workflows guide says the step cache keys on the member name, so a shot inserted in the middle
of a named list leaves every other shot cached (an indexed list would shift them all). M-F020 covers
an edited entry on H3. This case covers an inserted one, cheaply, on LTX.
Model/pipeline: `Lightricks/LTX-2.5-Diffusers` `LTX2ImageToVideoPipeline`, `device: cuda`. Paid,
about 1.7 min for step 1 and under 30 s for step 3 on lem.
Setup: **W** is an inline workflow with `id: "QAM068"`, `seed: 86` and a `shots` variable. Its step
`shot` is `for_each: "variable:shots"`, with the `image_to_video` step of `templates/ltx2/image-to-video`
copied verbatim. Its arguments are `prompt: "item:prompt"`, `image: "item:image"`,
`num_frames: "item:num_frames"`, `width: 512` and `height: 288`, and its result is
`video/mp4 fps 24 intermediate`. After it comes `edit`, a `concat_videos` task with
`videos: "gather:shot"`, `fps: 24`, `match_levels: "rms"` and `match_levels_dbfs: -24`, whose result
is `video/mp4 fps 24 final`. **L2** is two entries. `accuse` uses
`asset:qa-cast/priya-portrait.jpg` with 49 frames and a quoted line. `deflect` uses
`asset:qa-cast/hal-portrait.jpg` with 57 frames and a quoted line. **L3** is L2 with `gasp` inserted
between them, using the priya portrait and 41 frames.
Steps (workspace = this suite's, passed on every call):
1. `validate_workflow(workflow=W, arguments={"shots": L2})`, then `run_workflow` with the bound
   acknowledgement and `wait_for_job`.
2. `validate_workflow(workflow=W, arguments={"shots": L3})`.
3. `run_workflow` with step 2's plan bound, then `wait_for_job`.
expected:
- Step 1: `plan.cached_steps: 0`, `list_entries.shots: 2`. The job succeeds, and the `edit` manifest
  entry places the two shots at 0/49 and 49/57.
- Step 2: `plan.cached_steps: 2`, `list_entries.shots: 3`, `steps: 4`.
- Step 3: `shot@accuse` and `shot@deflect` carry `reused: true`, and their `files` name **step 1's**
  run directory (deflect's file still carries step 1's index, `.1-0.0`). `shot@gasp` is a new file,
  and `edit` places the shots at 0/49, 49/41 and 90/57 (147 frames).
- It is a **finding** if `shot@deflect` regenerates in step 3: the cache keyed on the index, not the
  name. It is also a finding if step 2 predicts a number other than what step 3 reuses.
- (A `gasp` prompt with no quoted line renders near-silent and warns, per #434. That is expected, and
  not this case's concern.)
metrics: step 3's job `started_at`→`finished_at` in seconds (`latency`, condition `insert-cached`),
logged to `regression-perf/M-F068.jsonl`. A reading near step 1's time means the cache missed, even if
`reused` somehow survived.
cleanup: `delete_output(job_id=…)` for both jobs.

### M-F069 — a `for_each` composing `templates/ltx2/image-to-video` writes 24 fps members, and their join lands on the frame grid with zero sync drift
source: tester, found while running TESTER_TASK.agent.md (ep94, job `c27ae74f2e00`), claude-opus-5-5 via anthropic; locks in #561 and #562
Model/pipeline: `Lightricks/LTX-2.5-Diffusers` `LTX2ImageToVideoPipeline`, reached by composing the catalog
template by `path` (not a copied pipeline block, which M-F057/M-F068 cover). Paid, about 1.6 min on lem.
Setup: workspace = this suite's, passed on every call. Inline workflow, `id: "QAM069"`, `seed: 94`,
variable `shots` = two entries, each with `name`, `prompt`, `image`, `num_frames`:
- `dodge`: 49 f, `image: "previous_result:last"`, a one-line HAL prompt with a quoted line.
- `pounce`: 41 f, `image: {"location": "asset:qa-cast/priya-portrait.jpg"}`, a one-line PRIYA prompt with a quoted line.
Steps: `last` — task `get_last_frame(video={"location": "asset:qa-cast/ep92-episode.mp4"})`, result
`image/jpeg`, `save: false`. `shot` — `for_each: "variable:shots"`, `workflow: {path: "templates/ltx2/image-to-video",
arguments: {prompt: "item:prompt", image: "item:image", num_frames: "item:num_frames", width: 512, height: 288,
seed: 94}}`, result `video/mp4` intermediate (no `fps` on the result). `edit` — `concat_videos(videos: "gather:shot",
fps: 24, match_levels: "rms", match_levels_dbfs: -24)`, result `video/mp4` final. `validate_workflow` → bind
cost → `run_workflow(wait_seconds=55)` → `wait_for_job`.
expected:
- validate is `valid: true`, `warnings: []`, `list_entries.shots: 2`. The job succeeds with `warnings: []`.
- `get_gallery_metadata` on each `shot@<entry>` file: `fps: 24.0`, 512×288, `frame_count` 49 / 41,
  `sample_rate` 48000. (Before #561 the members were written at 8 fps.)
- The `edit` manifest's shots: `shot@dodge` 0/49 frames, 0/98000 samples; `shot@pounce` at frame 49, sample
  98000, 41 frames, 82000 samples, `hard_cut: true`.
- `assess_output(<edit file>, probe="analyze_sync_drift")`: `max_offset_ms: 0.0`, `length_delta_ms: 0.0`,
  `findings: []`. (Before #562 the second shot started at sample 96480, −31.67 ms.)
It is a **finding** if a member's `fps` isn't 24, if a shot's `num_samples` isn't `num_frames × 2000`, or if
the drift probe reads any offset. A `shot_dead_air` warning from the full assessment is take-dependent, not this case's concern.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `2shot-composed-512`, to `regression-perf/M-F069.jsonl`.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.

### M-F070 — `gather:<step>` inside a join's `videos` list, beside an `asset:` cut, flattens in order with the cut's inner shots
source: tester, found while running TESTER_TASK.agent.md (ep96, job `c63e21f40b91`), claude-opus-5-5 via anthropic
Model/pipeline: `Lightricks/LTX-2.5-Diffusers` `LTX2ImageToVideoPipeline`, via `templates/ltx2/image-to-video`
composed by `path`. Paid, about 1.8 min on lem. M-F069 covers `gather:` as the whole `videos` argument; this case
covers it as one element of a list.
Setup: workspace = this suite's, passed on every call. Same inline workflow as M-F069 with `id: "QAM070"`,
`seed: 96`, `last` reading `asset:qa-cast/ep95-episode.mp4` (512×288, 180 f, 44.1 kHz, 4 inner shots
`shot@dodge/pounce/retort/confess`), entries `alibi` (49 f, `previous_result:last`) and `glare` (57 f,
priya portrait), and `edit` = `concat_videos(videos: ["asset:qa-cast/ep95-episode.mp4", "gather:shot"], fps: 24,
match_levels: "rms", match_levels_dbfs: -24)`, result `video/mp4` final. validate → bind cost → run → wait.
expected:
- validate is `valid: true`, `warnings: []`, `list_entries.shots: 2`, `steps: 4`.
- The job succeeds. Its one warning is `concat_videos`' `sample_rate_mismatch` (44100 vs 48000, resampling to 48000)
  naming **three** videos: the gather expanded to two inputs, not one.
- The `edit` file: 286 frames, 24 fps, 512×288, 48000 Hz. Its `media.shots` lists six shots in order —
  `shot@dodge`, `shot@pounce`, `shot@retort`, `shot@confess` (the asset's inner shots, flattened) at frames
  0/49/90/139, then `shot@alibi` at frame 180 and `shot@glare` at 229 (57 f) — every seam after the first `hard_cut: true`.
It is a **finding** if the gather element is refused, passed through as a literal string, joined as one input, or
reordered, or if the asset's inner shots are lost. A few samples missing from the last shot is the mux shortfall
(#455), logged as a `shortfall_samples` event, not this case's concern; so is a `shot_dead_air` warning.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `asset-plus-gather-512`, to `regression-perf/M-F070.jsonl`.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.

### M-F071 — a list split at a `get_last_frame` dependency: two `for_each` lists, a derived still between them, and both gathered into one join
source: tester, found while running TESTER_TASK.agent.md (ep104, job `8831b7b1a6df`), claude-opus-5-5 via anthropic
Model/pipeline: `Lightricks/LTX-2.5-Diffusers` `LTX2ImageToVideoPipeline`, via `templates/ltx2/image-to-video`
composed by `path`. Paid, about 3.4 min on lem. This is the pattern the workflows guide's `for_each` section prescribes
for "shot 2 starts where shot 1 ended": M-F069/M-F070 cover one list; this covers an ordinary step reading one list's
member, feeding an item of a second list, and two `gather:` elements in one `videos` list.
Setup: workspace = this suite's, passed on every call. Inline workflow, `id: "QAM071"`, `seed: 104`, variables
`a` = entries `scoop` (49 f, `image: "previous_result:last"`, a HAL prompt with a quoted line) and `freeze` (41 f,
`image: {"location": "asset:qa-cast/priya-portrait.jpg"}`, a PRIYA prompt with a quoted line), and `b` = one entry
`drip` (41 f, `image: "previous_result:tail"`, a HAL prompt with a quoted line). Steps, in order:
`last` — `get_last_frame(video: "asset:qa-cast/ep103-episode.mp4")`, result `image/png`. `shot` — `for_each:
"variable:a"`, `workflow: {path: "templates/ltx2/image-to-video", arguments: {image: "item:image", prompt:
"item:prompt", num_frames: "item:num_frames", width: 512, height: 288, seed: 104}}`, result `video/mp4`. `tail` —
`get_last_frame(video: "previous_result:shot@scoop")`, result `image/png`. `coda` — `for_each: "variable:b"`, same
`workflow` block. `cut` — `concat_videos(videos: ["gather:shot", "gather:coda"], fps: 24, match_levels: "rms",
match_levels_dbfs: -24)`, result `video/mp4` final. validate → bind cost → `run_workflow(wait_seconds=55)` → wait.
expected:
- validate is `valid: true`, `warnings: []`, `steps: 6`, `list_entries` `{a: 2, b: 1}`. The job succeeds with
  `warnings: []`; the manifest lists `last`, `shot@scoop`, `shot@freeze`, `tail`, `coda@drip`, `cut` in that order.
- The `cut` manifest's shots: `shot@scoop` 0/49 frames, 0/98000 samples; `shot@freeze` at frame 49, sample 98000,
  41 frames, 82000 samples; `coda@drip` at frame 90, sample 180000, 41 frames, 82000 samples; both later seams
  `hard_cut: true`. `get_gallery_metadata` on it: 131 frames, 24 fps, 512×288, 48000 Hz.
It is a **finding** if validate refuses `previous_result:shot@scoop` in an ordinary step or `previous_result:tail`
inside a `b` item, if a run fails on something validate passed, or if either gather is dropped, joined as one input,
or reordered. `shot_dead_air` warnings from `assess_output` are take-dependent, not this case's concern.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `split-list-3shot-512`, to `regression-perf/M-F071.jsonl`.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.

### M-F072 — `separate_stems` splits a song into four 44.1 kHz stereo stems, and a later step reads one by name
source: tester, verified in #604, claude-opus-5-5 via anthropic
Model/pipeline: htdemucs (the `demucs` package's pretrained separator), via the `separate_stems` task; the
transcription step uses `transcribe_audio`'s default Whisper model. Took about 20 s on mps, with nothing to download.
Setup: workspace = this suite's, passed on every call. The input is the shared common asset
`asset:qa-cast/ep15-song.mp3`, a 30 s sung track. Inline workflow, `id: "QAM072"`, two steps:
`stems`: `separate_stems(audio: "asset:qa-cast/ep15-song.mp3")`, result `{content_type: "audio/wav",
file_base_name: "stems"}`. `lyrics`: `transcribe_audio(audio: "previous_result:stems.vocals")`, result
`application/json`. validate → bind cost → `run_workflow(wait_seconds=55)` → wait.
expected:
- validate is `valid: true`, `steps: 2`. The job succeeds.
- The `stems` manifest lists exactly four files: `stems-0.0-drums.wav`, `stems-0.0-bass.wav`,
  `stems-0.0-other.wav` and `stems-0.0-vocals.wav`.
- `get_output_audio` on the vocals file reports `duration_seconds` ≈ 30.0, the input's length. A 5 s excerpt is
  ≈ 882,000 bytes, i.e. 44.1 kHz 16-bit stereo.
- The `lyrics` text from `get_output_text` is non-empty English words: the vocal stem fed the transcriber.
It is a **finding** if a stem is missing or renamed, if `previous_result:stems.vocals` doesn't resolve, or if a
stem's length differs from the input's. A level warning on a stem (such as clipping on drums) is not this case's
concern.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`.

### M-F073 — one lip-sync check round on a real two-singer `minimax/music-video` cut, timed by rule 1
pending: #617
source: tester, spec for #617 from #488's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: `templates/minimax/music-video` (MiniMax H3), then `templates/attribute-lines` (Whisper, htdemucs,
ECAPA) and `get_output_frames`. This case **rides on** a two-singer `music-video` render that the suite or an episode
has already made, so it starts no new H3 render. Skip it, and say so, when none exists. C-F189 is the fixture
stand-in that always runs.
Setup: workspace = this suite's (or the render's own workspace, passed on every call). You need the cut's `output:`
reference, the song it was rendered over (the job's `song` input, an `asset:` or `output:` reference), the render's
`trim_frames` value from `get_job_workflow`, and two reference spans of at least 3 s each, one per singer, where
only that singer is heard.
1. `run_workflow("templates/attribute-lines", arguments={"audio": <the song>, "voices": {<singer A>: [...],
   <singer B>: [...]}}, acknowledged_cost=true, wait_seconds=55)`.
2. Timeline rule 1 (from C-F188's subsection): with `trim_frames` 0 or unset, song time is cut time. If
   `trim_frames > 0`, follow what the subsection says for it and record which you applied.
3. Pick two lines with a non-null `voice` and `uncertain: false`, one per singer if both have one. Then call
   `get_output_frames(name=<cut>, at=[L1.start+0.3, L2.start+0.3], crop=<a face box from a count:4 sheet>,
   hear=1.0)`. One call per face crop: when the singers are framed apart, make one call per face.
expected:
- Step 1 succeeds, and every line has numeric `start`/`end` within the song's duration.
- Step 3 returns one tile per moment, cropped, each with ~1 s of audio. Each tile's audio carries **that line's**
  vocal: the same words as the line's `text`, sung by the attributed voice.
- Record whose mouth is open in each tile. Per the plan this is the caller's judgment. The case passes on the chain
  working, not on the mouth being right; a wrong mouth is a fact about the render, not a finding.
It is a **finding** if the template fails on the song, if a tile's audio is not the line's vocal under rule 1 (the
times are then not cut time), or if `crop`/`hear` are ignored.
cleanup: `delete_output(job_id=<id>, workspace=…)` for the `attribute-lines` job only. The render belongs to whoever
made it.

#### The `hold_audio` carrier (M-F074 to M-F079, M-F081)

#598 adds no template variable for `hold_audio`, so these cases put it into an inline copy of a
template:
1. Take the JSON from `get_workflow("templates/minimax/<template>")`.
2. Add `"hold_audio": <reference>` to the `arguments` of the step that runs the MiniMax H3
   pipeline (the one carrying `num_frames`/`video_shift`).
3. Pass that JSON as the inline workflow to `validate_workflow` / `run_workflow`.

`arguments={...}` overrides the template's variables as usual. Work in workspace
`regression-model-specific`, which also sees the shared `common/assets` library (`asset:qa-cast/…`,
`asset:song/…`). At 24 fps, 124 frames is 124/24 = 5.167 s, and one frame is 0.042 s.

### M-F074 — `hold_audio` is a documented H3 input and validates clean on t2va, fl2va and ref2va
source: tester, spec for #618 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3, all three core-denoise sequences: t2va (`video-with-audio`), fl2va
(`image-to-video`) and ref2va (`reference-to-video`).
#618 inserts hold/release blocks into all three sequences. The plan's surface is one new pipeline
input, visible in `get_pipeline_signature`, with no new MCP tool.
Steps:
1. `get_pipeline_signature(<the H3 pipeline name from step 2 of the carrier>)`.
2. With the carrier, `validate_workflow` each of these with
   `"hold_audio": "asset:qa-cast/hal-voice.wav"` and `arguments={"seed": 42}`:
   - (a) `video-with-audio`;
   - (b) `image-to-video` with `"image": "asset:qa-cast/priya-portrait.jpg"`;
   - (c) `reference-to-video` with `"subject": "asset:qa-cast/priya-portrait.jpg"` and
     `"voice": "asset:qa-cast/priya-voice.wav"`.
3. Repeat (a) with `hold_audio` given as an `output:` reference, using any audio output that
   `list_gallery` shows in this workspace or `common` (skip it if none exists). Then repeat (a)
   with a `previous_result:` reference: add a step before the H3 step that runs `slice_audio`
   over `asset:qa-cast/hal-voice.wav`, and point `hold_audio` at its result.
expected:
- The signature lists `hold_audio`, described as audio (asset, output or previous_result).
- (a), (b), (c) and both step-3 forms are `valid: true`, with no warning naming `hold_audio`.
- `list_tasks` and the tool list gain no new tool or task for holding audio.
It is a **finding** if the signature doesn't show `hold_audio`, or if any of the three sequences
refuses it while another accepts it.
cleanup: none (validation only).
metrics: none.

### M-F075 — `validate_workflow` refuses `hold_audio` that isn't audio, is missing, or sits on a non-H3 step
source: tester, spec for #618 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 (`video-with-audio`), plus the SD 1.5 and LTX-2.5 templates as non-H3
steps.
The plan says validation refuses `hold_audio` that isn't audio, and either new argument on a
non-H3 step. This case covers those refusals, plus a missing asset and a non-reference string.
Probes, each through `validate_workflow` via the carrier on `video-with-audio` unless it names
another template:
- (a) `hold_audio: "asset:qa-cast/priya-portrait.jpg"` (an image);
- (b) `hold_audio: "asset:qa-cast/no-such-hold-probe.wav"` (missing);
- (c) `hold_audio: "hello"` (a plain string, not a reference);
- (d) `hold_audio: 5` (a number);
- (e) the SD 1.5 template. Find it in `list_workflows(shape="image")`: its summary or pipeline
  names Stable Diffusion 1.5. Add `"hold_audio": "asset:qa-cast/hal-voice.wav"` to its pipeline
  step's arguments;
- (f) `templates/ltx2/text-to-video` with the same `hold_audio` added to its pipeline step. The
  plan makes no LTX change, and LTX also makes audio;
- (g) `hold_audio: "asset:qa-cast/ep3-shot1-incident.mp4"` (a video that has an audio stream).
For every probe that `validate_workflow` refuses, also call `run_workflow(...,
acknowledged_cost=true)`.
expected:
- (a)–(f) are `valid: false`. Each error names `hold_audio` at the step's argument path and says
  why: not audio, not found, or not accepted by this pipeline. (b)'s error doesn't echo a
  resolved server path.
- `run_workflow` on (a)–(f) is refused with no job queued.
- (g): the plan doesn't say whether a video's audio stream counts as audio. Either outcome passes
  if it is decided at validate: `valid: false` naming `hold_audio`, or `valid: true` and a run
  whose `get_output_audio` is the clip's own soundtrack. Record which. A run that queues and then
  fails with a raw decode or shape error is refused too late, and is a **finding**.
It is a **finding** if any of (a)–(f) validates, or queues and fails in the pipeline rather than
being refused (refused too late), or if the SD 1.5 or LTX step silently ignores the argument and
runs.
cleanup: `delete_output(job_id=...)` for any job (only (g) should have one).
metrics: none.

### M-F076 — a t2va run with `hold_audio` returns the supplied track, cropped to the clip, not generated audio
source: tester, spec for #618 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va (`templates/minimax/video-with-audio`, turbo LoRA, 9 steps).
The plan's core promise: a held audio row is encoded from the supplied track and kept fixed, and
the output `audio` is the original waveform fitted to the video length, not a VAE round trip.
`asset:qa-cast/hal-voice.wav` is a 6.48 s, 24 kHz mono spoken line. At 124 frames it is cropped
to 5.167 s and resampled.
Steps:
1. `run_workflow` the carrier on `video-with-audio` with
   `"hold_audio": "asset:qa-cast/hal-voice.wav"` and `arguments={"seed": 42, "num_frames": 124,
   "prompt": "A middle-aged man in a grey sweater sits at a kitchen table and speaks directly to
   the camera, close-up, warm evening light."}`, with `acknowledged_cost=true, wait_seconds=55`.
   Then `wait_for_job` until it is done.
2. `get_gallery_metadata` on the mp4.
3. Transcribe both the output's audio and `asset:qa-cast/hal-voice.wav`. Use `get_output_audio`'s
   transcript if it gives one; otherwise run a one-step `transcribe_audio` workflow on each.
4. `get_output_frames(name=<mp4>, count=4, hear=1.0)`.
expected:
- The job succeeds, giving a 960×544 mp4 with `frame_count` 124 and an audio stream.
- The audio duration is 5.167 s to within one frame (0.042 s).
- The output transcript is the first ~5.2 s of hal-voice's transcript: the same words, in order,
  at the same pace, ending mid-line where the crop falls. It is the same voice at about the same
  level (`mean_dbfs` within ~3 dB of the source's over the same span).
- The frames show a coherent scene matching the prompt: no noise, no grey frames.
It is a **finding** if any of these:
- the job fails;
- the audio is silent, or has different words or a different voice (generated, not held);
- the audio is smeared or garbled the way a VAE round trip would make it, when a clean transcript
  of the source exists;
- the audio length is off by more than one frame.
cleanup: `delete_output(job_id=<id>)`.
metrics: `latency_s` (the whole job, from `get_job`). Record it in `regression-perf/M-F076.jsonl`
with condition `t2va-124f-960x544-hold`. The first run seeds the file. Flag a reading more than
50% over the median.

### M-F077 — without `hold_audio`, a seed-42 t2va run matches the pre-#618 render
pending: #618
source: tester, spec for #618 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va (`templates/minimax/video-with-audio`).
Plan decision D2: the hold/release blocks are always in the sequence and do nothing without
`hold_audio`, so the output must be identical to before the stage. The reference is the fixture
`asset:h3-hold/vwa-seed42-baseline.mp4` (see Fixtures), rendered before #618 deployed. If it is
missing, record "fixture missing" and skip. That is a note for Don, not an issue.
Steps:
1. `run_workflow("templates/minimax/video-with-audio", arguments={"seed": 42},
   acknowledged_cost=true, wait_seconds=55)`. Use the template's defaults otherwise, the same as
   the fixture's. Then `wait_for_job` until it is done.
2. `get_gallery_metadata` on both the output and the fixture.
3. `get_output_frames` on both, at the same four moments (0.5 s, 1.7 s, 3.4 s, 5.0 s), with
   `hear=1.0`.
expected:
- The same `frame_count`, size, duration and audio sample rate.
- The frames are indistinguishable at all four moments: same composition, subject pose, colours
  and background. The audio is the same sound at the same level (`mean_dbfs` within 0.5 dB).
- Equal file `size` is expected. If the sizes differ but the frames and audio are
  indistinguishable, record it as a note, not a finding.
It is a **finding** if any moment's frame visibly differs (other composition, pose or colour), or
the audio differs. The always-inserted blocks then changed the no-hold path.
cleanup: `delete_output(job_id=<id>)`. Keep the fixture.
metrics: none.

### M-F078 — `hold_audio` longer than the clip is cropped, shorter is padded with silence, and stereo 44.1 kHz is taken
source: tester, spec for #618 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va (`templates/minimax/video-with-audio`).
The plan: the track is resampled, encoded, then cropped or padded (encoded silence) to the
clip's audio-latent count. The output audio length equals the video length.
Runs, each through the carrier on `video-with-audio` with `seed` 42, using
`run_workflow(..., acknowledged_cost=true, wait_seconds=55)` and then `wait_for_job`:
- (a) crop: `hold_audio: "asset:qa-cast/ep11-bed.wav"` (19.667 s, 32 kHz mono), `num_frames` 124;
- (b) pad: `hold_audio: "asset:qa-cast/hal-voice.wav"` (6.48 s), `num_frames` 192, which is 8.0 s
  (17·11+5);
- (c) stereo and hot: `hold_audio: "asset:qa-cast/ep15-song.mp3"` (30 s, 44.1 kHz stereo,
  decodes at +0.76 dBFS), `num_frames` 124.
For each run, call `get_gallery_metadata(<mp4>, envelope=true)`. For (b), also transcribe the
audio (`get_output_audio`'s transcript or `transcribe_audio`).
expected:
- All three succeed. Each audio duration equals `frame_count`/24 to within one frame: 5.167 s
  for (a) and (c), 8.0 s for (b).
- (a) is the bed's opening 5.17 s, with a level close to the source's.
- (b): the first ~6.5 s carry hal-voice's whole line at normal speed, not stretched to 8 s. The
  transcript matches the source's in full. The envelope's last full second is near silence (well
  below the speech; `findings` may flag near silence there, which is expected).
- (c) is the song's opening 5.17 s, with no added distortion. `findings` may report the source's
  own full-scale level.
It is a **finding** if any run fails, if a length is off by more than one frame, if (b) is
time-stretched or its tail repeats or loops the speech instead of going silent, or if (c) fails
on stereo or 44.1 kHz input.
cleanup: `delete_output(job_id=...)` for each job.
metrics: none.

### M-F079 — `hold_audio` on ref2va keeps the reference image's identity, and on fl2va keeps the first frame
pending: #618
source: tester, spec for #618 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 ref2va (`templates/minimax/reference-to-video`, ref2v turbo LoRA) and
fl2va (`templates/minimax/image-to-video`).
In Ref2VA the hold block sits after the reference-row check. The plan promises that a held run
completes and keeps the image identity.
Runs, through the carrier, with `run_workflow(..., acknowledged_cost=true, wait_seconds=55)` and
then `wait_for_job`:
- (a) `reference-to-video` with `arguments={"seed": 42, "subject": "asset:qa-cast/priya-portrait.jpg",
  "voice": "asset:qa-cast/priya-voice.wav", "prompt": "The man sits in a quiet office and
  speaks to the camera, medium close-up."}` and `"hold_audio": "asset:qa-cast/priya-voice.wav"`.
  The template's `seed` defaults to null, so it must be pinned;
- (b) `image-to-video` with `"image": "asset:qa-cast/priya-portrait.jpg"`, `seed` 42, a prompt
  of him speaking, and the same `hold_audio`.
For each run, call `get_output_frames(count=4, hear=1.0)`, view `asset:qa-cast/priya-portrait.jpg`
with `get_output_image`, and transcribe the audio.
expected:
- Both jobs succeed, at 960×544 with 124 frames.
- (a): the face in all four frames is recognisably the portrait's person: hair, face shape, skin
  tone and apparent age.
- (b): frame 0 is the still.
- In both runs the audio is priya-voice's opening 5.17 s, the same words as the source's
  transcript, to within one frame of the video's length.
It is a **finding** if either job fails (for example, the reference-row check rejecting the held
row), if (a) loses the identity (a different-looking person), or if the audio is generated rather
than held.
cleanup: `delete_output(job_id=...)` for each job.
metrics: none.

### M-F080 — music-video and the chain-matched templates hold each shot's slice, and the docs state the measured lip-sync result
source: tester, spec for #619 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 templates `templates/minimax/music-video`,
`templates/minimax/chain-matched-to-audio` and `templates/minimax/chain-matched-and-aligned`.
Plan decision D4: each shot passes its slice of the track as `hold_audio`, replacing the
`AudioReference`, and the final mux stays. The plan's fallback: if the A/B (M-F081 / #619's
record) found hold worse, the templates keep the reference path and hold is opt-in. Read #619's
closing record (`gh issue view 619 --repo dkackman/diffusers-workflow --comments`) to learn which
branch shipped, and check the branch that shipped.
Steps:
1. `get_workflow` each of the three templates.
2. `validate_workflow` each at its defaults. `chain-matched-*` need the supplied-track variable
   (named in `get_workflow`; today `voice`) set to `asset:qa-cast/hal-voice.wav`. Also pass
   `subject: "asset:qa-cast/priya-portrait.jpg"` where the template has a `subject` variable.
3. Read the H3 sections of `get_guide("tasks")` (search for "lip-sync") and the `minimax-h3` skill.
expected:
- Hold branch: every H3 shot or segment step carries `hold_audio`, pointing at that shot's slice
  (a `previous_result:` of the slice step or equivalent). No shot step passes the track as an
  audio reference (`AudioReference`, or an `audio_reference_type` driving the shot). The final
  mux or `pair_audio` step against the full track is still there.
- Reference branch: the templates are unchanged from before #619. The docs say hold is opt-in and
  name `hold_audio`.
- All three validate clean, with no new warning.
- Neither the guide nor the skill keeps the unconditional claim that H3 "lip-syncs poorly when it
  must follow supplied audio". Both state the measured A/B result (which path won) consistently
  with the templates.
It is a **finding** if the templates and the docs disagree about which path is used, if any
template fails validation, if a shot step is missing its slice or holds the whole track, or if
the old claim survives unchanged.
cleanup: none (no job).
metrics: none.

### M-F081 — lip-sync A/B on `chain-matched-to-audio`: hold vs reference-only, on one sung track and seed
source: tester, spec for #619 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 `templates/minimax/chain-matched-to-audio` (ref2va chain), plus
`transcribe_audio`, `analyze_sync_drift` and `get_output_frames`.
This is the plan's stage-4 measurement. It is expensive: two chain renders of about 10 s each.
Fixture: `asset:h3-hold/sung-10s.wav` (see Fixtures). If it is missing, record "fixture missing"
and skip.
Arms. Both use the same `seed` 42, the same track (the template's supplied-track variable, today
`voice`, set to `asset:h3-hold/sung-10s.wav`), the same `subject: "asset:qa-cast/priya-portrait.jpg"`
and the same prompt ("A woman sings on a small stage, medium close-up, facing the camera."):
- (H) hold: the template as it ships, if M-F080 found the hold branch. Otherwise use an inline
  copy with each shot's slice added as `hold_audio`;
- (R) reference-only: the template's reference path. On the hold branch this is an inline copy
  with each shot step's `hold_audio` removed and the pre-#619 `AudioReference` wiring restored.
  #598's plan doesn't name a switch for this; use one if the template or guide documents it.
Run each arm with `run_workflow(..., acknowledged_cost=true, wait_seconds=55)` and `wait_for_job`.
Then, for each arm:
1. `transcribe_audio` on the track to get word or line onsets. Pick at least 3 onsets per shot
   (the segment boundaries are in `get_job_workflow` / `media.shots`).
2. `get_output_frames(name=<mp4>, at=[each onset + 0.1], crop=<the face box>, hear=1.0)`.
3. Run an `analyze_sync_drift` step on the arm's mp4 and record its reading.
expected:
- Both arms succeed. Each mp4's audio is the supplied track, to within one frame.
- Record per arm:
  - at each onset, whether the mouth is open on a sung syllable;
  - the `analyze_sync_drift` reading;
  - minutes, from `get_job`.
- Hold should match or beat reference-only. If it is worse, the templates must keep the
  reference path (M-F080's reference branch), and the case still passes.
It is a **finding** if either arm fails, if either output's audio isn't the track, or if
M-F080's shipped branch contradicts this case's measurement (hold shipped as default although it
measured worse).
cleanup: `delete_output(job_id=...)` for both jobs.
metrics: `minutes_hold`, `minutes_ref`, `onsets_matched_hold`, `onsets_matched_ref` (counts of
onsets with the mouth open). Record them in `regression-perf/M-F081.jsonl` with condition
`chain-sung10s-seed42`. The first run seeds the file. Flag a minutes reading more than 50% over
the median.

### M-F082 — the guide's 768p section documents the refine pass, and the guide's workflow validates
source: tester, spec for #620 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 + `upscale_h3_latents` + H3 refine (`refine_strength`).
Steps:
1. `list_guides`. Then `get_guide(<the guide holding it>, section="Promoting an H3 take to 768p in
   latent space")`.
2. `validate_workflow` the section's example workflow as written (inline). Then validate it again
   with `refine_strength` 0.001 and 0.999.
expected:
- The section exists and no longer says "There is no refine pass".
- Its example is base → `upscale_h3_latents` → an H3 step at 1344×768 with
  `latents: previous_result:up`, `refine_strength: 0.2` and
  `hold_audio: previous_result:base.audio` (step names may differ; the shape is what counts).
- The section, or the template/guide `cost_drivers` it points at, says refine runs
  `num_inference_steps − 1` evaluations, so refine time scales with `num_inference_steps`.
- The example validates clean. Both 0.001 and 0.999 are inside the open range and validate.
It is a **finding** if the old "no refine pass" text remains, if the example fails validation, or
if 0.001 or 0.999 is refused.
cleanup: none (validation only).
metrics: none.

### M-F083 — `validate_workflow` refuses `refine_strength` at 0, 1.0 and outside, and without `latents` or `hold_audio`
source: tester, spec for #620 from #598's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 refine (`refine_strength`), plus the SD 1.5 template as a non-H3 step.
The carrier is M-F082's example workflow, inline. Each probe edits only the refine step's
arguments:
- (a) `refine_strength: 0`;
- (b) `refine_strength: 1.0`;
- (c) `refine_strength: -0.2`;
- (d) `refine_strength: 1.5`;
- (e) `refine_strength: "0.2"` (a string);
- (f) `latents` removed (keeps `hold_audio`, keeps 0.2);
- (g) `hold_audio` removed (keeps `latents`, keeps 0.2);
- (h) both removed;
- (i) the SD 1.5 template (see M-F075 (e)) with `"refine_strength": 0.2` added to its pipeline
  step;
- (j) `templates/minimax/video-with-audio` (no latents, no hold) with `"refine_strength": 0.2`
  added to its H3 step.
For each refused probe, also call `run_workflow(..., acknowledged_cost=true)`.
expected:
- Every probe is `valid: false`. The error names `refine_strength` and gives the reason: the range
  (0,1) for (a)–(d), the type for (e), "requires both `latents` and `hold_audio`" for (f)–(h) and
  (j), and "not an H3 pipeline input" for (i).
- No probe queues a job.
- The unedited carrier validates clean as the control.
It is a **finding** if any probe validates, if (a) or (b) (the boundaries) is accepted, or if a
probe queues and fails in the pipeline (refused too late).
cleanup: `delete_output(job_id=...)` for any job (none should exist).
metrics: none.

### M-F087 — `LTX2RefinePipeline` is discoverable, and its signature has `video` beside the parent's `latents`, `noise_scale` and `sigmas`
source: tester, spec for #638 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: `LTX2RefinePipeline` (dw community pipeline, subclass of `LTX2Pipeline`). Free: discovery only.
Context: on 2026-10-05 neither `list_pipelines` nor `get_pipeline_signature` showed community
pipelines. `get_pipeline_signature("RFInversionFluxPipeline")` answered "diffusers exports no class
named …". The stage's acceptance intent says both tools show the new class, so this case holds it to that.
Steps:
1. `list_pipelines` (filter on `LTX2` if the tool takes one).
2. `get_pipeline_signature("dw.community_pipelines.pipeline_ltx2_refine.LTX2RefinePipeline")`.
3. `get_pipeline_signature("LTX2Pipeline")`, for comparison.
4. `get_guide("workflows")` index. Find the community-pipelines line the plan adds (it names
   `LTX2RefinePipeline`) and read that section.
expected:
- `LTX2RefinePipeline` is listed by `list_pipelines`, marked or grouped so it is distinguishable from
  diffusers' own classes (a "community" source or equivalent). A plain listing is acceptable as long as
  step 2 works.
- Step 2 succeeds. It lists a `video` parameter, and still lists `latents`, `noise_scale`, `sigmas`,
  `width`, `height` and `num_frames`, with the same defaults step 3 shows for them.
- Apart from `video`, its parameters match `LTX2Pipeline`'s. No ladder or strength parameter appears:
  the plan keeps the class free of ladder and model constants.
- The guide's community-pipelines text names `LTX2RefinePipeline`. It says `video` is VAE-encoded at
  `width`×`height` and stands in for `latents`, and that the two can't be passed together.
It is a **finding** if `list_pipelines` omits the class, if `get_pipeline_signature` refuses it or
lacks `video`, if a parent parameter is missing or has a changed default, or if the guide has no line
for it.
cleanup: none (no job).
metrics: none.

### M-F088 — a hand-authored `loop_frames` → `LTX2RefinePipeline` workflow refines a 512×288×121 clip in place: same size, same frames, same scene
source: tester, spec for #638 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: `LTX2RefinePipeline` on `Lightricks/LTX-2.5-Diffusers` (stage-two distilled schedule).
Paid: one LTX refine job at 512×288, 121 frames (about the cost of `refine-clip`'s refine step).
Setup: fixture `asset:refine/src-512x288.mp4` (see Fixtures). Make it first if it is missing.
Steps:
1. `get_gallery_metadata("asset:refine/src-512x288.mp4", workspace="regression-model-specific")` pins the
   source's size (512×288), frames (121) and fps (24). Take `get_output_frames` on it at `frame:0`,
   `frame:60` and `frame:120` for comparison.
2. `get_workflow("templates/ltx2/refine-clip")`, to copy its `refine` step's pipeline block:
   `from_pretrained_arguments`, offload and component settings, prompt handling and `frame_rate`.
3. Author an inline workflow from that block with two steps:
   - `src`: `loop_frames(video: "asset:refine/src-512x288.mp4", num_frames: 121)`;
   - `refine`: a pipeline step with `component_type` `LTX2RefinePipeline`, named the way the guide's
     community-pipelines line (M-F087 step 4) says. Arguments: `video: "previous_result:src"`, `width`
     512, `height` 288, `num_frames` 121, `noise_scale` 0.909375, `sigmas` the three stage-two distilled
     values (as `refine-clip` names them, or literally), and `seed` 543. Its result is `video/mp4` at
     24 fps.
4. `validate_workflow` on it, then `run_workflow(..., acknowledged_cost=true, wait_seconds=55)` in
   workspace `regression-model-specific`. Then `wait_for_job` to the end.
expected:
- Validate is `valid: true` with no unknown-component or unknown-argument error. The step loads
  `LTX2RefinePipeline` and no separate upsampler.
- The job succeeds. Its output reads under `get_gallery_metadata` as exactly **512×288, 121 frames,
  24 fps**: not 1024×576 (that is `refine-clip`'s 2× route), and not a frame count snapped elsewhere.
- **Same scene, refined in place.** `get_output_frames` at frames 0, 60 and 120 shows the source's
  composition at the same frames: same subjects, positions and framing, with motion running the same
  way. Fine texture may differ.
- **Not washed out.** Exposure and saturation look like the source's. The plan's own risk is an encode
  normalization mismatch, which shows as a uniformly greyer or flatter picture than the source.
- `get_job_events` shows one denoise pass of three sigma steps, not a full schedule.
It is a **finding** if validate refuses the class or `video`, if the output size or frame count differs
from the source's, if the scene changes, or if the picture is visibly greyed or flattened against the
source.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")`. Keep the fixture.
metrics: `latency` (job `started_at`→`finished_at`, s), condition `512x288-121f`, to
`regression-perf/M-F088.jsonl`. The first run seeds the file.

### M-F089 — `LTX2RefinePipeline` refuses `video` and `latents` together, naming both, before it denoises
source: tester, spec for #638 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F088. Free if refused at validate. Otherwise one job that fails before denoising.
Setup: M-F088's workflow, with one argument added to the `refine` step: `latents:
"previous_result:src"` (any value will do; the refusal is about the pair). If that doesn't validate as a
type, add a cheap step whose result is a latent tensor (e.g. an `LTX2Pipeline` step with
`output_type: "latent"`, the same call M-F088 uses) and point `latents` at it.
Steps:
1. `validate_workflow` on it.
2. If validate passes, `run_workflow(..., acknowledged_cost=true, wait_seconds=55)` and `wait_for_job`
   to the end. Then `get_job_events`.
expected:
- The refusal comes at validate, or the job fails at the `refine` step before any denoise step (no
  step-progress events from the denoise loop).
- The message names **both** `video` and `latents` and says they can't be given together. A generic
  type error, or a shape mismatch from inside the transformer, does not count.
- No output file is written.
It is a **finding** if the pair is accepted (either one silently wins), if the failure comes from deep in
the denoise loop, or if the message doesn't name both arguments.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` if a job ran.
metrics: none.

### M-F090 — `LTX2RefinePipeline` encodes a `video` whose size differs from `width`×`height` at `width`×`height`, and without `video` it behaves like `LTX2Pipeline`
source: tester, spec for #638 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F088. Paid: two short LTX jobs.
The plan says `video` is VAE-encoded at `width`×`height`. This case covers a source that isn't already
that size, and the subclass with `video` left out.
Setup: fixture `asset:refine/src-384x288.mp4` (see Fixtures).
Steps:
1. **Size differs.** M-F088's workflow with `video` from `loop_frames(video:
   "asset:refine/src-384x288.mp4", num_frames: 121)`, and `width` 512, `height` 288. Validate, then run
   as in M-F088.
2. **No `video`.** M-F088's `refine` step with `video` removed and a `prompt` set (any short prompt; `refine-clip`'s
   default is fine). `width` 512, `height` 288, `num_frames` 121, `seed` 543, with the parent's default
   schedule (drop `sigmas` and `noise_scale`). Validate, then run.
expected:
- Step 1 succeeds at **512×288, 121 frames**. The source's content is resized to fit, not cropped or
  padded off-centre: subjects stay in the source's relative positions. Alternatively it is refused at
  validate, with a message naming the size mismatch and the expected size. Either is acceptable;
  record which.
- Step 2 succeeds and gives a 512×288×121 text-to-video clip, as `LTX2Pipeline` would. It is not an
  error about a missing `video`.
It is a **finding** if step 1 crashes in the VAE or transformer with a shape error, or yields a size
other than 512×288. It is also a finding if step 2 requires `video`.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` for each job.
metrics: none.

### M-F091 — `refine-in-place` is in the catalog as a shot with audio, and its first step selects a ladder by `strength` from 3–5 well-formed candidates
source: tester, spec for #639 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: `templates/ltx2/refine-in-place` (`LTX2RefinePipeline`). Free: discovery only.
Steps:
1. `list_workflows(shape="shot")`, then `list_workflows(shape="shot", include_models=true)`.
2. `get_workflow("templates/ltx2/refine-in-place", variables_only=true)`.
3. `get_workflow("templates/ltx2/refine-in-place")`.
4. Load the `dw:ltx-2-5` skill (or whichever LTX skill `refine-clip` is documented in).
5. `get_workflow` on `templates/ltx2/refine-clip` and `templates/ltx2/two-stage` (the non-goals).
expected:
- **Catalog.** `templates/ltx2/refine-in-place` is listed under `shot` with traits `has-audio` and
  `needs-input-media`. It has a non-null `cost` in the same units as `refine-clip`'s.
- **Variables.** There is a `strength` variable whose default is the **middle** ladder index
  (`(N-1)//2`, or `N//2` if the plan text reads that way for even N; record which). Its constraint or
  description gives the range 0..N-1. `width`/`height` constraints are `32*n+0` and `num_frames`'s is
  `8*n+1, 9+`, as `refine-clip` has them, on whichever route they still apply to.
- **The `select` step.** One `select` step, before any pipeline step, with `rule: "index"` and `index:
  "variable:strength"`. Let N be its candidate count:
  - **3 ≤ N ≤ 5**;
  - every candidate is a dict `{"sigmas": [...], "noise_scale": …}`;
  - every `sigmas` holds exactly **3** values, **strictly decreasing**, with **no trailing 0**;
  - every `noise_scale` **equals its `sigmas[0]`**;
  - `sigmas[0]` **increases with index**: 0 preserves most, N-1 reinterprets most.
  `select` declares `scores` required (pinned 2026-10-05). Whatever the template passes there must
  validate.
- **The refine step** reads `previous_result:<select step>.sigmas` and `.noise_scale`, with no literal
  schedule of its own. Its result is saved under `intermediate/`. A `pair_audio` step writes the
  deliverable under `final/` from the source's soundtrack.
- **Route.** Either:
  - **fit/restore**: `normalize_audio` → `fit_to_model` → select → refine → `restore_to_source` →
    `pair_audio`; or
  - **trim**: `normalize_audio` → `loop_frames` → select → refine → `pair_audio`.
  Record which; M-F092 to M-F095 depend on it.
- **Description** says the template is unsourced, and that the vendor's route to refined detail is the
  Refine-Details IC-LoRA.
- **Skill** carries:
  - a routing line for a same-size refine pointing at `refine-in-place`;
  - the "the schedule is not a knob" rule, reworded to except `refine-in-place`'s `strength`;
  - the rule `noise_scale = sigmas[0]`;
  - a cost line for `refine-in-place`.
- **Non-goals unchanged.** `refine-clip` still upsamples 2× with its fixed stage-two schedule and has
  no `strength` variable. `two-stage` has no `strength` variable either.
It is a **finding** if the template is missing from `shot`, if it lacks either trait or a cost, if any
ladder breaks the five rules above, if `strength`'s default isn't the middle index, if `refine-clip` or
`two-stage` gained a `strength`, or if the skill lacks any of the four lines.
cleanup: none (no job).
metrics: none.

### M-F092 — `refine-in-place` validates clean at its defaults, and on the trim route refuses off-grid `width`, `height` and `num_frames` at validate
source: tester, spec for #639 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F091. Free: validate only.
Setup: fixture `asset:refine/src-512x288.mp4`. Read N and the route from M-F091 steps 2–3; don't assume
either.
Steps:
1. `validate_workflow(name="templates/ltx2/refine-in-place", arguments={<its source-video variable>:
   "asset:refine/src-512x288.mp4"})`. The bare call, with the template's placeholder source, may be
   refused for want of a real asset; that is not a finding.
2. The same, with each of `strength` = 0, the middle index, and N-1.
3. **Trim route only:** step 1 with each of:
   - `width` 500;
   - `height` 300;
   - `num_frames` 120.
4. **Fit/restore route only:** the same three arguments, if the template still exposes `width`, `height`
   or `num_frames` on that route. Record which it exposes.
expected:
- Steps 1 and 2 are `valid: true`, with no error or warning. Each quotes a `plan.estimate`, and the
  estimates for the three strengths are the same or nearly so (the ladders all have three steps).
- Step 3: each is refused at validate, the message naming the variable and the `32*n+0` or
  `8*n+1, 9+` rule. Snapping with a warning, if the constraint declares `snap`, is acceptable instead;
  record which. No job is made.
- Step 4: where fit/restore picks the model size itself, those arguments are absent or have no effect.
  Neither is a finding; record which.
It is a **finding** if the defaults don't validate clean against a real asset, if the estimate swings
with `strength`, or if on the trim route an off-grid size or frame count passes validate silently.
cleanup: none (no job).
metrics: none.

### M-F093 — `refine-in-place` refuses `strength` N, −1 and 1.5 in the select step, naming the range, before any pipeline loads
source: tester, spec for #639 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F091. Free when refused at validate. Otherwise each is a job that must fail before
any model loads, so it costs seconds.
Setup: as M-F092. N is the candidate count from M-F091.
Steps: for each `strength` in **N** (one past the end), **−1**, **1.5** and **"1"** (a string), with the source
set as in M-F092 step 1:
1. `validate_workflow`.
2. If valid, `run_workflow(..., acknowledged_cost=true, wait_seconds=55)`, then `wait_for_job` to the end
   and `get_job_events`.
expected:
- N and −1 are refused, either at validate (a `strength` constraint) or as a failure of the `select` step.
  The message names the valid range (0..N-1, with N-1 as a number) and the value given. −1 must not
  wrap to the last ladder, the way Python indexing would.
- 1.5 is refused as not an integer, by the same route. It must not be truncated to 1.
- `"1"` is either refused as a non-integer or coerced to 1 and run as strength 1. Record which. Either is
  acceptable unless it is coerced silently while 1.5 is truncated.
- A refused job's events show no `LTX2RefinePipeline` or model load, and no download. The failure is
  the `select` step's (or an earlier step's) and finishes within 60 s.
It is a **finding** if any of N, −1 or 1.5 runs a ladder, if −1 selects the last ladder, if the message
lacks the range, or if a pipeline loads before the refusal.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` for any job made.
metrics: none.

### M-F094 — `refine-in-place` refuses a silent source in `normalize_audio`, before any pipeline loads
source: tester, spec for #639 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F091. Free when refused at validate. Otherwise a job that fails in seconds.
Setup: fixture `asset:refine/src-512x288-silent.mp4`, or `asset:upscale/src-480x272-silent.mp4` (see
Fixtures; on the trim route use the 512×288 one so size isn't what refuses it).
Steps:
1. `validate_workflow(name="templates/ltx2/refine-in-place", arguments={<source variable>: <silent asset>})`.
2. If valid, `run_workflow(..., acknowledged_cost=true, wait_seconds=55)`, then `wait_for_job` and
   `get_job_events`.
expected:
- Refused at validate, or the job fails at `normalize_audio`, its first step. The message says the source
  has no audio (or is silent) and names the asset.
- No refine pipeline load and no download in the events. The job finishes within 60 s.
- No `final/` or `intermediate/` file is written.
It is a **finding** if a silent source is refined (with or without a soundtrack), or if the refusal comes
after the pipeline loads.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` if a job ran.
metrics: none.

### M-F095 — `refine-in-place` at strength 0, the middle and N-1: right size, the source's soundtrack, change rising with strength, run time flat
source: tester, spec for #639 from #606's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: as M-F091. Paid: three LTX refine jobs at 512×288, 121 frames. When N > 3, run the other
strengths too: the stage's intent is "each strength".
Setup: fixture `asset:refine/src-512x288.mp4`. Read N and the route from M-F091.
Steps:
1. Pin the source as M-F064 step 1 does (`get_gallery_metadata`, `get_output_audio`), and take
   `get_output_frames` on it at `frame:0`, `frame:60` and `frame:120`.
2. For each `strength` in 0, the middle index, N-1 (and every other index when N > 3), with `seed` 543:
   `run_workflow(name="templates/ltx2/refine-in-place", arguments={<source>:
   "asset:refine/src-512x288.mp4", "strength": s, "seed": 543}, acknowledged_cost=true, wait_seconds=55)`
   in workspace `regression-model-specific`. Then `wait_for_job` to the end, `get_job`, and
   `get_gallery_metadata` on each saved file.
3. `get_output_frames` at frames 0, 60 and 120 on each final file. Also `crop` one detailed region
   (faces, text or foliage) at frame 60 of the source and of each output.
4. `get_output_audio` on each final file. Run `assess_output` on each final file.
expected:
- Every job succeeds with no `audio_no_headroom` or `audio_clipped` warning.
- **Size.**
  - fit/restore route: every final reads as the **source's own size, 512×288**, 121 frames, 24 fps;
  - trim route: `width`×`height` at the defaults, with the default `num_frames`.
  It is never 2× the source.
- **Layout.** Per job, one `final/` file from `pair_audio` and the refine's picture in `intermediate/`.
- **Soundtrack is the source's**, as in M-F064: same sample rate and channels, duration within one frame,
  `peak_dbfs` ≤ −3.0, and a per-second envelope following the source's.
- **Same scene at every strength**: same subjects, positions and framing at frames 0, 60 and 120, motion
  in the same direction.
- **Change rises with strength.** Against the source's frames and crop:
  - strength 0's output is the closest (fine detail sharpened or cleaned, little reinterpreted);
  - N-1's is the farthest (texture and small detail visibly regenerated);
  - the middle sits between.
  Record a one-line description per strength. The order is the pass condition; the amount is not.
- **Run time is flat.** Every ladder has three steps, so each job's `started_at`→`finished_at` is
  within 20% of the median of the three (a cold first load excluded: rerun the first strength if it
  carried the model download or load).
It is a **finding** if any job fails, if a final's size differs from the route's expected size, if the
soundtrack is generated or headroom is lost, if the scene changes, if a lower strength changes the
picture more than a higher one, or if one strength's run time is more than 20% off the others'.
cleanup: `delete_output(job_id=<id>, workspace="regression-model-specific")` for every job. Keep the
fixture.
metrics: `latency` per job, condition `512x288-121f-s<strength>` (e.g. `-s0`, `-s2`), to
`regression-perf/M-F095.jsonl`. The first run seeds the file.

### M-F096 — the 768p guide section documents refine schedule (B): 5 points / 0.2 example, evaluations = `num_inference_steps − 1`, and 2 points validates
source: tester, spec for #620 from #598's plan v4 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 + `upscale_h3_latents` + H3 refine (`refine_strength`, schedule (B)).
This case covers what plan v3/v4 changed. M-F082's own claim that refine time doesn't scale with
`num_inference_steps` is superseded by D6. Where the two disagree, this case is the current one.
Steps:
1. `list_guides`. Then `get_guide(<the guide holding it>, section="Promoting an H3 take to 768p in
   latent space")`.
2. `validate_workflow` the section's **first** JSON example as written (inline). Then do the same
   for the **refine** example, at its written values.
3. Validate the refine example again three times, each with only the refine step changed:
   `num_inference_steps: 2`, then `num_inference_steps: 6`, then `refine_strength: 0.4`.
expected:
- The section no longer says "There is no refine pass" or anything like it.
- The first JSON example is still the upscale-only workflow (base → `upscale_h3_latents` → decode
  → `pair_audio`, no `refine_strength`). The refine example comes **after** it.
- The section still names `upscale_h3_latents`, `pair_audio`, `previous_result:base.videos` and
  `"fps": 24`.
- The refine example is base → `upscale_h3_latents` → an H3 step at 1344×768 with
  `latents: previous_result:up` (or whatever the upscale step is named), `refine_strength: 0.2`,
  `num_inference_steps: 5` and `hold_audio: previous_result:base.audio`.
- The cost note says refine runs `num_inference_steps − 1` evaluations, so 4 at the example's 5.
  It does not say refine cost is independent of `num_inference_steps`.
- Where the section calls hold opt-in, it says refine uses hold to keep the base pass's own audio,
  and that this is a different case from lip sync to supplied audio.
- Both examples validate clean, and so do all three variants. `num_inference_steps: 2` is the
  smallest legal value (one evaluation).
It is a **finding** if any of these:
- the "no refine pass" text remains;
- the refine example is the first JSON block, or has a different strength or step count from 0.2
  and 5;
- the cost note is missing or still says cost doesn't scale with `num_inference_steps`;
- either example or any variant fails validation (2 points is the boundary and must pass).
cleanup: none (validation only).
metrics: none.

### M-F097 — `validate_workflow` refuses `refine_strength` with fewer than 2 points, and on an LTX step; with no `refine_strength`, few points are not a refine error
source: tester, spec for #620 from #598's plan v4 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 refine, plus `templates/ltx` (any LTX-2/2.5 t2v template in
`list_workflows(shape="shot")`) as a non-H3 step.
Covers the refusals plan v3 added. M-F083's probes (a)–(j) stand and still apply. The carrier is
M-F096's refine example, inline. Each probe edits only the refine step's arguments:
- (a) `num_inference_steps: 1` with `refine_strength: 0.2`;
- (b) `num_inference_steps: 0` with `refine_strength: 0.2`;
- (c) an LTX template (named above) with `"refine_strength": 0.2` added to its pipeline step;
- (d) the control: `templates/minimax/video-with-audio` with `num_inference_steps: 1` and no
  `refine_strength`.
For each refused probe, also call `run_workflow(..., acknowledged_cost=true)`.
expected:
- (a) and (b) are `valid: false`. The error names `num_inference_steps` and/or `refine_strength`,
  and says refine needs at least 2 points.
- (c) is `valid: false`, saying `refine_strength` is not an input of that pipeline (or that it is
  H3-only).
- No refused probe queues a job.
- (d) gets no error that mentions `refine_strength` or refine: the new rule applies only when
  `refine_strength` is set. Whatever H3's pre-existing rule on one step is, it still applies.
It is a **finding** if (a), (b) or (c) validates, if a refused probe queues and fails in the
pipeline (refused too late), or if (d) is refused with a refine error.
cleanup: `delete_output(job_id=...)` for any job (none should exist).
metrics: none.

### M-F098 — refine schedule (B): 4 evaluations at 5 points and 5 at 6; strength 0.4 runs the same 4 and moves the picture further than 0.2; audio and composition kept
source: tester, spec for #620 from #598's plan v4 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va at 960×544 + `upscale_h3_latents` + H3 refine at 1344×768.
This replaces M-F084's evaluation expectations. D6 reversed M-F084's "0.4 runs more evaluations
than 0.2" and "refine doesn't run `num_inference_steps`". Its audio and composition checks are
repeated here. Plan: σ₀ = `refine_strength`, then `num_inference_steps` shift-spaced points down to
0, which is `num_inference_steps − 1` evaluations. Only the generated rows are re-noised, seeded
from the step's generator.
Steps:
1. `save_workflow` M-F096's refine example as `m-f098-h3-refine`, with `num_frames` 124 and
   `seed` 42. Add these extra outputs:
   - the base's own mp4 with its audio;
   - an `ident` branch: `decode_h3_latents` on the upscale step's result, then `pair_audio` with
     the base audio. This is the upscale-only decode, as in M-F041.
   Make `refine_strength` and the refine step's `num_inference_steps` workflow variables
   (defaults 0.2 and 5), so the re-runs below only change arguments.
2. Run A: `run_workflow(name="m-f098-h3-refine", acknowledged_cost=true, wait_seconds=55)`, then
   `wait_for_job` until it is done.
3. `get_job_events` on run A. Count the refine step's denoise step-progress events and read its
   reported progress total. Use `get_job` for the step's duration.
4. Run B: same, with argument `num_inference_steps` 6. Run C: same, with `refine_strength` 0.4 at
   5 points. In both, the base and upscale steps should come from the step cache. Count
   evaluations as in step 3.
5. `get_output_frames` on A's refined mp4, C's refined mp4, `ident` and the base, at the same four
   moments, plus one `crop` on a detailed region. Compare audio with `get_output_audio` and
   `get_gallery_metadata`.
expected:
- All three jobs succeed. Every refined mp4 is 1344×768 with `frame_count` 124.
- **Evaluations:** A runs exactly **4** refine evaluations, B runs **5**, and C runs **4**. The
  refine step's progress total matches its count (N points report N−1 steps).
- B's refine duration is longer than A's (time scales with points). C's is within about 20% of A's.
- **Audio:** each refined mp4's audio is the base's track, with the same sound and level and a
  duration within one frame. It is not regenerated.
- **Composition at 0.2:** A keeps `ident`'s subject placement, pose, layout and motion direction,
  with equal or sharper detail and no colour cast or residual noise.
- **Strength moves further:** C is recognisably the same scene, but differs from `ident` more than
  A does (detail and texture visibly more regenerated in the crop). Record a one-line description
  of each.
It is a **finding** if any of these:
- a job fails, or a size or frame count differs;
- A ≠ 4, B ≠ 5 or C ≠ 4 evaluations, or the refine runs 0 evaluations (v2's bug) or the full
  schedule from σ 1;
- the audio differs from the base's (generated, shifted or missing);
- A changes the composition (a different picture);
- C is no further from `ident` than A, or C runs a different count from A.
cleanup: `delete_output(job_id=...)` for all three jobs; `delete_workflow("m-f098-h3-refine")`.
metrics: `latency_s`, `refine_s` and `refine_evals` per job, to `regression-perf/M-F098.jsonl`,
with conditions `124f-960x544-to-1344x768-p5-s0.2` (A), `…-p6-s0.2` (B) and `…-p5-s0.4` (C). The
first run seeds the file. Flag a reading more than 50% over the median.

### M-F100 — `prompts` passed down through a composing step gives each LTX chain segment its own line, spoken once
source: tester, found while running TESTER_TASK.agent.md (ep113; #652 is the template-level fix)
Needs LTX-2.5 (`Lightricks/LTX-2.5-Diffusers`) via `templates/ltx2/chained-segments`, about
1.5 min. A consumer giving each segment its own dialogue line usually composes the template
from an inline workflow, so `prompts` (a list) travels as a `workflow:` step argument and the
segment image comes from `previous_result:`. Inline workflow, `id` `m-f100-chain`, `seed` 113:
step `last` = task `get_last_frame` with `video: "asset:qa-cast/ep112-episode.mp4"`, `result`
`{"content_type": "image/png", "save": false}`; step `chain` = `workflow: {"path":
"templates/ltx2/chained-segments", "arguments": {"image": "previous_result:last", "width": 512,
"height": 288, "num_frames": 49, "segments": 2, "seed": 113, "prompt": "A kitchen at night, two
people by an open freezer.", "prompts": ["A wiry woman in a mustard sweater vest and glasses
points at an empty pistachio ice cream tub and says quickly, \"You ate the whole thing,
Hal.\"", "A heavyset bald man in a gray flannel shirt shrugs, deadpan, and says, \"The freezer
did it.\""]}}`, `result` `{"content_type": "video/mp4", "subfolder": "final"}`.
`validate_workflow` it, then `run_workflow` with the bound acknowledgement. Then run
`templates/transcribe-audio` with `input_audio: "output:<the chain video>"` and read the text
with `get_output_text`.
expected:
- validate is clean, and the run succeeds. The chain video is 512×288, 24 fps, 96 frames
  (49 + 47 after the 2-frame trim), 48 kHz. Its manifest entry carries 2 `shots`, `segment 1`
  and `segment 2`.
- The transcript holds "ate the whole thing" once and "freezer did it" once. Each line is
  spoken once, not repeated per segment.
It is a **finding** if a line is missing, if either line appears twice (the composed `prompts`
was dropped and `prompt` repeated, #652), or if the validate verdict doesn't hold at run.
cleanup: `delete_output(job_id=…)` for both jobs.
metrics: none.

### M-F101 — a chain's own seam crossfade is recorded, assessed as intentional, and survives a re-pair with a bed
source: tester, found while running TESTER_TASK.agent.md (ep115; #660 verified the record)
Needs LTX-2.5 via `templates/ltx2/chained-segments`, about 1.5 min plus an 8 s task job. Run
M-F100's inline workflow, but with `id` `m-f101-chain`, `seed` 115, `video:
"asset:qa-cast/ep114-episode.mp4"` in `last`, and **no steps after `chain`**. A later step that
reads `previous_result:chain` fails today (#667). `keep_output(name=<the chain video>,
asset_name="regression/m-f101-chain.mp4")` in the case's workspace. Then run a second inline
workflow, `id` `m-f101-bed`: `bed` = `loop_audio` (`audio: "asset:uploads/qa-cast/room-bed.wav"`,
`target_frames: 96`, `fps: 24`) → `mix` = `mix_audio` (`audios: ["asset:regression/m-f101-chain.mp4",
"previous_result:bed"]`, `gains: [1, 4]`) → `norm` = `normalize_audio` (`peak_dbfs: -3`,
`target_lufs: -16`, `limit: true`) → `episode` = `pair_audio` (`video:
"asset:regression/m-f101-chain.mp4"`, `audio: "previous_result:norm"`, `fit: "video"`, `result`
`{"content_type": "video/mp4", "subfolder": "final"}`). The first three steps' `result` is
`{"content_type": "audio/wav", "save": false}`.
expected:
- The chain's manifest `shots` has `segment 1` (49 f) and `segment 2` (47 f, `trim_frames: 2`,
  `crossfade_ms: 80.0`).
- `assess_output(probe="analyze_seams")` on the chain video: seam 1 has `hard_cut: false`
  and `crossfade_ms: 80.0`, `findings: []`, and `rules_skipped` names `seam_hole` with
  reason "seam carries its own fade/crossfade" and `seams: [1]`. The audio dip at the seam
  (`floor_dbfs` near −69) is expected and is not a finding.
- The bed job succeeds. Its `episode` is 96 frames, 4.00 s, 48 kHz, integrated LUFS within
  0.5 of −16. Its manifest `shots` repeat both segments with `trim_frames`/`crossfade_ms`, and
  `assess_output` reports no findings.
It is a **finding** if the trim/crossfade is missing from the chain's shots, if `seam_hole`
fires on the chain's own seam (or is skipped silently, not listed), or if `pair_audio`
drops the shots.
cleanup: `delete_output(job_id=…)` for both jobs; `delete_asset("regression/m-f101-chain.mp4")`.
metrics: none.

### M-F102 — a `for_each` whose entries each compose an LTX chain of a different length runs as validated
source: tester, found while running TESTER_TASK.agent.md (ep119)
Needs LTX-2.5 via `templates/ltx2/chained-segments`, about 1.7 min. Inline workflow, `id`
`m-f102-scenes`, `seed` 119, `variables: {"scenes": []}`: step `last` = task `get_last_frame` with
`video: "asset:qa-cast/ep117-episode.mp4"`, `result` `{"content_type": "image/png", "save": false}`;
step `scene` = `for_each: "variable:scenes"`, `workflow: {"path": "templates/ltx2/chained-segments",
"arguments": {"image": "item:image", "segments": "item:segments", "prompts": "item:prompts",
"num_frames": "item:num_frames", "prompt": "A kitchen at night, two people by an open freezer.",
"width": 512, "height": 288, "seed": 119}}`, `result` `{"content_type": "video/mp4", "subfolder":
"intermediate"}`; step `episode` = task `concat_videos` with `videos: "gather:scene"`, `fps: 24`,
`match_levels: "rms"`, `match_levels_dbfs: -24`, `result` `{"content_type": "video/mp4",
"subfolder": "final"}`. Arguments: `scenes` = `[{"name": "accuse", "image": "previous_result:last",
"segments": 2, "num_frames": 33, "prompts": ["A wiry woman in a mustard sweater vest and glasses
holds up a spoon and says quickly, \"There is green on this spoon.\"", "A heavyset bald man in a
gray flannel shirt looks at the spoon and says flatly, \"Mint.\""]}, {"name": "deflect", "image":
"asset:qa-cast/hal-portrait.jpg", "segments": 1, "num_frames": 41, "prompts": ["A heavyset bald man
in a gray flannel shirt folds his arms and says flatly, \"I stand by mint.\""]}]`.
`validate_workflow` with those arguments, then `run_workflow` with the bound acknowledgement.
expected:
- validate is clean with `list_entries: {"scenes": 2}` and `steps: 4`; the run succeeds.
- Manifest: `scene@accuse` carries 2 shots (33 f, then 31 f with `trim_frames: 2`,
  `crossfade_ms: 80.0`), `scene@deflect` 1 shot of 41 f — each member got its own `segments`,
  `num_frames` and `prompts`, and the item-level `previous_result:last` resolved.
- `episode` is 512×288, 24 fps, 105 frames, 4.375 s, 48 kHz, with 3 shots and the inner
  trim/crossfade carried; the shot at frame 64 has `hard_cut: true`.
It is a **finding** if validate passes and the run fails, if a member takes another member's
(or the template default's) segment count, length or prompts, or if the join drops the inner
shots. Shot *names* are not asserted (#670).
cleanup: `delete_output(job_id=…)`.
metrics: none.

### M-F103 — a hot H3 shot that `dialogue-short`'s `match_levels` join consumes draws no shot warning
source: tester, verified in #671 (claude-opus-5-5 via anthropic)
This is the **video** counterpart of M-F021. It needs MiniMax H3 `ref2va` through
`templates/minimax/dialogue-short`, about 12 min. Until #671, a shot saved as the template's
`intermediate` and then re-levelled by the join's `match_levels` still got a
"`shot@deflect` … decodes at +1.70 dBFS … add a 'normalize_audio' step" warning. A template
caller has no step to put that `normalize_audio` ahead of. The first fix produced a false
"could not be re-measured" held prediction in its place.
`run_workflow(workflow_path="templates/minimax/dialogue-short", workspace=<suite workspace>,
arguments={...}, wait_seconds=55)`, with the arguments below. Use the bound acknowledgement.
- Top level: `character_a_voice: "asset:qa-cast/priya-voice.wav"`,
  `character_b_voice: "asset:qa-cast/hal-voice.wav"`, `seed: 120`, `audio_bleed_ms: 0`,
  `seam_fade_ms: 150`, `match_levels: "rms"`.
- `shots`: two entries, each with `num_frames: 124`, both in the order given.
- Each entry's `references` are `{reference_type: "variable:subject_reference_type",
  from_file: <portrait>}` and `{reference_type: "variable:voice_reference_type",
  from_file: <voice>}`.

The two `shots` entries:
1. `name: "accuse"`, portrait `asset:qa-cast/priya-portrait.jpg`, voice `…/priya-voice.wav`.
   `prompt`: `"subject_definitions:\n<Subject 1> is the wiry man in <Picture 1>, early 30s, short
   curly dark hair, glasses, mustard-yellow sweater vest over a white button-down
   shirt.\n\nsummary:\n[reference generation] In a cluttered 1990s office kitchen, <Subject 1>
   holds up an empty pistachio ice cream carton and speaks fast and clipped, voice <Audio 1>:
   \"Someone finished the pistachio, and the spoon is still warm.\" Medium close-up, static
   camera."`
2. `name: "deflect"`, portrait `asset:qa-cast/hal-portrait.jpg`, voice `…/hal-voice.wav`.
   `prompt`: `"subject_definitions:\n<Subject 1> is the heavyset man in <Picture 1>, mid 40s,
   shaved head, calm and heavy-lidded, open gray flannel shirt over a dark
   t-shirt.\n\nsummary:\n[reference generation] In the same cluttered 1990s office kitchen,
   <Subject 1> leans on the counter and says flatly, voice <Audio 1>: \"Spoons retain heat,
   Priya. It's science.\" Medium close-up, static camera."`

expected:
- The run succeeds and is rendered fresh, not `reused`. If the step cache served the shots,
  the post-write checks didn't run: delete that cache's run first, or say the case proved
  nothing.
- **Precondition.** `job.warnings` carries the join's own
  `episode: concat_videos: video 2 would clip at the rms target (… dBFS peak) - held to -0.5 dBFS`.
  That note is the evidence that `shot@deflect` came out hot. Without it, the case proved
  nothing; say so.
- No warning names a `shot@…` file: no "above full scale" / `audio_clipped`, and no
  "predicted to peak … could not be re-measured" / `audio_no_headroom`. Apart from that, the
  only entries are the two `draw_character_a`/`_b` "did not run" notes.

It is a **finding** if either `shot@` warning comes back, or if the advice names a step the
caller can't insert.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### M-F113 — the H3 modular pipeline's signature still lists the hold, refine and guide inputs
source: tester, spec for #770 from #691's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 (`MiniMaxH3ModularPipeline`, the class behind every
`templates/minimax/*` t2va/fl2va/ref2va step).
#691 moves the dw blocks that add `hold_audio`, `refine_strength` and `guides` to the H3 pipeline
into new modules. Stage A only adds drift tests, and stage B splits the module. Neither may change
what a consumer sees. Free: no GPU.
Steps:
1. `get_pipeline_signature(name="MiniMaxH3ModularPipeline")`.
2. `get_pipeline_signature(name="MiniMaxAI/MiniMax-H3")` and
   `get_pipeline_signature(name="MiniMaxH3Pipeline")`. Both are names that don't resolve. They
   are here so a later change to that behaviour is noticed.
expected:
- (1) `parameters` holds each of these, `required: false`, with a non-empty `description`:
  - `hold_audio`, annotated as a `MiniMaxH3AudioReference`;
  - `refine_strength`, annotated `float`, whose description says it is a sigma in (0, 1);
  - `guides`, annotated `list`, whose description says `frame` is a multiple of 17.
- (1) also still lists `latents`, `audio_latents`, `num_frames`, `image`, `last_image` and
  `references`. Before #691, each of those parameters was present.
- (2) are refused errors, not a signature: today "Not Found" and "diffusers exports no class
  named 'MiniMaxH3Pipeline'". They must not be a traceback or a server path.
It is a **finding** if any of the three dw inputs is missing from (1), or loses its description.
That means the split dropped a block from the pipeline's composition.
cleanup: none.
metrics: none.

### M-F114 — `chained-segments` with `continuity:"guide"` accepts `guide_frames` 22 and 39 only, with today's message
source: tester, spec for #770 from #691's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3, via `templates/minimax/chained-segments`.
Per #691's plan, the `guide_frames` message is rebuilt from `GUIDE_CHAIN_FRAMES` when the module
is split, and its text must not change. This case pins the text as it stood before the split
(captured on mini-ai, 2026-10-08). Free: no GPU.
Setup:
- `use_workspace("regression-model-specific")`. If it doesn't exist, `create_workspace` it
  first. `asset:qa-cast/priya-portrait.jpg` comes from the shared `common/assets`.
Steps: `validate_workflow(name="templates/minimax/chained-segments", arguments={"image":
"asset:qa-cast/priya-portrait.jpg", "seed": 42, "continuity": "guide", "guide_frames": N})`
for each N:
- (a) 22;
- (b) 39;
- (c) 40;
- (d) 0;
- (e) 23;
- (f) 38;
- (g) 56;
- (h) 5.
Then `run_workflow` the same call with `guide_frames: 40` and `acknowledged_cost=true`.
expected:
- (a) and (b) are `valid: true` with no error and no warning about `guide_frames`.
- (c)–(h) are each `valid: false` with exactly one error at
  `steps[0].pipeline.chain.guide_frames`. Its message is, verbatim:
  `guide_frames must be 22 or 39 (the whole-latent guide lengths a chain carries), got <N>`,
  where `<N>` is the value passed. For (c), the message ends `got 40`.
- `run_workflow` with 40 is refused with the same error and queues no job.
It is a **finding** if:
- 22 or 39 is refused;
- any other value validates;
- the message's wording or the order of its allowed lengths differs from the text above;
- a refused value queues a job (refused too late).
cleanup: `delete_output(job_id=…)` for any job that queued.
metrics: none.

### M-F115 — `hold_audio` and `refine_strength` refusals keep their exact messages
source: tester, spec for #771 from #691's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va, plus the SD 1.5 pipeline as the non-H3 step.
Stage B of #691 moves these rules into `h3_rules` and deletes `h3_blocks.py`. The plan requires
every refusal to say exactly what it said before the split. The texts below were captured on
mini-ai on 2026-10-08, before the split. Free: no GPU.
Setup: `use_workspace("regression-model-specific")`, created if it is missing.
Carriers, each an inline `workflow` passed to `validate_workflow`:
- **H3**: `{"id":"probe","steps":[{"name":"base","pipeline":{"configuration":{"component_type":
  "ModularPipeline"},"from_pretrained_arguments":{"model_name":"MiniMaxAI/MiniMax-H3","workflow":
  "t2va"},"arguments":{"prompt":"a fox","num_frames":124,"width":960,"height":544,
  "num_inference_steps":9,"output":["videos","audio","sampling_rate"]}},"result":{"content_type":
  "video/mp4","fps":24}}]}`, with the probe's keys added to `arguments`.
- **SD**: `{"id":"probe","steps":[{"name":"img","pipeline":{"configuration":{"component_type":
  "StableDiffusionPipeline"},"from_pretrained_arguments":{"model_name":
  "stable-diffusion-v1-5/stable-diffusion-v1-5"},"arguments":{"prompt":"a fox"}},"result":
  {"content_type":"image/png"}}]}`, with the probe's keys added to `arguments`.
- **Refine**: the example in `get_guide("workflows", section="Promoting an H3 take to 768p in
  latent space")`, which M-F082 also uses, passed with `refine_strength` replaced by the probe's
  value.
Probes:
- (a) SD carrier, plus `"hold_audio": "asset:qa-cast/hal-voice.wav"` and `"refine_strength": 0.2`;
- (b) H3 carrier, plus `"refine_strength": 0`;
- (c) H3 carrier, plus `"refine_strength": 1.5` and `"hold_audio": "asset:qa-cast/hal-voice.wav"`;
- (d) Refine carrier at 0.2;
- (e) Refine carrier at 1.0;
- (f) Refine carrier at 0.999;
- (g) Refine carrier at 0.001;
- (h) Refine carrier at -0.2.
Then `run_workflow(..., acknowledged_cost=true)` (a) as an inline workflow.
expected (messages verbatim; `<v>` is the value as passed):
- (a) `valid: false`, three errors:
  - at `steps[0].pipeline.arguments.hold_audio`: `hold_audio is a MiniMax-H3 argument, taken by
    its fl2va, ref2va, t2va workflows, and this step loads StableDiffusionPipeline`;
  - at `steps[0].pipeline.arguments.refine_strength`: the same sentence beginning
    `refine_strength is a MiniMax-H3 argument, …`;
  - at the same path: `refine_strength re-denoises the 'latents' it is passed - pass the upscaled
    latents, e.g. 'previous_result:up'`.
- (b) `valid: false`, three errors at `steps[0].pipeline.arguments.refine_strength`:
  - `refine_strength is a sigma in (0, 1) - about 0.2 refines an upscaled take - and 0 is outside
    it`;
  - the `re-denoises the 'latents'` sentence above;
  - `refine_strength re-denoises the video only, so it needs 'hold_audio' to keep a soundtrack -
    e.g. the base pass's 'previous_result:base.audio'`.
- (c) `valid: false`, two errors at `steps[0].pipeline.arguments.refine_strength`: the range
  sentence ending `and 1.5 is outside it`, and the `re-denoises the 'latents'` sentence. There is
  no `hold_audio` error, since one was passed.
- (d), (f) and (g) are `valid: true`.
- (e) and (h) are `valid: false` with the range sentence for that value, and no other error.
- `run_workflow` on (a) is refused with the same errors and queues no job.
It is a **finding** if:
- any message's wording, its JSON path, or the number of errors per probe differs from the above
  (today's set is the contract);
- a bound moves (0 or 1 accepted, or 0.001 or 0.999 refused);
- a refused probe queues a job.
cleanup: `delete_output(job_id=…)` for any job that queued.
metrics: none.

### M-F116 — `guides` refusals (more than 4 clips, frame not a multiple of 17) keep their exact messages
source: tester, spec for #771 from #691's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 t2va.
The guide rules are the third piece stage B moves, into `h3_guides`. The texts below were captured
on mini-ai on 2026-10-08, before the split. Free: no GPU.
Setup: `use_workspace("regression-model-specific")`, created if it is missing. Use M-F115's H3
carrier. `G` is `"asset:qa-guides/ep6-22f.mp4"`. That clip need not exist here: the count and
frame rules are checked before the asset. If it is absent, an accepted probe's only errors are
`Asset 'qa-guides/ep6-22f.mp4' not found …` at `guides[i].video`.
Probes, each passed as `"guides": [...]` on the carrier:
- (a) five clips: `{"video": G, "frame": f}` for f = 0, 17, 34, 51, 68;
- (b) four clips at 0, 17, 34, 51;
- (c) one clip at frame 10;
- (d) one clip at frame 1;
- (e) one clip at frame 16;
- (f) one clip at frame 18;
- (g) one clip at frame 17;
- (h) one clip at frame 0;
- (i) an empty list, `[]`.
Then `run_workflow(..., acknowledged_cost=true)` (a).
expected (messages verbatim):
- (a) `valid: false`, exactly one error, at `steps[0].pipeline.arguments.guides`:
  `guides takes at most 4 clips, got 5`.
- (b), (g) and (h) carry no count or frame error. They are `valid: true`, or invalid only by the
  asset-not-found errors above when the clip is absent.
- (c) `valid: false`, one error at `steps[0].pipeline.arguments.guides[0]`: `'frame' must be a
  multiple of 17 (a VAE chunk boundary, where a guide lines up with the generated frames), got 10
  - use 0 or 17`.
- (d), (e) and (f) give the same sentence with their own value after `got`. Each ends with a
  suggestion naming the multiples of 17 on either side. (f), captured before the split, ends
  verbatim `got 18 - use 17 or 34`. (d) and (e) both end `- use 0 or 17`.
- (i) `valid: true`, carrying only the carrier's no-`seed` step-cache warning, which is not a
  guide error. This was captured before the split.
- `run_workflow` on (a) is refused with the same error and queues no job.
At #771's verification, also re-run M-F113 and M-F114. Both must pass unchanged.
It is a **finding** if a count or frame message changes wording or path, if 4 clips or a
multiple-of-17 frame is refused, or if a refused probe queues a job.
cleanup: `delete_output(job_id=…)` for any job that queued.
metrics: none.

### M-F117 — the H3 guide-memory record cites real runs, and 28.71 B per guide voxel separates every OOM from every completed run
source: tester, spec for #778 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA, the stage-A measurement runs on lem's RTX 3090.
Plan v2's stage A acceptance, replacing M-F104's "fit within 0.5 GB". The record is
`docs/proposals/h3-guide-vram.md`: a table with job ids, a least-squares fit with its residuals,
the check of the chosen term, the audio delta and the exit verdict. Don approved checking the
stage by that record.
Free: discovery calls only (`list_jobs`, `get_job`, `get_job_workflow`, `get_workflow`,
`get_guide`). Nothing is run.
Setup: find the record. On 2026-10-08 `list_guides()` serves no `docs/proposals/` file, so the
record a consumer can read is #778's hand-off comment, which must quote the table, the fit and the
verdict verbatim. If `list_guides()` lists the record by then, read it there instead. If it is in
neither place, the stage can't be checked: bounce it with that reason.
Terms: a row's **guide voxels** are Σ over its guides of (guide frames × width × height). The
**guide term** is 28.71 B × guide voxels. Convert bytes in the unit the record's table uses: GiB
is ÷ 2³⁰, GB is ÷ 10⁹. Every point is at `num_frames` 124. Two reference values: 4 × 124 at
1344×768 is 511,967,232 voxels, a 13.69 GiB (14.70 GB) guide term, and 1 × 22 at 1344×768 is
0.61 GiB (0.65 GB).
Steps:
1. For every table row, find its job id in `list_jobs`, then run `get_job` and
   `get_job_workflow` on it.
2. Check that the rows cover the plan v2 set. All are H3 t2va at `num_frames` 124, at 960×544 and
   at 1344×768:
   - 0, 1, 2 and 4 guides of 22 frames;
   - 1 and 4 guides of 124 frames;
   - 1 guide of 39 frames, with `"audio": true` and without.
   The plan names 14 runs. A missing point is acceptable only if the record says why. The near-top
   frame counts v1 asked for are listed as superseded, with the reason (they filled the card with
   no guides).
3. For each row, recompute the projection as `plain projection + guide term`. The plain
   projection is the H3 t2va template's own formula at that canvas and 124 frames, with no guides.
   Read `base_gb` and `bytes_per_voxel` from `get_workflow("templates/minimax/video-with-audio")`
   (or `-768p`), and the formula from the guide's `vram_estimate` formula text.
4. Recompute the exit test: the guide term alone at 4 × 124 on 1344×768.
expected:
- Every cited job id exists in `list_jobs`. Its resolved workflow is H3 t2va with the stated
  canvas, `num_frames` 124, guide count, guide lengths and `audio` flags.
- Each row's status matches the table:
  - a completed row is `completed`, and its output has the stated frame count;
  - an OOM row is `failed`, with an error naming CUDA out-of-memory.
- Step 3 reproduces the record's projection column to 0.05 (rounding).
- The separation holds on every row:
  - each OOM row projects **above 24 GiB**;
  - each completed row, censored ones included, projects **below 24 GiB**;
  - each uncensored row projects **at or above** its measured peak.
- The record states:
  - the separating range (27.7–35.9 B in the plan), with 28.71 inside it;
  - the two deviations: 124 frames instead of near-top lengths, and the peak read from
    `nvidia-smi memory.used` because the engine records no `max_memory_reserved`;
  - the censored rows as ≥ 23.55, not as measured peaks;
  - the 39-frame audio/no-audio delta, and that audio needs no term of its own;
  - the two-term least-squares fit with its residuals, showing why it was not chosen.
- The exit verdict is "not met". Step 4 gives about 13.7 GiB, far above the 0.5 GB exit line, so
  stage B follows.
It is a **finding** if:
- a cited job doesn't exist, or its workflow or status doesn't match its row;
- a planned point is missing with no stated reason;
- any row breaks the separation at 28.71 B;
- 28.71 lies outside the range the record states;
- the record's projection column disagrees with step 3;
- the exit arithmetic disagrees with the verdict.
cleanup: none.
metrics: none.

### M-F118 — `vram_estimate` takes one guide key, `bytes_per_guide_voxel`: optional, ≥ 0, absent means unchanged, and the dropped keys are refused
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA, via an inline copy of `templates/minimax/video-with-audio-768p`.
The schema case for plan v2's single key (it replaces M-F105, which named the dropped
`gb_per_guide`). Shaped like M-F048.
Free: `get_schema` and validate calls only.
Setup: `get_workflow("templates/minimax/video-with-audio-768p")` as **V**. Set its generating
step's `arguments.guides` to four 124-frame guides: `asset:qa-cast/ep6-cold-open.mp4` at frames 0,
51, 102 and 153. Set top-level arguments `{"width": 1344, "height": 768, "num_frames": 277}`. Then
set V's top-level `vram_estimate` per variant, starting from the template's own estimate with
`bytes_per_guide_voxel` removed:
- a. key absent;
- b. `bytes_per_guide_voxel: 0`;
- c. `bytes_per_guide_voxel: 28.71`;
- d. `bytes_per_guide_voxel: -1`;
- e. `bytes_per_guide_voxel: "28.71"`, a string;
- f. `bytes_per_guide_voxel: null`;
- g. a dropped key from plan v1, `gb_per_guide: 0.2`, alongside c's key;
- h. another dropped key, `gb_per_guide_audio: 0.1`, alongside c's key.
Also build **V0**: V with no `guides` key, with variant a's estimate.
Steps: `get_schema(section=…)` for the section holding `vram_estimate`. Then one
`validate_workflow(workflow=…, workspace="regression-model-specific")` on V0 and on each variant.
expected:
- The schema lists `bytes_per_guide_voxel` as an optional number with minimum 0. It lists no
  `gb_per_guide` or `gb_per_guide_audio`, and `vram_estimate` still has
  `additionalProperties: false`.
- a and b give the same verdict as V0. Any VRAM message gives the same GB as V0's: four guides add
  nothing when the key is absent or 0.
- c is `valid: false`, with a VRAM error naming 4 guides. Its projection exceeds a's by the guide
  term, 28.71 × 4 × 124 × 1344 × 768 B, which is 13.69 GiB (14.70 GB) in the message's unit, to
  0.1. If a and V0 quote no GB because they are under the card, check c's GB against the
  template's formula plus that term instead.
- d is `valid: false`, with an error naming the key and its minimum. e and f are type errors
  naming the key.
- g and h are refused as unknown keys. The dropped keys must not be silently accepted.
It is a **finding** if a negative, a string or null is accepted, if absent and 0 differ, or if a
dropped key validates.
cleanup: none.
metrics: none.

### M-F119 — a copied H3 t2va with no estimate warns, naming its guides, once 4 × 124 guides push it past the card; 1 × 22 stays clean
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA, via **NT768**: `templates/minimax/video-with-audio-768p` copied
inline with its top-level `vram_estimate` and `cost` deleted, as in M-F049/M-F051. It inherits the
template's estimate, including `bytes_per_guide_voxel`.
Plan v2's first acceptance line. A custom guided t2va at the largest canvas, at a length that is
clean with no guides, gets a `vram_projection_inherited` **warning**, never an error.
Free: validate calls only. Every step uses
`arguments={"width": 1344, "height": 768, "num_frames": 277}`. M-F026 pins 277 as the last clean
17n+5 below the 294 breakpoint. Set the generating step's `arguments.guides` per step:
1. no `guides` key;
2. `[{"video": "asset:qa-guides/ep6-22f.mp4", "frame": 0}]`;
3. four 124-frame guides, `asset:qa-cast/ep6-cold-open.mp4` at frames 0, 51, 102 and 153;
4. as 3, with `"audio": true` on every guide;
5. `[{"video": null, "frame": 0}]` plus step 3's four guides minus the last. This is the
   null-video edge the plan drops "as references are".
expected:
- Step 1 is `valid: true` with no inherited-ceiling warning. If it warns, 277 is no longer clean:
  use the largest clean 17n+5 throughout, and note it.
- Step 2 is `valid: true` with no inherited-ceiling warning. The guide term adds 0.61 GiB
  (0.65 GB). If the template's plain projection at 277 sits within that of 24, the arithmetic
  rules: a warning is then correct, and is not a finding. Record it, and file a `suite` request to
  move the step to a shorter length.
- Step 3 is **`valid: true`** with exactly one `vram_projection_inherited` warning, which:
  - names `templates/minimax/video-with-audio-768p`;
  - gives a projected GB over 24;
  - names the guides with their frame counts in the formula, e.g. "4 guides (124+124+124+124
    frames)".
  Its GB is the template's plain projection at 1344×768×277 plus 13.69 GiB (14.70 GB), in the
  message's unit, to 0.1.
- Step 4 gives the same warning and GB as step 3. Plan v2 has no guide-audio term.
- Step 5 either:
  - is refused by the guides validation, with the existing message for a missing `video`; or
  - is accepted, and charges 3 guides (it names "3 guides", not 4), with the null entry costing
    nothing.
It is a **finding** if:
- step 3 is an error, since an inherited ceiling is never one;
- step 3 is silent;
- the warning doesn't count the guides or their frames;
- `"audio": true` changes the GB;
- a null-video guide is charged;
- step 1 or step 2 warns while the arithmetic puts it under the card.
cleanup: none.
metrics: none.

### M-F120 — the guide term charges each clip's snapped, probed length and scales with the canvas; a declared template refuses
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA, via `templates/minimax/video-with-audio` (960×544) and
`templates/minimax/video-with-audio-768p` (1344×768), both with declared estimates. **NT** and
**NT768** are their inline copies with `vram_estimate` and `cost` deleted.
Plan v2 charges `bytes_per_guide_voxel` × Σ over guides of (probed, snapped frames × width ×
height). The probe runs at validate, at run and at admission, and all three answer the same.
Free: validate calls only. Read both templates' `vram_estimate` with `get_workflow` first. Each
step keeps the stated workflow's estimate (or lack of one) and sets the generating step's
`guides`:
1. NT768 at 1344×768×277 with three cold-open 124-frame guides (frames 0, 51 and 102) plus one more
   at frame 153:
   - a. `asset:qa-guides/ep6-22f.mp4`;
   - b. `asset:qa-guides/ep6-30f.mp4`, which snaps to 22 with today's snap warning.
2. NT at 960×544 with step 3 of M-F119's four 124-frame guides, at the largest clean 17n+5
   `num_frames` that has no guides (try 345 first, the template's maximum).
3. `video-with-audio-768p` itself (declared) at 1344×768×277 with M-F119 step 3's four guides.
4. `video-with-audio-768p` at 1344×768×277 with no guides.
expected:
- 1a and 1b each give one inherited warning with the **same** GB, the plain projection plus 28.71
  × (3 × 124 + 22) × 1344 × 768 B, which is 10.87 GiB (11.68 GB) more. The 30-frame clip is
  charged as 22, not 30, and the formula shows "124+124+124+22".
- Step 2's guide term is 28.71 × 4 × 124 × 960 × 544 B, which is 6.93 GiB (7.44 GB). That is
  (960 × 544)/(1344 × 768) = 0.506 of M-F119 step 3's. If step 2 is under the card, so that no
  GB is quoted, record "under the card at 960×544". That agrees with the plan's statement that
  the gap bites at 768p. The finding is only a warning the arithmetic contradicts.
- Step 3 is **`valid: false`**, with an error, not a warning, because the estimate is declared.
  The error names 4 guides and their frames, and its GB equals M-F119 step 3's to 0.1.
- Step 4 is `valid: true` with no VRAM error. The plain declared projection is unchanged by the
  feature.
It is a **finding** if:
- a raw (unsnapped) length is charged;
- the guide term ignores the canvas;
- a declared template gives only a warning;
- a quoted GB disagrees with the template's own terms;
- the formula shows guide frames that don't match the clips.
cleanup: none.
metrics: none.

### M-F121 — a guide nothing can probe at validate is charged at `num_frames`, and the message says "worst case"
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA, via an inline two-step workflow.
Plan v2: "A clip that cannot be probed (a `previous_result:` value, an unreadable header) is charged
at the step's own `num_frames`." Don chose the probe (Q1), so only an unprobeable clip gets the
worst case.
Free: validate calls only.
Setup: build **PR**, a two-step workflow:
- `clip`: `loop_frames(video="asset:qa-cast/ep6-cold-open.mp4", num_frames=22)`;
- `gen`: `templates/minimax/video-with-audio-768p`'s generating step, with `guides:
  [{"video": "previous_result:clip", "frame": 0}]`.
Keep the template's `vram_estimate` and `cost`. Build **PR-NT**, the same with both deleted.
Build **PR3**, PR with three more cold-open 124-frame guides at frames 51, 102 and 153.
Steps: `validate_workflow` at `arguments={"width": 1344, "height": 768, "num_frames": 277}` on PR,
PR-NT and PR3, then on PR and PR3 at `num_frames` 124.
expected:
- At 277, the `previous_result:` guide is charged as 277 frames, not 22, since the clip doesn't
  exist at validate. Its term is 28.71 × 277 × 1344 × 768 B, which is 7.64 GiB (8.21 GB):
  - if PR's total goes over 24, PR is `valid: false`. The error says the guide was charged at the
    worst case (`num_frames`), and its GB is the plain projection plus that term;
  - PR-NT gives the same GB as a `vram_projection_inherited` warning, never an error;
  - PR3 is `valid: false`, naming 4 guides as 277+124+124+124 frames, with "worst case" still
    stated.
  If PR is under the card at 277 (no message), PR3 still must carry the worst-case wording.
- At 124, the guide is charged at 124 frames. PR3 at 124 is 4 × 124, the same as M-F120 step 3,
  but at 124 frames: it refuses or passes exactly as the arithmetic says, and any message says
  worst case.
It is a **finding** if:
- the unprobeable guide is charged at 0, or dropped;
- it is charged at 22 (the validator can't know that without the clip);
- a message carrying it doesn't say worst case;
- PR-NT errors.
cleanup: none.
metrics: none.

### M-F122 — `chained-segments` gains a cost and an estimate, and its chain guide is counted: 3 own guides plus the carry are refused before a job exists
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 FL2VA, via `templates/minimax/chained-segments`. On 2026-10-08 its
variables are `segments` 3, `continuity` `"last_frame"`, `guide_frames` 22, 960×544, `num_frames`
124 (constraint 124–345, 17n+5), with no `vram_estimate` and a null `cost`. Plan v2 (Q3) gives it
both: the H3 t2va numbers plus `bytes_per_guide_voxel`. A `continuity: "guide"` chain counts its
carried clip as one more guide, at `guide_frames` frames.
Free: validate calls and refused `run_workflow` calls only. If a run is accepted, `cancel_job`
it at once and record the finding.
Setup: save **CS3**, the template's document with `guides` on its generating step: three
`asset:qa-cast/ep6-cold-open.mp4` guides at frames 51, 153 and 221 (221 + 124 = 345). Save
**CS1**, the same with only the frame-51 guide. Both use
`arguments={"continuity": "guide", "guide_frames": 39, "num_frames": 345}`, the template's
largest allowed frames.
Guide terms at 960×544 (×1.976 at 1344×768):
- CS3 with the carry, 3 × 124 + 39: 5.74 GiB (6.16 GB);
- CS3 without the carry: 5.19 GiB (5.58 GB);
- CS1 with the carry, 124 + 39: 2.28 GiB (2.44 GB).
Steps:
1. `get_workflow("templates/minimax/chained-segments")` and `list_workflows(shape="shot")`, or
   whichever shape lists it.
2. `list_jobs`, noting the newest id.
3. `validate_workflow` on CS3, then on CS1.
4. Without validating first, `run_workflow` on CS3 with the same arguments,
   `acknowledged_cost=true`, `wait_seconds=0`. Then `list_jobs`.
5. `validate_workflow` on CS3 with `"continuity": "last_frame"` (no chain guide).
6. Only if CS3 validated in step 3: repeat steps 3–5 at `"width": 1344, "height": 768`.
expected:
- (1) The template has a top-level `vram_estimate` carrying `bytes_per_guide_voxel: 28.71`, and
  `list_workflows` shows a non-null `cost` for it. It still validates at its defaults (M-F123).
- (3) CS3 is **`valid: false`**. The error names **4 guides**, 3 plus the chain's 39-frame carry,
  with their frames, e.g. "4 guides (124+124+124+39 frames)". Its GB is over 24 and equals the
  template's formula plus the guide term above, to 0.1. CS1 is `valid: true` with no VRAM error.
- (4) `run_workflow` refuses CS3 in M-F046's shape: `status: failed`, `run_id: null`, the same
  message and GB as validate. `list_jobs` shows no new job. This is the run-time probe agreeing
  with validate.
- (5) The `last_frame` chain charges 3 guides, not 4. Its message, if any, says "3 guides".
- (6) Reached only if the plan's refusal did not happen at 960×544. At 1344×768, steps 3–4 must
  refuse with the same checks.
It is a **finding** if:
- the template still lacks an estimate or a cost;
- the chain guide isn't counted under `"guide"`, or is counted under `"last_frame"`;
- validate and run disagree;
- a job is created;
- CS3 validates at both canvases, since the plan promised a refusal;
- CS1 is refused.
cleanup: `delete_workflow` on CS3 and CS1 if saved by name, and `cancel_job` and
`delete_output(job_id=…)` on any accepted run.
metrics: none.

### M-F123 — every H3 template still validates at its defaults; t2va/fl2va estimates carry `bytes_per_guide_voxel` equal to their `bytes_per_voxel`, ref2va ones don't
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: every `templates/minimax/*` template.
The plan's catalog promise, sharing M-F047's sweep. Replaces M-F110, which named the dropped
`gb_per_guide`.
Free: `list_workflows`, `get_workflow` and validate calls only.
Steps: for each `templates/minimax/*` name `list_workflows` lists under any shape: `get_workflow`,
then `validate_workflow(name, workspace="regression-model-specific")` with no arguments. Note each
H3 step's `from_pretrained_arguments.workflow` (`t2va`, `fl2va` or `ref2va`).
expected:
- Every template is `valid: true` at its defaults, with no VRAM error. That includes
  `chained-segments`.
- Every template with a `vram_estimate` whose H3 step is `t2va` or `fl2va` has
  `bytes_per_guide_voxel`, equal to that estimate's `bytes_per_voxel` (28.71 today). That includes
  `chained-segments`.
- No estimate in the catalog has `gb_per_guide` or `gb_per_guide_audio`.
- No template whose only H3 step is `ref2va` carries `bytes_per_guide_voxel`, since guides are
  refused there.
- Every template uses no guides at its defaults, so each projects exactly what it did before. Each
  default-argument projection that M-F043–M-F054 pin is unchanged.
It is a **finding** if a template no longer validates at its defaults, if a t2va/fl2va estimate
lacks the key or differs from its `bytes_per_voxel`, if a ref2va estimate has it, or if a dropped
key appears.
cleanup: none.
metrics: none.

### M-F124 — the guide and the minimax-h3 skill state the guide term and that the 4-guide limit is checked against the card
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: docs only: the served `WORKFLOW_GUIDE.md` and the dw plugin's `minimax-h3` skill.
The ARCHITECTURE row and the proposal record aren't served, so they are not checked here.
Replaces M-F111.
Free.
Steps:
1. `list_guides()`. Then `get_guide("workflows", section=…)` for the section holding the
   `vram_estimate` formula, and for the section holding "H3: holding a clip with `guides`".
2. Load the `minimax-h3` skill.
expected:
- (1) The formula text gives the guide term as `bytes_per_guide_voxel` × Σ(snapped guide frames) ×
  width × height. It also says:
  - an absent key adds nothing;
  - each guide's length is probed, and a `previous_result:` (or unprobeable) guide is charged at
    `num_frames`;
  - a `continuity: "guide"` chain counts as one more guide;
  - a declared estimate refuses, while an inherited one warns.
  It names no `gb_per_guide`. The guides section's line on the limit of 4 no longer calls it "a
  VRAM limit" that nothing checks: it says each guide is checked against the card's projection.
- (2) The skill's guides line says the ceiling drops with each guide and its length, as it says
  for references.
- Every key and example in that text validates when pasted into `validate_workflow`.
It is a **finding** if either text still describes the guide limit as purely a count, or names a
key the schema refuses.
cleanup: none.
metrics: none.

### M-F125 — the largest guided combination the catalog allows on 24 GB is flagged before any GPU time
source: tester, spec for #779 from #694's plan v2 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 T2VA, via `templates/minimax/video-with-audio-768p`.
#694's own acceptance: validate passes, then the card OOMs. The largest combination is:
- 1344×768;
- the template's largest `num_frames` that validates with no guides;
- 4 guides at the longest length the guides section allows, with `"audio": true`.
Replaces M-F112.
Free for the required part. The optional confirmation is **paid**: one H3 run, about 10 min.
Setup: read the longest guide length from the guides section (`get_guide`). If it exceeds 124,
make that clip CPU-only as in the Fixtures section's `m-guide-clips` recipe, with
`loop_frames(video="asset:qa-cast/ep6-cold-open.mp4", num_frames=<that length>)`, and use it in
place of the cold open. Delete it after.
Steps:
1. Find the largest 17n+5 `num_frames` at which the template is `valid: true` at 1344×768 with
   no guides (277 per M-F026).
2. Validate the template copy (estimate kept) at that length with the 4 longest guides, `"audio":
   true`, at frames 0, 51, 102 and 153 (or the earliest multiples of 17 that fit).
3. Validate the same with the estimate and cost deleted.
4. Optional, only when a curator or Don asks for OOM evidence: `run_workflow` step 3's workflow
   with `acknowledged_cost=true`.
expected:
- (2) `valid: false`, with a VRAM error naming the 4 guides and a GB over 24. No job is queued.
- (3) `valid: true`, with a `vram_projection_inherited` warning giving the same GB.
- (4) If run, it fails with a CUDA out-of-memory error. That confirms the projection is on the
  right side of the card. A clean finish means the 28.71 B term over-charges guides at this point.
  File that with the job id; it is the over-refusal risk the plan names.
It is a **finding** if (2) validates, or (3) is silent.
cleanup: `delete_output(job_id=…)` on any optional run and on the clip job, plus `delete_asset`
for any clip made in setup.
metrics: none.

### M-F126 — `music-video` with a supplied `song` pairs the pieces each shot sang, not the song from 0
source: tester, verified in #788 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax-H3 ref2va shots, via `templates/minimax/music-video` with `song` set to an
asset (no Music 3 generation). Before #788 the cut was paired with the song from frame 0, whatever
`start_frame` each shot sang at, so shots that sang 5.17–15.5 s carried 0–10.33 s of song. That was
`succeeded` with `warnings: []`. The soundtrack comes from slicing the asset, so it doesn't depend on
the shots' seed.
**Paid**: one run at reduced size, about 4–5 min on a 3090, plus a CPU-only reference job.
Steps:
1. `run_workflow("templates/minimax/music-video")` in a `qa-` or the suite's workspace with
   `song: "asset:qa-cast/ep15-song.mp3"`,
   `singer_reference: {"reference_type": "variable:image_reference_type", "from_file": "asset:qa-cast/hal-portrait.jpg"}`,
   `seed: 152`, `width: 512`, `height: 288` (multiples of 32; see #789), `num_inference_steps: 4`.
   Use two `shots`, each `num_frames: 124`, `lead_frames: 0`, `cut_frames: 124`: the first at
   `start_frame: 124`, the second at `start_frame: 248`.
2. Run an inline reference workflow with `slice_audio(audio="asset:qa-cast/ep15-song.mp3",
   sample_rate=44100, start_frame=124, lead_frames=0, num_frames=248, fps=24)` →
   `normalize_audio(peak_dbfs=-3, sample_rate=44100)`. Add the same pair with `start_frame: 0`.
   Save both as `audio/wav`.
3. `get_gallery_metadata(envelope=true)` on the run's final output and on both references.
expected:
- (1) `succeeded`, with no `pair_audio: 'fit' trimmed …` warning. `get_job_workflow` shows the song
  sliced per shot at `item:start_frame` for `item:cut_frames`, joined, then normalized and paired.
- (3) The final's per-second RMS tracks the **start_frame 124** reference within about 0.3 dB in
  every window. In #788's verify the gap was ≤ 0.13 dB, and integrated LUFS was -17.93 vs -17.86.
  Against the **start_frame 0** reference it differs by several dB in most windows (up to 5.6 dB).
It is a **finding** if the final tracks the frame-0 reference instead, or if a trim warning returns.
cleanup: `delete_output(job_id=…)` on both jobs.
metrics: none.

### M-F127 — a MiniMax-H3 width/height that isn't a multiple of 32 is refused at validate, not after the model load
Before #789, `templates/minimax/music-video` with `height: 272` validated clean. The run then loaded
MiniMax-H3 for about 100 s and failed with "`height` and `width` must be multiples of 32". The fix
declared the rule as a variable constraint (modulus 32, no snap) on every `templates/minimax/*`
template that takes `width`/`height`. M-F056 is the LTX-2.5 counterpart.
**Free**: validate and get_workflow only.
expected:
- `get_workflow("templates/minimax/music-video", variables_only=true)` → `constraints.width` and
  `constraints.height` each have `modulus: 32`, `remainder: 0`.
- `validate_workflow(name="templates/minimax/music-video", arguments={"width": 480, "height": 272,
  "num_inference_steps": 4})` → `valid: false`, with exactly one error, at `arguments.height`, naming
  the 32 rule.
- The same call with `height: 288` → `valid: true`, no errors.
- `width: 500, height: 290` → two errors, at `arguments.width` and `arguments.height`. Neither value
  is snapped.
- `validate_workflow(name="templates/minimax/reference-to-video", arguments={"width": 960, "height": 540})`
  → `valid: false`, with the error at `arguments.height`.
It is a **finding** if an off-grid size validates clean, or if an on-grid size is refused.
cleanup: none (nothing is queued or written).
source: tester, verified in #789, model `claude-opus-5-5` via provider `anthropic`, on 2026-10-08 against
mini-ai (mps) `develop @ f7b15455`.
metrics: none.

## Performance
