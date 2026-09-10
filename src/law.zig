//! law — OBS-7: operator inference (the note's §29 level 3, by way of §27).
//!
//! OBS-1 did level 1 (state), OBS-2 level 2 (the parameters of a hidden
//! potential), and OBS-6 made the structural-pressure signal readable by
//! taking the optimiser's wander out of it. §29 asks for each level to be
//! demonstrated independently before the next, so this is level 3:
//!
//! > Which combination of available field operators best explains the
//! > observations?
//!
//! **The rig already contained a hidden operator.** `trajectory.zig`'s law
//! is `ẋ = ω·R(x−c) − Σᵢ wᵢ∇φᵢ(x)`, and OBS-3 through OBS-6 used `ω` as a
//! KNOWN, GIVEN knob — correct 0, wrong 0.3. Level 3 is the same rig with
//! it taken away: the truth has it, the learner is not told, and must find
//! it in a library.
//!
//! ## Why this is a separate engine
//!
//! `trajectory.zig` is generic over a count of potential coefficients and
//! propagates ∂x/∂wᵢ. The library needs ∂x/∂θₖ for operators that are not
//! potential gradients, and four gates (G49, G50, G51, G53) rest on that
//! file reproducing bit for bit. Extending it in place would put those at
//! risk to save a hundred lines. The sensitivity ODE is the same shape in
//! both — ṡⱼ = ∂f/∂θⱼ + J·sⱼ — so nothing is duplicated except the loop.
//!
//! ## The prediction this phase exists for
//!
//! §27's success criterion is "the true coefficient converges to its value
//! while irrelevant coefficients approach zero". Half of that cannot
//! happen here, and the reason is Helmholtz rather than optimisation: the
//! learner is ALREADY fitting a pure gradient field, so any candidate that
//! is itself a gradient is competing for the same explanation. Exactly one
//! of the five candidates below is divergence-free. See
//! `tools/obs7_predict.py`, frozen before this file.

const std = @import("std");
const builtin = @import("builtin");
const marl = @import("marl.zig");
const inferred = @import("inferred.zig");
const rng = @import("rng.zig");
const thresholds = @import("thresholds.zig");

const testing = std.testing;

/// Potential coefficients — `inferred.shape`'s nine, unchanged, so the
/// model class is exactly OBS-2's.
pub const POT: usize = inferred.count;
/// Candidate operators in the library.
pub const OPS: usize = 5;
pub const N: usize = POT + OPS;

/// The centre the affine candidates are written about — the domain's, and
/// the same one `trajectory.zig`'s rotation uses.
pub const C: f32 = 0.5;

/// The library. Only `.rotation` is in the truth; the other four are
/// distractors, and the point of the phase is that they are not all the
/// same KIND of distractor.
///
/// `V_k(x)` with d = x − c:
///
///     rotation    (−d_y,  d_x)   divergence free, curl 2   NOT a gradient
///     divergence  ( d_x,  d_y)   = ∇(|d|²/2)                   a gradient
///     shear       ( d_y,  d_x)   = ∇(d_x d_y)                   a gradient
///     drift_x     ( 1, 0 )       = ∇(x)                         a gradient
///     drift_y     ( 0, 1 )       = ∇(y)                         a gradient
///
/// Four of the five lie in the span the potential term is already free to
/// reshape. That is not a flaw in the library — it is the most ordinary
/// library anyone would write for a 2-D flow, which is what makes the
/// finding worth having.
pub const Op = enum(usize) { rotation = 0, divergence = 1, shear = 2, drift_x = 3, drift_y = 4 };

/// V_k at x.
pub fn opVelocity(comptime T: type, k: usize, x: [2]T) [2]T {
    const d = [2]T{ x[0] - C, x[1] - C };
    return switch (@as(Op, @enumFromInt(k))) {
        .rotation => .{ -d[1], d[0] },
        .divergence => .{ d[0], d[1] },
        .shear => .{ d[1], d[0] },
        .drift_x => .{ 1, 0 },
        .drift_y => .{ 0, 1 },
    };
}

/// ∂V_k/∂x — constant, because every candidate is affine.
pub fn opJacobian(comptime T: type, k: usize) [2][2]T {
    return switch (@as(Op, @enumFromInt(k))) {
        .rotation => .{ .{ 0, -1 }, .{ 1, 0 } },
        .divergence => .{ .{ 1, 0 }, .{ 0, 1 } },
        .shear => .{ .{ 0, 1 }, .{ 1, 0 } },
        .drift_x, .drift_y => .{ .{ 0, 0 }, .{ 0, 0 } },
    };
}

/// The RMS velocity operator k contributes per unit coefficient, over the
/// sampled square — the unit that makes coefficients of different shape
/// comparable at all.
///
/// Closed form and not sampled: the starts are `0.15 + 0.7·u` per axis
/// (`observational_windows.start`), so d is uniform on [−0.35, 0.35] and
/// E[d²] per axis is 0.35²/3. The three |d|-shaped operators share
/// √(2·0.35²/3) = 0.2858 and the two uniform ones are exactly 1.
pub fn opUnit(k: usize) f32 {
    const h: f32 = 0.35;
    const rms_d: f32 = @sqrt(2 * h * h / 3.0);
    return switch (@as(Op, @enumFromInt(k))) {
        .rotation, .divergence, .shear => rms_d,
        .drift_x, .drift_y => 1,
    };
}

pub fn State(comptime T: type) type {
    return struct { x: [2]T, s: [N][2]T = .{.{ 0, 0 }} ** N };
}

