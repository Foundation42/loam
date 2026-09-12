#!/usr/bin/env python3
"""obs23_predict — OBS-23's design and numbers, before its run.

OBS-22 refuted Q6: **no intervention policy tested beat `none`.**  That is
the phase's headline and it is unattributed, because what OBS-22 called "an
intervention" is TWO mechanisms:

    1. r = 4096 TARGETED REVISITS, paid out of the same observation horizon
       — so an intervening arm makes 12 288 fewer FRESH observations than
       `none` over the same life.
    2. a CONSOLIDATION, which halves the population and refits the model
       against a window carrying historical labels.

OBS-22 measured their sum against zero.  Neither the campaign's own rule
(*when a correction changes several things at once, attribute none of it*)
nor the result itself licenses saying which one failed to earn its keep.

**This phase is the 2x2.**  It holds the placement fixed at OBS-22's
privileged `informed` timing, so the trigger — which OBS-22 established is
its own problem — is not under test here.

Astra reviewed this design before the sleeps were paid for and found a clock
bug in the runner plus four interpretation contracts that had to be frozen
first.  All five are below, marked.

    python3 tools/obs23_predict.py
"""

# ── THE CLOCK AND THE ORDERING ────────────────────────────────────────────
#
# Every paid observation advances the common clock, revisits included, each
# evaluated against the world at its own instant.  Where a query, a
# checkpoint and a sleep coincide at index i:
#     1. the observation at i is made and learned from
#     2. if an intervention COMPLETES at i, the consolidation runs
#     3. if i is a checkpoint, the model is scored — AFTER any consolidation
#
# **ASTRA (1), and it was a live bug.**  The two halves of the lattice
# complete at different instants and reach a coincident checkpoint by
# different code:
#
#   * an arm spending r observations completes r LATER than it starts, so a
#     checkpoint at its start instant belongs BEFORE the intervention, and
#     one landing on its LAST QUERY is deferred past the consolidation.
#   * an arm spending none completes at the instant it starts, so the
#     checkpoint already reached there must WAIT for the consolidation.
#
# The immediate path did not exist when OBS-22 was written and adding it
# scored at 30 000, 60 000 and 90 000 BEFORE consolidating — OBS-22's
# score-ordering bug, reintroduced on a new branch.  G70 (a) now asserts
# both paths at timings where every sleep lands exactly on a checkpoint, and
# asserts exactly one score per checkpoint.  The fix cannot move G69: none of
# its sleeps lands on a checkpoint, and every G69 arm revisits.
CHECK = 2000
TOTAL = 104_000
R = 4096
BUDGET = 3
W = 16_384
N = 8192

CHANGE_AT = 30_000
DRIFT_LO, DRIFT_HI = 60_000, 90_000
BOUNDS = [12_000, 30_000, 48_000, 60_000, 90_000, 104_000]

INFORMED = [30_000, 60_000, 90_000]
DEFERRED = [t + R for t in INFORMED]           # 34096, 64096, 94096

# ── THE LATTICE ───────────────────────────────────────────────────────────
#
# The two factors are (HOW THE r OBSERVATIONS ARE SPENT) x (CONSOLIDATE OR
# NOT).  The four cells must agree on the clock, or the factorial measures
# WHEN the sleep happened as well as what preceded it:
#
#   an arm that spends r on revisits CANNOT also sleep at the fire instant.
#   Its consolidation is necessarily r observations later.  So the matched
#   no-revisit cell is PLACED AT t + r and consolidates immediately, having
#   spent its r on ordinary fresh draws.  It does not fire early.
#
#     cell                 r spent on   consolidates at
#     -----------------------------------------------------
#     none                 fresh        --
#     revisit              revisits     --
#     sleep@t+r            fresh        t + r
#     both                 revisits     t + r
#
# `sleep@t` is the FIFTH arm and is not a cell: it is placed at t and
# consolidates immediately, isolating the r-observation OFFSET.  It is also
# the only arm in the campaign whose observation stream is identical to
# `none`'s at every index while differing in whether a sleep ran.
#
# `unguarded` is the sixth: `both` with the replay-loss acceptance rule off.
ARMS = [
    ("none",       "fresh",    None,     None,  "the control OBS-22 could not beat"),
    ("revisit",    "revisits", None,     None,  "the aiming half, alone"),
    ("sleep@t",    "fresh",    INFORMED, True,  "the offset control, placed at t"),
    ("sleep@t+r",  "fresh",    DEFERRED, True,  "the cell, clock-matched to `both`"),
    ("both",       "revisits", INFORMED, True,  "OBS-22's recipe, guarded"),
    ("unguarded",  "revisits", INFORMED, False, "acceptance and rollback, disabled"),
]

