#!/usr/bin/env python3
"""obs24_predict — OBS-24's design and numbers, before its run.

OBS-23 left one thing localised and unattributed. On acquisition 5678 the
`sleep@t+r` arm ran

    t = 94 000   0.16067      <- the last checkpoint BEFORE the sleep
    t = 96 000   0.92824      <- the first checkpoint AFTER it
    t = 98 000   0.90681
    t = 100 000  0.21799
    t = 102 000  0.25972
    t = 104 000  0.20848

with its third consolidation at **t = 94 096** and **zero guard rejections**
— so the refinement DESCENDED on replay and was accepted.

That is the measurement OBS-22 said it did not have.  OBS-22 established
that a replay-loss acceptance rule prevents a diverging refinement, and
recorded explicitly that this does *not* establish that a descent which
*does* descend on replay improves the current world.  Here is a case where
it descended, was accepted, and the world went to 0.93.

**OBS-24 forks that one consolidation.**  No further full-lattice run.

    python3 tools/obs24_predict.py
"""

# ── THE FORK POINT ────────────────────────────────────────────────────────
ARM = "sleep@t+r"
ACQ = 5678
FORK_AT = 94_096          # the third consolidation, intervention index 2
TOTAL = 104_000
CHECK = 2000
REMAINING = [96_000, 98_000, 100_000, 102_000, 104_000]

# The OBS-23 arm's own values at those instants, AS PRINTED — five decimals,
# rounded. The guarded branch IS that arm, so these are a CONTRACT ON THE
# HARNESS and not predictions: if the fork does not reproduce them the
# continuation is not the arm's. **Asserted at the recorded precision**
# (|difference| < 1e-5), because full precision was never written down; the
# gate prints its own at more digits so a future comparison can be tighter.
OBS23_GUARDED = [0.92824, 0.90681, 0.21799, 0.25972, 0.20848]
OBS23_PARENT_AT_94000 = 0.16067
# The arm's own band over the three checkpoints before the sleep, which is
# what "no excursion" has to be judged against.
OBS23_PRESLEEP_BAND = (0.13452, 0.23044)

# ── THE CONTRACT ASTRA PINNED, AND WHY SEEDS ARE NOT ENOUGH ──────────────
#
# `guarded` and `linear-only` must differ in the REFINEMENT AND NOTHING
# ELSE.  Running two arms from the same seed and trusting determinism is a
# weaker guarantee than constructing them from the same object, and the
# campaign has already paid for the difference between "the same by argument"
# and "the same by assertion" (OBS-21's ring).
#
# `sleepOnReporting` makes the stronger construction available, because the
# post-linear-refit candidate is a concrete thing:
#
#     select kernels per region        -> out.items
#     sample, solve, write weights     -> out.items IS the linear candidate
#     dupe it                          -> the snapshot (already exists under
#                                         `Options.guard`)
#     refine in place                  -> the attempted refinement
#     accept or restore from the dupe  -> the returned candidate
#
# So OBS-24 runs the consolidation ONCE, snapshots the linear candidate, and
# builds both branches from those exact bytes:
#
#     linear   = adopt(snapshot)
#     guarded  = adopt(out.items after refine and acceptance)
#
# **Asserted, not assumed:** both branches see the identical selected buffer
# (same pointer, same contents), and `linear`'s kernels equal the snapshot
# byte for byte.

# ── THE FOUR MEASUREMENT POINTS, IN TWO MEASURES EACH ────────────────────
#
# **The two measures use DIFFERENT LABELS and that is the point of having
# both.**
#
#   * REPLAY loss is scored on the selected buffer against ITS OWN STORED
#     LABELS, exactly as the consolidation fitted them — historical, drawn
#     when each point was observed. Nothing is relabelled. This is the
#     quantity the acceptance rule reads.
#   * WORLD error is scored on HELD-OUT probes against completion-time
#     truth at t = 94 096.
#
# An earlier draft said both were taken "against the same completion-time
# world", which reads as an oracle relabelling of the replay buffer. There is
# no oracle anywhere in this fork.
#
# What IS held fixed is the world the held-out measure uses: t = 94 096 is
# past `drift_hi`, so the world is stationary there and no part of any
# world-error difference below is the world moving. All four points use the
# same probe set.
POINTS = [
    ("parent",    "the model entering the consolidation"),
    ("linear",    "after selection and the linear refit"),
    ("attempted", "after the refinement, BEFORE acceptance — measured even if rejected"),
    ("returned",  "what the branch actually adopts"),
]
MEASURES = [
    ("replay", "RMS over the selected buffer the consolidation fitted"),
    ("world",  "RMS over held-out probes against the completion-time world"),
]
# `attempted` is the point OBS-22 could not see: its replay loss was kept
# (`Report.last`) but its kernels were discarded before anything scored them
# against the world.