/// ẋ and the sensitivity ODE, in one pass.
///
/// `p[0..POT]` are the potential coefficients and `p[POT..]` the library's.
/// For every parameter the sensitivity obeys ṡⱼ = ∂f/∂θⱼ + J·sⱼ, and the
/// two halves differ only in what ∂f/∂θⱼ is: −∇φⱼ for a potential
/// coefficient, V_k for an operator.
fn rhs(comptime T: type, p: [N]T, z: State(T), omit_position: bool) State(T) {
    var out = State(T){ .x = .{ 0, 0 } };
    var jac = [2][2]T{ .{ 0, 0 }, .{ 0, 0 } };

    // The potential, exactly `inferred`'s basis.
    var g: [POT][2]T = undefined;
    for (0..POT) |i| {
        const sh = inferred.shape(i);
        const inv: T = @as(T, sh.l[0]) * @as(T, sh.l[0]);
        const d = [2]T{ z.x[0] - @as(T, sh.mu[0]), z.x[1] - @as(T, sh.mu[1]) };
        const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
        if (r2 > marl.CUTOFF) {
            g[i] = .{ 0, 0 };
            continue;
        }
        const phi = @exp(-0.5 * r2);
        for (0..2) |a| {
            g[i][a] = -phi * inv * d[a];
            out.x[a] -= p[i] * g[i][a];
            for (0..2) |c| jac[a][c] -= p[i] * phi * (inv * inv * d[a] * d[c] - if (a == c) inv else @as(T, 0));
        }
    }

    // The library.
    var v: [OPS][2]T = undefined;
    for (0..OPS) |k| {
        v[k] = opVelocity(T, k, z.x);
        const a_k = opJacobian(T, k);
        for (0..2) |a| {
            out.x[a] += p[POT + k] * v[k][a];
            for (0..2) |c| jac[a][c] += p[POT + k] * a_k[a][c];
        }
    }

    for (0..N) |j| for (0..2) |a| {
        out.s[j][a] = if (j < POT) -g[j][a] else v[j - POT][a];
        // The J·s coupling: moving a coefficient moves the PATH, and the
        // path's own sensitivity feeds back. `trajectory.zig` carries the
        // same flag under the same name, and G49 (a) is where it was first
        // audited; dropping it leaves a derivative of the right sign and
        // the right order that drifts further wrong the longer the
        // trajectory runs.
        if (!omit_position) for (0..2) |c| {
            out.s[j][a] += jac[a][c] * z.s[j][c];
        };
    };
    return out;
}

fn add(comptime T: type, z: State(T), dz: State(T), dt: T) State(T) {
    var out = z;
    for (0..2) |a| {
        out.x[a] += dt * dz.x[a];
        for (0..N) |j| out.s[j][a] += dt * dz.s[j][a];
    }
    return out;
}

/// Midpoint, the same integrator `trajectory.zig` uses, so the two rigs
/// are comparable where they overlap.
pub fn trajectory(comptime T: type, p: [N]T, x: [2]T, dt: T, steps: u32) State(T) {
    return trace(T, p, x, dt, steps, false);
}

pub fn trace(comptime T: type, p: [N]T, x: [2]T, dt: T, steps: u32, omit_position: bool) State(T) {
    var z = State(T){ .x = x };
    for (0..steps) |_| {
        const mid = add(T, z, rhs(T, p, z, omit_position), dt / 2);
        z = add(T, z, rhs(T, p, mid, omit_position), dt);
    }
    return z;
}

pub const Observation = struct { x: [2]f32, y: [2]f32, steps: u32 };

pub const zero: [N]f32 = .{0} ** N;

/// The truth: OBS-2's potential coefficients, plus a rotation the learner
/// is not told about. `omega` is OBS-3 and OBS-4's own 0.3, not a new
/// number, so the hidden term is one the campaign has already characterised
/// from the other side.
pub fn truth(seed: u64, omega: f32) [N]f32 {
    var p = zero;
    const w = inferred.truthWeights(seed);
    @memcpy(p[0..POT], &w);
    p[POT + @intFromEnum(Op.rotation)] = omega;
    return p;
}

fn start(st: *rng.Stream) [2]f32 {
    return .{ 0.15 + 0.7 * st.unit(), 0.15 + 0.7 * st.unit() };
}

pub const Data = struct {
    train: [32]Observation,
    held: [64]Observation,

    /// The same sensor design OBS-4 uses: sixteen starts at two horizons
    /// for training, a disjoint sixty-four for evaluation.
    pub fn init(seed: u64, omega: f32) Data {
        const p = truth(seed, omega);
        var out: Data = undefined;
        var ts = rng.Stream.region(seed, 0x4f37_5452, 0); // "O7TR"
        for (0..16) |i| {
            const x = start(&ts);
            for ([_]u32{ 8, 24 }, 0..) |n, j| {
                out.train[2 * i + j] = .{ .x = x, .y = trajectory(f32, p, x, 0.005, n * 4).x, .steps = n };
            }
        }
        var hs = rng.Stream.region(seed, 0x4f37_484f, 0); // "O7HO"
        for (&out.held) |*o| {
            const x = start(&hs);
            o.* = .{ .x = x, .y = trajectory(f32, p, x, 0.005, 96).x, .steps = 24 };
        }
        return out;
    }
};

pub fn endpointRms(p: [N]f32, obs: []const Observation) f64 {
    var se: f64 = 0;
    for (obs) |o| {
        const z = trajectory(f32, p, o.x, 0.02, o.steps);
        for (0..2) |a| se += @as(f64, z.x[a] - o.y[a]) * (z.x[a] - o.y[a]);
    }
    return @sqrt(se / @as(f64, @floatFromInt(obs.len)));
}

/// The gradient of the endpoint loss in every learnable coefficient.
pub fn gradient(p: [N]f32, obs: []const Observation, mask: [N]bool) [N]f32 {
    var g = zero;
    for (obs) |o| {
        const z = trajectory(f32, p, o.x, 0.02, o.steps);
        for (0..N) |j| {
            if (!mask[j]) continue;
            for (0..2) |a| g[j] += (z.x[a] - o.y[a]) * z.s[j][a];
        }
    }
    return g;
}

/// Adam under OBS-5's schedule. `1/t` past the warm-up, which G52 (a)
/// measured directly on this optimiser and this fixture: at a fixed rate it
/// wanders in a ball of radius `lr` however converged the fit is, and OBS-6
/// showed the schedule costs the fit nothing here and improves it by three
/// orders where the rate is what binds.
pub const RATE: f32 = 0.003;
pub const WARMUP: usize = 400;

pub const Fit = struct {
    p: [N]f32,
    train: f64,
    held: f64,
};

pub fn fit(data: *const Data, mask: [N]bool, steps: usize) Fit {
    var p = zero;
    var m = zero;
    var v = zero;
    var b1: [N]f32 = .{1} ** N;
    var b2: [N]f32 = .{1} ** N;
    for (1..steps + 1) |t| {
        const g = gradient(p, &data.train, mask);
        const lr = RATE * @min(1, @as(f32, @floatFromInt(WARMUP)) / @as(f32, @floatFromInt(t)));
        for (0..N) |j| {
            if (!mask[j]) continue;
            b1[j] *= 0.9;
            b2[j] *= 0.999;
            m[j] = 0.9 * m[j] + 0.1 * g[j];
            v[j] = 0.999 * v[j] + 0.001 * g[j] * g[j];
            p[j] -= lr * (m[j] / (1 - b1[j])) / (@sqrt(v[j] / (1 - b2[j])) + 1e-8);
        }
    }
    return .{ .p = p, .train = endpointRms(p, &data.train), .held = endpointRms(p, &data.held) };
}

/// Every coefficient learnable — the level-3 arm.
pub fn fullMask() [N]bool {
    return .{true} ** N;
}

