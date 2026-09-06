//! operators — local operators over regions (spec §5.3, §9, §10).
//!
//! An operator declares what it reads and writes, and `evaluate`s one
//! region at a time — a whole brick per call, never a sample: batch-shaped
//! so the hot path has no per-sample dispatch. It reads the step-start
//! snapshot (its own brick directly, neighbours through the context, which
//! crosses seams by reconstruction) and writes deltas into the region's
//! update entry. It never sees another region's entry.
//!
//! The standard set here is the three with closed-form checks the brief
//! asks for first — Diffusion, Decay, Advection — and Healing, which
//! needs a front to act on and so waits for P1.4. Inhibition is a front
//! rule (`world.zig`, `canGrow` and the avoid-self gradient term): it
//! suppresses growth near occupied tissue, which is what §10 says it
//! does, and a front is the only thing that grows.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");
const front = @import("front.zig");
const update = @import("update.zig");
const thresholds = @import("thresholds.zig");
const fmath = @import("fmath.zig");

const Key = lattice.Key;
const Brick = brick.Brick;
const Plane = brick.Plane;
const Channel = channel.Channel;
const Mask = channel.Mask;
const N = brick.N;
const HN = brick.HN;

/// What an operator sees of one region.
pub const RegionContext = struct {
    snapshot: *const tree.Snapshot,
    brick: *const Brick,
    dt: f64,
    epoch: u64,
    /// Fed time of this step, seconds — what a touch time is read against.
    time_s: f32,
    seed: u64,
    alloc: std.mem.Allocator,
    registry: *const channel.Registry,
    /// Live, non-dormant fronts whose brick this is.
    fronts_here: u32,
    /// Stability clamps applied this evaluation — the seedbed prints it.
    clamped: u64 = 0,

    /// Value at a lattice point: this brick's own sample when it is one,
    /// else the holder's sample there, or the coarse interpolant where
    /// the point is off the holder's lattice (the absent value in the
    /// void). Samples, not the spline: a stencil reaches across seams
    /// through this and must see coefficients, or diffusion would not
    /// conserve mass.
    pub fn at(self: *const RegionContext, bit: u6, p: [3]i64) f32 {
        if (self.brick.localOf(p)) |l| return self.brick.get(bit, l[0], l[1], l[2]);
        const b = self.snapshot.findLeaf(p) orelse return self.brick.absentValue(bit);
        if (b.localOf(p)) |l| return b.get(bit, l[0], l[1], l[2]);
        return b.trilinear(bit, .{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) });
    }

    /// Continuous sample: this brick when inside it, else the snapshot.
    pub fn sample(self: *const RegionContext, bit: u6, q: [3]f64) f32 {
        const pi = [3]i64{ tree.floorI(q[0]), tree.floorI(q[1]), tree.floorI(q[2]) };
        if (self.brick.key.holdsPoint(pi) and self.brick.key.holdsPoint(.{ pi[0] + 1, pi[1] + 1, pi[2] + 1 })) return self.brick.spline(bit, q);
        return self.snapshot.sample(bit, q);
    }
};

pub const VTable = struct {
    name: []const u8,
    reads: *const fn (*anyopaque) Mask,
    writes: *const fn (*anyopaque) Mask,
    evaluate: *const fn (*anyopaque, *RegionContext, *update.RegionUpdate) anyerror!void,
};

pub const Operator = struct {
    ptr: *anyopaque,
    vt: *const VTable,

    pub fn name(self: Operator) []const u8 {
        return self.vt.name;
    }
    pub fn reads(self: Operator) Mask {
        return self.vt.reads(self.ptr);
    }
    pub fn writes(self: Operator) Mask {
        return self.vt.writes(self.ptr);
    }
    pub fn evaluate(self: Operator, ctx: *RegionContext, out: *update.RegionUpdate) !void {
        return self.vt.evaluate(self.ptr, ctx, out);
    }
};

