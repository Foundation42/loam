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
    zig build test -Dtest-filter="G33"             # MARL-13: the occlusion cache — the first NOISY field; tools/marl13_predict.py, two of whose three were REFUTED
    zig build test -Dtest-filter="G34"             # MARL-14: DISTILLATION — sample a built model to train a smaller one; all four numbers HELD
    zig build test -Dtest-filter="G35"             # MARL-15: QUANTIZATION — a kernel ships in 6.75 bytes (region-relative centres)
    zig build test -Dtest-filter="G36"             # MARL-16: the BIAS term, refuted twice — zero is special because it is the model's DEFAULT
    python3 tools/q3_volume.py --res 160 --out out/oa_spirit3.vol          # MARL-17: a Quake 3 level as a bark.Volume (reads ~/dev/tessera's BSP loader)
    zig build marl -Doptimize=ReleaseFast -- --q3 out/oa_spirit3.vol --exemplars 250000   # ... the occlusion cache on it (a tool run; not gated)
    zig build test -Dtest-filter="G37"             # MARL-18: CONSOLIDATION — distil, replace the master, resume learning. 79 s, four refutations; tools/marl18_predict.py
    zig build test -Dtest-filter="G38"             # MARL-19: the MILK ROUND — a schedule revealed in stages, NOISELESS. 65 s; tools/marl19_predict.py
    zig build test -Dtest-filter="G39"             # MARL-20: a MOVING OCCLUDER — static bake + residual layer. 11 s; tools/marl20_predict.py
    zig build test -Dtest-filter="G40"             # MARL-21: CONTACT — an object resting against geometry. 12 s; tools/marl21_predict.py
    zig build test -Dtest-filter="G41"             # MARL-22: it was never a noise floor — and the shell asks a question nobody makes. 25 s
    zig build marl -Doptimize=ReleaseFast -- --q3 out/oa_spirit3.vol --exemplars 120000 --exterior   # ... and on a real level it makes MARL/grid 0.619 → 0.398
    python3 tools/edge_rbf.py                      # MARL-23: Bresenham's question — how tightly can Gaussians hold an edge? No learner, least squares, outside MARL
    zig build test -Dtest-filter="G42"             # MARL-24: a residual layer wants a COARSER basis than the bake — 25 kernels in 1.0 KiB
    zig build test -Dtest-filter="G43"             # MARL-25: was `regions` wrong everywhere? the clamp read as a diagnostic. 40 s
    zig build marl -Doptimize=ReleaseFast -- --q3 out/oa_spirit3.vol --exemplars 120000 --exterior --regions 4   # the corrected headline: MARL/grid 0.329

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

MARL-13 then built the OCCLUSION CACHE Christian named on the first
morning, and it is the first field the campaign has learned from NOISY
samples — ambient occlusion is a Binomial(M, p)/M estimate, σ = √(p(1−p)/M),
a half at one ray. Three results.

**The learner has a noise floor and it belongs to the RATE.** NLMS with
step μ does not converge on noisy data, it hovers, at μ/(2−μ) of the
measurement variance HOWEVER MUCH DATA ARRIVES — so `RMS² = bias² +
μ/(2−μ)·V/M`, linear in 1/M, held at 1.023 (G33 b). The first thing this
campaign has met that more data does not fix. **(MARL-22 corrects the prose
that grew around this, not the law: the same fit's INTERCEPT is 0.15110
against a total of 0.17174 at sixteen rays, so the error is 77% BIAS. Every
"noise floor" written from here to MARL-21 was a REPRESENTATION floor.)**

**Noise enters by three doors and a rate closes one.** `rate_w` 0.5 → 0.05
is worth 1.29× (the pre-registered floor of 2.0 is REFUTED); adding
`rate_geom` 0.2 → 0.02 takes it to 1.67× and drops the population 11 176 →
7 113. The third door is the TOPOLOGY: births are gated on the raw
surprise, so **the model births on noise** — 9 923 kernels at one ray a
sample against 7 656 at sixteen, same samples. No rate closes that; it
needs a noise-aware birth test, and §5's "do not confuse noise with
complexity" is now a measurement rather than an instruction.

**Against a giant volume texture, at equal bytes and equal rays: MARL
LOSES 1.854× on a volume-filling field and WINS at 0.912 on a shell around
geometry.** Two mechanisms. A hard cutoff makes a Gaussian decay to exactly
zero, so a constant non-zero background must be held up by overlapping
kernels everywhere it extends. Learning `1 − AO` is one negation and worth
1.40× for 14% less capacity. (This originally added that MARL "never grew
the bias term `rbf.zig` has had from the start". **MARL-16 corrected that**
— see below.) And a grid pays memory for every
cell whether or not anything is asked there, while a renderer asks at
SHADING POINTS. So: **a learned sparse field beats a dense grid when the
interesting set is SPARSE IN THE DOMAIN, and loses when the field is
non-trivial everywhere.** The marble's veins were sparse; a volume-filling
occlusion field is not; a shell is.

