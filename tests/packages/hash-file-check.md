# Captured package payload hashing

Payload hashing now opens one descriptor with `O_NOFOLLOW`, `O_NONBLOCK` and
`O_CLOEXEC`, rejects embedded NUL path bytes, and requires a regular file through
`fstat`. Signed verification checks the expected length on that same descriptor
before reading. Generic publisher hashing admits the descriptor's captured length.
Both paths use a fixed 64 KiB buffer and read at most the captured size plus one
sentinel byte. Reads retry interruptions; early EOF, growth and changed final
sizes refuse. The final pathname must still identify the captured regular file
with the same device, inode and size before a digest is returned.

Previously, `hash_file` checked a pathname and then reopened it with `os.open`.
An exchanged symlink could redirect hashing and an exchanged FIFO could block.
`verified_file` also checked the size separately from the file it hashed, allowing
a mismatched-length replacement to pass when its digest matched the expected
hash. The [bounded public regression](hash-file-check.v) exercises four cases
against the actual old implementation: a FIFO alarm, hashing an alias, accepting
an alias during verification and accepting a different-length ordinary file.
Normal mode requires 10,000 safe hash/verification attempts per exchange case.
Each reader runs in a child with a four-second alarm; the parent reaps both
children.

The [core assertions](../../tools/packages/pkgcore/hash_test.v) cover empty and
binary contents, 64 KiB boundaries, multiple blocks, independently computed
digests, owned returned strings, correct and incorrect hashes and lengths, and
special/NUL/missing paths. Private checkpoints deterministically replace paths
before/after sizing, during hashing and after EOF. Even identical replacement
bytes must refuse a changed inode; FIFOs and aliases are never followed. Other
checkpoints grow, sparsely expand or truncate the captured file, then restore it
for a successful retry. A sparse 4 GiB fixture proves mismatched signed lengths
refuse before any hash block is read. Under a 32-descriptor limit, 128 cycles
exercise success, mismatch, malformed input and injected failure cleanup.

The Linux guest's production CLI checks five damaged installed payloads: a
symlink to identical bytes, a FIFO, a directory, appended data and a same-length
checksum mismatch. Every refusal preserves the generation, rollback history and
external file. Restoring each payload permits successful verification. Direct
hash/verification calls also reject NUL paths. The controller requires
`PACKAGE PAYLOAD HASH captured-files signed-length special-file-refusal preserved-state restored-retry PASS`.
Existing signed runtime maintenance, isolated launch, download recovery, offline
deployment, publisher revocation and rollback checks remain required.

These checks capture identity and bound hashing; they do not freeze arbitrary
same-length in-place writes or guarantee the pathname cannot change after return.
Controlled package directories, locks, signatures and later verification retain
their roles. Generic hashing has no fixed total-size ceiling; its captured regular
file length bounds work, while signed verification admits exactly the expected
length before reading. Descriptor tests do not claim whole-process heap retention.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/hash-core tools/packages/pkgcore/hash_test.v
/tmp/hash-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/hash-check tests/packages/hash-file-check.v
/tmp/hash-check /tmp/new-hash-qualification
```

The maintained distribution driver discovers the core tests and runs the public
exchange regression. `--before` requires the previous implementation. The
[Linux runtime controller](linux-runtime-check.md) supports retained target kernels
and production sandbox inputs, rebuilding the current service, guest init and
account/session programs. No public publisher enrollment, graphical login or
broader catalog/runtime acceptance is claimed by this change.

## Recorded results, 2026-10-14

All 42 package core runners passed, including the new captured hashing tests.
Hash, download recovery, mirror and release also passed clang ASan/UBSan with
leak detection disabled and undefined behavior fatal. The full signed CLI lifecycle,
public hash/copy/metadata regressions, ELF profile checks and updated distribution
driver compilation passed. Real TLS/Range checks passed through HTTPS-only mode.
The host ledger records all 105 successful compile/run results.

The previous binary reproduces one FIFO alarm and three wrong-content/length
acceptances. The final hash regression completes all four 10,000-attempt exchange
cases with safe results and preserved external file contents/modes.

Both fresh QEMU TCG Linux runtime guests passed every required marker and clean
poweroff: AArch64 reported 41.4 seconds, x86_64 reported 46.5 seconds, within the
300-second functional deadline. Current service, init, account/session and runtime
probe/library/runner programs were rebuilt with retained kernels and production
sandboxes. Each receipt pins eleven inputs/logs; QMP shutdown logs are retained
separately. Both guests require the new payload hash refusal/restored-retry marker.

Evidence: [before](results/2026-10-14/hash-file-before.txt),
[after](results/2026-10-14/hash-file-after.txt),
[host checks](results/2026-10-14/hash-file-host.txt),
[individual results](results/2026-10-14/hash-file-host.json),
[signed CLI](results/2026-10-14/hash-file-cli.txt),
[TLS/Range](results/2026-10-14/hash-file-https.txt),
[sanitizers](results/2026-10-14/hash-file-asan.txt),
[AArch64 receipt](results/2026-10-14/hash-file-aarch64.json),
[serial](results/2026-10-14/hash-file-aarch64.serial.txt),
[QMP](results/2026-10-14/hash-file-aarch64.qmp.txt),
[x86_64 receipt](results/2026-10-14/hash-file-x86_64.json),
[serial](results/2026-10-14/hash-file-x86_64.serial.txt),
[QMP](results/2026-10-14/hash-file-x86_64.qmp.txt) and
[source/compiler/artifact ledger](results/2026-10-14/hash-file-toolchain.json).
