//! thresholds — the gate numbers, in one place (brief §2).
//!
//! Every ⟨…⟩ in the brief's gate table is a value here. The brief says the
//! builder does not choose them; these are PROPOSED so the gates could be
//! written and bitten, and each stands until Christian strikes it. A gate
//! reads its number from here and nowhere else, so striking one is one
//! edit and one test run.

const std = @import("std");

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

/// G12 (Phase 2, P2.2 — brief STRUCK Sunday 2026-09-06 evening, built
/// the same night): THE COLLAR IS GATED BY PROVENANCE. A capsule
/// unions HARD (k = 0) into samples its own front laid within the
/// collar's REACH behind the capsule's start ring, and SMOOTH, with k
/// the ring's radius (`Params.collar` × the envelope — "the child's
/// radius at the join", Christian's number), into everything else:
/// another front's tube, authored tissue, or its own older tube (the
/// ammonite, the creeper doubling back — self-touch beyond the reach is
/// another front for collar purposes; his amendment).
///
/// The reach is DERIVED, not chosen. smin(a, b, k) differs from min(a, b)
/// only where |a − b| < k. On the front's own tube — radius r, samples
/// out to r + band — the new capsule's start cap reads √(ρ² + z²) − r
/// against the tube's own ρ − r at z behind the ring, so the two are
/// within k of each other out to z = √(k² + 2ρk), largest at the band's
/// outer edge (`collarReach`). Behind that the smooth union IS the hard
/// one, so the window is exactly the zone where the choice matters, and
/// it is measured along the front's arc: the sample's `segment` names
/// its capsule, the ring table holds that capsule's end arc, and the
/// window is the reach behind the new capsule's start (the arc of the
/// end, so every sample within reach is inside it and a span's tail at
/// most a ring beyond, where smin is min anyway) — Christian's "own
/// front, within the last m segments", with m read off the arcs, so a
/// count survives a change of dt (the trunk's reach is 6.7 lattice
/// units — seven rings at dt = 1 s, fourteen at 0.5 s). A curl
/// self-touches only after 2π·r of arc, and 2π > √(3 + 2·band/r) for any
/// r above 0.16 h, so no honest self-touch falls inside the reach.
///
/// The brief's "|∇φ| continuous to 1e-3 across the junction" was NOT an
/// observable and is withdrawn: the reconstruction is the cubic B-spline
/// of the samples, C2 whatever they hold, so a crease and a fillet both
/// reconstruct smooth and the C1 of the smin cannot be seen through it.
/// G12 is bit-exact instead, and the crease is a MEASUREMENT (below):
///   (a) THE COLLAR — against the same scene under the hard union (every
///       collar 0; straight fronts, so the paths agree): the collared
///       field is nowhere higher (smin ≤ min), lower only within
///       g12Zone of the child's axis — beyond the child's radius plus
///       the band its field is far, the union's identity — and lower
///       there by at most k/4 (the smin's own bound) and by more than
///       nothing. Mutations, executable (`Policy.collar_gate`): the
///       window dropped (`.none`) → the front beads into its own chain,
///       differences far from the child; the window made infinite
///       (`.own`) → the coil's self-touch is a hard crease, no
///       difference where its turns meet.
///   (b) THE BANDS — band 1 is the ring morphology read through the
///       provenance chart, and outside the collars it reproduces band 0
///       BIT FOR BIT: the capsule rebuilt from the ring records at (who,
///       segment) gives the sample's φ, its chart_s and its chart_theta
///       exactly (G12_BAND_TOL is zero, and not a tolerance). Mutation,
///       by hand: θ written in the start ring's frame at every foot →
///       mismatches wherever the frames twist.
///   (c) THE SPONGE — a band-0 query gathers G12_SPONGE_BYTES and no
///       provenance and no ring history; a bark query gathers more.
///       Mutation: the class ignored → every query pays for the bark.
pub fn collarReach(k: f32, rho: f32) f32 {
    return @sqrt(k * k + 2 * rho * k);
}
/// (a)'s zone: within this of the child's axis the child's field is
/// nearer than the band and the union can act; beyond, it is far.
pub fn g12Zone(child_radius: f32, band_lu: f32) f32 {
    return child_radius + band_lu;
}
pub const G12_BAND_TOL: f32 = 0; // bit-exact: the same capsule, the same arithmetic
/// A band-0 read at a lattice point: the B-spline's 64 coefficients of
/// the surface plane, four bytes each — what G7 counts for a plane.
pub const G12_SPONGE_BYTES: u64 = 64 * 4;