Honest costs: a cache lookup is 6 651 ns against a texture fetch's 13 — the
27-region gather is exact, not free, and at 9 334 kernels over 216 regions
"local" means ~1 166 kernels. G33 costs ~25 s of suite, most of it the
4 096-ray reference, which stays because the headline turns on 0.912.

MARL-14 is Christian's DISTILLATION idea: sample a built model to train
another. A teacher is two things no field here has ever been — NOISELESS,
which closes all three of MARL-13's doors at once including the topology
one no rate can close, and UNLIMITED, which lifts MARL-11's binding
constraint. (Not MARL-8: a student imports no geometry, it discovers its
own topology from a cheap oracle.) The student is scored against the TRUE
field throughout, never against its teacher.

All four numbers held. Copying at matched options is a FREE 6% of the
population for 5.8% of the accuracy — the capacity MARL-13 measured as
bought on noise, which a clean teacher cannot sell. **Halving the
population costs 14% of the accuracy**, because with an exact teacher the
surprise threshold stops being a risk and becomes a clean accuracy dial.
A coarser basis (`regions` 6 → 3) gives **4.32× fewer kernels — 814 at
31.8 KiB against 3 513 at 137.2** — for a quarter more error. And
GENERATION LOSS DOES NOT COMPOUND: A→B costs 1.058, B→C costs 1.036, the
second copy CHEAPER than the first, because B is a sum of anisotropic
gaussians and that is exactly the student's hypothesis class where the
truth is not.

The unregistered part is the best of it. Against a dense grid AT THE
STUDENT'S SIZE the distilled model scores **0.878**, better than the
teacher's own 0.912: **the learned field's advantage over a volume texture
WIDENS as memory shrinks**, because a grid's error is set by its cell size
and halving memory costs it a cube root of resolution. So: build once at
full fidelity from the expensive noisy source, then distil to whatever the
budget allows.

MARL-15 then asked what any of that is worth COMPRESSED, because every
byte count above is f32 on both sides. Quantization is applied to the
`rbf.Set` — the shipped artefact, bit-identical to the model by G31 (a) —
and never to a live `Model`, whose kernels are owned by regions and would
have their gather silently corrupted by a rounded centre. **A kernel ships
in 8.5 bytes** (8/6/6/10 bits over μ / log-diagonal / off-diagonal /
weight) for 1% of the accuracy: a 4.7× saving, where 54 bits breaks and 40
fails outright.

That is 5× better than `tools/marl15_predict.py` predicted, and the reason
is a method note worth keeping. It is NOT that the weights are small — the
gate prints their span at −0.50…1.38, ABOVE the 1.0 assumed. It is that
**peak sensitivity and peak overlap do not coincide**: the derivative's
maximum is at r = 1 exactly, and a point at r = 1 of one kernel is far out
in the tails of most of the others. A per-element worst case compounded
over an assumed overlap count multiplies two things that never happen
together, and is not conservative but wrong.

The ablation also said WHERE: the centre is the only expensive field
(0.01872 of excess at 8 bits against the weight's exactly ZERO), and its
cost is a SPAN choice. A kernel's centre is inside its owning region by
definition, so the span is `extent/regions` — and `setOf` already writes
kernels in region order, so only a u16 count per region need be stored.
**Region-relative centres cut the centre's excess 6.16×** (geometry said
3.0; read the numerator, the relative excess is at the edge of what 512
probes resolve). That makes **54 bits — 6.75 bytes — a kernel** the
production encoding, at NO MEASURABLE COST (0.995×) where the same budget
with absolute centres cost 8.6%. **5.93× on f32.**

So the headline goes the other way from the derivation, and keeps going:
**0.878 in f32 → 0.859 at 8-bit absolute → 0.804 at 54-bit
region-relative** — the last against a grid given MORE than its share,
because a cubic grid cannot land on a byte budget (17³ is 4.8 KiB, 18³ is
5.7; both are measured and the gate asserts the generous one). Every step
of compression moves the comparison further in the packed set's favour,
because **an adaptive basis compresses better than a uniform one: adaptation
narrows the dynamic range every field has to carry.**

MARL-16 then built the bias term MARL-13 said was owed, and **refuted it
twice.** A bias from the RESIDUAL never converges (the kernels absorb the
background long before a 1/n step reaches it — b strands at 0.1057) and
scores 1.302×. A bias from the TARGET converges correctly to 0.7211, the
field's actual mean, and scores **5.679×**. *The better estimator being the
worse model is what says the fault is not in the estimator.*

The mechanism: a Gaussian basis with a hard cutoff cannot cheaply represent
a plateau of ANY value. **Zero is not special because it is zero — it is
special because it is what an empty model already predicts**, so a target
that is zero over a large region costs literally nothing. A bias moves that
free value from 0 to b, helping where y ≈ b and hurting everywhere y ≈ 0,
which must now be held DOWN. Measured: 0.123 of the field within θ of zero
against 0.049 within θ of the bias — a losing trade by 2.5×, and G36
asserts that inequality rather than the refuted thresholds, so if it flips
on another field the bias should be tried there.

