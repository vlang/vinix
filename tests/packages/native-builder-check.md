# Complete native SDK profile ownership

Complete native SDK profile calls now retire their measured V storage after
one-time JSON field metadata initialization. This closes the boundary from
source admission, ELF/notice preflight and disk budgeting through six package
imports, canonicalization, exclusive publication, private inventory retirement
and reply close. Published locks, caller arguments and source inputs survive
retirement. Other publisher profiles and complete catalog/release ownership
remain separate boundaries.

Measurement identified a repeated **506-byte / 13-allocation** leak on the host:
twelve unowned seven-byte ELF signature comparison arrays, each tracked as 38
bytes, plus the ignored macOS `TMPDIR` allocation in `os.temp_dir()`. The ELF
signature now uses a fixed stack array. Native scratch budgeting uses the same
owned temporary-directory selection as the importer, preserving platform rules.
Imported-ELF and final-retirement errors now dispose of the error being wrapped
and its message. Disk-space diagnostics explicitly retire their numeric text;
diagnostic wording and budget arithmetic remain unchanged.

The [complete-builder fixture](../../tools/packages/pkgcore/native_builder_ownership_test.v)
measures **eight attempts across 32 cases (256 calls)** under a 32-descriptor
limit. A public warm-up initializes JSON metadata outside the tracker; each
measured attempt starts with fresh output or its specified obstruction. The frame
includes the builder implementation with controlled checkpoint/space hooks and
reply/error disposal. Public warm-up and retry calls use the default options.
The callbacks free their own path/environment scratch and use native writes,
keeping fixture file-helper allocations out of the measurement. Setup, restoration and canonical retries
are outside the tracker.

Cases include complete and nested-parent builds, invalid versions, missing roots
and architectures, incorrect ELF target/mode, missing/empty/directory notices,
output/scratch-space refusal and space-query failure. Checkpoint refusal follows
zero through all six imports and the completed lock. Late ELF/notice/directory
changes, rewritten locks, existing/concurrent targets, flush failure and private
cleanup failure are covered. Replaced stage/inventory/lock directories retain
their recovery trees. Every attempt requires zero retained V bytes/allocations
and unchanged descriptor counts. Exact canonical retries preserve SHA-256
`249d6bfb150918c4586f86d68da6b6394800d150f7385c3654fadb7ab19a3fce`, source bytes and
saved locks after publication errors.

The [ELF ownership fixture](../../tools/packages/pkgcore/elf_profile_ownership_test.v)
measures **1,200 checks across 150 cases**, covering static, PIE and shared ELF
images on both targets. Each of the seven signature bytes is changed separately.
Target/type/header/count/load/memory/alignment/entry refusals, bounded interpreter
admission and refusal, ordinary files, guest aliases, directories, FIFOs and
missing files retain zero tracked storage and stable descriptor counts under
the same limit. It checks metadata structure; these images are never executed.

The [host driver](native-builder-check.v) records **39 build/test checks** with
timings, argv, input pins and log/binary hashes. Completed suites are journaled
atomically and resume only with unchanged inputs and artifacts. It includes the
production CLI, both new tracked suites, previous metadata/import/packing owners,
ELF structural tests, signed native maintenance, all five publisher profiles,
all 320 captured staging substitutions and four ASan/UBSan suites. It admits the
exact reviewed FFmpeg 8.0.1 source archive before compilation. Sanitizer leak
detection is disabled; retained V allocations use the independent tracker.

The [guest controller](native-builder-runtime-check.v) builds five programs for
each target and stages the six reviewed example manifests used by the native
lifecycle test. It requires all 32 zero-retention markers, the 1,200 ELF checks,
the preceding 1,152 metadata cycles, signed native maintenance, all 64 native
staging substitutions and three saved-output cases, followed by guest poweroff.
Each builder case keeps all eight attempts in its own process. Native staging
uses four existing sixteen-case cohorts. The guest records **36 six-second
before/after resource pairs** with a 600-second deadline. These bounded cohorts
do not establish kernel heap behavior or an unlimited fixture process lifetime.
No kernel allocation/lifetime code changes here.

