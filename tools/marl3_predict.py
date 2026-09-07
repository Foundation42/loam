#!/usr/bin/env python3
"""marl3_predict — MARL-3's gate numbers, before its runs.

MARL-3 changes ONE thing: the child's birth decision, from "insufficient
geometric coverage" to "persistent post-update residual". Everything else
is held — the MARL-2 parent, the pressure trigger, two levels, frozen-parent
delta semantics, the responsibility mechanism, the optimizer, the target.

So the predictions are about placement, and the first thing to establish is
what placement can even mean here: the CEILING a perfect allocator would
reach, which is not the same number at every sharpness and is what makes
"materially better" sayable.
"""

import math

SHELL_C, SHELL_R, SHELL_W = (0.30, 0.62, 0.46), 0.20, 0.025
CUTOFF_R = math.sqrt(32.0)
COVERAGE = 0.35
R_COV = math.sqrt(-2 * math.log(COVERAGE))
REGIONS, REFINE = 6, 2

# Measured in MARL-2, used here as a BASELINE and not as a threshold:
# refined regions, child kernel counts, concentration, retention.
MARL2 = {1.0: (42, 4594, 1.54, 1.12), 2.0: (38, 4339, 1.67, 1.32), 4.0: (34, 3760, 1.65, 1.38)}


def band_volume(sharpness, n=600_000, seed=4242):
    rs = seed
    def rnd():
        nonlocal rs
        rs = (rs * 6364136223846793005 + 1442695040888963407) % (1 << 64)
        return ((rs >> 40) & 0xFFFFFF) / 16777216.0
    w = SHELL_W / sharpness
    hit = 0
    for _ in range(n):
        p = (rnd(), rnd(), rnd())
        if abs(math.dist(p, SHELL_C) - SHELL_R) < 2 * w:
            hit += 1
    return hit / n


def main():
    print("MARL-3 — predictions, written before the runs")
    print("=" * 70)
    region_vol = 1.0 / REGIONS ** 3

    print("\n0. What a perfect allocator would score")
    print("   Concentration is the child's band density over its density across")
    print("   the regions it occupies. If EVERY child kernel landed in the band,")
    print("   the ratio would be the refined volume over the band volume inside")
    print("   it — a ceiling that RISES with sharpness, because a thinner ridge")
    print("   is a smaller share of the region that contains it.")
    print(f"   {'sharpness':>10} {'band vol':>10} {'refined vol':>12} {'ceiling':>9} {'MARL-2':>8} {'of ceiling':>11}")
    ceilings = {}
    for sh, (nref, _k, conc, _r) in MARL2.items():
        bv = band_volume(sh)
        rv = nref * region_vol
        ceiling = rv / bv
        ceilings[sh] = ceiling
        print(f"   {sh:>10.0f} {bv:>10.5f} {rv:>12.5f} {ceiling:>9.2f} {conc:>8.2f} {100*conc/ceiling:>10.0f}%")
    print("   MARL-2 sits at 41%, 25%, 14% of perfect and FALLS as the target")
    print("   sharpens — the signature of an allocator that fills regions rather")
    print("   than structure.")

    print("\n1. Concentration must reach the number MARL-2 was refuted against")
    print("   `MARL2_CONCENTRATION` = 3 stands unstruck. At sharpness ×2 that is")
    print(f"   {100*3/ceilings[2.0]:.0f}% of a perfect allocator, which is a real ask and a")
    print("   reachable one. Reused as MARL-3's target rather than a new number:")
    print("   the prediction was not wrong about what good placement looks like,")
    print("   it was wrong about which allocator would deliver it.")
    print("   → MARL3_CONCENTRATION = 3, at sharpness ×2")

    print("\n2. …and it must respond in the right DIRECTION")
    print("   The ceiling rises with sharpness (%.1f → %.1f → %.1f). An allocator"
          % (ceilings[1.0], ceilings[2.0], ceilings[4.0]))
    print("   following structure should rise with it; MARL-2's went 1.54 → 1.67")
    print("   → 1.65, flat. This is the crisper of the two claims because it")
    print("   cannot be met by simply birthing more kernels everywhere.")
    print(f"   → MARL3_CONCENTRATION_SLOPE = 1.5: concentration at ×4 over ×1.")
    print(f"     A perfect allocator would score {ceilings[4.0]/ceilings[1.0]:.2f}; half of that, floored.")

    print("\n3. Placement, not growth")
    print("   A concentration win could be manufactured by birthing far more")
    print("   kernels and letting the band's share rise with them. So the child's")
    print("   population is capped at what MARL-2 already spent:")
    for sh, (_n, k, _c, _r) in MARL2.items():
        print(f"     sharpness ×{sh:.0f}: MARL-2 child kernels {k}")
    print("   → MARL3_CAPACITY_CAP = 1.0 — no more child kernels than MARL-2")
    print("     used at the same sharpness. Better placement, not more of it.")

    print("\n4. And the numbers MARL-2 already holds must not regress")
    print("   MARL2_CHILD_QUIET = 0, MARL2_PRECISION = 0.75 (the trigger is")
    print("   unchanged, so this is a control), MARL2_WORK_RATIO = 1.5,")
    print("   MARL1_OVERRESPONSIBILITY = 1.25 on both levels, and")
    print("   MARL2_SHARPNESS_RETENTION = 1.5 — also reused unstruck, and also")
    print("   the ask that MARL-2's allocator could not meet (1.12 / 1.32 / 1.38).")

    print("\n5. Measured, NOT gated (Christian: establish what it does first)")
    print("   `useful_child_fraction` — child kernels that have received enough")
    print("   gradient evidence to have been adapted at all — and the mean")
    print("   updates per child kernel. MARL-2's refine sweep showed allocated")
    print("   and usable capacity are different things: at ×6 the child held")
    print("   11 895 kernels on 208k updates, 17 apiece, and scored below ×2's")
    print("   3 927 on 1.37M, 349 apiece. No threshold; the record comes first.")
    print()


if __name__ == "__main__":
    main()