**And a claim of mine needed correcting.** `rbf.zig`'s "entry" is NOT a
learned constant — it is the HOST's material, supplied per hit, showing
through where the kernels are silent, with the kernels carrying a blend
that is ZERO in the matrix. That is exactly what MARL already does. MARL
was never missing the term.

What DID hold is the trade, now priced: one late event moves distant probes
by exactly 0.00 without a bias (exact locality, bitwise) and by 2.26e-6
with one, so disturbance × n / |e| = 0.272. The campaign CAN buy a
background at the cost of asymptotic rather than exact locality — it is
just not worth it where the zero mass is large. `BiasRule` stays,
defaulting `.off`, with both failures written into the enum.

MARL-17 then put the whole thing on a REAL Quake 3 level (`oa_spirit3`,
via `tools/q3_volume.py`, which reads `~/dev/tessera`'s BSP loader and
rasterises the world's solid BRUSHES to signed distance — a brush is a
convex intersection of half-spaces so its distance is exactly
`−maxᵢ(nᵢ·p − dᵢ)`, positive inside). Two things had to be right: the clamp
is ±3 CELLS not ±3 units, and rasterisation must be CONSERVATIVE — Q3 walls
are 8–16 units against a 28.8-unit voxel, so centre-sampling drops most of
them and the level LEAKS (2.8% solid against 3.9% grown, converging at
higher resolution). A level the grid cannot seal has no occlusion to study.

**And every RMS before this was quoted without an anchor.** Predicting the
mean everywhere scores 0.26448 on this query set; that is now reported
beside every arm, because an RMS without it is a number with no scale.

    MARL, online            1 614 kernels  63.0 KiB  0.12011  2.20× a constant
    dense grid, trilinear   25³            61.0 KiB  0.20397  1.30×
    → MARL/grid 0.589, against the grove's 0.804

The margin is far bigger than the synthetic fixture's, for exactly the
reason MARL-13's rule predicts: the level is 3.9% solid and queries sit two
voxels from a surface, so the interesting set is a thin shell in a mostly
empty cube. **The pipeline end to end — distil (MARL-14) then quantize
(MARL-15) — is 340 kernels in 2.3 KiB at 0.15807, which is 27.1× off the
master for 1.32× the error and 0.418 of a same-sized grid's.** At two
kilobytes an 8³ grid is WORSE THAN PREDICTING THE MEAN.

Two things the numbers do not say. Nothing here is a good fit absolutely —
the master is 2.20× a constant — and some of that ceiling is the occluder's
own 28.8-unit voxels. And a DENSE grid is the baseline `rbf.zig` was
written against, not the best a renderer could do: nobody stores a dense
grid over a level's bounding box, they cluster probes near surfaces, and
that sparse structure is a harder opponent that was not measured.

MARL-18 is Christian's wake/sleep idea: distillation as a LEARNING step
rather than a deployment one — distil, put the student in the master's
place, resume ordinary learning, repeat. Its stated premise was that
MARL-14 had shown a student beating its teacher. **It had not**: every row
of G34 goes the other way (1.058 rising to 1.141), and the 0.878 that
reads like the claim is the student against a SAME-SIZED GRID — a
statement about the opponent. The idea survives and sharpens, because
MARL-14 distilled a model and STOPPED; whether a student is a worse PLACE
TO LEARN FROM had never been run.

**A student cannot beat its teacher — except when the teacher is
noise-limited.** At sixteen rays the best of a coarseness sweep is 1.043;
at one ray every student wins, best 0.960, and a basis with a third of the
kernels still 0.971. A student fits its teacher's OUTPUT and has no access
to what the teacher got wrong, so the only way it can come out ahead is by
FAILING to reproduce part of it — the low-pass argument, whose signature is
the shallow U across the sweep (0.962, 0.960, 0.971). **A copy is a filter,
and it is worth something exactly when the original carries noise.**

**A consolidation CONCENTRATES rather than untangles.** The edit vocabulary
is measurable as overlap-ratio over population-ratio, so that a uniform
thinning scores exactly 1 and Christian's A + B + C + D → X + Y would score
below it. It scored **1.606**: at one ray the student sheds a third of the
population while RAISING crowding per kernel. Low-contribution kernels are
retired; the survivors sit where the queries are.

**The staircase is real and it tracks the noise.** Two arms on ONE reality
stream in one order, the control through the identical code path at
`sleeps = 0`: at sixteen rays three sleeps COST 1.011× (generation loss
with nothing to filter), at one ray they BUY 0.898× and a third of the
population, and the gradient — the saving in the noisy regime over the
clean one — is **1.432**, which is what makes the mechanism a claim rather
than a coincidence.

