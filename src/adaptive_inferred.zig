//! OBS-3: restricted candidate births for endpoint-driven inverse fitting.
//! All candidates are scored in every arm. This is an experimental birth
//! policy; MARL.observe, defaults, death and rehoming are not changed.
const std = @import("std");
const marl = @import("marl.zig");
const inferred = @import("inferred.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");
const testing = std.testing;
pub const count = 41;
pub const cap = 25;
pub const zero = [_]f32{0} ** count;
pub fn shape(i: usize) marl.Shape {
    if (i < 9) return inferred.shape(i);
    const j = (i - 9) % 16;
    const sigma: f32 = if (i < 25) 0.14 else 0.09;
    return .{ .mu = .{ 0.2 + 0.2 * @as(f32, @floatFromInt(j % 4)), 0.2 + 0.2 * @as(f32, @floatFromInt(j / 4)), 0.5 }, .l = .{ 1 / sigma, 0, 1 / sigma, 0, 0, 1 / sigma } };
}
pub const engine = @import("trajectory.zig").Fixed(count, shape);
pub const Observation = struct { x: [2]f32, y: [2]f32, steps: u32 };
fn start(st: *rng.Stream) [2]f32 {
    return .{ 0.15 + 0.7 * st.unit(), 0.15 + 0.7 * st.unit() };
}
pub const Data = struct {
    train: [32]Observation,
    held: [64]Observation,
    fn init(seed: u64) Data {
        const truth = inferred.truthWeights(seed);
        var data: Data = undefined;
        var st = rng.Stream.region(seed, 0x494e4654, 0);
        for (0..16) |i| {
            const x = start(&st);
            for ([_]u32{ 8, 24 }, 0..) |n, j| data.train[2 * i + j] = .{ .x = x, .y = inferred.trajectory(f32, truth, x, 0.005, n * 4, 0, false).x, .steps = n };
        }
        var hs = rng.Stream.region(seed, 0x494e4648, 0);
        for (&data.held) |*o| {
            const x = start(&hs);
            o.* = .{ .x = x, .y = inferred.trajectory(f32, truth, x, 0.005, 96, 0, false).x, .steps = 24 };
        }
        return data;
    }
};
pub fn bin(x: [2]f32, lo: f32, hi: f32) usize {
    if (x[0] < lo or x[0] >= hi or x[1] < lo or x[1] >= hi) return 16;
    const a: usize = @intFromFloat((x[0] - lo) * 4 / (hi - lo));
    const b: usize = @intFromFloat((x[1] - lo) * 4 / (hi - lo));
    return a + 4 * b;
}
pub const Batch = struct {
    g: [count]f32 = zero,
    h: [count]f32 = zero,
    residual: [32]f32 = .{0} ** 32,
    spatial: [17]f64 = .{0} ** 17,
    paths: [17]u32 = .{0} ** 17,
    se: f64 = 0,
    rhs: u64 = 0,
};
pub fn batch(w: [count]f32, data: *const Data, omega: f32) Batch {
    var b = Batch{};
    for (data.train, 0..) |o, oi| {
        var z = engine.State(f32){ .x = o.x };
        b.paths[bin(z.x, 0, 1)] += 1;
        for (0..o.steps) |_| {
            z = engine.advance(f32, w, z, 0.02, omega, false);
            b.paths[bin(z.x, 0, 1)] += 1;
            b.rhs += 2;
        }
        for (0..2) |a| {
            const r = z.x[a] - o.y[a];
            b.residual[oi] += r * r;
            for (0..count) |i| {
                b.g[i] += r * z.s[i][a] / data.train.len;
                b.h[i] += z.s[i][a] * z.s[i][a] / data.train.len;
            }
        }
        b.se += b.residual[oi];
        b.spatial[bin(o.x, 0.15, 0.85)] += b.residual[oi];
    }
    return b;
}
pub fn endpointRms(w: [count]f32, observations: []const Observation, omega: f32) f64 {
    var se: f64 = 0;
    for (observations) |o| {
        const z = engine.trajectory(f32, w, o.x, 0.02, o.steps, omega, false);
        for (0..2) |a| se += @as(f64, z.x[a] - o.y[a]) * (z.x[a] - o.y[a]);
    }
    return @sqrt(se / @as(f64, @floatFromInt(observations.len)));
}
pub const Model = struct {
    w: [count]f32 = zero,
    active: [count]bool = .{true} ** 9 ++ .{false} ** 32,
    m: [count]f32 = zero,
    v: [count]f32 = zero,
    beta1: [count]f32 = .{1} ** count,
    beta2: [count]f32 = .{1} ** count,
    k: usize = 9,
    pub fn birth(self: *Model, i: usize) void {
        std.debug.assert(!self.active[i] and self.k < cap);
        std.debug.assert(self.w[i] == 0 and self.m[i] == 0 and self.v[i] == 0);
        self.active[i] = true;
        self.k += 1;
    }
    pub fn update(self: *Model, g: [count]f32) f64 {
        var change: f64 = 0;
        for (0..count) |i| {
            if (!self.active[i]) continue;
            self.beta1[i] *= 0.9;
            self.beta2[i] *= 0.999;
            self.m[i] = 0.9 * self.m[i] + 0.1 * g[i];
            self.v[i] = 0.999 * self.v[i] + 0.001 * g[i] * g[i];
            const delta = 0.003 * (self.m[i] / (1 - self.beta1[i])) / (@sqrt(self.v[i] / (1 - self.beta2[i])) + 1e-8);
            self.w[i] -= delta;
            change += @abs(delta);
        }
        return change;
    }
};
pub const Candidate = struct { i: usize, score: f32 };
pub fn best(m: *const Model, b: *const Batch) Candidate {
    var result = Candidate{ .i = 9, .score = 0 };
    for (9..count) |i| {
        if (m.active[i] or b.h[i] <= 0) continue;
        const score = b.g[i] * b.g[i] / (2 * b.h[i]);
        if (score > result.score) result = .{ .i = i, .score = score };
    }
    return result;
}
const Report = struct {
    k: usize,
    late_births: usize,
    requests: usize,
    denied: usize,
    heldout: f64,
    train: f64,
    seconds: f64,
    rhs: u64,
    coefficient_updates: u64,
};
fn run(seed: u64, data: *const Data, omega: f32, adaptive: bool) !Report {
    var m = Model{};
    var late: usize = 0;
    var requests: usize = 0;
    var denied: usize = 0;
    var rhs: u64 = 0;
    var coefficient_updates: u64 = 0;
    var change: f64 = 0;
    var timer = try std.time.Timer.start();
    for (1..1201) |step| {
        const b = batch(m.w, data, omega);
        rhs += b.rhs;
        const candidate = best(&m, &b);
        const checkpoint = step % 40 == 0;
        const old_k = m.k;
        var born: i32 = -1;
        if (checkpoint and step > 400 and candidate.score > thresholds.OBS3_BIRTH_GAIN and adaptive) {
            requests += 1;
            if (m.k < cap) {
                const i = candidate.i;
                const sh = shape(i);
                var coverage: f32 = 0;
                for (0..count) |j| if (m.active[j]) {
                    coverage = @max(coverage, marl.gaussian(shape(j), sh.mu));
                };
                var rs: f64 = 0;
                var weight: f64 = 0;
                for (data.train, b.residual) |o, r| {
                    const phi = marl.gaussian(sh, .{ o.x[0], o.x[1], 0.5 });
                    weight += phi;
                    rs += @as(f64, phi) * r;
                }
                std.debug.print("OBS3_BIRTH,{d},{d:.1},{d},{d},{d:.4},{d:.4},{d:.4},{e},{e},{e},{e},{e}\n", .{ seed, omega, step, i, sh.mu[0], sh.mu[1], 1 / sh.l[0], coverage, rs / @max(weight, 1e-30), b.g[i], b.h[i], candidate.score });
                m.birth(i);
                born = @intCast(i);
                if (step > 800) late += 1;
            } else denied += 1;
        }
        if (checkpoint) {
            const held = endpointRms(m.w, &data.held, omega);
            std.debug.print("OBS3_HISTORY,{d},{d:.1},{d},{d},{d},{d},{d:.7},{d:.7},{d},{d},{d},{e},{e},{d},{d},{d}\n", .{ seed, omega, @intFromBool(adaptive), step, old_k, m.k, @sqrt(b.se / data.train.len), held, born, requests, denied, candidate.score, change, rhs, rhs * count, coefficient_updates });
            std.debug.print("OBS3_SPATIAL,{d},{d:.1},{d},{d}", .{ seed, omega, @intFromBool(adaptive), step });
            for (b.spatial) |v| std.debug.print(",{e}", .{v});
            for (b.paths) |v| std.debug.print(",{d}", .{v});
            std.debug.print("\n", .{});
            change = 0;
        }
        coefficient_updates += m.k;
        change += m.update(b.g);
        for (0..count) |i| if (!m.active[i]) try testing.expectEqual(@as(f32, 0), m.w[i]);
        try testing.expect(m.k <= cap);
    }
    return .{ .k = m.k, .late_births = late, .requests = requests, .denied = denied, .heldout = endpointRms(m.w, &data.held, omega), .train = endpointRms(m.w, &data.train, omega), .seconds = @as(f64, @floatFromInt(timer.read())) / 1e9, .rhs = rhs, .coefficient_updates = coefficient_updates };
}

