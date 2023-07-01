//! Root library file that exposes the public API.

const std = @import("std");
const utils = @import("utils.zig");
const test_data = @import("test_data.zig");

/// Simple, reliable, self-starting yet efficient PRNG, with 2^64 period.
/// 0.62 cycles/byte performance. Self-starts in 4 iterations, which is a
/// suggested "warming up" initialization before using its output.
pub const Komirand = struct {
    /// Base seed.
    seed1: u64 = 0,
    /// Extra seed.
    seed2: u64 = 0,

    /// Initializes PRNG with one seed.
    pub inline fn init(seed: u64) Komirand {
        return .{ .seed1 = seed, .seed2 = seed };
    }

    /// Initializes PRNG with two seeds. Best initialized to the same value.
    pub inline fn initWithExtraSeed(seed1: u64, seed2: u64) Komirand {
        return .{ .seed1 = seed1, .seed2 = seed2 };
    }

    /// Provides Random API initialized with the fill function.
    pub inline fn random(self: *Komirand) std.rand.Random {
        return std.rand.Random.init(self, fill);
    }

    /// Produces the next uniformly-random 64-bit value.
    pub inline fn next(self: *Komirand) u64 {
        var rh: u64 = undefined;
        utils.mul128(self.seed1, self.seed2, &self.seed1, &rh);
        self.seed2 +%= rh +% 0xAAAAAAAAAAAAAAAA;
        self.seed1 ^= self.seed2;
        return self.seed1;
    }

    /// Fills a byte buffer with pseudo-random values.
    pub inline fn fill(self: *Komirand, buf: []u8) void {
        const aligned_len = buf.len - (buf.len & 7);
        var i: usize = 0;

        while (i < aligned_len) : (i += 8) {
            var n = self.next();
            comptime var j: usize = 0;
            inline while (j < 8) : (j += 1) {
                buf[i + j] = @truncate(n);
                n >>= 8;
            }
        }

        if (i != buf.len) {
            var n = self.next();
            while (i < buf.len) : (i += 1) {
                buf[i] = @truncate(n);
                n >>= 8;
            }
        }
    }

    test "Komirand" {
        for (test_data.SEEDS, 0..) |seed, i| {
            var komirand = Komirand.init(seed);
            for (test_data.VALUES[i]) |value| {
                try std.testing.expectEqual(value, komirand.next());
            }
        }
    }
};

