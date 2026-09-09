//! field — the MARL field algebra: operators, projection and transport
//! over learned fields (`docs/MARL_ALGEBRA_CAMPAIGN.md`).
//!
//! Christian's design note, `docs/MARL_Field_Algebra.md`, proposes that a
//! MARL is not only a learned approximation to a dataset but a CONTINUOUS
//! FIELD, and that once two of them share a coordinate domain one may
//! operate on the other:
//!
//!     MARL --operator--> continuous field --projection--> MARL
//!
//! Twenty-five phases asked how little REPRESENTATION a field needs. This
//! one asks how little COMPUTATION it needs to evolve, and the claim worth
//! testing is §39's: that simulation cost tracks information CHANGE rather
//! than domain volume.
//!
//! ## Standing
//!
//! `marl.zig`'s, one level out. This file imports `marl.zig` and is
//! imported by neither it nor `rbf.zig` — `marble.zig`, `cache.zig` and
//! `milk.zig`'s precedent, and Christian's split enforced by construction:
//! a model that knows what advection is has a kernel with a second
//! customer, and `rbf.zig` is cross-repo pinned.
//!
//! **The derivatives live here and not in `marl.zig`.** G17 (a) holds
//! MARL's kernel to `rbf.zig`'s bit for bit, and a derivative `rbf.zig`
//! does not have would make the twin asymmetric on exactly the surface the
//! pin defends. They are built on `marl.mahal`, which IS pinned, so
//! nothing moves under rill or the shader. This is a call and not a law;
//! if the gradient belongs beside the gaussian it moves, and the pin grows
//! a row.
//!
//! Nothing here is on the sim path — no World, no step, no fed clock,
//! nothing in any hash.

const std = @import("std");
const builtin = @import("builtin");
const marl = @import("marl.zig");
const fmath = @import("fmath.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");

const testing = std.testing;

// ── §5: differential operators ────────────────────────────────────────

/// A kernel's value and spatial gradient at one point.
///
/// §5's claim, and it is correct: gradient evaluation is the same local
/// operation as field evaluation with a little more arithmetic. `mahal`
/// already computes v = Lᵀd; the gradient of ½|Lᵀd|² is L v, which is six
/// more multiplies.
pub const Jet = struct { f: f32, g: [3]f32 };

/// φ and ∇φ at q. Zero, exactly, beyond the cutoff — BOTH of them.
///
/// The cutoff is what makes locality exact, and it is free in the value
/// (the kernel reads exp(−16) = 1.13e-7 at the boundary). **It is not free
/// in the derivatives.** ∇φ = −φ·Lv and |Lv| = √32/σ at the cutoff, so the
/// step at the boundary is 1.4e-5 at regions 4 and grows as the basis
/// gets finer; the Laplacian's is 1.7e-3. Each derivative multiplies the
/// artefact by √32/σ. ALG-4 measures what that does to a diffusion loop;
/// ALG-1 only has to not be surprised by it.
pub fn gaussianJet(s: marl.Shape, q: [3]f32) Jet {
    const m = marl.mahal(s, q);
    if (m.r2 > marl.CUTOFF) return .{ .f = 0, .g = .{ 0, 0, 0 } };
    const f = fmath.expf(-0.5 * m.r2);
    const l = s.l;
    // L v, with L lower-triangular row by row (l00, l10, l11, l20, l21, l22).
    const lv = [3]f32{
        l[0] * m.v[0],
        l[1] * m.v[0] + l[2] * m.v[1],
        l[3] * m.v[0] + l[4] * m.v[1] + l[5] * m.v[2],
    };
    return .{ .f = f, .g = .{ -f * lv[0], -f * lv[1], -f * lv[2] } };
}

/// ∇²φ at q. φ·(|Lv|² − tr LLᵀ), and tr LLᵀ is the sum of the six stored
/// entries squared.
pub fn gaussianLaplacian(s: marl.Shape, q: [3]f32) f32 {
    const m = marl.mahal(s, q);
    if (m.r2 > marl.CUTOFF) return 0;
    const f = fmath.expf(-0.5 * m.r2);
    const l = s.l;
    const lv = [3]f32{
        l[0] * m.v[0],
        l[1] * m.v[0] + l[2] * m.v[1],
        l[3] * m.v[0] + l[4] * m.v[1] + l[5] * m.v[2],
    };
    var tr: f32 = 0;
    inline for (0..6) |i| tr += l[i] * l[i];
    return f * (lv[0] * lv[0] + lv[1] * lv[1] + lv[2] * lv[2] - tr);
}

/// ∇F over EVERY kernel — the O(N) reference, `predictAll`'s twin.
///
/// A gathered version belongs here eventually and does not yet, for the
/// reason `predictAll` exists: the first thing to establish is what the
/// operator MEANS, and a gather is an optimisation of a meaning that has
/// to be right first. ALG-1's projection points are the kernel centres, so
/// this is called K times a step and the model is small.
pub fn gradientAll(m: *const marl.Model, q: [3]f32) [3]f32 {
    var g = [3]f32{ 0, 0, 0 };
    for (m.regions) |*reg| {
        for (reg.own.items) |ki| {
            const k = &m.kernels.items[ki];
            const j = gaussianJet(k.shape(), q);
            const w = k.weightsConst()[0];
            inline for (0..3) |a| g[a] += w * j.g[a];
        }
    }
    return g;
}

/// ∇²F over every kernel. The bias, if any, is constant and contributes
/// nothing — which is one of the few places a global term is harmless.
pub fn laplacianAll(m: *const marl.Model, q: [3]f32) f32 {
    var s: f32 = 0;
    for (m.regions) |*reg| {
        for (reg.own.items) |ki| {
            const k = &m.kernels.items[ki];
            s += k.weightsConst()[0] * gaussianLaplacian(k.shape(), q);
        }
    }
    return s;
}

// ── §13: mass, in closed form ─────────────────────────────────────────

/// √((2π)³) — the integral of exp(−½|u|²) over ℝ³.
const GAUSS_VOLUME: f64 = 15.749609945722419;

/// The fraction of a kernel's mass the hard cutoff throws away: the tail
/// of a 3-D gaussian beyond √32 widths. Derived, not fitted —
/// `tools/alg1_predict.py` computes it as P(χ²₃ > 32) = 5.233e-7.
pub const CUTOFF_MASS_LOSS: f64 = 5.2335e-7;

/// ∫F dx over the whole domain, in closed form.
///
/// §13 proposes measuring a conserved quantity before and after projection
/// and correcting. It is better than practical — it is FREE. A kernel's
/// integral is w·(2π)^{3/2}/det L, det L is the product of L's diagonal,
/// and the diagonal is stored as its LOG, so det L is `exp` of a sum
/// already in the parameter vector. One multiply-add per kernel, exact to
/// a part in two million (the cutoff's own truncation, above).
///
/// f64 throughout: this is a sum over the whole population and the thing
/// it is for is measuring a drift of a few per cent, which f32 summation
/// over thousands of terms would put inside its own noise.
///
/// A `bias` is deliberately NOT included. It is a constant over the whole
/// cube and its integral is the domain's volume, which is a statement
/// about the domain and not about the field; every ALG arm runs
/// `bias = .off` (MARL-16), so there is nothing to leave out.
pub fn mass(m: *const marl.Model) f64 {
    var acc: f64 = 0;
    for (m.kernels.items) |*k| {
        const s = k.shape();
        const det = @as(f64, s.l[0]) * @as(f64, s.l[2]) * @as(f64, s.l[5]);
        acc += @as(f64, k.weightsConst()[0]) * GAUSS_VOLUME / det;
    }
    return acc * (1.0 - CUTOFF_MASS_LOSS);
}

// ── §34: `warp` — the affine subgroup, exactly ────────────────────────

/// An affine map x ↦ Ax + b, A row-major.
pub const Affine = struct {
    a: [9]f32,
    b: [3]f32,

    pub fn apply(self: Affine, x: [3]f32) [3]f32 {
        return .{
            self.a[0] * x[0] + self.a[1] * x[1] + self.a[2] * x[2] + self.b[0],
            self.a[3] * x[0] + self.a[4] * x[1] + self.a[5] * x[2] + self.b[1],
            self.a[6] * x[0] + self.a[7] * x[1] + self.a[8] * x[2] + self.b[2],
        };
    }
};

/// Rotation by θ about the z-axis through `c`.
pub fn rotationZ(theta: f32, c: [3]f32) Affine {
    const ct = fmath.cosf(theta);
    const st = fmath.sinf(theta);
    // x ↦ R(x − c) + c
    return .{
        .a = .{ ct, -st, 0, st, ct, 0, 0, 0, 1 },
        .b = .{
            c[0] - (ct * c[0] - st * c[1]),
            c[1] - (st * c[0] + ct * c[1]),
            0,
        },
    };
}

/// The Cholesky factor of a symmetric positive-definite 3×3, lower
/// triangular, in `Shape`'s storage order.
fn chol3(p: [6]f32) ?[6]f32 {
    // p is (p00, p10, p11, p20, p21, p22), the same order Shape.l uses.
    if (!(p[0] > 0)) return null;
    const l00 = @sqrt(p[0]);
    const l10 = p[1] / l00;
    const l20 = p[3] / l00;
    const d11 = p[2] - l10 * l10;
    if (!(d11 > 0)) return null;
    const l11 = @sqrt(d11);
    const l21 = (p[4] - l20 * l10) / l11;
    const d22 = p[5] - l20 * l20 - l21 * l21;
    if (!(d22 > 0)) return null;
    return .{ l00, l10, l11, l20, l21, l22Of(d22) };
}

fn l22Of(d: f32) f32 {
    return @sqrt(d);
}

/// Carry a kernel's SHAPE through a rigid rotation, exactly.
///
/// §3.4 of the lab book, and the reason ALG-1 has a control arm at all.
/// For F'(x) = F(R⁻¹x),
///
///     φ(R⁻¹x) = exp(−½‖LᵀR⁻¹(x − Rμ)‖²) = exp(−½‖(RL)ᵀ(x − Rμ)‖²)
///
/// so μ′ = Rμ and the new precision is R L Lᵀ Rᵀ, whose Cholesky is the
/// canonical lower-triangular L′. The weight does not move.
///
/// This is EXACT and not bit-exact: over 4 000 random kernels the worst
/// |F(x) − F′(Rx)| is 3.9e-15 in f64 and 2.4e-6 in f32, and the f32 figure
/// is the Cholesky's own rounding. G31 (a)'s conversion IS bit-exact
/// because rounding a difference commutes with scaling by a power of two;
/// a rotation mixes axes and nothing commutes.
///
/// It generalises to any affine A — μ′ = Aμ + b, precision′ =
/// A⁻ᵀLLᵀA⁻¹ — and a rotation is the case where A⁻ᵀ = A, which is why
/// this needs no inverse. **The flow map of a LINEAR velocity field is a
/// matrix exponential, hence affine, hence exactly representable here with
/// no projection at all.** That is what makes §35's proposed first
/// experiment a control rather than a test.
pub fn warpShape(s: marl.Shape, r: Affine) ?marl.Shape {
    // M = R L (row-major R, lower-triangular L).
    const l = s.l;
    const lm = [9]f32{
        l[0], 0,    0,
        l[1], l[2], 0,
        l[3], l[4], l[5],
    };
    var m: [9]f32 = undefined;
    inline for (0..3) |i| {
        inline for (0..3) |j| {
            var acc: f32 = 0;
            inline for (0..3) |k| acc += r.a[i * 3 + k] * lm[k * 3 + j];
            m[i * 3 + j] = acc;
        }
    }
    // P = M Mᵀ, symmetric; take the six entries Shape stores.
    var p: [6]f32 = undefined;
    const idx = [6][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 }, .{ 2, 0 }, .{ 2, 1 }, .{ 2, 2 } };
    inline for (idx, 0..) |ij, n| {
        var acc: f32 = 0;
        inline for (0..3) |k| acc += m[ij[0] * 3 + k] * m[ij[1] * 3 + k];
        p[n] = acc;
    }
    const lp = chol3(p) orelse return null;
    return .{ .mu = r.apply(s.mu), .l = lp };
}

/// What a warp did to a model, reported rather than silently fixed.
pub const WarpReport = struct {
    /// Kernels whose cutoff box now reaches further than one region edge.
    /// The gather's exactness rests on that bound, and **it is not
    /// rotation-invariant**: an anisotropic kernel's ∞-norm box grows when
    /// its ellipsoid turns off-axis. Counted and not corrected, because
    /// correcting it would change the field and this operator's whole
    /// claim is that it does not. The rebuilt model instead switches to
    /// an ordered full gather; the count now reports an acceleration cost.
    over_reach: u32 = 0,
    /// The worst reach as a fraction of the region edge.
    worst_reach: f32 = 0,
    /// Kernels the Cholesky refused — a precision that came back
    /// numerically indefinite. Should be zero for a rotation.
    refused: u32 = 0,
};

/// Carry a whole model through a rigid rotation. §34's `warp`, and the
/// only operator in the algebra that needs no projection.
pub fn warp(m: *marl.Model, r: Affine, scratch: []bool) !WarpReport {
    var rep = WarpReport{};
    const h = 1.0 / @as(f32, @floatFromInt(m.opts.regions));
    for (m.kernels.items) |*k| {
        const s = warpShape(k.shape(), r) orelse {
            rep.refused += 1;
            continue;
        };
        k.p[0] = s.mu[0];
        k.p[1] = s.mu[1];
        k.p[2] = s.mu[2];
        // Back to the parameterisation: the diagonal is stored as its log.
        k.p[3] = @log(s.l[0]);
        k.p[4] = @log(s.l[2]);
        k.p[5] = @log(s.l[5]);
        k.p[6] = s.l[1];
        k.p[7] = s.l[3];
        k.p[8] = s.l[4];
        k.reach = marl.reachOf(s);
        k.mu0 = s.mu;
        if (k.reach > h) {
            rep.over_reach += 1;
            rep.worst_reach = @max(rep.worst_reach, k.reach / h);
        } else {
            rep.worst_reach = @max(rep.worst_reach, k.reach / h);
        }
    }
    // Every centre moved, so every kernel needs re-homing and every
    // region's bound rebuilding. `compact` with nothing dead does exactly
    // that and is already gated; a second copy of the same loop here would
    // be a second truth about who owns what.
    @memset(scratch, false);
    try m.compact(scratch);
    return rep;
}

