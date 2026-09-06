//! ray — a traversal cursor over the tree (spec §8, §13; brief G6, P1.1).
//!
//! The stub ray the brief allows: a segment walks the tree near-to-far,
//! rejects subtrees from summaries alone, and hands back the bricks it
//! would sample. Matryoshka owns transport, budgets and stepping; this
//! owns "which regions, in what order, and why not the rest".
//!
//! Rejection, in order: the node's channel mask cannot answer the query;
//! the tracked ranges of the requested channels are all ≤ 0 (an optically
//! empty subtree); the segment misses the node's tight box. The last is
//! the geometric test; the first two are what the summaries buy, and
//! `use_summaries = false` turns them off so the gate can measure exactly
//! that — and so the seedbed can print it (`--no-skip`).
//!
//! `traceSurface` is the carrier's leaf (Phase 2, R8): a sphere tracer
//! stepped by |φ|/L with L the brick's Lipschitz bound from its summary,
//! over the leaves the cursor hands it. A sound L means a step never
//! lands inside; G11 counts the steps that do, and the mutation that
//! doubles the step is what makes the count move.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const summary = @import("summary.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");

const Brick = brick.Brick;
const Node = tree.Node;

pub const QueryClass = enum { primary, shadow, volume, emission };

pub const Query = struct {
    origin: [3]f64,
    dir: [3]f64,
    t_min: f64 = 0,
    t_max: f64 = std.math.inf(f64),
    channels: channel.Mask,
    class: QueryClass = .primary,
    error_tolerance: f32 = 0,
    /// The G6 mutation, as an instrument: false visits every node the
    /// segment crosses.
    use_summaries: bool = true,
};

pub const RegionView = struct {
    brick: *const Brick,
    t_enter: f64,
    t_exit: f64,

    pub fn sample(self: RegionView, bit: u6, p: [3]f64) f32 {
        return self.brick.spline(bit, p);
    }
};

pub const Stats = struct {
    nodes_tested: u64 = 0,
    nodes_rejected_mask: u64 = 0,
    nodes_rejected_range: u64 = 0,
    nodes_rejected_box: u64 = 0,
    leaves_returned: u64 = 0,
};

const Entry = struct { node: *const Node, t_enter: f64, t_exit: f64 };

fn nearer(_: void, a: Entry, b: Entry) std.math.Order {
    return std.math.order(a.t_enter, b.t_enter);
}

/// Strict near-to-far: a priority queue on entry distance, not a stack.
/// A stack with sibling sorting is not enough — a near parent's far child
/// can lie beyond a far sibling's near child, and a consumer integrating
/// transmittance needs the regions in order to stop early.
pub const Cursor = struct {
    snapshot: *const tree.Snapshot,
    query: Query,
    inv: [3]f64,
    queue: std.PriorityQueue(Entry, void, nearer),
    stats: Stats = .{},

    pub fn init(gpa: std.mem.Allocator, snapshot: *const tree.Snapshot, q: Query) !Cursor {
        var c = Cursor{ .snapshot = snapshot, .query = q, .inv = undefined, .queue = std.PriorityQueue(Entry, void, nearer).init(gpa, {}) };
        inline for (0..3) |a| c.inv[a] = if (q.dir[a] != 0) 1.0 / q.dir[a] else std.math.inf(f64);
        if (snapshot.root) |r| {
            c.stats.nodes_tested += 1;
            if (c.test_(r)) |hit| try c.queue.add(.{ .node = r, .t_enter = hit[0], .t_exit = hit[1] });
        }
        return c;
    }

    pub fn deinit(self: *Cursor) void {
        self.queue.deinit();
    }

    /// The next brick the query should sample, nearest first. Null when
    /// the segment is exhausted.
    pub fn next(self: *Cursor) !?RegionView {
        while (self.queue.removeOrNull()) |e| {
            switch (e.node.kind) {
                .leaf => |b| {
                    self.stats.leaves_returned += 1;
                    return .{ .brick = b, .t_enter = e.t_enter, .t_exit = e.t_exit };
                },
                .inner => |ch| {
                    for (ch) |c| {
                        const cn = c orelse continue;
                        self.stats.nodes_tested += 1;
                        const ct = self.test_(cn) orelse continue;
                        try self.queue.add(.{ .node = cn, .t_enter = ct[0], .t_exit = ct[1] });
                    }
                },
            }
        }
        return null;
    }

    /// Accept a node, returning the segment's [t_enter, t_exit] through
    /// its box, or null with the reason counted.
    fn test_(self: *Cursor, n: *const Node) ?[2]f64 {
        const q = &self.query;
        var lo: [3]f64 = undefined;
        var hi: [3]f64 = undefined;
        if (q.use_summaries) {
            const s = &n.summary;
            if ((s.mask & q.channels) == 0) {
                self.stats.nodes_rejected_mask += 1;
                return null;
            }
            if (!relevant(s, q)) {
                self.stats.nodes_rejected_range += 1;
                return null;
            }
            if (s.isEmpty()) {
                self.stats.nodes_rejected_box += 1;
                return null;
            }
            inline for (0..3) |a| {
                lo[a] = @floatFromInt(s.lo[a]);
                hi[a] = @floatFromInt(s.hi[a]);
            }
        } else {
            const o = n.key.origin();
            const side: f64 = @floatFromInt(n.key.side());
            inline for (0..3) |a| {
                lo[a] = @floatFromInt(o[a]);
                hi[a] = lo[a] + side;
            }
        }
        const r = slab(q.origin, self.inv, lo, hi, q.t_min, q.t_max) orelse {
            self.stats.nodes_rejected_box += 1;
            return null;
        };
        return r;
    }
};

