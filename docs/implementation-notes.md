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

## MARL-3 — residual-driven birth, and where the allocator's failure actually lives (Monday 2026-09-07)

Christian's surgical brief: change ONE thing, the child's birth decision,
from "insufficient geometric coverage" to "persistent post-update
residual". Keep the MARL-2 parent, the pressure trigger, two levels, the
frozen-parent delta semantics, the responsibility mechanism, the
optimiser, the target family. The question:

> Can residual-driven birth make child capacity follow unresolved
> structure rather than refined-region volume?

**The answer is no, and the experiment says why — the birth criterion was
never where the failure lived.** All three pre-registered numbers were
refuted, and they were refuted by a result more useful than the one they
were written for.

### What a perfect allocator would score

Written before the runs, and it is what makes "materially better" sayable:
if every child kernel landed in the band, concentration would be the
refined volume over the band volume inside it — a ceiling that RISES with
sharpness, because a thinner ridge is a smaller share of the region
holding it.

    sharpness    ceiling    MARL-2    of ceiling
        ×1         3.54       1.54        43%
        ×2         6.48       1.67        26%
        ×4        11.01       1.65        15%

### Three birth rules, one number that will not move

    rule / sharpness    childK  concen  ceiling   ratio   mean |w|  trained
    coverage ×1           4594    1.54     3.54    1.12     0.1031    0.985
    coverage ×2           4339    1.67     6.48    1.32     0.1481    0.990
    coverage ×4           3760    1.65    11.01    1.38     0.1518    0.989
    residual ×1           1188    1.60     2.99    0.23    13.6693    0.208
    residual ×2           1193    1.58     5.79    0.43    16.6195    0.215
    residual ×4            969    1.72     9.39    0.38    15.8824    0.240
    either   ×1           4594    1.54     3.54    1.12     0.1031    0.985
    either   ×2           4345    1.67     6.48    1.32     0.1481    0.990
    either   ×4           3778    1.67    11.01    1.39     0.1518    0.989

And across four settings of the residual bar at sharpness ×2, spanning 680
to 4 345 child kernels and convergent to badly divergent, concentration
stayed between 1.57 and 1.67. **It does not move.** The slope is 1.07 to
1.08 for every rule against a pre-registered 1.5, while the ceiling
triples.

### Three findings, in the order they landed

**1. Residual-only birth under-births into MARL-1's over-responsibility
regime.** Mean |w| of 13.7 to 16.6 against a converging 0.15, with 79% of
the child's kernels never receiving ten gradient updates. This is the same
mechanism MARL-1 characterised, arriving through a THIRD door — birth
refused by coverage, birth capped by budget, and now birth gated on
residual evidence. So the coverage rule was never only about placement: it
is a TRAINABILITY FLOOR, and removing it costs more than the placement it
was being blamed for.

There is a new twist in this door. Once the child diverges, its own
residual is large everywhere, so the residual signal it uses to place
capacity is contaminated by its own failure. The allocator loses the
ability to see where to allocate precisely by allocating badly.

**2. With the floor kept (`either`), residual evidence never gets to
decide anything.** 4 345 child kernels against coverage's 4 339 — SIX
births out of four thousand. By the time a cell has accumulated the
evidence to qualify, coverage has already birthed there. The rules are not
competing; one of them fires first, everywhere.

**3. Capacity concentration is bounded by EVIDENCE concentration, and the
child's evidence stream is uniform.** This is the finding.

A birth can only happen where an exemplar is. The child is handed every
exemplar landing in a refined region, regardless of where the residual is,
so its stream is uniform over that region — and no birth rule can
concentrate capacity above the stream it is given. Measured at sharpness
×4: the band is 8.0% of the refined volume, the routed stream is 9.3% of
it (a concentration of 1.16, which is nothing), and the birth rule lifts
the kernels to 15.0% under coverage or 18.4% under residual evidence. The
rule contributes its 1.6 to 2.0. The stream contributes none of it.

### The diagnosis, tested and not built

A two-line probe — route to the child only exemplars whose parent residual
exceeds 0.05 — was run to test the diagnosis and then reverted. It is not
in the tree and it is not MARL-4; it is the measurement that says whether
the explanation above is the right one.

                       band   stream   kernels   concentration
    uniform routing    8.0%     9.3%     15.0%           1.65
    filtered routing   8.0%    22.0%     21.9%           2.11

**The child's kernels land in the band at 21.89% when the stream delivers
21.95%.** To three digits, placement reproduces the distribution it is
fed. That is the diagnosis stated as an identity, and it says where an
allocator can and cannot be fixed: not at the birth criterion, which
faithfully tiles whatever arrives, but at what arrives.

It also says routing at a fixed bar is not the whole answer either — 22%
against a ceiling of 100% is better and still not close.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G20 (a) a residual birth needs persistence AND magnitude, and spends its evidence | the persistence half dropped — a singleton is evidence | fails |
| G20 (b) residual birth alone under-births into over-responsibility | `.residual` falls back to coverage — the floor never removed | fails |
| G20 (c) concentration is bounded by the evidence stream, and the stream is uniform | route only high-residual exemplars (MARL-4's change) | fails |

G20 (c) survived its mutation the first time and the reason was a defect
in the gate, not in the mutation: `routed` was counted at the top of the
branch rather than immediately before `child.observe`, so it measured what
was OFFERED to the child rather than what reached it, and a routing filter
was invisible to it. Moved. The gate is now the one that will notice when
routing changes, which is the point of having it.

### What this leaves for MARL-4

The architectural statement stands where Christian put it, one clause
sharper:

> MARL can detect where representation is inadequate. It cannot place new
> representation according to the structure of what remains unexplained,
> **because the evidence it places from is not distributed like that
> structure.**

Two things follow, and neither is "recurse":

- The coverage rule is doing two jobs — placing capacity and keeping the
  basis dense enough to train — and MARL-3 established they are separable
  only if something else takes over the second. Any allocator that
  concentrates must carry a trainability floor of its own, or it walks
  into the over-responsibility regime by three known doors.
- Concentration is bought at the stream, not at the birth. Whether that
  should be routing, importance-weighted exemplars, or residual-proportional
  attention is the next question, and the probe above says the first of
  those moves the number in the right direction without solving it.

## MARL-4 — routing: attention is what makes adaptive capacity possible (Monday 2026-09-07)

Christian's brief after MARL-3, and it is the sharper question:

> Can MARL concentrate the learning stream according to post-update
> residual while preserving enough baseline exposure to keep the child
> trainable?

Explicitly not a hard filter — MARL-3's probe showed one reaches 22%
against a 100% ceiling and starves the trainability floor. So the stream
becomes probabilistic:

    p(route) = min(1, route_floor + route_gain · |y − parent(x)|)

`route_floor` is the floor the coverage rule had been silently supplying;
`route_gain` is the epistemic bias. Defaults are floor 1, gain 0 — route
everything — so MARL-2 and MARL-3 stay reproducible and G19 and G20 keep
measuring what they measured. Nothing else changed.

**All four pre-registered numbers held.** That is the first time in this
campaign, and they held at a cost the pre-registration did not think to
ask about, which is the more interesting half.

### The chain, one number per arrow

At floor 0.02, gain 3 — the gain chosen because the ramp should span the
residual range actually seen (max |e| ≈ 0.33 at this sharpness, so
1/0.33 ≈ 3), not because it was the setting that passed:

    sharpness   band vol   stream   stream conc   kernels   concen   RMS ratio
       ×1        0.2661    0.6196      2.33         2606     1.88      0.99
       ×2        0.1456    0.4182      2.87         2545     2.20      1.14
       ×4        0.0801    0.2762      3.45         2135     2.50      1.21

against MARL-2's uniform routing on the same targets:

       ×1        0.2661    0.2941      1.11           —      1.54      1.12
       ×2        0.1456    0.1556      1.07           —      1.67      1.32
       ×4        0.0801    0.0933      1.17           —      1.65      1.38

Christian's chain, measured end to end: sharpness rises → the residual
localises → routing concentrates the stream (2.33 → 3.45, a slope of
**1.48** against a predicted 1.3, where uniform routing scores 1.05) →
capacity follows (**1.88 → 2.20 → 2.50**, where MARL-2's was flat at 1.54
→ 1.67 → 1.65).

| | predicted | measured | |
|---|---|---|---|
| `MARL4_TRACKING` kernels over stream | 0.8 – 1.7 | 0.86 – 1.61 | ✅ |
| `MARL4_STREAM_SLOPE` ×4 over ×1 | ≥ 1.3 | 1.48 | ✅ |
| `MARL4_TRAINED_FLOOR` | ≥ 0.8 | 0.958 – 0.973 | ✅ |
| `MARL4_CONCENTRATION` at ×4 | ≥ 2.5 | 2.50 | ✅ |
| `MARL2_WORK_RATIO` | ≤ 1.5 | 0.35 – 0.48 | ✅ |

MARL-3's diagnosis survives its own remedy: capacity still tracks the
stream, at 0.86 to 1.61, now that the stream is no longer uniform. The
allocator was never broken. It was being fed.

### What the pre-registration did not ask, and should have

**Concentration is bought with evidence per kernel, and the exchange rate
is steep at the end.** At sharpness ×4, 200 000 exemplars:

    floor / gain     RMS      kernels   updates/kernel   concentration
      1   / 0      0.04423      3760          461            1.65
      0.05 / 6     0.04477      2736          305            2.13
      0.02 / 3     0.05082      2135          217            2.50

Most of the placement is nearly free — 0.05/6 buys a 29% rise in
concentration for 1.2% of RMS — and the last of it is dear: pushing to
2.50 costs 15%. The axis is not the floor and it is not the gain; it is
updates per kernel, and RMS tracks it monotonically across every setting
tried.

**And more exemplars do not buy it back.** At sharpness ×4, tripling the
budget moves the biased model from 0.05082 to 0.04806 and never reaches
uniform routing's 0.04423 — while flat MARL improves faster still, so the
hierarchy's advantage over flat FALLS from 1.21 to 0.97. The cost is not
a shortage of exemplars. It is that a kernel placed in a starved
neighbourhood is placed and not fitted, and a badly fitted kernel is worse
than none.

That is the same invariant for the fourth time, now from a fourth
direction: MARL-2's refine ×6 (11 895 kernels at 17 updates each, beaten
by 3 927 at 349), MARL-3's residual-only birth (6% trained, |w| of 16),
MARL-1's under-birth divergence, and now routing. **Capacity you cannot
train is worse than capacity you do not have** — and every mechanism this
campaign has added for placing capacity better has had to be paid for in
the evidence available to fit it.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G21 (a) the stream concentrates, more so the sharper the target, and capacity follows | the gain ignored — uniform routing behind a floor | fails |
| G21 (b) the floor keeps the child trainable, and the bias is paid for in evidence | the floor removed | fails |

G21 (a) runs its own mutation rather than describing it, because the claim
is about the DIFFERENCE between biased and uniform routing and a gate that
only measured one of them would be asserting a magnitude.

### Where the architecture now stands

Christian's reading, which the numbers support:

> Representation does not merely grow where surprise exists. Attention
> must first reshape the learning stream so that local representation has
> enough evidence to form correctly.

MARL-4 adds the clause the campaign paid for:

> …and the same reshaping starves the representation it has already
> placed. Concentration and sufficiency are in tension at a fixed budget,
> and the exchange rate is the thing to design against.

Four mechanisms have now been separated, and each turned out to be doing a
second job nobody assigned it:

- **birth** places capacity — and supplies the basis density that keeps
  the model trainable (MARL-3);
- **deformation** fits it — and is what buys everything after the topology
  is found, since birth-only is flat from forty thousand exemplars on
  (MARL-1);
- **refinement** decides where the current level cannot represent — and
  does it precisely, while allocating inside that decision geometrically
  (MARL-2);
- **routing** concentrates the evidence — and is the only thing that can
  make capacity concentrate at all, at the price of the evidence it
  withdraws from everywhere else (MARL-4).

The open question is no longer where to put capacity. It is how to spend a
fixed evidence budget across regions that need different amounts of it —
which is a scheduling problem, and Loam has had one of those since R17.

## MARL-5 — scheduling, and the granularity that made it moot (Monday 2026-09-07)

Christian's question: can an adaptive scheduler allocate a fixed learning
budget better than static residual-biased routing? Three arms at one duty
so no arm can win by processing more; scheduler state per parent region
limited to quantities the campaign already understands — need (unresolved
pressure), sufficiency (evidence per child kernel), lag (anti-starvation).

**All three pre-registered numbers refuted. The answer is no, and the
reason is granularity.**

    arm                          RMS   routed  childUpd  kernels  upd/k  concen
    A  uniform                0.05154    9932    450555     2569    175    1.70
    B  static residual bias   0.04764    7411    620823     2438    255    2.29
    C1 need                   0.05233    7756    322370     2274    142    1.85
    C2 need × lag             0.05228    7762    321710     2274    141    1.83
    C3 need × lag ÷ suff      0.05380    7545    294950     2231    132    1.75
                                          (sharpness ×4, 200 000 exemplars, duty 0.4)

Every region-level policy loses to MARL-4's per-exemplar bias by about 10%
of RMS, and by a quarter of its concentration.

### Why: the schedule is coarser than its own signal

A parent region is a sixth of the domain across. The ridge this campaign
has spent five phases chasing is a fortieth of it thick. A schedule that
routes a whole region at one probability cannot separate the exemplar on
the ridge from the one beside it — and that separation IS the mechanism
MARL-4 established.

The decisive test was a HYBRID arm, added after the first three lost: the
per-exemplar bias multiplied by the region's starvation term.

    at ~620 000 child updates      RMS       concentration
      static bias (per-exemplar)   0.04764       2.29
      hybrid (per-exemplar × lag)  0.04719       2.29
      region schedule alone        0.05237       1.78   (at 739 000 updates)

The hybrid recovers static's number to within 1% and matches its
concentration exactly. **The region term contributes nothing; the exemplar
term contributes everything.** Christian's R17 correspondence was offered
as a hypothesis to be earned, and it is not earned: Loam schedules bricks
because a brick is its unit of work, while MARL's unit of work is one
exemplar and its structure is finer than any region. The two do not
transfer.

### The control, answered

`need × lag ÷ sufficiency` was the WORST of the three policies (0.05380
against 0.05228). So evidence-per-kernel was DIAGNOSTIC, exactly as
Christian allowed it might be — a real property of the machine that the
scheduler does not want stated explicitly. And `need` against `need × lag`
came out at 1.001, indistinguishable: which is not evidence that the
largest residual is the best schedule, but that at this granularity the
whole family is dominated and the question could not be answered here.
Christian's prediction is untested rather than refuted.

### Two things the sweep found that were not asked for

**A crossover, and my first two gates sat below it.** Biased routing is
BEHIND uniform until about 175 000 exemplars and only wins after:

    N          uniform   static 0.05/6   need_lag   hybrid
    100 000    0.04977      0.05415      0.05327   0.05386
    150 000    0.05065      0.05169      0.05218   0.05273
    200 000    0.05154      0.04764      0.05228   0.04719
    300 000    0.05216      0.04702      0.05100   0.04655
    400 000    0.05138      0.04458      0.04921   0.04499

Concentrated evidence starves before it compounds — the campaign's
standing invariant, arriving for the fifth time. And **uniform routing at
duty 0.4 never improves at all**: 0.0498 at a hundred thousand exemplars,
0.0514 at four hundred thousand. It plateaus, while every biased arm keeps
descending. Spreading a fixed budget evenly does not merely learn more
slowly; past a point it stops learning.

**The Pareto improvement MARL-5 was asked to find already existed.**
Against child work rather than exemplar count:

    uniform, full duty      RMS 0.04423   work 1 733 899   concentration 1.65
    static 0.05/6, duty 0.7 RMS 0.04495   work   923 161   concentration 2.06

Within 1.6% of the best error for 53% of the work and 25% better placement.
That is the improvement the scheduler was meant to deliver, and MARL-4 had
already delivered it.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G22 (a) a region schedule is coarser than its signal; the per-exemplar term carries the routing | the hybrid's per-exemplar term removed | fails |
| G22 (b) the Pareto improvement is MARL-4's | the gain zeroed — the biased arm IS the uniform arm | fails |

Both gates name their horizon, because the crossover means an arm ordering
asserted below 175 000 exemplars is the opposite of the one above it. The
first drafts ran at 150 000 and failed for that reason, which is worth
recording: an ordering that reverses in N is not a result until the N is
stated.

### Where the campaign stands after five phases

    birth       allocates degrees of freedom — and supplies the basis
                density that keeps the model trainable
    deformation fits them — and buys everything after the topology is found
    refinement  decides where a level cannot represent — precisely, and
                then allocates inside that decision geometrically
    routing     supplies evidence — and is the only thing that makes
                capacity concentrate at all
    scheduling  arbitrates scarcity — and at region granularity has nothing
                to arbitrate that the routing rule does not already decide

The invariant has now appeared six times, from six directions, and MARL-5
adds the sharpest version of it: **spreading a fixed evidence budget
evenly does not slow learning down, it stops it.** Uniform routing at 40%
duty is flat across a fourfold increase in exemplars. The budget is not
merely scarce; where it goes is the whole of the learning.

## MARL-6 — the world moves (Monday 2026-09-07)

The first phase that tests the PREMISE rather than a mechanism. The frozen
delta semantics say `child ≈ unresolved detail of the current parent`;
MARL-6 moves the target at a known exemplar count and asks whether that
survives or degrades into `child ≈ current target − historical parent` —
the same algebra, a different architecture. Nothing repairs anything: no
thawing, reparenting, forgetting or child collapse, as instructed.

**The outcome is Christian's B**, and one of his three shapes fits almost
exactly: RMS recovers most of the way while the hierarchy's semantics
degrade — the outcome an ordinary benchmark would call success.

### What happened, at sharpness ×2, the world moving at 200 000 exemplars

                        RMS      parent    child   events  births
    stationary +100k   0.03166   0.07146  0.07386   42772     487
    small drift +100k  0.05203   0.09281  0.09330   44647     851
    large drift +100k  0.04882   0.08855  0.08795   47943    1989

The parent barely moves across the whole recovery (0.09351 → 0.09281 under
small drift) while the child's contribution climbs (0.07191 → 0.09330).
The coarse level stays wrong about the world it is in and the fine level
takes the job on. That is the degradation, stated in two columns.

| | predicted | measured | |
|---|---|---|---|
| `MARL6_STRANDED` pre-move kernels outside the current band | ≥ 0.5 | 0.795 / 0.917 | ✅ |
| `MARL6_PRECISION_FALL` precision vs the current target | ≤ 0.85 | 0.69 | ✅ |
| `MARL6_CHILD_MAGNITUDE` child's contribution, small drift | ≥ 1.5 | 1.20–1.50 | ❌ |
| `MARL6_REACTIVATION` learning events after the move | ≥ 2.0 | 1.11 / 1.28 | ❌ |

### Two of my own claims, corrected by the data

**I disagreed with Christian's expectation 6 and was half right, on the
wrong instrument.** He expected large drift to expose the frozen parent
more strongly; I pre-registered the opposite, reasoning that small drift
lands the new ridge in regions ALREADY REFINED whose parents cannot learn
it, while large drift lands it in fresh regions whose parents can. On the
child's magnitude — the instrument I chose — the ordering held 3 of 4 and
inverted at sharpness ×4 seed 7. Too noisy to carry it. On TOTAL RMS it
separates 4 of 4, and the reasoning holds.

But with a condition neither of us stated:

    pre-drift    refined regions    small     large
     100 000           36           1.28×     1.39×    ← large is worse
     200 000           38           1.64×     1.54×
     300 000           41           1.68×     1.52×    ← small is worse

(damage relative to the stationary control at the same length.)

**The harm from a small move grows with the model's own age; the harm from
a large one does not.** Ossification is an exposure that deepens, and the
crossover is where commitment to the frozen parent outweighs having a free
parent somewhere else. One point of that sweep would have been a number
pretending to be a law, which is why none of it is gated.

**And the world moving is far quieter than predicted.** Learning events
rose only 1.11× (small) and 1.28× (large) against a predicted 2.0. The
derivation assumed every exemplar on newly-wrong structure becomes an
event; the band is 15% of the domain, the two bands overlap, and most of
those exemplars were provoking events already. A system that barely
notices its world has moved is a system that will not repair itself
unprompted — which is the more useful reading of a refuted threshold.

### The gate that was confounded, and what fixing it found

G23 (a)'s first draft compared the drifted hierarchy's parent against a
STATIONARY control's and found it 1.23× worse. But the control had 160 000
exemplars on one world and the drifted arm 60 000 on its new one, so any
learner whatever would have shown that. **The number measured the budget,
not the mechanism.**

The named mutation then SURVIVED, which is what exposed it: making
`freezeRegion` a no-op left the parent 1.32× off, no better. Freezing was
never the operative commitment — in a refined region `observeOne` returns
after routing, so **the parent never observes there at all**. Unfreezing
only changes whether a neighbouring region's exemplar can reach a kernel
across the face.

Rebuilt as drift against drift at identical budget, with each design
choice switched off in turn:

    frozen, parent cut off from refined regions   total 0.04905
    unfrozen, still cut off                             0.05051
    parent also observing in refined regions            0.06662

**Both choices are vindicated by the experiment designed to break them.**
Letting the parent keep learning where the child is learning improves its
own error and makes the PAIR's much worse, because the child is learning
`y − parent` while the parent moves underneath it. That is MARL-2's
freezing rationale, confirmed under exactly the conditions expected to
falsify it.

So the honest headline is not "the frozen parent fails under drift". It is:

> **Freezing survives a moving world. What does not survive is the
> capacity already committed to where the world used to be.**

91.4% of the child kernels alive at a large move are still outside the
band when the run ends, against a stationary control's 74.0%; refinement
precision against the current target falls to 0.618 from 0.973. The
kernels cannot follow — MARL-0 measured centre drift at 0.0009 of the
domain over a whole run — and a region once refined is never unrefined.

### Hysteresis: no memory, only accumulation

The cheap diagnostic, and it is unambiguous. Moving the shell back to
where it started:

    the moment it returns   RMS 0.10076   against 0.03528 when it left
    after another 100 000        0.04113   with 7 883 child kernels (from 4 339)

The return spike is the same magnitude as the original departure — the old
representation confers **no advantage whatever** on its own former world —
and the child population nearly doubled without recovering the accuracy it
had. A residual hierarchy with frozen historical structure does not
possess a primitive memory. It possesses corrective archaeology, and the
archaeology accumulates monotonically.

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G23 (a) freezing survives the move; the parent cannot repair and the child takes over | the parent made to observe in refined regions too | fails |
| G23 (b) capacity is stranded where structure used to be; refinement describes a world that has gone | none needed — the gate carries a stationary control at the same length | — |

### What MARL-7 has to be about

Not thawing. The experiment says freezing is right and the parent's
silence in refined regions is right. The thing that does not survive is
**committed capacity that cannot be recalled**, and the two mechanisms
that would address it are the two this campaign has deliberately never
built: unrefining a region whose structure has left, and letting a child
kernel die. The campaign's §15 called that erosion, and MARL-6 is the
first phase to produce a concrete reason to want it.

Christian's own ordering still stands ahead of that, though: the
responsibility-radius debt is a 6× multiplier on the evidence budget, and
every conclusion about scarcity from MARL-3 onward was measured while
paying it.

## MARL-6R — the learning unit corrected, and what survives it (Monday 2026-09-07)

Christian's interstitial, and deliberately boring: no new mechanism, only
the responsibility radius moved from full support to 3, the regime MARL-1
established and every phase since ignored. The question is not whether
that is better — MARL-1 answered it — but **which conclusions from MARL-2
to MARL-6 survive when the unit cost of learning is corrected.**

### The five anchors

**Stationary refinement.** Accuracy is indifferent; work is not.

    sharpness   R = 5.657                      R = 3
       ×1       0.02076  1 973 874  430/k      0.02116   322 914   72/k
       ×2       0.03528  2 049 288  472/k      0.03481   352 203   77/k
       ×4       0.04423  1 733 899  461/k      0.04479   303 990   77/k

Within 1.3% on every target, at a sixth of the work. Kernel counts,
concentration and refinement precision all unmoved.

**Routing (MARL-4).** The trade survives; the efficient regime does not.

    floor/gain    R = 5.657                    R = 3
      1 / 0       0.04423  461/k  conc 1.65    0.04479  77/k  1.70
      0.05 / 6    0.04477  305/k       2.13    0.04729  56/k  2.16
      0.02 / 3    0.05082  217/k       2.50    0.05095  41/k  2.56

Concentration still trades against evidence, and the exchange rate is
STEEPER: at full support 0.05/6 bought +29% concentration for +1.2% of
RMS, and at R = 3 the same setting costs +5.6%. The "broad efficient
regime" was partly an artifact of the waste — six times redundant gradient
work is slack, and starving the stream matters less when there is slack to
take it out of.

**The MARL-5 crossover is gone.** At full support biased routing lost to
uniform until about 175 000 exemplars; at R = 3 it wins at every horizon
tested, from 100 000 to 800 000. The crossover was the biased arm starving
early, and a sixfold cheaper learning event feeds it sooner.

**Drift is indifferent to the correction.** Every MARL-6 number reappears
within a few percent: small drift 0.05018 against 0.05203, large 0.04861
against 0.04882, stranding 0.921 against 0.917, precision falling to 0.66×
against 0.69×, small drift still worse than large. Committed capacity is
about commitment, not about gradient economics.

### The finding: the "critical evidence" transition was a confound

Swept in the corrected units, evidence per kernel degrades RMS smoothly
and monotonically, and nothing goes pathological:

    duty     RMS      kernels   updates/kernel   trained   mean |w|
    0.05   0.06131      669           6           0.149     0.142
    0.10   0.05871     1190          10           0.366     0.153
    0.20   0.05723     1888          17           0.657     0.158
    0.40   0.05173     2727          31           0.817     0.156
    0.70   0.05131     3437          53           0.894     0.152
    1.00   0.04479     3973          77           0.925     0.147

Six updates per kernel — a tenth of what the campaign called catastrophic —
and the weights are healthy at 0.142. **There is no cliff.** So the
campaign's repeated sightings of "capacity you cannot train is worse than
capacity you do not have" were reading two different things as one:

- **Under-BASIS-DENSITY** is the catastrophe. Coverage refused, budget
  capped, residual-only birth — three doors, all producing mean |w| of 13
  to 17 and divergence. Kernels too sparse to cover their ground, each
  made answerable for territory it cannot represent.
- **Under-EVIDENCE** is a gradient, not a cliff. It costs accuracy
  monotonically and never destabilises anything.

At full support the two were coupled — a sparse basis also means fewer
kernels overlap any point, so each gets fewer updates — which is why they
read as one phenomenon for five phases. Correcting the learning unit
separates them.

**That matters directly for MARL-7.** Kernel death reduces basis density,
which is the dangerous axis. Withdrawing evidence is safe. An erosion
mechanism that removes kernels must hold density, and one that merely
stops feeding a region need not.

