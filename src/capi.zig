//! capi — loam behind a C ABI, as a shared library (`libloam.so`).
//!
//! The seam rill established: a boundary that is a real artefact, so a
//! Python process (ctypes, pure stdlib — `py/loam`) or any non-Zig host
//! drives the SAME world the Zig surface does, through the same authoring
//! verbs the seedbed and `loam-run` use. Nothing here is a second
//! mechanism; every function is one call into `seedbed.zig` or
//! `world.zig`. Units at this door are world units, like the seedbed's.
//!
//! Errors are integers: 0 ok, negative a refusal, named by `loam_error_name`.
//! Handles are opaque pointers; the caller frees what it made.

const std = @import("std");
const loam = @import("loam");
const seedbed = loam.seedbed;
const Channel = loam.Channel;

pub const VERSION: u32 = 1;

const Handle = struct {
    gpa: std.mem.Allocator,
    world: loam.World,
    // Operators the C side mounted, owned here so their addresses are stable.
    diffusion: std.ArrayListUnmanaged(*loam.operators.Diffusion) = .{},
    decay: std.ArrayListUnmanaged(*loam.operators.Decay) = .{},
    advection: std.ArrayListUnmanaged(*loam.operators.Advection) = .{},
    healing: std.ArrayListUnmanaged(*loam.operators.Healing) = .{},
    last_error: [64]u8 = [_]u8{0} ** 64,
};

const gpa = std.heap.c_allocator;

fn fail(h: ?*Handle, err: anyerror) c_int {
    if (h) |hh| {
        const name = @errorName(err);
        const n = @min(name.len, hh.last_error.len - 1);
        @memcpy(hh.last_error[0..n], name[0..n]);
        hh.last_error[n] = 0;
    }
    return -1;
}

export fn loam_version() u32 {
    return VERSION;
}

/// A new world. `seed` seeds every stream; `extent` world units cover the
/// lattice on each axis, centred on `origin`; 0 = the default frame (one
/// unit per lattice cell, world origin at the lattice centre).
export fn loam_world_new(seed: u64, extent: f64, ox: f64, oy: f64, oz: f64, default_gauge: u32) ?*Handle {
    const h = gpa.create(Handle) catch return null;
    var domain = loam.Domain{};
    if (extent > 0) domain = .{ .origin = .{ ox, oy, oz }, .extent = extent };
    h.* = .{ .gpa = gpa, .world = loam.World.init(gpa, .{ .seed = seed, .domain = domain, .policy = .{ .default_gauge = @intCast(default_gauge) } }) catch {
        gpa.destroy(h);
        return null;
    } };
    return h;
}

export fn loam_world_free(h: ?*Handle) void {
    const hh = h orelse return;
    hh.world.deinit();
    for (hh.diffusion.items) |p| gpa.destroy(p);
    for (hh.decay.items) |p| gpa.destroy(p);
    for (hh.advection.items) |p| gpa.destroy(p);
    for (hh.healing.items) |p| gpa.destroy(p);
    hh.diffusion.deinit(gpa);
    hh.decay.deinit(gpa);
    hh.advection.deinit(gpa);
    hh.healing.deinit(gpa);
    gpa.destroy(hh);
}

/// The last refusal's name, for the caller's message.
export fn loam_error_name(h: ?*Handle) [*:0]const u8 {
    const hh = h orelse return "NullHandle";
    return @ptrCast(&hh.last_error);
}

/// Channel bit by name, or -1.
export fn loam_channel(h: ?*Handle, name: [*:0]const u8) c_int {
    const hh = h orelse return -1;
    const bit = hh.world.registry.find(std.mem.span(name)) orelse return fail(hh, error.UnknownChannel);
    return @intCast(bit);
}

