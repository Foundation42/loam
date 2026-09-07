//! marble — MARL-11: the campaign's first EXTERNAL baseline.
//!
//! Ten phases, and every comparison in all of them was MARL against MARL.
//! `rbf.zig` is the first thing to measure against that this campaign did
//! not write: the same anisotropic Gaussian, the same `CUTOFF`, the same
//! evaluator, fitted by BATCH ADAM to a real material field, and gated
//! since before `marl.zig` existed.
//!
//! ## Why this is its own file
//!
//! `marl.zig` must not learn what a `bark.Volume` is. Christian's split
//! puts Loam's FIELD STORAGE outside MARL, and a learner that imports the
//! sim's sample planes to get a training set has crossed it by the back
//! door — the next thing it wants is the halo. And `rbf.zig` must not
//! learn what a `marl.Model` is: it is cross-repo pinned, read by rill and
//! by matryoshka's shader, and a learning experiment must not be able to
//! move the kernel out from under three renderers.
//!
//! So the bridge is a third file that imports both and is imported by
//! neither. Nothing here is on the sim path.
//!
//! ## The comparison, and the two oracles
//!
//! `rbf.fit` does not start level. It carries two pieces of knowledge MARL
//! has no equivalent of:
//!
//!     the SEED — centres are placed ON vein voxels, so every kernel
//!                starts where the structure is;
//!     the POOL — half of every batch is drawn FROM vein voxels, so a cube
//!                that is a few per cent vein is sampled as though it were
//!                half.
//!
//! Both are hand-built versions of exactly what MARL-3 and MARL-4 spent
//! two phases discovering the model could not do for itself. So the
//! comparison is a 2×2 with one variable a cell:
//!
//!                            uniform seed+pool   vein-biased (oracle)
//!         rbf   batch Adam          B                    A
//!         MARL  online NLMS         D                    C
//!
//! `B/A` is what the oracle is worth to a batch optimiser. `D/B` is the
//! question the phase exists to ask: BIRTH-FROM-SURPRISE against
//! SEED-THEN-DESCENT, with neither side told where the structure is.
//! Capacity is matched exactly — each rbf arm is run at the kernel count
//! the MARL arm beside it discovered — because MARL-1 established that a
//! comparison at unequal capacity measures the capacity.
//!
//! ## Equal data, not equal work
//!
//! MARL sees each exemplar ONCE. `rbf.fit` draws from a pool of `pool`
//! distinct points and revisits it as many times as its iteration count
//! allows — that is what a batch optimiser is, and taking it away would
//! be measuring something nobody ships. So the currency held equal is
//! DISTINCT EXEMPLARS: MARL gets `pool` of them, rbf gets the same `pool`
//! and may re-read it. That is generous to rbf by a factor of however many
//! passes it makes, and it is the only matching that is unambiguous —
//! per-sample work is a 27-region gather on one side and an O(N) sum on
//! the other, so "equal work" would be a number about data structures.
//!
//! ## The conversion is exact
//!
//! MARL learns on the unit cube; the volume has an extent. A model is
//! carried across by μ′ = Eμ and L′ = L/E, which is exact in f32 when E is
//! a power of two — and so is the read, because (q/E − μ) and (q − Eμ)/E
//! round identically when the scaling is by a power of two. So a MARL
//! model IS an `rbf.Set`, bit for bit, rather than nearly one, and
//! G31 (a) is the gate that says so. That matters beyond tidiness: the
//! set is the asset a renderer loads, and an ε would let the learner and
//! the shader drift in the last places until one of them showed something
//! else and nobody was told.

const std = @import("std");
const builtin = @import("builtin");
const bark = @import("bark.zig");
const rbf = @import("rbf.zig");
const marl = @import("marl.zig");
const rng = @import("rng.zig");
const fmath = @import("fmath.zig");
const thresholds = @import("thresholds.zig");

// ── The fixture ──────────────────────────────────────────────────────

/// One warped sheet vein through a cube — the gate's field, mirrored term
/// for term by `tools/marl11_predict.py`, which is where the thresholds
/// beside it came from.
///
/// A SHEET rather than a ball or a tube, because a sheet is the shape the
/// marble actually makes and the extreme case for the kernel: thin across
/// one axis and wide along two, so an isotropic Gaussian is wrong by the
/// aspect ratio and the descent has to find that out. Warped by one period
/// of a sine, so the sheet is not axis-aligned anywhere except by
/// accident and a kernel cannot fit it with a diagonal L.
pub const FIXTURE_RES: u32 = 32;
/// A POWER OF TWO, and that is load-bearing: it is what makes the
/// unit-cube ↔ volume conversion exact rather than approximate.
pub const FIXTURE_EXTENT: f32 = 32;
/// The blend's softness. `MARBLE_VEIN` is 0.9 over an extent of 40; this
/// is the same ratio at this extent, so the fixture's proportions are the
/// marble's and not a shape chosen to be easy.
pub const FIXTURE_VEIN: f32 = 0.72;
const HALF_THICK: f32 = 0.90;
const WARP_AMP: f32 = 2.2;

/// Signed insideness of the sheet: positive inside the vein, in the
/// volume's own units.
pub fn sheetPhi(extent: f32, p: [3]f32) f32 {
    const freq = 2 * std.math.pi / extent;
    const surf = extent * 0.5 + WARP_AMP * fmath.sinf(freq * p[0]) * fmath.cosf(freq * p[1]);
    return HALF_THICK - @abs(p[2] - surf);
}

