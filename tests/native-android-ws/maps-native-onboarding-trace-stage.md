# Native onboarding trace overlay

`maps-native-onboarding-trace-stage.v` prepares a diagnostic successor to the
immutable `maps-onboarding-trace-r2` image, manifest
`de315f3f5f0120efbd1368a47e11db945aa9212160fc7e1ff351e522e9435be5`.
It preserves all fifteen modules and appends a five-file native overlay:
the JNI library, its two headless provenance receipts, headless input pins,
and the Maps deployment receipt. The headless contract changes only the JNI
digest. The deployment changes exactly four consumed input digests and the
native manifest identity. Framework, controller aliases and launcher remain
at their existing exact identities.

The stage verifies the complete original dependency bundles before and after
preparation, strict native link/export receipts coupled to the retained
broadcast-result framework, the unchanged seven-argument service ABI sources,
all module digests, payload paths, cumulative inherited inode modes and media
readback. APFS clones have no copy fallback. Streaming hashes, bounded command
output and the predecessor's 1 GiB reserve/512 MiB cumulative writable-phase
growth policy remain enabled; read-only audits refresh the disk baseline.

Native tracing uses the existing `VINIX_ANDROID_TRACE_TREE` activation from
`maps-account-guest --broker --trace-onboarding`. The native changes print
bounded input delivery, pre-draw and publication outcomes. They do not prove
Google authentication or that onboarding advances.

Build both tools serially with peak RSS and swaps recorded via
`/usr/bin/time -l`, using the same pinned compiler and Boehm GC as the
[controller trace stage](maps-onboarding-trace-stage.md). Compile the stager
with `-new-compiler -prod -gc boehm -nocache -cc cc` and this module search path:

```text
/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib
```

Run the stager's `--self-test`, then `--prepare FRESH_EXTERNAL_OUTPUT`.
Clone the sealed stage with the existing generic fresh-clone tool. Patch only
that mutable clone using `patch-kernel --maps-native-onboarding-trace` with
the exact frozen kernel build and receipt. On this host, shell file-size
limit requests are rejected; no file-size limit is claimed. Use the repository
`bounded-command.v` runner for process-tree RSS, time, disk reserve/growth and
output limits, while allowing the existing boot image's apparent size above
16 GiB. The stager's separate reserve and growth checks remain enabled.

The deployed/live comparison tool `maps-native-source-delta.v` checks all 87
production JNI sources, their exact source set and the unchanged binding
specification against the deployed startup producer
`current-native-build-2026-10-27-startup-r1`, manifest
`a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20`.
It permits changes only to `nativews/diagnostics.v` and `nativews/ws_views.v`.
The first comparison passed in 3.59 s with 322,174,976 bytes peak RSS and zero
swaps. Its external report is
`/Users/alex/.local/state/vinix/android/maps-native-source-delta-2026-10-27-r1.json`.
Comparison source revision: `3b393d2cb`.

After the strict-C pointer correction, the final comparison again passed all
87 sources with exactly those two diagnostic changes. Its report is
`/Users/alex/.local/state/vinix/android/maps-native-source-delta-2026-10-27-r3.json`.
The final `diagnostics.v` digest is
`dca8298349f52307542092707856e9bb472b7bd031b772d7003640e8003c0176`;
`ws_views.v` is
`1b74f775e27f1c7a392b9fd659c0d7000993a1b23bb3857f8c5363d7e6b58901`.
The standalone comparison passed in 0.30 seconds at 6,488,064 bytes peak RSS,
zero swaps; its separate build used 347,848,704 bytes peak RSS, zero swaps.

The producer's generator closure also includes one expected compatibility
change in `tests/native-android-tools/androidtools/native_ws.v`: it validates
and skips the canonical Java `VinixBroadcast.run` bridge required by the
retained broadcast-result framework, rather than exporting that Java method
as a lazy native binding. Other stale or non-native bindings remain errors.
Its deployed digest `c393323fcbd70d7012a964bb305a7a676a23460fd6fea92aa856420387286fb3`
changes to `2725ddfc834aba66d052ecdd4d7de2b5ef5853c6280e7870e0ba8796fd24f751`.
`tests/linuxkpi/generate_module.v` and `build-support/find-v.sh` retain their
deployed identities. The production JNI source delta remains the two native
diagnostic files above.

The complete native producer is
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-27-onboarding-r5`,
manifest `05baf5d011337d54aab26f6cc3c535f801221d51aceb966ebc9442d88b5fd6b8`.
Its library digest is
`efcf0a270d2116245558b35811a2a2b714f8348c90c5e1bdb9aaf91ae278f65c`,
and its build receipt digest is
`3ed2de875f39583ac86b83ebeeca027185757cbce396a29556cff48b679d1b04`.
The guarded producer passed in 52.32 seconds with about 629.7 MB peak RSS
and zero swaps.

Host tools and command receipts are retained under
`/Users/alex/.local/state/vinix/android/maps-native-onboarding-trace-build-2026-10-27-r1`.
The stager built in 10.71 seconds at 475,561,984 bytes peak RSS, zero swaps,
and passed its self-test. The kernel patcher built in 12.99 seconds at
538,443,776 bytes peak RSS, zero swaps; its first command omitted the Android
module search path and was corrected in `kernel-patcher-build-r2.log`.
All nine kernel profile self-tests passed before the outer process guard
rejected the generic FAT test's intentional command-helper process group.
That rejected attempt and verified cleanup remain in
`kernel-patcher-selftest.json`; complete FAT self-test and preparation remain
pending safe supervision of those subprocess groups. The comparison's first
`v run` attempt encountered the same guard restriction; the successful
comparison uses a separately compiled executable. Runtime validation remains
pending; no new stage or guest pass is claimed here.
