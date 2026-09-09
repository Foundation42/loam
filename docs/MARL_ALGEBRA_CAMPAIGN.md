# MARL Field Algebra — Campaign

**Operators, projection and transport over learned fields**\
**Project:** Loam / Matryoshka\
**Design note:** `docs/MARL_Field_Algebra.md` (Christian, September 2026)\
**Status:** ALG-1 and ALG-2 measured; G45–G46 investigate support width and selective transport\
**Date:** Wednesday 9 September 2026

------------------------------------------------------------------------

## 1. Premise

Twenty-five phases asked one question:

> **How little representation is required to describe this field?**

The design note asks the second one:

> **How little computation is required to evolve this field?**

and proposes the machinery to try it — differential operators taken
analytically from the kernels, a projection that turns any continuous
expression back into a model, and transport built from the two:

$$F' = P_F\!\left[\,F - \Delta t\,(V\cdot\nabla F)\,\right].$$

The claim worth testing is not that MARL can simulate a field. A grid
does that extremely well. It is §39's:

$$\text{simulation cost} \propto \text{information change}$$

rather than domain volume × frame rate.

This is a **new lab book because it is a new question**, not a new
subject. The phases are numbered **ALG-1, ALG-2, …** so that nothing has
to be renumbered if the two campaigns run side by side; the gates
continue the single G-series (`G44` is next) because there is one suite.
The ledger stays one file — `docs/implementation-notes.md` — for the
reason it always has: a decision is only findable if there is one place
decisions are.

------------------------------------------------------------------------

## 2. Standing

The same standing as MARL itself, one level out. `src/field.zig` is a
FOURTH file importing `marl.zig` and imported by neither it nor
`rbf.zig` — `marble.zig`, `cache.zig` and `milk.zig`'s precedent, and
Christian's split enforced by construction:

- **`marl.zig` must not learn what an operator is.** A model that knows
  about advection is a model whose kernel has a second customer.
- **`rbf.zig` must not learn what an expression is.** It is cross-repo
  pinned; rill and the shader read it.
- The kernel's derivatives are built on `marl.mahal` — the pinned
  primitive — and live in `field.zig`, NOT in `marl.zig`. G17 (a) holds
  MARL's kernel to `rbf.zig`'s bit for bit, and a derivative `rbf.zig`
  does not have would make the twin asymmetric on the exact surface the
  pin defends. *This is a call, not a law; if Christian would rather the
  gradient sat beside the gaussian, it moves and the pin grows a row.*

`field.Options.best()` from the first commit, each element naming the
phase that set it. The hyperparameter-spill ruling was paid for by eight
gates each writing `rate_geom = 0.02` as a literal; this campaign starts
on the other side of it.

------------------------------------------------------------------------

## 3. What the campaign already decides

The design note is written as though from a standing start. It is not:
several of its open questions have answers in the ledger already, two of
its proposals have been measured and lost, and one of its mechanisms is
already built and gated under another name. Recording that up front is
what stops this campaign paying twice.

### 3.1 The projection operator already exists (§6, §23 — MARL-14)

§6 defines $P_M[G]$ and says "MARL learning itself can serve as the
projection operator". It already does. `cache.distil` takes a teacher, draws
sample points, asks the teacher for a value and feeds `observe` — and the
teacher enters through exactly one line, `teacher.predict(x)`. Replace
that with any `fn([3]f32) -> Vec` and distillation IS $P_M[G]$ for an
arbitrary continuous $G$, which is what a lazy expression graph is.

So **§6 and §23 are one mechanism, not two.** Distillation is not a
consolidation step that happens after simulation; it is the projection
operator that simulation is made of. Everything G34 and G37 measured
about what a copy costs is already a statement about what one timestep
costs.

### 3.2 Every projection costs, and the compounding is the open question (MARL-14, MARL-19)

MARL-19's θ frontier, on a **noiseless** field: 1.041× kernels at 1.266×
RMS, 0.890× at 1.268×, 0.736× at 1.327×, 0.528× at 1.636×. **No student
is better than its teacher on both axes.** A single sleep on a noiseless
field costs 1.179×.

An evolution loop is N projections deep. At 1.18× compounding, ten steps
is 5.2× and a hundred is unusable. MARL-14 measured that it does NOT
compound on a static field — A→B 1.058, B→C 1.036, the second copy
*cheaper* than the first — with a mechanism: B is already a sum of
anisotropic gaussians, which is exactly the student's hypothesis class,
where the truth is not.

**That mechanism does not obviously survive transport.** Under advection
the field is TRANSFORMED between copies, so the student is not re-fitting
its own hypothesis class; it is fitting a warped version of it. Whether
generation loss compounds under a transformation is the load-bearing
unknown of this campaign, and it decides §40's criterion (4) —
"repeated evolution remains stable" — on its own. It is ALG-2.

### 3.3 Advection is drift, and drift has a law (MARL-6 … MARL-10)

The campaign has already run "the world moves and the model follows",
five times, and ended with a fitted law rather than a threshold:

- MARL-7: over six moves, **accuracy flat, capacity linear** at ~1000
  kernels a move. Unrefinement fires precisely and moves it by 1%.
- MARL-9: cycling between two worlds against walking to six —
  **capacity is paid per THING LEARNED, not per change.** The walking
  arm's marginal cost is flat at ~2100 kernels a move; the cycling arm's
  decays to 159 by the twelfth, and cycling is also more accurate.
- MARL-10: growth is $K_0 + A\,H(N)$ — **logarithmic** — with $n\Delta K$
  flat at 2034. Eighty moves reached 16 241 against the law's 15 726,
  where a linear tail would have reached 23 396, and RMS IMPROVED across
  the run.

Now put a blob on a rotation. **A rotation is a closed path**: the blob
at angle θ occupies, at θ + 2π, exactly the state it did before. So
after one revolution the model has seen every state on its own
trajectory, and MARL-9's cycling arm is what should happen — steep
growth through the first revolution, then $A/n$ per revolution
thereafter, logarithmic in total. A **translation on an open path** is
MARL-9's walking arm and should pay full price forever.

