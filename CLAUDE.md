# Working in loam

## Running tests — the default is to run NOTHING

Pick a gate because the change can break the thing it watches, never to
feel reassured. Chris has asked for this in every sibling repo; a suite
run per edit makes the harness the activity rather than the work.

    zig build test -Dtest-filter=straddling   # one gate: 17 s to compile ReleaseSafe, then seconds
    zig build test                            # 104 gates, ~3 min ReleaseSafe — before a commit
    zig build test -Dtest-optimize=Debug -Dtest-filter=…   # the other regime: 2 s to compile, slower to run
    zig build test -Dtest-optimize=ReleaseFast              # the delta, when Christian asks for it
    zig build verify-dump                     # loam-run writes a dump, the struple PYTHON port reads it
    zig build py-test                         # the ctypes binding, and G1 across two PROCESSES
    zig build run -- --units 8 --steps 40     # the step through work(8) calls: the same hash
    zig build run -- --cut 0.5 --steps 40     # CUT: fronts, half the head, finish; the cut on the trace
    zig build run -- --scene junction --steps 40   # a bud junction: the collar's scene (G12); --collar 0 is the hard reference
    zig build run -- --scene coil --steps 80       # a coiling tendril: self-touch, the inner elbow
    zig build test -Dtest-filter="G16"             # the picture's gates: what a hit reads (src/bark.zig)
    zig build run -- --scene marble --steps 90 --volume 64:slice.ppm   # the material seedbed: the marble as a material field, a colour slice
    zig build run -Doptimize=ReleaseSafe -- --scene marble --steps 90 --rbf 256:marble.lrbf   # the field packed into Gaussians (a tool run; the fit is not a sim measurement)
    zig build run -- --help                   # loam-run, the seedbed

The suite is CPU-only and deterministic, so the calculus is spindrift's:
run a gate when you have changed what it watches, the lot once before a
commit. What is NOT cheap is downstream — matryoshka will read the tree,
the summaries and the sampling contract the way it reads spindrift's
population, and once it does, anything a host reads (`Snapshot`,
`Summary`, `Brick` layout, the C seam, the dump) puts its GPU sweep in
the blast radius.

Rules that hold whatever you picked:

- A gate that passed stays passed until the code changes.
- The gates run ReleaseSafe by default — the same safety checks as
  Debug, the suite in 166 s against 270 (Christian, Sunday 2026-09-06:
  "running the tests ReleaseSafe — good idea") — and every timing a
  gate prints names its mode (`@tagName(builtin.mode)`), never assumes
  it. `loam-run` is unaffected: Debug is its measuring regime,
  `--phases` prints wall-clock per phase, and the numbers in the ledger
  state which build they came from. One suite per commit, not per edit.
- One GPU gate at a time, when a sibling repo's are involved.

## The ledger

`docs/implementation-notes.md` — every decision made while building, with
the mutation that paid for each gate. Same rules as rill's ledger, restated
at its head. Docs ride the same commit as the code they describe.

## House style

Write the reasoning into the code. A gate's comment should name the bug it
was paid for. A gate that cannot fail is decoration: check it fails against
the old behaviour before believing it — every gate in `src/tests.zig` has a
named mutation, executable where cheap, by hand where not, and the ledger
records which bit and which survived (a survived mutation is a finding:
either the gate does not vary on that axis, or the code is decoration).

Prose approves plausible semantics; execution approves actual semantics.
Read-aloud before naming; record rejected names. Recorded-not-built needs
a trigger. Loud, never a guess — a refusal lands on the node that refused.

## The sim's rules

- **Time is fed, never read.** `step(now)` carries `{frame, time_ns}`; dt
  is the fed delta; no wall clock reaches the sim. A regression is
  `error.TimeRegression`, never a clamp. The first tick is the epoch and
  moves nothing.
