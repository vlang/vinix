# AArch64 QEMU core regression

This test boots a freshly built Vinix kernel with a static test program as PID
1 and a disposable 64 MiB EXT2 `/root`. It checks secure random initialization,
copy-on-write fork, cached EXT2 I/O and shared mappings, synchronization,
namespace persistence, permissions, file locks, resource limits, inotify,
affinity, priority, and resource accounting.

The runner boots twice against the same disposable EXT2 image. The first boot
synchronizes a marker through the shared page cache; the second boot remounts
the volume and verifies the marker before removing the temporary VM state.

Build the AArch64 userland once to provide the musl test sysroot, then run:

```sh
./scripts/build-userland-aarch64.sh
tests/qemu-core/run.sh
```

Set `VINIX_QEMU_CORE_NO_BUILD=1` to reuse `kernel/bin/vinix`, or
`VINIX_QEMU_TIMEOUT` to change the default 300-second deadline. The boot and
EXT2 images are isolated in temporary directories and removed after the run.

The same test runs on amd64 against the kernel `build-amd64.sh` built, in a
throwaway ISO booted once under TCG with four CPUs. amd64 has no persistent
volume here, so the second, persistence-checking boot is skipped. It adds
the x86-64 ABI's own calls: utime, utimes, futimesat and getdents, and the TLS
descriptors and LDT of set_thread_area and modify_ldt, with 32-bit code run
from an LDT code segment:

```sh
V=/path/to/v ./scripts/build-amd64.sh --no-userland --no-iso
tests/qemu-core/run.sh amd64
```
