# Regression fleet: parallel lanes across servers, dispatched by capability

Status: built (2026-10-18), not yet run live. `python3 -m harness.drivers.fleet [--plan] <level|all>`;
progress on the dashboard's `/regression` page. Requirements generated for all four levels
(713 of 723 cases; $12.50 in all).

## Goal

Speed. A regression run splits the suite across every server's lanes, each case once, on
a lane that can run it. It has the servers to itself: no loop runs alongside it.

## Servers: policy in the profile, facts from the server

`targets/dw/profile.toml` holds policy per server. The server reports facts at startup,
and the run refuses when the two disagree.

| | lem | mini-ai | minid (this Mac) |
|---|---|---|---|
| facts (`/api/health`) | 2 × RTX 3090, 24 GB | M5 Pro, 54 GB to MPS | M4 Pro, 18 GB to MPS |
| transport | ssh | ssh | local (no ssh; server on loopback) |
| `lanes` | 2 (one per worker) | 1 | 1 |
| `downloads` | yes (the catch-all) | no | no |
| `max_model_gb` | none | none | 8 (SD 1.5 class) |
| `heavy` | yes | yes | no |
| `deny_models` | none | `MiniMaxAI/MiniMax-H3*` (its cache holds part of H3) | none |
| `speed` (vs lem) | 1.0 | 0.35 | 0.25 |
| held-back cases | none | the five memory cases | none (load does it) |

Facts are read, never declared: `get_health`'s `workers`, and `list_models`'s cache
(repo id and size). `lanes` may not exceed the worker count. Every server is
preflighted (health answers, hostname matches), lem included.

## Cases: requirements in a sidecar

`regression-requirements.json`, keyed by case ID:

    {"cases": {"S-F003": {"workflows": ["templates/text-to-image"],
                          "models": ["stable-diffusion-v1-5/stable-diffusion-v1-5"], "assets": [],
                          "load": "light", "hash": "<sha256 of the case block, whitespace-normalized>"}}}

- `workflows`: what the case runs by name. Each server validates each one once per run
  (`validate_workflow`, free), and its `plan.downloads_required` is that server's own answer
  to "what would this need that you lack?", with each repo's full size and whether the box's
  Hugging Face token may fetch it (`access_blocked`).
- `models`: every model the case loads, for an inline workflow (nothing to validate by name)
  and for the deny and size rules.

- `load`: `none` (no model: validate, list, schema, security probes), `light`, `heavy`
  (a large model, or a small one at a size that needs tens of GB), `exclusive` (the
  measurement needs the box to itself: host-memory and VRAM high-water cases, `-P` timings).
- The suites are not edited. The sidecar decides only where a case runs, never whether
  or what it expects, so it isn't a suite change.
- **Missing or stale (hash differs) → primary only.** lem has every model and may download,
  so incomplete data is always safe, only slower.
- It is produced by an agent pass over the case text (reading templates' models over MCP)
  and committed with the suites. A requirement it gets wrong shows up as a skip at run time
  (below).

## Dispatch

A case may run on a server when:
1. its entry is present and current (else primary only);
2. its load is allowed (`heavy` false refuses `heavy` and `exclusive`);
3. each named workflow validates there, and whatever it lacks is downloadable (not
   `access_blocked`) on a server with `downloads`;
4. no model matches `deny_models`, every listed model is cached (or downloadable), and each
   fits `max_model_gb` by its full size (the largest any server reports);
5. every asset is in that server's library, and no case of the group is held back there.

Groups are placed longest first, each on the eligible lane that would finish it soonest
(assigned work / `speed`). Work is time, not cases: each finished run kept in
`logs/fleet/runs/` records every pass's and fail's `secs` (its `REGRESSION-CASE` line to
the next, or to the session's end) and server, and `harness/durations.py` makes a case's
estimate the median of its last five readings, normalised to the primary by `speed`. An
unmeasured case weighs the median of the measured ones, so with no history the plan is the
count-based one. Steals (which victim has the most time left) and re-queues (the lane with
the least) use the same estimates; batch sizes stay in cases, since a session's setup cost
is per session. `--plan` prints each lane's estimated minutes once any case is measured.

Cases linked by a `cleanup:` or `setup:` line naming another case ID in the same suite (one
holding an output for a later case) form a dependency group, which runs on one lane, in
order. A group's requirement is the union of its members'. Body text doesn't link: "same
probe as S-F005" is a cross-reference, and linking on it chained 142 of complete's 460
cases into one group. The body-only dependencies that exist are written with a fallback
("built on its own if C-F144 already cleaned up"), as chunked runs already need. Largest
groups now: smoke 12, complete 11, model-specific 7, security 7. `exclusive` groups run
with their server's other lanes idle.

**Backstop.** An agent that finds a precondition missing still says `REGRESSION-SKIP`; the
fleet re-queues that case to another eligible lane rather than counting it skipped.

## Lanes

A lane is (server, slot), a thread. Each has its own state files, prompt files and
`.last-session`. A server's first lane works in the level's own workspace (`regression-smoke`),
as a one-server run does, so its workspace fixtures are there; a second lane gets its own
(`regression-smoke-lem-2`), created and seeded at the start with `copy_to_workspace` from the
level's workspace's own assets. Saved workflows and gallery runs aren't copied: a case that
needs one recreates it, as the Fixtures sections already ask. Suite and perf commits happen
once, at the end.

Progress: `logs/fleet/state.json`, rewritten on every change (each case's lane and outcome,
each lane's live case, cost, events), kept in `logs/fleet/runs/<id>.json` when done. The
agent writes `REGRESSION-CASE: <id>` as it starts a case and `REGRESSION-RESULT: <id>
<outcome>` for each at the end (`agents/regression/run-cases.md` step 6).

## Asked of dw, later

`validate_workflow` is most of a "can you run this?" endpoint. What a dispatcher still
lacks is a memory-fit verdict for the device (it warns in prose past the catalog template's
VRAM ceiling), device support as a field, and warning codes. A `plan.runnable` block
(`{ok, reasons: [{code, ...}]}`) would replace `deny_models` and `max_model_gb`. It is new
MCP surface, so it waits for dw's stabilization freeze to lift.

## Not yet

- The first live run (smoke first).
- The perf-reading condition for two lem lanes (`lanes_active`): an `exclusive` case runs
  with its server's other lanes idle, but ordinary `metrics:` readings may still overlap.
- Copying saved workflows into a second lane's workspace, if a case turns out to need one.