# ── WHAT THIS ESTIMATES: A REPEATED POLICY, NOT AN ISOLATED SLEEP ─────────
#
# **ASTRA (2), and it governs how every result below may be narrated.**
#
# After the first consolidation the model is different.  Different admission
# surprises follow, and the window's ranking changes — so `revisit` and
# `both` share the FRESH stream but need NOT share the locations their
# second and third revisits target.  Consolidation's effect therefore
# INCLUDES its feedback into future acquisition.
#
# That is legitimate for this factorial and it is what a policy actually
# does.  But it means a negative interaction may NOT be narrated as "sleep
# uses repaired evidence better" — it may equally be "sleep changes what
# gets revisited next", and this design cannot separate them.
#
# Likewise the shared fresh prefix is NOT shared evidence between a
# fresh-only arm and a revisiting one.  The same locations arrive at
# different PAID TIMES, so in the drift they carry different labels, and
# they are learned from by a model with a different history.  The common
# clock makes that part of the policy effect rather than an artefact.

# ── THE GUARD: A DIFFERENT POLICY, NOT A FREE SAFETY NET ─────────────────
#
# **ASTRA (4).**  OBS-22 established that an unguarded nonlinear refinement
# CAN diverge (replay RMS 0.13965 -> 0.35844, the held-out world left at
# 6.72213) and that a replay-loss acceptance rule prevents that failure.
#
# An exploding descent IS a possible cost of the unguarded intervention.
# Choosing a guarded recipe does not remove a distortion — it CHANGES THE
# POLICY BEING EVALUATED, deliberately, and `unguarded` measures the
# trajectory effect of that choice rather than leaving it assumed.
#
# What `unguarded` vs `both` does NOT measure is computational overhead.
# Both arms attempt the refinement; the guard adds snapshot, check and
# restore work on top.
#
# `Options.guard` still defaults false; nothing outside this phase changes.

# ── THE ACCOUNTING, WHICH IS ARITHMETIC AND THEREFORE ASSERTED EXACTLY ────
REVISIT_TOTAL = BUDGET * R                      # 12288
MONITORED_REVISIT = TOTAL - REVISIT_TOTAL       # 91712
MONITORED_FRESH = TOTAL                         # 104000

# ── THE STREAM CONTRACT ───────────────────────────────────────────────────
#
# The fresh-draw RNG advances once per FRESH observation and never for a
# revisit.  Therefore, by construction:
#
#   * `none`, `sleep@t` and `sleep@t+r` draw the IDENTICAL 104 000 fresh
#     locations in the identical order.
#   * `revisit`, `both` and `unguarded` draw a PREFIX — the first 91 712 of
#     the same locations, in order.
#
# Each arm carries a running hash over its fresh draws alone plus that hash
# snapshotted at 91 712 draws, and the gate asserts equality both ways.
#
# **Identical hashes are not enough on their own.**  A controller side
# effect need not move a single drawn location, so the stubbed run also
# asserts that the fresh-only arms match `none` on OUTPUTS — error by phase,
# population, births — and that the three revisiting arms match each other.

