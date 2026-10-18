# Offline release-image input ownership

Image configuration capture and offline repository publication retire encoding,
path, directory-creation and filesystem-query scratch on success and refusal.
The configuration encoder uses the owned publisher writer. Captured repository
indexes, signatures and objects keep their existing verification and publication
rules. Checked retirement releases metadata even when it preserves a replaced
or unsafe capture for inspection. Application reports remain independently owned;
closing plans preserves published files and exported deployment locks.

The [fixture](../../tools/packages/pkgcore/image_owner_test.v) measures **264
calls across 33 modes and both architecture declarations**, four attempts per
mode under a 32-descriptor limit. Configuration capture, two authenticated
repositories, application resolution, report/export generation, publication,
checked retirement and handled-error disposal are inside the measured frame.
JSON initialization, fixture construction/restoration and exact retries are
outside it. Controlled temporary-directory, disk-space, checkpoint and flush
callbacks execute inside tracking; retries use the same callbacks without faults.
The ordinary image suites also exercise public default options.

The two signed repositories contain aarch64 and x86_64 native application
declarations plus shared data. Explicit proprietary firmware, license and
permission policy is enforced. Structural payloads are copied and signed,
never executed. Every retry reproduces the complete newline-terminated format-2
application lock. Source edits after capture cannot alter that declaration.

Cases cover complete/check-only/existing publication, external lock export,
existing configuration, no bundle, malformed/wrong-architecture configuration,
missing/aliased/unsafe source, wrong keys, a bad second index, missing objects,
license/firmware/permission refusals, both disk budgets and query failure.
Capture/stage interruptions, changed metadata/objects, replaced capture/stage
roots, refused cleanup, saved-output flush failure, concurrent destinations,
changed image root/configuration and different existing bundles retain recovery
data and replacements. Descriptor counts stay fixed and no consumer state is
initialized. Double close remains harmless.

The [host driver](image-owner-check.v) runs **26 build/test checks**: production
CLI and image staging compilation, one tracked suite, four ASan/UBSan suites,
six ordinary suites and distribution CLI compilation/execution. This includes
80 image capture and 144 catalog substitutions, real staging preflight/refusal
CLI checks and offline lifecycle regressions. Input, command, timing and artifact
hash journals support verified resume. LeakSanitizer is disabled; the V heap
tracker measures retention separately.

The [guest controller](image-owner-runtime-check.v) runs ordinary repository,
application and configuration regressions and **ten selected modes (40 measured
frames per guest)** on aarch64 and x86_64. Each selected case runs in a fresh
process for that guest's architecture. Ten six-second before/after resource
pairs precede the cases; required markers and clean poweroff must complete
within 900 seconds.

```sh
v -nocache -o /tmp/image-owner-check tests/packages/image-owner-check.v
V=/path/to/reviewed/v /tmp/image-owner-check /build/new-image-host

v -nocache -path '@vlib|@vmodules|tests/hardware-platform' \
  -o /tmp/image-owner-runtime tests/packages/image-owner-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/image-owner-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-image-arm
```

Repeat with x86_64 and its kernel in a new directory. The baseline uses the
same fixture and original five changed implementation files at `127933e58`
in an isolated module copy; its flag skips only zero-retention assertions.
This qualifies package input preparation/publication, rather than target
compiler execution or full image construction. Cold JSON initialization,
production publisher/catalog migration, graphical sessions and real application
and runtime compatibility remain separate acceptance gates. Section 14 stays open.

## Recorded results, 2026-10-18

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 258.071 s | [receipt](results/2026-10-18/image-owner-aarch64.json), [serial](results/2026-10-18/image-owner-aarch64.serial.txt) |
| x86_64 | PASS | 299.669 s | [receipt](results/2026-10-18/image-owner-x86_64.json), [serial](results/2026-10-18/image-owner-x86_64.serial.txt) |

All **26 host build/test checks passed**, including the 264-call tracked suite,
four ASan/UBSan suites, 80 image capture and 144 catalog substitutions, real
staging preflight/refusal CLI checks and offline lifecycle regressions. The
[host receipt](results/2026-10-18/image-owner-host.json) records exact inputs,
commands, timings and artifact hashes; its
[summary](results/2026-10-18/image-owner-host.txt) lists each check. The
[CLI log](results/2026-10-18/image-owner-cli.txt) includes authenticated
enrollment, reviewed deployment, offline mirrors, rollback and uninstall after
publisher revocation.

Each guest passed ten selected complete-call modes, ordinary image repository,
application and configuration regressions and clean poweroff. All **140 denial
samples per guest** were zero. These bounded observations do not claim kernel
allocation freedom. Existing kernels are pinned. The x86_64 run uses an isolated
V plain-USTAR media adapter for its exact pre-gzip kernel; production image
tooling is unchanged. Toolchain, sysroot, firmware and Limine requirements follow
the [hardware harness](../hardware-platform/README.md).

The [baseline](results/2026-10-18/image-owner-baseline.txt) retained **106
allocations** per successful measured call (76,440 bytes at the recorded paths).
Its [fixture](results/2026-10-18/image-owner-baseline.v), five original sources
and [compile command](results/2026-10-18/image-owner-baseline-command.json)
are retained. The [journal guards](results/2026-10-18/image-owner-journal-check.txt)
reject changed inputs/artifacts and existing fresh-run directories before
compilation; an intact completed journal resumes with original timings and pins.

The [retention helper](results/2026-10-18/image-owner-retain.v) verifies the
baseline source anchor, receipts, zero-retention markers, preservation outcomes
and resource samples before saving evidence. Its
[ledger](results/2026-10-18/image-owner-toolchain.json) pins sources, compiler,
host/guest artifacts, baseline dependencies, local media adapter and reports.
Builds use `-nocache` with V 0.5.2 `826e96f`, compiler fallback disabled. The
compiler SHA-256 is
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
