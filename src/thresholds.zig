//! thresholds — the gate numbers, in one place (brief §2).
//!
//! Every ⟨…⟩ in the brief's gate table is a value here. The brief says the
//! builder does not choose them; these are PROPOSED so the gates could be
//! written and bitten, and each stands until Christian strikes it. A gate
//! reads its number from here and nowhere else, so striking one is one
//! edit and one test run.

/// G2: 3-D connected components of YOUNG material — Material > 0.3 and
/// laid within the last G2_YOUNG_WINDOW_S seconds of fed time — at its
/// highest over the run's checkpoints. Live tips each own one component
/// of young tissue; a coiled single front gives one; a branched one gives
/// one per tip. (Review 2026-09-06: the earlier slice measure scored a
/// coiling front twice — one item satisfied the numerator alone.)
pub const G2_MIN_YOUNG_COMPONENTS: usize = 3; // PROPOSED
pub const G2_YOUNG_WINDOW_S: f32 = 8; // PROPOSED
/// G2: fronts spawned by branching (not by seeding) — the mechanism firing.
pub const G2_MIN_BRANCHES: usize = 3; // PROPOSED
/// G2: a young component counts only from this many lattice points. The
/// carrier's birth times are crisp per swept capsule, so the window's
/// trailing edge cuts through a ring and leaves one- to three-point
/// slivers whose neighbours were born a step earlier; a live tip's young
/// tissue is a hundred points and more (P2.1: 130–250 at the checkpoints).
pub const G2_MIN_COMPONENT_POINTS: usize = 10; // PROPOSED
/// G2: steps for the growth run; checkpoints every G2_CHECK_EVERY.
pub const G2_STEPS: u32 = 160; // PROPOSED
pub const G2_CHECK_EVERY: u32 = 10; // PROPOSED

/// G3: matched ± stimulus pairs across G3_SEEDS seeded directions. For
/// seed i with its own horizontal direction û_i, the stimulus sits at
/// +D·û_i and at −D·û_i; the response is r_i = (c⁺ − c⁻)·û_i on the
/// material centroid. The counter-based noise is keyed by seed, front id
/// and epoch, so the pair shares its wander: r_i is a controlled
/// perturbation, not signal against generic variability. Three separate
/// requirements: the 95% lower confidence bound on r̄ is above zero;
/// every r_i has the right sign (P = 2⁻ⁿ under a directionless null);
/// and r̄ exceeds G3_EFFECT_K × σ₀, where σ₀ is the RMS horizontal
/// centroid wander with no stimulus — an EFFECT-SIZE floor, kept apart
/// from the confidence test because σ₀ is not the null variance of r.
pub const G3_SEEDS: u64 = 6; // PROPOSED
pub const G3_DISPLACEMENT: f64 = 40; // PROPOSED
pub const G3_EFFECT_K: f64 = 3.0; // PROPOSED
pub const G3_STEPS: u32 = 40; // PROPOSED — the response/wander ratio is 4.0 at 40 steps, 3.3 at 60, at half the cost

/// G4: bricks the update may touch, in bricks beyond the damage box.
pub const G4_DILATE_BRICKS: u32 = 2; // PROPOSED

/// G5: the dormancy slope — region-operator evaluations per active brick
/// per step is exactly the operator count; the gate asserts the count and
/// PRINTS the timing, which carries the error bars.
pub const G5_MAX_EVALS_PER_ACTIVE: usize = 8; // PROPOSED: number of operators mounted, at most

/// G6: leaves sampled as a fraction of leaves the ray's segment crosses.
pub const G6_MAX_SAMPLED_FRACTION: f64 = 0.25; // PROPOSED

/// G7: channel bytes gathered by a shadow query as a fraction of a
/// primary query's.
pub const G7_MAX_SHADOW_FRACTION: f64 = 0.5; // PROPOSED

