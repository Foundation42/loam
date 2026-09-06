//! dump — a snapshot as one canonical struple map.
//!
//! The dump is a gate artefact, not a persistence format (R3 says do not
//! build one). Two worlds fed the same inputs must produce byte-identical
//! dumps, so the format is fixed by the content and nothing else:
//! struple's `appendMap` sorts keys, bricks ride in key order, fronts in
//! id order, planes as little-endian f32 bytes so the reader gets exact
//! values with `array('f')`. A plane is the whole 11³ block, halo
//! included (R7): what a reader reconstructs from is what it gets. The
//! struple Python port reads this with no loam code — `tools/read_dump.py`
//! and `py/loam/dump.py`.

const std = @import("std");
const struple = @import("struple");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");
const front = @import("front.zig");
const world_mod = @import("world.zig");

const Brick = brick.Brick;

pub const FORMAT: i64 = 2;

const Entry = [2][]const u8;

fn key(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendString(s);
    return p.bytes();
}

fn int(a: std.mem.Allocator, v: i64) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendInt(v);
    return p.bytes();
}

fn uint(a: std.mem.Allocator, v: u64) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendUint(v);
    return p.bytes();
}

fn f64v(a: std.mem.Allocator, v: f64) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendF64(v);
    return p.bytes();
}

fn bytes(a: std.mem.Allocator, v: []const u8) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendBytes(v);
    return p.bytes();
}

fn str(a: std.mem.Allocator, v: []const u8) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendString(v);
    return p.bytes();
}

fn boolean(a: std.mem.Allocator, v: bool) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendBool(v);
    return p.bytes();
}

fn map(a: std.mem.Allocator, entries: []const Entry) ![]const u8 {
    var p = struple.Packer.init(a);
    try p.appendMap(entries);
    return p.bytes();
}

fn array(a: std.mem.Allocator, items: []const []const u8) ![]const u8 {
    var inner = struple.Packer.init(a);
    for (items) |it| try inner.appendRaw(it);
    var p = struple.Packer.init(a);
    try p.appendArray(inner.bytes());
    return p.bytes();
}

fn f64array(a: std.mem.Allocator, vs: []const f64) ![]const u8 {
    var inner = struple.Packer.init(a);
    for (vs) |v| try inner.appendF64(v);
    var p = struple.Packer.init(a);
    try p.appendArray(inner.bytes());
    return p.bytes();
}

fn intarray(a: std.mem.Allocator, vs: []const i64) ![]const u8 {
    var inner = struple.Packer.init(a);
    for (vs) |v| try inner.appendInt(v);
    var p = struple.Packer.init(a);
    try p.appendArray(inner.bytes());
    return p.bytes();
}

