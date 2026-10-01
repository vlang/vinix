# Linux i915 compatibility layer

**Status: initial kernel API support, not a working Intel graphics driver.**
Vinix does not yet compile, link or bind the complete Linux i915 driver.
The existing firmware framebuffer remains the display backend.

The initial hardware target is the Tiger Lake-LP GT2 GPU in the Core
i5-1135G7. The current PCI filter accepts only `8086:9a49`, with a display
class matching Linux's own Tiger Lake table. Confirm the actual device with
`lspci -nn -s 00:02.0`; CPU model information alone is not a PCI identity.

## Unmodified upstream sources

`kernel/linuxkpi/upstream.json` pins Linux **6.6.157**, its kernel.org archive
SHA256, and a separately pinned manifest of every imported file. Fetch with:

```sh
python3 kernel/linuxkpi/upstream.py fetch
python3 kernel/linuxkpi/upstream.py verify
```

The complete upstream `drivers/gpu/drm/i915` directory, Linux headers and
selected library sources are imported below
`third_party/linux-i915/linux-6.6.157`. The source archive and generated tree
are excluded from Git. Compatibility changes belong in
`kernel/linuxkpi/include` or Vinix's native backend; do not patch the driver.
Verification rejects changed, added, missing or symlinked source files, and
rejects a rewritten manifest. Original copyright notices, `COPYING` and
`LICENSES` are retained. Unrelated netfilter headers are excluded because
their case-distinct filenames cannot coexist on default macOS filesystems.

The current build compiles and links unmodified Linux `lib/list_sort.c`,
`lib/sort.c`, `lib/rbtree.c` and i915's `i915_memcpy.c`. The last file is a WC
memory-copy component, not GPU initialization or command submission. Importing
the complete i915 source tree is not evidence that the driver runs.

## Implemented APIs

- Linux integer types, error pointers, overflow helpers and compiler macros.
- Linux list/tree/sort APIs using the actual upstream headers and algorithms.
- 32/64-bit, `atomic_long`, raw and conditional atomic operations and memory
  barriers. Linux's generated API wrappers and compiler helpers stay upstream;
  the architecture primitives use compiler atomics. Compatibility C uses
  `-fwrapv`, as required by Linux's signed-overflow convention.
- Upstream `refcount_t` and ordinary `kref_get`/`kref_put`, including saturation,
  final-release ordering and spinlock release helpers. Mutex release helpers
  remain unresolved until the sleepable mutex backend exists.
- Spinlocks, nested IRQ save/restore and scheduler preemption guards. Lock
  spinning continues to answer Vinix's TLB shootdowns. IRQ flags belong to
  the caller, not to shared lock storage.
- `kmalloc`, `kzalloc`, `kcalloc`, `kmalloc_array`, `kmemdup`, `krealloc`,
  `ksize` and `kfree`, including zero-size pointers, overflow/OOM handling
  and Linux allocation alignment. The initial backend uses contiguous
  physical pages, including for small allocations; it favors correctness
  over memory efficiency.
- Non-reclaiming allocation for `GFP_ATOMIC`, `GFP_NOWAIT`, `GFP_NOFS`,
  `GFP_NOIO` and callers with IRQs/preemption disabled. Only unrestricted
  sleepable allocations invoke Vinix's existing reclaimers. Zone-constrained,
  `__GFP_NOFAIL` and memory-cgroup-accounted allocations are not supported.
- A read-only target identity check against the unmodified Tiger Lake PCI
  table. This does not register an i915 device or change GPU registers.
- Boolean static branches without text patching; CPUID feature words 0 and 4.
- Kernel FPU borrowing that saves/restores the running thread's existing
  XSAVE/FXSAVE storage while preemption is disabled. The upstream i915 WC-copy
  component uses it for SSE4.1 copies; other CPU-feature words fail explicitly.

The compatibility build is opt-in, x86-64 only:

```sh
LINUXKPI=1 PROD=false ./build-amd64.sh --no-userland --no-iso
```

For a direct kernel build, pass `LINUXKPI=1` to `make -C kernel`; cross
compilation on macOS also needs the compiler/linker settings used by
`build-amd64.sh`. An out-of-tree build can set `LINUXKPI_SOURCE_DIR` to the
absolute imported source directory. The default and arm64 builds do not
enable the compatibility runtime. Enabling it currently runs self-tests and
reports the target GPU as **not bound**, because i915 compatibility is
incomplete.

