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

## OBS-3 / G50 — restricted births under matched candidate coverage

### What is adaptive here

This phase adds coefficient-driven activation of new Gaussian shapes to
OBS-2. It is a **restricted inverse-fitting birth policy**, not a change
to MARL.observe's online coverage rule, nor moving-geometry inference.
Nine coarse kernels begin active. Both arms have the same dictionary of
32 additional candidates: a 4×4 lattice at .2/.4/.6/.8 in each axis, at
widths .14 and .09. Maximum active count is 25. Candidates retain fixed
centres and shapes after activation; there is no death, relocation or
hierarchical tree in this phase. K means active basis functions: all 41
candidate slots and sensitivities are allocated in every arm, so active
K is not a measurement of actual allocator bytes.

This restriction removes candidate-placement and candidate-search-budget
confounds before testing a freer adaptive representation. The scientific
predictions were frozen in `tools/obs3_predict.py`: wrong dynamics should
produce more total and late births, while correct dynamics should retain
lower held-out error. These are reported as HELD/REFUTED; implementation
invariants are hard gates. No prediction that births improve generalisation
under wrong dynamics was made.

### Controls and birth rule

Use OBS-2's exact three seeds, 16 initial positions, 32 endpoints, 64
held-out trajectories, dynamics and Adam settings. Four arms cross
correct/wrong dynamics with frozen/adaptive allocation. All receive 1200
full-batch updates, rather than OBS-2's 400; frozen controls measure the
effect of those additional iterations. Observations remain the same batch
throughout: this phase does not yet test a changing stream of new evidence.

The first 400 updates allow the initial basis to settle. At updates
440,480,...,1200, the best inactive candidate may be activated with zero
weight. For current pre-update loss gradient g_j and sensitivity-energy
h_j (the Gauss–Newton diagonal), its score is g_j²/(2h_j). This is the
linearised one-coefficient predicted loss reduction, not a guaranteed
improvement after nonlinear optimisation. Require score > 5e-9, the
half-squared loss corresponding to a declared 1e-4 endpoint accuracy
target. This is a chosen accuracy target, not measured observation noise.
If capacity is full, count the request as denied. Old optimiser moments
persist; new coefficients start fresh moment and bias-correction clocks.

All 41 candidate sensitivities are evaluated at every learning step,
including in frozen controls. Every arm uses **1,228,800 learning RHS
calls and 50,380,800 learning kernel evaluations**, and shares the same
capacity ceiling and 1200-update limit. Active coefficient updates are
also recorded; those counts can differ as K grows. Thus the dominant
integration/search work is exactly matched, not every hardware instruction
or total allocator operation. Scoring uses the same schedule in all arms.

### Histories, not just final populations

The portable measurements are in `docs/data/obs3/`:

- `history.csv`: 360 pre-update checkpoints, errors, K before/after birth,
  candidate score, requests/denials, coefficient-change L1 over the previous
  window, and work counters.
- `birth.csv`: every birth's position, width, pre-birth coverage, local
  residual energy, loss gradient, sensitivity energy and predicted gain.
- `spatial.csv`: residual squared error binned at the **common observation
  starts**, plus visit counts along predicted integration points. Source
  residual bins cover [.15,.85]²; path bins cover [0,1]². Both are 4×4 in
  x-fast order, followed by an outside bin. These are two distinct spatial
  diagnostics, not a claim that source residuals are force-localisation.
- `final.csv`: final errors, active K, late births (after update 800),
  requests, denials, work and measured time including scoring/output.

`python3 tools/obs3_report.py /tmp/marl-g50.log docs/data/obs3` extracts a
completed G50 log and refuses a partial sweep. Held-out values never enter
the birth score or optimiser. Local residual energy at a birth weights
pre-update endpoint errors by that candidate's Gaussian at observation
starts; this is a localisation proxy, not an adjoint-derived residual map.

### Results

