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

The same test runs on amd64 against the kernel `scripts/build-amd64.sh` built, in a
throwaway ISO booted once under TCG with four CPUs. amd64 has no persistent
volume here, so the second, persistence-checking boot is skipped. It adds
the x86-64 ABI's own calls: utime, utimes, futimesat and getdents, and the TLS
descriptors and LDT of set_thread_area and modify_ldt, with 32-bit code run
from an LDT code segment:

```sh
V=/path/to/v ./scripts/build-amd64.sh --no-userland --no-iso
tests/qemu-core/run.sh amd64
```

The signal-disposition, first-touch and interrupted-read fixtures are compiled
from `signalfixture`, `touchfixture` and `restartfixture` V modules. The normal
builder generates their ephemeral C and declaration headers outside the
checkout and links them with the remaining test program. All 61 original
`CHECK` sites keep their predicates and logical source line numbers; the shared
`reap_ok` body remains unchanged.

Independent comparisons recover the original fixture from commit
`bbf1e243e21ab58b46a4853c0e88383ff45b290a`, verify its Git blob and SHA256, and
materialize it only outside the checkout. Run the host sanitizer comparisons
with the actual host architecture, or `--arch amd64` on a Mac with Rosetta:

```sh
python3 tests/qemu-core/test-signalfixture.py /tmp/qemu-signal --arch arm64
python3 tests/qemu-core/test-touchfixture.py /tmp/qemu-touch --arch arm64
python3 tests/qemu-core/test-restartfixture.py /tmp/qemu-restart --arch arm64
```

The host touch comparison uses real mappings, forks, pipes, protection and
threads. Its V provider supplies the POSIX barrier missing from Darwin and
an explicit Linux free-memory timeline. The native comparison uses the target
SDK's actual barrier, memory accounting and `MAP_POPULATE` behavior.

Each tool also accepts `--native-build --arch arm64` or `--native-build --arch
amd64` to compile its paired original/V guest. Set `VINIX_AARCH64_SYSROOT` and
`CC` for ARM, or `CC_AMD64` for x86. Set `VINIX_V_COMPILER` to select the V
compiler. For example, after building the native signal comparison:

```sh
python3 tests/qemu-core/test-signalfixture.py /tmp/qemu-signal-native \
  --native-build --arch arm64
python3 tests/kernel-gaps/run.py --arch aarch64 \
  --prebuilt-init /tmp/qemu-signal-native/signal-init \
  --kernel-dir /path/to/kernel --state-dir /tmp/qemu-signal-vm \
  --expect 'QEMU CORE SIGNAL DIFFERENTIAL PASS: 6 native signal/fork cases' \
  --fail Assertion --no-network --timeout 300
```

The signal and restart comparisons deliberately inject `EAGAIN` at both fork
positions. They compare the original and translated return value, errno and
fork count, so matching original `QEMU CORE FAIL` diagnostics are expected for
those inputs. The final differential verdict and assertions determine success.
These bounded comparisons supplement the full feature and persistence runner.
