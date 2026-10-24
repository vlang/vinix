# Explicit refusal of unsupported semaphore undo

The 2026-10-24 qualification covers native musl ELF64 applications on AArch64
and x86-64. Vinix previously accepted value-changing `SEM_UNDO` operations
without recording the adjustments needed to restore semaphore values when a
process exits. Applications could receive success while losing their recovery
lock. `semop` and `semtimedop` now return `EOPNOTSUPP` for any vector containing
a nonzero operation with `SEM_UNDO`.

The whole copied vector is checked for invalid semaphore indices and access
permissions before this refusal. The refusal happens before evaluating values,
committing changes or queuing a waiter. Values, per-index PIDs, timestamps and
wait counts remain unchanged. A zero operation with `SEM_UNDO` needs no exit
adjustment and retains ordinary zero-wait behavior. Unknown operation flags
retain their existing Linux-compatible handling.

The [maintained probe](../tests/linux-compat/semundofixture/core.v) uses the same
executable on Linux 6.12.51, the original Vinix kernel and the fixed production
kernel. Reference mode checks common validation plus Linux's successful undo
and restoration on child exit. Native mode checks explicit refusal and preserved
state, including mixed vectors, cancelling adjustments, all four timed/untimed
call forms, root and UID 1000, and 200 repeated refusals. A queued ordinary
waiter stays blocked after a refused undo increment and progresses after a
normal increment.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux reference mode | 71 | 0 |
| Original Vinix kernel, native mode | 71 | 12 |
| Fixed production Vinix kernel, native mode | 1,643 | 0 |

The original stops before the remaining native refusal cases after detecting
the broken exit behavior; child diagnostics account for four additional mismatch
lines. Native refusal is an explicit unsupported contract, not Linux undo
conformance. Linux executes supported undo operations rather than returning
`EOPNOTSUPP`.

The isolated candidate is
`f10922d4f97bf6e6cae03f42fd4b555a2bfa39e5`, based on
`e6b46df29a19a3ecee282313c81cc640cf5e6be2`, with only
`kernel/sysvsem/sysvsem.v` changed. Its SHA-256 is
`d89d9c5382fda87300650e5b05672cdb37d95075ff31a8583cd63c284320c40a`.
Both production builds succeed. Generated C confirms the new state is a stack
boolean and the error path releases the existing lock; the change introduces
no allocation, free or object lifetime.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `c0838e31cfe2838db1980010313df14e976b9bcba9932c9f40522ff9b0b599d2` |
| x86-64 | `6781936e92e6ef8e9c929c5e00d2f0f96290d8c236dad6a562a8066f4ed239b6` |

All 13 maintained semaphore and IPC namespace suites pass as one complete batch
on each production architecture. The evidence checker passes five positive
and rejects 23 negative controls. Its full audit verifies both builds, identical
probe ELFs, all selected inputs and outputs, and the complete regression batches.
The retained bundle is
`/Users/alex/.cache/vinix-linux-compat/semundo-20261024/evidence-final-second`;
its manifest SHA-256 is
`beba0892f8c949f9d58ff91c8172ae79fcffca815fa8f71d55cdbf9d73ff4533`.
Failed attempts and the earlier bundle are preserved. Compile the checkers
without `-prod` so their assertions remain active:

```sh
v run tests/linux-compat/semundo-reference.v --self-test
v run tests/linux-compat/semundo-evidence.v self-test
v run tests/linux-compat/semundo-evidence.v check /Users/alex/.cache/vinix-linux-compat/semundo-20261024/evidence-final-second
```

Full exit-time undo, shared undo lists through `CLONE_SYSVSEM`, unshare/exit
ownership, and clearing adjustments through SETVAL/SETALL remain unsupported.
This qualification does not establish GNU libc, ELF32, translated application,
packaging, sandbox or desktop application compatibility. The broader roadmap
gates remain open. The reference implementation is retained from
[Linux v6.12 ipc/sem.c](https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c).
