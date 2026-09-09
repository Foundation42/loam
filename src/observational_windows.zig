//! OBS-4: fine truth and untouched pre-update transfer across sensor windows.
const std = @import("std");
const builtin = @import("builtin");
const adaptive = @import("adaptive_inferred.zig");
const inferred = @import("inferred.zig");
const marl = @import("marl.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");
const testing = std.testing;
const count = adaptive.count;
const windows = 3;
const updates = 1200;

const Fixture = struct {
    data: [windows]adaptive.Data,
    fn init(seed: u64, rich: bool) Fixture {
        var truth = adaptive.zero;
        const coarse = inferred.truthWeights(seed);
        @memcpy(truth[0..9], &coarse);
        if (rich) {
            truth[30] += 0.025;
            truth[35] -= 0.025;
        }
        var out: Fixture = undefined;
        var hs = rng.Stream.region(seed, 0x4f34484f, 0);
        var held: [64]adaptive.Observation = undefined;
        for (&held) |*o| {
            const x = start(&hs);
            o.* = .{ .x = x, .y = adaptive.engine.trajectory(f32, truth, x, 0.005, 96, 0, false).x, .steps = 24 };
        }
        for (&out.data, 0..) |*data, wi| {
            var st = rng.Stream.region(seed, 0x4f345452, @intCast(wi));
            for (0..16) |i| {
                const x = start(&st);
                for ([_]u32{ 8, 24 }, 0..) |n, j| data.train[2 * i + j] = .{ .x = x, .y = adaptive.engine.trajectory(f32, truth, x, 0.005, n * 4, 0, false).x, .steps = n };
            }
            data.held = held;
        }
        return out;
    }
    fn print(self: *const Fixture, seed: u64, rich: bool) void {
        for (self.data, 0..) |data, wi| for (data.train, 0..) |o, i| {
            std.debug.print("OBS4_SENSOR,{d},{d},train,{d},{d},{d},{e},{e},{e},{e}\n", .{ seed, @intFromBool(rich), wi, i, o.steps, o.x[0], o.x[1], o.y[0], o.y[1] });
        };
        for (self.data[0].held, 0..) |o, i| std.debug.print("OBS4_SENSOR,{d},{d},eval,-1,{d},{d},{e},{e},{e},{e}\n", .{ seed, @intFromBool(rich), i, o.steps, o.x[0], o.x[1], o.y[0], o.y[1] });
    }
};
fn start(st: *rng.Stream) [2]f32 {
    return .{ 0.15 + 0.7 * st.unit(), 0.15 + 0.7 * st.unit() };
}
const Report = struct {
    k: usize = 9,
    requests: usize = 0,
    denied: usize = 0,
    repeated_cross_window: usize = 0,
    incoming_sse: f64 = 0,
    train: f64 = 0,
    eval: f64 = 0,
    rhs: u64 = 0,
    coefficient_updates: u64 = 0,
};
/// OBS-6's schedule. `.none` is OBS-3 and OBS-4's fixed rate, so G50 and
/// G51 are untouched; `.inv` is `lr0 * min(1, t0/t)` with `t0` the step
/// births become possible at.
///
/// Both halves are read off this harness rather than chosen. Births are
/// gated on `step > BIRTH_WARMUP`, so that is the moment the birth signal
/// starts being READ: decaying before it slows learning over readings
/// nobody uses, and decaying after leaves the wander inside the window that
/// matters. And 1/t rather than 1/sqrt(t) because G52 (a) measured both on
/// this fixture — the milder schedule left six requests standing across
/// three seeds where 1/t left zero.
pub const Sched = enum {
    none,
    inv,

    pub fn rateAt(self: Sched, step: usize) f32 {
        return switch (self) {
            .none => adaptive.RATE,
            .inv => adaptive.RATE * @min(1, @as(f32, @floatFromInt(BIRTH_WARMUP)) /
                @as(f32, @floatFromInt(step))),
        };
    }
};

/// Updates before a birth may be requested — OBS-4's `step > 400`, named
/// so that OBS-6's schedule can be derived from it instead of repeating it.
pub const BIRTH_WARMUP: usize = 400;

