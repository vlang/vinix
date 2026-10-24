# Native pending-signal output prefixes

Vinix now accepts native rt_sigpending output lengths from zero through eight
bytes and copies only the requested prefix. Zero length succeeds without
accessing the pointer. Larger lengths return EINVAL before pointer validation;
unwritable nonempty output returns EFAULT. This follows
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).
The size requirements of other signal syscalls are unchanged.

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. They check
aligned and unaligned output, untouched surrounding bytes, empty and pending
thread/process signal sets including signal 64, libc sigpending, repeated reads,
null/low/all-ones/unmapped/inaccessible/read-only pointers, oversized lengths
including high bits, exact page boundaries and crossing into a guard page.
The pending signals remain blocked through cohort exit. Controls retain the
full-size rt_sigprocmask ABI.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 428 | 0 |
| Original Vinix production kernel | 428 | 256 |
| Corrected Vinix production kernel | 428 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. All eight maintained regression suites pass per architecture:
sigpending, randomsignal, clonesignal, cloneclear, seccomp, runtime, futex and jit.

The isolated candidate is `5d77bed2bca8a55d49a28dd21c0d785229517037`, based on
`2c0e2d6a3f1079c500ca9dfe4c0a3f618bae4e2a`. Only gaps.v changes:

| Source | SHA-256 |
| --- | --- |
| kernel/syscall/table/gaps.v | `f7a135f09229e9808ab5e4b75c3a0874d7087d3da4032aebbc7ab66e4e122a84` |
| kernel/memory/mmap/mmap.v (unchanged) | `abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f` |
| kernel/userland/exit.v (unchanged) | `2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `abd2c364ff183fea5ceb45d59b5616a3b980dfc61cb6966022ecb55b653aa9d1` |
| x86-64 | `8964b0294c618c783bd5ad22742d8d349c7e27fbb39534d208f0bdca50b1fe1b` |

Generated C review compares 143 AArch64 and 188 x86-64 syscall-table function
bodies. Only rt_sigpending changes, exactly its size guard, null guard and copy
length. The pending-set/mask calculation and six inspected signal, usercopy,
mapping and exit functions are byte-identical. Output remains a synchronous
copy from a stack u64, with no new allocation, release or object lifetime.
This scope review does not claim a measured allocation-leak qualification.

This qualifies the native output-prefix ABI. Signal delivery races, queued
payloads, timed waits, GNU libc, translated/ELF32 applications and installation,
service, sandbox and portal acceptance need separate evidence. The three broad
section 15 acceptance gates remain open.

The complete external bundle is
`/Users/alex/.cache/vinix-linux-compat/sigpending-20261025/evidence-final`.
Its manifest SHA-256 is
`54cdf5e04525a3122a10f79930fa2b248a3ac563614a54e43e688060e40e4234`.
The complete evidence audit passes: 18,745 artifacts, zero omitted selected
input pins, both builds, same-ELF comparisons and eight maintained suites per
architecture.
It retains selected build, compile, reference, native and maintained inputs and
outputs, generated C review, source inventories and diagnostic attempts. Two
initial probe compilations failed on errno lvalue/C macro handling; the corrected
third compilation passes on both architectures. The first evidence-control
invocation used an unsupported option; the corrected invocation passes. The
first maintained runs hit QEMU's Unix-socket path limit for longer case names.
The next AArch64 attempt exposed a compiler wrapper restricted to the old state
path. Fresh runs with short paths and the corrected wrapper pass all eight
suites on each architecture. These diagnostic records do not claim separately
qualified complete input closures.
The original complete historical bundles remain required.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/sigpending-reference.v --self-test
v run tests/linux-compat/sigpending-evidence.v self-test
v run tests/linux-compat/sigpending-evidence.v check /Users/alex/.cache/vinix-linux-compat/sigpending-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.
