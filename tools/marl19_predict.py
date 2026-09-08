#!/usr/bin/env python3
"""marl19_predict — MARL-19's gate numbers, before its run.

Christian's clarification of the consolidation idea, in his words:

    "You are told to deliver the milk on Mondays so you buy a kernel. Then
     you are told to deliver the milk on Wednesday as well .. surprise, and
     you buy another kernel. Then you are told to deliver milk on Tuesday
     and Thursday and Friday as well, but you already have two kernels
     refining the parent Milk delivery schedule kernel.

     Now you have three, potentially four kernels whose sum is..
     Deliver milk Monday to Friday.

     The distilled student samples and never sees all the patches.. it sees
     a continuous function Saturday and Sunday, no milk, Monday through
     Friday, deliver the milk."

That is a different mechanism from the one MARL-18 measured, and MARL-18's
fixture could not have seen it.

## What MARL-18 concluded, and the hole in it

MARL-18's sentence was "a sleep is worth exactly as much as there is
VARIANCE to remove" — 1.011x on a clean teacher, 0.940x at the right
rates, 0.898x at the wrong ones, gradient 1.432. Every arm of it learned a
STATIONARY field from NOISY samples, so the only thing a teacher could be
carrying that a student would not rebuild was noise.

The milk round says there is a second currency: **HISTORY**. A model that
was told the schedule in stages holds kernels for boundaries that no
longer exist, and their sum is a simple function. The student is handed
the sum. Nothing about that argument mentions noise.

So the fixture has to be NOISELESS, or the two currencies cannot be told
apart. MARL-19's target is analytic and exact.

## The fixture, which is the analogy taken literally

The week runs along x, seven days. `A(y,z)` is a fixed smooth amplitude so
the field is not degenerate off the axis. The schedule is revealed in three
stages:

    stage 1   Mon                 2 edges
    stage 2   Mon, Wed            4 edges   (Tue is a hole that must be held DOWN)
    stage 3   Mon Tue Wed Thu Fri 2 edges   (the hole is filled in)

Five distinct edge positions are presented over the run. The FINAL target
has two. That gap is the history, and it is what a sleep is being asked to
refund.

The arms, all scored against the FINAL schedule throughout:

    A  incremental       N/3 at each stage
    B  from scratch      N at stage 3 — the no-history reference
    B3 from scratch      N/3 at stage 3 — EQUAL EVIDENCE on the final target,
                         which is the honest denominator for a capacity
                         comparison, since A spent two thirds of its
                         exemplars on schedules that no longer apply
    C  A, then one sleep
    D  A with a sleep after each stage, then the same further reality as A
"""

import math

DAYS = 7
STAGES = [(1,), (1, 3), (1, 2, 3, 4, 5)]


def edges(days):
    """Boundary count of a day set: a transition wherever membership flips."""
    s = set(days)
    n = 0
    for d in range(DAYS + 1):
        if (d in s) != ((d - 1) in s):
            n += 1
    return n


