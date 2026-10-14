# Atomic package metadata publication

Catalogs, publisher manifests/indexes/locks, configuration and trust history now
share one bounded metadata writer. It refuses embedded NUL path bytes, invalid
file names and documents larger than 8 MiB before creating anything. A captured
ordinary parent directory anchors exclusive `openat` creation, `renameat`
publication, `unlinkat` cleanup and directory `fsync`. The parent and temporary
descriptors have close-on-exec set; opens do not follow final aliases and use
nonblocking mode. Temporary names use 128 random bits with bounded collision retry.

Temporary files start at mode `0600`. Complete writes handle interruptions and
short writes, then check the captured temporary's size and named identity before
setting `0644` and flushing it. Identity and size are checked again before atomic
replacement. The named parent must still match its captured device/inode. A
destination symlink is replaced itself, including a link to a directory; a real
directory destination refuses. The parent is flushed using its original descriptor.
Ordinary failure cleanup removes only a temporary name that still identifies the
opened file, without following or deleting a substituted name.

Before replacement, failure preserves the old document. After replacement,
failure retains the saved document and reports that saving occurred, with storage
inspection/retry guidance. This includes a directory flush failure or a changed
parent path. Readers continue seeing a complete old or new document. Existing
package locks and the ordering of trust floors before catalog/configuration
publication remain in effect; this is not a multi-document transaction.

Previously the general writer reused `PATH.new` with truncating path opens and
path-based chmod/flush. A stale symlink or hard link could overwrite external
data; a FIFO blocked. `os.rename` could also move the metadata inside a destination
directory or directory symlink instead of replacing the leaf. Administration had
a separate unique-temporary implementation. The
[public regression](atomic-write-check.v) records eight old behaviors and requires
safe publication or refusal with preserved external contents in normal mode.
Two-second child alarms bound blocking regressions.

The [core assertions](../../tools/packages/pkgcore/atomic_test.v) cover empty,
binary and inclusive-limit contents, temporary/final modes and close-on-exec,
one injected interruption plus short writes, zero/error writes, file/directory
flush failures, failure checkpoints before/after publication, changed temporary
names and changed parents. Four concurrent writers and a reader accept only
complete documents. Under a 32-descriptor limit, 128 success/failure cycles check
descriptor retirement. Existing administration tests also check common-writer
cleanup and preservation of planted `.new` aliases.

The Linux guest performs signed CLI refreshes with a catalog `.new` alias, hard
link, FIFO and directory, alongside planted configuration/history `.new` aliases.
Each update succeeds without following or modifying those names, changing the
installed generation or weakening retained trust history. Verification still
succeeds. Direct calls check directory-symlink replacement and NUL refusal. The
controller requires
`PACKAGE METADATA WRITE exclusive-temporary captured-parent stale-names preserved-state restored-verification PASS`.

Temporary names left by process death or power loss are ignored by later writes;
ordinary error paths attempt cleanup. Staging-directory recovery can remove its
abandoned work; this helper does not delete arbitrary stale names or promise
storage cleanup when the filesystem itself refuses unlink. Captured descriptors
do not freeze administrator changes to ancestors, destinations or same-size file
contents. Controlled directories and writer locks retain their roles. These
checks do not qualify physical power-loss behavior or whole-process heap retention.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/atomic-core tools/packages/pkgcore/atomic_test.v
/tmp/atomic-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/atomic-check tests/packages/atomic-write-check.v
/tmp/atomic-check /tmp/new-atomic-qualification
```

The maintained distribution driver discovers the core tests and runs the public
regression. `--before` requires the previous implementation. See the
[Linux runtime controller](linux-runtime-check.md) for retained kernel/sandbox
qualification without the legacy staging wrapper. Public publisher enrollment,
graphical login and broader catalog/runtime acceptance remain separate gates.

## Recorded results, 2026-10-14

All 43 package core runners passed. Atomic publication, administration, mirror
and release also passed clang ASan/UBSan with leak detection disabled and
undefined behavior fatal. The signed CLI lifecycle, public atomic/hash/copy/
metadata regressions, ELF profile checks and updated distribution driver
compilation passed. Real TLS/Range checks passed through HTTPS-only mode. The
host ledger records all 109 successful compile/run results.

The previous writer reproduces all eight cases, including one FIFO alarm,
external-file corruption through aliases/hard links, misplaced directory writes
and accepted NUL/oversized inputs. The final public regression records five safe
publications and three preserving refusals, without following stale names.

Both fresh QEMU TCG Linux runtime guests passed every required marker and clean
poweroff: AArch64 reported 51.8 seconds, x86_64 reported 56.1 seconds, within the
300-second functional deadline. Current service, guest init, account/session and
runtime probe/library/runner programs were rebuilt with retained kernels and
production sandboxes. Each receipt pins eleven inputs/logs, with QMP shutdown
logs retained separately. The new metadata-write marker is required on both
architectures alongside the existing signed runtime, offline recovery, reviewed
deployment, isolated launch, trust-history and rollback workflows.

Evidence: [before](results/2026-10-14/atomic-write-before.txt),
[after](results/2026-10-14/atomic-write-after.txt),
[host checks](results/2026-10-14/atomic-write-host.txt),
[individual results](results/2026-10-14/atomic-write-host.json),
[signed CLI](results/2026-10-14/atomic-write-cli.txt),
[TLS/Range](results/2026-10-14/atomic-write-https.txt),
[sanitizers](results/2026-10-14/atomic-write-asan.txt),
[AArch64 receipt](results/2026-10-14/atomic-write-aarch64.json),
[serial](results/2026-10-14/atomic-write-aarch64.serial.txt),
[QMP](results/2026-10-14/atomic-write-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/atomic-write-x86_64.json),
[serial](results/2026-10-14/atomic-write-x86_64.serial.txt),
[QMP](results/2026-10-14/atomic-write-x86_64.qmp.txt) and
[source/compiler/artifact ledger](results/2026-10-14/atomic-write-toolchain.json).
