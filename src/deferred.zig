//! ALG-2: checkpoint fits and the field read between them.
//! This experiment owns its evolving models; MARL itself knows nothing
//! about time or advection. All target values come from an immutable
//! checkpoint model, never the cheap pushed view or the analytic blob.
const std = @import("std");
const builtin = @import("builtin");
const marl = @import("marl.zig");
const field = @import("field.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");
const testing = std.testing;

pub const Options = struct {
    field_opts: field.Options,
    interval: u32 = 10,
    total_exemplars: u64 = 240_000,
    probes_per_frame: usize = 128,

    pub fn best() Options {
        return .{ .field_opts = field.Options.best() };
    }
};

/// A view of an immutable checkpoint through its pending flow map.
/// `model` must outlive the view and its parameters must not change while
/// it is read. Model.predict still owns mutable gather scratch: this is
/// the serial experimental surface, not concurrent snapshot publication.
pub const Pullback = struct {
    model: *marl.Model,
    flow: field.Flow,
    dt: f32,
    steps: u32,

    pub fn predict(self: Pullback, x: [3]f32) !f32 {
        const p = if (self.steps == 0) x else field.backtrace(self.flow, x, self.dt * @as(f32, @floatFromInt(self.steps)), self.steps);
        return (try self.model.predict(p))[0];
    }
};

fn clone(gpa: std.mem.Allocator, model: *const marl.Model) !marl.Model {
    var result = try marl.Model.init(gpa, model.opts);
    errdefer result.deinit();
    try result.reseedFrom(model);
    // reseedFrom copies topology, not the original per-region summation
    // order. Rehoming during learning changes that order; the first G47
    // run caught a two-ULP mismatch before any pending flow existed.
    // This copy is a numerical checkpoint, so preserve its evaluation
    // order as well as its parameters. No global MARL contract changes.
    for (model.regions, result.regions) |from, *to| @memcpy(to.own.items, from.own.items);
    result.bias = model.bias;
    result.bias_n = model.bias_n;
    return result;
}

fn sourcePoint(b: field.Blob, st: *rng.Stream) [3]f32 {
    while (true) {
        var p: [3]f32 = undefined;
        var d2: f32 = 0;
        inline for (0..3) |a| {
            p[a] = b.c[a] + (2 * st.unit() - 1) * 4 * b.s;
            d2 += (p[a] - b.c[a]) * (p[a] - b.c[a]);
        }
        if (d2 <= 16 * b.s * b.s and p[0] >= 0 and p[0] <= 1 and p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1) return p;
    }
}

/// Fit once to samples carried from the previous checkpoint. Sampling
/// coordinates trace the original blob's four-width ball through the
/// volume-preserving fixture. This is a declared sampling measure, not a
/// general-purpose support discovery algorithm.
fn materialize(gpa: std.mem.Allocator, checkpoint: *marl.Model, flow: field.Flow, o: Options, previous: u32, current: u32, n: u64, st: *rng.Stream) !marl.Model {
    var student = try marl.Model.init(gpa, checkpoint.opts);
    errdefer student.deinit();
    const dt = o.field_opts.dt();
    for (0..n) |_| {
        const start = sourcePoint(o.field_opts.blob, st);
        const p = if (previous == 0) start else field.forward(flow, start, dt * @as(f32, @floatFromInt(previous)), previous);
        const x = field.forward(flow, p, dt * @as(f32, @floatFromInt(current - previous)), current - previous);
        _ = try student.observe(x, try checkpoint.predict(p));
    }
    return student;
}

