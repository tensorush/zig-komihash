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

/// Builds an unsigned 64-bit value out of remaining bytes in a message,
/// and pads it with the "final byte". This function can only be called
/// if less than 8 bytes are left to read. The message should be "long",
/// permitting msg[-3] reads.
pub inline fn padLong3(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(idx > 2 and len < 8);
    const ml8 = -8 * @intCast(i8, len);
    if (len < 4) {
        const msg3 = msg[idx + len - 3 ..];
        const m = @intCast(u64, msg3[0]) | @intCast(u64, msg3[1]) << 8 | @intCast(u64, msg3[2]) << 16;
        return @intCast(u64, 1) << (@intCast(u6, msg3[2] >> 7) + @intCast(u6, -ml8)) | m >> @intCast(u6, 24 + ml8);
    } else {
        const mh: u64 = readInt32(msg[idx + len - 4 ..]);
        const ml: u64 = readInt32(msg[idx .. idx + 4]);
        return @intCast(u64, 1) << (@intCast(u6, mh >> 31) + @intCast(u6, -ml8)) | ml | (mh >> @intCast(u6, 64 + ml8)) << 32;
    }
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message,
/// and pads it with the "final byte". This function can only be called
/// if less than 8 bytes are left to read. The message should be "long",
/// permitting msg[-4] reads.
pub inline fn padLong4(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(idx > 3 and len < 8);
    const ml8 = -8 * @intCast(i8, len);
    if (len < 5) {
        const m: u64 = readInt32(msg[idx + len - 4 ..]);
        return @intCast(u64, 1) << (@intCast(u6, m >> 31) + @intCast(u6, -ml8)) | m >> @intCast(u6, 32 + ml8);
    } else {
        const m: u64 = readInt64(msg[idx + len - 8 ..]);
        return @intCast(u64, 1) << (@intCast(u6, m >> 63) + @intCast(u6, -ml8)) | m >> @intCast(u6, 64 + ml8);
    }
}

/// Builds an unsigned 64-bit value out of remaining bytes in a message,
/// and pads it with the "final byte". This function can only be called
/// if less than 8 bytes are left to read. Can be used on "short"
/// messages, but msg.len should be greater than 0.
pub inline fn padShort(msg: []const u8, idx: usize, len: usize) u64 {
    std.debug.assert(len > 0 and len < 8);
    const ml8 = -8 * @intCast(i8, len);
    if (len < 4) {
        const mf = msg[idx + len - 1];
        var m: u64 = msg[idx];
        if (len > 1) {
            m |= @intCast(u64, msg[idx + 1]) << 8;
            if (len > 2) {
                m |= @intCast(u64, mf) << 16;
            }
        }
        return @intCast(u64, 1) << (@intCast(u6, mf >> 7) + @intCast(u6, -ml8)) | m;
    } else {
        const mh: u64 = readInt32(msg[idx + len - 4 ..]);
        const ml: u64 = readInt32(msg[idx .. idx + 4]);
        return @intCast(u64, 1) << (@intCast(u6, mh >> 31) + @intCast(u6, -ml8)) | ml | (mh >> @intCast(u6, 64 + ml8)) << 32;
    }
}

/// Multiplies two 64-bit unsigned integers and
/// stores the result in two other 64-bit unsigned integers.
pub inline fn mul128(a: u64, b: u64, rl: *u64, rh: *u64) void {
    const r = std.math.mulWide(u128, a, b);
    rl.* = @truncate(u64, r);
    rh.* = @truncate(u64, r >> 64);
}