/// The potential alone: the law left incomplete, which is OBS-3's
/// wrong-dynamics arm in a different costume.
pub fn potentialOnly() [N]bool {
    var mask: [N]bool = .{false} ** N;
    for (0..POT) |i| mask[i] = true;
    return mask;
}

/// Mean and coefficient of variation of a set of samples.
pub const Spread = struct {
    mean: f64,
    cv: f64,

    pub fn of(v: []const f64) Spread {
        var s: f64 = 0;
        for (v) |x| s += x;
        const mean = s / @as(f64, @floatFromInt(v.len));
        var q: f64 = 0;
        for (v) |x| q += (x - mean) * (x - mean);
        const sd = @sqrt(q / @as(f64, @floatFromInt(v.len)));
        // About the MAGNITUDE, because a coefficient that lands at +0.02 on
        // one seed and −0.02 on another has a mean near zero and a CV that
        // would read as infinite. What is being measured is how much the
        // fit MOVES a coefficient, not where its centre is.
        var a: f64 = 0;
        for (v) |x| a += @abs(x);
        const scale = @max(1e-9, a / @as(f64, @floatFromInt(v.len)));
        return .{ .mean = mean, .cv = sd / scale };
    }
};

const SEEDS = [_]u64{ 7, 19, 41 };
const STEPS: usize = 3600;

test "G54 (a) the library's sensitivities survive finite differences" {
    // G49's discipline, one level out. The library's ∂x/∂θₖ is propagated
    // by the same ODE as the potential's, so the audit has to cover both —
    // and the mutation is at the foot: dropping the `J·s` coupling leaves a
    // derivative that is still the right ORDER and still points the right
    // way, which is exactly the kind of wrong that a loss curve hides.
    var worst: f64 = 0;
    var smallest: f64 = std.math.inf(f64);
    for (SEEDS) |seed| {
        const p32 = truth(seed, 0.3);
        var p: [N]f64 = undefined;
        for (&p, p32) |*a, b| a.* = b;
        for ([_]u32{ 8, 24, 64 }) |steps| {
            for ([_][2]f64{ .{ 0.35, 0.45 }, .{ 0.82, 0.75 }, .{ 0.18, 0.62 } }) |x| {
                const z = trajectory(f64, p, x, 0.02, steps);
                for (0..N) |j| {
                    for (0..2) |a| {
                        const analytic = z.s[j][a];
                        smallest = @min(smallest, @abs(analytic));
                        // Richardson over two step sizes, so the check is
                        // not at the mercy of one choice of eps.
                        var best: f64 = std.math.inf(f64);
                        for ([_]f64{ 1e-4, 1e-5 }) |eps| {
                            var hi = p;
                            var lo = p;
                            hi[j] += eps;
                            lo[j] -= eps;
                            const fd = (trajectory(f64, hi, x, 0.02, steps).x[a] -
                                trajectory(f64, lo, x, 0.02, steps).x[a]) / (2 * eps);
                            best = @min(best, @abs(fd - analytic) / @max(1e-6, @abs(analytic)));
                        }
                        worst = @max(worst, best);
                    }
                }
            }
        }
    }
    std.debug.print("\n  G54 (a) [{s}] worst relative sensitivity error {e:.3} over {d} parameters, smallest |ds/dtheta| {e:.3}\n", .{
        @tagName(builtin.mode), worst, N, smallest,
    });
    try testing.expect(worst < thresholds.OBS7_SENSITIVITY);
}

test "G54 (a) mutation: the sensitivity ODE without its J·s coupling still points the right way and is wrong" {
    // ṡ = ∂f/∂θ + J·s. Drop the second term and s becomes the naive
    // "accumulate the direct effect" derivative — same sign, same order of
    // magnitude, and increasingly wrong as the trajectory lengthens,
    // because it ignores that moving a coefficient moves the PATH. This is
    // G49 (a)'s own mutation, carried across to the library's parameters.
    const p32 = truth(7, 0.3);
    var p: [N]f64 = undefined;
    for (&p, p32) |*a, b| a.* = b;
    var worst_short: f64 = 0;
    var worst_long: f64 = 0;
    for ([_][2]f64{ .{ 0.35, 0.45 }, .{ 0.82, 0.75 } }) |x| {
        for ([_]u32{ 8, 64 }) |steps| {
            const good = trace(f64, p, x, 0.02, steps, false);
            const bad = trace(f64, p, x, 0.02, steps, true);
            for (0..N) |j| for (0..2) |a| {
                const rel = @abs(bad.s[j][a] - good.s[j][a]) / @max(1e-6, @abs(good.s[j][a]));
                if (steps == 8) worst_short = @max(worst_short, rel) else worst_long = @max(worst_long, rel);
            };
        }
    }
    std.debug.print("  G54 (a) mutation: the uncoupled derivative is off by {d:.1}% at 8 steps and {d:.1}% at 64 — it gets worse with the horizon\n", .{ 100 * worst_short, 100 * worst_long });
    try testing.expect(worst_long > worst_short);
    try testing.expect(worst_long > 0.05);
}

fn opName(k: usize) []const u8 {
    return switch (@as(Op, @enumFromInt(k))) {
        .rotation => "rotation  (NOT a gradient)",
        .divergence => "divergence    = grad |d|^2/2",
        .shear => "shear         = grad dx*dy",
        .drift_x => "drift x       = grad x",
        .drift_y => "drift y       = grad y",
    };
}

