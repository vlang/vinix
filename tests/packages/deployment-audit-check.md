# Installed deployment drift audit

`vinix-package [--offline] [--json] deployment-audit LOCK.json` compares a supplied
exact format-2 deployment with one reader-locked installed generation. Exit 0 means
metadata matches, 3 means a complete drift report, and 1 means an error. The report
identifies the generation, architecture and SHA-256 of the exact captured input.
It names all missing, unexpected and changed packages, including versions,
architectures, canonical manifests, publisher/repository identities, requested
roots and sequence floors. A newer installed sequence satisfies the lock floor.

Auditing reads no catalog, cache object, replay history or payload tree. Revoked
repositories, restrictive valid policy, unavailable catalogs and a fresh store
remain observable. The command never initializes a fresh package store, applies
changes, grants trust or enters the administrator mutation transport. A matching
report is not an integrity or trust attestation; health and reviewed deployment
retain their existing contracts.

Core tests cover both metadata architectures, all changed fields, shared runtime
and architecture-independent data, missing/extra/subset/root drift, exact captured
digests, newer/below-floor sequences, writer exclusion, malformed and roots-only
documents, aliased files, corrupt state, independently owned reports and fresh
empty observation. The bounded protocol reader rejects unknown/duplicate/missing
fields, bad types/numbers/UTF-8, unsorted/duplicate rows or differences, incoherent
versions/status/result and oversized unions. Its heap fixture measures 1,000
valid and partially invalid decode/close cycles.

The maintained distribution driver's signed snapshot probe also checks audit:
catalog withdrawal, below-floor data, offline revoked configuration, missing
fresh-state packages, exact reproduction from newly authenticated media, newer
installed publisher sequences, uninstall drift and fixed CLI exit codes. Guest
qualification adds an ordinary UID 1000 audit of root-owned installed metadata.

Run `tests/packages/deployment-audit-runtime-check.v` with the standard hardware
host module path, `--arch aarch64|x86_64`, `--kernel` and a fresh `--state-dir`.
The controller checks core/protocol/signed-workflow markers and clean shutdown,
then emits a receipt pinning kernel, init, CLI, core, protocol, probe and serial
log. Host ASan/UBSan checks cover core and the real signed CLI/probe workflow.
Broader graphical, publisher enrollment, catalog and foreign-runtime gates remain
open.


## Recorded results, 2026-10-15

All 20 host compile/run checks passed: core and strict protocol tests, installed
snapshot/deployment regressions, real signed CLI workflow and ASan/UBSan core,
protocol and instrumented CLI/probe. Leak detection was disabled. The protocol
heap check retained zero tracked bytes across 1,000 complete and partially invalid
decode/close cycles; this does not measure whole-service allocation freedom.

Committed-kernel TCG guests passed on AArch64 (20.2 seconds) and
x86_64 (21.4 seconds), including strict protocol checks, ordinary UID 1000
auditing of root-owned state, missing/changed drift, offline revoked metadata,
newer sequence-floor matches after exact authenticated reproduction, uninstall
drift and clean QMP shutdown. Each receipt pins seven artifacts.

Private V controllers use the previously qualified resumable builder and private
AArch64 sysroot. All init, package, core, protocol and probe binaries were built
for this feature. Compiler, sources, target C, build/resume records, final logs,
binaries and copied sysroot inputs are pinned. The initial CLI test expectation
was corrected to include unchanged data below the new lock sequence floor; its
failed probe and exploratory binaries are excluded from passing evidence.
Broader release gates remain open.

- [host checks](results/2026-10-15/deployment-audit-host.json)
- [host summary](results/2026-10-15/deployment-audit-host.txt)
- [core regressions](results/2026-10-15/deployment-audit-core.txt)
- [signed CLI workflow](results/2026-10-15/deployment-audit-cli.txt)
- [sanitizers](results/2026-10-15/deployment-audit-asan.txt)
- [compiler/source/artifact ledger](results/2026-10-15/deployment-audit-toolchain.json)
- [aarch64 receipt](results/2026-10-15/deployment-audit-aarch64.json)
- [aarch64 report](results/2026-10-15/deployment-audit-aarch64.txt)
- [aarch64 serial](results/2026-10-15/deployment-audit-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/deployment-audit-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/deployment-audit-x86_64.json)
- [x86_64 report](results/2026-10-15/deployment-audit-x86_64.txt)
- [x86_64 serial](results/2026-10-15/deployment-audit-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/deployment-audit-x86_64.qmp.txt)
