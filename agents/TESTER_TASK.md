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
  If a tool gives you no way to target a workspace, that is a ticket (see
  T012), and you stop that step rather than polluting the default.
- Name the workspace in every ticket's `repro:` so the implementer can look.

## The exercise

Produce a short series, one episode per cycle or so, using the templates the
MCP offers (`dialogue-short`, `music-video`, `assemble-and-score`, ...). A
recurring two-character cast is the point — it's what drives reuse across
episodes, and reuse is where the interesting bugs live (T005, T007, T010,
T011, T013). Keep the episodes tiny: two to four shots, short lines.

Each cycle, after verification work:

1. Pick up where the last episode left off. Keep a running `qa-bible.md` in
   your working directory with the cast, voice strings, workspace names, and
   what you produced per episode — this is your memory across cycles.
2. Advance the series by one concrete step: a new episode, or re-running an
   old one with a recently fixed tool to confirm the fix holds in context.
3. Exercise adjacent tools while you're there: probe, slice, resample, mix,
   pair. Chain them. Chains are where parameters get dropped (T009).
4. File a ticket the moment something is wrong, missing, undocumented, or
   just annoying enough that you worked around it. A workaround you had to
   invent is a bug report.

## Guardrails

- Don't spend a cycle polishing output. If an episode "works", move on.
- Don't repeat a step that already produced a ticket until that ticket comes
  back `fixed-pending-verify`.
- Budget: aim for one or two workflow runs per cycle. This is exploration,
  not production.
- Everything in `TESTER_AGENT.md` still applies: no source, no SSH, MCP only.
