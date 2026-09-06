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

/// Channel bytes a query gathers: eight samples of four bytes per plane
/// touched, for each requested channel the brick holds. The narrow
/// query's instrument — the mutation (ignore the mask) makes this equal.
fn gatherBytes(snap: *const loam.Snapshot, channels: channel.Mask) !u64 {
    var cur = try ray.Cursor.init(testing.allocator, snap, .{ .origin = .{ 524288 - 40, 524288, 524288 }, .dir = .{ 1, 0, 0 }, .channels = channels });
    defer cur.deinit();
    var bytes: u64 = 0;
    while (try cur.next()) |rv| {
        var t = rv.t_enter;
        while (t <= rv.t_exit) : (t += 1) {
            bytes += 8 * 4 * @as(u64, @popCount(rv.brick.mask & channels));
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
    try seedbed.blob(&w, Channel.activity.bit(), .{ 0, 0, 0 }, 5, 1.0, 0);
    try w.apply();
    var d = operators.Decay{ .bit = Channel.activity.bit(), .tau = 4.0 };
    try w.addOperator(operators.operatorOf(operators.Decay, &d));
    const p = w.domain.toLattice(.{ 0, 0, 0 });
    const v0 = w.published().sample(Channel.activity.bit(), p);
    try w.step(now(0), null);
    try w.step(.{ .frame = 1, .time_ns = 3 * std.time.ns_per_s }, null);
    try w.step(.{ .frame = 2, .time_ns = 10 * std.time.ns_per_s }, null);
    const v = w.published().sample(Channel.activity.bit(), p);
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
    var a: GrownWorld = undefined;
    try a.growWounded(gpa, 7, 40, null);
    defer a.deinit();
    var js = try jobs.JobSystem.init(gpa, 4);
    defer js.deinit();
    var b: GrownWorld = undefined;
    try b.growWounded(gpa, 7, 40, js);
    defer b.deinit();
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

/// The G2 run: the sapling for G2_STEPS, sampling the young-material
/// component count at every checkpoint, since tips are live in the middle
/// of the run and dormant by its end.
const G2Run = struct { max_young: usize = 0, material_half: f64 = 0, material_full: f64 = 0, branches: usize = 0 };

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
            r.max_young = @max(r.max_young, try seedbed.youngComponents(&w, gpa, 0.3, thresholds.G2_YOUNG_WINDOW_S));
        }
        if (i == thresholds.G2_STEPS / 2) r.material_half = seedbed.total(&w, Channel.material.bit());
    }
    r.material_full = seedbed.total(&w, Channel.material.bit());
    r.branches = w.published().fronts.len - 1;
    try guards.check(w.published());
    return r;
}

test "G2: a seeded front produces persistent, branching, deposited structure with no mesh" {
    const gpa = testing.allocator;
    const r = try g2Run(gpa, .{});
    std.debug.print("\nG2: material {d:.1} at N/2 → {d:.1} at N, {d} branches, {d} young-material components at peak\n", .{ r.material_half, r.material_full, r.branches, r.max_young });
    try testing.expect(r.material_full > 0 and r.material_full >= r.material_half); // persistent: no reset
    try testing.expect(r.branches >= thresholds.G2_MIN_BRANCHES); // the mechanism fired
    try testing.expect(r.max_young >= thresholds.G2_MIN_YOUNG_COMPONENTS); // and the FIELD shows it
}

test "G2 mutation: branching off → one component of young material while material still grows" {
    const gpa = testing.allocator;
    const r = try g2Run(gpa, .{ .max_generation = 0 });
    std.debug.print("\nG2 mutation: material {d:.1}, {d} branches, {d} young-material components at peak\n", .{ r.material_full, r.branches, r.max_young });
    try testing.expect(r.material_full > 0);
    try testing.expectEqual(@as(usize, 0), r.branches);
    try testing.expectEqual(@as(usize, 1), r.max_young);
}

test "G2 mutation: zero deposit rate → no material" {
    const gpa = testing.allocator;
    const r = try g2Run(gpa, .{ .deposit = 0 });
    try testing.expectEqual(@as(f64, 0), r.material_full);
    try testing.expectEqual(@as(usize, 0), r.max_young);
}

/// Centroid of live front positions, lattice units.
fn frontCentroid(snap: *const loam.Snapshot) [3]f64 {
    var c = [3]f64{ 0, 0, 0 };
    var n: f64 = 0;
    for (snap.fronts) |f| {
        if (!f.alive) continue;
        inline for (0..3) |a| c[a] += f.pos[a];
        n += 1;
    }
    if (n == 0) return c;
    inline for (0..3) |a| c[a] /= n;
    return c;
}

/// The stimulus coefficient the G3 scene uses. Spec §11's term is
/// a·∇stimulus and the blob's gradient over a radius of 64 is of order
/// 0.02 per lattice unit, so at a = 1.5 the term was several times
/// weaker per step than the wander noise — under the null floor, as the
/// review predicted. At 30 it is of order the persistence term.
const G3_COEFF: f32 = 30;

