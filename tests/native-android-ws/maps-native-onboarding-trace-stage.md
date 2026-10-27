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
growth policy remain enabled; explicit read-only audits refresh the disk
baseline. Module audits retain exact 68-byte, mode-0600 digest receipts and
charge a conservative 1 MiB budget allocation per receipt. Clone creation is
charged before its separate read-only hash verification. Receipt charges and
writable-phase drops remain cumulative without refunds.

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
`kernel-patcher-selftest.json`; that attempt did not complete the FAT tests.
The comparison's first
`v run` attempt encountered the same guard restriction; the successful
comparison uses a separately compiled executable. Guest validation remains
pending at this host-only checkpoint.

The complete kernel patcher self-test subsequently passed under the nested
process-group-aware r3 guard in 10.77 seconds at 26,443,776 bytes peak RSS,
zero swaps. This includes all nine profile validators and eleven FAT tests;
`kernel-patcher-selftest-r2.log` and `.json` retain the successful evidence.

Initial stage attempts remain preserved as `maps-native-onboarding-trace-r1`
and `-r2`. The first was stopped by the old guard's process-group restriction
after 73.616 seconds, with cleanup verified. The second passed outer process
supervision but stopped at the stager's 512 MiB write budget after 78.12 seconds
(52,330,496 bytes peak RSS, zero swaps): bulk original-module hashing had been
charged for unrelated shared-volume writes. Both failed before media cloning.
Their `prepare.log`/`.json` and `prepare-r2.log`/`.json` remain in the original
build directory. The accounting correction separates those audited media
reads and their bounded digest receipts; it retains both original disk limits
and all complete media checks. The corrected tool's build/evidence directory
is `maps-native-onboarding-trace-build-2026-10-27-r2` under the same external
Android state root. The corrected stager built in 7.23 seconds at 451,166,208
bytes peak RSS, zero swaps, then passed its focused self-test under the r3
guard.

Preparation passed for
`/Users/alex/.local/state/vinix/android/maps-native-onboarding-trace-r3`,
manifest `96b90172e338080ff50bf0e1188bdefc1f50e61fe3ad654593dfbac4d918d741`,
source revision `1fefb8dc2844175cb579b2cb7e5311f2241d8d21`.
All exact inherited module/dependency checks, payload inventory, inode modes,
APFS clone checks and media readback passed. The run took 191.56 seconds
(92.14 user, 61.60 sys), with 64,946,176 bytes peak RSS and zero swaps.
Final charged growth was 85,250,048 bytes, including 32,505,856 bytes allocated
to digest receipts; final free space was 19,385,405,440 bytes. The outer guard
passed with 66,256,896 bytes peak sampled process-tree RSS and verified cleanup.

The successful evidence in the corrected build directory is
`prepare-r3.log`, SHA-256
`37fe3b047117eca66b65cd261d1532ad7f7c2764f3c12ca6d2abce465371bccd`,
and `prepare-r3.json`, SHA-256
`553570f0993d2297358d756884996599b7f46c593e5ceb3d09cd9a4cdd889ec2`.
The staged boot digest is
`f90cb8b87b0fa2e4f34af9fe2f23026fbd2d029ac35481a735eeff507cdb3cd9`.
Fresh-clone, kernel-patch and live Maps validation remain pending at this stage
checkpoint; successful Google login is unverified.

At the subsequent 08:53 UTC checkpoint, a second fresh mutable clone was
prepared at
`/Users/alex/.local/state/vinix/android/maps-native-onboarding-trace-vm-r2`.
The earlier `maps-native-onboarding-trace-vm-r1` directory was preserved.
The complete sealed source/destination inventory and metadata checks passed
in 7.52 seconds at 21,250,048 bytes peak RSS, zero swaps. The adjacent
`maps-native-onboarding-trace-vm-r2-clone.json` receipt has SHA-256
`d0c24f26723e0a27ae4da475853e75a30d6a893e3c3d056e34ace83cf3cb44b8`.

The frozen kernel profile then passed all inherited media checks and kernel
readback in 46.19 seconds at 14,598,144 bytes peak RSS, zero swaps. Its
`kernel-patch.json` receipt has SHA-256
`1b51cf146b47cc33f8b820b28c8deedcfdb8cfab55e84fbe2b22eccaaf0fcc6f`;
the patched boot digest is
`7ad9f01f84ef4489629a9d989a0c1f888745bdc6b506aefaf15b336d50339766`.
The frozen kernel build receipt remains
`1e9077779aaed08188e6f8111ca9ceb27b479517ece736a58157049f004fb36d`.
Both operations passed the r3 process-tree guard with verified cleanup and
unchanged limits: 2 GiB RSS, 300 seconds, 1 GiB reserve and an explicitly
backed 8 GiB volume-growth allowance. The maximum sampled process-tree RSS
was 22,495,232 bytes for cloning and 27,164,672 bytes for patching.

The corrected build directory retains `fresh-clone-r2.log` (SHA-256
`b48234f037441a77ba4a0fe4c7c98f8060b7c4fe0d38e80e10423061b44718ca`),
`fresh-kernel-patch-r2.log` (SHA-256
`6505496a1392eb2ba2660c6834489066541b2252b42dbf8778a1191f5fbb6e99`),
and their `-bounded.json` guard receipts. The verified existing owned runner
was copied to that build directory as `runner-vm-r2`, digest
`2419d0760fa92a3e9caa3e60c5596836400616cad8205ca8e6118ade14979908`.
Its retained embedded source matches the current
`tests/android-webview-browser-probe/run.v`, digest
`c13a45576372481b911e0623dda7b0080438c7c5ba54b668c681459d57b67e12`.
No compiler or VM was started during this preparation. VM launch and live
Maps validation remain pending at this handoff; successful login is unverified.
