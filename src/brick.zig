//! brick — the spatial storage unit (spec §5.2, §6, §18; brief R2).
//!
//! A brick is a cube of 8 cells per axis at one GAUGE: samples sit on
//! lattice points spaced 2^gauge apart, 9 per axis, 729 per plane,
//! node-centred so a brick is self-contained for trilinear reconstruction
//! inside its closed cube — a sample never reaches into a neighbour, and
//! the seam contract (`world.zig`, reconcile) is what makes the two sides
//! of a face agree.
//!
//! Planes are popcount-packed by channel mask: `planes.len ==
//! @popCount(mask)`, always. A channel that is absent has no plane, no
//! pointer and no slot — "do not instantiate absent channels" (§18) is a
//! structural fact a guard can check, not a manner.
//!
//! A brick is immutable once it is in a published snapshot. The commit
//! clones a dirty brick (`clone`), edits the clone, and the old one lives
//! on in the older snapshot until its last reader releases it. Refcounts
//! are atomic because snapshots are read from other threads (G8).

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const summary = @import("summary.zig");

const Key = lattice.Key;
const Blake3 = std.crypto.hash.Blake3;

pub const CELLS: u32 = 1 << lattice.BRICK_LOG2;
pub const N: u32 = CELLS + 1;
pub const SAMPLES: usize = N * N * N;
pub const Plane = [SAMPLES]f32;

pub const Error = error{ OutOfMemory, GaugeConflict };

