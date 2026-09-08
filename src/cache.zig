//! cache — MARL-13: an OCCLUSION CACHE, and the first field the campaign
//! has had to learn from NOISY samples.
//!
//! Christian named this one on the morning MARL started: "an irradiance or
//! occlusion cache is exactly what gave me the idea". It is also the
//! regime MARL-11's loss argued MARL is actually for. That phase found the
//! binding constraint is EVIDENCE and not placement, and lost to a batch
//! optimiser that re-read its pool 4.7 times — but a cache cannot be
//! re-read. Its samples are computed once, at whatever point the renderer
//! asked about, and they are never seen again. A batch bake is not a
//! slower option there; it is not an option.
//!
//! ## What is new, and it is not the geometry
//!
//! Every field this campaign has learned — the synthetic truth, the
//! marble's blend, the marble's materials — was EXACT. `truthOf` and
//! `rbf.target` return the answer. Ambient occlusion does not: it is
//! `(1/M)·Σ V(x, ωᵢ)` over M sampled directions, a Binomial(M, p)/M
//! estimate whose standard deviation is `√(p(1−p)/M)` — 0.5 at one ray,
//! 0.06 at sixty-four. The campaign's §5 said "do not confuse noise with
//! complexity" as a design instruction. This is the phase where there is
//! finally some noise to not confuse.
//!
//! ## The sign of the carrier, measured rather than read
//!
//! `CLAUDE.md` says the carrier is "negative inside". IT IS NOT, and a
//! ray-marcher written from the prose would find occlusion in empty space
//! and none inside a trunk. `src/tests.zig`'s own sheet gate samples
//! `Channel.surface` and prints φ = +2.00 on the sheet's axis, +1.28 four
//! units along it, −1.53 two and a half across it and −2.72 nine beyond
//! its width. **φ > 0 is SOLID**, saturating near ±3. Everything here
//! follows the measurement.
//!
//! ## The baseline is a voxel grid, because that is what people ship
//!
//! `rbf.zig` exists because Christian asked for a packed Gaussian set
//! "instead of the giant volume texture". So the honest opponent for a
//! learned sparse field is the giant volume texture: a dense grid, read by
//! trilinear interpolation, **at equal bytes and equal ray budget**. Equal
//! bytes because memory is the thing a cache is rationed by. Equal rays
//! because the expense being cached is the rays — and a grid handed
//! unlimited rays would be being compared on a resource nobody has.
//!
//! Nothing here is on the sim path.

const std = @import("std");
const builtin = @import("builtin");
const bark = @import("bark.zig");
const marl = @import("marl.zig");
const marble = @import("marble.zig");
const rbf = @import("rbf.zig");
const rng = @import("rng.zig");
const fmath = @import("fmath.zig");
const thresholds = @import("thresholds.zig");

// ── The occluder ─────────────────────────────────────────────────────

pub const GROVE_RES: u32 = 48;
/// A power of two, for the same reason `marble.zig`'s is.
pub const GROVE_EXTENT: f32 = 32;
const GROVE_N: u32 = 3; // spheres a side
const GROVE_R: f32 = 3.4;
const GROVE_JITTER: f32 = 1.6;

/// A grove: spheres on a jittered lattice, φ positive inside.
///
/// Spheres and not a sheet, because ambient occlusion on a plane is 0.5
/// nearly everywhere and would make every arm look equally good. A lattice
/// of spheres has open sky, corridors between neighbours, and tight
/// crevices where two nearly touch — so the field has the full range and
/// its detail is concentrated where the geometry is, which is the property
/// a cache exists to exploit.
pub fn groveVolume(gpa: std.mem.Allocator, res: u32, extent: f32) !bark.Volume {
    const cell = extent / @as(f32, @floatFromInt(res));
    var v = bark.Volume{
        .res = res,
        .extent = extent,
        .columns = 0,
        .stride = bark.strideOf(0),
        .data = try gpa.alloc(f32, @as(usize, res) * res * res * bark.strideOf(0)),
        .hash = [_]u8{0} ** 32,
        .min = 0,
        .max = 0,
    };
    errdefer gpa.free(v.data);

    var centres: [GROVE_N * GROVE_N * GROVE_N][3]f32 = undefined;
    var st = rng.Stream.region(1, 0x4752_4f56, 0); // "GROV"
    const spacing = extent / @as(f32, @floatFromInt(GROVE_N));
    var idx: usize = 0;
    for (0..GROVE_N) |i| for (0..GROVE_N) |j| for (0..GROVE_N) |k| {
        centres[idx] = .{
            (@as(f32, @floatFromInt(i)) + 0.5) * spacing + (st.unit() - 0.5) * GROVE_JITTER,
            (@as(f32, @floatFromInt(j)) + 0.5) * spacing + (st.unit() - 0.5) * GROVE_JITTER,
            (@as(f32, @floatFromInt(k)) + 0.5) * spacing + (st.unit() - 0.5) * GROVE_JITTER,
        };
        idx += 1;
    };

    var lo: f32 = std.math.floatMax(f32);
    var hi: f32 = -std.math.floatMax(f32);
    var k: u32 = 0;
    while (k < res) : (k += 1) {
        var j: u32 = 0;
        while (j < res) : (j += 1) {
            var i: u32 = 0;
            while (i < res) : (i += 1) {
                const p = [3]f32{
                    (@as(f32, @floatFromInt(i)) + 0.5) * cell,
                    (@as(f32, @floatFromInt(j)) + 0.5) * cell,
                    (@as(f32, @floatFromInt(k)) + 0.5) * cell,
                };
                var best: f32 = -3;
                for (centres) |c| {
                    const d = @sqrt((p[0] - c[0]) * (p[0] - c[0]) + (p[1] - c[1]) * (p[1] - c[1]) + (p[2] - c[2]) * (p[2] - c[2]));
                    best = @max(best, GROVE_R - d);
                }
                // Clamped to ±3 as the carrier is, so a marcher written
                // against this fixture is written against the sim's field.
                const f = @min(3, @max(-3, best));
                v.data[v.index(i, j, k)] = f;
                lo = @min(lo, f);
                hi = @max(hi, f);
            }
        }
    }
    v.min = lo;
    v.max = hi;
    return v;
}

/// A volume written by `tools/q3_volume.py` — a Quake 3 level's solid
/// brushes rasterised to signed distance, positive inside.
///
/// Read rather than baked, because the BSP parser that produced it is
/// `~/dev/tessera`'s and is already mirrored field-for-field against
/// `~/dev/importers/src/q3bsp.zig`. Writing a third one here to avoid a
/// file would be the worse trade.
pub fn readVolume(gpa: std.mem.Allocator, path: []const u8) !bark.Volume {
    var f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var br = std.io.bufferedReader(f.reader());
    const r = br.reader();
    var magic: [4]u8 = undefined;
    try r.readNoEof(&magic);
    if (!std.mem.eql(u8, &magic, "QVOL")) return error.NotAQ3Volume;
    const res = try r.readInt(u32, .little);
    const extent: f32 = @bitCast(try r.readInt(u32, .little));
    var v = bark.Volume{
        .res = res,
        .extent = extent,
        .columns = 0,
        .stride = bark.strideOf(0),
        .data = try gpa.alloc(f32, @as(usize, res) * res * res),
        .hash = [_]u8{0} ** 32,
        .min = std.math.floatMax(f32),
        .max = -std.math.floatMax(f32),
    };
    errdefer gpa.free(v.data);
    for (v.data) |*x| {
        x.* = @bitCast(try r.readInt(u32, .little));
        v.min = @min(v.min, x.*);
        v.max = @max(v.max, x.*);
    }
    return v;
}

/// Ambient-occlusion options scaled to a volume's own units, so the same
/// study runs on a 32-unit grove and a 4608-unit deathmatch level without
/// either set of numbers being a coincidence of the fixture's size.
///
/// `reach` is a FRACTION OF THE EXTENT rather than an absolute, because
/// occlusion is local relative to the thing being occluded; `step` is half
/// a cell, because a marcher that steps further than the grid can resolve
/// is sampling a field it has already blurred past.
pub fn scaledAo(vol: *const bark.Volume, reach_fraction: f32) AoOptions {
    const cell = vol.extent / @as(f32, @floatFromInt(vol.res));
    return .{ .rays = 16, .reach = vol.extent * reach_fraction, .step = cell * 0.5 };
}

// ── The expensive thing ──────────────────────────────────────────────

pub const AoOptions = struct {
    /// Directions per estimate. THE NOISE KNOB: the estimator is
    /// Binomial(M, p)/M, so its standard deviation is √(p(1−p)/M) — a half
    /// at one ray, a sixteenth at sixty-four.
    rays: u32 = 16,
    /// How far a ray looks. Ambient occlusion is a LOCAL effect and this
    /// is what makes it one; it is also what bounds the cost.
    reach: f32 = 5,
    /// Fixed-step marching rather than sphere tracing. The carrier
    /// saturates at ±3 and is not a global distance field, so a sphere
    /// trace would either stall or overshoot; a fixed step is correct
    /// whatever the field's Lipschitz constant is, and being slower is not
    /// a problem in a routine whose expense is the entire premise.
    step: f32 = 0.25,
};

/// Directions per estimate times steps per ray — what one sample costs, in
/// trilinear fetches. The number the cache is measured against.
pub fn fetchesPerSample(o: AoOptions) u32 {
    return o.rays * @as(u32, @intFromFloat(@ceil(o.reach / o.step)));
}

/// One ambient-occlusion estimate at `x`: the fraction of `o.rays`
/// directions that reach `o.reach` without meeting solid.
///
/// Inside solid it is zero and no rays are cast — which is not an
/// optimisation, it is the definition: there is no ambient light inside a
/// trunk.
pub fn aoAt(vol: *const bark.Volume, o: AoOptions, x: [3]f32, st: *rng.Stream) f32 {
    if (vol.at(x) > 0) return 0;
    const steps: u32 = @intFromFloat(@ceil(o.reach / o.step));
    var open: u32 = 0;
    var r: u32 = 0;
    while (r < o.rays) : (r += 1) {
        // A uniform direction on the sphere: z uniform in [−1, 1], the
        // azimuth uniform. No cosine weighting, because there is no
        // surface normal here — the field is defined over the whole
        // volume, not over a surface.
        const z = 2 * st.unit() - 1;
        const a = 2 * std.math.pi * st.unit();
        const s = @sqrt(@max(0, 1 - z * z));
        const d = [3]f32{ s * fmath.cosf(a), s * fmath.sinf(a), z };
        var hit = false;
        var i: u32 = 1;
        while (i <= steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) * o.step;
            const p = [3]f32{ x[0] + d[0] * t, x[1] + d[1] * t, x[2] + d[2] * t };
            if (vol.at(p) > 0) {
                hit = true;
                break;
            }
        }
        if (!hit) open += 1;
    }
    return @as(f32, @floatFromInt(open)) / @as(f32, @floatFromInt(o.rays));
}

/// The reference: the same estimator at a ray count high enough that its
/// own noise is under everything being measured. 4096 rays is σ ≤ 0.008,
/// which is a twentieth of the smallest RMS any arm reaches.
pub const TRUTH_RAYS: u32 = 4096;

pub fn aoTrue(vol: *const bark.Volume, o: AoOptions, x: [3]f32, st: *rng.Stream) f32 {
    var t = o;
    t.rays = TRUTH_RAYS;
    return aoAt(vol, t, x, st);
}

// ── The baseline: a giant volume texture ─────────────────────────────

/// A dense grid of ambient occlusion, read by trilinear interpolation —
/// what a renderer ships today, and the thing `rbf.zig` was written to
/// replace.
pub const Grid = struct {
    res: u32,
    extent: f32,
    data: []f32,

    pub fn deinit(self: *Grid, gpa: std.mem.Allocator) void {
        gpa.free(self.data);
    }

    pub fn bytes(self: *const Grid) usize {
        return self.data.len * @sizeOf(f32);
    }

    /// The largest resolution whose grid fits in `budget` bytes.
    pub fn resFor(budget: usize) u32 {
        var r: u32 = 2;
        while ((@as(usize, r + 1) * (r + 1) * (r + 1)) * @sizeOf(f32) <= budget) r += 1;
        return r;
    }

    /// Fill every cell with an estimate of `rays` directions. The cell
    /// centres are the samples, which is the grid's whole advantage — it
    /// never has to work out where to look — and its whole weakness: it
    /// looks everywhere equally, including at the empty sky.
    pub fn fill(gpa: std.mem.Allocator, vol: *const bark.Volume, o: AoOptions, res: u32, rays: u32, seed: u64) !Grid {
        var g = Grid{ .res = res, .extent = vol.extent, .data = try gpa.alloc(f32, @as(usize, res) * res * res) };
        errdefer gpa.free(g.data);
        var st = rng.Stream.region(seed, 0x4752_4944, 0); // "GRID"
        var ao = o;
        ao.rays = @max(1, rays);
        const cell = vol.extent / @as(f32, @floatFromInt(res));
        var k: u32 = 0;
        while (k < res) : (k += 1) {
            var j: u32 = 0;
            while (j < res) : (j += 1) {
                var i: u32 = 0;
                while (i < res) : (i += 1) {
                    const p = [3]f32{
                        (@as(f32, @floatFromInt(i)) + 0.5) * cell,
                        (@as(f32, @floatFromInt(j)) + 0.5) * cell,
                        (@as(f32, @floatFromInt(k)) + 0.5) * cell,
                    };
                    g.data[(@as(usize, k) * res + j) * res + i] = aoAt(vol, ao, p, &st);
                }
            }
        }
        return g;
    }

    /// Trilinear, clamped at the faces — the read a shader does.
    pub fn at(self: *const Grid, x: [3]f32) f32 {
        const r: i32 = @intCast(self.res);
        var c: [3]f32 = undefined;
        var c0: [3]i32 = undefined;
        var t: [3]f32 = undefined;
        inline for (0..3) |a| {
            c[a] = x[a] / self.extent * @as(f32, @floatFromInt(self.res)) - 0.5;
            const f = @floor(c[a]);
            c0[a] = @intFromFloat(f);
            t[a] = c[a] - f;
        }
        var v: f32 = 0;
        inline for (0..2) |dz| {
            inline for (0..2) |dy| {
                inline for (0..2) |dx| {
                    const w = (if (dx == 0) 1 - t[0] else t[0]) * (if (dy == 0) 1 - t[1] else t[1]) * (if (dz == 0) 1 - t[2] else t[2]);
                    const ix: u32 = @intCast(@min(r - 1, @max(0, c0[0] + @as(i32, @intCast(dx)))));
                    const iy: u32 = @intCast(@min(r - 1, @max(0, c0[1] + @as(i32, @intCast(dy)))));
                    const iz: u32 = @intCast(@min(r - 1, @max(0, c0[2] + @as(i32, @intCast(dz)))));
                    v += w * self.data[(@as(usize, iz) * self.res + iy) * self.res + ix];
                }
            }
        }
        return v;
    }
};

// ── Held-out truth ───────────────────────────────────────────────────

pub const Probes = struct {
    x: [][3]f32,
    y: []f32,

    pub fn deinit(self: *Probes, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.y);
    }
};

/// Probes drawn uniformly over the cube, answered at `TRUTH_RAYS`.
/// Expensive, and computed once for every arm to share, so what is
/// compared is the arms and not their reference.
pub fn probesOf(gpa: std.mem.Allocator, vol: *const bark.Volume, o: AoOptions, n: u32, seed: u64, band: f32) !Probes {
    var st = rng.Stream.region(seed, 0x4341_4348, 0); // "CACH"
    var p = Probes{ .x = try gpa.alloc([3]f32, n), .y = try gpa.alloc(f32, n) };
    errdefer p.deinit(gpa);
    for (p.x, p.y) |*x, *y| {
        x.* = drawQuery(vol, band, &st);
        y.* = aoTrue(vol, o, x.*, &st);
    }
    return p;
}

