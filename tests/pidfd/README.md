# Stable process descriptors

Vinix implements `pidfd_open` (434) and `pidfd_send_signal` (424) on its native
AArch64 and x86-64 Linux syscall tables. `pidfd_open` accepts flags zero or
`PIDFD_NONBLOCK` (`O_NONBLOCK`), sets `FD_CLOEXEC`, and resolves a process-group
leader in the caller's PID namespace. Linux's signed 32-bit PID, descriptor and
signal arguments are preserved even when syscall registers zero-extend them.

A descriptor retains an immutable process identity through exit, reap and reuse
of the numeric PID. Exit publishes `POLLIN | POLLRDNORM` after all sibling
threads and the address space have been torn down; reap adds `POLLHUP`.
Read/write return `EINVAL`. Multiple opens, dup, inherited descriptors, poll and
epoll retain the same identity. Poll masks, `EPOLLET`, `EPOLLONESHOT` and rearm
keep their ordinary semantics. Poll/epoll capture event generations before a
final readiness scan so another waiter cannot consume their registration wake.
Permanent readiness lives in resource status; the Event pending count remains
consumable, allowing an already-delivered edge to sleep again.

Signal zero checks existence and authorization without delivering a signal.
In the same user namespace, real/effective sender IDs must match the target's real/saved ID, or the sender
must hold `CAP_KILL` in the target's governing user namespace. Initial-user
capabilities govern descendant namespaces under Vinix's current flat native
namespace model. `SIGCONT` also permits members of the same session. A pidfd
checks mandatory security domains before these identity, capability
and session exceptions. An inherited descriptor uses the target's current
domain on every signal, including after the target execs into another domain.
A PID namespace unable to see the target gets `EINVAL`; a reaped target gets `ESRCH`,
even after another process reuses its number. Authorization and delivery hold
the process table lock together. POSIX signal-info lock precedes that lock,
matching timer expiry and avoiding a timer/signal lock inversion.
Real delivery keeps the process thread list locked through enqueue, preventing
teardown from changing the chosen thread's process between lookup and delivery.
PTY group signals use the same timer, process-table and thread-list lock order.
Process-directed signals arriving during exec wait in a process-owned mask until
the replacement thread has inherited its mask, ignored dispositions and pending
signals. Replacement enqueue and signal publication share those locks, so a
pidfd cannot start an incompletely initialized replacement thread.
STOP/CONT state changes and opposite pending-signal cancellation also apply
during this handoff. A failure after exec replaces the page map terminates the
process with SIGKILL; an unpublished replacement thread releases its stacks and
owned state rather than returning to the discarded image.
An exiting or unreaped zombie target still passes an authorized signal probe;
ordinary delivery to it is ignored.

## Lifetime and bounds

The first open allocates one of 1024 static identity slots and an immutable,
monotonically increasing cookie. Process ownership lasts until reap. Each open
file description and epoll resource snapshot owns another reference; the open
syscall also pins its slot through descriptor installation and failure cleanup.
Signal lookup and authorization keep the Process under the table lock. Stop/
continue delivery pins a changed Process before releasing delivery locks, then
notifies its parent and releases the pin. First enqueue publishes a fully
constructed identity after fork parent bookkeeping, keeping the table lock
through its first enqueue. Clone caches the returned PID before that enqueue,
since another parent thread may reap the child as soon as it runs. Thread attachment takes
the process table before the thread list, matching atomic signal lookup and
avoiding a construction/signal lock inversion. Reap drops only process ownership,
so old descriptors and event waiters continue to use their retained slot. A
slot can be reused after its final reference and event-listener detachment.
The records and interface boxes are static; they require no heap-object free.
Identity exhaustion, including unreaped processes whose descriptors were
closed, returns `ENFILE`. The cookie counter refuses wrap instead of aliasing
an old identity. Ordinary descriptor exhaustion returns `EMFILE`.

Poll owns one pre-sized generation array until syscall cleanup; epoll owns one
per wait snapshot, freeing it after synchronous event detachment. Generated C
was checked for implicit boxing/allocation on record creation, pin, publish,
reap, unref and signal paths. The static Resource conversion is a value
assignment, and the optional 128-byte siginfo scratch stays on the stack.

## Unsupported interfaces

Non-null signal information is copied through the checked user-copy path and
returns `ENOSYS` for a valid buffer (`EFAULT` for an invalid buffer). Signal
scope flags and `PIDFD_THREAD` are rejected with `EINVAL`. Queued signal
metadata needs a real signal queue before it can be accepted.

`CLONE_PIDFD` is rejected with `EINVAL` by both `clone` and `clone3`; no child is
created and the supplied descriptor word stays unchanged. This checkpoint does
not add `waitid(P_PIDFD)`, `CLONE_PIDFD` descriptor creation, `pidfd_getfd`,
pidfd namespace ioctls, pidfs fdinfo or PIDFD_SELF pseudo-descriptors. In
particular, callers obtain a descriptor with `pidfd_open`. Nonblocking
status is stored on the open description; nonblocking `P_PIDFD` waits are
outside this checkpoint. PID/user namespaces still use Vinix's existing flat
model, without Linux's full namespace hierarchy or UID-map semantics.

