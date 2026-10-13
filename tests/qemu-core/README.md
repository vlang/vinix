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

`run.sh` invokes the native V `run-vm` controller. Its direct ARM options are
`--init`, `--initramfs`, `--state-dir` and `--timeout`; `--root` can select the
repository supplying `scripts/run-aarch64.sh`. For amd64 use `--arch amd64`,
`--iso`, `--qemu`, `--firmware` and `--cpus`. The Python frontend and child
launch bridge are retired. Five saved allocation-campaign runners also have
native `run-vm` entry points, retaining each captured CPU model. Existing saved
logs and historical provenance records are unchanged; recover their original
Python bytes from the Git source pinned in `native-vm-translation.json`.
See [native VM controller qualification](native-vm-tools.md).

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

The signal-disposition, first-touch, interrupted-read, nanosleep-remainder and
blocked-thread exit/exec fixtures are compiled from `signalfixture`,
`touchfixture`, `restartfixture`, `nanosleepfixture`, `blockedfixture`,
`pollfixture`, `epollfixture` and `intfixture` V modules. The normal builder
generates ephemeral C and declaration headers outside the checkout and links
them with the remaining test program. All 98 original `CHECK` sites keep their
predicates and logical source line numbers; the shared
`reap_ok` body remains unchanged.

Independent comparisons recover the original fixture from commit
`bbf1e243e21ab58b46a4853c0e88383ff45b290a`, verify its Git blob and SHA256, and
materialize it only outside the checkout. Run the host sanitizer comparisons
with the actual host architecture, or `--arch amd64` on a Mac with Rosetta:

```sh
tests/qemu-core/test-signalfixture /tmp/qemu-signal --arch arm64
tests/qemu-core/test-touchfixture /tmp/qemu-touch --arch arm64
tests/qemu-core/test-restartfixture /tmp/qemu-restart --arch arm64
tests/qemu-core/test-nanosleepfixture /tmp/qemu-nanosleep --arch arm64
tests/qemu-core/test-blockedfixture /tmp/qemu-blocked --arch arm64
tests/qemu-core/test-pollfixture /tmp/qemu-poll --arch arm64
tests/qemu-core/test-epollfixture /tmp/qemu-epoll --arch arm64
tests/qemu-core/test-intfixture /tmp/qemu-int --arch arm64
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
tests/qemu-core/test-signalfixture /tmp/qemu-signal-native \
  --native-build --arch arm64
tests/kernel-gaps/run-native --arch aarch64 \
  --prebuilt-init /tmp/qemu-signal-native/signal-init \
  --kernel-dir /path/to/kernel --state-dir /tmp/qemu-signal-vm \
  --expect 'QEMU CORE SIGNAL DIFFERENTIAL PASS: 6 native signal/fork cases' \
  --fail Assertion --no-network --timeout 300
```

The signal and restart comparisons deliberately inject `EAGAIN` at both fork
positions. They compare the original and translated return value, errno and
fork count, so matching original `QEMU CORE FAIL` diagnostics are expected for
those inputs. The final differential verdict and assertions determine success.
The nanosleep comparison also injects `EIO` at signal registration and `EAGAIN`
at fork, then compares its original checks, return value, errno and API counts.
The blocked-thread comparison retains real blocked reads, process exit and exec,
the original 100-ms settle and unchanged exec-memory probe. Six independent cases
compare fork/pipe/thread/exec failure statuses as well as return values and errno.
On the host, only Linux auxv inputs and the executable path are supplied by the
provider; native guests use actual `/sbin/init`, `/proc/self/auxv` and `getauxval`.
The poll comparison uses real pipe and poll calls with the SDK pollfd/count ABI;
eleven cases cover API errors, both close failures and event/byte sentinels.
The epoll comparison preserves the native packed event stride, data and count
ABI. Fifteen cases cover every API error, event/data/byte sentinels and all
three close failures. Host inputs use real pipe readiness through poll; native
guests use actual epoll calls.
The syscall C-int comparison preserves the original zero-extended directory word
and native variadic argument widths. Three cases compare syscall/close failures
and argument bits; an additional nonzero argument probe checks the instruction
ABI adapter. The host uses native openat while guests call actual syscall.
These bounded comparisons supplement the full feature and persistence runner.

