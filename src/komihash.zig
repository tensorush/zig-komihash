const std = @import("std");
const tests = @import("tests.zig");
const utils = @import("utils.zig");

pub const Komirand = @import("Komirand.zig");

/// Namespace for one-shot komihash hash function.
pub const Komihash = struct {
    /// Hashes the message with default seed.
    pub inline fn hash(msg: []const u8) u64 {
        return komihash(msg, msg.len, 0);
    }

    /// Hashes the message with specific seed.
    pub inline fn hashWithSeed(msg: []const u8, seed: u64) u64 {
        return komihash(msg, msg.len, seed);
    }

    /// Common hashing round with 16-byte input, using the "r1h" temporary variable.
    inline fn roundInput(msg: []const u8, idx: usize, seed1: *u64, seed5: *u64, r1h: *u64) void {
        utils.mul128(seed1.* ^ utils.readInt64(msg[idx .. idx + 8]), seed5.* ^ utils.readInt64(msg[idx + 8 .. idx + 16]), seed1, r1h);
        seed5.* +%= r1h.*;
        seed1.* ^= seed5.*;
    }

    /// Common hashing round without input, using the "r2h" temporary variable.
    inline fn round(seed1: *u64, seed5: *u64, r2h: *u64) void {
        utils.mul128(seed1.*, seed5.*, seed1, r2h);
        seed5.* +%= r2h.*;
        seed1.* ^= seed5.*;
    }

    /// Common hashing finalization round, with the finish hashing input
    /// expected in the "r1h" and "r2h" temporary variables.
    inline fn finish(seed1: *u64, seed5: *u64, r1h: *u64, r2h: *u64) void {
        utils.mul128(r1h.*, r2h.*, seed1, r1h);
        seed5.* +%= r1h.*;
        seed1.* ^= seed5.*;
        round(seed1, seed5, r2h);
    }

    /// Common 64-byte full-performance hashing loop. Expects msg and len values (greater than 63),
    /// requires initialized seed1-8 values, uses r1h-r4h temporary variables.
    /// The "shifting" arrangement of seed1-4 (below) does not increase individual
    /// seedN's PRNG period beyond 2^64, but reduces a chance of any occasional
    /// synchronization between PRNG lanes happening. Practically, seed1-4 together
    /// become a single "fused" 256-bit PRNG value, having a summary PRNG period.
    inline fn loop(msg: []const u8, idx: *usize, len: *usize, seed1: *u64, seed2: *u64, seed3: *u64, seed4: *u64, seed5: *u64, seed6: *u64, seed7: *u64, seed8: *u64, r1h: *u64, r2h: *u64, r3h: *u64, r4h: *u64) void {
        std.debug.assert(len.* > 63);
        while (true) {
            const i = idx.*;
            @prefetch(msg, .{ .locality = 1 });
            utils.mul128(seed1.* ^ utils.readInt64(msg[i .. i + 8]), seed5.* ^ utils.readInt64(msg[i + 8 .. i + 16]), seed1, r1h);
            utils.mul128(seed2.* ^ utils.readInt64(msg[i + 16 .. i + 24]), seed6.* ^ utils.readInt64(msg[i + 24 .. i + 32]), seed2, r2h);
            utils.mul128(seed3.* ^ utils.readInt64(msg[i + 32 .. i + 40]), seed7.* ^ utils.readInt64(msg[i + 40 .. i + 48]), seed3, r3h);
            utils.mul128(seed4.* ^ utils.readInt64(msg[i + 48 .. i + 56]), seed8.* ^ utils.readInt64(msg[i + 56 .. i + 64]), seed4, r4h);
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
            if (!utils.isLikely(len.* > 63))
                break;
        }
    }

    /// The hashing epilogue function.
    inline fn epilogue(msg: []const u8, idx: usize, len: usize, seed1: u64, seed5: u64) u64 {
        var r1h: u64 = undefined;
        var r2h: u64 = undefined;
        var s1 = seed1;
        var s5 = seed5;
        var i = idx;
        var l = len;
        @prefetch(msg, .{ .locality = 1 });
        if (utils.isLikely(l > 31)) {
            roundInput(msg, i, &s1, &s5, &r1h);
            roundInput(msg, i + 16, &s1, &s5, &r1h);
            i += 32;
            l -= 32;
        }
        if (l > 15) {
            roundInput(msg, i, &s1, &s5, &r1h);
            i += 16;
            l -= 16;
        }
        if (l > 7) {
            r2h = s5 ^ utils.padLong4(msg, i + 8, l - 8);
            r1h = s1 ^ utils.readInt64(msg[i .. i + 8]);
        } else {
            r1h = s1 ^ utils.padLong4(msg, i, l);
            r2h = s5;
        }
        finish(&s1, &s5, &r1h, &r2h);
        return s1;
    }

    /// Produces and returns a 64-bit hash value of the
    /// specified message, string, or binary data block.
    inline fn komihash(msg: []const u8, msg_len: usize, seed: u64) u64 {
        var seed1: u64 = 0x243F6A8885A308D3 ^ (seed & 0x5555555555555555);
        var seed5: u64 = 0x452821E638D01377 ^ (seed & 0xAAAAAAAAAAAAAAAA);
        var r1h: u64 = undefined;
        var r2h: u64 = undefined;
        var idx: usize = 0;
        var len = msg_len;
        round(&seed1, &seed5, &r2h);
        if (utils.isLikely(len < 16)) {
            @prefetch(msg, .{ .locality = 1 });
            r1h = seed1;
            r2h = seed5;
            if (len > 7) {
                r2h ^= utils.padLong3(msg, idx + 8, len - 8);
                r1h ^= utils.readInt64(msg[idx .. idx + 8]);
            } else if (utils.isLikely(len != 0)) {
                r1h ^= utils.padShort(msg, idx, len);
            }
            finish(&seed1, &seed5, &r1h, &r2h);
            return seed1;
        }
        if (utils.isLikely(len < 32)) {
            @prefetch(msg, .{ .locality = 1 });
            roundInput(msg, idx, &seed1, &seed5, &r1h);
            if (len > 23) {
                r2h = seed5 ^ utils.padLong4(msg, idx + 24, len - 24);
                r1h = seed1 ^ utils.readInt64(msg[idx + 16 .. idx + 24]);
            } else {
                r1h = seed1 ^ utils.padLong4(msg, idx + 16, len - 16);
                r2h = seed5;
            }
            finish(&seed1, &seed5, &r1h, &r2h);
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
            loop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
            seed5 ^= seed6 ^ seed7 ^ seed8;
            seed1 ^= seed2 ^ seed3 ^ seed4;
        }
        return epilogue(msg, idx, len, seed1, seed5);
    }
};

