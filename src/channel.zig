//! channel — what a field can hold, and the registry that names it (spec §6).
//!
//! A channel is one bit of a 64-bit mask and one scalar plane in a brick.
//! Bits 0..31 are the library's; 32..63 are the reserved user range an
//! application registers into by name. A vector quantity is three scalar
//! channels (velocity is `velocity_x/y/z`): one bit per plane keeps "absent
//! channels are unallocated" a statement about bits and nothing else.
//!
//! Names are for the dump, the seedbed and the C door; the hot path never
//! sees one. Every channel carries a clamp the commit applies, so a
//! Material that saturates at 1 and a Growth that cannot go negative are
//! declarations rather than operator manners.

const std = @import("std");

pub const Mask = u64;

/// The library's own channels. The spec's list (§6) plus the four the
/// brief's fronts and seedbed name — Light and Stimulus (what a front
/// reads), Damage (what a wound writes), Material (what a front laid in
/// Phase 1, kept for volumes) — and Phase 2's carrier, Surface (R8): a
/// signed implicit whose zero set is matter, negative inside, stored
/// truncated to ±SURFACE_BAND_CELLS cells of the brick's gauge and
/// composed by smooth union, never added.
pub const Channel = enum(u6) {
    density = 0,
    extinction = 1,
    albedo = 2,
    roughness = 3,
    emission = 4,
    velocity_x = 5,
    velocity_y = 6,
    velocity_z = 7,
    growth = 8,
    temperature = 9,
    age = 10,
    activity = 11,
    material = 12,
    light = 13,
    stimulus = 14,
    damage = 15,
    surface = 16,

    pub fn bit(self: Channel) u6 {
        return @intFromEnum(self);
    }
    pub fn mask(self: Channel) Mask {
        return @as(Mask, 1) << self.bit();
    }
};

pub const USER_FIRST: u6 = 32;
pub const COUNT: usize = 64;

/// The narrow band, in cells of the brick's gauge: a `surface` sample is
/// clamped to ±band, a sample at +band is "far" (absent), and a brick
/// holds a surface plane only where something is nearer than that. Three
/// cells: the cubic B-spline's support is two, so the zero set never sees
/// the truncation, and the frontier materialises a neighbour where the
/// band reaches a face. In lattice units the band is `band(spacing)`.
pub const SURFACE_BAND_CELLS: f32 = 3;

pub fn band(spacing: u32) f32 {
    return SURFACE_BAND_CELLS * @as(f32, @floatFromInt(spacing));
}

/// How the commit merges a delta into a sample. Additive is the rule;
/// Age is written once (a birth time); Activity is overwritten (a touch
/// time: the fed second a front last passed, so "warm" is `now − Activity`
/// and nothing decays — a decaying level kept fifty bricks changing for
/// forty steps after the last front stopped); Surface is a smooth union
/// with the collar radius carried on the op (R10).
pub const Rule = enum { add, set_once, touch, smin };

pub fn rule(bit: u6) Rule {
    if (bit == Channel.age.bit()) return .set_once;
    if (bit == Channel.activity.bit()) return .touch;
    if (bit == Channel.surface.bit()) return .smin;
    return .add;
}

/// What an absent channel reads as: zero, or "far" for the carrier.
pub fn absentValue(bit: u6, band_lu: f32) f32 {
    return if (bit == Channel.surface.bit()) band_lu else 0;
}

/// A sample that says nothing: zero, or at (or beyond) the band.
pub fn isAbsent(bit: u6, v: f32, band_lu: f32) bool {
    return if (bit == Channel.surface.bit()) v >= band_lu else v == 0;
}

/// A face sample that reaches across: above the change floor, or nearer
/// than the band — the frontier's test.
pub fn reaches(bit: u6, v: f32, band_lu: f32, eps: f32) bool {
    return if (bit == Channel.surface.bit()) v < band_lu else @abs(v) > eps;
}

/// Polynomial smooth minimum (Quilez): exactly min(a, b) where they
/// differ by k or more, at most k/4 below it where they agree. The far
/// value is the union's identity: nothing there blends with nothing.
/// k = 0 is the hard union, which is what a front's own consecutive
/// capsules need (a chain of smin'd capsules dips k/4 at every joint —
/// beads; the ledger records it, and the collar is P2.2's, G12).
pub fn smin(a: f32, b: f32, k: f32, band_lu: f32) f32 {
    if (a >= band_lu) return @min(b, band_lu);
    if (b >= band_lu) return a;
    if (k <= 0) return @min(a, b);
    const h = @max(k - @abs(a - b), 0) / k;
    return @min(a, b) - h * h * k * 0.25;
}

pub fn maskOf(bit: u6) Mask {
    return @as(Mask, 1) << bit;
}

pub fn has(m: Mask, bit: u6) bool {
    return (m >> bit) & 1 != 0;
}

/// Index of `bit`'s plane in a popcount-packed plane list.
pub fn planeIndex(m: Mask, bit: u6) usize {
    const below: Mask = if (bit == 0) 0 else (@as(Mask, 1) << bit) - 1;
    return @popCount(m & below);
}

pub const Clamp = struct {
    lo: f32 = -std.math.inf(f32),
    hi: f32 = std.math.inf(f32),

    pub fn apply(self: Clamp, v: f32) f32 {
        return @min(self.hi, @max(self.lo, v));
    }
};

pub const Error = error{ RegistryFull, NameTaken, NameTooLong, UnknownChannel };

pub const MAX_NAME = 32;