fn run(seed: u64, rich: bool, fresh: bool, omega: f32, allow_birth: bool, fixture: *const Fixture, sched: Sched, verbose: bool) !Report {
    var model = adaptive.Model{};
    var report = Report{};
    var request_count = [_]usize{0} ** count;
    var site_count = [_]usize{0} ** 16;
    var window_mask = [_]u8{0} ** count;
    var change: f64 = 0;
    var timer = try std.time.Timer.start();
    for (0..windows) |wi| {
        const data = &fixture.data[if (fresh) wi else 0];
        const incoming = adaptive.endpointRms(model.w, &data.train, omega);
        const eval_before = adaptive.endpointRms(model.w, &data.held, omega);
        if (wi > 0) report.incoming_sse += incoming * incoming;
        const k_before = model.k;
        const requests_before = report.requests;
        const denied_before = report.denied;
        const repeated_before = report.repeated_cross_window;
        var coverage = [_]u32{0} ** 17;
        for (data.train) |o| coverage[adaptive.bin(o.x, 0.15, 0.85)] += 1;
        for (1..updates + 1) |local_step| {
            const step = wi * updates + local_step;
            const b = adaptive.batch(model.w, data, omega);
            report.rhs += b.rhs;
            const candidate = adaptive.best(&model, &b);
            if (allow_birth and step > BIRTH_WARMUP and step % 40 == 0 and candidate.score > thresholds.OBS3_BIRTH_GAIN) {
                const i = candidate.i;
                const sh = adaptive.shape(i);
                const site = (i - 9) % 16;
                const previous_windows: u8 = (@as(u8, 1) << @intCast(wi)) - 1;
                const repeated = window_mask[i] & previous_windows != 0;
                var cov: f32 = 0;
                for (0..count) |j| if (model.active[j]) {
                    cov = @max(cov, marl.gaussian(adaptive.shape(j), sh.mu));
                };
                var rs: f64 = 0;
                var ws: f64 = 0;
                for (data.train, b.residual) |o, r| {
                    const phi = marl.gaussian(sh, .{ o.x[0], o.x[1], 0.5 });
                    rs += @as(f64, phi) * r;
                    ws += phi;
                }
                const accepted = model.k < adaptive.cap;
                if (verbose) std.debug.print("OBS4_REQUEST,{d},{d},{d},{d:.1},{d},{d},{d},{d},{d},{d},{d},{d},{e},{e},{e},{e},{e},{e},{e},{e}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, wi, step, i, @intFromBool(accepted), request_count[i], site_count[site], @intFromBool(repeated), model.k, sh.mu[0], sh.mu[1], 1 / sh.l[0], cov, rs / @max(ws, 1e-30), b.g[i], b.h[i], candidate.score });
                report.requests += 1;
                report.repeated_cross_window += @intFromBool(repeated);
                request_count[i] += 1;
                site_count[site] += 1;
                window_mask[i] |= @as(u8, 1) << @intCast(wi);
                if (accepted) model.birth(i) else report.denied += 1;
            }
            if (verbose and local_step % 120 == 0) {
                const ev = adaptive.endpointRms(model.w, &data.held, omega);
                std.debug.print("OBS4_HISTORY,{d},{d},{d},{d:.1},{d},{d},{d},{d},{e},{e},{e},{d},{d},{d},{e},{d},{d},{d}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, @intFromBool(allow_birth), wi, step, model.k, @sqrt(b.se / data.train.len), ev, candidate.score, report.requests, report.denied, report.repeated_cross_window, change, report.rhs, report.rhs * count, report.coefficient_updates });
                std.debug.print("OBS4_SPATIAL,{d},{d},{d},{d:.1},{d},{d},{d}", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, @intFromBool(allow_birth), wi, step });
                for (b.spatial) |v| std.debug.print(",{e}", .{v});
                for (coverage) |v| std.debug.print(",{d}", .{v});
                for (b.paths) |v| std.debug.print(",{d}", .{v});
                std.debug.print("\n", .{});
                change = 0;
            }
            report.coefficient_updates += model.k;
            change += model.updateAt(b.g, sched.rateAt(step));
            try testing.expect(model.k <= adaptive.cap);
            for (model.w, model.active) |w, active| {
                try testing.expect(std.math.isFinite(w));
                if (!active) try testing.expectEqual(@as(f32, 0), w);
            }
        }
        report.train = adaptive.endpointRms(model.w, &data.train, omega);
        report.eval = adaptive.endpointRms(model.w, &data.held, omega);
        try testing.expect(std.math.isFinite(report.train) and std.math.isFinite(report.eval));
        if (verbose) std.debug.print("OBS4_WINDOW,{d},{d},{d},{d:.1},{d},{d},{d},{d},{e},{e},{e},{e},{d},{d},{d}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, @intFromBool(allow_birth), wi, k_before, model.k, incoming, report.train, eval_before, report.eval, report.requests - requests_before, report.denied - denied_before, report.repeated_cross_window - repeated_before });
    }
    report.k = model.k;
    try testing.expectEqual(@as(u64, 3_686_400), report.rhs);
    if (!allow_birth) try testing.expectEqual(@as(usize, 9), model.k);
    if (verbose) std.debug.print("OBS4_FINAL,{d},{d},{d},{d:.1},{d},{d},{d},{d},{d},{e},{e},{e},{d},{d},{d},{d:.3}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, @intFromBool(allow_birth), report.k, report.requests, report.denied, report.repeated_cross_window, report.incoming_sse, report.train, report.eval, report.rhs, report.rhs * count, report.coefficient_updates, @as(f64, @floatFromInt(timer.read())) / 1e9 });
    return report;
}

test "G51 (a) fixed evaluation data never enters learning or the birth score" {
    var data = Fixture.init(7, true);
    const first = adaptive.batch(adaptive.zero, &data.data[0], 0);
    // Executable held-out-leak mutation: arbitrary changes to evaluation
    // labels cannot change any learning residual, derivative or candidate.
    for (&data.data[0].held) |*o| o.y = .{ 1000, -1000 };
    const second = adaptive.batch(adaptive.zero, &data.data[0], 0);
    try testing.expectEqualDeep(first, second);
    try testing.expectEqualDeep(adaptive.best(&adaptive.Model{}, &first), adaptive.best(&adaptive.Model{}, &second));
    // Separate streams are disjoint as concrete sampled starting points.
    const original = Fixture.init(7, true);
    for (original.data, 0..) |d, wi| {
        for (d.train) |o| {
            for (original.data[0].held) |h| try testing.expect(!std.meta.eql(o.x, h.x));
            for (original.data[0..wi]) |earlier| for (earlier.train) |p| try testing.expect(!std.meta.eql(o.x, p.x));
        }
        try testing.expectEqualDeep(original.data[0].held, d.held);
    }
}

test "G51 (b) useful structural growth and transfer to fresh observation windows" {
    // Accumulate the declared comparisons; no observations or evaluation
    // values are used to extend budgets or select a stopping checkpoint.
    var repeated_train = [_]f64{0} ** 2;
    var repeated_eval = [_]f64{0} ** 2;
    var fresh_eval = [_]f64{0} ** 2;
    var incoming = [_]f64{0} ** 2;
    var adaptive_eval = [_]f64{0} ** 2;
    var repeats = [_]usize{0} ** 2;
    var useful_births: usize = 0;
    for ([_]u64{ 7, 19, 41 }) |seed| for ([_]bool{ false, true }) |rich| {
        const fixture = Fixture.init(seed, rich);
        fixture.print(seed, rich);
        for ([_]bool{ false, true }) |fresh| for ([_]f32{ 0, 0.3 }, 0..) |omega, oi| for ([_]bool{ false, true }, 0..) |births, ai| {
            const r = try run(seed, rich, fresh, omega, births, &fixture, .none, true);
            if (rich and omega == 0 and !fresh) {
                repeated_train[ai] += r.train * r.train;
                repeated_eval[ai] += r.eval * r.eval;
                if (births) useful_births += r.k - 9;
            }
            if (rich and omega == 0 and fresh) {
                fresh_eval[ai] += r.eval * r.eval;
                incoming[ai] += r.incoming_sse;
            }
            if (rich and fresh and births) {
                adaptive_eval[oi] += r.eval * r.eval;
                repeats[oi] += r.repeated_cross_window;
            }
        };
    };
    const useful = useful_births > 0 and repeated_train[1] < repeated_train[0] and repeated_eval[1] < repeated_eval[0];
    std.debug.print("OBS4_PREDICTIONS useful births={d} train_ratio={d:.6} eval_ratio={d:.6} {s}; fresh_eval_ratio={d:.6} {s}; incoming_ratio={d:.6} {s}; correct_wrong_ratio={d:.6} {s}; cross-window requests correct/wrong={d}/{d} {s}\n", .{ useful_births, @sqrt(repeated_train[1] / repeated_train[0]), @sqrt(repeated_eval[1] / repeated_eval[0]), if (useful) "HELD" else "REFUTED", @sqrt(fresh_eval[1] / fresh_eval[0]), if (fresh_eval[1] < fresh_eval[0]) "HELD" else "REFUTED", @sqrt(incoming[1] / incoming[0]), if (incoming[1] < incoming[0]) "HELD" else "REFUTED", @sqrt(adaptive_eval[0] / adaptive_eval[1]), if (adaptive_eval[0] < adaptive_eval[1]) "HELD" else "REFUTED", repeats[0], repeats[1], if (repeats[1] > repeats[0]) "HELD" else "REFUTED" });
}

test "G51 (c) diagnose false birth pressure from continued updates after an accurate fit" {
    for ([_]u64{ 7, 19, 41 }) |seed| {
        const fixture = Fixture.init(seed, false);
        const data = &fixture.data[0];
        var checkpoint = adaptive.Model{};
        for (0..800) |_| {
            const b = adaptive.batch(checkpoint.w, data, 0);
            _ = checkpoint.update(b.g);
        }
        for ([_]bool{ false, true }) |keep_updating| {
            var m = checkpoint;
            var requests: usize = 0;
            var max_score: f32 = 0;
            var max_train: f64 = 0;
            const initial_train = adaptive.endpointRms(m.w, &data.train, 0);
            for (801..3601) |step| {
                const b = adaptive.batch(m.w, data, 0);
                if (step % 40 == 0) {
                    const candidate = adaptive.best(&m, &b);
                    requests += @intFromBool(candidate.score > thresholds.OBS3_BIRTH_GAIN);
                    max_score = @max(max_score, candidate.score);
                    max_train = @max(max_train, @sqrt(b.se / data.train.len));
                }
                if (keep_updating) _ = m.update(b.g);
            }
            if (!keep_updating) try testing.expectEqualDeep(checkpoint, m);
            std.debug.print("OBS4_DIAGNOSTIC,{d},{d},{e},{e},{e},{d},{e}\n", .{ seed, @intFromBool(keep_updating), initial_train, max_train, max_score, requests, adaptive.endpointRms(m.w, &data.held, 0) });
        }
    }
}

/// OBS-5's schedules, all of them functions of the update index alone so
/// that an arm is one enum and not a branch inside the loop.
const Schedule = enum {
    fixed,
    /// lr0 / sqrt(t / t0)
    inv_sqrt,
    /// lr0 / (t / t0)
    inv,

    fn rateAt(self: Schedule, lr0: f32, t: usize, t0: usize) f32 {
        const r = @as(f32, @floatFromInt(t)) / @as(f32, @floatFromInt(t0));
        return switch (self) {
            .fixed => lr0,
            .inv_sqrt => lr0 / @sqrt(r),
            .inv => lr0 / r,
        };
    }
};

test "G52 (a) OBS-4's false birth pressure is Adam's SCALE-FREE STEP: linear in the rate, and a schedule removes it" {
    // OBS-4 (c) found that continued optimisation alone manufactures birth
    // requests on stationary noiseless data already fitted to 2.2e-7, and
    // stopped there: "does not yet isolate which part of Adam/finite-
    // precision dynamics causes it".
    //
    // It is not finite precision. Adam's step is
    //
    //     w -= lr * mhat / (sqrt(vhat) + eps)
    //
    // and mhat/sqrt(vhat) is a RATIO of the gradient's own moments, so it
    // is dimensionless and of order one whenever eps does not dominate.
    // The step size is therefore lr, INDEPENDENT of how small the gradient
    // has become. That is what "adaptive" means, it is the whole point of
    // Adam, and its textbook consequence is that Adam at a fixed rate does
    // not converge — it wanders in a ball whose radius is set by lr.
    //
    // Two consequences, both registered in `tools/obs5_predict.py` before
    // this ran, and both falsifiable in one sweep:
    //
    //   the wander is LINEAR IN lr, so halving lr at least halves the
    //   train RMS the continued run reaches;
    //
    //   a DECAYED schedule removes the requests entirely.
    //
    // Two schedules, because the horizon past the checkpoint is only 3.5x
    // its length and 1/sqrt(t) can only buy 2.12x of it. If the mild one
    // leaves requests standing and the sharp one removes them, the
    // mechanism is confirmed and the schedule is a tuning question; if
    // neither does, the birth score is implicated rather than the rate,
    // which is a different phase.
    //
    // The checkpoint, the step counts, the scoring cadence and the request
    // rule are OBS-4 (c)'s exactly, so the `fixed` arm at 0.003 must
    // reproduce its 7/8/10.
    const t0: usize = 800;
    const Arm = struct { label: []const u8, lr: f32, sched: Schedule };
    const arms = [_]Arm{
        .{ .label = "0.003   fixed (OBS-4 c)", .lr = adaptive.RATE, .sched = .fixed },
        .{ .label = "0.0015  fixed", .lr = adaptive.RATE / 2, .sched = .fixed },
        .{ .label = "0.00075 fixed", .lr = adaptive.RATE / 4, .sched = .fixed },
        .{ .label = "0.003   / sqrt(t/t0)", .lr = adaptive.RATE, .sched = .inv_sqrt },
        .{ .label = "0.003   / (t/t0)", .lr = adaptive.RATE, .sched = .inv },
    };

    std.debug.print("\n  {s:<24} {s:>6} {s:>12} {s:>12} {s:>10} {s:>9}\n", .{ "arm", "seed", "train0", "max train", "wander", "requests" });
    var max_train: [arms.len]f64 = .{0} ** arms.len;
    var requests: [arms.len]usize = .{0} ** arms.len;
    for ([_]u64{ 7, 19, 41 }) |seed| {
        const fixture = Fixture.init(seed, false);
        const data = &fixture.data[0];
        var checkpoint = adaptive.Model{};
        for (0..t0) |_| {
            const b = adaptive.batch(checkpoint.w, data, 0);
            _ = checkpoint.update(b.g);
        }
        const train0 = adaptive.endpointRms(checkpoint.w, &data.train, 0);
        for (arms, 0..) |arm, ai| {
            var m = checkpoint;
            var req: usize = 0;
            var mt: f64 = 0;
            for (t0 + 1..3601) |step| {
                const b = adaptive.batch(m.w, data, 0);
                if (step % 40 == 0) {
                    req += @intFromBool(adaptive.best(&m, &b).score > thresholds.OBS3_BIRTH_GAIN);
                    mt = @max(mt, @sqrt(b.se / data.train.len));
                }
                _ = m.updateAt(b.g, arm.sched.rateAt(arm.lr, step, t0));
            }
            // How far the parameters travelled from the checkpoint —
            // the wander itself, rather than what it did to the error.
            var wander: f64 = 0;
            for (0..count) |i| {
                if (!m.active[i]) continue;
                const d = @as(f64, m.w[i] - checkpoint.w[i]);
                wander += d * d;
            }
            wander = @sqrt(wander);
            max_train[ai] += mt / 3;
            requests[ai] += req;
            std.debug.print("  {s:<24} {d:>6} {e:>12.3} {e:>12.3} {e:>10.3} {d:>9}\n", .{ arm.label, seed, train0, mt, wander, req });
        }
    }
    std.debug.print("  means over three seeds: max train {e:.3} / {e:.3} / {e:.3} at lr, lr/2, lr/4 — ratio {d:.3}, {d:.3}\n", .{
        max_train[0], max_train[1], max_train[2], max_train[1] / max_train[0], max_train[2] / max_train[1],
    });
    std.debug.print("  requests, summed over seeds: fixed {d} / {d} / {d}, 1-over-sqrt-t {d}, 1-over-t {d}\n", .{
        requests[0], requests[1], requests[2], requests[3], requests[4],
    });

    // The fixed arm must still be OBS-4 (c)'s: 7 + 8 + 10.
    try testing.expectEqual(@as(usize, 25), requests[0]);
    try testing.expect(max_train[1] / max_train[0] < thresholds.OBS5_RATE_SCALING);
    try testing.expect(max_train[2] / max_train[1] < thresholds.OBS5_RATE_SCALING);
    // The registered equality, on whichever schedule reaches it.
    try testing.expect(requests[3] == 0 or requests[4] == 0);
}

/// Everything OBS-6 compares between the two schedules, accumulated over
/// the same 48-cell factorial G51 (b) runs.
const Sweep = struct {
    /// rich, correct, repeated evidence, by [frozen, adaptive]
    repeated_train: [2]f64 = .{ 0, 0 },
    repeated_eval: [2]f64 = .{ 0, 0 },
    /// rich, correct, fresh evidence, by [frozen, adaptive]
    fresh_eval: [2]f64 = .{ 0, 0 },
    incoming: [2]f64 = .{ 0, 0 },
    /// rich, fresh, adaptive, by [correct, wrong]
    adaptive_eval: [2]f64 = .{ 0, 0 },
    /// cross-window repeat requests over the WHOLE factorial, by
    /// [correct, wrong] — the control's number, not just the rich cell's
    repeats: [2]usize = .{ 0, 0 },
    /// OBS-4's control: SIMPLE field, correct dynamics, where no extra
    /// capacity is called for at all. [repeated, fresh] × [frozen, adaptive]
    simple_eval: [2][2]f64 = .{.{ 0, 0 }} ** 2,
    /// The null: frozen-allocation final train RMS, split by whether the
    /// dynamics are CORRECT. Pooling the two hides the answer — under wrong
    /// dynamics the fit is limited by mis-specification and no learning
    /// rate can move it, so a pooled null is dominated by arms that cannot
    /// respond to the thing being tested. Measured pooled it read 1.0000,
    /// which is a true number about the wrong quantity.
    frozen_train: [2]f64 = .{ 0, 0 },
    /// Births in the control cells (simple field, correct dynamics), where
    /// there is nothing to buy. Printed because a ratio of exactly 1.000
    /// between the adaptive and frozen arms means they are the SAME RUN,
    /// and that has to be visible rather than inferred.
    control_births: usize = 0,
    births: usize = 0,
    seconds: f64 = 0,

    fn ratio(a: f64, b: f64) f64 {
        return @sqrt(a / b);
    }
};

fn sweep(sched: Sched) !Sweep {
    var s = Sweep{};
    var timer = try std.time.Timer.start();
    for ([_]u64{ 7, 19, 41 }) |seed| for ([_]bool{ false, true }) |rich| {
        const fixture = Fixture.init(seed, rich);
        for ([_]bool{ false, true }, 0..) |fresh, fi| for ([_]f32{ 0, 0.3 }, 0..) |omega, oi| for ([_]bool{ false, true }, 0..) |births, ai| {
            const r = try run(seed, rich, fresh, omega, births, &fixture, sched, false);
            if (!births) s.frozen_train[oi] += r.train * r.train;
            s.repeats[oi] += r.repeated_cross_window;
            if (rich and omega == 0 and !fresh) {
                s.repeated_train[ai] += r.train * r.train;
                s.repeated_eval[ai] += r.eval * r.eval;
                if (births) s.births += r.k - 9;
            }
            if (rich and omega == 0 and fresh) {
                s.fresh_eval[ai] += r.eval * r.eval;
                s.incoming[ai] += r.incoming_sse;
            }
            if (rich and fresh and births) s.adaptive_eval[oi] += r.eval * r.eval;
            if (!rich and omega == 0) {
                s.simple_eval[fi][ai] += r.eval * r.eval;
                if (births) s.control_births += r.k - 9;
            }
        };
    };
    s.seconds = @as(f64, @floatFromInt(timer.read())) / 1e9;
    return s;
}

test "G53 does the birth signal survive its own calibration? OBS-4's factorial under OBS-5's schedule" {
    // OBS-5 established that OBS-4's false birth pressure is Adam's
    // SCALE-FREE STEP, and that a 1/t schedule removes it at no cost to the
    // fit. OBS-3 and OBS-4 ran at a fixed rate, so `OBS3_BIRTH_GAIN` —
    // which decides what counts as a birth request in both — was calibrated
    // against a signal sitting on a wander nobody had measured.
    //
    // This runs OBS-4's factorial unchanged in every other respect, twice,
    // and asks what survives. `tools/obs6_predict.py` was frozen first.
    //
    // The order below is the order it is registered in, and the first is
    // load-bearing: a decayed rate could improve every birth number for the
    // stupidest possible reason, by learning less. MARL-20's two-nulls
    // discipline, and if the null fails everything after it is void.
    const none = try sweep(.none);
    const inv = try sweep(.inv);

    // (2) THE NULL. Frozen allocation, so coefficients are the only thing
    // that can move: did the schedule cost the fit?
    const null_ratio = Sweep.ratio(inv.frozen_train[0], none.frozen_train[0]);
    const null_wrong = Sweep.ratio(inv.frozen_train[1], none.frozen_train[1]);
    std.debug.print("\n  G53 [{s}] the null — frozen-allocation train RMS, scheduled over fixed: {d:.4} on CORRECT dynamics, {d:.4} on wrong ({d:.1} s + {d:.1} s)\n", .{
        @tagName(builtin.mode), null_ratio, null_wrong, none.seconds, inv.seconds,
    });
    std.debug.print("  {s:>18}  correct {e:.3} -> {e:.3}   wrong {e:.3} -> {e:.3}\n", .{
        "frozen train RMS", @sqrt(none.frozen_train[0] / 12), @sqrt(inv.frozen_train[0] / 12),
        @sqrt(none.frozen_train[1] / 12), @sqrt(inv.frozen_train[1] / 12),
    });

    // (3) OBS-4's five, under each schedule.
    for ([_]struct { l: []const u8, s: Sweep }{ .{ .l = "fixed 0.003", .s = none }, .{ .l = "1/t schedule", .s = inv } }) |a| {
        const w = a.s;
        const useful = w.births > 0 and w.repeated_train[1] < w.repeated_train[0] and w.repeated_eval[1] < w.repeated_eval[0];
        std.debug.print("  {s:<14} births {d:>3} {s:<8} train {d:.6} eval {d:.6} | fresh {d:.6} {s:<8} | incoming {d:.6} {s:<8} | correct/wrong {d:.6} {s:<8} | repeats {d}/{d} {s}\n", .{
            a.l, w.births, if (useful) "HELD" else "REFUTED",
            Sweep.ratio(w.repeated_train[1], w.repeated_train[0]),
            Sweep.ratio(w.repeated_eval[1], w.repeated_eval[0]),
            Sweep.ratio(w.fresh_eval[1], w.fresh_eval[0]), if (w.fresh_eval[1] < w.fresh_eval[0]) "HELD" else "REFUTED",
            Sweep.ratio(w.incoming[1], w.incoming[0]), if (w.incoming[1] < w.incoming[0]) "HELD" else "REFUTED",
            Sweep.ratio(w.adaptive_eval[0], w.adaptive_eval[1]), if (w.adaptive_eval[0] < w.adaptive_eval[1]) "HELD" else "REFUTED",
            w.repeats[0], w.repeats[1], if (w.repeats[1] > w.repeats[0]) "HELD" else "REFUTED",
        });
    }

    // (4) THE CONTROL. Simple field, correct dynamics: adaptive allocation
    // has nothing to buy, so any excess over frozen is the instrument.
    std.debug.print("  {s:<14} {s:>10} {s:>12} {s:>12} {s:>10}\n", .{ "control", "evidence", "frozen eval", "adaptive eval", "ratio" });
    var control_gain: [2]f64 = .{ 0, 0 };
    for ([_][]const u8{ "repeated", "fresh" }, 0..) |lab, fi| {
        const n_ratio = Sweep.ratio(none.simple_eval[fi][1], none.simple_eval[fi][0]);
        const i_ratio = Sweep.ratio(inv.simple_eval[fi][1], inv.simple_eval[fi][0]);
        control_gain[fi] = i_ratio / n_ratio;
        std.debug.print("  {s:<14} {s:>10} fixed {e:>12.3} {e:>14.3} {d:>10.3}\n", .{ "simple correct", lab, @sqrt(none.simple_eval[fi][0] / 3), @sqrt(none.simple_eval[fi][1] / 3), n_ratio });
        std.debug.print("  {s:<14} {s:>10}   1/t {e:>12.3} {e:>14.3} {d:>10.3}   scheduled/fixed {d:.3}\n", .{ "", lab, @sqrt(inv.simple_eval[fi][0] / 3), @sqrt(inv.simple_eval[fi][1] / 3), i_ratio, control_gain[fi] });
    }
    const correct_fall = @as(f64, @floatFromInt(inv.repeats[0] + 1)) / @as(f64, @floatFromInt(none.repeats[0] + 1));
    const wrong_fall = @as(f64, @floatFromInt(inv.repeats[1] + 1)) / @as(f64, @floatFromInt(none.repeats[1] + 1));
    std.debug.print("  control births (simple field, correct dynamics, nothing to buy): fixed {d}, 1/t {d}\n", .{ none.control_births, inv.control_births });
    std.debug.print("  repeat requests over the whole factorial: correct {d} -> {d} ({d:.3}), wrong {d} -> {d} ({d:.3})\n", .{
        none.repeats[0], inv.repeats[0], correct_fall, none.repeats[1], inv.repeats[1], wrong_fall,
    });

    // The null first, because nothing after it means anything otherwise.
    //
    // The pooled figure passes at 0.9999 and is nearly uninformative: it is
    // dominated by cells where the fit is limited by the MODEL CLASS — the
    // rich field's two components outside the nine-kernel span, and the
    // wrong dynamics — and no learning rate can move those. Sharpening it
    // from "all frozen arms" to "frozen arms under correct dynamics" only
    // swapped one source of mis-specification for the other; both read
    // 1.702e-2 -> 1.702e-2 and 3.035e-2 -> 3.035e-2.
    //
    // The cell where the RATE is the binding constraint is simple field,
    // correct dynamics, frozen allocation — a target the model class
    // contains exactly. There the null does not merely pass, it INVERTS:
    // 1.669e-4 -> 4.609e-7 and 5.177e-4 -> 4.380e-7, better by 360x and
    // 1180x. Fixed-rate Adam was hovering, exactly as G52 (a) measured, and
    // the schedule lets it converge. That is asserted below and it is the
    // one that matters.
    try testing.expect(null_ratio < thresholds.OBS6_FIT_NULL);
    try testing.expect(null_wrong < thresholds.OBS6_FIT_NULL);
    for (0..2) |fi| try testing.expect(inv.simple_eval[fi][0] < none.simple_eval[fi][0]);
    // OBS-4's five, still standing under the schedule.
    try testing.expect(inv.births > 0);
    try testing.expect(inv.repeated_train[1] < inv.repeated_train[0]);
    try testing.expect(inv.repeated_eval[1] < inv.repeated_eval[0]);
    try testing.expect(inv.fresh_eval[1] < inv.fresh_eval[0]);
    try testing.expect(inv.incoming[1] < inv.incoming[0]);
    try testing.expect(inv.adaptive_eval[0] < inv.adaptive_eval[1]);
    try testing.expect(inv.repeats[1] > inv.repeats[0]);
    // The control clearing, and the separation widening.
    try testing.expect(control_gain[0] < thresholds.OBS6_CONTROL_CLEARS);
    try testing.expect(control_gain[1] < thresholds.OBS6_CONTROL_CLEARS);
    try testing.expect(wrong_fall > correct_fall);
}
