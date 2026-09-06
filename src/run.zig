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
    \\  --consume C          potential drawn down per second around a front (default 1)
    \\  --no-heal            mount no healing operator
    \\  --damage x0,y0,z0,x1,y1,z1@step   clear material in the box at step
    \\  --slice CH:AXIS:COORD:RES:FILE    write a PGM slice at the end (e.g. surface:z:0:128:out.pgm; the carrier is drawn as inside = 1)
    \\  --project CH:AXIS:RES:FILE        write a PGM max-projection along AXIS at the end
    \\  --dump FILE          write the snapshot as a struple map at the end
    \\  --ray ox,oy,oz,dx,dy,dz           count leaves a ray samples vs crosses at the end
    \\  --all-regions        iterate every brick, not the active set (the G5 mutation)
    \\  --active             print the active set at the end
    \\  --every N            print a line every N steps (default 10; 0 = none)
    \\  --trace FILE         after every step, one line per front: step id alive dormant x y z dx dy dz s (lattice units)
    \\  --avoid A            the front's self-avoidance coefficient (default 0.5)
    \\  --inhibit I          the front's inhibition threshold (default the params')
    \\  --persist P          the front's heading persistence (default 1)
    \\  --phases             print wall-clock per phase beside each line
    \\  --budget N           evaluate at most N bricks a step, attention first (R15)
    \\  --budget-fraction F  the same as a fraction of each step's active set (G14 c)
    \\  --budget-order O     attention (default) | key | queue | no_lag — the three mutations
    \\  --budget-schedule F  replay the budgets recorded on trace F's `# step` lines (G14 d)
    \\  --tropism-sweep D,D,…  the G3 ensemble at each stimulus displacement D (dose-response), then exit
    \\  --seeds N            seeds in the ensemble (default 6)
    \\  --coeff A            stimulus coefficient for the sweep (default the G3 scene's)
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
    consume: f32 = 1,
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
    budget: ?u32 = null,
    budget_fraction: ?f32 = null,
    budget_order: loam.world.BudgetOrder = .attention,
    /// A recorded budget schedule (`# step N budget B …` lines of a trace)
    /// replayed: the budget is on the transcript, and replay replays the
    /// record (G14 d).
    budget_schedule: ?[]const u8 = null,
    trace: ?[]const u8 = null,
    avoid: ?f32 = null,
    inhibit: ?f32 = null,
    persist: ?f32 = null,
    sweep: std.ArrayListUnmanaged(f64) = .{},
    seeds: u64 = 6,
    coeff: f32 = seedbed.TROPISM_COEFF,
};

const Slice = struct { bit: u6, axis: u2, coord: f64, res: u32, path: []const u8 };

