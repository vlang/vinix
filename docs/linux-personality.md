# personality(2)

personality was vacant and returned ENOSYS on both architectures. GDB calls it
to start a program without address randomization, `setarch -R`, `linux32`
and `uname26` set it before exec, and Wine, QEMU-user and Valgrind query it.
`kernel/proc/personality.v` implements it on AArch64 (92) and x86-64 (135).

## Semantics

Established with exploratory probes on Linux 6.12.51 (Alpine `virt`) on both
architectures before implementing; the final probe checks each rule.

- The argument is an unsigned int: only the register's low 32 bits count.
  `0xffffffff` queries; any other value is stored. The result is the previous
  value.
- AArch64 refuses the 32-bit domain (`PER_LINUX32` in the low byte) with
  EINVAL, as Linux does on a CPU without AArch32 at EL0; x86-64 accepts it.
- The value belongs to the thread. New threads and fork children inherit it;
  exec keeps it except `READ_IMPLIES_EXEC`, which loading a 64-bit ELF clears.
- `ADDR_NO_RANDOMIZE` at exec gives the new program a fixed layout: PIE and
  interpreter bases, stack top, mmap base, first break and, on AArch64, the
  signal trampoline page. `Process.layout_fixed` records the decision for
  later mmap hints and the break, and fork keeps it.
- `READ_IMPLIES_EXEC` adds `PROT_EXEC` to readable mappings made by mmap
  (not for files on noexec mounts or refused by MAC policy) and mprotect
  (unless part of the range may never be executable). Vinix's W^X policy
  then judges the result, so read-write memory becomes read-write-execute only
  for processes allowed W^X exceptions.
- `UNAME26` makes uname(2) report `2.6.(60 + minor)` followed by whatever
  follows the release's version numbers, as Linux builds it: Vinix's `0.1.0`
  becomes `2.6.61`, Linux's `6.12.51-0-virt` becomes `2.6.72-0-virt`.
- On x86-64, `PER_LINUX32` makes uname(2) report the machine as `i686`.

## Qualification

`tests/linux-compat/run --cases personality` boots `personalityfixture` as
init. It checks query/set results and argument words, the 32-bit domain per
architecture, UNAME26 against an independent computation, per-thread values,
fork and exec inheritance of seven values, identical layouts across two
ADDR_NO_RANDOMIZE execs and differing stack/mmap/break across two ordinary
ones, and `/proc/self/maps` permissions under READ_IMPLIES_EXEC.
`tests/linux-compat/syscall-reference.v --case personality` boots the same
ELF on Linux 6.12.51. Existing `runtime`, `execnames`, `execown`, `mmap` and
`jit` cases also pass on the AArch64 kernel.

Source revision: the commit that adds this file. Kernels: `PROD=true`,
`LIMINE_MP=1`.

| Run | Result | Probe ELF | Kernel | Serial log |
| --- | --- | --- | --- | --- |
| Vinix AArch64 | 39 checks, 0 failures | `341364a3e47e8bb6` | `3afc225f627dd479` | `ad41ed0f323e713b` |
| Linux AArch64 6.12.51 | 39 checks, 0 failures | `341364a3e47e8bb6` | `c8d8cdec004d4259` | `c14cbc00defd1d76` |
| Vinix x86-64 | 40 checks, 0 failures | `7c7222ed65a67081` | `239f878edf92c9f7` | `7be44b5c14e4bf99` |
| Linux x86-64 6.12.51 | 40 checks, 0 failures | `7c7222ed65a67081` | `ec9073e710b26f59` | `85471ebad3d60ab0` |

Hashes are SHA-256 prefixes. Bundles are kept outside Git in
`~/.cache/vinix-r15/runs/persona-{arm,x86}-1` and `persona-{arm,x86}-linux-1`;
the exploratory Linux logs are in `~/.cache/vinix-r15/explore`
(`92960281d771b1ad`, `aed2eb72ff7b531c`).

## Limits

- `ADDR_COMPAT_LAYOUT` (Linux's legacy bottom-up mmap layout),
  `MMAP_PAGE_ZERO`, `STICKY_TIMEOUTS` and the remaining flags are stored and
  reported but change nothing.
- There is no 32-bit execution domain to switch to; `PER_LINUX32` on x86-64
  changes only what uname reports.
- Linux clears `PER_CLEAR_ON_SETID` flags when exec raises privilege; Vinix has
  no setuid exec, so that never applies.
