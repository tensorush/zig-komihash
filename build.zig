const std = @import("std");

pub fn build(b: *std.Build) void {
    const root_source_file = std.Build.FileSource.relative("src/komihash.zig");

    _ = b.addModule("komihash", .{ .source_file = root_source_file });

    const lib = b.addStaticLibrary(.{
        .name = "komihash",
        .root_source_file = root_source_file,
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseSafe,
        .version = .{ .major = 5, .minor = 3, .patch = 0 },
    });
    lib.emit_docs = .emit;
    b.installArtifact(lib);

    const benchmarks = b.addExecutable(.{
        .name = "benchmarks",
        .root_source_file = std.Build.FileSource.relative("src/benchmarks.zig"),
        .optimize = .ReleaseFast,
    });
    const benchmarks_run = b.addRunArtifact(benchmarks);

    if (b.args) |args| {
        benchmarks_run.addArgs(args);
    }

    const benchmarks_step = b.step("bench", "Run benchmarks");
    benchmarks_step.dependOn(&benchmarks_run.step);
    b.default_step.dependOn(benchmarks_step);

    const tests = b.addTest(.{
        .root_source_file = std.Build.FileSource.relative("src/tests.zig"),
    });
    const tests_run = b.addRunArtifact(tests);

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&tests_run.step);
    b.default_step.dependOn(tests_step);

    const lints = b.addFmt(.{
        .paths = &[_][]const u8{ "src", "build.zig" },
        .check = true,
    });

    const lints_step = b.step("lint", "Run lints");
    lints_step.dependOn(&lints.step);
    b.default_step.dependOn(lints_step);
}
