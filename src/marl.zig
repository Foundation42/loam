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
/// How complex the target is (MARL-1, Christian: "make target complexity
/// explicitly controllable, preferably with at least feature count and
/// spatial frequency/sharpness"). The defaults ARE MARL-0's target, term
/// for term, so every G17 number still stands.
pub const TruthParams = struct {
    /// Sharp shells. Feature 0 is MARL-0's; the rest are placed by a
    /// counter-based draw inside a box that cannot reach the quiet slab.
    features: u32 = 1,
    /// Multiplies 1/W: higher is a thinner ridge and a harder target.
    sharpness: f32 = 1,
    /// Multiplies the swell's three spatial frequencies.
    frequency: f32 = 1,
    /// MARL-6: every feature's centre is displaced by this. The world
    /// moves; nothing else about it changes, so old and new structure stay
    /// comparable and the hierarchy's response is attributable.
    shift: [3]f32 = .{ 0, 0, 0 },
};

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

    pub const Feature = struct { c: [3]f32, r: f32 };

    /// Feature i. Zero is MARL-0's shell exactly; the rest sit in
    /// x ∈ [0.15, 0.45] with radius ≤ 0.20, so the furthest any ridge
    /// reaches is 0.65 — inside the window, and so unable to put
    /// structure where the quiet slab's derivation says there is none.
    pub fn feature(tp: TruthParams, i: u32) Feature {
        var f: Feature = if (i == 0) .{ .c = SHELL_C, .r = SHELL_R } else blk: {
            var st = rng.Stream.region(0x5348_454C, i, 0); // "SHEL"
            break :blk .{
                .c = .{ 0.15 + 0.30 * st.unit(), 0.20 + 0.60 * st.unit(), 0.20 + 0.60 * st.unit() },
                .r = 0.12 + 0.08 * st.unit(),
            };
        };
        inline for (0..3) |a| f.c[a] += tp.shift[a];
        return f;
    }

    /// One at the origin end, zero past `WINDOW_HI`, a raised cosine
    /// between — so the swell dies smoothly and the quiet slab is not a
    /// second sharp feature.
    pub fn window(x: f32) f32 {
        if (x <= WINDOW_LO) return 1;
        if (x >= WINDOW_HI) return 0;
        const u = (x - WINDOW_LO) / (WINDOW_HI - WINDOW_LO);
        return 0.5 * (1 + fmath.cosf(std.math.pi * u));
    }

    pub fn swell(tp: TruthParams, p: [3]f32) f32 {
        const f = tp.frequency;
        return SWELL_A *
            fmath.sinf(TAU * (0.9 * f * p[0] + 0.13)) *
            fmath.cosf(TAU * (0.7 * f * p[1] - 0.21)) *
            fmath.sinf(TAU * (0.6 * f * p[2] + 0.37));
    }

    pub fn shell(tp: TruthParams, p: [3]f32) f32 {
        const w = SHELL_W / tp.sharpness;
        var acc: f32 = 0;
        var i: u32 = 0;
        while (i < tp.features) : (i += 1) {
            const ft = feature(tp, i);
            const d = [3]f32{ p[0] - ft.c[0], p[1] - ft.c[1], p[2] - ft.c[2] };
            const r = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
            const t = (r - ft.r) / w;
            const t2 = t * t;
            // Past exp(−16) the ridge is a tenth of a millionth of its
            // peak: cut it, the way a kernel is cut, so "outside the
            // shell" is a value and not an asymptote.
            if (t2 <= 16) acc += SHELL_A * fmath.expf(-t2);
        }
        return acc;
    }

    /// Within two widths of any ridge.
    pub fn inShell(tp: TruthParams, p: [3]f32) bool {
        const w = SHELL_W / tp.sharpness;
        var i: u32 = 0;
        while (i < tp.features) : (i += 1) {
            const ft = feature(tp, i);
            const d = [3]f32{ p[0] - ft.c[0], p[1] - ft.c[1], p[2] - ft.c[2] };
            const r = @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
            if (@abs(r - ft.r) < 2 * w) return true;
        }
        return false;
    }

    pub fn inQuiet(_: TruthParams, p: [3]f32) bool {
        return p[0] > QUIET_X;
    }
};

/// The volume of a region of the target, by a fixed deterministic
/// quadrature. Hard-coding it was wrong the moment `sharpness` existed:
/// the shell BAND is defined as two widths either side of a ridge, so
/// halving the width halves the band, and a density divided by the
/// one-feature volume reports a fall where the truth is a rise.
pub fn volumeOf(tp: TruthParams, comptime pred: fn (TruthParams, [3]f32) bool) f32 {
    const N: u32 = 200_000;
    var st = rng.Stream.region(0x564F_4C55, 0, 0); // "VOLU"
    var hit: u32 = 0;
    var i: u32 = 0;
    while (i < N) : (i += 1) {
        const p = [3]f32{ st.unit(), st.unit(), st.unit() };
        if (pred(tp, p)) hit += 1;
    }
    return @as(f32, @floatFromInt(hit)) / @as(f32, @floatFromInt(N));
}

pub fn truthOf(tp: TruthParams, p: [3]f32) f32 {
    return Truth.window(p[0]) * Truth.swell(tp, p) + Truth.shell(tp, p);
}

/// MARL-0's target: the defaults, and the one every G17 number was
/// measured against.
pub fn truth(p: [3]f32) f32 {
    return truthOf(.{}, p);
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

/// How the router scores a refined region (MARL-5).
///
/// The three signals are the only ones the campaign already understands:
/// NEED is unresolved representation pressure (the child's post-update
/// residual there); SUFFICIENCY is evidence per child kernel, MARL-4's
/// discovery that capacity you cannot train is worse than none; LAG is the
/// anti-starvation term, exemplars since the region was last served.
///
/// Deliberately not one clever multiplicative formula arrived at in a
/// single step: the point is to find out whether sufficiency contributes
/// CAUSALLY or merely correlates, and that needs the terms separable.
pub const SchedMode = enum {
    /// MARL-4: score is `route_floor + route_gain·|residual|`, per
    /// exemplar, with no per-region state at all.
    off,
    /// Largest residual wins. Christian's prediction is that this is NOT
    /// the best schedule, which makes it the one to beat rather than the
    /// one to use.
    need,
    /// need × (1 + lag/τ). The anti-starvation term alone.
    need_lag,
    /// need × (1 + lag/τ) ÷ (1 + sufficiency/ref). Damps a region whose
    /// kernels are already well evidenced, on the theory that more
    /// evidence there is not what its residual needs.
    need_lag_suff,
    /// The per-exemplar residual bias of MARL-4, modulated by the region's
    /// starvation. Added after the first three lost to static bias by 10%,
    /// to test whether the loss was GRANULARITY: a region-level schedule
    /// routes a whole region at one probability, and the residual
    /// structure this campaign has been chasing is a fortieth of the
    /// domain thick inside regions a sixth of it wide. A schedule coarser
    /// than its own signal throws away the selectivity MARL-4 established
    /// was the entire mechanism.
    hybrid,
};

/// Where a learned background takes its evidence from (MARL-16).
pub const BiasRule = enum {
    /// No background term. Every gate from G17 to G35 runs here, and
    /// locality is EXACT.
    off,
    /// A running mean of the RESIDUAL — what the kernels have not
    /// explained. The obvious formulation, and it does not work: the
    /// kernels descend at `rate_w` per event while a running mean's step
    /// is 1/n, so they absorb the background long before the bias can and
    /// then E[y − K] ≈ 0 leaves it stranded near zero. Measured at 0.1057
    /// after 125 000 exemplars on a field whose mean is far above that,
    /// for 1.302× the RMS and 8.5% MORE kernels. Kept because it is the
    /// formulation anyone would reach for first and the ledger should say
    /// why it is wrong.
    residual,
    /// A running mean of the TARGET, which converges whatever the kernels
    /// are doing. What the kernels then carry is `y − b`, whose amplitude
    /// is the field's standard deviation rather than its RMS — and MARL-13
    /// established that a smaller amplitude is most of what its inversion
    /// trick bought.
    target,
};

pub const BirthRule = enum {
    /// MARL-0 through MARL-2: birth where nothing already covers.
    coverage,
    /// MARL-3 as specified: birth on persistent post-update residual, and
    /// on nothing else.
    residual,
    /// Either. Keeps the coverage floor — which turns out to be about
    /// TRAINABILITY rather than placement — and adds residual-driven
    /// births on top of it.
    either,
};

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
    /// How a birth is decided (MARL-3, and the ONLY thing MARL-3 changes).
    ///
    /// `.coverage` — MARL-0 through MARL-2: birth where no kernel already
    /// reads above `coverage`. Geometric. It tiles whatever region it is
    /// given, which is why MARL-2's child concentrated no better than its
    /// parent (1.65 against a ceiling of 12.46 at sharpness ×4).
    ///
    /// `.residual` — birth where the POST-UPDATE residual has persisted:
    /// a cell of the evidence grid must have been visited `birth_evidence`
    /// times and still average more than `birth_residual` of error after
    /// adaptation. Both halves are needed, and the second is what keeps a
    /// singleton from being mistaken for structure (§5, "do not confuse
    /// noise with complexity").
    ///
    /// The default stays `.coverage` so that MARL-2 remains a reproducible
    /// configuration and G19 keeps measuring what it measured.
    birth_rule: BirthRule = .coverage,
    /// Observations a cell needs before its mean is evidence at all.
    birth_evidence: u32 = 8,
    /// The evidence cell's edge, in coverage spacings.
    ///
    /// One spacing is the natural scale — it is the neighbourhood a birth
    /// would claim — and at this exemplar budget it does not work: the
    /// refined volume holds about eighteen thousand such cells and receives
    /// about twenty-nine thousand routed exemplars, which is 1.6
    /// observations each against the eight required, and the child births
    /// NOTHING. Pooling over a coarser neighbourhood is the cheapest
    /// honest fix, and it costs less than it appears to: the cell decides
    /// WHERE EVIDENCE IS GATHERED, while the kernel is still placed at the
    /// exemplar, so widening it blurs the question and not the answer.
    ///
    /// This is Christian's evidence-per-kernel concern arriving one stage
    /// earlier than expected — at the birth decision rather than at the
    /// kernel — and it is the same trade: a finer grid asks a sharper
    /// question of a smaller sample.
    birth_scale: f32 = 2,
    /// Mean post-update residual a cell must still carry. Zero means "the
    /// surprise threshold" — this cell persistently fails to get under the
    /// bar the model already cares about, which needs no new number.
    birth_residual: f32 = 0,
    /// The target. MARL-1 experiment 2 varies this at fixed `coverage`.
    truth: TruthParams = .{},
    /// Births permitted. False FREEZES THE TOPOLOGY — MARL-1 experiment 1
    /// reruns arm A's discovered kernels with this off, so the question
    /// "given identical discovered capacity, what does deformation buy?"
    /// is asked with the capacity actually held identical (Christian: the
    /// A/C comparison is not a pure descent metric while C ends with 12%
    /// more kernels).
    births: bool = true,
    /// THE RESPONSIBILITY RADIUS, in Mahalanobis widths — the furthest a
    /// kernel may be from an exemplar and still LEARN from it.
    ///
    /// Support and responsibility are different things (Christian's
    /// ruling). Support is the full cutoff gather and prediction always
    /// sums it, so inference semantics do not move and `rbf.CUTOFF` is
    /// not touched. Responsibility is the subset permitted to take a
    /// gradient, and the NLMS normaliser Σg² is taken over THAT subset —
    /// over the support set instead, the attribution would divide by a
    /// sum larger than the corrections it is dividing among, and every
    /// step would silently under-correct.
    ///
    /// The default is `CUTOFF_R`: responsibility equals support, which is
    /// MARL-0 exactly. A kernel is only USEFUL out to about 1.45 widths
    /// (where it reads `coverage`), so most of the ninety kernels a
    /// learning event touches are contributing almost nothing to it.
    ///
    /// Note the coupling: below the coverage radius √(−2 ln coverage) no
    /// kernel can ever be responsible AND covering, so births fire on
    /// every event. `coverage` and this belong to the same sweep.
    responsibility: f32 = CUTOFF_R,
    /// A learned constant added to every prediction — `rbf.zig`'s "entry"
    /// as a parameter the model finds for itself.
    ///
    /// A hard cutoff makes a Gaussian decay to EXACTLY zero, so a constant
    /// non-zero background is not free: it has to be held up by
    /// overlapping kernels everywhere it extends. Every field this
    /// campaign learned before MARL-13 had a ZERO background — the quiet
    /// slab, the marble's matrix — so the term was never needed. Ambient
    /// occlusion is ≈1 across the open majority of a cube, and MARL-13
    /// measured the size of the hole by NEGATING the target: 1.40× the
    /// accuracy for 14% less capacity, from a trick that has to be told
    /// what the background is.
    ///
    /// **It costs exact locality, and that is the point of gating it.**
    /// `CUTOFF` makes a learning event structurally unable to disturb a
    /// distant region (G17 c, d, bitwise). One global scalar is not local
    /// at all: updating it moves every point by the same amount. Learned
    /// as a RUNNING MEAN the step is 1/n, so the disturbance decays and
    /// exact locality is recovered in the limit — asymptotic instead of
    /// exact. `rate_bias` puts a permanent floor back, deliberately, for a
    /// field that drifts.
    ///
    /// Default OFF, so every number from G17 to G35 is untouched.
    bias: BiasRule = .off,
    /// The floor under the bias's 1/n step. Zero is a pure running mean,
    /// which converges optimally and gives up its influence as it goes;
    /// non-zero is an EWMA that can track a moving background and never
    /// stops disturbing everywhere.
    rate_bias: f32 = 0,
    /// The recent-window the running error is averaged over.
    window: u32 = 4096,
};

/// When a region is judged unable to REPRESENT what it is being asked to
/// hold, as against merely not having learned it yet.
///
/// Christian's ruling, and the reason it is not "residual > threshold": a
/// large residual may be cheaply resolvable by ordinary deformation, and
/// refining on it would buy capacity the model did not need. What
/// distinguishes the two is whether the basis already believed it had the
/// ground covered. So pressure is measured ONLY over learning events where
/// `coverage` was already satisfied — no birth was called for — and it is
/// the residual left AFTER the update steps, which is what deformation
/// could not remove with the kernels it had.
///
/// MARL-1 is the evidence this is the right signal: at sharpness ×4 the
/// parent's kernel density on the ridge did not move while its accuracy
/// fell by a factor of three. Coverage was satisfied and the residual
/// stayed. That is the state this detects.
pub const PressureOptions = struct {
    /// Covered learning events a region must see before it can be judged.
    /// Below this the mean is noise, and refining on noise is the failure
    /// mode the campaign named in §5 — "do not confuse noise with
    /// complexity". Fifty, swept: 25 / 50 / 100 / 150 / 300 give held-out
    /// gains of 3.38 / 3.46 / 3.32 / 3.16 / 3.13 at sharpness ×2. Waiting
    /// longer buys precision (1.000 at 300) and loses accuracy, because a
    /// region that is refined late has already had its parent tile it.
    min_events: u32 = 50,
    /// Mean |post-update residual| over those events, above which the
    /// region is under representation pressure.
    ///
    /// A METHOD hyperparameter, not a gate threshold, and chosen the way
    /// one honestly can be: the statistic has a NOISE FLOOR made by the
    /// regions that are not under pressure, and that floor is observable
    /// without knowing where the structure is. Measured, it sits at 0.0044
    /// to 0.0046 and does not move with the target's sharpness — it is the
    /// surprise threshold's own residue. The pressured population does
    /// move: 0.0060 at sharpness ×1, 0.0089 at ×2, 0.0107 at ×4. So a
    /// threshold above the floor refines little on an easy target and a
    /// great deal on a hard one, at one fixed number, which is the
    /// property worth having. Seven thousandths clears the floor's highest
    /// observed value (0.0067) at every sharpness tested.
    threshold: f32 = 0.007,
    /// The child's region grid, as a multiple of the parent's. Two, and
    /// two levels only (Christian): enough to establish whether residual
    /// refinement works at all, and recursion is the boring part after.
    refine: u32 = 2,
    /// How the CHILD decides to birth — MARL-3's one variable. The default
    /// is MARL-2's, so that experiment stays reproducible from the
    /// defaults and G19 keeps measuring what it measured.
    child_birth: BirthRule = .coverage,
    /// MARL-4, and the only thing MARL-4 changes: an exemplar in a refined
    /// region reaches the child with probability
    ///
    ///     p = min(1, route_floor + route_gain · |y − parent(x)|)
    ///
    /// MARL-3 established that capacity can only concentrate where the
    /// STREAM concentrates — the child's kernels landed in the band at
    /// 21.89% when a filtered stream delivered 21.95%, to three digits —
    /// so the stream is what MARL-4 moves.
    ///
    /// The two terms are two different jobs, and the reason a hard filter
    /// is the wrong answer. `route_floor` is the TRAINABILITY floor: the
    /// coverage rule was silently supplying one, and MARL-3 walked into
    /// the over-responsibility regime through the third known door by
    /// removing it. `route_gain` is the epistemic bias. Starve the floor
    /// and the child's kernels are too sparse to train; drop the gain and
    /// the stream is uniform and no birth rule can concentrate above it.
    ///
    /// Defaults are MARL-2's: floor 1, gain 0 — route everything — so
    /// G19 and G20 keep measuring what they measured.
    route_floor: f32 = 1,
    route_gain: f32 = 0,
    /// MARL-5. Target fraction of the exemplars OFFERED to the child that
    /// are actually routed. Zero leaves MARL-4's raw probability alone;
    /// above zero, every routing score is normalised by its own running
    /// mean so the realised duty tracks this number whatever the score is.
    ///
    /// It exists so the arms can be compared at THE SAME ROUTED COUNT.
    /// Without it a scheduler wins by processing more, which answers a
    /// different question than the one asked.
    route_duty: f32 = 0,
    /// Which score the router normalises. `.off` is MARL-4's static
    /// `floor + gain·|residual|`; the rest are per-region schedules.
    sched: SchedMode = .off,
    /// The anti-starvation timescale, in exemplars: a region unserved for
    /// this long doubles its priority.
    lag_tau: f32 = 20_000,
    /// Evidence per child kernel at which a region counts as sufficiently
    /// served, so `.need_lag_suff` halves its priority.
    suff_ref: f32 = 200,
    /// MARL-7. A refined region is UNREFINED when its parent's error has
    /// grown by this factor over what it was when the region was refined —
    /// the parent has stopped being a valid coarse level there, and the
    /// child is being asked to do the parent's job rather than refine it.
    /// The child's kernels in the region are removed and the parent's are
    /// unfrozen IN ONE ACT, because MARL-7's opening measurement showed
    /// the archaeology is load-bearing: deleting a correction while the
    /// thing it corrects remains is not a repair.
    ///
    /// Zero disables it, which is MARL-2 through MARL-6, so every earlier
    /// gate keeps measuring what it measured.
    unrefine: f32 = 0,
    /// MARL-8: a retiring region's child is POOLED rather than destroyed,
    /// and a refining region draws from the pool — translated to its own
    /// origin — instead of starting empty. Positions and shapes are
    /// carried; weights are reset to zero, so the transplant changes the
    /// prediction by nothing at the moment it happens and the convex part
    /// is relearned in the new region's own terms against its own parent.
    ///
    /// Reuse is an ALLOCATOR operation. The exact locality that stops a
    /// gradient walking a kernel across the domain says nothing about an
    /// allocator moving one.
    recycle: bool = false,
    /// Routed exemplars a region must see before its baseline is taken
    /// and it becomes eligible — long enough for the EWMA to settle at a
    /// rate of 0.02, and short enough that a region actually reaches it:
    /// about thirty thousand exemplars are routed across some forty
    /// refined regions in a run, so a threshold of two thousand each was
    /// never reachable and the first version of this never fired once.
    unrefine_after: u32 = 300,
};

