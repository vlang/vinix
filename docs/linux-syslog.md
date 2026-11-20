# syslog(2) and restart_syscall(2)

syslog was vacant on both architectures, so busybox `dmesg` (Alpine's, which
calls `klogctl`) and `klogd` failed with ENOSYS. `kernel/syscall/table/syslog.v`
serves it (AArch64 116, x86-64 103) from the kernel's retained output, the
256 KiB `kprint.bootlog` ring, which now counts every byte it has taken so
readers can keep positions across wraps. restart_syscall (128, 219) was
vacant too.

## Semantics

Established with an exploratory probe on Linux 6.12.51 (Alpine `virt`).

- Like that kernel, Vinix applies `dmesg_restrict`: every action, an unknown
  one included, needs `CAP_SYSLOG` or `CAP_SYS_ADMIN` in the initial user
  namespace, checked first (EPERM). `/proc/bootlog` stays readable as before.
- A record is one complete line, returned as `<6>` and the line: Vinix's
  messages have no level or timestamp. Text that has wrapped out of the ring
  starts at the first whole line.
- `SYSLOG_ACTION_SIZE_BUFFER` (10) is the ring's size. CLOSE and OPEN return 0.
- READ_ALL (3) and READ_CLEAR (4) return the newest whole records after the
  clear point that fit in `len`; nothing is copied when none fits. A NULL
  buffer or negative `len` (a C int) is EINVAL, a zero `len` returns 0, and a
  bad buffer is EFAULT once a record is copied. CLEAR (5) and READ_CLEAR move
  the clear point to the end.
- READ (2) returns as many whole unread records as fit, or the first part of
  one that does not fit when nothing else was copied, and continues inside it
  next time. It waits, interruptibly and restartably, until a whole line is
  there. SIZE_UNREAD (9) counts the bytes READ would return. CLEAR does not
  change what READ returns.
- CONSOLE_OFF/ON/LEVEL (6–8) keep Linux's level bookkeeping, with LEVEL's
  `len` limited to 1–8 (EINVAL otherwise). Vinix messages carry no level, so
  the console level filters nothing.
- restart_syscall: Vinix restarts an interrupted call by running it again, so
  no restart block is ever left; Linux then answers EINTR, and so does Vinix.

## Qualification

`tests/linux-compat/run --cases syslog` boots `syslogfixture` as init. Log
text differs between systems, so it checks the buffer size, record
structure, READ_ALL limits and errors, a partial READ and its continuation
into every remaining record, unread counts, CLEAR, console levels, the
dmesg_restrict refusal of ten actions for UID 1000, and restart_syscall.
`syscall-reference.v --case syslog` boots the same ELF on Linux 6.12.51; its
first run showed that READ copies every whole record that fits, not one per
call, and both the kernel and the probe were corrected.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 35 + 10 checks, 0 failures | `6a37d7e6982d4a87` | `4f22bfa1dec3e606` | `c0d729b39aaaa66b` |
| Linux AArch64 6.12.51 | 35 + 10 checks, 0 failures | `6a37d7e6982d4a87` | `c8d8cdec004d4259` | `67fb4778ab145592` |
| Vinix x86-64 | 35 + 10 checks, 0 failures | `5cb8e6e2ead8c879` | `b77ff434c22bb931` | `80abea8c42eb33c9` |
| Linux x86-64 6.12.51 | 35 + 10 checks, 0 failures | `5cb8e6e2ead8c879` | `ec9073e710b26f59` | `0832f8a71872e7b4` |

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/syslog-{arm,x86}-1` and `syslog-{arm,x86}-linux-1`;
the exploratory log is `~/.cache/vinix-r15/explore/syslogx-arm-1`
(`0f10020f63b06d04`).

## Limits

- No `/dev/kmsg` and no `/proc/kmsg`; util-linux `dmesg` falls back to this
  call.
- Every call copies the ring (256 KiB, freed before returning); READ polls
  for new lines every 100 ms instead of being woken by the print path, which
  must not allocate or sleep.
- Records have no timestamps, so `dmesg -T` has nothing to convert.