### What survives, of the five asked

| | |
|---|---|
| 1. capacity you cannot train is worse than none | **amended** — true of density, not of evidence |
| 2. biased routing eventually beats uniform at fixed duty | **survives, strengthened** — no crossover left |
| 3. concentration trades against evidence sufficiency | **survives, steeper** |
| 4. frozen residual hierarchy preferable under drift | **survives unchanged** |
| 5. obsolete capacity accumulates after drift | **survives unchanged** |

### The recommendation, and what was deliberately not done

The default stays at full support, so G17 through G23 keep measuring what
they measured and the campaign's record stays comparable. G24 is the gate
that pins the correction — 0.980× the RMS for 0.184× the work — and MARL-7
should run at R = 3 from its first line, because pricing birth and death
against a learning event that costs six times what it needs to would be
pricing the wrong thing twice over.

## MARL-7 — erosion, and there was nothing to erode (Monday 2026-09-07)

Christian's split — KERNEL DEATH for locally useless basis functions,
UNREFINEMENT for a child level whose parent is sufficient again — with the
question MARL-6 finally earned: *can obsolete representation be retired
without destroying useful residual structure?*

**The premise does not hold. The representation in question is not
obsolete.** Two measurements taken before any mechanism was written scoped
the phase, and a third after it closed the question.

### One: obsolete kernels do not self-identify

Mean |w| of the child kernels alive when the world moved, after recovery:

                   outside the current band   inside it   born since
    stationary            0.0832               0.3214       0.0807
    small drift           0.1231               0.3278       0.1309
    large drift           0.1219               0.3290       0.1555

Drift makes the "obsolete" kernels BIGGER, not smaller, and they carry
less than the kernels born since the move. Weight does not separate
obsolete from useful in either direction.

### Two: they are load-bearing

Silencing every pre-move child kernel now outside the band:

    stationary   RMS 0.03082 → 0.04373   (1.42×)
    small drift      0.05018 → 0.07430   (1.48×)
    large drift      0.04861 → 0.07573   (1.56×)

So the corrective archaeology is not separable capacity sitting beside the
useful kind. It is a contamination INSIDE otherwise-useful kernels — the
same kernel fits the swell's fine structure and cancels the frozen
parent's stale contribution — and no deletion takes one without the other.
**Kernel death has nothing to target**, which is why MARL-7 became
unrefinement only.

### Unrefinement: built, precise, and it does not repay

A region retires when the parent's error there has grown past what it was
when the child was created to absorb it. The child's kernels go and the
parent's are unfrozen in ONE act, because the correction and the thing it
corrects are only removable together.

The trigger has to be a DECAYING MAX, not a mean, and the reason is this
campaign's recurring one: a region is a sixth of the domain across and the
structure that leaves is a fortieth of it thick, so a 0.9-amplitude error
over a fifth of a region's volume averages down to a factor barely over
three. The mean fired on two thirds of the right regions; the peak fires
on all of them. **Granularity, for the third time** — after MARL-2's
allocator and MARL-5's scheduler.

And it does not repay, at any sensitivity or horizon:

                                    +100k      +400k
    no unrefinement (small drift)   0.05018   0.03308
    unrefine ×2                     0.05215   0.03312
    unrefine ×3                     0.05005      —
    unrefine ×2, parent RESET too   0.05461   0.03343

Resetting the parent's stale kernels rather than merely thawing them does
not help either. Retiring the level does not repay because the level was
not the problem.

`MARL7_STATIONARY_QUIET` = 0 holds at factor 3 across 721 000 exemplars
and fails at factor 2 by 300 000 — quiet-when-still is a property of a
threshold, not of the mechanism, so it is recorded rather than gated.

### Three: what is actually wrong, over six moves

    move    RMS       parent    child K   parent K   mean |w|
      0   0.03082    0.07123      5233      3284      0.134
      1   0.04572    0.09384      5784      3316      0.155
      2   0.04499    0.09201      6922      3353      0.144
      3   0.04468    0.09923      7823      3379      0.146
      4   0.04611    0.09500      9106      3408      0.137
      5   0.04773    0.10797     10185      3423      0.132
      6   0.04424    0.09928     10997      3431      0.123

**Accuracy is flat. Capacity grows linearly, about a thousand kernels per
move, with no sign of saturating.** Weights stay healthy throughout. With
unrefinement on, the same run ends at 10 878 against 10 997 — a 1%
difference for fifteen retirements.

So MARL-6's "corrective archaeology" was the wrong metaphor and this phase
is what corrected it. Nothing is decaying, nothing is dead, and nothing
needs burying. The model handles a moving world about as well after six
moves as after one; what it does not do is REUSE anything. Every world
costs a fresh allocation, and the old allocation keeps earning its keep
somewhere else, which is why it cannot be deleted and why deleting it
hurts.

> **The pathology is not that old representation goes bad. It is that new
> representation is always bought rather than borrowed.**

### The gates, and what each was paid for

| gate | mutation | result |
|---|---|---|
| G26 (a) the capacity a moved world leaves is load-bearing | none needed — the gate asserts silencing HURTS, and the null it rules out is its own subject | — |
| ~~G26 (b) unrefinement fires on departed regions~~ | the mean instead of the peak (0.875); retiring on AGE ALONE (0.969) | **withdrawn — both survived** |

G26 (b) was written, passed at 1.000 precision, and then withdrawn before
it shipped because it could not fail. Retiring on age with no reference to
the parent's error at all scored 0.969 across 32 regions. The confound is
in the EXPERIMENT, not the trigger: on a drift test the regions refined
longest ago are exactly the regions refined before the world moved, which
are exactly the departed ones. Age and departure are the same variable
here, so any policy preferring older regions scores well.

The peak-versus-mean difference is real — 1.000 against 0.667 at factor 3
with the world moving at 200 000 — but it reproduces at one setting and
not another, so it is recorded and not asserted. What would discriminate
is a world where structure leaves regions refined at different times,
which this target does not provide. A fixture problem, and MARL-8's if it
needs the metric.

Three of MARL-7's four pre-registered numbers were refuted, and the fourth
holds only at a setting. That is the correct outcome for a phase whose
premise was wrong: the predictions were all about how well retirement
would work, and retirement was never the operation this needed.

### What MARL-8 would have to be about

Not erosion. **Reuse.** The question is whether a kernel that was fitted
to one world can be RE-POINTED at another — its position and shape are a
sunk cost that the descent already paid for, and MARL-1 established that
deformation is what buys everything after the topology is found. A model
that could re-point instead of re-buy would break the linear growth
without deleting anything, which is the only direction these measurements
leave open.

The obstacle is visible already: the kernels cannot move (centre drift is
0.0009 of the domain over a whole run), and they cannot move BECAUSE
locality is exact and their gradients vanish outside their own support.
The property that made MARL-0 cheap is the property that stops MARL-8
being possible in its obvious form. That tension is worth stating before
anyone tries.

## MARL-8 — recycling, and why geometry is not a transferable asset (Monday 2026-09-07)

MARL-7 left the pathology exactly stated: capacity is always bought, never
borrowed. MARL-8 is my own proposal for borrowing it — recycle at the
refine/unrefine boundary. A retiring region's child is POOLED rather than
destroyed; a refining region draws from the pool, translated to its own
origin, instead of starting empty. Positions and shapes carried, weights
reset.

**It does not work, and the reason is the useful part.**

### What was predicted, and what happened

| | predicted | measured | |
|---|---|---|---|
| `MARL8_GROWTH` population, with over without | ≤ 0.85 | **1.045** | ❌ wrong direction |
| `MARL8_NO_REGRESSION` RMS, with over without | ≤ 1.05 | 1.030 | ✅ vacuously |
| `MARL8_ADOPTION` transplants that acquire weight | ≥ 0.5 | 0.723 | ✅ and withdrawn |

Six moves, unrefinement at factor 2, R = 3:

    move    RMS (none)   K (none)    RMS (recycle)   K (recycle)   moved
      0      0.03079       5203        0.03067          5242          58
      3      0.04560       7747        0.04522          8135         744
      6      0.04453      10878        0.04581         11346         961

961 kernels transplanted, ~493 births suppressed. Each borrowed kernel
saved about half a purchase, so the population went UP. And the accuracy
is untouched — not merely at the end but at every point of the recovery
transient, which is where a pre-fitted geometry should have shown up if it
was worth anything:

    large drift          +1k       +20k      +100k      +400k
    no recycling       0.10288    0.07378   0.04761    0.03338
    recycling          0.10288    0.07379   0.04753    0.03384

### Why: geometry is cheap locally and worthless imported

My argument for carrying geometry rested on MARL-1 — deformation buys
2.15× over birth-alone at fixed topology, so geometry is the expensive
thing and weights are the cheap convex thing. That reasoning was sound
about WHERE the value is and wrong about WHEN.

Deformation's 2.15× accrues over a whole run of fitting geometry **to its
own local data**. It is not a startup cost that can be pre-paid. A
newly-refined region has a hundred thousand exemplars to fit its own
geometry with, so arriving with someone else's costs it nothing and saves
it nothing. The bottleneck was never acquiring geometry; it was having the
RIGHT geometry for THIS data, and that can only be found here.

> **Geometry is not a transferable asset in this architecture. It is cheap
> to acquire locally and worthless imported.**

Donor selection makes no difference either — nearest-region against
most-recent gives 11 346 against 11 362 — because at realistic retirement
rates the pool is a one-deep buffer and there is no choice to make. I
built the selection to fix a flaw that the retirement rate had already
made unreachable.

### A second metric withdrawn, and it was mine again

`MARL8_ADOPTION` held at 0.723 and means nothing. NLMS distributes a
residual over whatever basis is present, so a transplanted kernel anywhere
with support acquires weight whether or not it was worth carrying.
Adoption measures PRESENCE, not usefulness. That is the second metric this
campaign has had to withdraw for being unable to fail — after G26 (b)'s
precision, which age alone scored 0.969 on — and both were mine. The
pattern in both: I measured a quantity the mechanism trivially produces
rather than the effect the mechanism was supposed to have.

### What survives

One design decision, gated: **a transplant is inert at the moment it
lands.** Weights reset to zero means the prediction is unchanged bit for
bit by the act of transplanting, and the convex part is relearned against
the recipient's own parent. Carrying the donor's weights would inject a
correction fitted to a DIFFERENT parent's error, which is the one way this
could have been actively harmful rather than merely useless. G28 holds it,
and the mutation — letting the weights ride along — breaks it.

The mechanism stays in the tree behind `--recycle`, default off, so a
later phase can re-test it cheaply if the fixture changes.

### What this says about reuse generally

MARL-8 closes reuse in its TRANSPLANT form and says nothing about the
other form. A dictionary of shapes is a different proposition: it does not
carry specific geometry between places, it constrains the SPACE of
geometries so that each kernel has fewer parameters to fit at all. That is
a representational change rather than an allocator one, and this result
does not bear on it.

But there is a sharper reading available, and it is the honest one to
carry forward. If geometry is cheap to acquire locally, then "capacity is
always bought" costs only kernel COUNT and not learning. And a model whose
kernel count grows linearly with the number of genuinely distinct worlds
it has seen may simply be paying the correct price. The campaign has never
tested a world whose new structure is unlike its old — every drift has
been the same shell translated — so the question of whether that growth is
a pathology or an honest bill is still open, and it is a fixture question
before it is an architecture question.

## MARL-9 — per change, or per thing learned? (Monday 2026-09-07)

MARL-8 left one question open and named it a FIXTURE question: every drift
this campaign had run was the same shell translated, so "capacity grows
with the number of moves" could not be told apart from "capacity grows
with the amount of distinct structure". The two had been the same number
all along.

Two arms, six moves each, same budget. **CYCLING** alternates between two
worlds — six changes, two worlds' worth of structure. **WALKING** visits
six different ones. No new mechanism; only a fixture that can tell the two
currencies apart.

    move   WALK: RMS   child K      CYCLE: RMS   child K
      0      0.03082     5233         0.03082     5233
      1      0.04363     7373         0.04363     7373
      2      0.04808     9684         0.03742     8344
      3      0.04729    11796         0.04286     9089
      4      0.05001    14055         0.03721     9616
      5      0.04781    16168         0.04081     9984
      6      0.04514    18031         0.03182    10355

**Capacity is paid per thing learned, not per change.** The walking arm's
marginal cost is flat at about 2 100 kernels a move. The cycling arm's
decays — 2 140, 971, 745, 527, 368, 371 — and over twelve moves falls to
159 and is still falling. Final populations 18 031 against 10 355: a ratio
of 0.574 against a pre-registered 0.9, refuted in the direction that was
worth being wrong about.

And the cycling arm is not merely cheaper, it is MORE ACCURATE (0.03182
against 0.04514), which is what a world with half the distinct structure
should be. Its error on each world improves across visits: world B goes
0.04363 → 0.04286 → 0.04081 → 0.04066 → 0.03791 over its five returns.

### What this overturns

**MARL-6's hysteresis reading was wrong, and it was mine.** That measured
ONE round trip, saw the return spike at full magnitude, and I wrote "no
memory, only corrective archaeology". The spike is the TRANSIENT. The
settled state is not it — over repeated visits both the error and the
marginal cost improve, so there is memory, and it is substantial.

**MARL-7's pathology was overstated.** "Capacity is always bought, never
borrowed" is true only of structure the model has never seen. On
recurrence it borrows automatically, with no mechanism whatever.

**MARL-8's failure is now fully explained.** Recycling added nothing
because there was nothing to add: the model already reuses capacity on
recurrence. An explicit transplant was solving a problem the architecture
had already solved implicitly — which is precisely what the measurements
said, in the flattest possible way, at every timescale.

Three phases' conclusions moved on one fixture change. The lesson is the
one MARL-8 half-stated and then did not act on: a campaign that has only
ever tested one kind of world cannot tell what its numbers are counting.
I named that as a fixture question and then built MARL-8 anyway before
answering it, which cost a phase.

### What the pathology actually is

Not that capacity is bought rather than borrowed. It is:

> **The model pays in full for structure it has never seen, and almost
> nothing for structure it has. Growth is linear in the world's
> complexity, not in its rate of change.**

That is a much healthier property than three phases of this campaign
believed, and it is arguably the correct behaviour for a continual
learner. Whether the residual ~160 kernels a move on a fully-recurrent
world eventually plateaus or accumulates without bound is the one thing
twelve moves cannot settle.

### The gate, and what it was paid for

| gate | mutation | result |
|---|---|---|
| G29 capacity is paid per thing learned, not per change | the cycling arm given distinct worlds — it becomes the walking arm | fails |

A fixture mutation rather than a code one, which is right here: the claim
under test is about what the fixture can tell apart.

## MARL-10 — the growth is logarithmic (Monday 2026-09-07)

MARL-9 left one thing twelve moves could not settle: on a fully recurrent
world the marginal cost of a revisit decays, but to ZERO or to a small
constant? Logarithmic growth is effectively bounded at any practical
horizon; linear growth at 159 kernels a move is not.

This was not a threshold picked from a range. `n·ΔK` over MARL-9's twelve
points is flat at 2034 (spread 1776–2290, no trend), so ΔK ≈ A/n and
cumulative growth is K₀ + A·H(N). Eighty moves is where that stops being
indistinguishable from a linear tail. The law was written down, then the
run was made.

      N    measured   harmonic   linear tail   meas/harm
     12      12 584     11 938        12 584       1.054
     20      13 474     12 944        13 856       1.041
     40      14 737     14 329        17 036       1.029
     60      15 601     15 145        20 216       1.030
     80      16 241     15 726        23 396       1.033

**The law holds, at 1.033 against a pre-registered ceiling of 1.15**, where
a linear tail would have reached 23 396. And it holds throughout rather
than at the ends — n·ΔK by successive stretches of the run: 1972, 1764,
1890, 2166, 2252.

**And the model gets better, not merely survives.** RMS goes 0.02635 at
move 12 to 0.02234 at move 40 to 0.02237 at move 80 — a ratio of 0.849
against a stability ceiling of 1.25. That check existed because a bounded
population proves nothing if it is bounded by the thing having stopped
working, and it is the more interesting half of the result: eighty
world-changes, and the eightieth world is predicted better than the
twelfth was.

One honest caveat on the test. The run used 200 000 exemplars a move
rather than the 100 000 the fit was taken from, because `--drift-repeat`
reads `--exemplars` and that defaults to 200 000 — a default of mine, not
a choice. The law survives the unasked-for doubling with A drifting about
8%, which is a stronger result than the one intended: **the growth
constant barely depends on how long each world is shown.**

### Not gated, and why

Eighty moves at 200 000 exemplars is roughly ten minutes, which does not
belong in a suite that runs on every commit. Reproduce with

    zig build marl -- --sharpness 2 --responsibility 3 \
        --drift-mode cycle --drift-repeat 80

The campaign has one other long-horizon claim recorded this way and the
same rule applies: a measurement whose cost exceeds the suite's budget is
recorded with its command, not smuggled in at a scale that no longer tests
it.

### Where the campaign ends up

    The model pays A/n for the n-th visit to a world it has seen, so
    total capacity grows as A·log(N) in the number of world-changes and
    linearly in the number of DISTINCT worlds. Accuracy improves across
    recurrences and holds.

MARL-7 called this "corrective archaeology", MARL-8 tried to fix it with a
transplant, and both were describing a pathology that a different fixture
dissolved. What the architecture actually does with a repeating world is
consolidate: it pays full price once, a decaying remainder thereafter, and
ends up more accurate than it began. Whether that survives contact with
worlds less kind than a translated shell is the campaign's standing
question and always has been.

## MARL-11 — the marble, and the first thing the campaign did not write (Monday 2026-09-07)

Ten phases and every comparison in them was MARL against MARL. `rbf.fit`
is the first external baseline: the same anisotropic Gaussian held bit for
bit by G17 (a), the same `CUTOFF`, the same evaluator, fitted by BATCH
ADAM to a real material field, and gated since before `marl.zig` existed.

MARL needed **no changes at all** to be measured against it. `observe(x,
y)` has always taken an external exemplar; what was missing was a target
worth handing it and something to lose to.

### The bridge is its own file, and that is the design decision

`src/marble.zig` imports `marl` and `rbf` and is imported by neither.
`marl.zig` must not learn what a `bark.Volume` is — Christian's split puts
Loam's FIELD STORAGE outside MARL, and a learner that imports the sim's
sample planes to get a training set has crossed it by the back door. And
`rbf.zig` must not learn what a `marl.Model` is: it is cross-repo pinned,
read by rill and by matryoshka's shader, and a learning experiment must
not be able to move the kernel out from under three renderers by
refactoring. The two additions to `rbf.zig` are `vein_pool` and
`vein_seed`, both defaulting to what the marble has always been fitted
with, both implemented by handing the draw an EMPTY vein list rather than
by a branch — so the hot path is untouched and the existing gates cannot
notice.

### The two oracles, and the 2×2

`rbf.fit` does not start level. It seeds centres ON vein voxels and draws
half its pool FROM vein voxels. Both are hand-built versions of exactly
what MARL-3 and MARL-4 spent two phases discovering the model could not do
for itself. So the phase is a 2×2, one variable a cell, capacity matched
exactly (each rbf arm runs at the count the MARL arm beside it discovered)
and DATA held equal — MARL sees each exemplar once, rbf gets the same pool
and may re-read it, which is generous to rbf by its 4.7 passes and is the
only matching that is unambiguous.

The gate's fixture, seed 11, 32 768 distinct exemplars:

| arm | learner | kernels | RMS band | conc. | /ceiling | seconds |
|---|---|---|---|---|---|---|
| A | rbf, batch Adam, oracle | 1594 | 0.05564 | 8.93 | 0.84 | 6.43 |
| B | rbf, batch Adam, blind | 1551 | 0.07347 | 1.33 | 0.12 | 6.08 |
| C | MARL, online NLMS, oracle | 1594 | 0.08403 | 5.85 | 0.55 | 0.35 |
| D | MARL, online NLMS, blind | 1551 | 0.14598 | 4.24 | 0.40 | 0.13 |

Two of the four pre-registered numbers held and two were refuted.

**HELD — capacity concentration, 4.17 against a prediction of 4.11.** The
closest any number in this campaign has come to its own pre-registration,
and it is the geometric argument being right rather than luck. A real
field's matrix is EXACTLY zero, an empty model predicts EXACTLY zero, and
surprise below θ produces no learning event — so §8's quiet slab arrives
on a field nobody designed to have one. The dilution is the model's own
tail: a newborn carries the residual as its weight and reads above θ out
to 2.54σ, so cancelling its own leak costs kernels on the matrix side.

**HELD — C/A at 1.51.** With the oracle given to both, one pass of local
NLMS costs half again what 600 batches of global Adam cost.

**REFUTED — B/A at 1.32 against a floor of 1.5.** The dead-kernel argument
is sound (a uniformly seeded kernel beyond `CUTOFF_R·vein` of any vein has
a gradient of exactly zero and Adam never moves it), but the N^(−1/2) step
over-priced it: the live kernels widen to cover more, and a sheet's error
is dominated by the thin direction that more kernels along it do not help.
It does not invalidate the phase — the oracle still moves MARL by 1.74, so
arms C and D are firmly different tests, which is all the floor protected.

### REFUTED — D/B at 1.99, and it is the campaign's headline loss

Pre-registered as a CEILING at parity, deliberately, so that it could
embarrass the campaign. It did.

Both halves of the reasoning were **correct** and the conclusion did not
follow. MARL's concentration is 4.17 against arm B's 1.33, so
surprise-driven birth really does place capacity three times better than
blind seeding, exactly as MARL-3 said. Arm B really is carrying dead
kernels. And MARL loses anyway, by nearly two.

The error was assuming **placement was the binding constraint** — which is
what ten phases of placement work makes very easy to hold without noticing
it is an assumption. The campaign had never once been in a position to see
anything else bind, because it had never had an opponent.

### What actually binds, and G31 (c)

Arm D alone, past the equal-data protocol:

| exemplars | kernels | RMS band | conc. |
|---|---|---|---|
| 32 768 | 1583 | 0.14255 | 4.17 |
| 131 072 | 2403 | 0.09237 | 3.63 |
| 524 288 | 2928 | 0.06492 | 3.61 |
| 2 097 152 | 3285 | 0.05145 | 3.75 |

The RMS falls 2.8× and crosses BOTH rbf arms — blind (0.0732) between the
second and third rows, and the ORACLE arm (0.0546) by the fourth. The
concentration does not move.

So the online learner is not a worse fitter than batch Adam. It is a
**hungrier** one, and it buys kernels rather than passes to get there:
3 285 against 1 583 for the same field. Which is MARL-7's "capacity is
always bought, never borrowed" arriving from a direction the campaign had
not tried — MARL-7 found it in a moving world, and it is just as true in a
stationary one given more of the same stream.

G31 (c) was written AFTER the refutation and asserts DIRECTION with no
magnitude, precisely because it is post hoc. It rests on MARL-6R's prior
finding that under-evidence is a smooth gradient rather than a cliff: if
the loss were representational, more of the same stream would not help.

`MARL11_DISCOVERY` stays at 1.0, refuted, for Christian to strike. The
equal-data protocol is what makes the 2×2 a comparison, and a threshold
relaxed until the result clears it measures nothing.

### The real marble, and why raw concentration does not travel

`loam-run --scene marble --steps 110 --rbf-arms`, 64³ over an extent of
40, seven veins, seed 7 (a tool run, ReleaseSafe, 36 s including the sim
and the bake):

| arm | kernels | RMS band | conc. | /ceiling |
|---|---|---|---|---|
| A | 3758 | 0.14036 | 3.45 | 0.95 |
| B | 3653 | 0.15780 | 1.09 | 0.30 |
| C | 3758 | 0.18588 | 2.33 | 0.64 |
| D | 3653 | 0.21954 | 1.88 | 0.52 |

B/A 1.12, D/B 1.39, C/A 1.32 — every gap NARROWER than on the fixture, and
the reason is that the marble is **27.6% birth-eligible** where the fixture
is 9.4%. Concentration's ceiling is 1/f, so it is 3.62 here and 10.67
there, and the raw numbers say the opposite of the truth: 4.24 on the
fixture is 0.40 of what was available and 1.88 on the marble is 0.52 of it.
**The same allocator does BETTER on the harder field.** The report grew a
`/ceiling` column because of this; comparing raw concentration across two
fields is a mistake waiting to be made, and I nearly made it.

Two seeds and two fields, the same story: MARL places well and fits short.

### The conversion, and why it is gated bitwise

A model on the unit cube becomes an `rbf.Set` in a volume's units by
μ′ = Eμ and L′ = L/E. With E a power of two that is exact in f32, and so
is the READ — (q/E − μ) and (q − Eμ)/E round identically, because rounding
a difference commutes with scaling by a power of two. So a MARL model **is**
an `rbf.Set`, bit for bit, and G31 (a) checks 1024 probes as bit equality
with no tolerance. The set is the asset a renderer loads; an ε would let
the learner and the shader drift in the last places until one of them
showed something else and nobody was told.

MUTATION: convert at an extent of 40 instead. Still exact in the algebra,
still agreeing to an ulp or so — and the bits differ, which is what says
the gate is testing the rounding argument rather than the transcription.
The real marble's extent IS 40, so this is not a hypothetical.

### The gates, and what each was paid for

- **G31 (a)** the conversion, bitwise, and the fixture's own geometry.
  Paid for by an assertion that the sheet's blend peaks above 0.9: it does
  not, it peaks at 0.874, because a cell is 1.0 against a half-thickness of
  0.9 and the trilinear read never sees the middle. That is the fixture
  being honest — the real marble is baked at the same fidelity, so a
  fixture that resolved its own structure would be the easier problem.
- **G31 (b)** the 2×2. Asserts capacity is matched, the two thresholds that
  held, that the oracle is a real variable on both sides (direction only —
  the magnitude was refuted), that MARL out-places blind rbf by more than
  2×, and that it loses anyway. That last one FIRES IF MARL EVER WINS,
  which is the notification wanted: the ledger would then be wrong.
- **G31 (c)** the evidence gradient, at 1× and 4×. Direction only.

The suite grows by about 14 s, almost all of it the two rbf arms at ~1 550
kernels. That is a real cost and it is where the phase's content is.

### A harness bug worth recording

The first run printed `responsibility 5.66`. `marbleArms` did `mo.m = o.m`,
which overwrote `ArmOptions`'s pre-registered radius of 3 with `Opts`'s
default of `CUTOFF_R` — so the campaign's first external baseline ran at
the radius MARL-6R had already retired. Fixed with an explicit `resp_set`
flag rather than a sentinel value.

It cost nothing in the end (RMS 0.14331 at 5.66 against 0.14255 at 3, with
a fifth of the updates), which is G24 confirming itself on a field it was
never measured against. But it was luck, not design.

### Where this leaves the campaign

    MARL places capacity better than a blind batch optimiser and fits it
    worse. The gap is EVIDENCE, not placement, and it closes with the
    stream — at a price paid in kernels rather than in passes.

