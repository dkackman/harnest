"""The driver's own lines: to stdout and appended to the server's loop log,
which is what `echo ... | tee -a "$LOOP_LOG"` does in bash."""

import sys
import time


def ts():
    return time.strftime("%H:%M:%S")


class Log:
    def __init__(self, path):
        self.path = path

    def say(self, line, err=False):
        stream = sys.stderr if err else sys.stdout
        stream.write(line + "\n")
        stream.flush()
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(line + "\n")

    def append(self, text):
        """Lines to the loop log only (already prefixed by the caller)."""
        with open(self.path, "a", encoding="utf-8") as f:
            f.write(text)


def err(msg):
    sys.stderr.write(msg + "\n")
    sys.stderr.flush()
