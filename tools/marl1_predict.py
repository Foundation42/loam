#!/usr/bin/env python3
"""marl1_predict — MARL-1's gate numbers, computed BEFORE its runs.

`marl_predict.py`'s successor and the same discipline: a SECOND PROGRAM,
reimplementing only what it needs from `src/marl.zig`'s constants, so no
number a gate reads is the first result it saw. Where a prediction needs a
model rather than an identity, it builds one here in numpy — a synthetic
basis with the same overlap statistics as MARL-0's — and never looks at a
real run.

    python3 tools/marl1_predict.py
"""

import math
import numpy as np

CUTOFF = 32.0
CUTOFF_R = math.sqrt(CUTOFF)
COVERAGE = 0.35
R_COV = math.sqrt(-2 * math.log(COVERAGE))
TRUTH_RANGE = 1.25  # the target spans about −0.35 to 0.90


# ── experiment 1: what can deformation buy on a FROZEN topology? ──────
#
# With centres and shapes held, the model is LINEAR in its weights, so the
# best any weight-learner can do is the least-squares solution on that
# basis. Birth sets each weight ONCE, greedily — w = the residual at the
# exemplar, never revised — which is the first iterate of a Gauss-Seidel
# sweep and not the solution. So the floor for "what does deformation buy
# at identical capacity" is the greedy-to-least-squares ratio, and descent
# has the geometry as well, so it should beat it.
#
# The basis is synthetic and that is the point: it is built by MARL-0's own
# birth rule (accept a centre only where no existing kernel already reads
# above `coverage`) at MARL-0's own overlap ratio, so the Gram structure
# that decides this ratio is reproduced without any run being consulted.

def frozen_basis_ratio(sigma=0.06, seed=1, n_probe=6000):
    rs = np.random.default_rng(seed)

    def f(P):
        # A stand-in target with the same character: one broad smooth
        # component and one thin shell. Its exact form does not matter —
        # what is being predicted is a property of the BASIS.
        s = 0.35 * np.sin(2 * np.pi * (0.9 * P[:, 0] + 0.13)) \
                 * np.cos(2 * np.pi * (0.7 * P[:, 1] - 0.21)) \
                 * np.sin(2 * np.pi * (0.6 * P[:, 2] + 0.37))
        r = np.linalg.norm(P - np.array([0.30, 0.62, 0.46]), axis=1)
        t = (r - 0.20) / 0.025
        sh = np.where(t * t <= 16, 0.9 * np.exp(-np.minimum(t * t, 16)), 0.0)
        return s + sh

    # Birth, exactly as marl.zig does it: stream points, and seed a kernel
    # where nothing already reads above `coverage`, with the residual as
    # its weight.
    centres, weights = [], []
    stream = rs.random((60000, 3))
    for x in stream:
        if centres:
            C = np.array(centres)
            g = np.exp(-0.5 * np.sum((C - x) ** 2, axis=1) / sigma ** 2)
            g[np.sum((C - x) ** 2, axis=1) > CUTOFF * sigma ** 2] = 0.0
            pred = float(np.dot(np.array(weights), g))
            cover = float(g.max())
        else:
            pred, cover = 0.0, 0.0
        y = float(f(x[None, :])[0])
        if abs(y - pred) <= 0.02:
            continue
        if cover < COVERAGE:
            centres.append(x)
            weights.append(y - pred)
    C = np.array(centres)
    w_greedy = np.array(weights)

    P = rs.random((n_probe, 3))
    D2 = np.sum((P[:, None, :] - C[None, :, :]) ** 2, axis=2)
    PHI = np.where(D2 > CUTOFF * sigma ** 2, 0.0, np.exp(-0.5 * D2 / sigma ** 2))
    y = f(P)
    rms_greedy = float(np.sqrt(np.mean((PHI @ w_greedy - y) ** 2)))
    w_lsq, *_ = np.linalg.lstsq(PHI, y, rcond=None)
    rms_lsq = float(np.sqrt(np.mean((PHI @ w_lsq - y) ** 2)))
    overlap = float(np.mean(np.sum(PHI > 0, axis=1)))
    return len(centres), overlap, rms_greedy, rms_lsq