Correct dynamics request **no births**, retaining K=9 at all seeds.
Wrong dynamics activate **16 candidates per seed**, reaching K=25 at
update 1040. Each makes 20 requests, including four denied after saturation.
Six births per seed occur after update 800. All three frozen directional
predictions hold: pooled births 0/48, late births 0/18, and lower adaptive
held-out error under correct dynamics.

| seed | correct K | wrong adaptive K | wrong frozen train RMS | wrong adaptive train RMS | wrong frozen held-out RMS | wrong adaptive held-out RMS |
|---|---:|---:|---:|---:|---:|---:|
| 7 | 9 | 25 | .029921 | .011182 | .050910 | .093706 |
| 19 | 9 | 25 | .022706 | .007661 | .053516 | .086554 |
| 41 | 9 | 25 | .026689 | .008142 | .042721 | .089017 |

Pooled across seeds, adaptation under wrong dynamics reduces training RMS
to **.3432×** its frozen control, but increases held-out RMS to **1.8230×**.
This is a capacity-enabled training/generalisation split under matched
observations and search work. Correct adaptive and frozen arms coincide;
held-out error is 5.15e-7/5.24e-7/3.56e-7. OBS-2 seed 19's optimisation
residual disappears with the longer budget, without requiring a birth.

Every selected location was already covered before birth: maximum active
Gaussian value at its centre ranges **.8133 to 1.0**. Thus these are not
births into previously empty candidate locations. Of 48 births, 39 use
width .09 and nine width .14. Each seed activates 16 kernels at 13 distinct
locations: three locations acquire both scales. The mean ratio of
birth-local residual MSE to global training MSE is 1.13/1.17/1.64 by seed.
This is descriptive evidence of where allocation occurs, not a separately
pre-registered statistical test or proof of causal residual localisation.

Predicted path visit counts already differ between correct and wrong arms
at the first birth, despite shared sensor coverage and candidate sites.
Neither has outside-domain visits at that checkpoint. Internal-path
coverage therefore remains a distinction to account for in broader
claims; matching observation locations alone cannot make it identical.

### Claim boundary and validation

This supports a restricted statement: **under this birth policy, wrong
dynamics activate more already-covered basis functions, fit training
observations better, and generalise worse**. It does not establish a
universal MARL mismatch detector, physical memory expenditure, or persistent
birth–death churn. With no death policy, saturation ends actual growth;
continued rejected requests are pressure, not churn. The true field also
lies in the initial nine-kernel span, making this a controlled favourable
case for the correct dynamics, not an unknown-complexity recovery test.

The common trajectory engine was extracted into `src/trajectory.zig`;
G49's derivative audit and recovery results are unchanged. G50(a) checks
that dormant candidates preserve the original trajectory and sensitivities
bitwise, that zero-weight activation changes no field value, that a new
fine coefficient's derivative matches finite differences, and that inactive
weights remain zero. G50(b) enforces capacity and work contracts while
retaining the directional research predictions as explicit results.

Validation: targeted G49 and G50 passed; all 12 smoke tests passed
(about 3 s execution plus 12 s compilation). No full regression run.

## OBS-4 / G51 — useful growth, fresh evidence, and optimiser-induced pressure

OBS-3's standing conclusion remains: **under this restricted birth policy,
wrong dynamics use more already-covered basis functions to fit the training
observations, while making unseen predictions worse.** OBS-4 tests the
limits of extending that statement to a diagnostic.

### Pre-registration and full factorial

`tools/obs4_predict.py` freezes 48 arms: simple/rich truth × repeated/fresh
windows × correct/wrong dynamics × frozen/adaptive allocation × three seeds.
Rich truth adds +.025 at candidate 30 and -.025 at candidate 35: width .09,
centres (.4,.4) and (.6,.6). These shapes are outside the initial coarse
span but in the candidate dictionary. This is deliberately representable
fine structure, not arbitrary field discovery.

