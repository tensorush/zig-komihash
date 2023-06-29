//! Simple, reliable, self-starting yet efficient PRNG, with 2^64 period.
//! 0.62 cycles/byte performance. Self-starts in 4 iterations, which is a
//! suggested "warming up" initialization before using its output.

const std = @import("std");
const utils = @import("utils.zig");
const tests = @import("tests.zig");

const Komirand = @This();

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
    for (tests.SEEDS, 0..) |seed, i| {
        var komirand = Komirand.init(seed);
        for (tests.VALUES[i]) |value| {
            try std.testing.expectEqual(value, komirand.next());
        }
    }
}
