#!/usr/bin/env python3
"""obs21_predict — OBS-21's gate numbers, before its run.

The queue item OBS-20 left, after Astra retired the one it first proposed:

    Where a larger pool of VALIDLY LABELLED points could come from, since
    detection cannot supply it — cutting at the move deletes those
    observations rather than relabelling them.  The levers left: observe
    longer before consolidating, or RE-OBSERVE old locations under the
    current world, which is a different mechanism from replay.

**Re-observation is not replay.**  Replay reuses what the model was told;
re-observation spends a real observation to ask again, at a location the
model chooses.  MARL has always supported it — `observe(q, y)` takes an
external exemplar and has since MARL-0 — but no phase has ever CHOSEN q.

And it has a target.  OBS-19 found a `t_min`: consolidating 4 096
observations after a regime change was destructive under EVERY rule tested,
because with M fresh observations for N slots at least (N-M)/N of every
buffer is stale by arithmetic.  So:

    CAN YOU PAY TO CONSOLIDATE EARLY?

    python3 tools/obs21_predict.py
"""
import math
import random

TAU = 6.283185307179586
SHELL_C = (0.30, 0.62, 0.46)
SHELL_R, SHELL_W, SHELL_A = 0.20, 0.025, 0.9
SWELL_A, WINDOW_LO, WINDOW_HI = 0.35, 0.55, 0.70
A_SHIFT, B_SHIFT = (0.0, 0.0, 0.0), (0.0, -0.10, 0.0)


def window(x):
    if x <= WINDOW_LO:
        return 1.0
    if x >= WINDOW_HI:
        return 0.0
    return 0.5 * (1 + math.cos(math.pi * (x - WINDOW_LO) / (WINDOW_HI - WINDOW_LO)))


def swell(p):
    return (SWELL_A * math.sin(TAU * (0.9 * p[0] + 0.13))
            * math.cos(TAU * (0.7 * p[1] - 0.21))
            * math.sin(TAU * (0.6 * p[2] + 0.37)))


def shell(p, shift):
    c = [SHELL_C[i] + shift[i] for i in range(3)]
    r = math.dist(p, c)
    t = (r - SHELL_R) / SHELL_W
    return SHELL_A * math.exp(-t * t) if t * t <= 16 else 0.0


def truth(p, shift):
    return window(p[0]) * swell(p) + shell(p, shift)


N, W = 8192, 16384          # replay slots, and the hard window (OBS-20's 2N)
WAKE_A, M, BUDGET = 30_000, 4_096, 4_096
TOT = WAKE_A + M

print(__doc__.split("\n\n")[0])
print()
print("=" * 78)
print("  THE MATCH, AND IT IS ARITHMETIC")
print("=" * 78)
lo = TOT - W
pre = WAKE_A - lo
lo2 = TOT + BUDGET - W
print("""
  A hard window of W = 2N, consulted %d observations after the move, is
  %.1f%% pre-move: it spans t = %d..%d and the move was at %d.

  Now spend a budget of %d observations, one of two ways.  Both are real
  observations, both update the model, both cost the same:

    FRESH   %d uniform draws.  The window slides; its oldest %d slots
            fall out; %d of %d slots are now post-move.
    RECALL  %d RE-OBSERVATIONS at locations the window already holds.
            The window does not slide; %d stale labels become valid, so
            %d of %d slots are now validly labelled.

  **Both land at exactly %.3f.**  Equal label validity, equal budget, equal
  number of `observe` calls, the same model arithmetic.  The only thing that
  differs is WHAT THE BUDGET BOUGHT:

      FRESH  buys NEW LOCATIONS, and loses its oldest ones
      RECALL buys VALID LABELS at locations it already had

  That is the cleanest form the question has: re-observation against simply
  carrying on, at matched cost.
""" % (M, 100 * pre / W, lo, TOT - 1, WAKE_A, BUDGET,
       BUDGET, BUDGET, W - (WAKE_A - lo2), W,
       BUDGET, BUDGET, W - (pre - BUDGET), W,
       (pre - BUDGET) / W))

