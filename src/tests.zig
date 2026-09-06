//! The gates. Each names the mutation that must bite (brief §2): a gate
//! that passes under its mutation is a finding about the gate, not a
//! pass. Executable mutations are tests of their own; hand mutations are
//! recorded in the ledger (`docs/implementation-notes.md`) with what they
//! produced. Thresholds live in `thresholds.zig`, PROPOSED until struck.

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const common = @import("common");
const jobs = common.jobs;
const loam = @import("loam.zig");
const lattice = loam.lattice;
const channel = loam.channel;
const brick = loam.brick;
const tree = loam.tree;
const seedbed = loam.seedbed;
const operators = loam.operators;
const guards = loam.guards;
const ray = loam.ray;
const thresholds = loam.thresholds;
const World = loam.World;
const Key = loam.Key;
const Brick = loam.Brick;
const Channel = loam.Channel;
const Front = loam.Front;

fn now(step: u64) loam.Now {
    return .{ .frame = step, .time_ns = step * std.time.ns_per_s };
}

fn run(w: *World, steps: u32, js: ?*jobs.JobSystem) !void {
    var i: u64 = 0;
    while (i <= steps) : (i += 1) try w.step(now(i), js);
}

// ── P1.1: lattice, tree, summaries, the stub ray ─────────────────────────

test "P1.1: a hand-placed blob commits, the guards hold, and the summary is tight" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .blob);
    const snap = w.published();
    try guards.check(snap);
    try testing.expect(snap.brick_count > 8);
    const s = snap.rootSummary();
    try testing.expect(channel.has(s.mask, Channel.density.bit()));
    try testing.expect(channel.has(s.mask, Channel.light.bit()));
    try testing.expect(s.density.max > 0.9 and s.density.max <= 1.0);
    // The blob is at world (20,0,0), radius 6: lattice (524308, 524288, 524288).
    const v = snap.sample(Channel.density.bit(), w.domain.toLattice(.{ 20, 0, 0 }));
    try testing.expect(v > 0.9);
    try testing.expectEqual(@as(f32, 0), snap.sample(Channel.density.bit(), w.domain.toLattice(.{ -20, 0, 0 })));
    try testing.expect(snap.sample(Channel.light.bit(), w.domain.toLattice(.{ -20, 0, 0 })) > 0);
}

test "G6: a ray rejects subtrees from summaries alone" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .blob);
    // A ray along +x through the light sphere and the density blob.
    const c = try seedbed.rayCount(&w, .{ -100, 0, 0 }, .{ 1, 0, 0 }, Channel.density.mask(), .primary);
    try testing.expect(c.crossed > 8); // the denominator is not one item
    try testing.expect(c.sampled >= 1);
    const frac = @as(f64, @floatFromInt(c.sampled)) / @as(f64, @floatFromInt(c.crossed));
    std.debug.print("\nG6: sampled {d} of {d} leaves crossed ({d:.3}), {d} nodes tested\n", .{ c.sampled, c.crossed, frac, c.nodes_tested });
    try testing.expect(frac <= thresholds.G6_MAX_SAMPLED_FRACTION);
}

test "G6 mutation: without summaries every crossed leaf is sampled" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .blob);
    const snap = w.published();
    const o = w.domain.toLattice(.{ -100, 0, 0 });
    var cur = try ray.Cursor.init(gpa, snap, .{ .origin = o, .dir = .{ 1, 0, 0 }, .channels = Channel.density.mask(), .use_summaries = false });
    defer cur.deinit();
    var n: u64 = 0;
    while (try cur.next()) |_| n += 1;
    const c = try seedbed.rayCount(&w, .{ -100, 0, 0 }, .{ 1, 0, 0 }, Channel.density.mask(), .primary);
    try testing.expectEqual(c.crossed, n);
    try testing.expect(n > c.sampled);
}

test "G6: a ray that misses the support samples nothing, and near-to-far holds" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .blob);
    const miss = try seedbed.rayCount(&w, .{ -100, 200, 0 }, .{ 1, 0, 0 }, Channel.density.mask(), .primary);
    try testing.expectEqual(@as(u64, 0), miss.sampled);
    const snap = w.published();
    var cur = try ray.Cursor.init(gpa, snap, .{ .origin = w.domain.toLattice(.{ -100, 0, 0 }), .dir = .{ 1, 0, 0 }, .channels = Channel.light.mask() });
    defer cur.deinit();
    var last: f64 = -1;
    while (try cur.next()) |rv| {
        try testing.expect(rv.t_enter >= last);
        last = rv.t_enter;
    }
}

// ── P1.2: channel blocks and the seam contract ───────────────────────────

test "P1.2: absent channels are unallocated in every brick" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .blob);
    const bs = try w.published().bricks(gpa);
    defer gpa.free(bs);
    var light_only: usize = 0;
    for (bs) |b| {
        try testing.expectEqual(@as(usize, @popCount(b.mask)), b.planes.len);
        if (!b.has(Channel.density.bit())) light_only += 1;
    }
    try testing.expect(light_only > 0);
}

test "P1.2: a value straddling two bricks of different gauge is continuous across the seam" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .seams);
    try guards.check(w.published());
    // Authored blobs write the same value into every holder of a shared
    // point, so on their own they never exercise the anchor rule (a hand
    // mutation that disabled it survived). Diffuse: the two gauges then
    // compute DIFFERENT deltas at shared points, and only the seam pass
    // makes them agree.
    var d = operators.Diffusion{ .bit = Channel.light.bit(), .rate = 0.5 };
    try w.addOperator(operators.operatorOf(operators.Diffusion, &d));
    try run(&w, 3, null);
    try testing.expect(w.total.seam_writes > 0);
    const snap = w.published();
    try guards.check(snap);
    // Two gauges are present.
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    var g0: usize = 0;
    var g1: usize = 0;
    for (bs) |b| {
        if (b.gauge() == 0) g0 += 1 else g1 += 1;
    }
    try testing.expect(g0 > 0 and g1 > 0);
    // Walk across the world along x at several (y, z): the sampled light
    // must not jump between adjacent probes by more than the field's own
    // slope allows.
    var y: f64 = -6;
    while (y <= 6) : (y += 3) {
        var x: f64 = -40;
        var prev = snap.sample(Channel.light.bit(), w.domain.toLattice(.{ x, y, 1.5 }));
        while (x <= 40) : (x += 0.25) {
            const v = snap.sample(Channel.light.bit(), w.domain.toLattice(.{ x, y, 1.5 }));
            try testing.expect(@abs(v - prev) < 0.08);
            prev = v;
        }
    }
    // A point exactly on a shared face reads the same from both holders.
    var holders: [8]*const Brick = undefined;
    var checked: usize = 0;
    for (bs) |b| {
        if (b.gauge() != 0) continue;
        const o = b.origin();
        const p = [3]i64{ @as(i64, o[0]) + 8, @as(i64, o[1]) + 3, @as(i64, o[2]) + 5 };
        const n = snap.findAll(p, &holders);
        if (n < 2) continue;
        const q = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
        const v0 = holders[0].trilinear(Channel.light.bit(), q);
        for (holders[1..n]) |h| {
            try testing.expectApproxEqAbs(v0, h.trilinear(Channel.light.bit(), q), 1e-5);
            if (h.gauge() != holders[0].gauge()) checked += 1;
        }
    }
    try testing.expect(checked > 0); // the gate ran where A ≠ B: a fine/coarse pair was compared
}

test "G7: a shadow-class query gathers fewer channel bytes than a primary one" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    try seedbed.blob(&w, Channel.density.bit(), .{ 0, 0, 0 }, 10, 1.0, 0);
    try seedbed.blob(&w, Channel.albedo.bit(), .{ 0, 0, 0 }, 10, 0.5, 0);
    try seedbed.blob(&w, Channel.emission.bit(), .{ 0, 0, 0 }, 10, 0.2, 0);
    try seedbed.blob(&w, Channel.roughness.bit(), .{ 0, 0, 0 }, 10, 0.3, 0);
    try w.apply();
    const snap = w.published();
    const primary = Channel.density.mask() | Channel.albedo.mask() | Channel.emission.mask() | Channel.roughness.mask();
    const shadow = Channel.density.mask();
    const p = try gatherBytes(snap, primary);
    const s = try gatherBytes(snap, shadow);
    std.debug.print("\nG7: primary {d} bytes, shadow {d} bytes ({d:.3})\n", .{ p, s, @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(p)) });
    try testing.expect(@as(f64, @floatFromInt(s)) <= thresholds.G7_MAX_SHADOW_FRACTION * @as(f64, @floatFromInt(p)));
}

/// Channel bytes a query gathers: the B-spline's 64 coefficients of four
/// bytes per plane touched, for each requested channel the brick holds.
/// The narrow query's instrument — the mutation (ignore the mask) makes
/// this equal.
fn gatherBytes(snap: *const loam.Snapshot, channels: channel.Mask) !u64 {
    var cur = try ray.Cursor.init(testing.allocator, snap, .{ .origin = .{ 524288 - 40, 524288, 524288 }, .dir = .{ 1, 0, 0 }, .channels = channels });
    defer cur.deinit();
    var bytes: u64 = 0;
    while (try cur.next()) |rv| {
        var t = rv.t_enter;
        while (t <= rv.t_exit) : (t += 1) {
            bytes += 64 * 4 * @as(u64, @popCount(rv.brick.mask & channels));
        }
    }
    return bytes;
}

// ── P1.3: operators and the update cycle ─────────────────────────────────

test "diffusion: a point mass spreads to variance 2·D·t per axis and conserves mass" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    // A single hot sample at the lattice centre, in a brick of its own.
    const centre = [3]u32{ 524288, 524288, 524288 };
    const key = Key.containing(0, centre);
    const ru = try w.author(key);
    const o = key.origin();
    try ru.add(w.buffer.arena.allocator(), Channel.growth.bit(), Brick.index(centre[0] - o[0], centre[1] - o[1], centre[2] - o[2]), 1.0);
    try w.apply();
    var d = operators.Diffusion{ .bit = Channel.growth.bit(), .rate = 0.1 };
    try w.addOperator(operators.operatorOf(operators.Diffusion, &d));
    // The corner sample is shared by the neighbours the frontier
    // materialised, so a plain plane sum counts it four times: count
    // each lattice point once, before and after.
    const m0 = massOnce(&w, Channel.growth.bit());
    try testing.expectApproxEqRel(@as(f64, 1.0), m0, 1e-6);
    const steps: u32 = 40;
    try run(&w, steps, null);
    try guards.check(w.published());
    // Mass: the frontier materialises bricks as the mass reaches faces;
    // shared face samples count once per holder, so compare a sum that
    // counts each lattice point once.
    const m1 = massOnce(&w, Channel.growth.bit());
    try testing.expectApproxEqRel(m0, m1, 1e-3);
    // Variance about the centre along x: 2·D·t with D = 0.1, t = 40 s → 8.
    const var_x = varianceOnce(&w, Channel.growth.bit(), 0, @floatFromInt(centre[0]));
    std.debug.print("\ndiffusion: mass {d:.5} → {d:.5}, var_x {d:.3} (closed form 8.000), bricks {d}, clamped {d}\n", .{ m0, m1, var_x, w.published().brick_count, w.total.diffusion_clamped });
    try testing.expectApproxEqRel(@as(f64, 8.0), var_x, 0.03);
    try testing.expect(w.published().brick_count > 1); // it spread across seams
}

test "diffusion mutation: a rate above the stability bound is clamped and counted, never silent" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    try seedbed.blob(&w, Channel.growth.bit(), .{ 0, 0, 0 }, 3, 1.0, 0);
    try w.apply();
    var d = operators.Diffusion{ .bit = Channel.growth.bit(), .rate = 5.0 };
    try w.addOperator(operators.operatorOf(operators.Diffusion, &d));
    try run(&w, 3, null);
    try testing.expect(w.total.diffusion_clamped > 0);
    try testing.expect(seedbed.total(&w, Channel.growth.bit()) > 0);
}

test "decay: v(t) = v₀·exp(−t/τ) exactly, whatever the step" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    try seedbed.blob(&w, Channel.temperature.bit(), .{ 0, 0, 0 }, 5, 1.0, 0);
    try w.apply();
    var d = operators.Decay{ .bit = Channel.temperature.bit(), .tau = 4.0 };
    try w.addOperator(operators.operatorOf(operators.Decay, &d));
    const p = w.domain.toLattice(.{ 0, 0, 0 });
    const v0 = w.published().sample(Channel.temperature.bit(), p);
    try w.step(now(0), null);
    try w.step(.{ .frame = 1, .time_ns = 3 * std.time.ns_per_s }, null);
    try w.step(.{ .frame = 2, .time_ns = 10 * std.time.ns_per_s }, null);
    const v = w.published().sample(Channel.temperature.bit(), p);
    try testing.expectApproxEqRel(v0 * @exp(-10.0 / 4.0), v, 1e-5);
    try guards.check(w.published());
}

test "advection: a blob's centroid translates by u·t" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    try seedbed.blob(&w, Channel.growth.bit(), .{ 0, 0, 0 }, 5, 1.0, 0);
    try w.apply();
    var a = operators.Advection{ .bit = Channel.growth.bit(), .velocity = .{ 0.5, 0, 0 } };
    try w.addOperator(operators.operatorOf(operators.Advection, &a));
    const c0 = seedbed.centroid(&w, Channel.growth.bit());
    try run(&w, 20, null);
    const c1 = seedbed.centroid(&w, Channel.growth.bit());
    std.debug.print("\nadvection: centroid x {d:.3} → {d:.3} (closed form +10.000), mass {d:.3} → {d:.3}\n", .{ c0.c[0], c1.c[0], c0.mass, c1.mass });
    try testing.expectApproxEqAbs(c0.c[0] + 10.0, c1.c[0], 0.15);
    try testing.expectApproxEqAbs(c0.c[1], c1.c[1], 0.05);
    try guards.check(w.published());
}

test "time: fed time going backwards is refused, never clamped; the first tick is the epoch" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    try w.step(.{ .frame = 5, .time_ns = 50 }, null);
    try testing.expectError(loam.world.Error.TimeRegression, w.step(.{ .frame = 6, .time_ns = 40 }, null));
    try testing.expectError(loam.world.Error.TimeRegression, w.step(.{ .frame = 4, .time_ns = 60 }, null));
    try w.step(.{ .frame = 6, .time_ns = 50 }, null); // equal is fine
}

test "G1: (seed, initial fields, operators) → byte-identical snapshot, serial and over the job system" {
    const gpa = testing.allocator;
    // The serial run on a thread of its own while the JobSystem run —
    // which must stay on the thread that owns the system — goes here.
    var a: GrownWorld = undefined;
    var a_err: ?anyerror = null;
    const th = try std.Thread.spawn(.{}, struct {
        fn f(g: *GrownWorld, alloc: std.mem.Allocator, err: *?anyerror) void {
            g.growWounded(alloc, 7, 40, null) catch |e| {
                err.* = e;
            };
        }
    }.f, .{ &a, gpa, &a_err });
    var js = try jobs.JobSystem.init(gpa, 4);
    defer js.deinit();
    var b: GrownWorld = undefined;
    try b.growWounded(gpa, 7, 40, js);
    defer b.deinit();
    th.join();
    if (a_err) |e| return e;
    defer a.deinit();
    try testing.expect(a.published().fronts.len > 3); // the wound spawned repair fronts: the order axis is live
    const ha = a.published().contentHash();
    const hb = b.published().contentHash();
    try testing.expectEqualSlices(u8, &ha, &hb);
    const da = try loam.dump.write(gpa, &a.world);
    defer gpa.free(da);
    const db = try loam.dump.write(gpa, &b.world);
    defer gpa.free(db);
    try testing.expectEqualSlices(u8, da, db);
    std.debug.print("\nG1: {s} ({d} bricks, {d} fronts)\n", .{ loam.dump.hex(ha), a.published().brick_count, a.published().fronts.len });
    // The frozen reference: what this build must reproduce, not merely agree with itself about.
    try testing.expectEqualStrings(thresholds.G1_REFERENCE, &loam.dump.hex(ha));
}

test "G1 mutation: a perturbed seed is a different snapshot" {
    const gpa = testing.allocator;
    var a: GrownWorld = undefined;
    try a.growWounded(gpa, 7, 40, null);
    defer a.deinit();
    var b: GrownWorld = undefined;
    try b.growWounded(gpa, 7 ^ 1, 40, null);
    defer b.deinit();
    const ha = a.published().contentHash();
    const hb = b.published().contentHash();
    try testing.expect(!std.mem.eql(u8, &ha, &hb));
}

/// The sapling scene, run `steps` steps, built IN PLACE: the world holds
/// pointers into the scene's operators, so a GrownWorld must never move.
/// (Returned by value once; the pointers dangled and the gate leaked.)
const GrownWorld = struct {
    world: World,
    scene: seedbed.Scene,

    fn grow(self: *GrownWorld, gpa: std.mem.Allocator, seed: u64, steps: u32, js: ?*jobs.JobSystem) !void {
        self.world = try World.init(gpa, .{ .seed = seed });
        self.scene = .{};
        errdefer self.world.deinit();
        try self.scene.build(&self.world, .sapling);
        try run(&self.world, steps, js);
    }

    /// The sapling wounded at step 20 and run on: healing spawns then
    /// come from REGION entries, whose order is the commit's to fix. A
    /// hand mutation reversing the commit order survived the plain
    /// sapling; this fixture is what makes G1 watch that axis.
    fn growWounded(self: *GrownWorld, gpa: std.mem.Allocator, seed: u64, steps: u32, js: ?*jobs.JobSystem) !void {
        self.world = try World.init(gpa, .{ .seed = seed });
        self.world.jobs = js; // every parallel phase, scene build included
        self.scene = .{};
        errdefer self.world.deinit();
        try self.scene.build(&self.world, .sapling);
        var i: u64 = 0;
        while (i <= steps) : (i += 1) {
            if (i == 20) {
                try seedbed.damage(&self.world, .{ -10, 8, -10 }, .{ 10, 16, 10 });
                try self.world.apply();
            }
            try self.world.step(now(i), js);
        }
    }

    fn deinit(self: *GrownWorld) void {
        self.world.deinit();
    }
    fn published(self: *const GrownWorld) *const loam.Snapshot {
        return self.world.published();
    }
};

