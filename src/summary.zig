//! summary — the conservative payload of a tree node (spec §5.2, §8).
//!
//! A summary lets a consumer reject a subtree without sampling a leaf, so
//! every field is a bound that the subtree's contents cannot exceed:
//! union of bounds, union of channel masks, min/max of ranges, max of
//! gradients, max of the last change's magnitude and of its time.
//! Conservative is the whole contract; a guard checks it bottom-up and a
//! self-test corrupts it (`guards.zig`).
//!
//! Bounds are the TIGHT lattice box of non-zero support — the wide8 rule
//! (a node's box is what it holds, never its cell). An empty brick has an
//! empty box (lo > hi) and a ray skips it on bounds alone, which is why
//! G6's denominator is "leaves crossed", counted geometrically.

const std = @import("std");
const channel = @import("channel.zig");
const fmath = @import("fmath.zig");

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
/// (transport), emission (emission-only queries), material (volumes),
/// surface (the carrier: a subtree whose surface minimum is positive
/// holds no zero set). Others are answered by the mask alone.
pub const tracked = [_]channel.Channel{ .density, .extinction, .emission, .material, .surface };

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
    surface: Range = .{},
    /// A Lipschitz bound on every channel's reconstruction over the brick,
    /// per lattice unit: the root-sum-square over axes of the largest
    /// adjacent coefficient difference along each — the B-spline's
    /// derivative is a convex combination of those differences (R8).
    max_gradient: f32 = 0,
    /// The same bound for the surface channel alone: what a sphere tracer
    /// steps by (|φ|/L). Zero where there is no surface plane.
    lipschitz: f32 = 0,
    /// Transport majorant: max of density and extinction. Optional in the
    /// spec; here it is derived so it cannot disagree with the ranges.
    majorant: f32 = 0,
    /// Highest brick version in the subtree.
    version: u32 = 0,
    /// Attention bookkeeping (R15): the magnitude of the largest change
    /// that reached a brick at its last commit — its own deltas, its
    /// surface ops, a seam or halo write from a neighbour — and the fed
    /// nanosecond it landed. Never stepped: a(t) = attention ·
    /// exp(−(t − changed_ns)/τ) is derived where it is read
    /// (`attentionAt`), for a reader's τ. Merged by max on each
    /// separately, so a node's pair bounds every brick beneath it for
    /// any τ and a walk rejects a subtree whose bound is under its floor
    /// without touching a brick (G14 b).
    attention: f32 = 0,
    changed_ns: u64 = 0,

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
            .surface = Range.merge(a.surface, b.surface),
            .max_gradient = @max(a.max_gradient, b.max_gradient),
            .lipschitz = @max(a.lipschitz, b.lipschitz),
            .majorant = @max(a.majorant, b.majorant),
            .version = @max(a.version, b.version),
            .attention = @max(a.attention, b.attention),
            .changed_ns = @max(a.changed_ns, b.changed_ns),
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
        if (bit == channel.Channel.surface.bit()) return self.surface;
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
        if (!rangeCovers(a.surface, b.surface)) return false;
        if (a.max_gradient < b.max_gradient) return false;
        if (a.lipschitz < b.lipschitz) return false;
        if (a.majorant < b.majorant) return false;
        if (a.version < b.version) return false;
        if (a.attention < b.attention) return false;
        if (a.changed_ns < b.changed_ns) return false;
        return true;
    }

    /// The attention bound at fed time `now_ns` for a reader's τ:
    /// attention · exp(−(now − changed_ns)/τ) — exact at a leaf, an upper
    /// bound over a subtree. Zero where nothing ever changed. The sim's
    /// own exp: under a budget this ORDERS the step, so it is in the hash.
    pub fn attentionAt(self: *const Summary, now_ns: u64, tau_s: f64) f64 {
        if (self.attention <= 0) return 0;
        const elapsed_ns: u64 = if (now_ns > self.changed_ns) now_ns - self.changed_ns else 0;
        const elapsed: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        return @as(f64, self.attention) * fmath.exp(-elapsed / tau_s);
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
        inline for (.{ self.density, self.extinction, self.emission, self.material, self.surface }) |r| {
            h.update(std.mem.asBytes(&r.min));
            h.update(std.mem.asBytes(&r.max));
        }
        h.update(std.mem.asBytes(&self.max_gradient));
        h.update(std.mem.asBytes(&self.lipschitz));
        h.update(std.mem.asBytes(&self.majorant));
        h.update(std.mem.asBytes(&self.version));
        h.update(std.mem.asBytes(&self.attention));
        h.update(std.mem.asBytes(&self.changed_ns));
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

test "attention merges by max on magnitude and time separately, and the bound decays for any τ" {
    var a = Summary{ .attention = 2, .changed_ns = 5 * std.time.ns_per_s };
    const b = Summary{ .attention = 1, .changed_ns = 9 * std.time.ns_per_s };
    const m = Summary.merge(a, b);
    try std.testing.expectEqual(@as(f32, 2), m.attention);
    try std.testing.expectEqual(@as(u64, 9 * std.time.ns_per_s), m.changed_ns);
    try std.testing.expect(m.covers(a) and m.covers(b));
    try std.testing.expect(!a.covers(b) and !b.covers(a));
    // The bound at any time is at least each child's attention there.
    var t: u64 = 0;
    while (t <= 40 * std.time.ns_per_s) : (t += std.time.ns_per_s / 2) {
        try std.testing.expect(m.attentionAt(t, 3) >= a.attentionAt(t, 3));
        try std.testing.expect(m.attentionAt(t, 3) >= b.attentionAt(t, 3));
        try std.testing.expect(m.attentionAt(t, 0.5) >= b.attentionAt(t, 0.5));
    }
    // Exact at a leaf: a₀ at t₀, a₀/2 at t₀ + τ·ln 2, and nothing before it changed.
    try std.testing.expectEqual(@as(f64, 2), a.attentionAt(5 * std.time.ns_per_s, 3));
    try std.testing.expectEqual(@as(f64, 2), a.attentionAt(0, 3));
    const half: u64 = 5 * std.time.ns_per_s + @as(u64, @intFromFloat(3.0 * @log(2.0) * 1e9));
    try std.testing.expectApproxEqRel(@as(f64, 1), a.attentionAt(half, 3), 1e-6);
    a.attention = 0;
    try std.testing.expectEqual(@as(f64, 0), a.attentionAt(5 * std.time.ns_per_s, 3));
}