pub const Hit = struct {
    t: f64,
    p: [3]f64,
    /// The unit gradient of the carrier at the hit: the outward normal.
    n: [3]f64,
    /// The carrier's value where the march stopped, |φ| ≤ eps.
    phi: f32,
};

pub const TraceOptions = struct {
    /// The step is step_scale · |φ| / L; 1 is the sound step, 2 the G11
    /// mutation.
    step_scale: f64 = 1.0,
    /// A point within this of the zero set is the hit, lattice units.
    eps: f64 = 1e-3,
    /// Never step less than this: the march converges linearly at a
    /// grazing angle and must end.
    min_step: f64 = 1e-4,
    max_steps: u32 = 1024,
};

pub const TraceStats = struct {
    steps: u64 = 0,
    /// Steps that landed inside by more than eps: with a sound L, none.
    overshoots: u64 = 0,
    leaves: u64 = 0,
    /// Marches that ran out of steps before reaching eps.
    stalls: u64 = 0,
};

/// March the segment from t_min to t_max against the carrier's zero set:
/// the first point where φ ≤ eps, found by stepping |φ|/L inside each
/// leaf the cursor hands over, near to far. A ray that starts inside a
/// leaf's surface is a hit at its entry. Null where the segment meets no
/// surface.
pub fn traceSurface(gpa: std.mem.Allocator, snap: *const tree.Snapshot, origin: [3]f64, dir: [3]f64, t_min: f64, t_max: f64, opts: TraceOptions, stats: ?*TraceStats) !?Hit {
    const sbit = channel.Channel.surface.bit();
    var cur = try Cursor.init(gpa, snap, .{ .origin = origin, .dir = dir, .t_min = t_min, .t_max = t_max, .channels = channel.Channel.surface.mask() });
    defer cur.deinit();
    var steps: u32 = 0;
    while (try cur.next()) |rv| {
        if (stats) |s| s.leaves += 1;
        const b = rv.brick;
        const L: f64 = @max(@as(f64, b.summary.lipschitz), 1e-6);
        var t = @max(rv.t_enter, t_min);
        var prev_t: ?f64 = null;
        var prev_phi: f32 = 0;
        while (t <= rv.t_exit) {
            const p = [3]f64{ origin[0] + dir[0] * t, origin[1] + dir[1] * t, origin[2] + dir[2] * t };
            const phi = b.spline(sbit, p);
            steps += 1;
            if (stats) |s| s.steps += 1;
            if (@as(f64, phi) <= opts.eps) {
                var ht = t;
                var hphi = phi;
                if (@as(f64, phi) < -opts.eps) {
                    // Inside by more than eps: an overshoot (or an entry
                    // inside). Bisect back to the crossing when there is a
                    // point outside to bisect from.
                    if (stats) |s| if (prev_t != null) {
                        s.overshoots += 1;
                    };
                    if (prev_t) |pt| {
                        var lo = pt;
                        var hi = t;
                        var lo_phi = prev_phi;
                        _ = &lo_phi;
                        var it: u32 = 0;
                        while (it < 40) : (it += 1) {
                            const mid = 0.5 * (lo + hi);
                            const mp = [3]f64{ origin[0] + dir[0] * mid, origin[1] + dir[1] * mid, origin[2] + dir[2] * mid };
                            const mphi = b.spline(sbit, mp);
                            if (mphi > 0) lo = mid else hi = mid;
                        }
                        ht = hi;
                        const hp = [3]f64{ origin[0] + dir[0] * ht, origin[1] + dir[1] * ht, origin[2] + dir[2] * ht };
                        hphi = b.spline(sbit, hp);
                    }
                }
                const hp = [3]f64{ origin[0] + dir[0] * ht, origin[1] + dir[1] * ht, origin[2] + dir[2] * ht };
                const jet = b.splineJet(sbit, hp);
                var n = [3]f64{ jet.grad[0], jet.grad[1], jet.grad[2] };
                const nl = @sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
                if (nl > 1e-12) {
                    n[0] /= nl;
                    n[1] /= nl;
                    n[2] /= nl;
                }
                return .{ .t = ht, .p = hp, .n = n, .phi = hphi };
            }
            if (steps >= opts.max_steps) {
                if (stats) |s| s.stalls += 1;
                return null;
            }
            prev_t = t;
            prev_phi = phi;
            const step = @max(opts.min_step, opts.step_scale * @as(f64, phi) / L);
            if (t == rv.t_exit) break;
            t = @min(t + step, rv.t_exit);
        }
    }
    return null;
}