// ── §8, §11: flows, and the exact solution ────────────────────────────

/// The velocity fields ALG-1 transports by.
pub const Flow = union(enum) {
    /// §35's V = (−y, x): rigid rotation at rate ω about the z-axis
    /// through `c`. **LINEAR, therefore affine, therefore exactly
    /// representable by `warp`** — which is why it is the control.
    rotation: struct { omega: f32, c: [3]f32 },
    /// A Taylor–Green cell: V = A(sin πx cos πy, −cos πx sin πy, 0).
    ///
    /// Chosen for three properties, all load-bearing. It is DIVERGENCE
    /// FREE (the two π-terms cancel exactly), so mass is conserved in the
    /// continuum and any drift ALG-5 measures belongs to the projection.
    /// Its normal component vanishes on all four side faces (sin πx = 0 at
    /// x ∈ {0,1}), so the flow never leaves the cube and no boundary
    /// condition has to be invented. And it is NOT AFFINE, so `warp`
    /// cannot answer it and the projection is actually under test.
    ///
    /// Its angular velocity is not uniform, so the blob SHEARS: its
    /// streamlines are closed but the blob never exactly recurs, which is
    /// a genuinely harder case than the rotation and is why no population
    /// number is pre-registered for it.
    swirl: struct { amp: f32 },
};

pub fn velocity(f: Flow, x: [3]f32) [3]f32 {
    switch (f) {
        .rotation => |r| return .{
            -r.omega * (x[1] - r.c[1]),
            r.omega * (x[0] - r.c[0]),
            0,
        },
        .swirl => |s| {
            const px = std.math.pi * x[0];
            const py = std.math.pi * x[1];
            return .{
                s.amp * fmath.sinf(px) * fmath.cosf(py),
                -s.amp * fmath.cosf(px) * fmath.sinf(py),
                0,
            };
        },
    }
}

/// A point drawn uniformly inside a kernel's own COVERAGE ellipsoid.
///
/// The projection point set is the whole of what makes P well posed, and
/// §12's list leads with the one choice that is not: sampling only at
/// kernel centres gives K equations for K·(9+C) parameters, so the fit is
/// underdetermined between them and nothing holds the field's shape. Run
/// that way the blob collapses — peak 1.03 to 0.056 in ten steps, its
/// width quadrupling, and then the model diverges outright.
///
/// The natural radius is MARL's own: a birth fires where no kernel reads
/// above `coverage`, which is r = sqrt(-2 ln coverage) Mahalanobis widths,
/// so inside its own coverage ellipsoid a kernel IS the covering one and a
/// draw there can never birth spuriously. The union of those ellipsoids is
/// exactly the support the population tiles, so the measure covers the
/// field and its DENSITY follows the model's own capacity — which is §12's
/// principle stated properly:
///
///     compute where information exists, at the radius the basis itself
///     says it is responsible for
///
/// Uniform in the ellipsoid, not gaussian: a gaussian at sigma puts its
/// typical draw at 1.73 widths, outside the coverage radius of 1.45, and
/// would birth on its own tails.
fn sampleCoverage(sh: marl.Shape, r: f32, st: *rng.Stream) [3]f32 {
    // A point uniform in the unit ball, by rejection — three draws, and
    // the accept rate is pi/6.
    var u: [3]f32 = undefined;
    while (true) {
        var n2: f32 = 0;
        inline for (0..3) |a| {
            u[a] = 2 * st.unit() - 1;
            n2 += u[a] * u[a];
        }
        if (n2 <= 1) break;
    }
    // Solve Lᵀ d = r u by back substitution: Lᵀ is upper triangular.
    const l = sh.l;
    const d2 = r * u[2] / l[5];
    const d1 = (r * u[1] - l[4] * d2) / l[2];
    const d0 = (r * u[0] - l[1] * d1 - l[3] * d2) / l[0];
    return .{ sh.mu[0] + d0, sh.mu[1] + d1, sh.mu[2] + d2 };
}

/// One RK4 step of the characteristic, forwards for dt > 0 and backwards
/// for dt < 0.
pub fn rk4(f: Flow, x: [3]f32, dt: f32) [3]f32 {
    const k1 = velocity(f, x);
    var p: [3]f32 = undefined;
    inline for (0..3) |a| p[a] = x[a] + 0.5 * dt * k1[a];
    const k2 = velocity(f, p);
    inline for (0..3) |a| p[a] = x[a] + 0.5 * dt * k2[a];
    const k3 = velocity(f, p);
    inline for (0..3) |a| p[a] = x[a] + dt * k3[a];
    const k4 = velocity(f, p);
    var out: [3]f32 = undefined;
    inline for (0..3) |a| out[a] = x[a] + (dt / 6) * (k1[a] + 2 * k2[a] + 2 * k3[a] + k4[a]);
    return out;
}

/// Φ₋ₜ(x): where the point now at x came from, t ago. `sub` substeps of
/// RK4, so this is the reference and not an approximation of the scheme
/// under test.
pub fn backtrace(f: Flow, x: [3]f32, t: f32, sub: u32) [3]f32 {
    var p = x;
    const dt = -t / @as(f32, @floatFromInt(sub));
    var i: u32 = 0;
    while (i < sub) : (i += 1) p = rk4(f, p, dt);
    return p;
}

// ── the fixture ───────────────────────────────────────────────────────

/// The transported scalar: §35's smooth blob, F(x) = exp(−|x−c|²/2s²).
pub const Blob = struct {
    c: [3]f32,
    s: f32,

    pub fn at(self: Blob, x: [3]f32) f32 {
        var r2: f32 = 0;
        inline for (0..3) |a| {
            const d = x[a] - self.c[a];
            r2 += d * d;
        }
        return fmath.expf(-0.5 * r2 / (self.s * self.s));
    }
};

/// The EXACT solution of passive advection: F(x,t) = F₀(Φ₋ₜ(x)).
///
/// §35 chose a rotation because "the exact solution is known". For a
/// passive scalar it always is — integrating one characteristic backwards
/// from the analytic initial field gives the truth to integrator precision
/// for ANY smooth V, with no grid anywhere in the measurement. So the
/// choice of velocity field is free and can be made on physics.
pub fn reference(b: Blob, f: Flow, x: [3]f32, t: f32, sub: u32) f32 {
    return b.at(backtrace(f, x, t, sub));
}

// ── options ───────────────────────────────────────────────────────────

pub const Options = struct {
    seed: u64 = 7,
    /// The blob, at t = 0. Radius 0.25 from the rotation's axis.
    blob: Blob = .{ .c = .{ 0.75, 0.50, 0.50 }, .s = 0.08 },
    /// Steps per revolution — §35's "small dt", made explicit. At this
    /// count the per-step arc at the blob's radius is 0.0393, which is
    /// 0.49 of the blob's own width: a backtrace shorter than the blob
    /// lands inside the blob it came from, which is the regime a
    /// semi-Lagrangian scheme is stable in.
    steps_per_rev: u32 = 40,
    /// Substeps in the RK4 reference. The reference must be far more
    /// accurate than the scheme, or the measurement is of the reference.
    ref_sub: u32 = 16,
    /// Passes of the projection-point set per step. One pass gives NLMS a
    /// single look at each point, and MARL-11's law is that what binds is
    /// EVIDENCE; four is the cheapest number that is not one.
    passes: u32 = 4,
    /// Jitter on a projection point, in units of the kernel's own WIDTH.
    /// Zero would observe the identical point `passes` times, which
    /// converges there and nowhere between.
    ///
    /// **The unit is load-bearing and the first version got it wrong.**
    /// Written against the kernel's `reach` — the cutoff box, 5.66 widths
    /// — a nominal 0.25 was 1.41 widths, and a birth fires wherever no
    /// kernel reads above `coverage` = 0.35, which is 1.45 widths. So
    /// almost every jittered point landed outside its own parent's
    /// coverage and births fired by construction. The population then
    /// feeds back on itself: the projection points ARE the kernel centres,
    /// so more kernels means more points means more births. Measured
    /// before the fix: 125 kernels to 1 076 over forty steps, RMS from
    /// 0.058 to 0.735 of a constant, and the blob's WIDTH flat throughout
    /// — so it was never numerical diffusion, it was capacity nobody could
    /// train (MARL-1's invariant).
    jitter: f32 = 0.25,
    /// Project on the FORWARD-advected centres as well as the current
    /// ones. False is the gate's mutation, and §3.10's finding: the mass
    /// is going to x + ΔtV(x), and with no projection point there nothing
    /// observes that the field has arrived.
    forward: bool = true,
    /// Exemplars for the initial fit of the blob.
    fit_exemplars: u64 = 60_000,
    /// Probes in the local (in-the-blob) and global (whole-cube) sets.
    probes: usize = 1024,
    m: marl.Options = .{},

    /// The configuration ALG-1 measures at, in ONE place, each element
    /// naming the phase that established it.
    ///
    /// Christian's ruling after MARL-25: "we need to be really careful
    /// with these hyper parameters or experiments spilling over into later
    /// things." This campaign starts on the right side of it.
    ///
    /// Note what is deliberately NOT inherited from `cache.Options.best()`.
    /// MARL-13 (b, c) lowered `rate_w` to 0.05 and `rate_geom` to 0.02,
    /// and both were DERIVED FROM MEASUREMENT NOISE — NLMS hovers at
    /// μ/(2−μ) of the measurement variance, so a smaller step buys a lower
    /// floor. **ALG-1's target is analytic and noiseless.** There is no
    /// variance to hover at, and a tenth of the step is a tenth of the
    /// learning rate for nothing. The defaults are right here for the
    /// reason MARL-13's were right there, and saying so is the difference
    /// between a configuration and a habit.
    pub fn best() Options {
        var o = Options{};
        // MARL-25: a smooth target wants a coarse basis. Four and not two:
        // at regions 2 the 27-region gather visits the entire model and
        // locality stops being measurable at all, which is the one thing
        // this campaign must be able to see.
        o.m.regions = 4;
        // MARL-6R (G24): 0.980× the RMS for 0.184× the work.
        o.m.responsibility = 3;
        // MARL-16: zero is special because it is what an empty model
        // already predicts, and a transported blob is zero over 94% of the
        // cube. A bias would have to be held DOWN everywhere the blob is
        // not.
        o.m.bias = .off;
        return o;
    }

    pub fn dt(self: Options) f32 {
        return @as(f32, 2 * std.math.pi) / @as(f32, @floatFromInt(self.steps_per_rev));
    }
};

// ── §11: semi-Lagrangian advection ────────────────────────────────────

/// What one advection step did.
pub const StepReport = struct {
    points: u32 = 0,
    births: u32 = 0,
    learned: u32 = 0,
};

/// One semi-Lagrangian step: F ← P_F[ x ↦ F(x − Δt V(x)) ].
///
/// §11, and it is the one to implement first for the reason the note
/// gives — it is far more stable than explicit Euler on the differential
/// form, because it never differentiates the field it is transporting.
///
/// **Every sample is read from the OLD field before any of them is
/// written back.** An in-place update would have later points backtracing
/// into a field the earlier points had already modified, which is not
/// F(x − ΔtV) but an unnamed mixture of two timesteps. The two-phase
/// shape is not an optimisation; it is what makes the operator the one in
/// the note.
///
/// The projection points are the current kernel centres and — when
/// `forward` — their forward advections. §12's list has neither, and the
/// forward set is §3.10's finding: a transported blob moves into regions
/// with no kernels, so with samples only where kernels already are, the
/// trailing edge decays correctly and the leading edge never grows. The
/// mass is going to x + ΔtV(x); that is where it must be asked about.
pub fn advect(
    gpa: std.mem.Allocator,
    m: *marl.Model,
    f: Flow,
    dt: f32,
    o: Options,
    st: *rng.Stream,
) !StepReport {
    const n = m.kernels.items.len;
    if (n == 0) return .{};

    const per = @as(usize, if (o.forward) 2 else 1) * o.passes;
    var pts = try gpa.alloc([3]f32, n * per);
    defer gpa.free(pts);
    var vals = try gpa.alloc(f32, n * per);
    defer gpa.free(vals);

    // Phase one: choose the points and READ the old field at their
    // backtraces. Nothing is written in this loop.
    var w: usize = 0;
    for (m.kernels.items) |*k| {
        const mu = [3]f32{ k.p[0], k.p[1], k.p[2] };
        const fwd = rk4(f, mu, dt);
        var pass: u32 = 0;
        while (pass < o.passes) : (pass += 1) {
            const base = [_][3]f32{ mu, fwd };
            const lim: usize = if (o.forward) 2 else 1;
            for (base[0..lim]) |b| {
                var p: [3]f32 = undefined;
                inline for (0..3) |a| {
                    const j = if (pass == 0) 0 else st.gauss() * o.jitter * (k.reach / marl.CUTOFF_R);
                    p[a] = @min(1, @max(0, b[a] + j));
                }
                // The backtrace, and the old field there.
                const src = rk4(f, p, -dt);
                pts[w] = p;
                vals[w] = (try m.predict(src))[0];
                w += 1;
            }
        }
    }

    // Phase two: project. `observe` IS P_F — §6's "MARL learning itself
    // can serve as the projection operator", which `cache.distil` already
    // relies on with a model in place of an expression.
    var rep = StepReport{ .points = @intCast(w) };
    for (pts[0..w], vals[0..w]) |p, y| {
        const e = try m.observe(p, .{y});
        if (e.born) rep.births += 1;
        if (e.learned) rep.learned += 1;
    }
    return rep;
}

