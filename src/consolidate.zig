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
};

pub const Report = struct {
    /// Training RMS at the first and last step — the null: a descent that
    /// does not descend is not the thing being measured.
    first: f64,
    last: f64,
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
            mark, parent.kernels.items.len, parent.stats.births - pb0, p_rms[mi], parent.meanUpdates(),
            child.kernels.items.len,        child.stats.births - cb0, c_rms[mi],  child.meanUpdates(),
        });
    }
    const last = marks.len - 1;
    const regrowth = @as(f64, @floatFromInt(child.kernels.items.len)) / @as(f64, @floatFromInt(c0));
    std.debug.print("  child regrew {d:.3}x its post-sleep size, to {d:.3} of the parent's\n", .{
        regrowth, @as(f64, @floatFromInt(child.kernels.items.len)) / @as(f64, @floatFromInt(parent.kernels.items.len)),
    });
    std.debug.print("  Christian: redundancy is SCAFFOLDING, parent adapts faster.  Agent: it is BAGGAGE, child keeps up.\n", .{});
    std.debug.print("  final held-out: parent {d:.5}, child {d:.5} — child/parent {d:.4}, {s} was right\n", .{
        p_rms[last], c_rms[last], c_rms[last] / p_rms[last],
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
    _ = try refine(gpa, out.items, pts, target, m.opts.regions, o);
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
            label, parent.kernels.items.len, pr, parent.meanUpdates(),
            child.kernels.items.len, cr, child.meanUpdates(), gap[gi],
        });
    }
    std.debug.print("  the gap trajectory: {d:.4} -> {d:.4} -> {d:.4} — {s}\n", .{
        gap[0], gap[1], gap[2],
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
            mark, p0.kernels.items.len, readiness(&p0, 16), reads[mi], readiness(&p0, 256),
            updateSpread(&p0), before, after, gains[mi],
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
            n, keep * marl.PARAMS, after, g,
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
        spread[0], spread[1], spread[2],
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
            arm.name, comp.contested, comp.stale, comp.dead, comp.reached,
            row[ai].k, row[ai].after, row[ai].gain,
            row[ai].held, row[ai].ret, row[ai].ret_births, row[ai].plast, row[ai].plast_births,
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
            arms[ai].name, row[ai].gain, fr[ai].gain, fr[ai].gain - row[ai].gain,
            fr[ai].held, fr[ai].ret, fr[ai].ret_births, fr[ai].plast, fr[ai].plast_births,
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
            arms[pol[ax].winner].name, pol[ax].margin / @max(1e-9, noise[ax]), if (pol[ax].clears) "clears" else "(inside)",
            arms[loc[ax].winner].name, loc[ax].margin / @max(1e-9, fnoise[ax]), if (loc[ax].clears) "clears" else "(inside)",
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
            pp.n, arms[pp.lo].name, arms[pp.hi].name, pp.widest,
            lp.n, arms[lp.lo].name, arms[lp.hi].name, lp.widest,
        });
    }
    std.debug.print("  AS A POLICY: {s} wins the current world, {s} preserves the old one — {s}\n", .{
        arms[pol[0].winner].name, arms[pol[1].winner].name,
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
        @tagName(builtin.mode), TINY, OFFERS, @as(u64, @intFromFloat(@as(f64, @floatFromInt(OFFERS)) / TINY)),
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
            if (late) "LATE " else "EARLY", M,
            @as(f64, @floatFromInt(M)) / @as(f64, @floatFromInt(N)),
            m.kernels.items.len, keep, before,
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
                arm.name, row[ai].old, comp.contested, comp.stale, comp.dead,
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
                spanOf(row, groups[1], ax), spanOf(row, groups[2], ax),
                spanOf(row, groups[3], ax), spanOf(row, groups[4], ax),
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
            arms[ai].name, rows[1][ai].after, refr[ai],
            100 * (rows[1][ai].after - refr[ai]) / @max(1e-9, gap),
            rows[1][ai].held, refr_held[ai],
        });
    }
    std.debug.print("     CHANGING LABELS ALONE REVERSES THE RANKING, in both tested draws: {d:.5} and {d:.5} against the ring's {d:.5} — {d:.0}% and {d:.0}% lower error on the current world\n", .{
        refr[ERRW], refr[8], rows[1][REC].after,
        100 * (rows[1][REC].after - refr[ERRW]) / rows[1][REC].after,
        100 * (rows[1][REC].after - refr[8]) / rows[1][REC].after,
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
            arm.name, row[ai].old, comp.contested, comp.stale, row[ai].wrong, comp.dead,
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
        row[REC].held, row[E2].held, row[6].held, spanOf(&row, groups[3], 1),
        (row[E2].held - row[REC].held) / @max(1e-12, spanOf(&row, groups[3], 1)),
        ((row[E2].held + row[6].held) / 2 - row[REC].held) / @max(1e-12, spanOf(&row, groups[3], 1)),
    });
    std.debug.print("     error-selected locations, zero wrong labels, no oracle: {d:.5}/{d:.5} against the ring's {d:.5} — {d:.0}% lower error, ON THIS FIXTURE AND AT THIS TIMING\n", .{
        row[E2].after, row[6].after, row[REC].after,
        100 * (row[REC].after - (row[E2].after + row[6].after) / 2) / row[REC].after,
    });
    std.debug.print("     and the gain DECOMPOSES: the wider eligible pool alone takes the ring's {d:.5} to {d:.5}/{d:.5} ({d:.0}%), and error weighting adds the rest ({d:.0}% of what is left)\n", .{
        row[REC].after, row[U2].after, row[4].after,
        100 * (row[REC].after - (row[U2].after + row[4].after) / 2) / row[REC].after,
        100 * ((row[U2].after + row[4].after) / 2 - (row[E2].after + row[6].after) / 2) / ((row[U2].after + row[4].after) / 2),
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
                names[mi], aseed, parentk[mi][ai], nh, BUDGET, post[mi][ai],
                cell[mi][ai][0].after, cell[mi][ai][1].after,
                cell[mi][ai][0].lift, cell[mi][ai][1].lift,
                cell[mi][ai][0].old,
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
            names[mi], meanOf(cell[mi]), acqSpread(cell[mi]), selSpread(cell[mi]),
            hits[mi][0], hits[mi][1], parentk[mi][0], parentk[mi][1],
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
