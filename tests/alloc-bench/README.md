# Allocation benchmark in Vinix and macOS

The [completed user-space comparison and all raw samples](results/2026-10-03-userspace-v6/README.md)
show Vinix faster than Catalina on all six workloads in both matched QEMU
cohorts and when all samples are pooled. These are single-thread QEMU TCG
measurements; the report records compiler/toolchain differences and validation.
The complete [v5](results/2026-10-03-userspace-v5/README.md) and
[v4](results/2026-10-02-userspace/README.md) campaigns preserve their slower
captures and failed targets. The
[earlier kernel measurements](results/2026-10-02/README.md) preserve the direct
kernel allocator comparison and qualify the old user-space timings.

`benchcore/core.v` supplies identical single-thread workloads on both guests.
`compile-v-bench.py` emits their C build artifact and native declaration header.
Compile that artifact with genuine GNU GCC: Apple's `/usr/bin/gcc` is Clang,
and the benchmark records that distinction. Results count an allocation/free
pair, a map/unmap pair, or a pipe/create/close pair, rather than counting each
half separately.

The workloads are 64-byte malloc reuse, mixed-size 64-object batches,
256 KiB malloc with one verified byte per 4 KiB, anonymous 4 KiB mmap/unmap
without a touch, 256 KiB mmap/touch/unmap, and pipe creation/closure. Every
workload has a full warmup and 5–31 recorded samples. Payload reads and writes
use native volatile byte fields; checksums must match. `-fno-builtin` also
prevents allocation calls from being removed. Logs identify the compiler, OS,
architecture, native page size, clock resolution, counts, size distribution,
and access stride.
Both runners record the V source hashes, V compiler version/hash, generated
artifact hash and native header hash, then compile inside the guest with the
same GCC flags as before. `test_v_bench.py --original-reference /outside/bench.c`
compares the immutable original C under ASan/UBSan, using a deterministic clock
and fault provider to check sample ordering, all mixed-batch OOM prefixes,
syscall failures, both pipe closes and restoration of the first close's errno.
These model clocks verify semantics and do not provide timing comparisons.

## What the measurements mean

`malloc` compares musl's user-space allocator on Vinix with Apple's libmalloc.
`mmap` measures the OS's VM allocation and teardown policy, including physical
allocation and page faults. `pipe` includes syscall and kernel-object costs.
These are useful allocation workloads, but none directly times XNU's `kalloc`
or Vinix's kernel slab allocator.

`kernel/heapbench/core.v` supplies a separate, shared kernel workload.
`compile-v-sampler.py` emits one freestanding C artifact for both platforms;
its header selects native allocation/logging symbols and compiler metadata. It
calls Vinix's kernel `malloc/free` and macOS's exported
`kern_os_malloc/kern_os_free` through a diagnostic kext. Both must return
zeroed memory; warmup checks every requested byte. Five recorded samples
measure 100,000 64-byte allocation/free pairs and 48 batches of 256 objects
across all fourteen Vinix slab classes, plus 128 whole-page 256 KiB heap
allocation/free pairs. Timed samples verify the two payload
endpoints and use serialized x86 TSC reads. Allocation and free policies,
including Vinix's poison checks, remain enabled.

`samplerfixture/core.v` independently checks the sampler's checksum, exact
674,496 success allocations/frees, allocation failure and poisoned-zeroing
rollback in each phase, a constant clock, and kext start/stop results.
`python3 tests/alloc-bench/test_v_sampler.py` runs it under ASan/UBSan.
The original calloc/free pair remains explicit. Native assembly captures the
complete variadic register banks for the bounded libc log buffer; those three
original va-list capture lines receive no V algorithm credit. Original C/V
fixtures are also compared on both host ABIs and both native musl targets,
using a deterministic clock rather than reporting comparative benchmark timings.

Vinix runs this sampler on the boot CPU before the scheduler starts, after
SMP publishes heap-cache readiness. macOS runs it from a loaded kext. This
execution-context difference and TCG's timing limit the interpretation;
retain raw ranges and repeat runs. These are actual kernel API timings, not
native hardware throughput or a comparison of every allocator path.

