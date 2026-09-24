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
  asset library, reachable from every workspace. S-F114 resamples it in a ~1 s utility
  job; any short audio file substitutes. Read-only — never sliced in place, never
  deleted. The complete suite also uses it.
- `asset:qa-cast/ep6-cold-open.mp4`, `asset:qa-cast/ep3-shot2-reply.mp4`,
  `asset:qa-cast/ep13-episode.mp4` and `asset:qa-cast/ep20-score.wav` — three shots and a
  score bed in the shared asset library. S-F082 binds all four to
  `templates/dissolve-between-shots` in a validate-only call, so only their existence and
  kinds matter here. Read-only, never deleted. The complete suite also uses them, and its
  Fixtures section records the properties its cases depend on.
- `asset:qa-cast/hal-voice.wav` — a 6.48 s 24 kHz mono line in the shared asset
  library. S-F070 transcribes it; any short spoken clip substitutes. Read-only, never
  deleted. The complete suite also uses it.

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
- **From a failed task run.** Take C-F076 part 4's `resample_audio` job
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
running S-F005 and C-F076 against dw 0.4.0-beta.4 on `lem`, workspace `regression-smoke`.
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
  #177 (verified) was `usage` lagging a delete; asserting on the listing's own
  `total` keeps this case independent of it. S-F021 and S-F034 are where `usage` is held to account.
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

### S-F101 — a single-saving-step template's deliverable is marked `final`, so `list_gallery(subfolder="final")` finds it
#302: C-F071 guards the two sequence templates #235 fixed, but the `final` convention had
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

### S-F118 — `export_job` doesn't send an MCP-only agent to fetch a token-gated zip, and a mounted `download_output` with no destination is refused
Before #353, `export_job` told the agent to "fetch the zip URL and unpack it". The URL was
relative and sat behind the server's bearer token, which the agent can't attach. A mounted
`download_output` with no `destination` wrote the file loose in the workspace root, where
no delete tool reaches. Cheap: one ~1 s utility job, no model load.
Workflow: the S-F114 inline `resample_audio` on `asset:qa-cast/ep11-bed.wav`. Validate it,
then `run_workflow(..., workspace="regression-smoke", acknowledged_cost=<plan>,
wait_seconds=55)` → `succeeded`. Its output name is `<name>`.
expected:
- The **served tool descriptions** (the schemas as loaded):
  - `export_job`'s makes fetching conditional on `auth_required`, and says to hand
    `open_url` to the person when it is true.
  - `download_output`'s says a `dw.serve --mcp` endpoint requires `destination`.
- `export_job(job_id=<job>)` returns `zip_url`/`open_url` and `auth_required`.
  - When `auth_required` is `true`, `next` tells the agent to hand `open_url` to the
    person and not fetch it.
  - With DW_PUBLIC_URL unset, the **`absolute_zip_url` key is absent**, not null, and
    `list_gallery` entries carry `url` and no `absolute_url`. If the server has one
    configured, the key is present and equals that base URL + `zip_url`.
- On the mounted server (`get_server_info` → `mcp.mounted: true`),
  `download_output(name=<name>)` with no `destination` is **refused**. The error names
  the `list_gallery` url, the `get_output_*` tools or `keep_output`.
- `download_output(name=<name>, destination="outputs/regsmoke-f118/r1/")` → `saved_to`
  ends in `outputs/regsmoke-f118/r1/<file>`, bytes > 0. After that,
  `delete_output(name="regsmoke-f118/r1/<file>")` → `deleted: true`.
It is a **finding** if either description tells the agent to fetch unconditionally or to
omit `destination`. It is also a finding if `absolute_zip_url` comes back as `null`, or
if the no-destination call succeeds, wherever the file lands.
cleanup: `delete_output(job_id=<job>)`, plus the downloaded copy as above. The export
directory (`exports/<job id>`, a few KB) stays on the server because no MCP tool removes
exports.
metrics: none.
source: tester, verified in #353 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7` (export of `ef9c0e9cc3ff` and a
download/delete of a `templates/restore-faces` output in `default`, not the resample job
above; the DW_PUBLIC_URL-set path is untested, since that is server config).

### S-F119 — gallery reads take an `output:`-prefixed name, and `list_gallery(media=true)` carries duration
You need one audio or video output in the workspace. S-F007's final wav works if you run
this case before S-F007's cleanup. Otherwise run any short audio chain. Note the file's
`name` from `list_gallery(folder=<its folder>)`.
expected:
- `get_gallery_metadata(name="output:<name>")` resolves. It returns the bare `name` and
  a `media` block with `duration_seconds`. It does **not** return a 404 of the form
  `Unknown file: output:<name> - path does not exist`.
