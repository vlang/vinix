# POSIX message queues

mq_open, mq_unlink, mq_timedsend, mq_timedreceive, mq_notify and
mq_getsetattr were vacant (ENOSYS) on both architectures, so musl's and
glibc's `mq_*` functions, and the programs and language runtimes that use them
for IPC (Python's `posix_ipc`, Erlang and Rust crates, test suites of POSIX
conformance), failed. `kernel/mqueue/mqueue.v` implements them (AArch64
180–185, x86-64 240–245).

## Semantics

Established with an exploratory probe on Linux 6.12.51 (Alpine `virt`) and
checked by the final probe.

- A queue is a regular file (`S_IFREG`, size 80, the creator's filesystem ids,
  `mode & ~umask` with the set-id bits kept) behind its descriptors and, while
  it has a name, in its IPC namespace's registry. The registry, each
  descriptor and each call using it hold a reference; the last frees it, so an
  unlinked queue keeps working through its descriptors (link count 0).
- Names: the caller's string without the leading slash libc strips. A missing
  pointer is EFAULT, an empty name ENOENT, `.`, `..` or one containing `/`
  EACCES, one over 255 bytes ENAMETOOLONG. The attribute block is copied
  before the name (EFAULT first).
- mq_open on an existing queue: EEXIST for O_CREAT|O_EXCL, EINVAL for access
  mode 3, then the permission bits by filesystem ids (CAP_DAC_OVERRIDE, and
  CAP_DAC_READ_SEARCH for reading). Attributes are ignored. A new queue:
  ENOSPC once the namespace has 256 queues unless the caller has
  CAP_SYS_RESOURCE; maxmsg and msgsize must be positive and at most 10 and
  8192 (65536 and 16 MiB with CAP_SYS_RESOURCE), else EINVAL; the default is
  10 × 8192. The caller's real uid is charged `maxmsg × 48 + min(maxmsg,
  32768) × 48 + maxmsg × msgsize` bytes until the queue is freed, and EMFILE
  refuses a queue that takes its total past RLIMIT_MSGQUEUE, whose default is
  now Linux's 819200 bytes. Descriptors are always close-on-exec; F_GETFL
  shows the access mode and O_NONBLOCK.
- mq_timedsend: the absolute CLOCK_REALTIME timeout is validated first
  (EFAULT, EINVAL), then the priority (EINVAL from 32768; the word is an
  unsigned int), the descriptor (EBADF unless a queue open for writing), the
  length (EMSGSIZE) and the message (EFAULT). A full queue gives EAGAIN with
  O_NONBLOCK; otherwise the sender waits holding its message, which a
  receiver moves into the queue when it makes room. A handoff selects the
  waiting sender by scheduling priority, then by arrival order among ties.
- mq_timedreceive: EBADF unless open for reading, EMSGSIZE for a buffer
  shorter than msgsize, EAGAIN when empty and non-blocking. Messages come
  highest priority first, oldest first within one. A message sent while a
  receiver waits goes straight to the highest-ranked receiver, with ties in
  arrival order. The priority is written before the data. A fault in either
  copy returns EFAULT and consumes the message. Waits end with ETIMEDOUT at
  the deadline, or immediately if the deadline has passed and the call needs
  to wait. A signal without SA_RESTART gives EINTR. With SA_RESTART the call
  resumes the wait.
- poll and epoll report POLLIN|POLLRDNORM with messages queued and
  POLLOUT|POLLWRNORM while there is room, whatever the access mode. read(2)
  returns Linux's status line, `QSIZE:%-10lu NOTIFY:%-5d SIGNO:%-5d
  NOTIFY_PID:%-6d`, by file position; write(2) is EINVAL.
- mq_getsetattr: new flags other than O_NONBLOCK are EINVAL before the
  descriptor is looked at; it changes the open file's O_NONBLOCK (shared with
  F_SETFL) and reports the previous flags, maxmsg, msgsize and curmsgs with
  zeroed reserved words. A fault copying the old attributes out comes after
  the change.
- mq_notify: SIGEV_NONE, SIGEV_SIGNAL (signal 0–64) or SIGEV_THREAD, else
  EINVAL; one process may register (EBUSY otherwise); NULL unregisters the
  caller's own registration and succeeds whoever calls it. It fires, once,
  when a send makes an empty queue non-empty with no receiver waiting:
  SIGEV_SIGNAL queues the signal with SI_MESGQ, the sender's pid as the owner
  numbers it, its real uid and the registration's value; SIGEV_THREAD sends
  the 32-byte cookie read from `sigev_value` at registration, last byte 1, to
  the netlink socket named by `sigev_signo` (ENOTSOCK for a non-socket, EINVAL
  for another family), which is how musl and glibc implement it. Closing any
  of the queue's descriptors in the owner, by close, dup2, close-on-exec or
  exit, drops the registration, and a SIGEV_THREAD one is told with last byte
  2.
- mq_unlink: ENOENT, or EPERM unless the caller owns the queue, has
  filesystem uid 0 or CAP_FOWNER (the queues' sticky root directory).
- Each IPC namespace has its own names. When the namespace ends, a surviving
  mqueue directory keeps its existing names and refuses creation.

## Qualification

`tests/linux-compat/run --cases mqueue` boots `mqueuefixture` as init. It
checks names and their errors, attribute limits and RLIMIT_MSGQUEUE refusals,
descriptor flags and fstat, priority order with an unsigned-int priority word,
every send and receive error and its order, timeouts, faults losing a message,
the status text and file position, poll, a receiver handed a message (and the
notification left alone), a waiting sender's message going in first by
priority, EINTR and SA_RESTART for receivers and senders, mq_getsetattr, all
three notification kinds with SI_MESGQ sender information and both netlink
cookies, registrations dropped by close and by exit, unlink and a new queue
under the old name, and as UID 1000 permissions, unprivileged limits, exact
RLIMIT_MSGQUEUE accounting held until a queue is freed, 256 queues then
ENOSPC, and IPC namespace separation. `syscall-reference.v --case mqueue`
boots the same ELF on Linux 6.12.51; it passed there unchanged.

An independent review of the first version found that a new queue was named
before its descriptor existed and was removed again when the descriptor could
not be had, so another process could open or be refused by a queue that then
vanished. mq_open now reserves the descriptor number first, as Linux does, and
the probe checks that EMFILE comes before lookup and creation and leaves no
queue behind (3 checks added). The fixture's first version passed unchanged on
Linux; the final one is the one recorded here.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 191 + 16 checks, 0 failures | `dff6553309c3e46b` | `b6169a4ee163b42a` | `1187708f90025156` |
| Linux AArch64 6.12.51 | 191 + 16 checks, 0 failures | `dff6553309c3e46b` | `c8d8cdec004d4259` | `6479ba84f09a4ec7` |
| Vinix x86-64 | 191 + 16 checks, 0 failures | `0a7349d648a460b5` | `b1d7a53d8b0713d3` | `aa7d3db9708b4046` |
| Linux x86-64 6.12.51 | 191 + 16 checks, 0 failures | `0a7349d648a460b5` | `ec9073e710b26f59` | `82a6082f3e3ef815` |

The descriptor-close hook runs on every close and the IPC namespace hook on
every namespace's end. On the first version's kernels (`mqreg-{arm,x86}-1`) the
sigqueue, fsuid, dupabi, duppublish, fcntlabi, fcntlquery, ofdlocks,
lockrange, flocksame, semns, epollkey, pipeabi, selectready, execown,
waitevent, kcmp, pidfdgetfd, open and access cases pass on AArch64, and
sigqueue, fsuid, dupabi, fcntlabi, ofdlocks, cloneipc, execown, pidfdgetfd and
open on x86-64. AArch64 cloneipc passed its functional checks there but
reported one storage retention mismatch (`big_pages=85/87`) in its cohort that
makes no namespaces; on the final AArch64 kernel it passed every cohort,
namespace teardown included, twice (`cloneipc-arm-{1,2}`).
`tests/kernel-allocs/run.sh` reports no allocation site in the new code.

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/mq-{arm,x86}-3` and `mq-{arm,x86}-linux-2`, with the
first version's runs in `mq-{arm,x86}-{1,2}` and `mq-{arm,x86}-linux-1`; the
exploratory log is `~/.cache/vinix-r15/explore/mqx-arm-1` (`fef784677c079bf7`).

