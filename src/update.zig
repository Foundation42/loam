//! update — region-local update buffers (spec §9).
//!
//! An operator never writes a brick. It writes DELTAS into the update
//! buffer entry for the region it is evaluating — additive, per channel,
//! per sample — and the commit applies them in key order. Two operators
//! writing one channel sum; a job system running regions in any order
//! reaches the same buffer; a front, which writes wherever its ring
//! lands, gets an entry per brick it touches, created serially after the
//! barrier. That is what makes the parallel phase "free of accidental
//! order dependence" and G1 a property rather than a hope.
//!
//! Entries also carry what the commit must do besides add: materialise a
//! brick that does not exist yet, and spawn fronts an operator asked for.
//!
//! The carrier is not added (R10). A `surface` contribution is a
//! SURFACE OP — a plane of signed distances with the collar radius k and
//! an order — and the commit smooth-unions the ops into the brick in
//! that order, front id for a front's, insertion for authoring's. An
//! entry's ops are a list, never merged in the buffer, so two fronts
//! meeting in one brick compose in id order at commit and nowhere else.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const front = @import("front.zig");

const Key = lattice.Key;
const Plane = brick.Plane;

/// A front an operator or a front asked the commit to create.
pub const Spawn = struct {
    pos: [3]f64,
    dir: [3]f64,
    normal: [3]f64,
    params: front.Params,
    parent: u32 = std.math.maxInt(u32),
    generation: u8 = 0,
    morphogens: [4]f32 = .{ 0, 0, 0, 0 },
};

/// One smooth-union operand for the surface channel: a plane of signed
/// distances (+inf where the op says nothing), the collar radius, and
/// the order the commit applies it in. A FRONT's op also carries its
/// provenance (R12, P2.2): who (the front id plus one), the segment,
/// the arc length of its start ring and the collar's reach behind it.
/// The commit writes `who` and `segment` where this op's distance is
/// nearer than what stood, and reads `who` and `segment` of what stood
/// — against the ring table's arcs — to choose k: zero into the
/// front's own deposit within the reach, `k` into anything else. An
/// authored op has no provenance (`who` zero) and writes none.
pub const SurfaceOp = struct {
    plane: *Plane,
    k: f32,
    order: u64,
    mode: Mode = .join,
    who: u32 = 0,
    segment: u32 = 0,
    s0: f64 = 0,
    reach: f32 = 0,

    /// Join is the smooth union (what growth does); cut is the CSG
    /// difference φ = max(φ, −δ) with δ the cutter's own signed distance
    /// (what a wound does). Both hold the band.
    pub const Mode = enum { join, cut };

    /// "No contribution": the union's identity.
    pub const NONE: f32 = std.math.inf(f32);

    pub fn lessThan(_: void, a: SurfaceOp, b: SurfaceOp) bool {
        return a.order < b.order;
    }
};

pub const RegionUpdate = struct {
    key: Key,
    mask: channel.Mask = 0,
    deltas: [channel.COUNT]?*Plane = [_]?*Plane{null} ** channel.COUNT,
    /// Surface ops, in the order they were added; sorted by `order` at
    /// commit (a stable sort, so insertion breaks ties).
    surface_ops: std.ArrayListUnmanaged(SurfaceOp) = .{},
    /// Requested to exist even if no delta lands.
    materialise: bool = false,
    spawns: std.ArrayListUnmanaged(Spawn) = .{},

    /// The additive delta plane for `bit`. Not for the carrier: a surface
    /// contribution is an op (`surfaceOp`), and asking for its delta is a
    /// programming error, loudly.
    pub fn delta(self: *RegionUpdate, a: std.mem.Allocator, bit: u6) !*Plane {
        std.debug.assert(bit != channel.Channel.surface.bit());
        std.debug.assert(channel.rule(bit) != .set_by_winner and channel.rule(bit) != .distance); // provenance and the slots ride on the op
        if (self.deltas[bit]) |p| return p;
        const p = try a.create(Plane);
        @memset(p, 0);
        self.deltas[bit] = p;
        self.mask |= channel.maskOf(bit);
        return p;
    }

    pub fn add(self: *RegionUpdate, a: std.mem.Allocator, bit: u6, idx: usize, v: f32) !void {
        const p = try self.delta(a, bit);
        p[idx] += v;
    }

    /// A new surface op with collar `k` at `order`; its plane starts as
    /// "no contribution" everywhere.
    pub fn surfaceOp(self: *RegionUpdate, a: std.mem.Allocator, k: f32, order: u64) !*Plane {
        return self.surfaceOpMode(a, k, order, .join);
    }

    pub fn surfaceOpMode(self: *RegionUpdate, a: std.mem.Allocator, k: f32, order: u64, mode: SurfaceOp.Mode) !*Plane {
        const p = try a.create(Plane);
        @memset(p, SurfaceOp.NONE);
        try self.surface_ops.append(a, .{ .plane = p, .k = k, .order = order, .mode = mode });
        self.mask |= channel.Channel.surface.mask() | channel.SLOT_MASK;
        return p;
    }

    /// A front's op: the join with its provenance, ordered by front id.
    pub fn surfaceOpFront(self: *RegionUpdate, a: std.mem.Allocator, k: f32, who: u32, segment: u32, s0: f64, reach: f32) !*Plane {
        const p = try a.create(Plane);
        @memset(p, SurfaceOp.NONE);
        try self.surface_ops.append(a, .{ .plane = p, .k = k, .order = who - 1, .mode = .join, .who = who, .segment = segment, .s0 = s0, .reach = reach });
        self.mask |= channel.Channel.surface.mask() | channel.PROVENANCE_MASK | channel.SLOT_MASK;
        return p;
    }

    pub fn isEmpty(self: *const RegionUpdate) bool {
        return self.mask == 0 and !self.materialise and self.spawns.items.len == 0;
    }
};

