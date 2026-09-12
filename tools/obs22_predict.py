#!/usr/bin/env python3
"""obs22_predict — OBS-22's design and numbers, before its run.

Astra's framing, which replaces the one this phase nearly got built on:

    I'd frame it as "when is intervention worth its cost?" rather than
    requiring a detector to identify a regime change.  Surprise can also
    rise because the model is undertrained or observations are noisy.

    Can an online trigger allocate a fixed intervention budget better than
    a schedule, without being told the change time?

Every phase from OBS-18 to OBS-21 assumed someone said when the world moved.
This is the first where the policy has to decide.

**"Detect the change" is ill-posed here and that is deliberate.**  The
trajectory contains a GRADUAL DRIFT, during which there is no instant to
name.  "Is an intervention worth its cost now" stays well-posed throughout.

This file is the SECOND draft.  The first was reviewed before any code was
written and had three contract bugs in it: a trigger calibrated on data from
the future it was being tested on, a budget promised as exact while the
policy was allowed to stay silent, and an unstated clock.  Every amendment
below is Astra's.

    python3 tools/obs22_predict.py
"""
import math

# ── THE CLOCK, PINNED FIRST ───────────────────────────────────────────────
#
# **Every paid observation advances the common clock**, revisits included,
# and each is evaluated against the world AT THAT INSTANT.  Gradual drift
# continues through an intervention.  Otherwise a targeted arm receives extra
# learning while the environment politely waits for it.
#
# Ordering, where a query, a checkpoint and a sleep coincide at index i:
#     1. the observation at i is made and learned from
#     2. if an intervention completes at i, the sleep runs
#     3. if i is a checkpoint, the model is scored — AFTER any sleep
# so a checkpoint never reports a model that is about to be replaced.
#
# Checkpoints are at fixed GLOBAL indices, identical across every arm, and
# use ONE probe point set re-valued against the world at that instant.
# **Time-averaged error is the MEAN RMS over checkpoints**, not pooled MSE.
CHECK = 2000

PHASES = [
    ("cold start in A",      0,      12_000, "surprise high and FALLING: undertrained, not moved"),
    ("stationary A",         12_000, 30_000, "the null, with a settling model"),
    ("abrupt change to B",   30_000, 48_000, "a step. the easy case"),
    ("stationary B",         48_000, 60_000, "the null again, now well fitted"),
    ("gradual drift B -> C", 60_000, 90_000, "NO INSTANT TO NAME. detection ill-posed"),
    ("stationary C",         90_000, 104_000, "settle, and score the tail"),
]
TOTAL = PHASES[-1][2]
DRIFT_LO, DRIFT_HI = 60_000, 90_000

# ── THE INTERVENTION, FROZEN AND FULLY SPECIFIED ──────────────────────────
#
# "OBS-21 exactly" is not enough once interventions repeat at different
# population sizes, so the rule is stated rather than referenced:
#
#   ACQUIRE   R re-observations at the R highest-surprise locations in the
#             window, ranked by STORED surprise, chosen once before any of
#             them is made.  Each pushes into the window and advances the
#             clock.
#   SLEEP     consolidate to k = (population at the moment of the sleep) / 2,
#             selecting N points from the window by error-weighted A-Res.
#   STATE     the child replaces the model via `adopt`, which resets Adam
#             moments, `mu0` and update counts — a consolidated kernel is a
#             new element, not the ancestor it was selected from.
R = 4096
W = 16384
N = 8192
BUDGET = 3          # AT MOST three. See below.

