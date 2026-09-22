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
sweep) live in `agents/REGRESSION.agent.md`, not here.

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

Durable contents of `regression-complete` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- `asset:qa-cast/ep3-shot1-incident.mp4` and `asset:qa-cast/ep3-shot2-reply.mp4`
  — two independently generated 24 fps shots (124 frames / 5.175 s / 960x544,
  32 kHz stereo) whose soundtracks sit ~11 dB apart (`mean_dbfs` -20.0 and
  -31.1). Used by C-F001, C-F002, C-F009, C-F011, C-F012 and C-F013's stereo
  control. They live in the **shared**
  `common/assets`, not in `regression-complete`, so every workspace can
  reach them by that same `asset:` reference — do not delete them in a
  cleanup sweep, and do not expect them under `regression-complete`'s own
  asset dir. The level spread is the point: regenerating them would not
  reproduce it on purpose.

- `asset:qa-cast/priya-voice.wav` — a **mono** (1-channel) voice track. Used by
  C-F013, where the channel count is the entire subject: it is what makes the
  `video/mp4` encode fail, and a stereo file will not reproduce the case. Also in
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
  rms). Used by C-F044, where the integer duration is the point: a lossy
  decode runs a few samples past 15.0 s and the envelope must not report
  those as a 16th bin. Also in the shared `common/assets`: do not sweep it,
  do not expect it under `regression-complete`. A replacement needs
  `duration_seconds` to be a whole number and audible audio in its last
  second — confirm both with `get_gallery_metadata` and
  `get_output_frames(at=[<duration - 0.1>], hear=1)` before swapping it in.

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
asset and `audio` = a **stereo** track (the other C-F001 fixture serves — see
C-F013 for why the channel count is not incidental), `result` =
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
and `get_job(...)["warnings"]` holds **exactly one** entry, prefixed with the
step's name, containing `past the end of` and naming `loop_audio` with its
`target_frames`+`fps` pair as the remedy. The numbers in it must be the real
ones: source ≈ 4.96 s, ≈ 10.5 s padded, 15.50 s returned. (b) Counter-case, a
slice **inside** the source (`num_frames: 48`, `fps: 24`) → `warnings: []`.
(c) Counter-case, a slice a few ms past the end (`start_seconds: 0`,
`duration_seconds: 4.965`) → `warnings: []`: frame-aligned slicing lands a
sample or two past the end routinely and a warning fired on that is noise
nobody can act on. (d) The end-to-end path, which is where it bit:
`run_workflow("templates/assemble-and-score", arguments={shots: three
`common/assets` shots, score: the room-bed asset, sample_rate: 32000, fps: 24,
total_frames: 372})` → succeeds, and its `warnings` carries the same entry
attributed to the `soundtrack` step. The source reads at its real ~4.96 s here,
not a reinterpreted length: since #180 (see C-F031(b)/(c)) the `soundtrack`
step calls `slice_audio` with no `sample_rate` and a separate `resample_audio`
step follows it, so nothing in this template reinterprets a file's rate
anymore. The warning's arithmetic must be self-consistent with whatever length
the task actually saw.
It is a **finding** if (a) or (d) comes back `warnings: []` (the original bug —
79% of a track padded in silence), if the padding turns into an error or a
short track (that breaks the legitimate tail pad), or if (b) or (c) starts
warning. Also a finding if the warning is only a server-side log line: score
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
0.4.0-beta.4+, where the template resamples instead.

### C-F020 — `templates/dissolve-between-shots` passes `match_levels` through, so its own warning is followable
C-F018 and C-F019 exercise the `dissolve_videos` **task**. This case is about the
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