test "G50 (a) dormant candidates and zero-weight births preserve the trajectory" {
    const wf = inferred.truthWeights(7);
    var m = Model{};
    @memcpy(m.w[0..9], &wf);
    const x = [2]f32{ 0.31, 0.42 };
    const small = inferred.trajectory(f32, wf, x, 0.02, 24, 0.3, false);
    const large = engine.trajectory(f32, m.w, x, 0.02, 24, 0.3, false);
    try testing.expectEqualDeep(small.x, large.x);
    for (0..9) |i| try testing.expectEqualDeep(small.s[i], large.s[i]);
    m.birth(25);
    try testing.expectEqualDeep(large, engine.trajectory(f32, m.w, x, 0.02, 24, 0.3, false));
    // A new fine coefficient also carries a correctly differentiated path.
    var w: [count]f64 = undefined;
    for (&w, m.w) |*a, b| a.* = b;
    const z = engine.trajectory(f64, w, .{ 0.31, 0.42 }, 0.02, 24, 0.3, false);
    const eps: f64 = 1e-5;
    w[25] += eps;
    const plus = engine.trajectory(f64, w, .{ 0.31, 0.42 }, 0.02, 24, 0.3, false);
    w[25] -= 2 * eps;
    const minus = engine.trajectory(f64, w, .{ 0.31, 0.42 }, 0.02, 24, 0.3, false);
    for (0..2) |a| {
        const fd = (plus.x[a] - minus.x[a]) / (2 * eps);
        try testing.expect(@abs(fd - z.s[25][a]) <= thresholds.OBS2_GRAD_ABS + thresholds.OBS2_GRAD_REL * @max(@abs(fd), @abs(z.s[25][a])));
    }
    _ = m.update(.{1} ** count);
    try testing.expect(m.w[25] != 0);
    for (26..count) |i| try testing.expectEqual(@as(f32, 0), m.w[i]);
}

