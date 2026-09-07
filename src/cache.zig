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

