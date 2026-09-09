//! OBS-1: scalar state evidence through a known, parameter-independent flow.
//! No differentiation through topology changes, fitting, or learned velocity.
const std = @import("std");
const marl = @import("marl.zig");
const field = @import("field.zig");
const deferred = @import("deferred.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");
const testing = std.testing;

/// Assimilate into the source state. The caller must own the model for
/// mutation: this invalidates previously published views of that state.
/// For fixed Phi, d M_theta(Phi^-1(x))/d theta is MARL's existing local
/// derivative at the preimage. Responsibility/births retain MARL semantics.
pub fn assimilate(view: deferred.Pullback, x: [3]f32, y: f32) !marl.Event {
    const p = if (view.steps == 0) x else field.backtrace(view.flow, x, view.dt * @as(f32, @floatFromInt(view.steps)), view.steps);
    return view.model.observe(p, .{y});
}

fn copy(gpa: std.mem.Allocator, initial: *const marl.Model) !marl.Model {
    var m = try marl.Model.init(gpa, initial.opts);
    errdefer m.deinit();
    try m.reseedFrom(initial);
    for (initial.regions, m.regions) |from, *to| @memcpy(to.own.items, from.own.items);
    m.bias = initial.bias;
    m.bias_n = initial.bias_n;
    return m;
}

const rotation = field.Flow{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } };

// Independent analytic sensor coordinates: no shared forward/backward RK4
// implementation can hide an integration error in the experiment.
fn rotate(p: [3]f32, t: f32) [3]f32 {
    const c = @cos(t);
    const s = @sin(t);
    return .{ 0.5 + c * (p[0] - 0.5) - s * (p[1] - 0.5), 0.5 + s * (p[0] - 0.5) + c * (p[1] - 0.5), p[2] };
}

fn viewAt(m: *marl.Model, step: u32) deferred.Pullback {
    return .{ .model = m, .flow = rotation, .dt = field.Options.best().dt() / 4, .steps = 4 * step };
}

fn rms(m: *marl.Model, b: field.Blob, source: []const [3]f32, step: u32) !f64 {
    var se: f64 = 0;
    const view = viewAt(m, step);
    for (source) |p| {
        const q = rotate(p, field.Options.best().dt() * @as(f32, @floatFromInt(step)));
        const d = @as(f64, try view.predict(q)) - b.at(p);
        se += d * d;
    }
    return @sqrt(se / @as(f64, @floatFromInt(source.len)));
}

