# Prepared ART Makefile integration; checks blocked

Continuation of 475aa3ff6. Google sign-in remains unresolved, and no ART runtime
change has been deployed. `art-generator-overlay.v` prepares an external patch
for ten original Makefiles to invoke the checked V generators. The final
integration source and additional package-cleanup helper have not compiled or
passed their checks yet. Do not use this checkpoint as build qualification.

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
Its written self-test checks repeated/missing/duplicate replacements, zero-fuzz
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

Original caps remain RSS 629145600 bytes, wall 300000 ms, reserve 1073741824,
growth 536870912 and output 4194304 bytes. No VM was started. Next checks are
fresh guarded builds of both tools, the overlay self-test, the full source
helper self-test including package cleanup, platform-mode execution and the
50-header source check. Then apply to a fresh native source tree alongside
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
| art-source-generators.v | b11b1d619393c15d43c569bd1fb3d1513640a7b1f755243c7f49d4a40e8de4c7 |

External evidence is under `/Users/alex/.local/state/vinix/android/`:
`art-make-tools-20261114-r1`, `art-make-tools-20261114-r2`,
`art-make-helper-tools-20261114-r1` and `art-make-checks-20261114-r1`, each
with sibling logs/receipts. The failed check receipt SHA256 is
c4e5d9a22e1d6e81fba5310afd3ec54afe122de758bfcef19b2889585d24b57e;
the refused compiler receipt is
5d299e61e10a68d2f64b790d5c2d358c2b7cce46aee4ff3f45295adde8976719.
