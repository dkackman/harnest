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

### C-F008 — `result.file_base_name` is the whole base name, and a collision is counted not overwritten
Run one inline workflow with **two** steps that both write into the same
`subfolder` and both set the **same** `result.file_base_name` (e.g.
`"episode"`). Any cheap task step will do — `concat_videos` over the two
C-F001 fixtures, in either order, loads no model and costs no GPU.
expected: the manifest names the two files `<subfolder>/episode-0.0.<ext>` and
`<subfolder>/episode-0.0-2.<ext>`. Two assertions, and both matter:
1. **`file_base_name` replaced the derived base**, it was not glued in front
   of it. Neither name contains a `<workflow id>-<step name>` fragment. The
   regression is a name like `episodeqa-suite-episode-episode.0-0.0.mp4` —
   the caller's string prepended to the default base with no separator, which
   is what #100 was.
2. **Nothing was overwritten.** Replacing the derived base gives up what used
   to keep two steps' files apart, so `output_file_path`'s `-2`/`-3` counter
   is now the only thing standing between them. Two manifest entries, two
   distinct files.
Also assert the guard, which is free: `validate_workflow` on the same
workflow with `file_base_name: "sub/episode"` comes back **invalid**, with the
error at path `steps[0].result.file_base_name` and a message saying a
`file_base_name` is a name and not a path. A separator that validates is a
regression even if the run then writes somewhere sane.
Do not predict a filename from `file_base_name` anywhere else in a run — read
it back out of the manifest. This case is the one place that assertion belongs.
cleanup: delete both generated files.
source: tester, verified in #100 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as job `883c2fc82f5e`, model `opus` via
provider `anthropic`).

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

### C-F010 — a cost estimate re-prices for the list it was actually given
A list-driven template's curated cost was measured on one list length. Validating
it with a *different* length must not quote the measured figure unchanged.
`validate_workflow(name="templates/minimax/dialogue-short", arguments={"shots":
[...]})` three times — a list shorter than the stored default, the stored default
(pass no `arguments` at all), and a list longer than it. Free: validation only,
nothing is queued.
expected: `plan.estimate.minutes` differs across all three, and `plan.steps` moves
with the list. `basis` is the assertion that matters, in this order of preference:
`observed` (this box's own finished runs *at that list length* — strictly the best
answer, and what a template with history will normally report), then `per_entry`,
then `derived`, then `catalog`. What must never happen is the #85 shape: the same
`minutes` under `basis: "catalog"` for two different `steps` counts — a stored
figure wearing a label claiming it was measured for the caller's run.
The regression is #85: the same `minutes` returned for every length under
`basis: "catalog"`, so the quote was the stored default's figure wearing a label
that claimed it was measured for the caller's run. **Never the same number twice
with a different `steps` count** is the one-line form of this case.
Also assert `plan.list_entries` echoes the length the server realized, so a
failure separates "priced wrong" from "parsed the list wrong".
For scale (RTX 3090 figure of 42.0 min when first measured): 2 shots → 5
steps / 16.8 min / `derived`; 5 shots (default) → 8 steps / 42.0 min /
`catalog`; 10 shots → 13 steps / 84.0 min / `derived`. Read the current
figure from the catalog rather than asserting these.
cleanup: none — validation is free and queues nothing.
source: tester, verified in #85 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13, model `opus` via provider `anthropic`).

### C-F011 — a job records which form of cost acknowledgement queued it
`get_job.acknowledged` is documented as one of `none`, `boolean`, `bound`, and it
is the only record that a run passed the cost gate at all. Queue any cheap
task-only inline workflow **twice**: once with `acknowledged_cost=true`, once with
the bound object `{fingerprint, minutes, downloads}` taken from
`validate_workflow`'s `plan`.
expected: the bare run records `acknowledged: "boolean"` with `acknowledged_cost:
null`; the bound run records `acknowledged: "bound"` with the whole object echoed
back. The regression is #85: a bare `true` recorded `"none"`, which made a job
that went through the gate indistinguishable from one that never did — defeating
the point of recording the form. Note `"none"` must still be reachable in
principle, so assert the two positive forms rather than asserting `"none"` never
appears.
Assert the refusal arm while the fixture is at hand, since it is free and it is
what proves the server saw the flag: the same workflow with
`acknowledged_cost=false` is refused outright.
cleanup: delete both generated outputs.
source: tester, verified in #85 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as job `d21be61989ab`, model `opus` via provider
`anthropic`).