test "G48 (a) delayed scalar evidence corrects the source state under known flow" {
    const gpa = testing.allocator;
    var totals = [_]f64{0} ** 4;
    const names = [_][]const u8{ "prior", "pullback", "wrong-coordinate", "source-oracle" };
    std.debug.print("\n G48: known rotation, 30k observations at steps 1..40; future step 60 held out\n", .{});
    for ([_]u64{ 7, 19, 41 }) |seed| {
        var o = field.Options.best();
        o.seed = seed;
        o.m.seed = seed;
        var displaced = o.blob;
        displaced.c[0] += 0.04;
        var initial = try field.fitBlob(gpa, displaced, o);
        defer initial.deinit();
        var models: [4]marl.Model = undefined;
        var made: usize = 0;
        defer for (models[0..made]) |*m| m.deinit();
        for (&models) |*m| {
            m.* = try copy(gpa, &initial);
            made += 1;
        }
        var st = rng.Stream.region(seed, 0x4f425331, 0);
        var observations = try field.ballProbes(gpa, o.blob.c, 4 * o.blob.s, 30_000, &st);
        defer observations.deinit(gpa);
        var timer = try std.time.Timer.start();
        for (observations.x) |p| {
            const step: u32 = 1 + @as(u32, @intFromFloat(st.unit() * 40));
            const q = rotate(p, o.dt() * @as(f32, @floatFromInt(step)));
            const y = o.blob.at(p); // synthetic sensor, never supplied as a field to the learner
            _ = try assimilate(viewAt(&models[1], step), q, y);
            _ = try models[2].observe(q, .{y});
            _ = try models[3].observe(p, .{y});
        }
        const elapsed = @as(f64, @floatFromInt(timer.read())) / 1e9;
        var ps = rng.Stream.region(seed, 0x4f425350, 0);
        var local = try field.ballProbes(gpa, o.blob.c, 3 * o.blob.s, 2048, &ps);
        defer local.deinit(gpa);
        var global = try field.cubeProbes(gpa, 4096, &ps);
        defer global.deinit(gpa);
        for (&models, 0..) |*m, arm| {
            const a = try rms(m, o.blob, local.x, 10);
            const b = try rms(m, o.blob, local.x, 40);
            const future = try rms(m, o.blob, local.x, 60);
            const whole = try rms(m, o.blob, global.x, 60);
            totals[arm] += future * future;
            try testing.expectEqual(@as(u64, if (arm == 0) 0 else 30_000), m.stats.exemplars);
            std.debug.print("  seed {d} {s}: local t10/40/60 {d:.6}/{d:.6}/{d:.6}; source-cube future {d:.6}; K {d}, observations {d}\n", .{ seed, names[arm], a, b, future, whole, m.kernels.items.len, m.stats.exemplars });
        }
        std.debug.print("  seed {d}: all three assimilation arms {d:.3} s\n", .{ seed, elapsed });
    }
    std.debug.print("  pooled future RMS ratios: corrected/prior {d:.5}, corrected/wrong {d:.5}, corrected/oracle {d:.5}\n", .{ @sqrt(totals[1] / totals[0]), @sqrt(totals[1] / totals[2]), @sqrt(totals[1] / totals[3]) });
    try testing.expect(totals[1] * thresholds.OBS1_GAIN_MARGIN < totals[0]);
    try testing.expect(totals[1] * thresholds.OBS1_GAIN_MARGIN < totals[2]);
}

test "G48 (b) delayed weight derivative and update use the preimage" {
    const gpa = testing.allocator;
    var m = try marl.Model.init(gpa, .{ .regions = 4, .support_edges = 2 });
    defer m.deinit();
    try m.kernels.append(gpa, .{
        .p = .{ 0.75, 0.5, 0.5, @log(@as(f32, 20)), @log(@as(f32, 20)), @log(@as(f32, 20)), 0, 0, 0, 0.5 },
        .owner = 0,
        .mu0 = .{ 0.75, 0.5, 0.5 },
        .reach = 0,
        .born_at = 0,
    });
    try m.compact(&.{false});
    const q = [3]f32{ 0.5, 0.75, 0.5 };
    const view = viewAt(&m, 10);
    const p = field.backtrace(rotation, q, view.dt * @as(f32, @floatFromInt(view.steps)), view.steps);
    const derivative = marl.gaussian(m.kernels.items[0].shape(), p);
    const eps: f32 = 0.01;
    m.kernels.items[0].p[9] = 0.5 + eps;
    const plus = try view.predict(q);
    m.kernels.items[0].p[9] = 0.5 - eps;
    const minus = try view.predict(q);
    m.kernels.items[0].p[9] = 0.5;
    try testing.expectApproxEqAbs(derivative, (plus - minus) / (2 * eps), thresholds.ALG1_WARP_EXACT);
    // Omitted inverse map gives an exactly zero derivative at this query.
    try testing.expectEqual(@as(f32, 0), marl.gaussian(m.kernels.items[0].shape(), q));
    var direct = try copy(gpa, &m);
    defer direct.deinit();
    const a = try assimilate(view, q, 0.8);
    const b = try direct.observe(p, .{0.8});
    try testing.expectEqualDeep(b, a);
    try testing.expectEqualDeep(direct.kernels.items, m.kernels.items);
    try testing.expectEqual((try direct.predict(p))[0], try view.predict(q));
}
