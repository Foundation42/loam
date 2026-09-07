//! marl — MARL-0: local online RBF learning (docs/MARL_CAMPAIGN.md).
//!
//! The campaign's question, and nothing beyond it: **can a sparse set of
//! local radial basis functions learn an unknown 3-D function from single
//! exemplars, using only local updates?** No epochs, no global pass, no
//! backpropagation through anything but the handful of kernels whose
//! support contains the exemplar.
//!
//! ## Why this file is not in a brick
//!
//! Christian's split, and the reason MARL-0 is a standalone model rather
//! than a channel:
//!
//!     Loam's SUBSTRATE — scheduling, publication, deterministic merging,
//!     hashing, lifetimes, the active set              → reusable by MARL
//!
//!     Loam's FIELD STORAGE — sample planes, halos, seams, the B-spline,
//!     the Lipschitz summaries                         → NOT MARL storage
//!
//! A brick is planes of f32 over an 11³ block under a seam contract, a
//! halo contract and a per-channel Lipschitz bound. Kernels are a
//! variable-length parameter list with no per-sample meaning: put them in
//! planes and the seam pass hands brick A's centre coordinates the coarse
//! interpolant of brick B's, and `Summary.lipschitz` bounds the gradient
//! of parameter soup. So the campaign's "the substrate should not know
//! that learning is happening" holds for scheduling and publication and
//! does not hold for storage, and MARL-0 borrows the IDEAS of the
//! substrate here — a region that owns its own state, a conservative
//! bound a query rejects a region by, exact locality — while owning its
//! own memory. Whether kernels ever earn a home inside a brick is
//! MARL-0.5's question, and the saturation data this file records is what
//! it should be answered with (campaign §10).
//!
//! ## The model
//!
//!     ŷ(q) = Σ_i w_i · exp(−½ |Lᵀ_i (q − μ_i)|²)
//!
//! The same anisotropic Gaussian `rbf.zig` fits to the marble and rill's
//! evaluator reads at a particle's state — one channel here instead of
//! nine, because MARL-0's target is scalar (campaign §8). The shape math
//! is a deliberate TWIN of `rbf.zig`'s rather than a call into it:
//! `rbf.zig` now carries a cross-repo bit-pin (its `PIN_KERNELS` table
//! lives identically in rill's gates and in matryoshka's shader), and a
//! learning experiment must not be able to move the kernel out from under
//! three renderers by refactoring. `MARL_PIN` is this file's half of the
//! bargain: `marl.gaussian` and `rbf`'s read the same bits, and the gate
//! that says so is what tells a reader the copy is still a copy.
//!
//! ## Locality is exact, not approximate
//!
//! `CUTOFF` makes a kernel return a HARD ZERO beyond √32 ≈ 5.66
//! Mahalanobis widths — not exp(−16), zero — so the campaign's
//! proposition 3 ("previously learned distant regions remain
//! substantially undisturbed", §20) is not an empirical hope here. It is
//! structural, and the only ways to break it are to MOVE a centre into a
//! distant region or to BIRTH a kernel that overlaps one. That is what
//! G17 (c) measures, bitwise, and what makes centre drift a headline
//! number rather than a footnote.
//!
//! Regions are the bookkeeping unit — surprise statistics, the kernel
//! budget, saturation. A kernel is OWNED by the region holding its
//! centre, and its shape is projected after every step so its cutoff box
//! reaches at most one region edge (`h`) on every axis. That one clamp
//! buys exactness: a query's covering kernels are owned by its own region
//! and its 26 neighbours and by nobody else, so a 27-region gather is not
//! an approximation of the sum over the model — it IS the sum over the
//! model, and G17 (d) checks it against the O(N) truth.
//!
//! Each region also carries `max_reach`, the largest cutoff box of the
//! kernels it owns: a query whose distance to a region's cube exceeds it
//! skips the region without touching a kernel. That is `Summary.covers`'s
//! idea in one float — conservative, so it may only ever be too large,
//! and a stale-but-larger bound is correct where a stale-but-smaller one
//! would silently drop a kernel from a sum.
//!
//! ## What is deliberately absent
//!
//! No World, no Brick, no Snapshot, no channel, no operator, no attention
//! plumbing. Nothing here is on the sim path and the sim's hash never
//! sees it — `rbf.zig`'s standing, for the same reason. Parallel learning
//! is absent too, and the campaign's §6 needs one ruling before it can
//! exist: **gradient descent is not order-free.** Sums of gradients
//! commute; sequential steps do not, and Adam's moments certainly do not.
//! So a parallel MARL computes gradients against the PUBLISHED parameters
//! and applies one step at commit — Jacobi, not Gauss-Seidel — which fits
//! "operators write deltas, never bricks" exactly and costs convergence
//! rate. That is a price, and it belongs in the design before anyone
//! discovers it as a bug.

const std = @import("std");
const rbf = @import("rbf.zig");
const rng = @import("rng.zig");
const fmath = @import("fmath.zig");
const thresholds = @import("thresholds.zig");

/// A kernel is nothing beyond this Mahalanobis distance squared. THE SAME
/// 32 as `rbf.CUTOFF`, rill's `CUTOFF` and the shader's
/// `LOAM_RBF_CUTOFF`; if one moves they all move in the same beat, and
/// `MARL_PIN` is the gate that notices.
pub const CUTOFF: f32 = 32;
/// The cutoff in Mahalanobis widths: √32. A kernel's support is the
/// ellipsoid |Lᵀ(q − μ)| ≤ this.
pub const CUTOFF_R: f32 = 5.656854249492381;

/// Parameters per kernel: the centre (3), the LOG of L's diagonal (3, so
/// a width stays positive), L's off-diagonal (3: l10, l20, l21) and the
/// one weight. `rbf.KERNEL_FLOATS` minus eight material channels.
pub const PARAMS: usize = 10;
const MU: usize = 0;
const LOGD: usize = 3;
const OFF: usize = 6;
const W: usize = 9;

/// A kernel's geometry: the centre and the lower-triangular factor of the
/// precision, row by row (l00, l10, l11, l20, l21, l22). Σ⁻¹ = L Lᵀ.
/// `rbf.Kernel`'s `mu` and `l`, term for term.
pub const Shape = struct { mu: [3]f32, l: [6]f32 };

/// v = Lᵀ(q − μ) and |v|². `rbf.mahal`'s twin.
pub const Mahal = struct { d: [3]f32, v: [3]f32, r2: f32 };

pub fn mahal(s: Shape, q: [3]f32) Mahal {
    const d = [3]f32{ q[0] - s.mu[0], q[1] - s.mu[1], q[2] - s.mu[2] };
    const l = s.l;
    const v = [3]f32{ l[0] * d[0] + l[1] * d[1] + l[3] * d[2], l[2] * d[1] + l[4] * d[2], l[5] * d[2] };
    return .{ .d = d, .v = v, .r2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] };
}

/// The kernel's value at q — zero, exactly, beyond the cutoff.
/// `rbf.gaussian`'s twin: same order, same `fmath.expf`, same bits.
pub fn gaussian(s: Shape, q: [3]f32) f32 {
    const m = mahal(s, q);
    if (m.r2 > CUTOFF) return 0;
    return fmath.expf(-0.5 * m.r2);
}

/// Half-extents of the kernel's cutoff BOX, per axis: the support
/// ellipsoid |Lᵀd|² ≤ CUTOFF has half-extent √(CUTOFF · Σ_aa) along axis
/// a, with Σ = (L Lᵀ)⁻¹ = MᵀM for M = L⁻¹. Closed form, because M of a
/// lower-triangular L is forward substitution and nothing more — and the
/// clamp that keeps a gather exact reads this on every step, so it may
/// not be an iteration.
pub fn halfExtents(s: Shape) [3]f32 {
    const l = s.l;
    // M = L⁻¹, lower triangular.
    const m00 = 1 / l[0];
    const m11 = 1 / l[2];
    const m22 = 1 / l[5];
    const m10 = -l[1] / (l[0] * l[2]);
    const m21 = -l[4] / (l[2] * l[5]);
    const m20 = (l[1] * l[4] - l[2] * l[3]) / (l[0] * l[2] * l[5]);
    // Σ_aa is the squared norm of M's column a.
    const s00 = m00 * m00 + m10 * m10 + m20 * m20;
    const s11 = m11 * m11 + m21 * m21;
    const s22 = m22 * m22;
    return .{ @sqrt(CUTOFF * s00), @sqrt(CUTOFF * s11), @sqrt(CUTOFF * s22) };
}

