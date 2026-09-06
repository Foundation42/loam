//! seedbed — the authoring verbs (brief P1.7). Loam's tiltyard.
//!
//! Place a seed, a light, a wall of damage; dump slices; count what a ray
//! visits. These are the SAME verbs a real scene uses — a range-only
//! mechanism is a smell — and they are the whole surface the C door
//! (`capi.zig`) and `loam-run` expose. Everything here goes through the
//! world's update buffer and `apply`, so authored state commits the way
//! evolved state does: seams reconciled, summaries rebuilt, a new vid.
//!
//! Units at this door are WORLD units; everything below it is lattice.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");
const front = @import("front.zig");
const world_mod = @import("world.zig");
const operators = @import("operators.zig");
const ray = @import("ray.zig");
const update = @import("update.zig");

const World = world_mod.World;
const Key = lattice.Key;
const Brick = brick.Brick;
const Channel = channel.Channel;

/// Deposit the engine's cast kernel — k(d) = A·(1 − (d/r)²)², C¹, compact —
/// into `bit` around a world point, on bricks at `gauge`, materialising
/// what the sphere covers. Queued; `world.apply()` commits.
pub fn blob(w: *World, bit: u6, centre_world: [3]f64, radius_world: f64, amplitude: f32, gauge: u5) !void {
    const c = w.domain.toLattice(centre_world);
    const r = w.domain.lengthToLattice(radius_world);
    try blobLattice(w, bit, c, r, amplitude, gauge);
}

pub fn blobLattice(w: *World, bit: u6, c: [3]f64, r: f64, amplitude: f32, gauge: u5) !void {
    const level: u5 = gauge + lattice.BRICK_LOG2;
    const side: i64 = @as(i64, 1) << level;
    var lo: [3]i64 = undefined;
    var hi: [3]i64 = undefined;
    inline for (0..3) |a| {
        lo[a] = @max(@as(i64, 0), tree.floorI(c[a] - r));
        hi[a] = @min(@as(i64, lattice.CELLS), tree.floorI(c[a] + r) + 1);
    }
    // Cubes already held by bricks of another gauge get the blob at that
    // gauge; a partly filled cube is completed at the finer gauge. The
    // tree refuses overlap, so this is what makes mixed gauges authorable.
    var keys = std.AutoArrayHashMapUnmanaged(u64, void){};
    defer keys.deinit(w.gpa);
    var cover = std.ArrayListUnmanaged(Key){};
    defer cover.deinit(w.gpa);
    var z = lo[2] - @mod(lo[2], side);
    while (z < hi[2]) : (z += side) {
        var y = lo[1] - @mod(lo[1], side);
        while (y < hi[1]) : (y += side) {
            var x = lo[0] - @mod(lo[0], side);
            while (x < hi[0]) : (x += side) {
                cover.clearRetainingCapacity();
                try w.published().coverCube(Key.ofBrick(gauge, .{ @intCast(x), @intCast(y), @intCast(z) }), w.gpa, &cover);
                for (cover.items) |ck| try keys.put(w.gpa, ck.raw(), {});
            }
        }
    }
    for (keys.keys()) |raw| {
        const key = Key.fromRaw(raw);
        {
            {
                const ru = try w.author(key);
                const o = key.origin();
                const sp: i64 = key.spacing();
                var any = false;
                var k: u32 = 0;
                while (k < brick.N) : (k += 1) {
                    var j: u32 = 0;
                    while (j < brick.N) : (j += 1) {
                        var i: u32 = 0;
                        while (i < brick.N) : (i += 1) {
                            const p = [3]f64{
                                @floatFromInt(@as(i64, o[0]) + @as(i64, i) * sp),
                                @floatFromInt(@as(i64, o[1]) + @as(i64, j) * sp),
                                @floatFromInt(@as(i64, o[2]) + @as(i64, k) * sp),
                            };
                            const dx = p[0] - c[0];
                            const dy = p[1] - c[1];
                            const dz = p[2] - c[2];
                            const d2 = dx * dx + dy * dy + dz * dz;
                            if (d2 >= r * r) continue;
                            const q = 1 - d2 / (r * r);
                            const v: f32 = amplitude * @as(f32, @floatCast(q * q));
                            const idx = Brick.index(i, j, k);
                            try ru.add(w.buffer.arena.allocator(), bit, idx, v);
                            any = true;
                        }
                    }
                }
                if (!any and ru.mask == 0) ru.materialise = false;
            }
        }
    }
}

/// Spawn a front at a world position with a heading. Queued; `apply` or
/// the next step assigns its id.
pub fn plant(w: *World, pos_world: [3]f64, dir: [3]f64, params: front.Params) !void {
    const d = world_mod.normalize(dir);
    const t: [3]f64 = if (@abs(d[0]) < 0.9) .{ 1, 0, 0 } else .{ 0, 1, 0 };
    const n = world_mod.normalize(world_mod.cross(d, t));
    try w.spawnFront(.{ .pos = w.domain.toLattice(pos_world), .dir = d, .normal = n, .params = params });
}