Two things follow for the applications. An irradiance or occlusion cache
sees each sample once and accumulates them forever, which is the regime
where MARL's hunger is free and Adam's re-reading is impossible — so the
loss measured here is against a baseline that could not be run there at
all. And 48× the wall clock to produce a model of the same size (0.13 s
against 6.08) is not a curiosity when the alternative is a bake — though
it must be read honestly: 4.7 of that factor is rbf's extra passes over
its pool, and most of the remaining ~10× per sample is that `rbf.fit`
sums over ALL kernels where MARL does a 27-region gather. So it is partly
a measurement of rbf having no spatial index, which nothing until now had
any reason to give it.

What is still owed: the nine-channel widening (`w: f32` → `w: [9]f32`),
which is the only thing standing between this and fitting the marble's
actual materials rather than its geometry alone.

## MARL-12 — nine channels on one geometry, and the √C the campaign had never met (Monday 2026-09-07)

MARL-11 measured one channel: the vein's blend, where a vein's geometry
lives. `rbf.fit` has always fitted NINE — the blend and the eight material
columns it multiplies — and the nine share one centre and one shape. That
sharing is the entire reason a packed set beats a volume texture, and the
campaign could not test it while a kernel carried a single weight.

### The widening, and why it changed no call site

`marl.zig` becomes `pub fn Marl(comptime C: usize) type`, with
`pub const Scalar = Marl(1)` and a facade of aliases — `Model`,
`Hierarchy`, `Kernel`, `PARAMS` — under the plain names every gate and both
runners already used. Weights live at `p[W..W+C]`, INSIDE the kernel, so
the NLMS inner loop reads them from the cache line it just read the shape
from; a runtime channel count would put them in a second array and cost a
miss per kernel per step on a path that touches ninety kernels an event.

Zig forbids a nested container from shadowing a file-level declaration, so
the generic's 109 internal references go through `const Ch = @This()`.
That is the whole of the ugliness and it buys the facade.

`Options` and `PressureOptions` stay OUTSIDE the generic: they are
configuration, and a `Marl(1)` and a `Marl(9)` must be configurable by the
same values. `Region`, `Stats`, `Event`, `RegionSched` moved inside
without complaint, because nothing outside constructs them.

### Inert at C = 1, and two places where it nearly was not

The refactor's gate is not a threshold. Every number the campaign has
recorded must be IDENTICAL, and it is — the whole suite diffed against the
commit before, and G31 (a) still reading the same 975 kernels over the same
1024 probes bit for bit through `rbf.Set.eval`.

How it was checked, because "the suite still passes" is not the claim:
a `git worktree` at the commit before, with `../common` and `../struple`
symlinked beside it (the build resolves its siblings by relative path and
a bare worktree cannot), both suites run to completion, and their printed
gate lines diffed with wall-clock fields normalised away. **81 lines,
character for character identical**; the only difference is G32's own two.

Two things had to be written deliberately for that:

- **The channel magnitude is a MAX, not a Euclidean norm.** At C = 1 that
  is `@abs` exactly. It also happens to be the right semantic and Loam's
  own — R15 merges attention by max on each field separately, because the
  question is whether ANY channel is surprising here, and an average lets
  one badly wrong channel hide behind eight right ones.
- **The geometry's attribution accumulates FROM channel 0**, not from a
  zero: `0 + (−0.0)` is `+0.0`, and a sign of zero there reaches
  `moveCentre`.

### The finding: the geometry's step grows as √C

The first nine-channel run DIVERGED, in exactly MARL-1's shape. The
vein-biased arm birthed 3 666 kernels against the uniform arm's 1 896 and
scored **worse** with them — 0.629 against 0.352. More capacity, less
accuracy, which is the over-capacity-under-evidence signature the campaign
has seen three times.

The cause is structural and had no way of showing up before. The centre and
shape descend on `ew = Σ_c w_c a_c` — one term per channel, because nine
weights pull on one Gaussian and each gets a say in where it goes. For
channel errors that are not perfectly aligned that sum grows as **√C**, so
the rate that is right at one channel is √C too large at C of them. Three
settings, blind arm at nine channels:

| rate_geom | kernels | blend RMS | K(9)/K(1) | D/B |
|---|---|---|---|---|
| 0.2 (the C = 1 rate) | 1896 | 0.21178 | 1.198 | 2.568 |
| 0.2/√9 | 1575 | — | 0.963 | 1.762 |
| 0.2/9 | 1634 | — | 0.974 | 1.878 |

`rate/C` is slightly WORSE than `rate/√C`, which is the evidence that the
growth is √C rather than C — not merely that something smaller was needed.
So it is in the code as `Ch.GEOM_RATE`, a division by exactly 1.0 at C = 1,
and not in a threshold. G32's mutation undoes it and the gate fails, which
is what says the correction is load-bearing rather than decoration.

### What sharing costs, and what it saves

With the correction, at the default rate, two seeds:

| | kernels | blend RMS | floats/kernel |
|---|---|---|---|
| one channel (seed 7) | 1583 | 0.14255 | 10 |
| nine channels (seed 7) | 1578 | 0.14071 | 18 |
| one channel (seed 11) | 1551 | 0.14598 | 10 |
| nine channels (seed 11) | 1561 | 0.13949 | 18 |

- **K(9)/K(1) = 0.997 and 1.006** against a ceiling of 1.15. The geometry
  really is paid for once, and the reason is exact rather than lucky: a
  birth is gated by COVERAGE, which is a max over gaussians and knows
  nothing about channels, so nine channels cannot buy a birth that one
  would not have bought in the same place.
- **The blend's own error is 0.987 and 0.956** of what it is learned alone,
  against a ceiling of 1.25. Learning eight other channels on the same
  geometry makes the blend very slightly BETTER, not worse. The eight are
  extra constraints on where a centre should sit, and on this fixture they
  agree with the blend about that.
- **18 floats a kernel against 90** for nine separate scalar models — a
  fifth of the memory, and it is arithmetic, so G32 asserts it as equality
  of counts rather than as a bound.
- **D/B at nine channels is 1.764**, against MARL-11's 1.987 at one on the
  same fixture. What binds did not move, which is what the ceiling was set
  at 2.0 to check.

The fixture carries TWO materials split across x, and that is load-bearing.
With one material every channel is the blend times a constant, the nine are
exactly collinear, and a shared basis is free by construction — a fixture
that can only agree with the hypothesis is not a fixture.

### Not gated, and why

The nine-channel 2×2 against `rbf.fit` (`marl-run --marble9`) runs its two
rbf arms at 3 666 and 1 896 kernels, which is 22 s of suite for a number
whose shape MARL-11 already established. G32 gates the MARL-against-MARL
sharing pair, which is 0.5 s and is the question the widening was for.
`MARL12_ONLINE_COST` stands in `thresholds.zig` with what the tool run
measured, on MARL-10's precedent.

### Where this leaves the marble

    Nine channels cost no extra kernels, cost the blend nothing, and fit
    in a fifth of the memory nine models would need — provided the
    geometry's step is divided by √C.

Which is the marble's second half done, and the last thing that stood
between the campaign and a real material field.

## MARL-13 — the occlusion cache, and the first NOISY field (Monday 2026-09-07)

Christian named this one on the morning MARL started — "an irradiance or
occlusion cache is exactly what gave me the idea" — and MARL-11's loss
argued it is the regime MARL is actually for. That phase found the binding
constraint is EVIDENCE, and lost to a batch optimiser that re-read its pool
4.7 times. A cache cannot be re-read: each sample is computed once, at
whatever point the renderer asked about, and never seen again. A batch bake
is not a slower option there, it is not an option.

### What is new is the noise

Twelve phases and every field the campaign learned was EXACT. `truthOf`
returns the answer; `rbf.target` returns the answer. Ambient occlusion is
`(1/M)·Σ V(x, ωᵢ)` over M sampled directions — a Binomial(M, p)/M estimate
with σ = √(p(1−p)/M), a half at one ray and a sixteenth at sixty-four.
G33 (a) measures the fixture's estimator against that theory: σ 0.2114
against the binomial's 0.2167 at four rays, 0.0541 against 0.0542 at
sixty-four. §5's "do not confuse noise with complexity" was a design
instruction for twelve phases; this is the phase where there is finally
some noise to not confuse.

### A documentation bug found by needing to march

`CLAUDE.md` said the carrier is "negative inside". **It is not.**
`src/tests.zig`'s own sheet gate samples `Channel.surface` and prints
φ = +2.00 on the sheet's axis, +1.28 four units along it, −1.53 two and a
half ACROSS it and −2.72 nine beyond its width. **φ > 0 is solid.** A
ray-marcher written from the prose finds occlusion in empty space and none
inside a trunk — a bug that renders as a plausible picture. The line is
corrected, with the measurement beside it.

### The law: the learner has a noise floor, and it belongs to the RATE

NLMS with step μ does not converge on noisy data; it hovers, and the
hovering costs μ/(2−μ) of the measurement variance **however much data
arrives**. So

    RMS² = bias² + μ/(2−μ) · V/M

which is linear in 1/M. Fitted from the ends and checked in the middle, as
MARL-10's law was — a line through two points is not a claim, the third
point is. Measured 0.35980 / 0.22497 / 0.17174 at M = 1/4/16; the line
predicts 0.22246 at M = 4 against 0.22497 measured, a ratio of **1.023**
against a ceiling of 1.30. The intercept, the representation error with the
noise extrapolated away, is 0.15110.

**This is the first thing the campaign has met that more data does not
fix**, which is the exact opposite of MARL-11's conclusion and is why it is
gated as a law rather than mentioned as a caveat.

### Noise enters by three doors, and the rate closes one

The fitted slope implies a variance of 0.32 and a binomial's is at most
0.25 — so something else scales with the noise. It is CAPACITY. 9 923
kernels at one ray a sample against 7 656 at sixteen, for the same 60 000
samples: a noisy residual crosses the surprise threshold where a clean one
would not, and **the model births on noise.**

`MARL13_RATE` was pre-registered from μ/(2−μ) at a floor of 2.0 and is
**REFUTED at 1.29**. The diagnosis is the finding:

| door | closed by | worth |
|---|---|---|
| the weights | `rate_w` 0.5 → 0.05 | 1.29× |
| + the geometry | `rate_geom` 0.2 → 0.02 | 1.67×, and 11 176 → 7 113 kernels |
| the topology | nothing built | — |

Closing the geometry door also *shrinks* the population, because a settled
geometry covers better and births less. The third door cannot be closed by
any rate: births are gated on the RAW surprise, which is noisy however
slowly the weights follow it. It needs a noise-aware birth test.

### The headline: refuted, and worth more than parity would have been

`rbf.zig` exists because Christian asked for a packed Gaussian set "instead
of the giant volume texture", so the giant volume texture is who it has to
beat. Equal bytes (memory is what a cache is rationed by) and equal rays
(the rays are the expense being cached), 2 000 000 marched directions each:

| arm | rays | samples | kernels / grid | KiB | RMS | query ns |
|---|---|---|---|---|---|---|
| MARL, online | 16 | 125 000 | 9 334 | 364.6 | 0.12568 | 15 171 |
| dense grid, trilinear | 21 | 91 125 | 45³ | 356.0 | **0.06779** | 36 |
| MARL, on 1 − AO | 16 | 125 000 | 8 057 | 314.7 | 0.08975 | 13 680 |

**REFUTED at 1.854.** And two mechanisms came out of it.

**The background.** A hard cutoff makes a Gaussian decay to EXACTLY zero,
so a constant non-zero background is not free — it has to be held up by
overlapping kernels everywhere it extends. Occlusion is ≈1 across the open
majority of a cube. Learning `1 − AO` instead is one negation and no new
code, and it is worth 1.40× the accuracy for 14% less capacity.

> **Corrected by MARL-16.** This entry originally went on to say that MARL
> "never grew the bias term `rbf.zig` has had since the day it was
> written". That was wrong. `rbf.zig`'s entry is not a learned constant —
> it is the HOST's own material, supplied per hit, showing through where
> the kernels are silent, and the kernels carry a blend that is ZERO in the
> matrix. That is exactly what MARL already does. MARL-16 built the learned
> bias the claim implied and it is worse in both formulations.

**The domain.** A grid pays memory for every cell whether or not anything
is ever asked there. A renderer asks for occlusion at SHADING POINTS, which
are on surfaces — so the volume-uniform comparison is the artificial one.
Restricted to a shell around the geometry:

| arm | kernels / grid | KiB | RMS | query ns |
|---|---|---|---|---|
| MARL, shell, 1 − AO | 3 547 | 138.6 | **0.13222** | 6 651 |
| dense grid, shell probes | 32³ | 128.0 | 0.14503 | 13 |

**0.912.** The packed set beats the giant volume texture — in the regime
`rbf.zig` was written for and not in the one the threshold assumed:

    A learned sparse field beats a dense grid when the interesting set is
    SPARSE IN THE DOMAIN, and loses to it when the field is non-trivial
    everywhere.

The marble's veins were sparse. A volume-filling occlusion field is not. A
shell around geometry is.

### What the numbers do not flatter

A cache lookup is 6 651 ns against a texture fetch's 13. The 27-region
gather is exact and it is not free: at 9 334 kernels over 216 regions,
"local" means about 1 166 kernels evaluated, and MARL's locality advantage
was always an argument about SPARSE occupancy. The first version of this
harness read through `predictAll` — the O(N) reference the gather is
CHECKED against, not a query path — and priced a lookup at 129 µs. That was
mine, and it made the cache look 4 000× worse than a texture at the one
thing a cache exists to be good at.

The gate costs about 25 s of suite, most of it the 4 096-ray reference. It
could be cut fourfold by taking 1 024, at the price of putting the
reference's own noise at 2.6% of the smallest RMS measured instead of 0.7%
— and the headline turns on a ratio of 0.912, so the reference stays where
it is.

### What this indicates next

Two things, both concrete. A **bias term**, which `rbf.zig` has and MARL
does not, and which the campaign never needed because its fields were all
zero-background. And a **noise-aware birth test**, because the third door
is open at every rate and 30% of the population at one ray a sample is
capacity bought on noise.

## MARL-14 — distillation, and the first time the campaign has had a free oracle (Tuesday 2026-09-08)

Christian's idea, in his words: "after the MARL is built, you create
another MARL and sample from the first one and inject into the second one.
If you do it smartly it might be possible to significantly reduce the
number of kernels ... for many applications it doesn't have to be perfect,
an approximation is fine. And if we have the master copy, we can distill to
our hearts content."

It lands on two things MARL-13 had measured hours earlier, which is why it
was worth running rather than reasoning about. **A teacher is NOISELESS**,
so sampling it closes all three of MARL-13's doors at once with no new
mechanism — including the topology door, which no learning rate can close.
And **a teacher is UNLIMITED**, so the student is the first learner in this
campaign that is not evidence-starved, which was MARL-11's binding
constraint.

It must not be confused with MARL-8. That phase transplanted a retiring
region's KERNELS and failed, concluding geometry is "cheap to acquire
locally and worthless imported". A student imports no geometry: it starts
empty and discovers its own topology from a cheap oracle. The two findings
do not touch.

**The student is scored against the TRUE field throughout, never against
its teacher** — scored against the teacher it would be measuring how well
it copies a copy, a number that improves as both get worse.

### All four pre-registered numbers held

Teacher: MARL-13's shell arm — 3 513 kernels, RMS 0.13248, 137.2 KiB,
6 573 ns a lookup. Students get 200 000 samples of it.