### C-F012 — a `seed` is what turns the step cache on, and a cached step is marked `reused`
The step cache is disabled entirely for a workflow that declares no top-level
`seed` — `cached_steps` then reports `0` without probing, which from the consumer
side is indistinguishable from "checked, nothing hit". Pin both halves. Take any
cheap task-only inline workflow with a top-level `"seed": 1` and run it twice,
validating before each run.
expected:
1. First validate → `plan.cached_steps: 0`; the run executes and writes its file.
2. Second validate, byte-identical workflow → `plan.cached_steps: 1`.
3. Second run → the manifest entry carries **`reused: true`** and names the
   **first run's** file path, not a new one under its own `run_id`. The second job
   is materially faster (1.88 s → 0.84 s when first measured).
Then assert the negative, which is the half that misled a tester for two cycles:
the *same* workflow with the `seed` removed reports `cached_steps: 0` on every
validate and never marks a step `reused`, no matter how many times it runs.
Both arms are required. Asserting only the positive would let a change that
caches unseeded workflows pass, and asserting only `cached_steps` would miss a
plan that promises a hit the run does not take.
cleanup: delete the first run's output (the second run produces no new file).
source: tester, found while verifying #85 on 2026-09-13 — the first time
`cached_steps` had ever read non-zero in fourteen cycles, and the reason a wrong
conclusion ("task steps are not cacheable") reached #85 twice. Run over MCP as
jobs `6a9cb065c40e` and `e3c9b4f38d67`, model `opus` via provider `anthropic`.
Discoverability of the seed requirement is filed as #107; this case pins the
behavior regardless of how that is resolved.

