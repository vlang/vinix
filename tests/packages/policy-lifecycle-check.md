# Policy review and apply ownership

Policy service review/apply now release loaded configuration, nonempty installed
state, proposal/fingerprint storage and private paths on success and refusal.
Generation-zero state borrows configuration architecture and is not freed as an
independent owner. Every returned document/review still owns independent fields.
Apply transfers its proposal only on success; failed validation or persistence
closes it before releasing configuration and the writer lock. The CLI now closes
returned review/apply models after serialization.

Fingerprint construction and review-size admission use explicitly owned growing
JSON buffers. Fingerprints preserve the exact original typed JSON and SHA-256
identity, without a newline or a new combined-input limit. Complete review output
keeps its 8 MiB limit. No-op apply still avoids a configuration rewrite.

A conservative allocation-free output preflight counts required presentation
strings and minimum JSON record overhead before canonicalizing the proposed
settings, computing diagnostics or cloning response rows. Escaping, diagnostics,
envelope/settings keys and false flags can only increase that size. It refuses
only responses already certain to exceed 8 MiB; the final encoded-size check
still handles other overflows. Valid review bytes/fingerprints remain unchanged.

The writer's directory checks and writable-configuration preflight now capture
native stat scratch on the stack. Generated C showed the frozen V platform
`os.lstat` wrapper allocating a native struct for every call without retiring it.
The helpers retain their ordinary-directory/file, owner and writable-mode checks,
and release their temporary paths/collections on rejection too. Directory
creation remains the platform `mkdir_all`; allocation measurements warm an
existing store, while fresh creation is exercised functionally.

Matched warmed five-cycle baseline probes retained 41,365 bytes for empty review,
106,865 for one installed package, 2,351,590 for 64 packages, 44,190 for fresh-state
no-op apply, 109,690 for installed no-op apply, 109,690 for stale confirmation,
97,265 for a malformed proposal, 7,625 for writer acquisition and 5,230 for
writable-configuration preflight. Callers closed returned values/errors. All nine
matched probes now retain zero bytes. The first ownership-only pass still kept
10,800 bytes over five apply calls, traced to native stat wrappers; that output
and generated C remain retained.

The expanded fixture initially measured 1,404 bytes of immutable JSON writer
field metadata published on first use. Like the matched probes, final repeat-call
tests warm each shape before measuring ownership. The initial fixture/assertion
and final fixture remain pinned; production behavior was unchanged by warming.

Native tracked tests repeat empty, one- and 64-package review/no-op apply calls
1000 times on both metadata architectures; full 4096-package results run with a
single live owner outside the tracker's 16,384-allocation table. They compare
fingerprints with the original typed writer/one-shot SHA-256, verify independent
results after source replacement, repeated close and exact lightweight-client
wire bytes. Real alternating changed applies exercise atomic persistence without
changing installed state, activation, objects, catalog or history. Permission
denial propagates through dependency cycles; license/firmware settings persist.

Refusals cover malformed configuration/state/proposals, aliases/FIFOs/oversized
proposals, stale/invalid fingerprints, unsafe configuration permissions, missing
configuration parents, unsafe object/generation directories and malformed/busy
locks. Each case restores its sources and successfully reviews/applies again.
Catalog/history FIFOs remain unopened. A maximum fixture whose individual inputs
fit 8 MiB refuses oversized combined review output before response cloning,
without modifying sources.
ASan/UBSan uses functional 64-cycle loops; maximum cases run once.

Standalone frozen-kernel guests run fresh lifecycle workers plus existing policy,
coordination and atomic-write fixtures. Clean shutdown and seven executable/log
artifact hashes are required per architecture. No kernel is rebuilt from the
shared checkout. The recorded allocation scope is repeated policy service calls
and their shared preflight/locking paths, not every package operation or platform
first-use allocation.

The first x86_64 run crashed in the maximum output-refusal fixture. Isolated
tracing located an allocator fault while cloning policy duplicate-entry map
keys during canonicalization; the guest had more than 800 MiB free and unlimited
data/address-space limits. The output was already inadmissible by its required
field sizes. The early preflight avoids those unnecessary allocations and the
same isolated fixture now refuses normally. Original full-run failure, traced
source/generated C/registers and isolated preflight results remain pinned. This
does not claim to fix the underlying frozen-kernel/allocator behavior for other
workloads.

The [apply admission follow-up](policy-admission-check.md) identifies that fault
as a per-process kernel mapping-metadata budget refusal during lazy page
population, and applies the same early size gate to policy apply. It retains
the pre-fix apply crash/denial and fresh passing results on both architectures.

Roadmap 14 remains open for production publisher enrollment, catalog migration,
graphical login/display integration and broader foreign-runtime acceptance.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: fourteen core pairs, two tracked-allocation pairs, one ASan/UBSan pair, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact hashes each: AArch64 **36.9 seconds**, x86_64 **43.6 seconds**. Deadlines qualify functionality, not performance.

- [before/after policy service probes](results/2026-10-16/policy-lifecycle-baseline.txt)
- [host results](results/2026-10-16/policy-lifecycle-host.json)
- [host summary](results/2026-10-16/policy-lifecycle-host.txt)
- [core assertions](results/2026-10-16/policy-lifecycle-core.txt)
- [tracked policy service/configuration](results/2026-10-16/policy-lifecycle-memory.txt)
- [sanitizers](results/2026-10-16/policy-lifecycle-asan.txt)
- [signed CLI](results/2026-10-16/policy-lifecycle-cli.txt)
- [initial fixture/stat observations](results/2026-10-16/policy-lifecycle-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/policy-lifecycle-toolchain.json)
- [aarch64 receipt](results/2026-10-16/policy-lifecycle-aarch64.json)
- [aarch64 report](results/2026-10-16/policy-lifecycle-aarch64.txt)
- [aarch64 serial](results/2026-10-16/policy-lifecycle-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/policy-lifecycle-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/policy-lifecycle-x86_64.json)
- [x86_64 report](results/2026-10-16/policy-lifecycle-x86_64.txt)
- [x86_64 serial](results/2026-10-16/policy-lifecycle-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/policy-lifecycle-x86_64.qmp.txt)
