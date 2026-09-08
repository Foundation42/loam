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
const marble_mod = loam.marble;
const cache = loam.cache;
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
    \\ MARL-2
    \\  --hier              two-level residual hierarchy against flat MARL, same
    \\                      seed and same exemplars: parent + child_delta
    \\  --pressure T        mean post-update residual, over covered events, above
    \\                      which a region is under representation pressure (0.05)
    \\  --pressure-events N covered events a region must see first (default 200)
    \\  --refine F          the child's region grid, as a multiple (default 2)
    \\  --child-birth R     coverage (MARL-2, default) | residual | either: how the
    \\                      CHILD decides to birth — geometric tiling, or persistent
    \\                      post-update residual. The only thing MARL-3 changes
    \\  --birth-evidence N  observations a cell needs before it is evidence (8)
    \\  --route-floor E     baseline probability an exemplar in a refined region
    \\                      reaches the child — the trainability floor (default 1)
    \\  --route-gain B      added per unit of |parent residual| — the epistemic
    \\                      bias (default 0; floor 1 gain 0 is MARL-2's routing)
    \\  --duty D            MARL-5: normalise routing to this fraction of the
    \\                      exemplars offered, whatever the score (0 = MARL-4's
    \\                      raw probability). Equal duty is equal work
    \\  --sched M           off (MARL-4) | need | need_lag | need_lag_suff
    \\  --lag-tau T         anti-starvation timescale, exemplars (20000)
    \\  --suff-ref R        evidence per child kernel counting as served (200)
    \\  --unrefine F        MARL-7: retire a region's child level when the
    \\                      parent's error there has grown F× past what it was
    \\                      when the region was refined (0 = off, MARL-2..6)
    \\  --unrefine-after N  routed exemplars a region must see first (300)
    \\  --recycle           MARL-8: bank a retiring region's child and transplant
    \\                      it into the next region to refine — borrow, not buy
    \\  --drift6            MARL-6: move the world at a known exemplar count and
    \\                      watch. Stationary control, small and large drift
    \\  --drift-at N        when the world moves (default 200000)
    \\  --hysteresis        after the move, move it back — does the old
    \\                      representation become useful again, or interfere?
    \\  --arms5             MARL-5's controlled arms at one duty: uniform,
    \\                      static biased, and three schedules
    \\  --marble            MARL-11: the 2×2 against rbf.fit's batch Adam bake
    \\                      on a sheet-vein field — the first external baseline
    \\  --q3 FILE           MARL-17: the occlusion cache on a real Quake 3 level
    \\                      (tools/q3_volume.py writes FILE from a .bsp)
    \\  --marble9           MARL-12: the same arms at NINE channels on a sheet
    \\                      carrying two materials — what sharing one geometry
    \\                      across nine weights costs, and what it saves
    \\  --marble-pool N     distinct exemplars, MARL's stream AND rbf's pool (32768)
    \\  --marble-iters N    rbf's batch iterations (600)
    \\  --birth-scale F     the evidence cell's edge, in coverage spacings (2)
    \\  --birth-residual F  mean post-update residual it must still carry
    \\                      (default 0 = the surprise threshold)
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
    hier: bool = false,
    arms5: bool = false,
    drift6: bool = false,
    hysteresis: bool = false,
    drift_at: u64 = 200_000,
    repeat: u32 = 0,
    cycle: bool = false,
    marble: bool = false,
    marble9: bool = false,
    q3: ?[]const u8 = null,
    mo: marble_mod.ArmOptions = .{},
    /// Whether `--responsibility` was actually passed. The marble's arms
    /// are a PRE-REGISTERED configuration at G24's radius of 3, and
    /// `Opts.m`'s default is CUTOFF_R for every other mode's
    /// comparability — so copying `o.m` wholesale silently discarded
    /// MARL-6R's correction and ran the first external baseline at the
    /// radius the campaign had already retired. It did, once.
    resp_set: bool = false,
    p: marl.PressureOptions = .{},
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
        } else if (std.mem.eql(u8, a, "--hier")) {
            o.hier = true;
        } else if (std.mem.eql(u8, a, "--pressure")) {
            o.p.threshold = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--pressure-events")) {
            o.p.min_events = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--refine")) {
            o.p.refine = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--child-birth")) {
            const v = try next(args, &i);
            o.p.child_birth = if (std.mem.eql(u8, v, "coverage")) .coverage else if (std.mem.eql(u8, v, "residual")) .residual else if (std.mem.eql(u8, v, "either")) .either else return error.UnknownBirthRule;
        } else if (std.mem.eql(u8, a, "--birth-evidence")) {
            o.m.birth_evidence = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--route-floor")) {
            o.p.route_floor = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--route-gain")) {
            o.p.route_gain = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--duty")) {
            o.p.route_duty = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--lag-tau")) {
            o.p.lag_tau = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--suff-ref")) {
            o.p.suff_ref = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--unrefine")) {
            o.p.unrefine = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--recycle")) {
            o.p.recycle = true;
        } else if (std.mem.eql(u8, a, "--unrefine-after")) {
            o.p.unrefine_after = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--drift6")) {
            o.drift6 = true;
        } else if (std.mem.eql(u8, a, "--hysteresis")) {
            o.hysteresis = true;
        } else if (std.mem.eql(u8, a, "--drift-mode")) {
            const v = try next(args, &i);
            o.cycle = std.mem.eql(u8, v, "cycle");
        } else if (std.mem.eql(u8, a, "--drift-repeat")) {
            o.repeat = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--drift-at")) {
            o.drift_at = try std.fmt.parseInt(u64, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--marble")) {
            o.marble = true;
        } else if (std.mem.eql(u8, a, "--marble9")) {
            o.marble9 = true;
        } else if (std.mem.eql(u8, a, "--q3")) {
            o.q3 = try next(args, &i);
        } else if (std.mem.eql(u8, a, "--marble-pool")) {
            o.mo.pool = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--marble-iters")) {
            o.mo.iterations = try std.fmt.parseInt(u32, try next(args, &i), 10);
        } else if (std.mem.eql(u8, a, "--arms5")) {
            o.arms5 = true;
        } else if (std.mem.eql(u8, a, "--sched")) {
            const v = try next(args, &i);
            o.p.sched = if (std.mem.eql(u8, v, "off")) .off else if (std.mem.eql(u8, v, "need")) .need else if (std.mem.eql(u8, v, "need_lag")) .need_lag else if (std.mem.eql(u8, v, "need_lag_suff")) .need_lag_suff else if (std.mem.eql(u8, v, "hybrid")) .hybrid else return error.UnknownSched;
        } else if (std.mem.eql(u8, a, "--birth-scale")) {
            o.m.birth_scale = try parseF32(try next(args, &i));
        } else if (std.mem.eql(u8, a, "--birth-residual")) {
            o.m.birth_residual = try parseF32(try next(args, &i));
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
            o.resp_set = true;
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

    if (o.q3) |path| return q3Cache(gpa, o, path);
    if (o.marble9) return marbleNine(gpa, o);
    if (o.marble) return marbleArms(gpa, o);
    if (o.arms) return arms(gpa, o);
    if (o.repeat > 0) return driftRepeat(gpa, o);
    if (o.drift6) return drift6(gpa, o);
    if (o.arms5) return arms5(gpa, o);
    if (o.hier) return hier(gpa, o);
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

/// Does the archaeology ever become a problem? One drift showed capacity
/// growing and PAYING FOR ITSELF — silencing it costs error, so it is not
/// dead. The question erosion actually turns on is whether that stays true
/// over many moves, or whether the population runs away while the accuracy
/// stops improving. One drift cannot tell; this is the cheapest thing that
/// can.
fn driftRepeat(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    var h = try marl.Hierarchy.init(gpa, o.m, o.p);
    defer h.deinit();
    try h.stream_n(o.drift_at);

    try out.print("MARL-9 — the world moves {d} times, {s} ({s}, R {d:.3}, unrefine {d:.1}, recycle {})\n", .{ o.repeat, if (o.cycle) "CYCLING between two worlds" else "WALKING to six different ones", @tagName(builtin.mode), o.m.responsibility, o.p.unrefine, o.p.recycle });
    try out.print("  {s:>6} {s:>10} {s:>9} {s:>9} {s:>9} {s:>9} {s:>8}\n", .{ "move", "RMS", "child K", "unrefined", "banked", "moved", "adopted" });
    var tp = o.m.truth;
    var i: u32 = 0;
    while (i <= o.repeat) : (i += 1) {
        if (i > 0) {
            // WALK: six worlds that share nothing, each inside the bounds
            // the quiet slab's derivation needs (|shift x| ≤ 0.15, and the
            // shell inside the cube on every axis).
            // CYCLE: two worlds, alternating. Same number of changes, a
            // third of the distinct structure.
            const walk = [_][3]f32{
                .{ 0, -0.30, 0 },     .{ 0.12, 0, 0.22 },
                .{ -0.12, -0.20, -0.16 }, .{ 0, 0.14, 0.26 },
                .{ 0.14, -0.34, 0.10 },   .{ -0.14, 0.10, -0.18 },
            };
            tp.shift = if (o.cycle)
                (if (i % 2 == 1) [3]f32{ 0, -0.30, 0 } else [3]f32{ 0, 0, 0 })
            else
                walk[(i - 1) % walk.len];
            try h.drift(gpa, tp);
        }
        const pr = try marl.probesOf(gpa, tp, 0xB0B, o.probe_n);
        defer gpa.free(pr.p);
        defer gpa.free(pr.y);
        try h.stream_n(if (o.exemplars > 0) o.exemplars else 100_000);
        try out.print("  {d:>6} {d:>10.5} {d:>9} {d:>9} {d:>9} {d:>9} {d:>8.3}\n", .{
            i,                    try h.rms(pr.p, pr.y, null),
            h.child.kernels.items.len, h.unrefined_count,
            h.pool.items.len,     h.transplanted,
            h.adoption(),
        });
    }
}

/// MARL-6: move the world and watch. No repair of any kind — the refined
/// set, the frozen parents and every kernel stay as the old world left
/// them. Three arms of identical length: a stationary control, a small
/// displacement that lands the new ridge inside regions ALREADY REFINED,
/// and a large one that lands it in regions never pressured.
fn drift6(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    const Arm = struct { name: []const u8, shift: [3]f32 };
    const set = [_]Arm{
        .{ .name = "stationary control", .shift = .{ 0, 0, 0 } },
        .{ .name = "small drift (0.10)", .shift = .{ 0, -0.10, 0 } },
        .{ .name = "large drift (0.30)", .shift = .{ 0, -0.30, 0 } },
    };
    const old_tp = o.m.truth;

    try out.print("MARL-6 — the frozen parent under a moving world ({s})\n", .{@tagName(builtin.mode)});
    try out.print("  target sharpness ×{d:.1}; the world moves at {d} of {d} exemplars; seed {d}\n", .{ o.m.truth.sharpness, o.drift_at, o.exemplars, o.m.seed });
    try out.print("  nothing repairs anything: no thawing, no reparenting, no forgetting\n\n", .{});

    var base_child_rms: f32 = 0;
    var base_precision: f32 = 0;
    var base_events: u64 = 0;
    for (set, 0..) |arm, ai| {
        var new_tp = old_tp;
        new_tp.shift = arm.shift;
        var h = try marl.Hierarchy.init(gpa, o.m, o.p);
        defer h.deinit();
        try h.stream_n(o.drift_at);

        // Before the move, against the world as it then is.
        const pr_old = try marl.probesOf(gpa, old_tp, 0xB0B, o.probe_n);
        defer gpa.free(pr_old.p);
        defer gpa.free(pr_old.y);
        const rms_before = try h.rms(pr_old.p, pr_old.y, null);
        const child_before = try h.childRms(pr_old.p);
        const prec_before = h.precision();

        try h.drift(gpa, new_tp);
        const pr = try marl.probesOf(gpa, new_tp, 0xB0B, o.probe_n);
        defer gpa.free(pr.p);
        defer gpa.free(pr.y);

        try out.print("  ── {s} ──\n", .{arm.name});
        try out.print("    before the move: RMS {d:.5}, the child carrying {d:.5}, refinement precision {d:.3} over {d} regions\n", .{ rms_before, child_before, if (prec_before.refined > 0) @as(f32, @floatFromInt(prec_before.on_shell)) / @as(f32, @floatFromInt(prec_before.refined)) else 0, prec_before.refined });
        try out.print("    {s:>16} {s:>9} {s:>9} {s:>9} {s:>9} {s:>8}\n", .{ "after", "RMS", "parent", "child", "events", "births" });

        // The time series: transient surprise and structural corruption
        // look the same at one checkpoint and different across four.
        var last_events: u64 = h.parent.stats.events + h.child.stats.events;
        var window_events: u64 = 0;
        const marks = [_]u64{ 1_000, 20_000, 100_000, 400_000 };
        var done: u64 = 0;
        for (marks, 0..) |m, mi| {
            const kn = h.child.kernels.items.len;
            try h.stream_n(m - done);
            done = m;
            const ev_now = h.parent.stats.events + h.child.stats.events;
            if (mi == 0) window_events = ev_now - last_events;
            last_events = ev_now;
            try out.print("    {s:>16} {d:>9.5} {d:>9.5} {d:>9.5} {d:>9} {d:>8}\n", .{
                if (mi == 0) "+1k (immediate)" else if (mi == 1) "+20k (early)" else if (mi == 2) "+100k (late)" else "+400k (settled)",
                try h.rms(pr.p, pr.y, null),
                try h.parentRms(pr.p, pr.y),
                try h.childRms(pr.p),
                ev_now,
                // NET, and signed: with unrefinement the population can
                // SHRINK across a window, and this column underflowed the
                // first time it did.
                @as(i64, @intCast(h.child.kernels.items.len)) - @as(i64, @intCast(kn)),
            });
        }

        try out.print("    unrefinement: {d} regions retired ({d} of them where the band had left), {d} child kernels with them, {d} re-refined later\n", .{ h.unrefined_count, h.unrefined_on_departed, h.child_retired, h.rerefined_count });
        const st = h.strandedOf();
        const prec = h.precision();
        const pfrac = if (prec.refined > 0) @as(f32, @floatFromInt(prec.on_shell)) / @as(f32, @floatFromInt(prec.refined)) else 0;
        const child_after = try h.childRms(pr.p);
        if (ai == 0) {
            base_child_rms = child_after;
            base_precision = pfrac;
            base_events = window_events;
        }
        try out.print("    the child is carrying {d:.2}× what the stationary control's does\n", .{if (base_child_rms > 0) child_after / base_child_rms else 1});
        try out.print("    of {d} child kernels alive at the move: {d} ({d:.3}) are outside the CURRENT band, {d} ({d:.3}) took real gradient after it; mean |w| obsolete {d:.4}, still-relevant {d:.4}, born-since {d:.4}\n", .{ st.at_drift, st.outside_current, @as(f32, @floatFromInt(st.outside_current)) / @as(f32, @floatFromInt(@max(1, st.at_drift))), st.still_active, @as(f32, @floatFromInt(st.still_active)) / @as(f32, @floatFromInt(@max(1, st.at_drift))), st.w_obsolete, st.w_relevant, st.w_new });
        try out.print("    refinement precision against the CURRENT target {d:.3} ({d:.2}× the control's) over {d} regions\n", .{ pfrac, if (base_precision > 0) pfrac / base_precision else 1, prec.refined });
        try out.print("    the first 1 000 exemplars after the move cost {d} learning events ({d:.2}× the control's)\n", .{ window_events, if (base_events > 0) @as(f32, @floatFromInt(window_events)) / @as(f32, @floatFromInt(base_events)) else 1 });
        try out.print("    concentration {d:.2}, mean |w| parent {d:.3} child {d:.3}, {d:.0} updates per child kernel, {d:.3} trained\n\n", .{ h.childConcentration(), h.parent.weightStats().mean_abs, h.child.weightStats().mean_abs, h.child.meanUpdates(), h.child.trainedFraction(10) });

        {
            // Is the archaeology load-bearing? Silence it and look.
            const saved = try gpa.alloc(f32, h.child_at_drift);
            defer gpa.free(saved);
            const before_rms = try h.rms(pr.p, pr.y, null);
            const n = h.silenceObsolete(saved);
            const after_rms = try h.rms(pr.p, pr.y, null);
            h.restoreObsolete(saved[0..n]);
            try out.print("    ABLATION — silencing the {d} pre-move kernels now outside the band: RMS {d:.5} → {d:.5} ({d:.2}×)\n", .{ n, before_rms, after_rms, after_rms / before_rms });
        }

        if (o.hysteresis and ai == 2) {
            try h.drift(gpa, old_tp);
            const pr2 = try marl.probesOf(gpa, old_tp, 0xB0B, o.probe_n);
            defer gpa.free(pr2.p);
            defer gpa.free(pr2.y);
            try out.print("    ── and back again (hysteresis) ──\n", .{});
            try out.print("      the moment it returns: RMS {d:.5} against {d:.5} when it left\n", .{ try h.rms(pr2.p, pr2.y, null), rms_before });
            try h.stream_n(100_000);
            try out.print("      after another 100k: RMS {d:.5}, the child carrying {d:.5}, {d} child kernels\n", .{ try h.rms(pr2.p, pr2.y, null), try h.childRms(pr2.p), h.child.kernels.items.len });
        }
    }
}

/// MARL-5's controlled arms. Every arm sees the same exemplars in the same
/// order and routes the same FRACTION of them; they differ only in which
/// ones. So no arm can win by processing more, which is the whole point of
/// the control and the reason `--duty` exists.
fn arms5(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    const pr = try marl.probesOf(gpa, o.m.truth, 0xB0B, o.probe_n);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    const Arm = struct { name: []const u8, p: marl.PressureOptions };
    const duty = if (o.p.route_duty > 0) o.p.route_duty else 0.4;
    const set = [_]Arm{
        .{ .name = "A  uniform", .p = .{ .route_duty = duty, .route_floor = 1, .route_gain = 0 } },
        .{ .name = "B  static residual bias", .p = .{ .route_duty = duty, .route_floor = 0.05, .route_gain = 6 } },
        .{ .name = "C1 need", .p = .{ .route_duty = duty, .sched = .need, .lag_tau = o.p.lag_tau, .suff_ref = o.p.suff_ref } },
        .{ .name = "C2 need × lag", .p = .{ .route_duty = duty, .sched = .need_lag, .lag_tau = o.p.lag_tau, .suff_ref = o.p.suff_ref } },
        .{ .name = "C3 need × lag ÷ suff", .p = .{ .route_duty = duty, .sched = .need_lag_suff, .lag_tau = o.p.lag_tau, .suff_ref = o.p.suff_ref } },
    };

    try out.print("MARL-5 — scheduling a fixed learning budget ({s})\n", .{@tagName(builtin.mode)});
    try out.print("  target sharpness ×{d:.1}, {d} exemplars, duty {d:.2}, τ {d:.0}, suff_ref {d:.0}, seed {d}\n\n", .{ o.m.truth.sharpness, o.exemplars, duty, o.p.lag_tau, o.p.suff_ref, o.m.seed });
    try out.print("  {s:<24} {s:>9} {s:>8} {s:>9} {s:>8} {s:>7} {s:>7} {s:>8} {s:>9}\n", .{ "arm", "RMS", "routed", "childUpd", "kernels", "upd/k", "concen", "trained", "mean|w|" });

    var rms_a: f32 = 0;
    var conc_a: f64 = 0;
    for (set, 0..) |arm, ai| {
        var h = try marl.Hierarchy.init(gpa, o.m, arm.p);
        defer h.deinit();
        try h.stream_n(o.exemplars);
        const rms = try h.rms(pr.p, pr.y, null);
        const conc = h.childConcentration();
        if (ai == 0) {
            rms_a = rms;
            conc_a = conc;
        }
        try out.print("  {s:<24} {d:>9.5} {d:>8} {d:>9} {d:>8} {d:>7.0} {d:>7.2} {d:>8.3} {d:>9.3}\n", .{
            arm.name,                  rms,
            h.routed,                  h.child.stats.updates,
            h.child.kernels.items.len, h.child.meanUpdates(),
            conc,                      h.child.trainedFraction(10),
            h.child.weightStats().mean_abs,
        });
        if (ai == set.len - 1 or ai == 1) {
            // The learning-efficiency distribution, measured and never
            // scheduled from — split by whether the region's need is above
            // or below the median, which is the split that might one day
            // separate "send more evidence" from "the representation is
            // wrong".
            var hi: f64 = 0;
            var hi_n: u32 = 0;
            var lo: f64 = 0;
            var lo_n: u32 = 0;
            var med: f32 = 0;
            var cnt: u32 = 0;
            for (h.sched, 0..) |*e, i| {
                if (!h.refined[i] or e.eff_n == 0) continue;
                med += e.need;
                cnt += 1;
            }
            if (cnt > 0) med /= @floatFromInt(cnt);
            for (h.sched, 0..) |*e, i| {
                if (!h.refined[i] or e.eff_n == 0) continue;
                if (e.need >= med) {
                    hi += e.efficiency();
                    hi_n += 1;
                } else {
                    lo += e.efficiency();
                    lo_n += 1;
                }
            }
            if (hi_n > 0 and lo_n > 0) try out.print("     learning efficiency ({s}): above-median need {e:.3} over {d} regions, below {e:.3} over {d}\n", .{ arm.name, hi / @as(f64, @floatFromInt(hi_n)), hi_n, lo / @as(f64, @floatFromInt(lo_n)), lo_n });
        }
    }
    try out.print("\n  the gates read: C's RMS must beat B's by {d:.2} (MARL5_RMS_EDGE) AND\n", .{th.MARL5_RMS_EDGE});
    try out.print("  C's concentration must beat A's {d:.2} by {d:.2} (MARL5_CONCENTRATION_EDGE);\n", .{ conc_a, th.MARL5_CONCENTRATION_EDGE });
    try out.print("  and RMS(need) over RMS(need × lag) must clear {d:.2} (MARL5_LAG_HELPS)\n", .{th.MARL5_LAG_HELPS});
}

/// MARL-2: the two-level residual hierarchy against flat MARL, on the same
/// seed and the same exemplars. Every number Christian asked to see.
fn hier(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    const pr = try marl.probesOf(gpa, o.m.truth, 0xB0B, o.probe_n);
    defer gpa.free(pr.p);
    defer gpa.free(pr.y);

    var flat = try marl.Model.init(gpa, o.m);
    defer flat.deinit();
    const rms0 = try flat.rms(pr.p, pr.y, null);
    flat.stats = .{};
    try flat.stream_n(o.exemplars);
    const rms_flat = try flat.rms(pr.p, pr.y, null);

    var h = try marl.Hierarchy.init(gpa, o.m, o.p);
    defer h.deinit();
    try h.stream_n(o.exemplars);
    const rms_hier = try h.rms(pr.p, pr.y, null);
    const rms_parent = try h.parentRms(pr.p, pr.y);

    const V_SHELL = marl.volumeOf(o.m.truth, marl.Truth.inShell);
    const V_QUIET = marl.volumeOf(o.m.truth, marl.Truth.inQuiet);
    const prec = h.precision();

    const hc: f64 = @floatFromInt(h.child.opts.regions);
    const child_occ = @as(f64, @floatFromInt(h.child.occupiedRegions())) / (hc * hc * hc);
    const child_shell = h.child.densityIn(marl.Truth.inShell, V_SHELL);
    const child_conc = h.childConcentration();

    const pc: f64 = @floatFromInt(o.m.regions);
    const parent_cell = 1.0 / (pc * pc * pc);
    const parent_occ = @as(f64, @floatFromInt(h.parent.occupiedRegions())) * parent_cell;
    const parent_density = if (parent_occ > 0) @as(f64, @floatFromInt(h.parent.kernels.items.len)) / parent_occ else 0;
    const parent_shell = h.parent.densityIn(marl.Truth.inShell, V_SHELL);
    const parent_conc = if (parent_density > 0) @as(f64, parent_shell) / parent_density else 0;

    const work_h = h.parent.stats.updates + h.child.stats.updates;
    const work_ratio = @as(f64, @floatFromInt(work_h)) / @as(f64, @floatFromInt(@max(1, flat.stats.updates)));

    try out.print("MARL-2 — the residual hierarchy against flat MARL ({s})\n", .{@tagName(builtin.mode)});
    try out.print("  target: {d} feature(s), sharpness ×{d:.1}, frequency ×{d:.1}; {d} exemplars, {d} probes, seed {d}\n", .{ o.m.truth.features, o.m.truth.sharpness, o.m.truth.frequency, o.exemplars, o.probe_n, o.m.seed });
    try out.print("  pressure: mean post-update residual > {d:.3} over ≥ {d} events; child grid ×{d}; child births by {s}\n  routing: p = min(1, {d:.3} + {d:.2}·|residual|)\n\n", .{ o.p.threshold, o.p.min_events, o.p.refine, @tagName(o.p.child_birth), o.p.route_floor, o.p.route_gain });

    try out.print("  {s:<26} {s:>10} {s:>9} {s:>12} {s:>9}\n", .{ "", "RMS", "kernels", "updates", "mean |w|" });
    try out.print("  {s:<26} {d:>10.5} {d:>9} {d:>12} {d:>9.4}\n", .{ "empty", rms0, 0, 0, 0.0 });
    try out.print("  {s:<26} {d:>10.5} {d:>9} {d:>12} {d:>9.4}\n", .{ "flat MARL", rms_flat, flat.kernels.items.len, flat.stats.updates, flat.weightStats().mean_abs });
    try out.print("  {s:<26} {d:>10.5} {d:>9} {d:>12} {d:>9.4}\n", .{ "  hierarchy: parent alone", rms_parent, h.parent.kernels.items.len, h.parent.stats.updates, h.parent.weightStats().mean_abs });
    try out.print("  {s:<26} {d:>10.5} {d:>9} {d:>12} {d:>9.4}\n", .{ "  hierarchy: parent + child", rms_hier, h.child.kernels.items.len, h.child.stats.updates, h.child.weightStats().mean_abs });

    try out.print("\n  gain against empty:  flat {d:.2}   hierarchy {d:.2}   ratio {d:.2}  (predicted ≥ {d:.1}, MARL2_SHARPNESS_RETENTION)\n", .{ rms0 / rms_flat, rms0 / rms_hier, (rms0 / rms_hier) / (rms0 / rms_flat), th.MARL2_SHARPNESS_RETENTION });
    try out.print("  the child's own contribution: parent alone {d:.5} → with child {d:.5}, a factor of {d:.2}\n", .{ rms_parent, rms_hier, rms_parent / rms_hier });

    try out.print("\n  unrefinement: {d} regions retired, {d} child kernels with them\n", .{ h.unrefined_count, h.child_retired });
    try out.print("\n  WHERE the capacity went\n", .{});
    try out.print("    refined regions        {d:>6} of {d}   {d} touch the shell band, {d} do not\n", .{ prec.refined, h.parent.regions.len, prec.on_shell, prec.false_positive });
    try out.print("    precision              {d:>6.3}          predicted ≥ {d:.2} (MARL2_PRECISION)\n", .{ if (prec.refined > 0) @as(f32, @floatFromInt(prec.on_shell)) / @as(f32, @floatFromInt(prec.refined)) else 0, th.MARL2_PRECISION });
    try out.print("    exemplars routed       {d:>6.3}          of {d} seen\n", .{ @as(f64, @floatFromInt(h.routed)) / @as(f64, @floatFromInt(h.seen)), h.seen });
    try out.print("    parent frozen          {d:>6} kernels held in refined regions\n", .{h.parent.frozenCount()});
    try out.print("    child in the shell band {d:>5} kernels, {d:.0} per unit³\n", .{ h.child.countIn(marl.Truth.inShell), child_shell });
    try out.print("    child in the quiet slab {d:>5} kernels          predicted {d} (MARL2_CHILD_QUIET)\n", .{ h.child.countIn(marl.Truth.inQuiet), th.MARL2_CHILD_QUIET });
    const ceil_v: f64 = if (child_occ > 0) child_occ / @as(f64, V_SHELL) else 0;
    try out.print("    CONCENTRATION          parent {d:>5.2}   child {d:.2}   of a perfect {d:.2} ({d:.0}%)\n", .{ parent_conc, child_conc, ceil_v, if (ceil_v > 0) 100 * child_conc / ceil_v else 0 });
    try out.print("    child kernels          {d:>6}          MARL-2 spent {d} here (MARL3_CAPACITY_CAP)\n", .{ h.child.kernels.items.len, th.MARL3_MARL2_CHILD_KERNELS[if (o.m.truth.sharpness >= 4) @as(usize, 2) else if (o.m.truth.sharpness >= 2) @as(usize, 1) else @as(usize, 0)] });
    try out.print("    usable capacity        {d:>6.3} of child kernels have ≥ 10 updates; {d:.0} updates each on average\n", .{ h.child.trainedFraction(10), h.child.meanUpdates() });
    {
        const share = h.bandShareOfRefined();
        const routed_band = if (h.routed > 0) @as(f32, @floatFromInt(h.routed_in_band)) / @as(f32, @floatFromInt(h.routed)) else 0;
        const child_band = if (h.child.kernels.items.len > 0) @as(f32, @floatFromInt(h.child.countIn(marl.Truth.inShell))) / @as(f32, @floatFromInt(h.child.kernels.items.len)) else 0;
        try out.print("\n  THE EVIDENCE STREAM — a birth can only happen where an exemplar is\n", .{});
        try out.print("    the band is             {d:>6.4} of the refined volume\n", .{share});
        const offered_band = if (h.offered > 0) @as(f32, @floatFromInt(h.offered_in_band)) / @as(f32, @floatFromInt(h.offered)) else 0;
        try out.print("    of exemplars OFFERED    {d:>6.4} landed in it — before routing\n", .{offered_band});
        try out.print("    of exemplars ROUTED     {d:>6.4} landed in it — the stream the child learns from\n", .{routed_band});
        try out.print("    the router's duty cycle {d:>6.4}   stream concentration {d:.2}   kernels/stream {d:.2}\n", .{
            if (h.offered > 0) @as(f32, @floatFromInt(h.routed)) / @as(f32, @floatFromInt(h.offered)) else 0,
            if (share > 0) routed_band / share else 0,
            if (routed_band > 0) child_band / routed_band else 0,
        });
        try out.print("    of child kernels        {d:>6.4} landed in it — what the birth rule made of that stream\n", .{child_band});
    }

    // The signal's own separability, printed whatever the threshold did —
    // a refiner that fired on nothing and a refiner that fired on
    // everything look identical in the table above, and neither says
    // whether the STATISTIC can tell the two populations apart.
    {
        var on_lo: f32 = 1e9;
        var on_hi: f32 = 0;
        var on_sum: f64 = 0;
        var on_n: u32 = 0;
        var off_hi: f32 = 0;
        var off_sum: f64 = 0;
        var off_n: u32 = 0;
        for (0..h.parent.regions.len) |i| {
            const idx: u32 = @intCast(i);
            if (h.covered_events[idx] < o.p.min_events) continue;
            const pv = h.pressureOf(idx);
            if (h.regionMeetsShell(idx)) {
                on_lo = @min(on_lo, pv);
                on_hi = @max(on_hi, pv);
                on_sum += pv;
                on_n += 1;
            } else {
                off_hi = @max(off_hi, pv);
                off_sum += pv;
                off_n += 1;
            }
        }
        try out.print("\n  the pressure statistic's own separability ({d} regions judged)\n", .{on_n + off_n});
        if (on_n > 0) try out.print("    shell-band regions     {d:>3}   mean {d:.5}  range {d:.5} … {d:.5}\n", .{ on_n, on_sum / @as(f64, @floatFromInt(on_n)), on_lo, on_hi });
        if (off_n > 0) try out.print("    everywhere else        {d:>3}   mean {d:.5}  highest {d:.5}\n", .{ off_n, off_sum / @as(f64, @floatFromInt(off_n)), off_hi });
    }

    try out.print("\n  what it cost\n", .{});
    try out.print("    work ratio             {d:>6.3}          predicted ≤ {d:.1} (MARL2_WORK_RATIO)\n", .{ work_ratio, th.MARL2_WORK_RATIO });
    try out.print("    mean |w|               parent {d:.4}   child {d:.4}   both must stay under {d:.2}\n", .{ h.parent.weightStats().mean_abs, h.child.weightStats().mean_abs, th.MARL1_OVERRESPONSIBILITY });
    _ = V_QUIET;
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
    for (pr.p, before) |p, *b| b.* = (try model.predict(p))[0];

    // One event, at a point the model has certainly seen structure near.
    const x = [3]f32{ 0.30, 0.42, 0.46 };
    const ev = try model.observe(x, .{marl.truth(x)});

    const bound = th.marl0ReachBound(model.h, model.opts.steps, model.opts.trust);
    var max_beyond: f32 = 0;
    var changed_beyond: u32 = 0;
    var furthest_change: f32 = 0;
    var buckets: [12]f32 = [_]f32{0} ** 12;
    var counts: [12]u32 = [_]u32{0} ** 12;
    for (pr.p, before) |p, b| {
        const a = (try model.predict(p))[0];
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
            const y = (try model.predict(p))[0];
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
            const y = (try model.predict(p))[0];
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

// ── MARL-11: the marble ───────────────────────────────────────────────

/// The 2×2 against `rbf.fit` (docs/MARL_CAMPAIGN.md, and `src/marble.zig`'s
/// head for why the arms are shaped this way). The fixture is built here,
/// procedurally — no World, no sim, no baked asset — so the campaign's
/// first external baseline is still a `marl-run` measurement and not a
/// seedbed one. The REAL marble's volume needs the sim to bake it and is
/// `loam-run --rbf-arms`.
fn marbleArms(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    var vol = try marble_mod.sheetVolume(gpa, marble_mod.FIXTURE_RES, marble_mod.FIXTURE_EXTENT, 0);
    defer vol.deinit(gpa);

    var mo = o.mo;
    const resp = mo.m.responsibility; // G24's, unless the user asked
    mo.m = o.m;
    if (!o.resp_set) mo.m.responsibility = resp;
    mo.seed = o.m.seed;
    mo.verbose = true;

    try out.print("marl-run — MARL-11, the marble, {s}\n", .{@tagName(builtin.mode)});
    try out.print("  fixture {d}³ over extent {d:.0} (a power of two: the conversion is exact), vein {d:.2}\n", .{ marble_mod.FIXTURE_RES, marble_mod.FIXTURE_EXTENT, marble_mod.FIXTURE_VEIN });
    try out.print("  {d} distinct exemplars each side; rbf re-reads them for {d} batches of {d}\n", .{ mo.pool, mo.iterations, mo.batch });
    try out.print("  MARL: regions {d}³, budget {d}, θ {d:.3}, coverage {d:.2}, responsibility {d:.2}\n\n", .{ mo.m.regions, mo.m.budget, mo.m.threshold, mo.m.coverage, mo.m.responsibility });

    const arms_out = try marble_mod.run(1, gpa, &vol, marble_mod.FIXTURE_VEIN, mo);
    try marble_mod.report(out, arms_out);

    try out.print("\n  pre-registered (tools/marl11_predict.py, before the run):\n", .{});
    try out.print("    concentration ≥ {d:.1}   B/A ≥ {d:.1}   D/B ≤ {d:.1}   C/A ≤ {d:.1}\n", .{
        th.MARL11_CONCENTRATION, th.MARL11_ORACLE_WORTH, th.MARL11_DISCOVERY, th.MARL11_ONLINE_COST,
    });
    try out.print("  MARL births {d} / updates {d} blind, {d} / {d} biased\n", .{ arms_out.d.births, arms_out.d.updates, arms_out.c.births, arms_out.c.updates });

    // The evidence gradient. MARL-6R established under-evidence is a
    // smooth gradient rather than a cliff, so what the blind arm's RMS
    // does as the stream lengthens says whether the gap to batch Adam is
    // a shortage of data or a property of the mechanism. Outside the
    // equal-data protocol and therefore outside the gate: reported, never
    // compared against a threshold.
    try out.print("\n  the evidence gradient (arm D alone, past the equal-data protocol)\n", .{});
    try out.print("    {s:>10} {s:>8} {s:>10} {s:>7} {s:>8}\n", .{ "exemplars", "kernels", "RMS band", "conc.", "seconds" });
    for ([_]u32{ 1, 4, 16, 64 }) |mult| {
        var m2 = mo;
        m2.pool = mo.pool * mult;
        const arm = try marble_mod.blindArm(1, gpa, &vol, marble_mod.FIXTURE_VEIN, m2);
        try out.print("    {d:>10} {d:>8} {d:>10.5} {d:>7.2} {d:>8.2}\n", .{ arm.exemplars, arm.kernels, arm.rms_band, arm.concentration, arm.seconds });
    }
}

// ── MARL-12: nine channels on one geometry ────────────────────────────

/// The widened kernel put to the question it was widened for
/// (`tools/marl12_predict.py`): what does sharing ONE centre and ONE shape
/// across nine weights cost, and what does it save?
///
/// The fixture is MARL-11's sheet with materials on it — two of them,
/// split across x, because with a single material every channel is the
/// blend times a constant, the nine are exactly collinear, and a shared
/// basis is free by construction. A fixture that can only agree is not a
/// fixture.
fn marbleNine(gpa: std.mem.Allocator, o: Opts) !void {
    const out = std.io.getStdOut().writer();
    var vol = try marble_mod.sheetVolume(gpa, marble_mod.FIXTURE_RES, marble_mod.FIXTURE_EXTENT, loam.bark.ALL_COLUMNS);
    defer vol.deinit(gpa);

    var mo = o.mo;
    const resp = mo.m.responsibility;
    mo.m = o.m;
    if (!o.resp_set) mo.m.responsibility = resp;
    mo.seed = o.m.seed;
    mo.verbose = true;
    mo.normalise = true; // emissive reaches 6 where the blend reaches 1

    try out.print("marl-run — MARL-12, nine channels, {s}\n", .{@tagName(builtin.mode)});
    try out.print("  fixture {d}³ over extent {d:.0}, vein {d:.2}, TWO materials split across x\n", .{ marble_mod.FIXTURE_RES, marble_mod.FIXTURE_EXTENT, marble_mod.FIXTURE_VEIN });
    try out.print("  {d} distinct exemplars each side; rbf re-reads them for {d} batches of {d}\n\n", .{ mo.pool, mo.iterations, mo.batch });

    const nine = try marble_mod.run(9, gpa, &vol, marble_mod.FIXTURE_VEIN, mo);
    try marble_mod.report(out, nine);

    // The sharing ratio: the SAME learner, the same stream, the same
    // fixture, at one channel and at nine. MARL against MARL, which is
    // the only way to isolate what the sharing did — an rbf arm here
    // would be fitting nine on both sides and could not tell us.
    var one_o = mo;
    one_o.normalise = false; // at one channel the scale is the blend's own
    const c1 = try marble_mod.blindArm(1, gpa, &vol, marble_mod.FIXTURE_VEIN, one_o);
    const c9 = try marble_mod.blindArm(9, gpa, &vol, marble_mod.FIXTURE_VEIN, mo);
    try out.print("\n  sharing — the blend's own error, learned alone against learned with eight others\n", .{});
    try out.print("    {s:>10} {s:>9} {s:>11} {s:>9} {s:>9}\n", .{ "channels", "kernels", "RMS blend", "floats/k", "bytes" });
    for ([_]struct { c: usize, a: marble_mod.Arm }{ .{ .c = 1, .a = c1 }, .{ .c = 9, .a = c9 } }) |r| {
        try out.print("    {d:>10} {d:>9} {d:>11.5} {d:>9} {d:>9}\n", .{ r.c, r.a.kernels, r.a.rms_c0, 9 + r.c, r.a.kernels * (9 + r.c) * 4 });
    }
    try out.print("    K(9)/K(1)  {d:.3}   predicted ≤ {d:.2}\n", .{ @as(f32, @floatFromInt(c9.kernels)) / @as(f32, @floatFromInt(c1.kernels)), th.MARL12_COUNT });
    try out.print("    blend RMS  {d:.3}   predicted ≤ {d:.2}\n", .{ c9.rms_c0 / c1.rms_c0, th.MARL12_SHARING });
    try out.print("    nine channels packed cost {d} floats a kernel against {d} for nine separate scalar models ({d:.2}x)\n", .{ 9 + @as(usize, 9), 9 * 10, @as(f32, 18) / 90 });
    try out.print("    D/B at nine {d:.3}   predicted ≤ {d:.2}\n", .{ nine.d.rms_band / nine.b.rms_band, th.MARL12_ONLINE_COST });
}

// ── MARL-17: a real level ─────────────────────────────────────────────

/// The occlusion cache on `oa_spirit3`, which is the fixture MARL-13's
/// "sparse in the domain" question was really asking about. A grove of
/// spheres has open sky and crevices; a deathmatch level has ROOMS,
/// DOORWAYS and SCALE SEPARATION, and its playable space is a thin shell
/// inside a mostly-empty bounding cube.
fn q3Cache(gpa: std.mem.Allocator, o: Opts, path: []const u8) !void {
    const out = std.io.getStdOut().writer();
    var vol = try cache.readVolume(gpa, path);
    defer vol.deinit(gpa);
    const cell = vol.extent / @as(f32, @floatFromInt(vol.res));

    var co = cache.Options{ .ray_budget = o.exemplars * 16, .probes = 1024 };
    co.ao = cache.scaledAo(&vol, 1.0 / 18.0); // occlusion is a room-scale effect
    co.seed = o.m.seed;
    co.m = o.m;
    co.m.rate_w = 0.05; // MARL-13: the rate is the noise floor
    co.invert = true; // MARL-13: a zero background is the free one
    co.surface_band = 2 * cell; // where a renderer actually shades

    var solid: usize = 0;
    for (vol.data) |x| {
        if (x > 0) solid += 1;
    }
    try out.print("marl-run — MARL-17, {s}, {s}\n", .{ path, @tagName(builtin.mode) });
    try out.print("  {d}³ over {d:.0} units ({d:.1} a voxel), φ {d:.1}..{d:.1}, solid {d:.4} of the cube\n", .{ vol.res, vol.extent, cell, vol.min, vol.max, @as(f64, @floatFromInt(solid)) / @as(f64, @floatFromInt(vol.data.len)) });
    try out.print("  AO: {d} rays, reach {d:.0} units, step {d:.1}; queries within {d:.0} units of a surface\n", .{ co.ao.rays, co.ao.reach, co.ao.step, co.surface_band });
    try out.print("  {d} marched directions the budget, {d} probes at {d} rays each\n\n", .{ co.ray_budget, co.probes, cache.TRUTH_RAYS });

    var pr = try cache.probesOf(gpa, &vol, co.ao, co.probes, co.seed, co.surface_band);
    defer pr.deinit(gpa);
    var mean: f64 = 0;
    for (pr.y) |y| mean += y;
    const mu = mean / @as(f64, @floatFromInt(pr.y.len));
    var varsum: f64 = 0;
    for (pr.y) |y| varsum += (y - mu) * (y - mu);
    const sd = @sqrt(varsum / @as(f64, @floatFromInt(pr.y.len)));
    // The only honest denominator: what predicting the MEAN everywhere
    // scores. Any model that does not beat this has learned nothing, and
    // an RMS quoted without it is a number with no scale.
    try out.print("  the field: mean AO {d:.4}, sd {d:.4} — predicting the mean everywhere scores {d:.5}, which is what every arm below has to beat\n", .{ mu, sd, sd });

    var t = try cache.teach(gpa, &vol, co, pr);
    defer t.deinit();
    const g = try cache.gridArm(gpa, &vol, co, t.bytes(), pr, "dense grid, trilinear");
    try out.print("\n  {s:<26} {s:>8} {s:>10} {s:>9} {s:>9}\n", .{ "arm", "kernels", "KiB", "RMS", "query ns" });
    try out.print("  {s:<26} {d:>8} {d:>10.1} {d:>9.5} {d:>9.0}\n", .{ "MARL, online", t.kernels(), @as(f64, @floatFromInt(t.bytes())) / 1024.0, t.rms, t.query_ns });
    try out.print("  {s:<26} {d:>8} {d:>10.1} {d:>9.5} {d:>9.0}\n", .{ "dense grid, trilinear", g.grid_res, @as(f64, @floatFromInt(g.bytes)) / 1024.0, g.rms, g.query_ns });
    try out.print("  MARL/grid {d:.3}\n", .{t.rms / g.rms});

    // The production pipeline, end to end: DISTIL to a coarser basis
    // (MARL-14) and QUANTIZE at 54 bits with region-relative centres
    // (MARL-15). The teacher above is the master copy; this is what ships.
    var so = co.m;
    so.regions = 3;
    var st = try cache.distil(gpa, &t.model, &vol, co, so, o.exemplars, pr);
    defer st.deinit();
    const one: [loam.rbf.CHANNELS]f32 = [_]f32{1} ** loam.rbf.CHANNELS;
    var set = try loam.marble.setOf(gpa, &st.model, vol.extent, vol.columns, vol.hash, one);
    defer set.deinit(gpa);
    var bits = cache.Bits{ .mu = 6, .logd = 5, .off = 5, .w = 6 };
    bits.regions = so.regions;
    _ = cache.quantizeSet(&set, bits);
    const q_rms = cache.rmsOfSetInverted(&set, pr);
    const q_bytes = bits.bytesFor(set.kernels.len);
    const qg = try cache.gridArm(gpa, &vol, co, q_bytes, pr, "grid at the shipped size");

    try out.print("\n  the pipeline — distil to a coarser basis, then quantize\n", .{});
    try out.print("  {s:<26} {s:>8} {s:>10} {s:>9}\n", .{ "stage", "kernels", "KiB", "RMS" });
    try out.print("  {s:<26} {d:>8} {d:>10.1} {d:>9.5}\n", .{ "the master, f32", t.kernels(), @as(f64, @floatFromInt(t.bytes())) / 1024.0, t.rms });
    try out.print("  {s:<26} {d:>8} {d:>10.1} {d:>9.5}\n", .{ "distilled, regions 3", st.kernels(), @as(f64, @floatFromInt(st.bytes())) / 1024.0, st.rms });
    try out.print("  {s:<26} {d:>8} {d:>10.1} {d:>9.5}\n", .{ "…and quantized, 54 bits", set.kernels.len, @as(f64, @floatFromInt(q_bytes)) / 1024.0, q_rms });
    try out.print("  {s:<26} {d:>8} {d:>10.1} {d:>9.5}\n", .{ "dense grid, same bytes", qg.grid_res, @as(f64, @floatFromInt(qg.bytes)) / 1024.0, qg.rms });
    try out.print("  shipped/grid {d:.3}; {d:.1}× off the master for {d:.2}× the error\n", .{
        q_rms / qg.rms,
        @as(f64, @floatFromInt(t.bytes())) / @as(f64, @floatFromInt(q_bytes)),
        q_rms / t.rms,
    });
}
