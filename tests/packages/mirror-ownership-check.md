# Offline mirror preparation ownership

Ordinary and format-2 deployment mirrors now retain an explicit owner for their
authenticated catalog, complete decoded snapshot set, selected snapshot buffer,
resolved plan buffers, independently copied root IDs, captured deployment text,
paths and fingerprint. Success, stale approval, disk refusal and export failures
retire that owner. Catalog manifests borrow only publisher identity from the
live configuration; selected snapshots borrow the retained decoded set. Closing
the prepared owner twice is safe. Public reviews clone their presentation fields
before preparation/configuration storage retires.

Deployment preparation resolves exact pins against its retained authenticated
catalog. It retires the decoded input document and temporary solver buffers while
keeping independently owned roots and exact captured bytes for later export.
The existing provenance, closure, architecture, permission and runtime checks
remain mandatory. Review space observations finish before allocating returned
presentation fields, so failed observations cannot orphan a partial review.

Path normalization and parent inspection retire component, cwd, realpath and
stat scratch. Normalization keeps the lexical POSIX path contract; canonical
physical ancestors still bind their device/inode and enforce administrator/sticky
directory rules. Existing or dangling leaf names refuse publication. Space
estimates retire deduplication maps and temporary object paths. Fingerprinting
uses an owned encoding buffer and digest state with byte-identical input to the
previous encoder, including both domain tags and no added newline.

The [core fixture](../../tools/packages/pkgcore/mirror_ownership_test.v) checks
1,000 repetitions each of path resolution, space estimation, warmed preparation,
relative normalization and independent review creation, plus 2,000 preparation
failures at filesystem inspection and size overflow. Those measured components
retain zero tracked bytes. The synthetic plan has sixteen applications with
2 KiB descriptions and shared objects. Setup, generic JSON cache warm-up,
authenticated catalog loading, file copying and complete public service calls
are outside this zero-retention claim.

Functional assertions also cover occupied files/directories, aliases, dangling
links, FIFOs, unsafe ancestors, malformed snapshot metadata, restoration/retry,
unchanged inputs and absent destination/cache side effects. Prepared snapshots
remain usable after removing the source file, including a filtered revoked
record. Both ordinary and deployment identities match the old JSON encoding
digest exactly. Reviews remain independent after preparation retires, and
borrowed caller manifests/configuration remain usable.

Run the [host controller](mirror-ownership-check.v) with a reviewed compiler in
`V` and a new work directory. It combines tracked assertions with clang
ASan/UBSan for ownership, signed ordinary mirrors and deployment locks. The
[target controller](mirror-ownership-runtime-check.v) runs the tracked fixture
and signed mirror/deployment/release suites in both architecture guests. Use
`VINIX_HWTEST_TCG=1`, the usual cross-toolchain environment, `--kernel`, `--arch`
and a new short `--state-dir`. The existing
[image export controller](image-export-check.v) covers shared parent checks,
publisher releases, image staging, real CLI maintenance and offline consumption.

This increment does not complete section 14's production publisher/catalog,
graphical login/display-broker, broader foreign-runtime or device/crash gates.

## Recorded results, 2026-10-17

Before the change, 64 path checks retained **496,256 bytes**, 64 space estimates
retained **156,800 bytes**, and eight metadata preparations retained
**1,129,563 bytes** after retiring their returned paths/fingerprint. That initial
metadata measurement included generic JSON cache initialization. The final
fixture measures warmed preparation separately and requires zero retained bytes
over every tracked component described above; these counts do not imply a
whole-service steady-state allocation rate.

All **40 host build/test checks** passed: eight focused checks, including
ASan/UBSan for ownership, ordinary mirror and deployment-lock suites, and the
existing 32-check image export regression. That regression covers twelve core
suites, desktop cache behavior, image application sanitizers and signed real CLI
maintenance. Sanitizer leak detection is disabled; undefined behavior is fatal.

Fresh QEMU TCG runs passed on AArch64 (**37.2 seconds**) and x86_64
(**33.1 seconds**). Each runs the tracked fixture and signed mirror, deployment
and release suites, then shuts down within 300 seconds. Seven-artifact receipts
bind each kernel, init, four test programs and serial output. The first launch
attempts refused before boot because the QMP socket path was too long; retries
used shorter directories with unchanged sources. Source, compiler, generated C,
executables and evidence hashes are recorded in the ledger.

- [original allocation regression](results/2026-10-17/mirror-ownership-baseline.txt)
- [focused host receipt](results/2026-10-17/mirror-ownership-host.json)
- [focused host summary](results/2026-10-17/mirror-ownership-host.txt)
- [tracked measurements](results/2026-10-17/mirror-ownership-memory.txt)
- [sanitizers](results/2026-10-17/mirror-ownership-asan.txt)
- [broader regression receipt](results/2026-10-17/mirror-ownership-regression.json)
- [broader regression summary](results/2026-10-17/mirror-ownership-regression.txt)
- [signed CLI](results/2026-10-17/mirror-ownership-cli.txt)
- [initial setup diagnostics](results/2026-10-17/mirror-ownership-attempts.txt)
- [source/artifact ledger](results/2026-10-17/mirror-ownership-toolchain.json)
- [AArch64 receipt](results/2026-10-17/mirror-ownership-aarch64.json), [report](results/2026-10-17/mirror-ownership-aarch64.txt), [serial](results/2026-10-17/mirror-ownership-aarch64.serial.txt), [QMP](results/2026-10-17/mirror-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-17/mirror-ownership-x86_64.json), [report](results/2026-10-17/mirror-ownership-x86_64.txt), [serial](results/2026-10-17/mirror-ownership-x86_64.serial.txt), [QMP](results/2026-10-17/mirror-ownership-x86_64.qmp.txt)
