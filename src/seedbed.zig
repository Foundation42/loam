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
const fmath = @import("fmath.zig");

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
    // Entries serially (the buffer's map is not thread-safe); the fill in
    // parallel, each key its own entry, planes from the thread-safe
    // allocator. Order-free: G1's parallel run covers this path too.
    const rus = try w.gpa.alloc(*update.RegionUpdate, keys.count());
    defer w.gpa.free(rus);
    for (keys.keys(), 0..) |raw, i| rus[i] = try w.author(Key.fromRaw(raw));
    var ctx = BlobCtx{ .rus = rus, .alloc = w.buffer.planeAllocator(), .bit = bit, .c = c, .r = r, .amplitude = amplitude, .failed = std.atomic.Value(bool).init(false) };
    world_mod.World.parallelRangePub(w.jobs, rus.len, 4, BlobCtx, &ctx, blobFill);
    if (ctx.failed.load(.acquire)) return error.OutOfMemory;
}

const BlobCtx = struct {
    rus: []*update.RegionUpdate,
    alloc: std.mem.Allocator,
    bit: u6,
    c: [3]f64,
    r: f64,
    amplitude: f32,
    failed: std.atomic.Value(bool),
};

fn blobFill(ctx: *BlobCtx, i: usize) void {
    const ru = ctx.rus[i];
    const key = ru.key;
    const o = key.origin();
    const sp: i64 = key.spacing();
    var k: u32 = 0;
    while (k < brick.N) : (k += 1) {
        var j: u32 = 0;
        while (j < brick.N) : (j += 1) {
            var ii: u32 = 0;
            while (ii < brick.N) : (ii += 1) {
                const p = [3]f64{
                    @floatFromInt(@as(i64, o[0]) + @as(i64, ii) * sp),
                    @floatFromInt(@as(i64, o[1]) + @as(i64, j) * sp),
                    @floatFromInt(@as(i64, o[2]) + @as(i64, k) * sp),
                };
                const dx = p[0] - ctx.c[0];
                const dy = p[1] - ctx.c[1];
                const dz = p[2] - ctx.c[2];
                const d2 = dx * dx + dy * dy + dz * dz;
                if (d2 >= ctx.r * ctx.r) continue;
                const q = 1 - d2 / (ctx.r * ctx.r);
                const v: f32 = ctx.amplitude * @as(f32, @floatCast(q * q));
                ru.add(ctx.alloc, ctx.bit, Brick.index(ii, j, k), v) catch {
                    ctx.failed.store(true, .release);
                    return;
                };
            }
        }
    }
}

/// Author a straight capsule — the signed distance to the segment p0–p1
/// at radius r, lattice units — into the carrier as one surface op with
/// collar k, on bricks at `gauge` within the band of it. The G13
/// instrument's primitive, and G9–G11's scene. Queued; `apply` commits.
pub fn capsuleLattice(w: *World, p0: [3]f64, p1: [3]f64, r: f64, k: f32, gauge: u5) !void {
    const level: u5 = gauge + lattice.BRICK_LOG2;
    const side: i64 = @as(i64, 1) << level;
    const reach: f64 = r + channel.band(@as(u32, 1) << gauge);
    var lo: [3]i64 = undefined;
    var hi: [3]i64 = undefined;
    inline for (0..3) |a| {
        lo[a] = @max(@as(i64, 0), tree.floorI(@min(p0[a], p1[a]) - reach));
        hi[a] = @min(@as(i64, lattice.CELLS), tree.floorI(@max(p0[a], p1[a]) + reach) + 1);
    }
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
    const axis = [3]f64{ p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2] };
    const len2 = world_mod.dot(axis, axis);
    const order = w.buffer.next_order;
    w.buffer.next_order += 1;
    for (keys.keys()) |raw| {
        const key = Key.fromRaw(raw);
        const ru = try w.author(key);
        const alloc = w.buffer.arena.allocator();
        const band = channel.band(key.spacing());
        const o = key.origin();
        const sp: i64 = key.spacing();
        var op: ?*brick.Plane = null;
        var kk: u32 = 0;
        while (kk < brick.N) : (kk += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const q = [3]f64{
                        @floatFromInt(@as(i64, o[0]) + @as(i64, i) * sp),
                        @floatFromInt(@as(i64, o[1]) + @as(i64, j) * sp),
                        @floatFromInt(@as(i64, o[2]) + @as(i64, kk) * sp),
                    };
                    const d = [3]f64{ q[0] - p0[0], q[1] - p0[1], q[2] - p0[2] };
                    var s: f64 = 0;
                    if (len2 > 1e-18) s = @min(1.0, @max(0.0, world_mod.dot(d, axis) / len2));
                    const rad = [3]f64{ d[0] - s * axis[0], d[1] - s * axis[1], d[2] - s * axis[2] };
                    const phi: f32 = @floatCast(world_mod.len3(rad) - r);
                    if (phi >= band) continue;
                    if (op == null) op = try ru.surfaceOp(alloc, k, order);
                    op.?[Brick.index(i, j, kk)] = @max(phi, -band);
                }
            }
        }
    }
}

