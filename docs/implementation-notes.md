# Implementation notes — the ledger

**Status:** Phase 1 built, 2026-09-06: P1.1–P1.7, G1–G8 green and bitten.
**P2.1a built Sunday 2026-09-06, afternoon** — attention: derived from
each brick's last change, in the summaries and the hash, ordering the
step under a budget; G14 green and bitten, G1 re-baselined ("P2.1a —
attention" below); RULED the same afternoon — "Attention and obligation
are different things" (the entry of that name); then R17, the
residual, built the same afternoon: deferral costs, G14 (e) read its
prediction exactly ("R17 — the residual, built").
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
`blockPoint`. Not done: the day's frozen reference has moved four times
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

## Measurements (regime stated)

Sapling, seed 7, 3652 bricks, Ryzen 9950X3D, serial:

| build | scene build | step (≈30 changed bricks) | 46-gate suite |
|---|---|---|---|
| Debug | 2.0 s | 15 ms | ~2 min |
| ReleaseFast | 0.38 s | 1.9 ms | ~20 s |

Per phase at step 40 (Debug, serial): operate 0.02, fronts 0.24, apply
1.3, frontier 1.5, seams 9.0, finalize 6.0, build 1.2, publish 1.5 ms.

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
