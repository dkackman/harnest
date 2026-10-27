# Ticket protocol (the core of the design)

Moved from `CLAUDE.md`. Sections named "below" in this text now live in sibling files: Running → `running.md`, Tests → `tests.md`, Permissions → `permissions.md`, Ticket protocol → `ticket-protocol.md`, the component list → `components.md`.

Tickets are **GitHub Issues on `dkackman/diffusers-workflow`**, not entries in a file in this
repo. Both agents act on them with the `gh` CLI (`gh issue create` / `edit` / `comment` /
`close` / `list`). The invariants both role prompts and the status-board query depend on:

- **Which server's loop** (harnest#15): `backend:shared|cuda|mps` says what a bug is about
  and `target:lem|mini-ai` is the claim of the loop working it; `lib/classify.jq` holds
  another loop's issues at `wait` (README "Another server").
- `owner` is a label, exactly one of `owner:implementer` / `owner:tester` /
  `owner:don` / `owner:lead` at a time — whoever's turn it is to act
  next. Swap it with `gh issue edit <n> --remove-label owner:X --add-label
  owner:Y`. An agent only touches issues carrying its own owner label and
  never edits another agent's issue beyond the label/comment that hands it
  off. An `idea`-labeled issue goes to `owner:lead`, whose design session
  makes it a feature, hands it to `owner:implementer` as one fix, or closes
  it. `lib/classify.jq` is the authoritative map from labels to the session
  that runs next.
- **A release freeze** (R14): while an open issue labeled `release` exists (owner:don, titled
  with the version), `lib/classify.jq` holds every agent queue at `wait` except issues
  labeled `release-blocker`, and `run-loop.sh` holds the tester's standing task
  (`release_freeze` in `providers.sh`). Closing the release issue lifts it.
  `touch logs/stop-after-cycle` is the other freeze: the loop exits at the next cycle
  boundary. **dw's stabilization freeze** (`docs/stabilization/FREEZE` on its `develop`, read by
  `lib/freeze.py`) stops features and lead builds and has `guard.py` refuse new surface; the hot
  zone and ratchet outlive it, and `unpark_pass` hands back what it parked (roadmap "stage C").
- **Security holes are private** (R14 item 3). A finding where a boundary didn't hold
  goes to a draft GitHub security advisory via `scripts/file-advisory.sh`, never a public
  issue. That covers a gate, a path, a URL, a disclosure, or a destructive call without
  acknowledgement. Only Don and the repo's admins can see a draft. The script dedupes
  by summary, appending "seen again" rather than filing twice. The tester and regression
  agent may run it (`CONSUMER_PERMISSION_FLAGS`), and so may the implementer
  (`$HARNEST_ROOT`), and `run-release.sh review` files its security findings the same
  way. `guard.py` refuses the `security` label on any issue from every agent. A
  security-level case that fails while its boundary held is an ordinary issue. The
  board line and the digest count open drafts. Nothing in the loop works them: Don hands
  each one out.
- **The owner label is the only signal.** A status addressed to Don (`needs-approval`,
  `plan-review`, or `needs-info` on an implementer's or lead's issue) is stale once he
  swaps the owner back. It never decides a queue, and the agent that receives the issue
  clears it. README "Your moves" lists Don's actions.
- Status flow: no status label ("open", ready for the implementer) → (implementer fixes +
  deploys to `lem`) → `status:fixed-pending-verify` → (tester re-runs repro over MCP) → close the
  issue as `completed` with `status:verified` added, or back to no status label / owner back to
  `owner:implementer`. `status:needs-info` is a question bounce. `wontfix` (GitHub's built-in
  label) is the implementer's call, reason in a comment, issue closed as `not planned`; the
  tester may reopen it once with new evidence, and a second `wontfix` is final. `duplicate`
  (GitHub's built-in label) closes an issue as `not planned` in favour of another, named in a
  comment (`duplicate of #NN`). `status:needs-approval` + `owner:don` parks an issue with the
  human — the implementer must use it for engine/syntax changes and anything breaking beyond a
  rename, after writing a proposal; neither agent touches a parked issue. The triage session
  (see below) applies the same label earlier and more cheaply, before any fix is built: when an
  issue's own text suggests the fix would add new engine or validation surface (a new
  task/command, a new `validate_workflow` rule, widening an existing task's argument matrix)
  where a narrow repro-only verify is likely to pass while untested edge cases underneath it
  don't, triage escalates it straight to `owner:don` + `status:needs-approval` with a `triage:
  escalate` comment, no proposal required at that point — for Don to assess and either approve,
  ask for a proposal, or route out of band. It is also where any
  issue filed by a GitHub login other than `TICKET_OWNER` (default `dkackman`) lands: both agents
  run as that login, so their own filings pass, but a third party filing on the public repo must
  not be picked up unattended. `run-loop.sh` (`park_external_issues`) relabels such issues
  `owner:don` + `status:needs-approval` with an explanatory comment before every cycle, and the
  implementer's triage repeats the check; only a human hands one back in. The implementer
  triages every issue for duplicates and fixes already on `develop`/`lem` before reproducing,
  checking both open and closed issues (`gh issue list --state all`) — a closed issue is still
  canonical for duplicate detection. But a closed issue carrying `status:verified` is a prior fix,
  not a standing "already handled" — if the repro still reproduces against current `develop`/`lem`,
  that's a regression, not a duplicate. A regression against a verified issue is a **new** issue
  labeled `regression` that references it (`regression of #NN`); nobody reopens the old one. The
  implementer fixes the new issue and never closes it as `duplicate`/`wontfix` on the strength of
  the old verification alone. (The tester's one reopen of a `wontfix` with new evidence is not a
  regression and stands.)
  Only the tester may close an issue as `completed` (`verified`), and only from a real MCP call.
  The one exception is a fix that changed only text neither the server nor the plugin serves
  (README, non-guide `docs/`): the implementer labels it `docs-review` at hand-off (or the
  tester does on meeting one it can't observe), `lib/classify.jq` routes it to
  `reviewer:docs`, and `run-loop.sh`'s `reviewer_pass` (`agents/reviewer/`, on the tester's
  model, read-only against the plugin tree at `origin/develop`) closes it as `completed` with
  `status:reviewed` — never `status:verified`, which `guard.py` refuses it — or bounces it.
  The tester stays source-blind: that is why this is a separate role, not a wider fence.
  That rule is about the ticket repo: on this repo the curator closes the suite requests it
  applies as `completed`.
- Implementer commits reference the issue number (`fix(mcp): #42 - ...`), works on branches
  merged to `develop`, never `master`.
- Breaking MCP interface changes get the `breaking-change` label plus a comment, so the tester
  adjusts its calls rather than filing the change as a new bug.
- Agents never poll or sleep inside a session; "nothing to do" means exit and let the driver
  re-run them. Because cycles are serialized, server restarts can't collide with tester calls.
- Tickets filed before 2026-09-12 lived in `mcp-feedback.md` / `mcp-feedback-archive.md` in this
  repo; the ones still active then were carried forward as fresh Issues (#69–#79), cited in
  their body as "migrated from T0xx" so old cross-references still resolve. Those files have
  since been removed — GitHub is the sole ticket history, including everything that predates
  the migration.

When editing either role prompt, keep the asymmetry intact: any change that gives the tester
code or box access, or lets the implementer self-verify, defeats the purpose of the setup.
The status board in `run-loop.sh` queries `gh issue list --json number,title,labels`, so keep
the `owner:*` / `status:*` label prefixes if you change the label scheme.
