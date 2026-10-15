# Explicit repair without upgrading

`repair` restores the complete installed application/dependency set using the
existing transactional cache, disk checks, staging, activation and rollback
rules. It preserves exact manifests, publisher identities and sequence records,
permissions, versions and requested roots. `plan repair`, `review repair` and
`apply FINGERPRINT repair` take no package IDs. Healthy state remains a no-op.

Each installed manifest must still match an entry in the current authenticated
cached catalog with the same repository and key, and satisfy organization policy.
Repair does not refresh or substitute a newer manifest. A withdrawn version is
refused with guidance to refresh repositories or review updates. Offline use
requires valid cached metadata and verified payload objects.

The additive format-1 review operation permits only `keep`/`update` rows with
equal installed/target versions. Software labels affected rows as repairs and
offers **Repair installed** alongside **Verify installed**, including when an
installed dependency is selected. **Review updates** and **Update all** retain
their separate update behavior. Confirmation uses the frozen review and existing
administrator transport; raw repair is excluded from that transport.

The maintained [signed service/CLI probe](repair-check.v) now includes explicit
repair while newer application, runtime and data versions are available. It
checks preservation of the entire installed record, healthy and changed-damage
stale approvals, trust/policy/source refusal, offline cache recovery, healthy
retry, withdrawal refusal, argument rejection, damaged rollback refusal and clean
uninstall with personal data preserved. The existing install/upgrade/deployment
cases remain regressions. The [target controller](repair-runtime-check.v) runs the
same probe and core assertions on both architectures using committed kernels.

The actual Software source fixture checks dependency selection, both repair and
update controls, layout bounds, exact-version review/details, duplicate/modal
isolation, frozen confirmation and administrator authorization. Its allocation
mode measures 1,000 decode/disclose/render/cancel cycles after retiring the final
status. The complete Software functional suite and existing memory modes remain
regressions. Sanitizers use ASan/UBSan with leak detection disabled; whole-service
allocation freedom and graphical guest execution are not claimed.

Public publisher enrollment, catalog/runtime release qualification and ordinary
graphical login/display integration remain open roadmap gates.


## Recorded results, 2026-10-15

All 39 host compile/run checks passed, along with the maintained Software-only
distribution driver, complete Software functional suite, all nine allocation
modes and both full desktop architecture typechecks. The repair review probe
retained zero tracked bytes over 1,000 cycles. Signed service/CLI repair and
Software functional/allocation ASan/UBSan runs passed. Fresh committed-kernel
QEMU TCG runs passed on AArch64 (27.3 seconds) and x86_64 (44.3 seconds),
including the explicit repair scenario and orderly guest shutdown.

These checks do not qualify a full ordinary-user graphical session or foreign
runtime release. Initial fixture/layout/setup attempts are retained separately.

- [host results](results/2026-10-15/explicit-repair-host.json)
- [host summary](results/2026-10-15/explicit-repair-host.txt)
- [signed service](results/2026-10-15/explicit-repair-service.txt)
- [signed CLI](results/2026-10-15/explicit-repair-cli.txt)
- [Software and maintained driver](results/2026-10-15/explicit-repair-ui.txt)
- [allocation modes](results/2026-10-15/explicit-repair-ui-memory.txt)
- [sanitizers](results/2026-10-15/explicit-repair-asan.txt)
- [initial attempts](results/2026-10-15/explicit-repair-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-15/explicit-repair-toolchain.json)
- [aarch64 receipt](results/2026-10-15/explicit-repair-aarch64.json)
- [aarch64 report](results/2026-10-15/explicit-repair-aarch64.txt)
- [aarch64 serial](results/2026-10-15/explicit-repair-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-15/explicit-repair-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-15/explicit-repair-x86_64.json)
- [x86_64 report](results/2026-10-15/explicit-repair-x86_64.txt)
- [x86_64 serial](results/2026-10-15/explicit-repair-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-15/explicit-repair-x86_64.qmp.txt)
