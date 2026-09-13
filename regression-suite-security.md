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
  the same policy gap without the wait. (2026-09-13 earlier: SE-F018 failed —
  loopback *was* fetched — so for one run this exclusion rested on nothing but
  the stall. **2026-09-13 later: #115 fixed and verified, SE-F018 passes, and
  the refusal message names link-local explicitly alongside loopback and
  private ranges. The original reasoning is restored** — this stays excluded
  because the probe would stall the run, and the boundary is again believed to
  hold on SE-F018's evidence.)
- A 25,000-character variable value (SE-F022 probe (b)) as a single literal:
  the agent cannot emit one inside a tool call without blowing its output
  budget. The schema has no `maxLength` on argument values at any level, so
  the question is answered statically instead; see SE-F022.

## Fixtures

Durable contents of `regression-security` that persist across runs. Add a
line when a case starts relying on one; remove the line (and the fixture)
when nothing uses it anymore.

- (none yet)

Repro artifacts currently held in `regression-security` for open issues (not
fixtures — delete when the issue closes):

- (none — the six held for #114 and #116 were deleted 2026-09-13 when those
  issues were verified and closed. `list_gallery(workspace="regression-security")`
  should report `total: 0`.)

Still on `lem` outside every workspace, from the 2026-09-13 SE-F016 run, and
not removable by a consumer-only agent — asked for in #113:
`/tmp/dw-se-f016-probe.jpg`, `/home/don/dw-se-f016-probe.jpg`.

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

### SE-F001 — server states its security posture — **RUN THIS FIRST**
This is the precondition for the whole file, not one case among many. Every
other case here is defined to run on the default untrusted posture, and every
refusal they check for names `--trust-workflows` as the way to turn it off. A
pass on a trusted server therefore means nothing.
`get_server_info`.
expected: the response carries `auth_required` (true on the regression target —
it runs with a token) *and* `trust_workflows`. **If `trust_workflows` is
`true`, stop: do not run the rest of this file and do not report passes.** If
the field is absent, that is the finding — file it as "server doesn't expose
trust posture; security suite can't verify it's running on defaults", run the
rest anyway, and note the assumption in every `last run:`.
Reporting the field is not itself a disclosure: the refusal messages already
name the flag.
cleanup: none (read-only).
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 FAIL (opus/anthropic, v0.4.0-beta.3) — `auth_required:
true` is reported; there is no trust-posture field on `get_server_info` or
`get_health`. Filed #120. The posture was confirmed *indirectly* and firmly
this run: SE-F002–F007 all returned the explicit "…outside the ecosystem …
Pass --trust-workflows" message, which only appears untrusted. So the
2026-09-13 results are known to be on defaults, not assumed.

2026-09-13 later (opus/anthropic, v0.4.0-beta.3) **PASS — #120 fixed, closed.**
`get_server_info()` → `"auth_required": true, "trust_workflows": false`. The
field's meaning is in the tool description too. Promoted to the file's
precondition, per the fix's own proposal — from here on the suite reads the
posture rather than inferring it, which is what lets a later run tell a fix
from a posture change.

### SE-F002 — dotted `*_type` outside the ecosystem is refused
`validate_workflow` (then `run_workflow` if validation lets it through)
with an inline workflow whose scheduler or component type is a dotted name
outside the ecosystem — on an otherwise minimal, valid workflow (copy the
shape of a bundled template, e.g. `templates/text-to-image`). The two
places these live, confirmed against the live schema 2026-09-13:
`steps[].pipeline.configuration.component_type` (e.g. `"os.system"`) and
`steps[].pipeline.scheduler.configuration.scheduler_type` (e.g.
`"subprocess.Popen"`). Note `scheduler_type` is *not* a member of
`pipeline.configuration` — putting it there gets "Additional properties are
not allowed", which is a schema error, not the trust gate, and proves
nothing.
Expect `validate_workflow` to return `valid: true` for all of these —
dotted names are resolved at load, not at validation — so the run is the
real test, not an escalation.
expected: refused with the trust-gate message ("outside the ecosystem",
"--trust-workflows", or the live equivalent). Fail if validation passes
*and* the job fails only at load with an import/attribute error on the
probe name (it was imported), or if the job runs.
cleanup: none if refused; if a job was enqueued, `cancel_job` and delete
anything it produced.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `component_type: "os.system"`
→ job b8a640f53f84 failed in 1.0s: "Refusing to load a dotted type
reference 'os.system': it imports the 'os' module, which is outside the
ecosystem (diffusers, torch, torchvision, transformers, accelerate, peft,
sdnq, torchao, optimum, gguf, bitsandbytes, dw)…". `scheduler_type:
"subprocess.Popen"` → job f63276fdc798, same message, 1.0s. No import
attempted, no outputs.

### SE-F003 — `pre_load_modules` outside the ecosystem is refused
Inline workflow with `pre_load_modules: ["subprocess"]` (harmless if
imported — it's already loaded in any Python process — but out of
ecosystem), and a second attempt with a module that does not exist,
`["dw_security_probe_nonexistent"]`.
expected: both refused with the trust-gate message. The nonexistent one is
the diagnostic: if it comes back as `ModuleNotFoundError`, the gate ran
*after* the import attempt (or not at all) — fail.
`pre_load_modules` sits at `steps[].pipeline.configuration.pre_load_modules`.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `["subprocess"]` → job
b3d710114a7d, 1.0s, trust-gate message. `["dw_security_probe_nonexistent"]`
→ job f760da6fb822, 3.0s, *same* trust-gate message naming the module — not
a `ModuleNotFoundError`. The gate fires before the import, which is the
whole point of this case.

### SE-F004 — `constant:` reference outside the ecosystem is refused
A workflow argument valued `constant:os.environ` (would leak the server's
environment, including any HF token, into the job) and `constant:sys.argv`.
expected: refused with the trust-gate message before any import. Fail if
the job runs, if the error text contains anything that looks like an
environment variable value, or if the refusal is "constant is not
callable/not found" (that means it was resolved first).
A `constant:` goes in a pipeline `arguments` entry; `cross_attention_kwargs`
is a convenient carrier on SD1.5.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `constant:os.environ` → job
8ad58a4dd213, 1.0s: "Refusing to load a constant: reference 'os.environ'…
outside the ecosystem". `constant:sys.argv` → job 48ae8f0c0b68, same.
No environment values appeared in either error.

### SE-F005 — `trust_remote_code` is refused untrusted
Inline workflow whose pipeline or a component's `from_pretrained_arguments`
sets `trust_remote_code: true` (any small model; it should never get as far
as loading).
expected: refused with the trust-gate message naming `trust_remote_code`.
Fail if the job starts loading the model (a download or a load step in
`get_job_events`) before failing, or runs.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). Job 0d32be00092f, 0.95s:
"Refusing to load pipeline: its from_pretrained_arguments set
'trust_remote_code', which downloads and executes Python from the model
repository." No load phase reached.

### SE-F006 — `custom_pipeline` is refused untrusted
As SE-F005 with `custom_pipeline: "lpw_stable_diffusion"` (a real community
pipeline name — a refusal must not depend on the name being bogus).
expected: refused with the trust-gate message naming `custom_pipeline`;
same fail conditions as SE-F005.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). Job b49e0ce34cab, 0.95s:
"Refusing to load pipeline: its from_pretrained_arguments set
'custom_pipeline', which downloads and executes Python from the model
repository." Refused on the argument, not on the name being unknown.

### SE-F007 — dotted `config_type`/`dtype` outside the ecosystem is refused
Inline workflow using a quantization/cache config block whose
`config_type` is `"os.path.join"`, and separately a component `dtype` of
`"builtins.eval"`.
expected: both refused with the trust-gate message. Same fail conditions as
SE-F002.
`config_type` lives at `steps[].pipeline.components[].quantization_config.
configuration.config_type`; for the dtype probe, `torch_dtype:
"builtins.eval"` in `from_pretrained_arguments` is the simplest carrier.
cleanup: none if refused; otherwise as SE-F002.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `config_type: "os.path.join"`
→ job d086374db2d7, 1.0s, trust-gate message. `torch_dtype:
"builtins.eval"` → job e2eae4e76af9, 1.0s, "Refusing to load a dotted type
reference 'builtins.eval'…".

### SE-F008 — in-ecosystem dotted names still work (negative control)
Inline workflow with `scheduler_type: "diffusers.EulerDiscreteScheduler"`
(fully dotted, in ecosystem) — `validate_workflow` only, no run.
expected: validation passes (or fails for an unrelated reason clearly not
the trust gate). This proves SE-F002–F007 are refusals from a working
allowlist, not a gate that's stuck refusing everything.
cleanup: none (validation only).
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `validate_workflow` with
`scheduler_type: "diffusers.EulerDiscreteScheduler"` → `valid: true`.
Caveat worth remembering: validation returns `valid: true` for the *hostile*
dotted names too (SE-F002), so this control only proves the in-ecosystem
name isn't rejected — the allowlist itself is demonstrated by F002–F007
refusing at run time.

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
Probe (c) as written ("any `http://` URL to a host that isn't a known
inference endpoint") is **not safe to run against a real external host**
while this is broken: the request carries the server's HuggingFace token,
so an off-box probe exfiltrates a live credential to a third party. Use a
loopback discard-port URL (`http://127.0.0.1:9/encode`) instead — (b)
already establishes that the request leaves the process. Restore the
external form only once the gate exists and (b) passes.
The block lives at `steps[].pipeline.remote_text_encoder.url` and its only
property is `url` (no scheme/format constraint in the schema).
cleanup: none if refused; otherwise `cancel_job` and delete outputs.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 **FAIL — high severity. Filed #112.** (opus/anthropic)
All three validate `valid: true`. (a) `file:///etc/hostname` → job
8afbe15c0231: "No connection adapters were found for
'file:///etc/hostname'" — `requests`' own error, i.e. the URL reached the
HTTP client with no scheme policy; nothing but the missing `file://`
adapter stopped it. (b) `http://127.0.0.1:8765/api/server` → job
b60fbdedde8b: "The remote text encoder at … did not return embeddings
(HTTP 401, application/json)" — an HTTP status and content type from the
probe URL, so the POST went out. `get_job_events` shows the full pipeline
load completed (phase `loading` at 0.7s, `iteration_start` 2.2s) *before*
the request, so it is also refused far too late. (c) deliberately not run,
per the note above.

2026-09-13 later (opus/anthropic) **PASS — #112 fixed, closed.** All refused at
`validate_workflow`, free, before any load. (a) `file:///etc/hostname` →
`valid: false` at `steps[0].pipeline.remote_text_encoder.url`, "its scheme is
'file', and an untrusted workflow may only reach an https endpoint - the
request carries this machine's HuggingFace token". (b)
`http://127.0.0.1:8765/api/server` → refused on the same scheme rule, so it
never reaches the host rule. (c) `https://127.0.0.1:8765/encode` → refused on
the host rule: "127.0.0.1 resolves to 127.0.0.1, an address inside this
deployment (loopback, link-local or private)".
Two probes added to this case from here on, both cheap:
- **hostname, not literal** — `https://localhost:8765/encode` → refused,
  "localhost resolves to 127.0.0.1". This is the one that proves the check is
  on the *resolved* address; a rule that only pattern-matched `127.0.0.1`
  would pass every other case in this list and fail here.
- **control** — `https://huggingface.co/encode` → `valid: true`, plan
  returned. Without this the case cannot tell a policy from the feature having
  been disabled outright.
The credential-scoping half of the fix (token attached only for
`huggingface.co` / `huggingface.cloud` / `hf.space`) is **not observable from
a consumer** and is deliberately not probed — observing it is exactly the
exfiltration this case exists to prevent. It belongs in the dw repo's pytest
suite. The original external-host form of probe (c) stays retired permanently.
A shape note for whoever runs this next: `remote_text_encoder` sits on a
`pipeline` object, which requires `configuration` (with `component_type`),
`from_pretrained_arguments` and `arguments` — a draft missing those fails
schema validation before the URL is ever looked at, which reads like a pass
and is not one. Confirm the error path is
`steps[0].pipeline.remote_text_encoder.url`.

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
last run: 2026-09-13 PASS (opus/anthropic). No content returned, nothing
deleted, no asset created (`list_assets` unchanged). Two refusal styles,
both acceptable: `get_output_image`/`get_output_text` answer a bare "Not
Found" (no path echoed) for every probe; `get_gallery_metadata`,
`delete_output` and `keep_output` give explicit containment errors — "Path
contains dangerous pattern matching \.\.", "Path outside allowed directory:
/etc/hostname", "Path contains dangerous pattern matching ~[\\/]". Worth
noting the first pair discloses less but also proves less; if a future run
wants certainty there, compare against a name that *does* exist.

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
**For the `save_*` probes, do not use `../../../etc/hostname`** — if
containment fails that clobbers the box's hostname file, which breaks this
suite's own rule that a probe stay harmless when the boundary does not
hold. Use `../../../../tmp/dw-se-f011-probe` and `/tmp/dw-se-f011-abs`
instead. The read-only probes (`get_*`, `delete_*`) can keep the `/etc`
targets: they create nothing.
cleanup: delete anything a `save_*` created, and name it in the issue.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `get_workflow` on
`../../../etc/hostname`, `/etc/hostname` and
`/home/don/diffusers-workspace/pyproject.toml` → "Unknown workflow: <name>"
each time, no content. `save_workflow` to both `/tmp` targets → "Unknown
workflow", nothing written. `get_prompt`/`save_prompt`/`delete_prompt` →
"Invalid prompt name: … a prompt is named by its file under the prompt
directory, at most one folder deep". `list_workflows` afterwards shows only
the read-only `templates/*` examples; no workspace workflows exist.

### SE-F012 — asset names can't traverse
Generate one small output (cheapest image template, minimal steps), then
`keep_output` it with `asset_name` values `../escaped.png`,
`/tmp/escaped.png`, `~/escaped.png`, and `a/b/c/d/e/escaped.png` (deeper
than the documented folder limit). Then `delete_asset` with `../x.png` and
`/etc/hostname`.
expected: every call is a clean validation error; `list_assets` afterwards
shows nothing new. Fail if any asset appears, or a delete reports success.
**The probe extension must match the generated output's extension.** The
kind check runs before the name check, so `../escaped.png` against a `.jpg`
output is rejected with "asset_name … does not match the kept file's kind
(.jpg)" — which says nothing about containment and silently passes the case
for the wrong reason. Generate a `.jpg` and probe with `.jpg` names (or
match whatever the cheapest template emits).
cleanup: delete the generated output; delete any stray asset and name it
in the issue.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic), after re-running with matching
extensions — the first attempt with `.png` names hit the kind check and was
inconclusive. With `.jpg`: `../escaped.jpg`, `/tmp/escaped.jpg`,
`~/escaped.jpg` and `a/b/c/d/e/escaped.jpg` all → "Invalid asset name: … an
asset is named by its file under the asset directory, with its extension
and at most four folders deep". `delete_asset` on `../x.png` and
`/etc/hostname` → same. `list_assets` unchanged (only `origin: common`
entries, which belong to the tester).

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
last run: 2026-09-13 PASS (opus/anthropic). `../escaped`, `/tmp/escaped`,
`.hidden` and `regression-security/../escaped` → "Invalid workspace name: …
a workspace is one folder under the workspace root, named with letters,
numbers, dot, dash or underscore"; empty string → "Workspace name cannot be
empty". `use_workspace` with `../default` and `/` → "No workspace named
'…'". `list_workspaces` unchanged; session still on `regression-security`.

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
last run: 2026-09-13 **FAIL. Filed #114.** (opus/anthropic) Probes used
`StableDiffusionImg2ImgPipeline` with an absolute `image` argument; both
validate `valid: true`. (b) `/nonexistent-dw-probe/x.png` → job
2ca7c60dc968: "Path does not exist: /nonexistent-dw-probe/x.png" — the path
was accepted and only `stat` stopped it. (a)
`/usr/share/pixmaps/debian-logo.png` → job f919f8592d50 **succeeded**; the
output is 48×48, taking its dimensions from the source file, so the file
outside every dw root was opened and decoded. (a) and (b) are distinguished
purely by existence, which is the documented fail condition. Repro artifact
`se-f014a/20260913-180107-93dc1e80/se_f014a-0.0.jpg` kept for #114.
`from_file` not probed separately this run.