### C-F021 — casting an H3 short from files actually skips the portrait steps
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
- **Every `list_assets` entry carries an `origin`**, and the response carries `asset_dir`,
  `asset_dirs` (nearest library first) and a precomputed `folders` list. An entry missing
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
observable on this server (`/home/don/diffusers-workflow/assets` is on `asset_dirs` but
contributed no entries), so the read-only-refusal branch of `delete_asset` is deliberately
not asserted here; it belongs in the dw repo's pytest suite, where a fixture can exist.

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
`seam_fade_ms: 80`, `match_levels: "rms"` succeeds with `warnings: []` — in
particular **no `slice_past_end`**, the score being 10.83 s against a 10.33 s
cut — and the film reports 248 frames / `duration_seconds` ≈ 10.334 / `fps: 24.0`
/ `sample_rate: 32000` / `channels: 2` and `peak_dbfs` **below 0** (the template
normalizes to -3 before the mux; the AAC overshoot on this material is a few
hundredths of a dB, so -3 has ample headroom — cf. C-F024, where a lossy source
overshoots by ~0.44 dB).
It is a **finding** if either job warns, if the bed's duration is not exactly
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
(a) `ctrl` produces **exactly one** warning, prefixed with its step name and
containing `past the end of`, with the real numbers (≈2.98 s padded onto a
30.02 s source, 33.00 s returned) — this is C-F016's contract, re-asserted on a
second source. (b) `test` produces **no** `slice_past_end` warning at all:
33.00 s × 32000 = 1,056,000 samples is only 23.95 s of a 44100 Hz source, so
nothing runs past the end. (c) Both files decode at `duration_seconds: 33.0`,
`ctrl` at 44100 Hz and `test` at 32000 Hz. (d) The dilation is exactly the rate
ratio, 44100/32000 = 1.378: landmark `peak_dbfs` values in the source's own
envelope recur in `test`'s envelope at 1.378× their source timestamp, matching
to ~4 decimal places — e.g. source t=16 s `-8.9205` → test t=22 s; source t=21 s
`-21.6359` → test t=29 s; source t=23 s `-7.0706` → test t=31 s. (Envelope
buckets are 1 s wide, so score the values' identity and the ~1.38 trend across
several landmarks, not a single bucket index.)
It is a **finding** if (a) stops warning (C-F016 regressed), if (b) starts
emitting a `slice_past_end` warning computed from the *file's* rate rather than
the rate the task was given (the warning's arithmetic must stay self-consistent
with the length the task actually saw — C-F016 says the same), if (d)'s ratio is
no longer the rate ratio (the override quietly became a resample, which is a
behaviour change callers relying on the documented semantics would not be told
about), or if either step errors. It is **not** a finding — it is the fix landing
— if `test` gains a *new, distinctly named* warning that the given `sample_rate`
differs from the rate the named file carries; that is proposal 2 on #180 and is
the outcome this case exists to make visible. Update the case then, via the
normal route, rather than reading it as a pass or a fail.
cleanup: delete the run's outputs. `asset:qa-cast/ep15-song.mp3` is a durable
fixture listed above — keep it.
source: tester, found while running TESTER_TASK.agent.md (episode 18) on
2026-09-16 over MCP as model `opus` via provider `anthropic`, workspace
`qa-ep18`, job `ce7a0a579ecb` (1.45 s; `ctrl` warned `slice_past_end`, `test`
`warnings: []`; both 33.0 s; landmarks matched at 1.378×). Filed as #180 against
`templates/assemble-and-score`, which wires its mix `sample_rate` into this
parameter and so reaches the dilation from its own defaults.

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
expected: three parts.
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
`checked_arguments` naming exactly those six and `plan.steps: 7`; run it with
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
C-F033 pins the `bleed_join` detector at the `concat_videos` task level with
synthetic shots. This is the template-level pair on real dialogue: the same
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
is valid with `plan.steps: 7`; the run succeeds with **no `bleed_join:`
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
the seam still carries a ~2.6 dB step — #214 asks for that to be reported and
#215 for the template to expose `match_levels_dbfs`; when either lands,
extend this case rather than reading the silence as a pass.
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

### C-F040 — `validate_workflow` projects host memory for a resident `for_each` from observed history, warns, and never refuses
One cheap run plus four free validations; no model, no GPU. Save a
workspace workflow `c-f040-qr-list`: `variables: {codes: [{name: "a", text:
"alpha"}]}` and one step `{name: "qr", for_each: "variable:codes", task:
{command: "qr_code", arguments: {qr_code_contents: "item:text", height: 256,
width: 256}}, result: {content_type: "image/png", subfolder: "final"}}` — no
`release_pipeline`/`release_models`, so it is the resident shape. Then:
1. `validate_workflow(name="c-f040-qr-list", arguments={codes: [32 entries]})`
   **before any run** (32 is the `for_each` cap; 33 is a schema error);
2. `run_workflow` it once with the 1-entry default, `wait_for_job`;
3. the same 32-entry validation again;
4. the same validation with 16 entries;
5. `save_workflow(patch=...)` adding `release_pipeline: true` to the `qr`
   step, then the 32-entry validation once more.
