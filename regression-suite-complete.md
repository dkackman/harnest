# Regression suite — dw MCP server — complete level

Broader, slower general-purpose checks: edge cases, less common parameter
combinations, anything worth checking but not fast/central enough to run
every smoke pass. Still general-purpose — not tied to any one
model/pipeline (those go in
[`regression-suite-model-specific.md`](regression-suite-model-specific.md)).
Running this level also runs [`regression-suite-smoke.md`](regression-suite-smoke.md)
(`./run-regression.sh complete`); this file holds only the cases on top of
that.

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
fixes something general-purpose but slower or edge-case-y — not fast enough
for `regression-suite-smoke.md`, not niche enough for
`regression-suite-model-specific.md` — add a case to **this** file yourself,
same run. Use the existing case format (intent + `expected:` + `cleanup:`)
and a `source:` line naming who added it and why (e.g. `source:
implementer, fix for #42` or `source: tester, found while running
TESTER_TASK.md`). No separate approval step — the regression agent already
grows these files unsupervised when it notices gaps; a case either of you
adds is the same kind of edit. Leave `last run:` for the regression agent to
fill in on its next pass.

Workspace for every case in this file: `regression-complete` (created once,
reused) — kept separate from `regression-smoke` so a slower/heavier
`complete` run never skews smoke-level timings or clutters its fixtures.

Fixtures vs. outputs: `regression-complete` is this suite's own workspace,
and it may keep durable fixtures there for the convenience of future runs —
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
run `regression-complete` should hold only listed fixtures plus artifacts
an open issue references; anything else — including repro artifacts whose
issue has since closed — gets deleted on the next run's final sweep. Never
delete the workspace itself, and never delete anything outside
`regression-complete`.

## Fixtures

Durable contents of `regression-complete` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- (none yet)

## Functional

(none yet — cases land here as the implementer, tester, or regression agent
find general-purpose behavior worth checking beyond smoke-level coverage)

## Performance

(none yet)
