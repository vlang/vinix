# Signal senders and queued signal information

Before this change every signal not sent by a POSIX timer or a fault reached
its handler, `sigtimedwait` or signalfd with `si_code` SI_USER and no sender:
`si_pid` and `si_uid` were 0. rt_sigqueueinfo and rt_tgsigqueueinfo were
vacant (ENOSYS), so musl's and glibc's `sigqueue()`, `pthread_sigqueue()` and
POSIX AIO `SIGEV_SIGNAL` notification failed, and pidfd_send_signal refused a
siginfo with ENOSYS.

## Semantics

- A pending signal can carry a `proc.SignalSource`: `si_code`, `si_pid` and
  `si_uid` as the receiving process numbers them, and `si_value`. Threads keep
  one per thread-directed signal and processes one per process-directed
  signal. It is recorded under the signal-information lock only when no
  instance was pending before the send (job control may set the bit
  earlier in the same send), and taken in the same critical section as the
  claim that delivers the signal, so a concurrent sender cannot replace it
  and a discarded signal cannot leave a stale sender for a later one.
- kill and pidfd_send_signal without a siginfo record SI_USER with the
  caller's pid and real uid; tkill and tgkill record SI_TKILL. Senders the
  receiver's pid namespace cannot see are reported as pid 0, as on Linux.
- rt_sigqueueinfo (AArch64 138, x86-64 129) and rt_tgsigqueueinfo (240, 297)
  read the 48 bytes of the caller's siginfo Linux copies, and the rest of
  its 128 when Linux does not know the layout of that signal and code, which
  must then be zero (E2BIG); they deliver its `si_code`, `si_pid`, `si_uid`
  and `si_value` as given. Linux's order: EFAULT or E2BIG, EINVAL for a
  nonpositive thread or group id (rt_tgsigqueueinfo), EPERM for a
  kernel code (zero or positive) or SI_TKILL aimed at anyone but the caller's
  own thread id, ESRCH, EINVAL for the signal number, then EPERM for the
  credentials. rt_sigqueueinfo given a thread id signals that thread's
  live process; a pid still owned by an exiting process is found in the
  process table first.
- pidfd_send_signal with a siginfo checks the pidfd's namespace first, then
  requires `si_signo` to equal the signal (EINVAL) and refuses kernel codes
  and SI_TKILL unless the calling thread is the pidfd's process leader
  (EPERM).
- Handler frames on both architectures, `rt_sigtimedwait` and signalfd
  (`ssi_pid`, `ssi_uid`, `ssi_int`, `ssi_ptr`) report it. Faults keep their
  fault codes; POSIX timers keep SI_TIMER, which a later sender replaces, as
  musl's SIGEV_THREAD shutdown requires.
- Vinix still keeps one pending instance of each signal. A standard signal
  sent while pending merges and keeps its first instance's information (none
  for a kernel-sent one), as on Linux. A
  real-time signal queued with information while one is pending is refused
  with EAGAIN, as Linux refuses one past RLIMIT_SIGPENDING, instead of being
  lost; Linux would queue it. kill of a pending real-time signal still merges.

## Qualification

`tests/linux-compat/run --cases sigqueue` boots `sigqueuefixture` as init. It
checks kill and tgkill of itself, kill and `sigqueue` from a child, payloads
delivered as given (including a kernel code to itself), SI_USER between two
UID 1000 processes, signalfd for kill and queue, rt_tgsigqueueinfo to a
waiting thread, an SA_SIGINFO handler, every error and its order for both
calls and for pidfd_send_signal, and that a second real-time signal is
delivered or refused but never lost while a standard one keeps its first
sender. `syscall-reference.v --case sigqueue` boots the same ELF on Linux
6.12.51, which takes the queued branch (45 checks) where Vinix takes the
EAGAIN branch (44).

An independent review of the first version found stale senders after
job-control stops, a claim/information race, `kernel_process` lookups for
exiting processes and Linux's 48-byte siginfo rule; all were fixed and the
runs repeated. On the final kernels the existing sigpending, sigwaitcopy,
sigwaitorder, sigmaskcopy, sigactioncopy, sigactionabi, autodisarm,
sigactionflags, resethand, maskwait, altstackhandler, clonesignal, fcntlsig,
selectempty, waitevent and pidfdwait cases and the POSIX timer guest pass
(subsets per architecture as recorded in the bundles). The POSIX timer guest
expected SI_USER from two tgkill sends; it now expects Linux's SI_TKILL.
randomsignal fails its short-request timer checks on x86-64 with or without
this change on this host, and passes on AArch64.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 44 checks, 0 failures | `c3d9bd6500f7941c` | `62b3e7456504db46` | `6c12f4455fba232d` |
| Linux AArch64 6.12.51 | 45 checks, 0 failures | `c3d9bd6500f7941c` | `c8d8cdec004d4259` | `0494be2f0f17244c` |
| Vinix x86-64 | 44 checks, 0 failures | `b370d0a01a3a8a4b` | `2feec836625ce4a2` | `04d0b48b6bb937f7` |
| Linux x86-64 6.12.51 | 45 checks, 0 failures | `b370d0a01a3a8a4b` | `ec9073e710b26f59` | `9b1b5e787a4b5fd1` |

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/sigfix-arm-1` (with the AArch64 regression cases),
`sigq-x86-2`, `sigq-{arm,x86}-linux-1`, and the first-version runs
`sigq-{arm,x86}-1` and `sigreg-{arm,x86}-1`.

## Limits

- One pending instance per signal: real-time signals are not queued.
- Kernel-generated signals (SIGPIPE, SIGCHLD, job control) still report
  SI_USER with no sender; SIGCHLD's CLD_* codes and child pid are not filled
  in for handlers.
- Only `si_code`, `si_pid`, `si_uid` and `si_value` of a queued siginfo are
  kept; the rest of its union is delivered as zero.
- A sender recorded during exec's thread handoff is dropped.
- The EAGAIN check of rt_sigqueueinfo and rt_tgsigqueueinfo is made before
  the send takes its locks, so two racing senders of one real-time signal can
  both succeed and merge; pidfd_send_signal checks under the lock.
- The mlibc frame path reports code, pid and uid but not `si_value`.
