#!/usr/bin/env python3
"""obs8_predict — OBS-8's gate numbers, before its run.

Christian, on OBS-7, restating its result better than the phase did:

    An operator is inferable only to the extent that it contributes
    something linearly independent of the representational span already
    available to the learner.

with a refinement to the sentence OBS-7 closed on.  Not "a library is well
posed to the extent it lies outside the span" but:

    LOCALLY IDENTIFIABLE UNDER THE CHOSEN SAMPLING MEASURE AND BASIS

because the residual measures geometric independence, and practical
recoverability additionally needs conditioning, coverage, noise, and the
candidates not being collinear WITH EACH OTHER.  Two candidates can both
sit beautifully outside the potential span and still be nearly collinear.

OBS-8 is the geometry experiment that follows, and it is deliberately an
experiment about a BASIS rather than about a learner: most of it runs
least squares on a grid with no optimiser anywhere.  A learner appears only
at the end, on either side of a crossover the geometry predicted.

    python3 tools/obs8_predict.py
"""

import math

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-8 — a taxonomy of degeneracy.  PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) THE RESIDUALISED LIBRARY, AND WHY ITS GRAM IS A CLEAN READOUT

Christian's extension of `law.degeneracy`.  Instead of scoring each
candidate alone, residualise the whole library against the learned basis

    Gtilde = (I - P_Phi) G

and read two things off it before any optimisation:

    NOVELTY               ||gtilde_i|| / ||g_i||
    MUTUAL IDENTIFIABILITY  the singular values of H = Gtilde^T Gtilde

**And there is a reason this is unusually clean here, which was measured
before writing the rest of this file.**  On the symmetric sampling square
the RAW library is exactly orthogonal:

    worst off-diagonal of the normalised raw Gram   1.8e-14
    condition number of the raw Gram                1.0000

Every pair vanishes by the symmetry of the region -- E[dx] = E[dy] =
E[dx*dy] = 0 and E[dx^2] = E[dy^2] -- so rot.div, rot.shear, rot.drift,
div.shear, div.drift, shear.drift and driftx.drifty are all identically
zero.  Therefore:

    EVERY off-diagonal element of the residualised Gram is MANUFACTURED
    BY THE BASIS.  None of it comes from the library.

That makes H a pure readout of what the current representation does to a
library, with nothing of the library's own construction mixed in.

    PREDICTED  raw Gram: worst normalised off-diagonal < 1e-6, condition
               number within 1e-6 of 1 (a derivation, checked)
    PREDICTED  residualised Gram: worst normalised off-diagonal > 0.02,
               so the coupling exists and is basis-made

Two condition numbers are reported and they say different things, so both
are named rather than one being called "the" conditioning:

    cond(H) on the raw residuals      -- dominated by the NOVELTY SPREAD,
                                         ~ (1/0.097)^2 at OBS-7's basis:
                                         "one candidate is nearly invisible"
    cond on residuals normalised to
    unit length                       -- MUTUAL COLLINEARITY alone
""")

print("""(2) THE TWO AXES, EACH ISOLATING ONE THING

OBS-7's basis is 3x3 on [.25,.75], h = .25, sigma = .22, so sigma/h = .88
and the sampled square [.15,.85] extends 0.4h beyond the lattice each side.
The two axes move one property each and share that basis as their origin.

    AXIS A -- SMOOTHNESS SCALE.  Lattice fixed on [.25,.75], n in
              {3,4,5,6,8}, h = .5/(n-1), sigma = .88h.  Same support,
              finer structure.

    AXIS B -- SUPPORT SCALE.  h = .25 and sigma = .22 held at OBS-7's
              exactly, rings r in {0,1,2} added at the same spacing, so
              the lattice spans [.25-.25r, .75+.25r] with n = 3+2r.  Same
              resolution, more support.  At r = 1 the lattice covers
              [0,1] and contains the sampled square outright.

(3) THE TAXONOMY, WHICH IS CHRISTIAN'S PREDICTION AND NOT THE AGENT'S

    "The radial bowl should disappear mostly as a scale issue.  The saddle
     should collapse once the basis can represent the central sign
     structure.  The ramp should improve disproportionately when you
     extend support beyond the observed lattice boundary."

Registered as an INTERACTION, because each candidate falling on both axes
would be nothing more than "a richer basis absorbs more":

    PREDICTED  for the RAMP (drift x/y):
                   improvement on axis B (r 0 -> 1)
                 > improvement on axis A (n 3 -> 5)

    PREDICTED  for the SADDLE (shear): the reverse,
                   improvement on axis A (n 3 -> 5)
                 > improvement on axis B (r 0 -> 1)

    "improvement" is the drop in novelty, 1 - novelty(after)/novelty(before),
    so it is a fraction and the two axes are comparable.

    NOT PREDICTED  the bowl's split.  It starts at .0967 with little left
                   to lose, and a prediction about the direction of a small
                   remainder would be a prediction about quadrature.

(4) THE INVARIANT, AND IT IS THE SHARPEST THING HERE

    PREDICTED  the ROTATION's novelty stays above 0.999 at EVERY basis on
               BOTH axes -- an invariant, not a trend.

A potential's gradient field is curl-free everywhere, at any resolution and
any support.  A rigid rotation has curl 2.  So no amount of basis
refinement can make a rotation degenerate, and the degeneracy that OBS-7
measured for the other four is a matter of RESOLUTION AND SUPPORT while
the rotation's independence is TOPOLOGICAL.

That is the difference the taxonomy is for.  If a candidate's novelty
falls as the basis is enriched, its identifiability was always contingent;
if it does not, the candidate is independent of the whole model class and
no refinement will ever confuse it.

(5) THE CROSSOVER, WITH A LEARNER, AND THE DISTINCTION IT MEASURES

Christian: "geometry predicts identifiable -> learner recovers
coefficient; geometry predicts degenerate -> coefficient becomes
unstable/arbitrary while prediction remains good."

So: put the SHEAR in the truth instead of the rotation, and fit at a basis
either side of its predicted collapse on axis A.

    PREDICTED  at the basis where geometry says IDENTIFIABLE, the shear
               coefficient is recovered within 15% at every seed
    PREDICTED  at the basis where geometry says DEGENERATE, the across-seed
               spread of the recovered coefficient is at least 5x larger
    PREDICTED  held-out endpoint RMS is GOOD AT BOTH, within a factor of 2

The third is the one that matters and it is the one a system-identification
paper most often skips.  State prediction being identifiable and physical
decomposition being identifiable are not the same problem, and this
measures them apart on one run.

(6) WHAT IS NOT BEING CLAIMED

Noise is absent throughout.  Coverage is one symmetric square, which is
what makes the raw library orthogonal and is therefore load-bearing for
(1) -- on an asymmetric or clustered sensor region the raw Gram would not
be the identity and the clean attribution of coupling to the basis would
weaken.  That is a real limit and it is the obvious next axis after these
two.  Nothing here bears on level 4, and no candidate outside the affine
family is tested.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