**Then the control refuted the phase.** Against the consolidated arm's
0.21430 at 3 671 kernels in 11.6 s: four times the reality reaches 0.21976
but at 2.2× the population (the third door again), and **`rate_w`/10 with
`rate_geom`/10 reaches 0.18474 at 3 142 kernels in 1.5 s** — better on
every axis, eight times cheaper. MARL-13's "no rate closes the topology
door" was about `rate_w`; moving `rate_geom` closes it too, because a
kernel that does not chase a noise realisation geometrically stays where it
can cover. The arms had been run at G33 (d)'s configuration, which pins
`rate_geom` to the default DELIBERATELY so its headline is not configured
from its own result — right for G33, wrong for a phase asking whether
consolidation beats the best available LEARNING.

So G37 (c) re-ran it at MARL-13 (c)'s own rates, on a number frozen before
the run that gated a decision. **REFUTED at 0.940**: three sleeps still buy
six per cent of the accuracy and four of the memory on top of the cheap
fix. The win SHRANK from 0.898 to 0.940 rather than vanishing, which is the
one story every number here fits — **a sleep is worth exactly as much as
there is variance to remove**, and a rate is the UPSTREAM way not to carry
it, not a substitute for the downstream one. The sentence:

    Turn the rates down before you consolidate. It is better and eight
    times cheaper. Then consolidate anyway, because it still pays.

And at the right rates a sleep no longer restructures anything — overlap
2.30 → 2.22, mean σ 0.0278 → 0.0284, population 0.961× — so what it
performs is a **RE-FIT**: the same population, better placed and better
weighted, because the last fit it saw was against a noiseless field. The
1.606 concentration belonged to the handicapped regime, where there was
something to retire.

Honest costs: the sleeps are **5.6× the wall clock of the learning they
improve**, and that is the pessimistic end — one ray a sample is the
cheapest reality there is (~20 marched fetches against a real estimate's
~320), so this fixture's reality is ~16× cheaper than a renderer's. G37 is
79 s of suite, more than any gate the campaign has added.

What is NOT tested is what MARL-9 would ask about: one fixture, one field,
STATIONARY, and every result about MEASUREMENT noise. The tangle the plan
describes is what MARL-7 measured on a DRIFTING world — a thousand kernels
a move at flat accuracy, unrefinement moving it by 1%. **Distillation is a
candidate for the erosion mechanism MARL-7 could not find**, and for a
reason MARL-7's instrument could not see: it concluded "kernel death has
nothing to target" because every kernel is individually load-bearing, and
four overlapping kernels whose sum is smooth are all individually
load-bearing and collectively replaceable. **A consolidation never chooses
a victim — it declines to rebuild one**, which moves the unit of removal
from the kernel to the local function. That is the next experiment.

MARL-19 is Christian's clarification of the same idea — the milk round.
Told Monday, you buy a kernel; told Wednesday too, another; told Tuesday,
Thursday and Friday, and you already have kernels refining the parent. The
sum is "deliver Monday to Friday", and the student is handed the sum, never
the patches. That names a SECOND CURRENCY — history — which MARL-18's
fixture could not have seen, because one stationary field learned from a
noisy estimator leaves noise as the only thing a teacher can carry. So
`src/milk.zig`'s target is ANALYTIC AND EXACT.

**The premium is not there.** At equal total evidence the incremental arm
carries FEWER kernels than a from-scratch one (6 094 against 6 709) and is
simply behind (0.05791 against 0.04351) — it spent two thirds of its budget
on schedules with less structure in them. **Nothing it learned became
wrong**: Monday is delivered at every stage, so the reveal is NESTED and
MARL-9's law applies in its cheap direction. And MARL-16 covers the only
obsolete structure there was — the Tuesday hole sat at ZERO, which is what
an empty model already predicts, **so holding the hole down never cost a
kernel and there was nothing to cancel.**

**Nor does contradiction help.** A path that delivers Monday and Tuesday,
STOPS, and starts again costs 1.092× a path that only ever adds — and is
more accurate for it. History is nearly free in MARL whatever shape it has;
pulling a weight to zero is cheap, and the kernels left behind are few
against a population set by tiling the support.

**And a sleep on a noiseless field is a pure loss.** A copy costs 1.179×,
and with the dream PINNED to the teacher's own evidence it RAISES the
population on both paths. The θ frontier makes it precise: 1.041× kernels
at 1.266× RMS, 0.890× at 1.268×, 0.736× at 1.327×, 0.528× at 1.636× —
**no student is better than its teacher on both axes**, where MARL-14's
noisy field gave 0.937× the kernels for 1.058× the RMS. "Smoother ground"
does hold (0.976 for one sleep, 0.960 for a sleep every stage) but the
slept arms end 11% LARGER, and RMS tracks capacity.

**And then G38 (d) found the precondition the whole phase had been missing.**
Christian's actual framing is the guitar: hit a wall of improvement, step
away, come back and improve again on consolidated memory. Run with the
target fixed, the dream pinned, and the straight arm's RMS printed every
period so the wall would be visible — **there is no wall.** It gains 0.0039
in its last period and is still climbing, so the rested arm's 1.023× is not
a result, it is a test whose precondition failed.

