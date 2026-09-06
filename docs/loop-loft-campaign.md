# Loop Loft — Campaign Plan (v1)

**Intent.** A procedural geometry generator: spine spline + parallel-transport
frames + N fixed slots of (r, dz, dθ, tag, age) driven by a leaky integrator
toward a morphogen envelope, lofted into a watertight mesh. Growth parameters
are read from differentiable property volumes in space, so a structure is a
query against the world: growth(seed, fields) → mesh. The JSX toy
(loop-loft.jsx, 2026-08-30) is the reference behaviour — used as a
specification, not a port.

The long thesis, stated once: one algorithm spans pillars, arches, terrain
features and eventually creatures; the only thing distinguishing them is which
fields they grew through and where their knots landed. v1 builds the machine
and the field read path. Everything else is horizon.

---

## Pre-registered acceptance gates

Gates are pass/fail and written before the code. A mutation that doesn't bite
is a finding about the gate.

- **G1 — Determinism.** growth(seed, params) produces a byte-identical vertex
  and index buffer across runs and across rebuilds. Noise is counter-based —
  a fixed hash of (seed, ring, slot), never sequential draws — so
  determinism survives reordering and, later, parallel branch growth. No
  platform PRNG, no libm-dependent paths. Mutation: perturb one PRNG
  draw; gate must fail.
- **G2 — Watertight.** Output is a closed 2-manifold: every edge shared by
  exactly two triangles; Euler characteristic V − E + F = 2 for the
  single-spine (genus 0) case. Mutation: drop one cap triangle; gate must fail.
- **G3 — Manifold under jitter.** |dz| < spacing/2 enforced at the state
  level; no ring-to-ring vertex crossing at any knob setting inside the
  declared ranges. Mutation: remove the dz clamp; gate must fail at max
  jitter.
- **G4 — Field provenance.** growth(seed, sampled-field-values) is
  byte-identical to the original build; the sampled values ride the recipe as
  provenance. Same shape as the asset-pack bit-identity proof: regrow from
  stamp, compare buffers. Mutation: perturb one stamped sample; gate must
  fail.
- **G5 — Blend continuity.** A spine crossing a field boundary produces
  effective parameters that vary along s no faster than the field itself —
  no parameter step exceeds the field's own delta between consecutive ring
  samples. Mutation: sample fields once at the base instead of per ring; gate
  must fail on a straddling spine.
- **G6 — Branch conservation.** Each child ring after a knot split carries the
  full N slots; the assembled structure passes G2 after degenerate-seam
  removal. Mutation: let a child inherit only its arc's slot count; gate must
  fail.
- **G7 — Curvature guard.** At every ring, effective radius (envelope +
  residual) < 1/κ of the local spine curvature, or the build reports the
  violation. Mutation: 182° bend with an oversized envelope; guard must fire.

## Invariants

- N is fixed for the entire build. Triangle removal is post-process only.
- Rings step by arc length along the spine, never by height.
- Frames are rotation-minimizing (parallel transport). No Frenet anywhere.
- State is the residual: r decays toward the morphogen envelope, dz toward 0,
  both with leak k. Nothing stores absolute shape except the envelope.
- v1 growth happens at cut/build time and lands in the static tree. No
  runtime BLAS appends (see deferred fills).
- Fields are sampled at the spawn/cut tick; the sampled values are stamped
  onto the recipe. Fields stay off the transcript as already ruled — the
  stamp is what makes growth reproducible anyway.
- The generator is a recipe archetype on the ^ spine. A grown instance
  references its recipe; regrow is re-evaluation.
- Loft output emits through the existing Zig mesh-operator suite and inherits
  its test discipline.

---

## Phases

**P1 — Single-spine machine in Zig.** Spine (constant-curvature arc first,
general spline after), parallel transport, ring CA (leak, diffusion, noise,
impulses), envelope morphogens, loft with caps. Recipe archetype + registry
entry. Gates: G1, G2, G3, G7. Cross-check silhouettes against the JSX toy at
matched seeds — spec-derived agreement, not numeric identity (different PRNG
is fine; the toy defines qualitative behaviour, the Zig gates define truth).

**P2 — Field read path.** Growth samples property volumes per ring at the
spawn tick; sampled values stamp the recipe. Blend by superposition as per
the casts design. First two field-driven behaviours: (a) any scalar knob
driven by a field (taper, noise, k), (b) the mechanization field m —
blending the update rule itself: m=0 residuals flow, m=1 residuals snap to
lattice, dθ quantizes, impulses go periodic. Gates: G4, G5.