- `get_gallery_metadata(name="output:../../etc/passwd")` is still refused. The message
  names the stripped path as disallowed.
- `list_gallery(folder=<its folder>, media=true)`: the entry carries `duration_seconds`,
  and it equals the metadata's `media.duration_seconds`. Image and text entries in a
  `media=true` listing carry no such key.
- `list_gallery(folder=<its folder>)` without `media`: the same entry has no
  `duration_seconds` key.
cleanup: none of its own. Clean up whatever run supplied the file per that run's case,
or with `delete_output(job_id=<job>)` if it was run for this case alone.
metrics: none.
source: tester, verified in #356 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7`. That run used existing `default`-workspace
outputs: a Music 3 mp3 (30.023401 s in both the listing and the metadata), two LTX2 mp4s,
and image entries. The traversal probe was refused with `Unknown file: ../../etc/passwd -
path contains a disallowed pattern`.

### S-F120 — media metadata reports integrated LUFS, and `normalize_audio(target_lufs=…)` hits it or warns at the ceiling
Before #361, `peak_dbfs` was the only level control, and nothing on the server measured
perceived loudness. A sparse voice and a dense score could share a peak yet sit tens of dB
apart. Cheap: one ~3 s utility job, no model load.
`get_gallery_metadata` on `asset:qa-cast/hal-voice.wav` and `asset:qa-cast/ep20-score.wav`.
Then validate and run (`workspace="regression-smoke"`, `acknowledged_cost=<plan>`,
`wait_seconds=55`) one inline workflow with three `normalize_audio` steps, each
`result.content_type: "audio/wav"`:
`up` = ep20-score, `target_lufs=-26, peak_dbfs=-1`; `capped` = hal-voice,
`target_lufs=-16, peak_dbfs=-1`; `plain` = hal-voice, `peak_dbfs=-3` only. Read each
output's `get_gallery_metadata`.
expected:
- Both assets' `media` blocks carry numeric `integrated_lufs` and `true_peak_dbfs` next to
  `peak_dbfs`/`mean_dbfs`. For reference: hal-voice ≈ -20.5 LUFS with peak -1.0, and
  ep20-score ≈ -48.3 LUFS with peak -28.9.
- `up`'s output: `integrated_lufs` within 0.5 LU of -26 and `peak_dbfs` ≤ -1.
- `capped`'s output: `peak_dbfs` ≈ -1.0 (the ceiling holds), with loudness still short of
  -16. The job's `warnings` name `capped`, `target_lufs=-16`, and the shortfall in LU
  (≈ 4.5).
- `plain`'s output: `peak_dbfs` ≈ -3.0 with no loudness warning. Peak-only behaviour is
  unchanged.
- `validate_workflow` with `target_lufs: 3` on any `normalize_audio` step is refused at
  `steps[0].task.arguments.target_lufs`.
It is a **finding** if either LUFS key is missing or `null` on these non-silent inputs, if
`capped` exceeds its ceiling, or if the ceiling hits without a warning.
cleanup: `delete_output(job_id=<job>)`.
metrics: none.
source: tester, verified in #361 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7`. That job (4 steps, in a scratch workspace)
read -26.00 / -30.00 LUFS on target, and the capped step warned "4.5 LU short of the target".
The short (<400 ms) and all-silent `null` paths are untested over MCP.

### S-F121 — a `previous_result:` entry in a task's `inputs` list is resolved, not passed through as a literal
Before #381, `validate_workflow` checked a `previous_result:` reference inside a task's
`inputs` list, but the engine then handed the list over unchanged. The task got the
literal string `"previous_result:step1"`. Cheap: two utility-only jobs, about 2 s each,
no model load.
In `workspace="regression-smoke"`, validate and then run (`acknowledged_cost=<plan>`,
`wait_seconds=55`) this inline workflow:
`{"id":"inputs_reference_check","steps":[{"name":"step1","task":{"command":"gather_inputs","inputs":["value1","value2"]},"result":{"content_type":"application/json","save":false}},{"name":"step2","task":{"command":"gather_inputs","inputs":["previous_result:step1","extra"]},"result":{"content_type":"application/json"}}]}`.
Read each step2 file with `get_output_text`. Then run the same workflow again with step2's
`inputs` set to `[{"value":"previous_result:step1"}]` (a different `id`). Finally, validate
it with `previous_result:nosuch` as step2's first entry.
expected:
- The first run succeeds, and step2's manifest lists three files holding `"value1"`,
  `"value2"` and `"extra"`, in that order. No file contains `previous_result:`.
