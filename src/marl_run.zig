//! marl-run — MARL-0's seedbed (docs/MARL_CAMPAIGN.md §19).
//!
//! Stream exemplars at a scalar 3-D truth, report error and cost at
//! logarithmic checkpoints, and draw the error field. Its job is the same
//! as `loam-run`'s: make every number a gate asserts printable on the same
//! configuration, so a gate that cannot fail is visible as one.
//!
//! Separate from `loam-run` on purpose. MARL is not the sim: no World, no
//! step, no fed clock, nothing in a hash. A flag on the seedbed would say
//! otherwise.
//!
//! Timings are wall clock and never reach the model — the model is a
//! function of (seed, exemplar count, options) and of nothing else, which
//! is what makes two runs comparable at all.

const std = @import("std");
const builtin = @import("builtin");
const loam = @import("loam");
const marl = loam.marl;
const seedbed = loam.seedbed;
const th = loam.thresholds;

const usage =
    \\marl-run — MARL-0: local online RBF learning
    \\
    \\  --seed N            exemplar stream seed (default 7)
    \\  --regions N         regions per axis (default 6); h = 1/N sets the
    \\                      widest kernel a 27-region gather stays exact for
    \\  --budget N          kernels a region may own (default 48)
    \\  --exemplars N       exemplars to stream (default 200000)
    \\  --threshold F       surprise below this does nothing (default 0.02)
    \\  --coverage F        birth when no kernel reads above this (default 0.35)
    \\  --width F           birth width, as a fraction of the widest (default 0.5)
    \\  --optimizer O       nlms (default) | adam — adam is the instrument
    \\  --rate-w F          NLMS step on the weights (default 0.5; 0 is G17 (e)'s mutation)
    \\  --rate-geom F       the geometry's share of the same (default 0.2)
    \\  --rate F            Adam's step, for --optimizer adam (default 0.02)
    \\  --steps N           Adam steps per learning event (default 3)
    \\  --probes N          held-out probe count (default 8192)
    \\  --slice FILE        CSV of a z-slice: x,y,truth,prediction,abs_error
    \\  --slice-z F         the slice's z (default 0.46, the shell's centre)
    \\  --slice-res N       the slice's resolution (default 192)
    \\  --pgm PREFIX        PREFIX-{truth,pred,err,density}.pgm
    \\  --interference      after the run, one more learning event, and what
    \\                      it changed as a function of distance
    \\  --quiet             checkpoints only
    \\
    \\ MARL-1
    \\  --features N        sharp shells in the target (default 1)
    \\  --sharpness S       multiplies 1/W: higher is a thinner ridge (default 1)
    \\  --frequency F       multiplies the swell's spatial frequencies (default 1)
    \\  --responsibility R  the furthest, in Mahalanobis widths, a kernel may be
    \\                      from an exemplar and still LEARN from it. Support is
    \\                      separate: prediction always sums the full cutoff
    \\                      gather (default 5.657, which is support = responsibility)
    \\  --no-births         freeze the topology; descent only
    \\  --arms              the capacity-controlled experiment: A births with no
    \\                      descent, B' descends on A's frozen topology, C does
    \\                      both. Reports RMS_A/RMS_B' at identical capacity
    \\  --tsv               one summary line, for driving sweeps
    \\
;

const Opts = struct {
    m: marl.Options = .{},
    exemplars: u64 = 200_000,
    probe_n: usize = 8192,
    slice: ?[]const u8 = null,
    slice_z: f32 = 0.46,
    slice_res: u32 = 192,
    pgm: ?[]const u8 = null,
    interference: bool = false,
    quiet: bool = false,
    arms: bool = false,
    tsv: bool = false,
};

fn parseF32(s: []const u8) !f32 {
    return std.fmt.parseFloat(f32, s);
}

