//! thresholds — the gate numbers, in one place (brief §2).
//!
//! Every ⟨…⟩ in the brief's gate table is a value here. The brief says the
//! builder does not choose them; these are PROPOSED so the gates could be
//! written and bitten, and each stands until Christian strikes it. A gate
//! reads its number from here and nowhere else, so striking one is one
//! edit and one test run.

/// G2: connected components of Material in a slice above the first branch.
pub const G2_MIN_SLICE_COMPONENTS: usize = 2; // PROPOSED
/// G2: fronts spawned by branching (not by seeding) over the run.
pub const G2_MIN_BRANCHES: usize = 3; // PROPOSED
/// G2: steps for the growth run.
pub const G2_STEPS: u32 = 160; // PROPOSED

/// G3: front-centroid displacement toward the stimulus, lattice units,
/// after G3_STEPS with the stimulus on one side versus the other.
pub const G3_MIN_DRIFT: f64 = 4.0; // PROPOSED
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
/// 7, 40 steps, wound at 20) as of the ledger's P1.6 entry. Two runs of
/// one binary agreeing is necessary, not sufficient — a hand mutation
/// that reversed the commit order changed this hash and G1 still passed,
/// because both runs reversed. Re-baseline only as a reviewed event,
/// with the old and new values in the ledger and the reason beside them.
pub const G1_REFERENCE: []const u8 = "371e0e2dcf173ed6c5cd4fd010795d06054b0ccdbb0061b05c072827c8eb3afe";