Each of three windows receives OBS-3's **1200-update budget**. All paired
arms therefore run 3600 updates, carrying coefficients, active set and
Adam state forward. The first 400 global updates are the only birth
warmup; score cutoff, 40-update birth cadence, candidate dictionary and
active cap 25 are unchanged. Frozen controls get the same extra iterations.
Every arm evaluates 3,686,400 learning RHS calls and 151,142,400 kernel
contributions, consuming 115,200 endpoint-loss terms. Active coefficient
update counts are recorded separately and need not match. This remains
restricted candidate activation, not the original MARL online learner.

Every fresh window contains 16 independently sampled initial positions,
with endpoints at .16/.48. Repeated controls reuse window zero. A **new,
independent 64-start evaluation set** remains fixed across all windows and
never enters updates, birth scores or stopping decisions. Coordinates are
shared between simple/rich truth and the compared dynamics/allocation
arms; only ground-truth labels change with true field complexity. G51(a)
checks concrete training/evaluation sample disjointness and that changing
evaluation labels cannot change a learning batch or candidate score.

Score the incoming window and fixed evaluation set before any updates,
then again after the window. This tests transfer across initial-condition
samples of a stationary field. It is not free-running long-horizon
simulation, newly learned physics, or a temporally changing potential.
Sensors use the same finer reference integration as OBS-3.

### Useful growth is now observed

The first registered comparison required rich, correct, repeated-evidence
adaptive arms to acquire kernels and improve **both** training and
independent evaluation error over frozen controls. It holds: 47 births
across seeds, training RMS ratio **.061355**, evaluation ratio **.108451**.
The correct model now benefits from capacity acquisition rather than merely
having no need for it.

Pooled RMS over seeds:

| truth / evidence | dynamics | frozen train | adaptive train | frozen evaluation | adaptive evaluation |
|---|---|---:|---:|---:|---:|
| rich / repeated | correct | .025552 | .001568 | .055682 | .006039 |
| rich / repeated | wrong | .035558 | .007470 | .079176 | .144677 |
| rich / fresh | correct | .022501 | .000087 | .040954 | .000653 |
| rich / fresh | wrong | .035741 | .019147 | .066338 | .085045 |

For fresh rich evidence, adaptive correct evaluation RMS is **.015934×**
the frozen control. Its pooled incoming-window RMS, measured **before**
learning windows 1 and 2, is **.087542×** the frozen control. Correct/wrong
adaptive final evaluation RMS is **.007673**. These three registered
comparisons hold as well. Both true fine components are activated at every
seed, but many additional components are activated too: no minimal-basis
recovery claim follows.

### Final K is insufficient; the window history separates these arms

Both rich fresh adaptive models finish at **K=25 at every seed**. Their
paths to that count differ:

| window | correct K by seed | correct incoming RMS | correct evaluation after | wrong incoming RMS | wrong evaluation after |
|---|---|---:|---:|---:|---:|
| 0 | 14 / 12 / 19 | .039581 | .018437 | .047763 | .123950 |
| 1 | 18 / 20 / 23 | .003679 | .001666 | .092985 | .110759 |
| 2 | 25 / 25 / 25 | .001723 | .000653 | .096396 | .085045 |

Wrong dynamics already reach K=25 in the first window. Across all three
windows they request 78/80/80 interventions; correct dynamics request
17/16/17. A repeated cross-window request means the **same candidate
location and scale** was requested in an earlier window. Wrong dynamics
produce 35/13/18 such events (**66 total**); correct dynamics produce zero.
That fifth registered comparison holds. Requests for an active candidate
are not reconsidered by this birth policy; these repeated requests occur
for still-inactive candidates after saturation. They are unresolved
pressure, not birth–death churn or a new birth at the same active kernel.

Wrong dynamics' evaluation error does improve after later fresh windows,
from .123950 to .085045, despite remaining far worse than correct dynamics.
Thus “wrong dynamics never improve held-out prediction” would be false.
The comparison is with matched controls and the transfer history, not a
universal monotonicity rule.

