//! guards — every invariant, asserted on demand, with a self-test that
//! corrupts each and proves the guard fires (brief §2, "Guards").
//!
//! House practice after the Sep 4 lattice campaign, where four defects
//! produced plausible output instead of errors. A guard that has never
//! fired is decoration; `tests.zig` corrupts a snapshot per invariant.
//!
//! Invariants:
//!   - SUMMARY: a leaf's summary is its brick's, recomputed; a parent's
//!     covers each child's (bounds, mask, ranges, gradient, majorant,
//!     version). Conservative all the way up.
//!   - PLANES: `planes.len == popCount(mask)`; no plane says nothing over
//!     the brick's own samples (absent channels are not instantiated).
//!   - SEAM: every holder of a shared lattice point reconstructs the same
//!     value there, for every channel any holder has; and at points
//!     between shared samples on a shared face, too.
//!   - HALO: every halo entry of every brick is what the anchor rule one
//!     layer deeper says — the finest holder's sample, the coarse
//!     interpolant off the coarse lattice, the absent value in the void —
//!     recomputed here from the snapshot by the slow general path. Same-
//!     gauge neighbours then share their 64 coefficients across the face
//!     and the B-spline is C2 there; G9 measures it.
//!   - ACTIVE: every active key is a brick or a live front's brick; every
//!     dirty key is a brick; both are sorted and unique.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const summary = @import("summary.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");

const Brick = brick.Brick;
const Key = lattice.Key;

pub const Violation = error{
    SummaryNotConservative,
    LeafSummaryStale,
    PlaneCountMismatch,
    AbsentChannelAllocated,
    SeamDisagrees,
    HaloStale,
    ActiveKeyUnknown,
    DirtyKeyUnknown,
    KeysNotSortedUnique,
    OutOfMemory,
};

pub fn check(s: *const tree.Snapshot) Violation!void {
    if (s.root) |r| try checkNode(s.gpa, r);
    try checkSeams(s);
    try checkHalos(s);
    try checkKeys(s);
}

fn checkNode(gpa: std.mem.Allocator, n: *const tree.Node) Violation!void {
    switch (n.kind) {
        .leaf => |b| {
            if (b.planes.len != @popCount(b.mask)) return Violation.PlaneCountMismatch;
            var bit: u6 = 0;
            while (true) : (bit += 1) {
                if (b.plane(bit)) |pl| {
                    if (b.planeAbsent(bit, pl)) return Violation.AbsentChannelAllocated;
                }
                if (bit == 63) break;
            }
            // Recompute through a scratch clone so the brick is untouched.
            const c = Brick.clone(gpa, b) catch return Violation.OutOfMemory;
            defer c.release(gpa);
            c.finalize(gpa);
            if (!std.meta.eql(c.summary, b.summary)) return Violation.LeafSummaryStale;
            if (!std.meta.eql(n.summary, b.summary)) return Violation.LeafSummaryStale;
        },
        .inner => |ch| {
            for (ch) |c| {
                const cn = c orelse continue;
                if (!n.summary.covers(cn.summary)) return Violation.SummaryNotConservative;
                try checkNode(gpa, cn);
            }
        },
    }
}

fn checkSeams(s: *const tree.Snapshot) Violation!void {
    const bs = s.bricks(s.gpa) catch return Violation.OutOfMemory;
    defer s.gpa.free(bs);
    var holders: [8]*const Brick = undefined;
    for (bs) |b| {
        const sp: f64 = @floatFromInt(b.spacing());
        var k: u32 = 0;
        while (k < brick.N) : (k += 1) {
            var j: u32 = 0;
            while (j < brick.N) : (j += 1) {
                var i: u32 = 0;
                while (i < brick.N) : (i += 1) {
                    if (!Brick.isBoundary(i, j, k)) continue;
                    const p = b.pointAt(i, j, k);
                    const q = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
                    const nh = s.findAll(.{ p[0], p[1], p[2] }, &holders);
                    if (nh <= 1) continue;
                    try agree(holders[0..nh], q);
                    // Between samples along the face, toward each in-brick neighbour.
                    const half = sp * 0.5;
                    inline for (0..3) |a| {
                        var q2 = q;
                        q2[a] += half;
                        const p2 = [3]i64{ tree.floorI(q2[0]), tree.floorI(q2[1]), tree.floorI(q2[2]) };
                        var h2: [8]*const Brick = undefined;
                        const n2 = s.findAll(p2, &h2);
                        if (n2 > 1) try agree(h2[0..n2], q2);
                    }
                }
            }
        }
    }
}