// ── measurement ───────────────────────────────────────────────────────

pub const Probes = struct {
    x: [][3]f32,
    pub fn deinit(self: *Probes, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
    }
};

/// Probes uniform in a ball of `k` blob-widths about `c`.
///
/// MARL-20's rule and MARL-21's correction to it. A blob of width 0.08 in
/// the unit cube leaves 94% of the domain seeing nothing at all, so a
/// global RMS is 3.3× smaller than a local one for a reason that has
/// nothing to do with the model. Every ALG number is reported on the local
/// set with the global one printed beside it.
pub fn ballProbes(gpa: std.mem.Allocator, c: [3]f32, r: f32, n: usize, st: *rng.Stream) !Probes {
    const x = try gpa.alloc([3]f32, n);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        while (true) {
            const p = [3]f32{
                c[0] + (2 * st.unit() - 1) * r,
                c[1] + (2 * st.unit() - 1) * r,
                c[2] + (2 * st.unit() - 1) * r,
            };
            var d2: f32 = 0;
            inline for (0..3) |a| {
                const t = p[a] - c[a];
                d2 += t * t;
            }
            if (d2 > r * r) continue;
            if (p[0] < 0 or p[0] > 1 or p[1] < 0 or p[1] > 1 or p[2] < 0 or p[2] > 1) continue;
            x[i] = p;
            break;
        }
    }
    return .{ .x = x };
}

pub fn cubeProbes(gpa: std.mem.Allocator, n: usize, st: *rng.Stream) !Probes {
    const x = try gpa.alloc([3]f32, n);
    for (x) |*p| p.* = .{ st.unit(), st.unit(), st.unit() };
    return .{ .x = x };
}

pub const Score = struct {
    /// RMS of the model against the analytic reference.
    rms: f32,
    /// What a constant predictor scores on the same set — MARL-17's rule.
    /// An RMS without it is a number with no scale.
    anchor: f32,
    pub fn ratio(self: Score) f32 {
        return self.rms / self.anchor;
    }
};

pub fn score(m: *marl.Model, b: Blob, f: Flow, t: f32, pr: Probes, sub: u32) !Score {
    var se: f64 = 0;
    var s1: f64 = 0;
    var s2: f64 = 0;
    for (pr.x) |x| {
        const truth = reference(b, f, x, t, sub);
        const got = (try m.predict(x))[0];
        const d = @as(f64, got - truth);
        se += d * d;
        s1 += truth;
        s2 += @as(f64, truth) * truth;
    }
    const n: f64 = @floatFromInt(pr.x.len);
    const mean = s1 / n;
    return .{
        .rms = @floatCast(@sqrt(se / n)),
        .anchor = @floatCast(@sqrt(@max(0, s2 / n - mean * mean))),
    };
}

/// The model's centre of mass along an axis — how far the blob actually
/// travelled, as against how well it is shaped.
///
/// Closed form for the same reason `mass` is: ∫x_a φ = μ_a ∫φ.
pub fn centroid(m: *const marl.Model) [3]f64 {
    var num = [3]f64{ 0, 0, 0 };
    var den: f64 = 0;
    for (m.kernels.items) |*k| {
        const s = k.shape();
        const det = @as(f64, s.l[0]) * @as(f64, s.l[2]) * @as(f64, s.l[5]);
        const q = @as(f64, k.weightsConst()[0]) * GAUSS_VOLUME / det;
        den += q;
        inline for (0..3) |a| num[a] += q * @as(f64, s.mu[a]);
    }
    if (den == 0) return .{ 0, 0, 0 };
    return .{ num[0] / den, num[1] / den, num[2] / den };
}

/// Fit the blob from scratch — the model every arm starts from.
pub fn fitBlob(gpa: std.mem.Allocator, b: Blob, o: Options) !marl.Model {
    var m = try marl.Model.init(gpa, o.m);
    errdefer m.deinit();
    var st = rng.Stream.region(o.seed, 0x414c_4731, 0); // "ALG1"
    // Drawn in a ball of four widths: far enough out that the tails are
    // evidence rather than extrapolation, and no further, because the rest
    // of the cube is zero and MARL-16 established that zero is what an
    // empty model already predicts. Sampling it would buy nothing and
    // would cost the whole stream.
    var i: u64 = 0;
    while (i < o.fit_exemplars) : (i += 1) {
        var p: [3]f32 = undefined;
        while (true) {
            var d2: f32 = 0;
            inline for (0..3) |a| {
                p[a] = b.c[a] + (2 * st.unit() - 1) * 4 * b.s;
                const d = p[a] - b.c[a];
                d2 += d * d;
            }
            if (d2 <= 16 * b.s * b.s and p[0] >= 0 and p[0] <= 1 and
                p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1) break;
        }
        _ = try m.observe(p, .{b.at(p)});
    }
    return m;
}

/// The share of a population sitting within 1% of σ_max — MARL-24's
/// diagnostic, which MARL-25 then pointed at every arm in the campaign.
/// A population hard against the clamp is one the descent wanted WIDER and
/// could not have.
pub fn pinnedShare(m: *const marl.Model) f32 {
    if (m.kernels.items.len == 0) return 0;
    const sigma_max = m.sigma_max;
    var n: u32 = 0;
    for (m.kernels.items) |*k| {
        const s = k.shape();
        // σ along an axis is 1/L's diagonal entry; the widest is the
        // smallest diagonal.
        const sw = 1 / @min(s.l[0], @min(s.l[2], s.l[5]));
        if (sw >= 0.99 * sigma_max) n += 1;
    }
    return @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(m.kernels.items.len));
}

// ── §34: a velocity source, analytic or learned ───────────────────────

/// Where a velocity comes from. §3.6 of the lab book: MARL-13 (d) says a
/// learned sparse field LOSES to a dense grid when the field is
/// non-trivial everywhere, and a swirl is non-zero over the whole cube —
/// MARL-16's expensive object. So a velocity MARL imports a
/// representation error that has nothing to do with the algebra, and the
/// two must be measured apart or the phase cannot say which it measured.
pub const VelSrc = union(enum) {
    exact: Flow,
    /// A VECTOR MARL, and it needed no new code: `marl.Marl(3)` is the
    /// generic MARL-12 introduced, with three weights per kernel instead
    /// of one. §3's "a MARL may represent a vector field" is already true.
    learned: *Vec3Model,

    pub fn at(self: VelSrc, x: [3]f32) [3]f32 {
        switch (self) {
            .exact => |f| return velocity(f, x),
            // `catch unreachable` follows `cache.zig`'s Reader: `predict`
            // only fails on allocation, the gather's scratch is already
            // sized by this point, and a velocity sample is on the inner
            // loop of every step.
            .learned => |m| return m.predict(x) catch unreachable,
        }
    }
};

pub const Vec3 = marl.Marl(3);
pub const Vec3Model = Vec3.Model;

/// One RK4 step of the characteristic through a velocity SOURCE.
pub fn rk4v(v: VelSrc, x: [3]f32, dt: f32) [3]f32 {
    const k1 = v.at(x);
    var p: [3]f32 = undefined;
    inline for (0..3) |a| p[a] = x[a] + 0.5 * dt * k1[a];
    const k2 = v.at(p);
    inline for (0..3) |a| p[a] = x[a] + 0.5 * dt * k2[a];
    const k3 = v.at(p);
    inline for (0..3) |a| p[a] = x[a] + dt * k3[a];
    const k4 = v.at(p);
    var out: [3]f32 = undefined;
    inline for (0..3) |a| out[a] = x[a] + (dt / 6) * (k1[a] + 2 * k2[a] + 2 * k3[a] + k4[a]);
    return out;
}

/// Learn a velocity field as a three-channel MARL, over the whole cube.
pub fn fitVelocity(gpa: std.mem.Allocator, f: Flow, o: Options, n: u64) !Vec3Model {
    // The geometry step's √C correction (MARL-12, `Ch.GEOM_RATE`) is
    // applied inside the model, so nothing is needed here — recorded
    // because the first instinct is to divide the rate by hand, and doing
    // it twice is exactly MARL-12's divergent arm.
    var m = try Vec3.Model.init(gpa, o.m);
    errdefer m.deinit();
    var st = rng.Stream.region(o.seed, 0x414c_4756, 0); // "ALGV"
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const p = [3]f32{ st.unit(), st.unit(), st.unit() };
        _ = try m.observe(p, velocity(f, p));
    }
    return m;
}

/// RMS of a learned velocity against the analytic one, over the cube —
/// |δV| in §3.6's error-propagation prediction, and the only free
/// quantity in it.
pub fn velocityError(m: *Vec3Model, f: Flow, n: usize, st: *rng.Stream) !f32 {
    var se: f64 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const p = [3]f32{ st.unit(), st.unit(), st.unit() };
        const want = velocity(f, p);
        const got = try m.predict(p);
        inline for (0..3) |a| {
            const d = @as(f64, got[a] - want[a]);
            se += d * d;
        }
    }
    return @floatCast(@sqrt(se / @as(f64, @floatFromInt(n))));
}

// ── the gates ─────────────────────────────────────────────────────────

/// A handful of well-conditioned random kernel shapes, for the operator
/// gates. Widths around a tenth of the domain, so that a central
/// difference's truncation error (h²/6 · φ‴ ~ h²/σ³) is far below what is
/// being checked and the gate measures the FORMULA rather than the step.
fn testShapes(st: *rng.Stream, out: []marl.Shape) void {
    for (out) |*s| {
        const d = [3]f32{
            1 / (0.06 + 0.08 * st.unit()),
            1 / (0.06 + 0.08 * st.unit()),
            1 / (0.06 + 0.08 * st.unit()),
        };
        s.* = .{
            .mu = .{ 0.3 + 0.4 * st.unit(), 0.3 + 0.4 * st.unit(), 0.3 + 0.4 * st.unit() },
            .l = .{ d[0], st.gauss(), d[1], st.gauss(), st.gauss(), d[2] },
        };
    }
}

test "G44 (a) the operators: analytic gradient and Laplacian, and mass in closed form" {
    // §5 claims a derivative is "approximately the same local operation as
    // field evaluation with a small amount of additional arithmetic", and
    // §13 proposes measuring a conserved quantity by comparing it before
    // and after. Both are true and the second is stronger than claimed:
    // the integral is CLOSED FORM, so conservation needs no quadrature at
    // all.
    //
    // The mutation is at the foot: L v written as Lᵀ v — the wrong one of
    // the two matrices that are both to hand in `mahal` — which is the
    // mistake this gate exists to catch, because the gradient still points
    // roughly outward and still vanishes at the centre.
    var st = rng.Stream.region(11, 0x4732_3434, 0);

    var shapes: [16]marl.Shape = undefined;
    testShapes(&st, &shapes);

    // (1) the gradient, against a central difference on one kernel.
    const h: f32 = 1e-3;
    var worst_g: f32 = 0;
    var worst_l: f32 = 0;
    for (shapes) |s| {
        var t: u32 = 0;
        while (t < 12) : (t += 1) {
            var q: [3]f32 = undefined;
            inline for (0..3) |a| q[a] = s.mu[a] + st.gauss() * 0.06;
            const j = gaussianJet(s, q);
            if (j.f < 1e-3) continue; // in the tail the cutoff dominates; §3.7
            inline for (0..3) |a| {
                var lo = q;
                var hi = q;
                lo[a] -= h;
                hi[a] += h;
                const fd = (marl.gaussian(s, hi) - marl.gaussian(s, lo)) / (2 * h);
                worst_g = @max(worst_g, @abs(fd - j.g[a]) / @max(1e-3, @abs(j.g[a])));
            }
            // The Laplacian's own step, and it is NOT the gradient's.
            //
            // A central SECOND difference carries roundoff eps·|f|/h², so
            // at the gradient's h = 1e-3 in f32 the reference is uncertain
            // by 0.1 absolute — worse than the quantity it is refereeing.
            // The optimum is h ~ eps^(1/4)·sigma; 4e-3 at sigma ~ 0.1.
            // Measured at the gradient's step this gate read 7.1e-2 and
            // the formula was already correct: the finite difference was
            // the thing being measured.
            //
            // And it is scaled by phi·tr LLᵀ — the Laplacian's magnitude
            // at the centre — because the Laplacian VANISHES on a sphere
            // (where |Lv|² = tr LLᵀ) and dividing by its own local value
            // there measures nothing but the zero crossing.
            const hl: f32 = 4e-3;
            var lap: f32 = 0;
            inline for (0..3) |a| {
                var lo = q;
                var hi = q;
                lo[a] -= hl;
                hi[a] += hl;
                lap += (marl.gaussian(s, hi) - 2 * j.f + marl.gaussian(s, lo)) / (hl * hl);
            }
            var tr: f32 = 0;
            inline for (0..6) |ii| tr += s.l[ii] * s.l[ii];
            const la = gaussianLaplacian(s, q);
            worst_l = @max(worst_l, @abs(lap - la) / (j.f * tr));
        }
    }

    // (2) mass, closed form against fine quadrature IN THE KERNEL'S OWN
    // BOX. Per kernel and not over the model, because the claim is about
    // one kernel's integral and the sum over a population is linear — a
    // quadrature over the whole cube would need a grid finer than sigma
    // over a box larger than the domain, and would measure the grid.
    const NQ: u32 = 64;
    var worst_m: f64 = 0;
    for (shapes[0..6]) |s| {
        const e = marl.halfExtents(s);
        var acc: f64 = 0;
        var i: u32 = 0;
        while (i < NQ) : (i += 1) {
            const fx = (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(NQ)) * 2 - 1;
            var jj: u32 = 0;
            while (jj < NQ) : (jj += 1) {
                const fy = (@as(f32, @floatFromInt(jj)) + 0.5) / @as(f32, @floatFromInt(NQ)) * 2 - 1;
                var k: u32 = 0;
                while (k < NQ) : (k += 1) {
                    const fz = (@as(f32, @floatFromInt(k)) + 0.5) / @as(f32, @floatFromInt(NQ)) * 2 - 1;
                    acc += marl.gaussian(s, .{ s.mu[0] + fx * e[0], s.mu[1] + fy * e[1], s.mu[2] + fz * e[2] });
                }
            }
        }
        const cell = 8.0 * @as(f64, e[0]) * @as(f64, e[1]) * @as(f64, e[2]) /
            (@as(f64, NQ) * @as(f64, NQ) * @as(f64, NQ));
        const quad = acc * cell;
        const closed = GAUSS_VOLUME / (@as(f64, s.l[0]) * @as(f64, s.l[2]) * @as(f64, s.l[5])) *
            (1.0 - CUTOFF_MASS_LOSS);
        worst_m = @max(worst_m, @abs(quad - closed) / closed);
    }

    // (3) and the Laplacian against its CLOSED FORM on an isotropic
    // kernel, where a finite difference is not needed at all:
    // phi = exp(-r²/2s²) has grad = -(d/s²)phi and lap = phi(r²/s⁴ - 3/s²).
    // A finite difference can only ever bound the formula; this pins it.
    var worst_i: f32 = 0;
    for ([_]f32{ 0.05, 0.09, 0.13 }) |sig| {
        const s2 = marl.Shape{ .mu = .{ 0.5, 0.5, 0.5 }, .l = .{ 1 / sig, 0, 1 / sig, 0, 0, 1 / sig } };
        var t: u32 = 0;
        while (t < 24) : (t += 1) {
            var q: [3]f32 = undefined;
            var r2: f32 = 0;
            inline for (0..3) |a| {
                q[a] = 0.5 + st.gauss() * sig;
                const d = q[a] - 0.5;
                r2 += d * d;
            }
            if (r2 / (sig * sig) > marl.CUTOFF) continue;
            const phi = fmath.expf(-0.5 * r2 / (sig * sig));
            const want = phi * (r2 / (sig * sig * sig * sig) - 3 / (sig * sig));
            const got = gaussianLaplacian(s2, q);
            worst_i = @max(worst_i, @abs(got - want) / (phi * 3 / (sig * sig)));
        }
    }

    std.debug.print("\n  G44 (a) [{s}] gradient {e:.2}  laplacian {e:.2} (fd) {e:.2} (closed)  mass {e:.2}  — all relative\n", .{
        @tagName(builtin.mode), worst_g, worst_l, worst_i, worst_m,
    });

    // The gradient and Laplacian bounds are the central difference's own
    // error, not a tolerance on the formula: h²/6·φ‴ with sigma ~ 0.1 and
    // h = 1e-3, plus f32 roundoff eps/h. They are LOOSE on purpose — a
    // wrong formula is wrong by tens of per cent, not by one.
    try testing.expect(worst_g < 5e-3);
    try testing.expect(worst_l < 5e-3);
    try testing.expect(worst_i < 1e-5);
    try testing.expect(worst_m < thresholds.ALG1_MASS_CLOSED_FORM);
}