/// Sum over lattice points counted once: each point is credited to the
/// lowest-key holder.
fn massOnce(w: *const World, bit: u6) f64 {
    var acc = OnceAcc{ .snap = w.published(), .bit = bit };
    w.published().forEachBrick(&acc, OnceAcc.visit);
    return acc.sum;
}

fn varianceOnce(w: *const World, bit: u6, axis: u2, centre: f64) f64 {
    var acc = OnceAcc{ .snap = w.published(), .bit = bit, .axis = axis, .centre = centre };
    w.published().forEachBrick(&acc, OnceAcc.visit);
    return acc.m2 / acc.sum;
}

const OnceAcc = struct {
    snap: *const loam.Snapshot,
    bit: u6,
    axis: u2 = 0,
    centre: f64 = 0,
    sum: f64 = 0,
    m2: f64 = 0,

    fn visit(self: *OnceAcc, b: *const Brick) void {
        const pl = b.plane(self.bit) orelse return;
        var holders: [8]*const Brick = undefined;
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const v: f64 = pl[Brick.index(i, j, k)];
                    const p = b.pointAt(i, j, k);
                    if (Brick.isBoundary(i, j, k)) {
                        const n = self.snap.findAll(.{ p[0], p[1], p[2] }, &holders);
                        var lowest = b.key.raw();
                        for (holders[0..n]) |h| lowest = @min(lowest, h.key.raw());
                        if (lowest != b.key.raw()) continue;
                    }
                    self.sum += v;
                    const d = @as(f64, @floatFromInt(p[self.axis])) - self.centre;
                    self.m2 += v * d * d;
                }
            }
        }
    }
};

// ── P1.4: fronts ─────────────────────────────────────────────────────────

/// The G2 run: the sapling for G2_STEPS, sampling the young-tissue
/// component count at every checkpoint, since tips are live in the middle
/// of the run and dormant by its end. Tissue is the carrier's inside.
const G2Run = struct { max_young: usize = 0, tissue_half: u64 = 0, tissue_full: u64 = 0, branches: usize = 0 };

fn g2Run(gpa: std.mem.Allocator, scene_in: seedbed.Scene) !G2Run {
    var w = try World.init(gpa, .{ .seed = 7 });
    defer w.deinit();
    var scene = scene_in;
    try scene.build(&w, .sapling);
    var r = G2Run{};
    var i: u64 = 0;
    while (i <= thresholds.G2_STEPS) : (i += 1) {
        try w.step(now(i), null);
        if (i % thresholds.G2_CHECK_EVERY == 0) {
            r.max_young = @max(r.max_young, try seedbed.youngComponents(&w, gpa, 0.0, thresholds.G2_YOUNG_WINDOW_S, thresholds.G2_MIN_COMPONENT_POINTS));
        }
        if (i == thresholds.G2_STEPS / 2) r.tissue_half = seedbed.insideCount(&w);
    }
    r.tissue_full = seedbed.insideCount(&w);
    r.branches = w.published().fronts.len - 1;
    try guards.check(w.published());
    return r;
}

test "G2: a seeded front produces persistent, branching, deposited structure with no mesh" {
    const gpa = testing.allocator;
    const r = try g2Run(gpa, .{});
    std.debug.print("\nG2: tissue {d} samples at N/2 → {d} at N, {d} branches, {d} young-tissue components at peak\n", .{ r.tissue_half, r.tissue_full, r.branches, r.max_young });
    try testing.expect(r.tissue_full > 0 and r.tissue_full >= r.tissue_half); // persistent: no reset
    try testing.expect(r.branches >= thresholds.G2_MIN_BRANCHES); // the mechanism fired
    try testing.expect(r.max_young >= thresholds.G2_MIN_YOUNG_COMPONENTS); // and the FIELD shows it
}

test "G2 mutation: branching off → one component of young material while material still grows" {
    const gpa = testing.allocator;
    const r = try g2Run(gpa, .{ .max_generation = 0 });
    std.debug.print("\nG2 mutation: tissue {d}, {d} branches, {d} young-tissue components at peak\n", .{ r.tissue_full, r.branches, r.max_young });
    try testing.expect(r.tissue_full > 0);
    try testing.expectEqual(@as(usize, 0), r.branches);
    try testing.expectEqual(@as(usize, 1), r.max_young);
}

test "G2 mutation: zero deposit → no tissue" {
    const gpa = testing.allocator;
    const r = try g2Run(gpa, .{ .deposit = 0 });
    try testing.expectEqual(@as(u64, 0), r.tissue_full);
    try testing.expectEqual(@as(usize, 0), r.max_young);
}

fn printEnsemble(label: []const u8, e: *const seedbed.TropismEnsemble) void {
    std.debug.print("\n{s}: n = {d}, D = {d}: r̄ {d:.2}, sd {d:.2}, lower95 {d:.2}, σ₀ {d:.2} (floor {d:.2}), all positive {}\n", .{ label, e.samples.len, thresholds.G3_DISPLACEMENT, e.mean, e.sd, e.lower95, e.sigma0, thresholds.G3_EFFECT_K * e.sigma0, e.all_positive });
    for (e.samples) |smp| std.debug.print("  seed {d}: û ({d:.2}, {d:.2}) r {d:.2} null {d:.2}\n", .{ smp.seed, smp.u[0], smp.u[2], smp.r, smp.null_disp });
}

test "G3: matched ± stimulus pairs across seeded directions produce a positive directional response" {
    const gpa = testing.allocator;
    var e = try seedbed.tropismEnsemble(gpa, thresholds.G3_SEEDS, thresholds.G3_DISPLACEMENT, seedbed.TROPISM_COEFF, thresholds.G3_STEPS, true);
    defer e.deinit(gpa);
    printEnsemble("G3", &e);
    try testing.expect(e.sigma0 > 0); // the null wandered: the effect-size unit is real
    // 1. The paired directional response is positive: 95% lower bound above zero.
    try testing.expect(e.lower95 > 0);
    // 2. Every pair has the right sign: P = 2⁻ⁿ under a directionless null.
    try testing.expect(e.all_positive);
    // 3. And it is large against natural wander: the effect-size floor, kept separate.
    try testing.expect(e.mean > thresholds.G3_EFFECT_K * e.sigma0);
}

test "G3 mutation: coefficient zero → every pair bit-identical, response exactly zero" {
    const gpa = testing.allocator;
    var e = try seedbed.tropismEnsemble(gpa, 3, thresholds.G3_DISPLACEMENT, 0, thresholds.G3_STEPS, false);
    defer e.deinit(gpa);
    for (e.samples) |smp| try testing.expectEqual(@as(f64, 0), smp.r);
    try testing.expect(!e.all_positive);
}

test "G3 mutation: gradient term reversed → every pair has the wrong sign" {
    const gpa = testing.allocator;
    var e = try seedbed.tropismEnsemble(gpa, 3, thresholds.G3_DISPLACEMENT, -seedbed.TROPISM_COEFF, thresholds.G3_STEPS, false);
    defer e.deinit(gpa);
    printEnsemble("G3 reversed", &e);
    for (e.samples) |smp| try testing.expect(smp.r < 0);
    try testing.expect(e.lower95 < 0 or e.mean < 0);
}

const DamageBox = struct { lo: [3]f64 = .{ -10, 18, -10 }, hi: [3]f64 = .{ 10, 30, 10 } };

/// Grow to dormancy, wound, run K more steps. Returns the snapshot
/// before the wound (retained; caller releases) and the world.
fn woundRun(gpa: std.mem.Allocator, g: *GrownWorld, heal: bool) !*loam.Snapshot {
    g.world = try World.init(gpa, .{ .seed = 7 });
    g.scene = .{ .heal = heal };
    errdefer g.world.deinit();
    try g.scene.build(&g.world, .sapling);
    // Grow until nothing is active: dormant tissue, the G4 precondition.
    var i: u64 = 0;
    while (i <= 200) : (i += 1) {
        try g.world.step(now(i), null);
        if (i > 20 and g.published().active.len == 0) break;
    }
    try testing.expectEqual(@as(usize, 0), g.published().active.len);
    // The season ends: whatever potential the tree left is gone, so the
    // only potential anywhere after the wound is what healing restores.
    try seedbed.clearChannel(&g.world, Channel.growth.bit());
    try g.world.apply();
    i += 1;
    try g.world.step(now(i), null);
    i += 1;
    try g.world.step(now(i), null);
    try testing.expectEqual(@as(usize, 0), g.published().active.len);
    try testing.expectEqual(@as(f64, 0), seedbed.total(&g.world, Channel.growth.bit()));
    const before = g.world.head;
    before.retain();
    const box = DamageBox{};
    try seedbed.damage(&g.world, box.lo, box.hi);
    try g.world.apply();
    var k: u64 = 0;
    while (k < 40) : (k += 1) {
        i += 1;
        try g.world.step(now(i), null);
    }
    return before;
}

/// Lattice points in the world box whose SAMPLE of the carrier is inside
/// — coefficients, not the reconstruction: the cut leaves every sample
/// in the box at or above zero exactly, while the B-spline smooths the
/// cut's wall across a cell and read 18 points of "tissue" inside the
/// box where the trunk ran along it. What healing regrows is samples.
fn tissueInBox(w: *const World, lo: [3]f64, hi: [3]f64) u64 {
    var n: u64 = 0;
    const snap = w.published();
    var y = lo[1];
    while (y <= hi[1]) : (y += 1) {
        var z = lo[2];
        while (z <= hi[2]) : (z += 1) {
            var x = lo[0];
            while (x <= hi[0]) : (x += 1) {
                const q = w.domain.toLattice(.{ x, y, z });
                const p = [3]i64{ tree.floorI(q[0]), tree.floorI(q[1]), tree.floorI(q[2]) };
                const b = snap.findLeaf(p) orelse continue;
                const l = b.localOf(p) orelse continue;
                if (b.get(Channel.surface.bit(), l[0], l[1], l[2]) < 0) n += 1;
            }
        }
    }
    return n;
}

test "G4: removing material re-activates evolution locally only" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    const before = try woundRun(gpa, &g, true);
    defer before.release();
    defer g.deinit();
    const box = DamageBox{};
    const regrown = tissueInBox(&g.world, box.lo, box.hi);
    // Every brick outside the dilated box is the SAME brick as before the
    // wound — identity, not merely equality — and the touched ones lie
    // inside it.
    const lo_l = g.world.domain.toLattice(box.lo);
    const hi_l = g.world.domain.toLattice(box.hi);
    const after = g.published();
    const bs = try after.bricks(gpa);
    defer gpa.free(bs);
    var touched: usize = 0;
    var outside: usize = 0;
    for (bs) |b| {
        const same = before.brickAt(b.key) == b;
        if (same) continue;
        touched += 1;
        const o = b.origin();
        const side: f64 = @floatFromInt(b.key.side());
        const k: f64 = @as(f64, @floatFromInt(thresholds.G4_DILATE_BRICKS)) * side;
        var inside = true;
        inline for (0..3) |a| {
            const bl: f64 = @floatFromInt(o[a]);
            if (bl + side < lo_l[a] - k or bl > hi_l[a] + k) inside = false;
        }
        if (!inside) {
            outside += 1;
            if (outside <= 5) std.debug.print("\n  outside: brick at ({d}, {d}, {d}) vs box lattice [{d:.0}..{d:.0}, {d:.0}..{d:.0}, {d:.0}..{d:.0}]", .{ o[0], o[1], o[2], lo_l[0], hi_l[0], lo_l[1], hi_l[1], lo_l[2], hi_l[2] });
        }
    }
    std.debug.print("\nG4: {d} bricks touched by the repair, {d} outside dilate(box, {d}); tissue regrown in box {d} points; {d} fronts\n", .{ touched, outside, thresholds.G4_DILATE_BRICKS, regrown, after.fronts.len });
    try testing.expect(regrown > 0);
    try testing.expect(touched > 0);
    try testing.expectEqual(@as(usize, 0), outside);
    try guards.check(after);
}

test "G4 mutation: remove the healing operator → no reactivation" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    const before = try woundRun(gpa, &g, false);
    defer before.release();
    defer g.deinit();
    const box = DamageBox{};
    try testing.expectEqual(@as(u64, 0), tissueInBox(&g.world, box.lo, box.hi));
}

// ── P1.5: the active set ─────────────────────────────────────────────────

test "G5: dormant tissue costs nothing — evaluations track the active set, not the brick count" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 0, null);
    defer g.deinit();
    const n_ops = g.world.operators.items.len;
    var sum_active: u64 = 0;
    var i: u64 = 1;
    var timer = try std.time.Timer.start();
    while (i <= 80) : (i += 1) {
        try g.world.step(now(i), null);
        sum_active += g.world.stats.active_in;
        try testing.expectEqual(g.world.stats.active_in * n_ops, g.world.stats.region_evals);
    }
    const ms = @as(f64, @floatFromInt(timer.read())) / 1e6;
    const bricks = g.published().brick_count;
    const worst = @as(u64, bricks) * 80 * n_ops;
    std.debug.print("\nG5: {d} evals over 80 steps for {d} bricks (all-regions would be {d}); {d:.1} ms total, {s}, serial\n", .{ g.world.total.region_evals, bricks, worst, ms, @tagName(builtin.mode) });
    try testing.expectEqual(sum_active * n_ops, g.world.total.region_evals);
    try testing.expect(g.world.total.region_evals * 20 < worst);
}

test "G5 mutation: iterate every brick → evaluations scale with the brick count" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 7, .policy = .{ .active_only = false } });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .sapling);
    const n_ops = w.operators.items.len;
    try w.step(now(0), null);
    try w.step(now(1), null);
    try testing.expectEqual(@as(u64, w.published().brick_count) * n_ops, w.stats.region_evals);
}

// ── P2.1a: attention ─────────────────────────────────────────────────────

/// The budget G14 grows under: a fraction of the step's active set, at
/// least one brick, set before every step from the published count.
fn budgetFor(w: *const World, fraction: f32) u32 {
    const n: f32 = @floatFromInt(w.published().active.len);
    return @max(1, @as(u32, @intFromFloat(@ceil(n * fraction))));
}

const HeadAndTail = struct { head: []loam.lattice.Key, carried: usize };

fn hostsFront(snap: *const loam.Snapshot, k: loam.lattice.Key) bool {
    for (snap.fronts) |f| if (f.alive and f.brick.eql(k)) return true;
    return false;
}

/// The residual's score from the snapshot alone (R17): pending × (1 + lag/τ).
fn scoreOf(snap: *const loam.Snapshot, k: loam.lattice.Key, now_ns: u64) f64 {
    const pending: f64 = if (snap.brickAt(k)) |b| b.summary.attention else 0;
    const since = snap.sinceOf(k) orelse now_ns;
    const lag_s: f64 = @as(f64, @floatFromInt(now_ns -| since)) / 1e9;
    return pending * (1 + lag_s / thresholds.LAG_TAU_S);
}

/// What a step must evaluate, from the snapshot's bookkeeping alone: the
/// live fronts' bricks in key order, never cut, then the rest by the
/// residual's score at `now_ns` descending, ties by key, cut at
/// `budget` — the active set itself when it fits or there is no budget
/// — and how many of the tail carry (attentive above the floor, or
/// hosting a front).
fn attentionHead(gpa: std.mem.Allocator, snap: *const loam.Snapshot, now_ns: u64, budget: ?usize) !HeadAndTail {
    const K = loam.lattice.Key;
    const b = budget orelse snap.active.len;
    const Scored = struct { key: K, a: f64, score: f64, tier: u8 };
    const scored = try gpa.alloc(Scored, snap.active.len);
    defer gpa.free(scored);
    for (snap.active, 0..) |k, i| {
        const a: f64 = if (snap.brickAt(k)) |br| br.summary.attentionAt(now_ns, thresholds.ATTENTION_TAU_S) else 0;
        scored[i] = .{ .key = k, .a = a, .score = scoreOf(snap, k, now_ns), .tier = if (hostsFront(snap, k)) 0 else 1 };
    }
    std.mem.sort(Scored, scored, {}, struct {
        fn lt(_: void, x: Scored, y: Scored) bool {
            if (x.tier != y.tier) return x.tier < y.tier;
            if (x.tier == 1 and x.score != y.score) return x.score > y.score;
            return x.key.raw() < y.key.raw();
        }
    }.lt);
    // The fronts' tier is never cut: the head is at least that long.
    var n0: usize = 0;
    for (scored) |s| if (s.tier == 0) {
        n0 += 1;
    };
    const take = @max(b, n0);
    const out = try gpa.alloc(K, take);
    for (scored[0..take], 0..) |s, i| out[i] = s.key;
    var carried: usize = 0;
    for (scored[take..]) |s| {
        if (s.a > thresholds.EPSILON or hostsFront(snap, s.key)) carried += 1;
    }
    return .{ .head = out, .carried = carried };
}

fn expectSameKeys(expected: []const loam.lattice.Key, actual: []const loam.lattice.Key) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |e, a| try testing.expectEqual(e.raw(), a.raw());
}

