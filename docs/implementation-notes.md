# Implementation notes — the ledger

**Status:** Phase 1 built, 2026-09-06: P1.1–P1.7, G1–G8 green and bitten.
**The cost beat, the same night** — the bark reads nothing but the
carrier; the two chart planes gone, the collar's window through the
ring table, the chart at a read the capsule's exact foot; 5.21 → 4.49
ms a step ("The cost beat" below). **P2.3 built Sunday 2026-09-06, night** — what a hit reads: the chart
from the provenance planes (masked, the seam where two fields cross),
the bands by footprint fading in over an octave, the grain bare at a
collar, on the GPU with the ring table; G16 green and bitten, the
prediction read at every row ("P2.3 — the picture" below).
**P2.2 built Sunday 2026-09-06, night** — the collar gated by
provenance with the two-slot fill, the bands through the ring history,
G12 bit-exact and bitten, the inner elbow measured ("P2.2 — the collar,
provenance and the bands" below). **P2.1a built Sunday 2026-09-06, afternoon** — attention: derived from
each brick's last change, in the summaries and the hash, ordering the
step under a budget; G14 green and bitten, G1 re-baselined ("P2.1a —
attention" below); RULED the same afternoon — "Attention and obligation
are different things" (the entry of that name); then R17, the
residual, built the same afternoon: deferral costs, G14 (e) read its
prediction exactly ("R17 — the residual, built"). **P2.1b built the
same afternoon** — the step as begin / work / cut / finish, SPREAD
exact to the frozen reference, G15 green and bitten ("P2.1b — the
budget in work units"). The step cost taken and the matryoshka merge
done the same afternoon: matryoshka `main` carries the loam leaf.
Phase 2 opened the same evening: the first loam-grown thing on screen
(matryoshka branch `loam`, "Renderer integration, beat 1" below).
**P2.1 built Sunday 2026-09-06** — the continuous carrier: R7 and G13
struck by Christian, G13, G9, G10, G11 green and bitten, G1 re-baselined,
the tree on the lawn with no facets ("P2.1 — the carrier" below).
Reviewed the same day (Claude Chat against `3ecbb37`, forwarded by
Christian); the review's three recommendations adopted, see "Review
2026-09-06" below. Every threshold PROPOSED (brief §2,
`src/thresholds.zig`); every ruling below proposed against the code and
standing until Christian strikes it.

Everything here is a decision made while building
[loam-phase1-brief.md](loam-phase1-brief.md) against
[loam-spec-draft-0.1.md](loam-spec-draft-0.1.md), recorded so the next
session doesn't re-derive it. Rulings R1–R6 are the brief's; this ledger
holds what was decided *against the code* and what each gate was paid for.

## The rules this ledger runs under

Inherited from rill's and spindrift's ledgers unchanged, restated here so
they are read here:

- **Prose approves plausible semantics; execution approves actual
  semantics.** A gate is an executed program.
- **A mutation must bite.** A gate that passes under its named mutation is
  a finding about the gate, not a pass. A mutation that does not compile
  is not a mutation. A mutation that survives and is *right* names a
  decoration — delete it, with the reason at the site.
- **A gate must run where A ≠ B.** A gate over a field must vary on every
  axis it claims (two survived mutations this phase were exactly this;
  see P1.2 and P1.6 below).
- **Denominator check before any ratio.** What does it measure, and can
  one item satisfy the numerator alone?
- **Bit-exact instrument.** Hashes and counts are the evidence; timings
  carry error bars and state their regime (build mode, threads).
- **Recorded-not-built needs a trigger.** Fill, don't work around; a
  deferred fill gets a pointer and a paying customer, never a rule.
- **Read-aloud before naming; record rejected names.**
- **Loud, never a guess.** A refusal lands on the node that refused it.
- **Time is fed, never read.** No wall clock reaches the sim.
- **Docs ride the same commit.**

## Proposed rulings (standing until struck)

Answers to the brief's §8, and the choices §8 did not ask about but the
code had to make.

- **§8.1 Repo placement:** standalone at `~/dev/loam`, spindrift's shape
  (path deps on `../common` and `../struple`; matryoshka will depend on
  loam, never the reverse). Ratified by Christian in the opening brief.
- **§8.2 Thresholds:** all in `src/thresholds.zig`, PROPOSED, with the
  measured value beside each in the gate table below. G3's floor is no
  longer a number: it is k × the null spread, k = 3 PROPOSED (review).
- **§8.3 Front ownership:** a global id-ordered list on the world, each
  front carrying the key of the brick under it. G4's "regions touched"
  is measured on bricks, by pointer identity against the pre-wound
  snapshot, which needs no front ownership at all. *Review 2026-09-06
  recommended stamping; adopted, pending Christian's word.*
- **§8.4 Growth potential:** a field channel fronts consume (R1's lean
  taken, so generator rigs fall out). A front reads it one radius AHEAD,
  where it is going, and draws it down in a sphere of two radii around
  itself as it passes. Rejected: consuming at the deposit samples (a
  front standing in its own tube read zero and went dormant at once);
  reading under the front (same failure, one step later). *Review
  2026-09-06 recommended stamping; adopted, pending Christian's word.*
  Note for D2, not a ruling: the draw-down sphere (2R) is larger than
  the read-ahead distance (R + 1), so the exhaustion rate is coupled to
  step size (speed·dt) and to gauge (samples per sphere). Harmless at
  fixed gauge; the first thing refinement changes underfoot.
- **Activity is a touch time.** (Evening, "The steady state" below.) The
  fed second a front last passed a sample, overwritten, read as `now −
  Activity`. Rejected: the Phase 1 level under a Decay operator, which
  kept bricks changing for forty steps after the last front stopped and
  doubled the changed set during growth — a cost that never converged.
- **A quiet step publishes nothing.** No active brick, no live front,
  nothing queued: the clock advances and the snapshot stands. A host
  keyed on the vid sees no change because there was none.
- **Age is a birth time.** The Age channel holds the fed time (seconds)
  at which a sample was first laid; the age of tissue is `now − Age`.
  Rejected: accumulated deposit exposure (the first cut — it answered
  "how long was a front here", not "how old is this"); an ageing
  operator incrementing Age everywhere material exists (every brick with
  material would be active forever, and G5 would be false). Birth time
  is the only encoding of history a dormant brick can carry.
- **Numbers.** Lattice addresses are integers (u32 points, 60-bit Morton
  keys over cells); channel values are f32; front positions are f64
  lattice units. Bit-identity is claimed per BINARY on ONE MACHINE — two
  processes of one build — and, as measured below, across Debug and
  ReleaseFast of one source on this machine. Front positions pass
  through exp/sin/cos/atan2 in f64; agreement across a different libm
  is unmeasured and the regime line says so until it is. Rejected: Q16.16 everywhere (spindrift's rule). A field
  library's reconstruction, gradients and exponential decay want dynamic
  range; the integer-first contract applies to *where* a thing is, not
  to *how much* of it there is, and that is the split matryoshka
  already runs (integer lattice, f32 field values). The GPU twin (D3)
  is where this gets revisited.
- **Bricks are node-centred, 9³ samples, self-contained.** Two bricks
  sharing a face both store it, so trilinear never reaches across a
  brick, and the seam contract is a commit-time rule rather than a
  sampling-time lookup. Cost: 729 samples for 512 cells (42% on the
  planes). Rejected: cell-centred 8³ with neighbour gathers — every
  sample then needs up to eight bricks and the seam is a property of the
  gather, which no guard can check in isolation.
- **The seam contract (R2's "smooth by contract").** ANCHOR: a shared
  lattice point takes the finest holder's value; ties go to the holder
  that wrote deltas this commit, then a materialised-empty brick loses,
  then the lowest key. HANG: a fine sample on a face shared with a
  coarser brick, off the coarse lattice, takes the coarse interpolant.
  The coarse face governs the face; C⁰ across the seam; the fine brick
  loses face detail there. The rank in the tie-break was paid for by
  the diffusion gate: with key order alone, a freshly materialised
  neighbour (lower key) copied its zero over the point mass it was
  meant to receive, and mass went to zero while every seam agreed.
- **Snapshots are a persistent tree** (R3): path-copied per commit,
  refcounted nodes and bricks, untouched subtrees shared by identity.
  The identity tower is `vid` / `rootHash` (Merkle over summaries and
  brick bytes) / `contentHash` (root plus fronts, clock, active set),
  standalone here; when loam is mounted in a Substrate-backed host these
  are the same three names matryoshka's asset packs carry. Rejected:
  depending on `../substr`'s radix map — the octree IS a radix-8 trie on
  Morton keys, and a second index over the same keys would be a second
  truth.
- **Readers acquire through hazard slots**, not a lock: two loads, one
  store, one retain; the writer defers freeing any snapshot a slot
  names. `MAX_READERS = 64`. G8 counts zero mismatches over 40
  publishes. Rejected: a mutex around acquire (a wait is a wait);
  keeping the last K snapshots alive (a descheduled reader is a
  use-after-free with extra steps).
- **Activity.** A brick is active next step iff it holds a live,
  non-dormant front, or a change above `EPSILON` landed in it this
  commit (delta, seam copy, materialisation). When no operator ran (the
  epoch tick, an authoring apply) the active set carries forward — the
  epoch tick once emptied it and nothing ever ran (found by the
  diffusion gate reading zero mass after forty steps).
- **The frontier rule.** A changed brick whose face carries a value above
  `EPSILON` materialises the absent same-gauge neighbour across it,
  probed against a scratch tree holding this commit's bricks (probing
  the base tree once placed a fine neighbour inside a coarse brick from
  the same apply — GaugeConflict, loud). Nothing is materialised where
  any brick already is, at any gauge.
- **Mixed gauges are authorable, not refinable.** `Snapshot.coverCube`
  resolves a cube to the leaf there (any gauge), the finer leaves inside
  it, or the cube itself; blobs and stamps go through it, so a gauge is
  never placed over another. Refinement/coarsening stay fenced (D2).
- **Diffusion clamps at 1/6 and COUNTS the clamp** (`diffusion_clamped`
  in the stats, printed by loam-run). Rejected: refusing at mount — dt
  is not known at mount; silently clamping — the seedbed would have no
  way to see it.
- **Inhibition is a front rule**, not a region operator: `canGrow` reads
  Material one radius ahead against `inhibit`, and the avoid-self
  gradient term steers away. §10's row is satisfied by the thing that
  grows being the thing suppressed.
- **Healing restores potential across the wound** (every damaged sample
  without tissue), spawns one repair front where damage borders tissue
  and nothing is working nearby, and clears the damage mark where tissue
  regrew. "Nearby" is a brick and a half — counting only the brick
  itself spawned a front every few steps as each moved on (285 fronts for
  one wound, 7 bricks outside G4's band).
- **Names.** Loam (the brief's working name, kept). `Front` (R1's word;
  rejected: `tracer`, spindrift's row is a tracer that does not deposit;
  `tip`, biology). `stamp` for the deposit (rejected: `paint`, a tool's
  verb; `cast`, rill's word for a $-channel deposit and not this).
  `Neighbourhood` for the seam cache (rejected: `stencil`, an operator's
  word). `seedbed` for the tiltyard (the brief's word). `coverCube`
  (rejected: `resolve`, says nothing). `hazard` slots (the literature's
  word, kept on purpose).

## Gates, as they stand (Debug, serial, seed 7 unless stated)

Phase 1's table, as measured on the Phase 1 carrier (Material); the
P2.1 entry below has the same gates re-measured on `surface`, and the
four new ones.

| gate | measure | value | threshold | mutation | bit? |
|---|---|---|---|---|---|
| G1 | content hash, serial vs JobSystem(4); two dumps; two processes (py-test); Python door vs CLI door | identical, and equal to the frozen reference | identical | seed ^ 1 | yes |
| G1 | frozen reference | `74cc820b…` | fixed | commit order reversed | yes — see P1.6 |
| G2 | branches; young-material 3-D components at peak; material N/2 → N | 9; 5; 2596 → 2628 | ≥3; ≥3; no reset | branching off → 1 component, material grows; deposit = 0 → nothing | yes; yes |
| G3 | matched ± pairs, six seeded directions, D = 40, 40 steps: r̄, 95% lower bound, sign test, effect size vs σ₀ along û | r̄ 25.9, lower 24.0, 6/6 positive, σ₀ 6.5 (floor 19.5) | lower > 0; all > 0; r̄ > 3σ₀ | coefficient 0 → r ≡ 0; gradient reversed → all r < 0 | yes; yes |
| G4 | bricks touched vs dilate(box, 2), by identity; material regrown | 54 touched, 0 outside, 1601 regrown | 0 outside | no healing operator → 0 regrown | yes |
| G5 | region evaluations over 80 steps | 12,480 (all-regions: 584,320) | evals == Σ active × ops | `active_only = false` | yes |
| G6 | leaves sampled / leaves crossed | 12 / 64 | ≤ 0.25 | `use_summaries = false` → 64/64 | yes |
| G7 | shadow bytes / primary bytes | 2816 / 11264 = 0.25 | ≤ 0.5 | ignore mask → 1.0 | yes (hand) |
| G8 | re-hashes of pinned vid, mismatches | 10 of vid 22 while writer → 62; 0 | 0 | write a published brick in place | yes |
| seams | continuity across a gauge-0/gauge-1 face under diffusion | guard passes | exact | hang pass off; anchor pass off | yes; yes (after fix, P1.2) |
| diffusion | variance after 40 s at D = 0.1; mass | 7.997 (closed form 8.000); 1 → 0.99991 | 3%; 1e-3 | rate above stability → clamp counted | yes |
| decay | v(10 s), τ = 4 | v₀·e^−2.5 | 1e-5 rel | — | — |
| advection | centroid after 20 s at u = 0.5 | +9.88 (closed form +10) | 0.15 | — | — |
| guards | each invariant corrupted | refused by name | — | the self-test IS the mutation set | yes ×6 |

Denominators. G6's is "leaves the segment geometrically crosses" — a ray
cannot visit what it does not cross whatever the summaries say, so
"of all leaves" would flatter the ratio. G5's is Σ(active × operators),
exact, not a timing; the timing is printed beside it (2.0 s for 80 steps
in Debug) and carries no assertion. G2's "components" are 3-D
6-connected components of YOUNG material (Material > 0.3, laid within
the last 8 s), at their peak over checkpoints every 10 steps — see the
review entry for why the first cut (a slice) failed the denominator
check.

## P1.1 — lattice and tree (2026-09-06, G6)

Built against common `9a75dfb`, struple `d937815` (their heads at the time).

- **20-bit lattice, Morton over cells, points 0..2^20 inclusive** — the
  top point of the top brick is 2^20, so points ride as u32.
- **Keys sort Morton-major**, level in the low bits: a node's cube is a
  contiguous Morton range and one sorted pass builds the tree. Brick
  level = gauge + 3; the low nine Morton bits are always zero.
- **Octants match wide8**: bit0 = +x, bit1 = +y, bit2 = +z.
- **Summaries carry tight bounds of non-zero support, not the cell.** An
  empty brick has an empty box and is skipped on bounds alone.
- **The cursor is a priority queue.** A stack with sibling sorting is not
  near-to-far: a near parent's far child can lie beyond a far sibling's
  near child, and G6's ordering check caught exactly that. The queue is
  allocator-backed; `Cursor.init` takes a gpa.
- **`findLeaf` is closed-cube**: a point on a shared face has two holders;
  the upper octant is tried first (the `Key.containing` convention) and
  the other is the fallback, so the last face of the only brick is found.

## P1.2 — channel blocks and the seam (2026-09-06, G7)

- **Planes are popcount-packed**; `planes.len == @popCount(mask)` is a
  guard, and `finalize` drops a plane that went all-zero so the mask says
  what is there.
- **The guard's own bug**: probing half a step past a face compared a
  holder whose cube did not contain the probe — its reconstruction
  clamps at the face and the "seam" disagreed. Only holders whose closed
  cube contains the REAL point are compared. Recorded because a guard
  that fires wrongly teaches the wrong lesson.
- **The seam gate did not vary on the anchor axis.** Authored blobs write
  the same value into every holder of a shared point, so a hand mutation
  that disabled the anchor pass survived. The gate now diffuses the
  two-gauge field for three steps — the gauges then compute different
  deltas at shared points — and the mutation bites.
- **The seam pass is a neighbourhood cache**, not a set closure: per
  changed brick, 26 `nodeAt` lookups resolve every neighbour (a leaf at
  any gauge, or the finer leaves inside), and each boundary point finds
  its holders by key comparison. Live pointers and ranks are resolved
  once per neighbourhood. Measured on the sapling (Debug, `--phases`):
  seams 65 ms → 22 ms → 9 ms per step at ~30 changed bricks; the scene
  build 3.0 s → 2.0 s. ReleaseFast: 1.9 ms/step, 0.38 s build — a 5–8×
  delta, known, not leant on. The guard keeps the slow general path and
  is the witness.

## P1.3 — operators and the update cycle (2026-09-06, G1)

- **Operators write deltas** into region-local entries; commit applies
  them in key order under the channel's clamp. Two operators on one
  channel sum. The parallel phase allocates delta planes through a
  thread-safe wrapper over the step's arena and never creates an entry.
- **Fronts run serially after the barrier**, in id order; their entries
  are created then. Spawns from fronts queue on the world; spawns from
  region operators ride the entries and are assigned ids in key order.
- **Closed forms**: diffusion variance 2Dt (7.997 for 8), mass conserved
  to 1e-4 (the frontier floor); decay exact; advection centroid +9.88
  for +10 (semi-Lagrangian is a little diffusive; the tolerance says so).
- **The epoch tick emptied the active set** (above). **Material was
  counted four times** by a naive plane sum — the corner sample of the
  point mass is shared with the three neighbours the frontier
  materialised; `massOnce` credits a point to its lowest-key holder.

## P1.4 — fronts (2026-09-06, G2, G3, G4)

- **The ring is the toy's** (docs/loop-loft.jsx): leak, ring diffusion,
  counter-based gaussian noise, raised-cosine impulses, jitter clamp; 24
  slots. Noise amplitude scales with the radius and the jitter with the
  speed, since the toy's constants were world units. The bud enzyme is
  loop-loft P4's ridge rule (envelope-relative threshold, k consecutive
  rings) with the tag read as "may branch".
- **The stamp** is the ring rasterised: for a lattice point, the axial
  distance selects the slab, the angle (in the transported frame, less
  the roll) selects a slot pair, the interpolated residual plus the
  envelope is the radius there, softened by 0.75 units. Material
  saturates at 1 per sample; Age accumulates deposit time; Activity takes
  the weight.
- **Branching**: the hottest bud slot, after `min_age` and a cooldown,
  spawns a child at the ring's surface with heading rotated by
  `branch_angle` toward that slot, the parent's frame transported
  (loop-loft P3's rule: a child with an independent frame misaligns the
  seam), radius and length scaled by `child_ratio`, a fresh ring. The
  parent slot resets. Recorded-not-built: inheriting the ring's
  residuals into the child. Trigger: a capture where a branch base looks
  wrong.
- **G4 failed honestly twice.** (1) Repair reached 21 bricks past the
  band because potential was barely consumed: tips freed by the wound
  regrew on their full remaining length. Consumption became a draw-down
  sphere and reading moved ahead of the front. (2) 285 repair fronts, 7
  bricks outside: the spawn check counted only the brick itself. It now
  counts fronts within a brick and a half. And the precondition is
  stated: G4 is a claim about a *dormant* world, so the fixture ends the
  season (Growth cleared everywhere) before the wound — the only
  potential anywhere after that is what healing restores.

## P1.5 — the active set (2026-09-06, G5)

- Evaluations are counted per region per operator, atomically, and the
  gate asserts `evals == Σ active_in × operators` per step and that the
  total is under a twentieth of the all-regions figure (it is 1/47). The
  all-regions mutation is a policy flag so `loam-run --all-regions` can
  print what dormancy buys.

## P1.6 — snapshots (2026-09-06, G8, G1 end to end)

- **G8's reader** pins the snapshot current when it starts and re-hashes
  every brick's bytes in a loop while the writer publishes forty more
  vids, and acquires the live one each lap to prove acquire is safe
  mid-publish. 10 laps, 0 mismatches, retired list drained.
- **G1's survived mutation.** Reversing the commit order changed the
  content hash (front ids from healing spawns follow entry order) and
  G1 still passed: both of its runs reversed together. Two fixes. The
  fixture now wounds the sapling at step 20 so region-spawned fronts
  exist (the plain sapling had none, and the order was invisible). And
  G1 carries a FROZEN REFERENCE (`thresholds.G1_REFERENCE`): the hash
  this build must reproduce, not merely agree with itself about.
  Re-baselining is a reviewed event recorded here with old and new.
  Baseline: `371e0e2dcf173ed6c5cd4fd010795d06054b0ccdbb0061b05c072827c8eb3afe`
  (wounded sapling, seed 7, 40 steps).
- **Debug and ReleaseFast agree on the reference.** Measured: the G1
  fixture reproduces `371e0e2d…` in both, and `loam-run --steps 30`
  prints `546dcc61…` in both. Zig's default float mode is strict (no
  contraction), which is what this rides on; a GPU twin gets no such
  promise and that is D3's problem.

## Review 2026-09-06 — three recommendations, adopted

Claude Chat read `3ecbb37` (thresholds, the G2 test, the rulings) and
Christian forwarded the review. Against the code:

- **G2's measure failed the denominator check.** "Max over horizontal
  slices of 4-connected material" scores a single coiling front twice —
  one item satisfies the numerator alone, so it measured "crosses a
  plane more than once", not branching. Replaced by 3-D components of
  young material (`seedbed.youngComponents`: Material > 0.3 ∧ now − Age
  < 8 s), at the peak over checkpoints — live tips each own one, a
  coiled front gives one. This needed Age to mean birth time (above).
  Measured: 5 at peak on the sapling. **The missing mutation** —
  branching off (`max_generation = 0`) — gives exactly 1 while material
  still grows (1731 laid); the old mutation (deposit = 0) only bit
  through "no material at all" and never tested the branching claim.
  G2_MIN_BRANCHES stays as the mechanism check.
- **G3's floor is set from the null.** Six stimulus-free runs (seeds 1–6)
  give the material centroid's RMS spread about the seed axis: 7.97
  units. Floor = 3 × that = 23.9. The measured drift was then 1.17 — the
  stimulus blob (centre ±60, radius 64) did not contain the seed, so the
  trunk felt no gradient; and at coefficient 1.5 the term was several
  times weaker per step than the wander (the kernel's gradient over a
  radius of 64 is ~0.02/unit). Both are scene facts: the blob now covers
  the growth region (radius 96, centre ±40) and the G3 scene uses a
  coefficient of 30. Drift 30.9 against floor 23.9. The measure moved
  from the live-front centroid (noisy once tips go dormant) to the
  material centroid — the field, as G2 now does.
- **Front ownership and read-ahead stamped** (rulings above), with the
  D2 coupling note beside §8.4.
- **Re-baseline, reviewed:** `371e0e2d…` → `74cc820b…`, because Age
  changed meaning (birth time). Same fixture, same seed, same steps.
- **Regime:** per binary, one machine (above). The seam cut stays
  deferred as recorded.

## G3 rebuilt as a matched-pair ensemble (2026-09-06, after the review)

Christian's follow-up on the review's G3: replace centroid drift with a
directional growth response conditioned on stimulus displacement, over a
seed ensemble with confidence bounds. Built as agreed
(`seedbed.tropismEnsemble`, shared by the gate and `loam-run
--tropism-sweep`):

- **The pairing is the design.** The noise is counter-based on (seed,
  front id, epoch), so for one seed the +D and −D runs share their
  wander: r_i = (c⁺ − c⁻)·û_i is a controlled perturbation, not signal
  against generic variability. The coefficient-zero mutation shows it —
  every pair bit-identical, r ≡ 0 — and that is also why the earlier
  floor (an unpaired spread) was answering a different statistical
  question than the paired statistic. Recorded as the correction it was.
- **Three separate requirements**, not one inequality: the 95% lower
  confidence bound on r̄ is above zero (Student's t from a table, n − 1
  df); every r_i > 0 (P = 2⁻ⁿ = 1/64 under a directionless null); and
  r̄ > k·σ₀ with k = 3, an EFFECT-SIZE floor kept apart from the
  confidence test because σ₀ is not the null variance of r.
- **σ₀ is along û.** Pre-registered before the second measurement: the
  no-stimulus centroid's displacement projected on the same direction
  the pair is measured on. The first cut used the full 2-D horizontal
  wander (13.3 at 60 steps) against a 1-D projection and failed the
  floor; along û it is 9.65 at 60 steps, 6.5 at 40. Apples to apples.
- **Directions from the seed.** û_i is an angle drawn from seed i, so no
  axis is privileged and a response that only steered in x would fail.
  The six directions drawn all lie in one half-plane by chance of the
  hash; the sign test does not care, and a later n can widen it.
- **The coefficient is not the lever.** Swept at 30, 60 and 100: r̄ 32.1,
  31.9, 31.2 at 60 steps. The response saturates — once the stimulus
  term dominates the heading, the centroid shift is bounded by geometry
  (the stimulus at D = 40 against a tree ~60 tall). The scene keeps 30.
- **Dose-response** (instrument, not gate): D = 10, 20, 40 give r̄ 13.5,
  23.4, 31.9 at coefficient 60 — monotonic, sub-linear, slope 0.59 per
  unit of displacement. Kept out of the gate for suite time, as agreed;
  `loam-run --tropism-sweep 10,20,40 --coeff A --seeds N --steps S`.
- **Steps: 40, not 60.** The claim holds at both (ratio r̄/σ₀ 4.0 at 40,
  3.3 at 60) because wander accumulates faster than response once tips
  go dormant; 40 is the stronger ratio at half the cost. The mutations
  skip the null runs they never assert on.
- **Mutations.** Coefficient zero: r ≡ 0 on every seed (presence of the
  mechanism). Gradient reversed (coefficient −30): every r < 0, r̄ −15
  (directionality). The asymmetry — −15 against +32 — is the tree
  bending away out of its potential sphere and stalling; it is a scene
  fact and the sign test does not depend on it.
- Cost: 18 + 12 sapling runs of 40 steps — see the parallel entry below.

## Parallel phases (2026-09-06, Christian's btop)

Christian noticed one core busy. True: only the operate phase ran over
the JobSystem, 0.02 ms of a 15 ms Debug step, and `loam-run` defaulted
to serial. Built "what we can for now" — the order-free phases — and
left the one that is not.

- **`World.jobs`**: a host's system, used by every parallel phase;
  `step` may still be handed one per call. `loam-run --threads N` sets
  it before the scene builds, so authoring is parallel too.
- **Now parallel, per brick, over `parallelRange`**: applying deltas
  (clone, add, clamp — recorded in key order afterwards, serially, which
  is what fixes everything downstream); finalize (summary and BLAKE3);
  blob authoring (entries serially, the fill in parallel through the
  thread-safe plane allocator). Requires a thread-safe allocator, which
  GPA, c_allocator and the testing allocator are.
- **The ensemble runs one world per core** on plain threads pulling from
  an atomic index — each world is its own allocator and seed, so the
  schedule cannot reach the result and the reduction happens afterwards
  in seed order. G1's serial run rides a thread beside the JobSystem run,
  which must stay on the thread that owns the system.
- **Measured** (sapling, 3652 bricks, ReleaseFast): scene build finalize
  37 ms → 2.9 ms, apply 7.5 → 3.8; per step finalize 1.31 → 0.40 ms;
  content hash identical at 1 and 16 threads (`5110f333…`, 40 steps);
  the G1 frozen reference `74cc820b…` holds in Debug with the serial run
  threaded and the JobSystem run covering the new phases. The G3
  ensemble: 18 runs in 1.5 s wall at ten cores, where it was two minutes
  serial in Debug.
- **Not parallel at first**: the seam pass (two changed bricks could
  clone and write the same unchanged neighbour) and the front pass (id
  order is the determinism). The seam pass was then the per-step cost —
  1.8 of 2.1 ms in ReleaseFast, 195 of 218 ms of the scene build — and
  went parallel the same day; see the next entry.
- **A scene edit that landed by accident.** The interrupted command that
  cut the stimulus radius to 72 had written the file before the
  interrupt; the ensemble's stimulus runs moved (r̄ 25.86 → 26.18) while
  its null runs did not, which is how it was noticed. Reverted to 96;
  the numbers above are at 96.

## The seam pass, collect then apply (2026-09-06)

Christian asked for the seam pass parallel too, and wondered whether
radix (substr's ordered map, with its lock-free `Concurrent`) could
collect the keys and stream them out ordered at the end. It could — an
ordered concurrent map is exactly "insert from every thread, read back
sorted, duplicates collapsed". It was not taken, on his word once the
cheaper form was on the table: per-thread lists and one sort do the same
with no new dependency, and substr is private where loam is public.

- **Phase A, parallel over changed bricks, read-only.** For every shared
  point on a changed brick's surface (its own boundary samples plus
  finer neighbours' hanging points), the holder set and the value each
  holder must take are computed as before, but instead of writing, a
  `SeamWrite {key, bit, idx, value}` is EMITTED — and only when the
  holder's current value differs, so the list holds real changes. Each
  job chunk owns a list; nothing shared is written. The neighbourhood
  cache resolves live pointers through the changed map, which nobody
  mutates during the phase.
- **Phase B, serial.** Sort by (key, bit, idx); walk runs by key; on a
  key's first write clone the untouched neighbour (which is what grows
  `changed` and `order`, in key order now rather than discovery order);
  apply; skip duplicates. A duplicate is the same point seen from two
  changed bricks: its holder set is the same from either side (a holder
  of p is adjacent to both), so its value is the same, and that is
  asserted rather than resolved. Pass 1 (anchor) completes before pass 2
  (hang) collects, so the hang reads anchored values.
- **Why the schedule cannot reach the result.** The write SET is a
  function of the geometry and the step-start values; the order of
  application is the sort's; clones are created in key order; versions
  are old + 1. Only the per-thread lists' concatenation order varies,
  and the sort erases it.
- **Measured** (ReleaseFast, sapling, 3652 bricks, 200 steps): content
  hash identical at 1 and 16 threads (`61533f08…`); scene build 237 →
  30 ms (seams 183 → 17); 2.12 → 0.75 ms per step. The G1 frozen
  reference `74cc820b…` holds in Debug with the JobSystem run going
  through the parallel pass. Both seam hand mutations (anchor off, hang
  off) still bite the two-gauge gate.
- **Stats.** `seam_writes` now counts distinct writes applied — a
  count that does not depend on the schedule — and `seam_bricks` the
  clones. Rejected: counting attempted writes, which would have varied
  with the chunking.
- **What is still serial**: phase B, the frontier probe, the tree
  builds. Phase B is a sort plus a walk over a few hundred writes; the
  tree builds are path copies. The front pass went parallel next, while
  it was hot — the entry below.

## The front pass, sinks merged in id order (2026-09-06)

- **Each front stamps into a SINK of its own** — deposits by brick, its
  spawns, its counts — in parallel over the JobSystem; the sinks are
  merged into the shared buffer in id order afterwards. Float addition
  is not associative, so the merge adds each front's planes in the order
  the serial pass added them, and only the samples the front wrote (a
  zero it never touched must not turn a −0 into +0).
- **The frozen reference caught a drift the serial-versus-parallel
  comparison could not.** The first cut agreed with itself at 1 and 16
  threads and did not match `74cc820b…`. Cause: Age is written ONCE per
  sample per step (birth time), and the serial pass enforced "once" by
  reading the shared entry's pending delta — the first front's write
  stopped the second's. With per-front sinks the second front no longer
  saw it and wrote again; the merge summed two birth times. The merge
  now treats Age as set-once, first in id order wins (the same front the
  serial pass let win), and the reference holds. Two runs of one binary
  agreeing is necessary, not sufficient — the second time this phase
  has said so.
- **Reads during the pass** are the step-start snapshot, the active-key
  list, the policy, and each front's own struct; the writes are the
  front's struct and its sink. `coverCube` and the neighbourhood lists
  allocate per job through the thread-safe allocator.
- **Measured** (ReleaseFast, sapling, 220 steps, 10 fronts): `f6a18875…`
  at 1 and 16 threads — Christian's own number from the previous commit;
  0.69 ms per step against 1.95 serial. Ten fronts is too few to show
  the pass's own scaling; it is there for when there are thousands.

## Renderer integration, beat 1 (2026-09-06, D1's paying customer)

Christian: "integrate it into Matryoshka while you have it all in your
head." Built on matryoshka's `loam` branch against loam `67f22c2`+, the
smallest end-to-end path, and it rendered: a tree on the grass beside
Suzanne in `test_scene`, ray-traced with its own shadow.

- **The shape.** loam is a path dependency, imported wherever spindrift
  is. `src/loam_bridge.zig` is the tenant's engine half in
  `spray_bridge.zig`'s shape: one `World` mounted at a place and a scale
  in metres, stepped on the engine's fed time, its snapshot handed to
  the per-frame DYNAMIC tree as one object per brick that holds material
  — the brick's tight summary bounds as the leaf's AABB, so the SAH tree
  does the empty-space skipping the summaries were built for, and no
  second tree goes to the GPU. The static world BVH never hears of a
  tree. Leaf type `loam = 10`; the bricks in one flat float SSBO at
  binding 50 with a fixed stride (origin, spacing, 729 samples);
  `dynamic_trace.glsl` marches the leaf's AABB at half a cell to the
  first crossing of `iso`, bisects it, and takes the normal from the
  gradient — in both walks, so the tree shades the ground and itself.
  The hit shades like a prim (inline albedo, kind 1), which is the path
  a static `.solid` leaf takes: a grown thing must look like a placed
  thing.
- **Cadence (spec §14).** The ring CA is one ring per STEP, so a step
  per frame would grow a different tree than the seedbed. The bridge
  steps once per loam second and `time_scale` is the clock ratio at the
  seam (`--loam-speed 20`: a 240-step tree in twelve fed seconds). Same
  seed, same scene, same dt: the bridge's gate lays the seedbed's tree
  hash for hash, and `[loam]` prints the content hash at exit.
- **The OOM killer was the first gate to fire.** The seedbed's scenes
  authored through `toLattice` in the domain's world units; with the
  domain in metres the growth blob's radius 56 became 1120 lattice
  units, tens of millions of bricks, and the kernel killed both the
  bridge test and the engine (signal 9, twice). Ruling taken: **a scene
  is authored in lattice units about the lattice centre** — the scene
  frame, `seedbed.sceneToLattice`, whatever the domain; only a mount is
  in metres. In the default domain it is `toLattice` to the bit, so the
  frozen reference did not move (checked).
- **The signed place.** `--loam -4,0,6` parsed the minus as a flag and
  planted at the default; the `[loam]` diagnostic line (steps, vid,
  bricks packed, objects offered, hash) is what showed it, and is what
  every beat here should print first.
- **Measured** (Debug engine, RTX 3090, 720 frames of test_scene, 239
  loam steps): 54 material bricks packed, 54 objects in the pool, GPU
  5.9 ms a frame, traversal 1.9 ms — the tree costs what a prim costs at
  this size. The bridge's gates green; the engine's suite 2579/2579 with
  one red step that predates the branch (main's `23efb70`, a control root
  reaching `../physics_probe.zig`). refs not run — Christian's rule, and
  the frozen frame is not the instrument for a scene with a tree in it.
- **What the picture showed** (Christian's pose, `--cam
  -13.77,3,5.31,0.78,-0.42`): the ring's residuals as ridges on the bark
  — the loop-loft heat view, solid; branch collars where buds left; the
  sun's shadow of the whole crown on the grass; and the tree in the green
  sphere's reflection, which the reflection walk found through
  `dynTraceClosest` without a line written for it. Christian watched it
  grow. The seedbed said it would.
- **Three artefacts, found by looking closely** (Christian's close-ups,
  matryoshka `loam` branch, second commit). Shelves, flat, axis-aligned,
  view-dependent: the pack padded a brick's tight bounds by a sample
  and, where the support touched the cube's face, that reached OUTSIDE
  the cube; the sampler clamped to the face and extruded its values as a
  slab a sample thick — "triangles poking out" that were never
  triangles. Dark bands along every seam: the central-difference normal
  reached half a cell past the face into the neighbour and, once the
  sampler said zero outside the cube, pointed every near-face normal at
  the face. Hairline cracks at seams: the march broke when its next
  step passed the leaf's exit, so a crossing in the last partial step
  was never tested, and the neighbour started inside and reported
  nothing. Fixes: bounds clamped to the cube and zero outside it; the
  normal from the ANALYTIC gradient of the trilinear reconstruction
  inside its cell; the last step clamped to the exit and tested, and a
  leaf entered already inside reports the entry. A quarter-cell step
  for the silhouettes' sawteeth. A rule from it: a leaf's march may
  reach nothing outside its own cube, for values or for derivatives —
  the neighbour holds that, and the seam contract is what makes the two
  agree.
- **What remains is the reconstruction**: trilinear facets at cell
  scale on a trunk five cells across, the field's honest resolution
  here. Christian's ensemble idea — diverge the ray near the surface —
  antialiases the silhouette (the stable temporal sampling beat) but not
  the facets; those are D2 (a finer gauge under the trunk) and D4 (a
  smoother basis).
- **Recorded, not built, with triggers:** density/extinction as a
  VOLUME with the summaries' majorants (the second capture with smoke
  or foliage); a loam leaf in the STATIC tree for a tree that has gone
  dormant (a scene with a hundred trees); brick upload by dirty set
  rather than whole (a snapshot changing under a large forest — today
  the pack re-sends every material brick when the vid moves, 160 KB for
  this tree); the tree's colour from a channel (Albedo is a channel the
  spec already names).

## Phase 2 pre-registered (2026-09-06, evening)

Christian: the representation is wrong — "materialness" should be an
SDF, material properties frequencies on that surface, and completely
continuous. Claude Chat drew the three continuities (reconstruction,
composition, deposition) and the bands; Claude Code proposed the scalar
halo with a cubic B-spline over stored gradients, the `smin` op in
front-id order, and (s, θ) as node channels; Astra (`representation.md`)
concurred on the B-spline, named band 0 a signed implicit carrier with
a Lipschitz bound rather than a distance, moved cross-gauge prolongation
to the top of D2, and corrected the (s, θ) channels into charts with
provenance blended by the collar weights — adopted, it is the better
design. The brief is `loam-phase2-brief.md`: rulings R7–R14 asked, gates
G9–G12 with their mutations, the beats and the fence. Nothing of it is
built; the brief precedes the spade.

## G13's threshold, before the spade (Sunday 2026-09-06)

Claude Chat, forwarded by Christian: G13 had a measurement — the r/h at
which a capsule's zero set vanishes, and the radius bias above it — but
no threshold, and "the threshold is yours to write before the sweep
runs. Otherwise the first result becomes the threshold, which is the G3
situation again." Written now, against theory rather than against the
instrument, and PROPOSED in `src/thresholds.zig` like every other number.

The theory: the cubic B-spline with samples as control values (R7 as
recommended, no prefilter) is Schoenberg's variation-diminishing spline,
a smoothing with leading term (h²/6)∇²φ. A tube's ∇²φ is 1/ρ, so a capsule
of radius r reconstructs with its zero set at ρ ≈ r − h²/(6r), thinned by
(1/6)(h/r)², and vanishes where the smoothing lifts the axis above zero.
`tools/g13_predict.py` (numpy, a second program — the closed form the Zig
instrument is checked against, as the diffusion gate is checked against
its variance) evaluates the full sum, worst over nine axis offsets and
three orientations: vanishes below r/h ≈ 0.78; thinned 30% at 1.0, 9% at
1.5, 4.6% at 2.0, 1.9% at 3.0. The axis value came out 0.7794h − r to four
places whatever the offset or orientation — the B-spline's near-isotropy,
which is why one number is enough for survival.

The threshold has three parts, so a bad instrument and a bad gauge fail
differently: (a) the instrument reads the prediction to ⟨1%⟩ of r with
survival matching exactly, on real bricks with halos and seams; (b)
survival at r/h ≥ ⟨1.0⟩; (c) faithful to ⟨5%⟩ at r/h ≥ ⟨2.0⟩, and
**thinner than 2h is refinement's problem** — the ruling Astra wanted the
number for. Bites predicted the same way: the gauge doubled without
refinement vanishes at 1.0 and thins 30% at 2.0 (b, c); control values
half a cell off — the indexing bug this pipeline can actually have —
reads −40%/+31% at 2.0 (a, c); trilinear in place of the B-spline
survives lower (0.71) and thins less (3.4% at 2.0) — bites (a) only, and
that is the instrument's variation record, not a defect: interpolation
keeps more of a thin feature than approximation, and is C0 for it.

What the ruling says about the tree on the lawn: the sapling's ladder is
3.0 → 2.1 → 1.47 → 1.03 by `child_ratio` 0.7, tapering to 65% at a tip, so
at gauge 0 the generation-2 and -3 twigs are below the faithful floor and
the thinnest tips (0.67) below survival. P2.1 will grow a tree whose
twigs are thinner than authored and whose finest tips are missing, and
that is the pre-registered expectation, not a bug to chase; a finer
gauge under the twigs is D2's first customer (R9). Rejected: a prefilter
(interpolating control values) — it keeps the tips but adds ringing, a
second semantics at commit, and machinery Astra asked us not to add
unless the number forces it; the number does not, it locates the
customer.

## P2.1 — the carrier (Sunday 2026-09-06, G13, G9, G10, G11, G1 again)

Christian: "Strike both. Dig." R7 (halo + cubic B-spline) and G13 (the
three-part threshold, exactly as proposed) struck; the ruling he drew
from it is the one that matters downstream — **a structural feature of
radius r belongs at a gauge with h ≤ r/2**, and below that "Loam hasn't
rendered it badly; the feature belongs at a finer gauge." The biology
can drive the hierarchy: a front that wants radius r knows before
depositing whether its gauge can carry it.

**What was built.** Every plane is an 11³ block: the brick's 9³ samples
and one halo layer beyond each face (`brick.zig`: `index` for the
brick's own samples, `bindex` for the block, `blockPoint`, `isHalo`).
Reconstruction is the uniform cubic B-spline over the block with the
samples as control values — `spline`, and `splineJet` with the analytic
gradient and Hessian; `trilinear` stays as the hanging-node rule's
interpolant and as G13's instrument variation. The summary's ranges,
support and Lipschitz bound are taken over the whole block, since the
reconstruction inside the cube is a convex combination of block
coefficients, halo included; `max_gradient` is now the root-sum-square
over axes of the largest adjacent coefficient difference (the B-spline's
derivative is a convex combination of those differences — the proof is
one line and G10 is the check), and `lipschitz` is the same for the
carrier alone. The `surface` channel (bit 16): a signed implicit,
negative inside, stored clamped to ±3 cells of the brick's gauge; +band
is "far", the absent value, and a plane whose own samples are all far is
dropped like an all-zero one (`channel.absentValue`, `isAbsent`,
`reaches`). The commit composes it: a `SurfaceOp` on the update entry is
a plane of signed distances (+∞ where it says nothing) with a collar k,
an order, and a mode — join (`smin`, far the identity) or cut (`max(φ,
−δ)`, the CSG difference a wound makes); ops are applied in order,
front id or authoring order, never summed. Fronts sweep a lofted
capsule between their previous ring and this one (`Capsule` in
`world.zig`; the front now carries `prev_*`), the profile interpolated
between the two rings' 24 slots in their own transported frames and
faded to the envelope on the axis so θ's singularity does not reach the
bound; Age is set once where the capsule is inside, Activity follows a
soft step of φ. The frontier materialises a neighbour where a face
sample is above the floor or nearer than the band. After the seams, the
HALO PASS (`reconcileHalos`): every changed brick's halo, and every
neighbour's halo entries inside its cube, recomputed by the anchor rule
one layer deeper — finest holder's sample, coarse interpolant off the
coarse lattice, absent in the void — collected in parallel as writes and
applied in key order through the seam pass's own apply. The guard
recomputes every halo from the snapshot (`HaloStale`). The sphere tracer
(`ray.traceSurface`) steps |φ|/L through the cursor's leaves. The
seedbed authors capsules; `damage` cuts. Matryoshka's leaf reads the
block with the same B-spline and sphere-traces by the object's L.

**The gates.** G13 first, as the instrument (the numbers below are what
`zig build test` prints):

| gate | measure | value | threshold | mutation | bit? |
|---|---|---|---|---|---|
| G13 | survival and r_rec/r over the sweep, three orientations, nine offsets, on gauge-0 bricks across the seams at the lattice centre | vanishes at 0.5, 0.75; 0.7022…0.8112 at 1.0; 0.9088…0.9191 at 1.5; 0.9541…0.9561 at 2.0; 0.9808 at 3; 0.9894 at 4; 0.9953 at 6 — the prediction to four decimals | prediction to 1%; survive ≥ 1.0; 5% at ≥ 2.0 (worst 4.59%) | gauge doubled → vanishes at 1.0 and 1.5, −30% at 2.0; trilinear → survives at 0.75, 0.9659 at 2.0 | yes; yes (variation) |
| G9 | 91,193 same-gauge face pairs, value/gradient/Hessian from both holders | max Δ exactly 0 | ≤ 1e-5 | no halo copy → Δ∇ 5.3 | yes |
| G10 | 19,800 random pairs in bricks with surface | 0 violations; the tightest pair reached 0.707 of its bound | 0 | L from interior axis differences → 45 violations | yes |
| G11 | 4096 rays against a dense march at h/16 | 1767 hits, 0 hit/miss disagreements, 0 late, 0 off the surface; 21.3 steps per ray; 0 overshoots, 0 stalls | 0, 0, 0, 0 | step 2\|φ\|/L → 167 overshoots in 1024 rays | yes |
| G1 | frozen reference | `aff19f32…` (from `74cc820b…`) | identical | commit order reversed (P1.6, hand) | yes |
| G2 | on tissue (inside samples) | 4181 → 5880; 19 branches; 7 young-tissue components | ≥ 3; ≥ 3; no reset | branching off → 1 component; deposit 0 → no tissue | yes; yes |
| G3 | inside-sample centroid | r̄ 25.69, lower 24.05, 6/6, σ₀ 6.12 | as before | as before | yes |
| G4 | bricks touched vs dilate 2, by identity | 78 touched, 0 outside, 2276 points regrown | 0 outside | no healing → 0 | yes |
| G5 | evals over 80 steps | 14,972 (of 584,320) | == Σ active × ops | all-regions | yes |

G13's agreement to four decimals was the halo pass's witness before the
guard was: the sweep's capsules sit on the lattice centre, a brick
corner, so every probe straddles eight bricks' seams, and the Zig
instrument reading `tools/g13_predict.py`'s infinite lattice to 1e-4
means the halos are what the neighbours hold. G9's exact zero is not
luck: at a shared face one holder is at cell 7 with t = 1 and the other
at cell 0 with t = 0, the zero-weighted coefficient contributes an exact
0, and the three nonzero products are summed in the same association —
the same sums in the same order. G10's tightest pair at 0.707 of the
bound is the root-sum-square's own slack on a flat-ish field (one axis
carries the difference; the bound allows √2 of it); recorded, not
tightened. G11's 21 steps a ray is the sphere tracer's convergence at
grazing angles; the renderer's leaf caps it and lives with the rim.

**Three bugs the gates found, and one the doors found.** (1) Diffusion's
interior stencil still stepped `N` and `N²` through an 11-stride block:
mass went 1 → 3.25 in the closed-form gate. (2) The frontier created a
fine neighbour and, later in the same loop, a coarse neighbour into the
same void — `GaugeConflict` at the tree build in the mixed-gauge seam
gate. It now collects requests and resolves them finest first through
`coverCube` against a view that holds what finer requests created, so a
coarse request over a cube fine requests are filling completes it at
their gauge. (3) The guards self-test edited a halo entry thinking it a
face sample, because `unindex` now returns block coordinates; the test
walks samples by `index`, and the halo corruption became a case of its
own (`HaloStale`). (4) The Python door and the CLI door disagreed on the
content hash after agreeing on every brick: front 1's direction, one ulp,
after a branch — `libloam.so` links glibc's libm, `loam-run` uses
compiler_rt's musl port, and the brief's "a different libm is
unmeasured" was measured. `src/fmath.zig` now owns the sim's sin, cos and
exp (musl's kernels and medium reduction, a Sun exp, pinned bits in a
test); nothing on the sim path calls a libm. The frozen reference did not
move — the port is compiler_rt's bits — and the two doors agree.

**Findings.** *Beads:* a chain of a front's own consecutive capsules
smooth-unioned with k > 0 dips k/4 at every joint, since smin(a, a) =
a − k/4 — corrugation at every ring. P2.1 deposits with k = 0 (the hard
union; the zero set of min is the union of zero sets, exact for a tube)
and records the collar as P2.2's, G12, where a gradient-gated k (blend
where ∇a·∇b disagree, not along a tube) is the candidate. *Slivers:* the
G2 mutation read three young components with one front, all at the
window's trailing edge: one- to three-point clusters born at the oldest
young step with neighbours a step older. The capsule sweep makes birth
crisp per ring, so an 8-second window cuts through one; the measure now
counts components of at least ⟨10⟩ points (a tip's is 130–250). *The
frontier and the band:* a face sample at exactly +band lets the
neighbour stay void while the reconstruction just inside the face dips
to band − h/6 — the truncation seam, ≥ 2.8 cells from any zero set, and
the tracer never visits a leaf whose surface minimum is positive, so it
sees nothing of it. *Cross-gauge:* the hanging-node interpolant is still
trilinear, so a fine face's coefficients are coarse-trilinear values and
the two B-splines agree to C0 there, not exactly — R9's D2 item, and no
scene in P2.1 has a tree across a gauge change. *The stencil rule:* a
plane is a block; nothing may index it by `N`.

**Timings (Debug, serial, seed 7, 60 steps):** 34 ms a step against
Phase 1's 15; the seam-and-halo phase 33 ms at step 60 (80 changed
bricks, 5751 halo writes), finalize 23 ms (the 11³ summary), fronts 2.6
ms. The halo pass first cost 100 ms a step through per-point holder
lookups; a slab copy for same-gauge neighbours (the value rule is the
same; the hash did not move) halved the step. The slab copy's first cut
treated a VOID neighbour cell as a copy of nothing, and the guard
caught it in the diffusion gate's point mass at a brick corner: a halo
entry at the edge of a face slab lies on the boundary between cells,
and a brick in the next cell held it. The void takes the general path,
and a brick's own halo is recomputed when any neighbour changed, not
per cell — the guard is the witness, the cache is not. Fetch count per
reconstruction: 64 against trilinear's 8 (R7 asked for the number); the
render is untroubled by it. ReleaseFast (200 steps, seed 7, one run
after the suite went green): 7.82 ms a step serial, 2.70 ms at 16
threads, the same content hash at both — against Phase 1's 0.69 ms at
16 threads. Four times the cost at the same thread count, and only 2.9×
from 16 threads: the serial parts of the commit (the two sorted apply
passes, the tree build, publish) now lead; the halo pass's general path
for the void, and the 11³ finalize, are the first things to look at
when the profile is asked for. Not a crutch: Debug is what we iterate in.

**What stays a node quantity** (R14): Growth, Age, Activity, Light,
Stimulus, Damage unchanged; Material is no longer written by fronts and
stays for volumes; the healing operator reads the carrier. The first
cut had inhibition and avoid-self read the carrier itself — and the
sapling's habit changed with it, which Christian said should be pinned
as a check rather than a look; "The habit check" below is that check,
and the reads are restored to the occupancy of the carrier.

**The look.** `matryoshka test_scene --loam -13,0,3 --loam-scale 0.06
--loam-speed 20 --cam -13.77,3,5.31,0.78,-0.42 --fixed-dt --frames 480
--shot`: 159 steps, 211 bricks packed. No facets, no shelves, no cracks,
no view-dependent spikes; smooth collars where the hard union joins;
the shadow and the reflection; and the finest tips end in nothing,
which G13 said before the code was written.

## The habit check (Sunday 2026-09-06, evening)

Christian, on the sapling growing sideways: "a representation change
shouldn't move a front. If the tree's habit changed, some read the front
does changed meaning." Pinned as a check, not a look. `loam-run --trace
FILE` writes every front's position, heading and arc length after every
step; `tools/diff_traces.py A B` reports, per front, the first step at
which two traces part by more than a hundredth of a unit and how far
apart they end. Phase 1 is a worktree at `1586b57` with the same flag
patched in; both binaries ReleaseFast; seed 7, the sapling, 160 steps,
`--consume 0.2` (the mount's).

| reads | trunk parts at | trunk apart at step 71 | fronts |
|---|---|---|---|
| P2 as committed (self-avoidance on +∇φ, inhibition on φ) vs P1 | step 2 | 24.7 | 20 vs 12 |
| both with self-avoidance off | never (0.001–0.007 over 14 fronts, births and lifetimes equal) | — | 14 vs 14 |
| P2 with the self-read restored to the occupancy vs P1 | step 3 | 4.7 | 14 vs 12 |

So every read but one kept its meaning through the change of carrier —
light, potential, inhibition, the B-spline's smoother sampling of them,
all to a thousandth — and the one that moved was SELF-AVOIDANCE. Phase 1
read −a∇Material, and Material was a contact profile: 1 inside the ring,
falling to 0 over 0.75 units outside, flat everywhere else. The carrier's
gradient is a unit vector everywhere within the band — three cells, not
three quarters of one — and radially OUTWARD inside a tube, so a front
was pushed off its own axis and branches repelled one another from three
cells away: the trunk went straight up (horizontal reach 18 against 30)
and the crown sprawled (20 fronts against 12). Restored: what a front
reads of tissue is `World.occupancy`, the carrier through the same
ramp, 1 inside and 0 beyond `SOFT` = 0.75 outside; self-avoidance is
−a∇occupancy and inhibition is occupancy one radius ahead above
`inhibit` = 0.6, both Phase 1's meanings to the number. The trunk then
tracks Phase 1's for the whole run, the same lean toward the light, the
same height (57 against 58.5), and 13 branches against 9 in G2's scene.

The residue — 4.7 units at step 71, from step 3 — is Phase 1's own
artefact, and a persistence sweep says so: no constant added to the
heading term brings the traces together (the trunk is nearest at 1.0 and
parts further at every higher value; other fronts prefer other values).
Phase 1 laid a DISC per ring, and the front read the gradient of its
own last disc's tail at its own position — an axial push of about 0.17
along the heading when the discs overlapped straight, and a turning
force when they did not, scaled by the potential it found. The capsule's
round cap surrounds the front and gives it nothing to read of itself.
That is the better meaning — a front should not steer off tissue it laid
a step ago — so it is kept, and recorded here as the one place Phase 2's
habit differs from Phase 1's by intent. The frozen reference moves for
the restored reads, `aff19f32…` → `9c83587f…`, a reviewed event.

Instruments kept: `--trace`, `--avoid`, `--inhibit`, `--persist` on
`loam-run`; `tools/diff_traces.py`. Merge is Christian's call, and now
an understood one.

## The survival floor (Sunday 2026-09-06, evening, Christian watching it grow)

"I am still seeing visible gaps in the branches … Not rendering I don't
think." Two candidates, separated with numbers before anything moved.
The renderer: loam's own sphere tracer on the grown sapling, 4000 rays
into the crown, at the shader's budget (96 steps, a hundredth of a
sample) stalled on 19 rays and reported a miss — grazing rays converge
linearly; at 192 steps and a fiftieth of a sample, none. Fixed in the
shader; speckle, not gaps. The field: a twig at r/h near 1 carries a
ring residual of up to a quarter of its radius, and where the residual
dipped the radius under G13's survival floor (0.78h) the zero set
vanished locally — the loss G13 predicted at the tips, along a twig's
length instead. Christian was right that it was not rendering.

The ruling, PROPOSED against Christian's own from the morning ("a
structural feature of radius r belongs at a gauge with h ≤ r/2"): a
front lays NOTHING THINNER THAN THE SURVIVAL FLOOR, `Params.min_radius`
defaulting to G13_SURVIVE_R_OVER_H × h of the default gauge (1.0 at
gauge 0) — the ring's radius is clamped there in `Capsule.signed`. The
demand for a finer gauge is counted, not met: `StepStats.below_faithful`
is the front steps taken with an envelope under the faithful floor (2h),
and `loam-run` prints the total as "refinement's demand". Rejected for
now: stopping a front whose envelope falls under the floor (the
principled stand-in for refinement — the tree would lose almost every
generation-3 twig in its first tenth, since 1.03 × (1 − 0.35t) reaches
1.0 at t ≈ 0.08 — kept as the alternative Christian may strike). A
happy coincidence recorded, not relied on: a twig clamped to r = h
reconstructs 25% thinner (G13's row), 0.75h, close to the 0.67h the
taper asked for. The frozen reference moves `9c83587f…` → `6677f35e…`.
The habit check re-run against Phase 1 with the floor in: the trunk and
the first-generation branches unchanged from the occupancy result; the
thin fronts move, as they must, since their tubes are thicker than
Phase 1 laid.

## The steady state (Sunday 2026-09-06, evening)

Christian: "What can we do about the step cost? Also, I notice even
after the fields converge there still seems to be a cost at steady
state, so we should fix that … stop it at source if none of the input
parameters changed." Measured first, Debug, serial, seed 7, 400 steps:

| phase of the run | active | changed a step | ms a step | of which |
|---|---|---|---|---|
| growth, step 80 | 94 | 103 | 91 | seams 46, finalize 32 |
| fronts stopped, step 120 | 49 | 74 | 60 | seams 27, finalize 25 |
| quiet, step 160 on | 0 | 0 | 0.07 | publish 0.05 |

Two sources. The quiet cost was `publish`: every step made a new
snapshot under a new vid — a walk of all 4441 nodes to count them, a
copy of the fronts — and a host reading the vid re-packed the field
for the GPU once a loam second for nothing. The larger one was the
Activity channel: a level decaying with τ = 3 s under a Decay operator,
which kept about fifty bricks changing for forty steps after the last
front stopped (a change under the floor takes τ·ln(1/ε) = 41 steps to
arrive), and during growth made most of the hundred changed bricks a
step decaying, not growing — every one of them cloned, seamed, haloed,
finalized and rebuilt into the tree.

Both stopped at source. **A quiet step publishes nothing** (`World.
isQuiet`): no active brick, no live non-dormant front, no spawn
pending, nothing authored — then no operator would run and no front
would deposit, the commit would republish the same tree, and a dormant
front cannot wake since waking needs its brick active. The clock
advances, the snapshot stands, the vid does not move, and the bridge
does not repack. (`youngComponents` reads the world's clock, not the
snapshot's.) **Activity is a touch time** (proposed, as Age is a birth
time): the fed second a front last passed, written where its sweep
reaches (`Rule.touch`: overwritten, every front this step writing the
same second), read as `now − Activity` — the healing operator asks for
a front where nothing has passed for `quiet_s` = 9 s, which is where the
old level fell under 0.05. The sapling mounts no Decay; the decay gate
keeps its closed form on Temperature. Nothing decays, so nothing churns.
Node counts ride on the nodes (`Node.nodes`, `Node.bricks`), so a
snapshot's counts are the root's.

After, same run:

| phase of the run | active | changed a step | ms a step |
|---|---|---|---|
| growth, step 80 | 34 | 35 | 28 |
| fronts stopped, step 120 | 0 | 0 | 0.00 |
| quiet | 0 | 0 | 0.00 |

The gates on the touch time: G5 5,853 evaluations over 80 steps (of
292,160 all-regions; one operator mounted now); G4 53 bricks touched, 0
outside, 1,234 samples regrown, 40 fronts (healing asks for a front
where nothing has passed for 9 s); G2 13 branches, 6 young-tissue
components; G3 r̄ 26.19, lower 24.56, 6/6, σ₀ 7.51.

A correction on the record. The suite run after the survival floor was
read as green from its log's last line, which was the exit status of
the `grep` it was piped through, not the build's; it had two failures —
G1 against a stale reference, because the shell that carried the
floor's re-baseline killed itself (its `pkill` matched its own command
line) before the edit ran, and the G4 mutation. The suite after the
steady state found both. The reference now carries every event; the
G4 mutation's instrument counts samples of the carrier inside the box
rather than the reconstruction, which smooths the cut's wall across a
cell and read 18 points of tissue where the trunk ran along it; and a
scene with no operator mounted counts as evaluated when time passes,
so the G4 mutation's season can end. Lesson for the ledger: a suite is
green when its summary line says so, never when a pipe exits zero.

Growth three times cheaper, the tail gone, the steady state free. What
is left of a growing step is the seam-and-halo phase (14 ms of 28) and
finalize (9 ms, the 11³ summary); the next two things to look at are
building each changed brick's neighbourhood once a commit instead of
once a pass (three passes now), and the summary's per-entry
`blockPoint`. (Both taken the same afternoon — "The step cost" below.) Not done: the day's frozen reference has moved four times
and each was a reviewed event; this one moves it again.

## P2.1a — attention (Sunday 2026-09-06, afternoon; G14 green and bitten, G1 again)

Built as pre-registered the evening before (R15, G14, the entry above),
first thing of the session, Christian: "P2.1a etc.. let's make this
thing fly!"

**Where the bookkeeping lives.** Two fields on the brick beside its
version — `attention` (a₀, an f32) and `changed_ns` (t₀, the fed
nanosecond) — written in one place, the commit's finalize, from the
largest change that reached the brick this commit: its own deltas and
surface ops, a seam write, a halo write, whichever was larger
(`Changed.max_delta`, which the active-set rule already read). Carried
by `clone`, so an untouched brick keeps its pair; in the brick's hash,
because under a budget the pair decides what the next step evaluates
and a world that would step differently is a different world (the G1
reference moved once for it, `5220c6f2…` → `e3068932…`, the planes,
the fronts and the active set unmoved). Copied into the brick's
summary and merged up the tree by MAX on each field separately: a
node's (max a₀, max t₀) bounds a(t) = a₀·exp(−(t − t₀)/τ) for every
brick beneath it at every t and for any τ, which is what lets a reader
choose its own τ and still reject a subtree from the summary alone —
a single merged a(t) would have fixed τ and t at the merge. The guard's
`covers` holds the parent to both. Nothing is stepped: `attentionAt`
derives the value where it is read, through the sim's own exp, and a
quiet world stays quiet.

**The budget (R15's first customer).** `Policy.budget`, a count of
bricks: the active set is scored at the step's fed time, sorted by
attention descending with ties by key, and the head is the step — its
operators run, its fronts move; the tail carries forward unevaluated
with its pair intact, and a front whose brick was carried does not
move (the front is work in its brick). `World.evaluated` keeps the
head, in order, as the instrument G14 (a) checks against. A live
front's brick re-enters the active set by the front rule whatever its
attention, so a tip that was carried competes again next step.

**The fade rule (proposed).** The first instrument run under a fixed
budget of twelve on the wounded sapling showed the tail inflating to
3,463 of 3,652 bricks by step 40 — a brick that received a seam write
of 1e-5 was carried for ever, outranked every step by fresh deposits,
never evaluated, never settled. The change floor already says what
such a change is worth: a delta under EPSILON does not activate a
brick. Applied to the tail: a carried brick whose attention has
DECAYED under the floor leaves the active set (`StepStats.faded`). Same
run after: 35 active at step 60. What this drops is work on a brick
whose last change was, by the sim's own floor, nothing by the time it
would have been looked at; R16's "a brick skipped under a cut keeps its
attention" still holds — it keeps it until it is under the floor. Ruling
for Christian, with the alternative: keep the tail whole and bound it
by the brick count.

**G14 (a), restated at build.** The brief's (a) read "evaluations == Σ
ops over bricks with a(now) > floor". Built literally that is not a
claim this system makes: the attentive set — bricks with a(now) above
the floor — is what a READER sees and it decays over τ (a deposit of 6
lattice units stays above 1e-6 for 47 s), while the active set is exact
(changed at the last commit, or a live front) and has no tail; R15
itself keeps the two apart. What is exact, and what the gate now says:
the evaluated set is the attention-ordered head of the active set,
recomputable from the published summaries alone — the gate recomputes
it at every step and compares key for key, in order — and evaluations
are ops × its size (G5's identity, graded by the budget); the tail is
the attentive remainder, counted, and the faded the rest. Forty steps
unbudgeted then forty under the fraction: 40 steps cut, 1,089 bricks
carried, 23 faded, 12 front-steps skipped (dormant fronts in carried
bricks), 5,422 evaluations. Mutation, attention ignored (every brick
iterated, G5's): 3,652 bricks evaluated against a head of tens, and
evaluations at brick count × ops. Note the mutation had to be applied
at step 41: right after the scene build every brick is active — the
blobs touched them all — and "every brick" and "the active set"
coincide at step 1, where the G5 mutation also looks; recorded, G5's
mutation not changed.

**G14 (b).** The walk (`Snapshot.attentive`) descends only where the
node's bound is above the floor and accepts a leaf on its own pair —
exact at a leaf, conservative above. Against every brick's own
bookkeeping, and against the window the claim states (now − t₀ <
τ·ln(a₀/floor), the same inequality in the other form, checked equal
away from an ulp of the floor): the same keys in the same order, at
step 80 and for a reader 5, 20 and 45 s later. Numbers, seed 7, step
80, τ = 3 s, floor 1e-6: 98 of 3,652 bricks attentive, 264 leaves
examined; 45 s later 25 attentive, 96 examined. Mutation, as the
instrument's variation: without the summaries the walk examines all
3,652 to find the same 25. By hand: `Summary.merge` dropping attention
(a parent at 0) — the walk finds nothing and the exactness fails at the
first time; recorded.

**G14 (c).** The sapling, G2's 160 steps, under a budget of half of
each step's active set: inside count 4,999 unbudgeted and 4,999 under
the budget — not within 5%, identical — with 6,119 bricks carried, 79
faded and 141 front-steps skipped (dormant fronts whose bricks were
active for a neighbour's seam write), 6,247 evaluations against 6,820.
The reason it is identical: a front's deposit is the largest change in
the world (a sample crossing the band is a delta of 2·band = 6h), so
every live tip is in the head every step, and the only operator the
sapling mounts is healing, which evaluates to nothing on unwounded
tissue — the carried half was work that would have changed nothing.
Mutation, the head in key order: 3,192, a deviation of 36% (the tips in
the upper Morton half never move again). Before the fade rule the same
mutation read +12% — MORE tissue: the inflated tail made the budget
larger in absolute terms, the frozen tips stopped crowding the
survivors, and the survivors grew longer before inhibition stopped
them. A different tree either way; the gate varies on the axis.

**Where operators matter, a budget is a different world.** The wounded
sapling, 60 steps, wound at 20, `loam-run --scene wound --damage
-10,8,-10,10,16,10@20`: unbudgeted 3,125 inside and 15 fronts;
`--budget-fraction 0.5` 3,838 and 17; `--budget 12` 1,607 and 4. Under
the half budget the wound's 48 bricks cannot all be evaluated the step
they change (budget 24), and a cut's delta is at most the band (3h)
where a deposit's is twice that, so fresh deposits outrank the
unevaluated wound bricks while healing's 9-second window runs on them:
repair spawns land later and elsewhere, and the tree that grows is a
different tree. That is the graded sleep Christian asked for — less
work, and the work chosen by where the change was largest — and it
raises a question that is his: whether a wound should outrank a
deposit. By R15 attention is the magnitude of the change, and by the
carrier's measure a cut is the smaller change. Recorded, not tuned.

**Names.** `attention` and `changed_ns` (rejected: `touched_ns` —
clashes with Activity's touch, a per-sample time; `a0`, `t0` — say
nothing aloud); `faded` for the tail's departure under the floor;
`head` and `carried` for the budget's two halves; `Snapshot.attentive`
for the walk.

**Cost.** The head choice scores and sorts the active set once a step
(a `brickAt` and an exp a brick): O(n log n) in the active count, which
the fade rule bounds by the attentive set. `loam-run --budget N`,
`--budget-fraction F` and `--budget-order key` are the instruments; the
final line prints the attentive count and what the walk examined.

**Not done.** P2.1b's units and `work(B)`; a score a front can read;
D2's criterion. (The bridge's dirty-set upload from `changed_ns`: the
next entry.)

## Attention and obligation (Sunday 2026-09-06, afternoon — Christian's ruling on P2.1a)

Christian, reading P2.1a's table and the two findings: "The two findings
and the two rulings turn out to be one distinction, so I'd rule on the
distinction rather than case by case. **Attention and obligation are
different things.** Attention is 'how much changed here recently' and is
a proxy for 'how much will change next', which is what the budget wants
to spend on. Obligation is 'something here must run regardless': a live
front, a cut brick that was scheduled and not finished. Obligation isn't
a score; it's a queue." Four consequences, each built:

1. **The fade rule, struck with an amendment.** A carried brick fades
   when its attention has decayed under the floor AND it hosts no front
   — "diffusion and decay are contractions, so a 1e-5 seam write can't
   grow into something that mattered; a front can."

2. **Two tiers in the head.** Obligations first, in key order, by
   construction and not by their decayed score; then the rest by
   attention up to the budget. "That also makes CUT mode's semantics say
   what they mean." The carried bricks ride on the snapshot as
   `Snapshot.obliged`; the live fronts' bricks are read from `fronts`.

3. **Wound versus deposit was a denominator problem.** "Attention
   measured in surface units saturates at the band clamp, so a cut is
   worth at most one band while a deposit is worth two. The wound isn't
   outranked by importance; it's outranked by a clamp." Attention is now
   scored per channel over that channel's range, the max across
   channels (`channel.attentionScale`: the carrier's range is its band
   both ways; a bounded channel's is its clamp's; a channel with no
   finite range scores its change as it is, stated; Age and Activity,
   birth and touch times, score nothing — their delta is a timestamp).
   A wound writes Damage 0 → 1 and scores 1, as a deposit does.

4. **The budget is on the transcript.** "Under budget, the tree that
   grows depends on the budget … the budget is now an input to the
   world in the same way the seed is. So it has to be on the
   transcript: a budget schedule in fed time, logged, never derived from
   wall-clock at replay." `Snapshot.budget` — the count the step ran
   under — is in the content hash beside `obliged`, in the dump, and on
   `loam-run --trace` as a `# step N budget B head H carried C …` line
   (`diff_traces.py` skips it). P2.1b's work units carry the rule from
   the start: units measured, the budget consumed recorded, replay
   replays the record.

**One refinement inside tier one, from a measurement.** Built as a
single queue — carried bricks and fronts' bricks together in key order
— G14 (c) at a budget of half the active set read 6,898 inside against
4,999, 38% off, with 386 front-steps skipped. The mechanism: at half
the active set the carried half IS half the active set, so the backlog
filled tier one every step and every front moved every other step, by
key. Tier one is therefore the sim's own agents before its backlog:
bricks hosting a live front, then bricks the last step carried, each
in key order; tier two by attention. Both are obligations; the
refinement is their order. With it, G14 (c) is the identical tree again
(4,999 = 4,999) from 5,346 evaluations against 6,820 — 22% fewer — with
5,272 carried, 24 faded and 141 front-steps skipped (dormant fronts in
carried bricks). The wounded sapling at a fixed budget of twelve bricks
a step now skips no front-step at all where it skipped 25.

**G14 after the ruling.** (a) 40 of 80 steps cut, 788 carried, 14
faded, 12 front-steps skipped, 5,107 evaluations, the head recomputed
from the snapshot alone at every step (the recomputation now reads
`obliged` and the fronts as the gate's tiers). (b) 91 of 3,652
attentive at step 80, 264 leaves examined; 20 attentive 35 s later, 144
examined — the later reader moved from 45 to 35 s because attention is
at most about 1 now and nothing stays above the floor past τ·ln(1/ε) =
41 s. The gate's mutations bite as before. G1 re-baselined `e3068932…`
→ `f410e7b3…` (the scoring, and `obliged` and `budget` in the content
hash). The wounded sapling, 60 steps, deterministic as before: 3,125
inside and 15 fronts unbudgeted; 4,266 and 28 under the half budget
(healing's evaluations of the wound land a step later, as tier one's
backlog, and more repair fronts spawn before the first ones' passing
resets the quiet clock); 3,355 and 11 at twelve a step. A different
tree under each, as it should be with the budget on the transcript.

**The walk's overhead, a standing number** (Christian: "worth logging
the ratio as a standing number, since it's the walk's overhead and it
will drift when the tree gets big"): leaves examined per attentive
brick, G14 (b) prints it and `loam-run`'s last line prints it. In
"Measurements" below.

## The strike, and P2.1b's word (Sunday 2026-09-06, afternoon)

Christian, on the refinement inside tier one: "Strike it as built:
fronts' bricks before carried bricks inside tier one. The measurement
says why and it's a semantic reason, not a tuning one. A skipped front
step is the front's clock silently halved, and clocks in Loam are meant
to be explicit channels, never a side effect of the budget. The backlog
is field settling, which can wait; the agents are what the attention is
responding to in the first place. Record the single-queue version as
the mutation for this ruling." Done: `BudgetOrder.queue` — fronts and
backlog together in one key-ordered queue, cut at the budget — is the
ruling's executable mutation, reading 6,898 against 4,999 (38% off)
with the fronts skipped 99 times where the struck order skips none.

And his word on P2.1b's two questions, which reaches back into P2.1a:

**A front step counts as a unit.** "Otherwise the budget isn't one. But
fronts are non-deferrable, so the accounting is: charge the fronts
first, then the discretionary budget is whatever remains. If the fronts
alone exceed the budget, that's an overrun the step reports, not a
skip. Gate: no front step skipped under any budget, with the overrun
count on the trace line. That keeps the honest number and the honest
semantics apart." Built into the bricks-a-step budget now: the fronts'
tier is never cut, the head grows past the budget by what they exceed
it, `StepStats.overrun` says by how much, and the trace's `# step` line
carries it. A dormant front's brick is tier zero too — its wake check
is its step. G14 (a) holds `fronts_skipped` at zero under the fraction,
then runs ten steps at a budget of ONE brick: 57 live front-steps, none
skipped, an overrun of 43 bricks, the backlog at 50 and ten consecutive
steps over budget — the shape of the corollary below, on a number.

**Under a sustained cut the backlog recycles as obligations.** "Yes,
owed work is owed. But add the corollary to the brief: under a
sustained cut the backlog grows, obligations eventually fill the whole
head, and tier two gets nothing, so the system degrades to key-order
round-robin without anybody deciding it should. Backlog length becomes a
standing number beside the walk ratio, and 'backlog exceeds the budget
for N consecutive steps' is the signal that the honest response is
slowing the world's clock rather than owing more work. That's D5's job,
not P2.1b's, but the brief should name it so the degradation is
recognised when it appears rather than discovered." `StepStats.backlog`
(the obligations carried into a step) and `World.overload_steps` (the
consecutive count) are on every `loam-run` line and the trace; the
brief names D5's signal.

**Two claims, named.** Christian, from the table: "(c) at 4999 = 4999
is an invariance result, the budget didn't change the tree. The wounded
sapling's three different trees are a reproducibility result, the
budget changed the tree and the transcript records which. Both are
correct; they are different claims, and the gates should say which one
each is making." G14 (c) is now named invariance. Reproducibility got
its own gate, G14 (d): the wounded sapling under the half budget
records the budget every step ran under (`Snapshot.budget` on each
snapshot, checked step by step), and a run fed the record instead of
the fraction publishes the same content hash, serial and over four
threads (`3fba44b4…`); `loam-run --budget-schedule` replays a trace's
`# step` lines the same way. Its mutation had to be found: a record one
brick larger at step 25 evaluated one more brick that changed nothing,
the world was invariant to it, and the final hash agreed — the
transcript differed, the state did not, which is exactly the
distinction. The record altered where it bites — the three steps after
the wound at a budget of one, so the wound's bricks wait behind the
fronts and healing lands later — publishes `475a18f4…`, and the
unbudgeted run the frozen reference.

**A residual of obligation (Christian and Claude Chat, the same
afternoon; taken, and pre-registered as R17 and G14 (e) before the
spade).** In place of the backlog tier: score the discretionary head
by pending × (1 + lag/τ), lag = now − the fed time the brick has been
owed since, so deferral costs something and staleness is bounded;
fronts stay outside the score. Three things settled against the code
before building: the product must take the PENDING magnitude undecayed
(the reader's decayed attention in the product rises at most 1.5×
before it falls — g(t) = e^(−t/τₐ)(1 + t/τ) peaks at t = τₐ − τ — so a
carried brick could never catch a region ten times hotter), the fade
rule therefore stays as struck rather than falling out, and the
owed-since time rides the active set on the snapshot rather than the
brick, because an evaluated brick that did not change is never cloned
and a per-brick "last evaluated" would be stale exactly when it
mattered. τ PROPOSED 1 s; the prediction k = ⌈(R − 1)τ/dt + R⌉ +
⌈n_cold/slots⌉ frozen as `thresholds.g14ePredictedSteps`; the brief has
Christian's statement of the guarantee — a fair distribution, not
keeping up.

## R17 — the residual, built (Sunday 2026-09-06, afternoon; G14 (e) green and bitten, G1 again)

Christian, taking it: "Yeah, I think this makes more sense because then
a fast changing area can't drag down the whole world. Well it can
impose load, but the load distribution is still fair." And the
guarantee, stated precisely, is in the brief as R17: a fair
DISTRIBUTION — every brick with real pending change served within a
bounded delay — not the world keeping up; more load than budget raises
lag everywhere, visibly, on the transcript.

**What replaced the backlog tier.** `Snapshot.active_since`, aligned
with `active` and in the content hash: for every active brick, the fed
time since which it has been owed — now if the commit that made the
snapshot evaluated it, else what the previous snapshot held, else now.
lag = now − since is the brick's clock running behind the world's. The
discretionary head is ordered by score = pending × (1 + lag/τ), pending
the brick's attention accumulated by max while it is owed and reset
when it is evaluated, τ = `LAG_TAU_S` (PROPOSED 1 s). The fronts' bricks
stay outside the score, first and never cut (struck). `Snapshot.obliged`
is gone; the backlog is `Snapshot.backlog()`, the active bricks owed
from before the snapshot's commit.

**Three things settled against the code before building** (the entry
above): the product takes the pending magnitude UNDECAYED — the
reader's decayed attention in the product, g(t) = e^(−t/τₐ)(1 + t/τ),
peaks at t = τₐ − τ at about 1.5× and falls, so a carried brick could
never catch a region ten times hotter; the fade rule therefore stays as
struck and does not fall out of the product; and the since-time rides
the active set on the snapshot, not the brick, because an evaluated
brick that did not change is never cloned. That last point bit once
while building: a settled brick re-entering the active set accumulated
its STALE pending — the attention it carried from when it was last
looked at — and owed twice. Now a brick accumulates only while it is
owed (active in the base and not in the head); anything else starts
afresh.

**G14 (e), pre-registered and read exactly.** The prediction, from the
formula written before the run (`thresholds.g14ePredictedSteps`): a
brick at pending a catches a fresh brick at R·a once lag ≥ (R − 1)τ +
R·dt, each fresh brick carrying one step of lag itself, plus ⌈n_cold /
slots⌉ steps for a batch crossing together — at R = 10, τ = 1 s, dt =
1 s: 19 + 1 = 20 steps. The fixture: two 4×4×4-brick regions of UNIFORM
change authored before every step on a channel with no range (light: a
change scores as it is), the hot one at 0.01 a sample and the cold at
0.001, no operator, no front, the budget each step the hot region's
active count (its 64 bricks and the shell the frontier gave them, 160)
so the hot region alone fills it. Result: 160 cold bricks served 480
times in 60 steps — three passes — every one at a lag of 19 or 20
steps; the cold region deferred at all (its least lag 19), never past
the bound. Mutation, the lag term zeroed (`BudgetOrder.no_lag`): the
cold region is served 0 times in 60 steps, the hot 9,440. The first
fixture was two diffusing blobs, and it failed both ways: growth's
range clamped the hot blob flat, and cold centre bricks outranked hot
edge bricks on pending alone even without lag — the score working, not
the claim; a claim about regions at a ratio needs regions at a ratio.

**The rest of G14 under the residual, Debug, serial.** (a) 40 of 80
steps cut, 960 carried, 7 faded, 0 front-steps skipped, 5,276
evaluations, the head recomputed from the snapshot alone at every step
(fronts first by key, then by score); ten steps at a budget of one:
57 live front-steps, none skipped, an overrun of 43, the backlog at 67
and ten consecutive steps over. (b) unchanged (the reader's attention
is not the scheduler's). (c) invariance: 4,999 = 4,999 from 5,866
evaluations against 6,820 (14% fewer; the tiers gave 22% — the residual
serves the backlog sooner, which is the point); the queue mutation
34.8% off, key order 36.2%. (d) the wounded sapling under the half
budget `e8d636d7…` replayed from its record serial and over four
threads; the record starved for three steps after the wound
`c68a167b…`; unbudgeted the frozen reference. G1 re-baselined
`f410e7b3…` → `019f9e0a…` (the since times in the content hash, the
pending accumulated while owed, `obliged` gone).

**The wounded sapling under the residual** (60 steps, wound at 20,
Debug, serial; the reproducibility case): unbudgeted 3,125 inside and
15 fronts; at half the active set 4,081 and 21, backlog 33 at the end,
never over budget; at twelve bricks a step 3,812 and 15, backlog 66,
59 consecutive steps over — the sustained cut the corollary names,
with no front-step skipped and no overrun (the fronts fit in twelve),
and the world's backlog rising instead: the signal, on a number.

**Not done.** The lag-weighted pending over the active set as the
single "how far behind" number Chat named (the backlog count and the
consecutive-overload count stand in for it); τ's strike; P2.1b, whose
cut bricks ride this score with lag ≥ one step by construction.

## The suite's footprint (Sunday 2026-09-06, afternoon)

Christian: "Is there anything we can do in the tests to reduce the
carbon footprint. They are taking a long time." Measured first:

| regime | compile | run | wall | hash |
|---|---|---|---|---|
| Debug, alone | 2 s | ~4.5 min | ~4.5 min | `019f9e0a…` |
| Debug, beside a loam-run and a matryoshka build | 2 s | 7 min | 7 min | the same |
| ReleaseSafe | 17 s | 2 min | 166 s | the same |

Peak memory 7 GB in both regimes — the G3 ensemble's eighteen worlds on
threads under the testing allocator, not a leak (a retired snapshot is
released at the next publish unless a reader hazards it; the world's
own reference goes with it); noted for a check, not chased. And the
cache held 241 test binaries, 3.8 GB: every `-Dtest-filter` run compiles
its own, which in Debug is 2 s and in ReleaseSafe 17 s.

Taken (Christian: "Yes, running the tests ReleaseSafe — good idea"):
the gates build at `-Dtest-optimize`, ReleaseSafe by default — the
same runtime safety as Debug, optimised — through their own module set
so `loam-run` and the seam keep `-Doptimize`, Debug by default, the
measuring regime. The suite in 166 s against 270 with the frozen
reference unmoved, which is G1's Debug-equals-Release claim exercised
on every run from now on. Every timing a gate prints names its mode
(G5's format string said "Debug" outright; it says `builtin.mode` now).
Five full suites today, one per commit, was the rule followed, not
broken; what would have saved more is fewer commits.

Not done, recorded with a trigger: the sapling scene is built about
45 times per suite (2 s each in Debug, 0.3 in ReleaseSafe) — a shared
base snapshot, retained per test, would remove most of that; and
G14 (c)'s three tests each grow the unbudgeted sapling once more (a
cached run would save two). Worth it when the suite passes five
minutes in ReleaseSafe. Runtime gate selection through an environment
variable, to compile once and run several gates, is moot while a Debug
compile is 2 s.

## P2.1b — the budget in work units (Sunday 2026-09-06, afternoon; G15 green and bitten, G1 again)

Christian: "Commit it and push, then on to P2.1b." Built from the brief's
design paragraph, written first ("The design, settled before the spade").

**The step, resumable.** `begin(now)`, `work(units) → done?`, `cut()`,
`finish()`, with the step's state on the world between calls
(`StepState`: the update buffer, the changed set, the phase and its
cursors, everything the one-piece step held as locals). Phases in
order, one unit per item: the fronts stepped into their sinks (charged
first, never cut); the operators over the head (the only phase a cut
stops); the sinks merged in id order — after the operators, one serial
unit, so every floating-point sum lands as it did; apply per entry;
the frontier's requests per changed brick; the seam pass's two
collects and two sorted applies, per brick and per target brick; the
halo's the same; finalize per brick. The serial remainders — the
frontier's pre-tree, the materialise, the scratch tree, the real tree
— one unit each, performed whole. `work` never performs more than its
units (a phase's cursor stops where they run out; a serial remainder
waits for the next call); `finish` completes what remains and counts
it apart (`units_finish`), then spawns, the snapshot, publish.
`step(now)` is the three in one. `apply()` is the same machine entered
at the apply phase. `Snapshot.cut_at` is in the content hash — where a
step was cut is an input like the budget — and the units performed
and calls taken ride on the snapshot and the trace's `# step` line.

**Three things the refactor found.** First, stepping the fronts before
the operators moved them under the operators' feet: healing's
`frontsNear` read the world's live list, saw this step's positions,
and spawned two repair fronts more (9 for 7). The operators read the
fronts AS PUBLISHED now, `base.fronts` — a step's operators read the
snapshot they step from, fronts included — and the hash came back.
Second, a latent bug from P1.2: the buffer was reset only by `step`,
so a second `apply` re-applied everything queued before the first —
10,894 of light became 21,788 in the experiment written to check it,
and the seams scene's first blob had been doubled since P1.2 (its
gates check continuity and hold either way). An authoring finish
resets the buffer now; the experiment stays as a gate. Third, and
found only when `finish` was made to reset the buffer after EVERY
commit (so a settled world is quiet at the next step, not one empty
publish later — the stale entries made `isQuiet` say no once): the
same bug was inside the G1 fixture. The wound's `apply` at step 20
authored into a buffer still holding step 19's region entries — the
fronts' deposits and the operators' deltas on the bricks it cut into
— and re-applied step 19 on the wound's bricks along with the cut.
Every frozen reference since the wound fixture was born (P1.6, the
review's "G1 watches the commit order" fixture) carried it. Shown:
the plain sapling, with nothing authored mid-run, hashes identically
on the committed binary and this one (`631a8a64…`); the wound's seven
fronts trace identically to the thousandth; only the wound's field
values moved. G1 re-baselined once more, `9fb0a200…` → `ef8ab912…`,
and that is the second re-baseline of this entry: the first for the
cut point entering the content hash, this one for a bug the fixture
had carried for a day.

**Kept exact, and shown.** The committed binary (`ff010e7`) and the
resumable one on the wound fixture: the same root hash `e6b18d7f…`,
every front's trace identical to the thousandth
(`tools/diff_traces.py`, the habit check's instrument); the content
hash moved by the new field alone. G1 re-baselined `019f9e0a…` →
`9fb0a200…`. And live: `loam-run --units 8` for thirty steps publishes
the plain step's hash.

**G15, as pre-registered, with (d) added.** (a) SPREAD exact: the
wounded sapling through `work(8)` — 40 steps in 2,282 calls, 18,100
units, none in finish — publishes the frozen reference; the same over
four threads; the same in calls of 37 (505 calls). Mutation, by hand:
the step's dt re-read from the world clock at each call instead of
held on the state — the second chunk's operators see dt = 0 and the
hash moves. (b) No call performs more than its units: the largest of
2,282 calls performed 8 of 8. Mutation, executable: the seam and halo
apply passes unchunked (`Policy.chunk_applies = false`) — the largest
call performed 53, and the world was the same: chunking is
accounting, not semantics. (The mutation did not bite at first: the
call's spent units were computed from the budget, so a pass applied
whole was capped at 8 in the accounting; units performed are counted
now, not inferred.) (c) CUT at half the head, every step of G2's 160:
the evaluated set is the head order's prefix, recomputed from the
snapshot alone, 159 steps cut, 31,105 units in finish over the run;
4,999 = 4,999 against SPREAD — invariance. The brief's mutation, the
cut in key order, cannot bite here and the ledger says why: under a
cut the fronts are outside the cut by construction and the sapling's
only operator is inert, so key order changes which inert evaluations
run. The axis the gate varies on is the fronts' non-deferrability:
`Policy.cut_fronts` lets a cut stop the front pass, and the cut landing
among the fronts reads 4,503 against 4,999, 9.9% off, 389 front-steps
skipped. (d) No front step skipped under any cut: 410 front steps
against SPREAD's 410 (the same world, so the same steps — the honest
form; "stepped == live" miscounted fronts that went dormant that
step), 0 skipped, the step's work past the calls reported.

**One decision against the code.** The head is ordered — the fronts'
bricks, then the residual's score — whether or not a bricks-a-step
budget cuts it. Without a budget the one-piece step took the active
set in key order, which was fine when nothing could cut it; a `cut`
must keep the best prefix. The sort is a few dozen entries a step.

**The bridge, feeding a count per frame** (matryoshka branch `loam`,
`--loam-units N`, `Mount.units_per_frame`). Each frame spends its
units on the step in progress first, then on the next step fed time
owes, and so on while units remain; a step spreads over as many frames
as it takes, exact; the overlay prints the units spent, the measured
cost per unit (wall-clock, for the print only — nothing of it reaches
the sim) and how many steps the world is behind fed time. The bridge's
gate: forty units a frame for sixty frames — a fraction of the
sapling's first steps, which touch every brick — completes two loam
seconds, reports itself 59 behind, 7,440 units at 4.1 µs each
(ReleaseSafe), and the two completed steps are the same root hash as
two whole steps. The lag is the honest response to more load than
budget, on a number, where P2.1a's bricks-a-step budget would have cut.

**Not done.** A replay of the calls' record in units (the transcript
carries units and calls, the cut point is in the hash, and
`--budget-schedule` replays the bricks-a-step budget — the units
schedule's replay is the same shape, unwritten); the D5 signal on
lag-weighted pending; `World.inProgress` is the one addition after the
suite that closed this entry ran, and the suite ran again for it.

## τ struck, and the overlay's lag kept (Sunday 2026-09-06, afternoon)

Christian, on P2.1b's table: "The bridge overlay reporting '59 behind'
is the lag made visible, which is the D5 signal arriving before D5
exists. Worth keeping that line exactly as it is." Kept: the
`[loam]` line prints the units spent, the measured cost per unit and
the steps behind fed time, and is not to be tidied. And R17's knob:
"τ at one second of fed time: stamp it. Fed time rather than steps is
the right unit, because the fairness bound then survives a change of
dt. And there's a consequence coming that I like: once the clock
channel exists, a stiff district accrues lag slowly in its own time,
so it's content to wait, and a fast district isn't. Fairness inherits
the clocks without anyone wiring it." `LAG_TAU_S` = 1 s, STRUCK. Order
confirmed: step cost next, then the merge — and "the overlay's '40
units a frame is two whole steps in sixty frames' is the number the
step-cost beat has to explain: whether the unit is expensive or the
count is small."

## The step cost (Sunday 2026-09-06, afternoon)

Christian, ordering it after P2.1b and before the merge: "The overlay's
'40 units a frame is two whole steps in sixty frames' is the number the
step-cost beat has to explain: whether the unit is expensive or the
count is small." Measured before anything was touched, with two new
instruments — units by phase (`StepStats.units_phase`, printed by
`loam-run --phases` with the microseconds per unit of each shape) and
the hash's share of finalize — Debug, serial, the sapling, seed 7:

| phase, at step 80 | units | µs a unit | of the step |
|---|---|---|---|
| fronts | 11 | 130 | 1.4 ms |
| operate | 34 | 0.3 | 0.01 |
| apply | 32 | 47 | 1.5 |
| frontier | 34 | 22 | 0.75 |
| seams (collect 32+32+32, halo apply 33) | 130 | 113 | 14.8 |
| finalize | 35 | 268, of which the hash 164 | 9.4 |
| the step | ~300 | | 27 |

So the answer: the count was small — the bridge's gate fed forty
units a frame on purpose, against a step of three hundred — and the
unit is cheap on average and uneven by three orders of magnitude, with
two shapes expensive: a seam collect and a finalize. And the epoch
step's 3,656 units were an accounting error: every brick the scene
build touched was active, the step opened an empty region entry for
each, and applied 3,652 no-ops as units. An entry with nothing in it —
no mask, no materialise, no spawn — is not a unit now; the epoch step
is three. G1 unmoved.

Two candidates were named in "The steady state"; both taken, one
measured first. **The neighbourhood, once a commit.** Over a hundred
steps the seam phase was 1,307 ms of which 782 was building
neighbourhoods — 60% — 18,906 of them, which is exactly one per
collect unit once the scene build's own commit (3 × 3,652) is counted:
each changed brick built its 3×3×3 cache of neighbouring leaves three
times, for the seam pass's two walks and the halo's. Built once now,
by whichever collect reaches it first, kept on the step's state, and
REFRESHED before the second walk and the halo pass: every leaf is
re-resolved through `liveOf` against the growing changed set, because
a neighbour the last apply pass cloned must be read as its clone from
then on — the cells and the view's bricks do not move, the scratch
tree being built once, so the neighbourhood keeps the view brick
behind each leaf (`origin`) and the refresh is a hash lookup a leaf.
6,302 builds where there were 18,906; the seam phase 1,313 → 1,067 ms.
Less than the builds removed (461 ms), because a cached neighbourhood
carries its origins and is refreshed twice; the honest cost of reuse.
**The summary's box, converted once.** Finalize's summary called
`blockPoint` and widened the support box once per non-absent entry,
1,331 entries a plane; it tracks the box in block coordinates now and
converts the two corners once — the clamp to the cube is monotone per
axis, so the box of the clamped points is the clamped box of the
points. The summary's share of finalize 331 → 164 ms; P1.1 (the
summary is tight), G6 and G10 unmoved, the hash unmoved.

| over 100 steps | before | after | ReleaseSafe before → after |
|---|---|---|---|
| the step | 27.1 ms | 23.5 ms | 3.61 → 3.30 ms |
| seams | 1,314 ms (builds 792) | 1,073 (builds 327) | 193 → 159 |
| finalize | 857 ms (hash 508) | 673 (hash 509) | 95 → 98 |

**A unit is a count, never a time** (Christian, on the table: "units
are uneven by three orders of magnitude, and that's fine because a
unit is a count, not a time. The budget stays on the transcript as a
count; the bridge picks how many to spend per frame from the measured
cost, which is what it does. If anyone later makes a unit 'about
10 µs' for tidiness, the transcript stops replaying across machines.
Worth saying so nobody does.") Said, here and in the rules: the
unevenness is the shape of the work, the count is what replays, and
the cost of a unit is the host's measurement to feed a count from —
never the unit's definition.

**The hash covers the canonical samples** (the question above, ruled
the same afternoon, "and not for speed"): a brick's identity is its
key, mask, version, attention bookkeeping and its own 9³ samples of
every plane. The halo is a copy of the neighbours' own samples,
hashed in the bricks that own them; hashing it again was a derived
thing in the identity — a second truth — which this house pays to
remove. G9 and `HaloStale` are the witnesses that the copy is
faithful. Blake3 kept: the pack's root hash is Blake3 over bytes, and
a cheaper leaf hash would split the sim's identity from the pack's,
"the one place two identities would be genuinely painful". The gate
for the new contract is Christian's: one halo sample corrupted, the
hash recomputed from the corrupted block is the same hash and the halo
guard fires; one own sample corrupted, the hash moves. Mutation, by
hand: the whole block hashed again — the hash moves under the halo
corruption and the gate fails. Cost: the hash 509 → 293 ms over a
hundred steps, 0.58 of what it was against (9/11)³ = 0.55 predicted
(the rest is gathering the rows); finalize 673 → 462; the step 23.5 →
21.7 ms Debug. G1 re-baselined as a reviewed event, `ef8ab912…` →
`3fd87589…`, the fifth of the day and the first that changed what the
hash means rather than what the world holds.

What is left: the seam collect itself — the walk of 386 boundary
points with a holder lookup at each — is the other expensive shape,
100 µs a unit in Debug after the cache; the instrument says where to
look next.

## The merge (Sunday 2026-09-06, afternoon)

Christian's order: "Step cost next, then the merge, in that order."
Matryoshka's `main` sat exactly at the branch point — six reviewed
commits on `loam` (the leaf and the shader from the renderer beat, the
carrier's sphere tracer, the dirty upload from `changed_ns`, the
per-frame count of units), nothing new on `main` — so the merge was a
fast-forward with no conflicts: `main` is `f6371d7`, pushed; 157 of
157 build steps, the bridge's thirteen tests. His ruling from the
carrier's day held to: "merge once it's understood, not once it looks
fine" — the habit check, the residual, the fronts read as published,
and the buffer consumed were the understanding. The `loam` branch
stands, identical to `main`, until he deletes it.

## P2.2's brief struck (Sunday 2026-09-06, evening)

Christian: "The third answer is the right one, and it's right for the
reason it gives: the beads come from a front unioning into itself, the
collar is wanted only where a child meets its parent, and provenance
already knows which is which. No gradient, no spine, R12a intact.
Strike it, with one amendment and one number to record." The amendment
— hard only into own RECENT deposit, "own front, within the last m
segments", self-touch after m rings being another front for collar
purposes, m chosen from the ring spacing — and the number — the inner
elbow of a hard chain, a concave fold with a gradient jump of about
the bend angle between rings, to be measured once on the sapling and
on a deliberately tight curl and held in this ledger as the spine's
trigger — are in the brief in his words, with `COLLAR_RECENT_SEGMENTS`
(a placeholder until the sweep's geometry chooses it) and
`G12_GRADIENT_TOL` (PROPOSED, float slack) beside the other numbers.
Everything else stands as written. Nothing built: "Let's wrap it up,
and open with fresh heads for P2.2."

## P2.2 — the collar, provenance and the bands (Sunday 2026-09-06, night; G12 green and bitten, G1 again)

Built from the brief as struck, with three things found on the way that
changed what was built, each recorded here with the number that found
it. Christian's amendment (hard only into own RECENT deposit) and his
number (the inner elbow) are both in; the one place the letter of the
strike was not followed is named first.

**The recency window is arc length, not a count.** "Own front, within
the last m segments" is built as "own front, within the collar's REACH
behind the capsule's start ring, along the arc" — `thresholds.collarReach`,
√(k² + 2ρk) with ρ the tube's radius out to the band's edge: the
distance behind a ring at which the new capsule's start cap is within
k of the tube's own distance, beyond which smin IS min. The reach is
derived from the geometry, as he asked m to be, but a count of segments
is a function of dt (the trunk's 6.7 units are seven rings at dt = 1 s
and fourteen at 0.5 s) where the arc is not — the reason τ was struck
in fed seconds. `segment` is stored as struck and read by the bands;
the window reads `chart_s`, which is stored beside it. His to strike
back to a count if he wants one.

**The brief's observable did not exist.** "|∇φ| continuous to 1e-3
across the junction" was withdrawn before any gate ran: the
reconstruction is the cubic B-spline of the samples and is C2 whatever
they hold, so a crease and a fillet both reconstruct smooth and the C1
of the smin cannot be seen through it. `G12_GRADIENT_TOL` is gone. G12
is bit-exact instead (below), and the crease is a measurement.

**One slot was not enough, and the gate said so.** The first build kept
one contributor per sample, as the brief proposed: a capsule unioned
hard into samples its own front laid recently and smooth into the rest,
the winner writing its provenance. G12 (a)'s bound — the collared field
is under the hard union by AT MOST k/4, the smin's own limit — failed
at 1.46 against 0.75: a child arrives as a chain of capsules and each
one smooth-unioned AGAIN into the same parent-owned samples, so the
fillet at a junction was the sum of three or four collars and would
deepen as capsules shortened — a representation defect that depends on
dt. That is the case Christian named the two-slot form the fill for
("G12's mutation is what tells you when to pay for it"), and it is
paid: every sample keeps `own` (the nearest contributor's own signed
distance, before any collar), `other` (the runner-up's) and `collar`
(the join's k), and band 0 is their ONE smooth union, recomposed by the
commit whenever a slot changes. A front's capsule goes HARD into `own`
where the sample is its own recent deposit; a nearer stranger takes
`own` and demotes what stood to `other`; a farther one joins `other` by
the hard min — so a chain of a child's capsules is one tube in the
runner-up slot and the parent meets it once. The join's k is the least
willing member's, min over the ops that touched the sample: a child's
radius at the join is the smaller of the two, and a hard front makes a
hard join. A cut writes no provenance (the scar remembers who grew
there — Christian) but cuts both slots, so a later join recomposes
from cut tissue. The third contributor at a three-way junction is lost
into `other` by the hard min: the two-slot limit, stated. The largest
drop then read 0.520 against the child's k/4 of 0.525.

**The seam pass was waking the neighbours.** A seam copy of a `who`
sample — nobody to front six — counted as a change of six toward the
active-set floor, so every brick beside a tube woke for nothing: G14
(c)'s budgeted sapling evaluated more than the unbudgeted one, and the
key-order mutation stopped biting (3.8% against the 5% floor). The
floor and attention now count what the world reads — the carrier and
the additive channels; the slots and the provenance are the carrier's
bookkeeping, scored where the carrier is. G14 (c) reads 5050 = 5050
from 12.6% fewer evaluations again; key order loses 34.7%.

### What was built

- Seven channels: `who` (front id plus one; zero is nobody), `segment`,
  `chart_s`, `chart_theta` (the chart's (s, θ) at the sample's foot on
  the capsule's axis, θ lerped the short way round between the two
  rings' frames), rule `.set_by_winner`; `own`, `other` (rule
  `.distance`: far absent, band-clamped, interpolated across a hanging
  node like the carrier) and `collar` (nearest across a hanging node:
  an id between two ids is a third front, and so is a k). None is ever
  a delta (`RegionUpdate.delta` asserts); none reaches across a face
  for the frontier; none scores attention. A front's `SurfaceOp`
  carries who, segment, the start ring's arc and the reach, and two
  chart planes; an authored op carries none and writes `own`/`other`/
  `collar` only.
- `Params.collar` is now a FRACTION of the ring's envelope, default 1
  ("the child's radius at the join"); 0 is the hard union everywhere
  and the G12 (a) reference. `Params.coil`: a fixed turn of the heading
  about the scene's vertical per unit of arc, the elbow measurement's
  knob. `Front.segment` and `prev_s` (in the canonical bytes).
- The ring history — `World.rings`, per front, ring zero the seed,
  appended by the commit in id order from the front pass's sinks; a
  `Ring` is 224 bytes (pos, dir, normal, roll, s, envelope, the 24
  residuals and tags, the slot that budded). Not in the content hash:
  it is the fronts' past, which the hashes of the steps that made it
  hold; nothing on the sim path reads it. `Capsule.between(a, b)`
  rebuilds the sweep from two rings with the same arithmetic the front
  used (`Capsule.of` goes through it), and `foot`/`chartS`/`chartTheta`
  are the one place the chart is computed.
- Bands: `World.bandQuery(snap, p, class)` — `.sponge` reads band 0 and
  gathers `G12_SPONGE_BYTES` (256, the plane's 64 coefficients as G7
  counts them) and nothing else; `.bark` reads the four provenance
  samples and the ring records, band 1 the residual at the chart
  (lerped between the ring and the one before), band 2 its second
  difference along s, and whether the slot at θ budded here (a scar).
- `Policy.collar_gate`: `.recent` (struck), `.none`, `.own` — the two
  executable mutations; `loam-run --collar C`, `--collar-gate G`; two
  scenes, `--scene junction` (a straight parent with the ring CA on, no
  steering; its child budded by hand at step 12 through `seedbed.bud`)
  and `--scene coil` (a tendril at 0.25 rad per unit, radius 2, rising
  3.75 a turn so its turns touch); `collar acted on N samples;
  provenance written at M` on every reported step. Matryoshka's mount
  takes the same (`--loam-scene junction|coil`, `--loam-collar 0`,
  matryoshka `bb1e66f`); Christian's side-by-side of the sapling read
  the difference in the crotch of each fork and nowhere else — "quite
  subtle, but it is supposed to be".

### G12, as it stands (ReleaseSafe, serial)

| gate | measure | value | threshold | mutation | bit? |
|---|---|---|---|---|---|
| G12 (a) the collar | the collared junction against the same scene under the hard union (straight fronts, so the tubes agree): samples higher; lower outside the child's zone (its radius + band = 6.00 of its axis); the largest drop | 1,341,360 samples; 468 lower, 0 higher, 0 outside; drop 0.520 | 0; 0; ≤ k/4 = 0.525 (the join's k 2.10) | `.none`: nothing is its own → 9507 lower, 5813 outside the zone, beads of 0.750 along the parent's chain | yes |
| G12 (a) the amendment | the coil after 80 steps against its hard chain | 2353 lower, 0 higher, drop 0.500 = k/4; the collar acted on 21,165 samples | > the first 20 steps' count; 0; ≤ k/4 | `.own`: its own at any age → 0 lower, the collar acted on 0 | yes |
| G12 (b) the bands | every provenanced sample: the capsule rebuilt from the ring records at (who, segment) against `own`, the chart's s and θ; the carrier never above its slot | 10,126 of 10,126 exact; 0 chart mismatches; 0 above; 468 collared under | all; 0; 0 (`G12_BAND_TOL` is 0) | by hand: θ taken in the start ring's frame at every foot → mismatches wherever the frames twist | yes (hand) |
| G12 (b) the scar | a cut across the parent: provenanced samples before and after, raised above their deposit, charts | 10,126 → 10,126; 223 raised, still the parent's; 0 mismatches | equal; > 0; 0 | — | — |
| G12 (c) the sponge | bytes a band-0 query gathers; a bark query's least | 256; 720 (907.9 on average) | = 256; ≥ 256 + 16 + 2·224 | by hand, the class ignored → a sponge pays for the bark | yes (hand) |

(b)'s exactness is the two slots' doing: `own` is the winner's own
distance and no collar ever lowers it, so the recomputation is exact
at every sample and not only outside the collars, which is what the
one-slot version would have had to settle for. The hand mutations
were run once each and reverted.

### The inner elbow, measured (Christian's number)

Rays from a ring's centre in the plane of the bend, ±40° about the
inner bisector, to the reconstructed zero set; the B-spline gradient at
each hit; the largest turn of the normal between neighbouring hits per
lattice unit of their separation, against the median turn over the
sweep — the surface's own turn there, so the fold reads as an EXCESS.
The same in every build mode.

| elbow | bend per ring | fold, °/unit | baseline | excess | the tube's 1/r |
|---|---|---|---|---|---|
| sapling trunk, its sharpest ring | 21.30° | 10.44 | 5.80 | 4.63 | 18.1 |
| sapling trunk, its median ring | 10.17° | 18.02 | 4.31 | 13.71 | 21.6 |
| the coil, 14.16° a ring (radius 4, tube 2) | 14.16° | 35.82 | 27.39 | 8.43 | 28.6 |
| the bud junction, hard (k = 0) | corner 45.84° | 194.84 | 2.01 | 192.83 | — |
| the bud junction, collared (k = 2.10) | corner 45.84° | 111.33 | 3.06 | 108.27 | — |

Read against his question: a hard chain's inner elbow at the coil's
14° a ring is a fold of eight degrees per unit over the wall's own
turn; the sapling's trunk elbows (10–21° a ring) are under its bark —
the median ring's excess is the ring CA's own relief, an impulse, not
the fold, and the sharpest ring folds inward past its own radius (a
bend radius of 2.7 under a tube of 3). A bud's hard crease is 193°/unit,
an order of magnitude above anything a chain makes, and the collar at
the child's radius halves it. The spine's trigger stays PROPOSED as
`elbowTrigger` = h/r with this against it: the trunk's sharpest bend
(21°) exceeds h/r (18°) and its fold is still invisible, so the formula
is too strict; the number to watch is the excess, and nothing in these
scenes brings a chain within a decade of a junction's crease.

### The coil's inner wall — the arc rule's limit

In the coil's first 20 steps, before any turn could touch, 213 samples
of its own inner wall were collared: at a bend radius of 4 the tube
five to seven rings back is within the collar's Euclidean reach (the
chord) while beyond its arc reach, so the rule reads it as another
front. A coil tighter than the collar's reach cannot be told from a
self-touch by any window in arc; recorded, printed by the gate, not
gated. A tube whose bend radius exceeds the reach (the sapling's) is
unaffected.

### The habit check

`loam-run --trace` on both sides, `tools/diff_traces.py` between:

- the new build under `--collar 0` against the previous commit's
  binary: every front agrees to the last digit over 40 steps
  (separation 0.000), the inside count 1755 in both, growth to the
  thousandth. The representation change did not move a front.
- the collar against the hard union: the trunk moves 0.004 units by
  step 40; the two children, born at steps 26 and 38, diverge at step
  39 by 0.034 and 0.214 — what a newborn child reads one radius ahead
  is the fillet, which is real tissue. At 100 steps the sapling holds
  4966 inside samples against 4914 hard; the collar acts on 300–400
  samples a step once the buds are out.

### The cost, and G1

The step cost, sapling seed 7, 100 steps, serial, `loam-run --phases`:

| build | previous commit | this build, `--collar 0` | this build |
|---|---|---|---|
| Debug, ms/step | 21.49 | 38.88 | 40.29 |
| Debug µs/unit: apply / seams / finalize (hash) | 45 / 92 / 149 (96) | 112 / 154 / 411 (231) | 100 / 155 / 419 (241) |
| ReleaseSafe, ms/step | 2.96 | 4.98 | 5.18 |

Seven planes on every brick a front laid — twelve where there were
five — and every pass that walks planes pays in proportion: the clone
at apply, the seam collect, the hash. The collar itself costs 1.4 ms
Debug (the junction bricks keep changing while a child's chain
extends: seam units 97 → 148 at step 100). Candidates, none taken: the
seam collect reads seven bookkeeping planes whose shared points both
holders already hold from the same op; `own` duplicates `surface`
wherever `other` is far; `who` and `segment` would pack. About 37 KB
more per tissue brick.

G1's reference moves, `3fd87589…` → `d64a1b0f…`: the seven planes and
the fronts' two new fields are in the hash, and the sapling's children
now collar into the trunk. The suite: 87 gates, 238 s ReleaseSafe;
`verify-dump` (the seven planes named in the dump, the two slots read
as distances) and `py-test` (G1 across two processes) pass; the
matryoshka bridge's three tests pass unchanged against the new leaf
(it reads `surface` by bit; the stride did not move).

### Open

The cost above — pinned, not taken (next entry). The two-slot limit at
a three-way junction. The coil's inner wall. `elbowTrigger`, for
Christian: the measured excess against h/r. The arc window against his
count of segments. From before: a units-schedule replay; the D5 signal
on lag-weighted pending; the shared sapling fixture.

## P2.3 — the picture: what a hit reads (Sunday 2026-09-06, night; G16 green and bitten, G1 again)

Built from the brief as struck — fade, don't cut; the collar seam right
for band 1 and wrong for band 3; the octaves in world units; the arc
approximate across a bend; a prediction before the run — with the
prediction frozen first (`thresholds.G16_PREDICTED`) and then read by
the gate at every row. What a hit reads is `src/bark.zig`, the CPU
reference of the shader term for term, with the planes and bytes it
touches counted; the shader is matryoshka's `loamBark`.

**The prediction, and where it differed from the sketch.** Written
from the fade and the struck scales before anything ran: a close read
(footprint under 0.125) touches six provenance planes — who, chart_s,
chart_theta for the chart, own, other, collar for the collar's weight —
and the ring table; a mid read (0.5 to 1.0) three (who, chart_s,
chart_theta) and the table, bands 1–2 alone; a far read (1.0 and
beyond) none. Christian's sketch had the middle the other way (two
planes, band 3 only): that needs the microstructure coarser than the
ring pitch, and with the octaves struck at 0.5 and 0.25 it is finer —
the middle regime is the bark's history without its grain. The run
read the table at every row: 6 and the table at 0.1 and 0.3, 3 and the
table at 0.6 and 0.9, none at 1.2 — as predicted. Inside a collar the
count is different and was not in the table: five for the chart alone
(own and other decide the seam, below), six with the collar for the
grain.

**Four things the gate found before it passed, each a real defect.**

1. *The chart's foot was clamped.* A sample in the cap behind a
   capsule's start read the cap's s and roll, not the arc it lay
   beside; a ring whose bark bulged won samples axially behind it (its
   cap nearer than the previous capsule's side), and the chart jumped
   by up to a ring along a STRAIGHT tube — |Δs − Δarc| 0.15 against
   1e-3 on the far side, and θ 0.0185 off (the drift over a ring). The
   foot is unclamped for the chart (`Capsule.chartS`, `chartTheta`
   through `s_raw`) and clamped for the distance as before; the far
   side then reads 1.5e-5, 3e-7, 5e-7. G1 moved for it.
2. *The spline mixed two fronts' charts.* Read over all 64
   coefficients, `chart_s` beside a junction interpolated the parent's
   arc with the child's and read 12.9 where the arc was 15. The chart
   is read over ONE front's samples — the spline masked by `who` and
   renormalised, a partition of unity over one chart — which is what
   R12's "charts, not fields" means at a read. Its cost: a one-sided
   mask loses linear precision, and inside a collar's zone the chart is
   off by up to 0.080 in s and 0.060 rad in θ (the junction scene),
   under a ceiling of half a unit (`G16_MASK_BOUND`, PROPOSED; the
   theory bound is the support's half-width, 2h) and printed, not
   float slack. The seam's own width, where a ridge is anyway.
3. *`who` nearest put the seam on the sample grid.* The chart switched
   where the nearest sample's owner changed, up to most of a sample
   from where the two fields cross, and the grain was 86% present at
   the switch. The two-slot form fixes it: each front's field can be
   rebuilt at the hit from the slots (its distance is `own` where it
   won a sample and `other` where it did not — `bark.fieldOf`), the hit
   belongs to the nearer, and the seam is the crossing. At the flip
   the fields were 0.026 apart.
4. *"Bare" read literally left half the grain.* (1 − w_runner-up) is
   the winner's smooth-union weight, one half where the two fields are
   equal; the fan read bare 0.513 at the crossing. `collarBare` is the
   DIFFERENCE of the two weights, tanh(k(other − own)/2): zero at the
   crossing, one away from any collar. Christian's amendment read as
   its intent, "smooth and bare"; his to strike.

### G16, as it stands (ReleaseSafe, serial; the junction scene)

| gate | measure | value | threshold | mutation | bit? |
|---|---|---|---|---|---|
| G16 (a) the chart along a tube | probes every quarter unit along the parent's far generator (θ at π) and its junction generator (θ at the wrap): s against the arc, θ against the roll's drift and against the chart itself; `who` where it changes | far: 94 pairs, |Δs − Δarc| 1.5e-5, |Δθ + drift·Δarc| 3.0e-7, |θ − chart| 4.8e-7; junction side outside the zone: 51 pairs, 2.5e-5, 3.6e-6, 5.3e-6; inside: 33 pairs, 0.080 and 0.060; `who` changes twice, 23 child-owned hits, 0 outside G12's zone; non-integer `who` 0 | 1e-3 (STRUCK, float slack); inside the zone 0.5 (PROPOSED ceiling); 0 outside; 0 | θ as an angle → 1.047 rad off at the wrap; `who` interpolated → 45 non-integer ids | yes; yes |
| G16 (a) across the collar | a fan of 162 rays from the void above the junction, over the fillet from the parent's surface to the child's: the bent normal's turn over the unbent's and the bump's own curvature; at the flip, the grain's bareness and the bent normal's distance from the unbent | excess 0.000 rad; at the flip bare 0.028, the bent normal 0.002 rad from the unbent; bare down to 0.026 across the fan | ≤ 1e-3; bare ≤ tanh(k·sep) = 0.069 | band 3 not faded at the collar → bare 1.000, the bent normal 0.091 rad off | yes |
| G16 (b) the footprint | one hit with real bark, footprints 0.05 to 2.0 by 0.01: bytes; records fetched iff a band has weight; a sponge; band 1's change between neighbours against the fade's own slope; the prediction's rows | bytes monotone; exact; 256 everywhere; largest jump over the bound 0; every row as predicted | monotone; iff; 256; ≤ 0 | the footprint ignored → 1960 bytes at 1.5 as at 0.1; the hard cut → band 1 −0.065 then 0 across its scale | yes; yes |

### What was built

- `src/bark.zig`: `Rules` (each `false` a mutation), `chartAt` (who
  nearest, or by the fields where two fronts laid the neighbourhood;
  s and θ by the masked spline, θ from cos and sin), `read` (the bands
  by footprint with `thresholds.bandWeight`, band 1 from the ring at
  the arc found by binary search on the front's rings, band 2 its
  second difference, bands 3+ smoothstep value noise on (θ·r, s) at
  the octaves — WORLD units through `domain.cell()` — bared by
  `collarBare`, the normal bent by the relief's gradient in the chart's
  tangent frame ∇s, r∇θ), the bytes as G7 counts them. `World.dt_s`
  for band 2's scale; `Brick.splineJet1Mapped`, `Brick.locate` public.
- Thresholds: `G16_CHART_TOL` 1e-3 STRUCK; `bandWeight` (the mip
  rule); `collarBare`; `BARK_OCTAVES_W` 0.5, 0.25 STRUCK in world
  units; `BARK_AMPLITUDES_W` 0.05, 0.025 PROPOSED; `band1Scale`;
  `bendSlope`; `G16_MASK_BOUND` 0.5 PROPOSED; `G16_PREDICTED`.
- Matryoshka (`loam_bridge.zig`, `dynamic_trace.glsl`,
  `traversal.comp`, `vk_renderer.zig`, `dynamic_bvh.zig`,
  `common.glsl`): the stride 1336 → 10652 — eight planes a brick, the
  carrier then chart_s, cos θ, sin θ, who, own, other, collar (the
  distances in metres): 42.6 KB a brick against the struck 6664,
  because the collar's weight at the hit reads the two slots and their
  k; a one-plane bake of the weight is the named alternative. A ring
  table in a second SSBO (binding 51, 1.7 MB allocated; the front
  count, the bark's material, a row a front, 26 floats a ring;
  rewritten whole when a ring was added — some 200 KB for the
  sapling). `loamBark` at a hit: the same reads, the footprint from
  the pixel's cone at the hit's distance, band 1 darkening the albedo
  (`bark_darken` 0.8 per lattice unit of residual, clamped to 0.5–1.3),
  bands 3+ bending the normal. The material in METRES on the mount:
  octaves 3 cm and 1.5 cm, amplitudes 3 mm and 1.5 mm — grooves on a
  fifteen-centimetre trunk. `--loam-no-bark` for the side-by-side.
  The bridge's three tests pass; the picture is Christian's eyes.

### Numbers

The regression line, re-measured: 5.21 ms a step ReleaseSafe on the
sapling (5.18 pinned; the sim path gained the chart's unclamped foot
and nothing else; noise). G1 `d64a1b0f…` → `60b27f31…`, the chart
planes alone. The suite: 94 gates. The frame time of the close-up
against the plain sapling is not measured here — the overlay prints
it, and Christian's machine has the GPU.

### The first look (Christian, the same night)

"For a first attempt it looks amazing." Up close, speckle and hard-
edged black blobs; farther back, strips across the trunk. The speckle
and the blobs were two unit slips in the shader and an index: the
chart's gradients are per metre and s, r in lattice units, so the
bump's tangent frame is ∇v = h∇s and ∇u = r·h·∇θ — without the h both
directions were sixteen times too strong at six centimetres a unit,
and the normals flipped (the CPU reference works in lattice units
throughout and never had it; the two agree term for term only when
the units do). Band 1 darkened per lattice unit of residual, which
runs to a whole unit on the trunk, so grooves saturated the clamp into
blobs — it darkens as a fraction of the ring's envelope now. And the
nearest sample for `who` read block i where sample i sits at block
i + 1. Matryoshka `a30109a`. The strips are band 1 read across rings:
the loft table lerps linearly from ring to ring, so the relief is C0
along the arc, a kink at every ring — a Catmull-Rom over four rings is
the fill, recorded not built, with its trigger: the strips still read
after the darkening moved to the envelope. "Some seams but I think
that's okay."

### The scaffold question, and the field mode (Christian, the same night)

"I don't understand why the lofting rings even come into it. Those are
just a scaffold. The point of loam is the gradient field. There should
be no connection between the scaffold and the texture." He is right,
and the strips were the evidence: band 1 as built re-reads the ring's
residual, which the capsule already deposited into the carrier — at
this gauge the slot pitch is 0.8 against a lattice of 1, so it adds
nothing the field does not hold, and what it adds is the scaffold's
own artefacts. The only genuine history in the ring table is the
event: a bud that left, a cut. He sent Pixar's SIGGRAPH 2023 talk
(Bartsch, Thompson, de Goes, "A Procedural Approach for Stylized Bark
Shading"): a smooth tangent DIRECTION FIELD over the trunk from artist
strokes, streamlines advected along it, baked to Ptex — no history at
all, the direction field is the texture. Loam has that field for free
from the carrier: the Hessian at the hit gives the principal
directions of the level set, and a tube's axis is its direction of
least curvature. Pixar's strokes exist because a mesh has no Hessian
to ask.

Played, not briefed ("no brief for just an experiment, as long as
the base is committed and pushed"): matryoshka's `--loam-bark-mode
field` — the frame from the Hessian, the grain stretched four to one
along the axis, even in the frame's signs so no flip leaves a seam;
reads nothing but the carrier. No strips, no seams, no chart, no ring
table, no provenance planes: the bark read's cost in that mode is the
carrier's own 64 coefficients twice. Rendered headless beside the
chart mode at the same three cameras; his to judge. The chart keeps
one thing the field cannot give — a coordinate that follows matter
that moves in place — which nothing in loam does yet, and the history
proper (who, the scar) stays provenance.

His document on materials as loams, read the same night: an archetype
is a small loam world grown from processes — M(x, t_f) = Φⁿ(M₀, E) —
with the low bands stored history (rings, veins, plates) and the
higher bands procedural conditional on them; three levels, static,
developed, living; and the nested chain planet → geology → materials
→ terrain → life → weathering, "the same conceptual machinery at
different scales". Read against P2.3: the archetype's history is its
OWN field, attached to a surface through what the surface gives at a
hit — φ as depth, the Hessian's frame as orientation — never through
the sweep's scaffold. The bark's bands 1–2 were the scaffold standing
in for an archetype that does not exist yet. "An isolated material
seedbed would be a cracking experiment once P2 has settled."

### Struck: the field is the bark's frame (Christian, the same night)

"That looks a lot better! More importantly I much prefer the
loam-first approach that is more in line with my vision for it. And
yes, I'd definitely say the living material takes a back seat to the
cheap version." So: the grain's frame is the level set's own, from
the Hessian at the hit; the chart is for what only history can say.
Matryoshka's mount defaults to `field`. Of the three levels in his
document, the developed archetype — grown once, frozen, hashed,
sampled by footprint — comes first, and the living material waits.

The consequence for the cost beat, which is now the fact P2.3 was
for: in the bark's mode a read touches NO provenance plane — the
carrier's 64 coefficients, twice. `chart_s` and `chart_theta` have no
reader left but the collar's recency window (`chart_s`) and G12 (b)'s
exactness gate. That reopens Christian's original count of segments
for the window — the ring table holds the arc of every segment, so
"own front, within the reach" can be asked through `segment` alone,
dt-safe, and the two chart planes could go — and it leaves `who` and
`segment` for the events (a scar, a cut) and `own`, `other`, `collar`
for the collar. Five planes where there are seven, and the GPU stride
back toward 1336 with a ring table beside it. Candidates, none taken
tonight; the regression line stands at 5.21.

## The cost beat (Sunday 2026-09-06, late night; the conn Christian's, then mine — "your call to get it done as a test")

The bark said what it reads, and the sim followed. What went and what
held, each with its number, all gates green before any of it was
kept.

**The two chart planes are gone.** `chart_s` and `chart_theta` had
one reader left in the sim, the collar's recency window, and one in
the gates. The window now asks the ring table: a sample's `segment`
names its capsule, the table holds that capsule's end arc, and the
window is the reach behind the new capsule's start — Christian's
"own front, within the last m segments", m read off the arcs, so it
survives a change of dt. The end arc, so every sample within reach is
inside the window and a span's tail at most a ring beyond it, where
smin is min anyway. G12 (a) reads exactly what it read with the chart
plane: 468 samples lowered, none higher, none outside the zone, the
largest drop 0.520 — the same collar to the sample. Five provenance
planes where there were seven: who, segment, own, other, collar.

**The chart at a read is the capsule's foot, exact.** `bark.chartAt`
takes `who` and `segment` nearest (a sample each), rebuilds the
capsule from the ring records, and takes its foot at the point — s
and θ exact, their gradients from the capsule's own geometry, no
interpolation of anything. G16 (a) along the parent's generators: |Δs
− Δarc| = 0.00 exactly and |θ − chart| 4.8e-7 on both sides, through
the collar's zone as well as beyond it. The one-sided mask and its
ceiling (`G16_MASK_BOUND`) are gone with the planes they masked. The
seam between two fronts is still the fields' crossing from the two
slots; the mutations: `who` interpolated → 45 non-integer ids, the
segment interpolated → 101 non-integer segments (its s stays exact,
since any capsule's unclamped foot is the arc — the mutation bites on
the id, as recorded).

**The bark reads nothing but the carrier.** `bark.read` in the field
mode: the Hessian at the hit from the same 64 coefficients, the
principal frame (`principalFrame`, unit-tested on a tube), value
noise in that frame stretched `BARK_STRETCH` along the axis and even
in the frame's signs, the normal bent in the frame. The prediction
frozen before the run (`G16_PREDICTED`, both modes) read at every
row: the chart mode two planes and the table at 0.1 through 0.9 and
nothing at 1.2; the field mode zero planes at every footprint. The
fan across the crotch in the field mode: the bent normal's excess
turn 0.000, zero provenance planes; in the chart mode, bare 0.028 at
the flip against 0.069 as before.

**The GPU is the carrier alone.** Matryoshka `eff67ff`: the stride
10652 → 1344 — one plane behind a 12-float header carrying the
bark's material (octaves and amplitudes in metres, the darkening,
on/off, the stretch); the ring table, its binding and the chart mode
are gone with `--loam-bark-mode`; the grooves darken by the grain's
own relief. The struck stride of 6664 is passed on the way down, not
on the way up.

| the regression line, sapling seed 7, 100 steps, serial, ReleaseSafe | pinned | now |
|---|---|---|
| ms a step | 5.18 (re-measured 5.21) | 4.49 |
| seams / finalize / hash, ms over the run | 265 / 159 / 96 | 234 / 129 / 78 |

G1 `60b27f31…` → `6b7f4a8f…`, the two planes alone. 95 gates, 240 s
ReleaseSafe; `verify-dump` and `py-test` pass; the bridge's three
tests pass; the close-up rendered headless and sent.

### Unified to PBR (Christian, the same night)

"It would be nice if the shader could be unified to PBR, and the
material brick can simply hand back defaults for things it doesn't
model." Done on matryoshka's side: the loam leaf's instance names an
entry in the renderer's PBR material table like a mesh's, and shades
through the same branch a PBR box does — albedo, roughness, metallic
and emissive from the entry — with the brick's own bark on top: the
normal bent by the grain, the grooves' darkening applied only to the
hit that set it (the hit's distance is the guard). The mount appends
a bark entry (the mount's albedo, roughness 0.85, no textures) before
the renderer's first upload; a negative index is the old inline path.
With the entry's defaults equal to the inline path's the close-up
rendered pixel-identical, which is the check that the seam moved and
nothing else did. Marble is now a different entry and a different
grain; the tree never knows.

## The material seedbed, played (Sunday 2026-09-06, late night; "Time for the seedbed?")

The first archetype is the one the tree wants and the machinery
almost had: BARK PLATES, grown as cracks. Played on a committed base,
no brief; what was built, and what it read.

- **A crack front.** `Params.planar` keeps a front's heading in the
  plane of its seed; `Params.carve` applies its capsule as a CUT (the
  CSG difference with its own signed distance, as the wound's is)
  rather than a join: a groove of the front's radius along its path,
  no provenance written. Both in the front's canonical bytes, so G1
  moved: `6b7f4a8f…` → `364c3aa7…`, the two params alone.
- **A slab** (`seedbed.slabLattice`): a box joined into the carrier by
  its own signed distance. The `plates` scene: a slab 64 wide and 12
  deep with its face at z = 0, growth potential everywhere, and
  PLATES_CRACKS fronts seeded on the face at seeded positions and
  headings — radius 1.2, wander 0.12, `avoid_self` NEGATIVE so the
  occupancy they read (the slab, less the grooves) steers them toward
  material and away from every groove already there, `inhibit` 0.6 so
  a crack that meets a groove stops at it (a T), length 72. Two
  tunings by eye (14 cracks at wander 0.35 curled; 24 at 0.12 with
  the stop read as plates), then left: the pattern is play.
- **The relief** (`bark.Relief`): the face read by the spline at 256²
  points over the slab, positive where a groove is by its depth, the
  gradient beside it from the jet; tiled by MIRRORING across every
  edge so no seam shows and no sign flip of the frame shows either
  (unit-tested); named by the slab world's content hash. `loam-run
  --scene plates --relief 256:file.pgm` writes it as a picture:
  deepest groove 0.91 units, archetype `39aa6f1b…`.
- **The attachment** (`bark.readArchetype`, and the shader): at a hit,
  depth is φ, the frame is the Hessian's, position is the world's —
  (u, v) = the frame's projections in the archetype's units, the
  relief there in place of the grain, the normal bent by its gradient,
  the grooves darkened by their depth, the whole fading by footprint
  at the groove's scale. Nothing but the carrier is read of the tree.
- **Matryoshka** (`--loam-bark plates`): the mount grows the plates
  world at init (80 steps, the same hash as the CLI's — the archetype
  is deterministic across the two doors), bakes the relief, uploads
  it once to a third SSBO (binding 51: a 16-float header, then the
  height and its two gradients, 786 KB); the brick header's twelfth
  float says which source. `--loam-archetype-unit` (mm a unit) and
  `--loam-archetype-depth` (mm a groove) are the scale knobs, 5 mm and
  4 mm the defaults; rendered at 5, 10 and 20 mm a unit for
  Christian's eye.

What it says about the vision: the tree hands over three numbers at
a hit and the archetype is a field grown elsewhere — swap the plates
for a marble grown in a slab of its own and the tree never knows.
What it does not yet do: the relief is one level (the fade is a band
weight, not a mip chain), the tile is a mirror (a periodic growth
would be seamless without it), and the archetype is a height field
of a face, not the volume (a cut through the plates would show the
slab, not the tree). 96 gates green.

### The plates on the tree, and the marble (Christian's eye, then his idea; the same night)

His screenshots of the plates: "fancy modern fractal stockings" — the
whirlpools on a branch are the field frame's projection of world
position folding back around a tube, and the lace on the trunk is the
mirror tile reflected in plain view. Neither showed on the grain,
which has no motif to fold or reflect. The finding: a statistically
homogeneous texture needs only the field's frame; a STRUCTURED
archetype on a surface needs a chart of that surface — the sweep's
own (s, θ), kept as history — or it needs to be a VOLUME. "Different
archetypes for different use cases" (Christian). The grain, which he
read as walnut, stays the tree's default; the plates stay as the
surface variant; and the volume is his:

"Sampling the PBR field in the brick as if it were a 3D texture — a
loam gradient field that is reasonably milky white with a black
structure inside it, and the tree picks up the (wrapped/scaled)
material field in world space." Built: the `marble` scene — a cube of
base, 28 crack fronts freed from any plane carving veins through it
(a TUNNELLING front: `inhibit` NEGATIVE means inhibited by air ahead
rather than matter, so a vein stops where it meets a vein or a face —
the sign carries it, no new field, G1 unmoved); `bark.Volume`, the
cube's carrier baked to a dense grid inside the faces
(`MARBLE_BAKE_HALF`: the bake that reached the faces wore a line of
half-vein at every mirror), mirrored on every axis, trilinear,
unit-tested; `loam-run --scene marble --volume 128:file.pgm` writes
the middle slice. On the GPU the same buffer as the relief with a kind
in its header (2: a volume, res³ of φ), the shader sampling it at the
hit's world position scaled to the archetype's units, the colour a
mix from the material entry's white to the vein's dark by the vein's
soft edge, the normal left polished; the material entry for marble is
white at roughness 0.15. `--loam-bark marble`. Rendered at 8 mm a
unit: a polished pale stone, dark veins, no fold, no seam, and a cut
through the trunk would show the same veins. The tree never knew.

The veins are short: the fronts stop at the first vein or face they
meet and wander little. Longer, sheet-like veins are the archetype's
tuning, play.

Christian, on the marble: "This is the best one yet! See, the thing
is now we can have transitions on albedo, roughness, metalness,
emissives. Each of the sampling/conformal mappings makes sense for
different use cases, but the simple 'sampled space' mapping, like the
marble, makes the most initial intuitive sense." So the volume, read
at the hit's world position, is the default way an archetype attaches,
and the next step is the archetype as a MATERIAL FIELD: the bake
carrying every PBR channel the archetype models — albedo, roughness,
metallic, emissive — correlated because they come from one history
(a vein is glossier, an ore vein metallic, a hot vein emissive), the
material entry supplying the rest. The marble's tint is the first such
transition, on albedo alone.

## The archetype as a material field (Sunday 2026-09-06, late — "let's do the material field columns on the marble … give our coral growth a bit more character and material expression")

Built: beside φ every voxel of `bark.Volume` carries the COLUMNS the
archetype models — `bark.Column` {albedo 3, roughness 1, metallic 1,
emissive 3}, a mask (`Columns`), `strideOf`, `columnOffset` — as the
STRUCTURE's material there. A hit (`Volume.materialAt`, the shader's
twin term for term) mixes the renderer's material ENTRY — the matrix,
and the default for every column the archetype does not model — toward
the columns by the vein's soft edge (`veinBlend`), and the footprint's
fade multiplies the mix, so a far hit reads the entry alone. The
columns are correlated because they come from one history.

The finding that shaped it: THE MARBLE'S VEINS ARE CUTS, AND A CUT
WRITES NO PROVENANCE (Christian's ruling: the scar remembers who grew
there). The field inside a vein is carved and nobody's — the gate
checks `who` = 0 there — so nothing in the field can say which vein a
voxel lies in; only history can. The bake names every voxel from the
RING RECORDS: for each front, each capsule between consecutive rings
(`Capsule.between`, the front's own arithmetic, the one G12 (b) proved
reproduces every deposit) claims the voxels within its envelope plus
a margin for the nearest capsule's front and its chart s over the
front's whole arc (`bark.Near{id, u, d}`: u is 0 at the seed, 1 at the
tip); the rest — where the blend is zero and nothing reads the
columns — by dilation from the named (the marble: 67,244 of 262,144
within 2.15 units, the rest in 45 passes). The margin
(`seedbed.marbleMargin`) is the vein's width plus two cells: the blend
reaches a vein past the wall and a trilinear read a voxel past that.
The archetype's EXPRESSION (`bark.Expression`: the columns it models
and a function of (world, near, p, φ) → `Material`) is the seedbed's.

The character: a SPECIES per vein, drawn from a stream of the front's
own at an epoch no step reaches (`MARBLE_SPECIES_EPOCH` = 2³², so the
veins Christian saw stay where they are — the archetype's hash is the
same 24fd971e…), weighted 5:3:2 — GRAPHITE, the vein he saw (dark,
roughness 0.6); GOLD (metallic, roughness 0.25 at its root, running
out to graphite by its tip: `Material.lerp` by smoothstep(u)); EMBER
(a dull red, emissive (6, 2.5, 0.7) at its root, cooling along the
vein as (1 − u)²). Over seed 0's 28 veins: 10 graphite, 14 gold, 4
ember. The palette is PROPOSED: a material's numbers are his, by eye.

The gate, unnumbered — the seedbed is play, but a contract with a
shader twin gets a witness: "the material field names a carved vein
from the ring history". One straight tunnelling vein through a slab,
the seed chosen so that vein is gold. The field inside is carved and
`who` is 0. The bake's metallic column along the vein's axis falls
0.999 → 0.001 and never rises (24 voxels inside), the roughness is
0.25 at the root, the emissive column nothing; `materialAt` through a
white entry reads the gold through the edge at the root (metallic >
0.5, red over blue) and the entry alone off the vein, every column
exactly. THE MUTATION, executable: an expression that reads the vein's
name but not the arc position → the tip's metallic stays at 0.999 and
the fall is gone. Two unit gates beside it: the columns' offsets (a
stride of 1 + the present widths, an absent column has none), and a
hit's mix (a present column reads back; metallic and emissive, absent,
are the entry's exactly; φ = 0 is half way). 1,800 of 32,768 voxels
named, 27 passes.

The gate's first failure was the test's own: "off the vein" given in
WORLD coordinates read pure gold. The bake cube's corner is not a
multiple of the mirror period, and the point it folded to lay outside
the slab — air, φ = +band, "vein" by sign, named by dilation from the
root. The archetype's coordinates are the cube's own from its corner,
as the shader reads them (the hit's world position over the unit,
folded by the mirror); the test says so now.

GPU (matryoshka after `db382fe`): binding 51's header carries [12] the
columns and [13] the stride; res³ records (64³ × 9 floats, 9.4 MB;
`LOAM_VOLUME_STRIDE_MAX`); `loamLocate` finds the cell and its eight
weights once, `loamColumn` reads one float of a column through them,
`loamColumnOffset` is loam's from the mask. `loamBark(…, mat)` starts
every path from the entry's values and hands back
`loam_mat_albedo/roughness/metallic/emissive`: the marble path mixes
each present column by the vein's edge; the grain and the plates leave
the entry's and darken on top; traversal.comp's kind-3 branch shades
the loam hit (at `loam_hit_t`) with those in place of the entry's.
`Mount.vein_colour` is gone: the palette is loam's. The bridge's 13
gates green. Rendered at 8 mm a unit, close: a polished pale stone
with graphite flecks, gold flecks and the ember's orange glints. At 20
mm the flecks are blobs.

THE FINDING FOR THE PLAY: a tube vein crossing the tube's skin reads
as a SPOT. The along-vein transitions are in the bake and measured,
and the bake's middle slice (`loam-run --scene marble --volume
64:f.ppm`, a colour slice through a white entry now) shows a gold vein
running to graphite — but on the tree they are legible only where a
vein runs along the surface. The veins' morphology stays the next
play: a sheet (a flat ring profile — the residual per slot is the
mechanism, `Ring.r[24]`) or a planar crack swept through the cube.

Christian's aside, recorded with its trigger: "is there some way to
evaluate the field rather than to bake it — maybe 'bake' a cheaper to
evaluate field". The archetype IS a loam world, and the loam leaf
already evaluates one on the GPU through its bricks and the B-spline;
the bake is a resample of that to a regular grid with a mirror tiling.
The evaluated form is the archetype's bricks as a second loam bank
sampled with a wrap — no bake, the columns as channels. The cheaper
form is a fit: a packed set of radial basis functions, fitted by
gradient descent to the material's deviation from the entry, so the
matrix is the bias and only the veins cost kernels — his ask, the
next experiment. Trigger for the evaluated form: an archetype whose
bake exceeds the buffer (a 128³ material field is 75 MB) or one that
lives (ruled to take a back seat).

Cost: the sim untouched — G1 `364c3aa7…` unmoved, the regression line
4.49 ms not re-measured (no sim change); the bake's naming and
dilation at 64³ inside the noise of the 8 s Debug grow-and-bake.
Christian, from the renderer: "That looks great! Just what I had in
mind!"

## The packed RBF set (Sunday 2026-09-06, late — Christian, from the renderer: "That looks great! Just what I had in mind! So then I'm asking can we instead (as an experiment) try baking via gradient descent to create a packed RBF set for the albedo, roughness, metalness, emissives instead of the giant 7 MB volume texture?")

The cheaper field from his aside, built as an experiment on the
committed base. What a hit reads of a material field is, per present
column, entry·(1 − A) + B — A the vein's blend at the point, B = A
times the structure's material — LINEAR in the field, so a sum of
kernels carries it and the ENTRY IS THE BIAS: the matrix costs
nothing, only the structure costs kernels. `src/rbf.zig`: a `Set` of N
isotropic Gaussians, each a centre, a width and nine weights (A, then
B for albedo, roughness, metallic, emissive: `KERNEL_FLOATS` = 13);
`materialAt` folds the point by the mirror as the volume does, sums
every kernel within `CUTOFF` = 32 widths squared (exp(−16); beyond it
a read is the entry EXACTLY — a denormal exp once left 1e-42 of gold
on the matrix, and the gate caught it) and composes through the
entry; `write`/`read` make it a FILE ("LRBF", 13 KB at 256 kernels):
the archetype as an asset the renderer loads without growing
anything. `fit`: Adam on centres, log-widths and weights, targets the
baked volume's own read (`target` = (A, A·columns)) at a pool of
points HALF DRAWN FROM THE VEIN'S VOXELS (uniform sampling of a cube
that is 7% vein would fit the matrix), each channel normalised by its
range in the pool (an ember's radiance of 6 must not outweigh a matte
grey's 0.6), the kernels SEEDED ON THE VEINS most of a width apart
with the target at the centre as their weight, widths clamped between
half a cell and the cube. Held out: 4,096 points apart from the pool.

Gates (unnumbered, an experiment): a set of one kernel reads its
weights back at its centre through the entry, the entry alone far
away, folds by the mirror, and hands back the entry for columns it
does not model; THE FIT'S GRADIENT IS THE FINITE DIFFERENCE'S (a
centre, a log-width, a weight, to 1e-3 — a wrong derivative is the
fit's own bug and this is its witness); and the fit on two balls of
different material lowers the held-out RMS by `RBF_FIT_GAIN` = 2
PROPOSED, written before the run — measured 5.08 (0.240 → 0.047, 6
kernels, 300 iterations, 312 bytes), the gold ball reads metallic
through a white entry, the matrix reads the entry; the MUTATION,
executable: the step's sign flipped → the error climbs; and the set
survives its file bit for bit.

The marble, `loam-run --scene marble --steps 90 --rbf N:file.lrbf`
(ReleaseSafe, a tool run, not a measurement of the sim; the mode is
printed), against the 64³ field of 9,437,184 bytes, 17,913 vein voxels
in the pool, 2,000 iterations of 1,024 points:

| kernels | seconds | held-out RMS, normalised | A | albedo r | metallic | emissive r | bytes |
|---|---|---|---|---|---|---|---|
| 256 | 5.3 | 0.154 → 0.050 | 0.066 | 0.035 | 0.033 | 0.055 | 13,312 |
| 1024 | 20.0 | 0.126 → 0.022 | 0.027 | 0.016 | 0.014 | 0.042 | 53,248 |
| 4096 | 79.3 | 0.644 → 0.019 | 0.022 | 0.013 | 0.012 | 0.057 | 212,992 |

The 256-kernel slice beside the volume's: every vein where it was, the
gold running to graphite, the ember, the dots; a faint grey ghost
where two graphite veins were close, and a speckle of weak kernels in
the matrix. On the GPU (matryoshka after `d66de73`): `--loam-rbf FILE`
loads the set in place of growing the marble (kind 3 in binding 51's
header: [0] the count, [13] the floats a kernel, the kernels from the
header; `LOAM_RBF_MAX_KERNELS` 8192); `loamBark` folds the hit's point,
sums the kernels within the cutoff, composes entry·(1 − A) + B with
the footprint's fade scaling both toward the entry — `Set.materialAt`
term for term. The close shot through the 256-kernel set against the
volume's, same camera, same 480 frames: the flecks and the glints
where they were; the RMSE between the two frames is 0.0062 of full
scale, against 0.018 between the volume's own shots at 8 and 20 mm a
unit — a change of set is a third of a change of unit. The tree never
knew, twice. Christian, walking around it in the renderer: "it does to
me too" (indistinguishable) — "Great job".

The finding: at the scale the tree reads it, 256 Gaussians (13 KB, a
loop of 256 exps per loam hit) carry what 64³ × 9 floats carried, and
the fit is a five-second tool run. Past 1,024 the returns vanish:
4,096 kernels buy 0.019 against 0.022 and start from a worse seed
(4,096 overlapping widths overshoot before Adam pulls them in — 0.644
at the start), and the emissive's residual does not move at all
(0.042 → 0.057): the ember's glow is a steep ramp along a thin vein,
and the target is itself a 64³ trilinear — the set is fitting the
bake's own blur, and a finer bake, not more kernels, is what a lower
number would need. What the set cannot carry: a vein's
sharp WALL — a Gaussian's edge is a Gaussian's, and the blend A is a
smoothstep over the vein's width; a set is a low-pass of the field by
construction, and where the vein's edge matters (a cut face seen
close) the volume, or more and narrower kernels, are the answer. What
it invites: anisotropic kernels (a vein is a tube: one ellipsoid
where a chain of spheres stands now), pruning by weight (the packed
set packs itself), and the living archetype re-fitted from a warm
start. The palette stays PROPOSED; `RBF_FIT_GAIN` PROPOSED.

## Anisotropic kernels (Sunday 2026-09-06, late — Christian: "Oh great idea, yes, let's try the anisotropic kernels next")

A vein is a tube; a chain of spheres is the wrong shape for it. The
kernel's width became the lower-triangular factor L of its PRECISION
(Σ⁻¹ = L Lᵀ, six numbers), the Mahalanobis distance |Lᵀ(q − μ)| in
place of |q − μ|/σ — an isotropic kernel of width σ is L = I/σ, an
ellipsoid is whatever the descent makes of the six, and the form is
positive-definite by construction (the diagonal through its log, the
off-diagonal free). `KERNEL_FLOATS` 13 → 18; the file is version 2
(version 1, the spherical set of the same night, kept by nothing);
`rbf.mahal`, `Kernel.isotropic`, `Kernel.widths` (the precision's
eigenvalues by Jacobi, 1/√λ) and `Kernel.aspect` (longest over
shortest); the descent's gradients ∂g/∂μ = g·(L v) and ∂g/∂L_ij =
−g·v_j·d_i; widths clamped between half a cell and the cube on the
diagonal; `FitOptions.isotropic` projects the shape back to one width
after every step — the gate's mutation and the like-for-like
comparison, on one code path. The cutoff is the same 32, in
Mahalanobis units now. The shader (`loamBark`'s kind 3) reads the six
and forms v the same way; `LOAM_RBF_MAX_KERNELS` unchanged.

The gate, written before the run: "a tube is an ellipsoid" — one
straight vein of gold (a capsule twelve long, radius one and a half,
in a 16³ cube), two kernels, free against held spherical, the free
fit's held-out RMS lower by `RBF_ANISO_GAIN` = 2 PROPOSED (the theory
beside it: two spheres over a tube leak into the matrix on every side
and miss the ends together; two ellipsoids of the tube's width cover
it to the caps). Measured: free 0.063, spherical 0.218, GAIN 3.44;
the held set's aspect exactly 1, the free set's 36.8 — every free
kernel wider three units along the tube than across it. The descent
stretched the kernel to the cube's length: the tube runs nearly the
whole cube, so nothing in the data bounds the long axis but the caps.
The gradient gate probes each off-diagonal and a log-diagonal now
(1e-3 against the finite difference, all seven kinds). The two-ball
gate unchanged: 4.82.

The marble, like for like (2,000 iterations of 1,024, ReleaseSafe):

| kernels | shape | seconds | held-out RMS | A | emissive r | aspect median / max | bytes |
|---|---|---|---|---|---|---|---|
| 256 | spherical (held) | 14.1 | 0.0534 | 0.070 | 0.055 | 1.00 / 1.00 | 18,432 |
| 256 | anisotropic | 14.2 | 0.0264 | 0.034 | 0.040 | 2.67 / 110 | 18,432 |
| 128 | anisotropic | 7.2 | 0.0512 | 0.064 | 0.053 | 3.38 / 298 | 9,216 |
| 1024 | anisotropic | 54.4 | 0.0183 | 0.023 | 0.041 | 2.43 / 18 | 73,728 |

THE FINDING: anisotropy HALVES the error at the same count (0.053 →
0.026 at 256), or halves the count at the same error (128 free
kernels, 9 KB, match 256 spherical). The median kernel is two and a
half to three times longer than it is wide — the veins' own shape,
found by the descent from spherical seeds with no direction given —
and the longest are stretched along whole veins (110 at 256) or
across the cube (298 at 128: a faint streak in the 128 slice, a
kernel that found a line through the matrix cheaper than a vein — the
place pruning or a bound on the aspect would act). The emissive's
residual stays at 0.04, the bake's blur, as before. The tree through
the 256 free kernels against the volume's shot: RMSE 0.0031 of full
scale, half the spherical set's 0.0062. The evaluation costs a
kernel six multiplies more than a sphere's three; the fit 14 s where
the sphere's was 5, the same 2,000 iterations.

Open: a bound on the aspect (or a penalty), pruning by weight so the
packed set packs itself, seeding the long axis from the ring history
(the bake knows every vein's direction; the descent found it anyway),
the warm-start refit.

## Sheet veins: the marble that is marble (Sunday 2026-09-06, late — Christian: "one thing I haven't seen yet is something like actual marble with thick continuous veins. Our current marble is more like flecks or streaks, but it is like that in the source.")

It was like that in the source: 28 round crack fronts of radius 0.9
that stop at the first vein they meet, so every vein is a short tube
and a tube crossing the trunk's skin is a fleck. Real veining is a
FRACTURE FILLED — a sheet that runs the block. A front sweeps whatever
its ring is, and the ring's residual profile is a polar radius per
slot, so a ring held as the polar rectangle r(θ) = min(W/|cos θ|,
T/|sin θ|) — T across, W in the plane — is a sheet, and a long
wandering sweep of it is a vein. `front.sheetProfile(T, W)` builds it
as a residual over an envelope of T, never negative: the capsule fades
a residual toward its axis (`fade` = ρ over half the envelope), which
would have blunted a thin side written as a negative residual over a
wide envelope; written the other way round the thin side IS the
envelope and the fade never bites. `Spawn.profile` carries it to the
front at birth — the ring and the seed ring alike, so the first sweep
is already the shape (null is the round ring every front had, G1
untouched) — and `seedbed.plantSheet` chooses the ring frame: `wide`
is the ring's normal, θ = 0. The ring CA off (heal, diffuse, noise,
impulse, taper, bulge all zero) holds the profile along the sweep; the
frame transports along the wander, so the sheet twists gently as a
fracture does. The bake's naming reach grew by the profile's largest
residual (a sheet reaches W past its axis, not T).

The finding on the way: `inhibit` = 0 is not "never inhibited" — a
positive inhibit grows into occupancy at or below it, so zero is "only
into pure air", and a sheet started inside matter never moved (the
gate's first run: φ −3 everywhere). One is never inhibited: through
matter and air alike. The first sheet gate said it in one line.

The scene: `marble` is the sheets now — MARBLE_SHEETS 7 of MARBLE_THICK
1 (the survival floor: 2 units thick) by MARBLE_WIDE 14 (28 wide),
MARBLE_FAMILY 5 sharing one plane's normal scattered by a quarter (a
family of sub-parallel fractures), 2 crossing them, every one started
40 units outside the cube through a point inside it and swept
MARBLE_LENGTH 110 with wander 0.10, never stopped, MARBLE_STEPS 110;
the growth blob reaches the starts. The first night's scene is
`flecks` (FLECKS_VEINS 28, FLECKS_VEIN 0.9, FLECKS_STEPS 90), kept
beside it: "different archetypes for different use cases". The species
rule is the scene's (`marbleSpecies(preset, seed, id)`, the expression
carries the preset): the sheet marble's family is GRAPHITE — the
classic stone, grey veins in white — and its two crossing veins are
the accents, one GOLD running out to graphite along its length, one
EMBER cooling along its, so the transitions are on continuous veins
the eye can follow; the flecks keep their draw from the stream. The
first seed drew five gold sheets of seven before the rule and looked
like brass.

The gate: "a sheet vein" — one straight sheet (T 1, W 6) along a slab:
carved on the axis (φ 2.00) and four units out in the plane (1.28),
base two and a half across (−1.53) and nine beyond the width (−2.72),
the seed ring carrying the profile and the first sweep already a
sheet; the mutation, the round ring of the same radius: the plane's
point is base. The material-field gate is untouched (its slab is the
flecks' rule).

The marble on the tree, 8 mm a unit, close: continuous bands of grey
wrapping the trunk, an ember band glowing orange at its root and
cooling around the back, the gold one grey-gold where it enters. THIS
IS MARBLE. The bands are broad on a trunk 37 units across — a sheet
two thick crossing a cylinder obliquely is a band several times its
thickness — and the unit is the knob for that (`--loam-archetype-unit
5` for finer). The ember's radiance (6, 2.5, 0.7) that was a glint on
a fleck is a beacon on a sheet: the palette is PROPOSED, and this is
the number Christian will strike first.

The set on sheets (256 anisotropic, 2,000 iterations): held-out RMS
0.372 → 0.071, aspect median 6.4 — the descent made FLAT kernels for
flat veins — against the flecks' 0.026 at the same count: four times
the vein volume to cover (71,095 vein voxels in the pool against
17,913). With the family grey: 256 kernels 0.066 (A 0.111), 1,024
kernels 0.054 (A 0.085, 57 s, aspect median 4.0) — the second
thousand kernels buy little, and the emissive's residual is 0.26: the
ember sheet is a large bright structure with a sharp edge, and a
Gaussian's edge is soft. The slices reproduce every sheet, softened;
the tree through the 1,024 set against the volume's shot: RMSE 0.018
of full scale, six times the flecks' 0.003 — the bands are there and
where they were, their edges blurred and the ember's glow spread
thinner. A sheet is the set's hard case: the flecks were sparse and
small, the sheets are wide and sharp-edged, and what a sum of
Gaussians cannot carry is an edge. For sheets the volume stays the
reference and the set is the far LOD; a set that carries an edge
would need a kernel with one (a sigmoid across the sheet's normal),
which is the next shape if the far LOD is wanted sharp.

## The veins as light: the emissive record and the aura (Sunday 2026-09-06, late — Christian: "not sure the emissives are acting as radiant. Didn't see them in the NEE" → "the analytic lights are proper lamps, where I'm looking for simple glowing auras. It's more an effect than real lighting." → "what you really want is an emissive buffer that records information about emissive pixels during rendering and then take that buffer into account during the bloom")

The finding, in the renderer: matryoshka's emissive NEE reads a
static link cache baked at load from the scene's emissive materials
and light entities; its analytic lights are lamps; and a `light`
spray's rows are the composite's splats — deferred point lights each.
A loam vein's emissive column reached the pixel through the surface
shader and the bloom and stopped there: self-luminous, not radiant.
The first proposals (rows into the splat list from the bank's surface
samples) were lamps of another shape, and he did not want lamps.

His design, built in matryoshka (after `8a95f6a`; the loam side is
untouched): THE EMISSIVE RECORD — every producer of a primary hit
writes the luma of what the surface emits into `g_env_diff.a`, which
nothing read (a material's emissive as the shade adds it, a prim's
extra, a loam column; the lane cache carries it) — and the bloom
carries it DOWN ITS OWN PYRAMID'S ALPHA (the first downsample reads
the G-buffer at a third binding on the shared bloom layout, every
level blurs the alpha beside the rgb), so at the end `bloom.a` is the
emissive luma of the surfaces around a pixel at the bloom's radius,
and post adds THE AURA: `AURA_GAIN × (1 − exp(−EMISSIVE_DRIVE ×
bloom.a)) × (bloom.rgb / luma(bloom.rgb))` — the record alone says how
strong, the pyramid gives only the HUE, which near an emitter is the
emitter's own. Additive by design: a first build opened the
energy-conserving scatter's GATE by the record instead and moved the
frame by 0.0003 RMSE — at the veil's fraction a gate cannot make a
halo. Where the record is zero nothing is added.

THE FINDING, and Christian's eye that got it ("I'm not really seeing
any aura on the orange stripes, compared to that emissive cube"): the
build after that multiplied the record's falloff by the pyramid's
COLOUR, and since both fall off away from the emitter the product
died within a few pixels — the added term was the vein itself, re-lit
where it was already saturated, and nothing around it. ONE FALLOFF IS
A GLOW; TWO MULTIPLIED IS AN OUTLINE. Found by painting the buffer to
the screen: first `bloom.a` (the record is right — the ember bands and
the scene's emissive prims, black everywhere else), then the added
term alone (an orange band with a hard edge, which is the defect in
one picture). With the hue normalised the term is the record's own
profile and the bands warm the stone at the bloom's radius: RMSE
0.029 against the shot before, against 0.013 for the build that did
not read as a glow. His cube, for the comparison, is a light VOLUME —
its neighbours get analytic irradiance, their bloom gate opens, and
that is the halo he was measuring against. Numbers PROPOSED (drive 4,
gain 0.6). Recorded in matryoshka's architecture.md §7.8a.

THEN THE REACH, his next look ("it doesn't go into free space though,
like it is using multiply instead of additive blending?"): it was
additive all along — an amplified difference against the pre-aura
frame showed the delta crossing the silhouette into the background,
only too tight and too dim to read as a glow. The cause is the source's
shape, not the blend: a vein a few pixels wide dilutes to almost
nothing by the pyramid's coarse levels and comes back at a few per
cent, so the aura hugged the vein like a rim light. THE RECORD NOW HAS
ITS OWN SPREAD: `bloom_up` upsamples the alpha with
`max(scatter, AURA_SPREAD)` — 0.9, so the wide level dominates — and
the reach is the aura's property, not the look's scatter slider.
`EMISSIVE_DRIVE` becomes the reach knob then (the tail in open space
is small; the knee lifts it) and the two tune together: a steep knee
on a wide record saturates the near field and the glow flattens into
fog. Three shots settled it — the rim (drive 4, no spread), the fog
(12, 0.9), and 6/0.8 between them, which is the committed default.
All three numbers PROPOSED.

THEN THE COLOUR, and the eye again ("only the orange is emissive. But
why is the halo not orange - it's white?"): the strength was the
record's but the HUE was the bloom's, and the bloom's rgb is the
blurred FRAME. Painting the tint to the screen settled it in one
shot — the vein's red for a few pixels, the stone's blue-grey after
that — so an orange vein wore a white halo, and additive orange onto
bright blue stone desaturates on top of that. THE AURA GOT ITS OWN
CHAIN: a second, four-level pyramid over its own image, run by the
bloom's two pipelines and its descriptor layout, whose first level
reads the composite and the record TOGETHER — each full-res pixel's
colour WEIGHTED by its record into rgb, the record into alpha — so at
the top mip `rgb / luma(rgb)` is the emitters' own hue at any
distance. The bloom chain went back to exactly what it was. Four
levels also bound the reach by construction, which retires the level
rule. THEN, immediately: "that did it! But now we can see it, it's
way too much" — the drive and gain had been raised TWICE against the
diluted record, so they were tuned to the breakage; halved on the
chain (4 and 0.3). A NUMBER TUNED AGAINST A BROKEN SIGNAL IS TUNED TO
THE BREAKAGE, which is the general form of the finding and is written
into matryoshka's §7.8a — and is why they are KNOBS now, at his word
("awesome idea to add knobs. Let's expose them"): `render/bloom/
aura_gain`, `aura_drive` and `aura_spread`, on the FX page under an
Aura fold beside Bloom, gain 0 being off. Gain and drive ride
`oklab2.zw` (the post push range is full at the 256-byte spec floor
and those were the spare lanes nothing read); spread is a renderer
field beside `bloom_scatter`. THE GATE: at the defaults the frame is
BYTE-IDENTICAL to the constants they replaced (RMSE 0), and driven
from the console — `--exec "write render/bloom/aura_gain 0.9"`, the
verb is `write`, not `set` — 0 / 0.3 / 0.9 give no aura, the default
and a strong one (0.028 and 0.038 RMSE from the default).

THEN THE LEAK, and his eye again ("some of that cube's aura is
lighting up down at the bottom, or side of the screen, and all the
auras keep flickering ... it's like there is a fence/barrier
missing"): TWO causes, both mine, both in the spread I had just
added. (1) A mix of m at EVERY upsample level leaves the coarsest with
m^(levels−1) — at 0.9 over six levels mip 5 carries two thirds, and
mip 5 is a handful of texels across the whole screen, so the record
became a near-global wash whose few texels swung with the sub-pixel
jitter: the flicker. `bloom_up` now stops the alpha's descent above
`AURA_MAX_LEVEL` (3), so the support is that level's blur and no
wider, and the levels that flicker are the ones excluded. (2) THE
DYNAMIC RENDER SCALE, which Christian named the moment it was
described: the bloom chain is sized to the window, but only the
top-left renderW×renderH of a full-res image is written this frame and
the margin is the PREVIOUS frame's at another scale — the record was
reading it, so an emitter's aura appeared at the frame's right and
bottom edges and moved as the controller ramped. `bloom_down` clamps
the record's read to the valid extent, pushed in the constants. The
rgb path has the same exposure and is left alone: it lerps by a small
scatter where the record is amplified by a knee, so the same stale
margin is invisible there and glaring here — an amplifier finds every
approximation upstream of it. THE MUTATION, at `MTR_RENDER_SCALE=70`:
unbind the level and let the margin back in — the frame moves 0.016
RMSE and the difference is a broad wash across a whole side of the
frame with no emitter near it. Numbers now drive 5, gain 0.7, spread
0.9, max level 3, all PROPOSED.

RADIANT PARTICLES, the other half of his ask ("it needs solving for
radiant particles as well"): `sprites.frag` writes the record too — a
card's emission (its colour above one) times the coverage the blend
applies, max-merged into `g_env_diff.a`, with a fragment-write →
compute-read barrier after the pass, which already runs immediately
before the bloom. Overlapping cards race on the read-modify-write
(there is no atomic max on a float image), so the record is a LOWER
BOUND where cards pile up: every store is one of the frame's plausible
values, none above the true maximum — an effect's buffer, stated at
the write. SEEN RUNNING, at the wrap: no spray can be lit from
matryoshka's command line (they come from a rig), so the particle path
went in unwatched — and Christian's shots closed it the same night. An
ember spray's cards carry one broad orange glow across the whole
plume, and the Lumberyard Bistro's string lights each wear their own
colour off a scene with no loam in it at all: ordinary glTF emissive
materials, the same record, the same aura. THE RECORD IS
PRODUCER-AGNOSTIC BY CONSTRUCTION, and a scene that never heard of the
marble is the proof. A `light`
spray has no aura by this path and does not need one — its rows are
splats, real light.

### Open

The sprites' emissive record (their aura); the palette on sheets (the ember's radiance first); pruning and an aspect bound for the RBF set; the
archetype's mip chain; a periodic slab or cube; the palette,
PROPOSED; the evaluated archetype (a second loam bank) with its
trigger; the chart path for structured surface archetypes if the
plates are wanted on a tube. `who` and `segment` packed to one plane,
and `own` where `other` is far, are the next two of the seven-plane
cost. The one-sided mask's
error inside a collar, if a chart read there ever matters. The
amplitudes, PROPOSED. The silhouette ensemble, recorded with its
trigger (shimmer at a silhouette under the footprint cut). From
before: the cost, pinned; the three-way junction; the coil's inner
wall; the arc window; a units-schedule replay; the D5 signal; the
shared fixture.

## P2.3 before the cost (Sunday 2026-09-06, night — Christian, relaying Claude Chat)

"The seam finding is the right fix and the right principle: a copied
`who` is not a change, and the floor counts only what the world reads.
Provenance never wakes anything." Struck as a principle: the change
floor and attention count the carrier and the additive channels; the
slots and the provenance are the carrier's bookkeeping, scored where
the carrier is, and nothing of them wakes a brick.

The order: "5.18 ms is seven planes on every tissue brick, and the
candidates are obvious (integer planes for who/segment, halves for the
charts, provenance only where the band is). But which planes a bark
read actually touches, and at what footprint, is the fact that decides
which candidate, and P2.3 is where that fact appears. So: P2.3 first,
with 5.18 pinned as the regression line in ReleaseSafe and nothing
taken until the bark has told you what it reads. Optimising provenance
before anything reads it would be the sizing premise again." THE
REGRESSION LINE: the sapling, seed 7, 100 steps, serial, `loam-run
--phases`, ReleaseSafe — 5.18 ms a step, hash 97 ms of the run; every
beat from here re-measures it in that regime and states it, and a beat
that moves it up says why. No candidate above is taken before the bark
reads. P2.3 opens next: the bark from the bands (what a hit reads —
the chart channels, the ring records — and at what footprint, which is
the fact), the close-up, the ensemble near the surface for the
silhouettes if the footprint truncation leaves any.

## The bridge's dirty upload (Sunday 2026-09-06, afternoon, matryoshka branch `loam`)

The deferred fill D1 named, paid for by P2.1a: the bridge re-packed
every surface brick for the GPU whenever the vid moved — one contiguous
array, rebuilt from scratch, every loam second. Now a brick keeps its
slot in the loam SSBO for as long as it holds surface (`slot_of`, a free
list for slots whose brick lost its zero set or went), and on a vid
change the pack walks the surface bricks and writes only those whose
`changed_ns` is past what the slot holds — loam's attention bookkeeping
is the dirty set, nothing added to the field for it. The sink's `at`
was already an element offset; the pack now writes one stride at a
brick's own slot instead of the whole array at zero. The dynamic pool
is filled from the live slots, so an object's slot index never moves
under a brick between frames.

Gate, in the bridge's own test (`zig build loam-test`, 12/12): after 60
loam seconds the first pack writes one stride per surface brick at its
slot (59, the top offset 58 strides in); the same vid again writes
nothing; five seconds on, 34 of 73 surface bricks have a `changed_ns`
past the upload and exactly 34 strides are written — every changed
brick among them, none of the rest — and every object offered names a
live slot once. The overlay line says "{n} on the GPU ({m} written on
the last pack)". Not done: coalescing adjacent dirty slots into one
write (34 memcpys of 5.3 KB a pack is nothing yet); freeing is by
absence, so a brick that loses its surface and regains it next second
takes a fresh slot — harmless, and the free list is what pays for it.

## Attention pre-registered (Sunday 2026-09-06, evening)

Christian: "a variance or attention score associated with the cells, so
the step updates where things are changing — it would be like Box3D with
sleeping states, but differentiable … it's worth doing now since it's
load-bearing to the entire system. Pre-register it beside P2.2." Done in
the brief as R15 and G14, beat P2.1a, ordered ahead of P2.2; the numbers
PROPOSED in `thresholds.zig` before anything runs (τ = 3 s, the budget
fraction ½, the deviation floor 5%). The design decision that matters is
recorded there: attention is DERIVED from (a₀, t₀) — the magnitude and
time of a brick's last change — never stepped, the touch-time trick a
third time, so it has no tail and a quiet world stays quiet; the active
set keeps its exact rule and attention orders it under a budget and
feeds the readers (summaries, the render budget, D2's criterion).
Nothing of it is built; the brief precedes the spade.

And beside it, the same evening, the budget (R16, G15, P2.1b): Christian
— "a budget policy for the updates to keep everything within a specific
time cost. It's perfectly fine if it takes longer than a single frame
update, as long as we can make it all restartable and carry on." The
design decision recorded: the budget is FED in work units, as time is
fed, never read from a clock — a wall-clock deadline inside the step
would make the hash a property of the machine — and the step becomes
`begin` / `work(units)` / `finish` with its state on the world, exact
across any number of calls (SPREAD) because the phases are region-local
already, with a CUT mode that commits the attention-ordered head and
carries the rest forward. G15's numbers PROPOSED beside G14's.

## P1.7 — the seedbed (2026-09-06)

- `loam-run`: named scenes, `--damage box@step`, `--slice`, `--project`
  (a max-projection, since a slice through a thin tube mostly misses
  it), `--dump`, `--ray`, `--all-regions`, `--active`, `--phases`. Every
  number a gate asserts can be printed here on the same scene.
- **Looking at the tree** (after the parallel work; `--threads 16`,
  220 steps, 0.7 ms a step): a trunk thick at the base, tapering,
  bending toward the light, and a crown of branches near the top. Two
  findings from looking. The side view along x was laid on its side —
  `freeAxes` now puts y up for every view. And the branches were stubs:
  at `consume = 1` the trunk empties a two-radius sphere around itself
  in a step, so a bud born on its surface reads zero potential ahead and
  goes dormant at birth. `--consume 0.2` gives the crown room (material
  2628 → 3029, 12 fronts). A scene fact, exposed as a knob, not a
  default changed: the sapling's default stays 1 and the frozen
  reference with it.
- **Three doors, one surface**: the Zig verbs in `seedbed.zig`, the C
  seam (`libloam.so`, `capi.zig`), the Python binding (`py/loam`, ctypes,
  stdlib only). `py-test` proves the Python-driven sapling and the
  CLI-driven one publish the same content hash, and G1 across two
  processes.
- **The dump** is one canonical struple map, planes as little-endian f32
  bytes; `tools/read_dump.py` reads it with the struple Python port and
  checks mask/planes agreement and that no plane is all zero.

## Deferred fills (pointer and paying customer)

| fill | pointer | trigger |
|---|---|---|
| Refinement / coarsening (D2) | `Snapshot.coverCube` already resolves mixed gauges; `tree.build` refuses overlap loudly | first scene where an organism needs finer bricks than its environment was authored at |
| Renderer integration (D1) | `ray.Cursor`, `Summary.majorant`, `RegionView.sample` | first loam-grown thing on screen |
| GPU backend (D3) | Morton keys address bricks already; values are f32 | a capture that misses budget |
| Reconstruction bases per channel (D4) | `Brick.spline` is the one path; `trilinear` the hanging-node interpolant | a channel that wants interpolation (a mask, a label) |
| The collar (G12): gradient-gated smooth union | `SurfaceOp.k`, `channel.smin`; fronts deposit with k = 0 | P2.2 — a branch base with a crease in a capture |
| Spline-consistent prolongation across a gauge change | the hang rule copies `trilinear`; the two B-splines agree to C0 | D2's first item (R9): a tree across a gauge change |
| Halo slab copy for mixed gauges | `haloEmit`, the general path, per point | a mixed-gauge scene where the seam phase leads the profile |
| Bands for the picture | the carrier is band 0; bark is the ring residual through the capsule | P2.2, P2.3 |
| Operator scheduling (D5) | fixed order in `World.operators` | rill as host |
| Ring inheritance at a branch | `World.budSpawn` starts a fresh ring | a branch base that looks wrong in a capture |
| Frontier into partly filled cubes | `materialiseFrontier` skips an inner node | a diffusion mass check across a gauge boundary that leaks |
| A stack-allocated cursor | `ray.Cursor` takes a gpa for its queue | matryoshka's traversal wanting no allocator |

## The RBF set left home (2026-09-07, `src/rbf.zig` — a gate only)

rill grew a generic RBF evaluator (`rill/src/rbf.zig`, `rill/src/ops_rbf.zig`),
and nothing in this repo changed to let it. What happened is spindrift's
observation from the day before: **an RBF set does not care that its query
point is a position.** `fire.rill` read `Set.eval` at a particle's STATE —
cooled, sooted, thinned — and the same evaluator that skins the marble skinned
a flame. So the sum of gaussians is an interpolation primitive, `State → Field
→ Properties`, and rill took the model: the Mahalanobis form, the cutoff, and
an N-D centre with M channels in place of this repo's 3 and 9.

It took the model and nothing else. The nine-channel schema is bark's,
`compose` and `columns` are bark's, the extent and the mirror fold are the
volume's, the hash is the sim's, the `.lrbf` file is an asset's, and the fit
is a tool's — `loam-run --rbf` stays exactly where it is, because 2000 Adam
iterations over a pool of 32768 points is not a dataflow operator.

**What this repo owes now, and it is one thing.** There are two CPU copies of
one model (here and rill) and a third on the GPU (`dynamic_trace.glsl`, kind
3). Neither repo depends on the other and neither should — rill sits UNDER
loam, not beside it, and an edge in either direction to carry a test would
invert that for nothing — so the two CPU copies are held together by a frozen
table that lives identically in both: `PIN_KERNELS`/`PIN_ROWS` here, the same
numbers in `rill/src/tests.zig`. Byte equality in f32, not an epsilon. An
epsilon lets two implementations of one model drift in the last places until a
host that swaps one for the other renders something else and nobody is told.

Four kernels — isotropic, axis-aligned, fully anisotropic (every off-diagonal
of L non-zero and distinct, so a transposed index moves the answer), and one
that sits at r2 = 36 from one query and 31.36 from another with weights of
4096. That last one is the cutoff's, and it had to be built that way: a kernel
merely parked far away pins nothing, because exp of a large negative
underflows to zero on its own and `CUTOFF` could then be deleted without
moving a bit. The gate also asserts the far read is exactly +0 on every
channel — not a denormal residue, not a −0 — which is the same claim the note
on `CUTOFF` makes ("a denormal exp once left 1e-42 of gold on the matrix").

rill also transcribed `fmath.exp` from here, for the same reason this repo has
it, and pinned it to the same frozen output bits. Worth knowing, because it
was measured on the way: over all 1,098,907,649 f32 arguments the gaussian can
ever produce, glibc's `exp` and this repo's Sun `e_exp` differ in f64 on
11,626,851 of them by 1 ulp, and **zero** of those differences survive
narrowing to f32. So for the gaussian specifically the transcription is
insurance rather than a fix. It is not insurance for the rest of this repo —
sin, cos and the f64 path through the sim are where P2.1 actually bit.

**Mutations, three, all bitten** by the new gate: the `mahal` index swapped
(`l[2]` for `l[3]`); `CUTOFF` widened from 32 to 64; the half in
`exp(−½ r2)` moved to 0.4999.

**What a reader must do when this file changes.** If the kernel, the cutoff or
the packing of L moves here, it moves in rill in the same beat. The gate
failing IS that notification — it is not a flake, and it is not rill's problem
to notice later.

## MARL-0 — learning as local deformation (Monday 2026-09-07 — Christian: "I had this idea that Loam could do double duty as an ML platform … I put a campaign in the docs folder")

`docs/MARL_CAMPAIGN.md` is the brief. What landed is `src/marl.zig`, its
seedbed `src/marl_run.zig` (`zig build marl`), the predictions in
`tools/marl_predict.py`, the thresholds in `thresholds.zig`, and G17 (a)
to (g) beside the code in `rbf.zig`'s manner. Nothing is on the sim path,
nothing is a channel, nothing is in any hash, and the rest of the suite is
untouched.

### Where MARL is allowed to live, and where it is not

Christian's split, drawn before a line was written and the reason the
first day did not touch a brick:

    substrate — scheduling, publication, deterministic merging, hashing,
    lifetimes, the active set                            → reusable
    field storage — sample planes, halos, seams, the B-spline, the
    Lipschitz summaries                                  → NOT MARL storage

The campaign's "the substrate should not know that learning is happening"
holds for the first list and fails for the second. A brick is planes of
f32 over an 11³ block under a seam contract and a per-channel Lipschitz
bound; kernels are a variable-length parameter list with no per-sample
meaning. In planes, the seam pass would hand brick A's centre coordinates
the coarse interpolant of brick B's, and `Summary.lipschitz` would bound
the gradient of parameter soup. So MARL-0 borrows the substrate's IDEAS —
a region owning its own state, a conservative bound a query rejects a
region by, exact locality — and owns its own memory. Whether kernels earn
a home inside a brick is MARL-0.5's question, and the saturation data
below is what should answer it (campaign §10).

The kernel is a deliberate TWIN of `rbf.zig`'s rather than a call into it.
`rbf.zig` now carries the cross-repo bit-pin, and a learning experiment
must not be able to move the kernel out from under rill and the shader by
refactoring for its own convenience. G17 (a) is this file's half: the two
read the same bits at the same point, byte equality in f32.

### The predictions, written before a single exemplar streamed

`tools/marl_predict.py`, a second program that reimplements the truth
field from `marl.zig`'s constants and knows nothing about the learner —
`g13_predict.py`'s shape and for the same reason.

| | predicted | why |
|---|---|---|
| `MARL0_RMS_GAIN` | 2 | the target's variance is 43% swell, 60% shell, −3% cross. Learning the swell perfectly and the shell not at all buys 1.32; the shell alone buys 1.58. A gate at 2 needs 75% of the variance, which NEITHER PART ALONE CAN SUPPLY — the only way this gate could have been vacuous by construction |
| `MARL0_MAX_TOUCHED` | 120 | a birth is refused once a kernel reads above `coverage`, so kernels pack at one per ball of r_cov = √(−2 ln 0.35) = 1.449 widths while each is live to r_cut = √32 = 5.657. The overlap count is the volume ratio (r_cut/r_cov)³ = 59.5; the bound is twice it |
| `MARL0_MAX_TOUCHED_FRACTION` | 0.05 | §20 proposition 2, "a tiny fraction of model state" |
| `MARL0_CAPACITY_RATIO` | 10 | a FLOOR with a decade of headroom, not an estimate: the theory is an asymmetry of mechanism, not a number |
| the interference radius | 2h + one event's displacement | a proof, not a guess — and it needed an amendment, below |

### What the run said

Defaults: 6³ regions (h = 0.1667, σ_max 0.02946), budget 64, θ 0.02,
coverage 0.35, three steps, rate_w 0.5, rate_geom 0.2, trust h/3, seed 7.
ReleaseSafe.

| | 200 000 exemplars | 1 000 000 | predicted |
|---|---|---|---|
| held-out RMS | 0.14399 → 0.02326 (**gain 6.19**) | 0.14580 → 0.01202 (**12.13**) | ≥ 2 |
| max abs error | 1.0053 → 0.3340 | 1.0176 → 0.1303 | — |
| learning events | 17.7% of exemplars | 12.0% | — |
| kernels | 3 648, no saturation at all | 4 071 | — |
| kernels touched per event | 86.0 (2.36% of the model) | 108.9 (2.68%) | ≤ 120, ≤ 0.05 |
| kernels evaluated per prediction | 288.3 | 345.3 | — |
| regions touched | 10.8 of 27 | 11.6 | — |
| centre drift, mean / max | 0.00066 / 0.02015 | 0.00086 / 0.02605 | — |
| kernels that left their birth region | 14 of 3 648 | 23 of 4 071 | — |
| shell band : quiet slab | 8 454 : **0** per unit³ | 10 079 : **0** | ≥ 10 |
| wall clock | 2.19 s | 11.6 s | — |

The error falls at every checkpoint and the event rate falls with it —
68% of exemplars provoking work at a thousand, 17.7% at two hundred
thousand. That is §12's picture arriving on its own: broad regions settle,
activity stays where the structure is.

**The quiet slab took nothing.** Not a small number of kernels — none, at
either run length, and none under any instrument except Adam. §20's
proposition 5 is answered by that line alone: the error field is a thing
Loam's existing machinery would know what to do with, because it is
already shaped like an active set.

**Interference is a fact about bits.** One learning event, 20 000 probes,
at 1 000 000 exemplars:

    ∞-distance   max |Δŷ|      the proved bound is 0.5000
       0.083     2.193e-2
       0.167     2.633e-3
       0.250     7.091e-6
       0.333     0.000e0      ← and every bucket beyond it
    the observed radius — the furthest probe whose bits moved — 0.2418

Zero probes changed beyond the bound. §20 proposition 3 is not an
empirical hope in this model: `CUTOFF` returns a hard zero, so the only
ways to disturb a distant region are to move a centre there or birth a
kernel that overlaps it, and both are bounded. The observed radius is half
the proved one, which is what a loose proof looks like when it is honest.

### Adam is the wrong optimiser for one exemplar at a time

The sharpest finding of the day, and it cost a full rebuild of the step.
`rbf.fit` uses Adam, the campaign names Adam, and Adam is wrong here.

Adam divides the gradient by its own running magnitude — the property that
makes it scale-free over a batch. With ONE exemplar per step the gradient
is mostly noise, m̂/√v̂ is ±1 whatever the residual, and every touched
kernel takes a full `rate`-sized step forever. It violates the campaign's
own premise literally: *learning is deformation in response to surprise*,
and Adam deforms just as hard when there is no surprise left.

Measured, both at 200 000 exemplars, everything else equal:

| | Adam | NLMS |
|---|---|---|
| held-out RMS | 0.14399 → **0.15328** (gain 0.94) | → 0.02326 (6.19) |
| centre drift, mean / max | **0.570 / 1.541** (the domain is 1) | 0.00066 / 0.02015 |
| kernels that left their birth region | 28 184 of 28 436 | 14 of 3 648 |
| kernels | 28 436, **26 638 saturation events**, 167/216 regions full | 3 648, none |
| shell : quiet density | 6 249 : 52 545 — **inverted** | 8 454 : 0 |
| wall clock | 7.90 s | 2.19 s |

A model with eight times the capacity, predicting *worse than empty*, with
its kernels piled into the region where the truth is identically zero.

What replaced it is normalised least mean squares on the weights and the
NATURAL gradient on the geometry, both driven by one attribution

    a_i = e · g_i / Σ_j g_j²

the share of the residual kernel *i* is answerable for. The normalisation
is not cosmetic: about ninety kernels overlap any point, and ninety
unnormalised corrections each big enough to answer the whole residual
overshoot it ninetyfold. The natural gradient on the centre is the
pleasant part — preconditioning by the kernel's own covariance collapses
the whole thing, since Σ(Lv) = L⁻ᵀL⁻¹Lv = L⁻ᵀv = d, so

    Δμ ∝ −(w · a) · d

a kernel that under-reads at *x* simply moves toward *x*, by its share and
no more. No matrix, and no units to get wrong. Adam is kept as
`--optimizer adam`, an instrument and G17 (f)'s mutation.

### Three things the instruments and the gates found

**The unbounded log-width** (`--width 0.4`, a panic at 10 000 exemplars).
Nothing bounded a kernel from below: descent widened one until `expf`
underflowed L's diagonal to zero, `halfExtents` divided by it, the reach
came back infinite, and the reach projection added log(∞) to the
log-width. The centre clamp then let the NaN through, because
`if (v < 0 or v > 1)` is false for a NaN and no ordered comparison catches
one. Both fixed — σ ≤ h as an outer floor, and the centre clamp written as
`!(v >= 0 and v <= 1)` with an assert. The floor changes no converged
model, which is what an outer bound should do.

**The reach projection did not converge, and a field was hiding it.** The
gather's exactness rests on every kernel's cutoff box reaching at most one
region edge. The projection scaled L by f = reach/h and then stored
`min(reach, h)` — so the FIELD said the invariant held while the geometry
did not, on 0.6% of clamps. Replacing the store with an assert made the
assert fire, and the reason is arithmetic: for a kernel one ulp over `h`,
f = 1 + 2⁻²³, and log(f) ≈ 1.2e-7 is SMALLER THAN THE ULP OF THE LOG-WIDTH
ITSELF (~3.5, ulp 2.4e-7). The increment rounds away, the shape does not
move, and the loop spins on a kernel that is already correct to within a
float. A minimum shrink of one part in a thousand fixes it and terminates
by construction. Side effect worth recording: reach clamps fell from
335 466 to 30 963 per 200 000 exemplars, because nine tenths of them were
that boundary case re-firing to no effect. The model is otherwise
unmoved — gain 6.21 → 6.19, 3 640 → 3 648 kernels.

**The quiet slab was in the wrong place, and the gate on the EXPERIMENT
caught it.** The slab exists to be unreachable, not merely zero: the
window ends at 0.70 and a kernel reaches at most h, so nothing born on
structure should get into it. At 6³ that furthest reach is 0.8667, and the
slab started at 0.85. The derivation the slab exists to support was false
for the length of one gate run, while every measured number using it was
right — the slab was empty anyway. `the truth has the three parts the
campaign asked for` asserts the inequality directly and failed; the slab
moved to 0.90 (volume 0.0998) and the assertion is now true with 0.0333 of
margin. A gate on the target rather than on the learner is what this kind
of error needs, because G17 (f) would have gone on passing.

### The region bound is live only where kernels are narrow

Each region carries `max_reach`, the largest cutoff box it owns —
`Summary.covers`'s idea in one float, conservative so it may only ever be
too large. At the default birth width it prunes **nothing**, because a
newborn sits at the clamp and pins its region's bound to *h*, which is
further than any neighbour's cube. At `--width 0.4` it prunes 4.68 regions
per prediction. It is reported on every run so it can never be silently
dead, and the honest reading is that it earns its place only in a model
whose kernels have had room to narrow.

### The vacuous bound, and the amendment

`marl0ReachBound` was pre-registered as `2h + steps · rate · K` with
K = (1−β₁)/√(1−β₂) — Adam's bound on how far one step can displace a
centre. When NLMS replaced Adam the gate went on calling it, now with the
NLMS rate, and it returned **5.0768 of a unit domain**: a bound larger than
anything that exists, and G17 (d)'s "no probe beyond it moved" could not
fail. It passed on nothing.

An NLMS step has no a-priori bound at all — it is proportional to a
residual and a weight that nothing caps — so the model now carries an
explicit TRUST REGION (`Options.trust`, a third of a region per step) and
the bound is `h · (2 + steps · trust)` = 0.5000, exactly, for any
optimiser. G17 (d) additionally asserts the bound is smaller than the
domain and that probes exist beyond it, so this vacuity cannot come back
quietly. The trust region has never bitten at the defaults (`trust 0` on
every run above) — drift is fifty times under it — which is the point: it
costs nothing and makes the proof hold in the case that is not the default.

Amending a pre-registered number after a run is what the house rule
forbids, so it is recorded as what it is. The amendment makes the bound
SMALLER, which is the opposite of tuning a gate to pass, and it was forced
by replacing the step rule the original derivation assumed. `MARL0_ADAM_K`
stays where it was, documenting the instrument's bound.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G17 (a) the kernel is `rbf`'s, bit for bit | `CUTOFF` 32 → 30 | fails |
| G17 (b) the gradient is the finite difference's | centre components reversed | fails |
| | centre gradient halved | fails |
| | `l_ii` dropped from a log-diagonal | fails |
| | `d_i` dropped from an off-diagonal | fails |
| G17 (c) the 27-region gather IS the sum over the model | the reach projection removed | fails |
| | gather the own region only | fails |
| G17 (d) an event changes nothing beyond the bound | `gaussian`'s cutoff return removed | fails |
| G17 (e) the model learns | births refused and both rates zero | gain exactly 1 |
| G17 (f) capacity follows complexity | `--optimizer adam` | ratio inverts to 0.1 |
| G17 (g) the model is a function of (seed, count, options) | the stream keyed by a constant | fails |
| the truth has the three parts | — | it is the gate that caught the slab |

Three notes on the biting. G17 (b) needs its loss summed over sixteen
points in f64: differenced as a single f32 expression the same check fails
at the second digit on cancellation alone, and the gradient it was accusing
is correct. G17 (c) compares the gather against a reference that walks
EVERY region in linear index order — the order the gather visits its
twenty-seven in — so the two sums add the same terms in the same order;
summed in kernel-index order instead they differ in the last two places,
which is a true statement about associativity and a useless one about
locality. And one mutation was reported as SURVIVING when it had only
failed to compile: dropping `lv` outright leaves it unused, which is a
build error and not a bite. The harness now distinguishes the two, and the
real mutations (reversing and halving) both fail as they must.

### What G17 (e) does not witness — a question for Christian

With births refused AND both rates zero the model stays empty and the gain
is exactly 1, so the gate is not vacuous. But **birth alone clears it**:
with no descent whatsoever, kernels seeded at the exemplar with the
residual as their weight reach gain 2.85 at 200 000 exemplars against the
full learner's 6.19. Birth alone also empties the quiet slab, so it clears
G17 (f) too.

So the two gates witness *the model learns* and not *the descent works*.
That is a real hole and I am not going to plug it by writing a threshold
now that I have seen 2.85 and 6.19 — that is the first result becoming the
threshold, exactly what the house rule is for. Recorded, and MARL-1 should
pre-register a number for the descent's own contribution before it runs.
The decomposition to work from, all at 200 000 exemplars from an empty
0.14399: birth alone 0.05055 with 3 264 kernels, birth and descent 0.02326
with 3 648. The descent buys less than half the kernels' worth of capacity
and more than half the remaining error.

### Growth against deformation, and whether the plateau means anything (Astra's reading, tested)

Astra, on the feedback pass: five times the experience adding only ~12%
more kernels looks like a transition from growth-dominated learning to
deformation-dominated refinement, and if K(N) asymptotes then MARL looks
less like memory and more like function acquisition. The growth curve
supports the first half strongly:

    exemplars      10 000    100 000    1 000 000
    kernels          1 974      3 379        4 071
    held-out RMS   0.06930    0.03121      0.01161

K grows as N^0.233 over the first of those decades and N^0.081 over the
second, while the RMS falls by 2.69 over that same decade for 20% more
kernels. Capacity is flattening and the error is not: whatever is buying
the last decade of accuracy, it is not new kernels.

The second half needed a check rather than a reading, because there is a
duller explanation available: births stop when some kernel already reads
above `coverage`, so a plateau could be nothing more than SPACE BEING
TILED — an artefact of a hyperparameter and the cutoff's geometry, with no
epistemic content at all. Pure tiling predicts K ∝ r_cov⁻³ for
r_cov = √(−2 ln coverage). Swept at 300 000 exemplars:

| coverage | r_cov | tiling predicts | measured | ratio | gain |
|---|---|---|---|---|---|
| 0.10 | 2.146 | 1 164 | 14 674 | 12.60 | **0.77** |
| 0.20 | 1.794 | 1 992 | 2 686 | 1.35 | 5.80 |
| 0.35 | 1.449 | 3 782 | 3 782 | 1.00 | **8.14** |
| 0.50 | 1.177 | 7 049 | 5 459 | 0.77 | 7.53 |
| 0.60 | 1.011 | 11 143 | 6 414 | 0.58 | 7.09 |

Over 0.20 to 0.60 the tiling law spans 5.59× and K spans 2.39× — so
K ~ r_cov⁻¹·⁵, about the SQUARE ROOT of the tiling law, and the ratio
column walks monotonically from 1.35 to 0.58 rather than sitting at one.
The plateau is therefore not pure tiling: descent reshapes kernels to
satisfy coverage that births would otherwise have had to pay for, and it
does so more the looser the coverage. But the honest limit of this
evidence is that `coverage` is still the dominant knob on K, so the
asymptote is set substantially by a hyperparameter. The clean test is to
vary the TRUTH's complexity at fixed coverage and see whether K(∞) moves;
that needs a flag on the target and is MARL-1's.

**A third failure mode, and a new one.** `coverage 0.10` does not merely
learn badly, it DIVERGES — RMS 0.19107 against an empty model's 0.14717 —
and it does so while birthing 14 674 kernels, four times the default and
twelve times what tiling predicts. Births are refused so long that the few
kernels that exist carry weights far too large for the ground they cover;
the field goes wild, residuals stay above the threshold everywhere, and
the coverage test then starts failing on its own wreckage. So the three
ways MARL-0 is known to fail are Adam (a step that ignores the residual),
births too NARROW (`--width 0.4`, saturation), and coverage too LOW
(under-coverage, divergence) — and the default 0.35 happens to sit at the
best gain in the sweep, which was luck: it was written before any run.

### Recorded, not built

- **Parallel learning needs one ruling first.** Gradient descent is not
  order-free: sums of gradients commute, sequential steps do not, and
  Adam's moments certainly do not. A parallel MARL must compute gradients
  against the PUBLISHED parameters and apply one step at commit — Jacobi,
  not Gauss-Seidel. It fits "operators write deltas, never bricks" exactly
  and it costs convergence rate. That is a price and it belongs in the
  design before someone meets it as a bug. Trigger: MARL-0.5, the first
  time a learning event runs on a job system.
- **About ninety kernels overlap every point, and that is the cutoff's
  price.** `CUTOFF` = 32 makes a kernel live out to 5.66 widths while it is
  only USEFUL out to about 1.45, so the overlap count is 3.9³ ≈ 60 whatever
  the scale — measured 86 at 200 000 exemplars and 109 at a million,
  because descent widens kernels past their birth width. The generosity is
  there so `rbf`'s material read is exactly the entry far away, and it is
  paid for here in evaluations per prediction (288, then 345). Worth
  reading as a finding, not a nuisance. Trigger: if MARL ever needs the
  cutoff moved, it moves in rill and the shader in the same beat, and
  G17 (a) is the notification.
- **rill already has the D-dimensional evaluator MARL-3 wants**
  (`rill/src/rbf.zig`, MAX_D = 8), behind an explicit no-edge ruling
  between the repos. MARL is the first thing that will make that ruling
  cost something — but not before MARL-3, and at D = 3 nothing is needed.
- The kernel budget was never reached at the defaults (0 saturation
  events, 0/216 regions full), so the campaign's §10 saturation data comes
  from the instruments instead: `--width 0.4` saturates 111/216 regions
  with 10 779 events and drives the held-out RMS to 0.26790, worse than
  empty. Narrow births are the failure mode, not the budget — a kernel born
  at 40% of the widest the clamp allows needs eight times as many of
  itself to satisfy the same coverage, and the budget runs out first.

## MARL-1 — the five experiments, in Christian's order (Monday 2026-09-07)

Christian's ordering after MARL-0's numbers, and the rulings that came
with it: report the birth-versus-deformation comparison with its capacity
and work ratios beside it; make target complexity controllable; separate
support from responsibility; keep the under-birth divergence as an
explicit failure mode; force the saturation the natural experiment never
reached. Parallel learning stays untouched.

Every number below was predicted before it was measured, by
`tools/marl1_predict.py` — a second program that builds a SYNTHETIC basis
with MARL-0's own birth rule rather than consulting a run. That the
synthetic basis reproduces the measured overlap (81.6 against 86) is the
check that it is the right basis to be predicting from.

### 1. At identical capacity, what does deformation buy?

    arm                              RMS   kernels     updates   mean |w|
    A   births, no descent       0.05149      3264  12 019 596     0.0911
    B'  A's topology, descent    0.02394      3264   9 210 594     0.0917
    C   births and descent       0.02390      3648   9 158 380     0.0833

**RMS_A/RMS_B' = 2.15**, against a floor of 2 derived from the greedy-to-
least-squares ratio of a synthetic basis (1.49 available on the weights
alone; descent also has the geometry, and beats it). K is identical by
construction — B' reseeds from A and scores A's RMS exactly before its
first exemplar, which is the gate's own check that the reseed carries the
topology and nothing else.

The capacity control turned out not to matter, which is worth saying
plainly because the control was still the right thing to insist on:
**RMS_A/RMS_C is 2.15 as well.** Arm C's extra 384 kernels — 12% more
capacity — buy 0.2%. The confound I warned about was real in principle and
negligible in fact.

Two things fell out that were not asked for:

- **Arm A is FLAT.** 0.05293 at 40 000 exemplars, then 0.05040, 0.05076,
  0.05055, 0.05083 at 80 000 through 400 000. Birth-only reaches its
  ceiling almost immediately and a tenfold increase in experience does
  nothing for it. Everything after the topology is discovered is
  deformation.
- **The ratio therefore compounds**: 1.17, 1.54, 1.80, 2.30, 3.00 across
  those same horizons. Which exposes a gap in my own pre-registration —
  `MARL1_DESCENT_GAIN = 2` never said AT WHAT N. A floor on a growing
  quantity is not a threshold until its horizon is named. Recorded and the
  horizon named (`MARL1_DESCENT_N = 300 000`, where the ratio is 2.84);
  the number itself stays where it was written.

Arm A also does MORE work than C — 12.0M updates against 9.2M — because a
worse model leaves more exemplars above the surprise threshold. Birth-only
is not the cheap arm.

### 2. Fixed coverage, variable target complexity

`--features N --sharpness S --frequency F`, 200 000 exemplars each, and
the shell band's volume measured from the target rather than hard-coded
(it was hard-coded for one sweep, which reported a fall in density where
the truth was a rise: the band is two widths either side of a ridge, so
`sharpness` moves it).

    target              kernels   events    rms₀    gain   shell/unit³   quiet
    1 feature              3648    35 483  0.1440   6.19        8 402       0
    2 features             3829    39 395  0.2020   6.81        9 129       0
    4 features             4365    52 821  0.2753   6.54        9 350       0
    8 features            15 341  100 061  0.3828   0.33       26 608     210
    sharpness ×2           3718    37 733  0.1222   2.62       10 278       0
    sharpness ×4           3701    36 884  0.1103   1.80       10 326       0
    frequency ×2           3782    38 207  0.1443   5.96        8 537       0
    4 features, sharp ×2   4516    56 506  0.1892   2.24       10 748       0

The answer to "does capacity follow task complexity at fixed coverage" is
sharper and less flattering than the campaign hoped:

> **Kernels per unit of structured volume barely moves. What follows
> complexity is how much structure there is to tile, not how hard it is.**

Shell-band density sits between 8 400 and 10 700 across every converging
configuration — a spread of 1.3 over a fourfold change in feature count
and a fourfold change in ridge sharpness. Total capacity rises (3 648 →
4 365 for four features) exactly because the band's volume rises. The
allocation rule is GEOMETRIC.

The work is not. Events go 35 483 → 39 395 → 52 821 → 100 061 with the
feature count, and the held-out gain collapses with sharpness (6.19 → 2.62
→ 1.80) while the capacity spent on the ridge does not move. So MARL-0
cannot buy resolution with capacity: births stop as soon as space is
tiled, whether or not the residual there is resolved. **That is the
concrete case for residual-driven refinement** — the campaign's §5, and
item 6 on Christian's list — and it is now evidence rather than
anticipation.

Eight features tips the whole thing into the divergence regime of
experiment 4 (gain 0.33, 45 261 saturation events) and it is the ONE place
the quiet slab is not empty. It fails the pre-registered "zero at every
complexity" claim, and it fails it as a CONSEQUENCE of divergence rather
than of reach: recorded as a failed claim, not amended, because what it
teaches is that MARL-0's structural guarantees about where capacity goes
are conditional on the model converging at all.

### 3. Responsibility is separable from support, and most of the work was waste

Christian's ruling, implemented as he specified: support is the full
cutoff gather and prediction sums all of it, so inference semantics do not
move and `rbf.CUTOFF` is untouched; responsibility is the subset permitted
a gradient, and the NLMS normaliser Σg² is taken over that subset alone.

    R (widths)   predicted   responsible    gain     updates    work
    5.657 (all)       59.5         86.04    6.19   9 158 383   1.000
    4.0               21.0         32.57    6.25   3 467 590   0.379
    3.0                8.9         14.25    6.32   1 519 486   0.166
    2.5                5.1          8.45    6.18     907 418   0.099
    2.0                2.6          4.43    6.12     476 681   0.052
    1.5                1.1          1.95    5.04     216 044   0.024

The packing prediction (R/r_cov)³ tracks the measurement within a factor
of 1.5 to 1.8 at every radius, inside the pre-registered tolerance of 3.

The result is better than "cheaper for the same accuracy":

> **R = 3 is the most accurate setting tested — 6.32 against 6.19 — at
> one sixth of the work. R = 2.5 matches full accuracy at a tenth.**

Letting distant kernels learn does not merely cost work, it costs
ACCURACY. A kernel two hundredths of a unit away and reading 10⁻⁵ is
handed a share of a residual it cannot represent, and it moves. Only below
about four responsible kernels does convergence start to suffer (R = 1.5,
gain 5.04). So the answer to "how few kernels need to participate in
learning without harming convergence" is **about eight, from
eighty-six** — and every one of the reasons Christian gave for wanting
that number small before parallelising still applies, with a factor of ten
now attached to them.

One reporting bug worth recording: the first version of this sweep printed
86 at every radius, because the touched count was taken over the SUPPORT
set. The number that moves is the responsibility count and it had to be
counted separately. G18 (c) now asserts that it moves AND that the work
moves with it — a count that falls while the gradient loop still runs over
everything has saved nothing.

### 4. Under-birth is over-responsibility, by two independent routes

Christian's mechanism claim, pre-registered as `MARL1_OVERRESPONSIBILITY`
= 1.25, the target's own range: every diverging run must show a mean |w|
above it and every converging run below it. It separates the two
populations by two orders of magnitude, with nothing near the line.

    by REFUSAL (coverage)        by BUDGET (kernels per region)
    cov     gain   mean |w|      budget    gain   mean |w|   saturations
    0.05   0.790     13.84            4   0.165      13.59      105 538
    0.08   0.585     14.03            8   0.990      13.05      103 853
    0.10   0.419     13.83           16   0.918      12.71       95 940
    0.12   0.679     13.81           24   5.535       0.100        2 697
    0.15   0.606     13.81           32   6.092       0.086          271
    0.20   4.716      0.148           64   6.192       0.083            0
    0.35   6.192      0.083
    0.50   5.997      0.072

Two mechanisms that have nothing in common — a birth REFUSED because
coverage was satisfied, and a birth CAPPED because the region was full —
produce the same pathology and the same signature. Too few kernels are
made answerable for too much territory, weights leave the target's range
by an order of magnitude, and the resulting predictions then corrupt the
coverage decision that would have birthed more. The transition is sharp
and it is not graceful: coverage 0.15 → 0.20 and budget 16 → 24 are both
a single step from divergence to a working model.

That the same statistic separates both routes is what makes it a mechanism
rather than a correlation, and it is why G18 (d) tests both.

### 5. Deliberate saturation

`MARL1_SATURATION_BUDGET = 16` predicted that a budget that small must
saturate and the default 64 must not; both hold. What the sweep adds is
that saturation is not a graceful degradation into a smaller model — it is
a route into experiment 4's regime, and the whole transition sits between
budget 24 (2 697 saturation events, gain 5.53) and budget 16 (95 940
events, gain 0.918). A capped region cannot birth the kernel its residual
is asking for, so the kernels it has absorb the demand instead.

So the campaign's §10 instruction — record the saturation event rather
than inventing a refinement algorithm — has now been paid off with data,
and what the data says is that the saturating region needs somewhere for
the residual to GO. That is refinement's brief.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G18 (a) deformation at identical capacity | the births toggle ignored (B' is no longer capacity-controlled) | fails |
| | B' with both rates zero | executed in the gate: RMS unchanged |
| G18 (b) capacity per unit structure is set by coverage | birth made unconditional | fails |
| G18 (c) responsibility separates from support | the responsible count taken over the support set | fails |
| | gradients over the support set (count moves, work does not) | fails |
| G18 (d) under-birth is over-responsibility | the gate carries its own control, both routes | — |
| G18 (e) the budget bites below the natural occupancy | the budget test removed | fails |

G18 (b) needed a second arm before it could fail at all. Stability of
density across complexity is not a claim a mutation can break — an
unconditional birth rule produces a stable density too, for an entirely
different reason. So the gate also asserts the CAUSAL half: moving
`coverage` at fixed complexity must move the density (5 191 → 9 210), and
a birth rule that ignores coverage fails that while passing everything
else. Two mutations were reported as surviving when they had only failed
to compile; the harness now recognises a build error as inconclusive
rather than as a bite, which is the second time that distinction has
mattered.

### What this changes about the campaign

- Capacity allocation in MARL-0 is geometric, not epistemic. It tiles
  structure. The quiet slab stays empty because it has no structure, not
  because the model judged it easy — and a sharp ridge gets no more
  capacity than a smooth swell of the same band volume. **Residual-driven
  refinement is the fix and experiment 2 is its brief.**
- Work, by contrast, IS epistemic: events track difficulty even where
  capacity does not.
- The responsibility radius is a free order of magnitude, and it should be
  settled before parallelism rather than after — a tenth of the gradient
  packets, a tenth of the overlapping commits, and a locality graph with a
  tenth of the edges is a different parallelisation problem from the one
  MARL-0 would have handed over.
- Divergence has one mechanism and two doors. Birth may eventually need to
  depend on whether the update the existing kernels would need exceeds a
  bounded responsibility, not only on coverage — which is Christian's
  suggestion, and experiment 4 is the evidence for it.

## MARL-2 — the residual hierarchy (Monday 2026-09-07)

Christian's framing, which is the sentence the whole thing is built to
test: **MARL-0 has adaptive computation, but not yet adaptive
representation.** Work already follows unresolved state; capacity does
not. Refinement is the missing operation, and the design is the delta
patch — a child that learns only what its parent could not:

    f(x) ≈ parent(x) + Δchild(x)

Two levels, standalone, no recursion, no Loam tree. `src/marl.zig`'s
`Hierarchy`, `marl-run --hier`, thresholds from
`tools/marl2_predict.py` before the runs, gates G19 (a)–(c).

**On the lattice precedent.** Christian cited `~/dev/lattice` as already
containing this hierarchy — small child nodes delta-patching their parents
in situ. I looked: the repo as it stands is the mesh-topology library
(vert/edge/loop/face handles, Euler operators, BMesh parity), and the
delta-patch hierarchy is not in its README, ledger, operators or parity
docs. So this was built from his description rather than from that
precedent, and if the proposal exists it is somewhere I did not find.

### What was pre-registered, and how it came out

| | predicted | measured (×1 / ×2 / ×4 sharpness) | |
|---|---|---|---|
| `MARL2_CHILD_QUIET` child kernels in the quiet slab | 0, no slack | 0 / 0 / 0 | ✅ |
| `MARL2_PRECISION` refined regions touching the band | ≥ 0.75 | 1.000 / 0.947 / 0.941 | ✅ |
| `MARL2_WORK_RATIO` work against flat | ≤ 1.5 | 0.597 / 0.543 / 0.552 | ✅ |
| `MARL2_CONCENTRATION` child's band density over its own | ≥ 3 | 1.54 / 1.67 / 1.65 | ❌ |
| `MARL2_SHARPNESS_RETENTION` gain against flat's | ≥ 1.5 | 1.12 / 1.32 / 1.38 | ❌ |

Both refutations are left standing in `thresholds.zig` for Christian to
strike. No gate asserts either: asserting a refuted prediction fails the
suite, and moving one would be the first result becoming the threshold.

    flat MARL          RMS 0.04659   3718 kernels   9 950 176 updates
    parent alone           0.07166   3215              3 357 610
    parent + child         0.03528   4339 (child)     2 049 288
                                                   (sharpness ×2, 200 000 exemplars)

### The mechanism works

The delta semantics hold exactly. The parent is FROZEN where the child
learns — really frozen, checked byte for byte across twenty thousand
further exemplars, which matters because the responsibility radius lets an
exemplar in a neighbouring region reach a kernel across the face. The
prediction is the sum, bitwise, and each level is still the exact sum over
its own model. The child never receives an exemplar in the quiet slab and
holds nothing there, at every configuration tested.

And it is CHEAPER than flat, which was not predicted in the right
direction — 0.54 to 0.60 of flat's gradient applications, against a
prediction of "at most half again". The parent stops learning in refined
regions, so the child's work replaces the parent's rather than adding to
it, and the child's finer kernels sit in smaller responsibility sets.

### The pressure signal, and two implementations of one principle

Christian's ruling was that refinement must not fire on "residual >
threshold", because a large residual may be cheaply resolvable by ordinary
deformation. I implemented that twice, and only one of the two was doing
anything.

**What works: the POST-UPDATE residual.** Pressure is the mean residual
left after the update steps — what deformation could not remove with the
kernels it had. Accumulated instead from the residual BEFORE the steps,
precision collapses from 1.000 / 0.947 / 0.941 to 0.383 / 0.328 / 0.277
and the refiner opens 119 regions instead of 34 to 42.

**What did not: filtering to covered events.** The first implementation
also restricted the statistic's sample to learning events where `coverage`
was already satisfied — the basis saying it had the ground covered and
being wrong anyway. It made precision WORSE at every setting:

    min_events              10      25      50     150
    covered events only  0.507   0.600   0.679   0.963
    all learning events  0.919   0.923   1.000   1.000

Dropping the events where a birth happened removes exactly the events the
model handled well, which biases the mean upward everywhere and unevenly —
a structured region births more, so it reaches `min_events` later and on a
differently selected sample than a smooth one. The filter was a second,
redundant attempt at a distinction the post-update residual already makes,
and it cost precision to make it twice. Removed; the principle survives its
implementation.

**And the reason to have gated on placement at all.** When pressure is
driven by raw surprise instead, the ACCURACY barely moves — 1.09 / 1.30 /
1.35 against 1.12 / 1.32 / 1.38 — while precision falls by a factor of
three and twice as much of the parent is frozen. A gate on RMS alone would
have passed it. Christian's instruction to pre-register on where the
capacity appears is what caught it, and G19 (b) is that gate.

The threshold itself is a METHOD hyperparameter and was set the way one
honestly can be, from the statistic's own noise floor rather than from
ground truth: the unpressured population sits at 0.0044–0.0046 and does not
move with the target's sharpness — it is the surprise threshold's residue —
while the pressured population climbs 0.0060 → 0.0089 → 0.0107. One fixed
number above that floor therefore refines little on an easy target and a
great deal on a hard one, which is the property worth having.

### The two refutations, which are the finding

**Refinement is region-granular, not structure-granular.** The pressure
signal picks the right regions — precision 0.94 to 1.00 — and then inside
them the child tiles by the same coverage rule the parent used. A second
level of a geometric rule is still geometric. At sharpness ×4 the shell
band is about a tenth of a refined region's volume, so a child that
concentrated on the structure would read near 10; it reads 1.65, barely
above the parent's 1.20.

So MARL-2 replaced the TRIGGER with a residual signal and left the
ALLOCATION WITHIN a refined region geometric. That is the honest statement
of where the boundary now sits, and it is one level deeper than MARL-1's
version of the same finding rather than a repeat of it.

**And more capacity is not monotonically better.** Sweeping the child's
refinement multiple at sharpness ×4:

    refine        ×2      ×3      ×4      ×6
    child K     3 927   7 022   9 608  11 895
    ratio        1.22    1.46    1.36    1.14
    updates     1.37M   713k    457k    208k

There is an optimum at ×3 and past it more kernels score worse — ×6 has
three times ×2's capacity and beats it on nothing. The updates column says
why: finer kernels sit in fewer responsibility sets, so each is trained by
fewer exemplars, and capacity competes with training at a fixed exemplar
budget. Nothing in the prediction accounted for that, and it is probably
the more useful half of the refutation.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G19 (a) the delta semantics, and the parent really held | `freezeRegion` made a no-op | fails |
| | the parent never frozen on refinement | fails |
| G19 (b) pressure fires where the parent CANNOT represent | pressure from the pre-update residual | fails |
| G19 (c) the hierarchy beats flat and does less work | refinement never triggered | fails |

### Where this leaves the campaign

Christian's correspondence — Loam refines where a field cannot be
represented at the current spatial resolution; MARL refines where a
function cannot be represented at the current predictive resolution — is
now half demonstrated. The DETECTION half works and is precise. The
ALLOCATION half does not yet: having decided a region needs more
representation, MARL still fills it geometrically.

So the next question is not whether to recurse. It is whether a child's
BIRTH rule can be residual-driven the way its trigger now is — capacity
placed where the residual is, not where the tiling has a gap. Recursion on
top of a geometric allocator would multiply the wrong thing.

## Measurements (regime stated)

Sapling, seed 7, 3652 bricks, Ryzen 9950X3D, serial:

| build | scene build | step (≈30 changed bricks) | 46-gate suite |
|---|---|---|---|
| Debug | 2.0 s | 15 ms | ~2 min |
| ReleaseFast | 0.38 s | 1.9 ms | ~20 s |

Per phase at step 40 (Debug, serial): operate 0.02, fronts 0.24, apply
1.3, frontier 1.5, seams 9.0, finalize 6.0, build 1.2, publish 1.5 ms.

After "The step cost" (the same afternoon), the growing sapling at
100 steps: Debug 23.5 ms a step (seams 1,073 ms and finalize 673 of
2,373), ReleaseSafe 3.30 (seams 159, finalize 98, the hash 70). Units
by phase and the microseconds of each are on every `loam-run --phases`
line now.

After P2.2 (the same night), the same run: Debug 40.3 ms a step
(seams 1,918 ms and finalize 1,307 of 4,069, the hash 756),
ReleaseSafe 5.18 (seams 265, finalize 159, the hash 97) — seven new
planes on every tissue brick; the table in "P2.2 — the collar" has the
previous commit and the hard union beside it.

After the cost beat (the same night): ReleaseSafe 4.49 ms a step
(seams 234, finalize 129, the hash 78) — the two chart planes gone,
five provenance planes where there were seven. The regression line.

The attention walk's overhead (P2.1a, a standing number — it will drift
as the tree grows): leaves examined per attentive brick, sapling seed 7
at step 80, τ = 3 s, floor 1e-6:

| reader's time | attentive | examined | per attentive |
|---|---|---|---|
| at the step | 91 of 3652 | 264 | 2.90 |
| 20 s later | 68 | 240 | 3.53 |
| 35 s later | 20 | 144 | 7.20 |
| wounded sapling, step 60 | 67 | 224 | 3.34 |

The backlog, the other standing number (Christian, P2.1b's word):
obligations carried into a step, and consecutive steps it exceeded the
budget — sapling seed 7, Debug, serial: at half the active set, 0 to a
few dozen and never over; at a budget of one brick from step 81, 50
after ten steps and over on every one of them.
With 16 threads apply, finalize and the seam pass all go parallel;
ReleaseFast at 200 steps: 0.75 ms per step against 2.12 serial, the
scene build 30 ms against 237.
