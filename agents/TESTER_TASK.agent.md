# Tester standing task — test vehicle, not a deliverable

Your ongoing job between verifications is to exercise the MCP the way a real
consumer would, so that bugs and friction surface in use rather than from
reading schemas. Nothing you produce here ships anywhere. Treat it as a test
vehicle: correctness of the *process* matters, quality of the *output* does
not — but keep what you make, because it's interesting to look at.

## Workspace rules

- Do all work in workspaces whose names start with `qa-` (e.g. `qa-ep1`,
  `qa-scratch`). Create them with `create_workspace`; one per episode is fine.
- Never write into the default workspace or any workspace not prefixed `qa-`.
  If a tool gives you no way to target a workspace, that is a ticket, and
  you stop that step rather than polluting the default.
- Name the workspace in every ticket's `repro:` so the implementer can look.

## The exercise

Produce a short series, about one episode per task session, using the
templates the MCP offers (`dialogue-short`, `music-video`,
`assemble-and-score`, ...). A recurring two-character cast is the point —
it's what drives reuse across episodes, and reuse (of cast, assets and
outputs between jobs) is where the interesting bugs live. Keep the episodes
tiny: two to four shots, short lines.

Each task session (the driver runs one every few cycles — `TESTER_TASK_EVERY`,
default every fourth — separate from the per-issue verify sessions):

1. Pick up where the last episode left off. `qa-bible.md` in your working
   directory is your memory across cycles — see "The bible" below for what
   goes in it and how to read it.
2. Advance the series by one concrete step: a new episode, or re-running an
   old one with a recently fixed tool to confirm the fix holds in context.
3. Exercise adjacent tools while you're there: probe, slice, resample, mix,
   pair. Chain them. Chains are where parameters get dropped.
4. File a ticket for any significant issue encountered during the session,
  including bugs, missing documentation, or workarounds. A workaround you
  had to invent is a bug report. File it there and then — nothing survives
  this session but what you filed, so a ticket held back to the end of the
  task is a ticket the budget cut-off eats.

## The bible

`qa-bible.md` holds the state a fresh session needs to continue the series,
and nothing else. It is a snapshot, not a journal: what happened in a cycle
is already on the GitHub Issues it produced, so it isn't repeated here. Its
fixed sections, in order:

- **Cast** — the two characters, their voice strings, reference images.
- **Shared assets** — the `common/assets` fixtures and what each is for.
- **Workspaces** — one line per `qa-*` workspace: what it holds, whether
  it's still needed.
- **Episodes** — one line per episode: number, title, workspace, what was
  produced, what it exercised.
- **House rules** — the *current* rules for working the MCP well, each a
  short bullet. When a rule changes (a fix lands, a workaround becomes
  unnecessary), edit or delete the old bullet — never add a "cycle N"
  subsection that contradicts an earlier one and leaves both standing.
- **Next** — what the next cycle should do, replaced every cycle, not
  appended to.

Read it in full at the start of the standing task — that is what it is
for, so keep it readable in full: under about 12 KB. If a cycle's edits
push it past that, the fix is to condense (merge rules, trim episode lines
to their essentials, drop a workspace that's been deleted), not to move the
overflow somewhere else. Per-cycle narrative — what you ran, what you
verified, the story of a failed attempt — does not go in; the issue you
filed or commented on carries it.

## Guardrails

- Don't spend a cycle polishing output. If an episode "works", move on.
- Don't repeat a step that already produced a ticket until that ticket comes
  back `fixed-pending-verify`.
- Budget: aim for one or two workflow runs per cycle. This is exploration,
  not production.
- Everything in `TESTER.agent.md` still applies: no source, no SSH, MCP only.