### Scheduling-priority handoffs

When a sender or receiver joins the wait list, Vinix compares its scheduling
priority with the current priorities of blocked tasks. Equal priorities keep
arrival order. Changing an already queued task's priority preserves its
position. The comparison uses Vinix's effective real-time rank and ordinary
tasks' nice values. [Linux 6.12.51 waiter insertion](https://github.com/gregkh/linux/blob/v6.12.51/ipc/mqueue.c#L658)

The probe adds 30 checks for blocked senders and receivers. It lowers a task's
priority after confirming it is blocked, queues two tied tasks, and queues a
FIFO task last. The one-slot sender queue verifies that admission uses task
priority even when the first sender has the highest message priority. Each
receiver checks the byte it actually received.

Production kernels from `cd0c06b07` plus this change passed all 221 + 16
checks on both architectures. The same probe ELF passed on Linux 6.12.51 on
each architecture. The old x86-64 kernel admitted the first sender instead
of the FIFO sender. Both kernel links used `--strip-debug`. The AArch64 boot
image reused the earlier Limine loader and verified the embedded candidate
kernel and initramfs after replacing them. The allocation checker matched the
baseline's site counts and existing allow-list failures.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `09023b2f90169413` | `2605e916c4b27c05` | `8f34825a27609bc1` | `e3394fda85fc3901` |
| x86-64 | `ddcca48703dedaf3` | `62e52ad85e2b8440` | `2bffdd4c5eec7e27` | `bca0d070f9f293dd` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/mq-waiters/qualification.tar.gz`, with SHA-256
`65f1eabe78299adae2e3874aa344cb7667f1f46f963a63bb0a5b20924bb0f80e`.

### Mounted queue directory

Use `mount -t mqueue none /dev/mqueue` with an existing mount point. The
sticky directory exposes the IPC namespace selected at mount time. Listing
and pathname opens use the same queue inodes and messages as `mq_open`.
Regular files created with `O_CREAT` use the default queue attributes.
Either pathname `unlink` or `mq_unlink` removes the shared name. An open
descriptor continues to work after removal. A directory description and
an `O_PATH` description return `EBADF` from the queue syscalls.

The mount reports `MQUEUE_MAGIC` through `statfs` and carries `nodev` and
`noexec` restrictions. Mount aliases share inodes and directory permissions.
Each attachment applies its own read-only policy. [Linux mqueue filesystem](https://github.com/gregkh/linux/blob/v6.12.51/ipc/mqueue.c)

The probe adds 36 checks for pathname creation, listing and unlink, shared
queue metadata and message traffic, sticky directory and access rules,
read-only remounts, covered entries, and mounts across IPC namespace changes.
Optimized kernels from `7404d9eb8` plus this change and Linux 6.12.51 each
passed all 257 + 16 checks with the same probe ELF on both architectures.
The old x86-64 kernel failed the sticky-directory check because its mqueue
mount had tmpfs semantics. The `open` and `namespace` regressions passed on
both Vinix kernels. The allocation checker reported the same unlisted sites
as the baseline after accounting for the boot-time filesystem object and the
directory snapshot buffer freed by readdir.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `ce8eb695b272475b` | `78cc123e95fc66e5` | `769484120ffa2c3b` | `619f9b10db30e6cb` |
| x86-64 | `4012d67e17818c39` | `ddb074672114f4e3` | `6b16b2414a0a58b9` | `4122b16d0b94e875` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/mq-filesystem/qualification.tar.zst`, with SHA-256
`5f715cde39d8ddc6d61ac79d7d4e1d70d96f686d53f1b1a5c7bf6a07684d424c`.