Which reframes everything. **Where does MARL plateau?** MARL-13 (b) had
already answered it: on a NOISY field NLMS hovers at `μ/(2−μ)·V` however
much data arrives. That is the only wall in this system; on a noiseless
field MARL-10's logarithmic law keeps paying out and there is nothing to
step away from. So:

    MARL's plateau is made of VARIANCE.

"A sleep is worth as much as there is variance to remove" and "a rest helps
once you have hit the wall" are the SAME SENTENCE — and MARL-18's one-ray
arm was already the guitar, run at a real wall (its trace goes backwards
mid-run, 0.22455 → 0.23232, which is hovering) with three rests ratcheting
it to 0.940× after the best available rates. MARL-19's negatives are not
evidence against consolidation; they are the BOUNDARY of where it applies,
and the boundary is the wall.

Christian's picture of the representation is right — the sum is simpler
than the patches. What is wrong is the assumption that MARL *paid* for the
patches; it mostly did not, and MARL-9 and MARL-16 had already closed that
door. The analogy was never a spec for a fixture, and building it as one
was a category error worth recording: a refuted instantiation is not a
refuted principle.

One method note, and it is the harness's fault: the dream sample count is
an EVIDENCE DIAL. Invisible on a noisy target, where what a student
rebuilds is bounded by what its teacher got right; decisive on a noiseless
one, where it sets the student's population directly. Pin it to the
teacher's own evidence.

MARL-20 built Christian's §7: a baked static MARL for the world plus a
RESIDUAL layer for what moved, `F = M_static + Σ M_dyn_i`. It is MARL-16
cashed, and MARL-16 was a refutation at the time — *zero is special because
it is what an EMPTY MODEL ALREADY PREDICTS* — so a residual layer, which is
zero everywhere the world did not change, is the exact shape of field this
representation is free on.

The estimator matters: `aoPair` marches ONE set of directions and returns
both fields, because a mover only ADDS occlusion, so a ray that already hit
the level contributes exactly zero to the difference. **A residual is
cheaper to measure than a field.**

**The layer is free and the composition is an identity.** A 4.2-unit
occluder's residual is **283 kernels in 11.1 KiB against a full re-bake's
2 603 in 101.7**, built from an eighth of the rays in a tenth of the time.
On probes drawn in the object's neighbourhood: stale bake 0.16257, full
re-bake 0.14239, **static + residual 0.14957** — within five per cent of
re-baking the whole scene. `1 − AO_pert = (1 − AO_static) + (AO_static −
AO_pert)` is an identity, so only the two fits can be wrong.

**And the move answers MARL-7 and MARL-8.** Four moves, adapt-in-place
against discard-and-rebuild at equal work. The accuracy is
indistinguishable (1.013, 0.982, 1.008, 0.992 — no trend). The POPULATION
is the answer, and it is MARL-7's shape exactly: adapting grows ~200 kernels
a move, LINEARLY, at flat accuracy (493 → 697 → 887 → 1 086) while
rebuilding is FLAT (296 → 285 → 278 → 284). **After four moves the adapting
layer is 3.82× the size for the same error.**

    You do not need an erosion mechanism when the thing is small enough
    to throw away.

MARL-7 spent a phase looking for erosion and found the accumulated capacity
load-bearing with nothing to target; MARL-8 tried reuse and failed. Three
phases of failure resolved by a fourth phase's refutation, and only because
MARL-16 made the layer free where nothing changed.

Method notes, recorded because they nearly cost the phase. TWO NULLS: a 2.0
mover at a face centre disturbed 2% of the query set, and a 3.5 mover moved
the truth by 0.0334 against a model error of 0.14. THE DENOMINATOR: a global
probe set is diluted by construction — 24 of 512 probes landed where
anything changed, and an RMS over 24 probes is sampling noise — so the
numbers are taken over probes drawn IN the object's neighbourhood, with the
global ones printed beside them so the dilution is visible rather than
chosen. And a VALIDITY BAR nearly became a tuned threshold: a round 1.15×
that the measurement landed 0.7% under, replaced by one DERIVED from
`TRUTH_RAYS` (σ ≤ 0.5/√4096 = 0.0078; measured gap 0.0202). The arms were
also first run with `rate_geom` at the default — exactly the handicap
MARL-18's own control had caught hours earlier.

Honest limit: the effect is MODEST (the object degrades the local bake by
1.142×, not by a factor), because occlusion in a dense grove is dominated by
the grove. The case that would show it properly is CONTACT — an object
resting against geometry — and it is untested, as are object-local frames
(§8), a scheduler (§10) and a second mover.

MARL-21 took MARL-20's residual layer to CONTACT — a 3.5-unit occluder
RESTING against a grove sphere, which is the case a renderer actually has
and where an object subtends nearly a hemisphere. All four numbers refuted,
and the phase is worth more for it.

