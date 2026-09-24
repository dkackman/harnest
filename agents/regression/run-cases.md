
## Running cases

1. Read the suite file's header (see Guardrails), then each case's section
   only as you reach it.
2. Confirm the current tool and template schema before assuming a case's
   exact tool name or params still match: the suite describes intent and
   expected behavior, the live schema is ground truth for call shape. If a
   case's tool no longer exists or its params changed incompatibly, that is
   itself a finding to report — don't silently adapt. Use the discovery
   calls' compact default forms (the guide's index, one schema section, the
   summary catalog — S-F015 describes the contract) and drill into the full
   form only when a case needs it.
3. Skip any case carrying a `pending: #NN` line: it is a feature lead's
   acceptance case for behavior not built yet (the tester wrote it from an
   approved plan). Its failure is expected, and not an issue to file. List
   the skipped IDs in your summary and nothing else.
4. Execute each other case in order, against your level's workspace:
   - **Functional case**: make the call(s) described and compare the result
     against the case's `expected:`. Pass or fail.
   - **Performance case**: make the call(s) and measure the operation itself
     (not queue or startup overhead) — the job's own
     `started_at`→`finished_at` whenever the case yields a job, wall clock
     only when it doesn't, and say which (`condition`). Same for a
     functional case with a `metrics:` line: run its checks as usual, and
     measure each named metric too. History is `regression-perf/<case>.jsonl`
     (format in `regression-perf/README.md`); read that one file, not the
     directory. A reading is a regression when it crosses an explicit
     ceiling in the case, or — with `baseline:` still `TBD` or absent — when
     it is more than ~50% over the median of the last 5 entries with the
     same `metric` + `condition` **or** more than ~50% over the median of
     every entry with that key; the second clause catches slow creep a short
     window hides. A human-set `baseline:` is a hard ceiling on top of that.
     Fewer than 3 prior entries: record and move on. Small run-to-run noise
     is not a finding. Append the reading as the last line of that case's
     file, one line per `metric`+`condition`, pass or regression.
   - **Then its `cleanup:` line**: delete what the case made, unless it's
     kept for a repro. A delete that fails, or an output that still lists
     after deletion, is a finding in its own right.
5. Report each failure or regression as you find it ("Reporting a
   failure").

### Growing the suite

If, while exercising the suite, you notice an adjacent basic capability
that isn't covered yet (a template, an error path, a common parameter
combination), add a case for it. Growing the suite is part of the job. It
goes at the end of the relevant section of the level it belongs to — this
file, or another level's if the gap is niche or model-tied there
(`regression-suite-smoke.md`'s "Where a case belongs" draws the line) —
with the next unused ID for *that* file's prefix. A performance case gets
`baseline: TBD — first run`, and you seed its `regression-perf/` file with
the reading you just took. A functional case whose *number* matters as much
as its pass/fail (a payload size, an entry count) gets a `metrics:` line
naming each metric and its `condition`. Keep a case short and concrete —
exact intent, exact expected result, no padding: fresh sessions with no
memory of this one depend on it being self-explanatory.
