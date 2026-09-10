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

## OBS-6 / G53 — the birth signal, recalibrated

OBS-5 established that OBS-4's false birth pressure is Adam's scale-free
step, and that a `1/t` schedule removes it at no cost to the fit. OBS-3 and
OBS-4 ran at a **fixed** 0.003, so `OBS3_BIRTH_GAIN` — which decides what
counts as a birth request in both — was calibrated against a signal sitting
on a wander nobody had measured. OBS-4 said as much without knowing the
cause:

> Repeat pressure is therefore not exclusive to wrong physics even within
> this small factorial. The five registered comparisons hold, but the
> control results rule out a broader reading of them.

G53 runs OBS-4's 48-cell factorial unchanged in every other respect, twice,
and asks what survives. `tools/obs6_predict.py` was frozen first. G51 (b)
reproduces bit-identically under `Sched.none`, so nothing was disturbed.

### The schedule is read off the harness, not chosen

$$lr_t = lr_0 \cdot \min(1, t_0/t), \qquad t_0 = 400$$

Births are gated on `step > 400` in OBS-4's own `run`, so 400 is the moment
the birth signal starts being *read*: decaying earlier slows learning over
readings nobody uses, decaying later leaves the wander inside the window
that matters. `1/t` and not `1/√t` because G52 (a) measured both here — the
milder schedule left six requests standing where `1/t` left zero. Total RHS
calls and coefficient updates are unchanged, so OBS-4's equal-budget
contract holds with no new assertion.

### The null, and why the obvious version of it is useless

A decayed rate could improve every birth number for the stupidest possible
reason — by learning less. Registered first, and it took two attempts to
measure anything:

| frozen-allocation train RMS | fixed 0.003 | 1/t | ratio |
|---|---:|---:|---:|
| pooled over the factorial | 2.4e-2 | 2.4e-2 | 1.0000 |
| correct dynamics only | 1.702e-2 | 1.702e-2 | 0.9999 |
| **simple field, correct, frozen — repeated** | **1.669e-4** | **4.609e-7** | **0.0028** |
| **simple field, correct, frozen — fresh** | **5.177e-4** | **4.380e-7** | **0.0008** |

The first two pass and say almost nothing: they are dominated by cells where
the fit is limited by the **model class** — the rich field's two components
outside the nine-kernel span, and the wrong dynamics — and no learning rate
can move those. Sharpening from "all frozen arms" to "frozen arms under
correct dynamics" swapped one source of mis-specification for another.

The cell where the *rate* is the binding constraint is the simple field
under correct dynamics with allocation frozen — a target the model class
contains exactly. **There the null does not merely pass, it inverts: the
schedule is better by 360× and 1180×.** Fixed-rate Adam was hovering,
exactly as G52 (a) measured directly, and the schedule lets it converge.

### All five OBS-4 comparisons hold, and hold harder

| | births | repeated train | repeated eval | fresh eval | incoming | correct/wrong | repeats correct/wrong |
|---|---:|---:|---:|---:|---:|---:|---|
| fixed 0.003 | 47 | .061355 | .108451 | .015934 | .087542 | .007673 | 13 / 354 |
| **1/t** | **16** | **.003700** | **.021985** | **.004521** | .161477 | **.002229** | **0 / 362** |

Every one still HELD, and four of the five ratios improve by factors of 3.5
to 16.6 — **on a third of the births**. Two thirds of what OBS-4 counted as
useful growth on the rich field was the optimiser's wander, and removing it
made every accuracy comparison better.

The one that moved the wrong way is `incoming` (.0875 → .1615, still well
under one). The adaptive arm's advantage on incoming-window SSE shrank,
which is what less transferred capacity should do, and it is reported
rather than explained.

### The control clears completely, and that is the finding

OBS-4's control is what stopped its result becoming a detector: on the
**simple** field, where correct dynamics need no extra capacity at all,
adaptive allocation made the model *worse*.

| simple, correct dynamics | frozen eval | adaptive eval | ratio |
|---|---:|---:|---:|
| repeated, fixed 0.003 | 1.669e-4 | 1.457e-3 | 8.73 |
| repeated, **1/t** | 4.609e-7 | 4.609e-7 | **1.000** |
| fresh, fixed 0.003 | 5.177e-4 | 1.851e-3 | 3.58 |
| fresh, **1/t** | 4.380e-7 | 4.380e-7 | **1.000** |

A ratio of exactly one because the two arms are **the same run**: births in
the control cells go **74 → 0**. With nothing to buy, the scheduled model
buys nothing. And across the whole factorial, cross-window repeat requests
go **correct 13 → 0** while **wrong 354 → 362** — untouched.

    OBS-4's caution was about the instrument, not about the claim.

On this fixture, with the optimiser's wander removed, repeat pressure
separates wrong dynamics from correct perfectly: 0 against 362.

### What is still not claimed

The schedule is not proposed as a default for anything. MARL's own learner
does not use Adam by default and G52 (b) showed its NLMS default has no
floor to fix. This is a correction to two observational phases' instrument,
on one fixture, with a model class that contains the truth on the simple
field and demonstrably does not on the rich one. Whether a mismatch
detector built on repeat pressure generalises past that is untested and
stays untested here — OBS-3's original claim boundary (no death policy, so
continued rejected requests are pressure and not churn; the true field
inside the initial span) is unchanged by any of this.

What *has* changed is that OBS-3's and OBS-4's headline can now be stated
without the hedge the control forced on it, for this fixture:

> Under this birth policy and a converging schedule, wrong dynamics
> activate more already-covered basis functions, fit training observations
> better, and generalise worse — and correct dynamics do not.

Cost: G53 is ~120 s, two full factorials. Not a smoke check.
`python3 tools/obs6_predict.py` for the derivations.

## OBS-7 / G54 — operator inference, and what actually governs it

The note's §29 level 3, by way of §27. OBS-1 did level 1 (state), OBS-2
level 2 (parameters of a hidden potential), and OBS-6 made the structural
pressure signal readable. §29 asks each level to be demonstrated
independently before the next.

**The rig already contained a hidden operator.** `trajectory.zig`'s law is

$$\dot x = \omega R(x-c) - \sum_i w_i \nabla\phi_i(x)$$

and OBS-3 through OBS-6 used $\omega$ as a *known, given* knob — correct 0,
wrong 0.3. Level 3 is the same rig with it taken away: the truth has it, the
learner is not told, and must find it in a library. `src/law.zig` is a
separate engine because four gates rest on `trajectory.zig` reproducing bit
for bit; the sensitivity ODE $\dot s_j = \partial f/\partial\theta_j + Js_j$
is the same shape in both.

### The library, and the prediction that came with it

Five affine candidates, $d = x - c$. Only the first is in the truth.

| k | $V_k(x)$ | a gradient? |
|---|---|---|
| rotation | $(-d_y, d_x)$ | **no** — divergence-free, curl 2 |
| divergence | $(d_x, d_y)$ | yes — $\nabla(\lvert d\rvert^2/2)$ |
| shear | $(d_y, d_x)$ | yes — $\nabla(d_x d_y)$ |
| drift x | $(1,0)$ | yes — $\nabla x$ |
| drift y | $(0,1)$ | yes — $\nabla y$ |

`tools/obs7_predict.py`, frozen first, argued from Helmholtz that §27's
success criterion could only half hold: the learner is *already* fitting a
pure gradient field, so any candidate that is itself a gradient competes for
the same explanation, and four of the five are.

### G54 (a) — the sensitivities

G49's discipline carried to the library's parameters: worst relative error
against a Richardson finite difference is **4.42e-8** over all fourteen. The
mutation drops the $J\cdot s$ coupling — the term that says moving a
coefficient moves the *path* — and it is off by **100% at 8 steps and 178%
at 64**, same sign and same order, getting worse with the horizon. Exactly
the kind of wrong a loss curve hides.

### G54 (b) — §27's criterion holds in full, and my prediction was refuted

