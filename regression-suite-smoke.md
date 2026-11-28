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

Durable contents of `regression-smoke` that persist across runs. Add a line
when a case starts relying on one; remove the line (and the fixture) when
nothing uses it anymore.

- `asset:qa-cast/ep11-bed.wav` — a 472-frame (24 fps) 32 kHz mono bed in the shared
  asset library, reachable from every workspace. C-F1513 resamples it in a ~1 s utility
  job; any short audio file substitutes. Read-only — never sliced in place, never
  deleted. The complete suite also uses it.
- `asset:qa-cast/ep6-cold-open.mp4`, `asset:qa-cast/ep3-shot2-reply.mp4`,
  `asset:qa-cast/ep13-episode.mp4` and `asset:qa-cast/ep20-score.wav` — three shots and a
  score bed in the shared asset library. C-F1506 binds all four to
  `templates/dissolve-between-shots` in a validate-only call, so only their existence and
  kinds matter here. Read-only, never deleted. The complete suite also uses them, and its
  Fixtures section records the properties its cases depend on.
- `asset:qa-cast/hal-voice.wav` — a 6.48 s 24 kHz mono line in the shared asset
  library. S-F070 transcribes it; any short spoken clip substitutes. C-F1520 slices it in a
  validate-only call and depends on the 6.48 s length. Read-only, never deleted. The
  complete suite also uses it.
- `asset:qa-cast/ep42-shot1-accuse.mp4` and `asset:qa-cast/ep42-shot2-deflect.mp4`: two
  shots in the shared asset library, 124 frames each. S-F125 depends on that count in a
  validate-only call. They are read-only and never deleted.
- `asset:qa-cast/priya-portrait.jpg` and `asset:qa-cast/hal-portrait.jpg`: two stills in
  the shared asset library. S-F128 binds them to `templates/ltx2/keyframes` in validate-only
  calls, so only their existence matters. Any two images substitute. S-F147 names the first
  as its image reference, also validate-only. Read-only, never deleted.
- `asset:qa-cast/priya-voice.wav`: about 6 s of speech in the shared asset library.
  C-F1521 transcribes it with word and segment timestamps. Any short spoken clip under 30 s
  substitutes. Read-only, never deleted.
- `asset:qa-cast/ep86-episode.mp4`, `asset:qa-cast/ep84-episode.mp4` and
  `asset:qa-cast/ep68-score.mp3`: two cut episodes and a score in the shared asset library.
  C-F1522 cuts them with `templates/assemble-and-score` in a ~6 s utility job. Only their
  existence matters: any two same-size 24 fps clips with audio and a score substitute (with
  `total_frames` adjusted). Read-only, never deleted.

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
runner: script

