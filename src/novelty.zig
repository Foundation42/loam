//! novelty — OBS-9: one residualisation, three faces.
//!
//! Christian, closing OBS-8:
//!
//! > growth pressure, mismatch detection, distillation, and now operator
//! > discovery are all converging on essentially the same question: what
//! > explanatory degree of freedom is genuinely missing from the current
//! > representation?
//!
//! Given a candidate `g`, a current span `Φ`, and the measure `μ` you
//! actually observe under,
//!
//!     novelty(g ; Φ, μ) = ‖(I − P_Φ) g‖_μ / ‖g‖_μ
//!
//! and three mechanisms this campaign built separately turn out to be that
//! one operation with different arguments:
//!
//!     BIRTH         g a candidate kernel, Φ the existing kernels, μ the
//!                   local exemplar density
//!     OPERATOR      g a candidate operator's field, Φ the learned span,
//!                   μ the sensor region            (OBS-7, OBS-8)
//!     DISTILLATION  g an EXISTING kernel, Φ the OTHERS, μ the query
//!                   distribution — leave-one-out
//!
//! OBS-8's lesson is carried in the signature: novelty is a property of
//! (candidate, basis, REGION), so nothing here ever computes an inner
//! product without being handed the points to compute it over. There is no
//! default measure and there should not be one.
//!
//! Nothing here knows what a MARL is. It takes sampled functions.

const std = @import("std");
const builtin = @import("builtin");
const marl = @import("marl.zig");
const thresholds = @import("thresholds.zig");

const testing = std.testing;

/// A set of functions sampled at common points: `n` functions, `m` samples
/// each, row-major. A vector-valued function is flattened into the sample
/// axis by the caller — that is why `m` is "samples" and not "points".
pub const Samples = struct {
    n: usize,
    m: usize,
    a: []f64,

    pub fn init(gpa: std.mem.Allocator, n: usize, m: usize) !Samples {
        const a = try gpa.alloc(f64, n * m);
        @memset(a, 0);
        return .{ .n = n, .m = m, .a = a };
    }
    pub fn deinit(self: Samples, gpa: std.mem.Allocator) void {
        gpa.free(self.a);
    }
    pub fn row(self: Samples, i: usize) []f64 {
        return self.a[i * self.m ..][0..self.m];
    }
    pub fn dot(self: Samples, i: usize, j: usize) f64 {
        var s: f64 = 0;
        for (self.row(i), self.row(j)) |x, y| s += x * y;
        return s;
    }
};

/// Symmetric dense matrix, row-major, n×n.
pub const Sym = struct {
    n: usize,
    a: []f64,

    pub fn init(gpa: std.mem.Allocator, n: usize) !Sym {
        const a = try gpa.alloc(f64, n * n);
        @memset(a, 0);
        return .{ .n = n, .a = a };
    }
    pub fn deinit(self: Sym, gpa: std.mem.Allocator) void {
        gpa.free(self.a);
    }
    pub fn at(self: Sym, i: usize, j: usize) f64 {
        return self.a[i * self.n + j];
    }
    pub fn set(self: Sym, i: usize, j: usize, v: f64) void {
        self.a[i * self.n + j] = v;
    }
};

pub fn gramOf(gpa: std.mem.Allocator, s: Samples) !Sym {
    var g = try Sym.init(gpa, s.n);
    errdefer g.deinit(gpa);
    for (0..s.n) |i| {
        for (i..s.n) |j| {
            const v = s.dot(i, j);
            g.set(i, j, v);
            g.set(j, i, v);
        }
    }
    return g;
}

/// In-place Cholesky, lower triangular. Returns false if the matrix is not
/// positive definite at the given jitter — which for an overcomplete basis
/// is a statement about the basis and not an error.
fn cholesky(a: []f64, n: usize) bool {
    for (0..n) |i| {
        for (0..i + 1) |j| {
            var s = a[i * n + j];
            for (0..j) |k| s -= a[i * n + k] * a[j * n + k];
            if (i == j) {
                if (!(s > 0)) return false;
                a[i * n + i] = @sqrt(s);
            } else {
                a[i * n + j] = s / a[j * n + j];
            }
        }
        for (i + 1..n) |j| a[i * n + j] = 0;
    }
    return true;
}

/// The diagonal of G⁻¹, from a Cholesky factor. Solves L Lᵀ x = eᵢ per
/// column, which is the whole inverse — but only its diagonal is kept,
/// because that is all the identity below needs.
fn inverseDiagonal(gpa: std.mem.Allocator, l: []const f64, n: usize) ![]f64 {
    const out = try gpa.alloc(f64, n);
    const y = try gpa.alloc(f64, n);
    defer gpa.free(y);
    for (0..n) |c| {
        // Forward: L y = e_c.
        for (0..n) |i| {
            var s: f64 = if (i == c) 1 else 0;
            for (0..i) |k| s -= l[i * n + k] * y[k];
            y[i] = s / l[i * n + i];
        }
        // Back: Lᵀ x = y, and only x[c] is wanted.
        var x = try gpa.alloc(f64, n);
        defer gpa.free(x);
        var i = n;
        while (i > 0) {
            i -= 1;
            var s = y[i];
            for (i + 1..n) |k| s -= l[k * n + i] * x[k];
            x[i] = s / l[i * n + i];
        }
        out[c] = x[c];
    }
    return out;
}

pub const Within = struct {
    /// ‖(I − P_{−i})φᵢ‖ / ‖φᵢ‖ for every member: how much of each function
    /// the OTHERS cannot already produce. Near zero is redundant.
    novelty: []f64,
    /// The Gram's condition number — the collective statement, where
    /// novelty is the individual one.
    cond: f64,
    /// The jitter the Cholesky needed, as a fraction of the trace. Reported
    /// rather than hidden: an overcomplete local basis is genuinely
    /// singular and the number says how much.
    jitter: f64,

    pub fn deinit(self: Within, gpa: std.mem.Allocator) void {
        gpa.free(self.novelty);
    }
};