test "G14 (a): what a step evaluates is the attention-ordered head of the active set, recomputable from the summaries alone, and evaluations follow it" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 0, null);
    defer g.deinit();
    const n_ops = g.world.operators.items.len;
    var cut_steps: u64 = 0;
    var i: u64 = 1;
    while (i <= 80) : (i += 1) {
        // Unbudgeted for forty steps — the head is the active set, G5's
        // identity — then under the fraction, the head its attention order.
        const budget: ?u32 = if (i > 40) budgetFor(&g.world, thresholds.G14_BUDGET_FRACTION) else null;
        g.world.policy.budget = budget;
        const before = g.world.head;
        before.retain();
        defer before.release();
        try g.world.step(now(i), null);
        const ht = try attentionHead(gpa, before, now(i).time_ns, if (budget) |b| @as(usize, b) else null);
        defer gpa.free(ht.head);
        try expectSameKeys(ht.head, g.world.evaluated);
        try testing.expectEqual(g.world.evaluated.len * n_ops, g.world.stats.region_evals);
        try testing.expectEqual(ht.carried, g.world.stats.carried);
        try testing.expectEqual(before.active.len - g.world.evaluated.len - ht.carried, g.world.stats.faded);
        // The carried bricks are the next snapshot's backlog — owed since
        // before its commit — and the budget the step ran under is on it.
        try testing.expectEqual(ht.carried, g.published().backlog());
        try testing.expectEqual(budget, g.published().budget);
        // No live front's step is ever skipped under a budget (struck):
        // what the fronts exceed it by is an overrun, reported.
        try testing.expectEqual(@as(u64, 0), g.world.stats.fronts_skipped);
        if (before.active.len > g.world.evaluated.len) cut_steps += 1;
    }
    std.debug.print("\nG14 (a): 80 steps, the evaluated set recomputed from the summaries at every one; {d} steps cut by the budget, {d} bricks carried, {d} faded under the floor, {d} front-steps skipped, {d} overrun, {d} evals\n", .{ cut_steps, g.world.total.carried, g.world.total.faded, g.world.total.fronts_skipped, g.world.total.overrun, g.world.total.region_evals });
    try testing.expect(cut_steps > 0);
    // Ten steps at a budget of ONE brick: every front still moves, the
    // overrun says by how much, and the backlog — the standing number —
    // grows, with the consecutive-overload count as D5's signal.
    var overrun: u64 = 0;
    var live: u64 = 0;
    while (i <= 90) : (i += 1) {
        g.world.policy.budget = 1;
        try g.world.step(now(i), null);
        try testing.expectEqual(@as(u64, 0), g.world.stats.fronts_skipped);
        overrun += g.world.stats.overrun;
        for (g.published().fronts) |f| if (f.alive and !f.dormant) {
            live += 1;
        };
    }
    std.debug.print("G14 (a): ten steps at a budget of one brick: {d} live front-steps, none skipped, overrun {d} bricks; backlog {d} at the end, {d} consecutive steps over budget\n", .{ live, overrun, g.published().backlog(), g.world.overload_steps });
    try testing.expect(overrun > 0);
    try testing.expect(g.world.overload_steps >= 9);
    try guards.check(g.published());
}

test "G14 (a) mutation: attention ignored (every brick iterated) → evaluations scale with the brick count and the head is not the active set's" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    // Forty steps in: the active set is a few dozen bricks of thousands.
    // (Right after the scene build every brick is active — the blobs
    // touched them all — and the mutation is invisible there.)
    try g.grow(gpa, 7, 40, null);
    defer g.deinit();
    const n_ops = g.world.operators.items.len;
    g.world.policy.active_only = false;
    const before = g.world.head;
    before.retain();
    defer before.release();
    try g.world.step(now(41), null);
    const ht = try attentionHead(gpa, before, now(41).time_ns, null);
    defer gpa.free(ht.head);
    try testing.expect(ht.head.len * 10 < g.world.evaluated.len);
    try testing.expectEqual(@as(u64, g.world.published().brick_count) * n_ops, g.world.stats.region_evals);
}

test "G14 (b): a walk rejecting on the summaries' attention bound finds exactly the bricks above the floor, at the step and for a reader later" {
    const gpa = testing.allocator;
    const K = loam.lattice.Key;
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 80, null);
    defer g.deinit();
    const snap = g.published();
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    const tau: f64 = thresholds.ATTENTION_TAU_S;
    const floor: f64 = thresholds.EPSILON;
    var last_found: usize = 0;
    var last_examined: usize = 0;
    // Attention is at most about 1 now (a change of a channel's whole
    // range), so nothing stays attentive past τ·ln(1/floor) = 41 s.
    for ([_]u64{ 0, 5, 20, 35 }) |later_s| {
        const t = snap.time_ns + later_s * std.time.ns_per_s;
        var found = std.ArrayListUnmanaged(K){};
        defer found.deinit(gpa);
        var examined: usize = 0;
        try snap.attentive(t, floor, tau, true, gpa, &found, &examined);
        // Brute force over every brick's own bookkeeping — and the window
        // the claim states, τ·ln(a₀/floor), which is the same test.
        var expected = std.ArrayListUnmanaged(K){};
        defer expected.deinit(gpa);
        for (bs) |b| {
            const s = b.summary;
            const a = s.attentionAt(t, tau);
            const above = a > floor;
            if (@abs(a - floor) > 1e-6 * floor) {
                const elapsed: f64 = @as(f64, @floatFromInt(t - s.changed_ns)) / 1e9;
                const in_window = s.attention > 0 and elapsed < tau * @log(@as(f64, s.attention) / floor);
                try testing.expectEqual(in_window, above);
            }
            if (above) try expected.append(gpa, b.key);
        }
        try expectSameKeys(expected.items, found.items);
        std.debug.print("\nG14 (b): {d} s after step 80, {d} of {d} bricks attentive above {e:.0} at τ = {d} s; the walk examined {d} leaves ({d:.2} per attentive brick)", .{ later_s, found.items.len, bs.len, floor, tau, examined, @as(f64, @floatFromInt(examined)) / @as(f64, @floatFromInt(@max(found.items.len, 1))) });
        last_found = found.items.len;
        last_examined = examined;
    }
    std.debug.print("\n", .{});
    // Rejection from the summaries: far fewer leaves examined than exist.
    try testing.expect(last_examined < bs.len / 4);
    // The mutation, as an instrument: without the summaries the walk
    // examines every leaf to find the same set.
    var found = std.ArrayListUnmanaged(K){};
    defer found.deinit(gpa);
    var examined: usize = 0;
    try snap.attentive(snap.time_ns + 35 * std.time.ns_per_s, floor, tau, false, gpa, &found, &examined);
    try testing.expectEqual(bs.len, examined);
    try testing.expectEqual(last_found, found.items.len);
}

// ── G14 (e): the residual ────────────────────────────────────────────────

const Residual = struct { cold_max: u64 = 0, cold_min: u64 = std.math.maxInt(u64), cold_served: u64 = 0, hot_served: u64 = 0, n_cold: usize = 0, slots: usize = 0, predicted: u32 = 0 };

fn isHot(k: loam.lattice.Key) bool {
    return k.origin()[0] < lattice.CELLS / 2;
}

/// A 4×4×4-brick region of uniform change: `amount` added to every own
/// sample of every brick, queued for the next `apply`.
fn authorRegion(w: *World, bit: u6, x0: u32, mid: u32, amount: f32) !void {
    const alloc = w.buffer.arena.allocator();
    const side: u32 = brick.CELLS;
    var bx: u32 = 0;
    while (bx < 4) : (bx += 1) {
        var by: u32 = 0;
        while (by < 4) : (by += 1) {
            var bz: u32 = 0;
            while (bz < 4) : (bz += 1) {
                const ru = try w.author(lattice.Key.ofBrick(0, .{ x0 + bx * side, mid - 2 * side + by * side, mid - 2 * side + bz * side }));
                var k: u32 = 0;
                while (k < brick.N) : (k += 1) {
                    var j: u32 = 0;
                    while (j < brick.N) : (j += 1) {
                        var ii: u32 = 0;
                        while (ii < brick.N) : (ii += 1) try ru.add(alloc, bit, Brick.index(ii, j, k), amount);
                    }
                }
            }
        }
    }
}

/// Two regions of UNIFORM pending change, authored before every step —
/// the hot one at G14E_RATIO times the cold one's delta, on a channel
/// with no range so a change scores as it is — under a budget the hot
/// region's active bricks alone fill; no operator, no front. (A
/// diffusing blob gave each region a profile, and cold centre bricks
/// outranked hot edge bricks on pending alone, which is the score
/// working, not the claim.) The lag, in steps, at which every cold
/// brick is served.
fn residualRun(gpa: std.mem.Allocator, order: loam.world.BudgetOrder, steps: u64) !Residual {
    var w = try World.init(gpa, .{ .seed = 3 });
    defer w.deinit();
    w.policy.budget_order = order;
    const bit = Channel.light.bit();
    const mid: u32 = lattice.CELLS / 2;
    const hot_delta: f32 = 0.01;
    var r = Residual{};
    var i: u64 = 0;
    while (i <= steps) : (i += 1) {
        try authorRegion(&w, bit, mid - 6 * brick.CELLS, mid, hot_delta);
        try authorRegion(&w, bit, mid + 2 * brick.CELLS, mid, hot_delta / thresholds.G14E_RATIO);
        try w.apply();
        const snap = w.head;
        snap.retain();
        defer snap.release();
        var hot: u32 = 0;
        for (snap.active) |k| if (isHot(k)) {
            hot += 1;
        };
        // From step 2 the hot region's active count IS the budget.
        w.policy.budget = if (i >= 2) @max(1, hot) else null;
        if (i == 2) {
            r.n_cold = snap.active.len - hot;
            r.slots = hot;
            r.predicted = thresholds.g14ePredictedSteps(1.0, thresholds.G14E_RATIO, r.n_cold, r.slots);
        }
        try w.step(now(i), null);
        if (i < 2) continue;
        for (w.evaluated) |k| {
            const since = snap.sinceOf(k) orelse continue;
            const lag_steps = (now(i).time_ns - since) / std.time.ns_per_s;
            if (isHot(k)) {
                r.hot_served += 1;
            } else {
                r.cold_served += 1;
                r.cold_max = @max(r.cold_max, lag_steps);
                r.cold_min = @min(r.cold_min, lag_steps);
            }
        }
    }
    try guards.check(w.published());
    return r;
}

test "G14 (e) the residual: under a budget the hot region alone fills, every cold brick is served within the steps predicted from τ, and the cold region is deferred at all" {
    const gpa = testing.allocator;
    const r = try residualRun(gpa, .attention, 60);
    std.debug.print("\nG14 (e): {d} cold bricks against {d} hot slots at {d:.0}×; cold served {d} times at lags {d}–{d} steps, predicted ≤ {d} (τ = {d} s); hot served {d}\n", .{ r.n_cold, r.slots, thresholds.G14E_RATIO, r.cold_served, r.cold_min, r.cold_max, r.predicted, thresholds.LAG_TAU_S, r.hot_served });
    try testing.expect(r.cold_served > 0);
    try testing.expect(r.cold_min > 1);
    try testing.expect(r.cold_max <= r.predicted);
}

test "G14 (e) mutation: the lag term zeroed → the cold region is never served" {
    const gpa = testing.allocator;
    const r = try residualRun(gpa, .no_lag, 60);
    std.debug.print("\nG14 (e) mutation, no lag: cold served {d} times in 60 steps; hot {d}\n", .{ r.cold_served, r.hot_served });
    try testing.expectEqual(@as(u64, 0), r.cold_served);
}

const BudgetedRun = struct { inside: u64, carried: u64, faded: u64, skipped: u64, evals: u64, front_steps: u64 };

/// The sapling, G2's 160 steps, under a budget of `fraction` of each
/// step's active set — or none — the head chosen by `order`.
fn budgetedRun(gpa: std.mem.Allocator, fraction: ?f32, order: loam.world.BudgetOrder) !BudgetedRun {
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 0, null);
    defer g.deinit();
    g.world.policy.budget_order = order;
    var i: u64 = 1;
    while (i <= thresholds.G2_STEPS) : (i += 1) {
        if (fraction) |f| g.world.policy.budget = budgetFor(&g.world, f);
        try g.world.step(now(i), null);
    }
    try guards.check(g.published());
    return .{ .inside = seedbed.insideCount(&g.world), .carried = g.world.total.carried, .faded = g.world.total.faded, .skipped = g.world.total.fronts_skipped, .evals = g.world.total.region_evals, .front_steps = g.world.total.front_steps };
}

fn deviation(full: u64, under: u64) f64 {
    const a: f64 = @floatFromInt(full);
    const b: f64 = @floatFromInt(under);
    return @abs(b - a) / a;
}

test "G14 (c) invariance: the sapling grown under a budget of half its active set, fronts then backlog then attention, ends within the floor of the unbudgeted run's tissue" {
    const gpa = testing.allocator;
    const full = try budgetedRun(gpa, null, .attention);
    const half = try budgetedRun(gpa, thresholds.G14_BUDGET_FRACTION, .attention);
    const dev = deviation(full.inside, half.inside);
    std.debug.print("\nG14 (c) invariance: inside {d} unbudgeted vs {d} at {d:.0}% of the active set (deviation {d:.2}%; {d} carried, {d} faded, {d} front-steps skipped; evals {d} vs {d})\n", .{ full.inside, half.inside, thresholds.G14_BUDGET_FRACTION * 100, dev * 100, half.carried, half.faded, half.skipped, full.evals, half.evals });
    try testing.expect(half.carried > 0);
    try testing.expectEqual(@as(u64, 0), half.skipped);
    try testing.expect(dev <= thresholds.G14_MAX_DEVIATION);
}

test "G14 (c) mutation, the ruling's: one obligation queue, fronts and backlog together in key order → every front moves every other step and the tissue deviates past the floor" {
    const gpa = testing.allocator;
    const full = try budgetedRun(gpa, null, .attention);
    const queued = try budgetedRun(gpa, thresholds.G14_BUDGET_FRACTION, .queue);
    const dev = deviation(full.inside, queued.inside);
    std.debug.print("\nG14 (c) mutation, one queue: inside {d} unbudgeted vs {d} (deviation {d:.2}%; {d} front-steps skipped)\n", .{ full.inside, queued.inside, dev * 100, queued.skipped });
    try testing.expect(queued.skipped > 0);
    try testing.expect(dev > thresholds.G14_MAX_DEVIATION);
}

test "G14 (c) mutation: the head taken in key order → the tips lag and the tissue deviates past the floor" {
    const gpa = testing.allocator;
    const full = try budgetedRun(gpa, null, .attention);
    const keyed = try budgetedRun(gpa, thresholds.G14_BUDGET_FRACTION, .key);
    const dev = deviation(full.inside, keyed.inside);
    std.debug.print("\nG14 (c) mutation: inside {d} unbudgeted vs {d} with the head in key order (deviation {d:.2}%; {d} front-steps skipped)\n", .{ full.inside, keyed.inside, dev * 100, keyed.skipped });
    try testing.expect(dev > thresholds.G14_MAX_DEVIATION);
}

const WoundedUnderBudget = struct { hash: [32]u8, record: []?u32 };

/// The wounded sapling (G1's fixture: seed 7, 40 steps, wound at 20)
/// under a budget of `fraction` of each step's active set, or under a
/// recorded `schedule` replayed. Returns the content hash and the budget
/// every step ran under — the record. Caller frees the record.
fn woundedUnderBudget(gpa: std.mem.Allocator, fraction: ?f32, schedule: ?[]const ?u32, js: ?*jobs.JobSystem) !WoundedUnderBudget {
    var g: GrownWorld = undefined;
    g.world = try World.init(gpa, .{ .seed = 7 });
    g.world.jobs = js;
    g.scene = .{};
    errdefer g.world.deinit();
    try g.scene.build(&g.world, .sapling);
    defer g.deinit();
    const record = try gpa.alloc(?u32, 41);
    errdefer gpa.free(record);
    var i: u64 = 0;
    while (i <= 40) : (i += 1) {
        if (i == 20) {
            try seedbed.damage(&g.world, .{ -10, 8, -10 }, .{ 10, 16, 10 });
            try g.world.apply();
        }
        g.world.policy.budget = if (schedule) |s| s[i] else if (fraction) |f| budgetFor(&g.world, f) else null;
        record[i] = g.world.policy.budget;
        try g.world.step(now(i), js);
        // The snapshot carries the budget it ran under.
        try testing.expectEqual(record[i], g.published().budget);
    }
    return .{ .hash = g.published().contentHash(), .record = record };
}

test "G14 (d) reproducibility: the budget is on the transcript — a run replayed from its recorded budgets publishes the same hash, serial and over the job system; a record with one budget changed does not" {
    const gpa = testing.allocator;
    const a = try woundedUnderBudget(gpa, thresholds.G14_BUDGET_FRACTION, null, null);
    defer gpa.free(a.record);
    const b = try woundedUnderBudget(gpa, null, a.record, null);
    defer gpa.free(b.record);
    try testing.expectEqualSlices(u8, &a.hash, &b.hash);
    var js = try jobs.JobSystem.init(gpa, 4);
    defer js.deinit();
    const c = try woundedUnderBudget(gpa, null, a.record, js);
    defer gpa.free(c.record);
    try testing.expectEqualSlices(u8, &a.hash, &c.hash);
    // The mutation: the record altered where it bites — the three steps
    // after the wound at a budget of one brick, so the wound's bricks wait
    // behind the fronts and healing lands later. (A budget one brick
    // larger at step 25 evaluated one more brick that changed nothing:
    // the world was invariant to it and the final hash agreed — the
    // transcript differed, the state did not, which is the distinction
    // between the two claims.)
    const altered = try gpa.dupe(?u32, a.record);
    defer gpa.free(altered);
    altered[21] = 1;
    altered[22] = 1;
    altered[23] = 1;
    const d = try woundedUnderBudget(gpa, null, altered, null);
    defer gpa.free(d.record);
    try testing.expect(!std.mem.eql(u8, &a.hash, &d.hash));
    // And the unbudgeted run is a third world: the transcript says which.
    const e = try woundedUnderBudget(gpa, null, null, null);
    defer gpa.free(e.record);
    try testing.expect(!std.mem.eql(u8, &a.hash, &e.hash));
    try testing.expectEqualSlices(u8, thresholds.G1_REFERENCE, &loam.dump.hex(e.hash));
    std.debug.print("\nG14 (d) reproducibility: the wounded sapling under the half budget {s}… replayed from its record serial and over 4 threads; steps 21–23 at a budget of 1 instead of {d}, {d}, {d}: {s}…; unbudgeted the frozen reference\n", .{ loam.dump.hex(a.hash)[0..8], a.record[21].?, a.record[22].?, a.record[23].?, loam.dump.hex(d.hash)[0..8] });
}

