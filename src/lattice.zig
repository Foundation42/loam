//! lattice — the integer dyadic lattice the whole library addresses by (R2).
//!
//! `vec3 position, float time` is the public QUERY surface (spec §7); the
//! representation is a 20-bit-per-axis global lattice, Morton-keyed. Twenty
//! is not a taste: it is the widest per-axis width for which an exact
//! orient3d determinant still fits an i64 (3b+4 <= 64), and the width
//! matryoshka's `gauge_quantise.zig` snaps geometry to — so a field and the
//! geometry growing through it agree on where a point is by identity, not
//! by tolerance (tessera's Lattice Contract).
//!
//! Cells versus points. The lattice has 2^20 CELLS per axis and 2^20 + 1
//! POINTS (0..2^20 inclusive); a brick's samples sit on points, so the top
//! point of the top brick is 2^20, which is why point coordinates ride as
//! u32 and cell coordinates fit u20. Morton keys are over cells.
//!
//! Units. One lattice unit is `Domain.cell()` world units. Everything
//! inside the library is in lattice units; the domain converts at the two
//! doors (`toLattice`, `toWorld`) and nowhere else.

const std = @import("std");

/// Bits per axis on the global lattice.
pub const BITS: u6 = 20;
/// Cells per axis; also the coordinate of the top lattice point.
pub const CELLS: u32 = 1 << BITS;
/// Log2 of a brick's cells per axis. A brick is 8 cells = 9 sample points
/// per axis; level = gauge + BRICK_LOG2.
pub const BRICK_LOG2: u5 = 3;
/// The lattice's own level: the root cube.
pub const ROOT_LEVEL: u5 = @intCast(BITS);
/// The finest brick level (gauge 0) and the coarsest gauge a brick can have.
pub const MIN_LEVEL: u5 = BRICK_LOG2;
pub const MAX_GAUGE: u5 = ROOT_LEVEL - BRICK_LOG2;

/// World <-> lattice. `extent` world units cover 2^20 cells on every axis.
/// Default: one lattice unit per world unit, world origin at the lattice's
/// centre — the seedbed's frame, and the identity map when nobody asks
/// for another.
pub const Domain = struct {
    origin: [3]f64 = .{ -@as(f64, CELLS / 2), -@as(f64, CELLS / 2), -@as(f64, CELLS / 2) },
    extent: f64 = @as(f64, CELLS),

    /// One lattice unit in world units.
    pub fn cell(self: Domain) f64 {
        return self.extent / @as(f64, CELLS);
    }

    pub fn toLattice(self: Domain, w: [3]f64) [3]f64 {
        const c = self.cell();
        return .{ (w[0] - self.origin[0]) / c, (w[1] - self.origin[1]) / c, (w[2] - self.origin[2]) / c };
    }

    pub fn toWorld(self: Domain, l: [3]f64) [3]f64 {
        const c = self.cell();
        return .{ l[0] * c + self.origin[0], l[1] * c + self.origin[1], l[2] * c + self.origin[2] };
    }

    /// A world-unit length in lattice units.
    pub fn lengthToLattice(self: Domain, w: f64) f64 {
        return w / self.cell();
    }
};

fn spread(v: u32) u64 {
    var x: u64 = v & 0x1fffff;
    x = (x | (x << 32)) & 0x1f00000000ffff;
    x = (x | (x << 16)) & 0x1f0000ff0000ff;
    x = (x | (x << 8)) & 0x100f00f00f00f00f;
    x = (x | (x << 4)) & 0x10c30c30c30c30c3;
    x = (x | (x << 2)) & 0x1249249249249249;
    return x;
}

fn compact(v: u64) u32 {
    var x: u64 = v & 0x1249249249249249;
    x = (x ^ (x >> 2)) & 0x10c30c30c30c30c3;
    x = (x ^ (x >> 4)) & 0x100f00f00f00f00f;
    x = (x ^ (x >> 8)) & 0x1f0000ff0000ff;
    x = (x ^ (x >> 16)) & 0x1f00000000ffff;
    x = (x ^ (x >> 32)) & 0x1fffff;
    return @intCast(x);
}