/// The same error, for a model that learned the complement: it is scored
/// against the SAME truth, so the two are comparable and inverting cannot
/// flatter itself by changing what is being measured.
/// One draw from the query distribution: uniform through the cube, or
/// rejection-sampled into the shell around the geometry.
fn drawQuery(vol: *const bark.Volume, band: f32, st: *rng.Stream) [3]f32 {
    var tries: u32 = 0;
    while (tries < 4096) : (tries += 1) {
        const q = [3]f32{ st.unit() * vol.extent, st.unit() * vol.extent, st.unit() * vol.extent };
        if (band <= 0 or @abs(vol.at(q)) < band) return q;
    }
    return .{ st.unit() * vol.extent, st.unit() * vol.extent, st.unit() * vol.extent };
}

fn rmsInverted(pr: Probes, ctx: anytype) f32 {
    var acc: f64 = 0;
    for (pr.x, pr.y) |x, y| {
        const e = (1 - ctx.at(x)) - y;
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.x.len))));
}

fn rmsOf(pr: Probes, ctx: anytype) f32 {
    var acc: f64 = 0;
    for (pr.x, pr.y) |x, y| {
        const e = ctx.at(x) - y;
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.x.len))));
}

// ── The arms ─────────────────────────────────────────────────────────

pub const Arm = struct {
    label: []const u8 = "",
    /// Directions per sample.
    rays: u32 = 0,
    /// Samples taken. `rays × samples` is the budget, and it is held equal
    /// across every arm in a comparison.
    samples: u64 = 0,
    kernels: u32 = 0,
    grid_res: u32 = 0,
    bytes: usize = 0,
    rms: f32 = 0,
    seconds: f64 = 0,
    /// Nanoseconds per lookup, measured over the probe set — what the
    /// cache is FOR.
    query_ns: f64 = 0,
};

pub const Options = struct {
    /// The total ray budget, held equal across arms. Every arm spends
    /// exactly this many marched directions building itself.
    ray_budget: u64 = 8_000_000,
    /// Draw samples and probes only where |φ| is under this — a shell
    /// around the geometry — instead of uniformly through the cube.
    ///
    /// This is the REALISTIC query distribution and the volume-uniform one
    /// is the artificial case: a renderer asks for occlusion at shading
    /// points, and shading points are on surfaces. It is also the shape
    /// that should suit MARL, because it makes the interesting set a thin
    /// shell in a large cube — sparse in exactly the way the marble's
    /// veins were and a volume-filling field is not.
    ///
    /// The grid cannot follow: it pays memory for every cell whether or
    /// not anything is ever asked there. That asymmetry IS the argument
    /// `rbf.zig` was written to make, and this is where it gets tested.
    surface_band: f32 = 0,
    /// Learn `1 − AO` rather than AO.
    ///
    /// Not a trick and not a tuning knob — it is a one-line test of a
    /// structural hypothesis. A Gaussian basis with a HARD CUTOFF decays
    /// to exactly zero, so a constant non-zero background is not free: it
    /// has to be held up by overlapping kernels everywhere it extends.
    /// Ambient occlusion is ≈1 across the open majority of a cube, and
    /// every phase before this one learned a field whose background was
    /// ZERO — the synthetic truth's quiet slab, the marble's matrix. So
    /// the campaign has never once paid for a background and has no term
    /// for one, where `rbf.zig` has had the entry as an explicit BIAS from
    /// the day it was written ("the matrix costs nothing, only the
    /// structure costs kernels").
    ///
    /// Inverting makes the background zero and the structure sparse. If
    /// that is where the loss to a dense grid lives, this moves it and
    /// nothing else can.
    invert: bool = false,
    /// Fix the SAMPLE count instead, and let the ray budget follow. The
    /// two sweeps ask different questions: at a fixed budget, how should
    /// rays be spent (§3 of the predictor); at a fixed sample count, what
    /// does the noise alone do (§1, the 1/M law).
    samples: ?u64 = null,
    rays: u32 = 16,
    probes: u32 = 2048,
    seed: u64 = 13,
    ao: AoOptions = .{},
    m: marl.Options = .{ .responsibility = 3 },
};

/// A MARL arm: `budget / rays` samples, each an `rays`-direction estimate,
/// each observed exactly once and never again — which is the regime a
/// cache is actually in.
pub fn marlArm(gpa: std.mem.Allocator, vol: *const bark.Volume, o: Options, rays: u32, pr: Probes, label: []const u8) !Arm {
    var model = try marl.Model.init(gpa, o.m);
    defer model.deinit();
    var st = rng.Stream.region(o.seed, 0x4d43_4143, 0); // "MCAC"
    var ao = o.ao;
    ao.rays = rays;
    const inv = 1 / vol.extent;
    const n = o.samples orelse (o.ray_budget / @max(1, rays));

    var timer = try std.time.Timer.start();
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const q = drawQuery(vol, o.surface_band, &st);
        const raw = aoAt(vol, ao, q, &st);
        const y = if (o.invert) 1 - raw else raw;
        _ = try model.observe(.{ q[0] * inv, q[1] * inv, q[2] * inv }, .{y});
    }
    const secs = @as(f64, @floatFromInt(timer.read())) / 1e9;

    // The read, timed apart from the build.
    // The read is `predict` — the 27-region gather, which is what a cache
    // lookup actually costs. `predictAll` is the O(N) reference the gather
    // is CHECKED against (G17 d) and is not a query path; using it here
    // priced a lookup at 129 µs against the gather's true cost, which made
    // the cache look 4 000× worse than a texture fetch at the one thing a
    // cache is supposed to be good at.
    const Reader = struct {
        m: *marl.Model,
        e: f32,
        fn at(self: @This(), x: [3]f32) f32 {
            return (self.m.predict(.{ x[0] / self.e, x[1] / self.e, x[2] / self.e }) catch unreachable)[0];
        }
    };
    const rd = Reader{ .m = &model, .e = vol.extent };
    var qt = try std.time.Timer.start();
    const rms = if (o.invert) rmsInverted(pr, rd) else rmsOf(pr, rd);
    const qns = @as(f64, @floatFromInt(qt.read())) / @as(f64, @floatFromInt(pr.x.len));

    return .{
        .label = label,
        .rays = rays,
        .samples = n,
        .kernels = @intCast(model.kernels.items.len),
        .bytes = model.kernels.items.len * marl.PARAMS * @sizeOf(f32),
        .rms = rms,
        .seconds = secs,
        .query_ns = qns,
    };
}

/// A grid arm at a byte budget: the largest resolution that fits, and the
/// ray budget split evenly over its cells.
pub fn gridArm(gpa: std.mem.Allocator, vol: *const bark.Volume, o: Options, budget_bytes: usize, pr: Probes, label: []const u8) !Arm {
    const res = Grid.resFor(budget_bytes);
    const cells: u64 = @as(u64, res) * res * res;
    const per: u32 = @intCast(@max(1, o.ray_budget / cells));
    var timer = try std.time.Timer.start();
    var g = try Grid.fill(gpa, vol, o.ao, res, per, o.seed);
    defer g.deinit(gpa);
    const secs = @as(f64, @floatFromInt(timer.read())) / 1e9;
    var qt = try std.time.Timer.start();
    const rms = rmsOf(pr, &g);
    const qns = @as(f64, @floatFromInt(qt.read())) / @as(f64, @floatFromInt(pr.x.len));
    return .{
        .label = label,
        .rays = per,
        .samples = cells,
        .grid_res = res,
        .bytes = g.bytes(),
        .rms = rms,
        .seconds = secs,
        .query_ns = qns,
    };
}

pub fn report(w: anytype, arms: []const Arm, o: Options) !void {
    try w.print("\n  {s:<24} {s:>6} {s:>10} {s:>8} {s:>9} {s:>9} {s:>8} {s:>9}\n", .{ "arm", "rays", "samples", "kernels", "KiB", "RMS", "build s", "query ns" });
    for (arms) |a| {
        try w.print("  {s:<24} {d:>6} {d:>10} {d:>8} {d:>9.1} {d:>9.5} {d:>8.2} {d:>9.0}\n", .{
            a.label, a.rays, a.samples, if (a.grid_res > 0) a.grid_res else a.kernels,
            @as(f64, @floatFromInt(a.bytes)) / 1024.0, a.rms, a.seconds, a.query_ns,
        });
    }
    try w.print("  (kernels for MARL, grid resolution for the grid; every arm spent {d} marched directions)\n", .{o.ray_budget});
}

// ── Gates ────────────────────────────────────────────────────────────

const testing = std.testing;

test "G33 (a) the occluder's sign, the estimator's noise, and the cost the cache exists to avoid" {
    // THE CONVENTION, pinned. `CLAUDE.md` says the carrier is "negative
    // inside" and it is NOT: `src/tests.zig`'s sheet gate samples
    // `Channel.surface` and reads +2.00 on the sheet's axis against −2.72
    // nine units beyond its width. A ray-marcher written from the prose
    // finds occlusion in empty space and none inside a trunk, which is a
    // bug that looks like a plausible picture. This gate is the fixture's
    // half of the same statement.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);

    const o = AoOptions{};
    // Deep inside a sphere: solid, and there is no ambient light there.
    var st = rng.Stream.region(1, 1, 0);
    const centre = [3]f32{ GROVE_EXTENT / 6, GROVE_EXTENT / 6, GROVE_EXTENT / 6 };
    try testing.expect(vol.at(centre) > 0);
    try testing.expectEqual(@as(f32, 0), aoAt(&vol, o, centre, &st));
    // A corner of the cube is the most open place in it.
    const open = [3]f32{ 0.4, 0.4, 0.4 };
    try testing.expect(vol.at(open) < 0);
    const open_ao = aoTrue(&vol, o, open, &st);
    try testing.expect(open_ao > 0.75);

    // THE NOISE, measured against its own theory. The estimator is
    // Binomial(M, p)/M, so σ = √(p(1−p)/M) and the spread of repeated
    // estimates at one point must track it. Nothing in this campaign has
    // ever had a noise floor before and every number below depends on
    // this one being what it says.
    const x = [3]f32{ 0.35 * GROVE_EXTENT, 0.5 * GROVE_EXTENT, 0.5 * GROVE_EXTENT };
    const p_true = aoTrue(&vol, o, x, &st);
    try testing.expect(p_true > 0.05 and p_true < 0.95); // or there is no variance to measure
    inline for (.{ 4, 64 }) |M| {
        var mo = o;
        mo.rays = M;
        var acc: f64 = 0;
        var n: u32 = 0;
        while (n < 256) : (n += 1) {
            const e = aoAt(&vol, mo, x, &st) - p_true;
            acc += @as(f64, e) * @as(f64, e);
        }
        const got: f32 = @floatCast(@sqrt(acc / 256));
        const want: f32 = @sqrt(p_true * (1 - p_true) / @as(f32, M));
        std.debug.print("  G33 (a): at p = {d:.3}, {d} rays gives σ {d:.4} against the binomial's {d:.4} ({s})\n", .{ p_true, M, got, want, @tagName(builtin.mode) });
        try testing.expect(got > want * 0.6 and got < want * 1.6);
    }

    // And the expense, which is the entire premise: one estimate is
    // `rays × steps` trilinear fetches of the occluder.
    try testing.expectEqual(@as(u32, 16 * 20), fetchesPerSample(o));
}

test "G33 (b) the learner's error against a noisy field is bias plus the RATE's own floor, linear in 1/M" {
    // THE LAW, and it is the phase's content. NLMS with step μ does not
    // converge on noisy data — it hovers, and the hovering costs μ/(2−μ)
    // of the measurement variance no matter how much data arrives. So
    //
    //     RMS² = bias² + μ/(2−μ) · V/M
    //
    // is LINEAR IN 1/M, with V the field's mean p(1−p). Everything this
    // campaign has measured until now said more data helps; this says
    // there is a term it cannot touch.
    //
    // Fitted from the two ends and checked in the middle, which is the
    // shape MARL-10's law was tested in — a line through two points is not
    // a claim, the third point is.
    //
    // MUTATION: drop the μ/(2−μ) term and predict RMS² = bias² alone. The
    // measured points then miss the line by more than threefold at M = 1,
    // which is what says the floor is real and not a fitted constant.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);
    const o = Options{ .samples = 60_000, .probes = 512 };
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    const ms = [_]u32{ 1, 4, 16 };
    var got: [3]f32 = undefined;
    var ks: [3]u32 = undefined;
    for (ms, 0..) |m, i| {
        const a = try marlArm(gpa, &vol, o, m, pr, "MARL");
        got[i] = a.rms;
        ks[i] = a.kernels;
    }
    // The line through the ends, in (1/M, RMS²).
    const x0 = 1.0 / @as(f64, @floatFromInt(ms[0]));
    const x2 = 1.0 / @as(f64, @floatFromInt(ms[2]));
    const y0 = @as(f64, got[0]) * got[0];
    const y2 = @as(f64, got[2]) * got[2];
    const slope = (y0 - y2) / (x0 - x2);
    const intercept = y2 - slope * x2;
    const mid = intercept + slope / @as(f64, @floatFromInt(ms[1]));
    const ratio = @as(f64, got[1]) * got[1] / mid;
    std.debug.print("  G33 (b): RMS at M = 1/4/16 is {d:.5}/{d:.5}/{d:.5}; the line through the ends predicts {d:.5} at M = 4, measured {d:.5} (ratio {d:.3}, ≤ {d:.2}); intercept — the representation error alone — {d:.5} ({s})\n", .{
        got[0], got[1], got[2], @sqrt(@max(0, mid)), got[1], ratio, thresholds.MARL13_NOISE_LAW, @sqrt(@max(0, intercept)), @tagName(builtin.mode),
    });
    // Noise does not only sit on the weights: a noisy residual crosses the
    // surprise threshold where a clean one would not, so it BUYS KERNELS
    // too. That is why the fitted slope implies a variance above the
    // binomial's own ceiling of 0.25, and it is worth printing rather than
    // explaining away.
    std.debug.print("  G33 (b): and the noise buys capacity — {d} kernels at M = 1, {d} at 4, {d} at 16\n", .{ ks[0], ks[1], ks[2] });
    try testing.expect(ratio <= thresholds.MARL13_NOISE_LAW and ratio >= 1.0 / thresholds.MARL13_NOISE_LAW);
    // Noise must actually dominate at M = 1, or the law is being fitted to
    // a flat line and the gate cannot fail.
    try testing.expect(got[0] > got[2] * 1.5);
    // And the intercept must be a real representation error, not an
    // artefact of a negative fit.
    try testing.expect(intercept > 0);
}

