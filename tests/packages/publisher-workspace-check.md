# Publisher workspace coordination

`pack`, legacy `publish` and `publish-release` use the same nonblocking
`.publisher/lock`. Packing holds it through object copying/verification and
manifest publication; signing commands hold it through their own publication.
Prepared-root/catalog imports use the same guarded packing path. A busy writer
refuses before changing objects, package manifests, index/signature or release
history. Ordinary return, failure and process exit close the owning descriptor;
retry never requires deleting a lock file.

Workspace admission rejects empty/NUL/over-4096-byte paths, leaf directory
aliases (with or without trailing separators), foreign-owned roots and roots writable by other
users. Ordinary/slashed roots and parent aliases are supported. Missing packing
roots are created beneath checked, controlled ancestors; existing root modes
are preserved. Object/manifest directories require ordinary owned entries.
Locks require a private owned regular file, one hard link and a named identity
matching the captured descriptor before and after acquisition. Invalid inputs
remain available for inspection rather than being removed or repaired.

Packing also walks output ancestors by directory descriptor and compares their
device/inode identity with the captured source. An output equal to or inside
that source refuses before any output parent, object or lock is created. Parent
aliases and `alias/..` retain filesystem semantics rather than lexical prefix
semantics. Similar unrelated path prefixes still work. This prevents generated
publisher objects/locks from becoming their own package inputs.

Publishers must still control source contents and physical workspace ancestors.
Cooperative locking does not freeze arbitrary same-user manual writes. The
legacy command still writes its index/signature separately and retains its
existing development-only role; complete release publication, sequence history,
consumer replay checks and license decisions keep their existing contracts.
Private `.publisher` files never enter a consumer release. No new metadata or
package format is introduced.

The [public CLI probe](publisher-workspace-check.v) holds the release lock and
tries all three writers. The baseline `pack` and `publish` ignore that lock;
`publish-release` already refuses. Fixed commands must all refuse and preserve
exact publication documents and object inventory. Releasing the lock permits
packing, index signing and release export with identical signed metadata. The
new CLI also refuses ordinary/slashed leaf aliases and nested/alias-dotdot
outputs without source/publication changes. A deterministic public fixture seed
permits comparison of baseline/final signed bytes; it is not a release credential.

The [core assertions](../../tools/packages/pkgcore/publisher_workspace_test.v)
check exclusion during the packing lock checkpoint, all three writers' refusal
and retry, interrupted packing after lock acquisition, NUL/alias/shared-root
admission, unsafe child directories, shared/replaced locks and output containment.
Sixty-four ancestor/admission/acquisition/refusal cycles run under a 32-descriptor
limit. They check descriptor retirement without claiming heap retention.

The [distribution driver](distribution-check.v) discovers those assertions and
runs the public CLI probe. A focused [guest controller](publisher-workspace-runtime-check.v)
rebuilds the core assertions and a minimal init on either architecture, then
requires the complete workspace marker and clean guest shutdown under a
300-second functional allowance. Its receipt pins kernel, init, assertions and
serial output. Each named guest case runs in a fresh process, matching the
publisher CLI's process lifetime and bounding no-collector test allocations.
All five case markers are required. Guest checks use the package APIs; CLI
checks run on the host.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/publisher-workspace-core tools/packages/pkgcore/publisher_workspace_test.v
/tmp/publisher-workspace-core
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/publisher-workspace-check tests/packages/publisher-workspace-check.v
/tmp/publisher-workspace-check /path/to/vinix-package /tmp/new-publisher-check
V=/path/to/v v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  run tests/packages/publisher-workspace-runtime-check.v --arch aarch64 \
  --kernel /build/aarch64/kernel --state-dir /tmp/publisher-arm
