#!/usr/bin/env python3
"""marl6_predict — MARL-6's gate numbers, before its runs.

The first experiment that tests the PREMISE rather than a mechanism. The
frozen-parent delta semantics say

    child ≈ unresolved detail of the current parent

and MARL-6 moves the world to find out whether that survives, or degrades
into

    child ≈ current target − historical parent

which is the same algebra and a different architecture.

Christian's restraint: break the world and watch. No thawing, reparenting,
forgetting or repair. And do NOT pre-register that RMS fails to recover —
the interesting question is whether it recovers by preserving a meaningful
hierarchy or by accumulating corrective archaeology.
"""

import math

R, BAND = 0.20, 0.05          # shell radius, band thickness (2W either side)
H = 1.0 / 6                    # parent region edge


def main():
    print("MARL-6 — predictions, written before the runs")
    print("=" * 70)

    print("\n0. The drift, and why two magnitudes")
    for name, d in (("small", 0.10), ("large", 0.30)):
        print(f"   {name:>5} displacement {d:.2f} = {d/H:.1f} parent regions, {d/BAND:.0f} band thicknesses")
    print("   Small keeps the new ridge inside the regions the old one refined.")
    print("   Large moves it into regions that were never pressured.")

    print("\n1. WHERE THE SEMANTIC FAILURE SHOULD APPEAR — and it is not where")
    print("   Christian expects")
    print("   His expectation 6 is that large drift exposes the frozen-parent")
    print("   problem more strongly. I predict the OPPOSITE for the semantic")
    print("   failure specifically, and the reasoning is structural:")
    print()
    print("     SMALL drift — the new ridge lands in regions that are already")
    print("     refined, so their parents are FROZEN and cannot learn it. The")
    print("     child is the only thing left that can, and it must carry the")
    print("     full shell amplitude (0.9) rather than a fine-scale residual.")
    print("     That is 'current target − historical parent' exactly.")
    print()
    print("     LARGE drift — the new ridge lands in regions that were never")
    print("     pressured, so their parents are NOT frozen and learn it")
    print("     normally, the way MARL-2's parent learns any structure. The")
    print("     damage there is stranded capacity in the abandoned regions,")
    print("     which is a different pathology and a cheaper one.")
    print()
    print("   → MARL6_CHILD_MAGNITUDE = 1.5: the child's RMS contribution")
    print("     after SMALL drift, over the stationary control's. The child is")
    print("     being asked to hold coarse structure it was never meant to.")
    print("   → and the same ratio under LARGE drift should be SMALLER than")
    print("     under small. If that inverts, my reasoning is wrong and")
    print("     Christian's expectation was right — which is worth finding out")
    print("     and is why both are run.")

    print("\n2. Stranded capacity (Christian's expectations 2 and 3)")
    print("   Child kernels born before the drift do not move far — MARL-0")
    print("   measured centre drift at 0.0009 mean over a whole run — so they")
    print("   stay where the old ridge was. Under large drift the old band and")
    print("   the new share almost nothing.")
    print("   → MARL6_STRANDED = 0.5: at least half the child kernels that")
    print("     existed at the drift are still outside the CURRENT band when")
    print("     the run ends. A floor, and a low one: they cannot leave.")

    print("\n3. Work reactivates (expectation 5)")
    print("   The surprise threshold is 0.02 and the ridge is 0.9 tall, so")
    print("   every exemplar landing on newly-wrong structure is a learning")
    print("   event. The settled rate is about 12% of exemplars by 200 000.")
    print("   → MARL6_REACTIVATION = 2.0: learning events in the window after")
    print("     the drift, over the same window in the stationary control.")

    print("\n4. Refinement precision against the CURRENT target falls")
    print("   (expectation 4). Regions are refined once and never unrefined,")
    print("   so after a move the refined set describes where structure USED")
    print("   to be. Precision is measured against the current band, so it")
    print("   must fall by roughly the share of the old refined set the new")
    print("   ridge no longer occupies.")
    print("   → MARL6_PRECISION_FALL = 0.85: precision after large drift, over")
    print("     the stationary control's. Only a modest fall is required —")
    print("     newly pressured regions are still refined correctly, so the")
    print("     set is diluted rather than replaced.")

    print("\n5. NOT pre-registered, at Christian's instruction")
    print("   That RMS fails to recover. It may recover well, and recovering")
    print("   well while the hierarchy ossifies is outcome B — the one an")
    print("   ordinary benchmark would call success. Reported, never gated.")
    print("   Also reported and not gated: the hysteresis run, A → B → A.")
    print()


if __name__ == "__main__":
    main()