const Entry = struct {
    name_buf: [MAX_NAME]u8 = undefined,
    name_len: u8 = 0,
    clamp: Clamp = .{},
    present: bool = false,

    fn name(self: *const Entry) []const u8 {
        return self.name_buf[0..self.name_len];
    }
};

pub const Registry = struct {
    entries: [COUNT]Entry = [_]Entry{.{}} ** COUNT,

    pub fn init() Registry {
        var r = Registry{};
        inline for (std.meta.fields(Channel)) |f| {
            const ch: Channel = @enumFromInt(f.value);
            r.set(@intCast(f.value), f.name, defaultClamp(ch)) catch unreachable;
        }
        return r;
    }

    fn defaultClamp(ch: Channel) Clamp {
        return switch (ch) {
            .density, .extinction, .age, .activity, .temperature, .emission => .{ .lo = 0 },
            .albedo, .roughness, .material, .damage, .growth => .{ .lo = 0, .hi = 1 },
            .light, .stimulus, .surface => .{},
            .velocity_x, .velocity_y, .velocity_z => .{},
        };
    }

    fn set(self: *Registry, bit: u6, nm: []const u8, cl: Clamp) Error!void {
        if (nm.len > MAX_NAME) return Error.NameTooLong;
        var e = &self.entries[bit];
        @memcpy(e.name_buf[0..nm.len], nm);
        e.name_len = @intCast(nm.len);
        e.clamp = cl;
        e.present = true;
    }

    /// Register an application channel in the user range. Refuses a taken
    /// name loudly rather than aliasing it.
    pub fn register(self: *Registry, nm: []const u8, cl: Clamp) Error!u6 {
        if (self.find(nm) != null) return Error.NameTaken;
        var bit: u6 = USER_FIRST;
        while (true) : (bit += 1) {
            if (!self.entries[bit].present) {
                try self.set(bit, nm, cl);
                return bit;
            }
            if (bit == COUNT - 1) return Error.RegistryFull;
        }
    }

    pub fn find(self: *const Registry, nm: []const u8) ?u6 {
        for (self.entries, 0..) |e, i| {
            if (e.present and std.mem.eql(u8, e.name(), nm)) return @intCast(i);
        }
        return null;
    }

    pub fn name(self: *const Registry, bit: u6) []const u8 {
        return self.entries[bit].name();
    }

    pub fn isRegistered(self: *const Registry, bit: u6) bool {
        return self.entries[bit].present;
    }

    pub fn clamp(self: *const Registry, bit: u6) Clamp {
        return self.entries[bit].clamp;
    }

    /// Mask of every registered channel — the "all" a guard checks against.
    pub fn registeredMask(self: *const Registry) Mask {
        var m: Mask = 0;
        for (self.entries, 0..) |e, i| if (e.present) {
            m |= maskOf(@intCast(i));
        };
        return m;
    }
};

test "plane index is the popcount below the bit" {
    const m: Mask = Channel.density.mask() | Channel.material.mask() | Channel.light.mask();
    try std.testing.expectEqual(@as(usize, 0), planeIndex(m, Channel.density.bit()));
    try std.testing.expectEqual(@as(usize, 1), planeIndex(m, Channel.material.bit()));
    try std.testing.expectEqual(@as(usize, 2), planeIndex(m, Channel.light.bit()));
    try std.testing.expect(!has(m, Channel.growth.bit()));
}

test "smin: exact where apart, at most k/4 below where equal, far is the identity" {
    const bd = band(1);
    try std.testing.expectEqual(@as(f32, -1), smin(-1, 2, 0.5, bd));
    try std.testing.expectEqual(@as(f32, 1.0 - 0.25), smin(1, 1, 1, bd));
    try std.testing.expectEqual(@as(f32, 0.5), smin(bd, 0.5, 1, bd));
    try std.testing.expectEqual(@as(f32, 0.5), smin(0.5, bd, 1, bd));
    try std.testing.expectEqual(bd, smin(bd, std.math.inf(f32), 1, bd));
    try std.testing.expectEqual(@as(f32, 0.25), smin(0.25, 0.5, 0, bd));
    try std.testing.expect(smin(0.2, 0.3, 1, bd) < 0.2);
    try std.testing.expectEqual(Rule.smin, rule(Channel.surface.bit()));
    try std.testing.expectEqual(Rule.set_once, rule(Channel.age.bit()));
    try std.testing.expectEqual(Rule.touch, rule(Channel.activity.bit()));
    try std.testing.expectEqual(Rule.add, rule(Channel.growth.bit()));
    try std.testing.expect(isAbsent(Channel.surface.bit(), bd, bd) and !isAbsent(Channel.surface.bit(), 2.9, bd));
    try std.testing.expect(reaches(Channel.surface.bit(), 2.9, bd, 1e-6) and !reaches(Channel.surface.bit(), bd, bd, 1e-6));
}

test "registry: built-ins are named, user channels land at 32, a taken name is refused" {
    var r = Registry.init();
    try std.testing.expectEqualStrings("material", r.name(Channel.material.bit()));
    try std.testing.expectEqual(Channel.light.bit(), r.find("light").?);
    const moisture = try r.register("moisture", .{ .lo = 0, .hi = 1 });
    try std.testing.expectEqual(USER_FIRST, moisture);
    try std.testing.expectError(Error.NameTaken, r.register("moisture", .{}));
    try std.testing.expectError(Error.NameTaken, r.register("density", .{}));
    try std.testing.expectEqual(@as(f32, 1), r.clamp(Channel.material.bit()).apply(3.0));
    try std.testing.expectEqual(@as(f32, 0), r.clamp(Channel.growth.bit()).apply(-1.0));
}
