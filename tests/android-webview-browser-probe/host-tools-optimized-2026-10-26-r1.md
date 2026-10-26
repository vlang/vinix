The unchanged kernel patcher, guest runner and evidence sealer were rebuilt with
the pinned old V compiler and `-prod -cc clang`. All three retained compiler logs
show `clang -std=gnu11 -O3 -flto`; all existing self-tests passed. No validation
checks, guest images or production tool sources changed.

The complete host-tool audit bundle is outside Git at
`/Users/alex/.local/state/vinix/android/maps-host-tools-optimized-2026-10-26-r1`.
Its sibling `maps-host-tools-optimized-2026-10-26-r1-sha256.json` inventories every
child's mode, contents and symlink target; SHA256:
`31331353567ef5794703bf07990c30bc20fa7864fe774ca4a13c1eee15fa8031`.
`build.json` SHA256:
`2f46ccbe4a6f5302b95631d6519d75cd95aae0adc250f0dff02c275158f2b857`.

| Tool | Source revision | Exact source SHA256 | Executable SHA256 |
| --- | --- | --- | --- |
| `patch-kernel` | `51a2af3090304acb0add6ebb92e36ec97d44a95e` | `1cc14f493bef51f955d85252c543ab3722c3d3fc7fe9851ad73a938741968a0d` | `f9d530d14f28e7567287b7edcc23f730e1cfc4e95e4be0db2be6b16058a591c1` |
| `run` | `b81dd5c8c702b278f3e57fe7143804c5a570bea9` | `7953d7540600aa37daa3b721eaa974c3d08d1fb9b687fe362d521f986bbbcfd9` | `cfe95909d62aac2ab108920462362a1d0a10e5f84240562c4bfa0b8509190f49` |
| `seal` | `8239e1f93cd5a19f74e529949c9e14ba6216effd` | `9b990d6c2bc849f7732a8e18662f84564dc8adb833f148888004e628c28cec6a` | `b6415ce2ebf2159c10f86276135d5b8a68ee06584d71af9968bd586718e25cfd` |

The compiler is retained in the complete original dependency bundle at
`/Users/alex/.local/state/vinix/android/unix-recvmsg-kernel-x86_64-2026-10-26-r2/compiler/v`:
V `0.5.2 b5bcdbb`, SHA256
`109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e`.
From the repository root, each build used that compiler with
`-prod -cc clang -showcc -path '@vlib|build-support|build-support/android' -o BUNDLE/NAME tests/android-webview-browser-probe/NAME.v`;
the sealer also used `-keepc`. The audit bundle retains native link objects,
Clang version, logs, exact entry sources and the receipt recorder. This is an
entry-source/build/test receipt, not a replacement for a complete compiler
source closure.

The recorder `host-tool-receipt.v` verifies the compiler pin, unchanged source
pins, exact source bytes embedded in each executable, optimization flags and
existing self-test PASS markers before producing `build.json`. The original
complete compiler dependency bundle remains required. The full bundle inventory
was written and checked with the maintained browser inventory tool.

The patcher still passes both browser and Maps FAT replacement tests, exact
module/firmware readback, bad-pin rejection, configuration/inventory/symlink
checks and historical launch guards. The runner still passes process ownership,
complete output, stopped/disappeared guest and `cleanup-gone` socket checks.
The sealer still passes full-tree tampering, observed absence, stop receipts,
manifest pins, live-process rejection and special-file rejection.

The old `maps-kernel-patch-tool-r2` executable has SHA256
`92d7f519dd7b520d10aca64c73da52591ef7d70267559fa4b9838d973a89e6c7`.
Its original compile invocation was unavailable; retained disassembly shows the
SHA256 loop's stack-heavy code, consistent with an unoptimized build. The new
optimization flags are directly evidenced by the compiler log. Existing patch
self-tests took 2.36 seconds for the old tool and 1.25 seconds for the new tool;
runner and sealer tests took 1.52 and 0.27 seconds. These small fixtures are not a
full-image throughput benchmark. The sealer already uses CommonCrypto SHA256;
the patcher and runner use pure V SHA256. These results establish host-tool
validation, not guest execution or successful Google account login.
