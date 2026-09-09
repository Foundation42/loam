//! OBS-2: short-window trajectory inference on frozen MARL kernel geometry.
//! A coefficient-only experiment, not MARL's adaptive observe algorithm.
const std = @import("std");
const marl = @import("marl.zig");
const field = @import("field.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");
const testing = std.testing;
pub const count = 9;

pub fn shape(i: usize) marl.Shape {
    return .{ .mu = .{ 0.25 + 0.25 * @as(f32, @floatFromInt(i % 3)), 0.25 + 0.25 * @as(f32, @floatFromInt(i / 3)), 0.5 }, .l = .{ 1.0 / 0.22, 0, 1.0 / 0.22, 0, 0, 1.0 / 0.22 } };
}

fn Basis(comptime T: type) type {
    return struct { g: [2]T, h: [2][2]T };
}
fn basis(comptime T: type, i: usize, x: [2]T) Basis(T) {
    const sh = shape(i);
    const inv: T = @as(T, sh.l[0]) * @as(T, sh.l[0]);
    const d = [2]T{ x[0] - @as(T, sh.mu[0]), x[1] - @as(T, sh.mu[1]) };
    const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
    if (r2 > marl.CUTOFF) return .{ .g = .{ 0, 0 }, .h = .{ .{ 0, 0 }, .{ 0, 0 } } };
    const phi = @exp(-0.5 * r2);
    var b: Basis(T) = undefined;
    for (0..2) |a| {
        b.g[a] = -phi * inv * d[a];
        for (0..2) |c| b.h[a][c] = phi * (inv * inv * d[a] * d[c] - if (a == c) inv else @as(T, 0));
    }
    return b;
}

fn State(comptime T: type) type {
    return struct { x: [2]T, s: [count][2]T = .{.{ 0, 0 }} ** count };
}
fn rhs(comptime T: type, w: [count]T, z: State(T), omega: T, omit_position: bool) State(T) {
    var out = State(T){ .x = .{ -omega * (z.x[1] - 0.5), omega * (z.x[0] - 0.5) } };
    var jac = [2][2]T{ .{ 0, -omega }, .{ omega, 0 } };
    var b: [count]Basis(T) = undefined;
    for (0..count) |i| {
        b[i] = basis(T, i, z.x);
        for (0..2) |a| {
            out.x[a] -= w[i] * b[i].g[a];
            for (0..2) |c| jac[a][c] -= w[i] * b[i].h[a][c];
        }
    }
    for (0..count) |i| for (0..2) |a| {
        out.s[i][a] = -b[i].g[a];
        if (!omit_position) for (0..2) |c| {
            out.s[i][a] += jac[a][c] * z.s[i][c];
        };
    };
    return out;
}
fn add(comptime T: type, z: State(T), dz: State(T), dt: T) State(T) {
    var out = z;
    for (0..2) |a| {
        out.x[a] += dt * dz.x[a];
        for (0..count) |i| out.s[i][a] += dt * dz.s[i][a];
    }
    return out;
}
pub fn trajectory(comptime T: type, w: [count]T, x: [2]T, dt: T, steps: u32, omega: T, omit_position: bool) State(T) {
    var z = State(T){ .x = x };
    for (0..steps) |_| {
        const mid = add(T, z, rhs(T, w, z, omega, omit_position), dt / 2);
        z = add(T, z, rhs(T, w, mid, omega, omit_position), dt);
    }
    return z;
}
fn loss(comptime T: type, z: State(T), target: [2]T) T {
    var l: T = 0;
    for (0..2) |a| l += 0.5 * (z.x[a] - target[a]) * (z.x[a] - target[a]);
    return l;
}

fn truthWeights(seed: u64) [count]f32 {
    var st = rng.Stream.region(seed, 0x494e4657, 0);
    var w: [count]f32 = undefined;
    for (&w, 0..) |*v, i| v.* = (0.015 + 0.03 * st.unit()) * (if (i % 2 == 0) @as(f32, 1) else -1);
    return w;
}

