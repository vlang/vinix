# Maps browser result polling successor

`maps-browser-poll-stage.v` appends `maps-browser-poll.tar` to the sealed
`maps-native-heartbeat-r1` image, manifest
`70ea9f41ad045541066dec75a1ddcdc1e44efefd8d35ffb2e4414a77e2235b32`.
It preserves all 18 existing modules and 34 complete dependency bundles. The
new browser producer and heartbeat base bring the complete dependency set to 36;
the previous browser producer remains required.

The nineteenth module contains exactly two regular files, both mode `0644`:

- `opt/vinix-android-aarch64/usr/lib/libvinix-android-browser.so`
- `opt/vinix-maps-account/build.json`

The deployment receipt changes only the library's input digest and
`browser_client_manifest_sha256`. Its WebKit `browser_manifest_sha256`, native
heartbeat, framework, controllers, launcher and headless receipts remain
identical. Every historical overlay participates in the inode mode audit.
The new browser bundle receives the complete `verify_browser_client` audit with
an empty runtime dependency map; this profile introduces no runtime dependencies.

Preparation uses fresh APFS media clones, complete input audits before and after
the append, exact module readbacks, embedded source provenance and a sealed
output inventory. It requires 1.5 GiB initially free, retains a 1 GiB reserve and
limits cumulative charged writes to 512 MiB. Each exact 68-byte module digest
receipt receives a separate 1 MiB charge. Read-only audits refresh the shared
volume baseline without refunding prior charges. These guards are inherited
unchanged from the heartbeat stager except for the nineteen-module bound.

The selective browser producer reuses the complete
`current-browser-build-2026-10-26-r2` baseline, manifest
`af2373af972966cc72b2b8eb8ba90d73063fad5d24a4a76b29ce8daff78062f3`,
and its retained `bootstrap-builder`, SHA-256
`d13e16230e758444e0d70619cd524e4e297cb61c17f8a9c2583e386c1bf38896`.
The compiler is `/Users/alex/code/v-tccbin-bootstrap-20261026/v`, SHA-256
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
The exact source audit accepts one reviewed change among 347 inputs, retaining
all 346 others, the 18 production input paths, bootstrap and compiler identities.
The browser correction is committed as `9f01a1edb`; the accepted `client.c.v`
digest is `3d40120b6b3c8c3fd60d54fed64977476d588f88b39665e2766a132507a74513`.

The producer ran under a 2 GiB RSS limit, 300-second deadline, 1 GiB disk reserve
and 256 MiB disk-growth limit. Selective compilation reuses the frozen bootstrap
and avoids native/framework rebuilds. Its measured growth was 107,823,104 bytes;
the 256 MiB allocation leaves room for its retained closure and receipts.
The command was:

```sh
env VINIX_CURRENT_LAUNCH_COMPILER=/Users/alex/code/v-tccbin-bootstrap-20261026/v \
  VROOT=/Users/alex/code/v-tccbin-bootstrap-20261026 \
  V=/Users/alex/code/v-tccbin-bootstrap-20261026/v \
  VINIX_V_COMPILER=/Users/alex/code/v-tccbin-bootstrap-20261026/v \
  /Users/alex/.local/state/vinix/android/current-browser-build-2026-10-26-r2/bootstrap-builder \
  --browser /Users/alex/.local/state/vinix/android/current-browser-build-2026-10-27-poll-r1
```

Host evidence is retained in
`/Users/alex/.local/state/vinix/android/maps-browser-poll-build-2026-10-27-r1`:

- Source-checker compilation passed in 2.13 seconds, with 372,916,224 bytes peak
  sampled RSS. The earlier disk-preflight rejection remains in
  `checker-compile-guard.json`; the successful retry is `checker-compile-r2-guard.json`.
- Checker selftest passed in 0.30 seconds at 20,905,984 bytes RSS; the live source
  audit passed in 0.83 seconds at 32,292,864 bytes RSS, both with zero swaps.
- The browser producer passed in 10.03 seconds; `/usr/bin/time` recorded
  398,835,712 bytes maximum process RSS, while the guard's sampled supervised
  process-tree peak was 442,531,840 bytes. It recorded zero swaps and complete
  guard cleanup. The sealed-bundle source audit passed in
  0.82 seconds at 45,187,072 bytes RSS with zero swaps. Its manifest is
  `fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62`,
  library `16def2047bf7605a23d949ff7b6b56bc56dcece038136553a98a0524b26ded1a`,
  and `build.json` `196758e035100e16b35aca4f3bc6988735c7588e167c28e62a55286c737bd6cb`.

Tool validation resumed on 2026-10-28 in
`/Users/alex/.local/state/vinix/android/maps-browser-poll-build-2026-10-28-r1`:

- The exact browser source/bundle recheck passed again (347 inputs, one change,
  346 preserved) in 1.42 seconds at 51,232,768 bytes sampled process-tree RSS.
- Stager compilation passed in 5.13 seconds at 445,251,584 bytes sampled
  process-tree RSS; `/usr/bin/time` recorded 527,777,792 bytes process maximum
  RSS. Its complete selftest passed in 0.28 seconds, with 13,336,576 bytes
  process maximum RSS. The two selftest-only fixture corrections are committed
  as `f38a6ccd0`: independently copy JSON values for mutation, and ensure each
  negative input mutation changes the original value. The earlier compiler and
  no-op mutation failures remain in the original logs.
- Patcher compilation passed in 19.25 seconds at 585,498,624 bytes sampled
  process-tree RSS (550,977,536 bytes process maximum RSS). Its complete
  selftest, including all historical FAT profiles and the new browser profile,
  passed in 32.15 seconds at 30,654,464 bytes sampled process-tree RSS
  (19,185,664 bytes process maximum RSS). The first selftest stopped at its
  128 MiB disk-growth cap; the unchanged retry used 512 MiB and observed
  311,926,784 bytes of shared-volume growth.