# ── THE DETECTOR'S FEEDBACK CONTRACT ──────────────────────────────────────
#
# Targeted queries have a different surprise distribution from uniform ones,
# so feeding their residuals to the detector lets an intervention manufacture
# its own next alarm.  Therefore:
#
#   * the detector updates from MONITORING observations only — the ordinary
#     uniform stream.  Revisit queries enter the replay window and the model,
#     and never the detector.  `monitor` itself refuses to update while busy,
#     AND the controller is asserted not to call it — belt and braces,
#     because the first structural draft could not have caught a controller
#     that routed acquisition queries into the detector.
#   * firing is paused for the duration of an intervention.
#   * the cooldown is counted in MONITORING observations.
#
# The cooldown of W is a HEURISTIC and not a guarantee: an intervention
# pushes R = W/4 entries and changes the model, and the slow EWMA carries
# influence well past that.  Stated as such.
H_FAST, H_SLOW = 2048, 16384
COOLDOWN = W

print(__doc__.split("\n\n")[0])
print()
print("=" * 78)
print("  THE TRAJECTORY: surprise rises for three reasons, not all worth acting on")
print("=" * 78)
for name, a, b, why in PHASES:
    print("  %-22s %6d..%-6d  %s" % (name, a, b, why))
print("\n  %d observations. Drift interpolates the shift LINEARLY from B to C" % TOTAL)
print("  over %d..%d, so the world moves during any intervention placed there." % (DRIFT_LO, DRIFT_HI))
print()

print("=" * 78)
print("  AMENDMENT 1 — CALIBRATION MUST NOT SEE THE FUTURE")
print("=" * 78)
alpha_f = 1 - 2 ** (-1.0 / H_FAST)
alpha_s = 1 - 2 ** (-1.0 / H_SLOW)
print("""
  The first draft estimated the threshold from observations 12 000-30 000 and
  then tested whether the trigger stayed quiet BEFORE 12 000.  That is a
  trigger calibrated on its own future.

  Fixed: a SEPARATE, explicitly designated CALIBRATION TRAJECTORY, its own
  seed, never scored.  `k` is frozen from it before any evaluation begins.

  And the EWMAs need an initialisation contract, because with both started at
  zero their first nonzero ratio is alpha_fast/alpha_slow = %.4f/%.6f = %.2f —
  an alarm manufactured entirely by the update rates.

  **Seeding waits for the first NONZERO surprise.**  Seeding on the first
  surprise whatever it is does NOT fix this when that surprise is zero: both
  accumulators start at zero again and the next positive value reopens the
  ratio at 8.  And this fixture HAS an exactly-zero region — past the window
  the target is zero, an empty model predicts zero, the residual is exactly
  zero.  So `0, 0, positive` is a real history and is tested as one.  Until
  the seed arrives the ratio is 1, firing is refused, and the denominator is
  floored at 1e-9.

  The frozen threshold is PRINTED before evaluation.  If calibration returns
  a value below 1, even the neutral seeded ratio exceeds it and the detector
  fires constantly; that is reported, never silently clamped.

  The threshold is registered as  mean(ratio) + 3*sd(ratio)  over the
  calibration trajectory's stationary stretch — NOT 1 + 3*sd.  A stationary
  world does not imply a ratio centred at one, because the learner's own
  residuals are not stationary.

  **Three standard deviations is a registered heuristic, not a calibrated
  false-alarm probability.** The checks are thousands and heavily correlated;
  nothing here computes a family-wise rate.
""" % (alpha_f, alpha_s, alpha_f / alpha_s))