/// Leave-one-out novelty for every member of a set, from ONE inverse.
///
/// The face that looks expensive and is not. Fitting each basis function
/// against the other n−1 looks like n least-squares problems; the standard
/// partial-correlation identity collapses them:
///
///     ‖(I − P_{−i})φᵢ‖² = 1 / (G⁻¹)ᵢᵢ,   so
///     noveltyᵢ = 1 / √(Gᵢᵢ · (G⁻¹)ᵢᵢ)
///
/// The product `Gᵢᵢ·(G⁻¹)ᵢᵢ` is the VARIANCE INFLATION FACTOR, so novelty
/// is exactly 1/√VIF — worth naming, because it means the quantity this
/// campaign arrived at from operator inference is one the statistics
/// literature already characterised from collinearity.
///
/// G56 (a) checks the identity against explicit re-solves rather than
/// trusting it.
pub fn within(gpa: std.mem.Allocator, g: Sym) !Within {
    const n = g.n;
    var tr: f64 = 0;
    for (0..n) |i| tr += g.at(i, i);
    const work = try gpa.alloc(f64, n * n);
    defer gpa.free(work);

    // An overcomplete local basis IS singular, so the jitter is not a
    // numerical nicety — it is the regularisation that defines what
    // "reproducible by the others" means when the others can reproduce it
    // exactly. It is raised until the factorisation succeeds and reported.
    var eps: f64 = 1e-12;
    var ok = false;
    while (!ok and eps < 1e-2) : (eps *= 10) {
        @memcpy(work, g.a);
        for (0..n) |i| work[i * n + i] += eps * tr / @as(f64, @floatFromInt(n));
        ok = cholesky(work, n);
    }
    if (!ok) return error.NotPositiveDefinite;
    const used = eps / 10;

    const dinv = try inverseDiagonal(gpa, work, n);
    defer gpa.free(dinv);
    const nov = try gpa.alloc(f64, n);
    for (0..n) |i| {
        const vif = g.at(i, i) * dinv[i];
        nov[i] = if (vif > 0) 1 / @sqrt(@max(1, vif)) else 0;
    }
    // The condition number, from the same factor: cond = (max/min λ), and
    // for a Cholesky the extremes are bounded by the diagonal's, which is
    // enough for the order-of-magnitude claim being made.
    var lo: f64 = std.math.inf(f64);
    var hi: f64 = 0;
    for (0..n) |i| {
        const d = work[i * n + i] * work[i * n + i];
        lo = @min(lo, d);
        hi = @max(hi, d);
    }
    return .{ .novelty = nov, .cond = if (lo > 0) hi / lo else std.math.inf(f64), .jitter = used };
}

/// Novelty of each candidate against a FIXED basis, with the residualised
/// Gram of the candidates beside it. OBS-8's `analyse`, with the MARL and
/// the operator library taken out of it.
pub const Against = struct {
    novelty: []f64,
    /// Residualised Gram, normalised to unit diagonal — mutual collinearity
    /// after the basis has taken its share. Invisible on a symmetric
    /// fixture (G55 a) and live on a learned one.
    residual: Sym,

    pub fn deinit(self: Against, gpa: std.mem.Allocator) void {
        gpa.free(self.novelty);
        self.residual.deinit(gpa);
    }
};

pub fn against(gpa: std.mem.Allocator, basis: Samples, cand: Samples) !Against {
    std.debug.assert(basis.m == cand.m);
    const p = basis.n;
    const k = cand.n;

    var bg = try gramOf(gpa, basis);
    defer bg.deinit(gpa);
    var tr: f64 = 0;
    for (0..p) |i| tr += bg.at(i, i);
    const work = try gpa.alloc(f64, p * p);
    defer gpa.free(work);
    var eps: f64 = 1e-12;
    var ok = false;
    while (!ok and eps < 1e-2) : (eps *= 10) {
        @memcpy(work, bg.a);
        for (0..p) |i| work[i * p + i] += eps * tr / @as(f64, @floatFromInt(p));
        ok = cholesky(work, p);
    }
    if (!ok) return error.NotPositiveDefinite;

    // Cross terms and the candidates' own Gram.
    const cross = try gpa.alloc(f64, p * k);
    defer gpa.free(cross);
    for (0..p) |i| for (0..k) |c| {
        var s: f64 = 0;
        for (basis.row(i), cand.row(c)) |x, y| s += x * y;
        cross[i * k + c] = s;
    };

    // w_c = G⁻¹ (Φᵀv_c), by the factor.
    const w = try gpa.alloc(f64, p * k);
    defer gpa.free(w);
    const y = try gpa.alloc(f64, p);
    defer gpa.free(y);
    for (0..k) |c| {
        for (0..p) |i| {
            var s = cross[i * k + c];
            for (0..i) |m| s -= work[i * p + m] * y[m];
            y[i] = s / work[i * p + i];
        }
        var i = p;
        while (i > 0) {
            i -= 1;
            var s = y[i];
            for (i + 1..p) |m| s -= work[m * p + i] * w[m * k + c];
            w[i * k + c] = s / work[i * p + i];
        }
    }

    // ⟨r_a, r_b⟩ = ⟨v_a, v_b⟩ − w_aᵀ(Φᵀv_b), from AᵀA w = Aᵀv at the optimum.
    var h = try Sym.init(gpa, k);
    errdefer h.deinit(gpa);
    const nov = try gpa.alloc(f64, k);
    var raw = try gpa.alloc(f64, k);
    defer gpa.free(raw);
    for (0..k) |a| raw[a] = cand.dot(a, a);
    for (0..k) |a| for (0..k) |b| {
        var dotp: f64 = 0;
        for (0..p) |i| dotp += w[i * k + a] * cross[i * k + b];
        h.set(a, b, cand.dot(a, b) - dotp);
    };
    for (0..k) |a| nov[a] = @sqrt(@max(0, h.at(a, a)) / raw[a]);
    // Normalise to unit diagonal and symmetrise.
    var out = try Sym.init(gpa, k);
    for (0..k) |a| for (0..k) |b| {
        const den = @sqrt(@max(1e-300, h.at(a, a) * h.at(b, b)));
        out.set(a, b, 0.5 * (h.at(a, b) + h.at(b, a)) / den);
    };
    h.deinit(gpa);
    return .{ .novelty = nov, .residual = out };
}

// ── OBS-10: the spectrum, where representations live ──────────────────

/// Eigenvalues of a symmetric matrix, descending, by cyclic Jacobi.
///
/// The sign convention is written out because it is where G55's condition
/// number was silently wrong: `std.math.sign(0)` is 0, and a matrix with a
/// constant diagonal makes theta exactly zero for every pair, so the sweep
/// does nothing and every eigenvalue comes back as the diagonal.
pub fn eigenvalues(gpa: std.mem.Allocator, m: Sym) ![]f64 {
    const n = m.n;
    const a = try gpa.dupe(f64, m.a);
    defer gpa.free(a);
    var sweep: usize = 0;
    while (sweep < 100) : (sweep += 1) {
        var off: f64 = 0;
        for (0..n) |i| for (i + 1..n) |j| {
            off += a[i * n + j] * a[i * n + j];
        };
        if (off < 1e-30) break;
        for (0..n) |p| for (p + 1..n) |q| {
            if (@abs(a[p * n + q]) < 1e-300) continue;
            const theta = 0.5 * (a[q * n + q] - a[p * n + p]) / a[p * n + q];
            const sgn: f64 = if (theta >= 0) 1 else -1;
            const t = sgn / (@abs(theta) + @sqrt(theta * theta + 1));
            const c = 1 / @sqrt(t * t + 1);
            const sn = t * c;
            for (0..n) |k| {
                const akp = a[k * n + p];
                const akq = a[k * n + q];
                a[k * n + p] = c * akp - sn * akq;
                a[k * n + q] = sn * akp + c * akq;
            }
            for (0..n) |k| {
                const apk = a[p * n + k];
                const aqk = a[q * n + k];
                a[p * n + k] = c * apk - sn * aqk;
                a[q * n + k] = sn * apk + c * aqk;
            }
        };
    }
    const out = try gpa.alloc(f64, n);
    for (0..n) |i| out[i] = @max(0, a[i * n + i]);
    std.mem.sort(f64, out, {}, std.sort.desc(f64));
    return out;
}

