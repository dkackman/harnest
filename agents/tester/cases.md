
## Adding a regression case

When you confirm something over MCP this session that is basic enough that
a future regression in it would be bad and easy to miss, add a case to the
suite file that fits: `regression-suite-smoke.md` (fast, fundamental,
general-purpose — the common case), `regression-suite-complete.md`
(general-purpose but slower or edge-case-y),
`regression-suite-model-specific.md` (tied to one model or pipeline), or
`regression-suite-security.md` (its failure would be a boundary escape: code
execution, a file outside the server's roots, an off-box request, a leaked
secret). `regression-suite-smoke.md`'s "Where a case belongs" section draws
the line if you're unsure.

- Same format as the file's existing cases, the next unused ID for that
  file's prefix, and a `source:` line: `source: tester, verified in #NN` or
  `source: tester, found while running TESTER_TASK.agent.md` (the standing
  task's old file name, kept so the suites stay searchable).
- Follow the file's own "Adding a case" section, including the `metrics:`
  line and the `regression-perf/<case>.jsonl` seed for a performance case or
  one whose number matters as a trend (format in
  `regression-perf/README.md`). Measurements never go in the suite file.
- Only for something you actually ran over MCP this session — never from
  the implementer's comment alone. Most verifications warrant no case.

### Durable or once

A suite case runs on every regression pass for as long as the suite
exists, so it has to check something a later code change could break: a
tool's answer, a refusal, a warning, an output's properties. Some checks
can only be made once, and those are never suite cases:
- what a bench, probe, audit or drill record says, and whether the jobs it
  cites exist, finished, or differ the way the record claims;
- what a hand-off or issue comment contains;
- that a stage changed nothing else, or a comparison of before and after
  a deploy;
- anything that needs a tool you don't have (`npm`, the checkout);
- "run cases X to Y again".

Make a one-time check where it belongs, in the verify session, and report
it in that session's comment.

**One behavior, one case.** Arms of one check over the same calls and
fixtures (one argument's refusal matrix, one rule on each template that
carries it) are numbered arms of a single case, each with its own
`expected:` bullet. They are not a case each. Before you add a case,
`Grep` the suite for the tool or task it calls: when a case already checks
that behavior, the suite needs no second one.
