# Regression suite — dw MCP server — smoke level

Fast, fundamental, general-purpose checks — not tied to a specific
model/pipeline. This is what runs by default (`./run-regression.sh` with no
args), and every run of `complete` runs this file first. Sibling suites:
[`regression-suite-complete.md`](regression-suite-complete.md),
[`regression-suite-model-specific.md`](regression-suite-model-specific.md)
and [`regression-suite-security.md`](regression-suite-security.md).

**Where a case belongs** (same test for the implementer, tester, and
regression agent): would it be bad if this broke silently and stayed broken
between every regression run, for any model/pipeline a consumer might use?
→ **this file**. Is it a real gap but the suite can afford to check it less
often — because it's individually slower, or because there are simply many
variants of it? → `regression-suite-complete.md`. Does it only make sense
for one specific named model/pipeline/checkpoint? →
`regression-suite-model-specific.md`. Would its *failure* mean an agent got
past a server boundary — code ran, a file outside the server's roots was
touched, a request left the box, a secret leaked? →
`regression-suite-security.md`, regardless of speed. Keep this file itself
lean — every
case in it runs on every single pass.

Workspace: `regression-smoke`. Case IDs in this file use the `S-` prefix
(`S-F001`, `S-P001`, ...) so they never collide with the `C-`/`M-` IDs in
the sibling suites — the regression agent's duplicate-issue search is keyed
on the full prefixed ID. Full run mechanics (fixtures vs. outputs, cleanup,
the final sweep) live in `agents/REGRESSION.agent.md`, not here.

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
regression agent — see "Where a case belongs" above for which file. Use the
existing case format (intent + `expected:` + `cleanup:`, plus `metrics:` when a number
the case yields — a size, a count — matters as a trend and should be logged
in `regression-perf/`; seed that file with the reading you just took, and do
the same for a new `-P` case's timing), the next unused
`S-Fnnn`/`S-Pnnn` ID, and a `source:` line naming who added it and why
(e.g. `source: implementer, fix for #42` or `source: tester, found while
running TESTER_TASK.agent.md`). No separate approval step — the regression agent
already grows these files unsupervised when it notices gaps; a case either
of you adds is the same kind of edit.

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

Durable contents of `regression-smoke` that persist across runs. Add a line
when a case starts relying on one; remove the line (and the fixture) when
nothing uses it anymore.

- `asset:qa-cast/ep11-bed.wav` — a 472-frame (24 fps) 32 kHz mono bed in
  the shared asset library, reachable from every workspace. S-F029 slices 141
  frames from its head; all that matters is that it is comfortably longer than
  that, so the slice never reaches the end and pads. S-F081 reads its envelope: it is
  19.667 s, so a `ceil` bin count is 20, and its last 0.667 s is a fade ≈ 15 dB below the
  body — any substitute needs a non-whole-second duration and a tail that is audibly
  quieter than the second before it. S-F096 mixes and crossfades it with the 44.1 kHz
  `ep15-song.mp3` as the 32 kHz half of a rate-mismatched pair. Read-only — never sliced
  in place, never deleted.
- `asset:qa-cast/ep13-episode.mp4` — a 282-frame 24 fps 960x544 stereo 44.1 kHz
  episode in the shared asset library. S-F031 muxes a soundtrack onto it twice; its
  known geometry is what says the mux moved only the audio. S-F086 dissolves it after the
  32 kHz `ep6-cold-open.mp4` as the 44.1 kHz half of a rate-mismatched pair. S-F082
  validates it as a `shots` entry. Read-only.
- `asset:qa-cast/ep15-song.mp3` — a 30.0 s 44.1 kHz stereo Music 3 track that decodes
  at **+0.76 dBFS**, i.e. with no headroom. S-F031's positive control depends on that:
  it is the clipping exhibit from #158/#159, not just a song, so replacing it with a
  quieter track silently disarms the case. S-F096 mixes and crossfades it with the 32 kHz
  `ep11-bed.wav` as the 44.1 kHz half of a rate-mismatched pair; its 30.023 s length is
  in that case's expected durations. Read-only — never normalized in place, never deleted.
- `asset:qa-cast/ep6-cold-open.mp4` and `asset:qa-cast/ep3-shot2-reply.mp4` — two
  124-frame 24 fps 960x544 32 kHz stereo shots in the shared asset library. Joined in
  that order because the first has the loudest outgoing tail among the
  shared shots (last full second −20.5 dBFS RMS) and the second the quietest head
  (first second −44.4 dBFS RMS), which is what makes a bled tail measurable against
  the incoming material. Both also serve the `complete` suite; read-only, never
  deleted. Any substitute pair needs the same loud-tail-into-quiet-head shape, re-read
  from `get_gallery_metadata(envelope=true)` on the assets. S-F071 also tiles the first
  one with `frame_grid`; its 960×544 / 124-frame geometry is what the expected grid
  sizes are computed from. S-F086 dissolves the first one into the 44.1 kHz
  `ep13-episode.mp4` as the 32 kHz half of a rate-mismatched pair (its 124 frames are in
  that case's expected frame count). S-F082 binds both (with `ep13-episode.mp4` and
  `ep20-score.wav`) to `templates/dissolve-between-shots` in a validate-only call.
- `asset:qa-cast/ep11-coldopen.mp4` — a video with a soundtrack in the shared asset
  library (peak −1.04 dBFS, RMS −20.9 dBFS as `analyze_audio` reads it). Kept as a
  "video in, soundtrack measured" input shape for `analyze_audio`; any substitute
  just needs a non-silent soundtrack. Read-only, never deleted.
- `asset:qa-cast/ep20-score.wav` — a ~10.3 s score bed in the shared asset library.
  S-F057 and S-F068 pass it as `score` to the two sequence templates; a `total_frames`
  longer than it draws a `slice_past_end` warning, which those cases either expect or
  avoid by choosing `total_frames` ≤ 248. S-F082 validates it as `score`. Read-only,
  never deleted.
- `asset:qa-cast/hal-voice.wav` — a 6.48 s 24 kHz mono line in the shared asset
  library. S-F072's pad control lays it under the 19.67 s `ep11-coldopen.mp4`; any
  substitute just needs to be clearly shorter than that video. Read-only, never deleted.
- `asset:qa-cast/ep25-episode.mp4` — a 360-frame 24 fps 960x544 32 kHz stereo cut in the
  shared asset library: a 248-frame shot dissolved over 12 frames into a 124-frame one, so
  the second shot's first frame is 236 and the track is exactly 15.0 s. S-F080 reads it
  with `get_output_frames`; the frame arithmetic in its expected block is computed from
  that geometry. S-F081 reads its envelope as the whole-second control (exactly 15 bins).
  Read-only, never deleted.
- `asset:qa-cast/ep33-episode.mp4` — a 224-frame 24 fps 960x544 32 kHz stereo cut in the
  shared asset library that decodes at about −1.0 dBFS peak. S-F093 mixes it solo at 1.0
  and 0.5 and reads the 6.02 dB difference; any substitute needs a non-silent 32 kHz
  soundtrack (its exact peak is read from the asset at run time, not assumed). S-F093 also
  loops `ep11-bed.wav` (above) to its 224-frame length. Read-only, never deleted.
- `asset:uploads/qa-cast/room-bed.wav` — a 4.96 s 16 kHz mono room-tone bed in the
  shared asset library that decodes at about −50 dBFS mean, i.e. below the −40 dBFS
  `audio_near_silent` line by design. S-F103 slices it as the "source that arrived
  quiet" half of the near-silent rule; any substitute must already be under −40 dBFS
  before it is sliced, or the case's negative arm proves nothing. Also the `complete`
  suite's C-F016 fixture. Read-only, never deleted.

## Functional

### S-F001 — create workspace
Create a workspace if `regression-smoke` doesn't already exist.
expected: workspace created and selectable/targetable by subsequent calls.
When it already exists, `create_workspace` answers with a clean, named tool
error ("Workspace 'regression-smoke' already exists") rather than succeeding
idempotently — that is the server's behaviour as of 0.4.0-beta.3 and is fine;
a crash, an unnamed 500, or a silent re-create that loses the fixtures is the
finding. `create_workspace(name, use=true)` also switches the session.
cleanup: none — the workspace and its listed fixtures persist across runs
by design.

### S-F002 — list available tools/templates
Call whatever the server exposes for tool/template discovery (e.g. a
tools-list or templates-list call).
expected: non-empty list; response includes at least one image-generation
capability and at least one audio/workflow template — concretely,
`templates/text-to-image` (image) and `templates/generate-speech` /
`templates/minimax/music` (audio) have been present on every run to date, so
their absence is the first thing to suspect. `list_workflows()` is the call;
its default answer is the summary view S-F015 pins. This is the schema
sanity check every other case leans on.
cleanup: none (read-only).

### S-F003 — generate a single image, default params
Using the server's basic image-generation tool/template, generate one image
in `regression-smoke` with only the required parameters (a simple prompt,
everything else default).
expected: call succeeds, response includes a reference to a generated image
asset (path/id/url per whatever the schema returns), and that asset is
retrievable/listable afterward in the workspace.
cleanup: S-F006/S-P002 inspect this output first; delete it right after
they've run (or after this case, if S-F006 is skipped).

### S-F004 — generate a single image, explicit size/seed
Same as S-F003 but pin an explicit size and a fixed seed. The stock
`templates/text-to-image` declares only `prompt` and `num_images_per_prompt`,
so this needs an inline workflow: top-level `seed` (per the "workflows" guide)
and `width`/`height` as step arguments — 384x384, seed 424242, 20 steps has
been the shape. Run it **twice, differing only in `result.file_base_name`**
(`s_f004_a` / `s_f004_b`): that field is part of the step's cache key but not
of the image, so it is the lever that forces the pipeline to actually re-run.
An identical rerun only comes back `reused: true` from the step cache and
proves cache keying, not the seed.
expected: both calls succeed as two distinct run ids with no `reused` flag on
either manifest; `get_output_image` reports `original_size: [384, 384]`; the
two jpgs are byte-identical (compare `size` in the listing and the bytes
returned) and both carry `seed: 424242` in `get_gallery_metadata`. Seed
reproducibility is established behaviour as of 0.4.0-beta.3 — two different
images from the same seed is the finding.
cleanup: same as S-F003 — hold for S-F006/S-P002, then delete both images
(the seed-repeat one too).

### S-F005 — invalid image-generation params are rejected cleanly
Call the image-generation tool with an invalid parameter. Three probes,
run all of them: (a) `arguments: {num_images_per_prompt: "not-a-number"}`;
(b) `arguments: {nonexistent_variable: 3}`; (c) an inline workflow at
383x383 (not divisible by 8).
expected: a clear validation error, not a 500/crash/hang, and not a silently
"corrected" result. (a) and (b) are refused pre-flight by `run_workflow`
with a tool error naming the path and, for (b), listing the declared
variables — nothing is queued. (c) is caught only at run time —
`validate_workflow` passes it (that boundary is S-F011's subject): the job
`fails` with the pipeline's "`height` and `width` have to be divisible by 8"
message, an empty manifest, and nothing in the gallery.
cleanup: confirm nothing was created (a rejected call must not leave an
output behind — if it did, that's part of the finding); delete it if so.

### S-F006 — list/probe workspace contents
After S-F003/S-F004, use whatever inspection tool the server offers (list,
probe, etc.) against `regression-smoke`.
expected: the generated assets from this run are visible and correctly
described (type, size, or other basic metadata matches what was requested).
`list_gallery()` carries `folder`, `subfolder`, `kind`, `size`, `mtime` and a
workspace-scoped `url` but **no image dimensions**, so "size matches what was
requested" is checked with `get_output_image` (reports `original_size`) or
`get_gallery_metadata` (returns the embedded workflow, arguments and seed).
cleanup: this is the last case that needs the S-F003/S-F004 outputs — delete
them here, then re-list to confirm they're gone (a deleted output still
showing is a finding).

### S-F007 — basic audio or multi-step template runs end-to-end
Run one of the simpler multi-step templates (whatever the schema currently
calls the smallest end-to-end workflow — e.g. a single-shot or single-line
template) with minimal inputs. The shape used to date is a three-step inline
chain: Bark `generate_speech` → `slice_audio` to `variable:clip_seconds` =
1.5 → `fade_audio` at `variable:sample_rate` = 24000, saving only the final
step. (Schema note: `result.sample_rate` will not take a `variable:`
reference — schema validation runs before substitution — and the error names
both paths; documented behaviour, not a finding.)
expected: the whole chain completes without a dropped parameter between
steps (this class of bug has bitten before — a chain silently losing a param
partway through is worse than an outright failure, so check the final output
actually reflects every input given, not just that the call returned 200).
For the chain above: `get_gallery_metadata` on the final wav reports
`duration_seconds: 1.5` and `sample_rate: 24000`, its envelope shows the
fades and a non-silent level, and the unsaved intermediate steps report empty
file lists. S-P004 times this same job.
cleanup: delete every intermediate and final output the template
produced, plus any asset `keep_output`-style steps may have linked, unless
one is needed for a repro.

### S-F008 — delete_output actually removes the file
Generate one small default image, delete it with the server's delete tool,
then list/probe the workspace.
expected: delete call succeeds; the output no longer appears in the listing
and fetching it by name is a clean not-found, not a stale entry or a 500.
This is the case the rest of the suite's cleanup leans on — if it fails,
say so in every other case's issue.
cleanup: the case is its own cleanup.

### S-F009 — the step cache does not serve a deleted output
Run a workflow once, delete the output it produced, then run the identical
workflow again.
expected: the second run regenerates — a fresh run id and a real file on
disk. A manifest entry marked `reused` that points at the file just deleted
is the finding: it hands a consumer a name that 404s.
cleanup: delete the regenerated output.

### S-F010 — validate_workflow catches argument errors before the run
Call `validate_workflow` with the same `arguments` a run would use: one
undeclared name, and one value that will not coerce to the declared type.
expected: `valid: false` with one error per problem, each carrying its JSON
path (`arguments.<name>`), `checked_arguments` naming what was checked, and
no GPU time spent. Then send the same two mistakes to `run_workflow`: they
are refused pre-flight rather than failing a queued job, and the message and
`path` are the same string `validate_workflow` returned — the two paths
share one validator, and them drifting apart is the finding.
cleanup: none (read-only).

### S-F011 — pipeline value constraints are a clean run-time failure
Validate, then run, a workflow whose values are schema-valid but the
pipeline will refuse (e.g. an image size not divisible by 8).
expected: documents where the line sits. `validate_workflow` checks schema
and pipeline *signatures*, not value ranges, so it passes; the job then
fails with the pipeline's own message, an empty manifest, and no partial
output left behind. A hang, a 500, or a silently corrected size is the
finding — so is a run that leaves a file in the gallery. (Same probe as
S-F005(c); kept as its own case because what it pins down is the
validate/run boundary, not the error's tone.)
cleanup: confirm the failed run wrote nothing; delete it if it did.

### S-F012 — the host-memory high-water mark is never below current
Call `get_memory()`. Whenever both `host_memory_rss_mb` and
`host_memory_peak_rss_mb` are present in a reading, assert
`host_memory_peak_rss_mb >= host_memory_rss_mb`.
expected: the invariant holds, in every state the worker can be in — never
read, freshly started, busy, idle after a load, dying. A peak is defined by
never being below the current value, and `peak - rss` is the leak test an
agent writes against these fields; a small negative number there reads as
"my arithmetic is wrong" or "these fields are not comparable", and the
honest next move is to stop trusting the pair.
Note which state the reading came from, because that is what makes this case
worth running repeatedly for one assertion: the two figures come from
different sources (a kernel high-water quantized to whole pages, and psutil's
current `rss` sampled a moment later), so they only disagree where the
process has never peaked meaningfully above where it sits — a **fresh worker
that has not yet run a large model**. That state is hard to reach on purpose
from the consumer side, since starting a worker means running something,
which immediately gives it a real multi-gigabyte peak. A regression run that
happens to begin shortly after a server restart is the best chance anything
has of sampling it, which is precisely why this lives here rather than being
called verified once. (As of 2026-09-13 that state has not been sampled by
any run — every reading so far came from a worker already carrying a
multi-gigabyte peak. Say explicitly which state each reading was from.)
A reading with `live: false` and `info: null` (nothing resident) has neither
field and is not a failure — skip it and say so. Both fields are absent
rather than null on a platform that cannot measure them; same treatment.
cleanup: none (read-only).
source: tester, verified in #83 (implementer proposed the case in its hand-off
comment; added here after running `get_memory()` as model `opus` via provider
`anthropic` — peak 2594.86 against rss 2226.33 on a worker that had just run
a job).

### S-F013 — a per-call workspace pin reaches the output-side tools
From a session **not** in the workspace under test, run a cheap generation
pinned with `run_workflow(..., workspace="regression-smoke")`, then take a
file name **verbatim from that job's manifest** and call the output-side
tools with the same `workspace=` pin and **without** calling `use_workspace`
first: `keep_output` it to an asset, and `list_gallery` it.
Set the session with `use_workspace("default")` for the duration and restore
`use_workspace("regression-smoke")` at the end. Nothing is written to
`default` — the pin is what sends every write into `regression-smoke`, which
is the whole assertion.
expected: the pinned `keep_output` returns an `asset:` reference whose `path`
is under `regression-smoke/assets`, and the pinned `list_gallery` returns
`regression-smoke`'s files with `workspace: "regression-smoke"` in the reply
and a `url` on each entry already carrying `?workspace=regression-smoke`.
"Path does not exist", with the workspace segment missing from the path it
names, is the regression.
Two things to assert beyond the happy path, because they are what a
half-wired pin looks like:
(a) **negative control** — the same `keep_output` with `workspace` dropped
must still *fail*. That failure is correct (an unpinned call resolving
against the session's `default`); if it succeeds, the pin is being ignored in
favour of something else and the passing case above proves nothing.
(b) **the pin must not switch the session** — an unpinned `list_gallery`
straight after the pinned keep must report `workspace: "default"`. A pin that
silently becomes a switch is a different bug with the same symptom set.
The tools carrying `workspace` are `keep_output`, `list_gallery`,
`get_gallery_metadata`, `get_output_image`, `get_output_text`,
`download_output` and `delete_output`. Checking one read tool and one write
tool is enough per run; rotate which ones rather than doing all seven.
cleanup: delete the generated output and the kept asset (both pinned).
source: tester, verified in #99 (proposed by the implementer in that issue's
hand-off; run over MCP 2026-09-13 as job `bd2f45b50862` into workspace
`qa-ep5` from a session in `default`, model `opus` via provider `anthropic`).
This is the second time a workspace pin has been wired on the run side only,
which is why it is in smoke and not `complete`.

### S-F014 — the asset-side tools and the per-call workspace pin
`keep_output` takes a `workspace` pin and will create an asset in a workspace the
session is not in (S-F013). Check what can then be done with that asset from
outside: call the asset-listing and asset-deleting tools, from a session in
`default`, against an asset that lives in `regression-smoke`.
expected: documents the pin's coverage on the asset side, which as of
0.4.0-beta.3 is *absent* — `list_assets` and `delete_asset` declare no
`workspace` parameter, so an asset created by a pinned `keep_output` is invisible
and undeletable until `use_workspace` switches the session to it. That asymmetry
is the case's subject, not a pass/fail on its own: record it. It becomes a
**finding** if it gets worse (a pinned `keep_output` starts writing somewhere
`use_workspace` cannot reach either), and the case should be rewritten as a
happy-path pin check if the two tools gain the argument.
Assert regardless: after `use_workspace("regression-smoke")`, `list_assets` shows
the asset with `origin: "workspace"` and `delete_asset` removes it — a pinned
write must never strand a file the API cannot clean up.
cleanup: delete the generated output (pinned) and the kept asset (after
switching), leaving no asset behind either way.
source: regression agent, noticed while running S-F013 on 2026-09-13 as model
`opus` via provider `anthropic`; added at smoke level rather than `complete`
because it is the cleanup path every other case's `cleanup:` line depends on
being able to reach.

### S-F015 — the discovery calls answer compactly, and the full form is still reachable
The three calls a cold session makes before it knows anything — the guide, the
schema, the workflow catalog — each answer an *index* by default and the whole
thing on request. This is the contract #101 shipped, and its failure mode is
silent: a regression costs every session tokens it never sees itemised, and
nobody notices until a context runs out. All three are free and instant.
expected: three independent assertions, each a default call and its drill-down.
1. **Guide.** `get_guide("workflows")` with no section → `content` is the
   opening plus the *first* section only, and the answer carries `sections`
   (every heading, in order) and `withheld` (the rest). Assert `content` is
   under ~3 KB and contains **no heading named in `withheld`** — leakage is the
   regression, not size alone. Then fetch one withheld section by name and get
   it whole. The pre-#101 behavior was ~19.6 KB on the no-section call.
2. **Schema.** `get_schema(section="result")` → `schema.$defs` has exactly the
   one key `result`; `sections` lists all six (`configuration`, `pipelines`,
   `result`, `steps`, `tasks`, `variables`); `elsewhere` names the section
   holding each `$def` the fragment still `$ref`s (`{}` for `result`, and
   `{"arguments": "pipelines"}` for `tasks`). Then `get_schema()` with no
   argument → still the whole schema, with `steps` under `properties`. Then a
   misspelled section (`"pipline"`) → an error **naming the six real sections**,
   not a silent empty answer.
3. **Catalog.** `list_workflows()` with no filter → `view == "summary"` and every
   entry in `details` is `{summary, shape}` only; the `workflows` name list is
   unabridged. Then `list_workflows(shape=...)` for any shape → the same entries
   carry `traits`, `cost`, `kinds`, `variable_names` and (where the workflow is
   list-driven) `lists` again. Both directions matter: a summary that never
   expands is as broken as a default that never summarises.
metrics: `bytes` of 1 (`condition: guide-index`) and of 3's summary answer
(`condition: catalog-summary`), logged to `regression-perf/S-F015.jsonl` — the
point of #101 was the number, and a slow creep back up is what this case exists
to catch, so those two are compared against their history per the regression
agent's rule as well as against the ceilings here: guide index under 3 KB (above),
catalog summary under **20 KB** (~12 KB at 71 entries; a catalog that has
legitimately outgrown that is a `baseline:`-style needs-approval ask, not a
silent edit). Also log `get_schema()`'s full size (`condition: schema-full`) for
the trend, but no ceiling on it: it's on-request, and its size is the schema's
honest size — the guard against it is `section=`, which item 2 already checks.
Note `view`/`note` are absent rather than `view: "full"` on the filtered answer —
that is current behavior as of 0.4.0-beta.3, not a finding; key on
`view == "summary"`.
cleanup: none — every call is read-only.
source: tester, verified in #101 (all three items proposed by the implementer in
that issue's hand-off; run over MCP 2026-09-13, model `opus` via provider
`anthropic`).

### S-F016 — an unseeded workflow is told why its step cache is off
`cached_steps: 0` on a plan is ambiguous on its own: it means either "nothing was
cached yet" or "the cache is off because this workflow sets no `seed`". A consumer
reading the second as the first re-runs everything forever and never learns why.
`validate_workflow` must say which. Free and instant — no run.
expected: `validate_workflow` on an inline workflow **with a pipeline step** and no
top-level `seed` (a task-only workflow is exempt — see S-F069) →
`valid: true` and a `warnings` entry naming both `seed` and `cached_steps` (the
0.4.0-beta.3 wording: "This workflow sets no 'seed', so the step cache is disabled
and 'cached_steps' is 0 without being probed …"). The **byte-identical** workflow
with `"seed": 1` added → `valid: true` and **no such warning**: the control is half
the case, since a warning that fires on everything says nothing. A seed supplied as
an `arguments` value for a `variable:`-spelled seed counts as seeded and must not
warn either.
It becomes a **finding** if the warning disappears (the #107 regression), if it
fires on a seeded workflow, or if `valid` flips to `false` — this is advice, not an
error, and must never block a run.
cleanup: none (read-only).
source: tester, verified in #107 on 2026-09-13 over MCP as model `opus` via
provider `anthropic` — unseeded and `"seed": 1` forms of the same one-step
`pair_audio` workflow, warning present then absent. The `pair_audio` form no
longer warns as of #247 (it's task-only, see S-F069); the probe is now a
one-step `StableDiffusionPipeline` workflow (proposed and verified in #297).

### S-F018 — the other three workflow objects are closed too
The `step`, `task`, `pipeline_reference` and `workflow_reference` objects' schema
closure is covered by unit tests (the case that once re-confirmed it here, S-F017,
was retired in commit `bd5e0d5` as duplicate of that coverage). The same guarantee must
hold for the three that were still open after it: the **top-level workflow**
object, the **`result`** object, and the **`pipeline`** object. A stray key in any
of them is the same failure S-F017 existed for — the workflow runs and the key
does nothing. Free and instant — no run.
expected: four `validate_workflow` probes on inline one-step workflows.
(a) Top level carrying `"sedd": 42` and `"varaibles": {}` → `valid: false`, **one**
error at root (`path: null`) naming both keys and listing the legal set
(`configures, cost, description, id, seed, shape, steps, summary, traits,
variables`). (b) `result: {"content_type": "text/plain", "subfoldr": "final"}` →
`valid: false` at `steps[0].result` naming `subfoldr` and listing `subfolder`
among the legal set. (c) `pipeline_type` and `model_name` written at **pipeline
level** (they belong inside `configuration` / `from_pretrained_arguments`) →
`valid: false` with **exactly one** error per key, at
`steps[0].pipeline.pipeline_type` and `steps[0].pipeline.model_name`. (d)
`"trasformer": {}` at pipeline level → `valid: false`, **exactly one** error at
`steps[0].pipeline.trasformer`. The pipeline messages must state the *rule* — "any
other key whose value is a component definition (an object carrying
`from_pretrained_arguments`)" — not a fixed key list, since a component's name is
one of the pipeline's own keys.
Positive controls, and the reason this case cannot be scored without them:
`validate_workflow(name = "templates/ltx2/two-stage")` → `valid: true`. That is a
shipped workflow carrying a dynamic component key, so it is what distinguishes
"closed correctly" from "refuses everything unfamiliar". Second control, cheaper to
reason about: a hand-written component under an undeclared name but **missing its
`configuration`** → the error must be `'configuration' is a required property` at
`steps[0].pipeline.<name>` — i.e. the key was recognized as a component definition
and validated as one, not rejected as unknown.
It is a **finding** if any of (a)–(d) comes back `valid: true`, if a single stray
pipeline key produces more than one error (the pre-fix behaviour: a key refused by
the component rule also failed that rule's `type` and `required` checks, so one
typo arrived as three errors describing a component definition the author never
meant to write), or if either positive control stops validating.
`from_pretrained_arguments` is open by design and must stay so — do not add a probe
that closes it.
cleanup: none (read-only).
source: tester, verified in #123 on 2026-09-13 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep7`, dw 0.4.0-beta.3. Labelled
`breaking-change` on the fix: a workflow carrying a dead key validated before it
and does not after.

### S-F019 — an input asset's own duration/fps/sample_rate is readable before a run
A workflow's `total_frames`, `fps` and `sample_rate` are arguments the *caller*
supplies, and they are properties of the assets being passed in. If they cannot
be read, they are guessed, and a wrong guess is discovered as a failed job or as
silence padded onto a track (see C-F016). `get_gallery_metadata` must answer for
an `asset:` reference, not only for an output. Free and instant — no run.
expected: (a) `list_assets()` → take any entry with `kind: "audio"` or
`"video"`, and pass its `reference` verbatim to `get_gallery_metadata`. The
answer carries `source: "asset"`, `job: null`, `metadata: null` for a file
nothing here generated, and a `media` block whose `duration_seconds` is a
number — plus `frame_count` and `fps` for a video, `sample_rate` and `channels`
for audio. (b) `envelope=true` works on an asset too, returning one
`rms_dbfs`/`peak_dbfs` entry per second, so a position in an input track is
locatable and not just its length. (c) Counter-case:
`get_gallery_metadata(name="asset:does-not-exist.wav")` errors with a message
that names **every asset root it searched** (the workspace's own library,
`common/assets`, the examples library) — not a path under `outputs/`. (d)
Counter-case: `get_gallery_metadata(name="asset:../../../../etc/passwd")` is
refused as an invalid asset *name*, before any lookup.
It is a **finding** if an `asset:` reference resolves against the outputs root
again (the original bug: the prefix was echoed into an outputs path verbatim, so
the error read as a missing file rather than an unsupported reference form), if
`source` stops distinguishing `"asset"` from `"output"`, if `media` is absent for
a media asset, or if (d) resolves to anything at all — that last one is a
containment escape and belongs in `regression-suite-security.md`'s territory, so
report it there as well.
cleanup: none (read-only).
source: tester, verified in #127 on 2026-09-13 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep9`, dw 0.4.0-beta.3.

### S-F020 — a `succeeded` image job never hands back a blank frame unannounced
A job that reports `succeeded` with a populated manifest, a real file and no
warning is the only signal an unattended consumer has. If the engine can
substitute a solid-colour image for the one it generated — a safety-checker
blank, a degenerate latent — and still report exactly that, then no automated
caller can tell a shipped deliverable from a suppressed one without fetching and
*looking at* every frame. This is the assertion; the mechanism is the server's
business.
expected: two runs of the stock text-to-image template, differing only in seed.
(a) **The known-blank seed.** A run pinned to seed `3220371727974403` (prompt
`an apple`, SD 1.5, 25 steps, 512x512 — the #133 repro) must come back as
*either* a real rendered image, *or* `succeeded` **carrying a warning that names
the suppression** (in `warnings`, or in `get_gallery_metadata`). What it must not
be is an unqualified success wrapping a black frame.
(b) **Control.** The same workflow on a seed that renders normally → a real
image and **no** such warning. The control is half the case: a warning that
fires on every run says nothing.
For an agent that cannot judge pixels, the cheap discriminator is file size from
`list_gallery`: a solid-colour 512x512 JPEG is ~5-6 KB, a real SD 1.5 render of
the same prompt and size is ~25-33 KB. Anything under ~10 KB is the thing to look
at with `get_output_image` — but look, don't rely on the number alone, since a
genuinely flat composition would also be small.
It is a **finding** if (a) is a black frame with no warning anywhere in the MCP
surface, and a *different* finding if (b) starts warning too.
cleanup: delete both outputs. While #133 is open its own repro artifact is kept
separately and named there — don't keep a second copy from this case.
source: regression agent, found on 2026-09-13 running S-F009 as model `opus` via
provider `anthropic` (filed as #133: the stock template returned an all-black
image on a random seed and reported `succeeded`, `warnings: []`). At smoke level
because `templates/text-to-image` is the catalog's reference "hello world" and
the cheap generation step several other cases lean on.

### S-F021 — deleting a run's outputs returns the workspace to the size it was
Every other case's `cleanup:` line, and the regression agent's final sweep,
assume that deleting what a run produced leaves the workspace as it was found.
Check that directly instead of assuming it, since `list_gallery` being empty is
not the same claim.
expected: read `list_workspaces()` and note this workspace's `usage.files` and
`usage.bytes` before the run's first job; after every `cleanup:` has run, read
them again. The delta must be only what was deliberately kept — fixtures from
the "Fixtures" section and repro artifacts named in an *open* issue.
As of 0.4.0-beta.3 it is **not**: each queued job leaves two sidecars
(`manifest.json` and the realized `workflow.json`) in its run directory, which no
MCP tool lists or deletes, so the count rises by 2 per job forever — including
for a job that *failed* and wrote no media. That is #134, and until it closes this
case documents the gap rather than passing.
It becomes a **worse finding** if the per-job residue grows beyond those two
files, or if a deleted output's own media file is what survives — that last one
would mean `delete_output` is not deleting, and S-F008 would be failing too.
cleanup: none of its own — it measures the other cases' cleanup.
source: regression agent, found on 2026-09-13 during the final sweep as model
`opus` via provider `anthropic` (filed as #134). At smoke level because it is the
cleanup path every other case's `cleanup:` line depends on being able to reach —
the same reason S-F014 is here.

### S-F022 — `delete_output` reports the sweep, and a run directory is addressable and contained
S-F021 measures the *outcome* — the workspace returning to the size it was. This
case pins the two pieces of API surface #134's fix added to get there, which
S-F021 would not notice the loss of: `delete_output`'s `run_swept` field, and the
`<workflow>/<run id>` name form. A regression in either leaves S-F021 still
passing on a workspace that happens to be clean for another reason.
Run any cheap generating workflow whose manifest has exactly one media file
(`templates/dissolve-between-shots` over three short video assets is ~6 s, or
reuse whatever S-F007 just ran), and note its `run_id`.
expected:
- `delete_output(name=<the one media file's gallery name>)` → `deleted: true` and
  `run_swept` equal to that `run_id`. The field is how a caller knows the sidecars
  went with it; `run_swept: null` on the last media file of a run is a finding.
- On a second run of the same thing, `delete_output(name="<workflow>/<run id>")` —
  the first two segments of a gallery name — → `deleted: true`, `run_swept` the
  run id. This form is the only way to reach a run that failed before writing
  media, so it must not decay into "404 unless a media file names it".
- `delete_output(name="<workflow>/../../<some other workspace>/outputs")` → refused
  as an unknown file whose message ends ` - path contains a disallowed pattern`
  (it must not echo any resolved server path — the only path in the message is
  the `name` passed). Nothing outside this workspace's `outputs/` is reachable,
  and the refusal is a 404-shaped error, not a partial delete.
- `delete_output(name="<workflow>/not-a-run-id")` → refused as an unknown file
  whose message ends ` - path does not exist`. A name that is not a run id must
  never be treated as "delete this directory tree" — that is the failure mode
  that would turn a typo into a workspace wipe.
The last two are the reason this is not folded into S-F021: the addressable-run
form is a recursive delete taking a caller-supplied path, and what makes it safe
is that it refuses everything that is not exactly a run directory.
cleanup: the case deletes its own runs as its assertions — nothing is left. If a
probe's refusal unexpectedly succeeded, whatever it removed is gone and that is
the finding.
source: tester, model `opus` via provider `anthropic`, verified in #134 on
2026-09-13 against dw 0.4.0-beta.3 on `lem`, workspace `qa-ep10` (four jobs run
and swept by the two forms; `usage` returned to 4 files / 6,138 bytes exactly).
Not covered here, because a consumer-only agent could not provoke it: the
failed-job-with-no-media run the `<workflow>/<run id>` form exists for. Two
attempts at a fast runtime failure both succeeded instead — which became its own
issue — so that path is exercised against runs that did write media. Bullets 3-4
reworded per #322 to the exact refusal strings #310's fix settled on (`cc0c710`,
2026-09-22): the containment and not-a-run-id refusals no longer echo the `..`
pattern or a resolved path, so the wording pins the two message suffixes
observed over MCP instead.

### S-F024 — an out-of-domain number in an audio task argument is refused, not interpreted
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
- **4. At run time, which is the half a validator cannot cover.** `run_workflow`
  does **not** re-run the static pass, so a bad value reaches the command: run a
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
  workflow's own declared default — reaches the command unchecked. The job must
  **fail** — `status: "failed"`, `manifest: []`, `error` naming
  `target_sample_rate` — and must not succeed. This is the layer that produced
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
source: tester, model `opus` via provider `anthropic`, verified in #139 and #140
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

### S-F025 — an `asset:` reference nested inside a list entry is resolved at validate
`validate_workflow`'s argument pass must reach references that sit *inside* a
list-driven workflow's entries, not just top-level scalar arguments (S-F010's
ground). This is the shape a recurring cast takes:
`templates/minimax/dialogue-short` gets its portraits and voice clips from
`arguments.shots[N].references[M].from_file`, several objects deep in a list
entry. If a mistyped asset name there validates clean, the caller gets a
`valid: true`, a plan and a multi-minute quote, and the job dies at run time —
after the two Z-Image portrait steps have already burned about a minute — on a
typo that was free to catch. Both halves are needed: a validator that reports
every unresolvable nested reference but also refuses a good one is no better.
expected:
- **Negative.** `validate_workflow(name="templates/minimax/dialogue-short",
  workspace=<a workspace that can reach the cast>, arguments={"shots": [one
  entry whose `references[0].from_file` is a **nonexistent** `asset:` path, e.g.
  `asset:qa-cast/priya-portrait-NOPE.jpg`, and whose `references[1].from_file`
  is a real one]})` → `valid: false`, exactly one error, its `path` being
  `arguments.shots[0].references[0].from_file` — the full index chain, not
  `arguments.shots` and not a bare message — and its text naming the asset and
  listing the asset roots searched. `checked_arguments` includes `shots`. The
  finding is `valid: true`, or an error whose path stops at the list.
- **Positive control.** The same call with every `from_file` naming a real
  asset → `valid: true`, `errors: []`, `warnings: []`, and a `plan` whose
  `list_entries.shots` equals the number of entries passed. A validator that
  cannot resolve a legitimate nested reference would fail this and pass the
  negative for the wrong reason.
- Any list-driven template with `from_file`/`asset:` references in its entries
  works; `dialogue-short` is named because its cast fixtures are durable.
cleanup: none — `validate_workflow` is free and writes nothing.
source: tester, model `opus` via provider `anthropic`, found while running
TESTER_TASK.agent.md on 2026-09-14 against dw 0.4.0-beta.4 on `lem`. Both halves were
run in `qa-ep12` while casting ep12 from `asset:qa-cast/{priya,hal}-{portrait.jpg,voice.wav}`:
the typo gave the single error at `arguments.shots[0].references[0].from_file`,
and the corrected two-entry call gave `valid: true` with `list_entries.shots: 2`
and a 16.8 min `derived` estimate.

### S-F026 — a task step that cannot run is refused by the free pre-flight
`validate_workflow`'s own description says "always run this before
run_workflow", and the server already knows every task command's signature
(`get_task` reports `required: true` per parameter). A step that omits a
required argument, or passes one the command does not accept, cannot run — so
letting it validate clean hands back a `valid: true`, a plan and a fingerprint
for a job that will die, which costs a queue slot and, once the step is a
pipeline rather than an audio task, minutes of loading first. The false-positive
half matters as much as the check: a signature pass that refuses a *legitimate*
step would break every catalog workflow, so the positive controls below are not
optional padding.
expected:
- **Missing required argument.** `validate_workflow(workflow={"id":
  "missing-required", "steps": [{"name": "a", "task": {"command":
  "resample_audio", "arguments": {"target_sample_rate": 16000}}, "result":
  {"content_type": "audio/wav"}}]})` → `valid: false`, exactly one error whose
  `path` is `steps[0].task.arguments.audio` and whose text names both
  `resample_audio` and `audio`. **No `plan` key** — the answer must not also
  hand back a fingerprint for a run that cannot start.
- **Unknown argument is an error, not a warning.** The same shape with
  `crossfade_audio` and `{"audio": <any asset>, "other": <any asset>,
  "crossfade_ms": 0}` (the real parameter is `audios`, a list) → `valid: false`
  with **three** errors: the required `audios` not supplied, plus `audio` and
  `other` not accepted, each at its own `steps[0].task.arguments.<name>` path.
  A `valid: true` with these reported as warnings is the finding.
- **Positive control, single step.** `slice_audio` with `audio`,
  `start_seconds` and `duration_seconds` → `valid: true`, a `plan` present,
  and no error mentioning a signature.
- **Positive control, reference-supplied.** A two-step workflow whose second
  step supplies its required argument as `"audio": "previous_result:<step1>"`
  → `valid: true`, `plan.steps: 2`. The check must count a reference as
  supplying the argument rather than demanding a literal.
- **The chained-omission case is a refusal, and that is correct.** The same
  two-step workflow with step 2 omitting `audio` entirely → `valid: false` at
  `steps[1].task.arguments.audio`. Task steps are not fed the previous result
  implicitly (guide `workflows`, "Cross-Step Data Flow": chaining is an explicit
  `previous_result:step_name`), so the check applies at every step index, not
  only step 1. `run_workflow` on that same body is refused at the gate with the
  identical message rather than queueing.
cleanup: none — every call above is `validate_workflow`, which is free and
writes nothing. The one `run_workflow` is refused before a job exists.
source: tester, model `opus` via provider `anthropic`, verified in #141 on
2026-09-14 against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep10`. Cases 1-2 are
the implementer's proposed pair; the three controls are mine, and the fourth
was run specifically to rule out a false positive on implicit chaining.

### S-F027 — a step nothing reads does not run, and the three guardrails hold
The engine drops, before the first step executes, any step whose result no
later step references and which saves no file (#122). This changes what *every*
catalog workflow runs, so it is worth pinning cheaply rather than only at the
price of the H3 template that motivated it. Two things can go wrong and the
second is far worse than the first: elision stops happening (a silent cost
regression), or elision becomes too eager and deletes work someone wanted (a
silently different deliverable). Both directions below. All steps are
sub-second `slice_audio` calls, so the whole case is cheap.
expected:
- **Positive control — elision happens, at plan time and at run time.** A
  two-step workflow, step `a` a `slice_audio` with `result.save: false` that
  nothing references, step `b` an independent `slice_audio` that saves →
  `validate_workflow` gives `plan.steps: 1` and
  `plan.elided_steps: [{"step": "a", "reason": <names both halves: nothing
  reads it and it saves no file>}]`. Running it succeeds with `a` named in the
  job's **`warnings`**, and a manifest containing **only** `b`. The warning must
  survive to the finished job, not just the plan: the elision has to be legible
  as "the step did not run" rather than as a mysteriously different result.
- **Guardrail 1 — a step that saves is kept.** The same two steps with `a`
  carrying a default `result` (i.e. `save` not false) → `plan.steps: 2`,
  `elided_steps: []`, even though nothing references `a`. `save` defaults to
  true, so this is what keeps every pre-existing workflow behaving as it did.
- **Guardrail 2 — the last step is kept even when it reads nothing.** A
  single-step workflow whose only step has `result.save: false` →
  `plan.steps: 1`, `elided_steps: []`. A one-step utility workflow must never
  be elided into doing nothing.
- `plan` is computed **after** elision, so the step count a caller acknowledges
  is the count that runs.
cleanup: delete the output of step `b` from the positive-control run
(`delete_output` on that run directory). The validate-only cases write nothing.
source: tester, model `opus` via provider `anthropic`, verified in #122 on
2026-09-14 against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep11` (job
`f46dd989c696` for the run-time half). The implementer proposed the expensive
H3 version of this for `regression-suite-complete.md`; this is the cheap
engine-level equivalent, written because the guardrails are the part most
likely to be got wrong by a later change and they need no GPU to check.

### S-F028 — a declared variable bound is refused before anything loads
A workflow can declare a bound on a variable (`constraints`), and the point of
declaring it is that a bad value costs nothing instead of failing after the
weights are in memory — the filed case was `num_frames: 61` on an H3 template,
which used to validate clean and then fail 138 s into the run (#96). Two
properties are load-bearing and neither is obvious: the bound is checked against
the value **after** any declared rounding, and the bound is **readable from the
catalog** so the next caller does not pick a bad value in the first place.
expected:
- **Refusal, free and instant.** `validate_workflow(name=
  "templates/minimax/video-with-audio", arguments={"num_frames": 61})` →
  `valid: false`, one error at **`arguments.num_frames`** (the argument path,
  not a step path), its text carrying all three of: the accepted range
  (`124 to 345`), the rule (`17 * n + 5`), and the value it would round to
  (`73`).
- **Rounding is announced, not silent.** `{"num_frames": 130}` → `valid: true`
  with a warning naming `141` and saying the run generates 141, not 130.
- **Snap-then-range, the subtle half.** `{"num_frames": 108}` → **`valid: true`**
  (it rounds up to 124, which is in range) and `{"num_frames": 346}` →
  **`valid: false`** ("rounds up to 362 ... must be at most 345"). The bound is
  applied to the *aligned* count. A validator that checked the raw value would
  falsely refuse 108-123 — legal input — while still passing the 61 case, so
  this is the assertion that distinguishes a correct fix from a plausible one.
- **The catalog carries the rule.** `get_workflow(name=
  "templates/minimax/video-with-audio", variables_only=true)` →
  `constraints.num_frames` present beside the `num_frames` default, carrying the
  numbers and a `reason`. `list_workflows(shape="shot")` carries it terse on the
  same entry (`"17*n+5, 124-345, rounds up"`). This is the half that prevents the
  mistake rather than catching it.
cleanup: none — all four calls are free discovery/validate calls that write
nothing.
source: tester, model `opus` via provider `anthropic`, verified in #96 on
2026-09-14 against dw 0.4.0-beta.4 on `lem`. The implementer proposed the first,
second and fourth bullets; the snap-then-range pair is mine, added because the
implementer reported that their own first attempt checked the raw value and
would have falsely refused 108-123.

### S-F029 — a declared rounding is applied to the variable, not just inside the pipeline that needs it
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
- **The realized workflow reports the value as submitted.** `get_job_workflow`
  on that job → `workflow.variables.num_frames` is **`130`**, with
  `variable_constraints` alongside it. This is correct and deliberate, not a
  discrepancy to "fix": re-running that definition rounds to 141 again, so it
  still reproduces the run. It is written down because the obvious reading — that
  a realized workflow shows effective values — is wrong here, and a future change
  that rewrote it to 141 would need a deliberate decision rather than a silent one.
cleanup: `delete_output` the run directory of both jobs. The asset it reads is a
durable fixture (see "Fixtures") and is never written to.
source: tester, model `opus` via provider `anthropic`, found while running
TESTER_TASK.agent.md on 2026-09-14 against dw 0.4.0-beta.4 on `lem`. Measured twice: a
`music-video`-shaped run with `num_frames: 130` produced a 282-frame deliverable
(2 x 141) with both warnings on the job, and this audio-only probe isolated the
question the expensive run could not answer on its own — whether `slice_audio` saw
130 or 141. It saw 141.

### S-F030 — a cost estimate quotes this box's own history, and says when it stops being able to
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
  now demonstrates; see S-F100. Pick this bullet's example fresh each time rather than
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
  curated figure — see S-F078). Resizing away from the driver values the history
  was bucketed on must not keep quoting 11.8 under an `observed` label. `basis:
  "observed"` on an overridden shape is the regression, and it is the dangerous one,
  because the answer still looks well-sourced.
It is a finding if any of the three fail, and specifically if `basis` and `runs`
disagree in either direction — `observed` without a count, or a count on a figure
nobody measured here.
cleanup: none — `list_workflows` and `validate_workflow` are free and write nothing.
source: tester, model `opus` via provider `anthropic`, verified in #154 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`. The implementer proposed the
first bullet; the `runs`-is-honest bullet and the fall-back-off-the-bucket bullet are
mine, the third added because quoting a measured-looking figure for an unmeasured
shape is the failure that would survive the implementer's own case. Bullet 3's
fall-back target was reworded from `catalog` to `unknown` in #304 (2026-09-21) after
#267 removed the catalog hop; S-F078 is the case that pins that behaviour. Bullet 2's
example swapped from `music-video` to `enhance-prompt` per #320 (2026-09-22): #301's
small-n blend (S-F100) pulls a 1-run estimate toward a curated `cost` figure when one
exists, so `music-video`'s own 1-run answer is now 31.9 (blended), not the 25.8 raw
observed minutes this bullet quoted. Swapped again to `templates/describe-and-regenerate`
per #327 (2026-09-22): `enhance-prompt` had grown its own curated `cost` block (5.67
min/RTX 3090) by the time #320 landed — or already had one and #320's premise was wrong
from the start, consumer-side calls can't tell which — so it answered `tempered: true`
with `curated_minutes`/`observed_minutes` instead of `low_confidence: true`, the same
blended shape S-F100 exists to demonstrate, not this bullet's. Re-verified live over MCP:
`describe-and-regenerate` has `cost: null`, `observed_runs: 1`, and
`validate_workflow(name="templates/describe-and-regenerate")` answers `basis: "observed"`,
`runs: 1`, `minutes: 5.7`, `low_confidence: true`, with no `tempered`/`curated_minutes`
field present.

### S-F031 — normalizing before a mux is what puts headroom in the deliverable, and the warning tracks it
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
  `docs/proposals/h3-video-mux-headroom-warning-partial.md`), so a clean mux is never
  warned about a defect the encode didn't introduce. **Two** headroom entries for
  `raw_mux` is the regression to watch for in one direction (the deferral stopped
  working — the pre-2026-09-20 shape #194/#305 recorded); **zero** is the regression
  in the other (the written-file probe stopped firing, and a video mux's overshoot is
  exactly what that probe exists to catch). With the fixtures as given
  (`ep15-song.mp3` at 30.02 s, `ep13-episode.mp4` at 11.75 s), both branches also
  carry a `pair_audio: 'fit' trimmed …` warning — #246's intended trim notice (pinned
  as expected by S-F072's trim arm), not a finding, and not counted among the
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
to `regression-perf/S-F031.jsonl`. Logged pass or fail — the interesting number is the
*gap* between the two conditions and whether the normalized one creeps toward 0 as the
encoder or the fixture changes. The median-and-50% rule in `regression-perf/README.md`
means nothing on a figure that sits near zero and may be negative: read these two by eye
against the sign assertions above, and do not file an issue off the percentage alone.
cleanup: delete the run's whole output folder — all three files are scratch. The two
assets it reads are durable fixtures listed in "Fixtures" and are never deleted.
source: tester, model `opus` via provider `anthropic`, verified in #159 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`, job `089b1e2945d2` (7.7 s):
`raw_mux` warned at +0.8 dBFS and decoded `peak_dbfs: 0.776`, `balanced_mux` did not
warn and decoded `peak_dbfs: -0.626`, both 282 f / 24 fps / 960x544 / 11.75 s. The same
job is what finally settled M-F011's fourth bullet (the warning naming a muxed mp4, not
only a saved audio file) with a real MCP call rather than a description. Warning-count
bullet amended per #305's wontfix (bbe4adb) on 2026-09-22.

### S-F032 — a declared bound reaches a value inside a list entry, at the same three places
S-F028 pins a bound on a **top-level** variable. This is its list-entry twin, and it
exists because for a while the two were not the same rule: `constraint_errors`,
`apply_constraints` and the catalog all indexed the declared block by variable *name*
against the top-level arguments, so a `num_frames` sitting inside a `shots[]` entry was
invisible to every one of them (#145). The asymmetry was silent in the worst way — the
same 61 that `video-with-audio` refused for free, `dialogue-short` accepted, quoted a
plan for, and then failed on 138 s into the run with the weights already loaded. It is
worth pinning separately from S-F028 because a fix can pass that case and miss this one
entirely, and because `dialogue-short` is the one H3 template where per-shot length is
*meant* to vary, so it is where a frame count is most likely typed by hand.
The bound is matched to an entry field only when a step consumes it as `item:<name>` —
the constraint follows the value into the pipeline argument rather than following the
name into the JSON — so an entry key nothing reads is not silently bound. That is a
server-side rule this case cannot reach over MCP; it is named here so a reader knows the
match is not by spelling alone.
Free and instant: three discovery/validate calls, no run, no model load.
expected:
- **Refusal at the entry's own path.** `validate_workflow(name=
  "templates/minimax/dialogue-short", arguments={"shots": [{"name": "cold_open",
  "num_frames": 61, "prompt": "A short test line.", "references": []}]})` →
  `valid: false`, one error whose path is **`arguments.shots[0].num_frames`** — the
  index is part of the path, not a bare `num_frames` — with the same text S-F028
  demands: the accepted range (`124 to 345`), the rule (`17 * n + 5`), and what it
  rounds to (`73`). And **no `plan` in the answer**: a refused argument set must not
  come back with an estimate a caller could acknowledge.
- **Rounding is announced with the entry named.** The same call with `num_frames: 130`
  → `valid: true`, one warning **beginning `shots[0]:`** and naming `141`, and a `plan`
  present. A warning that names only `num_frames` has lost the half that tells a caller
  *which shot* changes length.
- **The index is real, not always zero.** Two entries, the first `num_frames: 141`
  (legal, on the grid) and the second `400` → `valid: false` with the error at
  **`arguments.shots[1].num_frames`**, saying "rounds up to 413 … must be at most 345",
  and **no warning for `shots[0]`**, which needs no rounding. A fix that reported every
  entry error against index 0, or that warned about a value already on the grid, passes
  the first two bullets and fails here.
- **The catalog carries the rule beside the field.** `get_workflow(name=
  "templates/minimax/dialogue-short", variables_only=true)` →
  `lists.shots.constraints.num_frames` present, terse
  (`"17*n+5, 124-345, rounds up"`), alongside `lists.shots.fields`. A caller reading
  what a `shots` entry carries reads the bound in the same place, rather than having to
  know to look at a top-level `constraints` block for a variable this template does not
  declare. This is the half that prevents the mistake instead of catching it.
cleanup: none — all three calls are free discovery/validate calls that write nothing.
source: tester, model `opus` via provider `anthropic`, verified in #145 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`. Don asked for this case by name
when approving the fix, as the list-entry variant of the existing #96 case. The third
bullet is mine: the implementer's hand-off proposed only the single-entry 61/130 pair,
which cannot tell a correct index from a hardcoded one.

### S-F033 — a file the server named can be named back to it, and a name it refuses says which character
A `for_each` step names its members `step@entry`, and the files it writes carry that `@`.
Those names come back from `job.manifest`, `list_gallery` and `get_gallery_metadata`
verbatim — but for a while feeding one back as an `output:` reference was rejected as
malformed (#162), so a whole class of files the server itself had named could not be
referenced by the language meant to consume them. Every list-driven template is affected,
since `for_each` is how they all work, and the workaround was a re-render or an
`upload_asset` round trip. The second half is the message: the refusal described a
correctly-spelled name and never mentioned `@`, so the cause was only findable by
bisecting against a sibling file.
This case is the round trip — *what the server wrote, the server accepts* — plus the two
edges of the widened grammar, so a future tightening of the pattern can't quietly take
`@` back out and can't loosen into traversal either. Cheap: one `pair_audio` mux (no
model load, a few seconds) and three free validate calls.
expected:
- **The round trip runs.** Take a `shot@<entry>` file name out of a list-driven run's
  `job.manifest` **verbatim**, pass it as `output:<that name>` to a `pair_audio` step's
  `video` (any audio from the same run as `audio`) → `validate_workflow` `valid: true`
  with a `plan`, and `run_workflow` **`succeeded`** with a file in the manifest. Do not
  retype or normalize the name; copying it from the manifest is the whole point. No GPU
  needed if a prior run's files are still on the box — pick any run whose files a
  `list_gallery` shows.
- **A malformed name is refused in the free call, and names the character.**
  `validate_workflow` on an inline workflow carrying `output:tpl/ru n/x.mp4` →
  `valid: false`, error path **`steps[0].task.arguments.video`**, message naming the
  offending character *and its position* (`' ' (position 6) is not a character this kind
  of name may contain`). Two separate failures if either half is missing: a name that can
  never resolve rejected only after the job is queued is a failure even though the job
  fails (`validate_workflow` passed this exact workflow before the fix), and a message
  that merely describes the correct form without naming its objection is the second.
- **`@` is mid-segment only.** A *leading* `@` — `.../intermediate/@shot.mp4` →
  `valid: false`, `segment '@shot.mp4' starts with '@', and every segment must start with
  a letter, digit or underscore`. The widening admitted one character inside a segment; it
  did not make `@` free.
- **Shape, not existence.** A well-formed `shot@no_such_entry...` name that is not on disk
  → `valid: true`. Deliberate, not a gap: whether a run id is still on disk depends on the
  workspace and on pruning, and validate resolves `arguments` against the workspace but
  not inline step references. Pinned so a later reader knows this boundary was chosen
  rather than missed — if it ever *should* become an existence check, that is a new issue,
  not a silent change to this bullet.
Traversal in the same reference form is SE-F028, in the security suite, where a boundary
escape belongs.
cleanup: delete the run directory the mux wrote (`delete_output` on the run id); the three
validate calls write nothing.
source: tester, model `opus` via provider `anthropic`, verified in #162 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-ep15` (round trip = job `2557decd9852`).
First two bullets proposed by the implementer in its hand-off; the third and fourth are
mine, from adjacent probes run at verification.

### S-F034 — a run that failed before writing any media is still deletable by its run name
S-F022 pins the `<workflow>/<run id>` delete form, but could only exercise it against
runs that *did* write media — its own source note says the failed-job-with-no-media case
"could not be provoked" from the consumer side, two attempts at a fast runtime failure
having succeeded instead. That is the one shape the form exists for: such a run leaves a
run directory containing only `manifest.json` and `workflow.json`, no media file names
it, and no other call can address it. If the form decays into "404 unless a media file
names it", those directories accumulate with no way to reach them and every later sweep
is wrong about what a workspace holds.
Two fast runtime failures that reliably write nothing are now known, and both are already
run by other cases — this case costs only the two deletes.
expected:
- **From a failed pipeline run.** Take S-F005(c)/S-F011's 383x383 SD 1.5 job (fails in
  ~2.5 s on "`height` and `width` have to be divisible by 8", `manifest: []`). Note its
  `run_id`, then `delete_output(name="<workflow id>/<run id>")` → `deleted: true` and
  `run_swept` equal to that run id.
- **From a failed task run.** Take S-F024 part 4's `resample_audio` job
  (`target_sample_rate` arriving as 0 through a **caller's `arguments` override**
  on a `variable:` reference — not baked into the workflow's own declared
  default, which is refused pre-flight instead, see part 4's note per #328;
  fails in ~1.3 s, `manifest: []`) and delete it the same way → `deleted: true`,
  `run_swept` the run id. Two different failure layers, because a form wired
  only into the pipeline path would pass the first bullet alone.
- **The delete is the assertion.** Either call answering "not found", or answering
  `deleted: true` with `run_swept: null`, is the finding — the second more quietly, since
  it says the directory was left behind.
- **And it actually went.** `list_workspaces()` reports this workspace's `usage.files`
  down by exactly 2 per swept run (the two sidecars). A `deleted: true` that does not move
  `usage` is the same finding as a refusal.
cleanup: none of its own — the case *is* the cleanup those two cases would otherwise have
to do, and it leaves nothing behind.
metrics: none. The timings above are context for recognising the failures, not figures to
log; S-P001 already tracks this box's SD 1.5 latency.
source: regression agent, model `opus` via provider `anthropic`, found on 2026-09-16 while
running S-F005 and S-F024 against dw 0.4.0-beta.4 on `lem`, workspace `regression-smoke`.
Both halves were run: job `e4e35b833f56` (383x383, run `20260916-004532-c9a15679`) and job
`2168c7a24782` (`target_sample_rate` 0, run `20260916-005157-1a7e0a0c`), each swept by its
`<workflow>/<run id>` name with `run_swept` matching, and the workspace measured back to
its pre-run 47 files / 43,135 bytes afterwards. Added at smoke level for the same reason
S-F014, S-F021 and S-F022 are here: it is the cleanup path every other case's `cleanup:`
line depends on being able to reach. Written as a new case rather than a bullet on S-F022,
which no agent may edit.

### S-F035 — a stored default that cannot resolve is caught by the free pre-flight, not by the run
`validate_workflow` is documented as the pre-flight you always run before
`run_workflow`, and its own description promises a valid answer says "whether it
covered your values or only the stored defaults". The filed bug (#166) was that it
only walked caller-supplied `arguments` for `asset:`/`prompt:`/`output:` existence
and never the workflow's declared `variables` defaults, so one workflow gave two
verdicts depending on whether the caller happened to restate a default —
`valid: true` bare, `valid: false` with the same value passed explicitly — and the
bare path deferred the failure until after the weights had loaded. The general
property, not the template: **a reference is checked wherever the effective value
comes from.**
expected:
- **Bare call reports the unresolvable default.** `validate_workflow(name=
  "templates/ltx2/reference-sheet")`, no arguments → `valid: false`, one error whose
  path is **`variables.reference_sheet`** (not `arguments.`, not a step path), its
  text naming the missing asset `reference_sheet.png` and the asset roots searched.
  `checked_arguments: []`. A `valid: true` here is the regression.
- **The default really is unresolvable.** `get_workflow(name=
  "templates/ltx2/reference-sheet", variables_only=true)` → `"reference_sheet":
  "asset:reference_sheet.png"`, and `list_assets()` reports no such asset in any
  root. If a later run of this suite finds the template's default changed or that
  asset present, the case's premise is gone — file an issue rather than editing it.
- **The two paths agree.** The same call with `arguments={"reference_sheet":
  "asset:reference_sheet.png"}` → `valid: false` too, same message, but at
  **`arguments.reference_sheet`**. Identical verdict, different path: the path is
  what tells a caller "you wrote a bad reference" from "you did not override a bad
  default", so a fix that reports both as `arguments.` is a partial fix.
- **No over-reporting — the override is what gets judged.** The same call with
  `arguments={"reference_sheet": "asset:<any real image in this workspace>"}` →
  `valid: true`, `checked_arguments: ["reference_sheet"]`, and a `plan`. This is the
  assertion that separates a correct fix from one that just fails any workflow
  carrying a placeholder default: the caller's value replaces the default before the
  check, and the workflow's *other* defaults (its `prompt:` and `constant:` ones)
  resolve and are not falsely flagged.
cleanup: none — all four calls are free discovery/validate calls that load nothing,
queue nothing and write nothing.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #166 on
2026-09-15 against dw 0.4.0-beta.4 on `lem` (fix a199d37 on `develop`). The
implementer proposed the first and fourth bullets in its hand-off comment; the
`variables.` vs `arguments.` path pair and the premise check are mine. At smoke
level because the pre-flight is what every other case's cost control rests on, and
because the failure mode is silent — a bare `validate_workflow` answering
`valid: true` looks exactly like a healthy one. Note the intended side effect the
implementer flagged: any catalog template shipping a placeholder `asset:` default
now answers `valid: false` on a bare call in a workspace without that file.

### S-F036 — an unwritable `result.content_type` is refused by the free pre-flight, not by the writer
S-F018 (and, for the objects it no longer covers itself, unit tests) pins that an
*unknown key* on a workflow object is an error. This is the
other half: a **known key carrying a value no writer can honour**. The filed bug (#168)
was that `result.content_type: "video"` — the obvious shorthand for `video/mp4` —
validated clean with a plan, then died at run time inside a writer the caller never
chose, as `TiffWriter.write() got an unexpected keyword argument 'fps'`: a message
naming neither the field, the value, nor the step. An unrecognised content type fell
through to the image writer instead of being an error. Same shape as #162 in a
different field. The general property: **the writer a `content_type` selects is
resolved at validate, and a value that selects nothing is refused there.** Cheap to
regress on and expensive to hit — this one cost only a `pair_audio` step, but the same
mistake on a step behind a multi-GB download is paid for in full before the message
arrives.
expected:
- **The bare word is refused, at its own path.** `validate_workflow` on a single-step
  document whose `result` is `{"subfolder": "final", "content_type": "video"}` →
  `valid: false`, exactly one error, path **`steps[0].result.content_type`**, message
  naming the value and what it wanted (`content_type wants a MIME type like
  'video/mp4' or 'image/png', not a bare word`). `valid: true` here is the regression;
  so is an error at a vaguer path, since the path is the whole point of catching it
  here rather than in the writer.
- **A well-formed but unwritable MIME type is refused too.** The same document with
  `content_type: "video/webm"` → `valid: false` at the same path, with a message
  distinguishing *this* objection from the bare-word one (`video is only written as
  'video/mp4'`). This is the assertion that the check consults the real writer
  registry rather than pattern-matching `type/subtype`; a fix that only rejects
  shapes without a slash passes the first bullet and fails here.
- **No over-tightening — the legitimate value still passes.** The same document with
  `content_type: "video/mp4"` → `valid: true`, a `plan` with a fingerprint, and no
  error at `steps[0].result.content_type`. A suite that only asserts refusals is
  satisfied by a check that refuses everything.
- **The check runs after substitution.** The same document with `content_type:
  "variable:ct"`, a declared `ct` variable, and `arguments: {"ct": "video"}` →
  `valid: false` with the bare-word message at `steps[0].result.content_type`. A value
  routed through `arguments` must not be able to walk past the pre-flight and reach
  the writer; a check that only reads literals in the stored document passes the first
  three bullets and leaves the original bug open on the path callers actually use.
- **Workspace-independent.** All four calls use `output:` references that need not
  exist (inline task arguments are not existence-checked), so this case carries no
  fixture and runs identically in any workspace. If a future run finds the positive
  bullet failing on a missing-reference error instead, that is a change in
  `validate_workflow`'s reference checking, not in this case's subject — file it
  rather than editing here.
cleanup: none — all four are free validate calls. Nothing loads, queues, or is written.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #168 on 2026-09-15
against dw 0.4.0-beta.4 on `lem` (fix 3db782e on `develop`), run in both `qa-ep15` and
`regression-smoke` to confirm the workspace-independence bullet. The implementer's
hand-off comment proposed the first and third bullets; the `video/webm` and
`variable:`-substitution bullets are mine, and the second closes the "how wide is the
fall-through" question the original issue listed as unprobed. At smoke level for the
same reason S-F010 and S-F035 are: the free pre-flight is what every other case's cost
control rests on, and a hole in it is silent — a `valid: true` with a plan looks
exactly like a healthy one right up until the run burns the budget.

### S-F038 — a media-less run directory is enumerable and deletable by name
S-F034 pins that a run which wrote no media can still be *deleted* by its
`<workflow>/<run id>` name — but only while you still hold that name from the job
you just ran. Nothing enumerated the ones already on disk, so a workspace could
report files in `list_workspaces().usage` that no listing call would name and no
cleanup could reach (#170: 44 such files in `regression-smoke`, 22 run directories
of `manifest.json` + `workflow.json`). `list_gallery(only_orphans=true)` is the
approved answer: a run directory with no file of a `MEDIA_KINDS` extension anywhere
beneath it. If it decays, every `cleanup:` line in this file goes back to being
unverifiable for the failure case, which is exactly the case that leaves litter.
Cheap — no generation, pure listing plus one delete of something already garbage.
expected:
- **Orphan mode enumerates.** `list_gallery(only_orphans=true, workspace=<a
  workspace holding at least one media-less run dir>)` returns a `runs` array of
  `{name, mtime}`, newest first, with `total` the full count and `limit`/`offset`
  paging it (`limit=3` → 3 entries, `total` still the full count). A workspace that
  has never been run answers `runs: []`, `total: 0`.
- **The two modes stay separate.** The same call without `only_orphans` returns
  `files` plus the `folders`/`subfolders` facets and **no** `runs` key; orphan mode
  returns `runs` and no `files`/facets. A response carrying both, or orphan mode
  quietly answering with the normal listing, is the finding.
- **It does not claim media-bearing runs.** In a workspace whose normal listing
  shows real media, the orphan listing must not contain the run directory that
  media sits under. A false positive here is worse than a false negative: the
  approved semantics make these directories deletable, so a run with output in it
  being listed as an orphan is a data-loss path, not a cosmetic bug.
- **Enumerable means actionable.** `delete_output(name=<one of the returned
  `runs[].name`s>, workspace=<same>)` → `deleted: true` with `run_swept` equal to
  that run id, and a repeat orphan listing has `total` down by one with that name
  absent. A name the listing hands back that `delete_output` will not take is the
  finding.
- Assert on the orphan listing's own `total`, not on `list_workspaces().usage` —
  #177 is open on `usage` not moving after a delete, and this case must not
  inherit that. S-F021 and S-F034 are where `usage` is held to account.
cleanup: it is cleanup — each run it deletes is litter by definition. Delete only
what the orphan listing named, one run is enough to prove the round trip, and never
in a workspace outside this suite's own.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #170 on
2026-09-16 against dw on `lem`, workspace `regression-smoke`. Proposed by the
implementer in its hand-off comment (the list→delete→re-list round trip); the mode
separation, the paging, the false-positive bullet and the "don't assert on `usage`"
note are mine, from what the verify session actually ran — 22 orphans enumerated
and matching the 44-file figure, `regression-model-specific` empty as a control, a
media-bearing `iron-bloom-frames/` run correctly absent from that workspace's 6
orphans, and `regr-seeded-image/20260912-212841-20cb7305` deleted with the listing
going 22 → 21. At smoke level for the same reason S-F022 and S-F034 are: it is part
of the cleanup path every other case depends on being able to reach.

### S-F041 — a schema-advertised `device` is accepted by a task that runs no model
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
source: tester, model `opus` via provider `anthropic`, verified in #185 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`, workspace `qa-verify-185` (using
`asset:uploads/qa-cast/room-bed.wav` / `asset:qa-cast/hal-voice.wav`; the case uses
the suite's own fixture bed instead): job `242d79ae47d0` (`resample_audio`,
`device: "cpu"`) succeeded in 2.9 s; job `1b501f78d203` (`gain_audio` `device:
"cuda"` + `resample_audio` `device: "cuda:0"`) succeeded in 0.6 s. The implementer's
hand-off also proposed pinning that a command whose `arguments` is a list (the
`previous_result` fan-out into `gather_inputs`) survives the new wrapper; that path is
not constructible from an inline workflow (the schema requires `arguments` to be an
object), so it belongs in the dw repo's pytest suite, not here.

### S-F042 — `gain_audio` changes only the addressed region, and clips a region past the end
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
source: tester, model `opus` via provider `anthropic`, verified in #187 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`, workspace `qa-verify-187`: job `6751bf30fdb4`
(seconds/−12 dB: seconds 5–7 peak −28.886 → −40.883, RMS −50.78 → −62.78, all others
identical; 1.1 s) and job `bc12d804d750` (frames/+6 dB past the end: duration still
19.666656 s, seconds 16–18 peak −28.886 → −22.884; 0.6 s). The implementer's
proposed sample-level assertions (scaled-by-linear-gain inside, bit-identical outside)
are the pytest form of the same properties and belong in the dw repo.

### S-F057 — the two sequence templates expose the same `match_levels` pair, and `assemble-and-score` passes `match_levels_dbfs` through to `concat_videos`
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
source: tester, model `opus` via provider `anthropic`, verified in #215 on 2026-09-18
against dw `develop` 5b6e3d9 on `lem`. The issue's own pair (ep21 shots, workspace
`qa-ep22`, job `c9609479cce0`): `video 1 rms -24.3 dBFS, gain +0.3 dB` / `video 2 rms
-20.6 dBFS, gain -3.4 dB`, both `held: false`, `warnings: []` — the clip-hold from
#214's job `a3f5e0b2fcbe` gone once the template accepted `-24`. The fixture pair
above is the shared `ep6-cold-open.mp4`/`ep3-shot2-reply.mp4` pair, chosen so this
case never touches `qa-ep22`; its exact gains were
not run in #215, so treat the ≈ figures as expectations to confirm on first run, not
measured values.