### S-F003 — generate a single image, default params; its deliverable is marked `final`, so `list_gallery(subfolder="final")` finds it
Using the server's basic image-generation tool/template, generate one image
in `regression-smoke` with only the required parameters (a simple prompt,
everything else default).
The same run carries a second check, the `final` arm (#302): C-F071 guards the two
sequence templates #235 fixed, but the `final` convention had never reached any *other*
one-saving-step template — every LTX-2.5 template and the general single-shot ones
(`text-to-image`, …) shipped `"subfolder": ""`, so the documented "list only deliverables"
pattern returned nothing for them. The dw repo's own test now covers 1+ saving steps; this
is the consumer-side guard that the convention holds catalog-wide, checked on the cheapest
template rather than the LTX-2.5 one the issue was filed against (the fix is one sweep, so
one template stands for the class). One generation serves both checks; do not generate
again for the `final` arm.
1. Run `templates/text-to-image` in `regression-smoke` (defaults) — the generation above;
   `wait_for_job` (or `run_workflow(..., wait_seconds=55)`).
2. `list_gallery(workspace="regression-smoke", subfolder="final")`.
expected: call succeeds, response includes a reference to a generated image
asset (path/id/url per whatever the schema returns), and that asset is
retrievable/listable afterward in the workspace.
- `final` arm, step 1: the job succeeds; its one manifest entry (step `main`) has
  `"subfolder": "final"` and its file name reads
  `templates/text-to-image/<run id>/final/<file>.jpg` — the `final/` segment present in the
  name, not just the field.
- `final` arm, step 2: that file is listed with `subfolder: "final"` and `folder:
  templates/text-to-image`.
- `final` arm, the regression is: the manifest entry back to `"subfolder": ""`, a name
  without the `final/` segment, or the `final` filter not listing the file.
cleanup: S-F006/S-F006 inspect this output first; delete it right after
they've run (or after this case, if S-F006 is skipped). Deleting the run
(`delete_output(job_id=<id>)`) covers the `final` arm too.
metrics: none.

absorbs: S-F101 (merged 2026-11-26, suite review)
- S-F101: tester, verified in #302 (implementer proposed the case in its hand-off comment; added after running it on 2026-09-21 over MCP as model `opus` via provider `anthropic` against `develop @ d5e3725`, in workspace `qa-verify-302`: `templates/text-to-image` job `1692848b00f8` → `templates/text-to-image/20260922-033453-b3b4bd77/final/test_image-0.0.jpg`, and the issue's own family `templates/ltx2/text-to-video` (`num_frames: 25`) job `61c44d8f7b66` → `.../20260922-033214-a189631c/final/LTX2-text_to_video.0-0.0.mp4`; `list_gallery(subfolder="final")` returned exactly those two).

### S-F004 — generate a single image, explicit size/seed
Same as S-F003 but pin an explicit size and a fixed seed. The stock
`templates/text-to-image` declares `seed`, `width` and `height` (512 by default)
since dw#1710 but no step count,
so this stays an inline workflow: top-level `seed` (per the "workflows" guide)
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
cleanup: same as S-F003 — hold for S-F006/S-F006, then delete both images
(the seed-repeat one too).
amended: 2026-11-26, suite review: the template now declares `seed`, `width` and `height` (dw#1710 verified; `get_workflow` shows them); the inline workflow and every expectation are unchanged.

### S-F005 — invalid image-generation params are rejected cleanly, and pipeline value constraints are a clean run-time failure
Call the image-generation tool with an invalid parameter. Three probes,
run all of them: (a) `arguments: {num_images_per_prompt: "not-a-number"}`;
(b) `arguments: {nonexistent_variable: 3}`; (c) an inline workflow at
383x383 (not divisible by 8).
For (c), validate, then run: it is a workflow whose values are schema-valid but the
pipeline will refuse, so call `validate_workflow` on it first, then run it.
expected: a clear validation error, not a 500/crash/hang, and not a silently
"corrected" result. (a) and (b) are refused pre-flight by `run_workflow`
with a tool error naming the path and, for (b), listing the declared
variables — nothing is queued. (c) is caught only at run time —
`validate_workflow` passes it (that boundary is the "(c), validate/run boundary" paragraph below): the job
`fails` with the pipeline's "`height` and `width` have to be divisible by 8"
message, an empty manifest, and nothing in the gallery.
(c), validate/run boundary: documents where the line sits. `validate_workflow` checks schema
and pipeline *signatures*, not value ranges, so it passes; the job then
fails with the pipeline's own message, an empty manifest, and no partial
output left behind. A hang, a 500, or a silently corrected size is the
finding — so is a run that leaves a file in the gallery. (Same probe as (c) above,
asserted separately because what this paragraph pins down is the validate/run boundary,
not the error's tone.)
cleanup: confirm nothing was created (a rejected call must not leave an
output behind — if it did, that's part of the finding); delete it if so.
For (c), confirm the failed run wrote nothing; delete it if it did.

absorbs: S-F011 (merged 2026-11-26, suite review)
- S-F011: (no source: line)

### S-F006 — list/probe workspace contents, within a latency ceiling
After S-F003/S-F004, use whatever inspection tool the server offers (list,
probe, etc.) against `regression-smoke`.
Time the listing/probe call (a workspace with a handful of assets already in it) for the
`metrics:` line below.
expected: the generated assets from this run are visible and correctly
described (type, size, or other basic metadata matches what was requested).
`list_gallery()` carries `folder`, `subfolder`, `kind`, `size`, `mtime` and a
workspace-scoped `url` but **no image dimensions**, so "size matches what was
requested" is checked with `get_output_image` (reports `original_size`) or
`get_gallery_metadata` (returns the embedded workflow, arguments and seed).
cleanup: this is the last case that needs the S-F003/S-F004 outputs — delete
them here, then re-list to confirm they're gone (a deleted output still
showing is a finding).
metrics: `latency` of the listing/probe call. Consumer-side wall clock
(`condition: wall`) — a sub-second call's figure is almost entirely agent turnaround
between two `date` readings, so this is only meaningful as a "nothing pathological"
ceiling. baseline: 5 s wall — a ceiling, not a target; anything under it is a pass.

absorbs: S-P002 (merged 2026-11-26, suite review)
- S-P002: (no source: line)

### S-F007 — basic audio or multi-step template runs end-to-end
Run one of the simpler multi-step templates (whatever the schema currently
calls the smallest end-to-end workflow — e.g. a single-shot or single-line
template) with minimal inputs. The shape used to date is a three-step inline
chain: Bark `generate_speech` → `slice_audio` to `variable:clip_seconds` =
1.5 → `fade_audio` at `variable:sample_rate` = 24000, saving only the final
step. Pin the speech step's inputs exactly - `model_name: "suno/bark-small"`,
step `seed: 7`, text `"Somebody finished the pistachio and nobody is saying
anything."` - because this case's `metrics:` line times this job: Bark's take length is set by
text and seed, and another sentence at seed 7 ("Hello there, this is a short
test of the speech chain.") generates 14.7 s with 10.5 s of leading silence,
taking 16.5 s instead of ~4 s and leaving the 1.5 s slice near-silent (#819).
With these inputs the slice is audible, about -21 dBFS mean. (Schema note: `result.sample_rate` will not take a `variable:`
reference — schema validation runs before substitution — and the error names
both paths; documented behaviour, not a finding.)
expected: the whole chain completes without a dropped parameter between
steps (this class of bug has bitten before — a chain silently losing a param
partway through is worse than an outright failure, so check the final output
actually reflects every input given, not just that the call returned 200).
For the chain above: `get_gallery_metadata` on the final wav reports
`duration_seconds: 1.5` and `sample_rate: 24000`, its envelope shows the
fades and a non-silent level, and the unsaved intermediate steps report empty
file lists. The `metrics:` line below times this same job.
Loudness is not this case's subject. The take is pinned (`seed: 7` above), so it
should be the audible one; if it still comes back near-silent, that is not a failure as
long as the job says so. The
final wav either decodes audibly, **or** the job carries the near-silent warning
(`near-silent for a deliverable meant to be heard`). Either passes. A near-silent
wav with **no** warning is the finding (the #261 regression). Keep `seed` pinned on
`generate_speech` so the `metrics:` line always times the same take. (Amended per
harnest#26, dw#530: Don, 2026-09-27, 0.5.0 release.)
cleanup: delete every intermediate and final output the template
produced, plus any asset `keep_output`-style steps may have linked, unless
one is needed for a repro.
metrics: `latency` of this job (speech → trim → fade, three steps in one job) using the
job's own `started_at`/`finished_at`, not wall clock. Bark-small loading is included
and is most of the figure; the two audio tasks are sub-second. A reading
whose speech inputs differ from the pinned ones above is not comparable to the
log - note it as such rather than filing it (#819). baseline: TBD — the log is the
baseline.

absorbs: S-P004 (merged 2026-11-26, suite review)
- S-P004: (no source: line)
amended: 2026-11-26, suite review: the loudness paragraph spoke of an unseeded take while the steps pin seed 7 (#819); wording aligned, the audible-or-warned rule of harnest#26 unchanged

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
runner: script

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
expected: the pinned `keep_output` returns an `asset:` reference with
`workspace: "regression-smoke"` (it carries no `path` since #527), and the pinned `list_gallery` returns
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
expected: the asset side takes the same per-call pin (#463). From the session in
`default`, without switching it:
1. `list_assets()` with no pin does **not** show the asset.
2. `list_assets(workspace="regression-smoke")` shows it with `origin: "workspace"`,
   and the session's own pin is unchanged afterwards.
3. `delete_asset(name, workspace="regression-smoke")` → `deleted: true`,
   `origin: "workspace"`, and a second pinned `list_assets` no longer shows it.
It is a **finding** if a pinned call touches `default`, if the unpinned listing
shows the other workspace's asset, or if a pinned write leaves a file neither a
pinned call nor `use_workspace` can clean up. (Rewritten from the documented-gap
form per harnest#27, dw#531: Don, 2026-09-27, 0.5.0 release.)
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
(`condition: catalog-summary-delivered`), logged to `regression-perf/S-F015.jsonl` — the
point of #101 was the number, and a slow creep back up is what this case exists
to catch, so those two are compared against their history per the regression
agent's rule as well as against the ceilings here: guide index under 3 KB (above);
catalog summary: measure, do not estimate - use the size of the `list_workflows()`
reply as delivered (the harness's saved-result / `< N chars` figure), and log that
number. Two ceilings: (a) **250 B per entry** as delivered (size / number of
`details` entries; 219 B/entry at 118 entries on 2026-11-20) - exceeding it means
entries got fatter, which is the regression this case exists to catch, and is a
finding; (b) **32 KB total** as delivered (25.9 KB at 118 entries) - exceeding it
with (a) still met means the catalog has outgrown the summary form: file a normal dw
ticket asking for a smaller default answer, not a suite request to raise the number
again. The delivered size has its own `condition` because the `catalog-summary`
readings logged up to 2026-11-20 were estimates: they are not comparable with a
measured size and are never pooled with it. (Amended per dkackman/harnest#269: Don,
2026-11-20, 0.21.0 release.) Also log `get_schema()`'s full size (`condition: schema-full`) for
the trend, but no ceiling on it: it's on-request, and its size is the schema's
honest size — the guard against it is `section=`, which item 2 already checks.
Note `view`/`note` are absent rather than `view: "full"` on the filtered answer —
that is current behavior as of 0.4.0-beta.3, not a finding; key on
`view == "summary"`.
cleanup: none — every call is read-only.
source: tester, verified in #101 (all three items proposed by the implementer in
that issue's hand-off; run over MCP 2026-09-13, model `opus` via provider
`anthropic`).

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
(`configures, cost, cost_drivers, description, host_ram_gb, id, presets, seed, shape,
steps, summary, traits, variable_constraints, variables, vram_estimate`). (b) `result: {"content_type": "text/plain", "subfoldr": "final"}` →
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
runner: script
source: tester, verified in #123 on 2026-09-13 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep7`, dw 0.4.0-beta.3. Labelled
`breaking-change` on the fix: a workflow carrying a dead key validated before it
and does not after.
Amended 2026-11-20 (dkackman/harnest#271, approved by Don): the legal root set gains
`presets` (#1203) and `host_ram_gb` (#1227).

### S-F019 — an input asset's own duration/fps/sample_rate, or an image's measured size, is readable before a run, and `include_workflow=false` drops the embedded workflow
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
Image arm (#922): asking "how big is this image" must not take reading the pipeline's
arguments out of ~20 KB of embedded workflow. Read-only, no GPU. Two calls:
(e) `get_gallery_metadata(name="asset:qa-cast/hal-portrait.jpg", include_workflow=false)`;
(f) the same call without `include_workflow`.
- (e): `media` is `{kind: "image", width: 768, height: 768, mode: "RGB"}`. `metadata` has
  `workflow_omitted: true` and no `workflow` key, and still carries `step_name`, `seed` and
  `arguments`.
- (f): the same `media`, and `metadata.workflow` is present (the default is unchanged).
It is a **finding** if an `asset:` reference resolves against the outputs root
again (the original bug: the prefix was echoed into an outputs path verbatim, so
the error read as a missing file rather than an unsupported reference form), if
`source` stops distinguishing `"asset"` from `"output"`, if `media` is absent for
a media asset, or if (d) resolves to anything at all — that last one is a
containment escape and belongs in `regression-suite-security.md`'s territory, so
report it there as well.
In the image arm it is a **finding** if `media` is null or has no `width`/`height` for an
image, or if (e) still inlines `metadata.workflow`.
cleanup: none (read-only).
metrics: none.
source: tester, verified in #127 on 2026-09-13 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep9`, dw 0.4.0-beta.3.

absorbs: S-F142 (merged 2026-11-26, suite review)
- S-F142: tester, verified in #922 on 2026-10-15 over MCP as model `claude-opus-5-5` via provider `anthropic` against `develop @ 4a79cb35` on `lem` (cuda).

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
Since #134 (verified) the run directory, sidecars included, goes with the last
`delete_output` (`run_swept`, S-F022), so the delta is zero apart from kept
fixtures. Any `manifest.json`/`workflow.json` residue is the #134 regression.
It becomes a **worse finding** if the per-job residue grows beyond those two
files, or if a deleted output's own media file is what survives — that last one
would mean `delete_output` is not deleting, and S-F008 would be failing too.
cleanup: none of its own — it measures the other cases' cleanup.
source: regression agent, found on 2026-09-13 during the final sweep as model
`opus` via provider `anthropic` (filed as #134). At smoke level because it is the
cleanup path every other case's `cleanup:` line depends on being able to reach —
the same reason S-F014 is here.

### S-F022 — `delete_output` reports the sweep, and a run directory is addressable and contained, including a run that failed before writing any media
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
Failed-run arm — a run that failed before writing any media is still deletable by its run
name. The bullets above exercise the `<workflow>/<run id>` form only against runs that
*did* write media. A run that fails before writing media is the one shape the form exists
for: such a run leaves a run directory containing only `manifest.json` and
`workflow.json`, no media file names it, and no other call can address it. If the form
decays into "404 unless a media file names it", those directories accumulate with no way
to reach them and every later sweep is wrong about what a workspace holds.
Two fast runtime failures that reliably write nothing are known; the pipeline one is already
run by S-F005(c)/S-F005, the task one is built here from one upload.
- **Failed-run arm, from a failed pipeline run.** Take S-F005(c)/S-F005's 383x383 SD 1.5
  job (fails in ~2.5 s on "`height` and `width` have to be divisible by 8",
  `manifest: []`). Note its `run_id`, then `delete_output(name="<workflow id>/<run id>")`
  → `deleted: true` and `run_swept` equal to that run id.
- **Failed-run arm, from a failed task run.** `upload_asset` a few bytes of plain text
  under a valid audio name, `sf034-not-audio.wav`, then run an inline one-step
  `resample_audio` workflow on `asset:sf034-not-audio.wav` with `target_sample_rate: 16000`
  → it passes pre-flight (name and rate are valid; only the task can see the content),
  queues, and fails at the task layer with `manifest: []`. Delete it the same way →
  `deleted: true`, `run_swept` the run id. Two different failure layers, because a form
  wired only into the pipeline path would pass the pipeline bullet alone.
- **Failed-run arm, the delete is the assertion.** Either call answering "not found", or
  answering `deleted: true` with `run_swept: null`, is the finding — the second more
  quietly, since it says the directory was left behind.
- **Failed-run arm, and it actually went.** `list_workspaces()` reports this workspace's
  `usage.files` down by exactly 2 per swept run (the two sidecars). A `deleted: true` that
  does not move `usage` is the same finding as a refusal.
cleanup: the case deletes its own runs as its assertions — nothing is left. If a
probe's refusal unexpectedly succeeded, whatever it removed is gone and that is
the finding. The failed-run arm has no run cleanup of its own — it *is* the cleanup those
two failed runs would otherwise need, and it leaves nothing behind. `delete_asset` of
`sf034-not-audio.wav`.
metrics: none. The timings above are context for recognising the failures, not figures to
log; S-P001 already tracks this box's SD 1.5 latency.
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

absorbs: S-F034 (merged 2026-11-26, suite review)
- S-F034: regression agent, model `opus` via provider `anthropic`, found on 2026-09-16 while running S-F005 and C-F076 against dw 0.4.0-beta.4 on `lem`, workspace `regression-smoke`. Both halves were run: job `e4e35b833f56` (383x383, run `20260916-004532-c9a15679`) and job `2168c7a24782` (`target_sample_rate` 0, run `20260916-005157-1a7e0a0c`), each swept by its `<workflow>/<run id>` name with `run_swept` matching, and the workspace measured back to its pre-run 47 files / 43,135 bytes afterwards. Added at smoke level for the same reason S-F014, S-F021 and S-F022 are here: it is the cleanup path every other case's `cleanup:` line depends on being able to reach. Written as a new case rather than a bullet on S-F022, which no agent may edit.

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
runner: script
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
runner: script
source: tester, model `opus` via provider `anthropic`, verified in #96 on
2026-09-14 against dw 0.4.0-beta.4 on `lem`. The implementer proposed the first,
second and fourth bullets; the snap-then-range pair is mine, added because the
implementer reported that their own first attempt checked the raw value and
would have falsely refused 108-123.

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
runner: script
source: tester, model `opus` via provider `anthropic`, verified in #145 on 2026-09-14
against dw 0.4.0-beta.4 on `lem`, workspace `qa-verify`. Don asked for this case by name
when approving the fix, as the list-entry variant of the existing #96 case. The third
bullet is mine: the implementer's hand-off proposed only the single-entry 61/130 pair,
which cannot tell a correct index from a hardcoded one.

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
Let `W` be an inline workflow `{"id": "s-f035", "variables": {"reference_sheet":
"asset:s-f035-never-uploaded.png", "prompt": "prompt:<any stored prompt>"}, ...}` with one
step that uses both variables.
expected:
- **Bare call reports the unresolvable default.** `validate_workflow(workflow=W)`, no
  arguments → `valid: false`, one error whose
  path is **`variables.reference_sheet`** (not `arguments.`, not a step path), its
  text naming the missing asset `s-f035-never-uploaded.png` and the asset roots searched.
  `checked_arguments: []`. A `valid: true` here is the regression.
- **The default really is unresolvable.** `list_assets()` reports no
  `s-f035-never-uploaded.png` in any root. If one ever appears, the premise is gone —
  file an issue rather than editing the case.
- **The two paths agree.** The same call with `arguments={"reference_sheet":
  "asset:s-f035-never-uploaded.png"}` → `valid: false` too, same message, but at
  **`arguments.reference_sheet`**. Identical verdict, different path: the path is
  what tells a caller "you wrote a bad reference" from "you did not override a bad
  default", so a fix that reports both as `arguments.` is a partial fix.
- **No over-reporting — the override is what gets judged.** The same call with
  `arguments={"reference_sheet": "asset:<any real image in this workspace>"}` →
  `valid: true`, `checked_arguments: ["reference_sheet"]`, and a `plan`. This is the
  assertion that separates a correct fix from one that just fails any workflow
  carrying a placeholder default: the caller's value replaces the default before the
  check, and the workflow's *other* defaults (its `prompt:` one)
  resolve and are not falsely flagged.
cleanup: none — all four calls are free discovery/validate calls that load nothing,
queue nothing and write nothing.
runner: script
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
source: rebased from `templates/ltx2/reference-sheet` onto the inline `W` after
dkackman/diffusers-workflow#450 found that template's default now resolving from
`common/assets`; approved by Don in dkackman/harnest#17.

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
  `content_type: "video/mp4"`, and with its `pair_audio` inputs pointed at media that
  exist (`asset:qa-cast/ep6-cold-open.mp4` and `asset:qa-cast/ep20-score.wav`; since
  #494 validate refuses `output:` references that don't exist) → `valid: true`, a
  `plan` with a fingerprint, and no error at `steps[0].result.content_type`. (Amended
  per harnest#28, dw#533: Don, 2026-09-27, 0.5.0 release.) A suite that only asserts refusals is
  satisfied by a check that refuses everything.
- **The check runs after substitution.** The same document with `content_type:
  "variable:ct"`, a declared `ct` variable, and `arguments: {"ct": "video"}` →
  `valid: false` with the bare-word message at `steps[0].result.content_type`. A value
  routed through `arguments` must not be able to walk past the pre-flight and reach
  the writer; a check that only reads literals in the stored document passes the first
  three bullets and leaves the original bug open on the path callers actually use.
- **Workspace-independent, with one fixture.** Since #494 validate existence-checks
  references written into a step, so the positive bullet depends on the two
  `asset:qa-cast/…` media named there (shared asset library, reachable from every
  workspace; see Fixtures). The three refusal bullets assert an error at
  `steps[0].result.content_type` whatever the inputs point at, so the case still runs
  identically in any workspace. A missing-reference error on the positive bullet
  means the fixture is gone, not that this case's subject regressed.
cleanup: none — all four are free validate calls. Nothing loads, queues, or is written.
runner: script
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
amended: 2026-11-26, suite review: the workspace-independent bullet said inline references are not existence-checked and the case carries no fixture, contradicting the amended third bullet (harnest#28, dw#494/#533)

### S-F038 — a media-less run directory is enumerable and deletable by name
S-F022 pins that a run which wrote no media can still be *deleted* by its
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
  #177 (verified) was `usage` lagging a delete; asserting on the listing's own
  `total` keeps this case independent of it. S-F021 and S-F022 are where `usage` is held to account.
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
   `stable-diffusion-v1-5/does-not-exist-qa269`). Since #1201 validate answers `valid: false`
   for it, with one error at `model_name` saying the repo "is not a model repo on Hugging
   Face", and still returns the `plan`: the repo is listed under `downloads_required` with
   `not_found: true`, and the bound acknowledgement must name it. (A hub lookup that is
   offline or times out leaves the entry unknown and the answer `valid: true`, as before; that
   is not a finding.) Validate's refusal does not stop the submit: run it anyway, since the
   failed job is what this step is for. Fails in the load, offline.
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
two sidecars, S-F022's shape), or delete the case's workspace.
metrics: none.
source: tester, verified in #269 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`, dw 0.4.0-beta.6 on `lem`: job `19fa559e8158` OOM'd at `at: 6.3` after
`generating` at `at: 4.8`, `seconds_in_phase: 1.4` on both `wait_for_job` and a later
`get_job`; job `c4dd43dd0787` failed loading with `progress.phase: "loading"`,
`seconds_in_phase: 0.9`. Case proposed by the implementer in its hand-off comment.
Amended 2026-11-20 (dkackman/harnest#271, approved by Don): step 3's validate answer follows
#1201 (a `model_name` the hub does not have is `valid: false`, no longer a plain
`downloads_required` entry); the run and its expectations are unchanged.

### S-F084 — the `workflow_end` event's manifest names files exactly as `get_job` and `step_end` do
#284: the last content event of a finished job, `workflow_end`, carried a `manifest[]`
whose `files` were absolute paths under the workspace's `outputs/` root, while `step_end`
in the same stream and `get_job`'s manifest gave the gallery-relative
`<workflow>/<run id>/<subfolder>/<file>` — so a consumer reading the final manifest off
the event stream had a name no output-side tool accepted. Cheap: one CPU-only inline run.
1. `run_workflow(inline_workflow=..., acknowledged_cost=true)` with three steps —
   `gather_images` of the shared fixture `asset:qa-cast/priya-portrait.jpg` (as its `urls` entry), then `canny` with
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
amended: 2026-11-26, suite review: the input is a server asset instead of a Hugging Face URL, so the case no longer needs the network; `get_task("gather_images")` documents `asset:` entries in `urls`, and the three-step workflow validates clean in `regression-smoke` (validated, not run)

### S-F085 — a `task.command` the engine does not register is refused by the free pre-flight
#285: `validate_workflow` said `valid: true` on a step whose `task.command` named nothing
the engine registers (the shipped `templates/image-processors` carried a `face_detector`
step), so the run did nine steps' worth of work before dying with the engine's own
"Unknown task command". The per-argument checks (S-F010) only ran once the command
resolved; a command that did not exist at all fell through silently. Free: two validate
calls, nothing runs.
1. `validate_workflow(inline_workflow={"id": "regression-bad-command", "steps": [{"name":
   "bad", "task": {"command": "nonexistent_processor", "arguments": {"strength": 0.5}}}]})`.
2. `validate_workflow(name="templates/image-processors")`.
expected:
- Step 1 is `valid: false` with exactly one error at `steps[0].task.command` whose message
  names `nonexistent_processor` and says it is not a registered task command — the
  refusal lands at the command, with no missing/unknown-argument complaint about
  `strength`. (The argument was `image: "x"` until dw#952 made validate refuse a bare
  media name on its own; `strength` is not a media key, so the one-error check still
  isolates the command refusal - harnest#151.)
- Step 2 is `valid: true`, and `plan.steps` equals the number of steps `get_workflow`
  reports for the template (25 as of #285) — the shipped template names only commands
  the engine registers.
It is a **finding** if step 1 comes back `valid: true`, or reports only argument-level
errors with no error at `steps[0].task.command`, or reports any error besides the one
at `steps[0].task.command`, or if step 2 reports any step's
`task.command` as unregistered.
cleanup: none — nothing is written.
runner: script
metrics: none.
source: tester, verified in #285 on 2026-09-21 over MCP as model `opus` via provider
`anthropic`: step 1 returned `'nonexistent_processor' is not a registered task command.
This step would fail at run time with the engine's own "Unknown task command" error` at
`steps[0].task.command`; step 2 returned `valid: true`, `plan.steps: 25`, and the
template then ran to `succeeded` 25/25 (job `a0e10ced3bad`).

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
runner: script
metrics: none.
source: tester, verified in #338 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`.

### S-F128 — an object or list sent to a string-typed variable is refused, not stringified
#433: coercion to a string-typed variable was a bare `str(v)`, which never raises. The old
`{"location": "asset:..."}` shape for `templates/ltx2/keyframes`' `first_image` (a plain
string since #431) validated clean. The run then failed on a path built from the dict's
repr. Free: no job is queued.
1. `validate_workflow(name="templates/ltx2/keyframes", arguments={"first_image":
   {"location": "asset:qa-cast/priya-portrait.jpg"}, "last_image":
   ["asset:qa-cast/hal-portrait.jpg"]})`.
2. `run_workflow(workflow_path="templates/ltx2/keyframes",` with the same arguments,
   `acknowledged_cost=true)`.
3. `validate_workflow(name="templates/ltx2/keyframes", arguments={"first_image":
   "asset:qa-cast/priya-portrait.jpg", "last_image": "asset:qa-cast/hal-portrait.jpg"})`.
expected:
- Step 1: `valid: false`, with one error at `arguments.first_image` and one at
  `arguments.last_image`. Each names the variable and the value and says it takes a plain
  string. Today's message ends `this variable takes a plain string (a URL, or an
  'asset:'/'output:' reference), not an object`.
- Step 2: refused before queueing, with the same two errors. No `job_id`.
- Step 3: `valid: true`, no errors, both images in `checked_arguments`.
It is a **finding** if step 1 validates or step 2 queues a job, because an object would
again reach a string variable as its repr. It is also a finding if step 3 is refused, which
would mean the guard catches the intended string form too.
cleanup: none. Nothing is queued or written.
runner: script
metrics: none.
source: tester, verified in #433 on 2026-09-25 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ b055573`.

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
runner: script
metrics: none.
source: tester, verified in #345 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`. All four came back as expected above.
Step 2 quoted 71.6 GB. (The issue's original `QwenImage21Pipeline` repro now validates
correctly: `get_class` shows lem's diffusers exports that class, so this case uses a
misspelling instead.)

### S-F116 — `get_task` describes the three frame-grab commands, each with its own summary
Before #366, `get_task("get_frame")` returned an empty `summary` and no parameter
descriptions. Nothing said that `frame_index` is 0-based or that a negative value counts
from the end. `get_first_frame` and `get_last_frame` share `get_frame`'s implementation.
Free: three discovery calls, nothing runs.
1. `get_task("get_frame")`.
2. `get_task("get_first_frame")`.
3. `get_task("get_last_frame")`.
expected:
- All three: a non-empty `summary`, and all three summaries differ from each other.
  Step 2's names the first frame and step 3's names the last. `video` has a non-empty
  `description` saying what it accepts (frame list/array/tensor, AudioVideo, file reference).
- Step 1: `frame_index` (default 0) has a `description` saying it is 0-based and that
  negative indexes count from the end.
- Steps 2 and 3: `frame_index` is absent because it is pinned. `parameters` is `video` and
  `device`.
It is a **finding** if any summary is empty, if steps 2 and 3 share a summary with each other
or with step 1, or if `video`/`frame_index` lose their descriptions.
cleanup: none — nothing is written.
metrics: none.
source: tester, verified in #366 on 2026-09-22 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ e5bfb9e`.

### S-F117 — a null-seeded catalog entry reports the seed it drew, replays from it, and takes `new_seed`
The catalog convention (#351) is `"seed": "variable:seed"` on every generative entry.
An unseeded entry declares `variables.seed: null`, so every run draws a fresh seed, and a
caller can only get a take back if the run reports the seed it drew. Before #351,
`rerun_job(new_seed=true)` also refused any entry whose seed didn't come from a
variable. `templates/text-to-image` (SD 1.5, ~10 s a run) is the cheap member of that group.
expected:
- `get_workflow("templates/text-to-image", variables_only=true)` → `variables.seed: null`
  and top-level `"seed": "variable:seed"`.
- `run_workflow(workflow_path="templates/text-to-image", workspace="regression-smoke",
  acknowledged_cost=true, wait_seconds=55)` → `succeeded`. `get_job_workflow(<job>)` →
  `realized: true`, `seed_variable: "seed"`, and an integer `workflow.seed` equal to
  `workflow.variables.seed` (call it S).
- The same run with `arguments={"seed": S}` → `succeeded`, and its image is the same
  picture as the first run (same `bytes` from `get_output_image(max_dimension=256)`
  on both).
- `rerun_job(<first job>, new_seed=true, acknowledged_cost=true)` → queued with
  `arguments.seed` an integer ≠ S, and `wait_for_job` → `succeeded`.
It is a **finding** if the entry has lost `variable:seed`, the realized seed is null or
missing, the replay differs, or `new_seed` refuses.
cleanup: `delete_output(job_id=…)` for all three jobs.
metrics: none.
source: tester, verified in #351 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7` (jobs `543804adb1fe`, `fd89268291d1`,
`32398232dba4`, run in `default`; the pinned half, `templates/ltx2/text-to-video` realizing
42 and taking `new_seed`, was also checked but is too slow for smoke).

### S-F124 — an unknown workflow name suggests the catalog entry it's a suffix or typo of
#397: `get_workflow(name="dialogue-short")` used to answer a bare `Unknown workflow`, though
the catalog holds `templates/minimax/dialogue-short`. The error now appends a suggestion for a
unique path suffix or a close spelling match. Free: no job is queued.
1. `get_workflow(name="dialogue-short", variables_only=true)` (unique suffix).
2. `get_workflow(name="dialog-short", variables_only=true)` (typo on the short name).
3. `validate_workflow(name="dialog-short")`.
4. `get_workflow(name="music-vidoe", variables_only=true)` (typo with more than one near match).
5. `get_workflow(name="zzqq-nothing-like-this", variables_only=true)`.
expected:
- Steps 1–2: error `Unknown workflow: <name> - did you mean templates/minimax/dialogue-short?`.
- Step 3: error ending `... - did you mean templates/minimax/dialogue-short?`.
- Step 4: error with `did you mean one of:` naming at least `templates/minimax/music-video`.
- Step 5: plain `Unknown workflow: zzqq-nothing-like-this`, with no `did you mean`.
It is a **finding** if steps 1–4 leave out the suggestion, or if step 5 invents one.
cleanup: none. Nothing is queued or written.
runner: script
metrics: none.
source: tester, verified in #397 on 2026-09-24 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 9fed519`.

### S-F125 — a `dissolve_frames` longer than a known input clip is refused by the free pre-flight
#400: `dissolve_videos` used to validate clean when a literal `dissolve_frames` was longer than
an `asset:` input's real frame count, and then fail at run time. A middle clip needs room
for two dissolves, and an input whose length isn't known before the run (`previous_result:`)
is left alone. Free: no job is queued. Every call is `validate_workflow(workspace="regression-smoke",
workflow={"id": "s-dissolve", "seed": 1, "steps": [<steps>]})`, and each step is
`{"name": ..., "task": {"command": "dissolve_videos", "arguments": {"videos": [...],
"dissolve_frames": N, "fps": 24}}, "result": {"content_type": "video/mp4"}}`. A = `asset:qa-cast/ep42-shot1-accuse.mp4`,
B = `asset:qa-cast/ep42-shot2-deflect.mp4` (124 f each).
1. One step, videos `[A, B]`, `dissolve_frames: 130`.
2. One step, videos `[A, B]`, `dissolve_frames: 12`.
3. One step, videos `[A, B, A]`, `dissolve_frames: 70`.
4. Two steps: `src` = videos `[A, B]`, 12. Then `film` = videos `["previous_result:src", B]`, 130.
expected:
- Step 1: `valid: false`, one error at `steps[0].task.arguments.dissolve_frames` naming
  both `video 0 has 124 frames, too few for its 1 dissolve(s) of 130 frames` and the same
  for `video 1`.
- Step 2: `valid: true`, no errors.
- Step 3: `valid: false`, and only `video 1 has 124 frames, too few for its 2 dissolve(s) of 70
  frames` (videos 0 and 2 need only 70).
- Step 4: `valid: false` at `steps[1].task.arguments.dissolve_frames` naming only `video 1`.
  The `previous_result:` entry is not flagged.
It is a **finding** if step 1 or 3 validates clean, if step 2 or step 4's `video 0` is flagged,
or if the error lands at a different path.
cleanup: none. Nothing is queued or written.
runner: script
metrics: none.
source: tester, verified in #400 on 2026-09-24 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 0fd6043`.

### S-F126 — `gain_audio` with a frame region gains only that region, and logs the samples it covered
C-F1519 covers the whole-track form. A shot-sized region given as `start_frame`/`num_frames`/`fps`
is how one shot of a cut gets rebalanced. A region that lands somewhere else, or gets ignored,
still succeeds silently. Cheap: one ~3 s utility job, no model load.
Validate, then run (`workspace="regression-smoke"`, `acknowledged_cost=<plan>`,
`wait_seconds=55`) one inline workflow with `"seed": 1`:
`lift` = `gain_audio(audio="asset:qa-cast/ep45-episode.mp4", gain_db=3, start_frame=224,
num_frames=124, fps=24)`, result `audio/wav`. Then `get_job_events` on the job.
expected:
- `validate_workflow` is `valid: true`, and the job succeeds.
- A `log` event with `command: "gain_audio"`, `gain_db: 3`, `sample_rate: 32000`,
  `start_sample` 298666 or 298667 (224 × 32000/24 = 298666.67, and the floor-vs-round
  choice is #401), and `end_sample: 464000` (the asset's 348 f end). `start_seconds` is ≈9.333 and
  `duration_seconds` ≈5.167.
It is a **finding** if the job fails, if there is no such log event, or if the logged region
starts at 0 or ends anywhere but 464000. Either of those means the frame arguments were
dropped or misconverted.
cleanup: `delete_output(job_id=<job>)`.
metrics: none.
source: tester, found while running TESTER_TASK.agent.md (ep48), on 2026-09-24 over MCP as
model `claude-opus-5-5` via provider `anthropic`, job `d72297d8719b` in `qa-ep48` (step
`dry_s3`, run there after a whole-track −6 dB step, which doesn't affect the logged region).

### S-F129 — `save_workflow`/`delete_workflow`/`upload_asset`/`delete_asset` honour a per-call `workspace=`, and their replies name it
#463: with no `workspace=`, `delete_workflow` acted on the shared session pin. It deleted the
good copy in one workspace while the stray in another survived, and its reply didn't say where.
Free: no job is queued. Make two throwaway workspaces, `s-f129-a` and `s-f129-b`
(`create_workspace("s-f129-b", use=true)`), so the session is pinned to B. W is a one-step
workflow `{"id": "s-f129", "variables": {"marker": "<X>"}, "steps": [{"name": "s", "task":
{"command": "compose_text", "arguments": {"parts": ["variable:marker"]}}}]}`.
1. `save_workflow("s-f129", workflow=W with marker "B")`, with no `workspace=`.
2. `save_workflow("s-f129", workflow=W with marker "A", workspace="s-f129-a")`.
3. `delete_workflow("s-f129", workspace="s-f129-a")`, then `get_workflow("s-f129",
   variables_only=true)`, still pinned to B.
4. `delete_workflow("s-f129", workspace="s-f129-a")` again.
5. `upload_asset(content=<any tiny base64 PNG>, asset_name="px.png", workspace="s-f129-a")`,
   then the same upload with no `workspace=`.
6. `delete_asset("uploads/px.png", workspace="s-f129-a")`, then `list_assets(workspace="s-f129-a")`
   and `list_assets()`.
7. `delete_workflow("s-f129")` and `delete_asset("uploads/px.png")`, with no `workspace=`.
expected:
- 1: `workspace: "s-f129-b"`, `origin: "workspace"`, and no `path` or absolute server path (dw#527).
- 2: `workspace: "s-f129-a"`, `origin: "workspace"`, and no `path` or absolute server path.
- 3: the delete returns `workspace: "s-f129-a"`, `name: "s-f129"`, `origin: "workspace"` and
  `deleted: true`, and no server path (#521). `get_workflow` still answers `marker: "B"`.
- 4: `Unknown workflow`. It never falls through to B's copy.
- 5: the replies name `s-f129-a` and `s-f129-b` respectively.
- 6: the delete returns `workspace: "s-f129-a"` and `reference: "asset:uploads/px.png"`. A's listing
  no longer has `uploads/px.png`. B's (pinned) still lists it with `origin: "workspace"`.
- 7: both replies name `workspace: "s-f129-b"`. Omitting `workspace=` follows the pin.
It is a **finding** if any `workspace=` call touches the pinned workspace, or if a save or delete reply
omits `workspace` or carries an absolute server path. (Delete replies amended per
harnest#29, dw#534: Don, 2026-09-27, 0.5.0 release.)
cleanup: `use_workspace("regression-smoke")`, then `delete_workspace` both `s-f129-*` with
`acknowledged_cost=true`.
metrics: none.
source: tester, verified in #463 on 2026-09-26 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 3e8bf8d` (mps on Mac-mini.lan).

### S-F130 — a keyed media reference that resolves to null is refused by the free pre-flight; one inside a list is not
#478: `validate_workflow` passed a `for_each` item whose references held a dict-keyed object
with a null `from_file`. The run's prepare step then failed with "'ref_b' names an object to
build but the media it would be built from is null". A null inside a *list* is different: the
run drops it on purpose, and that is how a template makes a reference optional. Free: no job is
queued. Every call is `validate_workflow(name="templates/minimax/dialogue-short",
workspace="regression-smoke", arguments={"shots": [{"name": "s1", "num_frames": 124, "prompt":
"a man talks", "references": R}]})`, where A = `{"reference_type":
"variable:subject_reference_type", "from_previous_result": "draw_character_a"}`.
1. R = `{"ref_a": A, "ref_b": {"reference_type": "variable:subject_reference_type",
   "from_file": null}}`.
2. R = `[A, {"reference_type": "variable:subject_reference_type", "from_file": null}]`.
3. R = `{"ref_a": A, "voice": {"reference_type": "variable:voice_reference_type", "from_file":
   "variable:character_a_voice"}}`. That variable defaults to null.
expected:
- Call 1: `valid: false`, one error at `steps[<n>].pipeline.arguments.references.ref_b.from_file`.
  Its message names `'ref_b'`, "the media it would be built from is null", and member `shot@s1`.
- Call 2: `valid: true`, no errors.
- Call 3: `valid: false`, the same error at `...references.voice.from_file`. A null reached
  through a `variable:` is caught too.
It is a **finding** if call 1 or 3 validates, or if call 2 is refused. The template's own default
shots depend on a null inside a list being dropped silently.
cleanup: none. Nothing is queued or written.
runner: script
metrics: none.
source: tester, verified in #478 on 2026-09-26 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 3e8bf8d`.

### S-F132 — a frame-size mismatch between known join inputs is refused by the free pre-flight
#504: `dissolve_videos`/`concat_videos` used to validate clean on `asset:` videos of different
sizes and then fail at run time. Nothing reconciles a size mismatch the way a sample-rate one is
resampled. Free: no job is queued. Every call is `validate_workflow(workspace="regression-smoke",
workflow={"id": "s-join-size", "steps": [{"name": "join", "task": {"command": <cmd>, "arguments":
{"videos": [...]}}, "result": {"content_type": "video/mp4"}}]})`. A = `asset:qa-cast/ep62-shot1-accuse.mp4`
(960x544), B = `asset:qa-cast/ep62-shot2-deflect.mp4` (960x544), L = `asset:qa-cast/ep75-shot-ltx2stage-hal.mp4`
(1536x896).
1. `concat_videos`, videos `[A, L]`.
2. `dissolve_videos`, videos `[A, L, B]`.
3. `concat_videos`, videos `[A, B]`.
expected:
- Step 1: `valid: false`, one error at `steps[0].task.arguments.videos`: `concat_videos needs every
  video at one size: video 0 is 960x544, video 1 is 1536x896`.
- Step 2: the same error at the same path, naming `dissolve_videos`.
- Step 3: `valid: true`, no errors.
It is a **finding** if step 1 or 2 validates clean, if step 3 is flagged, or if the error lands at
a different path.
cleanup: none. Nothing is queued or written.
runner: script
metrics: none.
source: tester, verified in #504 on 2026-09-27 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ b8fd862`.

### S-F140 — a recreated workspace does not inherit the deleted one's job history
`delete_workspace` used to leave the workspace's jobs in job history. A later workspace with
the same name then listed them under `list_jobs(workspace=X)` as `historical: true` (#913).
Each run below is `templates/image-processors`, about 12–40 s, with no inputs. Get the plan
from `validate_workflow(name="templates/image-processors", workspace="regression-smoke-913")`
and pass it as `acknowledged_cost`, with `wait_seconds=55`.
1. `create_workspace("regression-smoke-913")`, run one job in it (`workspace=` pinned), and
   note its id as J1.
2. `delete_workspace("regression-smoke-913", acknowledged_cost=true)`.
3. `create_workspace("regression-smoke-913")` again, then `list_jobs(workspace="regression-smoke-913")`.
4. Run one job in it (J2), then `list_jobs(workspace="regression-smoke-913")` and `get_job(J1)`.
expected:
- Both jobs succeed.
- Call 3 returns `total: 0`.
- Call 4's listing has `total: 1`, and that job is J2. `get_job(J1)` answers with
  `historical: true` and `workspace: "regression-smoke-913 (deleted)"` (#944).
It is a **finding** if J1 shows up in either listing, with or without `historical: true`, or if
`get_job(J1)` errors `Unknown job`.
cleanup: `delete_workspace("regression-smoke-913", acknowledged_cost=true)`. Confirm
`list_workspaces` no longer has it.
metrics: none.
source: tester, verified in #913 on 2026-10-14 over MCP as model `claude-opus-5-5` via provider
`anthropic` against `develop @ 9dfb9e6c` on `lem` (cuda).

### S-F145 — an object or list sent to a bool-typed variable is refused, not folded to `true`
The bool counterpart of S-F128 and S-F108. A variable's type comes from its default, and a
dict sent to a bool-defaulted variable used to become `true` via `bool(dict)`, with no warning
(#1250). `templates/ltx2/chained-segments`' `look_hold: {"precompensate": true}` validated
clean and then ran all four corrections. Free: no job is queued. `<img>` is any image this
workspace can reach (an `asset:` or `output:` still). Verification used
`output:grey_keyframe/20261107-195328-00ce62a2/grey_keyframe-grey.0-0.0.png`.
1. `validate_workflow(name="templates/ltx2/chained-segments", arguments={"image": <img>,
   "look_hold": {"precompensate": true}, "segments": 3, "num_frames": 49, "width": 512,
   "height": 512, "seed": 1242})`.
2. The same validate call with `"look_hold": ["precompensate"]`.
3. `run_workflow(workflow_path="templates/ltx2/chained-segments",` with step 1's arguments,
   `acknowledged_cost=true)`.
4. The same validate call with `"look_hold": "off"`.
expected:
- Steps 1 and 2: `valid: false`, with an error at `arguments.look_hold` that names the
  variable, the value and its bool type. Today's message ends `this variable is typed bool by
  its default and takes true or false, not an object or list`.
- Step 3: refused before queueing, with the same message. No `job_id`, and no new job in
  `list_jobs`.
- Step 4: `valid: true` with a plan. The existing string spellings still coerce.
It is a **finding** if step 1 or 2 validates, or step 3 queues a job, because an object would
again run as `true` without a word. It is also a finding if step 4 is refused.
cleanup: none. Nothing is queued or written.
runner: script
metrics: none.
source: tester, verified in #1250 on 2026-11-07 over MCP as model `claude-opus-5-5` via provider
`anthropic` against `develop @ 6db8d963` on `mini-ai` (mps).

### S-F147 — an H3 video reference shorter than the encoder's minimum is refused at validate
An H3 `MiniMaxH3VideoReference` must run a minimum number of frames, which comes from
diffusers' encoder. Validation used to pass a shorter one, so it failed only at run time, after
the chain's earlier steps had spent their GPU time (#1422). Free apart from one short
utility job. `<vid>` is a video asset at 24 fps with at least 113 frames.
Verification used `asset:qa-cast/priya-hal-two-shot.mp4` (121 frames). `<img>` is any image
asset: use `asset:qa-cast/priya-portrait.jpg` (Fixtures). `<H3>` is a `pipeline` step with
`from_pretrained_arguments={"model_name": "MiniMaxAI/MiniMax-H3", "workflow": "ref2va"}`,
`configuration={"component_type": "ModularPipeline"}`, `num_frames` 124, 960x544, 9 steps,
`output: ["videos","audio","sampling_rate"]`, and
`references: [{"reference_type": "diffusers.modular_pipelines.minimax_h3.MiniMaxH3ImageReference", "from_file": <img>}, <video ref>]`.
The key is `reference_type` and the value is the full dotted path; an entry spelled any other
way is not a reference and is not measured.
1. Inline workflow: step `window` =
   `trim_video(video=<vid>, start_frame=100, num_frames="variable:num_window")`, then `<H3>` with
   `<video ref>` =
   `{"reference_type": "diffusers.modular_pipelines.minimax_h3.MiniMaxH3VideoReference", "from_previous_result": "window", "audio": null}`.
   `validate_workflow` it with `arguments={"num_window": 5}`, then `12`, then `13`.
2. The same workflow with literal `num_frames: 5, pad_to: 13` in the trim step.
3. Run a task-only workflow, `trim_video(video=<vid>, start_frame=100, num_frames=5)`, which
   writes `<short>`. Then validate a single `<H3>` step with `<video ref>` =
   `{"reference_type": "diffusers.modular_pipelines.minimax_h3.MiniMaxH3VideoReference", "from_file": "output:<short>"}`,
   and again with `"from_file": <vid>`.
expected:
- Step 1: `5` and `12` give `valid: false` at `steps[1].pipeline.arguments.references[1]`. The
  message is the encoder's own and gives the minimum. Today's reads `...must run at least 13
  frames at 24 fps (0.54 seconds), got 5 frames at 24 fps.` The value just below the minimum is
  refused. The minimum itself (`13` today) gives `valid: true` with no reference-length error.
- Step 2: `valid: true`, because `pad_to` lengthens the window to the minimum.
- Step 3: the `output:<short>` reference gives `valid: false` at
  `steps[0].pipeline.arguments.references[1]` with the same message, `got 5 frames`. `<vid>` gives
  `valid: true`.
It is a **finding** if a window below the minimum validates, because it then fails only after
queueing. It is also a finding if the minimum itself, or a `pad_to` window, is refused. If the
encoder's minimum ever changes, take the new lengths from its message, not from this text.
cleanup: `delete_output(job_id=<step 3's job>)`.
metrics: none.
source: tester, verified in #1422 on 2026-11-17 over MCP as model `claude-opus-5-5` via provider
`anthropic` against `develop @ 7c2c39c9` on `mini-ai` (mps).
Amended 2026-11-20 (dkackman/harnest#272, approved by Don): the reference entries are spelled
out with `reference_type` and the full dotted path, and `<img>` names a fixture asset (the
verification's `asset:uploads/cast/loki.jpg` is not on lem).

### S-F148 — leaving out `arguments` does not skip the required-variable check, at validate or at submit
Validate is the free check a caller runs before quoting a price. With `arguments` left out
entirely, as opposed to `arguments={}`, it used to skip the `required` rule. It then answered
`valid: true` with a plan and estimate for a run that could not happen (#1758). Free: no job
queues.
1. `validate_workflow(name="templates/voice-clone", workspace="regression-smoke")`, with no
   `arguments` at all, and again with `arguments={}`.
2. `validate_workflow(workflow_path="templates/minimax/h3-seam-pass", workspace="regression-smoke")`,
   with no `arguments`.
3. `run_workflow(workflow_path="templates/voice-clone", acknowledged_cost=true,
   workspace="regression-smoke")`, with no `arguments`, then
   `list_jobs(workspace="regression-smoke", limit=3)`.
4. `validate_workflow(name="templates/preferred/text-to-image", workspace="regression-smoke")`,
   with no `arguments`.
expected:
- Step 1: both calls give `valid: false`, with the same error at `variables.reference_audio`
  saying it is required and has no default, and no `plan`.
- Step 2: `valid: false` at `variables.source` (required, no default), and no `plan`.
- Step 3: the call is refused with the `reference_audio` required message, and `list_jobs`
  shows no job from it.
- Step 4: `valid: true` with a `plan`, because a template with no required variable still
  validates with `arguments` left out.
It is a **finding** if step 1's or step 2's call with `arguments` left out validates, or prices
a plan, or if step 3 queues a job. It is also a finding if step 4 is refused.
cleanup: none (nothing queues; if step 3 did queue, `cancel_job` it and `delete_output(job_id=...)`).
metrics: none.
source: tester, verified in #1758 on 2026-11-26 over MCP as model `claude-opus-5-5` via provider
`anthropic` against `develop @ 009256f1` on `lem`.

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

### S-P003 — tool/template discovery latency
Time S-F002 (the tools/templates list call), cold — i.e. as the first call of
the run, before anything else warms up server-side caches. Consumer-side wall
clock (`condition: wall`), same caveat as S-F006; no cold server-side penalty
has been seen to date (the same call later in a run is indistinguishable), so
a real one appearing is worth a note even under the noise band.
baseline: TBD — the log is the baseline.
cleanup: none (read-only).
