#!/usr/bin/env python3
"""obs20_predict — OBS-20's gate numbers, before its run.

The queue item OBS-19 pointed at, in Astra's words:

    a hard cutoff, error-weighted selection within its eligible pool,
    matched uniform selection, and replicated policies.

    Its key contract: IDENTICAL ELIGIBLE OBSERVATIONS for both selections,
    with the cutoff preventing EITHER rule from retaining an expired
    sample.

OBS-19 established that an EXPONENTIAL recency price can be PAID: whatever
survives had to outbid the window, and on a moved world what outbids it is
adversely selected, because A-era surprise already concentrates on the
structure the worlds will later disagree about.  err@tau carried 276 wrong
labels of 8192 against uni@tau's 37.

It also established, under a same-points refresh control, that THE
LOCATIONS ARE NOT THE PROBLEM: given current labels the error-selected
points reach 0.02866 and 0.03004 against the ring's 0.04650, 38% and 35%
lower error.  A hard cutoff cannot be bought past at any weight.  So the
question this phase exists to answer is whether it delivers that arm
WITHOUT AN ORACLE.

    python3 tools/obs20_predict.py
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


N = 8192            # replay slots handed to the sleep, every arm
WAKE_A = 30_000     # observations in world A
M = 16_384          # B observations before the sleep (M/N = 2.0, OBS-19's late offset)
TOTAL = WAKE_A + M

print(__doc__.split("\n\n")[0])
print()
print("=" * 78)
print("  THE CONTRACT, AND WHY IT DECIDES THE IMPLEMENTATION")
print("=" * 78)
print("""
  A reservoir maintained per rule cannot honour "identical eligible
  observations": two A-Res streams over the same input keep different
  subsets, and every comparison then confounds SELECTION with WHICH POOL
  EACH RULE HAPPENED TO KEEP.  OBS-18 and OBS-19 both had that confound and
  both had to reason around it.

  So the eligible pool becomes a LITERAL SHARED OBJECT: one ring of the
  last W observations, deterministic, no sampling anywhere in it, and both
  rules select their N from THE SAME BYTES.  The gate can then assert the
  contract rather than argue it.

  Selection happens AT THE SLEEP rather than at admission.  A-Res over a
  static pool is exactly weighted sampling without replacement, and drawing
  the keys once at read time is cleaner than carrying them: a hard cutoff
  has no incumbent to be bit-identical to.

  This also separates two things OBS-18 and OBS-19 held together:

      WHAT YOU KEEP        the window, W observations
      WHAT YOU CONSOLIDATE ON   the selection, N of them

  The honest price of a hard cutoff is that first number.  The exponential
  form stores N and nothing else; a hard window stores W.
