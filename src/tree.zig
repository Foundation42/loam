//! tree — the sparse hierarchy and its published snapshots (spec §5.2,
//! §8, §15; brief R2, R3).
//!
//! An 8-way tree over the 20-bit lattice: node identity is a Morton
//! prefix at a level, children are octants, leaves are bricks. Nodes carry
//! conservative summaries and a Merkle hash. It is the SHARED NODE
//! REPRESENTATION the brief's R2 rules for spec §23 Q1: a node here is
//! what a wide8 node is in matryoshka — a cube with up to eight children
//! and a tight box — with a summary where wide8 has triangles.
//!
//! Snapshots are radix CoW commits (R3). A commit path-copies the nodes
//! above every dirty brick and shares every untouched subtree by
//! retaining it; a snapshot is immutable, refcounted, and read from any
//! thread without a lock. Untouched bricks are the SAME pointers in
//! consecutive snapshots, which is what lets G4 say "byte-identical" by
//! identity and G8 hash snapshot N while N+1 is being built.
//!
//! The identity tower: `vid` (which publish), `rootHash` (Merkle over
//! summaries and bricks — what the field IS), `contentHash` (root plus
//! fronts and clock — what the WORLD is). Standalone here; when loam is
//! mounted in a Substrate-backed host these are the same three names
//! matryoshka's asset packs already carry.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const summary = @import("summary.zig");
const brick = @import("brick.zig");
const front = @import("front.zig");

const Key = lattice.Key;
const Brick = brick.Brick;
const Summary = summary.Summary;
const Blake3 = std.crypto.hash.Blake3;

pub const Error = error{ OutOfMemory, GaugeConflict };

pub const ZERO_HASH = [_]u8{0} ** 32;

pub const Node = struct {
    key: Key,
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    summary: Summary = .{},
    hash: [32]u8 = ZERO_HASH,
    kind: union(enum) {
        inner: [8]?*Node,
        leaf: *Brick,
    },

    pub fn retain(self: *Node) void {
        _ = self.refs.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Node, gpa: std.mem.Allocator) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            switch (self.kind) {
                .inner => |ch| for (ch) |c| if (c) |n| n.release(gpa),
                .leaf => |b| b.release(gpa),
            }
            gpa.destroy(self);
        }
    }

    pub fn isLeaf(self: *const Node) bool {
        return self.kind == .leaf;
    }

    /// A leaf over a brick the caller has already retained for it.
    fn makeLeaf(gpa: std.mem.Allocator, b: *Brick) !*Node {
        const n = try gpa.create(Node);
        n.* = .{ .key = b.key, .summary = b.summary, .hash = b.hash, .kind = .{ .leaf = b } };
        return n;
    }

    /// An inner node over children the caller has already retained.
    fn makeInner(gpa: std.mem.Allocator, key: Key, children: [8]?*Node) !*Node {
        const n = try gpa.create(Node);
        var s = Summary{};
        var h = Blake3.init(.{});
        const raw = key.raw();
        h.update(std.mem.asBytes(&raw));
        for (children) |c| {
            if (c) |cn| {
                s = Summary.merge(s, cn.summary);
                h.update(&cn.hash);
            } else {
                h.update(&ZERO_HASH);
            }
        }
        var out: [32]u8 = undefined;
        h.final(&out);
        n.* = .{ .key = key, .summary = s, .hash = out, .kind = .{ .inner = children } };
        return n;
    }
};

/// One edit to the tree: put this brick at this key (`brick` retained by
/// the builder), or remove the brick at this key when null.
pub const Override = struct {
    key: Key,
    brick: ?*Brick,

    pub fn lessThan(_: void, a: Override, b: Override) bool {
        return a.key.raw() < b.key.raw();
    }
};

/// Build a new tree from `old` and a Morton-sorted list of overrides.
/// Untouched subtrees are retained, not copied. Returns null for an empty
/// tree. A brick placed over an existing brick of another gauge — or over
/// a subtree of finer bricks — is a GaugeConflict: refinement and
/// coarsening are fenced in P1 and nothing here does either silently.
pub fn build(gpa: std.mem.Allocator, old: ?*Node, overrides: []const Override) Error!?*Node {
    return buildNode(gpa, old, Key.init(lattice.ROOT_LEVEL, .{ 0, 0, 0 }), overrides);
}