/// Centroid of the MATERIAL laid over the run — the field, not the
/// live tips, whose centroid is a noisy statistic once tips go dormant.
fn tropismRun(gpa: std.mem.Allocator, seed: u64, stimulus_x: ?f64, coeff: f32) ![3]f64 {
    var w = try World.init(gpa, .{ .seed = seed });
    defer w.deinit();
    var scene = seedbed.Scene{ .stimulus = if (stimulus_x) |x| .{ x, 40, 0 } else null, .tropism_light = 0, .tropism_stimulus = coeff };
    try scene.build(&w, .sapling);
    try run(&w, thresholds.G3_STEPS, null);
    return seedbed.centroid(&w, Channel.material.bit()).c;
}

/// The null: no stimulus, wander alone, across seeds — the RMS of the
/// material centroid's x about the seed axis. What noise does on its own.
fn nullSpread(gpa: std.mem.Allocator) !f64 {
    const axis_x: f64 = @as(f64, lattice.CELLS / 2);
    var sum2: f64 = 0;
    var seed: u64 = 1;
    while (seed <= thresholds.G3_NULL_SEEDS) : (seed += 1) {
        const c = try tropismRun(gpa, seed, null, 0);
        const dx = c[0] - axis_x;
        sum2 += dx * dx;
    }
    return @sqrt(sum2 / @as(f64, @floatFromInt(thresholds.G3_NULL_SEEDS)));
}

test "G3: moving a stimulus field redirects live fronts, beyond k× the null spread" {
    const gpa = testing.allocator;
    const spread = try nullSpread(gpa);
    const floor = thresholds.G3_NULL_K * spread;
    const plus = try tropismRun(gpa, 7, 40, G3_COEFF);
    const minus = try tropismRun(gpa, 7, -40, G3_COEFF);
    const drift = plus[0] - minus[0];
    std.debug.print("\nG3: null spread {d:.2} over {d} seeds, floor {d:.2} (k = {d}); drift {d:.2} between stimulus at +40 and −40\n", .{ spread, thresholds.G3_NULL_SEEDS, floor, thresholds.G3_NULL_K, drift });
    try testing.expect(spread > 0); // the null varied: wander is on
    try testing.expect(drift >= floor);
}

test "G3 mutation: stimulus gradient term zeroed → no drift" {
    const gpa = testing.allocator;
    const plus = try tropismRun(gpa, 7, 40, 0);
    const minus = try tropismRun(gpa, 7, -40, 0);
    try testing.expectEqual(plus[0], minus[0]); // nobody read the field: bit-identical
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

fn materialInBox(w: *const World, lo: [3]f64, hi: [3]f64) f64 {
    var sum: f64 = 0;
    const snap = w.published();
    var y = lo[1];
    while (y <= hi[1]) : (y += 1) {
        var z = lo[2];
        while (z <= hi[2]) : (z += 1) {
            var x = lo[0];
            while (x <= hi[0]) : (x += 1) {
                sum += snap.sample(Channel.material.bit(), w.domain.toLattice(.{ x, y, z }));
            }
        }
    }
    return sum;
}

test "G4: removing material re-activates evolution locally only" {
    const gpa = testing.allocator;
    var g: GrownWorld = undefined;
    const before = try woundRun(gpa, &g, true);
    defer before.release();
    defer g.deinit();
    const box = DamageBox{};
    const regrown = materialInBox(&g.world, box.lo, box.hi);
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
    std.debug.print("\nG4: {d} bricks touched by the repair, {d} outside dilate(box, {d}); material regrown in box {d:.1}; {d} fronts\n", .{ touched, outside, thresholds.G4_DILATE_BRICKS, regrown, after.fronts.len });
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
    try testing.expectEqual(@as(f64, 0), materialInBox(&g.world, box.lo, box.hi));
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

    // 2. An absent channel instantiated (an all-zero plane).
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    const victim: *Brick = @constCast(bs[0]);
    _ = try victim.ensurePlane(gpa, Channel.roughness.bit());
    try testing.expectError(guards.Violation.AbsentChannelAllocated, guards.check(snap));
    victim.finalize(gpa); // drops the zero plane
    try guards.check(snap);

    // 3. A stale leaf summary: a sample edited without finalize.
    var edited: ?*Brick = null;
    var edited_idx: usize = 0;
    var edited_old: f32 = 0;
    for (bs) |b| {
        const pl = b.plane(Channel.light.bit()) orelse continue;
        var idx: usize = 0;
        while (idx < brick.SAMPLES) : (idx += 1) {
            const ijk = Brick.unindex(idx);
            if (Brick.isBoundary(ijk[0], ijk[1], ijk[2]) and pl[idx] > 0.1) {
                edited = @constCast(b);
                edited_idx = idx;
                edited_old = pl[idx];
                break;
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
    try testing.expect(std.mem.indexOf(u8, da, "material") != null);
}