/// Register an application channel in the user range; returns its bit.
export fn loam_channel_register(h: ?*Handle, name: [*:0]const u8, lo: f32, hi: f32) c_int {
    const hh = h orelse return -1;
    const bit = hh.world.registry.register(std.mem.span(name), .{ .lo = lo, .hi = hi }) catch |e| return fail(hh, e);
    return @intCast(bit);
}

/// Queue a blob (the engine's kernel) into a channel; `loam_apply` commits.
export fn loam_blob(h: ?*Handle, channel: u32, cx: f64, cy: f64, cz: f64, radius: f64, amplitude: f32, gauge: u32) c_int {
    const hh = h orelse return -1;
    seedbed.blob(&hh.world, @intCast(channel), .{ cx, cy, cz }, radius, amplitude, @intCast(gauge)) catch |e| return fail(hh, e);
    return 0;
}

/// Queue a front at a world position with a heading; default ring params
/// with the given radius, length, deposit, tropisms and consumption.
export fn loam_plant(h: ?*Handle, px: f64, py: f64, pz: f64, dx: f64, dy: f64, dz: f64, radius: f32, length: f32, deposit: f32, tropism_light: f32, tropism_stimulus: f32, consume: f32) c_int {
    const hh = h orelse return -1;
    var params = loam.FrontParams{};
    if (radius > 0) params.radius = radius;
    if (length > 0) params.length = length;
    params.deposit = deposit;
    params.tropism_light = tropism_light;
    params.tropism_stimulus = tropism_stimulus;
    if (consume >= 0) params.consume = consume;
    seedbed.plant(&hh.world, .{ px, py, pz }, .{ dx, dy, dz }, params) catch |e| return fail(hh, e);
    return 0;
}

/// Queue a wall of damage over a world box; `loam_apply` commits.
export fn loam_damage(h: ?*Handle, x0: f64, y0: f64, z0: f64, x1: f64, y1: f64, z1: f64) c_int {
    const hh = h orelse return -1;
    seedbed.damage(&hh.world, .{ x0, y0, z0 }, .{ x1, y1, z1 }) catch |e| return fail(hh, e);
    return 0;
}

/// Queue a channel to zero everywhere (the season ends).
export fn loam_clear(h: ?*Handle, channel: u32) c_int {
    const hh = h orelse return -1;
    seedbed.clearChannel(&hh.world, @intCast(channel)) catch |e| return fail(hh, e);
    return 0;
}

/// Commit queued authoring: a new vid.
export fn loam_apply(h: ?*Handle) c_int {
    const hh = h orelse return -1;
    hh.world.apply() catch |e| return fail(hh, e);
    return 0;
}

export fn loam_add_diffusion(h: ?*Handle, channel: u32, rate: f32) c_int {
    const hh = h orelse return -1;
    const op = gpa.create(loam.operators.Diffusion) catch |e| return fail(hh, e);
    op.* = .{ .bit = @intCast(channel), .rate = rate };
    hh.diffusion.append(gpa, op) catch |e| return fail(hh, e);
    hh.world.addOperator(loam.operators.operatorOf(loam.operators.Diffusion, op)) catch |e| return fail(hh, e);
    return 0;
}

export fn loam_add_decay(h: ?*Handle, channel: u32, tau: f32) c_int {
    const hh = h orelse return -1;
    const op = gpa.create(loam.operators.Decay) catch |e| return fail(hh, e);
    op.* = .{ .bit = @intCast(channel), .tau = tau };
    hh.decay.append(gpa, op) catch |e| return fail(hh, e);
    hh.world.addOperator(loam.operators.operatorOf(loam.operators.Decay, op)) catch |e| return fail(hh, e);
    return 0;
}

/// Constant velocity in world units per second.
export fn loam_add_advection(h: ?*Handle, channel: u32, vx: f64, vy: f64, vz: f64) c_int {
    const hh = h orelse return -1;
    const op = gpa.create(loam.operators.Advection) catch |e| return fail(hh, e);
    const c = hh.world.domain.cell();
    op.* = .{ .bit = @intCast(channel), .velocity = .{ vx / c, vy / c, vz / c } };
    hh.advection.append(gpa, op) catch |e| return fail(hh, e);
    hh.world.addOperator(loam.operators.operatorOf(loam.operators.Advection, op)) catch |e| return fail(hh, e);
    return 0;
}