fn buildNode(gpa: std.mem.Allocator, old: ?*Node, key: Key, overrides: []const Override) Error!?*Node {
    if (overrides.len == 0) {
        if (old) |o| o.retain();
        return old;
    }
    // An override that IS this cube: a brick at this level.
    if (overrides[0].key.eql(key)) {
        if (overrides.len != 1) return Error.GaugeConflict; // a brick and something finer inside it
        if (old) |o| if (!o.isLeaf()) return Error.GaugeConflict; // finer bricks already here
        const b = overrides[0].brick orelse return null;
        b.retain();
        return try Node.makeLeaf(gpa, b);
    }
    // Overrides finer than this cube: descend.
    if (old) |o| if (o.isLeaf()) return Error.GaugeConflict; // a coarser brick already here
    if (key.level <= lattice.MIN_LEVEL) return Error.GaugeConflict; // cannot be: overrides are >= MIN_LEVEL
    var children: [8]?*Node = .{ null, null, null, null, null, null, null, null };
    var made: usize = 0;
    errdefer for (children[0..made]) |c| if (c) |n| n.release(gpa);
    var any = false;
    var k: u4 = 0;
    var start: usize = 0;
    const o = key.origin();
    while (k < 8) : (k += 1) {
        const ck = Key.init(key.level - 1, lattice.childOrigin(key.level, o, @intCast(k)));
        const range = ck.mortonRange();
        var end = start;
        while (end < overrides.len and overrides[end].key.mortonCode() < range[1]) : (end += 1) {}
        const old_child: ?*Node = if (old) |on| on.kind.inner[k] else null;
        children[k] = try buildNode(gpa, old_child, ck, overrides[start..end]);
        made = k + 1;
        if (children[k] != null) any = true;
        start = end;
    }
    if (!any) return null;
    return try Node.makeInner(gpa, key, children);
}

