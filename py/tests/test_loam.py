"""The Python gates: the binding over the seam, and G1 across two
PROCESSES — the regime the brief names — through both doors.

Run: `zig build py-test` (builds first), or `python3 -m unittest discover -s py/tests`.
"""

import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "py"))

import loam  # noqa: E402
from loam.dump import read  # noqa: E402

RUN = os.path.join(ROOT, "zig-out", "bin", "loam-run")


def sapling(seed=7, steps=30):
    w = loam.World(seed=seed)
    w.blob("growth", (0, 24, 0), 56, 1.0)
    w.blob("light", (40, 60, 0), 64, 1.0)
    w.plant((0, 0, 0), (0, 1, 0), length=72, tropism_light=0.6)
    w.apply()
    w.add_decay("activity", tau=3.0)
    w.add_healing()
    w.run(steps)
    return w


class Binding(unittest.TestCase):
    def test_version_and_channels(self):
        self.assertEqual(loam.version(), 1)
        w = loam.World(seed=1)
        self.assertEqual(w.channel("density"), 0)
        self.assertEqual(w.channel("material"), 12)
        bit = w.register("moisture", 0.0, 1.0)
        self.assertEqual(bit, 32)
        with self.assertRaises(loam.LoamError):
            w.register("moisture")
        with self.assertRaises(loam.LoamError):
            w.channel("oak")

    def test_blob_sample_and_ray(self):
        w = loam.World(seed=1)
        w.blob("density", (20, 0, 0), 6, 1.0)
        w.blob("light", (0, 0, 0), 64, 1.0)
        w.apply()
        self.assertGreater(w.sample("density", (20, 0, 0)), 0.9)
        self.assertEqual(w.sample("density", (-20, 0, 0)), 0.0)
        vals = w.sample_many("density", [(20, 0, 0), (-20, 0, 0)])
        self.assertGreater(vals[0], 0.9)
        self.assertEqual(vals[1], 0.0)
        sampled, crossed = w.ray_count("density", (-100, 0, 0), (1, 0, 0))
        self.assertGreater(crossed, sampled)
        self.assertGreaterEqual(sampled, 1)
        st = w.stats()
        self.assertGreater(st["bricks"], 8)

    def test_time_regression_is_refused(self):
        w = loam.World(seed=1)
        w.step(5, 50)
        with self.assertRaises(loam.LoamError) as cm:
            w.step(6, 40)
        self.assertEqual(str(cm.exception), "TimeRegression")

    def test_growth_grows_and_is_deterministic_in_process(self):
        a = sapling()
        b = sapling()
        self.assertEqual(a.root_hash(), b.root_hash())
        self.assertGreater(a.total("material"), 0)
        self.assertGreaterEqual(len(a.fronts()), 1)
        c = sapling(seed=8)
        self.assertNotEqual(a.root_hash(), c.root_hash())
        # A slice and a projection come back the right size.
        self.assertEqual(len(a.slice("material", "z", 0, (-32, -32), (32, 32), 16)), 256)
        self.assertEqual(len(a.project("material", "z", (-32, -16, -32), (32, 80, 32), 16)), 256)

    def test_dump_round_trips_through_struple(self):
        w = sapling(steps=10)
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "s.struple")
            w.dump(path)
            d = read(path)
        self.assertEqual(d["root_hash"], w.root_hash())
        self.assertEqual(d["content_hash"], w.content_hash())
        self.assertEqual(d["vid"], w.stats()["vid"])
        names = {n for b in d["bricks"] for n in b["planes"]}
        self.assertIn("material", names)
        self.assertEqual(len(d["fronts"]), w.stats()["fronts"])


@unittest.skipUnless(os.path.exists(RUN), "loam-run not built")
class ReplayAcrossProcesses(unittest.TestCase):
    """G1 in the brief's regime: two processes, byte-identical snapshot."""

    def _hash(self, extra=()):
        out = subprocess.run([RUN, "--steps", "30", "--every", "0", *extra], capture_output=True, text=True, check=True).stdout
        for line in out.splitlines():
            if line.startswith("content_hash"):
                return line.split()[1]
        self.fail("no content_hash in loam-run output")

    def test_two_processes_agree(self):
        self.assertEqual(self._hash(), self._hash())

    def test_perturbed_seed_differs(self):
        self.assertNotEqual(self._hash(), self._hash(["--seed", "6"]))

    def test_python_and_cli_agree(self):
        # The Python door and the CLI door drive the same world: the
        # sapling scene, spelt out here and built in by loam-run.
        w = sapling(steps=30)
        self.assertEqual(w.content_hash().hex(), self._hash())

    def test_dump_from_cli_reads_in_python(self):
        with tempfile.TemporaryDirectory() as td:
            path = os.path.join(td, "cli.struple")
            subprocess.run([RUN, "--steps", "12", "--every", "0", "--dump", path], capture_output=True, check=True)
            d = read(path)
        self.assertGreater(len(d["bricks"]), 0)


if __name__ == "__main__":
    unittest.main()
