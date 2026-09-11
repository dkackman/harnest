# diffusers-workflow MCP — Feedback Log

Rules for both agents:
- Never delete or rewrite another agent's entries — only append new entries or edit the `status` line of an entry you own the next step of.
- Each entry gets a unique ID: `T001`, `T002`, ... increment from the last one in this file.
- `owner` = whose turn it is to act next: `implementer` or `tester`.
- Do not start new work if there is an open ticket with `owner: tester` and you are the implementer, or vice versa — that ticket isn't yours yet.

---

## T000 (template — copy this block for new tickets)

- **status:** open | fixed-pending-verify | verified | wontfix | needs-info
- **owner:** implementer | tester
- **reported:** <ISO timestamp>
- **title:** short one-line summary
- **tool/endpoint:** which MCP tool or method this concerns
- **repro:** exact call made (tool name + params, or command run)
- **expected:**
- **actual:**
- **notes:** (implementer fills in on fix: what changed, commit/deploy ref)
- **verify-notes:** (tester fills in on re-test)