test "G54 (b) operator inference: what a library recovers, and what it cannot" {
    // The note's §27, on the rig that already had a hidden operator in it.
    // Its stated success criterion is "the true coefficient converges to
    // its value while irrelevant coefficients approach zero", and only the
    // first half can happen here. `tools/obs7_predict.py` says why before
    // the run: the learner is ALREADY fitting a pure gradient field, so any
    // candidate that is itself a gradient is competing for the same
    // explanation. Four of the five are. Helmholtz, not optimisation.
    //
    // Coefficients are reported as the RMS VELOCITY they contribute over
    // the sampled square, theta_k * opUnit(k), because a raw coefficient is
    // not comparable across operators of different shape. The unit is
    // closed form from the sensor design, not sampled.
    const OMEGA: f32 = 0.3; // OBS-3 and OBS-4's own value
    var contribution: [OPS][SEEDS.len]f64 = .{.{0} ** SEEDS.len} ** OPS;
    var with_library: f64 = 0;
    var incomplete: f64 = 0;
    var null_rot: f64 = 0;
    var omega_err: f64 = 0;

    std.debug.print("\n  G54 (b) [{s}] truth = potential + rotation {d}; the learner is told neither\n", .{ @tagName(builtin.mode), OMEGA });
    std.debug.print("  {s:<30} {s:>10} {s:>10} {s:>10}   (RMS velocity contributed)\n", .{ "operator", "seed 7", "seed 19", "seed 41" });

    for (SEEDS, 0..) |seed, si| {
        const data = Data.init(seed, OMEGA);
        const full = fit(&data, fullMask(), STEPS);
        const only = fit(&data, potentialOnly(), STEPS);
        with_library += full.held * full.held;
        incomplete += only.held * only.held;
        omega_err += @abs(@as(f64, full.p[POT + @intFromEnum(Op.rotation)]) - OMEGA) / OMEGA;
        for (0..OPS) |k| contribution[k][si] = @as(f64, full.p[POT + k]) * opUnit(k);

        // The null: the same library against a truth with NO rotation. §27's
        // second half, on the one candidate that is identifiable at all.
        const clean = Data.init(seed, 0);
        const cf = fit(&clean, fullMask(), STEPS);
        null_rot = @max(null_rot, @abs(@as(f64, cf.p[POT + @intFromEnum(Op.rotation)])) * opUnit(@intFromEnum(Op.rotation)));
    }

    var cv: [OPS]f64 = undefined;
    for (0..OPS) |k| {
        const sp = Spread.of(&contribution[k]);
        cv[k] = sp.cv;
        std.debug.print("  {s:<30} {d:>10.5} {d:>10.5} {d:>10.5}   CV {d:.3}\n", .{
            opName(k), contribution[k][0], contribution[k][1], contribution[k][2], sp.cv,
        });
    }

    const truth_contribution = @as(f64, OMEGA) * opUnit(@intFromEnum(Op.rotation));
    var curl_free_cv: f64 = 0;
    for (1..OPS) |k| curl_free_cv += cv[k] / @as(f64, OPS - 1);
    const rel_err = omega_err / SEEDS.len;
    const predict = @sqrt(with_library / incomplete);

    std.debug.print("  the truth's rotation contributes {d:.5}; recovered to {d:.1}% \n", .{ truth_contribution, 100 * rel_err });
    std.debug.print("  across-seed CV: rotation {d:.3}, curl-free mean {d:.3} — a factor of {d:.1}\n", .{ cv[0], curl_free_cv, curl_free_cv / @max(1e-9, cv[0]) });
    std.debug.print("  held-out endpoint RMS, library over incomplete law: {d:.4}\n", .{predict});
    std.debug.print("  the null — truth with NO rotation, worst recovered rotation {d:.6} against a bar of {d:.6}\n", .{ null_rot, 0.1 * truth_contribution });

    // (a) §27's first half.
    try testing.expect(rel_err < thresholds.OBS7_RECOVERY);
    // (b) and its second half, on the operator that can satisfy it.
    try testing.expect(null_rot < 0.1 * truth_contribution);
    // (c) **REFUTED, and the statistic was flawed as well as the
    // prediction.** A coefficient of variation on a near-zero quantity is
    // always about one, so `OBS7_IDENTIFIABLE` "passed" at a factor of
    // 15 408 for a reason that has nothing to do with degeneracy: the
    // curl-free contributions are TINY (the largest is 0.00704, 8% of the
    // rotation's, and three of the four are under 0.3%), and a CV cannot
    // tell "arbitrary" from "correctly zero".
    //
    // So §27's success criterion HOLDS in full here — the true coefficient
    // is recovered and the irrelevant ones do approach zero — and the
    // Helmholtz argument that said it could not was too crude. G54 (c)
    // measures what actually governs it. What is asserted here instead is
    // the magnitude statement, which is what §27 asks for:
    var worst_curl_free_contribution: f64 = 0;
    for (1..OPS) |k| for (contribution[k]) |c| {
        worst_curl_free_contribution = @max(worst_curl_free_contribution, @abs(c));
    };
    std.debug.print("  the largest curl-free contribution is {d:.5}, {d:.1}% of the rotation's — §27's criterion HOLDS\n", .{
        worst_curl_free_contribution, 100 * worst_curl_free_contribution / truth_contribution,
    });
    try testing.expect(worst_curl_free_contribution < thresholds.OBS7_IRRELEVANT * truth_contribution);
    // (d) and it does not matter for prediction.
    try testing.expect(predict < thresholds.OBS7_PREDICTS);
}

// ── OBS-8: the geometry of degeneracy ─────────────────────────────────

/// A potential basis, as a lattice of isotropic Gaussians. OBS-7's is
/// `OBS7_BASIS` below and every gate before this one uses it.
pub const Spec = struct {
    /// Kernels per axis.
    n: u32,
    /// The lattice's span, per axis.
    lo: f32,
    hi: f32,
    /// Kernel width as a multiple of the lattice spacing. OBS-7's basis is
    /// sigma .22 at spacing .25, so .88 — heavily overlapping.
    sigma_over_h: f32,
    /// Deterministic per-kernel displacement, in spacings. Zero is the
    /// perfect lattice; non-zero BREAKS THE SYMMETRY, which G55 (a) needs
    /// because a symmetric basis makes the residualised library exactly
    /// diagonal and hides the very coupling the Gram exists to show.
    /// A learned MARL basis is never symmetric, so this is the ordinary
    /// case and the lattice is the special one.
    jitter: f32 = 0,

    pub fn count(self: Spec) usize {
        return @as(usize, self.n) * self.n;
    }
    pub fn h(self: Spec) f32 {
        return if (self.n < 2) (self.hi - self.lo) else (self.hi - self.lo) / @as(f32, @floatFromInt(self.n - 1));
    }
    pub fn sigma(self: Spec) f32 {
        return self.sigma_over_h * self.h();
    }
    pub fn shape(self: Spec, i: usize) marl.Shape {
        const step = self.h();
        const inv = 1.0 / self.sigma();
        var jx: f32 = 0;
        var jy: f32 = 0;
        if (self.jitter != 0) {
            var st = rng.Stream.region(0x4f38_4a54, @intCast(i), 0); // "O8JT"
            jx = (2 * st.unit() - 1) * self.jitter * step;
            jy = (2 * st.unit() - 1) * self.jitter * step;
        }
        return .{
            .mu = .{
                self.lo + step * @as(f32, @floatFromInt(i % self.n)) + jx,
                self.lo + step * @as(f32, @floatFromInt(i / self.n)) + jy,
                0.5,
            },
            .l = .{ inv, 0, inv, 0, 0, inv },
        };
    }
};

/// OBS-7's basis, term for term with `inferred.shape`: 3x3 on [.25,.75],
/// spacing .25, sigma .22.
pub const OBS7_BASIS = Spec{ .n = 3, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.22 / 0.25 };