test "the hash covers the canonical samples, not the halo: a corrupted halo sample leaves the hash where it is and the halo guard fires" {
    // Christian, the step-cost beat: the halo is a copy of the neighbours'
    // own samples, hashed where they are owned; hashing it again is a
    // second truth in the identity. Mutation, by hand: hash the whole
    // 11³ block again → the hash moves under the corruption.
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 20, null);
    defer g.deinit();
    const snap: *loam.Snapshot = @constCast(g.published());
    try guards.check(snap);
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    // A brick with a surface plane whose halo holds a value nearer than
    // far: one the neighbours reach into.
    var victim: ?*Brick = null;
    var idx: usize = 0;
    for (bs) |b| {
        const pl = b.plane(Channel.surface.bit()) orelse continue;
        const i = Brick.bindex(0, 5, 5);
        if (pl[i] < b.band()) {
            victim = @constCast(b);
            idx = i;
            break;
        }
    }
    const v = victim.?;
    const before = v.hash;
    const pl = v.plane(Channel.surface.bit()).?;
    const old = pl[idx];
    pl[idx] = old - 0.5;
    // The hash, recomputed from the corrupted block, is the same hash…
    const scratch = try Brick.clone(gpa, v);
    defer scratch.release(gpa);
    scratch.finalize(gpa);
    try testing.expectEqualSlices(u8, &before, &scratch.hash);
    // …and the halo guard fires.
    try testing.expectError(guards.Violation.HaloStale, guards.check(snap));
    pl[idx] = old;
    try guards.check(snap);
    // A corrupted OWN sample, by contrast, moves the hash.
    const own = Brick.index(4, 4, 4);
    const old_own = pl[own];
    pl[own] = old_own - 0.5;
    const scratch2 = try Brick.clone(gpa, v);
    defer scratch2.release(gpa);
    scratch2.finalize(gpa);
    try testing.expect(!std.mem.eql(u8, &before, &scratch2.hash));
    pl[own] = old_own;
}

// ── P2.1b: the budget in work units — begin / work / cut / finish ────────

test "apply twice: a second apply with nothing new authored applies nothing" {
    // Found building P2.1b: the buffer was reset only by `step`, so a
    // second `apply` re-applied everything queued before the first —
    // 10894 of light became 21788, and the seams scene's first blob was
    // doubled since P1.2. An authoring finish resets the buffer now.
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    try seedbed.blobLattice(&w, Channel.light.bit(), .{ 512, 512, 512 }, 20, 1.0, 0);
    try w.apply();
    const t1 = seedbed.total(&w, Channel.light.bit());
    try w.apply();
    const t2 = seedbed.total(&w, Channel.light.bit());
    std.debug.print("\napply twice: total {d:.3} then {d:.3}\n", .{ t1, t2 });
    try testing.expectApproxEqRel(t1, t2, 1e-9);
}

const UnitsRun = struct { hash: [32]u8, calls: u64, units: u64, max_call: u64, finish_units: u64, inside: u64, fronts_skipped: u64 };

/// The wounded sapling (G1's fixture) stepped through `work(units)` calls
/// — SPREAD — serial or over `js`. Every call's units are checked
/// against `units` (G15 b).
fn woundedThroughUnits(gpa: std.mem.Allocator, units: u64, js: ?*jobs.JobSystem, chunk_applies: bool) !UnitsRun {
    var g: GrownWorld = undefined;
    g.world = try World.init(gpa, .{ .seed = 7 });
    g.world.jobs = js;
    g.world.policy.chunk_applies = chunk_applies;
    g.scene = .{};
    errdefer g.world.deinit();
    try g.scene.build(&g.world, .sapling);
    defer g.deinit();
    var r = UnitsRun{ .hash = undefined, .calls = 0, .units = 0, .max_call = 0, .finish_units = 0, .inside = 0, .fronts_skipped = 0 };
    var i: u64 = 0;
    while (i <= 40) : (i += 1) {
        if (i == 20) {
            try seedbed.damage(&g.world, .{ -10, 8, -10 }, .{ 10, 16, 10 });
            try g.world.apply();
        }
        try g.world.begin(now(i), js);
        while (!try g.world.work(units)) {
            r.calls += 1;
            r.max_call = @max(r.max_call, g.world.stats.units_last_call);
        }
        r.calls += 1;
        r.max_call = @max(r.max_call, g.world.stats.units_last_call);
        try g.world.finish();
        r.units += g.published().units;
        r.finish_units += g.world.stats.units_finish;
        r.fronts_skipped += g.world.stats.fronts_skipped;
    }
    r.hash = g.published().contentHash();
    r.inside = seedbed.insideCount(&g.world);
    return r;
}

test "G15 (a) SPREAD is exact: the wounded sapling through work(8) publishes the frozen reference, serial and over the job system" {
    const gpa = testing.allocator;
    const a = try woundedThroughUnits(gpa, thresholds.G15_UNITS, null, true);
    try testing.expectEqualSlices(u8, thresholds.G1_REFERENCE, &loam.dump.hex(a.hash));
    var js = try jobs.JobSystem.init(gpa, 4);
    defer js.deinit();
    const b = try woundedThroughUnits(gpa, thresholds.G15_UNITS, js, true);
    try testing.expectEqualSlices(u8, thresholds.G1_REFERENCE, &loam.dump.hex(b.hash));
    // And through a different call size: the same world.
    const c = try woundedThroughUnits(gpa, 37, null, true);
    try testing.expectEqualSlices(u8, thresholds.G1_REFERENCE, &loam.dump.hex(c.hash));
    std.debug.print("\nG15 (a): 40 steps in {d} calls of {d} units ({d} units, none in finish); over 4 threads {d} calls; in calls of 37, {d} calls: all the frozen reference\n", .{ a.calls, thresholds.G15_UNITS, a.units, b.calls, c.calls });
    try testing.expectEqual(@as(u64, 0), a.finish_units);
    try testing.expect(a.calls > 40 * 10);
}

test "G15 (b) no work call performs more than its units, any phase" {
    const gpa = testing.allocator;
    const a = try woundedThroughUnits(gpa, thresholds.G15_UNITS, null, true);
    std.debug.print("\nG15 (b): the largest call performed {d} of {d} units over {d} calls\n", .{ a.max_call, thresholds.G15_UNITS, a.calls });
    try testing.expect(a.max_call <= thresholds.G15_UNITS);
}

test "G15 (b) mutation: the seam and halo apply passes unchunked → a call exceeds its units" {
    const gpa = testing.allocator;
    const a = try woundedThroughUnits(gpa, thresholds.G15_UNITS, null, false);
    std.debug.print("\nG15 (b) mutation: the largest call performed {d} of {d} units\n", .{ a.max_call, thresholds.G15_UNITS });
    try testing.expect(a.max_call > thresholds.G15_UNITS);
    // And the world is the same: chunking is accounting, not semantics.
    try testing.expectEqualSlices(u8, thresholds.G1_REFERENCE, &loam.dump.hex(a.hash));
}

const CutRun = struct { inside: u64, cut_steps: u64, fronts_skipped: u64, finish_units: u64, live_steps: u64, front_steps: u64 };

/// The sapling, G2's 160 steps, each CUT after the fronts and `fraction`
/// of the head: the evaluated set checked against the head order's
/// prefix recomputed from the snapshot alone (G15 c), no front step
/// skipped (G15 d). Under the mutation the fronts are deferrable and the
/// cut lands after `fraction` of THEM.
fn saplingCut(gpa: std.mem.Allocator, fraction: f32, cut_fronts: bool) !CutRun {
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 0, null);
    defer g.deinit();
    g.world.policy.cut_fronts = cut_fronts;
    var r = CutRun{ .inside = 0, .cut_steps = 0, .fronts_skipped = 0, .finish_units = 0, .live_steps = 0, .front_steps = 0 };
    var i: u64 = 1;
    while (i <= thresholds.G2_STEPS) : (i += 1) {
        const before = g.world.head;
        before.retain();
        defer before.release();
        var live: u64 = 0;
        for (before.fronts) |f| if (f.alive and !f.dormant) {
            live += 1;
        };
        try g.world.begin(now(i), null);
        const p = g.world.plan().?;
        const head_take: u64 = @intFromFloat(@ceil(@as(f32, @floatFromInt(p.head)) * fraction));
        const front_take: u64 = if (cut_fronts) @intFromFloat(@ceil(@as(f32, @floatFromInt(p.fronts)) * fraction)) else @as(u64, p.fronts) + head_take;
        _ = try g.world.work(front_take);
        try g.world.cut();
        try g.world.finish();
        if (g.published().cut_at) |c| {
            r.cut_steps += 1;
            if (!cut_fronts) {
                const ht = try attentionHead(gpa, before, now(i).time_ns, null);
                defer gpa.free(ht.head);
                try expectSameKeys(ht.head[0..c], g.world.evaluated);
            }
        }
        r.fronts_skipped += g.world.stats.fronts_skipped;
        r.finish_units += g.world.stats.units_finish;
        r.live_steps += live;
        r.front_steps += g.world.stats.front_steps;
    }
    r.inside = seedbed.insideCount(&g.world);
    return r;
}

test "G15 (c) CUT at half the head: the evaluated set is the head order's prefix, and the sapling ends within the floor of SPREAD's tissue (invariance)" {
    const gpa = testing.allocator;
    const full = try budgetedRun(gpa, null, .attention);
    const c = try saplingCut(gpa, thresholds.G15_CUT_FRACTION, false);
    const dev = deviation(full.inside, c.inside);
    std.debug.print("\nG15 (c) invariance: inside {d} SPREAD vs {d} CUT at {d:.0}% of the head (deviation {d:.2}%; {d} steps cut; {d} units in finish over the run)\n", .{ full.inside, c.inside, thresholds.G15_CUT_FRACTION * 100, dev * 100, c.cut_steps, c.finish_units });
    try testing.expect(c.cut_steps > 0);
    try testing.expect(dev <= thresholds.G15_MAX_DEVIATION);
}

test "G15 (c) mutation: the fronts made deferrable and the cut landing among them → the tips lag and the tissue deviates past the floor" {
    // (The brief named the cut in key order. Under a cut the fronts are
    // outside the cut by construction and the sapling's only operator is
    // inert, so key order changes which inert evaluations run — nothing.
    // The axis the gate varies on is the fronts' non-deferrability.)
    const gpa = testing.allocator;
    const full = try budgetedRun(gpa, null, .attention);
    const c = try saplingCut(gpa, thresholds.G15_CUT_FRACTION, true);
    const dev = deviation(full.inside, c.inside);
    std.debug.print("\nG15 (c) mutation, fronts deferrable: inside {d} vs {d} (deviation {d:.2}%; {d} front-steps skipped)\n", .{ full.inside, c.inside, dev * 100, c.fronts_skipped });
    try testing.expect(c.fronts_skipped > 0);
    try testing.expect(dev > thresholds.G15_MAX_DEVIATION);
}

test "G15 (d) no front step is skipped under any cut — the same front steps as SPREAD — and the step's work past the calls is reported" {
    const gpa = testing.allocator;
    const full = try budgetedRun(gpa, null, .attention);
    const c = try saplingCut(gpa, thresholds.G15_CUT_FRACTION, false);
    std.debug.print("\nG15 (d): {d} front steps over 160 cut steps against SPREAD's {d}, {d} skipped; {d} units in finish\n", .{ c.front_steps, full.front_steps, c.fronts_skipped, c.finish_units });
    try testing.expectEqual(@as(u64, 0), c.fronts_skipped);
    try testing.expectEqual(full.front_steps, c.front_steps);
    try testing.expect(c.finish_units > 0);
}

// ── P1.6: snapshots ──────────────────────────────────────────────────────

const Reader = struct {
    world: *World,
    slot: *loam.world.ReaderSlot,
    target: [32]u8,
    reads: u64 = 0,
    max_vid: u64 = 0,
    mismatches: u64 = 0,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    fn hashBricks(snap: *const loam.Snapshot, gpa: std.mem.Allocator) ![32]u8 {
        // A walk over every brick's bytes, not the cached root hash: the
        // reader must touch the memory the writer might be clobbering.
        var h = std.crypto.hash.Blake3.init(.{});
        const bs = try snap.bricks(gpa);
        defer gpa.free(bs);
        for (bs) |b| {
            for (b.planes) |pl| h.update(std.mem.sliceAsBytes(pl[0..]));
        }
        var out: [32]u8 = undefined;
        h.final(&out);
        return out;
    }

    fn run(self: *Reader) void {
        const gpa = std.heap.page_allocator;
        // Pin the snapshot that was current when the reader started, and
        // hash it again and again while the writer publishes N+1, N+2 …
        const pinned = self.world.acquire(self.slot);
        defer pinned.release();
        while (!self.stop.load(.acquire)) {
            const h = hashBricks(pinned, gpa) catch unreachable;
            if (!std.mem.eql(u8, &h, &self.target)) self.mismatches += 1;
            self.reads += 1;
            // And the live one, to prove acquire is safe mid-publish.
            const live = self.world.acquire(self.slot);
            self.max_vid = @max(self.max_vid, live.vid);
            live.release();
        }
    }
};

test "G8: snapshot N stays readable and byte-stable while N+1.. simulate on another thread" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 20, null);
    defer g.deinit();
    const slot = try g.world.registerReader();
    defer g.world.unregisterReader(slot);
    const target = try Reader.hashBricks(g.published(), gpa);
    const vid0 = g.published().vid;
    var reader = Reader{ .world = &g.world, .slot = slot, .target = target };
    const th = try std.Thread.spawn(.{}, Reader.run, .{&reader});
    var i: u64 = 21;
    while (i <= 60) : (i += 1) try g.world.step(now(i), null);
    reader.stop.store(true, .release);
    th.join();
    std.debug.print("\nG8: {d} full re-hashes of vid {d} while the writer reached vid {d}; {d} mismatches; reader saw vid {d}\n", .{ reader.reads, vid0, g.published().vid, reader.mismatches, reader.max_vid });
    try testing.expect(reader.reads > 0);
    try testing.expectEqual(@as(u64, 0), reader.mismatches);
    try testing.expect(reader.max_vid > vid0);
    try testing.expect(g.world.retired.items.len == 0 or g.world.retired.items.len < 4);
}

test "G8 mutation: a brick written in place changes the hash the reader holds" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    try g.grow(gpa, 7, 20, null);
    defer g.deinit();
    const snap = g.published();
    const h0 = try Reader.hashBricks(snap, gpa);
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    // Publish in place: the mutation. Never do this outside a test.
    const victim: *Brick = @constCast(bs[0]);
    if (victim.planes.len > 0) victim.planes[0][0] += 1;
    const h1 = try Reader.hashBricks(snap, gpa);
    try testing.expect(!std.mem.eql(u8, &h0, &h1));
    if (victim.planes.len > 0) victim.planes[0][0] -= 1;
}

// ── Guards: every invariant, corrupted, fires ────────────────────────────

