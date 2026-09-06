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

## Status — Phase 2.3: the picture, on the continuous carrier with its collar and provenance

Matter is the zero set of a continuous signed implicit, `surface`,
stored in 11³ blocks (the brick's 9³ samples and one halo layer from the
neighbours) and reconstructed by a cubic B-spline: C2 inside a brick and
across a same-gauge seam, with a Lipschitz bound in every summary so a
renderer sphere-traces it by |φ|/L and never overshoots. Fronts sweep
lofted capsules into it; a wound cuts it. Matryoshka (on `main`
since Sunday 2026-09-06) mounts a world through `src/loam_bridge.zig`
and renders the carrier's bricks as a leaf of the dynamic tree with the same B-spline and the same
step: a tree on the grass beside Suzanne, ray-traced with its shadow, no
facet, no seam, no triangle anywhere in it.

```
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --cam -13.77,3,5.31,0.78,-0.42
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --loam-scene junction   # a bud junction: the collar's scene
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --loam-scene coil       # a coiling tendril: the self-touch
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --loam-collar 0         # the hard union, for a side-by-side
matryoshka test_scene --loam -13,0,3 --loam-scale 0.06 --loam-speed 20 --loam-no-bark          # the carrier alone: the bark off
```

The mount grows the sapling unless `--loam-scene` names one of P2.2's
two scenes; `--loam-collar` is the collar as a fraction of the ring's
radius, and zero is the fold the collar replaces. The difference is in
the crotch of each fork and nowhere else, a fillet of the child's
radius, so it is subtle by design.

Up close the bark is there, and it comes from the field alone: at
every hit the level set's own principal directions, from the Hessian,
give the tube's axis, and a procedural grain in that frame bends the
normal and darkens its own grooves. No chart, no ring, no provenance
plane is read — the sweep's rings are a scaffold, and the point of
loam is the gradient field. Each octave fades in over an octave of
the pixel's footprint rather than switching on, so walking toward the
trunk pops nothing; far away a hit reads the carrier and nothing
else. History stays where it is: `who` and `segment` on every sample
a front laid, and the chart's (s, θ) anywhere is that capsule's exact
foot, rebuilt from the ring records when history is asked for.
`--loam-no-bark` is the carrier alone; `--loam-bark-scale` is one
knob over the depth; the bark's octaves are in metres (three
centimetres and half that), because bark does not get finer when the
brick does.

Every brick knows how much it last changed and when — attention, derived
where it is read, never stepped, scored per channel over its range — so
a reader finds where the world is changing from the summaries alone, and
a step under a budget spends its work first on what it owes (the live
fronts, never cut) and then by a score in which deferral costs —
pending change times how long it has waited — so a hot region is served
often and every brick with real pending change within a bounded delay. `loam-run --budget-fraction 0.5` grows
the same sapling from 22% fewer evaluations, and the budget rides on the
snapshot's hash and the trace: an input like the seed. The bridge reads
the same bookkeeping as its dirty set: a brick keeps its slot on the GPU
and is re-uploaded only when it changed.

