# loam

**Sparse field dynamics.** Things grow in it; it does not make the oak.

A renderer-neutral substrate for evolving worlds: continuous spatial
state on a sparse 8-way tree, local operators that evolve it, Lagrangian
fronts that read it and deposit into it, and immutable snapshots a
renderer samples while the next step is being made. The library does not
generate objects. It evolves spatial state; a renderer merely asks what
that state means to a ray.

```zig
const loam = @import("loam");

var world = try loam.World.init(gpa, .{ .seed = 7 });
defer world.deinit();
try loam.seedbed.blob(&world, loam.Channel.growth.bit(), .{ 0, 24, 0 }, 56, 1.0, 0);
try loam.seedbed.blob(&world, loam.Channel.light.bit(), .{ 40, 60, 0 }, 64, 1.0, 0);
try loam.seedbed.plant(&world, .{ 0, 0, 0 }, .{ 0, 1, 0 }, .{ .tropism_light = 0.6, .length = 72 });
try world.apply();
var t: u64 = 0;
while (t <= 60) : (t += 1) try world.step(.{ .frame = t, .time_ns = t * std.time.ns_per_s }, null);
const hash = world.published().rootHash();
```

The same world from Python, over the C seam:

```python
import loam
w = loam.World(seed=7)
w.blob("growth", (0, 24, 0), 56); w.blob("light", (40, 60, 0), 64)
w.plant((0, 0, 0), (0, 1, 0), length=72, tropism_light=0.6); w.apply()
w.run(60)
print(w.root_hash().hex(), w.stats()["fronts"])
```

## Status — Phase 2.1: the continuous carrier

Matter is the zero set of a continuous signed implicit, `surface`,
stored in 11³ blocks (the brick's 9³ samples and one halo layer from the
neighbours) and reconstructed by a cubic B-spline: C2 inside a brick and
across a same-gauge seam, with a Lipschitz bound in every summary so a
renderer sphere-traces it by |φ|/L and never overshoots. Fronts sweep
lofted capsules into it; a wound cuts it. Matryoshka's `loam` branch
mounts a world through `src/loam_bridge.zig` and renders the carrier's
bricks as a leaf of the dynamic tree with the same B-spline and the same
step: a tree on the grass beside Suzanne, ray-traced with its shadow, no
facet, no seam, no triangle anywhere in it.

```
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --cam -13.77,3,5.31,0.78,-0.42
```