/// **The model, parameterised by how many CHANNELS a kernel weighs.**
///
/// MARL-0 through MARL-11 are all `Marl(1)`: one weight, one scalar
/// target, because the campaign's truth (§8) is scalar. `rbf.zig` fits
/// NINE — the vein's blend and the eight material columns it multiplies —
/// and they share one centre and one shape, which is the entire reason a
/// packed set is cheaper than nine sets: the geometry is paid for once.
///
/// C is comptime rather than a field, and that is a performance decision
/// with the campaign's own numbers behind it. The weights live INSIDE the
/// kernel, at `p[W..W+C]`, so the NLMS inner loop reads them from the same
/// cache line it just read the shape from. A runtime channel count would
/// put them in a second array and cost a miss per kernel per step, on a
/// path that touches ninety kernels an event — and MARL's standing against
/// a batch bake is 45x the speed at the same kernel count (MARL-11), which
/// is not a number to spend on saving an indent.
///
/// Everything C-free stays outside: `Options`, `PressureOptions`, the
/// truth, the kernel's own arithmetic (`mahal`, `gaussian`, `halfExtents`,
/// `reachOf`) — so a `Marl(1)` and a `Marl(9)` are configured by the same
/// values and read by the same shape math, and only the parameter vector
/// differs.
pub fn Marl(comptime C: usize) type {
    return struct {
        /// This instantiation's own namespace.
        ///
        /// Zig forbids a nested container from shadowing a file-level
        /// declaration, and the file DOES declare `Model`, `Kernel` and the
        /// rest below as the C = 1 facade. So every reference in here names
        /// them through `Ch`, and the facade keeps the plain names that every
        /// gate and both runners already use — which is why widening the
        /// kernel changed no call site anywhere.
        const Ch = @This();

        /// Parameters per kernel: the centre (3), the LOG of L's diagonal (3, so
        /// a width stays positive), L's off-diagonal (3: l10, l20, l21) and ONE
        /// WEIGHT PER CHANNEL. `rbf.KERNEL_FLOATS` is this at C = 9.
        pub const PARAMS: usize = W + C;
        /// How many channels this instantiation weighs, for code that needs to
        /// say so rather than take it from a signature.
        pub const CHANNELS: usize = C;

        /// One value per channel — a target, a prediction, a residual.
        /// `[1]f32` for the campaign, `[9]f32` for the marble's materials.
        pub const Vec = [C]f32;

        /// The MAGNITUDE of a channel vector: the largest absolute component.
        ///
        /// Max and not a Euclidean norm, for two reasons. Loam's R15 already
        /// merges attention by MAX on each field separately, and for the same
        /// reason — the question a threshold asks is whether ANY channel is
        /// surprising here, not whether the channels are surprising on
        /// average, and an average lets one badly wrong channel hide behind
        /// eight right ones. And at C = 1 it is `@abs` EXACTLY, bit for bit,
        /// which is what lets every gate from G17 to G29 keep its numbers
        /// unchanged across this widening.
        /// The campaign's SCALAR truth (§8) as a channel vector: channel 0
        /// carries it and the rest are zero. There is no multi-channel
        /// synthetic truth and there should not be one — a target invented
        /// to exercise nine channels would be nine channels of whatever the
        /// inventor already believed. Anything wanting a real one brings
        /// its own field, as `src/marble.zig` does.
        /// The geometry step's channel-count correction, and it is
        /// LOAD-BEARING at C > 1.
        ///
        /// The centre and shape descend on `ew = Σ_c w_c a_c` — one term
        /// per channel, because nine weights pull on one Gaussian and each
        /// gets a say in where it goes. For channel errors that are not
        /// perfectly aligned that sum grows as √C, so the rate that is
        /// right at one channel is √C too large at C of them.
        ///
        /// Measured, on the two-material sheet at nine channels: at the
        /// C = 1 rate the model DIVERGES in exactly MARL-1's way — the
        /// vein-biased arm births 3 666 kernels against the uniform arm's
        /// 1 896 and scores WORSE with them (0.629 against 0.352), which is
        /// the over-capacity-under-evidence signature. At `rate/√C` it is
        /// stable and every one of MARL-12's pre-registered numbers holds.
        /// `rate/C` was tested too and is slightly worse (blend RMS 0.928
        /// against 0.931, D/B 1.878 against 1.762) — which is the evidence
        /// that the growth is √C and not C, rather than merely that
        /// something smaller was needed.
        ///
        /// At C = 1 this is a division by exactly 1.0, so every number the
        /// campaign recorded before the widening is untouched.
        pub const GEOM_RATE: f32 = 1.0 / @sqrt(@as(f32, @floatFromInt(C)));

        pub fn vecOf(t: f32) Ch.Vec {
            var v: Ch.Vec = [_]f32{0} ** C;
            v[0] = t;
            return v;
        }

        pub fn magOf(v: Ch.Vec) f32 {
            var m: f32 = 0;
            inline for (0..C) |c| m = @max(m, @abs(v[c]));
            return m;
        }

        pub const Kernel = struct {
            p: [Ch.PARAMS]f32,
            /// Adam's moments and this kernel's OWN step count: kernels are
            /// updated at irregular times, so the bias correction cannot share a
            /// clock.
            m1: [Ch.PARAMS]f32 = [_]f32{0} ** Ch.PARAMS,
            m2: [Ch.PARAMS]f32 = [_]f32{0} ** Ch.PARAMS,
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
            /// Held: the region this kernel belongs to has been refined, so its
            /// contribution is the coarse approximation the child is learning the
            /// residual of. Frozen for real — an exemplar in a NEIGHBOURING region
            /// can reach a kernel across the face, and a "frozen" parent that
            /// drifts by that route is a parent the child is chasing.
            frozen: bool = false,

            pub fn shape(self: *const Ch.Kernel) Shape {
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

            /// The kernel's weights, one per channel — a VIEW into the
            /// parameter vector and not a copy, because the NLMS step
            /// writes through it.
            pub fn weights(self: *Ch.Kernel) *[C]f32 {
                return self.p[W..][0..C];
            }

            pub fn weightsConst(self: *const Ch.Kernel) *const [C]f32 {
                return self.p[W..][0..C];
            }

            pub fn drift(self: *const Ch.Kernel) f32 {
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
            residual: Ch.Vec,
            /// `magOf(residual)` — the scalar that every threshold, every birth
            /// decision and every pressure statistic reads.
            surprise: f32,
            learned: bool,
            born: bool,
            saturated: bool,
            /// Some kernel already read above `coverage` at the exemplar, so no
            /// birth was called for. This is the half of the population that
            /// matters for representation pressure: a residual that persists where
            /// the basis said it had the ground covered is the basis being wrong
            /// about itself, and a residual where nothing covers the ground is
            /// just a birth waiting to happen.
            covered: bool,
            /// The residual AFTER the update steps. What deformation could not
            /// remove from this exemplar with the kernels it had.
            post_residual: Ch.Vec,
            /// Kernels whose support contains the exemplar: exactly the set the
            /// prediction summed.
            touched: u32,
            /// Kernels inside the RESPONSIBILITY radius — the subset that actually
            /// took a gradient. Equal to `touched` when responsibility is support,
            /// which is the default. Counted separately because reporting the
            /// support set for both makes a responsibility sweep look like it
            /// changes nothing: the number that moves is this one.
            responsible: u32,
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
            responsible: u64 = 0,
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
            /// THE WORK: gradient applications, summed over kernels and steps. A
            /// count, never a time — the unit that replays across machines, and
            /// what `work_C/work_A` is measured in.
            updates: u64 = 0,
        };

        pub const Model = struct {
            /// How many channels this model weighs, readable from the TYPE —
            /// so a caller handed a `*Model` can size its own buffers without
            /// being told separately which instantiation it got.
            pub const CHANNELS: usize = C;

            gpa: std.mem.Allocator,
            opts: Options,
            /// The learned background (`opts.bias`), and how many exemplars
            /// have gone into it. Zero and unused when the option is off.
            bias: Ch.Vec = [_]f32{0} ** C,
            bias_n: u64 = 0,
            /// Region edge, and the widest a kernel's cutoff box may reach.
            h: f32,
            sigma_max: f32,
            sigma_min: f32,
            kernels: std.ArrayListUnmanaged(Ch.Kernel) = .{},
            regions: []Ch.Region,
            stats: Ch.Stats = .{},
            stream: rng.Stream,
            /// Scratch for a gather: reused, so an observation allocates nothing.
            hit: std.ArrayListUnmanaged(u32) = .{},
            /// The recent window of |residual| (campaign §11), a ring.
            recent: []f32,
            recent_n: u64 = 0,
            /// The residual evidence grid (`.residual` births only): per cell, how
            /// many learning events landed there and the sum of what was left
            /// after adaptation. Cells are one coverage-spacing across, which is
            /// the scale at which a birth would be placed anyway — finer would be
            /// evidence about nothing, coarser would place kernels by a rule
            /// blinder than the one being replaced.
            ev_cells: u32 = 0,
            ev_count: []u32 = &.{},
            ev_sum: []f32 = &.{},
            /// Stamps for counting the distinct regions one event reached, in one
            /// pass over the touched set rather than a pass per member: sixty
            /// kernels is the predicted touch and sixty squared per event is not
            /// a measurement, it is the measurement's cost.
            visit_gen: []u32,
            gen: u32 = 0,

            pub fn init(gpa: std.mem.Allocator, opts: Options) !Ch.Model {
                const n = opts.regions * opts.regions * opts.regions;
                const regions = try gpa.alloc(Ch.Region, n);
                errdefer gpa.free(regions);
                for (regions) |*r| r.* = .{};
                const recent = try gpa.alloc(f32, opts.window);
                errdefer gpa.free(recent);
                @memset(recent, 0);
                const gens = try gpa.alloc(u32, n);
                errdefer gpa.free(gens);
                @memset(gens, 0);
                const h = 1 / @as(f32, @floatFromInt(opts.regions));
                const sig_max = h / CUTOFF_R;
                var ev_cells: u32 = 0;
                var ev_count: []u32 = &.{};
                var ev_sum: []f32 = &.{};
                if (opts.birth_rule != .coverage) {
                    const r_cov = @sqrt(-2 * @log(@max(1e-6, opts.coverage)));
                    ev_cells = @intFromFloat(@ceil(1 / (opts.birth_scale * r_cov * sig_max)));
                    ev_cells = @max(2, ev_cells);
                    const cells: usize = @as(usize, ev_cells) * ev_cells * ev_cells;
                    ev_count = try gpa.alloc(u32, cells);
                    errdefer gpa.free(ev_count);
                    @memset(ev_count, 0);
                    ev_sum = try gpa.alloc(f32, cells);
                    @memset(ev_sum, 0);
                }
                return .{
                    .gpa = gpa,
                    .opts = opts,
                    .h = h,
                    .sigma_max = sig_max,
                    // A width may thin to a sixty-fourth of a region — the shell
                    // is a fortieth of the domain thick and a kernel that cannot
                    // get thinner than the feature cannot represent it.
                    .sigma_min = h / 64,
                    .regions = regions,
                    .stream = rng.Stream.region(opts.seed, 0x4D41_524C, 0), // "MARL"
                    .recent = recent,
                    .visit_gen = gens,
                    .ev_cells = ev_cells,
                    .ev_count = ev_count,
                    .ev_sum = ev_sum,
                };
            }

            pub fn deinit(self: *Ch.Model) void {
                for (self.regions) |*r| r.own.deinit(self.gpa);
                self.gpa.free(self.regions);
                self.kernels.deinit(self.gpa);
                self.hit.deinit(self.gpa);
                self.gpa.free(self.recent);
                self.gpa.free(self.visit_gen);
                if (self.ev_count.len > 0) self.gpa.free(self.ev_count);
                if (self.ev_sum.len > 0) self.gpa.free(self.ev_sum);
            }

            fn evIndex(self: *const Ch.Model, p: [3]f32) usize {
                const n = self.ev_cells;
                var c: [3]u32 = undefined;
                inline for (0..3) |a| {
                    const v = @floor(p[a] * @as(f32, @floatFromInt(n)));
                    c[a] = if (v < 0) 0 else @min(n - 1, @as(u32, @intFromFloat(v)));
                }
                return (@as(usize, c[2]) * n + c[1]) * n + c[0];
            }

            /// Whether this cell has seen enough, and still carries too much.
            fn evidenced(self: *const Ch.Model, idx: usize) bool {
                const n = self.ev_count[idx];
                if (n < self.opts.birth_evidence) return false;
                const bar = if (self.opts.birth_residual > 0) self.opts.birth_residual else self.opts.threshold;
                return self.ev_sum[idx] / @as(f32, @floatFromInt(n)) > bar;
            }

            /// Child kernels that have had enough gradient to have been adapted at
            /// all. MARL-2's refine sweep showed allocated and usable capacity are
            /// different things; this is the second of the two, measured and not
            /// yet used for anything.
            pub fn trainedFraction(self: *const Ch.Model, min_updates: u32) f32 {
                if (self.kernels.items.len == 0) return 0;
                var n: u32 = 0;
                for (self.kernels.items) |*k| {
                    if (k.updates >= min_updates) n += 1;
                }
                return @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(self.kernels.items.len));
            }

            pub fn meanUpdates(self: *const Ch.Model) f32 {
                if (self.kernels.items.len == 0) return 0;
                var acc: u64 = 0;
                for (self.kernels.items) |*k| acc += k.updates;
                return @as(f32, @floatFromInt(acc)) / @as(f32, @floatFromInt(self.kernels.items.len));
            }

            // ── geometry ──────────────────────────────────────────────────────

            fn cellOf(self: *const Ch.Model, x: f32) u32 {
                const r = self.opts.regions;
                const c = @floor(x / self.h);
                if (c < 0) return 0;
                const ci: u32 = @intFromFloat(c);
                return @min(r - 1, ci);
            }

            pub fn regionOf(self: *const Ch.Model, p: [3]f32) u32 {
                const r = self.opts.regions;
                return (self.cellOf(p[2]) * r + self.cellOf(p[1])) * r + self.cellOf(p[0]);
            }

            fn regionCoords(self: *const Ch.Model, idx: u32) [3]u32 {
                const r = self.opts.regions;
                return .{ idx % r, (idx / r) % r, idx / (r * r) };
            }

            /// ∞-distance from q to a region's closed cube — what `max_reach` is
            /// compared against.
            fn distToRegion(self: *const Ch.Model, idx: u32, q: [3]f32) f32 {
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
            fn gather(self: *Ch.Model, q: [3]f32, ev: ?*Ch.Event) !void {
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
            pub fn gatherForTest(self: *Ch.Model, q: [3]f32) !void {
                try self.gather(q, null);
            }

            /// The prediction at q. Exact: the cutoff makes every kernel the
            /// gather did not reach contribute zero, not a small number.
            pub fn predict(self: *Ch.Model, q: [3]f32) !Ch.Vec {
                var t = std.time.Timer.start() catch null;
                try self.gather(q, null);
                var y: Ch.Vec = [_]f32{0} ** C;
                for (self.hit.items) |ki| {
                    const k = &self.kernels.items[ki];
                    const g = gaussian(k.shape(), q);
                    const w = k.weightsConst();
                    inline for (0..C) |c| y[c] += w[c] * g;
                }
                // Behind a branch and not an unconditional `+ 0`, because
                // `−0.0 + 0.0` is `+0.0` and a sign of zero reaches the
                // gates that compare predictions bitwise.
                if (self.opts.bias != .off) inline for (0..C) |c| {
                    y[c] += self.bias[c];
                };
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
            pub fn predictAll(self: *const Ch.Model, q: [3]f32) Ch.Vec {
                var y: Ch.Vec = [_]f32{0} ** C;
                for (self.regions) |*reg| {
                    for (reg.own.items) |ki| {
                        const k = &self.kernels.items[ki];
                        const g = gaussian(k.shape(), q);
                        const w = k.weightsConst();
                        inline for (0..C) |c| y[c] += w[c] * g;
                    }
                }
                if (self.opts.bias != .off) inline for (0..C) |c| {
                    y[c] += self.bias[c];
                };
                return y;
            }

            // ── the clamp ─────────────────────────────────────────────────────

            /// Project a kernel's parameters back inside what keeps the gather
            /// exact: the centre in the cube, no width below the floor, and the
            /// cutoff box reaching at most one region edge. The reach projection
            /// scales L, which shrinks every half-extent by the same factor and
            /// so keeps the SHAPE — an ellipsoid stays as anisotropic as the
            /// descent made it, it only stops growing past the gather.
            fn clamp(self: *Ch.Model, k: *Ch.Kernel) void {
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
            fn moveCentre(self: *Ch.Model, k: *Ch.Kernel, d: [3]f32) void {
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
            fn rehome(self: *Ch.Model, ki: u32) !void {
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

            /// Hold every kernel a region owns. The parent's contribution in a
            /// refined region is RETAINED, not relearned — which is the whole of
            /// the residual hierarchy's semantics: the child holds exactly what
            /// this level could not.
            pub fn freezeRegion(self: *Ch.Model, region: u32) void {
                for (self.regions[region].own.items) |ki| self.kernels.items[ki].frozen = true;
            }

            pub fn unfreezeRegion(self: *Ch.Model, region: u32) void {
                for (self.regions[region].own.items) |ki| self.kernels.items[ki].frozen = false;
            }

            /// Remove the kernels `dead` marks, and rebuild every index that named
            /// them. Real removal rather than a zeroed weight, because the child's
            /// POPULATION is a headline number for erosion and a kernel that still
            /// occupies a gather is not retired.
            pub fn compact(self: *Ch.Model, dead: []const bool) !void {
                var kept = std.ArrayListUnmanaged(Ch.Kernel){};
                errdefer kept.deinit(self.gpa);
                try kept.ensureTotalCapacity(self.gpa, self.kernels.items.len);
                for (self.kernels.items, dead) |k, d| {
                    if (!d) kept.appendAssumeCapacity(k);
                }
                self.kernels.deinit(self.gpa);
                self.kernels = kept;
                for (self.regions) |*r| {
                    r.own.clearRetainingCapacity();
                    r.max_reach = 0;
                }
                for (self.kernels.items, 0..) |*k, i| {
                    const owner = self.regionOf(.{ k.p[MU], k.p[MU + 1], k.p[MU + 2] });
                    k.owner = owner;
                    try self.regions[owner].own.append(self.gpa, @intCast(i));
                    if (k.reach > self.regions[owner].max_reach) self.regions[owner].max_reach = k.reach;
                }
            }

            pub fn frozenCount(self: *const Ch.Model) u32 {
                var n: u32 = 0;
                for (self.kernels.items) |*k| {
                    if (k.frozen) n += 1;
                }
                return n;
            }

            /// Recompute every region's bound from the kernels it owns. Only ever
            /// LOWERS one, so it changes no answer — it makes the prune sharper,
            /// and the gate that the bound is conservative is what says so.
            pub fn retighten(self: *Ch.Model) void {
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
            pub fn observe(self: *Ch.Model, x: [3]f32, y: Ch.Vec) !Ch.Event {
                const zero: Ch.Vec = [_]f32{0} ** C;
                var ev = Ch.Event{ .residual = zero, .surprise = 0, .learned = false, .born = false, .saturated = false, .covered = false, .post_residual = zero, .touched = 0, .responsible = 0, .regions_touched = 0, .evaluated = 0, .visited = 0, .pruned = 0 };
                var pt = std.time.Timer.start() catch null;

                try self.gather(x, &ev);
                const resp2 = self.opts.responsibility * self.opts.responsibility;
                var yhat: Ch.Vec = [_]f32{0} ** C;
                var cover: f32 = 0;
                for (self.hit.items) |ki| {
                    const k = &self.kernels.items[ki];
                    const m = mahal(k.shape(), x);
                    const g = if (m.r2 > CUTOFF) 0 else fmath.expf(-0.5 * m.r2);
                    // Prediction is over the SUPPORT set — always, or it stops
                    // being the sum over the model. Coverage is over the
                    // RESPONSIBILITY set, because coverage asks whether some
                    // kernel can be made answerable for this exemplar, and a
                    // kernel that may not learn from it cannot.
                    const w = k.weightsConst();
                    inline for (0..C) |c| yhat[c] += w[c] * g;
                    if (m.r2 <= resp2) cover = @max(cover, g);
                }
                if (self.opts.bias != .off) inline for (0..C) |c| {
                    yhat[c] += self.bias[c];
                };
                if (pt) |*tt| self.stats.predict_ns += tt.read();
                self.stats.predictions += 1;
                ev.touched = @intCast(self.hit.items.len);
                inline for (0..C) |c| ev.residual[c] = y[c] - yhat[c];
                ev.surprise = Ch.magOf(ev.residual);

                // The background, as a RUNNING MEAN of what the kernels
                // have not explained. Stepped 1/n, so at n = 1 it is the
                // first exemplar exactly and the warm-up cannot buy kernels
                // to hold up a constant it is about to learn; and so that
                // its disturbance to the whole field decays rather than
                // sitting at a permanent floor.
                //
                // Updated on EVERY exemplar, including the ones below the
                // surprise threshold. A background is exactly what a
                // sequence of unsurprising exemplars is evidence about, and
                // skipping them would bias it toward the structure.
                if (self.opts.bias != .off) {
                    self.bias_n += 1;
                    const step = @max(self.opts.rate_bias, 1 / @as(f32, @floatFromInt(self.bias_n)));
                    switch (self.opts.bias) {
                        .off => unreachable,
                        .residual => inline for (0..C) |c| {
                            self.bias[c] += step * ev.residual[c];
                        },
                        // From the TARGET, so the estimate does not depend
                        // on how fast the kernels are eating the thing it
                        // is trying to measure.
                        .target => inline for (0..C) |c| {
                            self.bias[c] += step * (y[c] - self.bias[c]);
                        },
                    }
                }

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

                ev.covered = cover >= self.opts.coverage;
                if (ev.surprise <= self.opts.threshold) return ev;

                var lt = std.time.Timer.start() catch null;
                ev.learned = true;
                reg.events += 1;
                self.stats.events += 1;

                // Birth. Under `.coverage` this is the campaign's §10 rule — no
                // kernel covers the exemplar usefully. Under `.residual` it is
                // MARL-3's: this neighbourhood has been visited enough times and
                // still carries too much error AFTER adaptation, so the shortfall
                // is representational and not merely unlearned.
                //
                // Either way the weight is the residual, so the newborn alone
                // answers this exemplar exactly and the descent has to keep it
                // honest at every other exemplar it reaches.
                const ev_idx: usize = if (self.opts.birth_rule != .coverage) self.evIndex(x) else 0;
                const want_birth = switch (self.opts.birth_rule) {
                    .coverage => cover < self.opts.coverage,
                    .residual => self.evidenced(ev_idx),
                    .either => cover < self.opts.coverage or self.evidenced(ev_idx),
                };
                if (want_birth and self.opts.births) {
                    if (reg.own.items.len >= self.opts.budget) {
                        ev.saturated = true;
                        reg.saturated += 1;
                        self.stats.saturations += 1;
                    } else {
                        const sigma = self.opts.birth_width * self.sigma_max;
                        const inv = 1 / sigma;
                        const li = @log(inv);
                        const ki: u32 = @intCast(self.kernels.items.len);
                        // The weight is the residual ON EVERY CHANNEL, so the
                        // newborn alone answers this exemplar exactly and the
                        // descent has to keep it honest everywhere else it
                        // reaches. Written as a geometry prefix plus the
                        // residual rather than a literal, because the literal
                        // was ten floats and PARAMS is now 9 + C.
                        var born: [Ch.PARAMS]f32 = undefined;
                        born[MU..][0..3].* = x;
                        born[LOGD..][0..3].* = .{ li, li, li };
                        born[OFF..][0..3].* = .{ 0, 0, 0 };
                        born[W..][0..C].* = ev.residual;
                        try self.kernels.append(self.gpa, .{
                            .p = born,
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
                        // The evidence has been spent. Without this the same cell
                        // births on every subsequent event until its mean falls,
                        // which is a burst of kernels for one piece of evidence.
                        if (self.opts.birth_rule != .coverage) {
                            self.ev_count[ev_idx] = 0;
                            self.ev_sum[ev_idx] = 0;
                        }
                    }
                }

                // The steps. Only the kernels in `hit` move, and `hit` is exactly
                // the kernels whose support contains x.
                var grad: [Ch.PARAMS]f32 = undefined;
                var s: u32 = 0;
                while (s < self.opts.steps) : (s += 1) {
                    var pred: Ch.Vec = [_]f32{0} ** C;
                    var gg: f32 = 0;
                    for (self.hit.items) |ki| {
                        const k = &self.kernels.items[ki];
                        const m = mahal(k.shape(), x);
                        const g = if (m.r2 > CUTOFF) 0 else fmath.expf(-0.5 * m.r2);
                        // support: the whole sum, always
                        const w = k.weightsConst();
                        inline for (0..C) |c| pred[c] += w[c] * g;
                        if (m.r2 <= resp2) gg += g * g; // responsibility: who pays
                    }
                    // The error per channel. `gg` is channel-free: the kernels
                    // share one geometry, so they share one normaliser, and
                    // dividing each channel by its own would make a kernel's
                    // share of the residual depend on which channel is asking.
                    var e: Ch.Vec = undefined;
                    inline for (0..C) |c| e[c] = pred[c] - y[c];
                    switch (self.opts.optimizer) {
                        .adam => for (self.hit.items) |ki| {
                            const k = &self.kernels.items[ki];
                            if (k.frozen) continue;
                            if (mahal(k.shape(), x).r2 > resp2) continue;
                            if (!Ch.gradOne(k, x, e, &grad)) continue;
                            const mu0 = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                            Ch.adam(k, &grad, self.opts.rate);
                            // Through the same trust region, so the interference
                            // bound is a property of the model and not of which
                            // optimiser happens to be mounted.
                            const d = [3]f32{ k.p[MU] - mu0[0], k.p[MU + 1] - mu0[1], k.p[MU + 2] - mu0[2] };
                            inline for (0..3) |c| k.p[MU + c] = mu0[c];
                            self.moveCentre(k, d);
                            self.clamp(k);
                            k.updates += 1;
                            self.stats.updates += 1;
                        },
                        .nlms => {
                            const inv = 1 / (gg + 1e-6);
                            for (self.hit.items) |ki| {
                                const k = &self.kernels.items[ki];
                                if (k.frozen) continue;
                                const sh = k.shape();
                                const m = mahal(sh, x);
                                if (m.r2 > resp2) continue;
                                const g = fmath.expf(-0.5 * m.r2);
                                // This kernel's share of the residual, per
                                // channel.
                                var a: Ch.Vec = undefined;
                                inline for (0..C) |c| a[c] = e[c] * g * inv;
                                const w = k.weights();
                                // The GEOMETRY's share is the sum over channels
                                // of each weight's own attribution — `rbf`'s
                                // `ew`, and the whole reason a packed set is
                                // cheaper than C separate ones: nine channels
                                // pull on one centre and one shape, so the
                                // geometry is paid for once and every channel
                                // gets a say in where it goes.
                                //
                                // Accumulated from channel 0 rather than from a
                                // zero, so that at C = 1 this is `w[0] * a[0]`
                                // bit for bit — `0 + (−0.0)` is `+0.0`, and a
                                // sign of zero here would reach `moveCentre`.
                                var ew: f32 = w[0] * a[0];
                                inline for (1..C) |c| ew += w[c] * a[c];
                                const wa = ew * Ch.GEOM_RATE * self.opts.rate_geom;
                                inline for (0..C) |c| w[c] -= self.opts.rate_w * a[c];
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
                                self.stats.updates += 1;
                            }
                        },
                    }
                }
                for (self.hit.items) |ki| try self.rehome(ki);

                {
                    var after: Ch.Vec = [_]f32{0} ** C;
                    for (self.hit.items) |ki| {
                        const k = &self.kernels.items[ki];
                        const g = gaussian(k.shape(), x);
                        const w = k.weightsConst();
                        inline for (0..C) |c| after[c] += w[c] * g;
                    }
                    inline for (0..C) |c| ev.post_residual[c] = y[c] - after[c];
                    if (self.opts.birth_rule != .coverage) {
                        self.ev_count[ev_idx] += 1;
                        self.ev_sum[ev_idx] += Ch.magOf(ev.post_residual);
                        // Forget by halving, so the mean is over RECENT evidence.
                        // A running mean over a whole run keeps a cell that was
                        // bad early and is fine now looking bad forever, and would
                        // birth on history rather than on the present residual.
                        if (self.ev_count[ev_idx] >= 4 * self.opts.birth_evidence) {
                            self.ev_count[ev_idx] /= 2;
                            self.ev_sum[ev_idx] *= 0.5;
                        }
                    }
                }
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
                for (self.hit.items) |ki| {
                    if (mahal(self.kernels.items[ki].shape(), x).r2 <= resp2) ev.responsible += 1;
                }
                self.stats.responsible += ev.responsible;
                self.stats.touched += ev.touched;
                self.stats.regions_touched += ev.regions_touched;
                if (lt) |*tt| self.stats.learn_ns += tt.read();
                return ev;
            }

            /// Draw an exemplar from the domain and observe it. Uniform, from the
            /// counter-based stream — no sequential draw anywhere, so the model
            /// is a function of (seed, count) and of nothing about the order work
            /// happened to be done in.
            pub fn observeOne(self: *Ch.Model) !Ch.Event {
                const x = [3]f32{ self.stream.unit(), self.stream.unit(), self.stream.unit() };
                return self.observe(x, Ch.vecOf(truthOf(self.opts.truth, x)));
            }

            pub fn stream_n(self: *Ch.Model, n: u64) !void {
                var i: u64 = 0;
                while (i < n) : (i += 1) _ = try self.observeOne();
            }

            /// Take another model's DISCOVERED TOPOLOGY — centres, shapes,
            /// weights — and nothing else: no optimiser state, no update counts,
            /// no history. Drift is then measured from where this model starts,
            /// which is the frozen topology, so "how far did deformation move
            /// what birth found" is a number and not an inference.
            pub fn reseedFrom(self: *Ch.Model, src: *const Ch.Model) !void {
                for (self.regions) |*r| {
                    r.own.clearRetainingCapacity();
                    r.max_reach = 0;
                }
                self.kernels.clearRetainingCapacity();
                for (src.kernels.items) |*k| {
                    const mu = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    const owner = self.regionOf(mu);
                    const ki: u32 = @intCast(self.kernels.items.len);
                    try self.kernels.append(self.gpa, .{ .p = k.p, .owner = owner, .mu0 = mu, .reach = k.reach, .born_at = 0 });
                    try self.regions[owner].own.append(self.gpa, ki);
                    if (k.reach > self.regions[owner].max_reach) self.regions[owner].max_reach = k.reach;
                }
            }

            // ── measurement ───────────────────────────────────────────────────

            /// Root mean square error over a held-out set — points drawn from
            /// their own stream and never learned from.
            /// Over the points AND the channels — the mean square is taken
            /// across both, so C = 1 is the campaign's number unchanged and
            /// C = 9 is one figure for the whole set rather than nine to
            /// compare by eye. `max_abs` stays the worst SINGLE channel at
            /// the worst point, because a peak that hides in a mean is
            /// exactly what it is there to catch.
            pub fn rms(self: *Ch.Model, pts: []const [3]f32, targets: []const Ch.Vec, max_abs: ?*f32) !f32 {
                var acc: f64 = 0;
                var mx: f32 = 0;
                for (pts, targets) |p, t| {
                    const yh = try self.predict(p);
                    inline for (0..C) |c| {
                        const e = yh[c] - t[c];
                        acc += @as(f64, e) * @as(f64, e);
                        mx = @max(mx, @abs(e));
                    }
                }
                if (max_abs) |m| m.* = mx;
                return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pts.len * C))));
            }

            pub fn recentError(self: *const Ch.Model) f32 {
                const n: usize = @intCast(@min(self.recent_n, self.opts.window));
                if (n == 0) return 0;
                var acc: f64 = 0;
                for (self.recent[0..n]) |v| acc += v;
                return @floatCast(acc / @as(f64, @floatFromInt(n)));
            }

            pub fn occupiedRegions(self: *const Ch.Model) u32 {
                var n: u32 = 0;
                for (self.regions) |*r| {
                    if (r.own.items.len > 0) n += 1;
                }
                return n;
            }

            pub fn saturatedRegions(self: *const Ch.Model) u32 {
                var n: u32 = 0;
                for (self.regions) |*r| {
                    if (r.own.items.len >= self.opts.budget) n += 1;
                }
                return n;
            }

            /// What the kernels are being asked to carry. Christian's reading of
            /// the coverage-0.10 divergence: under-birth causes OVER-RESPONSIBILITY
            /// — too few kernels forced to explain too much territory, weights go
            /// pathological, and the resulting predictions then corrupt the
            /// coverage decision that would have birthed more. The truth's own
            /// range is about 1.25, so a mean |w| near that is already a warning
            /// and a max in the tens is the regime itself.
            pub const Weights = struct { mean_abs: f32, max_abs: f32 };

            pub fn weightStats(self: *const Ch.Model) Weights {
                if (self.kernels.items.len == 0) return .{ .mean_abs = 0, .max_abs = 0 };
                var acc: f64 = 0;
                var mx: f32 = 0;
                for (self.kernels.items) |*k| {
                    acc += @abs(k.p[W]);
                    mx = @max(mx, @abs(k.p[W]));
                }
                return .{ .mean_abs = @floatCast(acc / @as(f64, @floatFromInt(self.kernels.items.len))), .max_abs = mx };
            }

            pub const Drift = struct { mean: f32, max: f32, out_of_region: u32 };

            pub fn driftOf(self: *const Ch.Model) Drift {
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
            pub fn densityIn(self: *const Ch.Model, comptime pred: fn (TruthParams, [3]f32) bool, volume: f32) f32 {
                return @as(f32, @floatFromInt(self.countIn(pred))) / volume;
            }

            pub fn countIn(self: *const Ch.Model, comptime pred: fn (TruthParams, [3]f32) bool) u32 {
                var n: u32 = 0;
                for (self.kernels.items) |*k| {
                    if (pred(self.opts.truth, .{ k.p[MU], k.p[MU + 1], k.p[MU + 2] })) n += 1;
                }
                return n;
            }
        };

        // ── MARL-2: the residual hierarchy ────────────────────────────────────

        /// A banked child, and where it came from. The source region matters: a
        /// donor set's geometry is only right for a recipient whose structure sits
        /// at a similar angle, and on a moving shell that means a NEARBY region.
        /// The first version picked the most recent retirement — a temporal
        /// correspondence, which a move does provide — and it transplanted
        /// pancakes at the wrong orientation, adding more kernels than it saved.
        pub const Donor = struct { from: u32, kernels: std.ArrayListUnmanaged(Ch.Kernel) };

        /// What the scheduler knows about one refined region. Nothing here is new
        /// physics — every field is a quantity an earlier phase already measured
        /// and understood, which is the condition Christian set.
        pub const RegionSched = struct {
            /// Unresolved representation pressure: an EWMA of the CHILD's
            /// post-update residual here. Seeded at refinement from the parent's
            /// own pressure, or a region that has never been served has a need of
            /// zero, scores zero, is never served, and the scheduler deadlocks on
            /// its first step.
            need: f32 = 0,
            /// Exemplars served, child kernels born here, and child gradient
            /// applications spent here.
            routed: u64 = 0,
            kernels: u32 = 0,
            updates: u64 = 0,
            /// Exemplar index when this region was last served.
            last_served: u64 = 0,
            /// MARL-7: an EWMA of |y − parent(x)| over the exemplars routed here,
            /// and what it was when the region was refined. The child was created
            /// to absorb the parent's error at the size it then had; if that error
            /// GROWS well past it, the parent has stopped being a valid coarse
            /// level and no amount of residual will fix that — the residual is
            /// what is being asked to do the parent's job.
            parent_error: f32 = 0,
            parent_error_at_refine: f32 = 0,
            /// A DECAYING MAX of the same error. The mean is the wrong statistic
            /// and the reason is the campaign's recurring one: a region is a sixth
            /// of the domain across and the structure that leaves it is a
            /// fortieth of the domain thick, so a 0.9-amplitude error over a fifth
            /// of a region's volume averages down to a factor barely over three.
            /// The question is not whether the parent is wrong ON AVERAGE here; it
            /// is whether it is badly wrong ANYWHERE here.
            parent_peak: f32 = 0,
            parent_peak_at_refine: f32 = 0,
            since_refined: u32 = 0,
            /// The learning-efficiency window: need at the window's start, work
            /// spent since, and the accumulated efficiency. MEASURED, and nothing
            /// schedules from it — Christian's instruction, and the right one:
            /// until it is characterised, scheduling from it would be scheduling
            /// from a quantity nobody has read.
            win_need: f32 = 0,
            win_updates: u64 = 0,
            win_n: u32 = 0,
            eff_sum: f64 = 0,
            eff_n: u32 = 0,

            pub fn sufficiency(self: *const Ch.RegionSched) f32 {
                return @as(f32, @floatFromInt(self.updates)) / @as(f32, @floatFromInt(@max(1, self.kernels)));
            }

            pub fn efficiency(self: *const Ch.RegionSched) f32 {
                if (self.eff_n == 0) return 0;
                return @floatCast(self.eff_sum / @as(f64, @floatFromInt(self.eff_n)));
            }
        };

        /// Two levels, and the prediction is their SUM:
        ///
        ///     f(x) ≈ parent(x) + Δchild(x)
        ///
        /// The child never sees the target. It sees `y − parent(x)` with the
        /// parent HELD, so what it holds has a precise meaning: the information
        /// the level above could not represent. That is the whole of the design,
        /// and the freezing is what makes the meaning true — a parent that went on
        /// learning in a refined region would be a parent the child is chasing.
        ///
        /// Standalone on purpose, and two levels on purpose. No tree, no Loam
        /// storage, no recursion.
        pub const Hierarchy = struct {
            gpa: std.mem.Allocator,
            parent: Ch.Model,
            child: Ch.Model,
            popts: PressureOptions,
            /// Per parent region.
            refined: []bool,
            covered_events: []u32,
            post_sum: []f64,
            /// The exemplar stream, keyed exactly as a flat `Model`'s is, so a
            /// hierarchy and a flat learner at the same seed see THE SAME
            /// exemplars in the same order. Any comparison between them that did
            /// not is a comparison of two different experiments.
            stream: rng.Stream,
            seen: u64 = 0,
            routed: u64 = 0,
            /// Of the exemplars routed to the child, how many landed in the shell
            /// band. THE DIAGNOSIS: a birth can only happen where an exemplar is,
            /// so capacity concentration is bounded by EVIDENCE concentration, and
            /// this is the evidence's. If it matches the band's share of the
            /// refined volume, the child's stream is uniform and no birth rule
            /// whatsoever can concentrate capacity above it.
            routed_in_band: u64 = 0,
            /// Exemplars that landed in a refined region at all — the pool routing
            /// selects from. `routed / offered` is the router's duty cycle.
            offered: u64 = 0,
            offered_in_band: u64 = 0,
            refined_count: u32 = 0,
            /// The routing coin, keyed apart from the exemplar stream so that
            /// biasing the stream does not change WHICH exemplars arrive — only
            /// which of them the child is shown. Two routing settings therefore
            /// see the same world.
            route_stream: rng.Stream,
            /// Per parent region, and only for the refined ones.
            sched: []Ch.RegionSched,
            /// MARL-6's epoch marks. Diagnostics only — nothing reads them to
            /// decide anything, which is the condition on tagging at all.
            child_at_drift: usize = 0,
            parent_at_drift: usize = 0,
            events_at_drift: u64 = 0,
            seen_at_drift: u64 = 0,
            updates_at_drift: []u32 = &.{},
            /// MARL-8: banked donor sets, each one region's child expressed
            /// RELATIVE to its region's origin, so it can be instantiated
            /// anywhere. A set rather than loose kernels, because the relative
            /// arrangement is most of what was learned.
            pool: std.ArrayListUnmanaged(Ch.Donor) = .{},
            transplanted: usize = 0,
            transplant_events: u32 = 0,
            /// Indices of the child kernels that arrived by transplant, for the
            /// adoption measurement. Diagnostics only.
            transplant_marks: std.ArrayListUnmanaged(u32) = .{},
            /// MARL-7 bookkeeping: regions retired, and the child kernels that
            /// went with them.
            unrefined_count: u32 = 0,
            unrefined_on_departed: u32 = 0,
            child_retired: usize = 0,
            rerefined_count: u32 = 0,
            ever_refined: []bool = &.{},
            /// Running mean of the routing score, so a score of any scale
            /// normalises to the target duty. An EWMA rather than a true mean
            /// because the scores move as the model learns, and a normaliser
            /// averaged over the whole run would hold the duty at what the score
            /// used to be.
            score_mean: f32 = 1,

            pub fn init(gpa: std.mem.Allocator, opts: Options, popts: PressureOptions) !Ch.Hierarchy {
                var parent = try Ch.Model.init(gpa, opts);
                errdefer parent.deinit();
                var copts = opts;
                copts.regions = opts.regions * popts.refine;
                copts.birth_rule = popts.child_birth;
                var child = try Ch.Model.init(gpa, copts);
                errdefer child.deinit();
                const n = parent.regions.len;
                const refined = try gpa.alloc(bool, n);
                errdefer gpa.free(refined);
                @memset(refined, false);
                const ce = try gpa.alloc(u32, n);
                errdefer gpa.free(ce);
                @memset(ce, 0);
                const ps = try gpa.alloc(f64, n);
                errdefer gpa.free(ps);
                @memset(ps, 0);
                const sch = try gpa.alloc(Ch.RegionSched, n);
                errdefer gpa.free(sch);
                for (sch) |*e| e.* = .{};
                const ever = try gpa.alloc(bool, n);
                errdefer gpa.free(ever);
                @memset(ever, false);
                return .{
                    .gpa = gpa,
                    .parent = parent,
                    .child = child,
                    .popts = popts,
                    .refined = refined,
                    .covered_events = ce,
                    .post_sum = ps,
                    .stream = rng.Stream.region(opts.seed, 0x4D41_524C, 0), // "MARL", the flat model's key
                    .route_stream = rng.Stream.region(opts.seed, 0x524F_5554, 0), // "ROUT"
                    .sched = sch,
                    .ever_refined = ever,
                };
            }

            pub fn deinit(self: *Ch.Hierarchy) void {
                self.parent.deinit();
                self.child.deinit();
                self.gpa.free(self.refined);
                self.gpa.free(self.covered_events);
                self.gpa.free(self.post_sum);
                self.gpa.free(self.sched);
                if (self.updates_at_drift.len > 0) self.gpa.free(self.updates_at_drift);
                self.gpa.free(self.ever_refined);
                for (self.pool.items) |*d| d.kernels.deinit(self.gpa);
                self.pool.deinit(self.gpa);
                self.transplant_marks.deinit(self.gpa);
            }

            /// The origin of a parent region, in domain coordinates.
            fn regionOrigin(self: *const Ch.Hierarchy, r: u32) [3]f32 {
                const rr = self.parent.opts.regions;
                const c = [3]u32{ r % rr, (r / rr) % rr, r / (rr * rr) };
                const h = self.parent.h;
                return .{ @as(f32, @floatFromInt(c[0])) * h, @as(f32, @floatFromInt(c[1])) * h, @as(f32, @floatFromInt(c[2])) * h };
            }

            /// Bank a retiring region's child, relative to its own origin.
            fn bank(self: *Ch.Hierarchy, r: u32) !void {
                const o = self.regionOrigin(r);
                var set = std.ArrayListUnmanaged(Ch.Kernel){};
                errdefer set.deinit(self.gpa);
                for (self.child.kernels.items) |k| {
                    const mu = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    if (self.parent.regionOf(mu) != r) continue;
                    var rel = k;
                    inline for (0..3) |a| rel.p[MU + a] -= o[a];
                    rel.p[W] = 0; // the geometry is carried; the weight is not
                    rel.m1 = [_]f32{0} ** Ch.PARAMS;
                    rel.m2 = [_]f32{0} ** Ch.PARAMS;
                    rel.t = 0;
                    rel.updates = 0;
                    rel.frozen = false;
                    try set.append(self.gpa, rel);
                }
                if (set.items.len == 0) {
                    set.deinit(self.gpa);
                    return;
                }
                try self.pool.append(self.gpa, .{ .from = r, .kernels = set });
            }

            /// Instantiate a banked set into a refining region, choosing the
            /// NEAREST donor. Geometry is what is being carried, and on a moving
            /// shell the piece of structure a region holds is only similar to the
            /// piece a nearby region held — orientation is local. Picking by
            /// recency instead transplanted pancakes at the wrong angle, and added
            /// more kernels than it suppressed.
            fn transplant(self: *Ch.Hierarchy, r: u32) !void {
                if (self.pool.items.len == 0) return;
                const want = self.regionOrigin(r);
                var best: usize = 0;
                var best_d: f32 = std.math.inf(f32);
                for (self.pool.items, 0..) |*d, i| {
                    const o = self.regionOrigin(d.from);
                    const dd = (o[0] - want[0]) * (o[0] - want[0]) + (o[1] - want[1]) * (o[1] - want[1]) + (o[2] - want[2]) * (o[2] - want[2]);
                    if (dd < best_d) {
                        best_d = dd;
                        best = i;
                    }
                }
                const donor = self.pool.swapRemove(best);
                var set = donor.kernels;
                defer set.deinit(self.gpa);
                const o = self.regionOrigin(r);
                for (set.items) |k| {
                    var nk = k;
                    inline for (0..3) |a| nk.p[MU + a] += o[a];
                    const mu = [3]f32{ nk.p[MU], nk.p[MU + 1], nk.p[MU + 2] };
                    // A donor set can spill past a region's face; anything that
                    // lands outside the child's domain is dropped rather than
                    // clamped, because a clamped kernel is a kernel in a place
                    // nothing chose for it.
                    if (mu[0] < 0 or mu[0] > 1 or mu[1] < 0 or mu[1] > 1 or mu[2] < 0 or mu[2] > 1) continue;
                    const owner = self.child.regionOf(mu);
                    nk.owner = owner;
                    nk.mu0 = mu;
                    nk.born_at = self.seen;
                    const ki: u32 = @intCast(self.child.kernels.items.len);
                    try self.child.kernels.append(self.child.gpa, nk);
                    self.child.clamp(&self.child.kernels.items[ki]);
                    try self.child.regions[owner].own.append(self.child.gpa, ki);
                    if (nk.reach > self.child.regions[owner].max_reach) self.child.regions[owner].max_reach = nk.reach;
                    try self.transplant_marks.append(self.gpa, ki);
                    self.transplanted += 1;
                }
                self.transplant_events += 1;
            }

            /// Of the kernels that arrived by transplant, the share whose weight
            /// has risen off zero into real use. A transplant that stays at zero
            /// is a no-op dressed as a saving.
            pub fn adoption(self: *const Ch.Hierarchy) f32 {
                if (self.transplant_marks.items.len == 0) return 0;
                const bar = self.child.weightStats().mean_abs * 0.1;
                var used: u32 = 0;
                var alive: u32 = 0;
                for (self.transplant_marks.items) |ki| {
                    if (ki >= self.child.kernels.items.len) continue; // compacted away
                    alive += 1;
                    if (@abs(self.child.kernels.items[ki].p[W]) > bar) used += 1;
                }
                if (alive == 0) return 0;
                return @as(f32, @floatFromInt(used)) / @as(f32, @floatFromInt(alive));
            }

            /// Retire a region's child level and hand the region back to the
            /// parent. The two halves are ONE act: the child's kernels go and the
            /// parent's are unfrozen in the same breath, because the correction
            /// and the thing it corrects are only removable together.
            ///
            /// Safe on MARL-6R's analysis: under-basis-density is the catastrophe,
            /// and this removes a LEVEL while leaving the parent's density where
            /// it was. There is no sparse child left behind — there is no child.
            fn unrefine(self: *Ch.Hierarchy, gpa: std.mem.Allocator, r: u32) !void {
                const dead = try gpa.alloc(bool, self.child.kernels.items.len);
                defer gpa.free(dead);
                var n: usize = 0;
                for (self.child.kernels.items, dead) |*k, *d| {
                    const mu = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    d.* = self.parent.regionOf(mu) == r;
                    if (d.*) n += 1;
                }
                if (self.popts.recycle) try self.bank(r);
                try self.child.compact(dead);
                self.parent.unfreezeRegion(r);
                self.refined[r] = false;
                // The pressure statistic starts again, or the region re-refines on
                // the evidence that had it refined before.
                self.covered_events[r] = 0;
                self.post_sum[r] = 0;
                self.sched[r] = .{};
                self.unrefined_count += 1;
                self.child_retired += n;
                if (!Truth.inShell(self.parent.opts.truth, self.regionCentre(r))) self.unrefined_on_departed += 1;
            }

            fn regionCentre(self: *const Ch.Hierarchy, r: u32) [3]f32 {
                const rr = self.parent.opts.regions;
                const c = [3]u32{ r % rr, (r / rr) % rr, r / (rr * rr) };
                const h = self.parent.h;
                return .{ (@as(f32, @floatFromInt(c[0])) + 0.5) * h, (@as(f32, @floatFromInt(c[1])) + 0.5) * h, (@as(f32, @floatFromInt(c[2])) + 0.5) * h };
            }

            /// The routing score for a region, before normalisation.
            fn scoreOf(self: *const Ch.Hierarchy, r: u32, residual: f32) f32 {
                const e = &self.sched[r];
                return switch (self.popts.sched) {
                    .off => self.popts.route_floor + self.popts.route_gain * @abs(residual),
                    .need => e.need,
                    .need_lag => e.need * (1 + @as(f32, @floatFromInt(self.seen - e.last_served)) / self.popts.lag_tau),
                    .need_lag_suff => e.need *
                        (1 + @as(f32, @floatFromInt(self.seen - e.last_served)) / self.popts.lag_tau) /
                        (1 + e.sufficiency() / self.popts.suff_ref),
                    .hybrid => (self.popts.route_floor + self.popts.route_gain * @abs(residual)) *
                        (1 + @as(f32, @floatFromInt(self.seen - e.last_served)) / self.popts.lag_tau),
                };
            }

            /// The sum. The child contributes exactly zero where it has no
            /// kernels, so an unrefined domain reads as the parent alone — not
            /// approximately, the cutoff makes it exact.
            pub fn predict(self: *Ch.Hierarchy, q: [3]f32) !Ch.Vec {
                const a = try self.parent.predict(q);
                const b = try self.child.predict(q);
                var out: Ch.Vec = undefined;
                inline for (0..C) |c| out[c] = a[c] + b[c];
                return out;
            }

            pub fn pressureOf(self: *const Ch.Hierarchy, region: u32) f32 {
                if (self.covered_events[region] == 0) return 0;
                return @floatCast(self.post_sum[region] / @as(f64, @floatFromInt(self.covered_events[region])));
            }

            pub fn observeOne(self: *Ch.Hierarchy) !void {
                const x = [3]f32{ self.stream.unit(), self.stream.unit(), self.stream.unit() };
                const y = Ch.vecOf(truthOf(self.parent.opts.truth, x));
                const r = self.parent.regionOf(x);
                self.seen += 1;
                if (self.refined[r]) {
                    const in_band = Truth.inShell(self.parent.opts.truth, x);
                    self.offered += 1;
                    if (in_band) self.offered_in_band += 1;
                    // The residual has to be known to decide, which means the
                    // parent's prediction is paid for whether or not the exemplar
                    // is routed. That is the router's honest cost and it is what
                    // `work` will show.
                    const held = try self.parent.predict(x);
                    var delta: Ch.Vec = undefined;
                    inline for (0..C) |c| delta[c] = y[c] - held[c];
                    const score = self.scoreOf(r, Ch.magOf(delta));
                    // One normaliser for every mode, so the arms differ in WHICH
                    // exemplars they route and not in how many.
                    self.score_mean += 0.001 * (score - self.score_mean);
                    const p = if (self.popts.route_duty > 0)
                        @min(1, self.popts.route_duty * score / @max(1e-6, self.score_mean))
                    else
                        @min(1, score);
                    if (self.route_stream.unit() >= p) return;
                    // Counted HERE, immediately before the child sees it, and not
                    // at the top of the branch: the number that matters is the
                    // stream the child actually learns from, so that any filter on
                    // what reaches it shows up in the measurement. Placed earlier,
                    // a routing change was invisible and G20 (c) went on reporting
                    // a uniform stream that no longer was one.
                    self.routed += 1;
                    if (in_band) self.routed_in_band += 1;
                    const before = self.child.stats.updates;
                    const kn = self.child.kernels.items.len;
                    const cev = try self.child.observe(x, delta);
                    const spent = self.child.stats.updates - before;

                    const e = &self.sched[r];
                    e.need += 0.01 * (Ch.magOf(cev.post_residual) - e.need);
                    e.routed += 1;
                    e.updates += spent;
                    e.kernels += @intCast(self.child.kernels.items.len - kn);
                    e.last_served = self.seen;
                    const perr = Ch.magOf(delta);
                    e.parent_error += 0.02 * (perr - e.parent_error);
                    e.parent_peak = @max(e.parent_peak * 0.9995, perr);
                    e.since_refined +|= 1;
                    // The baseline is MEASURED, not inherited. What the child was
                    // created to absorb is the parent's error once the region has
                    // settled under refinement — and because the parent is frozen
                    // there, that number does not move again unless the world
                    // does. Taking it from the pressure statistic instead was
                    // wrong by an order of magnitude: pressure is a POST-update
                    // residual (~0.008) and this is the raw error (~0.08), so the
                    // trigger compared two different quantities and never fired.
                    if (e.since_refined == self.popts.unrefine_after) {
                        e.parent_error_at_refine = @max(1e-4, e.parent_error);
                        e.parent_peak_at_refine = @max(1e-4, e.parent_peak);
                    } else if (self.popts.unrefine > 0 and e.since_refined > self.popts.unrefine_after and
                        e.parent_peak > e.parent_peak_at_refine * self.popts.unrefine)
                    {
                        try self.unrefine(self.gpa, r);
                        return;
                    }
                    // Learning efficiency, measured over a moving window: how much
                    // unresolved residual a unit of learning work removed here.
                    e.win_updates += spent;
                    e.win_n += 1;
                    if (e.win_n >= 200) {
                        if (e.win_updates > 0) {
                            e.eff_sum += @as(f64, e.win_need - e.need) / @as(f64, @floatFromInt(e.win_updates));
                            e.eff_n += 1;
                        }
                        e.win_need = e.need;
                        e.win_updates = 0;
                        e.win_n = 0;
                    }
                    return;
                }
                const ev = try self.parent.observe(x, y);
                // Every learning event, NOT only the ones where coverage was
                // already satisfied.
                //
                // Filtering to covered events was the first implementation of
                // Christian's principle — refine where the basis said it had the
                // ground covered and was still wrong — and it was the WRONG
                // implementation, by a wide margin. Measured at four settings of
                // `min_events`, precision with the filter was 0.507, 0.600, 0.679,
                // 0.963; without it, 0.919, 0.923, 1.000, 1.000. Dropping the
                // events where a birth happened removes exactly the events the
                // model handled well, which biases the mean upward everywhere and
                // unevenly: a structured region births more, so it reaches
                // `min_events` later and on a differently-selected sample than a
                // smooth one.
                //
                // The principle survives its implementation. What distinguishes
                // "not learned yet" from "cannot be represented" is that this is
                // the POST-UPDATE residual — what deformation could not remove
                // with the kernels it had — and that is the whole of it. The
                // coverage filter was a second, redundant attempt at the same
                // distinction, and it cost precision to make it twice.
                if (!ev.learned) return;
                self.covered_events[r] += 1;
                self.post_sum[r] += Ch.magOf(ev.post_residual);
                if (self.covered_events[r] >= self.popts.min_events and
                    self.pressureOf(r) > self.popts.threshold)
                {
                    self.refined[r] = true;
                    self.refined_count += 1;
                    self.parent.freezeRegion(r);
                    // Seeded from the parent's own pressure: a region whose need
                    // started at zero would score zero, never be served, and never
                    // learn what its need was.
                    self.sched[r].need = self.pressureOf(r);
                    self.sched[r].win_need = self.sched[r].need;
                    self.sched[r].last_served = self.seen;
                    if (self.ever_refined[r]) self.rerefined_count += 1;
                    self.ever_refined[r] = true;
                    if (self.popts.recycle) try self.transplant(r);
                }
            }

            pub fn stream_n(self: *Ch.Hierarchy, n: u64) !void {
                var i: u64 = 0;
                while (i < n) : (i += 1) try self.observeOne();
            }

            pub fn rms(self: *Ch.Hierarchy, pts: []const [3]f32, targets: []const Ch.Vec, max_abs: ?*f32) !f32 {
                var acc: f64 = 0;
                var mx: f32 = 0;
                for (pts, targets) |p, t| {
                    const yh = try self.predict(p);
                    inline for (0..C) |c| {
                        const e = yh[c] - t[c];
                        acc += @as(f64, e) * @as(f64, e);
                        mx = @max(mx, @abs(e));
                    }
                }
                if (max_abs) |m| m.* = mx;
                return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pts.len * C))));
            }

            /// The parent alone — what the model would score with the child
            /// discarded. The difference between this and `rms` is the child's
            /// contribution, stated rather than inferred.
            pub fn parentRms(self: *Ch.Hierarchy, pts: []const [3]f32, targets: []const Ch.Vec) !f32 {
                var acc: f64 = 0;
                for (pts, targets) |p, t| {
                    const yh = try self.parent.predict(p);
                    inline for (0..C) |c| {
                        const e = yh[c] - t[c];
                        acc += @as(f64, e) * @as(f64, e);
                    }
                }
                return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pts.len * C))));
            }

            /// Whether a parent region's cube touches the target's shell band —
            /// the ground truth a refinement decision is scored against.
            pub fn regionMeetsShell(self: *const Ch.Hierarchy, region: u32) bool {
                const tp = self.parent.opts.truth;
                const h = self.parent.h;
                const rr = self.parent.opts.regions;
                const c = [3]u32{ region % rr, (region / rr) % rr, region / (rr * rr) };
                const N: u32 = 9;
                var k: u32 = 0;
                while (k <= N) : (k += 1) {
                    var j: u32 = 0;
                    while (j <= N) : (j += 1) {
                        var i: u32 = 0;
                        while (i <= N) : (i += 1) {
                            const p = [3]f32{
                                (@as(f32, @floatFromInt(c[0])) + @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(N))) * h,
                                (@as(f32, @floatFromInt(c[1])) + @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(N))) * h,
                                (@as(f32, @floatFromInt(c[2])) + @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(N))) * h,
                            };
                            if (Truth.inShell(tp, p)) return true;
                        }
                    }
                }
                return false;
            }

            /// Of the regions refinement opened, the share that actually touch
            /// structure the parent could not resolve. A pressure signal that
            /// fires on the smooth swell is buying capacity for something ordinary
            /// deformation had in hand, which is the campaign's §5 failure —
            /// noise mistaken for complexity — wearing a different hat.
            /// MARL-6: move the world. Only the target changes — no thawing, no
            /// reparenting, no forgetting. The refined set, the frozen parents and
            /// every kernel stay exactly as the old world left them, which is the
            /// whole point: the premise under test is that a frozen coarse level
            /// plus a residual child survives its function moving.
            ///
            /// Kernels are tagged by epoch for DIAGNOSTICS ONLY, and the tag costs
            /// nothing to keep: the kernel arrays are append-only, so everything
            /// below `child_at_drift` was born before the world moved. Nothing
            /// reads the tag to decide anything.
            pub fn drift(self: *Ch.Hierarchy, gpa: std.mem.Allocator, tp: TruthParams) !void {
                self.parent.opts.truth = tp;
                self.child.opts.truth = tp;
                self.child_at_drift = self.child.kernels.items.len;
                self.parent_at_drift = self.parent.kernels.items.len;
                self.events_at_drift = self.parent.stats.events + self.child.stats.events;
                self.seen_at_drift = self.seen;
                if (self.updates_at_drift.len > 0) gpa.free(self.updates_at_drift);
                self.updates_at_drift = try gpa.alloc(u32, self.child_at_drift);
                for (self.child.kernels.items[0..self.child_at_drift], self.updates_at_drift) |*k, *u| u.* = k.updates;
            }

            /// The magnitude of what the CHILD is holding, on its own. The
            /// sharpest detector of the semantic failure this phase is looking
            /// for: a child holding unresolved detail of the current parent is
            /// small, and a child holding `current target − historical parent`
            /// has to carry the coarse structure the frozen parent no longer
            /// explains.
            pub fn childRms(self: *Ch.Hierarchy, pts: []const [3]f32) !f32 {
                var acc: f64 = 0;
                for (pts) |p| {
                    const yh = try self.child.predict(p);
                    inline for (0..C) |c| acc += @as(f64, yh[c]) * @as(f64, yh[c]);
                }
                return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pts.len * C))));
            }

            /// Of the child kernels that existed when the world moved, how many
            /// are still outside the band the target now has — and how many have
            /// taken any real gradient since.
            pub const Stranded = struct {
                at_drift: usize,
                outside_current: usize,
                still_active: usize,
                /// Mean |w| of the pre-move kernels that are now outside the
                /// current band, and of those inside it. THE QUESTION EROSION
                /// TURNS ON: if obsolete capacity shrinks its own weight, death is
                /// a matter of noticing; if it does not, death needs a signal the
                /// model does not currently produce.
                w_obsolete: f32,
                w_relevant: f32,
                /// And the same for kernels born since the move, as the control.
                w_new: f32,
            };

            pub fn strandedOf(self: *const Ch.Hierarchy) Stranded {
                var outside: usize = 0;
                var active: usize = 0;
                var w_out: f64 = 0;
                var w_in: f64 = 0;
                var n_in: usize = 0;
                for (self.child.kernels.items[0..self.child_at_drift], self.updates_at_drift) |*k, was| {
                    const mu = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    if (Truth.inShell(self.parent.opts.truth, mu)) {
                        w_in += @abs(k.p[W]);
                        n_in += 1;
                    } else {
                        w_out += @abs(k.p[W]);
                        outside += 1;
                    }
                    if (k.updates > was + 10) active += 1;
                }
                var w_new: f64 = 0;
                const n_new = self.child.kernels.items.len - self.child_at_drift;
                for (self.child.kernels.items[self.child_at_drift..]) |*k| w_new += @abs(k.p[W]);
                return .{
                    .at_drift = self.child_at_drift,
                    .outside_current = outside,
                    .still_active = active,
                    .w_obsolete = if (outside > 0) @floatCast(w_out / @as(f64, @floatFromInt(outside))) else 0,
                    .w_relevant = if (n_in > 0) @floatCast(w_in / @as(f64, @floatFromInt(n_in))) else 0,
                    .w_new = if (n_new > 0) @floatCast(w_new / @as(f64, @floatFromInt(n_new))) else 0,
                };
            }

            /// THE ABLATION THAT DECIDES WHETHER DEATH IS EVEN POSSIBLE: silence
            /// every pre-move child kernel now outside the current band, and see
            /// what the prediction does. If those kernels are obsolete, removing
            /// them costs nothing and erosion is a matter of noticing. If the
            /// prediction gets WORSE, they are load-bearing — they are cancelling
            /// the frozen parent's stale contribution, and deleting a correction
            /// while the thing it corrects remains is not a repair.
            ///
            /// Reversible, and reversed by the caller: this is a measurement, not
            /// a mechanism.
            pub fn silenceObsolete(self: *Ch.Hierarchy, saved: []f32) usize {
                var n: usize = 0;
                for (self.child.kernels.items[0..self.child_at_drift]) |*k| {
                    const mu = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    if (Truth.inShell(self.parent.opts.truth, mu)) continue;
                    saved[n] = k.p[W];
                    k.p[W] = 0;
                    n += 1;
                }
                return n;
            }

            pub fn restoreObsolete(self: *Ch.Hierarchy, saved: []const f32) void {
                var n: usize = 0;
                for (self.child.kernels.items[0..self.child_at_drift]) |*k| {
                    const mu = [3]f32{ k.p[MU], k.p[MU + 1], k.p[MU + 2] };
                    if (Truth.inShell(self.parent.opts.truth, mu)) continue;
                    k.p[W] = saved[n];
                    n += 1;
                }
            }

            /// The child's shell-band density over its density across the cells it
            /// occupies at all. One definition, used by the gate and the seedbed
            /// alike, because two spellings of a headline number is how a campaign
            /// ends up arguing with itself.
            pub fn childConcentration(self: *const Ch.Hierarchy) f64 {
                const n: f64 = @floatFromInt(self.child.opts.regions);
                const cell = 1 / (n * n * n);
                const occ = @as(f64, @floatFromInt(self.child.occupiedRegions())) * cell;
                if (occ <= 0 or self.child.kernels.items.len == 0) return 0;
                const density = @as(f64, @floatFromInt(self.child.kernels.items.len)) / occ;
                const band_v = volumeOf(self.parent.opts.truth, Truth.inShell);
                const band_d = @as(f64, @floatFromInt(self.child.countIn(Truth.inShell))) / @as(f64, band_v);
                return band_d / density;
            }

            /// The band's share of the refined volume — what a uniform stream
            /// would deliver, and therefore the concentration ceiling any birth
            /// rule is working under.
            pub fn bandShareOfRefined(self: *const Ch.Hierarchy) f32 {
                const N: u32 = 120_000;
                var st = rng.Stream.region(0x5348_4152, 0, 0); // "SHAR"
                var refined: u32 = 0;
                var in_band: u32 = 0;
                var i: u32 = 0;
                while (i < N) : (i += 1) {
                    const p = [3]f32{ st.unit(), st.unit(), st.unit() };
                    if (!self.refined[self.parent.regionOf(p)]) continue;
                    refined += 1;
                    if (Truth.inShell(self.parent.opts.truth, p)) in_band += 1;
                }
                if (refined == 0) return 0;
                return @as(f32, @floatFromInt(in_band)) / @as(f32, @floatFromInt(refined));
            }

            pub const Precision = struct { refined: u32, on_shell: u32, false_positive: u32 };

            pub fn precision(self: *const Ch.Hierarchy) Precision {
                var on: u32 = 0;
                var off: u32 = 0;
                for (self.refined, 0..) |r, i| {
                    if (!r) continue;
                    if (self.regionMeetsShell(@intCast(i))) on += 1 else off += 1;
                }
                return .{ .refined = on + off, .on_shell = on, .false_positive = off };
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
        pub fn gradOne(k: *const Ch.Kernel, q: [3]f32, e: Ch.Vec, grad: *[Ch.PARAMS]f32) bool {
            const s = k.shape();
            const m = mahal(s, q);
            if (m.r2 > CUTOFF) return false;
            const g = fmath.expf(-0.5 * m.r2);
            if (g < 1e-7) return false;
            @memset(grad, 0);
            const w = k.weightsConst();
            // One weight gradient per channel; the geometry's is the sum of
            // each channel's error against its own weight, which is `rbf`'s
            // `ew` term.
            inline for (0..C) |c| grad[W + c] = 2 * e[c] * g;
            var ew: f32 = e[0] * w[0];
            inline for (1..C) |c| ew += e[c] * w[c];
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

        /// A held-out probe set: points from their own stream, never
        /// observed. The truth (§8) is SCALAR, so channel 0 carries it and
        /// the rest are zero — which at C = 1 is the campaign's probe set
        /// exactly, and at C > 1 is a set the synthetic truth has nothing
        /// to say about. Anything wanting a real multi-channel target
        /// brings its own, as `src/marble.zig` does.
        pub const Probes = struct { p: [][3]f32, y: []Ch.Vec };

        pub fn probesOf(gpa: std.mem.Allocator, tp: TruthParams, seed: u64, n: usize) !Ch.Probes {
            var st = rng.Stream.region(seed, 0x5052_4F42, 0); // "PROB"
            const p = try gpa.alloc([3]f32, n);
            errdefer gpa.free(p);
            const y = try gpa.alloc(Ch.Vec, n);
            errdefer gpa.free(y);
            for (p, y) |*pt, *ty| {
                pt.* = .{ st.unit(), st.unit(), st.unit() };
                ty.* = [_]f32{0} ** C;
                ty.*[0] = truthOf(tp, pt.*);
            }
            return .{ .p = p, .y = y };
        }

        pub fn probes(gpa: std.mem.Allocator, seed: u64, n: usize) !Ch.Probes {
            return Ch.probesOf(gpa, .{}, seed, n);
        }

        /// One Adam step on one kernel, against its own step count.
        pub fn adam(k: *Ch.Kernel, grad: *const [Ch.PARAMS]f32, rate: f32) void {
            k.t += 1;
            const t: f32 = @floatFromInt(k.t);
            const c1 = 1 - std.math.pow(f32, B1, t);
            const c2 = 1 - std.math.pow(f32, B2, t);
            inline for (0..Ch.PARAMS) |i| {
                k.m1[i] = B1 * k.m1[i] + (1 - B1) * grad[i];
                k.m2[i] = B2 * k.m2[i] + (1 - B2) * grad[i] * grad[i];
                k.p[i] -= rate * (k.m1[i] / c1) / (@sqrt(k.m2[i] / c2) + 1e-8);
            }
        }
    };
}

