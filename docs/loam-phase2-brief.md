# Loam — Phase 2 brief: the continuous carrier

Companion to `loam-phase1-brief.md`, `representation.md` (Astra,
2026-09-06) and the conversation that produced it (Christian, Claude Chat,
Claude Code, the same day). The brief says what P2.1 builds, how we will
know, and what it does not build. Where it disagrees with the chat, the
brief wins; where a ruling is Christian's, it says so.

## 0. The change, in one sentence

Yesterday Loam grew matter. Now Loam grows a continuous implicit function
whose zero set is matter, and everything perceived as bark, scars, grain
and age is structured history around that carrier.

## 1. Rulings asked (Christian's to strike before P2.1)

Status, Sunday 2026-09-06: **R7 STRUCK** and **G13 STRUCK** by Christian
("Strike both. Dig."), with the ruling he drew from the number — a
structural feature of radius r belongs at a gauge with h ≤ r/2; below
that the feature belongs at a finer gauge, not at a prefilter. P2.1 is
built (the ledger, "P2.1 — the carrier"); R8–R14 stand, accepted as
proposed the same day ("I'd let them stand").

**R7 — Reconstruction: a scalar halo and a cubic B-spline.** Every
channel stays one plane; a brick stores an 11³ block — its 9³ samples and
one halo sample beyond each face, copied from the neighbours at commit by
the anchor rule taken one layer deeper. Reconstruction is a uniform cubic
B-spline over the 11³ block: C2 inside a brick and across a same-gauge
seam, because both sides reconstruct from the same 64 samples. Rejected:
stored value + gradient with Hermite (a second truth the seam contract
must also anchor; 4× the carrier's memory against 1.8×). Claude Code
proposed, Astra concurred; the fetch count (64 against 32) is measured in
P2.1 and recorded. **B-spline samples are control values, not points the
zero set passes through** — documented at the channel, and refine/coarsen
(D2) is defined on the reconstructed function, never by resampling
values.

**R8 — Band 0 is a signed implicit carrier with a Lipschitz bound, not a
distance.** φ = 0 is the surface, φ < 0 inside. After smooth union,
displacement and reconstruction it is a bound; what a renderer needs is
continuity and |φ(x) − φ(y)| ≤ L‖x − y‖, and `Summary.max_gradient` is L
— derived conservatively from the B-spline coefficients, not measured by
finite difference. A safe step is |φ|/L. The channel is `surface`
(rejected: `distance`, which promises what it is not; `sdf`, same).

**R9 — Continuity contract.** C2 inside bricks and across same-gauge
seams by construction. C0 across a gauge change in P2.1 (the hanging-node
rule gives values). **Spline-consistent prolongation is D2's first item,
not cosmetic cleanup**: refinement adds bandwidth, it does not change
shape — the fine side represents the coarse function before local
information is added.

**R10 — Composition is smooth union at commit.** A `surface` delta is not
added; the commit applies smin(φ, δ, k) with k the collar radius carried
on the delta. Applied in front-id order: deterministic, and marked a
DELIBERATE COMPROMISE, not architecture — the log-sum-exp family is
associative for a shared k and is the path to an unordered reduction if
one is ever wanted.

**R11 — Deposition is a swept capsule.** A front deposits nothing at a
point. Between ring k−1 and ring k it sweeps a capsule whose radius is
the ring's radius at (s, θ), evaluates signed distance to it at every
node in reach, and smooth-unions it in. Nothing is quantised.

**R12 — (s, θ) are charts, not fields.** Ring history stays on the front
genealogy (24 slots per ring, the loft table it always was). Deposition
leaves PROVENANCE at the nodes it touches — front id, segment id, and the
chart's (s, θ) — not an authoritative global (s, θ). At a branch collar
several segments contribute; band signal is blended by the same
smooth-union weights that compose the shape, w_i ∝ exp(−kφ_i), so bark
never rotates 140° because nearest-front ownership changed by one sample
(Astra's correction of Claude Code's proposal; adopted).

**R13 — Bands are semantic bandwidth classes.** Band 0 the carrier;
bands 1–2 developmental history (ring morphology, scars, knots) from the
front's ring history through the charts; bands 3+ material microstructure,
procedural, with a per-material amplitude vector. A query names the
footprint and the class; bands finer than the footprint are not
evaluated. Sponge, sound and sensors ask for band 0.

**R12a — The field is canonical; provenance is optional history.**
(Astra, `representation2.md`.) Band 0 is never a re-derivable cache of
the front genealogy: for terrain, erosion, melting, welding, fracture and
arbitrary operators there may be no genealogy at all. Grown organisms
carry provenance that drives the higher bands; geology may carry none.
The hierarchy is: canonical truth, the continuous field state; optional
provenance, how some of it came to exist.

**R14 — What stays a node quantity.** Growth, Age, Activity, Light,
Stimulus, Damage: conserved, diffusing, additive, unchanged. Density and
Extinction stay for volumes. The tree stops being a volume. (Activity
became a touch time on Sunday evening — the ledger, "The steady state".)

**R15 — Attention is derived, never stepped.** (Christian, Sunday
evening: "a variance or attention score associated with the cells, so
the step updates where things are changing — like Box3D with sleeping
states, but differentiable." Ordered ahead of P2.2: load-bearing to the
entire system.) Every brick carries the MAGNITUDE of its last committed
change and the fed second it landed, (a₀, t₀), written at commit from the
change that reached it — its own deltas, or a seam or halo write from a
neighbour, whichever was larger — and nowhere else. Attention at any
moment is a(t) = a₀ · exp(−(t − t₀)/τ), computed where it is read.
Nothing is stepped to maintain it: a quiet world stays quiet, and two
readers may choose two τ. It lives in the snapshot's bookkeeping beside
the active set, in the content hash (it decides what the next step
does), not in the brick's planes. Merged by MAX up the tree into
`Summary.attention`, so "where is the world changing" is answered from
the walk alone, as G6 answers "where is there anything". Rejected: an
exponential moving average stepped on every brick — the tail the touch
time just removed, brought back as a scalar; a wake fraction handed to
neighbours — the magnitude of what actually reached a neighbour is the
honest graded wake, and the seam and halo writes already carry it. The
active set stays what it is — changed above the floor, or a live front
— since for local operators that rule is exact; attention orders the
active set when a BUDGET is set, and is what readers see. (Built Sunday
afternoon; RULED on the same afternoon, Christian: "Attention and
obligation are different things" — attention a score of what will
change next, per channel over its range; obligation a queue of what
must run regardless, a live front's brick and a carried brick, first in
key order; a carried brick fades under the floor only when it hosts no
front; and the budget is an input like the seed, on the transcript.
The ledger, "Attention and obligation".)

**R16 — The budget is fed, in work units, and a step is resumable.**
(Christian, Sunday evening: "a budget policy for the updates to keep
everything within a specific time cost. It's perfectly fine if it takes
longer than a single frame update, as long as we can make it all
restartable and carry on.") Time is fed, never read (R6), and so is the
budget: `work(units)` takes a count of UNITS — a brick evaluated, a
brick applied, seamed, haloed or finalized, each a unit of known shape —
never milliseconds. A host measures what a unit costs it and feeds the
count its frame can afford; two hosts feeding the same counts publish
the same hash, and the budget is an input to G1 like dt. A step becomes
three calls — `begin(now)`, `work(units) → done?`, `finish()` — with its
state (the update buffer, the changed set, the phase and its cursor)
held on the world between them. The operate phase and the front pass
are region-local and order-free already, so any subset in any order
against the one base snapshot is exact; the commit's phases are per
changed brick and chunk the same way, with their two sorted apply
passes and the tree build the serial remainder; publish is one atomic
swap at `finish`, and readers hold the old snapshot until then (R3, G8:
the hazard slots were built for a next that takes its time). Two modes.
SPREAD, the default: the step runs to completion across as many calls
as it takes — exact, the same hash as one call, and the loam clock
advances per STEP, so a world that cannot keep up with fed time simply
lags, which is the host's cadence policy to feel. CUT: `finish` may be
called with work undone — the bricks evaluated are the highest by
attention (R15), the rest carry forward with their attention intact —
Box3D's islands going to sleep under load, graded, and deterministic
because the cut lands on a fed count. Rejected: a wall-clock deadline
inside the step (the hash would depend on the machine); dropping the
undone work (a brick skipped under a cut keeps its attention and is
first next step).

## 2. Gates first (pre-registered)

Thresholds ⟨…⟩ are Christian's; PROPOSED values live in
`src/thresholds.zig` and stand until struck. Every gate has a mutation
that must bite.

| Gate | Claim | Measure | Threshold | Mutation |
|---|---|---|---|---|
| G9 Continuity | the carrier is C2 across a same-gauge seam | max over shared-face probe points of \|∇φ_A − ∇φ_B\| and \|∇²φ_A − ∇²φ_B\| from the two holders' reconstructions | 0 to float tolerance ⟨1e-5⟩ | drop the halo copy → C0 only, derivatives disagree |
| G10 Bound | the summary's L is conservative | for every brick, max over probe pairs of \|φ(x) − φ(y)\|/‖x − y‖ ≤ L | ≤ L, exactly | L from finite differences instead of coefficients → a pair exceeds it |
| G11 Sphere trace | a march stepped by \|φ\|/L never overshoots the zero set | for N random rays, the first sign change lies within one bisection tolerance of the hit; no hit missed that a dense march finds | 0 misses in ⟨4096⟩ rays | step by 2\|φ\|/L → overshoots |
| G12 Collar | smooth union is smooth at a branch | \|∇φ\| continuous across the junction; provenance-blended band signal continuous | no jump above ⟨…⟩ | hard min → a crease; nearest-front ownership → the bark rotates |
| G13 Thin feature (STRUCK) | sub-gauge structure survives the B-spline | a straight capsule across a radius sweep ⟨0.5 … 6⟩ r/h, nine axis offsets in the cell, three orientations: whether the zero set survives, and r_rec/r worst and best | (a) the instrument reads the prediction: survival matches, r_rec/r within ⟨1%⟩ of `tools/g13_predict.py`; (b) survives at r/h ≥ ⟨1.0⟩; (c) \|r_rec − r\|/r ≤ ⟨5%⟩ at r/h ≥ ⟨2.0⟩, and thinner is refinement's problem | gauge doubled without refinement → vanishes at 1.0, thins 30% at 2.0 (bites b, c); control values half a cell off → ±40% at 2.0 (bites a, c); trilinear → survives lower, thins less (bites a only: the instrument's variation, recorded) |
| G14 Attention (built Sunday afternoon; (a) restated at build, the head in two tiers by the ruling, (c) named invariance and (d) reproducibility added by the ruling, see the ledger) | the step's work follows where things are changing, and a reader can see it without touching a brick | (a) the evaluated set is the head of the active set — the fronts' bricks never cut, then the backlog, both in key order, then by attention — recomputable from the published snapshot alone, evaluations == ops × its size, and no front step skipped under any budget with the overrun reported, every step (G5 made graded); (d) the budget is on the transcript: a run replayed from its recorded per-step budgets publishes the same content hash, serial and over the job system, and a record altered where it bites does not; (b) a walk rejecting attention-zero subtrees from summaries alone visits exactly the bricks changed within τ·ln(a₀/floor) of now; (c) under a budget of ⟨50%⟩ of the step's active bricks, the ones evaluated are the highest-attention ones, and the sapling grown under budget ends within ⟨5%⟩ of the unbudgeted run's inside count | exact; exact; ⟨5%⟩ | (a) attention ignored → evaluations scale with the brick count; (b) attention not merged → the walk visits every brick; (c) budget taken in key order instead of attention order → the tips lag and the deviation exceeds the floor |
| G14 (e) The residual (pre-registered Sunday afternoon, then built: lags 19–20 against a bound of 20, the cold region never served without the lag term) | deferral costs, so no brick with real pending change starves under a hot region | two diffusing regions, one at ⟨10⟩× the other's attention, under a budget the hot region alone fills: the longest lag at which any cold brick is evaluated, against the prediction from τ | ≤ k = ⌈(R − 1)·τ/dt + R⌉ + ⌈n_cold / slots⌉, from `g14ePredictedSteps` before the run; and the cold region IS deferred (its least lag > one step) | the lag term zeroed → the cold region is never served in the run |
| G15 Budget | a step spread over frames is the same step, and a call never exceeds its budget | (a) the wounded sapling stepped through `work(B)` in calls of ⟨B = 8⟩ units publishes the frozen reference — exactly; (b) no call performs more than B units, any phase; (c) under CUT at ⟨50%⟩ of each step's units the evaluated set is the attention-ordered head, and the run ends within ⟨5%⟩ of SPREAD's inside count | exact; exact; ⟨5%⟩ | (a) a chunk reading a brick another chunk already changed → the hash moves; (b) the seam and halo apply passes left unchunked → a call exceeds B; (c) the cut taken in key order → the deviation exceeds the floor |
| G1 again | replay, end to end, with the new carrier | frozen reference, re-baselined as a reviewed event with old and new in the ledger | identical | commit order reversed |
| The look | the trunk with no facets | the close-up at `--loam-scale 0.06` | Christian's eyes | — |

G13 is Claude Chat's addition, Astra's tie-breaker (`representation2.md`):
it answers an architectural question — the smallest structural feature a
gauge represents faithfully — before the look is judged, and its number
decides whether P2.1 declares a minimum structural radius and pushes
thinner branches into refinement, or needs a prefilter. Measure first;
no prefilter unless the number forces it.

**G13's threshold was written before the sweep** (Claude Chat, Sunday
2026-09-06: a measurement without a threshold makes the first result the
threshold — G3 again). It is struck against theory, not against the
instrument. With samples as control values the cubic B-spline is a
smoothing, S ≈ φ + (h²/6)∇²φ; a tube's Laplacian is 1/ρ, so the zero set
of a capsule of radius r sits at ρ ≈ r − h²/(6r) — thinned by (1/6)(h/r)²
— and vanishes where the smoothing lifts the axis above zero, near
r ≈ 0.78h. `tools/g13_predict.py` evaluates the full sum, worst over
nine axis offsets in the cell and three orientations:

| r/h | zero set | r_rec/r worst … best | thinning | second order |
|---|---|---|---|---|
| 0.50 | vanishes | — | — | — |
| 0.75 | vanishes | — | — | — |
| 1.00 | survives | 0.702 … 0.811 | −30% … −19% | −17% |
| 1.50 | survives | 0.909 … 0.919 | −9.1% … −8.1% | −7.4% |
| 2.00 | survives | 0.954 … 0.956 | −4.6% … −4.4% | −4.2% |
| 3.00 | survives | 0.981 | −1.9% | −1.9% |
| 4.00 | survives | 0.989 | −1.1% | −1.0% |
| 6.00 | survives | 0.995 | −0.5% | −0.5% |

From which the PROPOSED numbers in `src/thresholds.zig`: the instrument
must read this table to ⟨1%⟩ of r (survival matching exactly) — the Zig
reconstruction runs on real bricks with halos and seams, so a halo
copied one layer short shows here first; a capsule at r/h ≥ ⟨1.0⟩ must
survive (theory 0.78, headroom 0.22h); and the radius must be faithful to
⟨5%⟩ at r/h ≥ ⟨2.0⟩ (theory 4.6% worst). **Thinner than 2h is
refinement's problem, not a prefilter's.** What that rules today: the
sapling's radius ladder is 3.0 → 2.1 → 1.47 → 1.03 lattice units by
`child_ratio` 0.7, each tapering to 65% at its tip, so at gauge 0 the
generation-2 and -3 twigs fall below the faithful floor and the
thinnest tips (0.67) below survival — the number Astra asked for, and
D2's first paying customer. The mutations' curves were predicted the
same way (the script's `--gauge 2`, `--shift 0.5`, `--trilinear`) and are
in the table above; trilinear bites only the instrument-agreement check,
which is the finding Astra anticipated — interpolation keeps more of a
thin feature than approximation and is C0 for it.

Denominator check: G11's is the dense march's hit set, so "0 misses" is
measured against something that can miss for its own reasons at a
sliver; the dense march runs at a sixteenth of a cell.

## 3. Beats

**P2.1 — the carrier** (built 2026-09-06; the ledger has the numbers). Halo blocks; B-spline reconstruction and its
analytic gradient; `max_gradient` from coefficients; the `surface`
channel with narrow-band frontier (a brick is materialised where the
band reaches a face, and a brick whose φ minimum is positive holds no
surface); the `smin` op on the update buffer, front-id ordered; the
capsule sweep; the leaf as a sphere tracer stepped by the brick's L; the
seam guard extended to derivatives. Gates: G13 first — the instrument the
reconstruction is checked with before anything is grown on it — then
G9, G10, G11, G1 re-baselined.
The bridge and the shader move from `material` iso to `surface` zero.

**P2.1a — attention** (pre-registered Sunday evening; ordered ahead of
P2.2 by Christian; BUILT Sunday 2026-09-06 afternoon — the ledger,
"P2.1a — attention" and "The bridge's dirty upload": G14 green and
bitten, G1 `e3068932…`, the fade rule proposed, the bridge writing only
the strides whose `changed_ns` moved). (a₀, t₀) per brick in the snapshot beside the active
set, written at commit from the largest change that reached the brick;
`Summary.attention` merged by max; `World.attention(key, now)` and a
walk that rejects on it; `Policy.budget` — evaluations a step may
spend, the active set ordered by attention when it is set, the rest
carried forward unevaluated with their attention intact; the bridge's
dirty-set upload from t₀ (the deferred fill D1 named, for free). Gate:
G14 with its three mutations; G5 restated on it; G1 re-baselined as a
reviewed event if the hash moves (it will: the bookkeeping is in it).
What it feeds later: D2's criterion (refine where attention is high and
the front's radius is under the faithful floor; coarsen where attention
has been zero for a season), the render budget (samples where attention
is high, temporal accumulation where it is zero), and a score a front
or a controller can read.