## Verification

Build each architecture in a separate prepared worktree and boot the test as
PID 1 with the common standalone kernel-gap harness:

```sh
VEXE=/Users/alex/code/v/v make -C kernel -j4 CC=clang \
  V=/Users/alex/code/v/v ARCH=aarch64 PROD=true LIMINE_MP=1
python3 tests/kernel-gaps/run.py --no-network --source tests/pidfd/guest.c \
  --arch aarch64 --kernel-dir kernel --expect 'PIDFD PASS' \
  --fail 'PIDFD FAIL' --timeout 900
```

For x86-64 use `ARCH=x86_64 LD_X86_64=/opt/homebrew/bin/ld.lld` and point
`--arch x86_64 --kernel-dir` at that architecture's separate build tree. Allow
`--timeout 7200` with QEMU TCG: the four busy syscall workers exercise remote
TLB invalidation during every multithreaded fork, which runs slowly in software
emulation. The guest prints progress every 100 lifecycle rounds.

The test verifies ABI errors, unsupported clone rejection and CLOEXEC, exit versus reap, same-identity
multiple opens/dup, signal permission and namespace restrictions, ET timeouts,
ONESHOT rearm, irrelevant poll masks, and 80 exit-registration races with two
poll and two epoll waiters. It races two open/signal/poll threads against 1200
fork/exit/reap cycles, descriptor dup/close and POSIX timer create/expiry/delete.
An additional periodic timer remains armed during the race, and its blocked
signal must be pending afterward to verify actual expiry occurred.
It sends blocked `SIGUSR1` and ignored `SIGUSR2` through one retained pidfd
during 40 exec replacements, checking inherited mask/disposition and pending
signal preservation. Another test races 2000 PTY interrupt writes against 4000
pidfd sends and checks that the foreground process received its blocked signal.
PTY stress runs after every retention snapshot, because removed PTY nodes and
names use the separate VFS grace and periodic reaper. The dedicated
`tests/resource-open/test.c` regression measures their cleanup after that grace.
It exhausts all 1024 identity slots and verifies cleanup/recovery. A pre-created
runner allocates 5000 target PIDs while the observer retains 512 reaped
identities, then probes and attempts SIGKILL on every actual number collision.
The targets must still exit normally.

Allocation boots use `--no-network` to keep DHCP setup outside the measured heap.
A CPU-pinned retirement sweep and matching grace periods replace delayed corpses
on every allowed CPU before both snapshots.

Allocation measurements cover 10,000 open/dup/poll/epoll registration cycles
and three consecutive windows of 2000 timed poll/ET-epoll rounds. Every one of
the 18 ARM64 or 14 x86 classes must remain exactly flat, as must large pages
and the written-after-free counter. No class or background delta is exempt.
Allocation tracing exposed the old 32-byte ppoll scratch and 512-byte generic
read/write scratch leaks. Poll scratch now stays on the synchronous caller stack;
generic I/O buffers have explicit allocation and cleanup on every return. The
committed stack SHA-256 helper also removes the periodic reseed allocation.
Measured pipe-result and mapping-release scratch now stay on the caller stack;
the owned process thread list frees old capacity as it grows. x86 fork retains
the executable-path copy made by the shared constructor instead of overwriting
it with a second allocation.

`tests/pidfd/job_guest.c` selects a bounded integration suite through the same
runner. It covers self-stop, busy and blocked siblings, 600 STOP/CONT cycles
with blocked/ignored/default CONT, consumed wait states, cancellation during
40 exec replacements, failed exec and concurrent PTY signals. It requires
exactly flat post-grace job-control measurements and 4000 live
poll/ppoll/epoll rounds. The ordinary guest retains the full lifecycle,
exhaustion and numeric-reuse tests. Native results are recorded in
`docs/macos-xnu-implementation-status.md` with their completed checkpoints.

`tests/pidfd/mac_guest.c` verifies inherited trusted-parent denial for signal
zero, CONT and KILL despite matching IDs, CAP_KILL and session. It also checks
same-domain delivery and authorization changes when a retained target execs
into the sender's domain. Run it with the same harness and
`--source tests/pidfd/mac_guest.c --expect 'PIDFD MAC PASS' --fail 'PIDFD MAC FAIL'`.

`tests/kernel-allocs/run.sh` now copies missing project imports and rejects
incomplete compiler reports. Both architecture scans complete with V exit zero.
The matched candidate introduces no new or increased warning groups, and the
new pidfd source files produce no allocation warnings. The gate still fails
against inherited allowances; the allowance file remains unchanged.

ABI references: [Linux pidfd_open manual](https://man7.org/linux/man-pages/man2/pidfd_open.2.html),
[Linux pidfd_send_signal manual](https://man7.org/linux/man-pages/man2/pidfd_send_signal.2.html),
and [Linux v6.17 pidfs poll implementation](https://github.com/torvalds/linux/blob/v6.17/fs/pidfs.c).