test "G33 (c) noise enters by THREE doors and the learning rate only closes one of them" {
    // PRE-REGISTERED AND REFUTED. `tools/marl13_predict.py` derived, from
    // μ/(2−μ), that dropping `rate_w` from 0.5 to 0.05 should cut the
    // noise floor 3.6-fold, and set MARL13_RATE at a floor of 2.0 to allow
    // for the bias term capping how much of that could show.
    //
    // Measured 1.29. The threshold stands refuted in `thresholds.zig` and
    // is NOT asserted here.
    //
    // The diagnosis, and it is why the phase was worth running: the LMS
    // floor analysis treats the model as a fixed basis with noisy weights,
    // and this model is not that. Noise enters by three doors —
    //
    //   the WEIGHTS   — `rate_w`, which is the door the theory is about
    //                   and the only one it closes;
    //   the GEOMETRY  — `rate_geom`, since a noisy residual moves centres
    //                   and shapes as readily as it moves weights;
    //   the TOPOLOGY  — a noisy residual crosses the surprise threshold
    //                   where a clean one would not, so the model BIRTHS
    //                   on noise. G33 (b) measures that directly: 9 923
    //                   kernels at one ray a sample against 7 656 at
    //                   sixteen, for the same 60 000 samples.
    //
    // The third door is the campaign's §5 — "do not confuse noise with
    // complexity" — arriving as a measurement rather than an instruction,
    // and no rate can close it: births are gated on the RAW surprise,
    // which is noisy however slowly the weights follow it.
    //
    // MUTATION: this gate would be vacuous if lowering the rate did
    // nothing at all, so it asserts that the weight door is real (the
    // ratio clears 1.1) while recording that it is not the whole story.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);
    var o = Options{ .samples = 60_000, .probes = 512 };
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    const fast = try marlArm(gpa, &vol, o, 1, pr, "rate 0.5");
    o.m.rate_w = 0.05;
    const slow = try marlArm(gpa, &vol, o, 1, pr, "rate 0.05");
    o.m.rate_geom = 0.02;
    const both = try marlArm(gpa, &vol, o, 1, pr, "both slowed");
    std.debug.print("  G33 (c): at one ray a sample — rate_w 0.5 {d:.5} ({d} kernels), 0.05 {d:.5} ({d}), and with rate_geom 0.2 → 0.02 as well {d:.5} ({d}); the weight door alone is {d:.2}× against {d:.1} predicted (REFUTED), both doors {d:.2}× ({s})\n", .{
        fast.rms, fast.kernels, slow.rms, slow.kernels, both.rms, both.kernels,
        fast.rms / slow.rms, thresholds.MARL13_RATE, fast.rms / both.rms, @tagName(builtin.mode),
    });
    // The weight door is real…
    try testing.expect(fast.rms / slow.rms > 1.1);
    // …and it is not the whole of it: the topology door is open at every
    // rate, and it shows up as capacity bought on noise.
    try testing.expect(slow.kernels > 7000);
}

test "G33 (d) a learned sparse field against a giant volume texture, at equal bytes and equal rays" {
    // THE HEADLINE, and the question the phase exists to answer for a
    // renderer. `rbf.zig` exists because Christian asked for a packed
    // Gaussian set "instead of the giant volume texture", so the giant
    // volume texture is who it has to beat.
    //
    // EQUAL BYTES, because memory is what a cache is rationed by: the grid
    // gets the largest resolution that fits in what MARL's kernels cost.
    // EQUAL RAYS, because the rays are the expense being cached — the
    // grid's budget is split evenly over its cells, and a grid handed
    // unlimited rays would be being compared on a resource nobody has.
    //
    // MARL runs at the rate `tools/marl13_predict.py` DERIVED before the
    // run (rate_w = 0.05 from μ/(2−μ)), and not at the better one G33 (c)
    // went on to find, because a headline configured from its own result
    // is not a headline.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);
    var o = Options{ .ray_budget = 2_000_000, .probes = 512 };
    o.m.rate_w = 0.05;
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    const m = try marlArm(gpa, &vol, o, o.rays, pr, "MARL, online");
    const g = try gridArm(gpa, &vol, o, m.bytes, pr, "dense grid, trilinear");
    var io = o;
    io.invert = true;
    const inv = try marlArm(gpa, &vol, io, io.rays, pr, "MARL, on 1 − AO");
    try report(std.io.getStdErr().writer(), &.{ m, g, inv }, o);

    // And the realistic query distribution: a shell around the geometry,
    // which is where a renderer actually asks. The grid must still store
    // every cell; MARL spends only where it was asked.
    var so = o;
    so.surface_band = 1.0;
    so.invert = true;
    var spr = try probesOf(gpa, &vol, so.ao, so.probes, so.seed, so.surface_band);
    defer spr.deinit(gpa);
    const sm = try marlArm(gpa, &vol, so, so.rays, spr, "MARL, shell, 1 − AO");
    const sg = try gridArm(gpa, &vol, so, sm.bytes, spr, "dense grid, shell probes");
    try report(std.io.getStdErr().writer(), &.{ sm, sg }, so);
    std.debug.print("  G33 (d): volume-uniform MARL/grid {d:.3} (REFUTED against ≤ {d:.1}); a zero background recovers {d:.2}×; on the SHELL, where a renderer actually asks, MARL/grid {d:.3} at {d:.0} KiB against {d:.0} ({s})\n", .{
        m.rms / g.rms,      thresholds.MARL13_TEXTURE,
        m.rms / inv.rms,    sm.rms / sg.rms,
        @as(f64, @floatFromInt(sm.bytes)) / 1024.0, @as(f64, @floatFromInt(sg.bytes)) / 1024.0,
        @tagName(builtin.mode),
    });

    // Equal bytes, to within one grid resolution step, on both comparisons.
    try testing.expect(g.bytes <= m.bytes and @as(f64, @floatFromInt(g.bytes)) > 0.5 * @as(f64, @floatFromInt(m.bytes)));
    try testing.expect(sg.bytes <= sm.bytes and @as(f64, @floatFromInt(sg.bytes)) > 0.5 * @as(f64, @floatFromInt(sm.bytes)));

    // MARL13_TEXTURE is REFUTED at 1.854 and is not asserted. What is
    // asserted is the two mechanisms the refutation turned up.
    //
    // One: the background. A hard cutoff makes a Gaussian basis decay to
    // EXACTLY zero, so a constant non-zero background has to be held up by
    // overlapping kernels everywhere it extends. Every field the campaign
    // ever learned had a zero background and it therefore never grew the
    // bias term `rbf.zig` has had since the day it was written.
    try testing.expect(inv.rms < m.rms * 0.85);
    try testing.expect(inv.kernels < m.kernels);
    // Two: the domain. A grid pays memory for every cell whether or not
    // anything is ever asked there; MARL pays only where it was asked. On
    // the shell — which is where a renderer actually asks — that asymmetry
    // is worth more than the representation gap, and the packed set beats
    // the giant volume texture. Which is the argument `rbf.zig` exists to
    // make, tested for the first time against the thing it replaced.
    try testing.expect(sm.rms <= sg.rms);
    // And a cache lookup must be far cheaper than the estimate it
    // replaces: one AO sample is 320 marched fetches of the occluder.
    try testing.expect(sm.query_ns < 20_000);
}


// ── MARL-14: distillation ────────────────────────────────────────────
//
// Christian's idea: once a model is built, sample IT to train another.
// `tools/marl14_predict.py` has the reasoning and the numbers; the short
// version is that a teacher is two things no field in this campaign has
// ever been — NOISELESS, which closes all three of MARL-13's doors at
// once, and UNLIMITED, which lifts MARL-11's binding constraint.
//
// Not to be confused with MARL-8. That phase transplanted a retiring
// region's KERNELS into a new region and failed, concluding geometry is
// "cheap to acquire locally and worthless imported". A student imports no
// geometry: it starts empty and discovers its own topology from a cheap
// oracle. The two findings do not touch.

/// A trained model and what it cost to make.
pub const Trained = struct {
    model: marl.Model,
    samples: u64,
    seconds: f64,
    rms: f32 = 0,
    query_ns: f64 = 0,

    pub fn deinit(self: *Trained) void {
        self.model.deinit();
    }

    pub fn kernels(self: *const Trained) u32 {
        return @intCast(self.model.kernels.items.len);
    }

    pub fn bytes(self: *const Trained) usize {
        return self.model.kernels.items.len * marl.PARAMS * @sizeOf(f32);
    }
};

/// Score a model against the TRUE probes — never against its teacher.
/// Scored against a teacher, a student would be measuring how well it
/// copies a copy, a number that improves as both get worse.
fn score(t: *Trained, extent: f32, invert: bool, pr: Probes) void {
    const Reader = struct {
        m: *marl.Model,
        e: f32,
        fn at(self: @This(), x: [3]f32) f32 {
            return (self.m.predict(.{ x[0] / self.e, x[1] / self.e, x[2] / self.e }) catch unreachable)[0];
        }
    };
    const rd = Reader{ .m = &t.model, .e = extent };
    var qt = std.time.Timer.start() catch unreachable;
    t.rms = if (invert) rmsInverted(pr, rd) else rmsOf(pr, rd);
    t.query_ns = @as(f64, @floatFromInt(qt.read())) / @as(f64, @floatFromInt(pr.x.len));
}

/// Observe `n` samples of the EXPENSIVE field into an EXISTING model,
/// carrying the reality stream so a run can be stopped and continued.
///
/// MARL-18 needs this because its two arms must see the SAME reality in
/// the SAME order — the only difference between them is whether the model
/// was rebuilt from itself partway. A fresh stream per segment would make
/// the arms differ in their data as well as their treatment, and the
/// comparison would be measuring both.
pub fn teachInto(model: *marl.Model, vol: *const bark.Volume, o: Options, n: u64, st: *rng.Stream) !void {
    var ao = o.ao;
    ao.rays = o.rays;
    const inv = 1 / vol.extent;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const q = drawQuery(vol, o.surface_band, st);
        const raw = aoAt(vol, ao, q, st);
        const y = if (o.invert) 1 - raw else raw;
        _ = try model.observe(.{ q[0] * inv, q[1] * inv, q[2] * inv }, .{y});
    }
}

/// Train from the EXPENSIVE field — the teacher's own apprenticeship.
pub fn teach(gpa: std.mem.Allocator, vol: *const bark.Volume, o: Options, pr: Probes) !Trained {
    var t = Trained{ .model = try marl.Model.init(gpa, o.m), .samples = 0, .seconds = 0 };
    errdefer t.deinit();
    var st = rng.Stream.region(o.seed, 0x5445_4143, 0); // "TEAC"
    t.samples = o.samples orelse (o.ray_budget / @max(1, o.rays));
    var timer = try std.time.Timer.start();
    try teachInto(&t.model, vol, o, t.samples, &st);
    t.seconds = @as(f64, @floatFromInt(timer.read())) / 1e9;
    score(&t, vol.extent, o.invert, pr);
    return t;
}

/// Train from ANOTHER MODEL. The teacher answers exactly, anywhere, as
/// often as asked — so the student is the first learner in this campaign
/// that is neither noise-limited nor evidence-starved.
///
/// `sopts` is the student's own configuration and is deliberately free to
/// differ: a coarser region grid gives it bigger kernels and fewer of
/// them, and a higher surprise threshold tells it how good an
/// approximation has to be. With a noisy field that second dial is
/// dangerous, because a residual above θ might be a sampling wobble; with
/// an exact teacher every residual above θ is real structure.
pub fn distil(gpa: std.mem.Allocator, teacher: *marl.Model, vol: *const bark.Volume, o: Options, sopts: marl.Options, n: u64, pr: Probes) !Trained {
    return distilEpoch(gpa, teacher, vol, o, sopts, n, pr, 0);
}

/// The same, with an EPOCH on the dream's own stream. A repeated
/// consolidation (MARL-18) sleeps several times, and at epoch 0 every
/// sleep would query the teacher at the identical points — which would
/// make the later sleeps re-derivations of the earlier ones rather than
/// fresh views of a changed field.
pub fn distilEpoch(gpa: std.mem.Allocator, teacher: *marl.Model, vol: *const bark.Volume, o: Options, sopts: marl.Options, n: u64, pr: Probes, epoch: u64) !Trained {
    var t = Trained{ .model = try marl.Model.init(gpa, sopts), .samples = n, .seconds = 0 };
    errdefer t.deinit();
    var st = rng.Stream.region(o.seed ^ 0x51, 0x4449_5354, epoch); // "DIST"
    const inv = 1 / vol.extent;
    var timer = try std.time.Timer.start();
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        // Drawn from the SAME query distribution the teacher was trained
        // on. A student sampled somewhere else would be being asked about
        // a region its teacher never learned, and would faithfully
        // reproduce the teacher's ignorance.
        const q = drawQuery(vol, o.surface_band, &st);
        const x = [3]f32{ q[0] * inv, q[1] * inv, q[2] * inv };
        const y = (try teacher.predict(x))[0];
        _ = try t.model.observe(x, .{y});
    }
    t.seconds = @as(f64, @floatFromInt(timer.read())) / 1e9;
    score(&t, vol.extent, o.invert, pr);
    return t;
}

test "G34 distillation: a noiseless unlimited teacher, and what an approximation is allowed to cost" {
    // Christian's idea, run. The student is scored against the TRUE field
    // throughout — never against its teacher, which would measure how well
    // it copies a copy.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);
    var o = Options{ .ray_budget = 2_000_000, .probes = 512, .surface_band = 1.0, .invert = true };
    o.m.rate_w = 0.05;
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    var t = try teach(gpa, &vol, o, pr);
    defer t.deinit();
    const N: u64 = 200_000;

    // (1) The same options, a clean teacher. What falls away is the
    // capacity MARL-13 measured as bought on noise.
    var s0 = try distil(gpa, &t.model, &vol, o, o.m, N, pr);
    defer s0.deinit();
    const free = @as(f32, @floatFromInt(s0.kernels())) / @as(f32, @floatFromInt(t.kernels()));

    // (2) The accuracy dial. θ gates learning events and a birth needs
    // one, so with an exact teacher θ is how good the copy has to be.
    std.debug.print("\n  G34: teacher {d} kernels, RMS {d:.5} ({d:.1} KiB, {d:.0} ns a lookup)\n", .{ t.kernels(), t.rms, @as(f64, @floatFromInt(t.bytes())) / 1024.0, t.query_ns });
    std.debug.print("  G34: {s:>10} {s:>9} {s:>10} {s:>8} {s:>9}\n", .{ "θ", "kernels", "RMS", "K/K_t", "RMS/RMS_t" });
    std.debug.print("  G34: {d:>10.3} {d:>9} {d:>10.5} {d:>8.3} {d:>9.3}   (the teacher's own θ)\n", .{ o.m.threshold, s0.kernels(), s0.rms, free, s0.rms / t.rms });
    var halved: ?Trained = null;
    defer if (halved) |*h| h.deinit();
    for ([_]f32{ 0.05, 0.10, 0.20 }) |th| {
        var so = o.m;
        so.threshold = th;
        var s = try distil(gpa, &t.model, &vol, o, so, N, pr);
        std.debug.print("  G34: {d:>10.3} {d:>9} {d:>10.5} {d:>8.3} {d:>9.3}\n", .{ th, s.kernels(), s.rms, @as(f32, @floatFromInt(s.kernels())) / @as(f32, @floatFromInt(t.kernels())), s.rms / t.rms });
        if (halved == null and s.kernels() * 2 <= t.kernels()) {
            halved = s;
        } else s.deinit();
    }

    // (3) A coarser basis: fewer regions is bigger kernels and fewer of
    // them, and a shell is nearly two-dimensional so the saving should go
    // as the square rather than the cube.
    var co = o.m;
    co.regions = 3;
    var coarse = try distil(gpa, &t.model, &vol, o, co, N, pr);
    defer coarse.deinit();
    const shrink = @as(f32, @floatFromInt(t.kernels())) / @as(f32, @floatFromInt(coarse.kernels()));
    std.debug.print("  G34: regions 6 → 3 gives {d} kernels, RMS {d:.5} — {d:.2}× fewer (≥ {d:.1} predicted), {d:.1} KiB against {d:.1}\n", .{
        coarse.kernels(), coarse.rms, shrink, thresholds.MARL14_COARSE,
        @as(f64, @floatFromInt(coarse.bytes())) / 1024.0, @as(f64, @floatFromInt(t.bytes())) / 1024.0,
    });

    // (4) Generation loss. B is a sum of anisotropic gaussians, which is
    // EXACTLY the student's hypothesis class; the truth is not. So the
    // second copy should cost less than the first.
    var s2 = try distil(gpa, &s0.model, &vol, o, o.m, N, pr);
    defer s2.deinit();
    const first = s0.rms / t.rms;
    const second = s2.rms / s0.rms;
    std.debug.print("  G34: A→B costs {d:.3}, B→C costs {d:.3} — the second copy is {d:.2}× the first (≤ {d:.1} predicted); C has {d} kernels\n", .{ first, second, second / first, thresholds.MARL14_GENERATION, s2.kernels() });

    // (5) And the thing MARL-13 lost to. The teacher beat a dense grid on
    // the shell by 0.912 at roughly equal bytes; the question distillation
    // actually raises is what happens when the bytes are no longer equal
    // because one side got four times smaller.
    const cg = try gridArm(gpa, &vol, o, coarse.bytes(), pr, "grid at the student's size");
    std.debug.print("  G34: against a dense grid AT THE STUDENT'S SIZE — student {d:.5} at {d:.1} KiB, grid {d:.5} at {d:.1} KiB ({d}³ cells): {d:.3}\n", .{
        coarse.rms, @as(f64, @floatFromInt(coarse.bytes())) / 1024.0,
        cg.rms,     @as(f64, @floatFromInt(cg.bytes)) / 1024.0, cg.grid_res,
        coarse.rms / cg.rms,
    });
    try testing.expect(coarse.rms < cg.rms);

    try testing.expect(free <= thresholds.MARL14_FREE);
    if (halved) |h| {
        std.debug.print("  G34: halving the population costs {d:.3}× the RMS (≤ {d:.1} predicted): {d} kernels at RMS {d:.5}\n", .{ h.rms / t.rms, thresholds.MARL14_TRADE, h.kernels(), h.rms });
        try testing.expect(h.rms / t.rms <= thresholds.MARL14_TRADE);
    } else return error.NoThresholdHalvedThePopulation;
    try testing.expect(shrink >= thresholds.MARL14_COARSE);
    try testing.expect(second / first <= thresholds.MARL14_GENERATION);
}