// ── The campaign's instantiation ──────────────────────────────────────
//
// One channel, which is what every gate from G17 to G29 measures and what
// `marl-run` drives. These aliases are why widening the kernel did not
// touch a single call site: `marl.Model` still names a type, it just names
// `Marl(1).Model` now.

pub const Scalar = Marl(1);
pub const PARAMS = Scalar.PARAMS;
pub const Kernel = Scalar.Kernel;
pub const Region = Scalar.Region;
pub const Event = Scalar.Event;
pub const Stats = Scalar.Stats;
pub const Model = Scalar.Model;
pub const Donor = Scalar.Donor;
pub const RegionSched = Scalar.RegionSched;
pub const Hierarchy = Scalar.Hierarchy;
pub const gradOne = Scalar.gradOne;
pub const adam = Scalar.adam;
pub const Probes = Scalar.Probes;
pub const probesOf = Scalar.probesOf;
pub const probes = Scalar.probes;

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
                if (!gradOne(kk, p, .{e}, &g)) continue;
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
    for (pr.p, before) |p, *b| b.* = (try m.predict(p))[0];

    const x = [3]f32{ 0.30, 0.42, 0.46 };
    const ev = try m.observe(x, .{truth(x)});
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
        const a = (try m.predict(p))[0];
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

    const V_SHELL = volumeOf(m.opts.truth, Truth.inShell);
    const V_QUIET = volumeOf(m.opts.truth, Truth.inQuiet);
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
        if (Truth.inQuiet(.{}, p)) {
            quiet += 1;
            try testing.expectEqual(@as(f32, 0), t);
        }
        if (Truth.inShell(.{}, p)) {
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

// ── MARL-1's gates ────────────────────────────────────────────────────
//
// Christian's ordering: capacity-controlled birth vs deformation; fixed
// coverage against variable target complexity; the responsibility-radius
// sweep; the under-birth divergence regime; deliberate saturation. Every
// threshold is in thresholds.zig and came out of tools/marl1_predict.py
// before these ran.

test "G18 (a) at IDENTICAL capacity, deformation buys the predicted gain over birth alone" {
    // Christian's design, and the reason it is not the A-versus-C
    // comparison: arm C ends with 12% more kernels than A, so A/C measures
    // deformation AND the capacity deformation went on to discover. Arm B'
    // takes A's frozen topology and descends with births off, so K is
    // identical by construction and only the geometry and the weights
    // differ.
    //
    // The horizon is named because the ratio compounds: arm A plateaus at
    // RMS ≈ 0.051 within about forty thousand exemplars and never improves
    // again, while B' keeps going, so the ratio is 1.17 at 40 000 and 3.00
    // at 400 000. A floor on a growing quantity needs its N stated.
    //
    // MUTATION: B' with both rates zero — it then IS arm A, the ratio is
    // exactly 1, and the gate fails. Checked below rather than by hand,
    // because it costs one more run of a model that births nothing.
    const gpa = testing.allocator;
    const pr = try probes(gpa, 0xB0B, 4096);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var a = try Model.init(gpa, .{ .rate_w = 0, .rate_geom = 0 });
    defer a.deinit();
    try a.stream_n(thresholds.MARL1_DESCENT_N);
    const rms_a = try a.rms(pr.p, pr.y, null);

    var b = try Model.init(gpa, .{ .births = false });
    defer b.deinit();
    try b.reseedFrom(&a);
    // The reseed carries the topology and NOTHING else: before a single
    // exemplar, B' scores exactly what A scores.
    try testing.expectEqual(a.kernels.items.len, b.kernels.items.len);
    try testing.expectEqual(rms_a, try b.rms(pr.p, pr.y, null));
    try b.stream_n(thresholds.MARL1_DESCENT_N);
    const rms_b = try b.rms(pr.p, pr.y, null);
    // Births really were off, so the capacity control really is exact.
    try testing.expectEqual(a.kernels.items.len, b.kernels.items.len);
    try testing.expect(rms_a / rms_b >= thresholds.MARL1_DESCENT_GAIN);

    // The mutation, executed: descent disabled on the same frozen topology
    // leaves the model exactly where A left it.
    var dead = try Model.init(gpa, .{ .births = false, .rate_w = 0, .rate_geom = 0 });
    defer dead.deinit();
    try dead.reseedFrom(&a);
    try dead.stream_n(20_000);
    try testing.expectEqual(rms_a, try dead.rms(pr.p, pr.y, null));

    std.debug.print("\n  G18 (a): at K = {d} held identical, RMS {d:.5} → {d:.5}, deformation buys {d:.2} (predicted ≥ {d:.0} at N = {d}) ({s})\n", .{ a.kernels.items.len, rms_a, rms_b, rms_a / rms_b, thresholds.MARL1_DESCENT_GAIN, thresholds.MARL1_DESCENT_N, @tagName(builtin.mode) });
}

test "G18 (b) at fixed coverage, capacity follows the VOLUME of structure and its density does not move" {
    // The question was whether capacity follows task complexity. The
    // answer this gate pins down is more specific and less flattering than
    // the campaign hoped: kernels per unit of BAND VOLUME barely moves as
    // features are added, so what follows complexity is how much structure
    // there is to tile, not how hard it is. The work follows complexity
    // properly — events rise with features — but the capacity rule is
    // geometric. That is the evidence for residual-driven refinement being
    // MARL-2's, and it is why the gate asserts the density is STABLE
    // rather than that it grows.
    //
    // MUTATION: the birth test made unconditional (every learning event
    // births) — the density then tracks the event rate instead of the
    // coverage rule and leaves the band. Verified by hand.
    const gpa = testing.allocator;
    var density: [3]f32 = undefined;
    var counts: [3]u32 = undefined;
    for ([_]u32{ 1, 2, 4 }, 0..) |features, i| {
        const tp = TruthParams{ .features = features };
        var m = try Model.init(gpa, .{ .truth = tp });
        defer m.deinit();
        try m.stream_n(40_000);
        density[i] = m.densityIn(Truth.inShell, volumeOf(tp, Truth.inShell));
        counts[i] = m.countIn(Truth.inShell);
        // The quiet slab is unreachable at every complexity: features are
        // placed inside x ≤ 0.65 and the window ends at 0.70.
        try testing.expectEqual(@as(u32, 0), m.countIn(Truth.inQuiet));
        // And each feature is carried: the band's population must not fall
        // below the pre-registered share of the one-feature count.
        const per = @as(f32, @floatFromInt(counts[i])) / @as(f32, @floatFromInt(features));
        try testing.expect(per >= thresholds.MARL1_FEATURE_SCALING * @as(f32, @floatFromInt(counts[0])));
    }
    // Not vacuous: the band really did grow, so a stable density is a
    // statement about allocation and not about an unchanged experiment.
    try testing.expect(counts[2] > counts[0] * 2);
    const spread = @max(density[0], @max(density[1], density[2])) / @min(density[0], @min(density[1], density[2]));
    try testing.expect(spread < 1.5);

    // Stability across complexity is only half the claim, and on its own
    // it is not a claim a mutation can break — an unconditional birth rule
    // produces a stable density too, for a completely different reason. So
    // the other half is CAUSAL: if the coverage rule is what sets the
    // density, then moving coverage must move it, at complexity held
    // fixed. A birth rule that ignores coverage fails here and passes
    // everything above.
    var by_coverage: [2]f32 = undefined;
    for ([_]f32{ 0.20, 0.50 }, 0..) |cv, i| {
        var m = try Model.init(gpa, .{ .coverage = cv });
        defer m.deinit();
        try m.stream_n(40_000);
        by_coverage[i] = m.densityIn(Truth.inShell, volumeOf(.{}, Truth.inShell));
    }
    try testing.expect(by_coverage[1] > by_coverage[0] * 1.5);
    std.debug.print("  G18 (b): shell kernels {d} → {d} → {d} as features 1 → 2 → 4, but density {d:.0} → {d:.0} → {d:.0} per unit³ (spread {d:.2}); moving COVERAGE moves it, {d:.0} → {d:.0} — the tiling is geometric ({s})\n", .{ counts[0], counts[1], counts[2], density[0], density[1], density[2], spread, by_coverage[0], by_coverage[1], @tagName(builtin.mode) });
}

test "G18 (c) responsibility is separable from support: a fraction of the kernels need to learn, and the prediction stays exact" {
    // Christian's ruling. Support is the full cutoff gather and prediction
    // sums all of it, so inference semantics do not move and `rbf.CUTOFF`
    // is untouched; responsibility is the subset permitted a gradient, and
    // the NLMS normaliser Σg² is taken over that subset alone.
    //
    // MUTATION: the responsibility test dropped from the update loop
    // (gradients over the whole support set) — the responsible count stops
    // moving with the radius, which is what the sweep's first version
    // reported before the count was taken over the right set. Verified by
    // hand, and it is why this gate asserts the count MOVES.
    const gpa = testing.allocator;
    const pr = try probes(gpa, 0xB0B, 2048);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    const radii = [_]f32{ 2.0, 3.0, CUTOFF_R };
    var resp: [3]f64 = undefined;
    var gain: [3]f32 = undefined;
    var work: [3]u64 = undefined;
    const r_cov = @sqrt(-2 * @log(@as(f32, 0.35)));
    for (radii, 0..) |rr, i| {
        var m = try Model.init(gpa, .{ .responsibility = rr });
        defer m.deinit();
        const start = try m.rms(pr.p, pr.y, null);
        m.stats = .{};
        try m.stream_n(40_000);
        resp[i] = @as(f64, @floatFromInt(m.stats.responsible)) / @as(f64, @floatFromInt(m.stats.events));
        gain[i] = start / (try m.rms(pr.p, pr.y, null));
        work[i] = m.stats.updates;
        // The packing prediction: one kernel per ball of r_cov, so the
        // count inside R is the volume ratio.
        const predicted = @max(1.0, std.math.pow(f64, rr / r_cov, 3));
        try testing.expect(resp[i] <= predicted * thresholds.MARL1_TOUCHED_TOLERANCE);
        try testing.expect(resp[i] * thresholds.MARL1_TOUCHED_TOLERANCE >= predicted);
        // Prediction is still the sum over the model, whatever learns.
        var st = rng.Stream.region(3, 0xE4AC, 0);
        var k: usize = 0;
        while (k < 200) : (k += 1) {
            const q = [3]f32{ st.unit(), st.unit(), st.unit() };
            try testing.expectEqual(@as(u32, @bitCast(m.predictAll(q))), @as(u32, @bitCast(try m.predict(q))));
        }
    }
    // The count must actually move with the radius, or the gate is
    // watching the support set again — which is exactly what the sweep's
    // first version did, reporting 86 at every radius.
    try testing.expect(resp[0] * 4 < resp[2]);
    // And so must the WORK, which is the point of the whole separation: a
    // count that moves while the gradient loop still runs over everything
    // has saved nothing.
    try testing.expect(work[0] * 4 < work[2]);
    // And the accuracy must survive the cut: a tenth of the work, and no
    // worse. This is the campaign's cost question answered in the
    // direction nobody expected — letting distant kernels learn does not
    // help, and at R = 3 it actively hurts.
    try testing.expect(gain[1] >= gain[2]);
    std.debug.print("  G18 (c): responsible {d:.2} / {d:.2} / {d:.2} at R = 2, 3, {d:.3}; gain {d:.2} / {d:.2} / {d:.2}; work {d} / {d} / {d} ({s})\n", .{ resp[0], resp[1], resp[2], CUTOFF_R, gain[0], gain[1], gain[2], work[0], work[1], work[2], @tagName(builtin.mode) });
}

test "G18 (d) under-birth is over-responsibility: every diverging run carries weights outside the target's range, and every converging one does not" {
    // Christian's mechanism claim, and the gate is written so it can fail:
    // if divergence were something other than too few kernels carrying too
    // much, the weight statistic would not separate the two populations.
    // Two INDEPENDENT routes to under-birth are tested, refusal and
    // budget, because a mechanism that only shows up one way is a
    // coincidence.
    //
    // MUTATION: none needed — the gate carries its own control. The
    // converging arm must sit below the line and the diverging arm above
    // it, so a statistic that failed to separate them fails the gate.
    const gpa = testing.allocator;
    const pr = try probes(gpa, 0xB0B, 2048);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    const Case = struct { name: []const u8, opts: Options, diverges: bool };
    const cases = [_]Case{
        .{ .name = "coverage 0.10 (birth refused)", .opts = .{ .coverage = 0.10 }, .diverges = true },
        .{ .name = "budget 16 (birth capped)", .opts = .{ .budget = 16 }, .diverges = true },
        .{ .name = "the defaults", .opts = .{}, .diverges = false },
        .{ .name = "budget 32", .opts = .{ .budget = 32 }, .diverges = false },
    };
    for (cases) |c| {
        var m = try Model.init(gpa, c.opts);
        defer m.deinit();
        const start = try m.rms(pr.p, pr.y, null);
        try m.stream_n(40_000);
        const end = try m.rms(pr.p, pr.y, null);
        const w = m.weightStats();
        const diverged = end > start;
        try testing.expectEqual(c.diverges, diverged);
        if (diverged) {
            try testing.expect(w.mean_abs > thresholds.MARL1_OVERRESPONSIBILITY);
        } else {
            try testing.expect(w.mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
        }
        std.debug.print("  G18 (d): {s:<30} RMS {d:.5} → {d:.5}, mean |w| {d:.4} against the target's range {d:.2} ({s})\n", .{ c.name, start, end, w.mean_abs, thresholds.MARL1_OVERRESPONSIBILITY, if (diverged) "diverged" else "converged" });
    }
}

test "G18 (e) the budget bites when it is below the natural occupancy, and not when it is above" {
    // The campaign's §10 asked for saturation data and the natural
    // experiment never produced any: at the default budget of 64 no region
    // ever fills. So it is forced, and what it shows is that saturation
    // does not degrade gracefully — it is a route into G18 (d)'s regime.
    //
    // MUTATION: the budget test removed from the birth path — nothing ever
    // saturates and the low-budget arm converges like the high one.
    // Verified by hand.
    const gpa = testing.allocator;
    var tight = try Model.init(gpa, .{ .budget = thresholds.MARL1_SATURATION_BUDGET });
    defer tight.deinit();
    try tight.stream_n(40_000);
    try testing.expect(tight.stats.saturations > 0);
    try testing.expect(tight.saturatedRegions() > 0);

    var loose = try Model.init(gpa, .{});
    defer loose.deinit();
    try loose.stream_n(40_000);
    try testing.expectEqual(@as(u64, 0), loose.stats.saturations);
    try testing.expectEqual(@as(u32, 0), loose.saturatedRegions());

    std.debug.print("  G18 (e): budget {d} → {d} saturation events in {d} full regions; budget {d} → none at all ({s})\n", .{ thresholds.MARL1_SATURATION_BUDGET, tight.stats.saturations, tight.saturatedRegions(), loose.opts.budget, @tagName(builtin.mode) });
}

// ── MARL-2's gates ────────────────────────────────────────────────────
//
// Two of the five pre-registered numbers were REFUTED by the runs and are
// recorded as refuted in `thresholds.zig` rather than moved:
// `MARL2_CONCENTRATION` (predicted ≥ 3, measured 1.13 to 1.74) and
// `MARL2_SHARPNESS_RETENTION` (predicted ≥ 1.5, measured 1.22 at the
// defaults and 1.46 at its best). Striking or amending them is Christian's
// call, so no gate below asserts either. What the gates cover is what the
// runs confirmed, and the ledger has the rest.

test "G19 (a) the residual hierarchy's semantics: the child holds exactly what the parent could not, and the parent really is held" {
    // f(x) ≈ parent(x) + Δchild(x), and the whole meaning of that Δ rests
    // on the parent being FROZEN where the child is learning. A parent
    // that went on moving would be a parent the child is chasing, and the
    // second level would stop meaning "what the first could not represent".
    //
    // Freezing has to survive the case that made it necessary: an exemplar
    // in a NEIGHBOURING region reaching a kernel across the face, which the
    // responsibility radius lets it do.
    //
    // MUTATION: `freezeRegion` made a no-op — the parent's kernels in
    // refined regions move again, and the bitwise check below fails on the
    // first one. Verified by hand.
    const gpa = testing.allocator;
    var h = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 } }, .{});
    defer h.deinit();
    try h.stream_n(80_000);
    try testing.expect(h.refined_count > 0); // not vacuous: something refined
    try testing.expect(h.child.kernels.items.len > 0);

    // Every frozen kernel, byte for byte, across another twenty thousand
    // exemplars.
    var held = std.ArrayListUnmanaged(struct { i: usize, p: [PARAMS]f32 }){};
    defer held.deinit(gpa);
    for (h.parent.kernels.items, 0..) |*k, i| {
        if (k.frozen) try held.append(gpa, .{ .i = i, .p = k.p });
    }
    try testing.expect(held.items.len > 100);
    try h.stream_n(20_000);
    for (held.items) |rec| {
        for (h.parent.kernels.items[rec.i].p, rec.p) |now, then| {
            try testing.expectEqual(@as(u32, @bitCast(then)), @as(u32, @bitCast(now)));
        }
    }

    // The prediction is the sum, exactly, and each level is still the sum
    // over its own model.
    var st = rng.Stream.region(11, 0xD117, 0);
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const p = (try h.parent.predict(q))[0];
        const c = (try h.child.predict(q))[0];
        try testing.expectEqual(@as(u32, @bitCast(p + c)), @as(u32, @bitCast((try h.predict(q))[0])));
        try testing.expectEqual(@as(u32, @bitCast(h.parent.predictAll(q)[0])), @as(u32, @bitCast(p)));
        try testing.expectEqual(@as(u32, @bitCast(h.child.predictAll(q)[0])), @as(u32, @bitCast(c)));
    }

    // And the child spends nothing where there is nothing — the chain of
    // derivations in MARL2_CHILD_QUIET, checked at its end.
    try testing.expectEqual(thresholds.MARL2_CHILD_QUIET, h.child.countIn(Truth.inQuiet));
    std.debug.print("\n  G19 (a): {d} regions refined, {d} parent kernels held byte-identical across 20 000 further exemplars, {d} child kernels, {d} of them in the quiet slab ({s})\n", .{ h.refined_count, held.items.len, h.child.kernels.items.len, h.child.countIn(Truth.inQuiet), @tagName(builtin.mode) });
}