The build controllers run in `fixturehost` V code: input staging, immutable
oracle checks, source ranges, compiler flags, allocator guards and receipts all
use the native implementation. The eight comparison commands and fixture
generator invoke V directly through `fixturecli`, retaining the original CLI
modes and architecture defaults. Their Python entry points are retired.
`compile-basefixture`, `test-basefixture` and `test-futexfixture` also invoke V
directly. Their generator, host comparison and paired futex guest build preserve
the pending fixture policies; the shared Python import bridge is retired.
The base receipt identifies the native host through `uname -srm`.
The independent `test.c`, fixture assertions and guest deadlines are unchanged.
Controller qualification compares generated sources, headers, objects and
logs against frozen Python controls on ARM64 and x86-64, and links both SDK
targets. Mach-O comparisons validate and account for linker UUIDs, object
timestamps and their derived signature hashes; raw executable hashes remain
in each receipt. This host-tool qualification does not establish a new kernel
or guest result.

## Pending migration checkpoint

The committed `.pending` files preserve unfinished base/memory and futex
fixture work. They are not selected by `run.sh` or the normal fixture builder;
the corresponding bodies remain in `test.c`. These scopes receive **zero
completed migration credit** until their native comparisons and normal-runner
integration are complete. Original checks, workloads and deadlines remain
unchanged. Their oracle is the same immutable `bbf1e243` source described above.

The comparison tools are maintained native commands even while these fixture
bodies await integration. Use `tests/qemu-core/test-basefixture /tmp/base-check`
for the base/memory host comparison, or
`tests/qemu-core/test-futexfixture /tmp/futex-check --arch=arm64` for futex.
The latter retains `--prepare-only`, `--guest` and `--native-build` modes.
`tests/qemu-core/compile-basefixture /tmp/base-sources --module-only --arch=amd64`
generates only the V module/header; omitting `--module-only` additionally recovers
the pinned C oracle, original declarations and full comparison source.
Recovered originals remain outside the checkout. `VINIX_QEMU_BASE_GENERATOR`
may select a prebuilt native generator for qualification.

The base/memory scope covers 270 original lines and preserves all 76 `CHECK`
expressions and logical lines. Its current inputs match the cached ARM host
ASan/UBSan comparison and ARM/x86 SDK build receipts. Earlier ARM full feature
and persistence C/V comparisons passed. Native x86 completion remains blocked:
the original full control passed the memory groups, then failed the untouched
alarm assertion at original line 2239, observing nine timer firings against the
required ten. Its paired V run was not launched. The earlier `max`/TCG control
also exhausted its outer allowance during the original joined-thread workload;
neither result establishes a cause or permits weakening the test.

The futex scope covers 18 original lines and preserves all five `CHECK`
expressions and logical lines. Fresh 2026-10-07 host ASan/UBSan comparisons
passed seven independent cases on both actual host ABIs. Host providers model
the atomic word operations and supply the target SDK's syscall number; guest
providers invoke the real syscall. Cached ARM/x86 SDK links exist, but complete
native validation of the current exact inputs and normal-runner integration
remain pending. Historical guest logs are retained as evidence, including an
x86 run whose original diagnostic line tags predate the final correction.

Local checkpoint evidence is under
`~/.cache/vinix-c-to-v/firstparty-only-20261006-011023`: the
`pending-commit-oct07/qemu-core-pending-source-audit.json` input/check audit,
`pending-commit-oct07/futex-host-{arm,x86}/validation.json` fresh host receipts,
`qemu-core-host270-final/validation.json` base host receipt,
`qemu-core-native270-final/validation.json` SDK receipt, and
`qemu-core-qemu64-config.json` unresolved original native control. These local
receipts and generated binaries are not maintained fixture sources.
