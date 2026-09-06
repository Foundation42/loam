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
var decay = loam.operators.Decay{ .bit = loam.Channel.activity.bit(), .tau = 3 };
try world.addOperator(loam.operators.operatorOf(loam.operators.Decay, &decay));
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
w.add_decay("activity", tau=3.0)
w.run(60)
print(w.root_hash().hex(), w.stats()["fronts"])
```

## Status — Phase 1 green and bitten; the first loam-grown thing is on screen

Matryoshka's `loam` branch mounts a world through `src/loam_bridge.zig`
and renders its material bricks as a leaf of the dynamic tree, marched
to an iso-surface from the field's own 9³ samples: a tree on the grass
beside Suzanne, ray-traced with its shadow, no triangle anywhere in it.

```
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --cam -13.77,3,5.31,0.78,-0.42
```

Christian's pose, from the P key. The ridges on the bark are the ring's
residuals — loop-loft's heat map, made solid — and the collars are where
buds left; the shadow is the sun's, and the tree stands in the green
sphere's reflection because the reflection walk found the leaf unasked.

### Phase 1, all eight gates

| gate | claim | as measured (Debug, serial, seed 7) |
|---|---|---|
| G1 replay | (seed, fields, operators) → byte-identical snapshot | same hash serial and over the JobSystem; across two processes; from Python and from the CLI; equal to a frozen reference in Debug and ReleaseFast |
| G2 growth | a seeded front builds persistent branching structure, no mesh | 9 branches; 5 components of young material at peak (1 with branching off); material never resets |
| G3 tropism | matched ± stimulus pairs across 6 seeded directions produce a positive directional centroid response | 95% lower confidence bound > 0, every pair has the correct sign, mean response exceeds 3× natural wander RMS; zero-coefficient and reversed-gradient mutations both fail |
| G4 repair | removing material re-activates locally only | 54 bricks touched, 0 beyond two bricks of the wound; untouched bricks are the same pointers |
| G5 dormancy | dormant tissue costs nothing | 12,480 evaluations where iterating every brick would be 584,320 |
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
zig build run -- --steps 120 --project material:z:256:tree.pgm
zig build run -- --scene wound --damage -10,18,-10,10,30,10@100 --steps 160 --phases
zig build run -- --all-regions --steps 40   # the G5 mutation, as a number
zig build run -- --threads 16 --steps 200 --phases      # the parallel phases over common's JobSystem; same hash
zig build run -- --tropism-sweep 10,20,40   # G3's ensemble as a dose-response, one world per core
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
| `src/brick.zig` | 8-cell bricks at a gauge, 9³ node-centred samples, popcount-packed planes |
| `src/summary.zig` | the conservative node payload: tight bounds, mask, ranges, gradient, majorant, version |
| `src/tree.zig` | the persistent 8-way tree, Merkle hashes, snapshots, point lookup and sampling |
| `src/update.zig` | region-local update buffers: deltas, materialise, spawns |
| `src/world.zig` | the step: operate → fronts → commit (frontier, seams, summaries) → publish; the hazard-slot reader |
| `src/operators.zig` | Diffusion, Decay, Advection, Healing; the operator vtable |
| `src/front.zig` | the Lagrangian front carrying loop-loft's ring |
| `src/ray.zig` | the traversal cursor: near-to-far, summary rejection, the `--no-skip` instrument |
| `src/guards.zig` | every invariant, checkable; corrupted one by one in the self-test |
| `src/dump.zig` | the snapshot as one canonical struple map |
| `src/seedbed.zig` | the authoring verbs and the named scenes |
| `src/run.zig` | `loam-run` |
| `src/capi.zig` | the C seam (`libloam.so`) |
| `src/thresholds.zig` | the gate numbers, PROPOSED |
| `src/tests.zig` | the gates, each with its named mutation |
| `py/loam/` | the ctypes binding and the dump reader |
| `py/tests/` | the Python gates |
| `tools/read_dump.py` | the cross-language dump reader (`zig build verify-dump`) |
| `docs/` | the spec, the brief, loop-loft, and the ledger |

## Depends on

`../common` (the one JobSystem), `../struple` (every byte that leaves
memory). Matryoshka will depend on loam; loam never depends on Matryoshka.

## License

Dual-licensed: Apache 2.0 or a commercial license from Foundation42 —
see `LICENSE`.
