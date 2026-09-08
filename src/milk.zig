//! milk — MARL-19: the milk round, and whether a consolidation refunds the
//! capacity that HISTORY bought.
//!
//! Christian's clarification of the consolidation idea, in his words:
//!
//! > "You are told to deliver the milk on Mondays so you buy a kernel. Then
//! >  you are told to deliver the milk on Wednesday as well .. surprise, and
//! >  you buy another kernel. Then you are told to deliver milk on Tuesday
//! >  and Thursday and Friday as well, but you already have two kernels
//! >  refining the parent Milk delivery schedule kernel.
//! >
//! >  Now you have three, potentially four kernels whose sum is..
//! >  Deliver milk Monday to Friday.
//! >
//! >  The distilled student samples and never sees all the patches.. it sees
//! >  a continuous function Saturday and Sunday, no milk, Monday through
//! >  Friday, deliver the milk."
//!
//! ## Why MARL-18 could not have seen this
//!
//! MARL-18's sentence was "a sleep is worth exactly as much as there is
//! VARIANCE to remove", and its fixture gave it no alternative: one
//! stationary field, one noisy estimator, so the only thing a teacher could
//! carry that a student would not rebuild was noise. The milk round makes
//! no mention of noise. It says a model that was TOLD THE SCHEDULE IN
//! STAGES holds kernels for boundaries that no longer exist, and that their
//! sum is a simple function the student is handed directly.
//!
//! So this target is ANALYTIC AND EXACT. If a sleep still collapses the
//! population here, MARL-18's sentence is incomplete and there is a second
//! currency: history.
//!
//! ## The fixture is the analogy taken literally
//!
//! The week runs along x, seven days, with a fixed smooth amplitude in
//! (y, z) so the field is not degenerate off the axis. Three stages:
//!
//!     stage 1   Mon                   2 edges
//!     stage 2   Mon, Wed              4 edges — Tuesday is a HOLE, held down
//!     stage 3   Mon Tue Wed Thu Fri   2 edges — the hole is filled in
//!
//! Five distinct edge positions are presented over the run; the final
//! schedule has two. That gap is the history, and it is what a sleep is
//! being asked to refund. `tools/marl19_predict.py` has the numbers.
//!
//! Nothing here is on the sim path — `marl.zig`'s standing, and this file
//! imports it and is imported by nothing.

const std = @import("std");
const builtin = @import("builtin");
const marl = @import("marl.zig");
const rng = @import("rng.zig");
const fmath = @import("fmath.zig");
const thresholds = @import("thresholds.zig");

const testing = std.testing;

pub const DAYS: u32 = 7;

/// Edge softness, in days. A HARD indicator is not in a Gaussian basis's
/// hypothesis class at any capacity, so learning one would measure the
/// basis and not the history. A fifth of a day is representable and still
/// reads as a boundary.
pub const EDGE: f32 = 0.2;

/// The NESTED path: Monday, then Monday and Wednesday, then Monday to
/// Friday. A bit per day; day 1 is Monday.
///
/// This is the analogy as literally described, and G38 (a) found it costs
/// almost nothing — because nothing it learns becomes WRONG. Monday is
/// delivered at every stage, so MARL-9's law applies in its cheap
/// direction, and the Tuesday hole was ZERO, which MARL-16 established is
/// what an empty model already predicts. There was never anything there to
/// cancel.
pub const STAGES = [_]u8{
    (1 << 1),
    (1 << 1) | (1 << 3),
    (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5),
};

/// The CONTRADICTORY path: the same three stages, the same total evidence
/// and the same destination, but the round STOPS delivering Monday and
/// Tuesday before starting again. Kernels pulled down to zero stay in the
/// population, which is MARL-7's "capacity a moved world leaves behind"
/// produced on demand instead of over six drift moves.
pub const CONTRA = [_]u8{
    (1 << 1) | (1 << 2) | (1 << 3),
    (1 << 3) | (1 << 4) | (1 << 5),
    (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 5),
};