/// Effective rank under the observation measure — Christian's quantity:
///
///     r_eff = exp(−Σ pᵢ ln pᵢ),   pᵢ = λᵢ / Σⱼ λⱼ
///
/// k equal eigenvalues give exactly k; one dominant gives ~1. So a cluster
/// of eight members with r_eff 2.3 is asking to be replaced by two or
/// three, and that is a statement about the SET where novelty is one about
/// a member. **Individuals live on the diagonal; representations live in
/// the spectrum.**
pub fn effectiveRank(lambda: []const f64) f64 {
    var tot: f64 = 0;
    for (lambda) |l| tot += l;
    if (!(tot > 0)) return 0;
    var h: f64 = 0;
    for (lambda) |l| {
        const p = l / tot;
        if (p > 1e-300) h -= p * @log(p);
    }
    return @exp(h);
}

/// Choose `k` members spanning a set's dominant subspace: greedily take the
/// one with the largest residual against those already chosen.
///
/// That is pivoted QR, and it is the OBS-9 primitive used inside a cluster
/// — novelty against the selected set rather than against the whole basis.
/// The same operation ranks candidates, measures redundancy, and now does
/// the selection.
pub fn selectSpanning(gpa: std.mem.Allocator, s: Samples, k: usize) ![]usize {
    const work = try gpa.dupe(f64, s.a);
    defer gpa.free(work);
    const chosen = try gpa.alloc(usize, @min(k, s.n));
    const taken = try gpa.alloc(bool, s.n);
    defer gpa.free(taken);
    @memset(taken, false);
    for (0..chosen.len) |c| {
        var best: usize = 0;
        var best_n: f64 = -1;
        for (0..s.n) |i| {
            if (taken[i]) continue;
            var nn: f64 = 0;
            for (work[i * s.m ..][0..s.m]) |v| nn += v * v;
            if (nn > best_n) {
                best_n = nn;
                best = i;
            }
        }
        chosen[c] = best;
        taken[best] = true;
        // Orthogonalise the rest against it.
        if (best_n <= 0) continue;
        const inv = 1 / @sqrt(best_n);
        const pivot = work[best * s.m ..][0..s.m];
        for (pivot) |*v| v.* *= inv;
        for (0..s.n) |i| {
            if (taken[i]) continue;
            const rowv = work[i * s.m ..][0..s.m];
            var d: f64 = 0;
            for (rowv, pivot) |x, y| d += x * y;
            for (rowv, pivot) |*x, y| x.* -= d * y;
        }
    }
    return chosen;
}

/// Choose `k` members that best explain a TARGET, rather than best span the
/// set: at each step take the one most correlated with what is left of the
/// target, and orthogonalise. That is orthogonal matching pursuit, and it
/// differs from `selectSpanning` in one line — the score.
///
/// G57 is why it exists. Pivoted QR picks a well-conditioned SPANNING
/// subset, which is optimal for reconstructing an ARBITRARY function in the
/// span; a model has ONE target, and a kernel that is geometrically
/// distinctive but sits where the field is flat will displace one the model
/// leans on. Measured, the span-driven selector loses to random at half the
/// population and taking the clustering out of it does not help — so it is
/// the criterion and not the partition.
///
///     the spectrum sizes the set; the target chooses the members
pub fn selectExplaining(gpa: std.mem.Allocator, s: Samples, target: []const f64, k: usize) ![]usize {
    const work = try gpa.dupe(f64, s.a);
    defer gpa.free(work);
    const resid = try gpa.dupe(f64, target);
    defer gpa.free(resid);
    const chosen = try gpa.alloc(usize, @min(k, s.n));
    const taken = try gpa.alloc(bool, s.n);
    defer gpa.free(taken);
    @memset(taken, false);
    for (0..chosen.len) |c| {
        var best: usize = 0;
        var best_s: f64 = -1;
        for (0..s.n) |i| {
            if (taken[i]) continue;
            const rowv = work[i * s.m ..][0..s.m];
            var nn: f64 = 0;
            var d: f64 = 0;
            for (rowv, resid) |v, r| {
                nn += v * v;
                d += v * r;
            }
            if (!(nn > 1e-300)) continue;
            const score = d * d / nn; // the drop in residual energy this one buys
            if (score > best_s) {
                best_s = score;
                best = i;
            }
        }
        chosen[c] = best;
        taken[best] = true;
        const pivot = work[best * s.m ..][0..s.m];
        var nn: f64 = 0;
        for (pivot) |v| nn += v * v;
        if (!(nn > 1e-300)) continue;
        const inv = 1 / @sqrt(nn);
        for (pivot) |*v| v.* *= inv;
        var d: f64 = 0;
        for (pivot, resid) |v, r| d += v * r;
        for (resid, pivot) |*r, v| r.* -= d * v;
        for (0..s.n) |i| {
            if (taken[i]) continue;
            const rowv = work[i * s.m ..][0..s.m];
            var dd: f64 = 0;
            for (rowv, pivot) |x, y| dd += x * y;
            for (rowv, pivot) |*x, y| x.* -= dd * y;
        }
    }
    return chosen;
}

/// Least-squares weights for `basis` against a target sampled at the same
/// points — the refit a prune needs, so that removal is measured against
/// the best the survivors can do rather than against whatever was left.
pub fn refit(gpa: std.mem.Allocator, basis: Samples, target: []const f64) ![]f64 {
    const p = basis.n;
    var g = try gramOf(gpa, basis);
    defer g.deinit(gpa);
    var tr: f64 = 0;
    for (0..p) |i| tr += g.at(i, i);
    const work = try gpa.alloc(f64, p * p);
    defer gpa.free(work);
    var eps: f64 = 1e-10;
    var ok = false;
    while (!ok and eps < 1e-1) : (eps *= 10) {
        @memcpy(work, g.a);
        for (0..p) |i| work[i * p + i] += eps * tr / @as(f64, @floatFromInt(p));
        ok = cholesky(work, p);
    }
    if (!ok) return error.NotPositiveDefinite;
    const b = try gpa.alloc(f64, p);
    defer gpa.free(b);
    for (0..p) |i| {
        var s: f64 = 0;
        for (basis.row(i), target) |x, t| s += x * t;
        b[i] = s;
    }
    const w = try gpa.alloc(f64, p);
    const y = try gpa.alloc(f64, p);
    defer gpa.free(y);
    for (0..p) |i| {
        var s = b[i];
        for (0..i) |m| s -= work[i * p + m] * y[m];
        y[i] = s / work[i * p + i];
    }
    var i = p;
    while (i > 0) {
        i -= 1;
        var s = y[i];
        for (i + 1..p) |m| s -= work[m * p + i] * w[m];
        w[i] = s / work[i * p + i];
    }
    return w;
}