| θ | kernels | RMS | K/K_t | RMS/RMS_t |
|---|---|---|---|---|
| 0.020 (the teacher's) | 3 292 | 0.14016 | 0.937 | 1.058 |
| 0.050 | 3 063 | 0.13999 | 0.872 | 1.057 |
| 0.100 | 2 512 | 0.14456 | 0.715 | 1.091 |
| 0.200 | 1 612 | 0.15109 | **0.459** | **1.141** |

**(1) FREE, at 0.937** against a ceiling of 0.95. Copying at matched
options sheds 6% of the population for 5.8% of the accuracy — and that is
the capacity MARL-13 measured as bought on noise, which a clean teacher
cannot sell.

**(2) THE TRADE, at 1.141** against a ceiling of 1.5. **Halving the
population costs fourteen per cent of the accuracy.** With a noisy field
raising θ is dangerous, because a residual above it might be a sampling
wobble — MARL-13's third door. With an exact teacher every residual above θ
is real structure, so θ stops being a risk and becomes a clean accuracy
dial. That is "it doesn't have to be perfect" turned into a mechanism.

**(3) THE COARSE BASIS, at 4.32×** against a floor of 3.0. `regions` 6 → 3
doubles every kernel, and a shell is nearly two-dimensional so the saving
goes as the square: **814 kernels at 31.8 KiB against the teacher's 3 513
at 137.2**, for RMS 0.16309 against 0.13248. A quarter of the memory for a
quarter more error.

**(4) GENERATION LOSS DOES NOT COMPOUND, at 0.98** against a ceiling of
1.0. A→B costs 1.058 and B→C costs 1.036 — the second copy is CHEAPER than
the first. The argument was structural and it held: B is a sum of
anisotropic gaussians, which is exactly the student's hypothesis class,
and the truth is not. The first copy pays a representation cost; the second
is fitting something it can represent perfectly given enough kernels. So
"distill to our hearts content" is sound — the sequence converges rather
than decaying.

### The part that was not pre-registered, and is the best of it

MARL-13 left the packed set beating a dense grid on the shell by 0.912 at
roughly equal bytes. The question distillation actually raises is what
happens when the bytes stop being equal because one side got four times
smaller:

| | RMS | KiB |
|---|---|---|
| distilled student, regions 3 | **0.16309** | 31.8 |
| dense grid at the same size (20³) | 0.18580 | 31.3 |

**0.878** — better than the teacher's own 0.912. **The learned field's
advantage over the volume texture WIDENS as the memory budget shrinks**,
because a grid's error is set by its cell size and halving memory costs it
a cube root of resolution, while a packed set simply places its kernels
where the field actually varies.

Which is the sentence this idea bought:

    Build once at full fidelity from the expensive, noisy source; distil
    to whatever the budget allows. The copy is cheaper to make than the
    original, it can be made as approximate as the application permits,
    and copying it again costs less than copying it once.

### What it costs, honestly

Sampling a teacher is one 27-region gather — 6 573 ns here — against an AO
estimate's 320 marched fetches. Cheaper, but only about fivefold, and not
the orders of magnitude "free oracle" suggests: the gather is expensive
precisely when the teacher is large, which is when you most want to distil
it. For a proxy-mesh or smoothing use that hardly matters, because the
teacher is built once offline and the student is the shipped asset.

G34 costs about 25 s of suite. With G31's 14 and G33's 25 the suite is
approaching four minutes, and the next phase that wants a gate this size
should be asked to justify it rather than assumed to be entitled to it.

## MARL-15 — quantization, and a sensitivity analysis that was wrong by fivefold (Tuesday 2026-09-08)

Christian asked whether quantization was already in the numbers. **It was
not.** Every byte count this campaign had quoted was `kernels × PARAMS × 4`
with the grid baseline in f32 too — fair, and uncompressed. MARL-14's
headline was a claim about a representation nobody would ship, and the two
sides do not quantize alike: a grid of values in [0, 1] goes to eight bits
for essentially nothing, where an RBF set's ten floats have wildly
different sensitivities and the weight sits in a sum where neighbours
cancel. So this phase exists to qualify a claim, not to add one.

### What is quantized, and what deliberately is not

The `rbf.Set` — the thing that actually ships, and bit-identical to the
model by G31 (a) at a power-of-two extent — and not a live `marl.Model`. A
model's kernels are OWNED by regions, so rounding a centre could move it
across a face or grow its reach past the region's bound; quantizing in
place would silently corrupt the gather and charge it to the quantizer.

No bit-packed container is built. Quantization is applied by ROUNDING the
parameters onto the representable grid and scoring normally, with the byte
count computed from the allocation. A packer would change no number here.

The log-diagonal is quantized and not the diagonal, because that is the
parameterisation the model descends in and the one whose error is
RELATIVE — a width is a scale, and a scale quantized linearly spends all
its precision on the widest kernels.

### The sweep, on MARL-14's shipped 814-kernel student

| allocation (μ/logd/off/w) | bits | KiB | RMS | vs f32 |
|---|---|---|---|---|
| 16 / 10 / 10 / 12 (pre-registered) | 120 | 12.0 | 0.16307 | 1.000 |
| 12 / 8 / 8 / 10 | 94 | 9.4 | 0.16315 | 1.000 |
| 10 / 6 / 6 / 8 | 74 | 7.4 | 0.16379 | 1.004 |
| **8 / 6 / 6 / 8** | **68** | **6.8** | 0.16474 | **1.010** |
| 6 / 5 / 5 / 6 | 54 | 5.4 | 0.17715 | 1.086 |
| 4 / 4 / 4 / 4 (mutation) | 40 | 4.0 | 0.26227 | 1.608 |

`MARL15_BITS` HELD at 1.000 — and the analysis behind it was **pessimistic
by about fivefold**. A kernel ships in **8.5 bytes**, not the fifteen
predicted: a 4.7× saving for one per cent of the accuracy. The knee is
sharp, which is what makes the sweep a measurement rather than a shape: 54
bits breaks the ceiling and 40 fails outright.

### Why the prediction was wrong, and it is not the obvious answer

The first explanation I wrote was that the weights must be small — a
heavily overlapping basis sharing the field between its kernels, so each
carries a small share and rounds cheaply. **That is wrong, and the gate
prints the number that disproves it**: the weights span −0.4982 to 1.3759,
so |w| is slightly ABOVE the 1.0 the prediction assumed and makes the
analysis worse rather than better.

The real reason is that **peak sensitivity and peak overlap do not
coincide.** The prediction multiplied the derivative's maximum — 0.6065, at
r = 1 exactly — by √(3n) for n = 30 overlapping kernels. But a point
sitting at r = 1 of one kernel sits far out in the tails of most of the
others, where both the value and the derivative are near zero. The kernels
that are SENSITIVE there are a handful, not thirty. Compounding a worst
case over an assumed overlap count multiplies two things that never happen
together, and measured, that product is about fivefold.

Worth keeping as a method note: a per-element worst-case sensitivity
analysis over an overlapping basis is not conservative, it is wrong, and
the direction of the error is predictable.

### Which field, decomposed — and Christian's adaptive-refinement guess

He asked whether the forgiveness was down to the adaptive refinement. It
is, in part, and the ablation says exactly where. Each field starved to
eight bits alone with the other three left in f32:

| field | span | 8-bit step | excess RMS |
|---|---|---|---|
| centre | 32.0 (the whole extent) | 0.125 | **0.01872** |
| log-width | **1.0361** | 0.0040 | 0.00412 |
| off-diagonal | **1.1304** | 0.0044 | 0.00312 |
| weight | 1.8741 | 0.0073 | **0.00000** |

Three things fall out.

**The sensitivity RANKING was right and only the magnitude was wrong.** The
centre dominates, as predicted; it just costs 0.019 at eight bits rather
than the 0.110 derived.

**The adaptation shows up in the SPANS, and that is Christian's point.**
The log-width span is 1.04 NATS where the prediction assumed four — a
quarter, and a straight factor of four on that field's error. The reason is
structural: an adaptive learner refines by PLACING MORE KERNELS, not by
making them wildly different sizes, so the population stays tightly
clustered in scale and never needs the dynamic range the clamp would allow.
A fixed-count basis forced to cover the same detail range would have to
spread its widths and would pay for it in bits. The off-diagonals are
narrow for the same reason.

**The weight, the field most feared, costs exactly nothing at eight bits.**
The cancellation risk the prediction worried about never materialised: the
span is narrow, and δw·g is attenuated by g < 1 before it reaches the
field.

The centre is the outlier, and its cost is entirely a SPAN choice rather
than a sensitivity: it is quantized over the whole extent, giving a step of
0.066σ.

### Region-relative centres, which is where that pointed

A kernel's centre is inside its owning region BY DEFINITION — that is what
ownership means in this model, and the clamp keeps it there. So the span a
centre needs is not the cube but `extent/regions`, which is log2(regions)
bits an axis free at the same error. And `marble.setOf` already writes
kernels in `predictAll`'s order — region by region, then each region's own
list — so the grouping a decoder needs is already in the file; all that has
to be stored is a u16 count per region, charged in full at 27 × 2 = 54
bytes.

Pre-registered in `tools/marl15_predict.py`'s second section, written after
the absolute sweep ran and before this one did.

**MARL15_RELATIVE HELD at 6.16×**, twice the 3.0 the geometry predicts:
excess 0.01872 absolute against 0.00304 relative, eight bits with the other
three fields in f32. Read the numerator rather than the ratio, though — the
relative excess is a difference of 0.00003 in the fourth decimal of an RMS,
at the edge of what 512 probes resolve. The safe reading is that the centre
STOPS BEING THE EXPENSIVE FIELD, not that the saving is exactly six-fold.

**MARL15_RBITS HELD at 0.995 — no measurable cost at all** — where the same
54-bit budget with absolute centres cost 8.6%. That is not "better than
f32"; it is indistinguishable from it, and half a per cent is not a claim
worth making.

So the production encoding is **54 bits, 6.75 bytes, a kernel**: 6 bits an
axis of region-relative centre, 5 of log-diagonal, 5 of off-diagonal, 6 of
weight. **5.93× on f32**, 5.5 KiB for the 814-kernel model.

### The headline, re-priced, and the grid's granularity

A cubic grid cannot land on a byte budget — at 5.5 KiB it fits 17³ = 4.8
and the next size up is 18³ = 5.7. Reporting only the one that fits would
flatter MARL by 13% of the memory, so both are measured and the gate
asserts against the larger, the grid given MORE than its share:

| | MARL over grid |
|---|---|
| f32 (MARL-14) | 0.878 |
| 8-bit absolute centres | 0.859 |
| 54-bit region-relative, grid under budget (17³) | 0.769 |
| **54-bit region-relative, grid over budget (18³)** | **0.804** ← gated |

MARL 0.16230 at 5.5 KiB against 0.20184 at 5.7. Every step of compression
has moved the comparison FURTHER in the packed set's favour, which is the
opposite of what the derivation expected and is worth stating plainly: an
adaptive basis compresses better than a uniform one, because adaptation
narrows the dynamic range every field has to carry.

### Recorded, not built: QAT belongs in the transfer step

Christian's, and it is the right place for it: quantization-aware training
should ride the DISTILLATION transfer rather than the original fit. A
student is already re-fitting from scratch against a free, noiseless,
unlimited oracle (MARL-14), so snapping to the quantization grid inside its
existing `clamp` projection costs nothing extra — the model's own rule is
"nothing enters the model unprojected", and a quantization grid is just a
finer projection.

There is no headroom for it at 54 bits, where the cost is already
unmeasurable. Where it would earn its place is below: 40 bits absolute
measured 1.608, and if QAT made that budget viable it would be another 1.35×
on top of the 5.93×. The caution is that MARL's kernels MOVE, so the grid a
centre snaps to keeps shifting under it, and a kernel wanting to move less
than half a step would never move at all.



### The headline: quantization IMPROVES MARL's position

| | RMS | KiB |
|---|---|---|
| MARL, 68 bits a kernel | **0.16474** | 6.8 |
| dense grid, 19³ at 8 bits | 0.19189 | 6.7 |

**0.859**, where MARL-14's f32 number on the same fixture was 0.878. The
derivation predicted 1.06 on the assumption that a grid compresses 4× and a
kernel only 2.7×. A kernel compresses **4.7×**, so the packed set gains
slightly MORE from compression than the texture does — and the f32
comparison was, if anything, unfair to it.

So the sentence MARL-14 bought survives compression, and gets a number
attached to it:

    A distilled, quantized MARL of 814 kernels is 6.8 KiB and beats an
    eight-bit 19³ volume texture of the same size by 14% on error — on a
    field queried where a renderer actually queries it.

### What is still owed

The weights were quantized against a single global span. MARL-1's divergent
regime reached mean |w| of 13–17, and a set with that spread would waste
most of its levels on outliers; per-region spans, or a non-uniform
allocation, are the obvious next thing and are not built. Nothing here
tested a set in that condition.

## MARL-16 — the bias term, refuted twice, and a claim of mine corrected (Tuesday 2026-09-08)

MARL-13 left "a bias term" as the indicated next thing, on the strength of
a sentence I wrote in its ledger entry: that `rbf.zig` has had one since
the day it was written and MARL never grew it. **That sentence was wrong**,
and building the thing it implied is how it got found.

### Both formulations, and the better estimator is the worse model

The field is MARL-13's LOSING configuration — volume-uniform occlusion,
learned directly rather than inverted — because that is where the
background problem lives.

| | kernels | RMS | b after 125 000 | vs no bias |
|---|---|---|---|---|
| no bias | 9 307 | 0.11872 | — | — |
| bias from the RESIDUAL | 10 100 | 0.15459 | 0.1057 | 1.302× |
| bias from the TARGET | 12 493 | **0.67423** | 0.7211 | **5.679×** |

The residual form is the one anyone reaches for first, and it does not even
converge: the kernels descend at `rate_w` per event while a running mean's
step is 1/n, so they absorb the background long before the bias can and
then `E[y − K] ≈ 0` strands it near zero. Fixing that — taking the running
mean of the TARGET, which converges whatever the kernels do — lands b on
0.7211, the field's actual mean, and makes the model **five times worse.**

**The better estimator being the worse model is what says the fault is not
in the estimator.**

### The mechanism, measured rather than argued

A Gaussian basis with a hard cutoff cannot cheaply represent a plateau of
ANY value. **Zero is not special because it is zero. It is special because
it is what an empty model already predicts** — so a target that is zero
over a large region costs literally nothing, and that is the only sense in
which the campaign's earlier fields had a "free background".

A bias moves the free value from 0 to b. It helps where y ≈ b and it hurts
everywhere y ≈ 0, which now has to be held DOWN by kernels that previously
did not need to exist. On this field:

    0.123 of the probes sit within θ of ZERO   (free without a bias)
    0.049 sit within θ of the learned bias     (free with one)

A losing trade by 2.5×, and the gate asserts that inequality rather than
the refuted thresholds — so if it ever flips on some other field, the bias
should be tried there and is expected to win.

### What MARL-13's inversion actually bought

Not a "zero background" in any abstract sense. Two concrete things: the
zero mass stayed free, AND the amplitude the kernels had to carry fell from
mean(AO) ≈ 0.72 to mean(1 − AO) ≈ 0.28. A bias delivers the second and
destroys the first.

### The trade that DID hold, and it is worth keeping

`CUTOFF` makes a learning event structurally unable to disturb a distant
region, and G17 (c)/(d) check it bitwise. A global scalar is not local at
all. Learned as a running mean its step is 1/n, so the disturbance decays:

    no bias    one late event moved distant probes by EXACTLY 0.00
    with bias  2.26e-6 on a residual of 1.04 after 125 001 exemplars
               → disturbance × n / |e| = 0.272 against a ceiling of 1.5

So the campaign CAN buy a background term, at the price of asymptotic
rather than exact locality, and the price is now priced. It is simply not
worth paying on a field with a large zero mass. An EWMA (`rate_bias > 0`)
would give up both — its step never decays — and is there for a field whose
background drifts, knowingly.

### Kept, not deleted

`BiasRule` stays in `Options`, defaulting `.off`, with both formulations
and the reason each fails written into the enum. The residual form
especially: it is what anyone would reach for, and the ledger should say
why it is wrong rather than leave the next person to find out.

Every number from G17 to G35 is untouched — verified on G17 and G31 (a)
rather than by a suite run, because the suite is four minutes and Christian
asked for it not to be run on every edit. G17 (d) reads 2 468 kernels and
G17 (e) 0.04823 at gain 2.99, both identical to the pre-change baseline,
and G31 (a) is still bit-identical at 975 kernels.

## MARL-17 — a real Quake 3 level, and the sparsity rule confirmed (Tuesday 2026-09-08)

MARL-13 ended with a rule: **a learned sparse field beats a dense grid when
the interesting set is SPARSE IN THE DOMAIN, and loses when the field is
non-trivial everywhere.** The grove of spheres it was measured on has open
sky and crevices but no rooms, no doorways and no scale separation.
Christian suggested `oa_spirit3` — an OpenArena deathmatch level — which
has all three.

### Getting it in

`tools/q3_volume.py` reads the BSP through `~/dev/tessera`'s loader
(Christian's, already mirrored field-for-field against
`~/dev/importers/src/q3bsp.zig`) rather than writing a third parser, and
rasterises the world's SOLID BRUSHES to signed distance. Brushes and not
the render faces: a brush is a convex intersection of half-spaces, so its
signed distance is exactly `−maxᵢ(nᵢ·p − dᵢ)` — positive inside, which is
the convention MARL-13 measured the carrier to have — where the faces are
an unclosed triangle soup with sky and decals in it.

Two things had to be got right.

**The clamp is ±3 CELLS, not ±3 units.** The carrier's is; an absolute ±3
is sub-voxel on a level where a voxel is twenty-odd Q3 units and there
would be no band at all.

**Conservative rasterisation, or the level leaks.** Q3 walls are eight to
sixteen units and a voxel at 160³ is 28.8, so a centre-sampled
rasterisation drops most of them: measured, 2.8% of the cube solid, and
rays walking straight through walls. Growing every brush by half a cell
puts it at 3.9% at 160³ and 3.6% at 224³ — converging, which is what says
the growth is sealing the level rather than inflating it. The cost is that
the thinnest walls end up about a voxel thick, and that is stated rather
than hidden: **a level the grid cannot seal has no occlusion to study.**

    oa_spirit3: 1 568 solid brushes, bounds 2176 × 4608 × 1600 Q3 units,
    a cube of 4608 at 160³ = 28.8 units a voxel, 3.9% of it solid.

### The result, with an anchor this time

Every RMS in MARL-13 through MARL-16 was quoted without saying what
predicting a CONSTANT would score, which is the only thing that gives an
RMS a scale. Fixed here, and it changes how one of the numbers reads.

    the query set: mean AO 0.2269, sd 0.2645
    → predicting the mean everywhere scores 0.26448

| arm | kernels / grid | KiB | RMS | vs a constant | query ns |
|---|---|---|---|---|---|
| MARL, online | 1 614 | 63.0 | **0.12011** | 2.20× better | 12 607 |
| dense grid, trilinear | 25³ | 61.0 | 0.20397 | 1.30× better | 9 |

**MARL/grid 0.589** — a far bigger margin than the grove's 0.804, and for
exactly the reason the rule predicts. The level is 3.9% solid and the
queries sit within two voxels of a surface, so the interesting set is a
thin shell inside a mostly-empty cube. A 25³ grid over 4608 units has
184-unit cells and cannot resolve anything; MARL puts 1 614 kernels where
the shading points are.

### The pipeline, end to end

| stage | kernels | KiB | RMS | vs a constant |
|---|---|---|---|---|
| the master, f32 | 1 614 | 63.0 | 0.12011 | 2.20× |
| distilled, regions 3 (MARL-14) | 340 | 13.3 | 0.14649 | 1.81× |
| …and quantized, 54 bits (MARL-15) | 340 | **2.3** | 0.15807 | **1.67×** |
| dense grid at the same bytes | 8³ | 2.0 | 0.37835 | **1.43× WORSE** |

**27.1× off the master for 1.32× the error**, and the shipped model is
0.418 of the grid's error at the same size.

The line worth pausing on is the last one: at two kilobytes an 8³ grid is
**worse than predicting the mean everywhere**. Trilinear interpolation over
184-unit cells does not approximate the field, it adds error to a constant.
The learned field at the same size is still doing real work.

### What the numbers do not say

**Nothing here is a good fit in absolute terms.** The master is 2.20× a
constant and the shipped model 1.67×. Occlusion near surfaces in a level is
driven by geometry at the scale of tens of units and the occluder itself is
quantised to 28.8-unit voxels, so some of that ceiling is the fixture's and
not the learner's. A finer volume would raise every arm and is not run here
because a 224³ grid is 45 MB and the AO marcher's random access into it
dominates the wall clock.

**And a dense grid is the baseline `rbf.zig` was written against, not the
best a renderer could do.** Nobody stores a dense grid over a level's whole
bounding box; they cluster probes near surfaces. That is a sparse structure,
it is a harder opponent, and it is not what was measured. What the 0.418
says is that a learned field beats the DENSE representation decisively on
real geometry — which is the claim `rbf.zig` exists to make and the one this
campaign set out to test.

### Not gated, and why

The fixture is a 16 MB artefact generated from a copyrighted game asset that
is not in this repo, so a gate cannot depend on it. The MECHANISM is already
gated on the grove (G33 d, G34, G35), and this is its confirmation on
geometry nobody designed for it. Reproduce with:

    python3 tools/q3_volume.py --res 160 --out out/oa_spirit3.vol
    zig build marl -Doptimize=ReleaseFast -- --q3 out/oa_spirit3.vol --exemplars 250000

`src/marl.zig` is untouched by this phase; the additions are
`cache.readVolume`, `cache.scaledAo` and a `marl-run --q3` mode.

## MARL-18 — consolidation, and the control that refuted the phase twice (Tuesday 2026-09-08)

Christian's plan for the day (`MARL_Tomorrow_Action_Plan.md`) proposes
that distillation is not a deployment step but a LEARNING step: distil,
put the student in the master's place, resume ordinary learning, repeat.
Wake and sleep. "Learn, accumulate interference, consolidate, resume
learning from a cleaner state."

### The premise it rests on was a misreading, and saying so first is the phase

The plan opens: "the distilled student has been observed to achieve
significantly lower error than the teacher, not merely fewer kernels."
**MARL-14 measured the opposite at every point of its sweep** — 1.058 at
matched options, rising to 1.141 at the coarsest, against a teacher's
0.13248. The number that reads like the claim is **0.878**, and it is a
different ratio entirely: the student against a DENSE GRID OF THE SAME
BYTE COUNT. The student beat the *baseline* by more than the teacher did,
because shrinking a memory budget costs a grid a cube root of resolution
and costs a placed basis almost nothing. A statement about the opponent,
not about the teacher.

The idea survives the correction and gets sharper for it, because
**MARL-14 distilled a model and STOPPED.** It never resumed learning.
"The student is worse at the instant of the copy" and "the student is a
worse place to learn from" are different claims, and only the first had
ever been run.

### G37 (a) — a student cannot beat its teacher, EXCEPT when the teacher is noise-limited

| rays | teacher | best student | ratio | |
|---|---|---|---|---|
| 16 | 3 387 k, 0.13222 | 3 228 k, 0.13789 | **1.043** | HELD (≥ 1.0) |
| 1 | 5 520 k, 0.23875 | 3 456 k, 0.22913 | **0.960** | **REFUTED** |

**Christian is right, and only in the noisy regime.** At one ray a sample
every student in the sweep beats its teacher — matched 0.962, θ = 0.1
0.960, and a basis with a third of the kernels (1 712 against 5 520) still
0.971.

The mechanism is not "discarding optimisation baggage". A student fits its
teacher's OUTPUT, noise and all, and has no access to anything the teacher
got wrong — so the only way it can come out ahead is by FAILING to
reproduce part of the teacher and being better off for the failure. That
is the low-pass argument, and the sweep is its signature: a shallow U
(0.962, 0.960, 0.971) with a minimum at intermediate capacity, which is a
bias-variance curve and not a monotone saving. **A copy is a filter, and
it is worth something exactly when the original is carrying noise.**

**THE DIFF was refuted the OTHER WAY, at 1.606.** The plan asked what edits
a consolidation performs, and the unit that makes it measurable is not
kernel identity — a student shares none — it is OVERLAP: how many kernels
read above `coverage` at a query point, over the population ratio, so that
a uniform thinning scores exactly 1. Christian's picture is A + B + C + D
→ X + Y and would score BELOW one. It scored 1.606: at one ray the student
sheds a THIRD of the population while RAISING the crowding per kernel.
**A consolidation does not untangle, it CONCENTRATES** — the ninth item on
his list rather than the eighth. Low-contribution kernels are retired and
the survivors sit where the queries are.

### G37 (b) — the staircase is real, and it tracks the noise

Two arms on ONE reality stream in one order, the same points and the same
estimates and the same total, differing only in whether the model was
rebuilt from itself three times along the way. The control runs the
identical code path at `sleeps = 0`.

| rays | straight | consolidated | RMS | kernels |
|---|---|---|---|---|
| 16 | 0.13222, 3 387 | 0.13368, 3 225 | 1.011 (HELD) | 0.952 |
| 1 | 0.23875, 5 520 | **0.21430, 3 671** | **0.898 (REFUTED)** | **0.665** |

**MARL18_GRADIENT HELD at 1.432**, and it is the number that makes the
mechanism a claim rather than a coincidence: the population saving is
half again as large in the noisy regime as in the clean one. A re-fit that
merely found a leaner solution would save the same either way.

The one-ray trace is the staircase Christian drew, and the sleeps are
doing the ratcheting:

    wake 1  24 000   3 606   0.28004
    SLEEP 1          3 783   0.26961     ← the sleep IMPROVED it
    wake 2  48 000   4 011   0.22455
    SLEEP 2          3 546   0.22828
    wake 3  72 000   3 758   0.23232     ← learning went BACKWARDS: the hover
    SLEEP 3          3 465   0.22565     ← and the sleep took it back
    wake 4  96 000   3 671   0.21430

At sixteen rays every sleep COSTS a little (0.16498 → 0.16533, 0.14158 →
0.14363, 0.13450 → 0.14068) — MARL-14's generation loss with nothing to
filter. `MARL18_POPULATION` is refuted there by two thousandths (0.952
against a ceiling of 0.95) and comfortably held at one ray.

### …and then the control refuted the phase

The finding above is "consolidation is worth 10% of the accuracy at one
ray". Two much cheaper things could produce that number, and until they
were ruled out it read "some variance reduction helps", which nobody needs
a second model to learn.

    against the consolidated arm's 0.21430 at 3 671 kernels in 11.6 s —
    4× the reality   0.21976 at 8 135 kernels,  8.9 s
    rate/10          0.18474 at 3 142 kernels,  1.5 s

**C1 holds and is instructive.** Four times the reality gets most of the
way there and pays for it in TOPOLOGY: 2.2× the population. MARL-13's
third door, open at every rate, is what makes "more samples" the wrong
answer even when it nearly works.

**C2 REFUTES the phase.** Dropping `rate_w` and `rate_geom` tenfold beats
consolidation on accuracy, on memory and on wall clock at once, at an
eighth of the cost. The control was written expecting a rate to close the
weight door and leave the topology one open, because MARL-13 says "no rate
closes that" — but MARL-13's sentence was about `rate_w`, and this moves
`rate_geom` too. A kernel that does not chase a noise realisation
geometrically stays where it can cover, so fewer births are needed. That
is MARL-13 (c)'s own 11 176 → 7 113 showing up again in a place nobody
looked for it.

And it exposed a methodological error. The arms ran at G33 (d)'s
configuration, which pins `rate_geom` to the DEFAULT deliberately, so that
its headline is not configured from its own result. Right for G33 and
**wrong here**: MARL-18 asks whether consolidation beats LEARNING, and
that has to mean the best learning this repo already knows about.

### G37 (c) — with the rates already right, does a sleep still buy anything?

`MARL18_RATE_FIRST` was frozen in `thresholds.zig` and
`tools/marl18_predict.py` before this ran, and it gated a decision: a
refutation means consolidation does something no rate can, and the plan's
§4 local micro-distillation is worth building.

**REFUTED at 0.940.** At one ray with `rate_w` 0.05 and `rate_geom` 0.02,
straight learning reaches 0.18954 with 2 984 kernels and three sleeps
reach **0.17810 with 2 867** — six per cent of the accuracy and four of
the memory, on top of the cheap fix.

So the prediction was wrong and the direction of the error is the finding:
the win SHRANK from 0.898 to 0.940 when the baseline was corrected, which
is the variance story holding, and it did not go to zero. **A sleep is
worth exactly as much as there is variance to remove** — 1.011× on a clean
teacher, 0.940× at the right rates, 0.898× at the wrong ones — and a rate
is the upstream way to not carry it, not a substitute for the downstream
one.

Which is the sentence the phase bought:

    Turn the rates down before you consolidate. It is better and eight
    times cheaper. Then consolidate anyway, because it still pays.

**And at the right rates a sleep no longer RESTRUCTURES anything.** Overlap
2.30 → 2.22, mean σ 0.0278 → 0.0284, population 0.961× — all within a few
per cent. The 1.606 concentration of G37 (a) belonged to the handicapped
regime, where a third of the population was bought on noise and there was
something to retire. With the rates right there is almost nothing to
retire, and what a sleep performs is a **RE-FIT**: the same population,
better placed and better weighted, because the last fit it saw was against
a noiseless field. Christian's edit vocabulary, on this fixture, is
"movement" and "weight adjustment" — not merging, and not splitting.

### What it costs, honestly

The sleeps cost **5.6× the wall clock of the learning they improved** (8.8 s
asleep against 1.6 s awake). That number is the pessimistic end of its
range and the reason is worth stating: one ray a sample is the CHEAPEST
reality that exists, about twenty marched fetches against the ~320 G33
measured for a real estimate, so this fixture's reality is roughly sixteen
times cheaper than a renderer's. Scale accordingly before reading anything
into it for the plan's §10 per-frame scheduling.

G37 is **79 s of suite** — (a) 29, (b) 44, (c) 19 — which is more than any
gate the campaign has added and more than MARL-14's entry said the next
one should assume it was entitled to. It is spent on three refutations and
two controls, and if it needs trimming the first thing to go is (b)'s
16-ray pair, whose only surviving job is the gradient.

### What is NOT tested, and it is the thing MARL-9 would ask about

One fixture, one field, STATIONARY. MARL-9's lesson stands: "a campaign
that has only tested one kind of world cannot tell what its numbers are
counting." Every result here is about a model carrying MEASUREMENT noise.
The tangle Christian's plan describes — "path-dependent optimisation
history, redundant kernels, awkward overlaps" — is what MARL-7 measured on
a DRIFTING world, where capacity grows about a thousand kernels a move
while accuracy stays flat and unrefinement moves it by 1%.

**Distillation is a plausible candidate for the erosion mechanism MARL-7
could not find**, and for a reason MARL-7's instrument could not see: it
concluded "kernel death has nothing to target" because silencing old
capacity costs 1.4–1.6× the RMS, so every kernel is individually
load-bearing. Four overlapping kernels whose sum is smooth are all
individually load-bearing and collectively replaceable. **A consolidation
never chooses a victim — it declines to rebuild one**, which changes the
unit of removal from the kernel to the local function. That is the next
experiment, and it is a bigger one than today's.

### Recorded, not built

The plan's §4 (local micro-distillation) is greenlit by G37 (c)'s own rule,
with one qualification the phase adds: at the right rates a sleep is a
RE-FIT rather than a restructure, so the local version is a local re-fit,
and what makes that plausible is exact locality — a region's kernels can be
re-derived from the model's own field without disturbing anything outside
the cutoff, which G17 (c)/(d) already check bitwise. §7–§12 (stacked
dynamic layers, object frames, particles, per-frame budgets) are downstream
of a drifting-world result that does not exist yet.

    zig build test -Dtest-filter="G37"        # 79 s; (a) the premise, (b) the staircase and its controls, (c) the corrected fixture
    python3 tools/marl18_predict.py           # where the numbers came from, extension included

`src/marl.zig` is untouched by this phase. The additions are
`cache.teachInto` (a split out of `teach`, so a run can be continued),
`cache.distilEpoch` (a dream stream that differs per sleep),
`cache.wakeSleep`, `cache.overlapOf` and `cache.meanWidth`. G34, G35 and
G36 were re-run against the refactor and read identically, line for line.

## MARL-19 — the milk round, and the second currency that turned out not to exist (Tuesday 2026-09-08)

Christian's clarification of the consolidation idea, in his words:

> "You are told to deliver the milk on Mondays so you buy a kernel. Then
>  you are told to deliver the milk on Wednesday as well .. surprise, and
>  you buy another kernel. Then you are told to deliver milk on Tuesday and
>  Thursday and Friday as well, but you already have two kernels refining
>  the parent Milk delivery schedule kernel. Now you have three, potentially
>  four kernels whose sum is.. Deliver milk Monday to Friday. The distilled
>  student samples and never sees all the patches.. it sees a continuous
>  function Saturday and Sunday, no milk, Monday through Friday, deliver
>  the milk."

That is a different mechanism from the one MARL-18 measured, and MARL-18's
fixture could not have seen it. MARL-18 concluded "a sleep is worth exactly
as much as there is VARIANCE to remove" — and one stationary field learned
from a noisy estimator leaves noise as the only thing a teacher can carry
that a student would not rebuild. The milk round names a second currency:
**HISTORY**.

So `src/milk.zig`'s target is ANALYTIC AND EXACT. Seven days along x, a
fixed smooth amplitude in (y, z) so the field is not degenerate off the
axis, and the schedule revealed in three stages. If a sleep collapses the
population *here*, MARL-18's sentence is incomplete.

### G38 (a) — the premium is not there, and the reason is two prior phases

    a constant predictor scores 0.26922

| arm | kernels | RMS |
|---|---|---|
| A  incremental, 3 stages | 6 094 | 0.05791 |
| B  scratch, same TOTAL evidence | 6 709 | 0.04351 |
| B3 scratch, same FINAL-schedule evidence | 5 526 | 0.07418 |
| C  A, then one sleep | 7 110 | 0.06826 |

**`MARL19_HISTORY` REFUTED at 1.103**, and **`MARL19_REFUND` at −1.789** —
the sleep RAISED the population.

At equal total evidence the incremental arm carries FEWER kernels than the
from-scratch one and is behind on accuracy. It is not paying a premium; it
is further back, having spent two thirds of its budget on schedules with
less structure in them. **Nothing it learned became wrong.** Monday is
delivered at every stage, so the reveal is NESTED and MARL-9's law applies
in its cheap direction: capacity is paid per THING LEARNED, and everything
learned is still true. And MARL-16 covers the only obsolete structure there
was — the Tuesday hole sat at ZERO, which is exactly what an empty model
already predicts, **so holding the hole down never cost a kernel and there
was nothing there to cancel.**

**`MARL19_COPY` HELD at 1.179**, and it is the number that separates the
two currencies: a copy of an exactly noiseless teacher is a pure loss,
which says MARL-18's 0.960 belonged to the teacher's noise and not to the
act of copying.

### G38 (b) — "smoother ground" holds, and the kernel column says why not to celebrate

| arm, + one more period of Mon–Fri | kernels | RMS | vs A |
|---|---|---|---|
| A  straight through | 6 620 | 0.04576 | 1.000 |
| D  one sleep, then learn | 7 357 | 0.04465 | **0.976** |
| E  a sleep after every stage | 7 412 | 0.04394 | **0.960** |

**`MARL19_GROUND` HELD.** Consolidating and then learning does beat
learning straight through — on a noiseless field, which is where MARL-18
could not have told the currencies apart. But the slept arms end with
**eleven per cent more capacity**, and this campaign has found four times
over that RMS tracks capacity. A 2–4% win carrying an 11% larger population
is not a clean result.

### G38 (c) — it is not addition that costs; and contradiction barely costs either

Two paths, same three stages, same 120 000 exemplars, same destination,
differing only in whether the path contradicted itself — and the dream
PINNED to the teacher's own evidence, which is the confound (a) tripped
over:

    nested         {Mon}          {Mon,Wed}      {Mon..Fri}
    contradictory  {Mon,Tue,Wed}  {Wed,Thu,Fri}  {Mon..Fri}

| path | kernels | RMS |
|---|---|---|
| nested | 6 094 | 0.05791 |
| … slept | 6 976 | 0.07168 |
| contradictory | 6 654 | 0.05115 |
| … slept | 6 929 | 0.06478 |

**`MARL19_CONTRADICT` REFUTED at 1.092.** A round that stops delivering
Monday and Tuesday and then starts again costs nine per cent more capacity
than one that only ever adds — and is MORE accurate for it, having seen
more of the destination's structure earlier. **History is nearly free in
MARL whatever shape it has**: 1.103 nested, 1.092 contradicting. Pulling a
weight to zero is cheap, and the kernels left behind are few against a
population set by tiling the support.

**`MARL19_REFUND2` REFUTED at −0.491.** With the dream pinned, a sleep
still raises the population on both paths. The θ frontier makes that
precise rather than anecdotal — a student chases its teacher at θ, and a
teacher's field is a sum of gaussians with ripple at kernel scale, so a low
θ buys kernels for the ripple:

| θ | kernels | RMS |
|---|---|---|
| 0.02 | 1.041× | 1.266× |
| 0.05 | 0.890× | 1.268× |
| 0.10 | 0.736× | 1.327× |
| 0.20 | 0.528× | 1.636× |

**No student is better than its teacher on both axes.** Set against
MARL-14's noisy-field trade — 0.937× the kernels for 1.058× the RMS at
matched options — that is a different regime entirely, and the difference
is the noise.

### G38 (d) — the guitar, and the precondition the whole phase was missing

Christian, on what he actually meant, after (a)–(c) had gone looking for
the wrong thing:

> "when I play my guitar, eventually I hit a wall of improvement, but if I
>  step away and I leave it for a few days then return, I can improve again
>  on the smooth consolidated memory."

Not compression, and not the milk round. A learner AT A PLATEAU, rested,
resumes improving. So: the schedule never changes, the dream is pinned to
the teacher's own evidence, and the straight arm's RMS is printed every
period so the wall is VISIBLE before the rest is placed at it.

| period | straight | rested |
|---|---|---|
| 1 | 0.04976 | 0.04976 |
| 2 | 0.03689 | 0.04854 ← rested here |
| 3 | 0.03214 | 0.03352 |
| 4 | 0.02827 | 0.02892 |

**There is no wall.** The straight arm gains 0.00387 in its last period and
is still climbing. The rested arm ends 1.023× and 1.019× the capacity,
which measures nothing at all — the precondition the claim rests on was
never met, and the gate says so in its own output rather than reporting a
ratio as if it were an answer.

That is the finding, and it reframes everything above.

**Where does MARL hit a wall?** MARL-13 (b) answered it and this phase
walked past the answer three times: on a NOISY field NLMS does not
converge, it hovers, at `μ/(2−μ)·V` of the measurement variance HOWEVER
MUCH DATA ARRIVES. That is the only plateau in this system. On a noiseless
field there is none — MARL-10's logarithmic law keeps paying out, so there
is nothing to step away from.

### What the two phases together say

    MARL's plateau is made of VARIANCE.

So "a sleep is worth as much as there is variance to remove" and "a rest
helps once you have hit the wall" are the SAME SENTENCE, and the campaign
had already run the experiment: MARL-18's one-ray arm sits at a real wall
— its trace goes backwards mid-run, 0.22455 → 0.23232, which is hovering
— and three rests ratcheted it down to **0.940× after the best available
learning rates**. That IS the guitar, measured, and MARL-19 filed it under
the wrong heading before this gate.

The corrected reading of MARL-19's negative results: they are not evidence
against consolidation. They are the boundary of where it applies, and the
boundary is the wall.

    A sleep is worth exactly as much as there is VARIANCE to remove.

MARL-18 measured it on a noisy field and found the saving tracks the noise
(gradient 1.432, and 0.940 surviving the best available rates). MARL-19
took the noise away and the saving inverted: a sleep costs accuracy and
BUYS capacity, on both path shapes, with the dream pinned. **What a student
declines to rebuild is its teacher's noise.**

Christian's picture of the representation is right — the sum IS simpler
than the patches, and a student handed the sum has an easier job. What is
wrong is the assumption that MARL *paid* for the patches. It mostly did
not: the patches are still-valid structure (MARL-9), and the ones that are
not sit at zero, where the model's default already is (MARL-16). The
campaign's own two earlier findings had already closed the door this phase
went looking through, which is the best argument yet for the ledger being
worth its length.

### The methodological note, and it is mine

The dream sample count is an EVIDENCE DIAL. On a noisy target it is
invisible, because what a student rebuilds is bounded by what the teacher
got right. On a noiseless one it sets the student's population directly,
and G38 (a) ran it at 150 000 against a teacher trained on 120 000 — so the
student was handed a larger budget and spent it. G38 (c) pins it. The sign
did not change, but the number did, and "the sleep got bigger" was not a
claim until the θ frontier turned it into one.

    zig build test -Dtest-filter="G38"        # 65 s; (a) the milk round, (b) smoother ground, (c) addition against contradiction
    python3 tools/marl19_predict.py           # where the numbers came from, extension included

`src/marl.zig` is untouched. The additions are `src/milk.zig` — the
fixture, its two path shapes, `learn`, `sleep` and the gates — registered
in `loam.zig`'s import list AND its `test` block, which is what actually
makes a file's gates run.

## MARL-20 — a moving occluder, and the erosion mechanism that turned out to be a bin (Tuesday 2026-09-08)

Christian's plan §7/§8/§12-stage-2: keep a baked static MARL for the world
and represent moving things as RESIDUAL layers, `F = M_static + Σ M_dyn_i`,
with the architectural property being that **complexity follows change**.

This is MARL-16 cashed, and MARL-16 was a REFUTATION at the time. A bias
term was built twice and lost twice, and the sentence that came out of it
was: *zero is not special because it is zero — it is special because it is
what an EMPTY MODEL ALREADY PREDICTS.* A residual layer is zero everywhere
the world did not change, so it is the exact shape of field this
representation is free on. The phase that found that out did so by failing.

### The estimator, which is better than it looks

`aoPair` marches ONE set of directions and returns both fields. A mover only
ADDS occlusion, so a ray that already hit the level contributes exactly zero
to the difference: the two estimates are perfectly correlated wherever
nothing changed, and the difference of two Binomials sharing their draws has
far less variance than either. **A residual is cheaper to measure than a
field**, and estimating the two independently would pay √2 the noise for
strictly less information.

### G39 — the layer

| arm | kernels | KiB | RMS | build |
|---|---|---|---|---|
| the static bake, on the STATIC field | 2 638 | 103.0 | 0.15289 | 1.1 s |
| a full re-bake of the perturbed field | 2 603 | 101.7 | 0.14540 | 1.1 s |
| **static + residual, ⅛ the rays** | **283** | **11.1** | — | **0.1 s** |

On 512 probes drawn IN the object's neighbourhood, where it moves the truth
by 0.0483 on average: the stale bake 0.16257, a full re-bake 0.14239, and
**static + residual 0.14957**.

**`MARL20_SPARSE` HELD at 0.109** and **`MARL20_COMPOSE` HELD at 1.050.** A
residual layer recovers a change the static bake got wrong, at a tenth of
the kernels, an eighth of the rays and a tenth of the build time, landing
within five per cent of re-baking the whole scene. The composition is an
IDENTITY — `1 − AO_pert = (1 − AO_static) + (AO_static − AO_pert)` — so it
is not an approximation scheme and only the two fits can be wrong.

### THE MOVE, and it answers MARL-7 and MARL-8

Four moves, not one, because a single move cannot tell "adapting is better"
from "adapting is bigger". Adapting keeps the layer and is taken back over
BOTH neighbourhoods (a residual left behind is a wrong NON-ZERO value and
the model has to be told so); rebuilding starts a fresh layer over the new
one. Same budget either way.

| move | adapt k | adapt RMS | rebuild k | rebuild RMS | ratio |
|---|---|---|---|---|---|
| 1 | 493 | 0.14537 | 296 | 0.14727 | 1.013 |
| 2 | 697 | 0.14191 | 285 | 0.13939 | 0.982 |
| 3 | 887 | 0.14418 | 278 | 0.14538 | 1.008 |
| 4 | 1 086 | 0.14962 | 284 | 0.14837 | 0.992 |

**The accuracy is indistinguishable** — the ratio oscillates around parity
with no trend. **The population is the answer**, and it is MARL-7's shape
exactly: adapting grows about two hundred kernels a move, LINEARLY, at flat
accuracy, while rebuilding is flat. After four moves the adapting layer is
**3.82× the size for the same error.**

MARL-7 spent a whole phase looking for an erosion mechanism and concluded
the accumulated capacity was load-bearing with nothing to target. MARL-8
tried reuse and failed. The answer neither phase had available:

    You do not need an erosion mechanism when the thing is small enough
    to throw away.

And it is small enough only because MARL-16 made it free where nothing
changed. Three phases' worth of failure resolved by a fourth phase's
refutation.

### Two nulls and a tuned bar, recorded because they are the method

The first mover was 2.0 units at a lattice FACE centre. It disturbed 2.0%
of the query set and moved the global RMS by 0.2% — not a weak result, a
NULL. The second was 3.5 units and moved the truth by 0.0334 against a model
error of 0.14.

Then the denominator. A global probe set is diluted by construction: an
object occupying a few per cent of a scene leaves most probes untouched, and
only 24 of 512 landed where anything changed — an RMS over 24 probes is
sampling noise, not a measurement. The numbers that carry the phase are
taken over probes drawn IN the object's neighbourhood, which is also the
question a renderer asks. The global figures stay in the table so the
dilution is visible rather than chosen.

And a validity bar nearly became a tuned threshold. The first form demanded
the object move the truth by more than the cache's own RMS — the wrong bar,
because a model's error is spread over a whole field and a small STRUCTURED
change can be perfectly learnable underneath it. The second form was a round
1.15× that the measurement then landed **0.7% under**. The third is DERIVED:
the reference probes are `TRUTH_RAYS` = 4096, so their own σ is at most
0.5/√4096 = 0.0078, and a gap wider than that is a gap the instrument can
see. Measured 0.0202, which is 2.6× it.

One more correction the campaign made to itself: the arms were first run
with `rate_geom` at the default, which is exactly the handicap MARL-18's own
control caught a few hours earlier. Fixed before any number was read.

### Honest limits

The effect is MODEST — the object degrades the local bake by 1.142×, not by
a factor. Ambient occlusion in a dense grove is dominated by the grove, so a
single mover in a corridor changes little even when it nearly seals one. The
case that would show this properly is CONTACT — an object resting against
geometry, where the shading points immediately around it lose a large solid
angle — and it is untested. So is any object-local coordinate frame (§8), any
scheduler (§10), and any second mover.

    zig build test -Dtest-filter="G39"        # 11 s
    python3 tools/marl20_predict.py

`src/marl.zig` is untouched, and so is `aoAt` — `Mover`, `aoPair`,
`DynProbes`, `dynProbesNear`, `drawNear`, `teachMoved` and
`teachResidualInto` are pure additions, so every gate from G33 to G38 reads
as it did.

## MARL-21 — contact, and the ceiling on a layered representation (Tuesday 2026-09-08)

MARL-20's residual layer worked, and the honest limit recorded at the time
was that the effect was MODEST: a mover floating in a corridor degraded the
local bake by 1.142× and moved the truth by 0.0483, because ambient
occlusion in a dense grove is dominated by the grove. Christian: "go for it
with the more complex example. That is where it should start to shine."

CONTACT is that example — a 3.5-unit occluder RESTING against a grove
sphere, tangent with 0.21 of overlap, which is the case a renderer actually
has. At a contact point the object subtends nearly a hemisphere.

### The physics is right, and stronger than the floor said

All three pre-registered numbers were refuted, and the stratified
diagnostic says why:

| distance from its surface | probes | mean \|Δ\| | max \|Δ\| | mean AO |
|---|---|---|---|---|
| 0 – 1 | 10 | **0.2455** | 0.3145 | 0.6931 |
| 1 – 2 | 48 | 0.0921 | 0.1821 | 0.4963 |
| 2 – 4 | 257 | 0.0449 | 0.1155 | 0.4683 |
| 4 – … | 197 | 0.0108 | 0.0483 | 0.4401 |

**`MARL21_CONTACT` REFUTED at 0.0401 as a ball average — and measured at
0.2455 where contact happens, which is 2.5× the floor it failed.** The
change decays twentyfold over four units, and 38% of the probes sit in the
outermost band seeing essentially nothing.

    The affected ball is the SUPPORT, not the SCALE.

A residual's support and its magnitude have entirely different geometries:
the support is `r + reach`, the magnitude lives within about a unit of the
surface. This is MARL-20's dilution mistake made again — a global probe set
diluted by a local object — one level in, inside the very region that was
introduced to fix it. Twice in two phases, which is enough to make it a
rule rather than an anecdote.

### MARL-4's mechanism, and why it does not rescue the headline

`MARL21_CONCENTRATE` had predicted the composed arm would BEAT a full
re-bake locally, on MARL-11's law: evidence binds, and a re-bake spreads
60 000 samples over the whole query set (≈4 320 landing locally) while the
residual spends all 7 500 inside the ball. It measured **1.030**.

The stratification named the flaw: uniform-in-VOLUME sampling puts evidence
in proportion to r², so the layer spent ~38% of its samples where |Δ| =
0.0108 — learning that zero is zero — and 2% where |Δ| = 0.2455. MARL-4
already solved that class of problem by changing the STREAM rather than the
model, and the geometric analogue needs no tuning constant at all: draw the
radial offset uniformly in DISTANCE from the surface, which puts equal
numbers in each band and exactly cancels the r².

`MARL21_SURFACE` was frozen before that arm ran. **REFUTED at 1.023**,
against uniform-in-volume's 1.030. The reweighting is directionally right
and worth 0.7%.

### The finding, which is a ceiling

    A residual layer is bounded below by the static bake it sits on.

The composed prediction is `static + residual`, so its error carries the
static model's own fit error on the base field — 0.15078 on this probe set
— and the residual can only remove the part contributed by the disturbance,
whose mean is 0.0401. **A full re-bake wins locally because it RE-FITS THE
BASE as well**, not because it fits the disturbance better. No sampling
rule applied to the residual can touch the term that dominates.

So Christian's §7 is validated on its real merits and refuted on the one it
was hoped for. Its value is **memory, build time and update cost** —
MARL-20 measured a tenth, an eighth and a tenth, with a flat population
under motion where adapting grows two hundred kernels a move — and it is
**never accuracy**. Which is the right trade for a renderer anyway: nobody
re-bakes a level because a crate moved.

    on 512 probes at the contact                kernels     KiB       RMS
    the static bake's own floor (no mover)            —       —   0.15078
    the static bake, now WRONG                     2638   103.0   0.15228
    a full re-bake, ALL the rays                   2600   101.6   0.14074
    static + residual, 1/8 the rays                 208     8.1   0.14501
    …the SAME layer, sampled by distance            209     8.2   0.14394

### One refactor, gated by being invisible

`groveCentres` is split out of `groveVolume` so a mover can be placed
against a sphere — same stream, same arithmetic, same order. And `drawNear`
gained an exclusion for the interior of whatever occluder is actually
present, because a point inside a solid returns AO = 0 by convention and a
residual measured there would be the whole field over a region no renderer
shades. The vacated position stays IN, since that is exactly where a stale
residual has to be un-learned. G39 re-read at 3.83× and 0.997× against its
recorded 3.82× and 0.992×.

    zig build test -Dtest-filter="G40"        # 12 s
    python3 tools/marl21_predict.py           # extension included

## MARL-22 — it was never a noise floor, and a third of the query set was a question nobody asks (Tuesday 2026-09-08)

Christian, looking at MARL-21's numbers: *"Seems like the RBF might need a
higher dimension? like it's struggling to represent? or am I reading it
wrong?"*

He was reading it right, and the campaign's own instrument had already said
so and nobody read it back. **G33 (b) fits `RMS² = bias² + μ/(2−μ)·V/M` and
its intercept — the error with ALL measurement noise removed — is 0.15110**,
against a total of 0.17174 at sixteen rays. The error is **77% bias.** Every
0.15 quoted in the prose from MARL-13 to MARL-21 was called a noise floor.
It is a REPRESENTATION floor. The law itself held and was never wrong; the
sentences written around it were.

### G41 — where the representation error is

The shell query set is drawn on `|φ| < band`, which STRADDLES the surface,
so **354 of 1 024 probes (35%) sit INSIDE solid geometry**, where `aoAt`
returns exactly 0 — and under `invert` that is a plateau at 1.0, the object
MARL-16 measured at 5.679×.

`MARL22_STEP` predicted the interior would be at least twice as costly per
probe. **REFUTED at 1.268** — 0.17533 inside against 0.13831 outside. The
damage is real but spread, not concentrated.

### …and then the anchor, which is the phase

**A renderer never shades inside a wall.** The interior was in the query set
for no reason but the shape of `|φ| < band`. Deleting it:

| trained on | scored on exterior probes | vs a constant |
|---|---|---|
| the full shell | 0.13836 | — |
| **the exterior shell** | **0.06651** | — |
| a constant predictor | 0.06870 | 1.000 |

`MARL22_EXTERIOR` HELD at 0.481 — and the anchor says do not celebrate. The
exterior arm is **0.968× a constant** where the full-shell arm is 0.446×.

    Almost all of the cache's apparent skill on the grove's shell was
    learning that a point inside a wall is occluded — which the geometry
    already knows for free.

MARL-17 introduced the anchor rule with the words "every RMS before this was
quoted without an anchor". This gate PRINTED the anchor, pre-registered a
threshold that ignored it, and was saved by the number it had already been
told to print. Twice in one campaign is a habit, not an accident.

### The other two, both refuted

`MARL22_INVERT` predicted `invert` would stop mattering once the plateau was
gone. **REFUTED at 1.655** — it matters MORE on an exterior shell (0.06651
against 0.11010). The interior plateau was never what made it worth having;
the open-sky end is, and MARL-13's choice stands for its original reason.

`MARL22_CAPACITY` is the direct answer to the question. **REFUTED at
1.392**: eight times the regions gives 9 711 kernels against 1 989 and the
fit is half again WORSE. **The basis does not need more resolution — more
resolution makes it worse.** Fifth sighting of MARL-1's invariant, and it
points at MARL-11's law for the remedy: what binds is EVIDENCE.

So Christian's reading was right and the cure he proposed is not the one.

### And on a REAL level it goes the other way — MARL-17 was UNDERSTATED

The grove's exterior shell is nearly flat because the grove is a regular
lattice of identical spheres: every point just outside one sees much the
same sky. That is a FIXTURE limit, and `oa_spirit3` says so. Same volume,
same budget, `--exterior` against MARL-17's own configuration:

| query set | a constant | MARL | vs constant | grid | MARL/grid |
|---|---|---|---|---|---|
| straddling (MARL-17's) | 0.26448 | 0.12976 | 0.491× | 0.20973 | 0.619 |
| **exterior only** | 0.20617 | **0.06021** | **0.292×** | 0.15117 | **0.398** |

A real level's exterior shell is NOT flat — the anchor only falls 0.2645 →
0.2062 — and the cache does substantially better relative work on it
(0.292× a constant against 0.491×). **MARL/grid improves from 0.619 to
0.398: the learned field's advantage over a dense grid nearly doubles when
you stop asking it about wall interiors.**

So the fix is free, it is one line, and it makes the campaign's headline
better rather than worse:

    Draw the query shell OUTSIDE the geometry. A renderer never shades
    inside a wall, and asking a cache to represent the step at a surface
    spends its capacity on information the geometry already has.

### What this does to the phases above it

Nothing measured is retracted — every arm was compared against every other
arm on the same query set, so the RATIOS stand. What changes is the reading:
MARL-13 through MARL-21's absolute RMS figures are dominated by a
discontinuity, their "noise floor" language is wrong, and MARL-20/21's
0.15-ish static bake was representation-limited rather than noise-limited,
which is why more rays did not help it and why a residual layer could not
get under it.

    zig build test -Dtest-filter="G41"                                  # 25 s
    zig build marl -Doptimize=ReleaseFast -- --q3 out/oa_spirit3.vol --exemplars 120000 --exterior
    python3 tools/marl22_predict.py

`Options.exterior` defaults false and `probesOf` keeps its signature as a
wrapper over `probesOfEx`, so every gate from G31 to G40 is untouched.

## MARL-23 — the edge sweep, outside MARL: Bresenham's question, answered (Tuesday 2026-09-08)

Christian, pulling a thread after MARL-22: *"I'm just thinking back to
Bresenham... There comes a question about drawing straight lines with RBFs
and residuals and how tight you want them. That seems to be an experiment
for some simple Python outside of MARL, so we can sweep it and play."*

Right, and right about the venue. `tools/edge_rbf.py` has **no learner** —
centres are placed analytically and the weights are least-squares by SVD.
That separates what the BASIS can do from what the LEARNER finds, which
every phase so far had tangled together, and MARL-22 had just made the
distinction the important one.

The kernel is MARL's term for term, hard cutoff included, so a plateau is
not free here either.

### 1. Bresenham's law, and it is exact until it is a cliff

An elongated kernel laid along a circle of radius R with tangent half-length
L departs from the curve by a sagitta of about `L²/2R`; it stops hugging the
edge once that exceeds its own normal width, giving `aspect ≲ √(2R/σ_n)`.

Measured as **how few kernels reach a fixed accuracy**, which is what a
longer kernel is supposed to buy:

    straight edge      aspect  1 → 64 kernels,  2 → 32,  4 → 16,  8 → 8,  16 → 4
                       a saving of EXACTLY the aspect ratio, one for one

    circle R = 0.30    aspect  1 → 128,  1.41 → 64,  2 → 64,  2.83 → 32
                       aspect  4 → NEVER, at any count up to 256

So the trade is **linear in aspect right up to a hard cliff**, and past the
cliff no amount of extra capacity rescues an over-long kernel. That is
Bresenham in continuous form: you run straight, one step per step, until the
curve forces you to break.

And the cliff obeys the sagitta scaling with a constant:

| R | last aspect that works | √(2R/σ_n) | usable fraction |
|---|---|---|---|
| 0.40 | 2.83 | 8.9 | **0.316** |
| 0.30 | 2.83 | 7.7 | **0.365** |
| 0.20 | 2.00 | 6.3 | **0.316** |
| 0.10 | 1.41 | 4.5 | **0.315** |

Constant to within 8% over a fourfold range of curvature:

    max usable aspect ≈ 0.32 · √(2R / σ_n)

0.32² ≈ 1/10, so the criterion in words is: **a kernel may run straight
until its sagitta reaches about a TENTH of its own normal width** — an order
of magnitude tighter than "until it leaves its own support", which is the
bound you would write down first and which is wrong by a factor of three in
aspect.

### 2. Kernels on an edge cannot represent a step at all

The first form of the aspect sweep used a STEP as its target and scored
**1.407× a constant predictor** — worse than useless. Kernels placed on an
edge with the edge's own width cannot reach the plateau; the plateau IS the
error. MARL-16 arriving before the sweep had started, and it is why every
edge measurement here is taken on a RIDGE — the same edge with the plateau
removed, which is exactly what a residual layer is handed.

### 3. Coarse + residual is NOT cheaper to REPRESENT

At equal total kernels, a uniform tiling of the domain against a coarse
tiling plus a residual layer on the edge, with the residual layer's own
width swept:

| total | one layer | coarse + residual | ratio |
|---|---|---|---|
| 36 | 0.18312 | 0.17245 | 1.06× |
| 64 | 0.17198 | 0.15946 | 1.08× |
| 121 | 0.13670 | 0.16573 | 0.82× |
| 256 | 0.11853 | 0.12465 | 0.95× |

**A wash** — 0.76× to 1.18× across both edge shapes, with no trend. Which is
MARL-21's ceiling confirmed in the cleanest possible setting: no learner, no
noise, no evidence limit, analytic placement, exact least squares.

    A layered decomposition is not cheaper to REPRESENT. It is cheaper to
    UPDATE, and that is the whole of its value.

MARL-20 measured the update side and it is not small: a tenth of the memory,
an eighth of the rays, a tenth of the build time, and a FLAT population
under motion where adapting grows two hundred kernels a move. But the
representation question now has a clean negative from two independent
directions.

### 4. And a second reason finer is worse, distinct from MARL-1's

MARL-22 found `regions` 6 → 12 made the fit 1.392× WORSE, and attributed it
to MARL-1's invariant — capacity you cannot train. This sweep has no learner
and unlimited evidence, and finer is still worse:

    kernels    σ_n     eval      fit
         16  0.0400  0.12211  0.12438
         32  0.0200  0.08755  0.08816
         64  0.0100  0.03450  0.03366     ← σ = the feature's own width
        128  0.0050  0.06724  0.05005
        256  0.0025  339.008  0.09104

The FIT error rises along with the eval error past σ = the feature's width,
which is not overfitting — with more parameters a least-squares fit error
cannot rise unless the system is rank-deficient. **A Gaussian basis much
finer than the feature it is fitting is nearly linearly dependent**, so the
extra kernels are unusable however much evidence you have.

So there are TWO mechanisms behind "finer is worse" and the campaign had
only one:

- MARL-1's, which is about EVIDENCE — capacity you cannot train.
- This one, which is about the BASIS — capacity that is nearly a linear
  combination of what you already have.

They call for different remedies, and only the first is fixed by more data.

### What it says about Christian's question

He asked whether the residual layer should have an extra dimension while the
tree stays as it is. §3 says the extra dimension would not buy
representation — the split itself does not. §1 says what WOULD: an
anisotropic kernel aligned with the surface, whose usable elongation is set
by curvature, and which is already expressible in MARL's existing kernel.
**The open question is not whether MARL's basis can hold an edge tightly —
it can, one kernel per `0.32·√(2Rσ)` of arc — but whether the NLMS geometry
step ever FINDS that orientation.** That is a learner question and it is the
next thing to measure.

    python3 tools/edge_rbf.py                  # all three sweeps, ~20 s
    python3 tools/edge_rbf.py --sweep aspect   # the Bresenham one

Nothing in `src/` changed.

## MARL-24 — a residual layer wants a coarser basis than the bake it sits beside (Tuesday 2026-09-08)

Christian: *"what are we keeping in the residuals right now, just out of
curiosity?"*

Dumping one answered it. The target is small and broad — mean 0.0502, max
0.4297, with 52% of draws in the affected ball above 0.02 — and the layer
holding it is 283 kernels of ten floats each, weights spanning −0.2082 to
0.3192 at a mean |w| of 0.0643. That last figure is a quarter of the static
model's span (MARL-15 measured −0.4982…1.3759), which matters for
quantization, since MARL-15 uses ONE GLOBAL SPAN for the weight field and
already had "the weights use one global span" in its recorded-not-built.

But one line of the dump was not a curiosity:

    σ (of the unit cube) 0.02858 … 0.02946    and    σ_max = 0.02946

**Every kernel was pinned at the widest the clamp allows.** The whole
population against the stop. σ_max = h/√CUTOFF with h = 1/regions, and the
layer had inherited `regions = 6` from the static bake beside it — so the
geometry descent wanted them wider and could not have it.

That is MARL-23 arriving from the other direction. The edge sweep found the
optimum kernel width is THE FEATURE'S OWN WIDTH, and a residual is a
smoother object than the field it corrects. The static bake and the residual
layer are fitting different things and there was never a reason to share a
region grid.

### G42, run on the harder fixture on purpose

The observation came from the corridor, so confirming it there would be
confirming an observation with itself. MARL-21's CONTACT geometry has the
sharper residual and is the weaker case for a coarse basis:

| regions | σ_max | kernels | KiB | composed | widest/σ_max |
|---|---|---|---|---|---|
| 6 | 0.02946 | 206 | 8.0 | 0.14689 | 1.0000 |
| 4 | 0.04419 | 96 | 3.8 | 0.14625 | 1.0000 |
| 3 | 0.05893 | 51 | 2.0 | 0.14490 | 0.9994 |
| 2 | 0.08839 | **25** | **1.0** | **0.14347** | 0.9991 |

**`MARL24_SHRINK` HELD at 0.466 and `MARL24_FREE` at 0.996** — not merely
free, better. And the unregistered part goes further: **coarsening is
monotone all the way down. 25 kernels in 1.0 KiB beats 206 in 8.0.**

The last column is the mechanism confirming itself. The population is hard
against the stop at regions 6 and 4 (1.0000) and only comes off it at 3 and
2 — which is exactly where the improvement stops accelerating.

### What it does to MARL-20's headline

That phase measured a full re-bake at 2 603 kernels and 101.7 KiB against a
residual layer's 283 and 11.1, and called it a tenth. With the region grid
chosen for the layer's own target rather than inherited:

    a full re-bake        2 603 kernels    101.7 KiB
    a residual layer         25 kernels      1.0 KiB

**104× fewer kernels and 100× less memory**, at better accuracy than the
layer it replaces. No new mechanism — the layer had simply been carrying
about eight times the capacity it needed because it borrowed a number from a
neighbour with a different job.

### Method note

The numbers on the corridor came out of an INSPECTION, before any threshold
was written, which is the order this campaign does not accept. They are
recorded above as an observation and the gate was pre-registered for a
different fixture. That is the only honest way to promote something noticed
by accident into something measured.

    zig build test -Dtest-filter="G42"        # 11 s
    python3 tools/marl24_predict.py

## MARL-25 — was `regions` wrong everywhere? (Tuesday 2026-09-08)

Christian, after MARL-24: *"so what, it works now? ... we should try it on
some of our previous stuff maybe."*

The sharper version of that is not re-running old arms but taking the
DIAGNOSTIC that made MARL-24 findable and pointing it at everything:

    the share of a population sitting within 1% of σ_max

σ_max = h/√CUTOFF exists to keep the 27-region gather exact. A population
hard against it is one the geometry descent wanted WIDER and could not have,
so `regions` is finer than the target needs. One reading was already on the
record unnoticed — G37 (c) printed the static bake's mean σ as 0.0278
against a σ_max of 0.02946.

### G43 — the clamp, read on the arm every occlusion phase has used

| shell | regions | kernels | KiB | RMS | × constant | pinned |
|---|---|---|---|---|---|---|
| straddling | 6 | 2 638 | 103.0 | 0.15213 | 0.446 | 43% |
| straddling | 4 | 1 072 | 41.9 | 0.16299 | 0.478 | 29% |
| straddling | 3 | 597 | 23.3 | 0.16431 | 0.482 | 19% |
| **exterior** | 6 | 1 989 | 77.7 | 0.06651 | 0.968 | **64%** |
| **exterior** | 4 | 864 | 33.8 | 0.06274 | 0.913 | 48% |
| **exterior** | 3 | 485 | 18.9 | **0.06048** | 0.880 | 37% |

`MARL25_PINNED` REFUTED at 43%, and the relationship it was reaching for is
cleaner than the threshold: **the more pinned population is the one where
coarsening pays.** 43% pinned, coarsening costs 7.1%; 64% pinned, coarsening
gains 5.7%.

`MARL25_STEP_PAYS` is DEGENERATE — a ceiling on a ratio of two positive
costs where one came out negative. Not asserted. Its claim holds in a
stronger form: **the step was not paying part of the fine grid's price, it
was paying all of it.** MARL-14 measured coarsening as a trade (6 → 3 for
4.32× fewer kernels at 1.23× the error) and it measured honestly — on a
query set with a step in it, which is the finest structure in the target and
the thing a fine grid is bought for. MARL-22 showed a renderer never asks
there.

`MARL25_FREE` HELD at 0.943 — better than free — and on the grove it keeps
going: **four times less memory and nine per cent better** at regions 3.

### …and on a real level, where the field actually varies

The grove's exterior shell is nearly flat (0.968× a constant at best), so it
cannot show what this is worth. `oa_spirit3` can:

| regions | kernels | KiB | RMS |
|---|---|---|---|
| 6 | 1 207 | 47.1 | 0.06021 |
| **4** | **504** | **19.7** | **0.05968** |
| 3 | 280 | 10.9 | 0.06889 |
| 2 | 138 | 5.4 | 0.07617 |

**Regions 4 is strictly better than 6: 2.4× fewer kernels, 2.4× less memory,
and a slightly lower error.** Past that it becomes MARL-14's trade again,
which is the honest boundary — the free step is one, not three.

### What the two one-line changes do to the campaign's headline

| | query set | regions | MARL/grid |
|---|---|---|---|
| MARL-17 | straddling | 6 | 0.589 |
| MARL-22 | exterior | 6 | 0.398 |
| **MARL-25** | **exterior** | **4** | **0.329** |

The headline is the f32 MASTER, per Christian's ruling that quantization is
a production step and not a measurement: **504 kernels in 19.7 KiB at
0.05968 — 0.289× a constant predictor** — where MARL-17's master was 1 479
kernels in 57.8 KiB at 0.491×.

*(Production, reported apart: distilled to regions 3 and quantized at 54
bits gives 249 kernels in 1.7 KiB at 0.07063, which is 0.322 of a same-sized
grid. Not part of the comparison above.)*

Two lines. Neither is a mechanism, neither is new maths, and between them
they nearly halve the error relative to the field's own scale.

### One consequence worth flagging

The distillation dial has less room once the master is already coarse. At a
regions-6 master, MARL-14's 6 → 3 was a 4.32× population cut; from a
regions-4 master, 4 → 3 is 504 → 249, a 2× cut for 1.13× the error. The two
levers overlap, and taking the free one first leaves the paid one with less
to sell.

    zig build test -Dtest-filter="G43"        # 40 s
    zig build marl -Doptimize=ReleaseFast -- --q3 out/oa_spirit3.vol --exemplars 120000 --exterior --regions 4
    python3 tools/marl25_predict.py

`cache.pinnedFraction` is the diagnostic, promoted out of MARL-24's
inspection because it reads off any model.

## The state of things, and the plan for next session (Tuesday 2026-09-08, end of day)

Six phases today — MARL-20 through MARL-25 — plus MARL-18 and MARL-19 in the
morning. Eight in a day, and the shape of it is worth stating: **almost
every one was refuted, and the campaign got materially better anyway.**

### What actually moved

| | query set | regions | MARL/grid on `oa_spirit3` |
|---|---|---|---|
| MARL-17 (yesterday) | straddling | 6 | 0.589 |
| MARL-22 | exterior | 6 | 0.398 |
| MARL-25 | exterior | 4 | **0.329** |

Two one-line changes, neither a mechanism. And a residual layer for a moving
object went from "not built" to **25 kernels in 1.0 KiB**, with a flat
population under motion where adapting grows two hundred kernels a move.

### What was learned that is not a number

- **It was never a noise floor.** 77% of the occlusion error is
  representation. Every phase from MARL-13 to MARL-21 said otherwise in
  prose.
- **A layered decomposition is cheaper to UPDATE, not to REPRESENT.**
  Confirmed twice — once inside MARL (MARL-21) and once outside it with no
  learner at all (MARL-23).
- **Bresenham's law for RBFs**: one kernel per `0.32·√(2Rσ)` of arc, linear
  in aspect up to a hard cliff.
- **Two mechanisms for "finer is worse"**, where the campaign had one:
  MARL-1's evidence limit, and MARL-23's near-rank-deficiency. Only the
  first is fixed by more data.
- **The clamp is a diagnostic.** The share of a population pinned at σ_max
  says whether `regions` is finer than the target needs, and it reads off
  any model.

### The plan for next session, in order

**1. The configuration audit, and it comes first because it protects
everything after.** `cache.Options.best()` now exists and nothing uses it
yet. Migrate the gates that SHOULD move to it, leave the historical ones
alone deliberately, and make the difference explicit in each. Then re-read
the campaign's grove chain — G33's 0.912, G34's 0.878, G35's 0.804 — at the
corrected configuration, because their RATIOS stand but nobody knows what
the picture looks like now. Cheap, and it stops the next finding landing on
sand.

**2. Does the learner ever FIND the orientation?** MARL-23 established what
the BASIS can do with an edge — one kernel per `0.32·√(2Rσ)` of arc, with
kernels placed analytically and oriented by hand. Whether the NLMS geometry
step discovers surface-aligned anisotropy on its own is untested and is the
highest-value open question in the campaign: if it does not, there is a
large win sitting in the geometry step, and MARL-1's "deformation buys
2.15×" was measuring something much weaker than what is available. The
instrument already exists — `tools/edge_rbf.py` grows an arm that DESCENDS
the shapes instead of placing them, and the comparison is against the
oracle-aligned frontier it already measured.

**3. The narrow-band SDF proxy**, still parked from Monday and never
started. Learn `max(0, band − |sdf|)` rather than the SDF, because zero is
the model's default and a directly-learned SDF would report contact
everywhere it has not looked. Physics cares about MAX error and everything
this campaign has measured is RMS — `Model.rms` already takes a `max_abs`
out-param that nothing has ever printed.

**Recorded, not built**, and unchanged: QAT inside the distillation transfer
step, a noise-aware birth test, per-region weight spans (MARL-24 found a
residual layer's weights span a quarter of a static model's, and MARL-15
quantizes over one global span), object-local coordinate frames, a per-frame
scheduler, and D > 3.

## Where this goes, against the map the campaign measured (Tuesday 2026-09-08)

Christian's list, after MARL-17: radiance fields and GI, occlusion,
importance sampling for rays, procedural materials, and proxy meshes for
physics. Put against what was actually measured, four of the five sit in
the win case and two carry concrete gotchas that are worth writing down
before anyone builds on them.

**Occlusion** — measured. 0.418 of a same-sized dense grid's error at the
shipped size (MARL-17).

**Procedural materials** — measured (MARL-11, MARL-12). Nine channels cost
no extra kernels and the blend got slightly BETTER for having eight
passengers. Bounded by the sparsity rule: the marble's veins are 9–28% of
the cube, which is why it works.

**Radiance / GI** — a strong fit, and MARL-12 is why: RGB is C = 3, SH is
C = 9 or 27, and nine channels were free. Two things transfer with it —
`rate_geom` must be divided by **√C** or it diverges in MARL-1's shape, and
SH bands have wildly different magnitudes so the per-channel normalisation
is not optional. The caution is MARL-13's: GI in a large open room is
smooth and volume-filling, which is the LOSING case. The win is where
geometry is dense.

**Importance sampling** — needs no D > 3, which is the standing debt it
looks like it would need. A distribution over directions per position is
5-D, but its SH or wavelet coefficients are CHANNELS on a 3-D field, and
the C-channel machinery already does that. One read-time detail: a sum of
gaussians with signed weights is neither non-negative nor normalised, so it
wants clamping and renormalising on read — which is what `rbf.compose`
already does to the blend.

### Proxy meshes: the trap, and it is MARL-16's finding wearing a hat

Best fit of the five on paper — a surface is a 2-D set in 3-D, which is
maximally sparse in the domain; distillation gives LOD proxies at any
budget; and C∞ means normals are free and continuous, which is what
collision response wants.

**But zero means "on the surface", and zero is exactly what this model
returns where it has learned nothing.** The hard cutoff makes the field
EXACTLY zero away from kernels — that is the property MARL-16 turned on,
and it is why a bias term made things worse. A naively learned SDF proxy
therefore reports CONTACT EVERYWHERE IT HAS NOT SEEN, which is the worst
possible failure direction for physics.

The fix falls out of the same finding: do not learn the SDF, learn a
NARROW BAND — something of the shape `max(0, band − |sdf|)`, which is zero
far away (free, and correct: "no surface here") and positive near the
surface (sparse, and the win case). Recover the surface from the band's
crest rather than from a zero crossing.

**And physics cares about MAX error, where everything here is RMS.**
`Model.rms` already takes a `max_abs` out-param and the cache has never
printed it. An RMS of 0.15 with a worst case of 0.6 is a proxy that lets
things fall through floors. That number belongs on the table before anyone
builds on this, and getting it is a print statement.

Neither is built. Both are consequences of measurements already in this
ledger rather than new speculation, which is why they are written here.

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


## ALG-1 follow-up — query correctness and the velocity observable (2026-09-09)

Christian handed over the completed, uncommitted ALG-1 beat for a fresh
look. Two corrections precede ALG-2; no pre-registered threshold value
was changed, and the frozen Python predictions remain untouched.

**Transport must preserve the query as well as the parameters.** A warp
can violate the learner's one-region-edge support bound. `Model.compact`
and `reseedFrom` now detect this (including centres outside their owner's
cube) and select an ordered full gather. Ordinary fitted models keep the
27-region path. G44 (i) rotates an admissible kernel into a shape whose
support crosses two owner cells: the old gather returns zero for a
nonzero contribution; the new query agrees bit for bit with `predictAll`,
also over 2 048 random points. Copying preserves this behaviour and
removing the last kernel restores the narrow path. The old gather is an
executable mutation in the gate.

This deliberately pays O(K) kernel evaluations for affected models;
it does not shrink or refit the field. A fixed 5³ gather was not chosen
because repeated nonlinear deformation can outgrow it too. A spatial
index based on transformed support is deferred until transported-query
cost is measured as the bottleneck. Derivatives stay in `field.zig`:
there is no correctness pressure to move the pinned kernel boundary.

**The circulation conclusion was not measured by G44 (h).** Its two arms
used different probes and subtracted RMS errors against truth. G44 (h)
now shares probes and reports direct RMS between the fields. At 10 and
40 steps this is 0.020783 and 0.064921, while the truth-RMS difference
falls from 0.00927 to 0.00053. Small difference of errors is not small
field error. The reference centre is still 0.096610 from its starting
point at 40 steps: a nominal rotation period is not this swirl's period.
G44 (j) supplies a closed-streamline counterexample: a 1% angular-rate
bias grows displacement from 0.003927 to 0.015705 at quarter/full turn.
Removing that bias is the executable mutation; strict growth disappears.
The lab book retains the original numbers and records the correction.

The main push-forward result survives full support: swirl 0.432× a
constant versus the projected loop's 1.431×, 125 versus 894 kernels.
The appropriate ALG-2 comparison still includes deferred projection,
but cancellation on recurrence is now a hypothesis to test directly,
not an established law to build on.

Validation: ReleaseSafe G44 and G17 passed; G28's transplant/compaction
check passed. No full-suite rerun or commit in this follow-up. Logs are
in `/tmp/marl-g44-review.log`, `/tmp/marl-g17-review.log`, and
`/tmp/marl-g28-review.log` for this workspace session.


## ALG-1 diagnosis — initial fit versus transport, and one materialisation (2026-09-09)

Christian asked whether the observed errors indict the original MARL
representation and what can improve them. G44 (k) holds the initial fit
immutable, transports coordinates instead of kernel parameters, and
measures all arms on common final swirl probes. The original model read
at backtraced coordinates has RMS 0.008781 (0.049× a constant); the pushed
model has 0.073649 (0.413×). Their direct separation is 0.071951, while
40-versus-640-step backtracing differs by only 8.547e-6. The large added
error is therefore the local-affine transport approximation in this case.
A nonlinear deformation need not preserve Gaussian shape.

A fresh model fitted ONCE to transported examples of the original model
has RMS 0.023059 (0.129×), using 267 kernels instead of 125, 60k exemplars,
and 0.875 s in ReleaseSafe. No analytic target is used to train it. This
is approximately 3.2× less error than pushing for 2.1× the kernels and a
fit pass. The backtraced reader keeps the best accuracy but pays for flow
integration on each read; its cost is not hidden in a claimed free warp.
The proposed ordering `ALG1_PULLBACK_MARGIN = 1` was written before the
run and held. No existing threshold or default was changed.

The diagnostic informs ALG-2, without claiming its k sweep is complete.
Mutation: leave training points at their source locations; a student
trained without transport must lose the proposed advantage. The fitted
source values, stream, exemplar count and all other settings stay fixed.

ReleaseSafe G44 (k) passed. The executable mutation failed its ordering
assertion at RMS 0.197182 (1.105× a constant), as intended; the transported
training locations were restored. Logs: `/tmp/marl-g44k-review.log` and
`/tmp/marl-g44k-mutation.log`. No full-suite rerun or commit for this
additive diagnostic.


## G45–G46 — width is a representation choice, transport has another scale (2026-09-09)

Christian authorised further investigation and suggested locally chosen
advection methods or representations. `tools/width_predict.py` records
G45's geometry prediction and G46's initial ranking prediction before
their measurements; the additional sharp-shell and weight-only controls
are labelled exploratory.

The core gains `Options.support_edges` (default 1): the permitted support
half-extent and query stencil can grow independently of ownership region
size. The initial width ceiling follows that limit; the centre trust and
minimum width keep their old scale. The Gaussian evaluator, original
defaults and pinned cross-repo semantics are unchanged. A query-work
instrument calls the actual gather, without a learning event. The field
module's pinned-width diagnostic now reads the model's configured limit.

G45's smooth-blob sweep, seeds 7/19/41 and 60k matched exemplars, finds
that doubling support with broad births buys 0.2939× population and
0.7511× initial raw RMS. Permitting widening from the old birth width
buys less. Quadrupled support settles at 13 kernels for all three seeds.
But pushed swirl error rises with width: the widest kernels fit the
initial field best and follow the nonlinear flow worst. On the existing
two-sharp-shell target (200k exemplars, two seeds), doubled support instead
costs 17% more error for 72% fewer kernels. Width is not changed globally.

G46 probes each kernel's local deformation discrepancy and compares
selectively backtraced contributions with matched random subsets. At
6 of 13 corrected kernels, selected/random RMS is 0.0361 across three
seeds. A necessary follow-up baseline — absolute weight alone — gets
almost exactly the same result (local-error/weight RMS 0.9956). This
fixture therefore earns importance-based selection as an accuracy signal,
not the extra calibration work. No per-node scheduler is introduced.
The mixture selects complete kernel contributions, preserving their
continuous interiors rather than adding cell-face method switches.
The existing hard support cutoff still applies.

The diagnostic is not a speed claim: once a query needs a backtraced
contribution it pays for a shared backtrace. A support bound on deformed
contributions, or an amortised flow map, is needed to turn selection into
runtime savings. A future selector experiment should put equally
important components under different deformation, so importance alone
cannot answer the experiment. These triggers are recorded in the lab
book alongside full tables and configuration details.


Validation for G45–G46: ReleaseSafe G17, G44 (i), G45 and G46 passed.
Executable mutations were compiled and run: making the broad-birth arm
use historical support produced population/RMS ratios of exactly 1 and
failed G45's population comparison; reversing the local-error ranking
produced selected/random RMS 1.4459 and failed G46. Both mutations were
restored and the gates passed again. G45 (a)'s stencil/reference witness
also covers ownership grids 4/6/8, including non-power-of-two cell widths.
No full-suite rerun or commit for this beat. Session logs are
`/tmp/marl-g45-restored.log`, `/tmp/marl-g46-restored.log`,
`/tmp/marl-g45-mutation.log`, `/tmp/marl-g46-mutation.log`,
`/tmp/marl-g17-width.log`, `/tmp/marl-g44i-width.log` and
`/tmp/marl-g45a-grid.log`.


Pre-commit validation (2026-09-09): the complete `zig build test` suite
passed in ReleaseSafe, exit 0, including the legacy simulation gates and
G44–G46. The run took about twelve minutes including compilation; the
old three-minute estimate in the working guidance was stale. Log:
`/tmp/marl-precommit-suite.log`. This supersedes the earlier per-beat
notes saying no full-suite rerun had yet been performed.


## ALG-2 — fewer materialisations, with the intervening reads measured (2026-09-09)

G47 (`src/deferred.zig`; pre-registration `tools/alg2_predict.py`) sweeps
checkpoint intervals 1/2/5/10/20/40 over the standing 40-step swirl, seeds
7/19/41. Every arm spends 240k training examples after the common initial
60k fit. Targets come only from the previous checkpoint model. Between
fits, a cheap pushed model and a coordinate pullback into the checkpoint
remain readable. The cheap model never becomes the teacher.

Mean per-frame cheap-view RMS / constant is
0.4794/0.2438/0.1341/0.0989/0.1097/0.1960: interval 10 wins at each seed.
Final-only scoring would choose interval 40 (0.0777 versus 0.1508 at 10).
Pullback mean error decreases to 0.0524 at 40, paid by 19.5 pending RK4
steps per query versus 4.5 at 10. The two pre-registered comparisons hold;
no threshold was retuned.

The pre-planned 60k-per-fit control gives every-step fitting ten times the
primary budget. Its mean error improves to 0.2278, but still exceeds
interval 10's 0.0989 at one tenth the evidence. Both undertraining and
repeated materialisation contribute in this experiment. See lab book §5c
for tables, costs, sampling measure and conservation limitations.

The first checkpoint identity check found a two-ULP copy discrepancy:
reseedFrom rebuilds region lists in kernel-index order, while learning
can rehome kernels in another order. The experiment's clone preserves
that order; core reseeding semantics are unchanged. G47 also checks
actual observation counts, quarter-turn pullback and zero-step identity.
Targeted ReleaseSafe G47 (a), (b), and (c) passed. Christian subsequently
replaced the full-suite-per-commit rule with smoke checks and roughly
daily full regressions; see the workflow entry below.


## Testing workflow — smoke by default (2026-09-09)

Christian: "We need a sniff test, not a full regression suite." `zig build test` now selects nine existing contract gates: loam publication/guards,
mixed-gauge seam continuity, the cross-repo Gaussian pin, MARL kernel and
gradient pins, gather correctness after learning, held-out learning gain,
transported support, and deferred coordinate reads. It also runs the two
existing CLI grammar/ladder tests. `-Dtest-filter` still replaces that
selection with an affected gate. Research sweeps and their thresholds
remain unchanged under the explicit `zig build test-full` target.

Normal commits use smoke plus affected gates. Full runs are roughly daily
or justified by a broad change, not automatically every commit; no daily
scheduler was installed. The second full run today was cancelled (exit
130) after this instruction, not recorded as passing. The earlier full
suite at b53ea5a passed. CODEX.md is the compact recovery guide, with
AGENTS.md pointing to it; it supersedes CLAUDE.md for Codex recovery.

Validation: the new default smoke target passed 12/12 tests in 18.85 s
including compilation; its main test executable took about 3 s. The count
includes the module registration test and both CLI tests. No second full
suite was launched after changing the build target.


## OBS-1 — evidence follows the preimage (2026-09-09)

G48 opens docs/MARL_OBSERVATIONAL_CAMPAIGN.md. For a flow independent of
MARL parameters, the derivative of M_theta(Phi_-t(x)) is MARL's existing
parameter derivative at the preimage. `observed.assimilate` uses that
coordinate for observe, retaining the learner's responsibility and births.
It mutates an owned source state and invalidates its earlier views.

Three seeds, displaced initial state, 30k delayed scalar observations:
pooled held-out corrected/prior RMS 0.12553; corrected/wrong-coordinate
0.04884; corrected/source-oracle 1.00950. Corrected models add 2–5 kernels;
wrong-coordinate updates grow roughly 900 and make error worse. The two
pre-registered directional predictions hold; thresholds are unchanged.
G48(b) pins a delayed weight derivative and manual-update equivalence.
Both targeted ReleaseSafe gates passed. This does not learn dynamics;
rotating held-out probes makes the future score another view of the same
state error. Full methods, limitations and next experiment are in the
new lab book. The user's observational design note was read, not edited.


## OBS-2 — trajectory endpoints infer a frozen potential (2026-09-09)

G49 (`src/inferred.zig`, `tools/obs2_predict.py`) learns nine fixed Gaussian
coefficients from 32 endpoints on 16 short trajectories. Velocity is
-gradient(P), not acceleration. True potential lies in this basis;
observations are noiseless. Headline computation is f32. Synthetic
endpoints use finer integration than prediction. Three seeds, matched
observations, K=9 and 400 full-batch updates in each arm.

Correct/prior pooled held-out endpoint RMS .003332, correct/wrong-dynamics
.002397; potential-gradient error/prior .003826. Wrong dynamics add a
prescribed rotational velocity that no scalar potential can cancel
everywhere. Its training error improves, but held-out improvement is mixed
and remains far worse than the correct arm. Both use 409600 RHS calls
and 3686400 kernel evaluations per seed, about .025 s fitting per arm.
This isolates coefficient inference; it does not test adaptive births.

The f64 sensitivity audit covers all weights, 3 starts/seeds, 4 lengths
and 3 perturbation sizes. Original all-raw-differences-pass prediction is
REFUTED: four failures at h=.001, none at .0001/.00001. The preregistered
amendment adds Richardson cancellation without changing tolerances;
all 972 comparisons pass, worst relative error 2.65e-6, with derivatives
spanning 3.14e-8 to .8264. Omitting position feedback fails 936 raw checks.
This mutation exposes the Hessian term in temporal credit assignment.
G49(a) and (b) pass targeted ReleaseSafe. Full method and limitations are
in docs/MARL_OBSERVATIONAL_CAMPAIGN.md. No full suite was launched.


## OBS-3 — already-covered births improve training and worsen prediction (2026-09-09)

G50 adds a restricted candidate-birth policy to inverse fitting, with
pre-registration in tools/obs3_predict.py. Four arms cross correct/wrong
dynamics and frozen/adaptive allocation. Identical OBS-2 data, 1200 updates,
41 shared candidate shapes, active cap 25. All candidates carry sensitivities
in all arms, including frozen controls. This is not original MARL.observe
or moving-geometry differentiation, and allocated dictionary memory is
fixed: K counts active basis functions.

Correct arms stay at K=9 without requesting a birth. Wrong adaptive arms
reach K=25 at step 1040, each with 16 births (6 after 800) and 4 subsequent denied
requests. Compared with wrong frozen controls, pooled training RMS falls
to .3432x but held-out RMS rises to 1.8230x. Each birth centre already has
maximum active Gaussian coverage .8133–1.0; 39/48 births use the finer .09
width. Each seed revisits three candidate locations at a second scale.
The two growth predictions and held-out ordering hold.

Every arm uses 1,228,800 learning RHS and 50,380,800 learning basis evaluations.
Actual coefficient updates are 10,800 in frozen/correct arms versus 18,176
in wrong adaptive arms; budget and dominant search work are matched, not
every instruction. Timings including scoring/output are about .43s per arm.
All 32 endpoints repeat throughout: no newly arriving evidence, no deletion,
no claim of persistent birth-death churn. Internal paths differ despite
matched sensors and candidate coverage; visits are recorded separately.

The lab book OBS-3 section details the policy, controls and limitations.
Portable CSVs in docs/data/obs3 preserve 360 histories/spatial snapshots,
48 births and 12 final reports; tools/obs3_report.py extracts a complete log.
The shared trajectory engine moved to src/trajectory.zig. Targeted G49
still matches prior results; G50's zero-weight birth, dormant-candidate,
fine sensitivity, masking, capacity and work contracts passed.


## OBS-4 — useful growth transfers; optimisation can also demand false repairs (2026-09-09)

G51 runs the preregistered simple/rich × repeated/fresh × correct/wrong ×
frozen/adaptive factorial, three seeds, three 1200-update windows. Rich
truth adds two fine components absent from the initial nine-kernel span.
Incoming windows are scored BEFORE updates; a new disjoint fixed 64-start
evaluation set never enters learning or birth decisions. All arms share
3,686,400 learning RHS calls and 151,142,400 kernel evaluations. Capacity,
scoring policy, optimizer and candidate geometry are unchanged.

All five directional hypotheses hold. Rich correct adaptive/frozen RMS:
repeated training .061355, evaluation .108451; fresh evaluation .015934;
incoming fresh windows .087542. Correct/wrong rich fresh adaptive final
evaluation ratio .007673. Both finish K25, yet wrong/correct cross-window
repeat requests are 66/0. This separates useful from compensatory growth
on this fixture, but not through final population alone.

The controls defeat a stronger classifier interpretation. Simple correct
models acquire unnecessary candidates and worsen evaluation; one correct
rich repeated-data seed makes 13 cross-window repeat requests. A separately
recorded post-inspection diagnostic holds an accurate step 800 simple model
or continues coefficient updates, with births disabled. Continued updates
produce 7/8/10 above-threshold requests; held state produces 0 and stays
bitwise fixed. Continued optimisation itself can create structural
pressure. The diagnostic's checkpoint was chosen after seeing results;
it is not a proposed or independently validated stopping policy.

Full method and limitations: observational lab book OBS-4. Portable data
in docs/data/obs4 includes 960 sensors, 144 window transitions, 1440 history
and spatial rows, 1096 requests, 48 final reports and 6 diagnostic records.
G51(a/b) and diagnostic(c) passed targeted ReleaseSafe. No full suite run.

## OBS-5 / G52 — the churn floor: calibrating population as an instrument

OBS-4(c) found that continued optimisation alone manufactures birth pressure
on stationary noiseless data already fitted to 2.2e-7, and scoped the cause
no further than "Adam/finite-precision dynamics". Its subject is the core
learner, so its consequence is campaign-wide: population is a headline in
MARL-7, MARL-9, MARL-10, MARL-20 and every occlusion phase, and the
observational note's §12 and §31 ask population to BE an instrument.

G52(a) isolates it, and it is neither finite precision nor this fixture.
Adam's step is lr*mhat/(sqrt(vhat)+eps); that ratio is dimensionless, so the
step stays at lr however small the gradient becomes. Fixed-rate Adam does not
converge, it wanders in a ball of radius set by lr. MARL's own `adam` is the
identical expression. Its NLMS default is not: `w -= rate_w*e*g/sum(g^2)`
and the geometry step through `ew = sum_c w_c a_c` are linear in the residual
and vanish with it.

`adaptive_inferred.Model.updateAt` exposes the rate; `update` delegates at
`RATE`, so every G50 and G51 number is bit-identical and the fixed arm
reproduces OBS-4(c)'s 7/8/10 exactly. Mean max train RMS over three seeds is
8.033e-4 / 2.169e-4 / 1.264e-5 at lr, lr/2, lr/4 — ratios .270 and .058
against a registered ceiling of .60, steeper than the derived linear relation
because below some amplitude the wander stops crossing the birth score at all
and the maximum collapses to the checkpoint. Not fitted. A 1/t schedule holds
the fit at 3.3e-7/3.2e-7/1.9e-7 and makes zero requests at every seed; the
milder 1/sqrt(t) leaves six, which is why both were registered.

G52(b)'s first design needed a settled model and did not have one. At 300k
settling and four equal windows, NLMS RMS fell .01989 -> .01476 across the
measurement — still improving 26% — so its births were learning and neither
registered number meant what it was written to mean (RMS .742 "held" against
1.05, births .52 failed against .10). MARL-19(d)'s shape; MARL-10's reason.
Both thresholds are left standing and marked superseded rather than struck.

Re-posed to a form needing no settled state, and registered in obs5_predict
§(3') before it ran: under MARL-10's law the marginal cost decays as A/n, so
the integral over a doubling is A*ln2, a constant, while an additive floor of
c births per exemplar contributes c*n and doubles. Checkpoints 100k/200k/400k/
800k/1600k, responsibility 3, otherwise default.

NLMS doubling ratios .848 .807 .743, mean .799, FALLING — no additive floor,
and growth on a stationary stream is slower than logarithmic, so MARL-10's
law (fitted on a drifting stream) is an upper bound on the stationary case.
Adam's .409/1.408 1.447 1.528, mean 1.461, RISING toward the two an additive
floor demands. Its registered floor of 1.60 is refuted at 1.461 and the gate
asserts the shape instead, which needs no threshold. Adam adds 14,530 kernels
in the last doubling, reaching 47,037 against NLMS's 4,128, while its RMS
does not move: .796 to .845 of a constant, slightly worse. Eleven times the
population for eleven times the error.

The doubling ratio excludes window 1 by definition, not by preference: it
runs from an empty model to 100k and is the initial fit, holding 3,386 of
NLMS's 4,128 kernels, so dividing window 2 by it compares a doubling against
a from-scratch build. With it included the arms read .617 and 1.195; the
correction is the harness's error, on the same footing as ALG-1's jitter
measured in the wrong unit.

Scope, registered before the run: this licenses only that under NLMS on a
stationary noiseless field MARL does not manufacture capacity. Nothing about
moving or noisy fields — MARL-13(c) already measured that floor from the
other side (9,923 kernels at one ray against 7,656 at sixteen) and it stays.
For the observational campaign, OBS-3 and OBS-4 run Adam at a fixed .003 and
therefore sit on a wander OBS3_BIRTH_GAIN was never calibrated against; a 1/t
schedule removes it at no cost to the fit, and whether their directional
findings survive is a re-run.

Recorded, not built: a maturity decay on MARL's rates (Kernel.updates is
already there and nothing schedules on it) must not be built on this
evidence. It would freeze exactly the kernels a drifting world most needs to
move, and MARL-7 priced that. Trigger: a churn floor found under NLMS,
measured against a drift arm in the same phase. G52(b) found none.

Cost: G52 ~96 s, 80 of it Adam's 1.6M exemplars at 47,037 kernels. Not smoke.

## OBS-6 / G53 — the birth signal, recalibrated

OBS-3 and OBS-4 ran Adam at a fixed .003, so OBS3_BIRTH_GAIN — which decides
what counts as a birth request in both — was calibrated against a signal
sitting on the wander OBS-5 measured. G53 reruns OBS-4's 48-cell factorial
unchanged in every other respect, twice, under Sched.none and Sched.inv.
G51(b) reproduces bit-identically under .none, so nothing was disturbed:
births 47, .061355, .108451, .015934, .087542, .007673, repeats 0/66.

The schedule is lr0*min(1, t0/t) with t0 = 400, both halves read off the
harness. Births are gated on step > 400, so that is when the birth signal
starts being read; decaying earlier slows learning over readings nobody
uses. 1/t and not 1/sqrt(t) because G52(a) measured both here — the milder
one left six requests standing where 1/t left zero. RHS calls and
coefficient updates are unchanged, so the equal-budget contract holds.

The null took two attempts to measure anything. Pooled over the factorial,
then over correct-dynamics arms alone, it reads .9999 and 1.0000 — dominated
by cells where the fit is limited by the MODEL CLASS (the rich field's two
components outside the nine-kernel span; the wrong dynamics) and no rate can
move those: 1.702e-2 -> 1.702e-2 and 3.035e-2 -> 3.035e-2. The cell where
the rate binds is simple field, correct dynamics, frozen allocation, whose
target the model class contains exactly. There the null INVERTS: 1.669e-4 ->
4.609e-7 and 5.177e-4 -> 4.380e-7, better by 360x and 1180x. Fixed-rate Adam
was hovering as G52(a) measured; the schedule lets it converge. Both the
pooled figures and that cell are asserted.

All five OBS-4 comparisons hold, four of them 3.5x to 16.6x better, on a
THIRD of the births: 47 -> 16, train .061355 -> .003700, eval .108451 ->
.021985, fresh .015934 -> .004521, correct/wrong .007673 -> .002229. Two
thirds of what OBS-4 counted as useful growth on the rich field was the
optimiser's wander, and removing it improved every accuracy comparison. The
exception is incoming, .087542 -> .161477, still well under one — what less
transferred capacity should do, reported and not explained.

The control clears completely. On the simple field under correct dynamics,
where there is nothing to buy, adaptive/frozen eval goes 8.73 -> 1.000 and
3.58 -> 1.000 — exactly one because the two arms are the same run: control
births go 74 -> 0. Across the whole factorial, cross-window repeat requests
go correct 13 -> 0 while wrong 354 -> 362, untouched. OBS-4's caution was
about the instrument and not about the claim, and on this fixture repeat
pressure now separates wrong from correct perfectly.

Not claimed: the schedule is not a default for anything. MARL's learner does
not use Adam by default and G52(b) showed its NLMS default has no floor to
fix. OBS-3's original claim boundary is unchanged — no death policy, so
rejected requests are pressure and not churn; the true field lies inside the
initial nine-kernel span on the simple field and demonstrably not on the
rich one. Whether a detector built on repeat pressure generalises past this
fixture stays untested.

Cost: G53 ~120 s, two full factorials. Not smoke.

## OBS-7 / G54 — operator inference, and what actually governs it

The note's §29 level 3 by way of §27. The rig already contained a hidden
operator: trajectory.zig's law is xdot = omega*R(x-c) - sum_i w_i grad phi_i,
and OBS-3..6 used omega as a KNOWN knob (correct 0, wrong .3). Level 3 takes
it away — the truth has it, the learner is not told, and must find it in a
library. src/law.zig is a separate engine because G49, G50, G51 and G53 rest
on trajectory.zig reproducing bit for bit; the sensitivity ODE sdot =
df/dtheta + J*s is the same shape in both, so only the loop is duplicated.

Library: rotation (-dy,dx), divergence (dx,dy), shear (dy,dx), drift x (1,0),
drift y (0,1). Only rotation is in the truth. obs7_predict argued from
Helmholtz that §27's criterion could only half hold, because the learner is
already fitting a pure gradient field and four of the five candidates are
themselves gradients.

G54(a): worst relative sensitivity error 4.42e-8 over all fourteen
parameters against Richardson finite differences. The mutation drops the J*s
coupling and is off by 100% at 8 steps and 178% at 64 — same sign, same
order, worse with the horizon.

G54(b): §27's criterion HOLDS IN FULL and the prediction is REFUTED.
Rotation recovered to 0.0% (.08574/.08573/.08572 against a truth of .08573).
The null — no rotation in the truth — returns .000004 against a bar of
.008573, so the library invents nothing. Held-out endpoint RMS with the
library is .0028 of the incomplete law's. The largest curl-free contribution
is 8.2% of the rotation's and three of four are under .3%.

The statistic was flawed as well as the prediction. OBS7_IDENTIFIABLE asked
for the curl-free candidates' across-seed CV to exceed the rotation's by 5x
and "passed" at 15,408 — because a CV on a near-zero quantity is always
about one and cannot tell arbitrary from correctly zero. Both threshold and
prediction left standing and marked; OBS7_IRRELEVANT is the magnitude
statement G54(b) now rests on.

G54(c) measures what actually governs it, with no learner: least squares of
each candidate against the potential basis's own span over the sampled
square. rotation 1.0000, divergence .0967, shear .7355, drift x/y .7320. The
rotation's 1.0000 is Helmholtz confirmed to four places and is why recovery
was exact. But the curl-free candidates do not behave alike: being a
gradient is necessary and nowhere near sufficient, and what decides is
whether the candidate's potential is SMOOTH AT THE BASIS'S OWN SCALE. A
radial bowl is; a saddle needs a sign change at the centre that nine kernels
of sigma .22 on a .25 lattice are badly conditioned for, and a ramp needs
support past the lattice's edge. The gate asserts the split (one under .2,
one over .5) plus the correspondence, computed inside the same gate: the
candidate the basis absorbs most is the same one whose coefficient the fit
moves most. Divergence, both times.

Consequence, and it is a design rule for level 4: a library is well posed
exactly to the extent it lies outside the span of what is already being
learned, and law.degeneracy(k) is a 9x9 solve that says so BEFORE any
fitting. A candidate at .97 residual is worth adding; one at .10 will be
fitted arbitrarily and its coefficient is not a physical quantity — though
the model's predictions stay determined, which is §33's distinction with a
number attached.

Limits: the library contains the missing term, which is §27's stated scope.
One 2-D first-order flow, frozen potential basis, allocation deliberately
not adaptive so that operator recovery and capacity acquisition are measured
apart. Follow-up named in the pre-registration: sweep the basis and price
where level 3 stops working, with no learner in the loop.

Cost: G54 ~35 s. Not smoke.

## OBS-8 / G55 — a geometry of degeneracy, and three refutations

Christian's restatement of OBS-7 — an operator is inferable only to the
extent it contributes something linearly independent of the representational
span already available — with a correction to the closing sentence: not
"well posed" but LOCALLY IDENTIFIABLE UNDER THE CHOSEN SAMPLING MEASURE AND
BASIS. He was right, and by the end of this phase for a reason neither of us
had. Almost all of OBS-8 is least squares on a grid with no optimiser.

G55(a). The extension: residualise the whole library, Gtilde = (I-P)G, read
novelty off diag(H) and mutual identifiability off its spectrum. The raw
library is exactly orthogonal on the symmetric square (worst off-diagonal
4.5e-16, cond 1.0000) by E[dx]=E[dy]=E[dx*dy]=0 with E[dx^2]=E[dy^2], so the
pre-registration predicted every off-diagonal after residualisation would be
the basis's doing and asked for one above .02. REFUTED at 4.6e-15: the
coupling is <Pv_i, Pv_j>, a square lattice of isotropic kernels on a square
region is D4-invariant, P commutes with that group, and the five candidates
sit in different irreps (drift x/y sharing one, Schur making P a scalar).
The residualised Gram is diagonal EXACTLY at every basis on both sweeps.
Jitter the centres a quarter of a spacing and coupling appears at once:
worst off-diagonal .6990 (divergence-drift y), mutual collinearity 6.15. A
learned MARL basis is never symmetric, so the lattice is the special case.

G55(b). Axis A refines the lattice at fixed sigma/h; axis B adds rings at
OBS-7's own spacing and width. The predicted interaction (bowl by scale,
saddle by resolution, ramp by support) is REFUTED and axis A was the wrong
axis: holding sigma/h fixed while refining makes kernels NARROWER, and
narrow kernels over a small span are worse at a smooth global field, so
novelty RISES along it (shear .7125 -> .9929 at n=8). Resolution and
smoothness-scale are not one knob. Axis B is unambiguous: one ring takes the
saddle .7125 -> .0731 and the ramp .7083 -> .0722. Support is the mechanism;
the bowl was already absorbed at .0897 because its potential is concentrated
where the lattice already is.

