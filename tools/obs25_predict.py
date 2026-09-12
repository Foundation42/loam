#!/usr/bin/env python3
"""obs25_predict — OBS-25's design and numbers, before its run.

OBS-24 established that at one parent, both consolidation stages reduced
historical replay RMS while increasing current-world RMS, and that refinement
alone increased world RMS from 0.27473 to 0.86959.  The guard behaved exactly
as specified: replay non-increase is **insufficient** for current-world
protection.

The obvious response is a better acceptance rule.  **This phase does not
build one.**  It asks a narrower question:

    Do historical validation evidence and two sources of current-labelled
    evidence RANK A COMMON, EXPLICITLY CONSTRUCTED candidate set differently?

That is all it can be.  Astra's framing, after a first draft whose held-out
split was incoherent.

    python3 tools/obs25_predict.py
"""

# ── THE CONSTRUCTION, AND WHY OBS-24'S CANDIDATES CANNOT BE REUSED ───────
#
# **The first draft was incoherent.**  OBS-24's candidates were fitted using
# the WHOLE selected buffer, so taking a split of that buffer afterwards does
# not make it held out of anything.  Two coherent options existed:
#
#   (a) keep OBS-24's exact candidates and call the split a TRAINING-BUFFER
#       diagnostic — honest, but not a held-out experiment;
#   (b) exclude the validation entries BEFORE kernel selection, linear
#       refitting and refinement, and build ONE SHARED CANDIDATE SET that
#       every family is genuinely held out of.
#
# OBS-25 takes (b), which is the experiment that was wanted.
#
# **These are therefore NEW CANDIDATES.**  They are fitted on a smaller
# buffer than OBS-24's, so OBS-24's world figures are context and nothing
# more: this phase MEASURES the diagnostic ordering of its own candidates and
# asserts none of OBS-24's numbers.
#
# The exclusion covers BOTH historical families.  If the recent-window
# entries stayed in the fit while the held-out ones were removed, a
# historical-versus-recent comparison would vary label age AND fitting
# overlap together, and neither could be read.
FORK_AT = 94_096
W = 16_384
N = 8_192          # selected buffer size, as OBS-18..24
V = 256            # per validation family
K = 8              # independent FRESH draws, for sampling variability

# The exclusion set, fixed once so that one candidate set serves every
# family: V entries designated held-out replay, plus every buffer entry whose
# observation is among the V most recent in the window.
EXCLUDED = "the V held-out replay entries, plus any buffer entry among the V most recent observations"

CANDIDATES = [
    ("parent",  "the model entering the consolidation; adopting it IS declining"),
    ("linear",  "selection, compression and the linear refit on the REDUCED buffer"),
    ("refined", "the refinement on top of that same reduced-buffer candidate"),
]

# ── Q0, WHICH COMES FIRST AND MAY END THE PHASE ──────────────────────────
#
# Does the reduced-fit refined candidate still damage the current world?
# A smaller fit set is a different consolidation, and it may simply not
# reproduce OBS-24's failure.  **If it does not, the discrimination question
# is moot at this fork and the phase reports that** rather than treating it
# as a setback.  Registered first so it cannot be quietly skipped.
Q0_STILL_HARMS = True   # predicted, and refutable alone

# ── THE THREE FAMILIES, AND WHAT ACTUALLY SEPARATES THEM ─────────────────
#
# **A correction to the first draft, and it changes the whole reading.**  The
# fork is at t = 94 096 and the drift ends at t = 90 000, so the V most recent
# observations in the window span 93 840..94 096 — ALL of them post-drift,
# under the SAME STATIONARY WORLD as the decision.
#
# So `fresh` is NOT the only family carrying current-world labels.  Recent
# and fresh differ in PRIOR LEARNING EXPOSURE, possible FITTING OVERLAP and
# SAMPLED LOCATIONS — not in label currency, on this fixture.
WINDOW_SPAN = (FORK_AT - W, FORK_AT)      # 77 712 .. 94 096
DRIFT_HI = 90_000
RECENT_SPAN = (FORK_AT - V, FORK_AT)      # 93 840 .. 94 096, all post-drift

