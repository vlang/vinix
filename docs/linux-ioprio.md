# ioprio_get(2) and ioprio_set(2)

Both calls were vacant and returned ENOSYS, so `ionice` and programs that
lower their own I/O priority (backup tools, indexers, `updatedb`-style cron
jobs) failed. `kernel/proc/ioprio.v` implements them on AArch64 (30, 31) and
x86-64 (251, 252).

Linux keeps an I/O priority in a task's I/O context, which the default `none`
block scheduler ignores; only BFQ and mq-deadline act on it. Vinix's block
layer has no priority classes either, so priorities are recorded, inherited
and reported exactly as Linux does, and change no I/O ordering. That is the
behaviour of a Linux system on the `none` scheduler.

## Semantics

The rules were established by running exploratory probes on Linux 6.12.51
(Alpine `virt`) before implementing, and the final probe checks every one.

- `which`, `who` and the priority are C ints: the low 32 bits of their
  registers. A context stores 16 bits, so `0x14003` reads back as `0x4003`.
- The value is checked first: class RT needs `CAP_SYS_NICE` or
  `CAP_SYS_ADMIN` (EPERM); class NONE takes no level (EINVAL); classes above
  IDLE are EINVAL. Hint bits (3–12) are accepted for every class. Only then
  is an unknown `which` EINVAL and a missing target ESRCH.
- `ioprio_set` gives a task a context. A task may be set by a caller whose
  real or effective uid is the target's real uid, or with `CAP_SYS_NICE`.
  Unprivileged callers may set any BE or IDLE level, including BE 0.
- `IOPRIO_WHO_PROCESS` names one thread (0: the caller). `ioprio_get` returns
  the value as set, or 0 for a thread without a context.
- `IOPRIO_WHO_PGRP` (0: the caller's group) and `IOPRIO_WHO_USER` reach every
  visible thread of the group or real uid. Set stops at the first refusal.
  Get returns the lowest (best) effective value: the stored one for a context
  of class RT, BE or IDLE, otherwise `IOPRIO_PRIO_VALUE(class, (nice + 20) / 5)`
  with the class taken from the CPU policy (SCHED_IDLE: IDLE; FIFO, RR and
  DEADLINE: RT; otherwise BE).
- For `IOPRIO_WHO_USER`, who 0 means the caller's uid when getting but uid 0
  when setting, as Linux 6.12 does; an unprivileged `ioprio_set(USER, 0)` is
  EPERM.
- fork, clone and `pthread_create` copy the creator's context only when its
  class is valid (RT, BE or IDLE); exec keeps the context.
- `kcmp(KCMP_IO)` compares contexts: a thread with one differs from every
  other task, and tasks without one compare equal.

## Qualification

`tests/linux-compat/run --cases ioprio` boots `iopriofixture` as init. It
checks 22 values through set and read-back, argument words, error order,
inheritance by fork/thread/exec and `KCMP_IO`; aggregates over fresh process
groups of one or two members with nice values, contexts, hints and SCHED_FIFO
or SCHED_IDLE policies; group and user sets; and, as UID 1000, the
unprivileged limits. `tests/linux-compat/syscall-reference.v --case ioprio`
boots the same ELF on Linux 6.12.51.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 45 + 63 + 13 checks, 0 failures | `4f059d4d987241fe` | `28f1ce9a7f7d0d58` | `834edddac73d12ef` |
| Linux AArch64 6.12.51 | 45 + 63 + 13 checks, 0 failures | `4f059d4d987241fe` | `c8d8cdec004d4259` | `77b02dbafc283d99` |
| Vinix x86-64 | 45 + 63 + 13 checks, 0 failures | `721ab268dcbd1350` | `f28d45ddbee8fd33` | `23621adbf0e695c8` |
| Linux x86-64 6.12.51 | 45 + 63 + 13 checks, 0 failures | `721ab268dcbd1350` | `ec9073e710b26f59` | `269f0efa3473444c` |

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/ioprio-{arm,x86}-1` and `ioprio-{arm,x86}-linux-1`;
the three exploratory Linux logs are in `~/.cache/vinix-r15/explore`
(`131ab6d46b66687f`, `0ca8035e79882f93`, `174fef76a71ca5ac`).

## Limits

- No block-layer scheduling uses the priority.
- `CLONE_IO` is not modelled: a child gets a copy, not a shared context.
- A retired thread-group leader (its thread exited, others remain) is ESRCH;
  Linux still finds the zombie leader.
