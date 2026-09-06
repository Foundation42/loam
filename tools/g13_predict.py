#!/usr/bin/env python3
"""G13's PREDICTION — written before the sweep runs, so the threshold is
struck against theory and the instrument is checked against something
other than itself (the G3 lesson, Claude Chat 2026-09-06).

A straight capsule of radius r is sampled on a lattice of spacing h and
reconstructed by the uniform cubic B-spline with the SAMPLES AS CONTROL
VALUES (Schoenberg's variation-diminishing spline — no prefilter, R7).
That reconstruction is a smoothing: S ≈ φ + (h²/6)∇²φ + …, and for a
tube ∇²φ = 1/ρ, so the zero set sits at

    ρ ≈ r − h²/(6r)        bias ≈ −(1/6)(h/r)²   (second order)

and vanishes altogether where the smoothing lifts the axis above zero,
near r ≈ 0.7h. The numbers below are the full sum, not the expansion,
worst case over axis offsets in the cell and three orientations. They
are a prediction: `zig build test -Dtest-filter=G13` measures the Zig
reconstruction against the same capsules and must read the same curve.

Usage: python3 tools/g13_predict.py [--trilinear] [--shift 0.5] [--gauge 2]
  --trilinear   the instrument's variation record (a different curve)
  --shift S     the plausible bug: control values a fraction S of a cell off
  --gauge G     the coarsening: h → G·h without refinement (r/h scales by 1/G)
"""
import sys, argparse
import numpy as np

def bspline3(t):
    a = np.abs(t)
    out = np.zeros_like(a)
    m1 = a < 1
    m2 = (a >= 1) & (a < 2)
    out[m1] = 2/3 - a[m1]**2 + a[m1]**3/2
    out[m2] = (2 - a[m2])**3/6
    return out

def tri(t):
    a = np.abs(t)
    return np.where(a < 1, 1 - a, 0.0)

def make_axis(kind):
    if kind == "axis":     d = np.array([0, 0, 1.0])
    elif kind == "face":   d = np.array([1, 1, 0.0]) / np.sqrt(2)
    elif kind == "body":   d = np.array([1, 1, 1.0]) / np.sqrt(3)
    e1 = np.cross(d, [1, 0, 0]) if abs(d[0]) < 0.9 else np.cross(d, [0, 1, 0])
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(d, e1)
    return d, e1, e2

def reconstruct(pts, phi, kernel, shift):
    """S(x) = Σ c_ijk K(x−i)K(y−j)K(z−k), c = φ sampled at the lattice
    (shifted by `shift` cells along every axis when mutating)."""
    base = np.floor(pts).astype(int) - 1
    S = np.zeros(len(pts))
    for di in range(4):
        for dj in range(4):
            for dk in range(4):
                ijk = base + np.array([di, dj, dk])
                w = kernel(pts[:, 0] - ijk[:, 0]) * kernel(pts[:, 1] - ijk[:, 1]) * kernel(pts[:, 2] - ijk[:, 2])
                S += w * phi(ijk.astype(float) + shift)
    return S

def sweep(radii, kernel, shift, gauge, n_theta=24, n_axial=8, verbose=True):
    rows = []
    for r in radii:
        r_eff = r / gauge  # a coarser gauge sees a thinner tube, in cells
        worst_axis = -np.inf; rec_min = np.inf; rec_max = -np.inf; rec_sum = 0; rec_n = 0
        for kind in ("axis", "face", "body"):
            d, e1, e2 = make_axis(kind)
            for ou in (0.0, 0.25, 0.5):
                for ov in (0.0, 0.25, 0.5):
                    p0 = ou * e1 + ov * e2 + 8.0  # well inside the lattice
                    def phi(x):
                        q = x - p0
                        along = q @ d
                        perp = q - np.outer(along, d)
                        return np.linalg.norm(perp, axis=1) - r_eff
                    # on the axis: does the zero set survive?
                    s = np.linspace(0, 4, n_axial, endpoint=False)
                    axis_pts = p0 + np.outer(s, d)
                    worst_axis = max(worst_axis, reconstruct(axis_pts, phi, kernel, shift).max())
                    # perpendicular rays: where is the zero?
                    t = np.linspace(0.0, r_eff + 2.5, 400)
                    for sa in s[::2]:
                        for th in np.linspace(0, 2 * np.pi, n_theta, endpoint=False):
                            ray = p0 + sa * d + np.outer(t, np.cos(th) * e1 + np.sin(th) * e2)
                            S = reconstruct(ray, phi, kernel, shift)
                            cross = np.where((S[:-1] < 0) & (S[1:] >= 0))[0]
                            if len(cross) == 0:
                                continue
                            i = cross[0]
                            t0 = t[i] + (t[i + 1] - t[i]) * (-S[i]) / (S[i + 1] - S[i])
                            rec_min = min(rec_min, t0); rec_max = max(rec_max, t0); rec_sum += t0; rec_n += 1
        survives = worst_axis < 0
        mean = rec_sum / rec_n if rec_n else float("nan")
        rows.append((r, survives, worst_axis, rec_min, mean, rec_max, r_eff))
        if verbose:
            if survives:
                print(f"r/h {r:5.2f}  survives  axis max {worst_axis:+.4f}  r_rec min/mean/max {rec_min:.3f}/{mean:.3f}/{rec_max:.3f}"
                      f"  bias min/mean/max {100*(rec_min/r_eff-1):+.1f}%/{100*(mean/r_eff-1):+.1f}%/{100*(rec_max/r_eff-1):+.1f}%"
                      f"  second-order {-100/6*(1/r_eff)**2:+.1f}%")
            else:
                print(f"r/h {r:5.2f}  VANISHES  axis max {worst_axis:+.4f}")
    return rows

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--trilinear", action="store_true")
    ap.add_argument("--shift", type=float, default=0.0)
    ap.add_argument("--gauge", type=float, default=1.0)
    ap.add_argument("--radii", type=str, default="", help="comma list of r/h; default is the fine curve")
    ap.add_argument("--zig", action="store_true", help="print the table thresholds.zig freezes")
    args = ap.parse_args()
    kernel = tri if args.trilinear else bspline3
    radii = [float(x) for x in args.radii.split(",")] if args.radii else [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0, 6.0, 8.0]
    print(f"kernel {'trilinear' if args.trilinear else 'cubic B-spline (samples as control values)'}, shift {args.shift}, gauge {args.gauge}")
    rows = sweep(radii, kernel, args.shift, args.gauge, verbose=not args.zig)
    if args.zig:
        print("// r/h, survives, r_rec/r worst (min), r_rec/r best (max) — tools/g13_predict.py --zig")
        for r, ok, ax, lo, mean, hi, r_eff in rows:
            if ok:
                print(f"    .{{ .r_over_h = {r:.2f}, .survives = true, .rec_min = {lo/r_eff:.4f}, .rec_max = {hi/r_eff:.4f} }},")
            else:
                print(f"    .{{ .r_over_h = {r:.2f}, .survives = false, .rec_min = 0, .rec_max = 0 }},")
