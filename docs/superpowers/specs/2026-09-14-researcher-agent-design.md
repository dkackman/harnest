# Researcher agent — design

## Goal

A third standalone agent (alongside the regression agent), run outside the
implementer/tester alternation, that turns an "idea" GitHub Issue into a
disposition: reject it, propose a concrete plan for the implementer to run
with or send to Don, or ask Don directly for input. It researches the
codebase (read-only) and any links in the issue, then assesses complexity,
feasibility, and value before deciding.

## Ticket protocol additions

- New label **`idea`**, marking an issue as an idea ticket rather than a bug
  report. New template `.github/ISSUE_TEMPLATE/idea-ticket.md` in the
  `dkackman/diffusers-workflow` repo (alongside the existing
  `mcp-ticket.md`), pre-applying the `idea` label, with fields for the idea
  itself, motivation, and any reference links — no repro-steps section,
  which doesn't apply.
- New owner label **`owner:researcher`**, extending the existing
  "`owner` is a label, exactly one of `owner:implementer` / `owner:tester` /
  `owner:don`" invariant to a fourth value. An idea issue starts life with
  `idea` + `owner:researcher`, no status label. CLAUDE.md's ticket-protocol
  section and the status-board query's label-prefix comment get updated to
  say so.
- Disposition reuses **existing** status/label conventions rather than
  inventing researcher-specific ones:
  - **Reject** → `wontfix` + `gh issue close --reason "not planned"`,
    reasoning in a comment. Same convention as the implementer's reject
    path (including: only a human overturns a repeated `wontfix`).
  - **Propose to implementer** → remove `owner:researcher`, add
    `owner:implementer`, no status label — ready, same as any fresh ticket.
    The proposal (feasibility/complexity/value/recommendation) goes in a
    comment. No change to `IMPLEMENTER_AGENT.md`'s triage: it already reads
    the full issue body and comments before acting, so a researcher's
    proposal is just more context, not a new rule to encode — and the
    implementer still independently decides run-with-it vs.
    `status:needs-approval`, exactly as it would for a self-discovered fix.
  - **Ask Don** → remove `owner:researcher`, add `owner:don` +
    `status:needs-approval` — the same parking convention already used
    elsewhere, with the question in a comment.
- **External-filer parking** applies to idea issues exactly as it does
  today to bug tickets. `park_external_issues` (currently defined inline in
  `run-loop.sh`) is repo-wide already — it matches every open issue filed by
  a login other than `TICKET_OWNER`, regardless of label — so no filter
  change is needed. It moves into `providers.sh` as a shared helper (next to
  `co_author_for`, `runtime_note`, etc.) so `run-research.sh` calls the same
  function `run-loop.sh` does, rather than duplicating or drifting from it.
  `run-research.sh` calls it once at the top of each invocation, same as
  `run-loop.sh` does per cycle.

## Access & isolation

The researcher gets a **third isolation shape**, distinct from both the
implementer (full read/write + SSH) and the tester/regression agent
(MCP-consumer-only, no source checkout at all):

- cwd = `SOURCE_DIR` (the same checkout the implementer uses), so `Read` /
  `Grep` / `Glob` and `git log` / `git blame` / `git show` resolve naturally
  against real paths — needed to assess feasibility and complexity against
  actual code.
- **Read-only**: no `Edit`/`Write` on source, no `git` write subcommands, no
  `ssh lem`. It assesses; it never implements or touches the live server's
  filesystem or process.