/// The largest half-extent — the ∞-norm reach a region's bound is kept in.
pub fn reachOf(s: Shape) f32 {
    const e = halfExtents(s);
    return @max(e[0], @max(e[1], e[2]));
}

// ── The truth ─────────────────────────────────────────────────────────

/// The target field (campaign §8): broad smooth structure, one sharp
/// localised feature, and a region of near-constant output, over the unit
/// cube. Deterministic and directly evaluable everywhere, so error can be
/// drawn as a picture rather than inferred from a loss curve.
///
/// The three parts are chosen so the campaign's questions have room to
/// separate: the SWELL is smooth at a scale of about a third of the
/// domain and costs many kernels of the clamped width; the SHELL is a
/// spherical surface a fortieth of the domain thick, which no isotropic
/// kernel of that width can afford and an ellipsoid thin across it and
/// wide along it covers cheaply — the anisotropy earning its place; and
/// the QUIET slab is identically zero, far enough beyond the swell's
/// window that no kernel born on structure can reach it (the window ends
/// at 0.70, a kernel reaches at most `h`, and the slab starts at 0.85).
/// What that slab is for is the capacity question: a learner that spends
/// nothing there is allocating by epistemic complexity and not by volume.
pub const Truth = struct {
    pub const SHELL_C = [3]f32{ 0.30, 0.62, 0.46 };
    pub const SHELL_R: f32 = 0.20;
    pub const SHELL_W: f32 = 0.025;
    pub const SHELL_A: f32 = 0.9;
    pub const SWELL_A: f32 = 0.35;
    pub const WINDOW_LO: f32 = 0.55;
    pub const WINDOW_HI: f32 = 0.70;
    /// x beyond this is the quiet slab: the truth is exactly zero there,
    /// AND no kernel born on structure can reach it. The second half is
    /// what the number is for and it is arithmetic, not taste: the window
    /// ends at 0.70 and a kernel reaches at most one region edge, so at
    /// the default 6³ grid nothing born on structure gets past 0.8667.
    /// It was 0.85 for the length of one gate run — 0.70 + 1/6 = 0.8667,
    /// which is NOT less than 0.85, so the derivation this slab exists to
    /// support was false while every measured number using it was right.
    /// The gate below is what caught it. A coarser grid weakens the claim
    /// again (4³ reaches 0.95), which is why that gate asserts it.
    pub const QUIET_X: f32 = 0.90;

    const TAU: f32 = 6.283185307179586;

    /// One at the origin end, zero past `WINDOW_HI`, a raised cosine
    /// between — so the swell dies smoothly and the quiet slab is not a
    /// second sharp feature.
    pub fn window(x: f32) f32 {
        if (x <= WINDOW_LO) return 1;
        if (x >= WINDOW_HI) return 0;
        const u = (x - WINDOW_LO) / (WINDOW_HI - WINDOW_LO);
        return 0.5 * (1 + fmath.cosf(std.math.pi * u));
    }

    pub fn swell(p: [3]f32) f32 {
        return SWELL_A *
            fmath.sinf(TAU * (0.9 * p[0] + 0.13)) *
            fmath.cosf(TAU * (0.7 * p[1] - 0.21)) *
            fmath.sinf(TAU * (0.6 * p[2] + 0.37));
    }

    pub fn shell(p: [3]f32) f32 {
        const d = [3]f32{ p[0] - SHELL_C[0], p[1] - SHELL_C[1], p[2] - SHELL_C[2] };
        const r = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
        const t = (r - SHELL_R) / SHELL_W;
        const t2 = t * t;
        // Past exp(−16) the ridge is a tenth of a millionth of its peak:
        // cut it, the way a kernel is cut, so "outside the shell" is a
        // value and not an asymptote.
        if (t2 > 16) return 0;
        return SHELL_A * fmath.expf(-t2);
    }

    /// Whether p is in the shell's band — within two widths of the ridge.
    pub fn inShell(p: [3]f32) bool {
        const d = [3]f32{ p[0] - SHELL_C[0], p[1] - SHELL_C[1], p[2] - SHELL_C[2] };
        const r = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
        return @abs(r - SHELL_R) < 2 * SHELL_W;
    }

    pub fn inQuiet(p: [3]f32) bool {
        return p[0] > QUIET_X;
    }
};

pub fn truth(p: [3]f32) f32 {
    return Truth.window(p[0]) * Truth.swell(p) + Truth.shell(p);
}

// ── The model ─────────────────────────────────────────────────────────

/// How a learning event spends itself on the kernels it touched.
///
/// `.nlms` — normalised least mean squares on the weights, and the
/// NATURAL gradient on the geometry, both driven by one attribution
///
///     a_i = e · g_i / Σ_j g_j²
///
/// which is the share of the residual kernel i is answerable for. It is
/// the campaign's own sentence made arithmetic: no surprise, no
/// deformation. The normalisation matters because about sixty kernels
/// overlap any point (`MARL0_MAX_TOUCHED`'s derivation) and sixty
/// unnormalised corrections each large enough to answer the whole
/// residual overshoot it sixtyfold.
///
/// `.adam` — the batch optimiser `rbf.fit` uses, kept as an INSTRUMENT
/// and as this file's sharpest finding rather than as a default. Adam
/// divides the gradient by its own running magnitude, which is what makes
/// it scale-free over a batch and what makes it wrong here: with one
/// exemplar per step the gradient is mostly noise, m̂/√v̂ is ±1 whatever
/// the residual, and every touched kernel takes a full `rate`-sized step
/// forever. Measured, 200 000 exemplars in: centres drifted 0.57 of the
/// domain on average and 1.53 at worst, 27 995 of 28 264 kernels left the
/// region they were born in, and the held-out RMS ROSE from 0.131 at five
/// hundred exemplars to 0.151 at two hundred thousand — a model with a
/// hundred times the capacity, predicting worse. The ledger has the run.
pub const Optimizer = enum { nlms, adam };

pub const Options = struct {
    seed: u64 = 7,
    /// Regions per axis over the unit cube. The region edge `h` sets the
    /// widest kernel the gather stays exact for: σ_max = h/√CUTOFF.
    regions: u32 = 6,
    /// Kernels a region may own (campaign §10: a small budget, and the
    /// saturation recorded rather than a refinement invented).
    budget: u32 = 64,
    /// Surprise below this does nothing at all — no gradient, no birth.
    threshold: f32 = 0.02,
    /// Birth when no kernel already reads above this at the exemplar.
    coverage: f32 = 0.35,
    /// A newborn's width, as a fraction of the widest the clamp allows.
    /// ONE, and the reason is the cutoff's geometry rather than taste: a
    /// kernel is useful out to about 1.45 Mahalanobis widths (where it
    /// reads `coverage`) and non-zero out to 5.66, so births stop only
    /// once kernels sit within 1.45σ of every exemplar. Halve σ and the
    /// count that needs is eight times larger — at the first defaults the
    /// model wanted twenty thousand kernels for a budget of ten, birthed
    /// on 98% of its learning events, and saturated long before it
    /// converged. Descent can still narrow a kernel (the shell needs it);
    /// the clamp is what stops it widening.
    birth_width: f32 = 1.0,
    optimizer: Optimizer = .nlms,
    /// NLMS on the weights: one step answers the residual exactly at
    /// η = 1, and 0 < η < 2 is the stability range LMS has always had.
    rate_w: f32 = 0.5,
    /// The geometry's share of the same attribution — centres and shapes
    /// move an order slower than weights, because a weight is linear in
    /// the model and a centre is not.
    rate_geom: f32 = 0.2,
    /// Adam's step, for `.adam` alone. NEGATIVE climbs — a gate's mutation.
    rate: f32 = 0.02,
    /// Adam steps per learning event. The campaign's "small fixed number".
    steps: u32 = 3,
    /// The furthest one step may move a centre, in region edges. The
    /// trust region: it is what makes the interference bound a proof
    /// rather than an observation, and it is deliberately loose — a third
    /// of a region is fifty times the drift a whole run produces, so it
    /// costs nothing at the defaults and still bounds the pathological
    /// case. `Stats.trust_clamped` says whether it ever bit.
    trust: f32 = 1.0 / 3.0,
    /// The recent-window the running error is averaged over.
    window: u32 = 4096,
};

