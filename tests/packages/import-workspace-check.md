# Captured private import workspace ownership

Prepared-root imports now own their temporary parent, private root, payload
directory and manifest descriptor. Creation captures each identity before
admitting it for cleanup. Checks cover ownership, permissions, directory names,
manifest identity, length and digest. The manifest is written exclusively.
Retirement inventories the tree through captured descriptors and never follows
leaf aliases, opens special files or changes external hard-link targets.
All descriptors and owned strings close on success and refusal; `close` is
idempotent. The temporary directory retains the platform's existing selection
rules, including `/tmp` on macOS and `TMPDIR` on the guest.

Replacing the root, payload or manifest, rewriting the manifest or adding an
unadmitted root entry refuses cleanup and preserves recovery data. Diagnostics
include the retained path. A moved parent cannot redirect retirement into its
replacement. If packing already published a package, later check/cleanup errors
explicitly report that publication and leave its objects and manifest intact.
Failed child capture closes the captured root/parent and retires memory while
retaining the unadmitted filesystem tree for inspection.

Each root enumeration opens a fresh directory description. The adversarial
fixture caught a development bug where `dup` shared an exhausted directory cursor
with the preceding check, allowing a later cleanup check to miss unexpected
entries. The corrected check and its failure cleanup both refuse that case.

The [complete-import fixture](../../tools/packages/pkgcore/import_workspace_ownership_test.v)
runs **16 attempts for each of eight cases (128 calls)** with a 32-descriptor
limit. One public import initializes JSON field metadata outside measurement;
each measured call starts with a freshly removed/obstructed publisher output.
The measured frame includes private workspace creation, source copying, manifest
writing, packing, retirement and reply close. Success covers public recipe decode
and pinned descriptor imports. Refusals cover early file/directory checks, late
copy failure, an ordinary publisher-path file and object/manifest directories.
All calls require zero retained V bytes/allocations and unchanged descriptor
counts. Corrected retries must reproduce the exact canonical manifest and source
contents. Caller-owned source/pin fixtures remain outside the measured frame.

The [capture fixture](../../tools/packages/pkgcore/import_workspace_capture_test.v)
measures **14 admission/check/retirement frames**, with fixture construction
outside the tracker. Thirteen cover ordinary cleanup, replaced roots, payloads
and manifests, unsafe root mode, aliases, a FIFO, same-size manifest rewrite,
unexpected root entries and a renamed parent. A fourteenth forces payload capture
failure under descriptor exhaustion and verifies complete descriptor/storage
retirement and a diagnostic naming the retained tree. The retirement tree grows
both collections with 32 sibling directories and a 40-level chain; aliases,
external hard links and a FIFO remain safe. All 14 frames retain zero tracked V
bytes/allocations. Separately, **16 public substitutions** exercise four workspace
checkpoints and verify source preservation, publication timing, retained recovery
data and canonical retries. These functional fixture setups are not allocation
freedom measurements.

The [host driver](import-workspace-check.v) records check durations, argv,
log/binary hashes and compiler/source pins. Completed suites save their build/run
receipts atomically; an interrupted suite reruns before recording a result.
It can resume only with identical inputs and intact completed artifacts. Its **27 build/test checks**
include the production CLI, tracked workspace/capture/native-profile suites,
both new fixtures under ASan/UBSan, source consistency, traversal bounds, owned
pack/CLI replies and native, SQLite, FFmpeg, Wine and Apple publisher profiles.
Sanitizer leak detection is disabled; the independent V tracker measures retention.
The [journal guards](results/2026-10-18/import-workspace-journal-check.txt)
also verify refusal before compilation for changed source pins, damaged completed
artifact pins and an existing fresh-run directory. An intact completed journal
resumes with its original timings and artifacts.

The [guest controller](import-workspace-runtime-check.v) cross-compiles six
programs per architecture and requires every measured marker, all 16 public
substitutions, existing source/traversal/pack/native-profile checks and poweroff.
Each complete-import case uses its own process and retains all 16 attempts.
Each capture case and the public group also run in separate processes. The guest
records **23 six-second before/after cleanup intervals** under the unchanged
kernel's removed-node grace period, with a 600-second scenario deadline.
These bounded processes do not establish kernel allocation freedom or an
unlimited fixture lifetime. No kernel allocation or lifetime code changes here.
The controller also stages and hashes the six repository example manifests
needed by the native-profile regression at its canonical compile-time source path.

