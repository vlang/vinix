# Native resource synchronization fixture tools, 2026-11-01

The additive `--resource-locks` runner profile uses the unchanged Intent r2
framework and requires a distinct native resource-lock library and signed
fixture. `serve --resource-locks-api` retains the two-file protocol at
`/resource-locks-api-run` and `/resource-locks.apk`. The test-only JNI helper is
inside the pinned APK and uses the ordinary APK native-library load path.
Historical profiles, pins, routes and strict health checks remain intact.

The exact success marker is:

```text
RESOURCE-LOCKS-PASS workers=4 iterations=64 ids names strings arrays bags themes same-copy cross-copy configuration paths owned-asset owned-directory
```

Protected inputs, dedicated identity/data, six input pins, eleven receipt checks,
descriptor closure, bounded lifetime, exact PASS/READY markers, drained EOF and
clean child exit remain required. This fixture covers concurrent packaged
resource and owned NDK asset/directory operations; it does not establish Maps,
Play Services or authentication behavior.

Runtime identity is UID/GID 10137, with transfer port 55529, mount
`/opt/resource-locks-runtime`, inputs
`/opt/input/resource-locks-run` and `/opt/input/resource-locks.apk`, and fresh
output `/var/lib/resource-locks-r1`. The guest must verify the identity is unused
before provisioning it.

Paths below use `S=/Users/alex/.local/state/vinix/android`. The original r1
qualification follows; subsequent fixture and tool refreshes are recorded after
it.

| Input | Path below S | SHA-256 |
| --- | --- | --- |
| Framework | `combined-account-webview-intent-extras-framework-2026-11-01-r2/api-impl.jar` | `02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20` |
| Native | `current-native-build-2026-11-01-resource-lock-r2/native/libvinix-android-native.so` | `aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7` |
| Signed fixture | `resource-lock-fixture-2026-11-01-r3/probe.apk` | `bafc5f4e708f15fdb0d2868d8b332863c7ce429f1447952867968300e58e12dd` |

All five tool checks passed on their first attempt. Runner selftests rejected
1,941 malformed, mixed and failure cases. Transfer checks preserve exact pinned
snapshots, traversal/request/deadline controls and add malformed selector/port
refusals plus exact resource route/asset uniqueness assertions. ELF inspection
confirms static AArch64 EXEC without INTERP or DYNAMIC segments. This host
qualification establishes no ARM fixture or live Maps result.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 2.243 | 346,570,752 | 375,668,736 |
| Runner selftest | 1.142 | 22,298,624 | 17,776,640 |
| Static ARM runner compile | 2.769 | 366,018,560 | 363,380,736 |
| Host transfer compile | 2.889 | 370,884,608 | 381,665,280 |
| Transfer selftest | 1.438 | 10,633,216 | 9,404,416 |

Every guard and child exited zero with complete cleanup and zero swaps under
the unchanged 600 MiB aggregate RSS, 300-second, 512 MiB observed shared-growth,
1 GiB reserve, 4 MiB output and file-size caps. Runtime/tool/artifact inputs
were rehashed after checks; frozen sources still match the checkout. The Intent
r2 APK, runner, transfer and seal manifest were rehashed without modifying them.
Source base is `fea4b7a85b75a7db10300e1c1fcac3c49064ed84`; runner and transfer
source hashes are respectively
`1eddc5383df2115ccb7ce814a0e64933bcb5991499bf5ffb6fb54ef5fb6e651a`
and `0d98f92f61196157a636c6f1c19383235b599437beae7f6671c9349998f5aab3`.

ARM runner `S/resource-locks-api-run-2026-11-01-r1/run` has SHA-256
`a62460d72f5a20dcd239cf8abb8d479e4893ba167c970b1f1887b72c96482259`.
Transfer `S/resource-locks-api-transfer-build-2026-11-01-r1/transfer` has SHA-256
`bd66ede231a76a8b511586b98b1527b2700b0ce31ed9ba43b5ae5154b3c24a28`.
The four complete tool/control roots are closed. Full sealing and separate
fresh-process readback passed for 35 entries at
`S/resource-locks-api-tools-sealed-2026-11-01-r1/manifest.json`, SHA-256
`5895080689f336f04a1bbde112f1dbd001c9f4d78203889b6eacff3df004b538`.
Seal/readback took 0.096/0.273 seconds with zero guard/child exits, complete
cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/file-size caps. Controls remain in
`S/resource-locks-api-tools-seal-controls-2026-11-01-r1`. Independent source and
final pin/artifact/guard/ELF/seal reviews passed. Preserve all complete original
bundles and unchanged auditors.

## Corrected XML expectation, r2

The first ARM fixture run stopped on its XML parser expectation. The retained
parser returns `START_DOCUMENT` (0) on its first `next()` call before native
parsing returns `START_TAG` (2). The corrected fixture requires that exact 0,
then 2 sequence. Worker/iteration counts, resource literals and lifetime checks
remain intact. The framework, native library, helper, success marker and strict
runner checks are unchanged. This tool refresh changes exactly five source
constants: the runner's APK pin and the transfer's runner/APK paths and pins.
Original r1 fixture, tools and seal hashes were rechecked without modifying
them. This host qualification establishes no corrected ARM or Maps result.

