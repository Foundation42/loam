#!/usr/bin/env python3
"""marl4_predict — MARL-4's gate numbers, before its runs.

MARL-3 established that placement is upstream of birth: capacity can only
concentrate where the learning stream concentrates, and the child's stream
was uniform over the refined region. MARL-4 changes the STREAM, and only
the stream — routing becomes probabilistic,

    p(route) = min(1, floor + gain · |y − parent(x)|)

with `floor` protecting the trainability the coverage rule was silently
providing and `gain` concentrating evidence on unresolved structure.

Christian's framing sets what is gated: not "does RMS improve" but whether
kernel concentration TRACKS the biased stream, and whether the stream
itself tracks residual structure without entering the over-responsibility
regime.
"""

import math

# Measured, used as baselines and not as thresholds.
# (band volume share, stream band share, kernel band share, concentration)
UNIFORM = {1.0: (0.2205, 0.2298, 0.3129, 1.54),
           2.0: (0.1456, 0.1556, 0.2574, 1.67),
           4.0: (0.0801, 0.0933, 0.1497, 1.65)}
PROBE_X4 = (0.0801, 0.2195, 0.2189, 2.11)   # hard filter at |r| > 0.05


def main():
    print("MARL-4 — predictions, written before the runs")
    print("=" * 70)

    print("\n0. What MARL-3 measured, which is what these are derived from")
    print(f"   {'sharpness':>10} {'band vol':>9} {'stream':>8} {'kernels':>8} {'k/stream':>9}")
    for sh, (bv, st, kn, _c) in UNIFORM.items():
        print(f"   {sh:>10.0f} {bv:>9.4f} {st:>8.4f} {kn:>8.4f} {kn/st:>9.2f}")
    bv, st, kn, c = PROBE_X4
    print(f"   {'×4 probe':>10} {bv:>9.4f} {st:>8.4f} {kn:>8.4f} {kn/st:>9.2f}   (hard filter)")
    print("   The birth rule adds 1.36 to 1.61 over a uniform stream and 1.00")
    print("   over a concentrated one. So kernels track the stream, with a")
    print("   bounded local gain that shrinks as the stream does the work.")

    print("\n1. Kernel concentration must TRACK the stream")
    print("   → MARL4_TRACKING_LO = 0.8, MARL4_TRACKING_HI = 1.7")
    print("     the child's band share over the stream's, at every routing")
    print("     setting. MARL-3 spans 1.00 to 1.61 across the two extremes it")
    print("     measured; the band is that with a little room either side. A")
    print("     ratio outside it means placement has stopped following its")
    print("     input, which would falsify the whole diagnosis.")

    print("\n2. The stream must track residual structure AS THE TARGET SHARPENS")
    print("   Sharper structure localises the residual, so a residual-biased")
    print("   router should concentrate MORE at ×4 than at ×1. Under uniform")
    print("   routing the stream concentration is flat:")
    for sh, (bv, st, _k, _c) in UNIFORM.items():
        print(f"     ×{sh:.0f}: stream {st:.4f} / band {bv:.4f} = {st/bv:.2f}")
    print("   → MARL4_STREAM_SLOPE = 1.3: stream concentration at ×4 over ×1.")
    lo, hi = UNIFORM[1.0], UNIFORM[4.0]
    base = (hi[1]/hi[0]) / (lo[1]/lo[0])
    print(f"     Uniform routing already scores {base:.2f} on this ratio — the residual")
    print("     leans on the band a little even without help — so the ask is")
    print("     that a router beat it by a clear margin, not merely exceed 1.")

    print("\n3. …without entering the over-responsibility regime")
    print("   MARL-3's residual-only birth collapsed to 6% to 24% of kernels")
    print("   trained and mean |w| of 13 to 17. A floor that is doing its job")
    print("   keeps the child where MARL-2 was (0.99 trained, |w| 0.15).")
    print("   → MARL4_TRAINED_FLOOR = 0.8 of child kernels with ≥ 10 updates,")
    print("     and MARL1_OVERRESPONSIBILITY = 1.25 on both levels, unchanged.")

    print("\n4. And it must beat the crude probe it replaces")
    print(f"   A hard filter at |r| > 0.05 reached concentration {c:.2f} at ×4 while")
    print("   starving low-residual regions entirely. A graded bias with a")
    print("   protected floor should do better on placement AND on health.")
    print("   → MARL4_CONCENTRATION = 2.5 at sharpness ×4, against MARL-2's")
    print(f"     1.65 and the probe's {c:.2f}. The ceiling is 11.01, so this is")
    print("     23% of perfect — an ask, not a formality, and well short of")
    print("     claiming the problem solved.")
    print("   → MARL2_WORK_RATIO = 1.5 still holds: routing less can only")
    print("     reduce work, so this is a control rather than a target.")
    print()


if __name__ == "__main__":
    main()