export fn loam_add_healing(h: ?*Handle, rate: f32, front_radius: f32, front_length: f32) c_int {
    const hh = h orelse return -1;
    const op = gpa.create(loam.operators.Healing) catch |e| return fail(hh, e);
    op.* = .{ .rate = rate };
    op.params.radius = front_radius;
    op.params.length = front_length;
    op.params.min_age = 1000;
    op.params.wander = 0.05;
    hh.healing.append(gpa, op) catch |e| return fail(hh, e);
    hh.world.addOperator(loam.operators.operatorOf(loam.operators.Healing, op)) catch |e| return fail(hh, e);
    return 0;
}

/// One step on fed time. Serial; a host with a JobSystem uses the Zig surface.
export fn loam_step(h: ?*Handle, frame: u64, time_ns: u64) c_int {
    const hh = h orelse return -1;
    hh.world.step(.{ .frame = frame, .time_ns = time_ns }, null) catch |e| return fail(hh, e);
    return 0;
}

/// Continuous reconstruction at a world point.
export fn loam_sample(h: ?*Handle, channel: u32, x: f64, y: f64, z: f64) f32 {
    const hh = h orelse return 0;
    return hh.world.published().sample(@intCast(channel), hh.world.domain.toLattice(.{ x, y, z }));
}

/// `n` world points (xyz interleaved) → `out[n]`.
export fn loam_sample_many(h: ?*Handle, channel: u32, n: usize, xyz: [*]const f64, out: [*]f32) c_int {
    const hh = h orelse return -1;
    const snap = hh.world.published();
    var i: usize = 0;
    while (i < n) : (i += 1) {
        out[i] = snap.sample(@intCast(channel), hh.world.domain.toLattice(.{ xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2] }));
    }
    return 0;
}

/// A res×res slice (see seedbed.slice) into `out[res*res]`.
export fn loam_slice(h: ?*Handle, channel: u32, axis: u32, coord: f64, lo0: f64, lo1: f64, hi0: f64, hi1: f64, res: u32, out: [*]f32) c_int {
    const hh = h orelse return -1;
    const vals = seedbed.slice(&hh.world, gpa, @intCast(channel), @intCast(axis), coord, .{ lo0, lo1 }, .{ hi0, hi1 }, res) catch |e| return fail(hh, e);
    defer gpa.free(vals);
    @memcpy(out[0..vals.len], vals);
    return 0;
}

/// A res×res max-projection along `axis` over the world box.
export fn loam_project(h: ?*Handle, channel: u32, axis: u32, x0: f64, y0: f64, z0: f64, x1: f64, y1: f64, z1: f64, res: u32, depth: u32, out: [*]f32) c_int {
    const hh = h orelse return -1;
    const vals = seedbed.project(&hh.world, gpa, @intCast(channel), @intCast(axis), .{ x0, y0, z0 }, .{ x1, y1, z1 }, res, depth) catch |e| return fail(hh, e);
    defer gpa.free(vals);
    @memcpy(out[0..vals.len], vals);
    return 0;
}

export fn loam_root_hash(h: ?*Handle, out: [*]u8) c_int {
    const hh = h orelse return -1;
    const r = hh.world.published().rootHash();
    @memcpy(out[0..32], &r);
    return 0;
}

export fn loam_content_hash(h: ?*Handle, out: [*]u8) c_int {
    const hh = h orelse return -1;
    const r = hh.world.published().contentHash();
    @memcpy(out[0..32], &r);
    return 0;
}

