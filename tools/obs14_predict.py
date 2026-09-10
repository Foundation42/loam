#!/usr/bin/env python3
"""obs14_predict — OBS-14's gate numbers, before its run.

Christian's ordering, and his framing of what consolidation touches:

    Span          what functions the basis can represent
    Placement     where those functions are already useful
    Training state how adapted those functions are

    So far, synthesis is preserving span surprisingly well, partially
    rewriting placement, and throwing away training state entirely.

    Redundancy is not just extra capacity.  It can be STORED ADAPTATION.

and the experiment he put first:

    ratchet:             parent adapts faster, then both consolidate, and
                         the child lineage catches up or overtakes
    damage accumulation: each consolidation throws away useful latent
                         structure and the child lineage keeps paying
                         reacquisition cost

    P0 -wake-> P1 -sleep-> P2        C0 -wake-> C1 -sleep-> C2

    python3 tools/obs14_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-14 — the lineage.  PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) A DESIGN PROBLEM THAT SURFACED BEFORE ANY CODE, AND IT CHANGES THE PHASE

OBS-13 consolidated the child against THE PARENT'S OWN PREDICTIONS, on the
grounds that a child handed the truth would start life knowing what its
parent had to learn.  That was right about the cheating and wrong about the
consequence, and the consequence only becomes visible once sleep has to run
TWICE.

A student fitting its teacher's output can at best MATCH it.  MARL-19
measured exactly this: on a NOISELESS field a sleep is a pure loss, a copy
costs 1.179x, and no student is better than its teacher on both axes.  So
sleep-on-self can never improve held-out error, and a lineage built on it
can only decay.  Every step of OBS-14 would be measuring generation loss.

But OBS-11's consolidation DID improve on the basis it came from — 0.0538
against 0.0572 at three quarters of the kernels — and the reason is that
its target was the TRUTH ON PROBES rather than the model's output.

Which is not cheating either, once it is named properly: **the truth on
probes is what a replay buffer holds.**  A model's own observations are
legitimately its to reuse.  So the honest lifecycle consolidation is
sleep-on-REPLAY, and OBS-13's sleep-on-self was not merely conservative —
it was the wrong operation, and it is why its child could only ever pay.

    This is Christian's replay measure arriving one phase early, in its
    minimal form: not the lambda-weighted mixture over current, recent and
    rare, but simply "consolidate against what you have actually seen".
    The full objective stays where he put it, third.

    PREDICTED  sleep on the model's OWN OUTPUT does not improve held-out
               error: RMS(after) >= RMS(before), per MARL-19
    PREDICTED  sleep on REPLAY does: RMS(after) <= RMS(before)

    The contrast is the assertion.  If sleep-on-self also improves, MARL-19
    does not describe this operation and the low-pass account needs
    revisiting; if sleep-on-replay does not, OBS-11's gain was an artefact
    of a static fixture and the lifecycle claim collapses.

(2) THE LINEAGE

    P0  trained 20k on the campaign truth
    C0  sleep(P0) at half the population, on replay
        the world moves: shift {0, -0.10, 0}
    P1, C1  wake, 60k exemplars each, births on, identical options
    P2, C2  sleep at half, on replay
    P3, C3  a second wake, 20k, to compare adaptation AFTER sleep

The quantity Christian named as crucial is not C2 < P2 on one static test
but whether the sequence forms a monotone improvement loop.  So the
registered number is the GAP TRAJECTORY:

    gen 0, after the first sleep      C/P = 1.009   (OBS-13, measured)
    gen 1, after the first wake       C/P = 1.195   (OBS-13, measured)
    gen 2, after the second sleep     C/P = ?

    PREDICTED (ratchet)   the gap NARROWS at gen 2: C/P < 1.195
    PREDICTED (damage)    it widens or holds

    The agent expects it to narrow, and says so having lost the last two
    disagreements: the child's deficit in OBS-13 was measured to be YOUTH
    (mean updates 1024 against 1551), and a wake of 60k plus a second sleep
    gives that population time to age. If the gap instead widens, the
    deficit is not youth and the OBS-13 mechanism was mis-read.

(3) THE THIRD FACTOR, MEASURED AND NOT YET FIXED

Training-state inheritance is Christian's second item and is NOT built
here. What OBS-14 does is measure the quantity it would act on, at every
stage, so that the later phase has a baseline:

    PREDICTED  mean updates per kernel is lower in the child lineage at
               every generation, and the RATIO converges toward 1 as the
               lineage ages

If the ratio does not converge, no inheritance scheme will help, because
the gap is not an ageing effect.

(4) THE NULLS

    PREDICTED  both lineages consume identical exemplar counts at every
               stage, and every post-sleep population is within 5% of the
               budget it was given
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