/// The sampled square — `observational_windows.start`'s range, and the
/// measure every inner product below is taken under. It is load-bearing:
/// the library is orthogonal because this region is SYMMETRIC, and on a
/// clustered or asymmetric sensor region it would not be.
/// The region the inner products are taken over — the SAMPLING MEASURE,
/// and G55 (c) is the demonstration that it is not a detail.
///
/// A gradient and a rotation are orthogonal on a region only up to a
/// BOUNDARY TERM: ∫∇ψ·V = ∮ψ(V·n) − ∫ψ∇·V, and a rigid rotation is
/// divergence-free, so the overlap is exactly the boundary integral. On a
/// DISC centred on the rotation's axis, V is tangential everywhere on the
/// boundary and the term vanishes identically. On a SQUARE it does not.
pub const Region = enum { square, disc };

/// A disc of the same area as the sampled square, so the two regions are
/// compared at equal measure rather than equal diameter: r = 0.7/√π.
pub const DISC_R: f64 = 0.39493284;

pub const SAMPLE_LO: f64 = 0.15;
pub const SAMPLE_HI: f64 = 0.85;
const GRID: usize = 41;
const MAX_POT: usize = 81;

/// What the geometry says about a library, before any fitting.
pub const Analysis = struct {
    /// ‖(I − P_Φ)gₖ‖ / ‖gₖ‖ — how much of candidate k the basis CANNOT
    /// already produce. One is completely novel, zero is fully absorbed.
    novelty: [OPS]f64,
    /// The raw library's own Gram, normalised. Identity to quadrature
    /// error on a symmetric region, which is what makes `residual` a clean
    /// readout of the BASIS rather than of the library.
    raw: [OPS][OPS]f64,
    /// The residualised Gram, normalised to unit diagonal — mutual
    /// collinearity with the magnitudes divided out.
    residual: [OPS][OPS]f64,
    /// Condition of the residualised Gram as it stands: dominated by the
    /// spread of novelties, so it answers "is one candidate nearly
    /// invisible".
    cond_novelty: f64,
    /// Condition of the same after normalising every residual to unit
    /// length: mutual collinearity alone.
    cond_collinear: f64,
};

fn worstOff(m: [OPS][OPS]f64) f64 {
    var w: f64 = 0;
    for (0..OPS) |i| for (0..OPS) |j| {
        if (i != j) w = @max(w, @abs(m[i][j]));
    };
    return w;
}

/// Condition number of a symmetric positive-semidefinite matrix, by cyclic
/// Jacobi. Small and exact enough at 5x5, and it avoids pulling in a
/// dependency for one eigenvalue ratio.
fn condOf(min: [OPS][OPS]f64) f64 {
    var a = min;
    var sweep: usize = 0;
    while (sweep < 60) : (sweep += 1) {
        var off: f64 = 0;
        for (0..OPS) |i| for (i + 1..OPS) |j| {
            off += a[i][j] * a[i][j];
        };
        if (off < 1e-24) break;
        for (0..OPS) |p| for (p + 1..OPS) |q| {
            if (@abs(a[p][q]) < 1e-30) continue;
            const theta = 0.5 * (a[q][q] - a[p][p]) / a[p][q];
            // sign(0) must be +1, not 0. A CORRELATION matrix has a unit
            // diagonal, so theta is EXACTLY zero for every pair, and with
            // `std.math.sign` the rotation angle came out zero, the sweep
            // did nothing, and `cond_collinear` returned 1.0000 for every
            // matrix it was ever given — including one carrying a 0.699
            // off-diagonal, which is what gave it away. The correct
            // convention makes theta = 0 a 45-degree rotation, which is
            // exactly the case a correlation matrix always presents.
            const sgn: f64 = if (theta >= 0) 1 else -1;
            const t = sgn / (@abs(theta) + @sqrt(theta * theta + 1));
            const c = 1 / @sqrt(t * t + 1);
            const sn = t * c;
            for (0..OPS) |k| {
                const akp = a[k][p];
                const akq = a[k][q];
                a[k][p] = c * akp - sn * akq;
                a[k][q] = sn * akp + c * akq;
            }
            for (0..OPS) |k| {
                const apk = a[p][k];
                const aqk = a[q][k];
                a[p][k] = c * apk - sn * aqk;
                a[q][k] = sn * apk + c * aqk;
            }
        };
    }
    var lo: f64 = std.math.inf(f64);
    var hi: f64 = 0;
    for (0..OPS) |i| {
        const e = @abs(a[i][i]);
        lo = @min(lo, e);
        hi = @max(hi, e);
    }
    return if (lo < 1e-30) std.math.inf(f64) else hi / lo;
}

