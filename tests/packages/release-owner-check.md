# Signed release publisher ownership

Release publication retires decoded manifest trees, temporary canonical package
buffers, signing input/signature/public-key buffers, verified indexes, deduplication
maps, seed/path scratch and staged copy paths on success and refusal. Partial
decoded manifests move into one owner before payload checks. Canonicalization
borrows field strings and retires only its four sorted collection buffers.
Index encoding uses the existing owned publisher writer, preserving signed bytes.

`ReleaseInfo.close()` releases independently owned repository, key, digest and
directory strings idempotently. Replies survive caller-path/ID disposal; closing
them preserves the signed release, private seed and reserved sequence floor.
The CLI closes its reply after encoding the unchanged format-1 JSON object.
Legacy `publish` also retires its publication tuple and output-path scratch.

The [complete-call fixture](../../tools/packages/pkgcore/release_builder_ownership_test.v)
measures **304 calls across 38 cases**, eight attempts each under a 32-descriptor
limit. Workspace admission and publisher locking are inside each frame, followed
by seed capture, manifest/payload admission, signing, consumer validation, history
checks, dependency closure, disk budgeting, staged export and reply/error disposal.
Controlled checkpoint/space hooks execute inside tracking; fixture restoration,
public JSON warm-up and default-option exact retries stay outside it.

The fixture declares both host applications and shared explicitly licensed
firmware. Three structural payloads are copied and signed, never executed.
A fixed seed and expiry produce index SHA-256
`1cfdd899be97f03a74ec4d2176acf68e2b4e2d8ef541a440bcc82a38272dc112`.
Every retry must reproduce both exact index bytes and the detached signature.

Cases cover normal/nested and legacy in-place publication, invalid/private/
missing/NUL/aliased seeds, invalid ID/sequence/expiry, malformed/duplicate
manifests, absent/changed payloads, malformed/rollback/equivocating histories,
unresolved dependencies and accidentally packaged signing material. Disk-space
and query refusals, all five checkpoints, copied/staged/reserved metadata changes,
extra staged entries, history-write failure, concurrent destinations and replaced
stage roots preserve the seed, sources, reservations and recovery data.
Captured-seed replacement continues using the original admitted bytes.
Legacy in-place publication retains its existing sequence-history behavior.

The [canonical index fixture](../../tools/packages/pkgcore/canonical_index_ownership_test.v)
measures **448 cycles** with zero, one and 64 packages, complete encoding and
early/partial refusal. It checks that caller ordering and borrowed fields survive.

The [host driver](release-owner-check.v) runs **27 build/test checks**: production
CLI compilation, two tracked suites, four ASan/UBSan suites, six ordinary suites
and the distribution CLI regression. This includes 64 release and 144 catalog
stage substitutions, seed admission/capture, signed-index schemas, signature
checks and signed offline install/remove. Inputs, commands, timings and log/binary
hashes are journaled; resume verifies them. LeakSanitizer is disabled; tracked V
retention is measured independently.

The [guest controller](release-owner-runtime-check.v) runs all 448 tracked
canonical cycles, ordinary release/seed regressions and **twelve selected cases
(96 complete-call frames per guest)** on aarch64 and x86_64. Selected cases cover
complete/in-place publication, invalid/captured seeds, unresolved closure, seed
payload exclusion, copied/reserved refusals, changed staged/reserved indexes,
history-write failure and replaced stage root. Each selected case uses a fresh
process. Twelve six-second before/after resource pairs precede these cases.
Required markers and clean poweroff must complete within 900 seconds.

```sh
v -nocache -o /tmp/release-owner-check tests/packages/release-owner-check.v
V=/path/to/reviewed/v /tmp/release-owner-check /build/new-release-host

v -nocache -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/release-owner-runtime tests/packages/release-owner-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/release-owner-runtime --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-release-arm
```

Repeat for x86_64 with its matching kernel and a new state directory. The baseline
uses the same fixture and original release, publication, canonicalization and
seed-reader sources at `9c6e02a03` in an isolated module copy. Its flag skips the
new reply-close API and zero-retention assertions. Cold JSON initialization,
production publisher/catalog migration, graphical sessions and real application
and runtime compatibility remain separate acceptance gates. Section 14 stays open.

## Recorded results, 2026-10-18

| Target | Result | Time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 247.495 s | [receipt](results/2026-10-18/release-owner-aarch64.json), [serial](results/2026-10-18/release-owner-aarch64.serial.txt) |
| x86_64 | PASS | 300.686 s | [receipt](results/2026-10-18/release-owner-x86_64.json), [serial](results/2026-10-18/release-owner-x86_64.serial.txt) |

All **27 host build/test checks passed**, including both tracked suites, four
ASan/UBSan suites, 64 release and 144 catalog staging substitutions, signing-seed
and signed-index admission, signature and offline lifecycle/CLI regressions.
The [host receipt](results/2026-10-18/release-owner-host.json) retains exact
inputs, commands, timings and artifact hashes; its
[summary](results/2026-10-18/release-owner-host.txt) lists every check.
The [CLI log](results/2026-10-18/release-owner-cli.txt) covers authenticated
enrollment, reviewed deployment, offline mirrors, rollback and uninstall after
publisher revocation.

Each guest passed all 448 tracked canonical cycles, ordinary release/seed
regressions, twelve selected complete-call cases and clean poweroff. All
168 denial samples per guest were zero. These bounded observations do not claim
kernel allocation freedom. Existing kernels are pinned. The x86_64 run uses an
isolated V plain-USTAR media adapter for its exact pre-gzip kernel; production
image tooling is unchanged. Toolchain, sysroot, firmware and Limine requirements
follow the [hardware harness](../hardware-platform/README.md).

The [baseline](results/2026-10-18/release-owner-baseline.txt) retained **245
allocations** per successful measured call; byte counts depend on fixture paths.
Its [fixture](results/2026-10-18/release-owner-baseline.v), original sources and
[compile command](results/2026-10-18/release-owner-baseline-command.json) are
retained. The [journal guards](results/2026-10-18/release-owner-journal-check.txt)
reject changed inputs/artifacts and existing fresh-run directories before
compilation; an intact completed journal resumes with original timings and pins.

The [retention helper](results/2026-10-18/release-owner-retain.v) verifies
the baseline source anchor, receipts, zero-retention markers, preservation
outcomes and resource samples before saving evidence. Its
[ledger](results/2026-10-18/release-owner-toolchain.json) pins sources, compiler,
host/guest artifacts, baseline dependencies, the local media adapter and reports.
Builds use `-nocache` with V 0.5.2 `826e96f`, compiler fallback disabled. The
compiler SHA-256 is
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