```

Use a new state directory and the corresponding kernel for each architecture.
The usual [hardware controller options/toolchains](../hardware-platform/README.md)
apply. These focused checks do not close broader roadmap 14 publisher enrollment,
catalog migration, graphical login or application/runtime qualification gates.

## Recorded results, 2026-10-14

Eight host regression runners passed: publisher workspace, source traversal,
release, catalog, composition, root import, distribution and index schema. The
first three passed clang ASan/UBSan with leak detection disabled and undefined
behavior fatal. The signed CLI lifecycle and public before/after probe passed;
the maintained distribution driver compiled. The ledger records 29 successful
compile/run results. An initial CLI run failed its old expectation that packing
creates no `.publisher` directory; the assertion now checks only the private
lock exists, with no release history/index. That initial failure is retained.

The previous committed CLI ignores the release lock during `pack` and legacy
`publish`; the fixed CLI refuses all three busy writers without document/object
changes and succeeds after release. Final baseline/current manifests, signed
indexes, signatures, release history and object inventories match exactly after
normal retry. New core checks cover interrupted owner exit and descriptor
retirement under a 32-descriptor limit; they do not measure retained heap.

Fresh QEMU TCG runs passed all five named cases and clean shutdown on AArch64
(19.9 seconds) and x86_64 (29.7 seconds), within the 300-second functional
allowance. Both rebuild current assertions and init against retained committed
kernels; each receipt pins four artifacts/logs. Each case uses its own process.

The initial batched guest assertions failed: AArch64 reported an allocation
panic; x86_64 exited with status 139. An instrumented AArch64 retry also failed
on a later signing call. A separate no-fork AArch64 diagnostic reproduced an
allocation panic on the fifth signing call in one process, while `/proc/meminfo`
still reported about 828,880 KiB free. Its PID 1 panic prevented clean shutdown and
the controller timed out. This does not identify the allocator failure cause.
All four failed experiments remain in the serial/QMP/report evidence and attempt
ledger. Fresh case processes qualify the CLI-style lifetime; repeated signing
in a long-lived target process remains unqualified. No kernel, allocator or
signing implementation was changed to conceal that limitation.

The subsequent [signing field-temporary qualification](signing-repeat-check.md)
tests a revised signing tuple, including the batched assertions and repeated
publication in one process. The failed experiments above retain their original
sources and results.

These checks do not close production publisher enrollment, advertised catalog
migration, graphical login/broker integration or broader application/runtime
qualification gates.

Evidence:

- [before](results/2026-10-14/publisher-workspace-before.txt)
- [after](results/2026-10-14/publisher-workspace-after.txt)
- [host checks](results/2026-10-14/publisher-workspace-host.txt)
- [individual results](results/2026-10-14/publisher-workspace-host.json)
- [signed CLI](results/2026-10-14/publisher-workspace-cli.txt)
- [initial CLI failure](results/2026-10-14/publisher-workspace-cli-first.txt)
- [sanitizers](results/2026-10-14/publisher-workspace-asan.txt)
- [AArch64 receipt](results/2026-10-14/publisher-workspace-aarch64.json)
- [AArch64 serial](results/2026-10-14/publisher-workspace-aarch64.serial.txt)
- [AArch64 QMP](results/2026-10-14/publisher-workspace-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/publisher-workspace-x86_64.json)
- [x86_64 serial](results/2026-10-14/publisher-workspace-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/publisher-workspace-x86_64.qmp.txt)
- [attempt ledger](results/2026-10-14/publisher-workspace-attempts.json)
- [compiler/source/artifact ledger](results/2026-10-14/publisher-workspace-toolchain.json)
- [aarch64-first report](results/2026-10-14/publisher-workspace-aarch64-first.txt)
- [aarch64-first serial](results/2026-10-14/publisher-workspace-aarch64-first.serial.txt)
- [aarch64-first QMP](results/2026-10-14/publisher-workspace-aarch64-first.qmp.txt)
- [x86_64-first report](results/2026-10-14/publisher-workspace-x86_64-first.txt)
- [x86_64-first serial](results/2026-10-14/publisher-workspace-x86_64-first.serial.txt)
- [x86_64-first QMP](results/2026-10-14/publisher-workspace-x86_64-first.qmp.txt)
- [aarch64-diagnostic report](results/2026-10-14/publisher-workspace-aarch64-diagnostic.txt)
- [aarch64-diagnostic serial](results/2026-10-14/publisher-workspace-aarch64-diagnostic.serial.txt)
- [aarch64-diagnostic QMP](results/2026-10-14/publisher-workspace-aarch64-diagnostic.qmp.txt)
- [aarch64-no-fork report](results/2026-10-14/publisher-workspace-aarch64-no-fork.txt)
- [aarch64-no-fork serial](results/2026-10-14/publisher-workspace-aarch64-no-fork.serial.txt)
- [aarch64-no-fork QMP](results/2026-10-14/publisher-workspace-aarch64-no-fork.qmp.txt)
