#!/usr/bin/env python3
"""marl25_predict — MARL-25's gate numbers, before its run.

Christian, after MARL-24: "so what, it works now? ... we should try it on
some of our previous stuff maybe."

The right instinct, and there is a sharper version of it than re-running old
arms. MARL-24 found a residual layer with EVERY kernel pinned at sigma_max
and fixed it by lowering `regions`. What made that findable was not the
residual layer — it was the DIAGNOSTIC:

    the fraction of a population sitting within 1% of sigma_max

sigma_max = h/sqrt(CUTOFF) with h = 1/regions, and it exists to keep the
27-region gather exact. A population hard against it is a population the
geometry descent wanted WIDER and could not have — which means `regions` is
finer than the target needs, and every one of those kernels is capacity
spent on resolution nobody asked for.

**That number can be read off any model this campaign has ever built.** And
one of them is already on the record without anyone noticing: G37 (c)
printed the static occlusion bake's mean sigma as 0.0278 against a sigma_max
of 0.02946 — 94% of the way to the stop, on the arm that MARL-13 through
MARL-21 all used.

## Why the answer might still be "no, leave it alone"

MARL-14 already swept `regions` on the static bake and got a TRADE, not a
free win: 6 -> 3 gave 4.32x fewer kernels for 1.23x the error. So a pinned
population is NOT automatically over-fine — a model can be pressed against
the clamp and still be using every kernel it has.

What changed since is MARL-22. The query set MARL-14 swept on was the
STRADDLING shell, a third of which is inside solid where AO is exactly 0 —
a STEP, and the finest structure in the whole target. Delete it, as MARL-22
showed a renderer already does, and the sharpest thing the basis was being
asked to resolve goes with it.

So the prediction is not "coarser is better" but something narrower and
falsifiable: **coarsening should be much cheaper on the exterior shell than
MARL-14 measured on the straddling one, because the step is what was paying
for the fine grid.**
"""

MARL14_COARSE_K = 4.32     # kernels saved, regions 6 -> 3, straddling shell
MARL14_COARSE_RMS = 1.23   # what it cost


def main():
    print("MARL-25 — predictions, written before the run")
    print("=" * 72)

    print("\n1. THE DIAGNOSTIC, and whether it fires outside the residual layer")
    print("   MARL-24's residual layer was 100% pinned. G37 (c) put the")
    print("   static bake's MEAN sigma at 0.0278 against sigma_max 0.02946,")
    print("   which is 94% of the way to the stop — so the fraction actually")
    print("   AT the stop should be substantial.")
    print("   → MARL25_PINNED = 0.5, a FLOOR on the share of the static")
    print("     bake's kernels within 1% of sigma_max.")
    print("     If it comes in low, the mean was being dragged up by a tail")
    print("     and the clamp is not shaping this population — in which case")
    print("     MARL-24's finding is specific to residual layers and should")
    print("     stay there.")

    print("\n2. WHAT COARSENING COSTS, ON EACH QUERY SET")
    print(f"   MARL-14, straddling shell, regions 6 -> 3: {MARL14_COARSE_K}x fewer")
    print(f"   kernels for {MARL14_COARSE_RMS}x the error. A trade, and a reasonable one,")
    print("   but not free — which is why nobody went looking further.")
    print("   MARL-22 then found a third of that query set is inside solid,")
    print("   where AO is exactly 0 and the target has a STEP. A step is the")
    print("   finest structure in the field and it is the thing a fine grid")
    print("   is being bought for.")
    print("   → MARL25_STEP_PAYS = 0.6, a CEILING on")
    print("       (the RMS cost of coarsening on the EXTERIOR shell − 1)")
    print("       ÷ (the same cost on the STRADDLING shell − 1)")
    print("     i.e. deleting the step must remove at least 40% of what")
    print("     coarsening costs. Stated as a RATIO of the two shells rather")
    print("     than as an absolute, because the two have different targets")
    print("     and different anchors and their RMS values are not")
    print("     comparable — which is the mistake MARL-22 nearly made and")
    print("     MARL-17 wrote the anchor rule to prevent.")

    print("\n3. …AND WHETHER IT IS ACTUALLY FREE")
    print("   → MARL25_FREE = 1.05, a CEILING on RMS(regions 4)/RMS(regions 6)")
    print("     on the exterior shell. One step of coarsening, five per cent.")
    print("     MARL-24 got 0.996 for the same step on a RESIDUAL, which is a")
    print("     smoother target than a field; five per cent is the slack for")
    print("     that difference.")
    print("     If this holds, every occlusion arm in the campaign has been")
    print("     paying for resolution the query set did not need, and the fix")
    print("     is one number.")

    print("\n4. WHAT IS NOT CLAIMED")
    print("   Not that MARL-14 was wrong: it measured a trade on the query")
    print("   set it had, and the trade was real. What is claimed is that the")
    print("   PRICE of that trade was mostly the step, and the step was a")
    print("   question nobody asks.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL25_PINNED    = 0.5   (floor, share of the static bake at sigma_max)")
    print("  MARL25_STEP_PAYS = 0.6   (ceiling, coarsening's cost on exterior over straddling)")
    print("  MARL25_FREE      = 1.05  (ceiling, regions 4 over regions 6, exterior shell)")


if __name__ == "__main__":
    main()
