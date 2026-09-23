## #289: get_job reports event_count 0 for a historical job whose events get_job_events still serves in full
filed by: @dkackman

**tool/endpoint:** `get_job` vs `get_job_events`

**repro** (workspace `qa-ep30`, dw 0.4.0-beta.6 on `lem`, after the dw.serve restart that happened between 09:35 and 09:59 UTC today):

1. `get_job(job_id="22932ad7d1b6")` — the ep30 `dialogue-short` run, created 2026-09-21 09:20:36 UTC, finished 09:34:50 UTC, before the restart. Response tail:
   ```
   "event_count": 0,
   "historical": true
   ```
2. `get_job_events(job_id="22932ad7d1b6", limit=5)` → events seq 0–4, `truncated: true`.
3. `get_job_events(job_id="22932ad7d1b6", after=85, limit=50)` → seq 86–95 (`warning` match_levels_held, `bleed_tonal_material`, `step_end`, `workflow_end`, `memory`, `job_status: succeeded`), `last_seq: 95`, `truncated: false`.

So the job has 96 events on record and `get_job_events` pages through all of them, but `get_job.event_count` says 0.

Control: a job run in the current process — `d95ff1b61ed2` (ep31, same workspace, same template) — reports `event_count: 95` on `wait_for_job`/`get_job` and its events page the same way.

**expected:** `event_count` on a historical job equals the number of events `get_job_events` will serve (96 here), or — if the count is genuinely unknown for a job loaded from disk — it is `null`, not `0`. A consumer reading `event_count: 0` + `historical: true` reasonably concludes the events were lost with the process (that's exactly what I concluded and wrote into my notes before checking) and skips `get_job_events`, which is where the job's warnings-with-measurements (`measure_dbfs`, `gain_db`, `flatness`, `harmonicity`) live.

**actual:** `event_count: 0` while 96 events are retrievable.

Small ask: either count the persisted events when rehydrating, or make the field `null` for historical jobs and say so in `get_job`'s description.

(tester agent, model `opus` via provider `anthropic`)
