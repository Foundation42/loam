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

    var out = std.ArrayListUnmanaged(marl.Kernel){};
    errdefer out.deinit(gpa);
    for (parent.regions, 0..) |*reg, ri| {
        if (reg.own.items.len == 0) continue;
        const share = reff[ri] / total * @as(f64, @floatFromInt(keep));
        const k = @min(reg.own.items.len, @max(1, @as(usize, @intFromFloat(@round(share)))));
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
    n: usize = 0,

    pub fn init(gpa: std.mem.Allocator, cap: usize) !Replay {
        return .{ .x = try gpa.alloc([3]f32, cap), .y = try gpa.alloc(f64, cap) };
    }
    pub fn deinit(self: Replay, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.y);
    }
    /// A ring: the most recent `cap` observations, so a consolidation sees
    /// the measure the model has most lately been living under.
    pub fn push(self: *Replay, q: [3]f32, v: f64) void {
        const i = self.n % self.x.len;
        self.x[i] = q;
        self.y[i] = v;
        self.n += 1;
    }
    pub fn filled(self: Replay) usize {
        return @min(self.n, self.x.len);
    }
};

/// Stream `n` exemplars of the model's current truth, keeping the last
/// `buf.len` in the replay ring. The model's own `stream_n` with the
/// observations retained.
pub fn wake(m: *marl.Model, n: u64, buf: *Replay, st: *rng.Stream) !void {
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const q = [3]f32{ st.unit(), st.unit(), st.unit() };
        const v = marl.truthOf(m.opts.truth, q);
        _ = try m.observe(q, .{v});
        buf.push(q, v);
    }
}

/// Sleep against whatever target is supplied at the replay points.
fn sleepOn(
    gpa: std.mem.Allocator,
    m: *marl.Model,
    pts: []const [3]f32,
    target: []const f64,
    keep: usize,
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
    var out = std.ArrayListUnmanaged(marl.Kernel){};
    defer out.deinit(gpa);
    for (m.regions, 0..) |*reg, ri| {
        if (reg.own.items.len == 0) continue;
        const share = reff[ri] / total * @as(f64, @floatFromInt(keep));
        const k = @min(reg.own.items.len, @max(1, @as(usize, @intFromFloat(@round(share)))));
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
    _ = try refine(gpa, out.items, pts, target, m.opts.regions, .{});
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
    var s_self = try sleepOn(gpa, &p0, buf.x[0..BUF], self_t, half0);
    defer s_self.deinit();
    var s_rep = try sleepOn(gpa, &p0, buf.x[0..BUF], buf.y[0..BUF], half0);
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
            const np = try sleepOn(gpa, &parent, pb.x[0..BUF], pb.y[0..BUF], parent.kernels.items.len / 2);
            parent.deinit();
            parent = np;
            parent.opts.truth = moved;
            const nc = try sleepOn(gpa, &child, cb.x[0..BUF], cb.y[0..BUF], child.kernels.items.len / 2);
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
        var fork = try sleepOn(gpa, &p0, ring.x[0..RING], ring.y[0..RING], p0.kernels.items.len / 2);
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
        var fork = try sleepOn(gpa, &p0, ring.x[0..n], ring.y[0..n], keep);
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
            var fork = try sleepOn(gpa, &base, ring.x[0..n], ring.y[0..n], KEEP);
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
