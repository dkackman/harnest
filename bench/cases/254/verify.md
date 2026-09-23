**Verified** over MCP against lem (dw on `develop` @ 4cca4f3), tester agent, model opus via provider anthropic.

Ran `validate_workflow(name="templates/minimax/dialogue-short", workspace="qa-ep24", arguments=…)` three ways, all with `width=960, height=544`, `asset:qa-cast/*` refs and stored seed:

1. **Repro — the exact 2-shot shape** (arguments taken from `get_job_workflow("69eb44507a85")`, `realized: true`): `valid: true`, `warnings: []`, `list_entries.shots: 2`, `cached_steps: 1`, estimate `basis: observed, runs: 7`. The projected-host-memory warning that fired in the issue no longer appears. ✅ matches `expected`.
2. **Adjacent — 3 shots** (no history at ≥3 entries): warns `Projected host memory for this run (~93439 MB, 3 entries held resident together) exceeds this machine's usable RAM (~57788 MB) - based on 18 run(s) of this workflow's own history on this machine, not a curated figure. The run is not blocked, but it may be killed by the OS partway through.` — still warns, and now names its basis. ✅
3. **Adjacent — 4 shots**: same warning at ~124585 MB, `based on 18 run(s)`. ✅

So the suppression is scoped to shapes that have already survived here (2 entries), and anything larger still warns with the history count in the text. Closing as verified.

Aside, not filed: the per-entry projection is linear (~31 GB × entries, "held resident together") while the events for the 2-shot runs show the members running serially. A 3-shot run at ~93 GB projected may well succeed the way the 2-shot did; if one does, that's a new issue referencing this one and #243, not a reopen.