FAMILIES = [
    ("held-out replay",
     "V entries of the selected buffer, excluded from the fit",
     f"drawn from {WINDOW_SPAN[0]}..{WINDOW_SPAN[1]}, spanning the drift",
     "historical labels of MIXED currency; already learned from when they arrived",
     0),
    ("recent window",
     f"the V most recent observations, {RECENT_SPAN[0]}..{RECENT_SPAN[1]}",
     "all POST-drift, so current-world labels",
     "already learned from; locations are wherever the stream happened to go",
     0),
    ("fresh",
     f"V newly drawn queries over [{FORK_AT}, {FORK_AT + V})",
     "current-world labels, NOT yet learned from",
     "freshly sampled locations; costs V paid observations",
     V),
]
# The factorisation this gives, stated so no result is over-read:
#   held-out vs recent : varies LABEL AGE (drift-spanning against post-drift)
#   recent vs fresh    : varies PRIOR LEARNING EXPOSURE and LOCATION SAMPLING
# Nothing here varies label currency alone.
#
# **An age statistic is not a wrong-label fraction.**  Roughly three quarters
# of the window predates the end of the drift; how many of those labels are
# actually wrong for the current world is NOT measured, and the two must not
# be conflated.

# ── THE CLOCK, PINNED ─────────────────────────────────────────────────────
#
# Fresh validation queries are PAID OBSERVATIONS and advance the common
# clock.  They occupy [94 096, 94 352) — not an instant.
#
#   * candidates stay FROZEN while the V queries are collected and scored;
#   * the decision is taken at t = 94 352;
#   * the adopted candidate then trains on those ALREADY-PAID observations,
#     charged once and not twice;
#   * every continuation runs the remaining 9648 queries.
#
# **All three families' continuations start at 94 352 having trained on the
# same 256 observations**, so the decisions are compared on a common clock.
# The historical families would not have paid that cost in deployment; that
# differential is REPORTED as Q4 rather than folded into the comparison.
#
# Because a continuation depends only on WHICH candidate was adopted, three
# continuations suffice and each family's outcome is a lookup.
DECIDE_AT = FORK_AT + V                      # 94 352
REMAINING_AFTER = 104_000 - DECIDE_AT        # 9 648
CHECK = 2000
# **A DESIGN CONSTRAINT, not an observation:** no checkpoint may fall inside
# the validation span, or a score would land on a candidate about to be
# replaced.  The registered fixture satisfies it (94 096 % 2000 = 96, and the
# next checkpoint is 96 000) and G72 (a) ASSERTS it, so a future placement
# that broke it would fail the gate rather than silently mis-score.  The
# cheap gate's own first placement DID break it and was moved.
#
# And the historical families must receive NO SECOND TRAINING PASS: their
# entries were learned from when they arrived, and validation SCORES them,
# never observes them. Asserted by checking the candidates' summed kernel
# updates are unchanged across all scoring.

# ── THE FROZEN CRITERION, NOW TOTAL ──────────────────────────────────────
#
# One rule, applied identically to every family, frozen before any decision
# meets the diagnostic probes:
#
#     adopt the candidate with the LOWEST validation RMS;
#     on any tie, prefer the EARLIER of parent < linear < refined.
#
# The first draft said "prefer the parent on a tie", which does not specify a
# winner when linear and refined tie below the parent. The order above is
# total and resolves every case toward the least-changed candidate.
ORDER = ["parent", "linear", "refined"]

# ── REGISTERED QUESTIONS ──────────────────────────────────────────────────

# Q1  Does HELD-OUT REPLAY adopt the harmful candidate?  PREDICTED YES.
#
#     **What a YES would and would not establish.**  It would show that THIS
#     minimum-RMS rule, on THIS evidence, chooses the harmful candidate. It
#     would NOT establish that no rule using held-out historical evidence
#     could discriminate — a different statistic on the same points is
#     untested, and this phase tests one.
Q1_ADOPTS_REFINED = True

# Q2  Does the RECENT WINDOW rank `refined` worse than held-out replay does?
#     PREDICTED YES.  Whether it REVERSES the decision is deliberately
#     unregistered: its labels are current but its points were learned from,
#     and its locations are wherever the stream went.
Q2_RANKS_REFINED_WORSE = True
Q2_REVERSES = None

# Q3  Does FRESH evidence recover the measured diagnostic ordering?
#     PREDICTED YES.
#
#     **A failure would not rule out label currency as a contributor.**
#     Sampling variability, or regions the draw covers poorly, could prevent
#     recovery on 256 points. So the fresh draw is repeated K = 8 times on
#     the FROZEN candidates — scoring only, no refitting — and the spread of
#     decisions is reported. That separates "the signal cannot order these
#     candidates" from "this draw did not".
#
#     **This is already known to matter.** On the cheap structural fixture at
#     V = 64 the eight draws split 4/4 between two different decisions. Draw
#     0 is the PAID family; the other seven are hypothetical, and taking them
#     all would cost K x V observations rather than V.
Q3_RECOVERS_ORDER = True
Q3_DRAWS = K

