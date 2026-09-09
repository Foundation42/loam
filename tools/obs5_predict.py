#!/usr/bin/env python3
"""obs5_predict — OBS-5's gate numbers, before its run.

OBS-4 ended on a diagnostic that was scoped honestly and stopped:

    Continued optimisation alone is sufficient to create false birth
    pressure on stationary, noiseless data already fitted accurately.
    This isolates an optimiser-related mechanism; it does not yet isolate
    which part of Adam/finite-precision dynamics causes it.

Three seeds, train RMS 2.2e-7 at the checkpoint rising to 6.4e-4 under
continued updates, 7/8/10 birth requests against 0 for a held state.

**Its subject is the core learner, so its consequence is campaign-wide.**
Population has been a headline in MARL-7 (linear growth at flat accuracy),
MARL-9 and MARL-10 (the K0 + A*H(N) law), MARL-20 (200 kernels a move) and
every occlusion phase. If a converged model births from optimiser churn
rather than from structure, some fraction of each of those numbers is the
instrument and not the signal. And the observational note asks population
to BE an instrument — §12 "An Endogenous Complexity Instrument" and §31
"The Representation as an Instrument" — which cannot be used before it is
calibrated for its own noise floor.

    python3 tools/obs5_predict.py
"""

import math

print(__doc__.split("\n\n")[0])
print()
print("=" * 74)
print("OBS-5 — the churn floor.  PRE-REGISTERED, before the run")
print("=" * 74)

print("""
(1) THE MECHANISM, AS FAR AS IT CAN BE DERIVED FROM THE TWO UPDATE RULES

Read side by side, `src/adaptive_inferred.zig`'s optimiser and
`src/marl.zig`'s two, they differ in exactly the property that matters.

ADAM  (adaptive_inferred.Model.update, and marl.Marl(C).adam, identically)

    w -= lr * mhat / (sqrt(vhat) + eps)

    mhat and vhat are the gradient's own first and second moments, so
    their RATIO is dimensionless and of order one WHENEVER the gradient is
    large enough that eps does not dominate.  The step is therefore

        |dw| ~ lr   per parameter per update, INDEPENDENT OF |g|

    That is what "adaptive" means and it is the whole point of Adam: it is
    SCALE FREE.  At a converged point on noiseless stationary data the
    gradient is small, the ratio is not, and the parameters keep moving at
    the full step size.  Adam at a fixed learning rate does not converge —
    it wanders in a ball whose radius is set by lr, which is textbook and
    is why every practical schedule decays.

NLMS  (marl.zig's default, the campaign's every headline)

    w[c] -= rate_w * a[c],        a = e * g / sum(g^2)
    geometry by  wa = (sum_c w_c a_c) * GEOM_RATE * rate_geom

    Both steps are LINEAR IN THE RESIDUAL e.  As the fit converges the
    step vanishes with it.  NLMS is self-quenching; Adam is not.

So the hypothesis is specific, and it is a statement about optimisers and
not about MARL:

    the churn floor belongs to the SCALE-FREE STEP, so it should appear
    wherever Adam is mounted -- including MARL's own `--optimizer adam` --
    and should be ABSENT under MARL's NLMS default

Which is a prediction that can fail in three distinct ways, and each of
them means something different.  They are listed at (5).
""")

print("""(2) G52 (a) — THE MECHANISM, ON OBS-4's OWN FIXTURE

Astra's diagnostic, re-run with the learning rate as the swept variable.
If the wander is Adam's fixed step, it is LINEAR IN lr and does not care
how good the checkpoint fit was.

    PREDICTED  halving lr from 0.003 to 0.0015 at least halves the
               maximum train RMS reached over the continued run:

                   max_train(lr/2) / max_train(lr)  <=  0.60

               stated with slack against the exact 0.5, because the
               relationship between parameter wander and train RMS is a
               local quadratic and only the leading term is derived.

    PREDICTED  a decayed schedule drives the birth requests to ZERO at
               all three seeds -- an equality, not a threshold, and the
               sharpest form of the claim.  TWO schedules are registered,
               both now and both before the run, because the horizon is
               short and the milder one may not have room to work:

                   lr_t = lr0 / sqrt(t / t0)     t0 = 800, so 2.12x by 3600
                   lr_t = lr0 / (t / t0)         t0 = 800, so 4.50x by 3600

               If 1/sqrt(t) leaves requests standing and 1/t removes them,
               the mechanism is confirmed and the schedule is a tuning
               question.  If NEITHER does, that is outcome (iii) at (5)
               and the birth score is implicated rather than the rate.

    NOT PREDICTED  the exact wander.  It depends on how the gradient's
                   sign structure decorrelates along the walk, which is a
                   property of this fixture's curvature and not of Adam.""")
for lr in (0.003, 0.0015, 0.00075):
    n = 2800
    print(f"      lr {lr:<8} : |dw| per step ~ {lr:.5f}"
          f"   over {n} steps  sqrt(N)*lr = {math.sqrt(n)*lr:6.3f}   N*lr = {n*lr:7.2f}")
print("""    The two bounds bracket the walk: decorrelated signs give the first,
    perfectly correlated the second.  Both are linear in lr, which is why
    the RATIO is what is registered and the value is not.
""")

print("""(3) G52 (b) — DOES MARL's OWN DEFAULT CHURN?

The campaign question, and the one that decides whether anything has to be
re-read.  Fit a blob to convergence, then keep streaming exemplars from
the IDENTICAL distribution -- no drift, no noise, nothing new to learn --
and watch the birth rate and the error.

    PREDICTED, NLMS (the default, and every campaign headline)

        RMS(after 200k more) / RMS(at convergence)   <  1.05
        births in the last 50k / births in the first 50k after
            convergence                               <  0.10

        because the step is linear in the residual, so a converged model
        stops moving, so coverage stops opening holes, so births stop.

    PREDICTED, ADAM at the same nominal work

        RMS ratio                                     >  1.20
        late/early birth rate                         >  0.50

        because the step is scale free, so a converged model keeps
        moving at lr regardless.

    The CONTRAST is the assertion, not either number alone.  Two arms on
    one stream, one fixture, one seed set, differing in one enum.""")