const Timeline = struct {
    x: [][3]f32,
    truth: []f32,
    original: []f32,
    anchor: []f64,
    n: usize,

    fn deinit(self: Timeline, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.truth);
        gpa.free(self.original);
        gpa.free(self.anchor);
    }

    fn init(gpa: std.mem.Allocator, initial: *marl.Model, flow: field.Flow, o: Options) !Timeline {
        const count = o.probes_per_frame * o.field_opts.steps_per_rev;
        const x = try gpa.alloc([3]f32, count);
        errdefer gpa.free(x);
        const truth = try gpa.alloc(f32, count);
        errdefer gpa.free(truth);
        const original = try gpa.alloc(f32, count);
        errdefer gpa.free(original);
        const anchor = try gpa.alloc(f64, o.field_opts.steps_per_rev);
        errdefer gpa.free(anchor);
        var st = rng.Stream.region(o.field_opts.seed, 0x41325052, 0);
        for (0..o.field_opts.steps_per_rev) |fi| {
            const step: u32 = @intCast(fi + 1);
            const t = o.field_opts.dt() * @as(f32, @floatFromInt(step));
            const sub = step * o.field_opts.ref_sub;
            const c = field.forward(flow, o.field_opts.blob.c, t, sub);
            var pr = try field.ballProbes(gpa, c, 3 * o.field_opts.blob.s, o.probes_per_frame, &st);
            defer pr.deinit(gpa);
            var s1: f64 = 0;
            var s2: f64 = 0;
            for (pr.x, 0..) |q, pi| {
                const i = fi * o.probes_per_frame + pi;
                x[i] = q;
                const p = field.backtrace(flow, q, t, sub);
                truth[i] = o.field_opts.blob.at(p);
                original[i] = (try initial.predict(p))[0];
                s1 += truth[i];
                s2 += @as(f64, truth[i]) * truth[i];
            }
            const n: f64 = @floatFromInt(o.probes_per_frame);
            anchor[fi] = @sqrt(s2 / n - (s1 / n) * (s1 / n));
        }
        return .{ .x = x, .truth = truth, .original = original, .anchor = anchor, .n = o.probes_per_frame };
    }
};

pub const Report = struct {
    interval: u32,
    fits: u32 = 0,
    exemplars: u64 = 0,
    kernels: usize = 0,
    peak_live_kernels: usize = 0,
    mean_cheap_ratio: f64 = 0,
    mean_pullback_ratio: f64 = 0,
    mean_cheap_source_rms: f64 = 0,
    mean_pullback_source_rms: f64 = 0,
    final_ratio: f64 = 0,
    global_rms: f64 = 0,
    mass_ratio: f64 = 0,
    backtrace_steps: u64 = 0,
    fit_seconds: f64 = 0,
    seconds: f64 = 0,
};

