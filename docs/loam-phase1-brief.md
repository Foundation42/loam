# Loam — Sparse Field Dynamics
## Phase 1 hand-off brief for Claude Code

Companion to `loam-spec-draft-0.1.md` (Architecture & Interface Specification, Draft 0.1, Sep 2026). The spec says what Loam is. This brief says what to build first, how we'll know it works, and what not to build yet. Where the two disagree, this brief wins — it carries the Sep 6 rulings that amend the draft.

Working name: **Loam**. Things grow in it; it does not make the oak. Rename is a find-and-replace; do not let the name block a start.

---

## 0. The maxim, restated for the builder

The library does not generate objects. It evolves spatial state. Matryoshka asks what that state means to a ray.

Practical consequence: nothing in Phase 1 emits a mesh, and nothing in Phase 1 knows what a triangle is. If a beat starts wanting a mesh, the beat is wrong.

---

## 1. Rulings from the Sep 6 session (amendments to Draft 0.1)

These were settled in discussion and are Christian's to strike. They are listed before the beats because two of them change the data model.

**R1 — Fronts are Lagrangian; fields are Eulerian.**
The spec's §11 morphogenesis is written as pure field advection. Ruling: the active front is a first-class object — a tracer carrying a fixed-size state vector (the loop-loft ring: per-slot `r, dz, dθ, tag, age`; per-front `s, R, roll, morphogens`). Fronts *read* the field (light, stimulus, self-density, resources) and *deposit* into it (material, age, activity). The ring CA runs on the front; the §11 gradient terms steer the front's spine. The field is the memory; the front is the cell. This is the same object as a Spindrift particle: a particle is a front that samples but does not deposit.

**R2 — The domain is the integer dyadic lattice.**
§7's `vec3 position, float time` is the public *query* surface, not the representation. Internally: 20 bits/axis global dyadic lattice (the Lattice Contract), regions are bricks with their own gauge, smooth with respect to neighbours at the seams by contract. The hierarchy is the already-adopted wide 8-way tree with tight bounds — **shared node representation**, which closes spec §23 Q1. Region summaries (§5.2) are the payload of that tree's nodes, not a sibling structure.

**R3 — Snapshots are radix commits.**
§15's immutable published snapshot + dirty regions is a radix CoW commit with a vid. §17's FieldArchive is an asset-pack layer (blob heap + record plane). Do not build a persistence format; use the identity tower that exists (root_hash / content_hash / vid).

**R4 — Casts are Fields.**
`$channels` from rill-casts.md are Loam fields with contribute-only writes and a decay operator. The F1–F7 cast gates are downstream consumers of Loam and are not re-implemented here. Channel declaration lives on the `^` archetype spine as already ruled Aug 26.

**R5 — Language and placement.**
Zig. Standalone library in the rill/spindrift pattern, consumable by Matryoshka or any Substrate-backed process. The C++ in spec §20 is notation for the shape of the surface, not a target. *(Confirm repo placement before P1.1.)*

**R6 — Time.**
Operators advance on fed time, same as sensors and actuators. Wall-clock never reaches the step function. Replay re-derives.

---

## 2. Gates first (pre-registered)

Each gate has a threshold written down before the code exists, and a **mutation** that must make it fail. A mutation that does not bite is a finding about the gate, not a pass. Thresholds marked ⟨…⟩ are for Christian to fill before P1.1 starts; the builder does not choose them.

| Gate | Claim | Measure | Threshold | Mutation |
|---|---|---|---|---|
| G1 Replay | (seed, initial fields, operator config) → byte-identical snapshot | BLAKE3 of published snapshot after N steps, two processes | identical | perturb one seed bit → differs |
| G2 Growth | A seeded front produces persistent, branching, deposited structure with no mesh | count of connected material components > 1; material present at step N ≥ material at step N/2 (no reset) | components ≥ ⟨3⟩ at N=⟨…⟩ | zero deposit rate → no material |
| G3 Tropism | Moving a stimulus field redirects live fronts | displacement of active-front centroid toward stimulus over K steps | ≥ ⟨…⟩ lattice units, sign correct | stimulus gradient term zeroed → no drift |
| G4 Local repair | Removing material re-activates evolution locally only | regions touched by the update ⊆ dilate(damage AABB, k); all other regions byte-identical | k = ⟨…⟩ bricks | remove healing operator → no reactivation |
| G5 Dormancy | Dormant tissue costs nothing | step time vs active-region count at fixed total-region count | slope ≤ ⟨…⟩ ns/active region, intercept flat in total regions | remove the active set, iterate all → slope appears in total |
| G6 Skip | A ray rejects subtrees from summaries alone | leaf samples per ray on an empty-majority scene | ≤ ⟨…⟩% of leaves visited | summaries set to +∞ → all leaves visited |
| G7 Narrow query | Shadow-class queries do less work than primary | channel bytes gathered per query, by QueryClass | shadow ≤ ⟨…⟩% of primary | ignore channel mask → equal |
| G8 Snapshot safety | Snapshot N readable while N+1 simulates | reader thread hashes N continuously during sim of N+1; hash never changes; no locks in read path | zero changes, zero waits | publish in place → hash changes |

G1 is the acceptance gate for the whole phase, in the same role as (seed, sampled-fields) → byte-identical mesh was for loop-loft. Nothing ships without it.

**Guards.** Every build asserts its invariants (region bounds conservative, absent channels unallocated, active set ⊆ dirty set ⊆ all). A self-test corrupts each invariant and proves each guard fires. This is house practice after the Sep 4 lattice campaign, where four defects produced plausible output instead of errors.

---

