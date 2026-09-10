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

/// How much of candidate k's velocity field the POTENTIAL BASIS can
/// already produce — measured directly, with no learner anywhere in it.
///
/// This is MARL-23's move, one campaign over: separate what the BASIS can
/// do from what the LEARNER finds. G54 (b) turned on a Helmholtz argument —
/// four of the five candidates are themselves gradients, so a learner
/// already fitting `−∇Σwᵢφᵢ` should be free to put them either place — and
/// the argument was too crude. Being a gradient is necessary for the
/// degeneracy and nowhere near sufficient: what matters is whether the
/// candidate's own potential lies in the SPAN OF NINE GAUSSIANS, over the
/// square that is actually sampled.
///
/// So: least squares over a grid on the sampled square,
///
///     min over w of  ‖ V_k − Σᵢ wᵢ (−∇φᵢ) ‖
///
/// returning the residual as a fraction of ‖V_k‖. One means the basis
/// cannot imitate the candidate at all and the coefficient is cleanly
/// identifiable; zero means it can imitate it exactly and the split is
/// arbitrary. No optimiser, no observations, no trajectories — this is a
/// property of the model class and the sensor region, and it is what
/// governs whether §27's success criterion can hold.
pub fn degeneracy(k: usize) f64 {
    const G: usize = 21;
    var ata = [_][POT]f64{.{0} ** POT} ** POT;
    var atb = [_]f64{0} ** POT;
    var bb: f64 = 0;
    for (0..G) |gi| {
        for (0..G) |gj| {
            const x = [2]f64{
                0.15 + 0.7 * @as(f64, @floatFromInt(gi)) / @as(f64, G - 1),
                0.15 + 0.7 * @as(f64, @floatFromInt(gj)) / @as(f64, G - 1),
            };
            const v = opVelocity(f64, k, x);
            // The basis row: −∇φᵢ at x, which is what a unit of wᵢ adds to
            // the velocity.
            var row: [POT][2]f64 = undefined;
            for (0..POT) |i| {
                const sh = inferred.shape(i);
                const inv: f64 = @as(f64, sh.l[0]) * @as(f64, sh.l[0]);
                const d = [2]f64{ x[0] - @as(f64, sh.mu[0]), x[1] - @as(f64, sh.mu[1]) };
                const r2 = inv * (d[0] * d[0] + d[1] * d[1]);
                if (r2 > marl.CUTOFF) {
                    row[i] = .{ 0, 0 };
                    continue;
                }
                const phi = @exp(-0.5 * r2);
                for (0..2) |a| row[i][a] = phi * inv * d[a];
            }
            for (0..2) |a| {
                bb += v[a] * v[a];
                for (0..POT) |i| {
                    atb[i] += row[i][a] * v[a];
                    for (0..POT) |j| ata[i][j] += row[i][a] * row[j][a];
                }
            }
        }
    }
    // A pinch of ridge, so a rank-deficient normal matrix cannot make the
    // residual look small by way of an enormous coefficient. It is 1e-9 of
    // the trace, far below anything that changes an honest fit.
    var tr: f64 = 0;
    for (0..POT) |i| tr += ata[i][i];
    for (0..POT) |i| ata[i][i] += 1e-9 * tr / @as(f64, POT);
    // Gaussian elimination with partial pivoting.
    var w = [_]f64{0} ** POT;
    var a = ata;
    var b = atb;
    for (0..POT) |c| {
        var piv = c;
        for (c + 1..POT) |r| if (@abs(a[r][c]) > @abs(a[piv][c])) {
            piv = r;
        };
        std.mem.swap([POT]f64, &a[c], &a[piv]);
        std.mem.swap(f64, &b[c], &b[piv]);
        for (c + 1..POT) |r| {
            const f = a[r][c] / a[c][c];
            for (c..POT) |cc| a[r][cc] -= f * a[c][cc];
            b[r] -= f * b[c];
        }
    }
    var i = POT;
    while (i > 0) {
        i -= 1;
        var acc = b[i];
        for (i + 1..POT) |j| acc -= a[i][j] * w[j];
        w[i] = acc / a[i][i];
    }
    // ‖V − Aw‖² = ‖V‖² − 2wᵀAᵀV + wᵀAᵀAw, from the accumulators.
    var quad: f64 = 0;
    for (0..POT) |p| {
        quad -= 2 * w[p] * atb[p];
        for (0..POT) |q| quad += w[p] * ata[p][q] * w[q];
    }
    return @sqrt(@max(0, bb + quad) / bb);
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