G55(c). The pre-registration called the rotation's novelty an invariant.
REFUTED: on the square it falls to .918 once the lattice reaches the edge.
The Helmholtz argument drops a term that vanishes only on the whole plane —
integral grad(psi).V = boundary integral psi (V.n) - integral psi div V — and
a rotation is divergence-free, so the overlap with any potential is EXACTLY
the boundary integral. On a disc centred on the rotation's axis V is
tangential on the boundary, V.n is identically zero, and the term vanishes:
square 1.0000/.9253/.9181 against disc 1.0000/.9998/.9995 at equal area.
Same library, same kernels. Independence is a property of the REGION.

So novelty is a property of (operator, basis, region), all three. Absorbable
by support: divergence, shear, drift. Not absorbable given the right region:
rotation, but only because a disc's boundary is one of its streamlines.
Invisible on a symmetric fixture: mutual collinearity, which is what the
Gram was for and needs a learned basis to show.

Method notes. The disc was CLIPPED when sampled over the square's bounding
box — a disc with four chords cut off, whose boundary is partly straight and
where V.n is not zero, which is the one property it exists to have; it read
.9868 against a true disc's .9995. std.math.sign(0) is 0 and a correlation
matrix has a unit diagonal, so the Jacobi rotation angle was exactly zero
for every pair, the sweep did nothing, and cond_collinear returned 1.0000
for every matrix it was handed — including one carrying a .699 coupling,
which is what gave it away; the gate now asserts conditioning and
off-diagonals together. And degeneracy/analyse were two truths about one
quantity at two quadratures; degeneracy now delegates, and G54(c)'s numbers
move in the fourth decimal with its claims untouched.