fn run(gpa: std.mem.Allocator, initial: *const marl.Model, flow: field.Flow, o: Options, timeline: Timeline) !Report {
    const steps = o.field_opts.steps_per_rev;
    if (o.interval == 0 or steps % o.interval != 0) return error.InvalidInterval;
    const fits = steps / o.interval;
    if (o.total_exemplars % fits != 0) return error.IndivisibleBudget;
    const per_fit = o.total_exemplars / fits;
    var checkpoint = try clone(gpa, initial);
    defer checkpoint.deinit();
    var cheap = try clone(gpa, initial);
    defer cheap.deinit();
    var scratch = std.ArrayListUnmanaged(bool){};
    defer scratch.deinit(gpa);
    var rep = Report{ .interval = o.interval, .peak_live_kernels = 2 * initial.kernels.items.len };
    var previous: u32 = 0;
    var st = rng.Stream.region(o.field_opts.seed, 0x41324649, 0);
    var timer = try std.time.Timer.start();
    for (1..steps + 1) |si| {
        const step: u32 = @intCast(si);
        if (step % o.interval == 0) {
            var fit_timer = try std.time.Timer.start();
            var next = try materialize(gpa, &checkpoint, flow, o, previous, step, per_fit, &st);
            errdefer next.deinit();
            const next_cheap = try clone(gpa, &next);
            rep.peak_live_kernels = @max(rep.peak_live_kernels, checkpoint.kernels.items.len + cheap.kernels.items.len + 2 * next.kernels.items.len);
            checkpoint.deinit();
            cheap.deinit();
            checkpoint = next;
            cheap = next_cheap;
            previous = step;
            rep.fits += 1;
            rep.exemplars += checkpoint.stats.exemplars;
            rep.fit_seconds += @as(f64, @floatFromInt(fit_timer.read())) / 1e9;
        } else {
            try scratch.resize(gpa, cheap.kernels.items.len);
            const moved = try field.pushForward(&cheap, .{ .exact = flow }, o.field_opts.dt(), scratch.items);
            if (moved.refused != 0) return error.TransportRefused;
        }
        const view = Pullback{ .model = &checkpoint, .flow = flow, .dt = o.field_opts.dt(), .steps = step - previous };
        var cheap_se: f64 = 0;
        var view_se: f64 = 0;
        var cheap_source: f64 = 0;
        var view_source: f64 = 0;
        for (0..timeline.n) |pi| {
            const idx = (si - 1) * timeline.n + pi;
            const a = (try cheap.predict(timeline.x[idx]))[0];
            const b = try view.predict(timeline.x[idx]);
            const truth = timeline.truth[idx];
            const original = timeline.original[idx];
            cheap_se += (@as(f64, a) - truth) * (@as(f64, a) - truth);
            view_se += (@as(f64, b) - truth) * (@as(f64, b) - truth);
            cheap_source += (@as(f64, a) - original) * (@as(f64, a) - original);
            view_source += (@as(f64, b) - original) * (@as(f64, b) - original);
            if (view.steps == 0) try testing.expectEqual(@as(u32, @bitCast(a)), @as(u32, @bitCast(b)));
        }
        rep.backtrace_steps += @as(u64, view.steps) * timeline.n;
        const n: f64 = @floatFromInt(timeline.n);
        rep.final_ratio = @sqrt(cheap_se / n) / timeline.anchor[si - 1];
        rep.mean_cheap_ratio += rep.final_ratio / @as(f64, @floatFromInt(steps));
        rep.mean_pullback_ratio += (@sqrt(view_se / n) / timeline.anchor[si - 1]) / @as(f64, @floatFromInt(steps));
        rep.mean_cheap_source_rms += @sqrt(cheap_source / n) / @as(f64, @floatFromInt(steps));
        rep.mean_pullback_source_rms += @sqrt(view_source / n) / @as(f64, @floatFromInt(steps));
    }
    rep.seconds = @as(f64, @floatFromInt(timer.read())) / 1e9;
    rep.kernels = checkpoint.kernels.items.len;
    rep.mass_ratio = field.mass(&checkpoint) / field.mass(initial);
    var ps = rng.Stream.region(o.field_opts.seed, 0x4132474c, 0);
    var global = try field.cubeProbes(gpa, 1024, &ps);
    defer global.deinit(gpa);
    rep.global_rms = (try field.score(&checkpoint, o.field_opts.blob, flow, o.field_opts.dt() * @as(f32, @floatFromInt(steps)), global, steps * o.field_opts.ref_sub)).rms;
    return rep;
}

fn print(rep: Report, seed: u64) void {
    std.debug.print("  {d:>3} {d:>2} {d:>4} {d:>7} {d:>6} {d:>6} {d:>9.4} {d:>9.4} {d:>9.4} {d:>9.5} {d:>8.3} {d:>9} {d:>7.2}\n", .{
        seed,                 rep.interval,            rep.fits,        rep.exemplars,  rep.kernels,    rep.peak_live_kernels,
        rep.mean_cheap_ratio, rep.mean_pullback_ratio, rep.final_ratio, rep.global_rms, rep.mass_ratio, rep.backtrace_steps,
        rep.fit_seconds,
    });
    std.debug.print("      direct source RMS: cheap {d:.6}, pullback {d:.6}; measured total {d:.2} s (includes probe scoring)\n", .{ rep.mean_cheap_source_rms, rep.mean_pullback_source_rms, rep.seconds });
}