/// An immutable published state of the world (spec §15).
pub const Snapshot = struct {
    gpa: std.mem.Allocator,
    refs: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),
    vid: u64,
    epoch: u64,
    time_ns: u64,
    seed: u64,
    root: ?*Node,
    brick_count: u32 = 0,
    node_count: u32 = 0,
    /// Every front, live or not, in id order. Owned.
    fronts: []front.Front = &.{},
    /// Bricks that will be operated on in the step that starts from
    /// here. Owned, Morton-sorted.
    active: []Key = &.{},
    /// Bricks the commit that made this snapshot touched. Owned, sorted.
    dirty: []Key = &.{},

    pub fn retain(self: *Snapshot) void {
        _ = self.refs.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *Snapshot) void {
        if (self.refs.fetchSub(1, .acq_rel) == 1) {
            if (self.root) |r| r.release(self.gpa);
            self.gpa.free(self.fronts);
            self.gpa.free(self.active);
            self.gpa.free(self.dirty);
            self.gpa.destroy(self);
        }
    }

    pub fn rootHash(self: *const Snapshot) [32]u8 {
        return if (self.root) |r| r.hash else ZERO_HASH;
    }

    pub fn rootSummary(self: *const Snapshot) Summary {
        return if (self.root) |r| r.summary else Summary{};
    }

    /// Root hash plus fronts plus clock: what the WORLD is.
    pub fn contentHash(self: *const Snapshot) [32]u8 {
        var h = Blake3.init(.{});
        const rh = self.rootHash();
        h.update(&rh);
        h.update(std.mem.asBytes(&self.epoch));
        h.update(std.mem.asBytes(&self.time_ns));
        for (self.fronts) |*f| f.hashInto(&h);
        for (self.active) |k| {
            const raw = k.raw();
            h.update(std.mem.asBytes(&raw));
        }
        var out: [32]u8 = undefined;
        h.final(&out);
        return out;
    }

    /// The leaf whose closed cube holds lattice point `p`, or null. A
    /// point on a shared face has two holders; the upper octant is tried
    /// first (the `Key.containing` convention) and the other is a
    /// fallback, so a point on the last face of the only brick is found.
    pub fn findLeaf(self: *const Snapshot, p: [3]i64) ?*const Brick {
        const r = self.root orelse return null;
        if (!r.key.holdsPoint(p)) return null;
        return descend(r, p);
    }

    fn descend(n: *const Node, p: [3]i64) ?*const Brick {
        switch (n.kind) {
            .leaf => |b| return b,
            .inner => |ch| {
                const half: i64 = @as(i64, 1) << (n.key.level - 1);
                const o = n.key.origin();
                var lo_ok: [3]bool = undefined;
                var hi_ok: [3]bool = undefined;
                inline for (0..3) |a| {
                    const mid: i64 = @as(i64, o[a]) + half;
                    hi_ok[a] = p[a] >= mid;
                    lo_ok[a] = p[a] <= mid;
                }
                // Upper-first order: octant bits set where p is above the
                // mid plane; on the plane both are candidates.
                var order: u4 = 8;
                while (order > 0) : (order -= 1) {
                    const k: u3 = @intCast(order - 1);
                    const okx = if (k & 1 != 0) hi_ok[0] else lo_ok[0];
                    const oky = if (k & 2 != 0) hi_ok[1] else lo_ok[1];
                    const okz = if (k & 4 != 0) hi_ok[2] else lo_ok[2];
                    if (!(okx and oky and okz)) continue;
                    if (ch[k]) |c| {
                        if (descend(c, p)) |b| return b;
                    }
                }
                return null;
            },
        }
    }

    /// Every leaf whose closed cube holds `p` (up to 8 on a corner).
    pub fn findAll(self: *const Snapshot, p: [3]i64, out: *[8]*const Brick) usize {
        const r = self.root orelse return 0;
        if (!r.key.holdsPoint(p)) return 0;
        var n: usize = 0;
        collect(r, p, out, &n);
        return n;
    }

    fn collect(n: *const Node, p: [3]i64, out: *[8]*const Brick, count: *usize) void {
        switch (n.kind) {
            .leaf => |b| {
                if (count.* < 8) {
                    out[count.*] = b;
                    count.* += 1;
                }
            },
            .inner => |ch| {
                const half: i64 = @as(i64, 1) << (n.key.level - 1);
                const o = n.key.origin();
                var k: u4 = 0;
                while (k < 8) : (k += 1) {
                    const c = ch[k] orelse continue;
                    var ok = true;
                    inline for (0..3) |a| {
                        const mid: i64 = @as(i64, o[a]) + half;
                        const upper = (k >> a) & 1 != 0;
                        if (upper and p[a] < mid) ok = false;
                        if (!upper and p[a] > mid) ok = false;
                    }
                    if (ok) collect(c, p, out, count);
                }
            },
        }
    }

    /// The node at exactly this key, or the leaf that covers it from
    /// above, or null when nothing is there.
    pub fn nodeAt(self: *const Snapshot, key: Key) ?*const Node {
        var n = self.root orelse return null;
        const o = key.origin();
        while (true) {
            if (n.key.level == key.level) return if (n.key.eql(key)) n else null;
            switch (n.kind) {
                .leaf => return n,
                .inner => |ch| {
                    const k = lattice.octantOf(n.key.level, n.key.origin(), o);
                    n = ch[k] orelse return null;
                },
            }
        }
    }

    /// The bricks that cover the cube `key`, as keys: the leaf already
    /// there (possibly coarser), the finer leaves already inside it, or
    /// — where nothing is — `key` itself and the empty children of any
    /// partly filled sub-cube, to be created at that level. Authoring
    /// and deposition go through this so a gauge is never placed over
    /// another. Appends; callers dedupe.
    pub fn coverCube(self: *const Snapshot, key: Key, gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(Key)) !void {
        const n = self.nodeAt(key) orelse {
            try out.append(gpa, key);
            return;
        };
        switch (n.kind) {
            .leaf => |b| try out.append(gpa, b.key),
            .inner => {
                const o = key.origin();
                var k: u4 = 0;
                while (k < 8) : (k += 1) {
                    try self.coverCube(Key.init(key.level - 1, lattice.childOrigin(key.level, o, @intCast(k))), gpa, out);
                }
            },
        }
    }

    /// Every leaf under a node, Morton order.
    pub fn leavesUnder(n: *const Node, gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(*const Brick)) !void {
        switch (n.kind) {
            .leaf => |b| try out.append(gpa, b),
            .inner => |ch| for (ch) |c| if (c) |cn| try leavesUnder(cn, gpa, out),
        }
    }

    /// Exact lookup of the brick with this key.
    pub fn brickAt(self: *const Snapshot, key: Key) ?*const Brick {
        var n = self.root orelse return null;
        const o = key.origin();
        while (true) {
            switch (n.kind) {
                .leaf => |b| return if (b.key.eql(key)) b else null,
                .inner => |ch| {
                    if (n.key.level <= key.level) return null;
                    const k = lattice.octantOf(n.key.level, n.key.origin(), o);
                    n = ch[k] orelse return null;
                },
            }
        }
    }

    /// Continuous reconstruction of `bit` at `p` (lattice units): zero
    /// outside every brick. Any holder of a shared point answers the
    /// same by the seam contract.
    pub fn sample(self: *const Snapshot, bit: u6, p: [3]f64) f32 {
        const b = self.findLeaf(.{ floorI(p[0]), floorI(p[1]), floorI(p[2]) }) orelse return null_or_zero;
        return b.trilinear(bit, p);
    }
    const null_or_zero: f32 = 0;

    /// Central-difference gradient at `p` with step `h`, per lattice unit.
    pub fn gradient(self: *const Snapshot, bit: u6, p: [3]f64, h: f64) [3]f64 {
        var g: [3]f64 = undefined;
        inline for (0..3) |a| {
            var pp = p;
            var pm = p;
            pp[a] += h;
            pm[a] -= h;
            g[a] = (@as(f64, self.sample(bit, pp)) - @as(f64, self.sample(bit, pm))) / (2 * h);
        }
        return g;
    }

    /// Depth-first, Morton order, every brick.
    pub fn forEachBrick(self: *const Snapshot, ctx: anytype, comptime f: fn (@TypeOf(ctx), *const Brick) void) void {
        if (self.root) |r| walk(r, ctx, f);
    }

    fn walk(n: *const Node, ctx: anytype, comptime f: fn (@TypeOf(ctx), *const Brick) void) void {
        switch (n.kind) {
            .leaf => |b| f(ctx, b),
            .inner => |ch| for (ch) |c| if (c) |cn| walk(cn, ctx, f),
        }
    }

    /// Every brick, Morton order. Caller owns the slice.
    pub fn bricks(self: *const Snapshot, gpa: std.mem.Allocator) ![]*const Brick {
        var list = std.ArrayList(*const Brick).init(gpa);
        errdefer list.deinit();
        const Ctx = struct { list: *std.ArrayList(*const Brick) };
        self.forEachBrick(Ctx{ .list = &list }, struct {
            fn f(c: Ctx, b: *const Brick) void {
                c.list.append(b) catch {};
            }
        }.f);
        return list.toOwnedSlice();
    }

    pub fn countNodes(self: *const Snapshot) struct { nodes: u32, bricks: u32 } {
        var nodes: u32 = 0;
        var leaves: u32 = 0;
        if (self.root) |r| countRec(r, &nodes, &leaves);
        return .{ .nodes = nodes, .bricks = leaves };
    }

    fn countRec(n: *const Node, nodes: *u32, leaves: *u32) void {
        nodes.* += 1;
        switch (n.kind) {
            .leaf => leaves.* += 1,
            .inner => |ch| for (ch) |c| if (c) |cn| countRec(cn, nodes, leaves),
        }
    }
};

