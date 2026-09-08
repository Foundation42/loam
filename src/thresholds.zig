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

// ── MARL-2 (the residual hierarchy) ──────────────────────────────────
//
// From `tools/marl2_predict.py`, before its runs. Christian's instruction
// shapes the whole set: pre-register around WHERE the extra capacity
// appears and not merely whether the total error improves, "otherwise an
// unconditional second layer could pass while missing the point." So the
// load-bearing gates below are about placement and concentration, and the
// RMS one is the weakest of them.
//
// The ground truth they are scored against: of 216 parent regions, 47
// touch the shell band — 21.8% of the domain, which is also the share of
// exemplars a perfectly precise refiner would route to a child.

/// G19 (a): kernels the CHILD holds in the quiet slab.
///
/// PROPOSED at zero with no slack, because it is a chain of derivations
/// rather than an estimate: the truth is exactly zero past x = 0.90, no
/// parent kernel born on structure can reach there, so the parent's
/// post-update residual there is zero, so no covered event can raise that
/// region's pressure above any positive threshold, so no region there is
/// refined, so the child is never handed an exemplar there. One kernel in
/// the slab means a link in that chain is broken and the gate should say
/// which.
pub const MARL2_CHILD_QUIET: u32 = 0;

/// G19 (b): of the regions refinement opened, the share touching the
/// shell band.
///
/// PROPOSED, from this much theory: the swell varies on a scale of about
/// 0.3 — 1.8 region edges — and the parent tiles it at a coverage spacing
/// of 0.0427, seven kernels per wavelength, which is ample. The ridge is
/// thinner than one kernel and cannot be tiled at all. So pressure should
/// fire on the ridge and almost nowhere else. Three quarters is a FLOOR
/// rather than an estimate: a region beside the ridge can be pressured by
/// its tail without the band itself reaching in.
pub const MARL2_PRECISION: f32 = 0.75;

/// G19 (c): the child's shell-band density over its density across the
/// regions it occupies at all. THE GATE THIS EXPERIMENT EXISTS FOR.
///
/// PROPOSED: MARL-1 established that the parent's capacity rule is
/// geometric — it tiles structure, at a shell-band concentration of about
/// 1.66 (8 402 per unit³ in the band against roughly 5 067 across the
/// volume it occupies). If refinement is adaptive REPRESENTATION rather
/// than a second helping of the same rule, the child must be far more
/// concentrated than that, because it is only ever handed exemplars in
/// pressured regions. Three is double the parent's, and it is the number
/// an unconditional second layer fails.
///
/// **REFUTED, and left standing for Christian to strike.** Measured 1.54,
/// 1.67, 1.65 at sharpness ×1, ×2, ×4 — the child is barely more
/// concentrated than the parent (1.20 to 1.22). The reason is the finding:
/// refinement made the allocation REGION-granular, not structure-granular.
/// The pressure signal picks the right regions (precision 0.94 to 1.00),
/// and then inside them the child tiles by the same coverage rule the
/// parent used, so a second level of a geometric rule is still geometric.
/// At sharpness ×4 the band is a tenth of a refined region's volume and a
/// concentrating child would read near 10; it reads 1.65. No gate asserts
/// this number, because asserting a refuted prediction fails the suite and
/// moving it would be the first result becoming the threshold.
pub const MARL2_CONCENTRATION: f32 = 3;

/// G19 (d): at sharpness ×2, the hierarchy's held-out gain as a multiple
/// of flat MARL's at the same sharpness, same seed, same exemplars.
///
/// PROPOSED: flat MARL scores 6.19 at ×1, 2.62 at ×2 and 1.80 at ×4 —
/// capacity density unmoved, accuracy falling. The child's grid is twice
/// as fine, so its coverage spacing on the ridge is half the parent's and
/// it can hold four times the kernels per unit of ridge area. A fourfold
/// capacity increase on the component carrying most of the residual should
/// buy well over half as much again overall.
///
/// **REFUTED, and left standing.** Measured 1.12, 1.32, 1.38 at sharpness
/// ×1, ×2, ×4 — the right SHAPE (refinement helps most where the parent
/// struggles most) at the wrong magnitude. A finer child does not fix it:
/// at sharpness ×4 the refine multiple sweeps 1.22, 1.46, 1.36, 1.14 for
/// ×2, ×3, ×4, ×6, so there is an optimum and past it MORE CAPACITY IS
/// WORSE — 11 895 child kernels at ×6 score below 3 927 at ×2, because
/// finer kernels sit in fewer responsibility sets and each is trained by
/// fewer exemplars. Capacity and training compete at a fixed exemplar
/// budget, which nothing in the prediction accounted for.
pub const MARL2_SHARPNESS_RETENTION: f32 = 1.5;

/// G19 (e): total gradient applications, hierarchy over flat, at the same
/// exemplar count.
///
/// PROPOSED: only 21.8% of exemplars land in shell-touching regions and
/// only those reach the child, and the parent STOPS learning there — so
/// the child's work partly replaces the parent's rather than adding to
/// it. Half again is generous for that.
pub const MARL2_WORK_RATIO: f32 = 1.5;

// ── MARL-3 (residual-driven birth) ───────────────────────────────────
//
// From `tools/marl3_predict.py`, before its runs. MARL-3 changes exactly
// one thing — the child's birth decision, from "insufficient geometric
// coverage" to "persistent post-update residual" — and everything else is
// held, so any movement in these numbers is attributable.
//
// What a PERFECT allocator would score, which is what makes "materially
// better" sayable at all: if every child kernel landed in the band, the
// concentration would be the refined volume over the band volume inside
// it, and that ceiling RISES with sharpness because a thinner ridge is a
// smaller share of the region containing it.
//
//     sharpness    band vol   refined vol   ceiling   MARL-2   of ceiling
//         ×1        0.05149      0.19444      3.78      1.54       41%
//         ×2        0.02541      0.17593      6.92      1.67       24%
//         ×4        0.01263      0.15741     12.46      1.65       13%
//
// MARL-2 falls away from perfect as the target sharpens, which is the
// signature of an allocator that fills regions rather than structure.

/// G20 (a): the child's shell-band concentration at sharpness ×2.
///
/// PROPOSED as `MARL2_CONCENTRATION`'s number, unchanged and reused. That
/// prediction stands unstruck and was not wrong about what good placement
/// looks like — it was wrong about which allocator would deliver it. Three
/// is 43% of a perfect allocator at ×2, which is a real ask and a
/// reachable one.
///
/// **REFUTED, and left standing.** Measured 1.58 (residual births), 1.67
/// (coverage), 1.67 (either) at sharpness ×2 — and 1.57 to 1.67 across
/// four settings of the residual bar spanning 680 to 4 345 child kernels,
/// convergent to badly divergent. The number does not move. The birth
/// criterion is not where the concentration failure lives.
pub const MARL3_CONCENTRATION: f32 = 3;

/// G20 (b): concentration at sharpness ×4 over concentration at ×1.
///
/// PROPOSED, and the crisper of the two claims because birthing more
/// kernels everywhere cannot meet it: the ceiling rises 3.78 → 12.46 as
/// the ridge thins, so an allocator that follows structure must rise with
/// it. MARL-2's went 1.54 → 1.67 → 1.65 — flat, and slightly down at the
/// end. A perfect allocator would score 3.30 on this ratio; half of that,
/// floored, is the ask.
///
/// **REFUTED, and left standing.** Measured 1.07 (coverage), 1.08
/// (residual), 1.08 (either) while the ceiling went 3.54 → 11.01. Every
/// rule tracks the ceiling equally badly, which is the same statement as
/// the one above from the other end.
pub const MARL3_CONCENTRATION_SLOPE: f32 = 1.5;

/// G20 (c): the child's population, against what MARL-2's allocator spent
/// at the same sharpness.
///
/// PROPOSED at parity, because a concentration win is manufacturable by
/// birthing far more kernels and letting the band's share rise with them
/// (Christian: "so an apparent concentration win cannot hide unconditional
/// capacity growth"). The claim under test is BETTER PLACEMENT, not more
/// of it, so the budget is what MARL-2 already used.
///
/// **HELD, and vacuously.** `.residual` births 969 to 1 193 against
/// MARL-2's 3 760 to 4 594 — well under, and for the wrong reason: it
/// under-births into divergence. `.either` lands at 4 594 / 4 345 / 3 778
/// against 4 594 / 4 339 / 3 760, over by 0 to 18 kernels, which is
/// residual evidence contributing SIX births out of 4 345. The cap was
/// written to stop a concentration win hiding capacity growth; there was
/// no concentration win to hide anything.
pub const MARL3_CAPACITY_CAP: f32 = 1.0;
/// MARL-2's measured child populations at sharpness ×1, ×2, ×4 — a
/// baseline the cap is taken against, not a threshold in itself.
pub const MARL3_MARL2_CHILD_KERNELS = [3]u32{ 4594, 4339, 3760 };

// ── MARL-4 (routing: biasing the learning stream) ────────────────────
//
// From `tools/marl4_predict.py`, before its runs. MARL-3's result set the
// brief: capacity can only concentrate where the STREAM concentrates, so
// MARL-4 changes the stream and nothing else —
//
//     p(route) = min(1, route_floor + route_gain · |y − parent(x)|)
//
// the floor protecting the trainability the coverage rule was silently
// supplying, the gain concentrating evidence on unresolved structure.
//
// What MARL-3 measured, and what these are derived from:
//
//     sharpness   band vol   stream   kernels   kernels/stream
//        ×1        0.2205    0.2298    0.3129        1.36
//        ×2        0.1456    0.1556    0.2574        1.65
//        ×4        0.0801    0.0933    0.1497        1.60
//        ×4 probe  0.0801    0.2195    0.2189        1.00   (hard filter)

/// G21 (a): the child's band share over the STREAM's band share, at every
/// routing setting.
///
/// PROPOSED as a band rather than a target, because the claim under test
/// is TRACKING and not magnitude: MARL-3 measured 1.36 to 1.65 over a
/// uniform stream and 1.00 over a concentrated one — the birth rule adds a
/// bounded local gain that shrinks as the stream does the work. Outside
/// this band, placement has stopped following its input and MARL-3's
/// diagnosis is wrong.
pub const MARL4_TRACKING_LO: f32 = 0.8;
pub const MARL4_TRACKING_HI: f32 = 1.7;

