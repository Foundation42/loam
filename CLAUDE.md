# Working in loam

## Running tests — the default is to run NOTHING

Pick a gate because the change can break the thing it watches, never to
feel reassured. Chris has asked for this in every sibling repo; a suite
run per edit makes the harness the activity rather than the work.

    zig build test -Dtest-filter=straddling   # one gate: 17 s to compile ReleaseSafe, then seconds
    zig build test                            # 105 gates, ~3 min ReleaseSafe — before a commit
    zig build test -Dtest-optimize=Debug -Dtest-filter=…   # the other regime: 2 s to compile, slower to run
    zig build test -Dtest-optimize=ReleaseFast              # the delta, when Christian asks for it
    zig build verify-dump                     # loam-run writes a dump, the struple PYTHON port reads it
    zig build py-test                         # the ctypes binding, and G1 across two PROCESSES
    zig build run -- --units 8 --steps 40     # the step through work(8) calls: the same hash
    zig build run -- --cut 0.5 --steps 40     # CUT: fronts, half the head, finish; the cut on the trace
    zig build run -- --scene junction --steps 40   # a bud junction: the collar's scene (G12); --collar 0 is the hard reference
    zig build run -- --scene coil --steps 80       # a coiling tendril: self-touch, the inner elbow
    zig build test -Dtest-filter="G16"             # the picture's gates: what a hit reads (src/bark.zig)
    zig build run -- --scene marble --steps 110 --volume 64:slice.ppm  # the material seedbed: the marble (sheet veins) as a material field, a colour slice; --scene flecks the first
    zig build run -Doptimize=ReleaseSafe -- --scene marble --steps 110 --rbf 256:marble.lrbf   # the field packed into Gaussians (a tool run; the fit is not a sim measurement)
    zig build run -- --help                   # loam-run, the seedbed
    zig build marl -- --exemplars 200000           # MARL-0: local online RBF learning (docs/MARL_CAMPAIGN.md)
    zig build marl -- --exemplars 1000000 --interference --pgm out/m   # the error field as a picture, and what one event disturbed
    zig build marl -- --optimizer adam             # the instrument: the batch optimiser, and why it is wrong per-exemplar
    zig build test -Dtest-filter="G17"             # MARL-0's gates; python3 tools/marl_predict.py is where their numbers came from
    zig build marl -- --arms                       # MARL-1 (1): birth vs deformation at IDENTICAL capacity
    zig build marl -- --responsibility 3           # MARL-1 (3): who may learn, as against who is summed — a sixth of the work
    zig build marl -- --features 4 --sharpness 2   # MARL-1 (2): the target's complexity, at fixed coverage
    zig build marl -- --coverage 0.10              # MARL-1 (4): the under-birth divergence regime
    zig build marl -- --budget 16                  # MARL-1 (5): saturation, forced
    zig build marl -- --tsv                        # one line of numbers, for driving a sweep
    zig build test -Dtest-filter="G18"             # MARL-1's gates; tools/marl1_predict.py is where their numbers came from
    zig build marl -- --sharpness 2 --hier         # MARL-2: parent + child_delta against flat, on the same exemplars
    zig build marl -- --sharpness 4 --refine 3     # MARL-2: the child's scale — there is an optimum, and past it more is worse
    zig build test -Dtest-filter="G19"             # MARL-2's gates; tools/marl2_predict.py, two of whose five were REFUTED
    zig build marl -- --sharpness 4 --child-birth residual --hier   # MARL-3: residual-driven child birth — under-births into divergence
    zig build marl -- --sharpness 4 --child-birth either --hier     # MARL-3: with the coverage floor kept — six extra births in 4345
    zig build test -Dtest-filter="G20"             # MARL-3's gates; tools/marl3_predict.py, all three of whose numbers were REFUTED
    zig build marl -- --sharpness 4 --route-floor 0.02 --route-gain 3 --hier   # MARL-4: bias the STREAM — concentration 1.65 → 2.50
    zig build marl -- --sharpness 4 --route-floor 0.05 --route-gain 6 --hier   # MARL-4: most of the placement for almost none of the accuracy
    zig build test -Dtest-filter="G21"             # MARL-4's gates; tools/marl4_predict.py, all four of whose numbers HELD
    zig build marl -- --sharpness 4 --arms5        # MARL-5: five arms at one duty — region scheduling loses to per-exemplar bias
    zig build marl -- --sharpness 4 --duty 0.4 --sched hybrid --route-floor 0.05 --route-gain 6 --hier   # the granularity test
    zig build test -Dtest-filter="G22"             # MARL-5's gates; tools/marl5_predict.py, all three of whose numbers were REFUTED
    zig build marl -- --sharpness 2 --drift6 --hysteresis   # MARL-6: move the world at 200k and watch; then move it back
    zig build test -Dtest-filter="G23"             # MARL-6's gates; tools/marl6_predict.py, two of whose four held
    zig build marl -- --responsibility 3 --sharpness 2 --hier   # MARL-6R: the corrected learning unit — same accuracy, a sixth of the work
    zig build test -Dtest-filter="G24"             # the recalibration gate. MARL-7 onward should run at R = 3
    zig build marl -- --sharpness 2 --responsibility 3 --drift-repeat 6   # MARL-7: six moves — accuracy flat, capacity linear
    zig build marl -- --sharpness 2 --responsibility 3 --unrefine 2 --drift6   # unrefinement: precise, and it does not repay
    zig build test -Dtest-filter="G26"             # MARL-7's gate; tools/marl7_predict.py, three of whose four were REFUTED
    zig build marl -- --sharpness 2 --responsibility 3 --unrefine 2 --recycle --drift-repeat 6   # MARL-8: borrow instead of buy — it does not work
    zig build test -Dtest-filter="G28"             # MARL-8's gate: a transplant is inert when it lands
    zig build marl -- --sharpness 2 --responsibility 3 --drift-mode cycle --drift-repeat 12   # MARL-9: revisiting a known world gets cheap
    zig build marl -- --sharpness 2 --responsibility 3 --drift-mode walk  --drift-repeat 6    # …and a new one never does
    zig build test -Dtest-filter="G29"             # MARL-9's gate; it overturned three earlier phases' readings
    zig build marl -- --marble                     # MARL-11: the 2×2 against rbf.fit's batch Adam — the first EXTERNAL baseline
    zig build run -Doptimize=ReleaseSafe -- --scene marble --steps 110 --rbf-arms   # ... the same arms on the REAL marble (a tool run)
    zig build test -Dtest-filter="G31"             # MARL-11's gates; tools/marl11_predict.py, two of whose four were REFUTED
    zig build marl -- --marble9                    # MARL-12: NINE channels on one geometry — two materials, so the sharing can cost something
    zig build test -Dtest-filter="G32"             # MARL-12's gate; tools/marl12_predict.py. The widening's own gate is the suite being UNCHANGED

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