/// A summary can answer the query: some requested channel with a tracked
/// range is above zero — or, for the carrier, at or below it, since a
/// subtree whose surface minimum is positive holds no zero set (the
/// reconstruction is a convex combination of the coefficients) — or
/// some requested channel without one is present.
fn relevant(s: *const summary.Summary, q: *const Query) bool {
    var untracked_present = false;
    var tracked_requested = false;
    var bit: u6 = 0;
    while (true) : (bit += 1) {
        if (channel.has(q.channels, bit) and channel.has(s.mask, bit)) {
            if (s.rangeOf(bit)) |r| {
                tracked_requested = true;
                if (bit == channel.Channel.surface.bit()) {
                    if (!r.isEmpty() and r.min <= 0) return true;
                } else if (r.positive()) return true;
            } else {
                untracked_present = true;
            }
        }
        if (bit == 63) break;
    }
    return untracked_present;
}

/// Segment/box slab test with an inclusive box; a zero-thickness box
/// (a single lattice point of support) still intersects.
pub fn slab(o: [3]f64, inv: [3]f64, lo: [3]f64, hi: [3]f64, t_min: f64, t_max: f64) ?[2]f64 {
    var t0 = t_min;
    var t1 = t_max;
    inline for (0..3) |a| {
        if (std.math.isInf(inv[a])) {
            if (o[a] < lo[a] or o[a] > hi[a]) return null;
        } else {
            var ta = (lo[a] - o[a]) * inv[a];
            var tb = (hi[a] - o[a]) * inv[a];
            if (ta > tb) {
                const tmp = ta;
                ta = tb;
                tb = tmp;
            }
            if (ta > t0) t0 = ta;
            if (tb < t1) t1 = tb;
            if (t0 > t1) return null;
        }
    }
    return .{ t0, t1 };
}

test "slab: hits, misses, and a ray parallel to a face" {
    const inv = [3]f64{ 1, std.math.inf(f64), std.math.inf(f64) };
    try std.testing.expect(slab(.{ -1, 0.5, 0.5 }, inv, .{ 0, 0, 0 }, .{ 1, 1, 1 }, 0, 10) != null);
    try std.testing.expect(slab(.{ -1, 1.5, 0.5 }, inv, .{ 0, 0, 0 }, .{ 1, 1, 1 }, 0, 10) == null);
    const r = slab(.{ -1, 0.5, 0.5 }, inv, .{ 0, 0, 0 }, .{ 1, 1, 1 }, 0, 10).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1), r[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2), r[1], 1e-12);
    // Behind the origin: t_max limits.
    try std.testing.expect(slab(.{ 5, 0.5, 0.5 }, inv, .{ 0, 0, 0 }, .{ 1, 1, 1 }, 0, 10) == null);
}
