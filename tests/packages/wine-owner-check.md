# Wine publisher ownership

Wine catalog construction now owns the four decoded publisher templates, partial
packed manifests, host-declaration comparison text and canonicalization state.
An idempotent plan closes both complete and refused calls. Import lists and
notice buffers have bounded capacities; preflight paths, disk-budget scratch and
the canonical lock are released on every exercised exit. PE signatures and
subsystem comparisons use scalar or fixed-array checks without temporary dynamic
comparison arrays.

`WineProfileInfo.close()` releases independent reply metadata idempotently.
Replies survive disposal of their source plans and caller paths, and published
locks survive close. The CLI closes its reply after encoding format-1 JSON.
Compatible explicit runtime updates preserve application manifests, grants,
licensing and literal argument text. This change preserves the existing Win64
and native-launcher admission rules and never selects a host Wine installation.

The [complete-call fixture](../../tools/packages/pkgcore/wine_builder_ownership_test.v)
measures **368 calls across 46 cases**, eight attempts per case under a
32-descriptor limit. Each frame includes declaration decoding/validation,
preflight, the builder with controlled checkpoint/space/flush hooks and reply/error
disposal. Public warm-up initializes process-wide JSON field metadata outside the
tracker. Fixture preparation, restoration and public default-option canonical
retries are also outside it. Callback path/environment scratch is freed; native
writes keep fixture file-helper allocations outside the measured frame.

Cases include valid/nested publication; missing/invalid/unknown declarations;
wrong architecture, pinned templates, firmware, wrong kinds, unbounded runtime,
missing selectors, implicit runtime grants and inconsistent host/runtime
declarations; missing/invalid roots, PE, native launchers, modes and notices;
both disk budgets and query failure; all four partial imports; late PE, ELF,
mode, notice and directory changes; declaration replacement after capture;
rewritten locks, occupied/concurrent destinations, flush and retirement failure;
and replaced stage/inventory/lock directories. Every case requires zero retained
tracked V bytes/allocations, stable descriptors, exact canonical retry and
preserved source, concurrent and recovery data.

The canonical synthetic catalog remains SHA-256
`90db70b6721ee1375480ecdefb080c3d51d5cb3251b419ad942fc305065d3f35`.
The [baseline](results/2026-10-18/wine-owner-baseline.txt) retained
**98,774 bytes / 289 allocations** in its recorded successful call. It uses the
[same fixture](results/2026-10-18/wine-owner-baseline.v) in an isolated module
copy with the Wine and PE implementations at `a805ea319`, unchanged dependencies
and the reviewed compiler. Its flag skips the new reply-close calls and
zero-retention assertions. Fixture paths affect the exact retained byte count.

The [metadata fixture](../../tools/packages/pkgcore/wine_profile_ownership_test.v)
measures **896 cycles** across zero through four imports and duplicate/empty
catalog refusals. Each cycle captures and owns all four decoded declarations.
Canonical text and independently closeable replies survive plan retirement;
repeated plan/reply close is safe. First-call JSON metadata is excluded. This is
not an allocation-freedom claim for arbitrary profiles, fixture setup or unlimited
fixture process lifetimes.

The [host driver](wine-owner-check.v) runs **63 build/test checks**, retaining
input/compiler pins, argv, timings and log/binary hashes. It includes the rebuilt
production CLI, both new owners, the native/SQLite/FFmpeg/ELF/import/packing
regressions, all five publisher profiles, all 320 captured staging substitutions
and ten ASan/UBSan suites. Wine CLI checks include format-1 reply decoding, paths
with spaces, compatible runtime updates, unchanged application manifests and
exact refusal preservation. Sanitizer leak detection is disabled; tracked V
storage uses the independent tracker. Completed suites are journaled atomically
and resume only after input/artifact verification. The broader FFmpeg regression
requires its full reviewed source archive before compilation.

The [guest controller](wine-owner-runtime-check.v) runs all metadata cycles and
ordinary Wine profile regressions on each architecture. Its complete-call
coverage is a **twelve-case subset (96 measured frames per guest)**: success,
invalid schema, inconsistent hosts, invalid PE, wrong native launcher target,
second/fourth partial imports, late PE/ELF mutation, replaced declarations, flush
and cleanup failure. Each case runs in its own process with eight attempts and
exact retry. Twelve six-second before/after resource pairs precede these cases.
The recorded scenario has a 900-second deadline and requires every marker and
clean poweroff. It does not claim guest coverage of all 46 host cases or all 320
staging substitutions. Resource samples do not establish kernel allocation
freedom; no kernel code or lifetimes change here.

