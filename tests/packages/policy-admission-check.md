# Policy apply size admission

`Service.apply_policy` now uses the same conservative minimum-review-size
admission as review, after strict proposal parsing and before canonical policy
validation/cloning or fingerprint allocation. A proposal whose required review
already exceeds 8 MiB returns `organization policy review exceeds metadata limit`,
including when the caller supplies a well-formed stale fingerprint. Invalid
fingerprint syntax still refuses before accessing package state. No installed
generation, configuration, proposal or object changes on refusal; the writer
lock remains usable afterwards.

The regression uses 4096 installed packages, allowed IDs, pins and licenses with
maximum-length presentation fields. Each configuration/state/proposal input fits
the existing 8 MiB limit. Apply runs before review in its fresh worker; both
must return the size diagnostic. Existing accepted 4096-row short-field cases,
exact legacy fingerprints/wire bytes, no-op and changed saves, stale reviews and
other refusal paths continue through the lifecycle suite.

The earlier x86_64 crash is now attributed to kernel mapping metadata admission,
not physical RAM exhaustion or an unexplained libc write. An isolated copy of
the pre-fix apply path reproduced exit 139 while writing the first word of a
mapping returned to musl's allocator. A signal handler released one preallocated
mapping to allow diagnostic read scratch, then read its preopened
`/proc/kernel-resources` descriptor. Its retained denial reports an owner mapping
request of 4096 bytes at 61,445,264 owner bytes against a 61,446,400-byte owner
limit. The guest had more than 800 MiB available before the operation. The
one-page budget denial occurred on lazy page population after mmap had returned.

Review's earlier preflight already avoided this allocation pattern. Applying the
same gate to apply closes that reachable path without raising kernel budgets or
changing mmap semantics. This does not establish that every possible package
workload fits a 1 GiB guest's per-process metadata allowance. Kernel investigation
builds used an isolated worktree; final qualification uses the original frozen
kernels, without diagnostic kernel changes.

Roadmap 14's production publisher enrollment, catalog migration, graphical
login/display integration and broader foreign-runtime acceptance remain open.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: fourteen core pairs, two
tracked-allocation pairs, one ASan/UBSan pair, four signed CLI/driver checks and
two guest-tool builds. Repeated service/configuration checks retain zero bytes
over 1000 cycles; full 4096-entry fixtures run once outside the allocation
tracker's live-object capacity. ASan/UBSan exercises functional 64-cycle loops.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact
hashes per architecture: AArch64 **41.7 seconds**, x86_64 **46.4 seconds**. These
deadlines qualify functionality, not performance.

- [pre-fix apply reproduction](results/2026-10-16/policy-admission-before.txt)
- [pre-fix registers and metadata denial](results/2026-10-16/policy-admission-before.serial.txt)
- [host results](results/2026-10-16/policy-admission-host.json)
- [host summary](results/2026-10-16/policy-admission-host.txt)
- [core assertions](results/2026-10-16/policy-admission-core.txt)
- [tracked allocations](results/2026-10-16/policy-admission-memory.txt)
- [sanitizers](results/2026-10-16/policy-admission-asan.txt)
- [signed CLI](results/2026-10-16/policy-admission-cli.txt)
- [source/toolchain/artifact pins](results/2026-10-16/policy-admission-toolchain.json)
- [AArch64 receipt](results/2026-10-16/policy-admission-aarch64.json), [report](results/2026-10-16/policy-admission-aarch64.txt), [serial](results/2026-10-16/policy-admission-aarch64.serial.txt), [QMP](results/2026-10-16/policy-admission-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/policy-admission-x86_64.json), [report](results/2026-10-16/policy-admission-x86_64.txt), [serial](results/2026-10-16/policy-admission-x86_64.serial.txt), [QMP](results/2026-10-16/policy-admission-x86_64.qmp.txt)
