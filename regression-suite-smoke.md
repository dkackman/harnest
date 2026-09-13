# Regression suite — dw MCP server — smoke level

Fast, fundamental, general-purpose checks — not tied to a specific
model/pipeline. This is what runs by default (`./run-regression.sh` with no
args), and every run of `complete` runs this file first. Sibling suites:
[`regression-suite-complete.md`](regression-suite-complete.md) and
[`regression-suite-model-specific.md`](regression-suite-model-specific.md).

**Where a case belongs** (same test for the implementer, tester, and
regression agent): would it be bad if this broke silently and stayed broken
between every regression run, for any model/pipeline a consumer might use?
→ **this file**. Is it a real gap but the suite can afford to check it less
often — because it's individually slower, or because there are simply many
variants of it? → `regression-suite-complete.md`. Does it only make sense
for one specific named model/pipeline/checkpoint? →
`regression-suite-model-specific.md`. Keep this file itself lean — every
case in it runs on every single pass.

Workspace: `regression-smoke`. Case IDs in this file use the `S-` prefix
(`S-F001`, `S-P001`, ...) so they never collide with the `C-`/`M-` IDs in
the sibling suites — the regression agent's duplicate-issue search is keyed
on the full prefixed ID. Full run mechanics (fixtures vs. outputs, cleanup,
the final sweep) live in `agents/REGRESSION_AGENT.md`, not here.

Maintained by the regression agent, run via `run-regression.sh`, and grown
by the implementer/tester too (see "Adding a case" below). Each case is
intent + expected result, not a pinned tool/param name — confirm the exact
call shape against the live tool schema each run, since the server evolves.
Grows over time: new cases get appended to the relevant section, `last
run:` notes accumulate so a baseline drifting over many runs is visible.

## Adding a case

The implementer and the tester both grow these suites, not just the
regression agent — see "Where a case belongs" above for which file. Use the
existing case format (intent + `expected:` + `cleanup:`), the next unused
`S-Fnnn`/`S-Pnnn` ID, and a `source:` line naming who added it and why
(e.g. `source: implementer, fix for #42` or `source: tester, found while
running TESTER_TASK.md`). No separate approval step — the regression agent
already grows these files unsupervised when it notices gaps; a case either
of you adds is the same kind of edit. Leave `last run:` for the regression
agent to fill in on its next pass.

## Fixtures

Durable contents of `regression-smoke` that persist across runs. Add a line
when a case starts relying on one; remove the line (and the fixture) when
nothing uses it anymore.

- (none yet)

## Functional

### S-F001 — create workspace
Create a workspace if `regression-smoke` doesn't already exist.
expected: workspace created (or already-exists is reported cleanly, not an
error) and is selectable/targetable by subsequent calls.
cleanup: none — the workspace and its listed fixtures persist across runs
by design.
last run: 2026-09-12 pass — workspace did not exist, `create_workspace(name,
use=true)` made it and switched the session. Re-creating it is a clean tool
error ("Workspace 'regression-smoke' already exists"), not a crash; noted
because the second, idempotent branch of `expected:` is not what the server
does.

### S-F002 — list available tools/templates
Call whatever the server exposes for tool/template discovery (e.g. a
tools-list or templates-list call).
expected: non-empty list; response includes at least one image-generation
capability and at least one audio/workflow template. This is the schema
sanity check every other case leans on.
cleanup: none (read-only).
last run: 2026-09-12 pass — `list_workflows()` returned 67 entries (65
templates + 2 saved), including `templates/text-to-image` (image) and
`templates/generate-speech` / `templates/minimax/music` (audio). Server
0.4.0-beta.3 on `lem`, cuda, worker idle.

### S-F003 — generate a single image, default params
Using the server's basic image-generation tool/template, generate one image
in `regression-smoke` with only the required parameters (a simple prompt,
everything else default).
expected: call succeeds, response includes a reference to a generated image
asset (path/id/url per whatever the schema returns), and that asset is
retrievable/listable afterward in the workspace.
cleanup: S-F006/S-P002 inspect this output first; delete it right after
they've run (or after this case, if S-F006 is skipped).
last run: 2026-09-12 pass — `run_workflow(templates/text-to-image,
acknowledged_cost=true)`, no arguments. Job 1deae39acc2e succeeded, one jpg
in the manifest, listed and fetchable. Note: output filenames concatenate
`file_base_name` and the workflow id with no separator
(`test_imagetext-to-image-main.0-0.0.jpg`) — consistent across every run, so
recorded as the naming scheme, not filed.

