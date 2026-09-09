# MARL observational campaign

Working lab book, 2026-09-09. Gates continue the shared G-series.

## OBS-1 / G48 — state evidence through a known flow

The observational-dynamics design note proposes state inference before
parameter or law inference. ALG-2 already supplies the relevant read:

    predicted(x,t) = M_theta(Phi_-t(x))

When the flow is fixed and independent of theta, its preimage p is fixed
with respect to model parameters. Consequently the parameter derivative
is precisely the existing MARL derivative evaluated at p. The first
implementation is `observed.assimilate`: backtrace the sensor position,
then pass its measured scalar to MARL.observe at that source position.
This retains existing responsibility, geometry learning and birth rules;
it does not differentiate through those discrete decisions. The caller
must own the source model for mutation. Earlier views of that model are
invalidated, so this is an assimilation window, not mutable publication.

### Pre-registration and controls

`tools/obs1_predict.py` and `OBS1_GAIN_MARGIN` were written before the
code and measurements. Both directional predictions use margin 1:
corrected held-out future SSE must beat the unchanged prior and the
wrong-coordinate mutation, pooled over seeds 7/19/41.

- True state: the standing scalar Gaussian blob, known rigid rotation.
- Prior: 60k-example MARL fit to a blob displaced +0.04 in x.
- Evidence: 30k noiseless scalar observations, random steps 1..40.
  Source positions are drawn in the true initial four-sigma ball clipped
  to the unit cube; analytic rotation gives sensor positions independently
  of the RK4 inverse. This is an explicitly informative sensor placement,
  not blind support discovery. Current positions can leave the cube;
  source coordinates remain in the model's initial domain.
- Four arms start from identical numerical copies: unchanged prior,
  preimage updates, current-coordinate updates, and an oracle given the
  exact original sample position. Only the oracle receives that position;
  the real assimilation function sees position, time and measured value.
- Held-out local probes: 2048 independent source positions in a three-sigma
  ball, transported to steps 10/40/60. A further 4096 source-cube probes
  measure global error at step 60. At this half-turn the source cube maps
  to the world cube. All arms use the same held-out probes.
- The inverse uses four RK4 substeps per nominal step. Dynamics are given,
  and truth values are supplied only by the synthetic sensor and scorer.

The time-60 measurement is outside the training time window. However,
rotation and transported probes make it the same spatial state question
at another phase: equal local RMS at steps 10/40/60 is expected. This is
not independent evidence of long-horizon stability or learned dynamics.

### Results

Local RMS at held-out step 60:

| seed | prior | corrected | wrong coordinates | source oracle | prior → corrected kernels |
|---|---:|---:|---:|---:|---:|
| 7 | 0.074576 | 0.010217 | 0.157655 | 0.010217 | 125 → 130 |
| 19 | 0.079595 | 0.009180 | 0.216633 | 0.008880 | 111 → 115 |
| 41 | 0.080365 | 0.010028 | 0.222373 | 0.010028 | 103 → 105 |

Pooled corrected/prior RMS is **0.12553**, corrected/wrong **0.04884**,
and corrected/source-oracle **1.00950**. Both directional predictions
hold. The coordinate mutation acquires 892/898/891 kernels while trying
to absorb incompatible phases into one static field. More capacity does
not repair incorrect attribution.

Corrected global RMS is 0.002848/0.002204/0.002750, versus the prior's
0.019756/0.017768/0.020396. All three updating arms together take
0.828/0.810/0.791 seconds per seed in this ReleaseSafe run, excluding
initial fitting and diagnostic scoring. Each consumes exactly 30k
observations. The small oracle gap at seed 19 illustrates that very small
coordinate differences can alter an adaptive learner's subsequent path;
we did not pre-register an equality threshold for that comparison.

G48(b) independently finite-differences the weight derivative through a
delayed read, then compares the assimilation event and resulting kernel
parameters bitwise against manual preimage observe. Omitting the inverse
map gives an exactly zero derivative at the chosen quarter-turn query.
Both targeted G48 gates passed in ReleaseSafe. The normal smoke check
also passed 12/12 tests (about 3 s execution plus 12 s compilation); no
full regression run was needed.

### What this establishes, and next

The forward pullback now has an evidence path back into the source MARL.
No generic autodiff engine or eager re-projection is needed for this
fixed-flow scalar case. This is a useful baseline, not yet inverse
potential reconstruction: the latter requires differentiating observed
trajectories through a state-dependent field, including spatial Hessians
and temporal sensitivities. A potential's additive constant also cannot
be identified from gradient-driven motion alone.

Next observational beat: short-window trajectory observations with a
fixed kernel basis, learn coefficients of a hidden potential, pin the
trajectory sensitivity against finite differences, and measure both
held-out motion and gradient error. Keep geometry and allocation fixed
first to separate derivative correctness and observational ambiguity
from adaptive capacity acquisition. General sparse coverage, noise and
confidence remain separate experiments. ALG-3 long-horizon transport
also remains open; OBS-1 does not answer it.

## OBS-2 / G49 — endpoints identify coefficients of a hidden potential

### Scope and pre-registration

`tools/obs2_predict.py` was frozen before implementation and measurement.
`src/inferred.zig` uses nine frozen Gaussian shapes in the MARL parameter
format, on a 3×3 lattice with sigma .22. It learns only their coefficients.
There is no MARL.observe, geometry descent, birth or refinement in this
phase. That isolates the trajectory derivative from allocation decisions.
The synthetic true potential is deliberately in this span: alternating
sign coefficients, random magnitudes .015–.045 at seeds 7/19/41. No
constant offset is fitted; gradient-driven motion cannot identify one.