### C-F013 — a mono audio track is upmixed at encode, with a warning
Pairing a **mono** track onto a video and writing `video/mp4` must succeed: an mp4
audio stream takes two channels and nothing else, so the server duplicates a
1-channel track into two and says so. Run a one-step inline `pair_audio` with
`audio` = a 1-channel asset and `video` = any video fixture,
`result.content_type` = `video/mp4`. Run the identical workflow with a **stereo**
source as the control.
expected: the mono job **succeeds**; its `warnings` carry a line naming "mono" and
"two channels"; `get_gallery_metadata` on the output reports `channels: 2` and the
source video's own `fps` (no `result.fps` anywhere — the #104 carry-through must
survive the upmix). The stereo control succeeds with **no** such warning: the
warning is specific to the mono path, not blanket.
It becomes a **finding** if the mono job fails again (the #106 regression: a raw
`Expected samples with 2 channels; got shape torch.Size([1, N])` out of
`result.save_audio_video`), if the warning disappears while the upmix stays (a
silent channel change), or if the stereo control starts warning or failing.
Worth extending, not required: a mono track that then feeds a downstream
`concat_videos` against a natively-stereo video joins with `channels: 2` and no
channel mismatch — the upmix must hold through a chain, not only a one-step
encode. Both videos must be at the same audio sample rate for that join (see #108),
so insert `resample_audio` if the fixtures differ.
cleanup: delete both runs' outputs.
source: tester, found while running TESTER_TASK.agent.md on 2026-09-13 (filed as #106),
rewritten from a documented-failure case to a happy-path case on 2026-09-13 after
verifying the fix over MCP — jobs `bb66467e03f5` (mono, succeeded, `channels: 2`,
`fps: 24.0`), `90dbe57f0bc5` (stereo control, `warnings: []`) and `e33eac7b6449`
(the chained extension). Model `opus` via provider `anthropic`.

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

### C-F015 — mismatched audio sample rates are converted, loudly, and can be pinned
Shots assembled from different sources routinely carry different sample rates — a
24 kHz voice clip paired onto a 32 kHz generation is the ordinary case, not an edge
one. Unlike a level jump, the difference has no editorial meaning, so `concat_videos`
must convert rather than refuse — **and must say that it did**, because resampling
every track is a real audio decision made on the caller's behalf. Two-step inline
workflow: `pair_audio` a 24 kHz audio asset onto a 32 kHz video asset
(`result.save: false`), then `concat_videos` that result with a second, natively
32 kHz video asset. Needs two real media fixtures at different rates, which is why
this is here and not in smoke.
expected: the job **succeeds** (before #108 it failed mid-run at the join).
`get_gallery_metadata` on the joined output reports `sample_rate: 32000` — the
**highest** among the inputs, not the first or the lowest — with channels, fps and
frame count as the inputs imply. The job's `warnings` list carries **two** entries,
and `get_job_events` carries the new one as a structured `warning` event with:

```
kind:         "sample_rate_mismatch"
command:      "concat_videos"
sample_rate:  32000
sample_rates: {"<name of each input>": <its rate>, ...}
```

naming both rates, identifying each input (by its resolved path when it was given
as one, by position otherwise), and pointing at both remedies — the `sample_rate`
argument and the `resample_audio` task.
Variant, and the half that is easy to get wrong: the same workflow with
`"sample_rate": 24000` on the concat step → succeeds, output at `sample_rate:
24000`, and the warning still fires **naming 24000 as the target**. The message must
report the decision actually taken, not the highest-rate default it would have taken.
It becomes a **finding** if the join fails again, if the chosen rate is not the
highest when unpinned or not the pinned value when pinned, or — the #108 bounce, and
the reason this case scores the event and not just the log — if the conversion
happens with **no `warning` event**, only a server-side log line. A `logger.warning`
is not a warning the caller can see; `emit_warning` is. Score a structured-field
check, not a substring match on the message.
cleanup: delete both runs' outputs; the fixtures are durable.
source: tester, verified in #108 on 2026-09-13 over MCP as model `opus` via provider
`anthropic`, workspace `qa-ep7`, dw 0.4.0-beta.3 — jobs `8d09acd951e2` (unpinned,
succeeded 2.6 s, `sample_rate: 32000`, warning at event seq 13) and `454d8eb9af05`
(pinned to 24000, succeeded, output at 24000, warning naming 24000).

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
attributed to the `soundtrack` step. Note the source reads as ~2.48 s there,
not 4.96 s: the template passes `sample_rate` down and `slice_audio`'s
`sample_rate` *reinterprets* a file's rate rather than resampling it. That is
documented, pre-existing behaviour — it is not a finding, but the warning's
arithmetic must be self-consistent with whatever length the task actually saw.
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
to `soundtrack`).

### C-F017 — `loop_audio` lands a bed exactly on the requested length
This is the remedy C-F016's warning names, so it has to actually work: a warning
pointing at a task that lands a few frames off is worse than no warning, because
the caller follows it and gets the same silent tail. `loop_audio` must build a
bed of exactly `target_frames`/`fps` out of a shorter recording, with no silence
anywhere in it — the laps are crossfaded, not butted, and only the last lap is
trimmed. Needs the `room-bed.wav` fixture; seconds to run, generates nothing.
expected: a two-step inline workflow — `resample_audio` the 16 kHz
`asset:uploads/qa-cast/room-bed.wav` to 32000, then `loop_audio` it with
`target_frames: 348`, `fps: 24`, `crossfade_ms: 250` — succeeds with
`warnings: []`, and `get_gallery_metadata(..., envelope=true)` on the saved bed
reports `duration_seconds: 14.5` (348/24, exactly) at `sample_rate: 32000`, with
**15 envelope entries none of which is `-120.0`** and an `rms_dbfs` spread of
about 3 dB across the whole track. That last part is the real check: a bed
assembled from ~3 laps of a 4.96 s source must read as continuous material, not
as material followed by silence, and not with a hole at each loop point.
It is a **finding** if the duration is not exactly the requested frame count over
fps (a bed one lap too long or short is how the remedy silently reintroduces the
bug), if any envelope entry is `-120.0`, if a loop point shows as an `rms_dbfs`
notch of more than a few dB, or if the job warns — nothing about this is
irregular and `loop_audio` should have nothing to say about it.
cleanup: delete the run's output; the fixture is durable.
source: tester, found while running TESTER_TASK.agent.md (episode 10) on 2026-09-13
over MCP as model `opus` via provider `anthropic`, workspace `qa-ep10`, dw
0.4.0-beta.3 — job `6f3ae9e60d4d`, 0.6 s, bed 14.5 s / 32 kHz / mono, envelope
−50.8 … −47.8 dBFS across all 15 entries.

### C-F018 — `match_levels` moves the shots to the level the caller asked for
C-F001 pins the `rms` default (-20 dBFS). The other two halves of the same control
are untested and are what a caller reaching for it actually sets: the `peak`
measure, and `match_levels_dbfs` overriding the target. A target that is accepted
and then ignored is silent — the join succeeds, the levels are merely even at the
wrong place, and only this metadata call shows it. Task-only, loads no model, uses
the C-F001 fixtures.
expected: one inline `concat_videos` step over the two C-F001 fixtures with
`match_levels: "peak"` and `match_levels_dbfs: -6` succeeds with `warnings: []`
(matching suppresses the `level_spread` warning, as in C-F001's matched step), and
`get_gallery_metadata` on the output reports `peak_dbfs` within ~0.1 dB of **-6.0**
— not the -1.0 `peak` default, and not the inputs' own -1.5. `fps: 24.0`, 248
frames and `duration_seconds` ≈ 10.33 are unchanged: a level pass must not touch
the picture.
It is a **finding** if `peak_dbfs` lands on -1.0 (the default won over the
explicit argument), on the inputs' own peak (the match did not run), if the
`level_spread` warning fires anyway, or if the frame count or rate moves.
cleanup: delete the joined output. Keep the two input assets (fixtures).
source: regression agent, found while running C-F001/C-F002 on 2026-09-13 — the
suite pinned only the `rms` default. Measured over MCP as job `b80244bd5b1a`,
model `opus` via provider `anthropic`, dw 0.4.0-beta.3: `peak_dbfs` -5.9987,
`mean_dbfs` -23.87, 24.0 fps / 248 frames / 10.334 s, `warnings: []`.

### C-F019 — `dissolve_videos` shortens the cut by one overlap per seam
Nothing in this suite exercises `dissolve_videos` at all, and it is the other join
task: `concat_videos` cuts, this melts. Its arithmetic is the part that breaks
quietly — every seam overlaps two shots, so the result is the summed frames *minus*
one `dissolve_frames` per seam, and the soundtrack has to be crossfaded over
exactly that span or it walks off the picture. A wrong frame count here is the
number a caller then sizes a score slice to (see C-F016), so the error propagates
into a silently mis-scored film rather than a failed job. Task-only, loads no
model, uses the C-F001 fixtures.
expected: one inline `dissolve_videos` step over the two 124-frame C-F001 fixtures
with `dissolve_frames: 12`, `fps: 24` and `match_levels: "rms"` succeeds, and
`get_gallery_metadata` on the output reports **236 frames** (248 − 12, *not* 248),
`fps: 24.0`, and `duration_seconds` ≈ **9.83** — 236/24, i.e. the audio is the same
length as the picture rather than the un-overlapped 10.33 s. `sample_rate: 32000`,
`channels: 2`, and `mean_dbfs` on the `rms` target (-20 dBFS) as C-F001's matched
step.
It is a **finding** if the frame count is 248 (the overlap was not removed from the
picture) or the duration is 10.33 s against 236 frames (removed from the picture but
not the sound, which is the drift the whole-cut version of this bug accumulates over
a dozen seams), if `dissolve_frames: 0` stops being a plain hard cut, or if the task
refuses the pair.
cleanup: delete the dissolved output. Keep the two input assets (fixtures).
source: regression agent, found while running C-F001/C-F002 on 2026-09-13 —
`dissolve_videos` had no coverage at any level. Measured over MCP as job
`b80244bd5b1a`, model `opus` via provider `anthropic`, dw 0.4.0-beta.3: 236 frames
/ 24.0 fps / 9.834 s / 32 kHz stereo, `mean_dbfs` -19.81, in 1.7 s.

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
- `validate_workflow(name="templates/dissolve-between-shots", arguments={"match_levels": "rms"})`
  → `valid: true`, `checked_arguments` includes `match_levels`. This alone is the
  literal #128 repro.
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

### C-F022 — a derived cost figure is qualified, bucketed, and knows its device
`observed` reports what a workflow has actually cost **on this box**, beside the
curated `cost` a maintainer measured elsewhere (#93). The value of the number is
entirely in its qualifications: a cold and a warm run differ by 4x or more, and a
figure measured at one set of driver values says nothing about another. Three ways
this degrades silently — it starts reporting one unqualified number, it starts mixing
configurations into one average, or its device lookup fails and reports null on a box
plainly running CUDA (which is what happened on the first deploy, an `ImportError`
swallowed into a null by an over-broad `try`).
expected:
- **Never an unqualified figure.** `get_workflow(name=<a template with history>,
  variables_only=true)` → `observed` carrying `cold_minutes`/`cold_runs` and/or
  `warm_minutes`/`warm_runs`, each side with **its own** run count and range, and a
  side with no runs **absent rather than null**. There must be no `minutes` or
  `median_minutes` key: a reader must not be able to quote a number without also
  picking cold or warm. `runs` equals the two sides plus `unclassified_runs` where
  present.
- **The device is known.** `observed.device` and `observed.name` are **non-null** on a
  box with an accelerator (`"cuda"` / the card's name). Null here reads as "the server
  does not know what it is running on" and is invisible from the numbers themselves —
  this is the defect that actually shipped once.
- **Bucketing — a run at different driver values does not join the bucket.** Note a
  list-driven template's `observed` (`runs`, `cold_minutes`, `cold_range_minutes`,
  `drivers`), then run it with a **different list length**. Afterwards the reported
  block is **unchanged**: same `runs`, same median, same range. The reported bucket is
  the one the *defaults* give, which is what keeps it comparable to the curated figure.
  A `runs` that incremented, or a range that stretched to include the new run's time,
  is the finding.
- **`comparable: "drivers"` with the `drivers` block spelled out**, so a reader can see
  which configuration the figure is for rather than trusting it. A list driver reports
  its **length** (`"shots": 4`), not its contents — bucketing on contents would give
  every run its own bucket and so a permanent `runs: 1`.
- **A template with no history abstains.** One with `cost: null` and no default-args
  runs → no `observed` key at all, and the listing still reports
  `cost_basis: "curated"`.
- **The compact listing stays compact.** `list_workflows` carries at most
  `observed_minutes` (cold) and `observed_runs` per entry — never the full block. An
  entry with `cost: null` but history present still carries the derived pair, which is
  the case that makes the feature worth its tokens.
cleanup: delete the outputs of whatever run was made for the bucketing bullet. The
figures themselves are job history and are not cleaned up.
source: tester, model `opus` via provider `anthropic`, verified in #93 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`. The bucketing bullet was confirmed twice
incidentally: `dialogue-short` read `runs: 5, cold_minutes: 38.57, cold_range
[32.12, 42.81], drivers.shots: 5` both before and after an 8.93-min one-shot run, and
`music-video` read `runs: 1, cold_minutes: 25.75, drivers.shots: 4` with an earlier
14.2-min two-shot run likewise absent. The implementer's proposed cases 1 and 3 (two
runs into the *same* bucket; a cached `rerun_job` not counting) are **not** in this
case — I did not spend the runs to confirm them, and they are worth adding when
someone does.

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

### C-F026 — `stabilize_video` steadies the picture and leaves everything else alone
`stabilize_video` is the one general-purpose video task with no coverage at any level, and
what it must *not* change is the whole risk: it shifts every frame back toward the first,
crops to the region all of them cover, and resizes to the original size, so a regression
shows up as a deliverable that is quietly a different size, a different length, or silent —
never as a failed job. The assembly templates once ran it on every shot before a cut and
their output came out visibly wider than the source; that is the shape of the failure.
Task-only, loads no model, ~4 s, uses a C-F001 fixture.
expected: one inline `stabilize_video` step with `clip: "asset:qa-cast/ep3-shot1-incident.mp4"`
and `smooth: 0`, saved as `video/mp4`, succeeds with `warnings: []`, and
`get_gallery_metadata` on the output reports the source's own numbers unchanged:
`width: 960`, `height: 544`, `frame_count: 124`, `fps: 24.0`, `duration_seconds` ≈ 5.167,
`sample_rate: 32000`, `channels: 2`, and a `peak_dbfs` equal to the source's (-2.5700) —
the soundtrack is carried through untouched, not re-levelled. `mean_dbfs` lands within
~0.05 dB of the source's -20.0; the re-encode moves it by rounding, not by processing.
Second arm, free and the reason the first is written the way it is:
`validate_workflow` on the same step with the argument named **`video`** instead of `clip`
comes back **invalid**, with two errors — `steps[0].task.arguments.clip` (required and not
supplied) and `steps[0].task.arguments.video` (the task does not accept it). The name is
deliberate: the engine loads an argument called `video` itself, as bare frames, which would
strip the soundtrack before the task ever saw it. A `video` that validates is a regression
even if the run then produces a picture, because the sound is what it silently costs.
It is a **finding** if the size, frame count or rate moves, if the output comes back silent
or at a different level, if the job warns, or if `video` is accepted.
cleanup: delete the stabilized output. Keep the input asset (fixture).
source: regression agent, model `opus` via provider `anthropic`, found while running the
`complete` level on 2026-09-16 against dw 0.4.0-beta.4 on `lem` — `stabilize_video` had no
coverage in any suite file. Measured as job `d1edbd4dbc68` (960x544 / 124 / 24.0 fps /
5.167 s / 32 kHz stereo, `peak_dbfs` -2.5700, `mean_dbfs` -19.968, `warnings: []`, 4.0 s);
the `video`-argument refusal is from `validate_workflow` the same minute.

### C-F027 — `pair_audio`'s `fit` cuts a long track in silence and pads a short one loudly
`fit: "video"` is the control that makes a soundtrack follow a cut whose length is an
argument (#142), and its two directions have opposite obligations: cutting a track that is
too long is exactly what was asked for and must be silent, while padding one that is too
short leaves the end of the deliverable with no sound and must say so. A `fit` that warns
on both is noise a caller learns to ignore; one that warns on neither is #142 back. C-F015
and C-F024 both *use* `fit`, neither asserts it. Task-only, loads no model, ~6 s.
expected: one inline workflow over `asset:qa-cast/ep6-cold-open.mp4` (124 frames / 24 fps /
5.167 s) with three `pair_audio` steps, each saved as `video/mp4` —
- **`fit: "video"`, track longer than the picture** (`asset:qa-cast/ep15-song.mp3`, 30.02 s)
  → output `duration_seconds` ≈ **5.167** at `frame_count: 124`, and **no `fit` warning at
  all**. The cut is the requested behaviour, so silence about it is the assertion.
- **`fit: "video"`, track shorter than the picture** (a 5.00 s `slice_audio` of the same
  song) → output `duration_seconds` ≈ **5.167**, and **exactly one** `fit` warning, prefixed
  with the step's name, naming all three real figures: the track's length, the silence added,
  and the video's (`padded the 5.00 s track with 0.17 s of silence to reach the 5.17 s of
  video it is laid over`), and pointing at a longer track or fewer frames as the remedy.
- **`fit` unset, same 30.02 s track** → the track is used as it is: output
  `duration_seconds` ≈ **30.02** against `frame_count: 124`, with a warning naming both
  lengths *and* the frame count and rate (`the track is 30.02 s and the video it is laid
  over is 5.17 s (124 frames at 24 fps)`) and naming `fit: "video"` as the remedy. This arm
  is what keeps the default honest: the disagreement is allowed, it is just never silent.
Ignore the `audio_no_headroom` warning this song draws on every arm — it is a property of the
material (M-F011's subject), not of `fit`, and it is why the assertion above is "no `fit`
warning" rather than `warnings: []`.
It is a **finding** if the cut arm warns, if the pad arm does not, if either `fit: "video"`
arm's duration is not the picture's, if the unset arm stops warning, or if any warning loses
the figures — a warning that says a length disagrees without saying by how much cannot be
acted on without re-deriving it.
cleanup: delete the run's outputs. Keep the input assets — both are shared `common/assets`
fixtures; do not sweep them.
source: regression agent, model `opus` via provider `anthropic`, found while running C-F024
on 2026-09-16 against dw 0.4.0-beta.4 on `lem`, where the pad warning fired incidentally and
nothing in the suite asserted it. Measured as job `44a8336fe388`: `fit_cut` 5.166667 s / 124
frames / no `fit` warning, `fit_pad` 5.166667 s / 124 frames / one pad warning, `fit_unset`
30.022993 s / 124 frames / one disagreement warning.

### C-F028 — a phase that goes silent past the threshold says so, in a typed event, and stops when it resumes
A job that is working but emitting nothing is indistinguishable from a hung one over MCP, and
the pre-denoise lead-in of an `ltx2` run is the natural instance: `generating` starts, then
~50 s pass with `denoise_step: null` before the first `pipeline_step`. #176 made that visible
with a generic watchdog. What is worth locking in is not the LTX number but the three
properties that make it usable: the warning is **typed** (`kind: "phase_stall"`, so a consumer
keys on a field instead of matching prose), it reaches **both** consumer surfaces, and it is
measuring *silence*, not phase length — a phase that takes two minutes while emitting
sub-events must stay clean. The last is the part most likely to rot into a false-positive
generator. Loads a model; ~3-4 min.
expected: `run_workflow("templates/ltx2/text-to-video", {num_frames: 25, width: 768,
height: 448})`, then `get_job_events` on the finished job —
- **the fire.** Somewhere inside `generating`, before the first `pipeline_step`, exactly one
  `event: "warning"` carrying `kind: "phase_stall"`, `phase: "generating"`, and a numeric
  `seconds_since_phase_start` at or just past the server's threshold (30 s as built; read it
  off the reading, don't hard-code it). Its `message` names the phase and the elapsed figure.
  Nothing in the payload is LTX- or pipeline-specific — `phase` is just whatever phase the job
  was in.
- **both surfaces.** The same text appears in `get_job` / `wait_for_job` `warnings`, prefixed
  with the step's name, while the job is still running — not only after it finishes.
- **it stops.** No further `phase_stall` for `generating` after the first `pipeline_step`
  event. The watchdog is silenced by progress, not by the phase ending.
- **no false positive on a slow-but-talking phase.** The same job's `loading` phase runs well
  past 30 s total while emitting its component sub-events; as long as no *gap between* those
  is over the threshold, it draws no `phase_stall`. Check the gaps in the event stream and
  assert against them, not against the phase's total length.
If the lead-in happens to come in under the threshold (a fully warm box can shorten it), the
fire arm is **inconclusive, not a pass** — re-run it as the first `ltx2` job of the session so
the load is cold. The other three arms hold either way.
It is a **finding** if the warning is a plain `log` line or loses `kind`/`phase`/
`seconds_since_phase_start`, if it appears on only one of the two surfaces, if it keeps firing
after progress resumes, or if any phase that is emitting events inside the threshold draws one
anyway.
cleanup: delete the run's outputs. No durable fixtures.
source: tester, verified in #176, model `opus` via provider `anthropic`, on 2026-09-16 against
dw 0.4.0-beta.4 on `lem`. Measured as job `9baf48bea129`: `generating` entered at 84.2 s, one
`phase_stall` at 117.7 s with `seconds_since_phase_start: 33.5`, first `pipeline_step` at
134.3 s and nothing after; `loading` spanned 6.6-84.2 s with sub-event gaps of 28.5 s and
21.9 s and stayed clean. The issue's "repeats on an interval while the stall continues"
requirement is deliberately **not** asserted here — no consumer-side lever lengthens a phase's
silence enough to see a second firing, so it is covered by unit tests in the dw repo instead.

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

## Performance