2026-09-13 later (opus/anthropic) **PASS — #114 fixed, closed.** Repro artifact
deleted. (a) and (b) are now refused **identically** at `validate_workflow`,
messages differing only in the path: "Refusing to read 'image' at '<path>': it
resolves outside every directory this workflow may read (…5 roots listed…).
Put the file in the asset library and name it with an 'asset:' reference".
Existence-independent, so no oracle and no read.
Two additions to this case:
- **Probe a task argument as well as a pipeline one.** `get_image_size` (an
  image processor — loads no model, runs in ~3 s, costs nothing) with the same
  absolute path → identical refusal at `steps[0].task.arguments.image`. This
  is how the case checks the policy sits in the loader rather than on the
  pipeline path, and it is far cheaper than the img2img form, which wants a
  12 GB `stabilityai/sd-turbo` download.
- **Probe the relative spelling too**, and score it separately:
  `image: "../../../../../usr/share/pixmaps/debian-logo.png"`. Containment
  holds — 2026-09-13 job `70f3f2ea57bc` failed at 3.0 s with
  `PathTraversalError`, nothing read — but `validate_workflow` returns
  `valid: true` for it, where the absolute form and `gather_images`' glob
  (SE-F015) both refuse at validation. Filed as **#124**, low severity, open.
  Until it lands, `valid: true` on the relative form is expected; a *run* that
  succeeds is a fail and is the real escape.
