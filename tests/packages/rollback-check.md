# Transactional rollback qualification

Rollback restores a retained package set into a new generation. Its previous
link names the set it replaced. This keeps both the active and immediate
rollback state coherent after obsolete-generation cleanup and lets a subsequent
rollback undo the restoration. Source generations are never rewritten.

The previous implementation can be reproduced by installing four versions,
collecting generations 1 and 2, then rolling back from 4 to 3. Generation 3
still names deleted generation 2; cleanup then fails reading that missing state.
The retained before binary and source snapshot reproduce this failure.

`tools/packages/pkgcore/rollback_test.v` checks both metadata architectures,
exact retained-source space estimates, a valid 1 TiB reserve refusal before
abandoned-stage cleanup, interruption before activation, damaged publication,
offline retry without objects, rejection of legacy/reused approvals, immutable
source state, separate copied inodes, empty/identical sets, and reversible
cleanup. Existing generation-admission tests exercise four source changes after
activation progress and 90 changes to prepared/staged/published transactions.

`rollback-check.v NEW_WORK PACKAGE_CLI` uses real signed catalogs with an app,
target-specific runtime and architecture-independent data. It exercises reviewed
CLI restoration with ordered progress and no downloads, exact manifests,
provenance and roots, leased sources, cleanup before/after restoration, undo,
uninstall/reinstall through rollback, cache independence, and retained personal
data. The maintained distribution driver includes this probe.

`rollback-runtime-check.v` compiles the production CLI and both core probes for
each target, boots committed kernels and retains seven artifact hashes plus
serial/QMP evidence. Native catalog regressions run real Hello, Counter and Memo
through retained, hash-admitted production sandboxes, freshly built package and
account/session tools, signed update/rollback/uninstall and cached reinstall.
Software's existing fixture checks the restoration/undo explanation and source
identity in Details; its twelve allocation modes measure presentation ownership.

SDK 1 fields and command arguments remain unchanged. `target_generation` names
the restoration source. Active IDs advance; rollback toggles between the latest
two package sets rather than walking older ancestors. Old approvals require a
fresh review. Rollback requires space and current trust/policy admission, and
refuses damaged source trees. Personal data remains outside package history.

These are CLI/headless and isolated guest checks. Production publisher
enrollment, broader catalog migration, ordinary graphical login/display-broker
integration and additional foreign-runtime acceptance remain release gates.


## Recorded results, 2026-10-15

All 30 host compile/run checks passed, including the sanitizer run with leak
detection disabled and the real HTTPS transport regression. Both full desktop
architecture typechecks and the maintained Software driver passed. All twelve
presentation allocation modes retained zero tracked bytes; this does not measure
the complete package service. The cache-promotion regression now verifies state
through an observer-free service so Verify progress cannot contaminate the
refused transaction event log.

Committed-kernel TCG rollback guests passed on AArch64 (73.0 seconds)
and x86_64 (91.2 seconds). Native catalog guests passed on
AArch64 (42.677 seconds) and x86_64 (91.043 seconds), including real
Hello/Counter/Memo execution, updates, transactional rollback, uninstall and
cached reinstall with private data. All four guests shut down cleanly. Native
payloads and production sandboxes were admitted against existing receipts;
account/session/package tools were built for this change. Both suites use the
same production package CLI for each architecture.

Interrupted attempts are excluded. Private V resuming controllers reused completed
C/binary artifacts; remaining components were built without restarting completed
ones. Their sources, artifact records and final logs are pinned. After the shared
AArch64 sysroot disappeared, a private copy from the retained vinix-old sysroot
was admitted against 2180 original/copied file hashes; copied inputs are pinned.
Five completed host checks lost their timings on interruption and record zero
seconds. Host probe setup corrections (bounded reserve and observer isolation)
are reflected in the final successful logs. Broader release gates remain open.

- [host checks](results/2026-10-15/rollback-host.json)
- [host summary](results/2026-10-15/rollback-host.txt)
- [prior cleanup/rollback failure](results/2026-10-15/rollback-before.txt)
- [core regressions](results/2026-10-15/rollback-core.txt)
- [signed CLI and recovery probes](results/2026-10-15/rollback-cli.txt)
- [sanitizers](results/2026-10-15/rollback-asan.txt)
- [real HTTPS](results/2026-10-15/rollback-https.txt)
- [Software checks](results/2026-10-15/rollback-software.txt)
- [compiler/source/artifact ledger](results/2026-10-15/rollback-toolchain.json)
- [aarch64 receipt](results/2026-10-15/rollback-aarch64.json)
- [aarch64 report](results/2026-10-15/rollback-aarch64.txt)
- [aarch64 serial](results/2026-10-15/rollback-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/rollback-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/rollback-x86_64.json)
- [x86_64 report](results/2026-10-15/rollback-x86_64.txt)
- [x86_64 serial](results/2026-10-15/rollback-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/rollback-x86_64.qmp.txt)
- [native-aarch64 receipt](results/2026-10-15/rollback-native-aarch64.json)
- [native-aarch64 report](results/2026-10-15/rollback-native-aarch64.txt)
- [native-aarch64 serial](results/2026-10-15/rollback-native-aarch64.serial.txt)
- [native-aarch64 QMP](results/2026-10-15/rollback-native-aarch64.qmp.txt)
- [native-x86_64 receipt](results/2026-10-15/rollback-native-x86_64.json)
- [native-x86_64 report](results/2026-10-15/rollback-native-x86_64.txt)
- [native-x86_64 serial](results/2026-10-15/rollback-native-x86_64.serial.txt)
- [native-x86_64 QMP](results/2026-10-15/rollback-native-x86_64.qmp.txt)
