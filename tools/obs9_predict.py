#!/usr/bin/env python3
"""obs9_predict — OBS-9's gate numbers, before its run.

Christian, closing OBS-8:

    growth pressure, mismatch detection, distillation, and now operator
    discovery are all converging on essentially the same question:
    What explanatory degree of freedom is genuinely missing from the
    current representation?

    Kernel birth says "I need more spatial representational capacity."
    Operator inference says "I need a new dynamical direction."
    Distillation asks "Which existing degrees of freedom are redundant?"

OBS-9 builds that as ONE operation.  Given a candidate g, a current span
Phi, and the measure mu you actually observe under,

    novelty(g ; Phi, mu) = || (I - P_Phi) g ||_mu  /  || g ||_mu

with the residualised Gram of a whole candidate set beside it.  Three
faces, one primitive:

    BIRTH          g is a candidate kernel, Phi the existing kernels,
                   mu the local exemplar density
    OPERATOR       g is a candidate operator's field, Phi the learned
                   span, mu the sensor region              (OBS-7, OBS-8)
    DISTILLATION   g is an EXISTING kernel, Phi the OTHERS, mu the query
                   distribution -- leave-one-out

    python3 tools/obs9_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-9 — one residualisation, three faces.  PRE-REGISTERED")
print("=" * 74)

print("""
(1) LEAVE-ONE-OUT IS ONE MATRIX INVERSE, NOT N SOLVES

The distillation face looks expensive: N separate least-squares problems,
each fitting one basis function against the other N-1.  It is not.  For
G = Phi^T Phi,

    || (I - P_{-i}) phi_i ||^2  =  1 / (G^-1)_ii

which is the standard partial-correlation identity, and therefore

    novelty_i  =  1 / sqrt( G_ii * (G^-1)_ii )

One Cholesky gives EVERY function's redundancy.  The quantity
G_ii*(G^-1)_ii is the variance inflation factor, so novelty is exactly
1/sqrt(VIF) -- a fact worth naming because it means the statistics
literature has already characterised the thing this campaign arrived at
from the other direction.

    PREDICTED  G56 (a): the identity agrees with an explicit re-solve to
               better than 1e-8 relative, worst case over a learned basis.
               A derivation, checked -- not a tolerance.

(2) IT MUST REPRODUCE OBS-8 EXACTLY, OR IT IS NOT THE SAME PRIMITIVE

    PREDICTED  G56 (b): `against` on the operator library, at OBS-7's
               basis over the square, returns G55 (a)'s novelties to
               1e-9.  Same numbers or it is a different operation with a
               similar name.

(3) THE THIRD FACE, AND THE CONTRADICTION IT RESOLVES

MARL-7 spent a phase looking for erosion and concluded that kernel death
has nothing to target, because silencing accumulated capacity costs
1.4-1.6x the RMS -- every kernel is load-bearing.  MARL-18 then said the
sharper thing: "a consolidation never chooses a victim, it declines to
rebuild one", because four overlapping kernels whose sum is smooth are all
individually load-bearing and collectively replaceable.

Those two are only in tension if LOAD-BEARING and NON-REDUNDANT are the
same property.  They are not, and the primitive separates them:

    REPRESENTABILITY   can phi_i be reproduced by the others?
                       -- geometric, this is novelty
    CONTRIBUTION       does the error rise if phi_i is DELETED?
                       -- depends on w_i, and MARL-7 measured it by
                          SILENCING, with no refit

A basis can be highly redundant (novelty near zero) while deleting one
member without refitting is expensive, because its weight was carrying
something the others could have carried had they been asked.

    PREDICTED  G56 (c): on a learned MARL, the MEDIAN leave-one-out
               novelty is below 0.5 -- the basis is substantially
               redundant -- which does not contradict MARL-7 and is the
               reason MARL-7 could not find a victim by silencing.

(4) AND THE TEST THAT MAKES IT USEFUL RATHER THAN TRUE

If novelty is the right redundancy measure, it should say WHICH kernels to
remove.  Prune the lowest-novelty kernels, REFIT the remaining weights,
and compare against pruning at random with the identical refit and the
identical count.

    PREDICTED  novelty-guided excess RMS over the unpruned model is at
               most half of random pruning's, at matched count:

                   excess(guided) / excess(random)  <=  0.50

    "excess" is RMS(pruned, refitted) - RMS(unpruned), so a guided prune
    that costs nothing scores zero and the ratio is not flattered by the
    base error.

    This is MARL-18's "declines to rebuild" made into a criterion, and it
    is the one thing here that could fail while everything above holds:
    novelty could be a correct description of redundancy and still be a
    poor ranking, if what matters for removal is the product of
    redundancy and weight rather than redundancy alone.  That would be a
    finding and the remedy would be obvious.

(5) THE GRAM, AND WHY IT IS EXPECTED TO MATTER HERE WHERE IT DID NOT IN OBS-8

G55 (a) found the residualised Gram exactly diagonal, because a square
lattice on a square region is D4-symmetric and the candidates sit in
different irreps.  **A learned MARL basis has no symmetry at all** --
kernels move, are born at exemplars, and are shaped by descent.  So the
mutual channel that was invisible in OBS-8 should be live here.

    PREDICTED  the learned basis's Gram has condition number above 100,
               where OBS-8's residualised library was exactly 1.

    NOT PREDICTED  a number for it.  Conditioning of an overcomplete
                   local basis depends on the birth rule's spacing and
                   the clamp, and no derivation for it is offered.

(6) WHAT IS NOT BEING CLAIMED

The primitive is measured on a MARL fitted to the campaign's own truth,
at a modest budget so the full Gram is tractable exactly.  Nothing here
is a claim about the 47 000-kernel models of G52 (b), where the Gram is
block-sparse and would need MARL's own locality to be exploited -- that
is an implementation question and is deliberately separate from whether
the quantity is the right one.  Birth is discussed and not rebuilt: this
phase measures the primitive, it does not change any default.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
