# Apple publisher ownership

Apple catalog construction owns its two captured declarations, partial packed
manifests, canonicalization state, temporary paths and disk-budget scratch.
The plan closes complete and refused calls idempotently. Packed manifests own
their payload metadata; wrappers borrow selectors until the plan is retired.
Notice buffers borrow declaration paths without implicit append copies.

`AppleProfileInfo.close()` releases independent reply metadata idempotently.
Replies survive source-plan and caller-path disposal; closing them preserves the
published lock. The production CLI closes its reply after format-1 JSON encoding.
CLI regressions cover literal paths with spaces, compatible runtime updates,
unchanged application manifests, architecture and refusal preservation.

The plist parser now retires recursive reader headers, initial binary-reader
maps, scalar text buffers and XML entity/digit scratch on success and refusal.
Mach-O command admission uses a fixed comparison array. Existing format, bounds,
identity, platform, encryption, mapping and runtime-license rules are preserved.

The [complete-call fixture](../../tools/packages/pkgcore/apple_builder_ownership_test.v)
measures **384 calls across 48 cases**, eight attempts each under a 32-descriptor
limit. Frames include declaration decoding/validation, payload preflight, builder
execution with controlled checkpoint/space/flush hooks and reply/error disposal.
Public warm-up initializes process-wide JSON metadata outside tracking. Fixture
preparation/restoration and default-option canonical retries also stay outside.
Fault callbacks free path/environment scratch and use native file writes.

Cases cover normal/nested publication, missing/invalid declarations, architecture,
pinned templates, firmware, kinds, runtime bounds/identity/grants, missing
selectors, malformed argument paths, missing roots, Mach-O/plist/native launcher
admission, notices and modes, both disk budgets and query failure, both partial
imports, late payload/plist/notice/mode/directory changes, captured declarations,
changed locks, occupied/concurrent destinations, directory flush/cleanup failure
and replaced stage/inventory/lock directories. Every case requires zero retained
tracked V bytes/allocations, stable descriptors, exact canonical retry and
preserved source, concurrent and recovery data.

The unchanged synthetic catalog SHA-256 is
`86bec8ad8127402ffbd4fe94c1b845902e4b3c2785a2bcdc36237aa2c9ac435d`.
The retained baseline runs the same complete-call fixture against the original
Apple publisher, header admission and plist parser in an isolated module copy.
Its compile flag skips new reply-close calls and zero-retention assertions.
The baseline source anchor is `d7dbda441`; the exact retained byte count depends
on fixture paths. Sources, compiler, commands and artifact hashes are retained.

The [metadata fixture](../../tools/packages/pkgcore/apple_profile_ownership_test.v)
measures **640 cycles** across zero through two packed manifests and duplicate/
empty canonicalization refusals. Both decoded declarations are owned in every
cycle. Canonical text and two independent replies survive plan/caller retirement;
repeated close is safe. The
[admission fixture](../../tools/packages/pkgcore/apple_admission_ownership_test.v)
measures **1,920 cycles across 15 selections** covering XML and binary plists,
entities, extra nested/scalar fields, partial trees, duplicate/malformed fields,
identity mismatches, trailing data and valid/refused Mach-O command areas.

The [host driver](apple-owner-check.v) runs **41 build/test checks**: production
CLI compilation, four tracked suites, four ASan/UBSan suites and twelve ordinary
suites. These include all five profiles, all 320 captured-stage substitutions,
Apple headers/private launch context, shared ELF/import/packing checks and the
existing plist regression suite. LeakSanitizer is disabled; V storage is measured
with the independent tracker. Input pins, argv, timings and log/binary hashes
are journaled; resume verifies inputs and completed artifacts.
Shared FFmpeg staging regressions require the complete reviewed 8.0.1 source
archive; the driver checks its size/hash before compilation and pins it.

