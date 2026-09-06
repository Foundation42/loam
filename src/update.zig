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

pub const RegionUpdate = struct {
    key: Key,
    mask: channel.Mask = 0,
    deltas: [channel.COUNT]?*Plane = [_]?*Plane{null} ** channel.COUNT,
    /// Requested to exist even if no delta lands.
    materialise: bool = false,
    spawns: std.ArrayListUnmanaged(Spawn) = .{},

    pub fn delta(self: *RegionUpdate, a: std.mem.Allocator, bit: u6) !*Plane {
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