| operator | seed 7 | seed 19 | seed 41 | RMS velocity contributed |
|---|---:|---:|---:|---|
| **rotation** | **0.08574** | **0.08573** | **0.08572** | truth: 0.08573 |
| divergence | −0.00704 | −0.00042 | −0.00094 | |
| shear | 0.00026 | −0.00003 | −0.00014 | |
| drift x | −0.00015 | 0.00001 | −0.00004 | |
| drift y | 0.00005 | 0.00000 | 0.00001 | |

- **Recovery: 0.0%.** The hidden rotation comes back exact at every seed.
- **The null: 0.000004** against a bar of 0.008573 — with no rotation in the
  truth, the library does not invent one, by a factor of 2000.
- **Prediction: 0.0028.** Held-out endpoint RMS with the library is 360×
  better than the same fit with the law left incomplete.
- **The irrelevant coefficients do approach zero.** The largest is 8.2% of
  the rotation's contribution and three of the four are under 0.3%.

So §27's criterion holds in full and the Helmholtz prediction is
**refuted** — and so was the statistic written to test it. `OBS7_IDENTIFIABLE`
asked for the curl-free candidates' across-seed coefficient of variation to
exceed the rotation's by 5×; it "passed" at **15 408**, for a reason that has
nothing to do with degeneracy. **A CV on a near-zero quantity is always
about one**, so it cannot tell *arbitrary* from *correctly zero*. Both the
threshold and the prediction are left standing and marked, and G54 (b) now
rests on the magnitude statement it should have made first.

### G54 (c) — what actually governs it, measured with no learner

MARL-23's move, one campaign over: separate what the **basis** can do from
what the **learner** finds. Least squares over the sampled square, no
optimiser, no observations, no trajectories —

$$\min_w \left\lVert V_k - \sum_i w_i(-\nabla\phi_i)\right\rVert$$

as a fraction of $\lVert V_k\rVert$. One means the basis cannot imitate the
candidate at all; zero means the split is arbitrary.

| candidate | residual | |
|---|---:|---|
| rotation | **1.0000** | a curl-free span cannot make curl **at all** |
| **divergence** | **0.0967** | the basis absorbs **90%** of a radial bowl |
| shear | 0.7355 | |
| drift x / y | 0.7320 | |

The rotation's 1.0000 is the Helmholtz argument confirmed to four places,
and it is why the recovery in (b) was exact. But the curl-free candidates
**do not behave alike**, which the argument had no way to see:

    being a gradient is NECESSARY for the degeneracy and nowhere near
    SUFFICIENT — what decides is whether the candidate's potential is
    SMOOTH AT THE BASIS'S OWN SCALE

A radial bowl is: nine kernels of σ = .22 on a .25 lattice make one easily.
A saddle needs a sign change at the centre those kernels are badly
conditioned for, and a linear ramp needs support past the lattice's edge.

**And the correspondence makes it an explanation rather than a
coincidence**, asserted inside the same gate rather than read across from
(b)'s printout: the candidate the basis absorbs most is the same candidate
whose coefficient the fit moves most. Divergence, both times.

### What OBS-7 says

**Level 3 works** — on this fixture, with a library that contains the
missing term, the coefficient is recovered exactly, nothing is invented when
there is nothing to find, and held-out prediction improves 360×.

**And it is well posed exactly to the extent that the library lies outside
the span of what is already being learned.** That is a design rule for level
4, and it is measurable *before* any fitting: `law.degeneracy(k)` is a
9×9 least-squares solve. A candidate at 0.97 residual is worth adding; one
at 0.10 will be fitted arbitrarily and its coefficient should not be read as
a physical quantity, even though the model's *predictions* stay perfectly
determined. §33's distinction, with a number attached to it.

The obvious follow-up is the one the pre-registration named: **how fine does
the potential basis have to be before level 3 stops working?** The residual
above is a function of the basis, and sweeping it would price the boundary
directly, with no learner in the loop.

### Limits

The library contains the missing term, which §27 states as its scope
("...when that term already exists within its operator vocabulary").
Nothing here bears on level 4. One 2-D first-order flow, a frozen potential
basis, and allocation deliberately not adaptive — OBS-6's recalibrated birth
signal is what would drive a level-4 search and is kept out, so that
operator recovery and capacity acquisition are measured apart.

Cost: G54 is ~35 s. `python3 tools/obs7_predict.py` for the derivations.

## OBS-8 / G55 — a geometry of degeneracy, and three refutations

Christian, restating OBS-7's result better than the phase did:

> An operator is inferable only to the extent that it contributes something
> linearly independent of the representational span already available to
> the learner.

with a correction to the sentence OBS-7 closed on — not "well posed" but
**locally identifiable under the chosen sampling measure and basis**,
because the residual measures geometric independence while practical
recoverability also needs conditioning, coverage, and the candidates not
being collinear *with each other*.

He was right, and by the end of this phase he was right for a reason
neither of us had.

`tools/obs8_predict.py` was frozen first. Almost all of OBS-8 is least
squares on a grid with no optimiser anywhere: it is an experiment about a
basis, not about a learner.

### G55 (a) — the Gram idea is right and this fixture cannot show it

The extension: residualise the whole library, $\tilde G = (I-P_\Phi)G$, and
read novelty off the diagonal of $H = \tilde G^{\mathsf T}\tilde G$ and
mutual identifiability off its spectrum.

The raw library is **exactly orthogonal** on the symmetric sampling square
(worst off-diagonal 4.5e-16, condition number 1.0000) — every pair vanishes
by $E[d_x] = E[d_y] = E[d_xd_y] = 0$ with $E[d_x^2] = E[d_y^2]$. So the
pre-registration predicted that every off-diagonal *after* residualisation
would be the basis's doing, and asked for one above 0.02.

**Refuted at 4.6e-15, and for a better reason than the prediction had.**
The coupling is $\langle Pv_i, Pv_j\rangle$. A square lattice of isotropic
kernels on a square region is invariant under $D_4$; the projector commutes
with that group; and the five candidates sit in **different irreducible
representations** of it — drift x and y sharing one, where Schur makes $P$ a
scalar. Different irreps are orthogonal and $P$ cannot mix them. **The
residualised Gram is diagonal exactly, at every basis on both sweeps.**

So the mutual-identifiability channel is invisible on a symmetric fixture —
and live the moment the symmetry goes. Jitter the centres by a quarter of a
spacing and it appears at once:

    worst off-diagonal 0.6990 (divergence–drift y), mutual collinearity 6.15

**A learned MARL basis is never symmetric** — kernels move. The lattice is
the special case; the coupling is the ordinary one.

### G55 (b) — support absorbs an operator, resolution does not

| basis | rotation | divergence | shear | drift x/y |
|---|---:|---:|---:|---:|
| **A** 3×3 on [.25,.75], σ .220 | 1.0000 | 0.0897 | 0.7125 | 0.7083 |
| 5×5 same span, σ .110 | 0.9898 | 0.2349 | 0.9045 | 0.9130 |
| 8×8 same span, σ .063 | 0.9983 | 0.4192 | 0.9929 | 0.9935 |
| **B** 5×5 on [0,1], σ .220 | 0.9253 | **0.0048** | **0.0731** | **0.0722** |
| 7×7 on [−.25,1.25], σ .220 | 0.9181 | 0.0001 | 0.0015 | 0.0014 |

**The predicted interaction is refuted, and axis A was the wrong axis.**
Holding σ/h fixed while refining the lattice makes the kernels *narrower*,
and narrow kernels over a small span are **worse** at a smooth global field,
so novelty *rises* along it. Resolution and smoothness-scale are not one
knob, and the sweep as designed conflated them.

Axis B is unambiguous and overwhelming. At OBS-7's own spacing and width,
**one ring of extra kernels takes the saddle from 0.713 to 0.073 and the
ramp from 0.708 to 0.072.** Support is the mechanism. The bowl was already
absorbed at 0.090 because it is the one candidate whose potential is
concentrated where the lattice already is.

