# System V message queues

Vinix implements `msgget`, `msgsnd`, `msgrcv`, and `msgctl` (`IPC_SET`,
`IPC_STAT`, `IPC_RMID`) using the 64-bit Linux layouts on ARM64 and x86-64.
Queues have independent keys and IDs in each IPC namespace. Permissions use
owner/creator IDs, effective and supplementary groups, and capabilities scoped
to the user namespace that owns the IPC namespace. Creating a new user namespace
alone does not grant authority over an inherited IPC namespace or allow joining
an initial-owned namespace through a saved descriptor. When both are created
together, the new user namespace owns the new IPC namespace.

Receive supports FIFO, positive type, `MSG_EXCEPT`, lowest eligible negative
type (including `LONG_MIN`), `E2BIG`, and `MSG_NOERROR` truncation. `IPC_NOWAIT`
returns `EAGAIN` for a full sender and `ENOMSG` for a receiver without a matching
message. Blocked operations wake on capacity/message changes, fail with `EIDRM`
on removal, and return `EINTR` for a caught signal even with `SA_RESTART`.
The [Linux implementation](https://github.com/torvalds/linux/blob/v6.17/ipc/msg.c)
and [Linux syscall manual](https://man7.org/linux/man-pages/man2/msgrcv.2.html)
describe the compatibility behavior used by these tests.

Each queue defaults to 16 KiB of payload and can be configured up to 1 MiB;
raising it above 16 KiB needs `CAP_SYS_RESOURCE` in the governing user namespace.
Messages are limited to 8 KiB. There are 128 queue slots across the system and a
32 MiB logical budget for message headers and payloads, including blocked
senders and messages held by an in-progress receive copy. The allocator's size
classes can round that budget upward, to less than twice its logical size.
Zero-length messages also count toward queue capacity. Exhaustion reports
`ENOSPC` for slots and `ENOMEM` for the buffer budget. IDs are monotonically
assigned and exhaustion stops before integer wrap rather than reusing an old ID.

The registry and metadata use static storage. A send owns one allocation
containing both its message header and payload. A queued message belongs to its
queue; a receive unlinks it under the registry lock and owns it until the user
copy finishes. Removal frees only queued messages. Each copy or waiter retains
the queue slot, and a removed slot is reusable only after the final operation
has detached from the event and released that reference. All payload frees and
budget adjustments happen under the registry lock.

Each syscall pins its captured IPC namespace until completion. Namespace pointer
swaps, fork inheritance, and exit detachment coordinate through the process
table lock. Namespace destruction happens after queue locks have been released;
no queue lock is held while taking the process table lock. IPC namespace file
descriptors pin the namespace per open file description, so `dup`/fork share that
pin and closing the final handle releases it. A dead namespace cannot be revived
through an old nsfs node. Namespace structures and nsfs nodes retain their
existing permanent lifetime; this change does not claim to reclaim their
metadata. Namespace bind mounts do not yet supply an independent lifetime pin.

`MSG_COPY` returns `ENOSYS` with its required `IPC_NOWAIT` flag, matching a Linux
kernel without checkpoint/restore; invalid `MSG_COPY` flag combinations return
`EINVAL`. `IPC_INFO`, `MSG_INFO`, indexed `MSG_STAT`/`MSG_STAT_ANY`, procfs IPC
enumeration, and writable tuning sysctls remain unsupported. Existing semaphore
and shared-memory registries remain global; this queue implementation does not
claim isolation for those other System V IPC objects. User namespaces remain
Vinix's existing flat identity model, without Linux's full ancestry and ID maps.

Build each architecture in a separate worktree, with kernel dependencies linked
as described in [AGENTS.md](../../AGENTS.md), then run:

```sh
python3 tests/kernel-gaps/run.py --source tests/sysvmsg/guest.c \
  --arch aarch64 --kernel-dir kernel \
  --expect 'SYSVMSG PASS' --fail 'SYSVMSG FAIL' --timeout 240

python3 tests/kernel-gaps/run.py --source tests/sysvmsg/guest.c \
  --arch x86_64 --kernel-dir /path/to/x86-worktree/kernel \
  --expect 'SYSVMSG PASS' --fail 'SYSVMSG FAIL' --timeout 240
```

The real guest suite checks ABI layout, error paths, type selection, queue
statistics, permissions, namespace capability boundaries, blocked sender and
receiver wakeups/removal/signals, nsfs persistence, stale IDs, registry and buffer
exhaustion, and namespace destruction. It stresses concurrent IPC unshare and
queue creation/removal, and measures retained slab bytes after 10,000 queue
lifecycle cycles and 10,000 producer/consumer transfers on a one-message queue.
The latter reuses one consumer thread to avoid measuring process/thread startup
allocations as message-queue retention.

The implementation checkpoint passed the complete guest suite on both ARM64 and
x86-64. Each architecture retained 48 bytes after the 10,000 lifecycle cycles
and 48 bytes after the 10,000 producer/consumer transfers; these deltas are
consistent with fixed slab-observation overhead. The global
buffer-exhaustion test accepted 4,084 full-size messages before `ENOMEM`, then
removed every queue and verified subsequent allocation succeeds. Generated C
contains no hidden allocation in these syscall handlers or namespace pinning;
the send's one explicit owned `malloc` is its only allocation.

`tests/kernel-allocs/run.sh` remains failing against the existing allowance
file with the available pinned V compiler: ARM reports 363 sites (compiler exit
0), x86 reports 250 sites (compiler exit 1), and existing namespace/resource
allocations are among the allowance mismatches. No blanket allowance refresh
was made. This failure is separate from the successful production builds and
real guest lifetime/retention tests, and remains an integration validation issue.
