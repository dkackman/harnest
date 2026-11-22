# Contract cases (R6)

Mechanical regression cases, the kind that say "call X with Y, expect field Z",
run by a script instead of an LLM. A script is free, takes about a second,
and gets the same result every time.

```sh
contract/run.py                    # every case in contract/cases/
contract/run.py S-F028 S-F036      # just these
contract/run.py --level smoke
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

## Keeping the asymmetry

The implementer never writes or edits anything here. The runner sees only
MCP, never the source or `lem`. A case asserts what the server should do as
the tester verified it, not what the code currently does.

## Written so far

17 cases, all passing on lem on 2026-11-22 (dw 0.23.0-alpha.1) in 3.5 s together:
S-F002, S-F010, S-F018, S-F026, S-F028, S-F032, S-F035, S-F036, S-F085, S-F108, S-F110,
S-F124, S-F125, S-F128, S-F130, S-F132, S-F145. Each was mutation-checked: one expectation
per step changed, and every changed step failed with a readable message.

Only S-F002 and S-F028 are marked `runner: script` in the suite; the rest wait on approval.

Things a case author should know:

- **A case stops at its first failed step.** Five cases (S-F010, S-F026, S-F108, S-F128,
  S-F145) send a `run_workflow` the server must refuse, with `acknowledged_cost: true`
  because the server checks cost before arguments. Each follows a validate step asserting
  the same refusal, so a server that stops refusing fails there and the run is never sent.
  If a refusal step is handed a `job_id` anyway, the runner cancels the job.
- **"The same message" is pinned.** The runner cannot compare two steps, so where the prose
  says a second call returns the same message as the first, both steps assert the full
  text. A rewording on the server fails both and needs the JSON updated.
- **No starts-with, ends-with, pattern or cross-step assertion.** S-F060 and S-F116 stay
  with the agent for that reason; S-F147 because it needs a paid run.
- **Fixtures.** The cases use the common `qa-cast` assets, the stored prompt
  `flux/weighted_portrait` and the `regression-smoke` workspace. S-F110 assumes the SDXL
  repo is not downloaded on lem, as its prose does.