/// G21 (b): stream concentration (the stream's band share over the band's
/// volume share) at sharpness ×4 over the same at ×1.
///
/// PROPOSED: a sharper target localises the residual, so a
/// residual-biased router should concentrate MORE where the structure is
/// harder. Uniform routing already scores 1.12 on this ratio — the
/// residual leans on the band a little without any help — so the ask is
/// that a router beat that by a clear margin, not merely exceed one.
pub const MARL4_STREAM_SLOPE: f32 = 1.3;

/// G21 (c): child kernels with at least ten gradient updates.
///
/// PROPOSED: MARL-3's residual-only birth collapsed to 6% to 24% trained
/// with mean |w| of 13 to 17, and a routing floor doing its job keeps the
/// child where MARL-2 was — 0.99 trained, |w| 0.15. This is the number
/// that says the floor is a floor. `MARL1_OVERRESPONSIBILITY` holds on
/// both levels unchanged.
pub const MARL4_TRAINED_FLOOR: f32 = 0.8;

/// G21 (d): the child's shell-band concentration at sharpness ×4.
///
/// PROPOSED: MARL-2 and MARL-3 sat at 1.65 whatever the birth rule. A hard
/// filter at |r| > 0.05 reached 2.11 while starving low-residual regions
/// entirely; a graded bias with a protected floor should do better on
/// placement AND on health. The ceiling is 11.01, so 2.5 is 23% of
/// perfect — an ask, and well short of claiming the problem solved.
pub const MARL4_CONCENTRATION: f32 = 2.5;

// ── MARL-5 (scheduling a fixed learning budget) ──────────────────────
//
// From `tools/marl5_predict.py`, before its runs. MARL-4 left one tension:
// concentration and evidence sufficiency compete for a fixed budget. Three
// arms at THE SAME ROUTED COUNT, so no arm can win by processing more —
// uniform, best static residual bias, and adaptive scheduling.
//
// Christian's restraints shape the whole set. The criterion is a PARETO
// improvement and not a maximum, because MARL-4 established that chasing
// concentration to the ceiling is actively bad. And the sufficiency term
// is a control rather than a target: if residual-only scheduling does as
// well, evidence-per-kernel was diagnostic and the scheduler does not need
// it. That must not be pre-committed to.

/// G22 (a): the adaptive arm's RMS against the best static arm's, at the
/// same routed count.
///
/// PROPOSED, from what counts as an effect on this target: MARL-4's whole
/// efficient regime spans 1.2% of RMS between uniform routing and the
/// static 0.05/6 point, so five percent is several times anything a static
/// setting can buy and cannot be reached by drifting along that frontier.
///
/// **REFUTED, and left standing.** Measured 0.91 — the adaptive arm is 10%
/// WORSE than static bias, not 5% better, and so are the other two
/// policies. The reason is granularity: a region is a sixth of the domain
/// across and the ridge is a fortieth of it thick, so a schedule that
/// routes a whole region at one probability cannot separate the exemplar
/// on the ridge from the one beside it — and that separation is the entire
/// mechanism MARL-4 established.
pub const MARL5_RMS_EDGE: f32 = 1.05;

/// G22 (a), the other half: concentration against the UNIFORM arm's.
///
/// PROPOSED so that a scheduler cannot pass the RMS gate by quietly
/// becoming uniform routing, which would be the degenerate solution. Both
/// halves must hold; either alone is meaningless.
///
/// **REFUTED, and left standing.** Measured 1.08 (1.83 against uniform's
/// 1.70), where static per-exemplar bias reaches 2.29 on the same
/// exemplars at the same duty.
pub const MARL5_CONCENTRATION_EDGE: f32 = 1.2;

/// G22 (b): RMS(need alone) over RMS(need × anti-starvation), at the same
/// routed count.
///
/// PROPOSED as a DIRECTION claim with a deliberately small margin.
/// Christian's prediction is that the largest residual is not the best
/// schedule — that a scheduler must avoid both tails, repeatedly servicing
/// well-trained high-residual regions and starving newly created
/// representation. Demanding a large margin would make a true but modest
/// effect read as a refutation of a claim that was right.
///
/// **REFUTED, and left standing — though not in the way it was written
/// to be.** Measured 1.001: `need` and `need × lag` are indistinguishable.
/// That is not evidence that the largest residual IS the best schedule; it
/// is that at region granularity the whole family is dominated, so the
/// question the number was asking could not be answered at this
/// resolution. Christian's prediction is untested, not refuted.
///
/// The sufficiency control, reported and never gated: `need × lag ÷
/// sufficiency` was the WORST of the three (0.05380 against 0.05228). So
/// evidence-per-kernel was diagnostic, as Christian allowed it might be,
/// and the scheduler does not want it explicitly.
pub const MARL5_LAG_HELPS: f32 = 1.02;

// NOT gated, at Christian's instruction, and recorded rather than
// pre-committed: whether the SUFFICIENCY term contributes causally, and
// what `learning_efficiency` — Δ(regional unresolved residual) per unit of
// learning work — turns out to look like. Measured first, scheduled from
// never.

// ── MARL-6 (drift: the frozen parent under a moving world) ───────────
//
// From `tools/marl6_predict.py`, before its runs. The first experiment
// that tests the PREMISE rather than a mechanism: the frozen-parent delta
// semantics say `child ≈ unresolved detail of the current parent`, and
// this moves the world to find out whether that survives or degrades into
// `child ≈ current target − historical parent` — the same algebra, a
// different architecture.
//
// Two magnitudes at a known exemplar count, with a stationary control of
// identical length. Small displacement is 0.6 parent regions; large is
// 1.8. Nothing repairs anything: no thawing, reparenting or forgetting.

/// G23 (a): the child's RMS contribution after SMALL drift, over the
/// stationary control's.
///
/// PROPOSED, and it disagrees with Christian's expectation 6 on purpose.
/// He expects large drift to expose the frozen-parent problem more
/// strongly; for the SEMANTIC failure specifically I predict the opposite,
/// structurally:
///
///   SMALL drift lands the new ridge in regions ALREADY REFINED, whose
///   parents are frozen and cannot learn it. The child is the only thing
///   that can, and it must carry the shell's full amplitude rather than a
///   fine-scale residual — which is "current target − historical parent",
///   exactly the degradation this phase exists to detect.
///
///   LARGE drift lands it in regions never pressured, whose parents are
///   NOT frozen and learn it normally. The damage there is stranded
///   capacity in the abandoned regions: a different pathology, and a
///   cheaper one.
///
/// So the same ratio under large drift should be SMALLER than under
/// small. If it inverts, my reasoning is wrong and his expectation was
/// right — which is why both are run and why the ordering is gated.
///
/// **REFUTED as a magnitude, and the ORDERING is not established either.**
/// Measured 1.26, 1.50, 1.20, 1.21 for small drift across two sharpnesses
/// and two seeds — one of four reaches 1.5. And the small-over-large
/// ordering held 3 of 4, inverting at sharpness ×4 seed 7 (1.20 against
/// 1.34), so the child's magnitude is too noisy to carry the claim. It was
/// the wrong instrument: TOTAL RMS separates the two drifts 4 of 4.
///
/// On that instrument the reasoning holds, WITH A CONDITION neither of us
/// stated: small drift is worse than large only once enough of the domain
/// has been frozen. Damage relative to the stationary control, by how long
/// the model ran before the world moved —
///
///     pre-drift    refined    small    large
///      100 000        36       1.28×   1.39×    ← large is worse
///      200 000        38       1.64×   1.54×
///      300 000        41       1.68×   1.52×    ← small is worse
///
/// The harm from a small move GROWS with the model's own age while the
/// harm from a large one does not. Ossification is an exposure that
/// deepens, and the crossover is where commitment to the frozen parent
/// outweighs having a free parent elsewhere. No gate: it needs a
/// three-point sweep to state at all, and one point of it would be a
/// number pretending to be a law.
pub const MARL6_CHILD_MAGNITUDE: f32 = 1.5;

/// G23 (b): child kernels that existed at the drift and are still outside
/// the CURRENT band when the run ends.
///
/// PROPOSED as a floor, and a low one, because they cannot leave: MARL-0
/// measured centre drift at 0.0009 of the domain on average over a whole
/// run, so a kernel born on the old ridge stays on the old ridge. Under
/// large drift the two bands share almost nothing.
pub const MARL6_STRANDED: f32 = 0.5;

/// G23 (c): learning events in the window after the drift, over the same
/// window in the stationary control.
///
/// PROPOSED: the surprise threshold is 0.02 and the ridge is 0.9 tall, so
/// every exemplar landing on newly-wrong structure is a learning event,
/// against a settled rate of about 12% of exemplars by 200 000.
///
/// **REFUTED.** Measured 1.11 (small) and 1.28 (large). The derivation was
/// wrong in a way worth keeping: it assumed every exemplar landing on
/// newly-wrong structure becomes a learning event, but the band is about
/// 15% of the domain, the two bands overlap, and most of those exemplars
/// were provoking events already. The world moving is a much quieter
/// event than it feels like it should be — which is itself the finding,
/// because a system that barely notices is a system that will not repair
/// itself unprompted.
pub const MARL6_REACTIVATION: f32 = 2.0;

/// G23 (d): refinement precision against the CURRENT target after large
/// drift, over the stationary control's.
///
/// PROPOSED: regions are refined once and never unrefined, so after a move
/// the refined set describes where structure USED to be. Only a modest
/// fall is required — newly pressured regions are still refined
/// correctly, so the set is DILUTED rather than replaced.
pub const MARL6_PRECISION_FALL: f32 = 0.85;

// NOT gated, at Christian's instruction: that RMS fails to recover. It may
// recover well, and recovering well while the hierarchy ossifies is
// outcome B — the one an ordinary benchmark would call success. Reported
// only, along with the hysteresis run.