test "G50 (b) adaptive inverse fitting under matched observations and candidate budgets" {
    var births = [_]usize{0} ** 2;
    var late = [_]usize{0} ** 2;
    var held = [_]f64{0} ** 2;
    for ([_]u64{ 7, 19, 41 }) |seed| {
        const data = Data.init(seed);
        for ([_]f32{ 0, 0.3 }, 0..) |omega, oi| {
            for ([_]bool{ false, true }) |adaptive| {
                const r = try run(seed, &data, omega, adaptive);
                try testing.expectEqual(@as(u64, 1_228_800), r.rhs);
                if (!adaptive) try testing.expectEqual(@as(usize, 9), r.k);
                if (adaptive) {
                    births[oi] += r.k - 9;
                    late[oi] += r.late_births;
                    held[oi] += r.heldout * r.heldout;
                }
                std.debug.print("OBS3_FINAL,{d},{d:.1},{d},{d},{d},{d},{d},{e},{e},{d},{d},{d},{d:.3}\n", .{ seed, omega, @intFromBool(adaptive), r.k, r.late_births, r.requests, r.denied, r.train, r.heldout, r.rhs, r.rhs * count, r.coefficient_updates, r.seconds });
            }
        }
    }
    std.debug.print("OBS3_PREDICTIONS births correct/wrong {d}/{d} {s}; late {d}/{d} {s}; heldout RMS ratio {d:.6} {s}\n", .{ births[0], births[1], if (births[1] > births[0]) "HELD" else "REFUTED", late[0], late[1], if (late[1] > late[0]) "HELD" else "REFUTED", @sqrt(held[0] / held[1]), if (held[0] < held[1]) "HELD" else "REFUTED" });
}