test "guards self-test: each invariant, corrupted, is refused by name" {
    const gpa = testing.allocator;
    var w = try World.init(gpa, .{ .seed = 1 });
    defer w.deinit();
    var scene = seedbed.Scene{};
    try scene.build(&w, .seams);
    const snap: *loam.Snapshot = @constCast(w.published());
    try guards.check(snap);
    const root: *loam.tree.Node = @constCast(snap.root.?);

    // 1. A parent that does not cover its children.
    const saved_mask = root.summary.mask;
    root.summary.mask = 0;
    try testing.expectError(guards.Violation.SummaryNotConservative, guards.check(snap));
    root.summary.mask = saved_mask;
    try guards.check(snap);

    // 1b. A parent whose attention bound is under a child's (R15): a walk
    // trusting it would skip a brick that changed. The magnitude from the
    // root's side; the time from a child's — the seams scene is authored
    // at time zero, so every `changed_ns` here is zero and only a child
    // raised above its parent can show the bound.
    const saved_att = root.summary.attention;
    try testing.expect(saved_att > 0);
    root.summary.attention = 0;
    try testing.expectError(guards.Violation.SummaryNotConservative, guards.check(snap));
    root.summary.attention = saved_att;
    const child: *loam.tree.Node = blk: {
        for (root.kind.inner) |c| if (c) |cn| break :blk @constCast(cn);
        unreachable;
    };
    const saved_child = child.summary;
    child.summary.changed_ns = root.summary.changed_ns + 1;
    try testing.expectError(guards.Violation.SummaryNotConservative, guards.check(snap));
    child.summary = saved_child;
    try guards.check(snap);

    // 2. An absent channel instantiated (an all-zero plane).
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    const victim: *Brick = @constCast(bs[0]);
    _ = try victim.ensurePlane(gpa, Channel.roughness.bit());
    try testing.expectError(guards.Violation.AbsentChannelAllocated, guards.check(snap));
    victim.finalize(gpa); // drops the zero plane
    try guards.check(snap);

    // 3. A stale leaf summary: a boundary sample edited without finalize.
    var edited: ?*Brick = null;
    var edited_idx: usize = 0;
    var edited_old: f32 = 0;
    for (bs) |b| {
        const pl = b.plane(Channel.light.bit()) orelse continue;
        var k: u32 = 0;
        while (k < brick.N and edited == null) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N and edited == null) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const idx = Brick.index(i, j, k);
                    if (Brick.isBoundary(i, j, k) and pl[idx] > 0.1) {
                        edited = @constCast(b);
                        edited_idx = idx;
                        edited_old = pl[idx];
                        break;
                    }
                }
            }
        }
        if (edited != null) break;
    }
    const eb = edited.?;
    eb.planes[channel.planeIndex(eb.mask, Channel.light.bit())][edited_idx] = edited_old + 0.5;
    try testing.expectError(guards.Violation.LeafSummaryStale, guards.check(snap));

    // 4. The same edit with the summaries patched up: the seam disagrees.
    eb.finalize(gpa);
    patchLeafSummary(root, eb);
    try testing.expectError(guards.Violation.SeamDisagrees, guards.check(snap));
    eb.planes[channel.planeIndex(eb.mask, Channel.light.bit())][edited_idx] = edited_old;
    eb.finalize(gpa);
    patchLeafSummary(root, eb);
    try guards.check(snap);

    // 4b. A halo entry that is not what its neighbour holds (R7): the
    // summary patched so only the halo rule can catch it.
    const halo_idx = Brick.bindex(0, 5, 5);
    const hpl = eb.planes[channel.planeIndex(eb.mask, Channel.light.bit())];
    const halo_old = hpl[halo_idx];
    hpl[halo_idx] = halo_old + 0.25;
    eb.finalize(gpa);
    patchLeafSummary(root, eb);
    try testing.expectError(guards.Violation.HaloStale, guards.check(snap));
    hpl[halo_idx] = halo_old;
    eb.finalize(gpa);
    patchLeafSummary(root, eb);
    try guards.check(snap);

    // 5. An active key nobody holds; 6. keys out of order.
    const saved_active = snap.active;
    const bogus = try gpa.alloc(Key, 1);
    defer gpa.free(bogus);
    bogus[0] = Key.ofBrick(0, .{ 8, 8, 8 });
    snap.active = bogus;
    try testing.expectError(guards.Violation.ActiveKeyUnknown, guards.check(snap));
    const twice = try gpa.alloc(Key, 2);
    defer gpa.free(twice);
    twice[0] = bs[1].key;
    twice[1] = bs[0].key;
    snap.active = twice;
    try testing.expectError(guards.Violation.KeysNotSortedUnique, guards.check(snap));
    snap.active = saved_active;
    try guards.check(snap);
}

/// Recompute every node's summary from its children — what a commit
/// does along dirty paths, applied to the whole tree after a test edit.
fn patchLeafSummary(n: *loam.tree.Node, b: *const Brick) void {
    switch (n.kind) {
        .leaf => |lb| if (lb == b) {
            n.summary = b.summary;
        },
        .inner => |ch| {
            var s = loam.Summary{};
            for (ch) |c| if (c) |cn| {
                patchLeafSummary(@constCast(cn), b);
                s = loam.Summary.merge(s, cn.summary);
            };
            n.summary = s;
        },
    }
}

// ── The dump ─────────────────────────────────────────────────────────────

test "dump: two worlds fed the same inputs write the same bytes, and the bytes name what they hold" {
    const gpa = testing.allocator;
    var a: GrownWorld = undefined;
    try a.grow(gpa, 3, 10, null);
    defer a.deinit();
    var b: GrownWorld = undefined;
    try b.grow(gpa, 3, 10, null);
    defer b.deinit();
    const da = try loam.dump.write(gpa, &a.world);
    defer gpa.free(da);
    const db = try loam.dump.write(gpa, &b.world);
    defer gpa.free(db);
    try testing.expectEqualSlices(u8, da, db);
    try testing.expect(std.mem.indexOf(u8, da, "root_hash") != null);
    try testing.expect(std.mem.indexOf(u8, da, "surface") != null);
}

// ── Phase 2: the continuous carrier ──────────────────────────────────────
//
// G13 first: the instrument the reconstruction is checked with before
// anything is grown on it. Its threshold was written before the sweep
// ran, against theory (`tools/g13_predict.py`, frozen in thresholds.zig).

const Recon = enum { spline, trilinear };

/// The carrier at `p` by the named reconstruction, through the leaf that
/// holds it — the instrument's two arms.
fn probe(snap: *const loam.Snapshot, p: [3]f64, recon: Recon) f32 {
    const b = snap.findLeaf(.{ tree.floorI(p[0]), tree.floorI(p[1]), tree.floorI(p[2]) }) orelse return channel.band(1);
    return switch (recon) {
        .spline => b.spline(Channel.surface.bit(), p),
        .trilinear => b.trilinear(Channel.surface.bit(), p),
    };
}

const G13Row = struct { r_over_h: f32, survives: bool, rec_min: f32, rec_max: f32 };

/// A frame for one orientation: the axis and two perpendiculars, as in
/// the predictor.
fn g13Frame(kind: u8) struct { d: [3]f64, e1: [3]f64, e2: [3]f64 } {
    const d: [3]f64 = switch (kind) {
        0 => .{ 0, 0, 1 },
        1 => loam.world.normalize(.{ 1, 1, 0 }),
        else => loam.world.normalize(.{ 1, 1, 1 }),
    };
    const t: [3]f64 = if (@abs(d[0]) < 0.9) .{ 1, 0, 0 } else .{ 0, 1, 0 };
    const e1 = loam.world.normalize(loam.world.cross(d, t));
    const e2 = loam.world.cross(d, e1);
    return .{ .d = d, .e1 = e1, .e2 = e2 };
}

/// The sweep: for every r/h, a straight capsule at radius (r/h)·h on
/// bricks at `gauge`, in three orientations and nine axis offsets in the
/// cell; whether the zero set survives on the axis, and where the
/// reconstruction crosses zero on perpendicular rays (worst and best of
/// r_rec/r). The same geometry and the same root finder as the
/// predictor, so a disagreement is the reconstruction's.
fn g13Sweep(gpa: std.mem.Allocator, gauge: u5, recon: Recon, radii_in_cells: bool) ![thresholds.G13_SWEEP.len]G13Row {
    var rows: [thresholds.G13_SWEEP.len]G13Row = undefined;
    const h: f64 = @floatFromInt(@as(u32, 1) << gauge);
    const centre = seedbed.sceneToLattice(.{ 0, 0, 0 });
    for (thresholds.G13_SWEEP, 0..) |roh, ri| {
        // The radius in lattice units: r/h cells of this gauge, or — the
        // coarsening mutation — r/h lattice units whatever the gauge.
        const r: f64 = if (radii_in_cells) @as(f64, roh) * h else @as(f64, roh);
        const r_eff: f64 = r / h;
        var axis_max: f32 = -std.math.inf(f32);
        var rec_min: f64 = std.math.inf(f64);
        var rec_max: f64 = -std.math.inf(f64);
        var kind: u8 = 0;
        while (kind < 3) : (kind += 1) {
            const fr = g13Frame(kind);
            const offsets = [_]f64{ 0, 0.25, 0.5 };
            for (offsets) |ou| {
                for (offsets) |ov| {
                    var w = try World.init(gpa, .{ .seed = 1 });
                    defer w.deinit();
                    var p0: [3]f64 = undefined;
                    inline for (0..3) |a| p0[a] = centre[a] + (ou * fr.e1[a] + ov * fr.e2[a]) * h;
                    const half: f64 = 16 * h;
                    const a0 = [3]f64{ p0[0] - fr.d[0] * half, p0[1] - fr.d[1] * half, p0[2] - fr.d[2] * half };
                    const a1 = [3]f64{ p0[0] + fr.d[0] * half, p0[1] + fr.d[1] * half, p0[2] + fr.d[2] * half };
                    try seedbed.capsuleLattice(&w, a0, a1, r, 0, gauge);
                    try w.apply();
                    const snap = w.published();
                    // On the axis: does the zero set survive?
                    var si: u32 = 0;
                    while (si < 8) : (si += 1) {
                        const s = @as(f64, @floatFromInt(si)) * 0.5 * h;
                        const q = [3]f64{ p0[0] + fr.d[0] * s, p0[1] + fr.d[1] * s, p0[2] + fr.d[2] * s };
                        axis_max = @max(axis_max, probe(snap, q, recon));
                    }
                    // Perpendicular rays at four axial positions and 24 angles:
                    // the first crossing from inside to outside, interpolated
                    // between 400 samples, as the predictor does.
                    var sa: u32 = 0;
                    while (sa < 8) : (sa += 2) {
                        const s = @as(f64, @floatFromInt(sa)) * 0.5 * h;
                        var th: u32 = 0;
                        while (th < 24) : (th += 1) {
                            const ang = 2 * std.math.pi * @as(f64, @floatFromInt(th)) / 24.0;
                            var dir: [3]f64 = undefined;
                            inline for (0..3) |a| dir[a] = @cos(ang) * fr.e1[a] + @sin(ang) * fr.e2[a];
                            const t_end = (r_eff + 2.5) * h;
                            var prev: f32 = undefined;
                            var ti: u32 = 0;
                            while (ti < 400) : (ti += 1) {
                                const t = t_end * @as(f64, @floatFromInt(ti)) / 399.0;
                                const q = [3]f64{ p0[0] + fr.d[0] * s + dir[0] * t, p0[1] + fr.d[1] * s + dir[1] * t, p0[2] + fr.d[2] * s + dir[2] * t };
                                const v = probe(snap, q, recon);
                                if (ti > 0 and prev < 0 and v >= 0) {
                                    const t_prev = t_end * @as(f64, @floatFromInt(ti - 1)) / 399.0;
                                    const t0 = t_prev + (t - t_prev) * (-@as(f64, prev)) / (@as(f64, v) - @as(f64, prev));
                                    rec_min = @min(rec_min, t0 / h);
                                    rec_max = @max(rec_max, t0 / h);
                                    break;
                                }
                                prev = v;
                            }
                        }
                    }
                }
            }
        }
        const survives = axis_max < 0;
        rows[ri] = .{
            .r_over_h = @floatCast(r_eff),
            .survives = survives,
            .rec_min = if (survives and rec_min < std.math.inf(f64)) @floatCast(rec_min / r_eff) else 0,
            .rec_max = if (survives and rec_max > -std.math.inf(f64)) @floatCast(rec_max / r_eff) else 0,
        };
    }
    return rows;
}

fn printG13(label: []const u8, rows: []const G13Row) void {
    std.debug.print("\n{s}:\n", .{label});
    for (rows, 0..) |row, i| {
        const pred = thresholds.G13_PREDICTED[i];
        if (row.survives) {
            std.debug.print("  r/h {d:5.2}  survives  r_rec/r {d:.4} … {d:.4}  (predicted {d:.4} … {d:.4})  bias {d:.1}% … {d:.1}%\n", .{ row.r_over_h, row.rec_min, row.rec_max, pred.rec_min, pred.rec_max, 100 * (row.rec_min - 1), 100 * (row.rec_max - 1) });
        } else {
            std.debug.print("  r/h {d:5.2}  VANISHES  (predicted {s})\n", .{ row.r_over_h, if (pred.survives) "survives" else "vanishes" });
        }
    }
}

test "G13: a thin capsule survives the B-spline as the prediction says, at r/h >= 1, faithfully at r/h >= 2" {
    const gpa = testing.allocator;
    const rows = try g13Sweep(gpa, 0, .spline, true);
    printG13("G13 (gauge 0, B-spline)", &rows);
    var worst_bias: f32 = 0;
    for (rows, 0..) |row, i| {
        const pred = thresholds.G13_PREDICTED[i];
        // (a) The instrument reads the prediction.
        try testing.expectEqual(pred.survives, row.survives);
        if (row.survives) {
            try testing.expect(@abs(row.rec_min - pred.rec_min) <= thresholds.G13_PREDICTION_TOL);
            try testing.expect(@abs(row.rec_max - pred.rec_max) <= thresholds.G13_PREDICTION_TOL);
        }
        // (b) Survival at and above the survival floor.
        if (row.r_over_h >= thresholds.G13_SURVIVE_R_OVER_H) try testing.expect(row.survives);
        // (c) Faithful at and above the faithful floor.
        if (row.r_over_h >= thresholds.G13_FAITHFUL_R_OVER_H) {
            try testing.expect(@abs(row.rec_min - 1) <= thresholds.G13_MAX_BIAS);
            try testing.expect(@abs(row.rec_max - 1) <= thresholds.G13_MAX_BIAS);
            worst_bias = @max(worst_bias, @abs(row.rec_min - 1));
        }
    }
    std.debug.print("G13: worst bias at r/h >= {d}: {d:.2}% (threshold {d:.0}%)\n", .{ thresholds.G13_FAITHFUL_R_OVER_H, 100 * worst_bias, 100 * thresholds.G13_MAX_BIAS });
}

test "G13 mutation: the gauge doubled without refinement → the capsule at r/h 1 vanishes and at 2 thins by more than the floor" {
    const gpa = testing.allocator;
    // The same radii in lattice units, on gauge-1 bricks: r/h halves.
    const rows = try g13Sweep(gpa, 1, .spline, false);
    printG13("G13 mutation (gauge 1, radii unchanged)", &rows);
    for (rows, 0..) |row, i| {
        const label = thresholds.G13_SWEEP[i];
        if (label == 1.0 or label == 1.5) try testing.expect(!row.survives);
        if (label == 2.0) try testing.expect(row.survives and @abs(row.rec_min - 1) > thresholds.G13_MAX_BIAS);
    }
}

test "G13 variation: trilinear in place of the B-spline survives thinner and thins less — a different instrument, recorded" {
    const gpa = testing.allocator;
    const rows = try g13Sweep(gpa, 0, .trilinear, true);
    printG13("G13 variation (gauge 0, trilinear)", &rows);
    // Survival at 0.75, where the B-spline's tube is gone: the two
    // reconstructions differ, and the gate can tell them apart.
    for (rows, 0..) |row, i| {
        if (thresholds.G13_SWEEP[i] == 0.75) try testing.expect(row.survives);
        if (thresholds.G13_SWEEP[i] == 2.0) try testing.expect(row.rec_min > thresholds.G13_PREDICTED[i].rec_min + thresholds.G13_PREDICTION_TOL);
    }
}

// ── G9: C2 across a same-gauge seam ──────────────────────────────────────

/// A capsule scene on one gauge, diagonal so it crosses many faces.
fn capsuleScene(gpa: std.mem.Allocator, halo: bool) !World {
    var w = try World.init(gpa, .{ .seed = 1, .policy = .{ .halo = halo } });
    errdefer w.deinit();
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    try seedbed.capsuleLattice(&w, .{ c[0] - 14, c[1] - 9, c[2] - 6 }, .{ c[0] + 13, c[1] + 11, c[2] + 7 }, 3.2, 0, 0);
    try seedbed.capsuleLattice(&w, .{ c[0] - 4, c[1] + 6, c[2] - 12 }, .{ c[0] + 6, c[1] - 8, c[2] + 12 }, 2.4, 0, 0);
    try w.apply();
    return w;
}

const SeamJets = struct { max_dv: f32 = 0, max_dg: f32 = 0, max_dh: f32 = 0, pairs: usize = 0 };

/// Over every shared face point between same-gauge holders, and points
/// between samples on the face, the largest disagreement in value,
/// gradient and Hessian between the two holders' B-splines.
fn seamJets(snap: *const loam.Snapshot, gpa: std.mem.Allocator) !SeamJets {
    var out = SeamJets{};
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    var holders: [8]*const Brick = undefined;
    for (bs) |b| {
        if (!b.has(Channel.surface.bit())) continue;
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    if (!Brick.isBoundary(i, j, k)) continue;
                    const p = b.pointAt(i, j, k);
                    const q0 = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
                    // The point, and a few off-lattice points on the same face.
                    const dels = [_][3]f64{ .{ 0, 0, 0 }, .{ 0.5, 0, 0 }, .{ 0, 0.5, 0 }, .{ 0, 0, 0.5 }, .{ 0.3, 0.7, 0 }, .{ 0, 0.3, 0.7 }, .{ 0.7, 0, 0.3 } };
                    for (dels) |dl| {
                        const q = [3]f64{ q0[0] + dl[0], q0[1] + dl[1], q0[2] + dl[2] };
                        const pi = [3]i64{ tree.floorI(q[0]), tree.floorI(q[1]), tree.floorI(q[2]) };
                        const nh = snap.findAll(pi, &holders);
                        if (nh < 2) continue;
                        var first: ?loam.Brick.Jet = null;
                        for (holders[0..nh]) |h| {
                            if (!guards.holdsReal(h.key, q)) continue;
                            if (h.gauge() != b.gauge()) continue;
                            if (!h.has(Channel.surface.bit())) continue;
                            const jet = h.splineJet(Channel.surface.bit(), q);
                            if (first) |f| {
                                out.pairs += 1;
                                out.max_dv = @max(out.max_dv, @abs(jet.v - f.v));
                                inline for (0..3) |a| out.max_dg = @max(out.max_dg, @abs(jet.grad[a] - f.grad[a]));
                                inline for (0..6) |a| out.max_dh = @max(out.max_dh, @abs(jet.hess[a] - f.hess[a]));
                            } else first = jet;
                        }
                    }
                }
            }
        }
    }
    return out;
}

test "G9: the carrier is C2 across a same-gauge seam — both holders' B-splines agree in value, gradient and Hessian" {
    const gpa = testing.allocator;
    var w = try capsuleScene(gpa, true);
    defer w.deinit();
    try guards.check(w.published());
    const j = try seamJets(w.published(), gpa);
    std.debug.print("\nG9: {d} pairs; max |Δv| {e:.2}, |Δ∇| {e:.2}, |Δ∇²| {e:.2}\n", .{ j.pairs, j.max_dv, j.max_dg, j.max_dh });
    try testing.expect(j.pairs > 100);
    try testing.expect(j.max_dv <= thresholds.G9_TOL);
    try testing.expect(j.max_dg <= thresholds.G9_TOL);
    try testing.expect(j.max_dh <= thresholds.G9_TOL);
}