// ── MARL-7 (unrefinement: retiring a level that stopped being valid) ─
//
// From `tools/marl7_predict.py`. Christian asked that erosion be split
// into KERNEL DEATH and UNREFINEMENT, and two measurements run before any
// mechanism decided which of them MARL-7 could be about:
//
//   Obsolete kernels do NOT self-identify. After a large drift, pre-move
//   child kernels outside the current band carry mean |w| 0.1219 — larger
//   than the stationary control's off-band kernels at 0.0832.
//
//   And they are LOAD-BEARING. Silencing them costs 1.42× the RMS in the
//   stationary control and 1.56× after large drift.
//
// So the corrective archaeology is not separable capacity beside the
// useful kind; it is a contamination inside otherwise-useful kernels, and
// no deletion takes one without the other. MARL-7 is therefore
// UNREFINEMENT ONLY — drop the child level and unfreeze the parent in one
// act, so the stale error and its correction leave together.

/// G25 (a): of the regions unrefined, the share the current band has left.
///
/// PROPOSED at MARL2_PRECISION's floor and for the same reason: a region
/// beside the departure can be legitimately disturbed without the band
/// having left it.
pub const MARL7_UNREFINE_PRECISION: f32 = 0.75;

/// G25 (a), the other half: unrefinements in a stationary world.
///
/// PROPOSED at zero, absolute, and derivable: a refined region's parent
/// error is exactly what the child was created to absorb, and in a
/// stationary world it does not grow — MARL-6 measured the stationary
/// control's parent flat at 0.0715 across 100 000 exemplars. A single
/// unrefinement with nothing moving means the trigger is reading noise.
///
/// **HOLDS, BUT ONLY AT A SETTING** — so it is not gated. At an
/// unrefinement factor of 3 the trigger is silent in a still world across
/// 721 000 exemplars; at 2 it retires a region by 300 000. "Quiet when
/// nothing moves" turns out to be a property of a threshold rather than of
/// the mechanism, and a gate asserting it would launder the one into the
/// other.
pub const MARL7_STATIONARY_QUIET: u32 = 0;

/// G25 (b): total RMS after large drift with unrefinement, over MARL-6's
/// without it.
///
/// PROPOSED, and deliberately modest. MARL-6's large drift recovers to
/// 0.04861 with its parent stuck at 0.08968 — the parent contributes
/// nothing to the repair, being neither free to move nor observing.
/// Unrefinement hands those regions back to a parent that learns them the
/// way it learns anything, and MARL-2 established the parent alone reaches
/// about 0.07 on this target from scratch. But unrefinement also throws
/// away a level's worth of fitted capacity and the transient may eat much
/// of the gain, so a tenth is the ask.
pub const MARL7_RECOVERY: f32 = 0.9;

/// G25 (c): child kernels after a there-and-back drift, over the count
/// before it.
///
/// PROPOSED against MARL-6's measured 1.82 (7 883 from 4 339, with worse
/// accuracy than the state it returned to). If unrefinement works, the
/// regions abandoned on the way out are collapsed rather than carried and
/// the return trip does not pay for them twice. Not 1.0 — the new world
/// genuinely needs capacity of its own.
pub const MARL7_HYSTERESIS_GROWTH: f32 = 1.4;

// ── MARL-8 (recycling: borrowing capacity instead of buying it) ──────
//
// From `tools/marl8_predict.py`. MARL-7's pathology stated exactly:
// accuracy flat under repeated drift, capacity linear, and every kernel
// load-bearing so none of it can be deleted. The model never reuses
// anything.
//
// MARL-8 recycles at the refine/unrefine boundary — a retiring region's
// child is POOLED rather than destroyed, and a refining region draws from
// the pool, translated to its own origin, instead of starting empty.
// Positions and shapes carried, WEIGHTS RESET, because MARL-1 established
// the weights are the convex fast part and geometry is what deformation
// spends 2.15× buying.
//
// The ceiling first: MARL-7's six moves bought 961 kernels a move while
// retiring 2.5 regions a move at ~70 kernels each. So about 18% of what
// is bought is available to borrow, and recycling is BOUNDED BY THE
// RETIREMENT RATE. Every number below has to be read against that.

/// G27 (a): child population after six moves, with recycling over without.
///
/// PROPOSED from the ceiling: 18% of new kernels could be borrowed, so a
/// fifth off the growth is the ask, with room for transplants that do not
/// take.
///
/// **REFUTED, and in the wrong direction.** Measured 1.045 — 11 346
/// kernels against 10 878 without recycling. 961 kernels were transplanted
/// and roughly 493 births suppressed, so each borrowed kernel saved about
/// half a purchase: a donor region's child had tiled a WHOLE region, and
/// the recipient only needed structure in part of its own.
pub const MARL8_GROWTH: f32 = 0.85;

/// G27 (a), the other half: RMS with recycling over RMS without.
///
/// PROPOSED at the noise band these runs show between seeds. A
/// transplanted kernel arrives at weight zero, so at the moment of
/// transplant the prediction is UNCHANGED — the mechanism cannot make
/// things worse instantly, only slowly and only if the geometry is wrong
/// for its new home.
///
/// **HELD, vacuously.** Measured 1.030 over six moves, and identical at
/// every point of the recovery transient (0.10288 / 0.07379 / 0.04753 /
/// 0.03384 against 0.10288 / 0.07378 / 0.04761 / 0.03338). Recycling does
/// not regress accuracy because it does not affect accuracy at all.
pub const MARL8_NO_REGRESSION: f32 = 1.05;

/// G27 (b): transplanted kernels whose weight has risen above a tenth of
/// the child's mean |w|.
///
/// PROPOSED as a floor. Transplants start at zero; if they are in the
/// wrong place for their new region they stay near zero and the mechanism
/// is a no-op dressed as a saving. Half, because some fraction of any
/// donor set lands where the new region has nothing for it to do.
pub const MARL8_ADOPTION: f32 = 0.5;

// ── MARL-9 (per change, or per thing learned?) ───────────────────────
//
// From `tools/marl9_predict.py`. Every drift this campaign has run has
// been the same shell translated, so when capacity grows linearly with the
// number of moves there is no way to tell whether the model pays per
// CHANGE or per THING LEARNED — the two have been the same number all
// along. MARL-9 separates them with two arms of six moves each:
//
//     CYCLE — A B A B A B: six changes, two worlds of distinct structure
//     WALK  — six different worlds: six changes, six worlds' worth
//
// No new mechanism. Just a fixture that can tell the two currencies apart.

/// G29: child population after six moves, cycling over walking.
///
/// PROPOSED from MARL-6's hysteresis, which is a two-move version of the
/// cycling arm and showed no saving whatever: one round trip took 4 339
/// child kernels to 7 883, and the return spike was the same size as the
/// departure. At or above 0.9 the two arms are the same and capacity is
/// paid PER CHANGE — the model billed for the event rather than for what
/// it learned, which is a much sharper statement of MARL-7's pathology
/// than "capacity is bought".
///
/// The threshold is deliberately written so that its FAILURE is the
/// interesting outcome. If cycling is materially cheaper then latent reuse
/// exists, MARL-8's failure was about its mechanism rather than about the
/// possibility, and the dictionary is worth building.
///
/// **REFUTED, in the direction that was worth being wrong about.**
/// Measured 0.574 over six moves and 0.687 over four. Cycling is far
/// cheaper than walking, so capacity is paid PER THING LEARNED and not per
/// change. The marginal cost of a revisit decays — 2 140, 971, 745, 527,
/// 368, 371 across six moves, and down to 159 by the twelfth — against a
/// walking arm flat at about 2 100 a move.
///
/// This overturns MARL-6's hysteresis reading, which measured ONE round
/// trip, saw the return spike at full size and concluded "no memory, only
/// accumulation". The spike is the transient. The settled state is not it:
/// over repeated visits both the error and the marginal cost improve.
///
/// And it explains MARL-8 completely. The model already reuses capacity on
/// recurrence, with no mechanism at all, so an explicit transplant had
/// nothing left to add — which is exactly what recycling measured.
pub const MARL9_RECURRENCE: f32 = 0.9;

/// G29, the control: RMS of the cycling arm over the walking arm.
///
/// PROPOSED as a comparability band. A cycling world is genuinely easier —
/// half the distinct structure — so the cycling arm should if anything be
/// MORE accurate. Well outside this in either direction means the arms are
/// not comparable and their populations cannot be read against each other.
///
/// **HELD, and on the generous side.** The cycling arm is not merely
/// comparable, it is BETTER — RMS 0.03182 against 0.04514 over six moves,
/// 0.04550 against 0.06722 over four. Half the distinct structure, less
/// capacity spent, and a lower error.
pub const MARL9_FAIR: f32 = 1.15;

// ── MARL-10 (does recurrent growth plateau?) ─────────────────────────
//
// From `tools/marl10_predict.py`, and it is a LAW fitted to MARL-9's
// twelve points rather than a threshold picked from a range. On a fully
// recurrent world n·ΔK is flat at 2034 (spread 1776–2290, no trend), so
// ΔK ≈ A/n and cumulative growth is LOGARITHMIC — unbounded in principle,
// bounded in any practice. Eighty moves is where that stops being
// indistinguishable from a linear tail at 159 a move: 15 335 against
// 22 468.

/// G30: child population after eighty moves, over the harmonic law's
/// prediction of 15 335.
///
/// PROPOSED at a ceiling of 17 635, which is 79% of what a linear tail
/// would reach. The two hypotheses cannot both pass, which is the whole
/// reason for running eighty rather than twenty.
///
/// **HELD, at 1.033.** Eighty moves reached 16 241 kernels against the
/// harmonic law's 15 726; a linear tail would have reached 23 396. And
/// n·ΔK stays flat across the whole run — 1972, 1764, 1890, 2166, 2252 by
/// successive stretches — so the law is not merely fitted at the ends, it
/// holds throughout.
///
/// One honest caveat on the test: the run used 200 000 exemplars a move
/// rather than the 100 000 the fit was taken from, because
/// `--drift-repeat` reads `--exemplars` and its default is 200 000. The
/// law survives that unasked-for doubling with A drifting about 8%, which
/// is a stronger result than the one intended — the growth constant barely
/// depends on how long each world is shown.
pub const MARL10_LOGARITHMIC: f32 = 1.15;

