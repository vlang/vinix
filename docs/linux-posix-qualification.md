# Linux/POSIX qualification, 2026-10-11

Section 15 remains partial. These are results for exact hashed binaries in
disposable QEMU guests, plus explicitly separate host checks. They do not
qualify every wired syscall, unmodified glibc, persistent package installation,
desktop integration or physical hardware.

The kernels were built in isolated worktrees from `ea6c4189` with the three
Linux ABI fixes (`df484021`, `87611ce2`, `d9aee93e`). Concurrent changes in the
shared checkout were excluded from those builds. Kernel, fixture source,
init and image hashes are in the checked-in receipts under
[`tests/linux-compat/results/2026-10-11`](../tests/linux-compat/results/2026-10-11).
Use the [V qualification controllers](../tests/linux-compat/README.md) to
reproduce tests against another kernel; a new hash needs a new qualification.

| Check | Native AArch64 | Native x86-64 | x86-64 translated on AArch64 | i386 translated on AArch64 |
| --- | --- | --- | --- | --- |
| BPF load/attach/detach/query returns ENOSYS without changing user buffers | passed | passed | not tested | not tested |
| faccessat2 permissions, exact errors, empty/deleted/O_PATH paths and credentials | passed | passed | not tested | not tested |
| openat2 ordinary opens and exact validation/rejection of unsupported resolution | passed | passed | not tested | not tested |
| Concurrent pthread TLS/errno/keys, 64-bit atomics, SIMD and RW-to-RX JIT | passed | passed | passed | passed |
| auxv/sysconf page size, pointer width | 16 KiB, 64 bits | 4 KiB, 64 bits | 4 KiB, 64 bits | 4 KiB, 32 bits |

BPF is unavailable: passing its error regression means callers can discover
that limitation. Known openat2 RESOLVE constraints return EOPNOTSUPP; atomic
constrained traversal is still missing. Neither result is a sandbox support
claim. The runtime fixture covers NEON or SSE2, not the complete AVX/ARM feature
set, debugger operations, signal delivery through translation or every JIT.
The x86-64 translated result uses the existing QEMU-user launcher in `--direct` mode
with a static musl x86-64 fixture, not a glibc application runtime.

An initial i386 attempt failed before linking because V's amd64 inline assembly
could not target i386. The revised fixture uses SSE2 compiler intrinsics; it
passes natively on both architectures and as a static i386 executable through
the existing ARM-native QEMU-i386 translator. Separate native runtime receipts
record the revision. The i386 SDK's musl 1.2.5-r11, compiler-rt 19.1.4-r1, CRT
and builtins hashes are recorded with the build and package inputs. The static
probe bypasses the wrapper's dynamic musl loader and confines its W^X opt-in to
the translator child. Native ELF32 entry, x32, unmodified glibc, 32-bit large-file
and time APIs, loader interoperability and debugger operations remain unqualified.

The application suite also attempts all categories and preserves missing
dependencies as unsupported, with a nonzero complete-suite exit. Test roots
contain real Alpine 3.21 SQLite 3.48.0-r4 and BusyBox Extras 1.37.0-r14 payloads;
their package URLs and SHA-256 hashes are retained. They were extracted for
testing, with shared-library soname links materialized as the current Vinix
musl loader expects. Package scripts, signatures, update/remove transactions
and a persistent installed desktop were not qualified by extraction.

| Application workload | Native AArch64 | Native x86-64 |
| --- | --- | --- |
| SQLite WAL transaction, sum verification, integrity check and reopen | passed | passed |
| BusyBox Extras HTTP response content and process-group retirement | passed | passed |
| Runtime fixture invoked and its captured predicates verified | passed | passed |
| FFmpeg, Gnumeric, Chromium, Firefox, Go, Java, V, portal and games | unsupported | unsupported |

Each native catalog receipt has three passing workloads and nine unsupported
results, with no failed workload predicates in the final runs. The controller
and complete suite return failure because unsupported dependencies are not
success. The HTTP child is killed/reaped after the verified response; its
recorded nonzero termination is expected cleanup, not a service run failure.

The host SQLite WAL/integrity/reopen and FFmpeg frame encode/probe checks pass.
Those Darwin results validate workload predicates and report handling only.
They are not Vinix application results. Host tests also verify that a missing
executable, a nonzero command and an actual timeout cannot produce success.

Outstanding dependencies include the browser/office/media and Go/Java/V
packages in the prepared guest roots, D-Bus and a real portal backend,
systemd/service-unit integration, Flatpak/Snap/FUSE and enforced Linux sandbox
interfaces, and title-specific game assets, GPU/audio/input and vendor APIs.
The [behavior matrix](linux-posix-compatibility.md) lists the broader limits.
Every application report keeps `complete_lifecycle_qualified` false until its
advertised install/run/save/update/desktop workflow has been exercised.
