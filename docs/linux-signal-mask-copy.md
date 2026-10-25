# Native signal-mask output-copy ordering

Vinix rt_sigprocmask now commits a valid mask change before copying the old
mask to userspace. An output EFAULT leaves the valid update in place. Input
faults, invalid operations and invalid sizes preserve the mask and output.
The old-mask snapshot precedes input import, including when input and output
overlap. This follows rt_sigprocmask in
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. They
cover four starting masks, four incoming masks, all three valid operations,
six inaccessible output pointer classes, valid/unaligned/aliased/null output,
exact page boundaries and guard bytes. Input EFAULT/EINVAL precedence, invalid
sizes, ignored query-only operations and stripping SIGKILL/SIGSTOP are covered.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 3,984 | 0 |
| Original Vinix production kernel | 3,984 | 324 |
| Corrected Vinix production kernel | 3,984 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. The maintained set is sigmaskcopy, altstackcopy, sigwaitorder,
sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear, seccomp,
runtime, futex and jit.

All twelve maintained suites pass per architecture.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/sigmaskcopy-20261025/evidence-final`
retains 17999 files with zero omitted selected inputs. Its manifest
SHA-256 is `aeb8c3ca104a714a17353f86d62018a2bab5eee3b0a246c3d8012f6bf3a19d21`.
Historical complete bundles remain available at their original locations.

The isolated candidate is `6cbe5ba3a455cb02c72cbc6224aa7e6b8af071d1`, based on
`64636392d19550384154de8894eadbcaa8441db4`. Only signal.v changes, with SHA-256
`f5a2886b8b20aeea545c522a740a82127e489045c652f8bc6346f01d23880399`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `df41428278d89c1495f482b221ce87f6c94e4849a867da1ee08b82b33dcc8537` |
| x86-64 | `83145a85ef5041be1afefb49f7d69aae3d011caac5afc9358369e71390caeb8a` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only syscall_rt_sigprocmask changes: a stack scalar snapshots
the old mask, the existing update commits, then the snapshot is copied out.
Pending selection, timed wait, alternate stack, timers, usercopy, mapping and
exit bodies are unchanged. No allocation, release or new object lifetime is
introduced. This scope review does not claim measured allocation-leak
qualification.

The first private x86-64 fixture compilation failed during concurrent
temporary-directory creation. Its second compilation uses the same fixture
bytes as the first AArch64 compilation. Original, corrected and Linux runs
use the same compiled ELF for each architecture. The first reference-parser
control command used an invalid CLI argument; the corrected invocation passes.
Diagnostic attempts and frozen inputs are preserved. Historical complete
bundles remain required by their original checkers.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/sigmaskcopy-reference.v --self-test
v run tests/linux-compat/sigmaskcopy-evidence.v self-test
v run tests/linux-compat/sigmaskcopy-evidence.v check /Users/alex/.cache/vinix-linux-compat/sigmaskcopy-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.

Asynchronous mask/delivery races, GNU libc, translated/ELF32 applications and
installation, service, sandbox and portal acceptance remain separate
qualifications. Three broad section 15 gates remain open.
