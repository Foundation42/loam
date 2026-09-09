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
