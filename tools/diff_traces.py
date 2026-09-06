#!/usr/bin/env python3
"""diff_traces — where two front-trajectory traces part company.

`loam-run --trace FILE` writes, after every step, one line per front:
step id alive dormant x y z dx dy dz s. Given two such files from the
same seed and scene, this reports per front id the first step at which
the positions differ by more than `tol`, the separation at the end,
and the largest separation; plus the front counts. The habit check:
a change of representation must not move a front, and if it did, the
first step that moved tells which read moved it.

Usage: diff_traces.py A B [--tol 0.01]
"""
import sys, math

def load(path):
    by = {}
    for line in open(path):
        f = line.split()
        if len(f) < 11: continue
        step, fid = int(f[0]), int(f[1])
        by.setdefault(fid, {})[step] = (int(f[2]), int(f[3]), float(f[4]), float(f[5]), float(f[6]), float(f[7]), float(f[8]), float(f[9]), float(f[10]))
    return by

def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    tol = 0.01
    if "--tol" in sys.argv: tol = float(sys.argv[sys.argv.index("--tol") + 1])
    ids = sorted(set(a) | set(b))
    last_a = max(s for f in a.values() for s in f); last_b = max(s for f in b.values() for s in f)
    print(f"fronts: A {len(a)}, B {len(b)}; steps A {last_a}, B {last_b}")
    for fid in ids:
        if fid not in a or fid not in b:
            src = a if fid in a else b
            born = min(src[fid])
            print(f"  front {fid}: only in {'A' if fid in a else 'B'} (born step {born})")
            continue
        fa, fb = a[fid], b[fid]
        steps = sorted(set(fa) & set(fb))
        first = None; worst = 0.0; end = 0.0
        for s in steps:
            pa, pb = fa[s], fb[s]
            d = math.dist(pa[2:5], pb[2:5])
            if d > tol and first is None: first = s
            worst = max(worst, d); end = d
        born_a, born_b = min(fa), min(fb)
        ends_a = max(s for s in fa if fa[s][0]); ends_b = max(s for s in fb if fb[s][0])
        print(f"  front {fid}: born A {born_a} / B {born_b}; alive to A {ends_a} / B {ends_b}; first divergence > {tol}: {first}; separation at end {end:.3f}, max {worst:.3f}")

if __name__ == "__main__":
    main()
