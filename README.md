## :lizard: :hash: **zig komihash**

[![CI][ci-shield]][ci-url]
[![CD][cd-shield]][cd-url]
[![Docs][docs-shield]][docs-url]
[![Codecov][codecov-shield]][codecov-url]
[![License][license-shield]][license-url]

### Zig port of the [Komihash hash function](https://github.com/avaneev/komihash) created by [Aleksey Vaneev](https://github.com/avaneev).

#### :rocket: Usage

1. Add `komihash` as a dependency in your `build.zig.zon`.

    <details>

    <summary><code>build.zig.zon</code> example</summary>

    ```zig
    .{
        .name = "<name_of_your_package>",
        .version = "<version_of_your_package>",
        .dependencies = .{
            .komihash = .{
                .url = "https://github.com/tensorush/zig-komihash/archive/<git_tag_or_commit_hash>.tar.gz",
                .hash = "<package_hash>",
            },
        },
    }
    ```

    Set `<package_hash>` to `12200000000000000000000000000000000000000000000000000000000000000000`, and Zig will provide the correct found value in an error message.

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
    iterative:   762.1MiB/s [650703db2c0206d2]
    small keys:    1.9GiB/s [6c559c3193d43e3b]
adler32:
    iterative:     2.7GiB/s [c086aa3d00000000]
    small keys:    4.0GiB/s [1bf9e9d4621b7b00]
crc32:
    iterative:     2.2GiB/s [9d3deda300000000]
    small keys:    4.6GiB/s [20024c446a99a300]
komihash:
    iterative:    22.0GiB/s [e4eb29adadc6f054]
    small keys:    6.0GiB/s [d5e88245d12f1296]
wyhash:
    iterative:    24.2GiB/s [b11af152506ad324]
    small keys:   12.5GiB/s [f3ac0179e7c891a1]
xxhash64:
    iterative:    13.5GiB/s [ad5f91161395fc66]
    small keys:    5.4GiB/s [2109f6a3a1668fbd]
xxhash32:
    iterative:     5.8GiB/s [a0c7f49400000000]
    small keys:   13.0GiB/s [1ffbad07bda51000]
cityhash32:
    small keys:    3.6GiB/s [1ffdda7a22593c00]
cityhash64:
    small keys:   20.1GiB/s [b461824ac22258b1]
murmur2_32:
    small keys:    6.0GiB/s [20002678141d6f00]
murmur2_64:
    small keys:   10.8GiB/s [3ab85d34c908b670]
murmur3_32:
    small keys:    3.9GiB/s [1ffd2972d9cd7f00]
siphash64:
    iterative:     3.1GiB/s [15776aedb8c0be48]
    small keys:    1.9GiB/s [16263f2310b282a6]
siphash128:
    iterative:     3.1GiB/s [f7ebecf4cf7c2fe4]
    small keys:    2.0GiB/s [3b048c0df7e32674]
```

<!-- MARKDOWN LINKS -->

[ci-shield]: https://img.shields.io/github/actions/workflow/status/tensorush/zig-komihash/ci.yaml?branch=main&style=for-the-badge&logo=github&label=CI&labelColor=black
[ci-url]: https://github.com/tensorush/zig-komihash/blob/main/.github/workflows/ci.yaml
[cd-shield]: https://img.shields.io/github/actions/workflow/status/tensorush/zig-komihash/cd.yaml?branch=main&style=for-the-badge&logo=github&label=CD&labelColor=black
[cd-url]: https://github.com/tensorush/zig-komihash/blob/main/.github/workflows/cd.yaml
[docs-shield]: https://img.shields.io/badge/click-F6A516?style=for-the-badge&logo=zig&logoColor=F6A516&label=docs&labelColor=black
[docs-url]: https://tensorush.github.io/zig-komihash
[codecov-shield]: https://img.shields.io/codecov/c/github/tensorush/zig-komihash?style=for-the-badge&labelColor=black
[codecov-url]: https://app.codecov.io/gh/tensorush/zig-komihash
[license-shield]: https://img.shields.io/github/license/tensorush/zig-komihash.svg?style=for-the-badge&labelColor=black
[license-url]: https://github.com/tensorush/zig-komihash/blob/main/LICENSE.md