That prediction is not in the design note and it is the campaign's own
law applied to the design note's own first experiment. If it holds,
§39's hypothesis has its first evidence in dynamics. If population grows
linearly under a rotation, MARL-10's law does not survive contact with
transport, and that is the more interesting finding of the two.

### 3.4 §35's velocity field is exactly affine, so the experiment as written measures itself

This is the sharpest thing to say about the note and it changes the
first experiment.

For a rigid rotation $R$, the transported field $F(R^{-1}x)$ is
represented **exactly** by the transported parameters:

$$\mu' = R\mu, \qquad L' = \operatorname{chol}\!\left(R\,LL^{\mathsf T}R^{\mathsf T}\right), \qquad w' = w,$$

since $\phi(R^{-1}x) = \exp\!\left(-\tfrac12\lVert L^{\mathsf T}R^{-1}(x - R\mu)\rVert^2\right)$
and $L^{\mathsf T}R^{-1} = (RL)^{\mathsf T}$. Verified numerically over
4000 random kernels: worst $|F(x) - F'(Rx)|$ is **3.9e-15 in f64 and
2.4e-6 in f32** — the f32 figure is the Cholesky's rounding, so this is
exact but NOT bit-exact, unlike G31 (a)'s power-of-two scaling where
rounding a difference commutes with scaling by one.

It generalises. For any affine $x \mapsto Ax + b$,

$$\mu' = A\mu + b, \qquad L' = \operatorname{chol}\!\left(A^{-\mathsf T}LL^{\mathsf T}A^{-1}\right),$$

so **any affine warp is a closed-form operator on MARL requiring no
projection at all** — §34's `warp`, free. And the flow map of a *linear*
velocity field is a matrix exponential, which is affine. §35 proposes
$V = (-y, x)$, which is linear.

**So the note's first experiment has a closed-form exact answer that
bypasses the mechanism under test.** As a benchmark that is a gift — it
is the perfect control arm, zero error and zero population growth
forever, bounding everything the learned projection does. As the *only*
arm it would measure nothing, because a projection that merely
reproduced an affine map has demonstrated no more than that MARL can
represent a rotated blob, which G31 (a) already says.

ALG-1 therefore runs both: the affine operator as the control, and a
**non-affine** velocity field as the actual test.

### 3.5 The exact solution is available for any V, not just the rotation

§35 chose a rotation because "the exact solution is known". For a
passive scalar it always is:

$$F(x,t) = F_0\!\left(\Phi_{-t}(x)\right)$$

where $\Phi$ is the flow map of $V$. Integrating one characteristic
backwards with RK4 at small step from the *analytic* initial field gives
a reference to integrator precision for **any** smooth $V$, with no grid
anywhere in the measurement. So the choice of velocity field is free and
should be made on physics, not on tractability.

### 3.6 A velocity MARL is the field MARL is worst at (MARL-13 d)

MARL-13 (d): a learned sparse field beats a dense grid when the
interesting set is SPARSE IN THE DOMAIN, and loses when the field is
non-trivial everywhere. A rotational velocity field is non-zero
everywhere and grows linearly with radius — MARL-16's expensive object,
a plateau of non-zero value that a hard-cutoff basis must hold up
kernel by kernel.

The note conflates two things in one experiment. Separate them:

- **V analytic** — isolates the transport operator.
- **V as a MARL** — measures what the velocity's own fit error costs,
  which should enter as $\lvert\nabla F\rvert\,\Delta t\,\lvert\delta V\rvert$
  per step and accumulate.

Predict that arm (ii) is materially worse and that the gap is $\delta V$,
not the algebra.

### 3.7 Differentiation amplifies the hard cutoff by $\sqrt{32}/\sigma$ per order

A kernel is exactly zero beyond $r^2 = 32$ and $e^{-16} = 1.13\text{e-}7$
at the boundary, so the field has a 1e-7 step at every cutoff sphere —
which is why exact locality has always been free. **The derivatives do
not inherit that.** $\nabla\phi = -\phi\,Lv$ and
$\nabla^2\phi = \phi\left(\lVert Lv\rVert^2 - \operatorname{tr}LL^{\mathsf T}\right)$,
and at the cutoff $\lVert v\rVert = \sqrt{32}$:

| σ | value jump | ∇ jump | ∇² jump |
|---|---|---|---|
| 0.0442 (regions 4) | 1.13e-7 | 1.44e-5 | **1.67e-3** |
| 0.0295 (regions 6) | 1.13e-7 | 2.16e-5 | **3.75e-3** |
| 0.0147 (regions 12) | 1.13e-7 | 4.33e-5 | **1.51e-2** |

Each derivative multiplies the artefact by $\sqrt{32}/\sigma$. **The
Laplacian of a MARL rings at the 1e-3 level on every kernel's cutoff
sphere, four orders of magnitude above the value's step**, and it gets
worse as the basis gets finer.

Now compose that with MARL-13 (b): NLMS with step μ does not converge on
noisy data, it hovers at $\mu/(2-\mu)$ of the measurement variance
however much data arrives. **A diffusion loop generates its own noise
floor.** The cutoff ringing is not measurement noise — it is
deterministic — but it is spatially incoherent at the scale of the
kernel spacing, which is exactly what the projection cannot fit and the
descent will chase. §14's diffusion operator has a mechanism-level
reason to misbehave that no amount of data removes. It is ALG-4, and the
remedy if it bites is a smooth taper on the last fraction of the
support — which costs `rbf.zig`'s pin, so it is Christian's call and not
one to make casually.

### 3.8 Mass is closed form — conservation needs no quadrature (§13)

$\int \phi = (2\pi)^{3/2}/\det L$ with $\det L = l_{00}l_{11}l_{22}$,
which is $\exp$ of the sum of the log-diagonal — already in the parameter
vector. The hard cutoff throws away **5.23e-7** of it (measured, 3-D
gaussian beyond $\sqrt{32}\sigma$). So

$$M = \sum_i w_i \frac{(2\pi)^{3/2}}{\det L_i}\left(1 - 5.2\text{e-}7\right)$$

is **one multiply-add per kernel, exact to a part in two million**. §13's
"practical early implementation may simply measure the conserved quantity
before and after" is not merely practical — it is free, exact, and needs
no grid. The correction is one scalar multiply over all weights, and the
constrained projection of §13 is a single linear constraint on the
weights with a closed-form multiplier.

