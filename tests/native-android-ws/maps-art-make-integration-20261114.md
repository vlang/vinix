# Checked ART Makefile integration

The subsequent [native build continuation](maps-art-native-build-20261114.md)
extends this checkpoint to eleven Makefiles, an explicit 16-KiB buildspec and
an 18-file applied-input gate. Native compilation exposed generator allocation
and compiler-memory limits; the tested fixes and remaining build failures are
recorded there. The ten-file checks and identities below describe the earlier
801c43674 checkpoint, not the later build inputs.

Continuation of 475aa3ff6 and the initially blocked 718f690a7 checkpoint.
Google sign-in remains unresolved, and no ART runtime change has been deployed.
`art-generator-overlay.v` now passes its source-integration checks and prepares
an external patch for ten original Makefiles to invoke the V generators.
The package-cleanup helper also passes its fixture checks. Actual native ART
compilation and ARM validation remain pending.

The overlay replaces Makefile discovery in main.mk, definitions.mk and
cleanspec.mk; enum operators in five ART modules; assembly constants in three
modules; and interpreter commands in runtime/Android.mk. Interpreter output
uses explicit shell redirection while preserving Make's deferred automatic
variables and template glob. Native helper paths are
`/usr/local/bin/vinix-art-source-generators` and
`/usr/local/bin/vinix-art-mterp`. The build host must supply ARM64 executables
compiled from the current V sources before applying the overlay.

dumpvar.mk uses the V helper's new `platform` mode for descriptive OS metadata
via uname. The native build is supported on ARM64 Linux. Definitions for other
architectures also have their interpreter command rewritten, but those targets
are unqualified. Conditional Java-layer checking remains in the unchanged Java
compilation recipe; Java/image/CTS targets are outside this native build scope.

Review found another Python invocation in post_clean.mk: its package-overlay
comparison runs on incremental Make invocations. The new V `package-overlays`
mode preserves added/changed/removed package detection, whitespace normalization,
duplicate-key behavior and carry-forward of packages outside a partial build.
It appends only to the current overlay configuration, matching the original
implementation. Written fixture checks cover these cases, repeated invocation,
empty input and preservation of the other two files. No Python was executed
or modified.

```text
art-generator-overlay SOURCE_ROOT FRESH_OUTPUT
art-generator-overlay --self-test SOURCE_ROOT FRESH_OUTPUT
art-source-generators platform
art-source-generators package-overlays ALL_PACKAGES CURRENT_OVERLAYS PREVIOUS_OVERLAYS
```

The overlay requires exact command occurrence counts, records original/modified
Makefile hashes and a patch hash, preserves originals and refuses output reuse.
Its passing self-test checks repeated/missing/duplicate replacements, zero-fuzz
patch dry-run/application and readback. A GNU Make fixture executes the exact
rewritten ARM64 definition through eval, using printf to record the expanded
arguments and checking globbing and output redirection. It does not substitute
for the separate real interpreter source checks or native assembly/linking.

The preliminary nine-file tool compiled with available V 0.5.2 39e0e79 under
the original caps in 1047 ms, sampled RSS 294830080 bytes. Its first self-test
failed on the conditional Java-layer command. Review then identified and
ported incremental package-overlay cleanup and expanded the integration to
ten files. The updated r2 compiler invocation was refused before launch at
1356816384 free bytes: exit 125, child exit -1, PID 0, reason `disk growth
budget`, no supervised groups and `cleanup_complete=false`. No passing result
is claimed for that invocation. Free space subsequently fell below 1 GiB.
Space later recovered, allowing final r3 overlay compilation (2021 ms, sampled
RSS 304873472 bytes) and r3 helper compilation (1419 ms, RSS 309690368 bytes).
The overlay self-test passed in 389 ms, including exact application to all ten
files and GNU Make eval/argument/glob/redirection execution. The updated helper
passed its complete self-test, including package cleanup, and all 50 original
enum headers. An initial platform probe failed on macOS's uname path; the helper
now resolves uname through PATH and passed the guarded metadata check. All
final guarded checks returned 0/0 with complete cleanup under the same caps.

Original caps remain RSS 629145600 bytes, wall 300000 ms, reserve 1073741824,
growth 536870912 and output 4194304 bytes. These host checks started no VM.
Next, stage the ARM64 helpers and apply to a fresh native source tree alongside
the complete ABI/lifetime and imageless-compilation patches, retain compiler
inputs, rebuild ART and run the signed ARM regression and real Maps retry.

Read-only patch recovery also confirmed that the shutdown runtime manifest's
patch SHA256, 25be8e8a75bb317b9aa570ff89adb893f94196e8272de71586ee764c51a04554,
matches `build-support/android/art16k.patch` at 66c116f01. The current patch
is 26baba1150c148ee548caad36058bdb7e4071ae219620a5ed9c7ba52b1785039;
2592c266f added androidfw configuration support to that base. Preserve the
current patch and compare its six audited base files with art-expected-source
when reconstructing the build. This is runtime input recovery; V remains the
available current compiler.

Source checkpoint SHA256 values:

| Source | SHA256 |
| --- | --- |
| art-generator-overlay.v | 5488eb024ec5e09694603e7f40bc062ea2db100981e0be32f0178942dd3e3d72 |
| artgenerators/package_overlays.v | e85dd197021f7846c67dfffe94d5eea314b59d7d0ce9e97955fb06f6f6f55e77 |
| art-source-generators.v | d3aaac8657856b078957e5ac6d4f0583e1fcbfcc0673dd2c15fe39879d250c9e |

Qualified external artifacts:

| Artifact | SHA256 |
| --- | --- |
| art-make-tools-20261114-r3/art-generator-overlay | 515e1e053a7adc06a1a7f26733cdf4ab102d98f486816caa279b15931cdf1ac7 |
| art-make-helper-tools-20261114-r3/art-source-generators | e0169562bde7c19f4e189df21fd7a532da47b453ca6f64790249479932403743 |
| art-make-checks-20261114-r2/overlay/v-generators.patch | 812cc2b6224a8f7e624e795b6798c52d76131d75741cb9621834d557a9bead9f |
| art-make-checks-20261114-r2/overlay/inputs.json | ae2c32254aba519c95e73005afcec12dff532e6e98570dd71d684727ed8e7af1 |

External evidence is under `/Users/alex/.local/state/vinix/android/`:
`art-make-tools-20261114-r1`, `art-make-tools-20261114-r2`,
`art-make-helper-tools-20261114-r1` and `art-make-checks-20261114-r1`, each
with sibling logs/receipts. The failed check receipt SHA256 is
c4e5d9a22e1d6e81fba5310afd3ec54afe122de758bfcef19b2889585d24b57e;
the refused compiler receipt is
5d299e61e10a68d2f64b790d5c2d358c2b7cce46aee4ff3f45295adde8976719.
Final passing roots/receipts are `art-make-tools-20261114-r3`,
`art-make-helper-tools-20261114-r3`, `art-make-checks-20261114-r2`,
`art-make-helper-checks-20261114-r2`, `art-make-source-checks-20261114-r2`
and `art-make-platform-20261114-r1`.
