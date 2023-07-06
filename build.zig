const std = @import("std");

pub fn build(b: *std.Build) void {
    const root_source_file = std.Build.FileSource.relative("src/komihash.zig");

    // Module
    _ = b.addModule("komihash", .{ .source_file = root_source_file });

    // Library
    const lib = b.addStaticLibrary(.{
        .name = "komihash",
        .root_source_file = root_source_file,
        .target = b.standardTargetOptions(.{}),
        .optimize = .ReleaseSafe,
        .version = .{ .major = 5, .minor = 4, .patch = 0 },
    });
    lib.emit_docs = .emit;

    const lib_install = b.addInstallArtifact(lib);
    const lib_step = b.step("lib", "Install lib");
    lib_step.dependOn(&lib_install.step);
    b.default_step.dependOn(lib_step);

    // Benchmark
    const bench = b.addExecutable(.{
        .name = "hash_bench",
        .root_source_file = std.Build.FileSource.relative("src/bench.zig"),
        .optimize = .ReleaseFast,
    });

    const bench_run = b.addRunArtifact(bench);
    if (b.args) |args| {
        bench_run.addArgs(args);
    }

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_run.step);
    b.default_step.dependOn(bench_step);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = root_source_file,
    });

    const tests_run = b.addRunArtifact(tests);
    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&tests_run.step);
    b.default_step.dependOn(tests_step);

    // Code coverage
    const cov_run = b.addSystemCommand(&.{ "kcov", "--clean", "--include-pattern=src/", "kcov-output" });
    cov_run.addArtifactArg(tests);

    const cov_step = b.step("cov", "Generate code coverage report");
    cov_step.dependOn(&cov_run.step);
    b.default_step.dependOn(cov_step);

    // Lints
    const lints = b.addFmt(.{
        .paths = &[_][]const u8{ "src", "build.zig" },
        .check = true,
    });

    const lints_step = b.step("lint", "Run lints");
    lints_step.dependOn(&lints.step);
    b.default_step.dependOn(lints_step);
}