/// The fixture as a `bark.Volume` with NO material columns — stride one,
/// φ alone. That is what makes this a single-channel comparison without
/// touching `rbf.zig`: `rbf.target` reads `vol.sample`, and a volume that
/// models no columns returns zero for all eight material channels, so the
/// fit's targets are `{A, 0, 0, …}`. Adam's gradient on a channel whose
/// target and weight are both zero is exactly zero, so those eight
/// channels never move and the fit is a single-channel fit with eight
/// inert passengers. Reading `rms_channel[0]` would have measured the
/// same thing while letting the shared geometry be spent on nine.
/// The two materials the sheet carries when it is asked for any — a
/// graphite half and an ember half, split across x.
///
/// TWO and not one, and that is what makes the nine-channel question
/// non-trivial. With a single material every channel is the blend times a
/// constant, the nine are globally collinear, and a shared basis is free
/// by construction — which would be a fixture that could only agree with
/// the hypothesis. Split, the material changes across the sheet while the
/// GEOMETRY does not, so a kernel spanning the seam has to carry two
/// different constants on the same Gaussian and the sharing has somewhere
/// to actually cost something.
///
/// The ranges are the real marble's: emissive reaches 6 where the blend
/// reaches 1, which is what makes per-channel normalisation necessary
/// rather than tidy.
const SHEET_MATERIALS = [2]bark.Material{
    .{ .albedo = .{ 0.16, 0.17, 0.19 }, .roughness = 0.62, .metallic = 0.1, .emissive = .{ 0, 0, 0 } },
    .{ .albedo = .{ 0.55, 0.15, 0.05 }, .roughness = 0.35, .metallic = 0, .emissive = .{ 6, 2.5, 0.7 } },
};

pub fn sheetVolume(gpa: std.mem.Allocator, res: u32, extent: f32, columns: bark.Columns) !bark.Volume {
    const cell = extent / @as(f32, @floatFromInt(res));
    const stride = bark.strideOf(columns);
    var v = bark.Volume{
        .res = res,
        .extent = extent,
        .columns = columns,
        .stride = stride,
        .data = try gpa.alloc(f32, @as(usize, res) * res * res * stride),
        .hash = [_]u8{0} ** 32,
        .min = 0,
        .max = 0,
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
                const f = sheetPhi(extent, p);
                const rec = v.data[v.index(i, j, k)..][0..stride];
                rec[0] = f;
                if (columns != 0) {
                    const m = SHEET_MATERIALS[if (p[0] < extent * 0.5) 0 else 1];
                    rec[1..4].* = m.albedo;
                    rec[4] = m.roughness;
                    rec[5] = m.metallic;
                    rec[6..9].* = m.emissive;
                }
                lo = @min(lo, f);
                hi = @max(hi, f);
            }
        }
    }
    v.min = lo;
    v.max = hi;
    return v;
}

// ── The bridge ───────────────────────────────────────────────────────

/// The target MARL learns: the vein's blend, and nothing else.
/// `rbf.target(vol, vein, q)[0]`, called through `rbf` itself so the two
/// sides cannot drift apart by one being reimplemented.
pub fn blendAt(vol: *const bark.Volume, vein: f32, q: [3]f32) f32 {
    return rbf.target(vol, vein, q)[0];
}

/// A MARL model on the unit cube, carried into a volume's units as a
/// one-channel `rbf.Set`.
///
/// μ′ = Eμ and L′ = L/E. Exact in f32 for a power-of-two E, and the READ
/// is exact too: (q/E − μ) and (q − Eμ)/E round to the same float, because
/// rounding a difference commutes with scaling by a power of two. So
/// `set.eval(Ex)[0]` is `model.predictAll(x)` BIT FOR BIT.
///
/// The kernels are written in `predictAll`'s own order — region by region,
/// then each region's own list — and not in `model.kernels` order, because
/// float addition does not commute and a set built in a different order
/// would be right to an ulp instead of right.
pub fn setOf(gpa: std.mem.Allocator, model: anytype, extent: f32, columns: bark.Columns, hash: [32]u8, scale: rbf.Channels) !rbf.Set {
    // The model's channel count comes off its TYPE, so one function serves
    // `Marl(1)` and `Marl(9)` and a caller cannot pass the wrong number.
    const C = @TypeOf(model.*).CHANNELS;
    comptime std.debug.assert(C <= rbf.CHANNELS);
    var ks = try std.ArrayListUnmanaged(rbf.Kernel).initCapacity(gpa, model.kernels.items.len);
    errdefer ks.deinit(gpa);
    const inv = 1 / extent;
    for (model.regions) |*reg| {
        for (reg.own.items) |ki| {
            const k = &model.kernels.items[ki];
            const s = k.shape();
            var w: rbf.Channels = [_]f32{0} ** rbf.CHANNELS;
            // Scaled back out of the normalised units the model learned in,
            // exactly as `rbf.fit` does at the end of its own descent. At a
            // scale of one this is a multiply by 1.0, which is exact — so
            // G31 (a)'s bit equality survives the widening untouched.
            const kw = k.weightsConst();
            inline for (0..C) |c| w[c] = kw[c] * scale[c];
            ks.appendAssumeCapacity(.{
                .mu = .{ s.mu[0] * extent, s.mu[1] * extent, s.mu[2] * extent },
                .l = .{ s.l[0] * inv, s.l[1] * inv, s.l[2] * inv, s.l[3] * inv, s.l[4] * inv, s.l[5] * inv },
                .w = w,
            });
        }
    }
    return .{ .extent = extent, .columns = columns, .kernels = try ks.toOwnedSlice(gpa), .hash = hash };
}

// ── The exemplar stream ──────────────────────────────────────────────

/// Where the veins are, as voxel indices — the oracle, held in one place
/// so both sides of the comparison draw from the identical list.
pub const Veins = struct {
    idx: std.ArrayListUnmanaged(u32) = .{},
    /// The birth-eligible fraction of the cube: voxels whose blend clears
    /// MARL's surprise threshold. The denominator of every concentration
    /// number, MEASURED from the fixture rather than assumed — the
    /// campaign has paid for a hard-coded volume once already.
    fraction: f32 = 0,

    pub fn deinit(self: *Veins, gpa: std.mem.Allocator) void {
        self.idx.deinit(gpa);
    }
};

