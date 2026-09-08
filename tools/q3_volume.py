#!/usr/bin/env python3
"""q3_volume — a Quake 3 level as a `bark.Volume` of signed distance.

MARL-13 through MARL-16 measured an occlusion cache against a GROVE: 27
spheres on a jittered lattice, which has open sky, corridors and crevices
but no rooms, no doorways and no scale separation. A real level has all
three, and it is the shape the "sparse in the domain" question was really
asking about — a deathmatch map is a thin shell of playable space inside a
mostly-solid bounding box.

Reads the BSP through `~/dev/tessera`'s loader (Christian's, and already
mirrored field-for-field against `~/dev/importers/src/q3bsp.zig`), rather
than writing a third parser.

## Why brushes and not the triangle soup

Q3's collision geometry is BRUSHES: convex intersections of half-spaces.
For a convex brush the signed distance to its boundary is exactly
`−max_i(nᵢ·p − dᵢ)` — one line, no BVH, no winding rules, and positive
inside, which is the convention `src/cache.zig` measured the carrier to
have. The render faces would give a triangle soup that is not closed
(sky, decals, non-solid detail) and would need a robust inside test that
brushes make unnecessary.

## The cube, and the void

`bark.Volume` is cubic with one extent. A level is wide and flat, so a cube
over its largest dimension wastes the rest — which is fine and is in fact
the point: the waste IS the sparsity being measured. And a Q3 map is
SEALED, so within the bounds every point is either playable space or solid
rock; there is no third thing for the wasted corners to be.

    python3 tools/q3_volume.py --res 160 --out out/oa_spirit3.vol
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, "/home/chrisbe/dev/tessera/src")

import numpy as np
from tessera import bsp
from tessera.vfs import Pk3Vfs

PK3 = Path("/home/chrisbe/dev/importers/test_files/q3/pk3")
CONTENTS_SOLID = 1
# The carrier saturates at ±3 CELLS of the brick's gauge, and that is the
# convention here too — an absolute ±3 would be sub-voxel on a level where
# a voxel is twenty-odd Q3 units, and the band would not exist.
CLAMP_CELLS = 3.0


def solid_brushes(b) -> list[np.ndarray]:
    """Every world brush with CONTENTS_SOLID, as an (n, 4) plane array.

    Rows are (nx, ny, nz, d) with the half-space being `n·p ≤ d`, which is
    the sense Q3 stores and the sense that makes a brush the INTERSECTION
    of its sides.
    """
    world = b.models[0]
    first, count = int(world["first_brush"]), int(world["num_brushes"])
    flags = b.shaders["content_flags"]
    out = []
    for i in range(first, first + count):
        br = b.brushes[i]
        if not (int(flags[int(br["shader"])]) & CONTENTS_SOLID):
            continue
        fs, ns = int(br["first_side"]), int(br["num_sides"])
        if ns < 4:
            continue
        pl = b.brush_sides["plane"][fs : fs + ns]
        planes = np.empty((ns, 4), np.float64)
        planes[:, :3] = b.planes["normal"][pl]
        planes[:, 3] = b.planes["dist"][pl]
        out.append(planes)
    return out


def bbox_of(planes: np.ndarray, lo: np.ndarray, hi: np.ndarray):
    """A conservative box for a brush, from whichever sides are axis-aligned.

    Most Q3 brushes are boxes and give all six; a bevelled or angled one
    gives fewer, and the missing axes fall back to the world bounds. Being
    conservative is the only requirement — the half-space test inside the
    box is what decides, and a box that is too large only costs time.
    """
    blo, bhi = lo.copy(), hi.copy()
    for a in range(3):
        for row in planes:
            n, d = row[:3], row[3]
            if n[a] > 0.999 and abs(n[(a + 1) % 3]) < 1e-3 and abs(n[(a + 2) % 3]) < 1e-3:
                bhi[a] = min(bhi[a], d)
            elif n[a] < -0.999 and abs(n[(a + 1) % 3]) < 1e-3 and abs(n[(a + 2) % 3]) < 1e-3:
                blo[a] = max(blo[a], -d)
    return blo, bhi


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="maps/oa_spirit3.bsp")
    ap.add_argument("--res", type=int, default=160)
    ap.add_argument("--out", default="out/oa_spirit3.vol")
    ap.add_argument("--inflate", type=float, default=0.5,
                    help="grow every brush by this many cells (conservative "
                         "rasterisation: a wall thinner than a voxel is a "
                         "wall rays pass through)")
    ap.add_argument("--band", type=int, default=4, help="outward distance passes")
    a = ap.parse_args()

    v = Pk3Vfs(PK3)
    b = bsp.load(v, a.map)
    brushes = solid_brushes(b)
    world = b.models[0]
    lo = np.array(world["mins"], np.float64)
    hi = np.array(world["maxs"], np.float64)
    span = hi - lo
    extent = float(span.max())
    # A cube over the largest dimension, centred on the level.
    mid = (lo + hi) * 0.5
    lo = mid - extent * 0.5
    print(f"{a.map}: {len(brushes)} solid brushes of {len(b.brushes)}")
    print(f"  bounds {span[0]:.0f} x {span[1]:.0f} x {span[2]:.0f} Q3 units")
    print(f"  cube   {extent:.0f} at {a.res}³ = {extent / a.res:.1f} units a voxel")

    res = a.res
    cell = extent / res
    clamp = CLAMP_CELLS * cell
    # Q3 walls are eight to sixteen units and a voxel here is twenty-odd, so
    # a centre-sampled rasterisation drops most of them and the level LEAKS
    # — rays escape through walls and the occlusion being cached is not the
    # level's. Growing every brush by half a cell is conservative
    # rasterisation: no wall the grid could represent is missed, at the cost
    # of thickening the thinnest ones to about one voxel. That is the right
    # trade here, and it is stated rather than hidden: a level the grid
    # cannot seal has no occlusion to study.
    grow = a.inflate * cell
    axes = [lo[i] + (np.arange(res) + 0.5) * cell for i in range(3)]

    # φ, positive inside. Start everywhere "far outside" and raise it
    # brush by brush: a point in two brushes takes the deeper of the two,
    # which is the union's own distance.
    phi = np.full((res, res, res), -clamp, np.float32)
    for planes in brushes:
        blo, bhi = bbox_of(planes, lo, lo + extent)
        i0 = [max(0, int(np.floor((blo[k] - lo[k]) / cell)) - 1) for k in range(3)]
        i1 = [min(res, int(np.ceil((bhi[k] - lo[k]) / cell)) + 2) for k in range(3)]
        if any(i1[k] <= i0[k] for k in range(3)):
            continue
        gx = axes[0][i0[0] : i1[0]]
        gy = axes[1][i0[1] : i1[1]]
        gz = axes[2][i0[2] : i1[2]]
        # −max over sides of (n·p − d): positive inside a convex brush,
        # and exactly the distance to its nearest face.
        worst = np.full((gx.size, gy.size, gz.size), -np.inf, np.float32)
        for row in planes:
            n, d = row[:3], row[3]
            s = (n[0] * gx)[:, None, None] + (n[1] * gy)[None, :, None] + (n[2] * gz)[None, None, :] - d
            np.maximum(worst, s.astype(np.float32), out=worst)
        sub = phi[i0[0] : i1[0], i0[1] : i1[1], i0[2] : i1[2]]
        np.maximum(sub, np.clip(grow - worst, -clamp, clamp), out=sub)

    inside = float((phi > 0).mean())
    box = float(np.prod(span) / extent ** 3)
    print(f"  solid  {inside:.4f} of the cube, {inside / box:.4f} of the level's own box (grown {a.inflate} cell)")

    # A narrow band outside, by propagating the inside distance outward one
    # cell a pass. Not an exact distance transform and it does not need to
    # be: the marcher tests φ > 0, and the band exists so that trilinear
    # interpolation puts the boundary in a sensible place rather than
    # halfway between +3 and −3.
    for _ in range(a.band):
        m = phi.copy()
        for ax in range(3):
            sl_a = [slice(None)] * 3
            sl_b = [slice(None)] * 3
            sl_a[ax] = slice(1, None)
            sl_b[ax] = slice(None, -1)
            np.maximum(m[tuple(sl_a)], phi[tuple(sl_b)] - cell, out=m[tuple(sl_a)])
            np.maximum(m[tuple(sl_b)], phi[tuple(sl_a)] - cell, out=m[tuple(sl_b)])
        phi = np.clip(m, -clamp, clamp)

    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as f:
        # "QVOL", res, extent, then res³ little-endian f32 in x-fastest
        # order, which is `bark.Volume.index`'s.
        f.write(b"QVOL")
        f.write(struct.pack("<If", res, extent))
        f.write(np.ascontiguousarray(phi.transpose(2, 1, 0), np.float32).tobytes())
    print(f"  wrote  {out} ({out.stat().st_size / 1e6:.1f} MB), φ {phi.min():.2f}..{phi.max():.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
