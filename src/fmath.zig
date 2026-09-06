//! fmath — the sim's transcendentals, the same bits in every binary.
//!
//! `@sin`, `@cos` and `@exp` lower to LLVM intrinsics that become calls
//! to `sin`, `cos`, `exp`: glibc's libm when a binary links libc (the C
//! seam, matryoshka), compiler_rt's musl port when it does not (loam-run,
//! the test binary). The two differ by an ulp here and there, and one
//! ulp in a bud's heading is a different content hash (P2.1: the Python
//! door and the CLI door disagreed on front 1's direction in the last
//! bit, after agreeing on every brick). So the sim owns its own: musl's
//! kernels and its medium-range reduction, ported and pinned, and a Sun
//! exp. Pure IEEE arithmetic in strict float mode — no FMA contraction,
//! no fast-math — so every build of this source gives the same result.
//! Accuracy is musl's (under an ulp); reproducibility is the point.
//!
//! What the sim may call: `sin`, `cos`, `exp` here, `std.math.atan2`
//! (pure Zig), `@sqrt` (correctly rounded by IEEE everywhere), and the
//! arithmetic. Nothing else transcendental.

const std = @import("std");

// ── sin, cos (musl __sin, __cos, __rem_pio2 medium) ───────────────────────

const S1 = -1.66666666666666324348e-01;
const S2 = 8.33333333332248946124e-03;
const S3 = -1.98412698298579493134e-04;
const S4 = 2.75573137070700676789e-06;
const S5 = -2.50507602534068634195e-08;
const S6 = 1.58969099521155010221e-10;

fn kernelSin(x: f64, y: f64, iy: bool) f64 {
    const z = x * x;
    const w = z * z;
    const r = S2 + z * (S3 + z * S4) + z * w * (S5 + z * S6);
    const v = z * x;
    if (!iy) return x + v * (S1 + z * r);
    return x - ((z * (0.5 * y - v * r) - y) - v * S1);
}

const C1 = 4.16666666666666019037e-02;
const C2 = -1.38888888888741095749e-03;
const C3 = 2.48015872894767294178e-05;
const C4 = -2.75573143513906633035e-07;
const C5 = 2.08757232129817482790e-09;
const C6 = -1.13596475577881948265e-11;

fn kernelCos(x: f64, y: f64) f64 {
    const z = x * x;
    const w = z * z;
    const r = z * (C1 + z * (C2 + z * C3)) + w * w * (C4 + z * (C5 + z * C6));
    const hz = 0.5 * z;
    const w2 = 1.0 - hz;
    return w2 + (((1.0 - w2) - hz) + (z * r - x * y));
}

const toint = 1.5 / std.math.floatEps(f64);
const invpio2 = 6.36619772367581382433e-01;
const pio2_1 = 1.57079632673412561417e+00;
const pio2_1t = 6.07710050650619224932e-11;
const pio2_2 = 6.07710050630396597660e-11;
const pio2_2t = 2.02226624879595063154e-21;
const pio2_3 = 2.02226624871116645580e-21;
const pio2_3t = 8.47842766036889956997e-32;
const pio4 = 0.785398163397448309616;
/// Beyond this the medium reduction loses bits; the sim never gets near
/// (a front's roll grows a few hundredths a step).
const medium = 1.0e6;

const Reduced = struct { n: i32, y0: f64, y1: f64 };

fn remPio2(x_in: f64) Reduced {
    var x = x_in;
    if (@abs(x) >= medium) x = @rem(x, 2 * std.math.pi); // exact IEEE remainder; deterministic, not accurate
    var fnn = x * invpio2 + toint - toint;
    var n: i32 = @intFromFloat(fnn);
    var r = x - fnn * pio2_1;
    var w = fnn * pio2_1t;
    if (r - w < -pio4) {
        n -= 1;
        fnn -= 1;
        r = x - fnn * pio2_1;
        w = fnn * pio2_1t;
    } else if (r - w > pio4) {
        n += 1;
        fnn += 1;
        r = x - fnn * pio2_1;
        w = fnn * pio2_1t;
    }
    var y0 = r - w;
    const ex: i32 = @intCast((@as(u64, @bitCast(x)) >> 52) & 0x7ff);
    var ey: i32 = @intCast((@as(u64, @bitCast(y0)) >> 52) & 0x7ff);
    if (ex - ey > 16) {
        var t = r;
        w = fnn * pio2_2;
        r = t - w;
        w = fnn * pio2_2t - ((t - r) - w);
        y0 = r - w;
        ey = @intCast((@as(u64, @bitCast(y0)) >> 52) & 0x7ff);
        if (ex - ey > 49) {
            t = r;
            w = fnn * pio2_3;
            r = t - w;
            w = fnn * pio2_3t - ((t - r) - w);
            y0 = r - w;
        }
    }
    return .{ .n = n, .y0 = y0, .y1 = (r - y0) - w };
}

pub fn sin(x: f64) f64 {
    if (std.math.isNan(x) or std.math.isInf(x)) return std.math.nan(f64);
    if (@abs(x) <= pio4) {
        if (@abs(x) < 0x1p-26) return x;
        return kernelSin(x, 0, false);
    }
    const q = remPio2(x);
    return switch (@as(u2, @intCast(q.n & 3))) {
        0 => kernelSin(q.y0, q.y1, true),
        1 => kernelCos(q.y0, q.y1),
        2 => -kernelSin(q.y0, q.y1, true),
        3 => -kernelCos(q.y0, q.y1),
    };
}

