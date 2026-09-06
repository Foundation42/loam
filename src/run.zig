//! loam-run — the seedbed (brief P1.7). Loam's tiltyard.
//!
//! Place a seed, a light, a wall of damage; step on fed time; dump slices
//! as PGM and the active set as a list; print what each step cost. Its
//! job is making gate vacuity visible: every number a gate asserts can
//! be printed here, on the same scenes, and the two mutation instruments
//! (`--all-regions`, `--no-skip`) show what dormancy and summaries buy.
//!
//! Fixed dt is the only clock: `--dt-ms 1000` is one fed second per
//! step, and two runs with the same flags print the same hash. Timings
//! are wall clock, printed beside the counts, and never reach the sim.

const std = @import("std");
const loam = @import("loam");
const common = @import("common");
const jobs = common.jobs;
const seedbed = loam.seedbed;
const Channel = loam.Channel;

const usage =
    \\loam-run — the seedbed
    \\
    \\  --scene NAME         sapling | wound | blob | seams | diffusion   (default sapling)
    \\  --seed N             world seed (default 7)
    \\  --steps N            steps to run (default 60)
    \\  --dt-ms N            fed milliseconds per step (default 1000)
    \\  --threads N          job system workers; 0 = serial (default 0)
    \\  --light x,y,z        light blob centre (sapling/wound)
    \\  --stimulus x,y,z     stimulus blob centre (sapling/wound)
    \\  --tropism A          light tropism coefficient (default 0.6)
    \\  --stimulus-tropism B stimulus tropism coefficient (default 0)
    \\  --deposit D          material deposit rate (default 1)
    \\  --no-heal            mount no healing operator
    \\  --damage x0,y0,z0,x1,y1,z1@step   clear material in the box at step
    \\  --slice CH:AXIS:COORD:RES:FILE    write a PGM slice at the end (e.g. material:z:0:128:out.pgm)
    \\  --project CH:AXIS:RES:FILE        write a PGM max-projection along AXIS at the end
    \\  --dump FILE          write the snapshot as a struple map at the end
    \\  --ray ox,oy,oz,dx,dy,dz           count leaves a ray samples vs crosses at the end
    \\  --all-regions        iterate every brick, not the active set (the G5 mutation)
    \\  --active             print the active set at the end
    \\  --every N            print a line every N steps (default 10; 0 = none)
    \\  --phases             print wall-clock per phase beside each line
    \\  --help
    \\
;

const Opts = struct {
    scene: seedbed.Preset = .sapling,
    seed: u64 = 7,
    steps: u32 = 60,
    dt_ms: u64 = 1000,
    threads: u32 = 0,
    light: ?[3]f64 = null,
    stimulus: ?[3]f64 = null,
    tropism: f32 = 0.6,
    stimulus_tropism: f32 = 0,
    deposit: f32 = 1,
    heal: bool = true,
    damage: ?struct { lo: [3]f64, hi: [3]f64, step: u32 } = null,
    slices: std.ArrayListUnmanaged(Slice) = .{},
    projections: std.ArrayListUnmanaged(Slice) = .{},
    dump: ?[]const u8 = null,
    ray: ?[6]f64 = null,
    all_regions: bool = false,
    active: bool = false,
    every: u32 = 10,
    phases: bool = false,
};

const Slice = struct { bit: u6, axis: u2, coord: f64, res: u32, path: []const u8 };

fn parseVec(s: []const u8, comptime n: usize) ![n]f64 {
    var out: [n]f64 = undefined;
    var it = std.mem.splitScalar(u8, s, ',');
    for (&out) |*v| {
        const part = it.next() orelse return error.BadVector;
        v.* = try std.fmt.parseFloat(f64, part);
    }
    if (it.next() != null) return error.BadVector;
    return out;
}