fn agree(hs_all: []const *const Brick, q: [3]f64) Violation!void {
    // Only holders whose closed cube contains the REAL point may be
    // compared: a probe half a step past a face lies inside one holder
    // and outside the other, whose reconstruction clamps at its face.
    var hs: [8]*const Brick = undefined;
    var n: usize = 0;
    for (hs_all) |h| {
        if (holdsReal(h.key, q)) {
            hs[n] = h;
            n += 1;
        }
    }
    if (n < 2) return;
    var mask: channel.Mask = 0;
    for (hs[0..n]) |h| mask |= h.mask;
    var bit: u6 = 0;
    while (true) : (bit += 1) {
        if (channel.has(mask, bit)) {
            const v0 = hs[0].trilinear(bit, q);
            for (hs[1..n]) |h| {
                const v = h.trilinear(bit, q);
                if (@abs(v - v0) > 1e-5 * @max(1.0, @abs(v0))) return Violation.SeamDisagrees;
            }
        }
        if (bit == 63) break;
    }
}

/// The value a halo entry must hold, from the snapshot alone: the finest
/// holder of the point (ties by lowest key — equal by the seam contract),
/// its sample or its interpolant; the absent value where nothing holds it.
pub fn expectedHalo(s: *const tree.Snapshot, target: *const Brick, bit: u6, p: [3]i64) f32 {
    const bd = target.band();
    if (p[0] < 0 or p[1] < 0 or p[2] < 0 or p[0] > lattice.CELLS or p[1] > lattice.CELLS or p[2] > lattice.CELLS) return channel.absentValue(bit, bd);
    var hs: [8]*const Brick = undefined;
    const n = s.findAll(p, &hs);
    if (n == 0) return channel.absentValue(bit, bd);
    var finest = hs[0];
    for (hs[1..n]) |h| {
        if (h.key.level < finest.key.level or (h.key.level == finest.key.level and h.key.raw() < finest.key.raw())) finest = h;
    }
    var v: f32 = undefined;
    if (finest.localOf(p)) |l| {
        v = finest.get(bit, l[0], l[1], l[2]);
    } else {
        v = finest.trilinear(bit, .{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) });
    }
    if (bit == channel.Channel.surface.bit()) v = @min(v, bd);
    return v;
}

fn checkHalos(s: *const tree.Snapshot) Violation!void {
    const bs = s.bricks(s.gpa) catch return Violation.OutOfMemory;
    defer s.gpa.free(bs);
    for (bs) |b| {
        var bk: u32 = 0;
        while (bk < brick.HN) : (bk += 1) {
            var bj: u32 = 0;
            while (bj < brick.HN) : (bj += 1) {
                var bi: u32 = 0;
                while (bi < brick.HN) : (bi += 1) {
                    const hb = [3]u32{ bi, bj, bk };
                    if (!Brick.isHalo(hb)) continue;
                    const p = b.blockPoint(hb);
                    const idx = Brick.bindex(bi, bj, bk);
                    var mask = b.mask;
                    while (mask != 0) {
                        const bit: u6 = @intCast(@ctz(mask));
                        mask &= mask - 1;
                        if (b.plane(bit).?[idx] != expectedHalo(s, b, bit, p)) return Violation.HaloStale;
                    }
                }
            }
        }
    }
}

pub fn holdsReal(k: Key, q: [3]f64) bool {
    const o = k.origin();
    const side: f64 = @floatFromInt(k.side());
    inline for (0..3) |a| {
        const lo: f64 = @floatFromInt(o[a]);
        if (q[a] < lo or q[a] > lo + side) return false;
    }
    return true;
}

fn checkKeys(s: *const tree.Snapshot) Violation!void {
    try sortedUnique(s.active);
    try sortedUnique(s.dirty);
    for (s.dirty) |k| {
        if (s.brickAt(k) == null) return Violation.DirtyKeyUnknown;
    }
    for (s.active) |k| {
        if (s.brickAt(k) != null) continue;
        var ok = false;
        for (s.fronts) |f| {
            if (f.alive and f.brick.eql(k)) ok = true;
        }
        if (!ok) return Violation.ActiveKeyUnknown;
    }
}

fn sortedUnique(keys: []const Key) Violation!void {
    var i: usize = 1;
    while (i < keys.len) : (i += 1) {
        if (keys[i - 1].raw() >= keys[i].raw()) return Violation.KeysNotSortedUnique;
    }
}