Momentum $\int FV$ is not closed form and needs quadrature. Mass first.

### 3.9 §21's per-region schedule is MARL-5's arm, and MARL-5 lost — at a ratio this experiment changes

MARL-5: five arms at one duty, and region scheduling lost to per-exemplar
bias. **A region is a sixth of the domain across and the structure was a
fortieth of it thick, so a region-level schedule is coarser than its own
signal.** §21 proposes exactly a per-region update schedule.

But read the mechanism, not the verdict. MARL-5's refutation was about
the ratio of signal scale to region scale. Here the deciding signal is
$\lvert V\cdot\nabla F\rvert$, and $V$ is smooth at domain scale — a
region may well be *finer* than that signal rather than coarser. **§21 is
worth running precisely because it changes the ratio MARL-5 measured.**
What must not be repeated is testing it at region granularity only:
MARL-5's winning arm was per-exemplar, and here the exemplar is one
projection point. ALG-6 runs both.

### 3.10 The leading edge is invisible from the kernel centres (§12)

§11 and §35 project at the current kernel centres. A transported blob
moves into regions where there are **no kernels**, so there is no
projection point there, so nothing observes that the field has arrived —
and the model can only erode. §12 lists candidate projection points and
does not name this one.

The fix falls straight out of the semi-Lagrangian form: the mass is
going to $x_i + \Delta t\,V(x_i)$, so project on the **forward-advected**
centres as well as the current ones. Births then fire on coverage where
the field is arriving, which is MARL's existing mechanism doing exactly
its job. Pre-registered as part of ALG-1; the ablation (current centres
only) should show monotone decay of the blob.

### 3.11 The denominator, twice bitten (MARL-20, MARL-21)

A blob of width 0.08 in the unit cube has a global anchor RMS of
**0.0528** and a local one — probes in a ball of $3\sigma$ about the
blob — of **0.1758**. Two thirds of any global probe set sees nothing at
all. MARL-20 was diluted by a global probe set and fixed it with a local
one; MARL-21 was then diluted *again inside the local region*, because a
residual's support and its magnitude have different geometries.

    The affected ball is the SUPPORT, not the SCALE.

Every ALG number is reported on probes drawn where the field is, with the
global set printed beside it so the dilution is visible rather than
chosen — and stratified by distance from the blob where a mean would hide
a gradient.

### 3.12 The anchor (MARL-17, MARL-22)

Every RMS beside what a constant predictor scores on the same query set.
MARL-22 exists because a gate pre-registered a threshold that ignored the
number it was already printing.

------------------------------------------------------------------------

## 4. Phase plan

Each phase is one gate with its numbers written before it runs, a
predictor in `tools/`, and a ledger entry naming the mutation that paid
for the gate.

### ALG-1 — does one MARL move another? (G44)

The design note's §35 and §36, with §3.4's correction. A gaussian blob on
the unit cube, four arms at matched capacity:

| arm | velocity | transport | what it isolates |
|---|---|---|---|
| **E** | rotation (linear) | the exact affine operator, no projection | the representation's ceiling |
| **A** | rotation (linear) | semi-Lagrangian + projection | the projection against a known exact answer |
| **B** | non-affine swirl | semi-Lagrangian + projection | the actual question |
| **C** | non-affine swirl, **V as a MARL** | semi-Lagrangian + projection | what the velocity's own fit error costs |

Reference: $F_0(\Phi_{-t}(x))$ by RK4 backtrace from the analytic initial
field (§3.5). Measured per step: RMS against the reference, anchored;
population; mass by §3.8's closed form; projection points evaluated;
wall clock.

### ALG-2 — deferred projection: §19 as the remedy rather than the optimisation

**Rewritten after ALG-1.** The original plan was to run arm B deep and
measure whether generation loss compounds. G44 (c) and (d) answered that
without needing depth: it compounds, and refining the timestep makes it
worse, because the cost is paid per projection.

So the question becomes the one that answer points at. Compose the flow
map and project only when the local-affine push-forward stops being
enough:

    F_t = P[ F_0 . Phi_-t ]   materialised every k steps, k >> 1

with `pushKernel` carrying the affine part exactly and for nothing (G44 g)
and the projection correcting only what the per-kernel Jacobian misses —
which is second order in the kernel's width times the flow's curvature.
Sweep k. The claim is that there is an interior optimum: too small and
generation loss dominates, too large and the second-order term does.

This is MARL-20's static-plus-residual architecture in TIME rather than in
space, and it should be the same trade priced there — memory, build time
and update cost, never accuracy.

**First diagnostic toward ALG-2 (G44 k, 2026-09-09).** Christian asked
whether the errors came from the original MARL representation. Hold the
initial fit immutable and separate its transported fit error from the
local-affine transport error. On identical final swirl probes:

| read / representation | RMS | / constant | kernels |
|---|---:|---:|---:|
| Original MARL at backtraced coordinates | 0.008781 | 0.049 | 125 |
| Forty local-affine pushes | 0.073649 | 0.413 | 125 |
| One fresh fit to transported samples of the original MARL | 0.023059 | 0.129 | 267 |

The direct RMS between the pushed model and the backtraced initial model
is 0.071951. Changing the backtrace from 40 to 640 steps changes field
values by only 8.547e-6 RMS here. The dominant added error is therefore in
the local-affine transport approximation on this fixture, rather than the
initial fit or the backtrace resolution. These components are not added
as RMS values; they are measured independently on the same probes.

The one-time materialisation uses 60 000 exemplars (the original fit's
budget), takes 0.875 s in this ReleaseSafe run, and receives values from
the **original learned model**, never the analytic truth. Training points
are sampled in the original four-width ball and advected with 40 RK4
steps. This particular flow preserves volume, so transporting these
samples also transports their measure. The comparison of one-time fit
against pushed RMS was proposed in `ALG1_PULLBACK_MARGIN = 1` before the
run. No default is changed. The diagnostic has its own probe stream, so
its absolute RMS values differ from G44 (g)'s historical values.

