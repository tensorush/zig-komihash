//! Root library file that exposes the public API.

const std = @import("std");
const utils = @import("utils.zig");

/// Simple, reliable, self-starting yet efficient PRNG, with 2^64 period.
/// 0.62 cycles/byte performance. Self-starts in 4 iterations, which is a
/// suggested "warming up" initialization before using its output.
pub const Komirand = struct {
    /// Base seed.
    seed1: u64 = 0,
    /// Extra seed.
    seed2: u64 = 0,

    /// Initializes PRNG with one seed.
    pub fn init(seed: u64) Komirand {
        return .{ .seed1 = seed, .seed2 = seed };
    }

    /// Initializes PRNG with two seeds. Best initialized to the same value.
    pub fn initWithExtraSeed(seed1: u64, seed2: u64) Komirand {
        return .{ .seed1 = seed1, .seed2 = seed2 };
    }

    /// Provides Random API initialized with the fill function.
    pub fn random(self: *Komirand) std.rand.Random {
        return std.rand.Random.init(self, fill);
    }

    /// Produces the next uniformly-random 64-bit value.
    pub fn next(self: *Komirand) u64 {
        utils.mul128(self.seed1, self.seed2, &self.seed1, &self.seed2);
        self.seed2 +%= 0xAAAAAAAAAAAAAAAA;
        self.seed1 ^= self.seed2;
        return self.seed1;
    }

    /// Fills a byte buffer with pseudo-random values.
    pub fn fill(self: *Komirand, buf: []u8) void {
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
        for (TEST_SEEDS, 0..) |seed, i| {
            var komirand = Komirand.init(seed);
            for (TEST_VALUES[i]) |value| {
                try std.testing.expectEqual(value, komirand.next());
            }
        }
    }
};

