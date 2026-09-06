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

Status at the close of 2026-09-06: Astra's tie-breaker
(`representation2.md`) recommends striking R7 for the halo + B-spline,
adopting `surface`, adding G13, keeping the field canonical, and starting
P2.1 in a fresh session from this brief. Christian's word is the strike.

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
Extinction stay for volumes. The tree stops being a volume.

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
| G13 Thin feature | sub-gauge structure survives the B-spline | a straight capsule across a radius sweep ⟨0.5 … 6⟩ r/h, nine axis offsets in the cell, three orientations: whether the zero set survives, and r_rec/r worst and best | (a) the instrument reads the prediction: survival matches, r_rec/r within ⟨1%⟩ of `tools/g13_predict.py`; (b) survives at r/h ≥ ⟨1.0⟩; (c) \|r_rec − r\|/r ≤ ⟨5%⟩ at r/h ≥ ⟨2.0⟩, and thinner is refinement's problem | gauge doubled without refinement → vanishes at 1.0, thins 30% at 2.0 (bites b, c); control values half a cell off → ±40% at 2.0 (bites a, c); trilinear → survives lower, thins less (bites a only: the instrument's variation, recorded) |
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

**P2.1 — the carrier.** Halo blocks; B-spline reconstruction and its
analytic gradient; `max_gradient` from coefficients; the `surface`
channel with narrow-band frontier (a brick is materialised where the
band reaches a face, and a brick whose φ minimum is positive holds no
surface); the `smin` op on the update buffer, front-id ordered; the
capsule sweep; the leaf as a sphere tracer stepped by the brick's L; the
seam guard extended to derivatives. Gates: G13 first — the instrument the
reconstruction is checked with before anything is grown on it — then
G9, G10, G11, G1 re-baselined.
The bridge and the shader move from `material` iso to `surface` zero.

**P2.2 — history and bands.** Provenance at deposition; ring history on
the front; bands 1–2 through the charts, blended by collar weights; bands
3+ procedural; footprint-bandlimited queries by class. Gates: G12; a
Sponge-class query that touches band 0 only, with "ignore the class" as
the mutation.

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
