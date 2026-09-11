#!/usr/bin/env python3
"""obs19_predict — OBS-19's gate numbers, before its run.

The queue item, recorded at the close of OBS-18 and sharpened by Astra:

    Pre-register WINDOWED ERROR REPLAY as a TRADEOFF hypothesis: can it
    improve current-world fitting without giving up too much prior-world
    retention?  With matched recent/uniform controls, observations placed
    AROUND the transition rather than 20 000 clear of it, and the error
    policy replicated.

OBS-18 left the two halves of a replay buffer separated:

    a buffer's LOCATIONS decide how well it fits the world it is labelled
    for; its LABELS decide which world that is

and its Pareto surface was exactly that split showing through — the ring
took the current world (all its labels describe it) while the unbounded
error reservoir preserved the old one (half of its labels still describe
THAT).  Windowed error replay is the obvious synthesis: error's locations,
the ring's labels, and no oracle anywhere.

    python3 tools/obs19_predict.py
"""
import heapq
import math
import random

TAU = 6.283185307179586
SHELL_C = (0.30, 0.62, 0.46)
SHELL_R, SHELL_W, SHELL_A = 0.20, 0.025, 0.9
SWELL_A, WINDOW_LO, WINDOW_HI = 0.35, 0.55, 0.70
A_SHIFT = (0.0, 0.0, 0.0)
B_SHIFT = (0.0, -0.10, 0.0)      # OBS-13..18's move, and MARL-6's


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


# ── THE FIXTURE, as OBS-19 will actually run it ───────────────────────────
#
# N and k are OBS-18's.  What moves is WHEN the sleep happens: OBS-18 slept
# 20 000 observations clear of the move, so its ring was full of the new
# world BY THE FIXTURE'S TIMING and not by anything intrinsic to rings.
# Astra's risk note, recorded verbatim at the close of that phase:
#
#     a recency window can straddle a regime change (the ring was
#     label-consistent here only because 20 000 B observations flushed all
#     8 192 slots — the fixture's timing, not a property of rings)
#
# So the sleep happens TWICE in one life, at M/N = 0.5 and M/N = 2.0, and
# M/N is the quantity the phase is really about.
N = 8192            # replay slots, every arm
WAKE_A = 30_000     # observations in world A
EARLY = 4_096       # B observations before the first sleep   (M/N = 0.5)
LATE = 16_384       # B observations before the second sleep  (M/N = 2.0)
WINDOW_TAU = 4_096  # the recency E-FOLDING time (half-life tau*ln2 = 2839)

print(__doc__.split("\n\n")[0])
print()
print("=" * 78)
print("  A RECENCY WINDOW IS AN EXCHANGE RATE")
print("=" * 78)
print("""
  A-Res holds key = u^(1/w).  Bias it for recency by letting the weight
  grow with the observation index, w_eff = w * exp(t/tau); in logs the key
  is ln(u)*exp(-t/tau)/w, fixed at admission and correct at every later
  time because exp(T/tau) is a factor common to every slot.

  So the whole of "windowed" is one multiplication, and what tau buys is a
  PRICE rather than a cutoff:

      an exemplar may be  dt = tau * ln(w2/w1)  observations older
      for every factor    w2/w1  of extra weight it carries

  tau = %d therefore says: a factor e of surprise buys %d observations of
  age; a factor of 55 buys %d, which is 2N.  A hard window cannot say this
  at all — inside it every point is equal and outside it none exists.

  tau is an E-FOLDING time, not a half-life; the half-life is tau*ln2 = 2839.
  And a PRICE CAN BE PAID: whatever survives an exponential window had to
  outbid it, which is the phase's result and not its premise.
""" % (WINDOW_TAU, WINDOW_TAU, 4 * WINDOW_TAU))