/// THE INNER ELBOW (Christian's number, measured once and held in the
/// ledger, not gated): two of a front's own capsules sharing an
/// end-sphere are C1 on the outside of a bend and meet in a concave fold
/// on the inside whose normal turns by the bend angle β between rings.
/// The B-spline spreads that turn over about a cell. The tube's own
/// surface turns 1/r per lattice unit around it, so a fold whose turn
/// per unit exceeds the tube's is one the eye can find; the spine's
/// trigger, PROPOSED: a scene whose ring-to-ring bend, spread over one
/// cell, turns faster than the tube — β > h/r radians, 0.33 (19°) for
/// the trunk at gauge 0, 0.5 (29°) for a twig of two. Measured on the
/// sapling and on a deliberately tight coil (`Params.coil`), "P2.2 — the
/// collar" in the ledger.
pub fn elbowTrigger(r: f32, h: f32) f32 {
    return h / r;
}

/// G16 (Phase 2, P2.3 — brief STRUCK Sunday 2026-09-06, night, with two
/// amendments that are the same idea, and one unit; then STRUCK AGAIN
/// the same night after the first look: "the rings are a scaffold; the
/// point of loam is the gradient field"): THE PICTURE. What a bark read
/// touches at a hit, and at what footprint.
///
/// THE FRAME IS THE FIELD'S. The grain (bands 3+) is value noise in the
/// level set's own principal frame — the Hessian at the hit, the tube's
/// axis its direction of least curvature — stretched along the axis,
/// even in the frame's signs so no flip leaves a seam, keyed by world
/// position. It reads nothing but the carrier. Pixar's bark (SIGGRAPH
/// 2023) builds that direction field by hand from strokes; a signed
/// implicit has it for free. The CHART is history's: `who` and
/// `segment` name the capsule that laid a sample, and the chart's (s,
/// θ) at any point is that capsule's foot there, rebuilt from the ring
/// records exactly — no chart plane is stored, nothing is
/// interpolated, and the seam between two fronts is where their fields
/// (rebuilt from the two slots) cross. Bands 1–2, the ring morphology
/// through the chart, are what the field already holds and are read
/// for the events only (a scar); they are not the bark's.
///
/// Bands FADE, never cut (Christian: "a hard threshold pops: walk
/// toward the trunk and band 1 switches on at one frame. That's the
/// LOD pop. The mip rule: amplitude fades from scale = 2·footprint to
/// scale = footprint, so the contribution is continuous in footprint,
/// and bytes still fall monotonically because a band below its
/// fade-out is never fetched." `bandWeight`). The scales: band 1 the
/// ring's slot pitch 2π·r/24, band 2 the ring pitch speed·dt, bands 3+
/// the amplitude vector's octaves — in WORLD units ("lattice unit
/// changes meaning per gauge the day D2 lands, and bark shouldn't get
/// finer because the brick did. Same value today, different name").
/// At a collar the chart's grain (the chart mode, kept on the CPU for
/// history) goes bare by the DIFFERENCE of the two slots' weights
/// (`collarBare`, zero where they meet); the field's grain needs no
/// bareness — its frame turns with the fillet.
///
/// THE PREDICTION, written before the run: the field's read touches NO
/// provenance plane at any footprint — the carrier's coefficients
/// twice (value and gradient, then the Hessian). The chart's read
/// (history) touches `who` and `segment` — two planes, nearest — and
/// the ring table wherever a band has weight, and nothing at all
/// beyond band 2's scale (`G16_PREDICTED`). The run reads the table; a
/// disagreement is the finding. (The night's first prediction, six
/// planes close and three mid, was the chart-plane design's, and it
/// read as predicted; it is superseded, not falsified.)
///   (a) THE CHART IS EXACT ALONG A TUBE — probes on the parent's
///       surface along a generator: s advances by the arc to
///       G16_CHART_TOL, θ falls by the roll's drift and equals the
///       chart's own; `who` changes only inside G12's zone, and where
///       the two fields cross. The field's frame turns continuously
///       across the collar: the bent normal's turn between neighbouring
///       hits over the unbent's is under the bump's own curvature.
///       Mutations: `who` interpolated → a third front's id; the
///       segment interpolated → a foot on no capsule (s off by up to a
///       ring).
///   (b) THE FOOTPRINT — one hit, footprints swept: the bands fetched
///       are exactly those whose weight is above zero; bytes monotone;
///       a sponge 256 at every footprint; band 1 continuous in
///       footprint; the read at each predicted footprint as predicted,
///       in both modes. Mutations: the footprint ignored; the hard cut.
///   (c) THE NUMBER — the bridge's bytes per brick and the regression
///       line, in the ledger with the regime.
pub const G16_CHART_TOL: f32 = 1e-3; // STRUCK 2026-09-06 — float slack
/// The mip rule: a band's weight at a footprint — 1 at twice the
/// footprint and above, 0 at the footprint and below, linear between.
pub fn bandWeight(scale: f32, footprint: f32) f32 {
    if (footprint <= 0) return 1;
    return @min(1, @max(0, (scale - footprint) / footprint));
}
/// The collar's bareness for the chart's grain, from the two slots'
/// smooth-union weights w ∝ exp(−kφ) (R12's weights, from the two-slot
/// form for free): the winner's weight LESS the runner-up's, tanh(k(other −
/// own)/2) — one where the runner-up is far, ZERO where the two are
/// equal. Read literally, Christian's "(1 − w_runner-up)" is the
/// winner's weight alone, one half at the crossing, and half the grain
/// stayed at the seam (the fan read bare 0.513 where the fields were
/// 0.026 apart); "smooth and bare" is the difference. His to strike.
pub fn collarBare(own: f32, other: f32, k: f32, band_lu: f32) f32 {
    if (other >= band_lu or k <= 0) return 1;
    const x: f64 = @as(f64, k) * (@as(f64, other) - @as(f64, own));
    return @floatCast(std.math.tanh(0.5 * x));
}
/// Bands 3+: the bark's octaves and their amplitudes, WORLD units. The
/// octaves STRUCK at 0.5 and 0.25 (Christian: "same value today,
/// different name"); the amplitudes PROPOSED — a groove a tenth of its
/// octave deep, so the bump's slope is bounded by G16_BEND_SLOPE.
pub const BARK_OCTAVES_W = [_]f32{ 0.5, 0.25 }; // STRUCK 2026-09-06, world units
pub const BARK_AMPLITUDES_W = [_]f32{ 0.05, 0.025 }; // PROPOSED, world units
/// The grain's stretch along the axis of least curvature: streaks four
/// times longer than they are wide, PROPOSED by eye on the sapling.
pub const BARK_STRETCH: f32 = 4; // PROPOSED
/// The bump's largest slope, from the noise's construction: smoothstep
/// value noise has |d/dx| ≤ 1.5·A/λ per octave, two tangents — the
/// bound the bent normal's turn between neighbours is held to.
pub fn bendSlope() f32 {
    var s: f32 = 0;
    for (BARK_OCTAVES_W, BARK_AMPLITUDES_W) |l, a| s += 1.5 * a / l;
    return 2 * s;
}
/// Band 1's scale: the ring's slot pitch around a tube of radius r.
pub fn band1Scale(r: f32) f32 {
    return 2 * std.math.pi * r / 24.0;
}
/// What a read touches, predicted: footprint (world units, default
/// domain), provenance planes, the ring table — the chart mode (history)
/// and the field mode (the bark).
pub const G16Prediction = struct { footprint: f32, chart_planes: u8, chart_table: bool, field_planes: u8 };
pub const G16_PREDICTED = [_]G16Prediction{
    .{ .footprint = 0.1, .chart_planes = 2, .chart_table = true, .field_planes = 0 },
    .{ .footprint = 0.3, .chart_planes = 2, .chart_table = true, .field_planes = 0 },
    .{ .footprint = 0.6, .chart_planes = 2, .chart_table = true, .field_planes = 0 },
    .{ .footprint = 0.9, .chart_planes = 2, .chart_table = true, .field_planes = 0 },
    .{ .footprint = 1.2, .chart_planes = 0, .chart_table = false, .field_planes = 0 },
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
/// sample now leaves the hash where it is while the guard fires). THE
/// COLLAR `d64a1b0f…` (P2.2: every brick a front laid carries seven new
/// planes — who, segment, chart_s, chart_theta, own, other, collar —
/// and every front its segment count and previous arc length; the
/// sapling's children now smooth-union into the trunk with k their own
/// radius, which is real tissue a newborn child reads, so the wound
/// fixture's fronts move by a few hundredths of a unit in their first
/// steps; under `--collar 0` the new build reproduces the previous
/// commit's fronts to the last digit and its inside count exactly).
/// THE CHART'S FOOT `60b27f31…` (P2.3: `chart_s` and `chart_theta` are
/// written from the UNCLAMPED foot — a sample in the cap behind a
/// capsule's start reads the arc and the roll it lies beside, not the
/// cap's; clamped, a ring whose bark bulged won samples behind it and
/// the chart jumped by a ring along a straight tube. Only the two chart
/// planes moved; the carrier, the slots, the fronts and the active set
/// did not).
/// THE CHART PLANES GONE `6b7f4a8f…` (the cost beat after P2.3: the
/// bark's frame is the field's, so `chart_s` and `chart_theta` had no
/// reader left but the collar's window, which asks the ring table
/// through `segment` instead — the same collar to the sample, 468
/// lowered and a drop of 0.520 as before — and the chart at a read is
/// the capsule's foot, exact. Five provenance planes where there were
/// seven; nothing else moved).
/// THE CRACK FRONT `364c3aa7…` (the material seedbed's play: `Params.planar`
/// and `Params.carve` joined the front's canonical bytes — a crack keeps
/// to its face and carves rather than deposits; nothing else moved).
// ── The packed RBF set (Christian's experiment, after the marble's columns) ──
//
// The fit (`rbf.fit`, Adam on centres, log-widths and weights, seeded
// on the veins) must LOWER the held-out RMS of the two-ball fixture by
// this factor from its seeded start. PROPOSED, written before the run
// from this much theory: a Gaussian of the vein's width seeded at a
// ball's centre with the target as its weight already carries the
// ball's bulk, and the fit has the width, the weight and the overlap
// of six kernels on two balls to spend — a halving of the residual is
// the least the descent should buy. The first result never becomes
// the threshold.
pub const RBF_FIT_GAIN: f32 = 2;
/// Two ANISOTROPIC kernels against two held spherical on one straight
/// vein (a capsule twelve long, radius one and a half): the free fit
/// must lower the held-out RMS by this factor. PROPOSED, from this
/// much theory: a sphere covering a third of the tube's length is
/// wider than the tube by the same factor and leaks into the matrix
/// on every side, so two spheres leave the tube's ends and the
/// matrix's neighbourhood wrong together; two ellipsoids of the
/// tube's own width, six long, cover it with a residual only at the
/// caps — a halving is the least of it. The first result never
/// becomes the threshold.
pub const RBF_ANISO_GAIN: f32 = 2;

// ── MARL-0 (docs/MARL_CAMPAIGN.md; src/marl.zig) ─────────────────────
//
// Every number below was written BEFORE a single exemplar streamed, and
// every one of them comes out of `tools/marl_predict.py` — a second
// program that reimplements the truth field from marl.zig's constants and
// knows nothing about the learner. That is the brief's rule for a gate
// that measures something new, and MARL-0 is nothing but new
// measurements. The first result never becomes the threshold; the
// measured values live in the ledger.

/// G17 (e): streaming exemplars must lower the held-out RMS by this
/// factor from the empty model's, which predicts zero everywhere and so
/// scores the truth's own RMS (0.1458).
///
/// PROPOSED, from this much theory: the target's variance splits 43% into
/// the windowed swell and 60% into the shell (−3% cross term). Learning
/// the swell perfectly and the shell not at all buys a gain of 1.32;
/// learning the shell perfectly and the swell not at all buys 1.58. A
/// gate at 2 needs 75% of the variance gone, which NEITHER PART ALONE CAN
/// SUPPLY — so it cannot be passed by resolving the easy half, which is
/// the only way this gate could be vacuous.
pub const MARL0_RMS_GAIN: f32 = 2;

/// G17 (f): kernel centres per unit volume in the shell's band, over the
/// same in the quiet slab where the truth is identically zero.
///
/// PROPOSED as a FLOOR with a decade of headroom, not an estimate of the
/// value — the theory here is an asymmetry of mechanism, not a number. A
/// birth in the shell is driven by an amplitude-0.9 ridge at every
/// exemplar that lands on it. A birth in the quiet slab needs a leakage
/// cascade to stay above the surprise threshold across a gap wider than a
/// kernel's reach: each generation's residual is the previous
/// generation's Gaussian tail, and the tail of a tail is what has to
/// clear the same threshold. Ten is where a floor sits when the mechanism
/// is asymmetric and its magnitude is what the run is for.
pub const MARL0_CAPACITY_RATIO: f32 = 10;

/// G17 (c): kernels whose support contains one exemplar — the campaign's
/// §20 proposition 2, "a useful update touches only a tiny fraction of
/// model state", as a count and as a fraction.
///
/// PROPOSED, from this much theory: a birth is refused once some kernel
/// already reads above `coverage` at the exemplar, so kernels pack at
/// about one per ball of radius r_cov = √(−2 ln coverage) = 1.449
/// Mahalanobis widths, while each is non-zero out to r_cut = √CUTOFF =
/// 5.657. The number overlapping any point is the volume ratio,
/// (r_cut/r_cov)³ = 59.5. The bound is twice that: descent widens a
/// kernel past its birth width, and a packing estimate ignores overlap.
///
/// This number is the price of an exp(−16) cutoff, and it is worth
/// reading as a finding rather than a nuisance — sixty kernels overlap
/// every point BECAUSE the kernel is generous, and the generosity is
/// there so that `rbf`'s material read is exactly the entry far away.
pub const MARL0_MAX_TOUCHED: usize = 120;
pub const MARL0_MAX_TOUCHED_FRACTION: f64 = 0.05;

/// G17 (c): the radius beyond which a learning event changes the
/// prediction by NOTHING — bitwise, not to an epsilon. Adam's bound on
/// |m̂|/√v̂, which sets how far one step can displace a centre.
///
/// PROPOSED, and this one is a proof rather than a guess. A touched
/// kernel's cutoff box reaches at most `h` on every axis (the clamp), so
/// if it covers x its centre is within h of x and its support within 2h.
/// A step moves that centre by at most rate·K, a birth puts a new kernel
/// AT x with reach ≤ h, and nothing else in the model is written. So
/// every sample outside 2h + steps·rate·K is untouched — the campaign's
/// proposition 3, which is structural here and not an empirical hope.
///
/// The bound is LOOSE (0.52 of the domain at the defaults). The radius
/// actually observed is the finding and belongs in the ledger.
pub const MARL0_ADAM_K: f32 = 3.1622776601683795; // (1−β₁)/√(1−β₂), β = (0.9, 0.999)

/// The bound, in the model's own terms: 2h from the clamp, plus whatever
/// one event can displace a centre by.
///
/// AMENDED AFTER THE FIRST RUN, and the amendment is a finding rather than
/// a tuning — it makes the bound SMALLER, which is the opposite of what
/// tuning a gate to pass would do. What was pre-registered above assumed
/// Adam, whose step is bounded by rate·K whatever the residual. Adam turned
/// out to be the wrong optimiser for single-exemplar learning (see
/// `marl.Optimizer`) and NLMS replaced it — and an NLMS step has no
/// a-priori bound at all, because it is proportional to a residual and a
/// weight that nothing caps. Handed the NLMS rate, the pre-registered
/// formula returned 5.08 of a unit domain: a bound larger than anything
/// that exists, and G17 (d) asserting "no probe beyond it moved" could not
/// fail. A vacuous gate is worse than no gate, so the model now carries an
/// explicit TRUST REGION — a step may not move a centre more than
/// `Options.trust` region edges — and the bound is that, exactly, for any
/// optimiser. G17 (d) additionally requires the bound to be smaller than
/// the domain, so this particular vacuity cannot come back quietly.
pub fn marl0ReachBound(h: f32, steps: u32, trust: f32) f32 {
    return h * (2 + @as(f32, @floatFromInt(steps)) * trust);
}

// ── MARL-1 (Christian's ordering, after MARL-0's numbers) ────────────
//
// Written before MARL-1's first run, out of `tools/marl1_predict.py` —
// which builds a SYNTHETIC basis by MARL-0's own birth rule rather than
// consulting any run. That the synthetic basis reproduces the measured
// overlap (81.6 against 86) is the check that it is the right basis.

/// G18 (a): arm A births with no descent; arm B' takes A's frozen
/// topology and descends with births disabled. Capacity is identical by
/// construction, so this is deformation's contribution and nothing else.
/// RMS_A / RMS_B' must clear this.
///
/// PROPOSED, from this much theory: with centres and shapes held the
/// model is LINEAR in its weights, so the best any weight-learner can do
/// is least squares on that basis, and birth's greedy one-shot weights
/// are the first iterate of a Gauss-Seidel sweep rather than the
/// solution. On a synthetic basis built by the same birth rule at the
/// same overlap, greedy scores 0.09084 and least squares 0.06115 — a
/// ratio of 1.49 available on the WEIGHTS ALONE. Descent also has the
/// geometry, which should buy more; three steps an event is not a
/// least-squares solver, which buys less. Two is a floor that requires
/// descent to beat the linear-algebra headroom of its own basis.
///
/// A GAP IN THIS PRE-REGISTRATION, found by the run and recorded rather
/// than repaired by moving the number: it never said AT WHAT N. The ratio
/// compounds with experience — 1.17 at 40 000 exemplars, 1.54 at 80 000,
/// 1.80 at 120 000, 2.30 at 200 000, 3.00 at 400 000 — because arm A
/// plateaus at RMS ≈ 0.051 within about forty thousand exemplars and
/// never improves again, while B' keeps going. A floor on a quantity that
/// grows is only a threshold once its horizon is named, so the horizon is
/// named here and the number stays where it was written.
pub const MARL1_DESCENT_GAIN: f32 = 2;
pub const MARL1_DESCENT_N: u64 = 300_000;

/// G18 (b): at fixed coverage, kernels whose centres land in the shell
/// band, per feature, against the one-feature count.
///
/// PROPOSED: each shell is a separate surface and needs its own tiling at
/// the same coverage, so the count should scale about linearly with the
/// feature count. Half is the floor — a factor of two of slack for shells
/// that overlap one another and share kernels. The companion claim is
/// absolute and carries no slack: the quiet slab holds ZERO at every
/// complexity, because features are placed inside x ≤ 0.65 and the
/// slab's unreachability is arithmetic.
pub const MARL1_FEATURE_SCALING: f32 = 0.5;

/// G18 (c): kernels touched per event at responsibility radius R, against
/// the packing prediction (R/r_cov)³ with r_cov = √(−2 ln coverage).
///
/// PROPOSED: the same volume-ratio argument that predicted 59.5 for the
/// full cutoff and measured 86 — a factor of 1.4 — so three is a bound
/// with room in it rather than a restatement of the result.
pub const MARL1_TOUCHED_TOLERANCE: f32 = 3;

/// G18 (d): the target's own range, and the line the mean |w| must not be
/// on the wrong side of.
///
/// PROPOSED as a MECHANISM claim rather than a magnitude, which is what
/// makes it able to fail: Christian's reading of the coverage-0.10
/// divergence is that under-birth causes OVER-RESPONSIBILITY — too few
/// kernels forced to explain too much territory, weights going
/// pathological, and the resulting predictions then corrupting the
/// coverage decision that would have birthed more. If that is the
/// mechanism then every diverging run shows a mean |w| above the target's
/// own range and every converging one below it. If divergence is
/// something else, this gate says so.
pub const MARL1_OVERRESPONSIBILITY: f32 = 1.25;

/// G18 (e): a budget this small must saturate, and the default 64 must
/// not.
///
/// PROPOSED: the natural population is about 4 000 kernels across 155 of
/// 216 occupied regions — roughly 26 per occupied region — and the
/// campaign's §10 asked for saturation data that the natural experiment
/// never produced. Sixteen is below that occupancy and must therefore
/// bite; where between 16 and 64 the transition actually sits is the
/// measurement, not the threshold.
pub const MARL1_SATURATION_BUDGET: u32 = 16;

pub const G1_REFERENCE: []const u8 = "364c3aa756ffaf50aa89774ef63d774c690cc4d934725f7436988cc7a0193825";