/// Adapter: any struct with `reads/writes/evaluate` methods and a NAME.
pub fn operatorOf(comptime T: type, self: *T) Operator {
    const gen = struct {
        fn reads(p: *anyopaque) Mask {
            const s: *T = @ptrCast(@alignCast(p));
            return s.reads();
        }
        fn writes(p: *anyopaque) Mask {
            const s: *T = @ptrCast(@alignCast(p));
            return s.writes();
        }
        fn evaluate(p: *anyopaque, ctx: *RegionContext, out: *update.RegionUpdate) anyerror!void {
            const s: *T = @ptrCast(@alignCast(p));
            return s.evaluate(ctx, out);
        }
        const vt = VTable{ .name = T.NAME, .reads = reads, .writes = writes, .evaluate = evaluate };
    };
    return .{ .ptr = self, .vt = &gen.vt };
}

// ── Diffusion ────────────────────────────────────────────────────────────

/// ∂v/∂t = rate ∇²v, explicit, 6-point stencil. `rate` in lattice
/// units² per second. Explicit stability wants rate·dt/h² ≤ 1/6; the
/// coefficient is clamped there and the clamp is COUNTED, never silent.
/// Closed form: a point mass spreads to a Gaussian of variance 2·rate·t
/// per axis, total mass conserved.
pub const Diffusion = struct {
    pub const NAME = "diffusion";
    bit: u6,
    rate: f32,

    pub fn reads(self: *Diffusion) Mask {
        return channel.maskOf(self.bit);
    }
    pub fn writes(self: *Diffusion) Mask {
        return channel.maskOf(self.bit);
    }

    pub fn evaluate(self: *Diffusion, ctx: *RegionContext, out: *update.RegionUpdate) !void {
        const b = ctx.brick;
        const pl = b.plane(self.bit) orelse return;
        const h: f32 = @floatFromInt(b.spacing());
        var c: f32 = self.rate * @as(f32, @floatCast(ctx.dt)) / (h * h);
        if (c > 1.0 / 6.0) {
            c = 1.0 / 6.0;
            ctx.clamped += 1;
        }
        const o = b.origin();
        const sp: i64 = b.spacing();
        const dp = try out.delta(ctx.alloc, self.bit);
        var k: u32 = 0;
        while (k < N) : (k += 1) {
            var j: u32 = 0;
            while (j < N) : (j += 1) {
                var i: u32 = 0;
                while (i < N) : (i += 1) {
                    const idx = Brick.index(i, j, k);
                    const v = pl[idx];
                    var lap: f32 = 0;
                    if (!Brick.isBoundary(i, j, k)) {
                        // Block strides: the plane is the 11³ block (R7).
                        lap = pl[idx - 1] + pl[idx + 1] + pl[idx - HN] + pl[idx + HN] + pl[idx - HN * HN] + pl[idx + HN * HN] - 6 * v;
                    } else {
                        const p = [3]i64{ @as(i64, o[0]) + @as(i64, i) * sp, @as(i64, o[1]) + @as(i64, j) * sp, @as(i64, o[2]) + @as(i64, k) * sp };
                        inline for (0..3) |a| {
                            var pp = p;
                            var pm = p;
                            pp[a] += sp;
                            pm[a] -= sp;
                            lap += ctx.at(self.bit, pp) + ctx.at(self.bit, pm) - 2 * v;
                        }
                    }
                    dp[idx] = c * lap;
                }
            }
        }
    }
};

// ── Decay ────────────────────────────────────────────────────────────────

/// v(t) = v₀·exp(−t/τ). Exact per step whatever dt is.
pub const Decay = struct {
    pub const NAME = "decay";
    bit: u6,
    /// e-folding time, seconds.
    tau: f32,

    pub fn reads(self: *Decay) Mask {
        return channel.maskOf(self.bit);
    }
    pub fn writes(self: *Decay) Mask {
        return channel.maskOf(self.bit);
    }

    pub fn evaluate(self: *Decay, ctx: *RegionContext, out: *update.RegionUpdate) !void {
        const pl = ctx.brick.plane(self.bit) orelse return;
        const f: f32 = fmath.expf(-@as(f32, @floatCast(ctx.dt)) / self.tau) - 1;
        const dp = try out.delta(ctx.alloc, self.bit);
        for (pl, dp) |v, *d| d.* = v * f;
    }
};

