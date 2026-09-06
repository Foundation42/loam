//! rng — counter-based randomness (spec §16, loop-loft G1).
//!
//! No sequential draws anywhere. Every random number is a hash of (world
//! seed, who is asking, which epoch, which counter), so the value a region
//! or a front sees does not depend on how many other regions or fronts
//! drew before it — parallel order cannot reach the result, which is what
//! lets G1 hold under a job system. "Per-region random streams derive from
//! stable region identity plus simulation epoch" is `Stream.region`.

const std = @import("std");

/// splitmix64's finaliser: a good 64-bit mixer, and the one the toy's
/// mulberry32 is a 32-bit cousin of.
pub fn mix(v: u64) u64 {
    var z = v +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

pub fn hash4(seed: u64, a: u64, b: u64, c: u64) u64 {
    return mix(mix(mix(mix(seed) ^ a) ^ b) ^ c);
}

/// [0, 1) from the top 24 bits, so the f32 is exact.
pub fn unitOf(h: u64) f32 {
    return @as(f32, @floatFromInt(h >> 40)) * (1.0 / 16777216.0);
}

/// A stream keyed to one asker in one epoch; `counter` advances per draw.
pub const Stream = struct {
    seed: u64,
    who: u64,
    epoch: u64,
    counter: u64 = 0,

    pub fn region(seed: u64, key_raw: u64, epoch: u64) Stream {
        return .{ .seed = seed, .who = key_raw, .epoch = epoch };
    }

    pub fn front(seed: u64, front_id: u32, epoch: u64) Stream {
        return .{ .seed = seed, .who = 0xF000_0000_0000_0000 | @as(u64, front_id), .epoch = epoch };
    }

    pub fn next(self: *Stream) u64 {
        const h = hash4(self.seed, self.who, self.epoch, self.counter);
        self.counter += 1;
        return h;
    }

    pub fn unit(self: *Stream) f32 {
        return unitOf(self.next());
    }

    /// ~Gaussian in ±3, the toy's `grand`: three uniforms summed.
    pub fn gauss(self: *Stream) f32 {
        return (self.unit() + self.unit() + self.unit()) * 2 - 3;
    }

    pub fn below(self: *Stream, n: u32) u32 {
        return @intCast((self.next() >> 32) % n);
    }
};

test "a stream is a function of (seed, who, epoch, counter) and nothing else" {
    var a = Stream.region(7, 1234, 5);
    var b = Stream.region(7, 1234, 5);
    try std.testing.expectEqual(a.next(), b.next());
    try std.testing.expectEqual(a.next(), b.next());
    var c = Stream.region(8, 1234, 5);
    try std.testing.expect(a.next() != c.next());
    var d = Stream.region(7, 1234, 6);
    try std.testing.expect(b.next() != d.next());
    // Units are in [0, 1) and the gauss stays in its band.
    var s = Stream.front(1, 0, 0);
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const u = s.unit();
        try std.testing.expect(u >= 0 and u < 1);
        const g = s.gauss();
        try std.testing.expect(g >= -3 and g <= 3);
    }
}
