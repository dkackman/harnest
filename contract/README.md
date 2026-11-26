# Contract cases (R6)

Mechanical regression cases, the kind that say "call X with Y, expect field Z",
run by a script instead of an LLM. A script is free, takes about a second,
and gets the same result every time.

```sh
contract/run.py                    # every case in contract/cases/
contract/run.py S-F028 S-F036      # just these
contract/run.py --level smoke
contract/run.py --cases-dir DIR    # cases kept somewhere else, such as drafts
```

`run.py` prints a JSON report and exits 0 if everything passed, 1 if any case
failed, 2 if a case errored or the server was unreachable. `mcp_client.py` is
a standard-library MCP client over streamable HTTP. Like the tester, it's a
pure consumer: `DW_URL`/`DW_TOKEN` and nothing else.

## How a case graduates

The suite file stays the source of truth. A prose case runs as a script only
when both of these hold:

1. `contract/cases/<ID>.json` exists; and
2. the case's block in `regression-suite-<level>.md` has a line reading
   `runner: script`.

`run-regression.sh` then runs those cases through `run.py` before any agent
session and takes them out of the agent's chunks. It hands the report to the
final session, whose only job for them is to file failures ("Reporting a
failure" in `agents/regression/core.md`). Adding `runner: script` edits a case, so it goes
through the same `owner:don` approval as any other change to a case.

The prose stays in the suite. It says *why* the case exists, and the JSON only
says *what* to check. A JSON case must assert everything the prose's
`expected:` asserts. If it can't (the case needs judgment: does the image
look right, is the message useful), the case stays with the LLM.

## Case format

See the docstring at the top of `run.py`: `steps` of `{call, args, expect}`,
where `expect` is a list of assertions on paths into the result (`eq`,
`exists`, `len`, `contains`, `contains_any`, `not_contains`,
`any_contains`, `none_contains`). Cases are data, so writing one needs no
code execution.

A step can keep a value from its answer for later steps, with
`"capture": {"fp": "plan.fingerprint"}`. `"${fp}"` is then filled in anywhere
in a later step's `args` and in the value an assertion compares against, so
"the second call's fingerprint equals the first's" is
`{"path": "plan.fingerprint", "eq": "${fp}"}`. The docstring has the rules.

## Keeping the asymmetry

The implementer never writes or edits anything here. The runner sees only
MCP, never the source or `lem`. A case asserts what the server should do as
the tester verified it, not what the code currently does.

## Written so far

22 cases, every one marked `runner: script` in its suite block.

- 17 smoke cases, all passing on lem on 2026-11-22 (dw 0.23.0-alpha.1) in 3.5 s together:
  S-F002, S-F010, S-F018, S-F026, S-F028, S-F032, S-F035, S-F036, S-F085, S-F108, S-F110,
  S-F124, S-F125, S-F128, S-F130, S-F132, S-F145. Each was mutation-checked: one expectation
  per step changed, and every changed step failed with a readable message. All 17 have
  carried `runner: script` since harnest#280 (2026-11-22).
- 5 added on 2026-11-26 from that day's pilot: SE-F022 and SE-F034 (security), C-F255,
  C-F615 and C-F915 (complete). **These five have not yet been run against a server**, and
  neither have the steps S-F145 gained the same day (the job total before and after its
  `run_workflow`). They were replayed offline against the answers the pilot recorded, with
  one answer changed per case.

Things a case author should know:

- **A case stops at its first failed step.** Six cases (S-F010, S-F026, S-F108, S-F128,
  S-F145, C-F255) send a `run_workflow` the server must refuse, with `acknowledged_cost: true`
  because the server checks cost before arguments. Each follows a validate step asserting
  the same refusal, so a server that stops refusing fails there and the run is never sent.
  If a refusal step is handed a `job_id` anyway, the runner cancels the job.
- **"The same as the earlier call" is a capture.** S-F145 and C-F915 compare against a
  value an earlier step returned. The cases written before capture existed (S-F010, S-F026,
  S-F035, S-F085, S-F108, S-F128) still pin the full text in both steps: a rewording on the
  server fails both and needs the JSON updated.
- **"No new job" is the job total before and after.** S-F145, C-F255 and C-F915 capture
  `list_jobs`' `total` and assert it has not moved. A job another session queues in the same
  scope between the two calls fails the case, and the report shows the two totals.
- **No starts-with, ends-with, pattern, number or either-or assertion, and no following a
  job.** S-F060 and S-F116 stay with the agent for that reason, and S-F147 because it needs
  a paid run. Two cases here approximate: S-F032 asserts a warning *containing* `shots[0]:`
  where its prose says *beginning*, and S-F124 an error *containing* the suggestion where
  its prose says *ending*.
- **Fixtures.** The cases use the common `qa-cast` assets, the stored prompt
  `flux/weighted_portrait` and the `regression-smoke` workspace; the complete cases name
  `regression-complete` on each call that takes a workspace. S-F110 assumes the SDXL repo is
  not downloaded on lem, as its prose does. SE-F022 writes out 33 `for_each` entries, one
  more than the documented cap of 32, behind a step that checks the cap is still 32.
  C-F615 reads the catalog in whatever workspace the runner's session lands in.
