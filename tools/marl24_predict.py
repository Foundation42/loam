#!/usr/bin/env python3
"""marl24_predict — MARL-24's gate numbers, before its run.

Christian: "what are we keeping in the residuals right now, just out of
curiosity?"

Dumping one answered it, and one line of the dump was not a curiosity:

    sigma (of the unit cube) 0.02858 … 0.02946   and   sigma_max = 0.02946

**Every kernel in the residual layer is pinned at the widest the clamp
allows.** The whole population is against the stop. The geometry descent
wants them wider and cannot have it, because sigma_max = h/sqrt(CUTOFF) with
h = 1/regions, and the layer inherited `regions = 6` from the static bake it
sits beside.

That is MARL-23's finding arriving from the other direction. The edge sweep
found the optimum kernel width is THE FEATURE'S OWN WIDTH, and that finer
than that is worse for a linear-algebra reason. A residual is a SMOOTHER
object than the field it corrects — the dump measured its target at a mean
of 0.0502 and a max of 0.4297, spread across the whole affected ball — so
its natural sigma is larger, and the region grid is holding it fine.

## What was seen, on the corridor fixture, BEFORE this was written

    regions   sigma_max   kernels    KiB   composed RMS
          6     0.02946       283   11.1        0.14957
          4     0.04419       115    4.5        0.14830
          3     0.05893        62    2.4        0.15193
          2     0.08839        30    1.2        0.15216

Coarsening from 6 to 4 is 2.5x FEWER kernels and a slightly BETTER fit, and
2 is 9.4x less memory for 1.7% more error.

That is an OBSERVATION from an inspection, not a gated result: the numbers
came before any threshold was written, which is exactly the order this
campaign does not accept. So the numbers below are pre-registered for a
CONFIRMING run on a DIFFERENT fixture — MARL-21's CONTACT geometry, where
the residual is sharper and the case for a coarse basis is weaker.
"""


def main():
    print("MARL-24 — predictions, written before the run")
    print("=" * 72)

    print("\n0. THE MECHANISM, stated so it can be checked rather than assumed")
    print("   sigma_max = h/sqrt(CUTOFF), h = 1/regions. At regions 6 that is")
    print("   0.02946 of the unit cube, and the observed population spans")
    print("   0.02858 to 0.02946 — every kernel against the stop.")
    print("   → asserted directly: the residual layer's WIDEST kernel must")
    print("     sit within 1% of sigma_max, or the clamp is not what is")
    print("     limiting it and the rest of this phase is about something")
    print("     else.")

    print("\n1. THE SHRINK")
    print("   The static bake and the residual layer are fitting different")
    print("   objects and there is no reason they should share a region")
    print("   grid. MARL-14 already established `regions` as the dial (6 -> 3")
    print("   gave 4.32x fewer kernels for a quarter more error) — but that")
    print("   was a DISTILLATION trade, paying accuracy for size. Here the")
    print("   claim is stronger: it should be free, because the layer is")
    print("   currently forced finer than its target.")
    print("   → MARL24_SHRINK = 0.5, a CEILING on")
    print("       K(residual at regions 4) / K(residual at regions 6)")
    print("     on the CONTACT fixture. The corridor gave 0.41; contact has")
    print("     a sharper residual, so the ceiling is set looser than what")
    print("     was seen rather than at it.")

    print("\n2. …AND IT SHOULD BE FREE")
    print("   → MARL24_FREE = 1.02, a CEILING on")
    print("       RMS(composed, regions 4) / RMS(composed, regions 6)")
    print("     Two per cent, which is the campaign's usual noise on a")
    print("     composed figure. The corridor measured 0.991 — BETTER — and")
    print("     pitching this at parity would be claiming the improvement")
    print("     rather than testing the trade.")
    print("   If BOTH hold, MARL-20's headline improves without a new")
    print("   mechanism: its residual layer was carrying a region grid it")
    print("   inherited from a neighbour with a different job.")

    print("\n3. WHAT IT WOULD MEAN AT THE FAR END")
    print("   MARL-20 measured a full re-bake at 2 603 kernels and 101.7 KiB")
    print("   against a residual layer's 283 and 11.1. At regions 2 the")
    print("   corridor's layer was 30 kernels in 1.2 KiB — **87x fewer")
    print("   kernels than a re-bake** for 1.7% more error than the layer it")
    print("   replaces. Not gated here, because the accuracy trade at")
    print("   regions 2 is a choice rather than a free lunch, and this phase")
    print("   is only claiming the free part.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL24_SHRINK = 0.5   (ceiling, K at regions 4 over K at regions 6)")
    print("  MARL24_FREE   = 1.02  (ceiling, composed RMS at regions 4 over at 6)")


if __name__ == "__main__":
    main()
