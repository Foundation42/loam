#!/usr/bin/env python3
"""obs15_predict — OBS-15's gate numbers, before its run.

Christian, on OBS-14's qualified reading:

    The lineage data does not yet say "consolidation eventually degrades".
    It says something more specific: CONSOLIDATION QUALITY DEPENDS ON THE
    MATURITY OF THE POPULATION BEING CONSOLIDATED.

    wake -> birth burst -> settling -> consolidation window

    rather than a fixed cadence.

and the guardrail, promoted from a ledger note after its third occurrence:

    every optimisation experiment must name separate fit and evaluation
    measures explicitly, and reject the experiment if any alias
    unintentionally.

    python3 tools/obs15_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-15 — when is a population ready to be rewritten?  PRE-REGISTERED")
print("=" * 74)

print("""
(1) THE GUARDRAIL FIRST, BECAUSE IT IS PLUMBING AND NOT DISCIPLINE

Three times now a result has been measured on the points it was fitted on:
OBS-11's synthesis arm (train 0.00227 against held-out 0.05376), OBS-14's
sleep-target contrast (a fourteen-fold "improvement" that was 0.855x), and
OBS-8's disc, which was a different error of the same family — a measure
that was not what it was named.

`Measures` names the three explicitly and refuses to run if any two share a
point:

    fit_measure     what a descent optimises against
    sleep_measure   what a consolidation preserves
    eval_measure    what the result is scored on

    PREDICTED  the check FIRES on an aliased set — asserted with a
               deliberate alias, so the guardrail is not itself decoration

(2) THE SWEEP

One wake trajectory from a common trained parent on a MOVED world, with a
fork consolidated at each checkpoint. Same model, same stream, same sleep,
only the amount of settling differs:

    checkpoints  2k, 5k, 10k, 20k, 40k, 80k exemplars into the wake

At each: readiness before sleeping, held-out RMS before and after.

    gain = 1 - RMS(after) / RMS(before)

(3) READINESS, AND WHY A MEAN WILL NOT DO

A post-wake population is heterogeneous — old kernels, newly born ones,
partly adapted ones — so a mean update count averages exactly the thing
that matters. Christian's scalar is contribution-weighted:

    R = 1 - sum_i w_i [u_i < u_min] / sum_i w_i

the share of the model's OUTPUT that rests on immature kernels. Reported at
u_min in {16, 64, 256} so the shape is visible rather than a single number
standing in for it, with the coefficient of variation of update counts and
the recent birth rate beside it.

(4) THE PREDICTION

    PREDICTED  the gain CROSSES ZERO: negative at the shortest wake,
               positive at the longest.  A crossover is the claim; a sweep
               that is positive throughout would mean OBS-14's second sleep
               failed for some other reason, and one negative throughout
               would mean sleeping after a move never pays.

    PREDICTED  readiness ORDERS the gain: the correlation between R (at
               u_min = 64) and gain is positive across the sweep.

    NOT PREDICTED  where the crossover sits. That is the number the phase
                   exists to find, and guessing it would waste it.

(5) WHAT THIS WOULD LICENSE

If the crossover exists and readiness tracks it, "do not sleep too soon"
stops being an observation and becomes a policy with a measurable trigger.
It also un-confounds the ratchet test, which Christian correctly moved to
fourth: a lineage compared at a FIXED cadence is comparing consolidations
of populations at different maturities, and OBS-14's second sleep is
exactly that.

(6) NOT CLAIMED

One move, one fixture, one budget fraction (half). The sweep varies WHEN,
not HOW MUCH, and the two plainly interact — a mature population might
tolerate a deeper cut. Effective-age inheritance is Christian's second item
and is not built here, so the youth penalty this phase measures is the
uncorrected one.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