/// Fast, high-quality non-cryptographic hash function, discrete-incremental and streamed-hashing-capable.
pub const KomihashStateless = struct {
    /// Common hashing round with 16-byte input, using the "r1h" temporary variable.
    fn roundInput(msg: []const u8, idx: usize, seed1: *u64, seed5: *u64) void {
        utils.mul128(seed1.* ^ utils.readInt64(msg[idx .. idx + 8]), seed5.* ^ utils.readInt64(msg[idx + 8 .. idx + 16]), seed1, seed5);
        seed1.* ^= seed5.*;
    }

    /// Common hashing round without input, using the "r2h" temporary variable.
    fn roundNoInput(seed1: *u64, seed5: *u64) void {
        utils.mul128(seed1.*, seed5.*, seed1, seed5);
        seed1.* ^= seed5.*;
    }

    /// Common hashing finalization round, using the "r1h" and "r2h" temporary variables.
    fn final(seed1: *u64, seed5: *u64, r1h: *u64, r2h: *u64) void {
        utils.mul128(r1h.*, r2h.*, seed1, seed5);
        seed1.* ^= seed5.*;
        roundNoInput(seed1, seed5);
    }

    /// Common 64-byte full-performance hashing loop.
    fn loop(msg: []const u8, idx: *usize, len: *usize, seed1: *u64, seed2: *u64, seed3: *u64, seed4: *u64, seed5: *u64, seed6: *u64, seed7: *u64, seed8: *u64) void {
        std.debug.assert(len.* > 63);

        while (true) {
            const i = idx.*;

            @prefetch(msg, .{ .locality = 1 });

            utils.mul128(seed1.* ^ utils.readInt64(msg[i .. i + 8]), seed5.* ^ utils.readInt64(msg[i + 32 .. i + 40]), seed1, seed5);
            utils.mul128(seed2.* ^ utils.readInt64(msg[i + 8 .. i + 16]), seed6.* ^ utils.readInt64(msg[i + 40 .. i + 48]), seed2, seed6);
            utils.mul128(seed3.* ^ utils.readInt64(msg[i + 16 .. i + 24]), seed7.* ^ utils.readInt64(msg[i + 48 .. i + 56]), seed3, seed7);
            utils.mul128(seed4.* ^ utils.readInt64(msg[i + 24 .. i + 32]), seed8.* ^ utils.readInt64(msg[i + 56 .. i + 64]), seed4, seed8);

            idx.* += 64;
            len.* -= 64;

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
    fn epilogue(msg: []const u8, idx: usize, len: usize, seed1: u64, seed5: u64, last_bytes_opt: ?[8]u8) u64 {
        var r1h: u64 = undefined;
        var r2h: u64 = undefined;
        var s1 = seed1;
        var s5 = seed5;
        var i = idx;
        var l = len;

        if (utils.isLikely(l > 31)) {
            roundInput(msg, i, &s1, &s5);
            roundInput(msg, i + 16, &s1, &s5);
            i += 32;
            l -= 32;
        }

        if (l > 15) {
            roundInput(msg, i, &s1, &s5);
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
    pub fn hash(seed: u64, msg: []const u8) u64 {
        var seed1: u64 = 0x243F6A8885A308D3 ^ (seed & 0x5555555555555555);
        var seed5: u64 = 0x452821E638D01377 ^ (seed & 0xAAAAAAAAAAAAAAAA);
        var r1h: u64 = undefined;
        var r2h: u64 = undefined;
        var idx: usize = 0;
        var len = msg.len;

        @prefetch(msg, .{ .locality = 1 });

        roundNoInput(&seed1, &seed5);

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
            roundInput(msg, idx, &seed1, &seed5);
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

        if (utils.isLikely(len > 63)) {
            var seed2 = 0x13198A2E03707344 ^ seed1;
            var seed3 = 0xA4093822299F31D0 ^ seed1;
            var seed4 = 0x082EFA98EC4E6C89 ^ seed1;
            var seed6 = 0xBE5466CF34E90C6C ^ seed5;
            var seed7 = 0xC0AC29B7C97C50DD ^ seed5;
            var seed8 = 0x3F84D5B5B5470917 ^ seed5;

            loop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8);

            seed5 ^= seed6 ^ seed7 ^ seed8;
            seed1 ^= seed2 ^ seed3 ^ seed4;
        }

        return epilogue(msg, idx, len, seed1, seed5, null);
    }

    test "KomihashStateless" {
        for (TEST_SEEDS, 0..) |seed, i| {
            for (TEST_HASHES[i], 0..) |expected_hash, j| {
                try std.testing.expectEqual(expected_hash, KomihashStateless.hash(seed, TEST_MSGS[j]));
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
    pub fn init(seed: u64) Komihash {
        return .{ .seeds = [1]u64{seed} ++ ([1]u64{0} ** 7) };
    }

    /// Updates the streamed hashing state with new input data.
    pub fn update(self: *Komihash, msg: []const u8) void {
        var buf_len = self.buf_len;
        var sw_idx: usize = 0;
        var sw_len: usize = 0;
        var idx: usize = 0;
        var len = msg.len;
        var data = msg;

        if (buf_len + len >= BUF_CAPACITY and buf_len != 0) {
            const copy_len = BUF_CAPACITY - buf_len;
            @memcpy(self.buf[buf_len .. buf_len + copy_len], msg[0..copy_len]);
            sw_idx = idx + copy_len;
            sw_len = len - copy_len;
            data = self.buf[0..];
            len = BUF_CAPACITY;
            buf_len = 0;
            idx = 0;
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
                    KomihashStateless.roundNoInput(&seed1, &seed5);
                    seed2 = 0x13198A2E03707344 ^ seed1;
                    seed3 = 0xA4093822299F31D0 ^ seed1;
                    seed4 = 0x082EFA98EC4E6C89 ^ seed1;
                    seed6 = 0xBE5466CF34E90C6C ^ seed5;
                    seed7 = 0xC0AC29B7C97C50DD ^ seed5;
                    seed8 = 0x3F84D5B5B5470917 ^ seed5;
                }

                KomihashStateless.loop(data, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8);

                self.seeds[0] = seed1;
                self.seeds[1] = seed2;
                self.seeds[2] = seed3;
                self.seeds[3] = seed4;
                self.seeds[4] = seed5;
                self.seeds[5] = seed6;
                self.seeds[6] = seed7;
                self.seeds[7] = seed8;

                if (sw_len == 0) {
                    if (len != 0) {
                        break;
                    }
                    self.buf_len = 0;
                    return {};
                }

                idx = sw_idx;
                len = sw_len;
                data = msg;
                sw_len = 0;
            }
        }

        self.buf_len = buf_len + len;
        @memcpy(self.buf[buf_len .. buf_len + len], data[idx .. idx + len]);
    }

    /// Finalizes the streamed hashing session, and returns the hash of previously hashed data.
    pub fn final(self: *Komihash) u64 {
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
            KomihashStateless.loop(msg, &idx, &len, &seed1, &seed2, &seed3, &seed4, &seed5, &seed6, &seed7, &seed8);
        }

        seed5 ^= seed6 ^ seed7 ^ seed8;
        seed1 ^= seed2 ^ seed3 ^ seed4;

        return KomihashStateless.epilogue(msg, idx, len, seed1, seed5, self.last_bytes_opt);
    }

    /// Produces a 64-bit hash value of the specified message.
    pub fn hash(seed: u64, msg: []const u8) u64 {
        return KomihashStateless.hash(seed, msg);
    }

    test "Komihash" {
        for (TEST_SEEDS, 0..) |seed, i| {
            for (TEST_HASHES[i], 0..) |expected_hash, j| {
                var stream = Komihash.init(seed);
                stream.update(TEST_MSGS[j]);
                try std.testing.expectEqual(expected_hash, stream.final());

                var len: u8 = 1;
                while (len < 128) : (len += 1) {
                    stream = Komihash.init(seed);
                    var msg = TEST_MSGS[j];
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

/// Test seeds for initializing `Komirand` and `Komihash`.
const TEST_SEEDS = [_]u64{ 0, 256, 81_985_529_216_486_895 };

/// Test arrays of random values expected from `Komirand` when initialized with test seeds.
const TEST_VALUES = [TEST_SEEDS.len][12]u64{
    .{ 0xAAAAAAAAAAAAAAAA, 0xFFFFFFFFFFFFFFFE, 0x4924924924924910, 0xBAEBAEBAEBAEBA00, 0x400C62CC4727496B, 0x35A969173E8F925B, 0xDB47F6BAE9A247AD, 0x98E0F6CECE6711FE, 0x97FFA2397FDA534B, 0x11834262360DF918, 0x34E53DF5399F2252, 0xECAEB74A81D648ED },
    .{ 0xAAAAAAAAAAABABAA, 0xFFFFFFFFF8FCF8FE, 0xDB6DBA1E4DBB1134, 0xF5B7D3AEC37F4CB1, 0x66A571DA7DED7051, 0x2D59EC9245BF03D9, 0x5C06A41BD510AED8, 0xEA5E7EA9D2BD07A2, 0xE395015DDCE7756F, 0xC07981AAEAAE3B38, 0x2E120EBFEE59A5A2, 0x9001EEE495244DBA },
    .{ 0x776AD9718078CA64, 0x737AA5D5221633D0, 0x685046CCA30F6F44, 0xFB725CB01B30C1BA, 0xC501CC999EDE619F, 0x8427298E525DB507, 0xD9BAF3C54781F75E, 0x7F5A4E5B97B37C7B, 0xDE8A0AFE8E03B8C1, 0xB6ED3E72B69FC3D6, 0xA68727902F7628D0, 0x44162B63AF484587 },
};

/// Test hashes expected from `Komihash.hash()` function when initialized with test seeds and provided with test messages.
const TEST_HASHES = [TEST_SEEDS.len][TEST_MSGS.len]u64{
    .{ 0x05AD960802903A9D, 0xD15723521D3C37B1, 0x467CAA28EA3DA7A6, 0xF18E67BC90C43233, 0x2C514F6E5DCB11CB, 0x7A9717E9EEA4BE8B, 0xA56469564C2EA0FF, 0x00B4313A24431306, 0x64C2AD96013F70FE, 0x7A3888BC95545364, 0xC77E02ED4B201B9A, 0x256D74350303A1BA, 0x59609C71697BB9DF, 0x36EB9E6A4C2C5E4B, 0x8DD56C332850BAA6, 0xCBB722192B353999, 0x90B07E2158F88CC0, 0x24C9621701603741, 0x1D4C1D97CA684334, 0xD1A425D530652287, 0x72623BE342C20AB5, 0x94C3DBDCA59DDF57 },
    .{ 0x5F197B30BCEC1E45, 0xA761280322BB7698, 0x11C31CCABAA524F1, 0x3A43B7F58281C229, 0xCFF90B0466B7E3A2, 0x8AB53F45CC9315E3, 0xEA606E43D1976CCF, 0x889B2F2CEECBEC73, 0xACBEC1886CD23275, 0x57C3AFFD1B71FCDB, 0x7EF6BA49A3B068C3, 0x49DBCA62ED5A1DDF, 0x192848484481E8C0, 0x420B43A5EDBA1BD7, 0xD6E8400A9DE24CE3, 0xBEA291B225FF384D, 0x0EC94062B2F06960, 0xFA613272ECD49985, 0x76F0BB380BC207BE, 0x4AFB4E08CA77C020, 0x410F9C129AD88AEA, 0x066C7B25F4F569AE },
    .{ 0x6CE66A2E8D4979A5, 0x5B1DA0B43545D196, 0x26AF914213D0C915, 0x62D9CA1B73250CB5, 0x90AB7C9F831CD940, 0x84AE4EB65B96617E, 0xACEEBC32A3C0D9E4, 0xDAA1A90ECB95F6F8, 0xEC8EB3EF4AF380B4, 0x07045BD31ABBA34C, 0xD5F619FB2E62C4AE, 0x5A336FD2C4C39ABE, 0x0E870B4623EEA8EC, 0xE552EDD6BF419D1D, 0x37D170DDCB1223E6, 0x1CD89E708E5098B6, 0x765490569CCD77F2, 0x19E9D77B86D01EE8, 0x25F83EE520C1D241, 0xD6007417091CD4C0, 0x3E49C2D3727B9CC9, 0xB2B3405EE5D65F4C },
};

/// Test messages provided into `Komihash.hash()` function.
const TEST_MSGS = [_][]const u8{
    "This is a 32-byte testing string",
    "The cat is out of the bag",
    "A 16-byte string",
    "The new string",
    "7 chars",
    &.{ 0, 1, 2 },
    &.{ 0, 1, 2, 3, 4, 5 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131 },
    &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255 },
};

test {
    std.testing.refAllDecls(@This());
}