/// G13 (Phase 2): thin-feature survival — the smallest structural radius a
/// gauge carries faithfully. A straight capsule of radius r on a lattice of
/// spacing h, reconstructed by the cubic B-spline with the SAMPLES AS
/// CONTROL VALUES (R7, no prefilter), is a smoothed capsule: S ≈ φ +
/// (h²/6)∇²φ, and a tube's ∇²φ is 1/ρ, so the zero set sits at ρ ≈ r −
/// h²/(6r) — a THINNING of (1/6)(h/r)² — and vanishes where the smoothing
/// lifts the axis above zero, at r ≈ 0.78h. `tools/g13_predict.py` is the
/// full sum (not the expansion), worst over nine axis offsets in the cell
/// and three orientations; G13_PREDICTED below is its output, frozen.
///
/// The thresholds were written from that prediction BEFORE the sweep ran
/// (Claude Chat, Sunday 2026-09-06: "otherwise the first result becomes
/// the threshold, which is the G3 situation again"), and STRUCK by
/// Christian the same day, exactly as proposed. The sweep then read the
/// prediction to four decimals (the ledger, P2.1). Three parts:
///   (a) the INSTRUMENT agrees with the prediction — survival matches at
///       every swept r/h, and r_rec/r (worst and best over the same
///       offsets and orientations) is within G13_PREDICTION_TOL of it;
///       the Zig reconstruction runs on real bricks with seams and halos,
///       so this is where a halo copied one layer short shows;
///   (b) SURVIVAL — a capsule at r/h ≥ G13_SURVIVE_R_OVER_H keeps its zero
///       set at every offset and orientation (theory 0.78; headroom 0.22h);
///   (c) FAITHFUL — |r_rec − r|/r ≤ G13_MAX_BIAS at every r/h ≥
///       G13_FAITHFUL_R_OVER_H (theory −4.6% worst at 2.0, −1.9% at 3.0).
/// THINNER THAN G13_FAITHFUL_R_OVER_H IS REFINEMENT'S PROBLEM (D2), not a
/// prefilter's. What that rules today: the sapling's radius ladder is
/// 3.0 → 2.1 → 1.47 → 1.03 lattice units by child_ratio 0.7, each tapering
/// to 65% at its tip, so at gauge 0 the generation-2 and -3 twigs fall
/// below the faithful floor (thinned 9–30%) and the thinnest tips (0.67)
/// fall below survival. That is the number Astra asked for; a finer gauge
/// under the twigs is D2's first customer.
///
/// Predicted bites: the gauge doubled without refinement (r/h halves)
/// vanishes at 1.0 and 1.5 and thins 30% at 2.0 — bites (b) and (c);
/// control values half a cell off — the plausible indexing bug — reads
/// −40%/+31% at 2.0 — bites (a) and (c); trilinear in place of the
/// B-spline survives lower (0.71) and thins less (−3.4% at 2.0) — bites
/// (a) only, and is recorded as the instrument's variation, not a defect.
pub const G13_SWEEP = [_]f32{ 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0 }; // STRUCK 2026-09-06
pub const G13_SURVIVE_R_OVER_H: f32 = 1.0; // STRUCK 2026-09-06
pub const G13_FAITHFUL_R_OVER_H: f32 = 2.0; // STRUCK 2026-09-06 — "a structural feature of radius r belongs at a gauge with h ≤ r/2"
pub const G13_MAX_BIAS: f32 = 0.05; // STRUCK 2026-09-06 — of r
pub const G13_PREDICTION_TOL: f32 = 0.01; // STRUCK 2026-09-06 — of r, worst and best separately
pub const G13Prediction = struct { r_over_h: f32, survives: bool, rec_min: f32, rec_max: f32 };
/// `python3 tools/g13_predict.py --radii 0.5,0.75,1.0,1.5,2.0,3.0,4.0,6.0 --zig`, 2026-09-06.
pub const G13_PREDICTED = [_]G13Prediction{
    .{ .r_over_h = 0.50, .survives = false, .rec_min = 0, .rec_max = 0 },
    .{ .r_over_h = 0.75, .survives = false, .rec_min = 0, .rec_max = 0 },
    .{ .r_over_h = 1.00, .survives = true, .rec_min = 0.7022, .rec_max = 0.8112 },
    .{ .r_over_h = 1.50, .survives = true, .rec_min = 0.9088, .rec_max = 0.9191 },
    .{ .r_over_h = 2.00, .survives = true, .rec_min = 0.9541, .rec_max = 0.9561 },
    .{ .r_over_h = 3.00, .survives = true, .rec_min = 0.9808, .rec_max = 0.9811 },
    .{ .r_over_h = 4.00, .survives = true, .rec_min = 0.9894, .rec_max = 0.9895 },
    .{ .r_over_h = 6.00, .survives = true, .rec_min = 0.9953, .rec_max = 0.9953 },
};

/// G9 (Phase 2): both holders of a same-gauge face reconstruct from the
/// same 64 coefficients, so value, gradient and Hessian agree to float
/// tolerance — the same sums in the same order.
pub const G9_TOL: f32 = 1e-5; // PROPOSED

