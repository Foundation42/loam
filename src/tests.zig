//! The gates. Each names the mutation that must bite (brief §2): a gate
//! that passes under its mutation is a finding about the gate, not a
//! pass. Executable mutations are tests of their own; hand mutations are
//! recorded in the ledger (`docs/implementation-notes.md`) with what they
//! produced. Thresholds live in `thresholds.zig`, PROPOSED until struck.

const std = @import("std");
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
    std.debug.print("\nG5: {d} evals over 80 steps for {d} bricks (all-regions would be {d}); {d:.1} ms total, Debug, serial\n", .{ g.world.total.region_evals, bricks, worst, ms });
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

/// 0 hosts a live front, 1 was carried by the last step, 2 the rest.
fn tierOf(snap: *const loam.Snapshot, k: loam.lattice.Key) u8 {
    if (hostsFront(snap, k)) return 0;
    for (snap.obliged) |o| if (o.eql(k)) return 1;
    return 2;
}

/// What a step must evaluate, from the snapshot's bookkeeping alone: the
/// obligations — the live fronts' bricks, then `obliged`, each in key
/// order — then the rest by attention at `now_ns` descending, ties by
/// key, cut at `budget` — the active set itself when it fits or there is
/// no budget — and how many of the tail carry (attentive above the
/// floor, or hosting a front).
fn attentionHead(gpa: std.mem.Allocator, snap: *const loam.Snapshot, now_ns: u64, budget: ?usize) !HeadAndTail {
    const K = loam.lattice.Key;
    const b = budget orelse snap.active.len;
    if (snap.active.len <= b) return .{ .head = try gpa.dupe(K, snap.active), .carried = 0 };
    const Scored = struct { key: K, a: f64, tier: u8 };
    const scored = try gpa.alloc(Scored, snap.active.len);
    defer gpa.free(scored);
    for (snap.active, 0..) |k, i| {
        const a: f64 = if (snap.brickAt(k)) |br| br.summary.attentionAt(now_ns, thresholds.ATTENTION_TAU_S) else 0;
        scored[i] = .{ .key = k, .a = a, .tier = tierOf(snap, k) };
    }
    std.mem.sort(Scored, scored, {}, struct {
        fn lt(_: void, x: Scored, y: Scored) bool {
            if (x.tier != y.tier) return x.tier < y.tier;
            if (x.tier == 2 and x.a != y.a) return x.a > y.a;
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
        // The carried bricks are the next snapshot's obligations, and the
        // budget the step ran under is on it.
        try testing.expectEqual(ht.carried, g.published().obliged.len);
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
    std.debug.print("G14 (a): ten steps at a budget of one brick: {d} live front-steps, none skipped, overrun {d} bricks; backlog {d} at the end, {d} consecutive steps over budget\n", .{ live, overrun, g.published().obliged.len, g.world.overload_steps });
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

const BudgetedRun = struct { inside: u64, carried: u64, faded: u64, skipped: u64, evals: u64 };

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
    return .{ .inside = seedbed.insideCount(&g.world), .carried = g.world.total.carried, .faded = g.world.total.faded, .skipped = g.world.total.fronts_skipped, .evals = g.world.total.region_evals };
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
