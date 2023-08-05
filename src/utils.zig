//! Utility functions used by this library.

const std = @import("std");

/// Cold path for manually-guided branch prediction.
pub fn coldPath() void {
    @setCold(true);
}

/// Likelihood check for manually-guided branch prediction.
pub fn isLikely(is_likely: bool) bool {
    if (!is_likely) {
        coldPath();
    }
    return is_likely;
}

/// Reads little-endian unsigned 32-bit integer from memory.
pub fn readInt32(bytes: []const u8) u32 {
    const bytes_ptr: *const [4]u8 = @ptrCast(bytes);
    return std.mem.readIntLittle(u32, bytes_ptr);
}

/// Reads little-endian unsigned 64-bit integer from memory.
pub fn readInt64(bytes: []const u8) u64 {
    const bytes_ptr: *const [8]u8 = @ptrCast(bytes);
    return std.mem.readIntLittle(u64, bytes_ptr);
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message, and pads it with the "final byte".
pub fn padLong3(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(len < 8);

    const ml8: u6 = @intCast(len * 8);

    if (len < 4) {
        const msg3 = msg[idx + len - 3 ..];
        var m: u64 = msg3[0] | @as(u64, msg3[1]) << 8 | @as(u64, msg3[2]) << 16;
        return @as(u64, 1) << ml8 | m >> (24 - ml8);
    }

    const mh: u64 = readInt32(msg[idx + len - 4 ..]);
    const ml: u64 = readInt32(msg[idx .. idx + 4]);

    return @as(u64, 1) << ml8 | ml | (mh >> @intCast(64 - @as(u7, ml8))) << 32;
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message, and pads it with the "final byte".
pub fn padShort(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(len > 0 and len < 8);

    const ml8: u6 = @intCast(len * 8);

    if (len < 4) {
        var m: u64 = msg[idx];
        if (len > 1) {
            m |= @as(u64, msg[idx + 1]) << 8;
            if (len > 2) {
                m |= @as(u64, msg[2]) << 16;
            }
        }
        return @as(u64, 1) << ml8 | m;
    }

    const mh: u64 = readInt32(msg[idx + len - 4 ..]);
    const ml: u64 = readInt32(msg[idx .. idx + 4]);

    return @as(u64, 1) << ml8 | ml | (mh >> @intCast(64 - @as(u7, ml8))) << 32;
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message, and pads it with the "final byte".
pub fn padLong4(msg: []const u8, idx: usize, len: usize, last_word_opt: ?[8]u8) u64 {
    std.debug.assert(len < 8);

    const ml8: u6 = @intCast(len * 8);

    if (last_word_opt) |last_word| {
        if (len < 5) {
            const m: u64 = readInt32(last_word[4..]);
            return @as(u64, 1) << ml8 | m >> (32 - ml8);
        }
        const m = readInt64(last_word[0..]);
        return @as(u64, 1) << ml8 | m >> @intCast(64 - @as(u7, ml8));
    }

    if (len < 5) {
        const m: u64 = readInt32(msg[idx + len - 4 ..]);
        return @as(u64, 1) << ml8 | m >> (32 - ml8);
    }

    const m = readInt64(msg[idx + len - 8 ..]);

    return @as(u64, 1) << ml8 | m >> @intCast(64 - @as(u7, ml8));
}

/// Multiplies two 64-bit unsigned integers, and stores the result in two other 64-bit unsigned integers.
pub fn mul128(a: u64, b: u64, rl: *u64, rh: *u64) void {
    const r = std.math.mulWide(u64, a, b);
    rl.* = @truncate(r);
    rh.* = @truncate(r >> 64);
}
