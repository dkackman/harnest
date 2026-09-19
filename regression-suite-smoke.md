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
  that, so the slice never reaches the end and pads. Read-only — never sliced in
  place, never deleted.
- `asset:qa-cast/ep13-episode.mp4` — a 282-frame 24 fps 960x544 stereo 44.1 kHz
  episode in the shared asset library. S-F031 muxes a soundtrack onto it twice; its
  known geometry is what says the mux moved only the audio. Read-only.
- `asset:qa-cast/ep15-song.mp3` — a 30.0 s 44.1 kHz stereo Music 3 track that decodes
  at **+0.76 dBFS**, i.e. with no headroom. S-F031's positive control depends on that:
  it is the clipping exhibit from #158/#159, not just a song, so replacing it with a
  quieter track silently disarms the case. Read-only — never normalized in place,
  never deleted.
- `asset:qa-cast/ep6-cold-open.mp4` and `asset:qa-cast/ep3-shot2-reply.mp4` — two
  124-frame 24 fps 960x544 32 kHz stereo shots in the shared asset library. S-F045
  joins them in that order because the first has the loudest outgoing tail among the
  shared shots (last full second −20.5 dBFS RMS) and the second the quietest head
  (first second −44.4 dBFS RMS), which is what makes a bled tail measurable against
  the incoming material. Both also serve the `complete` suite; read-only, never
  deleted. Any substitute pair needs the same loud-tail-into-quiet-head shape, re-read
  from `get_gallery_metadata(envelope=true)` on the assets.
- `asset:qa-cast/ep11-coldopen.mp4` — a video with a soundtrack in the shared asset
  library (peak −1.04 dBFS, RMS −20.9 dBFS as `analyze_audio` reads it). S-F051 hands
  it to `analyze_audio` as the "video in, soundtrack measured" input shape; any
  substitute just needs a non-silent soundtrack. Read-only, never deleted.
- `asset:qa-cast/ep20-score.wav` — a ~10.3 s score bed in the shared asset library.
  S-F057 and S-F068 pass it as `score` to the two sequence templates; a `total_frames`
  longer than it draws a `slice_past_end` warning, which those cases either expect or
  avoid by choosing `total_frames` ≤ 248. Read-only, never deleted.

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
expected: `validate_workflow` on any inline workflow with **no top-level `seed`** →
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
`pair_audio` workflow, warning present then absent.

### S-F017 — a step object is closed: an unknown step-level property is an error
A key the engine never reads is the worst kind of mistake, because the workflow
runs and the key does nothing. `validate_workflow` must refuse an unknown
property on a `step`, on a `task`, on a `pipeline_reference` and on a
`workflow_reference`. Free and instant — no run.
expected: an inline one-step workflow whose step carries invented control-flow
keys and a misspelled real one — `"when": "always"`, `"retry": 3`,
`"relase_pipeline": true` — comes back `valid: false` with **one** error at
`steps[0]` naming **all three** properties at once, naming the step
(`"probe"`), and listing the legal set (`for_each, name, pipeline,
pipeline_reference, release_models, release_pipeline, result, seed, task,
workflow`). Separately, a `task` spelled `{"name": ..., "parameters": ...}`
instead of `{"command": ..., "arguments": ...}` → `valid: false` naming
`"name"`, `"parameters"` and the legal set `arguments, command, inputs`.
Control: the same workflow with the unknown keys removed → `valid: true`.
It is a **finding** if any unknown key comes back `valid: true`, if only the
first of several is reported (a multi-typo file must be one round trip), or if
the message stops listing the legal set — that list is what makes
`relase_pipeline` self-answering.
cleanup: none (read-only).
source: tester, verified in #118 on 2026-09-13 over MCP as model `opus` via
provider `anthropic`, workspace `qa-ep7`, dw 0.4.0-beta.3.

### S-F018 — the other three workflow objects are closed too
S-F017 covers the `step`, `task`, `pipeline_reference` and `workflow_reference`
objects. The same guarantee must hold for the three that were still open after it:
the **top-level workflow** object, the **`result`** object, and the **`pipeline`**
object. A stray key in any of them is the same failure S-F017 exists for — the
workflow runs and the key does nothing. Free and instant — no run.
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
  as an unknown file, naming the `..` pattern. Nothing outside this workspace's
  `outputs/` is reachable, and the refusal is a 404-shaped error, not a partial
  delete.
- `delete_output(name="<workflow>/not-a-run-id")` → refused as a path that does not
  exist. A name that is not a run id must never be treated as "delete this
  directory tree" — that is the failure mode that would turn a typo into a
  workspace wipe.
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
issue — so that path is exercised against runs that did write media.

### S-F023 — a safety-checker blanking is announced, and the reference template is out of its path
SD 1.5's NSFW safety checker false-positives on ordinary prompts for particular
seeds and replaces the image with a solid black one. Until #133 the engine knew
and said so only in the server's own log, so a job came back `succeeded`, no
warnings, manifest populated, valid JPEG, and pure black — the exact failure an
unattended consumer cannot catch, since every signal it has says the run is fine.
Two things were fixed and both need pinning; ~13 s total on a 3090, no new assets.
expected:
- **The warning fires.** `run_workflow(inline_workflow=…)` with SD 1.5
  (`StableDiffusionPipeline`, `model_name: "stable-diffusion-v1-5/stable-diffusion-v1-5"`,
  `torch_dtype: "torch.float32"`), top-level `seed: 3220371727974403`, prompt
  `"an apple"`, `num_inference_steps: 25`, and **no** `safety_checker` key →
  `status: "succeeded"` and `warnings` containing an entry matching
  `safety checker blanked`. An empty `warnings` here is the regression, and it is
  invisible any other way. The seed is load-bearing: it is the one that reproduces,
  and a fresh seed usually will not.
- **The escape hatch works.** The same call with `"safety_checker": null` added to
  `from_pretrained_arguments` → `status: "succeeded"`, `warnings: []`.
- **The image is actually an image.** `get_output_image` on that second run's
  output is not black — at 192 px it is a recognisable apple. Assert this, not just
  the empty `warnings`: a regression that blanks everything regardless of the
  checker would satisfy both lines above, and the empty-warnings assertion would
  then be *hiding* the failure rather than catching it. (Corollary worth knowing
  when reading a failure here: same seed, same steps, same prompt, checker off →
  apple; checker on → black. The latents were never the problem.)
- **The template is out of the path.** `get_workflow(name="templates/text-to-image")`
  → its `from_pretrained_arguments` carries `"safety_checker": null`. The reference
  "hello world" of the catalog, and the cheap generation step several other cases
  lean on, must not have a silent content filter in it.
cleanup: `delete_output` both runs' images; each sweeps its run directory.
source: tester, model `opus` via provider `anthropic`, verified in #133 on
2026-09-13 against dw 0.4.0-beta.3 on `lem` (jobs `2f7d2fb743f8` — blanked, warned,
6.2 s — and `3a1545cc713c` — same seed, checker off, clean apple, 6.3 s). Found by
the regression agent while running S-F009.

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
  library) with `target_sample_rate: "variable:rate"` and
  `arguments={"rate": 0}`. The job must **fail** — `status: "failed"`,
  `manifest: []`, `error` naming `target_sample_rate` — and must not succeed.
  This is the layer that produced #140's wrong deliverable, since the rate there
  came from a `variable:` inside a chain. (`validate_workflow` on that same body
  with the same `arguments` also refuses, because the static pass substitutes
  caller arguments; both refusing is the expected result, and a refusal at
  either layer alone is a partial fix worth a finding.)
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
moved ~0.007 dB, i.e. a real filter ran rather than a relabel.

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
  not smoothed into a median — `templates/minimax/music-video` answers exactly that
  (25.8 minutes over 1 run). A basis of `observed` with `runs` absent or null is a
  finding: it is the field that tells a caller how much the figure is worth.