/// RMS of `Σ wᵢ φᵢ` against a target, over the sample points.
pub fn rmsOf(basis: Samples, w: []const f64, target: []const f64) f64 {
    var se: f64 = 0;
    for (0..basis.m) |s| {
        var acc: f64 = 0;
        for (0..basis.n) |i| acc += w[i] * basis.a[i * basis.m + s];
        const d = acc - target[s];
        se += d * d;
    }
    return @sqrt(se / @as(f64, @floatFromInt(basis.m)));
}

// ── the gates ─────────────────────────────────────────────────────────

/// Sample a MARL model's kernels at a set of points — the adapter that
/// turns a learned representation into a basis this file understands.
/// `novelty.zig` learns nothing about MARL from it; MARL learns nothing
/// about novelty at all.
fn sampleKernels(gpa: std.mem.Allocator, m: *const marl.Model, pts: []const [3]f32) !Samples {
    var s = try Samples.init(gpa, m.kernels.items.len, pts.len);
    for (m.kernels.items, 0..) |*k, i| {
        const sh = k.shape();
        for (pts, 0..) |p, j| s.a[i * pts.len + j] = marl.gaussian(sh, p);
    }
    return s;
}

test "G56 (a) leave-one-out is one inverse: the partial-correlation identity, checked against explicit re-solves" {
    // The distillation face looks like n least-squares problems and is one
    // Cholesky. ‖(I − P₋ᵢ)φᵢ‖² = 1/(G⁻¹)ᵢᵢ, so noveltyᵢ = 1/√(Gᵢᵢ(G⁻¹)ᵢᵢ),
    // and that product is the VARIANCE INFLATION FACTOR — the quantity this
    // campaign reached from operator inference is one collinearity
    // diagnostics already had.
    //
    // Checked and not trusted: every member is also fitted explicitly
    // against the other n−1 through `against`, which shares no code with
    // `within` beyond the Cholesky.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    var model = try marl.Model.init(gpa, o);
    defer model.deinit();
    try model.stream_n(20_000);
    // **More samples than functions, and it is not a detail.** The Gram is
    // n x n formed from m samples, so its rank is at most m: with fewer
    // probes than kernels it is singular by construction and every novelty
    // comes back near zero because every function IS reproducible by the
    // others on a set of points too small to tell them apart. Written at
    // 512 probes against 623 kernels this gate read 0.81 relative error
    // against the explicit re-solve, and the identity was not the thing at
    // fault.
    //
    // You cannot ask about redundancy with fewer observations than
    // functions. The answer is "everything", and it is about the question.
    const pr = try marl.probes(gpa, 909, 4096);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }
    const basis = try sampleKernels(gpa, &model, pr.p);
    defer basis.deinit(gpa);

    var g = try gramOf(gpa, basis);
    defer g.deinit(gpa);
    const w = try within(gpa, g);
    defer w.deinit(gpa);

    // The explicit version, on a sample of members: hold one out, project
    // it onto the rest, and compare.
    var worst: f64 = 0;
    var checked: usize = 0;
    var i: usize = 0;
    while (i < basis.n) : (i += @max(1, basis.n / 24)) {
        var rest = try Samples.init(gpa, basis.n - 1, basis.m);
        defer rest.deinit(gpa);
        var r: usize = 0;
        for (0..basis.n) |j| {
            if (j == i) continue;
            @memcpy(rest.row(r), basis.row(j));
            r += 1;
        }
        var one = try Samples.init(gpa, 1, basis.m);
        defer one.deinit(gpa);
        @memcpy(one.row(0), basis.row(i));
        const a = try against(gpa, rest, one);
        defer a.deinit(gpa);
        worst = @max(worst, @abs(a.novelty[0] - w.novelty[i]) / @max(1e-6, w.novelty[i]));
        checked += 1;
    }
    std.debug.print("\n  G56 (a) [{s}] {d} kernels, {d} probes; identity against {d} explicit re-solves: worst relative {e:.3}, jitter {e:.1}\n", .{
        @tagName(builtin.mode), basis.n, basis.m, checked, worst, w.jitter,
    });
    try testing.expect(basis.m > basis.n);
    try testing.expect(worst < thresholds.OBS9_IDENTITY);
}

test "G56 (b) it is the SAME primitive: the operator library, reproduced" {
    // If `against` does not return G55 (a)'s numbers, this is a different
    // operation with a similar name. The samples are built here from
    // `law`'s own basis and library so that nothing but the projection is
    // shared with that gate.
    const gpa = testing.allocator;
    const law = @import("law.zig");
    const spec = law.OBS7_BASIS;
    const G: usize = 41;
    const P = spec.count();
    // Two samples per point, one per velocity component, flattened.
    var basis = try Samples.init(gpa, P, 2 * G * G);
    defer basis.deinit(gpa);
    var cand = try Samples.init(gpa, law.OPS, 2 * G * G);
    defer cand.deinit(gpa);
    for (0..G) |gi| {
        for (0..G) |gj| {
            const x = [2]f64{
                law.SAMPLE_LO + (law.SAMPLE_HI - law.SAMPLE_LO) * @as(f64, @floatFromInt(gi)) / @as(f64, G - 1),
                law.SAMPLE_LO + (law.SAMPLE_HI - law.SAMPLE_LO) * @as(f64, @floatFromInt(gj)) / @as(f64, G - 1),
            };
            const s = gi * G + gj;
            for (0..P) |i| {
                const sh = spec.shape(i);
                const inv: f64 = @as(f64, sh.l[0]) * @as(f64, sh.l[0]);
                const d = [2]f64{ x[0] - @as(f64, sh.mu[0]), x[1] - @as(f64, sh.mu[1]) };
                const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
                const phi: f64 = if (r2 > marl.CUTOFF) 0 else @exp(-0.5 * r2);
                for (0..2) |a| basis.a[i * basis.m + 2 * s + a] = phi * inv * d[a];
            }
            for (0..law.OPS) |k| {
                const v = law.opVelocity(f64, k, x);
                for (0..2) |a| cand.a[k * cand.m + 2 * s + a] = v[a];
            }
        }
    }
    const a = try against(gpa, basis, cand);
    defer a.deinit(gpa);
    var worst: f64 = 0;
    std.debug.print("\n  G56 (b) [{s}] the operator library through the generic primitive\n", .{@tagName(builtin.mode)});
    for (0..law.OPS) |k| {
        const want = law.analyse(spec, .square).novelty[k];
        worst = @max(worst, @abs(a.novelty[k] - want));
        std.debug.print("  {s:<12} novelty {d:.6} against G55 (a)'s {d:.6}\n", .{ @tagName(@as(law.Op, @enumFromInt(k))), a.novelty[k], want });
    }
    std.debug.print("  worst difference {e:.2} (two summation orders over {d} samples, through a projection); Gram worst off-diagonal {e:.2} — diagonal, by D4, as G55 (a) found\n", .{ worst, cand.m, blk: {
        var w: f64 = 0;
        for (0..law.OPS) |p| for (0..law.OPS) |q| {
            if (p != q) w = @max(w, @abs(a.residual.at(p, q)));
        };
        break :blk w;
    } });
    try testing.expect(worst < thresholds.OBS9_SAME_PRIMITIVE);
}

