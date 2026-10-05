Vinix uses Alpine's musl ABI with allocation reuse built into the default
libc. The source releases and every patch from Alpine's `musl-1.2.5-r11` and
`musl-1.2.6-r2` recipes are pinned and checked before building. The helper
selects 1.2.5 or 1.2.6 from the existing staged loader. Newer 1.2.5 packages
that backport `posix_getdents` use the compatible 1.2.6 recipe. An ELF
architecture check and an exported-symbol check prevent silent ABI downgrades.
Alpine's loader SONAME and existing exported functions are preserved. The build also optimizes the `mallocng`
functions for speed, alongside musl's normal optimized string functions.

`stage.py --arch x86_64 --staging ROOT` and its `aarch64` equivalent install the
loader and, when development headers are present, `libc.a` and the extended
`malloc.h`. The userland and desktop builders call it after package overlays;
both desktop builders also update their static build sysroots. This applies to normal
programs and native GCC builds, without `LD_PRELOAD` or benchmark changes.
Builds are cached by source, patches, compiler, flags, architecture and policy.

The default policy keeps the final ordinary group in each size class when its
footprint is at most 128 KiB. Existing consolidation still releases extra free
groups, and individually mapped ordinary groups with a reduced stride retain
musl's release policy. Keeping a small nested group avoids rebuilding its
metadata on each malloc/free pair. New groups have a minimum capacity of up to
eight slots, calculated from the same 128 KiB budget and their full slot stride.
Upstream's larger groups remain unchanged. This gives ordinary applications a
small reusable working set instead of repeatedly mapping single-object groups.

Direct allocations keep at most one free mapping in each of five power of two
buckets, from 128 KiB through 2 MiB. The buckets total at most 3968 KiB. Other
free direct mappings are unmapped as before. A larger free map replaces a
smaller cached map in its bucket, preventing permanent misses after workloads
grow; the old mapping is released after unlocking. The retained ordinary groups' own storage totals at most 6 MiB across the
48 size classes. A nested group also holds a slot in its parent allocation;
on 16 KiB ARM pages its eventual parent mapping can be up to 256 KiB. Counting
each retained group against a separate parent gives a conservative 12 MiB
ordinary backing bound, and less than 16 MiB with the direct cache. Shared
parents reduce actual usage. Live allocations and upstream's pre-existing
bouncing/fragmentation policy are outside this additional-retention bound.
Bucket endpoints align with 16 KiB ARM pages, so page rounding preserves the
direct-cache bound.

Freed mappings remain owned by their metadata until reuse or trimming. The
existing malloc lock and fork protocol protect the cache. Header validation,
redzones and allocation offset cycling stay enabled. Mallocng assertions use
`__builtin_trap()` so GCC preserves redzone checks even when their return values
are unused; this hardening also applies to the retention-disabled control.
`calloc` clears reused
large mappings rather than assuming that they are fresh anonymous memory.
Existing `realloc`, aligned allocation and allocation failure paths remain in
use. The `malloc_trim(size_t)` extension releases cached direct mappings and
fully free ordinary groups, preserving every live allocation and `errno`.
It returns nonzero if a mapping was returned to the kernel; its padding hint
is ignored.

To build the same libc with upstream retention behavior, set
`VINIX_MUSL_RETAIN=0`. To keep the unmodified Alpine package altogether, set
`VINIX_OPTIMIZED_MUSL=0` while rebuilding the staging tree. Compiler commands
can be supplied through `VINIX_MUSL_CC_X86_64` and `VINIX_MUSL_CC_AARCH64`.
`VINIX_MUSL_BUILD_DIR` changes the private build cache directory.

`tests/user-alloc/verify.c` tests reuse, zeroing, resizing, aligned allocations,
observed retention and trimming with live objects, cross-thread ownership transfer,
allocation after a multithreaded fork, and corruption rejection. Compile it
against the staged default libc, both dynamically and statically, and run in
the actual guest before collecting allocation timings.

Sources: [musl releases](https://musl.libc.org/releases.html),
[Alpine musl 1.2.5-r11 recipe](https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.21-stable/main/musl/APKBUILD),
[Alpine musl 1.2.6-r2 recipe](https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.24-stable/main/musl/APKBUILD).
The vendored Alpine patches keep their upstream author notices and come from
Alpine's MIT-licensed musl package. [COPYRIGHT](COPYRIGHT) preserves musl's
MIT license, contributor attribution and compatible third-party terms; the
builder also installs this notice in `/usr/share/licenses/musl/COPYRIGHT`.
