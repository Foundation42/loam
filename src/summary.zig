//! summary — the conservative payload of a tree node (spec §5.2, §8).
//!
//! A summary lets a consumer reject a subtree without sampling a leaf, so
//! every field is a bound that the subtree's contents cannot exceed:
//! union of bounds, union of channel masks, min/max of ranges, max of
//! gradients. Conservative is the whole contract; a guard checks it
//! bottom-up and a self-test corrupts it (`guards.zig`).
//!
//! Bounds are the TIGHT lattice box of non-zero support — the wide8 rule
//! (a node's box is what it holds, never its cell). An empty brick has an
//! empty box (lo > hi) and a ray skips it on bounds alone, which is why
//! G6's denominator is "leaves crossed", counted geometrically.

const std = @import("std");
const channel = @import("channel.zig");

pub const Range = struct {
    min: f32 = std.math.inf(f32),
    max: f32 = -std.math.inf(f32),

    pub fn empty() Range {
        return .{};
    }

    pub fn include(self: *Range, v: f32) void {
        if (v < self.min) self.min = v;
        if (v > self.max) self.max = v;
    }

    pub fn merge(a: Range, b: Range) Range {
        return .{ .min = @min(a.min, b.min), .max = @max(a.max, b.max) };
    }

    pub fn isEmpty(self: Range) bool {
        return self.min > self.max;
    }

    /// Whether anything in the range is above zero — "optically relevant".
    pub fn positive(self: Range) bool {
        return !self.isEmpty() and self.max > 0;
    }
};

/// Channels whose ranges a summary tracks by name. Density and extinction
/// (transport), emission (emission-only queries), material (what fronts
/// build). Others are answered by the mask alone.
pub const tracked = [_]channel.Channel{ .density, .extinction, .emission, .material };

pub const Summary = struct {
    /// Tight lattice-point bounds of non-zero support, inclusive. Empty
    /// when lo > hi on any axis.
    lo: [3]u32 = .{ std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32) },
    hi: [3]u32 = .{ 0, 0, 0 },
    mask: channel.Mask = 0,
    density: Range = .{},
    extinction: Range = .{},
    emission: Range = .{},
    material: Range = .{},
    /// Largest |finite difference| between adjacent samples, any channel,
    /// per lattice unit.
    max_gradient: f32 = 0,
    /// Transport majorant: max of density and extinction. Optional in the
    /// spec; here it is derived so it cannot disagree with the ranges.
    majorant: f32 = 0,
    /// Highest brick version in the subtree.
    version: u32 = 0,

    pub fn isEmpty(self: Summary) bool {
        return self.lo[0] > self.hi[0] or self.lo[1] > self.hi[1] or self.lo[2] > self.hi[2];
    }

    pub fn includePoint(self: *Summary, p: [3]u32) void {
        inline for (0..3) |a| {
            if (p[a] < self.lo[a]) self.lo[a] = p[a];
            if (p[a] > self.hi[a]) self.hi[a] = p[a];
        }
    }

    pub fn merge(a: Summary, b: Summary) Summary {
        var s = Summary{
            .mask = a.mask | b.mask,
            .density = Range.merge(a.density, b.density),
            .extinction = Range.merge(a.extinction, b.extinction),
            .emission = Range.merge(a.emission, b.emission),
            .material = Range.merge(a.material, b.material),
            .max_gradient = @max(a.max_gradient, b.max_gradient),
            .majorant = @max(a.majorant, b.majorant),
            .version = @max(a.version, b.version),
        };
        inline for (0..3) |ax| {
            s.lo[ax] = @min(a.lo[ax], b.lo[ax]);
            s.hi[ax] = @max(a.hi[ax], b.hi[ax]);
        }
        return s;
    }

    /// The range tracked for `bit`, if the summary tracks one.
    pub fn rangeOf(self: *const Summary, bit: u6) ?Range {
        if (bit == channel.Channel.density.bit()) return self.density;
        if (bit == channel.Channel.extinction.bit()) return self.extinction;
        if (bit == channel.Channel.emission.bit()) return self.emission;
        if (bit == channel.Channel.material.bit()) return self.material;
        return null;
    }

    /// `a` is at least as conservative as `b` on every field: what a
    /// parent must be with respect to each child.
    pub fn covers(a: Summary, b: Summary) bool {
        if (b.isEmpty()) {
            // An empty child asks nothing of the bounds, only of the rest.
        } else {
            if (a.isEmpty()) return false;
            inline for (0..3) |ax| {
                if (a.lo[ax] > b.lo[ax] or a.hi[ax] < b.hi[ax]) return false;
            }
        }
        if ((a.mask & b.mask) != b.mask) return false;
        if (!rangeCovers(a.density, b.density)) return false;
        if (!rangeCovers(a.extinction, b.extinction)) return false;
        if (!rangeCovers(a.emission, b.emission)) return false;
        if (!rangeCovers(a.material, b.material)) return false;
        if (a.max_gradient < b.max_gradient) return false;
        if (a.majorant < b.majorant) return false;
        if (a.version < b.version) return false;
        return true;
    }

    fn rangeCovers(a: Range, b: Range) bool {
        if (b.isEmpty()) return true;
        if (a.isEmpty()) return false;
        return a.min <= b.min and a.max >= b.max;
    }

    /// Bytes for the Merkle hash: every field, fixed layout.
    pub fn hashInto(self: *const Summary, h: *std.crypto.hash.Blake3) void {
        h.update(std.mem.asBytes(&self.lo));
        h.update(std.mem.asBytes(&self.hi));
        h.update(std.mem.asBytes(&self.mask));
        inline for (.{ self.density, self.extinction, self.emission, self.material }) |r| {
            h.update(std.mem.asBytes(&r.min));
            h.update(std.mem.asBytes(&r.max));
        }
        h.update(std.mem.asBytes(&self.max_gradient));
        h.update(std.mem.asBytes(&self.majorant));
        h.update(std.mem.asBytes(&self.version));
    }
};

test "merge is conservative on every field and empty merges to the other" {
    var a = Summary{};
    a.includePoint(.{ 1, 2, 3 });
    a.includePoint(.{ 4, 5, 6 });
    a.mask = 1;
    a.density.include(0.5);
    var b = Summary{};
    b.includePoint(.{ 0, 9, 3 });
    b.mask = 2;
    b.density.include(-1);
    b.density.include(2);
    b.max_gradient = 3;
    const m = Summary.merge(a, b);
    try std.testing.expect(m.covers(a) and m.covers(b));
    try std.testing.expect(!a.covers(b));
    try std.testing.expectEqual([3]u32{ 0, 2, 3 }, m.lo);
    try std.testing.expectEqual([3]u32{ 4, 9, 6 }, m.hi);
    try std.testing.expectEqual(@as(f32, -1), m.density.min);
    const e = Summary{};
    try std.testing.expect(e.isEmpty());
    try std.testing.expect(Summary.merge(e, a).covers(a));
    try std.testing.expect(a.covers(e));
}