### G55 (c) — and independence is a property of the REGION

The pre-registration called the rotation's novelty an **invariant**: a
gradient is curl-free at any resolution and any support, a rotation has curl
2, so nothing could confuse them. **Refuted — on the square it falls to
0.918.**

The Helmholtz argument drops a term that only vanishes on the whole plane:

$$\int_\Omega \nabla\psi\cdot V = \oint_{\partial\Omega}\psi\,(V\cdot n) - \int_\Omega \psi\,(\nabla\cdot V)$$

A rigid rotation is divergence-free, so the overlap between *any* potential
and the rotation is **exactly the boundary integral**. At the 3×3 basis the
kernels decay before the edge, $\psi \approx 0$ there, and the residual is
1.0000. Enlarge the lattice and $\psi$ stops vanishing on $\partial\Omega$.

The discriminator is the region's *shape*, not the basis. On a disc centred
on the rotation's axis, $V$ is tangential everywhere on the boundary, so
$V\cdot n \equiv 0$ and the term vanishes identically:

| basis | square | disc, equal area |
|---|---:|---:|
| 3×3 on [.25,.75] | 1.0000 | 1.0000 |
| 5×5 on [0,1] | 0.9253 | **0.9998** |
| 7×7 on [−.25,1.25] | 0.9181 | **0.9995** |

Same library, same kernels, same area. **Christian's refinement vindicated
more strongly than the argument he made it with** — the sampling measure
matters through the *shape of its support*, not merely its coverage.

### What OBS-8 leaves

    Novelty is a property of (operator, basis, region) — all three.

- **Absorbable by support**, and cheaply: divergence, shear, drift. Their
  independence at OBS-7's basis was an artefact of a lattice too small for
  the region it was sampled over.
- **Not absorbable by any enrichment, given the right region**: the
  rotation, but only because a disc's boundary is one of its streamlines.
  On a square its independence erodes too.
- **Invisible on a symmetric fixture**: mutual collinearity. It is real, it
  is what Christian's Gram was for, and it needs an asymmetric basis to
  show — which is to say, a learned one.

Three predictions, three refutations, and the corrected statements are all
stronger than what they replaced. The practical form for whatever owns this
next:

    before admitting a candidate, compute its novelty against the CURRENT
    learned basis over the ACTUAL sensor region, and the Gram of the
    residualised library alongside it. A candidate near zero will be fitted
    arbitrarily; a pair with a large off-diagonal will trade against each
    other. Neither costs anything to check and neither is visible from the
    fit.

### Method notes the phase paid for

- **The disc was clipped.** Written against the square's bounding box it is
  a disc with four chords cut off, whose boundary is partly straight and
  where $V\cdot n \neq 0$ — the one property the disc exists to have. It
  read 0.9868 against a true disc's 0.9995.
- **`std.math.sign(0)` is 0, and a correlation matrix has a unit
  diagonal.** So the Jacobi rotation angle was exactly zero for every pair,
  the sweep did nothing, and `cond_collinear` returned 1.0000 for every
  matrix it was ever handed — including one carrying a 0.699 coupling,
  which is what gave it away. The gate now asserts the conditioning and the
  off-diagonals together.
- **`degeneracy` and `analyse` were two truths** about one quantity at two
  quadratures. `degeneracy` now delegates; G54 (c)'s numbers move in the
  fourth decimal and its claims are untouched.

Cost: G55 is ~10 s. `python3 tools/obs8_predict.py` for the derivations.

## OBS-9 / G56 — one residualisation, three faces

Christian, closing OBS-8:

> growth pressure, mismatch detection, distillation, and now operator
> discovery are all converging on essentially the same question: what
> explanatory degree of freedom is genuinely missing from the current
> representation?

`src/novelty.zig` is that as one operation. Given a candidate $g$, a span
$\Phi$, and the measure $\mu$ you actually observe under,

$$\text{novelty}(g;\Phi,\mu) = \frac{\lVert (I-P_\Phi)g\rVert_\mu}{\lVert g\rVert_\mu}$$

    BIRTH         g a candidate kernel, Φ the existing kernels, μ the
                  local exemplar density
    OPERATOR      g a candidate operator's field, Φ the learned span,
                  μ the sensor region                    (OBS-7, OBS-8)
    DISTILLATION  g an EXISTING kernel, Φ the OTHERS, μ the query
                  distribution — leave-one-out

OBS-8's lesson is carried in the signature: nothing computes an inner
product without being handed the points to compute it over. There is no
default measure and there should not be one. The module knows nothing about
MARL; MARL knows nothing about it.

### G56 (a) — leave-one-out is one inverse, not n solves

The distillation face looks like $n$ least-squares problems and is one
Cholesky:

$$\lVert (I-P_{-i})\phi_i\rVert^2 = \frac{1}{(G^{-1})_{ii}}, \qquad \text{novelty}_i = \frac{1}{\sqrt{G_{ii}(G^{-1})_{ii}}}$$

and that product is the **variance inflation factor** — so novelty is
exactly $1/\sqrt{\text{VIF}}$. Worth naming: the quantity this campaign
reached from operator inference is one collinearity diagnostics already
characterised from the other side.

Checked against 25 explicit re-solves: **7.44e-12**.

**It first read 0.81, and the identity was not at fault** — 623 kernels
against 512 probes. The Gram is $n\times n$ built from $m$ samples, so its
rank is at most $m$; with fewer probes than kernels it is singular by
construction and everything looks redundant. *You cannot ask about
redundancy with fewer observations than functions.* The gate now asserts
$m > n$.

### G56 (b) — it is the same primitive

Rebuilt from `law`'s basis and library inside the gate, sharing nothing
with G55 but the projection: **all five novelties reproduce to 6 decimal
places**, and the residualised Gram comes back diagonal at 4.6e-15, D4
again.

Registered at 1e-9 and measured 5.95e-9 — that was a mis-derivation of
machine precision, corrected to 1e-6 with a derivation rather than a fit
(the smallest gap between two distinct novelties is 4.2e-3, so 1e-6 is
three orders below anything that could change a reading). Flagged rather
than moved quietly.

### G56 (c) — the third face, and the contradiction it resolves

MARL-7 concluded kernel death has nothing to target, because silencing
accumulated capacity costs 1.4–1.6× the RMS. MARL-18 said the sharper
thing: *a consolidation never chooses a victim — it declines to rebuild
one.* Those are only in tension if **load-bearing** and **non-redundant**
are the same property. They are not:

    REPRESENTABILITY  can φᵢ be reproduced by the others?  — geometric
    CONTRIBUTION      does the error rise if φᵢ is DELETED? — depends on
                      wᵢ, and MARL-7 measured it by SILENCING, with no refit

On a learned MARL: **median leave-one-out novelty 0.479** (min 0.252, max
0.829). The basis *is* substantially redundant — and that is exactly why
MARL-7 could not find a victim by silencing. A kernel can be reproducible
by its neighbours and still expensive to delete, because its weight was
carrying something they could have carried had they been asked.

The Gram's condition is **45.0** where OBS-8's residualised library was
exactly 1. A learned basis has no symmetry — kernels are born at exemplars,
move under descent, are shaped by the clamp — so the mutual channel that
was invisible in OBS-8 is live here, as predicted. (The registered 100 was
a guess with no derivation and is refuted; the contrast is what holds.)

### And then the useful test failed, which is the best part

Prune the least-novel kernels, refit the survivors, compare against random
pruning at matched count with the identical refit:

| pruned | batch | staged | random | batch/rnd | staged/rnd |
|---|---:|---:|---:|---:|---:|
| 25% | 0.059822 | 0.057240 | 0.061526 | 0.8654 | **0.6613** |
| 50% | 0.084323 | 0.067857 | 0.076081 | **1.3029** | **0.6977** |