### S-F059 — `clear_memory` is refused while a job runs, frees VRAM when idle, and drops the step cache
Before #221 the worker's `clear_memory` command was reachable only from the REPL, so
an agent doing repeated runs against a live box had no way to reclaim VRAM short of an
out-of-band restart. The MCP tool wires it with two rules that matter: the worker queue
is FIFO, so a clear sent while a job is active is refused (409) rather than blocking
behind it or corrupting it; and it drops the step cache, so a seeded workflow reruns
instead of reusing. Cheap — three SD 1.5 runs (~5–9 s each warm) plus one that is
served from cache.
1. `run_workflow(workflow_path="templates/text-to-image",
   arguments={"prompt":"a red lighthouse on a cliff at dusk","num_images_per_prompt":1},
   acknowledged_cost=true)` and, without waiting, `clear_memory()`.
2. `wait_for_job` on that job to completion. Then `get_memory` (note
   `gpu_memory_allocated_mb`, `run_count`), then `clear_memory()` with the queue idle,
   then `get_health`.
3. `get_job_workflow(<step-1 job>)` and run its realized `workflow` (which carries the
   pinned `seed`) as `inline_workflow` twice, waiting each time.
4. `clear_memory()`, then the identical inline run a third time.
expected:
- Step 1: `clear_memory` returns an error *immediately* — "A job is running or queued -
  clearing memory out from under it would corrupt the run…" — and the job still
  finishes `succeeded` with its one `main` file. A clear that blocks for the job's
  duration, or a job that fails/cancels after the refused clear, is the regression.