- **The budget is fed too, in work units (R16).** A step is `begin(now)`,
  `work(units) → done?`, `cut()`, `finish()`, its state on the world
  between calls; `step(now)` is the three in one. `work` performs at
  most its units, in phase order — fronts (charged first, never cut),
  operators (the only phase a cut stops), the sinks merged, apply,
  frontier, seams, halos, finalize, build — with the serial remainders
  one unit each; `finish` does what remains and counts it apart
  (`units_finish`). SPREAD is exact: any call sizes publish the one-piece
  step's hash (G15 a). `Snapshot.cut_at` is in the content hash; the
  units and calls ride on the snapshot and the trace. Operators read the
  fronts AS PUBLISHED (`base.fronts`): the front pass has moved the live
  ones by the time they run. Every `finish` consumes the buffer: a
  second `apply` applies nothing. **A unit is a count, never a time.**
  Units are uneven by three orders of magnitude and that is the shape
  of the work; the count is what replays across machines, and the cost
  of a unit is the host's measurement to feed a count from. Nobody
  makes a unit "about 10 µs" for tidiness.
- **A brick's hash covers its own 9³ samples, never the halo.** The
  halo is a copy of the neighbours' own samples, hashed where they are
  owned; hashing it again is a second truth in the identity. `HaloStale`
  and G9 are the halo's witnesses: a corrupted halo sample leaves the
  hash where it is and fires the guard (the gate "the hash covers the
  canonical samples"). Blake3 stays, because the pack's root hash is
  Blake3 over bytes and a cheaper leaf hash would split the sim's
  identity from the pack's.
- **Addresses are integers; values are f32; movers are f64.** Lattice
  points and Morton keys are integers on the 20-bit lattice (R2). Channel
  values are f32 with a fixed evaluation order. Front positions are f64
  lattice units. Bit-identity (G1) is claimed per SOURCE on ONE MACHINE:
  two processes agree, Debug and ReleaseFast agree, the C seam (glibc)
  and loam-run (no libc) agree — because the sim calls no libm: sin, cos
  and exp are `src/fmath.zig`'s, pinned bit for bit (a glibc/musl ulp in
  a bud's heading once split the two doors' hashes). Nothing on the sim
  path may call `@sin`, `@cos`, `@exp` or `@log`; `@sqrt` and
  `std.math.atan2` are fine. A GPU twin is D3's problem and the integer
  lattice is the path there.
- **Operators write deltas, never bricks.** Region-local update entries,
  applied at commit in key order. No parallel phase can reach the result
  in a different order; G1 runs serial and over common's JobSystem and
  compares the bytes against a frozen reference.
- **The carrier is composed, never added.** `surface` (Phase 2, R8–R11)
  is a signed implicit, negative inside, clamped to ±3 cells of the
  brick's gauge; +band is "far", the absent value. A contribution is a
  `SurfaceOp` — a plane of signed distances with a collar k, an order and
  a mode (join = smooth union, cut = CSG difference) — applied in order
  at commit. Fronts sweep capsules with k = 0: a chain of a front's own
  capsules smooth-unioned with k > 0 beads at every joint (the ledger,
  P2.1); the collar is P2.2's.
