# Socket I/O ownership and per-call flags

The guest exercises the production syscall wrappers and socket family queues.
It holds duplicated descriptors while pthreads wait in `recv`, `recvmsg`,
`send`, and `sendmsg`, changes `F_SETFL` through the alias, then checks that
returning I/O preserves the change. Empty `MSG_DONTWAIT` reads on a second
alias must leave the first receive blocked and shared status flags unchanged.
Full Unix stream buffers test writer wakeup after the receiver makes room.
The writer captures the receiver event generation before releasing its lock,
so a drain before waiter attachment also cannot be missed.

SCM_RIGHTS tests cover descriptor contents and `MSG_CMSG_CLOEXEC`, closing the
sender's original descriptor before delivery, plain-read discard, truncated
control delivery, and closing a socket with rights still queued on stream,
sequence-packet, and datagram sockets. Invalid iovec pointers fail through
usercopy; a first invalid receive destination leaves the message available.
A full datagram buffer rejects repeated rights sends and releases the temporary
references acquired before that failure.

The allocation fixture warms each path, samples all 18 ARM / 14 AMD64 size
classes, resets allocation tracking, then performs 1,000 Unix datagram, Unix
multi-iovec message, and loopback UDP round trips, plus 200 successful and 200
rejected SCM_RIGHTS sends. It names live sites and enforces bounded total and
per-class growth without changing the thresholds between baseline and fix.

Build and run from an isolated worktree with the untracked kernel dependencies
linked from the main checkout. Production kernel builds use `ALLOC_TRACK=1`.
The saved artifact directory must contain `bin/vinix`; the ARM VM runner does
not need its Makefile when `VINIX_QEMU_RT_NO_BUILD=1` is set.

```sh
make -C kernel ARCH=aarch64 LIMINE_MP=1 ALLOC_TRACK=1 V=/path/to/v CC=clang
python3 tests/socket-io/check-generated.py kernel/obj/blob.c
VINIX_VM_RUNNER_ROOT=/path/to/prepared/vinix \
VINIX_AARCH64_SYSROOT=/path/to/vinix/build-aarch64-userland/sysroot \
VINIX_KERNEL_DIR=/path/to/saved-arm-kernel VINIX_QEMU_RT_NO_BUILD=1 \
python3 tests/socket-io/run.py --arch=aarch64

make -C kernel clean
make -C kernel ARCH=x86_64 ALLOC_TRACK=1 V=/path/to/v CC=clang \
  LD_X86_64=/path/to/ld.lld
python3 tests/socket-io/check-generated.py kernel/obj/blob.c
VINIX_VM_RUNNER_ROOT=/path/to/prepared/vinix \
VINIX_AMD64_KERNEL=/path/to/saved-amd64-kernel/bin/vinix \
python3 tests/socket-io/run.py --arch=amd64
```

`--baseline` permits measured heap growth and reports lost shared flag updates;
the full-buffer writer regression still requires progress, so the old kernel
can stall there. The initial baseline measurements were captured before adding
that separate writer regression. Inspect the generated C from the exact booted
kernel, because V escape and derived-array clone decisions can change when
another part of the call graph changes.

Caller-stack buffers, iovecs, headers, address lengths, and Handle views remain
valid through the synchronous family call, including waits. The real FD lookup
pin keeps the resource alive; the view contains only resource and flag fields,
never copies reference counts or locks, and is never unrefed. The temporary
PendingFdGroup record is copied synchronously through the builtin array header
into the endpoint-owned queue, transferring one descriptor-list buffer. Queue
retirement installs or drops the descriptor references and frees that buffer
exactly once. No borrowed user address or caller-stack pointer is retained.

These fixes preserve existing partial-copy semantics: a later invalid iovec,
control, or address destination can fail after a receive has consumed bytes.
Atomic rollback of receive results and descriptor delivery on a later usercopy
fault is separate work. This change also does not implement unsupported socket
families/options or general per-open-file-description flag synchronization.

Measured on the saved baseline kernel at `25781047`, with named allocation
sites and its matching generated C:

| Workload | Iterations | Baseline retained bytes | Fixed ARM / AMD64 retained bytes |
| --- | ---: | ---: | ---: |
| Unix sendto/recvfrom | 1,000 | 272,096 | 96 |
| Unix sendmsg/recvmsg | 1,000 | 336,096 | 96 |
| SCM_RIGHTS delivered | 200 | 89,696 | 96 |
| SCM_RIGHTS rejected on a full queue | 200 | not sampled | 96 |
| IPv4 loopback sendto/recvfrom | 1,000 | 272,096 | 96 |

The fixed 96 bytes are two `/proc/slabinfo` measurement descriptors; all other
size classes and large-allocation pages remain flat. Baseline lost both
concurrent receive-side F_SETFL updates; the fixed kernel loses none on either
receive path or either blocked-send path. The original full stream writer
stalls after its receiver makes room; the fixed writer and rights-bearing
writer return. The final SCM_RIGHTS result includes avoiding V's derived deep
clone of the PendingFdGroup array field, in addition to `.noslices`.

Both architectures build with allocation tracking and pass the 13-function
actual-generated-C ownership checker. `tests/kernel-allocs/run.sh` still fails
against the pre-existing allowance table: the unchanged `aba01de5` baseline
has 424 distinct sites / 159 excess groups; this patch has 416 / 158, removing
exactly the eight Socket I/O escape sites and introducing no excess group.
No allowances were increased.

The focused ARM and AMD64 guests pass all cases, including the five allocation
measurements above. The AMD64 fixture redirects stdout and stderr to
`/dev/com1`; its earlier missing serial output came from leaving them on the
graphical console, rather than a kernel startup failure.

The full ARM desktop sweep completed `ops,churn,cache,idle,apps,drag` using the
existing desktop binary and the saved, allocation-tracked kernel. Unix and
Internet socket classes remain flat or fall during ops; `/proc` reads,
directory listings, and poll also retain no bytes per operation. The 300-run
churn measurements retain 32–64 KiB per program across the entire run; this
broader residual growth is not attributed to Socket I/O. Recorded CPU use is
0.25% idle, 0.80% with apps, and 4.21% during drag.

The ARM full-core guest passes the 65,536-call socket reclamation regression,
buffer/readiness checks, and the corrected console-session fixture. It later
fails the separate POSIX SIGEV_THREAD timer callback assertion; the full core
suite therefore remains incomplete. No test thresholds or assertions were
relaxed.
