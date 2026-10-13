# Collection descriptor qualification

The stored-state preflight introduced in `b73655b66` held one lease descriptor
for each eligible obsolete generation until cleanup finished. A long update
history could exceed the process descriptor limit and prevent garbage collection
from reclaiming disk space. The V baseline harness compiles that commit's
collector against the new 128-generation / 32-descriptor assertion and records
the expected `cannot check generation lease before collection` failure.

Preflight now opens one generation directory and its ordinary lease file at a
time, tests the exclusive lease, records both device/inode identities, then
closes both descriptors. All names, retained state and eligible leases still
pass admission before the first removal. The package writer lock spans both
phases and excludes new launch admission. Each removal reopens and checks the
recorded identities, then reacquires the exclusive lease. A holder that becomes
busy after preflight is retained. Replaced directory/lease inodes and symbolic
directories refuse removal with diagnostics. The collector does not delete the
replacement tree. Normal subsequent I/O failures or external changes can still
leave partial cleanup; this does not make collection atomic.

Host assertions cover 128 obsolete generations under `RLIMIT_NOFILE=32`, active
and previous preservation, a held generation's payload surviving the first
collection and its removal after release, and unused object/partial cleanup.
Existing stored-state assertions retain their corruption, name, missing lease,
directory/FIFO lease and preflight failure checks. New assertions change an
already admitted holder's lock after preflight and replace directory/lease
inodes without freeing the originals, preventing immediate inode reuse from
weakening the test. They also exercise symbolic replacement and successful
removal after the original identities are restored. Both assertion runners pass
ASan/UBSan with leak detection disabled and undefined behavior fatal; this checks
exercised safety, rather than general decoder leak freedom.

The guest creates 128 obsolete generations in the offline deployment client,
holds generation 64's shared lease in the parent and starts a test helper child.
That child sets and rereads its 32-descriptor soft limit, then directly execs the
production `vinix-package --root ROOT gc` command. The root generation, live
payload and activation pointer survive while the unused cache sentinel disappears.
After releasing the lease, normal CLI collection retires it and payload
verification still succeeds. The required marker is
`PACKAGE COLLECTION obsolete=128 nofile=32 live-lease preserved-and-released verified-state PASS`.
The rest of the signed Linux/update/offline/state-corruption workflow also runs.

Reproduce with the pinned compiler and staged headless UI module:

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused \
  -o /tmp/distribution-check tests/packages/distribution-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 \
  VINIX_PACKAGE_TEST_UI2=/path/to/desktop-assets/modules \
  /tmp/distribution-check --direct-tests --cross
```

Run [the Linux guest controller](linux-runtime-check.v) on matching AArch64 and
x86_64 kernel/sandbox inputs with `VINIX_HWTEST_TCG=1` and a fresh directory.
The test helper and limit override are part of the guest fixture only; production
CLI options remain unchanged. Kernel/native sandbox inputs are retained; service,
init, account and session programs are freshly built.

The 2026-10-13 host driver passes 30 assertion runners, SDK context heap,
CLI/PTY/Software fixtures and both target service builds. Both new/extended
assertion runners pass ASan/UBSan. Final QEMU TCG workflows pass in 76.7 seconds
on AArch64 and 55.6 seconds on x86_64, within the 180-second deadline, with clean
guest shutdown.

[Host results](results/2026-10-13/collection-limit-host.txt) and
[compiler/source/artifact ledger](results/2026-10-13/collection-limit-toolchain.json)
retain passing markers and witnesses. Guest receipts, serial and QMP:

- [AArch64 receipt](results/2026-10-13/collection-limit-aarch64.json),
  [serial](results/2026-10-13/collection-limit-aarch64.serial.txt) and
  [QMP](results/2026-10-13/collection-limit-aarch64.qmp.txt).
- [x86_64 receipt](results/2026-10-13/collection-limit-x86_64.json),
  [serial](results/2026-10-13/collection-limit-x86_64.serial.txt) and
  [QMP](results/2026-10-13/collection-limit-x86_64.qmp.txt).

The ledger checks eleven artifact hashes per guest and clean guest shutdown.
Full logs, the expected failing baseline, generated C, binaries and sanitizer
results remain under `build/package-collection-limit-work`. Compiler notices
and generated-C warnings remain in local logs. This step adds no desktop heap/
typecheck, physical-media, power-cut, public publisher enrollment, graphical
broker or wider foreign-runtime qualification. Roadmap 14 remains open.
