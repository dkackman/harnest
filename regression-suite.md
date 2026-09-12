# Regression suite — dw MCP server

Maintained by the regression agent (`agents/REGRESSION_AGENT.md`), run via
`run-regression.sh`. Each case is intent + expected result, not a pinned
tool/param name — confirm the exact call shape against the live tool schema
each run, since the server evolves. Grows over time: new cases get appended
to the relevant section, `last run:` notes accumulate so a baseline drifting
over many runs is visible.

Workspace for every case: `regression-smoke` (created once, reused).

Fixtures vs. outputs: `regression-smoke` is the suite's own workspace, and
it may keep durable fixtures there for the convenience of future runs —
workflows the suite authors, input assets it uploads, anything a case is
faster or more stable for having ready-made. Every fixture is listed in the
"Fixtures" section below (name, what it's for, which cases use it); if it's
not listed, it's not a fixture and gets cleaned up.

Cleanup: everything a case *generates* (outputs, and any asset it links from
an output) is deleted as soon as the case's checks — and any later case
that needs it, called out in `cleanup:` — are done, via `delete_output` /
`delete_asset` or whatever the live schema calls them. The only exception
is an artifact needed to reproduce a failure being filed: keep it, name it
in the issue, and note it in the case's `last run:` line. At the end of a
run `regression-smoke` should hold only listed fixtures plus artifacts an
open issue references; anything else — including repro artifacts whose
issue has since closed — gets deleted on the next run's final sweep. Never
delete the workspace itself, and never delete anything outside
`regression-smoke`.

## Fixtures

Durable contents of `regression-smoke` that persist across runs. Add a line
when a case starts relying on one; remove the line (and the fixture) when
nothing uses it anymore.

- (none yet)

## Functional

### F001 — create workspace
Create a workspace if `regression-smoke` doesn't already exist.
expected: workspace created (or already-exists is reported cleanly, not an
error) and is selectable/targetable by subsequent calls.
cleanup: none — the workspace and its listed fixtures persist across runs
by design.
last run: —

### F002 — list available tools/templates
Call whatever the server exposes for tool/template discovery (e.g. a
tools-list or templates-list call).
expected: non-empty list; response includes at least one image-generation
capability and at least one audio/workflow template. This is the schema
sanity check every other case leans on.
cleanup: none (read-only).
last run: —

### F003 — generate a single image, default params
Using the server's basic image-generation tool/template, generate one image
in `regression-smoke` with only the required parameters (a simple prompt,
everything else default).
expected: call succeeds, response includes a reference to a generated image
asset (path/id/url per whatever the schema returns), and that asset is
retrievable/listable afterward in the workspace.
cleanup: F006/P002 inspect this output first; delete it right after
they've run (or after this case, if F006 is skipped).
last run: —

### F004 — generate a single image, explicit size/seed
Same as F003 but pin an explicit size and a fixed seed if the tool supports
one.
expected: call succeeds; if a seed param is honored, a second identical call
produces the same image (or the schema documents it as non-deterministic —
either is fine, but note which).
cleanup: same as F003 — hold for F006/P002, then delete both images
(the seed-repeat one too).
last run: —

### F005 — invalid image-generation params are rejected cleanly
Call the image-generation tool with an invalid parameter (e.g. malformed
size, out-of-range value, or a required field omitted).
expected: a clear validation error, not a 500/crash/hang, and not a silently
"corrected" result.
cleanup: confirm nothing was created (a rejected call must not leave an
output behind — if it did, that's part of the finding); delete it if so.
last run: —

### F006 — list/probe workspace contents
After F003/F004, use whatever inspection tool the server offers (list,
probe, etc.) against `regression-smoke`.
expected: the generated assets from this run are visible and correctly
described (type, size, or other basic metadata matches what was requested).
cleanup: this is the last case that needs the F003/F004 outputs — delete
them here, then re-list to confirm they're gone (a deleted output still
showing is a finding).
last run: —

### F007 — basic audio or multi-step template runs end-to-end
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
last run: —

### F008 — delete_output actually removes the file
Generate one small default image, delete it with the server's delete tool,
then list/probe the workspace.
expected: delete call succeeds; the output no longer appears in the listing
and fetching it by name is a clean not-found, not a stale entry or a 500.
This is the case the rest of the suite's cleanup leans on — if it fails,
say so in every other case's issue.
cleanup: the case is its own cleanup.
last run: —

## Performance

### P001 — default image generation latency
Time F003 (single image, default params) end-to-end, call issued to result
returned — not counting any explicit queue-position polling.
baseline: TBD — first run
cleanup: as F003.
last run: —

### P002 — workspace listing/probe latency
Time F006 (listing/probing a workspace with a handful of assets already in
it).
baseline: TBD — first run
cleanup: as F006.
last run: —

### P003 — tool/template discovery latency
Time F002 (the tools/templates list call), cold — i.e. as the first call of
the run, before anything else warms up server-side caches.
baseline: TBD — first run
cleanup: none (read-only).
last run: —