**The physics is right and stronger than the floor said.** Stratified by
distance from the object's surface, mean |Δ| runs 0.2455 / 0.0921 / 0.0449 /
0.0108 over bands 0–1, 1–2, 2–4 and 4+. Contact is **0.2455 where contact
happens**, 2.5× the floor it failed as a ball average of 0.0401 — because
38% of the probes sit in the outermost band seeing nothing.

    The affected ball is the SUPPORT, not the SCALE.

A residual's support and its magnitude have entirely different geometries.
This is MARL-20's dilution mistake made again, one level in, inside the
region introduced to fix it — twice in two phases, so it is a rule now.

**And MARL-4's mechanism does not rescue the headline.** Uniform-in-VOLUME
sampling spends evidence in proportion to r², so the layer put ~38% of its
samples where |Δ| = 0.0108 and 2% where |Δ| = 0.2455. Drawing the radial
offset uniformly in DISTANCE instead needs no tuning constant and exactly
cancels the r² — and bought 0.7% (1.030 → 1.023). The reason is the
phase's real finding:

    A residual layer is bounded below by the static bake it sits on.

The composed prediction is `static + residual`, so its error carries the
static model's own fit error on the base field (0.15078 here) while the
residual can only remove the disturbance's contribution (mean 0.0401). **A
full re-bake wins locally because it RE-FITS THE BASE as well**, not
because it fits the disturbance better, and no sampling rule applied to the
residual can touch the dominant term.

So §7 is validated on its real merits and refuted on the one it was hoped
for: its value is MEMORY, BUILD TIME and UPDATE COST — a tenth, an eighth
and a tenth, with a flat population under motion — and never accuracy.
Which is the right trade anyway: nobody re-bakes a level because a crate
moved.

MARL-22 answered a question of Christian's — *"seems like the RBF might
need a higher dimension? like it's struggling to represent?"* — and he was
right about the diagnosis and wrong about the cure, which is the best kind
of question to be handed.

**It was never a noise floor.** G33 (b) had already measured it: the same
fit's INTERCEPT, the error with all measurement noise removed, is 0.15110
against a total of 0.17174 at sixteen rays. **77% bias.** Every 0.15 in the
prose from MARL-13 to MARL-21 was mislabelled. The law held; the sentences
around it did not.

**And a third of the query set was a question nobody asks.** The shell is
drawn on `|φ| < band`, which STRADDLES the surface, so 35% of probes sit
INSIDE solid where `aoAt` returns exactly 0 — and under `invert` that is a
plateau at 1.0, MARL-16's expensive object. **A renderer never shades inside
a wall.** It was there for no reason but the shape of the test.

Deleting it on the grove gives 0.06651 against the full-shell model's
0.13836 — and the ANCHOR says do not celebrate: a constant scores 0.06870
there, so the exterior arm is **0.968× a constant** where the full-shell arm
is 0.446×. *Almost all of the cache's apparent skill on the grove's shell
was learning that a point inside a wall is occluded, which the geometry
already knows.* MARL-17 introduced the anchor rule for exactly this and the
gate still pre-registered a threshold that ignored the number it was
printing.

**But on a REAL level it goes the other way, and MARL-17 was UNDERSTATED.**
The grove's exterior shell is flat because it is a lattice of identical
spheres; `oa_spirit3`'s is not. Same volume, same budget:

