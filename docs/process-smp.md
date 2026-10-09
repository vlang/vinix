# SMP process lifecycle

Fork, exec, exit, shared-VM clone and vfork use the same ownership rules on
AArch64 and x86_64. A separate process created with `CLONE_VM` owns a reference
to the existing page map. Private mappings, changes to mappings and the program
break remain visible to both processes. Ordinary fork creates a distinct map
with copy-on-write private pages and shared aliases. Exec releases the old map
and installs a fresh one; the last owner releases its mappings and page tables.
Inspection references drain before that final destruction.

The program break belongs to the address space. A sleepable transaction
serializes break changes and fork snapshots without holding the page-map
spinlock through page-in or reclaim. Shared-VM owners divide anonymous-memory
charges, including shared aliases, rather than each charging the whole map.

`CLONE_VFORK` suspends the calling thread until the child releases its old map
through successful exec or exit. The parent holds a process pin across the wait
so another waiter cannot recycle the completion event. Ordinary signals remain
pending; fatal kill or sibling teardown can interrupt the suspended creator.
The child's map reference remains valid if the creator dies. x86_64's dedicated
vfork syscall follows these rules too.

A cloned thread stays behind a publication gate while its creator initializes
registers, TLS and TID words. Signals can become pending during this interval,
but cannot run the child. Group teardown waits for the creator to publish before
retiring that thread, preserving usercopy and page-in references. Publication
checks the process exit/exec transition under the process-table lock; a child
created during teardown publishes for kernel unwind without running userspace.

Fatal signals and `exit_group` claim process teardown before clearing the
exiting thread's TID word. That word can be musl's shared thread-list lock:
clearing it at a killed creator's clone return previously let an unlinked child
run pthread exit, dereference its null list link and claim SIGSEGV before the
original SIGKILL. The teardown owner now retires siblings before its own
robust-futex, TID and filesystem cleanup. All existing siblings receive their
unwind flag before any is woken. ARM teardown also drains the scheduler
handoff lock and waits until a permanently stopped thread is off CPU before
releasing its resources.

ARM checks pending signals after successful userspace faults as well as syscall
and interrupt returns. First-touch faults renew the scheduler quantum; without
this boundary, a quota OOM victim could continue renewing it and reach
`exit_group(77)` before its queued SIGKILL ran. The new boundary runs after
page-in releases its locks and references, copies the saved frame into the
thread's inline asynchronous context and redirects onto its kernel stack.
Same-EL kernel fault continuations retain their original return path.

Ordinary process-directed signals use an atomic pending pool on the process.
A sibling can claim a blocked signal even if it starts waiting after the send.
Private thread-directed signals remain on their target; shared claims do not
consume that thread's POSIX timer metadata. Failed siginfo writes restore the
signal to its original pool and wake eligible observers. Fork starts with an
empty shared pool; exec preserves it, including signals received during the
handoff. Existing job-control signals retain their generation protocol.

Signal descriptors consume the caller's private signals and the shared pool.
Poll and epoll invoke a borrowed readiness callback for each reader rather than
using a single descriptor status bit. Inherited descriptors work in their new
reader's process. Matching descriptors receive conservative broadcast wakes;
readiness filters unrelated pools, and cancellation checks prevent a stream of
spurious wakes from hiding teardown. The callback's interface storage stays on
the kernel stack, and mask updates retain the descriptor through their wakeup.
The 128-byte signal-info buffer also belongs to the read frame; repeated reads
previously leaked one V-promoted fixed array per record.

`ITIMER_REAL` belongs to the process. Any sibling can inspect or replace it;
the arming thread's exit and exec preserve it, fork starts without it, and
process exit removes it. Active timers use an intrusive process list rather
than a separate 32-entry table. Delivery pins the process, drops the timer lock
and uses normal process signal selection. Both architectures use the monotonic
clock in microseconds. Periodic expiry advances from the original phase and
coalesces late ordinary signals. Disarming preserves the configured interval.

Empty poll waits keep their temporary event and pointer-list storage on the
caller's kernel stack. The listener detaches before the frame unwinds; a timed
wait then disarms and frees its timer. Generated-C inspection and allocation
tracking cover V's otherwise implicit heap promotion of both temporaries.

The supported clone combinations cover ordinary fork, musl pthreads and
separate processes with shared VM, including vfork/POSIX spawn. Invalid Linux
sharing dependencies return `EINVAL`. Independent processes requesting shared
FS state, descriptors or signal handlers return `ENOTSUP`; threads requesting
independent FS/descriptors or `CLONE_VFORK` also return `ENOTSUP`. Process-scoped
ownership of these objects cannot implement those combinations yet. PIDFD clone
construction and other previously unsupported clone flags retain their existing
errors. This qualification does not claim every Linux clone combination or
hardware configuration.

See the [repeatable acceptance matrix](../tests/process-smp/README.md),
[job-control regression](../tests/kernel-job-control/README.md) and
[resource-group pressure tests](../tests/resource-groups/README.md).

## Qualification record, 2026-10-10

Both architectures were built in isolated worktrees with allocation tracking
and booted in QEMU. The process, job-control, detached-thread, resource-group
and POSIX-timer suites passed on four CPUs. Paging pressure passed with 256 MiB
of RAM on four AArch64 CPUs and two x86_64 CPUs, including encrypted disk
pageout/refault and swapoff.

| Measurement | AArch64 | x86_64 |
| --- | --- | --- |
| 400 empty poll waits and 400 process-signal/signalfd cycles | Every live slab class flat | Every live slab class flat |
| Three measured cohorts of 100 fork/exec/exit cycles | No retained physical pages or slab objects | No retained physical pages or slab objects |
| 420 detached-thread processes raced against kill/exit_group | Every slab class flat; 96 KiB physical retention in the first two batches, then four flat batches | Every slab class flat; one 4 KiB physical change, remaining batches flat |
| 40 quota OOM victims racing first-touch faults against exit | All terminated by SIGKILL | All terminated by SIGKILL |

Generated-C inspection confirmed that empty-poll storage and signalfd's
128-byte record buffer remain on the caller's stack. A second review covered
the new ownership, scheduler-quiescence, timer, signal and fault-return paths.

The AArch64 desktop performance run completed `ops,churn,cache`: poll, mmap
and thread creation retained zero bytes per operation. The broader run still
reported 208 bytes per mkdir and 48--96 KiB after each 300-program churn
scenario. These results do not establish flat retention across all kernel
paths; the controlled lifecycle measurements above use separate cohorts and
wait for retirement to settle.

The final AArch64 desktop also completed `idle,apps,drag` without a guest
failure. One three-second sample per scenario used 116.8, 276.4 and 107.4 MiB
of physical memory respectively. These short emulator runs provide desktop
regression coverage, not long-duration or hardware qualification.

The same-compiler allocation audit still exits unsuccessfully because of
inherited allowance mismatches: 170 unallowed groups compared with 172 in the
baseline. Neither architecture gained an allocation-site group; the two
removed groups are the fixed-array promotions in poll and signalfd. The
allowance file was not expanded. Broader filesystem retention and hardware
qualification remain separate work.
