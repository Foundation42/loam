const std = @import("std");

/// The module set — common, struple, loam — at one optimize mode.
const Mods = struct { common: *std.Build.Module, struple: *std.Build.Module, loam: *std.Build.Module };

fn modules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, public: bool) Mods {
    const common_dep = b.dependency("common", .{ .target = target, .optimize = optimize });
    const struple_dep = b.dependency("struple", .{ .target = target, .optimize = optimize });
    const common_mod = common_dep.module("common");
    const struple_mod = struple_dep.module("struple");
    const opts = std.Build.Module.CreateOptions{
        .root_source_file = b.path("src/loam.zig"),
        .target = target,
        .optimize = optimize,
    };
    // The public library module — depend on this as `loam`.
    const loam_mod = if (public) b.addModule("loam", opts) else b.createModule(opts);
    loam_mod.addImport("common", common_mod);
    loam_mod.addImport("struple", struple_mod);
    return .{ .common = common_mod, .struple = struple_mod, .loam = loam_mod };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // The gates run ReleaseSafe unless told otherwise: the same safety
    // checks as Debug, the suite in 166 s against 270 (Christian, Sunday
    // 2026-09-06: "running the tests ReleaseSafe — good idea"). The
    // artefacts — loam-run, the seam — keep `-Doptimize`, Debug by
    // default, which is the measuring regime.
    const test_optimize = b.option(std.builtin.OptimizeMode, "test-optimize", "Optimize mode for the gates (default ReleaseSafe)") orelse .ReleaseSafe;

    const m = modules(b, target, optimize, true);
    const common_mod = m.common;
    const mod = m.loam;

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "loam",
        .root_module = mod,
    });
    b.installArtifact(lib);

    // ── the seam ─────────────────────────────────────────────────────────
    // loam behind a C ABI as a SHARED library, so Python (ctypes, pure
    // stdlib) and any non-Zig host drive the same World the Zig surface
    // does. rill's precedent: a boundary that is a real artefact, not a
    // header. `zig build seam` rebuilds only this.
    const seam_mod = b.createModule(.{
        .root_source_file = b.path("src/capi.zig"),
        .target = target,
        .optimize = optimize,
    });
    seam_mod.addImport("loam", mod);
    const seam = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "loam",
        .root_module = seam_mod,
    });
    seam.linkLibC(); // the C allocator is the honest one behind a C ABI
    const seam_install = b.addInstallArtifact(seam, .{});
    b.getInstallStep().dependOn(&seam_install.step);
    b.step("seam", "Rebuild ONLY the C-ABI shared seam (libloam.so)").dependOn(&seam_install.step);

    // loam-run: the seedbed. Place a seed, a light, a wall of damage; step
    // on fed time; dump slices as PGM and the active set as a list. Its
    // job is making gate vacuity visible (brief P1.7).
    const run_mod = b.createModule(.{
        .root_source_file = b.path("src/run.zig"),
        .target = target,
        .optimize = optimize,
    });
    run_mod.addImport("loam", mod);
    run_mod.addImport("common", common_mod);
    const runner = b.addExecutable(.{ .name = "loam-run", .root_module = run_mod });
    b.installArtifact(runner);
    const runner_cmd = b.addRunArtifact(runner);
    runner_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| runner_cmd.addArgs(args);
    b.step("run", "Run loam-run: zig build run -- [opts]").dependOn(&runner_cmd.step);

    // marl-run: MARL-0's seedbed (docs/MARL_CAMPAIGN.md). A separate
    // executable, not a flag on loam-run: MARL is not the sim — no World,
    // no step, no fed clock, nothing in a hash — and a flag would say
    // otherwise.
    const marl_mod = b.createModule(.{
        .root_source_file = b.path("src/marl_run.zig"),
        .target = target,
        .optimize = optimize,
    });
    marl_mod.addImport("loam", mod);
    const marl_exe = b.addExecutable(.{ .name = "marl-run", .root_module = marl_mod });
    b.installArtifact(marl_exe);
    const marl_cmd = b.addRunArtifact(marl_exe);
    marl_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| marl_cmd.addArgs(args);
    b.step("marl", "Run marl-run: zig build marl -- [opts]").dependOn(&marl_cmd.step);

    // verify-dump: the cross-language half of the dump gate. loam-run
    // writes a snapshot, and the struple PYTHON port reads it back with no
    // loam code on that side — one witness is prose.
    const vd_run = b.addRunArtifact(runner);
    vd_run.addArgs(&.{ "--scene", "sapling", "--steps", "12", "--dump" });
    const vd_dump = vd_run.addOutputFileArg("verify.struple");
    const vd_read = b.addSystemCommand(&.{ "python3", "tools/read_dump.py" });
    vd_read.addFileArg(vd_dump);
    vd_read.step.dependOn(&vd_run.step);
    b.step("verify-dump", "Dump a snapshot with loam-run and read it back from Python").dependOn(&vd_read.step);

    // py-test: the Python gates — the ctypes binding over the seam, and
    // G1 across two PROCESSES, which is the regime the brief names.
    const py_test = b.addSystemCommand(&.{ "python3", "-m", "unittest", "discover", "-s", "py/tests", "-v" });
    py_test.setCwd(b.path("."));
    py_test.step.dependOn(b.getInstallStep());
    b.step("py-test", "Run the Python tests over libloam.so and loam-run").dependOn(&py_test.step);

    // Normal development/commit check: a small set of existing contract
    // witnesses, not the research sweeps. An explicit filter replaces it.
    // The full regression suite is opt-in (roughly daily, not per commit).
    const tm = if (test_optimize == optimize) m else modules(b, target, test_optimize, false);
    const tests = b.addTest(.{ .root_module = tm.loam });
    if (b.option([]const u8, "test-filter", "Only run tests whose name contains this")) |f| {
        tests.filters = b.allocator.dupe([]const u8, &.{f}) catch @panic("OOM");
    } else {
        tests.filters = &.{
            "P1.1: a hand-placed blob",
            "P1.2: a value straddling",
            "the set reads the same bits rill's evaluator reads",
            "G17 (a)", // kernel pin
            "G17 (b)", // learning gradient
            "G17 (c)", // gather after learning
            "G17 (e)", // held-out learning gain, with disabled-learner mutation
            "G44 (i)", // transformed support
            "G47 (c)", // deferred read
            // A recency window whose decay underflows does not break, it
            // INVERTS — the oldest exemplars become unevictable and the
            // buffer fills with the wrong end of history, looking entirely
            // ordinary while it does. Milliseconds, and nothing else in the
            // suite would notice.
            "G66 (a)", // replay window inversion
            // OBS-22's trajectory contracts: EWMA initialisation, the
            // calibration freeze, the budget ceiling, the cooldown counted
            // in MONITORING observations, and a drift that does not wait for
            // an intervention. No sleeps; milliseconds. Built BEFORE the
            // expensive comparison, because OBS-21 discovered its headline
            // contract was underspecified only on the first full run.
            "G69 (a)", // trajectory contract
            // OBS-23's lattice, and the reason it can attribute anything:
            // with the sleep stubbed the six arms must collapse to exactly
            // TWO trajectories, matched on outputs and not merely on drawn
            // locations. It also pins the registered event order on BOTH
            // sleep paths — the immediate one reintroduced OBS-22's
            // score-ordering bug the day it was added. Seconds, no sleeps.
            "G70 (a)", // lattice contract
            // OBS-24's fork: both consolidated branches built from the
            // SAME post-linear-refit bytes rather than the same seed, the
            // control continuing the ACTUAL parent (an `adopt` would reset
            // Adam moments, update counts and the residual ring that gates
            // births), and — with the refinement stubbed — the two branches
            // identical THROUGH CONTINUATION rather than merely at adoption.
            "G71 (a)", // fork contract
        };
    }
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run smoke checks (or -Dtest-filter); ReleaseSafe by default");
    test_step.dependOn(&run_tests.step);
    const full_tests = b.addTest(.{ .root_module = tm.loam });
    const full_step = b.step("test-full", "Run ALL regression/research gates (expensive; roughly daily)");
    full_step.dependOn(&b.addRunArtifact(full_tests).step);
    const test_run_mod = b.createModule(.{
        .root_source_file = b.path("src/run.zig"),
        .target = target,
        .optimize = test_optimize,
    });
    test_run_mod.addImport("loam", tm.loam);
    test_run_mod.addImport("common", tm.common);
    const run_tests_exe = b.addTest(.{ .root_module = test_run_mod });
    const run_cli_tests = b.addRunArtifact(run_tests_exe);
    test_step.dependOn(&run_cli_tests.step);
    full_step.dependOn(&run_cli_tests.step);
    const marl_test_mod = b.createModule(.{
        .root_source_file = b.path("src/marl_run.zig"),
        .target = target,
        .optimize = test_optimize,
    });
    marl_test_mod.addImport("loam", tm.loam);
    const marl_cli_tests = b.addRunArtifact(b.addTest(.{ .root_module = marl_test_mod }));
    test_step.dependOn(&marl_cli_tests.step);
    full_step.dependOn(&marl_cli_tests.step);
}
