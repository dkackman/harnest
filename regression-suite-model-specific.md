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
`lora_alpha: 128`, `num_inference_steps: 9`. Every one of those has to reach a different part of
the stack — the canvas to the pipeline, the shift to the scheduler, the alpha to the peft layers
after load — and none of them fails loudly if it doesn't. A 768p LoRA run on the 544p sigma
schedule at the file's own `alpha: 8` (a sixteenth of what upstream passes) produces a clip that
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
- **The bare call is refused, not silently accepted.**
  `validate_workflow(name="templates/ltx2/reference-sheet")` with no `arguments` → `valid: false`,
  one error at `variables.reference_sheet` naming the missing default `asset:reference_sheet.png`
  (#166). A bare call answering `valid: true` here is that bug back.
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
pending: #499
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
pending: #499
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
pending: #499
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

### M-F042 — `templates/minimax/upscale-preview` is a catalog shot with a cost, renders 1344×768, and leaves the other minimax entries unchanged
pending: #500
source: tester, spec for #500 from #471's plan v1 (claude-opus-5-5 via anthropic)
Model/pipeline: MiniMax H3 + `upscale_h3_latents` (template `templates/minimax/upscale-preview`).
Stage 2 of #471 adds the template and one line in the `minimax-h3` skill, and changes nothing
else. The baseline for the existing minimax entries was captured on 2026-09-26, before the
stage. Two examples from it:
- `templates/minimax/video-with-audio` has cost 6.6;
- `templates/minimax/video-with-audio-768p` has cost 9.87, with `variable_constraints` num_frames
  "17*n+5, 124-345, rounds up".

The case compares every minimax entry except the new one against the same entry on
`origin/develop` *before* #500 merged. If the regression run has no stored copy, compare
against the entry's own `get_workflow` and the skill's stated defaults.
Steps:
1. `list_workflows(shape="shot")`.
2. `get_workflow("templates/minimax/upscale-preview")`.
3. `validate_workflow(name="templates/minimax/upscale-preview")` with no arguments.
4. `run_workflow(name="templates/minimax/upscale-preview", acknowledged_cost=true,
   wait_seconds=55)`, in workspace `regression-model-specific`. Then `wait_for_job`.
5. Read the `minimax-h3` skill (plugin `dw`).
expected:
- In step 1, `templates/minimax/upscale-preview` is listed with a numeric cost. Its
  `variable_constraints` give num_frames as 17n+5.
- In step 1, every other `templates/minimax/*` entry is unchanged: name, cost, shape, traits,
  `variable_constraints` and description.
- The workflow has `final`/`intermediate` subfolders, and its latents are not saved.
- Step 3 is `valid: true`, with a `plan.estimate` whose `basis` is `catalog`.
- Step 4 succeeds with one mp4 under `final/`. It is 1344×768 and carries audio.
- In step 5, the skill's list of tested combinations has one new line naming
  `upscale-preview`. The skill's defaults (resolution, frames, steps, guidance) read as before.
It is a **finding** if:
- the template is missing from `shape="shot"`, or has no cost;
- its estimate `basis` isn't `catalog`;
- the run doesn't produce 1344×768 under `final/`;
- any other minimax entry's catalog line changed;
- the skill line is missing, or a default moved.
cleanup: `delete_output(job_id=...)`.
metrics: `latency_s` from `get_job`, recorded in `regression-perf/M-F042.jsonl` with condition
`template-defaults`. The first run seeds it.

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
pending: #502
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
4. `arguments={"width": 1344, "height": 768, "num_frames": 260, "voice": null}` (1 ref, ~24.2).
expected:
- Step 1 is **`valid: true`** with exactly one inherited-ceiling warning. It names:
  - `templates/minimax/reference-to-video`;
  - the projected GB (~24.8), the 24 GB it is over, and the reference count;
  - that the copy's config may differ from the template's.

  Any other warning, such as no seed, stays as it is today.
- Steps 2 and 3 carry no inherited-ceiling warning.
- Step 4 carries the warning at ~24.2 GB.
It is a **finding** if:
- step 1 is refused, since an inherited ceiling must never be an error;
- step 1 has no warning, or its warning doesn't name the source template;
- an under-ceiling point warns;
- the warning ignores references (step 1 silent while step 4 warns).
cleanup: none.
metrics: none.

### M-F050 — the inherited-ceiling warning on a `for_each` Ref2VA workflow names the heavy member
pending: #502
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
pending: #502
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
pending: #502
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
pending: #502
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
pending: #502
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

## Performance
