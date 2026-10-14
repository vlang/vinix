# Captured file and directory durability

The package service's `sync_file` and `sync_directory` now open one descriptor
with `O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK`; directories also require
`O_DIRECTORY`. File flushes require regular files and nonnegative sizes;
directory flushes require directories. Empty/NUL paths refuse before opening.
Trailing directory separators are removed while preserving root, so a trailing
slash cannot bypass protection of the actual leaf.

Before and after `fsync`, descriptor and no-follow named metadata must still
match the captured type, device and inode. File sizes must remain unchanged;
directory sizes can change as entries are created. Flushes use the captured
descriptor, retry EINTR and close it on every exit. Errors identify changed
targets or failed captured flushes and request inspection of storage/state.
Existing activation/publication callers retain their explicit diagnostics when
a directory flush fails after an atomic switch.

Previously file flushes used a blocking pathname open that accepted directories,
followed leaf aliases and silently truncated NUL paths. Directory flushes followed
leaf aliases and also accepted NUL suffixes. The [before/after probe](durability-check.v)
reproduces six acceptances, a FIFO alarm and an existing wrong-type refusal.
The final implementation must promptly refuse all eight cases, preserve outside
contents/modes, and flush ordinary files and trailing-slash ordinary directories
on retry. The maintained distribution driver and both Linux runtime guests run
the probe; guests require `PACKAGE DURABILITY`.

The [core runner](../../tools/packages/pkgcore/durability_test.v) checks name
substitution before and after flushing, file growth, exact descriptor identity,
EINTR retry, injected I/O failure and restored successful flushes. A 32-descriptor
limit covers 128 cycles of file/directory success and four refusal paths.
No CLI/environment option enables production fault hooks.

Controlled ancestors and package locks remain required. These checks do not
freeze arbitrary in-place edits, qualify all caller-side mutations or establish
physical-device write-cache behavior. They confirm successful flushes against a
captured object and refuse observable changes. The separate ext2 runs cut QEMU
at three completed transaction checkpoints, then recover the same disk without
host repair. They do not interrupt inside a filesystem rename/flush or model
loss of the host's write cache. See [persistent-storage recovery](persistence-check.md).

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/durability-core tools/packages/pkgcore/durability_test.v
/tmp/durability-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/durability-probe tests/packages/durability-check.v
/tmp/durability-probe /tmp/new-durability-work
```

Publisher enrollment, broader catalog migration and graphical/runtime
qualification remain separate roadmap gates.

## Recorded results, 2026-10-14

All 46 package core runners passed in four independent shards. Durability,
release, mirror and progress passed clang ASan/UBSan (leak detection disabled,
undefined behavior fatal). The signed CLI lifecycle, signing-seed regression
and maintained real TLS/Range suite passed. The host ledger records 110 successful
compile/run results. The baseline reproduces six acceptances and a FIFO alarm;
the final probe refuses all eight malformed inputs and permits ordinary retries.

Both fresh Linux runtime guests passed their full signed workflows and clean
shutdown: AArch64 reported 298.2 seconds; x86_64 reported 191.0 seconds (300-second deadline). Each receipt
pins fifteen artifacts/logs, including the target durability probe.
The initial x86_64 run reached the same 300-second deadline during concurrent
host compilation, after passing the new durability probe. The unchanged build
passed on retry with less host load; both controller logs remain pinned.

All three ext2 SIGKILL/reboot scenarios passed on each architecture, using the
same disk across each cut/recovery pair, with no host filesystem
repair. Receipts pin ten inputs/logs each; the exact initial formatted images
are retained privately and rehashed during the evidence audit. Each case has
two serial boots and a guest-initiated final shutdown in QMP. These are completed
checkpoint tests; wider filesystem/device crash windows remain open.
An initial AArch64 harness attempt could not start the two longer checkpoint
names because their QMP socket paths exceeded the host limit. The full suite
was rerun from shorter state directories; the failed controller log is pinned.

Evidence: [before](results/2026-10-14/durability-before.txt),
[after](results/2026-10-14/durability-after.txt),
[host](results/2026-10-14/durability-host.txt),
[results](results/2026-10-14/durability-host.json),
[CLI](results/2026-10-14/durability-cli.txt),
[TLS](results/2026-10-14/durability-https.txt),
[sanitizers](results/2026-10-14/durability-asan.txt),
[Linux AArch64 receipt](results/2026-10-14/durability-linux-aarch64.json),
[serial](results/2026-10-14/durability-linux-aarch64.serial.txt),
[QMP](results/2026-10-14/durability-linux-aarch64.qmp.txt),
[Linux x86_64 receipt](results/2026-10-14/durability-linux-x86_64.json),
[serial](results/2026-10-14/durability-linux-x86_64.serial.txt),
[QMP](results/2026-10-14/durability-linux-x86_64.qmp.txt),
[ext2 AArch64 receipt](results/2026-10-14/durability-persistence-aarch64.json),
[serial](results/2026-10-14/durability-persistence-aarch64.serial.txt),
[QMP](results/2026-10-14/durability-persistence-aarch64.qmp.txt),
[ext2 x86_64 receipt](results/2026-10-14/durability-persistence-x86_64.json),
[serial](results/2026-10-14/durability-persistence-x86_64.serial.txt),
[QMP](results/2026-10-14/durability-persistence-x86_64.qmp.txt) and
[compiler/source/artifact ledger](results/2026-10-14/durability-toolchain.json).
