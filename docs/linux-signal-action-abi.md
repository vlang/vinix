# Native signal-action queries and validation ordering

Vinix rt_sigaction accepts queries for SIGKILL and SIGSTOP while rejecting
changes to their dispositions. It checks the sigset size first, imports a
non-null new action next, and then validates the signal number and whether
an update is permitted. An unreadable new action therefore returns EFAULT
before an invalid signal returns EINVAL. The existing snapshot, process-wide
update and old-action output order remain unchanged. This follows
rt_sigaction and do_sigaction in
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. Ten
signal numbers include integer limits, invalid zero/negative/out-of-range
values, SIGKILL/SIGSTOP and three ordinary signals. Seven sizes, eight input
pointer classes and ten output classes exercise null, aligned/unaligned,
unmapped, protected, read-only and page-boundary records. Each combination
checks return value, errno, disposition state, writable output and guards.
The input record uses SIG_IGN, SA_RESTART|SA_SIGINFO, zero restorer and all
mask bits; ordinary queries verify SIGKILL/SIGSTOP mask stripping. No signals
are delivered by this fixture. The preceding sigactioncopy suite separately
retains action transitions, aliasing and output-fault checks.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 56,000 | 0 |
| Original Vinix production kernel | 56,000 | 908 |
| Corrected Vinix production kernel | 56,000 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references
use 4 KiB pages. Both production builds pass with unchanged before/after
source inventories. All fourteen maintained suites pass per architecture:
sigactionabi, sigactioncopy, sigmaskcopy, altstackcopy, sigwaitorder,
sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear, seccomp,
runtime, futex and jit.

Earlier AArch64 attempts reported a randomsignal failure and a host compiler output-path assertion; the third returned success. Earlier x86-64 attempts reported randomsignal failures; the third was still running when its guest directory disappeared. All prior guest-suite directories disappeared during concurrent work, with the cause unknown. Their controller logs, commands and statuses survive, including termination diagnostics for the interrupted third x86-64 attempt. No missing receipt is reconstructed. The first persistent AArch64 run also observed two timer signals in one randomsignal transfer; its complete failed artifacts are retained. A second unchanged AArch64 run and the first persistent x86-64 run retain complete artifacts for all fourteen suites on both architectures with unchanged fixtures and kernels. The intermittent failures remain unresolved; passing replays do not establish their cause.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/sigactionabi-20261025/evidence-final`
retains 18409 files with zero omitted selected inputs. Its manifest
SHA-256 is `7b22d6defd92ecf4ab44df94d75fc0c3cec80634bf0219f0fd51a2a2e9eff6cd`.
Historical complete bundles remain required by their original checkers.

The isolated candidate is `2f42584b88b29771f2206af5c48e17afb06a7bc1`, based on
`ffaff4f7f5c9be4e82c9d769f16431083e1a9b6c`. Only signal.v changes, with SHA-256
`7d1a6b0bd9a87a74cd9f6e19748d35022b3d93db89f8502fba60244cfcb07416`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `3458a488786e08fb73566492e3cff2610e47360f95b214bb2e42ccbec780cb86` |
| x86-64 | `cecdcfc1ff789a7f8b27c655a1247fcb6f822ffd52be1fb6fdad83d91cac7ac1` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only syscall_rt_sigaction changes: the validation moves
after input import and permits queries of the two immutable dispositions.
No allocation, release or new object lifetime is introduced. All other
bodies, usercopy and mapping/exit functions remain identical. No measured
allocation-leak qualification is claimed.

The first private probe-preparation helper failed to compile because an
Option was treated as a Result. Its corrected invocation passes. The failed
diagnostic and corrected V helper are retained with the frozen inputs.
Original, corrected and Linux runs use the same ELF per architecture.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/sigactionabi-reference.v --self-test
v run tests/linux-compat/sigactionabi-evidence.v self-test
v run tests/linux-compat/sigactionabi-evidence.v check /Users/alex/.cache/vinix-linux-compat/sigactionabi-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.

Handler delivery, pending-signal flushing, arbitrary flags/restorers and
asynchronous races remain unqualified. Surviving diagnostics document the
earlier intermittent randomsignal failures; a passing maintained run does
not establish their cause. GNU libc, translated/ELF32 paths and installation,
service, sandbox and portal acceptance remain separate qualifications.
Three broad section 15 gates remain open.