# ── REGISTERED CONTRASTS, ALL PAIRED, ALL PER TRAJECTORY ──────────────────
#
# **ASTRA (3).**  A 2x2 read as four separate arm means loses the pairing
# that makes it a factorial.  Each contrast below is formed WITHIN a
# trajectory and only then averaged, and each is reported for BOTH
# objectives — whole and drift-plus-tail.
CONTRASTS = [
    ("C1  revisit - none",                 "the aiming half, without a consolidation"),
    ("C2  sleep@t+r - none",               "the consolidation half, without revisiting"),
    ("C3  both - revisit",                 "consolidation's effect WITH revisiting"),
    ("C4  both - sleep@t+r",               "revisiting's effect WITH consolidation"),
    ("C5  both - revisit - sleep@t+r + none", "THE INTERACTION. equals C3 - C2 and C4 - C1"),
    ("C6  sleep@t+r - sleep@t",            "the r-observation offset, alone"),
]
#
# **Two trajectories are descriptive replication and nothing more.**  The
# between-trajectory difference of a PAIRED contrast is reported for each
# contrast separately; an individual arm's own spread is NOT the uncertainty
# of a paired interaction and may not be spent on one.  (The campaign's
# standing second invariant, in a new place: a spread measured on one
# quantity must never be spent on another's margin.)

# ── REGISTERED QUESTIONS ──────────────────────────────────────────────────
#
# Objectives are OBS-22's, unchanged: mean RMS over checkpoints, WHOLE and
# DRIFT+TAIL (the last two phases).  OBS-22's own numbers, for reference and
# NOT as an arm of this experiment — the recipe differs by the guard:
OBS22_NONE_WHOLE = 0.08492
OBS22_INFORMED_WHOLE = 0.09079
OBS22_DEFICIT = OBS22_INFORMED_WHOLE - OBS22_NONE_WHOLE   # +0.00587

# Q1  Does the AIMING half pay on its own?   C1 PREDICTED NEGATIVE.
#     OBS-21 measured targeted revisiting beating fresh draws BEFORE any
#     sleep, .0770 against .0849 — a ratio of 0.907 at one well-placed
#     intervention.  The magnitude here is NOT derivable: two of these three
#     placements sit in or at the end of a drift, where a location chosen by
#     STORED surprise may no longer be where the model is wrong.
Q1_SIGN = -1

# Q2  Does the CONSOLIDATION half pay on its own?  C2 PREDICTED POSITIVE,
#     and separately PREDICTED LARGER than OBS-22's whole deficit — i.e. the
#     consolidation carries more than all of it and the revisits repay part.
#     The second is registered apart because it can be refuted alone.
Q2_SIGN = +1
Q2_EXCEEDS = OBS22_DEFICIT

# Q3  Do the two halves INTERACT?   C5 PREDICTED NEGATIVE.
#     OBS-21's result is precisely an interaction: a sleep improved the
#     TARGETED models by 6-11% while WORSENING fresh draws and untargeted
#     revisits.  If that survives here, the combination must beat what the
#     halves predict additively.
#
#     **ASTRA (3), narrowing what a refutation would establish.**  It would
#     say OBS-21's interaction did not carry over to THIS repeated
#     trajectory policy.  It would NOT say that scheduling caused the
#     disappearance: repetition, the model states, drifting labels, the
#     feedback into later revisit targeting and the objective itself all
#     differ from OBS-21 as well.
Q3_SIGN = -1

# Q4  THE RESOURCE ACCOUNT, which OBS-22 did not report at all.
#     `none` never prunes; the sleeping arms halve three times and regrow.
#     OBS-22 counted the regrowth — 645->322->727 and 727->363->817, a return
#     to ~1.13x the pre-sleep population — so three halvings do NOT give 1/8.
#
#     Registered: k_final(both) / k_final(none) in [0.40, 0.80].  The bound
#     is SOFT, derived from one arm's regrowth in a different phase, and is
#     registered so that it can be wrong.
#
#     **ASTRA (5).**  Final population is not trajectory resource
#     expenditure — it can miss most of the history — so the population at
#     every checkpoint, its trajectory mean and its peak are all carried,
#     with births kept apart from sleeps because they are different costs.
#
#     If this reveals an accuracy-capacity trade it does NOT invalidate
#     OBS-22's comparison, which was valid for its stated objective and
#     merely incomplete as a resource account.
Q4_LO, Q4_HI = 0.40, 0.80

