# Current Android builder SHA verification — 2026-10-26

The launch and JNI host builders now release their 1 MiB read buffer and SHA
workspace after every file. On macOS they stream the same bytes through
CommonCrypto; other hosts retain the pure V SHA implementation with explicit
digest cleanup. The read-only `--hash-file PATH COUNT` diagnostic exercises the
actual production hash function and releases each returned digest. Existing
before/after input verification, copied provenance and output seals are unchanged.

Both host builder self-tests passed. The launch builder also passed its complete
pinned static-zlib producer check. The actual CLI checker passed for both builders:
12 fixtures cover empty input, SHA block/padding boundaries, the 1 MiB read
boundary, 3 MiB and 32 MiB. Every digest matches both the pure V oracle and
`/usr/bin/shasum -a 256`. Missing inputs, directory reads and six invalid iteration
counts fail without a success marker.

| Measured workload | Launch builder | JNI builder |
| --- | ---: | ---: |
| Peak RSS, one 1-byte hash | 2,031,616 bytes | 6,537,216 bytes |
| Peak RSS, 4,096 repeated 1-byte hashes | 2,228,224 bytes | 6,733,824 bytes |
| 32 MiB actual builder CLI wall time | 40,637,583 ns | 42,781,667 ns |
| 32 MiB pure V oracle wall time | 9,368,104,958 ns | 8,966,104,250 ns |

These are single-run measurements with concurrent host work. Generated macOS C
was inspected: the CommonCrypto context is on the stack; success and error paths
close the file and free the read/checksum buffers; the owned hexadecimal result
is created before checksum cleanup. Independent source review found no digest
or ownership defect. The production non-macOS branch was source-reviewed; it was
not executed by these macOS CLI runs.

All paths below are relative to `/Users/alex/.local/state/vinix/android/`.
Complete checker bundles retain fixtures, command logs, executable pins,
checker source and inventories. The host executables remain at the paths listed
below. The bundles' `sha256.json` pins are:

| Bundle | SHA-256 of `sha256.json` |
| --- | --- |
| `current-launch-builder-hash-check-2026-10-26-r1` | `2c5beb8b2504661f65b86bdbf7e1ae142bc58363beeea0b86cb72ed5c0702aa6` |
| `current-native-builder-hash-check-2026-10-26-r1` | `e71dba622279c3eb294809900ef757493ee8b290df342965d25b1488ff223238` |

The checker records repository revision
`ecbd3964aff243304e16df45271c7de8dee4d2da`; the following exact source hashes
identify the tested changes applied above that revision:

| Source | SHA-256 |
| --- | --- |
| `build-current-launch.v` | `a00628725834222fb801cf214094a60eb737c8187e8f7eddf6088aaf6a6ccc0a` |
| `build-current-native.v` | `1f68bc792e31031f9312ea2d9b26fb2dedf060c58c59f6357eb57476cdaf1015` |
| `current-builder-hash-check.v` | `31101bb34396693c0e0cf08e05edade6b9302eda3c4e40f76192d315dcc4d8da` |

Tested host executables:

| Executable | SHA-256 |
| --- | --- |
| `current-launch-builder-hash-host-r1` | `63f721b4ffc88cbb26d74d5f1230dd6b066de6ccddb684d4b8216b4ce28c8011` |
| `current-native-builder-hash-host-r1` | `d85a91c12f1e34b8ded10f62aef418e0324de8c32268b649051250c5f0636bff` |
| `current-builder-hash-check-old276-2026-10-26-r3` | `d236cef872ae786f3509425c819532856881ea6714c0071b6c237c2b8da1e432` |

Launch host compilation used
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`
(`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`),
with `-new-compiler -gc none -nocache -cc cc`. JNI and checker compilation used
`headless-service-native-build-2026-10-26-r5/tools/v_old276`
(`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`),
with `-gc none -nocache -cc cc`; the JNI builder additionally used its existing
`@vlib|/Users/alex/code/vinix/tests/native-android-tools` module path.
Sibling `-compile.log`, `-self-test.log` and launch `-zlib-check.log` files retain
the host results. Sibling `.c` and `-c-generation.log` files retain generated C
from the same pinned compilers.

macOS SDK headers and libSystem are host environmental dependencies; this report
does not establish a hermetic host rebuild. The already sealed account r6, UI r1,
JNI r16, launch r13 and token controller r2 captures remain unchanged. This host
verification provides no guest or Google account login result.