fn parse(args: []const []const u8) !?Opts {
    var o = Opts{};
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        const next = struct {
            fn get(ar: []const []const u8, k: *usize) ![]const u8 {
                k.* += 1;
                if (k.* >= ar.len) return error.MissingValue;
                return ar[k.*];
            }
        }.get;
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) return null;
        if (std.mem.eql(u8, a, "--seed")) {
            o.m.seed = try std.fmt.parseInt(u64, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--regions")) {
            o.m.regions = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--budget")) {
            o.m.budget = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--exemplars")) {
            o.exemplars = try std.fmt.parseInt(u64, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--threshold")) {
            o.m.threshold = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--coverage")) {
            o.m.coverage = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--width")) {
            o.m.birth_width = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--rate")) {
            o.m.rate = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--rate-w")) {
            o.m.rate_w = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--rate-geom")) {
            o.m.rate_geom = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--optimizer")) {
            const v = try next(args, &i);
            o.m.optimizer = if (std.mem.eql(u8, v, "nlms")) .nlms else if (std.mem.eql(u8, v, "adam")) .adam else return error.UnknownOptimizer;
        } else if (std.mem.eql(u8, a, "--steps")) {
            o.m.steps = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--probes")) {
            o.probe_n = try std.fmt.parseInt(usize, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--slice")) {
            o.slice = try next(args, &i);
        } else if (std.mem.eql(u8, a, "--slice-z")) {
            o.slice_z = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--slice-res")) {
            o.slice_res = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--pgm")) {
            o.pgm = try next(args, &i);
        } else if (std.mem.eql(u8, a, "--interference")) {
            o.interference = true;
        } else if (std.mem.eql(u8, a, "--quiet")) {
            o.quiet = true;
        } else if (std.mem.eql(u8, a, "--tsv")) {
            o.tsv = true;
            o.quiet = true;
        } else if (std.mem.eql(u8, a, "--arms")) {
            o.arms = true;
        } else if (std.mem.eql(u8, a, "--no-births")) {
            o.m.births = false;
        } else if (std.mem.eql(u8, a, "--features")) {
            o.m.truth.features = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--sharpness")) {
            o.m.truth.sharpness = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--frequency")) {
            o.m.truth.frequency = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--responsibility")) {
            o.m.responsibility = try parseF32(try next(args, &i));
        } else {
            std.debug.print("unknown option: {s}\n", .{a});
            return error.UnknownOption;
        }
    }
    return o;
}

/// 1, 2, 5, 10, 20, 50, … — the campaign's §19F decades with two rungs
/// between, so a curve has shape and not just endpoints.
fn nextCheckpoint(c: u64) u64 {
    var p: u64 = 1;
    while (p <= c) : (p *= 10) {
        if (c < p * 2) return p * 2;
        if (c < p * 5) return p * 5;
        if (c < p * 10) return p * 10;
    }
    return c * 2;
}

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const argv = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, argv);
    const o = parse(argv[1..]) catch |e| {
        std.debug.print("{s}\n", .{usage});
        return e;
    } orelse {
        std.debug.print("{s}\n", .{usage});
        return;
    };

    if (o.arms) return arms(gpa, o);
    var model = try marl.Model.init(gpa, o.m);
    defer model.deinit();

    const pr = try marl.probesOf(gpa, o.m.truth, 0xB0B, o.probe_n);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    const out = std.io.getStdOut().writer();
    try out.print("marl-run — MARL-0, {s}\n", .{@tagName(builtin.mode)});
    try out.print("  regions {d}³ (h {d:.4}, σ_max {d:.5}, σ_birth {d:.5})  budget {d}  θ {d:.3}  coverage {d:.2}  steps {d}  seed {d}\n", .{
        o.m.regions, model.h, model.sigma_max, o.m.birth_width * model.sigma_max, o.m.budget, o.m.threshold, o.m.coverage, o.m.steps, o.m.seed,
    });
    try out.print("  optimizer {s} (rate_w {d:.3}, rate_geom {d:.3}, adam rate {d:.3})\n", .{ @tagName(o.m.optimizer), o.m.rate_w, o.m.rate_geom, o.m.rate });
    var rms_empty: f32 = 0;
    {
        var mx: f32 = 0;
        const r0 = try model.rms(pr.p, pr.y, &mx);
        rms_empty = r0;
        try out.print("  the empty model scores RMS {d:.5} on {d} held-out probes (it predicts zero; that is the truth's own RMS)\n", .{ r0, o.probe_n });
        try out.print("  the interference bound, proved: {d:.4} of the domain (thresholds.marl0ReachBound)\n\n", .{th.marl0ReachBound(model.h, o.m.steps, o.m.trust)});
    }

    try out.print("{s:>10} {s:>8} {s:>7} {s:>8} {s:>5} {s:>4} {s:>8} {s:>8} {s:>8} {s:>7} {s:>7} {s:>8} {s:>9}\n", .{
        "exemplars", "events", "births", "kernels", "regs", "sat", "rms", "max|e|", "recent", "touch", "eval", "ns/pred", "ns/learn",
    });

    var timer = try std.time.Timer.start();
    var next_cp: u64 = 1;
    var last_stats = model.stats;
    var seen: u64 = 0;
    while (seen < o.exemplars) {
        const run_to = @min(o.exemplars, next_cp);
        while (seen < run_to) : (seen += 1) _ = try model.observeOne();

        const s = model.stats;
        const d_ev = s.events - last_stats.events;
        const d_touch = s.touched - last_stats.touched;
        const d_eval = s.evaluated - last_stats.evaluated;
        const d_pred = s.exemplars - last_stats.exemplars;
        const d_pns = s.predict_ns - last_stats.predict_ns;
        const d_lns = s.learn_ns - last_stats.learn_ns;

        var mx: f32 = 0;
        const before = model.stats;
        const r = try model.rms(pr.p, pr.y, &mx);
        model.stats = before; // probing is measurement; it never counts as the model's cost

        if (!o.quiet or seen == o.exemplars) {
            try out.print("{d:>10} {d:>8} {d:>7} {d:>8} {d:>5} {d:>4} {d:>8.5} {d:>8.4} {d:>8.5} {d:>7.1} {d:>7.0} {d:>8} {d:>9}\n", .{
                seen,                    s.events,
                s.births,                model.kernels.items.len,
                model.occupiedRegions(), model.saturatedRegions(),
                r,                       mx,
                model.recentError(),     if (d_ev > 0) @as(f64, @floatFromInt(d_touch)) / @as(f64, @floatFromInt(d_ev)) else 0,
                if (d_pred > 0) @as(f64, @floatFromInt(d_eval)) / @as(f64, @floatFromInt(d_pred)) else 0,
                if (d_pred > 0) d_pns / d_pred else 0,
                if (d_ev > 0) d_lns / d_ev else 0,
            });
        }
        last_stats = s;
        next_cp = nextCheckpoint(next_cp);
    }
    const wall = timer.read();

    // ── what the campaign asked to be told ────────────────────────────
    const s = model.stats;
    const drift = model.driftOf();
    model.retighten();
    try out.print("\nthe run: {d} exemplars in {d:.2} s ({s})\n", .{ seen, @as(f64, @floatFromInt(wall)) / 1e9, @tagName(builtin.mode) });
    try out.print("  learning events    {d:>10}  ({d:.1}% of exemplars — the rest cost one prediction and nothing else)\n", .{ s.events, 100 * @as(f64, @floatFromInt(s.events)) / @as(f64, @floatFromInt(s.exemplars)) });
    try out.print("  kernel births      {d:>10}   saturation events {d}   saturated regions {d}/{d}\n", .{ s.births, s.saturations, model.saturatedRegions(), model.regions.len });
    try out.print("  kernels            {d:>10}   in {d} of {d} regions\n", .{ model.kernels.items.len, model.occupiedRegions(), model.regions.len });

    const mean_touch = if (s.events > 0) @as(f64, @floatFromInt(s.touched)) / @as(f64, @floatFromInt(s.events)) else 0;
    const mean_regs = if (s.events > 0) @as(f64, @floatFromInt(s.regions_touched)) / @as(f64, @floatFromInt(s.events)) else 0;
    try out.print("\nlocality (§11) — what one learning event reached\n", .{});
    try out.print("  kernels touched    {d:>10.1}   predicted ≤ {d} (thresholds.MARL0_MAX_TOUCHED) — the SUPPORT set\n", .{ mean_touch, th.MARL0_MAX_TOUCHED });
    try out.print("  of those, responsible {d:>7.1}   the subset that took a gradient (radius {d:.3} widths)\n", .{ @as(f64, @floatFromInt(s.responsible)) / @as(f64, @floatFromInt(@max(1, s.events))), model.opts.responsibility });
    try out.print("  of the model       {d:>10.4}   predicted ≤ {d:.3}\n", .{ mean_touch / @as(f64, @floatFromInt(@max(1, model.kernels.items.len))), th.MARL0_MAX_TOUCHED_FRACTION });
    try out.print("  regions touched    {d:>10.2}   of 27 a gather may open\n", .{mean_regs});
    try out.print("  kernels evaluated  {d:>10.1}   per prediction (the COST; the touched set is the LOCALITY)\n", .{@as(f64, @floatFromInt(s.evaluated)) / @as(f64, @floatFromInt(@max(1, s.exemplars)))});
    try out.print("  regions pruned     {d:>10.2}   per prediction by max_reach alone, never opened\n", .{@as(f64, @floatFromInt(s.pruned)) / @as(f64, @floatFromInt(@max(1, s.exemplars)))});

    try out.print("\ndrift (§11) — the only thing that can break exact locality\n", .{});
    try out.print("  centre drift       mean {d:.5}  max {d:.5}  (h = {d:.4})\n", .{ drift.mean, drift.max, model.h });
    try out.print("  left their birth region  {d} of {d}   re-homings {d}\n", .{ drift.out_of_region, model.kernels.items.len, s.rehomed });
    try out.print("  clamps bit: reach {d}  width {d}  centre {d}  trust {d}\n", .{ s.reach_clamped, s.width_clamped, s.centre_clamped, s.trust_clamped });

    // Capacity allocation (§11): where the kernels went.
    // Measured from the target itself, not hard-coded: the band is two
    // widths either side of a ridge, so `sharpness` moves it.
    const V_SHELL = marl.volumeOf(model.opts.truth, marl.Truth.inShell);
    const V_QUIET = marl.volumeOf(model.opts.truth, marl.Truth.inQuiet);
    const d_shell = model.densityIn(marl.Truth.inShell, V_SHELL);
    const d_quiet = model.densityIn(marl.Truth.inQuiet, V_QUIET);
    try out.print("\ncapacity (§11) — where the model spent itself (band volume {d:.5}, slab {d:.5})\n", .{ V_SHELL, V_QUIET });
    try out.print("  shell band         {d:>6} kernels   {d:>9.1} per unit volume\n", .{ model.countIn(marl.Truth.inShell), d_shell });
    try out.print("  quiet slab         {d:>6} kernels   {d:>9.1} per unit volume   (the truth is zero there)\n", .{ model.countIn(marl.Truth.inQuiet), d_quiet });
    if (d_quiet > 0) {
        try out.print("  ratio              {d:>6.1}             predicted ≥ {d:.0} (thresholds.MARL0_CAPACITY_RATIO)\n", .{ d_shell / d_quiet, th.MARL0_CAPACITY_RATIO });
    } else {
        try out.print("  ratio                    ∞             the quiet slab took nothing at all\n", .{});
    }

    {
        var mx: f32 = 0;
        const r = try model.rms(pr.p, pr.y, &mx);
        var m0 = try marl.Model.init(gpa, o.m);
        defer m0.deinit();
        var mx0: f32 = 0;
        const r0 = try m0.rms(pr.p, pr.y, &mx0);
        try out.print("\nconvergence (§13) — held-out, {d} probes never learned from\n", .{o.probe_n});
        try out.print("  RMS {d:.5} → {d:.5}   gain {d:.2}   predicted ≥ {d:.0} (thresholds.MARL0_RMS_GAIN)\n", .{ r0, r, r0 / r, th.MARL0_RMS_GAIN });
        try out.print("  max |e| {d:.4} → {d:.4}\n", .{ mx0, mx });
    }

    if (o.tsv) {
        try out.print("{s}\n", .{TSV_HEADER});
        try tsvLine(&model, pr, rms_empty, out);
        return;
    }
    if (o.interference) try interference(&model, gpa, out);
    if (o.slice) |path| try writeSlice(&model, path, o.slice_z, o.slice_res, out);
    if (o.pgm) |prefix| try writePgms(&model, gpa, prefix, o.slice_z, o.slice_res, out);
}