pub const Stats = extern struct {
    vid: u64,
    epoch: u64,
    bricks: u32,
    nodes: u32,
    fronts: u32,
    fronts_live: u32,
    active: u32,
    dirty: u32,
    region_evals: u64,
    front_steps: u64,
    bricks_changed: u64,
    bricks_materialised: u64,
    spawns: u64,
};

export fn loam_stats(h: ?*Handle, out: *Stats) c_int {
    const hh = h orelse return -1;
    const snap = hh.world.published();
    var live: u32 = 0;
    for (snap.fronts) |f| if (f.alive and !f.dormant) {
        live += 1;
    };
    out.* = .{
        .vid = snap.vid,
        .epoch = snap.epoch,
        .bricks = snap.brick_count,
        .nodes = snap.node_count,
        .fronts = @intCast(snap.fronts.len),
        .fronts_live = live,
        .active = @intCast(snap.active.len),
        .dirty = @intCast(snap.dirty.len),
        .region_evals = hh.world.stats.region_evals,
        .front_steps = hh.world.stats.front_steps,
        .bricks_changed = hh.world.stats.bricks_changed,
        .bricks_materialised = hh.world.stats.bricks_materialised,
        .spawns = hh.world.stats.spawns,
    };
    return 0;
}

/// Sum of a channel over every brick sample.
export fn loam_total(h: ?*Handle, channel: u32) f64 {
    const hh = h orelse return 0;
    return seedbed.total(&hh.world, @intCast(channel));
}

/// Samples of the carrier that are inside (φ < 0): the amount of tissue.
export fn loam_inside_count(h: ?*Handle) u64 {
    const hh = h orelse return 0;
    return seedbed.insideCount(&hh.world);
}

/// Queue a straight capsule of radius `r` (world units) between two world
/// points into the carrier, smooth-unioned with collar `k`; `loam_apply`
/// commits.
export fn loam_capsule(h: ?*Handle, x0: f64, y0: f64, z0: f64, x1: f64, y1: f64, z1: f64, r: f64, k: f32, gauge: u32) c_int {
    const hh = h orelse return -1;
    const d = hh.world.domain;
    seedbed.capsuleLattice(&hh.world, d.toLattice(.{ x0, y0, z0 }), d.toLattice(.{ x1, y1, z1 }), d.lengthToLattice(r), k, @intCast(gauge)) catch |e| return fail(hh, e);
    return 0;
}

/// Live front positions (xyz interleaved, world units) into `out[cap*3]`;
/// returns how many there are (which may exceed `cap`).
export fn loam_fronts(h: ?*Handle, cap: usize, out: [*]f64) usize {
    const hh = h orelse return 0;
    const snap = hh.world.published();
    var n: usize = 0;
    for (snap.fronts) |f| {
        if (!f.alive) continue;
        if (n < cap) {
            const w = hh.world.domain.toWorld(f.pos);
            out[n * 3] = w[0];
            out[n * 3 + 1] = w[1];
            out[n * 3 + 2] = w[2];
        }
        n += 1;
    }
    return n;
}

/// Leaves a ray samples versus crosses (G6's instrument). Returns 0 and
/// fills the two counts.
export fn loam_ray_count(h: ?*Handle, channel: u32, ox: f64, oy: f64, oz: f64, dx: f64, dy: f64, dz: f64, sampled: *u64, crossed: *u64) c_int {
    const hh = h orelse return -1;
    const c = seedbed.rayCount(&hh.world, .{ ox, oy, oz }, .{ dx, dy, dz }, loam.channel.maskOf(@intCast(channel)), .primary) catch |e| return fail(hh, e);
    sampled.* = c.sampled;
    crossed.* = c.crossed;
    return 0;
}

/// Write the snapshot as a struple map.
export fn loam_dump(h: ?*Handle, path: [*:0]const u8) c_int {
    const hh = h orelse return -1;
    loam.dump.writeFile(gpa, &hh.world, std.mem.span(path)) catch |e| return fail(hh, e);
    return 0;
}