```sh
v -nocache -o /tmp/import-workspace-check tests/packages/import-workspace-check.v
V=/path/to/reviewed/v /tmp/import-workspace-check /build/new-workspace-host
# After interruption, with identical sources/compiler:
V=/path/to/reviewed/v /tmp/import-workspace-check --resume /build/new-workspace-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/import-workspace-runtime tests/packages/import-workspace-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/import-workspace-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-workspace-arm
```

Repeat with `x86_64`, its kernel and a new state directory. Cross compilers,
sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-18

All **27 host checks passed**, including both ASan/UBSan suites:
[receipt](results/2026-10-18/import-workspace-host.json),
[summary](results/2026-10-18/import-workspace-host.txt).
The [complete-import log](results/2026-10-18/import-workspace-workspace-run.txt)
and [capture log](results/2026-10-18/import-workspace-capture-run.txt) contain all
zero-retention markers and preservation/retry results.

The [preceding implementation](results/2026-10-18/import-workspace-baseline-import.v)
at `2b59aba66` retained the following per-call maxima under the same
[eight-case fixture](results/2026-10-18/import-workspace-baseline.v), compiler,
manual-free flags and 32-descriptor limit:

| Case | Retained bytes | Allocations | Current |
| --- | ---: | ---: | --- |
| Complete / pinned | 12,207 | 96 | 0 / 0 |
| Opened / directory refusal | 1,379 | 4 | 0 / 0 |
| Late copied refusal | 10,325 | 86 | 0 / 0 |
| Publisher / object / manifest refusal | 12,207 | 96 | 0 / 0 |

See the [raw baseline](results/2026-10-18/import-workspace-baseline.txt).
The complete native-profile diagnostic now retains **6,649 bytes / 71
allocations**, down from the preceding **52,087 / 323**. Its nine metadata-only
measurements remain zero and canonical catalog bytes remain unchanged:
[current diagnostic](results/2026-10-18/import-workspace-native-run.txt),
[preceding diagnostic](results/2026-10-17/import-materialization-ownership-native.txt).
Complete profile construction remains an open ownership boundary.

Both unchanged kernels passed all six program groups, all eight complete-import
cases, all 14 captured admission/retirement cases, the 16 public substitutions
and guest poweroff:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64, QEMU TCG | PASS | 389.1 s | [receipt](results/2026-10-18/import-workspace-aarch64.json), [serial](results/2026-10-18/import-workspace-aarch64.serial.txt) |
| x86_64, QEMU TCG | PASS | 243.2 s | [receipt](results/2026-10-18/import-workspace-x86_64.json), [serial](results/2026-10-18/import-workspace-x86_64.serial.txt) |

Each guest records 23 before/after resource pairs. All 322 aggregate/category
`Denied` counter samples per guest are zero. These describe the bounded
qualification; they do not establish kernel heap behavior or an unlimited
process lifetime.

The initial x86_64 boot failed before the guest started: the production ISO builder
now emits gzip initramfs, while this pinned kernel predates decompression support.
The corrected run uses an isolated [V media adapter](results/2026-10-18/import-workspace-legacy-media.v)
that admits only the exact pinned kernel digest and boots the unchanged plain
USTAR archive with the previously used Limine files. The
[launch wrapper](results/2026-10-18/import-workspace-guest-launch.v) places that
adapter in an isolated `VINIX_ROOT`; the production image builder stays unchanged.
The initial AArch64 run passed the source, depth and pack regressions, then
refused because the native-profile fixture's example manifests were absent.
The controller now stages those six files using the canonical source path.
Intermediate rebuilds were interrupted to finish that correction before boot.
The [x86_64 boot failure](results/2026-10-18/import-workspace-x86_64-initial-failure.txt)
and [AArch64 fixture failure](results/2026-10-18/import-workspace-aarch64-initial-failure.txt)
remain separate from the successful receipts, with their raw image, serial and
QMP logs. Setup interruptions are also retained.

The [retainer](results/2026-10-18/import-workspace-retain.v) verifies the
[compiler/source/artifact ledger](results/2026-10-18/import-workspace-toolchain.json),
including the unchanged kernels, guest programs, host binaries and raw evidence.
This boundary does not qualify production publisher enrollment/catalog migration,
full profile/catalog/release ownership, graphical login/presentation, real
compatibility-runtime execution or broader device/crash acceptance. Roadmap
section 14 remains open.