/// KomihashStream structure holding streamed hashing state.
pub const KomihashStream = struct {
    /// Streamed hashing's buffer size in bytes, must be a multiple of 64, and not less than 128.
    const BUF_SIZE = 768;

    buf: [BUF_SIZE]u8 = undefined,
    seeds: [8]u64 = undefined,
    is_hashing: bool = false,
    buf_fill: usize = 0,

    /// Initializes the streamed hashing session.
    pub inline fn init(seed: u64) KomihashStream {
        var stream = KomihashStream{};
        stream.seeds[0] = seed;
        return stream;
    }

    /// Updates the streamed hashing stream with new input data.
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
                    Komihash.round(&seed1, &seed5, &r2h);
                    seed2 = 0x13198A2E03707344 ^ seed1;
                    seed3 = 0xA4093822299F31D0 ^ seed1;
                    seed4 = 0x082EFA98EC4E6C89 ^ seed1;
                    seed6 = 0xBE5466CF34E90C6C ^ seed5;
                    seed7 = 0xC0AC29B7C97C50DD ^ seed5;
                    seed8 = 0x3F84D5B5B5470917 ^ seed5;
                }
                if (did_fit)
                    Komihash.loop(self.buf[0..], &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h)
                else
                    Komihash.loop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
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

    /// Finalizes the streamed hashing session, and returns the resulting
    /// hash value of the previously hashed data. This value is equal to the value
    /// returned by the komihash() function for the same provided data.
    pub inline fn finish(self: *KomihashStream) u64 {
        const msg = self.buf[0..self.buf_fill];
        var len = self.buf_fill;
        var idx: usize = 0;
        if (self.is_hashing == false)
            return Komihash.komihash(msg, len, self.seeds[0]);
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
            Komihash.loop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
        }
        seed5 ^= seed6 ^ seed7 ^ seed8;
        seed1 ^= seed2 ^ seed3 ^ seed4;
        return Komihash.epilogue(msg, idx, len, seed1, seed5);
    }
};

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