/// G11 (Phase 2): rays in the sphere-tracer gate. Zero misses, zero
/// overshoots, zero late hits, in all of them.
pub const G11_RAYS: u32 = 4096; // PROPOSED

/// G14 (Phase 2, P2.1a, built Sunday 2026-09-06): attention is
/// a(t) = a₀·exp(−(t − t₀)/τ) from a brick's last change (a₀, t₀), never
/// stepped (R15); a₀ is the change per channel over that channel's range,
/// the max across channels (Christian's ruling, Sunday afternoon), so a
/// change of a whole range scores 1. τ is a reader's choice; this is the
/// sim's, for the active set's order under a budget (in the hash, through
/// fmath.exp). The floor is the change floor, EPSILON: what was not a
/// change is not attention, G14 (b)'s walk rejects below it, and a
/// carried brick hosting no front fades under it.
pub const ATTENTION_TAU_S: f32 = 3; // PROPOSED — the Phase 1 Activity level's τ
/// G14 (c): the budget the gate grows the sapling under, as a fraction of
/// each step's active bricks, and how far the budgeted run's inside count
/// may end from the unbudgeted run's.
pub const G14_BUDGET_FRACTION: f32 = 0.5; // PROPOSED
pub const G14_MAX_DEVIATION: f32 = 0.05; // PROPOSED — of the unbudgeted inside count

/// G14 (e) — THE RESIDUAL (Christian with Claude Chat, Sunday afternoon;
/// pre-registered before the run, then built: the run read the
/// prediction exactly, lags 19–20 against a bound of 20). The
/// discretionary head is ordered by score = pending × (1 + lag/τ), where
/// pending is the brick's attention accumulated by max since it was last
/// evaluated (undecayed: the reader's decayed attention in the product
/// rises at most 1.5× before it falls, and a carried brick could never
/// catch a region ten times hotter) and lag = now − the fed time it has
/// been owed since (`Snapshot.active_since`). τ is the price of fairness
/// in fed seconds: a brick at attention a catches a region at R·a once
/// lag ≥ (R − 1)·τ + R·dt, and a batch of n cold bricks crossing
/// together is served over ⌈n / slots⌉ further steps. The gate: one
/// region at R = 10× the other's attention under a budget the hot region
/// alone fills; the coldest real brick is served within k steps, k
/// predicted from the formula BEFORE the run; mutation: the lag term
/// zeroed → the cold region is never served. "If k comes out long
/// enough to see, τ is wrong, not the design."
pub const LAG_TAU_S: f32 = 1.0; // STRUCK 2026-09-06 — one FED second, not one step: "the fairness bound then survives a change of dt" (Christian)
pub const G14E_RATIO: f32 = 10; // PROPOSED — the hot region's attention over the cold's

/// G14 (e)'s prediction: steps until a brick at attention a outranks a
/// fresh brick at `ratio`·a (each fresh brick carries one step of lag
/// itself), plus the steps a batch of `n_cold` equal cold bricks takes to
/// pass through `slots` discretionary slots. Written from the formula,
/// frozen beside the threshold; the run reads it.
pub fn g14ePredictedSteps(dt_s: f32, ratio: f32, n_cold: usize, slots: usize) u32 {
    const catch_up = (ratio - 1) * LAG_TAU_S / dt_s + ratio;
    const batch: f32 = @ceil(@as(f32, @floatFromInt(n_cold)) / @as(f32, @floatFromInt(@max(slots, 1))));
    return @intFromFloat(@ceil(catch_up) + batch);
}

/// G15 (Phase 2, P2.1b, built Sunday 2026-09-06): the budget is fed in
/// WORK UNITS (R16), never milliseconds. (a) steps spread over calls of
/// G15_UNITS publish the frozen reference exactly; (c) CUT at
/// G15_CUT_FRACTION of a step's units ends within G15_MAX_DEVIATION of
/// SPREAD.
pub const G15_UNITS: u32 = 8; // PROPOSED — small enough that the wounded sapling's steps span many calls
pub const G15_CUT_FRACTION: f32 = 0.5; // PROPOSED
pub const G15_MAX_DEVIATION: f32 = 0.05; // PROPOSED — of SPREAD's inside count