/// Residualise the whole library against a basis and report what the
/// geometry knows before a single coefficient is learned.
///
/// Christian's extension of `degeneracy`: instead of scoring candidates one
/// at a time, form G̃ = (I − P_Φ)G and inspect its Gram. Novelty comes off
/// the diagonal and mutual identifiability off the spectrum — because two
/// candidates can both sit well outside the potential's span and still be
/// nearly collinear with each other, which a per-candidate residual cannot
/// see.
///
/// The inner products use the identity ⟨rᵢ, rⱼ⟩ = ⟨vᵢ, vⱼ⟩ − wᵢᵀ(Aᵀvⱼ),
/// which follows from AᵀA wᵢ = Aᵀvᵢ at the least-squares optimum. So the
/// design matrix is factored once for the whole library rather than per
/// candidate.
pub fn analyse(spec: Spec, region: Region) Analysis {
    const P = spec.count();
    std.debug.assert(P <= MAX_POT);
    var ata = [_][MAX_POT]f64{.{0} ** MAX_POT} ** MAX_POT;
    var atv = [_][OPS]f64{.{0} ** OPS} ** MAX_POT;
    var vv = [_][OPS]f64{.{0} ** OPS} ** OPS;

    // The disc is sampled over ITS OWN bounding box. Written against the
    // square's it is clipped at four chords — a disc with its corners cut
    // off, whose boundary is partly straight, where V·n is NOT zero. The
    // whole point of the disc is that its boundary is a streamline of the
    // rotation, and a clipped one is not. Measured before the fix: 0.9868
    // where the true disc gives 0.9955.
    const lo: f64 = if (region == .disc) 0.5 - DISC_R else SAMPLE_LO;
    const hi: f64 = if (region == .disc) 0.5 + DISC_R else SAMPLE_HI;
    for (0..GRID) |gi| {
        for (0..GRID) |gj| {
            const x = [2]f64{
                lo + (hi - lo) * @as(f64, @floatFromInt(gi)) / @as(f64, GRID - 1),
                lo + (hi - lo) * @as(f64, @floatFromInt(gj)) / @as(f64, GRID - 1),
            };
            if (region == .disc) {
                const rx = x[0] - 0.5;
                const ry = x[1] - 0.5;
                if (rx * rx + ry * ry > DISC_R * DISC_R) continue;
            }
            var row: [MAX_POT][2]f64 = undefined;
            for (0..P) |i| {
                const sh = spec.shape(i);
                const inv: f64 = @as(f64, sh.l[0]) * @as(f64, sh.l[0]);
                const d = [2]f64{ x[0] - @as(f64, sh.mu[0]), x[1] - @as(f64, sh.mu[1]) };
                const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
                if (r2 > marl.CUTOFF) {
                    row[i] = .{ 0, 0 };
                    continue;
                }
                const phi = @exp(-0.5 * r2);
                // A unit of wᵢ adds −∇φᵢ to the velocity.
                for (0..2) |a| row[i][a] = phi * inv * d[a];
            }
            var v: [OPS][2]f64 = undefined;
            for (0..OPS) |k| v[k] = opVelocity(f64, k, x);
            for (0..2) |a| {
                for (0..OPS) |k| for (0..OPS) |l| {
                    vv[k][l] += v[k][a] * v[l][a];
                };
                for (0..P) |i| {
                    for (0..OPS) |k| atv[i][k] += row[i][a] * v[k][a];
                    for (0..P) |j| ata[i][j] += row[i][a] * row[j][a];
                }
            }
        }
    }

    // A pinch of ridge, so a rank-deficient normal matrix cannot make a
    // residual look small by way of an enormous coefficient.
    var tr: f64 = 0;
    for (0..P) |i| tr += ata[i][i];
    for (0..P) |i| ata[i][i] += 1e-9 * tr / @as(f64, @floatFromInt(P));

    // One LU for the whole library.
    var a = ata;
    var perm: [MAX_POT]usize = undefined;
    for (0..P) |i| perm[i] = i;
    for (0..P) |c| {
        var piv = c;
        for (c + 1..P) |r| if (@abs(a[r][c]) > @abs(a[piv][c])) {
            piv = r;
        };
        std.mem.swap([MAX_POT]f64, &a[c], &a[piv]);
        std.mem.swap(usize, &perm[c], &perm[piv]);
        for (c + 1..P) |r| {
            const f = a[r][c] / a[c][c];
            a[r][c] = f;
            for (c + 1..P) |cc| a[r][cc] -= f * a[c][cc];
        }
    }
    var w = [_][OPS]f64{.{0} ** OPS} ** MAX_POT;
    for (0..OPS) |k| {
        var b: [MAX_POT]f64 = undefined;
        for (0..P) |i| b[i] = atv[perm[i]][k];
        for (0..P) |r| for (0..r) |c| {
            b[r] -= a[r][c] * b[c];
        };
        var i = P;
        while (i > 0) {
            i -= 1;
            var acc = b[i];
            for (i + 1..P) |j| acc -= a[i][j] * w[j][k];
            w[i][k] = acc / a[i][i];
        }
    }

    var out: Analysis = undefined;
    var h: [OPS][OPS]f64 = undefined;
    for (0..OPS) |k| for (0..OPS) |l| {
        var dot: f64 = 0;
        for (0..P) |i| dot += w[i][k] * atv[i][l];
        h[k][l] = vv[k][l] - dot;
    };
    for (0..OPS) |k| {
        out.novelty[k] = @sqrt(@max(0, h[k][k]) / vv[k][k]);
        for (0..OPS) |l| out.raw[k][l] = vv[k][l] / @sqrt(vv[k][k] * vv[l][l]);
    }
    for (0..OPS) |k| for (0..OPS) |l| {
        const den = @sqrt(@max(1e-300, h[k][k] * h[l][l]));
        out.residual[k][l] = h[k][l] / den;
    };
    // Symmetrise: the identity above is exact in reals and the two halves
    // differ in the last places, and a Jacobi sweep on a matrix that is not
    // quite symmetric is not measuring an eigenvalue.
    var sym = h;
    for (0..OPS) |k| for (0..OPS) |l| {
        sym[k][l] = 0.5 * (h[k][l] + h[l][k]);
    };
    out.cond_novelty = condOf(sym);
    var norm = out.residual;
    for (0..OPS) |k| for (0..OPS) |l| {
        norm[k][l] = 0.5 * (out.residual[k][l] + out.residual[l][k]);
    };
    out.cond_collinear = condOf(norm);
    return out;
}

/// How much of candidate k's velocity field the POTENTIAL BASIS can
/// already produce — measured directly, with no learner anywhere in it.
///
/// This is MARL-23's move, one campaign over: separate what the BASIS can
/// do from what the LEARNER finds. G54 (b) turned on a Helmholtz argument —
/// four of the five candidates are themselves gradients, so a learner
/// already fitting `−∇Σwᵢφᵢ` should be free to put them either place — and
/// the argument was too crude. Being a gradient is necessary for the
/// degeneracy and nowhere near sufficient: what matters is whether the
/// candidate's own potential lies in the SPAN OF THE KERNELS, over the
/// region that is actually sampled.
///
/// One line, because OBS-8 generalised this into `analyse` and two
/// functions computing the same quantity by different quadratures would be
/// two truths about it.
pub fn degeneracy(k: usize) f64 {
    return analyse(OBS7_BASIS, .square).novelty[k];
}