fn member(mask: u8, d: i32) bool {
    if (d < 0 or d >= @as(i32, @intCast(DAYS))) return false;
    return (mask >> @intCast(d)) & 1 != 0;
}

/// Smoothstep on [−1, 1], zero below and one above.
fn smooth(u: f32) f32 {
    if (u <= -1) return 0;
    if (u >= 1) return 1;
    const t = (u + 1) * 0.5;
    return t * t * (3 - 2 * t);
}

/// The schedule as a smooth indicator along the week.
///
/// Built from the signed distance to the nearest TRANSITION rather than by
/// summing per-day windows, because adjacent delivery days must merge into
/// one slab with no seam in the middle. A seam at Tuesday/Wednesday would
/// make "Mon–Fri" structurally complicated, and the whole premise is that
/// the destination is simple however tangled the path was.
pub fn schedule(mask: u8, x: f32) f32 {
    const t = x * @as(f32, @floatFromInt(DAYS));
    const inside = member(mask, @intFromFloat(@floor(t)));
    var near: f32 = 1e9;
    var d: i32 = 0;
    while (d <= @as(i32, @intCast(DAYS))) : (d += 1) {
        if (member(mask, d - 1) == member(mask, d)) continue;
        near = @min(near, @abs(t - @as(f32, @floatFromInt(d))));
    }
    const s = if (inside) near else -near;
    return smooth(s / EDGE);
}

/// A fixed smooth amplitude across the round: two Gaussian bumps. Without
/// it every kernel could sit anywhere on a plane of constant x and the
/// population would be measuring nothing.
pub fn amplitude(y: f32, z: f32) f32 {
    const a = fmath.expf(-8 * ((y - 0.35) * (y - 0.35) + (z - 0.40) * (z - 0.40)));
    const b = fmath.expf(-12 * ((y - 0.70) * (y - 0.70) + (z - 0.65) * (z - 0.65)));
    return 0.35 + 0.40 * a + 0.35 * b;
}

/// The delivery schedule as a field, EXACT — no estimator, no noise.
pub fn milkAt(mask: u8, p: [3]f32) f32 {
    return amplitude(p[1], p[2]) * schedule(mask, p[0]);
}

// ── Probes, arms, and a sleep ────────────────────────────────────────

pub const Probes = struct {
    x: [][3]f32,
    y: []f32,
    pub fn deinit(self: *Probes, gpa: std.mem.Allocator) void {
        gpa.free(self.x);
        gpa.free(self.y);
    }
};

/// Probes on the FINAL schedule. Every arm is scored against the schedule
/// that currently applies, because that is what a delivery round is for.
pub fn probesOf(gpa: std.mem.Allocator, mask: u8, n: u32, seed: u64) !Probes {
    var st = rng.Stream.region(seed, 0x4d494c4b, 0); // "MILK"
    var p = Probes{ .x = try gpa.alloc([3]f32, n), .y = try gpa.alloc(f32, n) };
    errdefer p.deinit(gpa);
    for (p.x, p.y) |*x, *y| {
        x.* = .{ st.unit(), st.unit(), st.unit() };
        y.* = milkAt(mask, x.*);
    }
    return p;
}

pub fn rmsOf(m: *marl.Model, pr: Probes) f32 {
    var acc: f64 = 0;
    for (pr.x, pr.y) |x, y| {
        const e = (m.predict(x) catch unreachable)[0] - y;
        acc += @as(f64, e) * @as(f64, e);
    }
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.x.len))));
}

/// The constant-predictor anchor. MARL-17 established that an RMS without
/// one is a number with no scale.
pub fn meanRms(pr: Probes) f32 {
    var s: f64 = 0;
    for (pr.y) |y| s += y;
    const mean = s / @as(f64, @floatFromInt(pr.y.len));
    var acc: f64 = 0;
    for (pr.y) |y| acc += (y - mean) * (y - mean);
    return @floatCast(@sqrt(acc / @as(f64, @floatFromInt(pr.y.len))));
}

