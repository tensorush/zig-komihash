## :lizard: :hash: **zig komihash**

[![CI][ci-shield]][ci-url]
[![Docs][docs-shield]][docs-url]
[![License][license-shield]][license-url]
[![Resources][resources-shield]][resources-url]

### Zig port of [komihash and komirand](https://github.com/avaneev/komihash) by [Aleksey Vaneev](https://github.com/avaneev).

#### :rocket: Usage

1. Add `komihash` as a dependency in your `build.zig.zon`.

    <details>

    <summary><code>build.zig.zon</code> example</summary>

    ```zig
    .{
        .name = "<name_of_your_program>",
        .version = "<version_of_your_program>",
        .dependencies = .{
            .komihash = .{
                .url = "https://github.com/tensorush/zig-komihash/archive/refs/tags/<git_tag>.tar.gz",
                .hash = "<package_hash>",
            },
        },
    }
    ```

    If unsure what to fill out for `<package_hash>`, set it to `12200000000000000000000000000000000000000000000000000000000000000000` and Zig will tell you the correct value in an error message.

    </details>

2. Add `komihash` as a module in your `build.zig`.

    <details>

    <summary><code>build.zig</code> example</summary>

    ```zig
    const komihash = b.dependency("komihash", .{});
    exe.addModule("komihash", komihash.module("komihash"));
    ```

    </details>

#### :bar_chart: Benchmarks

```bash
$ zig build bench
fnv1a:
    iterative:   718.4MiB/s [650703db2c0206d2]
    small keys:    1.8GiB/s [6c559c3193d43e3b]
adler32:
    iterative:     2.6GiB/s [c086aa3d00000000]
    small keys:    3.9GiB/s [1bf9e9d4621b7b00]
crc32:
    iterative:     2.1GiB/s [9d3deda300000000]
    small keys:    4.6GiB/s [20024c446a99a300]
komihash:
    iterative:    21.2GiB/s [e4eb29adadc6f054]
    small keys:    8.7GiB/s [d5e88245d12f1296]
wyhash:
    iterative:    23.2GiB/s [b11af152506ad324]
    small keys:   12.3GiB/s [f3ac0179e7c891a1]
xxhash64:
    iterative:    13.6GiB/s [ad5f91161395fc66]
    small keys:    4.0GiB/s [2109f6a3a1668fbd]
xxhash32:
    iterative:     6.3GiB/s [a0c7f49400000000]
    small keys:    5.1GiB/s [1ffbad07bda51000]
cityhash32:
    small keys:    3.3GiB/s [1ffdda7a22593c00]
cityhash64:
    small keys:   19.1GiB/s [b461824ac22258b1]
murmur2_32:
    small keys:    5.6GiB/s [20002678141d6f00]
murmur2_64:
    small keys:   10.6GiB/s [3ab85d34c908b670]
murmur3_32:
    small keys:    3.8GiB/s [1ffd2972d9cd7f00]
siphash64:
    iterative:     3.1GiB/s [15776aedb8c0be48]
    small keys:    1.9GiB/s [16263f2310b282a6]
siphash128:
    iterative:     3.1GiB/s [f7ebecf4cf7c2fe4]
    small keys:    1.9GiB/s [3b048c0df7e32674]
```

<!-- MARKDOWN LINKS -->

[ci-shield]: https://img.shields.io/github/actions/workflow/status/tensorush/zig-komihash/ci.yaml?branch=main&style=for-the-badge&logo=github&label=CI&labelColor=black
[ci-url]: https://github.com/tensorush/zig-komihash/blob/main/.github/workflows/ci.yaml
[docs-shield]: https://img.shields.io/badge/click-F6A516?style=for-the-badge&logo=zig&logoColor=F6A516&label=docs&labelColor=black
[docs-url]: https://tensorush.github.io/zig-komihash
[license-shield]: https://img.shields.io/github/license/tensorush/zig-komihash.svg?style=for-the-badge&labelColor=black
[license-url]: https://github.com/tensorush/zig-komihash/blob/main/LICENSE.md
[resources-shield]: https://img.shields.io/badge/click-F6A516?style=for-the-badge&logo=zig&logoColor=F6A516&label=resources&labelColor=black
[resources-url]: https://github.com/tensorush/Awesome-Languages-Learning#lizard-zig