test "G54 (c) what governs level 3 is not whether a candidate is a gradient, but whether the basis can already make it" {
    // G54 (b)'s Helmholtz prediction was REFUTED: the four curl-free
    // candidates went essentially to zero rather than absorbing signal, so
    // §27's success criterion held in full. This is why, and it is measured
    // with no learner in it at all.
    //
    // Being a gradient is NECESSARY for the degeneracy and nowhere near
    // SUFFICIENT. Nine isotropic Gaussians of sigma .22 on a 3x3 lattice
    // over [.25,.75] are a poor basis for a global linear ramp or a
    // quadratic bowl across [.15,.85] — the candidate's potential has to
    // lie in their span, and it mostly does not.
    std.debug.print("\n  G54 (c) [{s}] how much of each candidate the potential basis can already produce\n", .{@tagName(builtin.mode)});
    std.debug.print("  {s:<30} {s:>12}  {s}\n", .{ "candidate", "residual", "what it means" });
    var res: [OPS]f64 = undefined;
    for (0..OPS) |k| {
        res[k] = degeneracy(k);
        std.debug.print("  {s:<30} {d:>12.4}  {s}\n", .{
            opName(k), res[k],
            if (res[k] > 0.5) "identifiable" else if (res[k] > 0.2) "partly absorbed" else "degenerate",
        });
    }
    // A rotation cannot be produced by a curl-free span AT ALL, so its
    // residual must be one. It comes back 1.0000 — a derivation confirmed
    // to four places, and the reason the rotation was recovered exactly in
    // G54 (b).
    try testing.expect(res[0] > 0.99);

    // **The finding: the curl-free candidates do not behave alike.** The
    // basis absorbs 90% of a radial expansion and almost none of a saddle
    // or a ramp. Being a gradient is necessary and nowhere near sufficient;
    // what decides is whether the candidate's potential is SMOOTH AT THE
    // BASIS'S OWN SCALE. A bowl is. A saddle needs a sign change at the
    // centre that nine kernels of sigma .22 on a .25 lattice are badly
    // conditioned for, and a linear ramp needs support past the lattice's
    // edge.
    var most_degenerate: usize = 1;
    var least: usize = 1;
    for (1..OPS) |k| {
        if (res[k] < res[most_degenerate]) most_degenerate = k;
        if (res[k] > res[least]) least = k;
    }
    try testing.expect(res[most_degenerate] < 0.2);
    try testing.expect(res[least] > 0.5);

    // And the correspondence that makes this an explanation rather than a
    // coincidence: the candidate the basis can absorb is the SAME candidate
    // whose recovered coefficient was largest in G54 (b). Measured here
    // rather than read across from that gate's printout, because a
    // comparison assembled from two gates is one nobody re-runs.
    const data = Data.init(SEEDS[0], 0.3);
    const full = fit(&data, fullMask(), STEPS);
    var largest: usize = 1;
    for (1..OPS) |k| {
        if (@abs(full.p[POT + k]) * opUnit(k) > @abs(full.p[POT + largest]) * opUnit(largest)) largest = k;
    }
    std.debug.print("  the basis absorbs {s} most (residual {d:.4}), and it is {s} whose coefficient the fit moves most\n", .{
        opName(most_degenerate), res[most_degenerate], opName(largest),
    });
    try testing.expectEqual(most_degenerate, largest);
}

test "G55 (a) the residualised Gram is diagonal by SYMMETRY, and a learned basis would not be" {
    // Christian's extension of `degeneracy`: residualise the whole library
    // and read its Gram, because two candidates can both sit well outside
    // the potential's span and still be nearly collinear with each other.
    // The idea is right and this fixture cannot show it, which is the
    // finding.
    //
    // The raw library is exactly orthogonal on the symmetric sampling
    // square — E[dx] = E[dy] = E[dx·dy] = 0 with E[dx²] = E[dy²] — so the
    // pre-registration predicted every off-diagonal AFTER residualisation
    // would be the BASIS's doing, and asked for one above 0.02.
    //
    // **REFUTED at 0.0000, and for a better reason than the prediction
    // had.** ⟨(I−P)vᵢ, (I−P)vⱼ⟩ = ⟨vᵢ,vⱼ⟩ − ⟨Pvᵢ, Pvⱼ⟩, so the coupling is
    // the overlap of the PROJECTIONS. A square lattice of isotropic
    // kernels on a square region is invariant under D4, the projector
    // commutes with that group, and the five candidates sit in different
    // irreducible representations of it — drift x and y sharing one, where
    // Schur makes P a scalar. Functions in different irreps are orthogonal,
    // and P cannot mix them. The residualised Gram is diagonal EXACTLY, at
    // every basis on both sweeps.
    //
    // So the mutual-identifiability channel is invisible on a symmetric
    // fixture and live the moment the symmetry goes. **A learned MARL basis
    // is never symmetric** — kernels move — so the lattice is the special
    // case and the coupling is the ordinary one. Jittering the centres is
    // enough to show it.
    const a = analyse(OBS7_BASIS, .square);
    std.debug.print("\n  G55 (a) [{s}] at OBS-7's basis (3x3 on [.25,.75], sigma .22)\n", .{@tagName(builtin.mode)});
    std.debug.print("  {s:<30} {s:>9}   {s}\n", .{ "candidate", "novelty", "residualised Gram, normalised" });
    for (0..OPS) |k| {
        std.debug.print("  {s:<30} {d:>9.4}  ", .{ opName(k), a.novelty[k] });
        for (0..OPS) |l| std.debug.print(" {d:>7.3}", .{a.residual[k][l]});
        std.debug.print("\n", .{});
    }
    std.debug.print("  worst off-diagonal: raw {e:.2}, residualised {e:.2} — both zero, by D4\n", .{ worstOff(a.raw), worstOff(a.residual) });
    std.debug.print("  condition — novelty spread {d:.1}, mutual collinearity {d:.4}\n", .{ a.cond_novelty, a.cond_collinear });

    // Break the symmetry and the coupling appears. This is the ordinary
    // case, not the exception.
    var jittered = OBS7_BASIS;
    jittered.jitter = 0.25;
    const j = analyse(jittered, .square);
    std.debug.print("  centres jittered by a quarter of a spacing:\n", .{});
    for (0..OPS) |k| {
        std.debug.print("  {s:<30} {d:>9.4}  ", .{ opName(k), j.novelty[k] });
        for (0..OPS) |l| std.debug.print(" {d:>7.3}", .{j.residual[k][l]});
        std.debug.print("\n", .{});
    }
    std.debug.print("  worst off-diagonal {d:.4}, mutual collinearity {d:.4}\n", .{ worstOff(j.residual), j.cond_collinear });

    // The derivation: the raw library is the identity on this region.
    try testing.expect(worstOff(a.raw) < 1e-6);
    try testing.expect(@abs(condOf(a.raw) - 1) < 1e-6);
    // A symmetric basis adds no coupling at all...
    try testing.expect(worstOff(a.residual) < 1e-3);
    // ...and an asymmetric one does, which is what a learned basis is.
    try testing.expect(worstOff(j.residual) > thresholds.OBS8_BASIS_COUPLING);
    // The conditioning must agree with the off-diagonals, which is how the
    // eigensolver's sign convention was caught: a correlation matrix has a
    // unit diagonal, `std.math.sign(0)` is 0, and the Jacobi rotation angle
    // came out zero, so `cond_collinear` returned 1.0000 beside a 0.699
    // coupling. Asserting both together is what makes that impossible to
    // reintroduce.
    try testing.expect(a.cond_collinear < 1.001);
    try testing.expect(j.cond_collinear > 2);
}

/// AXIS A — refine the lattice at a FIXED overlap ratio, so the kernels
/// narrow as the spacing does. Same support, finer structure.
const AXIS_A = [_]Spec{
    .{ .n = 3, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.88 },
    .{ .n = 4, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.88 },
    .{ .n = 5, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.88 },
    .{ .n = 6, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.88 },
    .{ .n = 8, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.88 },
};
/// AXIS B — add rings at OBS-7's own spacing and width. Same resolution,
/// more support; at n = 5 the lattice covers [0,1] outright.
const AXIS_B = [_]Spec{
    .{ .n = 3, .lo = 0.25, .hi = 0.75, .sigma_over_h = 0.88 },
    .{ .n = 5, .lo = 0.00, .hi = 1.00, .sigma_over_h = 0.88 },
    .{ .n = 7, .lo = -0.25, .hi = 1.25, .sigma_over_h = 0.88 },
};