Noted, not filed: the refusal message enumerates five absolute server paths.
Judged acceptable — a refusal a caller can act on has to say where it may
read, and `get_server_info().directories` already reports four of them.

### SE-F015 — `gather_images`/`gather_videos` glob can't leave the workspace
Inline task-only workflow (no model) whose `gather_images` step has
`glob: "/usr/share/pixmaps/*.png"` — bounded, cheap, and outside every dw
root; then `glob: "../../**/*.png"`.
expected: both refused at validation as outside the allowed roots. Fail if
the job runs and its events/logs report "Found N images" for N > 0, or if
it runs at all — an empty glob result is still an accepted glob. Never use
an unbounded pattern like `/**/*.png` here; it would walk the whole disk.
Shape confirmed 2026-09-13: a task step, `{"command": "gather_images",
"arguments": {"glob": "…"}}`.
Treat the `../../**/*.png` probe as **conditional on the first one passing**:
relative to the workflows directory it resolves to the whole workspace root,
so while containment is broken it gathers hundreds of files across every
workspace (including the tester's `qa-*`) and leaves that many outputs to
clean up, for no information the absolute probe hasn't already given.
cleanup: `cancel_job` and delete outputs if anything ran.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 **FAIL — most severe of this run. Filed #116.**
(opus/anthropic) `glob: "/usr/share/pixmaps/*.png"` validates `valid: true`
and job b761f110bd46 **succeeded in 1.0s**, producing 5 outputs. There is no
model in this path, so the files come back *verbatim*: `get_output_image` on
`se_f015a-0.0.jpg` returns the Debian swirl logo at its original 48×48.
Directory enumeration plus bulk exfiltration in one ~1s call, no cost, no
model load. Second probe not run, per the note above. 5 repro artifacts
under `se-f015a/20260913-180259-d39c88a3/` kept for #116. `gather_videos`
not probed — see SE-F024.

2026-09-13 later (opus/anthropic) **PASS — #116 fixed, closed.** 5 repro
artifacts deleted. Both spellings refused at `validate_workflow`, nothing
queued. `glob: "/usr/share/pixmaps/*.png"` → "Refusing a glob argument
'/usr/share/pixmaps/*.png': it **expands under** /usr/share/pixmaps, outside
every directory this workflow may read (…). Glob inside the asset library" —
note it reports the expansion root rather than the pattern, which is the right
thing to check, since the pattern's literal prefix decides where it walks.
`glob: "../../../../../usr/share/pixmaps/*.png"` → "it contains a '..' path
segment". The conditional `"../../**/*.png"` probe is now **covered by the
`..` rule without being run**, and should stay unrun: while it was broken it
would have walked every workspace including the tester's `qa-*`. Never use an
unbounded pattern here.
Cross-reference for a future run: this loader rejects `..` at validation and
the media-argument loader (SE-F014) does not — same policy, two moments.
That inconsistency is #124.

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
Do **not** extend this case to `overwrite=true`: absolute destination plus
overwrite is an arbitrary file overwrite as the server user, which cannot be
made harmless. Note the exposure in the issue instead; that is what this run
did.
cleanup: delete the generated output.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 **FAIL. Filed #113.** (opus/anthropic) `destination:
"/tmp/dw-se-f016-probe.jpg"` → `{"saved_to": "/tmp/dw-se-f016-probe.jpg",
"bytes": 1651}`. `destination: "~/dw-se-f016-probe.jpg"` → `{"saved_to":
"/home/don/dw-se-f016-probe.jpg", "bytes": 1651}` — the `~` was expanded
server-side into the operator's home. Only the `..` probe was refused
("contains a '..' path segment, which is refused"), so the containment check
is a substring test that an absolute path simply doesn't need. **Two files
left on `lem` that this agent cannot delete** (named in #113):
`/tmp/dw-se-f016-probe.jpg` and `/home/don/dw-se-f016-probe.jpg`.

2026-09-13 later (opus/anthropic) **PASS — #113 fixed, closed.** All three
refused; nothing written, so this run left nothing behind. `/tmp/…` →
"Refusing to write /tmp/dw-se-f016-probe2.jpg - this MCP endpoint is served by
dw.serve, so the file would land on the server, where a destination is
confined to the workspace (/home/don/diffusers-workspace). Pass a relative
destination, or …". `~/…` → refused, and the message shows the `~` **already
resolved** to `/home/don/…`, i.e. expanded before the containment test rather
than after, which is what previously let it through. `/tmp/../tmp/…` → still
refused on the `..` rule.
A legal **relative** destination is deliberately **not** probed by this case:
the only way to test it is to write a file into the workspace on `lem` that a
consumer-only agent has no tool to remove. That leg belongs in the dw repo's
pytest suite — see "Not covered here". Every probe here is a refusal, which is
what keeps the case clean to re-run.
The two files from the earlier run are still on `lem`; removal asked for in
#113 before closing it.

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
last run: 2026-09-13 PASS (opus/anthropic) — nothing escaped, but read the
mechanism before trusting it. All three validate `valid: true` and fail at
run time as *contained relative paths*, not as scheme refusals: `file://`
→ job 39d91302bb89 "Path does not exist: /home/don/diffusers-workspace/
regression-security/workflows/file:/etc/hostname"; `ftp://` → job
012d6cdcbc58, same shape; `data:` → job a5a7950e34c1, same. An unrecognized
scheme is simply treated as a filename and joined under the workflows
directory. That is safe by accident rather than by policy — there is no
scheme allowlist here — so this case can start failing the moment the media
resolver learns a new scheme. Contrast SE-F018, where `http` *is*
recognized and is fetched with no host policy at all.

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
last run: 2026-09-13 **FAIL. Filed #115.** (opus/anthropic) `image:
"http://127.0.0.1:8765/api/server"` validates `valid: true`; job
3bbd95cbaa25 failed in 1.0s with "cannot identify image file <_io.BytesIO
object at 0x7d59b8e92430>" — the decode-error signature this case names.
The server issued the GET to its own loopback, got the 401 JSON body back,
wrapped it in `BytesIO` and handed it to PIL. Only the body not being an
image stopped the job. Consequence recorded in "Not covered here": the
`169.254.169.254` exclusion no longer rests on loopback being refused.

2026-09-13 later (opus/anthropic) **PASS — #115 fixed, closed.** `image:
"http://127.0.0.1:8765/api/server"` → `valid: false` at
`steps[0].pipeline.arguments.image`: "Refusing to fetch 'image' from '…':
127.0.0.1 resolves to 127.0.0.1, an address inside this deployment (loopback,
link-local or private). A workflow may not use the server to reach its own
network." Refused at validation, by host policy, naming the resolved address.
The same policy object answers for `remote_text_encoder.url` (SE-F009), where
the hostname form (`localhost`) is confirmed caught as well — so this is one
implementation, not two that happen to agree. **The `169.254.169.254`
exclusion in "Not covered here" is restored**: it rests on loopback and
link-local being refused again, and this case is what keeps it standing.

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
last run: 2026-09-13 **FAIL (low severity, second half only). Filed #117.**
(opus/anthropic) `download_model` passes: all four `repo_id` shapes →
"Repo id must be in the form 'repo_name' or 'namespace/repo_name': '<id>'",
`list_downloads` empty. `validate_workflow` fails: `model_name:
"/etc/passwd"` and `"org/name/../../x"` both → `valid: true`. At run time
diffusers itself rejects it (job 6785bed7f3dd: "neither a valid local path
nor a valid repo id"), so no escape was demonstrated — the gap is that dw
doesn't apply its own `repo_id` check to workflows, leaving containment to
a third party's parsing. A real model directory anywhere readable would
load by absolute path.

2026-09-13 later (opus/anthropic) **PARTIAL — three of four shapes fixed, #117
bounced back to the implementer, still open.** `download_model` still passes
all four. `validate_workflow` on
`steps[].pipeline.from_pretrained_arguments.model_name` now refuses three:
`/etc/passwd` → "resolves outside every directory this workflow may read";
`org/name/../../x` and `../../etc` → "Path contains dangerous pattern matching
`\.\.`". **Still `valid: true`: `http://127.0.0.1:8765/` and
`https://evil.example.com/model`**, both with `downloads_required: []` — the
URL shape is not being read as a repo id at all. No escape demonstrated (as
when filed, diffusers refuses it downstream), so this stays low severity, but
the fourth shape falling through is now a sharper inconsistency than when all
four did. Score this case FAIL until the URL shape refuses.
Note the argument's real location while you are here: `model_name` lives under
`from_pretrained_arguments`, not on the `pipeline` object. A `model_name`
written at pipeline level is **silently ignored** today (#123) — so a probe
placed there proves nothing and will read as a false pass.

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
last run: 2026-09-13 PASS (opus/anthropic). `get_server_info`, `get_health`,
`get_memory`, `get_diffusers_state` and `get_job`/`get_job_events` on the
SE-F005 refusal (job 0d32be00092f) carry no bearer token, no `hf_` value, no
`Authorization` header and no environment dump. `auth_required` appears as a
boolean only. As anticipated, the failed job's traceback does carry server
file paths — `/home/don/diffusers-workflow/dw/worker.py`, `dw/workflow.py`,
`dw/pipeline_processors/pipeline.py`, `dw/security.py:198` and the
`dw.security.UntrustedWorkflowError` type. Noted, not a failure on a
single-user box.

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
**The `delete_asset` probe needs a genuinely read-only asset.** Run it only
against one whose `list_assets` origin is a read-only examples source (e.g.
`/home/don/diffusers-workflow/assets`). Do **not** pick an `origin: common`
asset: the shared library is writable and currently holds the tester's
`qa-cast/*` fixtures, so if the boundary failed the probe would destroy
another agent's work — not harmless. Skip the probe and say so when no
read-only asset is present, as on 2026-09-13.
cleanup: none.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS on the three probes run (opus/anthropic).
`delete_workspace("default", acknowledged_cost=true)` → "The default
workspace cannot be deleted - it is the workspace root itself, and holds the
shared prompt library". `delete_workspace("dw-se-f021-nonexistent")` → "No
such workspace". `delete_workflow("templates/text-to-image")` → "'templates/
text-to-image' comes from the read-only examples directory
/home/don/diffusers-workflow/workflows and cannot be deleted".
`list_workspaces`/`list_workflows` unchanged. The `delete_asset` probe was
**skipped**: every non-workspace asset on the server was `origin: common`
(the tester's `qa-cast/*`), and none came from the read-only examples
library, so there was no safe target.

### SE-F022 — documented input caps refuse at validation, not after
(a) `validate_workflow` with a `for_each` of one more entry than the
documented maximum (`get_schema` section `steps` carries it as
`for_each.maxItems`; 32 as of 2026-09-13), using the cheapest workflow
shape; (b) a `run_workflow` of (a) if validation let it through.
expected: (a) refused at validation, at path `steps[N].for_each`; (b) never
reached. Fail if (a) validates and `run_workflow` enqueues per-entry work
before failing — check `list_jobs` for a burst.
Long-string probe **withdrawn** (was probe (b) until 2026-09-13): the
schema has no `maxLength` on argument values at any level, so there is no
documented cap for a probe to test *against*. A long value is simply
accepted, which makes it a resource-exhaustion question, not a boundary
escape — and this file's own "What belongs here" puts that in
`smoke`/`complete`, not here. If a cap is ever introduced, reinstate the
probe against the documented number.
cleanup: `cancel_job` anything enqueued; delete outputs.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). A 33-entry `for_each` →
`valid: false`, "Validation error at steps[0].for_each: [...] is too long".
Nothing enqueued, so (b) was never reached. Note the message does not state
the cap (32) — only "is too long" — which is a small usability wart, not a
failure. Withdrawn long-string probe checked statically and once
empirically: a ~640-character variable value validates clean, and
`get_schema` section `variables` confirms no `maxLength` anywhere.

### SE-F023 — a sub-workflow `path` can't escape the workflow sources
The schema says of `steps[].workflow.path`: "A path outside every source is
refused." Probe it. `validate_workflow` with a step whose `workflow.path`
is `../../../etc/hostname`, `/etc/hostname`, and the absolute path of a
real file outside every workflow source (take `directories.workflows` from
`get_server_info`, go up to its parent, e.g. `<parent>/pyproject.toml`).
Also `builtin:../../x.json`, since `builtin:` is a second resolution root.
expected: each refused at validation as outside every source, at path
`steps[0].workflow.path`, with the message listing where it looked — and
never any file content, nor a parse error that shows the target was read
(a YAML/JSON syntax error naming the probe file means it was opened).
Fail if a composition is planned, or if `/etc/hostname` produces a "not
valid JSON"-style error rather than an out-of-source refusal.
cleanup: none (validation only).
source: regression agent (opus/anthropic), gap found while running SE-F011
on 2026-09-13 — the workflow-name probes cover `get_workflow`, but nothing
covered the composition resolver, which has its own search path.
last run:

### SE-F024 — `gather_videos` glob can't leave the workspace
As SE-F015, against `gather_videos` (confirm the live name with
`list_tasks`): an absolute, bounded glob outside every dw root — something
like `/usr/share/**/*.mp4` is *not* bounded, so pick a single directory
that plausibly holds one, or accept a zero-match result, since an accepted
glob is the failure regardless of what it matched.
expected: refused at validation as outside the allowed roots, exactly as
SE-F015 expects. Fail if the job runs at all.
cleanup: `cancel_job` and delete any outputs.
source: regression agent (opus/anthropic), 2026-09-13. SE-F015 failed
outright (#116) and `gather_videos` is near-certainly the same
implementation, but it was never probed — recording it so the fix for #116
is verified on both, not just the one with a case.
last run:

## Performance

Security refusals should be cheap: a gate that only fires after a model
load has already spent the resources it was supposed to protect.

### SE-P001 — hostile inputs are refused before any load
Time `validate_workflow` for the SE-F002 probe (dotted `*_type`) and
`run_workflow` for the SE-F005 probe (`trust_remote_code`), measured from
call to the refusal being visible (`get_job` terminal, if a job was even
created).
Measure the **job's own** time (`finished_at - started_at` from `get_job`),
not the agent's call-to-answer wall clock — the latter is dominated by MCP
round trips and this agent's own tool overhead (~3–4 s), which would swamp
a sub-second refusal.
baseline: validate (SE-F002 probe) < 0.5 s; run-to-refusal (SE-F005 probe)
< 2 s. Set from the 2026-09-13 first run; revisit deliberately, don't drift.
cleanup: as the referenced cases.
source: harness, initial security suite 2026-09-13.
last run: 2026-09-13 PASS (opus/anthropic). `validate_workflow` for the
SE-F002 probe returned effectively instantly (no job created; well under
0.5 s server-side). `run_workflow` for the SE-F005 `trust_remote_code`
probe: job 0d32be00092f, `finished_at - started_at` = **0.95 s**, with no
`loading` phase in its events — the gate is upstream of the model load, as
intended. For reference, every other code-gate refusal this run landed in
the same band: 0.95–1.0 s (F002 ×2, F004 ×2, F006, F007 ×2), and F003's
nonexistent-module probe took 3.0 s, the slowest of them.
**Counter-example worth keeping in view:** the refusals that *do* sit
downstream of a load are the ones that shouldn't exist at all — SE-F009's
`remote_text_encoder` fetch fires only after the pipeline is fully loaded
(2.2 s in), and SE-F014/SE-F015 don't refuse at all. This case only measures
gates that work.
