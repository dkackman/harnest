
## This session: REVIEW one area of the release

Your prompt names the area and the range (`<base>..<candidate>`, i.e.
master...develop). Read the range as one change: `git log --oneline` for its
shape, `git diff --stat`, then the changed code in context, in the tree
itself. Delegate a wide sweep to a subagent (Agent) when the area spans many
files. Run it in the foreground, and give it the same read-only brief.

### Areas

- **security**: the untrusted-workflow gate: dotted types, `constant:`,
  `pre_load_modules`, `trust_remote_code` and `custom_pipeline`. Then:
  - path containment for outputs, assets, workflows, prompts and workspaces,
    including symlinks;
  - the URL and host policy: private ranges, redirects and schemes;
  - anything that discloses a secret, a server path, or whether a file exists;
  - destructive tools without `acknowledged_cost`;
  - routes outside the token gate. The auth middleware covers `/api/` and
    `/mcp` only.
- **engine**: workflow execution, argument resolution, tasks, the step cache,
  and the save path. Look for fixes to one copy of duplicated logic that
  missed the twin, fixes in the range that contradict each other, and tests
  that mock the very thing the fix claims.
- **mcp-and-docs**: the MCP tools' parameters, response shapes and error
  text. A change a caller would notice needs `breaking-change` and a release
  note. Also check `docs/`, the served guides and `plugins/dw/skills` against
  the code as it now behaves.
- **templates-ui-packaging**: `templates/` and `workflows/`, which should run
  with their own defaults and warn only on what a caller can act on. Also
  `ui/`, `pyproject.toml` and anything the wheel or `install.sh` ships.

### Each finding

Verify it by reading the code. Say what input goes wrong, and what happens.
If you can't say that, it's not a finding. Then decide:
- `blocker`: releasing this ships a bug, a hole or a false doc that users
  will hit. Fix it first.
- `follow-up`: real, but it can ship and be fixed after.
- `security: true` for anything an untrusted caller could use against the
  server or its operator. Those never reach the public tracker. Describe them
  just as fully: the driver keeps them in a local file for Don.

### The file

A JSON array, nothing else in the file, `[]` if the area is clean:

    [{"area": "<your area>",
      "severity": "blocker" | "follow-up",
      "security": true | false,
      "title": "<one line, as an issue title>",
      "file": "<path:line>",
      "detail": "<what goes wrong, the input that shows it, what the fix is; the model and provider you ran as>"}]

A malformed file fails the whole review stage, so write it once, with
`Write`, at the end.
