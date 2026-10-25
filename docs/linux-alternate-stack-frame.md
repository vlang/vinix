# Native alternate-stack records in signal frames

Both architectures save the configured alternate-stack base, flags and size
in the signal frame ucontext uc_stack record. Enabled stacks save flags zero;
disabled stacks save SS_DISABLE, including when interrupted on an alternate
stack. A live sigaltstack query still reports SS_ONSTACK while executing there.
AArch64 previously left uc_stack zeroed, and x86-64 saved the live SS_ONSTACK
flag in nested frames. See
[Linux v6.12 signal.h](https://github.com/torvalds/linux/blob/v6.12/include/linux/signal.h)
and [kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

The static musl probe runs as root and UID 1000/GID 2000. Eight configurations
combine an enabled/disabled alternate stack with outer and inner SA_ONSTACK
flags. SIGUSR1 invokes SIGUSR2 once. Both handlers inspect the saved base,
configured flags and size, check their actual stack placement and query live
stack state. Queries after nested and outer returns check state and output
guards. The alternate stack is 65,536 bytes with inaccessible guard pages.

| Architecture and kernel | Checks | Failures |
| --- | ---: | ---: |
| AArch64 Linux 6.12.51 | 272 | 0 |
| AArch64 original Vinix production | 272 | 48 |
| AArch64 corrected Vinix production | 272 | 0 |
| x86-64 Linux 6.12.51 | 272 | 0 |
| x86-64 original Vinix production | 272 | 4 |
| x86-64 corrected Vinix production | 272 | 0 |

Native AArch64 uses 16 KiB pages; native x86-64 and both Linux references
use 4 KiB pages. Both production builds pass with identical before/after
source inventories. All 18 maintained suites pass on AArch64. On x86-64,
17 pass and randomsignal fails one of 168 unprivileged requests: an ordinary
8 MiB read returns its full request despite observing the interrupting signal.
The failing diagnostic has seen=1, frame=0 and guards=1; all other cases pass.
A subsequent replay with the identical ELF and kernel passes. Both verdicts
are retained; the cause and resolution remain unproven. The suites cover
altstackframe, altstacksp, altstackhandler, altstackabi, sigactionabi,
sigactioncopy, sigmaskcopy, altstackcopy, sigwaitorder, sigwaitcopy, sigpending,
randomsignal, clonesignal, cloneclear, seccomp, runtime, futex and jit. Earlier
intermittent randomsignal and futex failures, including the handler
qualification and its identical replay, also remain unresolved.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/altstackframe-20261025/evidence-final`
retains 18615 files with zero omitted selected inputs. Its manifest
SHA-256 is `ba9a80148f0224a8d786c4e6458076abc67fca6e435c029d62779ab592854edb`.
Historical complete bundles remain required by their original checkers.

The isolated candidate is `5b3178ace528631c0b4a60b167c9b9ecd6236860`, based on
`7406d1740951142074a2f58447edbb53048aea01`. The changed source SHA-256 values are:

| Source | SHA-256 |
| --- | --- |
| linux_signal_amd64.v | `b37cd3d65ac33d6391178f0563e95617331cc328cb627271cead803bf9ec5c36` |
| userland_arm64.v | `1f4259c8a6952bff743550a69975054005d38f6b188fc7f5b222402328f7f267` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `c3f6c8aef18cc9409d79d1a5fbb783e599cac0ebfbe6db9738f25d5783b3308f` |
| x86-64 | `82059f5ca537dcc049e443bc369c3183ec305b34392451e4b8b4e2a26147e0ce` |

Generated C review compares the complete before/after files and 395 AArch64
and 434 x86-64 userland, syscall-table and timer bodies. AArch64 adds three
scalar uc_stack writes; x86-64 removes live-stack flag calculation from the
frame helper and its call. Only one AArch64 and two x86-64 function bodies
change. No allocation, release or object lifetime changes. No allocation-leak
qualification is claimed.

Original, corrected and Linux runs use the same ELF per architecture. The
first private source-preparation helper had a wrong search anchor and was
corrected before running. Original-run attempts with an incorrect kernel
root failed before boot; the corrected second attempts are retained and
selected. The first generated C review helper rejected an extra newline in
its expected x86 transformation; the corrected exact-file comparison passes.
The first replay attempt exceeded the QMP socket path limit before boot.
Host disk exhaustion interrupted the first AArch64 maintained batch after
13 recorded passes and a second replay attempt before serial capture. Their
remaining guest verdicts are unknown; incomplete attempts are preserved. An
AArch64 retry stopped before boot because its compiler wrapper still required
the earlier output path. The corrected third batch is selected. Checksum-
verified consolidation preserves identical artifact bytes and original paths.
The first replay-control self-test used an incomplete synthetic input path;
the corrected control passes. All failed diagnostics and frozen inputs remain
in the external bundle.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/altstackframe-reference.v --self-test
v run tests/linux-compat/altstackframe-evidence.v self-test
v run tests/linux-compat/altstackframe-evidence.v check /Users/alex/.cache/vinix-linux-compat/altstackframe-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes 11 positive and rejects 46 negative controls,
including swapped original failure counts, altered recorded failures and
changed replay identity. Its successful audit certifies complete evidence for
the focused fix; it preserves the x86-64 maintained failure as a failure.

This qualifies saved uc_stack records and one nested delivery per outer
handler. Repeated nested delivery on AArch64 still uses its existing delivery
boolean. Restoring handler-modified uc_stack on rt_sigreturn is not
implemented or qualified by this change. SS_AUTODISARM, dynamic frame sizing,
minimum-stack delivery and thread races remain unqualified. GNU libc,
translated/ELF32 paths and installation, service, sandbox and portal acceptance
remain separate qualifications. Three broad section 15 gates remain open.
