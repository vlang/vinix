# Kernel link layout randomization

Direct LLD links now shuffle `.text.*` input sections by default, including the
individual V-generated functions inside blob.c.o. Limine request markers,
per-CPU data templates and segment permissions retain the linker script's
ordering. `KERNEL_LINK_RANDOMIZE=0` disables it; `KERNEL_LINK_SEED=<positive int>`
selects a reproducible layout. Seed 0 requests fresh randomness from LLD.

This addresses build-time layout randomization in SEC10 on the direct LLD
builds used for both architecture cross-builds. It does not randomize the kernel
base, relink on every boot, add return guards, or change native compiler-driver
links (which may use a linker without this option). Keep the exact ELF with
any crash report, because source-identical builds may have different addresses.

After building each architecture's objects, put `ld.lld` and `llvm-nm` on
PATH (or set `LD` and `NM` to their absolute paths), then run:

```sh
tests/kernel-link-layout/check --kernel=kernel --arch=aarch64
tests/kernel-link-layout/check --kernel=build-amd64-kernel --arch=x86_64
```

The test relinks the actual objects with equal, distinct and random seeds,
requires byte-identical output with equal fixed seeds, checks different function
orders otherwise, and verifies the kernel entry survives. A normal guest boot
checks that shuffled code still runs; address variation is not a performance claim.

The command compiles and runs native V through `build-support/run-v-tool.sh`;
select the compiler with `V` or `VINIX_V_COMPILER`. It needs no Python runtime.
Qualification compared the previous checker with ARM and x86 host binaries
using isolated AArch64 and x86_64 ELF objects, the repository linker scripts
and real LLD/llvm-nm. Both target layouts passed all five links. The shared
checkout's existing objects contain both architectures and duplicate fixture
symbols, so neither checker can qualify that object directory without a clean
build. This port does not claim a new kernel build or guest boot.