/// One line of numbers, for driving a sweep from a shell. Tab separated,
/// with a header on request — a sweep is a table and a table wants to be
/// read by something other than a person.
fn tsvLine(model: *marl.Model, pr: marl.Probes, rms0: f32, out: anytype) !void {
    var mx: f32 = 0;
    const before = model.stats;
    const r = try model.rms(pr.p, pr.y, &mx);
    model.stats = before;
    const s = model.stats;
    const d = model.driftOf();
    const w = model.weightStats();
    const V_SHELL = marl.volumeOf(model.opts.truth, marl.Truth.inShell);
    const V_QUIET = marl.volumeOf(model.opts.truth, marl.Truth.inQuiet);
    const ev: f64 = @floatFromInt(@max(1, s.events));
    try out.print("{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d}\t{d:.6}\t{d:.6}\t{d:.4}\t{d:.4}\t{d:.2}\t{d:.2}\t{d:.6}\t{d:.6}\t{d:.4}\t{d:.4}\t{d:.1}\t{d:.1}\n", .{
        s.exemplars,             model.kernels.items.len,
        s.events,                s.updates,
        s.saturations,           model.saturatedRegions(),
        model.occupiedRegions(), rms0,
        r,                       rms0 / r,
        mx,                      @as(f64, @floatFromInt(s.responsible)) / ev,
        @as(f64, @floatFromInt(s.evaluated)) / @as(f64, @floatFromInt(@max(1, s.exemplars))),
        d.mean,                  d.max,
        w.mean_abs,              w.max_abs,
        model.densityIn(marl.Truth.inShell, V_SHELL),
        model.densityIn(marl.Truth.inQuiet, V_QUIET),
    });
}

