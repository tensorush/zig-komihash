const std = @import("std");
const tests = @import("tests.zig");

/// Cold path for manually-guided branch prediction.
inline fn coldPath() void {
    @setCold(true);
}

/// Likelihood check for manually-guided branch prediction.
inline fn isLikely(is_likely: bool) bool {
    if (!is_likely)
        coldPath();
    return is_likely;
}

/// Reads little-endian unsigned 32-bit integer from memory.
inline fn readInt32(bytes: []const u8) u32 {
    return std.mem.readIntLittle(u32, @ptrCast(*const [4]u8, bytes));
}

/// Reads little-endian unsigned 64-bit integer from memory.
inline fn readInt64(bytes: []const u8) u64 {
    return std.mem.readIntLittle(u64, @ptrCast(*const [8]u8, bytes));
}

/// Function builds an unsigned 64-bit value out of remaining bytes in a
/// message, and pads it with the "final byte". This function can only be
/// called if less than 8 bytes are left to read. The message should be "long",
/// permitting msg[-3] reads.
///
/// @param msg Message pointer, alignment is unimportant.
/// @param idx Message's current index.
/// @param len Message's remaining length, in bytes; can be 0.
/// @return Final byte-padded value from the message.
inline fn padLong3(msg: []const u8, idx: usize, len: usize) u64 {
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

/// Function builds an unsigned 64-bit value out of remaining bytes in a
/// message, and pads it with the "final byte". This function can only be
/// called if less than 8 bytes are left to read. The message should be "long",
/// permitting msg[-4] reads.
///
/// @param msg Message pointer, alignment is unimportant.
/// @param idx Message's current index.
/// @param len Message's remaining length, in bytes; can be 0.
/// @return Final byte-padded value from the message.
inline fn padLong4(msg: []const u8, idx: usize, len: usize) u64 {
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

/// Function builds an unsigned 64-bit value out of remaining bytes in a
/// message, and pads it with the "final byte". This function can only be
/// called if less than 8 bytes are left to read. Can be used on "short"
/// messages, but msg.len should be greater than 0.
///
/// @param msg Message pointer, alignment is unimportant.
/// @param idx Message's current index.
/// @param len Message's remaining length, in bytes; cannot be 0.
/// @return Final byte-padded value from the message.
inline fn padShort(msg: []const u8, idx: usize, len: usize) u64 {
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

/// 64-bit by 64-bit unsigned integer multiplication.
///
/// @param a First multiplier.
/// @param b Second multiplier.
/// @param[out] rl The lower half of the 128-bit result.
/// @param[out] rh The higher half of the 128-bit result.
inline fn multiply128(a: u64, b: u64, rl: *u64, rh: *u64) void {
    const r = std.math.mulWide(u128, a, b);
    rl.* = @truncate(u64, r);
    rh.* = @truncate(u64, r >> 64);
}

/// Common hashing round with 16-byte input, using the "r1h" temporary variable.
inline fn hash16(msg: []const u8, idx: usize, seed1: *u64, seed5: *u64, r1h: *u64) void {
    multiply128(seed1.* ^ readInt64(msg[idx .. idx + 8]), seed5.* ^ readInt64(msg[idx + 8 .. idx + 16]), seed1, r1h);
    seed5.* +%= r1h.*;
    seed1.* ^= seed5.*;
}

/// Common hashing round without input, using the "r2h" temporary variable.
inline fn hashRound(seed1: *u64, seed5: *u64, r2h: *u64) void {
    multiply128(seed1.*, seed5.*, seed1, r2h);
    seed5.* +%= r2h.*;
    seed1.* ^= seed5.*;
}

/// Common hashing finalization round, with the finish hashing input
/// expected in the "r1h" and "r2h" temporary variables.
inline fn hashFinish(seed1: *u64, seed5: *u64, r1h: *u64, r2h: *u64) void {
    multiply128(r1h.*, r2h.*, seed1, r1h);
    seed5.* +%= r1h.*;
    seed1.* ^= seed5.*;
    hashRound(seed1, seed5, r2h);
}

/// Common 64-byte full-performance hashing loop. Expects msg and len values (greater than 63),
/// requires initialized seed1-8 values, uses r1h-r4h temporary variables.
/// The "shifting" arrangement of seed1-4 (below) does not increase individual
/// seedN's PRNG period beyond 2^64, but reduces a chance of any occasional
/// synchronization between PRNG lanes happening. Practically, seed1-4 together
/// become a single "fused" 256-bit PRNG value, having a summary PRNG period.
inline fn hashLoop(msg: []const u8, idx: *usize, len: *usize, seed1: *u64, seed2: *u64, seed3: *u64, seed4: *u64, seed5: *u64, seed6: *u64, seed7: *u64, seed8: *u64, r1h: *u64, r2h: *u64, r3h: *u64, r4h: *u64) void {
    std.debug.assert(len.* > 63);
    while (true) {
        const i = idx.*;
        @prefetch(msg, .{ .locality = 1 });
        multiply128(seed1.* ^ readInt64(msg[i .. i + 8]), seed5.* ^ readInt64(msg[i + 8 .. i + 16]), seed1, r1h);
        multiply128(seed2.* ^ readInt64(msg[i + 16 .. i + 24]), seed6.* ^ readInt64(msg[i + 24 .. i + 32]), seed2, r2h);
        multiply128(seed3.* ^ readInt64(msg[i + 32 .. i + 40]), seed7.* ^ readInt64(msg[i + 40 .. i + 48]), seed3, r3h);
        multiply128(seed4.* ^ readInt64(msg[i + 48 .. i + 56]), seed8.* ^ readInt64(msg[i + 56 .. i + 64]), seed4, r4h);
        idx.* += 64;
        len.* -= 64;
        seed5.* +%= r1h.*;
        seed6.* +%= r2h.*;
        seed7.* +%= r3h.*;
        seed8.* +%= r4h.*;
        seed2.* ^= seed5.*;
        seed3.* ^= seed6.*;
        seed4.* ^= seed7.*;
        seed1.* ^= seed8.*;
        if (!isLikely(len.* > 63))
            break;
    }
}

/// The hashing epilogue function.
///
/// @param msg Pointer to the remaining part of the message.
/// @param idx Message's current index.
/// @param len Remaining message's length, can be zero.
/// @param seed1 Latest seed1 value.
/// @param seed5 Latest seed5 value.
/// @return 64-bit hash value.
inline fn epilogue(msg: []const u8, idx: usize, len: usize, seed1: u64, seed5: u64) u64 {
    var r1h: u64 = undefined;
    var r2h: u64 = undefined;
    var s1 = seed1;
    var s5 = seed5;
    var i = idx;
    var l = len;
    @prefetch(msg, .{ .locality = 1 });
    if (isLikely(l > 31)) {
        hash16(msg, i, &s1, &s5, &r1h);
        hash16(msg, i + 16, &s1, &s5, &r1h);
        i += 32;
        l -= 32;
    }
    if (l > 15) {
        hash16(msg, i, &s1, &s5, &r1h);
        i += 16;
        l -= 16;
    }
    if (l > 7) {
        r2h = s5 ^ padLong4(msg, i + 8, l - 8);
        r1h = s1 ^ readInt64(msg[i .. i + 8]);
    } else {
        r1h = s1 ^ padLong4(msg, i, l);
        r2h = s5;
    }
    hashFinish(&s1, &s5, &r1h, &r2h);
    return s1;
}

/// Simple, reliable, self-starting yet efficient PRNG, with 2^64 period.
/// 0.62 cycles/byte performance. Self-starts in 4 iterations, which is a
/// suggested "warming up" initialization before using its output.
pub const Komirand = struct {
    seed1: u64 = 0,
    seed2: u64 = 0,

    /// @param seed Base seed value. Can be initialized to any value.
    pub inline fn init(seed: u64) Komirand {
        return .{ .seed1 = seed, .seed2 = seed };
    }

    /// @param seed1 Base seed value. Can be initialized to any value.
    /// @param seed2 Extra seed value. Best initialized to the same value as seed1.
    pub inline fn initWithExtraSeed(seed1: u64, seed2: u64) Komirand {
        return .{ .seed1 = seed1, .seed2 = seed2 };
    }

    /// @return The next uniformly-random 64-bit value.
    pub inline fn next(self: *Komirand) u64 {
        var rh: u64 = undefined;
        multiply128(self.seed1, self.seed2, &self.seed1, &rh);
        self.seed2 +%= rh +% 0xAAAAAAAAAAAAAAAA;
        self.seed1 ^= self.seed2;
        return self.seed1;
    }
};

pub const Komihash = struct {
    pub inline fn hash(msg: []const u8) u64 {
        return komihash(msg, msg.len, 0);
    }

    pub inline fn hashWithSeed(msg: []const u8, seed: u64) u64 {
        return komihash(msg, msg.len, seed);
    }
};

/// Komihash hash function produces and returns a 64-bit hash value of the
/// specified message, string, or binary data block. Designed for 64-bit
/// hash-table and hash-map uses.
///
/// @param msg The message to produce a hash from. The alignment of this
/// pointer is unimportant. It is valid to pass 0 when len == 0.
/// @param msg_len Message's length, in bytes, can be zero.
/// @param seed Seed value to use instead of the default seed.
/// The seed value can have any bit length and statistical quality,
/// and is used only as an additional entropy source.
/// @return 64-bit hash of the input data.
inline fn komihash(msg: []const u8, msg_len: usize, seed: u64) u64 {
    var seed1: u64 = 0x243F6A8885A308D3 ^ (seed & 0x5555555555555555);
    var seed5: u64 = 0x452821E638D01377 ^ (seed & 0xAAAAAAAAAAAAAAAA);
    var r1h: u64 = undefined;
    var r2h: u64 = undefined;
    var idx: usize = 0;
    var len = msg_len;
    hashRound(&seed1, &seed5, &r2h);
    if (isLikely(len < 16)) {
        @prefetch(msg, .{ .locality = 1 });
        r1h = seed1;
        r2h = seed5;
        if (len > 7) {
            r2h ^= padLong3(msg, idx + 8, len - 8);
            r1h ^= readInt64(msg[idx .. idx + 8]);
        } else if (isLikely(len != 0)) {
            r1h ^= padShort(msg, idx, len);
        }
        hashFinish(&seed1, &seed5, &r1h, &r2h);
        return seed1;
    }
    if (isLikely(len < 32)) {
        @prefetch(msg, .{ .locality = 1 });
        hash16(msg, idx, &seed1, &seed5, &r1h);
        if (len > 23) {
            r2h = seed5 ^ padLong4(msg, idx + 24, len - 24);
            r1h = seed1 ^ readInt64(msg[idx + 16 .. idx + 24]);
        } else {
            r1h = seed1 ^ padLong4(msg, idx + 16, len - 16);
            r2h = seed5;
        }
        hashFinish(&seed1, &seed5, &r1h, &r2h);
        return seed1;
    }
    if (len > 63) {
        var seed2 = 0x13198A2E03707344 ^ seed1;
        var seed3 = 0xA4093822299F31D0 ^ seed1;
        var seed4 = 0x082EFA98EC4E6C89 ^ seed1;
        var seed6 = 0xBE5466CF34E90C6C ^ seed5;
        var seed7 = 0xC0AC29B7C97C50DD ^ seed5;
        var seed8 = 0x3F84D5B5B5470917 ^ seed5;
        var r3h: u64 = undefined;
        var r4h: u64 = undefined;
        hashLoop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
        seed5 ^= seed6 ^ seed7 ^ seed8;
        seed1 ^= seed2 ^ seed3 ^ seed4;
    }
    return epilogue(msg, idx, len, seed1, seed5);
}

/// KomihashStream structure that holds streamed hashing stream.
/// The init() function should be called to initialize the structure before hashing.
/// Note that the default buffer size is modest, permitting placement of this
/// structure on stack. seed[0] is used as initial seed storage.
pub const KomihashStream = struct {
    /// Streamed hashing's buffer size in bytes, must be a multiple of 64, and not less than 128.
    const BUF_SIZE = 768;

    buf: [BUF_SIZE]u8 = undefined,
    seeds: [8]u64 = undefined,
    is_hashing: bool = false,
    buf_fill: usize = 0,

    /// Function initializes the streamed hashing session.
    ///
    /// @param seed Optional value, to use instead of the default seed.
    /// The seed value can have any bit length and statistical quality,
    /// and is used only as an additional entropy source.
    pub inline fn init(seed: u64) KomihashStream {
        var stream = KomihashStream{};
        stream.seeds[0] = seed;
        return stream;
    }

    /// Function updates the streamed hashing stream with a new input data.
    ///
    /// @param[in] Pointer to the context structure.
    /// @param msg The next part of the whole message being hashed. The alignment
    /// of this pointer is unimportant. It is valid to pass 0 when len == 0.
    pub inline fn update(self: *KomihashStream, msg: []const u8) void {
        var buf_fill = self.buf_fill;
        var sw_idx: usize = 0;
        var sw_len: usize = 0;
        var idx: usize = 0;
        var len = msg.len;
        const did_fit = buf_fill + len >= BUF_SIZE and buf_fill != 0;
        if (did_fit) {
            const copy_len = BUF_SIZE - buf_fill;
            std.mem.copy(u8, self.buf[buf_fill..], msg[0..copy_len]);
            buf_fill = 0;
            sw_idx = idx + copy_len;
            sw_len = len - copy_len;
            len = BUF_SIZE;
        } else if (len < 9) {
            var op = self.buf[buf_fill..];
            if (len == 4) {
                std.mem.copy(u8, op, msg[0..4]);
                self.buf_fill = buf_fill + 4;
                return {};
            }
            if (len == 8) {
                std.mem.copy(u8, op, msg[0..8]);
                self.buf_fill = buf_fill + 8;
                return {};
            }
            self.buf_fill = buf_fill + len;
            std.mem.copy(u8, op, msg[0..len]);
            return {};
        }
        if (buf_fill == 0) {
            while (len > 127) {
                var seed1: u64 = undefined;
                var seed2: u64 = undefined;
                var seed3: u64 = undefined;
                var seed4: u64 = undefined;
                var seed5: u64 = undefined;
                var seed6: u64 = undefined;
                var seed7: u64 = undefined;
                var seed8: u64 = undefined;
                var r1h: u64 = undefined;
                var r2h: u64 = undefined;
                var r3h: u64 = undefined;
                var r4h: u64 = undefined;
                if (self.is_hashing) {
                    seed1 = self.seeds[0];
                    seed2 = self.seeds[1];
                    seed3 = self.seeds[2];
                    seed4 = self.seeds[3];
                    seed5 = self.seeds[4];
                    seed6 = self.seeds[5];
                    seed7 = self.seeds[6];
                    seed8 = self.seeds[7];
                } else {
                    self.is_hashing = true;
                    const seed = self.seeds[0];
                    seed1 = 0x243F6A8885A308D3 ^ (seed & 0x5555555555555555);
                    seed5 = 0x452821E638D01377 ^ (seed & 0xAAAAAAAAAAAAAAAA);
                    hashRound(&seed1, &seed5, &r2h);
                    seed2 = 0x13198A2E03707344 ^ seed1;
                    seed3 = 0xA4093822299F31D0 ^ seed1;
                    seed4 = 0x082EFA98EC4E6C89 ^ seed1;
                    seed6 = 0xBE5466CF34E90C6C ^ seed5;
                    seed7 = 0xC0AC29B7C97C50DD ^ seed5;
                    seed8 = 0x3F84D5B5B5470917 ^ seed5;
                }
                if (did_fit)
                    hashLoop(self.buf[0..], &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h)
                else
                    hashLoop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
                self.seeds[0] = seed1;
                self.seeds[1] = seed2;
                self.seeds[2] = seed3;
                self.seeds[3] = seed4;
                self.seeds[4] = seed5;
                self.seeds[5] = seed6;
                self.seeds[6] = seed7;
                self.seeds[7] = seed8;
                if (sw_len == 0) {
                    if (len == 0) {
                        self.buf_fill = 0;
                        return {};
                    }
                    break;
                }
                idx = sw_idx;
                len = sw_len;
                sw_len = 0;
            }
        }
        if (did_fit)
            std.mem.copy(u8, self.buf[buf_fill..], self.buf[0..len])
        else
            std.mem.copy(u8, self.buf[buf_fill..], msg[0..len]);
        self.buf_fill = buf_fill + len;
    }

    /// Function finalizes the streamed hashing session, and returns the resulting
    /// hash value of the previously hashed data. This value is equal to the value
    /// returned by the komihash() function for the same provided data.
    ///
    /// @param[in] Pointer to the context structure.
    /// @return 64-bit hash value.
    pub inline fn finish(self: *KomihashStream) u64 {
        const msg = self.buf[0..self.buf_fill];
        var len = self.buf_fill;
        var idx: usize = 0;
        if (self.is_hashing == false)
            return komihash(msg, len, self.seeds[0]);
        var seed1 = self.seeds[0];
        var seed2 = self.seeds[1];
        var seed3 = self.seeds[2];
        var seed4 = self.seeds[3];
        var seed5 = self.seeds[4];
        var seed6 = self.seeds[5];
        var seed7 = self.seeds[6];
        var seed8 = self.seeds[7];
        if (len > 63) {
            var r1h: u64 = undefined;
            var r2h: u64 = undefined;
            var r3h: u64 = undefined;
            var r4h: u64 = undefined;
            hashLoop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
        }
        seed5 ^= seed6 ^ seed7 ^ seed8;
        seed1 ^= seed2 ^ seed3 ^ seed4;
        return epilogue(msg, idx, len, seed1, seed5);
    }
};

test "Komirand" {
    for (tests.KOMIRAND_SEEDS, 0..) |seed, i| {
        var komirand = Komirand.init(seed);
        for (tests.KOMIRAND_VALUES[i]) |value| {
            try std.testing.expectEqual(value, komirand.next());
        }
    }
}

test "Komihash" {
    for (tests.KOMIHASH_HASHES, 0..) |hashes, i| {
        try std.testing.expectEqual(hashes[0], Komihash.hash(tests.KOMIHASH_MSGS[i]));
        try std.testing.expectEqual(hashes[1], Komihash.hashWithSeed(tests.KOMIHASH_MSGS[i], hashes[2]));
    }
}

test "KomihashStream" {
    for (tests.KOMIHASH_HASHES, 0..) |hashes, i| {
        var len: u8 = 1;
        while (len < 128) : (len += 1) {
            var stream = KomihashStream.init(0);
            var msg = tests.KOMIHASH_MSGS[i];
            while (msg.len > 0) {
                const slice = msg[0..std.math.min(msg.len, len)];
                msg = msg[slice.len..];
                stream.update(slice);
            }
            try std.testing.expectEqual(hashes[0], stream.finish());

            stream = KomihashStream.init(hashes[2]);
            msg = tests.KOMIHASH_MSGS[i];
            while (msg.len > 0) {
                const slice = msg[0..std.math.min(msg.len, len)];
                msg = msg[slice.len..];
                stream.update(slice);
            }
            try std.testing.expectEqual(hashes[1], stream.finish());
        }

        // var stream = KomihashStream.init(0);
        // stream.update(tests.KOMIHASH_MSGS[i]);
        // try std.testing.expectEqual(hashes[0], stream.finish());

        // stream = KomihashStream.init(hashes[2]);
        // stream.update(tests.KOMIHASH_MSGS[i]);
        // try std.testing.expectEqual(hashes[1], stream.finish());
    }
}
