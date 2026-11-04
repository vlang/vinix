# Native signal masks during masked waits

x86-64 handler entry now preserves the live mask installed by a masked wait.
It adds the action mask and, unless SA_NODEFER applies, the delivered signal.
The signal frame independently saves the mask from before the wait, which
rt_sigreturn restores. AArch64 already makes this distinction.

The identical static musl ELF for each architecture runs on Linux 6.12.51 and
the production Vinix kernels. The probe covers rt_sigsuspend, ppoll, pselect6,
epoll_pwait, epoll_pwait2 and ordinary rt_sigprocmask unmasking. It queues a
thread-directed signal while blocked, then checks actual handler delivery,
the complete handler mask, ucontext's saved mask, syscall EINTR and restored
mask. SA_RESTART, SA_NODEFER, recursive delivery, explicit self-blocking in
sa_mask and zero-timeout restoration run as root and UID1000/GID2000 for
SIGUSR1 and SIGUSR2. pselect6 uses a finite deadline in this qualification.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux reference | 1,256 / 0 | 1,256 / 0 |
| Original production kernel | 1,256 / 0 | 1,256 / 160 |
| Corrected production kernel | 1,256 / 0 | 1,256 / 0 |

All eight selected maintained suites pass on each architecture: maskwait,
resethand, sigmaskcopy, altstackrestore, sigwaitorder, seccomp, runtime and jit.
Vinix AArch64 uses four virtual CPUs and 16 KiB pages; Vinix x86-64 and the
Linux references use two virtual CPUs and 4 KiB pages. The regression runner
freezes each fixture and kernel before compiling or booting.

The isolated build base is `6b84a78a8`. The retained base source archive and
candidate diff describe the build exactly. Both architectures build with
PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. Full generated-C
comparison of original and corrected x86-64 kernels finds exactly one scalar
assignment changed. There are no added allocations, frees or lifetime changes;
this is not a measured leak qualification.

The execution bundle is `/Users/alex/.cache/vinix-linux-compat/maskwait-evidence-20261104`.
Its SHA-256 inventory, original/corrected kernels, generated C, identical
reference/native probe ELFs, source archive/diff, scripts, receipts, raw serial
logs and earlier failed attempts are retained outside Git. Inventory checksum:
`f09a1c21bc0943c4587e04c83831dfc3b8f31784fb55168e9b2e037962d92ef9`.

Build and run the evidence checker with a V compiler that retains assertions
(the checker itself uses explicit errors):

```sh
v -o /external/maskwait-evidence tests/linux-compat/maskwait-evidence.v
/external/maskwait-evidence self-test
/external/maskwait-evidence check /external/restored-bundle
```

The evidence parser passes two positive and 718 negative controls; the Linux
reference parser passes two positive and 107 negative controls. The evidence
checker verifies every case and every original mismatch stage, matches probe
and kernel bytes across boots, checks all eight regression receipts and rejects
missing, extra or altered bundle files. The maintained runner accepts
`--cases maskwait`; the host compilation/build controller and reference launcher
are maintained beside the fixture.

Earlier attempts remain visible. The first probe exposed a separate EINVAL
refusal for empty pselect6 waits without a timeout on both architectures; the
final mask probe isolates that admission issue with a finite deadline. An
initial maintained attempt used the shared launcher and was terminated after
its failed probe; final runs use frozen launcher modules. Neither attempt is
counted as a passing regression run.

The subsequent [empty-select qualification](linux-empty-select-waits.md)
fixes and validates that separate untimed-wait refusal.

This does not qualify blocked-to-running wakeup races, ready-descriptor
precedence, arbitrary nested waits, signal storms, handler-modified contexts,
GNU libc or foreign/32-bit execution. Section 15's libc, installation/integration
and AArch64 translated/32-bit gates remain open.

The expected mask behavior follows Linux's
[signal_delivered implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c#L2748-L2775).