Validation: G54 and G55 pass ReleaseSafe; smoke set clean. G55 ~10 s.

## OBS-9 / G56 — one residualisation, three faces

src/novelty.zig makes Christian's unification one operation: novelty(g; Phi,
mu) = ||(I-P)g||/||g||, with birth, operator inference and distillation as
the same call with different arguments. OBS-8's lesson is in the signature —
nothing computes an inner product without being handed the points. The
module knows nothing about MARL and MARL knows nothing about it.

G56(a). Leave-one-out is one Cholesky, not n solves: ||(I-P_-i)phi_i||^2 =
1/(G^-1)_ii, so novelty_i = 1/sqrt(G_ii (G^-1)_ii), and that product is the
VARIANCE INFLATION FACTOR — novelty is exactly 1/sqrt(VIF). Checked against
25 explicit re-solves at 7.44e-12. It first read 0.81 and the identity was
not at fault: 623 kernels against 512 probes, so rank(G) <= 512 and
everything is trivially redundant. You cannot ask about redundancy with
fewer observations than functions; the gate now asserts m > n.

G56(b). Rebuilt from law's basis and library inside the gate: all five
novelties reproduce to six decimal places, residualised Gram diagonal at
4.6e-15. Registered at 1e-9 and measured 5.95e-9 — a mis-derivation of
machine precision (two summation orders through a badly conditioned
projection), corrected to 1e-6 from the smallest gap between distinct
novelties (4.2e-3), and flagged rather than moved quietly.