pub fn veinsOf(gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, threshold: f32) !Veins {
    var v = Veins{};
    errdefer v.deinit(gpa);
    const count: usize = @as(usize, vol.res) * vol.res * vol.res;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (bark.veinBlend(vol.data[i * vol.stride], vein) > threshold) try v.idx.append(gpa, @intCast(i));
    }
    v.fraction = @as(f32, @floatFromInt(v.idx.items.len)) / @as(f32, @floatFromInt(count));
    return v;
}

/// One draw. With `veins` empty this is uniform over the cube; with it
/// populated, half the draws land in a vein voxel. `rbf.fit`'s own
/// `draw.point`, transcribed so that the two sides' streams have the same
/// shape — and transcribed rather than shared because `rbf`'s is a private
/// closure and exporting it would put a MARL convenience into a
/// cross-repo pinned file.
pub fn drawPoint(st: *rng.Stream, vol: *const bark.Volume, veins: []const u32, extent: f32, cell: f32) [3]f32 {
    if (veins.len > 0 and st.unit() < 0.5) {
        const vi = veins[st.below(@intCast(veins.len))];
        const i = vi % vol.res;
        const j = (vi / vol.res) % vol.res;
        const k = vi / (vol.res * vol.res);
        return .{
            (@as(f32, @floatFromInt(i)) + st.unit()) * cell,
            (@as(f32, @floatFromInt(j)) + st.unit()) * cell,
            (@as(f32, @floatFromInt(k)) + st.unit()) * cell,
        };
    }
    return .{ st.unit() * extent, st.unit() * extent, st.unit() * extent };
}

// ── The arms ─────────────────────────────────────────────────────────

pub const Arm = struct {
    /// The kernels the arm ended with. For MARL this is discovered; for
    /// rbf it is what it was told, which is what MARL discovered.
    kernels: u32 = 0,
    /// Held-out RMS of the blend, in the blend's own units, over probes
    /// drawn UNIFORMLY — what a random query costs.
    rms_uniform: f32 = 0,
    /// … and over probes drawn from the vein band — what the STRUCTURE
    /// costs. Reported apart because a uniform probe set on a field that
    /// is 9% vein is 91% a test of predicting zero, and both arms pass
    /// that trivially.
    rms_band: f32 = 0,
    /// The BLEND alone, on the band probes — channel 0, whatever the arm
    /// weighed. It is the one number a C = 1 arm and a C = 9 arm can be
    /// compared on directly, and the whole of MARL-12's sharing question
    /// is the ratio between two of them.
    rms_c0: f32 = 0,
    /// (kernels in the band / all kernels) ÷ (the band's volume fraction).
    /// One means a uniform allocator; 1/fraction means every kernel sits
    /// on structure.
    concentration: f32 = 0,
    /// Distinct exemplars the arm was shown.
    exemplars: u64 = 0,
    seconds: f64 = 0,
    /// MARL arms only: kernels born, and gradient steps taken.
    births: u64 = 0,
    updates: u64 = 0,
};

pub const Arms = struct {
    a: Arm = .{}, // rbf, both oracles — the shipped default
    b: Arm = .{}, // rbf, neither oracle
    c: Arm = .{}, // MARL, vein-biased stream
    d: Arm = .{}, // MARL, uniform stream
    /// The fixture's birth-eligible fraction, measured.
    fraction: f32 = 0,
    /// Channels the arms weighed.
    channels: usize = 1,
};

pub const ArmOptions = struct {
    /// Distinct exemplars — MARL's stream length AND rbf's pool, which is
    /// the whole point: the currency held equal is data, not work.
    pool: u32 = 32768,
    iterations: u32 = 600,
    batch: u32 = 256,
    probes: u32 = 4096,
    seed: u64 = 11,
    /// MARL's configuration. `responsibility = 3` is G24's recalibration,
    /// which the ledger says every phase from MARL-7 on should run at.
    m: marl.Options = .{ .responsibility = 3 },
    /// Report progress as the arms run — a tool's flag, never a gate's.
    verbose: bool = false,
    /// Learn NORMALISED targets, per-channel, and scale the weights back
    /// into the field's units at the end — `rbf.fit`'s own treatment.
    ///
    /// Off by default, and that is deliberate rather than lazy: at one
    /// channel the scale is the blend's own range and normalising moves
    /// nothing that gets measured, so leaving it off keeps every MARL-11
    /// number reproducible. At nine it is necessary — emissive reaches 6
    /// where the blend reaches 1, and an unnormalised learner spends its
    /// geometry on whichever channel happens to carry the largest units.
    normalise: bool = false,
};

/// A held-out probe set and its answers.
const Probes = struct {
    q: [][3]f32,
    /// All NINE channels at every probe, whatever the arm under test
    /// weighs. One probe set serves a C = 1 run and a C = 9 run, so the
    /// two are answering questions about the same points and the same
    /// draws — which is the only way `rms` at one channel count is
    /// comparable with `rms` at another.
    y: []rbf.Channels,

    fn deinit(self: *Probes, gpa: std.mem.Allocator) void {
        gpa.free(self.q);
        gpa.free(self.y);
    }
};

fn probesOf(gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, veins: []const u32, n: u32, seed: u64) !Probes {
    var st = rng.Stream.region(seed, 0x4d41_5242, 0);
    const cell = vol.extent / @as(f32, @floatFromInt(vol.res));
    var p = Probes{ .q = try gpa.alloc([3]f32, n), .y = try gpa.alloc(rbf.Channels, n) };
    errdefer p.deinit(gpa);
    for (p.q, p.y) |*q, *y| {
        q.* = drawPoint(&st, vol, veins, vol.extent, cell);
        y.* = rbf.target(vol, vein, q.*);
    }
    return p;
}

