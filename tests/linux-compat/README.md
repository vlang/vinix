# Linux compatibility qualification

The maintained V controller snapshots a matching, already built ELF64 kernel
and each V fixture before compiling or booting. Both architectures use the
existing native guest supervisor and disposable images. Every requested marker
must pass; bad pointers, errno, compiler failure, panic, timeout and late failure
remain failures. Sources, init/ISO/kernel hashes, receipts and raw serial logs
stay in the required fresh artifact directory, including on failure.

```sh
tests/linux-compat/run --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /path/to/fresh-arm
tests/linux-compat/run --arch x86_64 --kernel-dir /path/to/x86/kernel --state-dir /path/to/fresh-x86
```

`--cases bpf,access,open,mmap,runtime` selects the tests; `--timeout` sets each guest's
deadline. The kernel is never rebuilt implicitly. Build in separate worktrees
and supply the ARM musl sysroot through `VINIX_AARCH64_SYSROOT` when necessary.

- `bpf` verifies ENOSYS for unavailable program operations and untouched query
  buffers; loading or attaching a policy cannot return a dummy success.
- `access` checks empty paths, exact errors, execute permission, O_PATH/deleted
  files, pipes, real/effective UID differences and nonempty AT_EMPTY_PATH paths.
- `open` checks open_how size/extensions, flags, invalid pointers, O_PATH,
  link inode descriptors for regular, dangling and procfs links with
  O_PATH|O_NOFOLLOW, and EBADF on reads through those descriptors,
  mutually exclusive/unknown constraints, NO_SYMLINKS and NO_MAGICLINKS on
  intermediate/final/nested/procfs links and creation, and final link handles.
  Trailing slashes require directory resolution even with O_PATH|O_NOFOLLOW;
  failed O_CREAT requests cannot leave regular files behind.
  Exclusive creation returns EEXIST for existing final symlinks, including
  dangling targets and supported link constraints, without creating a target.
  Plain O_CREAT follows dangling final links, including relative chains, and
  verifies target contents/mode. Link restrictions and mount boundaries still
  apply, and failed requests leave no target.
  Plain open/openat ignore creation, truncation and access flags with O_PATH;
  data stays intact and descriptor flags remain correct. openat2 rejects them.
  NO_XDEV checks tmpfs and same-filesystem bind mounts, alias-relative opens,
  '..', absolute symlink targets, creation and procfs descriptor jumps.
  BENEATH, IN_ROOT, CACHED and combinations requesting them return EOPNOTSUPP;
  this does not qualify containment or cache-only lookup.
- `runtime` checks four concurrent pthreads, isolated libc errno/TLS and keys,
  64-bit atomic increments, SSE2/NEON across scheduling, auxv/sysconf page sizes
  and an actual RW-to-RX JIT function. It prints pointer width and page size.
  It also verifies file offsets past 8 GiB, normalized CLOCK_REALTIME and a
  nonblocking timerfd deadline 2^32 seconds into the future, including through
  the i386 libc's time64 wrappers.
  `--once` makes a staged runtime fixture exit after testing instead of waiting
  as PID 1. It is a native musl test until run through a foreign runtime.
- `mmap` checks that MAP_ANONYMOUS ignores every descriptor, including an
  invalid positive value and a zero-extended -1, and that file-backed mappings
  consume only the low signed C-int descriptor. Invalid file descriptors still
  return EBADF. The test writes anonymous pages and verifies mapped file data.

The [coverage matrix](../../docs/linux-posix-compatibility.md) separates missing
interfaces from implemented behavior and lists unsupported dependencies. The
application workload command is V as well:

```sh
build-support/run-v-tool.sh tools/linux-compat/workloads/main.v --host --work=/path/to/fresh-evidence --cases=sqlite,media
# Inside Vinix, installation can be included explicitly:
linux-compat-workloads --work=/tmp/compat-evidence --install
```