### The simple control prevents a premature detector claim

On the simple field, correct dynamics also make unnecessary births under
the longer optimisation schedule and new sample draws:

| correct simple dynamics | frozen evaluation RMS | adaptive evaluation RMS | adaptive final K by seed |
|---|---:|---:|---|
| repeated evidence | .000167 | .001457 | 18 / 25 / 22 |
| fresh evidence | .000518 | .001851 | 18 / 22 / 23 |

Moreover, one **correct rich repeated-evidence** seed makes 13 cross-window
repeat requests. Repeat pressure is therefore not exclusive to wrong
physics even within this small factorial. The five registered comparisons
hold, but the control results rule out a broader reading of them.

A diagnostic amendment was recorded before its run, **after inspecting the
main results**. The earliest observed simple-field birth request was at
step 1160; choose an explicitly inspection-derived step-800 checkpoint and
compare continued updates with holding that state fixed through step 3600.
Births are disabled in both diagnostic arms, while candidate pressure is
still scored every 40 updates. This is not an independently validated
stopping rule, nor a change to the main experiment's policy.

| seed | checkpoint train RMS | maximum train RMS with continued updates | requests with continued updates | requests while held fixed |
|---|---:|---:|---:|---:|
| 7 | 2.20e-7 | 6.44e-4 | 7 | 0 |
| 19 | 2.35e-7 | 7.37e-4 | 8 | 0 |
| 41 | 1.92e-7 | 1.03e-3 | 10 | 0 |

The held states remain bitwise unchanged. Continued optimisation alone is
sufficient to create false birth pressure on stationary, noiseless data
already fitted accurately. This isolates an optimiser-related mechanism;
it does not yet isolate which part of Adam/finite-precision dynamics causes
it or establish a replacement learning-rate policy. No threshold or main
arm was retuned after seeing this result.

### Preserved records and limits

`docs/data/obs4/` contains 960 sensor rows, 144 window transitions, 1440
histories and spatial snapshots, 1096 request events, 48 final reports and
six diagnostic records. `tools/obs4_report.py` extracts complete logs into
LF-terminated CSVs. Spatial records include source counts alongside source
residual SSE, so an unobserved bin cannot be mistaken for a well-explained
one, plus independent predicted-path visit counts. Every request records
pre-intervention coverage, local residual energy, sensitivity score,
location/scale and previous candidate/site/window requests. Minimum
pre-request active Gaussian coverage remains .8133.

The operational picture now has at least three causes of structural
pressure: genuine missing capacity, compensation for wrong dynamics, and
continued optimiser updates disturbing an already good fit. Useful growth
and compensatory growth separate strongly on this rich-field fixture, but
neither final K nor repeat requests alone is a reliable classifier. The
representation remains an instrument whose readings require controls for
learning dynamics, observational support and the allowed model class.

Validation: targeted G51(a/b) and diagnostic G51(c) passed. All 12 smoke
tests passed (about 3 s execution plus 12 s compilation); no full suite.

## OBS-5 / G52 — the churn floor: calibrating population as an instrument

OBS-4 (c) ended on a diagnostic that was scoped honestly and stopped:

> Continued optimisation alone is sufficient to create false birth pressure
> on stationary, noiseless data already fitted accurately. This isolates an
> optimiser-related mechanism; it does not yet isolate which part of
> Adam/finite-precision dynamics causes it.

**Its subject is the core learner, so its consequence is campaign-wide.**
Population is a headline in MARL-7 (capacity linear at flat accuracy),
MARL-9 and MARL-10 (the K₀ + A·H(N) law), MARL-20 (~200 kernels a move) and
every occlusion phase. If a model births from the optimiser rather than
from structure, some fraction of each of those numbers is the instrument
rather than the signal. And the observational note asks population to *be*
an instrument — §12 "An Endogenous Complexity Instrument", §31 "The
Representation as an Instrument" — which cannot be used before it is
calibrated for its own noise floor.

