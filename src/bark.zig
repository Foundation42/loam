//! bark — what a hit reads of the higher bands (P2.3; R12, R13; G16).
//!
//! Band 0 is the carrier and the renderer has it. The bark is what a
//! hit reads BEYOND it: the CHART (s, θ) of the front that laid the
//! sample, from the provenance planes; the ring morphology at that
//! chart from the ring history (bands 1–2); and procedural grain keyed
//! by the chart so it sticks to the tube and never swims (bands 3+).
//! Every band is evaluated by FOOTPRINT — the ray's width at the hit,
//! WORLD units — and FADES in over an octave (`thresholds.bandWeight`)
//! rather than switching on: "no sample ever arrives all at once"
//! (Christian). Bands 3+ go bare at a collar, where the two slots'
//! weights meet, so the grain's phase never jumps where `who` changes;
//! the ridge in the grooves there is band 1's alone and real.
//!
//! This file is the CPU reference of what the shader does at a hit,
//! term for term, with the planes and bytes it touches counted — the
//! fact P2.3 exists to produce, against the prediction frozen beside
//! G16's threshold. The rules a mutation flips are `Rules`.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");
const front = @import("front.zig");
const world = @import("world.zig");
const thresholds = @import("thresholds.zig");
const fmath = @import("fmath.zig");

const Channel = channel.Channel;
const Brick = brick.Brick;
const Snapshot = tree.Snapshot;
const World = world.World;

/// A plane read through the spline: its 64 coefficients, as G7 counts.
pub const PLANE_BYTES: u64 = 64 * 4;
/// A plane read nearest: one sample.
pub const SAMPLE_BYTES: u64 = 4;

/// How a hit reads. Every `false` is a named mutation of G16.
pub const Rules = struct {
    /// θ interpolated as (cos θ, sin θ) and recovered by atan2; false
    /// interpolates the angle itself — a sliver of nonsense at the wrap.
    theta_wrapped: bool = true,
    /// `who` taken nearest; false interpolates it — a third front's id.
    who_nearest: bool = true,
    /// Bands fade in over an octave of footprint; false is the hard cut.
    fade: bool = true,
    /// Bands 3+ go bare at a collar; false lets the grain's phase jump.
    bare_collar: bool = true,
    /// The footprint honoured; false pays for everything at every hit.
    footprint: bool = true,
};

pub const Class = enum { sponge, bark };

/// The chart at a point: the front, its (s, θ) there, and the spatial
/// gradients of s and θ — the tangent frame a bump is bent in.
pub const Chart = struct {
    who: u32,
    /// `who` as read, before it is made an id: nearest it is an integer,
    /// interpolated it need not be, which is what G16 (a) checks.
    who_raw: f32,
    s: f32,
    theta: f32,
    grad_s: [3]f32,
    grad_theta: [3]f32,
    /// Where two fronts laid the neighbourhood: this front's field at
    /// the hit and the other's, rebuilt from the slots.
    fields: ?[2]f32 = null,
};

pub const Slots = struct { own: f32, other: f32, collar: f32 };

fn cosMap(x: f32) f32 {
    return fmath.cosf(x);
}
fn sinMap(x: f32) f32 {
    return fmath.sinf(x);
}
fn idMap(x: f32) f32 {
    return x;
}

fn leafAt(snap: *const Snapshot, p: [3]f64) ?*const Brick {
    return snap.findLeaf(.{ tree.floorI(p[0]), tree.floorI(p[1]), tree.floorI(p[2]) });
}