# Q5  What does enabling acceptance and rollback do to the trajectory?
#     PREDICTED INERT at these placements: ZERO rejections, and `unguarded`
#     equal to `both` EXACTLY — asserted on the f64 outputs, not to printed
#     precision, since with no rejection the guard restores nothing.
#     OBS-22's divergence was on the `schedule` arm at t = 82 096;
#     `informed`'s instants differ.  If a rejection DOES fire here, that is
#     the phase's finding and not an inconvenience.
Q5_REJECTIONS = 0

# ── WHAT THIS PHASE CANNOT SAY ────────────────────────────────────────────
#
# One fixture, one placement set, one r, one budget, one compression ratio.
# The 2x2 is measured at a SINGLE point of each, so an interaction found
# here is a fact about this cell of a space nobody has swept.
#
# It estimates a REPEATED POLICY.  Three interventions interact with each
# other through the model, and no contrast here isolates the first from the
# third.
#
# And it says nothing about timing, deliberately.  C6 is a 4096-observation
# offset between two placements, not a t_min sweep.


def main() -> None:
    print(__doc__.rstrip())
    print()
    print("  the six arms")
    print("  " + "-" * 74)
    print(f"  {'arm':<12} {'r spent on':<10} {'consolidates at':<26} {'guard':<6} note")
    for name, spend, at, guard, note in ARMS:
        at_s = "--" if at is None else "{" + ", ".join(f"{t}" for t in at) + "}"
        g = "--" if guard is None else ("on" if guard else "OFF")
        print(f"  {name:<12} {spend:<10} {at_s:<26} {g:<6} {note}")
    print()
    print("  accounting, asserted exactly")
    print("  " + "-" * 74)
    print(f"  paid, every arm                      {TOTAL}")
    print(f"  revisits, revisiting arms            {REVISIT_TOTAL}  = {BUDGET} x {R}")
    print(f"  monitored, revisiting arms           {MONITORED_REVISIT}")
    print(f"  monitored, fresh-only arms           {MONITORED_FRESH}")
    print(f"  started, every intervening arm       {BUDGET}")
    print(f"  crossings / unready / blocked        0 / 0 / 0   (every arm is `.at`)")
    print(f"  scores per checkpoint                exactly 1, on BOTH sleep paths")
    print()
    print("  the stream contract")
    print("  " + "-" * 74)
    print("    h(none) == h(sleep@t) == h(sleep@t+r)")
    print(f"    h(revisit) == h(both) == h(unguarded) == prefix{MONITORED_REVISIT}(none)")
    print("    and the stubbed run matches OUTPUTS too — a side effect moves no query")
    print()
    print("  paired contrasts, formed WITHIN a trajectory, for whole AND drift+tail")
    print("  " + "-" * 74)
    for name, note in CONTRASTS:
        print(f"  {name:<40} {note}")
    print()
    print("  registered questions")
    print("  " + "-" * 74)
    print(f"  Q1  C1 = revisit - none                         PREDICTED < 0")
    print(f"  Q2  C2 = sleep@t+r - none                       PREDICTED > 0, and > {Q2_EXCEEDS:+.5f}")
    print(f"  Q3  C5 = the interaction                        PREDICTED < 0")
    print(f"  Q4  k_final(both) / k_final(none)               PREDICTED in [{Q4_LO}, {Q4_HI}]")
    print(f"  Q5  guard rejections                            PREDICTED {Q5_REJECTIONS}, and both == unguarded EXACTLY")
    print()
    print(f"  OBS-22's reference deficit, informed - none:    {OBS22_DEFICIT:+.5f}")
    print("     (reference only. OBS-23's recipe is GUARDED, so `both` is a different policy.)")


if __name__ == "__main__":
    main()