/// Held-out RMS over the first `C` channels, in the channels' own units.
/// Both learners are read through `rbf.Set.eval` — the same evaluator, the
/// same cutoff, the same summation order — so what is compared is the two
/// sets and not two ways of asking them.
fn rmsOfSet(comptime C: usize, set: *const rbf.Set, pr: Probes) f32 {
    var acc: f64 = 0;
    for (pr.q, pr.y) |q, y| {
        const yh = set.eval(q);
        inline for (0..C) |c| {
            const e = yh[c] - y[c];
            acc += @as(f64, e) * @as(f64, e);
        }
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.q.len * C))));
}

/// One channel of a set, on one probe set — `rmsOfSet` with C = 1 pinned
/// to a particular channel rather than to the first.
fn rmsOfChannel(set: *const rbf.Set, pr: Probes, comptime c: usize) f32 {
    var acc: f64 = 0;
    for (pr.q, pr.y) |q, y| {
        const e = set.eval(q)[c] - y[c];
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.q.len))));
}

/// Per-channel scale: the largest magnitude the channel reaches over a
/// draw from the field, floored so a channel the archetype does not model
/// cannot divide by zero. `rbf.fit`'s own, transcribed — it normalises its
/// targets this way and scales the weights back at the end.
///
/// It matters far more at nine channels than at one: emissive reaches 6
/// where the blend reaches 1, so an unnormalised fit spends its geometry
/// on whichever channel happens to have the largest units. At C = 1 the
/// scale is the blend's own range and normalising changes nothing that is
/// measured, which is why `ArmOptions.normalise` defaults OFF and the
/// campaign's C = 1 numbers do not move.
fn scalesOf(vol: *const bark.Volume, vein: f32, veins: []const u32, n: u32, seed: u64) rbf.Channels {
    var st = rng.Stream.region(seed, 0x5343_414c, 0); // "SCAL"
    const cell = vol.extent / @as(f32, @floatFromInt(vol.res));
    var scale: rbf.Channels = [_]f32{1e-3} ** rbf.CHANNELS;
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const y = rbf.target(vol, vein, drawPoint(&st, vol, veins, vol.extent, cell));
        inline for (0..rbf.CHANNELS) |c| scale[c] = @max(scale[c], @abs(y[c]));
    }
    return scale;
}

/// The fraction of a set's kernels whose CENTRE sits where the blend
/// clears MARL's surprise threshold — the numerator of concentration. A
/// centre and not a support: support asks where a kernel can be felt,
/// which every kernel large enough answers yes to; the question here is
/// where the model chose to spend.
fn bandShare(set: *const rbf.Set, vol: *const bark.Volume, vein: f32, threshold: f32) f32 {
    if (set.kernels.len == 0) return 0;
    var in: u32 = 0;
    for (set.kernels) |k| {
        if (blendAt(vol, vein, rbf.Set.fold(set.extent, k.mu)) > threshold) in += 1;
    }
    return @as(f32, @floatFromInt(in)) / @as(f32, @floatFromInt(set.kernels.len));
}

/// One MARL arm: `pool` distinct exemplars, drawn uniformly or vein-biased,
/// each observed exactly once and never again.
fn marlArm(comptime C: usize, gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, veins: []const u32, o: ArmOptions, uni: Probes, band: Probes, fraction: f32) !struct { arm: Arm, set: rbf.Set } {
    var model = try marl.Marl(C).Model.init(gpa, o.m);
    defer model.deinit();
    var st = rng.Stream.region(o.seed, 0x4d41_524c, 0);
    const cell = vol.extent / @as(f32, @floatFromInt(vol.res));
    const inv = 1 / vol.extent;
    const one: rbf.Channels = [_]f32{1} ** rbf.CHANNELS;
    const scale = if (o.normalise) scalesOf(vol, vein, veins, o.pool, o.seed) else one;
    var timer = try std.time.Timer.start();
    var n: u32 = 0;
    while (n < o.pool) : (n += 1) {
        const q = drawPoint(&st, vol, veins, vol.extent, cell);
        const t = rbf.target(vol, vein, q);
        var y: [C]f32 = undefined;
        inline for (0..C) |c| y[c] = t[c] / scale[c];
        _ = try model.observe(.{ q[0] * inv, q[1] * inv, q[2] * inv }, y);
    }
    const secs = @as(f64, @floatFromInt(timer.read())) / 1e9;
    var set = try setOf(gpa, &model, vol.extent, vol.columns, vol.hash, scale);
    errdefer set.deinit(gpa);
    return .{ .arm = .{
        .kernels = @intCast(model.kernels.items.len),
        .rms_uniform = rmsOfSet(C, &set, uni),
        .rms_band = rmsOfSet(C, &set, band),
        .rms_c0 = rmsOfChannel(&set, band, 0),
        .concentration = bandShare(&set, vol, vein, o.m.threshold) / @max(1e-6, fraction),
        .exemplars = o.pool,
        .seconds = secs,
        .births = model.stats.births,
        .updates = model.stats.updates,
    }, .set = set };
}

/// One rbf arm, at a kernel count MARL discovered.
fn rbfArm(comptime C: usize, gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, o: ArmOptions, kernels: u32, oracle: bool, uni: Probes, band: Probes, fraction: f32) !Arm {
    var timer = try std.time.Timer.start();
    var fitted = try rbf.fit(gpa, vol, vein, .{
        .kernels = kernels,
        .iterations = o.iterations,
        .batch = o.batch,
        .pool = o.pool,
        .held_out = 64, // rbf's own report is unused; ours is the shared probe set
        .seed = o.seed,
        .vein_pool = oracle,
        .vein_seed = oracle,
    });
    defer fitted.set.deinit(gpa);
    const secs = @as(f64, @floatFromInt(timer.read())) / 1e9;
    return .{
        .kernels = @intCast(fitted.set.kernels.len),
        .rms_uniform = rmsOfSet(C, &fitted.set, uni),
        .rms_band = rmsOfSet(C, &fitted.set, band),
        .rms_c0 = rmsOfChannel(&fitted.set, band, 0),
        .concentration = bandShare(&fitted.set, vol, vein, o.m.threshold) / @max(1e-6, fraction),
        .exemplars = o.pool,
        .seconds = secs,
    };
}

