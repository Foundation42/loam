#!/usr/bin/env python3
"""marl18_predict — MARL-18's gate numbers, before its run.

Christian's plan for today (`MARL_Tomorrow_Action_Plan.md`) opens with an
observation and builds five sections on top of it:

    "the distilled student has been observed to achieve **significantly
     lower error than the teacher**, not merely fewer kernels."

## That is not what MARL-14 measured, and the correction is the phase

MARL-14's table is in `docs/implementation-notes.md` and every row of it
goes the other way:

    theta   kernels    RMS      K/K_t   RMS/RMS_t
    0.020     3 292  0.14016    0.937     1.058     <- matched options
    0.050     3 063  0.13999    0.872     1.057
    0.100     2 512  0.14456    0.715     1.091
    0.200     1 612  0.15109    0.459     1.141

    A->B costs 1.058, B->C costs 1.036

The teacher scored 0.13248. **No student ever beat it.** The number that
looks like the claim is 0.878, and it is a different ratio entirely: the
distilled student's RMS over A DENSE GRID OF THE SAME BYTE COUNT. The
student beat the *baseline* by more than the teacher beat the baseline,
because shrinking the memory budget hurts a grid (cube root of resolution)
far more than it hurts a placed basis. That is a real and good result. It
is a statement about the opponent, not about the teacher.

So the premise of the plan's SS1, SS2 and SS13 is a misreading of an
existing measurement, and the honest thing is to say so before building
five sections on it.

## Why the plan is still worth running, and is in fact MORE interesting

MARL-14 distilled a model and STOPPED. It never resumed learning against
reality. The plan's SS2 loop is:

    learn -> distil -> LEARN AGAIN -> distil -> ...

and that resume step has never been run. The student is worse at the
instant of the copy (1.058x). The open question is whether it is a better
PLACE TO LEARN FROM. Those are different claims, and the second one has
three mechanisms behind it that this campaign has already measured.

**FOR consolidation.**

(a) MARL-13's third door. Births are gated on RAW SURPRISE, so the model
    births on noise, and no learning rate closes it: 9 923 kernels at one
    ray a sample against 7 656 at sixteen, for the SAME 60 000 samples.
    About 23% of a noisy model's population is bought on nothing. A
    noiseless teacher cannot sell that capacity, so a sleep collects it.

(b) MARL-1 and MARL-6R, four sightings: "capacity you cannot train is
    worse than capacity you do not have", and RMS tracks updates-per-kernel
    monotonically. A smaller population on the same stream gets more
    updates each.

(c) The COVERAGE GATE, which is the mechanism behind Christian's word
    "tangled". A birth needs surprise above theta AND no kernel reading
    above 0.35 within the responsibility radius. So a region that has
    already spent kernels CANNOT BUY MORE, however badly placed the ones
    it has are. It is locked by its own history. Consolidation is the only
    operation in the codebase that can unlock it, because it does not
    remove kernels — it declines to rebuild them.

**AGAINST consolidation.**

(d) MARL-13 (b), and this is the one to beat: NLMS on noisy data does not
    converge, it hovers, and

        RMS^2 = bias^2 + mu/(2-mu) * V/M

    The variance term belongs to the RATE. Consolidation changes the
    population and leaves mu alone, so if an arm is already sitting on its
    noise floor, consolidation cannot move it and can only pay the
    generation cost.

(e) The student inherits the teacher's BIAS exactly and cannot tell it
    from signal. Whatever the teacher got wrong, the student now believes
    with a clean conscience.

(d) and (e) are why the predictions below mostly go against the plan. They
are stated as floors so that the plan's hypothesis is what refutes them.
"""

import math

# MARL-14's own measurements, which are the priors for everything here.
GEN_LOSS = 1.058        # A->B at matched options
FREE_POP = 0.937        # K_student / K_teacher at matched options
NOISE_POP_1 = 9923      # MARL-13: kernels at one ray a sample
NOISE_POP_16 = 7656     # MARL-13: kernels at sixteen, same samples


