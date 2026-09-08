#!/usr/bin/env python3
"""marl21_predict — MARL-21's gate numbers, before its run.

MARL-20 built Christian's residual layer and it worked, but the effect was
MODEST: a 4.2-unit occluder floating in a corridor degraded the local bake
by 1.142x and moved the truth by 0.0483 on average. The honest limit
recorded at the time was that ambient occlusion in a dense grove is
dominated by the grove — a mover in open space competes with spheres that
are already blocking most of the sky.

**CONTACT is the case that should bite**, and it is the one a renderer
actually cares about: a crate resting on a floor, a barrel against a wall.
At a contact point the object subtends nearly a HEMISPHERE, so the change
in occlusion is not a few per cent, it is up to a half.

## Why this should be where a residual layer shines, and not merely work

MARL-11's law is the one that decides it: **evidence binds, not placement.**
That phase lost to batch Adam because the online learner could not re-read
its pool, and every phase since has confirmed that RMS tracks
updates-per-kernel.

A residual layer inverts that constraint by construction. A full re-bake
spreads its samples over the WHOLE query distribution, of which the
affected ball is a few per cent; the residual layer spends every one of its
samples inside that ball. So the residual arm has LESS total evidence and
MORE local evidence, and the local set is the only place either of them
differs.

That is a sharp, falsifiable prediction and it is the point of the phase.
"""

import math

RE_BAKE_SAMPLES = 60_000
RESIDUAL_SAMPLES = RE_BAKE_SAMPLES // 8
AFFECTED_FRACTION = 0.072      # MARL-20 measured this for r = 4.2
MARL20_DELTA = 0.0483          # the corridor mover's mean |change|
MARL20_RECOVER = 1.09          # what its residual recovered of the stale error