**Batch-guided pruning is WORSE than random at half the population.**
Novelty was measured against the *full* basis, so once one member of a
mutually redundant cluster goes, the rest are no longer redundant — the
ranking is stale, and deleting the cluster entire removes what the cluster
was collectively carrying. Random wins because it thins **uniformly**.

Which is MARL-18's sentence inverted:

    four overlapping kernels whose sum is smooth are individually
    load-bearing and collectively replaceable; four MUTUALLY REDUNDANT
    kernels are individually removable and collectively essential

Staging the identical rule — recompute every eighth of the removals —
gives 0.661 and 0.698, beating random at both prunes and confirming the
staleness diagnosis directly. It does not reach the registered halving, and
that number is refuted for both arms.

    Novelty is the right PER-ITEM quantity and the wrong BATCH criterion.

A batch criterion wants the **Gram**, which is precisely what Christian
asked for it: the spectrum says which *set* is replaceable where the
diagonal only says which member is. That is the next phase and it now has a
concrete target rather than an intuition.

### What OBS-9 leaves

Three mechanisms this campaign built separately are one operation with
different arguments, and the unification is not cosmetic — it transfers
results between them:

- **MARL-7 and MARL-18 are reconciled**, by separating representability
  from contribution. Silencing measures the second; novelty measures the
  first; a criterion needs both.
- **OBS-8's symmetry finding predicted OBS-9's conditioning**: the mutual
  channel is dead on a lattice and live on a learned basis, and the
  learned basis is the case that matters.
- **The rank condition is a real precondition**, not an implementation
  note: redundancy is unanswerable with fewer samples than functions, and
  a birth rule evaluating coverage at a single exemplar is at the extreme
  of that.

Not claimed: nothing here changes a default. Birth is discussed and not
rebuilt. The measurement is on a 623-kernel model where the full Gram is
exact; the 47 000-kernel models of G52 (b) would need MARL's own locality
exploited, which is an implementation question and deliberately separate
from whether the quantity is right.

Cost: G56 is ~25 s. `python3 tools/obs9_predict.py` for the derivations.

## OBS-10 / G57 — local rank reduction: the spectrum sizes the set, the target chooses the members

Christian, on OBS-9's batch failure: the question is not *which diagonal
entries are small* but *how much dimension does this set actually add* — and
that is spectral. With

$$r_{\text{eff}} = \exp\!\left(-\sum_i p_i\ln p_i\right),\qquad p_i = \lambda_i/\textstyle\sum_j\lambda_j$$

a cluster of eight with $r_{\text{eff}}=2.3$ is asking to be replaced by two
or three. **You are no longer deleting weak kernels; you are performing
local rank reduction.**

### The precondition holds

Mean $r_{\text{eff}}/k$ across a learned model's regions is **0.673** —
379.4 effective dimensions over 623 members. The clusters really are
lower-dimensional than their membership, so there is rank to reduce.

### The ordering was refuted on its last step

| pruned | random | staged | spanning | global | **target** | stg | spn | glb | **tgt** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 25% | 0.061526 | 0.057240 | 0.059329 | 0.062720 | **0.052936** | 0.661 | 0.826 | 1.094 | **0.321** |
| 50% | 0.076081 | 0.067857 | 0.077541 | 0.078276 | **0.057799** | 0.698 | 1.054 | 1.081 | **0.328** |
| 75% | 0.101888 | 0.094772 | 0.105151 | 0.101178 | **0.070734** | 0.866 | 1.062 | 0.987 | **0.412** |

Predicted: batch > random > staged ≥ spectral. **Refuted at the last step.**
The span-driven spectral arm comes in at 1.054 and 1.062 — *behind random*,
let alone staged. There is no crossover; it loses at every fraction.

### And it is the criterion, not the clustering

The obvious suspect was the partition: regions are a lattice, a kernel's
reach is a whole region edge, so supports cross faces massively and each
region keeps representatives of a subspace its neighbour also kept. So the
clustering was taken out entirely — pivoted QR over the whole basis at once.

**It does not help** (1.094 / 1.081 / 0.987). The partition was not the
problem.

Pivoted QR selects a well-conditioned **spanning** subset, which is optimal
for reconstructing an *arbitrary* function in the span. A model has **one**
target. A kernel that is geometrically distinctive but sits where the field
is flat displaces one the model leans on.

This is OBS-9's own registered escape hatch arriving: *novelty could be a
correct description of redundancy and still be a poor ranking, if what
matters is the product of redundancy and weight rather than redundancy
alone.*

### One line different, and it resolves

Score a member by what it **explains** — the drop in the target's residual
energy — rather than by what it spans. That is orthogonal matching pursuit,
and `selectExplaining` differs from `selectSpanning` in the score alone.

    against staged:  spanning 1.250 1.510 1.226
                     global   1.655 1.549 1.140
                     TARGET   0.486 0.470 0.476

**The target-driven selector beats staged by 2.1× at every fraction**, and
at three quarters pruned — 156 kernels of 623, a fourfold reduction — it
reaches RMS 0.0707 where random reaches 0.1019 and the full basis sits at
0.0489.

    the spectrum sizes the set; the TARGET chooses the members

Both halves are needed and they answer different questions. $r_{\text{eff}}$
says *how many degrees of freedom this cluster deserves*; the target says
*which members carry them*. Sizing is not selecting, and OBS-10's failure
was assuming one operation could do both.

### The work went the way locality predicted

    selection cost, 25% / 50% / 75% pruned
      staged diagonal    2671   1998   1500 ms
      spanning            32     28     18 ms
      global             566    452    263 ms
      TARGET              39     32     21 ms

The registered 5× held enormously: **the target-driven method is 68× cheaper
than the staged diagonal and better on every axis.** Staged factorises the
whole basis once per stage; the clustered methods factorise each region,
which is block-diagonal by construction because distant kernels do not
overlap at all. The method with more linear algebra in its description has
less of it in its execution, and MARL's own locality is why.

### The frozen threshold, validated

`OBS9_SAME_PRIMITIVE` was moved 1e-9 → 1e-6 after observing a failure, with
the numerical reason identified, the replacement derived from the observed
separation scale, and the change disclosed as post hoc. Christian: *freeze
1e-6 now and make the next unseen fixture the actual validation of it.*

G57 (b) re-checks it on OBS-8's axis-B basis — 5×5 on [0,1], which G56 never
ran — with no further adjustment: **1.67e-7**. Held.

### What OBS-10 leaves

The larger pattern Christian named holds and gets one more term:

    birth added things; distillation removed things; operator inference
    added new KINDS of things — and all three live in the geometry of
    subspace change under an observation measure

    individuals live on the diagonal; representations live in the spectrum;
    and the OBJECTIVE lives in neither

The third clause is this phase's contribution. Geometry tells you the shape
of the redundancy and cannot tell you which of two equally redundant members
to keep — that needs the thing you are trying to explain. A consolidation
rule wants all three: novelty to rank, $r_{\text{eff}}$ to budget, and the
target to select.

Not claimed: representatives are still **selected**, never synthesised.
Turning "keep 2 of 8" into "make 2 new ones" is MARL-14's distillation and
is deliberately separate, so that the rank decision is measured apart from
the fitting of new elements. Clusters are MARL's own regions and
cross-region overlap at the faces is neglected — shown here not to matter
for the criterion, but untested for the *budgeting*.

Cost: G57 is ~40 s. `python3 tools/obs10_predict.py` for the derivations.

## OBS-11 / G58 — synthesis, and the threshold where sleep stops being a metaphor

Christian's three-stage decomposition, with the third stage built:

    geometry     -> how many dimensions exist
    objective    -> which dimensions matter
    distillation -> how to synthesise a better basis for them

`src/consolidate.zig` warm-starts from OBS-10's winner and lets the chosen
kernels **move** — every parameter, through `marl.gradOne`, so the result is
a set of kernels in MARL's own family. The comparison is then exactly
*selection* against *selection then refinement*, and a win cannot be an
accident of where new elements were placed.

