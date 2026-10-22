# Captured package image integration

The package stager captures the signing/SDK licenses and the two package action
definitions before compilation. It publishes notices, default actions, the
Software launcher and application-registration link through captured image
directories, and prepares the package state directory without initializing
consumer state. This closes the ordinary `cp`/`chmod` and remove-then-symlink
paths that could follow a license alias outside the image or leave a missing
launcher after interruption.

Each source is a controlled, ordinary single-link file of 1 byte to 64 KiB.
Capture checks its descriptor, name, size, mode and digest. Subsequent source
changes cannot affect the captured bytes. Every image directory component is
opened without following aliases, checked for controlled ownership/permissions
and required to stay on the admitted image filesystem. Publication rechecks the
root, full parent chains and package state identity. Existing controlled
directory modes are preserved; newly created directories use 0755.

All six outputs are prepared before any integration entry is published. Files
use mode-0644 private temporaries, complete writes, flushes and atomic renames.
Links use exclusive random temporary names and atomic renames. Replacing a leaf
alias or hard link never writes through it. Administrator action/registration
overrides are preserved; a late competing override refuses exclusive
publication. Cleanup removes only matching owned temporaries and preserves
replacements. A late failure reports an incomplete image; saved files remain
saved. Whole-image publication remains per-file staging, and builders must
distribute only a successfully completed image.

The [core fixture](../../tools/packages/pkgcore/image_integration_test.v) checks
**82 cases** across both architecture declarations: captured-source removal,
missing/aliased/hard-linked/writable/empty/oversized/FIFO sources, source-parent
aliases, root/parent/ancestor/state replacement, writable directories, temporary
aliases/hard links/mode/size changes, replaced temporary links, restrictive
umask, private state modes, preserved overrides, short/interrupted/failed writes,
space query/refusal, early/late flush failure and post-publication replacements.
Publication cases check outside data, existing entries, unrelated temporaries
and descriptor counts; preparation refusals also check descriptor counts.

The [real staging CLI fixture](image-integration-cli.v) runs **18 invocations**
with the literal V/C compiler substitute. It checks actual notices/actions,
launcher/registration installation, overrides, private state modes, leaf aliases,
directory alias refusals and incomplete-build diagnostics. The existing tool
fixture adds **28 compiler/output/publication regression invocations**. Structural
ELF fixtures are never executed.

The [host driver](image-integration-check.v) runs **18 checks**: CLI builds/runs,
core and ASan/UBSan builds/runs, tool/configuration/exclusive-publication
regressions, and a prior-version reproduction. It compiles the stager from
`9f86f7ea0` with the current module and demonstrates the outside license
contents/mode corruption. That reproduction concerns the old staging sequence,
rather than a complete historical binary/toolchain replay.

```sh
v -nocache -o /tmp/image-integration-check tests/packages/image-integration-check.v
V=/path/to/reviewed/v /tmp/image-integration-check "$PWD/build/new-integration-host"
```

The [native controller](image-integration-runtime-check.v) uses the production
stager and real musl cross compilers to build all three static tools. Its
[guest](image-integration-guest/main.v) repeats all 82 cases, compares installed
notices/actions against embedded source bytes, checks the exact two link targets
and empty consumer state, then executes package help/status, session usage and
Linux-runner argument admission. Required markers and clean poweroff qualify
this staging boundary. See the [hardware harness](../hardware-platform/README.md)
for QEMU TCG, firmware, kernel and cross-compiler prerequisites.

```sh
v -nocache -path '@vlib|@vmodules|tests/hardware-platform' \
  -o /tmp/image-integration-runtime tests/packages/image-integration-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  VINIX_IMAGE_INTEGRATION_STAGE="$PWD/build/new-integration-host/stage" \
  /tmp/image-integration-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-integration-arm
```

Repeat for x86_64 with its matching kernel and a fresh state directory. These
checks do not qualify graphical login/presentation, application runtime
compatibility, production publisher/catalog migration or complete image
transactions. Section 14 remains open.

## Recorded results, 2026-10-18

