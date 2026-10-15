# Dependency removal guidance

Blocked removals now identify an installed target and one requested package
that would still require it. Previously, implicit-dependency errors said only
to remove dependents, and explicit-but-required packages produced a generic
refusal. The retained baseline shows the missing requested-package identity.

The explanation walks installed dependency edges from retained requested roots.
Root IDs are sorted before a breadth-first traversal; each package is visited
once, so cycles and shared dependencies terminate without recursive calls.
Batch removal names are excluded from retained roots. The result names one
blocker, not every dependent application, and does not claim that removing only
that blocker will always suffice. A validated state has at most 4,096 packages
and roots, and 128 dependencies per package. Messages contain two validated IDs
and fixed guidance, within 512 bytes.

The removal rules and review format are unchanged. Implicit dependencies still
cannot be removed directly, even when named alongside every dependent root.
Removing all relevant requested roots continues to remove their unreachable
dependency closure. Explanations use installed state, so publisher revocation,
offline media and damaged cached catalogs/history do not hide the blocker or
prevent an otherwise permitted uninstall.

Root planning now creates only the returned array, reuses its buffer on install
growth, and borrows ID strings consistently from caller inputs. Removal planning
retires its temporary roots, license list, default permission list and refused
plan arrays. Returned plans retain their separate array storage; caller-owned
state/configuration strings remain intact. The pre-change tracked probe retained
**1,320,400 bytes over 100 root-planning cycles**. Initial extended runs saturated
the 16,384-record tracker and exited 133: generated C exposed implicit ID/license
clones and the default removal-policy permission array. The corrected fixture
retains **zero tracked bytes** over 1,000 root-planning and in-memory removal-plan
success/refusal cycles. This covers scratch ownership, not full service memory.

Host assertions cover implicit and explicit blockers, batch exclusions, shared
dependencies, cycles, input preservation, a 4,096-node chain and a dense
512-package graph. The tracked runner exercises install/remove/upgrade/deploy,
growth, invalid operations, implicit refusals and successful/refused removal
planning. ASan/UBSan run the removal and existing resolver/preference assertions,
including their tracked loops. Leak detection is disabled for sanitizers;
the explicit heap tracker measures retained bytes. The maintained V distribution
driver includes the new allocation runner.

The signed CLI fixture installs an editor with a transitive bridge and an
explicitly requested shared dependency into separate AArch64/x86_64 roots.
`plan`, `review` and `remove` identify the editor for both implicit and explicit
blocked targets while preserving activation, state, configuration, catalog,
history and generation names. It repeats after actual publisher revocation and
damage to cached catalog/history. Repository media and cached payloads are then
unavailable; reviewed editor removal retains only the requested shared package,
which can subsequently be removed. The full existing CLI lifecycle also runs.

Both fresh administrator guests require a synthetic public root-planning marker
for transitive guidance, batch rules and borrowed-state preservation, alongside
the existing resolver and authenticated administration workflows. They boot
frozen kernels; no kernel source is rebuilt. These checks do not qualify
graphical login, real application catalogs or foreign runtime APIs. Roadmap 14
remains open for the broader distribution acceptance work.

Run the allocation assertions directly with the reviewed V toolchain:

```sh
V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 /path/to/v \
  -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/removal-memory \
  tools/packages/pkgcore/removal_test.v
/tmp/removal-memory
```

## Recorded results, 2026-10-16

All **33 focused compile/run checks** passed: eleven core compile/run pairs, a native allocation pair, three sanitizer pairs and three signed CLI compile/run checks. All phases were refreshed after the ownership corrections; the maintained distribution driver also compiled.

Both fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **30.491 seconds**, x86_64 **39.037 seconds**. These are functional deadlines, not performance qualification.

- [baseline regression](results/2026-10-16/removal-guidance-baseline.txt)
- [host results](results/2026-10-16/removal-guidance-host.json)
- [host summary](results/2026-10-16/removal-guidance-host.txt)
- [core assertions](results/2026-10-16/removal-guidance-core.txt)
- [tracked allocations](results/2026-10-16/removal-guidance-memory.txt)
- [sanitizers](results/2026-10-16/removal-guidance-asan.txt)
- [signed CLI](results/2026-10-16/removal-guidance-cli.txt)
- [initial attempts](results/2026-10-16/removal-guidance-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/removal-guidance-toolchain.json)
- [aarch64 receipt](results/2026-10-16/removal-guidance-aarch64.json)
- [aarch64 report](results/2026-10-16/removal-guidance-aarch64.txt)
- [aarch64 serial](results/2026-10-16/removal-guidance-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/removal-guidance-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/removal-guidance-x86_64.json)
- [x86_64 report](results/2026-10-16/removal-guidance-x86_64.txt)
- [x86_64 serial](results/2026-10-16/removal-guidance-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/removal-guidance-x86_64.qmp.txt)