- `WebFetch`, to follow links an idea issue cites (prior art, a paper, an
  upstream library's docs).
- `gh`, for issue management (read/comment/label/close), matching the CLI
  surface the other roles already get.
- Read-only `dw` MCP access — `list_workflows`, `list_guides`,
  `list_pipelines`, `list_classes`, `get_server_info`, `get_schema`, and
  similar discovery calls only, no job/workspace/asset mutation — so it can
  check "does this already exist as a workflow" against the live catalog
  instead of guessing from source alone. This is new relative to the
  implementer/tester split (neither mixes source access with MCP access
  today) but stays inside the "read-only" character of the role.
- Enforced the same way the tester/regression agent's fence is enforced: a
  new `RESEARCHER_PERMISSION_FLAGS` array in `providers.sh`,
  `--permission-mode dontAsk` + an explicit `--allowedTools` list — not the
  implementer's `--permission-mode auto`. No `Bash(git commit*)`, no
  `Bash(ssh *)`, no `Bash(curl *)`, no generic `Edit`/`Write` on
  `SOURCE_DIR` (only the narrow file tools it actually needs — none, in the
  current design; it has no durable file of its own to maintain, unlike
  `qa-bible.md` or the regression suites).

## `agents/RESEARCHER_AGENT.md` (new file)

Structured like `REGRESSION_AGENT.md`: states its isolation and why (mirrors
the "Do not shortcut its verification" framing the implementer prompt uses
for the tester, inverted — the researcher must not shortcut the
implementer's judgment either: a proposal is input, not a decision). Per
invocation it is handed exactly one issue number (see driver, below) and:

1. Reads the issue (`gh issue view <n> --comments`).
2. Triage first, same spirit as the implementer's step 1: confirm it's
   still `idea` + `owner:researcher` with no status label (a stale
   invocation could race a human edit); check for an existing duplicate idea
   or an already-shipped equivalent via `gh issue list --state all --search`
   and a codebase check.
3. Research: read relevant source, `git log`/`blame` for history/prior
   attempts, follow links via `WebFetch`, check the live catalog via
   read-only `dw` calls.
4. Assess and write one comment covering Feasibility / Complexity / Value /
   Recommendation — short and concrete, like a regression suite case: no
   prose padding, future readers (a fresh implementer session) depend on it
   being self-explanatory.
5. Disposition per "Ticket protocol additions" above.
6. Never closes an issue as `completed`/`verified` (that's the tester's
   verb), never touches an issue it doesn't own, never edits source or
   regression-suite files, never proposes a regression case itself (out of
   scope — that stays the implementer's/tester's/regression agent's
   channel, since a case shouldn't be recorded before anything is even
   built).
7. Runtime note: `runtime_note` in `providers.sh` gains a `researcher`
   branch (examples: "a proposal comment, a reject reason, a question to
   Don") so its judgment calls are attributable, same as the other three
   roles.

## `run-research.sh` (new driver script)

Standalone, invoked by hand/cron/`loop` skill — never part of
`run-loop.sh`'s alternation, matching `run-regression.sh`'s pattern.
Structure mirrors `run-regression.sh`'s header/flag-resolution/logging
conventions but the *looping* is the key departure from a single
"exercise everything in one session" run: to avoid one session's context
growing with every issue it processes (the concern that shaped this part of
the design), the script itself loops over issues, giving each its own fresh
`claude -p` session — the same "no state survives between invocations
except what's on GitHub" principle the whole harness already relies on for
cycles.

```
./run-research.sh                       # research every open idea awaiting research
RESEARCH_MODEL=opus ./run-research.sh   # override; defaults to sonnet (not $MODEL)
PROVIDER=ollama MODEL=qwen2.5:32b ./run-research.sh
tail -f logs/research.log
```

Flow:
1. Source `providers.sh`; resolve `RESEARCH_PROVIDER` (defaults to
   `$PROVIDER`) and `RESEARCH_MODEL` (defaults to **`sonnet`**, not `$MODEL`
   — deep feasibility judgment is expected to land with the implementer
   pass and, where parked, Don — the research pass itself is triage-weight,
   so it gets the cheaper default while staying overridable).
2. `park_external_issues` (shared from `providers.sh`).
3. `gh issue list --repo "$TICKET_REPO" --state open --label idea --label
   owner:researcher --json number` → an array of issue numbers.
4. If empty, log and exit (no session spent).
5. For each issue number, in order: one `claude -p` session, prompt naming
   that single issue number and pointing at `RESEARCHER_AGENT.md`, same
   `--mcp-config`/`--strict-mcp-config` MCP wiring the tester/regression
   agent get (dw only, no plugin-dir — the researcher doesn't touch dw
   skills), `RESEARCHER_PERMISSION_FLAGS`, logged to `logs/research.log`
   and `logs/loop.log` with a `[researcher:#N]` prefix.
6. No suite/file commit step — the researcher's only durable output is
   GitHub state, so there's nothing in the repo tree for the driver to
   commit (unlike the tester/regression agent's suite-file edits).

## `providers.sh` changes

- Move `park_external_issues` here from `run-loop.sh` (behavior unchanged),
  called by both drivers.
- New `RESEARCHER_PERMISSION_FLAGS` array (see Access & isolation).
- `runtime_note` gains a `researcher` case.
- `co_author_for` is not needed for this role (no commits it makes itself).

## CLAUDE.md changes

Add a `RESEARCHER_AGENT.md` / `run-research.sh` bullet in the file-overview
section (next to the regression agent's), document `idea` /
`owner:researcher` in the "Ticket protocol" section's invariant list, and
note the third isolation shape in "Permissions" alongside the existing two.

## Out of scope (YAGNI)

- The researcher does not edit `regression-suite-*.md` or propose cases —
  that channel stays with the implementer/tester/regression agent as today.
- No researcher-specific status labels — existing ones cover all three
  dispositions.
- No write/mutating `dw` MCP access — discovery calls only.
- No chunking/`CASES_PER_SESSION`-equivalent — the driver's one-session-per-
  issue loop already bounds context per session; a single issue plus its
  linked pages is not expected to approach a small model's window the way a
  40-50 KB suite file does. Revisit only if evidence says otherwise.
