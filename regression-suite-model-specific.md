# Regression suite — dw MCP server — model-specific level

Niche checks tied to a particular model, pipeline, or LoRA/adapter quirk —
not general-purpose behavior any model could hit (see
[`regression-suite-smoke.md`](regression-suite-smoke.md) for the exact line
between general-purpose and niche). Opt-in only: `./run-regression.sh
model-specific` (or `all`, which also runs the other two files). Expect
these to be slower and more expensive — a model load, a specific
checkpoint, a particular sampler/scheduler combination — which is exactly
why they're kept out of the default cadence.

Workspace: `regression-model-specific` — kept separate from the other
levels' workspaces so a model-heavy run never skews their timings or
clutters their fixtures. Case IDs in this file use the `M-` prefix
(`M-F001`, `M-P001`, ...) so they never collide with the `S-`/`C-` IDs in
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
regression agent — see `regression-suite-smoke.md`'s "Where a case
belongs" for which file. Use the existing case format (intent + `expected:`
+ `cleanup:`), the next unused `M-Fnnn`/`M-Pnnn` ID, and a `source:` line
naming who added it and why (e.g. `source: implementer, fix for #42` or
`source: tester, found while running TESTER_TASK.md`). Name the
model/pipeline/checkpoint the case depends on explicitly in its body — a
model-specific case that doesn't say which model it needs is useless to a
future run. No separate approval step — the regression agent already grows
these files unsupervised when it notices gaps; a case either of you adds is
the same kind of edit. Leave `last run:` for the regression agent to fill
in on its next pass.

## Fixtures

Durable contents of `regression-model-specific` that persist across runs.
Add a line when a case starts relying on one; remove the line (and the
fixture) when nothing uses it anymore.

- (none yet)

## Functional

## Performance
