# Performance log

One append-only JSONL file per regression case, named for the case id
(`S-P001.jsonl`, `S-F015.jsonl`, …). This is where measurements live — the
suite files (`regression-suite-*.md`) hold only the durable test and are never
edited on a pass. Checked in and committed by `run-regression.sh` around every
level, the same as the suite files: a measurement is evidence, and creep is only
visible across weeks if the history survives the machine.

Which cases log: every performance case (`*-Pnnn`), and any functional case
that declares a `metrics:` line. Nothing else — a wall-clock reading from an
ordinary functional case is noise, not a metric.

One object per line, keys in this order:

```json
{"ts":"2026-09-13T23:31:00Z","level":"smoke","case":"S-P001","metric":"latency","condition":"cold","value":8.9,"unit":"s","server":"0.4.0-beta.3","model":"opus","provider":"anthropic","ref":"job dbd1304d11f3"}
```

- `ts` — UTC, from `date -u +%FT%TZ`.
- `level` — `smoke` / `complete` / `model-specific` / `security`.
- `case` — the case id; matches the filename.
- `metric` — `latency`, `bytes`, `count`, or whatever the case's `metrics:` line names.
- `condition` — distinguishes readings that must not be pooled: `cold` / `warm`
  for latency, `wall` when the figure is consumer-side wall clock (and so
  includes agent turnaround), `-` when there is only one kind.
- `value`, `unit` — number and its unit (`s`, `bytes`, `entries`).
- `server` — the version the server reports, or `null` if it doesn't.
- `model`, `provider` — what the agent that measured it was running as.
- `ref` — what was measured: a job id (prefer the job's own
  `started_at`→`finished_at` over wall clock whenever the case yields a job),
  a call, or the fixture used. Optional `note` for anything a reader
  comparing two lines would need (`"71 entries"`, `"time approximate"`).

Reading: an agent reads only the file for the case it is about to compare
(`Read regression-perf/<case>.jsonl`) — never the whole directory. Append by
reading that file and writing it back with the new line last; never rewrite or
drop an existing line. The comparison rule (what counts as a regression against
this history) is in `agents/regression/run-cases.md`, step 3.
