# Results ledger

One append-only JSONL file per regression case, named for the case id
(`S-F001.jsonl`, `SE-P001.jsonl`, …), with one line for every session that
was handed the case or answered for it: how it ended and, where the driver
timed it, how long it took. The drivers write it, not the agent:
`run-regression.sh` (through `scripts/record-results.sh`),
`harness.drivers.regression` and the fleet (`harness/results.py`), after
every session. Committed with the suites and `regression-perf/` around
every level (`commit_suite_changes`, `harness.suite.commit_paths`).

What it is for: which cases cost a run its time and how often each one
fails, skips or goes unanswered, read across runs. It is not a
measurement: a `-P` case's timing and a `metrics:` reading belong in
`regression-perf/`, which the agent compares against. Nothing here is
compared by an agent, and a case's outcome here never changes the suite.

One object per line, keys in this order:

```json
{"ts":"2026-10-24T09:12:03Z","level":"smoke","case":"S-F002","outcome":"fail","issue":812,"secs":41.5,"session":"regression:smoke.1 of 9","head":"develop @ 1a2b3c4d5","model":"claude-sonnet-5-5","server":"lem"}
```

- `ts` — UTC, when the driver recorded the line (the session's end).
- `level` — `smoke` / `complete` / `model-specific` / `security`.
- `case` — the case id; matches the filename.
- `outcome` — the session's `REGRESSION-RESULT` line for the case (`pass`,
  `fail`, `skip`, `pending`); else `skip` for a `REGRESSION-SKIP` line; else,
  for a case the session was handed, `not run` when it died or reported its
  server unreachable, and `unreported` when it ended (budget or turns ran
  out) without answering. A case the fleet re-queues gets a second line
  from the session that runs it again.
- `issue` — the issue number a `fail` named (`fail #812`), or `null`.
- `secs` — seconds from the case's `REGRESSION-CASE` line to the next one
  (or the session's end), or `null` when the driver didn't time it. Only
  the fleet times cases; `run-regression.sh` and `harness.drivers.regression`
  write `null`.
- `session` — the session's log label (`regression:smoke.2 of 9`,
  `regression:smoke.lem-1.3`), as in `loop.log`.
- `head` — what the server was running (`deployed_head`).
- `model` — the model id the session resolved to.
- `server` — the server the case ran on (`lem`, `mini-ai`, …).

**Measurement gap.** Only fleet runs (`harness.drivers.fleet`) carry
`secs` today: the fleet watches each session's `REGRESSION-CASE` lines as
they arrive, and the level drivers (`run-regression.sh`,
`harness.drivers.regression`) read the session's log only after it ends,
when it holds no times. Their rows have `"secs": null`. A reader of case
times filters out null and groups by `server`: a time is its server's
hardware, never pooled with another's.

A server other than the primary keeps its own ledger in a subdirectory
named for it (`regression-results/mini-ai/S-F001.jsonl`), same format, as
`regression-perf/` does: its outcomes and times are its own hardware's.
