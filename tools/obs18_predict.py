#!/usr/bin/env python3
"""obs18_predict — OBS-18's gate numbers, before its run.

Christian's queue item 1, written after OBS-17 separated evidence from
compression:

    Replay composition.  Now the obvious next question, because quantity
    and geometry are finally separated.  Equal-sized rings, same N, same k,
    same optimiser, differing only in the measure: uniform historical,
    recent-biased, error-biased, novelty/coverage-biased.  Nothing can then
    hide behind sample count or compression severity.  Expect a Pareto
    surface rather than a winner.

    python3 tools/obs18_predict.py
"""
import math
import random

TAU = 6.283185307179586
SHELL_C = (0.30, 0.62, 0.46)
SHELL_R, SHELL_W, SHELL_A = 0.20, 0.025, 0.9
SWELL_A, WINDOW_LO, WINDOW_HI = 0.35, 0.55, 0.70
A_SHIFT = (0.0, 0.0, 0.0)
B_SHIFT = (0.0, -0.10, 0.0)      # OBS-13..17's move, and MARL-6's
C_SHIFT = (0.12, 0.0, 0.22)      # walk[1] from MARL-9's table: unseen


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


def in_band(p, shift):
    c = [SHELL_C[i] + shift[i] for i in range(3)]
    return abs(math.dist(p, c) - SHELL_R) < 2 * SHELL_W


N_MC = 200_000
random.seed(18_2026)
band_a = band_ab = contested = dead = 0
abs_a = 0.0
for _ in range(N_MC):
    p = (random.random(), random.random(), random.random())
    ya, yb = truth(p, A_SHIFT), truth(p, B_SHIFT)
    abs_a += abs(ya)
    if in_band(p, A_SHIFT):
        band_a += 1
    if in_band(p, A_SHIFT) or in_band(p, B_SHIFT):
        band_ab += 1
    if abs(ya - yb) > 1e-3:
        contested += 1
    if p[0] > WINDOW_HI:
        dead += 1