/// Arm D alone, at whatever stream length `o.pool` names — the evidence
/// gradient, for reading a result rather than gating one. It builds its own
/// probe sets so a caller can sweep the stream without carrying the rest of
/// the 2×2 along.
pub fn blindArm(comptime C: usize, gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, o: ArmOptions) !Arm {
    var veins = try veinsOf(gpa, vol, vein, o.m.threshold);
    defer veins.deinit(gpa);
    var uni = try probesOf(gpa, vol, vein, &.{}, o.probes, o.seed ^ 0x9e37);
    defer uni.deinit(gpa);
    var band = try probesOf(gpa, vol, vein, veins.idx.items, o.probes, o.seed ^ 0x517c);
    defer band.deinit(gpa);
    var r = try marlArm(C, gpa, vol, vein, &.{}, o, uni, band, veins.fraction);
    r.set.deinit(gpa);
    return r.arm;
}

/// The 2×2, run in the order that lets capacity be matched: both MARL arms
/// first, then each rbf arm at the count the MARL arm beside it
/// discovered.
pub fn run(comptime C: usize, gpa: std.mem.Allocator, vol: *const bark.Volume, vein: f32, o: ArmOptions) !Arms {
    var veins = try veinsOf(gpa, vol, vein, o.m.threshold);
    defer veins.deinit(gpa);

    var uni = try probesOf(gpa, vol, vein, &.{}, o.probes, o.seed ^ 0x9e37);
    defer uni.deinit(gpa);
    var band = try probesOf(gpa, vol, vein, veins.idx.items, o.probes, o.seed ^ 0x517c);
    defer band.deinit(gpa);

    var out = Arms{ .fraction = veins.fraction, .channels = C };

    var d = try marlArm(C, gpa, vol, vein, &.{}, o, uni, band, veins.fraction);
    d.set.deinit(gpa);
    out.d = d.arm;
    if (o.verbose) std.debug.print("  D  MARL, uniform          {d:>5} kernels\n", .{out.d.kernels});

    var c = try marlArm(C, gpa, vol, vein, veins.idx.items, o, uni, band, veins.fraction);
    c.set.deinit(gpa);
    out.c = c.arm;
    if (o.verbose) std.debug.print("  C  MARL, vein-biased      {d:>5} kernels\n", .{out.c.kernels});

    out.b = try rbfArm(C, gpa, vol, vein, o, out.d.kernels, false, uni, band, veins.fraction);
    if (o.verbose) std.debug.print("  B  rbf, no oracle         {d:>5} kernels\n", .{out.b.kernels});
    out.a = try rbfArm(C, gpa, vol, vein, o, out.c.kernels, true, uni, band, veins.fraction);
    if (o.verbose) std.debug.print("  A  rbf, both oracles      {d:>5} kernels\n", .{out.a.kernels});

    return out;
}

/// The table, for a tool run and for a gate that wants its numbers in the
/// transcript.
pub fn report(w: anytype, arms: Arms) !void {
    // Concentration is reported BOTH raw and as a fraction of its own
    // ceiling, because the ceiling is 1/f and f is a property of the
    // field. The gate's fixture is 9.4% structure and the real marble is
    // 27.6%, so a raw 4.17 there and a raw 1.88 here are 0.39 and 0.52 of
    // what was available — the same allocator doing BETTER on the harder
    // field, which the raw numbers say the opposite of. Comparing raw
    // concentration across two fields is the mistake this column exists
    // to stop.
    const ceil = 1 / @max(1e-6, arms.fraction);
    try w.print("\n  arm  {s:<26} {s:>7} {s:>10} {s:>10} {s:>10} {s:>7} {s:>7} {s:>8}\n", .{ "learner", "kernels", "RMS band", "RMS blend", "RMS unif", "conc.", "/ceil", "seconds" });
    const rows = [_]struct { n: []const u8, l: []const u8, a: Arm }{
        .{ .n = "A", .l = "rbf, batch Adam, oracle", .a = arms.a },
        .{ .n = "B", .l = "rbf, batch Adam, blind", .a = arms.b },
        .{ .n = "C", .l = "MARL, online NLMS, oracle", .a = arms.c },
        .{ .n = "D", .l = "MARL, online NLMS, blind", .a = arms.d },
    };
    for (rows) |r| {
        try w.print("  {s:<4} {s:<26} {d:>7} {d:>10.5} {d:>10.5} {d:>10.5} {d:>7.2} {d:>7.2} {d:>8.2}\n", .{ r.n, r.l, r.a.kernels, r.a.rms_band, r.a.rms_c0, r.a.rms_uniform, r.a.concentration, r.a.concentration / ceil, r.a.seconds });
    }
    try w.print("\n  {d} channel(s); the band is {d:.4} of the cube, so concentration's ceiling is {d:.2}\n", .{ arms.channels, arms.fraction, 1 / @max(1e-6, arms.fraction) });
    try w.print("  a kernel is {d} floats here against {d} for {d} separate scalar models\n", .{ 9 + arms.channels, arms.channels * 10, arms.channels });
    try w.print("  B/A {d:.3}  the seed and pool oracles, priced\n", .{arms.b.rms_band / arms.a.rms_band});
    try w.print("  D/B {d:.3}  discovery against seeding, neither side told\n", .{arms.d.rms_band / arms.b.rms_band});
    try w.print("  C/A {d:.3}  online against batch, the oracle held equal\n", .{arms.c.rms_band / arms.a.rms_band});
    // The column nobody pre-registered and everybody will want: what the
    // two learners cost to run. Not a gate — a wall clock is a property of
    // this machine — but the ratio is three orders of magnitude wide and
    // that is not a machine's doing.
    try w.print("  MARL is {d:.0}x faster than the batch fit at the same kernel count ({d:.2} s against {d:.2} s)\n", .{ arms.b.seconds / @max(1e-6, arms.d.seconds), arms.d.seconds, arms.b.seconds });
}