pub const TSV_HEADER = "exemplars\tkernels\tevents\tupdates\tsaturations\tsat_regions\toccupied\trms0\trms\tgain\tmaxe\ttouched\tevaluated\tdrift_mean\tdrift_max\tw_mean\tw_max\tshell_density\tquiet_density";

/// MARL-1 experiment 1, Christian's design: the capacity-controlled
/// birth-versus-deformation question.
///
///   A  — births, no descent. The topology surprise discovers on its own.
///   B' — A's frozen topology, descent on, births off, same stream.
///   C  — both, which is MARL-0.
///
/// A against B' is the honest descent metric because K is identical by
/// construction. A against C is not, and is reported beside it with the
/// capacity and work ratios that say why.
fn arms(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    const pr = try marl.probesOf(gpa, o.m.truth, 0xB0B, o.probe_n);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var a_opts = o.m;
    a_opts.rate_w = 0;
    a_opts.rate_geom = 0;
    var a = try marl.Model.init(gpa, a_opts);
    defer a.deinit();
    const rms0 = try a.rms(pr.p, pr.y, null);
    a.stats = .{};
    try a.stream_n(o.exemplars);
    const rms_a = try a.rms(pr.p, pr.y, null);

    var b = try marl.Model.init(gpa, .{
        .seed = o.m.seed,          .regions = o.m.regions,
        .budget = o.m.budget,      .threshold = o.m.threshold,
        .coverage = o.m.coverage,  .birth_width = o.m.birth_width,
        .optimizer = o.m.optimizer, .rate_w = o.m.rate_w,
        .rate_geom = o.m.rate_geom, .rate = o.m.rate,
        .steps = o.m.steps,        .truth = o.m.truth,
        .births = false,           .responsibility = o.m.responsibility,
        .trust = o.m.trust,        .window = o.m.window,
    });
    defer b.deinit();
    try b.reseedFrom(&a);
    const rms_b_start = try b.rms(pr.p, pr.y, null);
    b.stats = .{};
    try b.stream_n(o.exemplars);
    const rms_b = try b.rms(pr.p, pr.y, null);

    var c = try marl.Model.init(gpa, o.m);
    defer c.deinit();
    try c.stream_n(o.exemplars);
    const rms_c = try c.rms(pr.p, pr.y, null);

    try out.print("MARL-1 experiment 1 — capacity-controlled birth vs deformation ({s})\n", .{@tagName(builtin.mode)});
    try out.print("  {d} exemplars, the same stream in every arm, {d} held-out probes\n", .{ o.exemplars, o.probe_n });
    try out.print("  the empty model scores RMS {d:.5}\n\n", .{rms0});
    try out.print("  {s:<34} {s:>9} {s:>9} {s:>11} {s:>9}\n", .{ "arm", "RMS", "kernels", "updates", "w_mean" });
    try out.print("  {s:<34} {d:>9.5} {d:>9} {d:>11} {d:>9.4}\n", .{ "A  births, no descent", rms_a, a.kernels.items.len, a.stats.updates, a.weightStats().mean_abs });
    try out.print("  {s:<34} {d:>9.5} {d:>9} {d:>11} {d:>9.4}\n", .{ "B' A's topology, descent only", rms_b, b.kernels.items.len, b.stats.updates, b.weightStats().mean_abs });
    try out.print("  {s:<34} {d:>9.5} {d:>9} {d:>11} {d:>9.4}\n", .{ "C  births and descent", rms_c, c.kernels.items.len, c.stats.updates, c.weightStats().mean_abs });
    try out.print("\n  B' started from A's topology at RMS {d:.5} — the reseed is exact\n", .{rms_b_start});
    try out.print("  DEFORMATION, at identical capacity:  RMS_A/RMS_B' = {d:.2}   (predicted ≥ {d:.0}, thresholds.MARL1_DESCENT_GAIN)\n", .{ rms_a / rms_b, th.MARL1_DESCENT_GAIN });
    try out.print("  K_B'/K_A = {d:.4} — identical by construction, which is the point\n", .{@as(f64, @floatFromInt(b.kernels.items.len)) / @as(f64, @floatFromInt(a.kernels.items.len))});
    try out.print("\n  and the comparison that is NOT capacity-controlled, beside it:\n", .{});
    try out.print("    RMS_A/RMS_C = {d:.2}   K_C/K_A = {d:.3}   work_C/work_A = {d:.3}\n", .{
        rms_a / rms_c,
        @as(f64, @floatFromInt(c.kernels.items.len)) / @as(f64, @floatFromInt(a.kernels.items.len)),
        @as(f64, @floatFromInt(c.stats.updates)) / @as(f64, @floatFromInt(@max(1, a.stats.updates))),
    });
    // Arm A's updates are ZERO-MAGNITUDE, not absent: both rates are zero,
    // so the loop runs and applies nothing. It is counted because the
    // gather and the attribution were still paid for, and because A having
    // MORE of them than C is the finding — a worse model leaves more
    // exemplars above the surprise threshold, so birth-only does more work
    // to reach a worse answer.
    try out.print("    work_C/work_B' = {d:.3}\n", .{@as(f64, @floatFromInt(c.stats.updates)) / @as(f64, @floatFromInt(@max(1, b.stats.updates)))});
    const drift = b.driftOf();
    try out.print("    B' moved A's centres by {d:.5} on average, {d:.5} at most (h = {d:.4})\n", .{ drift.mean, drift.max, b.h });
}

