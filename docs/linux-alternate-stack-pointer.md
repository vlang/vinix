# Native alternate-stack live stack pointer

Vinix uses the user stack pointer saved at syscall entry to decide whether
sigaltstack is executing on the registered alternate stack. Both architectures
use Linux downward-growing stack bounds: the base is excluded and the end is
included. Queries report SS_ONSTACK only within these bounds; readable updates
return EPERM there. Outside them, valid updates succeed and mode/size errors
return EINVAL/ENOMEM. A handler that switches away from its alternate stack
may therefore query or update it. The previous x86-64 helper used stale thread
stack state, and AArch64 used a delivery boolean. See
[Linux v6.12 sched/signal.h](https://github.com/torvalds/linux/blob/v6.12/include/linux/sched/signal.h)
and [kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

The static musl probe runs as root and UID 1000/GID 2000. It checks both
ordinary execution and a real SIGUSR1 SA_ONSTACK handler on a guarded
65,536-byte stack. A small assembly wrapper pivots SP for a raw syscall and
restores it without touching the pivoted stack. Six offsets cover 16 bytes
below the base, the base, 16 bytes above it, 16 bytes below the end, the end
and 16 bytes beyond it. Query, valid update, invalid flags and zero-size
requests check raw return/errno, old records, current state and guards.

| Architecture and kernel | Checks | Failures |
| --- | ---: | ---: |
| AArch64 Linux 6.12.51 | 388 | 0 |
| AArch64 original Vinix production | 388 | 60 |
| AArch64 corrected Vinix production | 388 | 0 |
| x86-64 Linux 6.12.51 | 388 | 0 |
| x86-64 original Vinix production | 388 | 40 |
| x86-64 corrected Vinix production | 388 | 0 |

Native AArch64 uses 16 KiB pages; native x86-64 and both Linux references
use 4 KiB pages. Both production builds pass with identical before/after
source inventories. Seventeen maintained suites pass on each architecture:
altstacksp, altstackhandler, altstackabi, sigactionabi, sigactioncopy,
sigmaskcopy, altstackcopy, sigwaitorder, sigwaitcopy, sigpending, randomsignal,
clonesignal, cloneclear, seccomp, runtime, futex and jit. Earlier intermittent
randomsignal and futex failures, including the preceding handler qualification
and its identical replay, remain unresolved; this batch does not establish
their cause or resolution.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/altstacksp-20261025/evidence-final`
retains 18200 files with zero omitted selected inputs. Its manifest
SHA-256 is `2b61e869e777cb4573a89d3865aff033cfeb9026ce3c88bbc5330aabde874dd9`.
Historical complete bundles remain required by their original checkers.

The isolated candidate is `7406d1740951142074a2f58447edbb53048aea01`, based on
`60c383cf5355594e1ad6cf610ab071c40607e073`. The changed source SHA-256 values are:

| Source | SHA-256 |
| --- | --- |
| signal.v | `393364612c2773ad89d70cc4ced369ad836fdb79076ec4c37db49877f2cadde2` |
| linux_signal_amd64.v | `931b29d65bc379374f1c53bfc1c1b559e23ffe57f664e170de6b0dd072efb3aa` |
| userland_arm64.v | `a4609d6617f647b138c7be02c17f4a12a4970963f42d8b3a608f6a9e565aa346` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `8110467a6534548027ec3e4165764ebd829343adf55981b6cfd8d2d2c2b8e187` |
| x86-64 | `5217d5de006e19aca8975c658b558721fca6faec4ab5a93c360e6abe1505f218` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies with the preceding candidate. Only sigaltstack and the
architecture stack-detection helpers change: two bodies on AArch64 and three
on x86-64. The syscall passes its saved context; helpers read SP/RSP and apply
the Linux bounds. There is no allocation, release or new object lifetime.
Other bodies and usercopy/mapping/exit functions remain identical. No measured
allocation-leak qualification is claimed.

The first private review helper failed to compile because of Option/Result
propagation, and the first audit helper used an unsupported mutable string
parameter. Corrected helpers pass; diagnostics and frozen inputs are retained.
Original, corrected and Linux runs use the same ELF per architecture.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/altstacksp-reference.v --self-test
v run tests/linux-compat/altstacksp-evidence.v self-test
v run tests/linux-compat/altstacksp-evidence.v check /Users/alex/.cache/vinix-linux-compat/altstacksp-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes eight positive and rejects 33 negative controls,
including original failure counts for the wrong architecture.

SS_AUTODISARM, dynamic frame sizing, minimum-stack delivery, nested asynchronous
handlers and thread races remain unqualified. AArch64 signal delivery still
uses its existing boolean; this change qualifies syscall stack-state queries
and updates only. GNU libc, translated/ELF32 paths and installation, service,
sandbox and portal acceptance remain separate qualifications. Three broad
section 15 gates remain open.