pub const Brick = struct {
    key: Key,
    mask: channel.Mask = 0,
    planes: []*Plane = &.{},
    version: u32 = 0,
    summary: summary.Summary = .{},
    hash: [32]u8 = [_]u8{0} ** 32,
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    pub fn create(gpa: std.mem.Allocator, key: Key) !*Brick {
        const b = try gpa.create(Brick);
        b.* = .{ .key = key };
        return b;
    }

    /// A deep copy with refs = 1 and the source's version. The caller
    /// edits it, then `finalize`s it.
    pub fn clone(gpa: std.mem.Allocator, src: *const Brick) !*Brick {
        const b = try gpa.create(Brick);
        errdefer gpa.destroy(b);
        b.* = .{ .key = src.key, .mask = src.mask, .version = src.version, .summary = src.summary, .hash = src.hash };
        const planes = try gpa.alloc(*Plane, src.planes.len);
        errdefer gpa.free(planes);
        var made: usize = 0;
        errdefer for (planes[0..made]) |p| gpa.destroy(p);
        for (src.planes, 0..) |p, i| {
            const np = try gpa.create(Plane);
            np.* = p.*;
            planes[i] = np;
            made += 1;
        }
        b.planes = planes;
        return b;
    }

    pub fn retain(self: *Brick) void {
        _ = self.refs.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Brick, gpa: std.mem.Allocator) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            for (self.planes) |p| gpa.destroy(p);
            gpa.free(self.planes);
            gpa.destroy(self);
        }
    }

    pub fn gauge(self: *const Brick) u5 {
        return self.key.gauge();
    }

    pub fn spacing(self: *const Brick) u32 {
        return self.key.spacing();
    }

    pub fn origin(self: *const Brick) [3]u32 {
        return self.key.origin();
    }

    pub fn has(self: *const Brick, bit: u6) bool {
        return channel.has(self.mask, bit);
    }

    pub fn plane(self: *const Brick, bit: u6) ?*Plane {
        if (!channel.has(self.mask, bit)) return null;
        return self.planes[channel.planeIndex(self.mask, bit)];
    }

    /// The plane for `bit`, allocating it zeroed if absent. Only a brick
    /// under construction — this commit's clone, held by nothing but the
    /// commit and its scratch tree — may be written; a published brick
    /// is never handed out as `*Brick`, which is the guarantee.
    pub fn ensurePlane(self: *Brick, gpa: std.mem.Allocator, bit: u6) !*Plane {
        if (self.plane(bit)) |p| return p;
        const np = try gpa.create(Plane);
        @memset(np, 0);
        const idx = channel.planeIndex(self.mask, bit);
        const planes = try gpa.alloc(*Plane, self.planes.len + 1);
        @memcpy(planes[0..idx], self.planes[0..idx]);
        planes[idx] = np;
        @memcpy(planes[idx + 1 ..], self.planes[idx..]);
        gpa.free(self.planes);
        self.planes = planes;
        self.mask |= channel.maskOf(bit);
        return np;
    }

    /// Drop a plane that is all zero: the channel becomes absent again.
    fn dropPlane(self: *Brick, gpa: std.mem.Allocator, bit: u6) void {
        const idx = channel.planeIndex(self.mask, bit);
        gpa.destroy(self.planes[idx]);
        const planes = gpa.alloc(*Plane, self.planes.len - 1) catch unreachable; // shrinking
        @memcpy(planes[0..idx], self.planes[0..idx]);
        @memcpy(planes[idx..], self.planes[idx + 1 ..]);
        gpa.free(self.planes);
        self.planes = planes;
        self.mask &= ~channel.maskOf(bit);
    }

    pub inline fn index(i: u32, j: u32, k: u32) usize {
        return @as(usize, i) + N * (@as(usize, j) + N * @as(usize, k));
    }

    pub inline fn unindex(idx: usize) [3]u32 {
        const i: u32 = @intCast(idx % N);
        const j: u32 = @intCast((idx / N) % N);
        const k: u32 = @intCast(idx / (N * N));
        return .{ i, j, k };
    }

    pub fn get(self: *const Brick, bit: u6, i: u32, j: u32, k: u32) f32 {
        const p = self.plane(bit) orelse return 0;
        return p[index(i, j, k)];
    }

    /// Lattice point of sample (i, j, k).
    pub fn pointAt(self: *const Brick, i: u32, j: u32, k: u32) [3]u32 {
        const o = self.origin();
        const s = self.spacing();
        return .{ o[0] + i * s, o[1] + j * s, o[2] + k * s };
    }

    /// Sample index of lattice point `p` if it is one of this brick's
    /// samples (inside the closed cube and on this gauge's lattice).
    pub fn localOf(self: *const Brick, p: [3]i64) ?[3]u32 {
        if (!self.key.holdsPoint(p)) return null;
        const o = self.origin();
        const s: i64 = self.spacing();
        var r: [3]u32 = undefined;
        inline for (0..3) |a| {
            const d = p[a] - @as(i64, o[a]);
            if (@rem(d, s) != 0) return null;
            r[a] = @intCast(@divExact(d, s));
        }
        return r;
    }

    pub fn isBoundary(i: u32, j: u32, k: u32) bool {
        return i == 0 or i == CELLS or j == 0 or j == CELLS or k == 0 or k == CELLS;
    }

    /// Trilinear reconstruction at `p` (lattice units) inside the closed
    /// cube; clamped at the faces so a point on the boundary reads the
    /// boundary. Zero for an absent channel.
    pub fn trilinear(self: *const Brick, bit: u6, p: [3]f64) f32 {
        const pl = self.plane(bit) orelse return 0;
        return trilinearPlane(self, pl, p);
    }

    pub fn trilinearPlane(self: *const Brick, pl: *const Plane, p: [3]f64) f32 {
        const o = self.origin();
        const s: f64 = @floatFromInt(self.spacing());
        var ix: [3]u32 = undefined;
        var f: [3]f32 = undefined;
        inline for (0..3) |a| {
            var u = (p[a] - @as(f64, @floatFromInt(o[a]))) / s;
            if (u < 0) u = 0;
            if (u > @as(f64, CELLS)) u = @as(f64, CELLS);
            var ii: u32 = @intFromFloat(@floor(u));
            if (ii >= CELLS) ii = CELLS - 1;
            ix[a] = ii;
            f[a] = @floatCast(u - @as(f64, @floatFromInt(ii)));
        }
        const c000 = pl[index(ix[0], ix[1], ix[2])];
        const c100 = pl[index(ix[0] + 1, ix[1], ix[2])];
        const c010 = pl[index(ix[0], ix[1] + 1, ix[2])];
        const c110 = pl[index(ix[0] + 1, ix[1] + 1, ix[2])];
        const c001 = pl[index(ix[0], ix[1], ix[2] + 1)];
        const c101 = pl[index(ix[0] + 1, ix[1], ix[2] + 1)];
        const c011 = pl[index(ix[0], ix[1] + 1, ix[2] + 1)];
        const c111 = pl[index(ix[0] + 1, ix[1] + 1, ix[2] + 1)];
        const fx = f[0];
        const fy = f[1];
        const fz = f[2];
        const c00 = c000 + (c100 - c000) * fx;
        const c10 = c010 + (c110 - c010) * fx;
        const c01 = c001 + (c101 - c001) * fx;
        const c11 = c011 + (c111 - c011) * fx;
        const c0 = c00 + (c10 - c00) * fy;
        const c1 = c01 + (c11 - c01) * fy;
        return c0 + (c1 - c0) * fz;
    }

    /// Recompute the summary and the hash after editing; drop planes that
    /// are entirely zero so the mask says what is actually there.
    pub fn finalize(self: *Brick, gpa: std.mem.Allocator) void {
        var bit: u6 = 0;
        while (true) : (bit += 1) {
            if (self.plane(bit)) |pl| {
                var all_zero = true;
                for (pl) |v| if (v != 0) {
                    all_zero = false;
                    break;
                };
                if (all_zero) self.dropPlane(gpa, bit);
            }
            if (bit == 63) break;
        }
        self.summary = self.computeSummary();
        self.hash = self.computeHash();
    }

    fn computeSummary(self: *const Brick) summary.Summary {
        var s = summary.Summary{ .mask = self.mask, .version = self.version };
        const sp: f32 = @floatFromInt(self.spacing());
        var bit: u6 = 0;
        while (true) : (bit += 1) {
            if (self.plane(bit)) |pl| {
                const range: ?*summary.Range = blk: {
                    if (bit == channel.Channel.density.bit()) break :blk &s.density;
                    if (bit == channel.Channel.extinction.bit()) break :blk &s.extinction;
                    if (bit == channel.Channel.emission.bit()) break :blk &s.emission;
                    if (bit == channel.Channel.material.bit()) break :blk &s.material;
                    break :blk null;
                };
                var k: u32 = 0;
                while (k < N) : (k += 1) {
                    var j: u32 = 0;
                    while (j < N) : (j += 1) {
                        var i: u32 = 0;
                        while (i < N) : (i += 1) {
                            const v = pl[index(i, j, k)];
                            if (range) |r| r.include(v);
                            if (v != 0) s.includePoint(self.pointAt(i, j, k));
                            if (i + 1 < N) s.max_gradient = @max(s.max_gradient, @abs(pl[index(i + 1, j, k)] - v) / sp);
                            if (j + 1 < N) s.max_gradient = @max(s.max_gradient, @abs(pl[index(i, j + 1, k)] - v) / sp);
                            if (k + 1 < N) s.max_gradient = @max(s.max_gradient, @abs(pl[index(i, j, k + 1)] - v) / sp);
                        }
                    }
                }
            }
            if (bit == 63) break;
        }
        s.majorant = @max(@max(if (s.density.isEmpty()) 0 else s.density.max, if (s.extinction.isEmpty()) 0 else s.extinction.max), 0);
        return s;
    }

    fn computeHash(self: *const Brick) [32]u8 {
        var h = Blake3.init(.{});
        const raw = self.key.raw();
        h.update(std.mem.asBytes(&raw));
        h.update(std.mem.asBytes(&self.mask));
        h.update(std.mem.asBytes(&self.version));
        for (self.planes) |p| h.update(std.mem.sliceAsBytes(p[0..]));
        var out: [32]u8 = undefined;
        h.final(&out);
        return out;
    }

    /// Max |value| over a plane — the change floor's instrument.
    pub fn planeMaxAbs(pl: *const Plane) f32 {
        var m: f32 = 0;
        for (pl) |v| m = @max(m, @abs(v));
        return m;
    }
};