pub const Kernel = struct {
    p: [PARAMS]f32,
    /// Adam's moments and this kernel's OWN step count: kernels are
    /// updated at irregular times, so the bias correction cannot share a
    /// clock.
    m1: [PARAMS]f32 = [_]f32{0} ** PARAMS,
    m2: [PARAMS]f32 = [_]f32{0} ** PARAMS,
    t: u32 = 0,
    /// The region that owns it — the one holding its centre, re-homed
    /// when a step moves it across a face.
    owner: u32,
    /// The centre at birth: drift is measured against this, because drift
    /// is the only thing that can break exact locality.
    mu0: [3]f32,
    /// Cached ∞-norm half-extent of the cutoff box.
    reach: f32,
    updates: u32 = 0,
    born_at: u64,

    pub fn shape(self: *const Kernel) Shape {
        return .{
            .mu = .{ self.p[MU], self.p[MU + 1], self.p[MU + 2] },
            .l = .{
                fmath.expf(self.p[LOGD]),
                self.p[OFF],
                fmath.expf(self.p[LOGD + 1]),
                self.p[OFF + 1],
                self.p[OFF + 2],
                fmath.expf(self.p[LOGD + 2]),
            },
        };
    }

    pub fn weight(self: *const Kernel) f32 {
        return self.p[W];
    }

    pub fn drift(self: *const Kernel) f32 {
        const d = [3]f32{ self.p[MU] - self.mu0[0], self.p[MU + 1] - self.mu0[1], self.p[MU + 2] - self.mu0[2] };
        return @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    }
};

/// A region: the bookkeeping unit, the budget's unit, and the unit a
/// query rejects wholesale. Not a brick, and not pretending to be one.
pub const Region = struct {
    own: std.ArrayListUnmanaged(u32) = .{},
    /// Conservative: at least the largest reach among the kernels owned.
    /// Only ever grown on a step (a bound that is too large is correct;
    /// one that is too small silently drops a kernel from a sum), and
    /// tightened only by `retighten`.
    max_reach: f32 = 0,
    /// Unresolved surprise (campaign §2: attention). Both forms kept —
    /// the sum is what §9 writes, the max is what Loam's R15 would.
    surprise_sum: f64 = 0,
    surprise_max: f32 = 0,
    seen: u32 = 0,
    events: u32 = 0,
    births: u32 = 0,
    saturated: u32 = 0,
};

/// What one observation did — the campaign's §11 locality, per event.
pub const Event = struct {
    residual: f32,
    surprise: f32,
    learned: bool,
    born: bool,
    saturated: bool,
    /// Kernels whose support contains the exemplar: the touched set, and
    /// exactly the set the prediction summed.
    touched: u32,
    /// Distinct owning regions among them — the learning cone's width.
    regions_touched: u32,
    /// Kernels a gaussian was computed for, touched or not: the COST,
    /// which is a different number from the locality.
    evaluated: u32,
    /// Regions the query opened; and those `max_reach` rejected outright.
    visited: u32,
    pruned: u32,
};

pub const Stats = struct {
    exemplars: u64 = 0,
    events: u64 = 0,
    births: u64 = 0,
    saturations: u64 = 0,
    touched: u64 = 0,
    regions_touched: u64 = 0,
    evaluated: u64 = 0,
    visited: u64 = 0,
    pruned: u64 = 0,
    /// Wall clock, nanoseconds. Never read by the model — reported only.
    predict_ns: u64 = 0,
    learn_ns: u64 = 0,
    predictions: u64 = 0,
    /// Times a clamp bit: the shape projected back inside the reach, a
    /// width held off its floor, a centre held inside the cube.
    reach_clamped: u64 = 0,
    width_clamped: u64 = 0,
    centre_clamped: u64 = 0,
    rehomed: u64 = 0,
    trust_clamped: u64 = 0,
};

