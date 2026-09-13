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
sweep) live in `agents/REGRESSION_AGENT.md`, not here.

Maintained by the regression agent, run via `run-regression.sh`, and grown
by the implementer/tester too (see "Adding a case" below). Each case is
intent + expected result, not a pinned tool/param name — confirm the exact
call shape against the live tool schema each run, since the server evolves.
This file only ever grows with new cases and fixtures; it holds the durable
test, never a log of runs. A case that passes gets no edit — status for a
failure lives on the GitHub Issue it produced, not as a note appended here
(`last run:` lines already in this file predate that policy and are kept as
history, not a model to continue). No agent may delete, weaken, or rewrite
an existing case, including one it thinks has become too expensive or not
worth what it costs — see "Removing a case" below.

## Adding a case

The implementer and the tester both grow these suites, not just the
regression agent — see `regression-suite-smoke.md`'s "Where a case
belongs" for which file. Use the existing case format (intent + `expected:`
+ `cleanup:`), the next unused `C-Fnnn`/`C-Pnnn` ID, and a `source:` line
naming who added it and why (e.g. `source: implementer, fix for #42` or
`source: tester, found while running TESTER_TASK.md`). No separate approval
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
last run: (not yet run by the regression agent — first observed 2026-09-12 in
job `a8488310d953`, 8.5 s for a three-step version, no GPU time: warning text
`join_unmatched: concat_videos: the tracks being joined span 11.1 dB (rms
-31.1 to -20.0 dBFS) ...`, one `level_spread` event at seq 9, matched step
`mean_dbfs` -20.014.)

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
last run: (not yet run by the regression agent — first observed 2026-09-12 in
job `a8488310d953`: `fps: 24.0`, 248 frames, 10.334 s against 10.334 s of
audio, where the same step wrote 8.0 / 31.0 s before the fix. Prose half
first observed 2026-09-13 on 0.4.0-beta.3, jobs `59bbb88ac014` (declared 8:
`will play 0.33x speed (3 times as long)`) and `a3783461e87a` (declared 48:
`2x speed (0.5 times as long)`), 3.5 s and 2.6 s, no GPU time.)

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
cleanup: delete the `A`/`B` probe workflows from the workspace. No outputs.
source: tester, verified in #89 (run over MCP 2026-09-13 as the calls above,
model `opus` via provider `anthropic`).
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: all three as expected; the cycle error reads `... composes a
workflow that is already composing it - a cycle: B -> A -> B` at path
`steps[0].workflow.path -> steps[0].workflow.path -> steps[0].workflow.path`.
Note `save_workflow` accepts the write that *creates* the cycle, because at
that moment the child on disk is still the leaf; validate and run both catch
it immediately after, so no job can start. Do not assert a failure at save.)

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
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3, job `04c6bf9908d4`, 17.7 s for both steps including SD1.5 load:
manifest `left`/`right`, gallery total 2.)

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
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: Music3 job `bb2c89ba6f54`, 75.6 s, `semantic_generator` at 0.0 s
and `denoise` at 36.3 s bounding a previously silent 36 s lead-in, first
`pipeline_step` at 46.6 s; H3 job `958078231173`, `text_encoder` logged at
102.8 s, the same instant as `phase: generating`.)

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
**Cold worker matters:** the curated figure is whole-run wall clock including
model load, and ~65% of this run is `loading`. A warm-worker run lands far
under it and does not test anything.
cleanup: delete the generated mp4.
source: tester, verified in #97 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as job `bd2f45b50862`, model `opus` via
provider `anthropic`).
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: 108.1 s total against a curated 1.8 min; `saving` at 105.6 s,
`writing ... (121 frames)` at 105.6, `wrote ... in 1.3s (1.4 MB)` at 106.9,
`step_end` at 107.2 — 1.6 s, against 133 s before the fix.)

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
**This case is ~10 minutes of GPU time** and is the most expensive in the
file. It earns it: this is the failure mode that silently costs a whole
session's work, and it cannot be tested with one run or with two runs of the
same family.
cleanup: delete both generated outputs.
source: tester, verified in #98 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as jobs `bd2f45b50862` then `2700403c7998`,
model `opus` via provider `anthropic`).
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: job 2 succeeded in 483.3 s where the byte-identical job died at
314 s before the fix; `Released cached models: host RSS 2042 MB, 60528 MB
available (21892 MB returned to the OS)` at 5.6 s; job 2 peak 61,882 MB
against 61,867 MB on a fresh worker.)

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
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: `final/episode-0.0.mp4` + `final/episode-0.0-2.mp4` from a
6.4 s two-step `concat_videos` job, against
`ep5-episodeqa-ep5-episode-episode.0-0.0.mp4` before the fix; the `sub/episode`
validate refused at the documented path.)

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
the same day while running TESTER_TASK.md.
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: 24.0 fps / 5.167 s / 124 frames with no `result.fps`, against
8.0 fps / 15.5 s before the fix; the `fps: 12` arm warned "Writing video at 12
fps, but the frames it was given run at 24.0 fps - the file will play 0.5x speed
(2 times as long). Drop 'fps' from the step's result to keep the source rate".
Third arm first observed the same day in job `af9317223452`: a fully undeclared
`concat_videos` join of two 24 fps assets gave 24.0 fps / 248 frames / 10.334 s in
7.0 s, and the level warning fired — "the tracks being joined span 6.5 dB (rms
-25.5 to -19.0 dBFS) - the cut will be audible as a level jump. Pass match_levels
to even them out".)