/// Spawn a front at a world position with a heading. Queued; `apply` or
/// the next step assigns its id.
pub fn plant(w: *World, pos_world: [3]f64, dir: [3]f64, params: front.Params) !void {
    try plantLattice(w, w.domain.toLattice(pos_world), dir, params);
}

pub fn plantLattice(w: *World, pos: [3]f64, dir: [3]f64, params: front.Params) !void {
    const d = world_mod.normalize(dir);
    const t: [3]f64 = if (@abs(d[0]) < 0.9) .{ 1, 0, 0 } else .{ 0, 1, 0 };
    const n = world_mod.normalize(world_mod.cross(d, t));
    try w.spawnFront(.{ .pos = pos, .dir = d, .normal = n, .params = params });
}

/// The scene frame: lattice units about the lattice's centre. A scene is
/// authored here whatever the domain — a host mounting loam at five
/// centimetres a unit gets the seedbed's tree, not one 1120 units across.
/// (The first mount authored through `toLattice` in metres and the growth
/// blob asked for tens of millions of bricks; the kernel's OOM killer was
/// the gate that fired.) In the default domain this is `toLattice` to
/// the bit, so the frozen reference does not move.
pub fn sceneToLattice(p: [3]f64) [3]f64 {
    const c: f64 = @floatFromInt(lattice.CELLS / 2);
    return .{ c + p[0], c + p[1], c + p[2] };
}

/// A wall of damage: the world box is CUT from the carrier — the CSG
/// difference with the box's own signed distance, so the wound's walls
/// are as continuous as the tissue was — Material goes to zero and
/// Damage to one inside it. Queued; `apply` commits.
pub fn damage(w: *World, lo_world: [3]f64, hi_world: [3]f64) !void {
    const lo = w.domain.toLattice(lo_world);
    const hi = w.domain.toLattice(hi_world);
    const snap = w.published();
    const bs = try snap.bricks(w.gpa);
    defer w.gpa.free(bs);
    const order = w.buffer.next_order;
    w.buffer.next_order += 1;
    for (bs) |b| {
        const o = b.origin();
        const side: f64 = @floatFromInt(b.key.side());
        const band = b.band();
        var overlaps = true;
        inline for (0..3) |a| {
            const bl: f64 = @floatFromInt(o[a]);
            if (bl + side < lo[a] - band or bl > hi[a] + band) overlaps = false;
        }
        if (!overlaps) continue;
        const ru = try w.author(b.key);
        const alloc = w.buffer.arena.allocator();
        var op: ?*brick.Plane = null;
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const p = b.pointAt(i, j, k);
                    const idx = Brick.index(i, j, k);
                    // Signed distance to the box: negative inside.
                    var inside = true;
                    var d_out: f64 = 0;
                    var d_in: f64 = std.math.inf(f64);
                    inline for (0..3) |a| {
                        const pa: f64 = @floatFromInt(p[a]);
                        const below = lo[a] - pa;
                        const above = pa - hi[a];
                        const outside = @max(below, above);
                        if (outside > 0) {
                            inside = false;
                            d_out += outside * outside;
                        } else {
                            d_in = @min(d_in, -outside);
                        }
                    }
                    const d_box: f32 = @floatCast(if (inside) -d_in else @sqrt(d_out));
                    if (b.has(Channel.surface.bit()) and d_box < band) {
                        // The cut only matters where tissue is: the op says
                        // nothing where the carrier is already far.
                        if (b.get(Channel.surface.bit(), i, j, k) < band) {
                            if (op == null) op = try ru.surfaceOpMode(alloc, 0, order, .cut);
                            op.?[idx] = d_box;
                        }
                    }
                    if (!inside) continue;
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
    std.debug.assert(bit != Channel.surface.bit()); // the carrier is cut, not zeroed
    for (bs) |b| {
        const pl = b.plane(bit) orelse continue;
        const ru = try w.author(b.key);
        const alloc = w.buffer.arena.allocator();
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const idx = Brick.index(i, j, k);
                    if (pl[idx] != 0) try ru.add(alloc, bit, idx, -pl[idx]);
                }
            }
        }
    }
}