def main():
    print("MARL-19 — predictions, written before the run")
    print("=" * 72)

    print("\n0. Why this fixture is NOISELESS, and it is the whole design")
    print("   MARL-18 attributed every consolidation saving to variance,")
    print("   and its fixture gave it no choice: one stationary field, one")
    print("   noisy estimator, so the only thing a teacher could carry that")
    print("   a student would not rebuild was noise. The milk round makes")
    print("   no mention of noise. If a sleep collapses the population on an")
    print("   EXACT target, MARL-18's sentence is incomplete and there is a")
    print("   second currency.")

    print("\n1. THE HISTORY PREMIUM: what the path costs over the destination")
    seen = set()
    for i, st in enumerate(STAGES, 1):
        seen |= {("s", d) for d in st} | {("e", d) for d in st}
        print(f"   stage {i}: days {st} — {edges(st)} edges")
    final = edges(STAGES[-1])
    # distinct edge POSITIONS ever presented
    pos = set()
    for st in STAGES:
        s = set(st)
        for d in range(DAYS + 1):
            if (d in s) != ((d - 1) in s):
                pos.add(d)
    print(f"   distinct edge positions ever presented: {len(pos)}  ({sorted(pos)})")
    print(f"   the final schedule has:                 {final}")
    print(f"   so the structure the path presented is {len(pos)/final:.1f}x the destination's.")
    print("   Capacity does not track edges alone — kernels also tile the")
    print("   interior, where the field is A(y,z) and has its own structure —")
    print("   so the edge ratio is an upper bound on the premium, not an")
    print("   estimate of it.")
    print("   → MARL19_HISTORY = 1.3, a FLOOR on K(A)/K(B3): the incremental")
    print("     model carries at least 30% more capacity than a model that")
    print("     saw the SAME AMOUNT of the final schedule and no history.")
    print("     Well under the edge bound on purpose. MARL-7 measured this")
    print("     shape already — capacity linear in moves at flat accuracy —")
    print("     and MARL-9 sharpened it: capacity is paid per thing learned,")
    print("     and these are three different things.")

    print("\n2. THE REFUND, and it is Christian's claim")
    print("   The student is handed the SUM. It never sees the Tuesday hole")
    print("   being dug and filled in; it sees Mon–Fri. So it should rebuild")
    print("   the destination's structure and not the path's.")
    print("   Stated against what is achievable rather than as a raw ratio,")
    print("   because a raw ratio cannot tell a good refund on a small")
    print("   premium from a poor one on a large:")
    print("       refund = (K_A − K_C) / (K_A − K_B3)")
    print("   = 1  the sleep recovered the whole history premium")
    print("   = 0  the sleep recovered none of it")
    print("   → MARL19_REFUND = 0.5, a FLOOR. At least half the premium.")
    print("   Lean: HOLDS, and this is the prediction I would most like to")
    print("   be wrong about in either direction. The argument FOR is")
    print("   Christian's and it is clean. The argument AGAINST is MARL-18's")
    print("   own G37 (c): on a clean stationary field a sleep moved the")
    print("   population by 0.961x — almost nothing. The difference this")
    print("   fixture introduces is that MARL-18's teacher HAD NO HISTORY.")
    print("   So the two together are a real test rather than a re-run.")

    print("\n3. …and it should still COST accuracy, because the teacher is clean")
    print("   MARL-18 G37 (a): a copy of a sixteen-ray teacher costs 1.043,")
    print("   and MARL-14's was 1.058. Both teachers were nearly noiseless.")
    print("   This one is exactly noiseless, so there is no wiggle to filter")
    print("   and a copy should be a pure loss on the metric.")
    print("   → MARL19_COPY = 1.0, a FLOOR on RMS(C)/RMS(A).")
    print("     This is what separates the two currencies cleanly. If the")
    print("     refund is large AND the accuracy is unharmed, a sleep is")
    print("     buying memory for nothing on a field with no noise in it at")
    print("     all — which would be the strongest form of Christian's")
    print("     claim and would refute this number to get there.")

    print("\n4. SMOOTHER GROUND: the second half of the analogy")
    print("   'the Student can also learn away from the Teacher from the")
    print("   source of truth that the teacher learned from, but now it is")
    print("   learning on smoother ground.'")
    print("   The mechanism is the COVERAGE GATE and this fixture maximises")
    print("   it. A birth needs surprise above θ AND no kernel reading above")
    print("   `coverage` within the responsibility radius. The incremental")
    print("   model has spent kernels across three schedules, so the Tuesday")
    print("   it must now fill in is exactly where it is LEAST able to buy")
    print("   capacity — it is locked by its own history. The distilled model")
    print("   arrives at the same place with fewer kernels and the room to")
    print("   birth.")
    print("   → MARL19_GROUND = 1.0, a CEILING on RMS(D)/RMS(A) at equal")
    print("     further reality. Consolidating and then learning beats")
    print("     learning straight through.")
    print("   Lean: HOLDS. MARL-18 already refuted the same shape at 0.940")
    print("   on a NOISY field; this asks whether it survives with the noise")
    print("   taken away, which is the only way to know which currency paid.")

    print("\n5. What would make this a nothing-burger, and it is worth saying")
    print("   If MARL19_HISTORY fails — if the incremental model carries no")
    print("   premium — then this fixture does not reproduce MARL-7's")
    print("   accumulation and nothing downstream of it means anything. It")
    print("   is checked FIRST and the rest is read only if it holds.")

    # ── The extension, written AFTER G38 (a) and (b) ran and BEFORE
    #    G38 (c) did, and labelled so the two cannot be confused. ────────
    print("\n" + "=" * 72)
    print("EXTENSION — written AFTER G38 (a) and (b) ran and BEFORE G38 (c) did.")
    print("""
   MARL19_HISTORY was REFUTED at 1.103 and MARL19_REFUND at -1.789 — the
   sleep RAISED the population, 6 094 -> 7 110. MARL19_GROUND held at
   0.976 and 0.960, so the second half of the analogy works; the first
   half did not reproduce at all.

   Two things went wrong and only one of them is mine.

   THE CONFOUND, which is mine. The dream count is an EVIDENCE dial that
   sets the student's population directly, and it was set to 150 000
   against a teacher trained on 120 000. On a NOISELESS target more
   evidence buys more kernels, so the student was handed a bigger budget
   and spent it. In MARL-14 and MARL-18 that was invisible because noise
   dominated. Here it is the whole effect. G38 (c) pins the dream to the
   teacher's own evidence.

   THE REAL REASON, and it is a finding. Look at the arms at EQUAL total
   evidence: incremental 6 094 kernels at RMS 0.05791, from-scratch 6 709
   at 0.04351. The historical path bought FEWER kernels and is simply
   BEHIND, because it spent two thirds of its budget on schedules with
   less structure in them.

   Nothing it learned became WRONG. Monday is delivered at every stage.
   Wednesday is delivered at stages 2 and 3. The reveal is NESTED, so
   MARL-9's law applies and applies in the cheap direction: capacity is
   paid per THING LEARNED, and everything learned is still true. The only
   obsolete structure is two interior EDGES — Monday's end and Wednesday's
   start, which became interior when Tuesday was filled in — and two edges
   are a couple of per cent of a six-thousand-kernel population.

   And MARL-16 explains why even those are cheap: the Tuesday hole was
   ZERO, and zero is what an empty model already predicts, so holding the
   hole down never cost a kernel in the first place. There was nothing
   there to cancel.

   So the milk round as literally described does not accumulate a premium,
   and the reason is worth more than the prediction would have been:
   **incremental ADDITION is nested and cheap; it is CONTRADICTION that
   costs.** Which is exactly the world MARL-7 measured — a thousand kernels
   a move at flat accuracy — where the world MOVES and old structure
   becomes wrong rather than merely incomplete.

   G38 (c) puts the two paths side by side. Same three stages, same 120 000
   exemplars, same final schedule, differing only in whether the path
   contradicted itself:

       nested         {Mon}          {Mon,Wed}      {Mon..Fri}
       contradictory  {Mon,Tue,Wed}  {Wed,Thu,Fri}  {Mon..Fri}

   The contradictory path delivers Monday and Tuesday, then STOPS
   delivering them, then starts again. The model must pull those kernels
   down to zero and then push them back up, and the kernels it pulled down
   stay in the population with near-zero weights — which is MARL-7's
   "the capacity a moved world leaves behind", now produced on demand in a
   noiseless three-stage fixture instead of a six-move drift.
""")
    print("   → MARL19_CONTRADICT = 1.15, a FLOOR on K(contradictory)/K(nested)")
    print("     at equal evidence and the same final schedule. If the two")
    print("     paths cost the same, then history is free in MARL whatever")
    print("     shape it has, MARL-7's accumulation is about something else,")
    print("     and consolidation has nothing structural to collect.")
    print("   → MARL19_REFUND2 = 0.5, a FLOOR on the fraction of THAT premium")
    print("     a single sleep returns:")
    print("         (K_contra − K_contra_slept) / (K_contra − K_nested)")
    print("     with the dream pinned to the teacher's own evidence so the")
    print("     student is not simply handed a larger budget. This is the")
    print("     number Christian's claim actually rests on, on the only path")
    print("     shape that can carry it.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL19_HISTORY = 1.3  (floor, K incremental / K scratch at equal final evidence)")
    print("  MARL19_REFUND  = 0.5  (floor, fraction of the history premium a sleep returns)")
    print("  MARL19_COPY    = 1.0  (floor, RMS distilled / RMS incremental)")
    print("  MARL19_GROUND  = 1.0  (ceiling, RMS consolidated-then-learned / straight)")
    print("  MARL19_CONTRADICT = 1.15 (floor, K contradictory path / K nested path)")
    print("  MARL19_REFUND2    = 0.5  (floor, fraction of the CONTRADICTION premium a sleep returns)")


if __name__ == "__main__":
    main()
