# Implementation notes — the ledger

**Status:** Phase 1 built, 2026-09-06: P1.1–P1.7, G1–G8 green and bitten.
Phase 2 opened the same evening: the first loam-grown thing on screen
(matryoshka branch `loam`, "Renderer integration, beat 1" below).
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
| Reconstruction bases per channel (D4) | `Brick.trilinear` is the one path | measure before choosing |
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
With 16 threads apply, finalize and the seam pass all go parallel;
ReleaseFast at 200 steps: 0.75 ms per step against 2.12 serial, the
scene build 30 ms against 237.