## 3. Phase 1 beats

Each beat closes with its gate(s) green and a one-paragraph ledger entry. No beat begins before the previous beat's gates are green.

**P1.1 — Lattice domain and region tree.** 20-bit dyadic lattice, 8-way tree with tight bounds, region = brick with gauge. Summaries (`ChannelMask`, density/extinction/emission ranges, `maxGradient`, `version`). No channels yet beyond `Density`. Guards + self-test. *Gate: G6 on a hand-placed density blob.*

**P1.2 — Channel blocks.** SoA per-region channel storage; absent channels are not allocated (assert). Channel registry with reserved user range. `sample()` with trilinear reconstruction across brick seams (the seam contract is the whole point — test a value that straddles two bricks of different gauge). *Gate: G7.*

**P1.3 — Operators and the update cycle.** `reads()/writes()` declared; gather → operate → region-local UpdateBuffer → barrier → commit → summaries rebuilt → version bump. Diffusion, Decay, Advection first (all three have closed-form checks). Deterministic mode with per-region streams derived from (region id, epoch). *Gate: G1 on diffusion+decay only.*

**P1.4 — Fronts.** Lagrangian tracer with the ring state vector (R1). Ring CA as the toy already proved (leaky integrator heal, noise, drift, envelope). Fronts read light/stimulus/self-density, deposit `Material`, `Age`, `Activity`. Inhibition and Healing operators land here because both need a front to act on. *Gates: G2, G3, G4.*

**P1.5 — Active set and dormancy.** Active set = regions with a live front or non-zero activity above ε. Step iterates the active set only. *Gate: G5.*

**P1.6 — Snapshot publication.** Publish via radix commit (R3). Reader/writer on separate threads. *Gates: G8, then G1 re-run end to end.*

**P1.7 — The seedbed.** A small CLI range, Loam's tiltyard: place a seed, a light, a wall of damage; step; dump slices as PGM and the active set as a list. Its job is making gate vacuity visible. Same authoring surface the real scenes will use — a range-only mechanism is a smell.

---

## 4. Scope fence (Phase 1 does not include)

- Any Matryoshka integration, any ray. G6/G7 are exercised with a stub ray over the tree. Integration is Phase 2.
- GPU. CPU only, but batch-shaped (no per-sample virtual dispatch on the hot path).
- Dynamic refinement/coarsening. Bricks are fixed-gauge in P1. See D2.
- PBR/optical channels beyond `Density` and `Emission` placeholders.
- Topology rules beyond what fronts give you (no rejoins, no handles) — same fence as loop-loft.
- Inverse growth (fields from a target silhouette).
- Biology. Tropism is a gradient term, not a plant.
- Streaming, chunk residency, operator state persistence beyond what the radix commit already carries.

---

## 5. Deferred fills (recorded with a pointer, never as rules)

- **D1 Renderer integration.** Pointer: Matryoshka heterogeneous BVH leaf types. Horizon expectation: `LEAF_SDF_MARCH`, `LEAF_METABALLS`, `LEAF_PARTICLES` collapse into "region with channels + reconstruction mode". Paying customer: first Loam-grown thing on screen.
- **D2 Refinement/coarsening.** Pointer: the HOIST_K campaign (Sep 4). Where you coarsen is where you're wrong; the evidence on that trade transfers. Build it error-driven from day one, not gradient-driven, and price it in pixels.
- **D3 GPU backend.** Pointer: Sponge's Morton-hashed SSBO addressing — the tree's Morton codes already address the storage.
- **D4 Reconstruction bases per channel.** Trilinear in P1. Spec §23 Q2 stays open; measure before choosing.
- **D5 Operator scheduling.** Fixed order in P1. Dependency graph or event-driven activation is a Phase 4 question with rill as the obvious host.

---

## 6. Horizon notes (not for this campaign)

- **Sponge is an operator.** Radiance is a channel; the async tracer is a propagation operator; self-throttling is G5 applied to light.
- **Sound is the same shape.** §19's sound/energy row with a different propagation operator — the Aug 13 spatio-musical vision, finally on one substrate.
- **Spindrift unification.** Once R1 lands, a Spindrift emitter is a front factory with deposit off.
- **The hoisting question changes shape.** The Sep 4 sign-off asked whether plane hoisting pays on *generator-emitted* ring grids. Loam does not emit ring grids. The live question becomes whether hoisting pays on surfaces *extracted* from a field (density crossing lattice edges), which are smooth by construction where the field is smooth. Different corpus, same pre-registration.
- **Generator rigs.** Growth writes into the growth-potential channel, so second-level fields are deposited rather than authored. Revisit trigger from Aug 30 (someone hand-places second-level fields) may never fire.

---

## 7. Method (standing)

- Pre-registered thresholds; the builder does not choose them.
- One mutation per gate that must bite.
- Bit-exact instrument: hashes and counts are the evidence; timings carry the error bars and must state their regime.
- Denominator check before any ratio: what does the denominator measure, and can one item satisfy the numerator alone?
- Fill, don't work around. A deferred fill gets a pointer and a paying customer.
- Ledger entry per beat. No sub-agents for look-and-adjust work; reconnaissance parallelises.

---

## 8. Open for Christian before P1.1

1. Repo placement (R5) — sibling library like rill, or inside Matryoshka?
2. Threshold values ⟨…⟩ in §2.
3. Front ownership: does a front belong to the region it currently occupies, or to a global front list indexed by region? (Affects G4's "regions touched" measure.)
4. Whether `Growth` (potential) stays a field channel that fronts consume, or becomes a front-only quantity. R1 leans field-channel so generator-rigs fall out.
