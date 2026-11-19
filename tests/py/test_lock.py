"""harness/lock.py: the driver lock (release is owner-checked, R17)."""

import os
import tempfile
import unittest

from harness import lock


class LockTest(unittest.TestCase):
    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        self.lock = os.path.join(d.name, ".driver.lock")
        self.said = []

    def owner(self):
        with open(os.path.join(self.lock, "owner")) as f:
            return f.read().strip()

    def test_acquire_and_release(self):
        self.assertTrue(lock.acquire(self.lock, "run-loop", self.said.append, held=""))
        self.assertEqual(self.owner(), f"{os.getpid()} run-loop")
        self.assertTrue(lock.release(self.lock))
        self.assertFalse(os.path.exists(self.lock))

    def test_release_leaves_another_holder(self):
        os.mkdir(self.lock)
        with open(os.path.join(self.lock, "owner"), "w") as f:
            f.write("1 run-regression\n")
        self.assertFalse(lock.release(self.lock))
        self.assertTrue(os.path.isdir(self.lock))

    def test_stale_lock_taken_over(self):
        os.mkdir(self.lock)
        with open(os.path.join(self.lock, "owner"), "w") as f:
            f.write("999999 run-loop\n")
        lock.acquire(self.lock, "run-loop", self.said.append, held="")
        self.assertEqual(self.owner(), f"{os.getpid()} run-loop")
        self.assertIn("[lock] taking over a stale lock from '999999 run-loop'", self.said)
        lock.release(self.lock)
