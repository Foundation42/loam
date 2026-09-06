# Implementation notes — the ledger

**Status:** Phase 1 built, 2026-09-06: P1.1–P1.7, G1–G8 green and bitten.
Every threshold PROPOSED (brief §2, `src/thresholds.zig`); every ruling
below proposed against the code and standing until Christian strikes it.

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
  measured value beside each in the gate table below. G3's proposed
  floor (4 units, doubled for the ±stimulus pair) sits close to the
  measured 9.5 on the sapling scene; the others have headroom.
- **§8.3 Front ownership:** a global id-ordered list on the world, each
  front carrying the key of the brick under it. G4's "regions touched"
  is measured on bricks, by pointer identity against the pre-wound
  snapshot, which needs no front ownership at all.
- **§8.4 Growth potential:** a field channel fronts consume (R1's lean
  taken, so generator rigs fall out). A front reads it one radius AHEAD,
  where it is going, and draws it down in a sphere of two radii around
  itself as it passes. Rejected: consuming at the deposit samples (a
  front standing in its own tube read zero and went dormant at once);
  reading under the front (same failure, one step later).
- **Numbers.** Lattice addresses are integers (u32 points, 60-bit Morton
  keys over cells); channel values are f32; front positions are f64
  lattice units. Bit-identity is claimed per BINARY — two processes of
  one build — and, as measured below, across Debug and ReleaseFast of
  one source. Rejected: Q16.16 everywhere (spindrift's rule). A field
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
| G1 | frozen reference | `371e0e2d…` | fixed | commit order reversed | yes — see P1.6 |
| G2 | branches; components in a slice; material N/2 → N | 9; 3; 2596 → 2628 | ≥3; ≥2; no reset | deposit = 0 | yes |
| G3 | front-centroid x, stimulus at +60 vs −60 | 9.46 units | ≥ 8 | tropism_stimulus = 0 → bit-identical | yes |
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
in Debug) and carries no assertion. G2's "components" is the maximum
over horizontal slices of the material's 4-connected components above
0.3 — the brief's "connected material components > 1" read as *visible
branching in the field*; a whole tree is one 3-D component, so the 3-D
count would be a poor measure. Christian to confirm the reading.

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

## P1.7 — the seedbed (2026-09-06)

- `loam-run`: named scenes, `--damage box@step`, `--slice`, `--project`
  (a max-projection, since a slice through a thin tube mostly misses
  it), `--dump`, `--ray`, `--all-regions`, `--active`, `--phases`. Every
  number a gate asserts can be printed here on the same scene.
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

Per phase at step 40 (Debug): operate 0.02, fronts 0.24, apply 1.3,
frontier 1.5, seams 9.0, finalize 6.0, build 1.2, publish 1.5 ms. The
seams remain the cost; the next cut is a same-gauge face fast path that
skips the per-point holder search (recorded, trigger: G5's slope on a
scene with hundreds of active bricks).