/// G30, the health check: RMS at move 80 over RMS at move 12.
///
/// PROPOSED because a bounded population proves nothing if it is bounded
/// by the model having stopped working. Eighty world-changes is far
/// outside anything this campaign has run.
///
/// **HELD at 0.849, on the right side of one.** RMS goes 0.02635 at move
/// 12 to 0.02234 at move 40 to 0.02237 at move 80. The model does not
/// merely survive eighty world-changes, it gets BETTER across them and
/// then holds — which is what a bounded population had to be checked
/// against, because a population bounded by the thing having stopped
/// working would look identical on the count alone.
pub const MARL10_STABLE: f32 = 1.25;

// ── MARL-11 (the marble: the first external baseline) ────────────────
//
// From `tools/marl11_predict.py`, which designs the fixture, measures its
// geometry on the same grid the Zig builds, and derives these four from
// that geometry and the campaign's own measured constants.
//
// Ten phases and every comparison in them was MARL against MARL. `rbf.fit`
// is the first thing to measure against that this campaign did not write:
// the same anisotropic Gaussian held bit for bit by G17 (a), the same
// CUTOFF, the same evaluator, fitted by BATCH ADAM, gated since before
// `marl.zig` existed. But it does not start level — it seeds centres ON
// vein voxels and draws half its pool FROM vein voxels, which are
// hand-built versions of exactly what MARL-3 and MARL-4 spent two phases
// discovering the model could not do for itself. So the phase is a 2×2
// with one variable a cell, capacity matched exactly (each rbf arm runs at
// the count the MARL arm beside it discovered) and DATA held equal (MARL
// sees each exemplar once; rbf gets the same pool and may re-read it).

/// G31 (a): capacity concentration in the vein band, arm D — kernels on
/// structure over kernels in all, divided by the band's own volume
/// fraction. One is a uniform allocator; 1/f is every kernel on structure.
///
/// PROPOSED at 3.1, which is 75% of the 4.11 the geometry predicts, and
/// never below MARL-4's best of 2.50 on the synthetic truth. The mechanism
/// is that a real field's matrix is EXACTLY zero and an empty model
/// predicts EXACTLY zero, so surprise there is 0 ≤ θ and nothing is born —
/// the quiet slab of §8, arriving on a field nobody designed to have one.
/// The dilution is the model's own tail: a newborn carries the residual as
/// its weight, so it reads above θ out to 2.54σ and cancelling that costs
/// kernels on the matrix side of the edge.
///
/// Below MARL-4's number the phase would be claiming a real field is
/// HARDER to place capacity on than the one the mechanism was built
/// against, which is the finding this floor exists to make visible.
///
/// **HELD, at 4.17 (arm D), against a prediction of 4.11.** The closest
/// any number in this campaign has come to its own pre-registration, and
/// it is the geometric argument being right rather than luck: the ceiling
/// is 1/f = 10.67, the dilution is the newborn tail's 2.54σ leak into the
/// matrix, and 10.67 × 1.498/3.890 is 4.11.
///
/// The comparison that gives it meaning is arm B's 1.33 — batch Adam,
/// seeded uniformly, at the SAME kernel count, barely above the 1.0 of an
/// allocator that does not allocate. MARL places capacity three times
/// better than a blind batch optimiser can, and G31 (b) then measures what
/// that is worth.
pub const MARL11_CONCENTRATION: f32 = 3.1;

/// G31 (b): arm B over arm A — batch Adam blind, over batch Adam with both
/// oracles, at the same kernel count.
///
/// PROPOSED as a FLOOR at 1.5, which is 60% of the 1.69 predicted from
/// rbf's seed reach (CUTOFF_R·vein = 4.07 of an extent of 32, so a
/// uniformly seeded kernel is live with probability 0.35) and the N^(−1/2)
/// error of a 2-D structure fitted by N kernels.
///
/// A floor rather than an estimate because of what the number is FOR: if
/// the oracle turns out not to matter, arms C and D are the same test and
/// the headline comparison is not a comparison. This fails loudly in that
/// case, which is the only outcome that would invalidate the phase.
///
/// **REFUTED, and left standing.** Measured 1.32–1.35 across two seeds,
/// under the floor of 1.5 and well under the 1.69 predicted.
///
/// The over-estimate is in the N^(−1/2) step, not in the mechanism. The
/// dead-kernel argument is sound — a uniformly seeded kernel more than
/// CUTOFF_R·vein from any vein has a gradient of exactly zero and Adam
/// never moves it — but a batch optimiser with 2.7× fewer live kernels
/// does not lose the full N^(−1/2) of accuracy, because the live ones
/// widen to cover more and the field is a SHEET, whose error is dominated
/// by the thin direction that extra kernels along it do not help.
///
/// It does not invalidate the phase: 1.32 is still a real gap, and the
/// oracle moves MARL by 1.74 (0.143 → 0.084), so arms C and D are firmly
/// different tests. That was the only thing this floor was protecting.
pub const MARL11_ORACLE_WORTH: f32 = 1.5;

/// G31 (c), THE HEADLINE: arm D over arm B — MARL blind over rbf blind, at
/// matched capacity and equal data.
///
/// PROPOSED as a CEILING at parity. Not at a comfortable margin: this is
/// the one number in the phase that can embarrass the campaign, and a
/// ceiling of 1.0 is what makes it able to.
///
/// The campaign's own findings say MARL should win it. MARL-3: capacity
/// concentration is bounded by EVIDENCE concentration, and surprise IS
/// evidence, so a birth cannot land where the field is already right.
/// MARL-1: deformation buys 2.15× AFTER the topology is found, and a
/// kernel seeded in the matrix beyond CUTOFF_R·σ of any vein has a gradient
/// of EXACTLY zero — the hard cutoff makes it dead on arrival, and Adam
/// cannot move a centre it has never touched.
///
/// Against MARL: it sees each exemplar once where rbf re-reads its pool
/// with a global optimiser and full second-moment information. MARL-6R
/// priced that at G24 — a sixth of the evidence cost 2% of the accuracy —
/// so evidence is cheap on the margin and placement is not.
///
/// **REFUTED, and left standing — the campaign's headline loss.** Measured
/// 1.95–1.99 across two seeds. MARL, blind, loses to batch Adam, blind, by
/// very nearly two at matched capacity and equal data.
///
/// Both halves of the prediction's reasoning were CORRECT and the
/// conclusion did not follow. MARL's concentration is 4.17 against arm B's
/// 1.33, so surprise-driven birth really does place capacity where a blind
/// seeding cannot, exactly as MARL-3 said it would. And arm B really is
/// carrying dead kernels. The error was assuming placement was the binding
/// constraint, because placement is what ten phases had been about — the
/// campaign had never once been in a position to see anything else bind.
///
/// What binds is EVIDENCE, and G31 (c) measures it: over a 64-fold stream
/// the RMS falls 0.143 → 0.051 and crosses both rbf arms, while the
/// concentration does not move (4.17 → 3.75). So the online learner is not
/// a worse fitter than batch Adam. It is a hungrier one, and it buys
/// kernels rather than passes to get there — 3 285 against 1 583 for the
/// same field. Which is MARL-7's "capacity is always bought, never
/// borrowed" arriving from a direction the campaign had not tried.
pub const MARL11_DISCOVERY: f32 = 1.0;

/// G31 (d): arm C over arm A — online local NLMS against batch global
/// Adam, with the oracle stream given to both.
///
/// PROPOSED as a CEILING at 2.0. MARL should LOSE this one: MARL-0
/// measured Adam as the wrong optimiser per exemplar (RMS ROSE 0.131 →
/// 0.151 over 200 000), but this is Adam in the regime it was designed
/// for, and that finding does not transfer.
///
/// The ceiling is where it is because losing by more than 2× to a batch
/// optimiser given the same evidence would say the online learner is not a
/// competitive fitter, only a cheap one — and that is worth knowing before
/// an irradiance cache is built on it.
///
/// **HELD, at 1.51.** With the oracle stream given to both, one pass of
/// local NLMS costs half again what 600 batches of global Adam cost, on a
/// field neither was written against. That is the number to hold onto
/// before an irradiance cache: not free, not disqualifying.
///
/// Note what it is NOT evidence for. C and A are matched on kernels and on
/// distinct exemplars, and arm A re-reads its pool 4.7 times where arm C
/// sees each point once — so 1.51 is the price of a SINGLE PASS, and G31
/// (c) says most of it is bought back by lengthening the stream rather
/// than by changing anything.
pub const MARL11_ONLINE_COST: f32 = 2.0;

// ── MARL-12 (nine channels on one geometry) ──────────────────────────
//
// From `tools/marl12_predict.py`. MARL-11 measured one channel — the
// vein's blend, where a vein's geometry lives. `rbf.fit` fits NINE, and
// the nine share one centre and one shape; that sharing is the entire
// reason a packed set is cheaper than a volume texture, and the campaign
// could not test it until the kernel's weight was widened from one float
// to C of them.
//
// The refactor's own gate is not a threshold: at C = 1 every number from
// G17 to G31 must be IDENTICAL, and that is checked by diffing the suite
// against HEAD rather than by a bound.

/// G32 (a): kernels at nine channels over kernels at one, same stream.
///
/// PROPOSED as a CEILING at 1.15. A birth needs surprise above θ AND no
/// existing kernel covering within the responsibility radius, and the
/// second test is PURELY GEOMETRIC — a max over gaussians that knows
/// nothing about channels. So nine channels cannot buy a birth that one
/// would not have bought in the same place. What they do change is how
/// often surprise clears θ, since the magnitude is a max over channels and
/// so never smaller than channel 0's alone.
///
/// Above this ceiling, "the geometry is paid for once" is false and a
/// packed set is not the saving it is sold as.
pub const MARL12_COUNT: f32 = 1.15;

