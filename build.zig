const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const tests = b.addTest("src/komihash.zig");
    tests.setBuildMode(mode);
    tests.setTarget(target);
    tests.emit_docs = .emit;

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&tests.step);
}