test "planes are popcount-packed and an absent channel has no plane" {
    const gpa = std.testing.allocator;
    const b = try Brick.create(gpa, Key.ofBrick(0, .{ 0, 0, 0 }));
    defer b.release(gpa);
    try std.testing.expectEqual(@as(usize, 0), b.planes.len);
    try std.testing.expect(b.plane(channel.Channel.material.bit()) == null);
    const m = try b.ensurePlane(gpa, channel.Channel.material.bit());
    m[Brick.index(1, 2, 3)] = 0.5;
    const d = try b.ensurePlane(gpa, channel.Channel.density.bit());
    d[Brick.index(4, 4, 4)] = 2;
    // density (bit 0) packs before material (bit 12) whatever the order of creation
    try std.testing.expectEqual(@as(usize, 2), b.planes.len);
    try std.testing.expectEqual(d, b.planes[0]);
    try std.testing.expectEqual(m, b.planes[1]);
    try std.testing.expectEqual(@as(f32, 0.5), b.get(channel.Channel.material.bit(), 1, 2, 3));
    try std.testing.expectEqual(@as(f32, 0), b.get(channel.Channel.light.bit(), 1, 2, 3));
    b.finalize(gpa);
    try std.testing.expectEqual([3]u32{ 1, 2, 3 }, b.summary.lo);
    try std.testing.expectEqual([3]u32{ 4, 4, 4 }, b.summary.hi);
    try std.testing.expectEqual(@as(f32, 2), b.summary.density.max);
    try std.testing.expectEqual(@as(f32, 0.5), b.summary.material.max);
    try std.testing.expectEqual(@as(f32, 2), b.summary.majorant);
    // Zero the density plane: finalize drops it and the mask says so.
    @memset(d, 0);
    b.finalize(gpa);
    try std.testing.expectEqual(@as(usize, 1), b.planes.len);
    try std.testing.expect(!b.has(channel.Channel.density.bit()));
}

