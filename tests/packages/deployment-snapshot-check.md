# Installed deployment snapshots

`deployment-snapshot [INSTALLED_ID...]` exports a format-2 deployment document
from one reader-locked installed generation. It selects the original requested
roots or an explicit installed subset and includes their complete transitive
runtime/data closure. Versions, architecture, publisher identity, sequence floors
and canonical manifest digests remain exact. It never resolves replacements
against a catalog and does not initialize an empty package store.

The command records historical metadata. It can run with unavailable catalogs,
objects and replay history, revoked repositories and restrictive current policy.
It does not verify payload health, export payloads, enroll trust or authorize
installation. Existing deployment review/apply and mirror export still require
authenticated exact manifests and current replay/policy admission.

Core tests cover both metadata architectures, shared dependencies, explicit
dependency roots, sorting, exact pins, absent/duplicate/invalid/excess IDs,
independent document ownership and repeated close, fresh-state observation,
writer exclusion and malformed state refusal. The sanitizer run exercises success
and refusal cleanup. Existing deployment, review and service regressions cover
the shared independently owned document builder and authenticated maintenance.

The signed CLI probe installs version 1, withdraws it while publishing version 2,
and shows the catalog lock choosing 2 while the snapshot retains 1. It refuses
deployment while the exact manifests are unavailable. Snapshot export then
continues with corrupt catalog/history and revoked/restrictive configuration.
Newly signed approved media supplies the archived manifests; a fresh consumer
authenticates that media and applies the snapshot as exact version 1, retaining
the source floor while recording the newer authenticated publisher sequence.

The maintained distribution driver includes the CLI probe. The target controller
boots committed kernels on AArch64 and x86_64, retaining six artifact hashes,
serial output and QMP shutdown evidence. Guest root also forks an ordinary UID
1000 reader and checks that it obtains identical root-owned metadata without
administrator authorization. Snapshot export remains outside the administrator
mutation transport.

These are metadata/CLI qualifications, not graphical application or additional
foreign-runtime acceptance. Roadmap 14's production publisher enrollment, broader
catalog migration and ordinary graphical login/display-broker gates remain open.


## Recorded results, 2026-10-15

All 16 host compile/run checks passed: installed snapshot core, existing deployment,
review and service regressions, production CLI plus signed workflow, and ASan/UBSan
core plus signed workflow with both CLI and probe instrumented. Leak detection was
disabled; these runs do not establish whole-service allocation freedom.

Committed-kernel TCG guests passed on AArch64 (28.9 seconds) and
x86_64 (38.2 seconds). Both include an ordinary UID 1000 reading
root-owned metadata, exact signed app/runtime/all-data reproduction and clean QMP
guest shutdown. Each receipt pins six artifacts. No kernel rebuild was needed.

Private V controllers use the previously qualified resumable C/binary builder and
private AArch64 sysroot; all package, core, probe and guest-init binaries were
built for this feature. Builder sources, target C, build/resume records, successful
host logs and binaries, compiler and copied sysroot inputs are pinned. Initial
exploratory core binaries are excluded from the passing evidence.

- [host checks](results/2026-10-15/deployment-snapshot-host.json)
- [host summary](results/2026-10-15/deployment-snapshot-host.txt)
- [core regressions](results/2026-10-15/deployment-snapshot-core.txt)
- [signed CLI workflow](results/2026-10-15/deployment-snapshot-cli.txt)
- [sanitizers](results/2026-10-15/deployment-snapshot-asan.txt)
- [compiler/source/artifact ledger](results/2026-10-15/deployment-snapshot-toolchain.json)
- [aarch64 receipt](results/2026-10-15/deployment-snapshot-aarch64.json)
- [aarch64 report](results/2026-10-15/deployment-snapshot-aarch64.txt)
- [aarch64 serial](results/2026-10-15/deployment-snapshot-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/deployment-snapshot-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/deployment-snapshot-x86_64.json)
- [x86_64 report](results/2026-10-15/deployment-snapshot-x86_64.txt)
- [x86_64 serial](results/2026-10-15/deployment-snapshot-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/deployment-snapshot-x86_64.qmp.txt)