- The object-entry run's step2 writes two files, `{"value": "value1"}` and
  `{"value": "value2"}`.
- `previous_result:nosuch` is refused by `validate_workflow` at `steps[1].task.inputs[0]`,
  with a message naming the steps that are available.
It is a **finding** if any step2 output holds the literal reference string, or if the run
produces a different iteration count.
cleanup: `delete_output(job_id=<job>)` for each run.
metrics: none.
source: tester, verified in #381 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 4aaeef7` (jobs 4a586838a916 and a859dba09c23,
run in the default workspace and deleted afterwards).

### S-F122 — a required task argument fed by a null variable is a warning on save, and an error only when the caller's arguments leave it null
#364: `validate_workflow` and `save_workflow` refused a document whose required task
argument came from a `variable:` with a null default, claiming the step "does not supply"
it. After the first fix, `save_workflow` accepted it while `validate_workflow` with no
`arguments` still failed it, so the two tools disagreed. Free: validate and save calls,
nothing runs. Let D be `{"id": "regression_null_var", "variables": {"audio": null},
"steps": [{"name": "n", "task": {"command": "normalize_audio", "arguments": {"audio":
"variable:audio"}}, "result": {"content_type": "audio/wav"}}]}`.
1. `validate_workflow(workflow=D)` with no `arguments`.
2. `save_workflow(name="regression-null-var", workflow=D)`, then
   `validate_workflow(name="regression-null-var")` with no `arguments`.
3. `validate_workflow(workflow=D, arguments={})`, and again with `arguments={"audio": null}`.
4. `validate_workflow(name="regression-null-var", arguments={"audio":
   "https://example.com/a.mp3"})`.
5. `validate_workflow(workflow=D)` with the step's `arguments` changed to `{}`, so nothing
   feeds `audio`.
expected:
- Steps 1 and 2 are `valid: true` / saved. Each carries a warning at
  `steps[0].task.arguments.audio` saying `audio` is fed by variable `audio`, which is null.
- Step 3 is `valid: false` both times, with one error at `steps[0].task.arguments.audio`
  that carries `"variable": "audio"` and names the variable.
- Step 4 is `valid: true` with no warnings.
- Step 5 is `valid: false` with the generic "which the step does not supply" error and no
  `variable` key.
It is a **finding** if `save_workflow` refuses D, if steps 1 and 2 disagree with the
save, or if step 3 or step 5 comes back `valid: true`.
cleanup: `delete_workflow(name="regression-null-var")`.
metrics: none.
source: tester, verified in #364 on 2026-09-23 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 773e9d6`.

### S-F123 — `gain_audio` with no region gains the whole track by exactly `gain_db`, through a `pair_audio` chain
Before #395, a `gain_audio` step with no region validated clean and then failed at run
time. Now omitting every region argument means the whole track. Cheap: one ~6 s utility
job, no model load.
Validate, then run (`workspace="regression-smoke"`, `acknowledged_cost=<plan>`,
`wait_seconds=55`) one inline workflow with `"seed": 1`:
`quiet` = `gain_audio(audio="asset:qa-cast/ep31-shot2-shrug.mp4", gain_db=-8)`, result
`audio/wav`; `repaired` = `pair_audio(video=<same asset>, audio="previous_result:quiet",
fit="video")`, result `video/mp4`. Then `get_gallery_metadata` on the asset and on
`repaired`'s output.
expected:
- `validate_workflow` is `valid: true` with no region warning, and the job succeeds.
- `repaired`'s `peak_dbfs`, `mean_dbfs` and `integrated_lufs` each sit 8.0 dB (±0.2)
  below the asset's. For reference, the asset reads peak -1.76 / -16.58 LUFS, and the
  output read -9.77 / -24.63.
- `repaired` keeps the asset's 124 frames, 24 fps and 32 kHz stereo.
It is a **finding** if the run fails, or if the drop is 0 dB or only covers part of the
track (then `mean_dbfs` moves by less than `peak_dbfs`).
cleanup: `delete_output(job_id=<job>)`.
metrics: none.
source: tester, found while running TESTER_TASK.agent.md (ep41, confirms #395), on
2026-09-24 over MCP as model `claude-opus-5-5` via provider `anthropic`, job
`f8fe1be9fca1` in `qa-ep41`.

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
metrics: none.
source: tester, verified in #397 on 2026-09-24 over MCP as model `claude-opus-5-5` via
provider `anthropic` against `develop @ 9fed519`.

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