/// Observe `n` exemplars of one stage's schedule, carrying the stream so a
/// run can be continued — the same reason `cache.teachInto` exists.
pub fn learn(m: *marl.Model, mask: u8, n: u64, st: *rng.Stream) !void {
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const x = [3]f32{ st.unit(), st.unit(), st.unit() };
        _ = try m.observe(x, .{milkAt(mask, x)});
    }
}

/// A SLEEP: a fresh model trained on the teacher's own continuous field.
/// It never sees the patches — it sees the sum.
pub fn sleep(gpa: std.mem.Allocator, teacher: *marl.Model, opts: marl.Options, n: u64, st: *rng.Stream) !marl.Model {
    var s = try marl.Model.init(gpa, opts);
    errdefer s.deinit();
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        const x = [3]f32{ st.unit(), st.unit(), st.unit() };
        const y = (try teacher.predict(x))[0];
        _ = try s.observe(x, .{y});
    }
    return s;
}

/// Mean σ over a population — `exp(−logd)` read through `shape()`, so a
/// LARGER number is a wider kernel. MARL-18 found this is the statistic
/// that shows a collapse: fewer kernels, WIDER, coverage per point
/// unchanged (it must be — the function is the same).
pub fn meanWidth(m: *const marl.Model) f64 {
    if (m.kernels.items.len == 0) return 0;
    var acc: f64 = 0;
    for (m.kernels.items) |*k| {
        const l = k.shape().l;
        acc += (1.0 / @as(f64, l[0]) + 1.0 / @as(f64, l[2]) + 1.0 / @as(f64, l[5])) / 3.0;
    }
    return acc / @as(f64, @floatFromInt(m.kernels.items.len));
}

// ── The gates ────────────────────────────────────────────────────────