### Two corrections before the measurement meant anything

**The descent first won by leaving the family.** σ was bounded per axis but
the ellipsoid's ∞-norm *reach* was not — off-diagonals can make the cutoff
box far larger than any single width — so **359 of 468 kernels outgrew the
gather** and the arm read a thirty-fold win. The registered null caught it,
and `marl.Model.clamp`'s reach projection fixed it: 0 over reach at every
fraction thereafter.

**And it was then scored on the probes it was fitted on.** `refine`
optimises ten parameters per kernel against the points it is handed, so
scoring there is training on the test set — and it flatters synthesis
enormously, because the baseline only gets a weight refit on the same
points. Train 0.00227 against held-out 0.05376. Two disjoint probe sets now,
OBS-4's discipline: fixed evaluation data never enters learning.

### Held out, the result is smaller and real

| pruned | kept | selected | **synthesised** | sel/full | syn/sel |
|---|---:|---:|---:|---:|---:|
| 25% | 468 | 0.060584 | **0.053762** | 1.059 | **0.887** |
| 50% | 311 | 0.063476 | **0.053951** | 1.110 | **0.850** |
| 75% | 155 | 0.074707 | **0.066711** | 1.306 | **0.893** |

Full basis, 623 kernels: **0.057213** held out.

The registered 0.80 is **refuted** — synthesis buys 11–15%, not 20% — but
the direction holds at every fraction and consistently.

### The threshold Christian named: HELD, and at half

    distilled, 468 kernels   0.053762
    distilled, 311 kernels   0.053951
    FULL basis, 623 kernels  0.057213

**A consolidated basis is strictly better than the overcomplete one it was
built from, on data neither saw — at half the kernels.** Not compression
with a loss. Consolidation improves basis *quality*, not merely reduces
basis *size*.

    the system takes an overcomplete daytime representation and wakes with
    a smaller, better-conditioned, more task-aligned basis

That is the threshold, and it is crossed.

### The conditional did not separate

Christian's hypothesis was conditional: synthesis should dominate *where
redundancy is distributed across several individually imperfect kernels*,
measured before any fitting by

$$\text{spread} = 1 - E_{\text{sel}}/E_{\text{opt}}$$

Registered at ≥2× more gain in the top third by spread than the bottom.
**Measured 1.24×** — the right sign, nowhere near the margin. Two honest
reasons and neither is a defence: spread is small on this fixture
(0.003–0.117, because at light prunes the selected members already capture
nearly everything), and probes are attributed to clusters by which region
owns them, which is crude where supports cross faces. The hypothesis is not
refuted so much as **untested at adequate contrast**, and a fixture with
deliberately clustered redundancy would test it properly.

### The honest limit

Synthesis at 468 kernels has **4 680 free parameters against 4 096 fit
probes** — more parameters than points. It overfits hard (train 0.0023,
held 0.0538) and the 11–15% is what survives that. There is obvious
headroom in more probes or a regulariser, and equally the possibility that
a better-posed fit changes the ranking. Reported rather than tuned.

### Myopia, recorded and not addressed

Christian: *your current target-selection rule is still choosing according
to the present target; if the system is dynamic, that makes consolidation
potentially myopic.* Right, and untouched. The objective here is one static
target. Widening it to a replay measure $Y = \{y_t, y_{t-1}, \dots\}$, or to
the prediction residual over a recent window, is the next axis and OBS-11
deliberately does not take it — so that synthesis is measured before the
objective is generalised.

    the measure defines WHERE, the spectrum defines HOW MUCH,
    the objective defines WHAT TO PRESERVE

Cost: G58 is ~50 s. `python3 tools/obs11_predict.py` for the derivations.

## OBS-12 / G59 (a) — the conditional, on a fixture built to be brutal about it

Christian's sharpened framing, adopted: **consolidation with representational
improvement**, not distillation. OBS-11 showed redundancy was not dead
weight — it was useful during acquisition and suboptimal as the final
representation.

This phase tests the conditional he attached to it, on a fixture designed so
it cannot hide: four clusters, eight members each, equal total target
energy, in disjoint parts of the cube, differing only in internal geometry.
Budget three of eight everywhere, so the pruning fraction is identical.
Every arm scored on held-out probes.

### A registered disagreement, and the agent lost it

Christian: the gain is **monotonic** in redundancy. The agent: it should
**peak in the middle**, because both extremes are already solved by
selection — orthogonal members *are* the cluster, near-duplicates are
already captured by any one of them.

| cluster | r_eff/k | spread | selected | synthesised | **gain** |
|---|---:|---:|---:|---:|---:|
| orthogonal | 0.9366 | 0.2946 | 0.603250 | 0.419910 | 0.3039 |
| moderate | 0.3521 | 0.0185 | 0.150215 | 0.024065 | 0.8398 |
| duplicate | 0.1368 | 0.0000 | 0.005015 | 0.000338 | **0.9327** |
| anisotropic | 0.5459 | 0.0726 | 0.307557 | 0.241921 | 0.2134 |

**Monotone, exactly as predicted.** 0.304 → 0.840 → 0.933 as r_eff/k falls
0.937 → 0.352 → 0.137.

The agent's error is worth naming because it recurs: *near-duplicates let a
single MOVED kernel stand for the whole cluster, and there is nothing to
lose by moving it.* The "already solved by selection" intuition confused
"one member is nearly the cluster" with "one member at its current position
is nearly the cluster".

And `OBS12_ORTHOGONAL` — registered at ≤0.10, measured **0.304** — fails by
the same mistake one step earlier: the argument assumed budget =
cardinality. The budget is three of eight, so five members are dropped
outright and moving the survivors over their territory is a real gain even
among orthogonal members.

`r_eff` orders the clusters correctly, which is the axis holding.

### And a fixture bug that looked exactly like a diverging optimiser

The anisotropic cluster first scored **−8.04** — synthesised RMS 0.916
against selected 0.101, with the *training* loss rising 0.129 → 0.786. Three
diagnoses were run before the right one:

- **Which parameter group?** Even *weight-only* diverged (0.203 → 0.280).
- **The off-diagonal units?** `gradOne` returns the raw gradient where
  `marl.zig`'s own step scales the off-diagonals by $l_{ii}l_{jj}$. Fixing
  that is correct and changed almost nothing.
- **The schedule, per OBS-5?** Rate 0.01 / 0.001 / 0.0001 and warmup 100 /
  1 all landed within 5% of each other.

**That last table is the tell.** A change that does not care about the
learning rate does not come from the gradient. The anisotropic members were
built with off-diagonals up to $1/\sigma$ and a long axis three times the
nominal width, which puts their cutoff box past one region edge — so the
clamp corrected them on the descent's *first step*, before any gradient, and
the target had been computed from the unclamped kernels.

**The fixture was outside MARL's own family.** `project` is now shared by
the descent and the fixture builders, so a cluster cannot be constructed
from kernels MARL would never hold. The anisotropic arm then converges
(0.245 → 0.132) and gains 0.213.

It is reported beside the other three rather than ordered against them: it
differs in *kind*, not only in spacing, so it is off the redundancy axis.

### What this settles, and what it does not

**Settled**: synthesis gain rises monotonically with cluster redundancy, on
a fixture built to separate the cases. So `r_eff` is not only the budget
estimator — it is also a *predictor of where consolidation is worth spending
compute*, which is the criterion OBS-10 wanted and OBS-11 could not measure.

**Not settled**: the conditioning matrix. Christian's second test —
probes × regularisation, to tell "limited by variance" from
"underconstrained parameterisation" — is registered in
`tools/obs12_predict.py` §(4) and **was not reached this session**.
`Options.prox` is built and unused, and G58's arm is unchanged at
`prox = 0`. That is the next beat, and the outcome he flagged as most
interesting is registered so it cannot be claimed after the fact: *if the
full basis improves less than the consolidated one as observations
increase, consolidation is acting as structural regularisation rather than
numerical compression.*