| query set | a constant | MARL | vs constant | MARL/grid |
|---|---|---|---|---|
| straddling (MARL-17's) | 0.26448 | 0.12976 | 0.491× | 0.619 |
| **exterior only** | 0.20617 | **0.06021** | **0.292×** | **0.398** |

**The learned field's advantage over a dense grid nearly doubles when you
stop asking it about wall interiors.** The fix is one line and free.

**And the cure Christian proposed is refuted.** `regions` 6 → 12 gives 9 711
kernels against 1 989 and the fit is 1.392× WORSE. **The basis does not need
more resolution; more resolution makes it worse** — fifth sighting of
MARL-1's invariant, pointing at MARL-11's law for the remedy: what binds is
EVIDENCE. (`invert` was also re-tested and matters MORE on an exterior shell,
1.655×, so MARL-13's choice stands for its original reason and not for the
plateau.)

Nothing measured above is retracted — every arm was compared on the same
query set, so the RATIOS stand. What changes is the reading: those absolute
RMS figures are dominated by a discontinuity, and MARL-20/21's static bake
was representation-limited rather than noise-limited, which is why more rays
never helped it and why a residual layer could not get under it.

MARL-23 is Christian's Bresenham thread, run OUTSIDE MARL in
`tools/edge_rbf.py` — no learner, analytic placement, least squares by SVD,
so what the BASIS can do is separated from what the LEARNER finds. MARL-22
had just made that the important distinction.

**Bresenham's law, and it is exact until it is a cliff.** Measured as how
FEW kernels reach a fixed accuracy: on a straight edge the saving is exactly
the aspect ratio, one for one (aspect 1/2/4/8/16 → 64/32/16/8/4 kernels). On
a curve it is linear up to a HARD CLIFF past which no kernel count works at
all. The cliff obeys the sagitta scaling with a constant that holds to 8%
over a fourfold range of curvature — 0.316, 0.365, 0.316, 0.315 at R =
0.4/0.3/0.2/0.1:

    max usable aspect ≈ 0.32 · √(2R / σ_n)

0.32² ≈ 1/10, so: **a kernel may run straight until its sagitta reaches a
TENTH of its own normal width** — an order of magnitude tighter than "until
it leaves its own support", which is the bound you would write first and
which is wrong by 3× in aspect.

**Kernels on an edge cannot represent a step at all** — the first sweep
scored 1.407× a constant, because the plateau IS the error. MARL-16 arriving
before the experiment started, which is why every edge number here is taken
on a RIDGE.

**Coarse + residual is NOT cheaper to REPRESENT.** At equal total kernels
against a uniform tiling, with the residual's width swept: 1.06×, 1.08×,
0.82×, 0.95× — a wash. MARL-21's ceiling confirmed with no learner, no
noise and no evidence limit. *A layered decomposition is cheaper to UPDATE,
and that is the whole of its value* — which MARL-20 priced at a tenth of the
memory, an eighth of the rays and a flat population under motion.

**And a SECOND mechanism for "finer is worse".** MARL-22 blamed MARL-1's
invariant (capacity you cannot train). Here there is no learner and
unlimited evidence and finer is still worse — and the FIT error rises too,
which a least-squares fit cannot do on more parameters unless the system is
rank-deficient. **A Gaussian basis much finer than the feature is nearly
linearly dependent**, so the extra kernels are unusable at any evidence.
Two mechanisms, different remedies, and only MARL-1's is fixed by more data.

What it says about the question that prompted it: an extra dimension on the
residual layer would not buy representation, because the split itself does
not. What WOULD is an anisotropic kernel aligned with the surface — already
expressible in MARL's kernel. **The open question is not whether the basis
can hold an edge tightly (it can, one kernel per 0.32·√(2Rσ) of arc) but
whether the NLMS geometry step ever FINDS that orientation.** That is a
learner question and it is the next thing to measure.

MARL-24 came out of Christian asking what a residual layer actually holds.
The target is small and broad (mean 0.0502, max 0.4297) and the weights span
−0.2082…0.3192 at mean |w| 0.0643 — a QUARTER of the static model's span,
which matters because MARL-15 quantizes weights over one global span.

But one line was not a curiosity: **σ spanned 0.02858…0.02946 against a
σ_max of 0.02946 — every kernel pinned at the widest the clamp allows.** The
descent wanted them wider and could not, because σ_max = h/√CUTOFF and the
layer had inherited `regions = 6` from the static bake beside it. MARL-23
from the other direction: the optimum width is the FEATURE'S own, and a
residual is smoother than the field it corrects.

G42 confirmed it on MARL-21's CONTACT fixture — deliberately the harder
case, since the observation came from the corridor:

| regions | kernels | KiB | composed | widest/σ_max |
|---|---|---|---|---|
| 6 | 206 | 8.0 | 0.14689 | 1.0000 |
| 4 | 96 | 3.8 | 0.14625 | 1.0000 |
| 2 | **25** | **1.0** | **0.14347** | 0.9991 |

Both numbers held (0.466 and 0.996) and coarsening is MONOTONE all the way
down — 25 kernels in 1.0 KiB beats 206 in 8.0. The last column is the
mechanism confirming itself: hard against the stop at 6 and 4, coming off it
at 2.

**So MARL-20's headline improves with no new mechanism.** Against its full
re-bake of 2 603 kernels in 101.7 KiB, a residual layer is **104× fewer
kernels and 100× less memory** at better accuracy than the layer it
replaces. It had been carrying eight times the capacity it needed because it
borrowed a number from a neighbour with a different job.

Method note: the corridor numbers came from an INSPECTION, before any
threshold was written. They are recorded as an observation and the gate was
pre-registered for a different fixture, which is the only honest way to
promote something noticed by accident.

MARL-25 took MARL-24's diagnostic — **the share of a population within 1% of
σ_max** — and pointed it at the arm every occlusion phase has used. A
population hard against the clamp is one the descent wanted WIDER and could
not have, so `regions` is finer than the target needs. G37 (c) had printed
the static bake's mean σ at 0.0278 against a σ_max of 0.02946 and nobody
read it back.

**The more pinned population is the one where coarsening pays.** On the
grove: the straddling shell is 43% pinned and coarsening COSTS it 7.1%; the
exterior shell is 64% pinned and coarsening GAINS it 5.7%, reaching **four
times less memory and nine per cent better** at regions 3.

**MARL-14 was not wrong, it was measuring a query set with a step in it.**
That phase priced coarsening as a trade (6 → 3 for 4.32× fewer kernels at
1.23× the error) on the STRADDLING shell — and a step is the finest
structure in the target, which is exactly what a fine grid is bought for.
MARL-22 showed a renderer never asks there. The step was not paying part of
the fine grid's price, it was paying all of it.

**On `oa_spirit3`, where the field actually varies**, regions 4 is strictly
better than 6 — 504 kernels in 19.7 KiB at RMS 0.05968 against 1 207 in 47.1
at 0.06021. Past that it becomes MARL-14's trade again (280 at 0.06889, 138
at 0.07617), which is the honest boundary: the free step is one, not three.

