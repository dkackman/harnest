# Replay benchmark (R1)

Measures the implementer by re-running it on issues that were already fixed
and verified. Each case starts from the `develop` commit just before the real
fix and is scored against that fix. See `HARNESS-ROADMAP.md` R1 for why.

```sh
./run-bench.sh                              # all cases, default config (sonnet, working-tree prompt)
IMPLEMENTER_MODEL=opus ./run-bench.sh       # compare a model
BENCH_PROMPT_REV=<commit> ./run-bench.sh    # compare a prompt revision
BENCH_JOBS=3 ./run-bench.sh 289 74 238      # a subset, in parallel
./run-bench.sh --summary                    # one block per label
```

A run's rows are grouped under `BENCH_LABEL`, which defaults to
`provider/model@<harness commit>` (`+dirty` if `agents/implementer/`
has uncommitted edits). Set it yourself to name an experiment.

## Files

- `entries.tsv` — the curated list: issue, kind, one-line note. Chosen
  2026-09-22 from the 195 `status:verified` issues: fixes of one or two
  commits and 20–600 changed lines, spread across bounced, security, perf,
  engine, MCP, validation, skill-text and template fixes.
- `snapshot.py` — freezes `cases/<n>/` from `gh` and the agents' checkout:
  `meta.json` (pre-fix commit, fix commits, files, hand-off count),
  `issue.md` (title and body as filed; none of the 17 were edited after
  filing), `verify.md` (the owner's last comment), `fix.patch`,
  `tests.patch`. A run never calls `gh`; add an entry, run `snapshot.py`,
  commit the case.
- `replay-note.md` — appended to the implementer prompt under test. It
  turns off GitHub, `lem` and deploy steps and routes the hand-off comment
  to `HANDOFF.md`. It is identical for every configuration, so it cancels
  out of comparisons. `run-bench.sh` also enforces it with deny rules.
- `results/results.jsonl` — one row per (case, run). Checked in, append-only.

## Scores

| field | meaning |
|---|---|
| `verdict` | `pass`/`partial`/`fail` from a fresh `JUDGE_MODEL` session (default `claude-opus-5-5`, no tools) that sees the issue, the real fix, the tester's last comment, the candidate diff, `HANDOFF.md` and the signals below |
| `new_failures` | full-suite pytest failures not already failing at the pre-fix commit (this Mac fails ~18 worker tests at every commit; baselines are cached per commit in `logs/bench/`) |
| `hidden` | the real fix's test changes applied to the candidate tree: `pass`, `fail`, `conflict` or `none`. A candidate that implements the same behavior under other names fails this without being wrong, so it informs the judge rather than deciding the verdict |
| `file_recall` | share of the real fix's non-test files the candidate touched |
| `cost`, `turns`, `ctx_peak_k`, `budget_hit` | from the session's `usage:` line |

## Leak-proofing

A replay that can see the real fix measures nothing. Each case is a fresh
`git init` plus a fetch of the pre-fix sha from the agents' checkout, so no
later commit is in the object store. It has no remote, no MCP server, and
deny rules on `gh`, `ssh`, `git push/fetch/pull/remote/clone`, `curl`,
`wget`, `WebFetch` and `WebSearch`, because the fix and its verify comment
are on GitHub. The shared venv's editable install maps `dw`/`dw_mcp` to the
agents' checkout, so `PYTHONPATH` points each session and each scoring run
at the clone.

## What it doesn't measure

The tester side (that needs `lem` at the pre-fix commit and GPU time), and
deploy mistakes. A replay passes or fails on the diff alone.
