#!/usr/bin/env python3
"""marl22_predict — MARL-22's gate numbers, before its run.

Christian, looking at MARL-21: "Seems like the RBF might need a higher
dimension? like it's struggling to represent? or am I reading it wrong?"

He is reading it right, and the campaign's own instrument says so. G33 (b)
fits

    RMS^2 = bias^2 + mu/(2-mu) * V/M

and its intercept — the error with ALL measurement noise removed — is
**0.15110**. Every 0.15 quoted from MARL-13 to MARL-21 has been called a
noise floor in the prose. It is a REPRESENTATION floor. At M = 16 the
variance term is 0.0067 of an RMS^2 of 0.0295: the error is 77% bias, and
at MARL-20's slower rates it is more.

So the question is what the basis is failing to represent, and there is a
specific candidate that the campaign has already measured in another form.

## MARL-16, applied to the query set nobody re-examined

MARL-16 built a bias term twice and lost twice, and the sentence was:

    A Gaussian basis with a hard cutoff cannot cheaply represent a plateau
    of ANY value. Zero is not special because it is zero — it is special
    because it is what an EMPTY MODEL ALREADY PREDICTS.

MARL-13 then chose `invert` — learn `1 - AO` — because the OPEN SKY, where
AO is about 1, becomes zero in inverted space and is therefore free. It
measured 1.40x for it and every phase since has inherited the flag.

But look at what inverting does to the other end. Inside solid geometry
`aoAt` returns EXACTLY 0, so in inverted space **the interior of every
wall is a plateau at 1.0** — precisely the expensive object MARL-16
measured at 5.679x. That did not matter on MARL-13's volume-uniform query
set, where open sky dominates and solid is 4% of the cube.

It should matter enormously on the SHELL query set that MARL-13 (d) onward
actually uses, because the shell is drawn on `|phi| < band` and that
straddles the surface. For a sphere of radius R with a band of 1:

    inside   R^3 - (R-1)^3
    outside  (R+1)^3 - R^3

which at R = 3.4 is 25.5 against 45.9 — **36% of the query set is inside
solid, where the target is a constant 1.0 in inverted space, adjacent to a
region where it is about 0.5.**

A Gaussian mixture is continuous. It is being asked to fit a STEP, and a
third of the queries sit on the expensive side of it.
"""

import math

R = 3.4       # GROVE_R
BAND = 1.0    # surface_band on the shell arms
INTERCEPT = 0.15110   # G33 (b): the representation error alone
RMS_16 = 0.17174      # G33 (b): the total at M = 16


