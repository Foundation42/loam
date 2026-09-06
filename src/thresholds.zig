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

/// G14 (Phase 2, P2.1a — pre-registered, not built): attention is
/// a(t) = a₀·exp(−(t − t₀)/τ) from a brick's last change (a₀, t₀), never
/// stepped (R15). τ is a reader's choice; this is the sim's, for the
/// active set's order under a budget and for the summaries. The floor is
/// the change floor, EPSILON: what was not a change is not attention.
pub const ATTENTION_TAU_S: f32 = 3; // PROPOSED — the Phase 1 Activity level's τ
/// G14 (c): the budget the gate grows the sapling under, as a fraction of
/// each step's active bricks, and how far the budgeted run's inside count
/// may end from the unbudgeted run's.
pub const G14_BUDGET_FRACTION: f32 = 0.5; // PROPOSED
pub const G14_MAX_DEVIATION: f32 = 0.05; // PROPOSED — of the unbudgeted inside count

/// G15 (Phase 2, P2.1b — pre-registered, not built): the budget is fed in
/// WORK UNITS (R16), never milliseconds. (a) steps spread over calls of
/// G15_UNITS publish the frozen reference exactly; (c) CUT at
/// G15_CUT_FRACTION of a step's units ends within G15_MAX_DEVIATION of
/// SPREAD.
pub const G15_UNITS: u32 = 8; // PROPOSED — small enough that the wounded sapling's steps span many calls
pub const G15_CUT_FRACTION: f32 = 0.5; // PROPOSED
pub const G15_MAX_DEVIATION: f32 = 0.05; // PROPOSED — of SPREAD's inside count

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
/// edit ran; the suite caught it.
pub const G1_REFERENCE: []const u8 = "5220c6f21046e52b7410ff80b8663d8a95e079fe6c2baeda4358f5e431d0b5ea";