## Verification

```sh
tests/linuxkpi/run.sh
python3 kernel/linuxkpi/audit.py
python3 tests/linuxkpi/run_vm.py \
    --kernel build-amd64-kernel/bin/vinix \
    --state-dir /tmp/vinix-linuxkpi-guest
python3 tests/linuxkpi/run_vm.py \
    --kernel build-amd64-kernel/bin/vinix \
    --cpu max,hypervisor=off --state-dir /tmp/vinix-linuxkpi-guest-sse
```

The host tests use ASan and UBSan. They exercise allocation failure and
preservation of the original buffer after failed `krealloc`, zero-fill,
alignment, list stability, red-black tree invariants, concurrent atomic/lock
operations and nested IRQ restoration. Refcount tests cover overflow/underflow
saturation, concurrent final release, and acquire/release publication.
Source-import tests cover modification, manifest tampering and archive path
traversal.

An enabled kernel runs the allocator/list/sort/tree/IRQ-lock tests 200 times
and verifies that the physical free-page count returns to its initial value.
It then holds preemption disabled with IRQs enabled until a real scheduler
interrupt defers a context switch. The WC-copy test checks FPU register/MXCSR
preservation, buffer alignment and aligned/unaligned copies. Upstream i915
disables acceleration when CPUID reports a hypervisor; the second TCG guest
disables that CPUID flag to exercise the actual SSE4.1 path. This is a CPU
memory-copy test, not a test against GPU WC-mapped memory.
The QEMU test requires all kernel test markers and a static Linux-ABI PID 1
marker on COM1. Use a kernel built with
`PROD=false` for serial diagnostics. The test creates its own guest and disk
image; its state directory must not already exist. `--no-linuxkpi` checks a
default kernel's Linux-ABI startup and verifies that the API layer is disabled.
The WC test also exposed and verified a fix to the initial x86 kernel-thread
stack: entry now reserves a return-address word to satisfy SysV alignment.

`audit.py` obtains the driver translation-unit list from the original Linux
Kbuild Makefile, with ACPI and fbdev enabled and optional self-tests/GVT off.
It attempts every translation unit and writes complete compiler diagnostics
to `build/linuxkpi/i915-audit.json`. An incomplete API layer makes this command
exit with status 1. The current result is **1/269** translation units passing.
Even a successful syntax audit would still require actual
object linking, unresolved-symbol checks and runtime/hardware testing.

## Remaining driver integration

The complete i915 build still fails. The next work includes the wider Linux
compiler/type/atomic interface and these substantial runtime subsystems:

1. Linux device/PCI registration and removal, configuration access and devres.
2. MMIO mapping with correct cache attributes, DMA/scatter-gather APIs,
   page/shmem management, GPU address spaces and TTM/GEM memory management.
3. Sleepable locks, completions, wait queues, workqueues, timers and RCU
   lifetime rules.
4. Linux IRQ registration, interrupt synchronization and safe GPU reset paths.
5. C DRM core integration, device nodes, file ownership, ioctl/mmap handling,
   DMA fences, sync objects and dma-buf lifetime handling. The existing V DRM
   interfaces are not the internal Linux C DRM API.
6. Firmware loading, ACPI OpRegion, power management and display/KMS services.
7. Build/link all original i915 objects with that layer, filter PCI binding
   to the confirmed target and boot on the physical Tiger Lake machine.
8. Validate command submission, framebuffer/display handoff, GPU resets,
   repeated process teardown and Alpine Mesa/libdrm compatibility on hardware.

QEMU's standard VGA adapter cannot validate an Intel driver. Physical Tiger
Lake hardware, or a properly isolated passthrough setup, is required for that
final validation. GPU support must stay marked incomplete until those checks
pass.

References: [Linux 6.6 stable sources](https://cdn.kernel.org/pub/linux/kernel/v6.x/),
[Linux kernel versus userspace interfaces](https://docs.kernel.org/process/stable-api-nonsense.html),
[i915 documentation](https://docs.kernel.org/gpu/i915.html).