Every brick knows how much it last changed and when — attention, derived
where it is read, never stepped, scored per channel over its range — so
a reader finds where the world is changing from the summaries alone, and
a step under a budget spends its work in two tiers: what it owes (live
fronts, then last step's backlog, a queue in key order) and what it
wants (the rest by attention). `loam-run --budget-fraction 0.5` grows
the same sapling from 22% fewer evaluations, and the budget rides on the
snapshot's hash and the trace: an input like the seed. The bridge reads
the same bookkeeping as its dirty set: a brick keeps its slot on the GPU
and is re-uploaded only when it changed.

The representation states what it can know — a structural feature of
radius r belongs at a gauge with h ≤ r/2 (G13, struck by Christian from
`tools/g13_predict.py`'s theory before the sweep ran) — and the finest
tips of the sapling's twigs are missing from the picture by exactly that
ruling, the first customer of refinement. And a change of representation
did not move a front: `loam-run --trace` and `tools/diff_traces.py` put
Phase 1's and Phase 2's front trajectories side by side from the same
seed, and every read but self-avoidance agreed to a thousandth of a unit
(the ledger, "The habit check"). And a front lays nothing thinner than
the gauge's survival floor, r ≥ h, since a twig thinner than that loses
its zero set under the B-spline; the steps it takes under the faithful
floor, r < 2h, are counted as refinement's demand ("The survival
floor").

### Phase 2.1, the carrier's gates

| gate | claim | as measured (Debug, serial) |
|---|---|---|
| G13 thin feature | sub-gauge structure survives the B-spline as theory predicts | survival and radius agree with the predictor to four decimals across three orientations and nine offsets; a capsule at r/h ≥ 1 survives, at r/h ≥ 2 its radius is within 4.6%; the gauge doubled loses it |
| G9 continuity | the carrier is C2 across a same-gauge seam | 91,193 shared-face pairs, value, gradient and Hessian from both holders: exactly equal; no halo → they differ |
| G10 bound | the summary's Lipschitz bound is conservative | 19,800 random pairs, 0 exceed it; the old axis-only bound is exceeded 45 times |
| G11 sphere trace | a march stepped by \|φ\|/L never lands inside or tunnels | 4096 rays against a dense march: 0 disagreements, 0 late, 0 overshoots; stepping 2\|φ\|/L overshoots 167 times in 1024 |
| G1 again | replay with the new carrier | one frozen reference, from Zig, from Python, across processes, with any thread count; the sim owns its sin, cos and exp so no libm can move it |
| G14 attention | the step's work follows where things are changing, and a reader sees it from the summaries | the evaluated set is the head of the active set — obligations in key order, then by attention — recomputed from the snapshot at every step; a walk on the summaries finds exactly the attentive bricks (91 of 3652 at step 80, 264 leaves examined); the sapling under a budget of half its active set is the same tree from 22% fewer evaluations (invariance), and a run replayed from its recorded budgets is the same hash (reproducibility); no front step is ever skipped, the overrun is reported; the head in key order loses 36%, one queue of fronts and backlog gains 38% |

### Phase 1, all eight gates

| gate | claim | as measured (Debug, serial, seed 7) |
|---|---|---|
| G1 replay | (seed, fields, operators) → byte-identical snapshot | same hash serial and over the JobSystem; across two processes; from Python and from the CLI; equal to a frozen reference in Debug and ReleaseFast |
| G2 growth | a seeded front builds persistent branching structure, no mesh | 19 branches; 7 components of young tissue at peak (1 with branching off); tissue never resets |
| G3 tropism | matched ± stimulus pairs across 6 seeded directions produce a positive directional centroid response | 95% lower confidence bound > 0, every pair has the correct sign, mean response exceeds 3× natural wander RMS; zero-coefficient and reversed-gradient mutations both fail |
| G4 repair | cutting tissue re-activates locally only | 78 bricks touched, 0 beyond two bricks of the wound; untouched bricks are the same pointers |
| G5 dormancy | dormant tissue costs nothing | a quiet step publishes nothing and costs nothing; Activity is a touch time, so nothing decays and nothing churns once the fronts stop |
| G6 skip | a ray rejects subtrees from summaries alone | 12 of 64 crossed leaves sampled |
| G7 narrow query | shadow queries do less work than primary | shadow gathers 25% of primary's channel bytes |
| G8 snapshot safety | N readable while N+1 simulates | 10 full re-hashes of vid 22 while the writer reached 62, zero mismatches, no lock |

Every threshold is a PROPOSED value in `src/thresholds.zig`, for Christian
to strike. Every gate has a mutation; `docs/implementation-notes.md`
records which bit and which survived, and what each survivor changed.
Bit-identity is claimed per binary on one machine.

## Try it

```sh
zig build                                   # library, libloam.so (the C seam), loam-run
zig build run -- --steps 120 --project surface:z:256:tree.pgm
zig build run -- --scene wound --damage -10,18,-10,10,30,10@100 --steps 160 --phases
zig build run -- --all-regions --steps 40   # the G5 mutation, as a number
zig build run -- --threads 16 --steps 200 --phases      # the parallel phases over common's JobSystem; same hash
zig build run -- --tropism-sweep 10,20,40   # G3's ensemble as a dose-response, one world per core
zig build run -- --steps 160 --every 0 --trace fronts.txt   # every front, every step: the habit check's instrument
python3 -m unittest discover -s py/tests    # after zig build
zig build test                              # the gates
```

Fixed dt is the only clock: `--dt-ms 1000` is one fed second per step,
and two runs with the same flags print the same hash — with any thread
count.

## Layout

| path | what |
|---|---|
| `src/lattice.zig` | the 20-bit dyadic lattice, Morton keys, the world↔lattice door |
| `src/channel.zig` | channel bits, the registry with its user range, per-channel clamps |
| `src/brick.zig` | 8-cell bricks at a gauge, 11³ blocks (9³ samples and a halo), the cubic B-spline and its derivatives, popcount-packed planes |
| `src/summary.zig` | the conservative node payload: tight bounds, mask, ranges, Lipschitz bounds, majorant, version |
| `src/fmath.zig` | the sim's own sin, cos and exp: the same bits in every binary |
| `src/tree.zig` | the persistent 8-way tree, Merkle hashes, snapshots, point lookup and sampling |
| `src/update.zig` | region-local update buffers: deltas, surface ops (join, cut), materialise, spawns |
| `src/world.zig` | the step: operate → fronts (the capsule sweep) → commit (frontier, seams, halos, summaries) → publish; the hazard-slot reader |
| `src/operators.zig` | Diffusion, Decay, Advection, Healing; the operator vtable |
| `src/front.zig` | the Lagrangian front carrying loop-loft's ring |
| `src/ray.zig` | the traversal cursor: near-to-far, summary rejection, the `--no-skip` instrument; the sphere tracer |
| `src/guards.zig` | every invariant, checkable; corrupted one by one in the self-test |
| `src/dump.zig` | the snapshot as one canonical struple map |
| `src/seedbed.zig` | the authoring verbs and the named scenes |
| `src/run.zig` | `loam-run` |
| `src/capi.zig` | the C seam (`libloam.so`) |
| `src/thresholds.zig` | the gate numbers, PROPOSED until struck; G13's are struck, with the prediction frozen beside them |
| `src/tests.zig` | the gates, each with its named mutation |
| `py/loam/` | the ctypes binding and the dump reader |
| `py/tests/` | the Python gates |
| `tools/read_dump.py` | the cross-language dump reader (`zig build verify-dump`) |
| `tools/g13_predict.py` | G13's theory: what the B-spline does to a thin capsule, before the sweep ran |
| `tools/diff_traces.py` | where two front-trajectory traces part company: the habit check |
| `docs/` | the spec, the brief, loop-loft, and the ledger |

## Depends on

`../common` (the one JobSystem), `../struple` (every byte that leaves
memory). Matryoshka will depend on loam; loam never depends on Matryoshka.

## License

Dual-licensed: Apache 2.0 or a commercial license from Foundation42 —
see `LICENSE`.
