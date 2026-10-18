"""The driver lock: one driver at a time per server (logs/.driver.lock<sfx>).

A port of providers.sh's acquire_driver_lock, same protocol, so a bash
driver and a Python one exclude each other:
- mkdir is the atomic step; `<pid> <name>` goes in its owner file;
- a holder whose pid is gone is stale, and so is an owner-less lock older
  than two minutes (a holder killed between its mkdir and its write);
- a stale lock is taken over by renaming it aside and checking that what
  was renamed is what was judged stale, so two waiters can't both win;
- a driver started under one that holds the lock (run-release.sh's gates
  run the regression driver) names it in HARNEST_HELD_LOCK and runs under
  it, leaving the release to the parent.
"""
import atexit
import os
import shutil
import time


def _alive(pid):
    try:
        os.kill(int(pid), 0)
    except (ValueError, ProcessLookupError):
        return False
    except PermissionError:
        return True
    return True


def _owner(lock):
    try:
        with open(os.path.join(lock, "owner"), encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def acquire(lock, name, say, held=None, poll=30, sleep=time.sleep):
    """Blocks until <lock> is this process's; releases it at exit."""
    held = os.environ.get("HARNEST_HELD_LOCK", "") if held is None else held
    if held and _owner(lock) == held:
        say(f"[lock] {name} runs under '{held}'")
        return False
    waited = False
    while True:
        try:
            os.mkdir(lock)
            break
        except FileExistsError:
            pass
        holder = _owner(lock)
        stale = False
        if holder:
            stale = not _alive(holder.split(" ", 1)[0])
        else:
            try:
                stale = time.time() - os.stat(lock).st_mtime > 120
            except OSError:
                continue
        if stale:
            aside = f"{lock}.stale.{os.getpid()}"
            try:
                os.rename(lock, aside)
            except OSError:
                continue
            if _owner(aside) == holder:
                say(f"[lock] taking over a stale lock from '{holder or 'no owner'}'")
                shutil.rmtree(aside, ignore_errors=True)
            else:
                # Another waiter took it over first; put its live lock back.
                try:
                    os.rename(aside, lock)
                except OSError:
                    shutil.rmtree(aside, ignore_errors=True)
            continue
        if not waited:
            say(f"[lock] {name} waiting for '{holder}' to finish")
        waited = True
        sleep(poll)
    with open(os.path.join(lock, "owner"), "w", encoding="utf-8") as f:
        f.write(f"{os.getpid()} {name}\n")
    atexit.register(shutil.rmtree, lock, True)
    return True