G56(c). Median leave-one-out novelty on a learned MARL is .479 (min .252,
max .829) — substantially redundant, which does NOT contradict MARL-7 and is
why MARL-7 could not find a victim: representability and contribution are
different properties, and silencing measures the second. Gram condition 45.0
against OBS-8's exactly 1, so the mutual channel is live on a learned basis
as predicted; the registered 100 was a guess and is refuted.

The useful test failed and it is the best result. Batch pruning of the least
novel kernels, with a weight refit, scores .865 at a quarter and 1.303 at a
half — WORSE THAN RANDOM. Novelty was measured against the full basis, so
once one member of a mutually redundant cluster goes the rest are no longer
redundant; deleting the cluster entire removes what it collectively carried,
and random wins because it thins uniformly. MARL-18 inverted: four
mutually redundant kernels are individually removable and collectively
essential. Staging the identical rule (recompute every eighth of the
removals) gives .661 and .698, beating random at both and confirming the
staleness diagnosis. The registered halving is refuted for both arms.

So novelty is the right PER-ITEM quantity and the wrong BATCH criterion. A
batch criterion wants the GRAM — the spectrum says which SET is replaceable
where the diagonal says only which member is. Next phase, with a concrete
target rather than an intuition.

Not claimed: no default changes, birth is discussed and not rebuilt, and the
623-kernel measurement says nothing about the 47,000-kernel models of G52(b),
which would need MARL's locality exploited.

Validation: G56 (a/b/c) pass ReleaseSafe; smoke set clean. G56 ~25 s.

## OBS-10 / G57 — local rank reduction, and what geometry cannot decide

Christian's spec after OBS-9's batch failure: not "which diagonal entries are
small" but "how much dimension does this set add", with r_eff = exp(-sum p_i
ln p_i) over the cluster Gram's normalised eigenvalues sizing it. Local rank
reduction rather than pruning.

Precondition holds: mean r_eff/k across a learned model's regions is .673 —
379.4 effective dimensions over 623 members.

The predicted ordering (batch > random > staged >= spectral) is REFUTED on
its last step. The span-driven arm scores .826/1.054/1.062 at 25/50/75%
pruned — behind RANDOM at half and three quarters, let alone staged's
.661/.698/.866. There is no crossover; it loses everywhere.

And it is the criterion, not the clustering. Regions are a lattice partition
and a kernel's reach is a whole region edge, so the obvious suspect was
cross-face overlap. Taking the clustering out entirely — pivoted QR over the
whole basis — gives 1.094/1.081/.987 and does not help. Pivoted QR selects a
well-conditioned SPANNING subset, optimal for reconstructing an arbitrary
function in the span; a model has ONE target, and a geometrically
distinctive kernel sitting where the field is flat displaces one the model
leans on. This is OBS-9's own registered escape hatch arriving.