## MARL is not the sim

`src/marl.zig` and `marl-run` are a learning experiment
(`docs/MARL_CAMPAIGN.md`), on `rbf.zig`'s standing: no World, no step, no
fed clock, nothing in any hash, and a separate executable rather than a
flag on the seedbed. Christian's split governs what it may borrow —
Loam's SUBSTRATE (scheduling, publication, deterministic merging, hashing,
lifetimes, the active set) is reusable; Loam's FIELD STORAGE (sample
planes, halos, seams, the B-spline, the Lipschitz summaries) is NOT MARL
storage, because kernels are a parameter list and a seam pass would
interpolate them. MARL's kernel is a deliberate TWIN of `rbf.zig`'s, held
to it bit for bit by G17 (a): a learning experiment must not be able to
move the kernel out from under rill and the shader.

Two distinctions MARL will not survive losing. SUPPORT is the full cutoff
gather and prediction always sums it, so inference semantics never move;
RESPONSIBILITY is the subset permitted to take a gradient, and the NLMS
normaliser Σg² is taken over that subset alone (G18 c). And BIRTH is
topology acquisition while DESCENT is geometry adaptation — they are
measured apart, at capacity held identical, or the number measures both
(G18 a). MARL-2 adds a third: REFINEMENT is representational capacity, and
a child learns `target − parent(x)` with the parent FROZEN, so what the
child holds means "what the level above could not represent" (G19 a). Two
of MARL-2's five pre-registered numbers were refuted and are left standing
in `thresholds.zig` for Christian to strike — refinement turned out to be
region-granular rather than structure-granular, and more capacity is not
monotonically better. MARL-3 then established that the birth criterion is
not where that failure lives: **capacity concentration is bounded by
EVIDENCE concentration**, because a birth can only happen where an
exemplar is, and the child's stream is uniform over the refined region
(G20 c). The coverage rule turns out to be a TRAINABILITY floor as much as
a placement rule — removing it walks into MARL-1's over-responsibility
regime by a third door. MARL-4 then changed the STREAM —
`p(route) = min(1, floor + gain·|residual|)` — and capacity concentration
finally moved, 1.65 → 2.50, rising with sharpness as it should (G21). The
price is the campaign's fourth sighting of one invariant: **capacity you
cannot train is worse than capacity you do not have.** Every mechanism
added for placing capacity better has been paid for in the evidence
available to fit it, and RMS tracks updates-per-kernel monotonically.
MARL-5 then asked whether a scheduler could spend that budget better and
the answer was no: a region is a sixth of the domain across and the
structure is a fortieth of it thick, so **a region-level schedule is
coarser than its own signal** (G22 a). Loam's R17 correspondence is
therefore NOT earned — Loam schedules bricks because a brick is its unit
of work; MARL's unit is one exemplar. And the sharpest form of the
invariant: uniform routing at 40% duty is FLAT across a fourfold rise in
exemplars, so spreading a fixed evidence budget evenly does not slow
learning, it stops it. MARL-6 then moved the world, and the premise
survived better than expected: **freezing is vindicated** — letting the
parent keep learning where the child learns makes the pair much worse
(0.0666 against 0.0491), because the child is learning `y − parent` while
the parent moves under it. What does not survive is COMMITTED CAPACITY:
91% of pre-move child kernels end outside the current band, refinement
precision against the current target falls to 0.62, and moving the world
back gives the same spike as moving it away — no memory, only
accumulation. Erosion (§15) has its first concrete motivation.

