# FFmpeg publisher ownership

FFmpeg catalog construction now owns its templates, partial packed manifests,
canonicalization text/decoded catalogs, source/ELF preflight and filesystem
budget scratch. Template buffers have their complete capacities up front;
argument and selector strings are retired with the plan. Imported ELF errors
dispose of the wrapped error and its message. Failed imports and failed
publication retire partial state while preserving recovery trees and saved locks.

`FfmpegProfileInfo.close()` releases independent reply metadata idempotently.
Published locks and caller inputs survive. The CLI closes its reply after
encoding, preserving the format-1 JSON contract. A compatible runtime update
retains both application manifests. The source digest, notices, permissions,
licensing disclosures and compatibility bounds are unchanged.

The [complete-call fixture](../../tools/packages/pkgcore/ffmpeg_builder_ownership_test.v)
measures **76 calls across 38 cases**, two attempts per case under a
32-descriptor limit. Each frame includes the builder implementation with
controlled checkpoint/space/flush hooks and reply/error disposal. The public
warm-up initializes JSON field metadata outside the tracker; preparation,
restoration and public default-option canonical retries are also outside it.
Callback path/environment scratch is freed; native writes keep fixture helper
allocations outside the measured frame.

Cases cover valid/nested publication; version/range/root/architecture/ELF/mode
and notice refusals; missing, wrong-size, executable and same-size unpinned
source archives; source mutation after preflight; both disk-space refusals and
query failure; all six partial imports; late imported ELF/notice/directory
changes; changed locks and occupied/concurrent destinations; flush/private
retirement failure; and replacement of the stage, inventory or lock directory.
Each case requires zero retained tracked V bytes/allocations, stable descriptor
counts, exact canonical retry and preserved source/competitor/recovery data.

The synthetic catalog remains SHA-256
`3e143c0de9b7304576820a7dd70ad5949b23525211ca30a40a6791e8ccfc6431`.
The [baseline](results/2026-10-18/ffmpeg-owner-baseline.txt) retained
**192,344 bytes / 649 allocations** in its recorded successful call. It uses the
[same fixture](results/2026-10-18/ffmpeg-owner-baseline.v) in an isolated module
copy with the original FFmpeg implementation at `138c08d1e`, unchanged dependencies
and the reviewed compiler. The baseline flag skips the new reply close operation
and zero-retention assertions. Fixture paths affect the exact retained byte count.

The [metadata fixture](../../tools/packages/pkgcore/ffmpeg_profile_ownership_test.v)
measures **1,152 cycles** across zero through six imports and duplicate/empty
catalog refusals. It checks runtime version 1.1.0, borrowed caller arguments,
canonical text after plan retirement and independent replies after caller
argument retirement. Repeated plan/reply close is safe. First-call process-wide
JSON metadata is excluded; this is not an allocation-freedom claim for arbitrary
profiles, fixture setup or unlimited fixture process lifetimes.

The [host driver](ffmpeg-owner-check.v) runs **55 build/test checks** with pinned
inputs, compiler, argv, timings and log/binary hashes. It includes the production
CLI, both new owners, native/SQLite/ELF/import/packing owners, all five publisher
profiles, all 320 captured staging substitutions and eight ASan/UBSan suites.
Completed suites are journaled atomically and may resume only after verifying
input/artifact pins. Sanitizer leak detection is disabled; tracked V storage
uses the independent tracker.

The [guest controller](ffmpeg-owner-runtime-check.v) runs the complete metadata
fixture and ordinary FFmpeg profile regressions on each target. Its complete-call
coverage is an explicit **eight-case subset (16 measured frames)**: success,
third/sixth partial imports, late ELF/source changes, rewritten lock, flush and
cleanup failure. Every case runs in a fresh process with both attempts and exact
retry. Eight six-second before/after resource pairs precede these cases. The
scenario requires all markers and clean poweroff within 900 seconds. It does not
claim guest coverage of the full 38-case host matrix or all 320 staging changes.

Every complete fixture uses the **full 11,388,848-byte reviewed FFmpeg archive**,
SHA-256 `05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41`.
The archive is checked before host compilation or guest state creation, staged
as nonexecutable data and rechecked inside each guest fixture. ELF headers and
notice/build text in these roots are synthetic; they are never executed.
No kernel code or lifetime changes here.

```sh
v -nocache -o /tmp/ffmpeg-owner-check tests/packages/ffmpeg-owner-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz V=/path/to/reviewed/v \
  /tmp/ffmpeg-owner-check /build/new-ffmpeg-owner-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/ffmpeg-owner-runtime tests/packages/ffmpeg-owner-runtime-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz \
  VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/ffmpeg-owner-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-ffmpeg-owner-arm
```

Repeat for `x86_64` with its matching kernel and a new state directory. The
recorded x86_64 run uses the exact pinned pre-gzip kernel and an isolated V
plain-USTAR media adapter. Production image tooling stays unchanged. Target
compilers, sysroots, firmware and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-18

Both guest scenarios passed on their first recorded attempt with the 900-second
deadline:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64 | PASS | 398.764 s | [receipt](results/2026-10-18/ffmpeg-owner-aarch64.json), [serial](results/2026-10-18/ffmpeg-owner-aarch64.serial.txt) |
| x86_64 | PASS | 641.338 s | [receipt](results/2026-10-18/ffmpeg-owner-x86_64.json), [serial](results/2026-10-18/ffmpeg-owner-x86_64.serial.txt) |

Each guest has nine zero-retention metadata measurements and eight zero-retention
complete-call measurements, exact canonical retries and clean poweroff. All 112
denial samples per guest are zero across the eight resource pairs. These bounded
samples are not a kernel allocation-freedom claim.

The rebuilt [production CLI check](results/2026-10-18/ffmpeg-owner-cli.txt) passed
format-1 reply decoding, paths with spaces, compatible runtime-only updates and
exact saved-lock preservation after occupied/version/range refusals.

All **55 host build/test checks passed**, including the eight ASan/UBSan suites,
both tracked FFmpeg owners, all five profiles and all 320 staging substitutions.
The [host receipt](results/2026-10-18/ffmpeg-owner-host.json) retains exact argv,
timings and input/artifact hashes; the [summary](results/2026-10-18/ffmpeg-owner-host.txt)
lists each named check and its duration. The
[journal guards](results/2026-10-18/ffmpeg-owner-journal-check.txt) reject changed
source pins, damaged artifact pins and existing fresh-run directories before
compilation. An intact completed journal resumes with its original timings and
artifact pins.

The [retention helper](results/2026-10-18/ffmpeg-owner-retain.v) verifies the
baseline against `138c08d1e`, checks receipts and copies the evidence. Its
[ledger](results/2026-10-18/ffmpeg-owner-toolchain.json) pins sources, compiler,
baseline dependencies, host/guest artifacts, local media adapter and retained
reports. All builds use `-nocache` with the frozen V 0.5.2 `826e96f` compiler;
host helper builds disable compiler fallback. The compiler SHA-256 is
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.

These checks cover publisher ownership. Real upstream media encoding/decoding,
terminal launches, signed maintenance, isolation, rollback and cached reinstall
remain covered by the separate [FFmpeg lifecycle qualification](ffmpeg-profile-check.md).
Other complete profile/catalog/release ownership, production publisher/catalog
migration and broader graphical/runtime/device/crash acceptance remain open.