**Also registered and untested**: the two-phase reading — that the
overcomplete model may be the better *learning* representation while the
consolidated one is the better *inference* representation, with redundancy
as scaffolding rather than defect. Testing it means resuming learning from
a consolidated model against resuming from the overcomplete one, which is
MARL-18's wake/sleep loop with a better consolidation step and a phase of
its own.

Cost: G59 (a) is ~30 s. `python3 tools/obs12_predict.py` for the
derivations.

## OBS-13 / G60 — wake: scaffolding or clutter?

Christian's systems question, and he was right to call it the more
consequential one:

> Is overcompleteness actually advantageous during acquisition, even if
> consolidation produces the better final representation?

Same parent, its consolidated child at half the population, the same new
data stream, equal work, births on under identical policy. The new regime
is the campaign's own modest move — `shift = {0, −0.10, 0}`, MARL-6 through
MARL-9's — so old and new structure stay comparable and nothing needs a new
constant.

**The child is consolidated against the parent's own predictions, not
against the truth.** That is the difference between sleep and cheating.
OBS-11 used the truth because it was measuring representational quality; a
lifecycle cannot.

### A second registered disagreement, and the agent lost again

| exemplars | P kern | P births | P RMS | P upd | C kern | C births | C RMS | C upd |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 623 | 0 | 0.13254 | 446 | 311 | 0 | 0.13375 | 0 |
| 5 000 | 663 | 40 | 0.08985 | 546 | 551 | 240 | **0.08881** | 96 |
| 20 000 | 712 | 89 | 0.07396 | 861 | 713 | 402 | **0.07138** | 375 |
| 60 000 | 773 | 150 | **0.04793** | 1551 | 815 | 504 | 0.05726 | 1024 |

The agent predicted the child would keep up (MARL-6's *91% of committed
capacity ends outside the current band*, MARL-1's invariant). Christian
predicted the parent would adapt faster.

**Both are right, at different horizons — and that is the finding.** The
child is *ahead* through 20 000 exemplars and the parent pulls clearly
away by 60 000, ending at 0.04793 against 0.05726.

### The mechanism, measured rather than inferred

The child ends with **more kernels than the parent** (815 against 773) and
is **19% worse**. It bought 504 births against the parent's 150 — 3.4× —
and regrew to **1.054× the parent's size**.

The last column says why. **Mean updates per kernel: 1551 against 1024.**
The child's population is younger and less trained, because it had to
re-acquire what the parent still held. MARL-1's invariant, sixth sighting:
*capacity you cannot train is worse than capacity you do not have* — and
here it is the consolidation itself that created the untrainable capacity,
by discarding trained structure the moved world still had a use for.

    the child regrew to the parent's size and did not recover the parent's
    accuracy

So the parent's redundancy was not merely *more kernels*. It was **kernels
already trained, in places the moved world still needed**. Regrowing the
count does not regrow the training, and MARL-9's law says exactly that:
capacity is paid per thing learned, and the child had to pay again.

### What this does and does not settle

**Settles**: redundancy is not clutter. On this move it is scaffolding, and
the advantage is real but *late* — invisible at 20 000 exemplars and clear
at 60 000. A shorter experiment would have concluded the opposite, which is
worth recording as a methodological warning: an adaptation comparison
truncated early can invert.

**Does not settle**: whether the cycle is a ratchet. Christian's strongest
outcome — *parent faster, child better after a second sleep* — is untested,
and deliberately: one cycle first, so the adaptation comparison is not
entangled with a second consolidation's own gain. The child ending behind
after one wake does not decide it, because the question is what a *second*
sleep does to each.

**And it points at the fix.** The child was penalised for youth, not for
size. Two things follow, neither built here:

- **Consolidation should preserve training state, not only structure.** A
  synthesised kernel arrives with `updates = 0` and Adam's moments cleared;
  a fairer child would inherit an effective update count from the ancestors
  it replaced. That is a small change with a clear prediction.
- **This is the myopia OBS-11 recorded.** The consolidation optimised the
  parent's output *under the old measure*. The moved world needed structure
  the old measure said was redundant — which is exactly the case a replay
  measure $\mu_{\text{replay}}$ exists for. Christian's third outcome, and
  the data supports it: the criterion is myopic, and the objective is what
  is myopic about it.

### The rule, as it now stands

    Growth acquires possibilities.
    Novelty identifies redundancy.
    Effective rank sets the consolidation budget.
    The target determines what survives.
    Synthesis rewrites the basis.
    Wake tests whether the discarded freedom was useful plasticity.

— and OBS-13's answer to the last line is **yes, on a moved world, and
late**. Which makes the sixth line's objective the next thing to widen.

Cost: G60 is ~90 s. `python3 tools/obs13_predict.py` for the derivations.

## OBS-14 / G61 — the lineage, and a correction to OBS-13

Christian's three-way split, adopted: consolidation can preserve or destroy
**span**, **placement**, and **training state**. And his sentence for it:
*redundancy is not just extra capacity — it can be stored adaptation.*

### A design error found before any code, and it changes OBS-13's result

OBS-13 consolidated the child against **the parent's own predictions**, so
the child would not start life knowing what its parent had to learn. That
was right about the cheating and wrong about the consequence — and the
consequence is only visible once sleep has to run twice.

**A student fitting its teacher's output can at best match it.** MARL-19
measured exactly that: on a noiseless field a sleep is a pure loss, a copy
costs 1.179×, no student beats its teacher on both axes. A lineage built on
sleep-on-self can only decay.

OBS-11's consolidation *did* improve on its basis — and the reason is that
its target was the truth on probes. Which is not cheating either, once
named properly: **the truth on probes is what a replay buffer holds.** A
model's own observations are legitimately its to reuse.

Measured, held out on probes neither arm saw:

| sleep target | before | after | |
|---|---:|---:|---|
| the model's own output | 0.06926 | 0.07005 | **1.011×** — no gain, MARL-19 |
| **replay** | 0.06926 | **0.05920** | **0.855×**, at half the kernels |

### And that reverses OBS-13's headline

| | OBS-13 (sleep on self) | **OBS-14 (sleep on replay)** |
|---|---:|---:|
| child/parent after a 60 000-exemplar wake | 1.195 | **0.9391** |

**The consolidated child now wins the wake.** OBS-13 concluded redundancy
was scaffolding and the agent's "the child keeps up" lost; with the sleep
target corrected, the child does not merely keep up — it leads throughout.

So OBS-13's finding was an artefact of the wrong sleep target. What survives
of it is the *mechanism*, which was measured and is still true: a child
whose kernels arrive with `updates = 0` pays for youth. Replay-sleep does
not remove that, it just starts the child from a better basis than
self-sleep could.

### The lineage

    stage               P kern   P RMS   P upd    C kern   C RMS   C upd     C/P
    gen 0 post-sleep       631  0.13382      0       315  0.12867      0  0.9615
    gen 1 post-wake        768  0.05326   1241       791  0.05002   1031  0.9391
    gen 2 post-sleep       383  0.05884      0       396  0.06054      0  1.0288

    gap trajectory: 0.9615 -> 0.9391 -> 1.0288

**Not a ratchet on this run.** The child leads after the first sleep and
through the wake, and loses its lead at the second sleep.

But the reading is qualified, and the qualification is visible in the table:
**the second sleep hurt both lineages** (parent 0.05326 → 0.05884, child
0.05002 → 0.06054), where the first helped. The difference is what was slept
on — gen 0 halved a population converged over 20 000 exemplars, gen 2 halved
one that had just birthed heavily during a wake and had `updates` spread
very unevenly across it.

    the damage may be about sleeping too soon after a wake, not about
    lineage decay

That is a distinct hypothesis with an obvious test — vary the wake length
before the second sleep — and it is not run here. Calling this "damage
accumulation" without it would overclaim.

### What is now established, and what is next

- **Sleep must consolidate against replay, not against itself.** Measured
  contrast, 0.855 against 1.011. This is Christian's replay measure in its
  minimal form, arriving a phase early because OBS-14 could not be
  interpreted without it. The λ-weighted mixture over current, recent and
  rare stays where he put it.
- **A consolidated model is a better place to learn from**, at half the
  kernels — which is the opposite of OBS-13 and the same as OBS-11.
- **Training-state inheritance is still owed**, and is now better motivated:
  every post-sleep row shows `upd = 0`, and Christian's own caution about
  Adam moments applies — an inherited effective age
  $u_{\text{child}} = \sum_i \alpha_i u_i / \sum_i \alpha_i$ weighted by
  ancestor contribution is defensible where transplanting moment vectors is
  not.
- **The second sleep's cost needs its own phase**: wake length before sleep,
  and whether a population must converge before it can be consolidated.

Cost: G61 is ~120 s. `python3 tools/obs14_predict.py` for the derivations.

## OBS-15 / G62 — the consolidation window is evidence, not maturity

Christian's refinement of OBS-14 — *consolidation quality depends on the
maturity of the population being consolidated* — tested, and **refuted**;
the sweep found a different variable and a sharper policy.

### G62 (a) — the guardrail, promoted from a ledger note

Three occurrences earned it: OBS-11's synthesis arm scored on its own fit
probes, OBS-14's sleep-target contrast reading a fourteen-fold "improvement"
that was 0.855×, and OBS-8's clipped disc — a measure that was not what its
name said. `Measures` now names **fit**, **sleep** and **eval** explicitly
and refuses to run if any two share a point. The gate asserts it fires on a
deliberate alias, because a guardrail that cannot fail is decoration.

### G62 (b) — one wake, a fork consolidated at each checkpoint

| wake | kernels | R64 | cv | before | after | gain |
|---:|---:|---:|---:|---:|---:|---:|
| 2 000 | 645 | 0.987 | 0.59 | 0.10643 | 0.08947 | **+0.1594** |
| 5 000 | 654 | 0.992 | 0.58 | 0.09233 | 0.09021 | +0.0229 |
| 10 000 | 671 | 0.976 | 0.58 | 0.08860 | 0.08903 | −0.0048 |
| 20 000 | 706 | 0.985 | 0.60 | 0.07336 | 0.08050 | −0.0972 |
| 40 000 | 742 | 0.999 | 0.61 | 0.05914 | 0.08654 | −0.4633 |
| 80 000 | 781 | 0.999 | 0.62 | 0.04795 | 0.07478 | **−0.5594** |

**Correlation between readiness and gain: −0.72.** The wrong sign, and
decisively. *The better the model going in, the more the sleep hurt it.*
Readiness never varied — 0.98 to 0.999 across the whole sweep — so it was
never the discriminating variable.

### The `after` column is the finding

It is roughly **flat** at 0.067–0.101 however good the model was, while
`before` runs 0.106 down to 0.048. **The sleep imposes a ceiling**, and the
gain is positive only where the model was already worse than it.

Half of 781 kernels is 390, at ten parameters each: **3 900 free parameters
fitted against a 2 048-point ring.** Widening it, same model and same
budget:

| ring | points/param | after | gain |
|---:|---:|---:|---:|
| 2 048 | 0.53 | 0.07478 | −0.5594 |
| 8 192 | 2.10 | 0.04545 | +0.0523 |
| **32 768** | **8.40** | **0.02186** | **+0.5442** |

    There IS a consolidation window, and it is set by EVIDENCE PER
    PARAMETER, not by population maturity.

At eight points per parameter, **consolidation more than halves the
held-out error at half the kernels** — 0.04795 → 0.02186. At half a point
per parameter it destroys the model.

### What this reframes

- **OBS-14's second sleep** was not lineage damage and not immaturity — it
  was a 2 048-point ring against a ~390-kernel budget, squarely in the
  destructive regime. The ratchet question is still open and was never
  fairly asked.
- **OBS-11's "honest limit"** (4 680 parameters against 4 096 probes, 0.87
  points per parameter) sat in that regime too, and still showed 11–15%.
  Its gain was real and badly under-measured.