test "G49 (a) trajectory coefficient sensitivities survive multiscale finite differences" {
    var worst_rel: f64 = 0;
    var worst_abs: f64 = 0;
    var smallest: f64 = std.math.inf(f64);
    var largest: f64 = 0;
    var rejected: usize = 0;
    var checked: usize = 0;
    var raw_failures = [_]usize{0} ** 3;
    var extrap_rel: f64 = 0;
    var extrap_abs: f64 = 0;
    for ([_]u64{ 7, 19, 41 }) |seed| {
        const wf = truthWeights(seed);
        var w: [count]f64 = undefined;
        for (&w, wf) |*a, b| a.* = b;
        for ([_]u32{ 1, 8, 32, 64 }) |steps| {
            for ([_][2]f64{ .{ 0.35, 0.45 }, .{ 0.82, 0.75 }, .{ 0.02, 0.03 } }) |x| {
                const target = [2]f64{ x[0] + 0.013, x[1] - 0.021 };
                const z = trajectory(f64, w, x, 0.02, steps, 0.3, false);
                const bad = trajectory(f64, w, x, 0.02, steps, 0.3, true);
                for (0..count) |i| {
                    var g: f64 = 0;
                    var bad_g: f64 = 0;
                    for (0..2) |a| {
                        g += (z.x[a] - target[a]) * z.s[i][a];
                        bad_g += (bad.x[a] - target[a]) * bad.s[i][a];
                    }
                    smallest = @min(smallest, @abs(g));
                    largest = @max(largest, @abs(g));
                    for ([_]f64{ 1e-3, 1e-4, 1e-5 }, 0..) |eps, ei| {
                        var plus = w;
                        var minus = w;
                        plus[i] += eps;
                        minus[i] -= eps;
                        const fd = (loss(f64, trajectory(f64, plus, x, 0.02, steps, 0.3, false), target) - loss(f64, trajectory(f64, minus, x, 0.02, steps, 0.3, false), target)) / (2 * eps);
                        const delta = @abs(fd - g);
                        const scale = @max(@abs(fd), @abs(g));
                        worst_abs = @max(worst_abs, delta);
                        if (scale > thresholds.OBS2_GRAD_ABS / thresholds.OBS2_GRAD_REL) worst_rel = @max(worst_rel, delta / scale);
                        if (@abs(fd - bad_g) > thresholds.OBS2_GRAD_ABS + thresholds.OBS2_GRAD_REL * @max(@abs(fd), @abs(bad_g))) rejected += 1;
                        checked += 1;
                        if (delta > thresholds.OBS2_GRAD_ABS + thresholds.OBS2_GRAD_REL * scale) raw_failures[ei] += 1;
                        // Raw large-h comparisons remain a recorded refutation.
                        // Cancel the central difference's O(h²) truncation term;
                        // the original absolute/relative tolerances stay fixed.
                        plus[i] = w[i] + eps / 2;
                        minus[i] = w[i] - eps / 2;
                        const half = (loss(f64, trajectory(f64, plus, x, 0.02, steps, 0.3, false), target) - loss(f64, trajectory(f64, minus, x, 0.02, steps, 0.3, false), target)) / eps;
                        const richardson = (4 * half - fd) / 3;
                        const ed = @abs(richardson - g);
                        const es = @max(@abs(richardson), @abs(g));
                        extrap_abs = @max(extrap_abs, ed);
                        if (es > thresholds.OBS2_GRAD_ABS / thresholds.OBS2_GRAD_REL) extrap_rel = @max(extrap_rel, ed / es);
                        try testing.expect(ed <= thresholds.OBS2_GRAD_ABS + thresholds.OBS2_GRAD_REL * es);
                    }
                }
            }
        }
    }
    try testing.expect(rejected > 0);
    std.debug.print("  raw FD failures at 1e-3/1e-4/1e-5: {d}/{d}/{d}; Richardson max abs {e}, relative {e}\n", .{ raw_failures[0], raw_failures[1], raw_failures[2], extrap_abs, extrap_rel });
    std.debug.print("  G49 audit: {d} checks; max abs {e}, relative {e}; |gradient| {e}..{e}; omitted-position mutation rejected {d}\n", .{ checked, worst_abs, worst_rel, smallest, largest, rejected });
    // Independent f32 pin to the existing MARL derivative evaluator.
    for (0..count) |i| {
        const x = [2]f32{ 0.31, 0.62 };
        const b = basis(f32, i, x);
        const jet = field.gaussianJet(shape(i), .{ x[0], x[1], 0.5 });
        for (0..2) |a| try testing.expectApproxEqAbs(jet.g[a], b.g[a], thresholds.ALG1_WARP_EXACT);
    }
}

const Observation = struct { x: [2]f32, y: [2]f32, steps: u32 };
fn start(st: *rng.Stream) [2]f32 {
    return .{ 0.15 + 0.7 * st.unit(), 0.15 + 0.7 * st.unit() };
}
fn endpointRms(w: [count]f32, observations: []const Observation, omega: f32) f64 {
    var se: f64 = 0;
    for (observations) |o| {
        const z = trajectory(f32, w, o.x, 0.02, o.steps, omega, false);
        for (0..2) |a| se += @as(f64, z.x[a] - o.y[a]) * (z.x[a] - o.y[a]);
    }
    return @sqrt(se / @as(f64, @floatFromInt(observations.len)));
}
fn gradientRms(w: [count]f32, truth: [count]f32) f64 {
    var se: f64 = 0;
    for (0..25) |a| for (0..25) |b| {
        const x = [2]f32{ 0.15 + 0.7 * @as(f32, @floatFromInt(a)) / 24, 0.15 + 0.7 * @as(f32, @floatFromInt(b)) / 24 };
        var d = [2]f32{ 0, 0 };
        for (0..count) |i| {
            const jet = basis(f32, i, x);
            for (0..2) |c| d[c] += (w[i] - truth[i]) * jet.g[c];
        }
        for (d) |v| se += @as(f64, v) * v;
    };
    return @sqrt(se / 625);
}