/// The buffer for one step. The arena is reset per step; entries and
/// their planes live in it. `regions` is filled serially — before the
/// parallel phase for the active set, after the barrier for everything
/// the fronts touched — so the parallel phase never allocates an entry,
/// only planes, through the thread-safe wrapper.
pub const Buffer = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    tsa: std.heap.ThreadSafeAllocator,
    regions: std.AutoHashMapUnmanaged(u64, *RegionUpdate) = .{},
    /// Order of the next authoring surface op — insertion order, so two
    /// capsules authored in one apply compose the way they were queued.
    next_order: u64 = 0,

    pub fn init(gpa: std.mem.Allocator) Buffer {
        var b = Buffer{ .gpa = gpa, .arena = std.heap.ArenaAllocator.init(gpa), .tsa = undefined };
        b.tsa = .{ .child_allocator = undefined };
        return b;
    }

    pub fn deinit(self: *Buffer) void {
        self.regions.deinit(self.gpa);
        self.arena.deinit();
    }

    pub fn reset(self: *Buffer) void {
        self.regions.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
        self.next_order = 0;
    }

    /// Allocator for planes from the parallel phase.
    pub fn planeAllocator(self: *Buffer) std.mem.Allocator {
        self.tsa.child_allocator = self.arena.allocator();
        return self.tsa.allocator();
    }

    /// Get-or-create the entry for `key`. Serial only.
    pub fn region(self: *Buffer, key: Key) !*RegionUpdate {
        const gop = try self.regions.getOrPut(self.gpa, key.raw());
        if (!gop.found_existing) {
            const ru = try self.arena.allocator().create(RegionUpdate);
            ru.* = .{ .key = key };
            gop.value_ptr.* = ru;
        }
        return gop.value_ptr.*;
    }

    pub fn get(self: *Buffer, key: Key) ?*RegionUpdate {
        return self.regions.get(key.raw());
    }

    /// Every entry, sorted by key — the commit's order. Caller frees.
    pub fn sorted(self: *Buffer, a: std.mem.Allocator) ![]*RegionUpdate {
        const out = try a.alloc(*RegionUpdate, self.regions.count());
        var it = self.regions.valueIterator();
        var i: usize = 0;
        while (it.next()) |v| : (i += 1) out[i] = v.*;
        std.mem.sort(*RegionUpdate, out, {}, struct {
            fn lt(_: void, x: *RegionUpdate, y: *RegionUpdate) bool {
                return x.key.raw() < y.key.raw();
            }
        }.lt);
        return out;
    }
};

test "a surface op is a plane of no-contribution with its k and order, and never a delta" {
    const gpa = std.testing.allocator;
    var buf = Buffer.init(gpa);
    defer buf.deinit();
    const ru = try buf.region(Key.ofBrick(0, .{ 0, 0, 0 }));
    const a = buf.planeAllocator();
    const p = try ru.surfaceOp(a, 0.5, 3);
    try std.testing.expectEqual(SurfaceOp.NONE, p[7]);
    try std.testing.expect(channel.has(ru.mask, channel.Channel.surface.bit()));
    try std.testing.expect(ru.deltas[channel.Channel.surface.bit()] == null);
    try std.testing.expectEqual(@as(usize, 1), ru.surface_ops.items.len);
    try std.testing.expectEqual(@as(f32, 0.5), ru.surface_ops.items[0].k);
    try std.testing.expect(!ru.isEmpty());
}

test "deltas sum, entries sort by key, reset forgets" {
    const gpa = std.testing.allocator;
    var buf = Buffer.init(gpa);
    defer buf.deinit();
    const kb = Key.ofBrick(0, .{ 8, 0, 0 });
    const ka = Key.ofBrick(0, .{ 0, 0, 0 });
    const rb = try buf.region(kb);
    const ra = try buf.region(ka);
    try std.testing.expectEqual(rb, try buf.region(kb));
    const a = buf.planeAllocator();
    try ra.add(a, 3, 7, 0.5);
    try ra.add(a, 3, 7, 0.25);
    try std.testing.expectEqual(@as(f32, 0.75), ra.deltas[3].?[7]);
    try std.testing.expect(rb.isEmpty() and !ra.isEmpty());
    const s = try buf.sorted(gpa);
    defer gpa.free(s);
    try std.testing.expectEqual(ra, s[0]);
    try std.testing.expectEqual(rb, s[1]);
    buf.reset();
    try std.testing.expect(buf.get(ka) == null);
}