pub const Model = struct {
    gpa: std.mem.Allocator,
    opts: Options,
    /// Region edge, and the widest a kernel's cutoff box may reach.
    h: f32,
    sigma_max: f32,
    sigma_min: f32,
    kernels: std.ArrayListUnmanaged(Kernel) = .{},
    regions: []Region,
    stats: Stats = .{},
    stream: rng.Stream,
    /// Scratch for a gather: reused, so an observation allocates nothing.
    hit: std.ArrayListUnmanaged(u32) = .{},
    /// The recent window of |residual| (campaign §11), a ring.
    recent: []f32,
    recent_n: u64 = 0,
    /// Stamps for counting the distinct regions one event reached, in one
    /// pass over the touched set rather than a pass per member: sixty
    /// kernels is the predicted touch and sixty squared per event is not
    /// a measurement, it is the measurement's cost.
    visit_gen: []u32,
    gen: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, opts: Options) !Model {
        const n = opts.regions * opts.regions * opts.regions;
        const regions = try gpa.alloc(Region, n);
        errdefer gpa.free(regions);
        for (regions) |*r| r.* = .{};
        const recent = try gpa.alloc(f32, opts.window);
        errdefer gpa.free(recent);
        @memset(recent, 0);
        const gens = try gpa.alloc(u32, n);
        errdefer gpa.free(gens);
        @memset(gens, 0);
        const h = 1 / @as(f32, @floatFromInt(opts.regions));
        return .{
            .gpa = gpa,
            .opts = opts,
            .h = h,
            .sigma_max = h / CUTOFF_R,
            // A width may thin to a sixty-fourth of a region — the shell
            // is a fortieth of the domain thick and a kernel that cannot
            // get thinner than the feature cannot represent it.
            .sigma_min = h / 64,
            .regions = regions,
            .stream = rng.Stream.region(opts.seed, 0x4D41_524C, 0), // "MARL"
            .recent = recent,
            .visit_gen = gens,
        };
    }

    pub fn deinit(self: *Model) void {
        for (self.regions) |*r| r.own.deinit(self.gpa);
        self.gpa.free(self.regions);
        self.kernels.deinit(self.gpa);
        self.hit.deinit(self.gpa);
        self.gpa.free(self.recent);
        self.gpa.free(self.visit_gen);
    }

    // ── geometry ──────────────────────────────────────────────────────

    fn cellOf(self: *const Model, x: f32) u32 {
        const r = self.opts.regions;
        const c = @floor(x / self.h);
        if (c < 0) return 0;
        const ci: u32 = @intFromFloat(c);
        return @min(r - 1, ci);
    }

    pub fn regionOf(self: *const Model, p: [3]f32) u32 {
        const r = self.opts.regions;
        return (self.cellOf(p[2]) * r + self.cellOf(p[1])) * r + self.cellOf(p[0]);
    }

    fn regionCoords(self: *const Model, idx: u32) [3]u32 {
        const r = self.opts.regions;
        return .{ idx % r, (idx / r) % r, idx / (r * r) };
    }

    /// ∞-distance from q to a region's closed cube — what `max_reach` is
    /// compared against.
    fn distToRegion(self: *const Model, idx: u32, q: [3]f32) f32 {
        const c = self.regionCoords(idx);
        var d: f32 = 0;
        inline for (0..3) |a| {
            const lo = @as(f32, @floatFromInt(c[a])) * self.h;
            const hi = lo + self.h;
            d = @max(d, @max(lo - q[a], q[a] - hi));
        }
        return @max(d, 0);
    }

    // ── the gather: exact, and the only place a prediction comes from ──

    /// Every kernel whose support CONTAINS q, appended to `self.hit`. The
    /// clamp guarantees a kernel's box reaches at most one region edge,
    /// so its own region and the 26 neighbours are the whole of it — this
    /// is the sum over the model, not a truncation of it (G17 d).
    fn gather(self: *Model, q: [3]f32, ev: ?*Event) !void {
        self.hit.clearRetainingCapacity();
        const r = self.opts.regions;
        const c = [3]u32{ self.cellOf(q[0]), self.cellOf(q[1]), self.cellOf(q[2]) };
        var visited: u32 = 0;
        var pruned: u32 = 0;
        var evaluated: u32 = 0;
        var dz: i32 = -1;
        while (dz <= 1) : (dz += 1) {
            const z = @as(i32, @intCast(c[2])) + dz;
            if (z < 0 or z >= r) continue;
            var dy: i32 = -1;
            while (dy <= 1) : (dy += 1) {
                const y = @as(i32, @intCast(c[1])) + dy;
                if (y < 0 or y >= r) continue;
                var dx: i32 = -1;
                while (dx <= 1) : (dx += 1) {
                    const x = @as(i32, @intCast(c[0])) + dx;
                    if (x < 0 or x >= r) continue;
                    const idx: u32 = (@as(u32, @intCast(z)) * r + @as(u32, @intCast(y))) * r + @as(u32, @intCast(x));
                    const reg = &self.regions[idx];
                    if (reg.own.items.len == 0) continue;
                    // The region's own conservative bound, `Summary.covers`
                    // in one float: nothing it owns can reach q.
                    if (self.distToRegion(idx, q) > reg.max_reach) {
                        pruned += 1;
                        continue;
                    }
                    visited += 1;
                    for (reg.own.items) |ki| {
                        evaluated += 1;
                        if (gaussian(self.kernels.items[ki].shape(), q) > 0) {
                            try self.hit.append(self.gpa, ki);
                        }
                    }
                }
            }
        }
        if (ev) |e| {
            e.visited = visited;
            e.pruned = pruned;
            e.evaluated = evaluated;
        }
    }

    /// `gather` for a gate: leaves the touched set in `hit` so a witness
    /// can compare it against a brute-force pass over the whole model.
    pub fn gatherForTest(self: *Model, q: [3]f32) !void {
        try self.gather(q, null);
    }

    /// The prediction at q. Exact: the cutoff makes every kernel the
    /// gather did not reach contribute zero, not a small number.
    pub fn predict(self: *Model, q: [3]f32) !f32 {
        var t = std.time.Timer.start() catch null;
        try self.gather(q, null);
        var y: f32 = 0;
        for (self.hit.items) |ki| {
            const k = &self.kernels.items[ki];
            y += k.p[W] * gaussian(k.shape(), q);
        }
        if (t) |*tt| self.stats.predict_ns += tt.read();
        self.stats.predictions += 1;
        return y;
    }

    /// Every kernel in the model summed — the reference the 27-region
    /// gather is checked against, and nothing else.
    ///
    /// It walks EVERY region in linear index order, which is the order the
    /// gather visits its twenty-seven in, so the two sums add the same
    /// terms in the same order and the comparison is about the gather
    /// rather than about float addition. The regions the gather skips
    /// contribute w·0 here, and adding a zero is exact — which is the
    /// whole claim: the restriction to twenty-seven regions is LOSSLESS,
    /// not merely close. Summed in kernel-index order instead, the two
    /// answers differ in the last two places, which is a true statement
    /// about associativity and a useless one about locality.
    pub fn predictAll(self: *const Model, q: [3]f32) f32 {
        var y: f32 = 0;
        for (self.regions) |*reg| {
            for (reg.own.items) |ki| {
                const k = &self.kernels.items[ki];
                y += k.p[W] * gaussian(k.shape(), q);
            }
        }
        return y;
    }

    // ── the clamp ─────────────────────────────────────────────────────

    /// Project a kernel's parameters back inside what keeps the gather
    /// exact: the centre in the cube, no width below the floor, and the
    /// cutoff box reaching at most one region edge. The reach projection
    /// scales L, which shrinks every half-extent by the same factor and
    /// so keeps the SHAPE — an ellipsoid stays as anisotropic as the
    /// descent made it, it only stops growing past the gather.
    fn clamp(self: *Model, k: *Kernel) void {
        // BOTH sides of the log-diagonal, and the low side is not
        // decoration: it was paid for by a `--width 0.4` run that panicked
        // at 10 000 exemplars casting a non-finite centre to a region
        // index. Nothing bounded a kernel from below, so descent widened
        // one until `expf` underflowed L's diagonal to zero, `halfExtents`
        // divided by it, the reach came back infinite, and the reach
        // projection added log(∞) to the log-width. σ ≤ h is an OUTER
        // bound — the reach projection below is what actually governs the
        // width, and it can only ever ask for something narrower — so this
        // floor changes no converged model and makes the arithmetic
        // incapable of leaving the reals.
        const lo_log = -@log(self.h); // σ ≤ h
        const hi_log = -@log(self.sigma_min); // σ ≥ σ_min
        var bit_width = false;
        inline for (0..3) |a| {
            const v = k.p[LOGD + a];
            if (!(v >= lo_log and v <= hi_log)) {
                k.p[LOGD + a] = if (v < lo_log) lo_log else hi_log;
                bit_width = true;
            }
        }
        inline for (0..3) |a| {
            const v = k.p[MU + a];
            // Written to catch a NaN, which no ordered comparison does:
            // a centre that is not a number is a bug upstream, and it must
            // fail on the kernel that produced it rather than five
            // thousand exemplars later inside a region lookup.
            if (!(v >= 0 and v <= 1)) {
                std.debug.assert(std.math.isFinite(v));
                k.p[MU + a] = @min(1, @max(0, v));
                if (a == 0) self.stats.centre_clamped += 1;
            }
        }
        const off_cap = 1 / self.sigma_min;
        inline for (0..3) |a| k.p[OFF + a] = @min(off_cap, @max(-off_cap, k.p[OFF + a]));
        if (bit_width) self.stats.width_clamped += 1;

        var s = k.shape();
        var reach = reachOf(s);
        if (reach > self.h) {
            self.stats.reach_clamped += 1;
            // L ← fL shrinks every half-extent by f. Once is exact in
            // exact arithmetic and lands within an ulp in this one, so the
            // loop almost always runs a single pass — but it LOOPS rather
            // than storing min(reach, h), because the exactness the whole
            // gather rests on is a property of the geometry and not of
            // what a field was set to afterwards. A kernel one ulp over
            // `h` reaches into the ring the gather never visits, and what
            // it would contribute there is w·exp(−16): far too small to
            // be noticed and far too large to be called zero. The first
            // version stored min(reach, h) instead and the invariant was
            // false on 0.6% of clamps — invisible, because the field said
            // otherwise.
            var guard: u8 = 0;
            while (reach > self.h and guard < 16) : (guard += 1) {
                // At least a thousandth, and that floor is the whole
                // reason this terminates. A kernel one ulp over `h` gives
                // f = 1 + 2⁻²³, whose log is SMALLER THAN THE ULP OF THE
                // LOG-WIDTH ITSELF (~3.5, ulp 2.4e-7): the increment
                // rounds away, the shape does not move, and the loop
                // spins forever on a kernel that is already correct to
                // within a float. Costing the boundary case a tenth of a
                // percent of its width buys an invariant that holds
                // exactly, which is what the gather's exactness rests on.
                const f = @max(1.001, reach / self.h);
                const lf = @log(f);
                inline for (0..3) |a| k.p[LOGD + a] += lf;
                inline for (0..3) |a| k.p[OFF + a] *= f;
                s = k.shape();
                reach = reachOf(s);
            }
            std.debug.assert(reach <= self.h);
        }
        k.reach = reach;
    }

    /// Move a centre by `d`, held to the trust region: no step may
    /// displace a kernel more than `trust` region edges, in ∞-norm. This
    /// is the whole of what makes the interference bound provable — 2h
    /// from the clamp for where a touched kernel can already be, plus
    /// steps · trust · h for where a step can put it — and it holds
    /// whichever optimiser is mounted.
    fn moveCentre(self: *Model, k: *Kernel, d: [3]f32) void {
        const cap = self.opts.trust * self.h;
        const mag = @max(@abs(d[0]), @max(@abs(d[1]), @abs(d[2])));
        if (mag > cap) {
            const f = cap / mag;
            inline for (0..3) |c| k.p[MU + c] += d[c] * f;
            self.stats.trust_clamped += 1;
        } else {
            inline for (0..3) |c| k.p[MU + c] += d[c];
        }
    }

    /// Put a kernel in the region its centre now lies in, and keep that
    /// region's bound conservative.
    fn rehome(self: *Model, ki: u32) !void {
        const k = &self.kernels.items[ki];
        const want = self.regionOf(.{ k.p[MU], k.p[MU + 1], k.p[MU + 2] });
        if (want != k.owner) {
            const old = &self.regions[k.owner];
            for (old.own.items, 0..) |v, i| {
                if (v == ki) {
                    _ = old.own.orderedRemove(i);
                    break;
                }
            }
            try self.regions[want].own.append(self.gpa, ki);
            k.owner = want;
            self.stats.rehomed += 1;
        }
        const reg = &self.regions[k.owner];
        if (k.reach > reg.max_reach) reg.max_reach = k.reach;
    }

    /// Recompute every region's bound from the kernels it owns. Only ever
    /// LOWERS one, so it changes no answer — it makes the prune sharper,
    /// and the gate that the bound is conservative is what says so.
    pub fn retighten(self: *Model) void {
        for (self.regions) |*reg| {
            var m: f32 = 0;
            for (reg.own.items) |ki| m = @max(m, self.kernels.items[ki].reach);
            reg.max_reach = m;
        }
    }

    // ── one exemplar ──────────────────────────────────────────────────

    /// The campaign's §9, and deliberately nothing more: locate, predict,
    /// measure surprise, and either do nothing or take a few gradient
    /// steps on the kernels that were responsible — birthing one first if
    /// none of them covers the exemplar well enough.
    pub fn observe(self: *Model, x: [3]f32, y: f32) !Event {
        var ev = Event{ .residual = 0, .surprise = 0, .learned = false, .born = false, .saturated = false, .touched = 0, .regions_touched = 0, .evaluated = 0, .visited = 0, .pruned = 0 };
        var pt = std.time.Timer.start() catch null;

        try self.gather(x, &ev);
        var yhat: f32 = 0;
        var cover: f32 = 0;
        for (self.hit.items) |ki| {
            const k = &self.kernels.items[ki];
            const g = gaussian(k.shape(), x);
            yhat += k.p[W] * g;
            cover = @max(cover, g);
        }
        if (pt) |*tt| self.stats.predict_ns += tt.read();
        self.stats.predictions += 1;
        ev.touched = @intCast(self.hit.items.len);
        ev.residual = y - yhat;
        ev.surprise = @abs(ev.residual);

        const home = self.regionOf(x);
        const reg = &self.regions[home];
        reg.seen += 1;
        reg.surprise_sum += ev.surprise;
        reg.surprise_max = @max(reg.surprise_max, ev.surprise);

        self.recent[@intCast(self.recent_n % self.opts.window)] = ev.surprise;
        self.recent_n += 1;
        self.stats.exemplars += 1;
        self.stats.evaluated += ev.evaluated;
        self.stats.visited += ev.visited;
        self.stats.pruned += ev.pruned;

        if (ev.surprise <= self.opts.threshold) return ev;

        var lt = std.time.Timer.start() catch null;
        ev.learned = true;
        reg.events += 1;
        self.stats.events += 1;

        // Birth: no kernel covers the exemplar usefully (campaign §10).
        // The weight is the residual, so the newborn alone answers this
        // exemplar exactly; the descent then has to keep it honest at
        // every other exemplar it reaches.
        if (cover < self.opts.coverage) {
            if (reg.own.items.len >= self.opts.budget) {
                ev.saturated = true;
                reg.saturated += 1;
                self.stats.saturations += 1;
            } else {
                const sigma = self.opts.birth_width * self.sigma_max;
                const inv = 1 / sigma;
                const li = @log(inv);
                const ki: u32 = @intCast(self.kernels.items.len);
                try self.kernels.append(self.gpa, .{
                    .p = .{ x[0], x[1], x[2], li, li, li, 0, 0, 0, ev.residual },
                    .owner = home,
                    .mu0 = x,
                    .reach = CUTOFF_R * sigma,
                    .born_at = self.stats.exemplars,
                });
                // Nothing enters the model unprojected: `CUTOFF_R · σ` is
                // the reach only to within a float, and a kernel one ulp
                // over `h` is one the gather can miss.
                self.clamp(&self.kernels.items[ki]);
                try reg.own.append(self.gpa, ki);
                const kr = self.kernels.items[ki].reach;
                if (kr > reg.max_reach) reg.max_reach = kr;
                try self.hit.append(self.gpa, ki);
                ev.born = true;
                ev.touched += 1;
                reg.births += 1;
                self.stats.births += 1;
            }
        }

        // The steps. Only the kernels in `hit` move, and `hit` is exactly
        // the kernels whose support contains x.
        var grad: [PARAMS]f32 = undefined;
        var s: u32 = 0;
        while (s < self.opts.steps) : (s += 1) {
            var pred: f32 = 0;
            var gg: f32 = 0;
            for (self.hit.items) |ki| {
                const k = &self.kernels.items[ki];
                const g = gaussian(k.shape(), x);
                pred += k.p[W] * g;
                gg += g * g;
            }
            const e = pred - y;
            switch (self.opts.optimizer) {
                .adam => for (self.hit.items) |ki| {
                    const k = &self.kernels.items[ki];
                    if (!gradOne(k, x, e, &grad)) continue;
                    const mu0 = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    adam(k, &grad, self.opts.rate);
                    // Through the same trust region, so the interference
                    // bound is a property of the model and not of which
                    // optimiser happens to be mounted.
                    const d = [3]f32{ k.p[MU] - mu0[0], k.p[MU + 1] - mu0[1], k.p[MU + 2] - mu0[2] };
                    inline for (0..3) |c| k.p[MU + c] = mu0[c];
                    self.moveCentre(k, d);
                    self.clamp(k);
                    k.updates += 1;
                },
                .nlms => {
                    const inv = 1 / (gg + 1e-6);
                    for (self.hit.items) |ki| {
                        const k = &self.kernels.items[ki];
                        const sh = k.shape();
                        const m = mahal(sh, x);
                        if (m.r2 > CUTOFF) continue;
                        const g = fmath.expf(-0.5 * m.r2);
                        // This kernel's share of the residual.
                        const a = e * g * inv;
                        const wa = k.p[W] * a * self.opts.rate_geom;
                        k.p[W] -= self.opts.rate_w * a;
                        // The centre, in the kernel's OWN metric: the
                        // natural gradient Σ·∂g/∂μ collapses to g·d,
                        // because Σ(Lv) = L⁻ᵀL⁻¹Lv = L⁻ᵀv = d. So a
                        // kernel that under-reads at x simply moves
                        // toward x, by its share and no more — no matrix,
                        // and no units to get wrong.
                        self.moveCentre(k, .{ -wa * m.d[0], -wa * m.d[1], -wa * m.d[2] });
                        // The shape, each entry scaled into its own units:
                        // the diagonal through its log, the off-diagonal
                        // by l_ii·l_jj, so every group's step is a
                        // RELATIVE change and one rate governs them all.
                        const l = sh.l;
                        k.p[LOGD] += wa * m.v[0] * m.d[0] * l[0];
                        k.p[LOGD + 1] += wa * m.v[1] * m.d[1] * l[2];
                        k.p[LOGD + 2] += wa * m.v[2] * m.d[2] * l[5];
                        k.p[OFF] += wa * m.v[0] * m.d[1] * l[0] * l[2];
                        k.p[OFF + 1] += wa * m.v[0] * m.d[2] * l[0] * l[5];
                        k.p[OFF + 2] += wa * m.v[1] * m.d[2] * l[2] * l[5];
                        self.clamp(k);
                        k.updates += 1;
                    }
                },
            }
        }
        for (self.hit.items) |ki| try self.rehome(ki);

        self.gen += 1;
        var seen_reg: u32 = 0;
        for (self.hit.items) |ki| {
            const o = self.kernels.items[ki].owner;
            if (self.visit_gen[o] != self.gen) {
                self.visit_gen[o] = self.gen;
                seen_reg += 1;
            }
        }
        ev.regions_touched = seen_reg;
        self.stats.touched += ev.touched;
        self.stats.regions_touched += ev.regions_touched;
        if (lt) |*tt| self.stats.learn_ns += tt.read();
        return ev;
    }

    /// Draw an exemplar from the domain and observe it. Uniform, from the
    /// counter-based stream — no sequential draw anywhere, so the model
    /// is a function of (seed, count) and of nothing about the order work
    /// happened to be done in.
    pub fn observeOne(self: *Model) !Event {
        const x = [3]f32{ self.stream.unit(), self.stream.unit(), self.stream.unit() };
        return self.observe(x, truth(x));
    }

    pub fn stream_n(self: *Model, n: u64) !void {
        var i: u64 = 0;
        while (i < n) : (i += 1) _ = try self.observeOne();
    }

    // ── measurement ───────────────────────────────────────────────────

    /// Root mean square error over a held-out set — points drawn from
    /// their own stream and never learned from.
    pub fn rms(self: *Model, pts: []const [3]f32, targets: []const f32, max_abs: ?*f32) !f32 {
        var acc: f64 = 0;
        var mx: f32 = 0;
        for (pts, targets) |p, t| {
            const e = (try self.predict(p)) - t;
            acc += @as(f64, e) * @as(f64, e);
            mx = @max(mx, @abs(e));
        }
        if (max_abs) |m| m.* = mx;
        return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pts.len))));
    }

    pub fn recentError(self: *const Model) f32 {
        const n: usize = @intCast(@min(self.recent_n, self.opts.window));
        if (n == 0) return 0;
        var acc: f64 = 0;
        for (self.recent[0..n]) |v| acc += v;
        return @floatCast(acc / @as(f64, @floatFromInt(n)));
    }

    pub fn occupiedRegions(self: *const Model) u32 {
        var n: u32 = 0;
        for (self.regions) |*r| {
            if (r.own.items.len > 0) n += 1;
        }
        return n;
    }

    pub fn saturatedRegions(self: *const Model) u32 {
        var n: u32 = 0;
        for (self.regions) |*r| {
            if (r.own.items.len >= self.opts.budget) n += 1;
        }
        return n;
    }

    pub const Drift = struct { mean: f32, max: f32, out_of_region: u32 };

    pub fn driftOf(self: *const Model) Drift {
        if (self.kernels.items.len == 0) return .{ .mean = 0, .max = 0, .out_of_region = 0 };
        var acc: f64 = 0;
        var mx: f32 = 0;
        var out: u32 = 0;
        for (self.kernels.items) |*k| {
            const d = k.drift();
            acc += d;
            mx = @max(mx, d);
            if (self.regionOf(k.mu0) != k.owner) out += 1;
        }
        return .{ .mean = @floatCast(acc / @as(f64, @floatFromInt(self.kernels.items.len))), .max = mx, .out_of_region = out };
    }

    /// Kernel CENTRES per unit volume in a predicate's region — the
    /// campaign's capacity-allocation question, counted where the
    /// question is asked rather than over the whole cube.
    pub fn densityIn(self: *const Model, comptime pred: fn ([3]f32) bool, volume: f32) f32 {
        var n: u32 = 0;
        for (self.kernels.items) |*k| {
            if (pred(.{ k.p[MU], k.p[MU + 1], k.p[MU + 2] })) n += 1;
        }
        return @as(f32, @floatFromInt(n)) / volume;
    }

    pub fn countIn(self: *const Model, comptime pred: fn ([3]f32) bool) u32 {
        var n: u32 = 0;
        for (self.kernels.items) |*k| {
            if (pred(.{ k.p[MU], k.p[MU + 1], k.p[MU + 2] })) n += 1;
        }
        return n;
    }
};

