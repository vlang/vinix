# Owned installed-status observations

`Service.state()` and `Service.verify()` now return independently owned `State`
snapshots. Their reader path retires decoded configuration and its directory
string on success or refusal. A fresh state's architecture is cloned before
retiring configuration; a failed verification retires the decoded installed
state before returning its error. Returned errors remain owned by the caller.

Call `State.close()` after using one of these observations. It frees nested
metadata and resets that owner, so repeated close is harmless. This is an
ownership contract for these read results: transaction/plan results and
caller-built fixture states can borrow fields and must not be closed through
this method. It adds no fields or wire-format changes. The CLI retires status,
list and successful verification results after emitting their existing output.

Status validates stored metadata without inspecting installed payloads. Verify
holds its reader lock through every namespace, payload and launcher check and
through its completion callback; failure emits no completion. Both observations
remain independent of catalog/history availability, current publisher enrollment
and policy admission. They never initialize fresh state, activate a generation,
repair files or change retained package data.

The pre-change tracker measured 73,640 bytes retained by ten fresh state/verify
pairs, 73,800 by ten installed pairs and 242,040 by ten failed verifies, after
callers retired successful results and refusal errors. The original fixture,
production sources, executable, generated C and assertion output are retained.

The maintained fixture requires zero retained bytes for 1,000 fresh pairs,
1,000 installed pairs and 1,000 payload-verification refusals. Separate 1,000-cycle
configuration, state, registration, namespace, activation-pointer and busy-lock
refusals also require zero retained bytes, followed by successful restored reads.
Fixtures and injected damage are prepared outside the measured intervals.

Functional checks cover both metadata architectures; independent nested arrays
and fresh architecture strings; repeated close; exact stored-state bytes; returned
fields surviving replacement of config/state inputs; no fresh-store creation;
unchanged activation, cache/history and generation inventory; status skipping
integrity progress; writer exclusion throughout verification; and no successful
completion on damage. Host ASan/UBSan exercise all these lifetimes. The signed CLI
lifecycle and fresh frozen-kernel guests exercise the existing maintenance flows.

This qualifies these status/verification observations and the listed refusal
paths. Low-level `read_state` retains its existing borrowed fresh-architecture
contract. Other service operations, system-root lifetime qualification, publisher
enrollment, catalog migration, graphical login/display integration and broader
foreign-runtime acceptance remain separate roadmap-14 work.

## Recorded results, 2026-10-16

All **34 focused compile/run checks** passed: ten core and one protocol pairs, one native tracked-allocation pair and one ASan/UBSan pair, six signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact hashes each: AArch64 **50.4 seconds**, x86_64 **49.0 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/status-ownership-baseline.txt)
- [host results](results/2026-10-16/status-ownership-host.json)
- [host summary](results/2026-10-16/status-ownership-host.txt)
- [core assertions](results/2026-10-16/status-ownership-core.txt)
- [tracked public status allocations](results/2026-10-16/status-ownership-memory.txt)
- [sanitizers](results/2026-10-16/status-ownership-asan.txt)
- [signed CLI](results/2026-10-16/status-ownership-cli.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/status-ownership-toolchain.json)
- [aarch64 receipt](results/2026-10-16/status-ownership-aarch64.json)
- [aarch64 report](results/2026-10-16/status-ownership-aarch64.txt)
- [aarch64 serial](results/2026-10-16/status-ownership-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/status-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/status-ownership-x86_64.json)
- [x86_64 report](results/2026-10-16/status-ownership-x86_64.txt)
- [x86_64 serial](results/2026-10-16/status-ownership-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/status-ownership-x86_64.qmp.txt)
