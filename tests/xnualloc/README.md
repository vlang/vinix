# XNU allocator port tests

Experimental, partial translation. Read `docs/xnualloc/PORT_STATUS.md` before
using this kernel backend. Source and extracted-reference notices are retained;
APPLE_LICENSE accompanies this directory. This is not a GPL relicensing.

From the repository root, the checks executable without V are:

```sh
python3 tests/memory/heap_model_test.py
python3 tests/xnualloc/reference_test.py
python3 tests/xnualloc/zone_model_test.py
```

They passed locally: 10 independent slab-model tests, 4 C-reference/model tests
and 6 non-SMR zone-protocol/source tests. They do not execute V. The reference
suite requires a C compiler with UBSan; set `CC` to its executable if necessary.
The zone model uses four logical CPU caches, not concurrent hardware threads.

Actual V host tests (18 functions):

```sh
VMODULES="$(pwd)/kernel/modules" v -cc gcc -gc none test tests/xnualloc
VMODULES="$(pwd)/kernel/modules" v -prod -cc gcc -gc none test tests/xnualloc
```

On a normal Linux x86-64 Vinix build machine, with a compatible V compiler:

```sh
cd kernel
./get-deps
make clean
make PROD=false V=/absolute/path/to/v \
  VFLAGS='-d xnu_zone -d heap_selftest' \
  CFLAGS='-Ulinux -U__linux -U__linux__ -U__gnu_linux__ -D__vinix__ -O2 -g -pipe'
```

Use the repository's architecture-specific tooling for ARM64. Also build
flag-off and `-d xnu_bitmap` configurations. For each architecture boot the
resulting image using its normal Vinix deployment procedure, and require the
serial marker `heap: self-test passed`. This boot test executes before SMP, so
separate interrupt-heavy, cross-CPU allocation/free/trim and OOM tests are still
required.

On x86_64, add `-d heap_benchmark` to run the real allocator benchmark after
SMP cache registration. Build and boot otherwise identical default and
`-d xnu_zone` kernels, then compare the five `hot` and five `batch` samples by
median `ticks_per_op`. TSC ticks are relative measurements, so do not compare
results from different QEMU acceleration, CPU, memory, SMP or host settings.
