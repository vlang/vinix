# Native alternate-stack handler fault precedence

Vinix imports a non-null sigaltstack input record before checking whether
the calling thread is executing on its alternate stack. An unreadable record
returns EFAULT, including inside an alternate-stack handler. A readable record
inside that handler returns EPERM before mode/size validation and old-record
output. A null input still permits stack queries; invalid output returns
EFAULT. These semantics follow
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000.
A SIGUSR1 SA_SIGINFO/SA_ONSTACK handler verifies execution inside a guarded
65,536-byte alternate stack. Eight flag words, three sizes, nine input and
nine output placements cover aligned/unaligned, exact page ends, null,
invalid, protected, read-only, crossing-page and aliased records. Every
combination checks return value, errno, stack state, complete writable output
and guards. The upper padding of the flag word is nonzero; comparisons ignore
unspecified padding. Faulting partial-copy bytes are not asserted. Queries
report SS_ONSTACK inside the handler and mode zero after return.

| Architecture and kernel | Checks | Failures |
| --- | ---: | ---: |
| AArch64 Linux 6.12.51 | 19,444 | 0 |
| AArch64 original Vinix production | 19,444 | 2,160 |
| AArch64 corrected Vinix production | 19,444 | 0 |
| x86-64 Linux 6.12.51 | 19,444 | 0 |
| x86-64 original Vinix production | 19,444 | 2,160 |
| x86-64 corrected Vinix production | 19,444 | 0 |

Native AArch64 uses 16 KiB pages; native x86-64 and both Linux references
use 4 KiB pages. Both production builds pass with unchanged before/after
source inventories. Sixteen maintained suites pass on AArch64; fifteen pass
on x86-64, where randomsignal fails. The suites are:
altstackhandler, altstackabi, sigactionabi, sigactioncopy, sigmaskcopy,
altstackcopy, sigwaitorder, sigwaitcopy, sigpending, randomsignal, clonesignal,
cloneclear, seccomp, runtime, futex and jit. The x86-64 randomsignal failure
recurs with the identical ELF and kernel in a separate replay: an 8 MiB
request completes in full while the handler observes result zero. The
fixture assumes its 1 ms timer fires during the transfer. Pre-transfer
signal delivery is a possible explanation, not an established cause. Both
failures remain unresolved. The first replay failed before boot because
its QEMU socket path exceeded the host limit; its diagnostics are retained.
Earlier intermittent randomsignal and futex failures remain unresolved.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/altstackhandler-20261025/evidence-final`
retains 18204 files with zero omitted selected inputs. Its manifest
SHA-256 is `36f0a85c86d94dd60782c71411b499d23ec40368c2667edd290c118f69e234e9`.
Historical complete bundles remain required by their original checkers.

The isolated candidate is `60c383cf5355594e1ad6cf610ab071c40607e073`, based on
`4e8c41a2e26effce5ccfb6b66331dad4b399f8ec`. Only signal.v changes, with SHA-256
`659b2392ff63e82bcaf42fd0031313efff58726cb63bbb09f24fed9e25a8579e`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `0dc1b26f9027d4e13ec42023f10640258445639e62d657c97124352e4e8dcda1` |
| x86-64 | `af89717cd8e2f91572cf59053a4be862d3bb019df8bf342e1c0d10147befcd30` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only syscall_sigaltstack changes: the active-handler EPERM
check moves after the input copy. Mode/size checks, snapshot, update and
output ordering remain identical. There is no allocation, release or new
object lifetime. Other bodies and usercopy/mapping/exit functions remain
identical. No measured allocation-leak qualification is claimed.

The first private audit-preparation helper failed to compile because an
Option used Result propagation and string.quote was unavailable. The corrected
helper passes. Failed diagnostics and all frozen inputs are retained. Original,
corrected and Linux runs use the same ELF per architecture.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/altstackhandler-reference.v --self-test
v run tests/linux-compat/altstackhandler-evidence.v self-test
v run tests/linux-compat/altstackhandler-evidence.v check /Users/alex/.cache/vinix-linux-compat/altstackhandler-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes seven positive and rejects 28 negative controls,
including incorrect original failure counts for each architecture and
missing or changed retained regression failures. The audit verifies evidence
integrity; it does not classify these failures as passes.

SS_AUTODISARM, dynamic signal frame sizing, delivery on minimum-sized stacks,
nested asynchronous handlers and thread races remain unqualified. GNU libc,
translated/ELF32 paths and installation, service, sandbox and portal acceptance
remain separate qualifications. Three broad section 15 gates remain open.