### C-F010 — a cost estimate re-prices for the list it was actually given
A list-driven template's curated cost was measured on one list length. Validating
it with a *different* length must not quote the measured figure unchanged.
`validate_workflow(name="templates/minimax/dialogue-short", arguments={"shots":
[...]})` three times — a list shorter than the stored default, the stored default
(pass no `arguments` at all), and a list longer than it. Free: validation only,
nothing is queued.
expected: `plan.estimate.minutes` differs across all three, and `plan.steps` moves
with the list. `basis` is the assertion that matters:
- the **stored-default** run reports `catalog` — a measurement of *this* list.
- the resized runs report `derived` (or `per_entry`, which is strictly better, if
  the template gains a measured per-entry rate) — arithmetic on a figure measured
  on a list that is not yours.
The regression is #85: the same `minutes` returned for every length under
`basis: "catalog"`, so the quote was the stored default's figure wearing a label
that claimed it was measured for the caller's run. **Never the same number twice
with a different `steps` count** is the one-line form of this case.
Also assert `plan.list_entries` echoes the length the server realized, so a
failure separates "priced wrong" from "parsed the list wrong".
cleanup: none — validation is free and queues nothing.
source: tester, verified in #85 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13, model `opus` via provider `anthropic`).
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3, `templates/minimax/dialogue-short` on an RTX 3090 figure of 42.0:
2 shots → 5 steps / 16.8 min / `derived`; 5 shots (default) → 8 steps / 42.0 min /
`catalog`; 10 shots → 13 steps / 84.0 min / `derived`.)

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
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: bare `true` → `acknowledged: "boolean"`, `acknowledged_cost: null`,
against `"none"` before the fix.)

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
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: seeded `pair_audio` step, `cached_steps` 0 → 1, second manifest
`reused: true` pointing at run `20260913-152107-e387623b`'s file from run
`20260913-152117-e387623b`, 1.88 s → 0.84 s.)

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
source: tester, found while running TESTER_TASK.md on 2026-09-13 (filed as #106),
rewritten from a documented-failure case to a happy-path case on 2026-09-13 after
verifying the fix over MCP — jobs `bb66467e03f5` (mono, succeeded, `channels: 2`,
`fps: 24.0`), `90dbe57f0bc5` (stereo control, `warnings: []`) and `e33eac7b6449`
(the chained extension). Model `opus` via provider `anthropic`.
last run: (not yet run by the regression agent in its pass-form. History: the
pre-fix failure was first observed 2026-09-13 on 0.4.0-beta.3, two different mono
wavs failing identically (`[1, 155520]` and `[1, 178880]`); after the #106 fix on
the same day and the same server version, the mono job succeeds with
`"Duplicating a mono audio track of 178880 samples into two channels - an mp4
audio stream takes stereo and nothing else"`.)

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

## Performance
