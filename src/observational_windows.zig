//! OBS-4: fine truth and untouched pre-update transfer across sensor windows.
const std = @import("std");
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
fn run(seed: u64, rich: bool, fresh: bool, omega: f32, allow_birth: bool, fixture: *const Fixture) !Report {
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
            if (allow_birth and step > 400 and step % 40 == 0 and candidate.score > thresholds.OBS3_BIRTH_GAIN) {
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
                std.debug.print("OBS4_REQUEST,{d},{d},{d},{d:.1},{d},{d},{d},{d},{d},{d},{d},{d},{e},{e},{e},{e},{e},{e},{e},{e}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, wi, step, i, @intFromBool(accepted), request_count[i], site_count[site], @intFromBool(repeated), model.k, sh.mu[0], sh.mu[1], 1 / sh.l[0], cov, rs / @max(ws, 1e-30), b.g[i], b.h[i], candidate.score });
                report.requests += 1;
                report.repeated_cross_window += @intFromBool(repeated);
                request_count[i] += 1;
                site_count[site] += 1;
                window_mask[i] |= @as(u8, 1) << @intCast(wi);
                if (accepted) model.birth(i) else report.denied += 1;
            }
            if (local_step % 120 == 0) {
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
            change += model.update(b.g);
            try testing.expect(model.k <= adaptive.cap);
            for (model.w, model.active) |w, active| {
                try testing.expect(std.math.isFinite(w));
                if (!active) try testing.expectEqual(@as(f32, 0), w);
            }
        }
        report.train = adaptive.endpointRms(model.w, &data.train, omega);
        report.eval = adaptive.endpointRms(model.w, &data.held, omega);
        try testing.expect(std.math.isFinite(report.train) and std.math.isFinite(report.eval));
        std.debug.print("OBS4_WINDOW,{d},{d},{d},{d:.1},{d},{d},{d},{d},{e},{e},{e},{e},{d},{d},{d}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, @intFromBool(allow_birth), wi, k_before, model.k, incoming, report.train, eval_before, report.eval, report.requests - requests_before, report.denied - denied_before, report.repeated_cross_window - repeated_before });
    }
    report.k = model.k;
    try testing.expectEqual(@as(u64, 3_686_400), report.rhs);
    if (!allow_birth) try testing.expectEqual(@as(usize, 9), model.k);
    std.debug.print("OBS4_FINAL,{d},{d},{d},{d:.1},{d},{d},{d},{d},{d},{e},{e},{e},{d},{d},{d},{d:.3}\n", .{ seed, @intFromBool(rich), @intFromBool(fresh), omega, @intFromBool(allow_birth), report.k, report.requests, report.denied, report.repeated_cross_window, report.incoming_sse, report.train, report.eval, report.rhs, report.rhs * count, report.coefficient_updates, @as(f64, @floatFromInt(timer.read())) / 1e9 });
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
            const r = try run(seed, rich, fresh, omega, births, &fixture);
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