test "G19 (b) representation pressure fires where the parent CANNOT represent, not merely where it is wrong" {
    // The campaign's §5 — "do not confuse noise with complexity" — as a
    // number. Pressure is the mean post-update residual over learning
    // events where COVERAGE WAS ALREADY SATISFIED: a residual that persists
    // where the basis said it had the ground covered is the basis being
    // wrong about itself, while a residual where nothing covers the ground
    // is a birth waiting to happen and needs no new level.
    //
    // MUTATION, and it is the one that establishes the principle: pressure
    // accumulated from `ev.surprise`, the residual BEFORE the update steps,
    // instead of after them. Precision collapses to 0.383 / 0.328 / 0.277
    // at sharpness ×1 / ×2 / ×4, and 119 regions are refined instead of
    // 34 to 42 — the signal fires wherever the model is currently wrong
    // rather than where it cannot be made right.
    //
    // What makes that mutation worth its place: the ACCURACY barely moves,
    // 1.09 / 1.30 / 1.35 against 1.12 / 1.32 / 1.38. A gate on RMS alone
    // would have passed a refiner that opened three times too many regions
    // and froze twice as much of the parent. That is exactly the failure
    // Christian's instruction to pre-register on placement was written to
    // catch, and it caught it.
    const gpa = testing.allocator;
    var h = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 } }, .{});
    defer h.deinit();
    try h.stream_n(80_000);

    const p = h.precision();
    try testing.expect(p.refined > 5); // not vacuous
    const frac = @as(f32, @floatFromInt(p.on_shell)) / @as(f32, @floatFromInt(p.refined));
    try testing.expect(frac >= thresholds.MARL2_PRECISION);

    // The statistic must separate the two populations, or the precision
    // above is an accident of where the threshold happened to fall.
    var on: f64 = 0;
    var on_n: u32 = 0;
    var off: f64 = 0;
    var off_n: u32 = 0;
    for (0..h.parent.regions.len) |i| {
        const idx: u32 = @intCast(i);
        if (h.covered_events[idx] < h.popts.min_events) continue;
        if (h.regionMeetsShell(idx)) {
            on += h.pressureOf(idx);
            on_n += 1;
        } else {
            off += h.pressureOf(idx);
            off_n += 1;
        }
    }
    try testing.expect(on_n > 5 and off_n > 5);
    const on_mean = on / @as(f64, @floatFromInt(on_n));
    const off_mean = off / @as(f64, @floatFromInt(off_n));
    try testing.expect(on_mean > off_mean * 1.5);
    std.debug.print("  G19 (b): {d} of {d} refined regions touch the band (precision {d:.3}, predicted ≥ {d:.2}); pressure {d:.5} on the band against {d:.5} off it ({s})\n", .{ p.on_shell, p.refined, frac, thresholds.MARL2_PRECISION, on_mean, off_mean, @tagName(builtin.mode) });
}