/// The gradient of (ŷ − y)² for ONE kernel at one exemplar, into `grad`.
/// `rbf.lossAndGrad`'s inner loop with one channel: the same derivatives
/// through the same parameterisation, so a bug here is a bug there and
/// the finite-difference gate catches both shapes of it. False when the
/// kernel is outside the cutoff and has no gradient at all.
///
///     ∂g/∂μ   = g·(L v)
///     ∂g/∂L_ij = −g·v_j·d_i     (the diagonal through its log, ×L_ii)
pub fn gradOne(k: *const Kernel, q: [3]f32, e: f32, grad: *[PARAMS]f32) bool {
    const s = k.shape();
    const m = mahal(s, q);
    if (m.r2 > CUTOFF) return false;
    const g = fmath.expf(-0.5 * m.r2);
    if (g < 1e-7) return false;
    @memset(grad, 0);
    grad[W] = 2 * e * g;
    const ew = e * k.p[W];
    const l = s.l;
    const lv = [3]f32{
        l[0] * m.v[0],
        l[1] * m.v[0] + l[2] * m.v[1],
        l[3] * m.v[0] + l[4] * m.v[1] + l[5] * m.v[2],
    };
    inline for (0..3) |a| grad[MU + a] = 2 * ew * g * lv[a];
    grad[LOGD] = -2 * ew * g * m.v[0] * m.d[0] * l[0];
    grad[LOGD + 1] = -2 * ew * g * m.v[1] * m.d[1] * l[2];
    grad[LOGD + 2] = -2 * ew * g * m.v[2] * m.d[2] * l[5];
    grad[OFF] = -2 * ew * g * m.v[0] * m.d[1]; // l10
    grad[OFF + 1] = -2 * ew * g * m.v[0] * m.d[2]; // l20
    grad[OFF + 2] = -2 * ew * g * m.v[1] * m.d[2]; // l21
    return true;
}