- **The collar is gated by provenance, through two slots (P2.2, G12).**
  A capsule unions HARD into samples its own front laid within the
  collar's REACH behind its start ring — `thresholds.collarReach`,
  √(k² + 2ρk), measured along the arc through `chart_s`, never counted
  in segments (a count is a function of dt) — and SMOOTH, with k the
  ring's radius (`Params.collar` × envelope, "the child's radius at the
  join"), into everything else: another front's tube, authored tissue,
  its own older tube (self-touch beyond the reach is another front —
  Christian's amendment). Every sample keeps `own` (the nearest
  contributor's own distance, before any collar), `other` (the
  runner-up's) and `collar` (the join's k, the least willing member's),
  and `surface` is their ONE smooth union, recomposed when a slot
  changes. With one slot a child's chain of capsules collared the same
  parent sample once per capsule (1.46 deep against the smin's 0.75).
  Provenance — `who` (id + 1, zero is nobody), `segment`, `chart_s`,
  `chart_theta` — is written by the WINNER (the op nearer than what
  stood) and by nothing else: a cut writes none, so the scar remembers
  who grew there. None of the seven is ever a delta, reaches across a
  face, or scores attention; the seam pass counts none of them toward
  the change floor (a copied `who` of six once woke every neighbour of
  a tube). The ring history (`World.rings`) is optional history, not in
  the content hash; `Capsule.between` rebuilds any sweep from it with
  the front's own arithmetic, and G12 (b) reads every deposit back
  bit for bit. `--collar 0` reproduces the previous carrier exactly.
- **What a hit reads is `src/bark.zig`, term for term with the shader
  (P2.3, G16). THE BARK'S FRAME IS THE FIELD'S** (Christian: "the rings
  are a scaffold; the point of loam is the gradient field"): the grain
  is value noise in the level set's own principal frame — the Hessian
  at the hit, the tube's axis its direction of least curvature —
  stretched along the axis, even in the frame's signs, keyed by world
  position; it reads nothing but the carrier, and the GPU carries the
  carrier alone. THE CHART IS HISTORY'S: `who` and `segment` name the
  capsule that laid a sample, and the chart's (s, θ) at any point is
  that capsule's foot there, rebuilt from the ring records exactly —
  no chart plane is stored, nothing is interpolated (two stored chart
  planes were built and dropped the same night: the seam sat on the
  sample grid, a one-sided mask lost linear precision). Where two
  fronts laid the neighbourhood the hit belongs to the one whose
  field, rebuilt from the two slots, is nearer: the seam at the
  crossing. Bands are read by FOOTPRINT — the ray's width at the hit,
  WORLD units — and FADE in over an octave (`thresholds.bandWeight`,
  never a pop); a band under its footprint is never fetched. Bands
  1–2 (the ring morphology through the chart) are what the field
  already holds and are read for the events only. The chart's grain
  goes bare at a collar by the DIFFERENCE of the two slots' weights
  (`collarBare`, zero where they meet). The collar's recency window
  asks the ring table through `segment`: the reach behind the new
  capsule's start against the sample's capsule's end arc, dt-safe. The
  prediction of what a read touches is frozen beside the threshold
  (`G16_PREDICTED`, both modes) and the gate reads it at every row.
- **A plane is an 11³ block.** The brick's 9³ samples sit at block
  coordinates 1..9; the halo (0 and 10) is the neighbours' layer beyond
  each face, copied at commit by the halo pass. `Brick.index(i, j, k)`
  addresses the brick's own samples; nothing may step a plane by `N`
  (diffusion's stencil did, and mass went 1 → 3.25). Reconstruction is
  the cubic B-spline over the block (`spline`, `splineJet`); `trilinear`
  is the hanging-node interpolant and G13's instrument variation.
- **What runs in parallel** when a world has `jobs` (or `step` is handed
  a system): the operate phase, applying deltas, finalize (summary and
  hash), blob authoring, the seam and halo passes' collect phases, and
  the front pass into per-front sinks — all order-free; seam and halo
  writes are sorted and applied in key order, sinks are merged in id
  order (Age set-once: the first in id order wins; surface ops carried
  whole, composed at commit). The G3 ensemble runs its worlds one per core
  on plain threads. `loam-run --threads N` sets all of it, and the hash
  must not move — and "serial equals parallel" is not enough: G1's
  frozen reference is what caught the front pass summing two birth
  times while agreeing with itself at every thread count.
- **Randomness is counter-based.** `rng.Stream` hashes (seed, who, epoch,
  counter); nothing draws sequentially, so parallel order cannot leak in.
- **A quiet step publishes nothing.** No active brick, no live
  non-dormant front, no spawn pending, nothing authored: `step` advances
  the clock and returns; the vid stands. Activity is a TOUCH TIME (the
  fed second a front last passed; `Rule.touch`), never a decaying level:
  a decaying level kept fifty bricks changing for forty steps after the
  last front stopped. Read warmth as `now − Activity`, with the world's
  clock, not the snapshot's.
- **Attention is derived, never stepped (R15).** Every brick carries
  the magnitude and fed time of its last change, `attention` and
  `changed_ns`, written in the commit's finalize and nowhere else, in
  its hash, merged by MAX on each field separately into the summaries.
  The magnitude is per channel over that channel's range
  (`channel.attentionScale`), the max across channels — a wound's
  Damage 0 → 1 scores as a deposit does; in surface units alone a cut
  scored half a deposit and was outranked by a clamp. a(t) =
  a₀·exp(−(t − t₀)/τ) is computed where it is read
  (`Summary.attentionAt`, through `fmath.exp`); nothing maintains it.
- **Attention and obligation are different things (Christian's ruling).**
  Attention is a score of what will change next; obligation is what
  must run regardless. Under `Policy.budget` the head IS the step —
  operators and fronts. First the bricks hosting a live front (dormant
  included), in key order, NEVER cut (struck: a skipped front step is
  the front's clock silently halved, and clocks are explicit channels,
  never a side effect of the budget): what they exceed the budget by is
  `StepStats.overrun`, reported. Then THE RESIDUAL (R17): the rest by
  score = pending × (1 + lag/τ), pending the brick's attention
  accumulated by max while it is owed and reset when evaluated
  (undecayed — the reader's decayed attention in the product can never
  catch a hot region), lag = now − `Snapshot.active_since` (aligned
  with `active`, in the content hash; on the snapshot, not the brick,
  because an evaluated brick that did not change is never cloned), τ =
  `LAG_TAU_S`. Deferral costs: a brick at a catches a region at R·a
  once lag ≥ (R − 1)τ + R·dt (G14 e, predicted before the run). The
  guarantee is a fair distribution, not keeping up. The tail carries
  forward with its since intact and fades only when its READER
  attention is under EPSILON AND it hosts no front. The backlog
  (`Snapshot.backlog`, `World.overload_steps`) is a standing number:
  under a sustained cut it grows and lag rises everywhere — D5's signal
  to slow the clock, not P2.1b's problem. The budget a step ran under
  is on the snapshot and in the content hash: an input like the seed,
  logged by `loam-run --trace`, replayed by `--budget-schedule`, never
  derived from a clock at replay (G14 d). G14 (a) recomputes the head
  from the snapshot alone; a change to the score must keep that
  recomputable.
- **Snapshots are immutable and refcounted.** A published brick is never
  handed out as `*Brick`. The commit clones what it changes; untouched
  subtrees are shared by identity (G4 checks identity, not equality).
  Readers `acquire` through a hazard slot, lock-free (G8).

## The seam contract

Every brick stores its own faces, so two bricks sharing a face both hold
it. At commit, over every changed brick's surface: a shared point takes
the finest holder's value (ties: the holder that wrote deltas this
commit, then the lowest key); a fine sample on a face shared with a
coarser brick, off the coarse lattice, takes the coarse interpolant. Then
the halo: every changed brick's halo entries, and every neighbour's halo
entries inside its cube, take the same rule one layer deeper — so two
same-gauge holders reconstruct a face from the same 64 coefficients and
the B-spline is C2 there (G9, exactly). The guard (`guards.zig`)
reconstructs every shared face from both sides and recomputes every
halo by the slow general path; the commit collects writes in parallel
through a neighbourhood cache — a slab copy where the neighbour is one
brick at the same gauge, the general path for the void and for mixed
gauges (an entry at the edge of a face slab is held by the next cell
over) — and applies them sorted. They must agree, and the guard is the
witness, not the cache.

## A change of representation must not move a front

What a front READS is a contract apart from what it deposits into.
Self-avoidance and inhibition read `World.occupancy` — the carrier as
Phase 1's Material profile, 1 inside and a 0.75-unit ramp outside —
never the carrier's own gradient, which is a unit vector three cells out
and pointed off the tube's axis inside it (the trunk moved 25 units by
step 160 when it did). The check is `loam-run --trace` on both sides of
a change and `tools/diff_traces.py` between them: every read that kept
its meaning agrees to a thousandth of a unit, and the one that did not
names itself by the first step it moved.

## Thresholds are Christian's

`src/thresholds.zig` holds every ⟨…⟩ from the brief's gate table as a
PROPOSED value until he strikes it (G13's are STRUCK). Do not tune a
threshold to make a gate pass; change the code, or record the finding
and ask. A gate that measures something new gets its threshold written
BEFORE it runs, from theory where there is any (`tools/g13_predict.py`
is the shape: a second program, its table frozen beside the threshold),
so the first result never becomes the threshold.
