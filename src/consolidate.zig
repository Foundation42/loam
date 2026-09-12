//! consolidate — OBS-11: synthesis, the third stage.
//!
//! Christian's decomposition, settled by OBS-10:
//!
//!     geometry     → how many dimensions exist
//!     objective    → which dimensions matter
//!     distillation → how to synthesise a better basis for them
//!
//! `novelty.zig` owns the first two and knows nothing about MARL. This file
//! owns the third and necessarily does: synthesis means fitting kernels,
//! and a replacement that is not a Gaussian in MARL's family is not a
//! consolidation of a MARL.
//!
//! The operation is `A + B + C + D → X + Y`, where the budget comes from
//! the cluster's effective rank, the initial X and Y come from the
//! target-conditioned selection OBS-10 ended on, and then **they are
//! allowed to move**. Warm-starting from the baseline is deliberate: the
//! comparison becomes exactly "selection" against "selection then
//! refinement", so a win cannot be an accident of where new elements were
//! placed.
//!
//! Descent uses `marl.gradOne` — MARL's own parameter gradients, so the
//! result is expressible by the model that produced it.

const std = @import("std");
const builtin = @import("builtin");
const marl = @import("marl.zig");
const novelty = @import("novelty.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");

const testing = std.testing;

pub const Options = struct {
    /// Descent steps over the probe set.
    steps: usize = 400,
    /// Adam's step, with OBS-5's schedule past the warm-up. A fixed rate
    /// does not converge — G52 (a) measured that directly on this
    /// optimiser — and a consolidation that hovers is a consolidation that
    /// invents structure.
    rate: f32 = 0.01,
    warmup: usize = 100,
    /// Proximal penalty: how strongly a kernel is held to the ancestor it
    /// began as. The gradient of `prox * ||p - p0||^2`, subtracted.
    ///
    /// Proximal and not a penalty on the parameters themselves, because
    /// what this phase is uncertain about is HOW FAR SYNTHESIS MAY ROAM,
    /// and that needs no new notion of what a "large" parameter is. Zero is
    /// OBS-11's arm exactly.
    prox: f32 = 0,
    /// Whether the geometry may move at all. False refines only the
    /// weights, which is the refit OBS-10's arms already had, and is the
    /// control that says the win came from SYNTHESIS rather than from a
    /// better weight solve.
    geometry: bool = true,
    /// Which parameter groups may move, as a mask: 1 centre, 2 log-diagonal,
    /// 4 off-diagonal, 8 weight. The default is all of them; it exists so a
    /// divergence can be attributed to a group rather than guessed at.
    groups: u4 = 0b1111,
    /// Whether the per-region budgets must sum to EXACTLY the budget asked
    /// for. See `allocate`. False is the incumbent and stays the default,
    /// because G62 (b), G63 and G64 were measured under it.
    exact: bool = false,
    /// ACCEPTANCE: reject a refinement that ends non-finite or above the
    /// loss it started at, restoring the pre-refinement candidate.
    ///
    /// OBS-11 registered the null — *a descent that does not descend is not
    /// the thing being measured* — and G69 (b) caught one doing exactly
    /// that: replay RMS 0.13965 -> 0.35844, with the held-out world at
    /// 6.72213 afterwards. Nothing in the pipeline noticed.
    ///
    /// The decision uses REPLAY loss, which is what the optimiser sees.
    /// Current-world probes stay diagnostic and never enter it.
    ///
    /// Default false: this is a diagnostic fork, and a guarded policy is a
    /// SUBSEQUENT experiment, not a silent change to the registered one.
    guard: bool = false,
};

pub const Report = struct {
    /// Training RMS at the first and last step — the null: a descent that
    /// does not descend is not the thing being measured.
    first: f64,
    last: f64,
    /// Whether `Options.guard` rejected this refinement and restored the
    /// candidate it started from.
    rejected: bool = false,
    /// Times the reach projection fired — the clamp pushing back against a
    /// descent that wants a wider kernel than the gather allows. A large
    /// count means the two are fighting, which is its own failure mode.
    clamped: u64 = 0,
    /// Kernels whose cutoff box outgrew one region edge. The gather's
    /// exactness rests on that bound, so it is counted and never hidden;
    /// G44 (b) found the same failure in the affine warp and reported it
    /// rather than correcting it.
    over_reach: u32,
};

/// The two candidates a consolidation passes through, duplicated at the
/// instants they exist, so an experiment can fork from the SAME BYTES rather
/// than from the same seed.
///
/// Astra's contract for OBS-24: a `guarded` branch and a `linear-refit-only`
/// branch must differ in the REFINEMENT and in nothing else. Running two arms
/// from one seed and trusting determinism is a weaker guarantee than building
/// both from one object — and this campaign has already paid for the
/// difference between "the same by argument" and "the same by assertion"
/// (OBS-21's ring).
///
/// Taking them here, inside the consolidation the campaign actually uses,
/// means the fork cannot drift from the real code path. A reimplementation
/// could.
pub const Split = struct {
    /// The post-linear-refit candidate: selection done, weights solved,
    /// nothing descended yet.
    linear: []marl.Kernel = &.{},
    /// What the refinement produced, duplicated BEFORE acceptance — so a
    /// rejected refinement can still be scored against the world. OBS-22 kept
    /// its replay loss and discarded its kernels, which is why nobody could
    /// ask what it had done to the current world.
    attempted: []marl.Kernel = &.{},

    pub fn deinit(self: *Split, gpa: std.mem.Allocator) void {
        if (self.linear.len != 0) gpa.free(self.linear);
        if (self.attempted.len != 0) gpa.free(self.attempted);
        self.* = .{};
    }
};

/// Project a kernel back inside what MARL's gather requires: widths within
/// the floor and ceiling, centre in the cube, and the cutoff box no larger
/// than one region edge. `marl.Model.clamp`'s, reproduced because it is
/// private, and shared by the descent AND the fixtures — because a fixture
/// built from kernels MARL would never hold is not a fixture.
///
/// That was not obvious and cost a phase's diagnosis. G59 (a)'s anisotropic
/// cluster was built with off-diagonals up to 1/sigma and a long axis three
/// times the nominal width, which puts its reach past one region edge. The
/// clamp then corrected it on the descent's FIRST step — before any
/// gradient was applied — and the target had been computed from the
/// unclamped kernels, so the loss rose by 50% and stayed there. It looked
/// exactly like a diverging optimiser: rate 0.01 down to 0.0001 and warmup
/// 100 down to 1 all ended within 5% of each other, which is the signature
/// of a change that owes nothing to the gradient.
pub fn project(k: *marl.Kernel, h: f32, sigma_min: f32) bool {
    const lo_log = -@log(h);
    const hi_log = -@log(sigma_min);
    inline for (0..3) |a| {
        k.p[3 + a] = @min(hi_log, @max(lo_log, k.p[3 + a]));
        k.p[a] = @min(1, @max(0, k.p[a]));
    }
    const off_cap = 1 / sigma_min;
    inline for (0..3) |a| k.p[6 + a] = @min(off_cap, @max(-off_cap, k.p[6 + a]));
    var sh = k.shape();
    var reach = marl.reachOf(sh);
    const fired = reach > h;
    var guard: u8 = 0;
    // L ← fL shrinks every half-extent by f. It LOOPS rather than storing
    // min(reach, h) for the reason MARL's own clamp does: the exactness the
    // gather rests on is a property of the geometry, not of what a field
    // was set to afterwards.
    while (reach > h and guard < 16) : (guard += 1) {
        const f = @max(1.001, reach / h);
        const lf = @log(f);
        inline for (0..3) |a| k.p[3 + a] += lf;
        inline for (0..3) |a| k.p[6 + a] *= f;
        sh = k.shape();
        reach = marl.reachOf(sh);
    }
    k.reach = reach;
    return fired;
}

/// Predict a set of loose kernels at a point — no regions, no gather,
/// because a consolidation candidate is not yet a model.
pub fn predictAt(ks: []const marl.Kernel, q: [3]f32) f32 {
    var y: f32 = 0;
    for (ks) |*k| y += k.weightsConst()[0] * marl.gaussian(k.shape(), q);
    return y;
}

fn rmsAt(ks: []const marl.Kernel, pts: []const [3]f32, target: []const f64) f64 {
    var se: f64 = 0;
    for (pts, target) |q, t| {
        const d = @as(f64, predictAt(ks, q)) - t;
        se += d * d;
    }
    return @sqrt(se / @as(f64, @floatFromInt(pts.len)));
}

/// Let a set of kernels move to fit a target. Every parameter they have —
/// centre, log-diagonal, off-diagonal, weight — against the probes.
///
/// `gradOne` returns the DESCENT direction for the squared error (its
/// weight term is +2·e·g, so a kernel that under-reads gains weight), so
/// the update adds it. The gate asserts the loss falls, which is what
/// makes that a checked statement rather than a remembered one.
pub fn refine(
    gpa: std.mem.Allocator,
    ks: []marl.Kernel,
    pts: []const [3]f32,
    target: []const f64,
    regions: u32,
    o: Options,
) !Report {
    const n = ks.len;
    const P = marl.PARAMS;
    const m1 = try gpa.alloc(f32, n * P);
    defer gpa.free(m1);
    const m2 = try gpa.alloc(f32, n * P);
    defer gpa.free(m2);
    const acc = try gpa.alloc(f32, n * P);
    defer gpa.free(acc);
    @memset(m1, 0);
    @memset(m2, 0);
    const p0 = try gpa.alloc(f32, n * P);
    defer gpa.free(p0);
    for (ks, 0..) |*k, i| @memcpy(p0[i * P ..][0..P], &k.p);

    const h = 1.0 / @as(f32, @floatFromInt(regions));
    const sigma_min = h / 64.0;
    var rep = Report{ .first = rmsAt(ks, pts, target), .last = 0, .over_reach = 0, .clamped = 0 };

    var step: usize = 1;
    while (step <= o.steps) : (step += 1) {
        @memset(acc, 0);
        // One pass over the probes, accumulating the batch gradient. A
        // batch and not a stream: this is a consolidation over a fixed
        // query measure, not online learning, and the two have different
        // convergence stories (OBS-5).
        for (pts, target) |q, t| {
            const e: f32 = @floatCast(t - @as(f64, predictAt(ks, q)));
            var g: [marl.PARAMS]f32 = undefined;
            for (ks, 0..) |*k, i| {
                if (!marl.gradOne(k, q, .{e}, &g)) continue;
                // **The off-diagonals need MARL's own unit scaling and
                // `gradOne` does not carry it.** `gradOne` returns the raw
                // gradient; `marl.zig`'s descent then multiplies the
                // off-diagonal terms by l_ii*l_jj — "the off-diagonal by
                // l_ii·l_jj, so every group's step is a RELATIVE change and
                // one rate governs them all", as that file's own comment
                // puts it. The log-diagonal terms already arrive scaled.
                //
                // Without it the three parameter groups are in different
                // units, and on an ANISOTROPIC cluster, where the l values
                // are large and unequal, the descent DIVERGES: measured
                // train 0.1286 -> 0.7866, uphill by a factor of six, while
                // every isotropic cluster converged. Anisotropy is not a
                // corner case here — it is what MARL's shell exists for.
                const l = k.shape().l;
                g[6] *= l[0] * l[2];
                g[7] *= l[0] * l[5];
                g[8] *= l[2] * l[5];
                for (0..P) |p| acc[i * P + p] += g[p];
            }
        }
        const scale = 1 / @as(f32, @floatFromInt(pts.len));
        const t: f32 = @floatFromInt(step);
        const lr = o.rate * @min(1, @as(f32, @floatFromInt(o.warmup)) / t);
        const c1 = 1 - std.math.pow(f32, 0.9, t);
        const c2 = 1 - std.math.pow(f32, 0.999, t);
        for (ks, 0..) |*k, i| {
            for (0..P) |p| {
                // Weights only, unless the geometry is let out.
                if (!o.geometry and p < marl.PARAMS - 1) continue;
                const grp: u4 = if (p < 3) 0b0001 else if (p < 6) 0b0010 else if (p < 9) 0b0100 else 0b1000;
                if (o.groups & grp == 0) continue;
                // `gradOne` is the DESCENT direction for the squared error,
                // so the proximal term enters with the opposite sign: it
                // pulls back toward the ancestor.
                const gp = acc[i * P + p] * scale - o.prox * (k.p[p] - p0[i * P + p]);
                const j = i * P + p;
                m1[j] = 0.9 * m1[j] + 0.1 * gp;
                m2[j] = 0.999 * m2[j] + 0.001 * gp * gp;
                k.p[p] += lr * (m1[j] / c1) / (@sqrt(m2[j] / c2) + 1e-8);
            }
            // THE CLAMP, and it is not optional: a consolidation that
            // skips it is not producing a MARL.
            if (project(k, h, sigma_min)) rep.clamped += 1;
        }
    }
    for (ks) |*k| {
        if (k.reach > h) rep.over_reach += 1;
    }
    rep.last = rmsAt(ks, pts, target);
    return rep;
}

/// The target energy a cluster's best k MEMBERS capture, against what its
/// true top-k SUBSPACE captures — computable before any fitting.
///
///     spread = 1 − E_sel / E_opt
///
/// Near zero, k existing members already ARE the top-k subspace and
/// synthesis has nothing to buy. Large, and the subspace is a combination
/// no member realises alone — which is exactly Christian's "redundancy
/// distributed across several individually imperfect kernels", made into a
/// number that can be read in advance.
pub fn spreadOf(gpa: std.mem.Allocator, sub: novelty.Samples, target: []const f64, k: usize) !f64 {
    if (k >= sub.n) return 0;
    // E_sel: the energy orthogonal matching pursuit's k picks explain.
    const sel = try novelty.selectExplaining(gpa, sub, target, k);
    defer gpa.free(sel);
    var pick = try novelty.Samples.init(gpa, sel.len, sub.m);
    defer pick.deinit(gpa);
    for (sel, 0..) |j, i| @memcpy(pick.row(i), sub.row(j));
    const wsel = try novelty.refit(gpa, pick, target);
    defer gpa.free(wsel);
    const e_sel = explained(pick, wsel, target);

    // E_opt: the energy the whole cluster explains, which is what its full
    // span can do and therefore an upper bound on any k-subspace of it.
    // Used as the reference because the exact top-k subspace needs the
    // eigenvectors, and the BOUND is enough to rank clusters — which is
    // all `spread` is for.
    const wall = try novelty.refit(gpa, sub, target);
    defer gpa.free(wall);
    const e_opt = explained(sub, wall, target);
    if (!(e_opt > 0)) return 0;
    return @max(0, 1 - e_sel / e_opt);
}

fn explained(s: novelty.Samples, w: []const f64, target: []const f64) f64 {
    var tt: f64 = 0;
    var rr: f64 = 0;
    for (0..s.m) |j| {
        var acc: f64 = 0;
        for (0..s.n) |i| acc += w[i] * s.a[i * s.m + j];
        const d = acc - target[j];
        rr += d * d;
        tt += target[j] * target[j];
    }
    return @max(0, tt - rr);
}

// ── the gate ──────────────────────────────────────────────────────────

fn sampleKernels(gpa: std.mem.Allocator, ks: []const marl.Kernel, pts: []const [3]f32) !novelty.Samples {
    var s = try novelty.Samples.init(gpa, ks.len, pts.len);
    for (ks, 0..) |*k, i| {
        const sh = k.shape();
        for (pts, 0..) |p, j| s.a[i * pts.len + j] = marl.gaussian(sh, p);
    }
    return s;
}

test "G58 synthesis: can a consolidated basis be BETTER than the one it came from?" {
    // Christian's hypothesis, and it is conditional rather than universal:
    // synthesised representatives should dominate selected ones WHERE
    // REDUNDANCY IS DISTRIBUTED across several individually imperfect
    // kernels. If synthesis won uniformly it would be a better optimiser
    // and not a better decomposition, and the three-stage story would be
    // decoration.
    //
    // Warm-started from OBS-10's winner, so the comparison is exactly
    // "selection" against "selection then refinement".
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    var model = try marl.Model.init(gpa, o);
    defer model.deinit();
    try model.stream_n(20_000);
    // **Two disjoint probe sets, and the split is load-bearing.** `refine`
    // optimises every parameter a kernel has against the points it is
    // handed, so scoring it on those same points is training on the test
    // set — and it flatters synthesis enormously, because the baseline
    // only ever gets a weight refit there. Measured that way this gate read
    // 0.00227 against a full basis's 0.04887, a twenty-one-fold "win" that
    // is mostly the confound. OBS-4's discipline: fixed evaluation data
    // never enters learning.
    const pr = try marl.probes(gpa, 909, 4096);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }
    const ho = try marl.probes(gpa, 31337, 4096);
    defer {
        gpa.free(ho.p);
        gpa.free(ho.y);
    }
    const target = try gpa.alloc(f64, pr.p.len);
    defer gpa.free(target);
    for (pr.y, 0..) |y, i| target[i] = y[0];
    const held = try gpa.alloc(f64, ho.p.len);
    defer gpa.free(held);
    for (ho.y, 0..) |y, i| held[i] = y[0];

    const all = try sampleKernels(gpa, model.kernels.items, pr.p);
    defer all.deinit(gpa);
    const w_full = try novelty.refit(gpa, all, target);
    defer gpa.free(w_full);
    const all_h = try sampleKernels(gpa, model.kernels.items, ho.p);
    defer all_h.deinit(gpa);
    const rms_full = novelty.rmsOf(all_h, w_full, held);
    const rms_full_train = novelty.rmsOf(all, w_full, target);

    // r_eff per region — the budget estimator, unchanged from OBS-10.
    const reff = try gpa.alloc(f64, model.regions.len);
    defer gpa.free(reff);
    var total_reff: f64 = 0;
    for (model.regions, 0..) |*reg, ri| {
        reff[ri] = 0;
        if (reg.own.items.len == 0) continue;
        const tmp = try gpa.alloc(marl.Kernel, reg.own.items.len);
        defer gpa.free(tmp);
        for (reg.own.items, 0..) |g, i| tmp[i] = model.kernels.items[g];
        const sub = try sampleKernels(gpa, tmp, pr.p);
        defer sub.deinit(gpa);
        var g = try novelty.gramOf(gpa, sub);
        defer g.deinit(gpa);
        const lam = try novelty.eigenvalues(gpa, g);
        defer gpa.free(lam);
        reff[ri] = novelty.effectiveRank(lam);
        total_reff += reff[ri];
    }

    std.debug.print("\n  G58 [{s}] {d} kernels, {d} fit probes + {d} HELD OUT; full basis refit: held {d:.6}, train {d:.6}\n", .{
        @tagName(builtin.mode), model.kernels.items.len, pr.p.len, ho.p.len, rms_full, rms_full_train,
    });
    std.debug.print("  {s:>7} {s:>7} {s:>11} {s:>11} {s:>9} {s:>9} {s:>8}\n", .{ "pruned", "kept", "sel held", "syn held", "sel/full", "syn/sel", "spread" });

    var sel_r: [3]f64 = .{ 0, 0, 0 };
    var syn_r: [3]f64 = .{ 0, 0, 0 };
    var gain_hi: f64 = 0;
    var gain_lo: f64 = 0;
    var quarter_ok = false;
    var over_reach: u32 = 0;
    var descended = true;

    for ([_]f64{ 0.25, 0.50, 0.75 }, 0..) |frac, fi| {
        const keep = model.kernels.items.len - @as(usize, @intFromFloat(frac * @as(f64, @floatFromInt(model.kernels.items.len))));
        var chosen = std.ArrayListUnmanaged(marl.Kernel){};
        defer chosen.deinit(gpa);
        // Per-cluster spread, split at the median so the conditional can
        // be read: does the gain concentrate where redundancy is spread?
        var spreads = std.ArrayListUnmanaged(f64){};
        defer spreads.deinit(gpa);
        var owners = std.ArrayListUnmanaged(usize){};
        defer owners.deinit(gpa);

        for (model.regions, 0..) |*reg, ri| {
            if (reg.own.items.len == 0) continue;
            const share = reff[ri] / total_reff * @as(f64, @floatFromInt(keep));
            const k = @min(reg.own.items.len, @max(1, @as(usize, @intFromFloat(@round(share)))));
            const tmp = try gpa.alloc(marl.Kernel, reg.own.items.len);
            defer gpa.free(tmp);
            for (reg.own.items, 0..) |g, i| tmp[i] = model.kernels.items[g];
            const sub = try sampleKernels(gpa, tmp, pr.p);
            defer sub.deinit(gpa);
            const sp = try spreadOf(gpa, sub, target, k);
            const sel = try novelty.selectExplaining(gpa, sub, target, k);
            defer gpa.free(sel);
            for (sel) |j| {
                try chosen.append(gpa, tmp[j]);
                try spreads.append(gpa, sp);
                try owners.append(gpa, ri);
            }
        }

        // SELECTED — OBS-10's winner, weights refitted.
        const picked = try sampleKernels(gpa, chosen.items, pr.p);
        defer picked.deinit(gpa);
        const ws = try novelty.refit(gpa, picked, target);
        defer gpa.free(ws);
        const picked_h = try sampleKernels(gpa, chosen.items, ho.p);
        defer picked_h.deinit(gpa);
        const rms_sel = novelty.rmsOf(picked_h, ws, held);
        // Carry the refitted weights into the kernels, so synthesis starts
        // from the baseline's best rather than from stale ones.
        const syn = try gpa.dupe(marl.Kernel, chosen.items);
        defer gpa.free(syn);
        for (syn, ws) |*k, wv| k.p[marl.PARAMS - 1] = @floatCast(wv);

        // SYNTHESISED — the same kernels, allowed to move.
        const rep = try refine(gpa, syn, pr.p, target, o.regions, .{});
        over_reach += rep.over_reach;
        if (!(rep.last <= rep.first)) descended = false;
        const rms_syn = rmsAt(syn, ho.p, held);
        const rms_syn_train = rmsAt(syn, pr.p, target);

        // Where did the gain land? Per-cluster, split at the median spread.
        const med = try gpa.dupe(f64, spreads.items);
        defer gpa.free(med);
        std.mem.sort(f64, med, {}, std.sort.asc(f64));
        const bar = med[med.len / 2];
        var e_hi: f64 = 0;
        var e_lo: f64 = 0;
        for (pr.p, target, 0..) |q, t, j| {
            _ = j;
            const before = @as(f64, predictAt(chosen.items, q));
            const after = @as(f64, predictAt(syn, q));
            const d0 = before - t;
            const d1 = after - t;
            // Attribute a probe to the cluster nearest it, by the region
            // that owns the point.
            const ri = model.regionOf(q);
            var hi = false;
            for (owners.items, spreads.items) |ow, spv| {
                if (ow == ri) {
                    hi = spv > bar;
                    break;
                }
            }
            if (hi) e_hi += d0 * d0 - d1 * d1 else e_lo += d0 * d0 - d1 * d1;
        }
        if (fi == 2) {
            gain_hi = e_hi;
            gain_lo = e_lo;
        }

        sel_r[fi] = rms_sel;
        syn_r[fi] = rms_syn;
        if (fi == 0) quarter_ok = rms_syn <= rms_full;
        var mean_spread: f64 = 0;
        for (spreads.items) |x| mean_spread += x / @as(f64, @floatFromInt(spreads.items.len));
        std.debug.print("  {d:>6.0}% {d:>7} {d:>11.6} {d:>11.6} {d:>9.4} {d:>9.4} {d:>8.4}   train {d:.6}/{d:.6}, {d} over reach\n", .{
            100 * frac, chosen.items.len, rms_sel, rms_syn, rms_sel / rms_full, rms_syn / rms_sel, mean_spread, rep.last, rms_syn_train, rep.over_reach,
        });
    }

    std.debug.print("  the conditional: at three quarters pruned, energy recovered in high-spread clusters {e:.3} against low {e:.3}\n", .{ gain_hi, gain_lo });
    std.debug.print("  the threshold: distilled at a quarter pruned {d:.6} against the FULL basis's {d:.6} — {s}\n", .{
        syn_r[0], rms_full, if (quarter_ok) "BETTER, at 75% of the kernels" else "not reached",
    });

    // (5) the null first: a descent that does not descend measures nothing,
    // and a kernel that outgrows the gather is not a MARL any more.
    try testing.expect(descended);
    try testing.expectEqual(@as(u32, 0), over_reach);
    // (2) OBS11_SYNTHESIS (0.80) is REFUTED at 0.887/0.850/0.893 — the
    // direction holds convincingly and consistently, the magnitude does
    // not. Asserted instead: synthesis beats selection at EVERY fraction,
    // which is the claim, and the threshold §(4) registered, which is what
    // makes it matter.
    for (0..3) |i| try testing.expect(syn_r[i] < sel_r[i]);
    try testing.expect(quarter_ok);
    try testing.expect(syn_r[0] <= rms_full * thresholds.OBS11_BETTER_THAN_FULL);
}

// ── OBS-12: when does consolidation pay? ──────────────────────────────

/// A cluster built to a specified internal redundancy. Eight members,
/// equal total target energy, in its own part of the cube — so that
/// attribution cannot be the confound and only the internal geometry
/// differs between them.
pub const Kind = enum {
    /// Spacing far beyond the width: members nearly orthogonal.
    orthogonal,
    /// Spacing of about a width: the SUM is a smooth object no single
    /// member resembles. Christian's "redundancy distributed across
    /// several individually imperfect kernels", and the agent's pick for
    /// where synthesis should pay most.
    moderate,
    /// Spacing far below the width: near duplicates.
    duplicate,
    /// Elongated and crossed, so no axis-aligned member spans the set.
    anisotropic,
};

pub const MEMBERS: usize = 8;

/// Build one cluster's members about a centre.
pub fn cluster(kind: Kind, at: [3]f32, sigma: f32, seed: u64) [MEMBERS]marl.Kernel {
    var st = rng.Stream.region(seed, 0x4f31_3243, @intFromEnum(kind)); // "O12C"
    var out: [MEMBERS]marl.Kernel = undefined;
    const spacing: f32 = switch (kind) {
        .orthogonal => 4.0 * sigma,
        .moderate => 1.2 * sigma,
        .duplicate => 0.15 * sigma,
        .anisotropic => 1.2 * sigma,
    };
    for (&out, 0..) |*k, i| {
        var p: [marl.PARAMS]f32 = .{0} ** marl.PARAMS;
        inline for (0..3) |a| p[a] = at[a] + spacing * (st.unit() - 0.5) * 2;
        const inv = 1 / sigma;
        if (kind == .anisotropic) {
            // Long along one axis, thin across the others, with the long
            // axis turned by the member's index so the set is crossed.
            const t = @as(f32, @floatFromInt(i)) / @as(f32, MEMBERS);
            p[3] = @log(inv / 3);
            p[4] = @log(inv * 2);
            p[5] = @log(inv);
            p[6] = 2 * (t - 0.5) * inv;
        } else {
            p[3] = @log(inv);
            p[4] = @log(inv);
            p[5] = @log(inv);
        }
        p[marl.PARAMS - 1] = 0.5 + st.unit();
        k.* = .{ .p = p, .owner = 0, .mu0 = .{ p[0], p[1], p[2] }, .reach = 0, .born_at = 0 };
        // Projected at construction. A member outside the gather's bound is
        // not a kernel MARL would ever hold, and a target computed from one
        // is a target no consolidation can be scored against.
        _ = project(k, 1.0 / 3.0, (1.0 / 3.0) / 64.0);
    }
    return out;
}

/// Which cluster a probe belongs to, by ACTUAL SUPPORT under the
/// observation measure: the cluster whose members produce the largest total
/// response there.
///
/// OBS-11 attributed by which REGION owned the probe, which is
/// implementation topology. Christian: "support overlap is the geometry
/// that matters."
pub fn attribute(sets: []const []const marl.Kernel, q: [3]f32) usize {
    var best: usize = 0;
    var best_r: f32 = -1;
    for (sets, 0..) |ks, i| {
        var r: f32 = 0;
        for (ks) |*k| r += @abs(k.weightsConst()[0]) * marl.gaussian(k.shape(), q);
        if (r > best_r) {
            best_r = r;
            best = i;
        }
    }
    return best;
}

test "G59 (a) the conditional: where does synthesis actually pay?" {
    // Christian predicts the gain is MONOTONIC in redundancy — most where
    // members are most redundant. The agent predicts it is NOT: it should
    // peak at INTERMEDIATE redundancy, because both extremes are already
    // solved by selection. Nearly orthogonal members ARE the cluster at
    // budget k; near duplicates are already almost captured by any one of
    // them. It is in the middle that the SUM is a smooth object no single
    // member resembles, and a moved kernel can reach what a standing one
    // cannot.
    //
    // They differ on exactly one comparison, B against C, and that is the
    // whole experiment. Both agree A is lowest.
    const gpa = testing.allocator;
    const sigma: f32 = 0.035;
    const centres = [_][3]f32{
        .{ 0.25, 0.25, 0.5 }, .{ 0.75, 0.25, 0.5 }, .{ 0.25, 0.75, 0.5 }, .{ 0.75, 0.75, 0.5 },
    };
    const kinds = [_]Kind{ .orthogonal, .moderate, .duplicate, .anisotropic };
    const K: usize = 3; // budget per cluster, of eight

    var st = rng.Stream.region(77, 0x4f31_3250, 0); // "O12P"
    std.debug.print("\n  G59 (a) [{s}] four clusters of {d}, budget {d}, equal target energy, held-out scored\n", .{ @tagName(builtin.mode), MEMBERS, K });
    std.debug.print("  {s:<14} {s:>8} {s:>9} {s:>11} {s:>11} {s:>9}\n", .{ "cluster", "r_eff/k", "spread", "selected", "synthesised", "gain" });

    var gain: [4]f64 = .{ 0, 0, 0, 0 };
    var reff_ratio: [4]f64 = .{ 0, 0, 0, 0 };
    for (kinds, centres, 0..) |kind, at, ci| {
        var members = cluster(kind, at, sigma, 77);
        // Normalise so every cluster contributes the same target energy —
        // otherwise a gain is partly a statement about amplitude.
        var pts = try gpa.alloc([3]f32, 3072);
        defer gpa.free(pts);
        for (pts) |*p| {
            inline for (0..3) |a| p[a] = at[a] + 6 * sigma * (st.unit() - 0.5) * 2;
            inline for (0..3) |a| p[a] = @min(1, @max(0, p[a]));
        }
        var energy: f64 = 0;
        for (pts) |p| {
            const v = @as(f64, predictAt(&members, p));
            energy += v * v;
        }
        const norm: f32 = @floatCast(1.0 / @sqrt(energy / @as(f64, @floatFromInt(pts.len))));
        for (&members) |*k| k.p[marl.PARAMS - 1] *= norm;

        // Fit and held-out sets, disjoint.
        const half = pts.len / 2;
        const fitp = pts[0..half];
        const hop = pts[half..];
        const ftarget = try gpa.alloc(f64, half);
        defer gpa.free(ftarget);
        const htarget = try gpa.alloc(f64, pts.len - half);
        defer gpa.free(htarget);
        for (fitp, 0..) |p, i| ftarget[i] = predictAt(&members, p);
        for (hop, 0..) |p, i| htarget[i] = predictAt(&members, p);

        const sub = try sampleKernels(gpa, &members, fitp);
        defer sub.deinit(gpa);
        var g = try novelty.gramOf(gpa, sub);
        defer g.deinit(gpa);
        const lam = try novelty.eigenvalues(gpa, g);
        defer gpa.free(lam);
        reff_ratio[ci] = novelty.effectiveRank(lam) / @as(f64, MEMBERS);
        const spread = try spreadOf(gpa, sub, ftarget, K);

        const sel = try novelty.selectExplaining(gpa, sub, ftarget, K);
        defer gpa.free(sel);
        var chosen: [3]marl.Kernel = undefined;
        for (sel, 0..) |j, i| chosen[i] = members[j];
        const pick = try sampleKernels(gpa, &chosen, fitp);
        defer pick.deinit(gpa);
        const ws = try novelty.refit(gpa, pick, ftarget);
        defer gpa.free(ws);
        for (&chosen, ws) |*k, wv| k.p[marl.PARAMS - 1] = @floatCast(wv);
        const rms_sel = rmsAt(&chosen, hop, htarget);

        var syn = chosen;
        const rep = try refine(gpa, &syn, fitp, ftarget, 3, .{});
        const rms_syn = rmsAt(&syn, hop, htarget);
        gain[ci] = 1 - rms_syn / rms_sel;
        // The train/held pair is the diagnostic: a descent whose TRAIN loss
        // also rose has diverged, where one that fell while held-out rose
        // has overfitted. Three kernels of ten parameters against 1 536
        // points is nowhere near overparameterised, so the two readings
        // mean very different things here.
        std.debug.print("  {s:<14} {d:>8.4} {d:>9.4} {d:>11.6} {d:>11.6} {d:>9.4}   train {d:.6} -> {d:.6}, {d} over reach\n", .{
            @tagName(kind), reff_ratio[ci], spread, rms_sel, rms_syn, gain[ci], rep.first, rep.last, rep.over_reach,
        });
    }

    // Which parameter group makes the anisotropic cluster diverge?
    {
        const members = cluster(.anisotropic, centres[3], sigma, 77);
        const pts = try gpa.alloc([3]f32, 1536);
        defer gpa.free(pts);
        var ds = rng.Stream.region(78, 0x4f31_3244, 0);
        for (pts) |*p| {
            inline for (0..3) |a| p[a] = @min(1, @max(0, centres[3][a] + 6 * sigma * (ds.unit() - 0.5) * 2));
        }
        const tg = try gpa.alloc(f64, pts.len);
        defer gpa.free(tg);
        for (pts, 0..) |p, i| tg[i] = predictAt(&members, p);
        const sub = try sampleKernels(gpa, &members, pts);
        defer sub.deinit(gpa);
        const sel = try novelty.selectExplaining(gpa, sub, tg, K);
        defer gpa.free(sel);
        var base: [3]marl.Kernel = undefined;
        for (sel, 0..) |j, i| base[i] = members[j];
        std.debug.print("  which group diverges (anisotropic):\n", .{});
        for ([_]struct { m: u4, n: []const u8 }{
            .{ .m = 0b1000, .n = "weight only" },
            .{ .m = 0b1001, .n = "weight + centre" },
            .{ .m = 0b1011, .n = "weight + centre + diagonal" },
            .{ .m = 0b1111, .n = "everything" },
        }) |arm| {
            var k2 = base;
            const r = try refine(gpa, &k2, pts, tg, 3, .{ .groups = arm.m });
            std.debug.print("    {s:<28} train {d:.6} -> {d:.6}, clamp fired {d}\n", .{ arm.n, r.first, r.last, r.clamped });
        }
        // The schedule. G52 (a) established on this very optimiser that a
        // fixed-rate Adam does not converge — it wanders in a ball of
        // radius lr — and that 1/t from the start closes it. A warm start
        // that is ALREADY GOOD is exactly the case where hovering can only
        // hurt, which is why the anisotropic cluster diverged where the
        // isotropic ones (starting far from their optimum) still improved.
        std.debug.print("  the schedule and the rate, on the same cluster:\n", .{});
        for ([_]usize{ 100, 1 }) |wu| {
            for ([_]f32{ 0.01, 0.001, 0.0001 }) |rt| {
                var k3 = base;
                const r = try refine(gpa, &k3, pts, tg, 3, .{ .warmup = wu, .rate = rt });
                std.debug.print("    warmup {d:>4}  rate {d:.5}   train {d:.6} -> {d:.6}\n", .{ wu, rt, r.first, r.last });
            }
        }
    }

    std.debug.print("  Christian: gain monotone in redundancy, so duplicate > moderate.  Agent: peaks in the middle, so moderate > duplicate.\n", .{});
    std.debug.print("  moderate {d:.4} against duplicate {d:.4} — {s} was right\n", .{
        gain[1], gain[2], if (gain[1] > gain[2]) "the AGENT" else "CHRISTIAN",
    });

    // **CHRISTIAN WAS RIGHT AND THE AGENT WAS WRONG.** Across the three
    // clusters that differ only in SPACING, the gain is monotone in
    // redundancy: 0.304, 0.840, 0.933 as r_eff/k falls 0.937, 0.352, 0.137.
    // The agent's "both extremes are already solved by selection" was wrong
    // at the duplicate end for a reason it should have seen: near-duplicates
    // let a single moved kernel stand for the whole cluster, and there is
    // nothing to lose by moving it.
    //
    // `OBS12_ORTHOGONAL` (0.10) is also REFUTED at 0.304, and the mistake is
    // the same one: the argument assumed budget = cardinality. The budget is
    // THREE OF EIGHT, so five members are dropped outright and moving the
    // survivors to cover their territory is a real gain even when the
    // members were orthogonal to begin with.
    try testing.expect(gain[0] < gain[1]);
    try testing.expect(gain[1] < gain[2]);
    // And r_eff must order them, or the axis is not the axis.
    try testing.expect(reff_ratio[2] < reff_ratio[1]);
    try testing.expect(reff_ratio[1] < reff_ratio[0]);
    // The anisotropic cluster is off that axis — it differs in KIND and not
    // only in spacing — so it is reported and not ordered against them. What
    // is asserted is that it converges at all, which it did not until the
    // fixture was built inside the gather's bound.
    try testing.expect(gain[3] > 0);
}

/// Consolidate a model into a smaller one: r_eff sets the budget per
/// region (OBS-10), the target-conditioned residual chooses the members
/// (OBS-10), and synthesis lets them move (OBS-11).
///
/// **The target is the PARENT'S OWN PREDICTIONS, not the truth.** That is
/// the difference between sleep and cheating: a consolidation reorganises
/// what the model HAS, and a child handed the truth would start life
/// knowing something its parent had to learn. OBS-11 used the truth
/// because it was measuring representational quality; a lifecycle cannot.
/// How many kernels each region keeps.
///
/// `exact` is OBS-18's fix, and it is an EXPERIMENTAL-CONTRACT fix rather
/// than a numerical one. The incumbent rounds each region's share
/// independently, so a budget of 346 delivers between 345 and 347 depending
/// on where the fractions fall — measured across G65's five arms at
/// 347/345/347/345/347. Six tenths of a per cent cannot explain a gain of
/// +0.34 against −0.42, and that is exactly why it had to be fixed rather
/// than argued about: "equal N and equal k in every arm" was the design's
/// own premise, and a header printing the budget REQUESTED was reporting a
/// number that was not true. Astra found it in review.
///
/// False is the incumbent bit for bit, because three gates were measured
/// under it and their numbers must keep reproducing. True is largest-
/// remainder apportionment: floors first, then the leftover seats to the
/// largest fractional parts, skipping regions that are already full. Every
/// non-empty region still keeps at least one, which is the incumbent's rule
/// and not an artefact of its rounding.
///
/// If the population itself is smaller than `keep` the loop runs out of
/// room and returns short. The caller asserts the total; a budget that
/// cannot be met should fail loudly rather than quietly become a smaller
/// experiment.
fn allocate(
    gpa: std.mem.Allocator,
    reff: []const f64,
    room: []const usize,
    keep: usize,
    exact: bool,
) ![]usize {
    const n = reff.len;
    var total: f64 = 0;
    for (reff) |r| total += r;
    const out = try gpa.alloc(usize, n);
    errdefer gpa.free(out);
    const frac = try gpa.alloc(f64, n);
    defer gpa.free(frac);
    for (0..n) |i| {
        out[i] = 0;
        frac[i] = 0;
        if (room[i] == 0 or !(total > 0)) continue;
        const share = reff[i] / total * @as(f64, @floatFromInt(keep));
        if (!exact) {
            out[i] = @min(room[i], @max(1, @as(usize, @intFromFloat(@round(share)))));
            continue;
        }
        const fl = @floor(share);
        frac[i] = share - fl;
        out[i] = @min(room[i], @max(1, @as(usize, @intFromFloat(fl))));
    }
    if (!exact) return out;

    var have: usize = 0;
    for (out) |v| have += v;
    // Over: take back from the smallest fractional parts, never below one,
    // so no region is emptied by an accounting pass.
    while (have > keep) {
        var pick: ?usize = null;
        for (0..n) |i| {
            if (out[i] <= 1) continue;
            if (pick == null or frac[i] < frac[pick.?]) pick = i;
        }
        if (pick == null) break;
        out[pick.?] -= 1;
        have -= 1;
    }
    // Under: hand out the leftover seats by largest fractional part, and
    // keep going, because one pass is not enough once a region saturates.
    // A seat spent drops that region's claim by one so the next goes
    // elsewhere — otherwise one region with a large remainder takes them all.
    while (have < keep) {
        var pick: ?usize = null;
        for (0..n) |i| {
            if (out[i] >= room[i]) continue;
            if (pick == null or frac[i] > frac[pick.?]) pick = i;
        }
        if (pick == null) break;
        out[pick.?] += 1;
        frac[pick.?] -= 1;
        have += 1;
    }
    return out;
}

pub fn consolidate(
    gpa: std.mem.Allocator,
    parent: *marl.Model,
    pts: []const [3]f32,
    keep: usize,
    o: Options,
) !std.ArrayListUnmanaged(marl.Kernel) {
    const target = try gpa.alloc(f64, pts.len);
    defer gpa.free(target);
    for (pts, 0..) |q, i| target[i] = parent.predictAll(q)[0];

    // r_eff per region — the budget estimator.
    const reff = try gpa.alloc(f64, parent.regions.len);
    defer gpa.free(reff);
    var total: f64 = 0;
    for (parent.regions, 0..) |*reg, ri| {
        reff[ri] = 0;
        if (reg.own.items.len == 0) continue;
        const tmp = try gpa.alloc(marl.Kernel, reg.own.items.len);
        defer gpa.free(tmp);
        for (reg.own.items, 0..) |g, i| tmp[i] = parent.kernels.items[g];
        const sub = try sampleKernels(gpa, tmp, pts);
        defer sub.deinit(gpa);
        var g = try novelty.gramOf(gpa, sub);
        defer g.deinit(gpa);
        const lam = try novelty.eigenvalues(gpa, g);
        defer gpa.free(lam);
        reff[ri] = novelty.effectiveRank(lam);
        total += reff[ri];
    }

    const room = try gpa.alloc(usize, parent.regions.len);
    defer gpa.free(room);
    for (parent.regions, 0..) |*reg, ri| room[ri] = reg.own.items.len;
    const budget = try allocate(gpa, reff, room, keep, o.exact);
    defer gpa.free(budget);

    var out = std.ArrayListUnmanaged(marl.Kernel){};
    errdefer out.deinit(gpa);
    for (parent.regions, 0..) |*reg, ri| {
        if (reg.own.items.len == 0) continue;
        const k = budget[ri];
        const tmp = try gpa.alloc(marl.Kernel, reg.own.items.len);
        defer gpa.free(tmp);
        for (reg.own.items, 0..) |g, i| tmp[i] = parent.kernels.items[g];
        const sub = try sampleKernels(gpa, tmp, pts);
        defer sub.deinit(gpa);
        const sel = try novelty.selectExplaining(gpa, sub, target, k);
        defer gpa.free(sel);
        for (sel) |j| try out.append(gpa, tmp[j]);
    }
    // Refit the weights over the whole surviving basis, then let it move.
    const picked = try sampleKernels(gpa, out.items, pts);
    defer picked.deinit(gpa);
    const w = try novelty.refit(gpa, picked, target);
    defer gpa.free(w);
    for (out.items, w) |*k, wv| k.p[marl.PARAMS - 1] = @floatCast(wv);
    _ = try refine(gpa, out.items, pts, target, parent.opts.regions, o);
    return out;
}

/// Put a set of kernels into a fresh model so it can resume learning.
/// `compact` rebuilds ownership and every region's bound, which is the one
/// place that knowledge lives.
pub fn adopt(gpa: std.mem.Allocator, opts: marl.Options, ks: []const marl.Kernel) !marl.Model {
    var m = try marl.Model.init(gpa, opts);
    errdefer m.deinit();
    for (ks) |k| {
        var c = k;
        // Drift is measured from where a kernel STARTS, and this one starts
        // here — it is a new element, not the ancestor it was selected from.
        c.mu0 = .{ c.p[0], c.p[1], c.p[2] };
        c.m1 = .{0} ** marl.PARAMS;
        c.m2 = .{0} ** marl.PARAMS;
        c.t = 0;
        c.updates = 0;
        try m.kernels.append(gpa, c);
    }
    const dead = try gpa.alloc(bool, ks.len);
    defer gpa.free(dead);
    @memset(dead, false);
    try m.compact(dead);
    return m;
}

test "G60 wake: was the discarded freedom useful plasticity, or clutter?" {
    // Christian's systems question, and he calls it the more consequential
    // one: is overcompleteness advantageous DURING ACQUISITION, even if
    // consolidation produces the better final representation?
    //
    //     grow -> fit -> consolidate -> resume learning
    //
    // Same parent, its consolidated child, the same new data stream, equal
    // work, births on under identical policy. The new regime is the
    // campaign's own modest move — `shift = {0, -0.10, 0}`, MARL-6 through
    // MARL-9's — so old and new structure stay comparable.
    //
    // A second registered disagreement. Christian expects the parent to
    // adapt faster (redundancy as scaffolding); the agent expects the child
    // to keep up, on MARL-6's finding that 91% of committed capacity ends
    // outside the current band after a move, and MARL-1's invariant. The
    // agent lost the last one by reasoning from a property of the members
    // rather than of the operation, which is the failure mode to watch.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;

    var parent = try marl.Model.init(gpa, o);
    defer parent.deinit();
    try parent.stream_n(20_000);

    // Sleep. Consolidated against the parent's own output.
    const fitp = try marl.probes(gpa, 909, 4096);
    defer {
        gpa.free(fitp.p);
        gpa.free(fitp.y);
    }
    const half = parent.kernels.items.len / 2;
    var kids = try consolidate(gpa, &parent, fitp.p, half, .{});
    defer kids.deinit(gpa);
    var child = try adopt(gpa, o, kids.items);
    defer child.deinit();

    // The world moves.
    var moved = marl.TruthParams{};
    moved.shift = .{ 0, -0.10, 0 };
    parent.opts.truth = moved;
    child.opts.truth = moved;
    const ho = try marl.probesOf(gpa, moved, 31337, 4096);
    defer {
        gpa.free(ho.p);
        gpa.free(ho.y);
    }

    std.debug.print("\n  G60 [{s}] parent {d} kernels -> child {d} after sleep (budget {d})\n", .{
        @tagName(builtin.mode), parent.kernels.items.len, child.kernels.items.len, half,
    });
    std.debug.print("  {s:>8}  {s:>8} {s:>8} {s:>9} {s:>7}   {s:>8} {s:>8} {s:>9} {s:>7}\n", .{ "exemplars", "P kern", "P births", "P RMS", "P upd", "C kern", "C births", "C RMS", "C upd" });

    const marks = [_]u64{ 0, 5_000, 20_000, 60_000 };
    var seen: u64 = 0;
    var p_rms: [marks.len]f32 = undefined;
    var c_rms: [marks.len]f32 = undefined;
    const c0 = child.kernels.items.len;
    const pb0 = parent.stats.births;
    const cb0 = child.stats.births;
    for (marks, 0..) |mark, mi| {
        try parent.stream_n(mark - seen);
        try child.stream_n(mark - seen);
        seen = mark;
        p_rms[mi] = try parent.rms(ho.p, ho.y, null);
        c_rms[mi] = try child.rms(ho.p, ho.y, null);
        // Mean updates per kernel — the mechanism, measured rather than
        // inferred. MARL-1's invariant is that capacity you cannot TRAIN is
        // worse than capacity you do not have, so if the child ends behind
        // while carrying MORE kernels, this is where it should show.
        std.debug.print("  {d:>9}  {d:>8} {d:>8} {d:>9.5} {d:>7.0}   {d:>8} {d:>8} {d:>9.5} {d:>7.0}\n", .{
            mark,                    parent.kernels.items.len, parent.stats.births - pb0, p_rms[mi],           parent.meanUpdates(),
            child.kernels.items.len, child.stats.births - cb0, c_rms[mi],                 child.meanUpdates(),
        });
    }
    const last = marks.len - 1;
    const regrowth = @as(f64, @floatFromInt(child.kernels.items.len)) / @as(f64, @floatFromInt(c0));
    std.debug.print("  child regrew {d:.3}x its post-sleep size, to {d:.3} of the parent's\n", .{
        regrowth, @as(f64, @floatFromInt(child.kernels.items.len)) / @as(f64, @floatFromInt(parent.kernels.items.len)),
    });
    std.debug.print("  Christian: redundancy is SCAFFOLDING, parent adapts faster.  Agent: it is BAGGAGE, child keeps up.\n", .{});
    std.debug.print("  final held-out: parent {d:.5}, child {d:.5} — child/parent {d:.4}, {s} was right\n", .{
        p_rms[last],                                                         c_rms[last], c_rms[last] / p_rms[last],
        if (c_rms[last] <= p_rms[last] * 1.05) "the AGENT" else "CHRISTIAN",
    });

    // The nulls first.
    try testing.expect(c_rms[0] <= p_rms[0] * thresholds.OBS13_START_NULL);
    try testing.expect(child.kernels.items.len > 0);
    // Both arms learn something from the moved world.
    try testing.expect(p_rms[last] < p_rms[0]);
    try testing.expect(c_rms[last] < c_rms[0]);
    // And the regrowth question.
    try testing.expect(regrowth > thresholds.OBS13_REGROWTH);
}

/// What a model has actually seen — the minimal replay buffer.
///
/// OBS-14's design correction. OBS-13 consolidated against the model's OWN
/// OUTPUT, on the grounds that handing it the truth would be cheating. That
/// is right about the cheating and wrong about the consequence: a student
/// fitting its teacher can at best MATCH it, and MARL-19 measured that a
/// sleep on a noiseless field is a pure loss. A lineage built on it can
/// only decay.
///
/// OBS-11's consolidation improved on the basis it came from because its
/// target was the truth on probes — which is not cheating either, once
/// named properly: **the truth on probes is what a replay buffer holds.** A
/// model's own observations are legitimately its to reuse.
pub const Replay = struct {
    x: [][3]f32,
    y: []f64,
    /// A-Res keys, one per slot; the array is a MIN-HEAP on them, so the
    /// weakest survivor is always at slot zero. Untouched by `.recent`.
    key: []f64,
    /// The observation index each slot was admitted at. Written by every
    /// rule and READ BY NONE of them — `admit` decides from the index it
    /// has in hand — so it cannot move a selection. It exists because a
    /// recency window is a function of this quantity and there is no other
    /// way to ask, afterwards, how stale a buffer actually IS.
    t: []u64,
    n: usize = 0,
    kind: Compose = .recent,
    /// OBS-19's recency E-FOLDING TIME, in observations. Zero is NO window
    /// and is the incumbent: the key is then untouched arithmetic for
    /// arithmetic, so G61-G65 keep the buffers they were measured with.
    ///
    /// An e-folding time and NOT a half-life — Astra's correction. At
    /// tau = 4096 the half-life is `tau * ln 2` = 2839 observations.
    tau: f64 = 0,
    st: rng.Stream = rng.Stream.region(0, 0x5245_504C, 0), // "REPL"

    pub fn init(gpa: std.mem.Allocator, cap: usize) !Replay {
        return initWith(gpa, cap, .recent, 0);
    }
    /// The default is `.recent` and the default is the INCUMBENT: every
    /// gate before OBS-18 keeps the ring it was measured with, bit for bit.
    pub fn initWith(gpa: std.mem.Allocator, cap: usize, kind: Compose, seed: u64) !Replay {
        return .{
            .x = try gpa.alloc([3]f32, cap),
            .y = try gpa.alloc(f64, cap),
            .key = try gpa.alloc(f64, cap),
            .t = try gpa.alloc(u64, cap),
            .kind = kind,
            .st = rng.Stream.region(seed, 0x5245_504C, 0),
        };
    }
    /// The same buffer with a recency price on it — OBS-19's axis.
    ///
    /// `.recent` is refused rather than ignored: a ring IS a window, and a
    /// ring carrying a second one would be two mechanisms answering to one
    /// name. Loud, never a guess.
    pub fn initWindowed(gpa: std.mem.Allocator, cap: usize, kind: Compose, seed: u64, tau: f64) !Replay {
        std.debug.assert(kind != .recent);
        std.debug.assert(tau > 0);
        var r = try initWith(gpa, cap, kind, seed);
        r.tau = tau;
        return r;
    }
    pub fn deinit(self: Replay, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.y);
        gpa.free(self.key);
        gpa.free(self.t);
    }
    /// A ring: the most recent `cap` observations, so a consolidation sees
    /// the measure the model has most lately been living under.
    pub fn push(self: *Replay, q: [3]f32, v: f64) void {
        const i = self.n % self.x.len;
        self.x[i] = q;
        self.y[i] = v;
        self.t[i] = self.n;
        self.n += 1;
    }
    /// Offer one observation, under whatever rule this buffer holds.
    ///
    /// The reservoirs keep the `cap` largest A-Res keys, `u^(1/w)`, held in
    /// logs as `ln(u)/w` — the same order without underflowing at large w,
    /// and every key negative so the comparison is on one side of zero.
    pub fn admit(self: *Replay, q: [3]f32, v: f64, surprise: f32, cover: f32) void {
        return self.admitAt(q, v, surprise, cover, self.n);
    }
    /// The same admission with the observation index supplied.
    ///
    /// `admit` stamps `self.n`, which is right for a buffer fed by a live
    /// stream and WRONG for one filled by selecting from a pool — there the
    /// slot's index is the observation's, not the selection's. OBS-20 needs
    /// the distinction because its statistics ask how old a selected slot
    /// is, and a stamp of "seventh thing I looked at" answers nothing.
    pub fn admitAt(self: *Replay, q: [3]f32, v: f64, surprise: f32, cover: f32, stamp: u64) void {
        if (self.kind == .recent) {
            const i = self.n % self.x.len;
            self.x[i] = q;
            self.y[i] = v;
            self.t[i] = stamp;
            self.n += 1;
            return;
        }
        const at = stamp;
        const u = @max(1e-12, @as(f64, self.st.unit()));
        const w = self.kind.weight(surprise, cover);
        // OBS-19's window, and the whole of it: let the weight GROW with
        // the observation index, `w_eff = w * exp(t/tau)`, so the A-Res key
        // becomes `ln(u) * exp(-t/tau) / w`. It is fixed at admission and
        // still correct at every later time, because `exp(T/tau)` is a
        // factor common to every slot and cannot reorder them.
        //
        // So a window is not a second rule bolted to a first. It is a
        // PRICE: an exemplar may be `tau * ln(w2/w1)` observations older
        // for every factor `w2/w1` of extra weight it carries. A hard
        // window cannot say this — inside it every point is equal and
        // outside it none exists.
        //
        // **And that is exactly what OBS-19 found against it.** A price can
        // be PAID. An exemplar carrying enough surprise buys its way past
        // any exponential decay, and the exemplars that do are adversely
        // selected — so the window's stale remnant is enriched in the
        // labels the window exists to exclude. A hard cutoff cannot be
        // bought past at any weight and is a different object; it is
        // untested, and nothing here shows a synthesis is impossible.
        //
        // The cost is LOW, not zero. No expiry queue, no periodic scan, no
        // second heap — which is a real result about exponential weighting
        // and NOT a costing of a hard sliding window. It adds arithmetic
        // per admission, and `t` is 8 bytes a slot (64 KiB at N = 8192)
        // that only the diagnostics read.
        //
        // **Held as a LOG MAGNITUDE, and that is a correctness decision
        // rather than a tidiness one.** Written directly, `exp(-t/tau)`
        // underflows to zero past `t/tau = 745`, and an A-Res key is
        // NEGATIVE — so an underflowed factor yields -0.0, which sorts
        // ABOVE every live key and makes the OLDEST exemplars unevictable.
        // The rule would not break, it would INVERT, and the run would look
        // like a perfectly ordinary buffer full of the wrong world.
        //
        // Clamping the exponent was the first fix and was REJECTED before
        // any measurement: it trades inversion for SATURATION — past the
        // clamp every exemplar shares one decay factor, so the window stops
        // discriminating and silently becomes a uniform reservoir over the
        // clamped tail. A late failure instead of a catastrophic one is
        // still a failure the numbers cannot show you.
        //
        //     K = -log(-ln u) + log w + t/tau
        //
        // orders IDENTICALLY — it is `-log` of the key's magnitude, and the
        // key is negative, so larger K is the stronger exemplar exactly as
        // larger key was. The recency term is now LINEAR in t, so there is
        // nothing left to underflow at any tau, and the heap keeps its
        // direction: `key[0]` is still the weakest survivor. G66 (a) is the
        // executable mutation, at a tau that drives t/tau to 1250.
        //
        // The unwindowed key keeps the incumbent's arithmetic untouched,
        // because G61-G65's selections are the numbers this campaign has
        // already recorded.
        var k: f64 = undefined;
        if (self.tau == 0) {
            k = @log(u) / w;
        } else {
            k = -@log(@max(1e-300, -@log(u))) + @log(w) + @as(f64, @floatFromInt(at)) / self.tau;
        }
        if (self.n < self.x.len) {
            self.x[self.n] = q;
            self.y[self.n] = v;
            self.key[self.n] = k;
            self.t[self.n] = at;
            self.n += 1;
            if (self.n == self.x.len) self.heapify();
            return;
        }
        self.n += 1;
        // Weaker than the weakest survivor: the buffer never sees it.
        if (k <= self.key[0]) return;
        self.x[0] = q;
        self.y[0] = v;
        self.key[0] = k;
        self.t[0] = at;
        self.sift(0);
    }
    fn heapify(self: *Replay) void {
        var i = self.x.len / 2;
        while (i > 0) {
            i -= 1;
            self.sift(i);
        }
    }
    fn sift(self: *Replay, from: usize) void {
        var i = from;
        while (true) {
            var small = i;
            const l = 2 * i + 1;
            const r = l + 1;
            if (l < self.x.len and self.key[l] < self.key[small]) small = l;
            if (r < self.x.len and self.key[r] < self.key[small]) small = r;
            if (small == i) return;
            std.mem.swap([3]f32, &self.x[i], &self.x[small]);
            std.mem.swap(f64, &self.y[i], &self.y[small]);
            std.mem.swap(f64, &self.key[i], &self.key[small]);
            std.mem.swap(u64, &self.t[i], &self.t[small]);
            i = small;
        }
    }
    pub fn filled(self: Replay) usize {
        return @min(self.n, self.x.len);
    }
    /// The share of slots recorded BEFORE `cut` — staleness by time rather
    /// than by label.
    ///
    /// OBS-18's `stale` conditions on the contested points, which are a
    /// tenth of this fixture, so it answers the same question through ~780
    /// samples and a binomial sd of 0.018. This one is exact, and OBS-19
    /// turns on an exact floor: with M observations since a move and N
    /// slots to fill, EVERY buffer is at least (N-M)/N stale, the ring
    /// included.
    pub fn oldShare(self: Replay, cut: u64) f64 {
        const n = self.filled();
        var old: usize = 0;
        for (self.t[0..n]) |ti| {
            if (ti < cut) old += 1;
        }
        return @as(f64, @floatFromInt(old)) / @as(f64, @floatFromInt(@max(1, n)));
    }
};

/// How a replay buffer decides what to keep — OBS-18's axis, and the first
/// thing in this campaign that changes NEITHER the number of samples nor
/// the number of parameters.
///
/// Every rule is an ADMISSION policy: it decides at observation time from
/// what a learner already has in hand. Nothing here needs a second pass
/// over history, so no arm is cheating on cost against the ring.
///
/// `uncovered` was very nearly `coverage`, which reads both ways — a buffer
/// that seeks coverage and a buffer that has it are opposite objects.
pub const Compose = enum {
    /// A ring of the most recent `cap` observations. The incumbent: every
    /// OBS phase from 14 to 17 was measured on exactly this.
    recent,
    /// Reservoir over the whole history — every observation ever made is
    /// equally likely to be in the buffer.
    uniform,
    /// Weighted reservoir, w = the exemplar's surprise. Where the model was
    /// wrong when it looked.
    err,
    /// Weighted reservoir, w = 1 − the exemplar's coverage. Where the model
    /// has no basis, which is MARL's own birth statistic and NOT the same
    /// question as where it is wrong: a point can be well covered and badly
    /// fitted, or uncovered and accidentally right.
    uncovered,

    /// Weighted reservoir sampling at equal weights IS uniform reservoir
    /// sampling, so three of the four rules are one algorithm differing in
    /// this expression and nowhere else — which is what makes "differing
    /// only in the measure" a fact about the code and not about the prose.
    pub fn weight(self: Compose, surprise: f32, cover: f32) f64 {
        return switch (self) {
            .recent, .uniform => 1,
            .err => @max(1e-9, @as(f64, surprise)),
            .uncovered => @max(1e-9, 1 - @as(f64, cover)),
        };
    }
};

/// OBS-20's HARD CUTOFF: the last `span` observations, and nothing else.
///
/// Astra's contract for the phase — *identical eligible observations for the
/// error and uniform selections, with the cutoff preventing either rule from
/// retaining an expired sample* — decides this implementation.
///
/// A per-rule reservoir could have carried it, and an earlier draft of this
/// comment claimed otherwise — wrongly. OBS-18's and OBS-19's reservoirs all
/// received the SAME observation stream, and that two selection rules keep
/// different subsets is what selection rules ARE, not a confound in
/// comparing them (Astra).
///
/// What a LITERAL SHARED OBJECT adds is that hard-cutoff ELIGIBILITY becomes
/// explicit and ENFORCEABLE: one deterministic ring, no sampling anywhere in
/// it, every rule selecting its N from the same bytes, so "neither rule can
/// retain an expired sample" is a property of the structure rather than
/// something each arm has to be measured for. The gate asserts the contract
/// instead of checking it per rule.
///
/// Selection happens AT THE SLEEP rather than at admission, which is exact:
/// A-Res over a static pool IS weighted sampling without replacement. A hard
/// cutoff has no incumbent to stay bit-identical to, so there is nothing to
/// be gained by carrying keys forward.
///
/// **And this separates two things the previous phases held together.**
///
///     WHAT YOU KEEP            the window, W observations
///     WHAT YOU CONSOLIDATE ON  the selection, N of them
///
/// The honest price of a hard cutoff is the first number. OBS-19's
/// exponential form stored N and needed no expiry machinery at all; this
/// stores W. That is the cost Astra said had not been priced.
pub const Window = struct {
    x: [][3]f32,
    y: []f64,
    /// Surprise and coverage AS OBSERVED. A selection made at sleep time
    /// still weighs each exemplar by what the model knew when it saw it —
    /// nothing here reprioritises with hindsight, which is the property
    /// OBS-19 had to be corrected on.
    s: []f32,
    c: []f32,
    t: []u64,
    n: u64 = 0,

    pub fn init(gpa: std.mem.Allocator, span: usize) !Window {
        return .{
            .x = try gpa.alloc([3]f32, span),
            .y = try gpa.alloc(f64, span),
            .s = try gpa.alloc(f32, span),
            .c = try gpa.alloc(f32, span),
            .t = try gpa.alloc(u64, span),
        };
    }
    pub fn deinit(self: Window, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.y);
        gpa.free(self.s);
        gpa.free(self.c);
        gpa.free(self.t);
    }
    pub fn push(self: *Window, q: [3]f32, v: f64, surprise: f32, cover: f32) void {
        const i = self.n % self.x.len;
        self.x[i] = q;
        self.y[i] = v;
        self.s[i] = surprise;
        self.c[i] = cover;
        self.t[i] = self.n;
        self.n += 1;
    }
    pub fn filled(self: Window) usize {
        return @min(self.n, @as(u64, self.x.len));
    }
    /// The share of the POOL recorded before `cut`. Deterministic — a window
    /// is a ring, so arithmetic already says what this is, and the gate
    /// checks the arithmetic rather than trusting it.
    pub fn oldShare(self: Window, cut: u64) f64 {
        const f = self.filled();
        var old: usize = 0;
        for (self.t[0..f]) |ti| {
            if (ti < cut) old += 1;
        }
        return @as(f64, @floatFromInt(old)) / @as(f64, @floatFromInt(@max(1, f)));
    }
    /// Fill `out` by selecting under ITS rule from THIS pool.
    ///
    /// Offered oldest first, so that a `.recent` rule reduces to the ring
    /// exactly — which is the degenerate check at W = N, where the pool is
    /// the buffer and every rule must select all of it whatever its measure.
    pub fn selectInto(self: Window, out: *Replay) void {
        out.n = 0;
        const f = self.filled();
        const start = self.n - @as(u64, f);
        var i: u64 = 0;
        while (i < f) : (i += 1) {
            const j: usize = @intCast((start + i) % @as(u64, self.x.len));
            out.admitAt(self.x[j], self.y[j], self.s[j], self.c[j], self.t[j]);
        }
    }
};

/// OBS-22's intervention trigger: a RATIO OF TIMESCALES, never a level.
///
/// A trigger on the LEVEL of surprise fires hardest during a cold start,
/// when the model is merely untrained and the correct action is to keep
/// learning. During learning surprise is high and FALLING; at a change it
/// JUMPS. So the statistic is the rise, not the height.
///
/// **The initialisation is a contract, not a detail.** With both EWMAs
/// started at zero their first nonzero ratio is `alpha_fast/alpha_slow` =
/// `h_slow/h_fast` = 8 on these half-lives — an alarm manufactured entirely
/// by the update rates, before any data exists. Both are therefore seeded
/// with the FIRST monitoring surprise, so the ratio starts at exactly 1.
///
/// **The detector sees MONITORING observations only.** Targeted queries have
/// a different surprise distribution from uniform ones, so feeding their
/// residuals back would let an intervention manufacture its own next alarm.
/// Revisits enter the model and the replay window and never this. Astra's
/// contract, written before the first run rather than after it.
///
/// It needs NO ADDITIONAL SENSING QUERIES — `observe` already returns
/// surprise. The arithmetic is small but not zero.
pub const Trigger = struct {
    fast: f64 = 0,
    slow: f64 = 0,
    af: f64,
    as_: f64,
    /// MONITORING observations seen. The cooldown is counted in these, not
    /// in wall indices, because an intervention's own queries must not run
    /// the clock down on the silence that follows it.
    seen: u64 = 0,
    started: bool = false,
    /// Frozen on a SEPARATE calibration trajectory before any evaluation.
    /// Zero means uncalibrated and `fire` refuses.
    thresh: f64 = 0,
    cool_until: u64 = 0,
    /// How many nonzero monitoring surprises establish the seed.
    ///
    /// One is the incumbent and seeds from a SINGLE DRAW, which is the
    /// weakness G69 (c) traced: the two trajectories seeded on 0.049409 and
    /// 0.006119, an eightfold gap, and the slow EWMA's half-life carries it
    /// for a long time. Larger values seed from an ESTIMATE instead. The
    /// surprises consumed during seeding establish it and are not otherwise
    /// fed. At 1 the arithmetic is the incumbent's exactly.
    seed_from: usize = 1,
    seed_sum: f64 = 0,
    seed_n: usize = 0,
    budget: usize,
    fired: usize = 0,
    /// Set while an intervention is in progress: firing is paused, and the
    /// detector takes no updates because no monitoring is happening.
    busy: bool = false,

    pub fn init(half_fast: f64, half_slow: f64, budget: usize) Trigger {
        return .{
            .af = 1 - std.math.pow(f64, 2, -1 / half_fast),
            .as_ = 1 - std.math.pow(f64, 2, -1 / half_slow),
            .budget = budget,
        };
    }
    /// One MONITORING observation. Returns the ratio after the update.
    ///
    /// **Seeding waits for the first NONZERO surprise.** Seeding on the
    /// first surprise whatever it is does not fix the manufactured alarm
    /// when that surprise is zero — both accumulators start at zero again
    /// and the next positive value reopens the ratio at `h_slow/h_fast`.
    /// This fixture HAS an exactly-zero region: past the window the target
    /// is zero, an empty model predicts zero, and the residual is exactly
    /// zero. Astra found it in review, before any run. Until the seed
    /// arrives the ratio is 1 — neutral, and firing is refused anyway
    /// because an unseeded detector has nothing to compare.
    ///
    /// Refuses to update while BUSY, so that a controller which wrongly
    /// routed an acquisition query here cannot silently corrupt the
    /// detector; the controller is separately asserted not to call it.
    pub fn monitor(self: *Trigger, surprise: f32) f64 {
        if (self.busy) return self.ratio();
        const s = @as(f64, surprise);
        if (!self.started) {
            if (s == 0) {
                self.seen += 1;
                return 1;
            }
            self.seed_sum += s;
            self.seed_n += 1;
            self.seen += 1;
            if (self.seed_n < self.seed_from) return 1;
            const m0 = self.seed_sum / @as(f64, @floatFromInt(self.seed_n));
            self.fast = m0;
            self.slow = m0;
            self.started = true;
            return 1;
        } else {
            self.fast += self.af * (s - self.fast);
            self.slow += self.as_ * (s - self.slow);
        }
        self.seen += 1;
        return self.ratio();
    }
    pub fn ratio(self: Trigger) f64 {
        if (!self.started) return 1;
        return self.fast / @max(1e-9, self.slow);
    }
    /// Whether an intervention starts now. Refuses while busy, while
    /// uncalibrated, while cooling down, and once the budget is spent.
    /// Whether the detector CROSSES its threshold now. A crossing is not an
    /// intervention: the controller decides whether one can be executed, and
    /// charges the budget only when it starts. Reporting them apart is what
    /// lets a cold-start prediction be tested on the STATISTIC rather than
    /// on whatever readiness rule happens to gate it.
    pub fn crosses(self: *Trigger) bool {
        if (self.busy or self.thresh == 0 or !self.started) return false;
        if (self.seen < self.cool_until) return false;
        return self.ratio() > self.thresh;
    }
    /// Charge one intervention. Only the controller calls this, and only
    /// when an intervention actually begins.
    pub fn charge(self: *Trigger) void {
        self.fired += 1;
    }
    pub fn spent(self: Trigger) bool {
        return self.fired >= self.budget;
    }
    pub fn cooldown(self: *Trigger, obs: u64) void {
        self.cool_until = self.seen + obs;
    }
};

/// OBS-22's trajectory shape. One clock, and every paid observation advances
/// it — revisits included — so a gradual drift continues through an
/// intervention rather than waiting politely for it.
pub const Traj = struct {
    total: u64,
    /// Queries per intervention.
    r: usize,
    /// The hard window, and the replay slots the sleep consolidates from.
    w: usize,
    n: usize,
    /// Score the model against the world AT THAT INSTANT, this often.
    check: u64,
    /// End of the cold start — where the model is merely undertrained. Q2's
    /// interval, and NOT the same as `change_at`: between them lies a
    /// stationary stretch with a settled model, where a crossing means
    /// something different. Counted apart.
    cold_end: u64,
    change_at: u64,
    drift_lo: u64,
    drift_hi: u64,
    budget: usize,
    /// Phase end indices, for segmenting the objective. The registered
    /// drift-and-tail score is the last two.
    bounds: []const u64,

    pub fn phaseOf(self: Traj, i: u64) usize {
        for (self.bounds, 0..) |b, k| {
            if (i <= b) return k;
        }
        return self.bounds.len - 1;
    }
};

/// The world at one instant. Linear in the drift band, and this is the ONE
/// definition — a controller that interpolated privately would prove only
/// that its own formula was self-consistent.
pub fn worldAt(c: Traj, i: u64, a: marl.TruthParams, b: marl.TruthParams, d: marl.TruthParams) marl.TruthParams {
    if (i < c.change_at) return a;
    if (i <= c.drift_lo) return b;
    if (i >= c.drift_hi) return d;
    const u = @as(f32, @floatFromInt(i - c.drift_lo)) / @as(f32, @floatFromInt(c.drift_hi - c.drift_lo));
    var t = b;
    inline for (0..3) |k| t.shift[k] = b.shift[k] + u * (d.shift[k] - b.shift[k]);
    return t;
}

/// How an arm decides when to intervene.
pub const Plan = union(enum) {
    /// Online, from monitoring observations only.
    trigger,
    /// A fixed cadence, detecting nothing. Not a straw man: it is what a
    /// system without a trigger actually does.
    at: []const u64,
    /// No interventions at all: the whole horizon spent observing.
    never,
};

/// What happened and when, for asserting ORDER rather than counts.
///
/// `do_sleep = false` cannot reveal whether a checkpoint saw the replacement
/// model, because there is no replacement — so the event is emitted either
/// way and the cheap gate asserts the sequence. Astra's instrument.
pub const Event = struct {
    kind: enum { start, sleep, check },
    at: u64,
};

/// Everything the runner must be held to, counted rather than assumed.
pub const Tally = struct {
    /// Every paid observation, of every kind. Must equal `Traj.total`.
    paid: u64 = 0,
    /// Those the detector was offered. Revisits must never appear here.
    monitored: u64 = 0,
    revisits: u64 = 0,
    /// Steps at which the detector was eligible and above threshold, whether
    /// or not an intervention followed. **Not the same as interventions**:
    /// readiness gates every cold-start execution regardless of what the
    /// statistic wanted, so a restraint claim tested on EXECUTIONS would be
    /// vacuous.
    crossings: usize = 0,
    /// Split at `cold_end` and `change_at`, because "before the world moved"
    /// lumps an undertrained model together with a settled one and Q2 is
    /// about the first.
    crossings_cold: usize = 0,
    crossings_settled: usize = 0,
    first_cross: u64 = 0,
    /// Crossings refused because the window was not yet full (DEFERRED, and
    /// re-evaluated every step) or because fewer than `r` queries remained
    /// before the horizon (BLOCKED outright).
    unready: usize = 0,
    horizon_blocked: usize = 0,
    /// Interventions actually begun, and consolidations actually run.
    started: usize = 0,
    sleeps: usize = 0,
    checks: usize = 0,
    /// Time-averaged error: the MEAN RMS over checkpoints, not pooled MSE.
    err_sum: f64 = 0,
    /// The same, segmented by phase, so the registered drift-and-tail
    /// objective is a measurement rather than an arithmetic afterthought.
    err_phase: [8]f64 = .{0} ** 8,
    checks_phase: [8]usize = .{0} ** 8,
    /// Error over the two checkpoints after each intervention completes —
    /// Q7's "what the error did afterwards", reported per intervention and
    /// never scored as a false alarm.
    post_err: [8]f64 = .{0} ** 8,
    post_n: [8]usize = .{0} ** 8,
    watch_until: u64 = 0,
    watch_idx: usize = 0,
    watching: bool = false,
    /// Interventions begun, by phase.
    started_phase: [8]usize = .{0} ** 8,
    /// Budget remaining when the clock first reaches drift onset, on the
    /// COMMON paid clock and counting interventions actually STARTED — so it
    /// is correct for arms whose plan never touches the trigger, and an
    /// intervention beginning exactly at drift onset is NOT counted, because
    /// the snapshot is taken before the decision at that index.
    budget_at_drift: usize = 0,
    drift_marked: bool = false,
    fired_at: [8]u64 = .{0} ** 8,
    /// Consolidations whose refinement was REJECTED by the acceptance rule.
    /// Zero unless `Recipe.guard` is on; reported either way, because "the
    /// guard never fired" is a measurement and not an assumption.
    rejections: usize = 0,
    /// THE RESOURCE TRADE, which OBS-22 did not report at all. `none` never
    /// prunes; a sleeping arm halves and regrows. A comparison that reports
    /// error alone is the un-matched comparison OBS-20 was corrected for.
    k_final: usize = 0,
    k_peak: usize = 0,
    k_sum: u64 = 0,
    k_n: usize = 0,
    /// Topology acquired over the whole trajectory, SUMMED ACROSS
    /// consolidations — a sleep replaces the model and resets its counter,
    /// so a single read at the end measures only the last segment. Kernels
    /// a consolidation CARRIES OVER are not births, which is the right
    /// semantics: this counts what the birth rule bought, not what the
    /// model holds.
    births_total: u64 = 0,
    /// A running hash over the FRESH draws alone — never a revisit — and the
    /// same hash snapshotted at `prefix_at` fresh draws.
    ///
    /// The fresh-draw stream advances once per fresh observation and never
    /// for a revisit, so arms that do not revisit draw the IDENTICAL
    /// locations in the identical order, and arms that do draw a PREFIX of
    /// that same sequence. **That is a contract, not a summary**, and
    /// OBS-21's ring is what a gate reporting it as counts costs.
    /// Summed `Kernel.updates` at the end of a continuation. `adopt` zeroes
    /// every kernel's counter, so this separates a branch that CONTINUED a
    /// model from one that was rebuilt out of its kernels — at any scale,
    /// which a maximum does not.
    updates_sum: u64 = 0,
    stream_hash: u64 = 1469598103934665603,
    stream_prefix: u64 = 0,
    prefix_at: u64 = 0,
    /// A signature of the `r` locations each intervention TARGETED, one per
    /// intervention.
    ///
    /// Astra's caveat, made measurable: after a consolidation the model
    /// differs, so admission surprises differ, so the window's ranking
    /// differs — two arms sharing a fresh stream need not revisit the same
    /// places at their second and third interventions. A consolidation's
    /// effect therefore INCLUDES its feedback into later acquisition, and
    /// without this the caveat would only be prose.
    ///
    /// It establishes WHETHER the targeting diverged and from which
    /// intervention, not by how much: a hash is identical or it is not.
    rev_hash: [8]u64 = .{0} ** 8,
    /// The error at every checkpoint, in order. Checkpoints sit at fixed
    /// GLOBAL indices identical across arms — `check_err[k]` is the score at
    /// `(k + 1) * Traj.check` — so two arms' traces are directly comparable
    /// row by row.
    ///
    /// Astra's, for the question OBS-23 raises and cannot answer: *when* do
    /// two schedules' error trajectories separate? A phase mean cannot
    /// localise that, and without the trace the answer costs another run of
    /// the campaign's largest gate.
    check_err: [64]f64 = .{0} ** 64,
    trace: [64]Event = undefined,
    ntrace: usize = 0,

    pub fn mean(self: Tally) f64 {
        return self.err_sum / @as(f64, @floatFromInt(@max(1, self.checks)));
    }
    /// The registered drift-and-tail objective: the last two phases.
    pub fn meanTail(self: Tally, nphase: usize) f64 {
        var e: f64 = 0;
        var n: usize = 0;
        for (nphase - 2..nphase) |k| {
            e += self.err_phase[k];
            n += self.checks_phase[k];
        }
        return e / @as(f64, @floatFromInt(@max(1, n)));
    }
    /// Mean population over checkpoints. The final one alone hides three
    /// halvings and three regrowths.
    pub fn meanK(self: Tally) f64 {
        return @as(f64, @floatFromInt(self.k_sum)) / @as(f64, @floatFromInt(@max(1, self.k_n)));
    }
    /// FNV-1a over the fresh query's bits, in order. Order-sensitive by
    /// construction, which is the whole point of it.
    fn mix(self: *Tally, q: [3]f32) void {
        for (q) |v| {
            var b = @as(u32, @bitCast(v));
            for (0..4) |_| {
                self.stream_hash ^= b & 0xff;
                self.stream_hash *%= 1099511628211;
                b >>= 8;
            }
        }
        if (self.prefix_at != 0 and self.monitored == self.prefix_at) self.stream_prefix = self.stream_hash;
    }
    fn note(self: *Tally, kind: @TypeOf(@as(Event, undefined).kind), at: u64) void {
        if (self.ntrace < self.trace.len) {
            self.trace[self.ntrace] = .{ .kind = kind, .at = at };
            self.ntrace += 1;
        }
    }
};

/// One intervention, taken apart. Astra's diagnostic specification: the
/// world's RMS before acquisition, after acquisition and immediately after
/// the sleep, on IDENTICAL probes; the actual populations either side; the
/// births since the previous sleep; and the refinement's own fitting error.
///
/// Without the populations, "roughly an eighth" is speculation — regrowth
/// has to be counted, not assumed away.
pub const Step = struct {
    at: u64 = 0,
    rms_before: f64 = 0,
    /// **The pre-acquisition model, scored against the COMPLETION-TIME
    /// world.** Without it `rms_before` and `rms_after_acq` are scored
    /// against different worlds whenever an acquisition spans a change —
    /// which the first one here does, running 26 000 to 30 096 across a step
    /// at 30 000. Astra caught it; the 0.06059 -> 0.13428 it produced
    /// establishes nothing about acquisition.
    rms_frozen_end: f64 = 0,
    rms_after_acq: f64 = 0,
    rejected: bool = false,
    rms_after_sleep: f64 = 0,
    k_before: usize = 0,
    k_after: usize = 0,
    births_since: u64 = 0,
    fit_first: f64 = 0,
    fit_last: f64 = 0,
};

pub const Diag = struct {
    steps: [8]Step = [_]Step{.{}} ** 8,
    n: usize = 0,
};

/// What an intervention actually DOES, as two separable mechanisms.
///
/// OBS-22 measured their sum against zero and refuted Q6 — no policy beat
/// `none` — without being able to say which half failed to earn its cost.
/// **The defaults are OBS-22's recipe exactly**, so every gate written
/// before OBS-23 keeps its numbers by passing `.{}`.
///
/// The two are not symmetric in the clock, and that asymmetry is the reason
/// OBS-23 needs six arms rather than four: an arm spending `r` observations
/// on revisits **cannot also consolidate at the fire instant**, because the
/// revisits advance the common clock. Its matched no-revisit cell is
/// therefore PLACED AT `t + r` and consolidates immediately, having spent
/// its `r` on ordinary fresh draws — it does not fire early. A cell list
/// that ignores this measures WHEN the sleep happened as well as what
/// preceded it.
///
/// **And what the pair estimates is a repeated POLICY.** After the first
/// consolidation the model differs, so admission surprises differ, so the
/// window's ranking differs — two arms sharing a fresh stream need not
/// target the same locations at their second and third interventions. A
/// consolidation's effect includes its feedback into later acquisition, and
/// no contrast in this design separates the two.
pub const Recipe = struct {
    /// Spend `r` observations re-asking the window's highest-surprise
    /// locations. False spends them on the ordinary fresh stream instead —
    /// so the horizon is matched either way and only the SPEND differs.
    revisit: bool = true,
    /// Consolidate when the intervention completes.
    consolidate: bool = true,
    /// The replay-loss acceptance rule OBS-22 (b) established prevents a
    /// diverging refinement. Off by default because `Options.guard` is, and
    /// because OBS-22's registered recipe did not have it.
    guard: bool = false,
};

/// Optional instrumentation and a fork, both off by default so that adding
/// them cannot move a recorded number.
pub const Probe = struct {
    diag: ?*Diag = null,
    /// Replace the consolidation at this intervention index (0-based).
    fork_at: ?usize = null,
    /// `half` is the registered recipe; `skip` performs no consolidation;
    /// `full` consolidates to the PARENT'S population, which refits and
    /// refines without compressing.
    ///
    /// `norefine` does selection and the LINEAR refit only, zero descent
    /// steps — so a disastrous linear fit is distinguished from a disastrous
    /// refinement. `guarded` keeps the refinement but rejects one that ends
    /// non-finite or above its starting replay loss.
    ///
    /// `relabel` keeps the same points and the same selection and re-reads
    /// every label from the world at COMPLETION TIME. It needs an oracle per
    /// point, so it is a probe and never a policy — the same instrument
    /// OBS-18, OBS-20 and OBS-21 used. It tests whether the historical
    /// labels a drifting window carries are what the refinement failed on.
    fork_mode: enum { half, skip, full, norefine, guarded, relabel } = .half,
};

/// Stop an arm just before one of its consolidations and take the LIVE
/// learning state out, rather than a reconstruction of it.
///
/// **Astra's contract, and it is not cosmetic.** A `skip` branch has to
/// continue the ACTUAL parent. Rebuilding it as `adopt(parent.kernels)` would
/// reset every kernel's Adam moments `m1`/`m2`, its step counter `t`, its
/// `updates` and its drift origin `mu0`, and would hand it a fresh `Model` —
/// fresh `stats`, a fresh model RNG stream, and a fresh `recent` residual
/// ring, WHICH GATES BIRTHS. That branch would be "adopt without
/// consolidating", an intervention of its own rather than the control.
///
/// `adopt` stays right for the consolidated candidates, because a
/// consolidation does exactly that. The asymmetry is what the policies
/// differ by.
pub const Hand = struct {
    /// Take the state instead of running the consolidation that would be
    /// this arm's `stop_before`-th (0-based).
    stop_before: usize,
    taken: bool = false,
    m: marl.Model = undefined,
    win: Window = undefined,
    st: rng.Stream = undefined,
    at: u64 = 0,
    /// Whether a checkpoint was awaiting the consolidation at that instant.
    /// Handed out rather than assumed away.
    pending: bool = false,
};

/// Run one arm over the whole trajectory.
///
/// `do_sleep` is the injected stub: false runs every part of the controller
/// EXCEPT the expensive `sleepOn`, so the structural gate can exercise this
/// exact code path in seconds. The sleep EVENT is emitted either way, so
/// ordering is testable without paying for a consolidation.
pub fn runArm(
    gpa: std.mem.Allocator,
    o: marl.Options,
    c: Traj,
    plan: Plan,
    trig: *Trigger,
    worlds: [3]marl.TruthParams,
    probes: [][3]f32,
    do_sleep: bool,
    st: *rng.Stream,
    out: *Tally,
    probe: Probe,
    recipe: Recipe,
    hand: ?*Hand,
) !void {
    var m = try marl.Model.init(gpa, o);
    var handed = false;
    defer if (!handed) m.deinit();
    var win = try Window.init(gpa, c.w);
    defer if (!handed) win.deinit(gpa);
    const vals = try gpa.alloc([1]f32, probes.len);
    defer gpa.free(vals);
    const pick = try gpa.alloc(usize, c.w);
    defer gpa.free(pick);
    const pts = try gpa.alloc([3]f32, c.r);
    defer gpa.free(pts);

    var i: u64 = 0;
    var next_at: usize = 0;
    var births_mark: u64 = 0;
    // A checkpoint reached by an ordinary observation is held until the
    // TOP of the next iteration, so that an intervention completing at that
    // same index is scored BEFORE it. See the ordering note below.
    var pending = false;
    while (i < c.total) {
        // The drift snapshot, on the COMMON clock and BEFORE this index's
        // decision — so an intervention beginning exactly at onset is not
        // counted as already spent.
        if (!out.drift_marked and i >= c.drift_lo) {
            out.budget_at_drift = c.budget - out.started;
            out.drift_marked = true;
        }

        var want = false;
        switch (plan) {
            .never => {},
            .at => |times| want = next_at < times.len and i >= times[next_at],
            .trigger => want = trig.crosses(),
        }
        if (want) {
            if (plan == .trigger) {
                out.crossings += 1;
                if (out.first_cross == 0) out.first_cross = i;
                if (i < c.cold_end) {
                    out.crossings_cold += 1;
                } else if (i < c.change_at) {
                    out.crossings_settled += 1;
                }
            }
            const ready = win.n >= @as(u64, c.w);
            const room = i + @as(u64, c.r) <= c.total;
            if (!ready) out.unready += 1;
            if (ready and !room) out.horizon_blocked += 1;
            if (ready and room and !(plan == .trigger and trig.spent())) {
                if (hand) |h| {
                    if (!h.taken and out.started == h.stop_before) {
                        // Ownership moves to the caller: the model, the
                        // window and the fresh-draw stream exactly as they
                        // stand, with nothing reconstructed.
                        h.m = m;
                        h.win = win;
                        h.st = st.*;
                        h.at = i;
                        h.pending = pending;
                        h.taken = true;
                        handed = true;
                        return;
                    }
                }
                // **The registered order is observation, then the COMPLETED
                // intervention's sleep, then the score.** The two halves of
                // OBS-23's lattice complete at different instants and the
                // rule has to be applied to each:
                //
                //   * an intervention that spends `r` observations completes
                //     `r` LATER than it starts, so a checkpoint at its start
                //     instant belongs BEFORE it — scored here. A checkpoint
                //     landing on its LAST query is the `due` deferral below.
                //   * one that spends none completes at the instant it
                //     starts, so that checkpoint must wait for the
                //     consolidation — it stays pending and is scored at the
                //     top of the next iteration, after this block's
                //     `continue`.
                //
                // The immediate path did not exist when OBS-22 was written,
                // and adding it reintroduced OBS-22's score-ordering bug on
                // the new branch. Astra caught it by reading the loop again;
                // G70 (a) asserts BOTH paths at timings where the sleep
                // lands exactly on a checkpoint.
                if (recipe.revisit and pending) {
                    pending = false;
                    try score(&m, c, i, worlds, probes, vals, out);
                }
                if (plan == .at) next_at += 1;
                if (plan == .trigger) trig.charge();
                if (out.started < out.fired_at.len) out.fired_at[out.started] = i;
                out.started_phase[c.phaseOf(i)] += 1;
                out.note(.start, i);
                out.started += 1;
                trig.busy = true;
                var before_acq: f64 = 0;
                var frozen: ?marl.Model = null;
                defer if (frozen) |*f| f.deinit();
                if (probe.diag != null) {
                    for (probes, 0..) |pz, k| vals[k] = .{marl.truthOf(worldAt(c, i, worlds[0], worlds[1], worlds[2]), pz)};
                    before_acq = try m.rms(probes, vals, null);
                    // A prediction-identical copy, held back so the world's
                    // own motion can be separated from acquisition's effect.
                    frozen = try adopt(gpa, o, m.kernels.items);
                }

                var due = false;
                // **The aiming half.** Without it the same `r` observations
                // are spent on the ordinary fresh stream instead, so the
                // horizon is matched and only the SPEND differs — which is
                // OBS-23's first factor. An arm with `revisit = false`
                // consumes no observations here at all, and its
                // consolidation therefore lands at the fire instant; the
                // clock-matched cell is the one placed `r` later.
                if (recipe.revisit) {
                    for (0..c.w) |k| pick[k] = k;
                    std.mem.sort(usize, pick, win.s, struct {
                        fn lt(sv: []const f32, x: usize, y: usize) bool {
                            return sv[x] > sv[y];
                        }
                    }.lt);
                    for (pick[0..c.r], 0..) |k, j| pts[j] = win.x[k];
                    if (out.started - 1 < out.rev_hash.len) {
                        var h: u64 = 1469598103934665603;
                        for (pts) |qp| for (qp) |vv| {
                            var bb = @as(u32, @bitCast(vv));
                            for (0..4) |_| {
                                h ^= bb & 0xff;
                                h *%= 1099511628211;
                                bb >>= 8;
                            }
                        };
                        out.rev_hash[out.started - 1] = h;
                    }
                    for (pts, 0..) |q, j| {
                        const tp = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
                        const v: f64 = marl.truthOf(tp, q);
                        const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
                        win.push(q, v, ev.surprise, ev.cover);
                        out.paid += 1;
                        out.revisits += 1;
                        i += 1;
                        // **The registered ordering: observation, then the
                        // completed intervention's sleep, THEN the score.** A
                        // checkpoint landing on the LAST query is deferred past
                        // the consolidation, so it never reports a model that is
                        // about to be replaced. An earlier draft scored it first
                        // and Astra caught it by reading the loop.
                        if (i % c.check == 0) {
                            if (j + 1 == c.r) due = true else try score(&m, c, i, worlds, probes, vals, out);
                        }
                    }
                }
                var step = Step{ .at = i, .k_before = m.kernels.items.len };
                if (probe.diag) |d| {
                    step.rms_before = before_acq;
                    for (probes, 0..) |pz, k| vals[k] = .{marl.truthOf(worldAt(c, i, worlds[0], worlds[1], worlds[2]), pz)};
                    step.rms_after_acq = try m.rms(probes, vals, null);
                    if (frozen) |*f| step.rms_frozen_end = try f.rms(probes, vals, null);
                    step.births_since = m.stats.births - births_mark;
                    _ = d;
                }
                const forked = probe.fork_at != null and probe.fork_at.? == out.started - 1;
                const mode = if (forked) probe.fork_mode else .half;
                if (do_sleep and recipe.consolidate and mode != .skip) {
                    var buf = try Replay.initWith(gpa, c.n, .err, 0x33);
                    defer buf.deinit(gpa);
                    win.selectInto(&buf);
                    const keep: usize = if (mode == .full) m.kernels.items.len else m.kernels.items.len / 2;
                    if (mode == .relabel) {
                        const now = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
                        for (buf.x[0..c.n], 0..) |qz, k| buf.y[k] = marl.truthOf(now, qz);
                    }
                    var so = Options{ .exact = true };
                    if (mode == .norefine) so.steps = 0;
                    if (mode == .guarded or recipe.guard) so.guard = true;
                    var rep: Report = undefined;
                    var child = try sleepOnReporting(gpa, &m, buf.x[0..c.n], buf.y[0..c.n], keep, so, &rep, null);
                    errdefer child.deinit();
                    // **A consolidation REPLACES the model, and the child's
                    // birth counter starts at zero**, so the segment's
                    // births have to be banked here or the trajectory total
                    // silently becomes "births since the last sleep". The
                    // first run of G70 printed exactly that and it read as a
                    // finding — the sleeping arms looked as though they had
                    // bought a third of the topology. `none` and `revisit`
                    // reading births EXACTLY equal to their final population
                    // is what gave it away.
                    out.births_total += m.stats.births;
                    m.deinit();
                    m = child;
                    step.fit_first = rep.first;
                    step.fit_last = rep.last;
                    step.rejected = rep.rejected;
                    if (rep.rejected) out.rejections += 1;
                }
                if (probe.diag) |d| {
                    step.k_after = m.kernels.items.len;
                    for (probes, 0..) |pz, k| vals[k] = .{marl.truthOf(worldAt(c, i, worlds[0], worlds[1], worlds[2]), pz)};
                    step.rms_after_sleep = try m.rms(probes, vals, null);
                    if (d.n < d.steps.len) {
                        d.steps[d.n] = step;
                        d.n += 1;
                    }
                }
                births_mark = m.stats.births;
                // Counted for an arm that CONSOLIDATES, whether or not the
                // expensive call ran — `do_sleep = false` is the stub, and
                // G69 (a) asserts ordering through the event it still emits.
                // An arm with `consolidate = false` has no sleep to order.
                if (recipe.consolidate) {
                    out.sleeps += 1;
                    out.note(.sleep, i);
                }
                out.watch_until = i + 2 * c.check;
                out.watch_idx = out.started - 1;
                out.watching = true;
                if (due) try score(&m, c, i, worlds, probes, vals, out);
                trig.busy = false;
                trig.cooldown(@as(u64, c.w));
                continue;
            }
            if (plan == .at and !room) next_at += 1;
        }

        if (pending) {
            pending = false;
            try score(&m, c, i, worlds, probes, vals, out);
        }

        const tp = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const v: f64 = marl.truthOf(tp, q);
        const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
        win.push(q, v, ev.surprise, ev.cover);
        _ = trig.monitor(ev.surprise);
        out.paid += 1;
        out.monitored += 1;
        out.mix(q);
        i += 1;
        if (i % c.check == 0) pending = true;
    }
    // The horizon's own checkpoint. It can never be followed by an
    // intervention, so it is scored here rather than lost with the loop.
    if (pending) try score(&m, c, i, worlds, probes, vals, out);
    out.k_final = m.kernels.items.len;
    out.births_total += m.stats.births;
}

fn score(
    m: *marl.Model,
    c: Traj,
    i: u64,
    worlds: [3]marl.TruthParams,
    probes: [][3]f32,
    vals: [][1]f32,
    out: *Tally,
) !void {
    const tp = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
    for (probes, 0..) |p, k| vals[k] = .{marl.truthOf(tp, p)};
    const e = try m.rms(probes, vals, null);
    out.err_sum += e;
    out.checks += 1;
    out.k_sum += m.kernels.items.len;
    out.k_n += 1;
    if (out.checks - 1 < out.check_err.len) out.check_err[out.checks - 1] = e;
    out.k_peak = @max(out.k_peak, m.kernels.items.len);
    const ph = c.phaseOf(i);
    out.err_phase[ph] += e;
    out.checks_phase[ph] += 1;
    if (out.watching and i <= out.watch_until and out.watch_idx < out.post_err.len) {
        out.post_err[out.watch_idx] += e;
        out.post_n[out.watch_idx] += 1;
        if (i >= out.watch_until) out.watching = false;
    }
    out.note(.check, i);
}

/// Freeze the trigger's threshold on a SEPARATE trajectory that is never
/// scored and never reused as an evaluation arm.
///
/// The first draft of OBS-22 estimated it from observations 12 000-30 000 of
/// the trajectory it was then tested on, and tested cold-start restraint at
/// t < 12 000 — a trigger calibrated on its own future. Astra caught it
/// before any code existed.
///
/// Pinned: the seed, the stretch, the sampling (every monitoring
/// observation), and the convention — **population** standard deviation, and
/// `mean(ratio) + 3*sd(ratio)` rather than `1 + 3*sd`, because a stationary
/// world does not imply a ratio centred at one. The learner's own residuals
/// are not stationary either.
///
/// Three standard deviations is a REGISTERED HEURISTIC, not a calibrated
/// false-alarm probability: the checks are thousands and heavily correlated,
/// and nothing here computes a family-wise rate.
pub fn calibrate(
    gpa: std.mem.Allocator,
    o: marl.Options,
    c: Traj,
    worlds: [3]marl.TruthParams,
    half_fast: f64,
    half_slow: f64,
    seed: u64,
    lo: u64,
    hi: u64,
) !struct { thresh: f64, mean: f64, sd: f64, n: usize } {
    var m = try marl.Model.init(gpa, o);
    defer m.deinit();
    var trig = Trigger.init(half_fast, half_slow, 0);
    var st = rng.Stream.region(seed, 0x4341_4c42, 0); // "CALB"
    var sum: f64 = 0;
    var sum2: f64 = 0;
    var n: usize = 0;
    var i: u64 = 0;
    while (i < hi) : (i += 1) {
        const tp = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const v: f64 = marl.truthOf(tp, q);
        const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
        const r = trig.monitor(ev.surprise);
        if (i >= lo) {
            sum += r;
            sum2 += r * r;
            n += 1;
        }
    }
    const fn_ = @as(f64, @floatFromInt(@max(1, n)));
    const mean = sum / fn_;
    const sd = @sqrt(@max(0, sum2 / fn_ - mean * mean));
    return .{ .thresh = mean + 3 * sd, .mean = mean, .sd = sd, .n = n };
}

/// Stream `n` exemplars past every buffer AND every window at once — one
/// model, one stream, so no two arms can differ by a draw.
pub fn wakeInto(
    m: *marl.Model,
    n: u64,
    bufs: []const *Replay,
    wins: []const *Window,
    st: *rng.Stream,
) !void {
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const v = marl.truthOf(m.opts.truth, q);
        const ev = try m.observe(q, .{v});
        for (bufs) |b| b.admit(q, v, ev.surprise, ev.cover);
        for (wins) |w| w.push(q, v, ev.surprise, ev.cover);
    }
}

/// Stream `n` exemplars of the model's current truth past every buffer at
/// once. ONE model, ONE stream, one exemplar offered to each rule — so two
/// arms cannot differ by a draw, only by what they chose to keep.
pub fn wakeAll(m: *marl.Model, n: u64, bufs: []const *Replay, st: *rng.Stream) !void {
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const v = marl.truthOf(m.opts.truth, q);
        const ev = try m.observe(q, .{v});
        for (bufs) |b| b.admit(q, v, ev.surprise, ev.cover);
    }
}

/// Stream `n` exemplars, keeping what one buffer's rule keeps. The model's
/// own `stream_n` with the observations retained.
pub fn wake(m: *marl.Model, n: u64, buf: *Replay, st: *rng.Stream) !void {
    var one = [_]*Replay{buf};
    return wakeAll(m, n, &one, st);
}

/// Sleep against whatever target is supplied at the replay points.
fn sleepOn(
    gpa: std.mem.Allocator,
    m: *marl.Model,
    pts: []const [3]f32,
    target: []const f64,
    keep: usize,
    o: Options,
) !marl.Model {
    return sleepOnReporting(gpa, m, pts, target, keep, o, null, null);
}

/// The same consolidation with the refinement's own `Report` handed back —
/// the descent's fitting error at its first and last step. OBS-22's
/// diagnostic needs it to separate damage done by ACQUISITION from damage
/// done by CONSOLIDATION, and `sleepOn` discarded it.
fn sleepOnReporting(
    gpa: std.mem.Allocator,
    m: *marl.Model,
    pts: []const [3]f32,
    target: []const f64,
    keep: usize,
    o: Options,
    report: ?*Report,
    split: ?*Split,
) !marl.Model {
    const reff = try gpa.alloc(f64, m.regions.len);
    defer gpa.free(reff);
    var total: f64 = 0;
    for (m.regions, 0..) |*reg, ri| {
        reff[ri] = 0;
        if (reg.own.items.len == 0) continue;
        const tmp = try gpa.alloc(marl.Kernel, reg.own.items.len);
        defer gpa.free(tmp);
        for (reg.own.items, 0..) |g, i| tmp[i] = m.kernels.items[g];
        const sub = try sampleKernels(gpa, tmp, pts);
        defer sub.deinit(gpa);
        var g = try novelty.gramOf(gpa, sub);
        defer g.deinit(gpa);
        const lam = try novelty.eigenvalues(gpa, g);
        defer gpa.free(lam);
        reff[ri] = novelty.effectiveRank(lam);
        total += reff[ri];
    }
    const room = try gpa.alloc(usize, m.regions.len);
    defer gpa.free(room);
    for (m.regions, 0..) |*reg, ri| room[ri] = reg.own.items.len;
    const budget = try allocate(gpa, reff, room, keep, o.exact);
    defer gpa.free(budget);

    var out = std.ArrayListUnmanaged(marl.Kernel){};
    defer out.deinit(gpa);
    for (m.regions, 0..) |*reg, ri| {
        if (reg.own.items.len == 0) continue;
        const k = budget[ri];
        const tmp = try gpa.alloc(marl.Kernel, reg.own.items.len);
        defer gpa.free(tmp);
        for (reg.own.items, 0..) |g, i| tmp[i] = m.kernels.items[g];
        const sub = try sampleKernels(gpa, tmp, pts);
        defer sub.deinit(gpa);
        const sel = try novelty.selectExplaining(gpa, sub, target, k);
        defer gpa.free(sel);
        for (sel) |j| try out.append(gpa, tmp[j]);
    }
    const picked = try sampleKernels(gpa, out.items, pts);
    defer picked.deinit(gpa);
    const w = try novelty.refit(gpa, picked, target);
    defer gpa.free(w);
    for (out.items, w) |*k, wv| k.p[marl.PARAMS - 1] = @floatCast(wv);
    // **The post-linear-refit candidate exists exactly here** — selection
    // done, weights solved, nothing descended. Duplicated for a fork so that
    // two branches can be built from the same bytes rather than the same
    // seed.
    if (split) |sp| sp.linear = try gpa.dupe(marl.Kernel, out.items);
    var snap: []marl.Kernel = &.{};
    if (o.guard) snap = try gpa.dupe(marl.Kernel, out.items);
    defer if (o.guard) gpa.free(snap);
    var rep = try refine(gpa, out.items, pts, target, m.opts.regions, o);
    // And here is what the refinement produced, BEFORE acceptance can throw
    // it away. OBS-22 kept its replay loss and discarded its kernels, so
    // nobody could ask what it had done to the current world.
    if (split) |sp| sp.attempted = try gpa.dupe(marl.Kernel, out.items);
    if (o.guard and (!std.math.isFinite(rep.last) or rep.last > rep.first)) {
        @memcpy(out.items, snap);
        rep.rejected = true;
        // The restore is verified where it happens, not inferred from a
        // printed digit downstream. `rep.last` remains the ATTEMPTED
        // post-refinement loss — it is NOT the returned candidate's loss,
        // which is `rep.first` — and the printed column says so.
        std.debug.assert(std.mem.eql(u8, std.mem.sliceAsBytes(out.items), std.mem.sliceAsBytes(snap)));
    }
    if (report) |r| r.* = rep;
    return adopt(gpa, m.opts, out.items);
}

test "G61 the lineage: is the wake/sleep cycle a ratchet, or damage accumulating?" {
    // Christian: "the crucial quantity is not whether C2 < P2 on one static
    // test, but whether the sequence forms a MONOTONIC IMPROVEMENT LOOP
    // under repeated wake/sleep cycles."
    //
    // And a design correction that surfaced before any code: OBS-13's
    // sleep-on-self can never improve, because a student fitting its
    // teacher at best matches it and MARL-19 priced a noiseless copy at
    // 1.179x. Sleep on REPLAY can — which is what OBS-11 was doing without
    // calling it that, since the truth on probes is exactly what a replay
    // buffer holds.
    //
    // **Everything here is scored on HELD-OUT probes.** A sleep is fitted
    // on the replay ring, so scoring it there is training on the test set —
    // the mistake OBS-11 had to be corrected for, made again in this gate's
    // first draft, where the replay arm read a fourteen-fold "improvement"
    // measured on its own fitting points.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const BUF: usize = 4096;

    var st = rng.Stream.region(1234, 0x4f31_3457, 0); // "O14W"
    var buf = try Replay.init(gpa, BUF);
    defer buf.deinit(gpa);

    var p0 = try marl.Model.init(gpa, o);
    defer p0.deinit();
    try wake(&p0, 20_000, &buf, &st);

    // Held out against the STANDING truth, for the sleep-target contrast.
    const hs = try marl.probes(gpa, 5150, 4096);
    defer {
        gpa.free(hs.p);
        gpa.free(hs.y);
    }

    // (1) THE CONTRAST: self against replay, both fitted on the ring and
    // both scored on probes neither saw.
    const self_t = try gpa.alloc(f64, BUF);
    defer gpa.free(self_t);
    for (buf.x[0..BUF], 0..) |q, i| self_t[i] = p0.predictAll(q)[0];
    const before = try p0.rms(hs.p, hs.y, null);

    const half0 = p0.kernels.items.len / 2;
    var s_self = try sleepOn(gpa, &p0, buf.x[0..BUF], self_t, half0, .{});
    defer s_self.deinit();
    var s_rep = try sleepOn(gpa, &p0, buf.x[0..BUF], buf.y[0..BUF], half0, .{});
    defer s_rep.deinit();
    const r_self = try s_self.rms(hs.p, hs.y, null);
    const r_rep = try s_rep.rms(hs.p, hs.y, null);
    std.debug.print("\n  G61 [{s}] the sleep target, held out: before {d:.5} -> self {d:.5} ({d:.3}x), replay {d:.5} ({d:.3}x)\n", .{
        @tagName(builtin.mode), before, r_self, r_self / before, r_rep, r_rep / before,
    });

    // (2) THE LINEAGE, on replay throughout, each model against ITS OWN ring.
    var moved = marl.TruthParams{};
    moved.shift = .{ 0, -0.10, 0 };
    const ho = try marl.probesOf(gpa, moved, 31337, 4096);
    defer {
        gpa.free(ho.p);
        gpa.free(ho.y);
    }
    var parent = try adopt(gpa, o, p0.kernels.items);
    defer parent.deinit();
    var child = try adopt(gpa, o, s_rep.kernels.items);
    defer child.deinit();
    parent.opts.truth = moved;
    child.opts.truth = moved;

    var pb = try Replay.init(gpa, BUF);
    defer pb.deinit(gpa);
    var cb = try Replay.init(gpa, BUF);
    defer cb.deinit(gpa);

    std.debug.print("  {s:<19} {s:>7} {s:>9} {s:>7}   {s:>7} {s:>9} {s:>7}   {s:>7}\n", .{ "stage", "P kern", "P RMS", "P upd", "C kern", "C RMS", "C upd", "C/P" });
    var gap: [3]f64 = undefined;
    for ([_][]const u8{ "gen 0 post-sleep", "gen 1 post-wake", "gen 2 post-sleep" }, 0..) |label, gi| {
        if (gi == 1) {
            // The SAME stream for both: equal work, equal data.
            var ps = rng.Stream.region(99, 0x5741_4b45, 0);
            var cs = rng.Stream.region(99, 0x5741_4b45, 0);
            try wake(&parent, 60_000, &pb, &ps);
            try wake(&child, 60_000, &cb, &cs);
        } else if (gi == 2) {
            // Each sleeps against ITS OWN replay. Sharing one ring would
            // hand the child the parent's experience, which is the whole
            // thing the lineage is supposed to keep apart.
            const np = try sleepOn(gpa, &parent, pb.x[0..BUF], pb.y[0..BUF], parent.kernels.items.len / 2, .{});
            parent.deinit();
            parent = np;
            parent.opts.truth = moved;
            const nc = try sleepOn(gpa, &child, cb.x[0..BUF], cb.y[0..BUF], child.kernels.items.len / 2, .{});
            child.deinit();
            child = nc;
            child.opts.truth = moved;
        }
        const pr = try parent.rms(ho.p, ho.y, null);
        const cr = try child.rms(ho.p, ho.y, null);
        gap[gi] = cr / pr;
        std.debug.print("  {s:<19} {d:>7} {d:>9.5} {d:>7.0}   {d:>7} {d:>9.5} {d:>7.0}   {d:>7.4}\n", .{
            label,                   parent.kernels.items.len, pr,                  parent.meanUpdates(),
            child.kernels.items.len, cr,                       child.meanUpdates(), gap[gi],
        });
    }
    std.debug.print("  the gap trajectory: {d:.4} -> {d:.4} -> {d:.4} — {s}\n", .{
        gap[0],                                                                                                     gap[1], gap[2],
        if (gap[2] < gap[1]) "RATCHET: the second sleep narrowed it" else "DAMAGE: the child lineage keeps paying",
    });

    // The registered contrast: self cannot improve, replay can.
    try testing.expect(r_self >= before * thresholds.OBS14_SELF_SLEEP);
    try testing.expect(r_rep < r_self);
    try testing.expect(parent.kernels.items.len > 0 and child.kernels.items.len > 0);
}

// ── OBS-15: the guardrail, and readiness ──────────────────────────────

/// The three measures an optimisation experiment runs under, named
/// explicitly and checked for aliasing.
///
/// **Promoted from a ledger note after its third occurrence.** OBS-11's
/// synthesis arm was scored on the probes it was fitted on (train 0.00227
/// against a held-out 0.05376); OBS-14's sleep-target contrast read a
/// fourteen-fold "improvement" that was really 0.855x; and OBS-8's disc was
/// a different error of the same family — a measure that was not what its
/// name said. Christian: *every optimisation experiment must name separate
/// fit and evaluation measures explicitly, and reject the experiment if any
/// alias unintentionally.*
///
/// That is boring plumbing and it is exactly the kind that prevents
/// spectacular nonsense.
pub const Measures = struct {
    /// What a descent optimises against.
    fit: []const [3]f32,
    /// What a consolidation preserves.
    sleep: []const [3]f32,
    /// What the result is scored on. Must touch neither of the others.
    eval: []const [3]f32,

    pub fn check(self: Measures) !void {
        try disjoint(self.eval, self.fit);
        try disjoint(self.eval, self.sleep);
    }

    fn disjoint(a: []const [3]f32, b: []const [3]f32) !void {
        // Exact coincidence, because these are drawn from streams and a
        // shared point means a shared DRAW, not a near miss.
        for (a) |p| {
            for (b) |q| {
                if (std.meta.eql(p, q)) return error.MeasuresAlias;
            }
        }
    }
};

/// How much of a model's OUTPUT rests on kernels too young to have settled.
///
/// Christian's scalar, and the reason it is contribution-weighted: a
/// post-wake population is heterogeneous — old kernels, newly born ones,
/// partly adapted ones — so a mean update count averages away exactly the
/// thing that matters.
///
///     R = 1 − Σ wᵢ·[uᵢ < u_min] / Σ wᵢ
///
/// One is a fully settled model; zero is one whose every contributing
/// kernel is new.
pub fn readiness(m: *const marl.Model, u_min: u32) f64 {
    var tot: f64 = 0;
    var young: f64 = 0;
    for (m.kernels.items) |*k| {
        const w = @abs(@as(f64, k.weightsConst()[0]));
        tot += w;
        if (k.updates < u_min) young += w;
    }
    if (!(tot > 0)) return 1;
    return 1 - young / tot;
}

/// Coefficient of variation of the update counts — the heterogeneity a
/// mean hides, reported beside the readiness it explains.
pub fn updateSpread(m: *const marl.Model) f64 {
    const n = m.kernels.items.len;
    if (n == 0) return 0;
    var s: f64 = 0;
    for (m.kernels.items) |*k| s += @floatFromInt(k.updates);
    const mean = s / @as(f64, @floatFromInt(n));
    if (!(mean > 0)) return 0;
    var q: f64 = 0;
    for (m.kernels.items) |*k| {
        const d = @as(f64, @floatFromInt(k.updates)) - mean;
        q += d * d;
    }
    return @sqrt(q / @as(f64, @floatFromInt(n))) / mean;
}

test "G62 (a) the guardrail fires on an aliased measure" {
    // A guardrail that cannot fail is decoration. Two sets drawn from
    // different streams pass; the same set named twice does not.
    const gpa = testing.allocator;
    const a = try marl.probes(gpa, 1, 256);
    defer {
        gpa.free(a.p);
        gpa.free(a.y);
    }
    const b = try marl.probes(gpa, 2, 256);
    defer {
        gpa.free(b.p);
        gpa.free(b.y);
    }
    const c = try marl.probes(gpa, 3, 256);
    defer {
        gpa.free(c.p);
        gpa.free(c.y);
    }
    try (Measures{ .fit = a.p, .sleep = b.p, .eval = c.p }).check();
    try testing.expectError(error.MeasuresAlias, (Measures{ .fit = a.p, .sleep = b.p, .eval = a.p }).check());
    try testing.expectError(error.MeasuresAlias, (Measures{ .fit = a.p, .sleep = c.p, .eval = c.p }).check());
    std.debug.print("\n  G62 (a) [{s}] three distinct measures pass; fit/eval and sleep/eval aliases are refused by name\n", .{@tagName(builtin.mode)});
}

test "G62 (b) when is a population ready to be rewritten?" {
    // Christian's refinement of OBS-14: the lineage data does not say
    // consolidation degrades, it says consolidation quality depends on the
    // MATURITY of the population being consolidated.
    //
    //     wake -> birth burst -> settling -> consolidation window
    //
    // One wake trajectory from a common parent on a MOVED world, with a
    // fork consolidated at each checkpoint. Same model, same stream, same
    // sleep, same budget — only the amount of settling differs.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    // The ring is allocated large and SLICED for the sweep below, because
    // the phase's own result turned on its size.
    const RING: usize = 2048;
    const BIG: usize = 32768;

    var st = rng.Stream.region(1234, 0x4f31_3557, 0); // "O15W"
    var warm = try Replay.init(gpa, RING);
    defer warm.deinit(gpa);
    var p0 = try marl.Model.init(gpa, o);
    defer p0.deinit();
    try wake(&p0, 20_000, &warm, &st);

    // The world moves, and the wake begins.
    var moved = marl.TruthParams{};
    moved.shift = .{ 0, -0.10, 0 };
    p0.opts.truth = moved;
    const ho = try marl.probesOf(gpa, moved, 31337, 4096);
    defer {
        gpa.free(ho.p);
        gpa.free(ho.y);
    }

    var ring = try Replay.init(gpa, BIG);
    defer ring.deinit(gpa);
    var ws = rng.Stream.region(99, 0x5741_4b45, 0);

    std.debug.print("\n  G62 (b) [{s}] one wake, a fork consolidated at each checkpoint\n", .{@tagName(builtin.mode)});
    std.debug.print("  {s:>7} {s:>7} {s:>6} {s:>6} {s:>6} {s:>6} {s:>9} {s:>9} {s:>8}\n", .{ "wake", "kernels", "R16", "R64", "R256", "cv", "before", "after", "gain" });

    const marks = [_]u64{ 2_000, 5_000, 10_000, 20_000, 40_000, 80_000 };
    var gains: [marks.len]f64 = undefined;
    var reads: [marks.len]f64 = undefined;
    var seen: u64 = 0;
    for (marks, 0..) |mark, mi| {
        try wake(&p0, mark - seen, &ring, &ws);
        seen = mark;

        // The measures, named and checked before anything is optimised.
        try (Measures{ .fit = ring.x[0..RING], .sleep = ring.x[0..RING], .eval = ho.p }).check();

        reads[mi] = readiness(&p0, 64);
        const before = try p0.rms(ho.p, ho.y, null);
        var fork = try sleepOn(gpa, &p0, ring.x[0..RING], ring.y[0..RING], p0.kernels.items.len / 2, .{});
        defer fork.deinit();
        fork.opts.truth = moved;
        const after = try fork.rms(ho.p, ho.y, null);
        gains[mi] = 1 - @as(f64, after) / @as(f64, before);
        std.debug.print("  {d:>7} {d:>7} {d:>6.3} {d:>6.3} {d:>6.3} {d:>6.2} {d:>9.5} {d:>9.5} {d:>8.4}\n", .{
            mark,              p0.kernels.items.len, readiness(&p0, 16), reads[mi], readiness(&p0, 256),
            updateSpread(&p0), before,               after,              gains[mi],
        });
    }

    // Does readiness order the gain? Spearman would need a rank routine;
    // the plain correlation over six points is enough to say whether the
    // two move together, and the table is printed so it can be read.
    var mr: f64 = 0;
    var mg: f64 = 0;
    for (reads, gains) |r, g| {
        mr += r / marks.len;
        mg += g / marks.len;
    }
    var num: f64 = 0;
    var dr: f64 = 0;
    var dg: f64 = 0;
    for (reads, gains) |r, g| {
        num += (r - mr) * (g - mg);
        dr += (r - mr) * (r - mr);
        dg += (g - mg) * (g - mg);
    }
    const corr = if (dr > 0 and dg > 0) num / @sqrt(dr * dg) else 0;
    const crossed = gains[0] < 0 and gains[marks.len - 1] > 0;
    std.debug.print("  readiness against gain: correlation {d:.4}; the sweep {s}\n", .{
        corr, if (crossed) "CROSSES ZERO — there is a consolidation window" else "does not cross zero",
    });

    // **REFUTED, and the `after` column says why.** The post-sleep RMS is
    // roughly FLAT at 0.067–0.101 however good the model was going in,
    // while `before` runs 0.106 down to 0.048. So the gain is positive only
    // where the model was worse than a ceiling the sleep itself imposes —
    // and readiness, saturated at 0.98–0.999 across the whole sweep, was
    // never the discriminating variable.
    //
    // The ceiling is the REPLAY RING. Half of 781 kernels is 390, at ten
    // parameters each: 3 900 free parameters fitted against 2 048 points.
    // The consolidation is massively overparameterised and generalises to
    // wherever that lands it. OBS-11 flagged the same limit as honest and
    // did not chase it; here it dominates.
    //
    // Which is Christian's conditioning question, deferred twice and now
    // arriving on its own: is the win limited by VARIANCE? More points.
    std.debug.print("  the ring, at the last checkpoint ({d} kernels, {d} after sleep):\n", .{ p0.kernels.items.len, p0.kernels.items.len / 2 });
    std.debug.print("  {s:>8} {s:>9} {s:>9} {s:>8} {s:>10}\n", .{ "ring", "params", "after", "gain", "pts/param" });
    const before_last = try p0.rms(ho.p, ho.y, null);
    const keep = p0.kernels.items.len / 2;
    var lifted = false;
    for ([_]usize{ 2048, 8192, 32768 }) |n| {
        try (Measures{ .fit = ring.x[0..n], .sleep = ring.x[0..n], .eval = ho.p }).check();
        var fork = try sleepOn(gpa, &p0, ring.x[0..n], ring.y[0..n], keep, .{});
        defer fork.deinit();
        fork.opts.truth = moved;
        const after = try fork.rms(ho.p, ho.y, null);
        const g = 1 - @as(f64, after) / @as(f64, before_last);
        if (n == 32768 and g > gains[marks.len - 1]) lifted = true;
        std.debug.print("  {d:>8} {d:>9} {d:>9.5} {d:>8.4} {d:>10.2}\n", .{
            n,                                                                        keep * marl.PARAMS, after, g,
            @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(keep * marl.PARAMS)),
        });
    }

    // The registered numbers are REFUTED and left standing, marked. What is
    // asserted is the diagnosis: more replay lifts the ceiling.
    try testing.expect(lifted);
}

/// The largest consolidation budget the evidence permits — Christian's
/// rule, as code:
///
///     k_keep ≤ N_replay / (ρ_min · p)
///
/// **The spectrum proposes the budget; the evidence permits it.** OBS-10's
/// `r_eff` says how many dimensions deserve to survive; this says how many
/// can be fitted reliably, and the consolidation takes the smaller. If the
/// spectral budget asks for 390 kernels and replay can only support 150,
/// sleep either waits for more evidence or consolidates less aggressively.
///
/// The general form of what OBS-15 found, and G56 (a) found one level down:
/// *representational questions are only meaningful relative to the rank and
/// density of the evidence supporting them.*
pub fn evidenceBudget(n_replay: usize, rho_min: f64, p: usize) usize {
    const cap = @as(f64, @floatFromInt(n_replay)) / (rho_min * @as(f64, @floatFromInt(p)));
    return @max(1, @as(usize, @intFromFloat(@floor(cap))));
}

/// The share of a model's CONTRIBUTION resting on kernels born after a
/// given point — the maturity measure OBS-15's readiness could not be,
/// because update counts saturate almost at once.
pub fn freshShare(m: *const marl.Model, since: u64) f64 {
    var tot: f64 = 0;
    var new: f64 = 0;
    for (m.kernels.items) |*k| {
        const w = @abs(@as(f64, k.weightsConst()[0]));
        tot += w;
        if (k.born_at >= since) new += w;
    }
    return if (tot > 0) new / tot else 0;
}

test "G63 does maturity matter once the evidence is adequate?" {
    // OBS-15 refuted maturity, but only under an evidence-starved fit: the
    // rho effect was so dominant that any maturity effect was buried, and
    // readiness itself never varied. Christian's correction is a grid
    // rather than another sweep.
    //
    // **k_keep is FIXED at 200 in every cell**, so the ring is sized by his
    // own rule — N = rho·p·k — and rho is the only thing moving along that
    // axis. Letting the budget follow the population would change the
    // conditioning and the compression ratio together, which is the
    // confound OBS-15 fell into from the other side.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const KEEP: usize = 200;
    const BIG: usize = 16384;

    var st = rng.Stream.region(1234, 0x4f31_3657, 0); // "O16W"
    var warm = try Replay.init(gpa, 1024);
    defer warm.deinit(gpa);
    var base = try marl.Model.init(gpa, o);
    defer base.deinit();
    try wake(&base, 20_000, &warm, &st);

    var moved = marl.TruthParams{};
    moved.shift = .{ 0, -0.10, 0 };
    base.opts.truth = moved;
    const since = base.stats.exemplars;
    const ho = try marl.probesOf(gpa, moved, 31337, 4096);
    defer {
        gpa.free(ho.p);
        gpa.free(ho.y);
    }

    var ring = try Replay.init(gpa, BIG);
    defer ring.deinit(gpa);
    var ws = rng.Stream.region(99, 0x5741_4b45, 0);

    std.debug.print("\n  G63 [{s}] budget fixed at {d} kernels ({d} free parameters); the ring is sized by rho·p·k\n", .{
        @tagName(builtin.mode), KEEP, KEEP * marl.PARAMS,
    });
    std.debug.print("  {s:<9} {s:>7} {s:>7} {s:>7} {s:>9}   {s:>9} {s:>9} {s:>9}\n", .{ "maturity", "kernels", "R1024", "fresh", "before", "rho 0.5", "rho 2.0", "rho 8.0" });

    const marks = [_]u64{ 2_000, 20_000, 80_000 };
    const labels = [_][]const u8{ "young", "mid", "settled" };
    const rhos = [_]f64{ 0.5, 2.0, 8.0 };
    var grid: [3][3]f64 = undefined;
    var seen: u64 = 0;
    for (marks, labels, 0..) |mark, label, mi| {
        try wake(&base, mark - seen, &ring, &ws);
        seen = mark;
        const before = try base.rms(ho.p, ho.y, null);
        std.debug.print("  {s:<9} {d:>7} {d:>7.3} {d:>7.3} {d:>9.5}", .{
            label, base.kernels.items.len, readiness(&base, 1024), freshShare(&base, since), before,
        });
        for (rhos, 0..) |rho, ri| {
            const n = @as(usize, @intFromFloat(rho * @as(f64, @floatFromInt(KEEP * marl.PARAMS))));
            std.debug.assert(n <= BIG);
            // The guardrail, every cell.
            try (Measures{ .fit = ring.x[0..n], .sleep = ring.x[0..n], .eval = ho.p }).check();
            var fork = try sleepOn(gpa, &base, ring.x[0..n], ring.y[0..n], KEEP, .{});
            defer fork.deinit();
            fork.opts.truth = moved;
            const after = try fork.rms(ho.p, ho.y, null);
            grid[mi][ri] = 1 - @as(f64, after) / @as(f64, before);
            std.debug.print(" {d:>9.4}", .{grid[mi][ri]});
        }
        std.debug.print("\n", .{});
    }

    // Does rho dominate within every row?
    var rho_monotone = true;
    for (0..3) |mi| {
        if (!(grid[mi][0] < grid[mi][1] and grid[mi][1] < grid[mi][2])) rho_monotone = false;
    }
    // Does the maturity spread SHRINK as rho rises? The agent's prediction.
    var spread: [3]f64 = undefined;
    for (0..3) |ri| {
        var lo = grid[0][ri];
        var hi = grid[0][ri];
        for (0..3) |mi| {
            lo = @min(lo, grid[mi][ri]);
            hi = @max(hi, grid[mi][ri]);
        }
        spread[ri] = hi - lo;
    }
    std.debug.print("  maturity spread of the gain, by rho: {d:.4} {d:.4} {d:.4} — {s}\n", .{
        spread[0],                                                                                                               spread[1], spread[2],
        if (spread[2] < spread[0]) "the AGENT: evidence absorbs maturity" else "CHRISTIAN: maturity survives adequate evidence",
    });
    std.debug.print("  the rule: at rho_min = 2, {d} points permit {d} kernels; this grid kept {d}\n", .{
        BIG, evidenceBudget(BIG, 2.0, marl.PARAMS), KEEP,
    });

    try testing.expect(rho_monotone);
    // rho = 0.5 must be destructive somewhere, or the starved regime is not
    // being reached and the grid measures nothing.
    try testing.expect(grid[2][0] < 0);
}

test "G64 is rho a control law, or a description of one axis?" {
    // OBS-16 moved rho by RING SIZE at fixed budget and showed it predicts
    // each cell's sign. That establishes rho as the regime variable; it
    // does NOT establish that choosing k from N is safe, because k never
    // moved. `evidenceBudget` returns a budget and nothing has yet used it
    // to pick one.
    //
    // Christian: "hold replay ring fixed and sweep consolidation budget, so
    // rho changes entirely through free-parameter count. If the sign
    // transition appears at the same approximate rho, then evidenceBudget()
    // graduates from a descriptive fit to a real control law."
    //
    // The two families reach the same rho from opposite directions: at rho
    // 4 the small ring means k = 51 and the large one k = 205 — four times
    // the model complexity at the same evidence ratio.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const BIG: usize = 8192;

    var st = rng.Stream.region(1234, 0x4f31_3757, 0); // "O17W"
    var warm = try Replay.init(gpa, 1024);
    defer warm.deinit(gpa);
    var m = try marl.Model.init(gpa, o);
    defer m.deinit();
    try wake(&m, 20_000, &warm, &st);

    var moved = marl.TruthParams{};
    moved.shift = .{ 0, -0.10, 0 };
    m.opts.truth = moved;
    const ho = try marl.probesOf(gpa, moved, 31337, 4096);
    defer {
        gpa.free(ho.p);
        gpa.free(ho.y);
    }
    var ring = try Replay.init(gpa, BIG);
    defer ring.deinit(gpa);
    var ws = rng.Stream.region(99, 0x5741_4b45, 0);
    try wake(&m, 20_000, &ring, &ws); // the "mid" maturity of OBS-16

    const before = try m.rms(ho.p, ho.y, null);
    std.debug.print("\n  G64 [{s}] {d} kernels, before {d:.5}; rho moved by BUDGET at fixed ring\n", .{
        @tagName(builtin.mode), m.kernels.items.len, before,
    });
    std.debug.print("  {s:>6} {s:>7} {s:>7} {s:>9} {s:>9}   {s}\n", .{ "ring", "k", "rho", "after", "gain", "" });

    const rings = [_]usize{ 2048, 8192 };
    const ks = [_]usize{ 410, 205, 102, 51, 26 };
    var gain: [2][ks.len]f64 = .{.{ 0, 0, 0, 0, 0 }} ** 2;
    var have: [2][ks.len]bool = .{.{false} ** ks.len} ** 2;

    for (rings, 0..) |n, ni| {
        for (ks, 0..) |k, ki| {
            if (k > m.kernels.items.len) continue;
            const rho = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(k * marl.PARAMS));
            try (Measures{ .fit = ring.x[0..n], .sleep = ring.x[0..n], .eval = ho.p }).check();
            var fork = try sleepOn(gpa, &m, ring.x[0..n], ring.y[0..n], k, .{});
            defer fork.deinit();
            fork.opts.truth = moved;
            const after = try fork.rms(ho.p, ho.y, null);
            gain[ni][ki] = 1 - @as(f64, after) / @as(f64, before);
            have[ni][ki] = true;
            std.debug.print("  {d:>6} {d:>7} {d:>7.2} {d:>9.5} {d:>9.4}\n", .{ n, k, rho, after, gain[ni][ki] });
        }
    }

    // **THE COLLAPSE FAILS.** Matched by rho rather than by index, so the
    // pairing cannot be an off-by-one: for every cell in the small ring,
    // find the large-ring cell at the same rho and compare.
    std.debug.print("  the collapse — same rho, four times the complexity:\n", .{});
    std.debug.print("  {s:>7}   {s:>8} {s:>9}   {s:>8} {s:>9}   {s}\n", .{ "rho", "small k", "gain", "large k", "gain", "agree?" });
    var agree = true;
    var pairs: usize = 0;
    for (ks, 0..) |ka, ia| {
        if (!have[0][ia]) continue;
        const ra = @as(f64, 2048) / @as(f64, @floatFromInt(ka * marl.PARAMS));
        for (ks, 0..) |kb, ib| {
            if (!have[1][ib]) continue;
            const rb = @as(f64, 8192) / @as(f64, @floatFromInt(kb * marl.PARAMS));
            if (@abs(ra - rb) / ra > 0.05) continue;
            const ok = (gain[0][ia] > 0) == (gain[1][ib] > 0);
            if (!ok) agree = false;
            pairs += 1;
            std.debug.print("  {d:>7.2}   {d:>8} {d:>9.4}   {d:>8} {d:>9.4}   {s}\n", .{ ra, ka, gain[0][ia], kb, gain[1][ib], if (ok) "yes" else "NO" });
        }
    }

    // What IS monotone: within a ring, gain rises with k (less compression
    // is better); across rings at matched k, gain rises with N (more
    // evidence is better). Both directions raise or lower rho
    // inconsistently, which is why the ratio cannot be the law.
    var k_monotone = true;
    var n_monotone = true;
    for (0..ks.len - 1) |step| {
        for (0..2) |ni| {
            if (have[ni][step] and have[ni][step + 1] and !(gain[ni][step] > gain[ni][step + 1])) k_monotone = false;
        }
        if (have[0][step] and have[1][step] and !(gain[1][step] > gain[0][step])) n_monotone = false;
    }
    std.debug.print("  within a ring, gain rises with k: {}; at matched k, gain rises with N: {}\n", .{ k_monotone, n_monotone });
    std.debug.print("  so evidence and compression are SEPARABLE, and rho — their ratio — is not the law\n", .{});

    try testing.expect(pairs >= 2);
    // The registered collapse is REFUTED: at matched rho the two families
    // disagree in SIGN. Asserted as the refutation, because that is the
    // finding and a gate that asserted the collapse would now be a gate
    // that fails for the right reason and says the wrong thing.
    try testing.expect(!agree);
    try testing.expect(k_monotone);
    try testing.expect(n_monotone);
}

/// What a replay buffer is MADE OF, in the only terms in which the question
/// is observable.
///
/// A move shifts the shell and nothing else — `swell` never reads the shift
/// — so outside the band union the two worlds are IDENTICAL and a stored
/// sample is equally valid under both. Measured over 200 000 uniform
/// points, 0.0950 of the cube is CONTESTED. Every claim anyone makes about
/// stale replay is a claim about that tenth, and a "share of old samples"
/// taken over the whole buffer would mostly be counting samples that cannot
/// be old.
pub const Composition = struct {
    /// Share of the buffer where the two worlds disagree at all.
    contested: f64,
    /// Share of THOSE recorded under the old world.
    stale: f64,
    /// Share of the buffer past the window, where the target is exactly
    /// zero in every world and nothing is ever born.
    dead: f64,
    /// Share of the buffer some kernel's support contains. The rest are
    /// all-zero design rows: they cannot constrain the fit, and out past
    /// the window the target is zero too, so the row is ZERO = ZERO —
    /// not merely uninformative but empty on both sides.
    reached: f64,
};

pub fn compositionOf(
    b: Replay,
    old: marl.TruthParams,
    new: marl.TruthParams,
    ks: []const marl.Kernel,
) Composition {
    const n = b.filled();
    var contested: usize = 0;
    var stale: usize = 0;
    var dead: usize = 0;
    var reached: usize = 0;
    for (b.x[0..n], b.y[0..n]) |q, v| {
        const ya: f64 = marl.truthOf(old, q);
        const yb: f64 = marl.truthOf(new, q);
        if (@abs(ya - yb) > 1e-3) {
            contested += 1;
            if (@abs(v - ya) < @abs(v - yb)) stale += 1;
        }
        if (q[0] > marl.Truth.WINDOW_HI) dead += 1;
        for (ks) |*k| {
            if (marl.gaussian(k.shape(), q) > 0) {
                reached += 1;
                break;
            }
        }
    }
    const fn_ = @as(f64, @floatFromInt(@max(1, n)));
    return .{
        .contested = @as(f64, @floatFromInt(contested)) / fn_,
        .stale = if (contested == 0) 0 else @as(f64, @floatFromInt(stale)) / @as(f64, @floatFromInt(contested)),
        .dead = @as(f64, @floatFromInt(dead)) / fn_,
        .reached = @as(f64, @floatFromInt(reached)) / fn_,
    };
}

/// Put a basis into a fresh model, point it at a world, and let it learn.
///
/// Returns what it reached AND what it paid. Births are MARL-9's currency:
/// capacity is bought per THING LEARNED rather than per change, so a world
/// the basis still holds is nearly free to revisit and one it has dropped
/// costs full price. That is what makes this a retention measure rather
/// than a scoring of a model on a world it is no longer fitting.
fn adaptTo(
    gpa: std.mem.Allocator,
    o: marl.Options,
    ks: []const marl.Kernel,
    tp: marl.TruthParams,
    n: u64,
    pr: marl.Probes,
) !struct { rms: f64, births: u64, kernels: usize } {
    var m = try adopt(gpa, o, ks);
    defer m.deinit();
    m.opts.truth = tp;
    const b0 = m.stats.births;
    try m.stream_n(n);
    return .{
        .rms = try m.rms(pr.p, pr.y, null),
        .births = m.stats.births - b0,
        .kernels = m.kernels.items.len,
    };
}
test "G65 replay composition: what does a replay policy actually choose?" {
    // OBS-17 separated the two knobs a sleep has — f(N) estimation quality
    // and g(k) information destruction — and left the obvious question
    // open: nothing says what should be IN the N.
    //
    // Christian: "equal-sized rings, same N, same k, same optimiser,
    // differing only in the measure. Nothing can then hide behind sample
    // count or compression severity."
    //
    // The gate runs TWO experiments, and Astra's correction is that they
    // are complementary rather than one superseding the other:
    //
    //   THE POLICY QUESTION   four admission rules as they would actually
    //                         run. A rule over a non-stationary stream
    //                         chooses WHEN to observe as well as WHERE, so
    //                         it chooses which world its labels describe.
    //                         That is part of the policy, not a confound
    //                         in it.
    //   THE LOCATION QUESTION the same points with every label re-read from
    //                         the current world. Given these locations, and
    //                         labels that all describe B, which
    //                         distribution fits best? Needs an oracle, so
    //                         it is a probe and not a deployable policy.
    //
    // `tools/obs18_predict.py` is where the REGISTERED numbers were frozen.
    // Everything marked POST-HOC was measured because a run demanded it,
    // and is labelled so a reader can tell a prediction from a repair.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const N: usize = 8192;
    const WAKE: u64 = 20_000;
    const ADAPT: u64 = 20_000;

    const world_a = marl.TruthParams{};
    var world_b = marl.TruthParams{};
    world_b.shift = .{ 0, -0.10, 0 };
    var world_c = marl.TruthParams{};
    world_c.shift = .{ 0.12, 0, 0.22 };

    const Arm = struct { name: []const u8, kind: Compose, seed: u64 };
    const arms = [_]Arm{
        .{ .name = "recent", .kind = .recent, .seed = 0 },
        .{ .name = "uniform", .kind = .uniform, .seed = 0xA1 },
        .{ .name = "error", .kind = .err, .seed = 0xB2 },
        .{ .name = "uncovered", .kind = .uncovered, .seed = 0xC3 },
        // THE REPLICATES: same rule, different reservoir stream, nothing
        // else. Two arms give ONE observed gap, which is a sample of size
        // one; three uniform arms give three. And `error` gets its own,
        // because a spread measured on the uniform rule and then applied to
        // a comparison involving the error rule assumes the two rules vary
        // alike — an assumption that was being made silently.
        //
        // Even so this is a DESCRIPTIVE spread over a handful of draws, not
        // a confidence bound, and the gate says so wherever it prints one.
        .{ .name = "uniform'", .kind = .uniform, .seed = 0xD4 },
        .{ .name = "uniform''", .kind = .uniform, .seed = 0xE5 },
        .{ .name = "error'", .kind = .err, .seed = 0xF6 },
    };
    const REC = 0;
    const UNI = 1;
    const ERR = 2;
    const UNC = 3;
    const rules = [_]usize{ REC, UNI, ERR, UNC };
    const uni_reps = [_]usize{ UNI, 4, 5 };
    const err_reps = [_]usize{ ERR, 6 };

    var bufs: [arms.len]Replay = undefined;
    for (arms, 0..) |a, i| bufs[i] = try Replay.initWith(gpa, N, a.kind, a.seed);
    defer for (&bufs) |*b| b.deinit(gpa);
    var ptrs: [arms.len]*Replay = undefined;
    for (&bufs, 0..) |*b, i| ptrs[i] = b;

    var m = try marl.Model.init(gpa, o);
    defer m.deinit();
    var st = rng.Stream.region(1234, 0x4f31_3857, 0); // "O18W"
    try wakeAll(&m, WAKE, &ptrs, &st);
    m.opts.truth = world_b;
    try wakeAll(&m, WAKE, &ptrs, &st);

    // One probe SET across the three worlds — same points, three sets of
    // values — so an arm is never compared on a different query set.
    const ha = try marl.probesOf(gpa, world_a, 31337, 4096);
    const hb = try marl.probesOf(gpa, world_b, 31337, 4096);
    const hc = try marl.probesOf(gpa, world_c, 31337, 4096);
    defer {
        gpa.free(ha.p);
        gpa.free(ha.y);
        gpa.free(hb.p);
        gpa.free(hb.y);
        gpa.free(hc.p);
        gpa.free(hc.y);
    }

    const keep = m.kernels.items.len / 2;
    const before = try m.rms(hb.p, hb.y, null);
    std.debug.print("\n  G65 [{s}] {d} kernels after two worlds, before {d:.5}; N = {d} and k = {d} in EVERY arm\n", .{
        @tagName(builtin.mode), m.kernels.items.len, before, N, keep,
    });

    const ctl_a = try adaptTo(gpa, o, m.kernels.items, world_a, ADAPT, ha);
    const ctl_c = try adaptTo(gpa, o, m.kernels.items, world_c, ADAPT, hc);
    const ctl_held = try m.rms(ha.p, ha.y, null);
    std.debug.print("  control, no sleep: {d} kernels, B {d:.5} | A held {d:.5}, re-fits to {d:.5} on +{d} births | C {d:.5} +{d} births\n", .{
        m.kernels.items.len, before, ctl_held, ctl_a.rms, ctl_a.births, ctl_c.rms, ctl_c.births,
    });

    const Row = struct {
        comp: Composition,
        k: usize,
        after: f64,
        gain: f64,
        /// What the sleep PRESERVED of the old world, scored before any
        /// further learning. Astra's correction, and it carries a finding
        /// the re-fit column cannot: relearning washes out what was kept.
        held: f64,
        ret: f64,
        ret_births: u64,
        plast: f64,
        plast_births: u64,
    };
    // Four axes now, because "A held" and "A re-fit" are different
    // questions and reporting only the second lost a result.
    const AXES = 4;
    const axes = [_][]const u8{ "immediate (B)", "A held", "A re-fit", "arriving at C" };
    const pick = struct {
        fn v(r: anytype, ax: usize) f64 {
            return switch (ax) {
                0 => -r.gain, // negated so every axis is lower-is-better
                1 => r.held,
                2 => r.ret,
                else => r.plast,
            };
        }
    }.v;

    std.debug.print("  {s:<10} {s:>9} {s:>6} {s:>6} {s:>7} | {s:>4} {s:>8} {s:>8} | {s:>8} {s:>8} {s:>7} | {s:>8} {s:>7}\n", .{
        "arm", "contested", "stale", "dead", "reached", "k", "after", "gain", "A held", "A re-fit", "births", "C RMS", "births",
    });
    var row: [arms.len]Row = undefined;
    for (arms, 0..) |arm, ai| {
        const comp = compositionOf(bufs[ai], world_a, world_b, m.kernels.items);
        try (Measures{ .fit = bufs[ai].x[0..N], .sleep = bufs[ai].x[0..N], .eval = hb.p }).check();
        var child = try sleepOn(gpa, &m, bufs[ai].x[0..N], bufs[ai].y[0..N], keep, .{ .exact = true });
        defer child.deinit();
        child.opts.truth = world_b;
        const after = try child.rms(hb.p, hb.y, null);
        const held = try child.rms(ha.p, ha.y, null);
        const ret = try adaptTo(gpa, o, child.kernels.items, world_a, ADAPT, ha);
        const plast = try adaptTo(gpa, o, child.kernels.items, world_c, ADAPT, hc);
        row[ai] = .{
            .comp = comp,
            .k = child.kernels.items.len,
            .after = after,
            .gain = 1 - @as(f64, after) / @as(f64, before),
            .held = held,
            .ret = ret.rms,
            .ret_births = ret.births,
            .plast = plast.rms,
            .plast_births = plast.births,
        };
        std.debug.print("  {s:<10} {d:>9.4} {d:>6.3} {d:>6.3} {d:>7.3} | {d:>4} {d:>8.5} {d:>8.4} | {d:>8.5} {d:>8.5} {d:>7} | {d:>8.5} {d:>7}\n", .{
            arm.name,           comp.contested, comp.stale,           comp.dead,    comp.reached,
            row[ai].k,          row[ai].after,  row[ai].gain,         row[ai].held, row[ai].ret,
            row[ai].ret_births, row[ai].plast,  row[ai].plast_births,
        });
    }

    // (0) EQUAL k, asserted rather than announced. The incumbent allocator
    // rounded each region independently and delivered 345 to 347 against a
    // budget of 346 while the header printed 346 — a premise of the design
    // reported as true when it was not. Astra found it in review.
    for (row) |r| try testing.expectEqual(keep, r.k);

    // The observed same-rule spread, per axis: every pair within a rule,
    // worst taken. Reported per rule as well as pooled, because pooling
    // them assumes the rules vary alike and that is exactly the assumption
    // being leant on when an error-vs-uniform gap is read against it.
    const spreadOfReps = struct {
        fn go(r: []const Row, reps: []const usize, ax: usize) f64 {
            var worst: f64 = 0;
            for (reps, 0..) |a, i| {
                for (reps[i + 1 ..]) |b| worst = @max(worst, @abs(pick(r[a], ax) - pick(r[b], ax)));
            }
            return worst;
        }
    }.go;
    var noise: [AXES]f64 = undefined;
    for (0..AXES) |ax| {
        const u = spreadOfReps(&row, &uni_reps, ax);
        const e = spreadOfReps(&row, &err_reps, ax);
        noise[ax] = @max(u, e);
    }
    std.debug.print("  same-rule spread (DESCRIPTIVE, a handful of draws — not a confidence bound):\n", .{});
    for (axes, 0..) |axis, ax| {
        std.debug.print("    {s: <15} uniform x3 {d:.5}   error x2 {d:.5}   taken as {d:.5}\n", .{
            axis, spreadOfReps(&row, &uni_reps, ax), spreadOfReps(&row, &err_reps, ax), noise[ax],
        });
    }

    // **THE REGISTERED MECHANISM IS REFUTED AND `reached` IS HOW.**
    //
    // The prediction was that composition acts through EFFECTIVE evidence:
    // a point no kernel reaches has an all-zero design row, and past the
    // window the target is zero too, so the row is ZERO = ZERO. Every arm
    // reads 1.000. There is no unreached ground, because a Gaussian basis
    // must actively HOLD DOWN ITS OWN LEAKAGE. `mu0` is a kernel's BIRTH
    // centre, so the two counts separate "born there" from "drifted there"
    // instead of assuming it.
    //
    // This refutes the ROW-COUNT form of effective evidence and nothing
    // wider: conditioning, redundant constraints and information spread
    // unevenly across parameters are untouched by `reached`.
    var centred: usize = 0;
    var born: usize = 0;
    for (m.kernels.items) |*k| {
        if (k.p[0] > marl.Truth.WINDOW_HI) centred += 1;
        if (k.mu0[0] > marl.Truth.WINDOW_HI) born += 1;
    }
    std.debug.print("  N_eff REFUTED: reached ~1.000 in every arm — of {d} kernels, {d} are centred past the window and {d} were BORN there\n", .{
        m.kernels.items.len, centred, born,
    });

    // ── THE LOCATION QUESTION. Same points, every label re-read from the
    // world the model is in. An oracle call per point, so a probe and not a
    // policy — and a DIFFERENT question from the one above, not a repair of
    // it. Astra's point 2, and it is right: which observation times a rule
    // selects is part of what a replay policy IS.
    //
    // The ring needs no refresh, and that is the whole of what makes it
    // self-consistent here: every point it holds was observed under the
    // world it is being consolidated for. Checked, not assumed. Note the
    // condition is the FIXTURE'S — 20 000 observations in world B flushed
    // all 8 192 slots — and a ring whose window straddled the move would
    // not be self-consistent at all.
    var ring_current = true;
    for (bufs[REC].x[0..N], bufs[REC].y[0..N]) |q, v| {
        if (v != @as(f64, marl.truthOf(world_b, q))) ring_current = false;
    }

    const fresh = try gpa.alloc(f64, N);
    defer gpa.free(fresh);
    var fr: [arms.len]Row = undefined;
    fr[REC] = row[REC];
    std.debug.print("  THE LOCATION QUESTION: same points, labels re-read from the current world\n", .{});
    std.debug.print("  (the ring is unchanged by a refresh — {s} of its {d} labels move — so it stands as its own arm)\n", .{
        if (ring_current) "NONE" else "some", N,
    });
    std.debug.print("  {s:<10} {s:>10} {s:>9} {s:>9} | {s:>8} {s:>8} {s:>7} | {s:>8} {s:>7}\n", .{
        "arm", "stale gain", "gain", "delta", "A held", "A re-fit", "births", "C RMS", "births",
    });
    for ([_]usize{ UNI, ERR, UNC, 4, 5, 6 }) |ai| {
        for (bufs[ai].x[0..N], 0..) |q, i| fresh[i] = marl.truthOf(world_b, q);
        var fc = try sleepOn(gpa, &m, bufs[ai].x[0..N], fresh, keep, .{ .exact = true });
        defer fc.deinit();
        fc.opts.truth = world_b;
        const fa = try fc.rms(hb.p, hb.y, null);
        const fheld = try fc.rms(ha.p, ha.y, null);
        const fret = try adaptTo(gpa, o, fc.kernels.items, world_a, ADAPT, ha);
        const fpla = try adaptTo(gpa, o, fc.kernels.items, world_c, ADAPT, hc);
        fr[ai] = .{
            .comp = row[ai].comp,
            .k = fc.kernels.items.len,
            .after = fa,
            .gain = 1 - @as(f64, fa) / @as(f64, before),
            .held = fheld,
            .ret = fret.rms,
            .ret_births = fret.births,
            .plast = fpla.rms,
            .plast_births = fpla.births,
        };
        std.debug.print("  {s:<10} {d:>10.4} {d:>9.4} {d:>9.4} | {d:>8.5} {d:>8.5} {d:>7} | {d:>8.5} {d:>7}\n", .{
            arms[ai].name,       row[ai].gain, fr[ai].gain,       fr[ai].gain - row[ai].gain,
            fr[ai].held,         fr[ai].ret,   fr[ai].ret_births, fr[ai].plast,
            fr[ai].plast_births,
        });
        try testing.expectEqual(keep, fr[ai].k);
    }
    var fnoise: [AXES]f64 = undefined;
    for (0..AXES) |ax| {
        fnoise[ax] = @max(spreadOfReps(&fr, &uni_reps, ax), spreadOfReps(&fr, &err_reps, ax));
    }
    std.debug.print("  its own same-rule spread: {d:.4} on gain, {d:.5} A held, {d:.5} A re-fit, {d:.5} C\n", .{
        fnoise[0], fnoise[1], fnoise[2], fnoise[3],
    });

    // ── THE PARETO QUESTION, asked of both tables and in units of the
    // observed spread, because a lead smaller than the same-rule spread is
    // not a lead. Astra's point 3: this ratio SIZES a difference, it does
    // not certify one.
    const Verdict = struct { winner: usize, margin: f64, clears: bool };
    const judge = struct {
        fn go(r: []const Row, rs: []const usize, nz: []const f64, ax: usize) Verdict {
            var w = rs[0];
            for (rs) |ai| {
                if (pick(r[ai], ax) < pick(r[w], ax)) w = ai;
            }
            var best: f64 = 0;
            var first = true;
            for (rs) |ai| {
                if (ai == w) continue;
                const d = pick(r[ai], ax) - pick(r[w], ax);
                if (first or d < best) best = d;
                first = false;
            }
            return .{ .winner = w, .margin = best, .clears = best > nz[ax] };
        }
    }.go;

    // `judge` compares the leader to its NEAREST rival, so "the leader is
    // not uniquely separated" says nothing whatever about the rest of the
    // field: two nearly tied leaders hide every difference behind them.
    // An earlier draft of this gate printed "NOTHING else separates" off
    // exactly that test — and on the relabelled A-held axis four of six
    // pairs separate. Astra caught it. The two questions are reported apart
    // from here on, because they are different questions.
    const Pairs = struct { n: usize, widest: f64, lo: usize, hi: usize };
    const pairsOf = struct {
        fn go(r: []const Row, rs: []const usize, sp: f64, ax: usize) Pairs {
            var out = Pairs{ .n = 0, .widest = 0, .lo = rs[0], .hi = rs[0] };
            for (rs, 0..) |a, i| {
                for (rs[i + 1 ..]) |b| {
                    const d = @abs(pick(r[a], ax) - pick(r[b], ax));
                    if (d <= sp) continue;
                    out.n += 1;
                    if (d > out.widest) {
                        out.widest = d;
                        out.lo = a;
                        out.hi = b;
                    }
                }
            }
            return out;
        }
    }.go;

    var pol: [AXES]Verdict = undefined;
    var loc: [AXES]Verdict = undefined;
    std.debug.print("  {s:<16} {s:>26}   {s:>26}\n", .{ "axis", "AS A POLICY (own labels)", "AS A LOCATION (relabelled)" });
    for (axes, 0..) |axis, ax| {
        pol[ax] = judge(&row, &rules, &noise, ax);
        loc[ax] = judge(&fr, &rules, &fnoise, ax);
        std.debug.print("  {s:<16} {s:>10} by {d:>5.2}x {s:>7}   {s:>10} by {d:>5.2}x {s:>7}\n", .{
            axis,
            arms[pol[ax].winner].name,
            pol[ax].margin / @max(1e-9, noise[ax]),
            if (pol[ax].clears) "clears" else "(inside)",
            arms[loc[ax].winner].name,
            loc[ax].margin / @max(1e-9, fnoise[ax]),
            if (loc[ax].clears) "clears" else "(inside)",
        });
    }

    // ── THE FINDING, and Astra's point 1 is half of it.
    //
    // **The policy table already trades.** The ring wins the current world
    // and is LAST at preserving the old one; the error-weighted buffer is
    // the reverse. Historical observations really do preserve more of A —
    // which the re-fit column cannot show, because 20 000 further
    // observations wash out what was kept. Reporting only the re-fit column
    // lost a result that was sitting in the same run.
    var pol_trade = false;
    if (pol[0].winner == REC and pol[1].winner != REC) pol_trade = true;
    std.debug.print("  separated PAIRS, of six, at each table's own spread — a leader tied with its nearest rival hides none of these:\n", .{});
    for (axes, 0..) |axis, ax| {
        const pp = pairsOf(&row, &rules, noise[ax], ax);
        const lp = pairsOf(&fr, &rules, fnoise[ax], ax);
        std.debug.print("    {s: <15} policy {d}/6 (widest {s}/{s} {d:.5})   location {d}/6 (widest {s}/{s} {d:.5})\n", .{
            axis,
            pp.n,
            arms[pp.lo].name,
            arms[pp.hi].name,
            pp.widest,
            lp.n,
            arms[lp.lo].name,
            arms[lp.hi].name,
            lp.widest,
        });
    }
    std.debug.print("  AS A POLICY: {s} wins the current world, {s} preserves the old one — {s}\n", .{
        arms[pol[0].winner].name,                                                                arms[pol[1].winner].name,
        if (pol_trade) "the policy table trades ON ITS OWN" else "no trade in the policy table",
    });
    std.debug.print("  AS A LOCATION: {s} wins the current world by {d:.2}x — the ONLY axis with a uniquely separated leader (which is not the same as no differences)\n", .{
        arms[loc[0].winner].name, loc[0].margin / @max(1e-9, fnoise[0]),
    });
    // **The error rule's own replicate is why that reads differently from
    // the first attempt.** With a floor measured only on the uniform rule,
    // error looked last on both adaptation axes by 13.5x and 8.4x. Its own
    // two relabelled arms differ on A re-fit by an amount comparable to the
    // largest gap between any two RULES — so those margins were an artefact
    // of applying one rule's variability to another. Astra's point 3,
    // earning its cost on the first run that included it.
    var widest: f64 = 0;
    for (rules, 0..) |a, i| {
        for (rules[i + 1 ..]) |b| widest = @max(widest, @abs(fr[a].ret - fr[b].ret));
    }
    std.debug.print("  and the caution: the ERROR rule's own two relabelled arms differ by {d:.5} on A re-fit, against {d:.5} between the widest-separated RULES\n", .{
        spreadOfReps(&fr, &err_reps, 2), widest,
    });

    // Retention is carried by the LABELS, not by the locations. Every rule's
    // own points retain the old world WORSE once relabelled, because a
    // buffer all of whose labels describe B holds no evidence about A —
    // whatever its distribution.
    std.debug.print("  relabelling and A held: ", .{});
    for ([_]usize{ UNI, ERR, UNC }) |ai| {
        std.debug.print("{s} {d:.5}->{d:.5}  ", .{ arms[ai].name, row[ai].held, fr[ai].held });
    }
    std.debug.print("(spread {d:.5}) — worse for EVERY rule; the relabelled leaders are not separated, but four of their six pairs are\n", .{noise[1]});
    std.debug.print("  CHRISTIAN: a Pareto surface.  THE AGENT: the unbiased arms take everything.  — CHRISTIAN, and it lives in the POLICY table\n", .{});
    std.debug.print("  a buffer's LOCATIONS decide how well it fits the world it is labelled for; its LABELS decide which world that is\n", .{});
    // And the qualification the fixture itself supplies: only 0.0950 of this
    // cube is CONTESTED, so a relabelled buffer has not lost its information
    // about the old world — it has lost the A-SPECIFIC labels on the tenth
    // where the two worlds disagree. Over the other nine tenths a world-B
    // observation is a world-A observation.
    std.debug.print("  and what a relabelled buffer loses is not evidence about the old world but its A-SPECIFIC labels on the {d:.1}% where the worlds disagree\n", .{
        100 * row[UNI].comp.contested,
    });

    // ── REGISTERED: the buffers must actually differ, or the phase measures
    // nothing. Mutation: give every arm `.recent` and all seven rows become
    // one.
    try testing.expectEqual(@as(f64, 0), row[REC].comp.stale);
    try testing.expect(@abs(row[UNI].comp.stale - 0.5) < thresholds.OBS18_STALE_TOL);
    try testing.expect(row[ERR].comp.contested > thresholds.OBS18_ERROR_CONTESTED * row[UNI].comp.contested);

    // ── REGISTERED, and REFUTED. `OBS18_UNCOVERED_DEAD` and
    // `OBS18_UNCOVERED_REACHED` are left standing and marked; what is
    // asserted is the refutation and the mechanism that replaces it.
    for (row) |r| try testing.expect(r.comp.reached > 0.99);
    try testing.expect(centred > 0 and born > 0);
    try testing.expect(row[UNC].comp.dead > row[UNI].comp.dead);

    // ── POST-HOC: THE PARETO SURFACE, and it is in the POLICY table — the
    // one an earlier draft of this gate called confounded. Two rules win
    // two axes and both clear their own rule's observed spread: the ring
    // takes the world being evaluated, the error-weighted buffer preserves
    // the one before it.
    try testing.expect(ring_current);
    try testing.expect(pol[0].clears and pol[0].winner == REC);
    try testing.expect(pol[1].clears and pol[1].winner == ERR);
    try testing.expect(pol[0].winner != pol[1].winner);
    for (rules) |ai| {
        if (ai == REC) continue;
        try testing.expect(row[REC].held > row[ai].held);
    }

    // ── POST-HOC: relabelling lifts the fit to the CURRENT world for every
    // rule — which is not "stale data is corrupt" but "stale data is
    // evidence about a different world, and you are being marked on this
    // one".
    for ([_]usize{ UNI, ERR, UNC }) |ai| {
        try testing.expect(fr[ai].gain > 0);
        try testing.expect(fr[ai].gain - row[ai].gain > noise[0]);
    }

    // ── POST-HOC: in the location table the immediate axis is the only one
    // with a UNIQUELY SEPARATED LEADER. Asserted as a negative on purpose:
    // the first version of this gate read a trade off these columns using a
    // spread borrowed from another rule, and a gate silent about that would
    // let the same mistake back in.
    //
    // But the negative is only about the LEADER, and the pair count above is
    // what stops it being read as "no differences" — which is how it was
    // written up before Astra pointed at the arithmetic. On the relabelled
    // A-held axis the leader is tied with its nearest rival and four of six
    // pairs still separate, so both facts are asserted together.
    try testing.expect(loc[0].clears and loc[0].winner == ERR);
    try testing.expect(fr[ERR].gain > fr[UNI].gain and fr[6].gain > fr[UNI].gain);
    try testing.expect(!loc[1].clears and !loc[2].clears and !loc[3].clears);
    try testing.expect(pairsOf(&fr, &rules, fnoise[1], 1).n > 0);

    // ── POST-HOC: retention comes from the LABELS. Every rule's own points
    // retain the old world worse once every label describes the new one, by
    // more than the observed spread — including the arm that was BEST at it.
    for ([_]usize{ UNI, ERR, UNC }) |ai| {
        try testing.expect(fr[ai].held - row[ai].held > noise[1]);
    }

    // ── POST-HOC: a consolidation is paid for at the next regime change,
    // in CAPACITY. Not a claim about wall clock or about adaptation speed.
    var min_births = row[0].ret_births;
    for (rules) |ai| min_births = @min(min_births, row[ai].ret_births);
    std.debug.print("  returning to A: the control paid {d} births, the cheapest slept arm {d} — capacity, not wall clock\n", .{
        ctl_a.births, min_births,
    });
    try testing.expect(ctl_a.births * 2 < min_births);
}

test "G66 (a) a recency window must not invert when its decay underflows" {
    // The mutation, executable: write the window as `key *= exp(-t/tau)`
    // and run it here. Past `t/tau = 745` the factor underflows to zero,
    // the NEGATIVE key becomes -0.0, and -0.0 sorts ABOVE every live key —
    // so the OLDEST exemplars become unevictable and the buffer fills with
    // precisely the wrong end of history. Clamping the exponent passes no
    // better: past the clamp every exemplar shares one decay factor, so the
    // buffer becomes a uniform reservoir over the clamped tail and this
    // assertion fails at about t = 2 800 instead of inverting at 0.
    //
    // tau = 4 over 5 000 offers drives t/tau to 1250, so both failures fire
    // and the log-magnitude form is the only one that passes.
    const gpa = testing.allocator;
    const TINY: f64 = 4;
    const OFFERS: u64 = 5_000;
    var b = try Replay.initWindowed(gpa, 64, .uniform, 7, TINY);
    defer b.deinit(gpa);
    var st = rng.Stream.region(9, 0x4736_3641, 0); // "G66A"
    var i: u64 = 0;
    while (i < OFFERS) : (i += 1) {
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        b.admit(q, 0, 1, 0);
    }
    var oldest: u64 = std.math.maxInt(u64);
    for (b.t[0..b.filled()]) |t| oldest = @min(oldest, t);
    std.debug.print("\n  G66 (a) [{s}] tau = {d} over {d} offers reaches t/tau = {d} (inverts past {d}); oldest survivor {d}\n", .{
        @tagName(builtin.mode),                                TINY,   OFFERS, @as(u64, @intFromFloat(@as(f64, @floatFromInt(OFFERS)) / TINY)),
        @as(u64, @intFromFloat(thresholds.OBS19_UNDERFLOW_T)), oldest,
    });
    // 4*tau = 16 is the soft edge and the buffer is 64 slots, so 256 is
    // four times the width the rule may legitimately reach back.
    try testing.expect(oldest > OFFERS - 256);
}

test "G66 windowed error replay: can a window price staleness?" {
    // OBS-18 closed with the two halves of a replay buffer separated:
    //
    //     a buffer's LOCATIONS decide how well it fits the world it is
    //     labelled for; its LABELS decide which world that is
    //
    // and its Pareto surface was that split showing through. The ring took
    // the current world because every one of its labels describes it; the
    // unbounded error reservoir preserved the old one because half of its
    // labels still describe THAT. Windowed error replay is the synthesis
    // the split proposes — error's locations, the ring's labels, and no
    // oracle anywhere. OBS-18 could only reach it by relabelling from the
    // truth, which is a probe and not a policy.
    //
    // Two debts recorded at that phase's close, both paid here:
    //
    //   THE TIMING   OBS-18 slept 20 000 observations clear of the move, so
    //                its ring was label-consistent BY THE FIXTURE'S TIMING
    //                and not by any property of rings (Astra). The sleep
    //                happens TWICE in one life here, at M/N = 0.5 where the
    //                ring straddles and at M/N = 2.0 where it does not.
    //   THE FLOOR    every rule this gate makes a claim about is
    //                replicated, and a comparison uses the spread of the
    //                rules IN it. `recent` is the one exception and it is
    //                not an omission: a ring is a deterministic function of
    //                the stream, so its same-rule spread is zero by
    //                construction.
    //
    // `tools/obs19_predict.py` is where the REGISTERED numbers were frozen.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const N: usize = 8192;
    const WAKE_A: u64 = 30_000;
    const EARLY: u64 = 4_096; // M/N = 0.5: the ring straddles the move
    const LATE: u64 = 16_384; // M/N = 2.0: a fresh pool twice the buffer
    const ADAPT: u64 = 20_000;
    const TAU = thresholds.OBS19_WINDOW_TAU;

    const world_a = marl.TruthParams{};
    var world_b = marl.TruthParams{};
    world_b.shift = .{ 0, -0.10, 0 };

    const Arm = struct { name: []const u8, kind: Compose, tau: f64, seed: u64 };
    const arms = [_]Arm{
        .{ .name = "recent", .kind = .recent, .tau = 0, .seed = 0 },
        .{ .name = "uniform", .kind = .uniform, .tau = 0, .seed = 0xA1 },
        .{ .name = "uniform'", .kind = .uniform, .tau = 0, .seed = 0xD4 },
        .{ .name = "error", .kind = .err, .tau = 0, .seed = 0xB2 },
        .{ .name = "error'", .kind = .err, .tau = 0, .seed = 0xF6 },
        .{ .name = "uni@tau", .kind = .uniform, .tau = TAU, .seed = 0x1A },
        .{ .name = "uni@tau'", .kind = .uniform, .tau = TAU, .seed = 0x2B },
        .{ .name = "err@tau", .kind = .err, .tau = TAU, .seed = 0x3C },
        .{ .name = "err@tau'", .kind = .err, .tau = TAU, .seed = 0x4D },
    };
    const REC = 0;
    const UNI = 1;
    const ERR = 3;
    const UNIW = 5;
    const ERRW = 7;
    // One entry per RULE, in the same order, so `rules[i]` is led by
    // `groups[i]`. A comparison between two rules takes the worst spread of
    // the two groups involved — never one rule's variability spent on
    // another's margin, which is the mistake OBS-18 shipped a draft of.
    const rules = [_]usize{ REC, UNI, ERR, UNIW, ERRW };
    const groups = [_][]const usize{
        &.{REC},
        &.{ UNI, 2 },
        &.{ ERR, 4 },
        &.{ UNIW, 6 },
        &.{ ERRW, 8 },
    };

    var bufs: [arms.len]Replay = undefined;
    for (arms, 0..) |a, i| bufs[i] = if (a.tau == 0)
        try Replay.initWith(gpa, N, a.kind, a.seed)
    else
        try Replay.initWindowed(gpa, N, a.kind, a.seed, a.tau);
    defer for (&bufs) |*b| b.deinit(gpa);
    var ptrs: [arms.len]*Replay = undefined;
    for (&bufs, 0..) |*b, i| ptrs[i] = b;

    var m = try marl.Model.init(gpa, o);
    defer m.deinit();
    var st = rng.Stream.region(1234, 0x4f31_3957, 0); // "O19W"
    try wakeAll(&m, WAKE_A, &ptrs, &st);
    m.opts.truth = world_b;
    try wakeAll(&m, EARLY, &ptrs, &st);

    const ha = try marl.probesOf(gpa, world_a, 31337, 4096);
    const hb = try marl.probesOf(gpa, world_b, 31337, 4096);
    defer {
        gpa.free(ha.p);
        gpa.free(ha.y);
        gpa.free(hb.p);
        gpa.free(hb.y);
    }

    const Row = struct {
        old: f64,
        comp: Composition,
        k: usize,
        after: f64,
        gain: f64,
        /// What the sleep PRESERVED of the old world, scored before any
        /// further learning. OBS-18's axis: relearning washes out what a
        /// consolidation kept, so the re-fit column cannot show it.
        held: f64,
        ret: f64 = 0,
        ret_births: u64 = 0,
    };
    const AXES = 3;
    const axes = [_][]const u8{ "immediate (B)", "A held", "A re-fit" };
    const pick = struct {
        fn v(r: anytype, ax: usize) f64 {
            return switch (ax) {
                0 => -r.gain, // negated so every axis is lower-is-better
                1 => r.held,
                else => r.ret,
            };
        }
    }.v;
    const spanOf = struct {
        fn go(r: []const Row, g: []const usize, ax: usize) f64 {
            var worst: f64 = 0;
            for (g, 0..) |a, i| {
                for (g[i + 1 ..]) |b| worst = @max(worst, @abs(pick(r[a], ax) - pick(r[b], ax)));
            }
            return worst;
        }
    }.go;

    std.debug.print("\n  G66 [{s}] N = {d}, tau = {d} (= N/2), one life, two sleeps\n", .{
        @tagName(builtin.mode), N, TAU,
    });
    var rows: [2][arms.len]Row = undefined;
    var margin: [2]f64 = .{ 0, 0 };
    var held_gap: [2]f64 = .{ 0, 0 };
    for (0..2) |offset| {
        const late = offset == 1;
        if (late) try wakeAll(&m, LATE - EARLY, &ptrs, &st);
        const M: u64 = if (late) LATE else EARLY;
        const floor = @as(f64, @floatFromInt(N -| M)) / @as(f64, @floatFromInt(N));
        const keep = m.kernels.items.len / 2;
        const before = try m.rms(hb.p, hb.y, null);
        const ctl_held = try m.rms(ha.p, ha.y, null);
        std.debug.print("\n  ── {s}: {d} observations since the move, M/N = {d:.2}; {d} kernels, k = {d}, before {d:.5}\n", .{
            if (late) "LATE " else "EARLY",                          M,
            @as(f64, @floatFromInt(M)) / @as(f64, @floatFromInt(N)), m.kernels.items.len,
            keep,                                                    before,
        });
        std.debug.print("     the staleness FLOOR is arithmetic: (N-M)/N = {d:.3} — with {d} fresh observations for {d} slots, no rule can beat it\n", .{
            floor, M, N,
        });
        std.debug.print("     control, no sleep: B {d:.5} | A held {d:.5}\n", .{ before, ctl_held });
        std.debug.print("     {s:<9} {s:>6} {s:>9} {s:>6} {s:>6} | {s:>8} {s:>8} | {s:>8}", .{
            "arm", "old", "contested", "stale", "dead", "after", "gain", "A held",
        });
        if (late) std.debug.print(" | {s:>8} {s:>7}", .{ "A re-fit", "births" });
        std.debug.print("\n", .{});

        const row = &rows[offset];
        for (arms, 0..) |arm, ai| {
            const comp = compositionOf(bufs[ai], world_a, world_b, m.kernels.items);
            try (Measures{ .fit = bufs[ai].x[0..N], .sleep = bufs[ai].x[0..N], .eval = hb.p }).check();
            var child = try sleepOn(gpa, &m, bufs[ai].x[0..N], bufs[ai].y[0..N], keep, .{ .exact = true });
            defer child.deinit();
            child.opts.truth = world_b;
            const after = try child.rms(hb.p, hb.y, null);
            row[ai] = .{
                .old = bufs[ai].oldShare(WAKE_A),
                .comp = comp,
                .k = child.kernels.items.len,
                .after = after,
                .gain = 1 - @as(f64, after) / @as(f64, before),
                .held = try child.rms(ha.p, ha.y, null),
            };
            if (late) {
                const ret = try adaptTo(gpa, o, child.kernels.items, world_a, ADAPT, ha);
                row[ai].ret = ret.rms;
                row[ai].ret_births = ret.births;
            }
            std.debug.print("     {s:<9} {d:>6.3} {d:>9.4} {d:>6.3} {d:>6.3} | {d:>8.5} {d:>8.4} | {d:>8.5}", .{
                arm.name,      row[ai].old,  comp.contested, comp.stale, comp.dead,
                row[ai].after, row[ai].gain, row[ai].held,
            });
            if (late) std.debug.print(" | {d:>8.5} {d:>7}", .{ row[ai].ret, row[ai].ret_births });
            std.debug.print("\n", .{});
            // Equal k, asserted rather than announced — OBS-18 shipped a
            // draft that printed a budget it did not deliver.
            try testing.expectEqual(keep, row[ai].k);
        }

        const nax: usize = if (late) AXES else 2;
        std.debug.print("     same-rule spread (DESCRIPTIVE, two draws a rule — not a confidence bound):", .{});
        for (0..nax) |ax| {
            std.debug.print("  {s} u{d:.4}/e{d:.4}/uw{d:.4}/ew{d:.4}", .{
                axes[ax],
                spanOf(row, groups[1], ax),
                spanOf(row, groups[2], ax),
                spanOf(row, groups[3], ax),
                spanOf(row, groups[4], ax),
            });
        }
        std.debug.print("\n", .{});

        // A pair separates when it clears the WORSE of the two rules' own
        // spreads. Reported for every pair, because a leader tied with its
        // nearest rival hides every difference behind it — OBS-18's draft
        // read "nothing separates" off exactly that and was wrong about
        // four pairs of six.
        const sep = struct {
            fn go(r: []const Row, g: []const []const usize, a: usize, b: usize, ax: usize) f64 {
                const sp = @max(spanOf(r, g[a], ax), spanOf(r, g[b], ax));
                return (pick(r[g[a][0]], ax) - pick(r[g[b][0]], ax)) / @max(1e-12, sp);
            }
        }.go;
        std.debug.print("     pairwise, in units of the WORSE of the two rules' own spreads (negative = the first is better):\n", .{});
        // The A re-fit axis is EXPLORATORY and gets no pairwise ranking:
        // there is no unslept reacquisition baseline here, so a highlighted
        // comparison would read as a claim the gate cannot support. The raw
        // column and the per-rule spreads stay; err@tau's own two draws
        // differ by 0.0250 on it, which is the whole reason.
        for (0..@min(nax, 2)) |ax| {
            std.debug.print("       {s: <15}", .{axes[ax]});
            for (rules, 0..) |_, i| {
                for (rules[i + 1 ..], i + 1..) |_, j| {
                    const s = sep(row, &groups, i, j, ax);
                    if (@abs(s) <= 1) continue;
                    std.debug.print("  {s}/{s} {d:.2}x", .{ arms[rules[i]].name, arms[rules[j]].name, s });
                }
            }
            std.debug.print("\n", .{});
        }

        // The measure's own strength, as an enrichment of contested share
        // over its matched uniform control. Printed at BOTH offsets and
        // asserted at only one, because P8 predicts the window erases it
        // where the fresh pool is smaller than the buffer.
        std.debug.print("     the measure as an enrichment of contested share over its matched uniform control: unbounded {d:.2}x   windowed {d:.2}x\n", .{
            row[ERR].comp.contested / row[UNI].comp.contested,
            row[ERRW].comp.contested / row[UNIW].comp.contested,
        });
        // THE DERIVED QUANTITY THE FIRST DRAFT OF THIS TABLE WAS MISSING.
        //
        // `old` counts slots recorded before the move, but over nine tenths
        // of this cube the two worlds AGREE — so a pre-move observation is
        // usually a perfectly good post-move observation. What actually
        // misleads a consolidation is the product: contested AND stale.
        // On this fixture such a label is wrong by most of the shell's
        // amplitude, against a target whose mean magnitude is 0.075, so a
        // few hundred of them carry a sizeable share of the buffer's whole
        // squared signal.
        std.debug.print("     WRONG LABELS (contested AND stale), out of {d}:", .{N});
        for (rules) |ai| std.debug.print("  {s} {d}", .{
            arms[ai].name, @as(usize, @intFromFloat(@round(row[ai].comp.stale * row[ai].comp.contested * @as(f64, @floatFromInt(N))))),
        });
        std.debug.print("\n", .{});

        // THE ANTAGONISM, and it is the phase's finding. For every other
        // rule the share of CONTESTED slots that are stale tracks the share
        // of ALL slots that are stale. For windowed error it does not.
        std.debug.print("     staleness CONCENTRATION, stale - old (positive = the stale remnant is enriched in contested):", .{});
        for (rules) |ai| std.debug.print("  {s} {d:.3}", .{ arms[ai].name, row[ai].comp.stale - row[ai].old });
        std.debug.print("\n", .{});

        margin[offset] = row[ERRW].gain - row[REC].gain;
        held_gap[offset] = row[ERRW].held - row[REC].held;
    }

    // ── THE SAME-POINTS REFRESH CONTROL. Astra's, and it is the
    // INTERVENTION the phase's central claim needed — the wrong-label count
    // is a descriptive statistic and cannot establish a cause on its own.
    //
    // Same parent, same locations, same keep count, same selection/refit/
    // refinement; ONLY the labels change, re-read from the world being
    // evaluated. It needs an oracle per point, so it is a probe and not a
    // deployable policy — OBS-18's framing, and the same caveat: a label
    // change can move all three stages of a sleep, and this does not
    // separate them.
    const keep_late = m.kernels.items.len / 2;
    const fresh = try gpa.alloc(f64, N);
    defer gpa.free(fresh);
    var refr: [arms.len]f64 = .{0} ** arms.len;
    var refr_held: [arms.len]f64 = .{0} ** arms.len;
    const windowed = [_]usize{ UNIW, 6, ERRW, 8 };
    std.debug.print("\n  ── SAME-POINTS REFRESH (post-hoc probe, an oracle per point — NOT a policy). Ring B RMS {d:.5}\n", .{rows[1][REC].after});
    std.debug.print("     {s:<9} {s:>9} {s:>10} {s:>9} | {s:>9} {s:>10}   (gap closed over 100% = the refreshed arm BEATS the ring)\n", .{ "arm", "policy B", "refreshed", "gap closed", "policy A", "refreshed" });
    for (windowed) |ai| {
        for (bufs[ai].x[0..N], 0..) |q, i| fresh[i] = marl.truthOf(world_b, q);
        try (Measures{ .fit = bufs[ai].x[0..N], .sleep = bufs[ai].x[0..N], .eval = hb.p }).check();
        var fc = try sleepOn(gpa, &m, bufs[ai].x[0..N], fresh, keep_late, .{ .exact = true });
        defer fc.deinit();
        fc.opts.truth = world_b;
        refr[ai] = try fc.rms(hb.p, hb.y, null);
        refr_held[ai] = try fc.rms(ha.p, ha.y, null);
        try testing.expectEqual(keep_late, fc.kernels.items.len);
        const gap = rows[1][ai].after - rows[1][REC].after;
        std.debug.print("     {s:<9} {d:>9.5} {d:>10.5} {d:>8.0}% | {d:>9.5} {d:>10.5}\n", .{
            arms[ai].name,                                          rows[1][ai].after, refr[ai],
            100 * (rows[1][ai].after - refr[ai]) / @max(1e-9, gap), rows[1][ai].held,  refr_held[ai],
        });
    }
    std.debug.print("     CHANGING LABELS ALONE REVERSES THE RANKING, in both tested draws: {d:.5} and {d:.5} against the ring's {d:.5} — {d:.0}% and {d:.0}% lower error on the current world\n", .{
        refr[ERRW],                                                   refr[8],                                                   rows[1][REC].after,
        100 * (rows[1][REC].after - refr[ERRW]) / rows[1][REC].after, 100 * (rows[1][REC].after - refr[8]) / rows[1][REC].after,
    });
    std.debug.print("     the uniform draws close most of their gap and do NOT reach the ring, so their residual deficit is not labels alone. The gap-closed column is correct but depends on each arm's ORIGINAL deficit; the absolute RMS above is the interpretable number (Astra)\n", .{});
    std.debug.print("     this bounds the claim to the INTERVENTION — it does not show locations and labels act independently through selection, refit and refinement\n", .{});

    // ── WHAT THE REFRESH ESTABLISHES. Historical labels cause substantial
    // current-world loss through this pipeline: refreshing reverses BOTH
    // error draws' ordering against the ring and closes most of the uniform
    // draws' gap. So `err@tau` is not selecting bad locations — it is
    // selecting good ones and carrying bad labels on them, which is exactly
    // what a window is supposed to prevent and this window does not.
    for ([_]usize{ ERRW, 8 }) |ai| {
        try testing.expect(refr[ai] < rows[1][REC].after);
        // And refreshing COSTS the old world, as OBS-18 found for every rule
        // it tested: the error arm's retention is carried by its labels.
        try testing.expect(refr_held[ai] > rows[1][ai].held);
    }
    for ([_]usize{ UNIW, 6 }) |ai| {
        try testing.expect(refr[ai] < rows[1][ai].after);
        // ...but it does NOT reach the ring, so the uniform arm's residual
        // deficit is not explained by labels alone and leaves room for a
        // location effect. Asserted so a future change that closes it is
        // noticed rather than assumed.
        try testing.expect(refr[ai] > rows[1][REC].after);
    }

    std.debug.print("\n  err@tau against the ring, immediate fit: EARLY {d:.4}  LATE {d:.4}  (positive = the window wins)\n", .{ margin[0], margin[1] });
    std.debug.print("  err@tau against the ring, A held:        EARLY {d:.5}  LATE {d:.5}  (negative = the window retains BETTER)\n", .{ held_gap[0], held_gap[1] });
    std.debug.print("  REGISTERED and REFUTED: P4 (OBS-18's 2.5x enrichment not reached at EITHER offset, 2.09x both — and two checkpoints are two points, so no ceiling is claimed), P5 (the RING wins the current world), P7 (err@tau retains BETTER than the ring, the favourable direction), P8 (numerically refuted, MECHANISM UNRESOLVED — the offsets differ in parent, convergence, replay, normalisation denominator and kept budget)\n", .{});
    std.debug.print("  an EXPONENTIAL recency price can be BOUGHT PAST, and what buys its way past is adversely selected\n", .{});
    std.debug.print("  admission surprise is FROZEN at observation time — nothing reprioritises an old exemplar after the move — but A-era surprise already concentrates on the structure the worlds will later disagree about, so the exemplars that outbid the window are enriched in the labels it exists to exclude\n", .{});
    std.debug.print("  a HARD cutoff cannot be bought past at any weight, and is UNTESTED: no impossibility of synthesis is established here\n", .{});

    // ── Every assertion lives here, AFTER every print. A refuted
    // prediction must still leave its table behind: the first run of this
    // gate aborted inside the loop and threw away the offset it had not
    // reached yet.

    // ── REGISTERED P1/P2: THE PREMISE — where the sleep actually is. HELD.
    // The ring achieves the arithmetic floor EXACTLY at the early offset,
    // which is the whole of what OBS-18's 0.000 was: the fixture's timing.
    try testing.expect(@abs(rows[0][REC].old - thresholds.OBS19_STALE_FLOOR) < 1e-12);
    for (rows[0]) |r| try testing.expect(r.old >= thresholds.OBS19_STALE_FLOOR - 1e-12);
    try testing.expectEqual(@as(f64, 0), rows[1][REC].old);
    try testing.expectEqual(@as(f64, 0), rows[1][REC].comp.stale);

    // ── REGISTERED P3: the window is a window. HELD, at 0.036 against a
    // registered 0.05 and a simulated 0.035.
    //
    // The ceiling is asserted on the UNIFORM rule alone, because that is
    // the rule it was derived on — `obs19_predict.py` simulates w = 1
    // exactly. Spending it on the error arm would be this campaign's own
    // standing mistake, a number measured on one rule applied to another,
    // which is what Astra caught in OBS-18. The error arm carries the
    // ordinal claim and prints its value — and reads 0.076, which is to
    // say the ceiling would have been WRONG for it.
    try testing.expect(rows[1][UNIW].old < thresholds.OBS19_WINDOW_OLD);
    for (0..2) |i| {
        try testing.expect(rows[i][UNIW].old < rows[i][UNI].old);
        try testing.expect(rows[i][ERRW].old < rows[i][ERR].old);
    }

    // ── REGISTERED P4: REFUTED AT BOTH OFFSETS, and the refutation is
    // asserted so that a change of sign is caught.
    //
    // The measure survives a window in the sense that it still enriches —
    // but a window COSTS it a third of its enrichment, and the registered
    // 2.5x (OBS-18's own, carried over) is not reached at EITHER offset:
    // 3.08x -> 2.09x at M/N = 0.5 and 3.66x -> 2.09x at M/N = 2.0.
    //
    // That the two windowed values round alike (2.0901 and 2.0864) is NOT a
    // ceiling and NOT independence from timing — Astra's correction, and it
    // is right: two checkpoints are two points. What it does refute is P8's
    // REASONING, which had the erasure specific to M < N; the erasure is
    // present at both offsets measured.
    const enrich = struct {
        fn go(r: []const Row, w: bool) f64 {
            return if (w) r[ERRW].comp.contested / r[UNIW].comp.contested else r[ERR].comp.contested / r[UNI].comp.contested;
        }
    }.go;
    for (0..2) |i| {
        try testing.expect(rows[i][ERR].comp.contested > thresholds.OBS18_ERROR_CONTESTED * rows[i][UNI].comp.contested);
        try testing.expect(rows[i][ERRW].comp.contested > rows[i][UNIW].comp.contested);
        try testing.expect(enrich(&rows[i], true) < enrich(&rows[i], false));
        try testing.expect(enrich(&rows[i], true) < thresholds.OBS18_ERROR_CONTESTED);
    }

    // ── REGISTERED P5: REFUTED, and decisively. The RING wins the current
    // world at the late offset, beating every other rule by more than that
    // rule's own spread — windowed error by 9.25x and windowed uniform by
    // 4.14x. OBS-18's oracle result does NOT survive being earned honestly.
    //
    // The ring is the only rule whose membership is decided by TIME ALONE,
    // so when the fresh pool exceeds the buffer it carries EXACTLY zero
    // wrong labels. Every measure-based rule admits some, and an error
    // measure admits disproportionately the harmful ones.
    for (rules, 0..) |ai, gi| {
        if (ai == REC) continue;
        try testing.expect(rows[1][REC].gain - rows[1][ai].gain > spanOf(&rows[1], groups[gi], 0));
    }

    // ── REGISTERED P6: HELD. Windowed error retains the old world worse
    // than the unbounded error rule does, clearing the worse of the two
    // spreads. The tradeoff the phase was asked to test is real.
    try testing.expect(rows[1][ERRW].held - rows[1][ERR].held >
        @max(spanOf(&rows[1], groups[4], 1), spanOf(&rows[1], groups[2], 1)));

    // ── REGISTERED P7: REFUTED, in the FAVOURABLE direction. Registered as
    // "not separated from the ring on retention"; windowed error in fact
    // retains BETTER than the ring, by 3.04x its own spread. So the Pareto
    // surface survives with windowed error on it — just at the opposite
    // corner from the one predicted. It buys retention and pays in
    // immediate fit, where the prediction had it the other way round.
    try testing.expect(rows[1][REC].held - rows[1][ERRW].held > spanOf(&rows[1], groups[4], 1));

    // ── REGISTERED P8: its NUMERICAL prediction failed and its MECHANISM
    // is unresolved. The registered direction does not hold; no replacement
    // is claimed.
    //
    // The cross-offset comparison is confounded in five ways at once — the
    // two offsets differ in parent, convergence, replay contents, the
    // normalisation denominator (`before`, 0.10270 against 0.08002) and the
    // kept budget (343 against 367). An earlier draft argued the EARLY
    // margins were small because every gain there is negative; that is not
    // a bound on a pairwise lead and the argument is withdrawn.
    try testing.expect(margin[1] < margin[0]);

    // ── AND THE MECHANISM THAT REPLACES IT. An error measure and a recency
    // window select against each other. The window exists to drop pre-move
    // observations; the measure's highest weights sit on the contested
    // band, which is exactly where a pre-move observation is most wrong. So
    // what survives the window is ENRICHED in the labels the window was
    // built to exclude — and windowed error is the only rule for which the
    // stale remnant is enriched at all.
    //
    // Mutation: give `err@tau` the uniform weight and the concentration
    // collapses to `uni@tau`'s, which is zero to within a draw.
    for (0..2) |i| {
        const conc = rows[i][ERRW].comp.stale - rows[i][ERRW].old;
        try testing.expect(conc > 0.05);
        for (rules) |ai| {
            if (ai == ERRW) continue;
            try testing.expect(conc > (rows[i][ai].comp.stale - rows[i][ai].old) + 0.05);
        }
    }

    // ── AND WHAT THE MEASURE IS STILL WORTH. At MATCHED staleness the
    // error rule dominates the uniform one on BOTH axes — 0.639 against
    // 0.659 of the buffer stale, and better on the current world AND on the
    // old one. So the measure is not refuted; what is refuted is the idea
    // that a window can deliver it at the ring's freshness.
    try testing.expect(@abs(rows[1][ERR].old - rows[1][UNI].old) < 0.05);
    try testing.expect(rows[1][ERR].gain - rows[1][UNI].gain > @max(spanOf(&rows[1], groups[2], 0), spanOf(&rows[1], groups[1], 0)));
    try testing.expect(rows[1][UNI].held - rows[1][ERR].held > @max(spanOf(&rows[1], groups[2], 1), spanOf(&rows[1], groups[1], 1)));
}

test "G67 a hard cutoff: does error selection pay when the pool is shared?" {
    // OBS-19 established that an EXPONENTIAL recency price can be PAID.
    // Whatever survives such a window had to outbid it, and on a moved world
    // what outbids it is adversely selected — A-era surprise already
    // concentrates on the structure the two worlds will later disagree
    // about, so `err@tau` carried 276 wrong labels of 8192 against
    // `uni@tau`'s 37.
    //
    // It also established, under a same-points refresh control, that THE
    // LOCATIONS ARE NOT THE PROBLEM: given current labels the error-selected
    // points reached 0.02866 and 0.03004 against the ring's 0.04650, 38% and
    // 35% lower error. That arm needed an oracle per point.
    //
    // A HARD cutoff cannot be bought past at any weight. So: does it deliver
    // that arm honestly? Astra's specification, and its contract decides the
    // whole design — *identical eligible observations for the error and
    // uniform selections, with the cutoff preventing either rule from
    // retaining an expired sample.* See `Window`: the pool is one shared
    // object and the gate asserts the contract rather than arguing it.
    //
    // `tools/obs20_predict.py` is where the REGISTERED numbers were frozen.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const N: usize = 8192;
    const WAKE_A: u64 = 30_000;
    const M: u64 = 16_384; // M/N = 2.0, OBS-19's late offset exactly
    const CLEAN = thresholds.OBS20_CLEAN_SPAN * N; // 2N: reaches back to the move and no further
    const WIDE = 4 * N; // 4N: reaches 16384 observations PAST it
    const TOTAL = WAKE_A + M;

    const world_a = marl.TruthParams{};
    var world_b = marl.TruthParams{};
    world_b.shift = .{ 0, -0.10, 0 };

    var w_deg = try Window.init(gpa, N);
    defer w_deg.deinit(gpa);
    var w_clean = try Window.init(gpa, CLEAN);
    defer w_clean.deinit(gpa);
    var w_wide = try Window.init(gpa, WIDE);
    defer w_wide.deinit(gpa);

    const Arm = struct { name: []const u8, kind: Compose, tau: f64, seed: u64, w: ?usize };
    const arms = [_]Arm{
        // Streaming: the incumbent ring, and OBS-19's exponential price for
        // a direct comparison at matched N and k.
        .{ .name = "recent", .kind = .recent, .tau = 0, .seed = 0, .w = null },
        .{ .name = "err@tau", .kind = .err, .tau = thresholds.OBS19_WINDOW_TAU, .seed = 0x3C, .w = null },
        .{ .name = "err@tau'", .kind = .err, .tau = thresholds.OBS19_WINDOW_TAU, .seed = 0x4D, .w = null },
        // Selected from a SHARED hard-cutoff pool. Same window index means
        // literally the same object, which is the contract.
        .{ .name = "h-uni@2N", .kind = .uniform, .tau = 0, .seed = 0x11, .w = 1 },
        .{ .name = "h-uni@2N'", .kind = .uniform, .tau = 0, .seed = 0x22, .w = 1 },
        .{ .name = "h-err@2N", .kind = .err, .tau = 0, .seed = 0x33, .w = 1 },
        .{ .name = "h-err@2N'", .kind = .err, .tau = 0, .seed = 0x44, .w = 1 },
        .{ .name = "h-uni@4N", .kind = .uniform, .tau = 0, .seed = 0x55, .w = 2 },
        .{ .name = "h-uni@4N'", .kind = .uniform, .tau = 0, .seed = 0x66, .w = 2 },
        .{ .name = "h-err@4N", .kind = .err, .tau = 0, .seed = 0x77, .w = 2 },
        .{ .name = "h-err@4N'", .kind = .err, .tau = 0, .seed = 0x88, .w = 2 },
    };
    const REC = 0;
    const EXP = 1;
    const U2 = 3;
    const E2 = 5;
    const U4 = 7;
    const E4 = 9;
    const rules = [_]usize{ REC, EXP, U2, E2, U4, E4 };
    const groups = [_][]const usize{
        &.{REC}, // deterministic in the stream: its spread is zero by construction
        &.{ EXP, 2 },
        &.{ U2, 4 },
        &.{ E2, 6 },
        &.{ U4, 8 },
        &.{ E4, 10 },
    };

    var bufs: [arms.len]Replay = undefined;
    for (arms, 0..) |a, i| bufs[i] = if (a.tau == 0)
        try Replay.initWith(gpa, N, a.kind, a.seed)
    else
        try Replay.initWindowed(gpa, N, a.kind, a.seed, a.tau);
    defer for (&bufs) |*b| b.deinit(gpa);

    // Only the streaming arms are fed by the wake; the rest select afterwards.
    var streaming: [3]*Replay = .{ &bufs[0], &bufs[1], &bufs[2] };
    var wins: [3]*Window = .{ &w_deg, &w_clean, &w_wide };

    var m = try marl.Model.init(gpa, o);
    defer m.deinit();
    var st = rng.Stream.region(1234, 0x4f32_3048, 0); // "O20H"
    try wakeInto(&m, WAKE_A, &streaming, &wins, &st);
    m.opts.truth = world_b;
    try wakeInto(&m, M, &streaming, &wins, &st);

    const ha = try marl.probesOf(gpa, world_a, 31337, 4096);
    const hb = try marl.probesOf(gpa, world_b, 31337, 4096);
    defer {
        gpa.free(ha.p);
        gpa.free(ha.y);
        gpa.free(hb.p);
        gpa.free(hb.y);
    }

    const keep = m.kernels.items.len / 2;
    const before = try m.rms(hb.p, hb.y, null);
    const ctl_held = try m.rms(ha.p, ha.y, null);
    std.debug.print("\n  G67 [{s}] {d} kernels, k = {d}, N = {d}; W in {{N, 2N, 4N}} = {{{d}, {d}, {d}}} over {d} observations\n", .{
        @tagName(builtin.mode), m.kernels.items.len, keep, N, N, CLEAN, WIDE, TOTAL,
    });
    std.debug.print("     control, no sleep: B {d:.5} | A held {d:.5}\n", .{ before, ctl_held });

    // ── Q1, THE CONTRACT, asserted before anything is measured. A pool is a
    // ring, so arithmetic already says what is in it; the gate checks the
    // arithmetic rather than trusting it.
    for (wins, [_]usize{ N, CLEAN, WIDE }) |w, span| {
        try testing.expectEqual(span, w.filled());
        for (w.t[0..span]) |ti| try testing.expect(ti >= TOTAL - @as(u64, span));
    }
    std.debug.print("     pool composition (DETERMINISTIC — a window is a ring):", .{});
    for (wins, [_][]const u8{ "N", "2N", "4N" }) |w, nm| {
        std.debug.print("  W={s} {d} obs, pre-move {d:.3}", .{ nm, w.filled(), w.oldShare(WAKE_A) });
    }
    std.debug.print("\n", .{});
    try testing.expectEqual(@as(f64, 0), w_deg.oldShare(WAKE_A));
    try testing.expectEqual(@as(f64, 0), w_clean.oldShare(WAKE_A));
    try testing.expect(@abs(w_wide.oldShare(WAKE_A) - 0.5) < 1e-12);

    // ── Q2, THE DEGENERATE CHECK. At W = N the pool IS the buffer, so every
    // rule must select all of it whatever its measure — and the result is the
    // ring. If this fails, the window and the measure are not wired to each
    // other the way the phase assumes.
    {
        var d_uni = try Replay.initWith(gpa, N, .uniform, 0x99);
        defer d_uni.deinit(gpa);
        var d_err = try Replay.initWith(gpa, N, .err, 0xAA);
        defer d_err.deinit(gpa);
        w_deg.selectInto(&d_uni);
        w_deg.selectInto(&d_err);
        try testing.expectEqual(N, d_uni.filled());
        try testing.expectEqual(N, d_err.filled());
        for (d_uni.t[0..N]) |ti| try testing.expect(ti >= TOTAL - @as(u64, N));
        for (d_err.t[0..N]) |ti| try testing.expect(ti >= TOTAL - @as(u64, N));
        try testing.expectEqual(@as(f64, 0), bufs[REC].oldShare(TOTAL - N));
        std.debug.print("     Q2 degenerate: at W = N every rule selects the whole pool, so uniform and error both reduce to the ring\n", .{});
    }

    // Fill the selected arms from their shared pools.
    for (arms, 0..) |a, i| {
        if (a.w) |wi| wins[wi].selectInto(&bufs[i]);
    }

    const Row = struct {
        old: f64,
        comp: Composition,
        wrong: f64,
        k: usize,
        after: f64,
        gain: f64,
        held: f64,
    };
    const AXES = 2;
    const axes = [_][]const u8{ "immediate (B)", "A held" };
    const pick = struct {
        fn v(r: anytype, ax: usize) f64 {
            return if (ax == 0) -r.gain else r.held;
        }
    }.v;
    const spanOf = struct {
        fn go(r: []const Row, g: []const usize, ax: usize) f64 {
            var worst: f64 = 0;
            for (g, 0..) |a, i| {
                for (g[i + 1 ..]) |b| worst = @max(worst, @abs(pick(r[a], ax) - pick(r[b], ax)));
            }
            return worst;
        }
    }.go;

    std.debug.print("     {s:<11} {s:>6} {s:>9} {s:>6} {s:>7} {s:>6} | {s:>8} {s:>8} | {s:>8}\n", .{
        "arm", "old", "contested", "stale", "wrong", "dead", "after", "gain", "A held",
    });
    var row: [arms.len]Row = undefined;
    for (arms, 0..) |arm, ai| {
        const comp = compositionOf(bufs[ai], world_a, world_b, m.kernels.items);
        try (Measures{ .fit = bufs[ai].x[0..N], .sleep = bufs[ai].x[0..N], .eval = hb.p }).check();
        var child = try sleepOn(gpa, &m, bufs[ai].x[0..N], bufs[ai].y[0..N], keep, .{ .exact = true });
        defer child.deinit();
        child.opts.truth = world_b;
        const after = try child.rms(hb.p, hb.y, null);
        row[ai] = .{
            .old = bufs[ai].oldShare(WAKE_A),
            .comp = comp,
            .wrong = comp.stale * comp.contested * @as(f64, @floatFromInt(N)),
            .k = child.kernels.items.len,
            .after = after,
            .gain = 1 - @as(f64, after) / @as(f64, before),
            .held = try child.rms(ha.p, ha.y, null),
        };
        std.debug.print("     {s:<11} {d:>6.3} {d:>9.4} {d:>6.3} {d:>7.0} {d:>6.3} | {d:>8.5} {d:>8.4} | {d:>8.5}\n", .{
            arm.name,      row[ai].old,  comp.contested, comp.stale, row[ai].wrong, comp.dead,
            row[ai].after, row[ai].gain, row[ai].held,
        });
        try testing.expectEqual(keep, row[ai].k);
    }

    std.debug.print("     same-rule spread (DESCRIPTIVE, two draws a rule — not a confidence bound):", .{});
    for (0..AXES) |ax| {
        std.debug.print("  {s}", .{axes[ax]});
        for (groups[1..]) |g| std.debug.print(" {d:.4}", .{spanOf(&row, g, ax)});
    }
    std.debug.print("\n", .{});
    std.debug.print("     pairwise, in units of the WORSE of the two rules' own spreads (negative = the first is better):\n", .{});
    for (0..AXES) |ax| {
        std.debug.print("       {s: <15}", .{axes[ax]});
        for (rules, 0..) |_, i| {
            for (rules[i + 1 ..], i + 1..) |_, j| {
                const sp = @max(spanOf(&row, groups[i], ax), spanOf(&row, groups[j], ax));
                const d = (pick(row[rules[i]], ax) - pick(row[rules[j]], ax)) / @max(1e-12, sp);
                if (@abs(d) <= 1) continue;
                std.debug.print("  {s}/{s} {d:.2}x", .{ arms[rules[i]].name, arms[rules[j]].name, d });
            }
        }
        std.debug.print("\n", .{});
    }

    // ── THE SAME-POINTS REFRESH CONTROL, now standing practice. If the hard
    // cutoff has already removed every wrong label from the 2N arms, then
    // refreshing them can change nothing — which is a far stronger check of
    // the contract than counting labels.
    const fresh = try gpa.alloc(f64, N);
    defer gpa.free(fresh);
    var refr: [arms.len]f64 = .{0} ** arms.len;
    for ([_]usize{ E2, 6, E4, 10 }) |ai| {
        for (bufs[ai].x[0..N], 0..) |q, i| fresh[i] = marl.truthOf(world_b, q);
        var fc = try sleepOn(gpa, &m, bufs[ai].x[0..N], fresh, keep, .{ .exact = true });
        defer fc.deinit();
        fc.opts.truth = world_b;
        refr[ai] = try fc.rms(hb.p, hb.y, null);
    }
    std.debug.print("     SAME-POINTS REFRESH (a probe, an oracle per point — NOT a policy):", .{});
    for ([_]usize{ E2, 6, E4, 10 }) |ai| {
        std.debug.print("  {s} {d:.5}->{d:.5}", .{ arms[ai].name, row[ai].after, refr[ai] });
    }
    std.debug.print("\n", .{});

    // ── Q3: zero wrong labels at 2N BY CONSTRUCTION, both rules; and at 4N
    // the error rule carries MORE than the uniform one — OBS-19's adverse
    // selection surviving the change of mechanism. A cutoff removes the
    // ability to BUY past the window; it does not remove the measure's
    // preference for the contested band INSIDE it.
    for ([_]usize{ U2, 4, E2, 6 }) |ai| {
        try testing.expectEqual(@as(f64, 0), row[ai].old);
        try testing.expectEqual(@as(f64, 0), row[ai].comp.stale);
    }
    for ([_]usize{ U4, 8, E4, 10 }) |ai| try testing.expect(row[ai].old > 0.3);
    try testing.expect(row[E4].wrong > row[U4].wrong);
    try testing.expect(row[10].wrong > row[8].wrong);
    // The registered uniform figure, derived from the fixture's contested
    // share and the pool's arithmetic rather than guessed.
    try testing.expect(@abs(row[U4].wrong - thresholds.OBS20_STRADDLE_WRONG) < 120);

    // ── Q3b: a refresh can change NOTHING at 2N, because there is nothing to
    // refresh. The strongest available statement of the contract.
    for ([_]usize{ E2, 6 }) |ai| try testing.expect(@abs(refr[ai] - row[ai].after) < 1e-12);
    // ...and it CAN at 4N, where the window straddles.
    try testing.expect(refr[E4] < row[E4].after);

    std.debug.print("     a refresh changes NOTHING at W = 2N — there is nothing to refresh, which is the contract stated as a measurement rather than a count\n", .{});

    // ── Q9, THE PRICE OF THE CUTOFF, reported rather than thresholded. It is
    // STORAGE, and it is W rather than N: OBS-19's exponential form needed no
    // expiry machinery and no extra slots, and this needs the window.
    std.debug.print("     the cutoff's price is STORAGE: {d} observations retained at W = 2N and {d} at 4N, against the exponential form's {d}\n", .{
        CLEAN, WIDE, N,
    });

    // ── Q4, THE HEADLINE. Error-selected locations with zero wrong labels,
    // no oracle anywhere, beating the ring on the world being evaluated.
    //
    // **The ring comparison is NOT resource-matched, and that belongs beside
    // the number.** Both hard arms retain W = 2N observations plus the
    // selected N-slot buffer, against the ring's N, and they scan the pool at
    // selection time. Against each other the two hard arms are matched
    // exactly; against the ring they also buy a larger candidate pool.
    //
    // And the RESOURCE-MATCHED CONTROL is already in the table: `h-uni@2N`
    // IS a ring of 2N subsampled uniformly to N — the same retained history
    // as the error arms, the same k, differing only in the weight. It beats
    // the N-ring at 0.05139 and 0.05069 against 0.05390, about 5%, and error
    // weighting adds a further 26%. Reporting only the error arm against the
    // N-ring would credit the measure with a gain eligibility already bought:
    // roughly a sixth of the 30% is the pool, five sixths the measure.
    try testing.expect(row[E2].gain - row[REC].gain > spanOf(&row, groups[3], 0));
    try testing.expect(row[6].gain - row[REC].gain > spanOf(&row, groups[3], 0));

    // ── Q5, THE MEASURE AT IDENTICAL ELIGIBILITY. The same `Window` object,
    // identical k, identical selection/refit/refinement, differing only in
    // the expression inside `Compose.weight`.
    //
    // This ISOLATES the selection rule cleanly. It is NOT the campaign's
    // first legitimate comparison of selection rules — OBS-18 and OBS-19
    // compared rules fed one stream, and rules keeping different subsets is
    // what rules do (Astra). What is new is that eligibility is pinned, so
    // the comparison is of selection ALONE rather than of selection plus
    // whatever staleness each rule's own admissions happened to carry.
    try testing.expect(row[E2].gain - row[U2].gain >
        @max(spanOf(&row, groups[3], 0), spanOf(&row, groups[2], 0)));

    // ── Q6, THE LIMIT. A hard cutoff cannot be bought past — but it can be
    // set too WIDE, and nothing tells a policy where the last regime change
    // was. At W = 4N half the pool is pre-move and every arm goes negative.
    //
    //     A hard cutoff guarantees ELIGIBILITY, never VALIDITY.
    try testing.expect(row[E2].gain - row[E4].gain >
        @max(spanOf(&row, groups[3], 0), spanOf(&row, groups[5], 0)));
    for ([_]usize{ U4, 8, E4, 10 }) |ai| try testing.expect(row[ai].gain < 0);

    // ── Q7, HARD AGAINST EXPONENTIAL, at matched N and k. OBS-19's price
    // against OBS-20's cutoff, same fixture, same offset, same everything
    // else.
    try testing.expect(row[E2].gain - row[EXP].gain >
        @max(spanOf(&row, groups[3], 0), spanOf(&row, groups[1], 0)));

    // ── POST-HOC, AND THE SHARPEST THING IN THE TABLE. Refreshed, the WIDE
    // window's error locations beat the CLEAN window's — 0.02918 and 0.02829
    // against 0.03787 and 0.03733.
    //
    // So the cutoff is not free. It buys label validity by giving up
    // SELECTION FREEDOM: `h-err@2N` chooses 8 192 from 16 384 where
    // `h-err@4N` chooses from 32 768, and more pool makes better locations.
    // Registered as an asymmetry BEFORE the run, in the expectation that it
    // would cost the 2N arm; it does, and the refresh is what measures it.
    //
    // **What does NOT follow is that detecting the move would recover it.**
    // The refreshed 4N arm's better locations INCLUDE pre-move observations,
    // and cutting at the move REMOVES them rather than supplying their
    // current labels — an exact detected cutoff is the 2N eligible history
    // already tested here. Astra's correction, and it retires the next
    // experiment an earlier draft proposed. What the refreshed arm shows is
    // the value of a larger pool of VALIDLY LABELLED points, which on a moved
    // world cannot come from selecting better.
    try testing.expect(refr[E4] < refr[E2]);
    try testing.expect(refr[10] < refr[6]);
    std.debug.print("     SELECTION FREEDOM IS WORTH SOMETHING: refreshed, the WIDE window's locations beat the clean one's ({d:.5}/{d:.5} against {d:.5}/{d:.5}) — a wider window is the better instrument and the worse policy\n", .{
        refr[E4], refr[10], refr[E2], refr[6],
    });

    // ── RETENTION is reported and NOT asserted, because the reading depends
    // on whether first draws or replicate means are used: the ring against
    // `h-err@2N` is 0.84x the spread on leaders and about 1.3x on means.
    // Astra's OBS-19 catch was exactly this conflation, so the honest claim
    // is "not materially worse" and the gate makes no separation claim.
    std.debug.print("     retention, ring {d:.5} against h-err@2N {d:.5}/{d:.5} (spread {d:.4}): {d:.2}x on the leader, {d:.2}x on the mean — reported, NOT claimed\n", .{
        row[REC].held,                                                            row[E2].held,                                                                                 row[6].held, spanOf(&row, groups[3], 1),
        (row[E2].held - row[REC].held) / @max(1e-12, spanOf(&row, groups[3], 1)), ((row[E2].held + row[6].held) / 2 - row[REC].held) / @max(1e-12, spanOf(&row, groups[3], 1)),
    });
    std.debug.print("     error-selected locations, zero wrong labels, no oracle: {d:.5}/{d:.5} against the ring's {d:.5} — {d:.0}% lower error, ON THIS FIXTURE AND AT THIS TIMING\n", .{
        row[E2].after,                                                                row[6].after, row[REC].after,
        100 * (row[REC].after - (row[E2].after + row[6].after) / 2) / row[REC].after,
    });
    std.debug.print("     and the gain DECOMPOSES: the wider eligible pool alone takes the ring's {d:.5} to {d:.5}/{d:.5} ({d:.0}%), and error weighting adds the rest ({d:.0}% of what is left)\n", .{
        row[REC].after,                                                               row[U2].after,                                                                                                          row[4].after,
        100 * (row[REC].after - (row[U2].after + row[4].after) / 2) / row[REC].after, 100 * ((row[U2].after + row[4].after) / 2 - (row[E2].after + row[6].after) / 2) / ((row[U2].after + row[4].after) / 2),
    });
    std.debug.print("     NOT resource-matched against the ring: both hard arms retain W = {d} observations plus the selected {d}-slot buffer, and scan the pool at selection time. Against EACH OTHER they are matched exactly\n", .{ CLEAN, N });
}

test "G68 targeted re-observation: can you pay to consolidate early?" {
    // OBS-19 found a `t_min`: consolidating soon after a regime change was
    // destructive under every rule tested, because with M fresh observations
    // for N slots at least (N-M)/N of any buffer is stale by arithmetic.
    // OBS-20 fixed label validity by DISCARDING history, and Astra retired
    // the obvious way to get a wider valid pool: detecting the move deletes
    // those observations rather than relabelling them.
    //
    // The lever left is RE-OBSERVATION — spending a real observation to ask
    // again at a location the model CHOOSES. `observe(q, y)` has taken an
    // external exemplar since MARL-0; no phase had ever chosen q.
    //
    // **A RE-OBSERVATION IS AN OBSERVATION.** It pushes into the window and
    // evicts the oldest, exactly as a fresh draw does. The first version of
    // this gate instead mutated slots IN PLACE and advanced `Window.n`,
    // which retained 2 709 entries older than the cutoff, put 881 of them
    // into a sleep, and destroyed the `t % W == slot` mapping the ring
    // depends on. Astra measured all of it. Equal old-share is NOT equal
    // eligibility, and a green gate does not resolve a contract it never
    // asserts — so the contract is asserted here.
    //
    // With both modes pushing, eligibility is IDENTICAL BY CONSTRUCTION and
    // the only difference left is WHERE the budget's observations were
    // placed. That is the honest name for this phase: TARGETED versus
    // UNIFORM ACQUISITION.
    //
    // `tools/obs21_predict.py` is where the numbers were frozen.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const N: usize = 8192;
    const W: usize = 2 * N;
    const WAKE_A: u64 = 30_000;
    const M: u64 = 4_096;
    const BUDGET: usize = thresholds.OBS21_BUDGET;

    const world_a = marl.TruthParams{};
    var world_b = marl.TruthParams{};
    world_b.shift = .{ 0, -0.10, 0 };

    const ha = try marl.probesOf(gpa, world_a, 31337, 4096);
    const hb = try marl.probesOf(gpa, world_b, 31337, 4096);
    defer {
        gpa.free(ha.p);
        gpa.free(ha.y);
        gpa.free(hb.p);
        gpa.free(hb.y);
    }

    const Mode = enum { fresh, aimed, revisit };
    const modes = [_]Mode{ .fresh, .aimed, .revisit };
    const names = [_][]const u8{ "fresh", "aimed", "revisit" };
    // ACQUISITION is replicated, not only selection. Two whole lives per
    // mode, each with its own stream — Astra's point 3, and the two
    // sleep-time draws alone could never have spoken to it.
    const acq = [_]u64{ 1234, 5678 };
    const sel = [_]u64{ 0x33, 0x44 };

    std.debug.print("\n  G68 [{s}] W = 2N = {d}, budget {d} placed {d} observations after the move; {d} acquisitions x {d} selections per mode\n", .{
        @tagName(builtin.mode), W, BUDGET, M, acq.len, sel.len,
    });

    const Cell = struct { after: f64, lift: f64, held: f64, old: f64 };
    var cell: [modes.len][acq.len][sel.len]Cell = undefined;
    var hits: [modes.len][acq.len]usize = undefined;
    var post: [modes.len][acq.len]f64 = undefined;
    var parentk: [modes.len][acq.len]usize = undefined;
    var ref_after: [acq.len]f64 = undefined;
    var ref_before: [acq.len]f64 = undefined;
    var keep_of: [acq.len]usize = undefined;

    for (acq, 0..) |aseed, ai| {
        for (modes, 0..) |mode, mi| {
            // Every mode re-runs the whole life from this acquisition's
            // seeded stream, so all three reach the branch at a bit-identical
            // model. Cheaper and more honest than a deep clone.
            var m = try marl.Model.init(gpa, o);
            defer m.deinit();
            var win = try Window.init(gpa, W);
            defer win.deinit(gpa);
            var st = rng.Stream.region(aseed, 0x4f32_3152, 0); // "O21R"
            var none: [0]*Replay = .{};
            var wins = [_]*Window{&win};
            try wakeInto(&m, WAKE_A, &none, &wins, &st);
            m.opts.truth = world_b;
            try wakeInto(&m, M, &none, &wins, &st);
            const before = try m.rms(hb.p, hb.y, null);

            // **k is fixed at the BRANCH POINT**, so every mode consolidates
            // to the same number of kernels. The first version took k from
            // each mode's own post-budget population and delivered 344 / 346
            // / 343 — unequal k, which is OBS-18's mistake in a new costume.
            if (mi == 0) {
                keep_of[ai] = m.kernels.items.len / 2;
                ref_before[ai] = before;
                var ref = try Replay.initWith(gpa, N, .err, sel[0]);
                defer ref.deinit(gpa);
                win.selectInto(&ref);
                var rc = try sleepOn(gpa, &m, ref.x[0..N], ref.y[0..N], keep_of[ai], .{ .exact = true });
                defer rc.deinit();
                rc.opts.truth = world_b;
                ref_after[ai] = try rc.rms(hb.p, hb.y, null);
                std.debug.print("     acq {d}: branch model {d} kernels, k = {d}, before {d:.5}; NO-BUDGET reference sleeps to {d:.5}, lift {d:.4}\n", .{
                    aseed, m.kernels.items.len, keep_of[ai], before, ref_after[ai], 1 - ref_after[ai] / before,
                });
            } else {
                try testing.expectEqual(ref_before[ai], before);
            }

            // ── SPEND THE BUDGET. Three placements, one arithmetic.
            var chosen = try gpa.alloc(usize, W);
            defer gpa.free(chosen);
            var nh: usize = 0;
            switch (mode) {
                .fresh => try wakeInto(&m, BUDGET, &none, &wins, &st),
                .aimed, .revisit => {
                    for (0..W) |i| chosen[i] = i;
                    if (mode == .aimed) {
                        // Highest stored surprise, over the WHOLE window.
                        // **No staleness filter** — an earlier version chose
                        // among slots with `t < WAKE_A`, which is the known
                        // change boundary and therefore an oracle. Astra's
                        // point 4. A deployable policy does not know when the
                        // world moved.
                        std.mem.sort(usize, chosen, win.s, struct {
                            fn lt(sv: []const f32, x: usize, y: usize) bool {
                                return sv[x] > sv[y];
                            }
                        }.lt);
                    } else {
                        var sh = rng.Stream.region(aseed ^ 0x5245_5649, 0x5256_5354, 0);
                        var i: usize = W;
                        while (i > 1) {
                            i -= 1;
                            const j: usize = @intFromFloat(@as(f64, sh.unit()) * @as(f64, @floatFromInt(i + 1)));
                            std.mem.swap(usize, &chosen[i], &chosen[@min(j, i)]);
                        }
                    }
                    // The locations are read BEFORE any pushing, because
                    // pushing overwrites the ring underneath them.
                    const pts = try gpa.alloc([3]f32, BUDGET);
                    defer gpa.free(pts);
                    for (chosen[0..BUDGET], 0..) |i, k| pts[k] = win.x[i];
                    for (pts) |q| {
                        const ya: f64 = marl.truthOf(world_a, q);
                        const yb: f64 = marl.truthOf(world_b, q);
                        // Did this observation land where the worlds
                        // disagree? Over nine tenths of the cube they agree,
                        // so most of any buffer is not misleading at all, and
                        // how many of the budget's shots land on the tenth
                        // that is IS the aiming question.
                        if (@abs(ya - yb) > 1e-3) nh += 1;
                        const ev = try m.observe(q, .{@as(f32, @floatCast(yb))});
                        win.push(q, yb, ev.surprise, ev.cover);
                    }
                },
            }
            hits[mi][ai] = nh;
            parentk[mi][ai] = m.kernels.items.len;
            post[mi][ai] = try m.rms(hb.p, hb.y, null);

            // ── THE CONTRACT, asserted. Every slot inside the window, and
            // the ring's own mapping intact. This is what the first version
            // never checked and silently violated.
            const cut = win.n - @as(u64, W);
            for (win.t[0..W], 0..) |ti, i| {
                try testing.expect(ti >= cut);
                try testing.expectEqual(i, @as(usize, @intCast(ti % @as(u64, W))));
            }
            try testing.expect(@abs(win.oldShare(WAKE_A) - 0.5) < 1e-12);

            for (sel, 0..) |sd, si| {
                var buf = try Replay.initWith(gpa, N, .err, sd);
                defer buf.deinit(gpa);
                win.selectInto(&buf);
                try (Measures{ .fit = buf.x[0..N], .sleep = buf.x[0..N], .eval = hb.p }).check();
                var child = try sleepOn(gpa, &m, buf.x[0..N], buf.y[0..N], keep_of[ai], .{ .exact = true });
                defer child.deinit();
                child.opts.truth = world_b;
                const after = try child.rms(hb.p, hb.y, null);
                cell[mi][ai][si] = .{
                    .after = after,
                    .lift = 1 - @as(f64, after) / @as(f64, post[mi][ai]),
                    .held = try child.rms(ha.p, ha.y, null),
                    .old = buf.oldShare(WAKE_A),
                };
                try testing.expectEqual(keep_of[ai], child.kernels.items.len);
            }
            std.debug.print("       {s:<8} acq {d}  parent {d}k  hits {d:>5}/{d}  budget alone {d:.5}  after {d:.5}/{d:.5}  LIFT {d:.4}/{d:.4}  buffer-old {d:.3}\n", .{
                names[mi],             aseed,                 parentk[mi][ai],      nh,                   BUDGET,              post[mi][ai],
                cell[mi][ai][0].after, cell[mi][ai][1].after, cell[mi][ai][0].lift, cell[mi][ai][1].lift, cell[mi][ai][0].old,
            });
        }
    }

    // Two spreads, reported apart: ACQUISITION varies the whole life, and
    // SELECTION varies only the sleep's draw. Pooling them would assume they
    // are the same kind of variability and they are not.
    const meanOf = struct {
        fn go(c: [2][2]Cell) f64 {
            return (c[0][0].after + c[0][1].after + c[1][0].after + c[1][1].after) / 4;
        }
    }.go;
    const acqSpread = struct {
        fn go(c: [2][2]Cell) f64 {
            return @abs((c[0][0].after + c[0][1].after) / 2 - (c[1][0].after + c[1][1].after) / 2);
        }
    }.go;
    const selSpread = struct {
        fn go(c: [2][2]Cell) f64 {
            return @max(@abs(c[0][0].after - c[0][1].after), @abs(c[1][0].after - c[1][1].after));
        }
    }.go;

    std.debug.print("     mean after / ACQUISITION spread / SELECTION spread (DESCRIPTIVE, two draws each — not confidence bounds):\n", .{});
    for (modes, 0..) |_, mi| {
        std.debug.print("       {s:<8} {d:.5}   acq {d:.5}   sel {d:.5}   hits {d}/{d}   parent kernels {d}/{d}\n", .{
            names[mi],   meanOf(cell[mi]), acqSpread(cell[mi]), selSpread(cell[mi]),
            hits[mi][0], hits[mi][1],      parentk[mi][0],      parentk[mi][1],
        });
    }

    // ── THE CONTRACT, restated as the premise it is.
    std.debug.print("     the window contract HOLDS in every arm: no entry older than n - W, and t %% W == slot throughout; every mode at 0.500 pre-move by construction, not by coincidence\n", .{});

    // ── AIMING. Only ~0.094 of this cube is contested, so an untargeted
    // budget lands on that share of it and no more — the fixture's geometry,
    // not a tuning constant.
    try testing.expect(@abs(@as(f64, @floatFromInt(hits[2][0])) - thresholds.OBS21_UNAIMED_HITS) < 150);
    try testing.expect(hits[1][0] > 2 * hits[2][0]);
    try testing.expect(hits[1][1] > 2 * hits[2][1]);

    // ── THE HEADLINE, against BOTH uniform alternatives, clearing the worse
    // of the two spreads involved. `fresh` is the incumbent — it is simply
    // "keep observing" — and `revisit` isolates TARGETING from RE-ASKING.
    const worst = struct {
        fn go(a: [2][2]Cell, b: [2][2]Cell) f64 {
            return @max(@max(acqSpread(a), selSpread(a)), @max(acqSpread(b), selSpread(b)));
        }
    }.go;
    try testing.expect(meanOf(cell[1]) < meanOf(cell[0]) - worst(cell[1], cell[0]));
    try testing.expect(meanOf(cell[1]) < meanOf(cell[2]) - worst(cell[1], cell[2]));

    // ── THE t_min QUESTION, on LIFT: the budget improves the model by
    // itself, and crediting the sleep with that would answer a different
    // question.
    var lift_aimed: f64 = 0;
    for (0..acq.len) |i| for (0..sel.len) |j| {
        lift_aimed += cell[1][i][j].lift / 4;
    };
    var lift_fresh: f64 = 0;
    for (0..acq.len) |i| for (0..sel.len) |j| {
        lift_fresh += cell[0][i][j].lift / 4;
    };
    std.debug.print("     the no-budget reference sleeps DESTRUCTIVELY at {d:.4}/{d:.4} — OBS-19's situation QUALITATIVELY, not its numerical checkpoint; with a budget the sleep's own lift is fresh {d:.4}, aimed {d:.4}\n", .{
        1 - ref_after[0] / ref_before[0], 1 - ref_after[1] / ref_before[1], lift_fresh, lift_aimed,
    });
    for (0..acq.len) |i| try testing.expect(1 - ref_after[i] / ref_before[i] < 0);
    try testing.expect(lift_aimed > 0);

    // ── WHAT IS NOT CLAIMED, and it was claimed once.
    //
    // The first version reported that the budget "re-prioritises as well as
    // repairs, and the two compound" — from a selected-buffer old-share of
    // 0.312 against the other arms' ~0.474. Astra froze the acquired model,
    // labels, timestamps and selection seeds and restored the ORIGINAL
    // scores: the share went to 0.276, LOWER. Rescoring does not produce the
    // effect; targeting entries that already carried high weight does, and
    // rescoring partly OFFSETS it. The claim is withdrawn.
    //
    // Under these corrected semantics nothing is rescored in place at all —
    // a re-observed location simply appears twice until the older entry ages
    // out — so the question dissolves rather than being answered.
    std.debug.print("     NOT claimed: no compounding of repair with reprioritisation. Under push semantics nothing is rescored in place; the earlier claim was refuted by a frozen-score control (.312 -> .276, the wrong way) before it was retired by this fix\n", .{});

    // ── AND WHAT REMAINS CONFOUNDED. Equal observations and equal k; NOT
    // equal parent populations, because a budget placed differently births
    // differently. This is an end-to-end query-budget comparison, and it is
    // not a fixed-compute or fixed-representation one.
    std.debug.print("     STILL CONFOUNDED: observations and k are matched, parent populations are not ({d}/{d}/{d} at acq {d}) — a query-budget comparison, not fixed-compute or fixed-representation\n", .{
        parentk[0][0], parentk[1][0], parentk[2][0], acq[0],
    });
    // And the correction's COST is not attributable. Fixing this gate reduced
    // mean aimed lift from about +0.39 to +0.079, but it changed FIVE things
    // at once — the ring semantics, a fixed k, the removal of a
    // change-boundary oracle, the candidate population targeting draws from,
    // and a second acquisition trajectory. Blaming the expired entries for
    // most of that would need a matched ablation, which was not run. An
    // earlier write-up did blame them; Astra caught it.
    std.debug.print("     the correction reduced mean aimed lift from ~+0.39 to {d:.4}, but FIVE things changed at once — ring semantics, fixed k, the removal of a change-boundary oracle, the candidate population, and a second trajectory. No part of that reduction is attributed without a matched ablation\n", .{lift_aimed});
    // The acquisition spread varies the WHOLE LIFE including the branch
    // model, so it captures variability that selection-only replication
    // misses and is NOT acquisition-stage randomness isolated at a fixed
    // parent. Reported as what it is.
    std.debug.print("     the ACQUISITION spread varies the whole life including the branch model — it catches what selection-only replication misses, and is not acquisition randomness at a FIXED parent\n", .{});
}

test "G69 (a) the trajectory controller's contracts, driven with a sleep stub" {
    // **Astra's build order, and OBS-21's lesson applied before the fact:**
    // build the cheap structural checks first. But the FIRST draft of this
    // gate tested the `Trigger` in isolation and called it done — it proved
    // arithmetic and isolated behaviour, not the contracts the trajectory
    // RUNNER has to enforce. Astra's four objections, each fixed here:
    //
    //   * setting `busy` and checking `seen` cannot catch a controller that
    //     routes acquisition queries into the detector — no query was ever
    //     sent through any routing path.
    //   * interpolating the world INSIDE the test verifies the formula, not
    //     that the runner calls the shared one at each paid query.
    //   * `used*R + (TOTAL - used*R) == TOTAL` is an identity. It cannot
    //     catch a double-counted query, a skipped checkpoint, or an
    //     intervention overrunning the horizon.
    //   * refusing to fire at `thresh == 0` proves readiness, not that
    //     evaluation never recalibrates.
    //
    // So every assertion below drives `runArm` itself with `do_sleep =
    // false`: the real clock, the real routing, the real budget accounting,
    // with the one expensive call stubbed out. Seconds.
    //
    // The constants are small ON PURPOSE — this gate tests CONTROL FLOW, and
    // the expensive gate uses the registered ones.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 2;
    o.responsibility = 3;
    const bounds = [_]u64{ 2_000, 5_000, 6_500, 7_000, 10_000, 12_000 };
    const c = Traj{
        .total = 12_000,
        .r = 1_000,
        .w = 2_000,
        .n = 1_000,
        .check = 500,
        .cold_end = 2_000,
        .change_at = 5_000,
        .drift_lo = 7_000,
        .drift_hi = 10_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 512);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }

    std.debug.print("\n  G69 (a) [{s}] driving the REAL controller with a sleep stub; {d} observations, r = {d}, w = {d}\n", .{
        @tagName(builtin.mode), c.total, c.r, c.w,
    });

    const run = struct {
        fn go(g: std.mem.Allocator, oo: marl.Options, cc: Traj, plan: Plan, thresh: f64, ws: [3]marl.TruthParams, pp: [][3]f32) !struct { t: Tally, tr: Trigger } {
            // Half-lives scaled to this cheap horizon in the same ratio as
            // the registered 2048/16384 over 104 000, so the dynamics are
            // analogous rather than merely the same numbers on a tenth of
            // the trajectory.
            var trig = Trigger.init(256, 2048, cc.budget);
            trig.thresh = thresh;
            var out = Tally{};
            var st = rng.Stream.region(4242, 0x4f32_3254, 0); // "O22T"
            try runArm(g, oo, cc, plan, &trig, ws, pp, false, &st, &out, .{}, .{}, null);
            return .{ .t = out, .tr = trig };
        }
    }.go;

    // ── SCENARIO 1: NEVER. The whole horizon spent observing, no
    // interventions, no sleeps — and every paid observation monitored.
    {
        const r1 = try run(gpa, o, c, .never, 0, worlds, pr.p);
        try testing.expectEqual(c.total, r1.t.paid);
        try testing.expectEqual(c.total, r1.t.monitored);
        try testing.expectEqual(@as(u64, 0), r1.t.revisits);
        try testing.expectEqual(@as(usize, 0), r1.t.started);
        try testing.expectEqual(@as(usize, 0), r1.t.sleeps);
        try testing.expectEqual(@as(usize, @intCast(c.total / c.check)), r1.t.checks);
        std.debug.print("     never:    paid {d} = monitored {d}, revisits {d}, checks {d}\n", .{
            r1.t.paid, r1.t.monitored, r1.t.revisits, r1.t.checks,
        });
    }

    // ── SCENARIO 2: THE HORIZON, and the query accounting that an identity
    // could not check. Paid must equal the horizon EXACTLY however many
    // interventions ran, monitored + revisits must equal paid, and revisits
    // must be exactly r per started intervention.
    //
    // **This is the check that catches a double-counted query or an
    // intervention overrunning the horizon**, neither of which the first
    // draft could have seen.
    {
        const times = [_]u64{ 3_000, 6_000, 8_500 };
        const r2 = try run(gpa, o, c, .{ .at = &times }, 0, worlds, pr.p);
        try testing.expectEqual(c.total, r2.t.paid);
        try testing.expectEqual(c.total, r2.t.monitored + r2.t.revisits);
        try testing.expectEqual(@as(usize, 3), r2.t.started);
        try testing.expectEqual(@as(u64, 3 * c.r), r2.t.revisits);
        // The detector saw NONE of the revisits — the routing contract,
        // exercised by actually sending them through the controller.
        try testing.expectEqual(c.total - 3 * @as(u64, c.r), r2.t.monitored);
        // Checkpoints are on the GLOBAL clock, so an intervention spanning
        // them does not skip any: 1000 queries at check = 500 crosses two.
        try testing.expectEqual(@as(usize, @intCast(c.total / c.check)), r2.t.checks);
        std.debug.print("     schedule: paid {d}, monitored {d} + revisits {d}, started {d}, checks {d} (an intervention spans {d} of them)\n", .{
            r2.t.paid, r2.t.monitored, r2.t.revisits, r2.t.started, r2.t.checks, c.r / c.check,
        });
    }

    // ── SCENARIO 3: THE HORIZON EDGE. An intervention that cannot finish
    // must never start, and must never be charged.
    {
        const late = [_]u64{c.total - 10};
        const r3 = try run(gpa, o, c, .{ .at = &late }, 0, worlds, pr.p);
        try testing.expectEqual(c.total, r3.t.paid);
        try testing.expectEqual(@as(usize, 0), r3.t.started);
        try testing.expect(r3.t.horizon_blocked > 0);
        std.debug.print("     near-horizon: an intervention needing {d} queries at t = {d} is BLOCKED, not truncated ({d} refusals, 0 started)\n", .{
            c.r, late[0], r3.t.horizon_blocked,
        });
    }

    // ── SCENARIO 4: READINESS. A crossing before the window is full cannot
    // become an intervention — and is COUNTED, so a cold-start prediction is
    // tested on the STATISTIC rather than on whatever gate happens to
    // suppress it. A threshold of 0.5 is below the neutral ratio of 1, so it
    // crosses immediately and permanently: exactly the pathology Astra
    // warned a low calibrated threshold would produce.
    //
    // **An unready request is DEFERRED, not discarded** — it is re-evaluated
    // every step and runs once the window fills, so a schedule cannot lose an
    // intervention to an accident of timing and a trigger re-crosses
    // naturally. The rule was not stated in the first draft and this
    // scenario is what forced it to be: the assertion originally said the
    // intervention never happens, and the controller was right.
    {
        const eager = [_]u64{0};
        const r4 = try run(gpa, o, c, .{ .at = &eager }, 0, worlds, pr.p);
        try testing.expectEqual(@as(usize, 1), r4.t.started);
        try testing.expectEqual(@as(usize, @intCast(c.w)), r4.t.unready);
        try testing.expectEqual(@as(u64, c.w), r4.t.fired_at[0]);
        var trig = Trigger.init(2048, 16384, c.budget);
        trig.thresh = 0.5;
        _ = trig.monitor(0.25);
        try testing.expect(trig.crosses()); // a threshold under 1 fires on the seed itself
        std.debug.print("     readiness: a request at t = 0 is refused {d} times on an unfilled window and DEFERRED to t = {d}, not lost; and a calibrated threshold BELOW 1 crosses on the seed — reported, never clamped\n", .{ r4.t.unready, r4.t.fired_at[0] });
    }

    // ── SCENARIO 5: MAXIMUM FIRINGS, and the budget as a ceiling rather
    // than a promise. A threshold just above the neutral ratio makes the
    // trigger want to fire constantly; it must still stop at `budget`, and
    // the cooldown must be spent in MONITORING observations.
    //
    // A DEGENERATE threshold of 0.5 is used deliberately: it sits below the
    // neutral ratio of 1, so the detector wants to fire constantly. That is
    // the pathology a calibrated threshold under 1 would produce, and it is
    // exactly the case in which the ceiling has to hold.
    {
        const r5 = try run(gpa, o, c, .trigger, 0.5, worlds, pr.p);
        try testing.expectEqual(c.total, r5.t.paid);
        try testing.expectEqual(c.total, r5.t.monitored + r5.t.revisits);
        try testing.expectEqual(c.budget, r5.t.started);
        try testing.expectEqual(r5.t.started, r5.tr.fired);
        try testing.expect(r5.t.crossings >= r5.t.started);
        try testing.expectEqual(@as(u64, r5.t.started) * @as(u64, c.r), r5.t.revisits);
        std.debug.print("     ceiling:  a DEGENERATE threshold of 0.5 crosses {d} times and still starts exactly {d}; revisits {d}, budget at drift {d}\n", .{
            r5.t.crossings, r5.t.started, r5.t.revisits, r5.t.budget_at_drift,
        });
    }

    // ── SCENARIO 5b: AND THE COLD-START RESTRAINT, as a measurement rather
    // than a hope. During learning the fast EWMA falls FASTER than the slow,
    // so the ratio sits BELOW one and a threshold above one cannot fire. The
    // statistic is doing what it was designed for, and this is the cheapest
    // possible evidence of it — no calibration, no sleeps.
    //
    // **Asked of the STATISTIC, not of the executions.** The window must be
    // full before any intervention can run, so in this config nothing can
    // execute before t = 2000 and in the registered one nothing can execute
    // before 16 384 — later than the whole cold start. A restraint claim
    // tested on executions would therefore be vacuous whatever the detector
    // did. What is asserted is that it never wanted to.
    {
        const r6 = try run(gpa, o, c, .trigger, 1.0001, worlds, pr.p);
        try testing.expectEqual(c.total, r6.t.paid);
        try testing.expectEqual(@as(usize, 0), r6.t.crossings_cold);
        try testing.expect(r6.t.first_cross >= c.change_at);
        std.debug.print("     restraint: {d} crossings in the COLD START (t < {d}) and {d} in the settled stretch that follows; first at t = {d}. A TOY CONFIG — scaled half-lives, threshold 1.0001, change at {d} — so it exercises the statistic, it does not establish Q2 under the frozen threshold on the registered trajectory\n", .{
            r6.t.crossings_cold, c.cold_end, r6.t.crossings_settled, r6.t.first_cross, c.change_at,
        });
    }

    // ── SCENARIO 8: THE REGISTERED EVENT ORDER — observation, then the
    // completed intervention's SLEEP, then the SCORE. A checkpoint landing
    // on an intervention's last query must be DEFERRED past the
    // consolidation, or it reports a model that is about to be replaced.
    //
    // `do_sleep = false` cannot reveal this by outcome, because there is no
    // replacement to see. The sleep EVENT is emitted either way and the
    // order is asserted directly. Astra found the bug by reading the loop;
    // this is what would have caught it.
    {
        // r = 1000 and check = 500 divide, so every intervention's last
        // query lands exactly on a checkpoint. The worst case, chosen.
        const times = [_]u64{ 3_000, 6_000, 8_500 };
        const r8 = try run(gpa, o, c, .{ .at = &times }, 0, worlds, pr.p);
        var seen_sleep: usize = 0;
        var coincident: usize = 0;
        for (r8.t.trace[0..r8.t.ntrace], 0..) |e, k| {
            if (e.kind != .sleep) continue;
            seen_sleep += 1;
            // the very next event at the SAME index must be the check
            if (k + 1 < r8.t.ntrace and r8.t.trace[k + 1].kind == .check and r8.t.trace[k + 1].at == e.at) coincident += 1;
            // and no check at this index may PRECEDE the sleep
            for (r8.t.trace[0..k]) |q| try testing.expect(!(q.kind == .check and q.at == e.at));
        }
        try testing.expectEqual(@as(usize, 3), seen_sleep);
        try testing.expectEqual(@as(usize, 3), coincident);
        std.debug.print("     ordering: {d} interventions whose last query lands ON a checkpoint; in every one the SLEEP precedes the SCORE at that index\n", .{coincident});
    }

    // ── SCENARIO 9: THE DRIFT SNAPSHOT, on an arm that never touches the
    // trigger. It was previously taken from `trig.fired`, which a scheduled
    // plan never increments, so every such arm reported its full budget
    // however many interventions it had already run — and it was written
    // only in the monitoring branch, so an intervention spanning drift onset
    // skipped it entirely. Both fixed; both asserted here.
    {
        // Two interventions complete before drift onset at 7000; a third
        // starts at 6900 and SPANS it.
        const early = [_]u64{ 2_500, 4_000, 6_900 };
        const r9 = try run(gpa, o, c, .{ .at = &early }, 0, worlds, pr.p);
        try testing.expectEqual(@as(usize, 3), r9.t.started);
        // At the first index >= drift_lo, three had started, so none remain.
        try testing.expectEqual(@as(usize, 0), r9.t.budget_at_drift);
        try testing.expect(r9.t.drift_marked);
        std.debug.print("     drift snapshot: {d} interventions started before onset (one SPANNING it), budget remaining {d} — taken on the common clock from interventions STARTED, not from a trigger the arm never uses\n", .{
            r9.t.started, r9.t.budget_at_drift,
        });
    }

    // ── SCENARIO 10: THE THRESHOLD IS NOT TOUCHED BY EVALUATION. The
    // degenerate-threshold scenario proves the budget ceiling; it says
    // nothing about whether a run recalibrates. Asserted separately.
    {
        const r10 = try run(gpa, o, c, .trigger, 0.5, worlds, pr.p);
        try testing.expectEqual(@as(f64, 0.5), r10.tr.thresh);
        std.debug.print("     calibration: the supplied threshold is {d:.4} after a full evaluation run — unchanged, and never re-derived from evaluation data\n", .{r10.tr.thresh});
    }

    // ── SCENARIO 11: THE REPORTING PATHS the expensive gate will use, run
    // cheaply so that a segmentation bug is not discovered nine minutes in.
    {
        const times = [_]u64{ 3_000, 6_000, 8_500 };
        const r11 = try run(gpa, o, c, .{ .at = &times }, 0, worlds, pr.p);
        var seg: usize = 0;
        for (r11.t.checks_phase) |n| seg += n;
        try testing.expectEqual(r11.t.checks, seg);
        try testing.expect(r11.t.meanTail(bounds.len) > 0);
        var posted: usize = 0;
        for (r11.t.post_n[0..r11.t.started]) |n| {
            if (n > 0) posted += 1;
        }
        try testing.expectEqual(r11.t.started, posted);
        std.debug.print("     reporting: {d} checkpoints segment exactly across {d} phases; drift+tail mean {d:.5}; every one of {d} interventions has post-intervention error recorded\n", .{
            r11.t.checks, bounds.len, r11.t.meanTail(bounds.len), posted,
        });
    }

    // ── SCENARIO 6: THE WORLD IS THE RUNNER'S, NOT THE TEST'S. `worldAt` is
    // the single definition both use, so a controller that interpolated
    // privately would be caught here rather than proving its own formula
    // self-consistent.
    {
        try testing.expectEqual(wa.shift, worldAt(c, c.change_at - 1, wa, wb, wc).shift);
        try testing.expectEqual(wb.shift, worldAt(c, c.drift_lo, wa, wb, wc).shift);
        try testing.expectEqual(wc.shift, worldAt(c, c.drift_hi, wa, wb, wc).shift);
        const s0 = worldAt(c, c.drift_lo + 100, wa, wb, wc);
        const s1 = worldAt(c, c.drift_lo + 100 + c.r, wa, wb, wc);
        var moved: f32 = 0;
        inline for (0..3) |k| moved += @abs(s1.shift[k] - s0.shift[k]);
        try testing.expect(moved > 0);
        std.debug.print("     clock:    the world moves {d:.5} in shift across one intervention's {d} queries — the drift does not wait\n", .{ moved, c.r });
    }

    // ── SCENARIO 7: THE ZERO-SURPRISE START, which the first draft's
    // seeding contract did not survive. This fixture HAS an exactly-zero
    // region, so `0, 0, positive` is a real history and must not reopen the
    // manufactured alarm.
    {
        var t = Trigger.init(2048, 16384, c.budget);
        try testing.expectEqual(@as(f64, 1), t.monitor(0));
        try testing.expectEqual(@as(f64, 1), t.monitor(0));
        try testing.expect(!t.started);
        const after = t.monitor(0.4);
        try testing.expectEqual(@as(f64, 1), after);
        try testing.expect(t.started);
        try testing.expectEqual(@as(u64, 3), t.seen);
        const manufactured = t.af / t.as_;
        std.debug.print("     zero-start: 0, 0, positive opens at {d:.2}, not the {d:.2} that zero-init manufactures\n", .{ after, manufactured });
    }
}

test "G69 when is intervention worth its cost?" {
    // Every phase from OBS-18 to OBS-21 assumed someone said when the world
    // moved. OBS-19 chose its offsets, OBS-20 set its cutoff, OBS-21 spent
    // its budget — all because the experiment said so. This is the first
    // where the policy has to decide.
    //
    // Astra's framing, which replaced the one this phase nearly got built
    // on: **"when is intervention worth its cost?" rather than "detect the
    // change."** Surprise also rises because a model is undertrained. And
    // detection is ill-posed during the drift by construction — there is no
    // instant to name.
    //
    // `tools/obs22_predict.py` holds the registration, including the three
    // contract bugs its first draft had. G69 (a) holds the controller's
    // contracts and runs in seconds; this is the expensive comparison, and
    // it runs once.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const H_FAST: f64 = 2048;
    const H_SLOW: f64 = 16384;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 2048);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }

    // ── CALIBRATION, on its own trajectory, frozen before anything is
    // scored. Printed rather than clamped: a threshold below 1 would fire on
    // the neutral seed itself, and that is a finding, not something to fix
    // quietly.
    const cal = try calibrate(gpa, o, c, worlds, H_FAST, H_SLOW, 0x0CA1, c.cold_end, c.change_at);
    std.debug.print("\n  G69 [{s}] calibration on seed 0x0CA1, stationary {d}..{d}: ratio mean {d:.5}, population sd {d:.5} over {d} samples -> THRESHOLD {d:.5}\n", .{
        @tagName(builtin.mode), c.cold_end, c.change_at, cal.mean, cal.sd, cal.n, cal.thresh,
    });
    if (cal.thresh < 1) std.debug.print("     WARNING: the frozen threshold is BELOW 1, so the neutral seeded ratio crosses it. Reported, not clamped.\n", .{});

    const sched = [_]u64{ 26_000, 52_000, 78_000 };
    const informed = [_]u64{ 30_000, 60_000, 90_000 };
    const names = [_][]const u8{ "trigger", "schedule", "informed", "none" };
    const acq = [_]u64{ 1234, 5678 };

    var tal: [4][acq.len]Tally = undefined;
    for (acq, 0..) |aseed, ai| {
        for (0..4) |mi| {
            const plan: Plan = switch (mi) {
                0 => .trigger,
                1 => .{ .at = &sched },
                2 => .{ .at = &informed },
                else => .never,
            };
            var trig = Trigger.init(H_FAST, H_SLOW, c.budget);
            trig.thresh = cal.thresh;
            var out = Tally{};
            var st = rng.Stream.region(aseed, 0x4f32_3254, 0); // "O22T"
            try runArm(gpa, o, c, plan, &trig, worlds, pr.p, true, &st, &out, .{}, .{}, null);
            tal[mi][ai] = out;
            // The contracts G69 (a) proves cheaply, re-asserted on the real
            // configuration — they are premises, not conveniences.
            try testing.expectEqual(c.total, out.paid);
            try testing.expectEqual(c.total, out.monitored + out.revisits);
            try testing.expect(out.started <= c.budget);
            try testing.expectEqual(@as(u64, out.started) * @as(u64, c.r), out.revisits);
            std.debug.print("     {s:<9} acq {d}  started {d} (of at most {d})  sleeps {d}  above-threshold ticks {d} (cold {d}, settled {d})  first {d}  unready {d}  blocked {d}  budget@drift {d}  fired {any}\n", .{
                names[mi],           aseed,               out.started,                  c.budget,        out.sleeps,
                out.crossings,       out.crossings_cold,  out.crossings_settled,        out.first_cross, out.unready,
                out.horizon_blocked, out.budget_at_drift, out.fired_at[0..out.started],
            });
        }
    }

    const avg = struct {
        fn whole(t: [acq.len]Tally) f64 {
            return (t[0].mean() + t[1].mean()) / 2;
        }
        fn tail(t: [acq.len]Tally, nph: usize) f64 {
            return (t[0].meanTail(nph) + t[1].meanTail(nph)) / 2;
        }
        fn spread(t: [acq.len]Tally) f64 {
            return @abs(t[0].mean() - t[1].mean());
        }
        /// **The spread on the drift-and-tail objective itself.** Judging a
        /// drift-and-tail margin against whole-trajectory spread compares a
        /// difference to the variability of a different quantity. Astra's
        /// correction; an earlier draft did exactly that.
        fn tailSpread(t: [acq.len]Tally, nph: usize) f64 {
            return @abs(t[0].meanTail(nph) - t[1].meanTail(nph));
        }
    };
    std.debug.print("     TIME-AVERAGED ERROR (mean RMS over checkpoints, not pooled MSE):\n", .{});
    for (names, 0..) |nm, mi| {
        std.debug.print("       {s:<9} whole {d:.5} ({d:.5} / {d:.5}, spread {d:.5})   drift+tail {d:.5} ({d:.5} / {d:.5}, spread {d:.5})\n", .{
            nm,                            avg.whole(tal[mi]),              tal[mi][0].mean(),               tal[mi][1].mean(),                   avg.spread(tal[mi]),
            avg.tail(tal[mi], bounds.len), tal[mi][0].meanTail(bounds.len), tal[mi][1].meanTail(bounds.len), avg.tailSpread(tal[mi], bounds.len),
        });
    }
    // **Both trajectories.** An earlier draft printed only `tal[mi][0]`, so
    // its reassuring post-intervention errors described the arm that behaved
    // and said nothing about the one that blew up. Astra caught it reading
    // the preserved log.
    std.debug.print("     INTERVENTIONS BY PHASE, and the error over the two checkpoints after each — REPORTED, never scored as false alarms:\n", .{});
    for (names, 0..) |nm, mi| {
        for (acq, 0..) |aseed, ai| {
            std.debug.print("       {s:<9} acq {d}", .{ nm, aseed });
            for (0..bounds.len) |ph| std.debug.print(" p{d}:{d}", .{ ph, tal[mi][ai].started_phase[ph] });
            std.debug.print("   post-intervention RMS:", .{});
            for (0..tal[mi][ai].started) |k| {
                const n = tal[mi][ai].post_n[k];
                std.debug.print(" {d:.5}", .{tal[mi][ai].post_err[k] / @as(f64, @floatFromInt(@max(1, n)))});
            }
            std.debug.print("\n", .{});
        }
    }

    // ── Q1, THE MATCH, already asserted per arm above.
    // ── Q2, REGISTERED AND REFUTED, and the refutation is what is asserted
    // so that a change of sign is caught.
    //
    // The prediction was that the detector never wants to fire during the
    // cold start. It holds on one acquisition trajectory and fails utterly
    // on the other: 0 above-threshold ticks against 11 917 of 12 000,
    // beginning at t = 83. **The restraint is not a property of the
    // statistic; it is a property of the draw.** G69 (c) traces both and
    // describes the difference — the seeds are 0.049409 and 0.006119, an
    // eightfold gap the slow EWMA carries for its own half-life — without
    // claiming the seeding rule as its cause, which needs a separate
    // diagnostic.
    var cold_min: usize = std.math.maxInt(usize);
    var cold_max: usize = 0;
    for (0..acq.len) |ai| {
        cold_min = @min(cold_min, tal[0][ai].crossings_cold);
        cold_max = @max(cold_max, tal[0][ai].crossings_cold);
    }
    std.debug.print("     Q2 AS REGISTERED: the detector never crosses during the cold start. REFUTED — {d} above-threshold ticks on one trajectory and {d} on the other, so the restraint is a property of the DRAW and not of the statistic.\n", .{ cold_min, cold_max });
    std.debug.print("     Nothing is asserted here about Q2. The regression check that these fixed trajectories still reproduce {d} against {d} lives in G69 (c), which reaches the same cold-start numbers in seconds and without a single sleep — and passing it would not mean Q2 holds.\n", .{ cold_min, cold_max });

    // ── Q6, ACTING BEATS NOT ACTING — and if an arm loses to `none`, that
    // says THAT placement failed to earn its cost on THIS trajectory, not
    // that OBS-21's conditional result falls.
    const none_w = avg.whole(tal[3]);
    const trig_w = avg.whole(tal[0]);
    const sched_w = avg.whole(tal[1]);
    const inf_w = avg.whole(tal[2]);
    std.debug.print("     Q5 the reference gap, signed: trigger - informed = {d:.5} (negative means the online policy BEAT the privileged schedule, which refutes THAT schedule and not the value of timing information)\n", .{trig_w - inf_w});
    std.debug.print("     Q6 against no intervention at all: trigger {d:.5}, schedule {d:.5}, informed {d:.5}, none {d:.5}\n", .{ trig_w, sched_w, inf_w, none_w });

    // ── Q4, THE DRIFT, with the budget remaining at onset printed above so
    // that a win there is not read as drift sensitivity when it may be the
    // consequence of earlier decisions.
    const worst = @max(avg.tailSpread(tal[0], bounds.len), avg.tailSpread(tal[1], bounds.len));
    std.debug.print("     Q4 drift+tail: trigger {d:.5} against schedule {d:.5}, margin {d:.5} against the worse DRIFT+TAIL acquisition spread {d:.5} (not the whole-trajectory spread, which judges a different quantity)\n", .{
        avg.tail(tal[0], bounds.len),                                avg.tail(tal[1], bounds.len),
        avg.tail(tal[1], bounds.len) - avg.tail(tal[0], bounds.len), worst,
    });
}

test "G69 (b) localising the schedule/5678 failure" {
    // **A diagnostic of the failed arm, not a replacement for the registered
    // experiment.** G69's `schedule` arm reached a time-averaged error of
    // 0.37240 on acquisition 5678 against 0.08658 on 1234 — a fourfold
    // blow-up carrying nearly all of that arm's spread. Astra's instruction:
    // buy LOCALISATION with the next expenditure, not another headline, and
    // diagnose before changing any policy.
    //
    // My "roughly one eighth of the capacity" was speculation. Regrowth has
    // to be counted, so the populations are recorded rather than assumed.
    //
    // And G69's own per-intervention table printed trajectory 1234 ONLY, so
    // the reassuring post-intervention errors there described the arm that
    // behaved. Astra caught that reading the preserved log.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 2048);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }
    const sched = [_]u64{ 26_000, 52_000, 78_000 };
    const SEED: u64 = 5678;

    std.debug.print("\n  G69 (b) [{s}] replaying schedule/{d} UNCHANGED, instrumented\n", .{ @tagName(builtin.mode), SEED });

    var diag = Diag{};
    var tal = Tally{};
    {
        var trig = Trigger.init(2048, 16384, c.budget);
        var st = rng.Stream.region(SEED, 0x4f32_3254, 0); // "O22T"
        try runArm(gpa, o, c, .{ .at = &sched }, &trig, worlds, pr.p, true, &st, &tal, .{ .diag = &diag }, .{}, null);
    }
    try testing.expectEqual(@as(usize, 3), diag.n);
    std.debug.print("     {s:>6} {s:>10} {s:>10} {s:>10} {s:>11} | {s:>7} {s:>7} {s:>7} | {s:>9} {s:>9}\n", .{
        "at", "RMS before", "FROZEN end", "after acq", "after sleep", "k before", "k after", "births", "replay pre", "replay post",
    });
    var worst: usize = 0;
    var worst_jump: f64 = 0;
    for (diag.steps[0..diag.n], 0..) |sx, k| {
        const jump = sx.rms_after_sleep - sx.rms_after_acq;
        if (jump > worst_jump) {
            worst_jump = jump;
            worst = k;
        }
        std.debug.print("     {d:>6} {d:>10.5} {d:>10.5} {d:>10.5} {d:>11.5} | {d:>7} {d:>7} {d:>7} | {d:>9.5} {d:>9.5}\n", .{
            sx.at,       sx.rms_before, sx.rms_frozen_end, sx.rms_after_acq, sx.rms_after_sleep,
            sx.k_before, sx.k_after,    sx.births_since,   sx.fit_first,     sx.fit_last,
        });
    }
    std.debug.print("     whole {d:.5}, drift+tail {d:.5}; the sleep that costs most is #{d} at t = {d}, which moves the world RMS {d:.5} -> {d:.5}\n", .{
        tal.mean(),                      tal.meanTail(bounds.len),          worst, diag.steps[worst].at,
        diag.steps[worst].rms_after_acq, diag.steps[worst].rms_after_sleep,
    });
    std.debug.print("     POPULATIONS, counted rather than assumed: ", .{});
    for (diag.steps[0..diag.n]) |sx| std.debug.print("{d}->{d} (+{d} born) ", .{ sx.k_before, sx.k_after, sx.births_since });
    std.debug.print("\n", .{});

    // ── THE FORK, at the sleep that costs most. Same acquisition, same
    // replay selection, same subsequent observations — only the
    // consolidation differs, so compression and refitting are separated.
    std.debug.print("     ACQUISITION, judged against the SAME world: the frozen pre-acquisition model at completion time, beside the acquired one.\n", .{});
    for (diag.steps[0..diag.n]) |sx| {
        std.debug.print("       t = {d:>6}  frozen {d:.5} -> acquired {d:.5}  ({s})\n", .{
            sx.at,                                                                                  sx.rms_frozen_end, sx.rms_after_acq,
            if (sx.rms_after_acq < sx.rms_frozen_end) "acquisition HELPED" else "acquisition hurt",
        });
    }

    const modes = [_]@TypeOf(@as(Probe, undefined).fork_mode){ .half, .skip, .norefine, .guarded, .relabel };
    const mnames = [_][]const u8{ "half (registered)", "skip (parent reference)", "norefine (linear only)", "guarded (reject a rise)", "relabel (oracle, a PROBE)" };
    var res: [5]Tally = undefined;
    var fdiag: [5]Diag = undefined;
    std.debug.print("     {s:<26} {s:>9} {s:>11} |{s:>12} {s:>12} {s:>12}\n", .{
        "fork", "whole", "drift+tail", "replay pre", "ATTEMPTED post", "world after",
    });
    for (modes, 0..) |md, k| {
        var trig = Trigger.init(2048, 16384, c.budget);
        var st = rng.Stream.region(SEED, 0x4f32_3254, 0);
        res[k] = Tally{};
        fdiag[k] = Diag{};
        try runArm(gpa, o, c, .{ .at = &sched }, &trig, worlds, pr.p, true, &st, &res[k], .{ .fork_at = worst, .fork_mode = md, .diag = &fdiag[k] }, .{}, null);
        const fs = fdiag[k].steps[worst];
        std.debug.print("     {s:<26} {d:>9.5} {d:>11.5} |{d:>12.5} {d:>12.5} {d:>12.5}{s}\n", .{
            mnames[k],                               res[k].mean(), res[k].meanTail(bounds.len),
            fs.fit_first,                            fs.fit_last,   fs.rms_after_sleep,
            if (fs.rejected) "  [REJECTED]" else "",
        });
    }
    // `half` must reproduce the unforked replay exactly — the fork harness
    // is only trustworthy if its null case is identical.
    try testing.expectEqual(tal.mean(), res[0].mean());
    std.debug.print("     WHAT EACH FORK SEPARATES: `norefine` keeps selection and the LINEAR refit and drops the descent, so a disastrous linear fit is\n", .{});
    std.debug.print("     distinguished from a disastrous refinement; `guarded` keeps the descent but rejects one ending non-finite or above its starting\n", .{});
    std.debug.print("     REPLAY loss — the objective the optimiser sees. Current-world probes are diagnostic and never enter the decision.\n", .{});
    std.debug.print("     the fork's null case reproduces the replay exactly ({d:.5}), so the two variants differ only in the consolidation\n", .{res[0].mean()});
}

test "G69 (c) tracing the detector across both trajectories" {
    // G69's trigger behaved completely differently on its two acquisition
    // trajectories: 0 above-threshold ticks on 1234, and 11 917 during the
    // cold start alone on 5678, beginning at t = 83. The detector's
    // behaviour is the phase's own subject, so this describes it.
    //
    // **A trace describes the failure; it does not establish seeding as the
    // cause.** Astra's constraint, and it shapes what this gate may claim:
    // the initial nonzero surprise, the two EWMAs and their ratio through
    // the cold start, and where the first crossing falls. Nothing here
    // changes an initialisation rule or evaluates a new trigger — feeding a
    // recorded surprise sequence through a different rule is a SEPARATE
    // diagnostic, and a new trigger policy is a separate experiment again.
    //
    // No sleeps. Seconds.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const H_FAST: f64 = 2048;
    const H_SLOW: f64 = 16384;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };

    const cal = try calibrate(gpa, o, c, worlds, H_FAST, H_SLOW, 0x0CA1, c.cold_end, c.change_at);
    std.debug.print("\n  G69 (c) [{s}] frozen threshold {d:.5} (mean {d:.5} + 3 x sd {d:.5}), from G69's own calibration seed\n", .{
        @tagName(builtin.mode), cal.thresh, cal.mean, cal.sd,
    });

    const UNTIL: u64 = 32_000; // through the cold start and past the step
    for ([_]u64{ 1234, 5678 }) |seed| {
        var m = try marl.Model.init(gpa, o);
        defer m.deinit();
        var trig = Trigger.init(H_FAST, H_SLOW, c.budget);
        trig.thresh = cal.thresh;
        var st = rng.Stream.region(seed, 0x4f32_3254, 0); // G69's stream exactly
        var seed_surprise: f32 = 0;
        var seed_at: u64 = 0;
        var first_cross: u64 = 0;
        var cold_ticks: usize = 0;
        var i: u64 = 0;
        std.debug.print("     ── acquisition {d}\n", .{seed});
        while (i < UNTIL) : (i += 1) {
            // **The controller evaluates `crosses()` at the TOP of its loop,
            // before the observation at this index.** Checking after the
            // observation puts every crossing one index early — which is how
            // an earlier draft of this trace reported 82 where G69's
            // preserved output says 83. The ordering is the contract, so the
            // trace follows it rather than resembling it.
            if (first_cross == 0 and trig.crosses()) first_cross = i;
            if (i < c.cold_end and trig.crosses()) cold_ticks += 1;
            const tp = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
            const q = [3]f32{ st.unit(), st.unit(), st.unit() };
            const v: f64 = marl.truthOf(tp, q);
            const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
            const was_started = trig.started;
            const r = trig.monitor(ev.surprise);
            if (!was_started and trig.started) {
                seed_surprise = ev.surprise;
                seed_at = i;
            }
            if (i < 400 and (i < 8 or i % 100 == 0)) {
                std.debug.print("        t {d:>5}  surprise {d:.6}  fast {d:.6}  slow {d:.6}  ratio {d:.4}{s}\n", .{
                    i, ev.surprise, trig.fast, trig.slow, r, if (r > cal.thresh) "  ABOVE" else "",
                });
            }
            if (i % 4_000 == 0 and i >= 400) {
                std.debug.print("        t {d:>5}  fast {d:.6}  slow {d:.6}  ratio {d:.4}{s}\n", .{
                    i, trig.fast, trig.slow, r, if (r > cal.thresh) "  ABOVE" else "",
                });
            }
        }
        std.debug.print("        SEEDED at t = {d} on surprise {d:.6}; first above-threshold tick {d}; cold-start ticks {d} of {d}\n", .{
            seed_at, seed_surprise, first_cross, cold_ticks, c.cold_end,
        });
        std.debug.print("        (the slow EWMA's half-life is {d} monitoring updates — the seed's contribution HALVES there and stays relevant after, it is not a cutoff)\n", .{@as(u64, @intFromFloat(H_SLOW))});
        // ── A POST-HOC REGRESSION CHECK, and NOT a test of registered Q2.
        //
        // Q2 predicted the detector never crosses during the cold start and
        // is REFUTED; that stands in `thresholds.zig` and in G69's own
        // output. What is asserted here is only that these two fixed
        // trajectories keep reproducing the numbers the refutation was read
        // from — 0 ticks on one and >10 000 on the other. **Passing this
        // does not mean Q2 holds.** Astra's distinction, and the reason the
        // check lives here: G69 (c) reaches the same cold-start behaviour in
        // seconds, before any intervention could execute, so validating an
        // assertion about it never needs a sleep.
        if (seed == 5678) {
            try testing.expectEqual(@as(u64, 83), first_cross);
            try testing.expect(cold_ticks > 10_000);
        } else {
            try testing.expectEqual(@as(u64, 0), first_cross);
            try testing.expectEqual(@as(usize, 0), cold_ticks);
        }
    }
    std.debug.print("     DESCRIBED, NOT DIAGNOSED: this says what the detector did on each trajectory. Whether the seeding rule CAUSED it needs the\n", .{});
    std.debug.print("     recorded surprise sequence replayed through a separately specified initialisation, threshold frozen — a later diagnostic.\n", .{});
}

test "G69 (d) the initialisation diagnostic, on a fixed surprise sequence" {
    // G69 (c) DESCRIBED the detector's two behaviours; it did not establish
    // a cause. This isolates one: **the identical recorded surprise sequence
    // is replayed through two initialisation rules with the threshold
    // frozen**, so nothing differs but the seeding. Astra's specification,
    // and the alternative was written into `tools/obs22_predict.py` before
    // any of it was measured.
    //
    //   RULE A  seed both EWMAs from the FIRST nonzero surprise. The
    //           incumbent, and a single draw.
    //   RULE B  seed both from the MEAN of the first 256 nonzero surprises.
    //           An estimate rather than a draw; 256 is well below the fast
    //           half-life of 2048 and far above 1.
    //
    // **The threshold stays frozen at rule A's calibration**, which is right
    // for isolating initialisation and wrong for evaluating a policy: rule B
    // changes the ratio's distribution and a deployed alternative would need
    // its own calibration. This is a diagnostic. A new trigger policy would
    // be a separate registered experiment.
    //
    // No sleeps. Seconds.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const H_FAST: f64 = 2048;
    const H_SLOW: f64 = 16384;
    const SEED_B: usize = 256;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };

    const cal = try calibrate(gpa, o, c, worlds, H_FAST, H_SLOW, 0x0CA1, c.cold_end, c.change_at);
    std.debug.print("\n  G69 (d) [{s}] threshold FROZEN at {d:.5} (rule A's calibration, on both rules)\n", .{
        @tagName(builtin.mode), cal.thresh,
    });

    // **Far enough past the change to see whether a quieter rule still
    // DETECTS it.** An earlier draft stopped at 32 000 — under one fast
    // half-life after the step — so it could report that rule B removed the
    // false alarms while saying nothing about whether it had also removed
    // the true one. 48 000 gives ~9 fast half-lives of post-change signal.
    const UNTIL: usize = 48_000;
    const seq = try gpa.alloc(f32, UNTIL);
    defer gpa.free(seq);

    for ([_]u64{ 1234, 5678 }) |seed| {
        // Record the sequence ONCE, from the same stream the controller uses.
        var m = try marl.Model.init(gpa, o);
        defer m.deinit();
        var st = rng.Stream.region(seed, 0x4f32_3254, 0);
        for (0..UNTIL) |i| {
            const tp = worldAt(c, @intCast(i), worlds[0], worlds[1], worlds[2]);
            const q = [3]f32{ st.unit(), st.unit(), st.unit() };
            const v: f64 = marl.truthOf(tp, q);
            const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
            seq[i] = ev.surprise;
        }

        std.debug.print("     ── acquisition {d}\n", .{seed});
        var ticks: [2]usize = .{ 0, 0 };
        for ([_]usize{ 1, SEED_B }, 0..) |sf, r| {
            var trig = Trigger.init(H_FAST, H_SLOW, c.budget);
            trig.thresh = cal.thresh;
            trig.seed_from = sf;
            var first: u64 = 0;
            var cold: usize = 0;
            var post: usize = 0;
            var peak_cold: f64 = 0;
            var peak_post: f64 = 0;
            var seeded: f64 = 0;
            for (seq, 0..) |sv, i| {
                // The controller evaluates `crosses()` BEFORE the
                // observation at this index; the replay follows that.
                if (trig.crosses()) {
                    if (first == 0) first = i;
                    if (i < c.cold_end) cold += 1;
                    if (i >= c.change_at) post += 1;
                }
                const was = trig.started;
                _ = trig.monitor(sv);
                if (!was and trig.started) seeded = trig.fast;
                if (i < c.cold_end) peak_cold = @max(peak_cold, trig.ratio());
                if (i >= c.change_at) peak_post = @max(peak_post, trig.ratio());
            }
            ticks[r] = cold;
            // The SEED value, captured when seeding happens — an earlier
            // draft printed `trig.fast` at the END of the replay and called
            // it the seed, which is the converged value and not the seed at
            // all.
            std.debug.print("        rule {s}  seed from {d:>3} nonzero -> SEEDED ON {d:.6}  first tick {d}  | cold start: {d:>5} ticks, peak ratio {d:.4}  | after the change: {d:>5} ticks, peak ratio {d:.4}\n", .{
                if (sf == 1) "A" else "B", sf, seeded, first, cold, peak_cold, post, peak_post,
            });
        }
        // Rule A must reproduce G69 (c) exactly, or the replay is not the
        // sequence the controller saw.
        if (seed == 5678) {
            try testing.expect(ticks[0] > 10_000);
            std.debug.print("        RULE B changes cold-start ticks {d} -> {d}\n", .{ ticks[0], ticks[1] });
        } else {
            try testing.expectEqual(@as(usize, 0), ticks[0]);
            try testing.expectEqual(@as(usize, 0), ticks[1]);
        }
    }
    std.debug.print("     The sequence is FIXED and the threshold FROZEN, so nothing differs but the initialisation. What this can establish is whether\n", .{});
    std.debug.print("     seeding accounts for the cold-start behaviour — NOT that rule B is a better policy, which would need its own calibration and\n", .{});
    std.debug.print("     its own registered experiment.\n", .{});
    // ── AND A SCOPE LIMIT THAT IS EASY TO MISS. These sequences come from
    // UNINTERRUPTED LEARNING. G69's own trigger/5678 arm intervened at
    // 16 384, which changed its model, its query locations and its detector
    // updates from that point on — so this replay shares only the PREFIX
    // with it. Matching cold-start counts validates that prefix and nothing
    // after it. Astra's, from reading the controller.
    std.debug.print("     SCOPE: these are UNINTERRUPTED-LEARNING sequences. G69's trigger/5678 arm intervened at 16384, so this shares only the PREFIX\n", .{});
    std.debug.print("     with it — the cold-start agreement validates that prefix, not the post-step trajectory, which in G69 ran on a changed model.\n", .{});
    std.debug.print("     AND: initialisation dependence does NOT establish that the post-step crossings contain no response to the move. That needs a\n", .{});
    std.debug.print("     no-move counterfactual, which is G69 (e).\n", .{});
}

test "G69 (e) the no-move counterfactual: is there a response to the change at all?" {
    // G69 (d) established that rule A/5678's post-step threshold activity is
    // INITIALISATION-DEPENDENT. It did not establish that those crossings
    // contain no response to the move, and an earlier write-up said they
    // were "not a response to anything" — which does not follow. **A step
    // can raise surprise while the initialisation decides whether that rise
    // crosses a threshold; dependence and responsiveness coexist.** Astra's
    // correction, and this is the control it asks for.
    //
    // Fork at the change: MOVE against NO MOVE, identical future query
    // locations (the same seeded stream continues either way) and identical
    // detector state at the fork (the prefix is shared by construction).
    // Compare the fast, slow and ratio TRACES, not only threshold counts —
    // a response that never crosses is still a response.
    //
    // **Deliberately separate from explaining G69's controller**, which
    // intervened and therefore diverged from these sequences entirely.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const H_FAST: f64 = 2048;
    const H_SLOW: f64 = 16384;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };

    const cal = try calibrate(gpa, o, c, worlds, H_FAST, H_SLOW, 0x0CA1, c.cold_end, c.change_at);
    std.debug.print("\n  G69 (e) [{s}] threshold {d:.5}; forking at t = {d} into MOVE and NO MOVE, same stream either way\n", .{
        @tagName(builtin.mode), cal.thresh, c.change_at,
    });

    const UNTIL: usize = 48_000;
    const seq = try gpa.alloc(f32, UNTIL * 2); // [move, nomove]
    defer gpa.free(seq);

    for ([_]u64{ 5678, 1234 }) |seed| {
        std.debug.print("     ── acquisition {d}\n", .{seed});
        // Two runs from the same seed, differing ONLY in whether the world
        // moves at `change_at`. The query locations are identical because
        // the stream is.
        for ([_]bool{ true, false }, 0..) |moved, w| {
            var m = try marl.Model.init(gpa, o);
            defer m.deinit();
            var st = rng.Stream.region(seed, 0x4f32_3254, 0);
            for (0..UNTIL) |i| {
                const tp = if (moved) worldAt(c, @intCast(i), worlds[0], worlds[1], worlds[2]) else worlds[0];
                const q = [3]f32{ st.unit(), st.unit(), st.unit() };
                const v: f64 = marl.truthOf(tp, q);
                const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
                seq[w * UNTIL + i] = ev.surprise;
            }
        }
        // The prefix must be identical, or the fork is not a fork.
        for (0..@intCast(c.change_at)) |i| try testing.expectEqual(seq[i], seq[UNTIL + i]);

        var mean_s: [2]f64 = .{ 0, 0 };
        for (0..2) |w| {
            var acc: f64 = 0;
            for (@intCast(c.change_at)..UNTIL) |i| acc += seq[w * UNTIL + i];
            mean_s[w] = acc / @as(f64, @floatFromInt(UNTIL - @as(usize, @intCast(c.change_at))));
        }
        std.debug.print("        mean surprise over {d}..{d}:  MOVE {d:.6}   NO MOVE {d:.6}   ratio {d:.4}\n", .{
            c.change_at, UNTIL, mean_s[0], mean_s[1], mean_s[0] / @max(1e-12, mean_s[1]),
        });
        // The move raises surprise itself, before any detector sees it.
        try testing.expect(mean_s[0] > mean_s[1]);

        for ([_]usize{ 1, 256 }) |sf| {
            var tr: [2]Trigger = undefined;
            for (0..2) |w| {
                tr[w] = Trigger.init(H_FAST, H_SLOW, c.budget);
                tr[w].thresh = cal.thresh;
                tr[w].seed_from = sf;
            }
            std.debug.print("        rule {s}:", .{if (sf == 1) "A" else "B"});
            var cross: [2]usize = .{ 0, 0 };
            var peak: [2]f64 = .{ 0, 0 };
            for (0..UNTIL) |i| {
                for (0..2) |w| {
                    if (i >= @as(usize, @intCast(c.change_at)) and tr[w].crosses()) cross[w] += 1;
                    _ = tr[w].monitor(seq[w * UNTIL + i]);
                    if (i >= @as(usize, @intCast(c.change_at))) peak[w] = @max(peak[w], tr[w].ratio());
                }
                // PAIRED-TIME values are the contemporaneous evidence: the
                // two branches compared at the SAME instant. A difference of
                // maxima is a contrast between branches that may fall at
                // different times, and is not a climb along either one.
                if (i >= @as(usize, @intCast(c.change_at)) and (i - @as(usize, @intCast(c.change_at))) % 4500 == 0) {
                    std.debug.print("  t{d}: {d:.4}/{d:.4}", .{ i, tr[0].ratio(), tr[1].ratio() });
                }
            }
            std.debug.print("   | peak {d:.4}/{d:.4}  ticks {d}/{d}  (MOVE/NO MOVE)\n", .{
                peak[0], peak[1], cross[0], cross[1],
            });
            // **The response, if there is one, is the DIFFERENCE** — and it
            // exists whether or not either side crosses.
            std.debug.print("           the move raises the MAXIMUM ratio by {d:.4} — a contrast BETWEEN branches, not a climb along either; the paired-time columns above are the contemporaneous evidence\n", .{peak[0] - peak[1]});
            // ── THE FINDING, asserted. **The statistic RESPONDS to the move
            // in every cell** — both trajectories, both initialisations —
            // and what differs is the baseline the response starts from,
            // which the seeding sets. An earlier write-up called the 5678
            // crossings "not a response to anything"; this control refutes
            // that. Dependence and responsiveness coexist.
            try testing.expect(peak[0] > peak[1]);
        }
    }
    std.debug.print("     Identical prefixes, identical query locations, identical detector state at the fork. What differs is only whether the world moved.\n", .{});
    std.debug.print("     THE STATISTIC RESPONDS IN EVERY CELL, and only one combination crosses. Initialisation affects the ratio's LEVEL *and* its\n", .{});
    std.debug.print("     RESPONSE MAGNITUDE — the peak contrasts differ between rules too, and the slow EWMA is the denominator — so 'it sets the\n", .{});
    std.debug.print("     baseline' is incomplete. Threshold crossings are sensitive to initialisation HISTORY. A fact about this scheme, not a\n", .{});
    std.debug.print("     proposal for another. And the gap's decay over the traced window is MEASURED, not attributed: separating the learner's\n", .{});
    std.debug.print("     adaptation from the EWMAs' own adjustment would need its own control.\n", .{});
}

/// One arm's trace, read back as the contracts OBS-23 depends on.
///
/// A count is not an order. OBS-21 matched a share while the ring underneath
/// it held 2709 expired entries, and the gate that reported the share never
/// asserted the ring — so these are read off the event sequence itself.
const Order = struct {
    checks: usize = 0,
    duplicate_checks: usize = 0,
    /// Sleeps landing exactly on a checkpoint index, and how many of those
    /// are followed immediately by that index's score.
    sleeps_on_check: usize = 0,
    sleep_then_check: usize = 0,
    /// Checks preceding a sleep at the SAME index — the bug, counted.
    check_before_sleep: usize = 0,
    /// Starts landing on a checkpoint, and how many have that index's score
    /// already behind them (correct when the intervention completes later).
    starts_on_check: usize = 0,
    check_before_start: usize = 0,

    fn of(t: Tally, check: u64) Order {
        var r = Order{};
        for (t.trace[0..t.ntrace], 0..) |e, k| {
            switch (e.kind) {
                .check => {
                    r.checks += 1;
                    for (t.trace[0..k]) |q| {
                        if (q.kind == .check and q.at == e.at) r.duplicate_checks += 1;
                    }
                },
                .sleep => {
                    if (e.at % check != 0) continue;
                    r.sleeps_on_check += 1;
                    if (k + 1 < t.ntrace and t.trace[k + 1].kind == .check and t.trace[k + 1].at == e.at) r.sleep_then_check += 1;
                    for (t.trace[0..k]) |q| {
                        if (q.kind == .check and q.at == e.at) r.check_before_sleep += 1;
                    }
                },
                .start => {
                    if (e.at % check != 0) continue;
                    r.starts_on_check += 1;
                    for (t.trace[0..k]) |q| {
                        if (q.kind == .check and q.at == e.at) r.check_before_start += 1;
                    }
                },
            }
        }
        return r;
    }
};

test "G70 (a) the OBS-23 lattice's contracts, driven with a sleep stub" {
    // OBS-22 refuted Q6 — no intervention policy beat `none` — and could not
    // say which half of "an intervention" failed to earn its cost, because
    // an intervention is TWO mechanisms: `r` targeted revisits paid out of
    // the same horizon, and a consolidation. OBS-23 is the 2x2.
    //
    // `tools/obs23_predict.py` holds the registration. This gate holds the
    // contracts the factorial depends on, with the expensive call stubbed —
    // Astra's build order, which found three bugs in OBS-22 seconds into a
    // run instead of nine minutes, and found a fourth in THIS phase before
    // any sleep was paid for.
    //
    // **The headline contract is the collapse scenario**, and it is the
    // reason the phase can attribute anything: with the sleep stubbed the
    // six arms must reduce to exactly TWO trajectories, bit for bit. If they
    // do, every difference the expensive gate reports is the consolidation
    // or the spend. If they do not, the runner is a third factor nobody
    // registered — and identical query hashes would not reveal it, because a
    // controller side effect need not move a single drawn location.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 2;
    o.responsibility = 3;
    // The cheap constants, in G69 (a)'s proportions, and the placements are
    // chosen so that EVERY sleep in the lattice lands exactly on a
    // checkpoint — the immediate path at t, the deferred path at t + r.
    // Astra's requirement, because the two paths reach a coincident
    // checkpoint by different code and only a timing that hits both can
    // assert the registered order on both.
    const bounds = [_]u64{ 2_000, 5_000, 6_500, 7_000, 10_000, 12_000 };
    const c = Traj{
        .total = 12_000,
        .r = 1_000,
        .w = 2_000,
        .n = 1_000,
        .check = 500,
        .cold_end = 2_000,
        .change_at = 5_000,
        .drift_lo = 7_000,
        .drift_hi = 10_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const AT_T = [_]u64{ 5_000, 7_000, 10_000 }; // fire instants, all checkpoints
    const AT_TR = [_]u64{ 6_000, 8_000, 11_000 }; // each + r, all checkpoints
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 512);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }

    const REVISITS: u64 = @as(u64, c.budget) * @as(u64, c.r);
    const FRESH_AFTER: u64 = c.total - REVISITS;
    const CHECKS: usize = @intCast(c.total / c.check);

    std.debug.print("\n  G70 (a) [{s}] the OBS-23 lattice on the REAL controller, sleep stubbed; {d} observations, r = {d}, budget {d}, check {d}\n", .{
        @tagName(builtin.mode), c.total, c.r, c.budget, c.check,
    });

    const run = struct {
        fn go(
            g: std.mem.Allocator,
            oo: marl.Options,
            cc: Traj,
            at: []const u64,
            rec: Recipe,
            ws: [3]marl.TruthParams,
            pp: [][3]f32,
            prefix: u64,
        ) !Tally {
            var trig = Trigger.init(256, 2048, cc.budget);
            var out = Tally{ .prefix_at = prefix };
            var st = rng.Stream.region(4242, 0x4f32_3254, 0);
            const plan: Plan = if (at.len == 0) .never else .{ .at = at };
            try runArm(g, oo, cc, plan, &trig, ws, pp, false, &st, &out, .{}, rec, null);
            return out;
        }
    }.go;

    // The six arms of the registered lattice, in the pre-registration's
    // order. `none` is `.never` and the rest are `.at` — no arm here
    // consults the detector, so every crossing count must be zero.
    //
    // The clock is what makes it six and not four: an arm spending `r` on
    // revisits completes its intervention `r` after it starts, so `both`
    // consolidates at t + r. Its matched no-revisit cell is therefore PLACED
    // at t + r and consolidates immediately — it does not fire early.
    // `sleep@t` is the fifth arm and isolates that offset alone.
    const names = [_][]const u8{ "none", "revisit", "sleep@t", "sleep@t+r", "both", "unguarded" };
    const plans = [_][]const u64{ &.{}, &AT_T, &AT_T, &AT_TR, &AT_T, &AT_T };
    const recipes = [_]Recipe{
        .{ .revisit = false, .consolidate = false },
        .{ .revisit = true, .consolidate = false },
        .{ .revisit = false, .consolidate = true, .guard = true },
        .{ .revisit = false, .consolidate = true, .guard = true },
        .{ .revisit = true, .consolidate = true, .guard = true },
        .{ .revisit = true, .consolidate = true, .guard = false },
    };

    var t: [6]Tally = undefined;
    for (0..6) |k| t[k] = try run(gpa, o, c, plans[k], recipes[k], worlds, pr.p, FRESH_AFTER);

    // ── SCENARIO 1: THE ACCOUNTING, which is arithmetic and is therefore
    // asserted exactly rather than announced. `paid` must equal the horizon
    // for every arm however its budget was spent — that is what makes the
    // arms comparable at all.
    std.debug.print("     {s:<11} {s:>7} {s:>10} {s:>9} {s:>8} {s:>7} {s:>17} {s:>17}\n", .{
        "arm", "paid", "monitored", "revisits", "started", "sleeps", "stream hash", "prefix",
    });
    for (0..6) |k| {
        std.debug.print("     {s:<11} {d:>7} {d:>10} {d:>9} {d:>8} {d:>7} {x:>17} {x:>17}\n", .{
            names[k],    t[k].paid,        t[k].monitored,     t[k].revisits, t[k].started,
            t[k].sleeps, t[k].stream_hash, t[k].stream_prefix,
        });
    }
    for (0..6) |k| {
        try testing.expectEqual(c.total, t[k].paid);
        try testing.expectEqual(t[k].paid, t[k].monitored + t[k].revisits);
        try testing.expectEqual(if (recipes[k].revisit) REVISITS else @as(u64, 0), t[k].revisits);
        try testing.expectEqual(@as(usize, if (plans[k].len == 0) 0 else c.budget), t[k].started);
        try testing.expectEqual(@as(usize, if (recipes[k].consolidate and plans[k].len != 0) c.budget else 0), t[k].sleeps);
        // Every arm is `.at` or `.never`, so nothing may reach the detector,
        // and nothing may be refused for readiness or the horizon. A
        // placement that did either would silently change the budget an arm
        // actually spent, and the cells would stop being matched.
        try testing.expectEqual(@as(usize, 0), t[k].crossings);
        try testing.expectEqual(@as(usize, 0), t[k].unready);
        try testing.expectEqual(@as(usize, 0), t[k].horizon_blocked);
        try testing.expectEqual(@as(usize, 0), t[k].rejections);
    }

    // ── SCENARIO 2: THE STREAM CONTRACT. The fresh-draw RNG advances once
    // per fresh observation and NEVER for a revisit, so arms that do not
    // revisit draw the identical locations in the identical order, and arms
    // that do draw a PREFIX of that same sequence.
    //
    // **What the shared prefix is NOT is shared evidence.** Those locations
    // arrive at different PAID TIMES in a revisiting arm, so in the drift
    // they can carry different labels, and they are learned from by a model
    // with a different history. The common clock makes that part of the
    // policy effect rather than an artefact — but it is a difference the
    // hash equality must not be read as denying.
    try testing.expect(t[0].stream_prefix != 0);
    for ([_]usize{ 2, 3 }) |k| {
        try testing.expectEqual(t[0].stream_hash, t[k].stream_hash);
        try testing.expectEqual(t[0].monitored, t[k].monitored);
    }
    for ([_]usize{ 1, 4, 5 }) |k| {
        try testing.expectEqual(t[0].stream_prefix, t[k].stream_hash);
        try testing.expectEqual(FRESH_AFTER, t[k].monitored);
    }
    std.debug.print("     stream: none == sleep@t == sleep@t+r over {d} fresh draws; revisit == both == unguarded == none's first {d}. The LOCATIONS match; the paid times, labels and learner histories need not\n", .{
        t[0].monitored, FRESH_AFTER,
    });

    // ── SCENARIO 3: THE REGISTERED EVENT ORDER, ON BOTH PATHS. Observation,
    // then the COMPLETED intervention's sleep, then the score.
    //
    // The two halves complete at different instants and reach a coincident
    // checkpoint by different code: a revisiting arm defers the score of a
    // checkpoint landing on its LAST QUERY, while a non-revisiting arm
    // completes at the instant it started and must defer the checkpoint
    // already reached there. **The immediate path reintroduced OBS-22's
    // score-ordering bug when it was added** — it scored at 5000, 7000 and
    // 10 000 and only then consolidated — and every placement here lands on
    // a checkpoint so that both paths are pinned.
    std.debug.print("     {s:<11} {s:>7} {s:>6} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{
        "arm", "checks", "dupes", "sleep@check", "sleep->check", "check<sleep", "start@check", "check<start",
    });
    for (0..6) |k| {
        const ord = Order.of(t[k], c.check);
        std.debug.print("     {s:<11} {d:>7} {d:>6} {d:>12} {d:>12} {d:>12} {d:>12} {d:>12}\n", .{
            names[k],             ord.checks,             ord.duplicate_checks, ord.sleeps_on_check,
            ord.sleep_then_check, ord.check_before_sleep, ord.starts_on_check,  ord.check_before_start,
        });
    }
    for (0..6) |k| {
        const ord = Order.of(t[k], c.check);
        // Exactly one score per checkpoint, for every arm. A deferral that
        // dropped a score, or one that scored an index twice, would move the
        // objective without moving anything the design is about.
        try testing.expectEqual(CHECKS, ord.checks);
        try testing.expectEqual(CHECKS, t[k].checks);
        try testing.expectEqual(@as(usize, 0), ord.duplicate_checks);
        // Every sleep in this lattice lands on a checkpoint by construction.
        try testing.expectEqual(@as(usize, if (recipes[k].consolidate and plans[k].len != 0) c.budget else 0), ord.sleeps_on_check);
        // And at each, the sleep precedes that index's score.
        try testing.expectEqual(ord.sleeps_on_check, ord.sleep_then_check);
        try testing.expectEqual(@as(usize, 0), ord.check_before_sleep);
        // The mirror image for a revisiting arm: its intervention completes
        // LATER than it starts, so a checkpoint at the START instant belongs
        // BEFORE it and must already be behind.
        if (recipes[k].revisit) {
            try testing.expectEqual(@as(usize, c.budget), ord.starts_on_check);
            try testing.expectEqual(ord.starts_on_check, ord.check_before_start);
        }
    }
    std.debug.print("     ordering: every sleep lands ON a checkpoint and precedes its score, on the immediate path AND the deferred one; every revisiting start has its own checkpoint already behind it\n", .{});

    // ── SCENARIO 4: A NON-CONSOLIDATING ARM STARTS AND DOES NOT SLEEP.
    // `revisit` must perform the aiming half in full — the starts, the
    // revisits, the post-intervention watch — and emit no sleep event, so
    // that the row of the 2x2 it occupies really is "no consolidation"
    // rather than "a consolidation that happened to be cheap".
    {
        var starts: usize = 0;
        var sleeps: usize = 0;
        for (t[1].trace[0..t[1].ntrace]) |e| switch (e.kind) {
            .start => starts += 1,
            .sleep => sleeps += 1,
            .check => {},
        };
        try testing.expectEqual(@as(usize, c.budget), starts);
        try testing.expectEqual(@as(usize, 0), sleeps);
        std.debug.print("     revisit: {d} starts, {d} sleep events, {d} revisits — the aiming half in full and nothing else\n", .{
            starts, sleeps, t[1].revisits,
        });
    }

    // ── SCENARIO 5: THE CLOCK. `both` and `sleep@t+r` must consolidate at
    // the SAME indices, or the 2x2's sleeping row differs in WHEN as well as
    // in what preceded it and the interaction term measures both.
    {
        var a: [8]u64 = .{0} ** 8;
        var b: [8]u64 = .{0} ** 8;
        var e0: [8]u64 = .{0} ** 8;
        var na: usize = 0;
        var nb: usize = 0;
        var ne: usize = 0;
        for (t[3].trace[0..t[3].ntrace]) |e| if (e.kind == .sleep) {
            a[na] = e.at;
            na += 1;
        };
        for (t[4].trace[0..t[4].ntrace]) |e| if (e.kind == .sleep) {
            b[nb] = e.at;
            nb += 1;
        };
        for (t[2].trace[0..t[2].ntrace]) |e| if (e.kind == .sleep) {
            e0[ne] = e.at;
            ne += 1;
        };
        std.debug.print("     clock:  sleep@t+r at {any}, both at {any}, sleep@t at {any}\n", .{ a[0..na], b[0..nb], e0[0..ne] });
        try testing.expectEqual(@as(usize, c.budget), na);
        try testing.expectEqual(na, nb);
        try testing.expectEqual(na, ne);
        for (0..na) |k| try testing.expectEqual(a[k], b[k]);
        for (0..ne) |k| try testing.expectEqual(a[k] - @as(u64, c.r), e0[k]);
    }

    // ── SCENARIO 6: THE COLLAPSE, and the contract the whole phase rests
    // on. With the consolidation stubbed there is nothing left to tell a
    // sleeping arm from its non-sleeping partner, so the six must reduce to
    // exactly TWO trajectories — bit for bit, on the OUTPUTS and not only on
    // the drawn locations. A controller side effect need not move a single
    // query to move the objective.
    std.debug.print("     {s:<11} {s:>12} {s:>8} {s:>8} {s:>8} {s:>9} {s:>8}\n", .{ "arm", "err_sum", "checks", "k_final", "k_peak", "mean k", "births" });
    for (0..6) |k| std.debug.print("     {s:<11} {d:>12.6} {d:>8} {d:>8} {d:>8} {d:>9.1} {d:>8}\n", .{
        names[k], t[k].err_sum, t[k].checks, t[k].k_final, t[k].k_peak, t[k].meanK(), t[k].births_total,
    });
    for ([_]usize{ 2, 3 }) |k| {
        try testing.expectEqual(t[0].err_sum, t[k].err_sum);
        try testing.expectEqual(t[0].err_phase, t[k].err_phase);
        try testing.expectEqual(t[0].k_final, t[k].k_final);
        try testing.expectEqual(t[0].k_peak, t[k].k_peak);
        try testing.expectEqual(t[0].k_sum, t[k].k_sum);
        try testing.expectEqual(t[0].births_total, t[k].births_total);
    }
    for ([_]usize{ 4, 5 }) |k| {
        try testing.expectEqual(t[1].err_sum, t[k].err_sum);
        try testing.expectEqual(t[1].err_phase, t[k].err_phase);
        try testing.expectEqual(t[1].k_final, t[k].k_final);
        try testing.expectEqual(t[1].k_peak, t[k].k_peak);
        try testing.expectEqual(t[1].k_sum, t[k].k_sum);
        try testing.expectEqual(t[1].births_total, t[k].births_total);
    }
    // The two surviving trajectories must actually DIFFER, or the collapse
    // is vacuous and the revisit factor is doing nothing at all.
    try testing.expect(t[0].err_sum != t[1].err_sum);
    std.debug.print("     collapse: six arms -> TWO trajectories with the sleep stubbed, matched on outputs and not merely on drawn locations. Every G70 difference is therefore the consolidation or the spend, never the runner.\n", .{});

    // ── SCENARIO 7: THE RESOURCE COLUMNS EXIST AND ARE POPULATED at every
    // checkpoint, not only at the end. OBS-22 reported error alone — which
    // was valid for its stated objective and incomplete as a resource
    // account. Final population can miss most of a trajectory's history, so
    // the mean over checkpoints and the peak are carried beside it, and
    // births are kept apart from sleeps because they are different costs.
    for (0..6) |k| {
        try testing.expectEqual(t[k].checks, t[k].k_n);
        try testing.expect(t[k].meanK() > 0);
        try testing.expect(t[k].k_peak >= t[k].k_final);
    }
    std.debug.print("     capacity: mean population over checkpoints {d:.1} (fresh stream) and {d:.1} (revisiting), peaks {d} and {d} — reported alongside error, never instead of it\n", .{
        t[0].meanK(), t[1].meanK(), t[0].k_peak, t[1].k_peak,
    });
}

test "G70 what does an intervention actually cost?" {
    // OBS-22 refuted Q6 — no intervention policy beat `none` — and could not
    // say which half failed to earn its cost, because an intervention is two
    // mechanisms: `r` targeted revisits paid out of the same horizon, and a
    // consolidation. This is the 2x2, at OBS-22's privileged `informed`
    // placement so that the trigger is not a third factor.
    //
    // `tools/obs23_predict.py` holds the registration; G70 (a) holds the
    // contracts and runs in seconds; this is the expensive comparison, and
    // it runs once.
    //
    // **No arm consults the detector**, so nothing here is calibrated and
    // nothing here tests OBS-22's trigger. That is deliberate: OBS-22
    // established the trigger is its own problem.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const H_FAST: f64 = 2048;
    const H_SLOW: f64 = 16384;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 2048);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }

    const informed = [_]u64{ 30_000, 60_000, 90_000 };
    const deferred = [_]u64{ 34_096, 64_096, 94_096 }; // each + r
    const acq = [_]u64{ 1234, 5678 };
    const NPH = bounds.len;
    const REVISITS: u64 = @as(u64, c.budget) * @as(u64, c.r);
    const FRESH_AFTER: u64 = c.total - REVISITS;

    const NONE = 0;
    const REV = 1;
    const SL_T = 2;
    const SL_TR = 3;
    const BOTH = 4;
    const UNG = 5;
    const names = [_][]const u8{ "none", "revisit", "sleep@t", "sleep@t+r", "both", "unguarded" };
    const plans = [_][]const u64{ &.{}, &informed, &informed, &deferred, &informed, &informed };
    const recipes = [_]Recipe{
        .{ .revisit = false, .consolidate = false },
        .{ .revisit = true, .consolidate = false },
        .{ .revisit = false, .consolidate = true, .guard = true },
        .{ .revisit = false, .consolidate = true, .guard = true },
        .{ .revisit = true, .consolidate = true, .guard = true },
        .{ .revisit = true, .consolidate = true, .guard = false },
    };

    std.debug.print("\n  G70 [{s}] OBS-23: what does an intervention cost? {d} arms x {d} acquisition trajectories, {d} observations each\n", .{
        @tagName(builtin.mode), names.len, acq.len, c.total,
    });

    var tal: [6][acq.len]Tally = undefined;
    for (0..names.len) |a| {
        for (acq, 0..) |seed, j| {
            var trig = Trigger.init(H_FAST, H_SLOW, c.budget);
            var out = Tally{ .prefix_at = FRESH_AFTER };
            var st = rng.Stream.region(seed, 0x4f32_3254, 0);
            const plan: Plan = if (plans[a].len == 0) .never else .{ .at = plans[a] };
            try runArm(gpa, o, c, plan, &trig, worlds, pr.p, true, &st, &out, .{}, recipes[a], null);
            tal[a][j] = out;
        }
    }

    // ── THE ACCOUNTING, AND THE STREAM CONTRACT ──────────────────────────
    std.debug.print("     ACCOUNTING and the stream contract — the locations match; the paid times, labels and learner histories need not\n", .{});
    std.debug.print("     {s:<11} {s:>5} {s:>8} {s:>10} {s:>9} {s:>8} {s:>7} {s:>11} {s:>17}\n", .{
        "arm", "acq", "paid", "monitored", "revisits", "started", "sleeps", "rejections", "stream hash",
    });
    for (0..names.len) |a| for (acq, 0..) |seed, j| std.debug.print("     {s:<11} {d:>5} {d:>8} {d:>10} {d:>9} {d:>8} {d:>7} {d:>11} {x:>17}\n", .{
        names[a],          seed,             tal[a][j].paid,       tal[a][j].monitored,   tal[a][j].revisits,
        tal[a][j].started, tal[a][j].sleeps, tal[a][j].rejections, tal[a][j].stream_hash,
    });

    // ── THE OBJECTIVES, OBS-22's UNCHANGED ───────────────────────────────
    const obj = struct {
        fn go(t: Tally, nph: usize, tail: bool) f64 {
            return if (tail) t.meanTail(nph) else t.mean();
        }
    }.go;
    std.debug.print("     TIME-AVERAGED ERROR (mean RMS over checkpoints, not pooled MSE)\n", .{});
    std.debug.print("     {s:<11} {s:>10} {s:>10} {s:>10}   {s:>10} {s:>10} {s:>10}\n", .{
        "arm", "whole 1234", "whole 5678", "mean", "tail 1234", "tail 5678", "mean",
    });
    for (0..names.len) |a| {
        const w0 = obj(tal[a][0], NPH, false);
        const w1 = obj(tal[a][1], NPH, false);
        const t0 = obj(tal[a][0], NPH, true);
        const t1 = obj(tal[a][1], NPH, true);
        std.debug.print("     {s:<11} {d:>10.5} {d:>10.5} {d:>10.5}   {d:>10.5} {d:>10.5} {d:>10.5}\n", .{
            names[a], w0, w1, 0.5 * (w0 + w1), t0, t1, 0.5 * (t0 + t1),
        });
    }

    // ── THE PAIRED CONTRASTS. Astra's: a 2x2 read as four arm means loses
    // the pairing that makes it a factorial. Each is formed WITHIN a
    // trajectory and only then averaged.
    //
    // **Two trajectories are descriptive replication.** The between-
    // trajectory difference is printed for each contrast SEPARATELY; an
    // individual arm's own spread is not the uncertainty of a paired
    // interaction and is never spent on one.
    const cnames = [_][]const u8{
        "C1  revisit - none",
        "C2  sleep@t+r - none",
        "C3  both - revisit",
        "C4  both - sleep@t+r",
        "C5  INTERACTION",
        "C6  sleep@t+r - sleep@t",
    };
    const cnote = [_][]const u8{
        "the aiming half, without a consolidation",
        "the consolidation half, without revisiting",
        "consolidation's effect WITH revisiting",
        "revisiting's effect WITH consolidation",
        "both - revisit - sleep@t+r + none",
        "the r-observation offset, alone",
    };
    var cval: [2][6][acq.len]f64 = undefined; // [objective][contrast][seed]
    for ([_]bool{ false, true }, 0..) |tail, oi| {
        for (acq, 0..) |_, j| {
            const n = obj(tal[NONE][j], NPH, tail);
            const r = obj(tal[REV][j], NPH, tail);
            const st = obj(tal[SL_T][j], NPH, tail);
            const sr = obj(tal[SL_TR][j], NPH, tail);
            const b = obj(tal[BOTH][j], NPH, tail);
            cval[oi][0][j] = r - n;
            cval[oi][1][j] = sr - n;
            cval[oi][2][j] = b - r;
            cval[oi][3][j] = b - sr;
            cval[oi][4][j] = b - r - sr + n;
            cval[oi][5][j] = sr - st;
        }
    }
    for ([_]bool{ false, true }, 0..) |tail, oi| {
        std.debug.print("     PAIRED CONTRASTS, formed within a trajectory — {s}. NEGATIVE means the first term has the LOWER error\n", .{if (tail) "DRIFT+TAIL" else "WHOLE"});
        std.debug.print("     {s:<26} {s:>10} {s:>10} {s:>10} {s:>11}   {s}\n", .{ "contrast", "1234", "5678", "mean", "|between|", "what it is" });
        for (0..cnames.len) |k| {
            const v0 = cval[oi][k][0];
            const v1 = cval[oi][k][1];
            std.debug.print("     {s:<26} {d:>10.5} {d:>10.5} {d:>10.5} {d:>11.5}   {s}\n", .{
                cnames[k], v0, v1, 0.5 * (v0 + v1), @abs(v0 - v1), cnote[k],
            });
        }
    }

    // ── THE RESOURCE ACCOUNT, which OBS-22 did not report at all. Final
    // population can miss most of a trajectory's history, so the mean over
    // checkpoints and the peak are carried beside it, and births are kept
    // apart from sleeps because they are different costs.
    std.debug.print("     CAPACITY — reported alongside error, never instead of it\n", .{});
    std.debug.print("     {s:<11} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>8}\n", .{
        "arm", "k_fin 1234", "k_fin 5678", "k_peak", "mean k", "births", "sleeps", "k/none",
    });
    for (0..names.len) |a| {
        const kf = 0.5 * @as(f64, @floatFromInt(tal[a][0].k_final + tal[a][1].k_final));
        const kn = 0.5 * @as(f64, @floatFromInt(tal[NONE][0].k_final + tal[NONE][1].k_final));
        std.debug.print("     {s:<11} {d:>10} {d:>10} {d:>10.1} {d:>10.1} {d:>10.1} {d:>10} {d:>8.3}\n", .{
            names[a],
            tal[a][0].k_final,
            tal[a][1].k_final,
            0.5 * @as(f64, @floatFromInt(tal[a][0].k_peak + tal[a][1].k_peak)),
            0.5 * (tal[a][0].meanK() + tal[a][1].meanK()),
            0.5 * @as(f64, @floatFromInt(tal[a][0].births_total + tal[a][1].births_total)),
            tal[a][0].sleeps + tal[a][1].sleeps,
            kf / kn,
        });
    }

    // ── WHERE THE ARMS SEPARATE. C6 compares two complete sleep
    // SCHEDULES, not one window against another: after the first sleep that
    // differs, the models differ, later windows carry different surprise
    // weights, the selected buffers differ and every subsequent
    // consolidation starts from a different state. So a contrast between
    // schedules cannot be localised to any one intervention by its value
    // alone.
    //
    // **And that is an inability to ATTRIBUTE, never an exoneration.** An
    // early intervention can have delayed consequences, so a gap appearing
    // in drift-and-tail does not clear the first sleep of causing it; it
    // only means the aggregate cannot say. Astra's distinction.
    //
    // A phase mean cannot localise it either. The per-checkpoint trace can,
    // and it costs nothing to carry — without it the first step of any
    // follow-up is another sixteen minutes of this gate. What the first
    // visible separation identifies is WHERE TO INVESTIGATE, not where the
    // causal difference originated.
    std.debug.print("     ERROR BY PHASE (mean RMS over that phase's checkpoints), averaged over the two acquisition trajectories\n", .{});
    std.debug.print("     {s:<11} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10}\n", .{
        "arm", "cold", "stat A", "step", "stat B", "drift", "tail",
    });
    for (0..names.len) |a| {
        var row: [6]f64 = .{0} ** 6;
        for (0..NPH) |k| {
            var acc: f64 = 0;
            for (acq, 0..) |_, j| acc += tal[a][j].err_phase[k] / @as(f64, @floatFromInt(@max(1, tal[a][j].checks_phase[k])));
            row[k] = acc / @as(f64, @floatFromInt(acq.len));
        }
        std.debug.print("     {s:<11} {d:>10.5} {d:>10.5} {d:>10.5} {d:>10.5} {d:>10.5} {d:>10.5}\n", .{
            names[a], row[0], row[1], row[2], row[3], row[4], row[5],
        });
    }
    std.debug.print("     PER-CHECKPOINT ERROR, one row per arm per trajectory, seeds kept APART; column k is the score at (k + 1) x {d}, identical instants across arms.\n", .{c.check});
    std.debug.print("     The first visible separation says WHERE TO INVESTIGATE, not where the causal difference originated — an early intervention can act late.\n", .{});
    for (0..names.len) |a| for (acq, 0..) |seed, j| {
        std.debug.print("       {s:<11} {d:<5}", .{ names[a], seed });
        for (tal[a][j].check_err[0..tal[a][j].checks]) |e| std.debug.print(" {d:.5}", .{e});
        std.debug.print("\n", .{});
    };

    // ── THE FEEDBACK CHANNEL, measured rather than merely conceded.
    //
    // Astra: a consolidation's effect INCLUDES what it does to later
    // acquisition. `revisit` and `both` share the fresh stream, but once
    // `both` has consolidated its admission surprises differ, so the
    // window's ranking differs, so its second and third interventions need
    // not target the same locations.
    //
    // The first intervention is a CONTRACT, not a prediction: no arm has
    // slept before selecting its targets at t = 30 000, so all three
    // revisiting arms must agree exactly there. Divergence afterwards is
    // the channel opening, and this says only WHETHER it opened and when —
    // a hash is identical or it is not, and the magnitude of the
    // divergence is a separate instrument nobody has built.
    std.debug.print("     REVISIT TARGETING — do the revisiting arms aim at the same places once one of them has consolidated?\n", .{});
    for (acq, 0..) |seed, j| {
        for (0..c.budget) |k| {
            const same_b = tal[REV][j].rev_hash[k] == tal[BOTH][j].rev_hash[k];
            const same_u = tal[BOTH][j].rev_hash[k] == tal[UNG][j].rev_hash[k];
            std.debug.print("       acq {d}  intervention {d}: revisit vs both {s:<9} both vs unguarded {s}\n", .{
                seed, k, if (same_b) "IDENTICAL" else "differs", if (same_u) "IDENTICAL" else "differs",
            });
        }
    }

    // ── THE VERDICT TABLE, printed BEFORE anything is asserted, so that a
    // refutation still leaves its evidence behind. OBS-19 lost a ten-minute
    // run to an assertion inside the loop that produced its table.
    const q1 = 0.5 * (cval[0][0][0] + cval[0][0][1]);
    const q2 = 0.5 * (cval[0][1][0] + cval[0][1][1]);
    const q3 = 0.5 * (cval[0][4][0] + cval[0][4][1]);
    const q4 = 0.5 * (@as(f64, @floatFromInt(tal[BOTH][0].k_final)) / @as(f64, @floatFromInt(tal[NONE][0].k_final)) +
        @as(f64, @floatFromInt(tal[BOTH][1].k_final)) / @as(f64, @floatFromInt(tal[NONE][1].k_final)));
    const rej = tal[SL_T][0].rejections + tal[SL_T][1].rejections +
        tal[SL_TR][0].rejections + tal[SL_TR][1].rejections +
        tal[BOTH][0].rejections + tal[BOTH][1].rejections;
    std.debug.print("     VERDICT\n", .{});
    std.debug.print("       Q1  C1 = revisit - none            registered < 0            measured {d:.5}   {s}\n", .{ q1, if (q1 < 0) "HELD" else "REFUTED" });
    std.debug.print("       Q2  C2 = sleep@t+r - none          registered > 0            measured {d:.5}   {s}\n", .{ q2, if (q2 > 0) "HELD" else "REFUTED" });
    std.debug.print("       Q2' C2 exceeds OBS-22's deficit    registered > {d:.5}     measured {d:.5}   {s}\n", .{ thresholds.OBS23_DEFICIT_REF, q2, if (q2 > thresholds.OBS23_DEFICIT_REF) "HELD" else "REFUTED" });
    std.debug.print("       Q3  C5 = the interaction           registered < 0            measured {d:.5}   {s}\n", .{ q3, if (q3 < 0) "HELD" else "REFUTED" });
    std.debug.print("       Q4  k_final(both)/k_final(none)    registered [{d:.2}, {d:.2}]   measured {d:.5}    {s}\n", .{
        thresholds.OBS23_CAPACITY_LO,                                                                         thresholds.OBS23_CAPACITY_HI, q4,
        if (q4 >= thresholds.OBS23_CAPACITY_LO and q4 <= thresholds.OBS23_CAPACITY_HI) "HELD" else "REFUTED",
    });
    std.debug.print("       Q5  guard rejections               registered {d}              measured {d}          {s}\n", .{
        thresholds.OBS23_GUARD_REJECTIONS, rej, if (rej == thresholds.OBS23_GUARD_REJECTIONS) "HELD" else "REFUTED",
    });
    std.debug.print("       Q4 stands REGISTERED AND REFUTED and is NOT asserted below. The bound is wrong rather than the code, and it is left\n", .{});
    std.debug.print("       standing to be struck rather than tuned to fit. **The saving MISSED the prediction; it did not disappear** — final\n", .{});
    std.debug.print("       population {d:.3} of `none`'s, checkpoint-mean {d:.3}, while PEAK is {d:.3}, above one. So there IS an accuracy-capacity\n", .{
        q4,
        0.5 * (tal[BOTH][0].meanK() + tal[BOTH][1].meanK()) / (0.5 * (tal[NONE][0].meanK() + tal[NONE][1].meanK())),
        @as(f64, @floatFromInt(tal[BOTH][0].k_peak + tal[BOTH][1].k_peak)) / @as(f64, @floatFromInt(tal[NONE][0].k_peak + tal[NONE][1].k_peak)),
    });
    std.debug.print("       trade, smaller than registered and UNPRICED: nothing here says what ~12 per cent of the kernels is worth against the error.\n", .{});
    std.debug.print("     SCOPE: one fixture, one placement set, one r, one budget, one compression ratio. This estimates a REPEATED POLICY —\n", .{});
    std.debug.print("     three interventions interacting through the model — and a consolidation's effect INCLUDES its feedback into what later\n", .{});
    std.debug.print("     revisits target, so no contrast here separates 'sleep uses repaired evidence better' from 'sleep changes what is revisited next'.\n", .{});

    // ── ASSERTIONS, every one of them after every print ───────────────────
    for (0..names.len) |a| for (acq, 0..) |_, j| {
        const t = tal[a][j];
        try testing.expectEqual(c.total, t.paid);
        try testing.expectEqual(t.paid, t.monitored + t.revisits);
        try testing.expectEqual(if (recipes[a].revisit) REVISITS else @as(u64, 0), t.revisits);
        try testing.expectEqual(@as(usize, if (plans[a].len == 0) 0 else c.budget), t.started);
        try testing.expectEqual(@as(usize, if (recipes[a].consolidate and plans[a].len != 0) c.budget else 0), t.sleeps);
        try testing.expectEqual(@as(usize, 0), t.crossings);
        try testing.expectEqual(@as(usize, 0), t.unready);
        try testing.expectEqual(@as(usize, 0), t.horizon_blocked);
        // One score per checkpoint, for every arm, on both sleep paths.
        try testing.expectEqual(@as(usize, @intCast(c.total / c.check)), t.checks);
        try testing.expectEqual(t.checks, t.k_n);
    };
    // The stream contract, per trajectory.
    for (acq, 0..) |_, j| {
        try testing.expect(tal[NONE][j].stream_prefix != 0);
        for ([_]usize{ SL_T, SL_TR }) |a| try testing.expectEqual(tal[NONE][j].stream_hash, tal[a][j].stream_hash);
        for ([_]usize{ REV, BOTH, UNG }) |a| try testing.expectEqual(tal[NONE][j].stream_prefix, tal[a][j].stream_hash);
    }
    // THE TRACE'S OWN CONTRACT. A per-checkpoint record is only usable for a
    // later diagnosis if it is the SAME quantity the phase scored, taken at
    // the instants it claims. Astra's: assert the indices, the count and the
    // correspondence with the accumulated objective — otherwise OBS-24 reads
    // a different number from the one OBS-23 concluded from.
    for (0..names.len) |a| for (acq, 0..) |_, j| {
        const t = tal[a][j];
        try testing.expect(t.checks <= t.check_err.len);
        // The k-th checkpoint sits at exactly (k + 1) x check, and there are
        // exactly as many of them as the objective counted. A truncated
        // event trace fails here rather than silently shortening the record.
        var k: usize = 0;
        for (t.trace[0..t.ntrace]) |e| {
            if (e.kind != .check) continue;
            try testing.expectEqual(@as(u64, @intCast(k + 1)) * c.check, e.at);
            k += 1;
        }
        try testing.expectEqual(t.checks, k);
        // The trace sums to the accumulated objective, in the same order and
        // therefore bit for bit.
        var acc: f64 = 0;
        for (t.check_err[0..t.checks]) |e| acc += e;
        try testing.expectEqual(t.err_sum, acc);
        // And the phase segmentation partitions the same checkpoints — a
        // different addition order, so a tolerance rather than equality.
        var pn: usize = 0;
        var pe: f64 = 0;
        for (0..NPH) |ph| {
            pn += t.checks_phase[ph];
            pe += t.err_phase[ph];
        }
        try testing.expectEqual(t.checks, pn);
        try testing.expect(@abs(pe - t.err_sum) < 1e-12);
    };
    // The first intervention's targets are a CONTRACT: nothing has
    // consolidated when they are chosen, so every revisiting arm must pick
    // the same r locations. If they do not, the arms were never matched.
    for (acq, 0..) |_, j| {
        try testing.expect(tal[REV][j].rev_hash[0] != 0);
        try testing.expectEqual(tal[REV][j].rev_hash[0], tal[BOTH][j].rev_hash[0]);
        try testing.expectEqual(tal[REV][j].rev_hash[0], tal[UNG][j].rev_hash[0]);
    }
    // The interaction is an identity on the other two contrasts; if it is
    // not, the table is arithmetic rather than a factorial.
    for ([_]usize{ 0, 1 }) |oi| for (acq, 0..) |_, j| {
        try testing.expect(@abs(cval[oi][4][j] - (cval[oi][2][j] - cval[oi][1][j])) < 1e-12);
        try testing.expect(@abs(cval[oi][4][j] - (cval[oi][3][j] - cval[oi][0][j])) < 1e-12);
    };
    // Q5: with no rejection the guard restores nothing, so the two arms must
    // agree EXACTLY and not to printed precision.
    if (rej == 0) {
        for (acq, 0..) |_, j| {
            try testing.expectEqual(tal[BOTH][j].err_sum, tal[UNG][j].err_sum);
            try testing.expectEqual(tal[BOTH][j].err_phase, tal[UNG][j].err_phase);
            try testing.expectEqual(tal[BOTH][j].k_final, tal[UNG][j].k_final);
        }
    }
    try testing.expectEqual(thresholds.OBS23_GUARD_REJECTIONS, rej);
    // The registered headline. Asserted, because a gate that cannot fail on
    // its own headline is decoration.
    try testing.expect(q1 < thresholds.OBS23_REVISIT_PAYS);
    try testing.expect(q2 > thresholds.OBS23_SLEEP_COSTS);
    try testing.expect(q2 > thresholds.OBS23_DEFICIT_REF);
    try testing.expect(q3 < thresholds.OBS23_INTERACTION);
    // Q4 is REGISTERED AND REFUTED and is deliberately NOT asserted. A
    // threshold is not tuned to make a gate pass; the finding is recorded
    // and the bound left standing in `thresholds.zig` for Christian.
    //
    // What IS asserted is a structural invariant the capacity column
    // revealed and did not register: **nothing dies except at a
    // consolidation**, so an arm that never consolidates ends with exactly
    // as many kernels as it ever birthed. It is what exposed the births
    // accounting bug, and it would catch a silent pruning path.
    for (0..names.len) |a| {
        if (recipes[a].consolidate and plans[a].len != 0) continue;
        for (acq, 0..) |_, j| try testing.expectEqual(@as(u64, @intCast(tal[a][j].k_final)), tal[a][j].births_total);
    }
}

/// The four points a consolidation passes through, in the TWO measures that
/// have different labels — and keeping them apart is the whole reason for
/// having both.
///
///   * REPLAY is scored on the selected buffer against ITS OWN STORED
///     LABELS, exactly as the consolidation fitted them. Historical, drawn
///     when each point was observed. Nothing is relabelled; there is no
///     oracle anywhere in this fork. It is the quantity the acceptance rule
///     reads.
///   * WORLD is scored on HELD-OUT probes against completion-time truth.
///
/// An earlier draft of the registration said both were taken "against the
/// same completion-time world", which reads as an oracle relabelling of the
/// replay buffer. Astra caught it before the fork was built.
pub const Marks = struct {
    replay: [4]f64 = .{0} ** 4,
    world: [4]f64 = .{0} ** 4,
    k: [4]usize = .{0} ** 4,
    rejected: bool = false,
    at: u64 = 0,
    /// Evidence that `skip` continued the PARENT and not a rebuild of it.
    /// `adopt` zeroes every kernel's `updates` and `t`, so a nonzero maximum
    /// here is a witness that the learning state survived the fork. A gate
    /// asserting it fails the day someone reconstructs the control.
    parent_updates_max: u64 = 0,
    parent_updates_sum: u64 = 0,
    parent_births: u64 = 0,
    /// Whether the refinement STRICTLY lowered replay loss. Acceptance only
    /// establishes non-increase, so this is measured and reported rather
    /// than assumed from the fact that nothing was rejected.
    strict_descent: bool = false,

    pub const PARENT = 0;
    pub const LINEAR = 1;
    pub const ATTEMPTED = 2;
    pub const RETURNED = 3;
    pub const NAMES = [_][]const u8{ "parent", "linear", "attempted", "returned" };
};

/// Observe fresh queries to the horizon, scoring at checkpoints. No further
/// interventions — this is `runArm`'s ordinary tail once a budget is spent,
/// and every branch of a fork runs THIS function, so they cannot differ in
/// the continuation itself.
pub fn continueFrom(
    m: *marl.Model,
    c: Traj,
    worlds: [3]marl.TruthParams,
    probes: [][3]f32,
    vals: [][1]f32,
    win: *Window,
    st: *rng.Stream,
    from: u64,
    pending_in: bool,
    out: *Tally,
) !void {
    var i = from;
    var pending = pending_in;
    // **Births are counted from HERE.** A branch that continues a parent
    // carries that model's whole history in `stats.births`, while an adopted
    // branch starts at zero — so a raw read makes the control look as though
    // it bought topology it acquired long before the fork. OBS-23 paid for
    // this exact class of bug once already, in the other direction.
    const births0 = m.stats.births;
    while (i < c.total) {
        if (pending) {
            pending = false;
            try score(m, c, i, worlds, probes, vals, out);
        }
        const tp = worldAt(c, i, worlds[0], worlds[1], worlds[2]);
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const v: f64 = marl.truthOf(tp, q);
        const ev = try m.observe(q, .{@as(f32, @floatCast(v))});
        win.push(q, v, ev.surprise, ev.cover);
        out.paid += 1;
        out.monitored += 1;
        out.mix(q);
        i += 1;
        if (i % c.check == 0) pending = true;
    }
    if (pending) try score(m, c, i, worlds, probes, vals, out);
    out.k_final = m.kernels.items.len;
    out.births_total += m.stats.births - births0;
    for (m.kernels.items) |kk| out.updates_sum += kk.updates;
}

/// OBS-24's fork. Run one arm to the consolidation at `stop_before`, take the
/// LIVE parent, perform that consolidation ONCE, and continue three branches
/// from it on identical fresh queries.
///
/// `skip` continues the parent object; `linear` and `guarded` are built from
/// the SAME post-linear-refit bytes, so the refinement is the only thing
/// between them. That is a construction guarantee, not a seed-matching one.
pub fn forkThree(
    gpa: std.mem.Allocator,
    o: marl.Options,
    c: Traj,
    at: []const u64,
    worlds: [3]marl.TruthParams,
    probes: [][3]f32,
    seed: u64,
    so_in: Options,
    stop_before: usize,
    out: *[3]Tally,
    marks: *Marks,
) !void {
    var trig = Trigger.init(2048, 16384, c.budget);
    var pre = Tally{};
    var st = rng.Stream.region(seed, 0x4f32_3254, 0);
    var hand = Hand{ .stop_before = stop_before };
    try runArm(gpa, o, c, .{ .at = at }, &trig, worlds, probes, true, &st, &pre, .{}, .{ .revisit = false, .consolidate = true, .guard = true }, &hand);
    std.debug.assert(hand.taken);
    var parent = hand.m;
    var win = hand.win;
    defer win.deinit(gpa);
    marks.at = hand.at;

    const vals = try gpa.alloc([1]f32, probes.len);
    defer gpa.free(vals);
    const now = worldAt(c, hand.at, worlds[0], worlds[1], worlds[2]);
    for (probes, 0..) |pz, k| vals[k] = .{marl.truthOf(now, pz)};

    // The buffer this consolidation fits, selected ONCE and shared by both
    // consolidated branches by construction.
    var buf = try Replay.initWith(gpa, c.n, .err, 0x33);
    defer buf.deinit(gpa);
    win.selectInto(&buf);
    const bx = buf.x[0..c.n];
    const by = buf.y[0..c.n];
    const bv = try gpa.alloc([1]f32, c.n);
    defer gpa.free(bv);
    for (by, 0..) |yv, k| bv[k] = .{@as(f32, @floatCast(yv))};

    for (parent.kernels.items) |kk| {
        marks.parent_updates_max = @max(marks.parent_updates_max, kk.updates);
        marks.parent_updates_sum += kk.updates;
    }
    marks.parent_births = parent.stats.births;
    marks.replay[Marks.PARENT] = try parent.rms(bx, bv, null);
    marks.world[Marks.PARENT] = try parent.rms(probes, vals, null);
    marks.k[Marks.PARENT] = parent.kernels.items.len;

    var so = so_in;
    so.guard = true;
    var rep: Report = undefined;
    var split = Split{};
    defer split.deinit(gpa);
    const keep: usize = parent.kernels.items.len / 2;
    var guarded = try sleepOnReporting(gpa, &parent, bx, by, keep, so, &rep, &split);
    defer guarded.deinit();
    var linear = try adopt(gpa, o, split.linear);
    defer linear.deinit();
    var attempted = try adopt(gpa, o, split.attempted);
    defer attempted.deinit();

    marks.rejected = rep.rejected;
    marks.strict_descent = std.math.isFinite(rep.last) and rep.last < rep.first;
    marks.replay[Marks.LINEAR] = try linear.rms(bx, bv, null);
    marks.world[Marks.LINEAR] = try linear.rms(probes, vals, null);
    marks.k[Marks.LINEAR] = linear.kernels.items.len;
    marks.replay[Marks.ATTEMPTED] = try attempted.rms(bx, bv, null);
    marks.world[Marks.ATTEMPTED] = try attempted.rms(probes, vals, null);
    marks.k[Marks.ATTEMPTED] = attempted.kernels.items.len;
    marks.replay[Marks.RETURNED] = try guarded.rms(bx, bv, null);
    marks.world[Marks.RETURNED] = try guarded.rms(probes, vals, null);
    marks.k[Marks.RETURNED] = guarded.kernels.items.len;

    // Identical fresh queries: one stream state, copied three times.
    const models = [_]*marl.Model{ &parent, &linear, &guarded };
    for (models, 0..) |mm, b| {
        var bst = hand.st;
        // A fresh window per branch. Nothing reads it again — the budget is
        // spent, so no further consolidation selects from it — and the check
        // that this is true is an EXECUTION one: the guarded branch has to
        // reproduce the arm it came from, checkpoint for checkpoint.
        var bwin = try Window.init(gpa, c.w);
        defer bwin.deinit(gpa);
        out[b] = Tally{};
        try continueFrom(mm, c, worlds, probes, vals, &bwin, &bst, hand.at, hand.pending, &out[b]);
    }
    parent.deinit();
}

test "G71 (a) the OBS-24 fork's contracts, with the refinement stubbed" {
    // OBS-23 localised the visible damage on acquisition 5678 to a third
    // consolidation that the guard ACCEPTED — the refinement did not raise
    // replay loss, and the world went to 0.93 at the next checkpoint. OBS-24
    // forks that one consolidation.
    //
    // `tools/obs24_predict.py` holds the registration. This gate holds the
    // contracts, with the refinement stubbed to zero steps, and it is the
    // cheap one: no descent runs at all.
    //
    // **Astra's contract, and the reason a seed is not enough.** `guarded`
    // and `linear` must differ in the refinement and in NOTHING else, so both
    // are built from the same post-linear-refit bytes rather than from two
    // runs of the same seed. With the refinement stubbed the two candidates
    // are identical, and the demand is then the strong one: identical THROUGH
    // CONTINUATION, checkpoint errors included — not merely at adoption.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 2;
    o.responsibility = 3;
    const bounds = [_]u64{ 2_000, 5_000, 6_500, 7_000, 10_000, 12_000 };
    const c = Traj{
        .total = 12_000,
        .r = 1_000,
        .w = 2_000,
        .n = 1_000,
        .check = 500,
        .cold_end = 2_000,
        .change_at = 5_000,
        .drift_lo = 7_000,
        .drift_hi = 10_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const AT = [_]u64{ 6_000, 8_000, 11_000 }; // the deferred arm's shape
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 512);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }

    var tal: [3]Tally = undefined;
    var marks = Marks{};
    // THE STUB: zero descent steps. `refine` then returns the loss it started
    // from, acceptance is trivially satisfied, and the attempted candidate
    // must equal the linear one byte for byte.
    var so = Options{ .exact = true };
    so.steps = 0;
    try forkThree(gpa, o, c, &AT, worlds, pr.p, 5678, so, 2, &tal, &marks);

    const names = [_][]const u8{ "skip", "linear", "guarded" };
    std.debug.print("\n  G71 (a) [{s}] forking the third consolidation at t = {d}, refinement STUBBED to {d} steps\n", .{
        @tagName(builtin.mode), marks.at, so.steps,
    });
    std.debug.print("     {s:<11} {s:>10} {s:>10} {s:>8}\n", .{ "point", "replay", "world", "k" });
    for (Marks.NAMES, 0..) |n, k| std.debug.print("     {s:<11} {d:>10.5} {d:>10.5} {d:>8}\n", .{
        n, marks.replay[k], marks.world[k], marks.k[k],
    });
    std.debug.print("     parent learning state SURVIVED the fork: max kernel updates {d}, births {d} — an `adopt` would have zeroed both\n", .{
        marks.parent_updates_max, marks.parent_births,
    });
    std.debug.print("     {s:<11} {s:>10} {s:>8} {s:>8} {s:>8} {s:>17}\n", .{ "branch", "err_sum", "checks", "k_final", "births", "stream hash" });
    for (names, 0..) |n, b| std.debug.print("     {s:<11} {d:>10.6} {d:>8} {d:>8} {d:>8} {x:>17}\n", .{
        n, tal[b].err_sum, tal[b].checks, tal[b].k_final, tal[b].births_total, tal[b].stream_hash,
    });

    // ── THE FORK POINT. The arm must have been stopped before its third
    // consolidation, at the placement the registration names.
    try testing.expectEqual(AT[2], marks.at);

    // ── THE PARENT'S LEARNING STATE SURVIVED. `adopt` zeroes every kernel's
    // `updates`, so a nonzero maximum witnesses that `skip` continues the
    // real parent. This assertion fails the day someone rebuilds the control.
    try testing.expect(marks.parent_updates_max > 0);
    try testing.expect(marks.parent_births > 0);
    // The scale-free form, and the one that actually catches a rebuild:
    // `adopt` zeroes every kernel's counter, so a branch that CONTINUED the
    // parent must carry at least the parent's summed updates forward, while
    // the two adopted branches must carry FEWER than that — nothing dies
    // without a consolidation, so the sum can only grow along a branch.
    try testing.expect(tal[0].updates_sum >= marks.parent_updates_sum);
    try testing.expect(tal[1].updates_sum < marks.parent_updates_sum);
    try testing.expect(tal[2].updates_sum < marks.parent_updates_sum);
    std.debug.print("     updates: parent {d} at the fork; skip carries {d} forward, the adopted branches {d} — a rebuild of the control would drop to the latter\n", .{
        marks.parent_updates_sum, tal[0].updates_sum, tal[1].updates_sum,
    });

    // ── THE STUB IS A NO-OP, so the two consolidated branches adopt the same
    // kernels — and the demand is that they stay identical THROUGH the
    // continuation, not merely at adoption.
    try testing.expect(!marks.rejected);
    try testing.expect(!marks.strict_descent);
    try testing.expectEqual(marks.replay[Marks.LINEAR], marks.replay[Marks.ATTEMPTED]);
    try testing.expectEqual(marks.world[Marks.LINEAR], marks.world[Marks.ATTEMPTED]);
    try testing.expectEqual(marks.replay[Marks.LINEAR], marks.replay[Marks.RETURNED]);
    try testing.expectEqual(marks.world[Marks.LINEAR], marks.world[Marks.RETURNED]);
    try testing.expectEqual(marks.k[Marks.LINEAR], marks.k[Marks.RETURNED]);
    try testing.expectEqual(tal[1].err_sum, tal[2].err_sum);
    try testing.expectEqual(tal[1].check_err, tal[2].check_err);
    try testing.expectEqual(tal[1].k_final, tal[2].k_final);
    try testing.expectEqual(tal[1].births_total, tal[2].births_total);
    std.debug.print("     stubbed: linear and guarded identical at every checkpoint, not merely at adoption\n", .{});

    // ── IDENTICAL FRESH QUERIES. All three branches continue from one stream
    // state, so the locations and their order match across branches — skip
    // included, even though nothing else about it need match.
    try testing.expectEqual(tal[0].stream_hash, tal[1].stream_hash);
    try testing.expectEqual(tal[0].stream_hash, tal[2].stream_hash);
    try testing.expectEqual(tal[0].checks, tal[1].checks);
    try testing.expectEqual(tal[0].paid, tal[2].paid);
    try testing.expectEqual(c.total - marks.at, tal[0].paid);

    // ── AND SKIP IS A DIFFERENT BRANCH. If it matched the consolidated ones
    // the fork would not be forking anything.
    try testing.expect(tal[0].err_sum != tal[1].err_sum);
    std.debug.print("     skip continues the parent and diverges from both consolidated branches, on the same {d} fresh queries\n", .{tal[0].paid});

    // ── THE TWO MEASURES HAVE DIFFERENT LABELS. Replay is scored on the
    // buffer's OWN stored labels, world on held-out probes against
    // completion-time truth. Nothing is relabelled and no oracle is used, so
    // the two are not required to agree and must not be read as one number.
    std.debug.print("     replay is the buffer's OWN historical labels; world is held-out probes against completion-time truth. No relabelling anywhere\n", .{});
}

test "G71 forking the consolidation that failed" {
    // OBS-23 localised the visible damage on acquisition 5678 to the THIRD
    // consolidation of `sleep@t+r`, at t = 94 096: the checkpoint before it
    // read 0.16067 and the one after read 0.92824, with ZERO guard
    // rejections — so the refinement did not raise replay loss.
    //
    // OBS-22 recorded that recovery from a REJECTED refinement establishes
    // nothing about an accepted one. This forks that single consolidation
    // and asks directly. `tools/obs24_predict.py` holds the registration;
    // G71 (a) holds the contracts and runs in seconds.
    //
    // **What is already known is narrow.** The world was worse at the next
    // checkpoint, 1904 observations later. Whether the returned candidate
    // was worse AT THE INSTANT IT WAS ADOPTED is Q2; whether the refinement
    // is what made it worse is Q1. Both are predictions, not premises.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 3;
    o.responsibility = 3;
    const bounds = [_]u64{ 12_000, 30_000, 48_000, 60_000, 90_000, 104_000 };
    const c = Traj{
        .total = 104_000,
        .r = 4_096,
        .w = 16_384,
        .n = 8_192,
        .check = 2_000,
        .cold_end = 12_000,
        .change_at = 30_000,
        .drift_lo = 60_000,
        .drift_hi = 90_000,
        .budget = 3,
        .bounds = &bounds,
    };
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 2048);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }
    const deferred = [_]u64{ 34_096, 64_096, 94_096 };

    var tal: [3]Tally = undefined;
    var marks = Marks{};
    try forkThree(gpa, o, c, &deferred, worlds, pr.p, 5678, .{ .exact = true }, 2, &tal, &marks);

    const names = [_][]const u8{ "skip", "linear", "guarded" };
    const SKIP = 0;
    const LIN = 1;
    const GRD = 2;

    // ── EVERYTHING IS PRINTED BEFORE ANYTHING IS ASSERTED. A refuted
    // prediction must still leave its table behind — OBS-19 lost a
    // ten-minute run to an assertion inside the loop that produced its
    // numbers, and this gate's whole value is the eight measurements below.
    std.debug.print("\n  G71 [{s}] forking sleep@t+r / acq 5678 at its THIRD consolidation, t = {d}\n", .{
        @tagName(builtin.mode), marks.at,
    });
    std.debug.print("     THE FOUR POINTS. Replay is scored on the selected buffer's OWN HISTORICAL LABELS, exactly as the consolidation fitted them.\n", .{});
    std.debug.print("     World is held-out probes against completion-time truth at t = {d}, past drift_hi and therefore STATIONARY — so no part of\n", .{marks.at});
    std.debug.print("     any world difference is the world moving. Nothing is relabelled; there is no oracle anywhere in this fork.\n", .{});
    std.debug.print("     {s:<11} {s:>12} {s:>12} {s:>8}\n", .{ "point", "replay", "world", "k" });
    for (Marks.NAMES, 0..) |n, k| std.debug.print("     {s:<11} {d:>12.5} {d:>12.5} {d:>8}\n", .{
        n, marks.replay[k], marks.world[k], marks.k[k],
    });
    std.debug.print("     acceptance: rejected {}, and the refinement's replay change was {s} — acceptance establishes NON-INCREASE, never descent\n", .{
        marks.rejected, if (marks.strict_descent) "a STRICT decrease" else "not a strict decrease",
    });
    std.debug.print("     the parent's learning state entered the fork intact: {d} summed kernel updates, {d} births. `skip` continues THAT object\n", .{
        marks.parent_updates_sum, marks.parent_births,
    });

    std.debug.print("     THE CONTINUATIONS, identical fresh queries, {d} observations to the horizon\n", .{c.total - marks.at});
    std.debug.print("     {s:<11} {s:>10} {s:>10} {s:>10} {s:>10} {s:>10}   {s:>10} {s:>10}\n", .{
        "branch", "96000", "98000", "100000", "102000", "104000", "max", "mean",
    });
    var mx: [3]f64 = .{0} ** 3;
    var mn: [3]f64 = .{0} ** 3;
    for (0..3) |b| {
        std.debug.print("     {s:<11}", .{names[b]});
        for (tal[b].check_err[0..tal[b].checks]) |e| {
            std.debug.print(" {d:>10.5}", .{e});
            mx[b] = @max(mx[b], e);
            mn[b] += e;
        }
        mn[b] /= @as(f64, @floatFromInt(@max(1, tal[b].checks)));
        std.debug.print("   {d:>10.5} {d:>10.5}\n", .{ mx[b], mn[b] });
    }
    std.debug.print("     guarded at FULL precision, so a later comparison can be exact rather than to 1e-5:\n       ", .{});
    for (tal[GRD].check_err[0..tal[GRD].checks]) |e| std.debug.print(" {d:.12}", .{e});
    std.debug.print("\n", .{});
    std.debug.print("     UNREGISTERED, from the same four points: BOTH STAGES REDUCED HISTORICAL REPLAY RMS WHILE INCREASING CURRENT-WORLD RMS.\n", .{});
    std.debug.print("     The first stage BUNDLES compression, kernel selection and the linear refit — this fork does not separate them. And the second\n", .{});
    std.debug.print("     increase being larger is a RATIO OF TWO RMS INCREASES: not field disagreement, and not evidence of a shared mechanism.\n", .{});
    std.debug.print("       selection + compression + linear refit: replay {d:.5} -> {d:.5}, world {d:.5} -> {d:.5} ({d:.5} worse)\n", .{
        marks.replay[Marks.PARENT],                            marks.replay[Marks.LINEAR],
        marks.world[Marks.PARENT],                             marks.world[Marks.LINEAR],
        marks.world[Marks.LINEAR] - marks.world[Marks.PARENT],
    });
    std.debug.print("       the refinement on top:                  replay {d:.5} -> {d:.5}, world {d:.5} -> {d:.5} ({d:.5} worse)\n", .{
        marks.replay[Marks.LINEAR],                               marks.replay[Marks.ATTEMPTED],
        marks.world[Marks.LINEAR],                                marks.world[Marks.ATTEMPTED],
        marks.world[Marks.ATTEMPTED] - marks.world[Marks.LINEAR],
    });
    std.debug.print("     births below are the CONTINUATION's only, on a common baseline — the control carries its model's whole history in\n", .{});
    std.debug.print("     `stats.births` while an adopted branch starts at zero, so a raw read would credit the control with topology it bought long before the fork.\n", .{});
    std.debug.print("     {s:<11} {s:>10} {s:>10} {s:>12}\n", .{ "branch", "k_final", "births", "updates" });
    for (0..3) |b| std.debug.print("     {s:<11} {d:>10} {d:>10} {d:>12}\n", .{
        names[b], tal[b].k_final, tal[b].births_total, tal[b].updates_sum,
    });

    const q1 = marks.world[Marks.ATTEMPTED] - marks.world[Marks.LINEAR];
    const q2 = marks.world[Marks.RETURNED] - marks.world[Marks.PARENT];
    std.debug.print("     VERDICT\n", .{});
    std.debug.print("       Q1  world(attempted) - world(linear)     registered > 0      measured {d:.5}   {s}\n", .{ q1, if (q1 > 0) "HELD" else "REFUTED" });
    std.debug.print("       Q2  world(returned) - world(parent)      registered > 0      measured {d:.5}   {s}\n", .{ q2, if (q2 > 0) "HELD" else "REFUTED" });
    std.debug.print("       Q3  max(linear) < max(guarded)           {d:.5} vs {d:.5}   {s}\n", .{ mx[LIN], mx[GRD], if (mx[LIN] < mx[GRD]) "HELD" else "REFUTED" });
    std.debug.print("       Q4  max(skip) < max(guarded), and < {d:.2}  {d:.5} vs {d:.5}   {s} / {s}\n", .{
        thresholds.OBS24_SKIP_CEILING,                 mx[SKIP],                                                            mx[GRD],
        if (mx[SKIP] < mx[GRD]) "HELD" else "REFUTED", if (mx[SKIP] < thresholds.OBS24_SKIP_CEILING) "HELD" else "REFUTED",
    });
    std.debug.print("       Q5  guarded(104000) > skip(104000)       {d:.5} vs {d:.5}   {s}\n", .{
        tal[GRD].check_err[4],                                                     tal[SKIP].check_err[4],
        if (tal[GRD].check_err[4] > tal[SKIP].check_err[4]) "HELD" else "REFUTED",
    });
    std.debug.print("       Q6  mean(linear) < mean(skip)            {d:.5} vs {d:.5}   {s}\n", .{ mn[LIN], mn[SKIP], if (mn[LIN] < mn[SKIP]) "HELD" else "REFUTED" });
    std.debug.print("     Q3 and Q4's maxima are maxima OVER THESE FIVE CHECKPOINTS. The model is unobserved for 2000 observations at a time and\n", .{});
    std.debug.print("     they cannot exclude an excursion between them.\n", .{});
    std.debug.print("     THE GUARD BEHAVED EXACTLY AS SPECIFIED: the refinement did not raise replay loss, so accepting it was correct. What this\n", .{});
    std.debug.print("     establishes is about the CRITERION — replay non-increase is INSUFFICIENT for current-world protection — while it remains\n", .{});
    std.debug.print("     useful against optimisation that worsens its own objective, which is the OBS-22 failure it was introduced to prevent.\n", .{});
    std.debug.print("     SCOPE: ONE consolidation, ONE trajectory, and the conclusion is CONDITIONAL ON THE PARENT THE EARLIER SLEEPS PRODUCED.\n", .{});
    std.debug.print("     The first two sleeps are neither exonerated nor implicated — they built the state that fails here.\n", .{});

    // ── HARNESS CONTRACTS ────────────────────────────────────────────────
    try testing.expectEqual(deferred[2], marks.at);
    try testing.expectEqual(@as(usize, 5), tal[GRD].checks);
    // The guarded branch IS OBS-23's arm, so it must reproduce that arm's
    // remaining checkpoints. A TOLERANCE, not exact agreement: the recorded
    // values are rounded to five decimals and full precision was never
    // written down.
    for (thresholds.OBS24_ARM_TAIL, 0..) |want, k| {
        try testing.expect(@abs(tal[GRD].check_err[k] - want) < thresholds.OBS24_REPRO_TOL);
    }
    // Acceptance gives NON-INCREASE of replay loss, and no more.
    try testing.expect(marks.replay[Marks.ATTEMPTED] <= marks.replay[Marks.LINEAR]);
    try testing.expect(!marks.rejected);
    // The control continued the parent; the two consolidated branches were
    // adopted. `adopt` zeroes every kernel's counter, so this separates them
    // at any scale.
    try testing.expect(tal[SKIP].updates_sum >= marks.parent_updates_sum);
    try testing.expect(tal[LIN].updates_sum < marks.parent_updates_sum);
    // Identical fresh queries across all three branches.
    try testing.expectEqual(tal[SKIP].stream_hash, tal[LIN].stream_hash);
    try testing.expectEqual(tal[SKIP].stream_hash, tal[GRD].stream_hash);
    try testing.expectEqual(c.total - marks.at, tal[SKIP].paid);

    // ── THE REGISTERED PREDICTIONS ───────────────────────────────────────
    try testing.expect(q1 > thresholds.OBS24_WORLD_RISES);
    try testing.expect(q2 > thresholds.OBS24_IMMEDIATE);
    try testing.expect(mx[LIN] < mx[GRD]);
    try testing.expect(mx[SKIP] < mx[GRD]);
    try testing.expect(mx[SKIP] < thresholds.OBS24_SKIP_CEILING);
    try testing.expect(tal[GRD].check_err[4] > tal[SKIP].check_err[4]);
    // Q6 is REGISTERED AND REFUTED and is deliberately NOT asserted. A
    // threshold is not tuned to make a gate pass; the finding is recorded and
    // the prediction left standing in `thresholds.zig` for Christian.
}

/// OBS-25's frozen acceptance criterion, written before any decision of its
/// is compared with a diagnostic probe.
///
///     adopt the candidate with the LOWEST validation RMS;
///     on ANY tie, prefer the earlier of parent < linear < refined.
///
/// The strict `<` is what makes the tie rule total: a later candidate must be
/// STRICTLY better to displace an earlier one, so every tie — including
/// `linear` and `refined` tying below `parent` — resolves toward the
/// least-changed candidate. An earlier draft said "prefer the parent on a
/// tie", which named no winner in exactly that case (Astra).
pub fn decide(rms: [3]f64) usize {
    var best: usize = 0;
    for (1..3) |i| {
        if (rms[i] < rms[best]) best = i;
    }
    return best;
}

pub const CAND_PARENT = 0;
pub const CAND_LINEAR = 1;
pub const CAND_REFINED = 2;
pub const CAND_NAMES = [_][]const u8{ "parent", "linear", "refined" };
pub const FAMILY_NAMES = [_][]const u8{ "held-out replay", "recent window", "fresh" };

/// Everything OBS-25 measures at the fork, before any continuation.
pub const Val = struct {
    at: u64 = 0,
    decide_at: u64 = 0,
    /// Buffer accounting. `fit + excluded` must equal the selected buffer,
    /// and the fit must contain NO validation point.
    n_buffer: usize = 0,
    n_fit: usize = 0,
    n_heldout: usize = 0,
    n_recent: usize = 0,
    n_recent_in_buffer: usize = 0,
    /// Fit points matching a validation point of EITHER family, found by an
    /// independent pass over the built sets rather than counted inside the
    /// loop that builds them — a counter incremented where the `continue`
    /// already happened can only restate the construction, never check it.
    overlap_fit_val: usize = 0,
    /// The DIAGNOSTIC ordering, measured for THESE candidates and never
    /// asserted from OBS-24's — they are fitted on a smaller buffer and are
    /// a different consolidation.
    world: [3]f64 = .{0} ** 3,
    /// Each family's RMS over the three candidates, and what the frozen rule
    /// picks from it.
    fam: [3][3]f64 = .{.{0} ** 3} ** 3,
    pick: [3]usize = .{0} ** 3,
    /// K independent FRESH draws on the FROZEN candidates, so a failure to
    /// recover the diagnostic order separates "the signal cannot order
    /// these" from "this draw did not".
    draw_pick: [16]usize = .{0} ** 16,
    draws: usize = 0,
    /// Summed kernel updates over the three candidates, before and after all
    /// scoring. Validation SCORES and never observes, so these must match —
    /// a historical family must not receive a second training pass.
    updates_before: u64 = 0,
    updates_after: u64 = 0,
};

/// OBS-25's fork. One shared candidate set that every validation family is
/// genuinely held out of, and three families scored on it.
///
/// **The construction is the whole experiment.** OBS-24's candidates were
/// fitted on the WHOLE selected buffer, so a split taken afterwards is not
/// held out of anything — Astra caught that in the first registration. Here
/// the validation entries are removed BEFORE selection, the linear refit and
/// the refinement, so one candidate set serves every family. They are
/// therefore NEW candidates on a smaller buffer, and their diagnostic
/// ordering is MEASURED rather than carried over from OBS-24.
pub fn validateFork(
    gpa: std.mem.Allocator,
    o: marl.Options,
    c: Traj,
    at: []const u64,
    worlds: [3]marl.TruthParams,
    probes: [][3]f32,
    seed: u64,
    so_in: Options,
    stop_before: usize,
    v: usize,
    draws: usize,
    out: *Val,
    cands: *[3]marl.Model,
    hand_out: *Hand,
) !void {
    var trig = Trigger.init(2048, 16384, c.budget);
    var pre = Tally{};
    var st = rng.Stream.region(seed, 0x4f32_3254, 0);
    var hand = Hand{ .stop_before = stop_before };
    try runArm(gpa, o, c, .{ .at = at }, &trig, worlds, probes, true, &st, &pre, .{}, .{ .revisit = false, .consolidate = true, .guard = true }, &hand);
    std.debug.assert(hand.taken);
    var parent = hand.m;
    var win = hand.win;
    defer win.deinit(gpa);
    out.at = hand.at;
    out.decide_at = hand.at + v;

    // ── THE RECENT-WINDOW FAMILY, identified EXACTLY by observation time.
    // The window stores `t` per slot, so "the V most recent" needs no
    // coordinate matching and cannot accidentally catch an older duplicate.
    const cut = hand.at - @as(u64, v);
    const rx = try gpa.alloc([3]f32, v);
    defer gpa.free(rx);
    const rv = try gpa.alloc([1]f32, v);
    defer gpa.free(rv);
    {
        var got: usize = 0;
        const f = win.filled();
        const start = win.n - @as(u64, f);
        var i: u64 = 0;
        while (i < f and got < v) : (i += 1) {
            const j: usize = @intCast((start + i) % @as(u64, win.x.len));
            if (win.t[j] < cut) continue;
            rx[got] = win.x[j];
            rv[got] = .{@as(f32, @floatCast(win.y[j]))};
            got += 1;
        }
        out.n_recent = got;
    }

    // ── THE SELECTED BUFFER, then the two exclusions.
    var buf = try Replay.initWith(gpa, c.n, .err, 0x33);
    defer buf.deinit(gpa);
    win.selectInto(&buf);
    out.n_buffer = c.n;

    const fx = try gpa.alloc([3]f32, c.n);
    defer gpa.free(fx);
    const fy = try gpa.alloc(f64, c.n);
    defer gpa.free(fy);
    const hx = try gpa.alloc([3]f32, v);
    defer gpa.free(hx);
    const hv = try gpa.alloc([1]f32, v);
    defer gpa.free(hv);
    var nfit: usize = 0;
    var nheld: usize = 0;
    {
        // Every buffer entry observed at or after the cut belongs to the
        // RECENT family and is excluded from the fit. Of the rest, every
        // `stride`-th is designated HELD-OUT REPLAY, also excluded. What
        // remains is the fit, and it contains no validation point at all.
        var eligible: usize = 0;
        for (0..c.n) |k| {
            if (buf.t[k] >= cut) {
                out.n_recent_in_buffer += 1;
                continue;
            }
            eligible += 1;
        }
        const stride = @max(1, eligible / @max(1, v));
        var seen: usize = 0;
        for (0..c.n) |k| {
            if (buf.t[k] >= cut) continue; // recent: excluded, scored by that family
            if (nheld < v and seen % stride == 0) {
                hx[nheld] = buf.x[k];
                hv[nheld] = .{@as(f32, @floatCast(buf.y[k]))};
                nheld += 1;
            } else {
                fx[nfit] = buf.x[k];
                fy[nfit] = buf.y[k];
                nfit += 1;
            }
            seen += 1;
        }
    }
    out.n_fit = nfit;
    out.n_heldout = nheld;
    // An INDEPENDENT pass: does any fit point coincide with a validation
    // point of either family? This checks the construction rather than
    // restating it.
    for (fx[0..nfit]) |fp| {
        for (hx[0..nheld]) |vp| {
            if (fp[0] == vp[0] and fp[1] == vp[1] and fp[2] == vp[2]) out.overlap_fit_val += 1;
        }
        for (rx[0..out.n_recent]) |vp| {
            if (fp[0] == vp[0] and fp[1] == vp[1] and fp[2] == vp[2]) out.overlap_fit_val += 1;
        }
    }

    // ── ONE SHARED CANDIDATE SET, fitted on the reduced buffer.
    var so = so_in;
    so.guard = true;
    var rep: Report = undefined;
    var split = Split{};
    defer split.deinit(gpa);
    const keep: usize = parent.kernels.items.len / 2;
    cands[CAND_REFINED] = try sleepOnReporting(gpa, &parent, fx[0..nfit], fy[0..nfit], keep, so, &rep, &split);
    cands[CAND_LINEAR] = try adopt(gpa, o, split.linear);
    cands[CAND_PARENT] = parent;

    for (cands) |*m| for (m.kernels.items) |kk| {
        out.updates_before += kk.updates;
    };

    // ── THE DIAGNOSTIC, measured for THESE candidates. An oracle, used only
    // to judge decisions after they are made and never offered to the rule.
    const pv = try gpa.alloc([1]f32, probes.len);
    defer gpa.free(pv);
    const dw = worldAt(c, out.decide_at, worlds[0], worlds[1], worlds[2]);
    for (probes, 0..) |pz, k| pv[k] = .{marl.truthOf(dw, pz)};
    for (cands, 0..) |*m, k| out.world[k] = try m.rms(probes, pv, null);

    // ── THE THREE FAMILIES. Historical ones are SCORED, never observed.
    for (cands, 0..) |*m, k| {
        out.fam[0][k] = try m.rms(hx[0..nheld], hv[0..nheld], null);
        out.fam[1][k] = try m.rms(rx[0..out.n_recent], rv[0..out.n_recent], null);
    }

    // ── FRESH: PAID queries occupying [at, at + v), advancing the common
    // clock. Candidates stay frozen while they are collected and scored.
    const qx = try gpa.alloc([3]f32, v);
    defer gpa.free(qx);
    const qv = try gpa.alloc([1]f32, v);
    defer gpa.free(qv);
    for (0..v) |j| {
        const tp = worldAt(c, hand.at + j, worlds[0], worlds[1], worlds[2]);
        qx[j] = .{ st.unit(), st.unit(), st.unit() };
        qv[j] = .{marl.truthOf(tp, qx[j])};
    }
    for (cands, 0..) |*m, k| out.fam[2][k] = try m.rms(qx, qv, null);
    for (0..3) |f| out.pick[f] = decide(out.fam[f]);

    // ── K INDEPENDENT FRESH DRAWS on the FROZEN candidates. Draw 0 is the
    // paid family above; the rest are a VARIABILITY DIAGNOSTIC and are not a
    // policy — taking them all would cost `draws * v` observations.
    out.draw_pick[0] = out.pick[2];
    var d: usize = 1;
    var dst = st;
    while (d < draws and d < out.draw_pick.len) : (d += 1) {
        for (0..v) |j| {
            qx[j] = .{ dst.unit(), dst.unit(), dst.unit() };
            qv[j] = .{marl.truthOf(dw, qx[j])};
        }
        var r: [3]f64 = undefined;
        for (cands, 0..) |*m, k| r[k] = try m.rms(qx, qv, null);
        out.draw_pick[d] = decide(r);
    }
    out.draws = d;

    for (cands) |*m| for (m.kernels.items) |kk| {
        out.updates_after += kk.updates;
    };
    hand_out.* = hand;
    hand_out.st = st; // advanced past the V paid queries
}

test "G72 (a) the OBS-25 validation fork's contracts" {
    // OBS-24 established that replay non-increase is insufficient for
    // current-world protection. OBS-25 asks the narrower prior question: do
    // historical validation evidence and two sources of current-labelled
    // evidence RANK A COMMON candidate set differently?
    //
    // `tools/obs25_predict.py` holds the registration. This gate holds the
    // contracts — and the first draft of that registration had three that
    // could not be satisfied, all found by Astra before any code existed:
    //
    //   * a held-out split taken AFTER a fit is not held out of it. The
    //     validation entries are now removed BEFORE selection, the linear
    //     refit and the refinement, so one shared candidate set serves every
    //     family — and those are NEW candidates whose diagnostic ordering is
    //     measured, never carried over.
    //   * `recent` already carries CURRENT-WORLD labels on this fixture, so
    //     fresh is not the only current-labelled family. What recent and
    //     fresh differ in is prior learning exposure and location sampling.
    //   * fresh queries are PAID and occupy a SPAN, not an instant.
    const gpa = testing.allocator;
    var o = marl.Options{};
    o.regions = 2;
    o.responsibility = 3;
    const bounds = [_]u64{ 2_000, 5_000, 6_500, 7_000, 10_000, 12_000 };
    const c = Traj{
        .total = 12_000,
        .r = 1_000,
        .w = 2_000,
        .n = 1_000,
        .check = 500,
        .cold_end = 2_000,
        .change_at = 5_000,
        .drift_lo = 7_000,
        .drift_hi = 10_000,
        .budget = 3,
        .bounds = &bounds,
    };
    // The placements must leave NO CHECKPOINT inside the validation span,
    // or a score would land on a candidate about to be replaced. 10 900 is
    // not a multiple of `check`, and neither is anything in [10 900, 10 964).
    // The registered fixture satisfies this too — 94 096 % 2000 = 96 — and
    // the gate ASSERTS it rather than relying on the arithmetic holding.
    const AT = [_]u64{ 6_000, 8_000, 10_900 };
    const V: usize = 64;
    const DRAWS: usize = 8;
    const wa = marl.TruthParams{};
    var wb = marl.TruthParams{};
    wb.shift = .{ 0, -0.10, 0 };
    var wc = marl.TruthParams{};
    wc.shift = .{ 0.12, 0, 0.22 };
    const worlds = [3]marl.TruthParams{ wa, wb, wc };
    const pr = try marl.probesOf(gpa, wb, 31337, 512);
    defer {
        gpa.free(pr.p);
        gpa.free(pr.y);
    }

    var val = Val{};
    var cands: [3]marl.Model = undefined;
    var hand: Hand = undefined;
    var so = Options{ .exact = true };
    so.steps = 0; // the refinement stubbed: this gate tests structure
    try validateFork(gpa, o, c, &AT, worlds, pr.p, 5678, so, 2, V, DRAWS, &val, &cands, &hand);
    defer for (&cands) |*m| m.deinit();

    std.debug.print("\n  G72 (a) [{s}] validation fork at t = {d}, deciding at {d}; V = {d}, {d} draws, refinement STUBBED\n", .{
        @tagName(builtin.mode), val.at, val.decide_at, V, val.draws,
    });
    std.debug.print("     buffer {d} = fit {d} + held-out {d} + recent-in-buffer {d}; recent family {d}; fit/validation overlap {d} (independent pass)\n", .{
        val.n_buffer, val.n_fit, val.n_heldout, val.n_recent_in_buffer, val.n_recent, val.overlap_fit_val,
    });
    std.debug.print("     {s:<16} {s:>10} {s:>10} {s:>10}   {s}\n", .{ "family", "parent", "linear", "refined", "picks" });
    std.debug.print("     {s:<16} {d:>10.5} {d:>10.5} {d:>10.5}   {s}\n", .{ "DIAGNOSTIC world", val.world[0], val.world[1], val.world[2], CAND_NAMES[decide(val.world)] });
    for (FAMILY_NAMES, 0..) |fn_, f| std.debug.print("     {s:<16} {d:>10.5} {d:>10.5} {d:>10.5}   {s}\n", .{
        fn_, val.fam[f][0], val.fam[f][1], val.fam[f][2], CAND_NAMES[val.pick[f]],
    });
    std.debug.print("     fresh draws on the FROZEN candidates:", .{});
    for (val.draw_pick[0..val.draws]) |p| std.debug.print(" {s}", .{CAND_NAMES[p]});
    std.debug.print("\n", .{});

    // ── THE EXCLUSION IS REAL, not nominal. Every buffer entry is either in
    // the fit, designated held-out, or recent — and the fit contains no
    // validation point of any family.
    try testing.expectEqual(val.n_buffer, val.n_fit + val.n_heldout + val.n_recent_in_buffer);
    try testing.expect(val.n_fit > 0);
    try testing.expectEqual(V, val.n_heldout);
    try testing.expectEqual(V, val.n_recent);
    try testing.expectEqual(@as(usize, 0), val.overlap_fit_val);
    try testing.expect(val.n_fit < val.n_buffer);

    // ── VALIDATION SCORES AND NEVER OBSERVES. A historical family must not
    // receive a second training pass — its points were learned from when
    // they arrived.
    try testing.expectEqual(val.updates_before, val.updates_after);

    // ── THE CLOCK. The fresh queries occupy a SPAN and the decision is at
    // its end; no checkpoint may fall inside it, or a score would land on a
    // candidate that is about to be replaced.
    try testing.expectEqual(val.at + @as(u64, V), val.decide_at);
    var k = val.at;
    while (k < val.decide_at) : (k += 1) try testing.expect(k % c.check != 0);
    try testing.expect(val.decide_at < c.total);

    // ── THE FROZEN CRITERION IS TOTAL. Every tie resolves toward the
    // least-changed candidate, including the case an earlier draft left
    // unspecified: linear and refined tying BELOW the parent.
    try testing.expectEqual(@as(usize, CAND_PARENT), decide(.{ 1.0, 1.0, 1.0 }));
    try testing.expectEqual(@as(usize, CAND_LINEAR), decide(.{ 2.0, 1.0, 1.0 }));
    try testing.expectEqual(@as(usize, CAND_PARENT), decide(.{ 1.0, 2.0, 2.0 }));
    try testing.expectEqual(@as(usize, CAND_REFINED), decide(.{ 2.0, 2.0, 1.0 }));
    try testing.expectEqual(@as(usize, CAND_LINEAR), decide(.{ 2.0, 1.0, 3.0 }));
    std.debug.print("     the criterion is TOTAL: ties resolve toward the least-changed candidate, including linear and refined tying below parent\n", .{});

    // ── THE STUB. With zero descent steps the refinement is a no-op, so
    // `refined` and `linear` must be the same model — and every family must
    // therefore score them identically and be UNABLE to separate them. That
    // is the structural check that the two candidates really do share a fit.
    try testing.expectEqual(val.world[CAND_LINEAR], val.world[CAND_REFINED]);
    for (0..3) |f| try testing.expectEqual(val.fam[f][CAND_LINEAR], val.fam[f][CAND_REFINED]);
    // And the tie rule then makes every family prefer `linear` over
    // `refined` — never the other way — whichever of them wins.
    for (0..3) |f| try testing.expect(val.pick[f] != CAND_REFINED);
    std.debug.print("     stubbed: linear and refined are one model, every family scores them identically, and the tie rule never picks refined\n", .{});

    // ── THE VARIABILITY DIAGNOSTIC EXISTS and is separate from the paid
    // family. Draw 0 IS the paid one; the rest are hypothetical, and taking
    // them all would cost {d} observations rather than {d}.
    try testing.expectEqual(DRAWS, val.draws);
    try testing.expectEqual(val.pick[2], val.draw_pick[0]);
    std.debug.print("     draw 0 is the PAID family; the other {d} are a variability diagnostic and not a policy — taking them all would cost {d} observations, not {d}\n", .{
        val.draws - 1, val.draws * V, V,
    });

    // ── AND THE DIAGNOSTIC IS MEASURED, NOT CARRIED OVER. These candidates
    // are fitted on a reduced buffer and are a different consolidation from
    // OBS-24's; nothing here asserts 0.16446 / 0.27473 / 0.86959.
    for (val.world) |wv| try testing.expect(std.math.isFinite(wv) and wv > 0);
    std.debug.print("     the diagnostic ordering is MEASURED for these reduced-fit candidates; OBS-24's figures are context and are asserted nowhere\n", .{});
}