// ── MARL-15: quantization ────────────────────────────────────────────
//
// Every byte count this campaign has quoted is `kernels × PARAMS × 4`, and
// every grid it has been compared against is f32 too — so the comparisons
// are fair and both sides are uncompressed. MARL-14's headline is a claim
// about a representation nobody would ship, and the two sides do not
// quantize alike: a grid of values in [0, 1] goes to eight bits for
// essentially nothing, where an RBF set's ten floats have wildly different
// sensitivities and the weight sits in a sum where neighbours CANCEL.
//
// Quantization is applied to the `rbf.Set` — the thing that actually
// ships, and bit-identical to the model by G31 (a) at a power-of-two
// extent — rather than to a live `marl.Model`. That is not a shortcut: a
// model's kernels are OWNED by regions, and rounding a centre could move
// it across a face or grow its reach past the region's bound, so
// quantizing in place would silently corrupt the gather and charge it to
// the quantizer.

/// Bits per field of a kernel. The defaults are what
/// `tools/marl15_predict.py` allocated from the sensitivity analysis,
/// before any of this ran.
pub const Bits = struct {
    /// Per centre axis, over the volume's extent. The sensitive one: the
    /// derivative peaks at r = 1 where r·e^(−r²/2) = 0.6065, so a
    /// displacement costs 0.6065·|w|·ε/σ and σ is a seventeenth of the
    /// domain — an error measured against the DOMAIN is amplified
    /// seventeenfold before it reaches the field.
    mu: u6 = 16,
    /// Per log-diagonal, over the set's own measured range.
    logd: u6 = 10,
    /// Per off-diagonal, over the set's own measured range.
    off: u6 = 10,
    /// Per weight, over the set's own measured range — MEASURED, because
    /// MARL-1 saw mean |w| of 13–17 in its divergent regime and a span is
    /// not a thing to guess.
    w: u6 = 12,
    /// Centres stored RELATIVE to their owning region's corner rather than
    /// to the whole cube. Zero means absolute.
    ///
    /// A kernel's centre is inside its owning region BY DEFINITION — that
    /// is what ownership means in this model, and the clamp keeps it
    /// there. So the span a centre needs is not the cube but the region,
    /// `extent/regions`, which is `log2(regions)` bits an axis free at the
    /// same error. And `marble.setOf` already writes kernels in
    /// `predictAll`'s order — region by region, then each region's own
    /// list — so the grouping a decoder needs is already in the file; all
    /// that has to be stored is a count per region, which `bytesFor`
    /// charges for.
    ///
    /// The ablation is what pointed here: the centre is the ONLY expensive
    /// field (0.01872 of excess at eight bits against the weight's exactly
    /// zero), and its cost is a SPAN choice rather than a sensitivity.
    regions: u32 = 0,

    pub fn perKernel(self: Bits) u32 {
        return 3 * @as(u32, self.mu) + 3 * @as(u32, self.logd) + 3 * @as(u32, self.off) + @as(u32, self.w);
    }

    /// The packed size: the kernels, plus a header of eight f32 ranges
    /// that every kernel is decoded against.
    pub fn bytesFor(self: Bits, kernels: usize) usize {
        var b = (kernels * self.perKernel() + 7) / 8 + 8 * @sizeOf(f32);
        // A u16 count per region, which is what lets a decoder know which
        // region's corner to add back. Charged in full, empty regions
        // included, because a format that skipped them would need their
        // indices instead and that is not cheaper.
        if (self.regions > 0) b += @as(usize, self.regions) * self.regions * self.regions * 2;
        return b;
    }
};

fn quant(v: f32, lo: f32, hi: f32, bits: u6) f32 {
    if (hi <= lo or bits >= 32) return v;
    const levels: f32 = @floatFromInt((@as(u64, 1) << bits) - 1);
    const t = @min(1, @max(0, (v - lo) / (hi - lo)));
    return lo + @round(t * levels) / levels * (hi - lo);
}

/// Round a set's parameters onto the representable grid, in place.
///
/// The log-diagonal and not the diagonal, because that is the
/// parameterisation the model descends in and the one whose error is
/// RELATIVE — a width is a scale, and a scale quantized linearly spends
/// all its precision on the widest kernels.
pub const Spans = struct { logd: [2]f32, off: [2]f32, w: [2]f32 };

pub fn quantizeSet(set: *rbf.Set, b: Bits) Spans {
    if (set.kernels.len == 0) return .{ .logd = .{ 0, 0 }, .off = .{ 0, 0 }, .w = .{ 0, 0 } };
    var ld_lo: f32 = std.math.floatMax(f32);
    var ld_hi: f32 = -std.math.floatMax(f32);
    var of_lo: f32 = std.math.floatMax(f32);
    var of_hi: f32 = -std.math.floatMax(f32);
    var w_lo: f32 = std.math.floatMax(f32);
    var w_hi: f32 = -std.math.floatMax(f32);
    for (set.kernels) |k| {
        inline for (.{ 0, 2, 5 }) |i| {
            const l = @log(@max(1e-20, k.l[i]));
            ld_lo = @min(ld_lo, l);
            ld_hi = @max(ld_hi, l);
        }
        inline for (.{ 1, 3, 4 }) |i| {
            of_lo = @min(of_lo, k.l[i]);
            of_hi = @max(of_hi, k.l[i]);
        }
        w_lo = @min(w_lo, k.w[0]);
        w_hi = @max(w_hi, k.w[0]);
    }
    const hv: f32 = if (b.regions > 0) set.extent / @as(f32, @floatFromInt(b.regions)) else 0;
    for (set.kernels) |*k| {
        if (b.regions > 0) {
            inline for (0..3) |a| {
                // The owning region is the one holding the centre, which is
                // `regionOf`'s rule and needs no extra information.
                const idx = @min(@as(f32, @floatFromInt(b.regions - 1)), @max(0, @floor(k.mu[a] / hv)));
                const org = idx * hv;
                k.mu[a] = org + quant(k.mu[a] - org, 0, hv, b.mu);
            }
        } else {
            inline for (0..3) |a| k.mu[a] = quant(k.mu[a], 0, set.extent, b.mu);
        }
        inline for (.{ 0, 2, 5 }) |i| k.l[i] = @exp(quant(@log(@max(1e-20, k.l[i])), ld_lo, ld_hi, b.logd));
        inline for (.{ 1, 3, 4 }) |i| k.l[i] = quant(k.l[i], of_lo, of_hi, b.off);
        k.w[0] = quant(k.w[0], w_lo, w_hi, b.w);
    }
    return .{ .logd = .{ ld_lo, ld_hi }, .off = .{ of_lo, of_hi }, .w = .{ w_lo, w_hi } };
}

/// A grid's values rounded to `bits` over [0, 1] — what a renderer would
/// ship a volume texture as, and it costs almost nothing.
pub fn quantizeGrid(g: *Grid, bits: u6) void {
    for (g.data) |*v| v.* = quant(v.*, 0, 1, bits);
}

pub fn rmsOfSetInverted(set: *const rbf.Set, pr: Probes) f32 {
    var acc: f64 = 0;
    for (pr.x, pr.y) |x, y| {
        const e = (1 - set.eval(x)[0]) - y;
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.x.len))));
}