**P2.1b — the budget** (pre-registered the same evening; R16, G15). The
step as `begin` / `work(units)` / `finish` with its state on the world;
units defined per phase and counted (`StepStats.units`); the commit's
per-brick phases behind a cursor; SPREAD and CUT; `loam-run --budget B`
as the instrument (steps per fed second and calls per step printed);
the bridge feeding a count per frame from a measured cost per unit,
with its lag against fed time printed. Gate: G15 with its three
mutations. G1 re-baselined only if the hash moves under SPREAD — it must
not, and that is (a).

*Christian's word, Sunday afternoon, before the spade.* **A front step
counts as a unit** — "otherwise the budget isn't one" — and fronts are
non-deferrable: the fronts are charged first and the discretionary
budget is what remains; if the fronts alone exceed a call's budget the
step reports an OVERRUN, never a skip. Gate G15 (d): no front step
skipped under any budget, the overrun on the trace line. (Already true
of the bricks-a-step budget: G14 (a).) **Under a sustained cut the
backlog recycles as obligations** — owed work is owed — with the
corollary named here so it is recognised, not discovered: the backlog
grows, obligations fill the head, tier two gets nothing, and the world
degrades to key-order round-robin without anybody deciding it should.
Backlog length is a standing number beside the walk ratio
(`StepStats.backlog`), and "backlog exceeds the budget for N consecutive
steps" (`World.overload_steps`) is the signal that the honest response
is slowing the world's clock rather than owing more work — D5's job,
not P2.1b's. **The budget consumed is on the transcript** from the
start: units measured, the count each call was given and performed
recorded on the snapshot and the trace as `Snapshot.budget` is now, and
replay replays the record (G14 (d)'s shape, in units).

**R17 — The residual: deferral costs, and the guarantee is a fair
distribution, not keeping up.** (Christian with Claude Chat, Sunday
afternoon, taken and BUILT the same afternoon — the ledger, "R17 — the
residual, built": "then a fast changing area can't drag down the whole
world. Well it can impose load, but the load distribution is still
fair … Load is real; what the residual removes is the ability of load
to become injustice.") In place of the backlog tier: every active brick
is owed since a fed time (`Snapshot.active_since`, beside `active`, in
the content hash — it orders the step), set to now when the brick was
evaluated this step and kept from the previous snapshot when it was
not; lag = now − since is the brick's clock running behind the
world's. The discretionary head is ordered by score = pending × (1 +
lag/τ), pending the brick's attention accumulated by MAX while it
waits and reset by evaluation (undecayed — the reader's decayed
attention in the product rises at most 1.5× before it falls, so a
carried brick could never catch a hot region; the two are different
quantities: the reader asks how recently, the scheduler how much is
owed). Fronts stay outside the score: non-deferrable, charged first,
overrun reported (G15 d). A cut brick (P2.1b) rides the score with lag
≥ one step by construction. The fade rule stays as struck — the
reader's decayed attention under the floor and no front — bounding
the tail; it does not fall out of the product. The guarantee, in
Christian's words: "The scheduler guarantees a fair *distribution*: a
hot region gets served often, but every brick with real pending change
is served within a bounded delay, so the rest of the world keeps
evolving, just later. It does not guarantee the world keeps up. If the
hot region plus the fronts exceed the budget, lag rises everywhere,
and that's correct: the honest response to more load than budget is
the world's clock slowing, visibly and on the transcript, not one
region silently freezing while another runs." The one knob is τ
(`LAG_TAU_S`, PROPOSED 1 s): a brick at a catches a region at R·a once
lag ≥ (R − 1)τ + R·dt. Gate G14 (e), pre-registered: one region at R =
⟨10⟩× the other's attention under a budget the hot region alone
fills; the coldest real brick is served within k steps, k from
`thresholds.g14ePredictedSteps` before the run; mutation: the lag term
zeroed → the cold region is never served. "If k comes out long enough
to see, τ is wrong, not the design." Backlog and overload stay
standing numbers: lag-weighted pending over the active set is "how far
behind the world is", and its growth under a sustained cut is D5's
signal.

**P2.2 — history and bands.** Provenance at deposition; ring history on
the front; bands 1–2 through the charts, blended by collar weights; bands
3+ procedural; footprint-bandlimited queries by class. Gates: G12; a
Sponge-class query that touches band 0 only, with "ignore the class" as
the mutation.

*The collar, weighed before the spade (Christian, Sunday evening).* P2.1
deposits a front's tube as a chain of capsules joined by the hard union,
because a chain smooth-unioned with k > 0 beads: smin(a, a) = a − k/4 at
every joint. That is a REPRESENTATION cost of building a branch out of
capsules, not a lighting one, and two answers are on the bench for
P2.2. (1) A gradient-gated collar: blend only where the two fields'
gradients disagree, never along a tube — the local fix, k a tuning
constant. (2) The loft never had joints along a branch; it had a spine.
One swept tube per branch — the spine a spline through the ring centres,
the radius a function of s — has no interior joins to bead, and the
smooth union then happens only where a collar is real, at a bud, with
k the child's radius at the join: a number with a biological referent,
and G12 a gate on that rather than on a fix. Its cost: the tube's last
few segments must be RE-EVALUATED as the spline extends, so the front
replaces its own recent deposit instead of unioning into it — which is
exactly what provenance at the nodes (front id, segment) makes possible,
and P2.2 is where provenance arrives. The capsule chain may still win
on simplicity for now; the choice is made in P2.2's brief, not here.

**P2.3 — the picture.** Bark from the bands; the close-up; the ensemble
near the surface for the silhouettes if the footprint truncation leaves
any (stable temporal sampling, spec Phase 2).

## 4. Scope fence

- No refinement: cross-gauge stays C0 and D2 opens with prolongation.
- No volumes: Density and Extinction are untouched and the tree is not
  one.
- No Fourier machinery: a band is a class, not an octave.
- No terrain yet, and nothing that would make terrain harder.

## 5. Recorded, not built

| fill | pointer | trigger |
|---|---|---|
| Spline-consistent prolongation (D2, first item) | R9 | the first tree that needs a finer gauge under its trunk |
| Unordered smooth union | R10, log-sum-exp | a scene where front order is the parallel merge's cost |
| Hermite with stored gradients | R7 | P2.1's fetch count measured and found to matter |
| Cross-gauge C1 | R9 | the same trigger as D2 |
| Per-region cadence (a brick at low attention stepping every k steps with accumulated dt) | R15 | sub-cycling across a seam with conservation defended; not before D2 |