/// §11's interference, measured rather than argued: freeze the prediction
/// on a dense probe set, run ONE more learning event, and report the
/// largest change at each distance from the exemplar. Beyond the proved
/// reach bound every difference must be exactly zero — not small, zero,
/// which is a claim about bits and is checked as one.
fn interference(model: *marl.Model, gpa: std.mem.Allocator, out: anytype) !void {
    const n = 20000;
    const pr = try marl.probesOf(gpa, model.opts.truth, 0xFACE, n);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);
    const before = try gpa.alloc(f32, n);
    defer gpa.free(before);
    for (pr.p, before) |p, *b| b.* = try model.predict(p);

    // One event, at a point the model has certainly seen structure near.
    const x = [3]f32{ 0.30, 0.42, 0.46 };
    const ev = try model.observe(x, marl.truth(x));

    const bound = th.marl0ReachBound(model.h, model.opts.steps, model.opts.trust);
    var max_beyond: f32 = 0;
    var changed_beyond: u32 = 0;
    var furthest_change: f32 = 0;
    var buckets: [12]f32 = [_]f32{0} ** 12;
    var counts: [12]u32 = [_]u32{0} ** 12;
    for (pr.p, before) |p, b| {
        const a = try model.predict(p);
        const d = @max(@abs(p[0] - x[0]), @max(@abs(p[1] - x[1]), @abs(p[2] - x[2])));
        const diff = @abs(a - b);
        const bi: usize = @min(11, @as(usize, @intFromFloat(d * 12)));
        buckets[bi] = @max(buckets[bi], diff);
        counts[bi] += 1;
        if (a != b) furthest_change = @max(furthest_change, d);
        if (d > bound) {
            max_beyond = @max(max_beyond, diff);
            if (a != b) changed_beyond += 1;
        }
    }
    try out.print("\ninterference (§11) — one learning event at ({d:.2}, {d:.2}, {d:.2}), {d} probes\n", .{ x[0], x[1], x[2], n });
    try out.print("  the event touched {d} kernels in {d} regions, born={}\n", .{ ev.touched, ev.regions_touched, ev.born });
    try out.print("  beyond the proved bound {d:.4}: {d} probes changed, largest change {e:.3}\n", .{ bound, changed_beyond, max_beyond });
    try out.print("  the OBSERVED radius — furthest probe whose bits moved at all — {d:.4}\n", .{furthest_change});
    try out.print("  {s:>8}  {s:>10}  {s:>7}\n", .{ "∞-dist", "max |Δŷ|", "probes" });
    for (buckets, counts, 0..) |v, c, i| {
        if (c == 0) continue;
        try out.print("  {d:>8.3}  {e:>10.3}  {d:>7}\n", .{ @as(f32, @floatFromInt(i + 1)) / 12, v, c });
    }
}

