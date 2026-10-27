# Maps native heartbeat diagnostic successor

`maps-native-heartbeat-stage.v` adds an opt-in native main-stage heartbeat and
input-read checkpoints to the sealed `maps-onboarding-framework-r1` image. It
retains the repaired framework JAR/DEX, controller aliases, launcher, all 17
existing modules, and all 32 complete dependency bundles. The new eighteenth
module contains five regular files: the native library, its two producer
receipts, the headless input receipt, and the Maps deployment receipt. Only four
deployment input pins and its native manifest identity change; the headless
receipt changes only the library pin.

The separate `maps-native-heartbeat-source-delta.v` checker compares the new
native source closure with the deployed `current-native-build-2026-10-27-onboarding-r5`
bundle. Exactly `diagnostics.v`, `runtime.v`, and `ws_views.v` may change to the
reviewed hashes from commit `206610088`; the other 84 production sources,
binding inventory, generator helpers, generated JNI, and consumed broadcast
framework remain identical. The historical source checker and profiles remain
available with their original inputs.

The producer reuses the sealed private-VROOT bootstrap and old broadcast
framework for identical generated JNI. The guest retains the later onboarding
framework. The stager verifies both complete producer bundles and all inherited
dependencies before and after preparation, uses fresh APFS clones, preserves
existing inode modes, and checks every media module before and after the append.
Its accounting retains a 1 GiB reserve and a cumulative 512 MiB write budget;
each exact 68-byte digest receipt consumes a separate 1 MiB allocation within
that budget. Explicit read-only audits refresh the shared-volume baseline without
refunding writes. The outer process guard measures aggregate RSS, elapsed time,
volume growth and bounded output; no shell file-size limit is claimed.

`patch-kernel.v --maps-native-heartbeat` accepts only this exact profile: 17
preserved modules plus the heartbeat overlay, 34 complete dependency seals,
strict receipt deltas, and the frozen pidfd/wait kernel. Generic fresh-clone
validation remains unchanged. Runtime validation and Google login remain pending
until the new sealed image is booted and exercised.

The reviewed profile is committed as `abc45f8cb`. Generated evidence stays outside
Git under `/Users/alex/.local/state/vinix/android`. The native producer is
`current-native-build-2026-10-27-heartbeat-r1`; its manifest is
`6619a4cd8dcc7e30aa43120494b874f230d1e9b8ee5c5b756e25fcf5e5148eae`,
build receipt `ac77be848928c47ea5371a6f6532152d00c3ee8470e8f911d5748b61fa50c1f6`,
and library `3ac3ec1a026a409ec52b7973d9dcc4593bd5d266fc2c6e77fc5d5c1a88e439d9`.
Its complete producer checks passed in 65.73 seconds with 629,899,264 bytes peak
RSS and zero swaps. The process-tree guard recorded 664,371,200 bytes sampled
aggregate RSS, 325,251,072 bytes maximum shared-volume drop, successful cleanup,
and exit zero. The producer log and guard receipt are adjacent to that root.
Their SHA-256 hashes are respectively
`cf9f7222564717d6d96db8558233b2299a461dd2cff446d5106154306e5aa8d0`
and `4841d65fc1333ec0326e01db6807d22534db6004c143723f9821e85f4aa225c4`.

Host checks are retained in `maps-native-heartbeat-build-2026-10-27-r1`:

| Check | Result | Peak RSS | Real seconds |
| --- | --- | ---: | ---: |
| Source-checker build | PASS | 345,194,496 B | 2.82 |
| Stager build | PASS | 448,102,400 B | 8.78 |
| Patcher build | PASS | 570,638,336 B | 6.31 |
| Stager selftest | PASS | 11,894,784 B | 0.24 |
| Full patcher selftest | PASS | 19,628,032 B | 10.00 |

All measured commands reported zero swaps. The source checker selftest and both
live-source and sealed-producer audits passed, confirming the exact 87/3/84
source partition. Independent review read back their reports, logs and guards,
plus both profile selftests and all historical patcher/FAT controls. The initial
checker compilation stopped at an older-compiler syntax error; its failed log
and guard are retained beside the successful `checker-compile-r2` evidence.
The successful command arguments and process limits are in the corresponding
`*.guard.json` files. No compiler slot or process guard was bypassed.

The stager executable is `stage-tools/maps-native-heartbeat-stage`, SHA-256
`c20061962915c1113b6c949b900a0fbfe91fab0ddd1b356a906890cdc98830c6`.
The patcher is `patcher-tools/patch-kernel-native-heartbeat`, SHA-256
`ab4199060146daee7837f47f84733236d3ae3983f539825c0577efc1da016f95`.
Preparation passed for `maps-native-heartbeat-r1`, manifest
`70ea9f41ad045541066dec75a1ddcdc1e44efefd8d35ffb2e4414a77e2235b32`,
in 141.85 seconds with 79,495,168 bytes peak RSS and zero swaps. Its final
cumulative charge was 69,603,328 bytes and available space 5,593,722,880 bytes.
The 2 GiB outer volume-growth guard observed a 138,551,296-byte maximum drop,
80,019,456 bytes sampled aggregate RSS, exit zero and complete process cleanup.
Its original inner reserve and write limit remain enforced. `prepare.log` and
`prepare.guard.json` retain the measurements. This sealed stage is ready for a
fresh clone and the exact frozen-kernel patch; no boot or login is claimed here.

The adjacent `maps-native-heartbeat-build-2026-10-27-r1.sha256.txt` covers all
25 retained host-build files, including failed and successful checker logs,
executables, source audit reports, compilation/selftest guards and preparation
evidence. Its SHA-256 is
`8af620c8fe061894e67a58a36767860aa87b725f72905495120111476e3dfceb`.
Independent readback verified every checksum, exact recursive membership with
no links or special files, producer receipts, preparation measurements and the
table above. The sealed evidence roots were left unchanged.