test "G38 (a) the milk round: what history costs, and whether a sleep refunds it" {
    // The fixture's own sanity first, because a target that does not have
    // the shape the analogy describes would make every number below
    // meaningless. Mon–Fri must be ONE slab: full in the middle of
    // Wednesday, with no seam at the Tuesday/Wednesday join.
    const FINAL = STAGES[STAGES.len - 1];
    try testing.expect(schedule(FINAL, 3.5 / 7.0) > 0.999); // mid-Wednesday
    try testing.expect(schedule(FINAL, 3.0 / 7.0) > 0.999); // the Tue/Wed join
    try testing.expect(schedule(FINAL, 6.5 / 7.0) < 0.001); // Sunday
    try testing.expect(schedule(STAGES[1], 2.5 / 7.0) < 0.001); // Tuesday, before it is delivered

    const gpa = testing.allocator;
    const PER: u64 = 40_000;
    const DREAM: u64 = 150_000;
    const opts = marl.Options{ .responsibility = 3 };
    const SEED: u64 = 19;

    var pr = try probesOf(gpa, FINAL, 4096, SEED);
    defer pr.deinit(gpa);

    // Every arm's reality stream is built the same way and advanced ONLY
    // by `learn`, which draws exactly three times an exemplar. So the arms
    // see identical points in an identical order without any forking, and
    // a sleep cannot perturb the comparison because it draws from its own.
    var m_a = try marl.Model.init(gpa, opts);
    defer m_a.deinit();
    var s_a = rng.Stream.region(SEED, 0x57414b45, 0); // "WAKE"
    for (STAGES) |mask| try learn(&m_a, mask, PER, &s_a);

    // From scratch on the final schedule, at the same TOTAL exemplars…
    var m_b = try marl.Model.init(gpa, opts);
    defer m_b.deinit();
    var s_b = rng.Stream.region(SEED, 0x57414b45, 0);
    try learn(&m_b, FINAL, PER * STAGES.len, &s_b);

    // …and at the same exemplars OF THE FINAL SCHEDULE, which is the
    // honest denominator: the incremental arm spent two thirds of its
    // budget on schedules that no longer apply, so a comparison against an
    // arm with three times the current evidence would be charging history
    // for something else.
    var m_b3 = try marl.Model.init(gpa, opts);
    defer m_b3.deinit();
    var s_b3 = rng.Stream.region(SEED, 0x57414b45, 0);
    try learn(&m_b3, FINAL, PER, &s_b3);

    // THE SLEEP. The student never sees the patches; it sees the sum.
    var s_dream = rng.Stream.region(SEED ^ 0x51, 0x534c5045, 1); // "SLPE"
    var m_c = try sleep(gpa, &m_a, opts, DREAM, &s_dream);
    defer m_c.deinit();

    const k_a: f64 = @floatFromInt(m_a.kernels.items.len);
    const k_b: f64 = @floatFromInt(m_b.kernels.items.len);
    const k_b3: f64 = @floatFromInt(m_b3.kernels.items.len);
    const k_c: f64 = @floatFromInt(m_c.kernels.items.len);
    const premium = k_a / k_b3;
    const refund = (k_a - k_c) / (k_a - k_b3);

    std.debug.print("\n  G38 (a): the milk round — {d} exemplars a stage, {d} dream samples; a constant predictor scores {d:.5} ({s})\n", .{
        PER, DREAM, meanRms(pr), @tagName(builtin.mode),
    });
    std.debug.print("  G38 (a): {s:>34} {s:>8} {s:>10} {s:>8}\n", .{ "arm", "kernels", "RMS", "mean σ" });
    const rows = [_]struct { n: []const u8, m: *marl.Model }{
        .{ .n = "A  incremental, 3 stages", .m = &m_a },
        .{ .n = "B  scratch, same TOTAL", .m = &m_b },
        .{ .n = "B3 scratch, same FINAL evidence", .m = &m_b3 },
        .{ .n = "C  A, then one sleep", .m = &m_c },
    };
    for (rows) |r| std.debug.print("  G38 (a): {s:>34} {d:>8} {d:>10.5} {d:>8.4}\n", .{
        r.n, r.m.kernels.items.len, rmsOf(r.m, pr), meanWidth(r.m),
    });
    std.debug.print("  G38 (a): THE HISTORY PREMIUM {d:.3}× (≥ {d:.1} predicted); THE REFUND {d:.3} of it (≥ {d:.1}); the copy costs {d:.3}× (≥ {d:.1})\n", .{
        premium,  thresholds.MARL19_HISTORY,
        refund,   thresholds.MARL19_REFUND,
        rmsOf(&m_c, pr) / rmsOf(&m_a, pr), thresholds.MARL19_COPY,
    });

    // MARL19_HISTORY is REFUTED at 1.103 and MARL19_REFUND at −1.789, and
    // neither is asserted. What is asserted is the finding underneath.
    //
    // At EQUAL TOTAL EVIDENCE the incremental arm carries FEWER kernels
    // than the from-scratch one and is behind on accuracy. It is not
    // paying a history premium — it is simply further back, having spent
    // two thirds of its budget on schedules with less structure in them.
    // **Nothing it learned became WRONG**: Monday is delivered at every
    // stage, so the reveal is NESTED and MARL-9's law applies in its cheap
    // direction. And MARL-16 covers the only obsolete structure there was:
    // the Tuesday hole was ZERO, which is what an empty model already
    // predicts, so holding it down never cost a kernel to begin with.
    try testing.expect(k_a < k_b);
    try testing.expect(rmsOf(&m_a, pr) > rmsOf(&m_b, pr));

    // The refund went NEGATIVE because the dream was 150 000 against a
    // teacher trained on 120 000, and on a noiseless target more evidence
    // buys more kernels. That is a harness fault and G38 (c) pins it; the
    // assertion here records the direction so a future change that removes
    // it is read rather than assumed.
    try testing.expect(k_c > k_a);

    // MARL19_COPY HELD at 1.179. A copy of an EXACT teacher is a pure loss
    // on the metric, which is what says MARL-18's 0.960 belonged to the
    // noise and not to copying.
    try testing.expect(rmsOf(&m_c, pr) / rmsOf(&m_a, pr) >= thresholds.MARL19_COPY);
}

