#!/usr/bin/env python3
"""read_dump — read a loam snapshot dump with the struple Python port.

No loam code on this side beyond `py/loam/dump.py`'s decoding of plane
bytes: the dump is one canonical struple map and `struple.unpack` is the
whole reader. This is the cross-language half of the dump gate — a
format only Zig can read is a format with one witness. Run by
`zig build verify-dump`, which produces a dump with loam-run first.

Checks the shape: every brick's planes are 729 floats, its mask names
exactly the planes present, keys are ascending and unique, fronts are in
id order, and the root hash is 32 bytes. Exits non-zero on disagreement.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "py"))

from loam.dump import read  # noqa: E402


def fail(msg):
    print(f"read_dump: {msg}", file=sys.stderr)
    sys.exit(1)


def main(path):
    d = read(path)
    if d["lattice_bits"] != 20 or d["brick_cells"] != 8:
        fail("lattice or brick geometry is not the one loam declares")
    if len(d["root_hash"]) != 32 or len(d["content_hash"]) != 32:
        fail("hashes are not 32 bytes")
    channels = d["channels"]
    by_bit = {v: k for k, v in channels.items()}
    samples = (d["brick_cells"] + 1) ** 3
    keys = [b["key"] for b in d["bricks"]]
    if keys != sorted(keys) or len(set(keys)) != len(keys):
        fail("brick keys are not ascending and unique")
    nonzero = 0
    for b in d["bricks"]:
        present = {by_bit[i] for i in range(64) if (b["mask"] >> i) & 1}
        if present != set(b["planes"]):
            fail(f"brick {b['key']}: mask names {sorted(present)} but planes are {sorted(b['planes'])}")
        for name, pl in b["planes"].items():
            if len(pl) != samples:
                fail(f"brick {b['key']} plane {name}: {len(pl)} samples, not {samples}")
            if not any(pl):
                fail(f"brick {b['key']} plane {name}: all zero — an absent channel was instantiated")
            nonzero += 1
    ids = [f["id"] for f in d["fronts"]]
    if ids != list(range(len(ids))):
        fail("front ids are not 0..n-1 in order")
    print(f"fmt {d['fmt']}  vid {d['vid']}  epoch {d['epoch']}  bricks {len(d['bricks'])}  planes {nonzero}  fronts {len(d['fronts'])}  active {len(d['active'])}")
    print(f"root_hash {d['root_hash'].hex()}")
    print("read_dump: ok")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: read_dump.py <dump.struple>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
