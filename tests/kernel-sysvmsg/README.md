# Linux SysV message queue regression guest

The kernel implements `msgget`, `msgsnd`, `msgrcv` and `msgctl` on both Linux
64-bit syscall tables. Queues have generation-tagged IDs and namespace-local
keys; mode bits, supplementary groups and IPC capabilities control access.
Receive selection supports FIFO, positive types, lowest eligible negative
types, `MSG_EXCEPT`, `MSG_NOERROR` and ordinal `MSG_COPY` snapshots.

Blocking operations take a queue reference and link a stack-owned waiter under
the queue lock. Each waiter has one event, so queues do not inherit the shared
event's 64-listener limit. Removal unlinks the ID, wakes all waiters with
`EIDRM`, frees queued messages and defers queue destruction until operations
finish. Signals interrupt waits with `EINTR`, including with `SA_RESTART`.
Detached messages and copy snapshots remain owned through checked user copies.

IPC namespace descriptions, including `O_PATH`, pin their namespace once per
shared file description. `dup` and `fork` share that pin; final description
release drops it. Namespace cleanup removes its queues, and an atomic
try-reference prevents stale nsfs nodes from reviving a dead namespace.

The current fixed limits are 256 queues, 8192 bytes per message, 16384 bytes per
queue by default, a privileged queue limit of 1 MiB, and a global pool of
8 MiB including message headers and payloads, with at most 8192 message objects.
Pool reservations include blocked senders, detached receives and `MSG_COPY`
snapshots; zero-byte messages count
toward header and queue quotas. Allocation and pool exhaustion return `ENOMEM`.
Queue-limit exhaustion returns `EAGAIN` with `IPC_NOWAIT`, otherwise it waits.
The fixed global pool bounds aggregate use across IPC namespaces; its limits
are currently compile-time constants.

Build the isolated kernel with SMP enabled:

```sh
V=/path/to/v make -C /path/to/worktree/kernel ARCH=aarch64 LIMINE_MP=1 \
  CC=clang LD_AARCH64=/path/to/ld.lld AR=/path/to/llvm-ar -j4
USE_TCG=1 python3 /path/to/worktree/tests/kernel-sysvmsg/run.py \
  --repo /path/to/checkout-with-boot-dependencies \
  --kernel /path/to/worktree/kernel --smp 4 --log /tmp/sysvmsg.log
```

The runner uses the checkout's ARM Alpine sysroot, Limine and QEMU firmware,
without modifying its guest disks. Override `LLVM_BIN` and
`VINIX_AARCH64_SYSROOT` for other installations. It succeeds only after
`MSG-CHECK DONE failures=0`.

The guest checks selection and ABI metadata, ownership/group permissions,
faulting copies, byte/header quotas, producer/consumer wakeups, signal
interruption, wake/attach races, removal with 70 receivers, generation IDs,
namespace isolation, descriptor lifetime and queue cleanup. It warms the
paths, then measures two batches of 200 create/send/copy/receive/remove and
namespace open/dup/close cycles through `/proc/slabinfo`. `MSG-SLAB` reports
live-object changes; the assertion allows two objects of measurement noise
per class, while a repeated one-object-per-call leak fails by 200 objects.
Two further 200-cycle batches measure physical free memory with `MSG-MEM`,
covering maximum-size messages that exceed the largest slab class. The
physical check allows 128 KiB of background/page-cache noise per batch;
leaking one large allocation per call would retain several MiB.

The existing SysV semaphore/shared-memory implementations and namespace/nsfs
metadata reclamation are separate kernel workstreams. This change does not
extend their namespace behavior or remove persistent namespace metadata.

ABI and operation semantics were checked against the primary Linux sources:
[ipc/msg.c](https://github.com/torvalds/linux/blob/master/ipc/msg.c),
[asm-generic/msgbuf.h](https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/msgbuf.h)
and [asm-generic/ipcbuf.h](https://github.com/torvalds/linux/blob/master/include/uapi/asm-generic/ipcbuf.h).
