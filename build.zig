const std = @import("std");

pub fn build(b: *std.Build) void {
    const main_source_file = std.Build.FileSource.relative("src/komihash.zig");

    const lib = b.addStaticLibrary(.{
        .name = "komihash",
        .root_source_file = main_source_file,
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseSafe,
        .version = .{ .major = 5, .minor = 3, .patch = 0 },
    });
    lib.emit_docs = .emit;
    b.installArtifact(lib);

    const lib_step = b.step("lib", "Install library");
    lib_step.dependOn(&lib.step);

    _ = b.addModule("komihash", .{ .source_file = main_source_file });

    const benchmarks = b.addExecutable(.{
        .name = "hash_throughput_benchmarks",
        .root_source_file = std.Build.FileSource.relative("src/benchmarks.zig"),
        .optimize = .ReleaseFast,
    });
    const run_benchmarks = b.addRunArtifact(benchmarks);

    if (b.args) |args| {
        run_benchmarks.addArgs(args);
    }

    const benchmarks_step = b.step("bench", "Run benchmarks");
    benchmarks_step.dependOn(&run_benchmarks.step);

    const tests = b.addTest(.{
        .root_source_file = std.Build.FileSource.relative("src/tests.zig"),
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
