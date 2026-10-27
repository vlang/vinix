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
- The browser producer passed in 10.03 seconds at 398,835,712 bytes RSS with zero
  swaps and complete guard cleanup. The sealed-bundle source audit passed in
  0.82 seconds at 45,187,072 bytes RSS with zero swaps. Its manifest is
  `fa39f1486d651dff8904a9d75e82cf67d462b2c41511a1a4cd3a184c49239e62`,
  library `16def2047bf7605a23d949ff7b6b56bc56dcece038136553a98a0524b26ded1a`,
  and `build.json` `196758e035100e16b35aca4f3bc6988735c7588e167c28e62a55286c737bd6cb`.

Stager and patcher compilation, their selftests, preparation and runtime checks
remain pending. Free space briefly reached 1.255 GiB after the producer, then
fell below the 1 GiB reserve before either tool compiled. No Maps or Google
login result is established.

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
`/tmp/vinix-bounded-command-r3`, fresh external `log=` and `receipt=` paths,
`/usr/bin/time -l`, the unchanged 1 GiB reserve and a growth budget fully backed
by initial free space. A smaller 32 MiB compile budget is permitted; shared
volume drift still stops the process when it exceeds that cap. Preparation
also retains its own stricter phase accounting and 1.5 GiB initial floor.

Generated receipts, binaries and media belong under
`/Users/alex/.local/state/vinix/android`, outside Git. Keep the original bundles
complete for historical profile checks.