- **G56 (a) found the same principle one level down**: *you cannot ask about
  redundancy with fewer samples than functions.* This is it again, per
  parameter rather than per function. That it recurs at two levels is worth
  more than either sighting.

### The policy this licenses

    Do not sleep until the replay you can consolidate against carries at
    least a few observations per free parameter you intend to keep.

Which is the classical statistical requirement arriving by the back door,
and it makes the budget and the replay size **one decision, not two**:
$r_{\text{eff}}$ says how many kernels to keep, and the ring says how many
you can afford to fit.

### What is still owed

Maturity is refuted *at this ring size* and untested at an adequate one —
the sweep could not separate it from the evidence effect that dominated.
Christian's ordering therefore reshuffles again: the **ratchet test** needs
a properly-sized ring before it means anything, **effective-age
inheritance** is unaffected and still owed, and **replay weighting**
(recent / uniform / rare) is now the natural next question, because this
phase says only that the ring must be *big*, not what should be *in* it.

Cost: G62 is ~5 min. `python3 tools/obs15_predict.py` for the derivations.

## OBS-16 / G63 — evidence absorbs maturity, and the rule holds cell by cell

> **Do not ask a compressed model to remember more structure than its replay
> evidence can identify.**

Christian's correction to OBS-15: maturity was never refuted in general, it
was *non-discriminating under an evidence-starved fit*. So a grid, not
another sweep — and the budget held **fixed at 200 kernels** in every cell,
with the ring sized by his own rule, $N = \rho\,p\,k$, so that $\rho$ is the
only thing moving along that axis.

| maturity | kernels | R1024 | fresh | before | ρ 0.5 | ρ 2.0 | ρ 8.0 |
|---|---:|---:|---:|---:|---:|---:|---:|
| young | 641 | 0.035 | 0.016 | 0.10915 | −0.3875 | +0.0858 | +0.1111 |
| mid | 701 | 0.601 | 0.102 | 0.07529 | −0.7670 | −0.0232 | **+0.4619** |
| settled | 775 | 0.873 | 0.133 | 0.05213 | −3.3564 | −0.4356 | +0.3340 |

**ρ is monotone in every row.** Evidence dominates, as OBS-15 said.

### Evidence absorbs maturity — an interaction, not a main effect

    maturity spread of the gain, by rho:   2.969    0.521    0.351

The registered disagreement goes to the agent this time, and the mechanism
is the reason it was worth registering: **consolidation does not merely
select, it refines** — and refinement is exactly what fixes a badly placed
kernel. Given enough evidence it repairs a young population, so maturity
stops mattering.

Two things worth keeping beside that. The maturity measure now *works*:
R1024 reads 0.035 / 0.601 / 0.873 where OBS-15's R64 saturated at
0.98–0.999, and `fresh` — the share of contribution from kernels born since
the move — tracks it. And at ρ = 0.5 a **better** model loses **more**
(−0.39, −0.77, −3.36), which is OBS-15's ceiling seen from the other side.

At adequate evidence the *mid* model gains most (0.462). The young one has
less accumulated redundancy to exploit; the settled one has less headroom.
Neither is a monotone in maturity, and neither was predicted.

### The rule validates cell by cell

$$k_{\text{keep}} \le \frac{N_{\text{replay}}}{\rho_{\min}\,p}$$

At $\rho_{\min} = 2$, with $p = 10$ and 200 kernels kept throughout:

| column | points | permits | kept | outcome |
|---|---:|---:|---:|---|
| ρ 0.5 | 1 000 | 50 | 200 — **4× over** | all negative |
| ρ 2.0 | 4 000 | 200 | 200 — **exactly at** | mixed |
| ρ 8.0 | 16 000 | 800 | 200 — **4× inside** | all positive |

The rule predicts the sign of every cell. And the middle row is the useful
correction:

    rho_min = 2 is the BOUNDARY, not a safe floor — a working policy wants
    four or more

