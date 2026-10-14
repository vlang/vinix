# Local package output admission

Local copies require an ordinary destination with exactly one hard link before
truncation or writing. Sharing a read-only source is supported. This rule covers
`copy_file`, fresh/resumed `file://` transfers, publisher `pack` object temporaries
and the cache-to-generation/mirror/release copies that use the same copier.

The copier captures the destination descriptor and its device/inode, then checks
its named identity, regular-file type, length and link count before mutation,
after progress callbacks, before and after flushing, and after the final progress
callback. Reads/writes retain the existing captured source bound and resume
offset checks. Interrupted flushes retry; other storage errors return a diagnostic
and leave output available for inspection/retry. A failed operation cannot report
successful copy completion to its caller. A progress event can describe all bytes
written before a subsequent callback causes refusal; it is not an activation or
transaction-completion receipt.

The [public probe](copy-output-check.v) reproduces five prior overwrites of an
unrelated hard-linked file: fresh/resumed direct copies, fresh/resumed offline
transfers and a stale publisher object temporary. Against the fixed copier, all
five must refuse promptly and preserve source bytes, unrelated contents/mode and
retained output. A shared source copied into ordinary output must still succeed.
Three-second forked alarms make blocking regressions fail promptly. `--before`
requires the previous implementation and asserts its destructive behavior.

The [core assertions](../../tools/packages/pkgcore/copy_output_test.v) replace,
unlink, grow and hard-link output at the captured/opened and flushed checkpoints.
Aliased and FIFO replacements cannot redirect writes or flushes. Links added by
initial/final progress observers cause refusal; removing the extra name permits
an ordinary retry. Injected `EINTR` retries the flush, while `EIO` reports failure.
Sixty-four failure/refusal/success cycles run under a 32-descriptor limit. The
existing [copy assertions](../../tools/packages/pkgcore/copy_test.v) retain full,
empty, resumed and bounded transfer coverage; a destination replaced by the
initial progress observer now refuses before copying payload bytes.

The [distribution driver](distribution-check.v) discovers the new core runner and
runs the public probe. The [Linux runtime controller](linux-runtime-check.v)
cross-compiles it for both targets, includes it in receipt hashes, and requires
`PACKAGE COPY OUTPUT hardlink-refusal preserved-prefix publisher-temporary ordinary-retry PASS`
alongside the full signed lifecycle and isolated Linux runtime workflows.

Controlled parent directories and serialization of other writers remain
required. Descriptor capture and identity checks do not snapshot arbitrary
same-size in-place writes or freeze concurrent users with the same authority.
If a link is added during an operation, earlier bytes can already have changed;
refusal does not roll a copy back. Package staging, signature/hash verification
and generation activation retain their separate guarantees. No physical-device
write-cache durability or whole-process heap-retention claim is made here.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/copy-output-core tools/packages/pkgcore/copy_output_test.v
/tmp/copy-output-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/copy-output-check tests/packages/copy-output-check.v
/tmp/copy-output-check /tmp/new-copy-output-qualification
```
## Recorded results, 2026-10-14

All 48 package core runners passed in four independent shards. The copy, output,
download-recovery and release runners passed clang ASan/UBSan (leak detection
disabled, undefined behavior fatal). The signed CLI lifecycle, original nine-case
copy probe, private signing-seed probe and maintained real TLS/Range suite passed.
The host ledger records 116 successful compile/run results. The baseline reproduces
all five hard-linked output overwrites; the final probe refuses all five while
preserving retained contents and modes. A shared source/ordinary output succeeds.

Both fresh QEMU TCG Linux runtime guests passed the full signed lifecycle and
clean shutdown: AArch64 reported 245.6 seconds; x86_64 reported 533.0 seconds. AArch64 used its
unchanged 300-second deadline; x86_64 used a 600-second diagnostic deadline. Each receipt pins seventeen inputs/logs,
including the target output probe. Two x86_64 runs exhausted the unchanged
300-second deadline, after passing output admission/collection in the first run
and metadata writes in the second. The same sixteen boot artifacts completed
with a 600-second diagnostic budget. The original 300-second x86_64 budget remains
unqualified. Failed logs remain retained and hashed. The guest, package service, fixtures and account/
session programs were rebuilt from current sources against retained committed
kernels and production sandboxes. These runs do not extend the physical crash,
graphical login or broader application-catalog release qualification.

Evidence:

- [before](results/2026-10-14/copy-output-before.txt)
- [after](results/2026-10-14/copy-output-after.txt)
- [host checks](results/2026-10-14/copy-output-host.txt)
- [individual results](results/2026-10-14/copy-output-host.json)
- [signed CLI](results/2026-10-14/copy-output-cli.txt)
- [TLS/Range](results/2026-10-14/copy-output-https.txt)
- [sanitizers](results/2026-10-14/copy-output-asan.txt)
- [guest attempts](results/2026-10-14/copy-output-attempts.txt)
- [AArch64 receipt](results/2026-10-14/copy-output-aarch64.json)
- [AArch64 serial](results/2026-10-14/copy-output-aarch64.serial.txt)
- [AArch64 QMP](results/2026-10-14/copy-output-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/copy-output-x86_64.json)
- [x86_64 serial](results/2026-10-14/copy-output-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/copy-output-x86_64.qmp.txt)
- [compiler/source/artifact ledger](results/2026-10-14/copy-output-toolchain.json)