**P3 — Knots and branching.** Knots on the spine partition the ring by tag
arcs; each child resamples its arc to full N; degenerate seam triangles
deleted post-build (triangles only — vertices are never removed, N stays
fixed globally). A child's first frame is inherited from the parent's
transported frame at the knot, with only the tangent replaced by the child
spine's initial direction — spawning children with independent frames
misaligns the seam and G2 cannot survive it. Child spines run the same
machine with inherited state.
Gates: G6, plus G2 re-run on the assembled result. This phase is deliberately
last and behind its own gate — it is most of the topology risk.

**P4 — Semantics, one toy enzyme.** The tag channel goes live with a single
derived rule: a slot whose |residual| stays above threshold for k consecutive
rings acquires #ridge. The threshold is envelope-relative (~0.15 × local
envelope radius), not absolute — under taper an absolute threshold makes
ridges vanish toward the tip for no semantic reason; relative, the meaning
scales with the structure. One enzyme reads it (e.g. ridge slots get reduced
leak — ridges self-reinforce). Derived-tag mechanics follow the existing
ruling: one maintainer owns removal. Scope is one rule; the point is proving
that semantics derive from the residual bus, not building a rule library.

**P2.5 (stretch, only if P2 lands early) — Gradient tropism.** Spine steering
reads the field gradient: lean toward attractors, away from $blight. This is
the first place the spine itself becomes field-driven; if it slips, it slips
whole into the next campaign.

---

## Scope fence (v1 will not)

- No runtime regrowth or live field repainting — build/cut time only.
- No terrain, no characters, no foliage/leaves. Horizon notes only.
- No branch rejoining, no handles, no genus > 0.
- No self-emitted fields (generator rigs).
- No decimation/LOD beyond degenerate-seam cleanup.
- No texturing work beyond carrying (s, θ) and tags on the vertices.
- No inverse solves.

## Deferred fills (recorded with pointer and paying customer)

- **Runtime BLAS append under slim format.** Pointer: per-BLAS quantisation
  lattice work (already recorded 2026-08-25 against the recipe prim). Paying
  customers, in order: Ironwood's mesh-operator silhouette pass; then live
  regrow ("repaint the field, regrow the street").
- **General spline spines.** P1 ships constant-curvature arcs; the spline
  evaluator is a fill with the toy's bend knob as its spec. Paying customer:
  first asset that needs an S-curve.
- **Poisson-disc / stratified impulse placement.** v1 impulses are uniform;
  clustering artefacts at high rates are accepted. Paying customer: first
  terrain-flavoured asset where clustering reads as wrong.

---

## Horizon nuggets (v2+, parked)

- **Topology closure.** The machine makes tubes — genus 0 by construction.
  Branches split but never rejoin: no handles, no torus, no arch-that-merges.
  Terrain sheets stretch tube topology too. Revisit trigger: the first asset
  brief that needs a rejoin.
- **Inverse growth.** "Differentiable fields for everything" suggests the
  generator itself should be differentiable end to end — given a target
  silhouette, solve for the fields. Parked until the forward machine is
  boring.
- **Generator rigs (growth-emitted fields).** The closure property:
  fields → growth → fields → growth. An oak's knots cast their own
  suppression fields (apical dominance is a leaky integrator cast by the
  growing tip); authored fields supply only the coarsest level (soil, light,
  blight) and the rig supplies the rest recursively. Almost-free in this
  world: casts already have caster-owned volumes, superposition and
  unmount-cleanup — the new capability is "a knot may cast." Known dragons:
  evaluation order becomes a DAG (parent's cast must exist before the child
  samples), and self-reading growth is a feedback loop needing stability
  analysis. Revisit trigger: the first time someone authors a two-level
  structure by hand-placing fields for the second level.
- **The spine is the rig.** Characters: posing the spine deforms the mesh
  through (s, θ) with no skinning pass; branch knots are joints; fixed N
  means all creatures share one topology and interpolate/breed as points in
  one state space. Not scoped; recorded so the v1 decisions (fixed N,
  transport frames, state-relative geometry) are recognised as the enabling
  ones.
- **Terrain as leaf type.** A ridgeline is a horizontal spine; heightfield
  special cases (overhangs, arches, caves) cost nothing in tube land. Joins
  the 2026-08-19 direction: terrain as an evaluated-on-the-fly BVH leaf
  referencing a recipe, not stored geometry.

## Open questions carried forward

- ~~Where field-sampling sits relative to the knob/plane machinery~~ —
  **resolved 2026-08-30: both, separated by the cut tick.** Growth
  parameters live as plane paths during authoring (live knobs, console
  visibility, X-ray views for free); cut stamps the frozen snapshot that
  G4 hashes and regrow re-evaluates. Tuning and determinism are not in
  tension — they happen on opposite sides of the cut.
- Whether the mechanization field's rule-blend wants its own channel name or
  rides an existing semantic channel.
- Tag arcs at knots: authored per-recipe, or derived from the P4 enzyme
  output? v1 can hardcode one split layout to keep P3 honest.
