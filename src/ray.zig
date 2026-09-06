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
        return self.brick.trilinear(bit, p);
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

/// A summary can answer the query: some requested channel with a tracked
/// range is above zero, or some requested channel without one is present.
fn relevant(s: *const summary.Summary, q: *const Query) bool {
    var untracked_present = false;
    var tracked_requested = false;
    var bit: u6 = 0;
    while (true) : (bit += 1) {
        if (channel.has(q.channels, bit) and channel.has(s.mask, bit)) {
            if (s.rangeOf(bit)) |r| {
                tracked_requested = true;
                if (r.positive()) return true;
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