- **Off the recorded bucket, it falls back rather than lying.**
  `validate_workflow(name="templates/minimax/storyboard", arguments={"num_frames":
  345})` → `basis: "catalog"` (the curated figure, `minutes: 10.1`, `measured_on:
  "RTX 3090"`) and **`runs: null`**. Resizing away from the driver values the history
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
shape is the failure that would survive the implementer's own case.

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
- **The raw branch warns twice, by design, and both name the file.** `job.warnings`
  carries exactly two entries for `raw_mux`, both naming that step's mp4: an
  `audio_no_headroom` pre-encode warning, at a peak at or above **-0.5 dBFS**,
  advising `normalize_audio(peak_dbfs: -1)`; and an `audio_clipped` post-encode
  warning on the written file, advising `normalize_audio(peak_dbfs: -3)`. The two
  giving different advice is expected (#174/#161) — the pre-encode figure predates
  the post-encode probe's more conservative one — not a defect to flag. Either
  warning going silent is the regression to watch for: the pre-encode one silent
  means the waveform-level check stopped firing; the post-encode one silent means
  the written-file probe stopped firing, and a video mux's overshoot is not
  reliably positive enough to skip that check the way a plain audio save can (#174).
- **The normalized branch does not warn.** No `job.warnings` entry names `balanced_mux`.
  A warning on both branches means the check is measuring something other than the
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
only a saved audio file) with a real MCP call rather than a description.

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
  (`target_sample_rate` arriving as 0 through a `variable:`; fails in ~1.3 s,
  `manifest: []`) and delete it the same way → `deleted: true`, `run_swept` the run id.
  Two different failure layers, because a form wired only into the pipeline path would
  pass the first bullet alone.
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
S-F017/S-F018 pin that an *unknown key* on a workflow object is an error. This is the
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

### S-F039 — `usage` moves the moment a delete lands, not 60 s later
`list_workspaces().usage` is the "did my cleanup actually free anything" signal every
`cleanup:` line in this file leans on, and the regression agent's end-of-run sweep
asserts on it. It is a cached disk glance with a short TTL, so the number is only
trustworthy if every call that *changes* the tree drops that cache: before #177 it
did not, and three consecutive `delete_output` calls left `usage` byte-for-byte
identical, which reads from the consumer side as "the delete failed" or "something
leaked". The TTL itself is by design and is not what this case pins — a running job's
own writes are still allowed to lag. What is pinned is that an explicit delete is
reflected immediately. Cheap: pure listing plus deletes of things that are already
litter.
expected:
- **A delete moves the number.** In a workspace holding at least one deletable run,
  record `usage.{files,bytes}` from `list_workspaces()`, call `delete_output(name=<a
  run dir or file in that workspace>, workspace=<same>)` → `deleted: true`, then call
  `list_workspaces()` again **with no wait** — `files` and `bytes` for that workspace
  are both strictly lower. Unchanged figures are the finding; there is no acceptable
  amount of delay here short of the next call.
- **Every delete, not just the first.** Immediately after that read (which has
  repopulated the cache), delete a second run and re-read. The figures must move
  again. A fix that invalidates once, or one that merely happened to coincide with
  natural expiry, passes the first bullet and fails this one — run both.
- **The invalidation is scoped.** Across those same responses, every *other*
  workspace's `usage` block is unchanged. Dropping the whole cache on any delete
  would also pass the bullets above while making the figure churn for workspaces
  nothing touched.
- The drop should be consistent with what was removed (deleting a two-file
  media-less run takes `files` down by 2), but assert on the direction and on the
  delete's own `run_swept`/`deleted` fields rather than on exact byte counts — a
  concurrent job in that workspace can move `bytes` underneath the comparison.
cleanup: it is cleanup — pick the runs to delete from `list_gallery(only_orphans=true,
workspace=<this suite's own workspace>)`, which are litter by definition, and never
delete in a workspace outside this suite's own. Two runs is enough; nothing to
create, so nothing left behind.
metrics: none. `usage.files`/`usage.bytes` are a property of whatever the workspace
happens to hold that day, not a trend worth a `regression-perf/` file — the assertion
is the delta, and it is local to one run of the case.
source: tester, model `opus` via provider `anthropic`, verified in #177 on 2026-09-16
against dw on `lem`, workspace `regression-smoke`: `{files: 38, bytes: 31573}` →
delete `s-f007/20260913-232036-c058d295` → `{36, 29500}` on the very next call →
delete `s-f007/20260913-232117-1afca25d` → `{34, 27385}`, with all other workspaces'
figures identical throughout. Proposed by the implementer in its hand-off comment
(record `usage`, delete, re-read immediately); the second-delete-inside-the-TTL
bullet, the scoping bullet and the "assert the direction, not the byte count" note
are mine, from what that session ran. S-F038 deliberately refuses to assert on
`usage` because #177 was open when it was written — this is the case that holds
`usage` to account instead, alongside S-F021 and S-F034. Only `delete_output` is
covered here; the same invalidation on `delete_workflow`/`delete_prompt`/
`delete_asset` is claimed by #177's fix but was not exercised over MCP, since the
only candidates in this workspace are durable fixtures.

### S-F040 — a validated document runs without renaming a key
The server instructions describe validate→run as one loop, but the two halves used
four parameter names for two concepts: `validate_workflow` took `workflow`/`name`
while `run_workflow` took `inline_workflow`/`workflow_path`, each tool internally
consistent and mutually silent about the other. Carrying a document straight from a
`valid: true` answer into the run call therefore failed with "Provide exactly one
of" — a guaranteed wasted round trip for every agent that follows the documented
loop for the first time, and the kind of thing that gets papered over with a
"remember to rename the key" note in a memory file. #179 fixed it additively, with
both tools accepting both spellings; this case pins the round trip *and* the
exactly-one-of enforcement that an additive alias is the natural way to break.
Cheap: one 8-step SD 1.5 run (~12 s on a 3090) plus free pre-flight calls.
expected:
- **The round trip needs no edit.** `validate_workflow(workflow=<minimal valid
  inline definition>)` → `valid: true` with a `plan.fingerprint`; then
  `run_workflow(workflow=<the same JSON, unchanged>, acknowledged_cost={fingerprint,
  minutes, downloads})` → a job id, **not** a "Provide exactly one of" error. Then
  `wait_for_job` → `succeeded` with a populated manifest. Assert the run reached
  `succeeded`, not just that the call was accepted: a signature that takes the alias
  and then drops it on the floor passes an acceptance-only assertion.
- **Both aliases, both directions.** `validate_workflow(workflow_path=<a stored
  workflow name>)` → `valid: true` with a real plan (an `estimate` for a workflow
  this box has run, not a parse error) — the alias has to resolve to the catalog
  lookup, not to an inline-parse attempt. And `run_workflow(name=<the same stored
  name>, acknowledged_cost=true)` is accepted on the same footing.
- **Both spellings of one concept is its own error.**
  `validate_workflow(workflow=<def>, inline_workflow=<the same def>)` and
  `run_workflow(workflow_path=<name>, name=<the same name>, acknowledged_cost=true)`
  each fail naming *both* parameters as "the same thing - provide only one". A
  generic exactly-one-of message here is a (mild) finding: the caller passed one
  concept, and being told to pass exactly one of two things it thinks it did pass is
  the confusion this issue was about.
- **Exactly-one-of still holds across the alias pairs.** `run_workflow(workflow=<def>,
  name=<a stored name>, acknowledged_cost=true)` → refused, and bare
  `validate_workflow()` with neither a document nor a name → refused. Both messages
  name both spellings of each pair (`workflow_path`/`name`, `inline_workflow`/
  `workflow`), so the error teaches the alias instead of naming one arbitrary half.
  This bullet is the regression that matters most: aliasing is exactly how a
  mutually-exclusive pair quietly becomes a pair that accepts both.
- **The descriptions agree with the behavior.** Both tools' descriptions, as read
  from the live schema, cross-reference the other tool's naming. Half of #179 was
  that each description was silent about the other, so a behavior-only fix would
  leave the toll in place for any agent that reads before it calls.
cleanup: `delete_output` the run directory of the one job this case queues (last
media file takes the run directory with it). The stored workflow used for the
name-side bullets is read and validated only, never modified.
metrics: none — the assertions are all shape and error text; S-P001 already tracks
image-generation latency, and this case's run is a vehicle, not a measurement.
source: tester, model `opus` via provider `anthropic`, verified in #179 on 2026-09-16
against dw `0.4.0-beta.4` on `lem`, workspace `qa-ep17`: the failing call from the
report (`run_workflow(workflow=…)`) queued job `62054e5c3a49` and succeeded in 11.9 s;
`validate_workflow(workflow_path="templates/text-to-image")` returned a plan with
`estimate.basis: "observed"`, `runs: 13`; both collision cases returned "are the same
thing - provide only one"; and both exactly-one-of messages listed both spellings.
Proposed by the implementer in its hand-off comment (round trip plus the two
collision cases); the exactly-one-of-survives-aliasing bullet, the
`wait_for_job`-reached-`succeeded` requirement, the alias-resolves-to-the-catalog
check and the description bullet are mine, from what that session ran.

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

### S-F043 — `transcribe_audio` returns the words a TTS deliverable actually speaks
Before #188 nothing in the tool set returned what was spoken: a dropped line or a
mid-sentence truncation in a Bark/CSM take could only be inferred from `duration` and
words-per-second arithmetic. `transcribe_audio` (Whisper-class, default
`openai/whisper-base`) makes the words themselves checkable. This case pins the loop
end to end from the consumer side: speak a known script, transcribe the wav, and read
the text back over MCP. Cheap: bark-small (~15 s) plus whisper-base (~10 s), both
already cached on `lem`; a first run on a fresh box downloads whisper-base once.
expected:
- **The task and its template are discoverable.** `get_task("transcribe_audio")` lists
  `audio` (required), `device`, `sample_rate` and `model_name` (default named as
  `openai/whisper-base`); `list_workflows(shape="utility")` includes
  `templates/transcribe-audio` with `kinds: ["text"]` and variables `input_audio`,
  `model_name`. (It is bucketed under `utility`, not `text`.)
- **The stored template transcribes a stored template's speech.** Run
  `templates/generate-speech` with `arguments: {"text": "The purple elephant delivered
  seventeen umbrellas to the lighthouse on Tuesday."}` → `succeeded`, one wav. Then
  `templates/transcribe-audio` with `input_audio` = `output:` + that wav's manifest name
  → `succeeded`, one `.txt` in the manifest, `error: null`. `get_output_text` on it →
  `content_type` starts `text/plain`, `truncated: false`, and the text, lowercased,
  contains **`purple elephant`**, **`umbrellas`** and **`lighthouse`**, and the digit
  string `17` or the word `seventeen` (Whisper normalises numerals either way). An
  empty text, a text missing any of those tokens, or a manifest with no `.txt` is the
  regression. Word-for-word equality is *not* asserted — bark-small's rendering varies
  run to run and a single mangled word is TTS, not ASR.
- **Chained, on the accelerator, from `previous_result`.** One inline workflow, two
  steps: `generate_speech` `{"text": "Nine green bicycles waited outside the bakery
  until midnight.", "voice_preset": "v2/en_speaker_3", "model_name": "suno/bark-small"}`
  (`content_type: audio/wav`) then `transcribe_audio` `{"audio": "previous_result:speak",
  "device": "cuda"}` (`content_type: text/plain`) → `succeeded`, two manifest files; the
  text contains `bicycles` and `bakery`. A failure here with the bullet above passing
  means the in-memory waveform path or the `device` override broke, not the model.
cleanup: `delete_output` the run directory of each of the three jobs (the `.txt` is
the last file of its run, so the directory goes with it).
metrics: none — the assertions are token-presence; S-P004 tracks audio-chain latency.
source: tester, model `opus` via provider `anthropic`, verified in #188 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`, workspace `qa-verify-188`: job `9ac795d05425`
(bark-small, 15 s) → job `f2ab2ceaff4b` (whisper-base via the stored template, 11 s)
returned `"The purple elephant delivered 17 umbrellas to the lighthouse on Tuesday."`
exactly; job `052ef160620e` (chained inline, `device: "cuda"`, 17 s total) returned
`"nine green bicycles waited outside the bakery until midnight."`. A third run took
an H3 video (`asset:qa-cast/ep6-cold-open.mp4`) as `input_audio` and transcribed its
dialogue coherently in 2.6 s — the video-soundtrack path the schema doc promises
works, but that asset is a `qa-cast` fixture, not this suite's, so it is not asserted
here.

### S-F044 — a gated repo this box's token cannot reach is refused by the free pre-flight
Before #186 a gated Hugging Face repo whose license this box's token had not accepted
was invisible until the job ran and the load hit a 403 — a queue slot and a worker
load spent to discover something the hub could have said up front. The first fix
keyed `access_blocked` on `model_info`, which the hub answers for anyone, so the field
was `false` for a repo the token was genuinely refused on; the second fix probes a
real sibling file (the request class a load actually makes) when `gated` is truthy.
This case pins that the pre-flight answer matches what a download would do. Free:
`validate_workflow` only, nothing is fetched. The fixture repo is 10.9 MB and the
gate on it is **not** accepted on `lem` as of 2026-09-17 — if someone accepts it, the
first bullet inverts and the case needs a new un-granted fixture, not a weakened
assertion (a `download_model` on it that fails with a `403 ... Cannot access gated
repo` in `list_downloads` is how to reconfirm; `delete_model` the partial entry after).
expected:
- **Blocked is reported as blocked, with a pointer.** `validate_workflow` on an inline
  one-step workflow — `pipeline.configuration.component_type: "StableDiffusionPipeline"`,
  `from_pretrained_arguments.model_name: "pyannote/speaker-diarization-3.1"`, any
  `arguments`, `result.content_type: image/png`, a top-level `seed` so the cache warning
  stays out of the way — is `valid: true` and `plan.downloads_required` has exactly one
  entry, `repo: "pyannote/speaker-diarization-3.1"`, `gated` truthy (`"auto"` today) and
  **`access_blocked: true`**; `warnings` contains exactly one line, and it names both the
  repo and `https://huggingface.co/pyannote/speaker-diarization-3.1`. `access_blocked:
  false` or `null` for this repo with no warning is the regression (`null` is the
  honest answer only when the hub could not be reached at all — check `gb` and `gated`
  are also `null` in that event before calling it a network blip).
- **Accessible and un-gated are not flagged.** The same workflow with two more steps,
  `stabilityai/sd-turbo` (not gated) and `stabilityai/stable-diffusion-3.5-large` (gated,
  license accepted on `lem`): the pyannote entry is unchanged, sd-turbo's is
  `gated: false, access_blocked: false`, SD3.5's is `gated: "auto", access_blocked:
  false`, and `warnings` still carries exactly the one pyannote line — the warning is
  per blocked entry, not all-or-nothing, and an accepted gate is not a false positive.
- **Unknown stays unknown.** A fourth step naming `tester-nonexistent-org/does-not-exist-186`
  yields `gb: null, gated: null, access_blocked: null` and no warning for it: a repo the
  hub does not know is "unknown", never reported as blocked or as clear.
cleanup: none — validate only, no job, no download.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #186 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`: the single-step call returned `{"repo":
"pyannote/speaker-diarization-3.1", "gb": 0.0, "gated": "auto", "access_blocked":
true}` plus the one warning; the four-repo call returned `false`/`false` for sd-turbo,
`"auto"`/`false` for SD3.5-large, `"manual"`/`false` for `meta-llama/Llama-3.2-1B`
and `null`/`null` for the nonexistent repo, with no gate warning. The token's refusal
on pyannote was established live in the previous verify round (a `download_model`
that failed `403 ... you are not in the authorized list`).

### S-F045 — `audio_bleed_gain_db` ducks the bled tail by exactly the dB asked for
Before #199 a `concat_videos` bleed (`audio_bleed_ms`) added the outgoing shot's
reversed tail at full scale or not at all — a tail loud enough to push the seam over
0 dBFS could only be switched off. `audio_bleed_gain_db` (default 0) scales that
copy by `10^(gain/20)` before it is added, and does nothing when `audio_bleed_ms` is
0. This pins both halves with one cheap job (four utility steps, ~10 s, no model).
Confirm the argument name against `get_task("concat_videos")` first.
Run one inline workflow with four `concat_videos` steps, each over
`["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"]`, `fps: 24`,
`result.content_type: video/mp4`: (a) `audio_bleed_ms: 500, audio_bleed_gain_db: 0`,
(b) same with `-6`, (c) same with `-20`, (d) `audio_bleed_ms: 0, audio_bleed_gain_db:
-6`. Then `get_gallery_metadata(envelope=true)` on each output and read the seam
second — index 5 of `media.envelope` (5–6 s; the seam is at 5.175 s).
expected:
- The job **succeeds** with four 248-frame / 10.334 s / 32 kHz stereo outputs whose
  whole-file `peak_dbfs`, `duration_seconds` and `frame_count` are identical across
  all four — gain touches only the bled window.
- Seam-second `rms_dbfs` is **strictly monotonic**: (a) > (b) > (c) ≥ (d), with (a)
  at least 5 dB above (d) — the bleed is audible against this head — and (c) within
  0.5 dB of (d).
- Subtracting (d)'s energy (`10^(rms/10)`) from each of (a)–(c) isolates the bled
  tail's contribution; the ratio (a)/(b) must be **6 dB ± 1** and (a)/(c) **20 dB ± 3**
  (the −20 arm sits near the AAC floor, hence the wider band). A −6 that measures ~0
  dB (knob ignored), ~12 dB (applied twice, or applied to power instead of amplitude)
  or +6 (sign inverted) is the regression; each is a one-line mistake in a scale
  factor and none of them fails the job.
- (d)'s envelope matches a plain join — `audio_bleed_gain_db` without a bleed is
  inert, not an error and not a silent bleed.
- Seam-second `peak_dbfs` for (a) is above (b)'s; (b), (c) and (d) may be equal, since
  once the tail is ducked below the incoming shot's own peak that peak is what remains.
The `level_spread` warning fires on every step (these shots sit 12 dB apart) and, since
#198, a `bleed_join` tonal-tail warning on (a)–(c): both expected, neither a finding.
cleanup: delete the run (one `delete_output` on `<workflow>/<run id>`). The two
assets are shared fixtures — leave them.
metrics: none — the assertions are fixed ratios, not a trend.
source: tester, model `opus` via provider `anthropic`, verified in #199 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (job `894fd4dec2f0`, workspace `qa-verify-199`):
seam-second RMS −34.41 / −38.19 / −40.76 / −40.90 dBFS for (a)/(b)/(c)/(d), isolating
to 6.0 dB and 20.2 dB; seam peaks −17.87 / −20.72 / −20.72 / −20.72. The implementer
proposed the smoke check in its hand-off comment.

### S-F046 — a `select` rule that needs a threshold is refused by the free pre-flight, not after the fan-out
#119 added the `select` reducer (N candidates + N scores → one) so a scored fan-out
can pick a winner before an expensive stage. Its rule-specific arguments
(`threshold` for `first_above`/`first_below`, `index` for `index`) are only
checked at validate; if that check slips, a missing threshold surfaces only after
every candidate has been generated. Free, no model loads. Confirm the argument
names against `get_task("select")` first.
`validate_workflow` on this inline document (any real image pipeline will do — the
pre-flight never instantiates it):
```json
{"id": "s_f046", "seed": 7,
 "variables": {"candidates": [{"name":"a","prompt":"a red apple"},{"name":"b","prompt":"a green pear"}]},
 "steps": [
  {"name":"still","for_each":"variable:candidates","release_pipeline":true,
   "pipeline":{"configuration":{"component_type":"ZImagePipeline","offload":"sequential"},
     "from_pretrained_arguments":{"model_name":"Tongyi-MAI/Z-Image-Turbo","torch_dtype":"torch.bfloat16","low_cpu_mem_usage":true},
     "arguments":{"prompt":"item:prompt","num_inference_steps":9,"guidance_scale":0,"width":512,"height":512}},
   "result":{"content_type":"image/jpeg","subfolder":"intermediate"}},
  {"name":"judge","for_each":"variable:candidates",
   "task":{"command":"judge","arguments":{"image":"previous_result:still",
     "rubric":"How red is the dominant object? 0 = not at all, 10 = vivid red.","scale":[0,10],"device":"cuda"}}},
  {"name":"pick","task":{"command":"select","arguments":{"candidates":"gather:still","scores":"gather:judge","rule":"first_above"}},
   "result":{"content_type":"image/jpeg","subfolder":"final"}}]}
```
then the same document twice more: (b) `rule: "best"`; (c) `rule: "argmax"` (a
control — no threshold needed).
expected:
- (a) `valid: false`; one error whose path is `steps[2].task.arguments.threshold` and
  whose message names the rule and the missing argument ("select rule 'first_above'
  requires a threshold" or equivalent). No plan, nothing queued.
- (b) `valid: false` at `steps[2].task.arguments.rule`, naming `best` as unknown.
- (c) `valid: true` with a plan. A `valid: true` on (a) or (b) is the regression —
  the run would then burn the whole fan-out before `select` failed. Also a
  regression: (a) refused at some path other than the `threshold` argument, since
  the point of the path is that an agent can repair the one field.
`gather:` from a for_each step, `previous_result:` from inside a sibling for_each
over the same list, and `item:` are the conventions in play; a validate error about
any of *those* on (c) means the reference syntax moved, not that `select` broke —
re-read the guide's "Cross-Step Data Flow" section before filing.
cleanup: none — validate-only.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #119 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (workspace `qa-verify-119`): (a) refused at
`steps[2].task.arguments.threshold` "select rule 'first_above' requires a threshold.",
(b) at `steps[2].task.arguments.rule` "select: unknown rule: 'best'.", and the argmax
form ran to a `selected: {position, score, entry}` manifest entry (jobs `4011ed6e1007`,
`7d3e270b148a`). The implementer proposed check (a) in its hand-off comment.

### S-F047 — `compress_audio` / `filter_audio` shape a track the way their arguments say, measured by `analyze_audio`
#200 added whole-track dynamics (`compress_audio`: `mode` compress/limit/gate) and a
single biquad (`filter_audio`: `kind` lowpass/highpass/bandpass/notch). Both are pure
arithmetic on samples, so a regression is a wrong number, not a failed job — this pins
the arithmetic with one cheap utility-only job (~8 s, no model) and a round of free
refusals. Confirm the argument names against `get_task` for both tasks first.
Run one inline workflow on `asset:qa-cast/ep11-bed.wav` (19.67 s, 32 kHz mono, peak
−28.89 dBFS): an `analyze_audio` on the source, then four processing steps each
followed by `analyze_audio` on `previous_result:` (`application/json`, subfolder
`intermediate`): (a) `compress_audio` `threshold_dbfs: -40, ratio: 4, attack_ms: 0,
mode: "compress"`; (b) same with `mode: "limit"`; (c) `filter_audio` `cutoff_hz: 200,
kind: "lowpass"`; (d) `filter_audio` `cutoff_hz: 4000, kind: "highpass"`. Then
`validate_workflow` on a copy with `ratio: 0` on (a) and `cutoff_hz: -5` on (c), and
run four one-step jobs that must fail: `mode: "expand"`, `threshold_dbfs: 3`,
`kind: "shelf"`, and `cutoff_hz: 16000` (= Nyquist at 32 kHz).
expected:
- The job **succeeds**; every arm's `duration_seconds`, `sample_rate` and `channels`
  match the source's (19.666656 / 32000 / 1) — these tasks never resample or trim.
- (a) `peak_dbfs` is **−37.22 ± 0.1**: threshold + (source peak − threshold) / ratio
  = −40 + 11.11 / 4. A peak still at −28.89 is the compressor doing nothing;
  −40.0 is `limit` behaviour leaking into `compress`; −34.4 or −42.8 is the ratio
  applied to the wrong quantity.
- (b) `peak_dbfs` is **−40.0 ± 0.05** — a limiter with zero attack holds the peak
  exactly at threshold.
- (c) `high_dbfs` drops by **at least 40 dB** from the source's while `low_dbfs` moves
  less than 5 dB; (d) is the mirror — `low_dbfs` drops at least 40 dB, `high_dbfs`
  moves less than 3 dB. A filter that moves both bands the same way, or neither, is
  the regression; a swap between (c) and (d) is `kind` being ignored.
- `validate_workflow` refuses `ratio: 0` at `steps[<a>].task.arguments.ratio` and
  `cutoff_hz: -5` at `steps[<c>].task.arguments.cutoff_hz`, each message naming the
  task; no plan, nothing queued.
- Each of the four bad runs fails with a message that names the task, the argument and
  the accepted values: `mode must be one of ('compress', 'limit', 'gate')`,
  `'threshold_dbfs' cannot be above full scale (0)`, `kind must be one of
  ('lowpass', 'highpass', 'bandpass', 'notch')`, `must be below the Nyquist frequency
  (16000.0) for sample_rate 32000`. A run that succeeds on any of them, or a
  `cutoff_hz` at Nyquist that quietly produces silence, is the regression.
`analyze_audio`'s band figures are relative — assert the *shift* between source and
output, never an absolute band level (see #207). `compress` with the default
`attack_ms` (10) leaves this bed's single-sample peak untouched; that is why (a) sets
it to 0, not a finding.
cleanup: delete the runs (one `delete_output` per `<workflow>/<run id>`, the failed
ones included). The asset is a shared fixture — leave it.
metrics: none — the assertions are fixed numbers, not a trend.
source: tester, model `opus` via provider `anthropic`, verified in #200 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (jobs `7c175207aac8`, `a542ea98369a`, workspace
`qa-verify-200`): (a) peak −37.2215, (b) −39.999999, (c) high −123.7 → −181.6 with
low −91.3 → −94.4, (d) low −91.3 → −143.9 with high −123.7 → −124.7; refusals as
quoted (jobs `a542ea98369a`, `eb0ef01f09c6`, `b91568a540ae`, `a8e727d9dcc4`). The
implementer proposed the analyze → compress → analyze round-trip in its hand-off
comment.

### S-F048 — `save_workflow(patch=...)` edits one field and leaves the rest of the stored document alone
#202 added an optional `patch` argument to `save_workflow` — a JSON Merge Patch
(RFC 7396) merged onto the currently stored definition — as the alternative to
resending the whole `workflow`. The whole value of the feature is that a one-field
edit touches only that field, so the regression to catch is a patch that clobbers a
sibling, fails to delete, or bypasses validation. Free, no model, no job.
Save a throwaway utility workflow `qa-patch-smoke` with the full `workflow` form:
`id`, a `summary`, four variables (`prompt`, `width: 512`, `height: 512`, `steps: 4`)
and one `text`-command step whose `result.subfolder` is `final`. Then, in order:
(1) `patch: {"variables": {"steps": 8}}`; (2) `patch: {"variables": {"width": null,
"seed": 42}, "summary": "patched"}`; (3) `patch: {"steps": [<one new step, different
name>]}`; (4) `patch: {"steps": null}`; (5) the same call with both `workflow` and
`patch`, and once more with neither; (6) `patch: {"variables": {"steps": 1}}` against
a name that does not exist. `get_workflow` after (1), (2), (3) and (4).
expected:
- After (1): `variables.steps` is 8 and `id`, `summary`, the other three variables
  and the `steps` list are unchanged. Any other key moving is the regression.
- After (2): `width` is gone, `seed` is 42, `summary` is `patched`, and `prompt` /
  `height` / `steps: 8` are untouched — a `null` deletes, a new key adds, and the
  nested merge is recursive.
- After (3): the `steps` list holds exactly the one new step — a list is replaced
  whole, not merged or appended.
- (4) is refused with `Validation error: 'steps' is a required property` and the
  `get_workflow` that follows shows the document from (3) — a patch that produces an
  invalid document must not land.
- Both calls in (5) are refused with `Provide exactly one of `workflow` ... or
  `patch` ...`; (6) is refused with `Unknown workflow: <name>` and creates nothing.
cleanup: `delete_workflow("qa-patch-smoke")`.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #202 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (workspace `qa-verify-202`, since deleted): every
step above behaved as written. The implementer proposed the one-variable patch +
`get_workflow` check in its hand-off comment; the deletion, list, refusal and
unknown-name arms are the tester's adjacent cases.

### S-F049 — `upload_asset(content=...)` puts inline bytes in the library without touching any path
#203 added `content` (base64) to `upload_asset` as the alternative to `file_path`, so an
agent with no filesystem in common with a `dw.serve --mcp` endpoint can still land a
small input. The regression to catch is the inline path silently breaking (falling back
to a path read, dropping the `uploads/` placement, or letting a name escape) or the
two error messages losing the pointer to the agent-usable route. Free, no model, no job.
`content` is the base64 of a 1×1 PNG (70 bytes):
`iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==`
In order: (1) `upload_asset(content=<that>, asset_name="regress/inline-upload-test.png")`,
then `list_assets()`; (2) the same `content` with no `asset_name`; (3) the same with both
`content` and `file_path="/tmp/x.png"`, and once more with neither; (4) the same
`content` with `asset_name="regress/evil.py"`; (5) with `asset_name="../../escape.png"`;
(6) `content="!!!not-base64@@@"`, `asset_name="regress/bad.png"`; (7)
`upload_asset(file_path="/nowhere/local-only.png", asset_name="regress/x.png")`; (8)
`download_output(name="anything.png", destination="/nowhere/anything.png")`.
expected:
- (1) returns `reference: "asset:uploads/regress/inline-upload-test.png"`, `uploaded:
  "regress/inline-upload-test.png"`, `size: 70`, and `list_assets` lists it with
  `origin: workspace`, `kind: image`, `size: 70`. The `uploads/` prefix is the
  `/api/uploads` route's placement, the same one the web UI's picker gets.
- (2) is refused with `content requires asset_name`; both calls in (3) with `Pass exactly
  one of file_path or content.`; (4) with `not a kind the asset library takes`; (5) with
  `Invalid asset name` naming the `..` segment; (6) with `content could not be decoded as
  base64`. None of (2)–(6) creates an asset.
- (7) is refused (`Refusing to read`) and the message names `content=` as the
  alternative; (8) is refused (`Refusing to write`) and the message names the
  `list_gallery` url, `get_output_image` / `get_output_audio` / `get_output_text`, and
  `keep_output`. A refusal that only points at the web UI is the regression.
cleanup: `delete_asset("uploads/regress/inline-upload-test.png")`.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #203 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (workspace `qa-verify-203`, since deleted): every
step above behaved as written. The implementer proposed (1) in its hand-off comment
(with `asset:regress/…` as the reference; the server actually returns
`asset:uploads/regress/…`); the refusal arms are the tester's adjacent cases. The 4 MB
`MAX_INLINE_UPLOAD_BYTES` cap is deliberately not a case here: a >4 MB base64 argument
can't be sent from an LLM-driven seat, so that check lives in the dw repo's pytest suite.

### S-F050 — `get_output_audio` returns a short clip inline as a typed audio block, and refuses video
Before #204 there was no in-context path for a generated audio output: an agent could
see it in `list_gallery` and describe it with `get_gallery_metadata`, but getting the
bytes meant `download_output` (a write on the server's disk) or an out-of-band fetch
of the gallery `url`. `get_output_audio(name, workspace=None)` is the audio analogue of
`get_output_image`: a typed MCP `AudioContent` block plus a text tail naming the file
and its raw size. It is audio-only and never transcodes or cuts. Cheap: one utility
job, two steps, ~4 s, no model.
1. Run one inline workflow in this suite's workspace with two utility steps:
   `slice_audio` `{"audio": "asset:qa-cast/ep11-bed.wav", "start_seconds": 0,
   "duration_seconds": 2}` → `result: {"subfolder": "final", "file_base_name": "clip",
   "content_type": "audio/wav"}`, and `concat_videos` `{"videos":
   ["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"], "fps": 24}`
   → `result: {"subfolder": "final", "file_base_name": "cut", "content_type":
   "video/mp4"}`. (`concat_videos` warns about the 12 dB level jump between the two
   fixtures; that warning is S-F045's territory, not a finding here.)
2. `get_output_audio(name=<the wav from the manifest>, workspace="regression-smoke")`.
3. `get_output_audio(name=<the mp4 from the manifest>, workspace="regression-smoke")`.
4. `get_output_audio(name="asset:qa-cast/ep11-bed.wav", workspace="regression-smoke")`.
expected:
- Step 2 returns **a typed audio content block** (`audio/x-wav`) — not a text
  description, not a server path — followed by two text lines `name: <the wav name>`
  and `bytes: N`, where `N` equals that file's `size` in `list_gallery` (128044 for a
  2 s slice of the 32 kHz mono 16-bit bed) and equals the decoded blob's length. A
  `bytes` figure that disagrees with the gallery size, or a payload smaller than it,
  is the regression (a silent truncation).
- Step 3 is **refused, with no payload**, and the message names the file, says it is
  `video/mp4, not audio`, and points at `get_output_image` and `get_gallery_metadata`
  as the alternatives. A video handed back as an "audio" block is the regression.
- Step 4 → `Not Found`: `asset:` references are not gallery names and this tool reads
  the gallery only (same as `get_output_image`). This is the current contract, pinned
  so a change to it is noticed rather than silent; a later issue may extend it.
- The `workspace` pin works without `use_workspace` in every call above.
cleanup: `delete_output` the job's run directory (`<workflow>/<run id>`); the fixtures
are read-only.
metrics: none — the inline size limit is C-F034's over-budget case, not a trend here.
source: tester, model `opus` via provider `anthropic`, verified in #204 on 2026-09-17
against dw `0.4.0-beta.6` on `lem`: job `9b6558f16343` in `regression-smoke` (run
`20260918-014610-4b98a16d`, since deleted, 3.8 s) — the 2 s wav came back as
`audio/x-wav` with `bytes: 128044` and a 128044-byte blob; the mp4 was refused with the
message quoted above; the `asset:` name returned `Not Found`. The #204 verify also
covered a 41930-byte mp3 (`audio/mpeg`, `bytes` = gallery size, valid MPEG layer III)
and a 2,890,652-byte wav (3,854,203 B base64, just under the 4,194,304 ceiling)
returned whole; the over-budget refusal is C-F034 in the `complete` suite.

### S-F051 — `analyze_audio` reads a video's soundtrack, reports `null` for a band above Nyquist, and keeps `crest = peak − rms`
#207 added `analyze_audio(audio, sample_rate=None)`: a read-only measurement task
returning `peak_dbfs`, `rms_dbfs`, `crest_factor_db` and a low/mid/high band reading.
S-F047 already pins the band *shift* under `compress_audio`/`filter_audio`; this case
pins the task's own contract — the three input shapes it accepts and the one edge it
documents: a band whose lower bound is at or above the track's Nyquist frequency
reads `null`, never a spurious floor number. One utility job, four steps, ~4 s, no model.
Run one inline workflow in this suite's workspace, every `analyze_audio` step with
`result: {"content_type": "application/json", "subfolder": "final"}`:
(1) `resample_audio` `{"audio": "asset:qa-cast/ep15-song.mp3", "target_sample_rate":
4000}` → `audio/wav`, subfolder `intermediate`; (2) `analyze_audio` on
`asset:qa-cast/ep15-song.mp3` (the file, 44.1 kHz); (3) `analyze_audio` on
`previous_result:` of step 1 (the waveform, no explicit `sample_rate`); (4)
`analyze_audio` on `asset:qa-cast/ep11-coldopen.mp4` (a video — its soundtrack is
taken). Read each JSON with `get_output_text`.
expected:
- The job succeeds and each `analyze_audio` step writes exactly one JSON file with the
  six keys `peak_dbfs`, `rms_dbfs`, `crest_factor_db`, `low_dbfs`, `mid_dbfs`,
  `high_dbfs` — nothing else, no waveform written.
- In every step, `crest_factor_db` equals `peak_dbfs − rms_dbfs` to within 0.01 dB.
- Step 2 (the mp3 at full rate): all six values are numbers; `peak_dbfs` is **+0.76
  ± 0.05** (the fixture's known over-full-scale decode, see Fixtures) — the same figure
  `get_gallery_metadata` reports, so a peak here that disagrees with it is a reading
  error, not a fixture change.
- Step 3 (the 4 kHz waveform): `high_dbfs` is **`null`** — the high band's lower bound
  is above the 2 kHz Nyquist, so its mask is empty. `low_dbfs` and `mid_dbfs` are still
  numbers, and `low_dbfs` is within **0.1 dB** of step 2's (a downsample to 4 kHz
  leaves the low band untouched). A number in `high_dbfs` here — however small — is
  the regression (a false floor), as is a failed step (the empty mask crashing) or a
  `low_dbfs` that moved (the hand-off waveform's sample rate mis-read).
- Step 4 (the video): all six values are numbers; no error about the input kind.
  `analyze_audio` on a video that has no soundtrack is not covered here.
Band values are on a different scale from `rms_dbfs` (~40 dB below it on every track
to date — #211 tracks whether that stays so); assert only what is listed above, never
a band's absolute level against `rms_dbfs`.
cleanup: `delete_output` the job's run directory (`<workflow>/<run id>`); the fixtures
are read-only.
metrics: none — the assertions are fixed values and a `null`, not a trend.
source: tester, model `opus` via provider `anthropic`, verified in #207 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (jobs `0d5439af1982`, `7626b5f8ebbc`, workspace
`qa-verify-207`, since deleted): mp3 at 44.1 kHz peak 0.7575 / rms −18.236 / crest
18.994 / low −57.697 / mid −69.187 / high −88.844; the same track at 4 kHz peak 0.545 /
rms −18.851 / crest 19.397 / low −57.697 / mid −66.414 / **high `null`**; the video
soundtrack peak −1.036 / rms −20.880 / crest 19.844, all bands numeric. The Nyquist
`null` is the case the implementer proposed in its hand-off comment.

### S-F052 — `analyze_audio`'s band `*_dbfs` sit on `rms_dbfs`'s scale: one band's power adds up to the track's
#211 found the three band readings a constant ~40 dB under `rms_dbfs` — a per-bin mean
magnitude wearing a `_dbfs` suffix, so an agent comparing `low_dbfs` against
`compress_audio.threshold_dbfs` got a nonsense answer. The fix sums each band's
Parseval power, so the three bands together carry the track's `mean(x²)` — the
quantity `rms_dbfs` is built from. This pins that contract with a signal whose energy
is (almost) all in one band, where that band must read `rms_dbfs` itself. S-F051's
"band values are on a different scale" caveat describes the pre-#211 state and is
superseded by this case; S-F047's shift-only assertions remain valid either way. One
utility job, four steps, ~4 s, no model.
Run one inline workflow in this suite's workspace, every `analyze_audio` step with
`result: {"content_type": "application/json"}`: (1) `filter_audio` `{"audio":
"asset:qa-cast/ep15-song.mp3", "cutoff_hz": 120, "kind": "lowpass"}` → `audio/wav`,
subfolder `intermediate`; (2) `analyze_audio` on `previous_result:` of step 1; (3)
`analyze_audio` on `asset:qa-cast/ep15-song.mp3` (the unfiltered file); (4)
`analyze_audio` on `asset:qa-cast/ep11-bed.wav`. Read each JSON with `get_output_text`.
expected:
- Step 2 (the lowpassed song): `low_dbfs` is within **1 dB** of that step's own
  `rms_dbfs`, and `mid_dbfs` and `high_dbfs` are both at least 15 dB below it. A
  `low_dbfs` 30 dB or more under `rms_dbfs` is the #211 regression (per-bin magnitude
  back); a `low_dbfs` *above* `rms_dbfs` is a band claiming more power than the track
  has (a mirrored-half double-count).
- Steps 3 and 4 (unfiltered tracks): the loudest of `low_dbfs`/`mid_dbfs`/`high_dbfs`
  is within **6 dB** of that step's `rms_dbfs`, and the power sum of the three bands,
  `10·log10(Σ 10^(band/10))`, is within **1 dB** of `rms_dbfs` (never above it by more
  than 0.1 dB). A loudest band 30+ dB under `rms_dbfs` on either is the regression.
- Every step still returns the six keys of S-F051 with `crest_factor_db = peak_dbfs −
  rms_dbfs` to 0.01 dB — the rescale must not have touched the whole-track figures:
  step 3's `peak_dbfs` is still **+0.76 ± 0.05** and its `rms_dbfs` **−18.24 ± 0.05**.
Do not extend the power-sum check to a highpassed or otherwise top-heavy signal: at
verification a 6 kHz highpass summed ~2.3 dB short of `rms_dbfs` (the `high` band's
upper edge is below Nyquist, so energy above it is counted by `rms_dbfs` and by no
band). That is a band-edge property, not the #211 defect; the 1 dB sum tolerance is
for full-band material only.
cleanup: `delete_output` the job's run directory (`<workflow>/<run id>`); the fixtures
are read-only.
metrics: none — the assertions are tolerances around fixed values, not a trend.
source: tester, model `opus` via provider `anthropic`, verified in #211 on 2026-09-17
against dw `0.4.0-beta.6` on `lem` (jobs `315d6077aaa4`, `f38fc154efcc`, workspace
`qa-verify-211`, since deleted): lowpassed song rms −24.097 / low −24.266 / mid −42.529
/ high −82.535; unfiltered song rms −18.236 / low −22.316 / mid −21.682 / high −35.038
(sum −18.87); bed rms −49.938 / low −57.789 / mid −50.749 / high −72.955 (sum −49.95).
The single-band-equals-rms shape is the case the implementer proposed in its hand-off
comment.

### S-F053 — `validate_workflow`'s plan echoes the workspace and output root it probed against
#184 reported a step cache "wiped" by a failed job; the likelier story was a
`validate_workflow` probed against a different output root than the job ran in — the
cache keys on the root, so a validate from the wrong workspace answers `cached_steps: 0`
with nothing to say why. The fix adds `plan.workspace` and `plan.output_dir` so a `0`
can be cross-checked. This pins those two fields and that they follow the per-call
`workspace` pin, not the session. Two free calls, no job, no model.
Call `validate_workflow(name="templates/text-to-image", arguments={})` twice: once
with no `workspace` (session on the default workspace), once with
`workspace="regression-smoke"`.
expected:
- Both `valid: true`. Both plans carry the keys `workspace` and `output_dir` (strings).
- Unpinned: `plan.workspace == "default"` and `plan.output_dir` is the default
  workspace's `outputs` directory as `list_workspaces` reports it (ends in `/outputs`
  with no workspace segment).
- Pinned: `plan.workspace == "regression-smoke"` and `plan.output_dir` ends in
  `/regression-smoke/outputs`. A pinned call that still echoes `default` is the
  regression — the probe ran where the session is, not where the job would.
- Both plans still carry `fingerprint`, `steps`, `cached_steps`, `estimate` (the new
  keys are additive).
Do not assert on `cached_steps` — it depends on what the in-memory cache holds and this
template sets no seed, so it is `0` without being probed either way.
cleanup: none (read-only).
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #184 on 2026-09-18
against `lem` after the `develop` merge of `fix/184-plan-workspace-echo` (1996f8a):
unpinned → `default` / `/home/don/diffusers-workspace/outputs`; pinned to `qa-ep20` →
`qa-ep20` / `/home/don/diffusers-workspace/qa-ep20/outputs`. Shape as proposed in the
implementer's hand-off comment; a stored `name` that lives only in another workspace is
refused outright when unpinned, so the mismatch this guards is only reachable with a
template or an inline definition.

### S-F054 — a `result` block on a scalar-returning step is refused by the free pre-flight, not by the writer
#212 (split from #209): `judge` returns one number, not an artifact, and a `result`
block on it is a natural thing to write — the guide's Result Configuration section
describes saving text and a score reads as text. It used to validate clean and die
only after the whole fan-out had run (`write() argument must be str, not float` in
`save_artifact`, ~2 min of GPU wasted). The fix declares what each command returns
at the registry and refuses `result` on a scalar step at validate. Free, no model
loads; the `image` value is never fetched.
Four `validate_workflow` calls on inline documents, each one step named `score`:
- (a) `{"id":"s_f054","steps":[{"name":"score","task":{"command":"judge","arguments":{"image":"https://example.com/a.png","rubric":"Is this a cat?","scale":[1,10]}},"result":{"content_type":"text/plain","subfolder":"intermediate"}}]}`
- (b) the same document with the `result` block removed (control).
- (c) the same shape on an artifact-returning task: `{"command":"canny","arguments":{"image":"https://example.com/a.png"}}` with `"result":{"content_type":"image/png","subfolder":"intermediate"}` (control).
- (d) `run_workflow` on document (a) with `acknowledged_cost=true`.
expected:
- (a) `valid: false`; one error at path `steps[0].result` whose message says the
  command returns a number/scalar, not an artifact (e.g. "judge returns a number, not
  an artifact - 'result' cannot be saved"). No plan.
- (b) `valid: true` with a plan (the rule is not over-broad on `judge` itself).
- (c) `valid: true` with a plan (no false positive on an artifact task).
- (d) refused as a tool error carrying the same `steps[0].result` message; nothing
  queued — `get_health` afterwards shows `queued: 0` and `current_job: null`. A queued
  job here is the regression, whether or not it later fails.
Use the `content_type` form of `result` shown, not a bare `{"format":"json"}` — that
one is caught by the schema first (`'content_type' is a required property`) and never
reaches the scalar rule, so it cannot tell you whether the rule is still there.
cleanup: none — validate-only; (d) never queues.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #212 on 2026-09-18
against dw `0.4.0-beta.6` on `lem` after the `develop` merge of
`fix/212-scalar-result-validation` (36d5293): (a) `steps[0].result` "judge returns a
number, not an artifact - 'result' cannot be saved"; (b) and (c) `valid: true`; (d)
refused with the same message, `queued: 0`. Case as proposed in the implementer's
hand-off comment, with the two controls and the `run_workflow` check added.

### S-F055 — `select` refuses `candidates`/`scores` gathered from `for_each` groups of different sizes, on the resolved expansion
#213 (bounded release of #208): `select` zips `gather:candidates` against
`gather:scores`, and #119 only ever checked their *shape* (both `gather:` or both
lists), never that the two groups expanded to the same number of members. A 2-vs-1
mismatch validated clean and surfaced only after the fan-out had run, or not at all.
The fix compares the post-expansion sizes — after the caller's `arguments` are folded
in, not the static `variables` lists — and reports at the `select` step's `scores`
argument. Free, no model loads; the judge reads a fixed asset so the `previous_result`
list-identity rule (`_rewrite_reference`, fail-fast) cannot trip first and mask this one.
Three `validate_workflow` calls on the same inline document, varying only the lists:
```json
{"id":"s_f055",
 "variables":{"candidates":[{"name":"a","prompt":"a red apple"},{"name":"b","prompt":"a green pear"}],
              "other":[{"name":"x"}]},
 "seed":7,
 "steps":[
  {"name":"still","for_each":"variable:candidates","release_pipeline":true,
   "pipeline":{"configuration":{"component_type":"ZImagePipeline","offload":"sequential"},
     "from_pretrained_arguments":{"model_name":"Tongyi-MAI/Z-Image-Turbo","torch_dtype":"torch.bfloat16","low_cpu_mem_usage":true},
     "arguments":{"prompt":"item:prompt","num_inference_steps":9,"guidance_scale":0,"width":512,"height":512}},
   "result":{"content_type":"image/jpeg","subfolder":"intermediate"}},
  {"name":"judge","for_each":"variable:other",
   "task":{"command":"judge","arguments":{"image":"asset:qa-cast/hal-portrait.jpg","rubric":"How red is this?","scale":[0,10],"device":"cuda"}}},
  {"name":"pick","task":{"command":"select","arguments":{"candidates":"gather:still","scores":"gather:judge","rule":"argmax"}},
   "result":{"content_type":"image/jpeg","subfolder":"final"}}]}
```
- (a) as written: `candidates` 2 entries, `other` 1.
- (b) control: `other` given two entries (`x`, `y`).
- (c) override: document (b) with `arguments: {"other": [{"name":"x"}]}` — static
  lists agree, the caller's override makes them disagree.
Any image asset the workspace can reach works for `judge`'s `image`; it is never fetched.
expected:
- (a) `valid: false`; one error at `steps[2].task.arguments.scores` whose message
  names both counts, e.g. "select: 'candidates' and 'scores' gather from for_each
  groups of different sizes: candidates has 2 entries, scores has 1." No plan.
- (b) `valid: true` with a plan whose `list_entries` is `{candidates: 2, other: 2}`
  (unused-field warnings on `other` are fine).
- (c) `valid: false` with the same `.scores` error and the same "2 entries … 1" text
  as (a). A `valid: true` here means the check went back to reading the static
  `variables` lists instead of the resolved expansion — that is the regression #213's
  scope was written around.
cleanup: none — validate-only.
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #213 on 2026-09-18
against `develop` f6eba42 (merged bf6cc58) on `lem`: (a) and (c) `steps[2].task.arguments.scores`
"candidates has 2 entries, scores has 1."; (b) `valid: true`, `list_entries {candidates: 2, other: 2}`.
Also confirmed the mirror (1 vs 2) reports at `.scores`, not `.candidates`. Case as
proposed in the implementer's hand-off comment, with the control and override added.

### S-F056 — `match_levels` reports every shot's gain as a log event and a clip-hold as a `match_levels_held` warning
Before #214 `concat_videos` / `dissolve_videos` with `match_levels` set applied the
per-shot gain silently: a shot whose target would clip was held below full scale with
only a process-log line, so `job.warnings` stayed empty and the residual seam jump the
option exists to remove was invisible unless the consumer measured inputs and output
themselves. Both diagnostics now go through the event system. Cheap: one utility job,
two `concat_videos` steps, ~5 s, no model. Confirm `match_levels` / `match_levels_dbfs`
against `get_task("concat_videos")` first.
1. Run one inline workflow in this suite's workspace with two `concat_videos` steps,
   each over `["asset:qa-cast/ep6-cold-open.mp4", "asset:qa-cast/ep3-shot2-reply.mp4"]`,
   `fps: 24`, `match_levels: "rms"`, `result.content_type: video/mp4`: (a) the default
   target (no `match_levels_dbfs`); (b) `match_levels_dbfs: -8` — a target neither
   fixture can reach without clipping.
2. `wait_for_job`, then `get_job_events` and read the two steps' events.
expected:
- The job **succeeds** with two 248-frame outputs.
- Step (a): two `event: "log"` entries, one per shot, each carrying `index` (0 and 1),
  `measure_dbfs`, `gain_db` and `held: false` — shot 1 measures ≈ −19 dBFS with a
  small negative gain, shot 2 ≈ −31 dBFS with ≈ +11 dB (the fixtures are 12 dB apart
  and both reach −20 without clipping). **No** `match_levels_held` warning for (a),
  and nothing from (a) in `job.warnings` — the log fires every run, the warning only
  on a hold. (`level_spread` does not fire when `match_levels` is on.)
- Step (b): an `event: "warning"` with `kind: "match_levels_held"` for **each** shot,
  each carrying `command: "concat_videos"`, `index`, `measure_dbfs`, `target_dbfs:
  -8.0`, `gain_db`, `ceiling_dbfs: -0.5` and `shortfall_db` > 0; plus the same two
  per-shot `log` entries, now `held: true`. Both warnings also appear in
  `job.warnings` on `get_job`/`wait_for_job` as `held: concat_videos: video N would
  clip at the rms target (+X dBFS peak) - held to -0.5 dBFS, Y dB short of target`.
- The regression is any of: (a) or (b) with no per-shot `log` (gain applied
  silently again); (b) with `warnings: []` (the hold went back to the process log);
  or a `match_levels_held` on (a) (the hold test drifted).
`dissolve_videos` shares the helper — the `templates/dissolve-between-shots` path was
confirmed in #214 but is not repeated here; if (b) passes and dissolve regresses, that
is a new issue, not this case.
cleanup: delete the run (one `delete_output` on `<workflow>/<run id>`). The two
assets are shared fixtures — leave them.
metrics: none — the assertions are on event shape, not a trend.
source: tester, model `opus` via provider `anthropic`, verified in #214 on 2026-09-18
against dw `0.4.0-beta.6` (`develop` 5b6e3d9) on `lem`: (a) job `e511a83adda6` — logs
`video 1 rms -19.0 dBFS, gain -1.0 dB` / `video 2 rms -31.1 dBFS, gain +11.1 dB`, both
`held: false`, `warnings: []`; (b) job `9f2a69a2f263` — held both shots (`+8.3` /
`+10.5 dBFS peak`, `8.8` / `11.0 dB short`), two `match_levels_held` warnings in
`job.warnings`. The issue's own repro (`templates/assemble-and-score`, ep21 shots,
job `28fe19b70e99`) and `dissolve-between-shots` (job `ab2473b3a6d1`) both surfaced
the hold the same way. The implementer proposed the case in its hand-off comment.

### S-F057 — the two sequence templates expose the same `match_levels` pair, and `assemble-and-score` passes `match_levels_dbfs` through to `concat_videos`
Before #215 `templates/assemble-and-score` declared `match_levels` but not
`match_levels_dbfs` (#128 added the pair to `dissolve-between-shots` and never mirrored
it back), so a shot that could not reach the default −20 dBFS target without clipping
was clip-held and the only fix was copying the template inline. This case locks the
variable surface — cheap discovery calls — plus one ~3 s utility run proving the value
reaches the task. Run S-F056 first; this reuses its knowledge of the events.
1. `get_workflow(name="templates/assemble-and-score", variables_only=true)` and
   `get_workflow(name="templates/dissolve-between-shots", variables_only=true)`.
2. `list_workflows(shape="sequence")`.
3. `validate_workflow(name="templates/assemble-and-score", arguments={"match_levels":
   "rms", "match_levels_dbfs_typo": -24})` — a deliberately undeclared name.
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
above is S-F056's, chosen so this case never touches `qa-ep22`; its exact gains were
not run in #215, so treat the ≈ figures as expectations to confirm on first run, not
measured values.

### S-F058 — a `variable:` argument that resolves to `null` is omitted; a literal inline `null` is not
Before #209 `replace_variables` spliced a null-resolving `variable:` reference in
place, so a `select` step written as `rule: variable:rule, threshold:
variable:threshold, index: variable:index` with `threshold`/`index` defaulting to
`null` was refused ("'threshold' is only meaningful for rule 'first_above'…") and the
only way to change rules on a stored workflow was to edit the step. Don's scoped rule
(#209): a key whose value *arrived via* `variable:` and resolved to `null` is dropped
before argument checks; a literal `null` written inline keeps its meaning. Validate-only,
free. Same skeleton as S-F046 with the `select` arguments variable-driven:
```json
{"id":"s_f058","seed":7,
 "variables":{"candidates":[{"name":"a","prompt":"a red apple"},{"name":"b","prompt":"a green pear"}],
              "rule":"argmax","threshold":null,"index":null},
 "steps":[
  {"name":"still","for_each":"variable:candidates","release_pipeline":true,
   "pipeline":{"configuration":{"component_type":"ZImagePipeline","offload":"sequential"},
     "from_pretrained_arguments":{"model_name":"Tongyi-MAI/Z-Image-Turbo","torch_dtype":"torch.bfloat16","low_cpu_mem_usage":true},
     "arguments":{"prompt":"item:prompt","num_inference_steps":9,"guidance_scale":0,"width":512,"height":512}},
   "result":{"content_type":"image/jpeg","subfolder":"intermediate"}},
  {"name":"judge","for_each":"variable:candidates",
   "task":{"command":"judge","arguments":{"image":"previous_result:still",
     "rubric":"How red is the dominant object? 0 = not at all, 10 = vivid red.","scale":[0,10],"device":"cuda"}}},
  {"name":"pick","task":{"command":"select","arguments":{"candidates":"gather:still","scores":"gather:judge",
     "rule":"variable:rule","threshold":"variable:threshold","index":"variable:index"}},
   "result":{"content_type":"image/jpeg","subfolder":"final"}}]}
```
1. `validate_workflow(workflow=<above>)` as written.
2. Same document with `arguments={"rule":"first_above","threshold":5}`.
3. Same document with `arguments={"rule":"first_above"}` — threshold left at its `null` default.
4. Control: the `pick` step's arguments replaced by literal
   `"rule":"argmax","threshold":null,"index":null` (drop `rule`/`threshold`/`index` from
   `variables`).
expected:
- Step 1: `valid: true`, plan with 5 steps and `list_entries: {candidates: 2}`.
- Step 2: `valid: true`, `checked_arguments` lists `rule` and `threshold`.
- Step 3: `valid: false`, exactly one error at `steps[2].task.arguments.threshold` reading
  "select rule 'first_above' requires a threshold." — the dropped key reads as *missing*,
  not as "only meaningful for".
- Step 4: `valid: false` with **two** errors, at `steps[2].task.arguments.threshold` and
  `…index`, each "only meaningful for rule …, not 'argmax'" — literal null is still
  present. A `valid: true` here means null-dropping leaked into literal JSON, which is
  the wider engine change #209 explicitly declined.
- The regression is: step 1 refused at `threshold`/`index`; step 3 passing (a null
  threshold accepted for `first_above`); or step 4 passing.
cleanup: none (validate-only, nothing queued).
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #209 on 2026-09-18
against dw `develop` 506dcc6 on `lem`. All four validate calls above were run as
written; the step-1 document was also run once (job `a787dc68197c`, workspace
`qa-verify-209`, 68 s, `pick` → `selected: {position: 0, entry: still@a}`) to confirm
the run path agrees with validate — not repeated here, since the fix lives in the one
substitution routine both share.

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
(their `match_levels` behaviour is shared, S-F056/S-F057). This locks in that both
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

### S-F063 — `generate_speech` requires exactly one of `text` / `messages`, and a `messages` list reaches the pipeline as chat input
#225 added a `messages` argument (a list of `{role, content}` dicts, for chat-templated
TTS models such as VibeVoice) beside `text`, and turned the old "needs `text`" guard
into "exactly one of the two". This locks in the guard firing at the task level (before
any model load, so it is nearly free) and the list actually being handed to the
pipeline as chat input rather than stringified. Each step is a one-step inline
workflow: `{"id": "<id>", "steps": [{"name": "tts", "task": {"command":
"generate_speech", "arguments": <args>}, "result": {"content_type": "audio/wav",
"subfolder": "final", "file_base_name": "tts"}}]}`. No `seed` needed; all three fail
by design.
1. `args = {"text": "hello", "messages": [{"role": "user", "content": "hello"}],
   "model_name": "facebook/mms-tts-eng", "device": "cuda"}` → `run_workflow`, then
   `get_job`.
2. `args = {"model_name": "facebook/mms-tts-eng", "device": "cuda"}` (neither) →
   `run_workflow`, `get_job`.
3. `args = {"messages": [{"role": "user", "content": "hello there"}], "model_name":
   "facebook/mms-tts-eng", "device": "cuda"}` → `run_workflow`, `get_job`.
expected:
- Steps 1 and 2 fail in under ~2 s with an `error` containing `exactly one of 'text'`
  and `'messages'`; the traceback's deepest dw frame is in `dw/tasks/task.py`, with no
  `transformers/pipelines` frame — the guard ran before the pipeline was built.
- Step 3 fails with an error mentioning `chat_template` (VITS has none), and its
  traceback contains `apply_chat_template` under `transformers/pipelines/text_to_audio.py`
  — proof the list went through as chat input. A step 3 that fails with
  `exactly one of` (list rejected by the guard), or whose traceback shows no
  `apply_chat_template` (list coerced to text), is the regression. If step 3 fails
  with `BatchEncoding.to() got an unexpected keyword argument 'dtype'` instead, that
  is #232 (the transformers `preprocess` breakage), not this case — but it would mean
  the chat branch was skipped, so still report it.
- `validate_workflow` accepts all three (the guard is runtime-only as of #225); a
  validate-time rejection is an improvement, not a failure — note it and move on.
cleanup: `delete_output` on the three failed runs' `run_dir`s (each is empty; nothing
else is written).
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #225 on 2026-09-18
against dw `0.4.0-beta.6` / transformers `5.17.0` on `lem` (jobs `9ef1cbb420f7`,
`8d8f7829ffa9`, `a510779ccd67`).

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
- Step 2: `valid: true`, `plan.steps: 1`; the "no seed, step cache disabled" warning
  is this template's normal state. As in #169, a clean pre-flight is not evidence
  the run works — step 3 is what this case is for.
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

### S-F067 — `generate_speech` rejects a malformed `messages` before any model load, naming the argument
#233: `messages` (added by #225, see S-F063) had no shape guard, so a bare string
passed the exactly-one check and silently behaved as `text`, and a wrong-keyed dict
died in the tokenizer with an error that never named `messages`. This locks in the
runtime guard: every non-conforming shape fails at the task level, sub-second, with
one error that names `'messages'` and the required `{role, content}` shape — and a
well-formed list still gets through to the pipeline. Each step is a one-step inline
workflow `{"id": "<id>", "steps": [{"name": "speak", "task": {"command":
"generate_speech", "arguments": <args>}}]}` with `args` = `{"messages": <M>,
"model_name": "facebook/mms-tts-eng", "device": "cuda"}`; no `seed`, no `result`
block needed (every step fails by design). `run_workflow(acknowledged_cost=true)`
then `wait_for_job` for each.
1. `M = "hello there"` (bare string).
2. `M = [{"speaker": "bob", "text": "hello"}]` (wrong-keyed dict).
3. `M = []` (empty list).
4. `M = ["hello"]` (non-dict item).
5. `M = [{"role": "user", "content": 42}]` (non-string `content`).
6. `M = [{"role": "user", "content": "hello there"}]` (well-formed control).
expected:
- Steps 1–5 each finish `failed` in under ~2 s (`finished_at - started_at`), with no
  `loading` phase, and an `error` containing `'messages'` and `non-empty list of
  {'role': ..., 'content': ...}`. Any of them reaching the tokenizer (`Input must be
  a string, list of strings, or list of ints`), reaching the model, or — step 1
  especially — *succeeding* as if `text` had been given, is the regression.
- Step 6 fails **after** the guard with the model's own error mentioning
  `chat_template` (VITS has none; this is S-F063 step 3's outcome). A step 6 that
  fails with the `'messages' needs` wording is the guard over-rejecting — also a
  regression.
- `validate_workflow` accepting all six is the current state (runtime guard only);
  a validate-time rejection of 1–5 is an improvement, note it and move on.
cleanup: `delete_output` on the six failed runs' `run_dir`s (each is empty).
metrics: none.
source: tester, model `opus` via provider `anthropic`, verified in #233 on 2026-09-18
against dw `0.4.0-beta.6` / transformers `5.16.1` on `lem` (jobs `5e23773d18de`,
`a1518b26136d`, `05765286f54e`, `5937f06e6510`, `6c0ae99d62db`, control
`2ee19cd29502`) in workspace `qa-verify-233`.

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

## Performance

### S-P001 — default image generation latency
Time S-F003 (single image, default params) using the job's own
`started_at`→`finished_at` — not wall clock, which adds queue time and agent
turnaround. Log **cold** (first SD 1.5 run of the session, model loading from
disk) and **warm** (a later default run with the model resident, e.g.
S-F009's) as separate `condition`s; they are different numbers.
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