# ── THE THREE BRANCHES ────────────────────────────────────────────────────
BRANCHES = [
    ("skip",    "no consolidation; THE ACTUAL PARENT continues, not a copy"),
    ("linear",  "selection and the linear refit only, zero descent steps"),
    ("guarded", "the registered recipe: refine, accept on replay loss"),
]
# **`skip` must continue the parent OBJECT, with its complete learning state
# intact.** Rebuilding it as `adopt(parent.kernels)` would silently reset per
# kernel Adam moments `m1`/`m2`, the step counter `t`, `updates` and the
# drift origin `mu0`, and would hand it a fresh `Model` — fresh `stats`, a
# fresh model RNG stream, and a fresh `recent` residual ring, WHICH GATES
# BIRTHS. That branch would then be "adopt without consolidating", which is
# an intervention of its own and not the control.
#
# `adopt` is the right construction for the two consolidated candidates,
# because a consolidation does exactly that. The asymmetry is faithful, not
# a flaw: it is what the two policies differ by.
#
# The consolidation READS the parent and returns a new model without
# mutating it, so one prefix run can supply all three branches.
# All three then continue to t = 104 000 on **identical fresh queries** — the
# consolidation costs no observations in this arm, so the three branches
# observe the same 9904 locations at the same paid times, and are scored at
# the same five checkpoints.

# ── REGISTERED QUESTIONS ──────────────────────────────────────────────────

# Q1  THE CENTRAL ONE, and the one OBS-22 named as missing.
#     Does the accepted refinement LOWER replay loss while RAISING
#     same-world error?  PREDICTED YES on both halves.
#
#     The first half is near-tautological given zero rejections (acceptance
#     requires `last <= first`) and is asserted as a CONTRACT.  The second
#     half is the prediction: world(attempted) > world(linear).
#     **Acceptance establishes NON-INCREASE, not strict descent.** The rule
#     rejects on `last > first` or non-finite, so acceptance gives
#     `replay(attempted) <= replay(linear)` and no more. That inequality is
#     the CONTRACT. Whether the refinement strictly DECREASED replay loss is
#     a separate thing, measured and reported rather than assumed.
Q1_REPLAY_NON_INCREASE = True     # contract
Q1_REPLAY_STRICT_DECREASE = None  # measured, not predicted
Q1_WORLD_RISES = True             # the prediction

# Q2  Is the damage IMMEDIATE, or does it emerge over the following
#     observations?  world(returned) > world(parent), same instant, same
#     probes.  PREDICTED IMMEDIATE.  Sign only — no magnitude is derivable,
#     because nothing in OBS-23 scored the model between 94 000 and 96 000.
Q2_IMMEDIATE = True

# Q3  Is the REFINEMENT responsible?  max(linear over REMAINING) <
#     max(guarded over REMAINING).  PREDICTED YES.
#
#     **"max" is the maximum over the FIVE CHECKPOINTS and nothing more.**
#     It cannot exclude an excursion between them: the model is scored every
#     2000 observations and is unobserved in between.
#
#     OBS-22's fork at ITS failing sleep found `norefine` far better than the
#     registered recipe (0.09896 against 0.37240). That recipe was UNGUARDED:
#     its refinement RAN AND FAILED, and `norefine` was compared against that
#     failed result. The guarded row is separate, and restored the linear
#     candidate — which is why `guarded` and `norefine` agree to every digit
#     there.
#
#     So the distinction here is NOT accepted-versus-restored. It is that
#     OBS-22's refinement INCREASED replay loss (0.13965 -> 0.35844) while
#     this one did not increase it at all — and damaged the world anyway.
Q3_REFINEMENT_RESPONSIBLE = True

# Q4  Does consolidating at all damage, from this parent?
#     max(skip over REMAINING) < max(guarded over REMAINING), PREDICTED YES;
#     and separately max(skip) < 0.30, registered from the arm's own
#     pre-sleep band of 0.13452..0.23044 with margin.  The second can be
#     refuted alone: it says `skip` shows no excursion AT ITS CHECKPOINTS
#     rather than merely a smaller one — again, five samples, and nothing
#     between them.
Q4_SKIP_BETTER = True
Q4_SKIP_CEILING = 0.30