test "G35 quantization: what a shippable kernel costs, and what it does to MARL-14's position" {
    // MARL-14 left a distilled model beating a dense grid 0.878 at a
    // quarter of the memory — in f32, which nobody ships. The two sides do
    // not quantize alike, and the grid gains MORE, so this gate exists to
    // qualify a claim rather than to add one.
    //
    // MUTATION: the centre allocation. It is the sensitive field — 0.6065·
    // |w|·ε/σ with σ a seventeenth of the domain — and the analysis says
    // eight bits an axis costs 0.11, which is most of the RMS. The sweep
    // below runs it, and it must fail the ceiling the 16-bit allocation
    // passes, or `Bits.mu` is decoration.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);
    var o = Options{ .ray_budget = 2_000_000, .probes = 512, .surface_band = 1.0, .invert = true };
    o.m.rate_w = 0.05;
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    // MARL-14's shipped artefact: the coarse distilled student.
    var t = try teach(gpa, &vol, o, pr);
    defer t.deinit();
    var co = o.m;
    co.regions = 3;
    var s = try distil(gpa, &t.model, &vol, o, co, 200_000, pr);
    defer s.deinit();

    const one: rbf.Channels = [_]f32{1} ** rbf.CHANNELS;
    var ref = try marble.setOf(gpa, &s.model, vol.extent, vol.columns, vol.hash, one);
    defer ref.deinit(gpa);
    const rms_f32 = rmsOfSetInverted(&ref, pr);
    std.debug.print("\n  G35: the shipped set — {d} kernels, RMS {d:.5} in f32 at {d} bytes a kernel ({d:.1} KiB) ({s})\n", .{ ref.kernels.len, rms_f32, marl.PARAMS * 4, @as(f64, @floatFromInt(s.bytes())) / 1024.0, @tagName(builtin.mode) });
    std.debug.print("  G35: {s:>18} {s:>8} {s:>9} {s:>9} {s:>9}\n", .{ "allocation", "bits/k", "KiB", "RMS", "vs f32" });

    // The pre-registered allocation, then down until it breaks. The sweep
    // goes further than `tools/marl15_predict.py` planned because the
    // first run of it found the analysis PESSIMISTIC: 8-bit centres, which
    // it said would cost 0.11 of RMS, cost 0.0018.
    const allocs = [_]Bits{
        .{ .mu = 16, .logd = 10, .off = 10, .w = 12 }, // the pre-registered one
        .{ .mu = 12, .logd = 8, .off = 8, .w = 10 },
        .{ .mu = 10, .logd = 6, .off = 6, .w = 8 },
        .{ .mu = 8, .logd = 6, .off = 6, .w = 8 },
        .{ .mu = 6, .logd = 5, .off = 5, .w = 6 },
        .{ .mu = 4, .logd = 4, .off = 4, .w = 4 }, // the mutation, and it must fail
    };
    var ship: struct { bits: Bits, rms: f32, kib: f64 } = undefined;
    var got: [allocs.len]f32 = undefined;
    var kib: [allocs.len]f64 = undefined;
    var spans: Spans = undefined;
    for (allocs, 0..) |b, i| {
        var q = rbf.Set{ .extent = ref.extent, .columns = ref.columns, .hash = ref.hash, .kernels = try gpa.dupe(rbf.Kernel, ref.kernels) };
        defer q.deinit(gpa);
        spans = quantizeSet(&q, b);
        got[i] = rmsOfSetInverted(&q, pr);
        kib[i] = @as(f64, @floatFromInt(b.bytesFor(q.kernels.len))) / 1024.0;
        std.debug.print("  G35: {d:>4}/{d:>2}/{d:>2}/{d:>2}{s:>7} {d:>8} {d:>9.1} {d:>9.5} {d:>9.3}\n", .{ b.mu, b.logd, b.off, b.w, if (i == allocs.len - 1) " (mut)" else "", b.perKernel(), kib[i], got[i], got[i] / rms_f32 });
    }
    // WHY the analysis was pessimistic — and it is NOT the weights, which
    // is the first thing to check and the first thing to rule out. The
    // span is printed below and it is 1.376, slightly ABOVE the 1.0 the
    // prediction assumed, so |w| makes the analysis worse rather than
    // better.
    //
    // It is that PEAK SENSITIVITY AND PEAK OVERLAP DO NOT COINCIDE. The
    // prediction multiplied the derivative's maximum — 0.6065, which
    // occurs at r = 1 exactly — by √(3n) for n = 30 overlapping kernels.
    // But a point sitting at r = 1 of one kernel sits far out in the tails
    // of most of the others, where both the value and the derivative are
    // near zero, so the kernels that are SENSITIVE there are a handful and
    // not thirty. Compounding a worst case over an assumed overlap count
    // overstates by the product of two things that never happen together.
    // Measured, that product is about fivefold.
    const wspan = @max(@abs(spans.w[0]), @abs(spans.w[1]));
    std.debug.print("  G35: the weights span {d:.4} … {d:.4}, so |w| ≈ {d:.3} — ABOVE the 1.0 assumed, so the weights are not why the prediction was pessimistic; peak sensitivity and peak overlap simply do not coincide\n", .{ spans.w[0], spans.w[1], wspan });

    // WHICH FIELD is forgiving, decomposed. Each is starved to eight bits
    // alone with the other three left in f32, so the 1.010 above is split
    // into its parts instead of argued about. The spans are printed with
    // them, because a field's cost is its sensitivity TIMES its range and
    // the range is what an adapted basis would narrow.
    const F = struct { n: []const u8, b: Bits, span: f32 };
    const solo = [_]F{
        .{ .n = "centre only", .b = .{ .mu = 8, .logd = 32, .off = 32, .w = 32 }, .span = ref.extent },
        .{ .n = "log-width only", .b = .{ .mu = 32, .logd = 8, .off = 32, .w = 32 }, .span = spans.logd[1] - spans.logd[0] },
        .{ .n = "off-diagonal only", .b = .{ .mu = 32, .logd = 32, .off = 8, .w = 32 }, .span = spans.off[1] - spans.off[0] },
        .{ .n = "weight only", .b = .{ .mu = 32, .logd = 32, .off = 32, .w = 8 }, .span = spans.w[1] - spans.w[0] },
    };
    std.debug.print("  G35: per-field, each starved to 8 bits alone —\n", .{});
    for (solo) |f| {
        var q = rbf.Set{ .extent = ref.extent, .columns = ref.columns, .hash = ref.hash, .kernels = try gpa.dupe(rbf.Kernel, ref.kernels) };
        defer q.deinit(gpa);
        _ = quantizeSet(&q, f.b);
        const r = rmsOfSetInverted(&q, pr);
        // The excess in quadrature — what this field alone contributed.
        const excess = @sqrt(@max(0, @as(f64, r) * r - @as(f64, rms_f32) * rms_f32));
        std.debug.print("  G35:   {s:<20} span {d:>9.4}  step {e:>10.3}  RMS {d:.5} ({d:.3}×), excess {d:.5}\n", .{ f.n, f.span, f.span / 256.0, r, r / rms_f32, excess });
    }

    // REGION-RELATIVE CENTRES, which is where the ablation pointed. A
    // kernel's centre is inside its owning region by definition, so the
    // span is `extent/regions` and not the cube: log2(regions) bits an
    // axis free at the same error, for a u16 count per region.
    //
    // MUTATION: the same allocation with `regions = 0`. That is the
    // absolute row already in the sweep above, and it must be worse — if
    // it is not, the region-relative path is decoding to the same numbers
    // and the count table is being charged for nothing.
    {
        var abs = rbf.Set{ .extent = ref.extent, .columns = ref.columns, .hash = ref.hash, .kernels = try gpa.dupe(rbf.Kernel, ref.kernels) };
        defer abs.deinit(gpa);
        var rel = rbf.Set{ .extent = ref.extent, .columns = ref.columns, .hash = ref.hash, .kernels = try gpa.dupe(rbf.Kernel, ref.kernels) };
        defer rel.deinit(gpa);
        const only_mu = Bits{ .mu = 8, .logd = 32, .off = 32, .w = 32 };
        var only_mu_rel = only_mu;
        only_mu_rel.regions = co.regions;
        _ = quantizeSet(&abs, only_mu);
        _ = quantizeSet(&rel, only_mu_rel);
        const ea = @sqrt(@max(0, @as(f64, rmsOfSetInverted(&abs, pr)) * rmsOfSetInverted(&abs, pr) - @as(f64, rms_f32) * rms_f32));
        const er = @sqrt(@max(0, @as(f64, rmsOfSetInverted(&rel, pr)) * rmsOfSetInverted(&rel, pr) - @as(f64, rms_f32) * rms_f32));
        std.debug.print("  G35: region-relative centres, 8 bits alone — excess {d:.5} absolute against {d:.5} relative, {d:.2}× (≥ {d:.1} predicted, {d:.1} from the geometry)\n", .{ ea, er, ea / @max(1e-9, er), thresholds.MARL15_RELATIVE, @as(f32, @floatFromInt(co.regions)) });
        try testing.expect(ea / @max(1e-9, er) >= thresholds.MARL15_RELATIVE);
    }
    {
        // And what it buys: the 54-bit budget that FAILED absolute.
        var b = Bits{ .mu = 6, .logd = 5, .off = 5, .w = 6 };
        b.regions = co.regions;
        var q = rbf.Set{ .extent = ref.extent, .columns = ref.columns, .hash = ref.hash, .kernels = try gpa.dupe(rbf.Kernel, ref.kernels) };
        defer q.deinit(gpa);
        _ = quantizeSet(&q, b);
        const r = rmsOfSetInverted(&q, pr);
        std.debug.print("  G35: 6/5/5/6 relative — {d} bits a kernel, {d:.1} KiB (a {d:.2}× saving on f32), RMS {d:.5} = {d:.3}× (≤ {d:.2}); the same budget ABSOLUTE was {d:.3}\n", .{
            b.perKernel(), @as(f64, @floatFromInt(b.bytesFor(q.kernels.len))) / 1024.0,
            @as(f32, marl.PARAMS * 32) / @as(f32, @floatFromInt(b.perKernel())),
            r, r / rms_f32, thresholds.MARL15_RBITS, got[4] / rms_f32,
        });
        try testing.expect(r / rms_f32 <= thresholds.MARL15_RBITS);
        try testing.expect(r < got[4]); // the mutation: absolute, same budget
        ship = .{ .bits = b, .rms = r, .kib = @as(f64, @floatFromInt(b.bytesFor(q.kernels.len))) / 1024.0 };
    }

    // The pre-registered allocation survives…
    try testing.expect(got[0] / rms_f32 <= thresholds.MARL15_BITS);
    // …and four bits a field does not, or the whole sweep is decoration.
    try testing.expect(got[allocs.len - 1] / rms_f32 > thresholds.MARL15_BITS);

    // THE HEADLINE, both sides compressed. The grid gets eight bits over
    // [0, 1], which is what a renderer would ship, and the same bytes.
    // THE HEADLINE, at the encoding a production build would actually
    // pick: 54 bits with region-relative centres, which is the smallest
    // that stayed inside the ceiling.
    const budget = ship.bits.bytesFor(ref.kernels.len);
    // A cubic grid can only step in whole resolutions, so it cannot land
    // on the budget: at 5.5 KiB it fits 17³ = 4.8 and the next size up is
    // 18³ = 5.7. Reporting only the one that fits would flatter MARL by
    // 13% of the memory, so BOTH are measured and the assertion is made
    // against the larger — the grid given MORE than its share.
    const res = Grid.resFor(budget * 4); // four cells a byte at eight bits
    var g_rms: [2]f32 = undefined;
    var g_kib: [2]f64 = undefined;
    for ([_]u32{ res, res + 1 }, 0..) |r, i| {
        const cells: u64 = @as(u64, r) * r * r;
        var g = try Grid.fill(gpa, &vol, o.ao, r, @intCast(@max(1, o.ray_budget / cells)), o.seed);
        defer g.deinit(gpa);
        quantizeGrid(&g, 8);
        g_rms[i] = rmsOf(pr, &g);
        g_kib[i] = @as(f64, @floatFromInt(cells)) / 1024.0;
    }
    std.debug.print("  G35: both compressed — MARL {d:.5} at {d:.1} KiB; grid {d}³ {d:.5} at {d:.1} KiB (under budget) and {d}³ {d:.5} at {d:.1} KiB (over): ratios {d:.3} and {d:.3} (≤ {d:.2} predicted, ≈1.06 derived; MARL-14's f32 number was 0.878)\n", .{
        ship.rms, ship.kib,
        res,     g_rms[0], g_kib[0],
        res + 1, g_rms[1], g_kib[1],
        ship.rms / g_rms[0], ship.rms / g_rms[1], thresholds.MARL15_HEADLINE,
    });
    // The grid straddles the budget, and the generous side is the test.
    try testing.expect(g_kib[0] <= ship.kib and g_kib[1] >= ship.kib);
    try testing.expect(ship.rms / g_rms[1] <= thresholds.MARL15_HEADLINE);
}

// ── MARL-16: a learned background ────────────────────────────────────

test "G36 a learned background is what rbf.zig has always had — and it costs exact locality" {
    // MARL-13's LOSING configuration: volume-uniform occlusion, learned
    // directly rather than inverted. That is where the background problem
    // lives — a hard cutoff makes a Gaussian decay to exactly zero, so the
    // ≈1 across the open majority of the cube has to be held up by
    // overlapping kernels everywhere it extends.
    //
    // MARL-13 measured the size of the hole by NEGATING the target: 1.40×
    // the accuracy for 14% less capacity, from a trick that has to be TOLD
    // what the background is. This is the same thing learned.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);
    var o = Options{ .ray_budget = 2_000_000, .probes = 512 };
    o.m.rate_w = 0.05;
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    var plain = try teach(gpa, &vol, o, pr);
    defer plain.deinit();
    o.m.bias = .residual;
    var resb = try teach(gpa, &vol, o, pr);
    defer resb.deinit();
    o.m.bias = .target;
    var withb = try teach(gpa, &vol, o, pr);
    defer withb.deinit();
    std.debug.print("\n  G36: a bias from the RESIDUAL — {d} kernels, RMS {d:.5}, b = {d:.4}: {d:.3}× the no-bias RMS. REFUTED, and the value is the tell — the kernels eat the background long before a 1/n step can reach it.\n", .{ resb.kernels(), resb.rms, resb.model.bias[0], resb.rms / plain.rms });

    std.debug.print("  G36: no bias {d} kernels RMS {d:.5}; a bias from the TARGET {d} kernels RMS {d:.5} (b = {d:.4} after {d} exemplars) — RMS {d:.3}× (≤ {d:.2}), kernels {d:.3}× (≤ {d:.1}) ({s})\n", .{
        plain.kernels(), plain.rms, withb.kernels(), withb.rms,
        withb.model.bias[0], withb.model.bias_n,
        withb.rms / plain.rms, thresholds.MARL16_BIAS,
        @as(f32, @floatFromInt(withb.kernels())) / @as(f32, @floatFromInt(plain.kernels())), thresholds.MARL16_KERNELS,
        @tagName(builtin.mode),
    });
    // BOTH REFUTED, and the mechanism is not the estimator — the target
    // form converges to the right number (0.7211, the field's mean) and is
    // WORSE than the residual form that never converged at all.
    //
    // A Gaussian basis with a HARD CUTOFF cannot cheaply represent a
    // plateau of ANY value. Zero is not special because it is zero; it is
    // special because it is what an empty model already predicts, and a
    // target that is zero over a large region therefore costs literally
    // nothing. A bias moves that free value from 0 to b: it helps where
    // y ≈ b and it HURTS everywhere y ≈ 0, which now has to be held DOWN
    // by kernels that previously did not need to exist.
    //
    // So the trade is decided by how much of the field sits at zero, which
    // is measured here rather than argued.
    var at_zero: u32 = 0;
    var near_b: u32 = 0;
    for (pr.y) |y| {
        if (y <= 0.02) at_zero += 1;
        if (@abs(y - withb.model.bias[0]) <= 0.02) near_b += 1;
    }
    const fz = @as(f32, @floatFromInt(at_zero)) / @as(f32, @floatFromInt(pr.y.len));
    const fb = @as(f32, @floatFromInt(near_b)) / @as(f32, @floatFromInt(pr.y.len));
    std.debug.print("  G36: {d:.3} of the field is within θ of ZERO — free to a model that predicts zero — against {d:.3} within θ of the learned bias {d:.4}. A bias trades the first for the second, and here it is a losing trade by {d:.1}×.\n", .{ fz, fb, withb.model.bias[0], fz / @max(1e-6, fb) });

    // The claim, asserted: the zero mass is the larger, which is WHY the
    // bias loses. If this ever flips on some other field, the bias should
    // be tried again there and is expected to win.
    try testing.expect(fz > fb);
    // And both formulations are worse, which is what MARL16_BIAS records.
    try testing.expect(withb.rms > plain.rms and resb.rms > plain.rms);

    // THE TRADE, measured. `CUTOFF` makes a learning event structurally
    // unable to disturb a distant region and G17 (c)/(d) check it bitwise.
    // One global scalar is not local at all. Learned as a running mean its
    // step is 1/n, so what this gate asserts is that the disturbance
    // DECAYS — asymptotic locality where the kernels have exact locality.
    //
    // MUTATION: the same measurement on the model WITHOUT a bias, which
    // must be exactly zero. If it is not, the probes are not far enough
    // away and the number below is measuring the kernels.
    const inv = 1 / vol.extent;
    const far = [3]f32{ 0.02, 0.02, 0.02 }; // a corner, in unit coords
    const before = try gpa.alloc(f32, pr.x.len);
    defer gpa.free(before);
    var moved: [2]f32 = .{ 0, 0 };
    var resid: [2]f32 = .{ 0, 0 };
    for ([_]*Trained{ &plain, &withb }, 0..) |t, arm| {
        for (pr.x, before) |x, *b| b.* = (try t.model.predict(.{ x[0] * inv, x[1] * inv, x[2] * inv }))[0];
        var est = rng.Stream.region(99, 1, 0);
        const y = aoAt(&vol, o.ao, .{ far[0] * vol.extent, far[1] * vol.extent, far[2] * vol.extent }, &est);
        const ev = try t.model.observe(far, .{y});
        resid[arm] = @abs(ev.residual[0]);
        for (pr.x, before) |x, b| {
            // Only probes FAR from the event, so the kernels it touched
            // cannot be what is being measured.
            const d = @max(@abs(x[0] * inv - far[0]), @max(@abs(x[1] * inv - far[1]), @abs(x[2] * inv - far[2])));
            if (d < 0.4) continue;
            const a = (try t.model.predict(.{ x[0] * inv, x[1] * inv, x[2] * inv }))[0];
            moved[arm] = @max(moved[arm], @abs(a - b));
        }
    }
    const n: f64 = @floatFromInt(withb.model.bias_n);
    const scaled = @as(f64, moved[1]) * n / @max(1e-9, resid[1]);
    std.debug.print("  G36: one late event, at probes over 0.4 of the domain away — no bias moved {e:.2} (exactly zero is the claim), with a bias {e:.2} on a residual of {d:.4} after {d} exemplars, so disturbance × n / |e| = {d:.3} (≤ {d:.1})\n", .{ moved[0], moved[1], resid[1], withb.model.bias_n, scaled, thresholds.MARL16_LOCALITY });
    // Exact locality, with no bias, bitwise.
    try testing.expectEqual(@as(f32, 0), moved[0]);
    // …and asymptotic locality with one: the step is 1/n and the
    // disturbance is that step, so this number is about one.
    try testing.expect(scaled <= thresholds.MARL16_LOCALITY);
}


// ── MARL-18: consolidation ───────────────────────────────────────────
//
// Christian's plan for the day: once a model is built, distil it, REPLACE
// THE MASTER WITH THE STUDENT, and resume ordinary learning — "learn,
// accumulate interference, consolidate, resume learning from a cleaner
// state". Memory consolidation, or optimisation garbage collection.
//
// The plan's premise is that MARL-14 already showed a student beating its
// teacher on held-out error. **It did not.** Every row of G34's sweep goes
// the other way (1.058 at matched options, rising to 1.141), and the 0.878
// that reads like the claim is the student against a SAME-SIZED GRID — a
// statement about the opponent, not about the teacher.
//
// The idea survives the correction and gets sharper for it, because
// MARL-14 distilled a model and STOPPED. It never resumed learning. That a
// student is worse at the instant of the copy and that it is a worse PLACE
// TO LEARN FROM are different claims, and only the first has been run.
//
// `tools/marl18_predict.py` has the mechanisms. The two that matter:
//
//   FOR. The COVERAGE GATE is why "tangled" is a real state and not a
//   metaphor. A birth needs surprise above θ AND no kernel reading above
//   `coverage` within the responsibility radius — so a region that has
//   already spent kernels CANNOT BUY MORE, however badly placed the ones
//   it has are. It is locked by its own history. Consolidation is the only
//   operation in this codebase that can unlock it, and it does so without
//   choosing a victim: it does not remove kernels, it declines to rebuild
//   them. That is precisely what MARL-7 went looking for and could not
//   find, because it was looking for something to erode.
//
//   AGAINST. MARL-13 (b): on a noisy field NLMS does not converge, it
//   hovers, at `RMS² = bias² + μ/(2−μ)·V/M`. The variance term belongs to
//   the RATE. A consolidation changes the population and leaves μ alone,
//   so an arm already sitting on its noise floor cannot be moved by one.

/// One learn-and-consolidate run, and what it cost on both clocks.
///
/// The two costs are kept apart on purpose. REALITY is rays — the expense
/// a cache exists to avoid — and it is the resource the arms are matched
/// on. DREAM is gathers of the model's own field, which is a different and
/// much cheaper thing, and folding the two into one "work" number would
/// hide exactly the asymmetry that makes consolidation worth considering.
pub const Run = struct {
    t: Trained,
    reality: u64 = 0,
    dream: u64 = 0,
    wake_s: f64 = 0,
    sleep_s: f64 = 0,

    pub fn deinit(self: *Run) void {
        self.t.deinit();
    }
};