// ── Advection ────────────────────────────────────────────────────────────

/// Semi-Lagrangian: v'(p) = v(p − u·dt). Unconditionally stable, a little
/// diffusive, exact for the closed form it is gated on — a blob's
/// centroid translates by u·t. `velocity` constant in lattice units per
/// second, or null to read the velocity channels at each sample.
pub const Advection = struct {
    pub const NAME = "advection";
    bit: u6,
    velocity: ?[3]f64,

    pub fn reads(self: *Advection) Mask {
        var m = channel.maskOf(self.bit);
        if (self.velocity == null) m |= Channel.velocity_x.mask() | Channel.velocity_y.mask() | Channel.velocity_z.mask();
        return m;
    }
    pub fn writes(self: *Advection) Mask {
        return channel.maskOf(self.bit);
    }

    pub fn evaluate(self: *Advection, ctx: *RegionContext, out: *update.RegionUpdate) !void {
        const b = ctx.brick;
        const pl = b.plane(self.bit) orelse return;
        const dp = try out.delta(ctx.alloc, self.bit);
        var k: u32 = 0;
        while (k < N) : (k += 1) {
            var j: u32 = 0;
            while (j < N) : (j += 1) {
                var i: u32 = 0;
                while (i < N) : (i += 1) {
                    const p = b.pointAt(i, j, k);
                    const q = [3]f64{ @floatFromInt(p[0]), @floatFromInt(p[1]), @floatFromInt(p[2]) };
                    const u: [3]f64 = self.velocity orelse .{
                        ctx.sample(Channel.velocity_x.bit(), q),
                        ctx.sample(Channel.velocity_y.bit(), q),
                        ctx.sample(Channel.velocity_z.bit(), q),
                    };
                    const src = [3]f64{ q[0] - u[0] * ctx.dt, q[1] - u[1] * ctx.dt, q[2] - u[2] * ctx.dt };
                    const idx = Brick.index(i, j, k);
                    dp[idx] = ctx.sample(self.bit, src) - pl[idx];
                }
            }
        }
    }
};

// ── Healing ──────────────────────────────────────────────────────────────

