#!/usr/bin/env python3
"""obs25_predict — OBS-25's design and numbers, before its run.

OBS-24 established that at one parent, both consolidation stages reduced
historical replay RMS while increasing current-world RMS, and that refinement
alone increased world RMS from 0.27473 to 0.86959.  The guard behaved exactly
as specified in accepting it: replay non-increase is **insufficient** for
current-world protection.

The obvious next move is a better acceptance rule.  **This phase does not
build one.**  It asks the prior question:

    Is there any AVAILABLE signal — one a deployed system could actually
    compute at consolidation time — whose ranking of the candidates agrees
    with the current world's?

A signal that cannot discriminate cannot be the basis of any rule, however
the rule is written.  So OBS-25 is a DISCRIMINATION DIAGNOSTIC, and **no
acceptance policy is established by it.**

    python3 tools/obs25_predict.py
"""

# ── 1. WHICH CANDIDATES IT COMPARES ───────────────────────────────────────
#
# Astra's first pin. Exactly the three OBS-24 already measures, from the same
# `Split` construction, at the same fork:
CANDIDATES = [
    ("parent",   "the model entering the consolidation; adopting it IS declining"),
    ("linear",   "selection, compression and the linear refit; no descent"),
    ("refined",  "the refinement on top — the candidate that harmed"),
]
# Their current-world RMS at the fork, from OBS-24, is the DIAGNOSTIC TRUTH
# this phase judges each signal against. It is an oracle and is never
# available to any signal being tested.
DIAGNOSTIC_WORLD = {"parent": 0.16446, "linear": 0.27473, "refined": 0.86959}
DIAGNOSTIC_ORDER = ["parent", "linear", "refined"]      # best to worst
# And their replay RMS, which is what the incumbent rule reads:
INCUMBENT_REPLAY = {"parent": 0.22300, "linear": 0.12414, "refined": 0.06259}
INCUMBENT_ORDER = ["refined", "linear", "parent"]       # exactly reversed

# ── 2. DO VALIDATION OBSERVATIONS TRAIN THE LEARNER? ─────────────────────
#
# Astra's second pin, and it has to be answered per family because the answer
# differs.
#
#   * HELD-OUT REPLAY and RECENT-WINDOW evidence is ALREADY PAID. Those
#     observations were learned from when they arrived, at their own paid
#     times. They are withheld from the consolidation's FIT, not from the
#     learner's history — so "held out" here means held out of the refit,
#     and the candidates have all seen them before. **That is a weaker form
#     of held-out than it sounds and the registration says so.**
#   * FRESH VALIDATION queries are drawn at the decision instant and cost
#     paid observations. They are scored against all three candidates
#     FIRST, and only then learned from, BY THE ADOPTED CANDIDATE ALONE.
#     Learning from them before the decision would make them training data
#     for exactly the comparison they are meant to judge.
TRAINS_BEFORE_DECISION = False
TRAINS_AFTER_DECISION = "the adopted candidate only"

# ── 3. HISTORICAL AGAINST RECENT, WITH TIMING AND COST EXPLICIT ──────────
#
# The fork is at t = 94 096. The hard window holds W = 16 384 observations,
# so it spans t = 77 712 .. 94 096 — which STRADDLES the end of the drift at
# t = 90 000. That is not a detail: roughly three quarters of the window was
# observed while the world was still moving, and carries labels from worlds
# that no longer exist.
FORK_AT = 94_096
W = 16_384
WINDOW_SPAN = (FORK_AT - W, FORK_AT)                    # 77 712 .. 94 096
DRIFT_HI = 90_000
STALE_FRACTION = (DRIFT_HI - WINDOW_SPAN[0]) / W        # ~0.75

FAMILIES = [
    # name, evidence, when observed, query cost, what it can and cannot see
    ("held-out replay", "a split of the SELECTED buffer, withheld from the refit",
     "t in 77 712..94 096, the same span the fit sees", 0,
     "tests generalisation to held-out HISTORICAL evidence. Its labels are as stale as the fit's, so it can approve exactly the change that harmed."),
    ("recent window", "the most recent V observations in the window",
     "t in 94 096-V .. 94 096, all POST-drift", 0,
     "recent, but still historical: every label was drawn before the decision. Free, and representative only of where the stream happened to go."),
    ("fresh", "V newly drawn queries at the decision instant",
     "t = 94 096 exactly, current-world labels", "V paid observations",
     "the only family carrying CURRENT evidence. It is not free, and the observations it spends are not available for learning before the decision."),
]
V = 256
# V = 256 against the 9904 observations remaining: 2.6% of the horizon. Chosen
# before measuring, small enough that the cost is real but not decisive, and
# it is a REGISTERED DIAL rather than a tuned one — a sweep is a later phase.
REMAINING = 9904
COST_FRACTION = V / REMAINING

# REPRESENTATIVENESS. Fresh queries are drawn uniformly over the cube, which
# on this fixture is also the observation stream's distribution, so the two
# coincide HERE and would not on a fixture with a routed stream. Recorded so
# that the result is not read as general.

# ── 4. THE ACCEPTANCE CRITERION, FROZEN BEFORE ITS DECISIONS ARE JUDGED ──
#
# Astra's fourth pin. One rule, written here, applied identically to every
# family, and frozen before any decision is compared with the diagnostic:
#
#     adopt the candidate with the LOWEST validation RMS;
#     on an exact tie, prefer the parent.
#
# Preferring the parent on a tie makes the rule conservative in the only
# direction a safety rule should be, and the tie case is registered rather
# than left to whatever the comparison happens to do.
#
# **The diagnostic probes are never available to the rule.** They are used
# only to score the decision after it is made.