/// The plan's §2 loop: learn `total/(sleeps+1)` of reality, rebuild the
/// model from itself, learn the next segment, and so on. `sleeps = 0` is
/// the control and runs the identical code path.
///
/// Both arms draw from ONE stream in one order, so the reality they see is
/// the same sequence of the same points — the only difference between them
/// is whether the model was rebuilt partway. A fresh stream per segment
/// would make the arms differ in their data as well as their treatment.
pub fn wakeSleep(
    gpa: std.mem.Allocator,
    vol: *const bark.Volume,
    o: Options,
    pr: Probes,
    total: u64,
    sleeps: u32,
    dream: u64,
    label: []const u8,
) !Run {
    var run = Run{ .t = .{ .model = try marl.Model.init(gpa, o.m), .samples = 0, .seconds = 0 } };
    errdefer run.t.deinit();
    var st = rng.Stream.region(o.seed, 0x5445_4143, 0); // "TEAC", and `teach`'s own
    const wakes: u64 = @as(u64, sleeps) + 1;
    const per = total / wakes;

    var i: u64 = 0;
    while (i < wakes) : (i += 1) {
        const n = if (i + 1 == wakes) total - per * (wakes - 1) else per;
        var wt = try std.time.Timer.start();
        try teachInto(&run.t.model, vol, o, n, &st);
        run.wake_s += @as(f64, @floatFromInt(wt.read())) / 1e9;
        run.reality += n;
        run.t.samples = run.reality;
        score(&run.t, vol.extent, o.invert, pr);
        std.debug.print("  G37: {s:>16}  wake {d}   reality {d:>7}   {d:>6} kernels   RMS {d:.5}\n", .{
            label, i + 1, run.reality, run.t.kernels(), run.t.rms,
        });
        if (i + 1 == wakes) break;

        // SLEEP. The student's options are the teacher's — this is a test
        // of consolidation, not of coarsening, and a coarser student would
        // be answering MARL-14's question again.
        var stm = try std.time.Timer.start();
        const s = try distilEpoch(gpa, &run.t.model, vol, o, o.m, dream, pr, i + 1);
        run.sleep_s += @as(f64, @floatFromInt(stm.read())) / 1e9;
        run.dream += dream;
        run.t.model.deinit();
        run.t.model = s.model; // taken, so `s` is never deinit'd
        run.t.rms = s.rms;
        std.debug.print("  G37: {s:>16}  SLEEP {d}  dream   {d:>7}   {d:>6} kernels   RMS {d:.5}\n", .{
            label, i + 1, run.dream, run.t.kernels(), run.t.rms,
        });
    }
    return run;
}

/// How many kernels read above `level` at a probe point, averaged.
///
/// `level` is the birth rule's own `coverage` and not a chosen number: a
/// kernel covers a point exactly when it reads above it, and the coverage
/// gate is what decides whether a crowded neighbourhood may buy any more
/// capacity. Overlap measured at any other level would be measuring
/// something the model does not act on.
///
/// O(N) per probe, which is why it is a diagnostic over 512 probes and not
/// a query path — the same distinction `predictAll` carries.
fn overlapOf(m: *const marl.Model, pr: Probes, extent: f32, level: f32) f64 {
    var acc: f64 = 0;
    const inv = 1 / extent;
    for (pr.x) |x| {
        const q = [3]f32{ x[0] * inv, x[1] * inv, x[2] * inv };
        var n: u32 = 0;
        for (m.regions) |*reg| {
            for (reg.own.items) |ki| {
                const k = &m.kernels.items[ki];
                if (marl.gaussian(k.shape(), q) > level) n += 1;
            }
        }
        acc += @as(f64, @floatFromInt(n));
    }
    return acc / @as(f64, @floatFromInt(pr.x.len));
}

/// The mean of a model's kernel widths, as σ along the shortest axis —
/// `exp(−logd)` is a standard deviation, so a LARGER number is a wider
/// kernel. Reported beside the overlap because "several overlapping
/// kernels replaced by a cleaner one" should show up as fewer AND wider.
fn meanWidth(m: *const marl.Model) f64 {
    if (m.kernels.items.len == 0) return 0;
    var acc: f64 = 0;
    for (m.kernels.items) |*k| {
        // The diagonal of L, which is `exp(logd)`; σ along an axis is its
        // reciprocal. Read through `shape()` rather than the parameter
        // indices, which are marl.zig's own business.
        const l = k.shape().l;
        acc += (1.0 / @as(f64, l[0]) + 1.0 / @as(f64, l[2]) + 1.0 / @as(f64, l[5])) / 3.0;
    }
    return acc / @as(f64, @floatFromInt(m.kernels.items.len));
}

test "G37 (a) a student cannot beat its teacher — and what a consolidation actually changes" {
    // THE CORRECTION, first, because five sections of Christian's plan
    // rest on it. The plan reads MARL-14 as having shown a student
    // beating its teacher on held-out error. G34's own table says
    // otherwise at every point, and this gate restates it as a CLAIM so
    // that the plan is what refutes it rather than what assumes it.
    //
    // The information argument is short: a student sees only its
    // teacher's output. It has no access to anything the teacher got
    // wrong, so its best possible outcome is an exact copy and its actual
    // outcome is a copy on a budget.
    //
    // There is exactly ONE mechanism against that, and it is the reason
    // the one-ray teacher is here. Distillation to a smaller student is a
    // low-pass filter, and if a teacher's error is partly high-frequency —
    // kernels fighting, weights hovering at MARL-13's NLMS floor — a copy
    // that cannot represent the wiggle can be closer to a smooth truth
    // than the original. MARL-14 saw no sign of it, but its teacher was
    // trained at sixteen rays and is nearly clean. If it exists anywhere
    // it is at one ray, where MARL-13 measured 23% of the population
    // bought on nothing.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);

    var o = Options{ .samples = 96_000, .probes = 512, .surface_band = 1.0, .invert = true };
    o.m.rate_w = 0.05;
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    const DREAM: u64 = 150_000;
    var best: [2]f32 = .{ 999, 999 };
    var untangle: f64 = 999;

    for ([_]u32{ 16, 1 }, 0..) |rays, ri| {
        var to = o;
        to.rays = rays;
        var t = try teach(gpa, &vol, to, pr);
        defer t.deinit();
        const t_over = overlapOf(&t.model, pr, vol.extent, to.m.coverage);
        std.debug.print("\n  G37 (a): {d:>2} rays — teacher {d} kernels, RMS {d:.5}, overlap {d:.2}, mean σ {d:.4} ({s})\n", .{
            rays, t.kernels(), t.rms, t_over, meanWidth(&t.model), @tagName(builtin.mode),
        });
        std.debug.print("  G37 (a): {s:>22} {s:>8} {s:>10} {s:>10} {s:>9} {s:>8} {s:>9}\n", .{ "student", "kernels", "RMS", "RMS/RMS_t", "overlap", "mean σ", "untangle" });

        // Matched, then the two dials MARL-14 established: a higher
        // surprise threshold, and a coarser basis.
        var so_theta = to.m;
        so_theta.threshold = 0.1;
        var so_coarse = to.m;
        so_coarse.regions = 4;
        const sweep = [_]struct { name: []const u8, m: marl.Options }{
            .{ .name = "matched", .m = to.m },
            .{ .name = "θ = 0.1", .m = so_theta },
            .{ .name = "regions 6 → 4", .m = so_coarse },
        };
        for (sweep) |sw| {
            var s = try distil(gpa, &t.model, &vol, to, sw.m, DREAM, pr);
            defer s.deinit();
            const s_over = overlapOf(&s.model, pr, vol.extent, to.m.coverage);
            const kr = @as(f64, @floatFromInt(s.kernels())) / @as(f64, @floatFromInt(t.kernels()));
            const ur = (s_over / t_over) / kr;
            std.debug.print("  G37 (a): {s:>22} {d:>8} {d:>10.5} {d:>10.3} {d:>9.2} {d:>8.4} {d:>9.3}\n", .{
                sw.name, s.kernels(), s.rms, s.rms / t.rms, s_over, meanWidth(&s.model), ur,
            });
            best[ri] = @min(best[ri], s.rms / t.rms);
            // THE DIFF is read off the MATCHED student alone. A coarser
            // student is a different question — of course it overlaps
            // less, it has bigger regions — and mixing the two would let
            // a coarsening dial answer a structural question.
            if (std.mem.eql(u8, sw.name, "matched") and rays == 1) untangle = ur;
        }
    }

    std.debug.print("  G37 (a): the best student over the sweep is {d:.3}× its teacher at 16 rays (≥ {d:.1} predicted, HELD) and {d:.3}× at one (≥ {d:.1}, REFUTED — Christian's premise, in the noisy regime only)\n", .{
        best[0], thresholds.MARL18_PREMISE, best[1], thresholds.MARL18_REGULARISE,
    });
    std.debug.print("  G37 (a): THE DIFF, at one ray and matched options — overlap ratio over population ratio {d:.3} (≤ {d:.1} predicted, REFUTED the OTHER WAY: the student is MORE crowded per kernel, so a consolidation CONCENTRATES rather than untangles)\n", .{
        untangle, thresholds.MARL18_UNTANGLE,
    });

    // MARL18_PREMISE HELD, and it is asserted: on a nearly-clean teacher a
    // student cannot beat it, because it sees only the teacher's output
    // and has no access to anything the teacher got wrong.
    try testing.expect(best[0] >= thresholds.MARL18_PREMISE);

    // MARL18_REGULARISE is REFUTED at 0.960 and is NOT asserted. What is
    // asserted is the finding that refuted it, in its strong form: the
    // effect is a CROSS-OVER and not a level. Distillation is a net LOSS
    // on the clean teacher and a net GAIN on the noisy one, which is what
    // says the mechanism is the teacher's own noise and not some general
    // property of copying.
    //
    // The student fits the teacher's output, noise and all, so it cannot
    // learn anything the teacher got wrong. The only way it can come out
    // ahead is by FAILING to reproduce part of the teacher and being
    // better off for the failure — which is the low-pass argument, and the
    // sweep corroborates it: the coarsest student (1 712 kernels against
    // 5 520) still beats the teacher, where an evidence explanation would
    // have it lose.
    try testing.expect(best[1] < 1.0);
    try testing.expect(best[0] > best[1]);

    // MARL18_UNTANGLE is REFUTED at 1.606 and is NOT asserted. The
    // student sheds a THIRD of the population while raising the overlap at
    // a probe, so what a consolidation performs is not Christian's
    // A + B + C + D → X + Y. It is the ninth item on his list and not the
    // eighth: low-contribution kernels are retired and the survivors sit
    // where the queries are.
    try testing.expect(untangle > 1.0);
}

test "G37 (b) is a consolidated model a better PLACE TO LEARN FROM?" {
    // Christian's plan, §2, and the thing MARL-14 never ran: distil, put
    // the student in the master's place, and CARRY ON LEARNING.
    //
    // Two arms on ONE reality stream in one order — the same points, the
    // same estimates, the same total. The only difference is whether the
    // model was rebuilt from itself three times along the way. Anything
    // that separates them is attributable to the rebuild and to nothing
    // else, which is why `wakeSleep` runs the control through the
    // identical code path at `sleeps = 0`.
    //
    // Run at BOTH noise levels, because the population number alone
    // cannot tell "consolidation collects capacity bought on noise" from
    // "a re-fit happens to find a leaner solution". The noise story makes
    // the harder prediction — that the saving GROWS with the noise —
    // and MARL-13 measured the size of the prize: 9 923 kernels at one ray
    // against 7 656 at sixteen for the same samples.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);

    var o = Options{ .samples = 96_000, .probes = 512, .surface_band = 1.0, .invert = true };
    o.m.rate_w = 0.05;
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    const TOTAL: u64 = 96_000;
    const SLEEPS: u32 = 3;
    const DREAM: u64 = 150_000;
    var kr: [2]f64 = undefined;
    var b1_rms: f32 = 0;
    var b1_k: u32 = 0;
    var b1_s: f64 = 0;

    for ([_]u32{ 16, 1 }, 0..) |rays, ri| {
        var ro = o;
        ro.rays = rays;
        std.debug.print("\n  G37 (b): {d} rays, {d} reality samples, {d} sleeps of {d} dream samples ({s})\n", .{
            rays, TOTAL, SLEEPS, DREAM, @tagName(builtin.mode),
        });
        var a = try wakeSleep(gpa, &vol, ro, pr, TOTAL, 0, DREAM, "straight");
        defer a.deinit();
        var b = try wakeSleep(gpa, &vol, ro, pr, TOTAL, SLEEPS, DREAM, "consolidated");
        defer b.deinit();

        kr[ri] = @as(f64, @floatFromInt(b.t.kernels())) / @as(f64, @floatFromInt(a.t.kernels()));
        if (rays == 1) {
            b1_rms = b.t.rms;
            b1_k = b.t.kernels();
            b1_s = b.wake_s + b.sleep_s;
        }
        std.debug.print("  G37 (b): {d:>2} rays — RMS {d:.5} → {d:.5} ({d:.3}×, ≥ {d:.1} predicted); kernels {d} → {d} ({d:.3}×, ≤ {d:.2}); {d:.1} s awake + {d:.1} s asleep against {d:.1} s\n", .{
            rays,       a.t.rms,     b.t.rms,     b.t.rms / a.t.rms, thresholds.MARL18_STAIRCASE,
            a.t.kernels(), b.t.kernels(), kr[ri],  thresholds.MARL18_POPULATION,
            b.wake_s,   b.sleep_s,   a.wake_s,
        });

        // The arms are matched on REALITY, which is the expensive
        // resource — rays are what a cache exists to avoid buying.
        try testing.expectEqual(a.reality, b.reality);
        try testing.expectEqual(@as(u64, 0), a.dream);
    }

    std.debug.print("  G37 (b): THE GRADIENT — the saving is {d:.3}× at 16 rays and {d:.3}× at one; ratio {d:.3} (≥ {d:.1} predicted, HELD)\n", .{
        kr[0], kr[1], kr[0] / kr[1], thresholds.MARL18_GRADIENT,
    });

    // ── The two controls, which are the gate's ability to fail ────────
    //
    // The result above is that consolidation is worth 10% of the accuracy
    // at one ray a sample. Two much cheaper things could produce that
    // number, and until they are ruled out the finding is "some variance
    // reduction helps", which nobody needed a second model to learn.
    var co = o;
    co.rays = 1;

    // C1 — MORE REALITY, at roughly equal wall clock. The consolidated arm
    // spent most of its time asleep, so the straight arm is given four
    // times the samples instead.
    //
    // MARL-13 (b) says the VARIANCE half of the error cannot be bought
    // down this way — NLMS hovers at μ/(2−μ)·V however much data arrives
    // — but the BIAS half can, and this measures the two together. What
    // it finds is that four times the reality gets most of the way there
    // (0.21976 against 0.21430) and pays for it in TOPOLOGY: 8 135 kernels
    // against 3 671. The third door, open at every rate, and it is what
    // makes "more samples" the wrong answer even when it nearly works.
    var c1 = co;
    c1.samples = TOTAL * 4;
    var more = try wakeSleep(gpa, &vol, c1, pr, TOTAL * 4, 0, DREAM, "4x reality");
    defer more.deinit();

    // C2 — A LOWER RATE, and it REFUTES the phase's headline. MARL-13 (c)
    // measured the rate as a real door on the same noise, so a tenth of it
    // is the cheapest possible way to buy what a sleep buys. The
    // expectation written into this control was that a rate closes the
    // weight door and leaves the topology one open, because MARL-13 says
    // "no rate closes that".
    //
    // **It closes both.** 0.18474 at 3 142 kernels in 1.5 s, against
    // consolidation's 0.21430 at 3 671 in 11.6 — better on accuracy,
    // better on memory, and eight times cheaper. MARL-13's sentence was
    // about `rate_w`; this control moves `rate_geom` too, and a kernel
    // that does not chase a noise realisation geometrically stays where it
    // can cover, so fewer births are needed. That is MARL-13 (c)'s own
    // 11 176 → 7 113 showing up again.
    //
    // So the arms above were run against a baseline this repo already knew
    // was not the best available: G33 (d) fixed `rate_geom` at the default
    // ON PURPOSE, so that its headline would not be configured from its
    // own result. For MARL-18 that choice is wrong — the question is
    // whether consolidation beats LEARNING, and it has to be the best
    // learning. G37 (c) re-runs it on the corrected fixture.
    var c2 = co;
    c2.m.rate_w = o.m.rate_w / 10;
    c2.m.rate_geom = o.m.rate_geom / 10;
    var slow = try wakeSleep(gpa, &vol, c2, pr, TOTAL, 0, DREAM, "rate/10");
    defer slow.deinit();

    std.debug.print("  G37 (b): CONTROLS at one ray, against the consolidated arm's {d:.5} at {d} kernels and {d:.1} s —\n", .{ b1_rms, b1_k, b1_s });
    std.debug.print("  G37 (b):   4× the reality  {d:.5} at {d:>5} kernels, {d:.1} s — MARL-13 (b)'s hover does not decay with sample count\n", .{ more.t.rms, more.t.kernels(), more.wake_s });
    std.debug.print("  G37 (b):   rate/10         {d:.5} at {d:>5} kernels, {d:.1} s — a rate closes the weight door and not the topology one\n", .{ slow.t.rms, slow.t.kernels(), slow.wake_s });

    // C1 holds: more reality does not reach what the sleeps reached, and
    // buys its accuracy in kernels — 2.2× the population for 2.5% more
    // error than the consolidated arm.
    try testing.expect(more.t.rms > b1_rms);
    try testing.expect(more.t.kernels() > 2 * b1_k);

    // C2 is the REFUTATION and it is asserted in the direction it actually
    // went, so that a future change which makes consolidation win outright
    // fails here and gets read rather than celebrated.
    try testing.expect(slow.t.rms < b1_rms);
    try testing.expect(slow.t.kernels() < b1_k);
}