// ── Gates ────────────────────────────────────────────────────────────

const testing = std.testing;

// ── MARL-11's gates ───────────────────────────────────────────────────
//
// From `tools/marl11_predict.py`. Two of the four pre-registered numbers
// HELD and two were REFUTED; the refuted pair is left standing in
// `thresholds.zig` with what it measured, and is NOT asserted here —
// asserting a number that has already been refuted, against the value that
// refuted it, is the first result becoming the threshold. What G31 (b)
// asserts in their place is the MECHANISM the refutation established, in
// relations rather than magnitudes.

test "G31 (a) a MARL model carried into a volume's units IS an rbf set, bit for bit" {
    const gpa = testing.allocator;
    var vol = try sheetVolume(gpa, FIXTURE_RES, FIXTURE_EXTENT, 0);
    defer vol.deinit(gpa);
    var veins = try veinsOf(gpa, &vol, FIXTURE_VEIN, 0.02);
    defer veins.deinit(gpa);

    var model = try marl.Model.init(gpa, .{ .responsibility = 3 });
    defer model.deinit();
    var st = rng.Stream.region(3, 0x4d41_524c, 0);
    const cell = vol.extent / @as(f32, @floatFromInt(vol.res));
    const inv = 1 / vol.extent;
    var n: u32 = 0;
    while (n < 8000) : (n += 1) {
        const q = drawPoint(&st, &vol, veins.idx.items, vol.extent, cell);
        _ = try model.observe(.{ q[0] * inv, q[1] * inv, q[2] * inv }, .{blendAt(&vol, FIXTURE_VEIN, q)});
    }
    try testing.expect(model.kernels.items.len > 16);

    var set = try setOf(gpa, &model, vol.extent, vol.columns, vol.hash, [_]f32{1} ** rbf.CHANNELS);
    defer set.deinit(gpa);
    try testing.expectEqual(model.kernels.items.len, set.kernels.len);

    // Every probe, bitwise. Not an epsilon: the claim is that the online
    // learner's output IS the asset a renderer loads, and an epsilon lets
    // two implementations of one model drift in the last places until a
    // host that swaps one for the other shows something else.
    var probes = try probesOf(gpa, &vol, FIXTURE_VEIN, veins.idx.items, 1024, 5);
    defer probes.deinit(gpa);
    var checked: u32 = 0;
    for (probes.q) |q| {
        const there = model.predictAll(.{ q[0] * inv, q[1] * inv, q[2] * inv })[0];
        const here = set.eval(q)[0];
        if (@as(u32, @bitCast(there)) != @as(u32, @bitCast(here))) {
            std.debug.print("marble: at ({d:.4},{d:.4},{d:.4}) the model says 0x{x:0>8} and the set says 0x{x:0>8}\n", .{ q[0], q[1], q[2], @as(u32, @bitCast(there)), @as(u32, @bitCast(here)) });
            return error.TestUnexpectedResult;
        }
        checked += 1;
    }
    std.debug.print("\n  marble: {d} kernels carried to extent {d:.0}, {d} probes bit-identical through rbf.Set.eval ({s})\n", .{ set.kernels.len, vol.extent, checked, @tagName(builtin.mode) });

    // The mutation: an extent that is NOT a power of two. The conversion
    // is still mathematically exact and the reads still agree to an ulp
    // or so — which is precisely why the gate is bitwise. If this ever
    // stops disagreeing, the gate has stopped testing the rounding
    // argument and is only testing that the algebra was transcribed.
    var odd = try setOf(gpa, &model, 40, vol.columns, vol.hash, [_]f32{1} ** rbf.CHANNELS);
    defer odd.deinit(gpa);
    var differed: u32 = 0;
    for (probes.q) |q| {
        const x = [3]f32{ q[0] * inv, q[1] * inv, q[2] * inv };
        const there = model.predictAll(x)[0];
        const here = odd.eval(.{ x[0] * 40, x[1] * 40, x[2] * 40 })[0];
        if (@as(u32, @bitCast(there)) != @as(u32, @bitCast(here))) differed += 1;
    }
    try testing.expect(differed > 0);
}

test "G31 (a) the fixture is the sheet the predictor measured, and the volume reads it back" {
    const gpa = testing.allocator;
    var vol = try sheetVolume(gpa, FIXTURE_RES, FIXTURE_EXTENT, 0);
    defer vol.deinit(gpa);
    var veins = try veinsOf(gpa, &vol, FIXTURE_VEIN, 0.02);
    defer veins.deinit(gpa);
    // `tools/marl11_predict.py` measured 0.0938 of the cube birth-eligible
    // on this grid, and every MARL-11 threshold is derived from it.
    try testing.expectApproxEqAbs(@as(f32, 0.0938), veins.fraction, 0.002);
    // The matrix is EXACTLY zero, which is the whole reason MARL spends
    // nothing there: an empty model predicts zero and is not surprised.
    try testing.expectEqual(@as(f32, 0), blendAt(&vol, FIXTURE_VEIN, .{ 1, 1, 1 }));
    // And the sheet is a sheet: crossing it in z passes through the band.
    //
    // The peak is 0.874 and NOT 1, and that is the fixture being honest
    // rather than the fixture being wrong. A cell here is 1.0 against a
    // half-thickness of 0.9, so the voxel centres straddling the sheet
    // hold φ = 0.4 and the trilinear read never sees the 0.9 the analytic
    // field has at the middle. The real marble is baked at the same
    // fidelity — 64³ over an extent of 40 is a cell of 0.625 against a
    // softness of 0.9 — so a fixture that resolved its own structure
    // perfectly would be the easier problem, not the representative one.
    // This is also why `blend = 1` is 1% of the cube by the predictor's
    // analytic measure and 0% of it through the volume.
    var seen: f32 = 0;
    var t: f32 = 0;
    while (t < FIXTURE_EXTENT) : (t += 0.25) seen = @max(seen, blendAt(&vol, FIXTURE_VEIN, .{ 16, 16, t }));
    std.debug.print("\n  marble: the fixture is {d:.4} of the cube birth-eligible (the predictor said 0.0938); crossing the sheet peaks at blend {d:.3}, not 1, because a cell is {d:.2} against a half-thickness of {d:.2}\n", .{ veins.fraction, seen, FIXTURE_EXTENT / @as(f32, @floatFromInt(FIXTURE_RES)), HALF_THICK });
    try testing.expect(seen > 0.8);
}