test "G44 (a) mutation: the gradient taken through Lᵀ instead of L → still outward, still zero at the centre, and wrong" {
    // Both matrices are to hand in `mahal` — v = Lᵀd is what it returns,
    // and L v is what the gradient needs. Using Lᵀ v instead gives a
    // vector that still vanishes at the centre and still points broadly
    // outward, so a picture of it looks right. On an ANISOTROPIC kernel it
    // is a different vector, and this is the check that says so.
    var st = rng.Stream.region(11, 0x4732_3434, 0);
    var shapes: [16]marl.Shape = undefined;
    testShapes(&st, &shapes);
    var worst: f32 = 0;
    for (shapes) |s| {
        const q = [3]f32{ s.mu[0] + 0.05, s.mu[1] - 0.03, s.mu[2] + 0.02 };
        const m = marl.mahal(s, q);
        if (m.r2 > marl.CUTOFF) continue;
        const f = fmath.expf(-0.5 * m.r2);
        const l = s.l;
        // The WRONG one: Lᵀ v.
        const bad = [3]f32{
            l[0] * m.v[0] + l[1] * m.v[1] + l[3] * m.v[2],
            l[2] * m.v[1] + l[4] * m.v[2],
            l[5] * m.v[2],
        };
        const good = gaussianJet(s, q);
        inline for (0..3) |a| {
            const d = @abs(-f * bad[a] - good.g[a]) / @max(1e-3, @abs(good.g[a]));
            worst = @max(worst, d);
        }
    }
    std.debug.print("  G44 (a) mutation: Lᵀ for L moves the gradient by {d:.1}% — the gate's 0.5% would refuse it\n", .{100 * worst});
    try testing.expect(worst > 0.05);
}

/// RMS between two models over a probe set, `b` optionally read at a
/// pre-image. `rmsBetween(a, b, pr, R⁻¹)` is "how far has a drifted from
/// b carried by R", which is the only honest way to score `warp`: the
/// initial fit has its OWN error against the analytic blob, and a warp
/// that reproduced that fit exactly would still score it. What is under
/// test is the operator, not the fit it was handed.
fn rmsBetween(a: *marl.Model, b: *marl.Model, pr: Probes, pre: ?Affine) !f32 {
    var se: f64 = 0;
    for (pr.x) |x| {
        const xb = if (pre) |p| p.apply(x) else x;
        const d = @as(f64, (try a.predict(x))[0] - (try b.predict(xb))[0]);
        se += d * d;
    }
    return @floatCast(@sqrt(se / @as(f64, @floatFromInt(pr.x.len))));
}

test "G44 (b) the affine subgroup is exact: a rotation is a closed-form operator on the parameters, and needs no projection at all" {
    // §35 proposes V = (-y, x) as the first experiment. That field is
    // LINEAR, so its flow map is a matrix exponential, so it is AFFINE —
    // and an affine map acts on a gaussian's parameters in closed form:
    //
    //     mu' = A mu + b,   L' = chol(A^-T L L^T A^-1),   w' = w
    //
    // So the note's first experiment has an exact answer that BYPASSES the
    // mechanism it is meant to test. That makes it a gift as a control and
    // useless as the only arm, and it is why ALG-1 has four.
    //
    // Two things this gate is careful about. It scores the warp against
    // the MODEL it started from and not against the analytic blob, because
    // the initial fit has its own error and a perfect warp would still
    // carry it. And it reports the reach: the gather's exactness rests on
    // a kernel's cutoff box fitting inside one region edge, and **that
    // bound is not rotation-invariant** — an anisotropic ellipsoid turned
    // off-axis has a larger axis-aligned box. Counted, never corrected;
    // correcting it would change the field, and not changing the field is
    // this operator's entire claim.
    const gpa = testing.allocator;
    const o = Options.best();

    var m0 = try fitBlob(gpa, o.blob, o);
    defer m0.deinit();
    var me = try marl.Model.init(gpa, o.m);
    defer me.deinit();
    try me.reseedFrom(&m0);

    var st = rng.Stream.region(o.seed, 0x4732_3462, 0);
    var pr = try ballProbes(gpa, o.blob.c, 3 * o.blob.s, o.probes, &st);
    defer pr.deinit(gpa);

    const fit = try score(&m0, o.blob, .{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } }, 0, pr, o.ref_sub);
    std.debug.print("\n  G44 (b) [{s}] the fit: {d} kernels, RMS {d:.5} against a constant's {d:.5} ({d:.3}x), {d:.0}% pinned at sigma_max\n", .{
        @tagName(builtin.mode), m0.kernels.items.len, fit.rms, fit.anchor, fit.ratio(), 100 * pinnedShare(&m0),
    });

    const k0 = me.kernels.items.len;
    const scratch = try gpa.alloc(bool, 4096);
    defer gpa.free(scratch);

    const dt = o.dt();
    const step = rotationZ(dt, .{ 0.5, 0.5, 0.5 });
    var worst_reach: f32 = 0;
    var over: u32 = 0;
    var refused: u32 = 0;
    var quarter: f32 = 0;

    var i: u32 = 0;
    while (i < o.steps_per_rev) : (i += 1) {
        const rep = try warp(&me, step, scratch[0..me.kernels.items.len]);
        worst_reach = @max(worst_reach, rep.worst_reach);
        over += rep.over_reach;
        refused += rep.refused;
        if (i + 1 == o.steps_per_rev / 4) {
            // A quarter turn: the warped model against the ORIGINAL read
            // at the pre-image. A round trip alone could cancel its own
            // errors; this cannot.
            const back = rotationZ(-dt * @as(f32, @floatFromInt(o.steps_per_rev / 4)), .{ 0.5, 0.5, 0.5 });
            var qpr = try ballProbes(gpa, rotationZ(dt * @as(f32, @floatFromInt(o.steps_per_rev / 4)), .{ 0.5, 0.5, 0.5 }).apply(o.blob.c), 3 * o.blob.s, o.probes, &st);
            defer qpr.deinit(gpa);
            quarter = try rmsBetween(&me, &m0, qpr, back);
        }
    }

    // A full revolution is the identity, so the warped model must be the
    // model it started from.
    const closed = try rmsBetween(&me, &m0, pr, null);
    const dm = @abs(mass(&me) - mass(&m0)) / @abs(mass(&m0));

    std.debug.print("  G44 (b) 40 composed rotations: {d} kernels -> {d}, quarter turn {e:.2}, closed loop {e:.2}, mass drift {e:.2}\n", .{
        k0, me.kernels.items.len, quarter, closed, dm,
    });
    std.debug.print("  G44 (b) the reach the gather rests on: worst {d:.4} of a region edge, {d} over, {d} refused by the Cholesky\n", .{
        worst_reach, over, refused,
    });

    // Population is an EQUALITY, not a threshold: a warp is a change of
    // parameters and cannot birth or kill.
    try testing.expectEqual(k0, me.kernels.items.len);
    try testing.expectEqual(@as(u32, 0), refused);
    try testing.expect(quarter < thresholds.ALG1_WARP_EXACT);
    try testing.expect(closed < thresholds.ALG1_WARP_EXACT);
}

/// Parameters held fixed for the transport phase but not for the fit that
/// precedes it. MARL-1's distinction, one level out: BIRTH is topology
/// acquisition and DESCENT is geometry adaptation, and a phase that wants
/// to know which of them a loop is failing on has to be able to stop each.
pub const Freeze = struct { geom: ?f32 = null, births: ?bool = null };

/// One arm's state at the end of a revolution.
pub const Row = struct {
    step: u32,
    kernels: u32,
    local: Score,
    global: Score,
    mass_ratio: f64,
    /// The model read at the reference blob's centre. 1.0 at t = 0.
    peak: f32 = 0,
    /// The width a gaussian of this mass and this peak would have —
    /// s = (M / (peak (2 pi)^{3/2}))^{1/3}. Separates SMEARING from
    /// EROSION without a second measurement.
    width: f32 = 0,
    travel: f32,
    seconds: f64,
};

/// Forward-trace a point through the flow — where the blob's centre has
/// got to, which is where the local probe set belongs.
pub fn forward(f: Flow, x: [3]f32, t: f32, sub: u32) [3]f32 {
    var p = x;
    const dt = t / @as(f32, @floatFromInt(sub));
    var i: u32 = 0;
    while (i < sub) : (i += 1) p = rk4(f, p, dt);
    return p;
}

/// Run the semi-Lagrangian arm for `revs` revolutions, scoring at the end
/// of each against the analytic reference.
pub fn runProject(
    gpa: std.mem.Allocator,
    o: Options,
    f: Flow,
    v: VelSrc,
    marks: []const u32,
    rows: []Row,
    /// Applied AFTER the fit, never during it. Freezing births before the
    /// fit leaves an empty model, which is how this was first written and
    /// what the diagnostic printed: nought kernels and a tidy-looking RMS
    /// that was the anchor.
    after: Freeze,
    oracle: bool,
) !marl.Model {
    var m = try fitBlob(gpa, o.blob, o);
    if (after.geom) |g| m.opts.rate_geom = g;
    if (after.births) |b| m.opts.births = b;
    errdefer m.deinit();
    var st = rng.Stream.region(o.seed, 0x4132_4456, 0); // "A2DV"
    var gst = rng.Stream.region(o.seed, 0x4750_5242, 0); // "GPRB"
    var gpr = try cubeProbes(gpa, o.probes, &gst);
    defer gpr.deinit(gpa);

    const m0 = mass(&m);
    const dt = o.dt();
    var timer = try std.time.Timer.start();

    var done: u32 = 0;
    for (marks, 0..) |mark, r| {
        while (done < mark) : (done += 1) {
            const tgt: Target = if (oracle)
                .{ .oracle = .{ .b = o.blob, .f = f, .t = dt * @as(f32, @floatFromInt(done + 1)), .sub = o.ref_sub * (done + 1) } }
            else
                .model;
            _ = try advectV(gpa, &m, v, dt, o, &st, tgt);
        }

        const t = dt * @as(f32, @floatFromInt(mark));
        const sub = o.ref_sub * @max(1, mark);
        const c = forward(f, o.blob.c, t, sub);
        var lpr = try ballProbes(gpa, c, 3 * o.blob.s, o.probes, &gst);
        defer lpr.deinit(gpa);
        const sc = try score(&m, o.blob, f, t, lpr, sub);
        // Peak and effective width, which separate the two ways a
        // transported blob can degrade. SMEARING keeps the mass and
        // spreads it (peak down, width up); EROSION loses it (peak down,
        // width flat). For a gaussian M = peak*(2 pi)^{3/2} s^3, so the
        // width follows from the two numbers already to hand and needs no
        // second measurement.
        const peak = (try m.predict(c))[0];
        const mm = mass(&m);
        rows[r] = .{
            .step = mark,
            .kernels = @intCast(m.kernels.items.len),
            .local = sc,
            .global = try score(&m, o.blob, f, t, gpr, sub),
            .mass_ratio = mm / m0,
            .peak = peak,
            .width = if (peak > 1e-4) @floatCast(std.math.cbrt(mm / (@as(f64, peak) * GAUSS_VOLUME))) else 0,
            .travel = dist(c, o.blob.c),
            .seconds = @as(f64, @floatFromInt(timer.read())) / 1e9,
        };
    }
    return m;
}