test "G47 (a) deferred materialisation at equal total fitting evidence" {
    const gpa = testing.allocator;
    const flow = field.Flow{ .swirl = .{ .amp = 0.35355339 } };
    const intervals = [_]u32{ 1, 2, 5, 10, 20, 40 };
    var mean = [_]f64{0} ** intervals.len;
    var final = [_]f64{0} ** intervals.len;
    std.debug.print("\n  G47 [{s}] 240k exemplars TOTAL; means include every published frame\n", .{@tagName(builtin.mode)});
    std.debug.print("  seed k fits    obs   finalK liveK  cheap/const exact/const final/const globalRMS    mass  traceSteps fit sec\n", .{});
    for ([_]u64{ 7, 19, 41 }) |seed| {
        var o = Options.best();
        o.field_opts.seed = seed;
        o.field_opts.m.seed = seed;
        var initial = try field.fitBlob(gpa, o.field_opts.blob, o.field_opts);
        defer initial.deinit();
        const timeline = try Timeline.init(gpa, &initial, flow, o);
        defer timeline.deinit(gpa);
        for (intervals, 0..) |interval, i| {
            o.interval = interval;
            const rep = try run(gpa, &initial, flow, o, timeline);
            print(rep, seed);
            try testing.expectEqual(o.total_exemplars, rep.exemplars);
            try testing.expectEqual(o.field_opts.steps_per_rev / interval, rep.fits);
            if (interval == 1) try testing.expectEqual(@as(u64, 0), rep.backtrace_steps);
            mean[i] += rep.mean_cheap_ratio;
            final[i] += rep.final_ratio;
        }
    }
    var best: usize = 1;
    for (2..intervals.len - 1) |i| if (mean[i] < mean[best]) {
        best = i;
    };
    const endpoint = @min(mean[0], mean[intervals.len - 1]);
    std.debug.print("  best interior k={d}: mean error {d:.4} vs best endpoint {d:.4}; final k40/k1={d:.4}\n", .{ intervals[best], mean[best] / 3, endpoint / 3, final[5] / final[0] });
    try testing.expect(mean[best] * thresholds.ALG2_INTERIOR_MARGIN < endpoint);
    try testing.expect(final[5] * thresholds.ALG2_FINAL_MARGIN < final[0]);
}

test "G47 (b) give every materialisation the initial fit's evidence budget" {
    const gpa = testing.allocator;
    const flow = field.Flow{ .swirl = .{ .amp = 0.35355339 } };
    std.debug.print("\n  G47 (b) [{s}] 60k exemplars PER FIT: unequal work, labelled as a control\n", .{@tagName(builtin.mode)});
    std.debug.print("  seed k fits    obs   finalK liveK  cheap/const exact/const final/const globalRMS    mass  traceSteps fit sec\n", .{});
    for ([_]u64{ 7, 19, 41 }) |seed| {
        var o = Options.best();
        o.field_opts.seed = seed;
        o.field_opts.m.seed = seed;
        var initial = try field.fitBlob(gpa, o.field_opts.blob, o.field_opts);
        defer initial.deinit();
        const timeline = try Timeline.init(gpa, &initial, flow, o);
        defer timeline.deinit(gpa);
        for ([_]u32{ 1, 10, 40 }) |interval| {
            o.interval = interval;
            o.total_exemplars = o.field_opts.fit_exemplars * (o.field_opts.steps_per_rev / interval);
            const rep = try run(gpa, &initial, flow, o, timeline);
            print(rep, seed);
            try testing.expectEqual(o.total_exemplars, rep.exemplars);
            try testing.expectEqual(o.field_opts.steps_per_rev / interval, rep.fits);
        }
    }
}

test "G47 (c) a pullback reads the checkpoint at the preimage" {
    const gpa = testing.allocator;
    var m = try marl.Model.init(gpa, .{ .regions = 4, .support_edges = 2 });
    defer m.deinit();
    try m.kernels.append(gpa, .{
        .p = .{ 0.75, 0.5, 0.5, @log(@as(f32, 20)), @log(@as(f32, 20)), @log(@as(f32, 20)), 0, 0, 0, 1 },
        .owner = 0,
        .mu0 = .{ 0.75, 0.5, 0.5 },
        .reach = 0,
        .born_at = 0,
    });
    const dead = [_]bool{false};
    try m.compact(&dead);
    const dt = field.Options.best().dt();
    const view = Pullback{
        .model = &m,
        .flow = .{ .rotation = .{ .omega = 1, .c = .{ 0.5, 0.5, 0.5 } } },
        .dt = dt,
        .steps = 10,
    };
    const q = [3]f32{ 0.5, 0.75, 0.5 };
    try testing.expectApproxEqAbs(@as(f32, 1), try view.predict(q), thresholds.ALG1_WARP_EXACT);
    // Executable mutation: omit the coordinate pullback. This query is
    // outside the original kernel's support, so the mistaken read is zero.
    try testing.expectEqual(@as(f32, 0), (try m.predict(q))[0]);
    const identity = Pullback{ .model = &m, .flow = view.flow, .dt = dt, .steps = 0 };
    try testing.expectEqual((try m.predict(q))[0], try identity.predict(q));
}