const B1: f32 = 0.9;
const B2: f32 = 0.999;

/// One Adam step on one kernel, against its own step count.
pub fn adam(k: *Kernel, grad: *const [PARAMS]f32, rate: f32) void {
    k.t += 1;
    const t: f32 = @floatFromInt(k.t);
    const c1 = 1 - std.math.pow(f32, B1, t);
    const c2 = 1 - std.math.pow(f32, B2, t);
    inline for (0..PARAMS) |i| {
        k.m1[i] = B1 * k.m1[i] + (1 - B1) * grad[i];
        k.m2[i] = B2 * k.m2[i] + (1 - B2) * grad[i] * grad[i];
        k.p[i] -= rate * (k.m1[i] / c1) / (@sqrt(k.m2[i] / c2) + 1e-8);
    }
}

/// A held-out probe set: points from their own stream, never observed.
pub fn probes(gpa: std.mem.Allocator, seed: u64, n: usize) !struct { p: [][3]f32, y: []f32 } {
    var s = rng.Stream.region(seed, 0x5052_4F42, 0); // "PROB"
    const p = try gpa.alloc([3]f32, n);
    errdefer gpa.free(p);
    const y = try gpa.alloc(f32, n);
    errdefer gpa.free(y);
    for (p, y) |*pt, *ty| {
        pt.* = .{ s.unit(), s.unit(), s.unit() };
        ty.* = truth(pt.*);
    }
    return .{ .p = p, .y = y };
}

// ── Gates ─────────────────────────────────────────────────────────────
//
// Every threshold these read is in `thresholds.zig`, was written before
// the first exemplar streamed, and comes out of `tools/marl_predict.py`.
// Every gate names the mutation it was paid for.

const builtin = @import("builtin");
const testing = std.testing;