```sh
v -nocache -o /tmp/native-builder-check tests/packages/native-builder-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz V=/path/to/reviewed/v \
  /tmp/native-builder-check /build/new-native-builder-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/native-builder-runtime tests/packages/native-builder-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/native-builder-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-native-builder-arm
```

Repeat for `x86_64` with its matching kernel and a new state directory. The
recorded x86_64 run uses the pinned pre-gzip kernel and the isolated V plain-USTAR
media adapter from the preceding workspace qualification. The production image
builder stays unchanged; the adapter admits only the exact pinned kernel digest.
Cross compilers, sysroot and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-18

All **39 host build/test checks passed**, including all four ASan/UBSan suites,
all five publisher profiles and all 320 captured staging substitutions:
[receipt](results/2026-10-18/native-builder-host.json),
[summary](results/2026-10-18/native-builder-host.txt).
The [builder log](results/2026-10-18/native-builder-builder-run.txt) contains all
32 zero-retention markers and exact-retry results. The
[ELF log](results/2026-10-18/native-builder-elf-owned-run.txt) confirms all 1,200
checks. Three [journal guards](results/2026-10-18/native-builder-journal-check.txt)
refuse changed input pins, damaged artifact pins and an existing fresh-run
directory before compilation; an intact completed journal resumes successfully.

The [cold native diagnostic](results/2026-10-18/native-builder-native-run.txt)
now retains **6,143 bytes / 58 allocations**, down from **6,649 / 71** in the
preceding workspace qualification. The remaining first-call JSON field metadata
is process-wide initialization. It is excluded from the repeated-call boundary;
all 256 warmed builder calls and all nine preceding metadata measurements retain
zero tracked storage. Canonical catalog bytes remain unchanged.

Both unchanged kernels passed all five program groups, all 32 builder cases,
the 1,200 ELF checks, the 1,152 preceding metadata cycles, signed native
maintenance, all 64 staging substitutions and three saved-output cases, then
powered off cleanly:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64, QEMU TCG | PASS | 586.6 s | [receipt](results/2026-10-18/native-builder-aarch64.json), [serial](results/2026-10-18/native-builder-aarch64.serial.txt) |
| x86_64, QEMU TCG | PASS | 400.2 s | [receipt](results/2026-10-18/native-builder-x86_64.json), [serial](results/2026-10-18/native-builder-x86_64.serial.txt) |

Each guest records 36 before/after resource pairs. All 504 aggregate/category
`Denied` counter samples per guest are zero. These measurements describe the
bounded qualification, without a kernel allocation-freedom or unlimited-process
claim. The [launch wrapper](results/2026-10-18/native-builder-guest-launch.v)
and [plain-USTAR adapter](results/2026-10-18/native-builder-legacy-media.v)
retain the exact local guest configuration.

The [baseline](results/2026-10-18/native-builder-baseline.txt) uses the identical
fixture before production changes at `b15f7bfdc`. Complete/nested builds retained
506 bytes / 13 allocations; partial inventories rose from 278 / 7 before any
import to 506 / 13 after all six. Imported ELF refusal retained 647 / 15; final
cleanup refusal retained 644 / 15. The
[initial probe](results/2026-10-18/native-builder-probe-before.txt) distinguishes
first-call JSON metadata from repeated retention and measures one ELF check.

The [retainer](results/2026-10-18/native-builder-retain.v) validates the
[source/compiler/artifact ledger](results/2026-10-18/native-builder-toolchain.json),
including baseline sources, both unchanged kernels, host/guest binaries, reviewed
source/example inputs and raw evidence. Roadmap section 14 remains open for
production publisher/catalog migration, other complete publisher builders,
catalog/release ownership and broader graphical/runtime/device/crash acceptance.