pub fn parseArgs(gpa: std.mem.Allocator, args: []const []const u8, registry: *const loam.channel.Registry) !Opts {
    var o = Opts{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        const next = struct {
            fn f(list: []const []const u8, idx: *usize) ![]const u8 {
                idx.* += 1;
                if (idx.* >= list.len) return error.MissingValue;
                return list[idx.*];
            }
        }.f;
        if (std.mem.eql(u8, a, "--help")) return error.Help;
        if (std.mem.eql(u8, a, "--scene")) {
            const v = try next(args, &i);
            o.scene = std.meta.stringToEnum(seedbed.Preset, v) orelse return error.UnknownScene;
        } else if (std.mem.eql(u8, a, "--seed")) {
            o.seed = try std.fmt.parseInt(u64, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--steps")) {
            o.steps = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--dt-ms")) {
            o.dt_ms = try std.fmt.parseInt(u64, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--threads")) {
            o.threads = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--light")) {
            o.light = try parseVec(try next(args, &i), 3);
        } else if (std.mem.eql(u8, a, "--stimulus")) {
            o.stimulus = try parseVec(try next(args, &i), 3);
        } else if (std.mem.eql(u8, a, "--tropism")) {
            o.tropism = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--stimulus-tropism")) {
            o.stimulus_tropism = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--deposit")) {
            o.deposit = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--no-heal")) {
            o.heal = false;
        } else if (std.mem.eql(u8, a, "--damage")) {
            const v = try next(args, &i);
            const at = std.mem.indexOfScalar(u8, v, '@') orelse return error.BadDamage;
            const box = try parseVec(v[0..at], 6);
            o.damage = .{ .lo = .{ box[0], box[1], box[2] }, .hi = .{ box[3], box[4], box[5] }, .step = try std.fmt.parseInt(u32, v[at + 1 ..], 10) };
        } else if (std.mem.eql(u8, a, "--slice")) {
            const v = try next(args, &i);
            var it = std.mem.splitScalar(u8, v, ':');
            const ch = it.next() orelse return error.BadSlice;
            const ax = it.next() orelse return error.BadSlice;
            const co = it.next() orelse return error.BadSlice;
            const rs = it.next() orelse return error.BadSlice;
            const path = it.next() orelse return error.BadSlice;
            try o.slices.append(gpa, .{
                .bit = registry.find(ch) orelse return error.UnknownChannel,
                .axis = switch (ax[0]) {
                    'x' => 0,
                    'y' => 1,
                    'z' => 2,
                    else => return error.BadSlice,
                },
                .coord = try std.fmt.parseFloat(f64, co),
                .res = try std.fmt.parseInt(u32, rs, 10),
                .path = path,
            });
        } else if (std.mem.eql(u8, a, "--project")) {
            const v = try next(args, &i);
            var it = std.mem.splitScalar(u8, v, ':');
            const ch = it.next() orelse return error.BadSlice;
            const ax = it.next() orelse return error.BadSlice;
            const rs = it.next() orelse return error.BadSlice;
            const path = it.next() orelse return error.BadSlice;
            try o.projections.append(gpa, .{
                .bit = registry.find(ch) orelse return error.UnknownChannel,
                .axis = switch (ax[0]) {
                    'x' => 0,
                    'y' => 1,
                    'z' => 2,
                    else => return error.BadSlice,
                },
                .coord = 0,
                .res = try std.fmt.parseInt(u32, rs, 10),
                .path = path,
            });
        } else if (std.mem.eql(u8, a, "--dump")) {
            o.dump = try next(args, &i);
        } else if (std.mem.eql(u8, a, "--ray")) {
            o.ray = try parseVec(try next(args, &i), 6);
        } else if (std.mem.eql(u8, a, "--all-regions")) {
            o.all_regions = true;
        } else if (std.mem.eql(u8, a, "--active")) {
            o.active = true;
        } else if (std.mem.eql(u8, a, "--phases")) {
            o.phases = true;
        } else if (std.mem.eql(u8, a, "--every")) {
            o.every = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else {
            std.debug.print("unknown flag: {s}\n", .{a});
            return error.UnknownFlag;
        }
    }
    return o;
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    const registry = loam.channel.Registry.init();
    var opts = parseArgs(gpa, args[1..], &registry) catch |err| switch (err) {
        error.Help => {
            std.debug.print("{s}", .{usage});
            return;
        },
        else => {
            std.debug.print("{s}\nerror: {s}\n", .{ usage, @errorName(err) });
            std.process.exit(2);
        },
    };
    defer opts.slices.deinit(gpa);
    defer opts.projections.deinit(gpa);

    const stdout = std.io.getStdOut().writer();
    var world = try loam.World.init(gpa, .{ .seed = opts.seed, .policy = .{ .active_only = !opts.all_regions } });
    defer world.deinit();
    var scene = seedbed.Scene{};
    if (opts.light) |l| scene.light = l;
    scene.stimulus = opts.stimulus;
    scene.tropism_light = opts.tropism;
    scene.tropism_stimulus = opts.stimulus_tropism;
    scene.deposit = opts.deposit;
    scene.heal = opts.heal;
    var timer = try std.time.Timer.start();
    try scene.build(&world, opts.scene);
    const build_ms = @as(f64, @floatFromInt(timer.lap())) / 1e6;
    try stdout.print("scene {s}: {d} bricks, {d} nodes, {d} fronts, built in {d:.1} ms\n", .{ @tagName(opts.scene), world.published().brick_count, world.published().node_count, world.published().fronts.len, build_ms });
    if (opts.phases) {
        const s = world.stats;
        try stdout.print("           apply {d:.1}  frontier {d:.1}  seams {d:.1}  finalize {d:.1}  build {d:.1}  publish {d:.1} ms\n", .{
            @as(f64, @floatFromInt(s.ns_apply)) / 1e6, @as(f64, @floatFromInt(s.ns_frontier)) / 1e6, @as(f64, @floatFromInt(s.ns_seams)) / 1e6, @as(f64, @floatFromInt(s.ns_finalize)) / 1e6, @as(f64, @floatFromInt(s.ns_build)) / 1e6, @as(f64, @floatFromInt(s.ns_publish)) / 1e6,
        });
    }

    var js: ?*jobs.JobSystem = null;
    if (opts.threads > 0) js = try jobs.JobSystem.init(gpa, opts.threads);
    defer if (js) |s| s.deinit();

    var step: u64 = 0;
    var total_ms: f64 = 0;
    while (step <= opts.steps) : (step += 1) {
        if (opts.damage) |d| if (d.step == step) {
            try seedbed.damage(&world, d.lo, d.hi);
            try world.apply();
            try stdout.print("step {d}: damage applied, {d} bricks touched\n", .{ step, world.published().dirty.len });
        };
        timer.reset();
        try world.step(.{ .frame = step, .time_ns = step * opts.dt_ms * std.time.ns_per_ms }, js);
        const ms = @as(f64, @floatFromInt(timer.read())) / 1e6;
        total_ms += ms;
        if (opts.every > 0 and (step % opts.every == 0 or step == opts.steps)) {
            const s = world.stats;
            var live: usize = 0;
            var dormant: usize = 0;
            for (world.published().fronts) |f| {
                if (!f.alive) continue;
                if (f.dormant) dormant += 1 else live += 1;
            }
            try stdout.print("step {d:>4}  active {d:>5}→{d:<5} evals {d:>6}  fronts {d}/{d} dormant  changed {d:>4} (+{d} new, {d} seam)  spawns {d}  {d:.2} ms\n", .{
                step, s.active_in, s.active_out, s.region_evals, live, dormant, s.bricks_changed, s.bricks_materialised, s.seam_bricks, s.spawns, ms,
            });
            if (opts.phases) try stdout.print("           operate {d:.2}  fronts {d:.2}  apply {d:.2}  frontier {d:.2}  seams {d:.2}  finalize {d:.2}  build {d:.2}  publish {d:.2} ms\n", .{
                @as(f64, @floatFromInt(s.ns_operate)) / 1e6, @as(f64, @floatFromInt(s.ns_fronts)) / 1e6, @as(f64, @floatFromInt(s.ns_apply)) / 1e6, @as(f64, @floatFromInt(s.ns_frontier)) / 1e6, @as(f64, @floatFromInt(s.ns_seams)) / 1e6, @as(f64, @floatFromInt(s.ns_finalize)) / 1e6, @as(f64, @floatFromInt(s.ns_build)) / 1e6, @as(f64, @floatFromInt(s.ns_publish)) / 1e6,
            });
        }
    }
    const snap = world.published();
    try stdout.print("done: {d} steps in {d:.1} ms ({d:.2} ms/step), {d} bricks, {d} nodes, {d} fronts, vid {d}\n", .{ opts.steps, total_ms, total_ms / @as(f64, @floatFromInt(opts.steps + 1)), snap.brick_count, snap.node_count, snap.fronts.len, snap.vid });
    try stdout.print("root_hash    {s}\ncontent_hash {s}\n", .{ loam.dump.hex(snap.rootHash()), loam.dump.hex(snap.contentHash()) });
    try stdout.print("material {d:.3}  growth {d:.3}  activity {d:.3}\n", .{ seedbed.total(&world, Channel.material.bit()), seedbed.total(&world, Channel.growth.bit()), seedbed.total(&world, Channel.activity.bit()) });

    if (opts.ray) |r| {
        const c = try seedbed.rayCount(&world, .{ r[0], r[1], r[2] }, .{ r[3], r[4], r[5] }, Channel.material.mask() | Channel.density.mask(), .primary);
        try stdout.print("ray: sampled {d} of {d} leaves crossed, {d} nodes tested\n", .{ c.sampled, c.crossed, c.nodes_tested });
    }
    if (opts.active) {
        try stdout.print("active ({d}):", .{snap.active.len});
        for (snap.active) |k| {
            const o = k.origin();
            try stdout.print(" g{d}@{d},{d},{d}", .{ k.gauge(), o[0], o[1], o[2] });
        }
        try stdout.print("\n", .{});
    }
    for (opts.slices.items) |sl| {
        const half: f64 = 64;
        const vals = try seedbed.slice(&world, gpa, sl.bit, sl.axis, sl.coord, .{ -half, -half }, .{ half, half }, sl.res);
        defer gpa.free(vals);
        try seedbed.writePgm(sl.path, sl.res, vals, 1.0);
        try stdout.print("slice {s} axis {d} at {d:.1} → {s}\n", .{ registry.name(sl.bit), sl.axis, sl.coord, sl.path });
    }
    for (opts.projections.items) |pr| {
        const vals = try seedbed.project(&world, gpa, pr.bit, pr.axis, .{ -64, -16, -64 }, .{ 64, 112, 64 }, pr.res, pr.res);
        defer gpa.free(vals);
        try seedbed.writePgm(pr.path, pr.res, vals, 1.0);
        const comps = try seedbed.components(gpa, vals, pr.res, 0.3);
        try stdout.print("projection {s} along axis {d} → {s} ({d} components above 0.3)\n", .{ registry.name(pr.bit), pr.axis, pr.path, comps });
    }
    if (opts.dump) |path| {
        try loam.dump.writeFile(gpa, &world, path);
        try stdout.print("dump → {s}\n", .{path});
    }
}

test "argument grammar: a vector, a damage box, a slice, and a refusal" {
    const gpa = std.testing.allocator;
    const registry = loam.channel.Registry.init();
    var o = try parseArgs(gpa, &.{ "--scene", "wound", "--steps", "5", "--light", "1,2,3", "--damage", "0,0,0,1,1,1@3", "--slice", "material:z:0:64:x.pgm" }, &registry);
    defer o.slices.deinit(gpa);
    try std.testing.expectEqual(seedbed.Preset.wound, o.scene);
    try std.testing.expectEqual(@as(f64, 2), o.light.?[1]);
    try std.testing.expectEqual(@as(u32, 3), o.damage.?.step);
    try std.testing.expectEqual(Channel.material.bit(), o.slices.items[0].bit);
    try std.testing.expectError(error.UnknownScene, parseArgs(gpa, &.{ "--scene", "oak" }, &registry));
    try std.testing.expectError(error.BadVector, parseArgs(gpa, &.{ "--light", "1,2" }, &registry));
}