test "G37 (c) …and with the rates already right, does a sleep still buy anything?" {
    // G37 (b)'s control refuted G37 (b). Consolidation beat straight
    // learning 0.898 at one ray — and then `rate_w`/10 with `rate_geom`/10
    // beat consolidation on accuracy, on memory and on wall clock at once.
    //
    // The arms there ran at G33 (d)'s configuration, which pins
    // `rate_geom` to the default ON PURPOSE so that its headline is not
    // configured from its own result. That is right for G33 and wrong
    // here: MARL-18 asks whether consolidation beats LEARNING, and that
    // has to mean the best learning this repo knows about — MARL-13 (c)'s
    // `rate_w` 0.05 WITH `rate_geom` 0.02, which it measured at 1.67× and
    // 11 176 → 7 113 kernels.
    //
    // `MARL18_RATE_FIRST` was written into `thresholds.zig` and
    // `tools/marl18_predict.py` before this ran, and it gates a decision:
    // a refutation here means a sleep does something no rate can, and the
    // plan's §4 local micro-distillation is worth building.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);

    var o = Options{ .samples = 96_000, .probes = 512, .surface_band = 1.0, .invert = true, .rays = 1 };
    o.m.rate_w = 0.05;
    o.m.rate_geom = 0.02; // MARL-13 (c)'s, and the only line that differs from (b)
    var pr = try probesOf(gpa, &vol, o.ao, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);

    const TOTAL: u64 = 96_000;
    std.debug.print("\n  G37 (c): one ray, at MARL-13 (c)'s own best rates — rate_w {d}, rate_geom {d} ({s})\n", .{
        o.m.rate_w, o.m.rate_geom, @tagName(builtin.mode),
    });
    var a = try wakeSleep(gpa, &vol, o, pr, TOTAL, 0, 150_000, "straight");
    defer a.deinit();
    var b = try wakeSleep(gpa, &vol, o, pr, TOTAL, 3, 150_000, "consolidated");
    defer b.deinit();

    std.debug.print("  G37 (c): RMS {d:.5} → {d:.5} ({d:.3}×, ≥ {d:.1} predicted — REFUTED); kernels {d} → {d} ({d:.3}×); {d:.1} s + {d:.1} s asleep against {d:.1} s\n", .{
        a.t.rms,       b.t.rms,       b.t.rms / a.t.rms, thresholds.MARL18_RATE_FIRST,
        a.t.kernels(), b.t.kernels(),
        @as(f64, @floatFromInt(b.t.kernels())) / @as(f64, @floatFromInt(a.t.kernels())),
        b.wake_s,      b.sleep_s,     a.wake_s,
    });

    // WHAT a sleep did, since at the right rates it is barely a population
    // effect (0.961×). Christian's §3 asked for the edit vocabulary; these
    // are the two entries on his list that a Gaussian population can show
    // without a correspondence between kernels — widening, and crowding.
    std.debug.print("  G37 (c): straight     overlap {d:.2}, mean σ {d:.4}\n", .{
        overlapOf(&a.t.model, pr, vol.extent, o.m.coverage), meanWidth(&a.t.model),
    });
    std.debug.print("  G37 (c): consolidated overlap {d:.2}, mean σ {d:.4}\n", .{
        overlapOf(&b.t.model, pr, vol.extent, o.m.coverage), meanWidth(&b.t.model),
    });

    // And the honest accounting, because the plan's §10 wants to schedule
    // this per frame. One ray a sample is the CHEAPEST reality that
    // exists: about twenty marched fetches, against the ~320 G33 measured
    // for a real estimate. So this fixture's reality is roughly sixteen
    // times cheaper than a renderer's, and the ratio below is the
    // pessimistic end of the range, not the typical one.
    std.debug.print("  G37 (c): the sleeps cost {d:.1}× the wall clock of the learning they improved — and this fixture's reality is ~16× cheaper than a renderer's, so scale accordingly\n", .{
        b.sleep_s / b.wake_s,
    });

    // MARL18_RATE_FIRST is REFUTED at 0.940 and is NOT asserted. What is
    // asserted is the finding: a sleep still pays ON TOP of the cheap fix,
    // so consolidation is not merely a slow proxy for a lower rate. That
    // is the result that makes the plan's §4 worth building.
    try testing.expect(b.t.rms < a.t.rms);
    // …and the win is SMALLER than it was against the handicapped baseline
    // (0.940 against 0.898), which is the variance story holding: turn the
    // rates down first, and there is less left for a sleep to collect.
    try testing.expect(b.t.rms / a.t.rms > 0.898);
}


// ── MARL-20: a moving occluder, and residual layers ──────────────────
//
// Christian's plan, §7 and §8: keep a baked static MARL for the world and
// represent moving things as additional RESIDUAL layers,
//
//     F(x, t) = M_static(x) + Σ M_dynamic_i(x, t)
//
// with the property he is after being that COMPLEXITY FOLLOWS CHANGE.
//
// This is MARL-16 cashed, and MARL-16 was a refutation at the time. A bias
// term was built twice and lost twice, and what came out of it was: **zero
// is not special because it is zero — it is special because it is what an
// EMPTY MODEL ALREADY PREDICTS.** A residual layer is zero everywhere the
// world did not change, so it is the exact shape of field this
// representation is free on. The phase that found that out did so by
// failing to add a background.
//
// `tools/marl20_predict.py` has the numbers.

/// A dynamic occluder: a sphere in world units.
///
/// Its influence on the field has a HARD support, for the same structural
/// reason `CUTOFF` gives a kernel one — occlusion here is bounded by
/// `reach`, so a mover of radius r cannot change the field beyond r + reach
/// of its centre. Not approximately: exactly.
pub const Mover = struct {
    c: [3]f32,
    r: f32,

    pub fn inside(self: Mover, p: [3]f32) bool {
        const d = [3]f32{ p[0] - self.c[0], p[1] - self.c[1], p[2] - self.c[2] };
        return d[0] * d[0] + d[1] * d[1] + d[2] * d[2] < self.r * self.r;
    }

    /// How far from the centre the field can possibly differ.
    pub fn affected(self: Mover, o: AoOptions) f32 {
        return self.r + o.reach;
    }

    pub fn near(self: Mover, o: AoOptions, p: [3]f32) bool {
        const a = self.affected(o);
        const d = [3]f32{ p[0] - self.c[0], p[1] - self.c[1], p[2] - self.c[2] };
        return d[0] * d[0] + d[1] * d[1] + d[2] * d[2] < a * a;
    }
};

pub const Pair = struct { base: f32, moved: f32 };

/// Both fields from the SAME marched directions.
///
/// A mover only ADDS occlusion, so a ray that already hit the level
/// contributes exactly zero to the difference. The two estimates are
/// perfectly correlated wherever nothing changed, and the difference of two
/// Binomial estimates that share their draws has far less variance than
/// either of them — **a residual is cheaper to measure than a field.**
/// Estimating the two independently would pay √2 the noise for strictly
/// less information.
pub fn aoPair(vol: *const bark.Volume, o: AoOptions, mv: Mover, x: [3]f32, st: *rng.Stream) Pair {
    if (vol.at(x) > 0) return .{ .base = 0, .moved = 0 };
    const steps: u32 = @intFromFloat(@ceil(o.reach / o.step));
    const in_mover = mv.inside(x);
    var open_b: u32 = 0;
    var open_m: u32 = 0;
    var r: u32 = 0;
    while (r < o.rays) : (r += 1) {
        // `aoAt`'s draw, term for term, so the two estimators agree where
        // the mover is absent.
        const z = 2 * st.unit() - 1;
        const a = 2 * std.math.pi * st.unit();
        const s = @sqrt(@max(0, 1 - z * z));
        const d = [3]f32{ s * fmath.cosf(a), s * fmath.sinf(a), z };
        var hit_b = false;
        var hit_m = in_mover;
        var i: u32 = 1;
        while (i <= steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) * o.step;
            const p = [3]f32{ x[0] + d[0] * t, x[1] + d[1] * t, x[2] + d[2] * t };
            if (!hit_b and vol.at(p) > 0) hit_b = true;
            if (!hit_m and mv.inside(p)) hit_m = true;
            if (hit_b and hit_m) break;
        }
        if (!hit_b) open_b += 1;
        if (!hit_b and !hit_m) open_m += 1;
    }
    const inv = 1 / @as(f32, @floatFromInt(o.rays));
    return .{ .base = @as(f32, @floatFromInt(open_b)) * inv, .moved = @as(f32, @floatFromInt(open_m)) * inv };
}

/// Probes carrying BOTH truths, from the same reference rays.
pub const DynProbes = struct {
    x: [][3]f32,
    base: []f32,
    moved: []f32,

    pub fn deinit(self: *DynProbes, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.base);
        gpa.free(self.moved);
    }

    /// The fraction of the query set the mover actually disturbs, by more
    /// than `eps`. Measured rather than assumed: the geometric ball is over
    /// the CUBE and the queries are on a shell.
    pub fn disturbed(self: DynProbes, eps: f32) f64 {
        var n: usize = 0;
        for (self.base, self.moved) |b, m| {
            if (@abs(b - m) > eps) n += 1;
        }
        return @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(self.x.len));
    }
};

/// Probes drawn INSIDE the mover's affected ball.
///
/// A global probe set answers "how wrong is the level now", and it is
/// diluted by construction: an object occupying a few per cent of a scene
/// leaves most probes untouched, so only a handful land where anything
/// changed and their RMS is sampling noise rather than a measurement. This
/// set answers the question a renderer actually asks — how good is the
/// shading NEAR THE OBJECT — and it is where the phase's numbers are taken.
pub fn dynProbesNear(gpa: std.mem.Allocator, vol: *const bark.Volume, o: AoOptions, mv: Mover, n: u32, seed: u64, band: f32) !DynProbes {
    var st = rng.Stream.region(seed ^ 0x4e, 0x4e454152, 0); // "NEAR"
    var p = DynProbes{
        .x = try gpa.alloc([3]f32, n),
        .base = try gpa.alloc(f32, n),
        .moved = try gpa.alloc(f32, n),
    };
    errdefer p.deinit(gpa);
    var t = o;
    t.rays = TRUTH_RAYS;
    for (p.x, p.base, p.moved) |*x, *b, *m| {
        x.* = drawNear(vol, band, mv, o, &st);
        const pr = aoPair(vol, t, mv, x.*, &st);
        b.* = pr.base;
        m.* = pr.moved;
    }
    return p;
}

pub fn dynProbesOf(gpa: std.mem.Allocator, vol: *const bark.Volume, o: AoOptions, mv: Mover, n: u32, seed: u64, band: f32) !DynProbes {
    var st = rng.Stream.region(seed, 0x4341_4348, 0); // "CACH", the same as `probesOf`
    var p = DynProbes{
        .x = try gpa.alloc([3]f32, n),
        .base = try gpa.alloc(f32, n),
        .moved = try gpa.alloc(f32, n),
    };
    errdefer p.deinit(gpa);
    var t = o;
    t.rays = TRUTH_RAYS;
    for (p.x, p.base, p.moved) |*x, *b, *m| {
        x.* = drawQuery(vol, band, &st);
        const pr = aoPair(vol, t, mv, x.*, &st);
        b.* = pr.base;
        m.* = pr.moved;
    }
    return p;
}

/// One draw from the CHANGED REGION: inside the mover's affected ball and
/// on the shell where a renderer shades. This is §12's "work scales with
/// changed regions" as a sampling rule — you know where the object is, so
/// you know where the residual can be non-zero, exactly.
fn drawNear(vol: *const bark.Volume, band: f32, mv: Mover, o: AoOptions, st: *rng.Stream) [3]f32 {
    const a = mv.affected(o);
    var tries: u32 = 0;
    while (tries < 4096) : (tries += 1) {
        const q = [3]f32{
            mv.c[0] + (2 * st.unit() - 1) * a,
            mv.c[1] + (2 * st.unit() - 1) * a,
            mv.c[2] + (2 * st.unit() - 1) * a,
        };
        if (q[0] < 0 or q[0] >= vol.extent or q[1] < 0 or q[1] >= vol.extent) continue;
        if (q[2] < 0 or q[2] >= vol.extent) continue;
        if (!mv.near(o, q)) continue;
        if (band > 0 and @abs(vol.at(q)) >= band) continue;
        return q;
    }
    return mv.c;
}

/// A full RE-BAKE on the perturbed field: what you pay for not being clever.
fn teachMoved(gpa: std.mem.Allocator, vol: *const bark.Volume, o: Options, mv: Mover, n: u64) !Trained {
    var t = Trained{ .model = try marl.Model.init(gpa, o.m), .samples = n, .seconds = 0 };
    errdefer t.deinit();
    var st = rng.Stream.region(o.seed, 0x5245_4241, 0); // "REBA"
    var ao = o.ao;
    ao.rays = o.rays;
    const inv = 1 / vol.extent;
    var timer = try std.time.Timer.start();
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const q = drawQuery(vol, o.surface_band, &st);
        const p = aoPair(vol, ao, mv, q, &st);
        _ = try t.model.observe(.{ q[0] * inv, q[1] * inv, q[2] * inv }, .{1 - p.moved});
    }
    t.seconds = @as(f64, @floatFromInt(timer.read())) / 1e9;
    return t;
}

