# Regression suite — dw MCP server — model-specific level

Niche checks tied to a particular model, pipeline, or LoRA/adapter quirk —
not general-purpose behavior any model could hit (that belongs in
[`regression-suite-smoke.md`](regression-suite-smoke.md) or
[`regression-suite-complete.md`](regression-suite-complete.md)). Opt-in
only: `./run-regression.sh model-specific` (or `all`, which also runs the
other two files). Expect these to be slower and more expensive — a model
load, a specific checkpoint, a particular sampler/scheduler combination —
which is exactly why they're kept out of the default cadence.

Maintained by the regression agent (`agents/REGRESSION_AGENT.md`), run via
`run-regression.sh`, and grown by the implementer/tester too (see "Adding a
case" below). Each case is intent + expected result, not a pinned tool/param
name — confirm the exact call shape against the live tool schema each run,
since the server evolves. Grows over time: new cases get appended to the
relevant section, `last run:` notes accumulate so a baseline drifting over
many runs is visible.

## Adding a case

The implementer and the tester both grow this suite, not just the
regression agent. When either of you, in the course of normal work, hits or
fixes something tied to a specific model/pipeline that's worth locking in
so it never silently regresses — add a case to **this** file yourself, same
run (if it's actually general-purpose, use `regression-suite-smoke.md` or
`regression-suite-complete.md` instead — see their headers for the line
between them). Use the existing case format (intent + `expected:` +
`cleanup:`) and a `source:` line naming who added it and why (e.g. `source:
implementer, fix for #42` or `source: tester, found while running
TESTER_TASK.md`). Name the model/pipeline/checkpoint the case depends on
explicitly in its body — a model-specific case that doesn't say which model
it needs is useless to a future run. No separate approval step — the
regression agent already grows these files unsupervised when it notices
gaps; a case either of you adds is the same kind of edit. Leave `last run:`
for the regression agent to fill in on its next pass.

Workspace for every case in this file: `regression-model-specific` (created
once, reused) — kept separate from the other levels' workspaces so a
model-heavy run never skews their timings or clutters their fixtures.

Fixtures vs. outputs: `regression-model-specific` is this suite's own
workspace, and it may keep durable fixtures there for the convenience of
future runs — workflows the suite authors, input assets it uploads,
anything a case is faster or more stable for having ready-made. Every
fixture is listed in the "Fixtures" section below (name, what it's for,
which cases use it); if it's not listed, it's not a fixture and gets
cleaned up.

Cleanup: everything a case *generates* (outputs, and any asset it links from
an output) is deleted as soon as the case's checks — and any later case
that needs it, called out in `cleanup:` — are done, via `delete_output` /
`delete_asset` or whatever the live schema calls them. The only exception
is an artifact needed to reproduce a failure being filed: keep it, name it
in the issue, and note it in the case's `last run:` line. At the end of a
run `regression-model-specific` should hold only listed fixtures plus
artifacts an open issue references; anything else — including repro
artifacts whose issue has since closed — gets deleted on the next run's
final sweep. Never delete the workspace itself, and never delete anything
outside `regression-model-specific`.

## Fixtures

Durable contents of `regression-model-specific` that persist across runs.
Add a line when a case starts relying on one; remove the line (and the
fixture) when nothing uses it anymore.

- (none yet)

## Functional

(none yet — cases land here as the implementer, tester, or regression agent
find model/pipeline-specific behavior worth locking in)

## Performance

(none yet)
