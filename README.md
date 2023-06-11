## :zap: :hash: **zig-komihash**

[![CI][ci-shield]][ci-url]
[![Docs][docs-shield]][docs-url]
[![License][license-shield]][license-url]
[![Resources][resources-shield]][resources-url]

### Zig port of [komihash v4.7](https://github.com/avaneev/komihash).

#### :bar_chart: Benchmarks

```bash
$ zig build bench
fnv1a:
    iterative:   747.8MiB/s [650703db2c0206d2]
    small keys:    1.9GiB/s [6c559c3193d43e3b]
adler32:
    iterative:     2.8GiB/s [c086aa3d00000000]
    small keys:    4.0GiB/s [1bf9e9d4621b7b00]
crc32:
    iterative:     2.2GiB/s [9d3deda300000000]
    small keys:    4.4GiB/s [20024c446a99a300]
komihash:
    iterative:    21.9GiB/s [c5f250a50d06fc6b]
    small keys:    8.5GiB/s [f81f2ae2b8eda5e3]
wyhash:
    iterative:     5.0GiB/s [60dc0a45bd98528b]
    small keys:   13.1GiB/s [9e635cd3493a08ac]
xxhash64:
    iterative:    13.4GiB/s [ad5f91161395fc66]
    small keys:    4.2GiB/s [2109f6a3a1668fbd]
xxhash32:
    iterative:     6.7GiB/s [a0c7f49400000000]
    small keys:    5.2GiB/s [1ffbad07bda51000]
cityhash32:
    small keys:    3.6GiB/s [1ffdda7a22593c00]
cityhash64:
    small keys:   19.9GiB/s [b461824ac22258b1]
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
    small keys:    1.9GiB/s [3b048c0df7e32674]
```

<!-- MARKDOWN LINKS -->

[ci-shield]: https://img.shields.io/github/actions/workflow/status/tensorush/zig-komihash/ci.yml?branch=main&style=for-the-badge&logo=github&label=CI&labelColor=black
[ci-url]: https://github.com/tensorush/zig-komihash/blob/main/.github/workflows/ci.yml
[docs-shield]: https://img.shields.io/badge/click-F6A516?style=for-the-badge&logo=zig&logoColor=F6A516&label=docs&labelColor=black
[docs-url]: https://tensorush.github.io/zig-komihash
[license-shield]: https://img.shields.io/github/license/tensorush/zig-komihash.svg?style=for-the-badge&labelColor=black
[license-url]: https://github.com/tensorush/zig-komihash/blob/main/LICENSE.md
[resources-shield]: https://img.shields.io/badge/click-F6A516?style=for-the-badge&logo=zig&logoColor=F6A516&label=resources&labelColor=black
[resources-url]: https://github.com/tensorush/Awesome-Languages-Learning#lizard-zig
