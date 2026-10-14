# Space estimates for offline uninstall

Removal already copies verified retained files from the active generation.
Previously its space estimate also reserved a missing object-cache copy, even
when that download was unnecessary. This could reject an offline uninstall
despite enough room for the staged generation and the configured reserve.

Review and activation now share an operation-aware estimate. A retained file
discounts acquisition space only after regular-file, size and SHA-256 checks.
Missing, changed or linked files still require the cache/acquisition allowance;
shared missing objects are counted once. Other operations retain their original
accounting. Staged copies, filesystem overhead and policy reserves are required.
Size/addition overflow fails before staging. Every staged copy still verifies.

The [core assertions](../../tools/packages/pkgcore/removal_space_test.v) cover
active-generation selection, two paths sharing an object, valid/missing/corrupt
objects and retained files, symlinks/directories, acquisition operations and
overflow. The [lifecycle fixture](removal-space-fixture.v) signs/installs two
applications, then removes one with the publisher revoked, catalog/history
damaged, retained objects absent and repository objects unavailable. The
remaining app's verified files, registration, previous generation and personal
files must survive. Corruption after preflight refuses activation.

The [host controller](removal-space-check.v) compiles this fixture against the
platform's real `statvfs` layout and redirects only calls using a generated
forced-include header. Available bytes exactly equal staged space plus reserve;
the old extra download allowance fails at that threshold. One byte less must
still refuse. The production service contains no simulated free-space controls.

```sh
V=/path/to/v /path/to/v -nocache run tests/packages/removal-space-check.v
V=/path/to/v /path/to/v -nocache run tests/packages/removal-space-check.v --sanitize
```

The [target controller](removal-space-runtime-check.v) runs the same lifecycle
with real filesystem reports and the core
assertions. These checks cover functional preflight and transactional refusal,
not disk exhaustion during copying or physical-device power loss. Concurrent
writes, quotas and filesystem metadata allocation can still exhaust storage
after preflight. Broader roadmap 14 release gates remain open.

## Recorded results, 2026-10-14

The retained previous implementation (`c155a47f3`) failed the new lifecycle
assertion: it reported 4,231,168 bytes rather than 4,218,880 bytes, adding one
unnecessary 12,288-byte cache copy. The corrected service passed with exactly
4,218,880 bytes plus the unchanged 4,096-byte policy reserve. One byte less
refused; damaged retained bytes restored the fallback allowance and refused
activation. Corruption introduced by the progress observer after preflight also
refused activation. Restored bytes allowed reviewed offline removal while
retaining the other app, old generation, registration and personal files.

Eight host assertion runners passed: removal estimates, reviews, distribution,
service, policy, deployment, download recovery and durability. The real signed
CLI lifecycle passed, and the maintained distribution driver compiled. The
standalone threshold controller and the lifecycle with actual filesystem
reports also passed. Core and simulated-threshold lifecycle clang ASan/UBSan
runs passed with leak detection disabled and undefined behavior fatal. The
ledger records 30 successful host compile/run results; no whole-service leak
measurement is claimed.

Fresh QEMU TCG runs passed on AArch64 (12.9 seconds) and x86_64 (11.5
seconds). Each ran the core assertions and signed service lifecycle against
real filesystem reports, then shut down within the 300-second allowance. These
runs use retained committed kernels; no concurrent kernel edits were rebuilt.
Five-artifact receipts pin kernel, init, both assertion/lifecycle programs and
serial log. Generated C/build logs are pinned in the ledger. The exact free-space
threshold is simulated only in the host fixture, not in target kernels.

Evidence:

- [previous-implementation control](results/2026-10-14/removal-space-baseline.txt)
- [host results](results/2026-10-14/removal-space-host.json)
- [host checks](results/2026-10-14/removal-space-host.txt)
- [core assertions](results/2026-10-14/removal-space-core.txt)
- [threshold lifecycle](results/2026-10-14/removal-space-threshold.txt)
- [real filesystem lifecycle](results/2026-10-14/removal-space-real-space.txt)
- [sanitizers](results/2026-10-14/removal-space-asan.txt)
- [signed CLI lifecycle](results/2026-10-14/removal-space-cli.txt)
- [source/artifact ledger](results/2026-10-14/removal-space-toolchain.json)
- [aarch64 receipt](results/2026-10-14/removal-space-aarch64.json)
- [aarch64 report](results/2026-10-14/removal-space-aarch64.txt)
- [aarch64 serial](results/2026-10-14/removal-space-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/removal-space-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/removal-space-x86_64.json)
- [x86_64 report](results/2026-10-14/removal-space-x86_64.txt)
- [x86_64 serial](results/2026-10-14/removal-space-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/removal-space-x86_64.qmp.txt)