selectExplaining differs from selectSpanning in the score alone — the drop
in the target's residual energy, which is orthogonal matching pursuit. It
beats staged by 2.1x at every fraction (.486/.470/.476 of staged's excess),
and at three quarters pruned reaches RMS .0707 keeping 156 of 623 kernels,
against random's .1019 and the full basis's .0489.

    the spectrum sizes the set; the TARGET chooses the members

Both halves are needed and answer different questions. r_eff says how many
degrees of freedom a cluster deserves; the target says which members carry
them. Sizing is not selecting, and the phase's failure was assuming one
operation could do both.

Work went as locality predicted, enormously: target-driven selection is
39/32/21 ms against the staged diagonal's 2671/1998/1500 — 68x cheaper AND
better on every axis. Staged factorises the whole basis per stage; the
clustered methods factorise each region, block-diagonal by construction.

G57(b): OBS9_SAME_PRIMITIVE, frozen at 1e-6 after its post-hoc correction,
validated on a basis G56 never saw (OBS-8's axis-B 5x5 on [0,1]) at 1.67e-7,
with no further adjustment. Christian's condition for accepting the move.

So the pattern gains a clause: individuals live on the diagonal,
representations live in the spectrum, and THE OBJECTIVE LIVES IN NEITHER.
Geometry tells you the shape of the redundancy and cannot tell you which of
two equally redundant members to keep. A consolidation rule wants novelty to
rank, r_eff to budget, and the target to select.

Not claimed: representatives are SELECTED, never synthesised — turning "keep
2 of 8" into "make 2 new ones" is MARL-14's distillation and is deliberately
separate. Cross-region overlap is shown not to matter for the criterion and
is untested for the budgeting.

Validation: G57 and G57(b) pass ReleaseSafe; smoke set clean. G57 ~40 s.

## OBS-11 / G58 — synthesis, and where sleep stops being a metaphor

src/consolidate.zig builds Christian's third stage: budget from r_eff,
members from the target-conditioned residual, and then the chosen kernels
are allowed to MOVE — every parameter, through marl.gradOne, so the result
stays in MARL's family. Warm-started from OBS-10's winner on purpose, so the
comparison is exactly selection against selection-then-refinement.

Two corrections before the measurement meant anything. The descent first won
by LEAVING THE FAMILY: sigma was bounded per axis but the ellipsoid's
infinity-norm reach was not, so 359 of 468 kernels outgrew the gather and
the arm read a thirty-fold win. The registered null caught it and
marl.Model.clamp's reach projection fixed it (0 over reach thereafter). It
was then scored on the probes it was FITTED ON, which flatters synthesis
enormously because the baseline only gets a weight refit there: train
.00227 against held-out .05376. Two disjoint probe sets now.

Held out: syn/sel is .887/.850/.893 at a quarter, a half and three quarters
pruned. The registered .80 is REFUTED — synthesis buys 11-15%, not 20% —
but the direction holds at every fraction.

The threshold HELD and at half rather than a quarter: distilled 468 kernels
.053762 and 311 kernels .053951 against the FULL 623's .057213, all held
out. A consolidated basis is strictly better than the overcomplete one it
was built from, on data neither saw, at half the kernels. Consolidation
improves basis QUALITY, not merely reduces basis SIZE.

The conditional did not separate. spread = 1 - E_sel/E_opt was registered to
give the top third at least 2x the gain of the bottom; measured 1.24x —
right sign, nowhere near the margin. Spread is small on this fixture
(.003-.117) and probes are attributed to clusters by owning region, which is
crude where supports cross faces. Untested at adequate contrast rather than
refuted; a fixture with deliberately clustered redundancy would test it.

Honest limit: synthesis at 468 kernels has 4,680 free parameters against
4,096 fit probes — more parameters than points — and overfits hard. The
11-15% is what survives that. Headroom in more probes or a regulariser, and
equally the possibility that a better-posed fit changes the ranking.

Myopia recorded and not addressed: the objective is one static target, and
widening it to a replay measure or a recent-window residual is the next
axis, deliberately not taken so synthesis is measured before the objective
is generalised.

Validation: G58 passes ReleaseSafe; smoke set clean. G58 ~50 s.

## OBS-12 / G59 (a) — the conditional, and a fixture outside the family

Christian's framing adopted: consolidation with representational improvement,
not distillation. Four clusters of eight, equal target energy, disjoint parts
of the cube, budget three of eight, held-out scored, differing only in
internal geometry.

A registered disagreement, and the agent lost it. Christian predicted the
gain monotone in redundancy; the agent predicted a peak in the middle.
Measured, across the three clusters differing only in spacing: .3039, .8398,
.9327 as r_eff/k falls .9366, .3521, .1368. MONOTONE. The agent's error:
near-duplicates let a single MOVED kernel stand for the whole cluster, and
there is nothing to lose by moving it — "already solved by selection"
confused "one member is nearly the cluster" with "one member AT ITS CURRENT
POSITION is nearly the cluster". OBS12_ORTHOGONAL (.10) is refuted at .304 by
the same mistake one step earlier: the argument assumed budget = cardinality,
where the budget is three of eight and five members are dropped outright.

And a fixture bug that looked exactly like a diverging optimiser. The
anisotropic cluster first scored -8.04, train rising .129 -> .786. Three
diagnoses ran before the right one: which parameter group (even weight-only
diverged, .203 -> .280); the off-diagonal units (gradOne returns the raw
gradient where marl.zig's own step scales off-diagonals by l_ii*l_jj — the
fix is correct and changed almost nothing); and the schedule per OBS-5 (rate
.01/.001/.0001 x warmup 100/1 all landed within 5% of each other).

That last table is the tell: a change that does not care about the learning
rate does not come from the gradient. The anisotropic members were built
with off-diagonals up to 1/sigma and a long axis three times the nominal
width, putting their cutoff box past one region edge — so the clamp
corrected them on the first step, before any gradient, and the target had
been computed from the unclamped kernels. `project` is now shared by the
descent and the fixture builders so a cluster cannot be built from kernels
MARL would never hold. The anisotropic arm then converges (.245 -> .132,
gain .213) and is reported beside the others rather than ordered against
them, differing in kind rather than in spacing.

Settled: synthesis gain rises monotonically with cluster redundancy, so
r_eff is not only the budget estimator but a predictor of where consolidation
is worth spending compute.

Not reached this session: the conditioning matrix (probes x regularisation,
to tell variance-limited from underconstrained). Registered in
obs12_predict §(4); Options.prox is built and unused, G58 unchanged at
prox = 0. Also registered and untested: the two-phase reading, that the
overcomplete model may be the better LEARNING representation while the
consolidated one is the better INFERENCE representation.

Validation: G59 (a) passes ReleaseSafe; G58 unmoved; smoke set clean. ~30 s.

## OBS-13 / G60 — wake: scaffolding or clutter?

Same parent, its consolidated child at half the population, the same new
stream, equal work, births on under identical policy, new regime =
shift {0,-0.10,0} (the campaign's own modest move). The child is
consolidated against the PARENT'S OWN PREDICTIONS, not the truth — sleep
reorganises what a model has, and a child handed the truth would start
knowing what its parent had to learn.

A second registered disagreement, and both parties were right at different
horizons. Child ahead through 20k (.07138 vs .07396); parent clearly ahead
by 60k (.04793 vs .05726, child/parent 1.195).

The mechanism, measured rather than inferred. The child ends with MORE
kernels than the parent (815 vs 773) and is 19% worse, having bought 504
births against 150 and regrown to 1.054x the parent's size. Mean updates
per kernel: parent 1551, child 1024. The child's population is younger and
less trained because it had to re-acquire what the parent still held.
MARL-1's invariant, and here the consolidation itself created the
untrainable capacity by discarding trained structure the moved world still
needed. The child regrew to the parent's size and did not recover its
accuracy: regrowing the count does not regrow the training, which is
MARL-9's law read from the other side.

Settles: redundancy is scaffolding on this move, and the advantage is LATE —
invisible at 20k, clear at 60k. An adaptation comparison truncated early
would have concluded the opposite; recorded as a methodological warning.

Does not settle: whether the cycle is a ratchet. Christian's strongest
outcome — parent faster, child better after a SECOND sleep — is untested and
deliberately so, one cycle first.

Points at two fixes, neither built. Consolidation should preserve TRAINING
STATE and not only structure: a synthesised kernel arrives with updates = 0
and Adam's moments cleared, where a fairer child would inherit an effective
update count from the ancestors it replaced. And this is the myopia OBS-11
recorded — the consolidation optimised the parent's output under the OLD
measure, and the moved world needed structure that measure called redundant,
which is what a replay measure exists for.

Validation: G60 passes ReleaseSafe; smoke set clean. G60 ~90 s.

## OBS-14 / G61 — the lineage, and a correction to OBS-13

A design error found before any code, and it changes OBS-13's result.
OBS-13 consolidated the child against the PARENT'S OWN PREDICTIONS so it
would not start life knowing what its parent had to learn — right about the
cheating, wrong about the consequence, and visible only once sleep runs
twice. A student fitting its teacher's output can at best match it, and
MARL-19 measured that directly: on a noiseless field a sleep is a pure loss.
A lineage built on sleep-on-self can only decay. OBS-11 improved on its
basis because its target was the truth on probes — which is not cheating
either, once named: the truth on probes is what a REPLAY BUFFER holds.

Measured, held out on probes neither arm saw: sleep-on-self .06926 -> .07005
(1.011x, no gain); sleep-on-replay .06926 -> .05920 (.855x) at half the
kernels.

And that reverses OBS-13's headline. Child/parent after a 60k wake was 1.195
with self-sleep and is .9391 with replay-sleep — the consolidated child now
WINS the wake rather than losing it. OBS-13's "redundancy is scaffolding"
was an artefact of the wrong sleep target. What survives is the mechanism it
measured: a child whose kernels arrive with updates = 0 pays for youth.

The lineage, held out against the moved truth:
  gen 0 post-sleep  P 631 .13382 upd 0     C 315 .12867 upd 0     C/P .9615
  gen 1 post-wake   P 768 .05326 upd 1241  C 791 .05002 upd 1031  C/P .9391
  gen 2 post-sleep  P 383 .05884 upd 0     C 396 .06054 upd 0     C/P 1.0288

Not a ratchet on this run: the child leads after the first sleep and through
the wake, and loses at the second sleep. But the reading is qualified —
the SECOND SLEEP HURT BOTH lineages where the first helped, and the
difference is what was slept on. Gen 0 halved a population converged over
20k; gen 2 halved one that had just birthed heavily during a wake with
updates spread very unevenly. The damage may be about sleeping too soon
after a wake rather than about lineage decay, which is a distinct hypothesis
with an obvious test (vary wake length before the second sleep) and is not
run here. Calling it damage accumulation without that would overclaim.

Method note, third occurrence: the first draft scored the sleep-target
contrast on the replay ring it was FITTED on and read a fourteen-fold
"improvement". Everything is held out now. And each model sleeps against ITS
OWN ring — sharing one hands the child the parent's experience, which is the
thing a lineage exists to keep apart.

Validation: G61 passes ReleaseSafe; smoke set clean. G61 ~120 s.

## OBS-15 / G62 — the consolidation window is evidence, not maturity

G62(a) promotes the fit/eval separation from ledger note to plumbing after
its third occurrence (OBS-11's synthesis arm, OBS-14's sleep contrast,
OBS-8's clipped disc). `Measures` names fit, sleep and eval explicitly and
refuses to run if any two share a point; the gate asserts it fires on a
deliberate alias.

G62(b) tests Christian's maturity hypothesis and REFUTES it. One wake from a
common parent on a moved world, a fork consolidated at each of six
checkpoints, same model, same stream, same sleep, same budget. Correlation
between contribution-weighted readiness and post-sleep gain is -0.72 — the
wrong sign — and readiness never varied, sitting at .98-.999 across the
whole sweep. The better the model going in, the more the sleep hurt it:
gain +.1594 at 2k falling to -.5594 at 80k.

The `after` column says why: post-sleep RMS is roughly FLAT at .067-.101
however good the model was, while `before` runs .106 down to .048. The sleep
imposes a ceiling and the gain is positive only where the model was already
worse than it. Half of 781 kernels is 390 at ten parameters each — 3,900
free parameters fitted against a 2,048-point ring.

Widening the ring at the last checkpoint, same model and same budget:
  2048 points   0.53 per param   after .07478   gain -.5594
  8192 points   2.10 per param   after .04545   gain +.0523
 32768 points   8.40 per param   after .02186   gain +.5442

So there IS a consolidation window and it is set by EVIDENCE PER PARAMETER.
At eight points per parameter consolidation more than halves the held-out
error at half the kernels; at half a point per parameter it destroys the
model.

Reframes three earlier readings. OBS-14's second sleep was not lineage
damage and not immaturity — a 2,048-point ring against a ~390-kernel budget
is squarely in the destructive regime, so the ratchet question was never
fairly asked. OBS-11's "honest limit" (4,680 params against 4,096 probes,
.87 per param) sat there too and still showed 11-15%, so its gain was real
and badly under-measured. And G56(a) found the same principle one level
down — you cannot ask about redundancy with fewer samples than functions —
which makes this its second sighting, per parameter rather than per function.

Policy: do not sleep until the replay carries at least a few observations
per free parameter you intend to keep. Budget and ring size are one decision,
not two: r_eff says how many kernels to keep, the ring says how many can be
afforded.

Still owed: maturity is refuted AT THIS RING SIZE and untested at an
adequate one; the ratchet test needs a properly sized ring; effective-age
inheritance is unaffected; replay weighting is now the natural next question,
since this phase says only that the ring must be big, not what is in it.

Validation: G62 (a) and (b) pass ReleaseSafe; smoke set clean. G62 ~5 min.

## OBS-16 / G63 — evidence absorbs maturity, and the rule holds cell by cell

Christian's correction to OBS-15: maturity was never refuted in general, it
was non-discriminating under an evidence-starved fit. So a grid, with the
budget held FIXED at 200 kernels in every cell and the ring sized by his own
rule N = rho*p*k, so rho is the only thing moving along that axis.

  maturity  kernels  R1024  fresh   before    rho0.5   rho2.0   rho8.0
  young         641   .035   .016   .10915    -.3875   +.0858   +.1111
  mid           701   .601   .102   .07529    -.7670   -.0232   +.4619
  settled       775   .873   .133   .05213   -3.3564   -.4356   +.3340

rho is monotone in every row. And the maturity spread of the gain runs
2.969 / .521 / .351 across the rho columns — EVIDENCE ABSORBS MATURITY, an
interaction rather than a main effect. The registered disagreement goes to
the agent, and the mechanism is why it was worth registering: consolidation
does not merely select, it REFINES, and refinement is what fixes a badly
placed kernel, so ample evidence repairs a young population.

The maturity measure now works: R1024 reads .035/.601/.873 where OBS-15's
R64 saturated at .98-.999, and freshShare (contribution from kernels born
since the move) tracks it. At rho .5 a BETTER model loses MORE
(-.39/-.77/-3.36), which is OBS-15's ceiling from the other side. At
adequate evidence the MID model gains most (.462) — the young one has less
accumulated redundancy to exploit, the settled one less headroom. Neither
was predicted.

The rule validates cell by cell. At rho_min = 2 with p = 10 and 200 kept:
  rho 0.5   1,000 points permit  50   kept 200, 4x over    ALL NEGATIVE
  rho 2.0   4,000 points permit 200   kept 200, exactly at MIXED
  rho 8.0  16,000 points permit 800   kept 200, 4x inside  ALL POSITIVE
It predicts the sign of every cell, and the middle row is the correction:
rho_min = 2 is the BOUNDARY, not a safe floor. A working policy wants 4+.

evidenceBudget(n, rho_min, p) is the deliverable. The spectrum proposes the
budget; the evidence permits it.

The law at two scales — G56(a) "you cannot ask about redundancy with fewer
samples than functions", OBS-15/16 "you cannot synthesise a parameterisation
with fewer observations than it has parameters" — generalises to:
representational questions are only meaningful relative to the rank and
density of the evidence supporting them.

Still owed: rho is varied by ring size at fixed budget and never by budget
at fixed ring, so nothing yet says what happens when the SPECTRUM asks for
more than the evidence permits, which is the rule's actual use case. The
ratchet test is now runnable fairly at fixed points-per-parameter per
generation. Replay composition is untouched. Effective-age inheritance has
moved down the causal order.

Validation: G63 passes ReleaseSafe; smoke set clean. G63 ~4 min.

## OBS-17 / G64 — rho is not a control law, and two phases need re-reading

Christian's policy test: OBS-15 and OBS-16 moved rho by changing N, never k,
so evidenceBudget had never been tested on the quantity it returns. Hold the
ring fixed, sweep the budget, and see whether the sign transition lands at
the same rho.

It does not. Reaching the same rho from opposite directions gives opposite
signs: at rho 2 the small ring (k=102) scores -.4121 and the large (k=410)
+.3239; at rho 4, -.6692 against +.0651. Only the rho-8 pair agrees, and
both are negative there.

Within a ring, gain RISES with k — less compression is better, monotone over
five budgets. At matched k, gain RISES with N — more evidence is better,
monotone over all five. Both true, and they move rho in opposite directions,
which is exactly why the ratio cannot govern.

So OBS-15 and OBS-16 measured N and called it rho: both held k fixed or
nearly so while varying the ring, and OBS-16's grid held k at exactly 200,
making rho proportional to N inside it. Its "the rule predicts every cell"
was a statement about evidence alone.

evidenceBudget is REFUTED as a control law — you cannot choose k from N,
because shrinking k to satisfy a ratio makes the outcome worse. It stays in
the tree as a description of one axis, with that written on it.

What survives is the useful half: at a given replay size there is a maximum
COMPRESSION beyond which sleep hurts, near k = 150 of 703 at 8,192 points.
Evidence does not licence more compression; it reduces what compression
costs. The best cell in the table is the least compression at the most
evidence, which is the opposite of a ratio rule's recommendation.

The registered caution at obs17_predict §(3) turned out to be the whole
story rather than an edge case: a smaller k is not merely a better
conditioned fit, it is also a harsher compression, and rho captures only the
first. What was predicted as a turnover at high rho is monotone against rho
throughout.

Corrected picture: gain ~ f(N) + g(k), roughly additive on this data — four
times the ring buys +.29 to +.54 at every budget tried. Two knobs, not one.
And Christian's architectural sentence inverts: a small replay buffer does
not upper-bound the complexity sleep may produce, it places a LOWER bound on
the complexity sleep may safely keep.

Still owed: the ratchet test now needs fixed N and fixed k rather than fixed
rho, which is simpler. Replay composition is untouched and is now the most
interesting remaining question, since N is established as dominant and
nothing says what should be in it. Effective-age inheritance is unaffected.

Validation: G64 passes ReleaseSafe; smoke set clean. G64 ~4 min.

## OBS-18 / G65 — what does a replay policy actually choose?

Christian's queue item 1: equal N, equal k, same optimiser, differing only in
the measure. One model, one exemplar stream, four admission rules offered
every observation — recent (a ring), uniform (A-Res reservoir w=1), error
(w=surprise), uncovered (w = 1 - cover). Weighted reservoir sampling at equal
weights IS uniform reservoir sampling, so three of the four differ in one
expression. All four decide at observation time, so none is cheating on cost.
`Event.cover` added: the continuous coverage computed since MARL-0 and thrown
away since MARL-0, because a rule built on the boolean would be built on a
threshold belonging to a different decision.

TWO EXPERIMENTS, complementary, both kept. AS A POLICY each rule carries its
own labels — a rule over a non-stationary stream chooses WHEN to observe as
well as where, and that is part of the policy rather than a confound in it.
AS A LOCATION every label is re-read from the current world, which needs an
oracle call per point and is therefore a probe, not something deployable. An
earlier draft called the relabelled version "the only way to run the
experiment that was specified"; Astra's review corrected that.

Registered composition held. Recent's stale share exactly 0.000, uniform's
0.487 inside a tolerance derived from the fixture's own contested fraction
(0.0950 of the cube, ~778 contested points, binomial sd 0.0179), error
concentrating 3.15x on contested ground against a floor of 2.5.

Registered mechanism REFUTED. `reached` is 1.000 in every arm: no unreached
ground, because a Gaussian basis holds down its own leakage — 33 of 692
kernels centred past the window where the target is exactly zero, and `mu0`
says 33 were BORN there rather than drifting out. So the ROW-COUNT form of
effective evidence has nothing to vary; conditioning and uneven information
across parameters are untouched and stay open. Amends MARL-16: "zero is what
an empty model already predicts" is true of an EMPTY model, false of a
populated one.

CONTRACT FAILURES, all found by Astra in review and none by the gate.
(1) The arms did not have equal k. sleepOn rounded each region's share
independently — 345 to 347 against a budget of 346 — while the header printed
346. `allocate` is the fix: largest-remainder at exact=true, incumbent bit
for bit at exact=false so G62 (b), G63 and G64 keep reproducing. G64 re-run
and matches its recorded table cell for cell. The gate asserts the delivered
population rather than printing the requested one.
(2) Reporting only "A re-fit" (after 20,000 further observations) HID the
policy table's own retention trade, because relearning washes out what a
sleep preserved. "A held" is now its own column and it reverses the ordering:
error preserves A at .09117 against the ring's .13026. Historical
observations really do preserve more of the old world, which an earlier
reading of this same run denied.
(3) The replication floor was one gap from two uniform arms and was then
applied to comparisons involving the error rule. Now three uniform arms and
two error arms, per-rule spreads reported SEPARATELY because pooling assumes
the rules vary alike. And a margin printed as "3.07x the spread" SIZES a
difference over a handful of draws; it does not certify one.

THE PARETO SURFACE IS IN THE POLICY TABLE — the one an earlier draft called
confounded. Two rules win two axes and both clear their own rule's observed
spread: the ring takes the world being evaluated (immediate, 18.55x), the
error-weighted buffer preserves the one before it (A held, 1.93x). Christian's
registered expectation against the agent's predicted sweep; Christian.

AND THE ERROR REPLICATE OVERTURNED THE FIRST READING OF THE LOCATION TABLE.
With a floor measured on the uniform rule alone, error looked like it won the
sleep and came last on both adaptation axes by 13.5x and 8.4x. Its own two
relabelled arms differ by .04007 on A re-fit, comparable to the widest gap
between any two rules — so those margins were one rule's variability applied
to another. With error replicated they collapse to .07x and .01x. In the
location table only the immediate axis has a UNIQUELY SEPARATED LEADER
(error by 3.07x, replicated at +.6399 and +.6529); A held, A re-fit and C are
asserted as negatives because that is exactly where the first version read a
trade that was not there.

AND THAT NEGATIVE IS ABOUT THE LEADER, NOT THE FIELD — a third interpretation
bug, also Astra's. `judge` compares the leader to its NEAREST rival, so two
nearly tied leaders hide every difference behind them, and an earlier draft
printed "NOTHING else separates" off exactly that test. Counting PAIRS
separated by more than each table's own spread: A held is 5/6 policy and 4/6
location (widest recent/uncovered .00591 against a spread of .00345). So
relabelled buffers do not all behave alike. The gate now reports pairs and
leaders apart and asserts both.

RETENTION IS CARRIED BY THE LABELS, NOT THE LOCATIONS. Refreshing labels
worsens A retention in every tested reservoir, by more than the spread —
error .09117 -> .13467, uniform .11437 -> .13114, uncovered .11283 -> .13617
— clustering near the ring's .13026 and the un-slept control's .13111, with
their leaders unseparated by this phase's criterion though four of six pairs
are. The best retention anywhere belongs to a STALE buffer.

What a relabelled buffer loses is NOT evidence about the old world. Only
.0950 of this cube is contested, so over nine tenths of it a world-B
observation IS a world-A observation; what it loses is its A-SPECIFIC labels
on the tenth where the worlds disagree. The fixture statistic the phase
opened with turns out to be the mechanism.

  a replay buffer's LOCATIONS decide how well it fits the world it is
  labelled for; its LABELS decide which world that is

That is a SUMMARY and not a demonstrated separation: nothing here shows the
two effects are independent, and they have every reason to interact, since
the error rule's locations are chosen by a residual measured under particular
labels. Not to be cited as a factorisation.

Label validity is relative to the world being evaluated, not absolute. Error
weighting is importance sampling by the back door: the best allocation for
fitting the world its labels describe. The agent's "every parameter needs its
share" was the right shape and the wrong conclusion — the shares that matter
are not equal ones.

The control re-fits A for 41 births against every child's 355-440 — capacity,
not wall clock and not adaptation speed, neither of which this gate measures.

Still owed: windowed error replay, to be pre-registered as a TRADEOFF
hypothesis rather than an improvement one — can it improve current-world
fitting without giving up too much prior-world retention? Both halves
measured. It is a hypothesis, not a policy that follows.
A recency window can straddle a regime change — the ring is label-consistent
here only because 20,000 B observations flushed all 8,192 slots, which is the
fixture's timing and not a property of rings. Restricting error-weighting to
recent observations changes the distribution it draws from, since its
surprise values were recorded across both worlds. And a weighted sliding
window has storage and bookkeeping costs nothing here has priced. Needs
matched recent/uniform controls, observations placed AROUND the transition,
and replication of the error policy itself — which this phase has just shown
is not optional.

Validation: G65 passes ReleaseSafe; G64 re-run unchanged after the allocator
refactor; smoke set clean. G65 is the campaign's largest gate — thirteen
sleeps and twenty-eight adaptation runs, ~7 min 30 s.

OBS-19 / G66 — a recency window is an exchange rate, and a price can be paid

The queue item OBS-18 left: can windowed error replay improve current-world
fitting without giving up too much prior-world retention? Registered as a
TRADEOFF, both halves measured. tools/obs19_predict.py froze the numbers.

AS A POLICY it does not, on this fixture — the ring wins the current world at
M/N = 2.0 by 9.25x windowed error's spread and 4.14x windowed uniform's (both
on FIRST DRAWS; on replicate means the uniform comparison is ~3.64x against
the same observed spread). But the LOCATIONS were never the problem, and the
first draft of this entry had the reason wrong.

ASTRA'S SAME-POINTS REFRESH CONTROL is the intervention the claim needed; the
wrong-label count is descriptive and establishes nothing causal alone. Same
parent, same locations, same keep count, same selection/refit/refinement,
only the labels re-read from the world being evaluated (an oracle per point,
so a probe and not a policy):

  uni@tau  .06238 -> .04999   uni@tau' .05855 -> .05195
  err@tau  .06475 -> .02866   err@tau' .06672 -> .03004     ring .04650

CHANGING LABELS ALONE REVERSES THE RANKING in both tested draws: .02866 and
.03004 against the ring's .04650, which is 38% and 35% LOWER error on the
current world. Lead with the absolute figures, not the gap-closed percentages
(198%/181% for the error draws): those are correct but depend on each arm's
original deficit (Astra). Bounded to the intervention, this establishes that
HISTORICAL LABELS CAUSE SUBSTANTIAL CURRENT-WORLD LOSS through this pipeline;
it does NOT show locations and labels act independently, since a label change
moves selection, linear refit and non-linear refinement alike. The uniform
draws close ~78% and ~55% of their gap and do NOT reach the ring, so their
residual deficit is not labels alone and leaves room for a location effect.
Refreshing COSTS the error arms their retention (.12486 -> .13479, .12112 ->
.13512): OBS-18's finding reproduced, retention is carried by labels. Four
post-hoc interventions on one parent and one stream; they do not isolate the
above-threshold labels from smaller discrepancies, nor separate selection,
linear refit and non-linear refinement.

THE MECHANISM, corrected. An EXPONENTIAL price CAN BE PAID: whatever survives
the window had to outbid it, and what outbids it is adversely selected.
`old` counts pre-move slots, but only .095 of this cube is contested, so the
quantity that matters is contested AND stale. stale against old: recent
.000/.000, uniform .648/.659, error .617/.639, uni@tau .045/.036 all track;
err@tau .161/.076, a gap of +.085 replicated at +.082. It is NOT that the
rule discovers after the move that an old sample is wrong — ADMISSION
SURPRISE IS FROZEN AT OBSERVATION TIME and nothing reprioritises an old entry
(Astra). A-era surprise already concentrates on the structure the worlds will
LATER disagree about, because the contested band is the shell and the shell
is where the residual always lived. At the same tau err@tau carries 276 wrong
labels and uni@tau 37; among wrong labels the mean absolute discrepancy is
.324 and .393, and total squared discrepancy is 4.4% and 23.0% of the squared
B signal on each buffer's own points. ("Wrong by most of the shell amplitude"
was an overstatement: the max is .899, the typical value a third of that.)

A HARD cutoff cannot be bought past at any weight. It is a different object,
it is UNTESTED, and NO IMPOSSIBILITY OF SYNTHESIS IS ESTABLISHED. That is the
named next experiment.

A window costs LOW, not zero. No expiry queue, no periodic scan, no second
heap — a real result about EXPONENTIAL WEIGHTING and not a costing of a hard
sliding window. It adds arithmetic per admission and `Replay.t` is 8 bytes a
slot, 64 KiB at N = 8192, read only by diagnostics. tau is an E-FOLDING time,
not a half-life; the half-life is tau*ln2 = 2839 (Astra).

Held as a LOG MAGNITUDE, K = -log(-ln u) + log w + t/tau. Written directly,
exp(-t/tau) underflows past t/tau = 745 and an A-Res key is NEGATIVE, so the
factor gives -0.0, which sorts ABOVE every live key: the oldest exemplars
become unevictable. The rule does not break, it INVERTS. Clamping the
exponent was rejected BEFORE ANY MEASUREMENT — it trades inversion for
SATURATION, the window becoming a uniform reservoir over the clamped tail.
G66 (a) is the mutation, tau = 4 over 5000 offers; the clamped form fails at
an oldest survivor of 2874, which is 700*tau to three figures. In the smoke
set. `Replay.t` is written by every rule and READ BY NONE — `admit` decides
from the index in hand — so it cannot move a selection; tau = 0 is the
incumbent arithmetic and G61/G65 reproduce.

TWO SLEEPS IN ONE LIFE, M/N = 0.5 and 2.0, because OBS-18 slept 20,000 clear
of the move and its ring was clean BY THE FIXTURE'S TIMING. Nine arms: a 2x2
of measure x window, each replicated, plus the ring — which needs no
replicate and that is not an omission, it is deterministic in the stream.

AT M/N = 0.5 EVERY ARM LOSES: the un-slept model at .10270 beats its best
child at .12352. A sibling of k_min — there is a t_min. The MECHANISM is NOT
isolated: the counting argument establishes unavoidable OLD MEMBERSHIP when
M < N, not unavoidable DAMAGING LABELS nor destructive consolidation, and the
model is also less converged (before .10270 against .08002) with a different
budget (343 against 367). Retention goes the other way — error replay takes A
from the control's .12504 to .05224 — and the ring is WORST at retention,
worse than not sleeping.

NOT REFUTED: the measure. At MATCHED staleness (.639 vs .659) error beats
uniform on BOTH axes, 4.10x and 3.29x. Ordering five rules by staleness is
NOT a monotone trade — unbounded error beats unbounded uniform on both — and
one tau is one point, so "an exchange rate interpolates" is a hypothesis for
a tau sweep, not a result.

Four of eight registered predictions refuted (P4, P5, P7, P8); thresholds
left standing and marked. P8's NUMERICAL prediction failed and its mechanism
is UNRESOLVED — the offsets differ in parent, convergence, replay contents,
normalisation denominator and kept budget, five confounds at once, so no
replacement is claimed. An earlier draft argued the EARLY margins were small
BECAUSE every gain there is negative; that is not a bound on a pairwise lead
and is withdrawn. The enrichment values 2.0901 and 2.0864 round alike but two
checkpoints establish neither a ceiling nor independence from timing.

OBS19_WINDOW_OLD was derived on the UNIFORM rule (the predictor can only
simulate w = 1) and is asserted THERE ALONE — err@tau reads .076 against the
.05 ceiling, and that excess IS the finding. Spending one rule's number on
another is this campaign's standing mistake.

The A re-fit axis is EXPLORATORY and gets no pairwise ranking: there is no
unslept reacquisition baseline, so a highlighted comparison would read as a
claim the gate cannot support. Raw column and per-rule spreads stay.

THE FINDING AS RECORDED: at the tested decay scale and checkpoints,
exponential error-weighted replay retains more prior-world information and
sacrifices current-world fit relative to the ring. Same-points refresh
controls show that historical labels cause substantial current-world loss,
while the error-selected locations remain effective when supplied current
labels. Hard-window synthesis remains untested.

Three process notes, all mine. A python edit and a ten-minute run were chained
into one backgrounded command and the edit's output never checked — the pkill
in the same command matched its own wrapper and killed the job, so a full run
executed against an unmodified gate. The first draft asserted inside the
offset loop, so the first refutation threw away the offset it had not reached.
And the first write-up claimed "the synthesis does not exist" from a result
that only tested one of the two window shapes.

Owed, and Astra's specification is well posed as it stands: A HARD CUTOFF,
ERROR-WEIGHTED SELECTION WITHIN ITS ELIGIBLE POOL, MATCHED UNIFORM SELECTION,
REPLICATED POLICIES. Its key contract: IDENTICAL ELIGIBLE OBSERVATIONS for
both selections, the cutoff preventing EITHER rule from retaining an expired
sample — a test of selection-within-eligibility rather than another
comparison of two different pools. Then a tau sweep; a t_min swept at a FIXED model state;
a windowed measure NOT correlated with the regime change (uncovered).

Validation: G66 passes ReleaseSafe in 12:43 — twenty-two sleeps, almost all
of the gate, each ~30 s and almost entirely the 400-step descent over 8192
replay points. The validated numerical log is g66d; PRINT STRINGS ONLY were
edited after it (the refuted-summary wording, a column header, and leading the
refresh line with absolute RMS rather than gap-closed), verified by
compilation and NOT re-run. CODEX's own rule — reuse passing checks of
unchanged code — and Astra's instruction: do not spend 12:43 on two print
strings. No assertion, arithmetic or control flow changed. G66 (a) in the smoke set. G65 re-run reproduces its recorded table
cell for cell; G61 clean in Debug. Astra's audit reproduced the parent,
stream and seeds independently without touching the working tree.