test "G19 (c) the hierarchy beats flat MARL on the same exemplars and does LESS work doing it" {
    // The weakest of the pre-registered claims and the only one about RMS,
    // deliberately: Christian's instruction was to gate on where the
    // capacity appears rather than on whether the error improves, because
    // an unconditional second layer would pass the second and fail the
    // first. It did exactly that — see `MARL2_CONCENTRATION` in
    // thresholds.zig, predicted ≥ 3 and measured 1.13 to 1.74, refuted and
    // recorded rather than moved.
    //
    // What the work ratio shows was not predicted at all: the hierarchy is
    // CHEAPER than flat, not dearer. The parent stops learning in refined
    // regions, so the child's gradients replace the parent's rather than
    // adding to them, and the child's finer kernels have smaller
    // responsibility sets.
    //
    // MUTATION: refinement never triggered (the pressure threshold above
    // anything observed) — the hierarchy IS the flat model, the ratio is 1
    // and this gate fails. That was the first run's accidental state, when
    // the threshold was set ten times too high.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 2 };
    const pr = try probesOf(gpa, tp, 0xB0B, 4096);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var flat = try Model.init(gpa, .{ .truth = tp });
    defer flat.deinit();
    const empty = try flat.rms(pr.p, pr.y, null);
    flat.stats = .{};
    try flat.stream_n(80_000);
    const rms_flat = try flat.rms(pr.p, pr.y, null);

    var h = try Hierarchy.init(gpa, .{ .truth = tp }, .{});
    defer h.deinit();
    try h.stream_n(80_000);
    const rms_hier = try h.rms(pr.p, pr.y, null);
    const rms_parent = try h.parentRms(pr.p, pr.y);

    try testing.expect(rms_hier < rms_flat);
    // And the child is what did it: the parent alone, with its refined
    // regions frozen, is worse than the pair. (Whether it is also worse
    // than FLAT depends on how long the run is — at 200 000 exemplars it
    // is, 0.06697 against 0.04659, because freezing costs the parent more
    // the longer it would have gone on learning. Not asserted, because it
    // is a property of the horizon and not of the mechanism.)
    try testing.expect(rms_parent > rms_hier);
    const work = @as(f64, @floatFromInt(h.parent.stats.updates + h.child.stats.updates)) /
        @as(f64, @floatFromInt(flat.stats.updates));
    try testing.expect(work <= thresholds.MARL2_WORK_RATIO);
    // Both levels stay in the convergent weight regime — refinement must
    // not trade one pathology for another (MARL-1's finding).
    try testing.expect(h.parent.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
    try testing.expect(h.child.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
    std.debug.print("  G19 (c): empty {d:.5}, flat {d:.5}, parent alone {d:.5}, parent + child {d:.5}; work {d:.3} of flat's (predicted ≤ {d:.1}) ({s})\n", .{ empty, rms_flat, rms_parent, rms_hier, work, thresholds.MARL2_WORK_RATIO, @tagName(builtin.mode) });
}

// ── MARL-3's gates ────────────────────────────────────────────────────
//
// MARL-3 changed exactly one thing — the child's birth decision — and all
// three of its pre-registered numbers were REFUTED. They stand unstruck in
// `thresholds.zig`; no gate asserts them. What is gated below is what the
// experiment established instead, which is more useful than what it set
// out to show.

test "G20 (a) a residual birth needs BOTH persistence and magnitude, and spends its evidence" {
    // The campaign's §5 as arithmetic: "do not confuse noise with
    // complexity". One large residual is a singleton; `birth_evidence`
    // observations averaging above the bar is structure. And the evidence
    // is SPENT on the birth, or one piece of it births a kernel on every
    // subsequent event until the mean falls.
    //
    // MUTATION: the count requirement dropped from `evidenced` — every
    // learning event whose cell is over the bar births, the child's
    // population runs away, and the check below on it fails. Verified by
    // hand.
    const gpa = testing.allocator;
    var strict = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 } }, .{ .child_birth = .residual });
    defer strict.deinit();
    try strict.stream_n(80_000);
    // It does birth — and only just. Thirty-odd kernels at this horizon,
    // where the coverage rule births thousands on the same stream, which
    // is G20 (b)'s finding showing up here first.
    try testing.expect(strict.child.kernels.items.len > 10);

    // Raising the bar must reduce the population, or the magnitude half of
    // the rule is not being read.
    var high = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 }, .birth_residual = 0.10 }, .{ .child_birth = .residual });
    defer high.deinit();
    try high.stream_n(80_000);
    try testing.expect(high.child.kernels.items.len < strict.child.kernels.items.len);

    // …and so must demanding more evidence, which is the other half.
    var patient = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 }, .birth_evidence = 40 }, .{ .child_birth = .residual });
    defer patient.deinit();
    try patient.stream_n(80_000);
    try testing.expect(patient.child.kernels.items.len < strict.child.kernels.items.len);

    std.debug.print("\n  G20 (a): residual births {d}; bar ×5 → {d}; evidence ×5 → {d} ({s})\n", .{ strict.child.kernels.items.len, high.child.kernels.items.len, patient.child.kernels.items.len, @tagName(builtin.mode) });
}