def main():
    print("MARL-22 — predictions, written before the run")
    print("=" * 72)

    print("\n0. THE CORRECTION THIS PHASE EXISTS FOR")
    var = RMS_16 ** 2 - INTERCEPT ** 2
    print(f"   G33 (b), already measured: RMS(M=16) = {RMS_16}, intercept = {INTERCEPT}")
    print(f"   bias^2 = {INTERCEPT**2:.6f}, variance = {var:.6f}")
    print(f"   → the error is {INTERCEPT**2/RMS_16**2:.0%} REPRESENTATION and {var/RMS_16**2:.0%} noise.")
    print("   The prose in MARL-13 through MARL-21 calls it a noise floor.")
    print("   It is not one, and the ledger is corrected in this phase.")

    print("\n1. WHERE THE REPRESENTATION ERROR IS")
    inside = R ** 3 - (R - BAND) ** 3
    outside = (R + BAND) ** 3 - R ** 3
    frac = inside / (inside + outside)
    print(f"   The shell is drawn on |phi| < {BAND}, which STRADDLES the surface.")
    print(f"   For a sphere of radius {R}: inside {inside:.1f}, outside {outside:.1f}")
    print(f"   → {frac:.0%} of the query set is INSIDE SOLID, where aoAt returns")
    print("     exactly 0 — and with `invert` that is a plateau at 1.0,")
    print("     which is the object MARL-16 measured at 5.679x.")
    print("   → MARL22_STEP = 2.0, a FLOOR on")
    print("       RMS(probes inside solid) / RMS(probes outside)")
    print("     for the arm every phase since MARL-13 has been running. If")
    print("     the error is spread evenly the discontinuity is not the")
    print("     problem and the basis is simply short of capacity, which is")
    print("     the other half of Christian's question and is swept in SS3.")

    print("\n2. THE FIX, AND IT IS FREE")
    print("   **A renderer never shades inside a wall.** The interior of")
    print("   solid geometry is in the query set for no reason but that")
    print("   `drawQuery` tests `|phi| < band` rather than `-band < phi < 0`.")
    print("   Excluding it removes the expensive plateau AND the step in one")
    print("   line, and removes nothing anybody asks for.")
    print("   The kernels near a surface currently have to hold up a")
    print("   plateau on one side while tracking a varying field on the")
    print("   other; freed of the first, they should fit the second better.")
    print("   → MARL22_EXTERIOR = 0.8, a CEILING on")
    print("       RMS(trained on the exterior shell) / RMS(trained on the")
    print("       full shell), BOTH SCORED ON EXTERIOR PROBES ONLY.")
    print("     The scoring set is identical; only the training distribution")
    print("     differs, so this cannot be won by changing the denominator.")
    print("     A 20% improvement for deleting a query nobody makes.")

    print("\n3. …AND WHETHER `invert` IS STILL RIGHT ONCE IT IS GONE")
    print("   MARL-13 chose `invert` to make the open sky free, and paid for")
    print("   it with a plateau at 1.0 inside solid. Delete the interior and")
    print("   the payment disappears — but so does part of the reason, since")
    print("   an exterior shell is not mostly open sky either: it is the")
    print("   band right next to geometry, where AO runs about 0.2 to 0.9")
    print("   with neither end a large plateau.")
    print("   → MARL22_INVERT = 1.15, a CEILING on the RATIO of the two")
    print("     orientations on an exterior-only shell, whichever way round")
    print("     — i.e. a claim that it stops mattering. MARL-13 measured")
    print("     1.40x for inverting on the volume-uniform set; if it is")
    print("     still worth that much here, the plateau was not the")
    print("     mechanism and SS1's story is wrong.")

    print("\n4. AND THE OTHER HALF OF THE QUESTION: IS IT CAPACITY?")
    print("   'Higher dimension' can mean more capacity, and that is a")
    print("   separate axis with its own answer. sigma_max = h/sqrt(CUTOFF)")
    print("   with h = 1/regions, so `regions` sets the finest scale the")
    print("   basis can resolve. A step is approximated by a Gaussian sum to")
    print("   O(sigma) in RMS, so IF the residual error is the")
    print("   discontinuity, halving sigma should roughly halve it.")
    print(f"   {'regions':>9} {'h':>9} {'sigma_max':>11} {'ideal RMS':>11}")
    for r in (4, 6, 8, 12):
        h = 1.0 / r
        sig = h / math.sqrt(32.0)
        print(f"   {r:>9} {h:>9.4f} {sig:>11.5f} {INTERCEPT * (6.0/r):>11.5f}")
    print("   → MARL22_CAPACITY = 0.85, a CEILING on")
    print("       RMS(regions 12) / RMS(regions 6)")
    print("     on the exterior shell. Well above the 0.5 the O(sigma)")
    print("     argument gives, because MARL-1's invariant cuts the other")
    print("     way: eight times the regions is eight times the population")
    print("     on the same evidence, and 'capacity you cannot train is")
    print("     worse than capacity you do not have' has four sightings.")
    print("     If it comes in ABOVE 1.0, finer is worse and the answer to")
    print("     'does it need more' is no — it needs more EVIDENCE, which")
    print("     is MARL-11's law and would make this a fifth sighting.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL22_STEP     = 2.0   (floor, RMS inside solid over RMS outside)")
    print("  MARL22_EXTERIOR = 0.8   (ceiling, exterior-trained over full-shell-trained)")
    print("  MARL22_INVERT   = 1.15  (ceiling, the two orientations on an exterior shell)")
    print("  MARL22_CAPACITY = 0.85  (ceiling, regions 12 over regions 6)")


if __name__ == "__main__":
    main()