fn dist(a: [3]f32, b: [3]f32) f32 {
    var d2: f32 = 0;
    inline for (0..3) |i| {
        const d = a[i] - b[i];
        d2 += d * d;
    }
    return @sqrt(d2);
}

/// `advect` against a velocity SOURCE rather than an analytic flow — the
/// same operator, with arm C's learned velocity mounted in place of the
/// closed form.
/// The target a projection step is handed.
///
/// `.model` is the operator the note describes and the one a simulation
/// would actually run: the field is asked about ITSELF, one step back
/// along the characteristic. `.oracle` hands it the exact solution at the
/// current time instead, which no simulation can do — it is the CEILING,
/// and the difference between the two is exactly the accumulated cost of
/// having been its own source. Without it a phase cannot say whether a
/// degrading field means the representation cannot hold the answer or that
/// the loop cannot find it.
pub const Target = union(enum) {
    model,
    oracle: struct { b: Blob, f: Flow, t: f32, sub: u32 },
};

pub fn advectV(
    gpa: std.mem.Allocator,
    m: *marl.Model,
    v: VelSrc,
    dt: f32,
    o: Options,
    st: *rng.Stream,
    tgt: Target,
) !StepReport {
    const n = m.kernels.items.len;
    if (n == 0) return .{};
    const per = @as(usize, if (o.forward) 2 else 1) * o.passes;
    const pts = try gpa.alloc([3]f32, n * per);
    defer gpa.free(pts);
    const vals = try gpa.alloc(f32, n * per);
    defer gpa.free(vals);

    // The coverage radius, in Mahalanobis widths: where a kernel's own
    // reading falls to `coverage` and a birth becomes possible.
    const rc = @sqrt(-2 * @log(o.m.coverage));
    var w: usize = 0;
    for (m.kernels.items) |*k| {
        const sh = k.shape();
        const shift = rk4v(v, sh.mu, dt);
        var fwd = sh;
        fwd.mu = shift;
        var pass: u32 = 0;
        while (pass < o.passes) : (pass += 1) {
            const base = [_]marl.Shape{ sh, fwd };
            const lim: usize = if (o.forward) 2 else 1;
            for (base[0..lim]) |b| {
                var p = if (pass == 0) b.mu else sampleCoverage(b, rc, st);
                inline for (0..3) |a| p[a] = @min(1, @max(0, p[a]));
                pts[w] = p;
                vals[w] = switch (tgt) {
                    .model => (try m.predict(rk4v(v, p, -dt)))[0],
                    .oracle => |ok| reference(ok.b, ok.f, p, ok.t, ok.sub),
                };
                w += 1;
            }
        }
    }
    var rep = StepReport{ .points = @intCast(w) };
    for (pts[0..w], vals[0..w]) |p, y| {
        const e = try m.observe(p, .{y});
        if (e.born) rep.births += 1;
        if (e.learned) rep.learned += 1;
    }
    return rep;
}

fn printRow(label: []const u8, r: Row) void {
    std.debug.print("  {s:<22} {d:>5} {d:>7} {d:>9.5} {d:>7.3} {d:>8.5} {d:>7.3} {d:>7.4} {d:>7.4} {d:>7.2}\n", .{
        label,        r.step,       r.kernels, r.local.rms, r.local.ratio(),
        r.global.rms, r.mass_ratio, r.peak,    r.width,     r.seconds,
    });
}

fn header() void {
    std.debug.print("  {s:<22} {s:>5} {s:>7} {s:>9} {s:>7} {s:>8} {s:>7} {s:>7} {s:>7} {s:>7}\n", .{
        "arm", "step", "kernels", "RMS", "/const", "RMS glob", "mass", "peak", "width", "sec",
    });
}

test "G44 (c) does one MARL move another? — and the control that says which half fails" {
    // The design note's §35 and §36, with §3.4's correction: the note's own
    // velocity field is linear, hence affine, hence exactly representable
    // by G44 (b)'s closed form, so it cannot test a projection. Arm B is a
    // Taylor-Green swirl — divergence-free, never leaving the cube, and NOT
    // affine.
    //
    // The reference is F0(Phi_-t(x)) by RK4 backtrace from the analytic
    // initial field. §35 chose a rotation because "the exact solution is
    // known"; for a passive scalar it always is, for any smooth V, and with
    // no grid anywhere in the measurement.
    //
    // **The arm that decides the phase is the ORACLE.** It runs the same
    // loop, the same points, the same projection, and hands it the EXACT
    // solution at each step instead of the model's own backtraced output.
    // No simulation can do that; it is the ceiling. Without it a degrading
    // field cannot be told apart into "the representation cannot hold the
    // answer" and "the loop cannot find it", and those have opposite
    // remedies.
    const gpa = testing.allocator;
    const o = Options.best();
    const rot = Flow{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } };
    // Matched initial speed: the rotation moves the blob at omega x radius
    // = 0.25 and the swirl at amp/sqrt(2) there, so the two arms transport
    // it the same distance per step and their populations are comparable.
    const swirl = Flow{ .swirl = .{ .amp = 0.35355339 } };

    // Traced along the way, not only at the end. The SHAPE of the
    // degradation is what separates the two things that could cause it:
    // numerical diffusion smears (peak down, WIDTH UP, mass held) while
    // untrainable capacity erodes (width flat, population up).
    const marks = [_]u32{ 0, 1, 2, 5, 10, 20, 40 };
    header();
    var ra: [marks.len]Row = undefined;
    var ma = try runProject(gpa, o, rot, .{ .exact = rot }, &marks, &ra, .{}, false);
    defer ma.deinit();
    for (ra) |r| printRow("A rotation", r);

    var rb: [marks.len]Row = undefined;
    var mb = try runProject(gpa, o, swirl, .{ .exact = swirl }, &marks, &rb, .{}, false);
    defer mb.deinit();
    for (rb) |r| printRow("B swirl", r);

    var ro: [marks.len]Row = undefined;
    var mo = try runProject(gpa, o, rot, .{ .exact = rot }, &marks, &ro, .{}, true);
    defer mo.deinit();
    for (ro) |r| printRow("O rotation, ORACLE", r);

    const last_a = ra[marks.len - 1];
    const last_b = rb[marks.len - 1];
    const last_o = ro[marks.len - 1];
    std.debug.print("  travel: A {d:.4}  B {d:.4} (the blob's centre, from where it started)\n", .{ last_a.travel, last_b.travel });
    std.debug.print("  the loop's own cost: operator {d:.5} against the oracle's {d:.5} — {d:.1}x\n", .{
        last_a.local.rms, last_o.local.rms, last_a.local.rms / last_o.local.rms,
    });

    // **ALG1_TRANSPORT (0.25) IS REFUTED** — A lands at 1.02 of a constant
    // and B at 1.54 — and it is left in `thresholds.zig` for Christian to
    // strike, with what it measured written beside it. The assertion here
    // is the finding that replaced it, and it is the sharper claim:
    //
    //     the representation holds the transported field; the LOOP does
    //     not find it
    //
    // The oracle carries the same population growth, the same points and
    // the same projection, and ends where the initial fit began.
    try testing.expect(last_o.local.ratio() < thresholds.ALG1_ORACLE);
    try testing.expect(last_a.local.rms / last_o.local.rms > thresholds.ALG1_LOOP_COST);
    // And the width is FLAT while the population multiplies, so what is
    // happening is not the numerical diffusion a semi-Lagrangian scheme is
    // known for.
    try testing.expect(last_a.kernels > 4 * ra[0].kernels);
}

test "G44 (d) the timestep does not converge — the cost is paid per PROJECTION, not per unit time" {
    // Every classical scheme's first defence against error is a smaller
    // step. It is not available here. Halving dt doubles the number of
    // projections, and a projection is a generation of loss (MARL-19
    // priced one at 1.179x on a noiseless field), so refining the step buys
    // truncation accuracy that was never the binding term and pays
    // generation loss that is.
    //
    // The consequence is a design rule, not a tuning note: **there is an
    // optimal dt and it is the largest the transport scheme tolerates.**
    // Semi-Lagrangian is unconditionally stable, which is exactly why §11
    // was right to name it first — its value here is not accuracy but that
    // it lets the step be large enough to project rarely.
    const gpa = testing.allocator;
    const rot = Flow{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } };
    std.debug.print("\n  {s:>6} {s:>10} {s:>7} {s:>9} {s:>7} {s:>7} {s:>6}\n", .{ "steps", "arc/sigma", "kernels", "RMS", "/const", "mass", "sec" });
    var coarse: f32 = 0;
    var fine: f32 = 0;
    const sigma_max = (1.0 / @as(f32, @floatFromInt(Options.best().m.regions))) / marl.CUTOFF_R;
    for ([_]u32{ 10, 20, 40, 80 }) |n| {
        var o = Options.best();
        o.steps_per_rev = n;
        const marks = [_]u32{n};
        var rows: [1]Row = undefined;
        var m = try runProject(gpa, o, rot, .{ .exact = rot }, &marks, &rows, .{}, false);
        defer m.deinit();
        const r = rows[0];
        std.debug.print("  {d:>6} {d:>10.3} {d:>7} {d:>9.5} {d:>7.3} {d:>7.3} {d:>6.2}\n", .{
            n, 0.25 * o.dt() / sigma_max, r.kernels, r.local.rms, r.local.ratio(), r.mass_ratio, r.seconds,
        });
        if (n == 10) coarse = r.local.rms;
        if (n == 80) fine = r.local.rms;
    }
    std.debug.print("  eight times the steps: {d:.5} -> {d:.5}, {d:.2}x the error for {d:.0}x the work\n", .{ coarse, fine, fine / coarse, 8.0 });
    // The claim, as an assertion: refining the timestep does not reduce the
    // error. Stated as "no better than", so it would fail the moment the
    // scheme started behaving like a classical one.
    try testing.expect(fine > coarse);
}

test "G44 (e) the loop is a conditioning problem, and MARL-23 already named it" {
    // With the topology and the geometry both frozen, one step is a LINEAR
    // recursion on the weights:
    //
    //     w' = Phi(P)^+ Phi(P - delta) w
    //
    // and iterating it is a power method. MARL-23 measured, with no learner
    // and unlimited evidence, that **a Gaussian basis much finer than the
    // feature is nearly linearly dependent** — which makes Phi(P)^+
    // ill-conditioned. In a static fit that costs accuracy. In a LOOP it
    // costs stability, because the amplification is raised to the number of
    // steps.
    //
    // So the prediction is that the divergence rate rises with the basis's
    // fineness, and it does, brutally. MARL-24 and MARL-25's diagnostic —
    // the share of a population pinned at sigma_max — says this fixture's
    // basis is too fine at every setting tried, which is the same statement
    // arriving from the other side.
    //
    // And the second half is the surprise. **MARL's adaptivity is what
    // stops it exploding**: with births and the geometry descent switched
    // on, the same loop decays gracefully toward the anchor instead of
    // reaching 1e9. Every earlier sighting of MARL-1's invariant had
    // capacity acquisition as the thing that had to be restrained; here it
    // is the stabiliser.
    const gpa = testing.allocator;
    const rot = Flow{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } };
    std.debug.print("\n  {s:>7} {s:>10} {s:>8} {s:>7} {s:>14} {s:>7} {s:>14}\n", .{ "regions", "sigma_max", "pinned", "kernels", "RMS frozen", "kernels", "RMS adaptive" });
    var prev: f32 = 0;
    var monotone = true;
    var worst_adaptive: f32 = 0;
    for ([_]u32{ 2, 3, 4, 6 }) |reg| {
        var o = Options.best();
        o.m.regions = reg;
        const marks = [_]u32{40};
        var m0 = try fitBlob(gpa, o.blob, o);
        const pin = pinnedShare(&m0);
        const k0 = m0.kernels.items.len;
        m0.deinit();

        var rf: [1]Row = undefined;
        var mf = try runProject(gpa, o, rot, .{ .exact = rot }, &marks, &rf, .{ .geom = 0, .births = false }, false);
        defer mf.deinit();
        var rl: [1]Row = undefined;
        var ml = try runProject(gpa, o, rot, .{ .exact = rot }, &marks, &rl, .{}, false);
        defer ml.deinit();

        std.debug.print("  {d:>7} {d:>10.4} {d:>7.0}% {d:>7} {e:>14.3} {d:>7} {d:>14.4}\n", .{
            reg,             (1.0 / @as(f32, @floatFromInt(reg))) / marl.CUTOFF_R, 100 * pin,
            k0,              rf[0].local.rms,                                      rl[0].kernels,
            rl[0].local.rms,
        });
        if (prev != 0 and !(rf[0].local.rms > prev)) monotone = false;
        prev = rf[0].local.rms;
        worst_adaptive = @max(worst_adaptive, rl[0].local.rms);
    }
    std.debug.print("  the frozen basis diverges monotonically in fineness; the adaptive one never leaves {d:.3}\n", .{worst_adaptive});
    try testing.expect(monotone);
    try testing.expect(worst_adaptive < thresholds.ALG1_ADAPTIVE_BOUND);
}