Vinix's existing `-d heap_benchmark` workload directly exercises its kernel
heap. Its optional `-d xnu_zone` backend is a partial XNU-inspired port running
inside Vinix; it is **not a macOS guest**. See
[the earlier port comparison](../../docs/xnualloc/BENCHMARK.md).

Vinix commits private anonymous x86 mappings on first touch; ARM keeps small
mappings eager for HVF compatibility. A timing
difference therefore needs investigation before attributing it to the heap.
The kernel's zeroing and free-poison checks are part of its measured cost.

## Build and run

Both runners refuse to reuse an existing output directory. The Vinix runner
boots a private VM, compiles inside that guest, and terminates only that VM.
The macOS runner targets an already prepared, disposable macOS guest over SSH;
it does not change the guest's boot configuration or stop it.

Use an isolated kernel worktree as required by the repository instructions.
Symlink the untracked kernel dependencies from the main checkout. Build a
production x86_64 kernel, optionally with
`VFLAGS='-d heap_benchmark -d heap_selftest'`. Keep build outputs separate when
switching V flags; the kernel's configuration stamp does not encode all flags.

Prepare an Alpine x86_64 root containing GCC and musl headers:

```sh
VINIX_AMD64_USERLAND_BUILD_DIR="$PWD/build/alloc-userland" \
  VINIX_ALPINE_DEVTOOLS=1 ./scripts/build-userland-amd64.sh
```

Then run:

```sh
python3 tests/alloc-bench/run-vinix.py \
  --kernel /absolute/worktree/kernel/bin/vinix \
  --sysroot build/alloc-userland/staging \
  --state-dir build/alloc-vinix \
  --iterations 200000 --samples 7 \
  --allocator-check tests/user-alloc/verify.c
```

The optional allocator check compiles and runs both dynamic and static link
modes before timing, and rejects incomplete verification. The runner records
the loader and static libc hashes and checks the staged build manifest.
Both runners default to 200,000 base iterations, seven samples and a one-hour
deadline for slow TCG hosts. Vinix's precise x86 clock reads the free-running
HPET or calibrated TSC; interrupt delivery counts cannot measure these runs
reliably. Historical captures made with the interrupt-counted clock are
documented separately in the results directory.

Configure the **macOS guest** with the same QEMU version and common options
as the Vinix runner:

```text
-machine q35,vmport=off
-accel tcg,thread=single,tb-size=1024
-cpu Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt
-smp 2,sockets=1,cores=2,threads=1
-m 4096
```

macOS needs its own firmware, OpenCore/SMC and boot disk, so boot peripherals
are not identical. Record the actual common options in a JSON manifest with
`qemu_version`, `machine`, `accelerator`, `cpu`, `smp`, and `memory_mb`. The
runners add the source SHA-256, compiler flags, and workload settings. Do not
add unrecorded timing options such as `-icount`. Run timing workloads in
sequence after macOS finishes booting; preserve the raw samples, including
outliers. Other sessions on the host can still introduce noise.

With GNU GCC and Apple's development tools inside macOS:

```sh
python3 tests/alloc-bench/run-macos.py \
  --port 22322 --user vinix --identity /path/to/private-guest-key \
  --gcc /opt/local/bin/gcc-mp-14 \
  --vm-config /path/to/actual-qemu-config.json \
  --state-dir build/alloc-macos \
  --iterations 200000 --samples 7
```

If the macOS guest lacks Apple's assembler/linker, `--guest-sdk` and
`--host-sdk` select a documented fallback: **GNU GCC in the guest compiles C
to assembly**, then the host's Apple tools assemble/link it for x86_64 macOS
10.15; the executable runs only in the guest. The guest SDK needs compatible
Darwin headers. The manifest records both build stages. Example additions:

```text
--guest-sdk /tmp/bench-sdk
--host-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
```

Use the corrected precise clock for comparisons. The recommended 200,000
base iterations give long samples even when allocation reuses cached memory;
large allocations, mmap and pipes use 10,000 pairs per sample. The short
mode is for smoke testing.

## Direct kernel workload

The shared V sampler uses only freestanding integer headers and fixed
stack buffers. Generate its C artifact with the same V compiler revision,
then compile that artifact with genuine GCC 14 on both targets. On Vinix, copy
the sampler and wrapper changes into the isolated worktree, then build the
kernel with the final benchmark configuration before replacing its sampler
object with the cross compiler:

```sh
cd /absolute/worktree/kernel
make clean
make ARCH=x86_64 VFLAGS='-d heap_c_benchmark -d heap_selftest'
x86_64-linux-musl-gcc -std=c11 -O2 -Wall -Wextra -Werror \
  -fno-builtin -ffreestanding -fno-stack-protector -mno-red-zone \
  -mno-80387 -mno-mmx -mno-sse -mno-sse2 -fno-PIC -mcmodel=kernel \
  -nostdinc -isystem freestnd-c-hdrs -MMD -MP \
  -I c -c obj/heap_benchmark.c -o obj/heap_benchmark.c.o
make ARCH=x86_64 VFLAGS='-d heap_c_benchmark -d heap_selftest'
```

Use the repository's normal architecture-appropriate build tools for both
`make` invocations, preserving every build option between them. The GCC object
must remain newer than its generated source, header, `GNUmakefile` and active
configuration stamp. A changed configuration can rebuild it with the normal
kernel compiler. Inspect `make -n` before the final relink and retain the GCC
command; verify `KALLOC-META compiler=gcc` in the resulting log.
The runner accepts an already built kernel. Its source hash and prescribed
flags are build requirements, not authenticated binary provenance; retain
the compiler command and verify the kernel came from that build. The runner
validates the complete three-phase sampler output before reporting success.

```sh
python3 tests/alloc-bench/run-kernel-vinix.py \
  --kernel /absolute/worktree/kernel/bin/vinix \
  --cc /path/to/x86_64-linux-musl-gcc \
  --state-dir build/kernel-alloc-vinix
```

The direct-kernel runner defaults to one vCPU on both guests, with the other
common QEMU options unchanged. Vinix's secondary CPUs spin waiting for the
scheduler during this boot-time test; two vCPUs under single-thread TCG cause
large timing variance. `--cpus` can select another count, which must also be
used by macOS. The runner boots a tiny untimed init and terminates its private
VM after `KALLOC-DONE`. Its manifest records the
generated sampler hash, ABI-header hash, kernel hash, common compiler flags,
and execution context. Comparisons reject a mismatched generated artifact
or header.
On macOS, the generated V sampler supplies kext start/stop functions.
`compile-v-sampler.py --header /path/to/sampler.h /path/to/sampler.c` derives
their public declarations directly from those V exports. The old five-line
declaration-only C input is retired with zero algorithm credit.
`macos-kext-info.c` supplies the kmod ABI descriptor,
and `build-macos-kext.py` creates the bundle and records exact build commands:

```sh
python3 tests/alloc-bench/build-macos-kext.py \
  --gcc /opt/local/bin/gcc-mp-14 \
  --vm-config /path/to/actual-one-cpu-qemu-config.json \
  --state-dir build/kernel-alloc-macos
```

This packager needs Apple's assembler/linker. If those are available only on
the host, generate the sampler once and compile it plus the unchanged kmod ABI
descriptor to assembly with the guest's GCC and the
recorded common flags, transfer assembly while the guest disk is unmounted,
then assemble/link on the host and return the kext to the disposable guest.
Record target-specific assembly/link flags separately from common C flags.
Use a disposable guest for diagnostic-kext setup.

Compare complete direct-kernel logs with:

```sh
python3 tests/alloc-bench/compare-kernel.py \
  build/kernel-alloc-vinix/serial.log build/kernel-alloc-macos/serial.log
```

## Compare and verify

```sh
python3 tests/alloc-bench/compare.py \
  build/alloc-vinix/serial.log build/alloc-macos/serial.log
python3 tests/alloc-bench/compare_test.py
```

The comparator recomputes medians from raw timing records, checks completion,
all six workloads, sample uniqueness, checksums, sizes/counts, GCC major
versions, and recorded common QEMU settings/source/flags. GCC minor-version
differences are disclosed. Missing or mismatched runs fail; `--allow-mismatch`
prints explicitly diagnostic ratios and still returns a failing status.
Configuration validation checks recorded values; it cannot authenticate a
hand-written manifest. TCG ratios are measurements of these workloads in the
emulator, not native CPU cycles or universal allocator performance.
