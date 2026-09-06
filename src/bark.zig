//! bark — what a hit reads of the higher bands (P2.3; R12, R13; G16).
//!
//! Band 0 is the carrier and the renderer has it. THE BARK'S FRAME IS
//! THE FIELD'S (Christian, the night of P2.3: "the rings are a
//! scaffold; the point of loam is the gradient field"): the grain
//! (bands 3+) is value noise in the level set's own principal frame —
//! the Hessian at the hit, the tube's axis its direction of least
//! curvature — stretched along the axis, even in the frame's signs so
//! no flip leaves a seam, keyed by world position. It reads nothing but
//! the carrier. Pixar's bark builds that direction field by hand from
//! strokes (SIGGRAPH 2023, Bartsch, Thompson, de Goes); a signed
//! implicit has it for free.
//!
//! THE CHART IS HISTORY'S. `who` and `segment` name the capsule that
//! laid a sample; the chart's (s, θ) at any point is that capsule's
//! foot there, rebuilt from the ring records exactly — nothing stored
//! beyond the two ids, nothing interpolated (the night's first build
//! stored and interpolated two chart planes; the seam sat on the sample
//! grid and a one-sided mask lost linear precision at every collar).
//! Where two fronts laid the neighbourhood, the hit belongs to the one
//! whose field, rebuilt from the two slots, is nearer: the seam at the
//! crossing. Bands 1–2, the ring morphology through the chart, are read
//! in the chart mode for what only history can say (a scar); the field
//! already holds the rest.
//!
//! Every band is evaluated by FOOTPRINT — the ray's width at the hit,
//! WORLD units — and FADES in over an octave (`thresholds.bandWeight`):
//! "no sample ever arrives all at once". This file is the CPU reference
//! of the shader's field mode term for term, with the planes and bytes
//! a read touches counted against the prediction frozen beside G16's
//! threshold. The rules a mutation flips are `Rules`.

const std = @import("std");
const lattice = @import("lattice.zig");
const channel = @import("channel.zig");
const brick = @import("brick.zig");
const tree = @import("tree.zig");
const front = @import("front.zig");
const world = @import("world.zig");
const thresholds = @import("thresholds.zig");

const Channel = channel.Channel;
const Brick = brick.Brick;
const Snapshot = tree.Snapshot;
const World = world.World;

/// A plane read through the spline: its 64 coefficients, as G7 counts.
pub const PLANE_BYTES: u64 = 64 * 4;
/// A plane read nearest: one sample.
pub const SAMPLE_BYTES: u64 = 4;

pub const Mode = enum { chart, field };

/// How a hit reads. Every `false` is a named mutation of G16.
pub const Rules = struct {
    /// The grain's frame: the field's (the bark's) or the chart's (history's).
    mode: Mode = .field,
    /// `who` taken nearest, and by the fields where two fronts meet;
    /// false interpolates it — a third front's id.
    who_nearest: bool = true,
    /// `segment` taken nearest; false interpolates it — a foot on no
    /// capsule, s off by up to a ring.
    segment_nearest: bool = true,
    /// Bands fade in over an octave of footprint; false is the hard cut.
    fade: bool = true,
    /// The chart's grain bare at a collar; false lets its phase jump.
    bare_collar: bool = true,
    /// The footprint honoured; false pays for everything at every hit.
    footprint: bool = true,
};

pub const Class = enum { sponge, bark };

/// The chart at a point: the front, the capsule, its (s, θ) there, and
/// the spatial gradients of s and θ — the tangent frame the chart's
/// grain is bent in.
pub const Chart = struct {
    who: u32,
    /// `who` as read, before it is made an id: nearest it is an integer,
    /// interpolated it need not be, which is what G16 (a) checks.
    who_raw: f32,
    segment: u32,
    segment_raw: f32,
    s: f32,
    theta: f32,
    grad_s: [3]f32,
    grad_theta: [3]f32,
    /// Where two fronts laid the neighbourhood: this front's field at
    /// the hit and the other's, rebuilt from the slots.
    fields: ?[2]f32 = null,
};

fn leafAt(snap: *const Snapshot, p: [3]f64) ?*const Brick {
    return snap.findLeaf(.{ tree.floorI(p[0]), tree.floorI(p[1]), tree.floorI(p[2]) });
}

/// One front's distance field at `p`, rebuilt from the slots: at every
/// sample the front is the winner (its distance is `own`) or the
/// runner-up (`other`), and the spline of that choice is its field.
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

