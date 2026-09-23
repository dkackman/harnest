
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