""")
print("  storage, in observations retained:")
for mult in (1, 2, 4):
    W = mult * N
    print("    W = %dN = %6d   %5.2fx the exponential form's %d" % (mult, W, W / N, N))
print()

print("=" * 78)
print("  REGISTERED: the eligible pool, which is DETERMINISTIC")
print("=" * 78)
print("  A window is a ring, so its composition needs no simulation at all —")
print("  it is the last W observations, and arithmetic says what is in it.")
print()
print("    %-8s %8s %9s %9s %11s" % ("W", "pool", "pre-move", "share", "verdict"))
pools = {}
for mult in (1, 2, 4):
    W = mult * N
    lo = TOTAL - W
    pre = max(0, WAKE_A - lo)
    pools[mult] = (W, pre / W)
    verdict = ("DEGENERATE: pool == N, no selection" if W == N else
               "CLEAN: entirely post-move" if pre == 0 else
               "STRADDLES the move")
    print("    W = %dN %8d %9d %8.3f   %s" % (mult, W, pre, pre / W, verdict))
print()
print("  W = 2N is CLEAN because it exactly equals M, the observations since")
print("  the move — and that is the fixture's timing, not a property any")
print("  policy knows. W = 4N reaches 16384 observations back past the move,")
print("  so HALF its pool is pre-move. **A hard cutoff guarantees")
print("  ELIGIBILITY, not VALIDITY.**")
print()

# Wrong labels: contested AND pre-move. Contested share is the fixture's.
random.seed(20_2026)
MC = 200_000
contested = 0
for _ in range(MC):
    p = (random.random(), random.random(), random.random())
    if abs(truth(p, A_SHIFT) - truth(p, B_SHIFT)) > 1e-3:
        contested += 1
contested /= MC
print("  contested share of the cube, Monte-Carlo over %d points: %.4f" % (MC, contested))
print()
print("    %-8s %14s %22s" % ("W", "pre-move share", "wrong labels if uniform"))
for mult in (1, 2, 4):
    W, pre = pools[mult]
    print("    W = %dN %13.3f %18d of %d" % (mult, pre, round(pre * contested * N), N))
print()
print("  An ERROR selection concentrates on contested points, so its wrong-label")
print("  count at W = 4N must EXCEED the uniform figure — OBS-19's mechanism")
print("  with the price replaced by a cutoff. At W = 2N both are exactly ZERO,")
print("  and that is the contract doing its work.")
print()

print("=" * 78)
print("  THE REGISTERED PREDICTIONS")
print("=" * 78)
print("""
  Q1  THE CONTRACT.  The two rules' eligible pools are byte-identical, and
      no slot in either is older than W.  Asserted, not argued — this is
      the premise the phase is built on and OBS-18/19 could not state it.

  Q2  THE DEGENERATE CHECK.  At W = N the pool IS the buffer, so every rule
      selects all of it and every rule reduces EXACTLY to the ring —
      whatever its measure. A cheap structural assertion, and it says the
      window and the measure are wired to each other correctly.

  Q3  ZERO WRONG LABELS AT W = 2N, BY CONSTRUCTION, for both rules. At
      W = 4N the error rule carries MORE wrong labels than the uniform one,
      which is OBS-19's adverse selection surviving the change of mechanism.

  Q4  *** THE HEADLINE. hard-err@2N beats the RING on the current world,
      clearing the spread. *** This is the synthesis OBS-19 could only
      reach with an oracle: error-selected locations, zero wrong labels,
      nothing relabelled. OBS-19's refresh control put that arm at 0.02866
      and 0.03004 against the ring's 0.04650.

      Registered as an inequality against the ring, NOT at those values.
      The refresh control chose its locations by error weighting over the
      WHOLE history and then relabelled them; hard-err@2N chooses over the
      B era only. Different location distributions, so this is not a
      straight cash-in and must not be written up as one.

  Q5  *** THE MEASURE, AT LAST UNCONFOUNDED. hard-err@2N beats
      hard-uni@2N. *** Identical pools by construction, identical k,
      identical everything but the expression in the weight — the cleanest
      test of error weighting the campaign can run. OBS-19 could only reach
      this at MATCHED staleness (0.639 against 0.659) rather than identical
      pools.

  Q6  THE LIMIT. At W = 4N the error rule's advantage collapses or
      reverses, because the cutoff no longer excludes pre-move data. A hard
      cutoff cannot be bought past, but it can be set too WIDE — and
      nothing tells a policy where the last regime change was. Registered:
      gain(hard-err@4N) < gain(hard-err@2N), clearing spread.

  Q7  HARD AGAINST EXPONENTIAL, the direct OBS-19 comparison at matched
      N and k: hard-err@2N beats err@tau. If Q4 holds this follows, but it
      is registered separately because it is the phase's reason to exist.

  Q8  THE COST, registered as a trade rather than a hope. hard-err@2N
      retains world A WORSE than err@tau, because err@tau holds 276 A-era
      labels and hard-err@2N holds none. OBS-18's finding: retention rides
      on labels.

  Q9  THE PRICE OF THE CUTOFF. It is storage, and it is W rather than N:
      2x at W = 2N, 4x at W = 4N. The exponential form needed no expiry
      machinery and no extra storage; this needs the window. Reported, not
      thresholded.
""")
print("=" * 78)
print("  WHAT WOULD REFUTE THE PHASE OUTRIGHT")
print("=" * 78)
print("""
  - If Q1 fails the pools are not shared and nothing below it is a clean
    comparison — the whole point of the redesign.
  - If Q4 fails, a hard cutoff does NOT deliver OBS-19's oracle arm, and
    the honest reading is that error-selected locations are worth less than
    the refresh control suggested — that the control's advantage came
    partly from choosing over the whole history, which a cutoff forbids.
  - If Q5 fails at identical pools, error weighting does not pay at all on
    this fixture, and OBS-18's location finding needs re-examining rather
    than extending.
""")