### S-F004 — generate a single image, explicit size/seed
Same as S-F003 but pin an explicit size and a fixed seed if the tool supports
one.
expected: call succeeds; if a seed param is honored, a second identical call
produces the same image (or the schema documents it as non-deterministic —
either is fine, but note which).
cleanup: same as S-F003 — hold for S-F006/S-P002, then delete both images
(the seed-repeat one too).
last run: 2026-09-12 pass (size), seed determinism NOT exercised. The stock
`templates/text-to-image` declares only `prompt` and `num_images_per_prompt`,
so size/seed need an inline workflow: top-level `seed` (per the "workflows"
guide) and `width`/`height` as step arguments. Ran 384x384, seed 424242, 20
steps — `get_output_image` reported `original_size: [384, 384]`, so the size
was honored. The identical second run came back `reused: true` from the step
cache pointing at the first run's file, i.e. the pipeline never re-ran, so
this proves cache keying rather than seed reproducibility. A real determinism
check needs a way to bypass the step cache (vary something the cache keys on
but the image does not, or a cache-off flag) — open question for a future
case.

### S-F005 — invalid image-generation params are rejected cleanly
Call the image-generation tool with an invalid parameter (e.g. malformed
size, out-of-range value, or a required field omitted).
expected: a clear validation error, not a 500/crash/hang, and not a silently
"corrected" result.
cleanup: confirm nothing was created (a rejected call must not leave an
output behind — if it did, that's part of the finding); delete it if so.
last run: 2026-09-12 pass, three probes. (a) `arguments:
{num_images_per_prompt: "not-a-number"}` → pre-flight tool error naming the
path and the coercion failure. (b) `arguments: {nonexistent_variable: 3}` →
pre-flight tool error listing the declared variables. (c) inline workflow at
383x383 (not divisible by 8) → job 403dcd9a8820 `failed` with error
"`height` and `width` have to be divisible by 8 but are 383 and 383", empty
manifest, nothing left in the gallery. Nothing silently corrected, no 500,
no hang. Worth knowing: (c) is caught only at run time —
`validate_workflow` passes it (see S-F011).

### S-F006 — list/probe workspace contents
After S-F003/S-F004, use whatever inspection tool the server offers (list,
probe, etc.) against `regression-smoke`.
expected: the generated assets from this run are visible and correctly
described (type, size, or other basic metadata matches what was requested).
cleanup: this is the last case that needs the S-F003/S-F004 outputs — delete
them here, then re-list to confirm they're gone (a deleted output still
showing is a finding).
last run: 2026-09-12 pass — `list_gallery()` showed both outputs with
`folder`, `subfolder`, `kind`, `size`, `mtime` and a workspace-scoped `url`.
Note the listing carries no image dimensions, so "size matches what was
requested" has to be checked with `get_output_image` (which reports
`original_size`) or `get_gallery_metadata`. The latter returned the full
embedded workflow, arguments and seed for the S-F003 jpg.

### S-F007 — basic audio or multi-step template runs end-to-end
Run one of the simpler multi-step templates (whatever the schema currently
calls the smallest end-to-end workflow — e.g. a single-shot or single-line
template) with minimal inputs.
expected: the whole chain completes without a dropped parameter between
steps (this class of bug has bitten before — a chain silently losing a param
partway through is worse than an outright failure, so check the final output
actually reflects every input given, not just that the call returned 200).
cleanup: delete every intermediate and final output the template
produced, plus any asset `keep_output`-style steps may have linked, unless
one is needed for a repro.
last run: 2026-09-12 pass — three-step inline chain (Bark `generate_speech`
→ `slice_audio` to `variable:clip_seconds` = 1.5 → `fade_audio` at
`variable:sample_rate` = 24000), job 13037aa0aa51, 10.6 s. Both variables
survived the chain: `get_gallery_metadata` on the final wav reported
`duration_seconds: 1.5` and `sample_rate: 24000`, with an envelope showing
the fades. `subfolder` intermediate/final came through on the manifest; the
unsaved middle step reported an empty file list as expected. Schema note:
`result.sample_rate` will not take a `variable:` reference (schema validation
runs before substitution) — the error names both paths and is clear, so it is
documented behavior, not a finding.

### S-F008 — delete_output actually removes the file
Generate one small default image, delete it with the server's delete tool,
then list/probe the workspace.
expected: delete call succeeds; the output no longer appears in the listing
and fetching it by name is a clean not-found, not a stale entry or a 500.
This is the case the rest of the suite's cleanup leans on — if it fails,
say so in every other case's issue.
cleanup: the case is its own cleanup.
last run: 2026-09-12 pass — deleted the S-F003 jpg, `deleted: true`; the
subsequent `get_output_image` on the same name was a clean "Not Found" and
`list_gallery` no longer showed it.