/// G32 (b): the BLEND's own error learned with eight other channels, over
/// the same channel learned alone.
///
/// PROPOSED as a CEILING at 1.25. Inside one material every channel is
/// A(x) times a constant, so the nine are exactly collinear and a shared
/// basis carries all of them at no loss — which is why the fixture carries
/// TWO materials split across x. A fixture that can only agree with the
/// hypothesis is not a fixture.
///
/// A kernel is σ = 0.943 wide in the volume's units against an extent of
/// 32, so the seam compromises about 6% of the sheet, and on a 2-D
/// structure whose error goes as N^(−1/2) that is about 1.03. The ceiling
/// is eight times that margin because the geometry's descent is not
/// confined to the seam — the centres now move on the sum over nine
/// channels of each weight's attribution — and this is the first time
/// anyone has looked.
pub const MARL12_SHARING: f32 = 1.25;

/// G32 (c): arm D over arm B at nine channels.
///
/// PROPOSED as a CEILING at 2.0 — deliberately the same shape AND the same
/// value as `MARL11_ONLINE_COST`. MARL-11 found the binding constraint is
/// EVIDENCE and not placement, and the widening changes no exemplar count:
/// the same stream arrives, each exemplar now carrying nine numbers
/// instead of one. If what binds has not moved, this should sit where the
/// one-channel number sat.
pub const MARL12_ONLINE_COST: f32 = 2.0;

// ── MARL-13 (the occlusion cache: the first NOISY field) ─────────────
//
// From `tools/marl13_predict.py`. Twelve phases and every field the
// campaign learned was EXACT. Ambient occlusion is (1/M)·Σ V(x, ωᵢ) over M
// sampled directions — a Binomial(M, p)/M estimate with σ = √(p(1−p)/M),
// a half at one ray and a sixteenth at sixty-four. G33 (a) measures the
// fixture's estimator against that theory and it tracks it.

/// G33 (b): how far the measured RMS² at M = 4 sits from the line through
/// M = 1 and M = 16 in 1/M.
///
/// PROPOSED at 1.30 either side, and it is a LAW rather than a bound.
/// NLMS with step μ does not converge on noisy data, it hovers, and the
/// hovering costs μ/(2−μ) of the measurement variance no matter how much
/// data arrives. So
///
///     RMS² = bias² + μ/(2−μ) · V/M
///
/// which is linear in 1/M. Fitted from the ends and checked in the middle,
/// as MARL-10's law was: a line through two points is not a claim, the
/// third point is.
///
/// This is the first thing the campaign has met that MORE DATA DOES NOT
/// FIX, which is the opposite of everything MARL-11 concluded and is why
/// it is gated as a law rather than mentioned as a caveat.
///
/// **HELD, at 1.023.** RMS at M = 1/4/16 is 0.35980/0.22497/0.17174; the
/// line through the ends predicts 0.22246 at M = 4 and the measurement is
/// 0.22497. The intercept — the representation error with the noise
/// extrapolated away — is 0.15110.
///
/// One thing the law does NOT explain, and it is worth more than the fit.
/// The slope implies a variance of 0.32, and a binomial's is at most 0.25,
/// so something else is scaling with the noise. It is CAPACITY: 9 923
/// kernels at one ray a sample against 7 656 at sixteen, for the same
/// 60 000 samples. A noisy residual crosses the surprise threshold where a
/// clean one would not, so the model births on noise — §5's "do not
/// confuse noise with complexity" arriving as a measurement rather than an
/// instruction.
pub const MARL13_NOISE_LAW: f32 = 1.30;

/// G33 (c): RMS at `rate_w` 0.5 over RMS at 0.05, at one ray a sample.
///
/// PROPOSED as a FLOOR at 2.0. The theory says 3.6 — √(0.3333/0.0256) —
/// and the floor is two because the bias term does not shrink with the
/// rate and caps how much of the 3.6 can show.
///
/// Derived before the run, not swept. It is MARL-12's √C in another
/// disguise: a default that was correct on the data the campaign happened
/// to have, and wrong the moment the data changed character. `rate_w` 0.5
/// answers one exemplar exactly and hovers at 0.577σ forever; 0.05 costs
/// 0.160σ and still converges to 1e-7 over the ~300 samples a kernel sees.
///
/// **REFUTED, and left standing.** Measured 1.29 against a floor of 2.0.
///
/// The diagnosis is the phase's finding. The LMS floor analysis treats the
/// model as a fixed basis with noisy weights, and this model is not that.
/// Noise enters by THREE doors and `rate_w` closes one:
///
///   the WEIGHTS  — `rate_w`, the door the theory is about. Worth 1.29.
///   the GEOMETRY — `rate_geom`, since a noisy residual moves centres and
///                  shapes as readily as weights. Closing it as well takes
///                  the total to 1.67 AND drops the population from 11 176
///                  to 7 113, because a settled geometry covers better and
///                  births less.
///   the TOPOLOGY — births are gated on the RAW surprise, which is noisy
///                  however slowly the weights follow it. No rate closes
///                  this one; it needs a noise-aware birth test, and that
///                  is not built.
pub const MARL13_RATE_BOTH_DOORS: f32 = 1.67;
pub const MARL13_RATE: f32 = 2.0;

/// G33 (d), THE HEADLINE: RMS(MARL) over RMS(a dense grid), at EQUAL BYTES
/// and EQUAL RAY BUDGET.
///
/// PROPOSED as a CEILING at parity, as MARL-11's headline was and for the
/// same reason — it is the number that can embarrass the campaign, and a
/// comfortable margin would stop it being able to.
///
/// `rbf.zig` exists because Christian asked for a packed Gaussian set
/// "instead of the giant volume texture", so the giant volume texture is
/// who it has to beat. Equal bytes because memory is what a cache is
/// rationed by; equal rays because the rays are the expense being cached,
/// and a grid handed unlimited rays would be compared on a resource nobody
/// has.
///
/// The case for the grid is stronger than it looks: at 1 500 kernels it
/// gets 24³ cells and ~578 rays each, so its own noise is 0.021 and it is
/// limited by RESOLUTION rather than by noise — and it never has to work
/// out where to look. The case for MARL is that a grid spends its cells
/// uniformly while occlusion is ~1 over the open majority of the cube, and
/// that many samples can be averaged through one kernel where a grid cell
/// gets one shot at its own centre.
///
/// **REFUTED at 1.854, and the refutation is the useful part.** MARL
/// scores 0.12568 against the grid's 0.06779 at 365 KiB against 356, both
/// spending 2 000 000 marched directions.
///
/// TWO mechanisms came out of it, both gated in G33 (d).
///
/// **The background.** A hard cutoff makes a Gaussian decay to EXACTLY
/// zero, so a constant non-zero background is not free — it has to be held
/// up by overlapping kernels everywhere it extends. Occlusion is ≈1 across
/// the open majority of a cube. Every field this campaign ever learned had
/// a ZERO background (the quiet slab, the marble's matrix), so it never
/// grew the bias term `rbf.zig` has had from the day it was written — "the
/// entry is the BIAS: the matrix costs nothing, only the structure costs
/// kernels". Learning `1 − AO` instead, which is one negation and no new
/// code, scores 0.08975 with 8 057 kernels: 1.40× the accuracy for 14%
/// less capacity.
///
/// **The domain.** A grid pays memory for every cell whether or not
/// anything is ever asked there. A renderer asks for occlusion at SHADING
/// POINTS, which are on surfaces — so the volume-uniform comparison above
/// is the artificial one. Restricted to a shell around the geometry, MARL
/// scores 0.13222 at 139 KiB against the grid's 0.14503 at 128, a ratio of
/// **0.912**, with a lookup 2× cheaper than in the volume case because the
/// population fell to 3 547.
///
/// So the packed set does beat the giant volume texture, in the regime
/// `rbf.zig` was written for and not in the one this threshold assumed:
/// when the interesting set is SPARSE IN THE DOMAIN. The marble's veins
/// were. A volume-filling occlusion field is not. That is the sentence the
/// phase bought, and it is worth more than the parity it was set at.
pub const MARL13_SHELL: f32 = 0.912;
pub const MARL13_TEXTURE: f32 = 1.0;

// ── MARL-14 (distillation: resampling the solution) ──────────────────
//
// From `tools/marl14_predict.py`. Christian's idea: once a model is built,
// sample IT to train another. A teacher is two things no field in this
// campaign has ever been — NOISELESS, which closes all three of MARL-13's
// doors at once, and UNLIMITED, which lifts MARL-11's binding constraint.
// The student is scored against the TRUE field throughout, never against
// its teacher.

/// G34 (1): student kernels over teacher kernels, at matched options.
/// PROPOSED at 0.95 — a modest FREE saving, being the capacity MARL-13
/// measured as bought on noise, which a clean teacher cannot sell.
pub const MARL14_FREE: f32 = 0.95;

/// G34 (2): the RMS cost of HALVING the population, by raising the
/// surprise threshold. PROPOSED at 1.5. With a noisy field a high θ is
/// dangerous — a residual above it might be a sampling wobble, which is
/// MARL-13's third door — but with an exact teacher every residual above θ
/// is real structure, so θ becomes a clean accuracy dial. This is "it
/// doesn't have to be perfect" as a mechanism rather than a hope.
pub const MARL14_TRADE: f32 = 1.5;

/// G34 (3): teacher kernels over student kernels at `regions` 3.
/// PROPOSED as a FLOOR at 3.0. σ_max = h/√CUTOFF, so halving the region
/// count doubles every kernel, and tiling a nearly two-dimensional shell
/// with balls of twice the radius needs about four times fewer. Three
/// rather than four because the shell has thickness and the clamp will not
/// let a kernel's cutoff box exceed h on any axis.
pub const MARL14_COARSE: f32 = 3.0;

/// G34 (4): the second copy's cost over the first's, A→B→C.
/// PROPOSED as a CEILING at 1.0 — generation loss must not compound. The
/// argument is structural: B is a sum of anisotropic gaussians, which is
/// EXACTLY the student's hypothesis class, and the truth is not. A→B pays
/// a representation cost; B→C is fitting something it can represent
/// perfectly given enough kernels.
pub const MARL14_GENERATION: f32 = 1.0;

// ── MARL-15 (quantization: what a shippable kernel costs) ────────────
//
// From `tools/marl15_predict.py`. Every byte count this campaign has
// quoted is f32 on both sides — fair, and uncompressed. The two sides do
// not quantize alike: a grid of values in [0, 1] goes to eight bits for
// essentially nothing, where an RBF set's ten floats have wildly different
// sensitivities and the weight sits in a sum where neighbours cancel.