This buys roughly 3.2× lower error for 2.1× the kernel count and one fitting
pass. Keeping the backtraced reader buys still lower error but moves flow
integration into every query; it is not a free fast cache. It establishes
a useful control and a concrete deferred-materialisation opportunity,
not yet an interior-optimum result for the k sweep. The next phase must
price read cost, fit cost and representation bytes together.

A separate opportunity in the original representation is the coupling of
basis width to indexing. At regions 4, the one-edge support cap permits
an isotropic width of only `(1/4)/sqrt(32) ≈ 0.0442`; this blob has width
0.08 and is itself a Gaussian. Its 125-kernel initial fit therefore is
not evidence that the field intrinsically needs 125 Gaussian components.
A support-aware index could admit broad kernels alongside narrow ones.
This is a proposed core-MARL experiment, not a measured improvement:
broader kernels also broaden support and alter learning responsibility,
so locality, conditioning, convergence and actual query work must all be
measured. The current O(K) fallback supplies a correctness reference,
not that acceleration structure.

### ALG-3 — is a rotation a cycle? (§3.3)

Population against revolutions, closed path against open. MARL-10's law
fitted — $K_0 + A\,H(N)$ — against a linear tail. The claim under test is
§39's, and this is the cheapest decisive form of it.

The open arm needs designing rather than assuming: **a translation with
re-injection is still a closed path**, and so is any steady 2-D
divergence-free flow, whose streamlines are level sets of its
streamfunction. What makes a path genuinely open is a velocity field that
is not steady — a swirl whose centre itself drifts, so the blob's
trajectory never repeats. That is MARL-9's walking arm and should pay
full price forever.

### ALG-4 — the derivatives, and what the cutoff does to them (§3.7)

∇ and ∇² against central differences and against the analytic truth on a
field of known kernels; the discontinuity at the cutoff sphere measured
directly; and a diffusion loop run long enough to say whether the ringing
becomes a floor. If it does, the taper is priced and put to Christian.

### ALG-5 — conservation (§13, §3.8)

Mass drift per projection step, the closed form checked against
quadrature once, and the one-multiply global correction measured against
doing nothing. §38's instruction — *do not solve conservation
prematurely; first establish how serious the problem actually is* — is
the right one and is followed.

### ALG-6 — where does the work go? (§39, §3.9)

Four arms as §39 lists them, at **projection-point** granularity and at
**region** granularity, so that MARL-5's verdict is re-tested at the
ratio this problem actually has rather than assumed either way. Error
against work. This is the phase that decides whether
$\text{cost}\propto\text{information change}$ is a property or a hope.

------------------------------------------------------------------------

## 5. ALG-1's pre-registration

Written before the code, from theory where there is any.
`tools/alg1_predict.py` holds the derivations and the frozen table; the
thresholds go into `src/thresholds.zig` as PROPOSED for Christian to
strike.

Run `python3 tools/alg1_predict.py` for the derivations. The frozen
table, in the order the gate will print it:

| # | quantity | predicted | from |
|---|---|---|---|
| a | arm E population after one revolution | **exactly unchanged** | §3.4, an equality not a threshold |
| b | arm E RMS against the analytic reference | ≤ 1.0e-4 | 2.4e-6 per step × √40, ×6 margin |
| c | closed-form mass vs dense quadrature | ≤ 1e-5 relative | §3.8, the cutoff loses 5.23e-7 |
| d | arm B RMS / anchor, one revolution, local probes | ≤ 0.25 | a constant scores 1.00 |
| e | arm B population | ≥ 1.5 × arm E's | the projection buys capacity the closed form does not |
| f | \|mass drift\| over one revolution | < 20%, one-signed in ≥ 80% of steps | the θ dead zone holds 4.98% of the blob |
| g | arm A ΔK(2)/ΔK(1) | ≤ 0.60 | MARL-10's law says 0.50 |
| h | arm A ΔK(4)/ΔK(1) | ≤ 0.35 | MARL-10's law says 0.25 |
| i | arm C excess RMS over arm B | T·\|δV\|·3.392, within 2× | error propagation, no free parameter |
| j | ablation (no forward set): mass | ≤ 0.50 × its start | §3.10 — this is the gate's mutation |
| k | ablation: centroid displacement | ≤ 0.20 × the reference's arc | §3.10 |

Two things are deliberately NOT predicted, and saying so now is the point
of saying it now:

- **The sign of the mass drift.** The arriving tail is never learned
  (loss) and the departing tail is never unlearned (gain); which
  dominates is the measurement.
- **Arm B's population growth rate.** Its swirl is a Taylor–Green cell,
  whose streamlines are closed but whose angular velocity is not
  uniform — so the blob SHEARS and never exactly recurs. Only the
  ordering is registered: arm B grows faster than arm A and slower than
  linear.

------------------------------------------------------------------------

## 5a. ALG-1, measured (G44, 53 s)

Run Wednesday 9 September 2026. Seven parts, `src/field.zig`, thresholds
in `src/thresholds.zig` as `ALG1_*`. The pre-registration is
`tools/alg1_predict.py`, frozen before the Zig was written, with one
correction recorded in it (§10) and made before the gate ran.

### The scorecard

Original ALG-1 run; the G44 (h–j) follow-up below corrects the velocity
observable and interpretation without rewriting the pre-registration.

| # | quantity | predicted | measured | |
|---|---|---|---|---|
| a | arm E population | exactly unchanged | 125 → 125 | **HELD** |
| b | arm E departure from its own start | ≤ 1.0e-4 | **7.7e-7** | **HELD**, 130× |
| c | closed-form mass vs quadrature | ≤ 1e-5 | **1.26e-7** | **HELD** |
| d | arm B RMS / anchor | ≤ 0.25 | **1.54** | **REFUTED** |
| e | arm B population ≥ 1.5 × arm E | ≥ 1.5× | 7.2× | held, for the wrong reason |
| f | mass drift, one-signed | < 20%, one-signed | 71%, alternating | **REFUTED, both** |
| g,h | ΔK ratios over four revolutions | ≤ 0.60, ≤ 0.35 | — | **not measurable** |
| i | arm C excess = T·\|δV\|·3.392 | within 2× | **0.008×** | **REFUTED, 125×** |
| j | ablation: mass | ≤ 0.50 × start | **0.051** | **HELD** |
| k | ablation: centroid | ≤ 0.20 × arc | 0.89 × arc | **REFUTED** |