test "trilinear reproduces samples at points and interpolates between them, at gauge 2" {
    const gpa = std.testing.allocator;
    const b = try Brick.create(gpa, Key.ofBrick(2, .{ 32, 0, 0 }));
    defer b.release(gpa);
    const pl = try b.ensurePlane(gpa, 0);
    // f(x,y,z) = x + 2y + 3z in lattice units is reproduced exactly by trilinear.
    var k: u32 = 0;
    while (k < N) : (k += 1) {
        var j: u32 = 0;
        while (j < N) : (j += 1) {
            var i: u32 = 0;
            while (i < N) : (i += 1) {
                const p = b.pointAt(i, j, k);
                pl[Brick.index(i, j, k)] = @floatFromInt(p[0] + 2 * p[1] + 3 * p[2]);
            }
        }
    }
    try std.testing.expectApproxEqAbs(@as(f32, 36 + 2 * 4 + 3 * 8), b.trilinear(0, .{ 36, 4, 8 }), 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 33.5 + 2 * 1.25 + 3 * 30), b.trilinear(0, .{ 33.5, 1.25, 30 }), 1e-3);
    // The closed cube's far face reads the face.
    try std.testing.expectApproxEqAbs(@as(f32, 64 + 2 * 32 + 3 * 32), b.trilinear(0, .{ 64, 32, 32 }), 1e-3);
    try std.testing.expectEqual([3]u32{ 1, 2, 0 }, b.localOf(.{ 36, 8, 0 }).?);
    try std.testing.expect(b.localOf(.{ 37, 8, 0 }) == null);
    try std.testing.expect(b.localOf(.{ 36, 8, 33 }) == null);
}