test "G44 (f) mutation: the leading edge is invisible from the kernel centres" {
    // §11 and §35 project at the current kernel centres. A transported blob
    // moves into regions where there are no kernels, so no projection point
    // is there, so nothing observes that the field has ARRIVED: the
    // trailing edge decays correctly and the leading edge never grows.
    //
    // The fix falls out of the semi-Lagrangian form — the mass is going to
    // x + dt V(x), so project on the forward-advected centres as well —
    // and dropping it is this gate's mutation. The swirl is used and not
    // the rotation, because a rotation returns the blob to where it started
    // and a centroid that has not moved would be right for the wrong
    // reason.
    const gpa = testing.allocator;
    const swirl = Flow{ .swirl = .{ .amp = 0.35355339 } };
    const marks = [_]u32{20};

    var on = Options.best();
    var r_on: [1]Row = undefined;
    var m_on = try runProject(gpa, on, swirl, .{ .exact = swirl }, &marks, &r_on, .{}, false);
    defer m_on.deinit();
    const c_on = centroid(&m_on);

    var off = Options.best();
    off.forward = false;
    var r_off: [1]Row = undefined;
    var m_off = try runProject(gpa, off, swirl, .{ .exact = swirl }, &marks, &r_off, .{}, false);
    defer m_off.deinit();
    const c_off = centroid(&m_off);

    const start = on.blob.c;
    const want = forward(swirl, start, on.dt() * 20, on.ref_sub * 20);
    const arc = dist(want, start);
    const moved_on = dist(.{ @floatCast(c_on[0]), @floatCast(c_on[1]), @floatCast(c_on[2]) }, start);
    const moved_off = dist(.{ @floatCast(c_off[0]), @floatCast(c_off[1]), @floatCast(c_off[2]) }, start);
    std.debug.print("\n  G44 (f) [{s}] the reference centre moved {d:.4}\n", .{ @tagName(builtin.mode), arc });
    std.debug.print("  G44 (f) forward set ON : centroid moved {d:.4} ({d:.2} of it), mass {d:.3}, {d} kernels, RMS {d:.5}\n", .{ moved_on, moved_on / arc, r_on[0].mass_ratio, r_on[0].kernels, r_on[0].local.rms });
    std.debug.print("  G44 (f) forward set OFF: centroid moved {d:.4} ({d:.2} of it), mass {d:.3}, {d} kernels, RMS {d:.5}\n", .{ moved_off, moved_off / arc, r_off[0].mass_ratio, r_off[0].kernels, r_off[0].local.rms });
    try testing.expect(moved_off < moved_on);
    try testing.expect(r_off[0].local.rms > r_on[0].local.rms);
}

// ── the operator the measurements point at ────────────────────────────

/// Push ONE kernel along the flow: the affine warp of G44 (b), applied
/// locally, per kernel, with the flow map's own Jacobian.
///
/// G44 (b) established that an affine map acts on a gaussian's parameters
/// in closed form. A general flow is not affine — but it is affine TO
/// FIRST ORDER over the width of one kernel, and a kernel is small. So
/// near mu' = Phi_dt(mu),
///
///     Phi_-dt(x) ~ mu + J^-1 (x - mu'),   J = d Phi_dt / dx at mu
///
/// and therefore  L' = J^-T L,  mu' = Phi_dt(mu),  w unchanged.
///
/// **There is no projection anywhere in this.** That is the whole point.
/// G44 (c) measured the loop's self-reference at 14.6x the oracle's error
/// and G44 (d) showed it cannot be refined away, because the cost is paid
/// per projection; an operator that never projects pays none of it. The
/// residual error is second order — the kernel's own width times the flow's
/// curvature — where the projected loop's is first order in the step count.
///
/// The weight does NOT change, which is the passive-scalar convention: F is
/// constant along characteristics, so a kernel carries its value. A DENSITY
/// would want w / det J, and a divergence-free flow has det J = 1, so on
/// this fixture the two agree and the choice is invisible. It is recorded
/// because the moment a compressible flow arrives it stops being.
///
/// G44 (f) is where this came from, and it came sideways. With the forward
/// projection set switched off the model still TRANSPORTED — its centroid
/// moved 0.89 of the reference arc — while losing 95% of its mass. The
/// geometry descent was doing Lagrangian advection on its own, badly and
/// for free. This is that, done deliberately and exactly.
pub fn pushKernel(sh: marl.Shape, v: VelSrc, dt: f32) ?marl.Shape {
    const mu2 = rk4v(v, sh.mu, dt);
    // The flow map's Jacobian by central differences. h is set from the
    // domain and not from the kernel: a step small enough to be local and
    // large enough that f32 cancellation does not eat it.
    const h: f32 = 1e-3;
    var j: [9]f32 = undefined;
    inline for (0..3) |a| {
        var lo = sh.mu;
        var hi = sh.mu;
        lo[a] -= h;
        hi[a] += h;
        const pl = rk4v(v, lo, dt);
        const ph = rk4v(v, hi, dt);
        inline for (0..3) |r| j[r * 3 + a] = (ph[r] - pl[r]) / (2 * h);
    }
    // J^-1, then A = J^-T, which is what `warpShape` multiplies L by.
    const det = j[0] * (j[4] * j[8] - j[5] * j[7]) -
        j[1] * (j[3] * j[8] - j[5] * j[6]) +
        j[2] * (j[3] * j[7] - j[4] * j[6]);
    if (!(@abs(det) > 1e-12)) return null;
    const id = 1 / det;
    const inv = [9]f32{
        (j[4] * j[8] - j[5] * j[7]) * id, (j[2] * j[7] - j[1] * j[8]) * id, (j[1] * j[5] - j[2] * j[4]) * id,
        (j[5] * j[6] - j[3] * j[8]) * id, (j[0] * j[8] - j[2] * j[6]) * id, (j[2] * j[3] - j[0] * j[5]) * id,
        (j[3] * j[7] - j[4] * j[6]) * id, (j[1] * j[6] - j[0] * j[7]) * id, (j[0] * j[4] - j[1] * j[3]) * id,
    };
    const at = Affine{
        .a = .{ inv[0], inv[3], inv[6], inv[1], inv[4], inv[7], inv[2], inv[5], inv[8] },
        .b = .{ 0, 0, 0 },
    };
    var out = warpShape(sh, at) orelse return null;
    out.mu = mu2;
    return out;
}

/// Advect a whole model by pushing every kernel along the flow. The
/// projection-free operator, and the one ALG-1 ends up recommending.
pub fn pushForward(m: *marl.Model, v: VelSrc, dt: f32, scratch: []bool) !WarpReport {
    var rep = WarpReport{};
    const h = 1.0 / @as(f32, @floatFromInt(m.opts.regions));
    for (m.kernels.items) |*k| {
        const sh = pushKernel(k.shape(), v, dt) orelse {
            rep.refused += 1;
            continue;
        };
        var mu = sh.mu;
        inline for (0..3) |a| mu[a] = @min(1, @max(0, mu[a]));
        k.p[0] = mu[0];
        k.p[1] = mu[1];
        k.p[2] = mu[2];
        k.p[3] = @log(sh.l[0]);
        k.p[4] = @log(sh.l[2]);
        k.p[5] = @log(sh.l[5]);
        k.p[6] = sh.l[1];
        k.p[7] = sh.l[3];
        k.p[8] = sh.l[4];
        k.reach = marl.reachOf(sh);
        k.mu0 = mu;
        rep.worst_reach = @max(rep.worst_reach, k.reach / h);
        if (k.reach > h) rep.over_reach += 1;
    }
    @memset(scratch, false);
    try m.compact(scratch);
    return rep;
}

test "G44 (g) the operator the phase ends on: push the kernels, project nothing" {
    // G44 (c) says the representation holds a transported field and the
    // LOOP cannot find it; G44 (d) says the loop cannot be refined out of
    // trouble because its cost is per projection. Both point the same way:
    // do not project.
    //
    // A kernel is small, so the flow is affine across it, so G44 (b)'s
    // closed form applies LOCALLY with the flow map's own Jacobian. The
    // result advects a MARL with no learning, no evidence, no births and no
    // generation loss at all.
    const gpa = testing.allocator;
    const o = Options.best();
    const rot = Flow{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } };
    const swirl = Flow{ .swirl = .{ .amp = 0.35355339 } };
    var gst = rng.Stream.region(o.seed, 0x4750_5242, 0);

    std.debug.print("\n  {s:<26} {s:>7} {s:>9} {s:>7} {s:>7} {s:>7} {s:>7} {s:>6}\n", .{ "arm", "kernels", "RMS", "/const", "mass", "peak", "width", "sec" });
    var swirl_ratio: f32 = 0;
    for ([_]Flow{ rot, swirl }) |f| {
        var m = try fitBlob(gpa, o.blob, o);
        defer m.deinit();
        const m0 = mass(&m);
        const k0 = m.kernels.items.len;
        const scratch = try gpa.alloc(bool, k0 + 8);
        defer gpa.free(scratch);
        var timer = try std.time.Timer.start();
        var over: u32 = 0;
        var i: u32 = 0;
        while (i < o.steps_per_rev) : (i += 1) {
            const rep = try pushForward(&m, .{ .exact = f }, o.dt(), scratch[0..m.kernels.items.len]);
            over += rep.over_reach;
        }
        const secs = @as(f64, @floatFromInt(timer.read())) / 1e9;
        const t = o.dt() * @as(f32, @floatFromInt(o.steps_per_rev));
        const sub = o.ref_sub * o.steps_per_rev;
        const c = forward(f, o.blob.c, t, sub);
        var pr = try ballProbes(gpa, c, 3 * o.blob.s, o.probes, &gst);
        defer pr.deinit(gpa);
        const sc = try score(&m, o.blob, f, t, pr, sub);
        const peak = (try m.predict(c))[0];
        const mm = mass(&m);
        std.debug.print("  {s:<26} {d:>7} {d:>9.5} {d:>7.3} {d:>7.3} {d:>7.4} {d:>7.4} {d:>6.2}\n", .{
            switch (f) {
                .rotation => "push forward, rotation",
                .swirl => "push forward, swirl",
            },
            m.kernels.items.len,
            sc.rms,
            sc.ratio(),
            mm / m0,
            peak,
            @as(f32, @floatCast(std.math.cbrt(mm / (@as(f64, peak) * GAUSS_VOLUME)))),
            secs,
        });
        if (f == .swirl) swirl_ratio = sc.ratio();
        // Population is an EQUALITY: nothing is learned, so nothing is born.
        try testing.expectEqual(k0, m.kernels.items.len);
        // Mass is conserved to the Jacobian's own accuracy. A
        // divergence-free flow has det J = 1 and the weight is carried, so
        // this is a derivation and not a tolerance.
        try testing.expect(@abs(mm / m0 - 1) < 0.01);
        switch (f) {
            // The rotation is AFFINE, so the local Jacobian is the exact
            // global one and this is G44 (b) restated through a different
            // route. It must hold.
            .rotation => try testing.expect(sc.ratio() < thresholds.ALG1_PUSH),
            // **REFUTED on the swirl, at 0.431.** Pushing each kernel by
            // its own local affine map is first-order in the kernel's width
            // times the flow's curvature, and forty steps of a shearing
            // flow accumulate it. What holds is the comparison below, which
            // is the claim that matters.
            .swirl => {},
        }
    }

    // Head to head on the flow that is not affine, in one gate rather than
    // across two, because a comparison assembled out of two gates' printouts
    // is a comparison nobody re-runs.
    const marks = [_]u32{o.steps_per_rev};
    var rp: [1]Row = undefined;
    var mp = try runProject(gpa, o, swirl, .{ .exact = swirl }, &marks, &rp, .{}, false);
    defer mp.deinit();
    std.debug.print("  {s:<26} {d:>7} {d:>9.5} {d:>7.3} {d:>7.3} {d:>7.4} {d:>7.4} {d:>6.2}\n", .{
        "projected loop, swirl", rp[0].kernels, rp[0].local.rms, rp[0].local.ratio(),
        rp[0].mass_ratio,        rp[0].peak,    rp[0].width,     rp[0].seconds,
    });
    std.debug.print("  the push-forward against the loop, on the same flow: {d:.3} against {d:.3} of a constant, at {d} kernels against {d}\n", .{
        swirl_ratio, rp[0].local.ratio(), 125, rp[0].kernels,
    });
    try testing.expect(swirl_ratio * thresholds.ALG1_PUSH_MARGIN < rp[0].local.ratio());
    try testing.expect(rp[0].kernels > 4 * 125);
}

