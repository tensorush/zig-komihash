//! Utility functions used by this library.

const std = @import("std");

/// Cold path for manually-guided branch prediction.
pub inline fn coldPath() void {
    @setCold(true);
}

/// Likelihood check for manually-guided branch prediction.
pub inline fn isLikely(is_likely: bool) bool {
    if (!is_likely)
        coldPath();
    return is_likely;
}

/// Reads little-endian unsigned 32-bit integer from memory.
pub inline fn readInt32(bytes: []const u8) u32 {
    return std.mem.readIntLittle(u32, @ptrCast(*const [4]u8, bytes));
}

/// Reads little-endian unsigned 64-bit integer from memory.
pub inline fn readInt64(bytes: []const u8) u64 {
    return std.mem.readIntLittle(u64, @ptrCast(*const [8]u8, bytes));
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message, and pads it with the "final byte".
pub inline fn padLong3(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(len < 8);
    const ml8 = 8 * @intCast(u6, len);
    if (len < 4) {
        const msg3 = msg[idx + len - 3 ..];
        const m = @intCast(u64, msg3[0]) | @intCast(u64, msg3[1]) << 8 | @intCast(u64, msg3[2]) << 16;
        return @intCast(u64, 1) << ml8 | m >> (24 - ml8);
    }
    const mh: u64 = readInt32(msg[idx + len - 4 ..]);
    const ml: u64 = readInt32(msg[idx .. idx + 4]);
    return @intCast(u64, 1) << ml8 | ml | (mh >> @intCast(u6, 64 - @intCast(u7, ml8))) << 32;
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message, and pads it with the "final byte".
pub inline fn padShort(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(len > 0 and len < 8);
    const ml8 = 8 * @intCast(u6, len);
    if (len < 4) {
        var m: u64 = msg[idx];
        if (len > 1) {
            m |= @intCast(u64, msg[idx + 1]) << 8;
            if (len > 2) {
                m |= @intCast(u64, msg[2]) << 16;
            }
        }
        return @intCast(u64, 1) << ml8 | m;
    }
    const mh: u64 = readInt32(msg[idx + len - 4 ..]);
    const ml: u64 = readInt32(msg[idx .. idx + 4]);
    return @intCast(u64, 1) << ml8 | ml | (mh >> @intCast(u6, 64 - @intCast(u7, ml8))) << 32;
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message, and pads it with the "final byte".
pub inline fn padLong4(msg: []const u8, idx: usize, len: usize, last_word_opt: ?[8]u8) u64 {
    std.debug.assert(len < 8);
    const ml8 = 8 * @intCast(u6, len);
    if (last_word_opt) |last_word| {
        if (len < 5) {
            const m: u64 = readInt32(last_word[4..]);
            return @intCast(u64, 1) << ml8 | m >> (32 - ml8);
        }
        const m = readInt64(last_word[0..]);
        return @intCast(u64, 1) << ml8 | m >> @intCast(u6, 64 - @intCast(u7, ml8));
    }
    if (len < 5) {
        const m: u64 = readInt32(msg[idx + len - 4 ..]);
        return @intCast(u64, 1) << ml8 | m >> (32 - ml8);
    }
    const m = readInt64(msg[idx + len - 8 ..]);
    return @intCast(u64, 1) << ml8 | m >> @intCast(u6, 64 - @intCast(u7, ml8));
}

/// Multiplies two 64-bit unsigned integers, and stores the result in two other 64-bit unsigned integers.
pub inline fn mul128(a: u64, b: u64, rl: *u64, rh: *u64) void {
    const r = std.math.mulWide(u64, a, b);
    rl.* = @truncate(u64, r);
    rh.* = @truncate(u64, r >> 64);
}
