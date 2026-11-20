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
  receiver moves into the queue when it makes room.
- mq_timedreceive: EBADF unless open for reading, EMSGSIZE for a buffer
  shorter than msgsize, EAGAIN when empty and non-blocking. Messages come
  highest priority first, oldest first within one. A message sent while a
  receiver waits goes straight to the first waiting receiver. The priority is
  written before the data; a fault in either is EFAULT and the message is
  gone, as on Linux. Waits end with ETIMEDOUT at the deadline (at once for a
  past one, but only when they must wait) and are restartable: a signal
  without SA_RESTART gives EINTR, one with SA_RESTART resumes the wait.
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
- Each IPC namespace has its own names; when the namespace goes away its
  queues are unlinked.

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

## Limits

- No mqueue filesystem: `/dev/mqueue` cannot be mounted, so queues cannot be
  listed, inspected or removed through files.
- Waiting senders and receivers are served in arrival order; Linux orders them
  by scheduling priority.
- RLIMIT_MSGQUEUE is charged per real uid across all user namespaces; Linux
  charges per user namespace up its hierarchy. The queues' root directory
  counts as owned by uid 0 in every IPC namespace (Linux: by the namespace
  creator).
- A notification goes to the registered process even after it has executed a
  new program while keeping a descriptor without close-on-exec; Linux skips it.
- A SIGEV_THREAD cookie that does not fit the socket's receive limit when the
  notification fires is dropped; Linux reserves room at registration.
- mq_open can still fail after making a queue if the open file's kernel budget
  runs out; the queue is then removed again.
- Creating a queue walks every live queue to count the namespace's queues and
  the user's bytes, under the queues' lock.
