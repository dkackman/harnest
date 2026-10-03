# Regression suite — dw MCP server — complete level

Broader, slower general-purpose checks: edge cases, less common parameter
combinations, anything worth checking but not fast/central enough to run
every smoke pass. Still general-purpose — not tied to any one
model/pipeline (see [`regression-suite-smoke.md`](regression-suite-smoke.md)
for the exact line between the two, and
[`regression-suite-model-specific.md`](regression-suite-model-specific.md)
for what's niche instead, and
[`regression-suite-security.md`](regression-suite-security.md) for
boundary-escape probes). Running this level also runs
`regression-suite-smoke.md` first (`./run-regression.sh complete`); this
file holds only the cases on top of that.

Workspace: `regression-complete` — kept separate from `regression-smoke` so
a slower/heavier `complete` run never skews smoke-level timings or clutters
its fixtures. Case IDs in this file use the `C-` prefix (`C-F001`,
`C-P001`, ...) so they never collide with the `S-`/`M-` IDs in the sibling
suites — the regression agent's duplicate-issue search is keyed on the full
prefixed ID. Full run mechanics (fixtures vs. outputs, cleanup, the final
sweep) live in `agents/regression/`, not here.

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
file with the reading you just took, and do the same for a new `C-P` case's
timing), the next unused `C-Fnnn`/`C-Pnnn` ID, and a `source:` line
naming who added it and why (e.g. `source: implementer, fix for #42` or
`source: tester, found while running TESTER_TASK.agent.md`). No separate approval
step — the regression agent already grows these files unsupervised when it
notices gaps; a case either of you adds is the same kind of edit.

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

Durable contents of `regression-complete` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- `asset:qa-cast/ep3-shot1-incident.mp4` and `asset:qa-cast/ep3-shot2-reply.mp4`
  — two independently generated 24 fps shots (124 frames / 5.175 s / 960x544,
  32 kHz stereo) whose soundtracks sit ~11 dB apart (`mean_dbfs` -20.0 and
  -31.1). Used by C-F001, C-F002 and C-F009. They live in the **shared**
  `common/assets`, not in `regression-complete`, so every workspace can
  reach them by that same `asset:` reference — do not delete them in a
  cleanup sweep, and do not expect them under `regression-complete`'s own
  asset dir. The level spread is the point: regenerating them would not
  reproduce it on purpose.

- `asset:qa-cast/priya-voice.wav` — a **mono** (1-channel) voice track. Used by
  C-F029 and C-F035 (which asserts its 7.453 s mono shape). Also in
  the shared `common/assets`, so do not sweep it and do not expect it under
  `regression-complete`. If it ever has to be replaced, the only property that
  matters is that it is 1-channel — `get_gallery_metadata` on a paired output
  reports `channels`, which is the cheapest way to confirm a candidate.

- `asset:uploads/qa-cast/room-bed.wav` — a short room-tone recording, 4.96 s,
  16 kHz, mono. Used by C-F016, where the only properties that matter are that
  it is a few seconds long and that its length is known (`get_gallery_metadata`
  on the reference reports it — see S-F019), so a slice can be asked for well
  past its end. Also in the shared `common/assets`: do not sweep it, and do not
  expect it under `regression-complete`. A replacement needs no particular
  content; re-read its `duration_seconds` and re-derive the frame counts below
  from it.

- `asset:qa-cast/ep15-song.mp3` and `asset:qa-cast/ep6-cold-open.mp4` — a full-length
  song and a short 24 fps shot (124 frames), used together by C-F024 as audio source
  and mux carrier. Also in the shared `common/assets`: do not sweep them, do not
  expect them under `regression-complete`. Neither is load-bearing on content — C-F024
  asserts an agreement, not a level — so any few-second-sliceable track and any short
  video substitute. Note only that the song's mux overshoot on the sliced window is
  ~0.44 dB, which is why -0.55 dBFS does **not** clip on it; that is the case's true
  negative, not a defect.

- `asset:qa-cast/ep6-shot1-priya.mp4` — a short 24 fps shot, 124 frames / 5.175 s,
  960x544, with its own 32000 Hz stereo audio. Used by C-F031 as the single shot
  under a 44.1 kHz score, where the point is only that its audio rate differs from
  the score's. Also in the shared `common/assets`: do not sweep it, do not expect it
  under `regression-complete`. Not load-bearing on content; any short shot whose
  sample rate is *not* 44100 substitutes, re-reading its frame count and rate from
  `get_gallery_metadata` and re-deriving C-F031's `total_frames` from it.

- `asset:qa-cast/ep21-shot1-receipt.mp4` and `asset:qa-cast/ep21-shot2-verdict.mp4`
  — two 24 fps dialogue shots (124 frames / 5.167 s / 960x544, 32 kHz stereo)
  from episode 21, whose outgoing shot ends on a **voiced** speech tail
  (`bleed_join` measures it at flatness 0.22 / harmonicity 0.33). Used by
  C-F037, where that tail is the point: a shot ending in silence or room tone
  would not fire the warning. Also in the shared `common/assets`: do not sweep
  them, do not expect them under `regression-complete`. A replacement pair
  needs shot 1 to end in voiced speech — confirm a candidate by running the
  bleed arm of C-F037 alone before swapping it in.

- `asset:qa-cast/ep25-episode.mp4` — a 24 fps cut whose length is an **exact
  whole number of seconds**: 360 frames / 15.0 s / 960x544, 32 kHz stereo,
  with audio all the way to its last frame (its 15th second is ~-26 dBFS
  rms). Used by C-F087 (merged from C-F044), where the integer duration is the point: a lossy
  decode runs a few samples past 15.0 s and the envelope must not report
  those as a 16th bin. Also in the shared `common/assets`: do not sweep it,
  do not expect it under `regression-complete`. A replacement needs
  `duration_seconds` to be a whole number and audible audio in its last
  second — confirm both with `get_gallery_metadata` and
  `get_output_frames(at=[<duration - 0.1>], hear=1)` before swapping it in.

- `asset:qa-cast/long-film-4089.mp4` — a **long** 24 fps film, 4089 frames /
  170.4 s / 960x544, 33 MB. It is the actual clip from #367 that got SIGKILLed.
  Used by C-F050, where the length is the whole point: decoding all of it once
  per frame is what used to kill the worker. Also in the shared
  `common/assets`, so do not sweep it and do not expect it under
  `regression-complete`. Any replacement needs thousands of frames. Re-read its
  `frame_count` with `get_gallery_metadata` and re-derive C-F050's indexes.

The assets below came with C-F051–C-F090, which moved here from smoke (curation
2026-09-22, harnest#2). All are in the shared `common/assets`: do not sweep them, do
not expect them under `regression-complete`. Where a line also names a smoke case,
smoke's Fixtures lists the asset too.

- `asset:qa-cast/ep11-bed.wav` — a 472-frame (24 fps) 32 kHz mono bed. C-F077 slices
  141 frames from its head; all that matters is that it is comfortably longer than that,
  so the slice never reaches the end and pads. C-F087 reads its envelope: it is 19.667 s,
  so a `ceil` bin count is 20, and its last 0.667 s is a fade ≈ 15 dB below the body —
  any substitute needs a non-whole-second duration and a tail that is audibly quieter
  than the second before it. C-F062 mixes and crossfades it with the 44.1 kHz
  `ep15-song.mp3` as the 32 kHz half of a rate-mismatched pair. C-F059 loops it to
  `ep33-episode.mp4`'s length. Read-only — never sliced in place, never deleted.
- `asset:qa-cast/ep13-episode.mp4` — a 282-frame 24 fps 960x544 stereo 44.1 kHz
  episode. C-F078 muxes a soundtrack onto it twice; its known geometry is what says the
  mux moved only the audio. C-F057 dissolves it after the 32 kHz `ep6-cold-open.mp4` as
  the 44.1 kHz half of a rate-mismatched pair. Read-only.
- `asset:qa-cast/ep15-song.mp3` — a 30.0 s 44.1 kHz stereo Music 3 track that decodes
  at **+0.76 dBFS**, i.e. with no headroom. C-F078's positive control depends on that: it
  is the clipping exhibit from #158/#159, not just a song, so replacing it with a quieter
  track silently disarms the case. C-F062 mixes and crossfades it with `ep11-bed.wav`;
  its 30.023 s length is in that case's expected durations. Read-only — never normalized
  in place, never deleted.
- `asset:qa-cast/ep6-cold-open.mp4` and `asset:qa-cast/ep3-shot2-reply.mp4` — two
  124-frame 24 fps 960x544 32 kHz stereo shots, joined in that order because the first
  has the loudest outgoing tail among the shared shots (last full second −20.5 dBFS RMS)
  and the second the quietest head (first second −44.4 dBFS RMS). Any substitute pair
  needs the same loud-tail-into-quiet-head shape. C-F083 tiles the first with
  `frame_grid`; its 960×544 / 124-frame geometry is what the expected grid sizes are
  computed from. C-F057 dissolves the first into `ep13-episode.mp4` (its 124 frames are
  in that case's expected frame count). Read-only, never deleted.
- `asset:qa-cast/ep11-coldopen.mp4` — a video with a soundtrack (peak −1.04 dBFS, RMS
  −20.9 dBFS as `analyze_audio` reads it). C-F084 lays `hal-voice.wav` under it. Any
  substitute needs a non-silent soundtrack and a length well over 6.5 s. Read-only.
- `asset:qa-cast/ep20-score.wav` — a ~10.3 s score bed. C-F067 and C-F071 pass it as
  `score` to the two sequence templates; a `total_frames` longer than it draws a
  `slice_past_end` warning, which those cases either expect or avoid by choosing
  `total_frames` ≤ 248. Read-only, never deleted.
- `asset:qa-cast/hal-voice.wav` — a 6.48 s 24 kHz mono line. C-F084's pad control lays
  it under the 19.67 s `ep11-coldopen.mp4`; any substitute just needs to be clearly
  shorter than that video. Read-only, never deleted.
- `asset:qa-cast/ep25-episode.mp4`, above, is also read by C-F086 with
  `get_output_frames`: it is a 248-frame shot dissolved over 12 frames into a 124-frame
  one, so the second shot's first frame is 236, and C-F086's frame arithmetic is
  computed from that geometry.
- `asset:qa-cast/ep33-episode.mp4` — a 224-frame 24 fps 960x544 32 kHz stereo cut that
  decodes at about −1.0 dBFS peak. C-F059 mixes it solo at 1.0 and 0.5 and reads the
  6.02 dB difference; any substitute needs a non-silent 32 kHz soundtrack (its exact
  peak is read at run time). Read-only, never deleted.
- `asset:uploads/qa-cast/room-bed.wav`, above, is also sliced by C-F066 as the "source
  that arrived quiet" half of the near-silent rule: it decodes at about −50 dBFS mean,
  and any substitute must already be under −40 dBFS before it is sliced, or that case's
  negative arm proves nothing.
- `asset:qa-cast/ep49-episode.mp4` — a 372-frame 24 fps 960x544 **44.1 kHz** stereo hard
  cut of three 124-frame shots (`media.shots` named `ep42-shot1-accuse.mp4`,
  `ep42-shot2-deflect.mp4`, `ep37-shot1-receipt.mp4`). C-F112 joins it with
  `ep42-episode.mp4` (32 kHz), so any substitute needs a sample rate other than 32 kHz and
  carried shots. Read-only, never deleted.
- `asset:qa-cast/ep53-episode.mp4` — a 956-frame 24 fps 44.1 kHz cut of eight shots, the
  last three joined by 12-frame dissolves (`media.shots` carries `overlap_frames`), and
  `asset:qa-cast/ep51-bed.wav` — a quiet (~−50 dBFS mean) room bed. C-F123 scores the
  first under the second looped. Shared, read-only, never deleted.
- `asset:qa-cast/ep54-episode.mp4` — `ep53-episode` scored: 956 frames, 44.1 kHz, the same
  eight shots and overlaps, peak about −3 dBFS. C-F124 dissolves it into `ep42-episode.mp4`
  (32 kHz), so a substitute needs carried shots that include dissolves, and a rate other
  than 32 kHz. Shared, read-only, never deleted.
- `asset:qa-cast/ep65-episode.mp4` — a 469-frame 24 fps **48 kHz** stereo cut of four
  shots (`shot@accuse`, `shot@deflect`, `ep65-shot-kf-priya-hal.mp4`,
  `ep62-shot2-deflect.mp4`), the last two joined by 12-frame dissolves. C-F130 scores it
  under `ep15-song.mp3` (44.1 kHz) at `sample_rate` 48000, so a substitute needs a 48 kHz
  soundtrack and carried shots. Shared, read-only, never deleted.
- `asset:qa-cast/ep11-coldopen.mp4`, above, is also the **crest** fixture for the
  `normalize_audio(limit=true)` cases C-F132–C-F134 and, with `asset:qa-cast/ep11-bed.wav`
  (the same 472 frames long) under it, for C-F150. What matters is its gap between true peak
  and loudness: 2026-09-26 it read `integrated_lufs` −17.43 and `true_peak_dbfs` −0.96, a
  16.47 dB gap, so with a −3 ceiling no target above about −19.5 LUFS is reachable by gain
  alone. The cases' target arithmetic (how many dB of limiting a target needs) is derived
  from that gap; a substitute needs a gap of at least 14 dB, and the cases' targets are then
  re-derived from its own `get_gallery_metadata` numbers.

## Functional

### C-F001 — a run-time warning reaches the caller, on both channels
Join two videos whose soundtracks differ by well over 6 dB with
`concat_videos`, twice in one job: one step with no level matching, one with
the level-matching argument set to match perceived level. (Whatever the live
schema calls these — currently `match_levels: "rms"` — confirm against
`get_task`.) The two fixtures above are such a pair.
expected: the **unmatched** step produces a warning on *both* consumer
channels — an entry on `get_job(id).warnings` / `wait_for_job`'s job,
prefixed with the step's name and naming the spread, and a `warning` event
in `get_job_events` carrying `kind: "level_spread"` with the figures
(`spread_db`, `measure`). The **matched** step produces neither. The matched
output's `mean_dbfs` lands on the level target (-20 dBFS by default) rather
than between the two inputs'.
Two things are being pinned, and the second is the reason this case is worth
its seconds: the level matching itself, and the fact that the engine's
run-time warning channel is alive at all. That channel (`emit_warning` →
events + `job.warnings`) is now how *every* run-time diagnostic reaches a
consumer, not just this one — a warning that exists only in the server's own
log is, from outside, a warning that does not exist. If this case fails on
the warning half while the levels still match, the finding is the channel,
and it is more serious than the case looks.
cleanup: delete both joined outputs. Keep the two input assets (fixtures).
source: tester, verified in #82 (implementer proposed the case in its
hand-off comment; added here after running it as job `a8488310d953`, model
`opus` via provider `anthropic`).

### C-F002 — a video step writes the frame rate its frames are meant for
Join the two 24 fps fixtures with `concat_videos`, passing the task's own
`fps` as 24 and declaring **no** frame rate on the step's `result`.
expected: `get_gallery_metadata` on the output reports `fps: 24.0`, 248
frames, and `duration_seconds` ≈ 10.33 — i.e. frame count over 24, matching
the audio track's duration. A written rate of 8 fps (248 frames over 31 s,
against ~10.3 s of audio) is the regression: it is a 3x-slow picture against
correct sound, the job succeeds, and nothing but this metadata call shows it.
The frame rate is supposed to travel with the frames now, with an explicit
`result.fps` overriding, then whatever the frames carry, then 8 only when
nothing knows better.
Worth a second assertion in the same job if it is cheap: declare
`result.fps: 8` on an otherwise identical step and expect the job to carry an
`fps_mismatch` warning (both channels, as C-F001) — deliberate slow motion
stays available, it just says so. Assert the structured fields
(`kind: "fps_mismatch"`, `declared_fps: 8`, `source_fps: 24`) **and**, since
#88, the prose: it must say `0.33x speed` and must not say `3x speed`. A
third step declaring `result.fps: 48` should say `2x speed` — the factor is
`declared/source`, and the two directions together are what catch it being
re-inverted, which one direction alone cannot.
cleanup: delete the joined output(s). Keep the two input assets (fixtures).
source: tester, verified in #84 (implementer proposed the case; added here
after running it as job `a8488310d953`, model `opus` via provider
`anthropic`).

### C-F003 — validation resolves a sub-workflow path, and refuses a cycle
Three `validate_workflow` calls, no run, no GPU:
1. a one-step workflow composing a sub-workflow `path` that resolves
   nowhere (`templates/does-not-exist-at-all`);
2. one composing an absolute path outside every source the server lists
   (`/etc/passwd`), placed at a step that is **not** the first;
3. a composition cycle built on disk: save a leaf workflow `B`, save `A`
   composing `B`, then overwrite `B` to compose `A`; validate `A`.
expected: (1) `valid: false`, one error at `steps[0].workflow.path`, message
naming every candidate path it looked at; (2) `valid: false`, error at the
offending step's own index, not step 0; (3) `valid: false` with the
resolution chain in the message, **and** `run_workflow` on `A` refused at
queue time with the same error — no job created. Also assert the cheap
warning half: composing a real template with an argument name it declares
no variable for is a `warning` (not an error) at
`steps[N].workflow.arguments.<name>`, listing the declared names.
The point is that all of this is free and pre-flight. The regression is
`valid: true` — silent, and paid for later by a queued job that dies after
the expensive steps have already run.
Note `save_workflow` **accepts** the write that creates the cycle in (3),
because at that moment the child on disk is still a leaf; validate and run
both catch it immediately after, so no job can start. Do not assert a
failure at save. The cycle error reads like `... composes a workflow that is
already composing it - a cycle: B -> A -> B`, at a path that repeats
`steps[0].workflow.path` once per hop.
cleanup: delete the `A`/`B` probe workflows from the workspace. No outputs.
source: tester, verified in #89 (run over MCP 2026-09-13 as the calls above,
model `opus` via provider `anthropic`).

### C-F004 — a stored template composes by catalog name, and saves once
One workflow, two steps, each composing the same cheap stored template
(currently `templates/text-to-image`) **by its catalog name, with no copy of
it in the run's workspace**, each parent step declaring its own
`result: {content_type: ..., subfolder: "intermediate"}` while the composed
workflow's own step also declares a `result`. Give the two steps different
arguments so the second cannot be served from the step cache.
expected: the run succeeds — the name resolves from the read-only examples
source, which is the half that was broken (#90) — and it writes **one file
per step, two in total**: `list_gallery` for the run totals 2, both under
`intermediate`, nothing in the run root with `subfolder: ""`, no
byte-identical twin, no `-2` collision suffix. `get_job`'s manifest carries
exactly two entries, keyed on the **parent's** step names, not the composed
workflow's step name (#92).
Two regressions in one cheap run, and both are quiet: an unreachable
template forces every consumer to keep a private copy that silently stops
tracking the original, and a doubled save costs storage and a shadowed
manifest key on every composed run without ever failing a job.
cleanup: delete both outputs.
source: tester, verified in #90 and #92 (run over MCP 2026-09-13 as job
`04c6bf9908d4`, model `opus` via provider `anthropic`).

### C-F005 — a modular pipeline names its blocks while it runs
Run the cheapest modular pipeline on the box — currently
`templates/minimax/music` with a short `audio_duration` (30 is ~75 s) — then
read `get_job_events` for the whole run.
expected: between the `phase: generating` event and the **first**
`pipeline_step`, at least one `log` event of the form `<model>: <block name>`
(e.g. `MiniMaxAI/MiniMax-Music3: semantic_generator`), and one naming
`denoise` at the head of the loop. A `generating` phase followed by no event
at all until a `pipeline_step` is the regression.
Do **not** assert on the exact block names beyond `denoise` — they are
diffusers' own and can change with a version bump. Assert on "at least one
`log` line arrived during the lead-in", not on the sequence.
Second variant, if the level's budget allows an H3 run: the same assertion on
a MiniMax H3 template — the pipeline the original report was about. One
`log` naming a block must arrive at the same `at` as `phase: generating`.
Note that **LTX-2.5 emits no block logs at all** (measured, `templates/ltx2/text-to-video`,
job `83444a2ff3f1`): whatever makes it different from H3/Music3 is not
understood from the consumer side, so do not add an LTX variant expecting
narration, and do not treat its absence there as this case failing.
The whole point is a signal that is *absent*, and an absent signal is exactly
what nobody notices breaking: without it a null `denoise_step` under
`generating` is indistinguishable from a hang, which on H3 with a video
reference means ~10 min of silence a consumer is liable to cancel a healthy
job during (#95).
cleanup: delete the generated audio output.
source: tester, verified in #95 (proposed by the implementer in that issue's
hand-off, run over MCP 2026-09-13 as jobs `bb2c89ba6f54` (Music3) and
`958078231173` (H3), model `opus` via provider `anthropic`).

### C-F006 — the saving phase names the files it writes, and the run matches its curated cost
Run `templates/ltx2/text-to-video` with stock arguments on a **cold worker**
(`get_health` first: `worker_alive: false`), wait for it, then read
`get_job_events`.
expected: inside the `saving` phase, a `log` event naming the file as its
write starts and a second one costing it as it finishes, the closing one
carrying `file` and `seconds` as structured fields rather than only prose.
`saving` → `step_end` under ~5 s. A `saving` phase with no events under it is
the regression, and it is the shape that hid a real performance bug for a
whole cycle.
Also check the whole run against the catalog's curated `minutes` for the
template (1.8 at the time of writing, RTX 3090): within a minute or so of it.
Read the figure from `list_workflows` each run rather than pinning 1.8 here —
the point is that declared and actual still agree, not that the number is
still that number.
`denoise_step` stays frozen at its last value through `saving`; that is what
the phase is, not a finding.
metrics: `latency` of the whole run in seconds from the job's own timestamps
(`condition: cold`), and `latency` of `saving` → `step_end` (`condition:
saving`), logged to `regression-perf/C-F006.jsonl`. The first is the curated
cost check as a trend rather than a one-off; the second is the number that
was 133 s before #97 and ~1.6 s after, so creep there is the regression
returning quietly.
**Cold worker matters:** the curated figure is whole-run wall clock including
model load, and ~65% of this run is `loading`. A warm-worker run lands far
under it and does not test anything.
cleanup: delete the generated mp4.
source: tester, verified in #97 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as job `bd2f45b50862`, model `opus` via
provider `anthropic`).

### C-F007 — a second model family in the same worker lifetime is not OOM-killed
Run two generations back to back **without restarting the server**, so the
second one inherits the first's worker:
1. `templates/ltx2/text-to-video`, stock arguments.
2. `templates/minimax/reference-to-video` in the same lifetime.
expected: job 2 **succeeds**, rather than dying with `Worker process died:
killed by SIGKILL`. In job 2's events, a `Released cached models: host RSS
<n> MB, <n> MB available (<n> MB returned to the OS)` log line at the head of
the run, with the RSS figure a small number of GB — not the tens of GB job 1
peaked at. That line is the assertion; a job-2 success with a residual RSS in
the tens of GB is a pass by luck and should be reported as a near miss.
This box has ~4% host-RAM headroom and `reference-to-video` peaks at ~96% of
it, so job 2 has no margin to absorb anything job 1 left behind. Do **not**
"fix" a failure here by cutting job 2's frame count — the run is fine, the
residue is the bug, and `rerun_job` on a fresh worker succeeding is the
confirmation (that is exactly how #98 was found).
Job 2's own peak should be roughly what it is on a fresh worker (~61.9 GB of
64.2). The fix restored job 2's *starting point*, it did not make the
template cheaper, so a peak that has dropped a lot is a different change
worth asking about rather than an improvement to assume.
Note `get_memory` during a run returns `live: false`, `reason: job_running`
with a cached reading from the *previous* job — do not compare it against a
live figure. `host_pinned_*` is absent (not zero) on `lem`'s torch build.
metrics: logged to `regression-perf/C-F007.jsonl` — job 2's `latency` in
seconds (`condition: job2`), the residual host RSS in MB from the `Released
cached models` line (`bytes`, `condition: residual-rss-mb`), and job 2's
peak RSS in MB (`bytes`, `condition: job2-peak-mb`). The residual is the
number this case exists for: it was 14,928 MB before #98 and ~2,042 MB after,
and a creep back toward the tens of GB is the near miss described above
long before it is a SIGKILL.
**This case is ~10 minutes of GPU time** and is the most expensive in the
file. It earns it: this is the failure mode that silently costs a whole
session's work, and it cannot be tested with one run or with two runs of the
same family.
cleanup: delete both generated outputs.
source: tester, verified in #98 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as jobs `bd2f45b50862` then `2700403c7998`,
model `opus` via provider `anthropic`).

### C-F009 — a paired video keeps its source frame rate, with no `result.fps` anywhere
`pair_audio` is handed frames loaded from a file and an audio track, and the
output must be written at the rate those frames actually run at. Take a 24 fps
fixture and run a one-step inline workflow: `pair_audio` with `video` = that
asset and `audio` = a **stereo** track (the other C-F001 fixture serves), `result` =
`{"content_type": "video/mp4"}` **with no `fps` key**. Task-only, loads no model.
expected: `get_gallery_metadata` on the output reports `fps: 24.0` and
`duration_seconds` matching the source (5.167 s for a 124-frame fixture), not
`8.0` / 15.5 s. **The absence of `result.fps` is the point of the case — do not
add it**, and do not "fix" a failure by adding it. The regression is #104: the
loader dropped the rate, `AudioVideo.fps` came back `None`, and the engine fell
back to `DEFAULT_VIDEO_FPS` = 8, producing a file three times as long with the
audio finishing a third of the way in — `succeeded`, `warnings: []`, silent.
Assert the override arm too, in a second run, because it is what makes the first
arm meaningful: the same workflow **with** `"fps": 12` writes at 12 and emits a
run warning naming *both* rates and the resulting speed factor. A declared rate
that wins silently is a regression even though the file is what was asked for.
(C-F002 owns the detailed assertions on that warning's structured fields and
prose — here just assert one is present and names both rates.)
**Not a duplicate of C-F002**, which is the reason to keep both: C-F002 exercises
`concat_videos`, whose `videos` argument the step loads itself and which has
carried the rate since #84. This case exercises the *other* loader — an argument
named `video` (or `*_video`), which goes through the engine's own file-loading
path and is where the rate was still being dropped as late as #104. Same visible
symptom, two independent code paths; a fix to one has twice now not covered the
other.
Third arm, and the one with the most reach — assert the rate survives the whole
chain with **nothing declared anywhere**. Keep the paired output from arm 1 as an
asset, then `concat_videos` it with another 24 fps asset passing **no `fps`
argument to the task and no `result.fps` on the step**.
expected: 24 fps, and a frame count and duration that are the two sources' summed
frames over 24. This is file → load → `pair_audio` → keep as asset → load again →
join, which is four separate chances to drop the rate; before #104 this shape was
the reliable way to end up with an 8 fps file. Assert it undeclared or the arm
tests nothing — a passed-in `fps` would mask exactly the failure it exists for.
While the join is there and free, assert the level-spread warning too: with
`match_levels` **off** and two shots whose `mean_dbfs` differ by more than a few
dB, the run warns, naming both levels, the spread, and `match_levels` as the
remedy. Silence there is a regression — an audible level jump either side of a
cut is the one seam artifact no fade control can hide, and the warning is the
only thing that surfaces it to a caller who cannot listen.
cleanup: delete the generated outputs and the intermediate asset.
source: tester, verified in #104 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as jobs `7bac4a2b5d07` and `d0b79427fc24`,
model `opus` via provider `anthropic`). Third arm added from job `af9317223452`
the same day while running TESTER_TASK.agent.md.

### C-F014 — a stale cost acknowledgement is refused with a re-usable object
`run_workflow`'s bound acknowledgement (`{fingerprint, minutes, downloads}` from a
`validate_workflow` plan) must be refused when the workflow changed since, and the
refusal must hand back something a caller can act on without re-deriving it.
`validate_workflow` an inline workflow, keep its `plan.fingerprint`, then
`run_workflow` a **changed** workflow (add a step, or change an argument) bound to
that stale fingerprint.
expected: the call is refused, naming the mismatch; the message ends with a
`Re-acknowledge with {...}` object that (a) **parses as JSON** — `minutes` must be
`null`, not Python's `None`, which is the common case since an inline workflow has
no measured estimate — and (b) is accepted **verbatim** as `acknowledged_cost` on
an immediate retry of the changed workflow, which then queues and records
`acknowledged: "bound"`.
It becomes a **finding** if the object stops parsing (the #107 regression: any
Python repr — `None`, `True`, single quotes — inside what reads as pasteable JSON),
if the fingerprint it hands back is not the one the retry needs, or if a stale
acknowledgement is silently accepted.
cleanup: delete the retry run's outputs; the refused call writes nothing.
source: tester, verified in #107 on 2026-09-13 over MCP — refusal quoting
`sha256:ea73f2d8…` with `"minutes": null`, retry job `3fe89e48a2f0` succeeded on
that object pasted back unchanged. Model `opus` via provider `anthropic`.

### C-F016 — a slice past the end of its source is padded with silence, and says so
`slice_audio` asked for more material than its source holds returns the length
asked for with a digitally silent tail. That is deliberate and must stay — a few
frames of tail pad is a legitimate thing to want — but it is also how
`assemble-and-score` lays a short score under a long cut and leaves the rest of
the film unscored. The failure is invisible in the deliverable: the shots' own
world audio keeps going, so the film has no level drop to notice. The warning is
therefore the *entire* fix, and a regression in it looks exactly like success.
Needs the `room-bed.wav` fixture; seconds to run, generates nothing.
expected: (a) one inline `slice_audio` step against
`asset:uploads/qa-cast/room-bed.wav` (4.96 s) asking for `num_frames: 372` at
`fps: 24` — 15.5 s — **succeeds**, writes a file of the full requested length,
and `get_job(...)["warnings"]` holds **exactly two** entries about the slice
(since dw 39a97862, 2026-09-28, a submitted job records the full warning set
validate reports, #402's pre-flight included): the pre-flight one, keyed by
argument path (`steps[0].task.arguments.audio: slice_audio will run ... past the
end of ...`), and the run-time one, prefixed with the step's name (`cut:
slice_audio: ... past the end of ...`). Each names `loop_audio` with its
`target_frames`+`fps` pair as the remedy. The numbers in both must be the real
ones: source ≈ 4.96 s, ≈ 10.5 s padded, 15.50 s returned. (b) Counter-case, a
slice **inside** the source (`num_frames: 48`, `fps: 24`) → `warnings: []`.
(c) Counter-case, a slice a few ms past the end (`start_seconds: 0`,
`duration_seconds: 4.965`) → `warnings: []`: frame-aligned slicing lands a
sample or two past the end routinely and a warning fired on that is noise
nobody can act on. (d) The end-to-end path, which is where it bit:
`run_workflow("templates/assemble-and-score", arguments={shots: three
`common/assets` shots, score: the room-bed asset, sample_rate: 32000, fps: 24,
total_frames: 372})` → succeeds, and its `warnings` carries the same pair: the
pre-flight entry on the `score` slice's argument path and the run-time entry
attributed to the `soundtrack` step. The source reads at its real ~4.96 s here,
not a reinterpreted length: since #180 (see C-F031(b)/(c)) the `soundtrack`
step calls `slice_audio` with no `sample_rate` and a separate `resample_audio`
step follows it, so nothing in this template reinterprets a file's rate
anymore. The warning's arithmetic must be self-consistent with whatever length
the task actually saw.
It is a **finding** if (a) or (d) comes back `warnings: []` (the original bug —
79% of a track padded in silence), if the padding turns into an error or a
short track (that breaks the legitimate tail pad), or if (b) or (c) starts
warning. Fewer than the two entries in (a)/(d) is a finding only if the run-time
entry is the one missing; the pre-flight entry is the validate-time warning
carried into the job and may be absent for a source it cannot probe. More than two
(a third copy) is a finding. Also a finding if the warning is only a server-side log line: score
the job's `warnings` list, which is what a consumer can see.
The documentation half of the fix is checkable too, and free:
`get_guide("tasks", section="Video Processing")` → `slice_audio` must still
state the zero-padding, the warning and `loop_audio`; and
`get_workflow("templates/assemble-and-score")`'s description must still state
that a score shorter than `total_frames` is padded with digital silence and
that the film nonetheless sounds plausible. A caller who reads before running
is the one who never hits this.
cleanup: delete every output these runs write; the fixtures are durable.
source: tester, verified in #126 on 2026-09-13 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep9`, dw 0.4.0-beta.3 — jobs
`4c0b47638446` (past-end, one warning), `734ae3a07a90` (both counter-cases,
`warnings: []`) and `8ba0179fb3b4` (the template end-to-end, warning attributed
to `soundtrack`). Bullet (d)'s reinterpretation claim was stale against #180's
rewiring of `assemble-and-score` (see C-F031) and was corrected during the
2026-09-22 suite audit — it had never been re-verified against dw
0.4.0-beta.4+, where the template resamples instead. Reworded
2026-10-02 for the two-entry warning set (dw 39a97862, filed as drift in #575).

### C-F020 — `templates/dissolve-between-shots` passes `match_levels` through, so its own warning is followable
C-F057 and C-F096 exercise the `dissolve_videos` **task**. This case is about the
**template** that wraps it, which is what a caller actually runs, and about a
different failure: the template used to emit a `dissolve_videos` level-spread
warning telling the caller to "pass `match_levels`" while declaring no such
variable, so taking the advice came back `Unknown variable` (#128). A template
whose own warning names an argument it does not accept costs a round trip every
time, and the caller's first assumption is a typo.
Needs three video assets of the same canvas with a **wide level spread** — the
episode shots this suite's `qa-cast` fixtures provide (ep4/ep6/ep7 span 8.8 dB,
which is the ordinary spread for independently generated shots and is what makes
the warning fire at all). ~8 s, task-only, loads no model.
expected:
- `validate_workflow(name="templates/dissolve-between-shots", arguments={"match_levels":
  "rms", "shots": ["asset:qa-cast/ep4-shot1-amnesty.mp4",
  "asset:qa-cast/ep6-shot1-priya.mp4", "asset:qa-cast/ep7-shot1-ledger.mp4"], "score":
  "asset:qa-cast/ep11-bed.wav"})` — real fixture `shots`/`score` supplied alongside
  `match_levels` so the template's placeholder `asset:` defaults (#166, pinned by
  S-F035) don't also fire — → `valid: true`, `checked_arguments` includes
  `match_levels`. This alone is the literal #128 repro.
- `get_workflow(name=…, variables_only=true)` declares **both** `match_levels` and
  `match_levels_dbfs`, each defaulting to `null` — null so the task's own per-mode
  default stands rather than the template inventing one.
- Run it over the three wide-spread shots with `match_levels: "rms"`, the matching
  `total_frames`, and a score built to exactly that length: the job succeeds with
  `warnings: []`. The **absence** of the level-spread warning is the assertion that
  proves the variable reaches the task rather than only being accepted at the door.
  A declared-but-unbound variable passes the first two checks and fails only this one.
Frame arithmetic, worth asserting on the output and worth stating because the
template's description now carries it: the joined cut is `Σf − (n−1)*d`, which for
equal shots is `n*f − (n−1)*d`. It holds for **unequal** shots too — 124 + 124 + 248
with `dissolve_frames: 12` lands on exactly 472 frames / 19.667 s — and unequal is
the case a caller is most likely to get wrong, since the description states the
equal-shot form.
It is a **finding** if the argument is refused again, if either variable stops being
declared or loses its `null` default, or if the run raises the spread warning despite
`match_levels` being passed.
cleanup: delete both runs' outputs (each sweeps its run directory). Keep the shot
assets — they are episode fixtures.
source: tester, model `opus` via provider `anthropic`, verified in #128 on 2026-09-13
against dw 0.4.0-beta.3 on `lem` (job `bf289b68b439`, three 8.8 dB-spread shots,
`warnings: []` in 6.4 s where the unmatched run had raised the spread warning). The
unequal-shot arithmetic is from job `c35749b7ef07` the same evening, workspace
`qa-ep11`. At complete rather than smoke level because it needs three video assets.

### C-F023 — reloading one workflow against itself releases the resident pipeline first
The worker keeps loaded pipelines between jobs so a repeat run is warm. When the *same* workflow is
re-run with an argument that changes what a step loads — a LoRA scale, a canvas, a step count,
anything in the pipeline identity key — the new stack must be built, and the old one has to go
first. Before #150 it did not: the release path existed but read a `prior_step_keys` map that
nothing ever populated, so it could only fire *within* a single run and never between two. The
second job loaded on top of the first and the worker was SIGKILLed by the host OOM killer. This is
not a comfortable margin on the box that found it: one H3 load alone peaks at ~61.5 GB of 64 GB
host RSS, so there is no headroom for two and never was. C-F007 covers a second model *family* in
one worker lifetime; this covers the case it cannot — one workflow reloaded against itself, where
the workflow name never changes and so the workflow-*switch* release can't fire.
Costs two real runs of whatever template is chosen. Use a template heavy enough that a doubled
load would actually exhaust the host; a small pipeline would pass this case while the bug was fully
present, which is the way it is most likely to be tested into uselessness.
expected:
- **Run 1, cold**, on the template's defaults. `get_job_events` → **no `pipeline_released` event
  at all**. This control is half the case: an unconditional release on every run would satisfy the
  next bullet while meaning nothing.
- **Run 2, same workflow**, with an argument changed that is in the pipeline identity key (not
  merely a call argument — a prompt or an output name will *not* do it; `lora_scale` and a canvas
  or frame count will). `get_job_events` →
  `{"event": "pipeline_released", "reason": "superseded", ...}` carrying
  `gpu_memory_allocated_before_mb` and `gpu_memory_allocated_mb`.
- **Ordering, which is the actual assertion.** That event's `seq` is **lower** than the first
  `{"event": "phase", "phase": "loading"}` of run 2 — released *before* the new load, not after it.
  A release that fires after the load has already happened frees memory the run needed a moment ago
  and prevents nothing.
- **The release names what the previous job left.** Run 2's `gpu_memory_allocated_before_mb` equals
  run 1's closing `memory` event `gpu_memory_allocated_mb`, so the two event streams join up.
- **Run 2 completes**, `status: "succeeded"`. A SIGKILL presents as a job that stops without an
  error rather than as a failure with a traceback, so assert the success explicitly.
- **Peak host memory does not stack.** Run 2's closing `memory` event has a
  `host_memory_peak_rss_mb` **no higher than run 1's** (it is a process-lifetime high-water mark, so
  equality is the expected result, not a coincidence). This is the bullet that actually tracks the
  bug: a second load piling onto the first shows up here long before it shows up as a crash.
It is a **finding** if the `pipeline_released` event is absent from run 2, if its `reason` stops
being `"superseded"`, if it moves after the loading phase, if it starts appearing on the cold
control, or if run 2's peak RSS exceeds run 1's. A slow *first* denoise step on run 2 is **not** a
finding — allocator warm-up after a release-and-reload was observed at 207 s against a 36 s norm
with steps 2+ recovering immediately; only a rate that stays slow is a problem.
cleanup: delete both runs' outputs (sweeps their run directories). Nothing durable is produced.
metrics: `host_memory_peak_rss_mb` for each of the two runs, condition `run1` / `run2`, unit `MB`
— logged to `regression-perf/C-F023.jsonl` pass or fail. The trend that matters is not the absolute
value but whether run 2's reading ever starts exceeding run 1's, which is this bug returning as
creep instead of as a crash.
source: tester, model `opus` via provider `anthropic`, verified in #150 on 2026-09-14 against dw
0.4.0-beta.4 on `lem`, workspace `qa-verify`. Proposed by the implementer; the ordering assertion,
the cold-start control, the peak-RSS bullet and the warm-up caveat are mine. Confirmed with
`templates/minimax/reference-to-video`: job `b4b5959424d3` (defaults, 496.0 s, no release event)
then job `3368b1967b58` (`lora_scale: 0.8`, `num_frames: 141`, 662.3 s, release at `seq 7` / 4.8 s
against loading at `seq 8`, 536.29 → 8.125 MB), `run_count: 2` on one worker, peak RSS 61487.10 MB
on both.

### C-F024 — the mux's own clipping check reads the file it wrote, not the level it was asked for
`normalize_audio` sets the level of a *waveform*; the AAC encode inside `pair_audio`'s
`video/mp4` save then moves it, and by an amount that depends entirely on the material.
Measured on two tracks through the identical chain: one overshot its target by **1.94 dB**,
the other landed **0.92 dB under** it (#161). So a check that reasons from the requested
`peak_dbfs` cannot know whether the deliverable clips. The server now probes the written
file and emits an `audio_clipped` warning when *that* decodes at or above 0 dBFS — which is
the only measurement that answers the question. This case pins the probe, not the constant.
The assertion is the **agreement between the warning and the metadata**, in both directions,
because either half alone is satisfiable by a broken check: a warning that never fires
passes any "deliverable is clean" test, and a warning that always fires passes any "clipping
is caught" test. A normalize target that happens not to clip on this material is therefore
expected to be **silent**, and that silence is a pass, not a miss.
This is the post-encode counterpart to M-F011, which pins the *source*-side
`audio_no_headroom` warning on the waveform as written. Two different measurements of two
different artifacts; a run can legitimately fire one and not the other.
Costs one short CPU-side job — no model loads, no generation.
expected: one inline workflow, `slice_audio(asset:qa-cast/ep15-song.mp3, start_seconds: 2,
duration_seconds: 5)` into two branches, `normalize_audio(peak_dbfs: -0.55)` and
`normalize_audio(peak_dbfs: -3)`, each muxed by `pair_audio(video:
asset:qa-cast/ep6-cold-open.mp4, fit: "video")` and saved as `video/mp4` in `final` —
- **`fit` takes `"video"` or nothing.** `fit: "audio"` is refused with
  `pair_audio: 'fit' takes 'video' or nothing, got 'audio'`. Worth asserting because the
  refusal is what keeps the carrier's frame count authoritative.
- **For each of the two muxed mp4s, `get_gallery_metadata(...).media.peak_dbfs` and the
  presence of an `audio_clipped` entry in `job.warnings` agree.** Peak at or above 0 →
  exactly one warning naming *that* file and a figure within ~0.05 dB of the metadata's.
  Peak below 0 → no warning for that file. Disagreement in either direction is the finding.
- **The warning names the file and its measured level**, in the shape
  `<step>: <filename> decodes at +N.NN dBFS - above full scale, so it clips on playback…`.
  A warning that names only the step, or carries no figure, leaves a reader unable to tell
  which deliverable to re-render.
- **One warning per file at most.** The suppression when the source-side no-headroom check
  has already warned for the same file is deliberate — two warnings about one file read as
  two problems.
- **Do not assert that `-0.55` clips.** It did on one material and did not on another, which
  is the whole reason the probe exists. Assert only the agreement above. If a run wants a
  guaranteed positive, drive the hot branch from material already known to overshoot and
  confirm it from the metadata, not from the target.
cleanup: delete the run's output folder. `asset:qa-cast/ep15-song.mp3` and
`asset:qa-cast/ep6-cold-open.mp4` live in the shared `common/assets` — do not sweep them.
Neither is load-bearing on content: any track a few seconds long and any short video with a
known frame count substitute, since the case asserts agreement rather than a level.
source: tester, model `opus` via provider `anthropic`, verified in #161 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep15`. Proposed by the implementer; the
agreement framing, the true-negative control and the "do not assert -0.55 clips" caveat are
mine, and they come from the run disagreeing with the proposal. Job `e8c5eb90ba83` (the two
branches above): `mux_hot` decoded at **-0.1124 dBFS** with **no** warning — correct, that
material's mux overshoot is only ~0.44 dB — and `mux_safe` at **-3.401**, also silent. Job
`418e6300620a`, identical shape on material that overshoots ~0.96 dB on the sliced window:
`mux_hot` drew exactly one warning, `mux_hot… decodes at +0.41 dBFS - above full scale`,
and `get_gallery_metadata` independently measured **+0.4097**; `mux_safe` measured
**-2.4828**, silent. Job `8eb96c97d799` is where `fit: "audio"` was refused. No `metrics:`
line: a dBFS figure hovering around zero is not something `regression-perf/`'s
median-and-50% rule can say anything useful about, and the assertion here is an agreement,
not a number.

### C-F025 — a workspace asset shadows a shared one by elision, and deleting it leaves the shared copy
An `asset:` reference resolves through a search path — this workspace's `assets/`, then the
shared `common/assets`, then any read-only examples library — and `list_assets` tags every
entry with the `origin` it came from. Two things follow that a consumer has no other way to
learn, and both are easy to break silently: a name present in more than one library is
reported **once**, from the nearest library (the farther copies are elided, not listed as
dimmer duplicates), and `delete_asset` resolves in that same order, so deleting a local
name that shadows a shared one must remove the local copy and leave the shared original
intact. A regression in the first makes the same asset look duplicated or makes a local
override look absent; a regression in the second destroys a shared cast member from inside
a throwaway workspace, which is not recoverable.
Costs nothing — no jobs, no model loads, four metadata calls.
expected: in a workspace created fresh for the case, uploading a file whose stored name
collides with an existing `common/assets` entry, then —
- **Every `list_assets` entry carries an `origin`**, and the response carries `libraries`
  (the search path, nearest first, each `{origin, root, writable}`) and a precomputed
  `folders` list. An entry missing
  `origin` is the finding: the UI's source badge and the delete affordance both key off it.
- **The freshly uploaded entries report `origin: "workspace"`** and everything inherited
  reports `origin: "common"`. Both values must actually appear; a listing where everything
  is one origin proves nothing.
- **The colliding name appears exactly once, with `origin: "workspace"`.** Two entries for
  one name, or the shared copy winning, is the finding.
- **`delete_asset(<colliding name>)` returns `origin: "workspace"`**, and afterwards
  `get_gallery_metadata("asset:<colliding name>")` still resolves — to the shared copy,
  which is how you know the delete stopped at the nearest library. A failure to resolve
  means the shared original was destroyed; that is the severe half of this case.
- Note for whoever runs it: `upload_asset(asset_name: "x/y.ext")` stores under
  `uploads/x/y.ext`, so pick the collision target from a `common` asset already under
  `uploads/` rather than assuming the name you pass is the name you get.
cleanup: delete the workspace created for the case with
`delete_workspace(acknowledged_cost: true)` — that removes the uploaded copies with it.
Nothing in `common/assets` is touched; if the shared copy of the collision target is
missing at the end, that is the case failing, not cleanup to do.
source: tester, model `opus` via provider `anthropic`, verified in #165 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`. Ran in a throwaway workspace `qa-asset165`:
`uploads/qa-cast/room-bed.wav` (present in `common/assets`) was uploaded locally, listed
once as `origin: "workspace"`, deleted with `{"deleted": true, "origin": "workspace"}`, and
`get_gallery_metadata` then still resolved the reference to the shared 4.96 s / 16 kHz /
mono original. #165 itself is a web-UI ticket with no MCP surface — this case pins the
server behaviour the page rests on, not the page. No `examples`-origin library was
observable on this server (`/home/don/diffusers-workflow/assets` was on the search path but
contributed no entries), so the read-only-refusal branch of `delete_asset` is deliberately
not asserted here; it belongs in the dw repo's pytest suite, where a fixture can exist.
Amended 2026-10-01 (#572, approved by Don): `asset_dir`/`asset_dirs` became `libraries`
(`{origin, root, writable}`) in dw 46940b1b; the intent is unchanged.

### C-F028 — a phase that goes silent past the threshold draws no false positive while it is still talking
A job that is working but emitting nothing is indistinguishable from a hung one over MCP, and
the pre-denoise lead-in of an `ltx2` run was the natural instance for exercising the #176
watchdog end to end — but #239 found that lead-in has shrunk from ~48 s (source reading) to
~5 s on a cold load, under the 30 s threshold, so nothing in the current catalog forces the
watchdog to actually fire from MCP any more. The fire, both-surfaces and it-stops properties
are unit-tested directly against the watchdog instead (`tests/test_events.py`:
`test_watchdog_fires_after_threshold_with_no_events`,
`test_watchdog_repeats_while_the_stall_continues`,
`test_watchdog_stops_once_a_new_event_arrives`,
`test_watchdog_event_carries_the_required_fields`), where a fast threshold makes the timing
controllable. Note that the "both surfaces" property this case originally asserted no longer
holds by design: `490a42a` (#176, same day, after this case's own source reading) deliberately
kept a `phase_stall` report out of `job.warnings` — it is a moment, not a fact about the
result — so it reaches only the event log now, pinned by
`tests/test_job_warnings.py::test_a_phase_stall_report_stays_out_of_the_persisted_warnings`.
What is left worth checking from MCP is the one property with no unit-level equivalent: a real
job's `loading` phase, which genuinely runs long while emitting its own sub-events, must not
trip the watchdog on its account. Loads a model; ~1-2 min.
expected: `run_workflow("templates/ltx2/text-to-video", {num_frames: 25, width: 768,
height: 448})`, then `get_job_events` on the finished job —
- **no false positive on a slow-but-talking phase.** The job's `loading` phase runs for tens of
  seconds total while emitting its component sub-events; as long as no *gap between* those is
  over the server's threshold (30 s as built; read it off the reading, don't hard-code it), it
  draws no `phase_stall` anywhere in the job. Check the gaps in the event stream and assert
  against them, not against the phase's total length.
It is a **finding** if any phase that is emitting events inside the threshold draws a
`phase_stall` anyway. It is not a finding if no `phase_stall` fires anywhere in the job — that
is expected while the ltx2 lead-in stays under 30 s, and does not exercise this case's subject.
cleanup: delete the run's outputs. No durable fixtures.
source: tester, verified in #176, model `opus` via provider `anthropic`, on 2026-09-16 against
dw 0.4.0-beta.4 on `lem`. Measured as job `9baf48bea129`: `loading` spanned 6.6-84.2 s with
sub-event gaps of 28.5 s and 21.9 s and stayed clean. Narrowed to the no-false-positive arm
alone in #239 (2026-09-19, dw 0.4.0-beta.6), which found the fire arm unreachable from MCP
(job `4a4048d04cf1`: cold `loading` 1.1-86.2 s with a 32.3 s sub-event gap and no false
positive; `generating` lead-in only 5.4 s, under threshold) and the both-surfaces arm already
superseded by `490a42a`. The fire/repeats/it-stops/typed-fields properties are covered by unit
tests in the dw repo instead, per the options `#239` proposed.

### C-F029 — a six-step task-only chain carries its parameters, and `keep_output` hands the result to a stored template
Every other chained case here is two or three steps. The failure this one is for is
the one that only appears with depth: an argument that survives one hop and is
dropped at the fourth, where the run still succeeds and the deliverable is merely
wrong. It also pins the seam nothing else covers — a generated file promoted with
`keep_output(shared=true)` being consumed by a **stored** workflow under its
`asset:` name in the same session, which is the documented way to feed a template
something the catalog didn't ship. Task-only both halves: no model loads, ~13 s total.
expected: two runs.
(1) A six-step inline workflow (`id` + `seed`, one `result` on the last step only)
chaining `resample_audio` (`asset:uploads/qa-cast/room-bed.wav` → 32000) →
`loop_audio` (`target_frames: 260`, `fps: 24`, `crossfade_ms: 250`) →
`slice_audio` (`asset:qa-cast/priya-voice.wav`, `start_seconds: 0`,
`duration_seconds: 3`) → `resample_audio` (→ 32000) → `mix_audio` over
**both** branches (`audios: ["previous_result:bedloop", "previous_result:priya32"]`,
`gains: [2.5, 0.8]`) → `normalize_audio` (`peak_dbfs: -3`) succeeds with
`warnings: []` and no elided steps, and `get_gallery_metadata` on the one saved
file reports `duration_seconds: 10.8333` (260/24, exactly), `sample_rate: 32000`,
`channels: 1`, `peak_dbfs` within 0.05 dB of **-3.0**. Two independent chains
meeting at `mix_audio` is the point of the shape: the bed's length and the
normalizer's target both have four hops to get lost in.
(2) `keep_output(name=<that file>, asset_name="qa-cast/ep17-score.wav",
shared=true)` returns `reference: asset:qa-cast/ep17-score.wav`, and
`templates/assemble-and-score` run with `shots` = the two 32 kHz C-F001 fixtures,
`score` = that reference, `sample_rate: 32000`, `fps: 24`, `total_frames: 248`,
`seam_fade_ms: 80`, `match_levels: "rms"` succeeds with exactly one warning:
`slice_audio`'s tail-drop (`slice_trimmed_tail`, #342) on the `soundtrack` step,
the score being 10.83 s against a 10.33 s cut — and in particular **no
`slice_past_end`** and no `concat_videos` pad or sample-rate warning — and the film reports 248 frames / `duration_seconds` ≈ 10.334 / `fps: 24.0`
/ `sample_rate: 32000` / `channels: 2` and `peak_dbfs` **below 0** (the template
normalizes to -3 before the mux; the AAC overshoot on this material is a few
hundredths of a dB, so -3 has ample headroom — cf. C-F024, where a lossy source
overshoots by ~0.44 dB).
It is a **finding** if either job warns beyond that one warning (or #342's
warning goes quiet), if the bed's duration is not exactly
260/24, if the score is not 32 kHz mono at -3 dBFS (a rate or a gain dropped
mid-chain), if `keep_output`'s reference is not resolvable by the stored template
(`asset:` reference errors at validation), if the film's frame count, rate or
sample rate moves, or if the film's `peak_dbfs` reaches 0 — that last one being
the clipped-deliverable failure #161 reported against `music-video`, here on the
path that is supposed to be safe from it.
metrics: `film_peak_dbfs` — the decoded `peak_dbfs` of the muxed film from (2),
condition `-`. The number is the mux headroom actually delivered against the -3
the template asked for; drift toward 0 across runs is the regression, and a
single reading can't show it.
cleanup: delete both runs' outputs and the `qa-cast/ep17-score.wav` asset the case
creates (it is rebuilt by step 1 every run, so it is not a fixture). Keep the three
input assets — all durable fixtures listed above.
source: tester, found while running TESTER_TASK.agent.md (episode 17) on 2026-09-16
over MCP as model `opus` via provider `anthropic`, workspace `qa-ep17`, dw
0.4.0-beta.4 — job `589964f1a8db` (8.1 s, bed 10.833344 s / 32 kHz / mono /
-3.0000975 dBFS) and job `5b8def4f9a91` (4.7 s, film 248 frames / 10.334 s /
32 kHz / stereo / -2.9758 dBFS), both `warnings: []`. Episode 17 used
`ep4-shot1-amnesty.mp4`/`ep4-shot2-desk.mp4` as its shots; the C-F001 fixtures are
named above instead because they are the pair this suite already guarantees, and
the case asserts nothing about the shots beyond their rate and frame count.

### C-F030 — `slice_audio`'s `sample_rate` override reinterprets a file, and that silences C-F016's warning
C-F016 guarantees the padding warning that is the *entire* signal a score came up
short, and notes in passing that `slice_audio`'s `sample_rate` reinterprets a
file's rate rather than resampling it. This case pins the consequence of putting
those two together, because it is how the warning goes quiet in exactly the case
where the score is most wrong: given a `sample_rate` below the file's own, the
task consumes proportionally fewer samples, so a slice that would have run past
the end no longer does — no warning — and the material that *is* returned is
time-dilated by the rate ratio (slower and lower). Nothing in the response says
so. The override itself is documented and wanted for a raw waveform; what must
never regress is the pairing's observability, and what must never be "fixed" by
weakening C-F016's warning instead. Needs the `ep15-song.mp3` fixture; ~1.5 s to
run, no GPU.
expected: one inline workflow, seeded, two `slice_audio` steps against
`asset:qa-cast/ep15-song.mp3` (30.023 s, 44100 Hz, stereo), both
`start_frame: 0, num_frames: 792, fps: 24` (= 33.00 s, i.e. past the end), both
writing `audio/wav` to `final`, differing only in `sample_rate`: `ctrl` at
`44100`, `test` at `32000`. Then `get_job(...)["warnings"]` and
`get_gallery_metadata(..., envelope=true)` on both outputs.
(a) `ctrl` produces a warning, prefixed with its step name and containing
`past the end of`, with the real numbers (≈2.98 s padded onto a 30.02 s
source, 33.00 s returned) — this is C-F016's contract, re-asserted on a second
source; it may also carry the fixture's own unrelated no-headroom/clip
warnings (the file peaks above 0 dBFS regardless of the rate given), which are
not part of this case's assertion. `ctrl` carries **no** relabel warning: a
`sample_rate` matching the file's own is not a mismatch. (b) `test` produces
**no** `slice_past_end` warning at all: 33.00 s × 32000 = 1,056,000 samples is
only 23.95 s of a 44100 Hz source, so nothing runs past the end. Since #180's
proposal 2 landed, `test` instead carries a `rate_override_mismatch`-style
warning naming both rates (e.g. `sample_rate=32000 was given, but the source
actually carries 44100 Hz`) and pointing at `resample_audio` — this is the
guard C-F031(a) pins in full; its presence here is expected, not a finding.
(c) Both files decode at `duration_seconds: 33.0`, `ctrl` at 44100 Hz and
`test` at 32000 Hz. (d) The dilation is exactly the rate ratio, 44100/32000 =
1.378: landmark `peak_dbfs` values in the source's own envelope recur in
`test`'s envelope at 1.378× their source timestamp, matching to ~4 decimal
places — e.g. source t=16 s `-8.9205` → test t=22 s; source t=21 s `-21.6359`
→ test t=29 s; source t=23 s `-7.0706` → test t=31 s. (Envelope buckets are
1 s wide, so score the values' identity and the ~1.38 trend across several
landmarks, not a single bucket index.) The override still reinterprets rather
than resamples — the guard warns about it, it does not stop it.
It is a **finding** if (a) stops warning (C-F016 regressed) or gains a relabel
warning of its own (a matching rate flagged as a mismatch), if (b) starts
emitting a `slice_past_end` warning computed from the *file's* rate rather than
the rate the task was given (the warning's arithmetic must stay self-consistent
with the length the task actually saw — C-F016 says the same), if (b) stops
carrying the relabel warning (the guard regressing — #180 proposal 2 going
quiet again), if (d)'s ratio is no longer the rate ratio (the override quietly
became a resample, which is a behaviour change callers relying on the
documented semantics would not be told about), or if either step errors.
cleanup: delete the run's outputs. `asset:qa-cast/ep15-song.mp3` is a durable
fixture listed above — keep it.
source: tester, found while running TESTER_TASK.agent.md (episode 18) on
2026-09-16 over MCP as model `opus` via provider `anthropic`, workspace
`qa-ep18`, job `ce7a0a579ecb` (1.45 s; `ctrl` warned `slice_past_end`, `test`
`warnings: []`; both 33.0 s; landmarks matched at 1.378×). Filed as #180 against
`templates/assemble-and-score`, which wires its mix `sample_rate` into this
parameter and so reaches the dilation from its own defaults. Updated by the
regression agent (`complete` level) on 2026-09-22, model `sonnet` via provider
`anthropic`, after #180 proposal 2 landed: job `65dd5aed9633` reproduced (a)
(past-end warning plus incidental clip/headroom warnings from the fixture's
own level), (b) (`test` now carries the relabel warning and no `slice_past_end`),
(c) (both 33.0 s at their own rates) and (d) (landmarks at 1.378× matching to
4 decimal places) — the case's own "fix landing" carve-out, made the new
baseline rather than an in-band pass/fail read.

### C-F031 — a `sample_rate` that contradicts a file's real rate is warned about, and `assemble-and-score` resamples its score instead of relabelling it
C-F030 pins the *old* pairing: the override dilates and says nothing. This case
pins the two things #180 added on top of it, which are what make the dilation
survivable rather than silent. (1) The general guard: any task that takes an
`audio` argument plus a `sample_rate` warns when the named file's own rate
disagrees with the one it was handed — the one signal that separates a
deliberate reinterpretation from a mistake. (2) The template wiring:
`templates/assemble-and-score` slices its score at the score's own rate and
resamples it in a separate step, so the mix rate is a resample target
everywhere in that workflow and never a reinterpretation. Both halves are
reachable from the template's defaults (`sample_rate: 44100`) with a 32 kHz
score, or from a 32 kHz cut with a 44.1 kHz score, which is what every H3
deliverable on this box is. Needs the `ep15-song.mp3` and
`ep6-shot1-priya.mp4` fixtures; ~6 s to run, no GPU.
expected: three parts.
(a) **The guard.** One inline workflow, seeded, three `slice_audio` steps
against `asset:qa-cast/ep15-song.mp3` (30.023 s, 44100 Hz, stereo), all
`start_frame: 0, num_frames: 792, fps: 24`, differing only in `sample_rate`:
`44100` (the file's own), `32000` (contradicting it), and the argument omitted
entirely. `get_job(...)["warnings"]` carries, for the `32000` step **only**, a
warning naming both rates and saying the samples are relabeled rather than
resampled and that this changes speed and pitch, and pointing at
`resample_audio` as the way to convert — e.g. `sample_rate=32000 was given, but
the source actually carries 44100 Hz`. The other two steps produce **no** such
warning: a matching override is not a mismatch, and an omitted one is not an
override. (Each of the three steps also carries its own unrelated warnings —
`slice_past_end` for the two un-dilated arms, and a no-headroom warning on the
saved file for all three; score the presence and absence of the *rate* warning,
not the total count.)
(b) **The template's shape.** `get_workflow("templates/assemble-and-score")`:
the `soundtrack` step calls `slice_audio` with `audio`/`start_frame`/
`num_frames`/`fps` and **no** `sample_rate`; a `resample_audio` step follows it
with `target_sample_rate: variable:sample_rate`; and the `mix_audio` step
consumes that resampled step, not `soundtrack` directly.
(c) **The chain does not dilate, and still pads.** Run that pair inline —
`slice_audio` (no `sample_rate`) then `resample_audio(target_sample_rate:
32000)` — over the same source, asking for 792 frames @ 24 fps. The output
decodes at `duration_seconds: 33.0`, `sample_rate: 32000`, the `slice_past_end`
warning is present on the slice step, and `get_gallery_metadata(...,
envelope=true)` puts the source's landmark `peak_dbfs` values at **their own
timestamps, ratio 1.0** — source t=16 s `-8.9205` → t=16 s, t=21 s `-21.6359` →
t=21 s, t=23 s `-7.0706` → t=23 s, each within ~0.1 dB (the resample's own
error) — with the last ~3 s at `-120.0 dBFS`, the pad, ending at 30.02 s where
the source does. Then run the template itself for the end-to-end shape:
`run_workflow(workflow_path="templates/assemble-and-score", arguments={shots:
["asset:qa-cast/ep6-shot1-priya.mp4"], score: "asset:qa-cast/ep15-song.mp3",
sample_rate: 32000, fps: 24, total_frames: 124, score_start_frame: 0})` — a
44.1 kHz score under a 32 kHz cut, the exact shape #180 reported. It succeeds
with `warnings: []` (nothing is overridden and a 30 s score covers a 5.17 s
cut), and the film decodes at 124 frames / 24 fps / 960x544 / 32000 Hz, ~5.17 s.
It is a **finding** if the mismatch warning in (a) disappears (the guard
regressed — the dilation is silent again, which is #180 returning), if it starts
firing on the matching or the omitted arm (a false positive on the two
correct ways to call the task, which trains callers to ignore it), if (b)'s
`soundtrack` step regains a `sample_rate` argument or the resample step is
dropped, if (c)'s landmarks move off ratio 1.0 toward 1.378 (the template is
reinterpreting the score again) or the `slice_past_end` warning goes quiet, or
if the template run errors or returns a film at the wrong rate or length. A
warning that fires for a raw waveform given a `sample_rate` is **not** a
finding: a waveform carries no rate of its own, so the argument is the only way
to supply one and can't contradict anything — but it is worth noting if seen,
since it would be the same false-positive shape as the omitted arm.
cleanup: delete both runs' outputs, including the template run's film under
`templates/assemble-and-score/`. `asset:qa-cast/ep15-song.mp3` and
`asset:qa-cast/ep6-shot1-priya.mp4` are durable fixtures listed above — keep
them.
source: tester, verified in #180 on 2026-09-16 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep18`, jobs `54de94ae21fd` (guard, 3.2 s),
`efd7e2ff2144` (chain, 0.9 s) and `a6e92ae356b9` (template end to end, 2.2 s),
against `dw` 0.4.0-beta.4. Proposed by the implementer in #180's hand-off
comment, both halves; added here after confirming each over MCP. Reads with
C-F030, which pins the override semantics this warns about, and with C-F016,
whose padding warning the mismatch used to suppress.

### C-F032 — `templates/dissolve-between-shots` resamples its score instead of relabelling it, and its past-end warning survives a mix rate that differs from the score's
C-F031 (b)/(c) pin #180's wiring in `assemble-and-score`; this is the same
assertion against its sibling, `dissolve-between-shots`, which #196 found had
been left on the old wiring (`sample_rate` fed straight into the `soundtrack`
`slice_audio` step). The tell is the C-F030/C-F031 one: a relabel stretches the
score, so a slice that runs past the score's real end lands "inside" the
stretched source and the `slice_past_end` warning goes quiet — the deliverable
then ships with the score slow and pitched down, and the run says nothing
true about it. A two-run probe identical except for `sample_rate`, with
`total_frames` deliberately past the score's end, makes the past-end warning
the assertion. Task-only, loads no model, uses the two C-F001 fixtures and the
`ep15-song.mp3` fixture; ~10 s for both runs.
expected: four parts.
(a) **The template's shape.** `get_workflow("templates/dissolve-between-shots")`:
the `soundtrack` step calls `slice_audio` with `audio`/`start_frame`/
`num_frames`/`fps` and **no** `sample_rate`; a `soundtrack_resampled` step
(`resample_audio`, `target_sample_rate: variable:sample_rate`) follows it; and
`mixed` consumes `previous_result:soundtrack_resampled`, not `soundtrack`.
(b) **Control and treatment agree on the past-end warning.** Two
`run_workflow(workflow_path="templates/dissolve-between-shots", arguments={shots:
[<the two C-F001 fixtures>], score: "asset:qa-cast/ep15-song.mp3", fps: 24,
dissolve_frames: 12, total_frames: 840, score_start_frame: 0, sample_rate: R})`
with `R = 44100` (the score's own rate) and `R = 32000` (the shots' rate,
contradicting the score's). Both succeed, and both carry on the `soundtrack` step
a `slice_audio` warning that the slice runs ~4.98 s past the end of a 30.02 s
source (840 frames @ 24 fps = 35 s against a 30.02 s song). **Neither** run
carries a warning saying `sample_rate=... was given, but the source actually
carries 44100 Hz` / that samples are being relabeled — the relabel guard C-F031
(a) pins has nothing to fire on because the template no longer overrides the
score's rate. Each run also warns about the shots' level spread (the C-F001 pair
is unmatched by design) and about a 35 s track laid over a 236-frame / 9.83 s
cut; those are the probe's shape, not the assertion — score the presence of
`slice_past_end` and the absence of the relabel warning, not the count.
(c) **The film is at the mix rate and the right length.** `get_gallery_metadata`
on the treatment run's `film` output reports `sample_rate: 32000`,
`duration_seconds: 35.0` (±0.05), `frame_count: 236`, `fps: 24`, and `peak_dbfs`
within ~0.1 dB of -3.0 (the template's `balanced` step). A relabel would have
produced a 41.4 s track (35 × 44100/32000).
(d) **An in-range run is clean.** The treatment arguments with `total_frames:
236` (in range), `match_levels: "rms"` and `match_levels_dbfs: -24` validate
clean and finish with `warnings` empty — no `sample_rate_mismatch`, no
`slice_past_end`.
It is a **finding** if (a)'s `soundtrack` step regains a `sample_rate` argument
or the resample step is dropped or bypassed by `mixed`; if the treatment run's
`slice_past_end` warning is missing while the control's is present (the
template is relabelling again — #196 returning); if either run carries the
relabel warning; or if (c)'s duration drifts toward 41.4 s or its rate is not
32000. A treatment run whose `slice_past_end` text quotes a *different* source
length than the control's is the same finding (the length is being read after
a relabel).
cleanup: delete both runs under `templates/dissolve-between-shots/`. The two
C-F001 fixtures and `asset:qa-cast/ep15-song.mp3` are durable fixtures listed
above — keep them.
source: tester, verified in #196 on 2026-09-17 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep19`, jobs `8f70801901e1` (control,
44100, 6.9 s) and `511d18c51aca` (treatment, 32000, 3.4 s), against `dw`
0.4.0-beta.6; treatment film decoded at 32000 Hz / 35.0 s / 236 frames /
-2.948 dBFS. Proposed by the tester in #196's body and by the implementer's
hand-off; added after confirming over MCP. The verify used
`ep4-shot1-amnesty.mp4`/`ep4-shot2-desk.mp4` (8.1 dB spread) as its shots; the
C-F001 fixtures are named above instead because they are the pair this suite
already guarantees (same 124 frames / 24 fps / 32 kHz), and the case asserts
nothing about the shots beyond their rate and frame count — as C-F020 does.
Reads with C-F031, whose (b)/(c) are the same assertion on `assemble-and-score`.
source: merged C-F045 (curation 2026-09-24)

### C-F035 — `templates/audio-trim-fade` carries the source rate through, and a `result.sample_rate` relabel warns at save time
C-F031 (a) pins #180's guard on a task's `sample_rate` *argument*. #205 found the
other write path it missed: a step's `result.sample_rate` relabels the waveform
at save time with no warning at all, and it fires *after* the argument guard is
satisfied — so a caller who passed the correct argument rate got `warnings: []`
and a file playing 1.84× fast. `templates/audio-trim-fade` shipped that shape
(a hardcoded `result.sample_rate: 44100` on both steps against a `sample_rate`
variable that reached only `fade_audio`'s argument). The fix removed the
template's rate entirely and taught `save_artifact` the same
`rate_override_mismatch` warning. Three task-only runs over the 24 kHz
`priya-voice.wav` fixture (7.453 s, mono); ~6 s total, no GPU.
expected: four parts.
(a) **The template's shape.** `get_workflow("templates/audio-trim-fade")`: its
variables are exactly `input_audio`, `start_seconds`, `duration_seconds`,
`fade_in_ms`, `fade_out_ms` — **no** `sample_rate` — and neither the `trim` nor
the `fade` step's `result` block carries a `sample_rate` key; `fade`'s task
arguments carry none either. A `run_workflow` on it with `"sample_rate": 24000`
in `arguments` is refused before queueing (`Unknown variable 'sample_rate'`).
(b) **The template carries the source rate.** `run_workflow(workflow_path=
"templates/audio-trim-fade", arguments={"input_audio":
"asset:qa-cast/priya-voice.wav", "fade_out_ms": 500})` succeeds with
`warnings: []`, and `get_gallery_metadata` on the `fade` step's mp3 reports
`sample_rate: 24000`, `channels: 1`, `duration_seconds` within 0.05 s of the
source's 7.453.
(c) **The save-time guard.** One inline workflow: `slice_audio` `{"audio":
"asset:qa-cast/priya-voice.wav", "start_seconds": 0.0}` → `result:
{"content_type": "audio/wav", "save": false}`, then `fade_audio` `{"audio":
"previous_result:trim", "fade_out_ms": 500}` → `result: {"content_type":
"audio/mp3", "sample_rate": 44100}`. It succeeds, and `warnings` holds exactly
one relabel warning, on the `fade` step, naming `save_artifact` — `fade:
save_artifact: sample_rate=44100 was given, but the source actually carries
24000 Hz. The samples are being relabeled at 44100 Hz, not resampled …` — and
pointing at `resample_audio`. The file decodes at `sample_rate: 44100`,
`duration_seconds` ≈ 4.056 (7.453 × 24000/44100): the declared rate still wins,
it is just no longer silent.
(d) **No false positive.** The same `fade_audio` step alone over the fixture
with `result.sample_rate: 24000` (matching the carried rate) succeeds with
`warnings: []`.
It is a **finding** if (a) regains a `sample_rate` variable or a
`result.sample_rate` on either step; if (b) comes back at 44100 Hz or ~4.06 s,
or with any relabel warning (#205 returning); if (c) succeeds with no
`save_artifact` relabel warning (the save-time guard is gone — the silent arm
of #205 returning) or with the warning attributed only to the task argument
path; or if (d) warns (a matching declaration is not a mismatch, and a false
positive here trains callers to ignore the real one). Positive control if (c)'s
duration looks wrong: `resample_audio(target_sample_rate=44100)` over the same
fixture gives 7.453 s at 44100 Hz with no warning.
cleanup: delete all three runs (each sweeps its run directory).
`asset:qa-cast/priya-voice.wav` is a durable shared fixture listed above — keep
it.
source: tester, verified in #205 on 2026-09-17 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep19`, jobs `ba670a6ce8f5` (template, 1.9 s,
24000 Hz / 7.453 s), `02851bda9aec` (relabel guard, one `save_artifact` warning,
44100 Hz / 4.056 s), `8853b064f22c` (matching declaration, no warning) and
`1822a921ff72` (resample control, 44100 Hz / 7.453 s), against `dw`
0.4.0-beta.6 at develop `e762dae`. Proposed by the tester in #205's body and by
the implementer's hand-off; added after confirming each part over MCP. Reads
with C-F030/C-F031, which pin the argument-level override and its guard.

### C-F036 — `templates/assemble-and-score` at its default `sample_rate` upsamples all-32 kHz inputs honestly
C-F031(c) runs the template with `sample_rate` *passed* (32000 under a 44.1 kHz
score). This is the arm it leaves open: the argument **omitted**, so the
template's own default (44100) is the mix rate, over inputs that are all
32 kHz — shots and score alike, the shape of every H3 deliverable on this box
handed to the template by a caller who never read the default. Every audio
path in the workflow (the shots' soundtracks through `edit`/`world`, the score
through `soundtrack`/`soundtrack_resampled`) has to convert 32000 → 44100
rather than relabel, and a relabel is caught by one number: duration. Needs
the C-F001 fixtures (`ep3-shot1-incident.mp4` / `ep3-shot2-reply.mp4`, 124
frames each, 32 kHz stereo) and `room-bed.wav`; two utility jobs, ~4 s total,
no GPU.
expected: two parts.
(a) **A 32 kHz score of the cut's length.** Inline, seeded: `loop_audio`
(`audio: asset:uploads/qa-cast/room-bed.wav`, `target_frames: 248`, `fps:
24`) → `resample_audio` (`audio: "previous_result:bed"`, `target_sample_rate:
32000`), the second step with a `result` block (`content_type: audio/wav`).
`validate_workflow` reports `plan.steps: 2` and no elision (the first step is
read by the second). The output decodes at `duration_seconds` 10.33 ± 0.01,
`sample_rate: 32000`, 1 channel. `keep_output` it to an asset for (b).
(b) **The template, defaults.** `validate_workflow(name=
"templates/assemble-and-score", arguments={shots: [the two C-F001 fixtures],
score: "asset:<the kept score>", fps: 24, total_frames: 248, seam_fade_ms:
80, match_levels: "rms"})` — **no `sample_rate`** — is valid with
`checked_arguments` naming exactly those six and `plan.steps: 8`; run it with
the bound `acknowledged_cost`. It succeeds with `warnings: []` (nothing is
overridden, so the C-F031 guard has nothing to say, and the score covers the
cut exactly). The film decodes at **248 frames / 24 fps / `sample_rate:
44100` / 2 channels / `duration_seconds` 10.333 ± 0.01**, `peak_dbfs`
strictly below 0 (the template's `balanced` step targets −3; the mux
overshoots by tenths). The rate is the template's default, not the inputs' —
that is the point — and the duration is the cut's: a relabel of 32 kHz
samples as 44.1 kHz would shorten the track to ~7.5 s (ratio 0.7256) or, the
other way, stretch it to ~14.2 s.
It is a **finding** if the run errors (a step refusing to mix two rates, the
shape #184 reported from an inline chain), if the film's rate is anything but
44100 with `sample_rate` omitted (the default stopped applying, or the shots'
rate leaked into the mix), if `duration_seconds` is off by more than 0.05 s
(a relabel somewhere in the chain), if `warnings` is non-empty (a false
positive from the mismatch guard on a call that overrides nothing), or if
`peak_dbfs` reaches 0. A film at 44100 that is 10.33 s long with a
`rate_override_mismatch`-style warning is still a finding — the warning is
the finding.
cleanup: delete both jobs' outputs and the kept score asset (it is rebuilt by
(a) every run, not a fixture). The C-F001 fixtures and
`asset:uploads/qa-cast/room-bed.wav` are durable — keep them.
source: tester, found while running TESTER_TASK.agent.md (episode 20) on
2026-09-18 over MCP as model `opus` via provider `anthropic`, workspace
`qa-ep20`, jobs `ec8f8b7e5d3f` (score, 0.6 s, 10.333313 s / 32000 Hz / mono)
and `e6c0a3b2d783` (template, 2.9 s, 248 frames / 10.333333 s / 44100 Hz /
stereo / −2.884 dBFS, `warnings: []`), against `dw` 0.4.0-beta.6. Episode 20
used `ep4-shot1-amnesty.mp4`/`ep4-shot2-desk.mp4` as its shots (124 frames /
32 kHz stereo each); the C-F001 fixtures are named instead, as C-F029 does,
because they are the pair this suite guarantees and the case asserts nothing
about the shots beyond their rate and frame count. Reads with C-F031, which
pins the passed-argument arm, and C-F029, the same template at its inputs'
rate.

### C-F037 — `templates/assemble-and-score` honours the seam choice: `seam_fade_ms` on a speech tail is clean, `audio_bleed_ms` on the same tail warns
C-F073 pins the `bleed_join` detector at the `concat_videos` task level. This is the template-level pair on real dialogue: the same
two-shot cut run twice through `templates/assemble-and-score`, once with the
hard cut the warning recommends and once with the bleed it warns about, so a
regression in how the template forwards `seam_fade_ms` / `audio_bleed_ms` to
its `edit` step (a dropped variable, a default that overrides the argument, a
bleed applied on top of a fade) shows up as the wrong arm warning. Needs the
ep21 fixtures above and a 32 kHz score of the cut's length — build one as
C-F036(a) does, or reuse any 32 kHz ≥ 10.34 s audio asset. Two template
jobs, ~3 s each, no GPU.
expected: two parts, read from each job's `warnings` and the film's metadata.
Common arguments: `shots: [asset:qa-cast/ep21-shot1-receipt.mp4,
asset:qa-cast/ep21-shot2-verdict.mp4]`, `score: "asset:<the score>"`,
`sample_rate: 32000`, `fps: 24`, `total_frames: 248`, `match_levels: "rms"`,
`score_gain: 0.0`, `world_gain: 1.0`.
(a) **Hard cut.** `audio_bleed_ms: 0`, `seam_fade_ms: 80`. `validate_workflow`
is valid (the template plans 8 steps; the count is not this case's subject); the run succeeds with **no `bleed_join:`
warning**, and the film decodes at 248 frames / 24 fps / `sample_rate: 32000`
/ 2 channels / `duration_seconds` 10.333 ± 0.01, `peak_dbfs` strictly below 0.
(b) **Bleed.** `audio_bleed_ms: 1800`, `seam_fade_ms` omitted. Same
arguments otherwise; the run succeeds and the `edit` step carries a
`bleed_join:` warning saying the reversed tail looks tonal or speech-like,
quoting a flatness and a harmonicity and suggesting `seam_fade_ms`. Same
frame count and duration as (a).
It is a **finding** if (a) carries a `bleed_join:` warning (a bleed is being
applied despite `audio_bleed_ms: 0`, or the fade path is being run through
the detector), if (b) carries none (the argument is not reaching `concat_videos`,
or the fixture's tail is no longer voiced — check the fixture before filing),
if either run errors, or if either film's frame count, rate or duration is
off. `score_gain: 0.0` must be accepted without a warning in both arms (a
muted score is a legal mix). Levels are **not** the assertion: with
`match_levels: "rms"` shot 1 is clip-held short of the −20 dBFS target and
the seam still carries a ~2.6 dB step. #214 (clip-hold now reported, C-F069) and
#215 (template exposes `match_levels_dbfs`, C-F038/C-F067) are verified; level
matching is their subject, not this case's.
cleanup: delete both runs and the score if it was built for this case. The
ep21 fixtures are durable — keep them.
source: tester, found while running TESTER_TASK.agent.md (episode 22) on
2026-09-18 over MCP as model `opus` via provider `anthropic`, workspace
`qa-ep22`, score `asset:qa-cast/ep20-score.wav` (32 kHz mono, 10.33 s), jobs
`a3f5e0b2fcbe` (fade: `warnings: []`, 248 f / 10.334 s / 32000 Hz / stereo /
peak −3.002 dBFS, seam second rms −20.1 / peak −4.6) and `ca911ef36454`
(bleed 1800 ms: `bleed_join` flatness 0.22 / harmonicity 0.33), against `dw`
0.4.0-beta.6. Episode 21 (job `bbbd9aef3825`) is where the warning first fired
on this material with `audio_bleed_ms: 400`; ep22 is the re-cut the warning
asked for.

### C-F038 — `templates/dissolve-between-shots` honours `match_levels_dbfs` across three shots: every shot is gained to the lower target, none is clip-held
C-F037 leaves levels out of its assertion because the default −20 dBFS
`rms` target clip-holds a loud shot (#214). This is the level-match check the
extra variable makes possible (#215): three dialogue shots that sit 6–8 dB
apart are dissolved with `match_levels_dbfs: -24`, and the assertion is read
from the `dissolve_videos` step's level-match events — one per shot, each
with the measured rms, the gain applied, and `held`. A regression in how the
template forwards the target (variable dropped, default −20 winning, the
clip-hold engaging where the headroom exists) shows up as a wrong gain sign,
a `held: true`, or a missing event. Needs the two ep21 fixtures above plus a
third 24 fps / 124-frame / 32 kHz stereo shot — `asset:qa-cast/ep4-shot1-amnesty.mp4`
(shared `common/assets`, quieter than the ep21 pair) is what the source run
used; either C-F001 fixture substitutes, re-reading its frame count. One
template job, ~6 s, no GPU.
expected: `validate_workflow` on `templates/dissolve-between-shots` with
`shots: [asset:qa-cast/ep21-shot1-receipt.mp4, asset:qa-cast/ep21-shot2-verdict.mp4,
<third shot>]`, `dissolve_frames: 12`, `match_levels: "rms"`,
`match_levels_dbfs: -24`, `score: "asset:<any 32 kHz audio>"`,
`sample_rate: 32000`, `fps: 24`, `total_frames: 348` (= 3×124 − 2×12; re-derive
if the third shot's count differs), `score_gain: 0.6`, `world_gain: 1.0` is
valid; the run succeeds. `get_job_events` carries **three** level-match
events from the `dissolve_videos` step, one per shot in order, each naming
the measured rms in dBFS and the gain in dB, with **`held: false` on all
three** and each gain ≈ (−24 − measured rms) within 0.2 dB — so a shot
measuring above −24 gets a negative gain and one below gets a positive one.
The film decodes at 348 frames / 24 fps / 32000 Hz / 2 channels /
`duration_seconds` 14.5 ± 0.01, `peak_dbfs` strictly below 0; the seam
`envelope` from `get_gallery_metadata(envelope=true)` has no second more than
6 dB below its neighbours (no hole at either dissolve). A `slice_past_end`
warning on the score is expected when the score is shorter than 14.5 s and is
not a finding.
It is a **finding** if any event reports `held: true` (there is headroom for
every gain at −24 on this material), if a gain's sign contradicts its measured
rms against −24, if a gain matches the −20 target instead (the variable is not
reaching the task), if fewer than three events appear, if the run errors, or
if the film's frame count, rate or duration is off.
cleanup: delete the run. The ep21 fixtures and the shared ep4 shot are
durable — keep them.
source: tester, found while running TESTER_TASK.agent.md (episode 23) on
2026-09-19 over MCP as model `opus` via provider `anthropic`, workspace
`qa-ep23`, score `asset:qa-cast/ep20-score.wav` (10.33 s, padded 4.17 s with a
`slice_past_end` warning), job `1032400503fc` (6 s): shot rms −24.3 / −20.6 /
−27.9 dBFS → gains +0.3 / −3.4 / +3.9 dB, all `held: false`; film 348 f /
14.5 s / 32000 Hz / stereo / peak −2.94 dBFS, envelope rms −21.7 to −33.8 with
no seam hole; against `dw` 0.4.0-beta.6. The same job is the repro for #235
(the `film` step's `subfolder` is `""`, not `final`) — that is not part of
this case's assertion.

### C-F039 — a parent's own `cost` block sums with a composed child's curated cost as a `catalog` estimate
One `validate_workflow` call with an inline `workflow`, no run, no GPU: a
one-step parent carrying its own `cost: [{device: cuda, name: "RTX 3090",
vram_gb: 24, minutes: 0.5}]`, whose step is `workflow: {path:
templates/ltx2/text-to-video, arguments: {prompt: "variable:prompt"}}`
(curated cost, 1.8 min on RTX 3090), with `variables: {prompt: "a lighthouse
at dusk"}`.
expected: `plan.estimate.minutes` is the sum (2.3), `basis: "catalog"`,
`measured_on: "RTX 3090"`, `partial: false` — the parent's own priced work
plus the child's curated figure account for the whole run, so nothing is
partial.
cleanup: none — inline validations write nothing.
source: tester, verified in #242 (run over MCP 2026-09-19, model `opus` via
provider `anthropic`, against `dw` 0.4.0-beta.6); narrowed in #276 — this
case's original calls (1) and (2) asserted a pure-composition parent with no
`cost` of its own comes back `basis: "unknown"`/`partial: true`, which #268
deliberately changed (such a parent now inherits `basis: "observed"` from a
fully-observed child) and which C-F042 now covers more precisely, including
the still-live #242 hazard (a composed child's number silently trusted as a
parent's total) via its mixed-step call. Call (2)'s premise — a child with
`cost: null` and no observed history — had also gone stale on this box,
where curated-cost children accumulate observed runs over time. Retired
rather than rewritten, per #276 (model `opus` via provider `anthropic`).

### C-F040 — `validate_workflow` never refuses on a resident `for_each`'s host-memory projection, and skips it entirely for a task-only workflow
One cheap run plus four free validations; no model, no GPU. Save a
workspace workflow `c-f040-qr-list`: `variables: {codes: [{name: "a", text:
"alpha"}]}` and one step `{name: "qr", for_each: "variable:codes", task:
{command: "qr_code", arguments: {qr_code_contents: "item:text", height: 256,
width: 256}}, result: {content_type: "image/png", subfolder: "final"}}` — no
`release_pipeline`/`release_models`, so it is the resident shape, and no
pipeline/pipeline_reference/workflow step anywhere (task-only). Then:
1. `validate_workflow(name="c-f040-qr-list", arguments={codes: [32 entries]})`
   **before any run** (32 is the `for_each` cap; 33 is a schema error);
2. `run_workflow` it once with the 1-entry default, `wait_for_job`;
3. the same 32-entry validation again;
4. the same validation with 16 entries;
5. `save_workflow(patch=...)` adding `release_pipeline: true` to the `qr`
   step, then the 32-entry validation once more.
expected: (1) `valid: true`, `warnings: []` — cold start, no history, no
projection; (3) `valid: true`, `warnings: []` — a task-only workflow has no
pipeline/pipeline_reference/workflow step, so `host_memory_warnings` returns
`[]` unconditionally regardless of history or entry count (#348,
`_has_seedable_step`); this is not the same thing as a silent projection
that stayed under this box's RAM ceiling (see #334 for that shape, now
retired here since it no longer applies to a task-only fixture) — it is the
gate suppressing the projection outright; (4) `warnings: []` for the same
reason; (5) `warnings: []` — still task-only after `release_pipeline: true`,
the gate doesn't look at the release flag. The regressions: `valid: false`
on any call (the approved scope never refuses), or a warning on (1), (3),
(4), or (5) — any of them would mean the task-only gate stopped suppressing
the projection, or a projection formed from nothing.
cleanup: `delete_workflow("c-f040-qr-list")`; delete the run's output.
source: tester, verified in #243 (run over MCP 2026-09-19 as the calls above,
model `opus` via provider `anthropic`, against `dw` 0.4.0-beta.6); expected
text corrected for #272's job-scoped peak per #334 (2026-09-22); rewritten
for #348's task-only gate, which made the warning-branch assertions here and
in the retired C-F041 unreachable — see #369 (2026-09-22). #348's
base+slope projection on a pipeline-bearing workflow is now covered live by
M-F029 (`regression-suite-model-specific.md`) against `acorn-wars/shots-batch`;
the #264 default-arguments-row guard remains pinned by
`tests/test_host_memory_projection.py::test_default_arguments_row_still_counts_toward_the_projection`
in the dw repo's own pytest suite.

### C-F042 — a pure-composition parent inherits its observed child's basis, carrying `runs`/`measured_on` through; a parent with its own uncosted step does not
Five `validate_workflow` calls with an inline `workflow`, no run, no GPU.
All compose `templates/minimax/video-with-audio` — pick any catalog child
that `list_workflows` reports with `observed_runs >= 1` on this box if that
one has none — with a step `{name: "clip", workflow: {path: <child>,
arguments: {prompt: "a ferrofluid pool", num_frames: 124, width: 960,
height: 544}}, result: {content_type: "video/mp4", file_base_name: "clip",
subfolder: "final"}}`, `seed: 7`, and **no** `cost` block on the parent:
1. `id: "c-f042-pure"` — that one step only;
2. `id: "c-f042-mixed"` — the same step plus a second, own step `{name:
   "frames", task: {command: "frame_grid", arguments: {video:
   "previous_result:clip", count: 4}}, result: {content_type: "image/png",
   file_base_name: "frame", subfolder: "frames"}}` with no `cost` anywhere;
3. `validate_workflow(name: <child>)` — note `plan.estimate.runs` and
   `plan.estimate.measured_on`;
4. `id: "c-f042-one"` — a pure-composition parent with one child step
   (`{name: "a", workflow: {path: <child>}}`);
5. `id: "c-f042-two"` — two `workflow` steps to the same child (`{name: "a",
   workflow: {path: <child>}}, {name: "b", workflow: {path: <child>}}`).
expected: (1) `plan.estimate.basis: "observed"`, `partial: false`,
`unpriced: []`, and `minutes` equal to the child's own `observed_minutes` —
every declared step is a `workflow` step, so the children's figures are the
whole story; (2) `basis: "unknown"`, `partial: true`, `unpriced` naming the
parent — the `frame_grid` step is real declared work nobody priced, and
inheriting the child's number as a trusted total is exactly #242's hazard.
(4) `basis: "observed"`, `partial: false`, `minutes` equal to (3)'s, and
`runs` and `measured_on` equal to (3)'s — populated, not null; (5) `basis:
"observed"`, `minutes` twice (3)'s, `runs` equal to (3)'s (the min across
children, which are the same child), `measured_on` equal to (3)'s (every
child names the same device).
The regressions: (1) back to `basis: "unknown"`/`partial: true` (#268
reverted); (2) coming back `partial: false` (the pure-composition test
widened to "any parent with a composed child", which is the bug an earlier
attempt at #268 had); or (4)/(5) coming back `basis: "observed"` with
`runs: null` or `measured_on: null` — an estimate that says it was measured
without saying how many times or on what. (A multi-child parent whose
children genuinely disagree on device should null `measured_on`; that is
not reproducible on a one-GPU box and is left to the dw pytest suite.)
cleanup: none — inline validations write nothing.
source: tester, verified in #268 (run over MCP 2026-09-21 as calls 1-2,
model `opus` via provider `anthropic`; the implementer's proposed case from
its #268 hand-off, with the #242 half kept as its own numbered call) and
in #275 (run over MCP 2026-09-21 as calls 3-5, same model/provider; the
implementer's proposed case from its #275 hand-off, widened with the
two-child call). Merged from a separate C-F043 during the 2026-09-22 suite
audit — both cases built the identical inline composition against the same
child with no run cost of their own, differing only in which estimate
fields they scored.

### C-F046 — a lossless save of an over-full waveform warns twice: the prediction and the clipped file it wrote
One inline task-only job, no GPU (~5 s). `resample_audio` on
`asset:qa-cast/ep15-song.mp3` (shared; decodes at **+0.76 dBFS**, the
resampled float peaks at +0.52 — read it with `get_gallery_metadata` first,
the case is void if the fixture has been re-kept below 0 dBFS) saved as
`audio/wav`, plus three siblings in the same workflow: the identical resample
saved as `audio/mp3`; `normalize_audio(peak_dbfs: 0)` of the same asset saved
as wav; `normalize_audio(peak_dbfs: -3)` saved as wav (control). A wav writer
hard-clips anything above 1.0, so the pre-write `audio_no_headroom` figure and
the file on disk are two different facts, and before #295 only the first was
reported — in text that called the clip a *future* mp3/AAC risk, on a file
already clipped. This is the lossless counterpart to C-F024 (which pins the
post-encode probe on a video mux) and M-F011 (the source-side warning alone).
expected: the job `succeeded`, and per step, in `get_job_events` (`kind`) and
mirrored in `job.warnings`:
- **wav resample**: **both** `audio_no_headroom` (`peak_dbfs` ≈ 0.52; text says
  *the write itself clips samples above full scale to 0 dBFS - the file just
  written is already clipped*, not a hypothetical lossy encode) **and**
  `audio_clipped` (`peak_dbfs` 0.0, *decodes at +0.00 dBFS … The write itself
  clipped it*). `get_gallery_metadata(...).media.peak_dbfs` for the wav is
  **~0.000** (within 0.01 dB of full scale), agreeing with `audio_clipped`,
  not with the 0.52 prediction.
- **mp3 resample**: `audio_no_headroom` only, with the lossy wording (*an mp3
  or AAC encode of it decodes above 0 dBFS and clips*), and the mp3's metadata
  peak is genuinely above 0 (≈ +0.65) — the one-warning-per-lossy-file
  suppression from C-F024 still holds, and its text is true because the
  overshoot survived the encode.
- **`normalize_audio` to 0 dBFS, wav**: both warnings, `peak_dbfs` 0.0 on each.
- **`normalize_audio` to −3 dBFS, wav**: no warning; metadata peak ≈ −3.00.
- A `log` event `resample_audio: 44100 → 32000 Hz, 30.02 s` with structured
  `source_sample_rate` / `target_sample_rate` / `seconds` fields precedes each
  resample's `saving` phase — the proof-of-application line from #295's
  adjacent ask, matching `gain_audio` (#294) and `mix_audio`.
A wav step that draws only `audio_no_headroom`, a metadata peak that agrees
with the prediction instead of the file, or the lossy wording on a lossless
save is the regression. No `metrics:` line — the assertion is agreement, not a
number (see C-F024).
cleanup: delete the run's output folder. `asset:qa-cast/ep15-song.mp3` lives in
the shared `common/assets` — do not sweep it.
source: tester, verified in #295 (model `opus` via provider `anthropic`, run over
MCP 2026-09-21 in `qa-v295` as job `a750a03f4ff0`: wav resample seq 12/13,
metadata 0.00027; mp3 seq 22 only, metadata +0.649; norm0 seq 30/31; norm3
silent at −2.9997). Proposed by the implementer in its hand-off; the lossy and
−3 controls are mine.

### C-F047 — a light job after a heavy one reports its own host peak, not the worker's lifetime high-water mark
Two runs back to back in the **same worker lifetime** (no server restart
between them):
1. A heavy job — anything that pushes the worker's host RSS into the tens of
   GB: C-F007's job 1 (`templates/ltx2/text-to-video`) if this run already
   did it, else `templates/prompt-weighting` (FLUX.1-schnell). Its own
   outcome does not matter for this case; it only has to load a big model.
2. Immediately after: `templates/text-to-image`, stock arguments except the
   prompt (~10 s, SD1.5, ~2 GB of host RSS).
Then `get_job_events` on job 2 and read its `memory` events (one per `phase`
boundary plus the post-run one).
expected: every `memory.info` on job 2 carries **both** `host_memory_peak_rss_mb`
and `host_memory_job_peak_rss_mb`, and they differ by an order of magnitude:
- `host_memory_peak_rss_mb` is the process-lifetime `ru_maxrss` and still
  shows job 1's tens-of-GB high-water mark on every reading (unchanged in
  meaning — `host_memory.py`'s whole-process figure).
- `host_memory_job_peak_rss_mb` on the **first** reading equals that reading's
  `host_memory_rss_mb` (the job's baseline), and on every later reading is
  the running max of job 2's own rss — a few GB at most, never job 1's
  figure. Because job 2 never exceeds the inherited high-water mark, the
  field is floored at the job's current rss rather than reporting a zero or
  negative delta.
Job 1's own first `memory` reading shows the same pattern (job-scoped ==
rss at baseline), proving the baseline is captured per job, not carried over.
A job-2 `host_memory_job_peak_rss_mb` in the tens of GB, a missing field, or a
first reading whose two job-scoped/rss figures disagree is the regression
(#272: the lifetime peak was what fed `host_memory_projection`, so a trivial
job after a heavy one drew a false host-ceiling warning). No `metrics:` line —
the assertion is the split between two fields, not a number.
cleanup: delete both generated outputs.
source: tester, verified in #272 (model `opus` via provider `anthropic`, run over
MCP 2026-09-21 in `qa-verify-272`: heavy `fb77c0f322e6` (prompt-weighting,
OOMed on the card, baseline 1890 MB both fields), light `6ad4f4781fce`:
lifetime 61811 MB on all five readings, job-scoped 1898.8 → 2098.8 MB tracking
rss exactly). Proposed by the implementer in its hand-off.

### C-F048 — a workspace-local workflow's observed history is scoped to its workspace and purged by `delete_workflow`; a catalog template's still pools
Free apart from one ~2 s run; no model, no GPU. Runs in a **scratch
workspace**, not `regression-complete`, so it can hit the exact collision
#274 reported: a same-name copy of C-F040's fixture in a workspace that has
never run it.
1. `create_workspace("regression-complete-c-f048", use=true)`.
2. `save_workflow("c-f040-qr-list", <C-F040's workflow verbatim, id
   "c-f040-qr-list", resident shape>)` — the same name `regression-complete`
   has run under C-F040 (this run or an earlier one).
3. `validate_workflow(name="c-f040-qr-list", arguments={codes: [32 entries]})`.
4. `run_workflow(workflow_path="c-f040-qr-list", acknowledged_cost=true,
   wait_seconds=55)` — 1-entry default; then the same 32-entry validation.
5. `delete_workflow("c-f040-qr-list")`, `save_workflow` the identical
   document again, and the 32-entry validation once more.
6. `get_workflow("templates/minimax/video-with-audio", variables_only=true)`
   from this same never-run workspace.
expected: (3) `valid: true`, `warnings: []`, `plan.estimate.basis:
"unknown"`, `runs: null` — none of `regression-complete`'s runs of the name
leak in; (4) `valid: true`, `warnings: []` — the fixture is task-only, so
#348's gate (`_has_seedable_step`) suppresses the host-memory projection even
with this workspace's run in history; the scoping check rests on (3) and (5)'s
`basis`/`runs`; (5) back to `warnings: []`, `basis:
"unknown"`, `cached_minutes: null` — the deleted copy's row is gone with it
(`cached_steps` may still read non-zero: the step cache is content-keyed and
only cost rows are purged; merged from smoke's S-F104 (curation 2026-09-22, harnest#2)); (6) `observed` present
with `runs` ≥ 1 and no run of the template in this workspace — a shared
catalog source still pools across workspaces (#154). The regressions: a
warning or `runs` > 0 on (3) (history keyed on name alone again — #274),
any warning on (4) (the task-only gate stopped suppressing), a warning on (5) (`delete_workflow`
stopped purging — C-F040 step 1 then fails on every second cycle), or (6)
losing `observed` (workspace scoping applied to a read-only source too).
cleanup: `delete_output(job_id=<the run>)`, then
`delete_workspace("regression-complete-c-f048", acknowledged_cost=true)`.
source: tester, verified in #274 (model `opus` via provider `anthropic`, run
over MCP 2026-09-21 in `qa-verify-274` against develop `d5e3725` +
`9bdfe6f`: (3) clean, (4) `~67354 MB … based on 1 run(s)`, (5) clean, (6)
`runs: 3`). Proposed by the implementer in its hand-off, scoped to what was run.

### C-F049 — a slice that stops just short of its source's non-silent end says so; a deliberate excerpt does not
The opposite direction to C-F016. `assemble-and-score` and
`dissolve-between-shots` slice their score to `total_frames`. H3's `17n+5`
lattice often makes an exact match unreachable, so the cut ends a moment before
the score does and the score's real ending is dropped without a word. This
happened with a 2.37 s tail that held the song's loudest second (#342). A slice
is a slice, so the warning is gated: the dropped tail must be under 10 s,
under 5 % of the slice length, and non-silent. Seconds to run, no model. Uses
the shared assets `asset:qa-cast/ep11-bed.wav` (19.67 s, 32 kHz mono,
non-silent), `asset:qa-cast/ep28-shot1-wide.mp4` and
`asset:qa-cast/ep28-shot2-close.mp4` (124 frames each @ 24 fps).
expected:
- (a) An inline workflow with three `slice_audio` steps (`result.content_type:
  "audio/wav"`) on the bed succeeds. The steps are:
  - `near_end`: `start_frame: 0, num_frames: 460, fps: 24`, which leaves a
    0.50 s tail.
  - `excerpt`: `num_frames: 24`, which leaves an 18.67 s tail.
  - `half`: `start_seconds: 0, duration_seconds: 10`, which leaves a 9.67 s
    tail: under the absolute gate, but 97 % of the slice.
- In (a), `warnings` holds **exactly one** entry, prefixed `near_end:`. It must
  say `the slice ends 0.50 s before the 19.67 s source does, dropping its tail`
  and give a real `peak … dBFS in the dropped 0.50 s`.
- (b) `run_workflow("templates/assemble-and-score", arguments={shots: [the two
  ep28 shots], score: the bed, total_frames: 248, score_start_frame: 214,
  sample_rate: 32000})` succeeds, which leaves a 0.42 s tail. Its `warnings`
  holds the same kind of entry, attributed to `soundtrack`, naming `0.42 s`
  and `19.67 s`.
- It is a **finding** if (a) `near_end` or (b) comes back `warnings: []` (the
  #342 bug), or if `excerpt` or `half` starts warning (noise on legitimate
  excerpts, the reason for the gates).
cleanup: `delete_output(job_id=…)` for both runs; the assets are shared and
durable.
source: tester, verified in #342 (model `claude-opus-5-5` via provider
`anthropic`, run over MCP 2026-09-22 in `regression-complete` against develop
`e5bfb9e`; jobs `1a06544c0760` (a) and `61ea679c3904` (b)). Proposed by the
implementer in its hand-off.

### C-F050 — pulling frames from a long film seeks instead of decoding the whole clip
`get_frame`, `get_first_frame` and `get_last_frame` used to decode every frame of
a clip to return one. In a `for_each` they did that once per member, so 12
frames from a 4089-frame film ended in a SIGKILL at 82 s (#367). Seconds to run,
no model. Uses the shared `asset:qa-cast/long-film-4089.mp4` (4089 frames).
expected:
- (a) An inline task-only workflow succeeds, with `variables.clip:
  "asset:qa-cast/long-film-4089.mp4"` and a `frames` list of 12 `{name, at}`
  entries at 0, 340, 680, … 3400 and 4088. It has two steps:
  - `last`: `get_last_frame` with `video: "variable:clip"`.
  - `frame`: `for_each: "variable:frames"`, then `get_frame` with
    `video: "variable:clip"` and `frame_index: "item:at"`.
  Both steps use `result.content_type: "image/png"`. The job writes 13 PNGs,
  `warnings: []`, and takes **well under a minute** (about 6 s when verified).
  The `variable:` form is the one the callers use, as in the `GrabFrames`
  workflow shape.
- (b) A one-step workflow runs `get_frame` on the same asset with `frame_index:
  4089`. It fails fast with `frame 4089 is past the end of a 4089-frame clip
  (frames 0-4088)`.
- It is a **finding** if (a) is killed, fails with no Python error, or runs
  for tens of seconds or more (the whole-clip decode is back), or if (b)'s
  wording changes.
metrics: `latency` of (a) in seconds, from the job's own `started_at` →
`finished_at` (`condition: 12-frames`), logged to `regression-perf/C-F050.jsonl`.
cleanup: `delete_output(job_id=…)` for both runs. The asset is shared and
durable.
source: tester, verified in #367 (model `claude-opus-5-5` via provider
`anthropic`, run over MCP 2026-09-22 against develop `e5bfb9e`; job
`13504b665cc9` (a) in `regression-complete`; (b) job `afbff51cff8d`, run
against the same film before it was kept as a shared asset). Proposed by the
implementer in its hand-off.

### C-F051 — a cost estimate quotes this box's own history, and says when it stops being able to
The server records what each workflow actually cost on this machine, and
`list_workflows` reports it as `observed_minutes` / `observed_runs`. The failure this
case exists to catch is the two halves disagreeing: `plan.estimate` answering
`basis: "unknown"` on a workflow this box has finished eleven times, so the only
figure a caller can bind into `acknowledged_cost` is the one nobody measured. That is
what was filed (#154) — the history was there and the estimate ignored it.
The second half is the one that is easy to get wrong in the other direction, and it is
the load-bearing assertion here. An observed figure is only valid for the *shape* it
was measured on. Quoting the default list's minutes for a run whose frame count or
list length was overridden would be worse than answering "unknown", because it comes
with a provenance label that makes it look measured. So the estimate has to fall back
off `observed` the moment the caller's arguments leave the recorded bucket.
expected:
- **The listing and the estimate agree.** `list_workflows(shape="shot",
  traits="identity-referenced")` → at least one entry carrying a non-null
  `observed_minutes` and `observed_runs` (at time of writing
  `templates/minimax/reference-to-video` at 8.04/11 and `templates/minimax/storyboard`
  at 11.84/7). `validate_workflow(name=<that entry>)` → `plan.estimate` with
  `basis: "observed"`, `minutes` equal to the listing's `observed_minutes` rounded to
  one decimal, `device: "cuda"`, `measured_on` naming the accelerator, and `runs`
  equal to `observed_runs`. A `basis: "unknown"` on a workflow the listing reports
  history for is the regression.
- **`runs` is present and honest.** It is `null` on every other basis and an integer
  on `observed`. `runs: 1` is a measurement of one run and has to be reported as one,
  not smoothed into a median — `templates/describe-and-regenerate` answers exactly
  that (5.7 minutes over 1 run, `low_confidence: true`, no curated `cost` block to
  blend toward). A basis of `observed` with `runs` absent or null is a finding: it is
  the field that tells a caller how much the figure is worth. A 1-2 run workflow that
  *does* carry a curated `cost` is tempered toward it rather than reported at full
  authority — that blend, not this bullet, is what `templates/minimax/music-video`
  now demonstrates; see C-F055. Pick this bullet's example fresh each time rather than
  trusting the name written here: whether a workflow has a curated `cost` and how many
  runs it has behind it both drift as the catalog and this box's history change (#327
  caught `enhance-prompt`, this bullet's example before it, having grown a curated cost
  after the case was written and landing on `tempered` instead) — re-run
  `list_workflows(shape=<any>)` looking for `cost: null` with `observed_runs` 1 or 2,
  confirm with `validate_workflow` that `low_confidence` actually appears and neither
  `tempered` nor `curated_minutes` does, and swap the name in if it no longer holds.
- **Off the recorded bucket, it falls back rather than lying.**
  `validate_workflow(name="templates/minimax/storyboard", arguments={"num_frames":
  345})` → `basis: "unknown"`, `minutes: null`, `measured_on: null` and **`runs:
  null`** (since #267 an overridden cost driver quotes neither the observed nor the
  curated figure — see C-F054). Resizing away from the driver values the history
  was bucketed on must not keep quoting 11.8 under an `observed` label. `basis:
  "observed"` on an overridden shape is the regression, and it is the dangerous one,
  because the answer still looks well-sourced.
It is a finding if any of the three fail, and specifically if `basis` and `runs`
disagree in either direction — `observed` without a count, or a count on a figure
nobody measured here.
cleanup: none — `list_workflows` and `validate_workflow` are free and write nothing.
source: moved from S-F030 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #154 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`. The implementer proposed the
first bullet; the `runs`-is-honest bullet and the fall-back-off-the-bucket bullet are
mine, the third added because quoting a measured-looking figure for an unmeasured
shape is the failure that would survive the implementer's own case. Bullet 3's
fall-back target was reworded from `catalog` to `unknown` in #304 (2026-09-21) after
#267 removed the catalog hop; C-F054 is the case that pins that behaviour. Bullet 2's
example swapped from `music-video` to `enhance-prompt` per #320 (2026-09-22): #301's
small-n blend (C-F055) pulls a 1-run estimate toward a curated `cost` figure when one
exists, so `music-video`'s own 1-run answer is now 31.9 (blended), not the 25.8 raw
observed minutes this bullet quoted. Swapped again to `templates/describe-and-regenerate`
per #327 (2026-09-22): `enhance-prompt` had grown its own curated `cost` block (5.67
min/RTX 3090) by the time #320 landed — or already had one and #320's premise was wrong
from the start, consumer-side calls can't tell which — so it answered `tempered: true`
with `curated_minutes`/`observed_minutes` instead of `low_confidence: true`, the same
blended shape C-F055 exists to demonstrate, not this bullet's. Re-verified live over MCP:
`describe-and-regenerate` has `cost: null`, `observed_runs: 1`, and
`validate_workflow(name="templates/describe-and-regenerate")` answers `basis: "observed"`,
`runs: 1`, `minutes: 5.7`, `low_confidence: true`, with no `tempered`/`curated_minutes`
field present.

### C-F052 — a partial plan estimate names what was unpriced, and an all-priced one names nothing
`validate_workflow`'s `plan.estimate` sums curated `cost` blocks across a composed workflow
(#242); when some contributor has none, `partial: true` alone cannot tell a caller whether
the gap is a trivial step or a 12-shot loop. `unpriced` (#252) names each contributor: the
parent by its own `id` when the parent's own steps carry no `cost`, each composed child by
its `workflow.path`. Free, no
model, no job — two inline `validate_workflow` calls against stock templates whose cost
state is fixed: `templates/ltx2/text-to-video` has a curated cost (2.2 min on cuda at the
time of writing; it has moved once already, so read the current figure from
`list_workflows(shape="shot")` rather than the numbers here), `templates/ltx2/extend-clip`
has none. Each inline workflow is one step, `{"name": "clip", "workflow": {"path":
<template>, "arguments": {"prompt": "variable:prompt"}}, "result": {"content_type":
"video/mp4", "subfolder": "final"}}`, with `"variables": {"prompt": "a lighthouse at
dusk"}`, except where an arm says to add a second step.
expected:
- Arms for pure-composition and mixed parents: see C-F042 (curation 2026-09-22, harnest#2).
- `id: "qa-252-priced-parent"`, `"cost": [{"device": "cuda", "name": "RTX 3090",
  "vram_gb": 24, "minutes": 0.5}]`, composing `templates/ltx2/extend-clip` → `valid: true`;
  `partial: true`; `unpriced == ["templates/ltx2/extend-clip"]` — the child alone, by path;
  `basis: "catalog"`, `minutes: 0.5`.
- `id: "qa-252-all-priced"`, the same `cost` block, composing `templates/ltx2/text-to-video`
  → `valid: true`; `partial: false`; `unpriced == []` (present and empty, not absent);
  `minutes` is the parent's 0.5 plus the child's current catalog figure.
It becomes a **finding** if `unpriced` is missing from either reply, if it
names a priced contributor or omits an unpriced one, or if `partial` disagrees with whether
`unpriced` is empty. A change in the templates' curated costs (text-to-video losing its
block, extend-clip gaining one) moves which arm names what — re-check `list_workflows
(shape="shot")` `cost` before calling that a finding.
cleanup: none — nothing is created.
source: moved from S-F075 (curation 2026-09-22, harnest#2); tester, verified in #252 on 2026-09-19 over MCP as model `opus` via provider
`anthropic` — the original three replies exactly as above. Arm 1 was rewritten and the
mixed-parent arm added in #307 (2026-09-21) after #268 made a pure-composition parent
inherit its child's history: the regression agent's run that day answered `observed`,
2.2 min, 13 runs, `partial: false`, `unpriced: []` for the one-step parent, and arms 2
and 3 as written (text-to-video's curated figure had moved from 1.8 to 2.2).

### C-F053 — `plan.estimate.cached_minutes` accounts for `cached_steps`
Before #255 `plan.estimate.minutes` was the whole-workflow observed time regardless of
`plan.cached_steps` — 14.2 min quoted for a run that would touch no GPU at all — and the
consumer had no field to correct it from. The fix adds `cached_minutes`: the cost of the
plan *after* the cached steps are subtracted, present on every estimate shape (`null` when
`minutes` is). Cheap — two SD 1.5 jobs, one of them half-served from the step cache.
0. If `qa-s076-two-step` is already saved in the workspace (an earlier run that stopped
   before its cleanup), `delete_workflow` it first. Since #312 the cost history is kept
   per `(workspace, workflow_name)` and `delete_workflow` purges it, so a leftover — or
   rows from before #312, which is what #330 was — is the only way step 2 reads
   `observed`; deleting first makes step 2 cold by construction. C-F048 pins the
   scoping and the purge.
1. `save_workflow(name="qa-s076-two-step", workflow=...)`: `"seed": 255`, no `cost` or
   `cost_drivers`, `"variables": {"prompt_a": "a red lighthouse on a cliff at dusk",
   "prompt_b": "a blue rowboat on a calm lake at dawn"}`, two steps `first` / `second` each a
   `StableDiffusionPipeline` on `stable-diffusion-v1-5/stable-diffusion-v1-5` (`torch_dtype`
   `torch.float32`, `safety_checker: null`) with `prompt: variable:prompt_a` / `prompt_b`,
   `num_inference_steps: 25`, `num_images_per_prompt: 1`; results `image/jpeg`,
   subfolders `intermediate` / `final`.
2. `validate_workflow(name="qa-s076-two-step")` (cold), then `run_workflow` it
   (`acknowledged_cost=true`), `wait_for_job`.
3. `validate_workflow(name=...)` again, nothing changed.
4. `save_workflow(name=..., patch={"variables": {"prompt_b": "a green bicycle leaning on a
   brick wall"}})` — a stored change, **not** an `arguments` override (an override on a
   workflow with no `cost_drivers` drops the estimate to `basis: "unknown"`, which is not
   what this case tests) — then `validate_workflow(name=...)`.
5. `run_workflow` that plan with the bound ack `{fingerprint, minutes, downloads: []}` from
   step 4, `wait_for_job`.
expected:
- Step 2 (cold): `cached_steps: 0`, `estimate.cached_minutes` **present** and `null`
  alongside `minutes: null`, `basis: "unknown"`. The job succeeds with both steps in the
  manifest, no `reused`.
- Step 3: `cached_steps: 2`, `basis: "observed"`, `runs: 1`, `minutes` > 0 (≈0.3), and
  `cached_minutes: 0.0` — every step cached → a zero quote.
- Step 4: `cached_steps: 1`, `basis: "observed"`, `minutes` unchanged from step 3, and
  `0 < cached_minutes < minutes` (≈0.1 vs 0.3 — the warm cost of the one step that runs).
  The `fingerprint` differs from step 3's (the definition changed).
- Step 5: `first` carries `reused: true` naming step 2's file; `second` is a new file; the
  job finishes in seconds (≈4 s), near `cached_minutes`, not `minutes`.
It becomes a **finding** if `cached_minutes` is absent from any reply, if it is `> minutes`
or non-zero with every step cached, or if it equals `minutes` with a step cached.
cleanup: `delete_workflow("qa-s076-two-step")` and `delete_output` for both runs
(`qa-s076-two-step/<run>/`); or run the whole case in a throwaway workspace and delete it.
metrics: none.
source: moved from S-F076 (curation 2026-09-22, harnest#2); tester, verified in #255 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, workspace `qa-v255` (workflow there was named `qa-v255-two-step`): jobs
`0769bf82b652` (cold, 17.4 s) / `604ba5707167` (`first` reused, 4.1 s);
`cached_minutes` 0.0 → 0.1 → 0.0 across steps 3, 4, and a re-validate after step 5.

### C-F054 — a declared `cost_driver` overridden off its measured value drops the quote to `unknown`
#267: `templates/ltx2/text-to-video` declares `num_frames` (with `width`/`height`) as a
`cost_driver`, measured at 121. Overriding it to 345 found no matching observed bucket and
then fell back to the curated `catalog` figure for 121 frames — presented as authoritative
for a clip almost three times as long. The fix extends the list-length reprice check to a
scalar driver moved off the value the figure was measured at. Free — four validate calls,
no run, works against the stored template so no fixture is needed.
1. `validate_workflow(name="templates/ltx2/text-to-video")` — no arguments.
2. Same, `arguments={"num_frames": 345}`.
3. Same, `arguments={"width": 1280, "height": 704}`.
4. Same, `arguments={"num_frames": 121, "prompt": "a quiet lake at dawn"}` — the driver
   set explicitly to its measured value, plus a non-driver override.
expected:
- Step 1: `plan.estimate.basis` is `"observed"` (or `"catalog"` on a box that has never
  run it) with `minutes` > 0 — the template prices at its defaults.
- Steps 2 and 3: **either** `basis: "unknown"`, `minutes: null`, `runs: null`,
  `measured_on: null` — neither the catalog nor the observed figure is quoted for a
  driver value it was not measured at — **or**, once this box has accumulated enough
  real runs at that exact overridden value, `basis: "observed"` with
  `low_confidence: true` and `minutes` specific to *that* value's own bucket (#301/#319's
  small-n tempering, landed 2026-09-21, after this case was written). Either way
  `valid: true` with the overridden names in `checked_arguments`. What is never
  acceptable is `basis: "catalog"`, or an `observed`/`catalog` `minutes` copied from the
  *unmatched* measured bucket (step 1/4's own figure, priced for the driver's measured
  value) presented as if it priced the overridden one — that silent-wrong-figure
  behavior is #267's original bug and is the actual regression this case guards against,
  distinct from a correctly-bucketed low-confidence answer.
- Step 4: identical `estimate` to step 1 — an override that does not move a driver off
  its measured value keeps the quote.
It becomes a **finding** if step 2 or 3 answers `basis: "catalog"`, or answers
`basis: "observed"`/`"catalog"` with `minutes` matching step 1/4's unmatched
measured-bucket figure rather than one specific to the overridden value, or if step 4
drops to `unknown`.
cleanup: none — nothing is created.
metrics: none.
source: moved from S-F078 (curation 2026-09-22, harnest#2); tester, verified in #267 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: steps 1 and 4 answered `observed`, 2.5 min, 12 runs on the RTX 3090; steps 2
and 3 answered `unknown` with `minutes: null`. Step 2's expectation widened to admit
`observed`+`low_confidence` per #331 (2026-09-22, model `sonnet` via provider
`anthropic`) — #301/#319's small-n bucketing now legitimately answers `observed` for a
driver value with enough of its own runs, same pattern already seen for C-F051.

### C-F055 — a small-n observed estimate is tempered toward the curated figure, or flagged when there is none, and says so
Before #301 a figure measured once on this box was quoted by `plan.estimate` with the
same authority as one measured fourteen times (and ran ~3x pessimistic in the case that
was filed). The approved shape: below `runs: 3`, if the workflow carries a curated
`cost` block, `minutes` is blended linearly toward it (weight `runs/3` on the observed
figure); if there is no curated figure, `minutes` is left alone and `low_confidence:
true` is added beside `runs`. At or above 3 runs nothing changes. #319 added the label
half: before that fix a 1-run estimate blended toward the curated figure came back as
`basis: "observed", minutes: 31.9` while `list_workflows` reported
`observed_minutes: 25.75` for the same workflow — two tools disagreeing on "observed"
with nothing in the estimate to reconcile them. The additive shape: when the blend
fires, `plan.estimate` carries `tempered: true`, `observed_minutes` (the raw point
figure, the same number the listing reports) and `curated_minutes` (what it blended
toward) beside `runs`; `basis` and `minutes` are unchanged. Free — three
`validate_workflow` calls and one listing, nothing written. Read the listing first: the
run counts drift as the box is used, so pick the entries by their `observed_runs`, not by
the names below, and choose one entry per row.
1. `list_workflows(shape="shot")` and `list_workflows(shape="sequence")` — note each
   entry's `cost`, `observed_minutes`, `observed_runs`.
2. `validate_workflow(name=<entry with observed_runs 1 or 2 AND a non-null cost>)`.
3. `validate_workflow(name=<entry with observed_runs 1 or 2 AND cost: null>)`.
4. `validate_workflow(name=<entry with observed_runs >= 3>)`.
expected:
- Step 2 (blend): `basis: "observed"`, `runs` equal to the listing's count, **no**
  `low_confidence` key, and `minutes` strictly between the listing's `observed_minutes`
  and the curated `cost[].minutes`, within 0.1 of
  `observed * runs/3 + curated * (1 - runs/3)`. Equal to the raw observed figure is the
  regression. Also `tempered: true`, `observed_minutes` equal to the listing's
  `observed_minutes` (to one decimal), and `curated_minutes` equal to the listing's
  `cost[].minutes` for this device. Missing `tempered`, or a `tempered` that comes
  without both source figures, is the regression.
- Step 3 (flag): `basis: "observed"`, `minutes` equal to the listing's `observed_minutes`
  rounded to one decimal (unmodified), `runs` as listed, and `low_confidence: true`.
  Absent flag, or a `minutes` that moved with nothing to move toward, is the regression.
  **None** of `tempered`, `observed_minutes`, `curated_minutes` — the flag path and the
  blend path are exclusive.
- Step 4 (threshold): `minutes` equal to the listing's `observed_minutes` rounded to one
  decimal, no `low_confidence` key — with or without a curated `cost`. A blend or a flag
  at 3+ runs is the regression. **None** of `tempered`, `observed_minutes`,
  `curated_minutes`, `low_confidence`.
If no entry fits step 2 (every low-n workflow lacks a `cost`, or the low-n ones have all
been run past 3), skip that step and say so — do not manufacture one; it is not a finding.
cleanup: none.
metrics: none.
source: moved from S-F100 (curation 2026-09-22, harnest#2); tester, verified in #301 (implementer proposed both halves in its hand-off
comment; added after running it on 2026-09-21 over MCP as model `opus` via provider
`anthropic` against `develop @ d5e3725`: `templates/minimax/music-video` curated 35 /
observed 25.75 / 1 run → 31.9, no flag; `templates/minimax/enhance-prompt` no cost /
5.67 / 1 run → 5.7 with `low_confidence: true`; `templates/minimax/video-with-audio`
6.6 / 2 runs → flagged; `templates/ltx2/two-stage` 8.2 / 3.12 / 3 runs → 3.1, no flag).
The `tempered`/`observed_minutes`/`curated_minutes` labels were merged in from a
separate S-F108 during the 2026-09-22 suite audit (both cases ran the identical 3-arm
setup against the #301 tempering feature, free and read-only): verified in #319 on
2026-09-22 over MCP as model `opus` via provider `anthropic` against `develop @ 7e1a1a5`
(implementer proposed the case in its hand-off comment; `templates/minimax/music-video`
1 run / curated 35 → `tempered: true, observed_minutes: 25.8, curated_minutes: 35.0,
minutes: 31.9`; `templates/minimax/dialogue-short` 5 runs → no marker fields;
`templates/step-caching` 2 runs, no cost → `low_confidence: true`, no marker fields).

### C-F056 — a priced parent's composed estimate uses the child's catalog figure, and says so
#315: C-F052 arm 4's `minutes` was the parent's `cost` plus the child's *observed* median
(0.5 + 2.11 → 2.6) while `basis` read `"catalog"` and `measured_on` the short catalog
device string — the figure and its label disagreed. Since the fix, a child's observed
history is only folded in when the parent has no priced figure of its own (the only case
where the total can honestly be `basis: "observed"`); a priced parent prices its children
from their own `cost` block. C-F052 pins the arithmetic; this pins the label. Free, no
model, no job — three inline `validate_workflow` calls, each one step `{"name": "clip",
"workflow": {"path": <template>, "arguments": {"prompt": "variable:prompt"}}, "result":
{"content_type": "video/mp4", "subfolder": "final"}}` with `"variables": {"prompt": "a
lighthouse at dusk"}`. Read the children's current `cost`/`observed_minutes` from
`list_workflows(shape="shot")` first; the arithmetic below uses that, not the numbers here.
expected:
- `"cost": [{"device": "cuda", "name": "RTX 3090", "vram_gb": 24, "minutes": 0.5}]`
  composing `templates/ltx2/text-to-video` (curated cost, run on this box) → `basis:
  "catalog"`, `measured_on: "RTX 3090"` (the catalog block's `name`, not the observed
  device string), `runs: null`, `minutes == 0.5 + <child's catalog minutes>` to one decimal
  — **not** `0.5 + observed_minutes`, when the two differ.
- The same parent `cost` composing `templates/ltx2/two-stage` (curated cost, also observed
  here) → the same shape: `basis: "catalog"`, `minutes == 0.5 + <its catalog minutes>`.
- **No** parent `cost`, composing `templates/ltx2/text-to-video` → `basis: "observed"`,
  `runs` = the child's `observed_runs`, `measured_on` the long observed device name (e.g.
  `"NVIDIA GeForce RTX 3090"`), `minutes ≈ observed_minutes` — the pure-composition arm
  still inherits observed data (#268), so the fix did not over-correct.
It is a **finding** if any priced-parent arm's `minutes` equals `0.5 + observed_minutes`
rather than `0.5 + cost.minutes` (when those differ), or if `basis` and `measured_on` are
not the catalog forms alongside a catalog-summed figure. If a box has never run the child,
arm 1 and arm 3 both legitimately read `catalog` — the arms only discriminate when
`observed_minutes` is present and differs from `cost.minutes`.
cleanup: none — nothing is created.
metrics: none.
source: moved from S-F105 (curation 2026-09-22, harnest#2); tester, verified in #315 on 2026-09-22 over MCP as model `opus` via provider
`anthropic` against `develop @ d5e3725`: text-to-video catalog 1.8 / observed 2.11 (14
runs) → priced parent `2.3`/`catalog`/`"RTX 3090"`; two-stage catalog 8.2 / observed 3.12
→ `8.7`/`catalog`; no-cost parent → `2.1`/`observed`/`runs: 14`.

### C-F057 — `dissolve_videos` resamples shots at different sample rates instead of failing
#287: `dissolve_videos` died at the first step of `templates/dissolve-between-shots` with
`needs one sample rate, got [32000, 44100]` — the exact constraint #108 had already
removed from `concat_videos`. Shots from different families routinely carry different
rates, so a sequence template that refuses the mix is unusable on a real cast. Now the
task picks the highest rate among the inputs (or the caller's `sample_rate`), resamples
the rest, and says so as a warning. Cheap: one ~5 s task-only run.
1. `run_workflow(inline_workflow={"id": "regression-dissolve-rates", "steps": [{"name":
   "edit", "task": {"command": "dissolve_videos", "arguments": {"videos":
   ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep13-episode.mp4"],
   "dissolve_frames": 12, "fps": 24}}, "result": {"content_type": "video/mp4", "fps":
   24, "subfolder": "final"}}]}, acknowledged_cost=true)`, then `wait_for_job`. The 32 kHz
   shot is deliberately first, so "first video's rate" and "highest rate" disagree.
2. `get_gallery_metadata` on the `edit` file the manifest names.
expected:
- The job is `succeeded`, not `failed`, and `warnings` holds exactly one entry from
  `edit: dissolve_videos:` that names both input rates (`video 1: 32000 Hz, video 2:
  44100 Hz`), says it is resampling them all to **44100 Hz**, and names the two remedies
  (`sample_rate` to pin a target, `resample_audio` ahead of the step).
- Step 2 reports `sample_rate: 44100`, `channels: 2`, `frame_count: 394` (124 + 282 − 12),
  `fps: 24.0`.
- `get_task("dissolve_videos")` lists a `sample_rate` parameter, and its `videos`
  description does not say the rates must match.
It is a **finding** if the job fails with a "needs one sample rate" (or any) error, if it
succeeds with no `sample_rate_mismatch`-style warning, if the target is 32000 (first-listed
rather than highest, with no pin given), or if the output's `sample_rate` disagrees with the
warning's target.
cleanup: `delete_output` on the `regression-dissolve-rates/<run>` directory.
metrics: none.
source: moved from S-F086 (curation 2026-09-22, harnest#2); tester, verified in #287 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `47f27a3d566e` succeeded in 5 s with the warning quoted above; output read
back as 394 frames, 44100 Hz stereo. The same session confirmed `sample_rate: 32000` pins
the target (job `370442220fe7`) and that two 32 kHz shots draw no warning.

### C-F058 — `loop_audio` shortening a bed to `target_frames` is sample-faithful, not faded
`loop_audio` is documented for making a bed *longer*; the other direction — a bed longer
than the cut, cut down to `target_frames` — has no doc and no case, and a hidden fade or
crossfade at the truncation point would read as a dead last second under a `pair_audio`
(the ep33 film's last bin sat at −60 dBFS rms and looked exactly like that until probed).
Seeded, seconds, one job:
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id":
   "regression-loop-truncate", "seed": 1, "steps": [
   {"name": "bed_tail_raw", "task": {"command": "slice_audio", "arguments":
   {"audio": "asset:qa-cast/ep11-bed.wav", "start_seconds": 9.0, "duration_seconds": 0.334}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "tail-raw"}},
   {"name": "bed_loop", "task": {"command": "loop_audio", "arguments":
   {"audio": "asset:qa-cast/ep11-bed.wav", "target_frames": 224, "fps": 24}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "bed-loop"}},
   {"name": "bed_tail_loop", "task": {"command": "slice_audio", "arguments":
   {"audio": "previous_result:bed_loop", "start_seconds": 9.0, "duration_seconds": 0.334}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "tail-loop"}}]},
   acknowledged_cost=<bound from validate>)`, `wait_for_job`.
2. `get_gallery_metadata` on `bed-loop-0.0.wav`, `tail-raw-0.0.wav` and `tail-loop-0.0.wav`.
expected:
- `succeeded`; `bed-loop` is `duration_seconds` 9.33 ± 0.01 at `sample_rate` 32000, mono
  (224 f at 24 fps out of a 19.67 s source — nothing looped, so no crossfade applies).
- `tail-raw` and `tail-loop` `mean_dbfs` agree within 0.1 dB and `peak_dbfs` within
  0.5 dB: the last third of a second of the truncated bed is the source's own material at
  its own level, not a fade-out.
- `job.warnings` may carry `audio_near_silent` on any of the three (the bed is a −50 dBFS
  room tone by design); nothing else.
It is a **finding** if `bed-loop` is any other length or rate, if the two tails differ by
more than the tolerances (a fade or crossfade applied where no loop point exists), or if
the run fails.
cleanup: `delete_output` the run folder.
metrics: none.
source: moved from S-F091 (curation 2026-09-22, harnest#2); tester, found while running TESTER_TASK.agent.md (ep33, `qa-ep33`, job
`dfd9cc5a3244`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`: tails
−60.48 vs −60.50 dBFS mean, peak −38.01 on both, `bed-loop` 9.333 s / 32 kHz / mono,
peak equal to the source asset's (−28.89).

### C-F059 — `mix_audio` gains are linear multipliers applied as given: no hidden normalization, no sum-scaling
`mix_audio` is the one level control in the engine that is not in dB (`gains` are plain
multipliers), and the only way a consumer can tell a mixer that quietly peak-normalizes or
divides by the track count from one that does what it was told is to measure. A bed laid
under dialogue at 0.25 that comes back normalized to −1 dBFS, or a unity solo that lands
6 dB down because the mixer averaged two slots, would be a silent level bug in every
score-under-dialogue chain. Seeded, seconds, one job, one asset:
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id":
   "regression-mix-linear", "seed": 1, "steps": [
   {"name": "solo_unity", "task": {"command": "mix_audio", "arguments":
   {"audios": ["asset:qa-cast/ep33-episode.mp4"], "gains": [1.0]}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "solo-unity"}},
   {"name": "solo_half", "task": {"command": "mix_audio", "arguments":
   {"audios": ["asset:qa-cast/ep33-episode.mp4"], "gains": [0.5]}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "solo-half"}},
   {"name": "bed", "task": {"command": "loop_audio", "arguments":
   {"audio": "asset:qa-cast/ep11-bed.wav", "target_frames": 224, "fps": 24}},
   "result": {"content_type": "audio/wav", "save": false}},
   {"name": "bed_x12", "task": {"command": "mix_audio", "arguments":
   {"audios": ["previous_result:bed"], "gains": [12.0]}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "bed-x12"}},
   {"name": "two_slots_zero_bed", "task": {"command": "mix_audio", "arguments":
   {"audios": ["asset:qa-cast/ep33-episode.mp4", "previous_result:bed"], "gains": [1.0, 0.0]}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "two-slots"}}]},
   acknowledged_cost=<bound from validate>)`, `wait_for_job`.
2. `get_gallery_metadata` on `asset:qa-cast/ep33-episode.mp4`, `asset:qa-cast/ep11-bed.wav`
   and the four outputs.
expected:
- `succeeded`; every output is 9.33 ± 0.01 s at `sample_rate` 32000.
- `solo-unity` `peak_dbfs` equals the ep33 asset's decoded peak within 0.1 dB (about
  −1.0) — a single track at unity is passed through, not normalized.
- `solo-half` peak is `solo-unity` peak − 6.02 ± 0.1 dB, and its `mean_dbfs` is 6.02 ± 0.1
  below `solo-unity`'s.
- `bed-x12` peak is the ep11-bed asset's peak + 21.58 ± 0.1 dB (about −7.3 from −28.9) —
  a gain above 1 is applied as given, not clamped.
- `two-slots` peak and mean equal `solo-unity`'s within 0.05 dB — a second slot at gain 0
  adds nothing and the sum is not divided by the slot count.
- `job.warnings` may carry `audio_near_silent` for the bed (a −50 dBFS room tone by
  design); nothing else. (Once #292 lands, `bed_x12` may draw a "gain above 1 is a
  multiplier, not dB" warning — that is not a finding.)
It is a **finding** if any peak or mean lands outside the tolerances (a normalizing or
averaging mixer), if a gain above 1 is clamped, or if the run fails.
cleanup: `delete_output` the run folder.
metrics: none.
source: moved from S-F093 (curation 2026-09-22, harnest#2); tester, found while running TESTER_TASK.agent.md (ep34, `qa-ep34`, job
`a4433db88e90`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`:
`solo-unity` −1.012 / −19.81, `solo-half` −7.033 / −25.83, `bed-x12` −7.302 from an
asset peak of −28.886, `two-slots` identical to `solo-unity` to the third decimal;
every output 9.333 s / 32 kHz.

### C-F060 — a negative `mix_audio` gain is refused by the free pre-flight, and a dB-shaped gain (3 or above) is warned about as a not-dB value
`mix_audio.gains` is the engine's one level control that is a plain multiplier rather than
dB, so `-12` typed by habit is a phase-inverted 12x boost — it used to validate, run and
succeed with nothing in `warnings` or the events (#292). The domain check is the same
element-wise `non_negative` mechanism C-F076 exercises on scalars, reached through a list;
if it regresses, a bad bed level is a silent success again. Free except step 3, which is a
few seconds of CPU on one asset:
1. `get_task("mix_audio")`.
2. `validate_workflow(workspace=<suite workspace>, workflow={"id": "regression-mix-neg-gain",
   "variables": {"bed_gain": 12}, "steps": [
   {"name": "bed", "task": {"command": "loop_audio", "arguments":
   {"audio": "asset:qa-cast/ep11-bed.wav", "target_frames": 224, "fps": 24}},
   "result": {"content_type": "audio/wav", "save": false}},
   {"name": "mix", "task": {"command": "mix_audio", "arguments":
   {"audios": ["asset:qa-cast/ep33-episode.mp4", "previous_result:bed"], "gains": [0, "variable:bed_gain"]}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "mix-neg"}}]},
   arguments={"bed_gain": -12})`.
3. The same workflow with `gains: [1.0, "variable:bed_gain"]` and no `arguments` (so the bed
   gain is the declared 12): `validate_workflow`, then `run_workflow` with the bound
   acknowledgement, `wait_for_job`, `get_job_events`.
expected:
- Step 1: the `gains` parameter carries `"domain": "non_negative"` (and `sample_rate`
  still carries `positive`).
- Step 2: `valid: false`, exactly one error, at `steps[1].task.arguments.gains[1]`, whose
  message names `mix_audio`, `gains[1]`, "zero or above" and `got -12` — the value that
  arrived through `variable:` + `arguments` is what was checked, and the `0` in
  `gains[0]` was accepted (a zero gain is a valid mute, not a domain violation).
- Step 3: validates (`valid: true`), `succeeded`. `job.warnings` carries a `mix:` entry
  saying the gain(s) `[12]` are a multiplier, not decibels; the events for the `mix` step
  carry, in order, a `warning` with `kind: mix_audio_gain_not_db` and `gains: [1, 12]`,
  then a `log` whose `message` is `mix_audio: 2 tracks, gains [1.0, 12.0]` with a `gains`
  field, both before the `saving` phase. An `audio_no_headroom` warning on the output and
  `audio_near_silent` on the bed are expected side effects of a 12x bed, not findings.
It is a **finding** if step 2 validates, or reports the error at any other path, or if
step 3 runs without the `mix_audio_gain_not_db` warning or the applied-gains `log`.
cleanup: `delete_output` the run folder from step 3.
metrics: none.
source: moved from S-F094 (curation 2026-09-22, harnest#2); tester, verified in #292 on 2026-09-21 over MCP as model `opus` via provider
`anthropic` (job `b3491e7c8b92` in `qa-ep34`; 3.7 s end to end). Title reworded per #321
on 2026-09-22: #306 raised `mix_audio_gain_not_db`'s threshold from `> 1.0` to `>= 3.0`
(`GAIN_LOOKS_LIKE_DB_ABOVE`, commit `05cfbfd`), so a gain of 1.8 no longer warns; this
case's own gain of 12 is unaffected. The threshold's other side (1.8 silent, 12 warns) is
pinned by C-F065.

### C-F062 — `mix_audio` and `crossfade_audio` resample tracks at different sample rates instead of failing
#293: the two pure-audio joiners still died with `needs one sample rate, got [32000, 44100]`
after #108 (`concat_videos`) and #287 (`dissolve_videos`, C-F057) had removed that constraint
from the video joiners. A bed and a song from different families routinely disagree on rate,
so a score pass that refuses the mix is unusable on a real cast. Now, with `sample_rate`
unset, each picks the highest rate among its inputs, resamples the rest up to it, and says so
as a warning; a pinned `sample_rate` still relabels (#180) and the docstring says so. Cheap:
one ~4 s task-only run, two shared assets.
1. `validate_workflow(workspace=<suite workspace>, workflow={"id": "regression-audio-rates",
   "seed": 1, "steps": [
   {"name": "mix", "task": {"command": "mix_audio", "arguments": {"audios":
   ["asset:qa-cast/ep11-bed.wav", "asset:qa-cast/ep15-song.mp3"], "gains": [1.0, 0.5]}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "mix"}},
   {"name": "xfade", "task": {"command": "crossfade_audio", "arguments": {"audios":
   ["asset:qa-cast/ep11-bed.wav", "asset:qa-cast/ep15-song.mp3"], "crossfade_ms": 500}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "xfade"}}]})`,
   then `run_workflow` with the bound acknowledgement, then `wait_for_job`. The 32 kHz bed is
   deliberately first, so "first track's rate" and "highest rate" disagree.
2. `get_gallery_metadata` on the `mix` and `xfade` files the manifest names.
3. `get_task("mix_audio")` and `get_task("crossfade_audio")`.
expected:
- Validate is `valid: true` (no pre-flight rate check exists — declined in #287/#293).
- The job is `succeeded`, not `failed`. `warnings` holds one `mix: mix_audio:` entry and one
  `xfade: crossfade_audio:` entry, each saying the tracks carry different sample rates,
  naming both tracks with their rates (`ep11-bed.wav: 32000 Hz`, `ep15-song.mp3: 44100 Hz`),
  saying it is resampling them all to **44100 Hz**, and naming both remedies (`sample_rate`
  to pin a target, `resample_audio` ahead of the step). Neither step emits the #180
  "relabeled … not resampled" warning. (An `xfade:` no-headroom warning is expected too —
  the song decodes at +0.76 dBFS — and is not part of this case.)
- Step 2: `mix` is `sample_rate: 44100`, `duration_seconds` 30.02 ± 0.05 (the longer input,
  at its native length — a relabel would stretch it to ~41.4 s); `xfade` is `sample_rate:
  44100`, `duration_seconds` 49.19 ± 0.05 (19.667 + 30.023 − 0.5).
- Step 3: both `sample_rate` descriptions say that, left unset, the highest rate is used and
  the rest resampled, and that a given value *relabels* rather than resamples.
It is a **finding** if either step fails with "needs one sample rate" (or any) error, if a
step succeeds with no mismatch warning, if the target is 32000 (first-listed rather than
highest, with no pin given), if either output's rate or duration disagrees with the above, or
if a `get_task` description still calls a given `sample_rate` merely the one that "wins".
cleanup: `delete_output` on the `regression-audio-rates/<run>` directory.
metrics: none.
source: moved from S-F096 (curation 2026-09-22, harnest#2); tester, verified in #293 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `6e4f03a463de` (both orders of the pair, plus the pinned-32k control)
succeeded in 3.7 s with the warnings quoted above; mixes read back 44100 Hz / 30.023 s, the
crossfade 44100 Hz / 49.19 s, the pinned-32k control 32000 Hz / 41.376 s with the #180
warning. Job `9d5461d74dea` confirmed a three-track crossfade and a pin equal to the higher
rate behave the same way.

### C-F063 — `gain_audio` logs the dB and the resolved region it applied, in seconds and in samples, for both the seconds and the frames form
#294: `gain_audio` applied its gain silently — nothing between `phase: task / gain_audio` and
`phase: saving` — so a consumer that cannot listen could only prove a duck landed by
measuring the envelope (C-F080), and could not prove it at all where the region fell on a
quiet stretch. Now the step emits a log event in the shape #292 gave `mix_audio`, and the
frame form shows its frame→second→sample conversion in that same event, so a wrong `fps`
or rate is visible without a measurement. Cheap: one ~1 s task-only run, one shared asset,
no saved file needed for the second step.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "regression-gain-log",
   "seed": 1, "steps": [
   {"name": "duck_seconds", "task": {"command": "gain_audio", "arguments":
   {"audio": "asset:qa-cast/ep31-shot1-return.mp4", "gain_db": -12, "start_seconds": 2.0,
   "duration_seconds": 1.0}},
   "result": {"content_type": "audio/wav", "subfolder": "final", "file_base_name": "gain-log-s"}},
   {"name": "duck_frames", "task": {"command": "gain_audio", "arguments":
   {"audio": "asset:qa-cast/ep31-shot1-return.mp4", "gain_db": 3.5, "start_frame": 24,
   "num_frames": 12, "fps": 24}},
   "result": {"content_type": "audio/wav", "subfolder": "final", "file_base_name": "gain-log-f"}}]},
   acknowledged_cost=<bound from validate>)`, `wait_for_job`, then `get_job_events`.
expected:
- `succeeded`. In the events, each `phase: task / gain_audio` is followed, before that
  step's `phase: saving`, by one `event: "log"` with `command: "gain_audio"` and structured
  fields `gain_db`, `start_seconds`, `duration_seconds`, `start_sample`, `end_sample`,
  `sample_rate`.
- `duck_seconds`: message `gain_audio: -12.0 dB over 2.000-3.000 s (samples 64000-96000 @
  32000 Hz)`; `gain_db: -12`, `start_seconds: 2.0`, `duration_seconds: 1.0`,
  `start_sample: 64000`, `end_sample: 96000`, `sample_rate: 32000`.
- `duck_frames`: message `gain_audio: 3.5 dB over 1.000-1.500 s (samples 32000-48000 @
  32000 Hz)`; `start_seconds: 1.0`, `duration_seconds: 0.5` (24 f and 12 f at 24 fps),
  `start_sample: 32000`, `end_sample: 48000` — the frame form reports the region it
  resolved to in seconds and samples, not the frame numbers it was given.
It is a **finding** if either step has no `log` event between its `task` phase and its
`saving` phase, if the event lacks any of the six structured fields, if the samples disagree
with `start_seconds × sample_rate` / `(start + duration) × sample_rate`, or if the frames
step's resolved seconds are not 1.0 / 0.5.
cleanup: `delete_output` on the `regression-gain-log/<run>` directory.
metrics: none.
source: moved from S-F097 (curation 2026-09-22, harnest#2); tester, verified in #294 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `3cdc5f90dcd7` (seconds form, seq 11 between `task` seq 10 and `saving`
seq 12) and job `94a6677af7a5` (frames form, seq 12) produced exactly the two messages and
field sets above; each run under 1 s.

### C-F064 — `resample_audio` converts: the written track carries the target rate at the source's duration, and a frame-form slice of it lands on the target rate's sample grid
`resample_audio` is the remedy every mixed-rate warning names (#108, #287, #293) and the only
task whose purpose is to convert rather than relabel — yet the smoke suite only ever exercised
its refusals (C-F076 parts 1–4). A relabel bug would still "succeed": a 44.1 kHz track
stamped 32 kHz plays 37.8 % slow (#180's exact failure, in the one task that must never do
it). Cheap: one ~1 s task-only run, one shared asset.
1. `get_gallery_metadata(name="asset:qa-cast/ep15-song.mp3")` — the source: 44100 Hz,
   2 ch, `duration_seconds` 30.02 ± 0.05.
2. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "regression-resample",
   "seed": 1, "steps": [
   {"name": "resample", "task": {"command": "resample_audio", "arguments":
   {"audio": "asset:qa-cast/ep15-song.mp3", "target_sample_rate": 32000}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate", "file_base_name": "song32k"}},
   {"name": "slice", "task": {"command": "slice_audio", "arguments":
   {"audio": "previous_result:resample", "start_frame": 0, "num_frames": 224, "fps": 24}},
   "result": {"content_type": "audio/wav", "subfolder": "final", "file_base_name": "song32k-224f"}}]},
   acknowledged_cost=<bound from validate>)`, `wait_for_job`, then `get_gallery_metadata`
   on both files the manifest names.
expected:
- `succeeded`. `resample`: `sample_rate: 32000`, `channels: 2`, `duration_seconds` equal to
  the source's within 0.05 s (30.02 — a relabel reads ~41.38 s). `slice`: `sample_rate:
  32000`, `duration_seconds` 9.333 ± 0.005 (224 f / 24 fps, resolved on the *converted*
  track's rate — 298 667 samples at 32 kHz, not 224/24 of a 44.1 kHz sample count).
- No `#180` "relabeled … not resampled" warning on either step, and no sample-rate mismatch
  warning (there is one track). An `audio_no_headroom` warning on each written wav *is*
  expected — the song decodes above full scale — and is not part of this case (its wording
  and the missing `audio_clipped` are #295).
It is a **finding** if the resampled file's rate is not 32000, if its duration moves by more
than 0.05 s from the source's, if the slice is not 9.333 s at 32000 Hz, or if either step
warns that it relabeled.
cleanup: `delete_output` on the `regression-resample/<run>` directory.
metrics: none.
source: moved from S-F098 (curation 2026-09-22, harnest#2); tester, found while running TESTER_TASK.agent.md (ep36, `qa-ep36`, job
`d37790d23c42`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`: the
resampled wav read back 32000 Hz / 2 ch / 30.023406 s from a 30.02 s 44.1 kHz source, the
224-frame slice 9.333344 s / 32000 Hz; whole chain 0.4 s. Two `gain_audio` frame-form
ducks chained off the slice by `previous_result:` each landed exactly −9.00 dB in their
bins (C-F080/C-F063 cover that arithmetic; this case is the conversion in front of it).

### C-F065 — `mix_audio`'s not-dB gain warning has a threshold: a modest multiplier like the templates' stock `world_gain: 1.8` is silent, a dB-shaped 12 still warns
The `mix_audio_gain_not_db` heuristic C-F060 pins fired at any gain above 1.0 when it
shipped, which meant both sequence templates tripped it on their own `world_gain: 1.8`
default and `warnings: []` was unreachable for any bare template run (#306). The threshold
is now 3.0: a value under it is a plausible multiplier, a value at or above it is treated as
a dB figure typed into the wrong unit. If the threshold drifts down again, C-F067/C-F071/C-F020's
`warnings: []` expectations all break at once with a warning no caller can act on; if it
drifts up or the check is dropped, a real `12` becomes a silent 12x boost. Two short CPU
runs on the shared cast assets:
1. `run_workflow(workflow_path="templates/assemble-and-score", workspace=<suite workspace>,
   arguments={"shots": ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"],
   "score": "asset:qa-cast/ep20-score.wav", "match_levels": "rms", "match_levels_dbfs": -24,
   "total_frames": 248}, acknowledged_cost=<bound>, wait_seconds=55)` — `world_gain` left at
   the template's default (`get_workflow(variables_only=true)` shows it as 1.8).
2. The same call with `world_gain: 12` added to `arguments`.
expected:
- Step 1: `succeeded`, `warnings: []` — nothing from `mixed:`, and no
  `mix_audio_gain_not_db` event.
- Step 2: `succeeded`, and `warnings` carries exactly one `mixed: mix_audio: gain(s) [12.0]
  are a multiplier, not decibels …` entry (the `edit:` level-spread warning is also present
  only if `match_levels` was dropped; with it passed, the gain warning is the only entry).
It is a **finding** if step 1 carries any `mix_audio_gain_not_db` warning, or if step 2
does not.
cleanup: `delete_output(job_id=<id>)` for both runs.
metrics: none.
source: moved from S-F102 (curation 2026-09-22, harnest#2); tester, verified in #306 (implementer proposed the case in its hand-off comment;
added after running it on 2026-09-22 over MCP as model `opus` via provider `anthropic`
against `develop @ d5e3725`, workspace `regression-smoke`: job `d80bd33149e6` at the stock
1.8 → `warnings: []`; job `ae9e4d6d57ab` at `world_gain: 12` → the gain warning present,
alongside the `edit:` level-spread warning because that run omitted `match_levels`;
`templates/dissolve-between-shots` job `e0f581c0c0b1` at its stock 1.8 was likewise free of
the gain warning).

### C-F066 — `slice_audio` of a source that arrived near-silent does not warn `audio_near_silent`; a slice that *made* a normal source near-silent still does
The save-time near-silent check C-F085 pins (#261) fired on every slice of a room-tone bed
(#309) — exactly the material the tasks guide's `loop_audio` section tells a caller to cut
out and lay under a scene, quiet by design. The rule is now: `slice_audio` measures its
source's own level before cutting, and a slice whose source was *already* under the
−40 dBFS line is not a defect the slice introduced, so it is not warned about; a slice of a
normal-level source that comes out near-silent (here, because the past-end pad dwarfs the
material) still is. If the suppression goes, C-F016's `warnings: []` arms break and every
scored cut carries a warning nobody can act on; if it widens to all of `slice_audio`, a
genuinely attenuated slice goes unremarked. Two CPU-only runs, seconds each, no model:
1. `run_workflow(workspace=<suite workspace>, acknowledged_cost=true, wait_seconds=55,
   inline_workflow={"id": "s_f103_quiet", "variables": {}, "steps": [
     {"name": "past_end", "task": {"command": "slice_audio", "arguments":
       {"audio": "asset:uploads/qa-cast/room-bed.wav", "num_frames": 372, "fps": 24}},
      "result": {"content_type": "audio/wav", "file_base_name": "past_end"}},
     {"name": "inside", "task": {"command": "slice_audio", "arguments":
       {"audio": "asset:uploads/qa-cast/room-bed.wav", "num_frames": 48, "fps": 24}},
      "result": {"content_type": "audio/wav", "file_base_name": "inside"}}]})`
2. `run_workflow(workspace=<suite workspace>, acknowledged_cost=true, wait_seconds=55,
   inline_workflow={"id": "s_f103_loud", "variables": {}, "steps": [
     {"name": "voice_inside", "task": {"command": "slice_audio", "arguments":
       {"audio": "asset:qa-cast/hal-voice.wav", "num_frames": 48, "fps": 24}},
      "result": {"content_type": "audio/wav", "file_base_name": "voice_inside"}},
     {"name": "voice_diluted", "task": {"command": "slice_audio", "arguments":
       {"audio": "asset:qa-cast/hal-voice.wav", "start_seconds": 0, "duration_seconds": 1200}},
      "result": {"content_type": "audio/wav", "file_base_name": "voice_diluted"}}]})`
   (6.48 s of speech padded to 1200 s reads about −44 dBFS mean — under the line.)
The `result` blocks matter: a step nothing reads and that saves no file does not run
(S-F027), and the check is at save time.
expected:
- Run 1: `succeeded`; `warnings` holds **exactly two** entries, both the C-F016 past-end
  pair (since dw 39a97862 a job records #402's pre-flight warning too): the pre-flight
  `steps[0].task.arguments.audio: slice_audio will run … past the end of …` and the run-time
  `past_end: slice_audio: the requested slice runs … past the end of …`. No entry from either
  step contains `decodes at a mean level` (neither `audio_near_silent` wording).
- Run 2: `succeeded`; `warnings` holds exactly three entries: the pre-flight
  `steps[1].task.arguments.audio: slice_audio will run … past the end of …`, and two prefixed
  `voice_diluted:` — the run-time past-end one and `voice_diluted-0.0.wav decodes at a mean
  level of … dBFS but peaks at … dBFS: quiet overall, not empty …` (#358: peak ≥ -30 dBFS).
  Nothing from `voice_inside`. A third copy of a past-end warning in either run is a finding.
It is a **finding** if run 1 carries any `audio_near_silent` entry, in either wording (the
suppression regressed), if run 2's `voice_diluted` carries none (the check was dropped), or
if either run's past-end warning is missing (that is C-F016's ground, but it is cheap to
notice here).
cleanup: `delete_output(job_id=<id>)` for both runs.
metrics: none.
source: moved from S-F103 (curation 2026-09-22, harnest#2); tester, verified in #309 (implementer proposed the case in its hand-off comment;
added after running it on 2026-09-22 over MCP as model `opus` via provider `anthropic`
against `develop @ d5e3725`, workspace `regression-complete`: job `1c4096862cfa` on the
room bed → one warning, the past-end one, across a past-end, an inside and a 4.965 s slice;
job `e6c29c15ef40` on `hal-voice.wav` → the inside slice silent, the 1200 s slice carrying
both the past-end and a `-43.86 dBFS … near-silent` entry).

### C-F067 — the two sequence templates expose the same `match_levels` pair, and `assemble-and-score` passes `match_levels_dbfs` through to `concat_videos`
Before #215 `templates/assemble-and-score` declared `match_levels` but not
`match_levels_dbfs` (#128 added the pair to `dissolve-between-shots` and never mirrored
it back), so a shot that could not reach the default −20 dBFS target without clipping
was clip-held and the only fix was copying the template inline. This case locks the
variable surface — cheap discovery calls — plus one ~3 s utility run proving the value
reaches the task.
1. `get_workflow(name="templates/assemble-and-score", variables_only=true)` and
   `get_workflow(name="templates/dissolve-between-shots", variables_only=true)`.
2. `list_workflows(shape="sequence")`.
3. `validate_workflow(name="templates/assemble-and-score", arguments={"match_levels":
   "rms", "match_levels_dbfs_typo": -24, "shots": ["asset:qa-cast/ep6-cold-open.mp4",
   "asset:qa-cast/ep3-shot2-reply.mp4"], "score": "asset:qa-cast/ep20-score.wav"})` —
   a deliberately undeclared name, with real `shots`/`score` supplied (step 4's
   fixture pair) so the template's placeholder `asset:` defaults (#166, pinned by
   S-F035) don't also fire and this stays a one-error call.
4. Run `templates/assemble-and-score` in this suite's workspace with `shots:
   ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"]`, `score:
   "asset:qa-cast/ep20-score.wav"`, `match_levels: "rms"`, `match_levels_dbfs: -24`,
   `total_frames: 248`; `wait_for_job`, then `get_job_events`.
expected:
- Step 1: **both** templates list `match_levels: null` **and** `match_levels_dbfs: null`.
- Step 2: `variable_names` for both `templates/assemble-and-score` and
  `templates/dissolve-between-shots` contain `match_levels_dbfs`; `assemble-and-score`'s
  `summary` is its full first sentence, not cut with `…` (the added variable name is
  what pushed the compact listing near its budget in #215).
- Step 3: `valid: false`, one error at `arguments.match_levels_dbfs_typo` reading
  `Unknown variable`, and its "declared variables" list names `match_levels_dbfs`.
- Step 4: the job succeeds with `warnings: []`; the `edit` step's two per-shot `log`
  events show `gain_db` that moves each shot to −24 (shot 1 ≈ −19 dBFS → ≈ −5 dB, shot 2
  ≈ −31 dBFS → ≈ +7 dB), both `held: false`. A gain that lands on −20 instead means the
  variable is declared but no longer wired into the `concat_videos` step.
- The regression is: either template missing `match_levels_dbfs`; the argument refused
  as unknown by `validate_workflow`; or the run's gains targeting −20 with −24 passed.
cleanup: delete the run (one `delete_output` on `<workflow>/<run id>`). The assets are
shared fixtures — leave them.
metrics: none.
source: moved from S-F057 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #215 on 2026-09-18
against dw `develop` 5b6e3d9 on `lem`. The issue's own pair (ep21 shots, workspace
`qa-ep22`, job `c9609479cce0`): `video 1 rms -24.3 dBFS, gain +0.3 dB` / `video 2 rms
-20.6 dBFS, gain -3.4 dB`, both `held: false`, `warnings: []` — the clip-hold from
#214's job `a3f5e0b2fcbe` gone once the template accepted `-24`. The fixture pair
above is the shared `ep6-cold-open.mp4`/`ep3-shot2-reply.mp4` pair, chosen so this
case never touches `qa-ep22`; its exact gains were
not run in #215, so treat the ≈ figures as expectations to confirm on first run, not
measured values.

### C-F068 — a list-driven run's `intermediate/…-shot@*.mp4` files, named as the manifest names them, are valid `shots` for `templates/assemble-and-score`
The series-episodes procedure (#217) recuts an episode from the per-shot clips of an
H3 template run rather than re-uploading them: `assemble-and-score`'s `shots` variable
takes `output:` references to those files. The clips a `for_each` `shot` step writes
live in the run's `intermediate/` subfolder and carry the `<workflow id>-shot@<name>.<index>-0.0.mp4`
name; `final/` holds only the concatenated episode. Two things have to keep holding
for that to work: `validate_workflow` must resolve a template's *argument* `output:`
reference (an existence check against the workspace — unlike an inline step
reference, S-F033) exactly as the manifest spells it, `@` and all, and the guessed
form the skill used to teach (`final/<shot name>.mp4`) must keep failing *here*, in
the free call, not after the job is queued. Cheap: one two-entry `concat_videos`
`for_each` run (no model, ~5 s) and two free validate calls; no H3 generation needed,
since the naming and the subfolder are the `for_each` step's, not the model's.
Run this inline workflow in the level's workspace:
```json
{"id":"s_f061",
 "variables":{"shots":[{"name":"open","clip":"asset:qa-cast/ep6-cold-open.mp4"},
                       {"name":"reply","clip":"asset:qa-cast/ep3-shot2-reply.mp4"}]},
 "steps":[{"name":"shot","for_each":"variable:shots",
   "task":{"command":"concat_videos","arguments":{"videos":["item:clip"],"fps":24}},
   "result":{"content_type":"video/mp4","subfolder":"intermediate"}}]}
```
then `validate_workflow(name="templates/assemble-and-score", arguments={shots: [...],
score: "asset:qa-cast/ep15-song.mp3", total_frames: 248})` twice: (a) `shots` = the two
manifest names verbatim, each prefixed `output:`; (b) the same with `shots[0]`
replaced by the guessed form `output:s_f061/<run id>/final/open.mp4`.
expected:
- The run **succeeds** with a two-entry manifest, steps `shot@open` and `shot@reply`,
  both `subfolder: "intermediate"`, files
  `s_f061/<run id>/intermediate/s_f061-shot@open.0-0.0.mp4` and
  `…/s_f061-shot@reply.1-0.0.mp4` — no `final/` entry at all. Copy the names from the
  manifest; do not retype them.
- (a) → **`valid: true`**, `checked_arguments` containing `shots` (so the references
  were actually resolved, not skipped), and a `plan` (its step count is the template's,
  8 today, and not this case's subject).
- (b) → **`valid: false`**, single error at path **`arguments.shots[0]`** whose message
  names the missing name and the workspace's outputs directory (`Output
  's_f061/<run id>/final/open.mp4' not found under …/regression-complete/outputs`). A
  `valid: true` here — the existence check dropped from argument references — is the
  regression that turns a bad `shots` entry back into a queued job that fails at the
  cut.
cleanup: delete the run (`delete_output` on `s_f061/<run id>`); the validate calls
write nothing. The three assets are shared fixtures — leave them.
metrics: none.
source: moved from S-F061 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #217 on 2026-09-18
against dw `0.4.0-beta.6` on `lem` (job `c5354b8a9c99`, workspace `regression-smoke`);
the same two arms were first confirmed against a real `music-video` H3 run
(`slow-light`, job `2e646456406a`) in that issue's verify comment. The implementer
proposed the positive arm in its hand-off; the negative arm and the fixture-based
stand-in for the H3 run are mine.

### C-F069 — `match_levels_dbfs` on both `concat_videos` and `dissolve_videos` names the -0.5 dBFS clip-hold ceiling and the `match_levels_held` warning
#214 was reopened as a false regression because the served `match_levels_dbfs`
description named only the `peak` default (−1 dBFS), which a workflow author read as
the ceiling a clipping shot is held at; #220 fixed the text, and the first fix reached
only `concat_videos` because `dissolve_videos` carries its own copy of the string
(their `match_levels` behaviour is shared, see C-F067). This locks in that both
served descriptions agree and name what a consumer has to look for. Read-only, free.
1. `get_task(command="concat_videos")`.
2. `get_task(command="dissolve_videos")`.
expected:
- In both responses the `match_levels_dbfs` parameter's `description` contains all
  three of: `-0.5 dBFS` (the hold ceiling), `match_levels_held` (the warning kind),
  and the phrase `log event` (the per-shot hold report) — alongside the `-1 dBFS` /
  `-20 dBFS` defaults.
- The two descriptions are identical. A `dissolve_videos` text that names only the
  defaults, or that differs from `concat_videos`'s, is the regression (the two copies
  drifting apart is exactly how #220 bounced once).
cleanup: none (read-only).
metrics: none.
source: moved from S-F062 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #220 on 2026-09-18
against dw `0.4.0-beta.6` on `lem`.

### C-F070 — every template that exposes `audio_bleed_ms` also exposes `audio_bleed_gain_db`, and `assemble-and-score` wires it into `concat_videos`
#199 added `audio_bleed_gain_db` to `concat_videos` to duck the time-reversed tail
bleed #198 established, but no template reached it: `templates/assemble-and-score`,
`templates/minimax/dialogue-short` and `templates/minimax/music-video` all exposed the
switch that creates the bleed (`audio_bleed_ms`) and not the one that sets its level,
so the shipped mitigation was unreachable except by copying a template inline — the
second recurrence of "task argument exists, no template exposes it" after #215 /
C-F067. Discovery calls only, all free; the task-level behaviour of the gain is #199's.
1. `get_workflow(name=..., variables_only=true)` for each of the three templates.
2. `get_workflow(name="templates/assemble-and-score")` (full definition).
3. `list_workflows(shape="sequence")`.
4. `validate_workflow(name="templates/minimax/dialogue-short", arguments=
   {"audio_bleed_gain_db": -6.5})`, then the same with `{"audio_bleed_gain_db": "loud"}`.
expected:
- Step 1: all three list `audio_bleed_gain_db: 0` beside `audio_bleed_ms`. Any
  template whose variables carry `audio_bleed_ms` but not `audio_bleed_gain_db` is the
  regression — including a future template that adds the bleed switch without the gain.
- Step 2: the `edit` step's `concat_videos` arguments contain
  `"audio_bleed_gain_db": "variable:audio_bleed_gain_db"` — declared *and* wired; a
  variable present in step 1 but absent here is the silent form of the regression.
- Step 3: `variable_names` for all three templates contain `audio_bleed_gain_db`, and
  `assemble-and-score`'s `summary` is a complete sentence, not cut with `…` (the extra
  variable names are what pushed the compact listing over its #101 budget in #227).
- Step 4: `-6.5` → `valid: true` with `checked_arguments: ["audio_bleed_gain_db"]` (a
  fractional dB is accepted despite the integer default); `"loud"` → `valid: false`, one
  error at `arguments.audio_bleed_gain_db` reading `Cannot convert`.
cleanup: none (read-only).
metrics: none.
source: moved from S-F064 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #227 on 2026-09-18
against dw `develop` 5c03105 on `lem`. Not run to a generation in the verify: the
wiring is inspectable through the interface and the gain's effect on the join was
verified in #199; a run-level check belongs beside C-F067's step 4 if one is ever
wanted.

### C-F071 — both sequence templates mark their `film` as `final`, so a `subfolder == "final"` consumer finds the deliverable
#235: `templates/assemble-and-score` and `templates/dissolve-between-shots` each have a
single saving step (`film`) and neither declared a `subfolder`, so the film landed at the
run-dir top level with `"subfolder": ""` — invisible to a consumer following `get_job`'s
own convention ("`final` is the deliverable") and inconsistent with the generating
templates, whose shots come out under `intermediate/` and `final/` (C-F068). The
two-or-more-saving-steps test in the dw repo never reached a one-step template, so this
is the only guard. Two ~5 s utility runs plus two discovery calls.
1. `get_workflow(name="templates/assemble-and-score")` and
   `get_workflow(name="templates/dissolve-between-shots")` (full form).
2. Run `templates/assemble-and-score` in this suite's workspace with `shots:
   ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"]`, `score:
   "asset:qa-cast/ep20-score.wav"`, `sample_rate: 32000`, `total_frames: 248`;
   `wait_for_job`.
3. Run `templates/dissolve-between-shots` with the same `shots`/`score`/`sample_rate`,
   `dissolve_frames: 12`, `total_frames: 236`; `wait_for_job`.
4. `list_gallery(workspace=<this suite's workspace>, subfolder="final")`.
expected:
- Step 1: in both definitions the `film` step's `result` block carries `"subfolder":
  "final"`; no other step has a `result` block.
- Steps 2–3: both jobs succeed. In each manifest the `film` entry has `"subfolder":
  "final"` and its one file name reads `templates/<template>/<run id>/final/<template>-
  film.<n>-0.0.mp4` (`<n>` any integer: an ordinal, not a step count, per dw#458) — the `final/` segment present in the name, not just the field. Every
  other step reports `"files": []` and `"subfolder": ""` (they save nothing; that is
  correct, not a regression).
- Step 4: the two films are listed, each with `subfolder: "final"` and `folder:
  templates/<template>`; nothing else from these runs appears under `final`.
- The regression is: either `film` entry back to `"subfolder": ""` or a file name
  without the `final/` segment; or the gallery `final` filter returning fewer than the
  two films.
cleanup: delete both runs (`delete_output` on each `templates/<template>/<run id>`). The
assets are shared fixtures — leave them.
metrics: none.
source: moved from S-F068 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #235 on 2026-09-18
against dw `0.4.0-beta.6` on `lem` (develop `1acace7`), in workspace `qa-ep23` with the
issue's own ep21/ep4 shots: `dissolve-between-shots` job `f5e86f4ccfb1` →
`templates/dissolve-between-shots/20260919-010200-89f71598/final/dissolve-between-shots-film.6-0.0.mp4`,
`assemble-and-score` job `0664b1f20fff` →
`templates/assemble-and-score/20260919-010221-55c1580a/final/assemble-and-score-film.6-0.0.mp4`;
`list_gallery(subfolder="final")` returned exactly those two. The fixture pair above is
C-F067's so this case never touches `qa-ep23`; the `total_frames` values (248 for two
124-frame shots; 236 = 248 − 12 for the dissolve) keep the score slice inside the
~10.3 s bed so neither run warns.

### C-F072 — a companion argument that renders `seam_fade_ms` or `audio_bleed_gain_db` inert is warned about at validate
#288: `concat_videos` takes the bleed path at any hard cut where `audio_bleed_ms` is
non-zero, so a `seam_fade_ms` passed alongside it does nothing — and
`templates/minimax/dialogue-short` ships `audio_bleed_ms: 1800` as a default, so a caller
passing only `seam_fade_ms` (the remedy the old `bleed_tonal_material` warning itself
recommended) got a clean validate, a clean run and no fade. Now the pre-flight resolves
both arguments (through `variable:` references, defaults merged with the caller's
`arguments`) and warns. #290 is the mirror case: `audio_bleed_gain_db` only applies along
the bleed path, so with `audio_bleed_ms: 0` — explicitly, or simply left at the task
default — the gain does nothing, and until #290 the pre-flight said so for `seam_fade_ms`
but not for this pair. Free: four validate calls, nothing runs.
1. `validate_workflow(name="templates/minimax/dialogue-short", arguments={"seam_fade_ms":
   80})` — `audio_bleed_ms` deliberately left at the template default.
2. `validate_workflow(name="templates/minimax/dialogue-short", arguments={"seam_fade_ms":
   80, "audio_bleed_ms": 0})`.
3. `validate_workflow(inline_workflow={"id": "regression-inert-seam-fade", "steps":
   [{"name": "join", "task": {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep13-episode.mp4"],
   "audio_bleed_ms": 500, "seam_fade_ms": 80, "fps": 24}}, "result": {"content_type":
   "video/mp4", "fps": 24, "subfolder": "final"}}]})` — literals, no `variable:`.
4. `validate_workflow(workspace=<suite workspace>, workflow={"id":
   "regression-inert-bleed-gain", "seed": 1, "steps": [
   {"name": "gain_without_bleed", "task": {"command": "concat_videos", "arguments":
   {"videos": ["asset:qa-cast/ep31-shot1-return.mp4", "asset:qa-cast/ep31-shot2-shrug.mp4"],
   "audio_bleed_ms": 0, "audio_bleed_gain_db": -6, "fps": 24}}, "result":
   {"content_type": "video/mp4", "subfolder": "intermediate", "file_base_name": "gain-a"}},
   {"name": "gain_bleed_omitted", "task": {"command": "concat_videos", "arguments":
   {"videos": [same two], "audio_bleed_gain_db": -6, "fps": 24}}, "result": {...,
   "file_base_name": "gain-b"}},
   {"name": "gain_with_bleed", "task": {"command": "concat_videos", "arguments":
   {"videos": [same two], "audio_bleed_ms": 800, "audio_bleed_gain_db": -6, "fps": 24}},
   "result": {..., "file_base_name": "gain-c"}},
   {"name": "no_gain_no_bleed", "task": {"command": "concat_videos", "arguments":
   {"videos": [same two], "audio_bleed_ms": 0, "fps": 24}}, "result": {...,
   "file_base_name": "gain-d"}}]})`.
expected:
- Steps 1 and 3 are `valid: true` and each carries exactly one warning that names the
  step (`episode` / `join`), says `seam_fade_ms` has no effect while `audio_bleed_ms` is
  the resolved value (`1800` in step 1, `500` in step 3), and tells the caller to pass
  `audio_bleed_ms: 0` for the fade to apply.
- Step 2 carries no warning mentioning `seam_fade_ms` or `audio_bleed_ms` (the
  host-memory projection warning the template draws on this box is unrelated and may
  be present).
- Step 4 is `valid: true` with exactly two warnings, one naming `gain_without_bleed` and
  one naming `gain_bleed_omitted`, each saying `audio_bleed_gain_db` has no effect when
  `audio_bleed_ms` is 0 and telling the caller to pass a non-zero `audio_bleed_ms` for the
  gain to apply; no warning mentions `gain_with_bleed` or `no_gain_no_bleed`.
- `get_workflow("templates/minimax/dialogue-short").description` says the two are
  mutually exclusive and that a declick fade instead of a bleed means setting
  `audio_bleed_ms` to 0.
It is a **finding** if step 1 or 3 validates with no such warning, if the warning names
a value other than the one that resolves, if step 2 warns about the pair, if either of
step 4's inert steps validates without its warning (the omitted-key step in particular —
that is the "forgot the bleed" case), if step 4's warning does not name both arguments,
if step 4's non-zero-bleed or no-gain step draws one, or if the template description no
longer states the exclusivity.
cleanup: none — nothing is written.
metrics: none.
source: moved from S-F087 (curation 2026-09-22, harnest#2); tester, verified in #288 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: the template with `seam_fade_ms: 80` warned `Step 'episode': 'seam_fade_ms'
has no effect while 'audio_bleed_ms' is 1800 - a hard cut takes the bleed path instead of
the fade path. Pass 'audio_bleed_ms': 0 for 'seam_fade_ms' to apply.`; with
`audio_bleed_ms: 0` it did not; a literal inline step warned the same naming `1800`. A
task-only run over two existing shots (job `f46a7d3a2af2`) carried the warning at submit
and its `bleed_tonal_material` remedy now reads `Pass 'audio_bleed_ms': 0 for a hard cut
on this material instead - seam_fade_ms has no effect while audio_bleed_ms is non-zero.`
Step 4 merged in from a separate S-F090 during the 2026-09-22 suite audit (both cases were
the identical "modifier argument rendered inert by a companion argument's value" pattern on
`concat_videos`/`audio_bleed_ms`, free and validate-only): verified in #290 on 2026-09-21
over MCP as model `opus` via provider `anthropic`, in `qa-ep32` both inert steps warned
`Step '<name>': 'audio_bleed_gain_db' has no effect when 'audio_bleed_ms' is 0 - pass a
non-zero 'audio_bleed_ms' for the gain to apply.`, the other two steps were silent, and a
fifth `trim_frames: 0, crossfade_ms: 300` step in the same document still drew its #288
warning.

### C-F073 — `concat_videos` bleed with `audio_bleed_gain_db` fills the seam hole, and the inert `crossfade_ms` is warned about
#199/#288: a hard cut between two independently generated shots leaves a hole where the
outgoing shot's tail meets the incoming shot's silent head; `audio_bleed_ms` rings the
tail over it and `audio_bleed_gain_db` ducks that tail. Both are silent no-ops in some
combinations, so the working path and the pre-flight for one inert combination are
checked together. A/B in one job over two existing 124-frame shots; ~8 s, no GPU.
1. `validate_workflow(workspace=<suite workspace>, workflow={"id":
   "regression-bleed-ab", "seed": 1, "steps": [
   {"name": "control", "task": {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep31-shot1-return.mp4", "asset:qa-cast/ep31-shot2-shrug.mp4"],
   "audio_bleed_ms": 0, "fps": 24, "match_levels": "rms"}}, "result": {"content_type":
   "video/mp4", "subfolder": "intermediate", "file_base_name": "bleed-control"}},
   {"name": "treatment", "task": {"command": "concat_videos", "arguments": {"videos":
   [same two], "audio_bleed_ms": 800, "audio_bleed_gain_db": -6, "fps": 24,
   "match_levels": "rms"}}, "result": {"content_type": "video/mp4", "subfolder":
   "final", "file_base_name": "bleed-treatment"}},
   {"name": "inert_crossfade", "task": {"command": "concat_videos", "arguments":
   {"videos": [same two], "trim_frames": 0, "crossfade_ms": 300, "fps": 24}}, "result":
   {"content_type": "video/mp4", "subfolder": "intermediate", "file_base_name":
   "bleed-inert"}}]})`.
2. `run_workflow` the same document with the bound `acknowledged_cost`, `wait_for_job`
   to `succeeded`, then `get_gallery_metadata(envelope=true)` on the `control` and
   `treatment` files.
expected:
- Step 1 is `valid: true` with exactly one warning, naming step `inert_crossfade` and
  saying `crossfade_ms` has no effect when `trim_frames` is 0.
- The job succeeds; both A/B files are 248 frames, 24 fps, 32000 Hz stereo,
  `mean_dbfs` within ±0.5 of −20 (the rms target).
- `job.warnings` carries a `match_levels_held` line for each of `control` and
  `treatment` (video 2 held to −0.5 dBFS) and a `bleed_join` line for `treatment` only,
  whose remedy says to pass `audio_bleed_ms: 0` (not `seam_fade_ms`).
- Envelope index 5 (the seam second, 5.17 s) reads `rms_dbfs` below −45 in `control` and
  at least 15 dB higher in `treatment`; every other index's `rms_dbfs` matches between
  the two files within 0.5 dB.
It is a **finding** if the inert-crossfade warning is missing, if `treatment`'s seam
bin is not raised by the bleed, if any non-seam bin differs by more than 0.5 dB (the
bleed leaked past its 800 ms), or if the `bleed_join` remedy names `seam_fade_ms`.
cleanup: `delete_output` the run by run name.
metrics: none.
source: moved from S-F089 (curation 2026-09-22, harnest#2); tester, found while running TESTER_TASK.agent.md (ep32) on 2026-09-21 over MCP
as model `opus` via provider `anthropic`: job `310af1018ea1` in `qa-ep32`, 7.5 s; seam
bin −53.2 rms in control vs −32.0 in treatment, all other bins within 0.06 dB; both
clip-held 0.1 dB short; `bleed_join` recommended `audio_bleed_ms: 0`. The
`audio_bleed_gain_db`-with-`audio_bleed_ms: 0` combination is not in this case: it
warns at validate since #290, pinned by C-F072.

### C-F074 — a `match_levels_dbfs` that an unset `match_levels` makes inert is warned about at validate, on both join commands
#291: `concat_videos` and `dissolve_videos` only call the level matcher when
`match_levels` is `"rms"` or `"peak"` (off by default), so a caller who passes only the
`match_levels_dbfs` target has stated an intent the engine silently dropped — the third
"modifier without its enabler" pair on these commands after C-F072's #288 and #290 arms.
Free: one validate call, nothing runs.
1. `validate_workflow(workspace=<suite workspace>, workflow={"id":
   "regression-inert-match-levels-dbfs", "seed": 1, "steps": [
   {"name": "concat_target_only", "task": {"command": "concat_videos", "arguments":
   {"videos": ["asset:qa-cast/ep31-shot1-return.mp4", "asset:qa-cast/ep31-shot2-shrug.mp4"],
   "fps": 24, "match_levels_dbfs": -24}}, "result": {"content_type": "video/mp4",
   "subfolder": "intermediate", "file_base_name": "ml-a", "fps": 24}},
   {"name": "dissolve_target_only", "task": {"command": "dissolve_videos", "arguments":
   {"videos": [same two], "dissolve_frames": 0, "fps": 24, "match_levels_dbfs": -24}},
   "result": {..., "file_base_name": "ml-b"}},
   {"name": "concat_explicit_null", "task": {"command": "concat_videos", "arguments":
   {"videos": [same two], "fps": 24, "match_levels": null, "match_levels_dbfs": -24}},
   "result": {..., "file_base_name": "ml-c"}},
   {"name": "concat_live", "task": {"command": "concat_videos", "arguments":
   {"videos": [same two], "fps": 24, "match_levels": "rms", "match_levels_dbfs": -24}},
   "result": {..., "file_base_name": "ml-d"}},
   {"name": "dissolve_live", "task": {"command": "dissolve_videos", "arguments":
   {"videos": [same two], "dissolve_frames": 0, "fps": 24, "match_levels": "peak",
   "match_levels_dbfs": -24}}, "result": {..., "file_base_name": "ml-e"}},
   {"name": "dissolve_neither", "task": {"command": "dissolve_videos", "arguments":
   {"videos": [same two], "dissolve_frames": 0, "fps": 24}}, "result": {...,
   "file_base_name": "ml-f"}}]})`.
expected:
- `valid: true` with exactly three warnings, one each naming `concat_target_only`,
  `dissolve_target_only` and `concat_explicit_null`, each saying `match_levels_dbfs`
  has no effect when `match_levels` is unset and telling the caller to pass `"rms"` or
  `"peak"` for the target to apply.
- No warning mentions `concat_live`, `dissolve_live` or `dissolve_neither`.
It is a **finding** if any of the three inert steps validates without the warning (a
regression on only one of the two commands counts), if the warning does not name both
arguments, or if a live or no-target step draws one.
cleanup: none — nothing is written.
metrics: none.
source: moved from S-F092 (curation 2026-09-22, harnest#2); tester, verified in #291 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: in `qa-ep33` the two target-only steps and the explicit-null step each warned
`Step '<name>': 'match_levels_dbfs' has no effect when 'match_levels' is unset - pass
"rms" or "peak" for the target to apply.`; the `rms`, `peak` and no-target steps were
silent.

### C-F075 — both sequence templates' `world_fade_out_ms` fades only the world tail, and its default `0` changes nothing
Before #339 the shots' world sound in `templates/assemble-and-score` and
`templates/dissolve-between-shots` ran at full level to the last frame. It sat about 25 dB
over a score's written decay, and no argument could hand the ending to the score.
Both templates now declare `world_fade_out_ms` (default `0`) and run a `world_faded`
(`fade_audio`) step between `world` and `mixed`. This case checks that the fade touches
only the tail and that the default is a real no-op. Four ~4 s utility runs, no model.
1. `get_workflow(name="templates/assemble-and-score", variables_only=true)` and the same
   for `templates/dissolve-between-shots`.
2. Run `templates/assemble-and-score` in this suite's workspace with `shots:
   ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"]`, `score:
   "asset:qa-cast/ep20-score.wav"`, `total_frames: 248`. Run it again with
   `world_fade_out_ms: 3000` added. Read each film with
   `get_gallery_metadata(envelope=true)`.
3. Do the same for `templates/dissolve-between-shots` with `total_frames: 236`: once
   default, once with `world_fade_out_ms: 3000`. Read both envelopes.
expected:
- Step 1: both templates list `world_fade_out_ms: 0`.
- Steps 2–3: all four jobs succeed, and each manifest has a `world_faded` step between
  `world` and `mixed`. Within each template, the faded run's `warnings` equal the
  default run's. Neither template's fade adds a warning. The only warnings are the
  pre-existing no-`match_levels` level-jump note, plus the dissolve's resample note.
- Within each template, `media.envelope.rms_dbfs` is identical in the two runs up to about
  3 s from the end. The last three buckets of the faded run are lower than the default's,
  and the final bucket is lower by at least 6 dB. At verification, assemble's s7–s10
  went from −31.6/−30.2/−31.7/−52.0 to −31.7/−32.0/−39.4/−61.1, and dissolve's s7–s9 went
  from −29.2/−32.6/−33.0 to −30.1/−36.2/−44.5.
- The regression is any of these: the variable is missing; `world_faded` is missing; the
  tails are unchanged, which means `mixed` has been rewired back to the raw `world`; or the
  default run differs from the faded run before the tail, which means the fade is leaking
  earlier or the default is no longer a no-op.
cleanup: delete all four runs (`delete_output(job_id=...)` on each). The assets are
shared fixtures, so leave them.
metrics: none.
source: moved from S-F109 (curation 2026-09-22, harnest#2); tester, verified in #339 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (jobs 1a36cf75d84c, b007639f60eb,
2cb736b751d8, a5fe2d863125).

### C-F076 — an out-of-domain number in an audio task argument is refused, not interpreted
A negative frame count and a zero sample rate used to be *accepted*: `slice_audio`
with `num_frames: -10` returned all-but-the-last-10-frames (Python slice
semantics leaking through an argument that is a count, #139), and
`resample_audio` with `target_sample_rate: 0` relabelled the waveform 44100 Hz
without resampling it — `succeeded`, no warning, 38% duration change, levels
bit-identical to the source (#140). Both are the same shape and the worst one:
a plausible-looking track of the wrong length or speed, from a job that says it
is fine. Declared domains are now checked in three places and all three need
pinning, because each catches a value the others cannot see. Parts 1–3 are free
and instant and need no media at all.
expected:
- **1. Statically, at the JSON path.** `validate_workflow` on an inline
  one-step workflow whose `slice_audio` arguments carry `start_frame: -1`,
  `num_frames: -10`, `fps: 0` → `valid: false` with **three** errors, one per
  argument, each `path` being `steps[0].task.arguments.<name>` and each message
  naming that argument. All three at once is the assertion: a validator that
  short-circuits on the first out-of-domain value hides the rest, and the
  wording must distinguish "zero or above" (`start_frame`, `non_negative`) from
  "above zero" (`num_frames`/`fps`, `positive`). Separately, `resample_audio`
  with `target_sample_rate: 0` → `valid: false`, one error at
  `steps[0].task.arguments.target_sample_rate`. Use a deliberately
  **nonexistent** `asset:` reference for the `audio` argument in both — the
  domain pass must fire without any media present, and pinning that keeps this
  part fixture-free. (Asset resolution happens *later*, at run time: a
  nonexistent asset in a queued job fails on the missing file before the
  command's own domain check is reached, so don't expect a domain error from
  the run-time layer with a fake input.)
- **2. Given as a string.** The same `resample_audio` body with
  `target_sample_rate: "0"` → the same single error, reported as `got '0'`. The
  CLI / `variable: null` path arrives as a string; coercion must happen before
  the check, not instead of it.
- **3. Discoverable, so a caller can read the rule instead of guessing.**
  `get_task("slice_audio")` → `num_frames`, `duration_seconds`, `fps` and
  `sample_rate` each carry `"domain": "positive"`; `start_frame` and
  `start_seconds` carry `"domain": "non_negative"`.
  `get_task("resample_audio")` → `target_sample_rate` and `sample_rate` carry
  `"domain": "positive"`. Before the fix these reported `annotation: null` and
  no domain, which is why a consumer could not tell a negative count from a
  supported trim-from-the-end idiom.
- **4. At `run_workflow`, before any job exists.** `run_workflow` checks caller
  `arguments` against declared domains too (0.5.0; amended per harnest#32, dw#538:
  Don, 2026-09-27, 0.5.0 release), so the bad value never reaches the command: run a
  one-step `resample_audio` over a **real** audio track (any track the run has
  to hand — a `generate_speech` wav kept from S-F007, or any asset in the shared
  library) whose step declares `target_sample_rate: "variable:rate"`, with the
  workflow's own `variables` block giving `rate` some ordinary default (32000,
  say — anything positive) and the bad value arriving **only** as the *caller's*
  override: `run_workflow(..., arguments={"rate": 0})`. That last part is load-
  bearing (#328) — a 0 baked into the workflow's own declared default for `rate`
  is not this case: `set_variables` substitutes a declared default into the
  definition before the static domain pass runs, so it is already sitting in
  the resolved JSON body by the time the check fires and gets refused
  pre-flight, at `run_workflow` too, same as part 1. Only a value that arrives
  purely from the caller's `arguments` at run time — never touching the
  workflow's own declared default — used to reach the command unchecked. It is now
  refused up front: `run_workflow` returns a tool error naming
  `steps[0].task.arguments.target_sample_rate`, **no job is created**, and
  `list_gallery(only_orphans=true)` shows no new run directory. A job that queues
  and then fails is the old, weaker behaviour and a finding; a job that succeeds
  is the #140 regression. The command's own execution-time check is covered by
  the dw repo's pytest suite, since a consumer can no longer reach it. This is the layer that produced
  #140's wrong deliverable, since the rate there came from a `variable:` inside
  a chain. (`validate_workflow` given the same `name`/`workflow` and the same
  `arguments` also refuses, because it substitutes caller arguments the same
  way; both refusing is the expected result, and a refusal at either layer
  alone is a partial fix worth a finding.)
- **5. A legal zero is still legal.** `get_task("crossfade_audio")` reports
  `crossfade_ms` as `"domain": "non_negative"` (default `75`), and a
  `crossfade_audio` step with `crossfade_ms: 0` validates. A hard cut is an
  ordinary request; `trim_frames: 0` and `dissolve_frames: 0` likewise. Without
  this line the case invites over-tightening the domains until ordinary
  workflows break.
cleanup: parts 1, 2, 3 and 5 are `validate_workflow`/`get_task` only and write
nothing. Part 4's job fails before it writes media, but it still leaves a run
directory — `delete_output` it by its `<workflow>/<run id>` name.
source: moved from S-F024 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #139 and #140
on 2026-09-14 against dw 0.4.0-beta.3 on `lem`. Parts 1, 2 and 5 run in
`regression-smoke` exactly as written; part 4 was confirmed in `qa-ep10` against
a 14.5 s 32 kHz mono wav (job `0d6ea648c1c7`, failed in 0.59 s, empty manifest),
and its happy-path companion — `target_sample_rate: 16000` on that same track —
gave `duration_seconds: 14.5` unchanged at `sample_rate: 16000` with levels
moved ~0.007 dB, i.e. a real filter ran rather than a relabel. Part 4 re-verified
over MCP on 2026-09-22 (job `01bd05280c7e`, `qa-cast/ep11-bed.wav`, `variables:
{rate: 16000}` overridden by `arguments: {rate: 0}` at `run_workflow` — queued,
failed in 1.4 s, `manifest: []`, error naming `target_sample_rate`) per #328:
the regression agent's reconstruction had instead baked `0` into the workflow's
own declared `variables` default with no caller override, which a same-session
check confirmed *is* refused pre-flight (unlike the documented fixture) — not a
regression, a reconstruction that used a different shape than this case
specifies. Wording tightened above so the caller-override requirement is
unmissable.

### C-F077 — a declared rounding is applied to the variable, not just inside the pipeline that needs it
S-F028 covers the *validate-time* half of a declared bound: an off-grid value is
announced and a bad one refused, both for free. This is the run-time half, and it
asserts something narrower and easier to break: when a workflow rounds a variable
up, the **rounded value is what every step gets**, not just the pipeline whose VAE
imposed the grid. It matters because a frame count is usually shared — on
`templates/minimax/music-video` the same `num_frames` drives both the H3 `shot`
steps and the `slice_audio` steps that cut the song into the pieces those shots
lip-sync to. If rounding were applied inside the H3 pipeline only, every slice
would be cut short of the video it conditions (130 frames of song under 141 frames
of picture), the shots would drift out of sync, and nothing would say so: the final
`pair_audio` re-lays the whole song with `fit: "video"`, so the deliverable's own
duration still checks out. A silent per-shot failure hidden behind a correct-looking
deliverable is exactly the shape worth pinning, and it can be tested for pennies —
the assertion needs no model at all, just one audio task whose output length is the
effective frame count.
expected:
- **The rounded count is what the task runs.** An inline workflow declaring
  `variable_constraints.num_frames = {modulus: 17, remainder: 5, min_frames: 124,
  max_frames: 345, snap: "up"}` with `num_frames: 130`, whose single step is
  `slice_audio(audio="asset:qa-cast/ep11-bed.wav", sample_rate=32000,
  start_frame=0, num_frames="variable:num_frames", fps=24)` saved as
  `audio/wav` → `succeeded`, and `get_gallery_metadata` on the output reports
  **`duration_seconds: 5.875`** — 141 frames at 24 fps, not 130 (5.4167 s). The
  step never loads a model, so a regression here is a few seconds to catch.
- **The warning is on the job, not only on the validate.** The same job's
  `job.warnings` carries the rounding line naming `141` and saying the run
  generates 141, not 130. `validate_workflow` on the same definition carries it
  too, as `valid: true` with that warning — a caller who only ever runs still
  finds out.
- **Rounding travels with an inline workflow.** The constraint above is declared
  in the submitted JSON rather than by a stored template, and is honoured anyway.
  A fix that only consulted the catalog's bounds would pass S-F028 and fail here.
- **The realized workflow reports the value the run used.** `get_job_workflow`
  on that job → `workflow.variables.num_frames` is **`141`**, the snapped value, with
  `variable_constraints` alongside it. This is deliberate since dw 9566bd1f
  (2026-09-28, "validation and the realized record see constraint-snapped values";
  test `test_the_realized_record_carries_the_snapped_value`): the record beside the
  run's manifest matches what the run did, and 141 is on the grid, so re-running the
  definition still reproduces the run. Until then it recorded the submitted `130`.
  A value of `130` here is a finding (filed as drift in #576 when this was reworded).
cleanup: `delete_output` the run directory of both jobs. The asset it reads is a
durable fixture (see "Fixtures") and is never written to.
source: moved from S-F029 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, found while running
TESTER_TASK.agent.md on 2026-09-14 against dw 0.4.0-beta.4 on `lem`. Measured twice: a
`music-video`-shaped run with `num_frames: 130` produced a 282-frame deliverable
(2 x 141) with both warnings on the job, and this audio-only probe isolated the
question the expensive run could not answer on its own — whether `slice_audio` saw
130 or 141. It saw 141.
Realized-record bullet reworded 2026-10-02 for dw 9566bd1f.

### C-F078 — normalizing before a mux is what puts headroom in the deliverable, and the warning tracks it
Every audio deliverable this box makes is muxed or encoded at least once more after the
waveform is decided, and a lossy encode of a waveform with no headroom decodes above
0 dBFS and clips (#158). `normalize_audio(peak_dbfs: -1)` immediately before the saving
step is the whole fix, and #159 put it inside `templates/minimax/music` and
`templates/minimax/music-video` so a caller gets it without knowing to ask. This case
pins the mechanism rather than either template, so it stays true if the templates are
rewritten: the same video, the same song, muxed twice — once raw, once normalized — in
one job, with the warning and the decoded level read on both.
It is deliberately built as a **pair**: the raw branch is the positive control. A case
that only asserts "the normalized file is below 0" passes just as well when
`normalize_audio` has become a no-op and the source happens to be quiet, and passes when
the warning has stopped firing at all. The finding is the *difference* between the two
branches, in the warning and in the level at once.
Free and seconds long — two `pair_audio` calls and one `normalize_audio` over durable
fixtures, no model loads at all. Run it on every pass.
expected: one job with three task steps — `raw_mux` = `pair_audio(video:
"asset:qa-cast/ep13-episode.mp4", audio: "asset:qa-cast/ep15-song.mp3", sample_rate:
44100, fit: "video")`; `balanced` = `normalize_audio(audio:
"asset:qa-cast/ep15-song.mp3", peak_dbfs: -1, sample_rate: 44100)` with `result.save:
false`; `balanced_mux` = the same `pair_audio` reading
`"previous_result:balanced"` — all three `content_type: "video/mp4"` / `fps: 24` except
`balanced`, which is `audio/mp3` —
- **The raw branch warns on headroom, and the warning names the file.** `job.warnings`
  carries exactly **one** *headroom* entry for `raw_mux`, naming that step's mp4: the
  post-encode `audio_clipped` warning on the written file (decodes above full scale,
  advising `normalize_audio(peak_dbfs: -3)`). No pre-encode `audio_no_headroom` entry
  for `raw_mux` — on a video mux the pre-encode check is deliberately deferred to the
  post-encode probe (#174 amendment, bbe4adb,
  `docs/proposals/complete/h3-video-mux-headroom-warning-complete.md`), so a clean mux is never
  warned about a defect the encode didn't introduce. **Two** headroom entries for
  `raw_mux` is the regression to watch for in one direction (the deferral stopped
  working — the pre-2026-09-20 shape #194/#305 recorded); **zero** is the regression
  in the other (the written-file probe stopped firing, and a video mux's overshoot is
  exactly what that probe exists to catch). With the fixtures as given
  (`ep15-song.mp3` at 30.02 s, `ep13-episode.mp4` at 11.75 s), both branches also
  carry a `pair_audio: 'fit' trimmed …` warning — #246's intended trim notice (pinned
  as expected by C-F084's trim arm), not a finding, and not counted among the
  headroom warnings above.
- **The normalized branch does not warn on headroom.** No `job.warnings` entry names
  `balanced_mux` with an `audio_no_headroom` or `audio_clipped` warning. A headroom
  warning on both branches means the check is measuring something other than the
  waveform it was handed.
- **The decoded levels move the right way and land either side of full scale.**
  `get_gallery_metadata(<raw_mux mp4>).media.peak_dbfs` is **at or above 0**;
  `get_gallery_metadata(<balanced_mux mp4>).media.peak_dbfs` is **strictly below 0**.
  Assert the sign, not a target: the mux is a second lossy encode and it overshoots the
  -1.0 the waveform was written at, by 0.4 dB on the verifying run and by as much as
  0.93 dB on the Music 3 mp3s measured beside it. A case demanding `<= -0.9` would
  fail on a working fix — that is the trap, and it is why the assertion is the sign.
- **Both branches are the same picture.** `frame_count`, `fps`, `width`, `height` and
  `duration_seconds` match between the two mp4s and match the fixture (282 f, 24 fps,
  960x544, 11.75 s). `normalize_audio` is a gain change on the soundtrack; a branch that
  also moved the video is a different finding.
metrics: `peak_dbfs` of each mp4, conditions `raw` and `normalized`, unit `dBFS`, logged
to `regression-perf/C-F078.jsonl`. Logged pass or fail — the interesting number is the
*gap* between the two conditions and whether the normalized one creeps toward 0 as the
encoder or the fixture changes. The median-and-50% rule in `regression-perf/README.md`
means nothing on a figure that sits near zero and may be negative: read these two by eye
against the sign assertions above, and do not file an issue off the percentage alone.
cleanup: delete the run's whole output folder — all three files are scratch. The two
assets it reads are durable fixtures listed in "Fixtures" and are never deleted.
source: moved from S-F031 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #159 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`, job `089b1e2945d2` (7.7 s):
`raw_mux` warned at +0.8 dBFS and decoded `peak_dbfs: 0.776`, `balanced_mux` did not
warn and decoded `peak_dbfs: -0.626`, both 282 f / 24 fps / 960x544 / 11.75 s. The same
job is what finally settled M-F011's fourth bullet (the warning naming a muxed mp4, not
only a saved audio file) with a real MCP call rather than a description. Warning-count
bullet amended per #305's wontfix (bbe4adb) on 2026-09-22.

### C-F079 — a schema-advertised `device` is accepted by a task that runs no model
`get_task(<command>)` appends `device` to every task's parameter list — the engine
treats it as a universal, always-safe override. Before #185, only the model-backed
handlers actually consumed it; a utility task like `resample_audio` forwarded
`arguments` straight to a function whose signature had no `device`, so the argument
the schema advertised was a `TypeError` at run time, after the job was queued, and
the free pre-flight (`validate_workflow`) let it through because it does not check
argument names against the signature. The fix consumes `device` in the dispatcher for
every non-model handler. This case pins the contract from the consumer side: if the
schema lists it, passing it runs. Cheap: two utility-task jobs, a few seconds each,
no model load.
expected:
- **The schema still advertises it.** `get_task("resample_audio")` and
  `get_task("gain_audio")` each list a parameter named `device` (required: false)
  whose description says it is a device override. If a future change stops
  advertising it on non-model tasks instead, that is a *different* valid resolution
  of #185 — record it as an observation, not a failure, and propose retiring this
  case per "Removing a case".
- **Passing it runs.** An inline workflow with one step `resample_audio`,
  `arguments: {"audio": "asset:qa-cast/ep11-bed.wav", "target_sample_rate": 16000,
  "device": "cpu"}`, `result: {"subfolder": "final", "file_base_name": "resampled",
  "content_type": "audio/wav"}` → `validate_workflow` valid, `run_workflow` accepted,
  `wait_for_job` → `succeeded` with one manifest file, `error: null`. A `TypeError`
  mentioning `device` — or any failure at all — is the regression.
- **Not just `cpu`, not just one command.** A second inline workflow with two steps:
  `gain_audio` with `{"audio": "asset:qa-cast/ep11-bed.wav", "gain_db": -6,
  "start_seconds": 0, "duration_seconds": 1, "device": "cuda"}` and `resample_audio`
  with `device: "cuda:0"` (same audio, `target_sample_rate: 16000`), each with an
  audio/wav `result` → `succeeded`, two manifest files. `gain_audio` is a different
  non-model handler and the two accelerator spellings are what a real agent passes
  when it means "keep this off the pipeline's GPU"; a fix that special-cases one
  command or one literal passes the bullet above and fails this one.
cleanup: `delete_output` the run directory of each of the two jobs (last media file
takes the run directory with it). The fixture bed is read-only.
metrics: none — the assertions are all pass/fail; S-P004 tracks audio-chain latency.
source: moved from S-F041 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #185 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`, workspace `qa-verify-185` (using
`asset:uploads/qa-cast/room-bed.wav` / `asset:qa-cast/hal-voice.wav`; the case uses
the suite's own fixture bed instead): job `242d79ae47d0` (`resample_audio`,
`device: "cpu"`) succeeded in 2.9 s; job `1b501f78d203` (`gain_audio` `device:
"cuda"` + `resample_audio` `device: "cuda:0"`) succeeded in 0.6 s. The implementer's
hand-off also proposed pinning that a command whose `arguments` is a list (the
`previous_result` fan-out into `gather_inputs`) survives the new wrapper; that path is
not constructible from an inline workflow (the schema requires `arguments` to be an
object), so it belongs in the dw repo's pytest suite, not here.

### C-F080 — `gain_audio` changes only the addressed region, and clips a region past the end
Before #187 there was no per-region gain task: ducking a scene meant a five-step
`slice_audio` → normalize → `mix_audio` → rejoin → `pair_audio` chain. `gain_audio`
applies `gain_db` to one region, addressed in seconds (`start_seconds`/`duration_seconds`)
or in frames (`start_frame`/`num_frames`/`fps`, resolved like `slice_audio`), and
leaves everything outside it untouched. Cheap: two utility jobs, ~1 s each, no model.
The fixture bed's per-second `rms_dbfs`/`peak_dbfs` envelope is flat enough that a
region's shift and its neighbours' stillness are both unambiguous — read it once
with `get_gallery_metadata("asset:qa-cast/ep11-bed.wav", envelope=true)` before
either job, and compare the outputs' envelopes against it.
expected:
- **Seconds, negative gain, middle region.** Inline workflow, one step `gain_audio`
  `{"audio": "asset:qa-cast/ep11-bed.wav", "gain_db": -12, "start_seconds": 5,
  "duration_seconds": 3}`, `result: {"subfolder": "final", "file_base_name": "ducked",
  "content_type": "audio/wav"}` → `succeeded`, one manifest file. Its envelope vs. the
  source's: seconds 5, 6 and 7 have `peak_dbfs` and `rms_dbfs` each **12 dB (±0.1)
  below** the source's same-second figures; **every other second is numerically
  identical** to the source (not "close" — the same float). `duration_seconds`,
  `sample_rate` and `channels` unchanged. A shift outside the region, a region that
  moved by less than the asked gain, or a changed duration is the finding.
- **Seconds, a video's stereo soundtrack.** The same seconds-form call on the
  soundtrack of `asset:qa-cast/ep31-shot1-return.mp4` (`"start_seconds": 2.0,
  "duration_seconds": 1.0`) returns 2 channels / 32 kHz / 5.167 s, with only the
  addressed bin moved by −12 ± 0.1 dB.
- **Frames, positive gain, region reaching past the end.** Same shape with
  `{"gain_db": 6, "start_frame": 400, "num_frames": 200, "fps": 24}` (frame 400 =
  16.667 s; the region would end at 25 s on a 19.67 s track) → `succeeded`, and
  `duration_seconds` **equal to the source's** (19.666656) — the region is clipped to
  the track, never zero-padded like `slice_audio`'s. Seconds 16 onward are +6 dB
  (±0.1) on peak; seconds 0–15 identical to the source. An output longer than the
  source is the regression.
- **Domains are pinned.** `validate_workflow` on the frames shape with
  `start_frame: -1, num_frames: 0` → `valid: false`, two errors at
  `steps[0].task.arguments.start_frame` and `.num_frames`, each naming `gain_audio`.
  (A no-region call — `gain_db` alone — validates and is refused at run time with a
  message naming both address forms; that is the current behaviour, an observation
  on #187, not an assertion here.)
cleanup: `delete_output` the run directory of each of the two jobs. The fixture bed
is read-only.
metrics: none — S-P004 tracks audio-chain latency.
source: moved from S-F042 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #187 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`, workspace `qa-verify-187`: job `6751bf30fdb4`
(seconds/−12 dB: seconds 5–7 peak −28.886 → −40.883, RMS −50.78 → −62.78, all others
identical; 1.1 s) and job `bc12d804d750` (frames/+6 dB past the end: duration still
19.666656 s, seconds 16–18 peak −28.886 → −22.884; 0.6 s). The implementer's
proposed sample-level assertions (scaled-by-linear-gain inside, bit-identical outside)
are the pytest form of the same properties and belong in the dw repo.
source: merged C-F061 (curation 2026-09-24)

### C-F081 — the stock `generate-speech` template runs on its VITS defaults, and no longer declares `voice_preset`
#226 moved `templates/generate-speech`'s default `model_name` from `suno/bark-small`
to `facebook/mms-tts-eng` (VITS) and dropped the template's `voice_preset` variable
(a single-voice model refuses it, so keeping it would have made the template's own
defaults reject themselves). This is S-F037's property — **a stored template must run
as shipped, without a caller supplying anything** — re-stated against the new default;
S-F037's Bark-specific assertions (24 kHz, ~8 s, `v2/en_speaker_6`) are wrong by design
from `2d57b39` on, and it was retired for that reason. The catalog's `audio`
shape still has only two entries, one of which is this, and #169 showed the failure
mode is total yet invisible to every case that authors its own workflow inline.
1. `get_workflow(name="templates/generate-speech", variables_only=true)`.
2. `validate_workflow(name="templates/generate-speech")`.
3. `run_workflow(workflow_path="templates/generate-speech", acknowledged_cost=true)`
   with **no `arguments` at all**; `wait_for_job`; `get_gallery_metadata` on the wav.
4. `validate_workflow(name="templates/generate-speech", arguments={"voice_preset":
   "v2/en_speaker_6"})`.
5. `run_workflow(...)` again with `arguments={"text": "One."}`; `get_gallery_metadata`.
expected:
- Step 1: variables are exactly `text` and `model_name`, `model_name` is
  `facebook/mms-tts-eng`, and there is **no** `voice_preset`. A Bark default or a
  reappearing `voice_preset` is the regression, whether or not the run passes.
- Step 2: `valid: true`, `plan.steps: 1`, `warnings: []`. The template's only step is
  the `generate_speech` *task*, and since #247 (S-F069) the no-seed warning is scoped to
  workflows with a pipeline step — so no "sets no 'seed'" entry here (#329). As in
  #169, a clean pre-flight is not evidence the run works — step 3 is what this case is
  for.
- Step 3: `status: "succeeded"`, `error: null`, `warnings: []`, a **non-empty**
  manifest (one `speak` entry, one `.wav`). Metadata: `kind: audio`, `sample_rate:
  16000` (VITS's native rate — the template declares no `result.sample_rate`, so a
  different figure means the saving path re-stamped it), `channels: 1`,
  `duration_seconds` roughly 4-5 s for the stock line (measured 4.624), `mean_dbfs`
  well above -40 (measured -18.3, `peak_dbfs` -1.3). Under 30 s end to end
  (measured 2.9 s warm) — minutes here is #132's complaint, file it separately.
- Step 4: `valid: false`, one error at `arguments.voice_preset` reading `Unknown
  variable 'voice_preset'; declared variables: model_name, text`. The old Bark knob
  is refused by the free pre-flight, not at model load.
- Step 5: `succeeded`, a much shorter wav (measured 0.16 s, `mean_dbfs` -15.6) —
  `text` still reaches VITS as a plain string and the output length tracks it.
cleanup: delete both runs with the `<workflow>/<run id>` form of `delete_output`.
Nothing here is a fixture.
metrics: none — the VITS path is a few seconds warm and a timing series on it
would only mirror model-load time; S-P004 remains the audio-chain timing.
source: moved from S-F065 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #226 on 2026-09-18
against dw 0.4.0-beta.6 (`develop` 2d57b39) on `lem`, jobs `0d6dfd28a919` and
`d1a35e432ebf` in a throwaway `qa-verify-226` workspace. The implementer's hand-off
proposed the default run and the audio checks; the `voice_preset` refusal and the
`text` override are mine.

### C-F082 — `generate_speech` reaches the model for every TTS family it drives, not just the template default
#232: transformers 5.17.0's `TextToAudioPipeline.preprocess` called
`BatchEncoding.to(dtype=...)`, which that class never accepted, so **every** model
`generate_speech` routes through `pipeline("text-to-audio", ...)` — SpeechT5, VITS,
Bark — died ~4 s in before any forward pass. #224 had scoped the breakage to Bark
("expendable") on the strength of #169, and C-F081 alone would have kept passing
had the default been a model that avoids that pipeline class. This case pins the
shared-pipeline property with the two non-default families, plus the version
exclusion the fix restored, so a future bump that reintroduces the bug (or lands
5.17.0 again) is caught whichever model the template defaults to.
1. `get_server_info`; read `runtime.packages.transformers`.
2. `run_workflow(workflow_path="templates/generate-speech", arguments={"model_name":
   "suno/bark-small", "text": "The quick brown fox jumps over the lazy dog."},
   acknowledged_cost=true)`; `wait_for_job`.
3. `run_workflow(inline_workflow=..., acknowledged_cost=true)` with one
   `generate_speech` step, `arguments={"text": "The quick brown fox jumps over the
   lazy dog.", "model_name": "microsoft/speecht5_tts", "device": "cuda"}`, result
   `{"content_type": "audio/wav", "subfolder": "final", "file_base_name":
   "speecht5-plain"}`; `wait_for_job`; `get_job` for the traceback.
expected:
- Step 1: the version is **not** `5.17.0`. (The floor is `>=5.16.1,!=5.17.0`; a
  later version that passes steps 2-3 is fine — the pin, not the number, is the
  property.)
- Step 2: `status: "succeeded"`, `error: null`, `warnings: []`, one `.wav` in the
  `speak` manifest entry. Bark is the slow family here — measured 7.2 s warm; under
  a minute is normal.
- Step 3: `status: "failed"` — SpeechT5 has no default voice — but the failure is
  the model's own: `error` reads `speaker_embeddings must be specified` and the
  traceback's last frames are `text_to_audio.py … _forward` →
  `modeling_speecht5.py … _generate_speech`. **A `TypeError` mentioning
  `BatchEncoding.to()` / `dtype`, or a traceback that ends in
  `text_to_audio.py … preprocess`, is the regression** even though the job "fails"
  either way — the discriminator is *where* it failed, not that it did. (Passing
  `speaker_embedding` and getting a wav is #223's case, not this one.)
cleanup: delete step 2's run with the `<workflow>/<run id>` form of `delete_output`;
step 3 writes nothing. Nothing here is a fixture.
metrics: none — C-F081 and S-P004 carry the audio timings; this case is about
which frame the failure lands in.
source: moved from S-F066 (curation 2026-09-22, harnest#2); tester, model `opus` via provider `anthropic`, verified in #232 on 2026-09-18
against dw 0.4.0-beta.6 (`develop` 7f588c2, transformers 5.16.1) on `lem`, jobs
`ebc313a45891` (Bark) and `d0425f18a275` (SpeechT5) in workspace `qa-verify-223`.
The implementer's hand-off proposed the default-template run, which C-F081 already
holds; the non-default families and the failure-location check are mine.

### C-F083 — `frame_grid` tiles a clip into one contact sheet, and clamps `count` to the clip
The task command that lets an agent look at a clip without authoring a frames-extraction
workflow (#245): N frames sampled evenly across the full duration, first and last frame
inclusive, tiled into one image with the timestamp burned into each tile. Cheap — no
model, runs in about a second on the 124-frame fixture.
expected: `get_task("frame_grid")` lists `video`, `count` (default 12), `columns`
(default null), `tile_width` (default 320), `label` (default true). Then run an inline
one-step workflow `{"id": "qa-s071-grid", "variables": {"count": 12, "columns": null,
"tile_width": 320}, "steps": [{"name": "grid", "task": {"command": "frame_grid",
"arguments": {"video": "asset:qa-cast/ep6-cold-open.mp4", "count": "variable:count",
"columns": "variable:columns", "tile_width": "variable:tile_width"}}, "result":
{"content_type": "image/png", "subfolder": "final"}}]}`:
- defaults → `succeeded`, a manifest of exactly one `.png`, and `get_output_image` on it
  reports `original_size: [1280, 543]` — 4 columns × 3 rows of 320×181 tiles (the
  fixture is 960×544, so `rows = isqrt(12) = 3`, `columns = ceil(12/3) = 4`, biased wide).
  The image shows 12 frames of the clip, each carrying a `MM:SS.s` label; the first reads
  `00:00.0` and the last `00:05.1` (frame 123 at 24 fps), so the sample spans the whole
  clip.
- `arguments: {"count": 200, "columns": 16, "tile_width": 80}` → `succeeded`, **not** an
  error: `count` is clamped to the clip's 124 frames, `original_size: [1280, 360]`
  (16 × 8 cells of 80×45), and the last row holds 12 tiles with 4 black cells on the
  right (left-justified).
- `validate_workflow` with `arguments: {"count": 0}` → `valid: false`, an error at
  `steps[0].task.arguments.count` (positive domain), before anything runs.
It becomes a **finding** if `frame_grid` is missing from `get_task`, if the default grid's
size departs from the formula (a different tile height, columns fewer than rows), if the
first/last labels do not reach the clip's ends, if an over-long `count` fails the run
instead of clamping, or if `count: 0` reaches the run.
metrics: `default_grid_seconds` — `finished_at - started_at` of the defaults job.
cleanup: `delete_output` on each run's `qa-frame-grid/<run id>` directory.
source: moved from S-F071 (curation 2026-09-22, harnest#2); tester, verified in #245 on 2026-09-19 over MCP as model `opus` via provider
`anthropic` — defaults `[1280, 543]` in 1.3 s, labels `00:00.0` → `00:05.1`; `count: 200`
clamped to a 16×8 grid at `[1280, 360]`; `count: 0` refused at validate.

### C-F084 — `pair_audio` `fit: "video"` warns in both directions, and stays quiet on an exact fit
`fit: "video"` is lossy in one direction only: padding a short track adds silence
(nothing lost), trimming a long one discards real content. Before #246 only the pad
branch warned; the trim — the destructive one — was server-log only, so a caller
could lose the loudest second of a score with `warnings: []`. Three one-step inline
`pair_audio` muxes over shared fixtures, no model, each about two seconds:
`{"name": "mux", "task": {"command": "pair_audio", "arguments": {"video": <V>, "audio":
<A>, "fit": "video"}}, "result": {"content_type": "video/mp4", "subfolder": "final"}}`.
expected:
- **Trim arm** — `V = asset:qa-cast/ep6-cold-open.mp4` (124 frames, 5.17 s), `A =
  asset:qa-cast/ep11-bed.wav` (19.67 s) → `succeeded`, and `warnings[]` on `get_job`
  carries a `pair_audio: 'fit' trimmed 14.50 s off the 19.67 s track to reach the
  5.17 s of video …` line. `get_job_events` has the structured form: `event: warning`,
  `kind: audio_trimmed_to_video`, `command: pair_audio`, `trimmed_seconds: 14.5`,
  `audio_seconds` ≈ 19.67, `video_seconds` ≈ 5.17.
- **Pad control** — `V = asset:qa-cast/ep11-coldopen.mp4` (472 frames, 19.67 s), `A =
  asset:qa-cast/hal-voice.wav` (6.48 s) → `succeeded`, the `audio_padded_to_video`
  warning (`'fit' padded the 6.48 s track with 13.19 s of silence …`) and **no**
  `audio_trimmed_to_video` warning.
- **Exact-fit control** — `V = asset:qa-cast/ep11-coldopen.mp4`, `A =
  asset:qa-cast/ep11-bed.wav` (19.667 s vs 19.6667 s) → `succeeded` with **neither**
  fit warning; the only warning is the unrelated mono→stereo duplication. This arm is
  what keeps the case from being #159-style noise: a sub-frame rounding difference
  must not be reported as a trim.
Ignore the `Duplicating a mono audio track …` warning in all three; it is about the
mp4 container, not `fit`.
It becomes a **finding** if the trim arm's warning is missing from `warnings[]` or
lacks `kind`/`trimmed_seconds` in the event, if the pad control gains a trim warning
or loses its pad warning, or if the exact-fit control warns about either direction.
A stock `templates/music-video` run now carries the trim warning by design (its
default 30 s song over a ~20.7 s cut) — that is expected, not a finding.
cleanup: `delete_output` on each run's `<workflow id>/<run id>` directory.
source: moved from S-F072 (curation 2026-09-22, harnest#2); tester, verified in #246 on 2026-09-20 over MCP as model `opus` via provider
`anthropic` — jobs `46ea12726874` (trim, 14.50 s), `3f70d7aac7bb` (pad, 13.19 s),
`fd1b43c9c80e` (exact, no fit warning).

### C-F085 — a seeded `generate_speech` is reproducible, and a near-silent audio deliverable is warned about
#261: the S-F007 chain, submitted three times with `seed: 7`, produced three different Bark
waveforms — one of them a 1.5 s slice of leading pause that `succeeded` with `warnings: []`.
The workflow seed was never reaching the transformers pipeline (no `generator=` kwarg
there, so the fix seeds torch's global RNG right before the call), and no post-write check
existed for the quiet end of the scale the way `audio_no_headroom` covers the loud end.
Cheap — three Bark runs of a one-line prompt (~8 s each warm) plus one `normalize_audio`.
1. Submit the S-F007 chain inline with `"seed": 7`, `line` = "The regression suite is
   running the smoke level.", and the `speak` step **also saved** (`result: {content_type:
   "audio/wav", sample_rate: 24000, subfolder: "raw"}`). `wait_for_job`.
2. Submit it twice more, each time with a **different workflow `id`** (e.g. `…-b`, `…-c`)
   and a different `speak` subfolder. An unchanged resubmission is served entirely from the
   step cache (`reused: true` on every step, sub-second, run_id pointing at run 1's files)
   and proves nothing about the seed — that is what the changed id is for. Confirm each of
   these runs has **no** `reused` step in its manifest.
3. `get_gallery_metadata(name=<raw speak wav>, envelope=true)` on all three.
4. Submit a fourth inline workflow: `"seed": 8`, `generate_speech` on the same `line`
   (saved, subfolder `raw`) → `normalize_audio` with `peak_dbfs: -60`, `sample_rate: 24000`,
   saved as `final`. `wait_for_job`, then `get_job`.
expected:
- Step 3: the three raw `speak` wavs are identical — same `duration_seconds`, same
  `peak_dbfs` and `mean_dbfs` to the last printed digit, same per-second `envelope`
  entries. (2026-09-21: 4.0 s, peak -5.374823488688958, mean -23.968651572244767.) The
  seed-7 chains keep `warnings: []`.
- Step 4: the seed-8 raw wav differs from the seed-7 one (a different duration or level —
  the seed steers the draw, the RNG is not pinned to one constant), and the job `succeeded`
  with a `warnings[]` entry naming the `final` file, its mean dBFS (well below -40, ≈-75),
  and the phrase "near-silent". The seed-7 chains, at a mean of ≈-24 dBFS, must not carry it.
It becomes a **finding** if any two of the three seed-7 raw wavs differ in any figure, if a
cache-served run was counted as one of the three, if the -60 dBFS deliverable succeeds with
`warnings: []`, or if a normal-level speech run picks up the near-silent warning.
cleanup: run the whole case in a throwaway workspace and delete it; otherwise
`delete_output` on all four runs.
metrics: none.
source: moved from S-F077 (curation 2026-09-22, harnest#2); tester, verified in #261 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, workspace `qa-verify-261`: jobs `753b45752457` (cold) / `6040f3b8c826` /
`bccfb02a4524` identical to full float precision; `6c7c59722d33` was the cache-served
resubmission; `44bdcd423ffd` warned at -75.34 dBFS.

### C-F086 — `get_output_frames` reads an `asset:` video by seam and by moment, with sound
`get_output_frames` is the only way to *see* a cut over MCP (#245), and its `seams` and
`hear` selectors are what a cut is checked with; neither had a case. Free — no job, two
calls on the fixture `asset:qa-cast/ep25-episode.mp4` (360 frames, second shot from frame
236). Pass `workspace="regression-complete"` on both.
1. `get_output_frames(name="asset:qa-cast/ep25-episode.mp4", seams=true, boundaries=[236],
   names=["tub","receipt"], max_dimension=256)`.
2. `get_output_frames(name="asset:qa-cast/ep25-episode.mp4", at=["frame:242", 14.9], hear=1,
   max_dimension=256)`.
expected:
- Step 1: one image (the frame pair either side of the join, tiled side by side, no wider
  than 256 px) plus a text block reporting `frame_count: 360  fps: 24.0` and one seam line
  naming `tub | receipt` at `frame 236 @ 9.83s` with a numeric `difference`.
- Step 2: two images and two `audio/wav` blobs, one pair per moment, plus a text block with
  `frame 242 @ 10.08s` and `frame 358 @ 14.92s` (a `frame:N` selector lands on frame N; a
  seconds selector lands on `round(t * fps)`) and a `hear: 1.0s around each moment` line. The
  second wav is shorter than the first — the window is clipped at the end of the track, not
  padded.
It becomes a **finding** if an `asset:` name is refused (only gallery names accepted), if
`seams` needs a job-owned output rather than an asset, if a `frame:N` selector is read as
seconds, if `hear` returns no audio, or if the frame indices drift from the arithmetic above.
cleanup: none — nothing is written.
metrics: none.
source: moved from S-F080 (curation 2026-09-22, harnest#2); tester, found while running TESTER_TASK.agent.md (ep25, 2026-09-21) over MCP as model
`opus` via provider `anthropic`, dw 0.4.0-beta.6 on `lem`: seam 1 reported `frame 236 @ 9.83s
difference: 5.06 [256x72]`; moments `frame 242 @ 10.08s` / `frame 358 @ 14.92s` with 125 KB
and 73 KB wavs.

### C-F087 — the envelope has `ceil(duration)` bins: a real partial tail stands alone, a whole-second track gets no phantom bin
The tool says the envelope is "what says whether a shot is still sounding at its last
frame". That reading depends on the bin count: #277 was one *extra* near-silent bin on a
15.0 s track (codec padding decoded past the reported duration, read as a hole at the
tail), and #278 was the over-correction — every sub-second tail folded into the previous
bin, so a 0.667 s fade on a 19.667 s track was averaged into a full-level second and
invisible. Free — two read-only calls on fixtures. Pass `workspace="regression-complete"`.
1. `get_gallery_metadata(name="asset:qa-cast/ep11-bed.wav", envelope=true)`.
2. `get_gallery_metadata(name="asset:qa-cast/ep25-episode.mp4", envelope=true)`.
expected:
- Step 1: `duration_seconds` ≈ 19.667, `envelope.interval_seconds: 1.0`, and `rms_dbfs` /
  `peak_dbfs` each have **20** entries (`ceil(19.667)`). Entries 0–18 sit around −48…−51
  dBFS rms; entry 19 is clearly lower (≈ −64 rms / ≈ −50 peak) — the real fade-out,
  reported on its own rather than blended into entry 18.
- Step 2: `duration_seconds: 15.0`, and `rms_dbfs` / `peak_dbfs` each have exactly **15**
  entries, all in the −21…−36 dBFS rms range; no trailing entry tens of dB below the rest.
It is a **finding** if step 1 returns 19 bins (the tail folded away again, #278), if step
2 returns 16 (the padding bin back, #277), or if `len(rms_dbfs) != len(peak_dbfs)`.
On step 2, any last entry more than ~15 dB below the one before it fails, whatever the
count (merged from C-F044 (curation 2026-09-22, harnest#2)).
cleanup: none — nothing is written.
metrics: `envelope_bins` — `len(rms_dbfs)` on step 2, condition
`ep25-episode.mp4/interval-1.0`; history in `regression-perf/C-F044.jsonl`. Any reading
other than 15 is a failure regardless of trend.
source: moved from S-F081 (curation 2026-09-22, harnest#2); tester, verified in #278 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, dw on `lem` at develop ffd7455: ep11-bed → 20 bins, last `rms -64.31 /
peak -50.22`; ep25-episode → 15 bins, last `rms -26.27`. Also observed then:
`ep21-shot1-receipt.mp4` 5.167 s → 6 bins, `ep15-song.mp3` 30.023 s → 31 bins.

### C-F088 — `get_output_frames` `crop` is in source pixels, cut per frame before any downscale or sheet layout
#303: `get_output_frames` gained `get_output_image`'s `crop` (`[x, y, width, height]`), and
the first landing cut it from tiles *already shrunk* to `max_dimension` — so one box named a
different region at every size — and, in `count` mode, from the assembled contact sheet, so
an in-bounds source box was refused as "outside the 256x48 image". The contract is the image
tool's: the box is in the decoded frame's own pixels, cut per frame before anything else.
Free — no job, four calls on the fixture `asset:qa-cast/ep25-episode.mp4` (960x544 source).
Pass `workspace="regression-complete"` on each.
1. `get_output_frames(name="asset:qa-cast/ep25-episode.mp4", at=[0.0], crop=[100,50,120,90],
   max_dimension=1024)`.
2. The same call with `max_dimension=256`.
3. `get_output_frames(name="asset:qa-cast/ep25-episode.mp4", count=3, crop=[100,50,120,90],
   max_dimension=256)`.
4. `get_output_frames(name="asset:qa-cast/ep25-episode.mp4", at=[0.0], crop=[5000,5000,10,10])`.
expected:
- Steps 1 and 2: one `[120x90]` tile each, text block reporting `crop: [100, 50, 120, 90]`,
  and the two images show the **same** region (upper-left of frame 0: red brick wall with
  the top-left corner of a picture frame in the lower right of the tile) — `max_dimension`
  must not move the box.
- Step 3: accepted (no error), a `[256x64]` contact sheet of three per-frame `120x90` crops
  with `frames: 0 (0.00s), 180 (7.50s), 359 (14.96s)` and the same `crop:` line; the first
  tile is the same brick/frame-corner region as steps 1–2.
- Step 4: an error naming the **source** frame — `crop origin (5000, 5000) lies outside
  the 960x544 frame.` — not a tile or sheet size.
It is a **finding** if steps 1 and 2 show different regions, if step 3 is refused (a crop
checked against the sheet) or its tiles are not per-frame crops, if the `crop:` telemetry
line is missing, or if step 4's error quotes anything other than the source dimensions.
cleanup: none — nothing is written.
metrics: none.
source: moved from S-F107 (curation 2026-09-22, harnest#2); tester, verified in #303 on 2026-09-22 over MCP as model `opus` via provider
`anthropic` against `develop @ 7e1a1a5` (dw 0.4.0-beta.6 on `lem`).

### C-F089 — a still image under a `video` argument is refused by the free pre-flight, and the `media_type` form that loads it runs
Before #347, `loop_frames`'s `video` argument was documented as accepting a still.
`validate_workflow` passed `"video": "asset:<x>.png"`, and the run then failed with "Video
file extension not allowed: .png". Validate now checks the extension of a `video`-keyed
literal or `asset:`/`output:` reference against the allowed video extensions, including
after a `variable:` has been resolved. For an image extension, the error names the form
that works. One ~3 s utility run, no model.
Each call below uses this workflow shape, with only `<V>` changed: `{"id": "lf", "steps":
[{"name": "hold", "task": {"command": "loop_frames", "arguments": {"video": <V>,
"num_frames": 121}}, "result": {"content_type": "video/mp4", "fps": 24}}]}`.
1. `validate_workflow` with `<V>` = `"asset:qa-cast/hal-portrait.jpg"`.
2. The same still passed indirectly: add `"variables": {"clip":
   "asset:qa-cast/hal-portrait.jpg"}` and set `<V>` = `"variable:clip"`.
3. `<V>` = `"asset:qa-cast/ep20-score.wav"` (a non-image, non-video extension).
4. `<V>` = `"asset:qa-cast/ep6-cold-open.mp4"` (a real video).
5. `<V>` = `{"media_type": "image", "location": "asset:qa-cast/hal-portrait.jpg"}`. Validate
   it, then `run_workflow` it in this suite's workspace. Read the output with
   `get_gallery_metadata`.
expected:
- Steps 1–2: `valid: false`, with one error at `steps[0].task.arguments.video`. The message
  says the value is a still image and names `{"media_type": "image", "location":
  "asset:qa-cast/hal-portrait.jpg"}` as the form that loads it.
- Step 3: `valid: false` at the same path, "Video file extension not allowed: .wav".
- Step 4: `valid: true`. A real video is not refused.
- Step 5: `valid: true`. The job succeeds, and the output's `media.frame_count` is `121`.
It is a **finding** if step 1 or step 2 validates, since that would mean the failure has
moved back to run time. It is also a finding if step 4 is refused, or if step 5 fails or
returns a frame count other than 121.
cleanup: `delete_output(job_id=...)` on step 5's job. The assets are shared fixtures, so
leave them.
metrics: none.
source: moved from S-F111 (curation 2026-09-22, harnest#2); tester, verified in #347 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (job 4ae03c56e4a1: 121 frames, 24 fps,
768x768).

### C-F090 — media loads by the argument a variable lands in, not by the variable's name
Before #365, the engine applied its media-loading name rules (`image`/`*_image`,
`video`/`*_video`, `*_type`/`*_dtype`) to the variables dict, keyed by the *variable* name.
So a variable named `image` feeding a `video` argument was loaded as a PIL image, and the
job failed with `Video specification must be a string, got <class 'PIL.Image.Image'>`.
Cheap: two utility jobs of a few seconds each, no model.
1. Validate and then run `{"id": "qa-sf115-chain", "variables": {"image":
   "asset:qa-cast/ep6-shot1-priya.mp4", "video": "asset:qa-cast/ep6-cold-open.mp4"},
   "steps": [{"name": "bed", "task": {"command": "normalize_audio", "arguments": {"audio":
   "variable:video"}}}, {"name": "frames", "task": {"command": "loop_frames", "arguments":
   {"video": "variable:image", "num_frames": 48}}}, {"name": "out", "task": {"command":
   "pair_audio", "arguments": {"video": "previous_result:frames", "audio":
   "previous_result:bed", "fit": "video"}}, "result": {"content_type": "video/mp4"}}]}`.
   Read the mp4 with `get_gallery_metadata`.
2. Validate and then run `{"id": "qa-sf115-names", "variables": {"hero_image":
   "asset:cast/pat.jpg", "reference_type": "float16"}, "steps": [{"name": "size", "task":
   {"command": "get_image_size", "arguments": {"image": "variable:hero_image"}}, "result":
   {"content_type": "application/json"}}, {"name": "label", "task": {"command":
   "compose_text", "arguments": {"parts": ["kind=", "variable:reference_type"],
   "separator": ""}}, "result": {"content_type": "text/plain"}}]}`. Read both outputs with
   `get_output_text`.
expected:
- Step 1: `valid: true`, and the job succeeds with no warnings. The mp4 has
  `media.frame_count` 48, a width and height (960x544 from this source), and an audio
  stream (`sample_rate` is not null).
- Step 2: the job succeeds. `size` is `{"width": 768, "height": 768}`, so a `*_image`
  variable fed to an `image` argument still loads as an image. `label` is exactly
  `kind=float16`, so a `_type` variable stays a string and is not turned into a torch dtype.
It is a **finding** if step 1 fails with any message about a PIL image or a
"Video specification", or if step 2's label reads `torch.float16` or the job fails.
cleanup: `delete_output(job_id=…)` on both jobs. The assets are shared fixtures, so leave
them.
metrics: none.
source: moved from S-F115 (curation 2026-09-22, harnest#2); tester, verified in #365 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (jobs `bcb37cf0f8a5`, `1bc5b2354d70`).

### C-F091 — a composed child is priced for the `cost_driver` values its composing step passes, not its defaults
#341: a `workflow` step composing `templates/minimax/video-with-audio` with
`arguments: {"num_frames": 345}` was quoted at the child's default-frames figure, first
from the catalog and then, after the first fix, from the default bucket's observed
history. A 12-shot parent came out at about a third of its real cost. This case is
C-F054's check applied through composition. It costs nothing: five validate calls, no
run, inline workflows, no fixture.
1. `validate_workflow(name="templates/minimax/video-with-audio", arguments={"num_frames": 345})`.
   This is the top-level reference figure.
2. `validate_workflow(name="templates/minimax/video-with-audio")`, with no arguments.
   This is the default reference figure.
3. `validate_workflow(workflow={"id":"qa-c-f091-single","steps":[{"name":"shot","workflow":{"path":"templates/minimax/video-with-audio","arguments":{"num_frames":345,"prompt":"x"}}}]})`.
4. `validate_workflow(workflow={"id":"qa-c-f091-default","steps":[{"name":"shot","workflow":{"path":"templates/minimax/video-with-audio","arguments":{"prompt":"x"}}}]})`.
5. `validate_workflow(workflow={"id":"qa-c-f091-mix","variables":{"shots":[{"prompt":"a","nf":345},{"prompt":"b","nf":124}]},"steps":[{"name":"shot","for_each":"variable:shots","workflow":{"path":"templates/minimax/video-with-audio","arguments":{"num_frames":"item:nf","prompt":"item:prompt"}}}]})`.
expected:
- Step 3's `plan.estimate` `minutes` and `basis` equal step 1's. If step 1 is `unknown`
  with `minutes: null`, step 3 is too. Step 4's equal step 2's.
- Step 5: if steps 1 and 2 are both priced, `minutes` is their sum (within 0.1) and
  `partial: false`. If step 1 is `unknown`, `partial: true` and
  `templates/minimax/video-with-audio` is in `unpriced`, with `minutes` equal to step 2's.
It is a **finding** if step 3's `minutes` equals step 2's while step 1's differs, or if
step 5 comes to twice step 2's figure. Either one is #341: a composed child quoted at its
default's figure for a driver value it was not measured at.
cleanup: none. Nothing is created.
metrics: none.
source: tester, verified in #341 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7` (RTX 3090). Step 1 gave 19.0 observed,
step 2 gave 6.6 observed, step 3 gave 19.0, step 4 gave 6.6, and a 345/345/124 mix gave
44.6. A child at `num_frames: 243`, which had no bucket, came back `unknown`, the same as
the top level.

### C-F092 — `result.fps` takes a `variable:` reference, the written file carries the resolved rate, and a bad rate is refused at validate
Before #363, `result.fps` accepted only an integer literal. `"fps": "variable:fps"` failed
the schema check, so a template's `frame_rate` variable could not reach the file it wrote.
The ltx2 templates, `assemble-and-score` and `dissolve-between-shots` now point `result.fps`
at their rate variable. A resolved rate must be a positive whole number, because the
writer truncates a fraction. Cheap: one ~3 s utility run with no model, plus free
validates.
Workflow W: `{"id": "qa-c-f092", "variables": {"fps": 24}, "steps": [{"name": "qr",
"task": {"command": "qr_code", "arguments": {"qr_code_contents": "fps"}}}, {"name": "vid",
"task": {"command": "loop_frames", "arguments": {"video": "previous_result:qr",
"num_frames": 30}}, "result": {"content_type": "video/mp4", "fps": "variable:fps"}}]}`.
1. `validate_workflow` W with `arguments: {"fps": 12}`. Then `run_workflow` it with the
   same arguments, and read the mp4 with `get_gallery_metadata`.
2. `validate_workflow` W with `arguments: {"fps": 0}`.
3. `validate_workflow` W with the variable default changed to `23.976` and no arguments.
4. `validate_workflow(name="templates/ltx2/chained-segments", arguments={"frame_rate": 29.97})`,
   then the same call with `{"frame_rate": 30}`.
expected:
- Step 1: `valid: true`. The job succeeds, and the mp4's `media.fps` is `12.0`,
  `frame_count` is `30` and `duration_seconds` is `2.5`.
- Step 2: `valid: false` at `steps[1].result.fps`, with a message saying fps must be
  greater than zero.
- Step 3: `valid: false` at `steps[1].result.fps`, with a message saying fps must be a whole
  number.
- Step 4: the 29.97 call is `valid: false` at `steps[0].result.fps`, which shows the
  template's `result.fps` follows `frame_rate`. The 30 call is `valid: true`.
It is a **finding** if step 1 fails validation with a type error on `result.fps`, or if the
file is written at 24 or 8 fps. It is also a finding if step 2 or 3 validates, or if step 4's
29.97 call validates.
cleanup: `delete_output(job_id=…)` on step 1's job.
metrics: none.
source: tester, verified in #363 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7` (job `ca6861eb89fa`: 12.0 fps, 30 frames,
2.5 s, 768x768).

### C-F093 — `grade` grades a video file per frame, keeping frames, fps and audio, and refuses an out-of-range white balance at validate
#349 added the CPU `grade` task. At first it took only `image`, so an `.mp4` passed validate
and then failed at run time with "Image file extension not allowed". `temperature` and `tint`
were also extrapolated past their documented range of -1.0 to 1.0. The input is now `media`,
which takes an image or a video file. Cheap: two utility runs of about 3 s each with no model,
plus free validates.
1. `validate_workflow`, then `run_workflow` `{"id": "qa-c-f093", "steps": [{"name": "grade",
   "task": {"command": "grade", "arguments": {"media": "asset:qa-cast/ep6-cold-open.mp4",
   "saturation": 0, "temperature": -1}}, "result": {"content_type": "video/mp4"}}]}`. Read
   the mp4 with `get_gallery_metadata` and look at one frame with `get_output_frames`.
2. Run the same shape again with `media` set to `output:<step 1's mp4>` and arguments
   `"temperature": 1, "tint": -1, "contrast": 1.3`. Read it the same way.
3. `validate_workflow` with the step 1 shape, but with arguments `{"media":
   "asset:qa-cast/hal-portrait.jpg", "temperature": 5, "tint": -3}`.
4. `validate_workflow` with the step 1 shape, but with arguments `{"media":
   "asset:qa-cast/hal-portrait.jpg", "contrast": -0.5}`.
expected:
- Step 1: `valid: true`. The job succeeds. The mp4 has `frame_count` 124, `fps` 24.0, is
  960x544, and has 32000 Hz stereo audio. The source is the same on all four. The frame is
  greyscale.
- Step 2: the job succeeds with the same frame count, fps, size and audio. The frame has
  turned yellow-green from the grey, which is warm plus green, and the ±1.0 boundary values
  are accepted.
- Step 3: `valid: false`. There is one error each at `steps[0].task.arguments.temperature`
  and `.tint`, and each names the -1.0 to 1.0 range.
- Step 4: `valid: false` at `steps[0].task.arguments.contrast`. The exact wording is
  not part of this case; #383 covers it.
It is a **finding** if step 1 or 2 fails, drops the audio (`sample_rate` null), or changes
the frame count or fps. It is also a finding if step 3 or 4 validates.
cleanup: `delete_output(job_id=…)` on both jobs, step 2's first. The assets are shared
fixtures, so leave them.
metrics: none.
source: tester, verified in #349 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 0963746` (jobs `f345420a96a0`, `d43cf8781e64`: 124
frames, 24.0 fps, 960x544, 32 kHz stereo, 5.167 s).

### C-F094 — `pair_audio` with `fit` unset uses the track as it is, and warns when its length disagrees with the frames
C-F084 covers `fit: "video"`. This case covers the other branch, which the task's own
schema promises: "left unset the track is used as it is, and a length that disagrees
with the frames' is warned about rather than passing in silence". That silent path is
#142's failure shape. It is one inline mux with no model and takes about 4 s: `{"id":
"qa-c-f094", "seed": 1, "steps": [{"name": "pair", "task": {"command": "pair_audio",
"arguments": {"video": "asset:qa-cast/ep37-episode.mp4", "audio":
"asset:qa-cast/ep35-ducked.wav"}}, "result": {"content_type": "video/mp4", "subfolder":
"final"}}]}`. The video is 248 frames at 24 fps (10.33 s). The track is 9.83 s at 32 kHz.
expected:
- `validate_workflow` returns `valid: true`, and the job `succeeded`.
- `warnings[]` carries `pair: pair_audio: the track is 9.83 s and the video it is laid
  over is 10.33 s (248 frames at 24 fps) …`, which names `'fit': 'video'` as the remedy.
- `get_job_events` has the structured form: `event: warning`, `kind:
  audio_video_length_mismatch`, `command: pair_audio`, `audio_seconds` ≈ 9.83 and
  `video_seconds` ≈ 10.33.
- In `get_gallery_metadata` the output has `frame_count` 248, `fps` 24.0 and 32000 Hz
  stereo audio. Its audio is not padded or trimmed, so `peak_dbfs` stays below 0.
It is a **finding** if the job succeeds with no length warning, if the warning lacks its
`kind` or either duration, or if an unset `fit` pads or trims the way `"video"` would.
cleanup: `delete_output(job_id=…)`. Both assets are shared fixtures, so leave them.
metrics: none.
source: tester, found while running TESTER_TASK.agent.md (ep37); verified on 2026-09-23
over MCP as model `claude-opus-5-5` via provider `anthropic` (job `5eb50a6fbc7b` in
`qa-ep37`: 248 f, 24.0 fps, 32 kHz stereo, peak −1.84 dBFS).

### C-F095 — a `concat_videos` cut records its shots, and `seams=true` works without `boundaries`
source: tester, spec for #385 from #378's plan v2
Output assessment, stage A. A cut made by `concat_videos` now records its shots, each
with a name, a start frame and a frame count. They appear in the output's manifest and
in `get_gallery_metadata`'s `media.shots`. `get_output_frames(seams=true)` then finds
the seams from those shots. Before this, it returned a 400 unless the caller passed
`boundaries`. The case is CPU only and takes a few seconds. Workflow W (the gather cut):
`{"id": "qa-c-f095", "variables": {"clips": [{"name": "incident", "clip":
"asset:qa-cast/ep3-shot1-incident.mp4"}, {"name": "reply", "clip":
"asset:qa-cast/ep3-shot2-reply.mp4"}]}, "steps": [{"name": "shot", "for_each":
"variable:clips", "task": {"command": "grade", "arguments": {"media": "item:clip",
"contrast": 1}}, "result": {"content_type": "video/mp4", "fps": 24, "subfolder":
"intermediate", "save": false}}, {"name": "cut", "task": {"command": "concat_videos",
"arguments": {"videos": "gather:shot", "fps": 24}}, "result": {"content_type":
"video/mp4", "fps": 24, "subfolder": "final"}}]}`. Each fixture clip is 124 frames at
24 fps.
1. `validate_workflow(W)` returns `valid: true`. Then `run_workflow(inline_workflow=W,
   acknowledged_cost=true, wait_seconds=55)` returns `succeeded` with one `final` file,
   which is 248 frames.
2. `get_gallery_metadata(<cut>)`.
3. `get_output_frames(name=<cut>, seams=true)`, with no `boundaries`.
4. `get_output_frames(name=<cut>, seams=[1])`, with no `boundaries`.
expected:
- Step 2: `media.shots` has exactly 2 entries, in order. The first is `shot@incident`,
  starting at frame 0 with 124 frames. The second is `shot@reply`, starting at frame 124
  with 124 frames. The frame counts sum to the file's `frame_count` (248). The run's
  manifest, from `get_job`, carries the same `shots` for the cut file.
- Step 3 returns one seam, at frame 124 (5.17 s), labelled `shot@incident | shot@reply`
  (or those names in the tool's own seam-label form, as in C-F086). It carries the frames
  on either side of the seam and a `difference`. It is not a 400.
- Step 4 returns that same seam.
It is a **finding** if `shots` is missing or has the wrong count or names, if the frame
counts don't sum to 248, or if `seams=true` without `boundaries` still returns 400 for
this cut.
cleanup: `delete_output(job_id=…)`. The clips are shared fixtures, so leave them.
metrics: none.

### C-F096 — a `dissolve_videos` cut records its shots, and `boundaries` still overrides them
source: tester, spec for #385 from #378's plan v2
Stage A, the dissolve branch. It checks that the shot frame counts still sum to the
file's frames when neighbouring shots overlap, and that a caller's explicit `boundaries`
still wins over the recorded shots. The case is CPU only. Workflow D: `{"id":
"qa-c-f096", "steps": [{"name": "edit", "task": {"command": "dissolve_videos",
"arguments": {"videos": ["asset:qa-cast/ep3-shot1-incident.mp4",
"asset:qa-cast/ep3-shot2-reply.mp4", "asset:qa-cast/ep3-shot1-incident.mp4"],
"dissolve_frames": 12, "fps": 24}}, "result": {"content_type": "video/mp4", "fps": 24,
"subfolder": "final"}}]}`. If `get_task("dissolve_videos")` names the list or overlap
argument differently, use its names. The shape of the case stays the same. Three
124-frame clips with two 12-frame dissolves give 3·124 − 2·12 = 348 frames.
1. `validate_workflow(D)`, then `run_workflow(inline_workflow=D, acknowledged_cost=true,
   wait_seconds=55)` returns `succeeded`, and the file is 348 frames.
2. `get_gallery_metadata(<cut>)`.
3. `get_output_frames(name=<cut>, seams=true)`, with no `boundaries`.
4. `get_output_frames(name=<cut>, seams=true, boundaries=[100])`.
expected:
- Step 2: `media.shots` has 3 entries in input order. Their frame counts sum to exactly
  348. Their starts rise strictly, and the last shot ends at frame 348. Asset-literal
  inputs give no `shot@` names, so whatever names they carry are not asserted.
- Step 3 returns 2 seams, one at each dissolve. The first is near frame 112 (124 − 12),
  within the dissolve's 12 frames. The second is near 224.
- Step 4 returns one seam, at frame 100. The explicit `boundaries` override the recorded
  shots.
It is a **finding** if the frame counts sum to 372 (overlaps counted twice) or to any
figure other than the file's frames, if there is no `shots` entry, or if an explicit
`boundaries` is ignored in favour of the shots.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F097 — shot edges: trimmed cuts, a single-shot cut, `slice_audio`, and media with no shots
source: tester, spec for #385 from #378's plan v2
Stage A's implied edges:
- a shot's frame count is what landed in the file, after `trim_frames`;
- a one-shot cut has no seams, which is an empty answer rather than an error;
- `slice_audio` drops `shots`, as the plan says;
- media made before the feature carries no shots, so `seams=true` without `boundaries`
  must still refuse it clearly.

The case is CPU only, with three short jobs.
1. **Trimmed.** Inline one step `concat_videos` `{"videos":
   ["asset:qa-cast/ep3-shot1-incident.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"],
   "trim_frames": 4, "fps": 24}`, `result: {"content_type": "video/mp4", "fps": 24,
   "subfolder": "final"}`. Check `get_task("concat_videos")` for how `trim_frames`
   applies. Run it with `wait_seconds=55`, then call `get_gallery_metadata`.
   Expected: the `media.shots` frame counts sum to exactly the file's `frame_count`, and
   `seams=true` puts its one seam at the first shot's recorded length.
2. **One shot.** The same step with `"videos": ["asset:qa-cast/ep3-shot1-incident.mp4"]`,
   and no trim. Expected: `media.shots` has 1 entry of 124 frames.
   `get_output_frames(seams=true)` returns zero seams, as an empty list or a message
   saying there are none. It is not a 400 asking for `boundaries`, and not a 500.
3. **`slice_audio` drops shots.** Inline one step `slice_audio` `{"audio": "output:<step
   1's cut>", "start_seconds": 1, "duration_seconds": 3}`, `result: {"content_type":
   "audio/wav", "subfolder": "final"}`. Expected: `succeeded`. `get_gallery_metadata`
   on the result has no `media.shots` (absent or empty), and neither has its manifest
   entry.
4. **No shots recorded.** `get_output_frames(name="asset:qa-cast/ep25-episode.mp4",
   seams=true)` without `boundaries`. That fixture predates the feature, and the plan
   defers an mp4-embedded shot tag. Expected: a clear 400 that names `boundaries` as
   the remedy. Then the same call with `boundaries=[236]` returns the seam at frame 236,
   which is C-F086's result.
It is a **finding** if any step 1 shot count disagrees with the file's frames, if a
one-shot cut raises, if an audio slice carries `shots`, or if step 4 returns a 500 or an
empty success instead of naming `boundaries`.
cleanup: `delete_output(job_id=…)` for each of the three jobs. Delete step 3's job
before step 1's.
metrics: none.

### C-F098 — the probes are listed as `assessment` tasks, and a probe must save JSON
source: tester, spec for #387 from #378's plan v2
Stage B adds three probe tasks: `analyze_shots`, `analyze_seams` and
`analyze_sync_drift`. `list_tasks` gets a fourth list, `assessment`, which holds them.
A probe's result is a JSON document, so a probe step saved under any other content type
must fail validation. This case runs nothing and makes no GPU calls.
1. `list_tasks()`. Expected: a fourth list keyed `assessment` holds exactly the three
   probes. The three lists that were there before keep their contents.
2. `get_task` for each probe. Expected: each returns a schema, not "Unknown task
   command", with an argument that takes the media to probe.
3. `validate_workflow` on a one-step workflow `{"id": "qa-c-f098", "steps": [{"name":
   "probe", "task": {"command": "analyze_seams", "arguments": {<media arg>:
   "asset:qa-cast/ep25-episode.mp4"}}, "result": {"content_type": <ct>}}]}`, three
   times:
   - with `application/json`, expect `valid: true`;
   - with `text/plain`, expect `valid: false`, with an error on `steps[0].result` (or its
     `content_type`) that names `application/json`;
   - with `video/mp4`, expect `valid: false` in the same form.
   Repeat the `text/plain` validation for `analyze_shots` and `analyze_sync_drift`. It
   must fail there too.
It is a **finding** if the `assessment` list is missing or incomplete, if any probe is
unknown to `get_task`, or if a non-JSON content type validates.
cleanup: none.
metrics: none.

### C-F099 — `analyze_seams` flags a level step at the one seam that has it; a clean cut has no finding
source: tester, spec for #387 from #378's plan v2
Stage B's acceptance intent has two parts:
- a `gain_audio` step between two shots flags `seam_level_step` at that seam only;
- a clean cut has no drift finding.

Both halves are built from one clip repeated three times, so every shot starts at the
same level and the only step is the one made on purpose. The case is CPU only.

Workflow S has these steps:
1. `cut`: `concat_videos` `{"videos": ["asset:qa-cast/ep3-shot1-incident.mp4",
   "asset:qa-cast/ep3-shot1-incident.mp4", "asset:qa-cast/ep3-shot1-incident.mp4"],
   "fps": 24}`, with `video/mp4` in `final`. This makes 372 frames with seams at
   frames 124 and 248.
2. `stepped_audio`: `gain_audio` `{"audio": "previous_result:cut", "gain_db": -12,
   "start_frame": 248, "num_frames": 124, "fps": 24}`. The last shot drops 12 dB, so
   the only level change is at seam 2.
3. `stepped`: `pair_audio` `{"video": "previous_result:cut", "audio":
   "previous_result:stepped_audio"}`, with `video/mp4` in `final`.
4. `seams_clean`: `analyze_seams` on `previous_result:cut`.
5. `seams_stepped`: `analyze_seams` on `previous_result:stepped`.
6. `drift_clean`: `analyze_sync_drift` on `previous_result:cut`.
7. `shots_clean`: `analyze_shots` on `previous_result:cut`.

Each probe step saves `application/json` to `final`. Use the media-argument name that
`get_task` gives.

Run it with `validate_workflow`, then `run_workflow(..., acknowledged_cost=true,
wait_seconds=55)`, then read each probe's JSON with `get_output_text`.
expected:
- `seams_stepped` has a `seam_level_step` finding at seam 2 (frame 248). Its reported
  step is about 12 dB (±1.5). There is no `seam_level_step` at seam 1 (frame 124).
- `seams_clean` has no `seam_level_step` at either seam.
- `drift_clean` has no drift finding. The file's own sync is intact.
- `shots_clean` reports 3 shots, which match the cut's `media.shots` in starts and
  frame counts, and puts them within 1 dB of each other in level.
- Every seam a probe names lies within the file (0 < frame < 372).
It is a **finding** if the stepped seam isn't flagged, if seam 1 is flagged too, if the
clean cut has any level-step or drift finding, or if a probe returns something that
isn't JSON.
Positive checks for holes, clicks and video jumps aren't built here; see the note on
#378. A later case can add them.
cleanup: `delete_output(job_id=…)`.
metrics: `seam_level_step_db` (seam 2 of `seams_stepped`), from the probe's JSON.

### C-F100 — the level-spread threshold is one 6 dB line
source: tester, spec for #387 from #378's plan v2
Plan v2's answer to Q3 is one level-spread threshold, kept at 6 dB. This case checks
both sides of that line, plus the real-world pair it was drawn from:
`ep3-shot1-incident` and `ep3-shot2-reply`, whose mean levels are about 11 dB apart. It
is CPU only, and each workflow is a `concat_videos` of two shots followed by
`analyze_shots` saving JSON. A 2-shot spread is made by ducking the second shot's
region with `gain_audio` and pairing it back, as C-F099 does, starting at frame 124 of
an incident+incident cut.
- **Below.** Incident + incident with the second shot at −5 dB: no level-spread finding.
- **Above.** The same with −7 dB: a level-spread finding that names both shots and a
  spread of about 7 dB.
- **Real pair.** Incident + reply, joined with no `match_levels`: a level-spread finding
  of about 11 dB. The same pair joined with `match_levels: "rms"` has none.
It is a **finding** if −5 dB is flagged, if −7 dB isn't, if the unmatched ep3 pair
isn't, or if the threshold is plainly not 6 dB (the flip point lies outside 5–7). If the
implementer puts the spread finding in `analyze_seams` rather than `analyze_shots`,
read it there. The finding matters, not which probe carries it.
cleanup: `delete_output(job_id=…)` for each job.
metrics: `level_spread_db` for the real pair (unmatched), as a trend.

### C-F101 — `assess_output` judges a cut, says which rules it applied, and gives each probe's full body on request
source: tester, spec for #388 from #378's plan v2
Stage C adds the tool `assess_output(name, probe=None, detail=False, workspace=None)`,
which runs the probes over an existing output and applies the rules. Setup: run
C-F099's workflow S, or only its steps 1–3 if you want to skip the probes. That gives a
clean `cut` and a `stepped` cut with a 12 dB step at seam 2.
1. `assess_output(name=<stepped>)`.
2. `assess_output(name=<cut>)`.
3. `assess_output(name=<stepped>, detail=true)`.
4. `assess_output(name=<stepped>, probe="analyze_seams")`, and the same call with
   `analyze_shots` and `analyze_sync_drift`.
5. `assess_output(name="asset:qa-cast/ep25-episode.mp4")`.
6. `assess_output(name="asset:qa-cast/hal-portrait.jpg")`.
expected:
- 1: the result lists the `seam_level_step` finding at seam 2 and not at seam 1. It
  carries `rules_applied`, a non-empty list that names the seam rule.
- 2: no seam or drift finding, and `rules_applied` is still present.
- 3: more than step 1 (per-shot or per-seam figures), with the same findings.
- 4: each call returns that probe's full JSON body. The seams body agrees with C-F099's
  `seams_stepped`.
- 5: works on an `asset:` name. This is a 2-shot dissolve with no recorded shots, so
  it returns a result that says which rules were skipped for lack of shots. It doesn't
  raise, and it doesn't invent seams.
- 6: a still returns `not_applicable` for the video and seam rules, not an error.
- None of these calls creates a job: `list_jobs` shows no new entry.
It is a **finding** if the step-1 seam finding or `rules_applied` is missing, if the
still or the asset errors, or if a `probe=` call returns a summary rather than the
body.
cleanup: `delete_output(job_id=…)` on the setup run.
metrics: none.

### C-F102 — `assess_output` refusals, and it runs while the engine is busy
source: tester, spec for #388 from #378's plan v2
These are the refusals and the concurrency promise from stage C. The probe name is
checked first, so a bad probe is what gets reported, whatever else is wrong with the
call.
1. `assess_output(name="asset:qa-cast/ep25-episode.mp4", probe="analyze_everything")`
   returns a 400 whose message names the whitelist: `analyze_shots`, `analyze_seams`
   and `analyze_sync_drift`.
2. `assess_output(name="no-such/run/file.mp4", probe="analyze_everything")` returns
   the same probe 400. It is not a not-found error, because the probe is checked first.
3. `assess_output(name="no-such/run/file.mp4")` returns a clear not-found that names
   the input. It is not a 500.
4. **While busy.** Queue a run that keeps the engine busy for at least 10 s, such as
   `run_workflow(workflow="templates/dissolve-between-shots", arguments={"shots":
   ["asset:qa-cast/ep3-shot1-incident.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"],
   "score": "asset:qa-cast/ep20-score.wav", "total_frames": 236},
   acknowledged_cost=true, wait_seconds=0)`. Immediately, before waiting, call
   `assess_output(name="asset:qa-cast/ep25-episode.mp4")`. Then `get_job(<queued
   job>)`. Expected: `assess_output` returns its result while the job is still
   `running` or `queued`. It is not queued behind the job, and it doesn't add a job to
   `list_jobs`. Then `wait_for_job` the run to `succeeded`. If the run ended before
   the `assess_output` call, repeat with a longer run; the timing, not the tool, is at
   fault.
It is a **finding** if an unknown probe is accepted, if its 400 doesn't name the
whitelist, if step 2 reports the missing file instead of the probe, or if step 4's
call waits for the job or queues its own.
cleanup: `delete_output(job_id=…)` on step 4's run.
metrics: none.

### C-F103 — the guide and `get_gallery_metadata` point at `assess_output`
source: tester, spec for #388 from #378's plan v2
Stage C's discoverability promises. Step 3 needs a cut with recorded shots: C-F101's
setup (C-F099 workflow S, steps 1–3), or that run if it is still present.
1. `list_guides()`. One guide's sections include `Assessing a run's output`.
2. `get_guide(<that guide>, section="Assessing a run's output")` returns the section,
   which names `assess_output` and the three probes.
3. `get_gallery_metadata(<stepped>)`, a cut whose `media.shots` is set. Its `next` names
   `assess_output`.
It is a **finding** if the section is missing, or if a cut's `next` doesn't mention
`assess_output`.
cleanup: `delete_output(job_id=…)` on the setup run, if this case made it.
metrics: none.

### C-F104 — `assess_output` over fixture cuts: a tracked reading and a positive control
source: tester, spec for #386 from #378's plan v2
Stage D is a field test. The tester runs `assess_output` over a `music-video`, a
`dialogue-short`, a chained-segments run and the #197 repro cut, and reports the
numbers. The thresholds are settled from those numbers. That one-off field run is the
stage's verification, not a suite case. This case is the durable remainder: after the
thresholds are settled, the fixture cuts keep assessing as they did, and the known-bad
pair keeps being flagged. It is CPU only.
1. `assess_output(name=…, detail=true)` on each of `asset:qa-cast/ep25-episode.mp4`,
   `asset:qa-cast/ep13-episode.mp4` and `asset:qa-cast/ep37-episode.mp4`. Each returns
   a result with `rules_applied`. Every finding names a seam or shot inside the file's
   frames.
2. **Positive control.** Inline `concat_videos` of `ep3-shot1-incident.mp4` +
   `ep3-shot2-reply.mp4` (no `match_levels`, `fps` 24, `video/mp4` in `final`), then
   `assess_output(name=<cut>)`. The result has a level-spread finding of about 11 dB, at
   or above the settled threshold.
It is a **finding** if the positive control isn't flagged after the thresholds are
settled, or if a fixture cut's findings change without a verified threshold change.
Record each reading in `regression-perf/C-F104.jsonl`. A reading that moves by more than
the per-case rule is a regression to file.
cleanup: `delete_output(job_id=…)` on the control's run. The fixtures are shared.
metrics: per fixture cut, the count of findings and the largest `seam_level_step_db`
and `level_spread_db` that `detail=true` reports; the control's `level_spread_db`.

### C-F105 — a joined shot from an `asset:` input is named by its file name, not its server path
source: tester, verified in #390
An asset-literal input to a join used to be named by its resolved absolute server path.
That path showed up in the manifest's `shots`, in `get_gallery_metadata`'s `media.shots`
and in every seam label. The case is CPU only and takes two short jobs.
1. `run_workflow(inline_workflow={"id": "qa-c-f105", "steps": [{"name": "cut", "task":
   {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep3-shot1-incident.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"], "fps":
   24}}, "result": {"content_type": "video/mp4", "fps": 24, "subfolder": "final"}}]},
   acknowledged_cost=true, wait_seconds=55)`.
2. `get_gallery_metadata(<cut>)`, then `get_output_frames(name=<cut>, seams=true,
   max_dimension=128)`.
3. The same workflow with `dissolve_videos` in place of `concat_videos` (id
   `qa-c-f105-d`).
expected:
- Step 1 returns `succeeded`. The manifest `shots[].name` values are
  `ep3-shot1-incident.mp4` and `ep3-shot2-reply.mp4`, in that order.
- Step 2: `media.shots[].name` has the same two names. The seam label reads
  `seam 1: ep3-shot1-incident.mp4 | ep3-shot2-reply.mp4` at frame 124.
- Step 3's manifest shots carry the same two file names.
It is a **finding** if any name, in any of the three places, contains a `/` or a server
directory (such as `/home/…/assets/…`).
cleanup: `delete_output(job_id=…)` for both jobs.
metrics: none.

### C-F106 — a kept cut carries its shots, so a probe on the `asset:` finds its seams
source: tester, verified in #393
`keep_output` used to copy only the bytes of a joined cut. The kept asset had no
`media.shots`, and `analyze_seams` on it returned `shots_source: "none"` with
`findings: []`, which looked clean. The case is CPU only and takes two short jobs.
1. `run_workflow(inline_workflow={"id": "qa-c-f106", "steps": [{"name": "cut", "task":
   {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep31-shot1-return.mp4", "asset:qa-cast/ep31-shot2-shrug.mp4"], "fps":
   24}}, "result": {"content_type": "video/mp4", "subfolder": "final"}}]},
   acknowledged_cost=true, wait_seconds=55)`.
2. `keep_output(name=<cut>, asset_name="qa-c-f106-shared.mp4", shared=true)` and
   `keep_output(name=<cut>, asset_name="qa-c-f106-local.mp4")`.
3. `get_gallery_metadata("asset:qa-c-f106-shared.mp4")` and
   `get_gallery_metadata("asset:qa-c-f106-local.mp4")`.
4. One inline job with an `analyze_seams` step (`video`: each kept asset) and an
   `analyze_shots` step on the shared one, each saving `application/json` in `final`.
   Read the results with `get_output_text`.
expected:
- Step 3: both kept assets report `media.shots` with 2 entries. They match step 1's
  manifest `shots` (start frames 0 and 124).
- Step 4: both `analyze_seams` bodies have `shots_source` other than `"none"` (it was
  `"manifest"` when this case was verified) and exactly one seam, at frame 124 (about
  5.17 s). `analyze_shots` lists 2 shots with the same `shots_source`.
It is a **finding** if a kept asset has no `media.shots`, or if a probe on it reports
`shots_source: "none"` or no seams.
cleanup: `delete_output(job_id=…)` for both jobs, then
`delete_asset("qa-c-f106-local.mp4")` and `delete_asset("qa-c-f106-shared.mp4")`.
metrics: none.

### C-F107 — a probe on a file with no shots skips its shot rules and warns, instead of a false clean
source: tester, verified in #394
On a file with no shot records, `analyze_seams` used to list all four seam rules in
`rules_applied` with `findings: []` and no warning, although it had measured no seam.
The case is CPU only and takes two short jobs. `asset:qa-cast/ep38-episode.mp4` is a
two-shot cut kept before #393, so it has no `media.shots`.
1. `run_workflow(inline_workflow={"id": "qa-c-f107", "steps": [{"name": "seams", "task":
   {"command": "analyze_seams", "arguments": {"video": "asset:qa-cast/ep38-episode.mp4"}},
   "result": {"content_type": "application/json", "subfolder": "final"}}, {"name":
   "shots", "task": {"command": "analyze_shots", "arguments": {"video":
   "asset:qa-cast/ep38-episode.mp4"}}, "result": {"content_type": "application/json",
   "subfolder": "final"}}]}, acknowledged_cost=true, wait_seconds=55)`. Read both
   bodies with `get_output_text`.
2. Control: the same `analyze_seams` step with `"shots": [{"name": "a", "start_frame":
   0, "num_frames": 124}, {"name": "b", "start_frame": 124, "num_frames": 124}]` added
   to its arguments, as its own job.
expected:
- Step 1: both bodies have `shots_source: "none"`. `analyze_seams` has `rules_applied: []`.
  `analyze_shots` has `rules_applied: ["shot_dead_air"]`: that rule is a per-file
  measurement, not shot-dependent (only `shot_level_spread` is, `shot_dependent=` in
  `dw/tasks/assess.py`), and it runs over the one synthetic `whole` shot (#465, after this
  case was written; filed as drift in #577).
  `analyze_seams`'s `rules_skipped` names `seam_level_step`, `seam_click`, `seam_hole`
  and `seam_frame_jump`, and `analyze_shots`'s names `shot_level_spread`, each with
  `reason: "no shot boundaries"`. The job's `warnings` has one entry per step saying no
  shot boundaries were found and that `shots=` can supply them.
- Step 2: `shots_source: "argument"`, all four seam rules in `rules_applied`,
  `rules_skipped: []`, one seam, and no job warnings.
It is a **finding** if step 1 lists `shot_level_spread` or any seam rule in `rules_applied`,
or if it has no warning.
cleanup: `delete_output(job_id=…)` for both jobs.
metrics: none.

### C-F108 — a joined shot from a `previous_result:` input is named after its step, in the manifest and in probe findings
source: tester, verified in #396
A join input from an earlier step used to be named `video N`. The first fix renamed it
only in the manifest. The shot list on the artifact, which a later `previous_result:`
probe reads, kept `video N`. So check the probe bodies, not only the manifest. The case
is CPU only and takes one short job.
1. `run_workflow(inline_workflow={"id": "qa-c-f108", "steps": [{"name": "duck2", "task":
   {"command": "gain_audio", "arguments": {"audio": "asset:qa-cast/ep31-shot2-shrug.mp4",
   "gain_db": -8, "start_frame": 0, "num_frames": 124, "fps": 24}}, "result":
   {"content_type": "audio/wav", "save": false}}, {"name": "shot2d", "task": {"command":
   "pair_audio", "arguments": {"video": "asset:qa-cast/ep31-shot2-shrug.mp4", "audio":
   "previous_result:duck2", "fit": "video"}}, "result": {"content_type": "video/mp4",
   "save": false}}, {"name": "cut", "task": {"command": "concat_videos", "arguments":
   {"videos": ["asset:qa-cast/ep31-shot1-return.mp4", "previous_result:shot2d"], "fps":
   24}}, "result": {"content_type": "video/mp4", "subfolder": "final"}}, {"name":
   "seams_cut", "task": {"command": "analyze_seams", "arguments": {"video":
   "previous_result:cut"}}, "result": {"content_type": "application/json"}}, {"name":
   "drift_cut", "task": {"command": "analyze_sync_drift", "arguments": {"video":
   "previous_result:cut"}}, "result": {"content_type": "application/json"}}, {"name":
   "diss", "task": {"command": "dissolve_videos", "arguments": {"videos":
   ["previous_result:shot2d", "previous_result:cut"], "fps": 24}}, "result":
   {"content_type": "video/mp4", "subfolder": "intermediate"}}, {"name": "seams_diss",
   "task": {"command": "analyze_seams", "arguments": {"video": "previous_result:diss"}},
   "result": {"content_type": "application/json"}}]}, acknowledged_cost=true,
   wait_seconds=55)`.
2. `get_output_text` on the `seams_cut`, `drift_cut` and `seams_diss` files.
expected:
- Step 1 returns `succeeded`. Manifest `shots[].name`: `cut` has
  `ep31-shot1-return.mp4`, `shot2d`, and `diss` has `shot2d`, `ep31-shot1-return.mp4`,
  `shot2d` (a join nests an input's own shots, dw#399).
- Step 2: every body has `shots_source: "artifact"`. In `seams_cut`, the seam and each
  finding read `between: ["ep31-shot1-return.mp4", "shot2d"]`. In `drift_cut`, `shots[]`
  names are `ep31-shot1-return.mp4`, `shot2d`. In `seams_diss`, the seams read
  `between: ["shot2d", "ep31-shot1-return.mp4"]` and `["ep31-shot1-return.mp4", "shot2d"]`,
  and each finding names one of those pairs (seam pairs unconfirmed: the first run after
  harnest#18 confirms them, and files a suite request if they differ).
It is a **finding** if any name in the manifest or a probe body reads `video N`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F109 — rescoring a kept cut with `pair_audio` keeps its shots, from an `asset:` and from an `output:`
source: tester, verified in #398
This is the "rescore a kept episode" flow: lay a bed under a finished cut, then pair the
new track back onto the same picture. `pair_audio` loaded a `video` given as a file path
with no shot records. The rescored film had `media.shots: null`, and `analyze_seams` on
it warned that it found no shot boundaries. The shots are still exactly right, because
the picture is unchanged. C-F106 covers the step before this one (keeping the shots).
The case is CPU only and takes two short jobs. `asset:qa-cast/ep42-episode.mp4` is a
two-shot cut (248 f, 24 fps, 32 kHz) whose `media.shots` are `shot@accuse` 0/124 and
`shot@deflect` 124/124.
1. `run_workflow(inline_workflow={"id": "qa-c-f109", "seed": 1, "variables": {"episode":
   "asset:qa-cast/ep42-episode.mp4", "bed": "asset:qa-cast/ep11-bed.wav"}, "steps":
   [{"name": "mix", "task": {"command": "mix_audio", "arguments": {"audios":
   ["variable:episode", "variable:bed"], "gains": [1, 4]}}, "result": {"content_type":
   "audio/wav", "save": false}}, {"name": "norm", "task": {"command": "normalize_audio",
   "arguments": {"audio": "previous_result:mix", "peak_dbfs": -3, "target_lufs": -16}},
   "result": {"content_type": "audio/wav", "subfolder": "intermediate"}}, {"name": "film",
   "task": {"command": "pair_audio", "arguments": {"video": "variable:episode", "audio":
   "previous_result:norm", "fit": "video"}}, "result": {"content_type": "video/mp4",
   "subfolder": "final"}}, {"name": "seams", "task": {"command": "analyze_seams",
   "arguments": {"video": "previous_result:film"}}, "result": {"content_type":
   "application/json", "subfolder": "final"}}]}, acknowledged_cost=true,
   wait_seconds=55)`. Then `get_gallery_metadata` on the `film` file and `get_output_text`
   on the `seams` file.
2. Repeat with the `output:` form: a job with `pair_audio(video="output:<step 1's film
   file>", audio="asset:qa-cast/ep11-bed.wav", fit="video")` → `analyze_seams(video=
   "previous_result:film")`.
expected:
- Step 1: the `film` manifest entry and `get_gallery_metadata`'s `media.shots` both list
  `shot@accuse` (start_frame 0, num_frames 124, start_sample 0, num_samples 165333) and
  `shot@deflect` (124, 124, 165333, 165334). Frame boundaries are unchanged, and samples
  are re-measured at 32 kHz. The job has no `seams: … found no shot boundaries` warning.
  The seams body has `shots_source` other than `"none"` (it was `"artifact"` when this case
  was verified), `rules_skipped: []`, and one seam at about 5.17 s.
- Step 2: the `film` manifest entry has the same two shots, and there is no
  no-shot-boundaries warning.
It is a **finding** if either film has no `shots` / `media.shots: null`, or if a seams
probe on it reports `shots_source: "none"`.
cleanup: `delete_output(job_id=…)` for both jobs, step 2's first (it reads step 1's
output).
metrics: none.

### C-F110 — rescoring a kept *dissolve* cut keeps each shot's `overlap_frames`, so its seams stay dissolves
source: tester, found while running TESTER_TASK.agent.md
C-F109 covers rescoring a hard-cut episode. This case covers a cut joined by
`dissolve_videos`, whose shot records also carry `overlap_frames`. If a rescore drops that
field, `analyze_seams` would place the seams as hard cuts at the wrong time. It is CPU only
and takes one job of about 10 s. `asset:qa-cast/ep45-episode.mp4` is three shots dissolved
with `dissolve_frames: 12` (348 f, 24 fps, 32 kHz stereo). Its `media.shots` start at 0 /
112 / 224 with num_frames 112 / 112 / 124, and the second and third shots carry
`overlap_frames: 12`. `asset:uploads/qa-cast/room-bed.wav` is 4.96 s, 16 kHz mono.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f110", "seed": 1,
   "steps": [{"name": "bed", "task": {"command": "loop_audio", "arguments": {"audio":
   "asset:uploads/qa-cast/room-bed.wav", "target_frames": 348, "fps": 24}}, "result":
   {"content_type": "audio/wav", "save": false}}, {"name": "mix", "task": {"command":
   "mix_audio", "arguments": {"audios": ["asset:qa-cast/ep45-episode.mp4",
   "previous_result:bed"], "gains": [1, 0.251]}}, "result": {"content_type": "audio/wav",
   "save": false}}, {"name": "level", "task": {"command": "normalize_audio", "arguments":
   {"audio": "previous_result:mix", "peak_dbfs": -3}}, "result": {"content_type":
   "audio/wav", "subfolder": "intermediate"}}, {"name": "film", "task": {"command":
   "pair_audio", "arguments": {"video": "asset:qa-cast/ep45-episode.mp4", "audio":
   "previous_result:level", "fit": "video"}}, "result": {"content_type": "video/mp4",
   "subfolder": "final"}}, {"name": "seams", "task": {"command": "analyze_seams",
   "arguments": {"video": "previous_result:film"}}, "result": {"content_type":
   "application/json", "subfolder": "intermediate"}}]}, acknowledged_cost=<bound from
   validate>, wait_seconds=55)`. Then call `get_gallery_metadata` on the `film` file and
   `get_output_text` on the `seams` file.
expected:
- `succeeded`. Its only warning is `mix_audio`'s sample-rate mismatch (32000 vs 16000 Hz,
  resampled to 32000).
- The `film` manifest entry and `media.shots` list the same three shots. Frames are
  0/112, 112/112 and 224/124. The second and third shots carry `overlap_frames: 12`.
- The film is 348 frames, 24 fps, 14.5 s and 32 kHz stereo. `peak_dbfs` is at or below
  −2.5.
- The seams body has `shots_source` other than `"none"` (it was `"artifact"` when this case
  was written) and `rules_skipped: []`. It has exactly two seams, both `"kind":
  "dissolve"` and `"hard_cut": false`, at about 4.917 s and 9.583 s, and `findings: []`.
It is a **finding** if a film shot loses `overlap_frames`, if either seam is not
`dissolve`, or if either seam moves more than 0.05 s.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F111 — a dissolve's shot samples survive a `pair_audio` rescore unchanged
source: tester, verified in #401 (claude-opus-5-5 via anthropic)
`dissolve_videos` has to convert a shot's frame boundary to a sample with the same rule as
`pair_audio`: `round(frame × sample_rate / fps)`. If it doesn't, rescoring a cut shifts
where its shots start by one sample. It is CPU only and takes one job of about 20 s.
`asset:qa-cast/ep42-shot1-accuse.mp4` and `asset:qa-cast/ep42-shot2-deflect.mp4` are each
124 f, 24 fps, 32 kHz stereo. At 12 dissolve frames the window is a whole 16000 samples;
at 7 it is 9333.33, which isn't.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f111", "steps":
   [{"name": "cut", "task": {"command": "dissolve_videos", "arguments": {"videos":
   ["asset:qa-cast/ep42-shot1-accuse.mp4", "asset:qa-cast/ep42-shot2-deflect.mp4",
   "asset:qa-cast/ep42-shot1-accuse.mp4"], "dissolve_frames": 12, "fps": 24}}, "result":
   {"content_type": "video/mp4"}}, {"name": "film", "task": {"command": "pair_audio",
   "arguments": {"video": "previous_result:cut", "audio": "previous_result:cut", "fit":
   "video"}}, "result": {"content_type": "video/mp4"}}, {"name": "cut7", "task": {"command":
   "dissolve_videos", "arguments": {"videos": ["asset:qa-cast/ep42-shot1-accuse.mp4",
   "asset:qa-cast/ep42-shot2-deflect.mp4", "asset:qa-cast/ep42-shot1-accuse.mp4"],
   "dissolve_frames": 7, "fps": 24}}, "result": {"content_type": "video/mp4"}}, {"name":
   "film7", "task": {"command": "pair_audio", "arguments": {"video": "previous_result:cut7",
   "audio": "previous_result:cut7", "fit": "video"}}, "result": {"content_type":
   "video/mp4"}}]}, acknowledged_cost=<bound from validate>, wait_seconds=55)`.
expected:
- `succeeded`.
- `cut` and `film` manifest shots start at samples 0 / 149333 / 298667, with frames
  0 / 112 / 224.
- `cut7` and `film7` shots start at samples 0 / 156000 / 312000, with frames
  0 / 117 / 234.
- In each pair, every shot's `start_sample` is identical, and so is the first two shots'
  `num_samples`. The last shot's `num_samples` may differ by one sample: `fit: "video"`
  pads the dissolve's 463999-sample track to the video's 464000.
It is a **finding** if any `start_sample` differs between a dissolve and its `pair_audio`
rescore, or differs from `round(start_frame × 32000 / 24)`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F112 — a join of two kept cuts at different sample rates lists every inner shot, re-measured at the joined rate
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
A join of joins: `concat_videos` over two kept episodes, each already carrying
`media.shots`. The joined film must list the inner shots of both (#399), not one shot per
input. The inputs are at different rates, so the second episode's shot samples must be
re-measured at the rate the join resamples to. CPU only, one job of about 10 s.
`asset:qa-cast/ep49-episode.mp4` (372 f, 44.1 kHz, 3 shots) and
`asset:qa-cast/ep42-episode.mp4` (248 f, 32 kHz, shots `shot@accuse`/`shot@deflect`).
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f112", "seed": 1,
   "steps": [{"name": "film", "task": {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep49-episode.mp4", "asset:qa-cast/ep42-episode.mp4"], "fps": 24,
   "match_levels": "rms", "match_levels_dbfs": -24}}, "result": {"content_type":
   "video/mp4", "subfolder": "final"}}, {"name": "seams", "task": {"command":
   "analyze_seams", "arguments": {"video": "previous_result:film"}}, "result":
   {"content_type": "application/json", "subfolder": "intermediate"}}]},
   acknowledged_cost=<bound from validate>, wait_seconds=55)`. Then `get_gallery_metadata`
   on the `film` file and `get_output_text` on the `seams` file.
expected:
- `succeeded`. Its only warning is `concat_videos`' sample-rate mismatch (44100 vs 32000 Hz,
  resampled to 44100).
- The film is 620 frames, 24 fps, 25.833 s, 44.1 kHz stereo.
- The `film` manifest entry and `media.shots` both list five shots, in order:
  `ep42-shot1-accuse.mp4`, `ep42-shot2-deflect.mp4`, `ep37-shot1-receipt.mp4`,
  `shot@accuse`, `shot@deflect`, at start_frame 0/124/248/372/496, num_frames 124 each,
  start_sample 0/227850/455700/683550/911400 (`round(start_frame × 44100 / 24)`), and
  num_samples 227850 for the first four. The last shot's `start_sample + num_samples`
  equals the file's decoded audio length, `audio_stream_seconds × 44100` (#426; 1139235
  when written, last num_samples 227835).
- The seams body has `shots_source: "artifact"`, `rules_skipped: []`, and four seams, all
  `"kind": "cut"`, at about 5.167 / 10.333 / 15.5 / 20.667 s. Each `level_step_db` was
  ≤ 1.44 when this case was written; its only findings were info-level `seam_frame_jump`.
It is a **finding** if the film lists two shots (one per input) or none, if a
`shot@…` entry keeps its 32 kHz sample figures (165333), if any seam is missing, or if the
map ends past the file's last sample.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F113 — tool descriptions hold the rule, not the model narrative (#376)
source: tester, spec for #403 from #376's plan v2
#376 moved model-specific narrative and a transcription walkthrough out of the MCP tool
descriptions into the guide. Each description keeps its rule and loses its example. This case
checks that from the tool definitions a client actually loads. No run is needed.
1. Load the definitions with `ToolSearch("select:mcp__dw__get_output_audio,mcp__dw__validate_workflow,mcp__dw__list_workflows,mcp__dw__list_prompts,mcp__dw__get_job_events,mcp__dw__wait_for_job,mcp__dw__get_memory")`.
2. Load every other `mcp__dw__*` tool the same way, in batches, for the length check.
expected:
- `get_output_audio`:
  - It still says the served format: the phrases "own encoding" (a whole file) and "WAV"
    (extracted or excerpted) are both present.
  - It still says that a text-only client can't consume the `AudioContent` block, and that
    such a client confirms the *words* by transcribing.
  - It points at "The loop" in the `workflows` guide for how to do that.
  - It **no longer** carries the walkthrough. None of these appear: `templates/transcribe-audio`,
    `get_output_text`, `wait_seconds=55`, `basis: "unknown"`, "a few seconds per clip",
    "Four calls".
- `validate_workflow` still states the rule: a value outside a bound the workflow declares is
  an error at validate time, and one the workflow rounds up comes back as a warning naming what
  it becomes. The H3 example "`17 * n + 5` from 124 to 345" is gone.
- `list_workflows` still says `constraints` are terse. The example "`17*n+5, 124-345, rounds up`"
  is gone from the description. It stays in the catalog data; C-F115 checks that.
- `list_prompts` still says `intended_model` narrows to one family. The family list
  (`minimax-h3`, `minimax-music3`, `ltx-2.5`, `z-image`, `flux`) is gone.
- `get_job_events`:
  - It still says a `kind: "phase_stall"` entry is a watchdog notice and not evidence of a hang
    by itself.
  - It still says some models are silent for minutes in normal operation, and to check the
    model's skill or guide before treating one as a fault.
  - The parenthetical "(a video reference encode, block-cache gaps)" is gone.
- `wait_for_job` is **unchanged**. It still carries all of these:
  - "a video reference's lead-in can run many minutes emitting nothing";
  - "uneven under a transformer block cache";
  - "whether `denoise_step` has moved since a poll minutes ago";
  - the pointer to WORKFLOW_GUIDE's "The loop", step 5 for why `denoise_total_steps` can read
    one less than asked.
- `get_memory` is **unchanged**. It still names `host_pinned_reserved_mb` /
  `host_pinned_allocated_mb` with the pointer to the `acceleration` guide's "Reading Memory
  While Offloading". It still has the `live: true`/`live: false` paragraph with reasons
  `job_running`, `worker_stopped`, `worker_busy` and `worker_unreachable`.
- No `mcp__dw__*` description exceeds 2,048 characters, which is about 300 words or 25 lines of
  the rendered definition. A consumer can't count exactly. Flag any description that clearly
  runs past that, and name the tool.

It is a **finding** if any named piece is still present, or if a kept rule is lost with its
example. A description that points at the guide without saying the rule itself is a lost rule.
cleanup: none.
metrics: none.

### C-F115 — trimming the descriptions changed no behavior: H3 frame rule, catalog constraints, prompt filter (#376)
source: tester, spec for #403 from #376's plan v2
#376 is descriptions only. The examples it removed describe behavior that must still hold.
Values below were pinned 2026-09-24 against `templates/minimax/video-with-audio`, matching the
`workflows` guide's "What a variable is allowed to be". Validate only, no run.
1. `validate_workflow(name="templates/minimax/video-with-audio", arguments={"num_frames": N})`
   for N = 130, 108, 141, 345, 346 and 123.
2. `list_workflows(shape="shot")`.
3. `list_prompts(intended_model="minimax-h3")`, then `list_prompts(intended_model="no-such-family")`.
expected:
- Step 1:
  - 130 is `valid: true`, with one warning that it rounds up to 141 and "The run generates
    141, not 130".
  - 108 is `valid: true`, with a warning that it becomes 124.
  - 141 and 345 are `valid: true`, with no `num_frames` warning.
  - 346 is `valid: false`, with an error at `arguments.num_frames` saying it rounds up to 362,
    must be at most 345, and "Accepted: 124 to 345, 17 * n + 5".
  - 123 is `valid: true`, with a warning that it rounds up to 124 ("The run generates 124,
    not 123").
- Step 2: every H3 shot template (`templates/minimax/…`) still shows `"constraints":
  {"num_frames": "17*n+5, 124-345, rounds up"}`. `templates/minimax/shots-batch` shows it under
  `lists.shots.constraints`. The LTX templates still show `"8*n+1, 9+"`.
- Step 3:
  - The `minimax-h3` call returns a non-empty list whose every `details[*].intended_model` is
    `minimax-h3`. It had 36 entries on 2026-09-24; that count changes with the library.
  - The unknown family returns `prompts: []`, not an error (checked 2026-09-24).

It is a **finding** if any refusal, snap, warning text or catalog constraint differs from the
above, or if `intended_model` stops filtering.
cleanup: none.
metrics: none.

### C-F116 — a `previous_result:` passed into a composed workflow reaches the child's task as the live result, not its repr
Before #404, a sub-workflow step's `previous_result:` argument was coerced through the child
variable's string default. The child's `slice_audio` got the Python repr of the `AudioTrack`
as a "path", and containment refused it at run time, even though `validate_workflow` was
clean. C-F029 feeds the template a computed score only by going through `keep_output` first.
This case covers the one-job form, which #402's past-end warning recommends. Task-only, about
4 s.
One inline workflow (`id` + `seed`, no `result` blocks):
1. Step `bed`: `loop_audio` with `audio: "asset:uploads/qa-cast/room-bed.wav"`,
   `target_frames: 248`, `fps: 24`.
2. Step `cut`: a sub-workflow step, `workflow.path: "templates/assemble-and-score"`, with
   `shots` = the two C-F001 fixtures (`asset:qa-cast/ep3-shot1-incident.mp4`,
   `asset:qa-cast/ep3-shot2-reply.mp4`), `score: "previous_result:bed"` and
   `total_frames: 248`.

Validate it, then run it.
expected: `validate_workflow` is `valid: true`. The run **succeeds**, and the manifest carries
the child's whole chain through `film`, with one `final/…film…mp4` file and two
`shots` of 124 frames each. There is exactly one warning: the `edit: concat_videos` level
spread of 11.1 dB. That spread is the fixtures' own (see Fixtures) and is expected here,
since `match_levels` is unset. There is **no** `slice_audio … past the end of a 4.96 s
source` warning. That warning would mean the child sliced the raw room-bed file instead of
the 10.33 s looped track, as C-F016's source would do.
It is a **finding** if the run fails, above all with "resolves outside every directory
this workflow may read" or an error quoting `<dw.result.AudioTrack object at …>`. It is also
a finding if validation is clean but the run fails, or if the past-end warning appears.
cleanup: delete the run with `delete_output(job_id=…)`. The inputs are all durable fixtures.
source: tester, verified in #404. Ran over MCP as model `claude-opus-5-5` via provider
`anthropic` on 2026-09-24, develop @ 8c6183a, workspace `qa-ep51`: job `3e4887ef323b`,
3.7 s, only the 11.1 dB level-spread warning. The issue's own repro (three qa-cast shots,
372 frames) is job `dbe050a44c46`.

### C-F117 — "The loop" step 6, reached through its `##` section, carries the transcription procedure, and following it works (#376)
source: tester, spec for #403 from #376's plan v4
Plan v4's version of C-F114. The walkthrough `get_output_audio` used to carry now lives in
step 6 of "The loop" in the `workflows` guide. "The loop" is an `###` subsection, and
`get_guide` addresses only `##` sections. So an agent reaches it through the section that holds
it, "Authoring a workflow from an agent", the form the server instructions already use.
`section="The loop"` is not expected to resolve (plan v4, Q4). This case checks that the lookup
returns the procedure and that the procedure works end to end when followed exactly as written.
CPU/short-GPU only: one VITS speech clip plus one transcription.
1. `get_guide(name="workflows", section="Authoring a workflow from an agent")`.
2. Load `get_output_audio`'s definition (`ToolSearch("select:mcp__dw__get_output_audio")`) and
   note the section its pointer names.
3. Setup: make a gallery output with known speech.
   - `validate_workflow(name="templates/generate-speech", arguments={"text": "The quick brown
     fox jumps over the lazy dog."})`, then `run_workflow(workflow_path="templates/generate-speech",
     arguments=<same>, acknowledged_cost=<bound from that plan>, wait_seconds=55)`. This is
     C-F081's template: VITS, 16 kHz mono.
   - Note the `.wav`'s `<workflow>/<run id>/<file>` name as `<speech>` and the job id as
     `<setup job>`.
4. Follow step 6's procedure as the guide words it, with `<speech>` as the output. On
   2026-09-24 (develop @ 007717a, read while specifying) it was:
   - `validate_workflow(name="templates/transcribe-audio", arguments={"input_audio":
     "output:<speech>"})`;
   - `run_workflow` with the same arguments, `acknowledged_cost={"fingerprint": …, "minutes":
     …, "downloads": [...]}` bound to that plan, and `wait_seconds=55` (follow up with
     `wait_for_job` if `still_running: true`);
   - `get_output_text` on the result;
   - `delete_output(job_id=<transcribe job>)`.
   If the guide's wording differs from this, follow the guide and note the difference.
5. `list_gallery()` after step 4.
expected:
- Step 1 returns `content`, not an error. Inside it, the `### The loop` subsection has a step 6
  that still opens with `get_output_image` (look at what was made, judge it against the request),
  and carries a transcription paragraph added to that step, not replacing it. The paragraph
  names all of these:
  - `templates/transcribe-audio`;
  - an `output:` reference as `input_audio`;
  - a bound `acknowledged_cost` and `wait_seconds`;
  - `get_output_text`;
  - `delete_output(job_id=`.
- Step 2: the pointer names "The loop" and a `get_guide` form that resolves, meaning
  `section="Authoring a workflow from an agent"` or equivalent wording naming that `##` section.
  A pointer whose only lookup is `section="The loop"` dangles, and is a finding.
- Step 4:
  - validate is `valid: true` with no errors;
  - the run `succeeded`;
  - `get_output_text` returns the spoken words: "the quick brown fox jumps over the lazy dog",
    ignoring case and punctuation. One misheard word is tolerable on a VITS voice; a
    transcript that's empty or unrelated is not.
  - `delete_output(job_id=)` succeeds.
- Step 5 shows no `transcribe-audio` run left behind. The only run from this case is the
  setup's.

It is a **finding** if step 1 errors or returns a section without the procedure, if any call in
the procedure as the guide writes it is refused (a wrong argument name, a missing
`acknowledged_cost` shape), or if the procedure leaves a scratch run.
cleanup: `delete_output(job_id=<setup job>)`. Also delete the transcribe job if step 4 failed
before its own delete.
metrics: none.

### C-F118 — ordinary text and image results still save, read back and keep after the active-type refusal
source: tester, spec for #410 from #407's plan v2
The half of #410 that must not break: refusing `text/html`/`text/xml` (SE-F035) and adding
headers to active types must leave plain text and PNG results working. Both steps are
CPU-only tasks.
1. Run a one-step task workflow on `compose_text` (`parts: ["alpha", "beta"]`, `separator: " "`)
   with `result: {content_type: "text/plain"}`. Use `run_workflow(workflow=…,
   acknowledged_cost=<bound from the validate plan>, wait_seconds=55)`.
2. Call `get_output_text` on its output.
3. Run a one-step task workflow on `qr_code` (`qr_code_contents: "c-f118"`, `width: 256`,
   `height: 256`) with `result: {content_type: "image/png"}`.
4. Call `get_output_image` on the PNG output.
5. Call `keep_output(name=<png output>, asset_name="c-f118/qr.png")`, then `list_assets`.

expected:
- Steps 1 and 3 validate clean and complete.
- Step 2 returns `alpha beta`.
- Step 4 returns a 256×256 image.
- Step 5 succeeds, and `list_assets` shows `c-f118/qr.png`.

It is a **finding** if either `content_type` is refused, or any of those reads fails in a way it
didn't before #410.
cleanup: `delete_asset("c-f118/qr.png")`, `delete_output(job_id=…)` for both jobs.
metrics: none.

### C-F119 — a public-to-public redirect is still followed
source: tester, spec for #411 from #407's plan v2
The half of #411 that must not break: `safe_get` re-checks each hop (SE-F036), but a redirect
between public hosts must still be followed. Many real media URLs redirect: Hugging Face
`resolve/` links 302 to a CDN.
1. Run a one-step task workflow on `get_image_size` with `image:
   "https://huggingface.co/datasets/huggingface/documentation-images/resolve/main/diffusers/astronaut.jpg"`.
   That URL is itself a redirect to the CDN. Use `run_workflow(…, wait_seconds=55)`.
2. The same, with `image` wrapped in one more public hop:
   `https://httpbin.org/redirect-to?url=<the URL above, percent-encoded>&status_code=302`. If
   httpbin is down, skip this step and say so.

expected: both jobs complete, and the result reports the image's size (the same value both
times). It is a **finding** if either is refused as a redirect, as internal or for its hop count.
cleanup: `delete_output(job_id=…)` for both jobs.
metrics: none.

### C-F120 — gallery, asset, workflow and prompt listings and `export_job` are unchanged on an ordinary workspace
source: tester, spec for #412 from #407's plan v2
#412 adds symlink containment to the listing and export walks (pytest covers the symlink cases).
Over MCP, this case checks that nothing ordinary dropped out of those walks. Use workspace
`regression-complete`.
1. Run a `qr_code` one-step task workflow (`qr_code_contents: "c-f120"`, `width: 256`,
   `height: 256`) with `result: {content_type: "image/png"}` and `wait_seconds=55`.
2. Call `keep_output(name=<png output>, asset_name="c-f120/qr.png")`.
3. `save_workflow` that same workflow as `c-f120-qr`.
4. `save_prompt` a prompt named `c-f120` (any text).
5. Call `list_gallery`, `list_assets`, `list_workflows` and `list_prompts`.
6. Call `export_job(job_id=<step 1's job>)`.

expected:
- In step 5, each listing includes its item: the job's PNG, `c-f120/qr.png`, `c-f120-qr` and
  `c-f120`.
- Step 6 succeeds, and its listing names the PNG and the job's workflow/metadata files, as
  before #412.

It is a **finding** if any item is missing, or an ordinary file is reported as skipped or
outside the root.
cleanup: `delete_asset("c-f120/qr.png")`, `delete_workflow("c-f120-qr")`,
`delete_prompt("c-f120")`, `delete_output(job_id=…)`. Also delete whatever `export_job` wrote,
if its response names a separate location.
metrics: none.

### C-F121 — normal-sized image decode paths still work under the pixel limit
source: tester, spec for #413 from #407's plan v2
#413 caps decode at 50M pixels (pytest covers the refusal of a decoder bomb). This case checks
that every MCP path that decodes an image still handles an ordinary one.
1. Run a `qr_code` one-step task workflow (`qr_code_contents: "c-f121"`, default 768×768) with
   `result: {content_type: "image/png", embed_metadata: true}` and `wait_seconds=55`.
2. Call `get_output_image(name=<png>)`, and again with `crop=[0, 0, 384, 384]` and with
   `max_dimension=256`.
3. Call `list_gallery(folder="c-f121", limit=5)`.
4. Call `get_gallery_metadata` on the PNG.

expected:
- Step 2 returns a 768×768 image, a 384×384 crop and a 256-px downscale.
- Step 3 lists the PNG (with its thumbnail/preview field, if the listing has one).
- Step 4 returns the embedded workflow/metadata.

It is a **finding** if any of them errors with a pixel-limit, decompression-bomb or decode
refusal.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F122 — an argument that overrides an active `content_type` default to `text/plain` runs, as `validate_workflow` says
source: tester, verified in #415 (claude-opus-5-5, anthropic)
The mirror of SE-F035 (e). The document's default is active, the caller's argument isn't, and
the substituted value is what gets written. `validate_workflow` accepted this all along, but
`run_workflow` refused it at submit and then failed the job at execution. Both checks were
reading the unsubstituted default. Use workspace `regression-complete`. Carrier (CPU only):
`{"id": "c-f122", "variables": {"ct": "text/html"}, "steps": [{"name": "t", "task": {"command":
"compose_text", "arguments": {"parts": ["<b>x</b>"]}}, "result": {"content_type": "variable:ct"}}]}`
1. `validate_workflow(workflow=<carrier>, arguments={"ct": "text/plain"})`.
2. `run_workflow(workflow=<carrier>, arguments={"ct": "text/plain"}, acknowledged_cost=<bound
   from step 1's plan>, wait_seconds=55)`, then `get_output_text` on its output.
3. `run_workflow(workflow=<carrier>, acknowledged_cost=true)` with no `arguments`, so the
   `text/html` default stands.

expected:
- Step 1 returns `valid: true` with `checked_arguments: ["ct"]`.
- In step 2 the job reaches `succeeded` and writes one `.txt` file. `get_output_text` returns
  `<b>x</b>` with a `text/plain` content type.
- Step 3 is refused up front at `steps[0].result.content_type` ("active content is not
  written"), and no job is queued.

It is a **finding** if step 2 is refused, fails at execution, or writes anything but `.txt`,
because the two tools disagree again. It is a **finding** if step 3 queues a job.
cleanup: `delete_output(job_id=…)` for step 2's job.
metrics: none.

### C-F123 — scoring one kept joined cut through `templates/assemble-and-score` keeps every inner shot and its dissolve overlaps
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
A composed template given a *single* input that is itself a join of cuts and dissolves must
carry that input's inner shots through its `film` step, `overlap_frames` included, so a
probe still sees dissolves as dissolves. The bed comes from a `previous_result:` passed
into the child (#404). CPU only, one job of about 10 s.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f123", "seed": 1,
   "steps": [{"name": "bed", "task": {"command": "loop_audio", "arguments": {"audio":
   "asset:qa-cast/ep51-bed.wav", "target_frames": 956, "fps": 24}}, "result":
   {"content_type": "audio/wav", "save": true, "subfolder": "intermediate"}}, {"name": "cut",
   "workflow": {"path": "templates/assemble-and-score", "arguments": {"shots":
   ["asset:qa-cast/ep53-episode.mp4"], "score": "previous_result:bed", "total_frames": 956,
   "match_levels": "rms", "match_levels_dbfs": -24, "score_gain": 0.251}}}]},
   acknowledged_cost=<bound from validate>, wait_seconds=55)`.
2. `assess_output(name=<the film file>, probe="analyze_seams")`.
expected:
- `succeeded`; its only warning is the `bed` step's quiet-overall note.
- The `film` manifest entry lists eight shots at start_frame 0/124/248/372/496/608/720/832,
  num_frames 124/124/124/124/112/112/112/124, the last three with `overlap_frames: 12`
  (the same list `get_gallery_metadata` gives for `ep53-episode.mp4`).
- The film is 956 frames, 24 fps, 39.833 s, 44.1 kHz stereo, peak about −3 dBFS.
- The probe says `shots_source: "manifest"`, seven seams: 1–4 `cut`, 5–7 `dissolve`. When
  this case was written it had no findings, every `level_step_db` ≤ 1.16.
It is a **finding** if the film lists one shot (the input as a whole), drops
`overlap_frames`, or the probe reports seams 5–7 as cuts.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F124 — `templates/dissolve-between-shots` over a kept dissolve-and-cut join keeps its inner shots and adds its own dissolve
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
This is C-F123's nesting on the other assembly template, with two inputs at different
rates: a 44.1 kHz join of 8 shots and a 32 kHz join of 2. The new dissolve must shorten
only the last inner shot of input 1. It must mark only the first inner shot of input 2
`overlap_frames`, and it must leave input 1's own dissolves alone. CPU only, one job of
about 20 s.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f124", "seed": 1,
   "steps": [{"name": "bed", "task": {"command": "loop_audio", "arguments": {"audio":
   "asset:qa-cast/ep51-bed.wav", "target_frames": 1192, "fps": 24}}, "result":
   {"content_type": "audio/wav", "save": true, "subfolder": "intermediate"}}, {"name": "cut",
   "workflow": {"path": "templates/dissolve-between-shots", "arguments": {"shots":
   ["asset:qa-cast/ep54-episode.mp4", "asset:qa-cast/ep42-episode.mp4"], "score":
   "previous_result:bed", "total_frames": 1192, "dissolve_frames": 12, "match_levels": "rms",
   "match_levels_dbfs": -24, "score_gain": 0.251}}}]}, acknowledged_cost=<bound from
   validate>, wait_seconds=55)`.
2. `assess_output(name=<the film file>, probe="analyze_seams")`.
expected:
- `succeeded`. Its warnings are the `bed` step's quiet-overall note and the `edit` step's
  `sample_rate_mismatch` (44100 vs 32000, resampled to 44100).
- The `film` entry is in subfolder `final` and lists ten shots, at start_frame
  0/124/248/372/496/608/720/832/944/1068 with num_frames 124/124/124/124/112/112/112/112/124/124.
  Shots 6–9 carry `overlap_frames: 12`. Shot 8 (ep37-shot1-receipt, 124 frames in
  `ep54-episode`) is now 112, because the new dissolve takes its tail.
- The film is 1192 frames (956 + 248 − 12), 24 fps, 49.667 s, 44.1 kHz stereo, with a peak
  of about −3 dBFS.
- The probe gives `shots_source: "manifest"` and nine seams: 1–4 `cut`, 5–8 `dissolve`,
  9 `cut`. When this case was written it had no findings, and every `level_step_db` was
  ≤ 1.39.
It is a **finding** if an input collapses to one shot, input 1's dissolves (seams 5–7) come
back as cuts, the new seam 8 is not a dissolve, or shot 8 keeps 124 frames (#405).
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F125 — `analyze_seams`' own `shots` argument overrides the manifest and carries `hard_cut` to its seam
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
A hand-written shot list is the only way to mark a cut as intended. The flag has to reach the
seam it opens, and only that seam. CPU only, one job of about 5 s.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f125", "seed": 1,
   "steps": [{"name": "control", "task": {"command": "analyze_seams", "arguments": {"video":
   "asset:qa-cast/ep42-episode.mp4", "shots": [{"name": "accuse", "start_frame": 0,
   "num_frames": 124}, {"name": "deflect", "start_frame": 124, "num_frames": 124}]}}, "result":
   {"content_type": "application/json", "subfolder": "intermediate"}}, {"name": "marked", "task":
   {"command": "analyze_seams", "arguments": {"video": "asset:qa-cast/ep42-episode.mp4", "shots":
   [{"name": "accuse", "start_frame": 0, "num_frames": 124, "hard_cut": true}, {"name":
   "deflect", "start_frame": 124, "num_frames": 124, "hard_cut": true}]}}, "result":
   {"content_type": "application/json", "subfolder": "final"}}]}, acknowledged_cost=<bound from
   validate>, wait_seconds=55)`.
2. `get_output_text` on each step's JSON.
expected:
- `succeeded` with no warnings. Both outputs give `shots_source: "argument"` and exactly one
  seam, `between: ["accuse", "deflect"]`, `kind: "cut"`, at about 5.167 s. The seam names come
  from the argument, not the manifest's `shot@accuse`/`shot@deflect`.
- `control` seam `hard_cut: false`. `marked` seam `hard_cut: true`: the flag on the incoming
  shot applies, and the flag on the first shot opens no seam of its own.
- Every measurement is identical between the two steps. When this case was written,
  `level_step_db` was 1.44 and `jump_ratio` 20.29, with no findings.
It is a **finding** if `shots_source` is `manifest` or the seam names are `shot@…`, if either
step reports two seams, or if `marked` reads `hard_cut: false`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F126 — a same-rate join of two kept cuts keeps every inner shot and overlap, and its shot map ends where the file does
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
The counterpart of C-F112 with no resampling: both inputs are 32 kHz, and the second one is a
dissolve join whose shots carry `overlap_frames`. The offset must move the inner shots
without dropping the overlaps, and the shot map must end on the file's last sample (#426 was
a map that overran it). CPU only, one job of about 6 s.
`asset:qa-cast/ep42-episode.mp4` (248 f, 32 kHz, 2 shots) and
`asset:qa-cast/ep45-episode.mp4` (348 f, 32 kHz, 3 shots, two with `overlap_frames: 12`).
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f126", "seed": 1,
   "steps": [{"name": "join", "task": {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep42-episode.mp4", "asset:qa-cast/ep45-episode.mp4"], "fps": 24,
   "match_levels": "rms", "match_levels_dbfs": -24}}, "result": {"content_type": "video/mp4",
   "subfolder": "final"}}]}, acknowledged_cost=<bound from validate>, wait_seconds=55)`.
2. `get_gallery_metadata` and `assess_output` on the `join` file.
expected:
- `succeeded` with **no** warnings (no `sample_rate_mismatch`: both inputs are 32 kHz).
- 596 frames, 24 fps, 24.834 s, 32 kHz stereo, `audio_stream_seconds` equal to
  `duration_seconds`.
- The manifest entry and `media.shots` both list five shots, in order: `shot@accuse`,
  `shot@deflect`, `ep42-shot1-accuse.mp4`, `ep42-shot2-deflect.mp4`, `ep37-shot1-receipt.mp4`,
  at start_frame 0/124/248/360/472, num_frames 124/124/112/112/124. The last two keep
  `overlap_frames: 12`; the first three have none.
- start_sample 0/165333/330667/480000/629333. The last shot's `start_sample + num_samples`
  equals `duration_seconds × 32000` (794688 when written, last num_samples 165355).
- `assess_output`: `shots_source: "manifest"`, `rules_skipped: []`, no findings other than
  `shot_dead_air` (#465) warnings on the near-silent gaps inside the shots.
It is a **finding** if there are fewer than five shots, if an `overlap_frames` is lost, or if
the map ends past the file's last sample.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F127 — a dissolve that puts a 48 kHz LTX clip between two 32 kHz H3 shots resamples up and keeps its shot map exact
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
This is a cross-family join. LTX-2.5 writes its soundtrack at 48 kHz, and H3 shots are 32 kHz.
The resample has to land the shot map on whole samples at the new rate (2000 per frame at
24 fps), and the overlaps have to survive. CPU only, one job of about 12 s.
The inputs are `asset:qa-cast/ep62-shot1-accuse.mp4` (124 f, 32 kHz),
`asset:qa-cast/ep63-shot-ltx-priya.mp4` (121 f, 48 kHz, `templates/ltx2/image-to-video`) and
`asset:qa-cast/ep62-shot2-deflect.mp4` (124 f, 32 kHz).
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f127", "seed": 1,
   "steps": [{"name": "join", "task": {"command": "dissolve_videos", "arguments": {"videos":
   ["asset:qa-cast/ep62-shot1-accuse.mp4", "asset:qa-cast/ep63-shot-ltx-priya.mp4",
   "asset:qa-cast/ep62-shot2-deflect.mp4"], "dissolve_frames": 12, "fps": 24, "match_levels":
   "rms", "match_levels_dbfs": -24}}, "result": {"content_type": "video/mp4", "subfolder":
   "final"}}]}, acknowledged_cost=<bound from validate>, wait_seconds=55)`.
2. `get_gallery_metadata` and `assess_output` on the `join` file.
expected:
- `succeeded` with exactly one warning: the sample-rate mismatch, naming 32000/48000/32000 and
  resampling to 48000 Hz.
- 345 frames (124+121+124 − 2×12), 24 fps, 14.375 s, 48 kHz stereo, 960×544,
  `audio_stream_seconds` equal to `duration_seconds`.
- The manifest and `media.shots` list three shots at start_frame 0/112/221, num_frames
  112/109/124, start_sample 0/224000/442000, num_samples 224000/218000/248000. The last two
  carry `overlap_frames: 12`. The map ends at sample 690000 = 14.375 × 48000.
- `assess_output`: `shots_source: "manifest"`, `rules_skipped: []`, and no findings other than
  `shot_dead_air` (#465) warnings on the near-silent gaps inside the shots (seam 1's `after_rms_dbfs` reads about −65 because the LTX clip opens quiet, and
  that is below `seam_hole`'s floor).
It is a **finding** if the output is not at 48 kHz, if the map is off the 2000-samples-per-frame
grid, or if an overlap is lost.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F128 — a `previous_result:` join input is still named after its step when an earlier input carries inner shots
source: tester, verified in #432 (claude-opus-5-5 via anthropic)
This is C-F108 with a multi-shot first input. `asset:qa-cast/ep63-episode.mp4` is a kept
3-shot dissolve with its own `media.shots`. Before #432, the rename matched input index to
flattened shot position, so the step's shot fell back to `video 2`. The dissolve puts an
asset *after* the reference, so it also catches a shifted override. CPU only, two short jobs.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f128", "seed": 1,
   "steps": [{"name": "paired", "task": {"command": "pair_audio", "arguments": {"video":
   "asset:qa-cast/ep64-shot-ltx-hal.mp4", "audio": "asset:qa-cast/ep64-shot-ltx-hal.mp4",
   "fit": "video"}}, "result": {"content_type": "video/mp4", "save": false}}, {"name": "cut",
   "task": {"command": "concat_videos", "arguments": {"videos":
   ["asset:qa-cast/ep63-episode.mp4", "previous_result:paired"], "fps": 24}}, "result":
   {"content_type": "video/mp4", "subfolder": "final"}}]}, acknowledged_cost=true,
   wait_seconds=55)`.
2. The same call with the `cut` step replaced by `{"name": "diss", "task": {"command":
   "dissolve_videos", "arguments": {"videos": ["asset:qa-cast/ep63-episode.mp4",
   "previous_result:paired", "asset:qa-cast/ep62-shot1-accuse.mp4"], "fps": 24}}, "result":
   {"content_type": "video/mp4", "subfolder": "final"}}`.
3. `get_gallery_metadata` on the step 1 file.
expected:
- Both jobs return `succeeded`.
- Step 1 manifest `shots[].name`: `ep62-shot1-accuse.mp4`, `LTX2I2V-image_to_video.0-0.0.mp4`,
  `ep62-shot2-deflect.mp4`, `paired`. The last shot starts at frame 345 and runs 121 frames.
  Step 3's `media.shots` has the same four names.
- Step 2 manifest `shots[].name`: the same three inner names, then `paired`, then
  `ep62-shot1-accuse.mp4`. Shots 2 to 5 carry `overlap_frames: 12`.
It is a **finding** if any name reads `video N`, if ep63's inner names are replaced, or if the
trailing asset takes the `paired` name.
cleanup: `delete_output(job_id=…)` for both jobs.
metrics: none.

### C-F129 — a multi-shot `previous_result:` dissolved after a multi-shot asset keeps both sides' inner shots
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
C-F128 with inner shots on *both* sides of the join. The `bridge` step is itself a 2-shot
dissolve, and it is then fed by reference after the kept 2-shot `ep62-episode`. Its inner names
must survive: they must not be collapsed to `bridge` or renamed `video 2`. CPU only, one job of
about 16 s. The inputs are `asset:qa-cast/ep65-shot-kf-priya-hal.mp4` (121 f, 48 kHz,
`templates/ltx2/keyframes`), `asset:qa-cast/ep62-shot2-deflect.mp4` (124 f, 32 kHz) and
`asset:qa-cast/ep62-episode.mp4` (248 f, 32 kHz, shots `shot@accuse`/`shot@deflect`).
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f129", "seed": 1,
   "steps": [{"name": "bridge", "task": {"command": "dissolve_videos", "arguments": {"videos":
   ["asset:qa-cast/ep65-shot-kf-priya-hal.mp4", "asset:qa-cast/ep62-shot2-deflect.mp4"],
   "dissolve_frames": 12, "fps": 24, "match_levels": "rms", "match_levels_dbfs": -24}},
   "result": {"content_type": "video/mp4", "subfolder": "intermediate"}}, {"name": "episode",
   "task": {"command": "dissolve_videos", "arguments": {"videos":
   ["asset:qa-cast/ep62-episode.mp4", "previous_result:bridge"], "dissolve_frames": 12, "fps":
   24, "match_levels": "rms", "match_levels_dbfs": -24}}, "result": {"content_type":
   "video/mp4", "subfolder": "final"}}]}, acknowledged_cost=<bound from validate>,
   wait_seconds=55)`.
2. `get_gallery_metadata` on the `episode` file.
expected:
- `succeeded`. Each step has a `sample_rate_mismatch` warning that resamples to 48000 Hz.
- The `bridge` manifest has 2 shots: `ep65-shot-kf-priya-hal.mp4` at frame 0 (109 f) and
  `ep62-shot2-deflect.mp4` at frame 109 (124 f, `overlap_frames: 12`).
- The `episode` manifest and `media.shots` have 4 shots in this order: `shot@accuse` 0/124,
  `shot@deflect` 124/112, `ep65-shot-kf-priya-hal.mp4` 236/109, and `ep62-shot2-deflect.mp4`
  345/124. The last two carry `overlap_frames: 12`. start_sample is 0/248000/472000/690000.
- The file is 469 frames (248 + 233 − 12), 24 fps, 48 kHz stereo, 960×544.
It is a **finding** if any name reads `video N` or `bridge`, or if bridge's inner shots are
flattened into one.
Not asserted here: the last shot's `num_samples`, which read 247968 when this was written
(#435).
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F130 — `templates/assemble-and-score` at `sample_rate` 48000 resamples a 44.1 kHz score under a 48 kHz cut and keeps its shot map
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic)
The template's `sample_rate` defaults to 44100. Overriding it for a 48 kHz (LTX-bearing) cut
must *resample* the score, not relabel it (#180 is that trap in `slice_audio`/`fade_audio`).
The film must stay at 48 kHz with the input's inner shots. CPU only, about 6 s.
1. `validate_workflow(name="templates/assemble-and-score", workspace=<suite workspace>,
   arguments={"shots": ["asset:qa-cast/ep65-episode.mp4"], "score":
   "asset:qa-cast/ep15-song.mp3", "sample_rate": 48000, "total_frames": 469, "score_gain":
   0.3, "world_gain": 1.0})`, then `run_workflow` with the same name, workspace and arguments,
   `acknowledged_cost=<bound from the plan>`, `wait_seconds=55`.
2. `get_job_events(job_id)`, and `get_gallery_metadata` on the `film` file.
expected:
- `succeeded`. Validation is clean, and the plan has 8 steps and no downloads.
- The events carry `resample_audio` log lines `48000 → 48000` (the `world` step) and
  `44100 → 48000` (the `soundtrack_resampled` step), plus `mix_audio: 2 tracks, gains [0.3, 1.0]`.
- The film is 469 frames, 24 fps, 19.542 s, **48000 Hz** stereo, 960×544, with
  `peak_dbfs` ≤ −2.0 (the `balanced` step holds −3.0 on the mix; the AAC mux into the mp4 can
  land up to about 1 dB above it, per the template description, #497 — −2.17 measured
  2026-10-02, job `053a5047fd1c`; above −1.0 would be a finding). Its `media.shots` (and the `film` manifest) list the same 4 shots as
  the input: start_frame 0/124/236/345 and num_frames 124/112/109/124, the last two with
  `overlap_frames: 12`.
It is a **finding** if the film reads 44100 Hz, if the score's resample line is missing or
reads `44100 → 44100` / `48000 → 48000` (a relabel), or if the shots collapse to one, or if the film's peak is above −1.0 dBFS.
Not asserted here: a `joined_audio_short_after_mux` warning of 32 samples appeared when this
case was written (#435).
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F131 — `shot_dead_air` flags a near-silent gap inside a voiced shot, a room-tone bed clears it, and a quiet-throughout clip is spared
source: tester, verified in #465 (claude-opus-5-5 via anthropic)
A gap of digital near-silence between lines inside a shot plays as a dropout when hard-cut, and
`seam_hole` only looks at the joins. CPU only: two jobs of about 1 s each, plus read-only probes.
1. `assess_output(name="asset:qa-cast/ep62-episode.mp4")`, then the same with
   `probe="analyze_shots"`.
2. `assess_output(name="asset:qa-cast/priya-voice.wav", probe="analyze_shots")`.
3. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f131", "steps":
   [{"name": "bed", "task": {"command": "loop_audio", "arguments": {"audio":
   "asset:uploads/qa-cast/room-bed.wav", "target_frames": 248, "fps": 24}}}, {"name": "mix",
   "task": {"command": "mix_audio", "arguments": {"audios": ["asset:qa-cast/ep62-episode.mp4",
   "previous_result:bed"], "gains": [1.0, <g>]}}, "result": {"content_type": "audio/wav",
   "save": true}}]}, acknowledged_cost=true, wait_seconds=55)` twice: `<g>` = `1.0` (bedded) and
   `0.0` (bare control). Then `assess_output` on each `mix` file's `output:` reference.
expected:
- Step 1: a `shot_dead_air` finding, severity `warn`, `at.shot: "shot@deflect"`,
  `at.seconds` about 8.6, `threshold: 0.4`, `value` about 0.75. The fixture's manifest also
  overruns the file by 21 samples, so a `shot_span_overrun` finding at shot@deflect (#425) is
  allowed; it must be the only other finding, in both calls. In `analyze_shots`,
  `shot@deflect` carries `dead_air_seconds` about 0.75, `dead_air_at` about 8.62 and
  `dead_air_floor_dbfs` about −77. `shot@accuse` reads `0.0` / `null` / `null`.
  `rules_applied` includes `shot_dead_air`.
- Step 2: `rms_dbfs` about −37 and `dead_air_seconds` about 1.6, but **no** finding: the
  guard skips a shot at or below −30 dBFS.
- Step 3: the bare control reports `shot_dead_air` at about 8.6 s with a value of about 0.75.
  The bedded mix reports no finding, with `dead_air_seconds` ≤ 0.4.
It is a **finding** if step 1 has no `shot_dead_air`, if step 2 fires, if the bedded mix still
fires, or if the bare control doesn't.
cleanup: `delete_output(job_id=…)` for both jobs.
metrics: none.

### C-F132 — `normalize_audio(limit=true)` reaches a `target_lufs` the peak ceiling used to cap, under a true-peak ceiling, and leaves the default path alone
source: tester, spec for #496 from #474's plan v1 (claude-opus-5-5 via anthropic)
Without a limiter, one transient sets the peak and `target_lufs` stops at the `peak_dbfs`
ceiling with `target_lufs_capped` (#467). `limit: true` applies the full loudness gain and
limits the transients to a **true-peak** (dBTP, 4x oversampled) ceiling instead, with a
look-ahead on the gain curve only, so the signal is not delayed. The fixture's 16.47 dB
true-peak-to-loudness gap (see "Fixtures") means −16 LUFS at a −3 ceiling needs about 3.5 dB
of limiting: past the cap, under the 6 dB `limiter_heavy` line. The unlimited branches are the
positive control: a case that only checks the limited file passes when the fixture has
stopped needing a limiter at all. CPU only, seconds.
1. `get_task("normalize_audio")`.
2. `get_gallery_metadata("asset:qa-cast/ep11-coldopen.mp4")`, confirming the gap in "Fixtures".
3. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f132", "steps": [
   {"name": "capped", "task": {"command": "normalize_audio", "arguments": {"audio":
   "asset:qa-cast/ep11-coldopen.mp4", "target_lufs": -16, "peak_dbfs": -3}}, "result":
   {"content_type": "audio/wav", "save": true}},
   {"name": "capped_false", <same, arguments plus "limit": false>},
   {"name": "limited", <same, arguments plus "limit": true>},
   {"name": "limited_mux", "task": {"command": "pair_audio", "arguments": {"video":
   "asset:qa-cast/ep11-coldopen.mp4", "audio": "previous_result:limited", "sample_rate": 32000,
   "fit": "video"}}, "result": {"content_type": "video/mp4", "fps": 24, "save": true}}]},
   acknowledged_cost=true, wait_seconds=55)`. Validate the same inline workflow first; it is
   free.
4. `get_job(job_id)` for `warnings`, `get_job_events(job_id)` for the log events, and
   `get_gallery_metadata` on each saved file (the `limited_mux` one also with `envelope=true`,
   and the source asset with `envelope=true`).
expected:
- Step 1: `parameters` lists `limit`, default `false`, with a description that says it
  limits to reach `target_lufs` past the ceiling and that `peak_dbfs` is then a true-peak
  ceiling. `validate_workflow` on step 3's workflow is clean: `limit` is an accepted argument.
- **Default path unchanged.** `capped` and `capped_false` each carry a `target_lufs_capped`
  warning naming their step, and each step's log event reads `constraint: "peak_ceiling"`.
  Their files agree: `integrated_lufs` within 0.05 of each other (about −19.5), `peak_dbfs`
  within 0.05 (about −3.0). Neither log carries the limiter fields below.
- **The limited file reaches the target under the ceiling.** `limited`'s file: `integrated_lufs`
  within 0.5 LU of −16, and `true_peak_dbfs` ≤ −2.9 (−3.0 plus the plan's 0.1 tolerance).
  `job.warnings` has **no** `target_lufs_capped` and no `limiter_heavy` naming `limited`.
- **It says what it did.** `limited`'s log event carries `constraint: "limiter"`, `gain_db` > 0
  and at least the plain loudness gain (about +1.4 here; the searched static gain runs past it
  on this material, about +2.4; not the capped −2), `max_gain_reduction_db` > 0 and ≤ 6,
  `limited_fraction` strictly between 0 and 1, `output_true_peak_dbfs` ≤ −2.9 and `output_lufs`
  within 0.5 of −16. `output_lufs` and `output_true_peak_dbfs` agree with
  `get_gallery_metadata`'s reading of the file within 0.2.
- **No delay, no change of shape.** `limited`'s file is 19.667 s (±0.001), 32000 Hz, 2
  channels, the same as the source's audio.
- **The mux of it does not clip.** No `audio_clipped` (or `audio_no_headroom`) warning names
  `limited_mux`; its `peak_dbfs` is strictly below 0. It is 472 frames, 24 fps, 960×544,
  19.667 s. Its envelope has the same number of bins as the source's, and the loudest-rms bin
  and the first bin above −40 dBFS rms are at the same index in both: speech sits where the
  picture has it. (Per-second bins catch a gross offset only; sample-exact length is the
  bullet above, and sub-bin alignment is the server's own tests.)
It is a **finding** if `capped` no longer warns `target_lufs_capped` (the fixture or the
default path moved), if `capped` and `capped_false` differ, if `limited` misses −16 by more
than 0.5 LU, if its true peak is over −2.9, if its log reads `peak_ceiling` or lacks a limiter
field, if its length differs from the source's, or if its mux clips.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F133 — `normalize_audio(limit=true)` warns `limiter_heavy` past 6 dB of reduction, stops at 12 dB with `target_lufs_capped` and `limited: true`, and still holds the ceiling
source: tester, spec for #496 from #474's plan v1 (claude-opus-5-5 via anthropic)
The limiter never reduces by more than 12 dB, so a target past what 12 dB buys stops short and
says so with the existing warning, now marked as limited; beyond 6 dB it warns that pumping is
audible. On this dense fixture limiting costs loudness, so 12 dB at −3 reaches only about
−13.7 LUFS: −14.5 at −3 needs between 6 and 12 dB (heavy, not capped); −5 is capped. The ceiling itself is a boundary too: `peak_dbfs: 0` is a
0 dBTP ceiling, and the limiter must hold it there as well. CPU only, seconds.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f133", "steps": [
   {"name": "heavy", "task": {"command": "normalize_audio", "arguments": {"audio":
   "asset:qa-cast/ep11-coldopen.mp4", "target_lufs": -14.5, "peak_dbfs": -3, "limit": true}},
   "result": {"content_type": "audio/wav", "save": true}},
   {"name": "squashed", <same with "target_lufs": -5>},
   {"name": "full_scale", <same with "target_lufs": -12, "peak_dbfs": 0>}]},
   acknowledged_cost=true, wait_seconds=55)`.
2. `get_job`, `get_job_events`, and `get_gallery_metadata` on each file.
expected:
- `heavy`: a `limiter_heavy` warning naming the step; **no** `target_lufs_capped`. Log
  `max_gain_reduction_db` > 6 and ≤ 12. File `integrated_lufs` within 0.5 of −14.5,
  `true_peak_dbfs` ≤ −2.9.
- `squashed`: a `target_lufs_capped` warning naming the step, carrying `limited: true` and
  `shortfall_lu` > 0 (on the warning or on the step's log event; either placement meets the
  plan, and the case records which), **and** a `limiter_heavy` warning. Log
  `max_gain_reduction_db` ≤ 12.05. File `true_peak_dbfs` ≤ −2.9; `integrated_lufs` below −5,
  within 0.5 of −5 − `shortfall_lu`, and at least as loud as `heavy`'s.
- `full_scale`: `true_peak_dbfs` ≤ 0.1 and `integrated_lufs` within 0.5 of −12; no
  `target_lufs_capped`; `limiter_heavy` iff log `max_gain_reduction_db` > 6.
It is a **finding** if either ceiling is exceeded, if reduction passes 12 dB, if `squashed`
reaches −5 anyway (the cap is missing) or stops silently (no `target_lufs_capped`), if
`limited: true` or `shortfall_lu` is missing, or if `limiter_heavy` disagrees with
`full_scale`'s reduction or is missing on `heavy`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F134 — `normalize_audio(limit=true)` touches nothing when the ceiling isn't in the way, holds a true-peak ceiling without `target_lufs`, and passes silence through
source: tester, spec for #496 from #474's plan v1 (claude-opus-5-5 via anthropic)
The limiter must be a no-op when the gain already fits under the ceiling (−22 LUFS on the
fixture puts its true peak near −5.5), must still read `peak_dbfs` as true peak when only
peak-normalising, and must not divide by a silent track's zero peak. CPU only, seconds.
1. `run_workflow(workspace=<suite workspace>, inline_workflow={"id": "qa-c-f134", "steps": [
   {"name": "quiet_false", "task": {"command": "normalize_audio", "arguments": {"audio":
   "asset:qa-cast/ep11-coldopen.mp4", "target_lufs": -22, "peak_dbfs": -3}}, "result":
   {"content_type": "audio/wav", "save": true}},
   {"name": "quiet_true", <same plus "limit": true>},
   {"name": "peak_false", <audio as above, "peak_dbfs": -3 only>},
   {"name": "peak_true", <audio as above, "peak_dbfs": -3, "limit": true>},
   {"name": "silence", "task": {"command": "mix_audio", "arguments": {"audios":
   ["asset:qa-cast/ep11-coldopen.mp4"], "gains": [0.0]}}, "result": {"content_type":
   "audio/wav", "save": false}},
   {"name": "silent_false", "task": {"command": "normalize_audio", "arguments": {"audio":
   "previous_result:silence", "target_lufs": -16, "peak_dbfs": -3}}, "result":
   {"content_type": "audio/wav", "save": true}},
   {"name": "silent_true", <same plus "limit": true>}]},
   acknowledged_cost=true, wait_seconds=55)`. If a one-track `mix_audio` is refused, use
   two copies of the asset with `gains: [0.0, 0.0]`; the step only has to make digital
   silence of the fixture's length.
2. `get_job`, `get_job_events`, and `get_gallery_metadata` on each saved file.
expected:
- `succeeded`.
- **No-op:** `quiet_true`'s log reads `limited_fraction: 0` and `max_gain_reduction_db: 0`; no
  `target_lufs_capped` and no `limiter_heavy` names it. Its `integrated_lufs` and
  `true_peak_dbfs` equal `quiet_false`'s within 0.05, and the LUFS is within 0.5 of −22.
- **Peak-only:** `peak_true`'s `true_peak_dbfs` ≤ −2.9, and its log reads `limited_fraction`
  0 (a peak-normalising gain needs no limiting). Its `integrated_lufs` is at or a little
  below `peak_false`'s (within 0.3; the only difference is true peak vs sample peak), whose
  `peak_dbfs` is about −3.0.
- **Silence:** `silent_false` and `silent_true` both succeed with a silent file (same
  duration as the source, peak reported as silent in the same way on both). `silent_true`
  carries the same silent-track warning kind(s) as `silent_false`, no `limiter_heavy`, and no
  log claiming reduction (`limited_fraction`, if present, is 0).
It is a **finding** if `quiet_true` differs from `quiet_false`, if `peak_true` is over the
ceiling in true peak, or if either silent step fails, returns non-silence, or warns
differently from the other.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F136 — the series-episodes and minimax-music3 skills say when to pass `limit: true`, and that the default is to match downward
source: tester, spec for #497 from #474's plan v1 (claude-opus-5-5 via anthropic)
The plugin has no MCP surface, but its skills are what a driving session reads. Load them
with the `Skill` tool (`dw:series-episodes`, `dw:minimax-music3`); the plugin tree follows
`develop`.
expected:
- `dw:series-episodes`, in its normalize step and its loudness paragraph: episodes are matched
  **downward** to a series loudness every episode reaches, by default; `limit: true` is for a
  series that should sit louder than its most dynamic episode allows (an example such as −16
  for streaming); a `limiter_heavy` warning means lower the series target. It names
  `assemble-and-score`'s `limit` variable, or `normalize_audio`'s `limit`, as the way to pass it.
- `dw:minimax-music3`: one line saying the same for a song master (limit only to sit louder
  than the song's peaks allow; `limiter_heavy` means aim lower).
- Neither skill tells an agent to turn `limit` on by default.
It is a **finding** if either skill lacks the rule, recommends `limit: true` unconditionally,
or names a variable or warning the template and task don't have (check against C-F150 step 1
and C-F133's warning names).
cleanup: none.
metrics: none.

### C-F137 — `attribute_voices` is a listed command, not an assessment probe, and it must save JSON
source: tester, spec for #494 from #485's plan v1 (claude-opus-5-5 via anthropic)
Stage A adds the task `attribute_voices`. It returns JSON, like the probes, but the plan
gives `register_command` an explicit `assessment` flag so that a JSON return no longer
files a task under `assessment`. This case runs nothing and makes no GPU calls.
1. `list_tasks()`. Expected: `commands` contains `attribute_voices`. `assessment` is
   still exactly `analyze_seams`, `analyze_shots` and `analyze_sync_drift`: three
   entries, and `attribute_voices` is not among them.
2. `get_task("attribute_voices")`. Expected: a schema, not "Unknown task command". It
   has arguments `audio`, `voices`, `lines`, `windows`, `window_seconds`, `separate`
   (default `true`) and `device`. The minimum reference length (3 s, named
   `min_reference_seconds` in the plan) is either an argument or is named in a
   description. There is **no** model-name argument: the plan fixes htdemucs and ECAPA,
   so that nothing free-form reaches `torch.hub.load`.
3. `validate_workflow` on `{"id": "qa-c-f137", "steps": [{"name": "attr", "task":
   {"command": "attribute_voices", "arguments": {"audio":
   "asset:qa-cast/priya-voice.wav", "voices": {"a": [{"start_seconds": 0.0,
   "duration_seconds": 3.5}], "b": [{"start_seconds": 3.8, "duration_seconds": 3.5}]}}},
   "result": {"content_type": <ct>}}]}`, three times:
   - with `application/json`, expect `valid: true`;
   - with `text/plain`, expect `valid: false`, with an error on `steps[0].result` (or on
     its `content_type`) that names `application/json`;
   - with `audio/wav`, expect `valid: false` in the same form.
It is a **finding** if the task is missing from `commands`, if it appears under
`assessment` or the probe list changed, if `get_task` exposes a model-name argument, or if
a non-JSON content type validates.
cleanup: none.
metrics: none.

### C-F138 — known answer: `attribute_voices` names the right voice for each line and splits a window that straddles the join
source: tester, spec for #494 from #485's plan v1 (claude-opus-5-5 via anthropic)
This is the plan's known-answer check, and the test of its risk that ECAPA, a speech
encoder, may not tell voices apart. The clip is built from fixtures, so the singer at
each moment is known. The build runs on the CPU. The attribution loads htdemucs and
ECAPA, a few GPU-seconds.

**The duet steps.** C-F139 to C-F142 reuse these steps; in each case they come first in
the same workflow:
1. `bed`: `loop_audio` `{"audio": "asset:qa-cast/ep20-score.wav", "duration_seconds":
   20.5}`. This is a music bed, so the separation has work to do.
2. `hush`: `gain_audio` `{"audio": "asset:qa-cast/hal-voice.wav", "gain_db": -120}`.
   This gives 6.48 s of effective silence.
3. `voices_track`: `crossfade_audio` `{"audios": ["asset:qa-cast/priya-voice.wav",
   "asset:qa-cast/hal-voice.wav", "previous_result:hush"], "crossfade_ms": 10}`.
4. `duet`: `mix_audio` `{"audios": ["previous_result:voices_track",
   "previous_result:bed"], "gains": [1.0, 0.5]}`, saved as `audio/wav` to `final`.

The timeline, from the fixtures' lengths: Priya from 0 to about 7.44 s, then HAL to about
13.91 s, then the bed alone to the end. Read the end with `get_gallery_metadata` on the
`duet` output. Listen once with `get_output_audio` to confirm the two voices are audibly
different speakers. If they aren't, the fixtures have changed and the case can't run.

Then add these steps, each saving `application/json` to `final`:
5. `attr`: `attribute_voices` with:
   - `"audio": "previous_result:duet"`;
   - `"voices": {"priya": [{"start_seconds": 0.0, "duration_seconds": 3.5}], "hal":
     [{"start_seconds": 7.8, "duration_seconds": 3.2}]}`;
   - `"lines"`: `[{"start": 3.3, "end": 6.0, "text": "priya in-ref"}, {"start": 3.8,
     "end": 7.0, "text": "priya held-out"}, {"start": 8.0, "end": 10.5, "text": "hal
     in-ref"}, {"start": 11.2, "end": 13.6, "text": "hal held-out"}, {"start": 15.0,
     "end": 19.5, "text": "bed only"}]`;
   - `"windows"`: `[{"name": "shot_priya", "start": 0.0, "end": 7.0}, {"name":
     "shot_join", "start": 4.5, "end": 9.5}, {"name": "shot_hal", "start": 8.0, "end":
     13.5}, {"name": "shot_bed", "start": 15.0, "end": 19.5}]`.
6. `attr_alt_shape`: the same, except `lines` uses the other accepted shape,
   `{"start_seconds", "duration_seconds"}` (3.3/2.7, 3.8/3.2, 8.0/2.5, 11.2/2.4,
   15.0/4.5), and `text` is dropped from every line (`text` is optional).
7. `attr_clip_refs`: the same as `attr`, except `voices` names separate clips,
   `{"priya": "asset:qa-cast/priya-voice.wav", "hal": "asset:qa-cast/hal-voice.wav"}`.
   Use the reference form `get_task` shows for a clip.

Run `validate_workflow`, then `run_workflow(..., acknowledged_cost=true,
wait_seconds=55)`. Read each JSON with `get_output_text`.
expected:
- `attr.separated` is `true`, and `attr.voices` names `priya` and `hal`.
- Every line has `scores` for both voices, plus `voice`, `margin`, `voiced_seconds` and
  `uncertain`, and `text` is echoed unchanged.
- The two Priya lines have `voice: "priya"`, and the two HAL lines have `voice: "hal"`.
  The **held-out** lines (3.8–7.0 and 11.2–13.6) are the real test, because neither
  overlaps its reference span. All four lines have `uncertain: false` and `margin > 0`.
- The `bed only` line has `voice: null` and `uncertain: true`, with a stated reason (too
  little voiced audio). Its `voiced_seconds` is well under the line's 4.5 s.
- For windows: `shot_priya` has `voice: "priya"` and `shot_hal` has `voice: "hal"`, each
  with its own voice's `share` ≥ 0.8. `shot_join` has a split `share`, with each voice
  between 0.2 and 0.8, and its `voice` is the one with the larger share. Every window
  with voiced overlap has a `share` that sums to 1 (±0.05). `shot_bed` is `uncertain:
  true` and doesn't confidently name a voice.
- `reference_similarity` is present for the pair, and `voices_too_similar` is **not**
  reported.
- `attr_alt_shape` gives every line the same `voice` as `attr`, with scores within 0.02,
  and its lines carry no `text` (or `null`), not an error.
- `attr_clip_refs` gives the same `voice` on the four voiced lines, and `null` on `bed
  only`.
It is a **finding** if any held-out line names the wrong voice or is `uncertain`, if the
bed-only line names a voice, if `shot_join` isn't split, if a voiced window's `share`
doesn't sum to ~1, or if either alternative input form is refused. If ECAPA misnames a
held-out line here, that is the plan's stated trigger for Q2 (Resemblyzer): say so in the
issue.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F139 — `attribute_voices` without `lines` cuts fixed windows over the whole song, and `separate: false` runs on a dry stem
source: tester, spec for #494 from #485's plan v1 (claude-opus-5-5 via anthropic)
Use C-F138's duet steps (1–4). Then add these steps, each saving `application/json` to
`final`:
5. `attr_fixed`: `attribute_voices` with `audio: "previous_result:duet"` and C-F138's
   `voices`, and no `lines`, `windows` or `window_seconds`.
6. `attr_fixed5`: the same, with `"window_seconds": 5`.
7. `attr_dry`: `attribute_voices` on `"audio": "previous_result:voices_track"` (the
   voices with no bed, which is a dry stem), with C-F138's `voices` and `lines` and
   `"separate": false`.

Run it and read each JSON. Let D be the `duet` output's `duration_seconds` from
`get_gallery_metadata`.
expected:
- `attr_fixed` returns fixed 2.0 s windows as its per-line entries (or wherever
  `get_task` / `docs/TASKS.md` says fixed windows go). The first starts at 0, each starts
  where the last ended, and the last ends at D (±0.05). The count is `ceil(D / 2)`, and
  only the last window may be shorter than 2.0 s. None is dropped and none runs past D.
- In `attr_fixed`, the windows lying wholly inside 2–6 s name `priya`, the ones wholly
  inside 8–13 s name `hal`, and the ones wholly after 14.5 s have `voice: null` and
  `uncertain: true`. It reports `separated: true` (the default). The 0–2 s window may be
  `voice: null` (the fixture's opening holds one ~0.4 s word).
- `attr_fixed5` has `ceil(D / 5)` windows of 5 s, covering 0–D in the same way.
- `attr_dry` completes and reports `separated: false`. Its held-out lines name the right
  voice, as in C-F138.
It is a **finding** if the fixed windows leave a gap, overlap, or stop short of D, if
`window_seconds` is ignored, if `separate: false` errors or still reports `separated:
true`, or if the default run reports `separated: false`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F140 — one span under two names reports `voices_too_similar`, and every line is `uncertain`
source: tester, spec for #494 from #485's plan v1 (claude-opus-5-5 via anthropic)
Use C-F138's duet steps (1–4). Then add step 5, `attr_same`: `attribute_voices` with
`"audio": "previous_result:duet"`, `"voices": {"a": [{"start_seconds": 0.0,
"duration_seconds": 3.5}], "b": [{"start_seconds": 0.0, "duration_seconds": 3.5}]}`, and
C-F138's `lines`. It saves `application/json` to `final`. Run it and read the JSON.
expected:
- `reference_similarity` for `a`–`b` is about 1 (≥ 0.99).
- `voices_too_similar` is reported, in the result JSON or among the job's warnings
  (`get_job`).
- **Every** line has `uncertain: true`, including the ones that plainly contain Priya.
- The step completes: this is a warning, not a refusal.
It is a **finding** if the step refuses, if no `voices_too_similar` warning appears, or if
any line comes back `uncertain: false` and confidently names `a` or `b`.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F141 — `attribute_voices` refuses bad voices, short or out-of-range references and bad windows, and accepts the boundary
source: tester, spec for #494 from #485's plan v1 (claude-opus-5-5 via anthropic)
Each arm is a one-step workflow `attr` running `attribute_voices` on `"audio":
"asset:qa-cast/priya-voice.wav"` (7.453 s), with `"lines": [{"start": 0.5, "end": 3.0}]`
and `application/json` saved to `final`. Only `voices` (or `window_seconds`) differs.
Call `validate_workflow` on each arm. The plan allows a refusal "at validation or on the
step". If an arm validates, run it (`acknowledged_cost=true, wait_seconds=55`):
- a failure on the `attr` step whose error says the same thing counts as refused;
- a run that completes is a **finding**.
Refusal arms:
- (a) **One voice:** `{"a": [{"start_seconds": 0.0, "duration_seconds": 3.5}]}`. Refused;
  the message says at least 2 voices are needed.
- (b) **No voices:** `{}`. Refused the same way.
- (c) **Reference too short, in total:** `{"short": [{"start_seconds": 0.0,
  "duration_seconds": 1.5}, {"start_seconds": 2.0, "duration_seconds": 1.4}], "other":
  [{"start_seconds": 4.0, "duration_seconds": 3.0}]}`. That is 2.9 s in total. Refused,
  and the message **names `short`**.
- (d) **Span past the end:** `other` is `[{"start_seconds": 8.0, "duration_seconds":
  3.0}]`, with `short` as in (e). Refused, saying the span lies past the audio.
- (e) **Span straddling the end:** `other` is `[{"start_seconds": 5.0,
  "duration_seconds": 3.0}]` (ends at 8.0 > 7.453). Refused the same way. This must not
  be silently clamped.
- (f) **Bad voice name:** the key `"hal voice"` (a space) is refused. Then `"hal/../x"`
  is refused too. The message names the rule or the key.
- (g) **Missing asset:** `"other": "asset:qa-cast/no-such-voice.wav"` is refused at
  validation, as any missing `asset:` is.
- (h) **Bad window length:** no `lines`, and `"window_seconds": 0`, then `-1`. Refused.
  This is implied by the plan's fixed-window default rather than named by it.

Boundary control:
- (i) `{"priya_2": [{"start_seconds": 0.0, "duration_seconds": 1.5}, {"start_seconds":
  2.0, "duration_seconds": 1.5}], "other": [{"start_seconds": 4.0, "duration_seconds":
  3.0}]}`. That is exactly 3.0 s for `priya_2`, which is an underscore-and-digit name,
  and a span ending at 7.0 s. It validates and **runs to completion**. Its output may
  well say `voices_too_similar`, since both references are Priya; that is not a finding
  here.
expected: arms (a)–(h) are each refused, (c) names the voice, and none of them
completes. Arm (i) completes. A refusal at `validate_workflow` is preferred. A refusal on
the step passes, but note in any issue which arms were refused only at run time.
It is a **finding** if any refusal arm completes, if (e) is clamped instead of refused, if
(c)'s message doesn't name `short`, or if (i) is refused, since 3.0 s is the minimum, not
below it.
cleanup: `delete_output(job_id=…)` for every arm that ran.
metrics: none.

### C-F142 — a second `attribute_voices` run on the same box downloads nothing
source: tester, spec for #494 from #485's plan v1 (claude-opus-5-5 via anthropic)
The htdemucs weights come from Meta's CDN via torch.hub, not from HF, so
`plan.downloads_required` can't see them. The plan promises they are cached all the same.
Run C-F141's arm (i) workflow. Once it finishes, run it again with `rerun_job` or an
identical `run_workflow`. For each run, call `get_job_events` and `list_downloads`.
expected:
- The second run's events show no download or fetch of demucs or ECAPA weights.
- `list_downloads` shows no new entry started by the second run.
- The second run completes.
If the first run showed such a download (cold box), that is expected once. Note it as a
cold start.
It is a **finding** if the second run downloads either model again.
cleanup: `delete_output(job_id=…)` for both runs.
metrics: none.

### C-F143 — the minimax-music3 skill sends a duet to `attribute_voices`, not to pitch
source: tester, spec for #495 from #485's plan v1 (claude-opus-5-5 via anthropic)
Stage B is plugin-only. Load `dw:minimax-music3` with the `Skill` tool (the plugin tree
follows `develop`), and call `list_tasks()`.
expected:
- The skill says Music 3 ignores per-section singer directions.
- It says to run `attribute_voices`, with a reference span per singer, before staging
  lip-sync shots.
- It says not to infer the singer from pitch.
- `list_tasks().commands` contains `attribute_voices`.
- Any argument the skill names (e.g. `voices`, `lines`, `windows`) exists in
  `get_task("attribute_voices")`.
It is a **finding** if the skill doesn't name the task, still suggests a pitch method, or
names an argument the task doesn't have (the issue's own proposal said `references`,
which the plan replaced with `voices`).
cleanup: none.
metrics: none.

### C-F144 — a cut leaked 2.5 s or less into a shot is reported as `shot_opening_cut`, on the output and on a kept asset
pending: #493
source: tester, spec for #493 from #487's plan v2 (claude-opus-5-5 via anthropic)
#487: a generation whose first 1.5 s held the previous shot's picture before cutting to its
own passed every probe, because `analyze_seams` only looks at frame 0 of a shot and
`jump_ratio` is measured across the whole shot. Plan v2 adds two fields to each
`analyze_shots` per-shot record:
- `opening_jump_ratio`: the largest frame-to-frame delta in frames 1 through 2.0 s,
  divided by the shot's typical delta over the rest of the shot (the same scale as
  `jump_ratio`);
- `opening_cut_s`: when that frame falls, counted from the shot's start.
It also adds a rule, `shot_opening_cut`, with a measured threshold. This case builds a
leak with no shot records, so the whole file is one shot, and it runs CPU only (no model).

**Fixture** (one `run_workflow` in this suite's workspace, `wait_seconds=55`). The steps,
in order:
1. `still`: `loop_frames(video="asset:qa-cast/ep13-episode.mp4", num_frames=1)`.
2. `held`: `loop_frames(video="previous_result:still", num_frames=60)`, i.e. 2.5 s at
   24 fps of one unchanging picture.
3. `heldav`: `pair_audio(video="previous_result:held",
   audio="asset:uploads/qa-cast/room-bed.wav", fit="video")`. An `audio_trimmed_to_video`
   warning is expected.
4. `join`: `concat_videos(videos=["previous_result:heldav",
   "asset:qa-cast/ep3-shot1-incident.mp4"], fps=24)`. This makes 184 frames with 2 recorded
   shots, and the cut is at frame 60.
5. `frames`: `loop_frames(video="previous_result:join", num_frames=184)`.
6. `leak`: `pair_audio(video="previous_result:frames", audio="previous_result:join",
   fit="video")`, with `result` `{"content_type": "video/mp4", "fps": 24}`.

Steps 5–6 launder the join's shot records away. The gallery item for step 6 is the "leak
file". Its precondition: `get_gallery_metadata` shows `media.frame_count` 184 and no
`media.shots`. If shots are still present, record that in the run and go straight to the
`shots` override in C-F146 (shot `[0,184]`), which asserts the same thing. Also check
that the two frames either side of frame 60 differ visibly (`get_output_frames` on the
`join` output). The fixture is only valid if the cut is a real change of picture.

That leak file cuts at 2.5 s, outside the window. So this case asserts on a second leak
file built the same way with `held` at `num_frames=36` (a 1.5 s leak, 160 frames). Build
both in one workflow by duplicating steps 2–6 with a `36` suffix, or run the workflow
twice.

**Steps:**
1. `assess_output(name=<the 36-frame leak file>)` with the default probes.
2. `keep_output` that file as `qa-c-f144-leak` in this workspace, then
   `assess_output(name="asset:qa-c-f144-leak")` (or whichever form `assess_output` documents
   for an asset).
3. `assess_output` on the 60-frame (2.5 s) leak file.

expected:
- Steps 1–2: both carry one finding with rule `shot_opening_cut`.
  - Its `at` names the shot (the only one) and carries `opening_cut_s` within 1.5 ± 0.1.
  - The finding's measured value is above its own stated threshold.
  - The per-shot record (`probe="analyze_shots"`, or the detail form) has a non-null
    `opening_jump_ratio` and the same `opening_cut_s`.
  - Steps 1 and 2 agree.
- Step 3: `opening_cut_s` is no more than 2.0. The cut at 2.5 s is outside the window, so
  there is no `shot_opening_cut` finding, and both fields are non-null (the shot is
  7.67 s long).
- Nothing else about the report changes. `analyze_shots` still runs, and no new probe
  name appears.

It is a **finding** if:
- the 1.5 s leak passes with no `shot_opening_cut` (the #487 bug);
- `opening_cut_s` is off by more than 0.1 s;
- the kept-asset form disagrees with the output form;
- the 2.5 s leak fires, or reports an `opening_cut_s` beyond 2.0.

cleanup: `delete_output(job_id=...)` for every job, and `delete_asset("qa-c-f144-leak")`.
metrics: `opening_jump_ratio` of the 1.5 s leak (condition `leak-1.5s`).

### C-F145 — in a join with recorded shots, a shot's own hard cut at frame 0 is not an opening cut, and a short shot is skipped
pending: #493
source: tester, spec for #493 from #487's plan v2 (claude-opus-5-5 via anthropic)
The plan excludes frame 0 from the window, because the seam belongs to `analyze_seams`. It
also nulls both fields for a shot under 4 s and lists the rule in `rules_skipped`. This case
uses the `join` output from C-F144's fixture, built on its own if C-F144 already cleaned
up. That output has two shots:
- 0–60, which is 2.5 s, so short;
- 60–184, which is 5.17 s and opens on a hard cut at frame 0.

1. `get_gallery_metadata` on `join` confirms 2 entries in `media.shots`.
2. `assess_output(name=<join>, probe="analyze_shots", detail=true)` (or the detail form it
   documents).
3. `assess_output(name=<join>, probe="analyze_seams")`.

expected:
- Step 2: shot 1's record has `opening_jump_ratio: null` and `opening_cut_s: null`.
  - `rules_skipped` carries `shot_opening_cut`, with a reason naming the short shot or the
    4 s minimum.
  - Shot 2's record has both fields non-null.
  - Shot 2's `opening_cut_s` is not 0, since frame 0 is excluded.
  - There is no `shot_opening_cut` finding for either shot.
- Step 3 still reports the seam at frame 60 as before, so the seam stays `analyze_seams`'s.

It is a **finding** if:
- shot 2 fires `shot_opening_cut` at `opening_cut_s` ≈ 0 (the seam counted twice);
- shot 1 gets values or a finding instead of null + skipped;
- the whole report errors because one shot is short.

cleanup: `delete_output(job_id=...)` for any job this case ran.
metrics: none.

### C-F146 — window and length boundaries for `shot_opening_cut`, set through `analyze_shots`' `shots` override
pending: #493
source: tester, spec for #493 from #487's plan v2 (claude-opus-5-5 via anthropic)
This case pins the edges the plan implies, using the task form, which takes `shots=`. Each
step is one CPU `run_workflow` with a single `analyze_shots` step.
- The `video` is the `join` output from C-F144's fixture (60 held frames, then incident,
  184 frames, with the cut at frame 60), unless the step says otherwise.
- `shots` is a one-entry list shaped like the records `get_gallery_metadata(...).media.shots`
  returns for that join: copy one record and change its start and end frames to the values
  given.
- Read each run's per-shot record from its result (`get_output_text` or `get_job`).

Steps, with shot start–end frames (end exclusive):
1. `[24,184]`: the cut is 36 frames in (1.5 s).
2. `[13,184]`: the cut is 47 frames in (1.958 s), just inside the 2.0 s window.
3. `[11,184]`: the cut is 49 frames in (2.04 s), just outside.
4. `[59,184]`: the cut is 1 frame in (0.042 s), the earliest frame the window holds.
5. `[60,184]`: the cut is at frame 0, which is excluded.
6. `[0,184]`: the whole join as one shot, with the cut at 2.5 s.
7. The `video` is `asset:qa-cast/ep3-shot1-incident.mp4` with shot `[0,95]` (3.958 s), then
   `[0,96]` (4.000 s).

expected:
- Steps 1, 2 and 4: a `shot_opening_cut` finding each, with `opening_cut_s` within one frame
  (±0.042 s) of 1.5, 1.958 and 0.042 respectively.
- Steps 3, 5 and 6: no `shot_opening_cut` finding. `opening_cut_s` is non-null and at most
  2.0 in every one.
- Step 7:
  - `[0,95]` gives both fields `null` and `shot_opening_cut` in `rules_skipped`;
  - `[0,96]` gives both fields non-null and no finding (the incident is clean).
  - The plan says "under 4 s", so exactly 4.0 s is measured.

It is a **finding** if any step disagrees, or if `opening_cut_s` ever exceeds 2.0 or equals
0.

cleanup: `delete_output(job_id=...)` for each run, and for C-F144's fixture if this case
built it.
metrics: `opening_jump_ratio` of step 4 (condition `leak-1-frame`).

### C-F147 — clean shots stay clean: no `shot_opening_cut` on the incident or on a three-shot join of it
pending: #493
source: tester, spec for #493 from #487's plan v2 (claude-opus-5-5 via anthropic)
The threshold is "measured", so the guard against false positives is real footage with no
leak. This case uses the same fixture as C-F099:
1. `assess_output(name="asset:qa-cast/ep3-shot1-incident.mp4")`.
2. Run `concat_videos(videos=["asset:qa-cast/ep3-shot1-incident.mp4"] ×3, fps=24)` in this
   suite's workspace. That makes 372 frames, with shots at 0/124/248.
3. `assess_output` on the output of step 2.

expected:
- Neither report contains a `shot_opening_cut` finding.
- Every shot's `analyze_shots` record has non-null `opening_jump_ratio` and `opening_cut_s`
  (each shot is 5.17 s).
- In the join, the seams at 124 and 248 are not reported as opening cuts. Frame 0 of
  shots 2 and 3 is excluded.

It is a **finding** if clean footage fires the rule, or if a ≥4 s shot has null fields.

cleanup: `delete_output(job_id=...)` for step 2.
metrics: `opening_jump_ratio` of step 1 (condition `clean-incident`). That is the margin
the measured threshold has over clean footage.

### C-F148 — `shot_opening_cut` adds no new surface: no thumbnails, audio gate, probe whitelist, still, task schema and docs
pending: #493
source: tester, spec for #493 from #487's plan v2 (claude-opus-5-5 via anthropic)
The plan changes neither the tool, the probe list, the task's arguments nor the audio gate
(D2), and nulls the fields when there is no picture. All steps are free or CPU:
1. `assess_output(name="asset:qa-cast/priya-voice.wav", probe="analyze_shots")`. The file is
   audio only, so there are no thumbnails.
2. Take the `frames` output from C-F144's fixture (silent: `loop_frames` output, no
   `pair_audio`), with `keep_output` if a gallery name is needed, and run
   `assess_output(..., probe="analyze_shots")` on it.
3. `assess_output(name="asset:qa-cast/ep3-shot1-incident.mp4", probe="analyze_everything")`.
4. `assess_output(name="asset:qa-cast/hal-portrait.jpg")`.
5. `get_task("analyze_shots")`.
6. `list_guides`, then `get_guide` on the section holding `assess_output`'s rules table
   (the WORKFLOW_GUIDE's). Then the tasks guide's `analyze_shots` entry (`get_guide`
   "tasks").
7. Load the `dw:minimax-h3` skill with `Skill`.

expected:
- Step 1: the per-shot record is still returned (rms, dead_air, as in C-F131), with
  `opening_jump_ratio: null` and `opening_cut_s: null`. `shot_opening_cut` is in
  `rules_skipped`, with no error and no finding.
- Step 2: `analyze_shots` is not applicable because there is no audio, just as before #493.
  There is no error and no `shot_opening_cut` finding.
- Step 3: the same 400 as C-F102, naming exactly `analyze_shots`, `analyze_seams` and
  `analyze_sync_drift`.
- Step 4: not applicable for all three probes, as in C-F101.
- Step 5: the parameters are still exactly `video`, `shots` and `device`.
- Step 6:
  - the rules table lists `shot_opening_cut` with its threshold;
  - the tasks guide's `analyze_shots` answer names `opening_jump_ratio` and `opening_cut_s`;
  - no documented threshold contradicts the one reported in C-F144's finding.
- Step 7: the skill points to `shot_opening_cut` and no longer says to check the opening by
  eye or cites #487 as open.

It is a **finding** if any step disagrees, and in particular if the rule fires on an
audio-less file or with no picture, if a new probe or argument appears, or if the docs or
skill omit the rule.

cleanup: `delete_output(job_id=...)` and `delete_asset` for anything step 2 created.
metrics: none.

### C-F149 — `upload_asset`'s off-server refusal gives a runnable upload-route command for a remote client
source: tester, verified in #481 (claude-opus-5-5 via anthropic)
A client on another machine can't name its own file with `file_path`, and the refusal is
where it learns about the `POST /api/uploads` route. All the calls below are free and are refused.
1. `upload_asset(file_path="/nonexistent-client-path/x.png", asset_name="qa/x.png", workspace="regression-complete")`.
2. The same call without `workspace`.

expected:
- Both calls are refused, and nothing is uploaded.
- Each refusal contains a curl command with `Authorization: Bearer $DW_API_TOKEN` and
  `--data-binary @<file>`. The URL is `http://<host>:8765/api/uploads?filename=<name>&asset_name=<folder/name>&workspace=...`.
- It is a **finding** if the command's host is `127.0.0.1`, `localhost` or `0.0.0.0`. That address is
  the client's own machine. `<host>` is right, and so is an address that is really external.
- Step 1 fills in `&workspace=regression-complete`. Step 2 fills in the session's workspace. A
  `<ws>` placeholder or a missing `workspace=` is a finding.
- The refusal says the route answers 201 with `reference`, the `asset:` reference (the field
  was `path` until dw a90e3878, #527, dropped absolute server paths; `reference` is the real
  key). It gives the route's limit as 200MB and never says "no size cap". The upload bullet in
  `get_guide("workflows", section="Authoring a workflow from an agent")` → References → `asset:`
  carries the same command, the same 200MB limit and the same field name `reference`; a guide
  that still says `path` is a finding (#579).

cleanup: none (nothing is created).
metrics: none.

### C-F150 — `templates/assemble-and-score` with `limit: true` holds −3 dBTP on the mix, lands the film within 1 dB of it without clipping, and its description says so
source: tester, spec for #497 from #474's plan v2 (claude-opus-5-5 via anthropic)
Plan v2 (Q6 default (a)) moves where the ceiling is judged: the limiter holds −3.0 dBTP on
the `balanced` mix, and the AAC mux of the film may land up to about 1 dB above it (−2.54
measured on the first run). This replaces C-F135's film check (≤ −2.9 dBTP), which the
approved v2 plan changed on purpose. The fixture shot's crest (see "Fixtures") under a quiet
bed must still cap at −16 without the limiter; that capped control is what makes the
limited run mean anything. CPU only, three short runs.
1. `list_workflows(shape="sequence")` (read `assemble-and-score`'s entry and its
   description) and `get_workflow("templates/assemble-and-score")` for the full
   `description` and the `limit` default.
2. Common arguments: `{"shots": ["asset:qa-cast/ep11-coldopen.mp4"], "score":
   "asset:qa-cast/ep11-bed.wav", "total_frames": 472, "score_gain": 0.3, "world_gain": 1.0,
   "target_lufs": -16}`. `validate_workflow` then `run_workflow(name=
   "templates/assemble-and-score", workspace=<suite workspace>, arguments=…,
   acknowledged_cost=<bound from the plan>, wait_seconds=55)` three times: (a) as given,
   (b) plus `"limit": false`, (c) plus `"limit": true`.
3. For each: `get_job` warnings, `get_job_events` (the `balanced` step's log event), and
   `get_gallery_metadata` on the `film`.
expected:
- Step 1: `variable_names` include `limit` and `target_lufs`; `limit` defaults to `false`.
  The description says that with `limit` the −3 dBTP ceiling holds on the *mix* and that
  the encoded (AAC) film can land up to about 1 dB above it. It does **not** promise
  −3 dBTP (or "no overs past −3") on the film itself. `validate_workflow` is clean for all
  three argument sets.
- (a) and (b): each carries `target_lufs_capped` naming `balanced` (if neither does, the
  mix no longer needs a limiter: lower `score_gain` until (a) caps, and note it; that is a
  fixture problem, not a finding). Their `balanced` log reads `constraint: "peak_ceiling"`.
  Their films agree within 0.05 in `integrated_lufs` and `peak_dbfs`: the default is
  `false` and means the old behavior.
- (c): the `balanced` step's log event reads `constraint: "limiter"`, with
  `output_true_peak_dbfs` ≤ −3.0 (+0.05) and `max_gain_reduction_db` > 0. The film's
  `integrated_lufs` is within 0.5 LU of −16 and its `true_peak_dbfs` is ≤ −2.0. No
  `audio_clipped` and no `target_lufs_capped` in `job.warnings`. Record the film's
  `true_peak_dbfs` and the log's `output_true_peak_dbfs` in the report (the encode
  overshoot is their difference).
- All three films are 472 frames, 24 fps, 960×544, the same `duration_seconds`.
It is a **finding** if `limit` isn't a variable or defaults on; if (a) and (b) differ; if
(c)'s mix exceeds −3.0 dBTP, its film misses −16 by more than 0.5 LU or exceeds −2.0 dBTP,
or it warns `audio_clipped`; or if the description still promises −3 dBTP on the film.
cleanup: `delete_output(job_id=…)` for all three jobs.
metrics: none.

### C-F151 — `join_into_song` is discoverable: its arguments, defaults and domains are readable before anything runs
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
The task joins dialogue shots to song shots and lays a song under the join. A caller has
to be able to read its contract without running it. Read-only, free.
expected:
- `list_tasks` → `commands` contains `join_into_song`.
- `get_task("join_into_song")` lists exactly `dialogue`, `song_shots`, `song`,
  `cue_seconds`, `dialogue_target_lufs`, `duck_delay_ms`, `duck_db`, `duck_ramp_ms`, `fps`
  (plus the usual `device`):
  - `dialogue`, `song_shots` and `song` are required;
  - `cue_seconds` defaults to `0` with `"domain": "non_negative"`;
  - `dialogue_target_lufs` is optional with default `null` (omitted means no matching);
  - `duck_delay_ms` defaults to `0` (`non_negative`);
  - `duck_db` defaults to `-12` with a domain that refuses positive values (whatever
    its name, e.g. `non_positive`);
  - `duck_ramp_ms` defaults to `250` (`non_negative`).
  - `fps` is optional with default `null` and `"domain": "positive"` (used only when the
    videos carry no rate of their own).
  - Each parameter's `description` says what it does. `cue_seconds` must say it is the
    song time that lands on the first song shot's first frame. `song_shots` must say
    their own audio is discarded.
- `get_guide("tasks")` (or whichever guide `list_guides` indexes the task reference
  under) has a section for `join_into_song`.
It is a **finding** if the task is missing, a parameter above is missing or extra, a
default differs, a domain is absent, or `cue_seconds`'s description doesn't define the cue.
cleanup: none (read-only).
metrics: none.

### C-F152 — `join_into_song` places the song so its cue lands on the first song-shot frame, discards the song shots' audio, and records every shot
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
Plan v1's placement rule: the song starts at D − cue, where D is the joined dialogue's
length. So the song is audible under the tail of the dialogue, and song time `cue_seconds`
falls on the seam into the song shots. The song runs to the end of the picture. The song
shots' own audio contributes nothing, and the dialogue is gone once it ends.

The check is a marker. A 0.5 s hole cut into the song right at the cue has to land exactly
on the seam, and only there. The dialogue and song-shot fixtures all have loud audio of their
own, so silence in the hole proves both the placement and the discard. CPU only, no model.

Fixtures, all shared and listed under "Fixtures":
- dialogue: `asset:qa-cast/ep3-shot1-incident.mp4` then `asset:qa-cast/ep3-shot2-reply.mp4`.
  Each is 124 f, 24 fps, 960×544, with loud audio.
- song_shots: `asset:qa-cast/ep6-cold-open.mp4` then `asset:qa-cast/ep6-shot1-priya.mp4`.
  Same shape, loud own audio.
- song: `asset:qa-cast/ep15-song.mp3`, 30.02 s, 44.1 kHz stereo. It is loud around 2–4 s
  and its peak is +0.76 dBFS.

So D = 248 frames (10.333 s). With `cue_seconds: 3.0` the song enters at 7.333 s
(frame 176), and the seam S is frame 248.

**Steps:**
1. `validate_workflow`, then `run_workflow(..., wait_seconds=55)`, on an inline workflow
   with two steps:
   - `marked`: `gain_audio(audio="asset:qa-cast/ep15-song.mp3", gain_db=-60,
     start_seconds=3.0, duration_seconds=0.5)`. This cuts a hole over song time
     [3.0, 3.5).
   - `film`: `join_into_song(dialogue=[incident, reply], song_shots=[cold-open, priya],
     song="previous_result:marked", cue_seconds=3.0)` with `result:
     {"content_type": "video/mp4"}`. Leave every other argument at its default.
2. Measure windows of the film's audio. In one measurement workflow, add one `slice_audio`
   step per window: `audio` is the film's `output:` reference (as `get_job`'s manifest
   names it), with `start_frame`, `num_frames` and `fps: 24`, and each result is saved as
   `audio/wav`. Read each window's `mean_dbfs` with `get_gallery_metadata`. Windows are
   `[first, last)` in film frames:
   - A = [224, 247), the song under the dialogue's tail;
   - H = [249, 259), inside the hole;
   - R = [261, 285), the song after the hole.
   Also measure `asset:qa-cast/ep3-shot2-reply.mp4` frames [100, 123) the same way; call it
   Ref.
3. Run `get_gallery_metadata` on the film, then `assess_output(name=<film>,
   probe="analyze_sync_drift")`, `get_job_workflow(job_id)`, `list_gallery` and
   `export_job(job_id)`.
expected:
- `validate_workflow` is clean. The job `succeeded`, with one video/mp4 output.
- The film is 496 frames, 24 fps, 960×544, `duration_seconds` 20.667 (±1 frame).
- Placement, within one frame:
  - A is at least 6 dB above Ref: the song is audible before the first song-shot frame.
  - H is ≤ −50 dBFS: the song's cue sits on the seam, the dialogue has ended, and the
    song shots' audio is absent.
  - R is ≥ −35 dBFS: the song resumes after the hole.
- `media.shots` has 4 records named `ep3-shot1-incident.mp4`, `ep3-shot2-reply.mp4`,
  `ep6-cold-open.mp4` and `ep6-shot1-priya.mp4`, in that order. They cover
  [0,124), [124,248), [248,372) and [372,496), contiguously, summing to the film's
  `frame_count`, and each carries measured samples.
- The audio has one sample rate. The plan implies the song's (44100). Another rate is a
  note, not a finding, as long as the timing above holds.
- `job.warnings` carries `audio_no_headroom` and/or `audio_clipped`: the song peaks above
  full scale and the plan does no final normalization.
- `analyze_sync_drift` reports no drift.
- `get_job_workflow` shows all five `asset:` references (four shots and the song).
  `list_gallery` lists the film, and `export_job`'s bundle includes it.
It is a **finding** if:
- H is audible, meaning the song is misplaced or song-shot or dialogue audio leaks past
  the seam;
- A is not above Ref, meaning the song doesn't start before the seam;
- the shots are misnamed, missing or non-contiguous;
- no headroom warning appears on a mix this hot;
- sync drift is reported;
- or the job fails.
cleanup: `delete_output(job_id=…)` for the film job and the measurement job.
metrics: none.

### C-F153 — `join_into_song` ducks the dialogue by `duck_db` from song entry + `duck_delay_ms`, over a `duck_ramp_ms` ramp
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
The song enters under the dialogue. From song entry plus `duck_delay_ms`, the dialogue drops
by `duck_db`, and it gets there over a linear ramp of `duck_ramp_ms` rather than a step.

To measure the dialogue alone, mute the part of the song that plays under it:
`gain_audio(audio="asset:qa-cast/ep15-song.mp3", gain_db=-60, start_seconds=0,
duration_seconds=3.0)`, as step `quiet`. Use dialogue `[reply, incident]`, so the shot
under the song is the loud one, and song shots `[cold-open, priya]`. With `cue_seconds: 3.0`
the song enters at frame 176, and incident occupies film frames [124, 248).

Measure windows as C-F152 step 2 does, against the same frames of
`asset:qa-cast/ep3-shot1-incident.mp4`: film frame f corresponds to incident frame f − 124.
The level difference d(window) = film − incident, from `integrated_lufs` or `mean_dbfs`
(state which in the report).

Three runs, one `join_into_song` each, with song `previous_result:quiet`:
- (a) `duck_delay_ms: 1000`, `duck_db: -12`, ramp left at its default. The duck starts at
  frame 200 and is full by frame 206.
- (b) `duck_delay_ms: 0`, `duck_ramp_ms: 2000`, `duck_db: -12`. The duck ramps over frames
  [176, 224).
- (c) `duck_delay_ms: 0`, `duck_db: 0`. This is the zero-duck boundary.
expected:
- All three validate clean and succeed, each giving a 496-frame film.
- (a):
  - d([124,176)) is within ±0.5 dB: no duck before song entry.
  - d([176,200)) is within ±0.5 dB: no duck during the delay.
  - d([206,224)) is −12 ± 1 dB.
- (b): d for the 12-frame windows [176,188), [188,200), [200,212) and [212,224)
  never rises by more than 0.3 dB from one window to the next. The first window is
  ≥ −6.5 dB, and the last is between −13 and −8 dB: a ramp, not a step at either end.
- (c): d([176,224)) is within ±0.5 dB: `duck_db: 0` is accepted and ducks nothing.
It is a **finding** if:
- the duck starts before the delay or is missing;
- its depth misses −12 by more than 1 dB;
- (b)'s first window is already at full depth (a step);
- or `0` is refused for `duck_db` or `duck_delay_ms`.
cleanup: `delete_output(job_id=…)` for all three runs and the measurement jobs.
metrics: none.

### C-F154 — `dialogue_target_lufs` levels each dialogue shot statically, omitting it leaves them alone, and a sub-400 ms shot is warned about, not failed
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
The two dialogue fixtures sit about 11 LU apart: incident's integrated loudness is −16.4
LUFS and reply's is −27.4. With a target, each shot gets one static gain to reach it. With
no target, nothing changes.

Use the song muted over the part that plays under the dialogue: `gain_audio(audio=
"asset:qa-cast/ep15-song.mp3", gain_db=-60, start_seconds=0, duration_seconds=0.5)`.
Use `cue_seconds: 0.5`, so the song enters at frame 236. Dialogue is `[incident, reply]`,
and song shots are `[cold-open, priya]`. Measure `integrated_lufs` of film windows
W1 = [0,124) and W2 = [124,236) as in C-F152 step 2.
- (a) `dialogue_target_lufs: -23`.
- (b) The same run without `dialogue_target_lufs`.
- (c) As (a), but the dialogue is `[incident, short8, reply]`. `short8` is an 8-frame
  (333 ms) shot with audio, built in the same workflow:
  - `loop_frames(video="asset:qa-cast/ep3-shot1-incident.mp4", num_frames=8)`;
  - `slice_audio(audio="asset:qa-cast/ep3-shot1-incident.mp4", start_frame=0,
    num_frames=8, fps=24)`;
  - `pair_audio` of those two, with `fit: "video"`, at 24 fps. Set the rate with
    `result.fps` if the frames don't carry one (C-F009).

  If the join refuses `short8` for a rate mismatch, the fixture is wrong: fix it, don't
  file it. The film is then 504 frames. Measure W1 = [0,124) and W2' = [132,244), using
  song entry at frame 244 for this D.
expected:
- (a):
  - W1 and W2 are each within 1.5 LU of −23, and within 1.0 LU of each other.
  - `job.warnings` carries no clipping warning for the dialogue.
- (b): W1 and W2 are each within 0.5 LU of their source shots' own levels (the ~11 LU
  spread survives).
- (c):
  - The job `succeeded`.
  - `job.warnings` has an entry naming the short shot (by its `shot@…` name or index)
    that says it was left unmatched because it is under 400 ms.
  - W1 and W2' are still within 1.5 LU of −23.
  - `media.shots` has 5 records.
It is a **finding** if:
- (a) leaves a spread over 1 LU or misses the target;
- (b) changes the levels;
- or (c) fails, or passes the short shot without a warning.
cleanup: `delete_output(job_id=…)` for every run and measurement job.
metrics: none.

### C-F155 — a dialogue input with no audio track becomes silence of its own length, not a shift of everything after it
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
`concat_videos` has a known desync when an input has no audio. Plan v1 says `join_into_song`
fills silence for such an input instead of inheriting that desync.

**Setup:** a silent 124-frame, 24 fps mp4. Run a one-step workflow: `loop_frames(video=
"asset:qa-cast/ep3-shot2-reply.mp4", num_frames=124)` with `result: {"content_type":
"video/mp4", "fps": 24}`. Confirm with `get_gallery_metadata` that the file has no audio
stream. If it has one, the fixture is wrong: fix it, don't file it.

**Run:** `join_into_song(dialogue=[<the silent mp4's output: reference>,
"asset:qa-cast/ep3-shot2-reply.mp4"], song_shots=[cold-open, priya], song=<the C-F154
muted song>, cue_seconds=0.5)`. Measure windows as in C-F152 step 2.
expected:
- The job `succeeded`, and the film is 496 frames.
- Film [0,124) has `mean_dbfs` ≤ −50.
- Film [124,236) is within 0.5 dB (`mean_dbfs`) of reply's own frames [0,112): reply's
  audio sits under reply's pictures, not 124 frames early.
- `media.shots` has 4 records at [0,124), [124,248), [248,372) and [372,496).
- `analyze_sync_drift` reports no drift.
It is a **finding** if:
- the join refuses or fails on an input without audio;
- the reply audio is shifted onto the first shot;
- or the film's audio runs shorter than its picture by a shot.
cleanup: `delete_output(job_id=…)` for the setup, run and measurement jobs.
metrics: none.

### C-F156 — `join_into_song` refuses out-of-domain arguments, empty lists, an over-long cue and a frame-rate mismatch, each pointed at its cause
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
The refusals the plan names, plus the boundaries either side of them.

In every arm, the base step is `join_into_song(dialogue=[incident, reply],
song_shots=[cold-open, priya], song="asset:qa-cast/ep15-song.mp3")`.
expected:
- **1. Domains, statically.** `validate_workflow` with `cue_seconds: -1`,
  `duck_delay_ms: -1`, `duck_ramp_ms: -1` and `duck_db: 3` returns `valid: false` with
  **four** errors, one per argument. Each error's path is
  `steps[0].task.arguments.<name>` and its message names that argument.
- **2. The legal zeros.** `cue_seconds: 0`, `duck_delay_ms: 0`, `duck_ramp_ms: 0` and
  `duck_db: 0` together validate clean.
- **3. Empty lists.** `song_shots: []` is refused, and so, separately, is `dialogue: []`.
  The refusal comes either from `validate_workflow` with a path ending in the argument's
  name, or from a run that `failed` with an empty manifest and an error naming the
  argument. Either layer satisfies the case. A `succeeded` job is the finding.
- **4. Cue past the dialogue.** D = 248 frames = 10.333 s.
  - `cue_seconds: 10.375` (D + 1 frame): the run is refused or fails before writing a
    film. The error names `cue_seconds` and the dialogue's length (~10.33 s), so a
    caller knows what to shorten.
  - `cue_seconds: 10.29` (D − 1 frame): succeeds with a 496-frame film.
- **5. Frame-rate mismatch.** Replace `song_shots[0]` with a 12 fps copy of the cold open,
  made in the same workflow by `pair_audio(video="asset:qa-cast/ep6-cold-open.mp4",
  audio="asset:qa-cast/ep6-cold-open.mp4")` with `result.fps: 12` (as C-F009's override
  arm does). The join is refused or fails with no film written, and the error names both
  rates (24 and 12). A mismatched frame size is refused by the plan too, but no CPU fixture
  makes one, so it isn't covered here.
It is a **finding** if:
- any arm in 1, 3, 4 or 5 produces a film;
- part 1 reports fewer than four errors, or errors at the wrong paths;
- part 2 is refused;
- or part 4's error doesn't name `cue_seconds` and the dialogue length.
cleanup: `delete_output(job_id=…)` for every job that ran, failed ones included.
metrics: none.

### C-F157 — `join_into_song` edges: a cue of 0 starts the song on the seam, and a song too short for the picture is padded with silence and warned
source: tester, spec for #513 from #486's plan v1 (claude-opus-5-5 via anthropic)
- (a) **Cue 0.** Run C-F152's `film` step with the unmarked song
  (`asset:qa-cast/ep15-song.mp3`) and `cue_seconds: 0`.
- (b) **Short song.** Run the same step with `song: "asset:uploads/qa-cast/room-bed.wav"`
  (4.96 s, 16 kHz mono, so it is also resampled) and `cue_seconds: 1.0`. The song enters at
  frame 224 and runs out near frame 343, but the picture runs to frame 496.

Measure windows as in C-F152 step 2.
expected:
- (a):
  - The job `succeeded`, and the film is 496 frames.
  - Film [0,124) is within 0.5 dB (`mean_dbfs`) of incident's own frames, and [124,248)
    of reply's: no song and no duck before the seam.
  - Film [249,260) is ≥ −35 dBFS: the song opens on the seam.
- (b):
  - The job `succeeded`, with a `job.warnings` entry `song_short`.
  - The film is 496 frames, and its audio runs the picture's length (per `media.shots`,
    which has 4 records).
  - Film [360,496) is ≤ −50 dBFS: padded silence, with no song-shot audio.
  - Film [250,330) is at least 20 dB above that.
It is a **finding** if:
- (a) puts song audio before the seam;
- (b) fails, trims the picture to the song, or doesn't warn `song_short`;
- or (b)'s tail carries audio.
cleanup: `delete_output(job_id=…)` for both runs and the measurement jobs.
metrics: none.

### C-F158 — the dialogue-into-song recipe the skill and guide teach produces C-F152's placement when followed verbatim
source: tester, spec for #514 from #486's plan v1 (claude-opus-5-5 via anthropic)
Stage B teaches the recipe: `slice_audio` slices starting at `cue_seconds` (to condition
the song shots), then `join_into_song`, then `normalize_audio`, then `pair_audio`. The
point of the case is that a caller who reads only the docs gets the cue right.

**Read:**
- Load the `dw:minimax-music3` and `dw:minimax-h3` skills; the recipe is in one of them.
- Read the `docs/WORKFLOW_GUIDE.md` content via `get_guide` (the guide `list_guides`
  indexes it under, and the section the skill cross-references).

**Run:** follow the recipe verbatim with C-F152's fixtures:
- the marked song from C-F152 step 1, with `cue_seconds: 3.0`;
- dialogue `[incident, reply]`;
- song shots `[cold-open, priya]` standing in for the generated song shots. Skip the
  generation step, and nothing else.
expected:
- The skill states the four-step order above. It says in so many words that `cue_seconds`
  is the start of the first song shot's `slice_audio` slice.
- The skill links to the guide section, and the guide section exists and agrees with the
  skill.
- The recipe's first song-shot `slice_audio(song, start_seconds=3.0, …)` of the marked
  song opens with the hole: its first 10 frames are ≤ −50 dBFS. So the slice and the join
  share one cue.
- The final film:
  - 496 frames, with `media.shots` still at 4 records named as in C-F152.
  - C-F152's H window is ≤ −50 dBFS, and its A window is at least 6 dB above Ref.
  - No `audio_clipped` or `audio_no_headroom` in the last step's warnings, because
    `normalize_audio` took the headroom C-F152 warns about.
  - `analyze_sync_drift` reports no drift.
It is a **finding** if:
- the recipe is missing from both skills;
- the order differs;
- `cue_seconds` is described as anything but the slice start;
- the guide cross-reference is dead;
- or the verbatim recipe gives a film whose placement, shot records or headroom differ
  from the above. Say whether the recipe text or the task is at fault.
cleanup: `delete_output(job_id=…)` for every job the recipe ran.
metrics: none.

### C-F159 — `find_loop_bed` is discoverable as a command, not an assessment probe, with the plan's arguments and defaults
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
The task is registered `returns="json"`, `assessment=False`. It must be listed with the
utility commands, and the assessment list must not grow. Read-only.

**Calls:**
- `list_tasks()`
- `get_task(name="find_loop_bed")`
- `list_guides()`, then `get_guide("tasks", section=<the find_loop_bed section>)`
expected:
- `list_tasks` lists `find_loop_bed` under `commands`. `assessment` is exactly the three
  probes it held before this stage, and `find_loop_bed` is not one of them.
- `get_task` shows `audio` as required, and these optional arguments with these defaults:

  | argument | default |
  |---|---|
  | `start_seconds` / `end_seconds` | whole file (null or absent) |
  | `min_seconds` | 0.5 |
  | `max_seconds` | 2.0 |
  | `max_bin_dbfs` | −55 |
  | `max_mean_dbfs` | −60 |
  | `max_spike_db` | 12 |
  | `crossfade_ms` | 250 |
  | `loop_seconds` | 10 |
  | `target_bed_dbfs` | −60 |
  | `max_candidates` | 5 |
  | `device` | the server default |

  It also states that the result is JSON.
- The tasks guide has a `find_loop_bed` section. It names the output's `candidates` and
  `rejected` blocks, and says the candidate's `start_seconds`/`duration_seconds` feed
  `slice_audio` and its `gain` feeds `mix_audio`.
It is a **finding** if:
- the task is missing, or is listed under `assessment`;
- the assessment list changed;
- any default differs from the table;
- or there is no guide section.
cleanup: none (read-only).
metrics: none.

### C-F160 — `find_loop_bed` on a quiet bed with one click: ranked, non-overlapping candidates that avoid the click, with the full reading set
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
The known-answer case. It uses a bed quiet enough to pass the default thresholds, with a
single 1 ms click at 5.5 s. The click sits clear of the ~−47.8 dB bumps that
`ep51-bed.wav` carries in seconds 3, 7, 11 and 15.

**Setup:** one inline workflow in the suite workspace, `acknowledged_cost=true,
wait_seconds=55`, with three steps:
1. `bed`: `gain_audio(audio="asset:qa-cast/ep51-bed.wav", gain_db=-30)`, saved as
   `audio/wav`. The mean is about −80 dBFS. No sample can exceed about −58.9, so every bin
   is ≤ −55.
2. `clicked`: `gain_audio(audio="previous_result:bed", gain_db=20, start_seconds=5.5,
   duration_seconds=0.001)`, saved as `audio/wav`.
3. `find`: `find_loop_bed(audio="previous_result:clicked")`, all defaults, with
   `result: {"content_type": "application/json", "save": true}`.

**Control:** the same workflow with `find` pointed at `previous_result:bed`, or a
fourth step `find_control` over `bed`. Read both JSONs with `get_output_text`.
expected:
- The workflow validates clean, and the job succeeds.
- The top level has `source`, `criteria`, `candidates`, `rejected` and `findings`.
  - `source.duration_seconds` is 15.5 (±0.05) and `source.sample_rate` is 16000.
  - `source.searched` is `[0, 15.5]` (±0.05), and `source.shots_source` is null.
  - `criteria` echoes the defaults: `max_bin_dbfs` −55, `max_mean_dbfs` −60,
    `max_spike_db` 12, `crossfade_ms` 250, `loop_seconds` 10. It also carries
    `tonal_flatness` 0.3 and `harmonicity` 0.45.
- The control returns at least one candidate. If it returns none, the fixture is too
  spiky for the default 12 dB crest test. That is a **fixture note**, not a task finding:
  re-run both arms with `max_spike_db: 25` and `gain_db: 30` on the click, and judge them
  against the rest of this list.
- In the clicked arm:
  - Between 1 and 5 candidates, never more than `max_candidates`. `rank` runs 1..n.
  - `looped.ripple_db` is non-decreasing with rank.
  - Every candidate has `start_seconds`, `duration_seconds`, `end_seconds`, `shot` (null
    here), `mean_dbfs`, `max_bin_dbfs`, `spike_db`, `flatness`, `harmonicity`, `looped`,
    `gain_db`, `gain` and `warnings`. `looped` has `ripple_db`, `envelope_peak_db`,
    `envelope_peak_hz`, `lap_hz` and `lap_component_db`.
  - `duration_seconds` is in [0.5, 2.0] and on the 50 ms grid (a multiple of 0.05,
    ±0.001). `end_seconds` = `start_seconds` + `duration_seconds` (±0.001), and the
    candidate lies inside [0, 15.5].
  - No two candidates overlap in time.
  - No candidate's [start, end] contains 5.5 s.
  - Each candidate's `mean_dbfs` ≤ −60, `max_bin_dbfs` ≤ −55, `spike_db` ≤ 12,
    `flatness` ≥ 0.3 and `harmonicity` < 0.45.
  - `gain` = 10^(`gain_db`/20) (±1 %), and `mean_dbfs` + `gain_db` ≈ −60 (±1 dB), the
    default `target_bed_dbfs`.
  - A candidate whose `looped.envelope_peak_db` is above −15 has `"lap_modulation"` in
    `warnings`. Any other candidate does not.
- `rejected` has `too_loud`, `silent`, `spike` and `tonal`, each an integer ≥ 0. The
  clicked arm's `rejected.spike` is ≥ 1 and greater than the control's.
It is a **finding** if:
- any expectation above fails;
- or a candidate covers the click, since the spike test missed it.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F161 — `find_loop_bed` rejects a window with a voice under it (the near-programme trap)
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
A voice mixed far down under a bed can pass the level tests. The plan's tonal test
(flatness ≥ 0.3 and harmonicity < 0.45 to pass) is what must catch it.

**Setup:** an inline workflow, `acknowledged_cost=true, wait_seconds=55`:
1. `bed`: `gain_audio(audio="asset:qa-cast/ep51-bed.wav", gain_db=-10)`, mean about
   −60, saved as wav.
2. `voiced`: `mix_audio` of `previous_result:bed` and `asset:qa-cast/priya-voice.wav` with
   gains `[1.0, 0.01]`, a −40 dB voice at an rms of about −77, saved as wav.
3. `find`: `find_loop_bed(audio="previous_result:voiced", start_seconds=0,
   end_seconds=7.0, max_bin_dbfs=-40, max_mean_dbfs=-50, max_spike_db=30,
   max_candidates=20)`, saved as `application/json`.

The level thresholds are loosened so only the tonal test can separate voiced windows from
bed-only ones.

**Control:** the same workflow with voice gain `0.0` in step 2.
expected:
- Both jobs succeed.
- The voiced arm's `rejected.tonal` is greater than the control's.
- Every candidate in either arm has `flatness` ≥ 0.3 and `harmonicity` < 0.45.
- The voiced arm has no more candidates than the control.
It is a **finding** if the voice changes nothing in `rejected.tonal`, or a returned
candidate fails its own tonal criteria. In the finding, quote the voiced candidate's
`flatness`/`harmonicity`.
cleanup: `delete_output(job_id=…)` for both.
metrics: none.

### C-F162 — `find_loop_bed` with nothing to find: an empty answer with a reason, not a failed job (too loud; digital silence)
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
The plan says "no candidates" is an answer: `candidates: []`, the rejected counts, and one
finding naming what to relax. It also says digital silence is rejected as `silent`, never
offered as a bed.

**Loud arm:** `find_loop_bed(audio="asset:qa-cast/ep15-song.mp3", start_seconds=2,
end_seconds=4)`, all other arguments default, saved as `application/json`.

**Silent arm:**
1. `pad`: `slice_audio(audio="asset:uploads/qa-cast/room-bed.wav", start_seconds=0,
   duration_seconds=8.0)`. The source is 4.96 s, so this pads with digital zeros; saved
   as wav.
2. `find`: `find_loop_bed(audio="previous_result:pad", start_seconds=5.2,
   end_seconds=7.9)`, saved as `application/json`.

If `slice_audio` refuses to read past the end rather than padding, build the silence
another way, e.g. `gain_audio(audio=<room-bed>, gain_db=-200)` if that yields exact zeros.
Note the substitution.
expected:
- Both jobs **succeed**. Neither is a failed job or a validation refusal.
- Loud arm:
  - `candidates` is `[]` and `rejected.too_loud` > 0.
  - `findings` has exactly one entry, and it names at least one argument to relax (e.g.
    `max_bin_dbfs` / `max_mean_dbfs`).
  - `source.searched` is `[2, 4]`.
- Silent arm:
  - `candidates` is `[]` and `rejected.silent` > 0.
  - No window there is reported under `too_loud` or `spike`, and there is one finding.
It is a **finding** if:
- an empty search fails the job;
- the findings list is empty or has several entries;
- digital silence is returned as a candidate;
- or silence is counted under a bucket other than `silent`.
cleanup: `delete_output(job_id=…)` for both.
metrics: none.

### C-F163 — `find_loop_bed` arguments move the answer in the right direction
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
Every threshold must act in its stated direction and be echoed in `criteria`. Uses C-F160's
`clicked` setup: re-run it, or point `audio` at C-F160's saved clicked wav via `output:`
before its cleanup. Take its default result as the baseline `D`.

**Arms:** each is one `find_loop_bed` call over the clicked bed, saved as
`application/json`:
1. `max_spike_db` = (the smallest `spike_db` among `D`'s candidates) − 0.5.
2. `max_bin_dbfs` = (the smallest `max_bin_dbfs` among `D`'s candidates) − 0.5.
3. `max_candidates: 1`.
4. `min_seconds: 1.0, max_seconds: 1.0`.
5. `target_bed_dbfs: -50`.
expected:
- Every job succeeds, and each arm's `criteria` shows the value it passed.
- Arm 1: `rejected.spike` is greater than in `D`, and every candidate has `spike_db` ≤ the
  new ceiling.
- Arm 2: `rejected.too_loud` is greater than in `D`, and every candidate has
  `max_bin_dbfs` ≤ the new ceiling.
- Arm 3: exactly one candidate. It has the same `start_seconds`/`duration_seconds` as
  `D`'s rank 1 (±0.001).
- Arm 4: every candidate has `duration_seconds` 1.0 (±0.001).
- Arm 5: for the candidate at the same start as in `D`, `gain_db` is 10 dB higher than
  in `D` (±0.5).
It is a **finding** if a threshold moves the counts the wrong way or not at all, a
returned candidate breaks the criteria it was searched under, or `criteria` misreports a
passed value.
cleanup: `delete_output(job_id=…)` for every arm.
metrics: none.

### C-F164 — `find_loop_bed` on video sources: decodes audio only, from an asset, an `output:` and a `previous_result:` AudioVideo
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
The plan says a video source is decoded audio-only (no frames). It also says the task
accepts a `previous_result:` AudioTrack or AudioVideo.

**Arms:** each saves as `application/json`, `acknowledged_cost=true, wait_seconds=55`:
1. **Asset:** `find_loop_bed(audio="asset:qa-cast/long-film-4089.mp4")`. The film is
   170.4 s long.
2. **`output:`:**
   - A first run: `concat_videos` of `asset:qa-cast/ep3-shot1-incident.mp4` and
     `asset:qa-cast/ep3-shot2-reply.mp4`, saved as `video/mp4`.
   - A second run: `find_loop_bed(audio="output:<that run's mp4>")`.
3. **`previous_result:`:** one workflow with a `concat_videos` step as in arm 2 and a
   `find_loop_bed(audio="previous_result:<concat step>")` step.
expected:
- All three jobs succeed. None fails the output type, and none says "audio required".
- Arm 1:
  - `source.duration_seconds` is 170.4 (±0.1).
  - The job completes in under 60 s wall clock (`get_job` timing). At ≥ 120 s it is a
    finding: frames were decoded, or the search is quadratic.
- Arms 2 and 3:
  - `source.duration_seconds` is 10.33 (±0.05): 248 frames at 24 fps.
  - `source.sample_rate` is the clips' audio rate, 32000.
  - The two arms agree up to the lossy re-encode the `output:` form went through: the same
    number of candidates, each with the same `start_seconds`/`duration_seconds` (±0.05);
    each `rejected` bucket equal to within ±3; the same findings `rule`/`rejected_by`. A
    wider gap is a finding. The ep3 audio is
    loud, so `candidates: []` with a `too_loud` count and one finding is a correct
    answer here.
It is a **finding** if a video source is refused, or the durations are wrong. Also if the
`previous_result:` and `output:` forms disagree, or arm 1 exceeds the time bound.
cleanup: `delete_output(job_id=…)` for every job.
metrics: none.

### C-F165 — `find_loop_bed` argument domains are refused at validate, with the boundaries accepted; JSON-only saving
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
Free: `validate_workflow` only. Each arm is a one-step inline workflow,
`find_loop_bed(audio="asset:uploads/qa-cast/room-bed.wav", <arm>)` saved as
`application/json` unless the arm says otherwise.

| arm | argument | expected |
|---|---|---|
| r1 | `min_seconds: 0` | refused |
| r2 | `min_seconds: -1` | refused |
| r3 | `max_candidates: 0` | refused |
| r4 | `crossfade_ms: -1` | refused |
| r5 | save as `text/plain` | refused |
| r6 | save as `audio/wav` | refused |
| a1 | `crossfade_ms: 0` | valid |
| a2 | `max_candidates: 1` | valid |
| a3 | `min_seconds: 0.05` | valid |
| a4 | all defaults, `application/json` | valid |

expected:
- r1–r4: `valid: false`. The error names the step and the argument, and states the domain
  (e.g. "> 0", "≥ 0").
- r5–r6: `valid: false`, saying the task returns JSON.
- a1–a4: `valid: true`, with no error.
It is a **finding** if:
- a bad value validates. Say whether it then fails at run time, or runs;
- a boundary value is refused;
- or the error omits the argument name.
cleanup: none (validate only).
metrics: none.

### C-F166 — `find_loop_bed` run-time refusals: an impossible range or window fails the job naming the argument
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
These depend on the source's length, so the plan puts them at run time. A refusal at
validate is also acceptable wherever the server can know the length. Source for every arm:
`asset:uploads/qa-cast/room-bed.wav`, 4.96 s. Each arm is one `find_loop_bed` step saved
as `application/json`, `acknowledged_cost=true, wait_seconds=55`.

| arm | arguments | refuses because |
|---|---|---|
| f1 | `start_seconds: 2, end_seconds: 2` | end ≤ start |
| f2 | `start_seconds: 3, end_seconds: 1` | end ≤ start |
| f3 | `min_seconds: 1.5, max_seconds: 1.0` | min > max |
| f4 | `end_seconds: 6.0` | range past the end of the file |
| f5 | `start_seconds: 5.5` | range past the end of the file |
| f6 | `min_seconds: 5, max_seconds: 6` | source shorter than `min_seconds` |
| ok | `end_seconds: 4.96` | accepted: the exact end of the file |

expected:
- f1–f6 are each a validation refusal or a failed job. The error names the offending
  argument or arguments (`end_seconds`/`start_seconds`, `min_seconds`/`max_seconds`)
  and, for f4–f6, the source's duration.
- No arm among f1–f6 succeeds with an empty or clamped result.
- `ok` succeeds with `source.searched` `[0, 4.96]` (±0.01).
It is a **finding** if any of f1–f6 succeeds, fails without naming the argument, or fails
as a traceback. Also if `ok` is refused as past the end.
cleanup: `delete_output(job_id=…)` for every job that ran.
metrics: none.

### C-F167 — `bleed_join` gives unchanged readings after the harmonicity refactor
source: tester, spec for #544 from #218's plan v1 (claude-opus-5-5 via anthropic)
Stage A moves `_harmonicity` onto an FFT path shared with `find_loop_bed`, and promises
`bleed_join`'s outputs are unchanged. C-F037 is the case that pinned them.

**Run:** C-F037's arms (a) and (b), exactly as that case writes them.
expected:
- Arm (a) still carries no `bleed_join` tonal warning.
- Arm (b) still warns, quoting flatness 0.22 and harmonicity 0.33 (±0.01 each), the values
  recorded before the refactor.
- Everything else C-F037 expects still holds.
It is a **finding** if either arm changes verdict, or (b)'s readings move by more than
0.01. Quote the new numbers.
cleanup: as in C-F037.
metrics: none.

### C-F168 — `find_loop_bed` keeps candidates inside one shot, resolving shots from an argument, a carried AudioVideo or the run manifest
source: tester, spec for #545 from #218's plan v1 (claude-opus-5-5 via anthropic)
Stage B adds a `shots` argument (`[{name, start_frame, num_frames}]` plus `fps`). Shots
resolve in this order: the argument, then a carried `AudioVideo.shots`, then the run
manifest's `recorded_shots`, then none. No candidate may straddle a shot boundary, and each
names its `shot`. `source.shots_source` reports where the shots came from.

**Setup:**
1. Quiet score: `gain_audio(audio="asset:qa-cast/ep51-bed.wav", gain_db=-30)`, saved as
   `audio/wav`. Keep the `output:` reference.
2. Film: run `templates/assemble-and-score` with:
   - shots `[asset:qa-cast/ep3-shot1-incident.mp4, asset:qa-cast/ep3-shot2-reply.mp4]`;
   - score = step 1's `output:`;
   - `sample_rate` 32000, `fps` 24, `total_frames` 248;
   - `world_gain` 0.0 and `score_gain` 1.0, so the film's audio is only the quiet bed.
   Record `get_job`'s `media.shots`. The boundary is at 124 f, 5.1667 s.

**Arms:** each has `max_candidates: 20` and is saved as `application/json`:
1. **Manifest:** `find_loop_bed(audio="output:<film mp4>", max_bin_dbfs=0, max_mean_dbfs=0,
   max_spike_db=60)`, with no `shots`.
2. **Argument:** the same (with the same three gate overrides), plus `shots: [{"name": "a", "start_frame": 0, "num_frames":
   100}, {"name": "b", "start_frame": 100, "num_frames": 148}]` and `fps: 24`. The
   boundary is at 4.1667 s.
3. **None:** `find_loop_bed(audio=<step 1's output: wav>)`.
4. **Carried:** one workflow with three steps:
   - `concat_videos` of the two ep3 shots;
   - `pair_audio` of that with step 1's quiet bed;
   - `find_loop_bed(audio="previous_result:<pair step>")`.

Arms 1 and 2 open the level gates because assemble-and-score's `balanced` step normalizes
the film to a −3 dBFS peak (#467), which leaves no quiet bed. These arms test shot
resolution, not the level gates.
expected:
- Every job succeeds, and each arm returns ≥ 1 candidate. Arm 3 matches C-F160's control
  arm, so the same fixture note applies.
- Arm 1: `source.shots_source` is `"manifest"`. Every candidate's `shot` is one of the
  names in `media.shots`, and no candidate spans 5.1667 s.
- Arm 2: `shots_source` is `"argument"`. Every candidate's `shot` is `"a"` or `"b"`, and
  no candidate spans 4.1667 s. The argument overrides the manifest, so a candidate may
  span 5.1667 s here.
- Arm 3: `shots_source` is null, and every candidate's `shot` is null.
- Arm 4: `shots_source` is non-null and is neither `"argument"` nor `"manifest"`. The plan
  doesn't fix the exact string, so record it. Each candidate names a carried shot, and no
  candidate spans the concat's 5.1667 s boundary.
It is a **finding** if:
- a candidate straddles the boundary of the shots in force;
- `shot` is missing or wrong;
- `shots_source` misreports the source;
- or the argument fails to take precedence over the manifest.
cleanup: `delete_output(job_id=…)` for every job, including the setup runs.
metrics: none.

### C-F169 — the dialogue-cut skills, the tasks guide and `shot_dead_air` point callers at `find_loop_bed`
source: tester, spec for #545 from #218's plan v1 (claude-opus-5-5 via anthropic)
Stage B teaches the task where a caller meets the problem:
- the `dw:minimax-h3` skill (dialogue cuts need a room-tone bed);
- the `dw:series-episodes` skill (the bed beat);
- the tasks guide's `shots` argument;
- #465's `shot_dead_air` message.

**Read:**
- Load the `dw:minimax-h3` and `dw:series-episodes` skills. There is no MCP call for skill
  text, so the skill loader is the read.
- `get_task(name="find_loop_bed")`, and the tasks guide section from C-F159.
- `assess_output(name="asset:qa-cast/ep62-episode.mp4")`. Its `shot_dead_air` finding is
  at shot `deflect`, 8.62 s.
expected:
- `dw:minimax-h3` says a dialogue cut needs a bed under it and names `find_loop_bed` as how
  to find one. It includes the `slice_audio` → `loop_audio` → `mix_audio` hand-off, using
  the candidate's `start_seconds`/`duration_seconds` and `gain`.
- `dw:series-episodes`'s bed beat names `find_loop_bed`.
- Any threshold or default either skill states matches `get_task`'s defaults.
- The tasks guide documents `shots` (`name`, `start_frame`, `num_frames`, `fps`), the
  resolution order, and `source.shots_source`.
- The `shot_dead_air` finding's text names `find_loop_bed`. Before this stage it read "cut
  a room-tone bed from the take with slice_audio, loop it to the gap's length with
  loop_audio, and mix it under the line with mix_audio …".
It is a **finding** if:
- either skill omits the task;
- a skill states a default that disagrees with `get_task`;
- the guide omits `shots`;
- or `shot_dead_air` still omits `find_loop_bed`.
cleanup: none (read-only).
metrics: none.

### C-F170 — `wait_for_job` advertises lem's 1800 s cap, and the clamp holds at the boundary
source: tester, spec for #546 from #377's plan v1 (claude-opus-5-5 via anthropic)
lem's deploy sets `DW_MCP_MAX_WAIT_SECONDS=1800`. The code default stays 55 and
`timeout_seconds` still defaults to 20, so a caller only gets a long call by asking for one.
S-F073 checks that the description and the clamp agree on whatever the cap is. This case
pins lem's value and the edges around it. No model, and nothing queued: every call runs
against an already-finished job, which returns at once but still fills the timeout fields.

**Setup:** `list_jobs(status="succeeded", limit=1)` gives `<finished>`.

**Calls:**
- the `wait_for_job` and `run_workflow` tool descriptions, as the MCP client loads them;
- `wait_for_job(job_id=<finished>, timeout_seconds=5000)`;
- `wait_for_job(job_id=<finished>, timeout_seconds=1800)`;
- `wait_for_job(job_id=<finished>, timeout_seconds=1801)`;
- `wait_for_job(job_id=<finished>)`, with no `timeout_seconds`.

expected:
- The `wait_for_job` description says one call blocks for at most 1800 seconds (`1800` or
  `1800.0`). `run_workflow`'s description names the same cap for its folded `wait_seconds`
  wait. Neither says 55 anywhere.
- `5000` → `timeout_requested_seconds: 5000`, `timeout_applied_seconds: 1800`,
  `timeout_capped: true`, `still_running: false`, and a terminal `status`.
- `1800` → `timeout_applied_seconds: 1800`, `timeout_capped: false`. The cap itself is
  honoured, not clamped.
- `1801` → `timeout_applied_seconds: 1800`, `timeout_capped: true`.
- No `timeout_seconds` → `timeout_applied_seconds: 20`, `timeout_capped: false`. The
  default did not move with the cap.
- Every reply returns at once (a finished job), with `waited_seconds` under 2.

It is a **finding** if:
- either description states a cap other than 1800, or the two disagree;
- any arm's `timeout_applied_seconds` or `timeout_capped` differs from the above;
- or the default is no longer 20.

cleanup: none (read-only).
metrics: none.

### C-F171 — a long `wait_for_job` on a job id that does not exist fails at once
source: tester, spec for #546 from #377's plan v1 (claude-opus-5-5 via anthropic)
The #300 edge. A server restart drops a queued or running job, and its id then answers
"Unknown job". With an 1800 s cap, a wait that blocked on a vanished id would hang the
caller for half an hour. Nothing is queued.

**Calls:** time each call from your side.
- `wait_for_job(job_id="000000000000", timeout_seconds=1800)` (well-formed, never issued);
- `wait_for_job(job_id="qa-no-such-job-377", timeout_seconds=1800)`;
- `wait_for_job(job_id="", timeout_seconds=1800)`.

expected:
- The first two fail with an error whose text says "Unknown job". Each returns in under
  5 seconds.
- The empty id is refused, as an unknown job or as an invalid argument, also in under 5
  seconds.
- None of the three comes back as `still_running: true`, and none reports a
  `waited_seconds` near the budget.

It is a **finding** if any call blocks for more than 5 seconds, returns `still_running`,
or answers with anything that reads like a live job.
cleanup: none (read-only).
metrics: none.

### C-F172 — one `wait_for_job` call covers a job longer than ten minutes, and the default wait still returns at about 20 s
source: tester, spec for #546 from #377's plan v1 (claude-opus-5-5 via anthropic)
The field report behind #377: a 41-minute render needed about 45 polls at a 55 s cap. With
the cap at 1800, one call should cover the whole job. The HTTP mount answers a call with no
bytes until it returns. So this case is also the measurement of whether an intermediary or
the client cuts a silent 10-plus-minute request. **This spends GPU time: about 12 minutes of
H3 on lem.**

**Setup:** `validate_workflow(name="templates/minimax/shots-batch", arguments={"seed": 377,
"shots": <the template's own first three shots, unchanged: shot_1 and shot_2 at 124 frames,
shot_3 at 158>})`. Read `plan.estimate.minutes` as `<est>`. Expect roughly 12 (the curated
figure is 3.49 per entry, plus load). If `<est>` is under 10, add the template's `shot_4` to
reach 10 or more. Queue it with `run_workflow(..., acknowledged_cost=<bound from the plan>)`,
with no `wait_seconds`, giving `<job>`.

**Calls:**
1. `wait_for_job(job_id=<job>)` with no `timeout_seconds`. Time it from your side.
2. `get_job(job_id=<job>)` to confirm the job is running or queued.
3. One call, `wait_for_job(job_id=<job>, timeout_seconds=T)`, where
   `T = min(1800, ceil(<est> × 60 × 1.5))`. That is the documented rule: the plan estimate,
   plus margin. Note the wall-clock second you sent it and the second it came back.

expected:
- Call 1 returns within about 20 s: `still_running: true`, `timeout_applied_seconds: 20`,
  `timeout_capped: false`, and `waited_seconds` between 18 and 25.
- Call 3 returns with:
  - `still_running: false` and a terminal `status` (`succeeded` expected);
  - `timeout_requested_seconds: T`, `timeout_applied_seconds: T`, `timeout_capped: false`;
  - `waited_seconds` above 55, and above 600 when the job ran ten minutes or more.

  One call covered the whole job.
- A slim job, and the manifest once finished.

**The transport cut is recorded, not failed.** Call 3 may instead end in a transport or
client error (a timeout, a closed connection, an HTTP error) before the job finishes. Record
the exact error text and the second it came, counted from sending the call. Then confirm with
`get_job` that the job itself was unaffected, and let it finish with 55 s waits.
- While #547 (stage 2, the heartbeat) is open, that cut is the stage-2 trigger: comment it
  on #547, and file nothing.
- Once #547 is verified or closed `not planned`, a cut is a **finding**. Reference #377 and
  C-F174.

It is a **finding** if:
- call 1 blocks well past 20 s or reports a different applied timeout;
- call 3 returns `still_running: true` before `T` elapsed;
- call 3 reports `timeout_capped: true` for a `T` at or under 1800;
- or `waited_seconds` disagrees with your own wall-clock by more than 10 s.

metrics: `long_wait_seconds`, call 3's `waited_seconds`, recorded on success;
`cut_after_seconds`, the second a cut came, recorded only when there was one.
cleanup: `delete_output(job_id=<job>)`.

### C-F173 — the skills and the guide teach "ask for the estimate", not `wait_seconds=55`
source: tester, spec for #546 from #377's plan v1 (claude-opus-5-5 via anthropic)
Design item 4 of the plan. Every place that told an agent to wait 55 s per call now states
one rule, with no deployment number in it:
- ask for the job's `plan.estimate` (plus margin) as `timeout_seconds`;
- the reply's `timeout_applied_seconds`/`timeout_capped` say what you got;
- call again if `still_running`.

Read-only.

**Calls:**
- `get_guide("workflows", section=<"The loop">)`, then read step 5;
- load each skill with `Skill`: `dw:ltx-2-5`, `dw:minimax-h3`, `dw:minimax-music3`,
  `dw:series-episodes`, `dw:script-to-video`.

expected:
- None of the six texts says `wait_seconds=55` or tells the caller to wait 55 s per call.
  None states 1800 as a limit either. A number there would be wrong on another deployment.
- The guide's step 5, and each skill that tells the caller how to wait on a run, gives the
  rule above in substance:
  - the estimate (plus margin) as the timeout;
  - the reply's `timeout_applied_seconds`/`timeout_capped` as what was granted;
  - call again on `still_running`.
- No skill teaches a background-shell or `curl` wait instead (the plan's Q3 default is no).

It is a **finding** if any of the six still carries `55` as the per-call wait, if one states
a different rule from the guide, or if a skill that told the caller how to wait before now
says nothing on it.

Not covered here: `docs/MCP.md` and `dw_mcp/CLAUDE.md` change in the same stage, but
neither the server nor the plugin serves them. Their check is `docs-review`'s.
cleanup: none (read-only).
metrics: none.

### C-F174 — with the heartbeat, a ten-minute-plus wait survives the transport, both standalone and folded into `run_workflow`
pending: #547
source: tester, spec for #547 from #377's plan v1 (claude-opus-5-5 via anthropic)
Stage 2 is built only if C-F172 recorded a cut. It sends a progress notification about every
20 s while a `wait_for_job` or `run_workflow(wait_seconds=)` wait is blocked. The HTTP mount
answers such a call as an SSE stream, so the connection never goes idle. No new parameter,
and no description text. **This spends GPU time: about 12 minutes of H3 on lem.**

**Setup:** C-F172's workflow, arguments and `<est>` (`seed` 377, three shots, or four if
`<est>` is under 10). Validate as there.

**Calls:**
1. `run_workflow(..., acknowledged_cost=<bound>, wait_seconds=600)`. This is the folded
   wait, blocked for 10 minutes. Note when it returns.
2. On `still_running: true`, one
   `wait_for_job(job_id=<job>, timeout_seconds=min(1800, ceil(<est> × 60 × 1.5)))`.

expected:
- Call 1 comes back normally after about 600 s with `still_running: true`, `waited_seconds`
  between 595 and 610, `timeout_applied_seconds: 600` and `timeout_capped: false`. It also
  carries the job id and the slim `job` with its `progress`. If the job finished first, it
  comes back earlier with a terminal status, and call 2 is skipped.
- Call 2 comes back with `still_running: false`, a terminal `status` and
  `timeout_capped: false`. Its `waited_seconds` agrees with the wall clock.
- Neither call ends in a transport or client error. In particular, neither fails at the
  second C-F172 recorded as `cut_after_seconds` on #547.
- The final reply is an ordinary tool result, the same shape C-F172 asserts.
- If the client surfaces progress notifications, note what they carried (phase, denoise
  step). It is not asserted: the plan promises them to the transport, not to every client's
  UI.

It is a **finding** if either call is cut, if a reply arrives malformed or empty, or if the
waits return early with `still_running: true`.

metrics: `folded_wait_seconds` (call 1) and `long_wait_seconds` (call 2).
cleanup: `delete_output(job_id=<job>)`.

### C-F175 — every other tool still answers normally across the SSE framing change, errors included
pending: #547
source: tester, spec for #547 from #377's plan v1 (claude-opus-5-5 via anthropic)
Stage 2 switches the HTTP MCP mount to `json_response=False` for every tool, which is the
plan's one broad change. A non-waiting call, a refusal and a tool error must still
round-trip as ordinary tool results. A short wait that emits no heartbeat, or at most one,
must too. Cheap: one task-only job, about a second of work, and no model.

**Setup:** the inline `frame_grid` workflow from C-F083, as `<grid>`, over
`asset:qa-cast/ep6-cold-open.mp4` with its defaults.

**Calls:**
1. `list_workflows(shape="utility")` returns the usual compact catalog, with `workflows` and
   `details`.
2. `validate_workflow(workflow=<grid>)` returns `valid: true` and a `plan`.
3. `validate_workflow(workflow=<grid>, arguments={"count": 0})` returns `valid: false`, with
   the error at `steps[0].task.arguments.count`, as a normal reply and not a transport
   error.
4. `run_workflow(workflow=<grid>, acknowledged_cost=<bound or true, as the plan says>,
   wait_seconds=30)` comes back folded: `still_running: false`, `succeeded`, and a manifest
   with one `.png`.
5. `get_output_image(name=<that png>)` returns the image and its size part, with
   `original_size: [1280, 543]`.
6. `wait_for_job(job_id=<that job>, timeout_seconds=60)` on the finished job returns at
   once, terminal, with the timeout fields.
7. `wait_for_job(job_id="000000000000", timeout_seconds=60)` fails at once with
   "Unknown job" as a tool error, not a hung stream.
8. `get_job(job_id=<that job>)` returns the full job, arguments included.

expected: each call returns as stated, in one response, with nothing truncated, doubled or
wrapped in stream framing text.

It is a **finding** if any call:
- errors at the transport;
- returns an empty or malformed result;
- turns a refusal (3, 7) into a transport failure;
- or takes noticeably longer than before the change: more than 5 s for 1–3 and 5–8.

cleanup: `delete_output(job_id=<that job>)`.
metrics: none.

### C-F176 — an off-size shot is resized over `video_frames`, has its soundtrack put back with `pair_audio`, and then dissolves with 960×544 shots
source: tester, found while running TESTER_TASK.agent.md (claude-opus-5-5 via anthropic); #504, #551
Since #504, a join refuses shots of different sizes at validate. The route that reconciles them
chains image-processor tasks, so a dropped frame rate, size or soundtrack anywhere in it would
break a join silently. This case fixes that route. It runs on the CPU in about 10 s.
1. `validate_workflow(workspace=<suite workspace>, workflow=W)`, then `run_workflow` with the same
   `inline_workflow`, `acknowledged_cost=<bound from the plan>` and `wait_seconds=55`. W:
   `{"id": "c-f176-resize-dissolve", "seed": 1, "steps": [`
   `{"name": "hal_frames", "task": {"command": "video_frames", "arguments": {"video": "asset:qa-cast/ep75-shot-ltx2stage-hal.mp4"}}, "result": {"content_type": "video/mp4", "fps": 24, "save": false}},`
   `{"name": "hal_fit", "task": {"command": "resize_rescale", "arguments": {"image": "previous_result:hal_frames", "width": 960, "height": 544}}, "result": {"content_type": "video/mp4", "fps": 24, "save": false}},`
   `{"name": "hal_shot", "task": {"command": "pair_audio", "arguments": {"video": "previous_result:hal_fit", "audio": "asset:qa-cast/ep75-shot-ltx2stage-hal.mp4", "fps": 24, "fit": "video"}}, "result": {"content_type": "video/mp4", "fps": 24, "subfolder": "intermediate"}},`
   `{"name": "film", "task": {"command": "dissolve_videos", "arguments": {"videos": ["asset:qa-cast/ep62-shot1-accuse.mp4", "previous_result:hal_shot", "asset:qa-cast/ep62-shot2-deflect.mp4"], "dissolve_frames": 12, "fps": 24, "match_levels": "rms", "match_levels_dbfs": -24}}, "result": {"content_type": "video/mp4", "fps": 24, "subfolder": "final"}}]}`
2. `get_gallery_metadata` on the `film` file, and `assess_output` on it.
expected:
- Validation is clean and plans 4 steps. The run `succeeds`, and its only warning is `dissolve_videos`' sample-rate
  resample to 48000 Hz (32000/48000/32000 in).
- The film is **960×544**, 345 frames, 24 fps, 14.375 s, 48000 Hz stereo, and `audio_stream_seconds`
  equals the duration. Its `media.shots` read start_frame 0/112/221 and num_frames 112/109/124, with the last two
  at `overlap_frames: 12`.
- `assess_output` raises no `seam_*`, `sync_drift` or `sync_length` finding.
It is a **finding** if the film isn't 960×544, if `hal_shot` is silent or missing from the shot map
(the soundtrack was lost in the round trip), or if the frame count isn't 345.
Not asserted here: `shot_dead_air` warnings in `hal_shot` and `ep62-shot2-deflect` (those takes' own gaps).
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F177 — `concat_videos` fills a silent input with silence of its own length, so later shots stay in sync; all-silent stays audio-less
source: tester, verified in #553 (claude-opus-5-5 via anthropic)
Every multi-shot template joins through `concat_videos`. A silent input used to be skipped in
the audio, which pulled every later shot's sound early by the silent shot's length. Nothing
fails when that happens, so the drift is easy to miss. This case runs on the CPU in about 6 s.
1. `validate_workflow(workspace=<suite workspace>, workflow=W)`, then `run_workflow` with the same
   `inline_workflow`, `acknowledged_cost=<bound from the plan>` and `wait_seconds=55`. W:
   `{"id": "c-f177-silent-fill", "steps": [`
   `{"name": "silent", "task": {"command": "video_frames", "arguments": {"video": "asset:qa-cast/ep4-shot1-amnesty.mp4"}}},`
   `{"name": "mid", "task": {"command": "concat_videos", "arguments": {"videos": ["asset:qa-cast/ep4-shot1-amnesty.mp4", "previous_result:silent", "asset:qa-cast/ep4-shot2-desk.mp4"], "fps": 24}}, "result": {"content_type": "video/mp4", "subfolder": "final", "file_base_name": "mid"}},`
   `{"name": "first", "task": {"command": "concat_videos", "arguments": {"videos": ["previous_result:silent", "asset:qa-cast/ep4-shot2-desk.mp4"], "fps": 24}}, "result": {"content_type": "video/mp4", "subfolder": "final", "file_base_name": "first"}},`
   `{"name": "allsilent", "task": {"command": "concat_videos", "arguments": {"videos": ["previous_result:silent", "previous_result:silent"], "fps": 24}}, "result": {"content_type": "video/mp4", "subfolder": "final", "file_base_name": "allsilent"}}]}`
   (Both ep4 shots are 124 frames at 24 fps with 32 kHz stereo audio.)
2. `get_gallery_metadata(<mid file>, envelope=true)`.
expected:
- The run `succeeds`.
- `mid`'s shots start at samples 0 / 165333 / 330666, so shot 3 starts at 248/24×32000. The
  shots are contiguous, and the file's audio is 15.5 s, the same as its 372 frames.
- `mid`'s envelope reads −120 dBFS in bins 6–9 and has sound again by bin 10.
- `first`'s second shot starts at sample 165333.
- `allsilent`'s shots carry `start_sample: null`, so the output has no audio.
It is a **finding** if shot 3's `start_sample` is 165333 or less (the silent shot was
skipped), if `mid`'s audio runs shorter than its picture, or if `allsilent` gains a
soundtrack.
cleanup: `delete_output(job_id=…)`.
metrics: none.

### C-F178 — a `for_each` over a composed template tags each child manifest entry with its own member
source: tester, verified in #560 (claude-opus-5-5 via anthropic)
The members of a `for_each` that composes a catalog template all produce a child step with the same
name. With no `result` on the composing step, `parent_step` is the only thing in the manifest that
says which member wrote which file. A consumer that keys by `step` gets a collision without it.
This case runs on the GPU in about 10 s.
1. `validate_workflow(workspace=<suite workspace>, workflow=W)`, then `run_workflow` with the same
   `inline_workflow`, `acknowledged_cost=<bound from the plan>` and `wait_seconds=55`. W:
   `{"id": "c-f178-foreach-compose", "variables": {"shots": [{"name": "answer"}, {"name": "insist"}]}, "steps": [`
   `{"name": "shot", "for_each": "variable:shots", "workflow": {"path": "templates/upscale-spandrel", "arguments": {"input_image": "asset:qa-cast/priya-portrait.jpg"}}}]}`
2. `get_job` on the job.
expected:
- Validation is clean, apart from the no-`seed` step-cache warning, and plans 2 steps. The run `succeeds`.
- The manifest has 4 entries, the same in the `run_workflow` reply and in `get_job`: `shot@answer` and
  `shot@insist` with `files: []`, and two `upscale` entries. Each `upscale` entry lists one file. Its
  `parent_step` is `shot@answer` or `shot@insist`, and the file name starts with that same member name.
It is a **finding** if an `upscale` entry has no `parent_step`, if both carry the same value, or if an entry's
`parent_step` doesn't match the member its file is named after.
Not asserted here: the child's `final` subfolder showing up on member files (#560 left that as a separate design question).
cleanup: `delete_output(job_id=…)`.
metrics: none.

## Performance