fn writeSlice(model: *marl.Model, path: []const u8, z: f32, res: u32, out: anytype) !void {
    var f = try std.fs.cwd().createFile(path, .{});
    defer f.close();
    var bw = std.io.bufferedWriter(f.writer());
    const w = bw.writer();
    try w.print("x,y,truth,prediction,abs_error\n", .{});
    var j: u32 = 0;
    while (j < res) : (j += 1) {
        var i: u32 = 0;
        while (i < res) : (i += 1) {
            const p = [3]f32{
                (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(res)),
                (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(res)),
                z,
            };
            const t = marl.truth(p);
            const y = try model.predict(p);
            try w.print("{d:.6},{d:.6},{d:.6},{d:.6},{d:.6}\n", .{ p[0], p[1], t, y, @abs(t - y) });
        }
    }
    try bw.flush();
    try out.print("\nslice: {s} ({d}×{d} at z = {d:.3})\n", .{ path, res, res, z });
}

fn writePgms(model: *marl.Model, gpa: std.mem.Allocator, prefix: []const u8, z: f32, res: u32, out: anytype) !void {
    const n = @as(usize, res) * res;
    const t_v = try gpa.alloc(f32, n);
    defer gpa.free(t_v);
    const p_v = try gpa.alloc(f32, n);
    defer gpa.free(p_v);
    const e_v = try gpa.alloc(f32, n);
    defer gpa.free(e_v);
    const d_v = try gpa.alloc(f32, n);
    defer gpa.free(d_v);
    @memset(d_v, 0);

    var j: u32 = 0;
    while (j < res) : (j += 1) {
        var i: u32 = 0;
        while (i < res) : (i += 1) {
            const p = [3]f32{
                (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(res)),
                (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(res)),
                z,
            };
            const idx = @as(usize, j) * res + i;
            const t = marl.truth(p);
            const y = try model.predict(p);
            // Signed fields drawn about mid grey; the error drawn from black.
            t_v[idx] = 0.5 + t;
            p_v[idx] = 0.5 + y;
            e_v[idx] = @abs(t - y);
        }
    }
    // Kernel centres within half a region of the slice, as a density map.
    for (model.kernels.items) |*k| {
        const mu = [3]f32{ k.p[0], k.p[1], k.p[2] };
        if (@abs(mu[2] - z) > model.h / 2) continue;
        const i: u32 = @min(res - 1, @as(u32, @intFromFloat(mu[0] * @as(f32, @floatFromInt(res)))));
        const jj: u32 = @min(res - 1, @as(u32, @intFromFloat(mu[1] * @as(f32, @floatFromInt(res)))));
        d_v[@as(usize, jj) * res + i] += 1;
    }

    var buf: [512]u8 = undefined;
    inline for (.{ "truth", "pred", "err", "density" }, .{ t_v, p_v, e_v, d_v }, .{ 1.0, 1.0, 4.0, 1.0 }) |nm, vals, scale| {
        const path = try std.fmt.bufPrint(&buf, "{s}-{s}.pgm", .{ prefix, nm });
        try seedbed.writePgm(path, res, vals, scale);
    }
    try out.print("pgm: {s}-{{truth,pred,err,density}}.pgm ({d}×{d} at z = {d:.3}; err ×4)\n", .{ prefix, res, res, z });
}

test "the checkpoint ladder is 1, 2, 5 per decade and never stalls" {
    var c: u64 = 1;
    const want = [_]u64{ 2, 5, 10, 20, 50, 100, 200, 500, 1000 };
    for (want) |w| {
        c = nextCheckpoint(c);
        try std.testing.expectEqual(w, c);
    }
}
