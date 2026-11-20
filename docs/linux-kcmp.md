# kcmp(2)

kcmp was vacant on both native architectures and returned ENOSYS. Mesa's DRM
winsys calls `kcmp(pid, pid, KCMP_FILE, fd1, fd2)` to learn whether two
descriptors share one open-file description, and checkpoint/restore tools
compare the other objects. `kernel/userland/kcmp.v` implements all eight types
on AArch64 (272) and x86-64 (312).

## Semantics

- Lookup: `pid1`/`pid2` are any thread ids in the caller's pid namespace,
  decoded from the low 32 register bits, as are `type` and the `KCMP_FILE`
  descriptor words. A missing task is ESRCH.
- Permission: both tasks must pass ptrace's `PTRACE_MODE_READ_REALCREDS`
  check (`proc.may_inspect_realcreds_locked`), otherwise EPERM. ESRCH precedes
  EPERM, which precedes EINVAL for an unknown type.
- Result: 0 when both share the object; otherwise 1 or 2 by an order that mixes
  the object's address with two random words per type, as Linux does. The
  order is stable and total but reveals no kernel address.
- `KCMP_FILE` compares the `Handle` (open-file description) behind each
  descriptor; a closed descriptor is EBADF.
- `KCMP_VM` compares page maps, so a `CLONE_VM` child matches its parent.
- `KCMP_FILES` and `KCMP_SIGHAND` compare processes: clone shares the
  descriptor table and handlers only between threads.
- `KCMP_FS` compares the thread's own view after `unshare(CLONE_FS)`, and the
  process otherwise.
- `KCMP_IO` compares the per-thread I/O contexts `ioprio_set` and inheritance
  create (see [ioprio](linux-ioprio.md)); tasks without one compare equal, as
  on Linux.
- `KCMP_SYSVSEM`: Linux allocates a process's semaphore undo list when it
  first creates a `CLONE_SYSVSEM` thread (both libcs' `pthread_create` pass
  it), and drops it on `unshare(CLONE_SYSVSEM)`. `Process.sysvsem_undo`
  records the same, so a threaded process differs from a fresh fork child and
  matches it again after unsharing. Vinix still refuses `SEM_UNDO` itself.
- `KCMP_EPOLL_TFD` reads the 12-byte `kcmp_epoll_slot` first (EFAULT), then
  resolves `idx1` and the epoll descriptor (EBADF), then the `toff`-th
  registration of `tfd` (EINVAL for a non-epoll descriptor, ENOENT when
  absent). Registrations of one number are counted in the order they were
  added, in one pass; Linux walks its tree by description address. Either way
  each registration has exactly one offset.

Pids are resolved under the process table lock on every pass. Another
process's descriptor table is read under that lock with its descriptor lock
only tried, as procfs does, so the reaper cannot free the array; the
description address is read before the descriptor lock is released. The epoll
set is held by reference while its registrations are scanned. An independent
lifetime review found a stale descriptor read, a quadratic epoll scan under
the set's spinlock and pids resolved only once; all three were fixed before
commit. The generated C of every new function was checked: none allocates.

## Qualification

`tests/linux-compat/run --cases kcmp` boots `kcmpfixture` as init. It checks
self, dup/`F_DUPFD_CLOEXEC`, reopened and pipe descriptions with antisymmetry
and transitivity; upper register words; EBADF/ESRCH/EINVAL and their order;
every type for a thread (before and after its `unshare(CLONE_FS)`), a fork
child (inherited and new descriptions), and a reaped child; epoll targets,
duplicates, offsets, non-sets, closed descriptors, the slot fault, and a
number re-registered after `dup2` replaced its description; and, in UID 1000
children with `PR_SET_DUMPABLE`, self/sibling access and EPERM against root.

`tests/linux-compat/syscall-reference.v --case kcmp` boots the unchanged probe
ELF under Linux 6.12.51 (Alpine `virt`) and requires the same verdicts.
The first Linux run found the `KCMP_SYSVSEM` undo-list rule above; the
kernel and probe were corrected and both runs repeated.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 66 + 8 child checks, 0 failures | `3ace371bfd6750d2` | `220c042d4a3350bc` | `aaaaf1705683b9c0` |
| Linux AArch64 6.12.51 | 66 + 8 child checks, 0 failures | `3ace371bfd6750d2` | `c8d8cdec004d4259` | `6fcbb75de80cfec2` |
| Vinix x86-64 | 66 + 8 child checks, 0 failures | `7e3a93b1111edc3c` | `17dc782925145c3c` | `25168456f6d2e5e7` |
| Linux x86-64 6.12.51 | 66 + 8 child checks, 0 failures | `7e3a93b1111edc3c` | `ec9073e710b26f59` | `48df93438a8934ee` |

Hashes are SHA-256 prefixes. The bundles are kept outside Git in
`~/.cache/vinix-r15/runs/kcmp-{arm,x86}-1` and `kcmp-{arm,x86}-linux-1`.

When ioprio gave threads I/O contexts, the unchanged probe was run again with
the ioprio kernels and passed 66 + 8 checks on both architectures (serial logs
`1a5ad269d6905dc5` in `kcmp2-arm-1`, `c3aa71d5e901655d` in `ioprio-x86-1/kcmp`).

## Limits

- A zombie that has not been reaped is ESRCH; Linux still finds it and
  reports EBADF for its descriptors.
- `CLONE_SYSVSEM` between processes and per-thread undo lists after a
  multithreaded `unshare(CLONE_SYSVSEM)` are not modelled.
- `CLONE_IO` is not modelled: such a child gets its own context.
- pledge has no promise for kcmp, so a pledged process cannot call it.