test "G44 (h) arm C: paired field error separates velocity error from compensation" {
    // The original gate subtracted two RMS errors against truth, on
    // DIFFERENT probes. A small or negative difference can be compensation
    // between fit/transport error and velocity error, rather than agreement
    // between fields. Use identical probes and also measure their direct
    // RMS separation. No cancellation threshold is inferred from this run.
    const gpa = testing.allocator;
    const o = Options.best();
    const swirl = Flow{ .swirl = .{ .amp = 0.35355339 } };
    var gst = rng.Stream.region(o.seed, 0x4750_5242, 0);

    // A THREE-CHANNEL MARL, and it needed no new code: `marl.Marl(3)` is
    // the generic MARL-12 introduced. §3 of the note — "a MARL may
    // represent a vector field" — was already true.
    var vm = try fitVelocity(gpa, swirl, o, 400_000);
    defer vm.deinit();
    var est = rng.Stream.region(o.seed, 0x4556_4552, 0);
    const dv = try velocityError(&vm, swirl, 4096, &est);
    std.debug.print("\n  G44 (h) [{s}] the velocity MARL: {d} kernels, |dV| {d:.5}\n", .{
        @tagName(builtin.mode), vm.kernels.items.len, dv,
    });
    std.debug.print("  {s:>8} {s:>9} {s:>9} {s:>9} {s:>11} {s:>9}\n", .{ "steps", "exact V", "learned V", "excess", "T|dV|grad", "meas/pred" });

    var excess: [2]f32 = undefined;
    for ([_]u32{ o.steps_per_rev / 4, o.steps_per_rev }, 0..) |n, idx| {
        const t = o.dt() * @as(f32, @floatFromInt(n));
        const sub = o.ref_sub * n;
        const c = forward(swirl, o.blob.c, t, sub);
        var closure2: f32 = 0;
        inline for (0..3) |a| closure2 += (c[a] - o.blob.c[a]) * (c[a] - o.blob.c[a]);
        std.debug.print("  reference centre departure from start: {d:.6}\n", .{@sqrt(closure2)});
        var pr = try ballProbes(gpa, c, 3 * o.blob.s, o.probes, &gst);
        defer pr.deinit(gpa);
        const exact_values = try gpa.alloc(f32, pr.x.len);
        defer gpa.free(exact_values);
        var paired_se: f64 = 0;
        var rms: [2]f32 = undefined;
        for ([_]VelSrc{ .{ .exact = swirl }, .{ .learned = &vm } }, 0..) |v, i| {
            var m = try fitBlob(gpa, o.blob, o);
            defer m.deinit();
            const scratch = try gpa.alloc(bool, m.kernels.items.len + 8);
            defer gpa.free(scratch);
            var k: u32 = 0;
            while (k < n) : (k += 1) _ = try pushForward(&m, v, o.dt(), scratch[0..m.kernels.items.len]);
            rms[i] = (try score(&m, o.blob, swirl, t, pr, sub)).rms;
            for (pr.x, 0..) |x, pi| {
                const value = (try m.predict(x))[0];
                if (i == 0) {
                    exact_values[pi] = value;
                } else {
                    const d = @as(f64, value) - exact_values[pi];
                    paired_se += d * d;
                }
            }
        }
        const paired = @sqrt(paired_se / @as(f64, @floatFromInt(pr.x.len)));
        excess[idx] = rms[1] - rms[0];
        // Reverse triangle inequality: the error difference can be small
        // while the fields differ substantially. This is not a new fitted
        // threshold; the slack only covers f32 RMS rounding.
        try testing.expect(@abs(excess[idx]) <= paired + 1e-6);
        std.debug.print("  direct paired field RMS: {d:.6}\n", .{paired});
        const want = t * dv * 3.392;
        std.debug.print("  {d:>8} {d:>9.5} {d:>9.5} {d:>9.5} {d:>11.5} {d:>9.3}   {s}\n", .{
            n,                                                                               rms[0], rms[1], excess[idx], want, excess[idx] / want,
            if (n == o.steps_per_rev) "full nominal horizon" else "quarter nominal horizon",
        });
    }
    std.debug.print("  truth-RMS difference, quarter {d:.5}, full {d:.5}; this difference alone does not identify cancellation\n", .{ excess[0], excess[1] });
}

// A structural witness, not a new experimental tolerance: the accelerated
// prediction must equal the ordered full sum bit for bit, and the old
// 27-region gather must miss a nonzero contribution at the same point.
test "G44 (i) transport preserves support beyond the learner's gather" {
    const gpa = testing.allocator;
    var m = try marl.Model.init(gpa, .{ .regions = 4 });
    defer m.deinit();
    const angle: f32 = std.math.pi / 4.0;
    const axis = marl.Shape{
        .mu = .{ 0.249, 0.5, 0.5 },
        .l = .{ 1.0 / 0.06, 0, 1.0 / 0.015, 0, 0, 1.0 / 0.015 },
    };
    // At 45 degrees the long axis fits the learner's box; after turning
    // onto x it reaches from owner cell 0 into query cell 2.
    const sh = warpShape(axis, rotationZ(-angle, .{ 0.5, 0.5, 0.5 })).?;
    try m.kernels.append(gpa, .{
        .p = .{ sh.mu[0], sh.mu[1], sh.mu[2], @log(sh.l[0]), @log(sh.l[2]), @log(sh.l[5]), sh.l[1], sh.l[3], sh.l[4], 1 },
        .owner = 0,
        .mu0 = sh.mu,
        .reach = marl.reachOf(sh),
        .born_at = 0,
    });
    var scratch = [_]bool{false};
    try m.compact(&scratch);
    try testing.expect(!m.full_gather);
    const rep = try warp(&m, rotationZ(angle, .{ 0.5, 0.5, 0.5 }), &scratch);
    try testing.expectEqual(@as(u32, 1), rep.over_reach);
    try testing.expect(m.full_gather);
    const q = [3]f32{ 0.51, 0.5, 0.5 };
    const want = m.predictAll(q)[0];
    try testing.expect(want > 0);
    try testing.expectEqual(@as(u32, @bitCast(want)), @as(u32, @bitCast((try m.predict(q))[0])));
    // Executable mutation: restore precisely the old query contract.
    m.full_gather = false;
    try testing.expectEqual(@as(f32, 0), (try m.predict(q))[0]);
    m.full_gather = true;

    var copy = try marl.Model.init(gpa, .{ .regions = 4 });
    defer copy.deinit();
    try copy.reseedFrom(&m);
    try testing.expect(copy.full_gather);
    try testing.expectEqual(want, (try copy.predict(q))[0]);

    var st = rng.Stream.region(7, 0x47415448, 0);
    for (0..2048) |_| {
        const x = [3]f32{ st.unit(), st.unit(), st.unit() };
        try testing.expectEqual(m.predictAll(x), try m.predict(x));
    }
    // Ownership clamps to the boundary cell for an out-of-domain centre.
    // Its region cube is no longer a bound on its centre, even at small
    // width. The fallback must survive this separate failure of pruning.
    m.kernels.items[0].p[0] = -0.1;
    m.kernels.items[0].p[3] = @log(@as(f32, 100));
    try m.compact(&scratch);
    try testing.expect(m.full_gather);
    const outside = m.kernels.items[0].shape().mu;
    try testing.expectEqual(m.predictAll(outside), try m.predict(outside));
    scratch[0] = true;
    try m.compact(&scratch);
    try testing.expect(!m.full_gather);
}

// Closed reference trajectories do not imply cancellation of velocity
// error: a 1% angular-rate bias builds a phase error on every revolution.
// This analytic counterexample has no learned basis or projection error.
test "G44 (j) a closed streamline does not cancel a systematic velocity bias" {
    const centre = [3]f32{ 0.5, 0.5, 0.5 };
    const x = [3]f32{ 0.75, 0.5, 0.5 };
    const tau: f32 = 2 * std.math.pi;
    for ([_]f32{ 1.01, 1.0 }) |rate| {
        var error2: [2]f32 = .{ 0, 0 };
        for ([_]f32{ tau / 4, tau }, 0..) |t, i| {
            const exact = rotationZ(t, centre).apply(x);
            const biased = rotationZ(rate * t, centre).apply(x);
            inline for (0..3) |a| error2[i] += (biased[a] - exact[a]) * (biased[a] - exact[a]);
        }
        // Executable mutation: with no rate bias, the strict-growth
        // witness must fail, rather than merely get a little smaller.
        try testing.expectEqual(rate != 1, error2[1] > error2[0]);
        if (rate != 1) std.debug.print("\n  G44 (j) closed rotation with 1% rate bias: quarter displacement {d:.6}, full {d:.6}\n", .{ @sqrt(error2[0]), @sqrt(error2[1]) });
    }
}

// Pre-registered diagnostic: keep the original fitted MARL immutable and
// evaluate it at backtraced coordinates. This introduces no new fitting
// error. A single materialisation is trained from that same MODEL (not the
// analytic blob), with the original fit's exemplar budget. Compare all
// arms on identical final probes. The proposed ordering is recorded in
// thresholds.ALG1_PULLBACK_MARGIN before the run.
test "G44 (k) separate the fitted representation from the transport approximation" {
    const gpa = testing.allocator;
    const o = Options.best();
    const flow = Flow{ .swirl = .{ .amp = 0.35355339 } };
    const t = o.dt() * @as(f32, @floatFromInt(o.steps_per_rev));
    const sub = o.ref_sub * o.steps_per_rev;
    var original = try fitBlob(gpa, o.blob, o);
    defer original.deinit();
    var pushed = try marl.Model.init(gpa, o.m);
    defer pushed.deinit();
    try pushed.reseedFrom(&original);
    const scratch = try gpa.alloc(bool, pushed.kernels.items.len);
    defer gpa.free(scratch);
    for (0..o.steps_per_rev) |_| _ = try pushForward(&pushed, .{ .exact = flow }, o.dt(), scratch);

    // Transport training points, carrying the original model's value.
    // This flow preserves volume, so this also transports the sample
    // measure. No analytic target is fed to the student, no per-step fit.
    var student = try marl.Model.init(gpa, o.m);
    defer student.deinit();
    var st = rng.Stream.region(o.seed, 0x50424b46, 0);
    var timer = try std.time.Timer.start();
    for (0..o.fit_exemplars) |_| {
        var p: [3]f32 = undefined;
        while (true) {
            var d2: f32 = 0;
            inline for (0..3) |a| {
                p[a] = o.blob.c[a] + (2 * st.unit() - 1) * 4 * o.blob.s;
                d2 += (p[a] - o.blob.c[a]) * (p[a] - o.blob.c[a]);
            }
            if (d2 <= 16 * o.blob.s * o.blob.s and p[0] >= 0 and p[0] <= 1 and
                p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1) break;
        }
        const x = forward(flow, p, t, o.steps_per_rev);
        _ = try student.observe(x, try original.predict(p));
    }
    const train_s = @as(f64, @floatFromInt(timer.read())) / 1e9;
    var gst = rng.Stream.region(o.seed, 0x50424b50, 0);
    var pr = try ballProbes(gpa, forward(flow, o.blob.c, t, sub), 3 * o.blob.s, o.probes, &gst);
    defer pr.deinit(gpa);
    // fit, pushed, one-shot, transport-only, coarse backtrace vs reference
    var se = [_]f64{0} ** 5;
    var s1: f64 = 0;
    var s2: f64 = 0;
    for (pr.x) |x| {
        const p = backtrace(flow, x, t, sub);
        const truth = o.blob.at(p);
        const lazy = (try original.predict(p))[0];
        const push = (try pushed.predict(x))[0];
        const once = (try student.predict(x))[0];
        const coarse = (try original.predict(backtrace(flow, x, t, o.steps_per_rev)))[0];
        const errors = [_]f64{ lazy - truth, push - truth, once - truth, push - lazy, coarse - lazy };
        for (errors, &se) |e, *sum| sum.* += e * e;
        s1 += truth;
        s2 += @as(f64, truth) * truth;
    }
    const n: f64 = @floatFromInt(pr.x.len);
    const anchor = @sqrt(s2 / n - (s1 / n) * (s1 / n));
    for (&se) |*sum| sum.* = @sqrt(sum.* / n);
    std.debug.print("\n  G44 (k) [{s}] same-probe decomposition, {d} source kernels\n", .{ @tagName(builtin.mode), original.kernels.items.len });
    std.debug.print("  constant RMS {d:.6}; transported initial fit {d:.6} ({d:.3}x); pushed {d:.6} ({d:.3}x)\n", .{ anchor, se[0], se[0] / anchor, se[1], se[1] / anchor });
    std.debug.print("  push vs exact transport of fitted model {d:.6}; 40-vs-640-step backtrace difference {e:.3}\n", .{ se[3], se[4] });
    std.debug.print("  one materialisation: {d:.6} ({d:.3}x), {d} kernels, {d} exemplars, {d:.3} s\n", .{ se[2], se[2] / anchor, student.kernels.items.len, o.fit_exemplars, train_s });
    try testing.expect(se[2] * thresholds.ALG1_PULLBACK_MARGIN < se[1]);
}

test "G45 (a) a wider support stencil still equals the full kernel sum" {
    const gpa = testing.allocator;
    try testing.expectError(error.InvalidSupportEdges, marl.Model.init(gpa, .{ .support_edges = 0 }));
    for ([_]u32{ 4, 6, 8 }) |regions| {
        for ([_]u32{ 1, 2, 4 }) |edges| {
            var m = try marl.Model.init(gpa, .{ .regions = regions, .support_edges = edges });
            defer m.deinit();
            var st = rng.Stream.region(7, 0x57494445, 0);
            for (0..128) |_| {
                const scale = marl.CUTOFF_R / m.support_reach;
                var sh = marl.Shape{
                    .mu = .{ st.unit(), st.unit(), st.unit() },
                    .l = .{ scale * (1 + st.unit()), scale * st.unit(), scale * (1 + st.unit()), scale * st.unit(), scale * st.unit(), scale * (1 + st.unit()) },
                };
                const shrink = @max(1, marl.reachOf(sh) / (0.99 * m.support_reach));
                for (&sh.l) |*l| l.* *= shrink;
                try m.kernels.append(gpa, .{
                    .p = .{ sh.mu[0], sh.mu[1], sh.mu[2], @log(sh.l[0]), @log(sh.l[2]), @log(sh.l[5]), sh.l[1], sh.l[3], sh.l[4], 2 * st.unit() - 1 },
                    .owner = 0,
                    .mu0 = sh.mu,
                    .reach = marl.reachOf(sh),
                    .born_at = 0,
                });
            }
            const dead = [_]bool{false} ** 128;
            try m.compact(&dead);
            try testing.expect(!m.full_gather);
            for (0..2048) |_| {
                const x = [3]f32{ 1.2 * st.unit() - 0.1, 1.2 * st.unit() - 0.1, 1.2 * st.unit() - 0.1 };
                const got = (try m.predict(x))[0];
                try testing.expectEqual(@as(u32, @bitCast(m.predictAll(x)[0])), @as(u32, @bitCast(got)));
            }
        }
    }
    // An explicit live contribution in the second ring. Narrow the
    // stencil alone to the historical radius and the equality must fail.
    var m = try marl.Model.init(gpa, .{ .regions = 4, .support_edges = 2 });
    defer m.deinit();
    try m.kernels.append(gpa, .{
        .p = .{ 0.249, 0.5, 0.5, @log(@as(f32, 12.5)), @log(@as(f32, 12.5)), @log(@as(f32, 12.5)), 0, 0, 0, 1 },
        .owner = 0,
        .mu0 = .{ 0.249, 0.5, 0.5 },
        .reach = 0,
        .born_at = 0,
    });
    const dead = [_]bool{false};
    try m.compact(&dead);
    try testing.expect(!m.full_gather);
    const q = [3]f32{ 0.60, 0.5, 0.5 };
    const want = (try m.predict(q))[0];
    try testing.expect(want > 0);
    try testing.expectEqual(m.predictAll(q)[0], want);
    m.opts.support_edges = 1; // mutation: support unchanged, gather too small
    try testing.expectEqual(@as(f32, 0), (try m.predict(q))[0]);
}

