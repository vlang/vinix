# Native alternate-stack output-copy ordering

Vinix sigaltstack now commits a valid alternate-stack change before copying
the old stack to userspace. An output EFAULT leaves that valid change in
place. Input faults and validation failures preserve state and do not copy
the old record. The snapshot precedes the update, including when input and
output overlap. This follows do_sigaltstack in
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. They
cover enabled/disabled transitions, six inaccessible output pointer classes,
valid/unaligned records, exact page boundaries, input/output aliasing, guard
bytes and null outputs. Input EINVAL, ENOMEM and EFAULT take priority over
output faults; queries preserve state and high flag padding is ignored.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 560 | 0 |
| Original Vinix production kernel | 560 | 36 |
| Corrected Vinix production kernel | 560 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. The maintained set is altstackcopy, sigwaitorder, sigwaitcopy,
sigpending, randomsignal, clonesignal, cloneclear, seccomp, runtime, futex
and jit.

All eleven maintained suites pass per architecture.

The first x86-64 maintained attempt failed randomsignal: two reads returned
the full 8 MiB after a timer signal, with zero saved in the signal frame.
The complete retry passed all eleven cases with unchanged probes and kernel.
Both attempts are retained; the first failure has no conclusively established
cause.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/altstackcopy-20261025/evidence-final`
retains 18200 files with zero omitted selected inputs. Its manifest
SHA-256 is `c7f6d1ae61178d4f5885ec1ec898d77c85c559554be83712de2d1b75cce5b952`.
Historical complete bundles remain available at their original locations.

The isolated candidate is `64636392d19550384154de8894eadbcaa8441db4`, based on
`39f1785dfece264c5ad209836ac46f1118472efd`. Only signal.v changes, with SHA-256
`32f8d5dff2e02ca17ec37c985bc90a42e00fae7319b68bd3fbdca306552ae6b0`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `194d05d96b6caf99a4be6b06046f34f8bb5dc11803a8c3b88cc835b2b43a0277` |
| x86-64 | `ae36f842c38d06319b0394570c4dec8a8f4e501c73b23ed076a4fad6e2dfef0c` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only syscall_sigaltstack changes: a stack array snapshots
the old record, the existing update commits, then the snapshot is copied out.
Usercopy, mapping and exit bodies are unchanged. No allocation, release or
new object lifetime is introduced. This scope review does not claim measured
allocation-leak qualification.

The first private fixture compilation failed on cached-compiler errno
assignment syntax. The corrected second compilation is used unchanged by
original, corrected and Linux runs. Diagnostic attempts and frozen inputs
are preserved. Historical complete bundles remain required by their original
checkers.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/altstackcopy-reference.v --self-test
v run tests/linux-compat/altstackcopy-evidence.v self-test
v run tests/linux-compat/altstackcopy-evidence.v check /Users/alex/.cache/vinix-linux-compat/altstackcopy-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.

Signal-handler/on-stack changes, SS_ONSTACK and SS_AUTODISARM input semantics,
input-copy/on-stack error precedence, asynchronous races, GNU libc,
translated/ELF32 applications and installation, service, sandbox and portal
acceptance remain separate qualifications. Three broad section 15 gates
remain open.