# Q5  Damage against recovery.  Guarded's recovery is already visible in
#     OBS-23 (0.92824 -> 0.20848) and is a contract, not a prediction.  The
#     registered question is whether recovery is COMPLETE:
#     guarded(104 000) > skip(104 000).  PREDICTED YES — the damage is not
#     fully repaid within the remaining horizon.
Q5_INCOMPLETE_RECOVERY = True

# Q6  Does the linear refit alone HELP, relative to not consolidating?
#     mean(linear over REMAINING) < mean(skip over REMAINING).
#     PREDICTED YES, from OBS-22's fork where the linear refit alone beat
#     skipping (0.09896 against 0.11174).  Direction only.
Q6_LINEAR_HELPS = True

# ── WHAT THIS CANNOT SAY ──────────────────────────────────────────────────
#
# **The conclusion is conditional on the parent the earlier sleeps
# produced.**  This forks ONE consolidation, on ONE trajectory, from a model
# shaped by two consolidations before it.  A refinement that damages this
# parent says nothing about refinements in general, and nothing here
# exonerates or implicates the first two sleeps: they built the state that
# fails.
#
# It is also not a timing experiment.  OBS-23's C6 remains a contrast
# between two complete schedules; this fork holds the schedule fixed and
# varies only what happens at one of its sleeps.
#
# And `skip` is not "the right policy" if it wins.  It is the branch that
# declines to spend, on one parent, over 9904 remaining observations.


def main() -> None:
    print(__doc__.rstrip())
    print()
    print(f"  fork: {ARM} / acq {ACQ}, intervention index 2, t = {FORK_AT}")
    print(f"  continue all three branches to t = {TOTAL} on identical fresh queries")
    print()
    print("  the four measurement points, each in two measures — replay on the")
    print("  buffer's OWN historical labels, world on held-out probes against")
    print(f"  completion-time truth (t = {FORK_AT}, past drift_hi, so stationary)")
    print("  " + "-" * 72)
    for name, note in POINTS:
        print(f"  {name:<11} {note}")
    for name, note in MEASURES:
        print(f"    {name:<9} {note}")
    print()
    print("  the three branches")
    print("  " + "-" * 72)
    for name, note in BRANCHES:
        print(f"  {name:<11} {note}")
    print()
    print("  HARNESS CONTRACTS, asserted — not predictions")
    print("  " + "-" * 72)
    print("  guarded reproduces the OBS-23 arm at every remaining checkpoint:")
    print("    " + "  ".join(f"{t}:{v:.5f}" for t, v in zip(REMAINING, OBS23_GUARDED)))
    print("  linear's kernels equal the post-linear snapshot BYTE FOR BYTE")
    print("  both branches consolidate from the IDENTICAL selected buffer")
    print("  replay(attempted) <= replay(linear) — acceptance gives NON-INCREASE only")
    print("  skip continues the PARENT OBJECT; only the consolidated candidates are adopted")
    print()
    print("  registered questions")
    print("  " + "-" * 72)
    print("  Q1  world(attempted) > world(linear), replay not increased  PREDICTED YES")
    print("  Q2  world(returned)  > world(parent)                      PREDICTED YES (immediate)")
    print("  Q3  max(linear)      < max(guarded)   [max over 5 checks]  PREDICTED YES")
    print(f"  Q4  max(skip)        < max(guarded), and < {Q4_SKIP_CEILING}   [5 checks] PREDICTED YES")
    print("  Q5  guarded(104000)  > skip(104000)                       PREDICTED YES (recovery incomplete)")
    print("  Q6  mean(linear)     < mean(skip)                         PREDICTED YES")
    print()
    print(f"  parent's last pre-sleep checkpoint: {OBS23_PARENT_AT_94000:.5f}")
    print(f"  its pre-sleep band:                 {OBS23_PRESLEEP_BAND[0]:.5f} .. {OBS23_PRESLEEP_BAND[1]:.5f}")
    print()
    print("  CONDITIONAL ON THE PARENT THE EARLIER SLEEPS PRODUCED. One")
    print("  consolidation, one trajectory, one parent — and the first two sleeps")
    print("  are neither exonerated nor implicated: they built the state that fails.")


if __name__ == "__main__":
    main()
