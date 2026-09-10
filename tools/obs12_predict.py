#!/usr/bin/env python3
"""obs12_predict — OBS-12's gate numbers, before its run.

Christian, sharpening OBS-11's language and naming the next two tests:

    I would now sharpen the language from "distillation" to CONSOLIDATION
    WITH REPRESENTATIONAL IMPROVEMENT.  It means redundancy was not merely
    dead weight.  It was useful during acquisition, but suboptimal as the
    final representation.

(a) THE CONDITIONAL, on a fixture built to be brutal about it:

    cluster A: almost orthogonal members
    cluster B: moderately overlapping
    cluster C: nearly duplicate members
    cluster D: deliberately anisotropic / cross-region

    ...ask whether synthesis gain is monotonic with a properly measured
    cluster redundancy statistic ... attribution should follow ACTUAL
    SUPPORT under the observation measure, not administrative ownership by
    region.  Region membership is implementation topology; support overlap
    is the geometry that matters.

(b) THE CONDITIONING MATRIX, to tell two diagnoses apart:

    Is the win limited by VARIANCE?          more probes, same optimiser
    Is the parameterisation UNDERCONSTRAINED? same probes, regularise

    python3 tools/obs12_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-12 — when does consolidation pay?  PRE-REGISTERED")
print("=" * 74)

print("""
(1) TWO COMPETING PREDICTIONS, AND THE AGENT DISAGREES WITH CHRISTIAN

Christian's, as written: synthesis gain is MONOTONIC in cluster redundancy
-- most where members are most redundant.

The agent's, and the reason is geometric rather than empirical: the gain
should be NON-MONOTONIC, peaking at INTERMEDIATE redundancy, because both
extremes are already solved by selection.

    A  nearly ORTHOGONAL members.  At budget k = cardinality the members
       ARE the cluster; there is no subspace a moving kernel could reach
       that a standing one cannot.  Gain ~ 0.

    C  nearly DUPLICATE members.  One member is already almost the whole
       cluster, so the best-k selection is already almost optimal and
       there is very little left for a moved kernel to recover.
       Gain small.

    B  MODERATE overlap.  The SUM of eight partly-overlapping Gaussians is
       a smooth object that NO SINGLE MEMBER RESEMBLES -- and one wider,
       better-placed Gaussian can approximate it far better than any of
       them.  This is the case Christian's own sentence describes
       ("redundancy distributed across several individually imperfect
       kernels") and it is in the MIDDLE of the redundancy axis, not at
       its end.

    PREDICTED (agent)     gain(B) > gain(C) and gain(B) > gain(A)
    PREDICTED (Christian) gain(C) > gain(B) > gain(A)

    They differ on ONE comparison -- B against C -- and that is the whole
    experiment.  Both agree A is lowest.

    The right axis is not redundancy but SPREAD: how far the target's
    projection onto the cluster's span sits from any single member.  r_eff
    is small at BOTH extremes for different reasons, which is precisely why
    it is a budget estimator and not a payoff predictor (OBS-10's lesson,
    one level in).

(2) THE FIXTURE, BUILT TO SEPARATE THEM

Four clusters, eight members each, EQUAL TOTAL TARGET ENERGY, in disjoint
parts of the cube so that attribution cannot be the confound:

    A  spacing 4.0 sigma   nearly orthogonal
    B  spacing 1.2 sigma   moderate overlap
    C  spacing 0.15 sigma  near duplicates
    D  anisotropic, elongated and crossed

Each cluster is consolidated against ITS OWN contribution, in isolation, so
a gain is unambiguously that cluster's. Budget k = 3 of 8 everywhere, so
the pruning fraction is identical and only the internal geometry differs.

    PREDICTED  r_eff/k: A near 1.0, C near 0.15, B in between
    PREDICTED  every arm scored on HELD-OUT probes, as OBS-11 had to learn

(3) ATTRIBUTION BY SUPPORT, NOT BY OWNERSHIP

OBS-11 attributed probes to clusters by which REGION owned them, which is
administrative topology, and its conditional came out at 1.24x against a
registered 2x. Here a probe belongs to the cluster whose members produce
the largest total response there -- the measure's own geometry.

    PREDICTED  on OBS-11's own model, support attribution and region
               attribution disagree on at least 10% of probes

    If they agree almost everywhere, OBS-11's weak conditional was not an
    attribution artefact and the honest reading is that its fixture simply
    had no contrast -- which is what this phase's fixture is for.

(4) THE CONDITIONING MATRIX

Three regularisation strengths x two probe counts, on OBS-11's own model at
half pruned, everything else identical. Regularisation is PROXIMAL to the
warm start -- a penalty on how far a kernel may move from the ancestor it
began as -- because that is the quantity the phase is actually uncertain
about, and it needs no new notion of what a "large" parameter is.

    PREDICTED  synthesis still beats selection in every cell of the matrix
               (the ORDERING is stable under conditioning)

    PREDICTED  doubling the probes improves synthesis by at least 3%,
               so the reported 11-15% is CONSERVATIVE

    NOT PREDICTED  which of the two diagnoses dominates. That is what the
                   matrix is for and guessing it in advance would waste it.

    The outcome Christian flagged as most interesting is registered so it
    cannot be claimed after the fact: if the FULL basis improves LESS than
    the consolidated one as probes increase, consolidation is acting as
    STRUCTURAL REGULARISATION rather than numerical compression.

(5) RECORDED, NOT TESTED: THE TWO-PHASE READING

Christian: "the overcomplete 623-kernel model may actually be the better
LEARNING representation, while the 311-kernel model is the better INFERENCE
representation ... redundancy may be scaffolding."

That is the most consequential idea on the table and OBS-12 does not test
it, because testing it means resuming LEARNING from a consolidated model
and comparing against resuming from the overcomplete one -- which is
MARL-18's wake/sleep loop with a better consolidation step, and a phase of
its own. Registered here so that it is not quietly absorbed into this one's
conclusions.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