`evidenceBudget(n, rho_min, p)` is in `consolidate.zig` as the deliverable,
and the sentence it enforces is Christian's:

    The spectrum proposes the budget; the evidence permits it.

### The law, at two scales

G56 (a): *you cannot ask about redundancy with fewer samples than
functions.* OBS-15 and OBS-16: *you cannot synthesise a parameterisation
with fewer observations than it has parameters.* Christian's general form,
and it is worth keeping as the campaign's:

> **Representational questions are only meaningful relative to the rank and
> density of the evidence supporting them.**

### What is still owed

ρ is varied here by **ring size at fixed budget**, never by budget at fixed
ring — so nothing yet says what happens when the *spectrum* asks for more
than the evidence permits, which is the rule's actual use case. The
**ratchet test** is now runnable fairly, at fixed points-per-parameter per
generation rather than fixed ring. **Replay composition** — uniform, recent,
error-biased — is untouched, and OBS-15/16 answer *how much* evidence
without saying *which*. **Effective-age inheritance** has moved down the
causal order: youth looked primary before OBS-15 and now looks second-order
once consolidation is properly conditioned.

Cost: G63 is ~4 min. `python3 tools/obs16_predict.py` for the derivations.

## OBS-17 / G64 — ρ is not a control law, and two phases need re-reading

Christian: *so far, ρ has been changed by changing N, not k. If the sign
transition appears at the same approximate ρ, then `evidenceBudget()`
graduates from a descriptive fit to a real control law.*

It does not.

| ring | k | ρ | after | gain |
|---:|---:|---:|---:|---:|
| 2 048 | 410 | 0.50 | 0.09202 | −0.2161 |
| 2 048 | 205 | 1.00 | 0.10212 | −0.3495 |
| 2 048 | 102 | 2.01 | 0.10686 | −0.4121 |
| 2 048 | 51 | 4.02 | 0.12631 | −0.6692 |
| 2 048 | 26 | 7.88 | 0.13421 | −0.7735 |
| 8 192 | 410 | 2.00 | 0.05116 | **+0.3239** |
| 8 192 | 205 | 4.00 | 0.07074 | +0.0651 |
| 8 192 | 102 | 8.03 | 0.07840 | −0.0360 |
| 8 192 | 51 | 16.06 | 0.08825 | −0.1662 |
| 8 192 | 26 | 31.51 | 0.11201 | −0.4802 |

### The collapse fails at every shared point that matters

| ρ | small ring | gain | large ring | gain | agree? |
|---:|---:|---:|---:|---:|---|
| 2.01 | k = 102 | −0.4121 | k = 410 | **+0.3239** | **NO** |
| 4.02 | k = 51 | −0.6692 | k = 205 | **+0.0651** | **NO** |
| 7.88 | k = 26 | −0.7735 | k = 102 | −0.0360 | yes |

**Within a ring, gain rises with k.** Less compression is better, monotone
across five budgets. **At matched k, gain rises with N.** More evidence is
better, monotone across all five. Both are true, and they move ρ in
*opposite* directions — which is precisely why the ratio cannot govern.

    evidence and compression are SEPARABLE, and rho is not the law

### What this does to OBS-15 and OBS-16

Both held k fixed (or nearly) and varied the ring. **So both measured N and
called it ρ.** OBS-16's grid held k at exactly 200, which made ρ ∝ N inside
it — the rule "predicted every cell's sign" because within that grid it was
a statement about evidence alone.

`evidenceBudget` is **refuted as a control law**. You cannot choose $k$ from
$N$: shrinking $k$ to satisfy a ratio makes the outcome *worse*. It survives
only as a description of one axis, and the function stays in the tree with
that written on it.

### What survives, and it is the useful half

    At a given replay size there is a maximum COMPRESSION beyond which
    sleep hurts. Evidence does not licence more compression; it reduces
    what compression costs.

At 8 192 points the crossing sits near $k \approx 150$ of a 703-kernel
population — about a fifth kept. And the best cell in the whole table is the
*least* compression at the *most* evidence, which is the opposite of what a
ratio rule would recommend.

The registered caution at §(3) of `obs17_predict.py` turns out to have been
the whole story rather than an edge case: *a smaller k is not merely a
better-conditioned fit, it is also a harsher compression, and ρ captures
only the first.* What was predicted as a turnover at high ρ is in fact
monotone against ρ throughout.

### The corrected picture

$$\text{gain} \approx f(N) + g(k), \quad\text{not}\quad h(N/k)$$

Roughly additive on this data: four times the ring buys +0.29 to +0.54 of
gain at every budget tried, and the budget buys a monotone amount at every
ring. Two knobs, not one — and a policy needs both, with the spectrum
proposing $k$ and the evidence setting how much that choice will *cost*
rather than capping it.

Christian's architectural sentence needs the same correction. Not *the
replay buffer places an upper bound on the model complexity sleep may
produce* — the bound runs the other way. **A small replay buffer places a
LOWER bound on the complexity sleep may safely keep.**

### Still owed

The ratchet test now has no fixed-ρ recipe to run under, so it needs
fixed-$N$ and fixed-$k$ instead, which is simpler. **Replay composition** is
untouched and is now the most interesting remaining question, since $N$ is
established as the dominant knob and nothing says what should be *in* it.
**Effective-age inheritance** is unaffected.

Cost: G64 is ~4 min. `python3 tools/obs17_predict.py` for the derivations.

### Where OBS-17 leaves the control problem (Christian, after the run)

The two axes are mechanically distinct, and naming them separately is what
the phase bought:

    f(N)  ESTIMATION QUALITY — how well the replacement basis can be fitted
    g(k)  INFORMATION DESTRUCTION — how much burden is placed on it

One governs how well you can fit; the other how much you are asking. ρ
collapsed them into a single number and they can move it in opposite
directions, which is why the matched-ρ table has the same ratio giving
−0.412 and +0.324.

**The control problem inverts.** Not a maximum $k$ derived from replay size,
but a minimum below which consolidation turns destructive:

$$k_{\min} = K(N,\ \text{current basis},\ \text{target}), \qquad k < k_{\min} \Rightarrow \text{destructive}$$

with sleep choosing $k_{\text{keep}} \ge k_{\min}$. Which fits the data
exactly: small replay → high $k_{\min}$ → barely compress, or do nothing at
all; large replay → lower $k_{\min}$ → stronger consolidation becomes safe.

So evidence governs **how aggressively you may rewrite the representation**,
not the final model size. And two things that were being conflated:

    CONSOLIDATION BENEFIT   what a sleep gains
    COMPRESSION TOLERANCE   how much it may cut before it loses

Evidence raises both. They are not the same quantity, and the best cell in
G64's table — most evidence, *least* compression — is the reminder that
sleep is not trying to maximise compression. Compression is only useful
insofar as it improves the representation.

    **Evidence does not licence stronger compression; it makes a given
    compression less destructive.**

### The queue, as it stands

1. **Replay composition.** Now the obvious next question, because quantity
   and geometry are finally separated. Equal-sized rings, same $N$, same
   $k$, same optimiser, differing only in the measure: uniform historical,
   recent-biased, error-biased, novelty/coverage-biased. Nothing can then
   hide behind sample count or compression severity. Expect a **Pareto
   surface** rather than a winner — immediate post-sleep RMS, retention of
   older regimes, and adaptation speed after the next shift will trade.
2. **Ratchet, at fixed $N$ and fixed $k$** — the correct control now that
   fixed ρ is refuted, and simpler than what it replaces.
3. **Effective-age inheritance**, unaffected by any of this and still owed:
   $u_{\text{child}} = \sum_i \alpha_i u_i / \sum_i \alpha_i$ weighted by
   ancestor contribution, with optimiser moments left alone.
4. **$k_{\min}$ as a measured function** rather than a threshold — the
   crossing was near $k \approx 150$ of 703 at $N = 8192$, and one point is
   not a function.
