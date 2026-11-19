# Permissions

Moved from `CLAUDE.md`. Sections named "below" in this text now live in sibling files: Running → `running.md`, Tests → `tests.md`, Permissions → `permissions.md`, Ticket protocol → `ticket-protocol.md`, the component list → `components.md`.

No agent runs with `--dangerously-skip-permissions`. A headless `claude -p` session never
prompts — a call that would have prompted is denied and the denial comes back to the agent as a
tool result — so the choice is what gets auto-approved vs. auto-denied, per role:

- Tester and regression agent: `--permission-mode dontAsk` + an explicit `--allowedTools` list
  (`CONSUMER_PERMISSION_FLAGS` in `providers.sh`): `mcp__dw__*`, the dw skills, `gh issue`, file
  tools for the suite files and `qa-bible.md`, and a few read-only shell helpers. No `ssh`, `curl`,
  `python`, or `git` writes (the drivers commit suite edits themselves), and no other `gh`
  subcommand — a bare `gh *` let a consumer read the source through `gh api .../contents` or
  `gh repo clone`. `--disallowedTools` denies `delete_model` and `update_diffusers` outright
  (server-wide, used by no case); the other destructive dw tools are exercised by suite cases
  and stay on the prompts. This is what makes
  consumer-only isolation enforced rather than honor-system. `Write`/`Edit` are allowed only on
  the suite files, `regression-perf/**`, `qa-bible.md` and `/tmp`; the remaining gap is that
  `Read` isn't path-scoped, which the role prompts cover. If a cycle shows a
  denial in `logs/tester.log` for something the role legitimately needs, widen the list there,
  deliberately, rather than reaching for the bypass flag.
- Implementer: `--permission-mode auto`. Its shell surface (`git`, `gh`, `ssh lem`, `pytest`,
  `uv`, …) can't be enumerated without breaking a cycle the first time it needs something new,
  so the auto-mode classifier approves routine work and denies destructive or exfiltrating
  actions. The classifier's picture of the environment (trusted repo, `lem`, what "routine"
  means here) is `agent-settings/implementer.json`, passed via `--settings`; it used to be
  inherited from user settings and described a different checkout.
- Feature lead, design and decompose: `--permission-mode dontAsk` +
  `LEAD_DESIGN_PERMISSION_FLAGS` (`providers.sh`) — read-only against the source
  (`Read`/`Grep`/`Glob`, read-only `git`), read-only `dw` calls, `gh issue`, `WebFetch`,
  `Write` for staging text in /tmp, and one `gh api` PATCH form for the plan comment. A
  third isolation shape: it sees source, like the implementer, but can never change it.
  Its build and close-out sessions run with the implementer's flags.
- Docs reviewer: `--permission-mode dontAsk` + `REVIEWER_PERMISSION_FLAGS` — the lead-design
  shape minus every write: `Read`/`Grep`/`Glob`, read-only `git`, read-only `dw` discovery,
  `gh issue`. Its cwd is the plugin tree, and it runs with `--setting-sources local`, not
  `project,local`: the dw repo's checked-in `.claude/settings.json` allows `pip install`,
  `pytest` and `curl`, which a project source would add to its allowlist.

Guard hooks (roadmap R3): `agent-settings/hooks/guard.py` is a `PreToolUse` hook on `Bash`.
The implementer loads it via `agent-settings/implementer.json`; tester and regression load it
via `guard_settings consumer` (`providers.sh`, which generates the `--settings` JSON for the
consumer, lead, curator and reviewer roles), inside `CONSUMER_PERMISSION_FLAGS`. It refuses at
call time what `audit_issue` otherwise only finds afterwards:
- `completed` closes and `status:verified` from the implementer;
- lifting a `owner:don`/`needs-approval` park;
- pushes to `master`, and force pushes;
- stacking `owner:*` labels;
- a consumer verifying in a session with no `mcp__dw__*` call. A tester handoff session may
  close as `completed` without one, since it applies a harness-side edit with nothing to verify
  (`HARNEST_SESSION_KIND`, set by `run_agent`). It still can't add `status:verified`;
- `status:verified` from the docs reviewer, which closes as `completed` without an MCP call
  and marks it `status:reviewed` instead.

What it does not cover: a command the hook never sees whole. That means a script the agent
writes and then runs, a `bash -c` string (whose obfuscation detectors don't read inside it),
and a line hidden from its lexers by a `#` comment or `$'…'` quoting (harnest#141, the
hidden-script class). The consumer roles are held there by their tool allowlists instead:
`Write`/`Edit` are allow-only on the suite files, `regression-perf/**`, `qa-bible.md` and
`/tmp/**`, so a consumer can write a file under `/tmp`, but its `Bash` allowlist runs no file
it wrote, and `dontAsk` denies the rest. The one file it writes that something reads is a
`/tmp/dw-ui-*.json` spec, data for the fixed web-UI runner (`Bash(node
$HARNEST_ROOT/tools/ui-check/ui-check.mjs /tmp/dw-ui-*.json)`, Task 8b; components.md,
`ui-check`): the runner executes no code from it, and the guard refuses every other `node`,
`npx` or `npm` and any write under `tools/ui-check`.

It also gates the implementer's hand-off. The tree must be clean, `ruff` must pass on the
changed files, the UI's `npm run check`/`lint`/`test` must pass when `ui/` changed (about
15 s; absolute, since CI now holds `develop` to them), and no test may fail that passed on `HARNEST_BASE_COMMIT` (origin/develop
when the session began, exported by `implementer_pass`). The gate is relative because
`develop` isn't always green. The result is stamped per tree in the checkout's `.git`.
`HARNEST_HOOKS` (exported by `providers.sh`) is how the settings files find the script.
The role prompts' cores carry each guard rule as one line under "Enforced by the harness".
`arch_gate` also refuses a hand-off or a push of `develop` whose own commits touch dw's hot zone or worsen a
`scripts/arch_metrics.py` metric (`lib/arch_ratchet.py`, fails closed); only Don's `arch-approved` with a matching `baseline.json` raise waives a rise.

