# Saving installed deployment snapshots

`deployment-snapshot-save NEW_FILE [INSTALLED_ID...]` captures one reader-locked
installed generation and atomically publishes a new format-2 lock plus LF.
`--json` returns the captured generation, architecture, literal destination,
SHA-256 and root/package counts after file and directory flushing succeed.
Ordinary callers can export root-owned metadata into owned directories. The
command reads no catalog/history/cache/payload, grants no trust or administrator
authorization, and does not initialize a fresh package store.

Existing files, aliases (including dangling links), FIFOs, directories and
hardlinks are preserved. A destination created after preflight refuses at the
exclusive rename. The writer owns a random private temporary and one captured
parent descriptor. Short/EINTR writes, canonical final mode, file flush, exclusive
publication, directory flush and final identity admission retain the established
metadata write contract. Normal prepublication failures clean the owned
temporary. Postpublication errors explicitly report a saved file and preserve it
for inspection. Retry never replaces it. Abrupt-stop leftovers are not imported
or swept; controlled ancestors and no concurrent same-user in-place editing are
part of the file-publication contract.

New-file writer tests exercise every existing destination type, concurrent
publishers (one complete winner), write/space faults, pre/postpublication failures,
directory flush failure, destination creation races, mode changes, parent
replacement, final aliases/truncation, cleanup and safe retry. Existing atomic
replacement regressions retain their original behavior.

Snapshot-save tests cover both metadata architectures, sorted full/subset roots,
transitive runtime/all-data closure, exact bytes/provenance/sequence floors,
generation/digest receipts, valid policy independence, missing/duplicate/excess
roots, malformed paths/state, writer exclusion, no source mutation and fresh
empty observation. Receipt protocol tests cover complete typed fields,
duplicate/unknown keys, count/path/digest/numeric bounds, ownership and repeated
close, plus 1,000 complete/partial-invalid decode/close cycles under heap tracking.

The maintained distribution driver's signed CLI snapshot probe now saves the
actual deployment file consumed by audit and authenticated reproduction. It
checks exact receipts, withdrawn/offline/revoked metadata, existing-file
preservation, invalid invocation/root/progress refusal, and administrator
transport exclusion. The target controller runs save/new-file/protocol tests and
that signed workflow on both architectures. Guest UID 1000 exports identical
root-owned metadata to an owned relative destination and safely refuses overwrite.

The receipt pins kernel, guest init, production CLI, save core, new-file writer,
receipt protocol, signed probe and serial output. Clean QMP shutdown is required.
These are metadata/CLI qualifications; broader graphical, publisher enrollment,
catalog and foreign-runtime acceptance remain open.


## Recorded results, 2026-10-15

All 26 host compile/run checks passed: save/new-file/protocol core tests, existing
atomic replacement/snapshot/audit regressions, signed CLI workflow, ASan/UBSan
core and instrumented CLI/probe, and 1,000 receipt decode/close cycles retaining
zero tracked bytes. Leak detection was disabled; no whole-service allocation
freedom is claimed.

Committed-kernel TCG guests passed on AArch64 (14.5 seconds) and
x86_64 (14.5 seconds), including exclusive concurrent publication, all
new-file failure boundaries and existing destination types, exact saved receipts,
ordinary UID 1000 export into an owned relative destination, offline revoked
metadata and exact reproduction from newly authenticated media. Both guests
shut down cleanly. Each receipt pins eight artifacts.

Private V controllers use the previously qualified resumable builder and private
AArch64 sysroot. All init, CLI, save core, writer, receipt protocol and probe
binaries were built for this feature. Compiler, sources, generated target C,
build/resume records, final logs, binaries and copied sysroot inputs are pinned.
Broader graphical, publisher, catalog and foreign-runtime gates remain open.

- [host checks](results/2026-10-15/deployment-save-host.json)
- [host summary](results/2026-10-15/deployment-save-host.txt)
- [core regressions](results/2026-10-15/deployment-save-core.txt)
- [signed CLI workflow](results/2026-10-15/deployment-save-cli.txt)
- [sanitizers](results/2026-10-15/deployment-save-asan.txt)
- [compiler/source/artifact ledger](results/2026-10-15/deployment-save-toolchain.json)
- [aarch64 receipt](results/2026-10-15/deployment-save-aarch64.json)
- [aarch64 report](results/2026-10-15/deployment-save-aarch64.txt)
- [aarch64 serial](results/2026-10-15/deployment-save-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/deployment-save-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/deployment-save-x86_64.json)
- [x86_64 report](results/2026-10-15/deployment-save-x86_64.txt)
- [x86_64 serial](results/2026-10-15/deployment-save-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/deployment-save-x86_64.qmp.txt)