# ── REGISTERED QUESTIONS ──────────────────────────────────────────────────
#
# The measurable quantity is whether a family's RANKING of the three
# candidates agrees with the diagnostic ranking, and separately which
# candidate its frozen rule would adopt.

# Q1  Does HELD-OUT REPLAY approve the harmful candidate?  PREDICTED YES —
#     it would adopt `refined`. Its labels carry the same staleness as the
#     fit's, and ~75% of the window predates the end of the drift. If this
#     holds it is the phase's central negative: **the free signal cannot
#     discriminate, so no rule built on it can.**
Q1_APPROVES_REFINED = True

# Q2  Does the RECENT WINDOW discriminate better than held-out replay?
#     PREDICTED PARTIALLY — its ranking should place `refined` worse than
#     held-out replay does, because its labels are all post-drift. Whether
#     it reverses the decision is NOT predicted: every label is still
#     pre-decision, and the candidates were fitted on an overlapping span.
Q2_BETTER_THAN_HELDOUT = True
Q2_REVERSES = None      # deliberately unregistered

# Q3  Does FRESH evidence recover the diagnostic ranking?  PREDICTED YES,
#     with V = 256 sufficient to order three candidates separated by
#     0.16446 / 0.27473 / 0.86959. If fresh evidence does NOT recover it,
#     that is the more important result: it would say the gap is not about
#     label currency at all.
Q3_RECOVERS_ORDER = True

# Q4  What does the discrimination COST?  Reported, not predicted: V paid
#     observations, and the continuation after each decision is scored so the
#     spend is visible against the benefit rather than assumed worth it.

# ── WHAT THIS PHASE CANNOT ESTABLISH ──────────────────────────────────────
#
# **No acceptance policy.** It measures whether signals discriminate at ONE
# consolidation, on ONE trajectory, at ONE parent. A signal that discriminates
# here might not elsewhere, and a rule needs a false-alarm rate on
# consolidations that were fine — which this phase does not have, because
# OBS-24 forked the one that was not.
#
# It also cannot separate "recent" from "post-drift" on this fixture: the
# drift ends at 90 000 and the fork is at 94 096, so every recent observation
# is also a stationary-world one. On a fixture still drifting at the fork
# they would come apart.
#
# And "held out" is weaker than the term suggests: the held-out replay points
# were learned from when they arrived. They are held out of the REFIT, not of
# the model's history.


def main() -> None:
    print(__doc__.rstrip())
    print()
    print("  the three candidates, and the DIAGNOSTIC truth they are judged against")
    print("  " + "-" * 72)
    print(f"  {'candidate':<10} {'world RMS':>10} {'replay RMS':>11}   note")
    for name, note in CANDIDATES:
        print(f"  {name:<10} {DIAGNOSTIC_WORLD[name]:>10.5f} {INCUMBENT_REPLAY[name]:>11.5f}   {note}")
    print(f"  diagnostic order (best first): {' < '.join(DIAGNOSTIC_ORDER)}")
    print(f"  incumbent replay order:        {' < '.join(INCUMBENT_ORDER)}   — EXACTLY REVERSED")
    print()
    print("  validation families")
    print("  " + "-" * 72)
    for name, ev, when, cost, note in FAMILIES:
        print(f"  {name}")
        print(f"      evidence : {ev}")
        print(f"      when     : {when}")
        print(f"      cost     : {cost}")
        print(f"      limit    : {note}")
    print()
    print(f"  the window at the fork spans {WINDOW_SPAN[0]} .. {WINDOW_SPAN[1]} and the drift ends at {DRIFT_HI},")
    print(f"  so {STALE_FRACTION:.0%} of it was observed while the world was still moving")
    print(f"  V = {V}, which is {COST_FRACTION:.1%} of the {REMAINING} observations remaining")
    print()
    print("  training contract")
    print("  " + "-" * 72)
    print(f"  validation observations train the learner BEFORE the decision: {TRAINS_BEFORE_DECISION}")
    print(f"  after the decision: {TRAINS_AFTER_DECISION}")
    print("  held-out replay points WERE learned from when they arrived — they are")
    print("  held out of the REFIT, not of the model's history")
    print()
    print("  the frozen criterion, identical for every family")
    print("  " + "-" * 72)
    print("  adopt the candidate with the LOWEST validation RMS; on an exact tie, the parent")
    print("  the diagnostic probes are NEVER available to the rule")
    print()
    print("  registered questions")
    print("  " + "-" * 72)
    print("  Q1  held-out replay adopts `refined`                       PREDICTED YES")
    print("  Q2  recent window ranks `refined` worse than held-out does PREDICTED YES")
    print("      whether it REVERSES the decision                      deliberately unregistered")
    print("  Q3  fresh evidence recovers the diagnostic order          PREDICTED YES")
    print("  Q4  the cost of discriminating                            reported, not predicted")
    print()
    print("  NO ACCEPTANCE POLICY IS ESTABLISHED BY THIS PHASE. One consolidation,")
    print("  one trajectory, one parent, and no false-alarm rate on consolidations")
    print("  that were fine — OBS-24 forked the one that was not.")


if __name__ == "__main__":
    main()