test "G20 (b) residual birth alone under-births into MARL-1's over-responsibility regime, and the coverage floor is what prevents it" {
    // The finding, and it is MARL-1's mechanism arriving through a THIRD
    // door. Birth refused by coverage and birth capped by budget both
    // produced mean |w| near 13 against a converging 0.08; birth gated on
    // residual evidence does it too. Too few kernels are made answerable
    // for too much, and — the new part — a diverged child's own residual
    // then contaminates the very signal it was using to place capacity.
    //
    // So the coverage rule was never only about placement. It is a
    // TRAINABILITY floor, and MARL-3's result is that removing it costs
    // more than the placement it was blamed for.
    //
    // MUTATION: none needed — the gate carries its control. `.either`
    // keeps the floor and stays convergent on the same target and stream.
    const gpa = testing.allocator;
    var alone = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 } }, .{ .child_birth = .residual });
    defer alone.deinit();
    try alone.stream_n(80_000);

    var floored = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 2 } }, .{ .child_birth = .either });
    defer floored.deinit();
    try floored.stream_n(80_000);

    try testing.expect(alone.child.weightStats().mean_abs > thresholds.MARL1_OVERRESPONSIBILITY);
    try testing.expect(floored.child.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
    // And the reason, in the two numbers that say it: far fewer kernels,
    // each with far less evidence.
    try testing.expect(alone.child.kernels.items.len * 2 < floored.child.kernels.items.len);
    try testing.expect(alone.child.trainedFraction(10) < 0.5);
    try testing.expect(floored.child.trainedFraction(10) > 0.9);
    std.debug.print("  G20 (b): residual alone — {d} kernels, {d:.3} trained, mean |w| {d:.2}; with the coverage floor — {d} kernels, {d:.3} trained, mean |w| {d:.3} ({s})\n", .{ alone.child.kernels.items.len, alone.child.trainedFraction(10), alone.child.weightStats().mean_abs, floored.child.kernels.items.len, floored.child.trainedFraction(10), floored.child.weightStats().mean_abs, @tagName(builtin.mode) });
}