/// A wall of damage: inside the world box, Material goes to zero and
/// Damage to one. Queued; `apply` commits.
pub fn damage(w: *World, lo_world: [3]f64, hi_world: [3]f64) !void {
    const lo = w.domain.toLattice(lo_world);
    const hi = w.domain.toLattice(hi_world);
    const snap = w.published();
    const bs = try snap.bricks(w.gpa);
    defer w.gpa.free(bs);
    for (bs) |b| {
        const o = b.origin();
        const side: f64 = @floatFromInt(b.key.side());
        var overlaps = true;
        inline for (0..3) |a| {
            const bl: f64 = @floatFromInt(o[a]);
            if (bl + side < lo[a] or bl > hi[a]) overlaps = false;
        }
        if (!overlaps) continue;
        const ru = try w.author(b.key);
        const alloc = w.buffer.arena.allocator();
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const p = b.pointAt(i, j, k);
                    var inside = true;
                    inline for (0..3) |a| {
                        const pa: f64 = @floatFromInt(p[a]);
                        if (pa < lo[a] or pa > hi[a]) inside = false;
                    }
                    if (!inside) continue;
                    const idx = Brick.index(i, j, k);
                    const m = b.get(Channel.material.bit(), i, j, k);
                    if (m != 0) try ru.add(alloc, Channel.material.bit(), idx, -m);
                    const dmg = b.get(Channel.damage.bit(), i, j, k);
                    try ru.add(alloc, Channel.damage.bit(), idx, 1 - dmg);
                }
            }
        }
    }
}

/// End the season: a channel goes to zero everywhere it exists. Queued;
/// `apply` commits. G4's precondition — dormancy by exhaustion — is this
/// applied to Growth.
pub fn clearChannel(w: *World, bit: u6) !void {
    const snap = w.published();
    const bs = try snap.bricks(w.gpa);
    defer w.gpa.free(bs);
    for (bs) |b| {
        const pl = b.plane(bit) orelse continue;
        const ru = try w.author(b.key);
        const alloc = w.buffer.arena.allocator();
        for (pl, 0..) |v, idx| {
            if (v != 0) try ru.add(alloc, bit, idx, -v);
        }
    }
}

/// Sample a channel on a world-space slice: `axis` fixed at `coord`, the
/// other two axes spanning [lo, hi] at `res` samples each. Row-major,
/// the first free axis fastest. Caller owns the slice.
pub fn slice(w: *const World, gpa: std.mem.Allocator, bit: u6, axis: u2, coord: f64, lo: [2]f64, hi: [2]f64, res: u32) ![]f32 {
    const out = try gpa.alloc(f32, @as(usize, res) * res);
    const snap = w.published();
    const free: [2]u2 = switch (axis) {
        0 => .{ 1, 2 },
        1 => .{ 0, 2 },
        else => .{ 0, 1 },
    };
    var v: u32 = 0;
    while (v < res) : (v += 1) {
        var u: u32 = 0;
        while (u < res) : (u += 1) {
            var p: [3]f64 = undefined;
            p[axis] = coord;
            p[free[0]] = lo[0] + (hi[0] - lo[0]) * (@as(f64, @floatFromInt(u)) + 0.5) / @as(f64, @floatFromInt(res));
            p[free[1]] = lo[1] + (hi[1] - lo[1]) * (@as(f64, @floatFromInt(v)) + 0.5) / @as(f64, @floatFromInt(res));
            out[@as(usize, v) * res + u] = snap.sample(bit, w.domain.toLattice(p));
        }
    }
    return out;
}

/// Max-projection of a channel along `axis` over the world box: the
/// slice's honest sibling for a thin structure, which a single plane
/// mostly misses. Row-major like `slice`.
pub fn project(w: *const World, gpa: std.mem.Allocator, bit: u6, axis: u2, lo: [3]f64, hi: [3]f64, res: u32, depth: u32) ![]f32 {
    const out = try gpa.alloc(f32, @as(usize, res) * res);
    @memset(out, 0);
    const snap = w.published();
    const free: [2]u2 = switch (axis) {
        0 => .{ 1, 2 },
        1 => .{ 0, 2 },
        else => .{ 0, 1 },
    };
    var v: u32 = 0;
    while (v < res) : (v += 1) {
        var u: u32 = 0;
        while (u < res) : (u += 1) {
            var p: [3]f64 = undefined;
            p[free[0]] = lo[free[0]] + (hi[free[0]] - lo[free[0]]) * (@as(f64, @floatFromInt(u)) + 0.5) / @as(f64, @floatFromInt(res));
            p[free[1]] = lo[free[1]] + (hi[free[1]] - lo[free[1]]) * (@as(f64, @floatFromInt(v)) + 0.5) / @as(f64, @floatFromInt(res));
            var m: f32 = 0;
            var d: u32 = 0;
            while (d < depth) : (d += 1) {
                p[axis] = lo[axis] + (hi[axis] - lo[axis]) * (@as(f64, @floatFromInt(d)) + 0.5) / @as(f64, @floatFromInt(depth));
                m = @max(m, snap.sample(bit, w.domain.toLattice(p)));
            }
            out[@as(usize, v) * res + u] = m;
        }
    }
    return out;
}