/// G35: RMS at the 16/10/10/12 allocation (120 bits, 15 bytes, a 2.7×
/// saving) over RMS in f32. PROPOSED as a CEILING at 1.05, from the
/// per-field sensitivity analysis — the centre's 0.6065·|w|·ε/σ dominates,
/// because σ is a seventeenth of the domain and an error measured against
/// the domain is amplified seventeenfold before it reaches the field.
///
/// If a kernel cannot survive fifteen bytes, the packed set is not a
/// shippable representation and MARL-14's memory claim needs restating in
/// f32 terms only.
///
/// **HELD, at 1.000 — and the analysis behind it was pessimistic by about
/// fivefold.** The sweep, on MARL-14's shipped 814-kernel student:
///
///     120 bits  12.0 KiB  1.000      74 bits  7.4 KiB  1.004
///      94 bits   9.4 KiB  1.000      68 bits  6.8 KiB  1.010
///      54 bits   5.4 KiB  1.086      40 bits  4.0 KiB  1.608
///
/// So a kernel ships in **8.5 bytes**, not fifteen — a 4.7× saving for one
/// per cent of the accuracy, and the knee is sharp: 54 bits breaks the
/// ceiling and 40 fails outright, which is what says the sweep is not
/// decoration.
///
/// The prediction's error is worth keeping. It is NOT the weights, which
/// was the first thing to check: the span measures −0.4982 … 1.3759, so
/// |w| is slightly ABOVE the 1.0 assumed and makes the analysis worse.
/// It is that PEAK SENSITIVITY AND PEAK OVERLAP DO NOT COINCIDE — the
/// derivative's maximum is at r = 1 exactly, and a point at r = 1 of one
/// kernel is far out in the tails of most of the others, where both value
/// and derivative are near zero. Compounding a worst case over an assumed
/// overlap count multiplies two things that never happen together.
pub const MARL15_BITS: f32 = 1.05;

/// G35: MARL over the grid with BOTH compressed. PROPOSED as a CEILING at
/// 1.15, deliberately NOT at parity: the derivation says quantization
/// roughly cancels the distilled model's advantage and lands near 1.06, so
/// a gate at parity would be pre-registering a refutation rather than
/// testing anything. What 1.15 tests is whether an RBF set quantizes
/// SUBSTANTIALLY worse than the sensitivity analysis says — which is what
/// would actually be news, and what would make the packed set unshippable.
///
/// Either way the honest sentence is that MARL-14's 0.878 is an f32
/// number, and under compression the two representations are expected to
/// be about level on this field.
///
/// **HELD, and quantization IMPROVES MARL's position rather than
/// cancelling it.** The derivation predicted 1.06 on the assumption that a
/// grid compresses 4× and a kernel only 2.7×. A kernel compresses 4.7×
/// with absolute centres and **5.9× with region-relative ones**, so the
/// packed set gains MORE from compression than the texture does and the
/// f32 comparison was, if anything, unfair to it.
///
/// At the production encoding — 54 bits, region-relative — MARL is 0.16230
/// at 5.5 KiB. A cubic grid cannot land on that budget: 17³ is 4.8 KiB and
/// 18³ is 5.7, so BOTH are measured and the assertion is made against the
/// larger, the grid given MORE than its share.
///
///     f32, MARL-14                        0.878
///     8-bit absolute centres              0.859
///     54-bit region-relative, grid under  0.769
///     54-bit region-relative, grid over   **0.804**  ← the gated one
pub const MARL15_HEADLINE: f32 = 1.15;

/// G35, the region-relative extension. From `tools/marl15_predict.py`'s
/// second section, written after the absolute sweep ran and before this
/// one did.
///
/// G35's ablation found the centre is the ONLY expensive field — 0.01872
/// of excess RMS at eight bits against the weight's exactly zero — and
/// that its cost is a SPAN choice rather than a sensitivity: quantized
/// over the whole extent it steps 0.066σ. But a kernel's centre is inside
/// its owning region by definition, so the span is `extent/regions`.
///
/// The centre's 8-bit excess ABSOLUTE over the same excess RELATIVE.
/// PROPOSED as a FLOOR at 2.5 where the geometry says 3.0, because the
/// excess is a small difference of two nearby RMS values and does not
/// measure to three figures.
///
/// **HELD, at 6.16×** — twice the 3.0 the geometry predicts. Excess 0.01872
/// absolute against 0.00304 relative, at eight bits with the other three
/// fields left in f32.
///
/// Read the numerator, not the ratio. The relative excess is 0.00304 on an
/// RMS of 0.163, which is a difference of 0.00003 in the fourth decimal —
/// at the edge of what 512 probes resolve. The safe reading is that the
/// centre stops being the expensive field, not that the saving is exactly
/// six-fold.
pub const MARL15_RELATIVE: f32 = 2.5;

/// The same ceiling as `MARL15_BITS`, applied at 54 bits with relative
/// centres — 6.75 bytes a kernel, a 5.9× saving. PROPOSED at 1.05 with a
/// derived expectation of 1.043, propagated through the ablation's own
/// per-field numbers.
///
/// The point of the number is that a bit budget which FAILED absolute
/// (54 bits measured 1.086) must PASS relative, or the change has bought
/// nothing worth the count table.
///
/// **HELD, at 0.995 — no measurable cost at all**, where the same 54-bit
/// budget with absolute centres cost 8.6%. 5.5 KiB for the 814-kernel
/// model, a 5.93× saving on f32.
///
/// 0.995 is not "better than f32"; it is indistinguishable from it. The
/// two are scored on the same probes so the paired difference resolves
/// well, but half a per cent is not a claim worth making.
///
/// So the production encoding is **54 bits — 6.75 bytes — a kernel**:
/// 6 bits an axis of region-relative centre, 5 of log-diagonal, 5 of
/// off-diagonal, 6 of weight, plus a u16 count per region.
pub const MARL15_RBITS: f32 = 1.05;

// ── MARL-16 (a learned background) ───────────────────────────────────
//
// From `tools/marl16_predict.py`. `rbf.zig` has had this since the day it
// was written — "the entry is the BIAS: the matrix costs nothing, only the
// structure costs kernels" — and MARL never needed it, because every field
// it learned before MARL-13 had a ZERO background. Occlusion does not.

/// G36: RMS with a learned bias over RMS without, on MARL-13's losing
/// configuration (volume-uniform occlusion, learned directly).
///
/// PROPOSED as a CEILING at 0.85 — at least a 1.18× improvement, against
/// the 1.40× that being TOLD the background was worth (MARL-13's
/// inversion). Set BELOW the inversion's number deliberately: inversion
/// sets the background to the value of the largest flat region, and a
/// least-squares bias converges to the MEAN of what the kernels have not
/// explained. Those coincide only when one region dominates.
///
/// **REFUTED, twice, and left standing.** A bias from the RESIDUAL scores
/// 1.302× and strands itself at 0.1057; a bias from the TARGET converges
/// correctly to 0.7211 — the field's actual mean — and scores **5.679×**.
/// The better estimator is the worse model, which is what says the fault
/// is not in the estimator.
///
/// A Gaussian basis with a HARD CUTOFF cannot cheaply represent a plateau
/// of ANY value. Zero is not special because it is zero; it is special
/// because it is what an EMPTY MODEL ALREADY PREDICTS, so a target that is
/// zero over a large region costs literally nothing. A bias moves that
/// free value from 0 to b — it helps where y ≈ b and it hurts everywhere
/// y ≈ 0, which now has to be held DOWN by kernels that did not need to
/// exist. Measured: 0.123 of this field is within θ of zero against 0.049
/// within θ of the bias, a losing trade by 2.5×.
///
/// **And a claim in MARL-13's ledger entry was wrong.** It said `rbf.zig`
/// has had a bias term since it was written and MARL never grew one.
/// `rbf.zig`'s "entry" is NOT a learned constant: it is the HOST's own
/// material, supplied per hit, showing through where the kernels are
/// silent — and the kernels carry a blend that is ZERO in the matrix.
/// That is exactly what MARL already does. **MARL was never missing the
/// term**, and this phase is the correction.
pub const MARL16_BIAS: f32 = 0.85;

/// G36: kernels with a bias over kernels without. PROPOSED as a CEILING at
/// parity — the bias removes work from the kernels and cannot add any. The
/// one way it could go wrong is the warm-up, which is why the step is 1/n
/// and not a small constant: at n = 1 the bias IS the first exemplar, so
/// it cannot buy kernels to hold up a constant it is about to learn.
///
/// **REFUTED.** 1.085× from the residual form and 1.342× from the target
/// form. The bias does not remove work from the kernels, it relocates it —
/// from holding up the open majority to holding down the solid interior —
/// and relocating it costs more than it saves on this field.
pub const MARL16_KERNELS: f32 = 1.0;

/// G36, THE TRADE: the whole-field disturbance from one late event, times
/// n, over the event's residual.
///
/// PROPOSED as a CEILING at 1.5, where a pure running mean gives exactly
/// one and the slack is for the kernels' own contribution to the same
/// event.
///
/// `CUTOFF` makes a learning event structurally unable to disturb a
/// distant region, and G17 (c)/(d) check it bitwise. A global scalar is
/// not local at all: one update moves every point by the same amount. This
/// is the campaign giving up EXACT locality for ASYMPTOTIC locality, and
/// the number exists so that the trade is stated rather than hidden. An
/// EWMA would give up both — its step never decays, so no region is ever
/// undisturbed again — and that is what `rate_bias > 0` is for, knowingly,
/// on a field that drifts.
///
/// **HELD, at 0.272.** One late event at probes over 0.4 of the domain
/// away moves a biased model by 2.26e-6 on a residual of 1.04 after
/// 125 001 exemplars, and moves an unbiased one by **exactly 0.00** —
/// exact locality, bitwise, which is the mutation that says the number is
/// measuring the bias and not the kernels.
///
/// So the trade is real and it is priced: a background term is available
/// at the cost of asymptotic rather than exact locality. It is simply not
/// worth buying on a field with a large zero mass.
pub const MARL16_LOCALITY: f32 = 1.5;