test "G31 (b) MARL places capacity where a blind batch optimiser cannot, and still loses to it on accuracy" {
    // THE PHASE, and the campaign's first comparison against something it
    // did not write. Four arms, one variable a cell, capacity matched
    // exactly and distinct data held equal:
    //
    //   A  rbf  batch Adam, seeded on veins, half its pool drawn from them
    //   B  rbf  batch Adam, seeded and sampled uniformly
    //   C  MARL online NLMS, the same vein-biased stream as A
    //   D  MARL online NLMS, a uniform stream
    //
    // What HELD. Capacity concentration, predicted at 4.11 from the
    // fixture's geometry and measured at 4.17 — the campaign's quiet-slab
    // result transferring to a field nobody designed to have one, because
    // a real matrix is EXACTLY zero, an empty model predicts EXACTLY zero,
    // and surprise below θ produces no birth. And C/A, the price of being
    // online with the evidence held equal, inside its ceiling of 2.
    //
    // What was REFUTED. D/B, pre-registered as a CEILING at parity and
    // measured at 1.95: MARL loses to blind batch Adam by nearly two,
    // at matched capacity and equal data. The campaign predicted a win
    // from MARL-3 (a birth cannot land where the field is already right)
    // and from the hard cutoff making a badly seeded kernel dead on
    // arrival. Both of those are TRUE — concentration 4.17 against 1.33
    // says MARL placed its capacity three times better — and the win did
    // not follow from them. Placement was never the binding constraint.
    // G31 (c) is where what the binding constraint actually is gets
    // measured.
    //
    // MUTATION: hand arm D the vein-biased stream (that is arm C, run
    // here). RMS falls 0.143 → 0.083 and concentration rises 4.2 → 5.9, so
    // the gate varies on the axis it claims to measure. The second
    // mutation is the oracle on the rbf side, which is arms A against B.
    const gpa = testing.allocator;
    var vol = try sheetVolume(gpa, FIXTURE_RES, FIXTURE_EXTENT, 0);
    defer vol.deinit(gpa);
    const out = try run(1, gpa, &vol, FIXTURE_VEIN, .{});

    try report(std.io.getStdErr().writer(), out);

    // Capacity is matched, which is what makes any of the rest a
    // comparison at all (MARL-1: at unequal capacity the number measures
    // the capacity).
    try testing.expectEqual(out.d.kernels, out.b.kernels);
    try testing.expectEqual(out.c.kernels, out.a.kernels);

    // HELD: the blind learner concentrates capacity on structure.
    try testing.expect(out.d.concentration >= thresholds.MARL11_CONCENTRATION);
    // HELD: online costs less than the pre-registered ceiling against
    // batch, once both are given the same evidence.
    try testing.expect(out.c.rms_band / out.a.rms_band <= thresholds.MARL11_ONLINE_COST);

    // The premise of the 2x2: the oracle is a real variable on BOTH sides,
    // or arms C and D are the same test and there is nothing here.
    // Direction only — the magnitude is MARL11_ORACLE_WORTH's business and
    // that number was refuted.
    try testing.expect(out.a.rms_band < out.b.rms_band);
    try testing.expect(out.c.rms_band < out.d.rms_band);

    // The finding, as a relation rather than a magnitude: MARL blind
    // places capacity where rbf blind cannot, by a wide margin, because
    // rbf's uniformly seeded kernels land in a matrix where the gaussian
    // is a HARD zero and Adam can never move a centre it has not touched.
    try testing.expect(out.d.concentration > out.b.concentration * 2);
    // …and loses anyway. This assertion fires if MARL ever wins, which is
    // the notification wanted: the phase's conclusion would have changed
    // and the ledger would be wrong.
    try testing.expect(out.d.rms_band > out.b.rms_band);
}

test "G31 (c) the gap to batch Adam is EVIDENCE, not placement: it closes with the stream and the placement never moves" {
    // Written AFTER G31 (b) refuted the headline, and it is a diagnostic
    // rather than a pre-registration — so what it asserts is DIRECTION,
    // derived from a prior finding, and no magnitude at all.
    //
    // The prior finding is MARL-6R's: under-EVIDENCE is a smooth gradient
    // and not a cliff. If MARL's loss in G31 (b) were a placement or a
    // representation limit, more of the same stream would not help and the
    // RMS would flatten. If it is evidence, the RMS falls and CONCENTRATION
    // — which is a geometric property of where births are allowed to land —
    // stays where it is.
    //
    // Measured over the full sweep, past what this gate can afford:
    //     32 768 exemplars  RMS 0.14255  conc 4.17  1 583 kernels
    //    131 072            RMS 0.09237  conc 3.63  2 403
    //    524 288            RMS 0.06492  conc 3.61  2 928
    //  2 097 152            RMS 0.05145  conc 3.75  3 285
    // The RMS falls by 2.8x and crosses BOTH rbf arms — blind (0.0732)
    // between the second and third rows, and the ORACLE arm (0.0546) by
    // the fourth. The concentration does not move. So the online learner
    // is not a worse fitter than batch Adam; it is a hungrier one, and it
    // buys kernels rather than passes to get there — 3 285 against 1 583
    // for the same field.
    //
    // MUTATION: assert the concentration MOVES rather than holds. It does
    // not (4.17 → 3.75 over a 64-fold stream), which is the half of the
    // claim that says the extra data is being spent on fitting the
    // capacity rather than on placing more of it.
    const gpa = testing.allocator;
    var vol = try sheetVolume(gpa, FIXTURE_RES, FIXTURE_EXTENT, 0);
    defer vol.deinit(gpa);
    const base = ArmOptions{};
    const one = try blindArm(1, gpa, &vol, FIXTURE_VEIN, base);
    var four_o = base;
    four_o.pool = base.pool * 4;
    const four = try blindArm(1, gpa, &vol, FIXTURE_VEIN, four_o);
    std.debug.print("  G31 (c): {d} exemplars RMS {d:.5} conc {d:.2} ({d} kernels) → {d} exemplars RMS {d:.5} conc {d:.2} ({d} kernels) ({s})\n", .{
        one.exemplars,  one.rms_band,  one.concentration,  one.kernels,
        four.exemplars, four.rms_band, four.concentration, four.kernels,
        @tagName(builtin.mode),
    });
    // Evidence-limited, not placement-limited: the error falls…
    try testing.expect(four.rms_band < one.rms_band);
    // …while the placement does not improve, so the fall is not more
    // capacity landing in better places.
    try testing.expect(four.concentration <= one.concentration);
    // And it is still concentrating far above a uniform allocator, so the
    // extra kernels are not being sprayed over the matrix.
    try testing.expect(four.concentration >= thresholds.MARL11_CONCENTRATION);
}