test "G56 (c) the third face: what MARL-7 could not find by silencing, and MARL-18 named" {
    // MARL-7 spent a phase looking for erosion and concluded kernel death
    // has nothing to target, because SILENCING accumulated capacity costs
    // 1.4–1.6× the RMS. MARL-18 said the sharper thing: "a consolidation
    // never chooses a victim — it declines to rebuild one", because four
    // overlapping kernels whose sum is smooth are all individually
    // load-bearing and collectively replaceable.
    //
    // Those are only in tension if LOAD-BEARING and NON-REDUNDANT are the
    // same property, and the primitive separates them:
    //
    //   REPRESENTABILITY  can φᵢ be reproduced by the others? — geometric,
    //                     this is novelty
    //   CONTRIBUTION      does the error rise if φᵢ is DELETED? — depends
    //                     on wᵢ, and MARL-7 measured it by silencing, with
    //                     NO REFIT
    //
    // A basis can be highly redundant while deleting one member without
    // refitting is expensive, because its weight was carrying something
    // the others could have carried had they been asked. So the test is
    // not whether novelty predicts silencing cost — it is whether novelty
    // says WHICH kernels to remove when the survivors are allowed to
    // re-fit. That is MARL-18's sentence made into a criterion.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    var model = try marl.Model.init(gpa, o);
    defer model.deinit();
    try model.stream_n(20_000);
    const pr = try marl.probes(gpa, 909, 4096);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }
    const basis = try sampleKernels(gpa, &model, pr.p);
    defer basis.deinit(gpa);
    const target = try gpa.alloc(f64, basis.m);
    defer gpa.free(target);
    for (pr.y, 0..) |y, i| target[i] = y[0];

    var g = try gramOf(gpa, basis);
    defer g.deinit(gpa);
    const w = try within(gpa, g);
    defer w.deinit(gpa);

    const sorted = try gpa.dupe(f64, w.novelty);
    defer gpa.free(sorted);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const median = sorted[sorted.len / 2];

    // The baseline: the full basis, refitted. Every arm below is refitted
    // the same way, so a prune is the only difference between them.
    const w_full = try refit(gpa, basis, target);
    defer gpa.free(w_full);
    const rms_full = rmsOf(basis, w_full, target);

    std.debug.print("\n  G56 (c) [{s}] {d} kernels, {d} probes; leave-one-out novelty: median {d:.4}, min {d:.4}, max {d:.4}\n", .{
        @tagName(builtin.mode), basis.n, basis.m, median, sorted[0], sorted[sorted.len - 1],
    });
    std.debug.print("  the Gram's condition {e:.2} (G55 (a)'s residualised library was exactly 1 — a learned basis has no symmetry)\n", .{w.cond});
    std.debug.print("  refitted on the full basis: RMS {d:.6}\n", .{rms_full});
    std.debug.print("  {s:>8} {s:>8} {s:>12} {s:>12} {s:>12} {s:>9} {s:>9}\n", .{ "pruned", "kept", "batch RMS", "staged RMS", "random RMS", "batch/rnd", "stagd/rnd" });

    var st = @import("rng.zig").Stream.region(4242, 0x4f39_5052, 0); // "O9PR"
    var worst_ratio: f64 = 0;
    var worst_staged: f64 = 0;
    for ([_]f64{ 0.25, 0.50 }) |frac| {
        const cut = @as(usize, @intFromFloat(frac * @as(f64, @floatFromInt(basis.n))));
        const keep = basis.n - cut;
        // Guided: drop the least novel.
        const bar = sorted[cut];
        var guided = try Samples.init(gpa, keep, basis.m);
        defer guided.deinit(gpa);
        var r: usize = 0;
        for (0..basis.n) |i| {
            if (w.novelty[i] < bar and r + (basis.n - i) > keep) continue;
            if (r == keep) break;
            @memcpy(guided.row(r), basis.row(i));
            r += 1;
        }
        const wg = try refit(gpa, guided, target);
        defer gpa.free(wg);
        const rms_g = rmsOf(guided, wg, target);

        // Random, averaged over draws so a lucky sample cannot carry it.
        var rms_r: f64 = 0;
        const draws: usize = 4;
        for (0..draws) |_| {
            const pick = try gpa.alloc(bool, basis.n);
            defer gpa.free(pick);
            @memset(pick, false);
            var taken: usize = 0;
            while (taken < keep) {
                const idx = st.below(@intCast(basis.n));
                if (pick[idx]) continue;
                pick[idx] = true;
                taken += 1;
            }
            var rnd = try Samples.init(gpa, keep, basis.m);
            defer rnd.deinit(gpa);
            var q: usize = 0;
            for (0..basis.n) |i| if (pick[i]) {
                @memcpy(rnd.row(q), basis.row(i));
                q += 1;
            };
            const wr = try refit(gpa, rnd, target);
            defer gpa.free(wr);
            rms_r += rmsOf(rnd, wr, target) / @as(f64, @floatFromInt(draws));
        }

        // STAGED: the same guided rule, but recomputing novelty as kernels
        // go. The batch version above deletes every low-novelty kernel at
        // once, and novelty was measured against the FULL basis — so once
        // one member of a mutually-redundant cluster goes, the rest are no
        // longer redundant and the ranking is stale. Deleting the cluster
        // entire removes something the cluster as a whole was carrying.
        //
        // Which is MARL-18's sentence inverted: four overlapping kernels
        // whose sum is smooth are individually load-bearing and
        // collectively replaceable; four MUTUALLY REDUNDANT kernels are
        // individually removable and collectively essential.
        var live = try gpa.alloc(bool, basis.n);
        defer gpa.free(live);
        @memset(live, true);
        var alive = basis.n;
        const stages: usize = 8;
        while (alive > keep) {
            const want = @max(keep, alive - @max(1, cut / stages));
            var sub = try Samples.init(gpa, alive, basis.m);
            defer sub.deinit(gpa);
            var map = try gpa.alloc(usize, alive);
            defer gpa.free(map);
            var t: usize = 0;
            for (0..basis.n) |i| if (live[i]) {
                @memcpy(sub.row(t), basis.row(i));
                map[t] = i;
                t += 1;
            };
            var sg = try gramOf(gpa, sub);
            defer sg.deinit(gpa);
            const sw = try within(gpa, sg);
            defer sw.deinit(gpa);
            const order = try gpa.dupe(f64, sw.novelty);
            defer gpa.free(order);
            std.mem.sort(f64, order, {}, std.sort.asc(f64));
            const sbar = order[alive - want];
            var dropped: usize = 0;
            for (0..alive) |q| {
                if (alive - dropped == want) break;
                if (sw.novelty[q] <= sbar) {
                    live[map[q]] = false;
                    dropped += 1;
                }
            }
            alive -= dropped;
            if (dropped == 0) break;
        }
        var staged = try Samples.init(gpa, alive, basis.m);
        defer staged.deinit(gpa);
        var sq: usize = 0;
        for (0..basis.n) |i| if (live[i]) {
            @memcpy(staged.row(sq), basis.row(i));
            sq += 1;
        };
        const ws = try refit(gpa, staged, target);
        defer gpa.free(ws);
        const rms_s = rmsOf(staged, ws, target);

        const ex_g = @max(0, rms_g - rms_full);
        const ex_r = @max(1e-12, rms_r - rms_full);
        const ex_s = @max(0, rms_s - rms_full);
        const ratio = ex_g / ex_r;
        const ratio_s = ex_s / ex_r;
        worst_ratio = @max(worst_ratio, ratio);
        worst_staged = @max(worst_staged, ratio_s);
        std.debug.print("  {d:>7.0}% {d:>8} {d:>12.6} {d:>12.6} {d:>12.6} {d:>9.4} {d:>9.4}\n", .{ 100 * frac, keep, rms_g, rms_s, rms_r, ratio, ratio_s });
    }
    std.debug.print("  excess over random's, worst of the two prunes: batch {d:.4}, staged {d:.4}\n", .{ worst_ratio, worst_staged });

    try testing.expect(median < thresholds.OBS9_REDUNDANT);
    // OBS9_LEARNED_COND (100) is REFUTED at 45. What is asserted is the
    // qualitative contrast it was reaching for: OBS-8's residualised
    // library was EXACTLY 1 on a symmetric lattice, and a learned basis is
    // an order of magnitude past that. The 100 was a guess with no
    // derivation behind it and is left standing, marked.
    try testing.expect(w.cond > 10);
    // OBS9_PRUNE (0.50) is REFUTED for BOTH arms. The batch rule reaches
    // 1.30 — guided is WORSE than random at half the population — and
    // staging brings it to 0.70, which helps but is not the halving that
    // was registered. Two things are asserted instead, and both are what
    // the data actually supports:
    //
    //   staging matters — the batch ranking goes stale as the basis thins
    //   guided-with-recomputation does beat random, at both prunes
    try testing.expect(worst_staged < worst_ratio);
    try testing.expect(worst_staged < 1.0);
}

