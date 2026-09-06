const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const common_dep = b.dependency("common", .{ .target = target, .optimize = optimize });
    const struple_dep = b.dependency("struple", .{ .target = target, .optimize = optimize });
    const common_mod = common_dep.module("common");
    const struple_mod = struple_dep.module("struple");

    // The public library module — depend on this as `loam`.
    const mod = b.addModule("loam", .{
        .root_source_file = b.path("src/loam.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("common", common_mod);
    mod.addImport("struple", struple_mod);

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

    // Tests: src/loam.zig pulls in the gates from src/tests.zig.
    // `-Dtest-filter=<substring>` runs only matching tests.
    const tests = b.addTest(.{ .root_module = mod });
    if (b.option([]const u8, "test-filter", "Only run tests whose name contains this")) |f| {
        tests.filters = b.allocator.dupe([]const u8, &.{f}) catch @panic("OOM");
    }
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the gates");
    test_step.dependOn(&run_tests.step);
    const run_tests_exe = b.addTest(.{ .root_module = run_mod });
    test_step.dependOn(&b.addRunArtifact(run_tests_exe).step);
}