/// A B-spline over the nearest front's samples only: the 64
/// coefficients weighted as ever, those of another front (or nobody)
/// masked out, the rest renormalised — a partition of unity over one
/// chart. Charts are charts, not fields (R12): the spline of `chart_s`
/// across a `who` boundary mixed the parent's arc with the child's and
/// read 12.9 where the arc was 15. The gradient by the quotient rule.
fn maskedJet(b: *const Brick, pl: *const brick.Plane, who_pl: *const brick.Plane, who: f32, p: [3]f64, comptime map: fn (f32) f32) Brick.Jet1 {
    const l = b.locate(p);
    const bx = Brick.Basis.at(l.t[0]);
    const by = Brick.Basis.at(l.t[1]);
    const bz = Brick.Basis.at(l.t[2]);
    const h: f32 = @floatFromInt(b.spacing());
    // Σ w m v, and Σ w m, each with their three derivatives.
    var num: [4]f32 = .{ 0, 0, 0, 0 };
    var den: [4]f32 = .{ 0, 0, 0, 0 };
    var dk: u32 = 0;
    while (dk < 4) : (dk += 1) {
        var dj: u32 = 0;
        while (dj < 4) : (dj += 1) {
            var di: u32 = 0;
            while (di < 4) : (di += 1) {
                const idx = Brick.bindex(l.cell[0] + di, l.cell[1] + dj, l.cell[2] + dk);
                if (who_pl[idx] != who) continue;
                const v = map(pl[idx]);
                const w = bx.w[di] * by.w[dj] * bz.w[dk];
                const wx = bx.dw[di] * by.w[dj] * bz.w[dk];
                const wy = bx.w[di] * by.dw[dj] * bz.w[dk];
                const wz = bx.w[di] * by.w[dj] * bz.dw[dk];
                num[0] += w * v;
                num[1] += wx * v;
                num[2] += wy * v;
                num[3] += wz * v;
                den[0] += w;
                den[1] += wx;
                den[2] += wy;
                den[3] += wz;
            }
        }
    }
    if (den[0] <= 1e-12) return .{ .v = 0, .grad = .{ 0, 0, 0 } };
    const val = num[0] / den[0];
    var g: [3]f32 = undefined;
    inline for (0..3) |a| g[a] = (num[a + 1] - val * den[a + 1]) / den[0] / h;
    return .{ .v = val, .grad = g };
}

/// One front's distance field at `p`, rebuilt from the slots: at every
/// sample the front is the winner (its distance is `own`) or the
/// runner-up (`other`), and the spline of that choice is its field.
/// The two-slot form makes a front's own field readable at a hit even
/// where another front won the sample — which is what puts the chart's
/// seam where the two fields cross, not on the sample grid.
fn fieldOf(b: *const Brick, who_pl: *const brick.Plane, own_pl: *const brick.Plane, other_pl: *const brick.Plane, who: f32, p: [3]f64) f32 {
    const l = b.locate(p);
    const bx = Brick.Basis.at(l.t[0]);
    const by = Brick.Basis.at(l.t[1]);
    const bz = Brick.Basis.at(l.t[2]);
    var v: f32 = 0;
    var dk: u32 = 0;
    while (dk < 4) : (dk += 1) {
        var dj: u32 = 0;
        while (dj < 4) : (dj += 1) {
            var di: u32 = 0;
            while (di < 4) : (di += 1) {
                const idx = Brick.bindex(l.cell[0] + di, l.cell[1] + dj, l.cell[2] + dk);
                const c = if (who_pl[idx] == who) own_pl[idx] else other_pl[idx];
                v += c * bx.w[di] * by.w[dj] * bz.w[dk];
            }
        }
    }
    return v;
}