/// Connected components (6-connectivity in the plane) of `values > threshold`
/// on a res×res field. The G2 instrument.
pub fn components(gpa: std.mem.Allocator, values: []const f32, res: u32, threshold: f32) !usize {
    const n = @as(usize, res) * res;
    const seen = try gpa.alloc(bool, n);
    defer gpa.free(seen);
    @memset(seen, false);
    var stack = std.ArrayListUnmanaged(usize){};
    defer stack.deinit(gpa);
    var count: usize = 0;
    for (0..n) |start| {
        if (seen[start] or values[start] <= threshold) continue;
        count += 1;
        try stack.append(gpa, start);
        seen[start] = true;
        while (stack.pop()) |idx| {
            const u = idx % res;
            const v = idx / res;
            const nbrs = [4][2]i64{ .{ @as(i64, @intCast(u)) - 1, @intCast(v) }, .{ @as(i64, @intCast(u)) + 1, @intCast(v) }, .{ @intCast(u), @as(i64, @intCast(v)) - 1 }, .{ @intCast(u), @as(i64, @intCast(v)) + 1 } };
            for (nbrs) |q| {
                if (q[0] < 0 or q[1] < 0 or q[0] >= res or q[1] >= res) continue;
                const j = @as(usize, @intCast(q[1])) * res + @as(usize, @intCast(q[0]));
                if (seen[j] or values[j] <= threshold) continue;
                seen[j] = true;
                try stack.append(gpa, j);
            }
        }
    }
    return count;
}

/// Write a slice as an 8-bit PGM, values scaled by `scale` and clamped.
pub fn writePgm(path: []const u8, res: u32, values: []const f32, scale: f32) !void {
    var f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var bw = std.io.bufferedWriter(f.writer());
    const wr = bw.writer();
    try wr.print("P5\n{d} {d}\n255\n", .{ res, res });
    // Top row first: v runs bottom-up in `slice`, so flip.
    var v: u32 = res;
    while (v > 0) : (v -= 1) {
        const row = values[@as(usize, v - 1) * res ..][0..res];
        for (row) |x| {
            const s = @min(255.0, @max(0.0, x * scale * 255.0));
            try wr.writeByte(@intFromFloat(s));
        }
    }
    try bw.flush();
}

pub const RayCount = struct { sampled: u64, crossed: u64, nodes_tested: u64 };

/// What a ray visits with summaries against what it crosses without —
/// G6's numerator and denominator.
pub fn rayCount(w: *const World, origin_world: [3]f64, dir: [3]f64, channels: channel.Mask, class: ray.QueryClass) !RayCount {
    const snap = w.published();
    const o = w.domain.toLattice(origin_world);
    const d = world_mod.normalize(dir);
    var with = try ray.Cursor.init(w.gpa, snap, .{ .origin = o, .dir = d, .channels = channels, .class = class });
    defer with.deinit();
    var sampled: u64 = 0;
    while (try with.next()) |_| sampled += 1;
    var without = try ray.Cursor.init(w.gpa, snap, .{ .origin = o, .dir = d, .channels = channels, .class = class, .use_summaries = false });
    defer without.deinit();
    var crossed: u64 = 0;
    while (try without.next()) |_| crossed += 1;
    return .{ .sampled = sampled, .crossed = crossed, .nodes_tested = with.stats.nodes_tested };
}

/// Total of a channel over every sample of every brick — the mass a
/// closed-form check compares. Sums brick planes, so shared face samples
/// count once per holder; use for RATIOS across time, or on scenes with
/// one gauge where the double count is a constant factor of the layout.
pub fn total(w: *const World, bit: u6) f64 {
    const Ctx = struct { bit: u6, sum: f64 = 0 };
    var ctx = Ctx{ .bit = bit };
    w.published().forEachBrick(&ctx, struct {
        fn f(c: *Ctx, b: *const Brick) void {
            if (b.plane(c.bit)) |pl| {
                for (pl) |v| c.sum += v;
            }
        }
    }.f);
    return ctx.sum;
}