test "G55 (b) resolution and support are different axes, and only one of them absorbs an operator" {
    // Christian's prediction: the bowl goes as a scale issue, the saddle
    // collapses once the basis resolves its central sign structure, and the
    // ramp improves disproportionately with support. Registered as an
    // interaction so that "a richer basis absorbs more" could not pass.
    //
    // **The interaction is REFUTED, and axis A turned out to be the wrong
    // axis.** Holding sigma/h fixed while refining the lattice makes the
    // kernels NARROWER, and a basis of narrow kernels over a small span is
    // WORSE at a smooth global field than a basis of wide ones. Novelty
    // RISES along axis A for every curl-free candidate. Resolution and
    // smoothness-scale are not the same knob, and this sweep conflated them.
    //
    // Axis B is unambiguous and overwhelming: at OBS-7's own spacing and
    // width, one ring takes the saddle from .7355 to .0798 and the ramp
    // from .7320 to .0789. **Support is the mechanism.** The bowl was
    // already absorbed at .0967 because it is the one candidate whose
    // potential is concentrated where the lattice already is.
    std.debug.print("\n  G55 (b) [{s}] novelty, by basis\n", .{@tagName(builtin.mode)});
    var a_nov: [AXIS_A.len][OPS]f64 = undefined;
    var b_nov: [AXIS_B.len][OPS]f64 = undefined;

    std.debug.print("  {s:<38}", .{"AXIS A — resolution, span [.25,.75]"});
    for (0..OPS) |k| std.debug.print(" {s:>10}", .{@tagName(@as(Op, @enumFromInt(k)))});
    std.debug.print("\n", .{});
    for (AXIS_A, 0..) |spec, si| {
        const an = analyse(spec, .square);
        a_nov[si] = an.novelty;
        std.debug.print("  n={d} h={d:.4} sigma={d:.4} ({d:>2} kernels)   ", .{ spec.n, spec.h(), spec.sigma(), spec.count() });
        for (0..OPS) |k| std.debug.print(" {d:>10.4}", .{an.novelty[k]});
        std.debug.print("\n", .{});
    }
    std.debug.print("  {s:<38}\n", .{"AXIS B — support, spacing .25 sigma .22"});
    for (AXIS_B, 0..) |spec, si| {
        const an = analyse(spec, .square);
        b_nov[si] = an.novelty;
        std.debug.print("  span [{d:.2},{d:.2}] ({d:>2} kernels)            ", .{ spec.lo, spec.hi, spec.count() });
        for (0..OPS) |k| std.debug.print(" {d:>10.4}", .{an.novelty[k]});
        std.debug.print("\n", .{});
    }

    // Support absorbs; refining at fixed overlap does not. Asserted on the
    // curl-free candidates, which are the ones that CAN be absorbed at all.
    var worst_a_drop: f64 = 1;
    var worst_b_drop: f64 = 0;
    for (1..OPS) |k| {
        worst_a_drop = @min(worst_a_drop, 1 - a_nov[2][k] / a_nov[0][k]);
        worst_b_drop = @max(worst_b_drop, 1 - b_nov[1][k] / b_nov[0][k]);
    }
    std.debug.print("  one step of each: axis A drops novelty by at most {d:.4}, axis B by at least {d:.4}\n", .{ worst_a_drop, worst_b_drop });
    try testing.expect(worst_b_drop > thresholds.OBS8_SUPPORT_DOMINATES);
    try testing.expect(worst_b_drop > worst_a_drop);
}

test "G55 (c) an operator's independence is a property of the REGION, not only of the fields" {
    // The pre-registration called the rotation's novelty an INVARIANT: a
    // potential's gradient is curl-free at any resolution and any support,
    // a rotation has curl 2, so no enrichment could ever confuse them.
    //
    // **REFUTED. On the square it falls to 0.918** once the lattice reaches
    // the boundary — and the reason is the part of Helmholtz that gets
    // dropped when the argument is made on the whole plane:
    //
    //     ∫_Ω ∇ψ · V = ∮_∂Ω ψ (V·n) − ∫_Ω ψ (∇·V)
    //
    // A rigid rotation is divergence-free, so the second term vanishes and
    // the overlap between any potential and the rotation is EXACTLY the
    // boundary integral. At the 3x3 basis the kernels decay before the
    // edge, ψ ≈ 0 there, and the residual is 1.0000. Enlarge the lattice,
    // ψ stops vanishing on ∂Ω, and a gradient acquires overlap with a
    // rotation.
    //
    // The discriminator is the region's shape rather than the basis. On a
    // DISC centred on the rotation's axis, V is tangential everywhere on
    // the boundary, V·n ≡ 0, and the term vanishes identically at every
    // basis. Same library, same kernels, same area — different answer.
    //
    // Which is Christian's refinement of OBS-7's sentence vindicated more
    // strongly than the argument he made it with: **locally identifiable
    // under the chosen SAMPLING MEASURE and basis.**
    std.debug.print("\n  G55 (c) [{s}] the rotation's novelty, square against a disc of equal area (r = {d:.4})\n", .{ @tagName(builtin.mode), DISC_R });
    std.debug.print("  {s:<34} {s:>10} {s:>10}\n", .{ "basis", "square", "disc" });
    var worst_square: f64 = 1;
    var worst_disc: f64 = 1;
    for (AXIS_B) |spec| {
        const sq = analyse(spec, .square).novelty[@intFromEnum(Op.rotation)];
        const di = analyse(spec, .disc).novelty[@intFromEnum(Op.rotation)];
        worst_square = @min(worst_square, sq);
        worst_disc = @min(worst_disc, di);
        std.debug.print("  span [{d:.2},{d:.2}] ({d:>2} kernels){s:<10} {d:>10.4} {d:>10.4}\n", .{ spec.lo, spec.hi, spec.count(), "", sq, di });
    }
    std.debug.print("  worst over the sweep: square {d:.4}, disc {d:.4} — the boundary term, and nothing else\n", .{ worst_square, worst_disc });
    // On the square the "invariant" is broken outright.
    try testing.expect(worst_square < thresholds.OBS8_ROTATION_INVARIANT);
    // On the disc it holds, because V·n is identically zero there.
    try testing.expect(worst_disc > thresholds.OBS8_ROTATION_DISC);
}