```sh
v -nocache -o /tmp/wine-owner-check tests/packages/wine-owner-check.v
VINIX_PROFILE_EXPORT_SOURCE=/reviewed/ffmpeg-8.0.1.tar.xz V=/path/to/reviewed/v \
  /tmp/wine-owner-check /build/new-wine-owner-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/wine-owner-runtime tests/packages/wine-owner-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/wine-owner-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-wine-owner-arm
```

Repeat for `x86_64` with a matching kernel and new state directory. The recorded
x86_64 run uses an isolated V plain-USTAR media adapter for its exact pinned
pre-gzip kernel. Production image tooling stays unchanged. Target toolchains,
sysroots, firmware and Limine follow the
[hardware controller requirements](../hardware-platform/README.md).

## Recorded results, 2026-10-18

Both second-attempt guest scenarios passed within the 900-second deadline:

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| AArch64 | PASS | 168.326 s | [receipt](results/2026-10-18/wine-owner-aarch64.json), [serial](results/2026-10-18/wine-owner-aarch64.serial.txt) |
| x86_64 | PASS | 149.350 s | [receipt](results/2026-10-18/wine-owner-x86_64.json), [serial](results/2026-10-18/wine-owner-x86_64.serial.txt) |

Each guest has seven zero-retention metadata measurements and twelve
zero-retention complete-call measurements, exact canonical retries and clean
poweroff. All 168 denial samples per guest are zero across the twelve resource
pairs. These bounded samples are not a kernel allocation-freedom claim.

All **63 host build/test checks passed**, including the ten ASan/UBSan suites,
both tracked Wine owners, all five profiles and all 320 staging substitutions.
The [host receipt](results/2026-10-18/wine-owner-host.json) retains exact argv,
timings and input/artifact hashes; the [summary](results/2026-10-18/wine-owner-host.txt)
lists every named check and its duration. The
[production CLI log](results/2026-10-18/wine-owner-cli.txt) includes the runtime
update and reply compatibility assertions. The
[journal guards](results/2026-10-18/wine-owner-journal-check.txt) reject changed
source pins, damaged artifact pins and existing fresh-run directories before
compilation. An intact completed journal resumes with its original timings and
artifact pins.

The [retention helper](results/2026-10-18/wine-owner-retain.v) verifies both
baseline source files against `a805ea319`, checks receipts and copies the evidence.
Its [ledger](results/2026-10-18/wine-owner-toolchain.json) pins sources, compiler,
baseline dependencies, host/guest artifacts, local media adapter and retained
reports. Builds use `-nocache` with the frozen V 0.5.2 `826e96f` compiler and
disable compiler fallback. The compiler SHA-256 is
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.

The initial [AArch64](results/2026-10-18/wine-owner-aarch64.failed-1.txt) and
[x86_64](results/2026-10-18/wine-owner-x86_64.failed-1.txt) guest builds stopped
before boot because the frozen toolchain's `os.exec` cross-link referenced
`v_os_exec_capture_start` without a definition. The Wine test command helper now
uses argument arrays through `os.new_process`, retaining output and exit-code
checks. The [first host run](results/2026-10-18/wine-owner-interrupted-host-1.txt)
was stopped when this fixture changed; its
[input pins](results/2026-10-18/wine-owner-interrupted-host-1.json) and
[original fixture](results/2026-10-18/wine-owner-before-portable-profile.v) are
retained. Qualification restarted in fresh host/guest state with the updated
fixture, without resuming old pins. Neither initial guest build is a runtime
qualification result.

All PE/ELF payloads are synthetic structural fixtures and are never executed.
The [Wine lifecycle qualification](wine-profile-check.md) covers signed offline
maintenance, explicit proprietary license policy, launcher/MIME registration,
removal and rollback. These ownership checks do not qualify a real Wine or
translation closure, redistribution rights, Authenticode, APIs, IPC/devices,
ordinary-user graphical execution or production catalog migration. Other
complete profile/catalog/release owners remain separate; section 14 stays open.