Four refutations, three holds, one unmeasurable. The refutations are the
phase.

### The operators are cheap and the mass is free (G44 a)

§5's claim is correct: a derivative is field evaluation plus a little
arithmetic. `mahal` already computes v = Lᵀd, and ∇φ = −φ·Lv is six more
multiplies. Checked against central differences (gradient 5.07e-4
relative) and, for the Laplacian, against its closed form on an isotropic
kernel — **7.33e-7, which is f32 and nothing else.** Mass agrees with a
64³ quadrature to **1.26e-7 relative**, below the cutoff's own 5.23e-7
truncation, so §13's conserved quantity is one multiply-add per kernel
with no grid anywhere.

*Method note.* The Laplacian check first read 7.1e-2 and the formula was
already right: a central SECOND difference carries roundoff ε|f|/h², so at
the gradient's step of 1e-3 in f32 the reference was uncertain by 0.1 —
worse than the thing it was refereeing. The mutation (∇ taken through Lᵀ
instead of L, both being to hand in `mahal`) moves the gradient by 181%,
and it still points outward and still vanishes at the centre, which is why
a picture of it would have looked right.

### A rotation of a MARL is exact, and free (G44 b)

125 kernels fit the blob at **0.058× a constant**. Forty composed
rotations: **125 kernels, unchanged; departure 7.7e-7 at the closed loop
and 3.1e-7 at a quarter turn read at the pre-image; mass drift 2.0e-6.**
The affine subgroup acts on the parameters in closed form and §34's `warp`
is real.

**And the reach bound is not rotation-invariant.** A kernel's cutoff BOX
grows when its ellipsoid turns off-axis, and the gather's exactness rests
on that box fitting inside one region edge: worst **1.0222**, with kernels
over the bound on most steps. Counted, never corrected — correcting it
would change the field, which is this operator's whole claim. It is
a query-correctness issue even if a particular missed tail is small.
The earlier claim that every missed contribution is bounded by w·e⁻¹⁶
was incorrect: that is the value AT the cutoff, not an upper bound on
support omitted by a too-small gather.

**Follow-up:** rebuilding or copying a model now detects support outside
the learner's gather contract. Such models use an ordered full gather,
without changing kernel geometry. G44 (i) rotates an initially admissible
kernel so its support reaches two owner cells away; the old gather returns
zero and the corrected query agrees with the full sum bit for bit. This
is a correctness fallback, with O(K) kernel work per query. A support-aware
index remains an optimisation to earn before claiming fast transported
queries. A fixed 5³ stencil is not sufficient for arbitrary deformation.

### The headline is refuted, and the control says which half (G44 c)

    arm                  step  kernels      RMS   /const     mass   width
    A rotation              0      125  0.01009    0.058    1.000  0.0795
    A rotation             40     1006  0.17947    1.015    0.607  0.0609
    B swirl                40      894  0.28349    1.543    0.294  0.0505
    O rotation, ORACLE     40      369  0.01227    0.069    1.032  0.0807

**The field decays to a constant in one revolution — and the oracle,
running the identical loop on the identical points with the exact solution
as its target, ends where the fit began.**

    The representation holds a transported field.
    The LOOP cannot find it.

The loop's own cost is **14.6×**. And it is not the numerical diffusion a
semi-Lagrangian scheme is famous for: **the blob's width is flat
throughout** (0.0795 → 0.0609 — it gets *narrower*) while the population
multiplies eight-fold. Nothing is smearing; capacity is accumulating that
nobody can train, which is MARL-1's invariant in its seventh sighting.

### The timestep cannot save it (G44 d)

    steps   arc/sigma   kernels      RMS   /const
       10       3.554       444  0.12489    0.721
       20       1.777       513  0.12621    0.728
       40       0.889      1006  0.17355    1.001
       80       0.444      1447  0.31235    1.802

**Eight times the steps is 2.50× the error for 8× the work.** Every
classical scheme's first defence is unavailable here, and the reason is
structural rather than incidental:

    the cost is paid per PROJECTION, not per unit time

so refining Δt buys truncation accuracy that was never the binding term
and pays generation loss that is. The design rule that follows is the
inverse of the usual one: **there is an optimal Δt and it is the largest
the transport scheme tolerates.** Which is the real reason §11 was right
to name semi-Lagrangian first — its value is not accuracy, it is that
being unconditionally stable lets the step be large enough to project
rarely.

### It is a conditioning problem, and MARL-23 already named it (G44 e)

Freeze the topology and the geometry and one step is a linear recursion
on the weights, `w′ = Φ(P)⁺Φ(P−δ)w`, and iterating it is a power method.
MARL-23 measured — with no learner and unlimited evidence — that **a
Gaussian basis much finer than the feature is nearly linearly dependent**.
That makes Φ(P)⁺ ill-conditioned, and the amplification is raised to the
number of steps:

    regions  sigma_max  pinned   RMS frozen    RMS adaptive
          2     0.0884     95%      1.919e0          0.2551
          3     0.0589     97%      5.210e1          0.1514
          4     0.0442     98%      8.122e8          0.1735
          6     0.0295     97%      6.320e9          0.2729

In a static fit near-dependence costs accuracy. **In a loop it costs
stability.** And the second column is the surprise:

    MARL's adaptivity is what stops it exploding.

With births and the geometry descent switched on, the same recursion stays
bounded at every fineness — 1e9 becomes 0.27. Every earlier sighting of
MARL-1's invariant had capacity acquisition as the thing that needed
restraining. Here it is the stabiliser.

### The leading edge, refuted usefully (G44 f)

Predicted: with no forward projection set the blob stays where it is and
shrinks. **The mass HELD spectacularly — 0.051, five per cent left — and
the centroid REFUTED: it moved 0.89 of the reference arc anyway.**

The model transported itself. **The geometry descent was doing Lagrangian
advection on its own**, badly and for free: each kernel's centre chases a
one-sided residual and drifts along the flow. That is where the phase's
last part came from, and it came sideways.

### The operator the phase ends on (G44 g)

A kernel is small, so the flow is affine across it, so G44 (b)'s closed
form applies **locally, per kernel, with the flow map's own Jacobian**:

