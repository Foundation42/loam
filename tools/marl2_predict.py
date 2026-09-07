#!/usr/bin/env python3
"""marl2_predict — MARL-2's gate numbers, written before its runs.

The third in the series, same discipline. What is different here is what is
being predicted: Christian's instruction is to pre-register around WHERE the
extra capacity appears, not merely whether the total error improves —
"otherwise an unconditional second layer could pass while missing the point."
So the load-bearing predictions are about placement and concentration, and
the RMS gate is the weakest of them.
"""

import math

SHELL_C = (0.30, 0.62, 0.46)
SHELL_R, SHELL_W = 0.20, 0.025
WINDOW_HI, QUIET_X = 0.70, 0.90
CUTOFF_R = math.sqrt(32.0)
COVERAGE = 0.35
R_COV = math.sqrt(-2 * math.log(COVERAGE))


def in_shell(p, sharpness=1.0):
    w = SHELL_W / sharpness
    return abs(math.dist(p, SHELL_C) - SHELL_R) < 2 * w


def region_meets_shell(c, regions, sharpness=1.0, N=9):
    h = 1.0 / regions
    for k in range(N + 1):
        for j in range(N + 1):
            for i in range(N + 1):
                p = ((c[0] + i / N) * h, (c[1] + j / N) * h, (c[2] + k / N) * h)
                if in_shell(p, sharpness):
                    return True
    return False


def main():
    print("MARL-2 — predictions, written before the runs")
    print("=" * 70)
    R = 6
    meets = [c for c in
             ((i, j, k) for k in range(R) for j in range(R) for i in range(R))
             if region_meets_shell(c, R)]
    frac = len(meets) / R ** 3
    print(f"\n0. The ground truth a refinement decision is scored against")
    print(f"   Of {R**3} parent regions, {len(meets)} touch the shell band ({100*frac:.1f}%).")
    print(f"   Their combined volume is {frac:.4f} of the domain, which is also the")
    print(f"   share of exemplars a perfectly precise refiner would route to a child.")

    print("\n1. The child holds NOTHING in the quiet slab")
    print("   Absolute, and derivable rather than hoped: the truth is exactly")
    print("   zero past x = %.2f, no parent kernel born on structure reaches it," % QUIET_X)
    print("   so the parent's post-update residual there is zero, so no covered")
    print("   event can ever raise a region's pressure above any positive")
    print("   threshold, so no region there is ever refined, so the child never")
    print("   receives an exemplar there and births nothing.")
    print("   → MARL2_CHILD_QUIET = 0 kernels. No slack; a single kernel there")
    print("     means the chain above is broken somewhere and the gate should say so.")

    print("\n2. Refinement fires where the parent CANNOT represent, not merely")
    print("   where it is wrong")
    print("   The swell varies on a scale of about 0.3 — 1.8 region edges — and")
    print(f"   the parent tiles it with kernels of σ_max = {1/R/CUTOFF_R:.5f} at a coverage")
    print(f"   spacing of {R_COV/R/CUTOFF_R:.5f}, which is {0.3/(R_COV/R/CUTOFF_R):.0f} kernels per wavelength.")
    print("   Ample. The ridge is thinner than a single kernel and cannot be.")
    print("   So pressure should fire on shell regions and almost nowhere else.")
    print("   → MARL2_PRECISION = 0.75 of refined regions must touch the band.")
    print("     A floor, not an estimate: some ridge-adjacent region will be")
    print("     pressured by the ridge's tail without the band reaching into it.")

    print("\n3. WHERE the capacity appears — the one that matters")
    print("   MARL-1's finding was that the parent's capacity is geometric: it")
    print("   tiles structure, with a shell-band concentration of about 1.66")
    print("   (8402 per unit³ in the band against roughly 5067 over the volume")
    print("   it occupies at all). If refinement is adaptive REPRESENTATION and")
    print("   not merely a second helping of the same rule, the child must be")
    print("   far more concentrated than that — it is only ever handed")
    print("   exemplars in pressured regions.")
    print("   → MARL2_CONCENTRATION = 3: the child's shell-band density over")
    print("     its density across the regions it occupies, at least double the")
    print("     parent's 1.66. This is the gate that an unconditional second")
    print("     layer fails, and it is the point of the experiment.")

    print("\n4. The sharpness sweep — the killer comparison")
    print("   Flat MARL-1, measured: gain 6.19 at sharpness ×1, 2.62 at ×2,")
    print("   1.80 at ×4. Capacity density did not move; accuracy fell.")
    print(f"   The child's grid is twice as fine, so its σ_max is {1/(2*R)/CUTOFF_R:.5f} and")
    print(f"   its coverage spacing on the ridge is {R_COV/(2*R)/CUTOFF_R:.5f} — HALF the")
    print("   parent's, so four times the kernels per unit of ridge area. A")
    print("   fourfold capacity increase on the component carrying most of the")
    print("   residual should buy well over half as much again overall.")
    print("   → MARL2_SHARPNESS_RETENTION = 1.5: at sharpness ×2 the hierarchy's")
    print("     gain must be at least this multiple of flat MARL's at the same")
    print("     sharpness, same seed, same exemplars.")

    print("\n5. What it may cost")
    print(f"   Only {100*frac:.1f}% of exemplars land in shell-touching regions, and only")
    print("   those reach the child at all. The parent stops learning there, so")
    print("   the child's work partly REPLACES the parent's rather than adding")
    print("   to it.")
    print("   → MARL2_WORK_RATIO = 1.5: total gradient applications, hierarchy")
    print("     over flat, at the same exemplar count.")
    print("   → and MARL1_OVERRESPONSIBILITY still holds on both levels: mean |w|")
    print("     below 1.25, or refinement has traded one pathology for another.")
    print()


if __name__ == "__main__":
    main()