pub fn floorI(v: f64) i64 {
    return @intFromFloat(@floor(v));
}

/// A snapshot over an empty tree — where every world starts.
pub fn emptySnapshot(gpa: std.mem.Allocator, seed: u64) !*Snapshot {
    const s = try gpa.create(Snapshot);
    s.* = .{ .gpa = gpa, .vid = 0, .epoch = 0, .time_ns = 0, .seed = seed, .root = null };
    return s;
}

test "build shares untouched subtrees and path-copies the rest" {
    const gpa = std.testing.allocator;
    const a = try Brick.create(gpa, Key.ofBrick(0, .{ 0, 0, 0 }));
    defer a.release(gpa);
    const b = try Brick.create(gpa, Key.ofBrick(0, .{ 8, 0, 0 }));
    defer b.release(gpa);
    const far = try Brick.create(gpa, Key.ofBrick(0, .{ 524288, 524288, 524288 }));
    defer far.release(gpa);
    a.finalize(gpa);
    b.finalize(gpa);
    far.finalize(gpa);
    var ov = [_]Override{ .{ .key = a.key, .brick = a }, .{ .key = far.key, .brick = far } };
    std.mem.sort(Override, &ov, {}, Override.lessThan);
    const r1 = (try build(gpa, null, &ov)).?;
    defer r1.release(gpa);
    try std.testing.expectEqual(@as(u32, 3), a.refs.load(.monotonic) + far.refs.load(.monotonic) - 1); // each retained once by its leaf
    var ov2 = [_]Override{.{ .key = b.key, .brick = b }};
    const r2 = (try build(gpa, r1, &ov2)).?;
    defer r2.release(gpa);
    // The far subtree is the same node in both roots: shared, not copied.
    const far_k = lattice.octantOf(lattice.ROOT_LEVEL, .{ 0, 0, 0 }, far.key.origin());
    try std.testing.expectEqual(r1.kind.inner[far_k].?, r2.kind.inner[far_k].?);
    // The near subtree is a new path.
    try std.testing.expect(r1.kind.inner[0].? != r2.kind.inner[0].?);
    // And the hashes differ while the shared child's does not.
    try std.testing.expect(!std.mem.eql(u8, &r1.hash, &r2.hash));
    try std.testing.expect(std.mem.eql(u8, &r1.kind.inner[far_k].?.hash, &r2.kind.inner[far_k].?.hash));
    // Removing b gives back r1's hash exactly.
    var ov3 = [_]Override{.{ .key = b.key, .brick = null }};
    const r3 = (try build(gpa, r2, &ov3)).?;
    defer r3.release(gpa);
    try std.testing.expect(std.mem.eql(u8, &r1.hash, &r3.hash));
}