test "G38 (b) …and then it is learning on smoother ground" {
    // Christian's second half: "the Student can also learn away from the
    // Teacher from the source of truth that the teacher learned from, but
    // now it is learning on smoother ground."
    //
    // Three arms at IDENTICAL total reality — the three stages and then a
    // further period on the current schedule — differing only in whether
    // and when the model was rebuilt from itself. The mechanism under test
    // is the COVERAGE GATE: the incremental arm has spent kernels across
    // three schedules, so the Tuesday it must now fill in is exactly where
    // it is least able to buy capacity.
    const gpa = testing.allocator;
    const FINAL = STAGES[STAGES.len - 1];
    const PER: u64 = 40_000;
    const DREAM: u64 = 150_000;
    const opts = marl.Options{ .responsibility = 3 };
    const SEED: u64 = 19;

    var pr = try probesOf(gpa, FINAL, 4096, SEED);
    defer pr.deinit(gpa);

    // A′ — straight through, then more of the current schedule.
    var m_a = try marl.Model.init(gpa, opts);
    defer m_a.deinit();
    var s_a = rng.Stream.region(SEED, 0x57414b45, 0);
    for (STAGES) |mask| try learn(&m_a, mask, PER, &s_a);
    const a_before = rmsOf(&m_a, pr);
    const k_before: usize = m_a.kernels.items.len;
    try learn(&m_a, FINAL, PER, &s_a);

    // D — one sleep at the end of the stages, then the same further
    // reality from a stream at the same position.
    var m_d = try marl.Model.init(gpa, opts);
    var s_d = rng.Stream.region(SEED, 0x57414b45, 0);
    for (STAGES) |mask| try learn(&m_d, mask, PER, &s_d);
    var s_dream = rng.Stream.region(SEED ^ 0x51, 0x534c5045, 1);
    const slept = try sleep(gpa, &m_d, opts, DREAM, &s_dream);
    m_d.deinit();
    m_d = slept;
    defer m_d.deinit();
    const d_after_sleep = rmsOf(&m_d, pr);
    try learn(&m_d, FINAL, PER, &s_d);

    // E — the cycle Christian describes: a sleep after every stage.
    var m_e = try marl.Model.init(gpa, opts);
    var s_e = rng.Stream.region(SEED, 0x57414b45, 0);
    var e_dream = rng.Stream.region(SEED ^ 0x51, 0x534c5045, 1);
    for (STAGES) |mask| {
        try learn(&m_e, mask, PER, &s_e);
        var next = try sleep(gpa, &m_e, opts, DREAM, &e_dream);
        m_e.deinit();
        m_e = next;
        next = undefined;
    }
    defer m_e.deinit();
    try learn(&m_e, FINAL, PER, &s_e);

    const a_rms = rmsOf(&m_a, pr);
    std.debug.print("\n  G38 (b): after the three stages, before any further reality: {d:.5} at {d} kernels; one sleep takes it to {d:.5} ({s})\n", .{
        a_before, k_before, d_after_sleep, @tagName(builtin.mode),
    });
    std.debug.print("  G38 (b): {s:>34} {s:>8} {s:>10} {s:>9} {s:>8}\n", .{ "arm, + one more period of Mon–Fri", "kernels", "RMS", "vs A", "mean σ" });
    const rows = [_]struct { n: []const u8, m: *marl.Model }{
        .{ .n = "A  straight through", .m = &m_a },
        .{ .n = "D  one sleep, then learn", .m = &m_d },
        .{ .n = "E  a sleep after every stage", .m = &m_e },
    };
    for (rows) |r| std.debug.print("  G38 (b): {s:>34} {d:>8} {d:>10.5} {d:>9.3} {d:>8.4}\n", .{
        r.n, r.m.kernels.items.len, rmsOf(r.m, pr), rmsOf(r.m, pr) / a_rms, meanWidth(r.m),
    });
    std.debug.print("  G38 (b): SMOOTHER GROUND — one sleep {d:.3}×, a sleep every stage {d:.3}× (≤ {d:.1} predicted, HELD) — but read the kernel column: the slept arms end LARGER\n", .{
        rmsOf(&m_d, pr) / a_rms, rmsOf(&m_e, pr) / a_rms, thresholds.MARL19_GROUND,
    });

    // MARL19_GROUND HELD, and the direction is asserted: consolidating and
    // then learning beats learning straight through, on a NOISELESS field,
    // which is where MARL-18 could not have told the two currencies apart.
    try testing.expect(rmsOf(&m_d, pr) <= a_rms * thresholds.MARL19_GROUND);
    try testing.expect(rmsOf(&m_e, pr) <= rmsOf(&m_d, pr));

    // …and the caveat is asserted too, because it is the thing that makes
    // the number less than it looks. The slept arms end with MORE kernels
    // (the dream is 150 000 against the teacher's 120 000, and on an exact
    // target more evidence buys more capacity), and this campaign has found
    // four times over that RMS tracks capacity. So a 2–4% win carrying an
    // 11% larger population is not yet a clean result. G38 (c) pins the
    // dream to the teacher's own evidence.
    try testing.expect(m_d.kernels.items.len > m_a.kernels.items.len);
}

