"""The board as the loop driver sees it (R17): lib/classify.jq's rows per
server, read through lib/board.sh, and the work items they make.

lib/classify.jq stays the state machine. Each server's classify pass says
which queue an issue is in *for that server* (another server's claim holds
it at `wait` there); items() only folds the per-server answers into one
list of work items for harness/scheduler.py: who runs an item is the
board's call, when and where is the scheduler's.
"""

from __future__ import annotations

import contextlib
import os
import signal
import subprocess
from typing import NamedTuple

from . import REPO
from .scheduler import PRIORITY, Item

BOARD_SH = REPO / "lib" / "board.sh"

# Queues the board hands out, per issue. curator, tester:closures and
# tester:task are not board queues: the driver offers them itself.
BOARD_QUEUES = frozenset(PRIORITY) - {"curator", "tester:closures", "tester:task"}

# Server-free work that runs once, not once per server: an unclaimed one goes
# to the first server the driver drives (lem's, while it drives lem), as
# run-loop.sh's shared_passes_here has it. A stranded issue nobody claims is
# that server's to unstrand too (stranded_here).
SHARED = frozenset({"reviewer:arch", "reviewer:docs", "tester:spec", "tester:handoff", "delegate:rule"})

# Design and decompose read a lead worktree at origin/develop and make no
# claim, so an unclaimed one may run in any offering server's lead tree: it
# gets those servers as candidates, like an unclaimed fix, rather than
# queueing behind the first server's one leadtree slot while the other idles.
LEAD_ANY = frozenset({"lead:design", "lead:decompose"})

# R19's delegate rules for Don on any issue, claimed or not: a target:* claim
# names the loop working the issue, and the delegate is neither loop's. Its
# item always goes to the first server (the shared passes' loop).
UNCLAIMED = frozenset({"delegate:rule"})

# A stranded issue is unstranded by the implementer pass's triage
# (run-item.sh implementer <n>), which holds what a fix holds.
STRANDED = "stranded"


class Row(NamedTuple):
    number: int
    queue: str
    parent: int | None
    reason: str
    holder: str | None = None  # the server whose target:* claim holds it (board.sh)


# A board read is a few gh calls: past this it is hung (a dead network, a gh
# waiting on something), and its whole process group is killed.
BOARD_TIMEOUT = 120


def _run(args, env=None, timeout=BOARD_TIMEOUT):
    try:
        p = subprocess.Popen(
            ["bash", str(BOARD_SH), *args],
            cwd=str(REPO),
            env=env if env is not None else os.environ.copy(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            errors="replace",
            start_new_session=True,
        )
    except OSError:
        return None
    try:
        out, errs = p.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError, PermissionError):
            os.killpg(p.pid, signal.SIGKILL)
        with contextlib.suppress(subprocess.TimeoutExpired):
            p.communicate(timeout=5)
        return None
    return subprocess.CompletedProcess(p.args, p.returncode, out, errs)


def parse(text: str) -> list[Row]:
    rows = []
    for line in text.splitlines():
        f = line.split("\t")
        if len(f) < 4 or not f[0].isdigit():
            continue
        parent = int(f[2]) if f[2].isdigit() else None
        holder = f[4] if len(f) > 4 and f[4] not in ("", "-") else None
        rows.append(Row(int(f[0]), f[1], parent, f[3], holder))
    return rows


def snapshot(target: str, env=None) -> list[Row] | None:
    """classify_issues for <target>, or None when the board can't be read."""
    p = _run([target], env)
    if p is None or p.returncode != 0:
        return None
    return parse(p.stdout)


def query(what: str, target: str, env=None, *extra) -> str | None:
    """`board.sh <what> <target> [extra]`'s output, or None when it failed."""
    p = _run([what, target, *extra], env)
    if p is None or p.returncode != 0:
        return None
    return p.stdout


def status_rows(text: str) -> list[list]:
    """status_board's lines as [number, status, owner, title]."""
    out = []
    for line in text.splitlines():
        f = line.split(None, 3)
        if len(f) < 3 or not f[0].startswith("#") or not f[0][1:].isdigit():
            continue
        out.append([int(f[0][1:]), f[1], f[2], f[3] if len(f) > 3 else ""])
    return out


def numbers(text: str | None) -> list[int]:
    return [int(x) for x in (text or "").split() if x.isdigit()]


def _item_queue(queue: str) -> str | None:
    if queue == STRANDED:
        return "implementer:fix"
    return queue if queue in BOARD_QUEUES else None


def items(rows_by_target: dict[str, list[Row]]) -> list[Item]:
    """One work item per (queue, issue) across the servers' rows, in the
    order the rows came. rows_by_target is in the driver's server order.

    - An issue only one server offers is that server's (a claim, or a backend
      only it serves).
    - A claimed stranded issue is its holder's; an unclaimed one, and an
      unclaimed SHARED item, the first server's that offers it.
    - Any other item several servers offer (an unclaimed fix, build,
      close-out, design or decompose any of them may take) gets those servers
      as candidates: the scheduler gives it to the first with its resources
      free.
    """
    offers: dict[tuple, list] = {}
    order = []
    for target, rows in rows_by_target.items():
        for r in rows or ():
            q = _item_queue(r.queue)
            if q is None:
                continue
            key = (q, r.number)
            if key not in offers:
                offers[key] = []
                order.append((key, r))
            offers[key].append(target)
    out = []
    for (q, n), row in order:
        targets = offers[(q, n)]
        holder = row.holder
        if q in UNCLAIMED:
            out.append(Item(q, n, targets[0]))  # a claim says which loop works the issue, not who rules for Don
        elif holder is not None and holder in targets:
            out.append(Item(q, n, holder))
        elif row.queue == STRANDED and holder is not None:
            continue  # the holding loop's to unstrand, and it isn't driven here
        elif len(targets) == 1 or row.queue == STRANDED or q in SHARED:
            out.append(Item(q, n, targets[0]))
        else:
            out.append(Item(q, n, None, tuple(targets)))
    return out