def main():
    print("MARL-21 — predictions, written before the run")
    print("=" * 72)

    print("\n1. HOW MUCH BIGGER CONTACT SHOULD BE")
    print("   A sphere resting against a surface subtends, at the contact")
    print("   point itself, very nearly a hemisphere — half the sky. So the")
    print("   ceiling on the change is ΔAO = 0.5, against MARL-20's measured")
    print(f"   mean of {MARL20_DELTA} for a mover floating in a corridor.")
    print("   The mean over the affected ball's shell is far below the")
    print("   ceiling, because most of that shell is metres from the contact")
    print("   and sees the mover as a small disc.")
    print("   → MARL21_CONTACT = 0.10, a FLOOR on the mean |ΔAO| over the")
    print(f"     local probe set — roughly twice MARL-20's {MARL20_DELTA} and a")
    print("     fifth of the hemisphere ceiling. This is a FIXTURE VALIDITY")
    print("     number, checked first: MARL-20 burned two nulls on movers")
    print("     that disturbed nothing, and the lesson recorded then was that")
    print("     'the effect was too small to see' and 'there is no effect'")
    print("     print exactly the same way.")

    print("\n2. WHAT THE RESIDUAL SHOULD RECOVER")
    print(f"   MARL-20's residual recovered {MARL20_RECOVER}x of the stale bake's local")
    print("   error — real, but nothing to write home about. The recovery")
    print("   should scale with the size of the thing there is to recover,")
    print("   and SS1 says that is roughly doubling.")
    print("   → MARL21_RECOVER = 1.5, a FLOOR on")
    print("       RMS(stale bake) / RMS(static + residual)")
    print("     on the local probe set.")

    print("\n3. THE HEADLINE: a residual layer should BEAT a full re-bake")
    print("   locally, on an eighth of the rays")
    print("   MARL-11: evidence binds, not placement. A re-bake spreads its")
    print("   samples over the whole query distribution; the residual spends")
    print("   every one inside the affected ball. Counting them:")
    local_rebake = RE_BAKE_SAMPLES * AFFECTED_FRACTION
    print(f"     re-bake   {RE_BAKE_SAMPLES} samples × {AFFECTED_FRACTION:.3f} affected = {local_rebake:.0f} land locally")
    print(f"     residual  {RESIDUAL_SAMPLES} samples × 1.000            = {RESIDUAL_SAMPLES} land locally")
    print(f"   → {RESIDUAL_SAMPLES/local_rebake:.2f}× the LOCAL evidence for an EIGHTH of the total cost.")
    print("   And the residual is an easier target than the field: it is")
    print("   zero outside the ball (free, MARL-16), it is measured by a")
    print("   correlated estimator that shares its rays (MARL-20), and it")
    print("   has no background to hold up.")
    print("   → MARL21_CONCENTRATE = 1.0, a CEILING on")
    print("       RMS(static + residual) / RMS(a full re-bake)")
    print("     on the local set. **Below parity**, where MARL-20's")
    print("     MARL20_COMPOSE was pitched at 1.15 and measured 1.050.")
    print("     This is the phase's bold number: it says the layered")
    print("     representation is not a cheap approximation to re-baking, it")
    print("     is BETTER than re-baking where it matters, and for the")
    print("     campaign's own oldest reason.")
    print("   The way it fails is worth naming: the composed arm inherits")
    print("   the STATIC model's error on the unperturbed part of the field,")
    print("   and a re-bake does not — it refits everything. So the gate")
    print("   prints the static model's own local error beside the rest, as")
    print("   the floor the composed arm cannot go below.")

    print("\n4. WHAT IS NOT BEING CLAIMED")
    print("   Not that a residual layer is better than a re-bake GLOBALLY —")
    print("   it cannot be, it does not touch the rest of the scene. The")
    print("   claim is local, and 'local' is where the object is, which is")
    print("   the only place the two representations differ at all.")

    # ── The extension, written AFTER the first run of G40 and BEFORE the
    #    surface-weighted arm, and labelled so the two cannot be confused. ──
    print("\n" + "=" * 72)
    print("EXTENSION — written AFTER G40's first run and BEFORE its second.")
    print("""
   All three numbers were REFUTED, and the stratified diagnostic says the
   physics was right and the METRIC was wrong:

       distance from its surface  probes   mean |D|   max |D|
                          0 - 1       10     0.2455    0.3145
                          1 - 2       48     0.0921    0.1821
                          2 - 4      257     0.0449    0.1155
                          4 - 99     197     0.0108    0.0483

   Contact is STRONGER than predicted where contact happens — 0.2455
   against a floor of 0.10 — and it decays twentyfold over four units. The
   mean over the affected ball came to 0.0401 because 38% of the probes sit
   in the outermost band, seeing essentially nothing.

   **The affected ball is the SUPPORT, not the SCALE.** A residual's support
   and its magnitude have completely different geometries: the support is
   r + reach, and the magnitude lives within about a unit of the surface.
   MARL-20 hit the same dilution one level out (a global probe set diluted
   by a local object) and this is the identical mistake made again, inside
   the region that was supposed to fix it.

   And it explains MARL21_CONCENTRATE's failure directly. Sampling
   UNIFORMLY IN VOLUME over the ball puts samples in proportion to r^2, so
   the residual layer spent ~38% of its evidence in the band where |D| =
   0.0108 — learning that zero is zero — and 2% in the band where |D| =
   0.2455. The concentration argument was right that a residual layer can
   put its evidence where the change is; the implementation then spread it
   uniformly over the support instead.

   MARL-4 is the phase that already solved this. It changed the STREAM
   rather than the model — `p(route) = min(1, floor + gain*|residual|)` —
   and moved capacity concentration 1.65 -> 2.50, with all four of its
   pre-registered numbers holding. The geometric analogue here needs no
   tuning constant at all: draw the radial offset UNIFORMLY IN DISTANCE
   from the object's surface rather than uniformly in volume, which puts
   equal numbers of samples in each distance band and exactly cancels the
   r^2 dilution.
""")
    print("   The reweighting that buys, band by band, against uniform-in-volume:")
    for lo, hi, n, d in ((0, 1, 10, 0.2455), (1, 2, 48, 0.0921), (2, 4, 257, 0.0449), (4, 9.2, 197, 0.0108)):
        share = n / 512
        even = (hi - lo) / 9.2
        print(f"     {lo:>4.0f} - {hi:<4.1f}  |D| {d:.4f}   uniform-in-volume {share:6.1%}   uniform-in-distance {even:6.1%}   {even/share:5.1f}x")
    print("   → MARL21_SURFACE = 1.0, a CEILING on")
    print("       RMS(static + residual) / RMS(a full re-bake)")
    print("     on the SAME uniform local probe set, with the residual's")
    print("     TRAINING drawn uniformly in distance from the object's")
    print("     surface. The probes do not move — only where the layer")
    print("     spends its samples — so this is a clean test of MARL-4's")
    print("     mechanism and not a change of denominator.")
    print("     It is the headline MARL21_CONCENTRATE was reaching for, with")
    print("     the reason its first form failed now named.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL21_CONTACT     = 0.10  (floor, mean |ΔAO| locally — fixture validity)")
    print("  MARL21_RECOVER     = 1.5   (floor, stale over composed, locally)")
    print("  MARL21_CONCENTRATE = 1.0   (ceiling, composed over a full re-bake, locally)")
    print("  MARL21_SURFACE     = 1.0   (ceiling, the same with surface-weighted training)")


if __name__ == "__main__":
    main()