test "G9 mutation: no halo copy → the two holders reconstruct from different coefficients and the derivatives disagree" {
    const gpa = testing.allocator;
    var w = try capsuleScene(gpa, false);
    defer w.deinit();
    try testing.expectError(guards.Violation.HaloStale, guards.check(w.published()));
    const j = try seamJets(w.published(), gpa);
    std.debug.print("\nG9 mutation: {d} pairs; max |Δv| {e:.2}, |Δ∇| {e:.2}, |Δ∇²| {e:.2}\n", .{ j.pairs, j.max_dv, j.max_dg, j.max_dh });
    try testing.expect(j.max_dg > thresholds.G9_TOL);
}

// ── G10: the summary's Lipschitz bound is conservative ───────────────────

const BoundCheck = struct { pairs: u64 = 0, violations: u64 = 0, tightest: f64 = 0 };

/// Random pairs inside every brick with a surface plane: |φ(x) − φ(y)|
/// against L‖x − y‖, L from the summary or — the mutation — from the
/// interior finite differences along axes alone.
fn boundCheck(snap: *const loam.Snapshot, gpa: std.mem.Allocator, mutated: bool) !BoundCheck {
    var out = BoundCheck{};
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    var rng = std.Random.DefaultPrng.init(7);
    const rnd = rng.random();
    for (bs) |b| {
        const pl = b.plane(Channel.surface.bit()) orelse continue;
        var L: f64 = b.summary.lipschitz;
        if (mutated) {
            // The old definition: the largest axis difference over the
            // brick's own samples, no root-sum-square, no halo.
            var m: f32 = 0;
            const sp: f32 = @floatFromInt(b.spacing());
            var k: u32 = 0;
            while (k < brick.N) : (k += 1) {
                var j: u32 = 0;
                while (j < brick.N) : (j += 1) {
                    var i: u32 = 0;
                    while (i < brick.N) : (i += 1) {
                        const v = pl[Brick.index(i, j, k)];
                        if (i + 1 < brick.N) m = @max(m, @abs(pl[Brick.index(i + 1, j, k)] - v) / sp);
                        if (j + 1 < brick.N) m = @max(m, @abs(pl[Brick.index(i, j + 1, k)] - v) / sp);
                        if (k + 1 < brick.N) m = @max(m, @abs(pl[Brick.index(i, j, k + 1)] - v) / sp);
                    }
                }
            }
            L = m;
        }
        const o = b.origin();
        const side: f64 = @floatFromInt(b.key.side());
        var n: u32 = 0;
        while (n < 300) : (n += 1) {
            var x: [3]f64 = undefined;
            var y: [3]f64 = undefined;
            inline for (0..3) |a| {
                x[a] = @as(f64, @floatFromInt(o[a])) + rnd.float(f64) * side;
                // Half the pairs close together, half anywhere.
                y[a] = if (n % 2 == 0) @as(f64, @floatFromInt(o[a])) + rnd.float(f64) * side else @min(@as(f64, @floatFromInt(o[a])) + side, @max(@as(f64, @floatFromInt(o[a])), x[a] + (rnd.float(f64) - 0.5) * 1.5));
            }
            const d = loam.world.len3(.{ x[0] - y[0], x[1] - y[1], x[2] - y[2] });
            if (d < 1e-9) continue;
            const dv = @abs(@as(f64, b.spline(Channel.surface.bit(), x)) - @as(f64, b.spline(Channel.surface.bit(), y)));
            out.pairs += 1;
            if (dv > L * d * (1 + 1e-5) + 1e-6) out.violations += 1;
            if (L > 0) out.tightest = @max(out.tightest, dv / (L * d));
        }
    }
    return out;
}

test "G10: the summary's Lipschitz bound is never exceeded by the reconstruction" {
    const gpa = testing.allocator;
    var w = try capsuleScene(gpa, true);
    defer w.deinit();
    const c = try boundCheck(w.published(), gpa, false);
    std.debug.print("\nG10: {d} pairs, {d} violations; the tightest pair reached {d:.3} of its bound\n", .{ c.pairs, c.violations, c.tightest });
    try testing.expect(c.pairs > 1000);
    try testing.expectEqual(@as(u64, 0), c.violations);
}

test "G10 mutation: L from interior axis differences alone → pairs exceed it" {
    const gpa = testing.allocator;
    var w = try capsuleScene(gpa, true);
    defer w.deinit();
    const c = try boundCheck(w.published(), gpa, true);
    std.debug.print("\nG10 mutation: {d} pairs, {d} violations\n", .{ c.pairs, c.violations });
    try testing.expect(c.violations > 0);
}

// ── G11: the sphere tracer never overshoots the zero set ─────────────────

const TraceCheck = struct { rays: u64 = 0, hits: u64 = 0, disagreements: u64 = 0, late: u64 = 0, off_surface: u64 = 0, stats: ray.TraceStats = .{} };

/// N rays from a sphere around the scene toward points near its centre:
/// the sphere tracer against a dense march at a sixteenth of a cell
/// (bisected), on hit/miss, on never passing the first crossing, and on
/// the hit lying on the zero set.
fn traceCheck(snap: *const loam.Snapshot, gpa: std.mem.Allocator, n: u32, opts: ray.TraceOptions) !TraceCheck {
    var out = TraceCheck{};
    var rng = std.Random.DefaultPrng.init(11);
    const rnd = rng.random();
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        // Origin on a sphere of radius 40; aim at a point within 12 of the centre.
        var d = loam.world.normalize(.{ rnd.float(f64) - 0.5, rnd.float(f64) - 0.5, rnd.float(f64) - 0.5 });
        const o = [3]f64{ c[0] + d[0] * 40, c[1] + d[1] * 40, c[2] + d[2] * 40 };
        const aim = [3]f64{ c[0] + (rnd.float(f64) - 0.5) * 24, c[1] + (rnd.float(f64) - 0.5) * 24, c[2] + (rnd.float(f64) - 0.5) * 24 };
        d = loam.world.normalize(.{ aim[0] - o[0], aim[1] - o[1], aim[2] - o[2] });
        const t_max: f64 = 80;
        // The dense march.
        var t_dense: ?f64 = null;
        {
            const step: f64 = 1.0 / 16.0;
            var t: f64 = 0;
            var prev = snap.sample(Channel.surface.bit(), o);
            if (prev <= 0) t_dense = 0;
            while (t_dense == null and t < t_max) : (t += step) {
                const q = [3]f64{ o[0] + d[0] * (t + step), o[1] + d[1] * (t + step), o[2] + d[2] * (t + step) };
                const v = snap.sample(Channel.surface.bit(), q);
                if (prev > 0 and v <= 0) {
                    var lo = t;
                    var hi = t + step;
                    var it: u32 = 0;
                    while (it < 40) : (it += 1) {
                        const mid = 0.5 * (lo + hi);
                        const mq = [3]f64{ o[0] + d[0] * mid, o[1] + d[1] * mid, o[2] + d[2] * mid };
                        if (snap.sample(Channel.surface.bit(), mq) > 0) lo = mid else hi = mid;
                    }
                    t_dense = hi;
                }
                prev = v;
            }
        }
        const hit = try ray.traceSurface(gpa, snap, o, d, 0, t_max, opts, &out.stats);
        out.rays += 1;
        if ((hit != null) != (t_dense != null)) {
            out.disagreements += 1;
            continue;
        }
        if (hit) |h| {
            out.hits += 1;
            // Never past the first crossing (tunnelling), and on the surface.
            if (h.t > t_dense.? + 1e-3) out.late += 1;
            if (@abs(@as(f64, h.phi)) > opts.eps) out.off_surface += 1;
        }
    }
    return out;
}

test "G11: a march stepped by |φ|/L never lands inside, never tunnels, and agrees with a dense march on every ray" {
    const gpa = testing.allocator;
    var w = try capsuleScene(gpa, true);
    defer w.deinit();
    const c = try traceCheck(w.published(), gpa, thresholds.G11_RAYS, .{});
    std.debug.print("\nG11: {d} rays, {d} hits, {d} hit/miss disagreements, {d} late, {d} off the surface; {d} steps ({d:.1} per ray), {d} overshoots, {d} stalls, {d} leaves\n", .{ c.rays, c.hits, c.disagreements, c.late, c.off_surface, c.stats.steps, @as(f64, @floatFromInt(c.stats.steps)) / @as(f64, @floatFromInt(c.rays)), c.stats.overshoots, c.stats.stalls, c.stats.leaves });
    try testing.expect(c.hits > c.rays / 4); // the gate ran where rays hit
    try testing.expectEqual(@as(u64, 0), c.disagreements);
    try testing.expectEqual(@as(u64, 0), c.late);
    try testing.expectEqual(@as(u64, 0), c.off_surface);
    try testing.expectEqual(@as(u64, 0), c.stats.overshoots);
    try testing.expectEqual(@as(u64, 0), c.stats.stalls);
}

test "G11 mutation: stepping by 2|φ|/L lands inside" {
    const gpa = testing.allocator;
    var w = try capsuleScene(gpa, true);
    defer w.deinit();
    const c = try traceCheck(w.published(), gpa, thresholds.G11_RAYS / 4, .{ .step_scale = 2.0 });
    std.debug.print("\nG11 mutation: {d} rays, {d} overshoots\n", .{ c.rays, c.stats.overshoots });
    try testing.expect(c.stats.overshoots > 0);
}

// ── P2.2: the collar, provenance and the bands (G12) ─────────────────────
//
// The brief's G12 asked for |∇φ| continuous to 1e-3 across a bud's
// junction. That is not an observable here: the reconstruction is the
// cubic B-spline of the samples, C2 whatever they hold, so a crease and a
// fillet both reconstruct smooth. G12 is bit-exact instead (the thresholds
// file says how), and the crease is Christian's number, MEASURED by
// `creaseProfile` and printed, never gated.

/// The junction scene grown `steps`: a straight parent with the ring CA
/// on and no steering, its child budded by hand at JUNCTION_STEP. No
/// front reads the field to steer, so two runs differing only in the
/// collar lay their tubes along the same axes — what (a)'s comparison
/// against the hard union needs.
fn junctionRun(gpa: std.mem.Allocator, collar: ?f32, gate: loam.world.CollarGate, steps: u32) !World {
    var w = try World.init(gpa, .{ .seed = 3, .policy = .{ .collar_gate = gate } });
    errdefer w.deinit();
    var scene = seedbed.Scene{ .collar = collar };
    try scene.build(&w, .junction);
    var i: u64 = 0;
    while (i <= steps) : (i += 1) {
        if (i == seedbed.JUNCTION_STEP) try seedbed.bud(&w, 0, 0);
        try w.step(now(i), null);
    }
    return w;
}

/// The coil grown `steps` at bend `coil` (radians per unit of arc).
fn coilRun(gpa: std.mem.Allocator, collar: ?f32, gate: loam.world.CollarGate, coil: ?f32, steps: u32) !World {
    var w = try World.init(gpa, .{ .seed = 3, .policy = .{ .collar_gate = gate } });
    errdefer w.deinit();
    var scene = seedbed.Scene{ .collar = collar };
    try scene.build(&w, .coil);
    if (coil) |c| w.fronts.items[0].params.coil = c;
    try run(&w, steps, null);
    return w;
}

/// Distance from `q` to the polyline through a front's ring centres.
fn distToRings(rings: []const loam.front.Ring, q: [3]f64) f64 {
    var best: f64 = std.math.inf(f64);
    if (rings.len == 1) return loam.world.len3(.{ q[0] - rings[0].pos[0], q[1] - rings[0].pos[1], q[2] - rings[0].pos[2] });
    var k: usize = 1;
    while (k < rings.len) : (k += 1) {
        const a = rings[k - 1].pos;
        const b = rings[k].pos;
        const ab = [3]f64{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
        const aq = [3]f64{ q[0] - a[0], q[1] - a[1], q[2] - a[2] };
        const l2 = loam.world.dot(ab, ab);
        const t: f64 = if (l2 > 1e-18) @min(1.0, @max(0.0, loam.world.dot(aq, ab) / l2)) else 0;
        const d = [3]f64{ aq[0] - t * ab[0], aq[1] - t * ab[1], aq[2] - t * ab[2] };
        best = @min(best, loam.world.len3(d));
    }
    return best;
}

/// The largest radius a front laid: envelope plus residual, over its rings.
fn maxRadius(rings: []const loam.front.Ring) f32 {
    var r: f32 = 0;
    for (rings) |rg| {
        var rm: f32 = 0;
        for (rg.r) |v| rm = @max(rm, @abs(v));
        r = @max(r, rg.envelope + rm);
    }
    return r;
}

/// The largest collar any front's capsule carried: collar × envelope.
fn maxCollar(w: *const World) f32 {
    var k: f32 = 0;
    for (w.rings.items, 0..) |list, id| {
        for (list.items) |rg| k = @max(k, w.fronts.items[id].params.collar * rg.envelope);
    }
    return k;
}

const CollarDiff = struct { samples: u64 = 0, higher: u64 = 0, lowered: u64 = 0, outside: u64 = 0, max_drop: f32 = 0, max_drop_outside: f32 = 0 };

/// Every own sample of every brick in either world: A's carrier against
/// B's (absent is far), and where they differ, whether the point is
/// within `zone` of the child's axis (`child` null: no zone, every
/// difference counts as outside).
fn collarDiff(gpa: std.mem.Allocator, a: *const World, b: *const World, child: ?u32, zone: f64) !CollarDiff {
    var out = CollarDiff{};
    const sa = a.published();
    const sb = b.published();
    var keys = std.AutoArrayHashMapUnmanaged(u64, void){};
    defer keys.deinit(gpa);
    const ba = try sa.bricks(gpa);
    defer gpa.free(ba);
    const bb = try sb.bricks(gpa);
    defer gpa.free(bb);
    for (ba) |br| try keys.put(gpa, br.key.raw(), {});
    for (bb) |br| try keys.put(gpa, br.key.raw(), {});
    const rings: []const loam.front.Ring = if (child) |c| a.rings.items[c].items else &.{};
    const sbit = Channel.surface.bit();
    for (keys.keys()) |raw| {
        const key = Key.fromRaw(raw);
        const bd = channel.band(key.spacing());
        const xa = sa.brickAt(key);
        const xb = sb.brickAt(key);
        const o = key.origin();
        const sp = key.spacing();
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const va: f32 = if (xa) |x| x.get(sbit, i, j, k) else bd;
                    const vb: f32 = if (xb) |x| x.get(sbit, i, j, k) else bd;
                    out.samples += 1;
                    if (va == vb) continue;
                    if (va > vb) {
                        out.higher += 1;
                        continue;
                    }
                    out.lowered += 1;
                    const drop = vb - va;
                    out.max_drop = @max(out.max_drop, drop);
                    const q = [3]f64{ @floatFromInt(o[0] + i * sp), @floatFromInt(o[1] + j * sp), @floatFromInt(o[2] + k * sp) };
                    const inside = child != null and distToRings(rings, q) <= zone;
                    if (!inside) {
                        out.outside += 1;
                        out.max_drop_outside = @max(out.max_drop_outside, drop);
                    }
                }
            }
        }
    }
    return out;
}

test "G12 (a) the collar: against the hard union the collared junction is nowhere higher, lower only within the child's zone, by at most k/4 and by more than nothing" {
    const gpa = testing.allocator;
    var a = try junctionRun(gpa, null, .recent, 40);
    defer a.deinit();
    var b = try junctionRun(gpa, 0, .recent, 40);
    defer b.deinit();
    try guards.check(a.published());
    const child: u32 = 1;
    const zone: f64 = thresholds.g12Zone(maxRadius(a.rings.items[child].items), channel.band(1));
    const d = try collarDiff(gpa, &a, &b, child, zone);
    const k = maxCollar(&a);
    std.debug.print("\nG12 (a): {d} samples; collared lower at {d}, higher at {d}, outside the child's zone ({d:.2} of its axis) {d}; largest drop {d:.3} against k/4 = {d:.3}; the collar acted on {d} samples over the run, provenance written {d}\n", .{ d.samples, d.lowered, d.higher, zone, d.outside, d.max_drop, k / 4, a.total.collar_samples, a.total.provenance_writes });
    try testing.expectEqual(@as(u64, 0), d.higher);
    try testing.expectEqual(@as(u64, 0), d.outside);
    try testing.expect(d.lowered > 0);
    try testing.expect(d.max_drop <= k / 4);
}

test "G12 (a) mutation: nothing is its own (`.none`) → the front beads into its own chain, the field lower far from the child" {
    const gpa = testing.allocator;
    var a = try junctionRun(gpa, null, .none, 40);
    defer a.deinit();
    var b = try junctionRun(gpa, 0, .recent, 40);
    defer b.deinit();
    const child: u32 = 1;
    const zone: f64 = thresholds.g12Zone(maxRadius(a.rings.items[child].items), channel.band(1));
    const d = try collarDiff(gpa, &a, &b, child, zone);
    std.debug.print("\nG12 (a) mutation .none: lower at {d}, {d} of them outside the child's zone, the largest such drop {d:.3}\n", .{ d.lowered, d.outside, d.max_drop_outside });
    try testing.expect(d.outside > 0);
}