- Step 2: `{"cleared": true, "info": {...}}` where `info` has the same shape as
  `get_memory`'s: `gpu_memory_allocated_mb` drops to single digits (from the hundreds a
  resident SD 1.5 holds) and `run_count` is 0. `get_health` afterwards is `status: ok`
  (`worker_alive` may be true or false — both are fine; the worker restarts on the
  next job).
- Step 3: the second seeded run's `main` manifest entry carries `reused: true`, names
  the first run's file, and finishes in ~1 s with a dozen events.
- Step 4: the third run has **no** `reused` marker, writes into its own new run
  directory, and takes as long as the first (a full denoise, ~45 events). A `reused:
  true` here means the clear did not drop the step cache.
cleanup: `delete_output` for all four runs (`templates/text-to-image/<run>/` and the
inline id's directory); or run the whole case in a throwaway workspace and delete it.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #221 on 2026-09-18
against dw `0.4.0-beta.6` (develop `a516b12`) on `lem`, workspace `qa-verify-221`:
jobs `642773b65e7f` (refused clear, finished 8.8 s), `73376205bccc` / `122b21c67cf4`
(`reused: true`, 0.7 s) / `6fd7f4eec716` (regenerated after clear, 5.4 s); idle clear
took `gpu_memory_allocated_mb` 497 → 8.1.

### S-F060 — `get_server_info` reports the runtime environment, consistent with `get_diffusers_state`
Before #222 the server-info tools named the device, the dw version and the diffusers
version, and nothing else about the environment — an agent choosing a CUDA-only option
(bitsandbytes, torch.compile) or reading a torch/driver-shaped failure had to guess what
was installed. `get_server_info` now carries a `runtime` block. Read-only, free.
1. `get_server_info()`.
2. `get_diffusers_state()`.
expected:
- Step 1: the response has a `runtime` object with string fields `python_version`,
  `torch_version`, `cuda_version`, `driver_version` and a `packages` object keyed by
  package name — at least `diffusers`, `transformers`, `accelerate`, `bitsandbytes`,
  `peft`, `safetensors`, `sentencepiece` on a CUDA server. Every value is a non-empty
  version string, none is null or an error message. (On an mps/cpu server
  `bitsandbytes` may be absent from `packages` — absent, not present-with-an-error; the
  cuda/driver fields may likewise be absent there.) A missing `runtime` block, or a
  package whose value is an error string rather than a version, is the regression.
- Step 2: `version` equals `runtime.packages.diffusers` from step 1 — the two tools
  must not disagree about which diffusers is loaded.
cleanup: none (read-only).
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #222 on 2026-09-18
against dw `0.4.0-beta.6` (develop `a516b12`) on `lem`: python 3.12.3, torch
2.14.0+cu130, cuda 13.0, driver 580.173.02, diffusers 0.41.0.dev0 on both tools.

### S-F061 — a list-driven run's `intermediate/…-shot@*.mp4` files, named as the manifest names them, are valid `shots` for `templates/assemble-and-score`
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
  were actually resolved, not skipped), plan of 7 steps.