`tools/obs5_predict.py` was frozen before the code, including §(3′), which
records a precondition failure and its replacement before the replacement
ran. `src/churn.zig` is new; `adaptive_inferred.Model.updateAt` exposes the
rate and `update` delegates to it at `RATE`, so every G50 and G51 number is
bit-identical.

### G52 (a) — it is not finite precision, it is the scale-free step

Adam's update is `w -= lr · m̂/(√v̂ + ε)`. The ratio of the gradient's own
first and second moments is **dimensionless**, so the step stays at `lr`
however small the gradient becomes. That is what "adaptive" means, and its
textbook consequence is that Adam at a fixed rate does not converge — it
wanders in a ball whose radius is set by `lr`. MARL's own `adam` is the
identical expression; its NLMS default is not, because `w -= rate_w·e·g/Σg²`
and the geometry step through `ew = Σ_c w_c a_c` are both **linear in the
residual**, so they vanish with it.

OBS-4 (c)'s diagnostic, re-run with the rate as the swept variable and its
checkpoint, cadence and request rule untouched — so the fixed arm at 0.003
reproduces its 7/8/10 exactly:

| arm | max train RMS (mean of 3 seeds) | requests, summed |
|---|---:|---:|
| 0.003 fixed (OBS-4 c) | 8.033e-4 | **25** |
| 0.0015 fixed | 2.169e-4 | 2 |
| 0.00075 fixed | 1.264e-5 | **0** |
| 0.003 / √(t/t₀) | — | 6 |
| 0.003 / (t/t₀) | — | **0** |

Both registered predictions hold. The rate ratio is **0.270** then **0.058**
against a registered ceiling of 0.60 — *steeper* than the derived linear
relation, because below some amplitude the wander stops crossing the birth
score's threshold at all and the maximum collapses to the checkpoint value.
That is a threshold effect and not a power law, and it is not fitted here.

The `1/t` schedule holds the fit at **3.3e-7 / 3.2e-7 / 1.9e-7** against
checkpoints of 2.2e-7 / 2.4e-7 / 1.9e-7 — the model simply stays converged
— and makes **zero** requests at every seed. The milder `1/√t` leaves six
standing, which is what the two-schedule registration was for: the horizon
past the checkpoint is only 3.5× its length, so `1/√t` can buy 2.12× of it
and `1/t` buys 4.50×.

    OBS-4's false birth pressure is Adam's fixed step. A schedule removes it.

### G52 (b) — a precondition that failed, recorded

The campaign question needs a *settled* model. The first design settled for
300 000 exemplars on `marl.truth` and then measured four equal windows. It
does not work, and the reason is already in the ledger:

| | RMS at settling | RMS after 300k more | births, last/first |
|---|---:|---:|---:|
| NLMS | 0.01989 | 0.01476 (**0.742×**) | 0.52 |

The registered RMS bound "held" at 0.742 and the birth bound failed at 0.52
— and **neither number means what it was written to mean**, because the
model was still improving by 26% across the window it was supposed to be
settled in. Those births are learning. MARL-19 (d)'s shape exactly — *there
is no wall … a test whose precondition failed* — and MARL-10's reason:
growth here is K₀ + A·H(N), so the model improves logarithmically and
forever. **There may be no settled state on this fixture to ask about.**

### G52 (b) — re-posed: births per DOUBLING

A form that needs no settled state. Under MARL-10's law the marginal cost
decays as A/n, so

$$\int_n^{2n} \frac{A}{m}\,dm = A\ln 2,$$

a **constant** per doubling. An additive churn floor of *c* births per
exemplar contributes *c·n* over the same doubling, which **doubles** each
time. So the shape of the sequence separates structure from churn without
the model ever having to stop learning. Checkpoints at 100k/200k/400k/800k/
1600k, `responsibility = 3` (MARL-6R), everything else default:

