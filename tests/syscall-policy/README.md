# Syscall instruction policy regression

`guest.c` runs against the production kernel, using a small cooperating runtime
that copies dedicated AMD64/ARM64 syscall veneers into sealed anonymous text.
It covers disabled mode; descriptor/table failures; instruction bytes, bounds,
uniqueness and mapping policy; rejection while another thread is published;
direct enforcement; audit counters; immutable text mutations; pledge controls;
fork inheritance, independent strengthening, fatal violations and exec reset.

The alias checks reject unsupported `MREMAP_DONTUNMAP`, modify a writable split
mapping sharing the same global object, and let a parent rewrite text after a
pre-seal fork. The sealed child's original instruction must survive through
copy-on-write. Both actual guests pass these checks.

Build tracked kernels, then boot from an isolated worktree:

```sh
VINIX_VM_RUNNER_ROOT=/Users/alex/code/vinix \
VINIX_KERNEL_DIR="$PWD/kernel" \
VINIX_AARCH64_SYSROOT=/Users/alex/code/vinix/build-aarch64-userland/sysroot \
VINIX_QEMU_RT_NO_BUILD=1 VINIX_QEMU_AUDIO=off \
python3 tests/syscall-policy/run.py

VINIX_VM_RUNNER_ROOT=/Users/alex/code/vinix \
VINIX_KERNEL_DIR="$PWD/kernel" \
VINIX_AMD64_KERNEL="$PWD/build-amd64-kernel/bin/vinix" \
VINIX_QEMU_RT_NO_BUILD=1 VINIX_QEMU_AUDIO=off \
python3 tests/syscall-policy/run.py --arch=amd64
```

The guest redirects output to `/dev/com1` with `O_NOCTTY` before markers. It
measures 1,000 rejected installs that allocate and return a transient table,
then 10,000 successful checks and queries. On tracked kernels based on
`2137476a`, ARM slab stayed at 1392 KiB for rejections and 1616 KiB for entry
checks; AMD64 stayed at 952 KiB for rejections and fell from 1048 to 1032 KiB
for entry checks. Each guest also reaps 100 fork children while continuing to
use the parent's retained table. Allocation sites from that broader fork path
still include baseline allocations; these measurements do not claim every
preexisting kernel leak is fixed.

The host test extracts ten functions directly from the generated production C,
including metadata/opcode validation and table allocation, lookup, inheritance
and release. Adapters supply locks, physical pages and a fallible allocator.
ASan/UBSan check `ENOMEM`, `EFAULT`, validation rollback, last-owner release and
four concurrent inherit/release workers racing repeated parent reset/install:

```sh
python3 tests/syscall-policy/run-host.py kernel/obj/blob.c
python3 tests/syscall-policy/run-host.py build-amd64-kernel/obj/blob.c
```

Both generated architecture variants pass. The script also checks those
functions for V array/memdup promotions and the single caller-stack descriptor.
Both tracked architecture production builds pass. The allocation allowlist
audit still fails on preexisting categories: ARM reports 354 sites with V exit
0; AMD64 reports 245 sites with V exit 1 from the standalone audit's existing
`drm.simple` import-copy problem. No allowance is relaxed for this change.

This exercises an opt-in runtime contract. It does not demonstrate pin-table
loading from ELF or enforcement for unmodified libc, Go, or translated binaries.