print("""(3') THE PRECONDITION FAILED, AND THE QUESTION IS RE-POSED

Recorded because it happened, and written before the replacement ran.

(3) asks what a SETTLED model does.  Run at 300 000 settling exemplars and
four windows of 75 000, MARL's NLMS default was not settled: its RMS fell
0.01989 -> 0.01476 across the measurement, still improving by 26%.  Births
in that window are learning, and the measured late/early ratio of 0.52 is
the decay of legitimate acquisition rather than any floor.  The registered
RMS bound held (0.742 against < 1.05) and the birth bound did not (0.52
against < 0.10), and neither number means what it was written to mean.

That is MARL-19 (d)'s shape exactly -- "there is no wall ... the rested
arm's 1.023x is not a result, it is a test whose precondition failed" --
and the reason is MARL-10: growth on this fixture is K0 + A*H(N), so the
model improves logarithmically and forever.  **There may be no settled
state on this fixture to ask the question of.**

So the question is re-posed to one that needs no settled state, and it is
sharper for it.  Under MARL-10's law the marginal cost decays as A/n, so

    integral of A/n over a DOUBLING of the stream  =  A ln 2

which is a CONSTANT.  An additive churn floor of c births per exemplar
contributes c*n over the same doubling, which DOUBLES each time.  So:

    births per DOUBLING constant  ->  growth is structure, MARL-10's law
                                      holds on a stationary stream, and
                                      there is no additive floor
    births per DOUBLING doubling  ->  an additive floor owing nothing to
                                      the field

    PREDICTED, NLMS   mean ratio of successive doublings' births < 1.40
    PREDICTED, ADAM   mean ratio > 1.60

    Checkpoints at 100k / 200k / 400k / 800k / 1600k, each window one
    doubling of everything seen so far.  This also tests MARL-10's law on
    a STATIONARY stream, where it was fitted on a drifting one.""")

print("""
(4) WHAT A ZERO FLOOR WOULD AND WOULD NOT LICENCE

If NLMS's floor is zero it does NOT follow that every population number in
the campaign is churn-free, and the pre-registration says so now so that
the conclusion cannot quietly widen later:

  - every measured phase ran on a MOVING or NOISY target (MARL-6..10 drift,
    MARL-13 onward noise), and a non-zero residual is exactly the condition
    under which NLMS keeps stepping.  A zero floor on a stationary
    noiseless blob bounds the ARTEFACT, not the growth.
  - MARL-13 (c) already measured the noisy case from the other side: the
    model BIRTHS ON NOISE, 9 923 kernels at one ray a sample against 7 656
    at sixteen.  That is a real churn floor and it is already recorded.
    OBS-5 is asking whether there is a SECOND one underneath it that owes
    nothing to the data.

So the honest scope of a passing (b) is: **under NLMS, a converged model on
a stationary noiseless field does not manufacture capacity.** Everything
about moving or noisy fields stays where MARL-13 and MARL-7 left it.
""")

print("""(5) THE THREE WAYS THIS FAILS, AND WHAT EACH WOULD MEAN

  (i)  NLMS churns too.  Then the mechanism is not the scale-free step and
       the campaign's population numbers all carry a floor.  MARL-7's
       "capacity linear at flat accuracy", MARL-9's marginal cost and
       MARL-10's fitted A would each need a churn subtraction, and the
       observational note's §12 instrument needs a zero.

  (ii) Adam does NOT churn on MARL's fixture.  Then OBS-4's diagnostic is
       about `adaptive_inferred`'s particular loss surface rather than
       about Adam, and the finding narrows to that fixture.

  (iii) The decayed schedule does not reach zero requests.  Then the
       wander is not the whole story and something else -- the birth
       score's own sensitivity to a small residual, most likely --
       contributes.  That would point at OBS3_BIRTH_GAIN rather than at
       the optimiser.

Any of the three is a better outcome than the flat confirmation, which is
why they are written down before the run rather than after it.
""")

print("""(6) RECORDED, NOT BUILT — THE REMEDY, AND THE CONSTRAINT ON IT

A maturity decay is the obvious fix and MARL already stores what it needs:
`Kernel.updates` is incremented per learning event and nothing schedules on
it.  A rate falling as 1/sqrt(updates) would quench a settled kernel while
leaving a young one responsive.

**It must not be built on this evidence alone.**  MARL-6 through MARL-10
established that the model has to keep adapting to a world that moves, and
MARL-6's vindication of freezing was specifically about a parent moving
UNDER a child.  A decay keyed to maturity would freeze exactly the kernels
a drifting world most needs to move, and MARL-7 already measured what
committed capacity costs when it cannot follow.  So:

    TRIGGER   (b) failing for NLMS -- a real churn floor under the
              default -- and then the decay is measured against a DRIFT
              arm (MARL-6's fixture) in the same phase, never alone.

If (b) holds, the action is smaller and belongs to the observational
campaign rather than to the learner: OBS's Adam wants a schedule, and
`OBS3_BIRTH_GAIN` wants to be read against the wander it is now known to
sit on top of.
""")

print("=" * 74)
print("Frozen before the Zig was written.  Thresholds go into")
print("src/thresholds.zig as PROPOSED, for Christian to strike.")
print("=" * 74)