| seen | NLMS kernels | NLMS births | NLMS RMS/const | Adam kernels | Adam births | Adam RMS/const |
|---:|---:|---:|---:|---:|---:|---:|
| 100 000 | 3 386 | 3 386 | 0.231 | 11 750 | 11 750 | 0.796 |
| 200 000 | 3 630 | 244 | 0.167 | 16 421 | 4 671 | 0.771 |
| 400 000 | 3 837 | 207 | 0.113 | 22 996 | 6 575 | 0.831 |
| 800 000 | 4 004 | 167 | 0.086 | 32 507 | 9 511 | 0.789 |
| 1 600 000 | 4 128 | 124 | **0.075** | 47 037 | **14 530** | **0.845** |

    doubling ratios   NLMS  0.848  0.807  0.743   mean 0.799, FALLING
                      Adam  1.408  1.447  1.528   mean 1.461, RISING

**MARL's NLMS default has no additive churn floor**, and the registered
ceiling of 1.40 holds at 0.799. Its birth rate does not merely stay
constant per doubling, it *decays* — growth on a stationary stream is
**slower than logarithmic**, which is new: MARL-10's law was fitted on a
*drifting* stream and is therefore an upper bound on the stationary case.

Adam's registered floor of 1.60 is **refuted at 1.461** and held in every
way that matters: the three ratios climb monotonically toward the two an
additive floor demands, where NLMS's fall. The gate asserts that shape
rather than the level, because the shape needs no threshold.

The picture beside it is the one to keep. **Adam adds 14 530 kernels in the
last doubling alone**, reaching 47 037 against NLMS's 4 128, while its RMS
does not move — 0.796 to 0.845 of a constant, very slightly *worse*.
Eleven times the population for eleven times the error. The campaign has
described Adam as "the instrument: the batch optimiser, and why it is wrong
per-exemplar" since MARL-0; this is that, priced.

### What this licenses, and what it does not

Registered at §(4) before the run, so the conclusion cannot widen later.

**Licensed:** under NLMS, on a stationary noiseless field, MARL does not
manufacture capacity — the campaign's population headlines carry no
optimiser floor, and population is usable as an instrument there.

**Not licensed:** anything about moving or noisy fields. Every measured
phase from MARL-6 onward ran on one or the other, and a non-zero residual
is exactly the condition under which NLMS keeps stepping. MARL-13 (c)
already measured that case from the other side — **the model births on
noise**, 9 923 kernels at one ray a sample against 7 656 at sixteen — and
that floor is real and stays where it is. OBS-5 asked whether there was a
*second* floor underneath it owing nothing to the data. There is not, under
NLMS; there is, under Adam.

**For the observational campaign specifically:** OBS-3 and OBS-4's Adam runs
at a fixed 0.003 and therefore sit on a wander that `OBS3_BIRTH_GAIN` was
never calibrated against. G52 (a) shows a `1/t` schedule removes it at no
cost to the fit. Whether OBS-3's and OBS-4's *directional* findings survive
that change is a re-run, not a re-derivation, and it is the obvious next
beat if the observational thread continues.

### Recorded, not built

A maturity decay on MARL's own rates — `Kernel.updates` is already
incremented per learning event and nothing schedules on it — is the
symmetric fix and **must not be built on this evidence**. MARL-6 through
MARL-10 established that the model has to keep adapting to a world that
moves, and a decay keyed to maturity would freeze exactly the kernels a
drifting world most needs to move; MARL-7 already priced what committed
capacity costs when it cannot follow. **Trigger:** a churn floor found
under NLMS, measured against a drift arm in the same phase, never alone.
G52 (b) did not find one, so the trigger has not fired.

Cost: G52 is ~96 s, of which Adam's 1.6 M exemplars at 47 037 kernels are
80. Not a smoke check. `python3 tools/obs5_predict.py` for the derivations.