/// 3-axis Morton code of a cell. Bit 0 is x, bit 1 y, bit 2 z — the same
/// octant numbering as matryoshka's wide8 (`slot[k]`, k = +x | +y<<1 |
/// +z<<2), so a walk XORs the same sign mask to go near-to-far.
pub fn morton(x: u32, y: u32, z: u32) u64 {
    return spread(x) | (spread(y) << 1) | (spread(z) << 2);
}

pub fn demorton(m: u64) [3]u32 {
    return .{ compact(m), compact(m >> 1), compact(m >> 2) };
}

/// Identity of a node or brick: its level (cube side = 2^level lattice
/// units) and the Morton code of its origin. Packed so that `raw()` sorts
/// Morton-major — a node's cube is a contiguous Morton range, and a sorted
/// list of dirty keys walks the tree in one pass. A brick is `level =
/// gauge + BRICK_LOG2`; nodes below MIN_LEVEL do not exist, so the low 9
/// Morton bits are always zero and the code fits 51 bits.
pub const Key = packed struct(u64) {
    level: u5,
    _pad: u8 = 0,
    morton9: u51,

    pub fn init(level: u5, o: [3]u32) Key {
        std.debug.assert(level >= MIN_LEVEL and level <= ROOT_LEVEL);
        const sd: u32 = @as(u32, 1) << level;
        std.debug.assert(o[0] % sd == 0 and o[1] % sd == 0 and o[2] % sd == 0);
        return .{ .level = level, .morton9 = @intCast(morton(o[0], o[1], o[2]) >> 9) };
    }

    pub fn ofBrick(g: u5, o: [3]u32) Key {
        return init(g + BRICK_LOG2, o);
    }

    /// The brick (at `gauge`) whose closed cube holds lattice point `p`.
    /// Points on the lattice's top face belong to the last brick.
    pub fn containing(g: u5, p: [3]u32) Key {
        const level: u5 = g + BRICK_LOG2;
        const sd: u32 = @as(u32, 1) << level;
        var o: [3]u32 = undefined;
        inline for (0..3) |a| {
            const c = @min(p[a], CELLS - 1);
            o[a] = c - (c % sd);
        }
        return init(level, o);
    }

    pub fn raw(self: Key) u64 {
        return @bitCast(self);
    }

    pub fn fromRaw(r: u64) Key {
        return @bitCast(r);
    }

    pub fn mortonCode(self: Key) u64 {
        return @as(u64, self.morton9) << 9;
    }

    pub fn origin(self: Key) [3]u32 {
        return demorton(self.mortonCode());
    }

    pub fn gauge(self: Key) u5 {
        return self.level - BRICK_LOG2;
    }

    /// Cube side in lattice units.
    pub fn side(self: Key) u32 {
        return @as(u32, 1) << self.level;
    }

    /// Sample spacing for a brick with this key.
    pub fn spacing(self: Key) u32 {
        return @as(u32, 1) << self.gauge();
    }

    pub fn eql(a: Key, b: Key) bool {
        return a.raw() == b.raw();
    }

    /// Morton range [lo, hi) of every cell in this cube.
    pub fn mortonRange(self: Key) [2]u64 {
        const lo = self.mortonCode();
        return .{ lo, lo + (@as(u64, 1) << (3 * @as(u6, self.level))) };
    }

    /// Whether lattice point `p` (i64 so callers may probe past the edge)
    /// lies in this cube's CLOSED cube [origin, origin + side].
    pub fn holdsPoint(self: Key, p: [3]i64) bool {
        const o = self.origin();
        const s: i64 = self.side();
        inline for (0..3) |a| {
            const lo: i64 = o[a];
            if (p[a] < lo or p[a] > lo + s) return false;
        }
        return true;
    }

    pub fn lessThan(_: void, a: Key, b: Key) bool {
        return a.raw() < b.raw();
    }
};