Two deploy paths, and the hand-off must say which one a fix needs (`deploy: server` or `deploy: plugin`). No agent session deploys, on any server (R17): the guard refuses *running* `deploy.sh` (in command position, after `bash`/`sh`/`zsh`/`exec`/`source`/`.`/`env`/`nohup`/`command`/`sudo`, inside a `sh -c`/`bash -c`/`su -c`/`eval` string, anywhere in an ssh remote command, in a `NAME=value` such as `GIT_SSH_COMMAND`, a git alias or `-c` value, or any text piped to a shell or `xargs`) and `scripts/testbed.sh update|start|restart|stop`, and restarting `dw-serve` by another name (`systemctl restart|start|stop dw-serve`, `launchctl kickstart|bootout … dw`, `kill`/`pkill`/`killall` with `dw.serve` on the line, locally or over ssh), for every role, tester included, on every target. Reading, editing, diffing, staging or grepping `deploy.sh` is allowed, and only through `cat`, `head`, `tail`, `wc`, `grep` (not `-r`/`-R`/`--pre`), `git add|diff|log|show|commit|status|blame`, `shellcheck`, Edit/Write, and exactly `bash|sh|zsh -n <path>`, the syntax check. The path must be a plain argument, not an option's value (`-f deploy.sh`, `--opt=…/deploy.sh`; `--` and a `-20` count are not options). Any other command naming it is refused, since it may run it (`sed` `e`, `sort --compress-program`, `rg --pre`, `awk` `system()`). A line that names it is refused outright when any segment writes a file (`>`, `>>`, `&>`, `>|`, `2>`, `<>`; a `>&1` duplication is fine), so an edit is an Edit/Write and never a shell write, or when another segment, past `sudo`/`env`/`nice`/`timeout`/`busybox`/`ssh <host>`, is a shell, an interpreter (`python*`, `node`, `perl`, `ruby`, `php`, `lua`, `osascript`), `xargs`, `parallel`, `source`, `.`, `eval` or `tee` (`runs_deploy` and `deploy_line_runs` in `guard.py`). Only a message's inline text (`git commit -m`, `gh issue|pr --body/--title`, `gh api -f body=`) may name `deploy.sh` in a `gh` command. This is name matching: an agent that copies the script under another name defeats it, which is why R18 proposes an OS-level boundary. The driver deploys `develop` between GPU sessions. Server code → the driver runs
`ssh lem '~/diffusers-workflow/scripts/deploy.sh develop'` (in the dw repo: fetch, ff-only pull,
reinstall if `pyproject.toml` changed, wait for a running job, restart via the `dw-serve`
systemd user unit if installed else its `screen` session, poll health — the one call that
replaced ~40 hand-rolled ssh turns per issue and eleven `kill -9`s of the server), tool schemas
refresh automatically; plugin/skill changes → merge to `develop` and push, no restart (the
tester's plugin tree follows `origin/develop`). `run-loop.sh` also records what lem is running at the start of every cycle
(`deployed_head`, one ssh) and puts it, plus the issue's title/labels/body/latest comments
(`issue_context`, capped), into every per-issue session prompt so neither role spends its first
turns on `gh issue view`. `issue_context` withholds comments by any login other than
`TICKET_OWNER` (a one-line stub instead): the repo is public, `park_external_issues` only vets
who *filed* an issue, and the implementer that reads the prompt runs in auto mode with push
and ssh; every agent posts as `TICKET_OWNER`, so nothing the loop wrote is lost. The role
prompts say the same of comments met via `gh`. `DEPLOYED_HEAD` is refreshed between the implementer and tester
passes (the tester must be told what it is actually verifying against), and
`check_target_on_develop` logs a warning and redeploys `develop` itself (`deploy_target`; `DEPLOY_ON_MISMATCH=0`
to only warn) if the server isn't on `origin/develop` at that point —
the implementer merges every fix into `develop` and the driver deploys `develop` ("Fix" in `agents/implementer/fix.md`, "You never deploy" in the core)
because lem can only be on one commit and a cycle hands off several fixes; on 2026-09-21
three branch-only deploys (then done by sessions) were wiped by a fourth session's `develop` deploy and had to be
merged by hand before the tester ran. Both are driver-side (one `ls-remote`, the same ssh) —
the tester still reaches lem only over MCP.

Bounce escalation: `handoff_count` (labeled events for `status:fixed-pending-verify` on the
issue's timeline since its last `reopened` event, so a reopened issue's earlier hand-offs don't
count; a regression is a new issue and starts at zero) is how many fixes the tester has sent back. At `IMPLEMENTER_ESCALATE_AFTER`
(default 2) the issue's next implementer session runs on `TESTER_MODEL`/`TESTER_PROVIDER`
with a prompt note that the bounce comments are now the spec; at `IMPLEMENTER_PARK_AFTER`
(default 4) the driver parks it `owner:don` + `status:needs-approval` with a comment instead
of launching another session. Two, not one, because a first bounce is usually a spec gap
the bounce comment closes (#265's second round on sonnet cost $0.71 against $4.65 for the
first, and verified); 0 disables either.