/// Fast, high-quality non-cryptographic hash function, discrete-incremental and streamed-hashing-capable.
pub const KomihashStateless = struct {
    /// Common hashing round with 16-byte input, using the "r1h" temporary variable.
    inline fn roundInput(msg: []const u8, idx: usize, seed1: *u64, seed5: *u64, r1h: *u64) void {
        utils.mul128(seed1.* ^ utils.readInt64(msg[idx .. idx + 8]), seed5.* ^ utils.readInt64(msg[idx + 8 .. idx + 16]), seed1, r1h);
        seed5.* +%= r1h.*;
        seed1.* ^= seed5.*;
    }

    /// Common hashing round without input, using the "r2h" temporary variable.
    inline fn roundNoInput(seed1: *u64, seed5: *u64, r2h: *u64) void {
        utils.mul128(seed1.*, seed5.*, seed1, r2h);
        seed5.* +%= r2h.*;
        seed1.* ^= seed5.*;
    }

    /// Common hashing finalization round, using the "r1h" and "r2h" temporary variables.
    inline fn final(seed1: *u64, seed5: *u64, r1h: *u64, r2h: *u64) void {
        utils.mul128(r1h.*, r2h.*, seed1, r1h);
        seed5.* +%= r1h.*;
        seed1.* ^= seed5.*;
        roundNoInput(seed1, seed5, r2h);
    }

    /// Common 64-byte full-performance hashing loop.
    inline fn loop(msg: []const u8, idx: *usize, len: *usize, seed1: *u64, seed2: *u64, seed3: *u64, seed4: *u64, seed5: *u64, seed6: *u64, seed7: *u64, seed8: *u64, r1h: *u64, r2h: *u64, r3h: *u64, r4h: *u64) void {
        std.debug.assert(len.* > 63);

        while (true) {
            const i = idx.*;
            @prefetch(msg, .{ .locality = 1 });
            utils.mul128(seed1.* ^ utils.readInt64(msg[i .. i + 8]), seed5.* ^ utils.readInt64(msg[i + 32 .. i + 40]), seed1, r1h);
            utils.mul128(seed2.* ^ utils.readInt64(msg[i + 8 .. i + 16]), seed6.* ^ utils.readInt64(msg[i + 40 .. i + 48]), seed2, r2h);
            utils.mul128(seed3.* ^ utils.readInt64(msg[i + 16 .. i + 24]), seed7.* ^ utils.readInt64(msg[i + 48 .. i + 56]), seed3, r3h);
            utils.mul128(seed4.* ^ utils.readInt64(msg[i + 24 .. i + 32]), seed8.* ^ utils.readInt64(msg[i + 56 .. i + 64]), seed4, r4h);
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
            if (!utils.isLikely(len.* > 63)) {
                break;
            }
        }
    }

    /// The hashing epilogue function.
    inline fn epilogue(msg: []const u8, idx: usize, len: usize, seed1: u64, seed5: u64, last_bytes_opt: ?[8]u8) u64 {
        var r1h: u64 = undefined;
        var r2h: u64 = undefined;
        var s1 = seed1;
        var s5 = seed5;
        var i = idx;
        var l = len;

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
            r2h = s5 ^ utils.padLong4(msg, i + 8, l - 8, last_bytes_opt);
            r1h = s1 ^ utils.readInt64(msg[i .. i + 8]);
        } else {
            r1h = s1 ^ utils.padLong4(msg, i, l, last_bytes_opt);
            r2h = s5;
        }

        final(&s1, &s5, &r1h, &r2h);
        return s1;
    }

    /// Produces a 64-bit hash value of the specified message.
    pub inline fn hash(seed: u64, msg: []const u8) u64 {
        var seed1: u64 = 0x243F6A8885A308D3 ^ (seed & 0x5555555555555555);
        var seed5: u64 = 0x452821E638D01377 ^ (seed & 0xAAAAAAAAAAAAAAAA);
        var r1h: u64 = undefined;
        var r2h: u64 = undefined;
        var idx: usize = 0;
        var len = msg.len;

        @prefetch(msg, .{ .locality = 1 });

        roundNoInput(&seed1, &seed5, &r2h);

        if (utils.isLikely(len < 16)) {
            r1h = seed1;
            r2h = seed5;
            if (len > 7) {
                r2h ^= utils.padLong3(msg, idx + 8, len - 8);
                r1h ^= utils.readInt64(msg[idx .. idx + 8]);
            } else if (utils.isLikely(len != 0)) {
                r1h ^= utils.padShort(msg, idx, len);
            }

            final(&seed1, &seed5, &r1h, &r2h);
            return seed1;
        }

        if (utils.isLikely(len < 32)) {
            roundInput(msg, idx, &seed1, &seed5, &r1h);
            if (len > 23) {
                r2h = seed5 ^ utils.padLong4(msg, idx + 24, len - 24, null);
                r1h = seed1 ^ utils.readInt64(msg[idx + 16 .. idx + 24]);
            } else {
                r1h = seed1 ^ utils.padLong4(msg, idx + 16, len - 16, null);
                r2h = seed5;
            }

            final(&seed1, &seed5, &r1h, &r2h);
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

        return epilogue(msg, idx, len, seed1, seed5, null);
    }

    test "KomihashStateless" {
        for (test_data.SEEDS, 0..) |seed, i| {
            for (test_data.HASHES[i], 0..) |expected_hash, j| {
                try std.testing.expectEqual(expected_hash, KomihashStateless.hash(seed, test_data.MSGS[j]));
            }
        }
    }
};