// ── MARL-18 (consolidation: is a distilled student a better place to
//    LEARN from?) ────────────────────────────────────────────────────
//
// Christian's plan for the day opens on a premise: "the distilled student
// has been observed to achieve significantly lower error than the
// teacher". **MARL-14 measured the opposite at every point of its sweep**
// — 1.058 at matched options, rising to 1.141 at the coarsest. The number
// that reads like the claim is 0.878, and it is the student against a
// SAME-SIZED GRID: a statement about the opponent, not about the teacher.
//
// The plan survives the correction and gets better for it, because
// MARL-14 distilled a model and STOPPED. It never resumed learning. The
// student is worse at the instant of the copy; whether it is a better
// PLACE TO LEARN FROM is a different claim and has never been run.
//
// `tools/marl18_predict.py` has the two mechanisms pulling each way. The
// short version: the coverage gate means a region that has already spent
// kernels CANNOT BUY MORE however badly placed they are, and consolidation
// is the only operation in the codebase that unlocks it — it does not
// remove kernels, it declines to rebuild them. Against that, MARL-13 (b)
// says the error on a noisy field is variance-limited and the variance
// term belongs to the RATE, which a consolidation does not touch.

/// G37: RMS(student)/RMS(teacher) at matched options on the same probes,
/// sixteen rays. PROPOSED as a FLOOR at parity.
///
/// A student sees only its teacher's output, so it has no access to
/// anything the teacher got wrong: its best case is an exact copy and its
/// actual case is a copy on a budget. This restates MARL-14's 1.058 as a
/// CLAIM rather than an observation, so that the plan's premise is what
/// refutes it.
///
/// **HELD, at 1.043.** Teacher 3 387 kernels at 0.13222; the best of a
/// three-point coarseness sweep is 3 228 kernels at 0.13789. MARL-14's
/// 1.058 reproduces on a fresh fixture.
pub const MARL18_PREMISE: f32 = 1.0;

/// G37: the same ratio at ONE RAY a sample, minimised over a coarseness
/// sweep. PROPOSED as a FLOOR at parity, and it is the one mechanism by
/// which the plan's premise could be right.
///
/// Distillation to a SMALLER student is a low-pass filter. If a teacher's
/// error against truth is partly high-frequency — kernels fighting, weights
/// hovering at MARL-13's NLMS floor — then a copy that cannot represent the
/// wiggle is closer to a smooth truth than the original was. That is the
/// textbook regularisation argument for distillation, and it is what
/// "discarding optimisation baggage" would look like as a number.
///
/// MARL-14 saw no sign of it, but its teacher was trained at sixteen rays
/// and is nearly clean. If it exists anywhere it is at one ray.
///
/// **REFUTED, at 0.960 — and this is Christian's premise, in the noisy
/// regime only.** Teacher 5 520 kernels at 0.23875; matched 0.962, θ = 0.1
/// 0.960, and a basis with a THIRD of the kernels (1 712) still 0.971.
///
/// The mechanism is the low-pass one and the sweep is its signature: a
/// shallow U with a minimum at intermediate capacity, which is a
/// bias-variance curve rather than a monotone saving. A student fits its
/// teacher's OUTPUT and has no access to anything the teacher got wrong,
/// so the only way it can come out ahead is by FAILING to reproduce part
/// of it and being better off for the failure.
///
/// **A copy is a filter, and it is worth something exactly when the
/// original is carrying noise.**
pub const MARL18_REGULARISE: f32 = 1.0;

/// G37, THE STAIRCASE: RMS(consolidated)/RMS(straight) at equal reality
/// samples on identical streams. PROPOSED as a FLOOR at parity.
///
/// The plan's central claim is that periodic consolidation escapes
/// learning plateaus. The floor says it does not, on the grounds of
/// MARL-13 (b): on a stationary field the error is variance-limited,
/// `RMS² = bias² + μ/(2−μ)·V/M`, and the variance term belongs to the rate.
/// Each sleep pays MARL-14's 1.058 and buys back only what more
/// updates-per-kernel are worth, which on a converged arm is little.
///
/// Stated as a floor so that the plan refutes it rather than confirming it.
///
/// **REFUTED at one ray, at 0.898; HELD at sixteen, at 1.011.** Three
/// sleeps take 0.23875 to 0.21430 and 5 520 kernels to 3 671 on the noisy
/// field, and cost 1.1% on the clean one where there is nothing to filter.
/// Christian's staircase exists, and it exists where the noise is.
///
/// The control then refuted the phase — see `MARL18_RATE_FIRST`.
pub const MARL18_STAIRCASE: f32 = 1.0;

/// G37: K(consolidated)/K(straight) at equal reality samples. PROPOSED as
/// a CEILING at 0.95 — the minimum claim, that repetition does not erase
/// MARL-14's one-shot 6% saving.
///
/// **REFUTED at sixteen rays by two thousandths (0.952), and held with
/// room at one (0.665).** Stated unconditionally, so a marginal miss in
/// the clean regime refutes it; the finding underneath is that the saving
/// is a function of how much noise the population was bought on, which is
/// `MARL18_GRADIENT`'s business and not this one's.
pub const MARL18_POPULATION: f32 = 0.95;

/// G37, THE GRADIENT: the population saving at sixteen rays over the
/// saving at one. PROPOSED as a FLOOR at parity.
///
/// The population number alone cannot tell "consolidation collects
/// capacity bought on NOISE" from "a re-fit happens to find a leaner
/// solution". The noise story makes a second and harder prediction: the
/// saving must GROW with the noise, because that is what there is more of
/// to collect. MARL-13 measured the prize — 9 923 kernels at one ray
/// against 7 656 at sixteen for the same samples, 23% bought on nothing.
///
/// A flat gradient refutes the mechanism while leaving the population
/// number intact, which is exactly the confound worth a second arm.
///
/// **HELD, at 1.432.** 0.952× at sixteen rays against 0.665× at one. The
/// population saving is half again as large in the noisy regime, which is
/// what makes the mechanism a claim rather than a coincidence: a re-fit
/// that merely found a leaner solution would save the same either way.
pub const MARL18_GRADIENT: f32 = 1.0;

/// G37, THE DIFF (the plan's §3): overlap(student)/overlap(teacher) over
/// K(student)/K(teacher). PROPOSED as a CEILING at parity.
///
/// Christian asked what edits a distillation performs. Kernel identity
/// cannot answer it — a student shares none — so the unit is OVERLAP: how
/// many kernels read above a level at a query point. The trap is that
/// overlap falls when population falls for no structural reason, so the
/// quantity under test is the RATIO OF RATIOS. At 1 the population thinned
/// uniformly and nothing was untangled; below 1 crowded neighbourhoods
/// were preferentially thinned, which is A + B + C + D → X + Y and is
/// Christian's picture.
///
/// **REFUTED, at 1.606 — and refuted the OTHER WAY.** At one ray and
/// matched options the student sheds a THIRD of the population while
/// RAISING the crowding per kernel. **A consolidation does not untangle,
/// it CONCENTRATES**: the ninth item on Christian's list rather than the
/// eighth, low-contribution kernels retired and the survivors left where
/// the queries are.
///
/// And at the RIGHT rates it does neither — G37 (c) measures overlap
/// 2.30 → 2.22 and mean σ 0.0278 → 0.0284, all within a few per cent. The
/// 1.606 belongs to the handicapped regime, where a third of the
/// population was bought on noise and there was something to retire.
pub const MARL18_UNTANGLE: f32 = 1.0;

/// G37 (c): RMS(consolidated)/RMS(straight) at one ray with `rate_w` 0.05
/// AND `rate_geom` 0.02 — MARL-13 (c)'s own best rates. PROPOSED as a
/// FLOOR at parity, and written AFTER G37 (a) and (b) ran.
///
/// (b) refuted MARL18_STAIRCASE at 0.898 and held MARL18_GRADIENT at
/// 1.432: three sleeps beat straight learning by a tenth of the accuracy
/// and a third of the population on a one-ray field, and the saving tracks
/// the noise. Then the control refuted the phase: dropping both rates
/// tenfold reaches 0.18474 at 3 142 kernels in 1.5 s, against
/// consolidation's 0.21430 at 3 671 in 11.6.
///
/// Those arms ran at G33 (d)'s configuration, which pins `rate_geom` to
/// the default DELIBERATELY so that its headline is not configured from
/// its own result. Right for G33; wrong here, because the question is
/// whether consolidation beats LEARNING and that has to mean the best
/// learning this repo knows about.
///
/// So: with the rates already right, does a sleep still buy anything? Every
/// number in (a) and (b) is consistent with one story — a sleep removes
/// the MODEL'S OWN VARIANCE and is worth exactly as much as there is
/// variance to remove (1.011× on a clean teacher, 0.898× on a noisy one,
/// the gradient at 1.432). A rate is the other way not to carry variance
/// and it acts UPSTREAM: it stops the variance entering rather than
/// removing it afterwards. So there should be little left to collect, and
/// MARL-14's 1.058 generation cost should dominate as it does at sixteen
/// rays.
///
/// This number gates a decision. If it is REFUTED — a sleep still pays on
/// top of the right rates — then consolidation does something no rate can
/// and the plan's §4 local micro-distillation is worth building.
///
/// **REFUTED, at 0.940.** Straight learning reaches 0.18954 with 2 984
/// kernels; three sleeps reach 0.17810 with 2 867 — six per cent of the
/// accuracy and four of the memory, ON TOP of the cheap fix.
///
/// The direction of the error is the finding: the win SHRANK from 0.898 to
/// 0.940 when the baseline was corrected, and did not vanish. Every number
/// in G37 fits one story — **a sleep is worth exactly as much as there is
/// variance to remove** (1.011× on a clean teacher, 0.940× at the right
/// rates, 0.898× at the wrong ones) — and a rate is the UPSTREAM way not
/// to carry variance, not a substitute for the downstream one.
///
///     Turn the rates down before you consolidate. It is better and eight
///     times cheaper. Then consolidate anyway, because it still pays.
///
/// So the decision this number gated goes to §4: consolidation does
/// something no rate can. With one qualification the measurement adds — at
/// the right rates a sleep is a RE-FIT and not a restructure, so the local
/// version is a local RE-FIT, and what makes that plausible is exact
/// locality, which G17 (c)/(d) already check bitwise.
pub const MARL18_RATE_FIRST: f32 = 1.0;