/// The chart at `p`, or null where nobody laid it. Three planes where
/// one front laid the neighbourhood: `who` (its coefficients, all one
/// value), `chart_s` (the masked spline: linear precision, so along a
/// capsule's axis the interpolated s IS the arc, and across a bend it
/// is the spline's smoothing of the kink — approximate), `chart_theta`
/// (the masked splines of cos θ and sin θ over the same coefficients,
/// atan2 of the pair; its gradient from theirs). Five where two fronts
/// did: the hit belongs to the one whose field, rebuilt from the slots,
/// is nearer — the seam at the crossing — and the two fields ride out
/// for the collar's bareness. Read NEAREST (the mutation), the seam
/// sits on the sample grid, up to most of a sample from the crossing,
/// and the grain was 86% present where the chart switched.
pub fn chartAt(snap: *const Snapshot, p: [3]f64, rules: Rules, planes: *u8, bytes: *u64) ?Chart {
    const b = leafAt(snap, p) orelse return null;
    const who_pl = b.plane(Channel.who.bit()) orelse return null;
    planes.* += 1;
    bytes.* += PLANE_BYTES;
    var who_raw: f32 = undefined;
    var fields: ?[2]f32 = null;
    if (!rules.who_nearest) {
        who_raw = b.splinePlane(who_pl, p);
    } else {
        who_raw = b.nearest(Channel.who.bit(), p);
        // A second front among the coefficients: the seam is decided by
        // the fields, not the grid.
        const l = b.locate(p);
        var second: ?f32 = null;
        var dk: u32 = 0;
        outer: while (dk < 4) : (dk += 1) {
            var dj: u32 = 0;
            while (dj < 4) : (dj += 1) {
                var di: u32 = 0;
                while (di < 4) : (di += 1) {
                    const v = who_pl[Brick.bindex(l.cell[0] + di, l.cell[1] + dj, l.cell[2] + dk)];
                    if (v != who_raw and v != 0) {
                        second = v;
                        break :outer;
                    }
                }
            }
        }
        if (second) |sw| {
            const own_pl = b.plane(Channel.own.bit()) orelse return null;
            const other_pl = b.plane(Channel.other.bit()) orelse return null;
            planes.* += 2;
            bytes.* += 2 * PLANE_BYTES;
            const fa = fieldOf(b, who_pl, own_pl, other_pl, who_raw, p);
            const fb = fieldOf(b, who_pl, own_pl, other_pl, sw, p);
            if (fb < fa) {
                who_raw = sw;
                fields = .{ fb, fa };
            } else fields = .{ fa, fb };
        }
    }
    const id = channel.idOf(who_raw) orelse return null;
    const s_pl = b.plane(Channel.chart_s.bit()) orelse return null;
    const t_pl = b.plane(Channel.chart_theta.bit()) orelse return null;
    const mask: f32 = channel.whoOf(id);
    const sj = maskedJet(b, s_pl, who_pl, mask, p, idMap);
    planes.* += 1;
    bytes.* += PLANE_BYTES;
    var theta: f32 = undefined;
    var gt: [3]f32 = undefined;
    if (rules.theta_wrapped) {
        const c = maskedJet(b, t_pl, who_pl, mask, p, cosMap);
        const sn = maskedJet(b, t_pl, who_pl, mask, p, sinMap);
        theta = std.math.atan2(sn.v, c.v);
        if (theta < 0) theta += 2 * std.math.pi;
        // θ = atan2(S, C): ∇θ = (C∇S − S∇C) / (C² + S²).
        const d = @max(c.v * c.v + sn.v * sn.v, 1e-12);
        inline for (0..3) |a| gt[a] = (c.v * sn.grad[a] - sn.v * c.grad[a]) / d;
    } else {
        const tj = maskedJet(b, t_pl, who_pl, mask, p, idMap);
        theta = tj.v;
        gt = tj.grad;
    }
    planes.* += 1;
    bytes.* += PLANE_BYTES;
    return .{ .who = id, .who_raw = who_raw, .s = sj.v, .theta = theta, .grad_s = sj.grad, .grad_theta = gt, .fields = fields };
}

/// The two slots and the join's k at `p`: the distances by the spline,
/// k nearest. Three planes.
pub fn slotsAt(snap: *const Snapshot, p: [3]f64, planes: *u8, bytes: *u64) Slots {
    const b = leafAt(snap, p) orelse return .{ .own = channel.band(1), .other = channel.band(1), .collar = 0 };
    planes.* += 3;
    bytes.* += 2 * PLANE_BYTES + SAMPLE_BYTES;
    return .{
        .own = b.spline(Channel.own.bit(), p),
        .other = b.spline(Channel.other.bit(), p),
        .collar = b.nearest(Channel.collar.bit(), p),
    };
}

// ── Bands 3+: the grain ───────────────────────────────────────────────────
//
// Smoothstep value noise on the chart's (u, v) = (θ·r, s), lattice
// units, at the amplitude vector's octaves — WORLD units, converted at
// the read, so the grain is the material's and not the brick's. The
// hash is integer arithmetic so the shader can hold the same one.

fn hash2(ix: i32, iy: i32) f32 {
    var h: u32 = @as(u32, @bitCast(ix)) *% 0x8da6b343;
    h ^= @as(u32, @bitCast(iy)) *% 0xd8163841;
    h ^= h >> 13;
    h *%= 0x9e3779b1;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xffffff)) / @as(f32, 0x1000000) * 2 - 1;
}

pub const Noise = struct { v: f32, du: f32, dv: f32 };

/// Value noise in [−1, 1] and its derivatives per unit of (u, v).
pub fn valueNoise(u: f32, v: f32) Noise {
    const fu = @floor(u);
    const fv = @floor(v);
    const ix: i32 = @intFromFloat(fu);
    const iy: i32 = @intFromFloat(fv);
    const tx = u - fu;
    const ty = v - fv;
    const a = hash2(ix, iy);
    const b = hash2(ix + 1, iy);
    const c = hash2(ix, iy + 1);
    const d = hash2(ix + 1, iy + 1);
    const sx = tx * tx * (3 - 2 * tx);
    const sy = ty * ty * (3 - 2 * ty);
    const dsx = 6 * tx * (1 - tx);
    const dsy = 6 * ty * (1 - ty);
    const ab = a + (b - a) * sx;
    const cd = c + (d - c) * sx;
    return .{
        .v = ab + (cd - ab) * sy,
        .du = ((b - a) * (1 - sy) + (d - c) * sy) * dsx,
        .dv = (cd - ab) * dsy,
    };
}

