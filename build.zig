const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const swisseph_src = b.dependency("swisseph", .{});
    const swisseph_src_path = swisseph_src.path("");

    // Use swisseph library as a dependency for Ephemeris.
    const swisseph_module = b.createModule(.{
        .optimize = optimize,
        .target = target,
        .link_libc = true,
    });
    swisseph_module.addCSourceFiles(.{
        .root = swisseph_src_path,
        .files = &.{ "swedate.c", "swehouse.c", "swejpl.c", "swemmoon.c", "swemplan.c", "sweph.c", "swephlib.c", "swecl.c", "swehel.c" },
    });

    swisseph_module.addIncludePath(swisseph_src_path);

    const swisseph_lib = b.addLibrary(.{
        .name = "swisseph",
        .linkage = .static,
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .root_module = swisseph_module,
    });

    swisseph_lib.installHeader(swisseph_src.path("swephexp.h"), "swephexp.h");
    swisseph_lib.installHeader(swisseph_src.path("sweodef.h"), "sweodef.h");

    // Use zig-webui as a dependency for the UI.
    const zig_webui = b.dependency("zig_webui", .{
        .target = target,
        .optimize = optimize,
        .enable_tls = false, // whether enable tls support
        .is_static = true, // whether static link
    });

    // Build executable.
    const exe = b.addExecutable(.{
        .name = "panchang-muhurt",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .linkage = if (target.result.abi == .musl) .static else .dynamic,
    });

    // Don't show the console window when running on Windows.
    if (target.result.isMinGW()) {
        exe.subsystem = .Windows;
    }

    exe.root_module.addImport("webui", zig_webui.module("webui"));
    exe.linkLibrary(swisseph_lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{ .root_source_file = b.path("src/tests.zig") });
    exe_unit_tests.linkLibrary(swisseph_lib);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    const zlinter = @import("zlinter");
    const lint_cmd = b.step("lint", "lint source code");
    lint_cmd.dependOn(step: {
        var builder = zlinter.builder(b, .{});
        builder.addRule(.{ .builtin = .declaration_naming }, .{});
        builder.addRule(.{ .builtin = .field_naming }, .{});
        builder.addRule(.{ .builtin = .file_naming }, .{});
        builder.addRule(.{ .builtin = .function_naming }, .{});
        builder.addRule(.{ .builtin = .max_positional_args }, .{});
        builder.addRule(.{ .builtin = .no_comment_out_code }, .{});
        builder.addRule(.{ .builtin = .no_deprecated }, .{});
        builder.addRule(.{ .builtin = .no_hidden_allocations }, .{});
        builder.addRule(.{ .builtin = .no_literal_args }, .{});
        builder.addRule(.{ .builtin = .no_orelse_unreachable }, .{});
        builder.addRule(.{ .builtin = .no_panic }, .{});
        builder.addRule(.{ .builtin = .no_swallow_error }, .{});
        builder.addRule(.{ .builtin = .no_unused }, .{});
        builder.addRule(.{ .builtin = .switch_case_ordering }, .{});
        break :step builder.build();
    });
}
