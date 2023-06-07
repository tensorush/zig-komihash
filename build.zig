const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/komihash.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.emit_docs = .emit;

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&tests.step);
}