test "G20 (c) capacity concentration is bounded by EVIDENCE concentration, and the child's evidence stream is uniform" {
    // Why no birth rule fixed the allocator. A birth can only happen where
    // an exemplar is, so the most a birth rule can do is concentrate
    // capacity relative to the stream it is given — and the child's stream
    // is uniform over the refined region, because every exemplar landing
    // there is routed regardless of where the residual is.
    //
    // Measured at sharpness ×4: the band is 8.0% of the refined volume,
    // the routed exemplars are 9.3% of it — a concentration of 1.16, which
    // is nothing — and the birth rule lifts the kernels to 15.0%
    // (coverage) or 18.4% (residual). The rule contributes its 1.6 to 2.0;
    // the stream contributes none of it. That is the whole of the
    // concentration failure, and it is not in the birth criterion.
    //
    // MUTATION: route only high-residual exemplars to the child — the
    // stream stops being uniform and the first assertion below fails. That
    // is not a mutation, it is MARL-4, and this gate is what will notice
    // when it lands.
    const gpa = testing.allocator;
    var h = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = 4 } }, .{});
    defer h.deinit();
    try h.stream_n(80_000);
    try testing.expect(h.routed > 1000);

    const band_share = h.bandShareOfRefined();
    const routed_share = @as(f32, @floatFromInt(h.routed_in_band)) / @as(f32, @floatFromInt(h.routed));
    const kernel_share = @as(f32, @floatFromInt(h.child.countIn(Truth.inShell))) /
        @as(f32, @floatFromInt(h.child.kernels.items.len));

    // The stream is uniform: what reaches the child in the band is the
    // band's share of the volume, and nothing more.
    try testing.expect(routed_share < band_share * 1.3);
    // The birth rule does concentrate, above the stream it is given…
    try testing.expect(kernel_share > routed_share * 1.3);
    // …and nowhere near the ceiling, which is all of them.
    try testing.expect(kernel_share < 0.4);
    std.debug.print("  G20 (c): the band is {d:.4} of the refined volume; the routed stream {d:.4}; the child's kernels {d:.4}; ceiling 1.0 ({s})\n", .{ band_share, routed_share, kernel_share, @tagName(builtin.mode) });
}

// ── MARL-4's gates ────────────────────────────────────────────────────
//
// MARL-3 established that capacity concentrates only where the STREAM
// concentrates. MARL-4 changes the stream and nothing else. All four of
// its pre-registered numbers held, which is the first time in this
// campaign that happened — and they held at a cost the pre-registration
// did not ask about, which G21 (b) is where that is recorded.

test "G21 (a) biasing the stream concentrates it, more so the sharper the target, and capacity follows it" {
    // The chain Christian named: sharpness rises → the residual localises →
    // routing probability concentrates → evidence density concentrates →
    // child capacity follows. Each arrow is a number here.
    //
    // MUTATION: `route_gain` set to zero, which is uniform routing with a
    // floor — the stream stops concentrating (slope 0.96 against 1.40) and
    // the slope assertion fails. Executed below rather than described,
    // because it costs one more run and the gate is about the difference.
    const gpa = testing.allocator;
    const P = PressureOptions{ .route_floor = 0.02, .route_gain = 3 };
    var conc: [2]f32 = undefined;
    var track: [2]f32 = undefined;
    for ([_]f32{ 1, 4 }, 0..) |sharp, i| {
        var h = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = sharp } }, P);
        defer h.deinit();
        try h.stream_n(80_000);
        const band = h.bandShareOfRefined();
        const stream = @as(f32, @floatFromInt(h.routed_in_band)) / @as(f32, @floatFromInt(h.routed));
        const kern = @as(f32, @floatFromInt(h.child.countIn(Truth.inShell))) /
            @as(f32, @floatFromInt(h.child.kernels.items.len));
        conc[i] = stream / band;
        track[i] = kern / stream;
        // Capacity tracks the stream it is given — MARL-3's diagnosis,
        // still holding once the stream is no longer uniform.
        try testing.expect(track[i] >= thresholds.MARL4_TRACKING_LO);
        try testing.expect(track[i] <= thresholds.MARL4_TRACKING_HI);
        // The router routes strictly less than everything, or the floor
        // and the gain are doing nothing.
        try testing.expect(h.routed < h.offered);
    }
    try testing.expect(conc[1] / conc[0] >= thresholds.MARL4_STREAM_SLOPE);

    // The mutation, run: no gain, and the slope goes away.
    var flat_slope: [2]f32 = undefined;
    for ([_]f32{ 1, 4 }, 0..) |sharp, i| {
        var h = try Hierarchy.init(gpa, .{ .truth = .{ .sharpness = sharp } }, .{});
        defer h.deinit();
        try h.stream_n(80_000);
        const band = h.bandShareOfRefined();
        const stream = @as(f32, @floatFromInt(h.routed_in_band)) / @as(f32, @floatFromInt(h.routed));
        flat_slope[i] = stream / band;
    }
    try testing.expect(flat_slope[1] / flat_slope[0] < thresholds.MARL4_STREAM_SLOPE);
    std.debug.print("\n  G21 (a): stream concentration {d:.2} → {d:.2} as sharpness goes ×1 → ×4, a slope of {d:.2} (predicted ≥ {d:.1}); uniform routing scores {d:.2}; capacity tracks at {d:.2} and {d:.2} ({s})\n", .{ conc[0], conc[1], conc[1] / conc[0], thresholds.MARL4_STREAM_SLOPE, flat_slope[1] / flat_slope[0], track[0], track[1], @tagName(builtin.mode) });
}