/// The `# step N budget B …` lines of a trace: a step's budget, recorded.
fn readSchedule(gpa: std.mem.Allocator, path: []const u8, out: *std.AutoHashMapUnmanaged(u64, u32)) !void {
    const text = try std.fs.cwd().readFileAlloc(gpa, path, 1 << 30);
    defer gpa.free(text);
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "# step ")) continue;
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        _ = it.next(); // #
        _ = it.next(); // step
        const step = try std.fmt.parseInt(u64, it.next() orelse return error.BadSchedule, 10);
        if (!std.mem.eql(u8, it.next() orelse return error.BadSchedule, "budget")) return error.BadSchedule;
        const budget = try std.fmt.parseInt(u32, it.next() orelse return error.BadSchedule, 10);
        try out.put(gpa, step, budget);
    }
}

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
        } else if (std.mem.eql(u8, a, "--consume")) {
            o.consume = try std.fmt.parseFloat(f32, try next(args, &i));
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
        } else if (std.mem.eql(u8, a, "--budget")) {
            o.budget = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--budget-fraction")) {
            o.budget_fraction = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--budget-order")) {
            const v = try next(args, &i);
            o.budget_order = std.meta.stringToEnum(loam.world.BudgetOrder, v) orelse return error.BadBudgetOrder;
        } else if (std.mem.eql(u8, a, "--budget-schedule")) {
            o.budget_schedule = try next(args, &i);
        } else if (std.mem.eql(u8, a, "--tropism-sweep")) {
            var it = std.mem.splitScalar(u8, try next(args, &i), ',');
            while (it.next()) |part| try o.sweep.append(gpa, try std.fmt.parseFloat(f64, part));
        } else if (std.mem.eql(u8, a, "--seeds")) {
            o.seeds = try std.fmt.parseInt(u64, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--coeff")) {
            o.coeff = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--every")) {
            o.every = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--trace")) {
            o.trace = try next(args, &i);
        } else if (std.mem.eql(u8, a, "--avoid")) {
            o.avoid = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--inhibit")) {
            o.inhibit = try std.fmt.parseFloat(f32, try next(args, &i));
        } else if (std.mem.eql(u8, a, "--persist")) {
            o.persist = try std.fmt.parseFloat(f32, try next(args, &i));
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
    defer opts.sweep.deinit(gpa);

    const stdout = std.io.getStdOut().writer();
    if (opts.sweep.items.len > 0) {
        // The dose-response instrument: G3's ensemble at each displacement.
        try stdout.print("tropism sweep: {d} seeds, coefficient {d}, {d} steps\n", .{ opts.seeds, opts.coeff, opts.steps });
        try stdout.print("{s:>6} {s:>8} {s:>8} {s:>9} {s:>8} {s:>8}  {s}\n", .{ "D", "mean r", "sd", "lower95", "sigma0", "all>0", "per seed" });
        var sx: f64 = 0;
        var sy: f64 = 0;
        var sxx: f64 = 0;
        var sxy: f64 = 0;
        for (opts.sweep.items) |d| {
            var e = try seedbed.tropismEnsemble(gpa, opts.seeds, d, opts.coeff, opts.steps, true);
            defer e.deinit(gpa);
            try stdout.print("{d:>6.1} {d:>8.2} {d:>8.2} {d:>9.2} {d:>8.2} {s:>8} ", .{ d, e.mean, e.sd, e.lower95, e.sigma0, if (e.all_positive) "yes" else "no" });
            for (e.samples) |smp| try stdout.print(" {d:.1}", .{smp.r});
            try stdout.print("\n", .{});
            sx += d;
            sy += e.mean;
            sxx += d * d;
            sxy += d * e.mean;
        }
        const n: f64 = @floatFromInt(opts.sweep.items.len);
        if (n > 1) {
            const slope = (n * sxy - sx * sy) / (n * sxx - sx * sx);
            try stdout.print("slope of mean response against D: {d:.3} per lattice unit of displacement\n", .{slope});
        }
        return;
    }

    var js: ?*jobs.JobSystem = null;
    if (opts.threads > 0) js = try jobs.JobSystem.init(gpa, opts.threads);
    defer if (js) |s| s.deinit();
    var world = try loam.World.init(gpa, .{ .seed = opts.seed, .policy = .{ .active_only = !opts.all_regions } });
    defer world.deinit();
    world.jobs = js;
    var scene = seedbed.Scene{};
    if (opts.light) |l| scene.light = l;
    scene.stimulus = opts.stimulus;
    scene.tropism_light = opts.tropism;
    scene.tropism_stimulus = opts.stimulus_tropism;
    scene.deposit = opts.deposit;
    scene.consume = opts.consume;
    scene.heal = opts.heal;
    scene.avoid = opts.avoid;
    scene.inhibit = opts.inhibit;
    scene.persist = opts.persist;
    var trace_file: ?std.fs.File = null;
    if (opts.trace) |path| trace_file = try std.fs.cwd().createFile(path, .{});
    defer if (trace_file) |f| f.close();
    var schedule = std.AutoHashMapUnmanaged(u64, u32){};
    defer schedule.deinit(gpa);
    if (opts.budget_schedule) |path| try readSchedule(gpa, path, &schedule);
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

    var step: u64 = 0;
    var total_ms: f64 = 0;
    while (step <= opts.steps) : (step += 1) {
        if (opts.damage) |d| if (d.step == step) {
            try seedbed.damage(&world, d.lo, d.hi);
            try world.apply();
            try stdout.print("step {d}: damage applied, {d} bricks touched\n", .{ step, world.published().dirty.len });
        };
        // The budget, per step: a recorded schedule replayed, a count, or a
        // fraction of the published active set (G14 c's instrument), at
        // least one brick.
        if (opts.budget_schedule != null) {
            world.policy.budget = schedule.get(step);
        } else if (opts.budget_fraction) |f| {
            const n: f32 = @floatFromInt(world.published().active.len);
            world.policy.budget = @max(1, @as(u32, @intFromFloat(@ceil(n * f))));
        } else world.policy.budget = opts.budget;
        world.policy.budget_order = opts.budget_order;
        timer.reset();
        try world.step(.{ .frame = step, .time_ns = step * opts.dt_ms * std.time.ns_per_ms }, js);
        const ms = @as(f64, @floatFromInt(timer.read())) / 1e6;
        total_ms += ms;
        if (trace_file) |f| {
            // The step's budget on the transcript (Christian's ruling):
            // an input like the seed, so a replay replays the record.
            // `diff_traces.py` skips the line.
            if (world.policy.budget) |b| try f.writer().print("# step {d} budget {d} head {d} carried {d} faded {d} skipped {d} overrun {d} backlog {d}\n", .{ step, b, world.evaluated.len, world.stats.carried, world.stats.faded, world.stats.fronts_skipped, world.stats.overrun, world.stats.backlog });
            // The front's state after the step, lattice units about the
            // scene origin: what a representation change must not move.
            const c: f64 = @floatFromInt(loam.lattice.CELLS / 2);
            for (world.published().fronts) |fr| {
                try f.writer().print("{d} {d} {d} {d} {d:.6} {d:.6} {d:.6} {d:.6} {d:.6} {d:.6} {d:.4}\n", .{ step, fr.id, @intFromBool(fr.alive), @intFromBool(fr.dormant), fr.pos[0] - c, fr.pos[1] - c, fr.pos[2] - c, fr.dir[0], fr.dir[1], fr.dir[2], fr.s });
            }
        }
        if (opts.every > 0 and (step % opts.every == 0 or step == opts.steps)) {
            const s = world.stats;
            var live: usize = 0;
            var dormant: usize = 0;
            for (world.published().fronts) |f| {
                if (!f.alive) continue;
                if (f.dormant) dormant += 1 else live += 1;
            }
            try stdout.print("step {d:>4}  active {d:>5}→{d:<5} evals {d:>6}  fronts {d}/{d} dormant  changed {d:>4} (+{d} new, {d} seam)  writes {d}/{d} seam/halo  spawns {d}  {d:.2} ms\n", .{
                step, s.active_in, s.active_out, s.region_evals, live, dormant, s.bricks_changed, s.bricks_materialised, s.seam_bricks, s.seam_writes, s.halo_writes, s.spawns, ms,
            });
            if (world.policy.budget != null) try stdout.print("           budget {d}: {d} carried, {d} faded, {d} front-steps skipped, overrun {d}, backlog {d} ({d} steps over)\n", .{ world.policy.budget.?, s.carried, s.faded, s.fronts_skipped, s.overrun, s.backlog, world.overload_steps });
            if (opts.phases) try stdout.print("           operate {d:.2}  fronts {d:.2}  apply {d:.2}  frontier {d:.2}  seams {d:.2}  finalize {d:.2}  build {d:.2}  publish {d:.2} ms\n", .{
                @as(f64, @floatFromInt(s.ns_operate)) / 1e6, @as(f64, @floatFromInt(s.ns_fronts)) / 1e6, @as(f64, @floatFromInt(s.ns_apply)) / 1e6, @as(f64, @floatFromInt(s.ns_frontier)) / 1e6, @as(f64, @floatFromInt(s.ns_seams)) / 1e6, @as(f64, @floatFromInt(s.ns_finalize)) / 1e6, @as(f64, @floatFromInt(s.ns_build)) / 1e6, @as(f64, @floatFromInt(s.ns_publish)) / 1e6,
            });
        }
    }
    const snap = world.published();
    try stdout.print("done: {d} steps in {d:.1} ms ({d:.2} ms/step), {d} bricks, {d} nodes, {d} fronts, vid {d}\n", .{ opts.steps, total_ms, total_ms / @as(f64, @floatFromInt(opts.steps + 1)), snap.brick_count, snap.node_count, snap.fronts.len, snap.vid });
    try stdout.print("root_hash    {s}\ncontent_hash {s}\n", .{ loam.dump.hex(snap.rootHash()), loam.dump.hex(snap.contentHash()) });
    try stdout.print("inside {d}  growth {d:.3}  front-steps below the faithful floor {d} (refinement's demand)\n", .{ seedbed.insideCount(&world), seedbed.total(&world, Channel.growth.bit()), world.total.below_faithful });
    {
        // Where the world is changing, from the summaries alone (R15).
        var found = std.ArrayListUnmanaged(loam.lattice.Key){};
        defer found.deinit(gpa);
        var examined: usize = 0;
        try snap.attentive(snap.time_ns, loam.thresholds.EPSILON, loam.thresholds.ATTENTION_TAU_S, true, gpa, &found, &examined);
        try stdout.print("attentive {d} of {d} bricks at the end (τ {d} s, floor {e:.0}; the walk examined {d} leaves, {d:.2} per attentive brick); {d} carried, {d} faded, {d} front-steps skipped, overrun {d} over the run; backlog {d} at the end, {d} consecutive steps over budget\n", .{ found.items.len, snap.brick_count, loam.thresholds.ATTENTION_TAU_S, loam.thresholds.EPSILON, examined, @as(f64, @floatFromInt(examined)) / @as(f64, @floatFromInt(@max(found.items.len, 1))), world.total.carried, world.total.faded, world.total.fronts_skipped, world.total.overrun, snap.backlog(), world.overload_steps });
    }

    if (opts.ray) |r| {
        const c = try seedbed.rayCount(&world, .{ r[0], r[1], r[2] }, .{ r[3], r[4], r[5] }, Channel.surface.mask() | Channel.density.mask(), .primary);
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
        if (sl.bit == Channel.surface.bit()) seedbed.occupancy(vals);
        try seedbed.writePgm(sl.path, sl.res, vals, 1.0);
        try stdout.print("slice {s} axis {d} at {d:.1} → {s}\n", .{ registry.name(sl.bit), sl.axis, sl.coord, sl.path });
    }
    for (opts.projections.items) |pr| {
        const vals = try seedbed.project(&world, gpa, pr.bit, pr.axis, .{ -64, -16, -64 }, .{ 64, 112, 64 }, pr.res, pr.res);
        defer gpa.free(vals);
        if (pr.bit == Channel.surface.bit()) seedbed.occupancy(vals);
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
    var o = try parseArgs(gpa, &.{ "--scene", "wound", "--steps", "5", "--light", "1,2,3", "--damage", "0,0,0,1,1,1@3", "--slice", "surface:z:0:64:x.pgm" }, &registry);
    defer o.slices.deinit(gpa);
    try std.testing.expectEqual(seedbed.Preset.wound, o.scene);
    try std.testing.expectEqual(@as(f64, 2), o.light.?[1]);
    try std.testing.expectEqual(@as(u32, 3), o.damage.?.step);
    try std.testing.expectEqual(Channel.surface.bit(), o.slices.items[0].bit);
    try std.testing.expectError(error.UnknownScene, parseArgs(gpa, &.{ "--scene", "oak" }, &registry));
    try std.testing.expectError(error.BadVector, parseArgs(gpa, &.{ "--light", "1,2" }, &registry));
}
