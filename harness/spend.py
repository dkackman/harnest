"""The dated spend record, logs/spend.tsv: one line per session attempt that
reported a cost, as date, epoch, dollars and label, tab-separated.

DAY_BUDGET_USD is checked against it, because loop.log carries HH:MM:SS
only. providers.sh (spend_record, spend_today, day_budget_reached) writes
and reads the same file for the bash drivers; the format here must match.
"""

import os
import re
import time

NAME = "spend.tsv"


def cost_in(last):
    """The cost on the usage: line(s) of one rendered session, or None."""
    cost = None
    try:
        with open(last, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if not line.startswith("usage: "):
                    continue
                for tok in line.split():
                    if tok.startswith("cost=$"):
                        try:
                            cost = (cost or 0.0) + float(tok[6:])
                        except ValueError:
                            pass
    except OSError:
        return None
    return cost


def _day(day=None):
    return day or time.strftime("%Y-%m-%d")


def record(logs, label, last, day=None, clock=time.time):
    """Append the cost of the session rendered in <last>; a session with no
    usage: line records nothing. Never raises: a full disk must not stop a
    driver."""
    cost = cost_in(last)
    if cost is None:
        return None
    line = f"{_day(day)}\t{int(clock())}\t{cost:.2f}\t{label}\n"
    try:
        with open(os.path.join(logs, NAME), "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError:
        return None
    return cost


def today(logs, day=None):
    """The dollars recorded on <day> (default: today's local date)."""
    day = _day(day)
    total = 0.0
    try:
        with open(os.path.join(logs, NAME), encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3 and parts[0] == day:
                    try:
                        total += float(parts[2])
                    except ValueError:
                        continue
    except OSError:
        return 0.0
    return total


def budget(environ=None):
    """DAY_BUDGET_USD as a float; 0 means uncapped. Raises ValueError on
    anything that is not a number >= 0."""
    raw = (os.environ if environ is None else environ).get("DAY_BUDGET_USD") or "0"
    # The same shape run-loop.sh accepts (digits with at most one point): an
    # item's bash pass validates it again and would exit on anything else.
    if not re.fullmatch(r"[0-9]+\.?[0-9]*|\.[0-9]+", raw):
        raise ValueError(raw)
    return float(raw)


def reached(logs, limit, day=None):
    return limit > 0 and today(logs, day) >= limit