/// The chart at `p`, or null where nobody laid it: `who` and `segment`
/// nearest (two planes, a sample each), the capsule from the ring
/// records, its foot at `p` — s and θ exact, their gradients from the
/// capsule's own geometry. Where two fronts laid the 64 coefficients
/// around `p`, the fields decide whose the hit is (two more planes).
pub fn chartAt(w: *const World, snap: *const Snapshot, p: [3]f64, rules: Rules, planes: *u8, bytes: *u64) ?Chart {
    const b = leafAt(snap, p) orelse return null;
    const who_pl = b.plane(Channel.who.bit()) orelse return null;
    const seg_pl = b.plane(Channel.segment.bit()) orelse return null;
    planes.* += 2;
    var who_raw: f32 = undefined;
    var fields: ?[2]f32 = null;
    if (!rules.who_nearest) {
        who_raw = b.splinePlane(who_pl, p);
        bytes.* += PLANE_BYTES;
    } else {
        who_raw = b.nearest(Channel.who.bit(), p);
        bytes.* += SAMPLE_BYTES;
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
    // The segment: the nearest sample's among this front's.
    var seg_raw: f32 = undefined;
    if (!rules.segment_nearest) {
        seg_raw = b.splinePlane(seg_pl, p);
        bytes.* += PLANE_BYTES;
    } else {
        seg_raw = nearestOf(b, seg_pl, who_pl, channel.whoOf(id), p);
        bytes.* += SAMPLE_BYTES;
    }
    if (seg_raw < 1) return null;
    const segment: u32 = @intFromFloat(@round(seg_raw));
    const cap = w.capsuleAt(id, segment) orelse return null;
    const ft = cap.foot(p);
    // ∇s: the arc runs along the axis. ∇θ: the angle about it, in the
    // nearer ring's frame.
    const ds = cap.s1 - cap.s0;
    var grad_s: [3]f32 = .{ 0, 0, 0 };
    if (cap.len2 > 1e-18) {
        inline for (0..3) |a| grad_s[a] = @floatCast(cap.axis[a] * ds / cap.len2);
    }
    const use1 = ft.s_raw > 0.5;
    const nn = if (use1) cap.n1 else cap.n0;
    const bb = if (use1) cap.b1 else cap.b0;
    const d = [3]f64{ p[0] - cap.p0[0], p[1] - cap.p0[1], p[2] - cap.p0[2] };
    const rad = [3]f64{ d[0] - ft.s * cap.axis[0], d[1] - ft.s * cap.axis[1], d[2] - ft.s * cap.axis[2] };
    const x = world.dot(rad, nn);
    const y = world.dot(rad, bb);
    const r2 = @max(x * x + y * y, 1e-12);
    var grad_theta: [3]f32 = undefined;
    inline for (0..3) |a| grad_theta[a] = @floatCast((x * bb[a] - y * nn[a]) / r2);
    return .{ .who = id, .who_raw = who_raw, .segment = segment, .segment_raw = seg_raw, .s = cap.chartS(ft), .theta = cap.chartTheta(ft), .grad_s = grad_s, .grad_theta = grad_theta, .fields = fields };
}

/// The value of `pl` at the sample nearest `p` among those whose `who`
/// is `who` — the nearest of all if none is.
fn nearestOf(b: *const Brick, pl: *const brick.Plane, who_pl: *const brick.Plane, who: f32, p: [3]f64) f32 {
    const l = b.locate(p);
    var best: ?f32 = null;
    var best_d: f32 = std.math.inf(f32);
    var dk: u32 = 0;
    while (dk < 4) : (dk += 1) {
        var dj: u32 = 0;
        while (dj < 4) : (dj += 1) {
            var di: u32 = 0;
            while (di < 4) : (di += 1) {
                const idx = Brick.bindex(l.cell[0] + di, l.cell[1] + dj, l.cell[2] + dk);
                if (who_pl[idx] != who) continue;
                // The coefficient at block (c + di) is sample c + di − 1.
                const dx = l.t[0] - (@as(f32, @floatFromInt(di)) - 1);
                const dy = l.t[1] - (@as(f32, @floatFromInt(dj)) - 1);
                const dz = l.t[2] - (@as(f32, @floatFromInt(dk)) - 1);
                const dd = dx * dx + dy * dy + dz * dz;
                if (dd < best_d) {
                    best_d = dd;
                    best = pl[idx];
                }
            }
        }
    }
    return best orelse b.nearest(Channel.segment.bit(), p);
}

// ── Bands 3+: the grain ───────────────────────────────────────────────────
//
// Smoothstep value noise on a 2-D lattice at the amplitude vector's
// octaves — WORLD units, converted at the read, so the grain is the
// material's and not the brick's. The hash is integer arithmetic so
// the shader holds the same one.

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

/// The level set's principal frame at a hit from the Hessian: the
/// direction of least curvature (a tube's axis) and the one across it.
pub const Frame = struct { along: [3]f32, across: [3]f32, k_along: f32, k_across: f32 };

pub fn principalFrame(n: [3]f32, grad_len: f32, hess: [6]f32) Frame {
    // A tangent basis, then the shape operator's 2×2 in it.
    const up: [3]f32 = if (@abs(n[1]) < 0.9) .{ 0, 1, 0 } else .{ 1, 0, 0 };
    const t1 = normalize3(cross3(n, up));
    const t2 = cross3(n, t1);
    const gl = @max(grad_len, 1e-6);
    const a = quad(hess, t1, t1) / gl;
    const b = quad(hess, t1, t2) / gl;
    const c = quad(hess, t2, t2) / gl;
    const ang = 0.5 * std.math.atan2(2 * b, a - c);
    const ca = @cos(ang);
    const sa = @sin(ang);
    var e1: [3]f32 = undefined;
    var e2: [3]f32 = undefined;
    inline for (0..3) |i| {
        e1[i] = ca * t1[i] + sa * t2[i];
        e2[i] = -sa * t1[i] + ca * t2[i];
    }
    const m = 0.5 * (a + c);
    const dd = @sqrt(0.25 * (a - c) * (a - c) + b * b);
    const k1 = m + dd;
    const k2 = m - dd;
    if (@abs(k1) < @abs(k2)) return .{ .along = e1, .across = cross3(n, e1), .k_along = k1, .k_across = k2 };
    return .{ .along = e2, .across = cross3(n, e2), .k_along = k2, .k_across = k1 };
}

fn quad(hess: [6]f32, u: [3]f32, v: [3]f32) f32 {
    // hess: xx, yy, zz, xy, xz, yz.
    const hu = [3]f32{
        hess[0] * u[0] + hess[3] * u[1] + hess[4] * u[2],
        hess[3] * u[0] + hess[1] * u[1] + hess[5] * u[2],
        hess[4] * u[0] + hess[5] * u[1] + hess[2] * u[2],
    };
    return hu[0] * v[0] + hu[1] * v[1] + hu[2] * v[2];
}

fn cross3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn normalize3(v: [3]f32) [3]f32 {
    const l = @sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l < 1e-12) return v;
    return .{ v[0] / l, v[1] / l, v[2] / l };
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

/// What a hit read, and what it cost.
pub const Bark = struct {
    chart: ?Chart = null,
    frame: ?Frame = null,
    /// Band weights at the footprint: band 1, band 2, then the octaves.
    w1: f32 = 0,
    w2: f32 = 0,
    w3: [thresholds.BARK_OCTAVES_W.len]f32 = [_]f32{0} ** thresholds.BARK_OCTAVES_W.len,
    /// Band 1: the ring residual at the chart, weighted; band 2 its
    /// second difference along s, weighted; and band 1 unweighted.
    band1: f32 = 0,
    band2: f32 = 0,
    raw1: f32 = 0,
    /// The grain: relief in lattice units, weighted (and bared in the
    /// chart mode), and its derivatives per unit of (u, v).
    height: f32 = 0,
    grad_uv: [2]f32 = .{ 0, 0 },
    /// The chart's grain's bareness at the collar, one away from any.
    bare: f32 = 1,
    /// The normal bent by the grain; the unbent one where there is none.
    normal: [3]f32,
    /// What was touched: provenance planes, ring records, bytes.
    planes: u8 = 0,
    records: u8 = 0,
    bytes: u64 = 0,
};

/// A hit at `p` with unbent normal `n`, read for `class` at a
/// footprint in world units. Band 0 is assumed read (the renderer's
/// march); this counts what the bark adds.
pub fn read(w: *const World, snap: *const Snapshot, p: [3]f64, n: [3]f32, footprint_w: f32, class: Class, rules: Rules) Bark {
    var out = Bark{ .normal = n, .bytes = thresholds.G12_SPONGE_BYTES };
    if (class == .sponge) return out;
    const cell: f32 = @floatCast(w.domain.cell());
    const f: f32 = if (rules.footprint) footprint_w / cell else 0;
    for (thresholds.BARK_OCTAVES_W, 0..) |l, o| out.w3[o] = weight(l / cell, f, rules);
    var any3 = false;
    for (out.w3) |v| if (v > 0) {
        any3 = true;
    };
    if (rules.mode == .field) {
        // The field's frame: the Hessian at the hit — the carrier's
        // coefficients once more, no plane of provenance.
        if (!any3) return out;
        const b = leafAt(snap, p) orelse return out;
        const jet = b.splineJet(Channel.surface.bit(), p);
        out.bytes += thresholds.G12_SPONGE_BYTES;
        const gl = @sqrt(jet.grad[0] * jet.grad[0] + jet.grad[1] * jet.grad[1] + jet.grad[2] * jet.grad[2]);
        const fr = principalFrame(n, gl, jet.hess);
        out.frame = fr;
        const pw = [3]f32{ @floatCast(p[0]), @floatCast(p[1]), @floatCast(p[2]) };
        const u = dot3(pw, fr.across);
        const v = dot3(pw, fr.along);
        var h: f32 = 0;
        var gu: f32 = 0;
        var gv: f32 = 0;
        for (thresholds.BARK_OCTAVES_W, thresholds.BARK_AMPLITUDES_W, 0..) |l_w, a_w, o| {
            if (out.w3[o] <= 0) continue;
            const l = l_w / cell;
            const ls = l * thresholds.BARK_STRETCH;
            const a = a_w / cell * out.w3[o] * 0.25;
            // Even in u and in v: the frame's signs are arbitrary.
            const n1 = valueNoise(u / l, v / ls);
            const n2 = valueNoise(-u / l, v / ls);
            const n3 = valueNoise(u / l, -v / ls);
            const n4 = valueNoise(-u / l, -v / ls);
            h += a * (n1.v + n2.v + n3.v + n4.v);
            gu += a * (n1.du - n2.du + n3.du - n4.du) / l;
            gv += a * (n1.dv + n2.dv - n3.dv - n4.dv) / ls;
        }
        out.height = h;
        out.grad_uv = .{ gu, gv };
        var bent: [3]f32 = undefined;
        inline for (0..3) |ax| bent[ax] = n[ax] - gu * fr.across[ax] - gv * fr.along[ax];
        out.normal = normalize3(bent);
        return out;
    }
    // The chart mode: history through (who, segment), the capsule's foot.
    var coarsest: f32 = 0;
    for (thresholds.BARK_OCTAVES_W) |l| coarsest = @max(coarsest, l / cell);
    for (w.fronts.items) |fr| coarsest = @max(coarsest, @max(thresholds.band1Scale(fr.params.radius), fr.params.speed * @as(f32, @floatCast(w.dt_s))));
    if (weight(coarsest, f, rules) <= 0) return out;
    const chart = chartAt(w, snap, p, rules, &out.planes, &out.bytes) orelse return out;
    out.chart = chart;
    const fr = w.fronts.items[chart.who];
    out.w1 = weight(thresholds.band1Scale(fr.params.radius), f, rules);
    out.w2 = weight(fr.params.speed * @as(f32, @floatCast(w.dt_s)), f, rules);
    if (out.w1 > 0 or out.w2 > 0) {
        if (w.capsuleAt(chart.who, chart.segment)) |cap| {
            out.records += 2;
            out.bytes += 2 * @sizeOf(front.Ring);
            const t: f32 = if (cap.s1 > cap.s0) @floatCast((@as(f64, chart.s) - cap.s0) / (cap.s1 - cap.s0)) else 0;
            const r0 = World.Capsule.residual(cap.r0, chart.theta);
            const r1 = World.Capsule.residual(cap.r1, chart.theta);
            out.raw1 = std.math.lerp(r0, r1, @min(1, @max(0, t)));
            out.band1 = out.w1 * out.raw1;
            if (out.w2 > 0) {
                if (w.ringAt(chart.who, chart.segment + 1)) |next| {
                    out.records += 1;
                    out.bytes += @sizeOf(front.Ring);
                    out.band2 = out.w2 * (World.Capsule.residual(next.r, chart.theta) - 2 * r1 + r0);
                }
            }
        }
    }
    if (any3) {
        if (rules.bare_collar) {
            if (chart.fields) |fl| {
                const b = leafAt(snap, p).?;
                out.planes += 1;
                out.bytes += SAMPLE_BYTES;
                out.bare = thresholds.collarBare(fl[0], fl[1], b.nearest(Channel.collar.bit(), p), channel.band(1));
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
    try std.testing.expectEqual(@as(f32, 1), thresholds.collarBare(-1, 3, 2, 3));
    try std.testing.expectApproxEqAbs(@as(f32, 0), thresholds.collarBare(0.2, 0.2, 2, 3), 1e-6);
    try std.testing.expect(thresholds.collarBare(0, 1, 2, 3) > 0.7);
}

test "the principal frame of a tube is its axis and the direction around it" {
    // φ = ρ − r about the y axis at (r, 0, 0): ∇φ = x̂, H = diag(0, 0, 1/r).
    const r: f32 = 3;
    const fr = principalFrame(.{ 1, 0, 0 }, 1, .{ 0, 0, 1 / r, 0, 0, 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(fr.along[1]), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 1), @abs(fr.across[2]), 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), fr.k_along, 1e-6);
    try std.testing.expectApproxEqAbs(1 / r, fr.k_across, 1e-6);
}