test "G49 (b) infer a frozen potential from endpoints with matched wrong dynamics" {
    var pooled = [_]f64{0} ** 3;
    var field_before: f64 = 0;
    var field_after: f64 = 0;
    for ([_]u64{ 7, 19, 41 }) |seed| {
        const truth = truthWeights(seed);
        var st = rng.Stream.region(seed, 0x494e4654, 0);
        var train: [32]Observation = undefined;
        for (0..16) |i| {
            const x = start(&st);
            for ([_]u32{ 8, 24 }, 0..) |n, j| train[2 * i + j] = .{ .x = x, .y = trajectory(f32, truth, x, 0.005, n * 4, 0, false).x, .steps = n };
        }
        var held: [64]Observation = undefined;
        var hs = rng.Stream.region(seed, 0x494e4648, 0);
        for (&held) |*o| {
            const x = start(&hs);
            o.* = .{ .x = x, .y = trajectory(f32, truth, x, 0.005, 96, 0, false).x, .steps = 24 };
        }
        const zero = [_]f32{0} ** count;
        const baseline = endpointRms(zero, &held, 0);
        pooled[0] += baseline * baseline;
        const fg0 = gradientRms(zero, truth);
        field_before += fg0 * fg0;
        std.debug.print("  G49 seed {d}: baseline heldout {d:.6}, gradient {d:.6}\n", .{ seed, baseline, fg0 });
        for ([_]f32{ 0, 0.3 }, 0..) |omega, arm| {
            std.debug.print("    omega {d:.1} own initial train/heldout {d:.6}/{d:.6}\n", .{ omega, endpointRms(zero, &train, omega), endpointRms(zero, &held, omega) });
            var w = zero;
            var m = zero;
            var v = zero;
            var beta1: f32 = 1;
            var beta2: f32 = 1;
            var timer = try std.time.Timer.start();
            var rhs_calls: u64 = 0;
            for (0..400) |_| {
                var g = zero;
                for (train) |o| {
                    const z = trajectory(f32, w, o.x, 0.02, o.steps, omega, false);
                    rhs_calls += 2 * o.steps;
                    for (0..count) |i| for (0..2) |a| {
                        g[i] += (z.x[a] - o.y[a]) * z.s[i][a] / train.len;
                    };
                }
                beta1 *= 0.9;
                beta2 *= 0.999;
                for (0..count) |i| {
                    m[i] = 0.9 * m[i] + 0.1 * g[i];
                    v[i] = 0.999 * v[i] + 0.001 * g[i] * g[i];
                    w[i] -= 0.003 * (m[i] / (1 - beta1)) / (@sqrt(v[i] / (1 - beta2)) + 1e-8);
                }
            }
            const seconds = @as(f64, @floatFromInt(timer.read())) / 1e9;
            const tr = endpointRms(w, &train, omega);
            const he = endpointRms(w, &held, omega);
            const fg = gradientRms(w, truth);
            var cw: f64 = 0;
            for (w, truth) |a, b| cw += @as(f64, a - b) * (a - b);
            pooled[arm + 1] += he * he;
            if (arm == 0) field_after += fg * fg;
            try testing.expectEqual(@as(u64, 409_600), rhs_calls);
            std.debug.print("    omega {d:.1}: train {d:.6}, heldout {d:.6}, gradient {d:.6}, coefficient {d:.6}; K=9 births=0 updates=400 RHS={d} basis={d}; {d:.3}s\n", .{ omega, tr, he, fg, @sqrt(cw / count), rhs_calls, rhs_calls * count, seconds });
        }
    }
    std.debug.print("  G49 pooled RMS: correct/prior {d:.6}, correct/wrong {d:.6}, gradient/prior {d:.6}\n", .{ @sqrt(pooled[1] / pooled[0]), @sqrt(pooled[1] / pooled[2]), @sqrt(field_after / field_before) });
    try testing.expect(pooled[1] * thresholds.OBS2_GAIN_MARGIN < pooled[0]);
    try testing.expect(pooled[1] * thresholds.OBS2_GAIN_MARGIN < pooled[2]);
    try testing.expect(field_after * thresholds.OBS2_GAIN_MARGIN < field_before);
}