test "G12 (a) the amendment: the coil's later turns are collared where they touch the earlier ones — self-touch beyond the reach is another front" {
    const gpa = testing.allocator;
    // One turn is 25 rings. In twenty steps the turns cannot touch; what
    // the collar does act on is the coil's own INNER WALL five to seven
    // rings back: a bend radius of 4 puts it within the collar's
    // Euclidean reach (the chord) while beyond its arc reach — a coil
    // tighter than the collar can tell from a self-touch. Recorded as
    // the arc rule's limit, printed, not gated.
    var a1 = try coilRun(gpa, null, .recent, null, 20);
    defer a1.deinit();
    var b1 = try coilRun(gpa, 0, .recent, null, 20);
    defer b1.deinit();
    const d1 = try collarDiff(gpa, &a1, &b1, null, 0);
    var a = try coilRun(gpa, null, .recent, null, 80);
    defer a.deinit();
    var b = try coilRun(gpa, 0, .recent, null, 80);
    defer b.deinit();
    const d = try collarDiff(gpa, &a, &b, null, 0);
    const k = maxCollar(&a);
    std.debug.print("\nG12 (a) coil: after 80 steps {d} samples lower than the hard chain and {d} higher, largest drop {d:.3} against k/4 = {d:.3}; the collar acted on {d} samples (in the first 20 steps, before any turn could touch, {d} samples of the inner wall — the arc rule's limit at a bend radius of 4)\n", .{ d.lowered, d.higher, d.max_drop, k / 4, a.total.collar_samples, d1.lowered });
    try testing.expectEqual(@as(u64, 0), d.higher);
    try testing.expectEqual(@as(u64, 0), d1.higher);
    try testing.expect(d.lowered > d1.lowered);
    try testing.expect(d.max_drop <= k / 4);
}

test "G12 (a) mutation: its own at any age (`.own`) → the coil's self-touch is the hard crease, no sample lower than the hard chain" {
    const gpa = testing.allocator;
    var a = try coilRun(gpa, null, .own, null, 80);
    defer a.deinit();
    var b = try coilRun(gpa, 0, .recent, null, 80);
    defer b.deinit();
    const d = try collarDiff(gpa, &a, &b, null, 0);
    std.debug.print("\nG12 (a) mutation .own: {d} samples lower than the hard chain after 80 steps (collar acted on {d})\n", .{ d.lowered, a.total.collar_samples });
    try testing.expectEqual(@as(u64, 0), d.lowered);
}

const BandCheck = struct { provenanced: u64 = 0, exact: u64 = 0, collared: u64 = 0, mismatched: u64 = 0, raised: u64 = 0, above_own: u64 = 0 };

/// Every provenanced own sample: the capsule rebuilt from the ring
/// records at (who, segment), its foot at the point, and the slot's own
/// distance, the chart's s and θ read back; the carrier never above the
/// slot (the union only lowers), and lower where a collar acted.
fn bandCheck(gpa: std.mem.Allocator, w: *const World) !BandCheck {
    var out = BandCheck{};
    const snap = w.published();
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    for (bs) |b| {
        const bd = b.band();
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const pv = b.provenanceAt(i, j, k) orelse continue;
                    out.provenanced += 1;
                    const cap = w.capsuleAt(pv.who, pv.segment) orelse {
                        out.mismatched += 1;
                        continue;
                    };
                    const p = b.pointAt(i, j, k);
                    const q = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
                    const ft = cap.foot(q);
                    const expected = @min(bd, @max(cap.signedAt(ft), -bd));
                    const own = b.get(Channel.own.bit(), i, j, k);
                    const phi = b.get(Channel.surface.bit(), i, j, k);
                    if (phi > own) out.above_own += 1;
                    if (phi < own) out.collared += 1;
                    if (own == expected) {
                        out.exact += 1;
                    } else if (own > expected) {
                        out.raised += 1;
                    } else out.mismatched += 1;
                }
            }
        }
    }
    return out;
}

test "G12 (b) the bands: band 1 read through the provenance chart reproduces every deposit bit for bit, the carrier is never above it, and a cut leaves the scar its provenance" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 40);
    defer w.deinit();
    const c = try bandCheck(gpa, &w);
    std.debug.print("\nG12 (b): {d} provenanced samples; {d} reproduce their deposit exactly, {d} raised, {d} mismatched; the carrier above its own slot at {d}, collared under it at {d}; tolerance {e}\n", .{ c.provenanced, c.exact, c.raised, c.mismatched, c.above_own, c.collared, thresholds.G12_BAND_TOL });
    try testing.expect(c.provenanced > 1000);
    try testing.expectEqual(c.provenanced, c.exact);
    try testing.expectEqual(@as(u64, 0), c.above_own);
    try testing.expect(c.collared > 0);
    // Band 1 and 2 read at a provenanced sample on the parent's tube.
    const centre = seedbed.sceneToLattice(.{ 0, 6, 0 });
    const on_tube = [3]i64{ tree.floorI(centre[0]) + 3, tree.floorI(centre[1]), tree.floorI(centre[2]) };
    const bq = w.bandQuery(w.published(), on_tube, .bark);
    try testing.expect(bq.provenance != null);
    try testing.expect(bq.band1 != null);
    try testing.expectEqual(@as(u32, 0), bq.provenance.?.who);
    // The scar remembers: a cut across the parent raises the carrier and
    // the slots and writes no provenance, so the raised samples keep the
    // parent's id and its chart.
    try seedbed.damage(&w, .{ -6, 3, -6 }, .{ 6, 5, 6 });
    try w.apply();
    const after = try bandCheck(gpa, &w);
    std.debug.print("G12 (b) the scar: {d} provenanced samples before the cut, {d} after; {d} raised above their deposit by the cut, still the parent's\n", .{ c.provenanced, after.provenanced, after.raised });
    try testing.expectEqual(c.provenanced, after.provenanced);
    try testing.expect(after.raised > 0);
    try testing.expectEqual(@as(u64, 0), after.mismatched);
}

test "G12 (c) the sponge: a band-0 query gathers the carrier's coefficients and nothing else; a bark query pays for the provenance and the rings" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 30);
    defer w.deinit();
    const snap = w.published();
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    var provenanced: u64 = 0;
    var sponge_bytes: u64 = 0;
    var bark_bytes: u64 = 0;
    var sponge_extra: u64 = 0;
    var bark_min: u64 = std.math.maxInt(u64);
    for (bs) |b| {
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const p = b.pointAt(i, j, k);
                    const q = [3]i64{ p[0], p[1], p[2] };
                    const sp = w.bandQuery(snap, q, .sponge);
                    sponge_bytes += sp.bytes;
                    if (sp.bytes != thresholds.G12_SPONGE_BYTES or sp.band1 != null or sp.provenance != null) sponge_extra += 1;
                    if (b.provenanceAt(i, j, k) == null) continue;
                    provenanced += 1;
                    const bk = w.bandQuery(snap, q, .bark);
                    bark_bytes += bk.bytes;
                    bark_min = @min(bark_min, bk.bytes);
                    if (bk.band1 == null) sponge_extra += 1;
                }
            }
        }
    }
    std.debug.print("\nG12 (c): {d} provenanced samples; a sponge query {d} bytes each, a bark query {d} at least ({d:.1} on average) — two provenance samples and {d}-byte ring records\n", .{ provenanced, thresholds.G12_SPONGE_BYTES, bark_min, @as(f64, @floatFromInt(bark_bytes)) / @as(f64, @floatFromInt(provenanced)), @sizeOf(loam.front.Ring) });
    try testing.expect(provenanced > 1000);
    try testing.expectEqual(@as(u64, 0), sponge_extra);
    try testing.expect(bark_min >= thresholds.G12_SPONGE_BYTES + 2 * 4 + 2 * @sizeOf(loam.front.Ring));
}

// ── The inner elbow: Christian's number, measured ────────────────────────

const Crease = struct {
    /// The largest turn of the surface normal between neighbouring hits,
    /// radians per lattice unit of separation — a crease concentrates
    /// the turn, a fillet spreads it.
    turn_per_unit: f64 = 0,
    /// The median turn per unit over the sweep: the surface's own turn
    /// there — the tube's bend along a generator, its curvature across —
    /// against which the fold reads as an excess.
    baseline: f64 = 0,
    hits: usize = 0,
    /// Where the largest turn sat, as the ray's angle from the bisector.
    at_deg: f64 = 0,
};

/// Rays from `centre` in the plane (u, v), at angles ±`half` about u, to
/// the reconstructed zero set (a march then a bisection on the spline);
/// the B-spline gradient at each hit, and the turn between neighbours.
fn creaseProfile(snap: *const loam.Snapshot, centre: [3]f64, u: [3]f64, v: [3]f64, half: f64, n: usize) Crease {
    var out = Crease{};
    var prev_g: ?[3]f64 = null;
    var prev_p: [3]f64 = undefined;
    var turns: [256]f64 = undefined;
    var nt: usize = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const psi = -half + 2 * half * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        const cp = @cos(psi);
        const sn = @sin(psi);
        const d = [3]f64{ cp * u[0] + sn * v[0], cp * u[1] + sn * v[1], cp * u[2] + sn * v[2] };
        // March out to the first sign change, then bisect.
        var t0: f64 = 0;
        var t1: f64 = 0.1;
        var found = false;
        while (t1 < 30) : ({
            t0 = t1;
            t1 += 0.1;
        }) {
            const p = [3]f64{ centre[0] + d[0] * t1, centre[1] + d[1] * t1, centre[2] + d[2] * t1 };
            if (probe(snap, p, .spline) >= 0) {
                found = true;
                break;
            }
        }
        if (!found) continue;
        var it: usize = 0;
        while (it < 40) : (it += 1) {
            const tm = 0.5 * (t0 + t1);
            const p = [3]f64{ centre[0] + d[0] * tm, centre[1] + d[1] * tm, centre[2] + d[2] * tm };
            if (probe(snap, p, .spline) >= 0) t1 = tm else t0 = tm;
        }
        const p = [3]f64{ centre[0] + d[0] * t1, centre[1] + d[1] * t1, centre[2] + d[2] * t1 };
        const jet = snap.sampleJet(Channel.surface.bit(), p) orelse continue;
        const g = loam.world.normalize(.{ jet.grad[0], jet.grad[1], jet.grad[2] });
        out.hits += 1;
        if (prev_g) |pg| {
            const turn = std.math.acos(@min(1.0, @max(-1.0, loam.world.dot(g, pg))));
            const sep = loam.world.len3(.{ p[0] - prev_p[0], p[1] - prev_p[1], p[2] - prev_p[2] });
            if (sep > 1e-9) {
                if (nt < turns.len) {
                    turns[nt] = turn / sep;
                    nt += 1;
                }
                if (turn / sep > out.turn_per_unit) {
                    out.turn_per_unit = turn / sep;
                    out.at_deg = psi * 180.0 / std.math.pi;
                }
            }
        }
        prev_g = g;
        prev_p = p;
    }
    if (nt > 0) {
        std.mem.sort(f64, turns[0..nt], {}, std.sort.asc(f64));
        out.baseline = turns[nt / 2];
    }
    return out;
}

/// The inner elbow at ring `k` of a front: rays from the ring's centre
/// in the plane of the bend, about the inner bisector (toward the centre
/// of curvature); and the outer, opposite.
fn elbowAt(snap: *const loam.Snapshot, rings: []const loam.front.Ring, k: usize) struct { inner: Crease, outer: Crease, bend_deg: f64 } {
    const a = rings[k];
    const b = rings[k + 1];
    const bend = b.bendFrom(&a);
    const u = loam.world.normalize(.{ b.dir[0] - a.dir[0], b.dir[1] - a.dir[1], b.dir[2] - a.dir[2] });
    const v = loam.world.normalize(.{ b.dir[0] + a.dir[0], b.dir[1] + a.dir[1], b.dir[2] + a.dir[2] });
    // A sweep of ±40° from the ring's centre reaches about a radius along
    // the tube either way: across the fold, not along the bend.
    const half = 40.0 * std.math.pi / 180.0;
    return .{
        .inner = creaseProfile(snap, a.pos, u, v, half, 81),
        .outer = creaseProfile(snap, a.pos, .{ -u[0], -u[1], -u[2] }, v, half, 81),
        .bend_deg = bend * 180.0 / std.math.pi,
    };
}

fn printElbow(label: []const u8, r: f32, e: anytype) void {
    const deg = 180.0 / std.math.pi;
    std.debug.print("  {s:<30} bend {d:6.2}°/ring  inner fold {d:7.2}°/unit over a baseline of {d:6.2} (excess {d:6.2}, at {d:6.1}°)  outer {d:6.2} over {d:6.2}  tube 1/r {d:5.2}°/unit  trigger h/r {d:5.2}°\n", .{ label, e.bend_deg, e.inner.turn_per_unit * deg, e.inner.baseline * deg, (e.inner.turn_per_unit - e.inner.baseline) * deg, e.inner.at_deg, e.outer.turn_per_unit * deg, e.outer.baseline * deg, deg / r, thresholds.elbowTrigger(r, 1) * deg });
}

test "the inner elbow, measured: crease angle at the concave fold against the ring-to-ring bend, on the sapling, the coil and the bud junction" {
    const gpa = testing.allocator;
    std.debug.print("\nThe inner elbow ({s}): the normal's turn per lattice unit across the fold, from the B-spline jet at hits on the zero set\n", .{@tagName(builtin.mode)});
    // The sapling's trunk at its sharpest ring, and the sharpest ring of any front.
    {
        var g: GrownWorld = undefined;
        try g.grow(gpa, 7, 40, null);
        defer g.deinit();
        const snap = g.published();
        var best_k: usize = 1;
        var best_bend: f64 = 0;
        const trunk = g.world.rings.items[0].items;
        var k: usize = 1;
        while (k + 1 < trunk.len) : (k += 1) {
            const bend = trunk[k + 1].bendFrom(&trunk[k]);
            if (bend > best_bend) {
                best_bend = bend;
                best_k = k;
            }
        }
        printElbow("sapling trunk, sharpest ring", trunk[best_k].envelope, elbowAt(snap, trunk, best_k));
        // And a typical ring: the trunk's median bend.
        var bends: [256]f64 = undefined;
        var nb: usize = 0;
        k = 1;
        while (k + 1 < trunk.len and nb < bends.len) : (k += 1) {
            bends[nb] = trunk[k + 1].bendFrom(&trunk[k]);
            nb += 1;
        }
        std.mem.sort(f64, bends[0..nb], {}, std.sort.asc(f64));
        const median = bends[nb / 2];
        k = 1;
        while (k + 1 < trunk.len) : (k += 1) {
            if (trunk[k + 1].bendFrom(&trunk[k]) == median) break;
        }
        printElbow("sapling trunk, median ring", trunk[k].envelope, elbowAt(snap, trunk, k));
    }
    // The coil at its set bend: a fold every ring, 14° each.
    {
        var w = try coilRun(gpa, null, .recent, null, 40);
        defer w.deinit();
        const rings = w.rings.items[0].items;
        printElbow("coil 0.25 rad/unit, ring 20", rings[20].envelope, elbowAt(w.published(), rings, 20));
    }
    // The bud junction, collared and hard: rays from the junction on the
    // parent's axis, in the plane of the parent and the child, about the
    // bisector of the inner corner.
    for ([_]?f32{ null, 0 }) |collar| {
        var w = try junctionRun(gpa, collar, .recent, 40);
        defer w.deinit();
        const parent = w.rings.items[0].items;
        const child = w.rings.items[1].items;
        const jr = parent[seedbed.JUNCTION_STEP];
        const cd = child[1].dir;
        const u = loam.world.normalize(.{ jr.dir[0] + cd[0], jr.dir[1] + cd[1], jr.dir[2] + cd[2] });
        const w2 = loam.world.normalize(.{ cd[0] - jr.dir[0], cd[1] - jr.dir[1], cd[2] - jr.dir[2] });
        const c = creaseProfile(w.published(), jr.pos, u, w2, 40.0 * std.math.pi / 180.0, 81);
        const deg = 180.0 / std.math.pi;
        std.debug.print("  {s:<30} corner {d:6.2}°       inner fold {d:7.2}°/unit over a baseline of {d:6.2} (excess {d:6.2}, at {d:6.1}°)  the join's k {d:.2}\n", .{ if (collar == null) "bud junction, collared" else "bud junction, hard", child[1].bendFrom(&jr) * deg, c.turn_per_unit * deg, c.baseline * deg, (c.turn_per_unit - c.baseline) * deg, c.at_deg, if (collar == null) w.fronts.items[1].params.collar * child[1].envelope else 0 });
    }
}

// ── P2.3: the picture — what a hit reads (G16) ───────────────────────────

const bark = loam.bark;

/// The first zero crossing of the carrier from `from` along `dir`
/// (`from` inside), by a march and a bisection on the spline; the point
/// and the unbent normal from the jet.
fn surfaceHit(snap: *const loam.Snapshot, from: [3]f64, dir: [3]f64, max_t: f64) ?struct { p: [3]f64, n: [3]f32 } {
    // From inside, the first exit; from the void, the first entry.
    const inside = probe(snap, from, .spline) < 0;
    var t0: f64 = 0;
    var t1: f64 = 0.05;
    var found = false;
    while (t1 < max_t) : ({
        t0 = t1;
        t1 += 0.05;
    }) {
        const v = probe(snap, .{ from[0] + dir[0] * t1, from[1] + dir[1] * t1, from[2] + dir[2] * t1 }, .spline);
        if ((v >= 0) == inside) {
            found = true;
            break;
        }
    }
    if (!found) return null;
    var it: usize = 0;
    while (it < 40) : (it += 1) {
        const tm = 0.5 * (t0 + t1);
        const v = probe(snap, .{ from[0] + dir[0] * tm, from[1] + dir[1] * tm, from[2] + dir[2] * tm }, .spline);
        if ((v >= 0) == inside) t1 = tm else t0 = tm;
    }
    const p = [3]f64{ from[0] + dir[0] * t1, from[1] + dir[1] * t1, from[2] + dir[2] * t1 };
    const jet = snap.sampleJet(Channel.surface.bit(), p) orelse return null;
    const g = loam.world.normalize(.{ jet.grad[0], jet.grad[1], jet.grad[2] });
    return .{ .p = p, .n = .{ @floatCast(g[0]), @floatCast(g[1]), @floatCast(g[2]) } };
}