test "G17 (a) the kernel is rbf's: marl and the material set read the same bits at the same point" {
    // The pin is between two copies IN THIS BINARY, so it is a direct
    // comparison and not a frozen table — the frozen table is `rbf.zig`'s
    // job, because rill and the shader are not linked here and cannot be
    // asked. What this gate stops is the thing a learning experiment is
    // most likely to do: quietly change the kernel, the cutoff or the
    // packing of L to make its own numbers nicer, and take three
    // renderers with it. Byte equality in f32, not an epsilon.
    //
    // MUTATION: `CUTOFF` here set to anything but 32 — the two disagree
    // at the first query past the other's radius. Verified by hand.
    const gpa = testing.allocator;
    var one = [_]rbf.Kernel{undefined};
    var set = rbf.Set{ .extent = 1, .columns = 0, .kernels = one[0..], .hash = [_]u8{0} ** 32 };
    _ = &set;

    var st = rng.Stream.region(31337, 0xA11CE, 0);
    var checked: usize = 0;
    var i: usize = 0;
    while (i < 400) : (i += 1) {
        // A shape the descent could plausibly reach: positive diagonal,
        // off-diagonal of either sign.
        const l = [6]f32{
            fmath.expf(st.gauss() * 0.5 + 2.5), st.gauss() * 3,
            fmath.expf(st.gauss() * 0.5 + 2.5), st.gauss() * 3,
            st.gauss() * 3,                     fmath.expf(st.gauss() * 0.5 + 2.5),
        };
        const mu = [3]f32{ st.unit(), st.unit(), st.unit() };
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        one[0] = .{ .mu = mu, .l = l, .w = [_]f32{0} ** rbf.CHANNELS };
        one[0].w[0] = 1; // channel 0's weight is one, so eval returns g
        set.kernels = one[0..];
        const theirs = set.eval(q)[0];
        const ours = gaussian(.{ .mu = mu, .l = l }, q);
        try testing.expectEqual(@as(u32, @bitCast(theirs)), @as(u32, @bitCast(ours)));
        if (ours > 0) checked += 1;
    }
    // Not vacuous: the comparison has to have looked at live kernels and
    // not only at the zero the cutoff returns for everything.
    try testing.expect(checked > 100);
    try testing.expectEqual(rbf.CUTOFF, CUTOFF);
    _ = gpa;
}

test "G17 (b) the learning gradient is the finite difference's, for a centre, a log-diagonal, an off-diagonal and a weight" {
    // The same gate `rbf.zig` has, for the same reason: a wrong
    // derivative is a fit's own bug and nothing downstream reports it —
    // the model simply learns worse and every number in the run looks
    // plausible. The NLMS step and the Adam step are both built from
    // these terms, so one witness covers both.
    //
    // The loss is summed over sixteen points IN f64, which is rbf's gate's
    // shape and not decoration: differenced as a single f32 expression the
    // same check fails at the second digit on cancellation alone, and the
    // gradient it was accusing is correct.
    //
    // MUTATION: any single term dropped from `gradOne` — the centre's
    // `lv`, a log-diagonal's `l_ii` factor, an off-diagonal's `d_i` —
    // moves that parameter's finite difference off the analytic value by
    // far more than the tolerance. Verified by hand, term by term.
    var st = rng.Stream.region(4242, 0xF1D0, 0);
    var k = Kernel{
        .p = .{ 0.5, 0.5, 0.5, 2.4, 2.6, 2.5, 0.8, -0.5, 0.3, 0.6 },
        .owner = 0,
        .mu0 = .{ 0, 0, 0 },
        .reach = 0,
        .born_at = 0,
    };
    var pts: [16][3]f32 = undefined;
    var ys: [16]f32 = undefined;
    for (&pts, &ys) |*p, *y| {
        // Inside the kernel's support, or there is nothing to differentiate.
        p.* = .{ 0.5 + st.gauss() * 0.05, 0.5 + st.gauss() * 0.05, 0.5 + st.gauss() * 0.05 };
        y.* = st.unit() - 0.5;
    }

    const S = struct {
        fn loss(kk: *const Kernel, ps: []const [3]f32, ts: []const f32) f64 {
            var acc: f64 = 0;
            for (ps, ts) |p, t| {
                const e = kk.p[W] * gaussian(kk.shape(), p) - t;
                acc += @as(f64, e) * @as(f64, e);
            }
            return acc;
        }
        fn grads(kk: *const Kernel, ps: []const [3]f32, ts: []const f32) [PARAMS]f32 {
            var sum: [PARAMS]f32 = [_]f32{0} ** PARAMS;
            var g: [PARAMS]f32 = undefined;
            for (ps, ts) |p, t| {
                const e = kk.p[W] * gaussian(kk.shape(), p) - t;
                if (!gradOne(kk, p, e, &g)) continue;
                inline for (0..PARAMS) |i| sum[i] += g[i];
            }
            return sum;
        }
    };

    const analytic = S.grads(&k, &pts, &ys);
    var checked: usize = 0;
    var worst: f64 = 0;
    // One of each kind: the three centre coordinates, the three
    // log-diagonals, the three off-diagonals, the weight.
    for (0..PARAMS) |j| {
        const step: f32 = 1e-3;
        const x0 = k.p[j];
        k.p[j] = x0 + step;
        const lp = S.loss(&k, &pts, &ys);
        k.p[j] = x0 - step;
        const lm = S.loss(&k, &pts, &ys);
        k.p[j] = x0;
        const fd: f32 = @floatCast((lp - lm) / (2 * step));
        try testing.expectApproxEqAbs(fd, analytic[j], 1e-3 * @max(1, @abs(fd)));
        worst = @max(worst, @abs(fd - analytic[j]));
        if (@abs(fd) > 1e-3) checked += 1;
    }
    // Not vacuous: most parameters had a gradient worth differencing.
    try testing.expect(checked >= 7);
    std.debug.print("\n  G17 (b): {d} of {d} parameters carried a live gradient, worst absolute error {d:.6} ({s})\n", .{ checked, PARAMS, worst, @tagName(builtin.mode) });
}

test "G17 (c) the 27-region gather IS the sum over the model, bit for bit, and it is the set of kernels whose support contains the query" {
    // The clamp's whole purpose. A kernel's cutoff box reaches at most one
    // region edge, so a query's own region and its 26 neighbours hold every
    // kernel that can reach it — this is not an approximation of the sum,
    // and if it ever becomes one the model is quietly answering a
    // different question than the O(N) reference does.
    //
    // MUTATION: the reach projection removed from `clamp` (kernels grow
    // past `h`) — the gather drops kernels the O(N) sum keeps, and the
    // first disagreement is at the fourth decimal, which is exactly the
    // size of error nobody would attribute to a data structure. Verified
    // by hand: 61 of 4000 probes disagreed after 20 000 exemplars.
    const gpa = testing.allocator;
    var m = try Model.init(gpa, .{ .regions = 6, .budget = 64 });
    defer m.deinit();
    try m.stream_n(20_000);
    try testing.expect(m.kernels.items.len > 500);

    var st = rng.Stream.region(9, 0x9EA7, 0);
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const gathered = try m.predict(q);
        const all = m.predictAll(q);
        try testing.expectEqual(@as(u32, @bitCast(all)), @as(u32, @bitCast(gathered)));

        // And the touched set is exactly {i : support of k_i contains q}.
        try m.gatherForTest(q);
        var brute: usize = 0;
        for (m.kernels.items) |*k| {
            if (gaussian(k.shape(), q) > 0) brute += 1;
        }
        try testing.expectEqual(brute, m.hit.items.len);
    }
    // Every kernel in the model is inside its own clamp — the invariant
    // the exactness rests on, checked directly rather than inferred.
    for (m.kernels.items) |*k| {
        try testing.expect(reachOf(k.shape()) <= m.h * 1.000001);
        try testing.expectEqual(k.owner, m.regionOf(.{ k.p[0], k.p[1], k.p[2] }));
    }
}

