//! Root benchmark file that compares Komihash throughput against other `std.hash` functions.
//! Based on https://github.com/ziglang/zig/blob/master/lib/std/hash/benchmark.zig.

const std = @import("std");
const builtin = @import("builtin");
const Komihash = @import("komihash.zig").Komihash;

const MiB: usize = 1 << 20;
const ALIGNMENT: usize = 1 << 6;
const BLOCK_SIZE: usize = 1 << 16;

const HASHES = [_]Hash{
    Hash{ .ty = std.hash.Fnv1a_64, .name = "fnv1a" },
    Hash{ .ty = std.hash.Adler32, .name = "adler32" },
    Hash{ .ty = std.hash.crc.Crc32, .name = "crc32" },
    Hash{ .ty = Komihash, .name = "komihash", .init_u64_opt = 0 },
    Hash{ .ty = std.hash.Wyhash, .name = "wyhash", .init_u64_opt = 0 },
    Hash{ .ty = std.hash.XxHash64, .name = "xxhash64", .init_u64_opt = 0 },
    Hash{ .ty = std.hash.XxHash32, .name = "xxhash32", .init_u64_opt = 0 },
    Hash{ .ty = std.hash.CityHash32, .name = "cityhash32", .has_iter_api = false },
    Hash{ .ty = std.hash.CityHash64, .name = "cityhash64", .has_iter_api = false },
    Hash{ .ty = std.hash.Murmur2_32, .name = "murmur2_32", .has_iter_api = false },
    Hash{ .ty = std.hash.Murmur2_64, .name = "murmur2_64", .has_iter_api = false },
    Hash{ .ty = std.hash.Murmur3_32, .name = "murmur3_32", .has_iter_api = false },
    Hash{ .ty = std.hash.SipHash64(1, 3), .name = "siphash64", .has_crypto_api = true, .init_u8s_opt = &[_]u8{0} ** 16 },
    Hash{ .ty = std.hash.SipHash128(1, 3), .name = "siphash128", .has_crypto_api = true, .init_u8s_opt = &[_]u8{0} ** 16 },
};

const Hash = struct {
    ty: type,
    name: []const u8,
    init_u64_opt: ?u64 = null,
    has_iter_api: bool = true,
    has_crypto_api: bool = false,
    init_u8s_opt: ?[]const u8 = null,
};

const Result = struct {
    hash: u64,
    throughput: u64,
};

const BenchmarkError = std.mem.Allocator.Error || std.time.Timer.Error;

const MainError = BenchmarkError || std.process.ArgIterator.InitError || std.fmt.ParseIntError || std.os.WriteError;

fn benchmarkHash(comptime H: anytype, bytes: usize, allocator: std.mem.Allocator, random: std.rand.Random) BenchmarkError!Result {
    const blocks_count = bytes / BLOCK_SIZE;
    var blocks = try allocator.alloc(u8, BLOCK_SIZE + ALIGNMENT * (blocks_count - 1));
    defer allocator.free(blocks);
    random.bytes(blocks);

    var hash = blk: {
        if (H.init_u8s_opt) |init_u8s| {
            break :blk H.ty.init(init_u8s[0..H.ty.key_length]);
        }
        if (H.init_u64_opt) |init_u64| {
            break :blk H.ty.init(init_u64);
        }
        break :blk H.ty.init();
    };

    var timer = try std.time.Timer.start();
    const start = timer.lap();
    for (0..blocks_count) |i| {
        hash.update(blocks[i * ALIGNMENT ..][0..BLOCK_SIZE]);
    }
    const final = if (H.has_crypto_api) @truncate(u64, hash.finalInt()) else hash.final();
    std.mem.doNotOptimizeAway(final);

    const end = timer.read();

    const elapsed_s = @intToFloat(f64, end - start) / std.time.ns_per_s;
    const throughput = @floatToInt(u64, @intToFloat(f64, bytes) / elapsed_s);

    return Result{
        .hash = final,
        .throughput = throughput,
    };
}