/// What a hit read, and what it cost.
pub const Bark = struct {
    chart: ?Chart = null,
    /// Band weights at the footprint: band 1, band 2, then the octaves.
    w1: f32 = 0,
    w2: f32 = 0,
    w3: [thresholds.BARK_OCTAVES_W.len]f32 = [_]f32{0} ** thresholds.BARK_OCTAVES_W.len,
    /// Band 1: the ring residual at the chart, weighted; band 2 its
    /// second difference along s, weighted; and band 1 unweighted, the
    /// value the fade is applied to.
    band1: f32 = 0,
    band2: f32 = 0,
    raw1: f32 = 0,
    /// The grain: relief in lattice units, weighted and bared, and its
    /// derivatives per unit of (u, v).
    height: f32 = 0,
    grad_uv: [2]f32 = .{ 0, 0 },
    /// Bands 3+'s bareness at the collar, one away from any.
    bare: f32 = 1,
    /// The normal bent by the grain; the unbent one where there is none.
    normal: [3]f32,
    /// What was touched: provenance planes, ring records, bytes.
    planes: u8 = 0,
    records: u8 = 0,
    bytes: u64 = 0,
};

fn normalize3(v: [3]f32) [3]f32 {
    const l = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l < 1e-12) return v;
    return .{ v[0] / l, v[1] / l, v[2] / l };
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

/// The ring index whose capsule holds arc `s` on front `who`: the
/// smallest k with s ≤ s_k, at least 1. Null with no history.
fn segmentOf(w: *const World, who: u32, s: f32) ?u32 {
    if (who >= w.rings.items.len) return null;
    const list = w.rings.items[who].items;
    if (list.len < 2) return null;
    var lo: usize = 1;
    var hi: usize = list.len - 1;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (list[mid].s < s) lo = mid + 1 else hi = mid;
    }
    return @intCast(lo);
}