expected: (1) `valid: true`, `warnings: []` — cold start, no history, no
projection; (3) `valid: true` **and** one warning beginning `Projected host
memory for this run (~N MB, 32 entries held resident together) exceeds this
machine's usable RAM (~M MB)` — N is the run's observed peak × 32 (a bare
worker peaks ~1.9 GB, so N ≈ 60 GB), M ≈ 90% of host RAM, and the run is
*not* blocked; (4) `warnings: []` — 16 × ~1.9 GB is under the ceiling; (5)
`warnings: []` — the released shape projects the largest single peak, not
per-entry × N. The regressions: (3) coming back with no warning (history not
persisted or not read), `valid: false` on (3) (warn became refuse, which the
approved scope rejects), a warning on (1) (a projection from nothing), or a
warning on (5) (the shape distinction lost). If (3) is silent on a box with
much more than 64 GB RAM, that's the ceiling, not a regression — say so.
cleanup: `delete_workflow("c-f040-qr-list")`; delete the run's output.
source: tester, verified in #243 (run over MCP 2026-09-19 as the calls above,
model `opus` via provider `anthropic`, against `dw` 0.4.0-beta.6).

### C-F041 — a resident `for_each`'s host-memory projection counts history rows from default-argument runs
Companion to C-F040, narrowed to the one thing #264 broke: a history row
whose stored `arguments` is empty (the run used the workflow's declared
default for the list variable) must still resolve to an entry count and feed
the resident-shape per-entry figure. Free apart from one ~6 s run; no model,
no GPU. Because the projection's history lookup is keyed on workflow name
across workspaces (#274), use a name never run on this box — `c-f041-qr-<run
date as YYYYMMDD>` — not C-F040's. Save it with `id` equal to that name,
`variables: {codes: [{name: "a", text: "alpha"}]}` and one step `{name: "qr",
for_each: "variable:codes", task: {command: "qr_code", arguments:
{qr_code_contents: "item:text", height: 256, width: 256}}, result:
{content_type: "image/png", subfolder: "final"}}` — no
`release_pipeline`/`release_models`. Then:
1. `validate_workflow(name=<it>, arguments={codes: [32 entries]})` before any
   run;
2. `run_workflow(workflow_path=<it>, acknowledged_cost=true)` with **no
   `arguments`** — the 1-entry default, so the history row's own `arguments`
   is `{}`; `wait_for_job`;
3. the same 32-entry validation again.
expected: (1) `valid: true`, `warnings: []`; (3) `valid: true` and exactly one
warning beginning `Projected host memory for this run (~N MB, 32 entries held
resident together) exceeds this machine's usable RAM` and citing `based on 1
run(s) of this workflow's own history`. N is whatever the run's
`host_memory_peak_rss_mb` was × 32 — on a warm worker that peak is the
process's lifetime high-water mark (#272), so N can be absurd (~2 TB); the
case asserts only that the row was counted (the warning exists and says
"entries held resident together"), not N's size. The regression is (3)
coming back `warnings: []` — the default-arguments row dropped from the count
again — or `valid: false`. On a box with much more than 64 GB RAM (3) may be
silent because 32 × a bare ~1.9 GB peak fits under the ceiling; say so
rather than fail it. Do not extend this case to the 16-entry or
`release_pipeline` checks — those are C-F040's, and both are blocked on #272.
cleanup: `delete_workflow(<it>)`; delete the run's output.
source: tester, verified in #264 (run over MCP 2026-09-21 as the calls above,
model `opus` via provider `anthropic`; the implementer's proposed case from
its #264 hand-off).

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
   "frames", task: {command: "extract_frames", arguments: {video:
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
parent — the `extract_frames` step is real declared work nobody priced, and
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

### C-F044 — an envelope on a whole-second track has exactly one bin per second, and its last bin is the real last second
One `get_gallery_metadata` call, no run, no GPU:
`get_gallery_metadata(name: "asset:qa-cast/ep25-episode.mp4", envelope:
true)`. Note `media.duration_seconds` (15.0) and
`media.envelope.interval_seconds` (1.0).
expected: `media.envelope.rms_dbfs` and `media.envelope.peak_dbfs` each have
exactly `duration_seconds / interval_seconds` = **15** entries, and the last
entry is within a few dB of its neighbours (rms roughly -22 to -28 dBFS; peak
above -10 dBFS) — the level of the track's real 15th second. The regression
is a 16th entry: a lossy decoder's priming/padding runs a few samples past
the nominal 15.0 s, and before #277 that fragment was reported as its own
one-second bin at ~-56 dBFS rms, reading as a dead last second on a track
that is not. Any last entry more than ~15 dB below the one before it fails
the case, whatever the count. (The fold applies to any sub-second tail —
5.167 s gives 5 bins — so do not assert `ceil`; #278 is where the length of
that tail is being discussed.)
metrics: `envelope_bins` — `len(media.envelope.rms_dbfs)`, condition
`ep25-episode.mp4/interval-1.0`. Any reading other than 15 is a failure
regardless of trend.
cleanup: none — the call writes nothing.
source: tester, verified in #277 (run over MCP 2026-09-21 as the call above,
model `opus` via provider `anthropic`; 15 bins, last `-26.31 / -5.73`).

### C-F045 — `dissolve-between-shots` resamples a 44.1 kHz score onto 32 kHz shots when told the target rate
One template run, no GPU (~5 s). The two shots are shared assets at 32000 Hz
(`asset:qa-cast/ep28-shot1-wide.mp4`, `asset:qa-cast/ep28-shot2-close.mp4`,
248 f between them at 24 fps — read both with `get_gallery_metadata` first;
the case is void if either has been re-kept at another rate) and the score is
44100 Hz (`asset:qa-cast/ep15-song.mp3`). Validate, bind the cost, run:
`validate_workflow(name: "templates/dissolve-between-shots", workspace:
"regression-complete", arguments: {shots: [<shot1>, <shot2>],
dissolve_frames: 12, match_levels: "rms", match_levels_dbfs: -24, score:
<song>, sample_rate: 32000, fps: 24, score_start_frame: 0, total_frames:
236, score_gain: 1.0, world_gain: 1.8})` then `run_workflow` with the same
arguments and the bound `acknowledged_cost`; `wait_for_job`; then
`get_gallery_metadata(name: <final output>, envelope: true)` and
`get_job_events`.
expected: `validate_workflow` is `valid: true` with no warnings; the job
`succeeded`; a `soundtrack_resampled` step ran (present in the events /
`get_job` steps); the final video reports `media.sample_rate` **32000**,
`frame_count` 236 (248 − 12), `fps` 24, stereo; `job.warnings` is
empty — no `sample_rate_mismatch`, no `slice_past_end`. The template's
`sample_rate` variable is what resampled the score onto the shots' rate;
the regression is the job failing at step 0 with `dissolve_videos needs one
sample rate, got [...]` or the rate leaking through as 44100 on the output.
It is a **finding** if the run succeeds but the output rate is not the
`sample_rate` given, or if the run needs an extra `resample_audio` the
caller had to author. (The mirror case — shots at *different* rates from
each other — is #287, open; add its case there once verified, not here.)
cleanup: `delete_output` on the run's outputs (the shared assets stay).
source: tester, found while running TESTER_TASK.agent.md (episode 29; run
over MCP 2026-09-21 in `qa-ep29` as job `13a766bd6a77`, model `opus` via
provider `anthropic`; 236 f / 32000 Hz / peak −3.07, 10 envelope bins, no
warnings).

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
leak in; (4) one warning beginning `Projected host memory for this run (~N MB,
32 entries held resident together) exceeds this machine's usable RAM` citing
exactly `based on 1 run(s) of this workflow's own history` — this workspace's
run counted, nobody else's (on a box with much more than 64 GB RAM (4) may be
silent because 32 × a bare ~1.9 GB peak fits; say so rather than fail it, and
lean on (5)'s `basis`/`runs` instead); (5) back to `warnings: []`, `basis:
"unknown"` — the deleted copy's row is gone with it; (6) `observed` present
with `runs` ≥ 1 and no run of the template in this workspace — a shared
catalog source still pools across workspaces (#154). The regressions: a
warning or `runs` > 0 on (3) (history keyed on name alone again — #274),
`based on N run(s)` with N > 1 on (4), a warning on (5) (`delete_workflow`
stopped purging — C-F040 step 1 then fails on every second cycle), or (6)
losing `observed` (workspace scoping applied to a read-only source too).
cleanup: `delete_output(job_id=<the run>)`, then
`delete_workspace("regression-complete-c-f048", acknowledged_cost=true)`.
source: tester, verified in #274 (model `opus` via provider `anthropic`, run
over MCP 2026-09-21 in `qa-verify-274` against develop `d5e3725` +
`9bdfe6f`: (3) clean, (4) `~67354 MB … based on 1 run(s)`, (5) clean, (6)
`runs: 3`). Proposed by the implementer in its hand-off, scoped to what was run.

## Performance