Build the workload command for the target userland and stage it as
`linux-compat-workloads`. It invokes applications with literal argument vectors,
bounded output/deadlines and process-group cleanup; it never runs Python.
SQLite tests a WAL transaction and integrity/reopen; FFmpeg checks actual encoded
frames; Gnumeric saves and reopens cell data; browsers render real local content;
existing Go/Java application sources and a V compile/file workload test runtimes;
BusyBox (or Alpine's BusyBox Extras) runs and retires an HTTP service with a
unique response, recording its response and termination. Missing
executables are `unsupported`, nonzero exits/timeouts are `failed`, and either
causes a failing suite exit. There is no sandbox-disable fallback.

The application guest init supplies the usual login environment (HOME, user
names, UTF-8 locale and XDG_RUNTIME_DIR). Prepared office roots also need real
fonts; DejaVu and the Alpine Gnumeric dependency closure qualify the native
save/reopen workload. Archive and guest-input hashes accompany the dated
results, including the initial missing-font failure. Extraction remains
distinct from installed-system package transactions and desktop integration.

The Go case sets the installed `/usr/lib/go` root when present, a private build
cache and `CGO_ENABLED=0`, matching the existing pure-Go smoke workflow. Child
environment overrides and removed variable names are recorded per command and
cleared between workloads; inherited environment values are not serialized.

The Java case compiles the existing input and runs it from a class directory
and a newly created JAR, with a bounded heap. HotSpot requires writable
executable code pages: its children request VINIX_ALLOW_WX=1, which still
requires Vinix's [privileged launch or wxallowed mount policy](../../docs/mount-execution-policy.md).
That requirement is recorded in command receipts; ordinary unprivileged
launches without the administrator's policy are not qualified.

`--host` labels host-only evidence and prohibits installation. `--path` chooses
native AArch64/x86-64 or AArch64's translated x86-64/i386 launcher. Native paths
must match the driver architecture. `--runtime-probe` chooses the corresponding
staged fixture. The existing Go and Java inputs assert ARM64 and are explicitly
unsupported on other paths; translated HTTP service integration is also unqualified.
Portal discovery and games requiring licensed assets remain explicit unsupported
results until real chooser/save and title-specific GPU/input/audio/save tests
exist. The JSON report always keeps full lifecycle qualification false: these
workloads alone do not certify package updates, desktop integration, systemd,
Flatpak/Snap or every glibc software dependency.

Cross-build static musl executables with the maintained V builder. It generates
C through V, invokes the selected target compiler and verifies the ELF machine
and class. Production mode embeds the Go/Java application sources in the driver
so they are available inside the guest. The output directory must be fresh;
`build.json` records sources, generated C, command arguments and executable hashes.
Both modes currently name
their output `linux-compat-workloads`, so keep the driver and probe in different
directories:

```sh
build-support/run-v-tool.sh tools/linux-compat/build/main.v aarch64 /path/to/fresh-driver
build-support/run-v-tool.sh tools/linux-compat/build/main.v aarch64 /path/to/fresh-probe --runtime-probe
build-support/run-v-tool.sh tests/linux-compat/run-apps.v --arch aarch64 --kernel-dir /path/to/arm/kernel --state-dir /path/to/fresh-apps --rootfs /path/to/prepared-root --workloads /path/to/fresh-driver/linux-compat-workloads --runtime-probe /path/to/fresh-probe/linux-compat-workloads --cases sqlite,server,runtime
```

Repeat with `x86_64` and its matching kernel/root. The ARM builder uses
`VINIX_AARCH64_SYSROOT` and `CC_AARCH64` (default clang); x86 uses `CC_AMD64`
(default x86_64-linux-musl-gcc). `VINIX_V_COMPILER` selects V. The
`i386 --runtime-probe` path uses `CC_I386` (default i686-linux-musl-gcc), or a
clang-compatible compiler when `VINIX_I386_SYSROOT` names an i386 musl SDK and
`VINIX_I386_BUILTINS` names its compiler-rt builtins archive. In the latter mode
the receipt also hashes the SDK CRT, libc and builtins; host GCC libraries are
excluded. SSE2 intrinsics let this fixture build through V's i386 C backend.

```sh
VINIX_I386_SYSROOT=/path/to/i386-sdk VINIX_I386_BUILTINS=/path/to/libclang_rt.builtins-i386.a build-support/run-v-tool.sh tools/linux-compat/build/main.v i386 /path/to/fresh-i386-probe --runtime-probe
```

The application controller takes a prepared guest root with matching programs
and libraries, snapshots the kernel/driver/probe and init source, and preserves
guest symlinks literally. It boots without networking or implicit installation.
Root file/mode/link hashes, input receipts, serial output and extracted
`guest-report.json` stay in the state directory, including failed/unsupported
results. To test translation, select `--path translated-x86_64`, supply a
native ARM driver and an x86-64 probe, and stage the existing translator/private
runtime in the prepared root. The static probe uses `run-x86-64 --direct`;
dynamic applications use the normal private-loader path. A passing static probe
does not qualify glibc loaders or all translated applications.

Select `--path translated-i386` with an ELF32 probe to test 32-bit translation.
The static probe invokes `VINIX_I386_EMULATOR` (default `/usr/bin/qemu-i386`)
directly with the private runtime root and the launcher's W^X opt-in, because a
static ELF cannot be passed to the wrapper's dynamic musl loader. That environment
is confined to the child; ordinary i386 applications still use `run-x86-32`.
The dated [qualification report](../../docs/linux-posix-qualification.md) contains
passing native ELF64 and translated 32-bit runtime receipts. Native ELF32/x32 entry,
arbitrary glibc applications, the complete large-file/time ABI and debugger operations remain separate
checks beyond the qualified lseek/clock/timerfd predicates.

Unmodified GNU libc can be tested independently with the pinned Debian SDK:

```sh
build-support/run-v-tool.sh tools/linux-compat/sdk/main.v arm64 /path/to/fresh-sdk
VINIX_GLIBC_SYSROOT=/path/to/fresh-sdk/sysroot build-support/run-v-tool.sh tools/linux-compat/build/main.v aarch64 /path/to/fresh-gnu-probe --runtime-probe --libc=glibc
```

Use `amd64`/`x86_64` or `i386` for the other SDK/probe pairs. The SDK verifies
the checked-in archive hashes, then extracts headers, CRT and libraries without
executing package scripts. GNU builds use their own headers and dynamic loader;
i386 enables _FILE_OFFSET_BITS=64 and _TIME_BITS=64. Link receipts retain the
actual libc, loader, libm, libgcc and CRT hashes.

Stage those libraries in the prepared guest's
`/usr/libexec/vinix-glibc/ARCH/lib`. Native probes need the matching GNU
interpreter at `/lib/ld-linux-aarch64.so.1` or
`/lib64/ld-linux-x86-64.so.2`. For translation, each private `ARCH` root needs
its interpreter at the normal Linux path: `/lib64/ld-linux-x86-64.so.2` or
`/lib/ld-linux.so.2`. Pass `--runtime-libc glibc` to the application controller
(or `--runtime-libc=glibc` to the guest driver). Translated probes use QEMU-user
directly with this private root, scoped W^X opt-in and removed foreign library
environment variables. The driver requires the probe's GNU libc version marker
as well as every runtime predicate. Dated receipts cover both native and both
translated paths; these checks do not qualify every GNU application.

Select `--cases debugger` with either translated path and its matching runtime
probe to qualify the QEMU-user GDB remote stub. The V client verifies register
and instruction-memory reads, stack memory write/read/restore, a software
breakpoint, single stepping and successful continuation through every runtime
predicate. The report records the exact translator/probe hashes, addresses,
register-packet hash and child cleanup. The stub listens on guest loopback port
19016; packets and output are bounded, and socket operations have deadlines.
Native paths report unsupported because ptrace has no syscall dispatch.
Source-level symbols, unwinding, core dumps and JIT debugger registration need
their own qualification.

Host verification of the report generator and timeout/nonzero-exit handling:

```sh
v -cc cc test tools/linux-compat
```

If the local V compiler reports missing cached `_v3_lit_*` literals after edits,
use a fresh `V3CACHE` directory or `v -nocache -cc cc run` for the host tool.