/// A hit at `p` with unbent normal `n`, read for `class` at a
/// footprint in world units. Band 0 is assumed read (the renderer's
/// march); this counts what the bark adds.
pub fn read(w: *const World, snap: *const Snapshot, p: [3]f64, n: [3]f32, footprint_w: f32, class: Class, rules: Rules) Bark {
    var out = Bark{ .normal = n, .bytes = thresholds.G12_SPONGE_BYTES };
    if (class == .sponge) return out;
    const cell: f32 = @floatCast(w.domain.cell());
    const f: f32 = if (rules.footprint) footprint_w / cell else 0;
    // Nothing coarser than the coarsest band is worth a plane.
    var coarsest: f32 = 0;
    for (thresholds.BARK_OCTAVES_W) |l| coarsest = @max(coarsest, l / cell);
    for (w.fronts.items) |fr| coarsest = @max(coarsest, @max(thresholds.band1Scale(fr.params.radius), fr.params.speed * @as(f32, @floatCast(w.dt_s))));
    if (weight(coarsest, f, rules) <= 0) return out;
    const chart = chartAt(snap, p, rules, &out.planes, &out.bytes) orelse return out;
    out.chart = chart;
    const fr = w.fronts.items[chart.who];
    out.w1 = weight(thresholds.band1Scale(fr.params.radius), f, rules);
    out.w2 = weight(fr.params.speed * @as(f32, @floatCast(w.dt_s)), f, rules);
    for (thresholds.BARK_OCTAVES_W, 0..) |l, o| out.w3[o] = weight(l / cell, f, rules);
    // Bands 1–2: the ring records at (who, segment by s).
    if (out.w1 > 0 or out.w2 > 0) {
        if (segmentOf(w, chart.who, chart.s)) |k| {
            if (w.capsuleAt(chart.who, k)) |cap| {
                out.records += 2;
                out.bytes += 2 * @sizeOf(front.Ring);
                const t: f32 = if (cap.s1 > cap.s0) @floatCast((@as(f64, chart.s) - cap.s0) / (cap.s1 - cap.s0)) else 0;
                const r0 = World.Capsule.residual(cap.r0, chart.theta);
                const r1 = World.Capsule.residual(cap.r1, chart.theta);
                out.raw1 = std.math.lerp(r0, r1, @min(1, @max(0, t)));
                out.band1 = out.w1 * out.raw1;
                if (out.w2 > 0) {
                    if (w.ringAt(chart.who, k + 1)) |next| {
                        out.records += 1;
                        out.bytes += @sizeOf(front.Ring);
                        out.band2 = out.w2 * (World.Capsule.residual(next.r, chart.theta) - 2 * r1 + r0);
                    }
                }
            }
        }
    }
    // Bands 3+: the grain, bare at a collar.
    var any3 = false;
    for (out.w3) |v| if (v > 0) {
        any3 = true;
    };
    if (any3) {
        if (rules.bare_collar) {
            if (chart.fields) |fl| {
                // The two fields at the hit are known; the join's k nearest.
                const b = leafAt(snap, p).?;
                out.planes += 1;
                out.bytes += SAMPLE_BYTES;
                out.bare = thresholds.collarBare(fl[0], fl[1], b.nearest(Channel.collar.bit(), p), channel.band(1));
            } else {
                const sl = slotsAt(snap, p, &out.planes, &out.bytes);
                out.bare = thresholds.collarBare(sl.own, sl.other, sl.collar, channel.band(1));
            }
        }
        const r = fr.params.radius;
        const u = chart.theta * r;
        const v = chart.s;
        var h: f32 = 0;
        var gu: f32 = 0;
        var gv: f32 = 0;
        for (thresholds.BARK_OCTAVES_W, thresholds.BARK_AMPLITUDES_W, 0..) |l_w, a_w, o| {
            if (out.w3[o] <= 0) continue;
            const l = l_w / cell;
            const a = a_w / cell * out.w3[o] * out.bare;
            const nz = valueNoise(u / l, v / l);
            h += a * nz.v;
            gu += a * nz.du / l;
            gv += a * nz.dv / l;
        }
        out.height = h;
        out.grad_uv = .{ gu, gv };
        // The bump: the relief's gradient in space is h_u ∇u + h_v ∇v,
        // taken in the tangent plane, and the bent normal is n minus it.
        // ∇u = r ∇θ; |∇u| and |∇s| are one on the surface of a tube.
        var gs = chart.grad_s;
        var gth = chart.grad_theta;
        const ns = dot3(gs, n);
        const nt = dot3(gth, n);
        inline for (0..3) |ax| {
            gs[ax] -= ns * n[ax];
            gth[ax] = (gth[ax] - nt * n[ax]) * r;
        }
        var bent: [3]f32 = undefined;
        inline for (0..3) |ax| bent[ax] = n[ax] - gu * gth[ax] - gv * gs[ax];
        out.normal = normalize3(bent);
    }
    return out;
}

fn weight(scale: f32, f: f32, rules: Rules) f32 {
    if (!rules.footprint) return 1;
    if (!rules.fade) return if (scale >= f) 1 else 0;
    return thresholds.bandWeight(scale, f);
}

test "value noise is in range, continuous, and its derivatives are the finite differences" {
    var x: f32 = -3.7;
    while (x < 4) : (x += 0.37) {
        var y: f32 = -2.1;
        while (y < 3) : (y += 0.41) {
            const nz = valueNoise(x, y);
            try std.testing.expect(nz.v >= -1 and nz.v <= 1);
            const e: f32 = 1e-3;
            const du = (valueNoise(x + e, y).v - valueNoise(x - e, y).v) / (2 * e);
            const dv = (valueNoise(x, y + e).v - valueNoise(x, y - e).v) / (2 * e);
            try std.testing.expectApproxEqAbs(du, nz.du, 2e-2);
            try std.testing.expectApproxEqAbs(dv, nz.dv, 2e-2);
        }
    }
}

test "the band weight fades over an octave and a band under its footprint is never fetched" {
    try std.testing.expectEqual(@as(f32, 1), thresholds.bandWeight(1.0, 0.5));
    try std.testing.expectEqual(@as(f32, 0), thresholds.bandWeight(1.0, 1.0));
    try std.testing.expectEqual(@as(f32, 0), thresholds.bandWeight(1.0, 1.5));
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), thresholds.bandWeight(1.0, 2.0 / 3.0), 1e-6);
    // Bare: one away from any collar, zero where the two slots meet.
    try std.testing.expectEqual(@as(f32, 1), thresholds.collarBare(-1, 3, 2, 3));
    try std.testing.expectApproxEqAbs(@as(f32, 0), thresholds.collarBare(0.2, 0.2, 2, 3), 1e-6);
    try std.testing.expect(thresholds.collarBare(0, 1, 2, 3) > 0.7);
}