# ── WHY tau = N/2, derived rather than chosen ─────────────────────────────
#
# The reservoir keeps the N largest keys.  For weight w and threshold c an
# item at index t survives with p(t) = 1 - exp(-c*w*exp(t/tau)), which is
# ~0 four tau below the crossing and ~1 two tau above it: the buffer is the
# most recent N items with a SOFT EDGE about 4*tau wide.
#
# That is the whole design constraint.  If 4*tau << the fresh pool the edge
# never reaches back past the newest N and the measure has nothing left to
# choose between — a window that tight IS a ring, whatever weight it
# carries.  Making the edge span the fresh pool at the late offset:
#
#       4 * tau ~ M_late = 2N   =>   tau ~ N/2
print("  tau is DERIVED, not picked: the soft edge of an exponentially")
print("  biased reservoir is about 4*tau wide, and it must span the fresh")
print("  pool or the measure has nothing to choose between.")
print("    4*tau ~ M_late = 2N  =>  tau ~ N/2 = %d" % (N // 2))
print()


def simulate(stream, tau, seed):
    """A-Res with recency bias, exactly as `Replay.admit` will do it.

    `stream` is a list of (t, weight, payload); returns the surviving
    payloads.  Weight 1 throughout is the uniform family, which is the only
    one Python can reproduce: the error weights are the model's own
    surprise trajectory and do not exist outside the run.
    """
    rnd = random.Random(seed)
    heap = []  # (key, tie, payload) min-heap
    for t, w, payload in stream:
        k = math.log(max(1e-12, rnd.random())) / w
        if tau:
            k *= math.exp(-min(700.0, t / tau))
        if len(heap) < N:
            heapq.heappush(heap, (k, t, payload))
        elif k > heap[0][0]:
            heapq.heapreplace(heap, (k, t, payload))
    return heap


# One stream, drawn once, offered to every rule — as `wakeAll` does it.
random.seed(19_2026)
pts = []
for t in range(WAKE_A + LATE):
    p = (random.random(), random.random(), random.random())
    ya, yb = truth(p, A_SHIFT), truth(p, B_SHIFT)
    pts.append((t, p, abs(ya - yb) > 1e-3, p[0] > WINDOW_HI))


def compose(slots, cut):
    """`compositionOf`'s three reported shares, plus staleness by TIME.

    `stale` is OBS-18's: the share of CONTESTED slots recorded under the
    old world.  `old` is new here and is the blunter question — the share
    of slots, contested or not, observed before the move — because at
    M < N there is an arithmetic floor under it and the phase turns on it.
    """
    n = len(slots)
    contested = sum(1 for t, _, c, _ in slots if c)
    stale = sum(1 for t, _, c, _ in slots if c and t < cut)
    return dict(
        contested=contested / n,
        stale=(stale / contested) if contested else 0.0,
        dead=sum(1 for _, _, _, d in slots if d) / n,
        old=sum(1 for t, _, _, _ in slots if t < cut) / n,
        median_age=(cut + M) - sorted(t for t, _, _, _ in slots)[n // 2],
    )


print("=" * 78)
print("  REGISTERED: the buffer's composition, for the rules Python can run")
print("=" * 78)
print("  (the error family cannot be simulated here — its weights are the")
print("   model's own surprise, which exists only inside the run — so its")
print("   predictions below are ORDINAL and carry OBS-18's measured 2.5x)")
print()
rows = {}
for label, M in (("EARLY  M/N=0.5", EARLY), ("LATE   M/N=2.0", LATE)):
    cut = WAKE_A
    stream = [(t, 1.0, None) for t, _, _, _ in pts[:WAKE_A + M]]
    idx = {t: rec for rec in pts for t in (rec[0],)}
    print("  %s   %d A-observations then %d B" % (label, WAKE_A, M))
    print("    %-14s %9s %7s %7s %7s" % ("rule", "contested", "stale", "dead", "old"))
    floor = max(0.0, (N - M) / N)
    for rule, tau in (("recent", None), ("uniform", 0), ("uni@tau", WINDOW_TAU)):
        if rule == "recent":
            slots = [idx[t] for t in range(WAKE_A + M - N, WAKE_A + M)]
        else:
            heap = simulate([(t, 1.0, None) for t, _, _, _ in pts[:WAKE_A + M]], tau, 0xA1)
            slots = [idx[t] for _, t, _ in heap]
        c = compose(slots, cut)
        rows[(label, rule)] = c
        print("    %-14s %9.4f %7.3f %7.3f %7.3f" % (
            rule, c["contested"], c["stale"], c["dead"], c["old"]))
    print("    staleness FLOOR by arithmetic, (N-M)/N = %.3f  — no rule can beat it" % floor)
    print()

print("=" * 78)
print("  THE REGISTERED PREDICTIONS")
print("=" * 78)
print("""
  P1  PREMISE, EARLY.  The ring STRADDLES: its `old` is 0.500 exactly,
      against OBS-18's 0.000.  Every arm's `old` >= 0.500, because only
      4 096 fresh observations exist to fill 8 192 slots.  If this fails
      the phase has not placed the sleep where it said it did.

  P2  PREMISE, LATE.  The ring is clean again: `old` = 0.000 exactly, and
      `stale` = 0.000.

  P3  THE WINDOW WORKS.  uni@tau `old` < uniform `old` at both offsets, and
      at LATE uni@tau `old` < 0.05 where uniform's is ~0.65.

  P4  THE MEASURE SURVIVES THE WINDOW.  err@tau contested > 2.5x uni@tau
      contested — OBS-18's threshold, carried over unchanged rather than
      re-tuned, where it measured error 0.3138 against uniform 0.0996.

  P5  *** THE HEADLINE.  At LATE, windowed error replay fits the current
      world BETTER THAN THE RING, clearing both rules' own spreads. ***
      OBS-18's location table is the reason to expect it: given current
      labels, error-chosen locations beat uniform's by 3.07x its spread
      (gain 0.6399 against 0.3896, with the ring's policy gain 0.3456).
      err@tau is that arm built WITHOUT the oracle.  Registered at
      gain(err@tau) > gain(recent) + spread.

  P6  THE COST.  At LATE, err@tau retains the old world WORSE than
      unbounded error does: held(err@tau) > held(error), clearing spread.
      Retention rides on LABELS (OBS-18), and err@tau has none from A.
      So the tradeoff is real and the answer to "without giving up too
      much retention" is NO, measured against unbounded error.

  P7  THE OPEN ONE, and the phase's reason to exist.  Is err@tau better
      or worse than THE RING at retention?  Both carry only B labels, so
      OBS-18 says this is a pure LOCATION question — and its relabelled
      A-held column had error at 0.13467 against recent's 0.13026, a gap
      INSIDE the spread.  Registered as NOT SEPARATED: |held(err@tau) -
      held(recent)| < spread.  If it holds, windowed error replay
      DOMINATES the ring — strictly better immediate fit at retention that
      is not measurably worse — and the ring leaves the Pareto surface it
      was put on by OBS-18.

  P8  *** THE LAW.  M/N governs whether a window can price staleness at
      all. *** At M < N every rule must carry the same (N-M)/N of stale
      slots, so the window has no fresh alternative to buy; and an error
      rule then spends its remaining budget on the points where the model
      was MOST WRONG, which on a moved world is exactly where the stale
      labels are most wrong.  Registered: err@tau's advantage over the
      ring on immediate fit is SMALLER AT EARLY THAN AT LATE, and may
      reverse.  A window can only price staleness it has an alternative to.

  P9  THE SPREAD FLOOR, per rule.  The ring is the one rule that needs no
      replicate: it is a deterministic function of the stream, so its
      same-rule spread is ZERO BY CONSTRUCTION and a ring-vs-X comparison
      correctly uses X's own spread.  Every other rule is replicated.
""")

print("=" * 78)
print("  RECORDED BEFORE THE RUN: what would refute the phase outright")
print("=" * 78)
print("""
  - If P1 fails, the sleep is not near the transition and every EARLY
    number is measuring OBS-18's fixture again.
  - If P3 fails the window is not a window and nothing below it means
    anything.
  - If P5 fails, windowed error replay is not worth its multiplication:
    the oracle advantage OBS-18 measured does not survive being earned
    honestly, and the ring stays on the surface.
  - A SILENT FAILURE worth naming because it inverts the rule rather than
    breaking it: exp(-t/tau) UNDERFLOWS to zero past t/tau = 745, and a
    key of -0.0 sorts ABOVE every live key — so the OLDEST exemplars would
    become unevictable.  Clamped at 700 in the code, with its own check.
""")