print("=" * 78)
print("  FRESH IS THE CONTROL, NOT A STRAW MAN")
print("=" * 78)
print("""
  `FRESH` is exactly what the incumbent does: keep observing.  So this is
  not "re-observation against nothing" — it is re-observation against the
  default use of the same budget, which is the only comparison that means
  anything.  The unbudgeted sleep at M = %d is reported as a REFERENCE
  POINT, not a control: it has made %d fewer observations and its model is
  correspondingly less converged.
""" % (M, BUDGET))

random.seed(21_2026)
MC = 200_000
contested = sum(1 for _ in range(MC)
                if abs(truth((random.random(), random.random(), random.random()), A_SHIFT)
                       - truth((random.random(), random.random(), random.random()), B_SHIFT)) > 1e-3)
# the honest version: one point, both worlds
random.seed(21_2026)
contested = 0
for _ in range(MC):
    p = (random.random(), random.random(), random.random())
    if abs(truth(p, A_SHIFT) - truth(p, B_SHIFT)) > 1e-3:
        contested += 1
contested /= MC
print("  contested share of the cube: %.4f, so of the %d stale slots about %d"
      % (contested, pre, round(pre * contested)))
print("  carry an actually WRONG label, and a budget of %d can fix at most %d of them."
      % (BUDGET, round(BUDGET * contested)))
print()

print("=" * 78)
print("  THE REGISTERED PREDICTIONS")
print("=" * 78)
print("""
  P1  THE MATCH, asserted not announced.  Both arms make the same number of
      `observe` calls, and both windows end at 0.500 stale-labelled.  If
      either fails the comparison is not cost-matched and nothing below it
      means anything.

  P2  BOTH BEAT THE UNBUDGETED REFERENCE.  OBS-19 measured every rule as
      DESTRUCTIVE at this offset — the un-slept model beat its best child.
      Spending any budget at all should help, and if it does not, the
      problem is not staleness.

  P3  *** THE HEADLINE, and it is a genuine coin-toss registered as a
      direction. RECALL beats FRESH. ***

      The reasoning: the sleep's selection is error-weighted, so it will
      reach for high-surprise locations — and RECALL made exactly those
      valid, because it chose which slots to re-observe by the same measure.
      FRESH's valid half is whatever uniform draws happened to land.  So
      re-observation's value is not that it revalidates, it is that it can
      be AIMED, and fresh observation cannot be.

      The other way it could go, and the reason this is registered rather
      than assumed: RECALL adds no new locations at all.  It re-asks at
      points the buffer already had, so it buys no coverage, and OBS-20
      measured location quality as worth 19x the spread.  If locations
      dominate, FRESH wins.

  P4  TARGETING IS THE MECHANISM, isolated — and the fixture makes it
      sharp.  Only 0.0944 of this cube is CONTESTED, so a budget of 4 096
      spent on uniformly-chosen stale slots fixes about 387 actually-wrong
      labels: a 9.4% hit rate, because that is simply the contested share.
      Surprise concentrates on the contested band, so an AIMED budget should
      hit far more of them with the same 4 096 observations.

      Registered: recall-error fixes more than TWICE the wrong labels that
      recall-uniform does, and beats it on the current world.  The 2x is
      OBS-18's error-enrichment floor carried over rather than re-derived;
      OBS-20 measured the windowed version of it at 1.9x.

      If P3 holds and P4 does not, the win came from revalidation rather
      than from aiming, and the write-up must say so.

  P5  *** THE t_min PAYOFF.  Does either arm make an early consolidation
      WORTH DOING — gain > 0 — where OBS-19 found every rule negative? ***
      Registered as YES for recall-error and recorded as open for the rest.
      This is the practical question the phase exists for: OBS-19 said do
      not consolidate soon after a change, and the interesting answer is
      "unless you pay for it".

  P6  THE PRICE, reported not thresholded.  A re-observation costs exactly
      what an observation costs — this is not a cheaper operation, it is a
      differently AIMED one.  The phase claims no saving, only a better
      allocation.
""")
print("=" * 78)
print("  WHAT WOULD REFUTE IT OUTRIGHT")
print("=" * 78)
print("""
  - If P1 fails the arms are not cost-matched.
  - If P5 fails for every arm, `t_min` is not about label validity at all
    and OBS-19's arithmetic explanation needs replacing rather than
    extending — the budget would have bought valid labels and changed
    nothing.
  - If RECALL wins but P4 shows targeting contributes nothing, then what
    matters is simply having valid labels wherever they are, and the
    "aiming" story is wrong.
""")