/// Local repair (spec §11–12, brief G4). Reads Damage, the carrier and
/// Activity; across the wound it restores Growth potential, and where
/// damage borders tissue and nothing is active it asks for a front
/// headed into the wound. Where tissue has regrown, damage clears. It
/// has no idea what the organism was; the same dynamics that built it
/// rebuild it, and they stop where the restored potential stops — which
/// is what keeps repair local.
pub const Healing = struct {
    pub const NAME = "healing";
    /// Growth restored per second at the wound boundary.
    rate: f32 = 1.0,
    /// The carrier below this counts as tissue (lattice units; zero is
    /// the surface).
    tissue: f32 = 0.0,
    /// Seconds for regrown tissue to clear its damage mark.
    clear_time: f32 = 4.0,
    /// A front is asked for only where no front has passed for this many
    /// seconds (Activity is a touch time). Nine seconds is where the
    /// Phase 1 level, decaying from 1 with τ = 3, fell under 0.05.
    quiet_s: f32 = 9.0,
    /// The front template for repair.
    params: front.Params = .{},

    pub fn reads(_: *Healing) Mask {
        return Channel.damage.mask() | Channel.surface.mask() | Channel.activity.mask();
    }
    pub fn writes(_: *Healing) Mask {
        return Channel.growth.mask() | Channel.damage.mask();
    }

    pub fn evaluate(self: *Healing, ctx: *RegionContext, out: *update.RegionUpdate) !void {
        const b = ctx.brick;
        const dmg = b.plane(Channel.damage.bit()) orelse return;
        const dt: f32 = @floatCast(ctx.dt);
        const o = b.origin();
        const sp: i64 = b.spacing();
        var best_idx: ?usize = null;
        var best_phi: f32 = std.math.inf(f32);
        var best_p: [3]i64 = undefined;
        var k: u32 = 0;
        while (k < N) : (k += 1) {
            var j: u32 = 0;
            while (j < N) : (j += 1) {
                var i: u32 = 0;
                while (i < N) : (i += 1) {
                    const idx = Brick.index(i, j, k);
                    if (dmg[idx] <= 0.5) continue;
                    const p = [3]i64{ @as(i64, o[0]) + @as(i64, i) * sp, @as(i64, o[1]) + @as(i64, j) * sp, @as(i64, o[2]) + @as(i64, k) * sp };
                    const phi_here = b.get(Channel.surface.bit(), i, j, k);
                    if (phi_here < self.tissue) {
                        // Regrown: the mark clears.
                        try out.add(ctx.alloc, Channel.damage.bit(), idx, -dt / self.clear_time);
                        continue;
                    }
                    // The wound: potential comes back across it.
                    try out.add(ctx.alloc, Channel.growth.bit(), idx, self.rate * dt);
                    var phi_near: f32 = std.math.inf(f32);
                    inline for (0..3) |a| {
                        var pp = p;
                        var pm = p;
                        pp[a] += sp;
                        pm[a] -= sp;
                        phi_near = @min(phi_near, @min(ctx.at(Channel.surface.bit(), pp), ctx.at(Channel.surface.bit(), pm)));
                    }
                    if (phi_near >= self.tissue) continue;
                    // Wound boundary: a front may start here, by the deepest tissue.
                    const touched = b.get(Channel.activity.bit(), i, j, k);
                    const still = touched == 0 or ctx.time_s - touched > self.quiet_s;
                    if (phi_near < best_phi and still) {
                        best_phi = phi_near;
                        best_idx = idx;
                        best_p = p;
                    }
                }
            }
        }
        if (best_idx != null and ctx.fronts_here == 0) {
            // Into the wound: up the damage gradient.
            var g: [3]f64 = undefined;
            inline for (0..3) |a| {
                var pp = best_p;
                var pm = best_p;
                pp[a] += sp;
                pm[a] -= sp;
                g[a] = @as(f64, ctx.at(Channel.damage.bit(), pp)) - @as(f64, ctx.at(Channel.damage.bit(), pm));
            }
            const gl = @sqrt(g[0] * g[0] + g[1] * g[1] + g[2] * g[2]);
            const dir: [3]f64 = if (gl > 1e-9) .{ g[0] / gl, g[1] / gl, g[2] / gl } else .{ 0, 1, 0 };
            const t: [3]f64 = if (@abs(dir[0]) < 0.9) .{ 1, 0, 0 } else .{ 0, 1, 0 };
            const n0 = [3]f64{ dir[1] * t[2] - dir[2] * t[1], dir[2] * t[0] - dir[0] * t[2], dir[0] * t[1] - dir[1] * t[0] };
            const nl = @sqrt(n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2]);
            try out.spawns.append(ctx.alloc, .{
                .pos = .{ @floatFromInt(best_p[0]), @floatFromInt(best_p[1]), @floatFromInt(best_p[2]) },
                .dir = dir,
                .normal = .{ n0[0] / nl, n0[1] / nl, n0[2] / nl },
                .params = self.params,
            });
        }
    }
};

test "an operator adapter reports its declared channels by name" {
    var d = Diffusion{ .bit = Channel.growth.bit(), .rate = 1 };
    const op = operatorOf(Diffusion, &d);
    try std.testing.expectEqualStrings("diffusion", op.name());
    try std.testing.expectEqual(Channel.growth.mask(), op.reads());
    var h = Healing{};
    const hop = operatorOf(Healing, &h);
    try std.testing.expect(channel.has(hop.writes(), Channel.growth.bit()));
    try std.testing.expect(!channel.has(hop.writes(), Channel.surface.bit()));
    try std.testing.expect(channel.has(hop.reads(), Channel.surface.bit()));
}