The dynamics are first-order **velocity = -gradient(potential)**, not
Newtonian acceleration. The second arm adds prescribed angular velocity
.3 around the domain centre. That velocity has nonzero circulation; no
scalar potential can cancel it everywhere. This does not guarantee that
finite endpoint observations distinguish every possible alternative
field, so the held-out measurement remains necessary.

Both arms see the same 16 initial positions in [.15,.85]² and two
observed endpoints per trajectory, at times .16/.48. They start with zero
coefficients and use 400 full-batch Adam updates, rate .003, beta .9/.999,
epsilon 1e-8. Only endpoint positions enter the learning objective. No
velocity, gradient or potential values are supplied as training targets.
The scorer has 64 independent held-out initial positions and a 25×25 grid
for potential-gradient error. This is noiseless, known-initial-state,
known-basis identification; recovery outside this observed square is not
established. The nine kernels are a frozen basis, not a claim that online
MARL would discover these exact shapes.

Prediction uses explicit midpoint at dt=.02; synthetic sensors use
four-times-finer midpoint steps. Thus fitting is not merely inverting the
identical numerical step. The headline is f32 throughout. The f64 audit
below uses the same templated dynamics and sensitivity implementation;
an independent f32 pin compares its Gaussian gradients to field.gaussianJet.

### The derivative witness, including its refutation

For coefficient j, S_j = dx/dw_j obeys

    dS_j/dt = (-Hessian(P) + omega R) S_j - gradient(phi_j).

Both midpoint stages carry this sensitivity. Omitting position feedback
is an executable mutation, not just a sign reversal of the final gradient.

The audit covers all nine coefficients, three seeds, three initial
positions with different influences, four lengths (1/8/32/64 steps), and
three centred positive/negative perturbations (1e-3/1e-4/1e-5): 972
comparisons. Its frozen bound is abs error <= 1e-9 + 1e-3 * max magnitude.

**Refuted:** the original prediction that every raw finite difference
would pass at every perturbation size. Four cases fail at 1e-3; none fail
at 1e-4 or 1e-5. The worst raw relative error above the absolute-floor
regime is .04247. A weak derivative is particularly vulnerable to the
finite-difference truncation term; small absolute disagreement is not an
excuse to silently relax its relative requirement.

Before rerunning, the preregistration records an amendment: also compute
D(h/2) and (4D(h/2)-D(h))/3, cancelling the leading O(h²) central-difference
error, and require the **same unchanged tolerances** at all h. All 972
extrapolated comparisons pass. Worst absolute error is 8.23e-9 and worst
relative error 2.65e-6; derivative magnitudes span 3.14e-8 to .8264. The
omitted-position mutation fails 936 raw comparisons. The raw failures
remain printed by the gate and recorded here; they are not rewritten as
an originally successful prediction.

### Recovery at matched capacity and work

| seed | initial held-out endpoint RMS | correct dynamics | wrong dynamics | correct gradient RMS | wrong gradient RMS |
|---|---:|---:|---:|---:|---:|
| 7 | .034836 | .000001 | .050910 | .000001 | .075495 |
| 19 | .040768 | .000203 | .052652 | .000472 | .068025 |
| 41 | .029052 | .000000* | .042721 | .000000* | .032332 |

*Rounded to six decimals, not exact zero. Initial column is the zero
potential under correct dynamics. Each arm also prints its own initial
training and held-out error, since the wrong arm's prescribed drift is
already present before fitting.*

Pooled correct/prior held-out RMS is **.003332**, correct/wrong **.002397**,
and correct/prior potential-gradient RMS **.003826**. All three frozen
directional recovery predictions hold. Correct training endpoint RMS is
.000000/.000067/.000000; wrong training RMS .029921/.022713/.026689.
Correct coefficient RMS is .000000/.000380/.000000, versus wrong
.029267/.039052/.015461. Seed 19's finite optimisation residual is retained;
there is no convergence-based extension of its training budget.

Per arm and seed: **K=9, births=0, 400 updates, 12,800 observation-loss
terms, 409,600 RHS calls, 3,686,400 kernel evaluations** in learning.
Measured learning time is about .025 s per arm in ReleaseSafe on this
machine, excluding fixture creation, scoring and compilation. The counters
measure identical algorithmic work; they do not assert identical hardware
instruction counts. Every RHS computes the same coefficient sensitivities.

This establishes an endpoint → trajectory → potential-coefficient learning
path and a fixed-budget wrong-dynamics failure. It does **not** establish
kernel proliferation as a mismatch detector: population cannot change in
this experiment. The adaptive phase must still measure pre-update residuals,
coverage, births by location/scale and actual work under matched budgets.
Matched sensor positions alone also do not imply matched internal paths;
those paths will need to be recorded when interpreting births.

The wrong arm does learn: training RMS decreases at all seeds. Its own
initial → final held-out RMS is .049013→.050910, .059131→.052652 and
.043459→.042721. Thus mismatch does not imply every loss must rise;
imperfect explanations can partially improve observations. G49(a), with
its recorded Richardson amendment, and G49(b) pass targeted ReleaseSafe.

Commit validation: the standard smoke check passed 12/12 tests, about
3 s execution plus 12 s compilation. No full regression run.
