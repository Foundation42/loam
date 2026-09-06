"""Read a loam snapshot dump — one canonical struple map — with the struple
Python port and no loam code.

    from loam.dump import read
    d = read("snapshot.struple")
    d["vid"], d["root_hash"].hex(), len(d["bricks"])
    b = d["bricks"][0]; b["planes"]["surface"]   # array('f'), the 11³ block: 9³ samples plus one halo layer

Planes decode to ``array('f')`` (little-endian f32, exact); rings to a list
of (r, dz, tag, age) per slot.
"""

from __future__ import annotations

import os
import struct
import sys
from array import array

_HERE = os.path.dirname(os.path.abspath(__file__))
for cand in (os.environ.get("STRUPLE_PY"), os.path.join(_HERE, "..", "..", "..", "struple", "py")):
    if cand and os.path.isdir(cand) and cand not in sys.path:
        sys.path.insert(0, cand)

import struple  # noqa: E402

FORMAT = 2


def _plane(raw: bytes) -> array:
    a = array("f")
    a.frombytes(raw)
    if sys.byteorder != "little":
        a.byteswap()
    return a


def read(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    return decode(data)


def decode(data: bytes) -> dict:
    elems = struple.unpack(data)
    if len(elems) != 1 or not isinstance(elems[0], dict):
        raise ValueError("a loam dump is one struple map")
    m = elems[0]
    if m.get("fmt") != FORMAT:
        raise ValueError(f"dump format {m.get('fmt')} is not {FORMAT}")
    for b in m["bricks"]:
        b["planes"] = {name: _plane(raw) for name, raw in b["planes"].items()}
    for fr in m["fronts"]:
        ring = fr["ring"]
        fr["ring"] = [struct.unpack_from("<ffII", ring, i * 16) for i in range(len(ring) // 16)]
    return m