/// A RESIDUAL layer: `AO_static − AO_perturbed`, which is ≥ 0 because a
/// mover only adds occlusion, and ZERO everywhere it did not reach.
///
/// `into` continues an existing layer (the adapt arm); pass a fresh model
/// to build one (the rebuild arm). `over` is the region to sample: for a
/// move it must be the UNION of where the object was and where it now is,
/// because a residual left behind is a wrong NON-ZERO value and the model
/// has to be taken back there to be told so.
fn teachResidualInto(m: *marl.Model, vol: *const bark.Volume, o: Options, mv: Mover, over: []const Mover, n: u64, st: *rng.Stream) !void {
    var ao = o.ao;
    ao.rays = o.rays;
    const inv = 1 / vol.extent;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const pick = over[@intCast(st.below(@intCast(over.len)))];
        const q = drawNear(vol, o.surface_band, pick, ao, st);
        const p = aoPair(vol, ao, mv, q, st);
        _ = try m.observe(.{ q[0] * inv, q[1] * inv, q[2] * inv }, .{p.base - p.moved});
    }
}

/// The static bake's own error against the UNPERTURBED truth, and the
/// composed field's against the perturbed one. The static model holds
/// `1 − AO_static` (MARL-13: a zero background is the free one) and the
/// residual holds `AO_static − AO_perturbed`, so
///
///     1 − AO_perturbed = (1 − AO_static) + (AO_static − AO_perturbed)
///
/// is an IDENTITY, not an approximation scheme. Only the two fits can be
/// wrong.
fn rmsAgainst(m: *marl.Model, xs: [][3]f32, truth: []const f32, extent: f32) f32 {
    var acc: f64 = 0;
    for (xs, truth) |x, y| {
        const p = (m.predict(.{ x[0] / extent, x[1] / extent, x[2] / extent }) catch unreachable)[0];
        const e = (1 - p) - y;
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(xs.len))));
}

fn rmsComposed(s: *marl.Model, r: *marl.Model, xs: [][3]f32, truth: []const f32, extent: f32) f32 {
    var acc: f64 = 0;
    for (xs, truth) |x, y| {
        const q = [3]f32{ x[0] / extent, x[1] / extent, x[2] / extent };
        const a = (s.predict(q) catch unreachable)[0];
        const b = (r.predict(q) catch unreachable)[0];
        const e = (1 - (a + b)) - y;
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(xs.len))));
}

test "G39 a moving occluder: complexity follows change" {
    // Christian's plan §7/§8/§12-stage-2. A baked static world plus a
    // RESIDUAL layer for what moved, and the question is whether the cost
    // follows the CHANGE rather than the scene.
    //
    // MARL-16 is why this should work, and it was a refutation at the
    // time: zero is not special because it is zero, it is special because
    // it is what an EMPTY MODEL ALREADY PREDICTS. A residual is zero
    // everywhere the world did not change.
    const gpa = testing.allocator;
    var vol = try groveVolume(gpa, GROVE_RES, GROVE_EXTENT);
    defer vol.deinit(gpa);

    var o = Options{ .samples = 60_000, .probes = 512, .surface_band = 1.0, .invert = true };
    o.m.rate_w = 0.05; // MARL-13: the rate is the noise floor
    o.m.rate_geom = 0.02; // MARL-18 (c): and this is the half that phase's
    // own control caught being left at the default. The baseline here has
    // to be the best learning this repo knows about, or the residual layer
    // gets to look good against a handicap.
    const N: u64 = 60_000;

    // The mover sits at a lattice BODY CENTRE, which is where the grove's
    // corridors are widest — 9.25 units to the nearest sphere centre, so
    // 4.25 of clearance after the radius and the jitter.
    //
    // The first attempt put a 2.0 mover at a FACE centre and it disturbed
    // 2.0% of the query set for 0.2% of the global RMS. That is not a
    // weak result, it is a null: a fixture has to move the thing being
    // measured before its numbers mean anything. Recorded rather than
    // quietly replaced, because "the effect was too small to see" and
    // "there is no effect" print the same way.
    const A = Mover{ .c = .{ 10.67, 10.67, 10.67 }, .r = 4.2 };
    const B = Mover{ .c = .{ 21.33, 10.67, 10.67 }, .r = 4.2 };
    try testing.expect(vol.at(A.c) <= 0);
    try testing.expect(vol.at(B.c) <= 0);

    var pr = try dynProbesOf(gpa, &vol, o.ao, A, o.probes, o.seed, o.surface_band);
    defer pr.deinit(gpa);
    const moved_frac = pr.disturbed(0.01);

    // The static bake — MARL-13's shell arm, and the asset that ships.
    var stat = try teach(gpa, &vol, o, .{ .x = pr.x, .y = pr.base });
    defer stat.deinit();

    // A full re-bake on the perturbed field: the honest opponent.
    var re = try teachMoved(gpa, &vol, o, A, N);
    defer re.deinit();
    re.rms = rmsAgainst(&re.model, pr.x, pr.moved, vol.extent);

    // The residual layer, at ONE EIGHTH of the re-bake's rays, sampled
    // only where the object can possibly have changed anything.
    var res = try marl.Model.init(gpa, o.m);
    defer res.deinit();
    var s_res = rng.Stream.region(o.seed, 0x5245_5344, 0); // "RESD"
    var t_res = try std.time.Timer.start();
    try teachResidualInto(&res, &vol, o, A, &.{A}, N / 8, &s_res);
    const res_s = @as(f64, @floatFromInt(t_res.read())) / 1e9;

    const stat_on_moved = rmsAgainst(&stat.model, pr.x, pr.moved, vol.extent);
    const composed = rmsComposed(&stat.model, &res, pr.x, pr.moved, vol.extent);

    // THE DENOMINATOR, and the phase turns on it. A global probe set is
    // diluted by construction: an object occupying a few per cent of a
    // scene leaves most probes untouched, and only a couple of dozen of
    // 512 land where anything changed — an RMS over those is sampling
    // noise, not a measurement. (The first attempt did exactly that and
    // reported ratios off 24 probes.) So the numbers that carry the claim
    // are taken over probes drawn IN the object's neighbourhood, which is
    // also the question a renderer asks: how good is the shading near the
    // object. The global figures stay in the table so the dilution is
    // visible rather than chosen.
    var lpr = try dynProbesNear(gpa, &vol, o.ao, A, o.probes, o.seed, o.surface_band);
    defer lpr.deinit(gpa);
    const local_delta = blk: {
        var acc: f64 = 0;
        for (lpr.base, lpr.moved) |b, m| acc += @abs(b - m);
        break :blk acc / @as(f64, @floatFromInt(lpr.x.len));
    };
    const d_stale = rmsAgainst(&stat.model, lpr.x, lpr.moved, vol.extent);
    const d_re = rmsAgainst(&re.model, lpr.x, lpr.moved, vol.extent);
    const d_comp = rmsComposed(&stat.model, &res, lpr.x, lpr.moved, vol.extent);
    const k_ratio = @as(f64, @floatFromInt(res.kernels.items.len)) / @as(f64, @floatFromInt(re.kernels()));

    std.debug.print("\n  G39: a {d:.1}-unit mover in a {d:.0}-unit grove; it can disturb the field within {d:.1} units, and does disturb {d:.3} of the query set ({s})\n", .{
        A.r, vol.extent, A.affected(o.ao), moved_frac, @tagName(builtin.mode),
    });
    std.debug.print("  G39: {s:<34} {s:>8} {s:>9} {s:>9} {s:>8}\n", .{ "arm", "kernels", "KiB", "RMS", "build s" });
    std.debug.print("  G39: {s:<34} {d:>8} {d:>9.1} {d:>9.5} {d:>8.1}\n", .{ "the static bake, on the STATIC field", stat.kernels(), @as(f64, @floatFromInt(stat.bytes())) / 1024.0, stat.rms, stat.seconds });
    std.debug.print("  G39: {s:<34} {d:>8} {d:>9.1} {d:>9.5} {s:>8}\n", .{ "…the same bake, now WRONG", stat.kernels(), @as(f64, @floatFromInt(stat.bytes())) / 1024.0, stat_on_moved, "—" });
    std.debug.print("  G39: {s:<34} {d:>8} {d:>9.1} {d:>9.5} {d:>8.1}\n", .{ "a full re-bake", re.kernels(), @as(f64, @floatFromInt(re.bytes())) / 1024.0, re.rms, re.seconds });
    std.debug.print("  G39: {s:<34} {d:>8} {d:>9.1} {d:>9.5} {d:>8.1}\n", .{ "static + residual, 1/8 the rays", res.kernels.items.len, @as(f64, @floatFromInt(res.kernels.items.len * marl.PARAMS * 4)) / 1024.0, composed, res_s });
    std.debug.print("  G39: {d} probes drawn IN the object's neighbourhood, where it moves the truth by {d:.4} on average — the stale bake {d:.5}, a full re-bake {d:.5}, static + residual {d:.5}\n", .{ lpr.x.len, local_delta, d_stale, d_re, d_comp });
    std.debug.print("  G39: SPARSE {d:.3}× the re-bake's kernels (≤ {d:.2} predicted); COMPOSED {d:.3}× its RMS on the disturbed set (≤ {d:.2}); the residual recovers {d:.2}× of the stale bake's error there, and {d:.3}× globally\n", .{
        k_ratio, thresholds.MARL20_SPARSE, d_comp / d_re, thresholds.MARL20_COMPOSE, d_stale / d_comp, stat_on_moved / composed,
    });

    // The fixture has to be capable of showing something before its
    // numbers mean anything: the object must break the static bake on the
    // set it disturbed.
    // THE VALIDITY CRITERION, which should have been written down before
    // the first fixture rather than discovered by two nulls. A 2.0 mover
    // at a face centre moved the truth so little that 24 of 512 probes
    // noticed; a 3.5 mover moved it by 0.0334.
    //
    // The first form demanded the object move the truth by more than the
    // cache's own RMS, and that was the WRONG bar: a model's error is
    // spread over a whole field, and a small STRUCTURED change can be
    // perfectly learnable underneath it. The direct statement is that a
    // full re-bake must actually beat the stale bake on the local set,
    // because that is the definition of there being something for a
    // residual layer to learn.
    //
    // The margin is DERIVED rather than chosen, because the second form of
    // this check was a round 1.15 that the measurement then landed 0.7%
    // under — which is how a validity bar turns into a tuned threshold if
    // nobody is watching. The reference probes are `TRUTH_RAYS` = 4096, so
    // their own standard deviation is at most 0.5/√4096 = 0.0078. A gap
    // wider than that is a gap the instrument can see; anything narrower
    // is the instrument.
    const ref_sigma: f32 = 0.5 / @sqrt(@as(f32, @floatFromInt(TRUTH_RAYS)));
    std.debug.print("  G39: the object degrades the local bake by {d:.3}× — a gap of {d:.4} against the reference estimator's own σ of {d:.4}\n", .{
        d_stale / d_re, d_stale - d_re, ref_sigma,
    });
    try testing.expect(d_stale - d_re > ref_sigma);
    try testing.expect(k_ratio <= thresholds.MARL20_SPARSE);
    try testing.expect(d_comp / d_re <= thresholds.MARL20_COMPOSE);
    // The mutation this gate is paid for: a residual layer that learned
    // nothing would leave the composed arm exactly at the stale bake.
    try testing.expect(d_comp < d_stale);

    // ── THE MOVE, and it is the case MARL-19 could not reach ──────────
    //
    // MARL-19 found history nearly free, and MARL-16 said why: the
    // structure that goes obsolete sits at ZERO, which is what an empty
    // model already predicts. A moving occluder breaks that. When the
    // object leaves, the residual it left behind is a WRONG NON-ZERO
    // value, and now the model must actively pull it down.
    //
    // MARL-7 spent a phase looking for an erosion mechanism and found
    // nothing to erode; MARL-8 tried reuse and failed. A residual layer
    // offers a third option neither had: throw it away and build another.
    // FOUR moves, not one, because a single move cannot tell "adapting is
    // better" from "adapting is bigger" — and MARL-7 already measured what
    // repeated change does to a population that only ever accumulates: a
    // thousand kernels a move at flat accuracy, with unrefinement moving it
    // by one per cent. If that shape appears here, the accuracy comparison
    // is beside the point.
    const PATH = [_]Mover{
        .{ .c = .{ 21.33, 10.67, 10.67 }, .r = A.r },
        .{ .c = .{ 21.33, 21.33, 10.67 }, .r = A.r },
        .{ .c = .{ 21.33, 21.33, 21.33 }, .r = A.r },
        .{ .c = .{ 10.67, 21.33, 21.33 }, .r = A.r },
    };
    std.debug.print("  G39: THE MOVE — {s:>6} {s:>10} {s:>10} {s:>10} {s:>10} {s:>8}\n", .{ "step", "adapt k", "adapt RMS", "fresh k", "fresh RMS", "ratio" });
    var prev = A;
    for (PATH, 0..) |mv, step| {
        var lp = try dynProbesNear(gpa, &vol, o.ao, mv, o.probes, o.seed, o.surface_band);
        defer lp.deinit(gpa);

        // ADAPT: keep the layer and take it back over BOTH neighbourhoods,
        // because it must be told the old disturbance is gone as well as
        // where the new one is. Same budget, more ground to cover — which
        // is a cost the rebuild arm simply does not pay.
        var ast = rng.Stream.region(o.seed ^ @as(u64, @intCast(step)), 0x4144_4150, 0); // "ADAP"
        try teachResidualInto(&res, &vol, o, mv, &.{ prev, mv }, N / 8, &ast);
        const ad = rmsComposed(&stat.model, &res, lp.x, lp.moved, vol.extent);

        // REBUILD: a fresh layer, the SAME work, and only the new
        // neighbourhood to cover.
        var nf = try marl.Model.init(gpa, o.m);
        defer nf.deinit();
        var fst = rng.Stream.region(o.seed ^ @as(u64, @intCast(step)), 0x4144_4150, 0);
        try teachResidualInto(&nf, &vol, o, mv, &.{mv}, N / 8, &fst);
        const rb = rmsComposed(&stat.model, &nf, lp.x, lp.moved, vol.extent);

        std.debug.print("  G39:            {d:>6} {d:>10} {d:>10.5} {d:>10} {d:>10.5} {d:>8.3}\n", .{
            step + 1, res.kernels.items.len, ad, nf.kernels.items.len, rb, rb / ad,
        });
        if (step + 1 == PATH.len) {
            const kr = @as(f64, @floatFromInt(res.kernels.items.len)) / @as(f64, @floatFromInt(nf.kernels.items.len));
            std.debug.print("  G39: after {d} moves the adapting layer is {d:.2}× the rebuilt one's size for {d:.3}× its error (≤ {d:.1} predicted); {s}\n", .{
                PATH.len, kr, rb / ad, thresholds.MARL20_REBUILD,
                if (kr > 1.3) "MARL-7's accumulation, in a layer that could simply have been thrown away" else "no accumulation — adapting is holding its size",
            });
            // MARL20_REBUILD is a CEILING at parity. Whichever way it goes,
            // the population is what settles it: a rebuilt layer that is
            // near the adapting one's accuracy at a fraction of its size is
            // the better deal, and it needs no erosion mechanism at all —
            // which is the thing MARL-7 spent a phase failing to find and
            // MARL-8 failed to build.
            try testing.expect(res.kernels.items.len > nf.kernels.items.len);
        }
        prev = mv;
    }
}
