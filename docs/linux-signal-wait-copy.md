# Native timed-wait signal-copy faults

Vinix now consumes the selected signal when rt_sigtimedwait returns EFAULT
while copying siginfo_t. It acknowledges consumed POSIX timer notifications
even on that error, allowing later periodic notifications without rearming.
This follows
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c),
which dequeues before copying to userspace.

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. They check
thread-directed and process-directed signals 10, 12, 35, 48 and 64 against low,
all-ones, unmapped, inaccessible, read-only and partially guarded output.
Each fault consumes the selected signal, preserves a blocked bystander and
the signal mask, and makes a second zero-time wait return EAGAIN. Empty waits
ignore invalid output pointers. Successful aligned, unaligned, exact page-end
and null output cases remain covered, including surrounding-byte preservation.
A periodic SIGEV_THREAD_ID timer checks that EFAULT consumes its notification
and the next period delivers SI_TIMER with its value, without rearming.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 1,488 | 0 |
| Original Vinix production kernel | 1,488 | 244 |
| Corrected Vinix production kernel | 1,488 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. The maintained suite set is sigwaitcopy, sigpending, randomsignal,
clonesignal, cloneclear, seccomp, runtime, futex and jit; all nine pass on each
architecture.

The isolated candidate is `9e74d4592be58055c47f2a31a3fa1c64b13b1d5b`, based on
`5d77bed2bca8a55d49a28dd21c0d785229517037`. Only signal.v behavior and a
posixtimer comment change:

| Source | SHA-256 |
| --- | --- |
| kernel/userland/signal.v | `11a3020998641d0e63903c0c494c32d00c8f67489eef3b24a5f296a6b4cdf98b` |
| kernel/posixtimer/posix_timer.v | `a5874e940e181b10c8e4416c2f7cb2359c619bd40f54f09c64cce921712b21ab` |
| kernel/memory/mmap/mmap.v (unchanged) | `abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f` |
| kernel/userland/exit.v (unchanged) | `2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `d69cf71d9b3b27665a675c2a8ce3b511e2913e1c5a9f5c801c980cd4c9a36971` |
| x86-64 | `2ea53ea399bd8a2e90afc3b482ddd2af1da21f363644c068e3b84a0b3a871cd5` |

Generated C review compares 394 AArch64 and 433 x86-64 userland, syscall-table
and timer function bodies. Only rt_sigtimedwait changes; its unused shared
requeue callee is eliminated. Timer metadata/acknowledgement, signal selection,
usercopy, mapping and exit bodies remain unchanged. The replacement saves
copy status in a stack bool, acknowledges consumption and returns EFAULT when
needed. It adds no allocation, release or object lifetime. This scope review
does not claim a measured allocation-leak qualification.

This qualifies native signal-wait output faults. Pending-signal selection
priority, concurrent delivery/copy races, queued payloads, GNU libc,
translated/ELF32 applications and installation, service, sandbox and portal
acceptance require separate evidence. The three broad section 15 gates remain
open.

The complete external bundle is
`/Users/alex/.cache/vinix-linux-compat/sigwaitcopy-20261025/evidence-final`.
It retains 18,371 artifacts with no omitted inputs. Its manifest SHA-256 is
`17ab70072093c7f43bd1c50386deb9bc4b0bcc3ca08a9e807da4edcabbf14ccc`.
The complete evidence audit passes, including all hashes, build inventories,
same-ELF comparisons and nine maintained suites per architecture.

The bundle retains selected build, compile, Linux, original, corrected and
maintained inputs and outputs, generated C review and diagnostic attempts.
Initial 1,472-check probes lacked the periodic timer regression. A simultaneous
x86 compile hit a directory-creation race; the fresh third compile passes.
Interrupted first maintained invocations have no result claims. Early private
C review helper attempts failed Option syntax or assumed equal function counts;
the corrected review verifies the single eliminated requeue helper explicitly.
Historical complete bundles remain required by their original checkers.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/sigwaitcopy-reference.v --self-test
v run tests/linux-compat/sigwaitcopy-evidence.v self-test
v run tests/linux-compat/sigwaitcopy-evidence.v check /Users/alex/.cache/vinix-linux-compat/sigwaitcopy-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.