def main():
    print("MARL-1 — predictions, written before the runs")
    print("=" * 70)

    print("\n1. Capacity-controlled birth vs deformation")
    print("   Arm A births with no descent; arm B' takes A's frozen topology")
    print("   and descends with births off. Identical capacity by construction,")
    print("   so K_B'/K_A = 1 exactly and only the geometry and weights differ.")
    k, ov, rg, rl = frozen_basis_ratio()
    print(f"   synthetic basis: {k} kernels, {ov:.1f} overlapping any point")
    print(f"     greedy one-shot weights   RMS {rg:.5f}")
    print(f"     least-squares weights     RMS {rl:.5f}")
    print(f"     ratio                     {rg/rl:.2f}")
    print("   Weights alone are convex, so a descent that works must approach")
    print("   this. Descent also has the geometry, so it should beat it.")
    print(f"   → MARL1_DESCENT_GAIN = 2   (a FLOOR: half the {rg/rl:.1f} the basis")
    print("     offers on weights alone, since three Adam-free steps per event")
    print("     is not a least-squares solver and the geometry can also hurt)")

    print("\n2. Fixed coverage, variable target complexity")
    print("   Each shell is a separate surface needing its own tiling at the")
    print("   same coverage, so the kernels whose centres fall in the shell")
    print("   band should scale about linearly with the feature count, while")
    print("   the quiet slab stays empty at every complexity — it is")
    print("   unreachable by construction, and features are placed inside")
    print("   x ≤ 0.65 so that stays true.")
    print("   → MARL1_FEATURE_SCALING = 0.5 (shell kernels per feature must")
    print("     be at least half the one-feature count: linear with a factor")
    print("     of two of slack for shells that overlap each other)")
    print("   → the quiet slab holds ZERO at every complexity tested")

    print("\n3. Responsibility radius")
    print("   Kernels pack at one per ball of r_cov = %.4f widths, so the" % R_COV)
    print("   number inside a responsibility radius R is the volume ratio:")
    print(f"   {'R (widths)':>12} {'predicted touched':>18}")
    for R in (1.5, 2.0, 2.5, 3.0, 4.0, CUTOFF_R):
        print(f"   {R:>12.3f} {max(1.0, (R/R_COV)**3):>18.1f}")
    print("   → MARL1_TOUCHED_TOLERANCE = 3 (measured touched must sit within")
    print("     this factor of (R/r_cov)³ — the same packing argument that")
    print("     predicted 59.5 and measured 86, a factor of 1.4, so three is")
    print("     a bound with room and not a restatement of the result)")

    print("\n4. Under-birth divergence")
    print("   Christian's reading: too few kernels are forced to explain too")
    print("   much territory, weights become pathological, and the predictions")
    print("   then corrupt the coverage decision itself. So divergence should")
    print(f"   coincide with the mean |w| leaving the target's own range ({TRUTH_RANGE}).")
    print("   → MARL1_OVERRESPONSIBILITY = 1.25: every run whose held-out RMS")
    print("     ends above the empty model's must show mean |w| above this,")
    print("     and every run that converges must show mean |w| below it.")
    print("     A mechanism claim, and it fails if divergence is something else.")

    print("\n5. Deliberate saturation")
    print("   At the defaults the natural population is about 4 000 kernels in")
    print("   155 of 216 regions — roughly 26 per occupied region — and the")
    print("   budget of 64 is never reached. Saturation must therefore begin")
    print("   when the budget drops below that occupancy.")
    print("   → MARL1_SATURATION_BUDGET = 16: a budget of 16 must saturate")
    print("     (some region full, saturation events > 0) and a budget of 64")
    print("     must not. Between them is where the transition is, and where")
    print("     it sits is the measurement.")
    print()


if __name__ == "__main__":
    main()
