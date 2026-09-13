# Regression suite — dw MCP server — security level

Checks that the server's boundaries hold against a hostile-but-authorized
MCP consumer: nothing an agent sends through the API should read, write,
delete, fetch, or *execute* anything the server didn't mean to expose. Not
about workspaces — a workspace is a namespace, not a security boundary, and
this is a single-user system — but about escaping the server and its API
altogether. Every case here is run with the server's **default** security
posture (`--trust-workflows` off, no `DW_TRUST_WORKFLOWS`), because that's
the posture whose guarantees actually matter; a case that only holds with a
flag flipped isn't a guarantee. Opt-in only: `./run-regression.sh security`
(or `all`). Sibling suites:
[`regression-suite-smoke.md`](regression-suite-smoke.md),
[`regression-suite-complete.md`](regression-suite-complete.md),
[`regression-suite-model-specific.md`](regression-suite-model-specific.md).

**What belongs here** (vs. the functional suites): a case whose *failure*
means an agent got past a boundary — code ran that shouldn't have, a file
outside the server's own roots was read/written/deleted/enumerated, a
request left the box for a host the workflow chose, or a secret showed up
in a response. A tool merely misbehaving (wrong result, crash, slow) is a
functional case and belongs in `smoke`/`complete`, even if the input was
weird. Cases here are deliberately hostile inputs; they are never destructive
by design — each probe targets something that would be harmless even if the
boundary failed (a read of a stock system file, a write into `/tmp`, a
loopback fetch), never a real payload.

**How to read a result.** Most cases have two ways to fail, and the second
is the subtle one: (1) the hostile input *worked*; (2) the input was
rejected, but the error shows it was rejected *too late* — after an import
was attempted, a file was opened, or a request went out. A
`ModuleNotFoundError`, a `FileNotFoundError` naming the probe path, or an
HTTP status from the probe URL are all failures even though the job didn't
succeed. The `expected:` lines say what a refusal must look like; anything
else is a finding. Never work around a refusal to "see what happens" — the
refusal *is* the pass.

Workspace: `regression-security`. Case IDs use the `SE-` prefix (`SE-F001`,
`SE-P001`, ...) so they never collide with `S-`/`C-`/`M-` IDs — the
regression agent's duplicate-issue search is keyed on the full prefixed ID.
Issues filed from this file carry the `security` label in addition to
`regression`. Full run mechanics (fixtures vs. outputs, cleanup, the final
sweep) live in `agents/REGRESSION_AGENT.md`, not here.

Maintained by the regression agent, run via `run-regression.sh`, and grown
by the implementer/tester too (see "Adding a case" below). Each case is
intent + expected result, not a pinned tool/param name — confirm the exact
call shape against the live tool schema each run, since the server evolves.
Grows over time: new cases get appended to the relevant section, `last
run:` notes accumulate so a baseline drifting over many runs is visible.

## Adding a case

The implementer and the tester both grow these suites, not just the
regression agent. A case belongs here if its failure is a boundary escape
(see "What belongs here" above); otherwise pick the functional suite per
`regression-suite-smoke.md`'s "Where a case belongs". Use the existing case
format (intent + `expected:` + `cleanup:`), the next unused
`SE-Fnnn`/`SE-Pnnn` ID, and a `source:` line naming who added it and why
(e.g. `source: implementer, fix for #42` or `source: tester, found while
running TESTER_TASK.md`). Make the probe harmless even if the boundary is
broken — target `/tmp`, loopback, or a stock system file, never anything
that would damage the box if the check fails. State both failure modes:
what "it worked" looks like *and* what "refused too late" looks like. No
separate approval step. Leave `last run:` for the regression agent to fill
in on its next pass.

## Not covered here

Things a consumer-only agent can't exercise, listed so nobody assumes they
are. These belong in the `diffusers-workflow` repo's own pytest suite (the
implementer's territory), not in a live-server run:

- Auth itself: a wrong/missing bearer token → 401, the refusal to start
  `--mcp` on a non-loopback bind without a token, Origin/Host rejection,
  and the token-less `/outputs`/`/inputs` static routes. The agent's own
  connection is fixed by the driver; it can't vary its token or headers.
- Behavior with `--trust-workflows` **on** (everything in "Code execution
  gate" is expected to pass through in that mode — by design).
- Symlink escapes (planting a symlink inside a workspace needs box access).
- Decoder bombs (a crafted giant-pixel PNG needs a file the agent can't
  author; there is no pixel-count clamp on `get_output_image`/gallery
  thumbnails as of 2026-09-13 — noted here so it isn't forgotten).
- Link-local/RFC1918 SSRF targets other than loopback: a fetch to
  `169.254.169.254` on a LAN with no such host hangs until the 300 s
  request timeout, which would stall the run; loopback (SE-F018) proves
  the same policy gap without the wait.

## Fixtures

Durable contents of `regression-security` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- (none yet)

## Code execution gate (default: untrusted)

The server resolves class/module/constant names from workflow JSON by
import. Untrusted, every dotted name outside the diffusers ecosystem
(`diffusers`, `torch`, `transformers`, `accelerate`, `peft`, `sdnq`, ... —
whatever the live server's error message enumerates) must be refused, and
so must the two from_pretrained arguments that download and run code from
the Hub. A refusal is only a pass if it comes from the trust gate, *before*
any import: the message should say the workflow is untrusted / outside the
ecosystem. `ModuleNotFoundError`, `ImportError`, `AttributeError` on the
probe name, or any trace of the probe having executed, is a fail.

### SE-F001 — server states its security posture
`get_server_info` (or whatever the live schema calls it).
expected: the response says whether auth is required (`auth_required`
true on the regression target — it runs with a token) *and* whether
workflows are trusted, so this suite can confirm it's testing the untrusted
default rather than assuming it. If the trust posture isn't reported, that
is the finding: file it as "server doesn't expose trust posture; security
suite can't verify it's running on defaults", and run the rest of the
suite anyway, noting the assumption in every `last run:`.
cleanup: none (read-only).
source: harness, initial security suite 2026-09-13.
last run:

### SE-F002 — dotted `*_type` outside the ecosystem is refused
`validate_workflow` (then `run_workflow` if validation lets it through)
with an inline workflow whose scheduler or component type is a dotted name
outside the ecosystem — e.g. `scheduler_type: "subprocess.Popen"` or a
component `type: "os.system"` — on an otherwise minimal, valid workflow
(copy the shape of a bundled template, e.g. `templates/text-to-image`).
expected: refused with the trust-gate message ("outside the ecosystem",
"--trust-workflows", or the live equivalent). Fail if validation passes
*and* the job fails only at load with an import/attribute error on the
probe name (it was imported), or if the job runs.
cleanup: none if refused; if a job was enqueued, `cancel_job` and delete
anything it produced.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F003 — `pre_load_modules` outside the ecosystem is refused
Inline workflow with `pre_load_modules: ["subprocess"]` (harmless if
imported — it's already loaded in any Python process — but out of
ecosystem), and a second attempt with a module that does not exist,
`["dw_security_probe_nonexistent"]`.
expected: both refused with the trust-gate message. The nonexistent one is
the diagnostic: if it comes back as `ModuleNotFoundError`, the gate ran
*after* the import attempt (or not at all) — fail.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F004 — `constant:` reference outside the ecosystem is refused
A workflow argument valued `constant:os.environ` (would leak the server's
environment, including any HF token, into the job) and `constant:sys.argv`.
expected: refused with the trust-gate message before any import. Fail if
the job runs, if the error text contains anything that looks like an
environment variable value, or if the refusal is "constant is not
callable/not found" (that means it was resolved first).
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F005 — `trust_remote_code` is refused untrusted
Inline workflow whose pipeline or a component's `from_pretrained_arguments`
sets `trust_remote_code: true` (any small model; it should never get as far
as loading).
expected: refused with the trust-gate message naming `trust_remote_code`.
Fail if the job starts loading the model (a download or a load step in
`get_job_events`) before failing, or runs.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F006 — `custom_pipeline` is refused untrusted
As SE-F005 with `custom_pipeline: "lpw_stable_diffusion"` (a real community
pipeline name — a refusal must not depend on the name being bogus).
expected: refused with the trust-gate message naming `custom_pipeline`;
same fail conditions as SE-F005.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F007 — dotted `config_type`/`dtype` outside the ecosystem is refused
Inline workflow using a quantization/cache config block whose
`config_type` is `"os.path.join"`, and separately a component `dtype` of
`"builtins.eval"`.
expected: both refused with the trust-gate message. Same fail conditions as
SE-F002.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F008 — in-ecosystem dotted names still work (negative control)
Inline workflow with `scheduler_type: "diffusers.EulerDiscreteScheduler"`
(fully dotted, in ecosystem) — `validate_workflow` only, no run.
expected: validation passes (or fails for an unrelated reason clearly not
the trust gate). This proves SE-F002–F007 are refusals from a working
allowlist, not a gate that's stuck refusing everything.
cleanup: none (validation only).
source: harness, initial security suite 2026-09-13.
last run:

### SE-F009 — `remote_text_encoder.url` cannot point off-policy
The `remote_text_encoder` block makes the server POST to a URL the
workflow chooses, with its Hub token attached, and deserialize the reply.
Three probes, `validate_workflow` first and `run_workflow` only if
validation lets it through: (a) `url: "file:///etc/hostname"`; (b)
`url: "http://127.0.0.1:8765/api/server"` (the server itself — a harmless
loopback target that answers 405 to a POST); (c) any `http://` URL to a
host that isn't a known inference endpoint.
expected: refused at validation, either because the URL fails scheme/host
policy or because the feature itself is trust-gated untrusted. Fail — and
file as high severity — if the error reports an HTTP status, a content
type, or "did not return embeddings" from the probe URL: that means the
request went out, carrying the token, and the reply was handed to the
deserializer. Also fail if `file://` is accepted at all.
cleanup: none if refused; otherwise `cancel_job` and delete outputs.
source: harness, initial security suite 2026-09-13.
last run:

## Filesystem containment

Every name a tool takes that becomes a path on the server must resolve
inside the root that tool serves (outputs, assets, prompts, workflows,
workspaces). A traversal or absolute-path probe must come back as a clean
validation error ("invalid name", "not allowed", "outside ...") — never as
`FileNotFoundError`/"no such file" naming the probe path (the path was
tried), and never with content.

### SE-F010 — output names can't traverse
Against this workspace, call each of `get_output_image`, `get_output_text`,
`get_gallery_metadata`, `delete_output`, `keep_output` with names
`../../../../etc/hostname`, `/etc/hostname`, `..%2f..%2fetc%2fhostname`,
`~/.bashrc`, and `outputs/../../etc/hostname`.
expected: every call is a clean validation error; no bytes/text returned;
no delete reported as succeeding. Fail on any content, on a "file not
found" that echoes a normalized version of the probe, or on `keep_output`
creating an asset with a traversed name (check `list_assets` after).
cleanup: none; if `keep_output` did create something, delete it and name it
in the issue.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F011 — workflow and prompt names can't traverse or go absolute
`get_workflow`, `validate_workflow` (by name), `delete_workflow`,
`save_workflow`, `get_prompt`, `save_prompt`, `delete_prompt` with names
`../../../etc/hostname`, `/etc/hostname`, and (for `get_workflow`) the
absolute path of a real file outside every workflow source — use the
server's own `directories.workflows` path from `get_server_info` and go one
level up to its parent, e.g. `<parent>/pyproject.toml`.
expected: all clean validation errors; `save_*` creates nothing (check
`list_workflows`/`list_prompts` after); `get_workflow` on the
outside-source absolute path is refused as outside every source, not
served. Fail on any content or any created file.
cleanup: delete anything a `save_*` created, and name it in the issue.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F012 — asset names can't traverse
Generate one small output (cheapest image template, minimal steps), then
`keep_output` it with `asset_name` values `../escaped.png`,
`/tmp/escaped.png`, `~/escaped.png`, and `a/b/c/d/e/escaped.png` (deeper
than the documented folder limit). Then `delete_asset` with `../x.png` and
`/etc/hostname`.
expected: every call is a clean validation error; `list_assets` afterwards
shows nothing new. Fail if any asset appears, or a delete reports success.
cleanup: delete the generated output; delete any stray asset and name it
in the issue.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F013 — workspace names can't traverse, go absolute, or be hidden
`create_workspace` with `../escaped`, `/tmp/escaped`, `.hidden`,
`regression-security/../escaped`, and an empty string. `use_workspace` with
`../default` and `/`.
expected: every call refused cleanly; `list_workspaces` unchanged; the
session's current workspace unchanged. Fail if any workspace is created
(and if so, do **not** `delete_workspace` it — it may be pointing outside
the workspace root; name it in the issue and leave it).
cleanup: none.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F014 — media arguments can't name arbitrary server files
Inline image-to-image (or any workflow with an `image`/`audio` input) whose
input is a raw absolute path on the server rather than an `asset:`/
`output:` reference: (a) a path that very likely exists on a Linux box,
with an allowed extension, outside every dw root — try
`/usr/share/pixmaps/debian-logo.png` and
`/usr/share/icons/hicolor/48x48/apps/python3.png` (the agent can't list
the server's disk, so try both); (b) a path that certainly does not exist:
`/nonexistent-dw-probe/x.png`.
expected: (a) and (b) refused *identically*, as outside the allowed
roots — the refusal must not depend on whether the file exists. Fail if (a)
runs (the file was read) or if (b) comes back as "file not found" while (a)
proceeds further (existence was checked, i.e. the path was accepted). The
same applies to a `from_file` argument.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F015 — `gather_images`/`gather_videos` glob can't leave the workspace
Inline task-only workflow (no model) whose `gather_images` step has
`glob: "/usr/share/pixmaps/*.png"` — bounded, cheap, and outside every dw
root; then `glob: "../../**/*.png"`.
expected: both refused at validation as outside the allowed roots. Fail if
the job runs and its events/logs report "Found N images" for N > 0, or if
it runs at all — an empty glob result is still an accepted glob. Never use
an unbounded pattern like `/**/*.png` here; it would walk the whole disk.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F016 — `download_output` can't write outside the server's roots
This tool "downloads to local disk". When the MCP server is mounted inside
`dw.serve` (as it is on the regression target), *local* means the server's
own filesystem. Generate one small output, then `download_output` it with
`destination` `/tmp/dw-se-f016-probe.png`, `~/dw-se-f016-probe.png`, and
`/tmp/../tmp/dw-se-f016-probe2.png`.
expected: refused — either the tool declines an absolute/home destination
over HTTP transport, or it confines the destination to the workspace. Fail
if any call reports a file written (the tool returns the path it wrote):
that's an arbitrary-location write on the box by name. These probes land in
`/tmp` and are harmless, but the agent cannot remove them — say so in the
issue.
cleanup: delete the generated output.
source: harness, initial security suite 2026-09-13.
last run:

## Network egress

The server fetches media from URLs a workflow names. Scheme policy must
block anything that isn't `http`/`https`, and host policy must stop the
server being used as a proxy into its own loopback/LAN.

### SE-F017 — non-http schemes are refused
Inline workflow with an `image` (and separately `from_file`) input of
`file:///etc/hostname`, `ftp://127.0.0.1/x.png`, and
`data:image/png;base64,iVBORw0KGgo=`.
expected: all refused at validation as a disallowed scheme (or, for the
`data:` URL, as not a path/URL at all). Fail if any runs or if the error
indicates the target was opened/fetched.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F018 — loopback URLs are refused (SSRF)
Inline workflow with an `image` input of `http://127.0.0.1:8765/api/server`
and `http://localhost:8765/api/server` — the server itself, so the probe is
harmless and answers instantly.
expected: refused at validation by host policy (loopback / private ranges
not allowed as media sources). Fail if the error is a decode error
("cannot identify image file", "not an image", a JSON body in the message)
or an HTTP status from the probe URL — that means the server fetched from
its own loopback on the workflow's behalf. A pass here is what lets the
`169.254.169.254` case stay in "Not covered here".
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F019 — model identifiers are Hub repo ids, not paths or URLs
`download_model` (with `acknowledged_cost` true — the probe must reach the
validator, and an invalid id never downloads) with `repo_id` values
`../../etc`, `/etc/passwd`, `http://127.0.0.1:8765/`, and
`org/name/../../x`. Then the same shapes as `model_name`/`repo_id` inside
an inline workflow, via `validate_workflow`.
expected: every one refused as an invalid repo id, with no download
started (`list_downloads` shows nothing new). Fail if a download entry
appears, or if a workflow validation accepts a path-shaped model id.
cleanup: `cancel_download` anything that appeared and name it in the issue.
source: harness, initial security suite 2026-09-13.
last run:

## Secrets and disclosure

### SE-F020 — no secret ever appears in a response
`get_server_info`, `get_health`, `get_memory`, `get_diffusers_state`, and
the `get_job` / `get_job_events` of a deliberately failed job (SE-F005's
refusal is fine to reuse, or a job with a bogus model name).
expected: no response contains a bearer token, an HF token (`hf_` followed
by ≥20 alphanumerics), an `Authorization` header value, or an environment
dump. `auth_required` may be reported as a boolean; the token value never
is. Tracebacks in a failed job's events may contain server file paths —
note them in `last run:` but they are not a failure on a single-user box.
cleanup: delete the failed job's outputs if any.
source: harness, initial security suite 2026-09-13.
last run:

## Destructive scope and limits

Deletes must stay inside what the caller owns, and documented caps must be
enforced *before* work is enqueued — a cap that only bites after the fan-out
happened is a flood, not a limit.

### SE-F021 — the default workspace can't be deleted, nor a read-only asset
`delete_workspace("default", acknowledged_cost=true)`; `delete_workspace`
with a name that doesn't exist; `delete_asset` on a shared/bundled asset
(pick one from `list_assets` that isn't in this workspace's own library —
an example/common asset); `delete_workflow("templates/text-to-image")`.
expected: every call refused (the default workspace and read-only sources
answer with a permission-style error, the nonexistent name with not-found);
`list_workspaces`, `list_assets`, `list_workflows` unchanged afterwards.
Fail on any successful delete. Never call `delete_workspace` on any
regression or `qa-` workspace here.
cleanup: none.
source: harness, initial security suite 2026-09-13.
last run:

### SE-F022 — documented input caps refuse at validation, not after
(a) `validate_workflow` with a `for_each` of one more entry than the
documented maximum (check `get_schema`/the error text for the number; 32
as of 2026-09-13), using the cheapest workflow shape; (b) a variable whose
value is a 25,000-character string; (c) a `run_workflow` of (a) if
validation let it through.
expected: (a) and (b) refused at validation naming the cap; (c) never
reached. Fail if (a) validates and `run_workflow` enqueues per-entry work
before failing — check `list_jobs` for a burst — or if (b) is accepted.
cleanup: `cancel_job` anything enqueued; delete outputs.
source: harness, initial security suite 2026-09-13.
last run:

## Performance

Security refusals should be cheap: a gate that only fires after a model
load has already spent the resources it was supposed to protect.

### SE-P001 — hostile inputs are refused before any load
Time `validate_workflow` for the SE-F002 probe (dotted `*_type`) and
`run_workflow` for the SE-F005 probe (`trust_remote_code`), measured from
call to the refusal being visible (`get_job` terminal, if a job was even
created).
baseline: TBD — first run. Expected order: under 2 s each; a refusal that
takes as long as a model load means the gate is downstream of the load.
cleanup: as the referenced cases.
source: harness, initial security suite 2026-09-13.
last run:
