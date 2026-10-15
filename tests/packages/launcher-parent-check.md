# Launcher parent admission

The previous launcher check could accept canonical bytes reached through a
symbolic `share` or `share/applications` parent. The retained reproduction
exercises both aliases against that implementation.

Verification now captures the generation and both parent directories without
following aliases, checks administrator ownership, filesystem identity and final
0755 directory modes, and opens the canonical 0644 launcher relative to the
captured parent. It validates the captured file’s type, owner, size and bytes,
then rechecks its named identity and every parent’s identity, owner and mode.
No fault is repaired in place. The documented readable hard-linked-launcher
behavior is preserved; full generation publication/rollback still requires
single-link files. Runtime/data packages do not acquire a launcher requirement.
Private stages admit pre-flush modes under their private root, then pass the
existing full flushed-generation checks.

Verify, health, exact-version repair discovery and ordinary launch share this
check. Shared parent faults are `registration` findings for affected apps, while
runtime/data health stays independent. A damaged launcher prevents ordinary
launch before private-data preparation or runtime execution. Repair needs fresh
authorization and stages ordinary directories from authenticated cached payloads,
preserving manifests, provenance, outside alias targets and personal data.

The [core assertions](../../tools/packages/pkgcore/registration_parent_test.v)
cover both parent aliases, unsafe directory modes, special entries, hard-link
compatibility and private-stage modes. Twenty-four captured/opened/read mutations
replace or chmod the root, parents or file. Forked ordinary accounts refuse
damaged registration and can verify restored administrator-owned trees; root
guests additionally test foreign ownership. Repeated healthy/refused checks run
under a 32-descriptor limit, with allocation measurements in tracked host builds.

The [signed CLI probe](launcher-parent-check.v) covers alias and mode faults at
both shared parents, all affected apps, stale approvals, read-only findings,
offline repair, retained generations and clean uninstall. It checks unchanged
app/runtime/data manifests, provenance, trust history, outside files and personal
data. Existing installation-health, complete-health, generation admission,
registration, namespace, launch-data, review and distribution assertions regress
the shared paths.

The [target controller](launcher-parent-runtime-check.v) runs the real CLI,
parent assertions and complete health checks on both committed-kernel targets.
The existing [native catalog controller](native-catalog-check.v) additionally runs
the real Hello, Counter and Memo apps through ordinary sessions and production
sandboxes, including updates, rollback and offline reinstall. These remain CLI
and headless protocol checks; production publisher enrollment, catalog migration,
full graphical login and broader foreign-runtime qualification stay open.


## Recorded results, 2026-10-15

All 23 host compile/run checks and both complete desktop architecture typechecks
passed. The launcher-parent ASan/UBSan and tracked checks passed with leak
detection disabled. There were zero retained checker bytes in 128 healthy and
128 refused checks, and existing installation-health and complete-health probes
also retained zero tracked bytes. These measurements cover the checkers, not
the complete package service.

Fresh committed-kernel TCG launcher-parent guests passed on AArch64 (65.6 seconds)
and x86_64 (81.0 seconds). Both include ordinary UID refusal/restored-root-owned
verification, root-only ownership faults, mutation checks and the real signed CLI.
Fresh native catalog guests also passed on AArch64 (88.216 seconds)
and x86_64 (131.988 seconds), exercising real Hello, Counter and Memo execution
through production sandboxes, updates, rollback, uninstall and offline reinstall.
Every guest shut down cleanly. Existing signed native inputs and production
sandboxes were hash-admitted; account/session/package programs were freshly built.
These remain CLI/headless checks, with the broader release gates open.

- [host checks](results/2026-10-15/launcher-parent-host.json)
- [host summary](results/2026-10-15/launcher-parent-host.txt)
- [previous parent-alias bypass](results/2026-10-15/launcher-parent-before.txt)
- [core and allocation probes](results/2026-10-15/launcher-parent-core.txt)
- [signed CLI](results/2026-10-15/launcher-parent-cli.txt)
- [sanitizers](results/2026-10-15/launcher-parent-asan.txt)
- [compiler/source/artifact ledger](results/2026-10-15/launcher-parent-toolchain.json)
- [aarch64 receipt](results/2026-10-15/launcher-parent-aarch64.json)
- [aarch64 report](results/2026-10-15/launcher-parent-aarch64.txt)
- [aarch64 serial](results/2026-10-15/launcher-parent-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/launcher-parent-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/launcher-parent-x86_64.json)
- [x86_64 report](results/2026-10-15/launcher-parent-x86_64.txt)
- [x86_64 serial](results/2026-10-15/launcher-parent-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/launcher-parent-x86_64.qmp.txt)
- [native-aarch64 receipt](results/2026-10-15/launcher-parent-native-aarch64.json)
- [native-aarch64 report](results/2026-10-15/launcher-parent-native-aarch64.txt)
- [native-aarch64 serial](results/2026-10-15/launcher-parent-native-aarch64.serial.txt)
- [native-aarch64 QMP](results/2026-10-15/launcher-parent-native-aarch64.qmp.txt)
- [native-x86_64 receipt](results/2026-10-15/launcher-parent-native-x86_64.json)
- [native-x86_64 report](results/2026-10-15/launcher-parent-native-x86_64.txt)
- [native-x86_64 serial](results/2026-10-15/launcher-parent-native-x86_64.serial.txt)
- [native-x86_64 QMP](results/2026-10-15/launcher-parent-native-x86_64.qmp.txt)
