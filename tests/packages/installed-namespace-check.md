# Installed package namespaces

The baseline verifies an undeclared runtime library as healthy and finds no
unchanged-manifest repair. Verify, repair discovery and launch now require each
package tree to contain exactly its declared regular single-link files and the
directories implied by those paths. Extra files/directories/FIFOs, aliases,
missing entries, foreign ownership and changed modes refuse admission.

The state directory supplies administrator ownership independently of the reader's
UID. Generation/package parents are captured without following aliases; directories
inside a generation use 0755 and remain on the generation filesystem. File modes
remain 0755/0644 according to signed executable flags. Namespace inventory completes
before payload hashing, so a rejected directory alias is not used to hash outside
files. Ordinary launch checks the selected application/runtime/dependency closure
before private-data preparation or execution. Unrelated packages are checked by
Verify and their own launch/repair requests. Package namespace checks do not
inventory unrelated generation-level names or desktop registrations; existing
generation admission and registration checks retain those scopes.

Repair discovery binds faults to affected unchanged package IDs and existing
review fingerprints/disk estimates. Install, upgrade and managed deployment stage
fresh authenticated files rather than modifying damaged installed entries. Old
generations, outside targets, personal data, catalog and trust history survive.
Invalid state parents outside the generation require administrator restoration.
Rollback retains its whole-generation check and refuses damaged old trees.

Core assertions cover 24 application/runtime/data faults, generation/apps parent
aliases, root-guest foreign ownership and actual ordinary-account launch refusal
before private-data creation. Restored root-owned trees verify as an ordinary
account. Descriptor checks include a 64-level tree, a 1024-file inventory and
128 successful/refused shallow checks under a 32-descriptor limit. A separate
heap probe measures 128 healthy and 128 refused namespace checks.

The public service/CLI probe signs and installs app/runtime/data packages. Eight
cases preserve declared payload hashes while damaging their namespace. It checks
exact repair rows, stale healthy/restored approvals, offline repair with upstream
objects removed, healthy no-op, rollback refusal/restoration, registration removal
and retained data/history. The target controller runs core assertions and this
signed public probe on AArch64 and x86_64 with retained committed kernels.

Stable administrative inputs and controlled ancestors/mount topology remain
required. Same-authority mutation after checks, ACLs, arbitrary mount replacement,
power loss and whole-service heap retention are not qualified. These checks do
not expand runtime API support or close graphical/publisher/catalog release gates.

## Recorded results, 2026-10-15

Baseline `1321756d1` accepts an undeclared runtime library in Verify and produces
no repair row. Final checks refuse it and identify the runtime for repair.
Twenty-four application/runtime/data cases bind exact repair IDs, preserve
existing/outside data and pass after trusted entries are restored. Ordinary
launch refuses damaged app/runtime/dependency namespaces before private-data
creation or execution; restored administrator-owned trees verify as an ordinary
account. Both root guests also refuse foreign package/directory/file ownership.

All 38 host compile/run checks passed: twelve core runners, the checker heap
probe, namespace assertions and the signed public probe under clang ASan/UBSan,
signed service/CLI namespace repairs and existing signed CLI lifecycle/maintenance.
Leak detection was disabled and undefined behavior was fatal. The heap probe
retained zero checker allocations over 128 healthy and 128 refused checks.
Generated C was reviewed for stack stat records, borrowed directory names, owned
paths/queues/maps and descriptor retirement. Whole-service heap retention is not
qualified; compiler notices remain in retained logs.

The initial host attempt exposed a probe-owned temporary path allocation and an
older launch-data fixture's invalid publisher key. The final probe builds its
path before measurement, and the fixture uses an admitted key to reach its data
alias check. Initial diagnostics and guest inputs remain retained; final runs
use rebuilt inputs after these test-only corrections.

Fresh QEMU TCG runs passed on AArch64 (23.9 seconds) and x86_64 (22.9 seconds),
including all namespace/ordinary-account markers, eight signed offline repair
cases and guest shutdown within 600 seconds. Both checked a 64-level tree,
1024-file inventory and 128 successful/refused checks under 32 descriptors.
Five-artifact receipts bind each committed kernel, init, both programs and
serial output. Compiler, source, generated C and logs are pinned. Broader
publisher/catalog rollout, graphical, device and runtime gates remain open.

Evidence:

- [before regression](results/2026-10-15/installed-namespace-baseline.txt)
- [host results](results/2026-10-15/installed-namespace-host.json)
- [host summary](results/2026-10-15/installed-namespace-host.txt)
- [recovery assertions and lifecycle](results/2026-10-15/installed-namespace-core.txt)
- [sanitizers](results/2026-10-15/installed-namespace-asan.txt)
- [signed CLI](results/2026-10-15/installed-namespace-cli.txt)
- [source/artifact ledger](results/2026-10-15/installed-namespace-toolchain.json)
- [aarch64 receipt](results/2026-10-15/installed-namespace-aarch64.json)
- [aarch64 report](results/2026-10-15/installed-namespace-aarch64.txt)
- [aarch64 serial](results/2026-10-15/installed-namespace-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/installed-namespace-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/installed-namespace-x86_64.json)
- [x86_64 report](results/2026-10-15/installed-namespace-x86_64.txt)
- [x86_64 serial](results/2026-10-15/installed-namespace-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/installed-namespace-x86_64.qmp.txt)
