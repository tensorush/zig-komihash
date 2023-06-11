const std = @import("std");
const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "komihash",
        .root_source_file = .{ .path = "src/komihash.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.emit_docs = .emit;
    b.installArtifact(lib);

    const lib_step = b.step("lib", "Install library");
    lib_step.dependOn(&lib.step);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&run_tests.step);

    const fmt = b.addFmt(.{
        .paths = &[_][]const u8{ "src", "build.zig" },
        .check = true,
    });

    const fmt_step = b.step("fmt", "Run linter");
    fmt_step.dependOn(&fmt.step);
}