### Mounts that outlive their IPC namespace

Existing names and messages remain accessible through a surviving mount after
the last task leaves its IPC namespace. The directory returns `EACCES` for
creation. A binding of the directory or an inherited mount namespace copy
keeps the same queue registry. A lazy detach leaves the view usable through
retained directory descriptions. When the final view goes away, Vinix removes
its names and reclaims their quota after the VFS grace period. [Linux IPC namespace teardown](https://github.com/gregkh/linux/blob/v6.12.51/ipc/namespace.c#L140)

The probe adds 12 checks. A task creates a queue and exits its private IPC
namespace. Another task copies the directory bind into a new mount namespace,
then opens the queue after the original attachment is gone and the copied
attachment has been lazily detached. The probe tests the creator's quota
before and after the retained descriptor closes. The previous x86-64 kernel
lost the queue when the creator exited.

Optimized Vinix kernels from `8d590dfd1` plus this change and Linux 6.12.51
passed all 269 + 16 checks using the same ELF on both architectures. The
`open` and `namespace` regressions passed on both Vinix kernels. The
allocation checker's site counts and existing failures matched the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `6f5f94629442ed4a` | `d55c870ff5a0325b` | `e3f45c8417207d78` | `270599146dd02c9c` |
| x86-64 | `388147104958bab1` | `85c8e14e428a2484` | `4ddc5f04cd7a2193` | `42737fbaa2f83703` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/mq-namespace-lifetime/qualification.tar.zst`, with SHA-256
`e447e04584c7c2814fd29261e9ff7d553f6b76444bb5287a23dd1b7001c8bbc6`.

### Bind mounts of individual queues

A queue file bind retains the queue and its creator's `RLIMIT_MSGQUEUE`
charge after unlink. A mount namespace copy has its own reference. An open
description remains usable after lazy detach. When the last reference is
gone, Vinix releases the backing queue, unread messages, and quota after the
VFS grace period. A queue once covered by a file bind also releases its
charge after uncover and unlink. [Linux queue eviction](https://github.com/gregkh/linux/blob/v6.12.51/ipc/mqueue.c#L488)

The probe adds 16 checks for file bind lifetime and quota. It verifies the
charge while only the bind holds the unlinked queue, then copies the mount
namespace and opens the queue there after the original bind is unmounted.
The copied mount is lazily detached. The probe checks quota and receives the
queued byte after waiting for a maintenance pass, then checks that the quota
can be reused after close. A second queue tests the mount over its name.

Optimized Vinix kernels from `7f1b43b05` plus this change and Linux 6.12.51
passed all 285 + 16 checks with the same probe ELF on each architecture.
The previous x86-64 kernel failed the copied file bind check. `open`,
`namespace` and `mount` passed on both Vinix kernels. The allocation checker
found two boot-time allocations for the shared retired resource. Its other
allow-list failures matched the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `c03f172f31e9ae6a` | `b0f4f58fb76fbaca` | `7fc4c2f2084a440a` | `68eb26d067c6ab83` |
| x86-64 | `d395211e712e891e` | `158fe726e30dde88` | `a51c6c5e4c86f192` | `e30a116c165dd9d2` |

Hashes are SHA-256 prefixes. The archive is
`~/.cache/vinix-r15/mq-file-bind-lifetime/qualification.tar.zst`, with SHA-256
`f8df1cf4828691af73b9b28ef593a7aa0f686e6602db1ea3dcacb69c95636e56`.

### Signal notifications across exec

`SIGEV_SIGNAL` registrations record the current process image. A failed
exec preserves signal delivery. After a successful exec, a registration on
a retained descriptor still owns the queue's one notification slot. The
next transition from empty to nonempty consumes that registration without
sending the old signal to the replacement program. The replacement can then
register and receive its own signal. [Linux mqueue notification](https://github.com/gregkh/linux/blob/v6.12.51/ipc/mqueue.c#L773)

The probe adds five checks for failed exec, a retained registration across
exec, and delivery from a new registration. Optimized Vinix kernels from
`1e8d2c20a` plus this change and Linux 6.12.51 passed all 290 + 16 checks with
identical probe ELFs on both architectures. The previous x86-64 kernel
delivered the stale signal. `execown`, `execnames`, `sigqueue` and `groupabi`
passed on both Vinix kernels. The first x86-64 `groupabi` run timed out after
its privileged cohort. The same kernel and ELF passed with a 300-second
timeout. The allocation checker's site counts and existing failures matched
the baseline.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `98e3b317ea30fd51` | `c049d095dd91e2bb` | `94df431736b5badc` | `03d8b7e72fe0d0f5` |
| x86-64 | `d300cd1e60ab32c2` | `a9ffb7e3def6d020` | `871a22f80e7d3d62` | `63d9eb063a4e823b` |

Hashes are SHA-256 prefixes. The archives are under
`~/.cache/vinix-r15/mq-notification-exec/`.

- `qualification.tar.zst` has SHA-256
  `c90e13cf4fddca9715e8492dae82f059e8942408d1fa101264386c253b34e97c`.
- `groupabi-replay.tar.zst` has SHA-256
  `b00c78ec2871bf3f6a0543648f5ff94abf0cf067e24aca8e41bf0901a6c54a51`.

## Limits

- Retired queue nodes keep their references through the VFS grace period.
  Historical mount records retain their vnode and name metadata. A locked
  queue-file bind with a retained redirect can keep its queue until the mount
  namespace tears down.
- A locked child mount can remain reachable through a detached parent. The
  current reaper tracks descriptors and paths to the queue attachment itself.
- The mqueue device number is shared across IPC namespaces. Nested bind
  redirects use the VFS's shared-node behavior across mount aliases.
- Ordinary priority inheritance follows Vinix's scheduler. The probe covers
  nice values, FIFO and arrival ties.
- RLIMIT_MSGQUEUE is charged per real uid across all user namespaces; Linux
  charges per user namespace up its hierarchy.
- A SIGEV_THREAD cookie that does not fit the socket's receive limit when the
  notification fires is dropped; Linux reserves room at registration.
- mq_open can still fail after making a queue if the open file's kernel budget
  runs out; the queue is then removed again.
- Creating a queue walks every live queue to count the namespace's queues and
  the user's bytes, under the queues' lock.
