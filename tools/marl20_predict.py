#!/usr/bin/env python3
"""marl20_predict — MARL-20's gate numbers, before its run.

Christian's plan, SS7 and SS8: keep a baked static MARL for the world and
represent moving things as additional RESIDUAL field layers.

    F(x,t) = M_static(x) + sum_i M_dynamic_i(x,t)
    D(x,t) = F_current(x,t) - F_static(x)

with the architectural property he is after being that **complexity follows
change**: static knowledge stays cheap and stable, and only what actually
moved consumes ongoing work.

## Why this is the campaign's own best finding, cashed

MARL-16 is the phase that makes this work, and it was a REFUTATION at the
time. A bias term was built twice and lost twice, and the sentence that
came out of it was:

    Zero is not special because it is zero — it is special because it is
    what an EMPTY MODEL ALREADY PREDICTS. A target that is zero over a
    large region costs literally nothing.

A residual layer is zero everywhere the world did not change. So a residual
MARL is not merely a good fit for this, it is the exact shape of field this
representation is free on — and the phase that discovered it did so by
failing to add a background.

Two more standing results do the rest of the work:

  MARL-13's sparsity rule. "A learned sparse field beats a dense grid when
  the interesting set is SPARSE IN THE DOMAIN." A moving object's
  disturbance is the sparsest interesting set the campaign has had.

  Exact locality (G17 c/d, bitwise). The static layer is untouched by
  anything the residual learns, structurally, not approximately.

## The estimator, and it is better than it looks

The residual is `AO_static - AO_perturbed`, and BOTH terms can be taken
from the SAME marched directions: a mover only ADDS occlusion, so a ray
that already hit the level contributes exactly zero to the residual. The
two estimates are perfectly correlated where nothing changed, and the
difference of two Binomial estimates that share their draws has far less
variance than either. **A residual is cheaper to measure than a field.**
"""

import math

EXTENT = 32.0        # the grove's cube, cache.GROVE_EXTENT
REACH = 5.0          # AoOptions.reach — occlusion is a local effect
# The dynamic occluder. The grove's corridors are 2.5 units of clearance at
# their tightest (lattice spacing 10.67, sphere radius 3.4, jitter 1.6), so
# 2.0 keeps the mover in open space with room to spare — a mover embedded in
# a wall would disturb nothing and the phase would measure zero.
MOVER_R = 3.5


def main():
    print("MARL-20 — predictions, written before the run")
    print("=" * 72)

    print("\n1. HOW MUCH OF THE FIELD A MOVING OBJECT CAN POSSIBLY DISTURB")
    print("   Ambient occlusion here is bounded by `reach`: a ray that")
    print("   travels further than that is counted open whatever is beyond")
    print("   it. So a mover of radius r can change the field only within")
    print("   r + reach of its centre — not approximately, but exactly, and")
    print("   for the same structural reason CUTOFF gives the kernels exact")
    print("   locality. The occluder has a support and so does a kernel.")
    aff_r = MOVER_R + REACH
    ball = 4.0 / 3.0 * math.pi * aff_r ** 3
    cube = EXTENT ** 3
    print(f"   r = {MOVER_R}, reach = {REACH} → affected radius {aff_r}")
    print(f"   {ball:.0f} of {cube:.0f} cubic units = {ball/cube:.4f} of the domain")
    print("   The QUERIED set is a shell around geometry, not the cube, so")
    print("   the fraction that matters is measured rather than assumed —")
    print("   the gate counts probes whose truth actually moved.")
    print("   → MARL20_SPARSE = 0.25, a CEILING on")
    print("       K(residual layer) / K(a full re-bake).")
    print(f"     Generously above the {ball/cube:.3f} the geometry gives, because")
    print("     the residual has boundary structure of its own — it goes to")
    print("     zero at the edge of the affected ball, and an edge costs")
    print("     kernels. If it comes in near 1.0 then a residual layer is")
    print("     not sparse in practice and SS7 is machinery for nothing.")

    print("\n2. COMPOSITION IS EXACT, SO ONLY THE FITS CAN BE WRONG")
    print("   D is DEFINED as the difference, so `static + residual` is not")
    print("   an approximation scheme — it is an identity, whatever the")
    print("   underlying physics does. (SS9 is right that occlusion composes")
    print("   multiplicatively in general; that is an argument about")
    print("   combining two OCCLUDERS, not about a learned difference.)")
    print("   So the composed arm's error is its two fits in quadrature:")
    print("   the static model's own error, which the re-bake also pays,")
    print("   plus the residual model's.")
    print("   → MARL20_COMPOSE = 1.15, a CEILING on")
    print("       RMS(static + residual) / RMS(a full re-bake)")
    print("     with the residual arm given ONE EIGHTH of the re-bake's ray")
    print("     budget. Not parity: the composed arm carries two fits where")
    print("     the re-bake carries one. The eighth is what makes this a")
    print("     test of SS12's 'work scales with changed regions' rather")
    print("     than a test of whether a second model can be fitted at all.")

    print("\n3. THE MOVE, and it is the case MARL-19 could not reach")
    print("   MARL-19 found history is nearly free in MARL, and MARL-16 said")
    print("   why: the structure that goes obsolete sits at ZERO, which is")
    print("   what an empty model already predicts, so it never cost")
    print("   anything to hold down. A MOVING OCCLUDER is the case that")
    print("   breaks: when the object leaves, the residual it left behind is")
    print("   a WRONG NON-ZERO value, and now the model must actively pull")
    print("   it back down. Zero being free cuts the other way.")
    print("   MARL-7 spent a whole phase looking for an erosion mechanism")
    print("   and concluded there was nothing to erode. MARL-8 tried reuse")
    print("   and failed. But a residual layer is CHEAP by SS1 — so there is")
    print("   a third option neither phase had available:")
    print("     THROW IT AWAY AND BUILD A NEW ONE.")
    print("   → MARL20_REBUILD = 1.0, a CEILING on")
    print("       RMS(residual rebuilt from scratch) / RMS(residual adapted")
    print("       in place), at EQUAL work after the object moves.")
    print("     If it holds, the answer to erosion is that you do not need")
    print("     one when the thing is small enough to discard — which is a")
    print("     practical answer to two phases' worth of failure, and it is")
    print("     available only because the layer is sparse.")

    print("\n4. WHAT IS DELIBERATELY NOT BUILT")
    print("   No object-local coordinate frame (SS8), no scheduler (SS10),")
    print("   no particles (SS11). All three are downstream of SS1: if a")
    print("   residual layer is not cheap, none of them has a premise.")
    print("   And no multi-object stacking, because two movers that do not")
    print("   overlap are two independent instances of the same measurement.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL20_SPARSE  = 0.25  (ceiling, K residual / K re-bake)")
    print("  MARL20_COMPOSE = 1.15  (ceiling, RMS composed / RMS re-bake, at 1/8 the rays)")
    print("  MARL20_REBUILD = 1.0   (ceiling, RMS rebuilt / RMS adapted, after a move)")


if __name__ == "__main__":
    main()