/// Sample a channel on a world-space slice: `axis` fixed at `coord`, the
/// other two axes spanning [lo, hi] at `res` samples each. Row-major,
/// the first free axis fastest. Caller owns the slice.
pub fn slice(w: *const World, gpa: std.mem.Allocator, bit: u6, axis: u2, coord: f64, lo: [2]f64, hi: [2]f64, res: u32) ![]f32 {
    const out = try gpa.alloc(f32, @as(usize, res) * res);
    const snap = w.published();
    const free = freeAxes(axis);
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

/// The two axes a slice or projection spans, (horizontal, vertical),
/// chosen so a side view stands upright: along x → (z, y), along y →
/// (x, z), along z → (x, y). (The first cut laid the x view on its side.)
pub fn freeAxes(axis: u2) [2]u2 {
    return switch (axis) {
        0 => .{ 2, 1 },
        1 => .{ 0, 2 },
        else => .{ 0, 1 },
    };
}

/// Max-projection of a channel along `axis` over the world box — the
/// carrier's MIN, since inside is negative — the slice's honest sibling
/// for a thin structure, which a single plane mostly misses. Row-major
/// like `slice`.
pub fn project(w: *const World, gpa: std.mem.Allocator, bit: u6, axis: u2, lo: [3]f64, hi: [3]f64, res: u32, depth: u32) ![]f32 {
    const out = try gpa.alloc(f32, @as(usize, res) * res);
    const carrier = bit == Channel.surface.bit();
    @memset(out, if (carrier) channel.band(1) else 0);
    const snap = w.published();
    const free = freeAxes(axis);
    var v: u32 = 0;
    while (v < res) : (v += 1) {
        var u: u32 = 0;
        while (u < res) : (u += 1) {
            var p: [3]f64 = undefined;
            p[free[0]] = lo[free[0]] + (hi[free[0]] - lo[free[0]]) * (@as(f64, @floatFromInt(u)) + 0.5) / @as(f64, @floatFromInt(res));
            p[free[1]] = lo[free[1]] + (hi[free[1]] - lo[free[1]]) * (@as(f64, @floatFromInt(v)) + 0.5) / @as(f64, @floatFromInt(res));
            var m: f32 = if (carrier) channel.band(1) else 0;
            var d: u32 = 0;
            while (d < depth) : (d += 1) {
                p[axis] = lo[axis] + (hi[axis] - lo[axis]) * (@as(f64, @floatFromInt(d)) + 0.5) / @as(f64, @floatFromInt(depth));
                const v_here = snap.sample(bit, w.domain.toLattice(p));
                m = if (carrier) @min(m, v_here) else @max(m, v_here);
            }
            out[@as(usize, v) * res + u] = m;
        }
    }
    return out;
}

/// The carrier as occupancy for a picture: 1 inside, 0 outside, in place.
pub fn occupancy(values: []f32) void {
    for (values) |*v| v.* = if (v.* < 0) 1 else 0;
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

/// 3-D connected components (6-connectivity on lattice points) of young
/// tissue: the carrier below `phi_max` (zero: inside) laid within the
/// last `window_s` seconds of fed time, counting components of at least
/// `min_points` — the window's trailing edge cuts a ring and leaves
/// slivers of a point or three. Live tips each own one; the G2 instrument.
pub fn youngComponents(w: *const World, gpa: std.mem.Allocator, phi_max: f32, window_s: f32, min_points: usize) !usize {
    const snap = w.published();
    // The world's clock, not the snapshot's: a quiet step publishes nothing.
    const now_s: f32 = @floatCast(@as(f64, @floatFromInt(w.time_ns)) / 1e9);
    var points = std.AutoHashMapUnmanaged(u64, void){};
    defer points.deinit(gpa);
    const bs = try snap.bricks(gpa);
    defer gpa.free(bs);
    for (bs) |b| {
        const m = b.plane(Channel.surface.bit()) orelse continue;
        const age = b.plane(Channel.age.bit()) orelse continue;
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    const idx = Brick.index(i, j, k);
                    if (m[idx] >= phi_max) continue;
                    if (age[idx] == 0 or now_s - age[idx] >= window_s) continue;
                    const p = b.pointAt(i, j, k);
                    try points.put(gpa, lattice.morton(p[0], p[1], p[2]), {});
                }
            }
        }
    }
    var seen = std.AutoHashMapUnmanaged(u64, void){};
    defer seen.deinit(gpa);
    var stack = std.ArrayListUnmanaged(u64){};
    defer stack.deinit(gpa);
    var count: usize = 0;
    var it = points.keyIterator();
    while (it.next()) |start| {
        if (seen.contains(start.*)) continue;
        var size: usize = 0;
        try seen.put(gpa, start.*, {});
        try stack.append(gpa, start.*);
        while (stack.pop()) |code| {
            size += 1;
            const p = lattice.demorton(code);
            const nbrs = [6][3]i64{
                .{ @as(i64, p[0]) - 1, p[1], p[2] }, .{ @as(i64, p[0]) + 1, p[1], p[2] },
                .{ p[0], @as(i64, p[1]) - 1, p[2] }, .{ p[0], @as(i64, p[1]) + 1, p[2] },
                .{ p[0], p[1], @as(i64, p[2]) - 1 }, .{ p[0], p[1], @as(i64, p[2]) + 1 },
            };
            for (nbrs) |q| {
                if (q[0] < 0 or q[1] < 0 or q[2] < 0 or q[0] > lattice.CELLS or q[1] > lattice.CELLS or q[2] > lattice.CELLS) continue;
                const qc = lattice.morton(@intCast(q[0]), @intCast(q[1]), @intCast(q[2]));
                if (!points.contains(qc) or seen.contains(qc)) continue;
                try seen.put(gpa, qc, {});
                try stack.append(gpa, qc);
            }
        }
        if (size >= min_points) count += 1;
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
            const pl = b.plane(c.bit) orelse return;
            var k: u32 = 0;
            while (k < brick.N) : (k += 1) {
                var j: u32 = 0;
                while (j < brick.N) : (j += 1) {
                    var i: u32 = 0;
                    while (i < brick.N) : (i += 1) c.sum += pl[Brick.index(i, j, k)];
                }
            }
        }
    }.f);
    return ctx.sum;
}

