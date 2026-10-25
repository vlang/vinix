# Native alternate-stack modes and ABI minimum

Vinix sigaltstack accepts input modes zero, SS_ONSTACK and SS_DISABLE,
rejecting combined and unknown modes with EINVAL. Away from a handler,
SS_ONSTACK input installs a stack and queries report mode zero. SS_DISABLE
ignores the supplied pointer/size and clears the stack. Enabled stacks need
at least 5120 bytes on native AArch64 or 2048 on native x86-64; smaller
records return ENOMEM. Valid updates survive old-record output EFAULT.
These semantics follow
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c)
and the architecture UAPI minimum in
[arm64 signal.h](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/include/uapi/asm/signal.h)
and [x86 signal.h](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/uapi/asm/signal.h).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000,
starting with disabled and enabled stacks. Eight flag words and nine sizes
cover both minimum boundaries, combined/unknown flags and disable handling.
Three input and nine output placements cover aligned, unaligned, exact page
ends, null, invalid, read-only, crossing a protected page and aliased records.
Each combination checks return value, errno, stack state, complete writable
output and guard bytes. The upper padding of the flag word is nonzero;
record comparisons ignore unspecified padding. Faulting partial-copy bytes
are not asserted. This fixture delivers no signals.

| Architecture and kernel | Checks | Failures |
| --- | ---: | ---: |
| AArch64 Linux 6.12.51 | 38,880 | 0 |
| AArch64 original Vinix production | 38,880 | 2,628 |
| AArch64 corrected Vinix production | 38,880 | 0 |
| x86-64 Linux 6.12.51 | 38,880 | 0 |
| x86-64 original Vinix production | 38,880 | 2,268 |
| x86-64 corrected Vinix production | 38,880 | 0 |

Native AArch64 uses 16 KiB pages; native x86-64 and both Linux references
use 4 KiB pages. Both production builds pass with unchanged before/after
source inventories. All fifteen maintained suites pass per architecture:
altstackabi, sigactionabi, sigactioncopy, sigmaskcopy, altstackcopy,
sigwaitorder, sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear,
seccomp, runtime, futex and jit.

The first maintained runs lost their guest directories during concurrent work, with the cause unknown. The AArch64 QEMU was terminated after that loss; the x86-64 controller failed while writing its missing receipt. Controller logs, commands and statuses survive. No missing receipt is reconstructed. Fresh persistent runs retain complete artifacts for all fifteen suites on both architectures with unchanged fixtures and kernels. Earlier intermittent randomsignal and futex failures remain unresolved; passing replays do not establish their cause.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/altstackabi-20261025/evidence-final`
retains 18116 files with zero omitted selected inputs. Its manifest
SHA-256 is `10c0734b3470e02b5e7b3b03c03d7fd6575c62e26b219543923426e8fe5894ea`.
Historical complete bundles remain required by their original checkers.

The isolated candidate is `4e8c41a2e26effce5ccfb6b66331dad4b399f8ec`, based on
`2f42584b88b29771f2206af5c48e17afb06a7bc1`. Only signal.v changes, with SHA-256
`b082e62141a3f7d020bbba77b408b941e5b6cd5025c888345ed85f6a2a1d9dd4`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `a2eeb08a38785bd6a21a8409a675788cc45967dc2428ba98f1c638a1dc0354b3` |
| x86-64 | `5a319314d4fb1b0bc5efc0f47a823bb425cf358e4eb22779c180f8da85f869bd` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only syscall_sigaltstack changes: exact mode validation,
disable equality and an architecture-specific minimum replace the earlier
mask check and shared 2048-byte minimum. Snapshot, update and output-copy
ordering stay unchanged. There is no allocation, release or new object
lifetime. Other bodies and usercopy/mapping/exit functions remain identical.
No measured allocation-leak qualification is claimed.

The first private probe-preparation helper failed to compile because an
Option was treated as a Result. Its corrected invocation passes. The first
build-controller invocations used an invalid CLI argument order and failed
before building; corrected invocations pass. Failed diagnostics and all
frozen inputs are retained. Original, corrected and Linux runs use the same
ELF per architecture.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/altstackabi-reference.v --self-test
v run tests/linux-compat/altstackabi-evidence.v self-test
v run tests/linux-compat/altstackabi-evidence.v check /Users/alex/.cache/vinix-linux-compat/altstackabi-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes six positive and rejects 25 negative controls,
including original failure counts from the wrong architecture.

SS_AUTODISARM, active-handler EPERM/import-fault precedence, dynamic signal
frame sizing, delivery on minimum-sized stacks and asynchronous races remain
unqualified. GNU libc, translated/ELF32 paths and installation, service,
sandbox and portal acceptance remain separate qualifications. Three broad
section 15 gates remain open.