test "G17 (d) a learning event changes NOTHING beyond the proved reach bound — bitwise, not to an epsilon" {
    // The campaign's §20 proposition 3. It is structural here: the cutoff
    // returns a hard zero, the clamp bounds where a touched kernel can be,
    // and a birth lands on the exemplar. So the claim is about bits.
    //
    // MUTATION: the cutoff's early return removed from `gaussian` (the
    // exponential evaluated everywhere and left to underflow) — probes at
    // every distance move, and the far ones move by ~1e-30, which is not
    // zero and would let a "substantially undisturbed" claim be made about
    // a model that disturbs everything. Verified by hand: 19 987 of 20 000
    // probes changed.
    const gpa = testing.allocator;
    const opts = Options{ .regions = 6, .budget = 64 };
    var m = try Model.init(gpa, opts);
    defer m.deinit();
    try m.stream_n(20_000);

    const n = 6000;
    const pr = try probes(gpa, 0xFACE, n);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);
    const before = try gpa.alloc(f32, n);
    defer gpa.free(before);
    for (pr.p, before) |p, *b| b.* = try m.predict(p);

    const x = [3]f32{ 0.30, 0.42, 0.46 };
    const ev = try m.observe(x, truth(x));
    try testing.expect(ev.learned); // the gate must actually have learned something

    const bound = thresholds.marl0ReachBound(m.h, opts.steps, opts.trust);
    // The bound must be a real restriction. Handed Adam's rate the
    // pre-registered formula returned 5.08 of a unit domain and this whole
    // gate passed on nothing at all; that is what the amendment in
    // `thresholds.marl0ReachBound` records, and this is what stops it
    // recurring.
    try testing.expect(bound < 0.75);
    var beyond_exists: usize = 0;
    var beyond: usize = 0;
    var observed: f32 = 0;
    var moved: usize = 0;
    for (pr.p, before) |p, b| {
        const a = try m.predict(p);
        const d = @max(@abs(p[0] - x[0]), @max(@abs(p[1] - x[1]), @abs(p[2] - x[2])));
        if (d > bound) beyond_exists += 1;
        if (a != b) {
            moved += 1;
            observed = @max(observed, d);
            if (d > bound) beyond += 1;
        }
    }
    try testing.expectEqual(@as(usize, 0), beyond);
    // …and there were probes out there to be disturbed.
    try testing.expect(beyond_exists > n / 10);
    try testing.expect(moved > 0); // not vacuous: the event moved something
    try testing.expect(ev.touched <= thresholds.MARL0_MAX_TOUCHED);
    const frac = @as(f64, @floatFromInt(ev.touched)) / @as(f64, @floatFromInt(m.kernels.items.len));
    try testing.expect(frac <= thresholds.MARL0_MAX_TOUCHED_FRACTION);
    std.debug.print("  G17 (d): {d} kernels touched of {d} ({d:.4}); nothing moved past {d:.4}, proved bound {d:.4} ({s})\n", .{ ev.touched, m.kernels.items.len, frac, observed, bound, @tagName(builtin.mode) });
}

test "G17 (e) the model learns: held-out RMS falls by the predicted gain, and nothing learning at all leaves it exactly where it started" {
    // MUTATION, and it is the run rather than an argument: with births
    // refused (`coverage` = 0, so no exemplar is ever uncovered enough)
    // and both rates zero, the model stays empty and the gain is 1.
    const gpa = testing.allocator;
    const pr = try probes(gpa, 0xB0B, 4096);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var m = try Model.init(gpa, .{ .regions = 6, .budget = 64 });
    defer m.deinit();
    const start = try m.rms(pr.p, pr.y, null);
    var t = try std.time.Timer.start();
    try m.stream_n(40_000);
    const ns = t.read();
    var mx: f32 = 0;
    const end = try m.rms(pr.p, pr.y, &mx);
    const gain = start / end;
    try testing.expect(gain >= thresholds.MARL0_RMS_GAIN);

    var dead = try Model.init(gpa, .{ .regions = 6, .budget = 64, .coverage = 0, .rate_w = 0, .rate_geom = 0 });
    defer dead.deinit();
    try dead.stream_n(40_000);
    try testing.expectEqual(@as(usize, 0), dead.kernels.items.len);
    try testing.expectEqual(start, try dead.rms(pr.p, pr.y, null));

    std.debug.print("  G17 (e): RMS {d:.5} → {d:.5}, gain {d:.2} (predicted ≥ {d:.0}); {d} kernels, {d} events, {d:.1} µs/1k exemplars ({s})\n", .{ start, end, gain, thresholds.MARL0_RMS_GAIN, m.kernels.items.len, m.stats.events, @as(f64, @floatFromInt(ns)) / 40_000.0, @tagName(builtin.mode) });
}

test "G17 (f) capacity follows the target's complexity, not its volume: the shell's band holds kernels and the quiet slab holds none" {
    // The campaign's §13, "difficult regions attract disproportionate
    // work", as a number rather than a picture.
    //
    // MUTATION, measured rather than argued: `.adam`. The batch optimiser
    // random-walks every touched centre by a full step whatever the
    // residual, kernels wander into the slab where the truth is zero, and
    // the ratio INVERTS — 0.2 at 100 000 exemplars, with the slab holding
    // a higher density than the shell. The ledger has the run.
    const gpa = testing.allocator;
    var m = try Model.init(gpa, .{ .regions = 6, .budget = 64 });
    defer m.deinit();
    try m.stream_n(40_000);

    const V_SHELL: f32 = 0.05169; // tools/marl_predict.py
    const V_QUIET: f32 = 0.09980;
    const shell = m.densityIn(Truth.inShell, V_SHELL);
    const quiet = m.densityIn(Truth.inQuiet, V_QUIET);
    try testing.expect(shell > 0); // not vacuous: the shell was found at all
    const ratio: f32 = if (quiet > 0) shell / quiet else std.math.inf(f32);
    try testing.expect(ratio >= thresholds.MARL0_CAPACITY_RATIO);
    std.debug.print("  G17 (f): shell {d:.0}/unit³, quiet slab {d:.0}/unit³, ratio {d:.1} (predicted ≥ {d:.0}) ({s})\n", .{ shell, quiet, ratio, thresholds.MARL0_CAPACITY_RATIO, @tagName(builtin.mode) });
}

test "G17 (g) the model is a function of (seed, exemplar count, options) and of nothing else" {
    // Counter-based draws, no sequential state, no clock read anywhere on
    // the learning path — the same discipline `rng.zig` was written for.
    // Byte equality on every parameter, because an epsilon here would hide
    // exactly the kind of order-dependence a parallel MARL would introduce.
    const gpa = testing.allocator;
    var a = try Model.init(gpa, .{ .regions = 5, .budget = 32 });
    defer a.deinit();
    var b = try Model.init(gpa, .{ .regions = 5, .budget = 32 });
    defer b.deinit();
    try a.stream_n(8_000);
    try b.stream_n(8_000);
    try testing.expectEqual(a.kernels.items.len, b.kernels.items.len);
    try testing.expect(a.kernels.items.len > 100);
    for (a.kernels.items, b.kernels.items) |*ka, *kb| {
        try testing.expectEqual(ka.owner, kb.owner);
        for (ka.p, kb.p) |pa, pb| try testing.expectEqual(@as(u32, @bitCast(pa)), @as(u32, @bitCast(pb)));
    }
    // And a different seed is a different model, or the gate is watching
    // a constant.
    var c = try Model.init(gpa, .{ .regions = 5, .budget = 32, .seed = 8 });
    defer c.deinit();
    try c.stream_n(8_000);
    try testing.expect(c.kernels.items.len != a.kernels.items.len or
        @as(u32, @bitCast(c.kernels.items[0].p[0])) != @as(u32, @bitCast(a.kernels.items[0].p[0])));
}

test "the truth has the three parts the campaign asked for: a smooth swell, a sharp shell, and a slab that is exactly zero" {
    // Not a gate on the learner — a gate on the EXPERIMENT. If the target
    // stopped having a quiet region, G17 (f) would be measuring nothing
    // and would still pass.
    var st = rng.Stream.region(5, 0x7217, 0);
    var i: usize = 0;
    var shell_peak: f32 = 0;
    var quiet: usize = 0;
    var band: usize = 0;
    while (i < 200_000) : (i += 1) {
        const p = [3]f32{ st.unit(), st.unit(), st.unit() };
        const t = truth(p);
        if (Truth.inQuiet(p)) {
            quiet += 1;
            try testing.expectEqual(@as(f32, 0), t);
        }
        if (Truth.inShell(p)) {
            band += 1;
            shell_peak = @max(shell_peak, t);
        }
    }
    try testing.expect(shell_peak > 0.8); // the sharp feature is really there
    try testing.expect(quiet > 10_000 and band > 5_000); // both regions were sampled
    // And the slab is not merely zero, it is UNREACHABLE: the window ends
    // before it by more than one region edge, so no kernel born on
    // structure can put weight there and the only route in is a leakage
    // cascade. This is the assertion that caught 0.85, where the sum
    // 0.70 + 1/6 = 0.8667 quietly exceeded it.
    try testing.expect(Truth.WINDOW_HI + 1.0 / 6.0 < Truth.QUIET_X);
    std.debug.print("\n  the truth: shell peak {d:.4} over {d} band samples, {d} quiet samples all exactly zero; the slab starts {d:.4} past a kernel's furthest reach ({s})\n", .{ shell_peak, band, quiet, Truth.QUIET_X - (Truth.WINDOW_HI + 1.0 / 6.0), @tagName(builtin.mode) });
}