So two one-line changes compound through the whole chain:

| | query set | regions | MARL/grid |
|---|---|---|---|
| MARL-17 | straddling | 6 | 0.589 |
| MARL-22 | exterior | 6 | 0.398 |
| **MARL-25** | **exterior** | **4** | **0.329** |

The headline is the f32 MASTER against its opponent, per Christian's ruling
above: **504 kernels in 19.7 KiB at 0.05968, which is 0.289× a constant
predictor**, where MARL-17's master was 1 479 in 57.8 KiB at 0.491×. Neither
change is a mechanism or new maths, and between them they nearly halve the
error relative to the field's own scale.

*(Production, reported apart and not part of the measurement: distilled to
regions 3 and quantized at 54 bits gives 249 kernels in 1.7 KiB at 0.07063,
0.322 of a same-sized grid.)*

One consequence: the distillation dial has less room once the master is
already coarse. From a regions-4 master, 4 → 3 is a 2× population cut for
1.13× the error, where MARL-14's 6 → 3 was 4.32×. The two levers overlap,
and taking the free one first leaves the paid one with less to sell.

Recorded, not built. QAT belongs in the DISTILLATION transfer step
(Christian's, and right) — a student is already re-fitting against a free
noiseless oracle, so snapping to the grid inside its existing `clamp`
costs nothing, and "nothing enters the model unprojected" already describes
it. No headroom at 54 bits; the case is below, where 40 bits measured
1.608. The caution is that kernels MOVE, so the grid shifts under them and
a kernel wanting to move less than half a step never moves. Also owed: the
weights use ONE global span, and MARL-1's divergent regime reached mean |w|
of 13–17, which would waste most of the levels on outliers.

## The ledger

`docs/implementation-notes.md` — every decision made while building, with
the mutation that paid for each gate. Same rules as rill's ledger, restated
at its head. Docs ride the same commit as the code they describe.

`docs/marl-talk.html` — the campaign written up as a GDC-style talk, for
sharing outside the repo. Self-contained: no build step, open it in a
browser. Its hero is a LIVE two-dimensional MARL — the same birth rule, the
same NLMS attribution, the same responsibility radius — rendered by
accumulating each kernel over its own cutoff box, which is the locality
argument the whole technique rests on. Every figure in it is a measurement
from a gate in this repo. Published at
https://claude.ai/code/artifact/0fd1946b-9a53-482a-8c7e-82a1ed3871df

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
  is a signed implicit, POSITIVE INSIDE, clamped to ±3 cells of the
  brick's gauge; −band is "far", the absent value. (This read "negative
  inside" until MARL-13 needed to ray-march it. `src/tests.zig`'s own
  sheet gate samples `Channel.surface` and prints φ = +2.00 on the
  sheet's axis, +1.28 four units along it, −1.53 two and a half ACROSS
  it, −2.72 nine beyond its width. A marcher written from the old prose
  finds occlusion in empty space and none inside a trunk — a bug that
  renders as a plausible picture.) A contribution is a
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

## Two rulings from the day MARL-20 through MARL-25 ran

**Hyperparameters must not spill.** Christian: "we need to be really careful
with these hyper parameters or experiments spilling over into later things."
No DEFAULT has ever drifted — every gate sets its own — but that is the risk
in its real form, not a defence against it: by MARL-25 eight gates each wrote
`rate_geom = 0.02` as a literal while four older ones did not, so what the
campaign currently believes was recoverable only by reading every gate in
order. `cache.Options.best()` now holds it in ONE place, each element naming
the phase that established it. A phase that supersedes one changes it there
and says so. Gates written before a finding keep their own literals and are
historical ON PURPOSE — G33's headline must stay reproducible at the
configuration it was measured at, or its numbers stop meaning what the
ledger says they mean.

**Quantization is not a measurement, it is a production step.** Christian:
"not measure on quantized stuff in the main tests, since that's an ancillary
optimization step for production." So a phase's headline is the f32 master
against its opponent, and the packed artefact is reported separately and
labelled as such. G35 is the exception and is allowed to be, because
measuring quantization IS its subject. MARL-25's entry led with the shipped
1.7 KiB figure and has been corrected to lead with the master.

## Thresholds are Christian's

`src/thresholds.zig` holds every ⟨…⟩ from the brief's gate table as a
PROPOSED value until he strikes it (G13's are STRUCK). Do not tune a
threshold to make a gate pass; change the code, or record the finding
and ask. A gate that measures something new gets its threshold written
BEFORE it runs, from theory where there is any (`tools/g13_predict.py`
is the shape: a second program, its table frozen beside the threshold),
so the first result never becomes the threshold.