/// G12 (Phase 2, P2.2 — brief STRUCK Sunday 2026-09-06 evening, not
/// built): the collar is gated by provenance — a capsule unions HARD into
/// samples its own front wrote within the last COLLAR_RECENT_SEGMENTS
/// segments, and SMOOTH, with k the child's radius, into any other
/// sample: another front's, or its own older tube (the ammonite, the
/// creeper doubling back — self-touch after m rings is another front for
/// collar purposes). m is chosen from the sweep's geometry at build time
/// so that consecutive capsules sharing an end-sphere are inside it and
/// nothing else is; the value here is a placeholder until then.
/// G12_GRADIENT_TOL: |∇φ| continuous across a bud's junction to this per
/// lattice unit — the polynomial smin is C1 by construction, so this is
/// float slack, not a tolerance to tune. The inner elbow of a hard chain
/// is measured once (crease angle vs ring-to-ring bend, the sapling and a
/// tight curl) and recorded: the spine's trigger, a number.
pub const COLLAR_RECENT_SEGMENTS: u32 = 2; // PLACEHOLDER — chosen from the ring spacing at build time
pub const G12_GRADIENT_TOL: f32 = 1e-3; // PROPOSED

/// The change floor: a brick whose largest committed delta is below this
/// is not active next step, and a boundary sample below it does not
/// materialise a neighbour.
pub const EPSILON: f32 = 1e-6; // PROPOSED

/// G1's FROZEN REFERENCE: the content hash of the wounded sapling (seed
/// 7, 40 steps, wound at 20). Two runs of one binary agreeing is
/// necessary, not sufficient — a hand mutation that reversed the commit
/// order changed this hash and G1 still passed, because both runs
/// reversed. Re-baseline only as a reviewed event, with the old and new
/// values in the ledger and the reason beside them. Baselines: P1.6
/// `371e0e2d…`; review 2026-09-06 `74cc820b…` (Age became birth time);
/// P2.1 `aff19f32…` (the carrier: fronts sweep capsules into `surface`,
/// planes are 11³ blocks, the wound is a cut, fronts carry their
/// previous ring); P2.1 habit check `9c83587f…` (the front's self-read
/// restored to the occupancy of the carrier — 1 inside, a 0.75-unit ramp
/// outside — as Phase 1 read Material; the carrier's own gradient had
/// moved the trunk 25 units by step 160); the survival floor `6677f35e…`
/// (a front lays nothing thinner than G13_SURVIVE_R_OVER_H × h — twigs
/// whose ring residual dipped under it showed as gaps along their length);
/// the steady state `5220c6f2…` (Activity a touch time, no Decay mounted,
/// a quiet step publishing nothing; the wounded fixture spawns 7 fronts
/// where the decaying level let 11). The floor's and the steady state's
/// re-baselines were lost once to a shell that killed itself before its
/// edit ran; the suite caught it. Attention `e3068932…` (P2.1a: every
/// changed brick carries the magnitude and fed time of its last change in
/// its hash — it orders the step under a budget, so it is what the world
/// is; the planes, the fronts and the active set did not move). The
/// ruling `f410e7b3…` (attention scored per channel over its range, the
/// max across channels; the obligations and the budget on the snapshot,
/// in the content hash — the budget is an input like the seed). The
/// residual `019f9e0a…` (R17: since when each active brick is owed rides
/// the active set in the content hash, and a brick still owed accumulates
/// its pending by max — the obligations list it replaces is gone). The
/// resumable step `9fb0a200…` (P2.1b: where a step was cut, `cut_at`,
/// entered the content hash — an input like the budget; the root hash,
/// the fronts and the active set did not move, checked against the
/// previous commit's binary on the wound fixture). The buffer consumed
/// `ef8ab912…` (P2.1b: `finish` resets the update buffer after every
/// commit; until then the wound's `apply` at step 20 authored into a
/// buffer still holding step 19's region entries and re-applied step
/// 19's deltas on the wound's bricks — every reference since the wound
/// fixture was born carried that. The plain sapling's root hash is
/// unchanged, `631a8a64…`, and the wound's seven fronts trace
/// identically; only the wound's field values moved). The hash over the
/// canonical samples `3fd87589…` (the step-cost beat, Christian: a
/// brick's identity is its own 9³ samples and its bookkeeping — the halo
/// is a copy of the neighbours' own samples, hashed where they are
/// owned, and hashing it again was a second truth in the identity;
/// `HaloStale` and G9 are the halo's witnesses, and a corrupted halo
/// sample now leaves the hash where it is while the guard fires).
pub const G1_REFERENCE: []const u8 = "3fd87589c8d5e3f15becdf713f61dc4c04ca0c706acc0d6e04eee9edbf44cd7b";