test "a brick over a finer brick, or under a coarser one, is a GaugeConflict" {
    const gpa = std.testing.allocator;
    const fine = try Brick.create(gpa, Key.ofBrick(0, .{ 0, 0, 0 }));
    defer fine.release(gpa);
    fine.finalize(gpa);
    var ov = [_]Override{.{ .key = fine.key, .brick = fine }};
    const r1 = (try build(gpa, null, &ov)).?;
    defer r1.release(gpa);
    const coarse = try Brick.create(gpa, Key.ofBrick(1, .{ 0, 0, 0 }));
    defer coarse.release(gpa);
    coarse.finalize(gpa);
    var ov2 = [_]Override{.{ .key = coarse.key, .brick = coarse }};
    try std.testing.expectError(Error.GaugeConflict, build(gpa, r1, &ov2));
    const r2 = (try build(gpa, null, &ov2)).?;
    defer r2.release(gpa);
    try std.testing.expectError(Error.GaugeConflict, build(gpa, r2, &ov));
}

test "findLeaf resolves a shared face to a holder, and the last face of the only brick" {
    const gpa = std.testing.allocator;
    const a = try Brick.create(gpa, Key.ofBrick(0, .{ 0, 0, 0 }));
    defer a.release(gpa);
    const b = try Brick.create(gpa, Key.ofBrick(1, .{ 16, 0, 0 }));
    defer b.release(gpa);
    a.finalize(gpa);
    b.finalize(gpa);
    var ov = [_]Override{ .{ .key = a.key, .brick = a }, .{ .key = b.key, .brick = b } };
    std.mem.sort(Override, &ov, {}, Override.lessThan);
    const root = try build(gpa, null, &ov);
    const s = try gpa.create(Snapshot);
    s.* = .{ .gpa = gpa, .vid = 1, .epoch = 0, .time_ns = 0, .seed = 0, .root = root };
    defer s.release();
    try std.testing.expectEqual(a, s.findLeaf(.{ 3, 3, 3 }).?);
    try std.testing.expectEqual(b, s.findLeaf(.{ 20, 3, 3 }).?);
    // x = 8 is a's far face and nobody's near face: a holds it.
    try std.testing.expectEqual(a, s.findLeaf(.{ 8, 3, 3 }).?);
    // x = 16 is b's near face; a does not reach it.
    try std.testing.expectEqual(b, s.findLeaf(.{ 16, 0, 0 }).?);
    try std.testing.expect(s.findLeaf(.{ 12, 3, 3 }) == null);
    try std.testing.expect(s.findLeaf(.{ -1, 3, 3 }) == null);
    var all: [8]*const Brick = undefined;
    try std.testing.expectEqual(@as(usize, 1), s.findAll(.{ 8, 8, 8 }, &all));
    try std.testing.expectEqual(a, s.brickAt(a.key).?);
    try std.testing.expectEqual(b, s.brickAt(b.key).?);
    try std.testing.expect(s.brickAt(Key.ofBrick(0, .{ 16, 0, 0 })) == null);
    const c = s.countNodes();
    try std.testing.expectEqual(@as(u32, 2), c.bricks);
}