The corrected signed APK is `S/resource-lock-fixture-2026-11-01-r4/probe.apk`,
SHA-256 `ef4188b65ffd8fd5c2c0b4c71494b45cec3dea9038bc4d2853ae3daa726c1da1`.
Its `build.json` SHA-256 is
`de1210a74c5475ff29d86dcf83de0a5a88c3c375ec917e16458b317af15cb683`.
All five refreshed checks passed on their first attempt, including 1,941 runner
refusals, the transfer selftest and actual static AArch64 EXEC inspection without
INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 2.569 | 345,604,096 | 371,343,360 |
| Runner selftest | 1.250 | 20,742,144 | 17,760,256 |
| Static ARM runner compile | 3.158 | 373,063,680 | 364,855,296 |
| Host transfer compile | 2.615 | 375,586,816 | 385,761,280 |
| Transfer selftest | 1.108 | 9,863,168 | 9,371,648 |

All guards/children exited zero with complete cleanup and zero swaps under the
original 600 MiB/300-second/512 MiB shared-growth/1 GiB reserve/output/file-size
caps. Runtime/tool/artifact pins were rehashed after checks, and both frozen
sources match the checkout. Captured source base is
`cc5f16b30c026a036a140877d1c983dd13000d96`; runner and transfer source hashes
are `a914e6a318cbab50a470440a6b066f96caf90f957290ede97017dd09ef9d9c85`
and `0383ebcd90cdfb7f940ed7df04590b3c787afcf34d314f59254a9730036796a1`.

ARM runner `S/resource-locks-api-run-2026-11-01-r2/run` has SHA-256
`f71e631a65fb1008a4a78ede0e11bb930bd7347f65007f4e3a32c7adceda986a`.
Transfer `S/resource-locks-api-transfer-build-2026-11-01-r2/transfer` has SHA-256
`bc4d215a634dd734d50028a4cfefaf63616bd3d718114ead26a7fee2c09c006d`.
The four r2 tool/control roots are closed. Full sealing and a separate
fresh-process readback passed for 35 entries at
`S/resource-locks-api-tools-sealed-2026-11-01-r2/manifest.json`, SHA-256
`b6e2cb3a7c08c71d99224ab1d4101d249f18ed0ce91a52ebb7d5eee571967da2`.
Seal/readback took 0.091/0.283 seconds with zero guard/child exits, complete
cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/output/file-size caps. Controls remain in
`S/resource-locks-api-tools-seal-controls-2026-11-01-r2`. Independent refresh
source, pin/artifact/guard/ELF/seal and report reviews passed.

## Theme diagnostics, r3

The r4 ARM fixture returned false from `nativeThemes` at worker iteration 0,
without identifying which native theme assertion failed. The r5 fixture adds
failure-only phase/cookie/type/data/pending diagnostics and a serial invocation
of the same strict theme checks before starting workers. Every assertion,
worker/iteration count, success marker and lifetime check is retained. The
framework, native library and runner health/check logic remain unchanged.
This refresh changes only the same five runner/transfer pin/path constants.
It provides diagnostic evidence collection; it does not establish an ARM pass,
identify the underlying failure or validate Maps behavior.

The diagnostic APK is `S/resource-lock-fixture-2026-11-01-r5/probe.apk`, SHA-256
`b90fe510799ddf4d550c1915d3a730ab2db3aacbcdc95122c2862a85afdb814f`.
Its `build.json` SHA-256 is
`b3f15545d0fb8ef340ef9500bec19044c82a31ca93a4b55626e63f91f4822704`.
All five refreshed tool checks passed on their first attempt, including 1,941
runner refusals, the transfer selftest and static AArch64 EXEC inspection
without INTERP or DYNAMIC segments.

| Check | Guard seconds | Sampled aggregate RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Host runner compile | 3.492 | 348,340,224 | 370,589,696 |
| Runner selftest | 1.490 | 20,791,296 | 17,776,640 |
| Static ARM runner compile | 3.504 | 377,946,112 | 359,235,584 |
| Host transfer compile | 3.321 | 371,097,600 | 379,912,192 |
| Transfer selftest | 1.832 | 9,453,568 | 9,338,880 |

All guards/children exited zero with complete cleanup and zero swaps under the
original 600 MiB/300-second/512 MiB shared-growth/1 GiB reserve/output/file-size
caps. Runtime/tool/artifact pins were rehashed after checks, both frozen sources
match the checkout, and predecessor r2 APK/tool/seal hashes remain unchanged.
Captured source base is `fcee5f780796f6df200eb4a44430741b16c80d8e`; runner and
transfer source hashes are
`1bd6fe60d69358d2e7f40d3f82e7888089411a99c5657fbb3277a6bed1e0f771`
and `a90b0c49f0b282bdedbd82d601cd302a713b3fae48f08c08521329dc16d557c3`.

ARM runner `S/resource-locks-api-run-2026-11-01-r3/run` has SHA-256
`fc4584fa5070b7398f4df6987348467e027538c4469377e5042cf395a349af78`.
Transfer `S/resource-locks-api-transfer-build-2026-11-01-r3/transfer` has SHA-256
`21870d9fa926f559c55f4d2466e43340b9af0927a674ceec45ac92c93277d818`.
The four r3 tool/control roots are closed. Full sealing and a separate
fresh-process readback passed for 35 entries at
`S/resource-locks-api-tools-sealed-2026-11-01-r3/manifest.json`, SHA-256
`2ad3b8facf6ae1ae4af460606664eba05725c7f704de3e181e157016ec98c883`.
Seal/readback took 0.115/0.434 seconds with zero guard/child exits, complete
cleanup and zero swaps under the unchanged 600 MiB/300-second/64 MiB
shared-growth/1 GiB reserve/output/file-size caps. Controls remain in
`S/resource-locks-api-tools-seal-controls-2026-11-01-r3`. Independent refresh
source, pin/artifact/guard/ELF/seal and report reviews passed.
