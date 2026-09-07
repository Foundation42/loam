#!/usr/bin/env python3
"""marl5_predict — MARL-5's gate numbers, before its runs.

MARL-4 left one tension: concentration and evidence sufficiency compete for
a fixed learning budget. MARL-5 asks whether a scheduler can spend that
budget better than a static residual bias, under three arms at THE SAME
ROUTED COUNT — so no arm can win by processing more.

    A  uniform routing at duty D
    B  static residual-biased routing, normalised to duty D
    C  adaptive scheduled routing, normalised to duty D

Christian's restraints shape what is gated: not maximal concentration
(MARL-4 showed chasing the ceiling is actively bad), but a PARETO
improvement under equal work. And the sufficiency term is a control, not a
target — if residual-only scheduling does as well, the evidence-per-kernel
observation was diagnostic and the scheduler does not need it.
"""

MARL4 = {  # measured, sharpness ×4, 200 000 exemplars — baselines, not thresholds
    "uniform  (1/0)":   (0.04423, 3760, 461, 1.65, 1.00),
    "static  (0.05/6)": (0.04477, 2736, 305, 2.13, 0.78),
    "static  (0.02/3)": (0.05082, 2135, 217, 2.50, 0.62),
}


def main():
    print("MARL-5 — predictions, written before the runs")
    print("=" * 70)
    print("\n0. What MARL-4 left on the table")
    print(f"   {'arm':<20} {'RMS':>9} {'kernels':>8} {'upd/k':>7} {'concen':>7} {'duty':>6}")
    for k, (rms, n, u, c, d) in MARL4.items():
        print(f"   {k:<20} {rms:>9.5f} {n:>8} {u:>7} {c:>7.2f} {d:>6.2f}")
    print("   The efficient regime is broad: 0.05/6 buys +29% concentration for")
    print("   +1.2% RMS, and 0.02/3 buys the next +17% for another +13%. So the")
    print("   scheduler's job is not selectivity — it is keeping every active")
    print("   region resolved enough for the budget there is.")

    print("\n1. The success criterion is a PARETO improvement, not a maximum")
    print("   → MARL5_RMS_EDGE = 1.05: at the same routed count, the adaptive")
    print("     arm's RMS must beat the best static arm's by this factor.")
    print("     Derived from what counts as an effect here: MARL-4's whole")
    print("     efficient regime spans 1.2% of RMS between 1/0 and 0.05/6, so")
    print("     5% is several times the difference a static setting can make")
    print("     and cannot be reached by drifting along that frontier.")
    print("   → MARL5_CONCENTRATION_EDGE = 1.2 over the uniform arm, so a")
    print("     scheduler cannot win the RMS gate by quietly becoming uniform.")
    print("     Both must hold; either alone is a degenerate solution.")

    print("\n2. The largest residual is NOT the best schedule")
    print("   Christian's prediction, and the one worth being wrong about: a")
    print("   scheduler should avoid both tails — repeatedly servicing")
    print("   already-well-trained high-residual regions, and starving newly")
    print("   created representation. If that is right, adding the")
    print("   anti-starvation term must beat need alone.")
    print("   → MARL5_LAG_HELPS = 1.02: RMS(need) / RMS(need × lag) at the same")
    print("     routed count. A small margin deliberately — this is a")
    print("     DIRECTION claim, and demanding a large one would make a true")
    print("     but modest effect read as a refutation.")

    print("\n3. The sufficiency term is a CONTROL, not a target")
    print("   Reported and NOT gated, at Christian's instruction: if")
    print("   need × lag and need × lag ÷ sufficiency perform alike, then")
    print("   evidence-per-kernel was diagnostic and the scheduler does not")
    print("   need it explicitly. That is a finding either way and it must not")
    print("   be pre-committed to.")

    print("\n4. Learning efficiency: measured first, scheduled from never")
    print("   Δ(regional unresolved residual) per unit of learning work, over a")
    print("   moving window. Reported as a distribution and correlated against")
    print("   need. It may eventually separate 'high residual, learning well —")
    print("   send more' from 'high residual, learning badly — the")
    print("   representation may be wrong', but MARL-5 does not need to solve")
    print("   that and must not schedule from it.")

    print("\n5. And everything the campaign already holds must not regress")
    print("   MARL1_OVERRESPONSIBILITY on both levels; MARL4_TRAINED_FLOOR;")
    print("   MARL2_CHILD_QUIET = 0; MARL2_PRECISION — the refinement trigger")
    print("   is untouched, so that one is a control.")
    print()


if __name__ == "__main__":
    main()