/// The child octant of a point inside a node at `level` with origin `o`.
/// bit0 = +x half, bit1 = +y, bit2 = +z.
pub fn octantOf(level: u5, o: [3]u32, p: [3]u32) u3 {
    const half: u32 = @as(u32, 1) << (level - 1);
    var k: u3 = 0;
    if (p[0] >= o[0] + half) k |= 1;
    if (p[1] >= o[1] + half) k |= 2;
    if (p[2] >= o[2] + half) k |= 4;
    return k;
}

pub fn childOrigin(level: u5, o: [3]u32, k: u3) [3]u32 {
    const half: u32 = @as(u32, 1) << (level - 1);
    return .{
        o[0] + (if (k & 1 != 0) half else 0),
        o[1] + (if (k & 2 != 0) half else 0),
        o[2] + (if (k & 4 != 0) half else 0),
    };
}

test "morton round-trips every axis, and the top cell" {
    const cases = [_][3]u32{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 12345, 54321, 777 }, .{ CELLS - 1, CELLS - 1, CELLS - 1 } };
    for (cases) |c| {
        const m = morton(c[0], c[1], c[2]);
        try std.testing.expectEqual(c, demorton(m));
    }
    // Axis bits interleave x,y,z from bit 0 — the wide8 octant order.
    try std.testing.expectEqual(@as(u64, 1), morton(1, 0, 0));
    try std.testing.expectEqual(@as(u64, 2), morton(0, 1, 0));
    try std.testing.expectEqual(@as(u64, 4), morton(0, 0, 1));
}

test "keys sort Morton-major and a cube's Morton range holds its bricks" {
    const root = Key.init(ROOT_LEVEL, .{ 0, 0, 0 });
    const a = Key.ofBrick(0, .{ 0, 0, 0 });
    const b = Key.ofBrick(0, .{ 8, 0, 0 });
    const c = Key.ofBrick(1, .{ 0, 16, 0 });
    try std.testing.expect(a.raw() < b.raw());
    try std.testing.expect(b.raw() < c.raw());
    const r = root.mortonRange();
    try std.testing.expect(a.mortonCode() >= r[0] and c.mortonCode() < r[1]);
    const inner = Key.init(5, .{ 0, 0, 0 });
    const ir = inner.mortonRange();
    try std.testing.expect(b.mortonCode() < ir[1]);
    try std.testing.expect(Key.ofBrick(0, .{ 32, 0, 0 }).mortonCode() >= ir[1]);
    try std.testing.expectEqual(a, Key.fromRaw(a.raw()));
    try std.testing.expectEqual([3]u32{ 0, 16, 0 }, c.origin());
    try std.testing.expectEqual(@as(u5, 1), c.gauge());
}

test "containing: a point on the shared face belongs to the upper brick; the top face belongs to the last" {
    try std.testing.expectEqual(Key.ofBrick(0, .{ 8, 0, 0 }), Key.containing(0, .{ 8, 3, 3 }));
    try std.testing.expectEqual(Key.ofBrick(0, .{ 0, 0, 0 }), Key.containing(0, .{ 7, 3, 3 }));
    const top = Key.containing(0, .{ CELLS, CELLS, CELLS });
    try std.testing.expectEqual([3]u32{ CELLS - 8, CELLS - 8, CELLS - 8 }, top.origin());
    try std.testing.expect(top.holdsPoint(.{ CELLS, CELLS, CELLS }));
    try std.testing.expect(!top.holdsPoint(.{ CELLS + 1, CELLS, CELLS }));
}

test "domain: the default is one unit per cell, centred" {
    const d = Domain{};
    const l = d.toLattice(.{ 0, 0, 0 });
    try std.testing.expectEqual(@as(f64, CELLS / 2), l[0]);
    const w = d.toWorld(l);
    try std.testing.expectEqual(@as(f64, 0), w[1]);
    try std.testing.expectEqual(@as(f64, 1), d.cell());
}
