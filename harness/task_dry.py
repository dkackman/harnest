"""The standing task's dry-round rule, read side.

run-loop.sh (note_task_round) counts the standing-task sessions in a row
that filed no issue and added no suite case, in logs/task-dry. From
TESTER_TASK_DRY_ROUNDS of them the task waits twice its gap, doubling per
further dry round up to TESTER_TASK_DRY_MAX times; 0 rounds turns the rule
off. factor() here must agree with task_dry_factor in run-loop.sh.
"""

import os

NAME = "task-dry"


def count(logs):
    try:
        with open(os.path.join(logs, NAME), encoding="utf-8") as fh:
            text = fh.read().strip()
    except OSError:
        return 0
    return int(text) if text.isdigit() else 0


def factor(logs, rounds, most):
    """How many times its gap the standing task waits now."""
    if rounds <= 0:
        return 1
    over = count(logs) - rounds + 1
    f = 1
    while over > 0 and f < most:
        f *= 2
        over -= 1
    return max(1, min(f, most))