band_a /= N_MC
band_ab /= N_MC
contested /= N_MC
dead /= N_MC
abs_a /= N_MC

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-18 — replay COMPOSITION at equal N and equal k.  PRE-REGISTERED")
print("=" * 74)
print(f"""
(0) THE FIXTURE, MEASURED RATHER THAN ASSUMED  ({N_MC:,} uniform points)

    shell band, world A          {band_a:.4f}   |r - R| < 2w
    shell band, A or B           {band_ab:.4f}   the union the move spans
    CONTESTED, |y_A - y_B| > 1e-3 {contested:.4f}
    DEAD, x > {WINDOW_HI}, y == 0 exactly  {dead:.4f}
    mean |y| over the cube        {abs_a:.4f}

Two of these decide the phase before any learning happens.

**Most of a replay buffer carries no regime information at all.** The
shift moves the shell and nothing else -- `swell` does not read it -- so
outside the band union the two worlds are IDENTICAL and a stored sample is
equally valid under both.  Only {contested:.1%} of a uniform buffer can even
be said to be stale.  Any claim about "old data" is a claim about that
{contested:.1%}.

**A third of the cube is exactly zero in every world.**  window(x) = 0 past
{WINDOW_HI} and no feature reaches there, so nothing is ever surprising there,
nothing is ever born there, and no kernel covers it.  That is the trap the
coverage measure walks into below.

(1) THE FOUR MEASURES, AND WHY THREE OF THEM ARE ONE ALGORITHM

    recent      a ring -- the incumbent, and every OBS phase to date
    uniform     A-Res reservoir, w = 1
    error       A-Res reservoir, w = surprise (the pre-update residual)
    uncovered   A-Res reservoir, w = 1 - cover (MARL's own birth statistic)

Weighted reservoir sampling with equal weights IS uniform reservoir
sampling, so uniform / error / uncovered differ in ONE EXPRESSION and
nothing else.  "Differing only in the measure" is then true in the code
rather than in the prose.

All four are ADMISSION policies: each decides at observation time, from
what a learner already has in hand.  Nothing here needs a second pass over
history, so none of the arms is cheating on cost.

(2) COMPOSITION, PREDICTED BEFORE THE SLEEP

Reported as: STALE = share of the contested points that were recorded under
world A; DEAD = share of the buffer with x > {WINDOW_HI}; REACHED = share of the
buffer that at least one kernel's support contains.

    arm         stale     contested      dead    reached
    recent      0.000     {contested:.3f}          {dead:.3f}     ~1.00
    uniform     0.500     {contested:.3f}          {dead:.3f}     ~1.00
    error       > 0.20    > {2.5 * contested:.3f}          < 0.05    ~1.00
    uncovered   ?         < {0.25 * contested:.3f}          > 0.60     < 0.60

    PREDICTED  recent's stale share is EXACTLY zero -- 20 000 exemplars in
               world B against a buffer of 8 192, so no A sample survives
    PREDICTED  uniform's stale share is 0.500 +- 0.05.  The tolerance is
               the fixture's, not a taste: only {contested:.1%} of the buffer is
               contested at all, so the binomial sd over ~{int(contested * 8192)} points is
               {math.sqrt(0.25 / max(1, contested * 8192)):.4f} and 0.05 is 2.8 sigma.  A tighter bar would
               be a gate that fails on the draw
    PREDICTED  error's contested share exceeds 2.5x uniform's: all residual
               mass lives on the bands, in both worlds and at every stage
    PREDICTED  uncovered's dead share exceeds 0.60, and its REACHED share is
               under 0.60 of uniform's

(3) THE HEADLINE QUESTION -- IS COMPOSITION A THIRD AXIS, OR IS IT N AGAIN?

OBS-17 established two knobs: f(N) estimation quality, g(k) information
destruction.  A composition rule changes NEITHER count.  So either the
identity of the points carries information beyond their number, or

    composition acts entirely through EFFECTIVE evidence, N_eff

where N_eff counts the rows that can constrain the fit.  This is testable
because the two biased arms fail in opposite ways:

    uncovered  its rows are ZERO = ZERO.  A point no kernel reaches has an
               all-zero design row, and out past x = {WINDOW_HI} the target is zero
               too, so the row is not merely uninformative, it is empty on
               both sides.  N_eff ~ 0.2 N.
    error      every row is live, but they all lie in {band_ab:.1%} of the cube.
               `refit` is ridged least squares, so a kernel with no evidence
               is shrunk to zero -- and `selectExplaining` never picks it in
               the first place.  The off-band basis is DELETED, not merely
               left alone.

    PREDICTED  gain(uncovered) < 0 -- destructive, at an N and k where the
               uniform arm is comfortably positive.  G64 measured N = 2 048
               at k ~ 205 at -0.55; 0.2 x 8 192 is 1 638.
    PREDICTED  gain(error) < gain(uniform), by more than the replication gap

(4) THE REGISTERED DISAGREEMENT

    CHRISTIAN   expect a PARETO SURFACE rather than a winner: immediate RMS,
                retention of older regimes and adaptation speed will trade,
                and different measures will win different axes.

    THE AGENT   predicts a near-SWEEP by the unbiased arms.  A replay buffer
                is not a dataset of interesting points; it is the evidence
                for a GLOBAL fit, and every parameter in that fit needs its
                share.  MARL-1's invariant -- capacity you cannot train is
                worse than capacity you do not have -- applied to the sleep's
                least-squares rather than to the online learner.  The Pareto
                trade survives only on axis 2, where `recent` must lose
                because it has thrown A's evidence away.

The agent lost OBS-12 and OBS-13 by reasoning from a property of the members
rather than of the operation.  The failure mode to watch is the same one:
this argument is about the rows of a matrix, which IS the operation, but it
assumes the parent basis is the only thing that matters and says nothing
about what `refine` does with 400 free steps.

(5) THE THREE AXES, AND WHAT EACH IS FOR

    1  IMMEDIATE    held-out RMS in world B, straight after the sleep
    2  RETENTION    return to world A for 20 000 exemplars: RMS, and BIRTHS
    3  PLASTICITY   go to world C (never seen) for 20 000: RMS, and BIRTHS

Births are the currency MARL-9 established: capacity is paid per THING
LEARNED, not per change, and a world you still hold is nearly free to
revisit.  So retention is not "does it still score well on A" -- it has been
fitting B, of course it does not -- it is "what does it cost to go back".

    PREDICTED  on axis 2, recent is worst: RMS higher AND more births than
               uniform, because a buffer with no A evidence cannot keep the
               kernels that explain A through a selection driven by that
               buffer
    PREDICTED  on axis 3, the arms are close: the spread across arms is
               SMALLER on C than on A.  Nothing in any buffer is evidence
               about a world nobody has visited, so composition governs what
               you KEEP and not what you can LEARN

(6) THE NULLS

    (a) The four buffers must actually differ, by (2).  Four rules that all
        collapse to the same composition measure nothing.
    (b) A REPLICATION: `uniform` is run twice with different reservoir
        streams and nothing else changed.  That gap is the noise floor, and
        every difference claimed above must exceed it.  OBS phases have
        twice read a single unreplicated number as a finding.
    (c) The guardrail: fit, sleep and eval measures are checked disjoint in
        every cell, as since G62 (a).

(7) NOT CLAIMED

One N, one k, one fixture, one move size, one direction of move.  The
buffers are all 8 192 and OBS-17's crossing at that size sits near k = 150,
so this runs in the regime where sleep clearly helps -- differences will
show as differences in HOW MUCH, and a composition rule that only matters in
the starved regime would not be visible here.
""")
print("=" * 74)
print("Frozen before the Zig was written.")
print("=" * 74)
