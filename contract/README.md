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
final session, whose only job for them is to file failures (step 4 of
`REGRESSION.agent.md`). Adding `runner: script` edits a case, so it goes
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

| case | status | time |
|---|---|---|
| S-F002 | passes on lem, 2026-09-22 | 0.02 s |
| S-F028 | passes on lem, 2026-09-22 | 0.23 s |
| S-F036 | passes on lem, 2026-09-22 | 0.11 s |

A mutation check changed one expectation in each case: every changed
expectation failed, with a readable message. None of these is marked
`runner: script` in the suite yet; that needs approval.