Every successful command above exited zero with complete guard cleanup;
`/usr/bin/time` recorded zero swaps. Stager binary SHA-256 is
`9bac87cba0a63fd04b35b4c0b270bf742aa987928e6bbade0b4a710a9fc60129`;
patcher binary SHA-256 is
`aae7e0c186a7afca696066b29f085e9aa8f096def9eff2ba7a71398c7a5a3793`.

Preparation's first attempt stopped during read-only input audits after 71.01
seconds: shared-volume growth reached 556,802,048 bytes against an external
512 MiB guard. No destination existed. The retry retained that failure and
used a 2 GiB external cap. It stopped at 291.47 seconds after cloning media
and installing the overlay, when shared-volume growth reached 2,156,867,584
bytes. The internal cumulative writable-phase charge was 48,799,744 bytes,
still below the unchanged 512 MiB limit. Its partial
`/Users/alex/.local/state/vinix/android/maps-browser-poll-r1` is preserved.
Both guard stops completed cleanup.

The next preparation attempt used
`/Users/alex/.local/state/vinix/android/maps-browser-poll-r2` and the tested
long-audit guard at
`/Users/alex/.local/state/vinix/android/long-audit-guard-2026-10-28-r1/tools/bounded-command`,
SHA-256 `2af530965c86841d5c31c7f8a92590dec602f9246b54d32a892683adc929b7c5`.
Its explicit 900-second limit allows complete input audits before and after
staging; the default guard limit remains 300 seconds. The external shared-volume
growth allowance is 8 GiB, backed by 14.3 GiB initially free, while the 600 MiB
RSS limit, 1 GiB reserve and internal 512 MiB cumulative writable-phase cap stay
unchanged. The complete guard checker passed default and extended limits,
boundary rejection, real short-deadline cleanup, RSS, output and disk controls.
That attempt reached the complete final input recheck, then stopped at 329.20
seconds because an RSS monitor subprocess exceeded its one-second deadline.
Guard cleanup passed, sampled peak RSS was 70,451,200 bytes, observed shared
growth was 2,782,273,536 bytes and the internal writable-phase charge was
42,049,536 bytes. Its partial output is preserved without a stage receipt or
seal; this monitor timeout establishes no runtime result.

The unchanged guard then passed preparation in fresh
`/Users/alex/.local/state/vinix/android/maps-browser-poll-r3`. Its preflight had
10.97 GiB free; the guard's initial sample was 11,406,413,824 bytes, backing the
same 8 GiB external allowance and reserve. `prepare-r4.guard.json` records exit
zero, complete cleanup, 364.512 seconds, 67,649,536 bytes sampled process-tree
RSS and 3,356,667,904 bytes maximum shared-volume growth. `/usr/bin/time`
recorded 364.41 seconds, 66,584,576 bytes process maximum RSS and zero swaps.
Complete before/after input audits, all nineteen exact module readbacks and
the final output inventory passed. The receipt records 43,274,240 bytes charged
before receipt/inventory writes; the final log records 49,238,016 bytes, below
the unchanged 512 MiB internal cap.

The sealed stage records source revision
`41f03337d50d38446799dc98e2fece4b626e87a5` and inventory manifest
`f27b08e45994fb2e9cf2c2aac695e73c62f17e0b4785fdb310cbebb1f54ac297`.
Its `stage.json` digest is
`4692307a3614d12f37f69f57f5ca0f9a6f4f9d4b48ef249760d2fd95553fb9eb`,
boot image digest is
`8dbdf03669e6ed7545c172095112bc3e3008ad3a08d341ce389fe718158f6434`
and firmware-state digest is
`d3b3f7afddb44de7020b8544270a67791fca44a48864dcd550cefee633463cbf`.
The successful guard receipt digest is
`ec079b3af817974ae80d5c90e08510bed92f4c200ca42b71991feacd75334658`.
The complete build root, including every failed command, remains retained for
the later runtime audit's full integrity seal. These host checks establish no
Maps interaction or Google login result; fresh runtime validation remains
pending.

Checker commands use fresh external report paths. Stage commands follow guarded
compilation and require the disk floor:

```text
maps-browser-poll-source-delta --self-test
maps-browser-poll-source-delta --live FRESH_EXTERNAL_REPORT
maps-browser-poll-source-delta --bundle /Users/alex/.local/state/vinix/android/current-browser-build-2026-10-27-poll-r1 fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62 FRESH_EXTERNAL_REPORT
maps-browser-poll-stage --self-test
maps-browser-poll-stage --prepare FRESH_EXTERNAL_OUTPUT
patch-kernel --maps-browser-poll FRESH_VM_CLONE FROZEN_KERNEL_BUILD BUILD_JSON_SHA256
```

The remaining tool builds use the same pinned compiler and private `VROOT`
above, with `-new-compiler -prod -gc boehm -nocache -cc cc`. The stager module
path is `/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib`;
the patcher omits its first component. Build sources are
`tests/native-android-ws/maps-browser-poll-stage.v` and
`tests/android-webview-browser-probe/patch-kernel.v`. Use fresh binaries under
the retained build root, serialize compilations, and wrap each command with
the retained bounded-command guard, fresh external `log=` and `receipt=` paths,
`/usr/bin/time -l`, the unchanged 1 GiB reserve and a growth budget fully backed
by initial free space. A smaller 32 MiB compile budget is permitted; shared
volume drift still stops the process when it exceeds that cap. Preparation
also retains its own stricter phase accounting and 1.5 GiB initial floor.

Generated receipts, binaries and media belong under
`/Users/alex/.local/state/vinix/android`, outside Git. Keep the original bundles
complete for historical profile checks.