// ── MARL-19 (the milk round: does a consolidation refund the capacity
//    that HISTORY bought?) ────────────────────────────────────────────
//
// Christian's clarification of the consolidation idea. You are told to
// deliver the milk on Mondays, so you buy a kernel. Then on Wednesday as
// well — surprise, another kernel. Then Tuesday, Thursday and Friday, and
// you already have kernels refining the parent schedule. Now three or four
// kernels have a sum, and the sum is "deliver the milk Monday to Friday".
// The student never sees the patches. It sees the sum.
//
// MARL-18 concluded "a sleep is worth exactly as much as there is VARIANCE
// to remove" — and its fixture gave it no alternative, because one
// stationary field learned from a noisy estimator leaves noise as the only
// thing a teacher can carry that a student would not rebuild. The milk
// round names a second currency: HISTORY. So `src/milk.zig`'s target is
// ANALYTIC AND EXACT, and if a sleep still collapses the population there,
// MARL-18's sentence is incomplete.

/// G38 (a): K(incremental) / K(from scratch at EQUAL evidence on the final
/// schedule). PROPOSED as a FLOOR at 1.3.
///
/// Five distinct edge positions are presented over the three stages and the
/// final schedule has two, so the path presented 2.5× the destination's
/// structure. The floor sits well under that because capacity does not
/// track edges alone — kernels also tile the interior, where the amplitude
/// has its own structure — so the edge ratio is an upper bound and not an
/// estimate.
///
/// Checked FIRST: if the incremental model carries no premium then this
/// fixture does not reproduce MARL-7's accumulation and nothing downstream
/// of it means anything.
///
/// **REFUTED, at 1.103** — and the reason is worth more than the number
/// would have been. At EQUAL TOTAL evidence the incremental arm carries
/// FEWER kernels than the from-scratch one (6 094 against 6 709) and is
/// behind on accuracy (0.05791 against 0.04351). It is not paying a
/// premium; it is further back, having spent two thirds of its budget on
/// schedules with less structure in them.
///
/// **Nothing it learned became WRONG.** Monday is delivered at every
/// stage, so the reveal is NESTED and MARL-9's law applies in its cheap
/// direction: capacity is paid per THING LEARNED. And MARL-16 covers the
/// only obsolete structure there was — the Tuesday hole sat at ZERO, which
/// is what an empty model already predicts, so holding it down never cost
/// a kernel and there was nothing there to cancel.
pub const MARL19_HISTORY: f32 = 1.3;

/// G38 (a), THE REFUND and Christian's claim: the fraction of the history
/// premium a single sleep gives back,
///
///     (K_incremental − K_distilled) / (K_incremental − K_scratch)
///
/// PROPOSED as a FLOOR at 0.5. Stated against what is ACHIEVABLE rather
/// than as a raw ratio, because a raw ratio cannot tell a good refund on a
/// small premium from a poor one on a large.
///
/// The argument for is Christian's and it is clean: the student is handed
/// the sum and never sees the Tuesday hole being dug and filled in. The
/// argument against is MARL-18's own G37 (c), where a sleep on a clean
/// stationary field moved the population by 0.961× — almost nothing. The
/// difference this fixture introduces is that MARL-18's teacher HAD NO
/// HISTORY, which is what makes the two a test rather than a re-run.
///
/// **REFUTED, at −1.789**: the sleep RAISED the population, 6 094 → 7 110.
/// Partly a harness fault — the dream was 150 000 against a teacher trained
/// on 120 000, and on a noiseless target the dream count is an evidence
/// dial that sets the student's population directly. G38 (c) pins it, and
/// the sign does not change: 6 654 → 6 929 with the dream pinned.
pub const MARL19_REFUND: f32 = 0.5;

/// G38 (a): RMS(distilled)/RMS(incremental). PROPOSED as a FLOOR at parity.
///
/// MARL-18 G37 (a) measured 1.043 for a copy of a sixteen-ray teacher and
/// MARL-14 measured 1.058; both teachers were nearly noiseless. This one is
/// EXACTLY noiseless, so there is no wiggle to filter and a copy should be
/// a pure loss on the metric.
///
/// This is what separates the two currencies cleanly. A large refund with
/// the accuracy unharmed would mean a sleep buys memory for nothing on a
/// field with no noise in it at all — the strongest form of Christian's
/// claim, and it has to refute this number to get there.
///
/// **HELD, at 1.179**, and it is the number that separates the two
/// currencies. A copy of an EXACTLY noiseless teacher is a pure loss —
/// which is what says MARL-18's 0.960 belonged to the teacher's noise and
/// not to the act of copying.
pub const MARL19_COPY: f32 = 1.0;

/// G38 (b), SMOOTHER GROUND: RMS(consolidated then learned) over
/// RMS(learned straight through) at equal further reality. PROPOSED as a
/// CEILING at parity.
///
/// Christian's second half — "the Student can also learn away from the
/// Teacher from the source of truth that the teacher learned from, but now
/// it is learning on smoother ground". The mechanism is the COVERAGE GATE
/// and this fixture maximises it: a birth needs surprise above θ AND no
/// kernel reading above `coverage` within the responsibility radius, so the
/// Tuesday the model must now fill in is exactly where it is LEAST able to
/// buy capacity — locked by its own history. A distilled model arrives at
/// the same place with fewer kernels and the room to birth.
///
/// **HELD, at 0.976 for one sleep and 0.960 for a sleep after every
/// stage** — and the kernel column is the caveat that keeps it from being
/// worth much. The slept arms end with ELEVEN PER CENT MORE capacity
/// (7 357 and 7 412 against 6 620), and this campaign has found four times
/// over that RMS tracks capacity. A 2–4% win carrying an 11% larger
/// population is not a clean result, and G38 (c)'s θ frontier says why: on
/// a noiseless field no student is better than its teacher on both axes,
/// so a slept arm that is ahead is an arm that is bigger.
pub const MARL19_GROUND: f32 = 1.0;

/// G38 (c): K(contradictory path) / K(nested path), at equal evidence and
/// the same final schedule. PROPOSED as a FLOOR at 1.15, and written AFTER
/// G38 (a) and (b) ran.
///
/// `MARL19_HISTORY` was refuted at 1.103 and `MARL19_REFUND` at −1.789 (the
/// sleep RAISED the population). Two reasons, and only one is the
/// harness's fault.
///
/// The confound: the dream count is an EVIDENCE dial that sets the
/// student's population directly, and it was 150 000 against a teacher
/// trained on 120 000. On a noiseless target more evidence buys more
/// kernels. In MARL-14 and MARL-18 noise hid that; here it was the whole
/// effect. This gate pins the dream to the teacher's own evidence.
///
/// The real reason, and it is the finding: at equal total evidence the
/// incremental arm bought FEWER kernels than a from-scratch one (6 094
/// against 6 709) and was simply behind. **Nothing it learned became
/// wrong.** Monday is delivered at every stage, so the reveal is NESTED,
/// and MARL-9's law applies in its cheap direction. The only obsolete
/// structure is two interior edges, and MARL-16 says even those were free:
/// the Tuesday hole was ZERO, which is what an empty model already
/// predicts, so holding it down never cost a kernel.
///
/// **Incremental addition is nested and cheap; it is CONTRADICTION that
/// costs.** So the two paths run side by side —
///
///     nested         {Mon}          {Mon,Wed}      {Mon..Fri}
///     contradictory  {Mon,Tue,Wed}  {Wed,Thu,Fri}  {Mon..Fri}
///
/// — where the contradictory path delivers Monday and Tuesday, stops, and
/// starts again. Kernels pulled to zero stay in the population, which is
/// MARL-7's "the capacity a moved world leaves behind" produced on demand
/// in a noiseless three-stage fixture instead of a six-move drift.
///
/// If the two paths cost the same then history is free in MARL whatever
/// shape it has, MARL-7's accumulation is about something else, and
/// consolidation has nothing structural to collect.
///
/// **REFUTED, at 1.092.** A path that stops delivering Monday and Tuesday
/// and then starts again costs nine per cent more capacity than one that
/// only ever adds — and it is MORE accurate for it (0.05115 against
/// 0.05791), having seen more of the destination's structure earlier.
///
/// So history is nearly free in MARL whatever shape it has: 1.103 nested,
/// 1.092 contradicting. Pulling a weight to zero is cheap, and the kernels
/// left behind are few against a population set by tiling the support.
pub const MARL19_CONTRADICT: f32 = 1.15;

/// G38 (c): the fraction of the CONTRADICTION premium a single sleep
/// returns, `(K_contra − K_contra_slept) / (K_contra − K_nested)`.
/// PROPOSED as a FLOOR at 0.5, with the dream pinned to the teacher's own
/// evidence so the student is not simply handed a larger budget.
///
/// This is the number Christian's claim actually rests on, on the only
/// path shape that can carry it.
///
/// **REFUTED, at −0.491.** With the dream pinned to the teacher's own
/// evidence a sleep still RAISES the population on both paths.
///
/// The θ frontier makes it precise rather than anecdotal. A student chases
/// its teacher at θ, and a teacher's field is a sum of gaussians with
/// ripple at kernel scale, so a low θ buys kernels for the ripple:
///
///     θ = 0.02   1.041× kernels   1.266× RMS
///     θ = 0.05   0.890×           1.268×
///     θ = 0.10   0.736×           1.327×
///     θ = 0.20   0.528×           1.636×
///
/// **No student is better than its teacher on both axes.** Against
/// MARL-14's noisy-field trade — 0.937× kernels for 1.058× RMS at matched
/// options — that is a different regime entirely, and the difference is
/// the noise.
///
/// So two independent fixtures now agree: **a sleep is worth exactly as
/// much as there is VARIANCE to remove.** What a student declines to
/// rebuild is its teacher's noise. Where there is none it costs accuracy
/// and buys capacity.
pub const MARL19_REFUND2: f32 = 0.5;

pub const G1_REFERENCE: []const u8 = "364c3aa756ffaf50aa89774ef63d774c690cc4d934725f7436988cc7a0193825";
