#!/usr/bin/env python3
"""obs6_predict — OBS-6's gate numbers, before its run.

OBS-5 established that OBS-4's false birth pressure is Adam's SCALE-FREE
STEP: `lr * mhat/(sqrt(vhat) + eps)` is dimensionless in the gradient, so
the step stays at `lr` however converged the fit is, and a `1/t` schedule
removes the pressure entirely at no cost to the fit (0 requests at every
seed, the fit held at 3.3e-7 against a 2.2e-7 checkpoint).

OBS-3 and OBS-4 ran at a FIXED 0.003.  So `OBS3_BIRTH_GAIN` — the threshold
that decides what counts as a birth request in both phases — was calibrated
against a signal sitting on a wander nobody had measured.  OBS-4 said as
much without knowing the cause:

    Repeat pressure is therefore not exclusive to wrong physics even
    within this small factorial.  The five registered comparisons hold,
    but the control results rule out a broader reading of them.

The control that ruled it out was CORRECT dynamics making unnecessary
births "under the longer optimisation schedule and new sample draws", and
one correct-rich-repeated seed making 13 cross-window repeat requests.
OBS-5 now names the mechanism for exactly that: a longer schedule is more
wander is more false pressure.

So OBS-6 re-runs OBS-4's factorial with the schedule and asks what
survives.  It is a re-run, not a re-derivation, and the interesting outcome
is the one where the findings survive AND the control clears — because that
would turn OBS-4's "not a reliable classifier" into one.

    python3 tools/obs6_predict.py
"""

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-6 — does the birth signal survive its own calibration?")
print("PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) THE SCHEDULE, AND WHY ITS SHAPE IS NOT A FREE CHOICE

    lr_t = lr0 * min(1, t0 / t),     t0 = 400

Full rate through the warm-up, then 1/t from step 400 onward.  Both halves
are read off the harness rather than chosen:

  - births are gated on `step > 400` in OBS-4's own `run`, so 400 is the
    moment the birth signal starts being READ.  Decaying before then would
    slow learning during a period whose readings nobody uses; decaying
    after would leave the wander inside the window that matters.
  - 1/t and not 1/sqrt(t) because OBS-5 measured both on this fixture:
    1/sqrt(t) left six requests standing across three seeds and 1/t left
    zero.  The horizon is short and the milder schedule has no room.

By step 3600 the rate is lr0/9.  Total RHS calls and coefficient updates
are unchanged — a schedule changes the step size, never the work — so
OBS-4's equal-budget contract holds without any new assertion.

(2) THE NULL THAT MAKES EVERYTHING ELSE MEAN ANYTHING

A decayed rate could improve every birth number for the stupidest possible
reason: by learning less.  A model that barely moves makes no requests and
also fits nothing.  So the first thing measured is whether the schedule
COSTS THE FIT, on the arms where allocation is frozen and the only thing
that can change is the coefficients:

    PREDICTED  frozen-allocation final train RMS, scheduled over
               unscheduled, pooled over the factorial:   <= 1.10

    If that fails, OBS-6 is measuring slowed learning and every other
    number in it is void.  MARL-20's two-nulls discipline, and it is the
    reason this is registered first rather than last.

(3) THE FIVE OBS-4 COMPARISONS SHOULD ALL STILL HOLD

Their mechanism is compensation for WRONG PHYSICS, which a learning rate
does not touch.  If any of them flips, the finding was the wander.

    PREDICTED  all five still HELD:
                 useful births > 0, with adaptive beating frozen on
                   repeated train and repeated eval
                 fresh eval:      adaptive < frozen
                 incoming SSE:    adaptive < frozen
                 correct < wrong on adaptive eval
                 wrong repeats > correct repeats

(4) THE CONTROL SHOULD CLEAR, AND THAT IS THE POINT

OBS-4's control, on the SIMPLE field where correct dynamics need no extra
capacity at all:

    correct simple      frozen eval    adaptive eval
    repeated evidence      .000167         .001457      8.7x worse
    fresh evidence         .000518         .001851      3.6x worse

Adaptive allocation made the correct model WORSE by buying capacity it did
not need.  Under OBS-5's account that is the wander crossing
`OBS3_BIRTH_GAIN`, and the schedule should remove most of it.

    PREDICTED  the adaptive/frozen eval ratio on simple correct dynamics
               falls by at least 2x on BOTH evidence regimes:

                   scheduled ratio / unscheduled ratio  <= 0.50

    PREDICTED  correct-dynamics cross-window repeat requests, summed over
               the whole factorial, fall by at least 2x

    PREDICTED  wrong-dynamics repeat requests fall by LESS than
               correct-dynamics ones, so the separation WIDENS:

                   (wrong scheduled / wrong unscheduled)
                 > (correct scheduled / correct unscheduled)

(5) WHAT WOULD MAKE THIS PHASE INTERESTING RATHER THAN TIDY

  (i)  The control clears and the five hold.  Then repeat pressure IS a
       usable mismatch signal on this fixture once the optimiser stops
       manufacturing it, and OBS-4's caution was about the instrument
       rather than about the claim.  This is the outcome the phase is
       for, and it is also the least surprising.

  (ii) The control clears and one of the five FLIPS.  Then that comparison
       was measuring wander and not physics, and OBS-4's headline needs
       narrowing.  The likeliest candidate is `useful births > 0` on the
       rich field: if the schedule suppresses genuine acquisition as well
       as spurious, the rich field's two fine components never get bought
       and adaptive stops beating frozen.  That would say the birth rule
       cannot separate the two without a rate that distinguishes them,
       which is a real design problem and a better finding than (i).

  (iii) The control does NOT clear.  Then the correct-dynamics births are
       not wander, `OBS3_BIRTH_GAIN` is simply too low for this fixture,
       and the remedy is a threshold rather than a schedule.  OBS-5's
       mechanism would still stand — it was measured directly — but it
       would not be what OBS-4's control was seeing.

(6) WHAT IS NOT BEING CLAIMED

The schedule is not proposed as a default for anything.  MARL's own
learner does not use Adam by default and G52 (b) showed its NLMS default
has no floor to fix.  This is a correction to two observational phases'
instrument, on one fixture, with a model class that contains the truth.
Whether a mismatch detector built on repeat pressure generalises past that
is untested and stays untested here.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