MARL-6R then repaid the responsibility debt and separated something the
campaign had been reading as one thing: **under-BASIS-DENSITY is the
catastrophe** (mean |w| of 13–17, three doors) while **under-EVIDENCE is a
gradient, not a cliff** — six updates per kernel is merely less accurate,
not pathological. They were coupled only because a sparse basis also means
fewer kernels overlap. So an erosion mechanism that removes kernels must
hold density; one that merely stops feeding a region need not. The default
stays at full support for comparability, but **MARL-7 onward should run at
`--responsibility 3`** (G24: 0.980× the RMS for 0.184× the work).

MARL-7 went looking for erosion and found there is nothing to erode. The
capacity a moved world leaves behind is LOAD-BEARING — silencing it costs
1.4–1.6× the RMS — and its weights do not separate it from capacity born
since, so kernel death has nothing to target (G26). Unrefinement was built,
fires precisely, and does not repay at any sensitivity or horizon. Over six
consecutive moves accuracy is FLAT while capacity grows linearly at about a
thousand kernels per move, and unrefinement changes that by 1%. So: **the
pathology is not that old representation goes bad, it is that new
representation is always bought rather than borrowed.** MARL-8 is reuse,
not erosion — and the obstacle is that exact locality is precisely what
stops a kernel being re-pointed.

MARL-8 tried that reuse, by recycling a retiring region's child into the
next region to refine. **It does not work**: population went UP 4.5%,
accuracy was untouched at every timescale including the recovery
transient, and donor selection made no difference. The reason is worth
keeping — MARL-1's "deformation buys 2.15×" accrues over a run of fitting
geometry TO ITS OWN LOCAL DATA, so it is not a startup cost that can be
pre-paid. **Geometry is cheap to acquire locally and worthless imported.**
What survives is one design decision, gated: a transplant is INERT when it
lands (weights reset, prediction unchanged bit for bit), so it can never
be actively harmful. `--recycle` stays, default off.

MARL-9 then answered the fixture question and **overturned three phases'
readings**. Cycling between two worlds against walking to six, same six
moves: the walking arm's marginal cost is flat at ~2100 kernels a move
while the cycling arm's decays to 159 by the twelfth, and cycling is also
more accurate. So **capacity is paid per THING LEARNED, not per change**
— the model pays in full for structure it has never seen and almost
nothing for structure it has. MARL-6's "no memory" was the transient
mistaken for the settled state; MARL-7's "always bought, never borrowed"
was true only of novel structure; and MARL-8 failed because the
architecture already reuses on recurrence with no mechanism at all. A
campaign that has only tested one kind of world cannot tell what its
numbers are counting.

MARL-10 then settled the last open end with a fitted LAW rather than a
threshold: `n·ΔK` is flat at 2034, so growth is `K₀ + A·H(N)` —
**logarithmic**. Eighty moves reached 16 241 against the law's 15 726
(1.033×) where a linear tail would have reached 23 396, and RMS IMPROVED
across the run (0.02635 → 0.02237, ratio 0.849). The model pays A/n for
the n-th visit to a world it knows: full price once, a decaying remainder
after, and it ends more accurate than it began. Not gated — eighty moves
is ten minutes; reproduce with
`zig build marl -- --sharpness 2 --responsibility 3 --drift-mode cycle --drift-repeat 80`.