/// Encode the world's published snapshot. The caller owns the bytes.
pub fn write(gpa: std.mem.Allocator, w: *const world_mod.World) ![]u8 {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();
    const snap = w.published();

    var top = std.ArrayList(Entry).init(a);
    try top.append(.{ try key(a, "fmt"), try int(a, FORMAT) });
    try top.append(.{ try key(a, "vid"), try uint(a, snap.vid) });
    try top.append(.{ try key(a, "epoch"), try uint(a, snap.epoch) });
    try top.append(.{ try key(a, "time_ns"), try uint(a, snap.time_ns) });
    try top.append(.{ try key(a, "seed"), try uint(a, snap.seed) });
    try top.append(.{ try key(a, "lattice_bits"), try int(a, lattice.BITS) });
    try top.append(.{ try key(a, "brick_cells"), try int(a, brick.CELLS) });
    try top.append(.{ try key(a, "halo"), try int(a, 1) });
    try top.append(.{ try key(a, "band_cells"), try f64v(a, channel.SURFACE_BAND_CELLS) });
    try top.append(.{ try key(a, "slots"), try int(a, front.SLOTS) });
    const rh = snap.rootHash();
    try top.append(.{ try key(a, "root_hash"), try bytes(a, &rh) });
    const ch = snap.contentHash();
    try top.append(.{ try key(a, "content_hash"), try bytes(a, &ch) });

    // channels: {name: bit}
    var chan = std.ArrayList(Entry).init(a);
    var bit: u6 = 0;
    while (true) : (bit += 1) {
        if (w.registry.isRegistered(bit)) try chan.append(.{ try key(a, w.registry.name(bit)), try int(a, bit) });
        if (bit == 63) break;
    }
    try top.append(.{ try key(a, "channels"), try map(a, chan.items) });

    // bricks, key order
    const bs = try snap.bricks(a);
    var blist = std.ArrayList([]const u8).init(a);
    for (bs) |b| {
        var be = std.ArrayList(Entry).init(a);
        try be.append(.{ try key(a, "key"), try uint(a, b.key.raw()) });
        try be.append(.{ try key(a, "gauge"), try int(a, b.gauge()) });
        const o = b.origin();
        try be.append(.{ try key(a, "origin"), try intarray(a, &.{ o[0], o[1], o[2] }) });
        try be.append(.{ try key(a, "version"), try int(a, b.version) });
        try be.append(.{ try key(a, "mask"), try uint(a, b.mask) });
        var planes = std.ArrayList(Entry).init(a);
        var pb: u6 = 0;
        while (true) : (pb += 1) {
            if (b.plane(pb)) |pl| {
                var raw = try a.alloc(u8, brick.SAMPLES * 4);
                for (pl, 0..) |v, i| std.mem.writeInt(u32, raw[i * 4 ..][0..4], @bitCast(v), .little);
                try planes.append(.{ try key(a, w.registry.name(pb)), try bytes(a, raw) });
            }
            if (pb == 63) break;
        }
        try be.append(.{ try key(a, "planes"), try map(a, planes.items) });
        try blist.append(try map(a, be.items));
    }
    try top.append(.{ try key(a, "bricks"), try array(a, blist.items) });

    // fronts, id order
    var flist = std.ArrayList([]const u8).init(a);
    for (snap.fronts) |*f| {
        var fe = std.ArrayList(Entry).init(a);
        try fe.append(.{ try key(a, "id"), try int(a, f.id) });
        try fe.append(.{ try key(a, "parent"), try int(a, if (f.parent == std.math.maxInt(u32)) -1 else @as(i64, f.parent)) });
        try fe.append(.{ try key(a, "generation"), try int(a, f.generation) });
        try fe.append(.{ try key(a, "alive"), try boolean(a, f.alive) });
        try fe.append(.{ try key(a, "dormant"), try boolean(a, f.dormant) });
        try fe.append(.{ try key(a, "pos"), try f64array(a, &f.pos) });
        try fe.append(.{ try key(a, "dir"), try f64array(a, &f.dir) });
        try fe.append(.{ try key(a, "normal"), try f64array(a, &f.normal) });
        try fe.append(.{ try key(a, "s"), try f64v(a, f.s) });
        try fe.append(.{ try key(a, "roll"), try f64v(a, f.roll) });
        try fe.append(.{ try key(a, "age"), try int(a, f.age) });
        try fe.append(.{ try key(a, "born"), try uint(a, f.born_epoch) });
        try fe.append(.{ try key(a, "brick"), try uint(a, f.brick.raw()) });
        var ring = try a.alloc(u8, front.SLOTS * 16);
        for (f.ring, 0..) |sl, i| {
            std.mem.writeInt(u32, ring[i * 16 ..][0..4], @bitCast(sl.r), .little);
            std.mem.writeInt(u32, ring[i * 16 + 4 ..][0..4], @bitCast(sl.dz), .little);
            std.mem.writeInt(u32, ring[i * 16 + 8 ..][0..4], @intFromEnum(sl.tag), .little);
            std.mem.writeInt(u32, ring[i * 16 + 12 ..][0..4], sl.age, .little);
        }
        try fe.append(.{ try key(a, "ring"), try bytes(a, ring) });
        var canon = std.ArrayList(u8).init(a);
        try f.writeCanonical(canon.writer());
        try fe.append(.{ try key(a, "canonical"), try bytes(a, canon.items) });
        try flist.append(try map(a, fe.items));
    }
    try top.append(.{ try key(a, "fronts"), try array(a, flist.items) });

    var act = try a.alloc(i64, 0);
    _ = &act;
    var active = std.ArrayList([]const u8).init(a);
    for (snap.active) |k| try active.append(try uint(a, k.raw()));
    try top.append(.{ try key(a, "active"), try array(a, active.items) });
    var dirty = std.ArrayList([]const u8).init(a);
    for (snap.dirty) |k| try dirty.append(try uint(a, k.raw()));
    try top.append(.{ try key(a, "dirty"), try array(a, dirty.items) });
    var since = std.ArrayList([]const u8).init(a);
    for (snap.active_since) |t| try since.append(try uint(a, t));
    try top.append(.{ try key(a, "active_since"), try array(a, since.items) });
    try top.append(.{ try key(a, "budget"), try int(a, if (snap.budget) |b| @as(i64, b) else -1) });
    try top.append(.{ try key(a, "cut_at"), try int(a, if (snap.cut_at) |c| @as(i64, c) else -1) });
    try top.append(.{ try key(a, "units"), try uint(a, snap.units) });
    try top.append(.{ try key(a, "calls"), try uint(a, snap.calls) });

    var out = struple.Packer.init(gpa);
    errdefer out.deinit();
    try out.appendMap(top.items);
    return out.toOwnedSlice();
}

pub fn writeFile(gpa: std.mem.Allocator, w: *const world_mod.World, path: []const u8) !void {
    const b = try write(gpa, w);
    defer gpa.free(b);
    var f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    try f.writeAll(b);
}

pub fn hex(h: [32]u8) [64]u8 {
    var out: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&out, "{s}", .{std.fmt.fmtSliceHexLower(&h)}) catch unreachable;
    return out;
}
