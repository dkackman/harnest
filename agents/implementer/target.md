## Target: the {{TARGET}} server, not lem

This loop runs against the {{TARGET}} server ({{SERVER}}, {{URL}}), a
dw server on this machine, not lem. lem is a Linux box with a CUDA GPU that
another loop deploys to; this one is Apple silicon with MPS, several times
slower, and has none of lem's hand-made assets or job history. Where your
role instructions say lem, this section wins. The harness guard enforces
the ssh and label rules below.

### Deploy

Every "deploy to lem" in your instructions means, here, this one command,
from any directory:

    {{DEPLOY}}

It fast-forwards the serving clone ({{SERVER_DIR}}) to `develop`,
reinstalls when `pyproject.toml` changed, waits for a running job,
restarts the server in the `dw-serve` screen session and polls health.
"Server code: deploy. Plugin or skill: merge and push" is unchanged, and
so is "merge to `develop`, deploy `develop`": lem's loop deploys the same
branch. Never commit in {{SERVER_DIR}}; it is only deployed.

### No lem

You have no ssh here: the guard refuses `ssh`, `scp` and `rsync`. lem's
logs, its GPU and what it runs are out of reach, and not needed. This
server's log is `~/dw-serve.log`. What it runs:
`git -C {{SERVER_DIR}} log -1 --oneline`. Reproduce against it, or with
the source checkout's own tests.

### Which issues are yours

The driver claimed this issue for this loop (`target:{{TARGET}}`) before
your session. Its `backend:` label decides whether it belongs here
("Backend and target labels"):

- It turns out to be about CUDA (label it `backend:cuda` if it isn't):
  hand it to lem's loop with
  `gh issue edit N --remove-label target:{{TARGET}} --add-label target:lem`,
  comment why, and stop. Don't fix it here.
- A fix you can only check on CUDA hardware: say so in the hand-off
  comment. The tester here hands it on to lem.

### Timing

A `wait_for_job` that runs out, or a `still_running: true`, is expected
more often here than on lem, and is not a hang. Keep checks light: prefer a
small image or a short clip to anything that loads a large model.
