#!/usr/bin/env python3
"""obs11_predict — OBS-11's gate numbers, before its run.

Christian, settling OBS-10:

    geometry    -> how many dimensions exist
    objective   -> which dimensions matter
    distillation-> how to synthesise a better basis for them

    r_eff was never the selector; it is the BUDGET ESTIMATOR.

and naming the next rung as one sharp hypothesis:

    Synthesised representatives should dominate selected representatives
    when redundancy is distributed across several individually imperfect
    kernels.

with the threshold that makes it matter:

    If the distilled arm wins at equal cardinality, then you have
    demonstrated something qualitatively stronger than pruning:
    consolidation can improve basis QUALITY, not merely reduce basis SIZE.

    python3 tools/obs11_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-11 — synthesis.  PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) THE MECHANISM, AND WHY IT IS WARM-STARTED FROM THE BASELINE

Per cluster: budget k from r_eff (OBS-10), members chosen by the
target-conditioned residual (OBS-10), and then -- this is the new part --
those k kernels are allowed to MOVE. Gradient descent on every parameter
they have (centre, log-diagonal, off-diagonal, weight) against the target
over the probes, using `marl.gradOne`, so the result is a set of kernels in
MARL's own family and nothing else.

Warm-started from OBS-10's winner ON PURPOSE. The comparison is then
exactly "selection" against "selection then refinement", so any win is
unambiguously attributable to the synthesis and cannot be an accident of
where the new elements were initialised. A + B + C + D -> X + Y, where X
and Y began life as A and C and did not stay there.

    NOT DONE  a from-scratch fit of new elements, or MARL-14's full
              distillation loop. Both change two things at once.

(2) THE HEADLINE

    PREDICTED  distilled <= selected at every pruning fraction, measured
               as excess RMS over the full basis's refit divided by
               random's -- OBS-10's scale, where selected reads
               .321 / .328 / .412 at a quarter, a half and three quarters

               ratio distilled/selected <= 0.80 at every fraction

(3) THE CONDITIONAL, WHICH IS THE ACTUAL HYPOTHESIS

Christian's claim is not that synthesis always wins; it is that it wins
WHERE REDUNDANCY IS DISTRIBUTED. That is measurable BEFORE any fitting,
from the eigendecomposition already computed:

    E_opt  the target energy the cluster's true top-k SUBSPACE captures
    E_sel  the target energy its best k MEMBERS capture

    spread = 1 - E_sel / E_opt

Near zero, k existing members already are the top-k subspace and there is
nothing for synthesis to buy. Large, and the subspace is a COMBINATION no
member realises alone -- which is exactly "redundancy distributed across
several individually imperfect kernels".

    PREDICTED  the per-cluster gain from synthesis correlates with
               `spread`: clusters in the top third by spread gain at least
               2x what clusters in the bottom third gain

    That is the discriminating test. If synthesis wins uniformly, it is a
    better optimiser and not a better DECOMPOSITION, and the three-stage
    story is decoration.

(4) THE THRESHOLD CHRISTIAN NAMED

    PREDICTED  at a QUARTER pruned, the distilled basis reaches an RMS no
               worse than the FULL basis's refit:

                   RMS(distilled, 75% of the kernels) <= RMS(full)

    If that holds, consolidation is not compression with a loss -- it is a
    strictly better representation at strictly lower cost, and "sleep"
    stops being a metaphor. The overcomplete daytime basis really is worse
    than what can be built from it overnight.

    NOT PREDICTED  the same at three quarters pruned. A fourfold cut
                   should still cost something, and if it does not the
                   fixture was over-parameterised rather than the method
                   good.

(5) THE NULL

    PREDICTED  training loss falls monotonically over the descent, and the
               refined kernels stay inside the clamp MARL's own gather
               requires (reach <= one region edge).

    A synthesis that wins by leaving the family is not a MARL, and a
    kernel whose support outgrows the gather silently breaks exact
    locality -- G44 (b) found that exact failure in the affine warp and
    counted it rather than hiding it. Same discipline here.

(6) MYOPIA, RECORDED AND NOT ADDRESSED

Christian: "your current target-selection rule is still choosing according
to the present target. If the system is dynamic, that makes consolidation
potentially myopic."

Right, and untouched here. The objective is one static target y. Widening
it to a replay measure Y = {y_t, y_{t-1}, ...} or to the residual over a
recent window is the obvious next axis and OBS-11 does not take it, so
that synthesis is measured before the objective is generalised. The
statement being tested stays:

    the measure defines WHERE, the spectrum defines HOW MUCH,
    the objective defines WHAT TO PRESERVE
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
