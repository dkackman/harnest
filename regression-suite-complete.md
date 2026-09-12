# Regression suite — dw MCP server — complete level

Broader, slower general-purpose checks: edge cases, less common parameter
combinations, anything worth checking but not fast/central enough to run
every smoke pass. Still general-purpose — not tied to any one
model/pipeline (see [`regression-suite-smoke.md`](regression-suite-smoke.md)
for the exact line between the two, and
[`regression-suite-model-specific.md`](regression-suite-model-specific.md)
for what's niche instead). Running this level also runs
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
Grows over time: new cases get appended to the relevant section, `last
run:` notes accumulate so a baseline drifting over many runs is visible.

## Adding a case

The implementer and the tester both grow these suites, not just the
regression agent — see `regression-suite-smoke.md`'s "Where a case
belongs" for which file. Use the existing case format (intent + `expected:`
+ `cleanup:`), the next unused `C-Fnnn`/`C-Pnnn` ID, and a `source:` line
naming who added it and why (e.g. `source: implementer, fix for #42` or
`source: tester, found while running TESTER_TASK.md`). No separate approval
step — the regression agent already grows these files unsupervised when it
notices gaps; a case either of you adds is the same kind of edit. Leave
`last run:` for the regression agent to fill in on its next pass.

## Fixtures

Durable contents of `regression-complete` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- (none yet)

## Functional

## Performance