print("=" * 78)
print("  AMENDMENT 2 — AT MOST THREE, NOT EXACTLY THREE")
print("=" * 78)
print("""
  A threshold policy cannot promise a firing count while being allowed to
  stay silent through drift.  The first draft said "every arm spends exactly
  three interventions", which also contradicted `none`, which sleeps zero
  times.

  Registered: **at most %d interventions**.  Every arm runs the same
  observation horizon of %d; unspent intervention capacity is spent as
  ordinary fresh monitoring observations, so the OBSERVATION budget is
  matched exactly and the INTERVENTION count is an outcome.  Actual sleeps
  and fitting cost are reported per arm, not assumed.

  **READINESS, and when the budget is charged.**  A crossing is not an
  intervention.  An intervention may begin only when the window is FULL (it
  has locations to choose from) and at least R queries REMAIN before the
  horizon (it can finish what it starts).  Budget is charged when one
  BEGINS, never on a crossing.

  An unready request is **DEFERRED, not discarded**: it is re-evaluated every
  step and runs once the window fills, so a schedule cannot lose an
  intervention to an accident of timing and a trigger re-crosses naturally.
  A request that cannot finish before the horizon is BLOCKED outright — it is
  better to leave capacity unspent than to truncate an intervention.

  **Both refusals are counted and reported**, because they are the difference
  between a policy that did not want to act and one that was not allowed to.
""" % (BUDGET, TOTAL))

print("=" * 78)
print("  AMENDMENT 3 — THE REFERENCE ARM IS PRIVILEGED, NOT OPTIMAL")
print("=" * 78)
print("""
  `informed` is a PRIVILEGED TIMING REFERENCE and not an upper bound.
  Immediate intervention can be badly timed: too little current evidence, or
  a better return from waiting.  The online policy is ALLOWED TO BEAT IT, and
  if it does, that refutes this particular reference schedule's optimality
  rather than showing timing information is worthless.

  Its placements, stated rather than described as "immediately after each
  change": acquisition BEGINS at %d (the step), %d (drift onset) and %d
  (drift end), with the sleep running when that acquisition completes, %d
  observations later.
""" % (30_000, DRIFT_LO, DRIFT_HI, R))

print("=" * 78)
print("  THE ARMS")
print("=" * 78)
sched = [round(TOTAL * (i + 1) / (BUDGET + 1)) for i in range(BUDGET)]
print("""
    trigger    updates from MONITORING observations only; fires on the
               timescale ratio; at most %d times.
    schedule   acts at fixed intervals, detecting nothing — %s. Not a straw
               man: a fixed cadence is what a system without a trigger does.
    informed   the privileged timing reference above.
    none       spends the whole horizon on ordinary observations and never
               consolidates. The END-TO-END question — does intervening earn
               its cost at all — and it deliberately does not isolate
               acquisition placement. Kept on Astra's instruction.
""" % (BUDGET, sched))

print("=" * 78)
print("  THE REGISTERED PREDICTIONS")
print("=" * 78)
print("""
  Q1  THE MATCH.  Every arm runs the same observation horizon and is scored
      at the same checkpoints on the same probe points.  Intervention counts
      and sleep counts are OUTCOMES and are reported. Asserted.

  Q2  THE COLD-START TRAP, asked of the STATISTIC and not of the executions.
      **Readiness gates every cold-start intervention regardless of what the
      detector wanted** — the window is not full until 16 384, later than the
      whole cold start — so a restraint claim tested on executions would be
      vacuous.  What is registered is that the detector never CROSSES before
      the world first moves.  G69 (a) already measures this on a scaled
      config: 0 cold-start crossings, first crossing after the change.

      **And firing there is not defined as an error.** A stationary or
      undertrained model might genuinely benefit from targeted acquisition.
      If it crosses, whether acting helped is MEASURED, not assumed.

  Q3  THE STEP.  The trigger fires within %d monitoring observations of
      t = 30 000.  The easy case, registered as such.

  Q4  *** THE DRIFT.  Trigger beats schedule on time-averaged error over
      phases 5-6, clearing the acquisition spread. ***  Success there need
      not show drift sensitivity — it can reflect earlier decisions — so the
      gate prints BUDGET REMAINING AT DRIFT ONSET and every firing time.

  Q5  THE REFERENCE GAP, reported as a signed number rather than a bound.
      A trigger that beats `informed` refutes that schedule, not the value of
      timing information.

  Q6  ACTING BEATS NOT ACTING.  Every intervening arm beats `none` on
      time-averaged error.

      **If one arm loses to `none`, that says THAT SCHEDULE failed to earn
      its cost on THIS trajectory — not that OBS-21's conditional result is
      invalid.** OBS-21 measured a single well-placed intervention against
      uniform alternatives at one offset; this measures placements over a
      whole life. They can disagree without either being wrong.

  Q7  INTERVENTIONS BY PHASE, reported and NOT scored as false alarms.  For
      each arm: how many interventions landed in each phase, and what the
      error did over the following %d observations.  A stationary-phase
      firing is not automatically a mistake and a change-phase firing is not
      automatically useful.
""" % (R, CHECK * 2))

