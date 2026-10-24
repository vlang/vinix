# Native semaphore IPC namespaces

The 2026-10-24 qualification covers native musl ELF64 applications on AArch64
and x86-64. System V semaphore keys, IDs, enumeration indices and usage are now
scoped to the caller's IPC namespace. Leaving the last namespace reference
removes its semaphore sets. A syscall retains its namespace until it has
finished using the sets, including across user copies and blocked operations.

The [maintained probe](../tests/linux-compat/semnsfixture/core.v) runs the same
executable on Linux 6.12.51, the original Vinix kernel and the fixed production
kernel. Linux skips only the Vinix-specific slab storage assertion.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux reference | 445 | 0 |
| Original Vinix kernel | 446 | 36 |
| Fixed production Vinix kernel | 446 | 0 |

Fork inherits semaphore visibility. `unshare(CLONE_NEWIPC)` starts with empty
usage and enumeration; foreign IDs return `EINVAL`, absent keys return
`ENOENT`, and an exclusive create may reuse a key from another namespace.
Tests cover read controls, `semop`, `semtimedop`, `SEM_STAT_ANY`, nested
unshare, inherited value changes and `setns` restoration. An open namespace
descriptor retains sets after their creator exits and is reaped. Closing the
descriptor while a process remains a member preserves them; leaving the last
member then destroys them without changing the original namespace's sets.

Two teardown cycles each create 200 arrays of 32 semaphores in a namespace
retained only by its descriptor. After warming capacity, the measured cycle
shows 200 additional objects in each of the 384- and 512-byte slab classes
while the arrays exist. Both classes return to their starting counts after
the final descriptor closes. Every measured slab class stays flat or falls,
the written-after-free counter stays unchanged, and big-heap pages stay at
71 on AArch64 and 169 on x86-64. The original kernels retain those 200 objects
in both classes and fail the storage assertion.

The maintained runner also exercises `cloneipc`, `procns`, `semwait`,
`seminfo`, `semmeta`, `semperm`, `semrange`, `semarray`, `sempid`, `semword`
and `semabi` on the same fixed kernels. All 12 suites pass on both architectures.
The first x86 batch timed out in `procns` and `semwait`; each passes separately
with the same kernel and a longer deadline. An interrupted ARM batch is retained;
its complete retry passes all 12 suites. Selected results are bound to their
original receipts, commands, source inputs and kernel hashes.
The Linux parser passes two positive and nine negative controls; the evidence
checker rejects 38 negative serial, storage, cohort, architecture and provenance
controls.

The same AArch64 production kernel passes 36 operation measurements of 200
iterations each with zero retained bytes per operation, and four program churn
measurements of 300 launches each with zero retained bytes. The first churn
measurement frees four 384-byte objects, four 512-byte objects and one 2,048-byte
object; other churn slab deltas are zero. The strict performance auditor rejects
these reductions because it requires exactly zero slab deltas, so its overall
status remains failed. No measured class grows.
Writing 32 MiB for the cache scenario retains 20 MiB, including 16 MiB of cached
data, within the declared 64 MiB bound. Desktop idle, apps and drag scenarios
complete with process inventories, matching raw/JSON results and screenshots.
Interrupted performance attempts and two desktop logs with interleaved readiness
records remain in the bundle; those logs fail the strict raw-result audit.

The allocation-site check reports the same historical allowlist failures on
the original and candidate sources: 392 sites on AArch64 and 281 on x86-64,
with no added allocation sites. Both compiler invocations succeed. No allowlist
entries were added to conceal the existing failures.

The isolated build candidate is
`b30fa5233f3a1d8c8673e8d31f3889cedf769a35`, based on
`11fb7f395f04ac7f56aab7b97c3b6226f18413fa`, with only
`kernel/sysvsem/sysvsem.v` and `kernel/syscall/table/sysv_message.v` changed.
Their SHA-256 values are respectively
`b7f1c1c6bb8926ac79804a3e263428778872df96d6d7e85851deb71fb8729fe0` and
`7c06d49862ece2b1b36bc6b600fad71038eca405939b5c1089b98a2ed2dac436`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `f83997ba01b6688b7dedfafae07f6d11f570bb986299e88e021d56d6f5c0d3f4` |
| x86-64 | `a3899ad1ac5eb77a1e74cc4036b7d513e8b1ce4533cfe94cd89541f76d2c1161` |

An independent source and generated-C lifetime review passed for both builds:
identity snapshots stay on the stack, namespace pins are balanced and released
after the set lock, and removed sets survive until their last waiter exits.
The combined IPC release hook preserves message-queue teardown. Measured
storage results above separately check the namespace destruction path.

The complete external bundle is retained at
`/Users/alex/.cache/vinix-linux-compat/semns-20261024/evidence-final`.
Its manifest SHA-256 is
`e886287493e0e5ed02bcabd094b24757f40e7f9c2cd3d29d92f3158d7c761372`.
It preserves sources, executables, generated C, boot media, build inputs,
receipts, failed attempts and logs.
Audit it with the recorded V compiler and module dependencies:

```sh
v run tests/linux-compat/semns-reference.v --self-test
v run tests/linux-compat/semns-evidence.v --self-test
v run tests/linux-compat/semns-evidence.v check /Users/alex/.cache/vinix-linux-compat/semns-20261024/evidence-final
```

This is a privileged native ELF64 qualification using the existing process
namespace model. It does not qualify namespace changes racing blocked semaphore
calls or credential updates, complete user-namespace ID mapping, independent
filesystem IDs, `SEM_UNDO`, GNU libc, ELF32 or translated applications. The
native limits remain 4,096 sets per namespace, 32 semaphores per set, 32
operations per vector and value 32,767. The broader libc, packaging and foreign
architecture roadmap gates remain open.

The reference implementation is retained from
[Linux v6.12 ipc/sem.c](https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c)
and [ipc/util.c](https://github.com/torvalds/linux/blob/v6.12/ipc/util.c).