pub fn cos(x: f64) f64 {
    if (std.math.isNan(x) or std.math.isInf(x)) return std.math.nan(f64);
    if (@abs(x) <= pio4) {
        if (@abs(x) < 0x1p-27) return 1.0;
        return kernelCos(x, 0);
    }
    const q = remPio2(x);
    return switch (@as(u2, @intCast(q.n & 3))) {
        0 => kernelCos(q.y0, q.y1),
        1 => -kernelSin(q.y0, q.y1, true),
        2 => -kernelCos(q.y0, q.y1),
        3 => kernelSin(q.y0, q.y1, true),
    };
}

// ── exp (Sun e_exp) ───────────────────────────────────────────────────────

const ln2hi = 6.93147180369123816490e-01;
const ln2lo = 1.90821492927058770002e-10;
const invln2 = 1.44269504088896338700e+00;
const P1 = 1.66666666666666019037e-01;
const P2 = -2.77777777770155933842e-03;
const P3 = 6.61375632143793436117e-05;
const P4 = -1.65339022054652515390e-06;
const P5 = 4.13813679705723846039e-08;

/// x · 2^k by exponent arithmetic, for the k an exp can produce.
fn scale(x: f64, k: i32) f64 {
    if (k > 1023) return scale(x * 0x1p1023, k - 1023);
    if (k < -1022) return scale(x * 0x1p-1022, k + 1022);
    const bits: u64 = @as(u64, @intCast(k + 1023)) << 52;
    return x * @as(f64, @bitCast(bits));
}

pub fn exp(x: f64) f64 {
    if (std.math.isNan(x)) return x;
    if (x > 709.782712893384) return std.math.inf(f64);
    if (x < -745.1332191019412) return 0;
    if (@abs(x) < 0x1p-28) return 1.0 + x;
    // k = round(x / ln2), hi − lo = x − k·ln2 to extra precision.
    const kf = x * invln2 + toint - toint;
    const k: i32 = @intFromFloat(kf);
    const hi = x - kf * ln2hi;
    const lo = kf * ln2lo;
    const r = hi - lo;
    const t = r * r;
    const c = r - t * (P1 + t * (P2 + t * (P3 + t * (P4 + t * P5))));
    const y = 1.0 - ((lo - (r * c) / (2.0 - c)) - hi);
    return scale(y, k);
}

// ── f32, through f64 ──────────────────────────────────────────────────────

pub fn sinf(x: f32) f32 {
    return @floatCast(sin(@as(f64, x)));
}

pub fn cosf(x: f32) f32 {
    return @floatCast(cos(@as(f64, x)));
}

pub fn expf(x: f32) f32 {
    return @floatCast(exp(@as(f64, x)));
}

fn ulps(a: f64, b: f64) f64 {
    if (a == b) return 0;
    const scale_ = @max(@abs(a), @abs(b));
    return @abs(a - b) / (scale_ * std.math.floatEps(f64));
}

test "sin, cos and exp agree with the builtins to a couple of ulps over the sim's ranges" {
    var worst: f64 = 0;
    var x: f64 = -40;
    while (x <= 40) : (x += 0.0137) {
        worst = @max(worst, ulps(sin(x), @sin(x)));
        worst = @max(worst, ulps(cos(x), @cos(x)));
    }
    var e: f64 = -60;
    while (e <= 60) : (e += 0.0313) {
        worst = @max(worst, ulps(exp(e), @exp(e)));
    }
    try std.testing.expect(worst <= 2.0);
    try std.testing.expectEqual(@as(f64, 1), exp(0));
    try std.testing.expectEqual(@as(f64, 0), sin(0));
    try std.testing.expectEqual(@as(f64, 1), cos(0));
    try std.testing.expectApproxEqAbs(@as(f64, 0), sin(std.math.pi), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, -1), cos(std.math.pi), 1e-15);
    try std.testing.expectApproxEqAbs(@as(f64, 1), sin(1e7 + 0.25) * sin(1e7 + 0.25) + cos(1e7 + 0.25) * cos(1e7 + 0.25), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f32, 0.36787945), expf(-1), 1e-7);
}

test "the bits are pinned: a frozen sample of outputs" {
    // The regression that matters: these numbers must never move, in any
    // build mode, with or without libc. Frozen 2026-09-06 (P2.1).
    try std.testing.expectEqual(@as(u64, 0x3fe49d6e694619b8), @as(u64, @bitCast(sin(0.7))));
    try std.testing.expectEqual(@as(u64, 0x3fd2f6440ce940bb), @as(u64, @bitCast(cos(1.27))));
    try std.testing.expectEqual(@as(u64, 0x3ff4b050163af005), @as(u64, @bitCast(exp(0.257))));
    try std.testing.expectEqual(@as(u64, 0xbfef94cfefc15636), @as(u64, @bitCast(sin(23.4))));
    try std.testing.expectEqual(@as(u64, 0x3fe2a01b449c8a53), @as(u64, @bitCast(cos(-17.9))));
    try std.testing.expectEqual(@as(u64, 0x3fe6ee052939ace6), @as(u64, @bitCast(exp(-0.3333))));
}