| Target | Result | Native guest time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 24.717 s | [receipt](results/2026-10-18/image-integration-aarch64.json), [serial](results/2026-10-18/image-integration-aarch64.serial.txt), [staging](results/2026-10-18/image-integration-aarch64.stage.txt) |
| x86_64 | PASS | 18.199 s | [receipt](results/2026-10-18/image-integration-x86_64.json), [serial](results/2026-10-18/image-integration-x86_64.serial.txt), [staging](results/2026-10-18/image-integration-x86_64.stage.txt) |

All **18 host checks passed**, including 82 core cases, 46 real CLI invocations,
ASan/UBSan and the [prior-version reproduction](results/2026-10-18/image-integration-baseline-reproduces.txt).
The [host receipt](results/2026-10-18/image-integration-host.json) records inputs,
commands, timings and artifact hashes; its [summary](results/2026-10-18/image-integration-host.txt)
lists every check. Both guests passed all 82 cases, verified actual staged
integration files/links and executed all three real tools. Each guest reported
14 denial-counter samples across two resource frames, all zero; this is not a complete
allocation-lifetime measurement. The frozen compiler is V 0.5.2 `826e96f`.
The pinned prebuilt kernels were reused; an isolated V plain-USTAR adapter served
the x86_64 kernel's legacy media contract. Production boot-media tooling and
kernel code are unchanged.

The [ledger](results/2026-10-18/image-integration-ledger.json) retains **250 local
input/artifact hashes and 17 evidence hashes**. The
[retainer](image-integration-retain.v) verifies captured source/artifact hashes,
requires both guests to use the qualified host stager, and copies receipts and
logs without editing them. Its ledger also pins the cross-compiler drivers and
documentation. Run it with the three local work directories, or use `--verify`
to recheck an existing ledger while those local artifacts remain available.

```sh
v -nocache -prod -o /tmp/image-integration-retain tests/packages/image-integration-retain.v
/tmp/image-integration-retain /build/host /build/arm /build/x86 --output /build/new-evidence
/tmp/image-integration-retain --verify /build/new-evidence/image-integration-ledger.json
```

## Validator build modes, 2026-10-23

The retainer now uses explicit errors for every admission check. The previous
documented `-prod` command compiled away its assertions, including ledger
format, hashes, guest success/failure and denial counters. The
[mode controls](image-integration-evidence-check.v) reproduce that defect with
the original retainer: its production build accepts an invalid ledger with a
wrong input digest; its normal build refuses it. Both fixed builds refuse it.

The fixed normal and production builds each accept a private validator replay
and reject **25 corruptions**. These include wrong receipts, altered artifact
digests/stager, fully resealed missing/duplicated success markers, guest failure,
panic, allocation failure, denial counters and ledger corruption. Receipt and
serial refusals happen before retained output is created. Reports bind the
validator/control sources, executables, current compiler and original receipts:
[normal](results/2026-10-23/image-integration-retainer-normal.controls.json),
[production](results/2026-10-23/image-integration-retainer-prod.controls.json).

This is a validator-only replay, **not a new historical build or guest run**.
All 32 original native artifacts remain byte-identical. Thirty-five changed
V source inputs were recovered from commit
`539b659b61296e93b974c8360b83cca2fb24bb86` with their original SHA-256 digests
and relocated into private replay receipts. The unavailable historical compiler
(`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`) is
explicitly omitted only from those separate replay receipts and recorded as
unavailable. The original receipts and ledger are unchanged; original ledger
verification still refuses the missing compiler. Production pin matching has no
fallback or omission rule.

To check fully available inputs, build the controller without `-prod` (keeping
assertions enabled in any future control code) and run it against either
retainer build. The validator itself has no assertion-dependent checks.

```sh
v -nocache -o /tmp/image-integration-evidence-check tests/packages/image-integration-evidence-check.v
/tmp/image-integration-evidence-check /tmp/image-integration-retain /build/host /build/arm /build/x86 /build/new-controls
```

For this disclosed historical replay only, append
`--replay /Users/alex/code/vinix 539b659b61296e93b974c8360b83cca2fb24bb86`.
That mode also checks original-ledger refusal and reproduces the old build-mode
defect in an isolated directory. It never changes or executes native artifacts.