/// Samples of the carrier that are inside (φ < 0), over every brick's
/// own samples — the amount of tissue, in the sense G2 needs (monotone
/// where nothing is cut), with shared faces counted once per holder.
pub fn insideCount(w: *const World) u64 {
    const Ctx = struct { n: u64 = 0 };
    var ctx = Ctx{};
    w.published().forEachBrick(&ctx, struct {
        fn f(c: *Ctx, b: *const Brick) void {
            const pl = b.plane(Channel.surface.bit()) orelse return;
            var k: u32 = 0;
            while (k < brick.N) : (k += 1) {
                var j: u32 = 0;
                while (j < brick.N) : (j += 1) {
                    var i: u32 = 0;
                    while (i < brick.N) : (i += 1) if (pl[Brick.index(i, j, k)] < 0) {
                        c.n += 1;
                    };
                }
            }
        }
    }.f);
    return ctx.n;
}

/// Centroid of the inside samples of the carrier, lattice units, and how
/// many: the G3 measure, occupancy-weighted.
pub fn insideCentroid(w: *const World) struct { c: [3]f64, n: u64 } {
    const Ctx = struct { n: u64 = 0, m: [3]f64 = .{ 0, 0, 0 } };
    var ctx = Ctx{};
    w.published().forEachBrick(&ctx, struct {
        fn f(c: *Ctx, b: *const Brick) void {
            const pl = b.plane(Channel.surface.bit()) orelse return;
            var k: u32 = 0;
            while (k < brick.N) : (k += 1) {
                var j: u32 = 0;
                while (j < brick.N) : (j += 1) {
                    var i: u32 = 0;
                    while (i < brick.N) : (i += 1) {
                        if (pl[Brick.index(i, j, k)] >= 0) continue;
                        const p = b.pointAt(i, j, k);
                        c.n += 1;
                        c.m[0] += @floatFromInt(p[0]);
                        c.m[1] += @floatFromInt(p[1]);
                        c.m[2] += @floatFromInt(p[2]);
                    }
                }
            }
        }
    }.f);
    if (ctx.n == 0) return .{ .c = .{ 0, 0, 0 }, .n = 0 };
    const nf: f64 = @floatFromInt(ctx.n);
    return .{ .c = .{ ctx.m[0] / nf, ctx.m[1] / nf, ctx.m[2] / nf }, .n = ctx.n };
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
                        if (v == 0) continue; // additive channels: absent is zero
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

// ── Tropism: the matched-pair ensemble (G3, and `--tropism-sweep`) ─────

/// The stimulus coefficient the ensemble uses. Spec §11's term is
/// a·∇stimulus; a blob's gradient over a radius of 96 is of order 0.01
/// per lattice unit, so a = 30 puts the term at the order of the
/// persistence term. A scene parameter, not a threshold.
pub const TROPISM_COEFF: f32 = 30;

pub const TropismSample = struct {
    seed: u64,
    /// The imposed horizontal direction, drawn from the seed.
    u: [3]f64,
    /// (c⁺ − c⁻)·û: the paired directional response, lattice units.
    r: f64,
    /// The no-stimulus centroid's displacement projected on û — natural
    /// wander along the same direction the pair is measured on. NaN when
    /// the null run was skipped.
    null_disp: f64,
};

pub const TropismEnsemble = struct {
    samples: []TropismSample,
    mean: f64,
    /// Sample standard deviation of r.
    sd: f64,
    /// r̄ − t₀.₉₇₅,ₙ₋₁ · sd/√n.
    lower95: f64,
    /// RMS of null_disp over the seeds: the effect-size unit, 1-D along û.
    sigma0: f64,
    all_positive: bool,

    pub fn deinit(self: *TropismEnsemble, gpa: std.mem.Allocator) void {
        gpa.free(self.samples);
    }
};

/// Student's t, two-sided 95%, for df = n − 1. A table, because a gate
/// should not ship a special-function library for one number.
pub fn tStudent975(df: usize) f64 {
    const table = [_]f64{ 12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086 };
    std.debug.assert(df >= 1 and df <= table.len);
    return table[df - 1];
}

/// Direction û from the seed: an angle in the horizontal plane. The seed
/// chooses it, so no axis is privileged.
pub fn seededDirection(seed: u64) [3]f64 {
    const theta = 2 * std.math.pi * @as(f64, @import("rng.zig").unitOf(@import("rng.zig").hash4(seed, 0x7a3, 0, 0)));
    return .{ fmath.cos(theta), 0, fmath.sin(theta) };
}

/// Tissue centroid (inside samples of the carrier) of the sapling grown
/// `steps` steps with the stimulus at `stimulus` (world units), or none.
fn tropismRun(gpa: std.mem.Allocator, seed: u64, stimulus: ?[3]f64, coeff: f32, steps: u32) ![3]f64 {
    var w = try World.init(gpa, .{ .seed = seed });
    defer w.deinit();
    var scene = Scene{ .stimulus = stimulus, .tropism_light = 0, .tropism_stimulus = coeff };
    try scene.build(&w, .sapling);
    var i: u64 = 0;
    while (i <= steps) : (i += 1) try w.step(.{ .frame = i, .time_ns = i * std.time.ns_per_s }, null);
    return insideCentroid(&w).c;
}

/// One run of the ensemble: which seed, which condition.
const EnsembleRun = struct {
    seed: u64,
    stimulus: ?[3]f64,
    coeff: f32,
    steps: u32,
    result: [3]f64 = .{ 0, 0, 0 },
    err: ?anyerror = null,
};

const EnsembleCtx = struct {
    gpa: std.mem.Allocator,
    runs: []EnsembleRun,
    next: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    fn worker(self: *EnsembleCtx) void {
        while (true) {
            const i = self.next.fetchAdd(1, .monotonic);
            if (i >= self.runs.len) return;
            const r = &self.runs[i];
            r.result = tropismRun(self.gpa, r.seed, r.stimulus, r.coeff, r.steps) catch |e| {
                r.err = e;
                continue;
            };
        }
    }
};

/// Every run is its own world with its own seed, so they are independent
/// and run one per core: `min(runs, cpus)` threads pull from a shared
/// index. The result cannot depend on scheduling — each world is
/// deterministic and the reduction happens afterwards in seed order.
fn runEnsemble(gpa: std.mem.Allocator, runs: []EnsembleRun) !void {
    var ctx = EnsembleCtx{ .gpa = gpa, .runs = runs };
    const cpus = std.Thread.getCpuCount() catch 1;
    const nthreads = @max(1, @min(runs.len, cpus));
    const threads = try gpa.alloc(std.Thread, nthreads);
    defer gpa.free(threads);
    var spawned: usize = 0;
    for (threads) |*t| {
        t.* = std.Thread.spawn(.{}, EnsembleCtx.worker, .{&ctx}) catch break;
        spawned += 1;
    }
    if (spawned == 0) ctx.worker();
    for (threads[0..spawned]) |t| t.join();
    for (runs) |r| if (r.err) |e| return e;
}

/// Seeds 1..n, each with its direction: the ± pair and, when `with_null`,
/// the stimulus-free run that gives σ₀. A mutation that asserts only on
/// the pairs skips the null and a third of the cost.
pub fn tropismEnsemble(gpa: std.mem.Allocator, n: u64, d: f64, coeff: f32, steps: u32, with_null: bool) !TropismEnsemble {
    const per: usize = if (with_null) 3 else 2;
    const runs = try gpa.alloc(EnsembleRun, @as(usize, @intCast(n)) * per);
    defer gpa.free(runs);
    var seed: u64 = 1;
    while (seed <= n) : (seed += 1) {
        const u = seededDirection(seed);
        const base = (seed - 1) * per;
        runs[base] = .{ .seed = seed, .stimulus = .{ d * u[0], 40, d * u[2] }, .coeff = coeff, .steps = steps };
        runs[base + 1] = .{ .seed = seed, .stimulus = .{ -d * u[0], 40, -d * u[2] }, .coeff = coeff, .steps = steps };
        if (with_null) runs[base + 2] = .{ .seed = seed, .stimulus = null, .coeff = coeff, .steps = steps };
    }
    try runEnsemble(gpa, runs);

    const samples = try gpa.alloc(TropismSample, @intCast(n));
    errdefer gpa.free(samples);
    const seed_axis = (lattice.Domain{}).toLattice(.{ 0, 0, 0 });
    var sum: f64 = 0;
    var sum0: f64 = 0;
    var all_positive = true;
    seed = 1;
    while (seed <= n) : (seed += 1) {
        const u = seededDirection(seed);
        const base = (seed - 1) * per;
        const plus = runs[base].result;
        const minus = runs[base + 1].result;
        const r = (plus[0] - minus[0]) * u[0] + (plus[2] - minus[2]) * u[2];
        var disp: f64 = std.math.nan(f64);
        if (with_null) {
            const none = runs[base + 2].result;
            disp = (none[0] - seed_axis[0]) * u[0] + (none[2] - seed_axis[2]) * u[2];
            sum0 += disp * disp;
        }
        samples[seed - 1] = .{ .seed = seed, .u = u, .r = r, .null_disp = disp };
        sum += r;
        if (r <= 0) all_positive = false;
    }
    const nf: f64 = @floatFromInt(n);
    const mean = sum / nf;
    var ss: f64 = 0;
    for (samples) |smp| ss += (smp.r - mean) * (smp.r - mean);
    const sd = if (n > 1) @sqrt(ss / (nf - 1)) else 0;
    const lower = if (n > 1) mean - tStudent975(@intCast(n - 1)) * sd / @sqrt(nf) else mean;
    return .{ .samples = samples, .mean = mean, .sd = sd, .lower95 = lower, .sigma0 = if (with_null) @sqrt(sum0 / nf) else std.math.nan(f64), .all_positive = all_positive };
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
    /// Potential drawn down per second around a front; the sapling's
    /// default empties a two-radius sphere in a step, which is why its
    /// buds are born into exhausted ground and stay stubs.
    consume: f32 = 1.0,
    /// 0 turns branching off: G2's mutation.
    max_generation: u8 = 3,
    heal: bool = true,
    /// Overrides for the habit check (`loam-run --avoid`, `--inhibit`):
    /// null keeps the params' defaults.
    avoid: ?f32 = null,
    inhibit: ?f32 = null,
    persist: ?f32 = null,

    pub fn build(self: *Scene, w: *World, preset: Preset) !void {
        switch (preset) {
            .blob => {
                // A hand-placed density blob in a world of light-only
                // bricks: G6's empty-majority scene.
                try blobLattice(w, Channel.light.bit(), sceneToLattice(.{ 0, 0, 0 }), 64, 1.0, 0);
                try blobLattice(w, Channel.density.bit(), sceneToLattice(.{ 20, 0, 0 }), 6, 1.0, 0);
                try w.apply();
            },
            .seams => {
                // Two gauges sharing a face: the P1.2 gate's scene. The
                // fine blob first, applied, so the coarse one completes
                // the cubes it shares at the fine gauge.
                try blobLattice(w, Channel.light.bit(), sceneToLattice(.{ -12, 0, 0 }), 20, 1.0, 0);
                try w.apply();
                try blobLattice(w, Channel.light.bit(), sceneToLattice(.{ 20, 0, 0 }), 20, 1.0, 1);
                try w.apply();
            },
            .diffusion => {
                try blobLattice(w, Channel.growth.bit(), sceneToLattice(.{ 0, 0, 0 }), 3, 1.0, 0);
                try w.apply();
                self.diffusion[0] = .{ .bit = Channel.growth.bit(), .rate = 0.15 };
                try w.addOperator(operators.operatorOf(operators.Diffusion, &self.diffusion[0]));
                self.decay[0] = .{ .bit = Channel.growth.bit(), .tau = 20 };
                try w.addOperator(operators.operatorOf(operators.Decay, &self.decay[0]));
            },
            .sapling, .wound => {
                try blobLattice(w, Channel.growth.bit(), sceneToLattice(.{ 0, 24, 0 }), 56, 1.0, 0);
                try blobLattice(w, Channel.light.bit(), sceneToLattice(self.light), 64, 1.0, 0);
                // The stimulus covers the whole growth region: a blob that
                // excludes the seed steers nothing (G3 once sat at 1 unit
                // of drift for exactly that reason).
                if (self.stimulus) |s| try blobLattice(w, Channel.stimulus.bit(), sceneToLattice(s), 96, 1.0, 0);
                var params = front.Params{};
                params.tropism_light = self.tropism_light;
                params.tropism_stimulus = self.tropism_stimulus;
                params.deposit = self.deposit;
                params.consume = self.consume;
                params.max_generation = self.max_generation;
                params.length = 72;
                if (self.avoid) |a| params.avoid_self = a;
                if (self.inhibit) |v| params.inhibit = v;
                if (self.persist) |v| params.persist = v;
                try plantLattice(w, sceneToLattice(.{ 0, 0, 0 }), .{ 0, 1, 0 }, params);
                try w.apply();
                // No decay on Activity: it is a touch time now, and warmth is
                // `now − Activity` wherever it is read.
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