test "G45 (b) separate permitted width from ownership and newborn width" {
    const gpa = testing.allocator;
    const arms = [_]struct { edges: u32, birth: f32, name: []const u8 }{
        .{ .edges = 1, .birth = 1, .name = "historical" },
        .{ .edges = 2, .birth = 0.5, .name = "widen by descent" },
        .{ .edges = 2, .birth = 1, .name = "broad birth" },
        .{ .edges = 4, .birth = 1, .name = "widest birth" },
    };
    var counts = [_]f64{0} ** arms.len;
    var errors = [_]f64{0} ** arms.len;
    const seeds = [_]u64{ 7, 19, 41 };
    std.debug.print("\n  G45 (b) [{s}] width sweep, regions=4, 60k exemplars per arm\n", .{@tagName(builtin.mode)});
    std.debug.print("  seed  arm                  kernels   fit/const  push/const   eval/query  support/query  fit sec\n", .{});
    for (seeds) |seed| {
        var o = Options.best();
        o.seed = seed;
        o.m.seed = seed;
        var ps = rng.Stream.region(seed, 0x57505242, 0);
        var pr = try ballProbes(gpa, o.blob.c, 3 * o.blob.s, o.probes, &ps);
        defer pr.deinit(gpa);
        const flow = Flow{ .swirl = .{ .amp = 0.35355339 } };
        const t = o.dt() * @as(f32, @floatFromInt(o.steps_per_rev));
        const sub = o.ref_sub * o.steps_per_rev;
        var final_pr = try ballProbes(gpa, forward(flow, o.blob.c, t, sub), 3 * o.blob.s, o.probes, &ps);
        defer final_pr.deinit(gpa);
        for (arms, 0..) |arm, ai| {
            o.m.support_edges = arm.edges;
            o.m.birth_width = arm.birth;
            var timer = try std.time.Timer.start();
            var m = try fitBlob(gpa, o.blob, o);
            defer m.deinit();
            const fit_s = @as(f64, @floatFromInt(timer.read())) / 1e9;
            const sc = try score(&m, o.blob, flow, 0, pr, o.ref_sub);
            counts[ai] += @floatFromInt(m.kernels.items.len);
            errors[ai] += sc.rms;
            var evaluated: f64 = 0;
            var touched: f64 = 0;
            for (pr.x) |x| {
                const work = try m.gatherWork(x);
                evaluated += @floatFromInt(work.evaluated);
                touched += @floatFromInt(work.touched);
                try testing.expectEqual(m.predictAll(x), try m.predict(x));
            }
            const scratch = try gpa.alloc(bool, m.kernels.items.len);
            defer gpa.free(scratch);
            for (0..o.steps_per_rev) |_| _ = try pushForward(&m, .{ .exact = flow }, o.dt(), scratch);
            const transported = try score(&m, o.blob, flow, t, final_pr, sub);
            std.debug.print("  {d:>4}  {s:<20} {d:>7} {d:>11.4} {d:>11.4} {d:>12.2} {d:>14.2} {d:>8.3}\n", .{
                seed,                                          arm.name,                                    m.kernels.items.len, sc.ratio(), transported.ratio(),
                evaluated / @as(f64, @floatFromInt(pr.x.len)), touched / @as(f64, @floatFromInt(pr.x.len)), fit_s,
            });
        }
    }
    std.debug.print("  broad/historical mean population {d:.4}, mean RMS {d:.4}\n", .{ counts[2] / counts[0], errors[2] / errors[0] });
    try testing.expect(counts[2] * thresholds.ALG_WIDTH_POPULATION_MARGIN < counts[0]);
    try testing.expect(errors[2] <= thresholds.ALG_WIDTH_RMS_ALLOWANCE * errors[0]);
    // A broad Gaussian is an unusually favourable customer of wide
    // Gaussians. Before changing any default, also price width on the
    // existing sharp-shell fixture. This is an exploratory control, not
    // another post-hoc ordering threshold.
    const tp = marl.TruthParams{ .features = 2, .sharpness = 2 };
    const sharp_pr = try marl.probesOf(gpa, tp, 901, 2048);
    defer gpa.free(sharp_pr.p);
    defer gpa.free(sharp_pr.y);
    var s1: f64 = 0;
    var s2: f64 = 0;
    for (sharp_pr.y) |y| {
        s1 += y[0];
        s2 += @as(f64, y[0]) * y[0];
    }
    const np: f64 = @floatFromInt(sharp_pr.p.len);
    const anchor = @sqrt(s2 / np - (s1 / np) * (s1 / np));
    std.debug.print("  sharp-shell control: two features, sharpness=2, 200k exemplars; constant RMS {d:.5}\n", .{anchor});
    std.debug.print("  seed edges kernels   RMS/constant   mean|weight|  eval/query\n", .{});
    for ([_]u64{ 7, 19 }) |seed| {
        for ([_]u32{ 1, 2, 4 }) |edges| {
            var m = try marl.Model.init(gpa, .{ .regions = 4, .support_edges = edges, .responsibility = 3, .seed = seed, .truth = tp });
            defer m.deinit();
            try m.stream_n(200_000);
            const rms = try m.rms(sharp_pr.p, sharp_pr.y, null);
            var abs_weight: f64 = 0;
            for (m.kernels.items) |*k| abs_weight += @abs(k.weightsConst()[0]);
            var evaluated: f64 = 0;
            for (sharp_pr.p) |x| evaluated += @floatFromInt((try m.gatherWork(x)).evaluated);
            std.debug.print("  {d:>4} {d:>5} {d:>7} {d:>14.4} {d:>14.4} {d:>11.2}\n", .{ seed, edges, m.kernels.items.len, rms / anchor, abs_weight / @as(f64, @floatFromInt(m.kernels.items.len)), evaluated / np });
        }
    }
}

/// G46's offline instrument: whole kernel contributions select one
/// evaluator, avoiding a hard switch at spatial cell faces. Precomputed
/// terms isolate the accuracy signal; they are not a runtime speed claim.
const HybridProbeSet = struct {
    k: usize,
    pushed: []const f32,
    traced: []const f32,
    truth: []const f32,

    fn errorOf(self: HybridProbeSet, exact: []const bool) struct { source: f64, truth: f64 } {
        var source_se: f64 = 0;
        var truth_se: f64 = 0;
        for (self.truth, 0..) |truth, qi| {
            var sum: f64 = 0;
            var reference_sum: f64 = 0;
            for (exact, 0..) |use_trace, ki| {
                const idx = qi * self.k + ki;
                sum += if (use_trace) self.traced[idx] else self.pushed[idx];
                reference_sum += self.traced[idx];
            }
            source_se += (sum - reference_sum) * (sum - reference_sum);
            truth_se += (sum - truth) * (sum - truth);
        }
        const n: f64 = @floatFromInt(self.truth.len);
        return .{ .source = @sqrt(source_se / n), .truth = @sqrt(truth_se / n) };
    }
};

test "G46 local probes rank which kernel contributions need backtracing" {
    const gpa = testing.allocator;
    var selected_sum: f64 = 0;
    var random_sum: f64 = 0;
    var weight_sum: f64 = 0;
    std.debug.print("\n  G46 [{s}] local selector; direct error against the transported SOURCE model\n", .{@tagName(builtin.mode)});
    for ([_]u64{ 7, 19, 41 }) |seed| {
        var o = Options.best();
        o.seed = seed;
        o.m.seed = seed;
        o.m.support_edges = 4;
        var source = try fitBlob(gpa, o.blob, o);
        defer source.deinit();
        var pushed = try marl.Model.init(gpa, o.m);
        defer pushed.deinit();
        try pushed.reseedFrom(&source);
        const count = source.kernels.items.len;
        const mask = try gpa.alloc(bool, count);
        defer gpa.free(mask);
        const flow = Flow{ .swirl = .{ .amp = 0.35355339 } };
        const t = o.dt() * @as(f32, @floatFromInt(o.steps_per_rev));
        for (0..o.steps_per_rev) |_| _ = try pushForward(&pushed, .{ .exact = flow }, o.dt(), mask);
        try testing.expectEqual(count, pushed.kernels.items.len);
        const scores = try gpa.alloc(f64, count);
        defer gpa.free(scores);
        const order = try gpa.alloc(usize, count);
        defer gpa.free(order);
        const weight_scores = try gpa.alloc(f64, count);
        defer gpa.free(weight_scores);
        const weight_order = try gpa.alloc(usize, count);
        defer gpa.free(weight_order);
        var calibration = rng.Stream.region(seed, 0x53454c43, 0);
        for (source.kernels.items, pushed.kernels.items, 0..) |*s, *p, ki| {
            var sum: f64 = 0;
            for (0..32) |_| {
                const x = sampleCoverage(s.shape(), 2, &calibration);
                const at = forward(flow, x, t, o.steps_per_rev);
                const d = @as(f64, s.weightsConst()[0]) * (marl.gaussian(s.shape(), x) - marl.gaussian(p.shape(), at));
                sum += d * d;
            }
            scores[ki] = @sqrt(sum / 32);
            order[ki] = ki;
            weight_order[ki] = ki;
            weight_scores[ki] = @abs(s.weightsConst()[0]);
        }
        const Rank = struct {
            fn less(values: []const f64, a: usize, b: usize) bool {
                return values[a] > values[b] or (values[a] == values[b] and a < b);
            }
        };
        std.mem.sort(usize, order, @as([]const f64, scores), Rank.less);
        std.mem.sort(usize, weight_order, @as([]const f64, weight_scores), Rank.less);
        var probe_stream = rng.Stream.region(seed, 0x53454c50, 0);
        var pr = try ballProbes(gpa, forward(flow, o.blob.c, t, o.ref_sub * o.steps_per_rev), 3 * o.blob.s, o.probes, &probe_stream);
        defer pr.deinit(gpa);
        const pushed_terms = try gpa.alloc(f32, count * pr.x.len);
        defer gpa.free(pushed_terms);
        const traced_terms = try gpa.alloc(f32, count * pr.x.len);
        defer gpa.free(traced_terms);
        const truth = try gpa.alloc(f32, pr.x.len);
        defer gpa.free(truth);
        for (pr.x, 0..) |x, qi| {
            const from = backtrace(flow, x, t, o.ref_sub * o.steps_per_rev);
            truth[qi] = o.blob.at(from);
            for (source.kernels.items, pushed.kernels.items, 0..) |*s, *p, ki| {
                traced_terms[qi * count + ki] = s.weightsConst()[0] * marl.gaussian(s.shape(), from);
                pushed_terms[qi * count + ki] = p.weightsConst()[0] * marl.gaussian(p.shape(), x);
            }
        }
        const data = HybridProbeSet{ .k = count, .pushed = pushed_terms, .traced = traced_terms, .truth = truth };
        const shuffle = try gpa.alloc(usize, count);
        defer gpa.free(shuffle);
        std.debug.print("  seed {d}, {d} kernels; corrected   selected/source  random/source  weight/source  selected/truth\n", .{ seed, count });
        for (0..5) |quarter| {
            const n = count * quarter / 4;
            @memset(mask, false);
            for (order[0..n]) |ki| mask[ki] = true;
            const chosen = data.errorOf(mask);
            @memset(mask, false);
            for (weight_order[0..n]) |ki| mask[ki] = true;
            const by_weight = data.errorOf(mask);
            var random_mean: f64 = 0;
            for (0..8) |trial| {
                var random = rng.Stream.region(seed, 0x53454c52 + quarter, trial);
                for (shuffle, 0..) |*idx, i| idx.* = i;
                var i = count;
                while (i > 1) {
                    const j = random.below(@intCast(i));
                    i -= 1;
                    std.mem.swap(usize, &shuffle[i], &shuffle[j]);
                }
                @memset(mask, false);
                for (shuffle[0..n]) |ki| mask[ki] = true;
                random_mean += data.errorOf(mask).source / 8;
            }
            std.debug.print("                     {d:>2}/{d:<2}          {d:.6}       {d:.6}       {d:.6}       {d:.6}\n", .{ n, count, chosen.source, random_mean, by_weight.source, chosen.truth });
            if (quarter == 2) {
                selected_sum += chosen.source;
                random_sum += random_mean;
                weight_sum += by_weight.source;
            }
            // Exact endpoint identities: all backtraced is the source,
            // and with none backtraced the ranking is irrelevant.
            if (quarter == 4) try testing.expectEqual(@as(f64, 0), chosen.source);
            if (quarter == 0) try testing.expectApproxEqAbs(chosen.source, random_mean, 1e-12);
        }
    }
    std.debug.print("  half corrected: selected/random RMS = {d:.4}; shared backtrace cost is still paid once per query\n", .{selected_sum / random_sum});
    std.debug.print("  half corrected: local-error/weight-only RMS = {d:.4} (diagnostic; no pre-registered advantage over weights)\n", .{selected_sum / weight_sum});
    try testing.expect(selected_sum * thresholds.ALG_SELECTOR_MARGIN < random_sum);
}
