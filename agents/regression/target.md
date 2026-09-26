## Target: the {{TARGET}} server, not lem

This run is against the {{TARGET}} server ({{SERVER}}, {{URL}}), not lem.
The suites were written on lem: a Linux box with a 24 GB CUDA GPU (RTX
3090), whose storage holds assets, prompts and job history that other
agents made there by hand. This server starts from the same code and the
same bundled templates, and nothing else. It is also several times slower.
Where your role instructions or the suite file say otherwise, this section
wins. The harness guard enforces the file and label rules below.

### What you file

- An open issue for the same case covers a failure here when it is
  neither `backend:cuda` nor claimed by lem's loop (`target:lem`): comment
  on it. Never comment on a `target:lem` issue, even for the same case.
  The tester there reads its latest comments while verifying a fix on lem,
  and a symptom from this server would bounce a fix that works there. File
  your own instead, and reference it (`also fails on lem: #NN`).
- A new issue gets `owner:implementer` and `backend:mps`, plus
  `regression`/`performance` as usual. Use `backend:shared` instead when
  the same case also fails on lem (there's a lem issue for it): the bug is
  not about the accelerator. Never add a `target:` label; claims are the
  loop driver's. Name the target and accelerator ({{SERVER}}) in its body.
- The MCP server down is this server's outage, not lem's. Search with
  `--label backend:mps`, and file it the same way. The REGRESSION-ABORT
  line is unchanged.
- Stage issue bodies at `/tmp/<case>-{{TARGET}}-issue.md`. A run on lem
  may be staging the same case at the same time.
- An advisory's summary starts with `[{{TARGET}}] <case id>:`, and its
  description names the target and accelerator. Without that tag the
  dedupe would append this server's finding to lem's advisory, or seed
  one from it.

### What you may not edit

- The suite files. Every case in them runs on lem, and an expectation this
  server shows would fail there. Propose a case worth adding in the issue
  or comment body instead. (The loop's tester here may add one for a
  shared fix it verified; a regression run never does.)
- Performance history anywhere but `regression-perf/{{TARGET}}/<case>.jsonl`.
  The top-level files are lem's. When this server's file doesn't exist yet,
  create it with `Write` (your reading is its first line); after that,
  append with `Edit` as usual.

### Timing

Every absolute time in a case was measured on lem's CUDA GPU: a
`baseline:` ceiling, an "under N s", "about N min of GPU", a warm/cold
figure, a curated `cost` minutes figure. None of them applies here. Record
the reading and judge it only against this server's own history, under the
usual median rule. Fewer than 3 prior entries: record and move on. A
reading that includes a first-time model download is not a baseline: note
`"first run, includes download"` on it. A `wait_seconds` reply with
`still_running: true` is expected more often here. Follow it with
`wait_for_job`, and don't treat it as a finding.

### Skipped, not failed

Skip a case, and say so in your final message on a line of its own that
starts with `REGRESSION-SKIP: <case> <reason> <what>` (no bullet, no
backticks: the driver counts these lines; when there are none, write no
such line), when one of these holds:

- `fixture`: an asset, prompt, workflow, job or output the case needs
  before it starts is not on this server. Check before running it
  (`list_assets`, `list_prompts`, `list_jobs`), and name what's missing.
  Most `asset:qa-cast/…`, `asset:cast/…` and `asset:reference_sheet.jpg`
  fixtures exist only on lem until they are copied here.
- `cuda`: the expectation is about CUDA hardware itself: `device: cuda`
  behavior, VRAM or `gpu_memory_*` figures, an RTX 3090 or 24 GB ceiling,
  the caching allocator, or a model the case says needs a 24 GB card.
- `memory`: running it would load MiniMax H3, LTX-2.5 at full size, a
  very large image (thousands of pixels a side), or anything the case puts
  in the tens of GB. This machine has 64 GB of unified memory shared with
  the OS, and running out takes the server down mid-run. The driver
  already holds back the cases it knows of; your prompt names them.

Never skip because of an error the case's own calls produced. A missing
asset that a case probes on purpose (a `…-NOPE` name, a bad path) is the
test, and a refusal or an error in the case under test is a result: pass
or fail. A skip is for a precondition checked before the case starts.

### Differs on this server

Some expectations are really about lem's history or hardware, and the
difference is what this run is for: a quote's `basis` (here likely
`other_device`), `measured_on`, `observed` runs, a device name, `runtime`
fields such as `cuda_version`. Don't file these as failures. List each on
a line of its own in your final message, starting
`REGRESSION-DIFFERS: <case> <field>: expected <lem's> got <this server's>`
(no bullet, no backticks).

### Security probes

Paths the security suite probes are Linux paths. `/etc/hostname` and
`/usr/share/pixmaps/` don't exist on macOS, so a bare "not found" proves
nothing. For a *read* probe, use `/etc/hosts` in its place. Never point a
delete or write probe at a real file on this machine. A leaked server path
here looks like `/Users/…` or `/private/…`, as well as `/home/`, `/var/`,
`/srv/` or `/mnt/`. If `get_server_info` says `trust_workflows: true`,
stop the security level as the suite says.

### Sweep

A repro artifact is kept only when an open issue that lem's loop doesn't
hold (no `target:lem`) names it. Everything else this run made goes, as usual.