/// Centroid of a channel's mass, lattice units, and the mass.
pub fn centroid(w: *const World, bit: u6) struct { c: [3]f64, mass: f64 } {
    const Ctx = struct { bit: u6, sum: f64 = 0, m: [3]f64 = .{ 0, 0, 0 } };
    var ctx = Ctx{ .bit = bit };
    w.published().forEachBrick(&ctx, struct {
        fn f(c: *Ctx, b: *const Brick) void {
            const pl = b.plane(c.bit) orelse return;
            var k: u32 = 0;
            while (k < brick.N) : (k += 1) {
                var j: u32 = 0;
                while (j < brick.N) : (j += 1) {
                    var i: u32 = 0;
                    while (i < brick.N) : (i += 1) {
                        const v: f64 = pl[Brick.index(i, j, k)];
                        if (v == 0) continue;
                        const p = b.pointAt(i, j, k);
                        c.sum += v;
                        c.m[0] += v * @as(f64, @floatFromInt(p[0]));
                        c.m[1] += v * @as(f64, @floatFromInt(p[1]));
                        c.m[2] += v * @as(f64, @floatFromInt(p[2]));
                    }
                }
            }
        }
    }.f);
    if (ctx.sum == 0) return .{ .c = .{ 0, 0, 0 }, .mass = 0 };
    return .{ .c = .{ ctx.m[0] / ctx.sum, ctx.m[1] / ctx.sum, ctx.m[2] / ctx.sum }, .mass = ctx.sum };
}

/// Named scenes. The same handful the gates use, so `loam-run --scene`
/// shows exactly what a gate saw.
pub const Preset = enum { sapling, blob, seams, diffusion, wound };

pub const Scene = struct {
    /// Operators the scene mounted; the world holds pointers into here,
    /// so a Scene must not move after `build`.
    diffusion: [4]operators.Diffusion = undefined,
    decay: [4]operators.Decay = undefined,
    advection: operators.Advection = undefined,
    healing: operators.Healing = .{},
    light: [3]f64 = .{ 40, 60, 0 },
    stimulus: ?[3]f64 = null,
    tropism_light: f32 = 0.6,
    tropism_stimulus: f32 = 0.0,
    deposit: f32 = 1.0,
    heal: bool = true,

    pub fn build(self: *Scene, w: *World, preset: Preset) !void {
        switch (preset) {
            .blob => {
                // A hand-placed density blob in a world of light-only
                // bricks: G6's empty-majority scene.
                try blob(w, Channel.light.bit(), .{ 0, 0, 0 }, 64, 1.0, 0);
                try blob(w, Channel.density.bit(), .{ 20, 0, 0 }, 6, 1.0, 0);
                try w.apply();
            },
            .seams => {
                // Two gauges sharing a face: the P1.2 gate's scene. The
                // fine blob first, applied, so the coarse one completes
                // the cubes it shares at the fine gauge.
                try blob(w, Channel.light.bit(), .{ -12, 0, 0 }, 20, 1.0, 0);
                try w.apply();
                try blob(w, Channel.light.bit(), .{ 20, 0, 0 }, 20, 1.0, 1);
                try w.apply();
            },
            .diffusion => {
                try blob(w, Channel.growth.bit(), .{ 0, 0, 0 }, 3, 1.0, 0);
                try w.apply();
                self.diffusion[0] = .{ .bit = Channel.growth.bit(), .rate = 0.15 };
                try w.addOperator(operators.operatorOf(operators.Diffusion, &self.diffusion[0]));
                self.decay[0] = .{ .bit = Channel.growth.bit(), .tau = 20 };
                try w.addOperator(operators.operatorOf(operators.Decay, &self.decay[0]));
            },
            .sapling, .wound => {
                try blob(w, Channel.growth.bit(), .{ 0, 24, 0 }, 56, 1.0, 0);
                try blob(w, Channel.light.bit(), self.light, 64, 1.0, 0);
                if (self.stimulus) |s| try blob(w, Channel.stimulus.bit(), s, 64, 1.0, 0);
                var params = front.Params{};
                params.tropism_light = self.tropism_light;
                params.tropism_stimulus = self.tropism_stimulus;
                params.deposit = self.deposit;
                params.length = 72;
                try plant(w, .{ 0, 0, 0 }, .{ 0, 1, 0 }, params);
                try w.apply();
                self.decay[0] = .{ .bit = Channel.activity.bit(), .tau = 3 };
                try w.addOperator(operators.operatorOf(operators.Decay, &self.decay[0]));
                if (self.heal) {
                    self.healing = .{};
                    self.healing.params = params;
                    self.healing.params.length = 12;
                    self.healing.params.radius = 2;
                    self.healing.params.wander = 0.05;
                    self.healing.params.min_age = 1000; // repair does not branch
                    try w.addOperator(operators.operatorOf(operators.Healing, &self.healing));
                }
            },
        }
    }
};