def main():
    print("MARL-18 — predictions, written before the run")
    print("=" * 72)

    print("\n0. THE CORRECTION, and it is a gate rather than a footnote")
    print("   The plan's premise is that a student beats its teacher on")
    print("   held-out error. MARL-14 measured the opposite at every point")
    print("   of its sweep, and the 0.878 that reads like the claim is the")
    print("   student against a SAME-SIZED GRID, not against the teacher.")
    print(f"   Restated as a claim so it can be refuted rather than assumed:")
    print("   → MARL18_PREMISE = 1.0, a FLOOR on RMS(student)/RMS(teacher)")
    print("     at matched options on the same probes, sixteen rays.")
    print("     A student sees only its teacher's output, so it has no")
    print("     access to anything the teacher got wrong; its best case is")
    print("     an exact copy and its actual case is a copy on a budget.")
    print(f"     MARL-14 says {GEN_LOSS}. This should HOLD.")

    print("\n1. …except by ONE mechanism, and it is Christian's, so it gets")
    print("   its own number rather than a footnote inside SS0")
    print("   Distillation with a SMALLER student is a low-pass filter. If")
    print("   a teacher's error against truth is partly high-frequency —")
    print("   kernels fighting each other, weights hovering at the NLMS")
    print("   floor of SS(d) — then a copy that cannot represent the wiggle")
    print("   is closer to a smooth truth than the original. That is the")
    print("   textbook regularisation argument for distillation and it is")
    print("   exactly what 'discarding optimisation baggage' would look")
    print("   like as a number.")
    print("   MARL-14 saw no sign of it: its ratios rise monotonically with")
    print("   coarseness (1.058, 1.057, 1.091, 1.141), no U. But its teacher")
    print("   was trained at sixteen rays, which is nearly clean. The U, if")
    print("   it exists anywhere, is at ONE ray.")
    print("   → MARL18_REGULARISE = 1.0, a FLOOR on the best")
    print("     RMS(student)/RMS(teacher) over a coarseness sweep, at ONE")
    print("     RAY a sample.")
    print("     Lean: HOLDS, because a student's own births are driven by")
    print("     its residual AGAINST THE TEACHER, so it chases the wiggle")
    print("     rather than smoothing it — the filter is not low-pass, it")
    print("     is capacity-limited, which is not the same thing. But the")
    print("     mechanism is real and if it is going to appear it appears")
    print("     here, and that would be the plan's result.")

    print("\n2. THE STAIRCASE: is a student a better PLACE TO LEARN FROM?")
    print("   Two arms, IDENTICAL reality streams, equal total reality")
    print("   samples, differing only in whether the model is rebuilt from")
    print("   itself partway:")
    print("     A   learn N")
    print("     B   learn N/k, sleep, learn N/k, sleep, … k times")
    print("   → MARL18_STAIRCASE = 1.0, a FLOOR on RMS(B)/RMS(A).")
    print("     Consolidation does not beat simply continuing to learn.")
    print("     The reasoning is MARL-13 (b): on a STATIONARY field the")
    print("     error is variance-limited and the variance term belongs to")
    print("     the rate. Each sleep pays ~%.3f and buys back only what" % GEN_LOSS)
    print("     more updates-per-kernel are worth, which on a converged arm")
    print("     is little.")
    print("     This is the plan's central claim, stated so that the plan")
    print("     refutes it. If it comes in below 1.0 the staircase is real.")

    print("\n3. …but the POPULATION should fall, and that is the deployment")
    print("   result even if SS2 holds")
    print(f"   MARL-14: one copy sheds {1-FREE_POP:.1%} of the population for free.")
    print("   Over k sleeps, with births resuming in between, the saving")
    print("   should at least survive rather than being undone.")
    print("   → MARL18_POPULATION = 0.95, a CEILING on K(B)/K(A) at equal")
    print("     reality samples. The minimum claim: repetition does not")
    print("     erase the one-shot saving.")

    print("\n4. THE GRADIENT, and it is the sharp one")
    print("   SS3 alone cannot tell 'consolidation collects capacity bought")
    print("   on NOISE' from 'a re-fit happens to find a leaner solution'.")
    print("   The noise story makes a second, harder prediction: the saving")
    print("   must GROW with the noise, because that is what there is more")
    print("   of to collect.")
    print(f"   MARL-13 measured the size of the prize directly: {NOISE_POP_1} kernels")
    print(f"   at one ray against {NOISE_POP_16} at sixteen for the same samples —")
    print(f"   {1 - NOISE_POP_16/NOISE_POP_1:.1%} of the noisy population bought on nothing, against")
    print("   a clean model's nothing at all.")
    print("   → MARL18_GRADIENT = 1.0, a FLOOR on")
    print("       [K(B)/K(A) at 16 rays]  ÷  [K(B)/K(A) at 1 ray]")
    print("     i.e. the saving is at least as large in the noisy regime.")
    print("     A flat gradient refutes the mechanism while leaving SS3's")
    print("     number intact, which is exactly the confound worth paying a")
    print("     second arm to remove.")

    print("\n5. THE DIFF: what a consolidation actually CHANGES (plan SS3)")
    print("   Christian: 'measure whether distillation predominantly")
    print("   performs kernel retirement / merging / movement / widening /")
    print("   … replacement of several overlapping kernels with a cleaner")
    print("   kernel'. The unit that makes that measurable is not kernel")
    print("   identity — a student shares none — it is OVERLAP: how many")
    print("   kernels read above a level at a query point.")
    print("   The trap is that overlap falls when population falls, for no")
    print("   structural reason at all. So the quantity under test is the")
    print("   RATIO OF RATIOS:")
    print("     overlap(student)/overlap(teacher)  ÷  K(student)/K(teacher)")
    print("   = 1  the population thinned UNIFORMLY; nothing was untangled")
    print("   < 1  crowded neighbourhoods were preferentially thinned —")
    print("        A + B + C + D  ->  X + Y, which is Christian's picture")
    print("   > 1  the student is MORE crowded per kernel: it concentrated")
    print("   → MARL18_UNTANGLE = 1.0, a CEILING on that ratio of ratios.")
    print("     Lean: HOLDS but barely. The student rebuilds from a smooth")
    print("     field, and the coverage gate that let the teacher crowd a")
    print("     region (it births whenever surprise fires, and noise fires")
    print("     it repeatedly in the same place) never fires twice for a")
    print("     student that is already within theta there.")

    print("\n6. What is deliberately NOT built today")
    print("   Plan SS4's local micro-distillation, SS7's stacked dynamic")
    print("   layers, SS8's object frames, SS11's particles. Every one of")
    print("   them is downstream of SS2: if consolidation turns out to be a")
    print("   compression step and not a learning step, 'continuous")
    print("   metabolism' is machinery in search of a phenomenon. Local")
    print("   consolidation is worth building the moment SS4's number says")
    print("   there is something local to collect.")

    # ── The extension, written after G37 (a) and (b) ran and BEFORE
    #    G37 (c) did, and labelled so the two cannot be confused. ────────
    print("\n" + "=" * 72)
    print("EXTENSION — written AFTER G37 (a) and (b) ran and BEFORE G37 (c)")
    print("did, and labelled so the two cannot be confused.")
    print("""
   SS2's floor was REFUTED at 0.898: on a one-ray field, three sleeps beat
   straight learning by 10% of the accuracy and a THIRD of the population,
   and SS4's gradient HELD at 1.432, so the effect really does track the
   noise. Christian's staircase exists.

   Then C2 refuted the phase. Dropping rate_w and rate_geom tenfold gets
   0.18474 at 3 142 kernels in 1.5 s, against consolidation's 0.21430 at
   3 671 in 11.6 — better on every axis and eight times cheaper.

   The arms were run at G33 (d)'s configuration, which fixes rate_geom at
   the DEFAULT on purpose so that its headline is not configured from its
   own result. That is right for G33 and wrong here: the question MARL-18
   asks is whether consolidation beats LEARNING, so it has to be the best
   learning this repo knows about, which is MARL-13 (c)'s rate_w 0.05 WITH
   rate_geom 0.02 (it measured 1.67x and 11 176 -> 7 113 kernels).

   So the number that is actually owed is: with the rates already right,
   does a sleep still buy anything?

   The mechanism says no, and says it specifically. Every result above is
   consistent with ONE story — a sleep removes the MODEL'S OWN VARIANCE,
   and it is worth exactly as much as there is variance to remove:

     16 rays, clean teacher      1.011x   costs 1%, nothing to filter
      1 ray,  noisy teacher      0.898x   buys 10%, plenty to filter
      the gradient               1.432    the saving tracks the noise

   A rate is the other way to not carry variance, and it is upstream: it
   stops the variance entering rather than removing it afterwards. Once
   rate_geom is at 0.02 the model is carrying much less of it, so there is
   much less for a sleep to collect, and the generation cost MARL-14
   priced at 1.058 should dominate exactly as it does at sixteen rays.
""")
    print("   → MARL18_RATE_FIRST = 1.0, a FLOOR on RMS(consolidated)/RMS(straight)")
    print("     at ONE RAY with rate_w 0.05 and rate_geom 0.02 — MARL-13 (c)'s")
    print("     own best, and the fixture this comparison should always have")
    print("     been run on.")
    print("     The claim: consolidation's win at 0.898 is a win over a")
    print("     HANDICAPPED baseline, and disappears once the cheap fix is")
    print("     applied first. If it is refuted — if a sleep still pays on")
    print("     top of the right rates — then consolidation is doing")
    print("     something a rate cannot, and SS4's local micro-distillation is")
    print("     worth building. That is the whole decision this number gates.")

    print("\n" + "=" * 72)
    print("Frozen for src/thresholds.zig:")
    print("  MARL18_PREMISE    = 1.0   (floor, RMS student/teacher, 16 rays)")
    print("  MARL18_REGULARISE = 1.0   (floor, best RMS student/teacher, 1 ray)")
    print("  MARL18_STAIRCASE  = 1.0   (floor, RMS consolidated/straight)")
    print("  MARL18_POPULATION = 0.95  (ceiling, K consolidated/straight)")
    print("  MARL18_GRADIENT   = 1.0   (floor, the K saving at 16 rays over at 1)")
    print("  MARL18_UNTANGLE   = 1.0   (ceiling, overlap ratio over population ratio)")
    print("  MARL18_RATE_FIRST = 1.0   (floor, consolidated/straight once the rates are right)")


if __name__ == "__main__":
    main()