fn benchmarkHashSmallKeys(comptime H: anytype, key_size: usize, bytes: usize, allocator: std.mem.Allocator, random: std.rand.Random) BenchmarkError!Result {
    var blocks = try allocator.alloc(u8, bytes);
    defer allocator.free(blocks);
    random.bytes(blocks);

    const key_count = bytes / key_size;

    var timer = try std.time.Timer.start();
    const start = timer.lap();

    var sum: u64 = 0;
    for (0..key_count) |i| {
        const small_key = blocks[i * key_size ..][0..key_size];
        const final = blk: {
            if (H.init_u8s_opt) |init_u8s| {
                if (H.has_crypto_api) {
                    break :blk @truncate(u64, H.ty.toInt(small_key, init_u8s[0..H.ty.key_length]));
                } else {
                    break :blk H.ty.hash(init_u8s, small_key);
                }
            }
            if (H.init_u64_opt) |init_u64| {
                break :blk H.ty.hash(init_u64, small_key);
            }
            break :blk H.ty.hash(small_key);
        };
        sum +%= final;
    }
    const end = timer.read();

    const elapsed_s = @intToFloat(f64, end - start) / std.time.ns_per_s;
    const throughput = @floatToInt(u64, @intToFloat(f64, bytes) / elapsed_s);

    std.mem.doNotOptimizeAway(sum);

    return Result{
        .hash = sum,
        .throughput = throughput,
    };
}

fn getHelp() void {
    std.debug.print(
        \\hash_throughput_benchmarks [options]
        \\
        \\Options:
        \\  --filter    [test-name]
        \\  --seed      [int]
        \\  --count     [int]
        \\  --key-size  [int]
        \\  --iter-only
        \\  --help
        \\
    , .{});
}

pub fn main() MainError!void {
    const stdout = std.io.getStdOut().writer();

    var buf: [1024]u8 = undefined;
    var fixed_buf = std.heap.FixedBufferAllocator.init(buf[0..]);
    const args = try std.process.argsAlloc(fixed_buf.allocator());

    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();

    var seed: u32 = 0;
    var key_size: usize = 32;
    var is_iter_only = false;
    var filter_opt: ?[]u8 = null;
    var count = if (builtin.mode == .Debug) 2 * MiB else 128 * MiB;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--mode")) {
            try stdout.print("{}\n", .{builtin.mode});
            return;
        } else if (std.mem.eql(u8, args[i], "--seed")) {
            i += 1;
            if (i == args.len) {
                getHelp();
                std.os.exit(1);
            }
            seed = try std.fmt.parseUnsigned(u32, args[i], 10);
        } else if (std.mem.eql(u8, args[i], "--filter_opt")) {
            i += 1;
            if (i == args.len) {
                getHelp();
                std.os.exit(1);
            }
            filter_opt = args[i];
        } else if (std.mem.eql(u8, args[i], "--count")) {
            i += 1;
            if (i == args.len) {
                getHelp();
                std.os.exit(1);
            }
            const c = try std.fmt.parseUnsigned(usize, args[i], 10);
            count = c * MiB;
        } else if (std.mem.eql(u8, args[i], "--key-size")) {
            i += 1;
            if (i == args.len) {
                getHelp();
                std.os.exit(1);
            }
            key_size = try std.fmt.parseUnsigned(usize, args[i], 10);
            if (key_size > BLOCK_SIZE) {
                try stdout.print("key_size cannot exceed BLOCK_SIZE of {d}\n", .{BLOCK_SIZE});
                std.os.exit(1);
            }
        } else if (std.mem.eql(u8, args[i], "--iter-only")) {
            is_iter_only = true;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            getHelp();
            return;
        } else {
            getHelp();
            std.os.exit(1);
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("Leak!");
    const allocator = gpa.allocator();

    inline for (HASHES) |HASH| {
        if (filter_opt == null or std.mem.indexOf(u8, HASH.name, filter_opt.?) != null) {
            if (!is_iter_only or HASH.has_iter_api) {
                try stdout.print("{s}:\n", .{HASH.name});
                if (HASH.has_iter_api) {
                    prng.seed(seed);
                    const res = try benchmarkHash(HASH, count, allocator, random);
                    try stdout.print("    iterative: {d: >10.1}/s [{x:0<16}]\n", .{ std.fmt.fmtIntSizeBin(res.throughput), res.hash });
                }
                if (!is_iter_only) {
                    prng.seed(seed);
                    const res_small = try benchmarkHashSmallKeys(HASH, key_size, count, allocator, random);
                    try stdout.print("    small keys: {d: >9.1}/s [{x:0<16}]\n", .{ std.fmt.fmtIntSizeBin(res_small.throughput), res_small.hash });
                }
            }
        }
    }
}