- (b) → **`valid: false`**, single error at path **`arguments.shots[0]`** whose message
  names the missing name and the workspace's outputs directory (`Output
  's_f061/<run id>/final/open.mp4' not found under …/regression-smoke/outputs`). A
  `valid: true` here — the existence check dropped from argument references — is the
  regression that turns a bad `shots` entry back into a queued job that fails at the
  cut.
cleanup: delete the run (`delete_output` on `s_f061/<run id>`); the validate calls
write nothing. The three assets are shared fixtures — leave them.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #217 on 2026-09-18
against dw `0.4.0-beta.6` on `lem` (job `c5354b8a9c99`, workspace `regression-smoke`);
the same two arms were first confirmed against a real `music-video` H3 run
(`slow-light`, job `2e646456406a`) in that issue's verify comment. The implementer
proposed the positive arm in its hand-off; the negative arm and the fixture-based
stand-in for the H3 run are mine.

### S-F062 — `match_levels_dbfs` on both `concat_videos` and `dissolve_videos` names the -0.5 dBFS clip-hold ceiling and the `match_levels_held` warning
#214 was reopened as a false regression because the served `match_levels_dbfs`
description named only the `peak` default (−1 dBFS), which a workflow author read as
the ceiling a clipping shot is held at; #220 fixed the text, and the first fix reached
only `concat_videos` because `dissolve_videos` carries its own copy of the string
(their `match_levels` behaviour is shared, see S-F057). This locks in that both
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
source: tester, model `opus` via provider `anthropic`, verified in #220 on 2026-09-18
against dw `0.4.0-beta.6` on `lem`.

### S-F064 — every template that exposes `audio_bleed_ms` also exposes `audio_bleed_gain_db`, and `assemble-and-score` wires it into `concat_videos`
#199 added `audio_bleed_gain_db` to `concat_videos` to duck the time-reversed tail
bleed #198 established, but no template reached it: `templates/assemble-and-score`,
`templates/minimax/dialogue-short` and `templates/minimax/music-video` all exposed the
switch that creates the bleed (`audio_bleed_ms`) and not the one that sets its level,
so the shipped mitigation was unreachable except by copying a template inline — the
second recurrence of "task argument exists, no template exposes it" after #215 /
S-F057. Discovery calls only, all free; the task-level behaviour of the gain is #199's.
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
source: tester, model `opus` via provider `anthropic`, verified in #227 on 2026-09-18
against dw `develop` 5c03105 on `lem`. Not run to a generation in the verify: the
wiring is inspectable through the interface and the gain's effect on the join was
verified in #199; a run-level check belongs beside S-F057's step 4 if one is ever
wanted.

### S-F065 — the stock `generate-speech` template runs on its VITS defaults, and no longer declares `voice_preset`
#226 moved `templates/generate-speech`'s default `model_name` from `suno/bark-small`
to `facebook/mms-tts-eng` (VITS) and dropped the template's `voice_preset` variable
(a single-voice model refuses it, so keeping it would have made the template's own
defaults reject themselves). This is S-F037's property — **a stored template must run
as shipped, without a caller supplying anything** — re-stated against the new default;
S-F037's Bark-specific assertions (24 kHz, ~8 s, `v2/en_speaker_6`) are wrong by design
from `2d57b39` on and its retirement is proposed separately. The catalog's `audio`
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
source: tester, model `opus` via provider `anthropic`, verified in #226 on 2026-09-18
against dw 0.4.0-beta.6 (`develop` 2d57b39) on `lem`, jobs `0d6dfd28a919` and
`d1a35e432ebf` in a throwaway `qa-verify-226` workspace. The implementer's hand-off
proposed the default run and the audio checks; the `voice_preset` refusal and the
`text` override are mine.

### S-F066 — `generate_speech` reaches the model for every TTS family it drives, not just the template default
#232: transformers 5.17.0's `TextToAudioPipeline.preprocess` called
`BatchEncoding.to(dtype=...)`, which that class never accepted, so **every** model
`generate_speech` routes through `pipeline("text-to-audio", ...)` — SpeechT5, VITS,
Bark — died ~4 s in before any forward pass. #224 had scoped the breakage to Bark
("expendable") on the strength of #169, and S-F065 alone would have kept passing
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
metrics: none — S-F065 and S-P004 carry the audio timings; this case is about
which frame the failure lands in.
source: tester, model `opus` via provider `anthropic`, verified in #232 on 2026-09-18
against dw 0.4.0-beta.6 (`develop` 7f588c2, transformers 5.16.1) on `lem`, jobs
`ebc313a45891` (Bark) and `d0425f18a275` (SpeechT5) in workspace `qa-verify-223`.
The implementer's hand-off proposed the default-template run, which S-F065 already
holds; the non-default families and the failure-location check are mine.

### S-F068 — both sequence templates mark their `film` as `final`, so a `subfolder == "final"` consumer finds the deliverable
#235: `templates/assemble-and-score` and `templates/dissolve-between-shots` each have a
single saving step (`film`) and neither declared a `subfolder`, so the film landed at the
run-dir top level with `"subfolder": ""` — invisible to a consumer following `get_job`'s
own convention ("`final` is the deliverable") and inconsistent with the generating
templates, whose shots come out under `intermediate/` and `final/` (S-F061). The
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
  film.6-0.0.mp4` — the `final/` segment present in the name, not just the field. Every
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
source: tester, model `opus` via provider `anthropic`, verified in #235 on 2026-09-18
against dw `0.4.0-beta.6` on `lem` (develop `1acace7`), in workspace `qa-ep23` with the
issue's own ep21/ep4 shots: `dissolve-between-shots` job `f5e86f4ccfb1` →
`templates/dissolve-between-shots/20260919-010200-89f71598/final/dissolve-between-shots-film.6-0.0.mp4`,
`assemble-and-score` job `0664b1f20fff` →
`templates/assemble-and-score/20260919-010221-55c1580a/final/assemble-and-score-film.6-0.0.mp4`;
`list_gallery(subfolder="final")` returned exactly those two. The fixture pair above is
S-F057's so this case never touches `qa-ep23`; the `total_frames` values (248 for two
124-frame shots; 236 = 248 − 12 for the dissolve) keep the score slice inside the
~10.3 s bed so neither run warns.

