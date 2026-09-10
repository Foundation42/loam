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
    /// Whether the geometry may move at all. False refines only the
    /// weights, which is the refit OBS-10's arms already had, and is the
    /// control that says the win came from SYNTHESIS rather than from a
    /// better weight solve.
    geometry: bool = true,
};

pub const Report = struct {
    /// Training RMS at the first and last step — the null: a descent that
    /// does not descend is not the thing being measured.
    first: f64,
    last: f64,
    /// Kernels whose cutoff box outgrew one region edge. The gather's
    /// exactness rests on that bound, so it is counted and never hidden;
    /// G44 (b) found the same failure in the affine warp and reported it
    /// rather than correcting it.
    over_reach: u32,
};

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

    const h = 1.0 / @as(f32, @floatFromInt(regions));
    const sigma_min = h / 64.0;
    var rep = Report{ .first = rmsAt(ks, pts, target), .last = 0, .over_reach = 0 };

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
                const gp = acc[i * P + p] * scale;
                const j = i * P + p;
                m1[j] = 0.9 * m1[j] + 0.1 * gp;
                m2[j] = 0.999 * m2[j] + 0.001 * gp * gp;
                k.p[p] += lr * (m1[j] / c1) / (@sqrt(m2[j] / c2) + 1e-8);
            }
            // THE CLAMP, and it is not optional. `marl.Model.clamp`'s,
            // reproduced because it is private and because a consolidation
            // that skips it is not producing a MARL.
            //
            // The first version bounded sigma per axis at h and stopped
            // there, which is a far looser thing than bounding the
            // ellipsoid's infinity-norm REACH: off-diagonals can make the
            // cutoff box much larger than any single width. Run that way
            // the descent reached RMS 0.00176 against the full basis's
            // 0.04887 — a thirty-fold "win" with 359 of 468 kernels
            // outgrowing the gather. It had left the family, and the
            // registered null is what caught it.
            inline for (0..3) |a| {
                const lo_log = -@log(h);
                const hi_log = -@log(sigma_min);
                k.p[3 + a] = @min(hi_log, @max(lo_log, k.p[3 + a]));
                k.p[a] = @min(1, @max(0, k.p[a]));
            }
            const off_cap = 1 / sigma_min;
            inline for (0..3) |a| k.p[6 + a] = @min(off_cap, @max(-off_cap, k.p[6 + a]));
            // L ← fL shrinks every half-extent by f. It LOOPS rather than
            // storing min(reach, h) for the reason MARL's own clamp does:
            // the exactness the gather rests on is a property of the
            // geometry, not of what a field was set to afterwards.
            var sh = k.shape();
            var reach = marl.reachOf(sh);
            var guard: u8 = 0;
            while (reach > h and guard < 16) : (guard += 1) {
                const f = @max(1.001, reach / h);
                const lf = @log(f);
                inline for (0..3) |a| k.p[3 + a] += lf;
                inline for (0..3) |a| k.p[6 + a] *= f;
                sh = k.shape();
                reach = marl.reachOf(sh);
            }
            k.reach = reach;
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
