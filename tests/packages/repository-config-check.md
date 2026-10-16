# Repository configuration remains available for revocation

Software previously loaded configured publishers through `repo-list`, which
also authenticates cached indexes and validates replay history. Damaged
maintenance metadata could therefore hide the list needed to revoke trust.

`repo-config` now exposes a separate read-only configuration document with
explicit `scope:"configuration"`. It does not fetch or read catalog/history,
create state on fresh images, change trust or claim that repositories are usable.
It retains strict configuration parsing and package reader locking. `repo-list`
still verifies history/cache, and enrollment/update still refuse damaged data.
Software uses this scoped document, preserves its prior list on invalid replies,
and keeps reviewed, administrator-authorized mutation unchanged.

The [core assertions](../../tools/packages/pkgcore/repository_configuration_test.v)
cover fresh reads, damaged metadata, malformed configuration, reader locking,
invalid legacy curve-key visibility and reviewed revocation without metadata
reset. The [protocol assertions](../../tools/packages/pkgprotocol/repository_configuration_test.v)
check required scope, complete typed fields, duplicate/escaped fields, UTF-8,
identity validation, response bounds, full-status separation and owned cleanup.
With heap tracking, 1000 valid/partial-invalid decode/cleanup cycles retain zero
tracked bytes. This measures the typed reader, not every service allocation.

Follow-up [configuration observation checks](configuration-observation-check.md)
qualify the public repository/policy readers' result ownership and source scratch.
The maintained guest suite now runs that fixture too; the recorded results below
retain their original scope and artifact counts.

The [CLI lifecycle](distribution-cli.v) compares strict and scoped listing under
damaged cache/history, refuses enrollment/update, reviews and applies revocation,
preserves active state/objects/recovery data, and checks malformed coordination
files and active writers. The Software fixture exercises the real asynchronous
UI paths with a service fixture that refuses damaged-history enrollment but
allows reviewed revocation. Its existing metadata memory checks cover the new
configuration document. This is a headless interaction check, not graphical
session/display-broker qualification.

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.' -o /tmp/repository-config-reader \
  tools/packages/pkgprotocol/repository_configuration_test.v
/tmp/repository-config-reader
```

The [target controller](repository-config-runtime-check.v) runs core and protocol
assertions on both architectures. Production publisher enrollment, catalog
migration, graphical session integration and broader runtime/device
qualification remain roadmap 14 release gates.

## Recorded results, 2026-10-14

Eight core assertion runners passed: repository configuration, administration,
coordination, service, policy, retired publisher recovery, history schema and
snapshot schema. Configuration, existing repository and review protocol readers
passed. Core/protocol configuration assertions and the full headless Software
interaction suite passed clang ASan/UBSan (leak detection disabled; undefined
behavior fatal). The new reader measured zero retained tracked bytes over 1000
valid/partial-invalid cleanup cycles.

The real CLI compared strict/scoped listing under damaged cache/history, kept
enrollment and updates refused, completed reviewed revocation and preserved
activation, objects and recovery data. Existing lock, metadata, deployment,
mirror and lifecycle checks still passed. The full Software driver passed all
interaction checks and eight existing 1000-cycle memory modes using the staged
headless ui2 dependency. The production desktop type-checked for arm64 and
amd64. The ledger records 36 successful host compile/run/type-check results,
with the full Software-driver log retained separately.

Fresh QEMU TCG runs passed on AArch64 (8.2 seconds) and x86_64 (6.6
seconds), using retained committed kernels. Each ran core and protocol assertion
programs and shut down inside the 300-second functional allowance. Five-artifact
receipts pin kernel, init, both programs and serial log; generated C and build
logs are also recorded. These target runs check the service/protocol. Graphical
session/display-broker integration remains a separate acceptance gate.

Lifetime review: the configuration reader owns every parsed scope, architecture,
identity string and repository-array buffer, including partial failure paths.
Software replaces its previous owned document only after complete validation
and closes it on replacement/exit. The new read API never writes package state,
relaxes maintenance authentication or changes administrative authorization.

Evidence:

- [host results](results/2026-10-14/repository-config-host.json)
- [host checks](results/2026-10-14/repository-config-host.txt)
- [core assertions](results/2026-10-14/repository-config-core.txt)
- [protocol assertions](results/2026-10-14/repository-config-protocol.txt)
- [protocol allocations](results/2026-10-14/repository-config-memory.txt)
- [CLI lifecycle](results/2026-10-14/repository-config-cli.txt)
- [core/protocol sanitizers](results/2026-10-14/repository-config-asan.txt)
- [Software interactions and memory modes](results/2026-10-14/repository-config-software.txt)
- [Software sanitizers](results/2026-10-14/repository-config-software-asan.txt)
- [arm64 desktop types](results/2026-10-14/repository-config-desktop-arm64.txt)
- [amd64 desktop types](results/2026-10-14/repository-config-desktop-amd64.txt)
- [source/artifact ledger](results/2026-10-14/repository-config-toolchain.json)
- [aarch64 receipt](results/2026-10-14/repository-config-aarch64.json)
- [aarch64 report](results/2026-10-14/repository-config-aarch64.txt)
- [aarch64 serial](results/2026-10-14/repository-config-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/repository-config-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/repository-config-x86_64.json)
- [x86_64 report](results/2026-10-14/repository-config-x86_64.txt)
- [x86_64 serial](results/2026-10-14/repository-config-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/repository-config-x86_64.qmp.txt)
