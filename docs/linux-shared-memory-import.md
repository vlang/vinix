# Native shared-memory metadata import

Vinix now imports the complete native IPC_SET record before looking up a
nonnegative segment ID or checking ownership. An unreadable record returns
EFAULT even for a stale or missing ID or a caller without control rights.
Negative IDs and commands still return EINVAL before importing input.
This follows [Linux v6.12 ipc/shm.c](https://github.com/torvalds/linux/blob/v6.12/ipc/shm.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000, with
an additional UID 3000/GID 4000 nonowner cohort. They check null, low,
all-ones, unmapped, inaccessible and partially readable pointers, including
the ignored tail of the 112-byte native record. Failed calls preserve all
reported metadata. A complete read-only record ending exactly at a page
boundary succeeds. Readable input retains EINVAL for missing IDs and invalid
owner IDs and EPERM for nonowners. IPC_STAT and IPC_RMID retain ID error
precedence; successful IPC_RMID ignores the supplied pointer. No cohort forks
with an inherited SHM mapping.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 218 | 0 |
| Original Vinix production kernel | 218 | 33 |
| Corrected Vinix production kernel | 218 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. All twelve maintained regression suites pass per architecture:
shmimport, shmremove, shmtime, shmset, shmabi, shmflags, shmremap, sharedmem,
runtime, mmap, namespace and jit.

The isolated candidate is `2c0e2d6a3f1079c500ca9dfe4c0a3f618bae4e2a`, based on
`71c1556570c02d136dde1508d7866e7889666474`. Only sysvshm changes; the mapping
and exit sources are retained unchanged for comparison:

| Source | SHA-256 |
| --- | --- |
| kernel/sysvshm/sysvshm.v | `f67e8818f41bc2c61e728eba9a415d702119d4d1a1a7f289ca768d28bdbf989d` |
| kernel/memory/mmap/mmap.v | `abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f` |
| kernel/userland/exit.v | `2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `74aff3464344238441897aa8eda6d091c0ab90a7cffd78ae33ac4813b480231b` |
| x86-64 | `eeee315de8a8b855a9b819e6f025552434aa7b50b043dbce3e5947ae299bfd59` |

Generated C review on both architectures compares all 16 sysvshm function
bodies. Only shmctl changes: a negative-argument guard and stack input copy
precede the lock, and IPC_SET consumes that input without its former temporary
operation pin or unlock/relock sequence. No segment pointer survives usercopy;
lookup, authorization and metadata changes hold the segment lock. Every
post-lock return releases it. The other sysvshm bodies and four inspected
mapping/exit paths are byte-identical to the baseline. There is no new
allocation, release or object lifetime. This scope review does not claim a
measured allocation-leak qualification.

Fork-inherited/split attachment counts, intermediate detach timestamps,
mremap metadata, removal/credential races, IPC namespace isolation and mapped
user namespaces remain separate work. This does not qualify full System V IPC,
GNU libc, translated/ELF32 applications or installation/service/sandbox/portal
acceptance. The three broad section 15 acceptance gates remain open.

The external bundle is
`/Users/alex/.cache/vinix-linux-compat/shmimport-20261025/evidence-final`.
Its complete audit passes: 18,419 artifacts, no omitted selected inputs, and
manifest SHA-256
`4210872b53e96800e5b378a1b2cc274bdf7c51879dc49014699a55492899565b`.
It retains selected build/compile/reference/native/maintained inputs and
outputs, source inventories, generated C review and unsuccessful preparation
attempt receipts. Two initial probe compilations failed on an errno lvalue
and a nonliteral printf format; the corrected source compiles on both
architectures. The initial x86 build invocation failed before creating its
state directory; its retry passes. The first generated C review helper
expected an extra blank line; its corrected comparison passes. These
diagnostic records do not claim separately qualified complete input closures.
Selected runs must retain every pinned input, and the original complete
historical bundles remain required.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/shmimport-reference.v --self-test
v run tests/linux-compat/shmimport-evidence.v self-test
v run tests/linux-compat/shmimport-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmimport-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.