/// Komihash structure holding streamed hashing state.
pub const Komihash = struct {
    /// Streamed hashing buffer capacity, must be a multiple of 64, and not less than 128.
    pub const BUF_CAPACITY = 768;

    /// Buffer for storing the hashing state.
    buf: [BUF_CAPACITY]u8 = undefined,
    /// Hashing stream's last bytes.
    last_bytes_opt: ?[8]u8 = null,
    /// Hashing state's variables.
    seeds: [8]u64 = undefined,
    /// Hashing start indicator.
    is_hashing: bool = false,
    /// Buffer's filled length.
    buf_len: usize = 0,

    /// Initializes the streamed hashing session with a seed.
    pub inline fn init(seed: u64) Komihash {
        return .{ .seeds = [1]u64{seed} ++ ([1]u64{0} ** 7) };
    }

    /// Updates the streamed hashing state with new input data.
    pub inline fn update(self: *Komihash, msg: []const u8) void {
        var buf_len = self.buf_len;
        var sw_idx: usize = 0;
        var sw_len: usize = 0;
        var idx: usize = 0;
        var len = msg.len;
        var data = msg;

        if (buf_len + len >= BUF_CAPACITY and buf_len != 0) {
            const copy_len = BUF_CAPACITY - buf_len;
            std.mem.copy(u8, self.buf[buf_len..], msg[0..copy_len]);
            sw_idx = idx + copy_len;
            sw_len = len - copy_len;
            data = self.buf[0..];
            len = BUF_CAPACITY;
            buf_len = 0;
            idx = 0;
        } else if (len < 33) {
            var op = self.buf[buf_len..];

            if (len == 4) {
                std.mem.copy(u8, op, msg[0..4]);
                self.buf_len = buf_len + 4;
                return {};
            }

            if (len == 8) {
                std.mem.copy(u8, op, msg[0..8]);
                self.buf_len = buf_len + 8;
                return {};
            }

            if (len > 0) {
                self.buf_len = buf_len + len;
                std.mem.copy(u8, op, msg[0..len]);
            }

            return {};
        }

        if (buf_len == 0) {
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
                    KomihashStateless.roundNoInput(&seed1, &seed5, &r2h);
                    seed2 = 0x13198A2E03707344 ^ seed1;
                    seed3 = 0xA4093822299F31D0 ^ seed1;
                    seed4 = 0x082EFA98EC4E6C89 ^ seed1;
                    seed6 = 0xBE5466CF34E90C6C ^ seed5;
                    seed7 = 0xC0AC29B7C97C50DD ^ seed5;
                    seed8 = 0x3F84D5B5B5470917 ^ seed5;
                }

                KomihashStateless.loop(data, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);

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
                        self.buf_len = 0;
                        self.last_bytes_opt = ([1]u8{0} ** 7) ++ [1]u8{data[idx - 1]};
                        return {};
                    }
                    break;
                }

                idx = sw_idx;
                len = sw_len;
                data = msg;
                sw_len = 0;
            }
        }

        std.mem.copy(u8, self.buf[buf_len..], data[idx .. idx + len]);
        self.buf_len = buf_len + len;
    }

    /// Finalizes the streamed hashing session, and returns the hash of previously hashed data.
    pub inline fn final(self: *Komihash) u64 {
        var idx: usize = 0;
        var len = self.buf_len;
        const msg = self.buf[0..len];

        if (self.is_hashing == false) {
            return KomihashStateless.hash(self.seeds[0], msg);
        }

        if (self.last_bytes_opt == null and len < 9) {
            var last_bytes = [1]u8{0} ** 8;
            var i = 8 - len;
            for (msg) |byte| {
                last_bytes[i] = byte;
                i += 1;
            }
            self.last_bytes_opt = last_bytes;
        }

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

            KomihashStateless.loop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8, &r1h, &r2h, &r3h, &r4h);
        }

        seed5 ^= seed6 ^ seed7 ^ seed8;
        seed1 ^= seed2 ^ seed3 ^ seed4;

        return KomihashStateless.epilogue(msg, idx, len, seed1, seed5, self.last_bytes_opt);
    }

    /// Produces a 64-bit hash value of the specified message.
    pub inline fn hash(seed: u64, msg: []const u8) u64 {
        return KomihashStateless.hash(seed, msg);
    }

    test "Komihash" {
        for (test_data.SEEDS, 0..) |seed, i| {
            for (test_data.HASHES[i], 0..) |expected_hash, j| {
                var stream = Komihash.init(seed);
                stream.update(test_data.MSGS[j]);
                try std.testing.expectEqual(expected_hash, stream.final());

                var len: u8 = 1;
                while (len < 128) : (len += 1) {
                    stream = Komihash.init(seed);
                    var msg = test_data.MSGS[j];
                    while (msg.len > 0) {
                        const slice = msg[0..@min(msg.len, len)];
                        msg = msg[slice.len..];
                        stream.update(slice);
                    }
                    try std.testing.expectEqual(expected_hash, stream.final());
                }
            }
        }
    }
};

test {
    std.testing.refAllDecls(@This());
}