test "G38 (c) it is not addition that costs, it is CONTRADICTION" {
    // G38 (a) found the milk round as literally described carries no
    // history premium, and the reason was worth more than the prediction:
    // the reveal is NESTED, so nothing learned becomes wrong, and the one
    // piece of obsolete structure sat at ZERO where MARL-16 says a model
    // pays nothing anyway.
    //
    // So the two paths run side by side. Same three stages, same 120 000
    // exemplars, same destination, differing only in whether the path
    // contradicted itself: the contradictory round delivers Monday and
    // Tuesday, STOPS, and starts again. Kernels pulled down to zero stay
    // in the population — MARL-7's "capacity a moved world leaves behind",
    // produced on demand in a noiseless three-stage fixture instead of
    // over six drift moves.
    //
    // And the dream is PINNED to the teacher's own evidence, which is the
    // confound G38 (a) tripped over: on an exact target the dream count is
    // an evidence dial that sets the student's population directly.
    const gpa = testing.allocator;
    const FINAL = STAGES[STAGES.len - 1];
    const PER: u64 = 40_000;
    const TOTAL: u64 = PER * STAGES.len;
    const opts = marl.Options{ .responsibility = 3 };
    const SEED: u64 = 19;

    var pr = try probesOf(gpa, FINAL, 4096, SEED);
    defer pr.deinit(gpa);

    var m_n = try marl.Model.init(gpa, opts);
    defer m_n.deinit();
    var s_n = rng.Stream.region(SEED, 0x57414b45, 0);
    for (STAGES) |mask| try learn(&m_n, mask, PER, &s_n);

    var m_x = try marl.Model.init(gpa, opts);
    defer m_x.deinit();
    var s_x = rng.Stream.region(SEED, 0x57414b45, 0);
    for (CONTRA) |mask| try learn(&m_x, mask, PER, &s_x);

    var d_n = rng.Stream.region(SEED ^ 0x51, 0x534c5045, 2);
    var m_ns = try sleep(gpa, &m_n, opts, TOTAL, &d_n);
    defer m_ns.deinit();
    var d_x = rng.Stream.region(SEED ^ 0x51, 0x534c5045, 2);
    var m_xs = try sleep(gpa, &m_x, opts, TOTAL, &d_x);
    defer m_xs.deinit();

    const k_n: f64 = @floatFromInt(m_n.kernels.items.len);
    const k_x: f64 = @floatFromInt(m_x.kernels.items.len);
    const k_xs: f64 = @floatFromInt(m_xs.kernels.items.len);
    const premium = k_x / k_n;
    const refund = (k_x - k_xs) / (k_x - k_n);

    std.debug.print("\n  G38 (c): both paths, {d} exemplars a stage, the dream PINNED to the teacher's own {d} ({s})\n", .{ PER, TOTAL, @tagName(builtin.mode) });
    std.debug.print("  G38 (c): {s:>34} {s:>8} {s:>10} {s:>8}\n", .{ "path", "kernels", "RMS", "mean σ" });
    const rows = [_]struct { n: []const u8, m: *marl.Model }{
        .{ .n = "nested      Mon / Mon,Wed / Mon-Fri", .m = &m_n },
        .{ .n = "  … slept", .m = &m_ns },
        .{ .n = "contradictory  MTW / WTF / Mon-Fri", .m = &m_x },
        .{ .n = "  … slept", .m = &m_xs },
    };
    for (rows) |r| std.debug.print("  G38 (c): {s:>34} {d:>8} {d:>10.5} {d:>8.4}\n", .{
        r.n, r.m.kernels.items.len, rmsOf(r.m, pr), meanWidth(r.m),
    });
    std.debug.print("  G38 (c): THE CONTRADICTION PREMIUM {d:.3}× (≥ {d:.2} predicted, REFUTED); THE REFUND {d:.3} of it (≥ {d:.1}, REFUTED — the sleep RAISES the population on both paths, with the dream pinned)\n", .{
        premium, thresholds.MARL19_CONTRADICT, refund, thresholds.MARL19_REFUND2,
    });

    // ── The frontier, because "the sleep got bigger" is not yet a claim ──
    //
    // A student chases its teacher at θ, and a teacher's field is a sum of
    // gaussians with ripple at kernel scale — so at a low θ the student
    // reproduces the ripple and buys kernels for it. MARL-14's own lever
    // was θ and it bought 0.715× the population for 1.091× the RMS. The
    // honest question is therefore not "did one student get bigger" but
    // whether ANY student on the frontier is better than its teacher on
    // both axes. If none is, distillation is Pareto-dominated on a
    // noiseless field and the negative result is precise rather than
    // anecdotal.
    const x_rms = rmsOf(&m_x, pr);
    std.debug.print("  G38 (c): the contradictory teacher is {d} kernels at {d:.5}; its students along θ —\n", .{ m_x.kernels.items.len, x_rms });
    var dominated = true;
    for ([_]f32{ 0.02, 0.05, 0.10, 0.20 }) |th| {
        var so = opts;
        so.threshold = th;
        var d = rng.Stream.region(SEED ^ 0x51, 0x534c5045, 2);
        var st = try sleep(gpa, &m_x, so, TOTAL, &d);
        defer st.deinit();
        const r = rmsOf(&st, pr);
        const better = st.kernels.items.len < m_x.kernels.items.len and r <= x_rms;
        if (better) dominated = false;
        std.debug.print("  G38 (c):   θ = {d:>5.2}  {d:>6} kernels ({d:.3}×)  RMS {d:.5} ({d:.3}×){s}\n", .{
            th, st.kernels.items.len,
            @as(f64, @floatFromInt(st.kernels.items.len)) / k_x,
            r, r / x_rms, if (better) "  ← beats its teacher on BOTH" else "",
        });
    }

    // MARL19_CONTRADICT is REFUTED at 1.092 and MARL19_REFUND2 at −0.491;
    // neither is asserted. What is asserted is what two independent
    // fixtures now agree on.
    //
    // **A sleep is worth exactly as much as there is VARIANCE to remove.**
    // MARL-18 measured it on a noisy field and found the saving tracks the
    // noise (gradient 1.432). This fixture has NO noise, and here a sleep
    // costs accuracy and BUYS capacity, on both path shapes, with the
    // dream pinned — because the thing a student declines to rebuild is
    // the teacher's noise, and there is none.
    //
    // And history turns out to be nearly free in MARL whatever shape it
    // has: 1.103 for a nested reveal, 1.092 for one that contradicts
    // itself. Two prior phases explain it. MARL-9: capacity is paid per
    // THING LEARNED, and a nested reveal teaches nothing that becomes
    // wrong. MARL-16: the days that are not delivered sit at ZERO, which
    // is what an empty model already predicts, so a hole never cost a
    // kernel to hold down and there is nothing there to cancel.
    try testing.expect(premium < thresholds.MARL19_CONTRADICT);
    try testing.expect(k_xs > k_x);
    try testing.expect(dominated);
}