### S-F009 — the step cache does not serve a deleted output
Run a workflow once, delete the output it produced, then run the identical
workflow again.
expected: the second run regenerates — a fresh run id and a real file on
disk. A manifest entry marked `reused` that points at the file just deleted
is the finding: it hands a consumer a name that 404s.
cleanup: delete the regenerated output.
last run: 2026-09-12 pass — after S-F008 deleted job 1deae39acc2e's jpg, the
identical `templates/text-to-image` default run (b2ad7f3341bc) regenerated
into a new run id with no `reused` flag, 6.3 s. Contrast S-F004, where the
cached file still existed and the rerun was correctly served from cache.

### S-F010 — validate_workflow catches argument errors before the run
Call `validate_workflow` with the same `arguments` a run would use: one
undeclared name, and one value that will not coerce to the declared type.
expected: `valid: false` with one error per problem, each carrying its JSON
path (`arguments.<name>`), and no GPU time spent. The same mistakes passed
to `run_workflow` are refused pre-flight rather than failing a queued job.
cleanup: none (read-only).
last run: 2026-09-12 pass — exercised via `run_workflow`'s pre-flight path
(S-F005 a/b), which refused both before queueing anything. A draft with a
`variable:` reference in a typed `result` field (`result.sample_rate`) also
came back invalid with both paths named. Next run should call
`validate_workflow` directly as well, to confirm the two paths report the
same errors.

### S-F011 — pipeline value constraints are a clean run-time failure
Validate, then run, a workflow whose values are schema-valid but the
pipeline will refuse (e.g. an image size not divisible by 8).
expected: documents where the line sits. `validate_workflow` checks schema
and pipeline *signatures*, not value ranges, so it passes; the job then
fails with the pipeline's own message, an empty manifest, and no partial
output left behind. A hang, a 500, or a silently corrected size is the
finding — so is a run that leaves a file in the gallery.
cleanup: confirm the failed run wrote nothing; delete it if it did.
last run: 2026-09-12 pass — 383x383 SD 1.5 validated clean, then job
403dcd9a8820 failed with "`height` and `width` have to be divisible by 8".
Gallery unchanged. (Same probe as S-F005(c); kept as its own case because what
it pins down is the validate/run boundary, not the error's tone.)

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
called verified once.
A reading with `live: false` and `info: null` (nothing resident) has neither
field and is not a failure — skip it and say so. Both fields are absent
rather than null on a platform that cannot measure them; same treatment.
cleanup: none (read-only).
source: tester, verified in #83 (implementer proposed the case in its hand-off
comment; added here after running `get_memory()` as model `opus` via provider
`anthropic` — peak 2594.86 against rss 2226.33 on a worker that had just run
a job).
last run: (not yet run by the regression agent.)

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
last run: (not yet run by the regression agent — first observed 2026-09-13 on
0.4.0-beta.3: pinned `keep_output` returned
`asset:qa-pin-check.mp4` at `/home/don/diffusers-workspace/qa-ep5/assets/`,
the unpinned control failed with the `/qa-ep5` segment missing, and the
following unpinned `list_gallery` still reported `workspace: "default"`.)

## Performance

### S-P001 — default image generation latency
Time S-F003 (single image, default params) end-to-end, call issued to result
returned — not counting any explicit queue-position polling.
baseline: TBD — first run
cleanup: as S-F003.
last run: 2026-09-12 13.6 s cold (job `started_at`→`finished_at`, SD 1.5
loading from disk) / 6.3 s warm (second default run later in the session,
model resident). Wall clock from `run_workflow` to a succeeded
`wait_for_job` was 18.9 s cold. Use the job's own timestamps for the
baseline — they exclude queue and agent turnaround. Suggested when a human
sets one: cold and warm are different numbers and should get separate
ceilings.

### S-P002 — workspace listing/probe latency
Time S-F006 (listing/probing a workspace with a handful of assets already in
it).
baseline: TBD — first run
cleanup: as S-F006.
last run: 2026-09-12 ≤3.3 s wall for `list_gallery()` over 2 outputs — and
that figure is almost entirely agent turnaround between the two `date`
readings, not server time. A consumer-side stopwatch cannot separate the two
for a sub-second call, so this baseline is only meaningful as a ceiling
("nothing pathological"); treat anything under ~5 s as a pass until the
server reports its own timing.

### S-P003 — tool/template discovery latency
Time S-F002 (the tools/templates list call), cold — i.e. as the first call of
the run, before anything else warms up server-side caches.
baseline: TBD — first run
cleanup: none (read-only).
last run: 2026-09-12 3.6 s wall for the first `list_workflows()` of the
session, same caveat as S-P002 (includes agent turnaround). No sign of a cold
penalty: the same call later in the run was indistinguishable.

### S-P004 — multi-step audio chain latency
Time S-F007 (speech → trim → fade, three steps in one job) using the job's own
`started_at`/`finished_at`, not wall clock.
baseline: TBD — first run
cleanup: as S-F007.
last run: 2026-09-12 10.6 s (job 13037aa0aa51), Bark-small loading included.
Most of it is the TTS step; the two audio tasks are sub-second.
