#!/usr/bin/env python3
"""obs10_predict — OBS-10's gate numbers, before its run.

Christian, on OBS-9's batch failure:

    For a set C of candidate basis elements, the question is no longer
    "which diagonal entries are small?" but "how much dimension does C
    actually add?"  That is spectral.

    You are no longer deleting weak kernels.  You are performing LOCAL
    RANK REDUCTION.

    individuals live on the diagonal; representations live in the spectrum

with the batch quantity named: effective rank under the observation
measure,

    r_eff = exp( - sum_i p_i log p_i ),   p_i = lambda_i / sum_j lambda_j

so that a cluster of eight kernels with effective rank 2.3 is asking to be
replaced by two or three.

That is the mathematical form of A + B + C + D -> X + Y, and it is what
OBS-9 was missing: the diagonal ranks members, the spectrum sizes the SET.

    python3 tools/obs10_predict.py
"""

import math

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-10 — local rank reduction.  PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) THE MECHANISM, AND WHERE EACH PIECE COMES FROM

Per cluster C (a MARL region's own kernels, which is the model's native
locality and needs no new constant):

    1. sample the members at the probes -> Phi_C
    2. Gram, eigenvalues, r_eff by the entropy above
    3. allocate k_C = the cluster's share of the budget, IN PROPORTION TO
       r_eff rather than to membership
    4. select k_C members spanning the cluster's dominant subspace
    5. refit every surviving weight globally

Step 4 is the OBS-9 primitive again, used inside the cluster: greedily take
the member with the highest novelty AGAINST THOSE ALREADY CHOSEN.  That is
pivoted QR, and it means the same operation ranks candidates, measures
redundancy and now performs the selection.

Step 5 is why this is a REPLACEMENT and not a deletion.  The survivors'
weights after the refit are not the weights they had; two kernels come out
carrying what four carried.  A + B + C + D -> X + Y, with X and Y drawn
from the originals rather than synthesised.  Synthesising genuinely new
representatives is MARL-14's distillation and is deliberately NOT done
here, so that the rank decision is measured apart from the fitting of new
elements.

(2) THE ORDERING, WHICH IS CHRISTIAN'S PREDICTION

Stated by him in quality; restated here in the measured quantity, which is
excess RMS over the unpruned refit divided by random's, so LOWER IS BETTER
and the inequality reverses:

    batch diagonal  >  random  >  staged diagonal  >=  spectral

    known from OBS-9 at half the population:
        batch  1.3029      random  1.0 (the denominator)      staged  0.6977

    PREDICTED  spectral <= staged at 50% and at 75%
    PREDICTED  the full ordering holds at 50%

(3) THE CROSSOVER, WHICH IS THE USEFUL PART

Christian: "it would be very useful if the spectral method only wins once
the pruning fraction becomes large enough.  That would tell you where the
extra linear algebra actually pays for itself."

Registered as a crossover rather than a win, because a method that wins
everywhere says nothing about when to reach for it:

    PREDICTED  at 25%   spectral within 10% of staged, either way
                        |spectral/staged - 1| <= 0.10
    PREDICTED  at 75%   spectral beats staged by at least 10%
                        spectral/staged <= 0.90

    The reasoning: at a light prune almost every cluster keeps enough
    members to span itself, so the allocation has nothing to decide and
    both methods are removing the same nearly-redundant tail.  At a heavy
    prune the budget is scarce, and PROPORTIONING it by dimension rather
    than by rank order is the whole difference.

(4) THE CLUSTERS MUST ACTUALLY BE LOW-DIMENSIONAL, OR THERE IS NOTHING TO DO

    PREDICTED  mean r_eff / (members) <= 0.70 across a learned model's
               regions

If a cluster of k members carries k effective dimensions there is no rank
to reduce and the whole phase is measuring an allocation of nothing.  This
is the precondition and is registered first for that reason.
""")

for k, shape in ((8, "flat, 8 equal eigenvalues"),
                 (8, "one dominant, rest 1/20"),
                 (8, "geometric, ratio 0.5")):
    if "flat" in shape:
        lam = [1.0] * k
    elif "dominant" in shape:
        lam = [1.0] + [0.05] * (k - 1)
    else:
        lam = [0.5 ** i for i in range(k)]
    tot = sum(lam)
    p = [x / tot for x in lam]
    h = -sum(pi * math.log(pi) for pi in p if pi > 0)
    print(f"    r_eff of {shape:<28} = {math.exp(h):.3f}  (k = {k})")

print("""
(5) THE WORK, AND WHY LOCALITY SHOULD MAKE THE EXPENSIVE METHOD THE CHEAP ONE

Staged diagonal factorises the WHOLE basis once per stage: eight Choleskys
of 623 x 623.  Spectral factorises each REGION separately: twenty-seven
eigenproblems of about 23 x 23, which is block-diagonal by construction
because kernels in distant regions do not overlap at all.

    623^3 * 8   ~ 1.9e9        against        27 * 23^3  ~ 3.3e5

    PREDICTED  spectral's selection costs less wall clock than staged's,
               by at least 5x

So the method with more linear algebra in its description has less of it in
its execution, and the reason is MARL's own locality. If that fails, the
refit dominates both and the comparison is about the refit.

(6) THE FROZEN THRESHOLD, VALIDATED ON AN UNSEEN FIXTURE

Christian: "freeze 1e-6 now and make the next unseen fixture the actual
validation of it."  `OBS9_SAME_PRIMITIVE` was moved from 1e-9 to 1e-6 after
observing a failure, with the numerical reason identified and the
replacement derived from the observed separation scale.  It is frozen, and
G57 re-checks it on a basis G56 never saw -- OBS-8's axis-B 5x5 lattice on
[0,1] rather than OBS-7's 3x3 on [.25,.75].

    PREDICTED  the generic primitive reproduces `law.analyse` on that
               basis to within 1e-6, with no further adjustment

(7) WHAT IS NOT BEING CLAIMED

Clusters are MARL's own regions, so cross-region overlap at the faces is
neglected: a kernel near a boundary is analysed with its own region's
members and not its neighbours'. That is a real approximation and the
honest alternative -- connected components of the Gram above some
threshold -- needs a constant this phase does not want. No default changes.
Representatives are SELECTED, never synthesised.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