MARL-11 then measured the campaign against something it did not write, for
the first time in eleven phases: `rbf.fit`'s batch Adam bake, same kernel,
same cutoff, same evaluator, on a real material field. The bridge is
`src/marble.zig`, a third file importing both and imported by neither —
`marl.zig` must not learn what a `bark.Volume` is (that is the field-storage
half of Christian's split) and `rbf.zig` must not learn what a `marl.Model`
is (it is cross-repo pinned). MARL itself needed NO changes: `observe(x, y)`
has always taken an external exemplar.

The design is a 2×2 at matched capacity and equal distinct data, because
`rbf.fit` carries two oracles MARL has no equivalent of — it seeds centres
ON veins and draws half its pool FROM them. **Capacity concentration held
almost exactly** (4.17 measured against 4.11 predicted from the fixture's
geometry): a real field's matrix is EXACTLY zero, an empty model predicts
EXACTLY zero, so §8's quiet slab arrives on a field nobody designed to
have one, and MARL out-places blind batch Adam 4.17 to 1.33. **And it loses
anyway, by 1.99 — the headline was pre-registered at parity so that it
could be refuted, and it was.** Both halves of the prediction's reasoning
were right; what was wrong was assuming PLACEMENT was the binding
constraint, which ten phases of placement work makes very easy to hold
without noticing it is an assumption. What binds is EVIDENCE: over a
64-fold stream the RMS falls 0.143 → 0.051 and crosses both rbf arms while
concentration does not move. **The online learner is not a worse fitter
than batch Adam, it is a hungrier one — and it buys KERNELS rather than
passes to get there** (3 285 against 1 583). One more sighting of MARL-7's
"capacity is always bought", now in a stationary world.

Two cautions the phase paid for. Raw concentration DOES NOT TRAVEL between
fields: its ceiling is 1/f, so the real marble's 27.6% band caps it at 3.62
where the fixture's 9.4% allows 10.67, and MARL's raw 1.88 on the marble is
a BETTER 0.52 of ceiling than its raw 4.24 on the fixture (`report` grew a
`/ceiling` column for exactly this). And a `mo.m = o.m` in the harness
silently ran the first external baseline at the responsibility radius
MARL-6R had already retired — it cost nothing, which was luck.

The conversion is gated bitwise: a model on the unit cube becomes an
`rbf.Set` in a volume's units by μ′ = Eμ, L′ = L/E, EXACT in f32 for a
power-of-two extent because rounding a difference commutes with scaling by
one. So a MARL model IS the asset a renderer loads, not something close to
it (G31 a).

MARL-12 then widened the kernel from one weight to C of them —
`pub fn Marl(comptime C: usize) type`, with `Scalar = Marl(1)` and a facade
of aliases under the plain names, so **no call site anywhere changed**.
Weights sit at `p[W..W+C]` INSIDE the kernel, because a runtime channel
count would cost a cache miss per kernel per step on a path that touches
ninety kernels an event. The refactor's gate is not a threshold: at C = 1
every number the campaign recorded is IDENTICAL, checked by diffing the
whole suite, and G31 (a) still reads bit-for-bit equal. Two things had to
be written deliberately for that — the channel magnitude is a MAX (which is
`@abs` at C = 1, and is also Loam's R15 semantics), and the geometry's
attribution accumulates FROM channel 0 rather than from a zero, because
`0 + (−0.0)` is `+0.0` and a sign of zero there reaches `moveCentre`.

The finding is a scaling law the campaign could not have met before.
**The geometry's step grows as √C**: the centre and shape descend on
`Σ_c w_c a_c`, one term per channel, and at the C = 1 rate nine channels
DIVERGE in exactly MARL-1's shape — the vein-biased arm births 3 666
kernels against the uniform arm's 1 896 and scores WORSE with them (0.629
against 0.352). `rate/√C` is stable; `rate/C` was tested and is slightly
worse, which is the evidence that the growth is √C rather than merely that
something smaller was needed. It lives in the code as `Ch.GEOM_RATE`, a
division by exactly 1.0 at C = 1, and G32's mutation undoes it and fails.

With that correction, nine channels are close to free: **K(9)/K(1) = 0.997**
(a birth is gated by COVERAGE, which is a max over gaussians and knows
nothing about channels, so nine cannot buy a birth one would not), the
blend's own error is **0.987** of what it is learned alone (the eight
others are extra constraints on where a centre belongs, and they agree),
and a kernel is **18 floats against 90** for nine separate scalar models.
The fixture carries TWO materials split across x, and that is load-bearing:
with one, every channel is the blend times a constant, the nine are exactly
collinear, and a shared basis is free by construction — a fixture that can
only agree is not a fixture.

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