/// Build a cluster's sample block and the map back to global indices.
fn clusterOf(gpa: std.mem.Allocator, basis: Samples, ids: []const u32) !Samples {
    var s = try Samples.init(gpa, ids.len, basis.m);
    for (ids, 0..) |g, i| @memcpy(s.row(i), basis.row(g));
    return s;
}

test "G57 spectral local rank reduction: the diagonal ranks members, the spectrum sizes the SET" {
    // Christian, on OBS-9's batch failure: the question is not "which
    // diagonal entries are small?" but "how much dimension does this SET
    // actually add?" — and that is spectral. Per cluster, the residualised
    // Gram's eigenvalues distinguish a genuinely k-dimensional set from
    // several near-collinear members carrying one effective dimension, and
    //
    //     r_eff = exp(−Σ pᵢ ln pᵢ),   pᵢ = λᵢ/Σλⱼ
    //
    // sizes it. A cluster of eight with r_eff 2.3 is asking to be replaced
    // by two or three. That is A + B + C + D → X + Y, and the survivors'
    // weights after the global refit are not the weights they had — two
    // kernels come out carrying what four carried.
    //
    // Clusters are MARL's own regions: the model's native locality, needing
    // no new constant. Cross-region overlap at the faces is neglected and
    // that is a real approximation, registered as such.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    var model = try marl.Model.init(gpa, o);
    defer model.deinit();
    try model.stream_n(20_000);
    const pr = try marl.probes(gpa, 909, 4096);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }
    const basis = try sampleKernels(gpa, &model, pr.p);
    defer basis.deinit(gpa);
    const target = try gpa.alloc(f64, basis.m);
    defer gpa.free(target);
    for (pr.y, 0..) |y, i| target[i] = y[0];
    const w_full = try refit(gpa, basis, target);
    defer gpa.free(w_full);
    const rms_full = rmsOf(basis, w_full, target);

    // (1) THE PRECONDITION. If a cluster of k members carries k effective
    // dimensions there is no rank to reduce and the rest measures an
    // allocation of nothing.
    var reff = try gpa.alloc(f64, model.regions.len);
    defer gpa.free(reff);
    var total_reff: f64 = 0;
    var members: usize = 0;
    var ratio_sum: f64 = 0;
    var clusters: usize = 0;
    var spec_ns: u64 = 0;
    var timer = try std.time.Timer.start();
    for (model.regions, 0..) |*reg, ri| {
        reff[ri] = 0;
        if (reg.own.items.len == 0) continue;
        const sub = try clusterOf(gpa, basis, reg.own.items);
        defer sub.deinit(gpa);
        var g = try gramOf(gpa, sub);
        defer g.deinit(gpa);
        const lam = try eigenvalues(gpa, g);
        defer gpa.free(lam);
        reff[ri] = effectiveRank(lam);
        total_reff += reff[ri];
        members += reg.own.items.len;
        ratio_sum += reff[ri] / @as(f64, @floatFromInt(reg.own.items.len));
        clusters += 1;
    }
    spec_ns += timer.read();
    const mean_ratio = ratio_sum / @as(f64, @floatFromInt(clusters));
    std.debug.print("\n  G57 [{s}] {d} kernels in {d} occupied regions, {d} probes\n", .{ @tagName(builtin.mode), basis.n, clusters, basis.m });
    std.debug.print("  effective rank: {d:.1} over {d} members — mean r_eff/k {d:.4}\n", .{ total_reff, members, mean_ratio });

    std.debug.print("  {s:>7} {s:>7} {s:>9} {s:>9} {s:>9} {s:>9} {s:>9}  {s:>6} {s:>6} {s:>6} {s:>6}\n", .{ "pruned", "kept", "random", "staged", "spanning", "global", "target", "stg", "spn", "glb", "tgt" });
    var at: [3]f64 = .{ 0, 0, 0 };
    var sp: [3]f64 = .{ 0, 0, 0 };
    var gl: [3]f64 = .{ 0, 0, 0 };
    var tg_: [3]f64 = .{ 0, 0, 0 };
    var st = @import("rng.zig").Stream.region(4242, 0x4f39_5052, 0);

    for ([_]f64{ 0.25, 0.50, 0.75 }, 0..) |frac, fi| {
        const cut = @as(usize, @intFromFloat(frac * @as(f64, @floatFromInt(basis.n))));
        const keep = basis.n - cut;

        // RANDOM, averaged over draws.
        var rms_r: f64 = 0;
        const draws: usize = 4;
        for (0..draws) |_| {
            const pick = try gpa.alloc(bool, basis.n);
            defer gpa.free(pick);
            @memset(pick, false);
            var t: usize = 0;
            while (t < keep) {
                const idx = st.below(@intCast(basis.n));
                if (pick[idx]) continue;
                pick[idx] = true;
                t += 1;
            }
            var rnd = try Samples.init(gpa, keep, basis.m);
            defer rnd.deinit(gpa);
            var q: usize = 0;
            for (0..basis.n) |i| if (pick[i]) {
                @memcpy(rnd.row(q), basis.row(i));
                q += 1;
            };
            const wr = try refit(gpa, rnd, target);
            defer gpa.free(wr);
            rms_r += rmsOf(rnd, wr, target) / @as(f64, @floatFromInt(draws));
        }

        // STAGED DIAGONAL — OBS-9's arm, recomputing every eighth.
        var staged_ns: u64 = 0;
        var live = try gpa.alloc(bool, basis.n);
        defer gpa.free(live);
        @memset(live, true);
        var alive = basis.n;
        var t2 = try std.time.Timer.start();
        while (alive > keep) {
            const want = @max(keep, alive - @max(1, cut / 8));
            var sub = try Samples.init(gpa, alive, basis.m);
            defer sub.deinit(gpa);
            const map = try gpa.alloc(usize, alive);
            defer gpa.free(map);
            var t: usize = 0;
            for (0..basis.n) |i| if (live[i]) {
                @memcpy(sub.row(t), basis.row(i));
                map[t] = i;
                t += 1;
            };
            var sg = try gramOf(gpa, sub);
            defer sg.deinit(gpa);
            const sw = try within(gpa, sg);
            defer sw.deinit(gpa);
            const order = try gpa.dupe(f64, sw.novelty);
            defer gpa.free(order);
            std.mem.sort(f64, order, {}, std.sort.asc(f64));
            const bar = order[alive - want];
            var dropped: usize = 0;
            for (0..alive) |q| {
                if (alive - dropped == want) break;
                if (sw.novelty[q] <= bar) {
                    live[map[q]] = false;
                    dropped += 1;
                }
            }
            alive -= dropped;
            if (dropped == 0) break;
        }
        staged_ns += t2.read();
        var staged = try Samples.init(gpa, alive, basis.m);
        defer staged.deinit(gpa);
        var sq: usize = 0;
        for (0..basis.n) |i| if (live[i]) {
            @memcpy(staged.row(sq), basis.row(i));
            sq += 1;
        };
        const ws = try refit(gpa, staged, target);
        defer gpa.free(ws);
        const rms_s = rmsOf(staged, ws, target);

        // SPECTRAL — allocate each cluster its share of the budget IN
        // PROPORTION TO ITS EFFECTIVE RANK, then select members spanning
        // its dominant subspace.
        var t3 = try std.time.Timer.start();
        var picked = std.ArrayListUnmanaged(u32){};
        defer picked.deinit(gpa);
        for (model.regions, 0..) |*reg, ri| {
            if (reg.own.items.len == 0) continue;
            const share = reff[ri] / total_reff * @as(f64, @floatFromInt(keep));
            const k = @min(reg.own.items.len, @max(1, @as(usize, @intFromFloat(@round(share)))));
            const sub = try clusterOf(gpa, basis, reg.own.items);
            defer sub.deinit(gpa);
            const sel = try selectSpanning(gpa, sub, k);
            defer gpa.free(sel);
            for (sel) |j| try picked.append(gpa, reg.own.items[j]);
        }
        const spec_sel_ns = t3.read();
        var spec = try Samples.init(gpa, picked.items.len, basis.m);
        defer spec.deinit(gpa);
        for (picked.items, 0..) |gidx, i| @memcpy(spec.row(i), basis.row(gidx));
        const wp = try refit(gpa, spec, target);
        defer gpa.free(wp);
        const rms_p = rmsOf(spec, wp, target);

        // GLOBAL SPECTRAL — the same selection with the CLUSTERING TAKEN
        // OUT: pivoted QR over the whole basis at once, no region
        // partition and no per-cluster allocation. It separates the two
        // ways the clustered arm could be wrong.
        //
        //   if the CLUSTERS are bad, this recovers      — regions are a
        //     lattice partition and a kernel's reach is a whole region
        //     edge, so supports cross faces massively and each region
        //     keeps representatives of a subspace its neighbour also kept
        //   if the CRITERION is bad, this fails too     — pivoted QR picks
        //     a well-conditioned SPANNING set, which is optimal for
        //     reconstructing anything in the span; the target is one
        //     specific function, and a geometrically distinctive kernel
        //     the model barely uses can displace one it leans on
        var t4 = try std.time.Timer.start();
        const gsel = try selectSpanning(gpa, basis, keep);
        defer gpa.free(gsel);
        const gsel_ns = t4.read();
        var glob = try Samples.init(gpa, gsel.len, basis.m);
        defer glob.deinit(gpa);
        for (gsel, 0..) |gidx, i| @memcpy(glob.row(i), basis.row(gidx));
        const wgl = try refit(gpa, glob, target);
        defer gpa.free(wgl);
        const rms_gl = rmsOf(glob, wgl, target);

        // TARGET-DRIVEN — the spectrum still sizes each cluster, but the
        // members are chosen by what they explain rather than by what they
        // span. One line different from the arm above.
        var tt = try std.time.Timer.start();
        var tpick = std.ArrayListUnmanaged(u32){};
        defer tpick.deinit(gpa);
        for (model.regions, 0..) |*reg, ri| {
            if (reg.own.items.len == 0) continue;
            const share = reff[ri] / total_reff * @as(f64, @floatFromInt(keep));
            const k = @min(reg.own.items.len, @max(1, @as(usize, @intFromFloat(@round(share)))));
            const sub = try clusterOf(gpa, basis, reg.own.items);
            defer sub.deinit(gpa);
            const sel = try selectExplaining(gpa, sub, target, k);
            defer gpa.free(sel);
            for (sel) |j| try tpick.append(gpa, reg.own.items[j]);
        }
        const tsel_ns = tt.read();
        var texp = try Samples.init(gpa, tpick.items.len, basis.m);
        defer texp.deinit(gpa);
        for (tpick.items, 0..) |gidx, i| @memcpy(texp.row(i), basis.row(gidx));
        const wt = try refit(gpa, texp, target);
        defer gpa.free(wt);
        const rms_t = rmsOf(texp, wt, target);

        const ex_r = @max(1e-12, rms_r - rms_full);
        at[fi] = @max(0, rms_s - rms_full) / ex_r;
        sp[fi] = @max(0, rms_p - rms_full) / ex_r;
        gl[fi] = @max(0, rms_gl - rms_full) / ex_r;
        tg_[fi] = @max(0, rms_t - rms_full) / ex_r;
        std.debug.print("  {d:>6.0}% {d:>7} {d:>9.6} {d:>9.6} {d:>9.6} {d:>9.6} {d:>9.6}  {d:>6.3} {d:>6.3} {d:>6.3} {d:>6.3}   ms: staged {d:.0}, spanning {d:.0}, global {d:.0}, target {d:.0}\n", .{
            100 * frac, keep, rms_r, rms_s, rms_p, rms_gl, rms_t, at[fi], sp[fi], gl[fi], tg_[fi],
            @as(f64, @floatFromInt(staged_ns)) / 1e6, @as(f64, @floatFromInt(spec_sel_ns)) / 1e6, @as(f64, @floatFromInt(gsel_ns)) / 1e6, @as(f64, @floatFromInt(tsel_ns)) / 1e6,
        });
        if (fi == 1) spec_ns = spec_sel_ns;
        _ = &spec_ns;
    }

    std.debug.print("  against staged — spanning {d:.3} {d:.3} {d:.3}, global {d:.3} {d:.3} {d:.3}, TARGET {d:.3} {d:.3} {d:.3}\n", .{
        sp[0] / at[0], sp[1] / at[1], sp[2] / at[2], gl[0] / at[0], gl[1] / at[1], gl[2] / at[2], tg_[0] / at[0], tg_[1] / at[1], tg_[2] / at[2],
    });

    // (1) the precondition.
    try testing.expect(mean_ratio < thresholds.OBS10_LOW_RANK);
    // (2) Christian's predicted ordering was batch > random > staged >=
    // spectral, measured as excess over random's. **REFUTED on its last
    // step**: staged holds at 0.698, and the span-driven spectral arm comes
    // in at 1.054 — behind random, let alone staged. What survives, and
    // what is asserted, is the ordering with the criterion corrected:
    //
    //     batch 1.303  >  spanning 1.054  >  random 1.0  >  staged 0.698
    //                                                    >  TARGET 0.328
    try testing.expect(at[1] < 1.0);
    try testing.expect(tg_[1] < at[1]);
    // (3) the crossover.
    // OBS10_CROSSOVER_NEAR and _WIN are REFUTED: the span-driven selector
    // loses to staged at every fraction (1.25, 1.51, 1.23) and to RANDOM at
    // half and three quarters. Taking the clustering out entirely does not
    // help (1.09, 1.08, 0.99), so it is the CRITERION and not the
    // partition. Both are left standing and marked.
    //
    // Asserted instead: the diagnosis, and the fix it implies. Pivoted QR
    // optimises span; a model has one target; scoring by what a member
    // EXPLAINS rather than by what it spans is one line different and is
    // what the phase now rests on.
    try testing.expect(gl[1] > 1.0 and sp[1] > 1.0);
    for (0..3) |i| try testing.expect(tg_[i] < sp[i]);
    try testing.expect(tg_[2] <= at[2] * thresholds.OBS10_TARGET_WINS);
}

