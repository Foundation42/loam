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
/// brief's fronts and seedbed name: Material (what a front deposits),
/// Light and Stimulus (what it reads), Damage (what a wound writes).
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

    pub fn bit(self: Channel) u6 {
        return @intFromEnum(self);
    }
    pub fn mask(self: Channel) Mask {
        return @as(Mask, 1) << self.bit();
    }
};

pub const USER_FIRST: u6 = 32;
pub const COUNT: usize = 64;

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
            .density, .extinction, .age, .temperature, .emission => .{ .lo = 0 },
            .albedo, .roughness, .activity, .material, .damage, .growth => .{ .lo = 0, .hi = 1 },
            .light, .stimulus => .{},
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