fn wrapPi(x: f32) f32 {
    var v = @mod(x, 2 * std.math.pi);
    if (v > std.math.pi) v -= 2 * std.math.pi;
    return v;
}

fn turn3(a: [3]f32, b: [3]f32) f32 {
    const d = a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    return std.math.acos(@min(1.0, @max(-1.0, d)));
}

const Generator = struct { probes: u64 = 0, pairs: u64 = 0, max_ds: f32 = 0, max_dtheta: f32 = 0, max_theta_err: f32 = 0, who_flips: u64 = 0, flips_outside: u64 = 0, child_owned: u64 = 0, non_integer_who: u64 = 0, non_integer_seg: u64 = 0 };

/// Probes along a generator of the parent — rays from its axis toward
/// `side`, every quarter unit of arc — reading the chart at each hit.
/// Between neighbours both the parent's, s must advance by the arc and
/// θ fall by the roll's drift; at every parent-owned hit θ must be the
/// chart's own — `psi` minus the roll at that arc (the roll is drift ×
/// s along a straight parent) — read against the wrap; `who` may
/// change only inside G12's zone.
fn generator(w: *const World, side: [3]f64, psi: f32, rules: bark.Rules, zone: f64) Generator {
    var out = Generator{};
    const snap = w.published();
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    const drift: f32 = w.fronts.items[0].params.drift;
    const child = w.rings.items[1].items;
    var prev: ?bark.Chart = null;
    var prev_y: f64 = 0;
    var y: f64 = c[1] + 3;
    while (y <= c[1] + 30) : (y += 0.25) {
        const hit = surfaceHit(snap, .{ c[0], y, c[2] }, side, 12) orelse continue;
        var planes: u8 = 0;
        var bytes: u64 = 0;
        const ch = bark.chartAt(w, snap, hit.p, rules, &planes, &bytes) orelse continue;
        out.probes += 1;
        if (ch.who_raw != @round(ch.who_raw)) out.non_integer_who += 1;
        if (ch.segment_raw != @round(ch.segment_raw)) out.non_integer_seg += 1;
        const in_zone = distToRings(child, hit.p) <= zone;
        if (ch.who == 1) {
            out.child_owned += 1;
            if (!in_zone) out.flips_outside += 1;
        } else if (ch.who == 0) {
            const s_here: f32 = @floatCast(y - c[1]);
            out.max_theta_err = @max(out.max_theta_err, @abs(wrapPi(ch.theta - (psi - drift * s_here))));
        }
        if (prev) |pv| {
            if (pv.who != ch.who) {
                out.who_flips += 1;
            } else if (ch.who == 0) {
                out.pairs += 1;
                const dy: f32 = @floatCast(y - prev_y);
                out.max_ds = @max(out.max_ds, @abs((ch.s - pv.s) - dy));
                out.max_dtheta = @max(out.max_dtheta, @abs(wrapPi(ch.theta - pv.theta) + drift * dy));
            }
        }
        prev = ch;
        prev_y = y;
    }
    return out;
}

const Fan = struct { hits: u64 = 0, max_bent_excess: f32 = 0, at_flip_bent_vs_unbent: f32 = 0, at_flip_bare: f32 = 0, flips: u64 = 0, min_bare: f32 = 1, max_sep: f32 = 0, flip_sep: f32 = 0, max_planes: u8 = 0 };

/// A fan of rays from a point in the void above the junction, across the
/// crotch: from the parent's surface on one side, over the fillet, onto
/// the child's upper side on the other. At every hit the bark is read;
/// between neighbouring hits the bent normal's turn against the unbent
/// one's, bounded by the bump's own curvature over their separation;
/// and where `who` changes, how far the bent normal stands from the
/// unbent — bare, it stands nowhere.
fn fanAcross(w: *const World, from: [3]f64, u: [3]f64, v: [3]f64, half: f64, n: usize, footprint: f32, rules: bark.Rules) Fan {
    var out = Fan{};
    const snap = w.published();
    var prev: ?bark.Bark = null;
    var prev_n: [3]f32 = undefined;
    var prev_p: [3]f64 = undefined;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const psi = -half + 2 * half * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(n - 1));
        const cp = @cos(psi);
        const sn = @sin(psi);
        const d = [3]f64{ cp * u[0] + sn * v[0], cp * u[1] + sn * v[1], cp * u[2] + sn * v[2] };
        const hit = surfaceHit(snap, from, d, 20) orelse continue;
        const b = bark.read(w, snap, hit.p, hit.n, footprint, .bark, rules);
        out.hits += 1;
        out.min_bare = @min(out.min_bare, b.bare);
        out.max_planes = @max(out.max_planes, b.planes);
        if (prev) |pv| {
            const sep: f32 = @floatCast(loam.world.len3(.{ hit.p[0] - prev_p[0], hit.p[1] - prev_p[1], hit.p[2] - prev_p[2] }));
            out.max_sep = @max(out.max_sep, sep);
            const unbent = turn3(hit.n, prev_n);
            const bent = turn3(b.normal, pv.normal);
            // The bump may add its own curvature over the separation.
            out.max_bent_excess = @max(out.max_bent_excess, bent - unbent - bumpCurvature() * sep);
            if (pv.chart != null and b.chart != null and pv.chart.?.who != b.chart.?.who) {
                out.flips += 1;
                out.at_flip_bent_vs_unbent = @max(out.at_flip_bent_vs_unbent, @max(turn3(b.normal, hit.n), turn3(pv.normal, prev_n)));
                out.at_flip_bare = @max(out.at_flip_bare, @max(b.bare, pv.bare));
                out.flip_sep = @max(out.flip_sep, sep);
            }
        }
        prev = b;
        prev_n = hit.n;
        prev_p = hit.p;
    }
    return out;
}

/// The bump's bounds from the noise's construction, lattice units in
/// the default domain: the largest slope (3A/λ an octave, smoothstep's
/// 1.5 on a span of 2A) over two tangents, and the largest change of
/// slope over a step (12A/λ² an octave).
fn bumpSlope() f32 {
    var s: f32 = 0;
    for (thresholds.BARK_OCTAVES_W, thresholds.BARK_AMPLITUDES_W) |l, a| s += 3 * a / l;
    return s * std.math.sqrt2;
}
fn bumpCurvature() f32 {
    var s: f32 = 0;
    for (thresholds.BARK_OCTAVES_W, thresholds.BARK_AMPLITUDES_W) |l, a| s += 12 * a / (l * l);
    return 2 * s;
}

test "G16 (a) the chart is continuous along a tube: s advances by the arc, θ by the roll, who changes only inside the collar's zone, and the grain's bent normal is continuous across the collar" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 40);
    defer w.deinit();
    const zone: f64 = thresholds.g12Zone(maxRadius(w.rings.items[1].items), channel.band(1));
    // The parent's normal is −z, so θ = 0 on the junction side (at the
    // wrap) and π on the far side. The chart is the capsule's foot, so
    // it is exact through the collar's zone as well as beyond it.
    const far = generator(&w, .{ 0, 0, 1 }, std.math.pi, .{ .mode = .chart }, zone);
    const near = generator(&w, .{ 0, 0, -1 }, 0, .{ .mode = .chart }, zone);
    std.debug.print("\nG16 (a): far side {d} probes, {d} parent pairs: |Δs − Δarc| ≤ {e:.2}, |Δθ + drift·Δarc| ≤ {e:.2}, |θ − chart| ≤ {e:.2}; junction side {d} probes, {d} pairs: {e:.2}, {e:.2}, {e:.2}; who flips {d}, child-owned {d}, outside the zone {d}; non-integer who {d}, segment {d}\n", .{ far.probes, far.pairs, far.max_ds, far.max_dtheta, far.max_theta_err, near.probes, near.pairs, near.max_ds, near.max_dtheta, near.max_theta_err, near.who_flips, near.child_owned, near.flips_outside, far.non_integer_who + near.non_integer_who, far.non_integer_seg + near.non_integer_seg });
    try testing.expect(far.pairs > 80 and near.pairs > 40);
    try testing.expect(far.max_ds <= thresholds.G16_CHART_TOL and near.max_ds <= thresholds.G16_CHART_TOL);
    try testing.expect(far.max_dtheta <= thresholds.G16_CHART_TOL and near.max_dtheta <= thresholds.G16_CHART_TOL);
    try testing.expect(far.max_theta_err <= thresholds.G16_CHART_TOL and near.max_theta_err <= thresholds.G16_CHART_TOL);
    try testing.expectEqual(@as(u64, 0), far.who_flips);
    try testing.expect(near.child_owned > 0);
    try testing.expectEqual(@as(u64, 0), near.flips_outside);
    try testing.expectEqual(@as(u64, 0), far.non_integer_who + near.non_integer_who + far.non_integer_seg + near.non_integer_seg);
    // The fan: from the void above the junction, across the crotch —
    // the parent's surface, the fillet, the child's upper side. In the
    // field's mode the frame turns with the fillet and nothing switches;
    // in the chart's, the grain goes bare where the fields cross.
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    const child = w.rings.items[1].items;
    const from = [3]f64{ c[0], c[1] + 18, c[2] - 5 };
    const field = fanAcross(&w, from, .{ 0, -1, 0 }, .{ 0, 0, 1 }, 50.0 * std.math.pi / 180.0, 201, 0.1, .{});
    const fan = fanAcross(&w, from, .{ 0, -1, 0 }, .{ 0, 0, 1 }, 50.0 * std.math.pi / 180.0, 201, 0.1, .{ .mode = .chart });
    const k: f32 = w.fronts.items[1].params.collar * child[1].envelope;
    const bare_tol: f32 = std.math.tanh(k * fan.flip_sep);
    std.debug.print("G16 (a) the fan, the field's frame: {d} hits, the bent normal's turn over the unbent's and the bump's own curvature {d:.3} rad at most, {d} provenance planes read; the chart's: {d} who flips, neighbours at most {d:.3} apart, excess {d:.3}; at the flip the grain is bare to {d:.3} against the fade's {d:.3}, the bent normal {d:.3} rad from the unbent\n", .{ field.hits, field.max_bent_excess, field.max_planes, fan.flips, fan.max_sep, fan.max_bent_excess, fan.at_flip_bare, bare_tol, fan.at_flip_bent_vs_unbent });
    try testing.expect(field.hits > 150 and fan.hits > 150);
    try testing.expect(field.max_bent_excess <= 1e-3);
    try testing.expectEqual(@as(u8, 0), field.max_planes);
    try testing.expect(fan.flips > 0);
    try testing.expect(fan.max_bent_excess <= 1e-3);
    try testing.expect(fan.at_flip_bare <= bare_tol);
}

test "G16 (a) mutations: who interpolated → a third front's id; the segment interpolated → a foot on no capsule" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 40);
    defer w.deinit();
    const zone: f64 = thresholds.g12Zone(maxRadius(w.rings.items[1].items), channel.band(1));
    const interp = generator(&w, .{ 0, 0, -1 }, 0, .{ .mode = .chart, .who_nearest = false }, zone);
    const seg = generator(&w, .{ 0, 0, 1 }, std.math.pi, .{ .mode = .chart, .segment_nearest = false }, zone);
    std.debug.print("\nG16 (a) mutations: who interpolated → {d} non-integer ids; the segment interpolated → {d} non-integer segments, |Δs − Δarc| up to {d:.3}\n", .{ interp.non_integer_who, seg.non_integer_seg, seg.max_ds });
    try testing.expect(interp.non_integer_who > 0);
    try testing.expect(seg.non_integer_seg > 0);
}

test "G16 (a) mutation: band 3 not faded at the collar → the grain's phase jumps where who changes" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 40);
    defer w.deinit();
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    const child = w.rings.items[1].items;
    const from = [3]f64{ c[0], c[1] + 18, c[2] - 5 };
    const fan = fanAcross(&w, from, .{ 0, -1, 0 }, .{ 0, 0, 1 }, 50.0 * std.math.pi / 180.0, 201, 0.1, .{ .mode = .chart, .bare_collar = false });
    const k: f32 = w.fronts.items[1].params.collar * child[1].envelope;
    const bare_tol: f32 = std.math.tanh(k * fan.flip_sep);
    std.debug.print("\nG16 (a) mutation, no fade at the collar: {d} flips; at the flip the grain is bare to {d:.3} against the fade's {d:.3}, the bent normal {d:.3} rad from the unbent\n", .{ fan.flips, fan.at_flip_bare, bare_tol, fan.at_flip_bent_vs_unbent });
    try testing.expect(fan.flips > 0);
    try testing.expect(fan.at_flip_bare > bare_tol);
}

test "G16 (b) the footprint: bands fade over an octave, bytes fall monotonically, a sponge is 256 at every footprint, band 1 is continuous in footprint, and the read touches what was predicted" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 40);
    defer w.deinit();
    const snap = w.published();
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    // A hit on the parent's far side with real bark under it.
    var hit: ?struct { p: [3]f64, n: [3]f32 } = null;
    var y: f64 = c[1] + 4;
    while (y < c[1] + 30) : (y += 0.5) {
        const h = surfaceHit(snap, .{ c[0], y, c[2] }, .{ 0, 0, 1 }, 12) orelse continue;
        const b = bark.read(&w, snap, h.p, h.n, 0.1, .bark, .{ .mode = .chart });
        if (b.chart != null and @abs(b.band1) > 0.05) {
            hit = .{ .p = h.p, .n = h.n };
            break;
        }
    }
    const h = hit.?;
    var prev_bytes: u64 = std.math.maxInt(u64);
    var prev_band1: ?f32 = null;
    var prev_raw1: f32 = 0;
    var max_jump_over_bound: f32 = 0;
    var f: f32 = 0.05;
    const df: f32 = 0.01;
    const scale1 = thresholds.band1Scale(w.fronts.items[0].params.radius);
    while (f <= 2.0) : (f += df) {
        const b = bark.read(&w, snap, h.p, h.n, f, .bark, .{ .mode = .chart });
        const sp = bark.read(&w, snap, h.p, h.n, f, .sponge, .{});
        try testing.expectEqual(thresholds.G12_SPONGE_BYTES, sp.bytes);
        try testing.expect(b.bytes <= prev_bytes);
        prev_bytes = b.bytes;
        // Fetched exactly what has weight: records iff band 1 or 2 has weight.
        try testing.expectEqual(b.w1 > 0 or b.w2 > 0, b.records > 0);
        if (prev_band1) |pb| {
            // The fade's own slope: |d(w·v)/df| = |v|·scale/f², v the
            // residual under the fade (read on whichever side still reads it).
            const v: f32 = @max(@abs(b.raw1), @abs(prev_raw1));
            const bound = v * scale1 / ((f - df) * (f - df)) * df + 1e-5;
            max_jump_over_bound = @max(max_jump_over_bound, @abs(b.band1 - pb) - bound);
        }
        prev_band1 = b.band1;
        prev_raw1 = b.raw1;
    }
    // The prediction, frozen before the run, in both modes.
    var agree = true;
    std.debug.print("\nG16 (b): band 1's scale here {d:.3}; the read against the prediction —", .{scale1});
    for (thresholds.G16_PREDICTED) |row| {
        const b = bark.read(&w, snap, h.p, h.n, row.footprint, .bark, .{ .mode = .chart });
        const fb = bark.read(&w, snap, h.p, h.n, row.footprint, .bark, .{});
        const ok = b.planes == row.chart_planes and (b.records > 0) == row.chart_table and fb.planes == row.field_planes and fb.records == 0;
        if (!ok) agree = false;
        std.debug.print(" f {d:.1}: chart {d} planes, {s}; field {d} planes ({s});", .{ row.footprint, b.planes, if (b.records > 0) "the table" else "no table", fb.planes, if (ok) "as predicted" else "NOT as predicted" });
    }
    std.debug.print("\nG16 (b): bytes monotone; band 1's largest jump over the fade's bound {e:.2}\n", .{max_jump_over_bound});
    try testing.expect(max_jump_over_bound <= 0);
    try testing.expect(agree);
}

test "G16 (b) mutations: the footprint ignored → every read pays for everything; the hard cut → band 1 jumps by its whole value" {
    const gpa = testing.allocator;
    var w = try junctionRun(gpa, null, .recent, 40);
    defer w.deinit();
    const snap = w.published();
    const c = seedbed.sceneToLattice(.{ 0, 0, 0 });
    var hit: ?struct { p: [3]f64, n: [3]f32 } = null;
    var y: f64 = c[1] + 4;
    while (y < c[1] + 30) : (y += 0.5) {
        const h = surfaceHit(snap, .{ c[0], y, c[2] }, .{ 0, 0, 1 }, 12) orelse continue;
        const b = bark.read(&w, snap, h.p, h.n, 0.1, .bark, .{ .mode = .chart });
        if (b.chart != null and @abs(b.band1) > 0.05) {
            hit = .{ .p = h.p, .n = h.n };
            break;
        }
    }
    const h = hit.?;
    const far = bark.read(&w, snap, h.p, h.n, 1.5, .bark, .{ .mode = .chart, .footprint = false });
    const near = bark.read(&w, snap, h.p, h.n, 0.1, .bark, .{ .mode = .chart });
    const scale1 = thresholds.band1Scale(w.fronts.items[0].params.radius);
    const before = bark.read(&w, snap, h.p, h.n, scale1 - 0.005, .bark, .{ .mode = .chart, .fade = false });
    const after = bark.read(&w, snap, h.p, h.n, scale1 + 0.005, .bark, .{ .mode = .chart, .fade = false });
    std.debug.print("\nG16 (b) mutations: the footprint ignored at 1.5 pays {d} bytes, the honoured read at 0.1 {d}; the hard cut: band 1 {d:.3} then {d:.3} across the scale\n", .{ far.bytes, near.bytes, before.band1, after.band1 });
    try testing.expectEqual(near.bytes, far.bytes);
    try testing.expect(@abs(before.band1 - after.band1) > 0.05);
}