The [guest controller](apple-owner-runtime-check.v) runs all metadata and
admission cycles plus ordinary Apple profile regressions on each architecture.
Complete-call guest coverage is a **twelve-case subset (96 measured frames per
guest)**: success, invalid schema, invalid Mach-O, wrong plist identity, both
partial imports, late Mach-O/plist changes, captured declarations, directory flush,
cleanup failure and replaced stage root. Each runs in its own process. Twelve
six-second before/after kernel-resource pairs precede these cases. The scenario
requires every marker and clean poweroff within 900 seconds. It does not claim
all 48 cases on guests or kernel allocation freedom; no kernel code changes.

```sh
v -nocache -o /tmp/apple-owner-check tests/packages/apple-owner-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz V=/path/to/reviewed/v \
  /tmp/apple-owner-check /build/new-apple-owner-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/apple-owner-runtime tests/packages/apple-owner-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/apple-owner-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-apple-owner-arm
```

Repeat for `x86_64` with a matching kernel and new state directory. Running this
publisher on x86_64 still produces only an AArch64 lock. Fixtures are structural
Mach-O/ELF files and are never executed. Real native Mach-O instruction and
container/keychain execution has its separate
[Apple runtime qualification](apple-runtime-check.md). These ownership checks do
not qualify wider Apple APIs, entitlements, redistribution rights, graphical
sessions, translation or production catalog migration. Section 14 stays open.

## Recorded results, 2026-10-18

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 215.574 s | [receipt](results/2026-10-18/apple-owner-aarch64.json), [serial](results/2026-10-18/apple-owner-aarch64.serial.txt) |
| x86_64 | PASS | 228.077 s | [receipt](results/2026-10-18/apple-owner-x86_64.json), [serial](results/2026-10-18/apple-owner-x86_64.serial.txt) |

All **41 host build/test checks passed**, including four ASan/UBSan suites,
all five publisher profiles and all 320 captured staging substitutions. The
[host receipt](results/2026-10-18/apple-owner-host.json) retains exact inputs,
argv, timings and artifact hashes; its
[summary](results/2026-10-18/apple-owner-host.txt) lists every check. The
[CLI log](results/2026-10-18/apple-owner-cli.txt) includes compatible runtime
updates and reply-close preservation.

Each guest passed all 640 metadata and 1,920 admission cycles, twelve selected
complete-call cases, exact canonical retries and clean poweroff. All 168 denial
samples per guest were zero. These are bounded resource observations, not a
kernel allocation-freedom claim. Both runs use pinned existing kernels. The
x86_64 run uses an isolated V plain-USTAR media adapter for its exact pre-gzip
kernel; production image tooling is unchanged. Toolchain, sysroot, firmware and
Limine requirements follow the [hardware harness](../hardware-platform/README.md).

The [baseline](results/2026-10-18/apple-owner-baseline.txt) retained **55,359 bytes
/ 214 allocations** per successful measured call. Its
[fixture](results/2026-10-18/apple-owner-baseline.v), original sources and
[compile command](results/2026-10-18/apple-owner-baseline-command.json) are retained.
The [journal guards](results/2026-10-18/apple-owner-journal-check.txt) reject
changed input/artifact pins and existing fresh-run directories before compiling;
an intact completed journal resumes with original timings and artifacts.

The [retention helper](results/2026-10-18/apple-owner-retain.v) verifies the
baseline source anchor, all receipts, zero-retention markers, recovery outcomes
and resource samples before saving evidence. Its
[ledger](results/2026-10-18/apple-owner-toolchain.json) pins sources, compiler,
host/guest artifacts, baseline dependencies, local media adapter and reports.
Builds use `-nocache` with V 0.5.2 `826e96f`, compiler fallback disabled. The
compiler SHA-256 is
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.

The [first host attempt](results/2026-10-18/apple-owner-failed-host-1.txt)
stopped in shared FFmpeg staging regressions because the driver omitted their
required full source archive. Its [input pins](results/2026-10-18/apple-owner-failed-host-1-inputs.json)
and [original driver](results/2026-10-18/apple-owner-before-archive-driver.v)
are retained. The corrected driver validates and pins the reviewed archive
before compilation; all 41 checks passed in a fresh second host directory.
The two guest runs use the unchanged implementation and fixtures and passed on
their first attempts.