$$\mu' = \Phi_{\Delta t}(\mu), \qquad L' = J^{-\mathsf T}L, \qquad w' = w.$$

No learning, no evidence, no births, **no projection at all**.

    arm                     kernels      RMS   /const    mass     sec
    push forward, rotation      125  0.00987    0.060   0.999    0.00
    push forward, swirl         125  0.07788    0.431   0.999    0.00
    projected loop, swirl       894  0.25749    1.431   0.294    2.97

Exact for the affine flow, as it must be. On the flow that is not affine
it is **3.3× better at an eighth of the population and roughly a thousandth
of the time**, and its residual error is second order (the kernel's width
× the flow's curvature) where the loop's is first order in the number of
projections.

The weight does not change, which is the passive-scalar convention: F is
constant along characteristics. A **density** wants `w / det J`; a
divergence-free flow has det J = 1 so the two agree here and the choice is
invisible, which is exactly why it is written down.

### Learned velocity: the original result and its measurement correction (G44 h–j)

The original velocity fit had 2 524 kernels and |δV| = 0.0159. Its
pre-registered estimate was `T·|δV|·RMS|∇F|` = 0.338. The original
measurements, retained as history, were:

    steps  exact V  learned V   RMS difference
       10  0.01829    0.02650     0.00821
       40  0.07394    0.07037    -0.00357

These refuted the estimate as applied to this observable. They did **not**
establish the initially claimed law, “velocity error is paid per net
circulation”. The arms used different probes, and a difference between
errors against truth can be small because velocity error compensates for
fit or transport error. It is not the RMS distance between the fields.
Also, `steps_per_rev` defines the rigid rotation's period; the Taylor–Green
swirl has streamline-dependent periods and the experiment did not establish
closure at that horizon.

G44 (h) now uses common probes and reports the direct field-to-field RMS
as well as both errors against truth and reference-centre departure from
its starting point. The comparison of signed RMS differences is no longer
asserted as a cancellation mechanism. G44 (j) gives an analytic
counterexample to the general claim: a 1% angular-rate bias produces more
trajectory error after a complete reference revolution than after a
quarter, despite perfectly closed reference streamlines.

For a small velocity perturbation, trajectory error obeys
`dδx/dt = ∇V(x(t)) δx + δV(x(t))` to first order. Its accumulated effect
includes the flow's deformation of earlier perturbations; neither a
scalar circulation integral nor velocity RMS alone determines it.
Cancellation in particular learned flows remains possible, but requires
a direct characteristic/field comparison to establish.

**Corrected measurement (ReleaseSafe, common probes, full support):**

| steps | exact V RMS | learned V RMS | difference | direct field RMS | reference centre departure |
|---|---:|---:|---:|---:|---:|
| 10 | 0.01830 | 0.02756 | 0.00927 | 0.020783 | 0.335926 |
| 40 | 0.07813 | 0.07866 | 0.00053 | 0.064921 | 0.096610 |

Direct disagreement grows by about 3.1× while the difference of truth
errors nearly vanishes. The full-horizon centre is still 0.09661 from its
start (the blob's initial width is 0.08). This fixture therefore does not
support the claimed cancellation-on-closure mechanism. The analytic
rate-bias control has displacements 0.003927 and 0.015705 at the quarter
and full reference revolution respectively.

The full-support correction preserves G44 (g)'s main comparison:
rotation push-forward 0.060× a constant; swirl push-forward **0.432×**
versus projected **1.431×**, with **125 versus 894 kernels**. Historical
scorecard values above remain the original run, not silently replaced.

### What ALG-1 says to the design note

1. **§5 and §13 are better than claimed.** The derivatives are cheap and
   the conserved quantity is closed form.
2. **§34's `warp` is exact on the affine subgroup and costs nothing** —
   and §35's proposed first experiment lies inside it, so as written it
   would have measured itself.
3. **§8 and §11's projected loop does not work**, and the reason is
   neither the basis nor the scheme but that the field is its own source.
4. **§19's lazy expression graph is not an optimisation, it is the
   remedy.** Every materialisation is a generation of loss, so the algebra
   should project as rarely as it can — not once per timestep. That is the
   single most important consequence of this phase and it is ALG-2.
5. **§12 needs a correction.** Its list of projection points leads with
   kernel centres, and sampling only there gives K equations for K·(9+C)
   parameters: the fit is underdetermined between them and the field
   collapses (peak 1.03 → 0.056 in ten steps, then divergence). The
   natural radius is MARL's own — a kernel's coverage ellipsoid, inside
   which it IS the covering one — and the union of those tiles the
   support with a density that follows the model's own capacity, which is
   §12's principle stated properly.
6. **§21 is still open and MARL-5 is still the thing to beat.**

### Method notes the phase paid for

- **A harness constant in the wrong unit.** `jitter` was written against
  a kernel's `reach` (the cutoff box, 5.66 widths) when it meant widths,
  so a nominal 0.25 was 1.41 — past the 1.45-width coverage radius, and
  births fired by construction. The population then feeds back on itself,
  because the projection points ARE the kernel centres. `cache.zig`'s
  `mo.m = o.m` all over again.
- **Freezing before the fit rather than after it** left an empty model and
  a tidy-looking RMS that was the anchor. `Freeze` is applied after.
- **A second difference is not a first difference.** See G44 (a).

------------------------------------------------------------------------

## 5b. Support width and selective transport (G45–G46, 2026-09-09)

Christian suggested that MARL might select different advection methods or
representations locally, while keeping the first implementation simple.
Two investigations ask which additional choices the measurements justify.
Predictions are recorded in `tools/width_predict.py` and `thresholds.zig`.

### G45 — separate support width from the ownership grid

`marl.Options.support_edges` is an explicit, opt-in limit on support
half-extent in region edges. It defaults to **1**, preserving the original
27-region gather. A wider setting expands the query stencil, maximum
permitted width and default newborn width together. Centre trust, minimum
width, region ownership, budgets and the Gaussian evaluator stay as they
were. Per-region reach pruning remains conservative. Kernels deformed
beyond the selected support limit still select the full-gather fallback.

G45 (a) checks the enlarged stencil against the full ordered sum bit for
bit over anisotropic kernels, support settings 1/2/4, ownership grids
4/6/8, and in/out-of-cube queries. Its mutation reduces only the gather radius and misses a live
second-ring contribution. The learner's kernel math and cross-repo pin
are unchanged.

The blob sweep uses regions=4, 60k identical exemplars per arm and seeds
7/19/41. Approximate averages of the printed per-seed measurements:

| support edges | newborn width | kernels | initial RMS / constant | pushed RMS / constant |
|---|---|---:|---:|---:|
| 1 | historical | 115.7 | 0.0604 | 0.3936 |
| 2 | historical, may widen by descent | 91.0 | 0.0465 | 0.4559 |
| 2 | twice historical | 34.0 | 0.0454 | 0.6977 |
| 4 | four times historical | 13.0 | 0.0408 | 0.7511 |

For doubled support and broad births, mean population is **0.2939×** the
baseline and mean raw RMS **0.7511×**: both pre-registered comparisons
held. Mean candidate kernels per local query fall from about 114 to 34,
while actual support grows from roughly half to almost all candidates.
These are kernel-work counts, not a full query latency benchmark; wider
stencils examine more ownership cells. The half-width birth control
shows that merely permitting later widening buys less than broad births.

Broader kernels fit this smooth field better and transport it worse with
the local-affine approximation. The representation and evolution operator
have different preferred scales.

**Sharp-feature control, exploratory:** the existing synthetic target,
two shells at sharpness=2, 200k exemplars, seeds 7/19, same regions and
rates. Averaged results (constant RMS 0.15062):

| support edges | kernels | RMS / constant | candidates / query |
|---|---:|---:|---:|
| 1 | 1611 | 0.5280 | 444.7 |
| 2 | 443.5 | 0.6189 | 320.6 |
| 4 | 160 | 0.7024 | 160.0 |

Here width is a trade: doubled support saves about 72% of the kernels for
17% more error. Wider support is not made the default. This control does
not isolate a representational floor from convergence at this evidence
budget; it establishes that the blob's accuracy improvement is not a
general result.

### G46 — does local error justify choosing an evaluator?

The 13-kernel, widest-support blob fits are the adverse transport case.
For each source kernel, 32 independent calibration points within two
widths are carried forward through the swirl. Its original value is
compared with its pushed Gaussian's value there, weighted by the kernel's
coefficient. This local discrepancy ranks which contributions to read
through a backtrace. Whole kernel contributions choose one evaluator;
there is no discontinuous switch at a region face.

Independent final probes compare this ranking against eight uniformly
random subsets at equal selected counts. The target for this comparison
is **exact transport of the original fitted model**, so compensation
against the analytic blob does not masquerade as transport accuracy.
At 6 of 13 kernels corrected, mean selected/random RMS is **0.0361**.
The proposed ordering holds. Correcting 3 of 13 reduces direct transport
RMS from roughly 0.13 to 0.0042–0.0066 across the three seeds.

**The simpler control changes the interpretation:** ranking by absolute
weight alone gives virtually the same result: at half corrected,
local-error/weight-only RMS is **0.9956**. This control was added after
the first result and had no pre-registered advantage claim. The fixture
has important broad contributions and small corrections; identifying
importance is enough here. It does not yet earn calibration probes or
a learned method selector. A future paying fixture must separate weight
from local transport difficulty, for example equally important components
in near-affine and strongly deforming parts of a flow.

**Cost is not hidden:** the diagnostic precomputes terms to isolate the
accuracy question. Any backtraced contribution requires a shared
backtrace at that query, so this is not a demonstrated runtime saving.
To turn selection into speed, query scheduling needs conservative bounds
on where the backtraced contributions can matter, or amortised/local flow
maps. That is separate work, triggered by an accuracy signal that beats
the cheap importance baseline on a heterogeneous fixture. No production
scheduler, node variants or default changes were introduced.

------------------------------------------------------------------------

## 5c. ALG-2 — deferred materialisation through the whole trajectory (G47)

**Pre-registration:** `tools/alg2_predict.py`, written before the sweep.
The 40-step swirl, seeds 7/19/41, historical support width, 60k exemplars
for the common initial fit, and **240k exemplars total** for subsequent
materialisations. Intervals are 1/2/5/10/20/40; each interval divides the
horizon. Every fit starts a fresh model and learns from the previous
immutable checkpoint, never the pushed approximation and never analytic
target values. All arms consume the same exemplar stream but place those
examples at their own checkpoint times.

`src/deferred.zig` separates two reads between checkpoints:

- A cheap model pushed by local flow Jacobians.
- A `Pullback` read that backtraces into the last checkpoint. Its model
  must remain alive and unchanged; the current MARL reader still owns
  mutable scratch, so this is a serial surface, not snapshot publication.

At a checkpoint both represent the newly materialised model. The first
run caught an actual copy discrepancy here: `reseedFrom` preserves kernel
parameters but rebuilds per-region lists in kernel-index order. Learning
can rehome kernels into another order. G47's checkpoint copy preserves
the original summation order too; a two-ULP mismatch then disappears and
zero-pending-flow readings agree bitwise. The core reseeding contract is
unchanged.

**Measurement:** 128 common local probes at every published frame, not
just the final fit; average per-frame RMS divided by that frame's
constant-predictor RMS. Direct errors against the accurately transported
original model are also recorded, separating original fit error from
later evolution error. Final uniform whole-cube RMS and whole-space
kernel mass are reported separately. RK4 query-step counts expose the
pullback's read cost. Fit time includes transporting training locations;
reported total time also includes diagnostic probe scoring, so it is not
a runtime-only benchmark. Peak live kernel count includes old checkpoint,
cheap view, student and its new cheap copy, not merely the final payload.

**Equal-total-evidence results**, means over three seeds:

| interval | fits | exemplars / fit | cheap mean / constant | pullback mean / constant | final / constant |
|---|---:|---:|---:|---:|---:|
| 1 | 40 | 6 000 | 0.4794 | 0.4794 | 0.6975 |
| 2 | 20 | 12 000 | 0.2438 | 0.2434 | 0.4446 |
| 5 | 8 | 30 000 | 0.1341 | 0.1316 | 0.2572 |
| 10 | 4 | 60 000 | **0.0989** | 0.0885 | 0.1508 |
| 20 | 2 | 120 000 | 0.1097 | 0.0657 | 0.1196 |
| 40 | 1 | 240 000 | 0.1960 | **0.0524** | **0.0777** |

The proposed interior optimum holds, with interval 10 best at each seed.
Its mean cheap-view error is about half the best endpoint's, and about
one fifth of fitting every step. The final-only measurement would have
selected interval 40, which is why intermediate frames are part of the
gate. The other prediction holds too: final k40/k1 error is 0.1114.

Accurate reads are a different trade: they benefit from fewer fits and
pay for longer backtraces. Mean pending RK4 steps per read are
0/0.5/2/4.5/9.5/19.5 for these intervals. Both accurate and cheap views
remain queryable between materialisations; the approximate view is not
fed back as a teacher.

**Pre-planned training-budget control, G47 (b).** Give every fit 60k
examples, matching the initial fit, with intervals 1/10/40. This deliberately
uses unequal total evidence:

| interval | total exemplars | cheap mean / constant | final / constant | mean fitting seconds |
|---|---:|---:|---:|---:|
| 1 | 2 400 000 | 0.2278 | 0.4031 | 31.46 |
| 10 | 240 000 | 0.0989 | 0.1508 | 2.78 |
| 40 | 60 000 | 0.1970 | 0.1177 | 0.86 |

Extra evidence roughly halves the every-step error, so undertraining each
fresh fit explains part of the primary result. It does not erase it:
every-step fitting still loses to interval 10 on both mean and final
error while consuming ten times its examples. Repeated materialisation
remains costly for this learner and fixture; this is not a theorem about
all projection methods. Timings include fitting and sample transport.

G47 (a) checks actual observed exemplar counts and bitwise checkpoint
agreement. G47 (c) checks a quarter-turn pullback of a known Gaussian,
including an omitted-backtrace mutation that returns zero at the same
query, and zero-step identity. All three targeted ReleaseSafe gates passed.

No global default is changed and ten is not a universal cadence. This
is one smooth, time-independent, incompressible fixture and a declared
sampling measure (the advected initial four-width ball). Checkpoint
training remains synchronous. Long-horizon stability, general support
discovery and explicit conservation remain separate questions; for
example interval 10 retains 0.892/0.963/0.778 of initial whole-space
kernel mass at the three seeds.

------------------------------------------------------------------------

## 6. What would refute the campaign

Stated now, so that it cannot be softened later:

1. **Population grows linearly under a closed-path flow.** MARL-9 and
   MARL-10's law would not survive transport, and §39's hypothesis
   fails at its first test.
2. **Generation loss compounds** at anything near MARL-19's 1.18×.
   Repeated evolution is then unstable by construction and the algebra
   is a one-shot warp operator, not a dynamics.
3. **The non-affine arm is no better than a same-memory grid** stepped
   by the same scheme. MARL-13 (d)'s rule already says which way this
   should go for a *sparse* field; a blob is sparse, so losing here
   would be a real surprise and would point at the projection.
4. **The affine control and the learned arm land in the same place at
   the same cost.** Then the projection has learned nothing the closed
   form did not already give, and the interesting operator is `warp`.

Number 4 is the one to watch: it is the pleasant-looking result that
would mean the least.

**After ALG-1.** (2) happened — generation loss compounds, and worse, it
cannot be refined away (G44 d). (1) and (3) are unmeasured: a loop that
reaches the anchor in one revolution cannot be asked about four
revolutions or set against a grid, so both move to ALG-3 behind ALG-2's
deferred projection. (4) did not happen, and its inverse did: the
closed-form operator BEAT the projected loop by 3.3x at an eighth of the
population (G44 g). So the interesting operator is `warp` after all —
applied locally, per kernel, which is not what the note or this lab book
had in mind when that sentence was written.

------------------------------------------------------------------------

## 7. Recorded, not built

With triggers, per house style.

- **Operator fusion (§20) and the expression graph as an IR (§19).**
  Not until two operators are measured separately. The trigger is ALG-4
  showing advection and diffusion both working; fusing before that
  optimises something unproven.
- **Momentum and higher invariants (§13).** Trigger: ALG-5 finding mass
  drift material enough that a global correction is not sufficient.
- **The multiscale pressure solve (§27).** Genuinely attractive and
  genuinely a research project. Trigger: ALG-1 through ALG-3 all
  holding, and not before — a Poisson solve on a representation whose
  transport is unproven is an expensive way to learn about transport.
- **The smooth taper on the cutoff's last fraction (§3.7).** Costs the
  `rbf.zig` pin and therefore rill and the shader. Trigger: ALG-4
  measuring the ringing as a floor rather than a curiosity, with the
  cost of the pin priced beside it.
- **Higher-dimensional MARLs and spacetime fields (§33).** No trigger
  yet. The 3-D domain is not the constraint anything currently fails on.
- **Coupled systems — fire, weather, morphogenesis (§26, §29, §30).**
  These are what the algebra is FOR, and every one of them is an
  application of ALG-1 through ALG-6 rather than a test of them. The
  trigger is §40's six criteria, all six.

------------------------------------------------------------------------

## 8. Method rules inherited

Unchanged from the MARL campaign, restated because a new lab book is
exactly where they get quietly dropped:

- **Thresholds are Christian's.** Written BEFORE the run, from theory
  where there is any, in a second program frozen beside the gate. Do not
  tune a threshold to make a gate pass; change the code, or record the
  finding and ask.
- **A gate that cannot fail is decoration.** Every gate names its
  mutation, executable where cheap.
- **The anchor.** Every RMS beside what a constant predictor scores on
  the same query set.
- **The denominator.** Probes where the field is, the global set printed
  beside them, stratified where a mean would hide a gradient.
- **Hyperparameters must not spill.** `field.Options.best()`, each
  element naming its phase. A gate written before a finding keeps its
  own literals and is historical on purpose.
- **Quantization is not a measurement.** A headline is the f32 master
  against its opponent; the packed artefact is reported separately and
  labelled.
- **Docs ride the same commit as the code they describe.**