### S-F069 — the no-seed warning is scoped to workflows that have something to seed
S-F016 checks the warning fires on an unseeded workflow with a pipeline-shaped step;
this is the other half. A workflow built only of `task` steps has no generative
randomness — regeneration is deterministic and free — so asking it for a `seed` is
noise, and a consumer that takes every warning seriously adds a meaningless key or
stops trusting the warning list (#247). Free and instant — no run.
expected: `validate_workflow` on an inline workflow with **no top-level `seed`**
whose only step is a task (`{"name": "qr", "task": {"command": "qr_code",
"arguments": {"qr_code_contents": "https://example.com"}}, "result":
{"content_type": "image/png", "file_base_name": "qr", "subfolder": "final"}}`)
→ `valid: true` and `warnings: []` — in particular no "sets no 'seed'" entry.
Control: the same call with that step replaced by a one-step `pipeline`
(`configuration.component_type: StableDiffusionPipeline`, any `model_name`, no seed)
→ `valid: true` **with** the S-F016 warning, so the gate did not simply switch the
warning off.
It becomes a **finding** if the task-only form warns about `seed`, if the pipeline
control stops warning (that is S-F016's finding too), or if `valid` flips to `false`
on either.
cleanup: none (read-only).
source: tester, verified in #247 on 2026-09-19 over MCP as model `opus` via
provider `anthropic` — the `qr_code` form validated with `warnings: []`; the
`StableDiffusionPipeline` form validated with the no-seed warning present.

### S-F070 — a text-only run is visible to `list_gallery`, and its `.txt` is the run's media
A run whose only output is a `.txt` (`transcribe-audio`, `expand-prompt`, any `text`-shape
workflow) used to be invisible to both `list_gallery` modes — not a file in the normal
listing, and not a "media-less" run in `only_orphans` either — so a sweep could only
delete it if it already knew the name from the job (#238). Cheap: `transcribe-audio`
on a short clip runs in seconds.
expected: `run_workflow(workflow_path="templates/transcribe-audio", arguments=
{"input_audio": "asset:qa-cast/hal-voice.wav"})` succeeds with a manifest of exactly one
`.txt`. Then `list_gallery()` lists that file with `kind: "text"`, a non-zero `size`, a
`url` carrying `?workspace=<this workspace>`, and `templates/transcribe-audio` in
`folders`; `list_gallery(only_orphans=true)` → `runs: []` (the run has a real file);
`get_output_text(<name>)` returns the transcript. Then `delete_output(<name>)` →
`deleted: true` **and** `run_swept: <run id>` — the `.txt` counts as the run's last media
file, so the run directory goes with it — and both `list_gallery()` and
`list_gallery(only_orphans=true)` are empty afterwards.
It becomes a **finding** if the `.txt` is absent from the normal listing, appears with a
`kind` other than `text`, if the run shows up under `only_orphans` while its file
exists, or if `delete_output` removes the file without `run_swept` (leaving a
bookkeeping-only directory the pre-fix sweep could not see).
cleanup: the `delete_output` above is the cleanup; if it did not sweep, `delete_output`
on the run name `templates/transcribe-audio/<run id>`.
source: tester, verified in #238 on 2026-09-19 over MCP as model `opus` via
provider `anthropic` — fresh run in `qa-verify-238`: listed as `kind: "text"`, `size: 48`;
`only_orphans` empty; `delete_output` reported `run_swept`.

### S-F071 — `frame_grid` tiles a clip into one contact sheet, and clamps `count` to the clip
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
source: tester, verified in #245 on 2026-09-19 over MCP as model `opus` via provider
`anthropic` — defaults `[1280, 543]` in 1.3 s, labels `00:00.0` → `00:05.1`; `count: 200`
clamped to a 16×8 grid at `[1280, 360]`; `count: 0` refused at validate.

### S-F072 — `pair_audio` `fit: "video"` warns in both directions, and stays quiet on an exact fit
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
source: tester, verified in #246 on 2026-09-20 over MCP as model `opus` via provider
`anthropic` — jobs `46ea12726874` (trim, 14.50 s), `3f70d7aac7bb` (pad, 13.19 s),
`fd1b43c9c80e` (exact, no fit warning).

### S-F073 — `wait_for_job` advertises its cap in the tool description, and the reply's clamp agrees with it
The per-call cap on `wait_for_job` is a deployment setting (#248: `DW_MCP_MAX_WAIT_SECONDS`,
default 55), and an agent budgets its polls by it — one call per cap-seconds of the job. The
tool description interpolates the live value so a caller reads the real cap, not a number
baked into prose; the reply must then clamp to the same value. No model, no job queued:
this runs against any already-finished job (`list_jobs(status="succeeded", limit=1)`), which
returns immediately but still fills the timeout fields.
expected:
- The `wait_for_job` tool description (as the MCP client loads it) states a numeric cap:
  "One call blocks for at most `<cap>` seconds … budget roughly one call per `<cap>`s of the
  job". Note `<cap>` — it is the deployment's, not necessarily 55.
- `wait_for_job(job_id=<finished>, timeout_seconds=600)` (or any value above `<cap>`) →
  `timeout_requested_seconds: 600.0`, `timeout_applied_seconds` **equal to `<cap>`**,
  `timeout_capped: true`, `still_running: false`.
- `wait_for_job(job_id=<finished>, timeout_seconds=<n>)` with `<n>` below `<cap>` (30 when
  the cap is 55) → `timeout_applied_seconds: <n>`, `timeout_capped: false`.
It becomes a **finding** if the description carries no numeric cap, if the clamped
`timeout_applied_seconds` differs from the described cap, if `timeout_capped` is wrong for
either arm, or if any of the three timeout fields is missing from the reply. A cap other
than 55 is not a finding on its own — that is the deployment's choice — as long as the
description and the reply agree on it.
cleanup: none — nothing is created.
source: tester, verified in #248 on 2026-09-20 over MCP as model `opus` via provider
`anthropic` — description read 55.0, `timeout_seconds=600` on job `fd1b43c9c80e` applied
55.0/capped true, `timeout_seconds=30` applied 30.0/capped false.

### S-F074 — `list_assets` and `list_workspaces` are compact by default, and `detail=true` restores the full entry
Both listings are called dozens of times per session and every byte stays in context (#101,
#249). The default reply carries only what an agent needs to pick an entry; the rest is
behind `detail=true`. What a listing *reveals* — the library roots, their `writable` flags,
`shadowed` — does not change with `detail`, only the per-entry bulk. No model, nothing
created: runs against whatever the workspace already holds (an empty `assets` list still
exercises the top-level fields).
expected:
- `list_workspaces()` → every `workspaces[]` entry has exactly the keys `name`, `default`,
  `usage` (`usage` = `{files, bytes}`); a top-level `note` names `detail=True`;
  `workspace_root`, `default`, `current` present.
- `list_workspaces(detail=true)` → every entry additionally has `root`, `workflows`,
  `assets`, `outputs`, `prompts`, `common_assets`; **no** top-level `note`.
- `list_assets()` → every `assets[]` (and `shadowed[]`) entry has exactly the keys `name`,
  `reference`, `kind`, `size`, `origin`; a top-level `note` names `detail=True`; `asset_dir`,
  `asset_dirs`, `folders`, `libraries` (each with `origin`/`dir`/`writable`) and `shadowed`
  all present.
- `list_assets(detail=true)` → every entry additionally has `folder`, `mtime`, `url`; **no**
  top-level `note`.
It becomes a **finding** if a compact entry carries any of the detail-only keys, if a detail
entry lacks one, if the `note` is missing from the compact reply or present on the detail
reply, or if any top-level field listed above disappears in either mode.
cleanup: none — nothing is created.
source: tester, verified in #249 on 2026-09-19 over MCP as model `opus` via provider
`anthropic` — 19 workspaces / 47 assets in `default`, both modes exactly as above.

### S-F075 — a partial plan estimate names what was unpriced, and an all-priced one names nothing
`validate_workflow`'s `plan.estimate` sums curated `cost` blocks across a composed workflow
(#242); when some contributor has none, `partial: true` alone cannot tell a caller whether
the gap is a trivial step or a 12-shot loop. `unpriced` (#252) names each contributor: the
parent by its own `id` when the parent's own steps carry no `cost`, each composed child by
its `workflow.path`. Since #268 a parent with no `cost` whose *every* step is a `workflow`
step is pure composition and inherits its child's estimate instead of being named — the
parent is only unpriced when it has a task step of its own that nobody costed. Free, no
model, no job — four inline `validate_workflow` calls against stock templates whose cost
state is fixed: `templates/ltx2/text-to-video` has a curated cost (2.2 min on cuda at the
time of writing; it has moved once already, so read the current figure from
`list_workflows(shape="shot")` rather than the numbers here), `templates/ltx2/extend-clip`
has none. Each inline workflow is one step, `{"name": "clip", "workflow": {"path":
<template>, "arguments": {"prompt": "variable:prompt"}}, "result": {"content_type":
"video/mp4", "subfolder": "final"}}`, with `"variables": {"prompt": "a lighthouse at
dusk"}`, except where an arm says to add a second step.
expected:
- `id: "qa-252-unpriced-parent"`, **no** `cost`, composing `templates/ltx2/text-to-video`
  → `valid: true`; `estimate.partial: false`; `estimate.unpriced == []` (present and
  empty); `basis: "observed"` (or `"catalog"` on a box that has never run the child) —
  pure composition inherits the child's figure, and the parent is not named (#268).
- `id: "qa-252-unpriced-parent"` again, still **no** `cost`, with a second step after
  `clip`: `{"name": "sheet", "task": {"command": "frame_grid", "arguments": {"video":
  "previous_result:clip"}}, "result": {"content_type": "image/png", "subfolder": "intermediate"}}`
  → `valid: true`; `partial: true`; `unpriced == ["qa-252-unpriced-parent"]` — the parent
  alone, named for its own uncosted task step, since the child is priced; `minutes` is
  still the child's figure, not null. (The #242 shape #268 explicitly preserves; the
  tester's `qa-268-mixed` check there answered `basis: "unknown"` for it.)
- `id: "qa-252-priced-parent"`, `"cost": [{"device": "cuda", "name": "RTX 3090",
  "vram_gb": 24, "minutes": 0.5}]`, composing `templates/ltx2/extend-clip` → `valid: true`;
  `partial: true`; `unpriced == ["templates/ltx2/extend-clip"]` — the child alone, by path;
  `basis: "catalog"`, `minutes: 0.5`.
- `id: "qa-252-all-priced"`, the same `cost` block, composing `templates/ltx2/text-to-video`
  → `valid: true`; `partial: false`; `unpriced == []` (present and empty, not absent);
  `minutes` is the parent's 0.5 plus the child's current catalog figure.
It becomes a **finding** if `unpriced` is missing from any of the four replies, if it
names a priced contributor or omits an unpriced one, or if `partial` disagrees with whether
`unpriced` is empty. A change in the templates' curated costs (text-to-video losing its
block, extend-clip gaining one) moves which arm names what — re-check `list_workflows
(shape="shot")` `cost` before calling that a finding.
cleanup: none — nothing is created.
source: tester, verified in #252 on 2026-09-19 over MCP as model `opus` via provider
`anthropic` — the original three replies exactly as above. Arm 1 was rewritten and the
mixed-parent arm added in #307 (2026-09-21) after #268 made a pure-composition parent
inherit its child's history: the regression agent's run that day answered `observed`,
2.2 min, 13 runs, `partial: false`, `unpriced: []` for the one-step parent, and arms 2
and 3 as written (text-to-video's curated figure had moved from 1.8 to 2.2).

### S-F076 — `plan.estimate.cached_minutes` accounts for `cached_steps`
Before #255 `plan.estimate.minutes` was the whole-workflow observed time regardless of
`plan.cached_steps` — 14.2 min quoted for a run that would touch no GPU at all — and the
consumer had no field to correct it from. The fix adds `cached_minutes`: the cost of the
plan *after* the cached steps are subtracted, present on every estimate shape (`null` when
`minutes` is). Cheap — two SD 1.5 jobs, one of them half-served from the step cache.
0. If `qa-s076-two-step` is already saved in the workspace (an earlier run that stopped
   before its cleanup), `delete_workflow` it first. Since #312 the cost history is kept
   per `(workspace, workflow_name)` and `delete_workflow` purges it, so a leftover — or
   rows from before #312, which is what #330 was — is the only way step 2 reads
   `observed`; deleting first makes step 2 cold by construction.
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
source: tester, verified in #255 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, workspace `qa-v255` (workflow there was named `qa-v255-two-step`): jobs
`0769bf82b652` (cold, 17.4 s) / `604ba5707167` (`first` reused, 4.1 s);
`cached_minutes` 0.0 → 0.1 → 0.0 across steps 3, 4, and a re-validate after step 5.

### S-F077 — a seeded `generate_speech` is reproducible, and a near-silent audio deliverable is warned about
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
source: tester, verified in #261 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, workspace `qa-verify-261`: jobs `753b45752457` (cold) / `6040f3b8c826` /
`bccfb02a4524` identical to full float precision; `6c7c59722d33` was the cache-served
resubmission; `44bdcd423ffd` warned at -75.34 dBFS.

### S-F078 — a declared `cost_driver` overridden off its measured value drops the quote to `unknown`
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
source: tester, verified in #267 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: steps 1 and 4 answered `observed`, 2.5 min, 12 runs on the RTX 3090; steps 2
and 3 answered `unknown` with `minutes: null`. Step 2's expectation widened to admit
`observed`+`low_confidence` per #331 (2026-09-22, model `sonnet` via provider
`anthropic`) — #301/#319's small-n bucketing now legitimately answers `observed` for a
driver value with enough of its own runs, same pattern already seen for S-F030.

### S-F079 — a failed job keeps the phase it died in, frozen at `finished_at`
#269: `progress` went `null` the moment a job left `running`, so the only way to learn which
phase a failure hit was reading a ~40-frame traceback — when the job's own `phase` events
already held the answer. `get_job` and `wait_for_job` now keep the last-known phase on a
`failed` job, with `seconds_in_phase` stopped at `finished_at` rather than still counting.
Cheap — two deliberate failures on SD 1.5, ~6 s and ~2 s, no successful run needed.
1. Take the stored `templates/text-to-image` definition (`get_workflow`), and run it inline
   with the step's `arguments` widened to `height: 8192, width: 8192, num_inference_steps: 3`
   (`acknowledged_cost` bound to the validate plan; `minutes` is `null` for an inline
   workflow with no history). On a 24 GB card this CUDA-OOMs in the first UNet forward, a
   second or two after the `generating` phase event.
2. `wait_for_job`, then `get_job` on it at least a few seconds later.
3. Same definition with `model_name` pointing at a repo that does not exist (e.g.
   `stable-diffusion-v1-5/does-not-exist-qa269`; validate lists it under `downloads_required`
   and the bound acknowledgement must name it). Fails in the load, offline.
4. `wait_for_job` on that one.
expected:
- Step 2: `status: "failed"`, `manifest: []`, and `progress` **present** on both calls:
  `step: "main"`, `phase: "generating"`, `phase_detail` naming the SD 1.5 repo,
  `denoise_step: null`. `seconds_in_phase` equals the gap between the `phase: generating`
  event's `at` and the `job_status: failed` event's `at` in `get_job_events` (about 1.5 s),
  and reads the **same** value on the later `get_job` — it is frozen, not elapsed-since.
- Step 4: `status: "failed"` with `progress.phase: "loading"` and `phase_detail` naming the
  bogus repo — the last-known phase generally, not `generating` hard-wired.
- On a GPU too large to OOM at 8192², or where the failure lands elsewhere, the assertion is
  the same: whatever phase the last `phase` event named is what `progress.phase` reads, and
  `progress` is never `null` on a job that emitted at least one phase event.
It becomes a **finding** if either failed job answers `progress: null`, if the phase differs
from the last `phase` event in `get_job_events`, or if `seconds_in_phase` grows between the
`wait_for_job` reply and a later `get_job`. A `historical: true` job with `event_count: 0`
(one from before a server restart) showing no `progress` is not a finding — there is nothing
to derive it from.
cleanup: `delete_output(name="<workflow id>/<run id>")` for both runs (each leaves only the
two sidecars, S-F034's shape), or delete the case's workspace.
metrics: none.
source: tester, verified in #269 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, dw 0.4.0-beta.6 on `lem`: job `19fa559e8158` OOM'd at `at: 6.3` after
`generating` at `at: 4.8`, `seconds_in_phase: 1.4` on both `wait_for_job` and a later
`get_job`; job `c4dd43dd0787` failed loading with `progress.phase: "loading"`,
`seconds_in_phase: 0.9`. Case proposed by the implementer in its hand-off comment.

### S-F080 — `get_output_frames` reads an `asset:` video by seam and by moment, with sound
`get_output_frames` is the only way to *see* a cut over MCP (#245), and its `seams` and
`hear` selectors are what a cut is checked with; neither had a case. Free — no job, two
calls on the fixture `asset:qa-cast/ep25-episode.mp4` (360 frames, second shot from frame
236). Pass `workspace="regression-smoke"` on both.
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
source: tester, found while running TESTER_TASK.agent.md (ep25, 2026-09-21) over MCP as model
`opus` via provider `anthropic`, dw 0.4.0-beta.6 on `lem`: seam 1 reported `frame 236 @ 9.83s
difference: 5.06 [256x72]`; moments `frame 242 @ 10.08s` / `frame 358 @ 14.92s` with 125 KB
and 73 KB wavs.

### S-F081 — the envelope has `ceil(duration)` bins: a real partial tail stands alone, a whole-second track gets no phantom bin
The tool says the envelope is "what says whether a shot is still sounding at its last
frame". That reading depends on the bin count: #277 was one *extra* near-silent bin on a
15.0 s track (codec padding decoded past the reported duration, read as a hole at the
tail), and #278 was the over-correction — every sub-second tail folded into the previous
bin, so a 0.667 s fade on a 19.667 s track was averaged into a full-level second and
invisible. Free — two read-only calls on fixtures. Pass `workspace="regression-smoke"`.
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
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #278 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, dw on `lem` at develop ffd7455: ep11-bed → 20 bins, last `rms -64.31 /
peak -50.22`; ep25-episode → 15 bins, last `rms -26.27`. Also observed then:
`ep21-shot1-receipt.mp4` 5.167 s → 6 bins, `ep15-song.mp3` 30.023 s → 31 bins.

### S-F082 — the step cache's workspace scoping is documented, and a plan names the workspace it was evaluated in
#279: `validate_workflow(workspace=A)` reported `cached_steps: 1` and `workspace=B` reported
`0` for the same fingerprint, and nothing on the consumer surface said the step cache is
per workspace, nor which workspace a plan had been evaluated against. The fix is two guide
paragraphs plus `plan.workspace` / `plan.output_dir`. Free — three read-only calls, no run.
1. `get_guide(name="workflows", section="Seeds")`.
2. `get_guide(name="workspaces", section="Runs")`.
3. `validate_workflow(name="templates/dissolve-between-shots", workspace="regression-smoke",
   arguments={"shots": ["asset:qa-cast/ep6-cold-open.mp4",
   "asset:qa-cast/ep3-shot2-reply.mp4", "asset:qa-cast/ep13-episode.mp4"], "score":
   "asset:qa-cast/ep20-score.wav"})`. The arguments matter: a `plan` is only returned on
   `valid: true`, and the template's stored defaults name `asset:shot_1.mp4` etc., which
   do not exist in `regression-smoke` (#308).
expected:
- Step 1's `content` states that the step cache is scoped to the output directory a run
  writes into — the pinned workspace's own `outputs/` on `dw.serve` — that two workspaces
  holding a matching run do not share an entry, that `plan.cached_steps` answers for the
  pinned workspace only, and that deleting a workspace drops its entries.
- Step 2's `content` says the same from the workspace side: the cache is validated against
  the output *root*, is per workspace, and deleting a workspace drops its entries along with
  its `outputs/`.
- Step 3 answers `valid: true` and its `plan` carries `workspace: "regression-smoke"` and
  an `output_dir` ending in `/regression-smoke/outputs`, so a `cached_steps` value can
  always be read against the workspace it was computed for.
It is a **finding** if either section no longer mentions the workspace at all, or if `plan`
has no `workspace` / `output_dir`.
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #279 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: both guide sections carried the text; `validate_workflow` pinned to `qa-ep26`
and `qa-ep25` returned `plan.workspace` / `plan.output_dir` for each. (Whether an entry
survives a server restart is #281, not this case.) Step 3 was rebound to the
`regression-smoke` fixtures in #308 (2026-09-21): the original argument-free call is
`valid: false` there and so carries no `plan`; the regression agent's run with these
arguments answered `plan.workspace: "regression-smoke"`.

### S-F083 — the `get_gallery_metadata` docstring's tasks-guide cross-reference resolves through `get_guide`
#282: the tool description told the reader to "see \"Headroom and clipping warnings\" in
the tasks guide", but `get_guide` indexes only top-level headings, so that name errored
and the thresholds paragraph was unreachable from the cross-reference. The fix repointed
the docstring at a section that resolves. Free — one schema read and one guide read.
1. Read the `get_gallery_metadata` tool description as served (the deferred-tool schema,
   e.g. via `ToolSearch select:mcp__dw__get_gallery_metadata`); note the guide name and
   section it names for the `-0.5` / `0.0` dBFS thresholds.
2. `get_guide(name="tasks", section=<that section>)` — currently
   `section="Video Processing"`, with `normalize_audio` as the sub-section to look for.
expected:
- Step 1's description names a guide *and* a section (not just a bold paragraph title).
- Step 2 resolves (no `has no section` error) and its `content` contains the string
  `Headroom and clipping warnings` together with both threshold names `audio_no_headroom`
  and `audio_clipped`.
It is a **finding** if step 2 errors, or resolves to content that no longer carries the
thresholds paragraph — either way the docstring is pointing at something a reader can't
fetch. If the docstring's target moves to another section that does resolve and does
carry the paragraph, that is a pass, not a finding.
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #282 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: the description named `normalize_audio` in "Video Processing";
`get_guide(name="tasks", section="Video Processing")` returned the `### normalize_audio`
sub-section with the `**Headroom and clipping warnings.**` paragraph and both warning
names; the old title still errors, by design (sub-headings are not indexed).

### S-F084 — the `workflow_end` event's manifest names files exactly as `get_job` and `step_end` do
#284: the last content event of a finished job, `workflow_end`, carried a `manifest[]`
whose `files` were absolute paths under the workspace's `outputs/` root, while `step_end`
in the same stream and `get_job`'s manifest gave the gallery-relative
`<workflow>/<run id>/<subfolder>/<file>` — so a consumer reading the final manifest off
the event stream had a name no output-side tool accepted. Cheap: one CPU-only inline run.
1. `run_workflow(inline_workflow=..., acknowledged_cost=true)` with three steps —
   `gather_images` of the HF `robot.png` URL, then `canny` with
   `result: {content_type: "image/jpeg", subfolder: "final"}`, then `crop_square` with
   `subfolder: "intermediate"`, both over `previous_result:input_image` — and
   `wait_for_job` to `succeeded`.
2. `get_job_events(job_id, after=<last_seq minus ~10>)` and find the `workflow_end` event;
   `get_job(job_id)` for its `manifest`.
3. `get_gallery_metadata(name=<one workflow_end manifest file>)`.
expected:
- The `workflow_end` event's `manifest` is identical, entry for entry (`step`, `files`,
  `subfolder`), to `get_job`'s `manifest`, and every `files` entry is gallery-relative:
  starts with the workflow id, no leading `/`, no `outputs/` prefix, and matches the same
  step's `step_end.files` earlier in the stream. Both the `final` and the `intermediate`
  subfolder appear, and the `gather_images` step has `files: []` in both places.
- Step 3 resolves with `source: "output"` and the job's id — the name is usable as-is.
It is a **finding** if any `workflow_end` file differs from `get_job`'s for the same step,
carries a leading `/` or a directory outside `<workflow>/<run id>/`, or step 3 fails to
resolve the name.
cleanup: delete the run's outputs by run name (`delete_output`), as S-F022 does.
metrics: none.
source: tester, verified in #284 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `ed6d2fbaeb7e` — `workflow_end.manifest`, `get_job.manifest` and the two
`step_end.files` all read `qa284_canny/20260921-071603-082a2b15/{final,intermediate}/…`,
and `get_gallery_metadata` on the intermediate name returned `source: output`, job
`ed6d2fbaeb7e`.

### S-F085 — a `task.command` the engine does not register is refused by the free pre-flight
#285: `validate_workflow` said `valid: true` on a step whose `task.command` named nothing
the engine registers (the shipped `templates/image-processors` carried a `face_detector`
step), so the run did nine steps' worth of work before dying with the engine's own
"Unknown task command". The per-argument checks (S-F010) only ran once the command
resolved; a command that did not exist at all fell through silently. Free: two validate
calls, nothing runs.
1. `validate_workflow(inline_workflow={"id": "regression-bad-command", "steps": [{"name":
   "bad", "task": {"command": "nonexistent_processor", "arguments": {"image": "x"}}}]})`.
2. `validate_workflow(name="templates/image-processors")`.
expected:
- Step 1 is `valid: false` with exactly one error at `steps[0].task.command` whose message
  names `nonexistent_processor` and says it is not a registered task command — the
  refusal lands at the command, before any missing/unknown-argument complaint about
  `image`.
- Step 2 is `valid: true`, and `plan.steps` equals the number of steps `get_workflow`
  reports for the template (25 as of #285) — the shipped template names only commands
  the engine registers.
It is a **finding** if step 1 comes back `valid: true`, or reports only argument-level
errors with no error at `steps[0].task.command`, or if step 2 reports any step's
`task.command` as unregistered.
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #285 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: step 1 returned `'nonexistent_processor' is not a registered task command.
This step would fail at run time with the engine's own "Unknown task command" error` at
`steps[0].task.command`; step 2 returned `valid: true`, `plan.steps: 25`, and the
template then ran to `succeeded` 25/25 (job `a0e10ced3bad`).

### S-F086 — `dissolve_videos` resamples shots at different sample rates instead of failing
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
source: tester, verified in #287 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `47f27a3d566e` succeeded in 5 s with the warning quoted above; output read
back as 394 frames, 44100 Hz stereo. The same session confirmed `sample_rate: 32000` pins
the target (job `370442220fe7`) and that two 32 kHz shots draw no warning.

### S-F087 — a companion argument that renders `seam_fade_ms` or `audio_bleed_gain_db` inert is warned about at validate
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
source: tester, verified in #288 on 2026-09-21 over MCP as model `opus` via provider
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

### S-F088 — `get_job.event_count` on a historical job equals what `get_job_events` serves
#289: a job rehydrated from history (`historical: true` — after a server restart, or once
it aged out of memory) reported `event_count: 0` while `get_job_events` paged through its
full persisted tail, so a consumer reading the count concluded the events were lost with
the process and never looked for the warnings-with-measurements that live there. Live
jobs were never affected, so a case that only checks the job it just ran would pass
through the bug. Free: no run — any job already on the server does.
1. `list_jobs(limit=20, status="succeeded")` and pick one with `historical: true`
   (any workspace; the server keeps history from before this session, so there is
   always one). Prefer one with a multi-step workflow so the count is not trivial.
2. `get_job(job_id)` — note `event_count` and `historical`.
3. `get_job_events(job_id, after=<event_count - 3>, limit=50)` — the last few events.
4. Also run any small job (a one-step `slice_audio` or `gain_audio` over a fixture is
   enough), `wait_for_job` to `succeeded`, and repeat steps 2-3 on it while it is still
   live (`historical: false`).
expected:
- In step 2 `historical` is `true` and `event_count` is a positive integer, not `0` or
  `null`.
- Step 3 returns exactly the events with `seq` from `event_count - 2` through
  `event_count - 1`, the last being `job_status: succeeded`, `last_seq == event_count - 1`,
  `truncated: false` — i.e. the count is the number of events on record, no more and no
  less.
- The live job in step 4 satisfies the same identity.
It is a **finding** if a historical job reports `event_count: 0` while `get_job_events`
serves any event, if `last_seq + 1 != event_count` on either job, or if a live and a
historical job disagree on what `event_count` means.
cleanup: delete the step-4 run's outputs by run name (`delete_output`); the historical job
is someone else's and is left alone.
metrics: none.
source: tester, verified in #289 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: four historical jobs across `qa-ep30` and `qa-verify-285` — `22932ad7d1b6`
(96 events), `d95ff1b61ed2` (95), `0eebb7f67ece` (34), `a0e10ced3bad` (189) — each
reported `event_count` exactly `last_seq + 1` of its final `get_job_events` page. Before
the fix the first of these read `event_count: 0`. The over-200-event persisted-cap
variant the implementer proposed is not covered here: no such job existed to confirm it.

### S-F089 — `concat_videos` bleed with `audio_bleed_gain_db` fills the seam hole, and the inert `crossfade_ms` is warned about
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
source: tester, found while running TESTER_TASK.agent.md (ep32) on 2026-09-21 over MCP
as model `opus` via provider `anthropic`: job `310af1018ea1` in `qa-ep32`, 7.5 s; seam
bin −53.2 rms in control vs −32.0 in treatment, all other bins within 0.06 dB; both
clip-held 0.1 dB short; `bleed_join` recommended `audio_bleed_ms: 0`. The
`audio_bleed_gain_db`-with-`audio_bleed_ms: 0` combination is deliberately *not* in
this case: it draws no warning today (#290).

### S-F091 — `loop_audio` shortening a bed to `target_frames` is sample-faithful, not faded
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
source: tester, found while running TESTER_TASK.agent.md (ep33, `qa-ep33`, job
`dfd9cc5a3244`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`: tails
−60.48 vs −60.50 dBFS mean, peak −38.01 on both, `bed-loop` 9.333 s / 32 kHz / mono,
peak equal to the source asset's (−28.89).

### S-F092 — a `match_levels_dbfs` that an unset `match_levels` makes inert is warned about at validate, on both join commands
#291: `concat_videos` and `dissolve_videos` only call the level matcher when
`match_levels` is `"rms"` or `"peak"` (off by default), so a caller who passes only the
`match_levels_dbfs` target has stated an intent the engine silently dropped — the third
"modifier without its enabler" pair on these commands after S-F087's #288 and #290 arms.
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
source: tester, verified in #291 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: in `qa-ep33` the two target-only steps and the explicit-null step each warned
`Step '<name>': 'match_levels_dbfs' has no effect when 'match_levels' is unset - pass
"rms" or "peak" for the target to apply.`; the `rms`, `peak` and no-target steps were
silent.

### S-F093 — `mix_audio` gains are linear multipliers applied as given: no hidden normalization, no sum-scaling
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
source: tester, found while running TESTER_TASK.agent.md (ep34, `qa-ep34`, job
`a4433db88e90`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`:
`solo-unity` −1.012 / −19.81, `solo-half` −7.033 / −25.83, `bed-x12` −7.302 from an
asset peak of −28.886, `two-slots` identical to `solo-unity` to the third decimal;
every output 9.333 s / 32 kHz.

### S-F094 — a negative `mix_audio` gain is refused by the free pre-flight, and a dB-shaped gain (3 or above) is warned about as a not-dB value
`mix_audio.gains` is the engine's one level control that is a plain multiplier rather than
dB, so `-12` typed by habit is a phase-inverted 12x boost — it used to validate, run and
succeed with nothing in `warnings` or the events (#292). The domain check is the same
element-wise `non_negative` mechanism S-F024 exercises on scalars, reached through a list;
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
source: tester, verified in #292 on 2026-09-21 over MCP as model `opus` via provider
`anthropic` (job `b3491e7c8b92` in `qa-ep34`; 3.7 s end to end). Title reworded per #321
on 2026-09-22: #306 raised `mix_audio_gain_not_db`'s threshold from `> 1.0` to `>= 3.0`
(`GAIN_LOOKS_LIKE_DB_ABOVE`, commit `05cfbfd`), so a gain of 1.8 no longer warns; this
case's own gain of 12 is unaffected. The threshold's other side (1.8 silent, 12 warns) is
pinned by S-F102.

### S-F095 — `gain_audio` ducks exactly the second-based region it was given, by exactly the dB it was given, and nothing outside it
`gain_audio` is the one region-scoped level tool (a duck under a line, a boost on a sting),
and its failure modes — the gain applied to the whole track, the region converted with the
wrong rate or channel layout, dB applied as a multiplier — all still "succeed". A consumer
that cannot listen only catches them by measuring the envelope bin by bin, so this pins the
arithmetic on one shot with a known, flat middle. Seeded, one job, seconds, one asset:
1. `get_gallery_metadata(name="asset:qa-cast/ep31-shot1-return.mp4", envelope=true)` —
   the source (5.167 s, 32 kHz stereo, 124 f @ 24 fps).
2. `run_workflow(workspace=<suite workspace>, inline_workflow={"id":
   "regression-gain-region", "seed": 1, "steps": [
   {"name": "duck_middle", "task": {"command": "gain_audio", "arguments":
   {"audio": "asset:qa-cast/ep31-shot1-return.mp4", "gain_db": -12, "start_seconds": 2.0,
   "duration_seconds": 1.0}},
   "result": {"content_type": "audio/wav", "subfolder": "final", "file_base_name": "gain-region"}}]},
   acknowledged_cost=<bound from validate>)`, `wait_for_job`, then
   `get_gallery_metadata(envelope=true)` on the output.
expected:
- `succeeded`, `warnings: []`; output is 5.167 ± 0.01 s, `sample_rate` 32000, 2 channels
  (the video's soundtrack is taken, not relabeled or downmixed).
- Envelope bin 2 (2–3 s): `rms_dbfs` and `peak_dbfs` are each the source's bin-2 figure
  − 12.0 ± 0.1 dB (about −33.3 rms / −17.7 peak from −21.3 / −5.7).
- Every other bin's `rms_dbfs` and `peak_dbfs` equal the source's within 0.05 dB — the
  region did not leak into 1–2 s or 3–4 s (a wrong sample-rate or interleaving conversion
  moves or stretches it), and the track-level `peak_dbfs` is unchanged (−4.81, which lives
  in bin 3).
It is a **finding** if bin 2 moves by anything other than −12 dB, if any other bin moves,
if the duration or rate changes, or if the run fails.
cleanup: `delete_output` the run folder.
metrics: none.
source: tester, found while running TESTER_TASK.agent.md (ep35, `qa-ep35`, job
`220b0347481a`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`: bin 2
−21.258 → −33.258 rms, −5.666 → −17.668 peak; bins 0/1/3/4/5 identical to the source to
the third decimal; 5.1667 s / 32 kHz / 2 ch; 0.8 s end to end. Note the step logs nothing
about what it applied (#294) — the envelope is the only evidence until that lands.

### S-F096 — `mix_audio` and `crossfade_audio` resample tracks at different sample rates instead of failing
#293: the two pure-audio joiners still died with `needs one sample rate, got [32000, 44100]`
after #108 (`concat_videos`) and #287 (`dissolve_videos`, S-F086) had removed that constraint
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
source: tester, verified in #293 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `6e4f03a463de` (both orders of the pair, plus the pinned-32k control)
succeeded in 3.7 s with the warnings quoted above; mixes read back 44100 Hz / 30.023 s, the
crossfade 44100 Hz / 49.19 s, the pinned-32k control 32000 Hz / 41.376 s with the #180
warning. Job `9d5461d74dea` confirmed a three-track crossfade and a pin equal to the higher
rate behave the same way.

### S-F097 — `gain_audio` logs the dB and the resolved region it applied, in seconds and in samples, for both the seconds and the frames form
#294: `gain_audio` applied its gain silently — nothing between `phase: task / gain_audio` and
`phase: saving` — so a consumer that cannot listen could only prove a duck landed by
measuring the envelope (S-F095), and could not prove it at all where the region fell on a
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
source: tester, verified in #294 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: job `3cdc5f90dcd7` (seconds form, seq 11 between `task` seq 10 and `saving`
seq 12) and job `94a6677af7a5` (frames form, seq 12) produced exactly the two messages and
field sets above; each run under 1 s.

### S-F098 — `resample_audio` converts: the written track carries the target rate at the source's duration, and a frame-form slice of it lands on the target rate's sample grid
`resample_audio` is the remedy every mixed-rate warning names (#108, #287, #293) and the only
task whose purpose is to convert rather than relabel — yet the smoke suite only ever exercised
its refusals (S-F024 parts 1–4). A relabel bug would still "succeed": a 44.1 kHz track
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
source: tester, found while running TESTER_TASK.agent.md (ep36, `qa-ep36`, job
`d37790d23c42`) on 2026-09-21 over MCP as model `opus` via provider `anthropic`: the
resampled wav read back 32000 Hz / 2 ch / 30.023406 s from a 30.02 s 44.1 kHz source, the
224-frame slice 9.333344 s / 32000 Hz; whole chain 0.4 s. Two `gain_audio` frame-form
ducks chained off the slice by `previous_result:` each landed exactly −9.00 dB in their
bins (S-F095/S-F097 cover that arithmetic; this case is the conversion in front of it).

### S-F099 — `get_memory` answers mid-run from the job's last phase boundary, not a previous job's post-run reading
Before #273 the worker measured memory once per job, after it finished, so `get_memory`
during a run served whatever the *previous* job had left — minutes old — for the whole
duration, exactly when an agent needs it to tell a slow run from one thrashing toward an
OOM (#265/#266). Now the worker emits a `memory` reading at every phase boundary and the
server serves the freshest one. Cheap: one SD 1.5 run, no model load if resident.
1. `run_workflow(workspace=<suite workspace>, workflow_path="templates/text-to-image",
   arguments={"num_images_per_prompt": 8, "prompt": "a lighthouse on a cliff at dusk"},
   acknowledged_cost=true)` with `wait_seconds` **0** — the run needs to still be going.
2. Immediately `get_memory()` and `get_job(job_id)`; a few seconds later `get_memory()`
   again. Then `wait_for_job` to completion and `get_job_events(job_id)`.
expected:
- While `get_job` reports `status: running`: `live: false`, `stale: true`, `reason:
  "job_running"` (that label is correct — it says *why* the reading is cached, and is not
  the finding), with `info` **populated** (not null) and `age_seconds` small — under ~10 s
  on the first read, and on the second read grown by roughly the wall time between the two
  calls (both count from the same phase boundary, `generating` at t≈0 for a resident model).
- `get_job_events` shows a `memory` event immediately after **every** `phase` event
  (`cached` or `loading`, `generating`, `decoding`, `saving`), plus the post-run one before
  `job_status: succeeded`. The `decoding`/`saving` readings differ from the `generating`
  one in `gpu_memory_reserved_mb` — they are measurements, not a copied baseline.
- After the job finishes, `get_memory` returns `live: true`, `stale: false`, `reason: null`.
It is a **finding** if a mid-run `get_memory` has `info: null`, or an `age_seconds` larger
than the running job's own age (that is the previous job's reading again), or if a `phase`
event has no `memory` event after it.
cleanup: `delete_output(job_id=<id>)`.
metrics: none.
source: tester, verified in #273 (implementer proposed the case in its hand-off comment;
added after running it on 2026-09-21 over MCP as model `opus` via provider `anthropic`: job
`cfa6fb531220`, mid-run reads at `age_seconds` 1.8 and 8.4 with `reason: "job_running"`
and `info` populated; `memory` events at seq 8/11/39/41/60 after `cached`/`generating`/
`decoding`/`saving`/post-run, reserved 4088 → 6376 → 13316 MB across them).

### S-F100 — a small-n observed estimate is tempered toward the curated figure, or flagged when there is none, and says so
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
source: tester, verified in #301 (implementer proposed both halves in its hand-off
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

### S-F101 — a single-saving-step template's deliverable is marked `final`, so `list_gallery(subfolder="final")` finds it
#302: S-F068 guards the two sequence templates #235 fixed, but the `final` convention had
never reached any *other* one-saving-step template — every LTX-2.5 template and the general
single-shot ones (`text-to-image`, …) shipped `"subfolder": ""`, so the documented "list
only deliverables" pattern returned nothing for them. The dw repo's own test now covers
1+ saving steps; this is the consumer-side guard that the convention holds catalog-wide,
checked on the cheapest template rather than the LTX-2.5 one the issue was filed against
(the fix is one sweep, so one template stands for the class). Reuse S-F003's run if it is
still present rather than generating again.
1. Run `templates/text-to-image` in this suite's workspace (defaults); `wait_for_job` (or
   `run_workflow(..., wait_seconds=55)`).
2. `list_gallery(workspace=<this suite's workspace>, subfolder="final")`.
expected:
- Step 1: the job succeeds; its one manifest entry (step `main`) has `"subfolder":
  "final"` and its file name reads `templates/text-to-image/<run id>/final/<file>.jpg` —
  the `final/` segment present in the name, not just the field.
- Step 2: that file is listed with `subfolder: "final"` and `folder:
  templates/text-to-image`.
- The regression is: the manifest entry back to `"subfolder": ""`, a name without the
  `final/` segment, or the `final` filter not listing the file.
cleanup: delete the run (`delete_output(job_id=<id>)`) unless S-F003's cleanup already
covers it.
metrics: none.
source: tester, verified in #302 (implementer proposed the case in its hand-off comment;
added after running it on 2026-09-21 over MCP as model `opus` via provider `anthropic`
against `develop @ d5e3725`, in workspace `qa-verify-302`: `templates/text-to-image` job
`1692848b00f8` → `templates/text-to-image/20260922-033453-b3b4bd77/final/test_image-0.0.jpg`,
and the issue's own family `templates/ltx2/text-to-video` (`num_frames: 25`) job
`61c44d8f7b66` → `.../20260922-033214-a189631c/final/LTX2-text_to_video.0-0.0.mp4`;
`list_gallery(subfolder="final")` returned exactly those two).

### S-F102 — `mix_audio`'s not-dB gain warning has a threshold: a modest multiplier like the templates' stock `world_gain: 1.8` is silent, a dB-shaped 12 still warns
The `mix_audio_gain_not_db` heuristic S-F094 pins fired at any gain above 1.0 when it
shipped, which meant both sequence templates tripped it on their own `world_gain: 1.8`
default and `warnings: []` was unreachable for any bare template run (#306). The threshold
is now 3.0: a value under it is a plausible multiplier, a value at or above it is treated as
a dB figure typed into the wrong unit. If the threshold drifts down again, S-F057/S-F068/C-F020's
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
source: tester, verified in #306 (implementer proposed the case in its hand-off comment;
added after running it on 2026-09-22 over MCP as model `opus` via provider `anthropic`
against `develop @ d5e3725`, workspace `regression-smoke`: job `d80bd33149e6` at the stock
1.8 → `warnings: []`; job `ae9e4d6d57ab` at `world_gain: 12` → the gain warning present,
alongside the `edit:` level-spread warning because that run omitted `match_levels`;
`templates/dissolve-between-shots` job `e0f581c0c0b1` at its stock 1.8 was likewise free of
the gain warning).

### S-F103 — `slice_audio` of a source that arrived near-silent does not warn `audio_near_silent`; a slice that *made* a normal source near-silent still does
The save-time near-silent check S-F077 pins (#261) fired on every slice of a room-tone bed
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
- Run 1: `succeeded`; `warnings` holds **exactly one** entry, `past_end: slice_audio: the
  requested slice runs … past the end of …` (the C-F016 warning). No entry from either step
  contains `near-silent`.
- Run 2: `succeeded`; `warnings` holds exactly two entries, both prefixed `voice_diluted:`
  — the past-end one and `voice_diluted-0.0.wav decodes at a mean level of … dBFS -
  near-silent for a deliverable meant to be heard …`. Nothing from `voice_inside`.
It is a **finding** if run 1 carries any `near-silent` entry (the suppression regressed),
if run 2's `voice_diluted` does not (the check was dropped or widened to all slices), or
if either run's past-end warning is missing (that is C-F016's ground, but it is cheap to
notice here).
cleanup: `delete_output(job_id=<id>)` for both runs.
metrics: none.
source: tester, verified in #309 (implementer proposed the case in its hand-off comment;
added after running it on 2026-09-22 over MCP as model `opus` via provider `anthropic`
against `develop @ d5e3725`, workspace `regression-complete`: job `1c4096862cfa` on the
room bed → one warning, the past-end one, across a past-end, an inside and a 4.965 s slice;
job `e6c29c15ef40` on `hal-voice.wav` → the inside slice silent, the 1200 s slice carrying
both the past-end and a `-43.86 dBFS … near-silent` entry).

### S-F104 — observed-cost history is scoped to the workspace, and `delete_workflow` purges it
#312 (batched with #274): `plan.estimate`'s `basis: "observed"` was fed by every finished
run of the same `workflow_name` on the server, whatever workspace it ran in — so S-F076's
step-2 "cold" validate read `observed`, `runs: 3` in a workspace that had never run it,
and #274's host-memory warnings quoted other workspaces' runs. The rows are now keyed by
`(workspace, workflow_name)` for workspace-writable workflows, and `delete_workflow` drops
the name's rows with the file, which is what lets a case re-save a fixed name and still get
a cold quote. One SD 1.5 two-step run (~10 s warm); the rest is free.
1. In a **fresh throwaway workspace** (`create_workspace(name=..., use=true)`), save the
   S-F076 document under the exact name S-F076 uses, `qa-s076-two-step` — a name the
   `regression-smoke` workspace has run many times — and `validate_workflow(name=...)`.
2. `run_workflow(name=..., acknowledged_cost=true, wait_seconds=55)`, then
   `validate_workflow(name=...)` again.
3. `delete_workflow("qa-s076-two-step")`, `save_workflow` the identical document again,
   `validate_workflow(name=...)`.
expected:
- Step 1: `estimate.basis: "unknown"`, `minutes: null`, `runs: null`, `cached_minutes:
  null` — other workspaces' history for the name does not leak in.
- Step 2: `basis: "observed"`, **`runs: 1`** (this workspace's one run, not the server-wide
  count), `cached_steps: 2`, `cached_minutes: 0.0`.
- Step 3: back to `basis: "unknown"`, `runs: null`, `cached_minutes: null`. `cached_steps`
  may still read `2` — the step cache is content-keyed and the outputs are still on disk;
  only the cost rows are purged, and that is the point.
It is a **finding** if step 1 or step 3 answers `observed`, or if step 2's `runs` exceeds 1.
cleanup: `delete_workspace(name=<throwaway>, acknowledged_cost=true)`.
metrics: none.
source: tester, verified in #312 on 2026-09-22 over MCP as model `opus` via provider
`anthropic` against `develop @ d5e3725`, workspace `qa-v312`: step 1 `unknown`/`runs: null`;
job `6f5b8a81070d` (9.8 s, both steps fresh) → step 2 `observed`/`runs: 1`/`cached_minutes:
0.0`; after delete + re-save `unknown`/`runs: null` with `cached_steps: 2`.

### S-F105 — a priced parent's composed estimate uses the child's catalog figure, and says so
#315: S-F075 arm 4's `minutes` was the parent's `cost` plus the child's *observed* median
(0.5 + 2.11 → 2.6) while `basis` read `"catalog"` and `measured_on` the short catalog
device string — the figure and its label disagreed. Since the fix, a child's observed
history is only folded in when the parent has no priced figure of its own (the only case
where the total can honestly be `basis: "observed"`); a priced parent prices its children
from their own `cost` block. S-F075 pins the arithmetic; this pins the label. Free, no
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
source: tester, verified in #315 on 2026-09-22 over MCP as model `opus` via provider
`anthropic` against `develop @ d5e3725`: text-to-video catalog 1.8 / observed 2.11 (14
runs) → priced parent `2.3`/`catalog`/`"RTX 3090"`; two-stage catalog 8.2 / observed 3.12
→ `8.7`/`catalog`; no-cost parent → `2.1`/`observed`/`runs: 14`.

### S-F106 — on the mounted server, moving the session pin off a non-default workspace warns that the pin is shared, and `create_workspace(use=true)` lands for its own caller
#298: the mounted `/mcp` surface has one workspace pin for every connected client, so
another agent's `use_workspace`/`create_workspace(use=true)` changes what this session
sees (that is by design — single-user server, not fixed). The guard is that a switch
*away from* a non-default pin now carries a `warning` naming the old and new workspace
and pointing at per-call `workspace=`; and `create_workspace(use=true)` must agree with
the next `get_server_info()` in an uninterrupted session. Free, no model, no job. Run
with the suite's pin on `regression-smoke` (non-default) so the first arm has something
to move away from; every arm is a single call.
expected:
- `create_workspace(name="regression-smoke-298", use=true)` → `current:
  "regression-smoke-298"`, `next` says this session now works there, **and** a
  `warning` string that names both `'regression-smoke'` and `'regression-smoke-298'`
  and mentions `workspace=`. `get_server_info()` immediately after → `workspace:
  "regression-smoke-298"`, every `directories.{workflows,assets,outputs}` under
  `regression-smoke-298/`.
- `use_workspace(name="regression-smoke-298")` while already there → **no** `warning`
  key.
- `create_workspace(name="regression-smoke-298b")` (no `use`) → **no** `warning`,
  `current` still `regression-smoke-298`, `next` says the session did not move.
- `use_workspace(name="default")` → `warning` naming `'regression-smoke-298'` →
  `'default'`. Then `use_workspace(name="regression-smoke")` from default → **no**
  `warning` (leaving the default pin is not a leak worth warning about).
It is a **finding** if the non-default → anything switch has no `warning`, if the warning
names the wrong pair, if `get_server_info` disagrees with `create_workspace(use=true)`'s
own `current`, or if any of the three quiet arms warns. A cross-client interleave cannot
be exercised from one session; it is out of scope here.
cleanup: `delete_workspace("regression-smoke-298", acknowledged_cost=true)` and
`delete_workspace("regression-smoke-298b", acknowledged_cost=true)`; confirm
`list_workspaces().current == "regression-smoke"` before the next case.
metrics: none.
source: tester, verified in #298 on 2026-09-22 over MCP as model `opus` via provider
`anthropic` against `develop @ 7e1a1a5` (with `qa-verify-*` workspace names in place of
the `regression-smoke-*` ones above).

### S-F107 — `get_output_frames` `crop` is in source pixels, cut per frame before any downscale or sheet layout
#303: `get_output_frames` gained `get_output_image`'s `crop` (`[x, y, width, height]`), and
the first landing cut it from tiles *already shrunk* to `max_dimension` — so one box named a
different region at every size — and, in `count` mode, from the assembled contact sheet, so
an in-bounds source box was refused as "outside the 256x48 image". The contract is the image
tool's: the box is in the decoded frame's own pixels, cut per frame before anything else.
Free — no job, four calls on the fixture `asset:qa-cast/ep25-episode.mp4` (960x544 source).
Pass `workspace="regression-smoke"` on each.
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
source: tester, verified in #303 on 2026-09-22 over MCP as model `opus` via provider
`anthropic` against `develop @ 7e1a1a5` (dw 0.4.0-beta.6 on `lem`).

### S-F108 — a fractional argument to an integer-typed variable is refused, not truncated
#338: a variable's type comes from its default, and coercion used to be a bare `int(v)`.
`score_gain: 0.3` against a default of `1` was realized as `0` without a warning. It deleted
the music from four "succeeded" films. The real-valued catalog defaults are now floats
(`guidance_scale: 9.0`, `audio_bleed_gain_db: 0.0`, …), and a fractional value sent to a
variable that really is an int is refused at pre-flight. Free: no job is queued.
1. `validate_workflow(name="templates/upscale-diffusion", arguments={"noise_level": 20.5})`.
   `noise_level` is integer-typed (default `20`).
2. `run_workflow(workflow_path="templates/upscale-diffusion", arguments={"noise_level": 20.5},
   acknowledged_cost=true)`.
3. `validate_workflow(name="templates/upscale-diffusion", arguments={"guidance_scale": 7.5})`.
4. `validate_workflow(name="templates/upscale-diffusion",
   arguments={"noise_level": 30, "num_inference_steps": "12"})`, then the same call with
   `{"num_inference_steps": "12.5"}`.
expected:
- Step 1: `valid: false`, one error at `arguments.noise_level` that names the variable, the
  value and what it would have become. Today's message is `noise_level 20.5 would be realized
  as 20: this variable is typed integer by its default; …`.
- Step 2: refused before queueing, with the same message. No `job_id`.
- Step 3: `valid: true`, no warnings. `guidance_scale` is in `checked_arguments`.
- Step 4: the integral values are valid. The fractional string is refused at
  `arguments.num_inference_steps`.
It is a **finding** if step 1 or step 4's second call validates, or if step 2 queues a job.
Either one means a fraction can reach an int variable and be floored silently. It is also a
finding if step 3 is refused or warned about, which would mean a real-valued catalog default
has gone back to an integer literal.
cleanup: none. Nothing is queued or written.
metrics: none.
source: tester, verified in #338 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`.

### S-F109 — both sequence templates' `world_fade_out_ms` fades only the world tail, and its default `0` changes nothing
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
source: tester, verified in #339 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (jobs 1a36cf75d84c, b007639f60eb,
2cb736b751d8, a5fe2d863125).

### S-F110 — a `component_type`/`scheduler_type` the runtime cannot resolve is refused by the free pre-flight, with suggestions
Before #345, `validate_workflow` returned `valid: true` for a pipeline step whose
`component_type` named a class diffusers doesn't export, and quoted its download. The run
then died 3 s in with "module diffusers has no attribute …". This is the pipeline-side
twin of S-F085. Free: four validate calls, nothing runs.
Each call below uses this step shape, with only the named field changed: `{"id":
"regression-bad-class", "steps": [{"name": "g", "pipeline": {"configuration":
{"component_type": <CT>}, "from_pretrained_arguments": {"model_name":
"stabilityai/stable-diffusion-xl-base-1.0"}, "arguments": {"prompt": "a cat"}}, "result":
{"content_type": "image/png"}}]}`.
1. `<CT>` = `"StableDiffusionXLPipline"` (misspelled).
2. `<CT>` = `"StableDiffusionXLPipeline"` (real).
3. `<CT>` = `"os.system"` (outside the trusted ecosystem).
4. `<CT>` = `"StableDiffusionXLPipeline"`, plus `"scheduler": {"configuration":
   {"scheduler_type": "EulerDiscreteSchedulr"}}` inside `pipeline`.
expected:
- Step 1 is `valid: false`, with an error at `steps[0].pipeline.configuration.component_type`.
  The message says `'StableDiffusionXLPipline' does not exist` and lists closest matches,
  including `StableDiffusionXLPipeline`. There is no `plan`, so no `downloads_required`.
- Step 2 is `valid: true` and its plan quotes the SDXL repo in `downloads_required`. A real
  class is not refused.
- Step 3 is `valid: false` at the same path, with a *refusal* message ("Refusing to load a
  dotted type reference … outside the ecosystem"). That wording is different from step 1's
  "does not exist".
- Step 4 is `valid: false` at `steps[0].pipeline.scheduler.configuration.scheduler_type`.
  The message says it does not exist and suggests `EulerDiscreteScheduler`.
It is a **finding** if step 1 or step 4 comes back `valid: true`, or if step 1 still quotes
a download. It is also one if step 2 is refused, or if step 3's message can't be told apart
from step 1's.
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #345 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`. All four came back as expected above.
Step 2 quoted 71.6 GB. (The issue's original `QwenImage21Pipeline` repro now validates
correctly: `get_class` shows lem's diffusers exports that class, so this case uses a
misspelling instead.)

### S-F111 — a still image under a `video` argument is refused by the free pre-flight, and the `media_type` form that loads it runs
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
source: tester, verified in #347 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (job 4ae03c56e4a1: 121 frames, 24 fps,
768x768).

### S-F112 — `get_task` lists a function-backed image processor's real arguments, and validate checks them
Before #350, `get_task` reported every image processor as `(image, device)` with
`accepts_kwargs: true` and the generic summary "'<name>' image processor (ControlNet
preprocessor)". That hid real arguments, and an agent concluded `recenter_crop` could not
reach a corner. Free: three discovery calls and one validate, nothing runs.
1. `get_task("recenter_crop")`.
2. `get_task("resize_resample")`.
3. `get_task("canny")` (detector-backed, so no plain function behind it).
4. `validate_workflow` with `{"id": "qa_350", "steps": [{"name": "crop", "task": {"command":
   "recenter_crop", "arguments": {"image": "https://example.com/x.png", "center_x": 0.9,
   "center_y": 0.1, "crop": 0.25, "bogus_arg": 1}}}]}`.
expected:
- Step 1: `accepts_kwargs: false`, with a real docstring summary (not "ControlNet
  preprocessor"). `parameters` includes `center_x` (0.5), `center_y` (0.5), `crop` (1.0),
  `width` (null), `height` (null) and `fill` ("edge"), alongside `image` and `device`.
- Step 2: `accepts_kwargs: false`, and `parameters` includes `resolution` (1024).
- Step 3: still the generic shape. `parameters` is just `image` and `device`, with
  `accepts_kwargs: true`.
- Step 4: `valid: false`, with exactly one error, at `steps[0].task.arguments.bogus_arg`
  ("does not accept argument"). `center_x`/`center_y`/`crop` are not flagged.
It is a **finding** if step 1 or 2 falls back to `(image, device)`, if step 4 flags a real
argument or passes `bogus_arg`, or if step 3 starts claiming arguments it doesn't have.
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #350 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`.

### S-F113 — a dict parameter given as a JSON string is parsed, and a malformed one is named as invalid JSON
Before #359, `validate_workflow`, `run_workflow` and `save_prompt` typed their document
params as `dict` only. A JSON *string* with a syntax error got pydantic's
`Input should be a valid dictionary [type=dict_type …]`, and an agent read that as "the
tool won't take a document this size" when the real cause was a syntax error. Free: no
GPU time.
The values below must reach the server as **strings**, not objects. A client that
parses a `{`-leading parameter value as JSON will send an object and skip the path this
case tests; a leading space (`' {…}'`) keeps it a string, and the server's JSON parse
ignores the whitespace.
1. `save_prompt(name="qa-sf113", prompt=' {"text": "a red fox in snow", "description": "S-F113"}')`,
   then `get_prompt("qa-sf113")`.
2. `save_prompt(name="qa-sf113-bad", prompt=' {"text": "a cat", "description": "x" ')`.
3. `validate_workflow(workflow=' {"id": "x", "steps": [ }')`, and the same string as
   `validate_workflow(inline_workflow=…)` and `run_workflow(inline_workflow=…)`.
expected:
- Step 1: saved. `get_prompt` returns the parsed object (`text`, `description`).
- Step 2: refused with `` `prompt` is not valid JSON: `` plus the parser's detail
  (line/column), and nothing is saved.
- Step 3: each call is refused with `` `<param>` is not valid JSON: Expecting value: line 1
  column … ``, naming the param it was given as. `run_workflow` refuses before
  anything is queued.
It is a **finding** if any step returns `dict_type`/`Input should be a valid dictionary`,
or if step 1 stores the raw string instead of the object.
cleanup: `delete_prompt("qa-sf113")`. Also delete `qa-sf113-bad` if it exists, since
that existing is itself a finding.
metrics: none.
source: tester, verified in #359 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`.

### S-F114 — `run_workflow`'s queued answer names the workspace the job was queued into
Before #360, a `run_workflow` with `wait_seconds=0` answered `{job_id, status,
queue_position, next}` with no workspace. On the mounted server (`get_server_info` →
`mcp.mounted: true`) every client shares one pin (#298), so a client that another client
had moved got no sign of it until it went looking for its outputs. Cheap: two ~1 s
utility jobs, no model load.
Workflow: an inline one-step `resample_audio`, `arguments: {"audio":
"asset:qa-cast/ep11-bed.wav", "target_sample_rate": 16000}`, `result: {"subfolder":
"final", "file_base_name": "resampled", "content_type": "audio/wav"}`. Validate it first
and pass the plan as `acknowledged_cost`.
1. `use_workspace("regression-smoke")`, then `run_workflow(inline_workflow=…,
   wait_seconds=0)` with **no** `workspace=`.
2. `use_workspace("default")`, then the same run with `workspace="regression-smoke"`,
   `wait_seconds=0`. Then `use_workspace("regression-smoke")` again so the rest of the
   run stays in this suite's workspace.
expected:
- Step 1: the reply carries `"workspace": "regression-smoke"` beside `job_id`/`status`/
  `queue_position`/`next`.
- Step 2: the reply carries `"workspace": "regression-smoke"`. That is the job's
  workspace, not the session pin (`default`).
- `wait_for_job` on each job reports `job.workspace: "regression-smoke"`, the same value
  as the queued answer. It is a **finding** if the queued answer has no `workspace` key,
  or if it disagrees with the job's own.
cleanup: `delete_output(job_id=…)` for both jobs. The fixture bed is read-only.
metrics: none.
source: tester, verified in #360 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (jobs `5d05fc04b40d`, `79939a6ce65b`).

### S-F115 — media loads by the argument a variable lands in, not by the variable's name
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
source: tester, verified in #365 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e` (jobs `bcb37cf0f8a5`, `1bc5b2354d70`).

## Performance

### S-P001 — default image generation latency
Time S-F003 (single image, default params) using the job's own
`started_at`→`finished_at` — not wall clock, which adds queue time and agent
turnaround. Log **cold** (first SD 1.5 run of the session, model loading from
disk) and **warm** as separate `condition`s; they are different numbers.
**Warm** is S-F003's workflow (same template, default params) run again
immediately after the cold run, with no other workflow in between — the
server's resident-pipeline cache is keyed on workflow identity, not on the
model, so a run that follows a *different* workflow reloads the pipeline even
on the same SD 1.5 weights (#332: `Workflow changed - releasing cached
models...`, ~2 s of reload). Such a run is neither cold nor warm: don't log it
under either condition. The `warm` readings logged before this change (#337)
may include such reloads — the 6.16 s of 2026-09-22 is one — so the warm
median is noisy until they leave the last-5 window.
baseline: TBD — the log is the baseline; when a human sets one, cold and warm
get separate ceilings.
cleanup: as S-F003.

### S-P002 — workspace listing/probe latency
Time S-F006 (listing/probing a workspace with a handful of assets already in
it). Consumer-side wall clock (`condition: wall`) — a sub-second call's
figure is almost entirely agent turnaround between two `date` readings, so
this is only meaningful as a "nothing pathological" ceiling.
baseline: 5 s wall — a ceiling, not a target; anything under it is a pass.
cleanup: as S-F006.

### S-P003 — tool/template discovery latency
Time S-F002 (the tools/templates list call), cold — i.e. as the first call of
the run, before anything else warms up server-side caches. Consumer-side wall
clock (`condition: wall`), same caveat as S-P002; no cold server-side penalty
has been seen to date (the same call later in a run is indistinguishable), so
a real one appearing is worth a note even under the noise band.
baseline: TBD — the log is the baseline.
cleanup: none (read-only).

### S-P004 — multi-step audio chain latency
Time S-F007 (speech → trim → fade, three steps in one job) using the job's own
`started_at`/`finished_at`, not wall clock. Bark-small loading is included
and is most of the figure; the two audio tasks are sub-second.
baseline: TBD — the log is the baseline.
cleanup: as S-F007.