print("=" * 78)
print("  THE INITIALISATION DIAGNOSTIC — ALTERNATIVE SPECIFIED BEFORE MEASURING")
print("=" * 78)
print("""
  Q2 is refuted and the trace DESCRIBES why without establishing it: the two
  trajectories seed their EWMAs on 0.049409 and 0.006119, an eightfold gap,
  because trajectory 5678's first observation has EXACTLY zero surprise (the
  fixture's zero region) and the "first nonzero" rule then takes an
  atypically small second draw.  The slow EWMA's half-life is 16 384
  monitoring updates, so the seed's contribution HALVES there and remains
  relevant afterwards — it is not a cutoff.

  **Both EWMAs are seeded from a SINGLE observation.** That is the weakness
  the trace points at, so the alternative is specified now, before it is
  measured:

      RULE B: seed both EWMAs with the MEAN of the first B = 256 nonzero
              monitoring surprises, and refuse to fire until seeded.

  B = 256 is chosen as a round number well below the fast half-life of 2048,
  so the seed is established before the fast EWMA has moved appreciably, and
  far above 1, so it is an ESTIMATE rather than a DRAW.  The surprises
  consumed during seeding establish the seed and are not otherwise fed.

  THE TEST: replay the IDENTICAL recorded surprise sequence from both
  trajectories through rule A (the current single-draw seed) and rule B,
  with the threshold FROZEN at the same calibrated value.  Because the
  sequence is fixed, nothing differs but the initialisation.

  REGISTERED: under rule B the cold-start above-threshold ticks fall
  substantially on 5678 and stay at zero on 1234.  **If they do not,
  seeding is not the cause and the trace's story is wrong.**

  AND A LIMIT, stated before the run rather than after it: the threshold was
  calibrated under rule A.  Changing the initialisation changes the ratio's
  distribution, so a DEPLOYED alternative would need its own calibration.
  Freezing the threshold is right for isolating initialisation and wrong for
  evaluating a policy — this is a diagnostic, and a new trigger policy would
  be a separate registered experiment.
""")

print("=" * 78)
print("  BUILD ORDER, AND COST")
print("=" * 78)
sleeps = 3 * BUDGET * 2
print("""  Astra's instruction, and it is the lesson of OBS-21 applied before the
  fact: **build the cheap structural checks first.** G69 (a) validates the
  clock, the calibration freeze, the budget accounting and the detector's
  feedback contract with NO SLEEPS, in seconds. Only then does the expensive
  comparison run.

  G69 is at most %d sleeps (3 intervening arms x %d x 2 evaluation
  trajectories) at ~30 s, plus a calibration trajectory that sleeps never.
  Both evaluation trajectories are PRESERVED: shortening the stationary
  stretches would change false-alarm exposure and calibration quality, so it
  is a design change and not a runtime optimisation.

  The trigger needs NO ADDITIONAL SENSING QUERIES — surprise is already
  returned by `observe`. Its EWMA arithmetic is small but not zero.

  CALIBRATION IS PINNED: seed 0x0CA1, the same %d-observation trajectory
  shape, sampled at every monitoring observation, and the variance is the
  POPULATION standard deviation over the stationary stretch 12 000-30 000 of
  that trajectory alone. It is never scored and never reused as an
  evaluation arm.""" % (sleeps, BUDGET, TOTAL))
