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

/// G3: the floor is set from the NULL, not from the measurement. Runs
/// with no stimulus across G3_NULL_SEEDS seeds give the centroid's
/// spread under wander alone (RMS about the seed axis); the drift between
/// the stimulus at +x and at −x must exceed G3_NULL_K × that spread.
/// (Review 2026-09-06: a fixed floor under a measured value is post hoc.)
pub const G3_NULL_K: f64 = 3.0; // PROPOSED
pub const G3_NULL_SEEDS: u64 = 6; // PROPOSED
pub const G3_STEPS: u32 = 60; // PROPOSED

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