// ── MARL-12's gates ───────────────────────────────────────────────────
//
// From `tools/marl12_predict.py`. The widening's own gate is not here and
// is not a threshold: at C = 1 every number from G17 to G31 must be
// IDENTICAL, checked by diffing the suite against the commit before it.
// G31 (a) carries the sharpest form of it — the same 975 kernels, the same
// 1024 probes, still bit-for-bit equal through `rbf.Set.eval`.

test "G32 nine channels on one geometry cost no extra kernels and no accuracy — once the geometry's step is corrected for the channel count" {
    // THE POINT OF THE WIDENING. `rbf.fit` has always fitted nine channels
    // sharing one centre and one shape; that sharing is the whole reason a
    // packed set beats a volume texture, and the campaign could not test
    // it while a kernel carried one weight.
    //
    // The fixture carries TWO materials split across x. With one material
    // every channel is the blend times a constant, the nine are exactly
    // collinear, and a shared basis is free BY CONSTRUCTION — a fixture
    // that can only agree is not a fixture. Split, the material changes
    // while the geometry does not, so a kernel spanning the seam has to
    // put two different constants on one Gaussian.
    //
    // What the first run found, at the C = 1 geometry rate: DIVERGENCE, in
    // exactly MARL-1's shape. The vein-biased arm births 3 666 kernels
    // against the uniform arm's 1 896 and scores worse with them (0.629
    // against 0.352) — more capacity, less accuracy, which is the
    // over-capacity-under-evidence signature. The cause is that the
    // geometry descends on `Σ_c w_c a_c`, one term per channel, and that
    // sum grows as √C. `Ch.GEOM_RATE` is the correction and this gate is
    // what it was paid for.
    const gpa = testing.allocator;
    var vol = try sheetVolume(gpa, FIXTURE_RES, FIXTURE_EXTENT, bark.ALL_COLUMNS);
    defer vol.deinit(gpa);

    var o = ArmOptions{};
    const c1 = try blindArm(1, gpa, &vol, FIXTURE_VEIN, o);
    o.normalise = true; // emissive reaches 6 where the blend reaches 1
    const c9 = try blindArm(9, gpa, &vol, FIXTURE_VEIN, o);

    const count = @as(f32, @floatFromInt(c9.kernels)) / @as(f32, @floatFromInt(c1.kernels));
    const sharing = c9.rms_c0 / c1.rms_c0;
    std.debug.print("\n  G32: one channel {d} kernels, blend RMS {d:.5}; nine channels {d} kernels, blend RMS {d:.5} — count {d:.3} (≤ {d:.2}), sharing {d:.3} (≤ {d:.2}); {d} floats a kernel against {d} for nine scalar models ({s})\n", .{
        c1.kernels, c1.rms_c0, c9.kernels, c9.rms_c0,
        count,      thresholds.MARL12_COUNT,
        sharing,    thresholds.MARL12_SHARING,
        9 + @as(usize, 9), 9 * 10, @tagName(builtin.mode),
    });

    // The geometry is paid for ONCE: nine channels buy no extra kernels,
    // because a birth is gated by COVERAGE and coverage is a max over
    // gaussians that knows nothing about channels.
    try testing.expect(count <= thresholds.MARL12_COUNT);
    // And the blend does not get worse for having eight passengers.
    try testing.expect(sharing <= thresholds.MARL12_SHARING);
    // The saving, as arithmetic rather than as a bound: a kernel is
    // 9 + C floats where C separate scalar models are C × (9 + 1).
    try testing.expectEqual(@as(usize, 18), 9 + marl.Marl(9).CHANNELS);
    try testing.expectEqual(@as(usize, 90), 9 * (9 + marl.Marl(1).CHANNELS));

    // MUTATION, executable: undo the √C correction by scaling `rate_geom`
    // back up by √9. That is the exact step the first run took, and it
    // must fail this gate — if it does not, `GEOM_RATE` is decoration and
    // the divergence above had some other cause.
    var bad = o;
    bad.m.rate_geom = o.m.rate_geom * 3;
    const un = try blindArm(9, gpa, &vol, FIXTURE_VEIN, bad);
    std.debug.print("  G32 mutation, the correction undone: {d} kernels, blend RMS {d:.5} — {d:.2}× the corrected run's\n", .{ un.kernels, un.rms_c0, un.rms_c0 / c9.rms_c0 });
    try testing.expect(un.rms_c0 / c1.rms_c0 > thresholds.MARL12_SHARING);
}
