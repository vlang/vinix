# Allocation benchmark in Vinix and macOS

`bench.c` runs identical single-thread C workloads on both guests. Compile
with genuine GNU GCC: Apple's `/usr/bin/gcc` is Clang, and the benchmark records
that distinction. Results count an allocation/free pair, a map/unmap pair, or
a pipe/create/close pair, rather than counting each half separately.

The workloads are 64-byte malloc reuse, mixed-size 64-object batches,
256 KiB malloc with one verified byte per 4 KiB, anonymous 4 KiB mmap/unmap
without a touch, 256 KiB mmap/touch/unmap, and pipe creation/closure. Every
workload has a full warmup and 5–31 recorded samples. Payload reads and writes
are volatile; checksums must match. `-fno-builtin` also prevents allocation
calls from being removed. Logs identify the compiler, OS, architecture, native
page size, clock resolution, counts, size distribution, and access stride.

## What the measurements mean

`malloc` compares musl's user-space allocator on Vinix with Apple's libmalloc.
`mmap` measures the OS's VM allocation and teardown policy, including physical
allocation and page faults. `pipe` includes syscall and kernel-object costs.
These are useful allocation workloads, but none directly times XNU's `kalloc`
or Vinix's kernel slab allocator.

Vinix's existing `-d heap_benchmark` workload directly exercises its kernel
heap. Its optional `-d xnu_zone` backend is a partial XNU-inspired port running
inside Vinix; it is **not a macOS guest**. See
[the earlier port comparison](../../docs/xnualloc/BENCHMARK.md).

Vinix currently pre-populates small anonymous mappings; large reservations
and private mappings accounted to a cgroup can use its fault path. A timing
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
  VINIX_ALPINE_DEVTOOLS=1 ./build-userland-amd64.sh
```

Then run:

```sh
python3 tests/alloc-bench/run-vinix.py \
  --kernel /absolute/worktree/kernel/bin/vinix \
  --sysroot build/alloc-userland/staging \
  --state-dir build/alloc-vinix \
  --iterations 200000 --samples 7
```

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

Vinix's 1 ms reported clock resolution needs reasonably long samples. The
recommended 200,000 base iterations reduce quantization compared with
`--quick`; large allocations, mmap and pipes use 10,000 pairs per sample.
The short mode is for smoke testing.

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