test "G21 (b) the floor keeps the child trainable, and the bias is paid for in evidence per kernel" {
    // Both halves matter and they pull against each other. `route_floor`
    // is the trainability floor the coverage rule was silently supplying —
    // MARL-3 removed it and walked into the over-responsibility regime by
    // the third known door. `route_gain` is the concentration. Turning the
    // gain up spends evidence per kernel to buy placement, and this gate
    // asserts BOTH that the floor holds and that the price is real, so
    // neither can be quietly optimised away.
    //
    // The exchange rate, measured at sharpness ×4 and 200 000 exemplars:
    //
    //     floor/gain   RMS      kernels  updates/kernel  concentration
    //      1 / 0       0.04423     3760        461            1.65
    //      0.05 / 6    0.04477     2736        305            2.13
    //      0.02 / 3    0.05082     2135        217            2.50
    //
    // So most of the placement is available for almost nothing and the
    // last of it is dear — which is the shape a campaign should know
    // before it picks an operating point.
    //
    // MUTATION: `route_floor` set to zero. Verified by hand.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 4 };

    var biased = try Hierarchy.init(gpa, .{ .truth = tp }, .{ .route_floor = 0.02, .route_gain = 3 });
    defer biased.deinit();
    try biased.stream_n(200_000);
    var uniform = try Hierarchy.init(gpa, .{ .truth = tp }, .{});
    defer uniform.deinit();
    try uniform.stream_n(200_000);

    const child_conc = biased.childConcentration();
    try testing.expect(child_conc >= thresholds.MARL4_CONCENTRATION);
    // And it really is better placed than uniform routing's, not merely
    // above a number.
    try testing.expect(child_conc > uniform.childConcentration() * 1.2);

    // The floor is a floor.
    try testing.expect(biased.child.trainedFraction(10) >= thresholds.MARL4_TRAINED_FLOOR);
    try testing.expect(biased.child.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
    try testing.expect(biased.parent.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);

    // And the price is real: the same budget buys fewer kernels and far
    // less evidence for each of them.
    try testing.expect(biased.child.meanUpdates() < uniform.child.meanUpdates() * 0.75);
    try testing.expect(biased.child.kernels.items.len < uniform.child.kernels.items.len);
    // Routing less can only do less work, so this is a control.
    const work = @as(f64, @floatFromInt(biased.parent.stats.updates + biased.child.stats.updates)) /
        @as(f64, @floatFromInt(uniform.parent.stats.updates + uniform.child.stats.updates));
    try testing.expect(work < thresholds.MARL2_WORK_RATIO);
    std.debug.print("  G21 (b): concentration {d:.2} (predicted ≥ {d:.1}); {d} kernels at {d:.0} updates each against uniform's {d} at {d:.0}; trained {d:.3}, mean |w| {d:.3} ({s})\n", .{ child_conc, thresholds.MARL4_CONCENTRATION, biased.child.kernels.items.len, biased.child.meanUpdates(), uniform.child.kernels.items.len, uniform.child.meanUpdates(), biased.child.trainedFraction(10), biased.child.weightStats().mean_abs, @tagName(builtin.mode) });
}

// ── MARL-5's gates ────────────────────────────────────────────────────
//
// All three pre-registered numbers were REFUTED and stand unstruck in
// `thresholds.zig`. The answer to "can an adaptive scheduler allocate a
// fixed learning budget better than static residual-biased routing?" is
// NO, and the reason is granularity: the schedule is coarser than the
// signal it must act on.

test "G22 (a) a region-level schedule is coarser than the structure it must resolve, and the per-exemplar term is what carries the routing" {
    // MARL-5's refutation, isolated. Three region-level policies — need,
    // need × lag, need × lag ÷ sufficiency — all lose to MARL-4's static
    // per-exemplar bias by about 10% of RMS at the same duty. The hybrid
    // (per-exemplar bias × the region's starvation) recovers static's
    // number to within 1%, which says the region term contributes nothing
    // and the exemplar term contributes everything.
    //
    // The reason is scale. A region is a sixth of the domain across; the
    // ridge this campaign has been chasing is a fortieth of it thick. A
    // schedule that routes a whole region at one probability cannot
    // separate the exemplar on the ridge from the one beside it, and that
    // separation IS the mechanism MARL-4 established.
    //
    // MUTATION: the hybrid's per-exemplar term removed, leaving the region
    // term alone — it becomes `need_lag` and the comparison below fails.
    //
    // The horizon is named, and it has to be: biased routing CROSSES OVER
    // uniform routing between 150 000 and 200 000 exemplars and only wins
    // after. Below the crossover it is behind, because concentrating
    // evidence starves before it compounds — the campaign's standing
    // invariant arriving one more time. Measured at duty 0.4, sharpness
    // ×4: uniform 0.0498 → 0.0514 across a fourfold rise in N (it plateaus
    // and never improves), while static bias goes 0.0542 → 0.0446 and the
    // hybrid 0.0539 → 0.0450.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 4 };
    const pr = try probesOf(gpa, tp, 0xB0B, 4096);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    const base = PressureOptions{ .route_duty = 0.4, .route_floor = 0.05, .route_gain = 6 };
    var region = try Hierarchy.init(gpa, .{ .truth = tp }, blk: {
        var p = base;
        p.sched = .need_lag;
        break :blk p;
    });
    defer region.deinit();
    try region.stream_n(200_000);
    const rms_region = try region.rms(pr.p, pr.y, null);

    var hybrid = try Hierarchy.init(gpa, .{ .truth = tp }, blk: {
        var p = base;
        p.sched = .hybrid;
        break :blk p;
    });
    defer hybrid.deinit();
    try hybrid.stream_n(200_000);
    const rms_hybrid = try hybrid.rms(pr.p, pr.y, null);

    // The per-exemplar term wins, and it is not close.
    try testing.expect(rms_hybrid < rms_region);
    // …and it wins on concentration too, so this is not a work trade.
    try testing.expect(hybrid.childConcentration() > region.childConcentration() * 1.15);
    std.debug.print("\n  G22 (a): region schedule {d:.5} at concentration {d:.2}; the same schedule with MARL-4's per-exemplar term {d:.5} at {d:.2} ({s})\n", .{ rms_region, region.childConcentration(), rms_hybrid, hybrid.childConcentration(), @tagName(builtin.mode) });
}

test "G22 (b) the Pareto improvement MARL-5 was asked for already existed, and it is MARL-4's" {
    // At equal duty, static residual bias reaches a materially better
    // error AND a materially better concentration than uniform routing,
    // for less child work. That is the improvement the scheduler was meant
    // to find, and it was already there — which is the honest reading of
    // MARL-5 and the reason its own three numbers were refuted rather than
    // met.
    //
    // MUTATION: `route_gain` set to zero — the biased arm IS the uniform
    // arm, and every comparison below collapses. Verified by hand.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 4 };
    const pr = try probesOf(gpa, tp, 0xB0B, 4096);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    // Past the crossover, and it must be: below about 175 000 exemplars
    // the biased arm is BEHIND uniform, because concentrated evidence
    // starves before it compounds. Uniform at this duty never improves —
    // 0.0498 at 100 000, 0.0514 at 400 000 — while the biased arm goes
    // 0.0542 to 0.0446 and passes it on the way.
    var uniform = try Hierarchy.init(gpa, .{ .truth = tp }, .{ .route_duty = 0.4, .route_floor = 1, .route_gain = 0 });
    defer uniform.deinit();
    try uniform.stream_n(200_000);
    var biased = try Hierarchy.init(gpa, .{ .truth = tp }, .{ .route_duty = 0.4, .route_floor = 0.05, .route_gain = 6 });
    defer biased.deinit();
    try biased.stream_n(200_000);

    try testing.expect((try biased.rms(pr.p, pr.y, null)) < (try uniform.rms(pr.p, pr.y, null)));
    try testing.expect(biased.childConcentration() > uniform.childConcentration() * 1.2);
    // Both levels stay healthy — the campaign's standing invariant.
    try testing.expect(biased.child.trainedFraction(10) >= thresholds.MARL4_TRAINED_FLOOR);
    try testing.expect(biased.child.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
    std.debug.print("  G22 (b): uniform {d:.5} at concentration {d:.2}; static residual bias {d:.5} at {d:.2}, on the same exemplars at the same duty ({s})\n", .{ try uniform.rms(pr.p, pr.y, null), uniform.childConcentration(), try biased.rms(pr.p, pr.y, null), biased.childConcentration(), @tagName(builtin.mode) });
}

// ── MARL-6's gates ────────────────────────────────────────────────────
//
// The first phase that tests the PREMISE. Two of four pre-registered
// numbers held; the two that did not are recorded in `thresholds.zig`.
// The outcome is Christian's B — RMS partially recovers while the
// hierarchy's semantics degrade — which is the one an ordinary benchmark
// would call success.

test "G23 (a) freezing SURVIVES the world moving — and the first version of this gate was confounded" {
    // What this gate was written to show, and does not: that the frozen
    // parent is what breaks under drift. Its first draft compared a
    // drifted hierarchy's parent against a STATIONARY control's and found
    // it 1.23× worse — but the control had 160 000 exemplars on one world
    // and the drifted arm 60 000 on its new one, so any learner whatever
    // would have shown that. The number measured the budget, not the
    // mechanism.
    //
    // Worse, the named mutation SURVIVED: making `freezeRegion` a no-op
    // left the parent 1.32× off, no better. That is because freezing was
    // never the operative commitment — in a refined region `observeOne`
    // returns after routing, so the parent NEVER OBSERVES THERE AT ALL.
    // Unfreezing changes only whether a neighbouring region's exemplar can
    // reach a kernel across the face.
    //
    // So the comparison that isolates it is drift against drift, at
    // identical budget, with the design choices switched off one at a
    // time. And the answer is the opposite of what this phase set out to
    // find — both choices are VINDICATED under drift:
    //
    //     frozen, parent cut off from refined regions   total 0.04905
    //     unfrozen, still cut off                             0.05051
    //     parent also observing in refined regions            0.06662
    //
    // Letting the parent keep learning where the child is learning makes
    // its own error better and the PAIR's much worse, because the child is
    // learning `y − parent` while the parent moves underneath it. That is
    // MARL-2's freezing rationale, confirmed by an experiment designed to
    // break it.
    //
    // MUTATION: the parent made to observe in refined regions too — the
    // total gets worse and the assertion below fails.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 2 };
    var moved = tp;
    moved.shift = .{ 0, -0.10, 0 };
    const pr = try probesOf(gpa, moved, 0xB0B, 2048);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var h = try Hierarchy.init(gpa, .{ .truth = tp }, .{});
    defer h.deinit();
    try h.stream_n(100_000);
    try h.drift(gpa, moved);
    const child_at_move = try h.childRms(pr.p);
    const parent_at_move = try h.parentRms(pr.p, pr.y);
    try h.stream_n(60_000);

    // The coarse level does not repair itself: it is neither observing in
    // the regions that moved nor free to move there.
    const parent_after = try h.parentRms(pr.p, pr.y);
    try testing.expect(parent_after > parent_at_move * 0.95);
    // And the child takes the job on — which is the semantic degradation,
    // `current target − historical parent` rather than unresolved detail.
    const child_after = try h.childRms(pr.p);
    try testing.expect(child_after > child_at_move * 1.2);
    // The pair still recovers most of the way, which is outcome B: an
    // ordinary benchmark would call this success.
    try testing.expect((try h.rms(pr.p, pr.y, null)) < 0.06);
    std.debug.print("\n  G23 (a): across the move the parent went {d:.5} → {d:.5} (it cannot repair) while the child went {d:.5} → {d:.5} (it takes over); the pair reaches {d:.5} ({s})\n", .{ parent_at_move, parent_after, child_at_move, child_after, try h.rms(pr.p, pr.y, null), @tagName(builtin.mode) });
}

test "G23 (b) capacity is stranded where the structure used to be, and refinement now describes a world that has gone" {
    // Kernels cannot follow the world: MARL-0 measured centre drift at
    // 0.0009 of the domain over a whole run, so a kernel born on the old
    // ridge dies on the old ridge. And a region, once refined, is never
    // unrefined — so after a move the refined set describes where
    // structure USED to be, diluted by wherever it went.
    //
    // MUTATION: none is available and none is needed, because the gate
    // carries its control — the stationary arm runs the same length on the
    // same seed and is compared against directly. A stranding that is
    // merely what any run shows would fail the comparison below.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 2 };
    var moved = tp;
    moved.shift = .{ 0, -0.30, 0 }; // large: into regions never pressured

    var control = try Hierarchy.init(gpa, .{ .truth = tp }, .{});
    defer control.deinit();
    try control.stream_n(100_000);
    try control.drift(gpa, tp); // marks the epoch without moving anything
    try control.stream_n(60_000);

    var drifted = try Hierarchy.init(gpa, .{ .truth = tp }, .{});
    defer drifted.deinit();
    try drifted.stream_n(100_000);
    try drifted.drift(gpa, moved);
    try drifted.stream_n(60_000);

    const sc = control.strandedOf();
    const sd = drifted.strandedOf();
    const frac_c = @as(f32, @floatFromInt(sc.outside_current)) / @as(f32, @floatFromInt(sc.at_drift));
    const frac_d = @as(f32, @floatFromInt(sd.outside_current)) / @as(f32, @floatFromInt(sd.at_drift));
    try testing.expect(frac_d >= thresholds.MARL6_STRANDED);
    try testing.expect(frac_d > frac_c); // not merely what any run shows

    const pc = control.precision();
    const pd = drifted.precision();
    const prec_c = @as(f32, @floatFromInt(pc.on_shell)) / @as(f32, @floatFromInt(pc.refined));
    const prec_d = @as(f32, @floatFromInt(pd.on_shell)) / @as(f32, @floatFromInt(pd.refined));
    try testing.expect(prec_d <= prec_c * thresholds.MARL6_PRECISION_FALL);
    std.debug.print("  G23 (b): {d:.3} of pre-move child kernels stranded outside the current band against the control's {d:.3}; refinement precision {d:.3} against {d:.3} ({d:.2}×) ({s})\n", .{ frac_d, frac_c, prec_d, prec_c, prec_d / prec_c, @tagName(builtin.mode) });
}

// ── MARL-6R's gate ────────────────────────────────────────────────────
//
// The interstitial: no new mechanism, only the learning unit corrected.
// MARL-1 established that a responsibility radius of 3 preserves accuracy
// at a sixth of the work, and then every phase from MARL-2 to MARL-6
// reasoned about evidence, starvation and budget while paying the full
// support cost anyway. This gate is what stops that debt being taken on
// again silently.

test "G24 the hierarchy is indifferent to the responsibility radius in accuracy and sixfold cheaper in work" {
    // The recalibration's whole claim, and the one MARL-7's economics will
    // rest on. Everything a later phase might read — error, capacity,
    // concentration, refinement precision — is unchanged; only the price
    // of a learning event moves.
    //
    // MUTATION: the responsibility test dropped from the update loop, so
    // both arms gather gradients over the whole support set — the work
    // ratio goes to one and the assertion below fails. It is G18 (c)'s
    // mutation, which is the right one: this gate is that finding carried
    // into the hierarchy.
    const gpa = testing.allocator;
    const tp = TruthParams{ .sharpness = 2 };
    const pr = try probesOf(gpa, tp, 0xB0B, 2048);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var full = try Hierarchy.init(gpa, .{ .truth = tp }, .{});
    defer full.deinit();
    try full.stream_n(80_000);
    var lean = try Hierarchy.init(gpa, .{ .truth = tp, .responsibility = 3 }, .{});
    defer lean.deinit();
    try lean.stream_n(80_000);

    const rms_full = try full.rms(pr.p, pr.y, null);
    const rms_lean = try lean.rms(pr.p, pr.y, null);
    // Accuracy is indifferent, in both directions — a lean model that was
    // merely better would be a different finding and would want its own
    // threshold.
    try testing.expect(rms_lean < rms_full * 1.1);
    try testing.expect(rms_lean > rms_full * 0.9);
    // And the work is not.
    const work_full = full.parent.stats.updates + full.child.stats.updates;
    const work_lean = lean.parent.stats.updates + lean.child.stats.updates;
    try testing.expect(work_lean * 4 < work_full);
    // Nothing a later phase reads has moved.
    try testing.expect(lean.child.kernels.items.len > full.child.kernels.items.len * 3 / 4);
    try testing.expect(lean.childConcentration() > full.childConcentration() * 0.8);
    try testing.expect(lean.child.weightStats().mean_abs < thresholds.MARL1_OVERRESPONSIBILITY);
    std.debug.print("\n  G24: RMS {d:.5} → {d:.5} ({d:.3}×) for work {d} → {d} ({d:.3}×); {d} kernels → {d}, concentration {d:.2} → {d:.2} ({s})\n", .{ rms_full, rms_lean, rms_lean / rms_full, work_full, work_lean, @as(f64, @floatFromInt(work_lean)) / @as(f64, @floatFromInt(work_full)), full.child.kernels.items.len, lean.child.kernels.items.len, full.childConcentration(), lean.childConcentration(), @tagName(builtin.mode) });
}

// ── MARL-7's gates ────────────────────────────────────────────────────
//
// Erosion, and the answer is that there is nothing to erode. Two
// measurements run before any mechanism scoped the phase, and a third
// after it closed the question — the capacity a drifted model accumulates
// is not obsolete, it is working, and neither of the operations Christian
// separated addresses what is actually wrong.

test "G26 (a) the capacity a moved world leaves behind is LOAD-BEARING, so kernel death has nothing to target" {
    // The measurement that scoped MARL-7. Obsolete kernels do not
    // self-identify by weight — after a large drift the pre-move kernels
    // outside the current band carry MORE than the stationary control's
    // off-band kernels do — and silencing them makes the prediction worse,
    // not better. They are simultaneously fitting the swell's fine
    // structure and cancelling the frozen parent's stale contribution, and
    // no deletion takes one without the other.
    //
    // MUTATION: none is available, and the gate is written so it does not
    // need one — it asserts that silencing HURTS. Were those kernels
    // obsolete, silencing would be free and the assertion would fail. The
    // gate's own subject is the null it rules out.
    const gpa = testing.allocator;
    const t = TruthParams{ .sharpness = 2 };
    var moved = t;
    moved.shift = .{ 0, -0.30, 0 };

    var h = try Hierarchy.init(gpa, .{ .truth = t, .responsibility = 3 }, .{});
    defer h.deinit();
    try h.stream_n(100_000);
    try h.drift(gpa, moved);
    try h.stream_n(60_000);

    const pr = try probesOf(gpa, moved, 0xB0B, 2048);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);
    const before = try h.rms(pr.p, pr.y, null);
    const saved = try gpa.alloc(f32, h.child_at_drift);
    defer gpa.free(saved);
    const n = h.silenceObsolete(saved);
    const after = try h.rms(pr.p, pr.y, null);
    h.restoreObsolete(saved[0..n]);

    try testing.expect(n > 500); // there really is a population to silence
    try testing.expect(after > before * 1.2); // and it was doing real work
    // Weight does not separate it from anything: the "obsolete" kernels
    // carry as much as the ones born since.
    const st = h.strandedOf();
    try testing.expect(st.w_obsolete > st.w_new * 0.6);
    std.debug.print("\n  G26 (a): silencing {d} pre-move kernels now outside the band costs {d:.5} → {d:.5} ({d:.2}×); their mean |w| {d:.4} against {d:.4} for kernels born since ({s})\n", .{ n, before, after, after / before, st.w_obsolete, st.w_new, @tagName(builtin.mode) });
}

// G26 (b) WAS a precision gate on unrefinement — "of the regions it
// retires, the share the structure has left" — and it was withdrawn
// before it shipped, because it could not fail.
//
// Two mutations survived it. The mean statistic instead of the decaying
// max scored 0.875 against the peak's 1.000, and retiring on AGE ALONE —
// with no reference to the parent's error whatever — scored 0.969 across
// 32 regions. The reason is a confound in the EXPERIMENT rather than in
// the trigger: on a drift test the regions refined longest ago are
// exactly the regions refined before the world moved, which are exactly
// the departed ones. Age and departure are the same variable here, so any
// policy preferring older regions scores well and the metric
// distinguishes nothing.
//
// The peak-versus-mean difference is real — 1.000 against 0.667 at an
// unrefinement factor of 3 with the world moving at 200 000 — but it is
// configuration-dependent, and a gate that reproduces it at one setting
// and not another is reporting a setting. It is in the ledger instead.
//
// What would discriminate is a world where structure leaves regions that
// were refined at different times, which this target does not provide.
// That is a fixture problem, and MARL-8's to fix if it needs the metric.

// ── MARL-8's gate ─────────────────────────────────────────────────────
//
// Recycling did not work. What it did do is establish that geometry is
// not a transferable asset here, and one design decision inside it — the
// weight reset — is worth protecting, because it is what makes a
// transplant SAFE rather than merely ineffective.

test "G28 a transplant is inert at the moment it lands: the geometry arrives, the weights do not" {
    // The one thing MARL-8 built that clearly works. A banked kernel is
    // instantiated at weight zero, so the prediction is unchanged by the
    // act of transplanting — bit for bit, not approximately. The convex
    // part is then relearned in the new region's own terms against its own
    // parent, which is what MARL-1 said the weights are for.
    //
    // Carrying the donor's weights instead would inject a correction
    // fitted to a DIFFERENT parent's error, which is the one way this
    // mechanism could have been actively harmful rather than merely
    // useless.
    //
    // MUTATION: `rel.p[W] = 0` removed from `bank`, so donor weights ride
    // along — the prediction jumps the moment a region refines and the
    // bitwise check below fails. Verified by hand.
    const gpa = testing.allocator;
    const t = TruthParams{ .sharpness = 2 };
    var moved = t;
    moved.shift = .{ 0, -0.30, 0 };

    var h = try Hierarchy.init(gpa, .{ .truth = t, .responsibility = 3 }, .{ .unrefine = 2, .recycle = true });
    defer h.deinit();
    try h.stream_n(100_000);
    try h.drift(gpa, moved);
    try h.stream_n(200_000);
    // The mechanism actually ran, or the gate is watching nothing.
    try testing.expect(h.transplant_events > 0);
    try testing.expect(h.transplanted > 100);

    // Bank a region by hand and transplant it into another: the prediction
    // must not move anywhere, by any amount.
    var st = rng.Stream.region(77, 0x7B00, 0);
    var before: [300]f32 = undefined;
    var pts: [300][3]f32 = undefined;
    for (&pts, &before) |*p, *b| {
        p.* = .{ st.unit(), st.unit(), st.unit() };
        b.* = (try h.predict(p.*))[0];
    }
    var donor: u32 = 0;
    while (donor < h.parent.regions.len and !h.refined[donor]) donor += 1;
    try testing.expect(donor < h.parent.regions.len);
    try h.bank(donor);
    try testing.expect(h.pool.items.len > 0);
    var target: u32 = @intCast(h.parent.regions.len - 1);
    while (target > 0 and h.refined[target]) target -= 1;
    try h.transplant(target);

    for (pts, before) |p, b| {
        try testing.expectEqual(@as(u32, @bitCast(b)), @as(u32, @bitCast(try h.predict(p))));
    }
    std.debug.print("\n  G28: {d} kernels transplanted over {d} events; banking region {d} into {d} moved the prediction at 300 probes by exactly nothing ({s})\n", .{ h.transplanted, h.transplant_events, donor, target, @tagName(builtin.mode) });
}

// ── MARL-9's gate ─────────────────────────────────────────────────────
//
// The fixture question, settled. Every earlier drift was the same shell
// translated, so "capacity grows with the number of moves" could not be
// distinguished from "capacity grows with the amount of distinct
// structure" — the two were the same number. They are not the same thing,
// and separating them overturns the reading of three earlier phases.

test "G29 capacity is paid per THING LEARNED, not per change: revisiting a known world costs progressively less" {
    // Two arms, the same six moves and the same budget. CYCLING alternates
    // between two worlds — six changes, two worlds of distinct structure.
    // WALKING visits six different ones. If the model paid per change they
    // would grow alike.
    //
    // They do not. Measured over six moves at 100 000 exemplars each, the
    // walking arm's marginal cost is flat at about 2 100 kernels a move
    // while the cycling arm's decays — 2 140, 971, 745, 527, 368, 371 —
    // and over twelve moves it falls to 159. The cycling arm is also MORE
    // accurate, which is what a world with half the distinct structure
    // should be.
    //
    // This overturns MARL-6's hysteresis reading. That measured ONE round
    // trip and saw the return spike at full size, and I wrote "no memory,
    // only accumulation". The spike is the transient; the settled state is
    // not it. Over repeated visits both the error and the marginal cost
    // improve, so there IS memory — and it explains MARL-8's failure
    // completely: the model already reuses capacity on recurrence, without
    // any mechanism, so an explicit transplant had nothing left to add.
    //
    // MUTATION: the cycling arm given distinct worlds — it becomes the
    // walking arm and the comparison collapses. That is a fixture mutation
    // rather than a code one, which is correct here, because the claim
    // under test is about what the fixture can tell apart.
    const gpa = testing.allocator;
    const walk = [_][3]f32{
        .{ 0, -0.30, 0 },         .{ 0.12, 0, 0.22 },
        .{ -0.12, -0.20, -0.16 }, .{ 0, 0.14, 0.26 },
    };
    var pop: [2]usize = undefined;
    var err: [2]f32 = undefined;
    for ([_]bool{ false, true }, 0..) |cycling, arm| {
        var tp = TruthParams{ .sharpness = 2 };
        var h = try Hierarchy.init(gpa, .{ .truth = tp, .responsibility = 3 }, .{});
        defer h.deinit();
        try h.stream_n(60_000);
        var i: u32 = 1;
        while (i <= 4) : (i += 1) {
            tp.shift = if (cycling)
                (if (i % 2 == 1) [3]f32{ 0, -0.30, 0 } else [3]f32{ 0, 0, 0 })
            else
                walk[i - 1];
            try h.drift(gpa, tp);
            try h.stream_n(60_000);
        }
        const pr = try probesOf(gpa, tp, 0xB0B, 2048);
        defer gpa.free(pr.p);
        defer gpa.free(pr.y);
        pop[arm] = h.child.kernels.items.len;
        err[arm] = try h.rms(pr.p, pr.y, null);
    }
    // Seeing the same world twice is materially cheaper than seeing two.
    const ratio = @as(f32, @floatFromInt(pop[1])) / @as(f32, @floatFromInt(pop[0]));
    try testing.expect(ratio < thresholds.MARL9_RECURRENCE);
    // And the comparison is fair: the easier world is not being paid for
    // in accuracy.
    try testing.expect(err[1] <= err[0] * thresholds.MARL9_FAIR);
    std.debug.print("\n  G29: four moves — walking to four worlds costs {d} kernels at RMS {d:.5}; cycling between two costs {d} at {d:.5} ({d:.3}× the capacity) ({s})\n", .{ pop[0], err[0], pop[1], err[1], ratio, @tagName(builtin.mode) });
}
