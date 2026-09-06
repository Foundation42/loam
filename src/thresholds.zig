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
/// the threshold, which is the G3 situation again"). Three parts:
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
pub const G13_SWEEP = [_]f32{ 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0 }; // PROPOSED
pub const G13_SURVIVE_R_OVER_H: f32 = 1.0; // PROPOSED
pub const G13_FAITHFUL_R_OVER_H: f32 = 2.0; // PROPOSED
pub const G13_MAX_BIAS: f32 = 0.05; // PROPOSED — of r
pub const G13_PREDICTION_TOL: f32 = 0.01; // PROPOSED — of r, worst and best separately
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
/// `371e0e2d…`; review 2026-09-06 `74cc820b…` (Age became birth time).
pub const G1_REFERENCE: []const u8 = "74cc820b93395e24d24e4def8e52b2a7030d006ff1100fe991c2cd0d5cbd9554";