# Q4  The COST, reported and not predicted: V paid observations for the fresh
#     family and none for the historical ones, against whatever the decisions
#     are worth over the remaining 9648.

# ── WHAT THIS PHASE CANNOT ESTABLISH ──────────────────────────────────────
#
# **No acceptance policy.**  One consolidation, one trajectory, one parent,
# one statistic, and no false-alarm rate on consolidations that were fine —
# OBS-24 forked the one that was not.
#
# It cannot separate "recent" from "post-drift" on this fixture, because the
# drift ends before the window's last V observations begin.  On a fixture
# still drifting at the fork they would come apart.
#
# And "held out" means held out of THIS REFIT.  Those points were learned
# from when they arrived, so no family is held out of the model's history.


def main() -> None:
    print(__doc__.rstrip())
    print()
    print("  the construction")
    print("  " + "-" * 72)
    print(f"  fork at t = {FORK_AT}; buffer N = {N} selected from a window of W = {W}")
    print(f"  EXCLUDED from the fit, before selection/refit/refinement:")
    print(f"    {EXCLUDED}")
    print("  ONE shared candidate set, and its diagnostic ordering is MEASURED:")
    for name, note in CANDIDATES:
        print(f"    {name:<9} {note}")
    print("  OBS-24's world figures are CONTEXT. None is asserted here.")
    print()
    print("  Q0, first and refutable alone: does the reduced-fit refined candidate")
    print("  still damage the current world? If not, the discrimination question is")
    print("  moot at this fork and the phase reports that.")
    print()
    print("  the three families")
    print("  " + "-" * 72)
    for name, ev, when, note, cost in FAMILIES:
        print(f"  {name}")
        print(f"      evidence : {ev}")
        print(f"      labels   : {when}")
        print(f"      limit    : {note}")
        print(f"      cost     : {cost} paid observations")
    print()
    print("  what actually separates them on THIS fixture")
    print("  " + "-" * 72)
    print(f"  the drift ends at {DRIFT_HI} and the recent window spans {RECENT_SPAN[0]}..{RECENT_SPAN[1]},")
    print("  so RECENT ALREADY CARRIES CURRENT-WORLD LABELS. Fresh is not the only")
    print("  current-labelled family.")
    print("    held-out vs recent : varies LABEL AGE")
    print("    recent vs fresh    : varies PRIOR LEARNING EXPOSURE and LOCATION SAMPLING")
    print("  An age statistic is NOT a wrong-label fraction; the latter is unmeasured.")
    print()
    print("  the clock")
    print("  " + "-" * 72)
    print(f"  fresh queries are PAID and occupy [{FORK_AT}, {DECIDE_AT}) — not an instant")
    print(f"  candidates frozen while collecting; decide at {DECIDE_AT}; the adopted")
    print(f"  candidate then trains on those already-paid points, charged ONCE")
    print(f"  every continuation runs the remaining {REMAINING_AFTER} queries")
    print(f"  no checkpoint falls inside the span (next is {((FORK_AT // CHECK) + 1) * CHECK}) — asserted, not assumed")
    print("  historical families are SCORED, never re-observed: no second training pass")
    print()
    print("  the frozen criterion, now total")
    print("  " + "-" * 72)
    print(f"  lowest validation RMS; on any tie prefer the earlier of {' < '.join(ORDER)}")
    print()
    print("  registered questions")
    print("  " + "-" * 72)
    print("  Q0  the reduced-fit refined candidate still harms          PREDICTED YES")
    print("  Q1  held-out replay adopts `refined`                       PREDICTED YES")
    print("      — establishes what THIS rule on THIS evidence does, not that no")
    print("        rule on that evidence could discriminate")
    print("  Q2  recent ranks `refined` worse than held-out does        PREDICTED YES")
    print("      whether it REVERSES the decision                      unregistered")
    print(f"  Q3  fresh recovers the measured diagnostic order          PREDICTED YES")
    print(f"      over K = {K} independent draws, so a failure separates 'the signal")
    print("      cannot order these' from 'this draw did not'")
    print("  Q4  the cost                                              reported")
    print()
    print("  NO ACCEPTANCE POLICY IS ESTABLISHED. One consolidation, one trajectory,")
    print("  one parent, ONE STATISTIC, and no false-alarm rate on consolidations")
    print("  that were fine.")


if __name__ == "__main__":
    main()