Where a child meets its parent the two tubes join through a collar of
the child's radius — a smooth union that is real only there: along a
front's own chain the union is hard, so no bead sits at a joint, and a
tendril that curls back onto its own older tube meets it as it would
another front. Provenance decides which is which: every sample a front
lays remembers who laid it, at which ring, and where on that ring's
chart, so the bark's finer bands read back through the ring history —
a band-1 read through a sample's chart rebuilds its deposit to the bit
— and a wound keeps the id of whoever grew there. Each sample keeps its
two nearest contributors apart and the carrier is their one smooth
union, so a child arriving as a chain of capsules is collared once
(the ledger, "P2.2 — the collar, provenance and the bands", with the
inner elbow of a hard chain measured against a bud's crease). `loam-run
--scene junction` and `--scene coil` are the scenes; `--collar 0` is
the hard union.

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
| G16 the picture | the bark's frame is the field's own, the chart is history's, and the bytes a hit touches say so | the grain's frame comes from the Hessian at the hit and reads nothing but the carrier, no provenance plane at any footprint; the chart, the capsule's exact foot from (who, segment), advances by the arc to zero error and switches fronts only inside a collar's zone and only where the two fields cross; the bent normal turns continuously across the collar; bands fade in over an octave of footprint, never pop, and a band under its footprint is never fetched; a sponge reads 256 bytes at any distance; `who` or the segment interpolated is a front that does not exist, the footprint ignored pays for everything |
| G12 collar | the smooth union happens where a child meets its parent and nowhere along a chain; the bark's bands read back through provenance | against the same scene under the hard union the collared junction is nowhere higher and lower only within the child's zone, by at most k/4 (468 samples, 0.520 against 0.525); a coil is collared where its turns touch and hard where its own recent capsules meet; band 1 read through each sample's chart rebuilds its deposit bit for bit (10,126 of 10,126) and a cut leaves the scar its provenance; a sponge-class query gathers 256 bytes and nothing of the history; "nothing is its own" beads the chain, "its own at any age" creases the coil |
| G13 thin feature | sub-gauge structure survives the B-spline as theory predicts | survival and radius agree with the predictor to four decimals across three orientations and nine offsets; a capsule at r/h ≥ 1 survives, at r/h ≥ 2 its radius is within 4.6%; the gauge doubled loses it |
| G9 continuity | the carrier is C2 across a same-gauge seam | 91,193 shared-face pairs, value, gradient and Hessian from both holders: exactly equal; no halo → they differ |
| G10 bound | the summary's Lipschitz bound is conservative | 19,800 random pairs, 0 exceed it; the old axis-only bound is exceeded 45 times |
| G11 sphere trace | a march stepped by \|φ\|/L never lands inside or tunnels | 4096 rays against a dense march: 0 disagreements, 0 late, 0 overshoots; stepping 2\|φ\|/L overshoots 167 times in 1024 |
| G1 again | replay with the new carrier | one frozen reference, from Zig, from Python, across processes, with any thread count; the sim owns its sin, cos and exp so no libm can move it; a brick's hash covers its own 9³ samples and never the halo — a corrupted halo sample leaves the hash where it is and fires the halo guard |
| G15 budget | a step spread over frames is the same step, and a call never exceeds its budget | 40 steps in 2282 calls of 8 units publish the frozen reference, serial, over 4 threads and in calls of 37; the largest call performed 8 of 8 (unchunked applies: 53); cut at half the head every step, the sapling is the same tree and no front step is skipped; fronts made deferrable loses 9.9% |
| G14 attention | the step's work follows where things are changing, and a reader sees it from the summaries | the evaluated set is the head of the active set — obligations in key order, then by attention — recomputed from the snapshot at every step; a walk on the summaries finds exactly the attentive bricks (91 of 3652 at step 80, 264 leaves examined); the sapling under a budget of half its active set is the same tree from 14% fewer evaluations (invariance), and a run replayed from its recorded budgets is the same hash (reproducibility); no front step is ever skipped, the overrun is reported; deferral costs, so under a region ten times hotter every cold brick is served within the 20 steps predicted from τ, and never without the lag term; the head in key order loses 36%, one queue of fronts and backlog gains 35% |

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
zig build run -- --steps 160 --budget-fraction 0.5 --trace run.txt   # half the active set a step; the budget on every `# step` line
zig build run -- --steps 160 --budget-schedule run.txt              # replayed from the record: the same hash
zig build run -- --scene wound --damage -10,8,-10,10,16,10@20 --steps 60 --budget 12   # a sustained cut: the backlog, and the overload count
zig build run -- --steps 160 --budget-fraction 0.5 --budget-order no_lag   # G14 (e)'s mutation, as a number
zig build run -- --steps 40 --units 8           # the step through work(8) calls: the plain step's hash
zig build run -- --steps 40 --cut 0.5 --trace run.txt   # CUT after the fronts and half the head; the cut point on every `# step` line
zig build run -- --scene junction --steps 40    # a bud junction: the child collars into its parent at its own radius; --collar 0 is the hard union
zig build run -- --scene coil --steps 80        # a coiling tendril: hard along its own recent chain, collared where its turns touch
python3 -m unittest discover -s py/tests    # after zig build
zig build test                              # the gates
```

Fixed dt is the only clock: `--dt-ms 1000` is one fed second per step,
and two runs with the same flags print the same hash — with any thread
count. The budget is the other input, and it is on the transcript: a
run replayed from its recorded per-step budgets prints the same hash,
and a different schedule is a different world that says so. A step is
also resumable: `begin`, `work(units)`, `cut`, `finish`, and a host that
spreads one step over as many frames as it likes publishes the same
hash as a host that takes it in one (`--units 8`); a host that cuts
keeps the fronts and the best of the rest, and where it cut is on the
transcript (`--cut 0.5`).

## Layout

| path | what |
|---|---|
| `src/lattice.zig` | the 20-bit dyadic lattice, Morton keys, the world↔lattice door |
| `src/channel.zig` | channel bits, the registry with its user range, per-channel clamps; the seven of P2.2 — who, segment, chart_s, chart_theta (set by the winner), own, other, collar (the two slots and the join's k) |
| `src/brick.zig` | 8-cell bricks at a gauge, 11³ blocks (9³ samples and a halo), the cubic B-spline and its derivatives, popcount-packed planes |
| `src/summary.zig` | the conservative node payload: tight bounds, mask, ranges, Lipschitz bounds, majorant, version, and attention — the last change's magnitude and time, merged by max, decayed where it is read |
| `src/fmath.zig` | the sim's own sin, cos and exp: the same bits in every binary |
| `src/tree.zig` | the persistent 8-way tree, Merkle hashes, snapshots (the active set, since when each brick is owed, the budget the step ran under), point lookup and sampling, the attention walk |
| `src/update.zig` | region-local update buffers: deltas, surface ops (join, cut — a front's with its provenance and charts), materialise, spawns |
| `src/world.zig` | the step: the head under a budget (the fronts' bricks first, never cut; then the residual's score) → operate → fronts (the capsule sweep, the charts) → commit (the two slots and the collar, frontier, seams, halos, summaries, the attention bookkeeping) → publish; the ring history and the band query; the hazard-slot reader |
| `src/operators.zig` | Diffusion, Decay, Advection, Healing; the operator vtable |
| `src/front.zig` | the Lagrangian front carrying loop-loft's ring; the ring record the history keeps |
| `src/ray.zig` | the traversal cursor: near-to-far, summary rejection, the `--no-skip` instrument; the sphere tracer |
| `src/guards.zig` | every invariant, checkable; corrupted one by one in the self-test |
| `src/dump.zig` | the snapshot as one canonical struple map |
| `src/seedbed.zig` | the authoring verbs and the named scenes |
| `src/bark.zig` | what a hit reads beyond the carrier: the grain in the field's own frame, the chart as history, the bands by footprint — the shader's CPU reference, its bytes counted |
| `src/run.zig` | `loam-run` |
| `src/capi.zig` | the C seam (`libloam.so`) |
| `src/thresholds.zig` | the gate numbers, PROPOSED until struck; G13's are struck, with the prediction frozen beside them; G14 (e)'s prediction frozen beside τ; the collar's reach derived beside G12 |
| `src/tests.zig` | the gates, each with its named mutation |
| `py/loam/` | the ctypes binding and the dump reader |
| `py/tests/` | the Python gates |
| `tools/` | `g13_predict.py` (the thin-feature prediction, frozen beside G13), `diff_traces.py` (the habit check), `read_dump.py` |
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