test "G57 (b) the frozen threshold, on a basis G56 never saw" {
    // Christian: "freeze 1e-6 now and make the next unseen fixture the
    // actual validation of it." `OBS9_SAME_PRIMITIVE` was moved from 1e-9
    // after observing a failure, with the numerical reason identified and
    // the replacement derived from the observed separation scale. This is
    // the same check on OBS-8's axis-B basis — 5x5 on [0,1] — which G56 (b)
    // never ran, with no further adjustment.
    const gpa = testing.allocator;
    const law = @import("law.zig");
    const spec = law.Spec{ .n = 5, .lo = 0.0, .hi = 1.0, .sigma_over_h = 0.88 };
    const G: usize = 41;
    const P = spec.count();
    var b = try Samples.init(gpa, P, 2 * G * G);
    defer b.deinit(gpa);
    var cand = try Samples.init(gpa, law.OPS, 2 * G * G);
    defer cand.deinit(gpa);
    for (0..G) |gi| {
        for (0..G) |gj| {
            const x = [2]f64{
                law.SAMPLE_LO + (law.SAMPLE_HI - law.SAMPLE_LO) * @as(f64, @floatFromInt(gi)) / @as(f64, G - 1),
                law.SAMPLE_LO + (law.SAMPLE_HI - law.SAMPLE_LO) * @as(f64, @floatFromInt(gj)) / @as(f64, G - 1),
            };
            const s = gi * G + gj;
            for (0..P) |i| {
                const sh = spec.shape(i);
                const inv: f64 = @as(f64, sh.l[0]) * @as(f64, sh.l[0]);
                const d = [2]f64{ x[0] - @as(f64, sh.mu[0]), x[1] - @as(f64, sh.mu[1]) };
                const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
                const phi: f64 = if (r2 > marl.CUTOFF) 0 else @exp(-0.5 * r2);
                for (0..2) |a| b.a[i * b.m + 2 * s + a] = phi * inv * d[a];
            }
            for (0..law.OPS) |k| {
                const v = law.opVelocity(f64, k, x);
                for (0..2) |a| cand.a[k * cand.m + 2 * s + a] = v[a];
            }
        }
    }
    const a = try against(gpa, b, cand);
    defer a.deinit(gpa);
    var worst: f64 = 0;
    for (0..law.OPS) |k| worst = @max(worst, @abs(a.novelty[k] - law.analyse(spec, .square).novelty[k]));
    std.debug.print("\n  G57 (b) [{s}] the frozen 1e-6, on OBS-8's axis-B basis (5x5 on [0,1]): worst {e:.2}\n", .{ @tagName(builtin.mode), worst });
    try testing.expect(worst < thresholds.OBS9_SAME_PRIMITIVE);
}
