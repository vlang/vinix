# Linux/POSIX qualification, 2026-10-11

Section 15 remains partial. These are results for exact hashed binaries in
disposable QEMU guests, plus explicitly separate host checks. They do not
qualify every wired syscall or GNU libc API, every package runtime, desktop
integration or physical hardware. The disk-backed SQLite package lifecycle
below is qualified on both native architectures.

The initial kernels were built in isolated worktrees from `ea6c4189` with the three
Linux ABI fixes (`df484021`, `87611ce2`, `d9aee93e`). Concurrent changes in the
shared checkout were excluded from those builds. Kernel, fixture source,
init and image hashes are in the checked-in receipts under
[`tests/linux-compat/results/2026-10-11`](../tests/linux-compat/results/2026-10-11).
Use the [V qualification controllers](../tests/linux-compat/README.md) to
reproduce tests against another kernel; a new hash needs a new qualification.

Later `opath-*.json` receipts qualify an additional O_PATH|O_NOFOLLOW fix on
both native architectures, built on that isolated kernel baseline. The raw
fixture checks that regular, dangling, executable and pipe procfs links produce
descriptors for the symlink inode and reject reads with EBADF. Plain openat
and openat2 exercise the same behavior, following the
[Linux open contract](https://man7.org/linux/man-pages/man2/open.2.html).

| Check | Native AArch64 | Native x86-64 | x86-64 translated on AArch64 | i386 translated on AArch64 |
| --- | --- | --- | --- | --- |
| BPF load/attach/detach/query returns ENOSYS without changing user buffers | passed | passed | not tested | not tested |
| faccessat2 permissions, exact errors, empty/deleted/O_PATH paths and credentials | passed | passed | not tested | not tested |
| openat2 ordinary opens and exact validation/rejection of unsupported resolution | passed | passed | not tested | not tested |
| openat2 NO_SYMLINKS/NO_MAGICLINKS lookup, creation and final O_PATH link handles | passed | passed | not tested | not tested |
| openat2 NO_XDEV including bind aliases, '..', absolute and magic-link targets | passed | passed | not tested | not tested |
| Concurrent pthread TLS/errno/keys, 64-bit atomics, SIMD and RW-to-RX JIT | passed | passed | passed | passed |
| File offsets past 8 GiB, normalized clock and time64 timerfd deadline roundtrip | passed | passed | passed | passed |
| auxv/sysconf page size, pointer width | 16 KiB, 64 bits | 4 KiB, 64 bits | 4 KiB, 64 bits | 4 KiB, 32 bits |
| Same runtime predicates with unmodified Debian glibc 2.36 | passed | passed | passed | passed |
| Remote register/memory reads, stack mutation/restoration, breakpoint and step | unavailable | unavailable | passed | passed |
| Ordinary ext2 mount, source symlink, readonly alias, errors and remount content | passed | passed | not tested | not tested |

BPF is unavailable: passing its error regression means callers can discover
that limitation. The later `link-policy-*.json` receipts test kernels that add
NO_SYMLINKS and NO_MAGICLINKS to the O_PATH baseline. Constraints propagate
through the actual lookup, nested targets and creation retries; forbidden
link traversal returns ELOOP. NO_MAGICLINKS permits ordinary links, including
/proc/self, and final O_PATH|O_NOFOLLOW handles preserve symlink inodes.
BENEATH, IN_ROOT and CACHED still return EOPNOTSUPP, including mixed
requests. Containment and complete sandbox support remain unqualified. The
[Linux openat2 contract](https://man7.org/linux/man-pages/man2/openat2.2.html)
defines these distinctions. The runtime fixture covers NEON or SSE2, not the complete AVX/ARM feature
set, native debugger operations, signal delivery through translation or every JIT.
The x86-64 translated result uses the existing QEMU-user launcher in `--direct` mode
with a static musl x86-64 fixture, not a glibc application runtime.

The `trailing-*.json` native receipts add directory requirements for open paths
ending in a slash. Regular files return ENOTDIR, dangling links return ENOENT,
directory links resolve even with O_PATH|O_NOFOLLOW, and NO_SYMLINKS still
returns ELOOP. O_CREAT rejects a final slash with EISDIR after validating the
prefix; the fixture verifies that rejection leaves no created file.

The `xdev-root-*.json` receipts additionally qualify NO_XDEV on both native
architectures. Entering tmpfs or a bind alias, leaving a mount with '..',
an absolute symlink target crossing mounts and a procfs descriptor jump return
EXDEV. Relative access and creation inside the held mount succeed; a final
O_PATH|O_NOFOLLOW magic link remains a link handle. The test checks same-filesystem
bind boundaries by mount identity and verifies blocked creation leaves no file.
The effective boot root is established before checking subsequent transitions.

The final `followup-*.json` native receipts run all four ABI/runtime fixtures
after the additional exclusive-create fix. O_CREAT|O_EXCL returns EEXIST for
regular files and final symlinks, including dangling links and supported link
constraints, without creating the missing target. BPF errors, faccessat2,
all open regressions and the wide-offset/time64/TLS/atomic/SIMD/JIT runtime
checks pass on both architectures against the exact recorded kernel hashes.

The `opath-mask-*.json` native receipts qualify flag normalization in plain
open/openat: O_PATH ignores access, creation, exclusive-create and truncation
flags, preserves file contents, and retains the requested descriptor flags.
Missing paths still fail with ENOENT. openat2 rejects those combinations with
EINVAL under its stricter contract. Both architectures pass the complete open
fixture with these additional checks.

The `mmap-verified-*.json` native receipts qualify anonymous descriptor handling
and file descriptor argument width. MAP_ANONYMOUS ignores invalid descriptors
and zero-extended -1; file-backed mappings use the low signed C-int value and
retain EBADF for invalid descriptors. Both architectures pass actual anonymous
page writes and mapped file-content checks. `mmap-before-x86_64.json` records
the same fixture failing on the prior kernel with EBADF for descriptor 123456.
The anonymous-mapping fault also prevented the unmodified x86-64 glibc loader
from allocating its shared-object descriptor; that workload identified the fix.

The `dangling-*.json` native receipts qualify O_CREAT through an existing
dangling final symlink. Absolute targets and relative link chains create the
target with the requested permissions and preserve the link inode. Reads
through the target verify the written content. NOFOLLOW/NO_SYMLINKS return
ELOOP, bind-mount escapes under NO_XDEV return EXDEV, and a target ending in
a slash returns EISDIR; denied requests leave no target. Both architectures
pass the complete open fixture. `dangling-before-x86_64.json` retains the
prior kernel's actual failure to create the target. This follows Linux's
[final-component open lookup](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c).

The `directory-create-after-*.json` receipts pass all six native cases after
rejecting O_CREAT|O_DIRECTORY with EINVAL before lookup or creation. The raw
fixture covers plain open, openat and openat2 against missing paths, a missing
parent, an existing directory and an existing file, and verifies no missing
file was created. Legacy O_PATH still discards O_CREAT before validation.
The matching `directory-create-before-*.json` controls fail on both prior
kernels with ENOTDIR. This follows Linux's
[creation-flag validation](https://github.com/torvalds/linux/blob/v6.12/fs/open.c).

An initial i386 attempt failed before linking because V's amd64 inline assembly
could not target i386. The revised fixture uses SSE2 compiler intrinsics; it
passes natively on both architectures and as a static i386 executable through
the existing ARM-native QEMU-i386 translator. Separate native runtime receipts
record the revision. The i386 SDK's musl 1.2.5-r11, compiler-rt 19.1.4-r1, CRT
and builtins hashes are recorded with the build and package inputs. The static
probe bypasses the wrapper's dynamic musl loader and confines its W^X opt-in to
the translator child. Native ELF32 entry, x32, arbitrary glibc applications, complete
large-file/time ABI coverage, loader interoperability and native debugger operations
remain unqualified.

The `mount-after-*.json` receipts and serial logs qualify ordinary ext2 mounting
on both native architectures. Boot-detected volumes register their actual
backing resource and physical extent; mount selects that source's template and
cache, retaining verified/read-only wrappers as distinct backends. A source
symlink resolves normally. The raw fixture verifies ENOENT for a missing source,
ENOTBLK for a character device, ENODEV for an unknown filesystem, mounted data
readback, a read-only alias rejecting creation with EROFS, and content after
unmount/remount. The matching `mount-before-*.json` controls fail on both prior
kernels because ext2 was not registered for the ordinary mount syscall.
The registry is bounded to 256 detected backends and retains the same volume
lifetimes as the cache registry. Discovery of newly formatted or hot-plugged
volumes needs separate qualification.

The `namespace-after-*.json` receipts pass all six native ABI cases, including
the namespace regression, on both architectures. User, network and time
namespace requests previously changed only identities. Clone, clone3, unshare
and setns now return EINVAL for these unavailable kinds, following Linux's
disabled-namespace behavior ([user](https://github.com/torvalds/linux/blob/v6.12/include/linux/user_namespace.h),
[network](https://github.com/torvalds/linux/blob/v6.12/include/net/net_namespace.h),
[time](https://github.com/torvalds/linux/blob/v6.12/include/linux/time_namespace.h)).
Rejected mixed flags preserve every namespace identity rather than partially
applying the supported flags. Writes to uid_map, gid_map and setgroups return
EPERM instead of reporting an applied mapping/policy; the initial namespace's
contents remain unchanged. Matching prior-kernel controls fail on the ignored
write. This qualifies feature discovery and refusal, not user/network/time
isolation. Applications that require these kinds need an implementation or
an explicit maintained port before sandbox qualification. Earlier tests that
created identity-only user namespaces do not establish working remapping.

The additional wide-offset/time64 fixture passes on both native architectures
and both translated x86 paths. It seeks past 8 GiB, verifies current and negative
relative offsets and EOF, reads a normalized realtime clock, then arms a
nonblocking timerfd 2^32 seconds in the future. Getting the remaining duration
must retain more than a signed time32 can hold, and reading must return EAGAIN.
The `runtime-wide-*.json`, `translated-wide-*.json`, input and i386 build receipts
record these binaries. This checks the musl lseek/clock/timerfd wrappers and
translation; it does not qualify legacy time32 interfaces, large disk writes,
every stat/truncate/mmap layout, or wall-clock synchronization.

The additional `glibc-*.json` reports qualify the same runtime predicates with
unmodified Debian Bookworm glibc 2.36-9+deb12u14 on all four paths. These probes
use the pinned GNU headers, CRT, loader, libc, libm and libgcc; gcompat is not in
their dependency chain. The SDK's package URLs and hashes are retained in
[`glibc-packages.json`](../tools/linux-compat/reference/glibc-packages.json),
with individual linked-input hashes in `build-glibc-*.json`. i386 uses
_FILE_OFFSET_BITS=64 and _TIME_BITS=64, including its GNU time64 wrappers.
Native AArch64 reports 16 KiB pages; native and translated x86 report 4 KiB.
The native x86-64 result additionally includes the anonymous-mmap fix described
above. `glibc-loader-before-x86_64.json` records the proper glibc workload
failing before that fix with shared-object descriptor allocation error 9.
Translated probes use the real GNU interpreter in a private root and confine
W^X opt-in and environment cleanup to the translator child. These results
qualify the exercised GNU runtime APIs; arbitrary glibc applications, native
ELF32/x32, native debugger operations and complete legacy time32 behavior remain open.

The `debugger-translated-*.json` receipts qualify the QEMU-user GDB remote stub
for both GNU x86 paths on AArch64. A V protocol client reads the initial
registers and instruction memory, mutates and restores a stack byte, inserts
and hits a software breakpoint, removes it, single-steps and verifies a changed
instruction pointer. Continuing then exits successfully with all TLS, atomic,
SIMD, JIT, page-size and wide-offset/time64 runtime predicates still passing.
The driver validates packet checksums and bounds, uses socket deadlines and
retires the translator. Emulator, probe, driver and kernel hashes accompany
the raw replies' register hash and observed addresses. The translator child
uses the same private GNU root and scoped W^X/environment policy as the runtime
case. This tests the [QEMU-user remote stub](https://www.qemu.org/docs/master/user/main.html)
through the [GDB remote protocol](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Packets.html).
Native ptrace remains unavailable; source-level symbols, stack unwinding, core
dumps, JIT symbol registration and tracing of arbitrary applications remain
separate checks. Remote writes respect guest page permissions; the fixture
mutates writable stack data and restores it before execution.

The initial application suite also attempts all categories and preserves missing
dependencies as unsupported, with a nonzero complete-suite exit. Test roots
contain real Alpine 3.21 SQLite 3.48.0-r4 and BusyBox Extras 1.37.0-r14 payloads;
their package URLs and SHA-256 hashes are retained. They were extracted for
testing, with shared-library soname links materialized as the current Vinix
musl loader expects. Package scripts, signatures, update/remove transactions
and a persistent installed desktop were not qualified by extraction.

| Application workload | Native AArch64 | Native x86-64 |
| --- | --- | --- |
| SQLite WAL transaction, sum verification, integrity check and reopen | passed | passed |
| BusyBox Extras HTTP response content and process-group retirement | passed | passed |
| Runtime fixture invoked and its captured predicates verified | passed | passed |
| FFmpeg, Gnumeric, Chromium, Firefox, Go, Java, V, portal and games | unsupported | unsupported |

Each native catalog receipt has three passing workloads and nine unsupported
results, with no failed workload predicates in the final runs. The controller
and complete suite return failure because unsupported dependencies are not
success. The HTTP child is killed/reaped after the verified response; its
recorded nonzero termination is expected cleanup, not a service run failure.

Additional `catalog-aarch64.json` and `catalog-x86_64.json` receipts pass all
four native media/office/database/server workloads: FFmpeg 6.1.2 encodes ten
64x48 MPEG-4 frames and FFprobe verifies their format/count; Gnumeric 1.12.57
converts CSV to its native format, reopens it and verifies the cell data;
SQLite commits a WAL transaction and checks integrity after reopening; BusyBox
Extras serves exact HTTP content and is retired. The prepared roots include
the actual Alpine dependency closures and DejaVu fonts, with archive/index
hashes in `packages-catalog-*.json`. They use the dangling-creation kernels.
The initial AArch64 office attempt lacked fonts and a login environment and
failed; `catalog-before-aarch64.json` retains that result. The guest init now
provides HOME, user names, UTF-8 locale and a private user runtime directory.
These are disposable-guest execution/save/reopen checks; package transactions,
persistent-disk reboot, GTK windows, updates and desktop integration remain
separate acceptance requirements.

The `package-install-*.json` and `package-upgrade-*.json` receipts qualify a
real disk-backed CLI package lifecycle on both native architectures. The V
stager retains unchanged signed Alpine v3.20/v3.21 repository indexes and APK
archives. Inside Vinix, the existing `pkg` frontend invokes real APK with its
default signature validation and installs SQLite 3.45.3 into an ext2 target
without SQLite. The installed executable uses the unmodified musl package
installed by APK; the boot root retains its prepared Vinix interpreter. The
separate, unused GNU runtime probe in these receipts does not establish a
glibc package result. SQLite commits saved data in WAL mode; a second cold
QEMU boot checks the installed version, integrity and saved value, then
`pkg update` and `pkg upgrade` replace it with SQLite 3.48.0 and newer libraries.
`pkg remove sqlite` removes its executable and APK registration while retaining
the database and base musl runtime. Both boots sync and unmount successfully.
Input receipts verify that the install boot's final volume hash equals the
upgrade boot's initial hash. `packages-lifecycle-*.json` and
`build-driver-packages-*.json` preserve archive and executable/source hashes.
These offline signed-repository transactions qualify this CLI workflow;
network acquisition, interrupted upgrades, desktop package triggers, service
installation and sandbox/portal runtimes remain separate acceptance checks.

The `game-doom-aarch64.json` guest receipt runs Chocolate Doom 3.1.1's `demo1`
timedemo twice against a locally licensed Ultimate DOOM IWAD. Each replay
completes 1,710 gameplay ticks; the runs take 45 and 46 engine realtics.
The driver requires a complete timing record, positive realticks and identical
gameplay ticks, with no timeout or output-limit termination. Upstream ends
timedemos through `I_Error` with exit 255; only that exact benchmark result is
accepted, following the [timedemo interface](https://www.chocolate-doom.org/wiki/index.php/Command-line_arguments).
Host regression checks reject crashes, startup errors, truncated records and
ordinary nonzero exits. Build/input receipts retain the driver, kernel,
SDL libraries, engine and IWAD hashes. Assets are not checked into this repository.
This qualifies native AArch64 gameplay and repeatability with SDL's dummy video
driver and software rendering. It does not qualify visible frames, GPU, audio,
input, saves, installation/update or foreign game runtimes. The raw engine
texture-size warning remains in the report.

The host SQLite WAL/integrity/reopen and FFmpeg frame encode/probe checks pass.
Those Darwin results validate workload predicates and report handling only.
They are not Vinix application results. Host tests also verify that a missing
executable, a nonzero command and an actual timeout cannot produce success.

A later, separate AArch64 guest with the existing staged Go 1.23.9 toolchain
passes compilation and execution of the Go application fixture: filesystem
create/read/truncate/append/rename/link/enumeration, 16 goroutines and channels,
timers, a subprocess, SHA-256, randomness and TCP loopback. Its report, input
receipt and production driver build are checked in as `go-aarch64.json`,
`inputs-go-aarch64.json` and `build-driver-production.json`. The driver embeds
application sources and sets the trimmed Alpine toolchain's GOROOT, private
cache and CGO_ENABLED=0 in its child environment. This qualifies that pure-Go
workload; cgo, x86-64 Go, toolchain installation/update and desktop integration
remain separate. The original minimal-root catalog reports remain unchanged.

A separate AArch64 guest with staged Alpine OpenJDK 25.0.4_p7 and musl 1.2.6
passes Java version discovery, javac compilation, NIO file roundtrip, SHA-256,
threaded TCP loopback, JAR creation and execution from that archive. The five
commands all exit successfully. `java-aarch64.json`, its input/build receipts
and `packages-java-aarch64.json` retain the exact runtime and archive hashes.
The first default-policy run failed during HotSpot executable-page setup;
`java-default-policy-aarch64.json` retains that failure. The passing workload
requests VINIX_ALLOW_WX=1 only in its children and limits application heaps to
128 MiB. This remains subject to the kernel's
[privileged-launcher or wxallowed mount policy](mount-execution-policy.md);
the qualification guest uses a privileged launcher. Unprivileged launches
without administrator policy, other Java architectures, persistent package
transactions and desktop integration remain unqualified.

## Linux service-unit integration

Both native architectures pass `serviceunits` with the native session broker:
an actual BusyBox HTTP unit is installed disabled, explicitly started, killed
to exercise failure restart, restored after a clean broker restart, stopped,
removed, and confirmed absent after another broker restart. Every run verifies
the exact HTTP body and different process IDs, three successful broker exits,
and unchanged saved configuration after unauthorized import, unsupported
`PrivateNetwork=yes`, and active-service removal are refused.

The Services tab's **Import Linux service…** chooser installs the selected
`.service` file disabled. **Start**, **Stop**, and **Remove** use the existing
compositor authorization; ordinary CLI children cannot acquire that authority
from their parent. The host integration test exercises the real chooser ticket,
result delivery, registry refresh, disabled state, and removal.

The supported contract is explicit `Type=simple`, an absolute `ExecStart`
without command prefixes or expansions, up to 16 arguments, `Restart=no`,
`on-failure` or `always`, and restart/stop durations from 100 ms to 60 seconds.
Quoted whole arguments and the documented basic escapes preserve literal argv;
no shell is inserted. The native supervisor limits failure restarts to five.
`Description` and `WantedBy=default.target` are accepted metadata. Installation
never enables a service solely because a target appears in its unit.
Dependencies, credentials, environment/working-directory changes, notify or
forking services, privileged prefixes, specifiers, continuations, and sandbox
directives are errors. This is a maintained native integration for that subset;
full systemd and system service management remain unsupported.

Receipts are `service-units-{aarch64,x86_64}.json`, matching guest-input and
driver-build receipts, and `build-service-broker-{aarch64,x86_64}.json` in the
[dated results](../tests/linux-compat/results/2026-10-11/). The broker manifests
hash all staged V/C inputs and the executable. Earlier guest failures in
`service-broker-before-*` retain the actual startup panic: a cross-compiled
desktop tried to read `calculator.vml` from a host build directory. Production
cross-compilation now embeds those assets; both isolated guest brokers start
and complete the lifecycle. The before reports use earlier driver builds and
are startup controls, not identical-driver semantic comparisons.

Persistence here means synchronized configuration restored across broker
restarts. Cold boot on a persistent home, package-triggered unit discovery,
visual guest interaction, and systemd/portal/sandbox integration need their
own acceptance checks. Whole-application lifecycle qualification stays false.

Outstanding dependencies include browser rendering and sandbox interfaces, V packages, desktop integration
for the qualified office/media workloads, Go/Java on unqualified paths, D-Bus and a real portal backend,
full systemd integration, Flatpak/Snap/FUSE and enforced Linux sandbox
interfaces, and title-specific game assets, GPU/audio/input and vendor APIs.
The [behavior matrix](linux-posix-compatibility.md) lists the broader limits.
Every application report keeps `complete_lifecycle_qualified` false until its
advertised install/run/save/update/desktop workflow has been exercised.

## Ordinary-user shared memory

Browser qualification exposed incorrect anonymous-file ownership and a mounted
`/dev/shm` root with mode 0755. Both native architectures now pass the same
ordinary-user regression: UID 1000/GID 2000 owns a new memfd, receives mode 0777
independent of umask and zero directory links, changes permissions, and reopens
the inode read-only through `/proc/self/fd` with exact data. A forbidden write
reopen returns EACCES. `/dev/shm` retains mode 1777 after mounting, permits user
file creation, and refuses removal of another owner's file with EPERM.

The initial memfd metadata follows Linux's
[anonymous shmem file creation](https://github.com/torvalds/linux/blob/v6.12/mm/shmem.c#L4884)
used by [memfd_create](https://github.com/torvalds/linux/blob/v6.12/mm/memfd.c#L310).
The change sets metadata before publishing the descriptor and preserves the
existing reference-count lifetime.

`shared-memory-before-*` records the old kernel returning UID/GID 0, mode 0600
and one link to the identical fixture. `shared-memory-after-*` contains all
seven passing ABI cases on each architecture, plus the shared-memory serial
logs, in the [dated results](../tests/linux-compat/results/2026-10-11/).
These checks qualify shared-memory permissions, not complete browser or
sandbox behavior.

## Ordinary-user application and browser regressions

`ordinary-user-{aarch64,x86_64}.json` passes SQLite WAL/integrity/reopen,
exact-content HTTP serving and the runtime probe with observed UID/GID 1000,
cleared supplementary groups, a private HOME and XDG runtime directory, and
2 GiB guest RAM. Input receipts record credentials, kernel, init source,
prepared-root manifest and driver/probe hashes. `build-driver-browsers-*`
retains the production driver's V source and generated-C hashes. These checks
exercise ordinary-user execution, without claiming package installation or a
persistent login session.

The AArch64 browser root contains the actual Alpine 3.21 Firefox 128.14.0esr
and Chromium 136.0.7103.113 dependency closures. `packages-browsers-aarch64.json`
pins repository indexes and archives; `selected-browsers-aarch64.json` records
the dependency selection and `rootfs-browsers-aarch64.json` records installed
input bytes and modes. This is disposable test-input extraction; browser
package scripts, signature verification and installed-system registration are
not claimed. The prepared Vinix musl interpreter is retained.

Both engines run directly as UID 1000 with fresh profiles and their default
sandbox policy. The regression requires a nonce-bearing JavaScript callback
with value 42, plus Chromium's changed DOM or Firefox's PNG. Host tests prove
that merely requesting the page, a wrong result and a wrong nonce cannot
replace that proof. No browser sandbox-disable wrapper or environment override
is accepted.

The actual guest failures are retained in `browsers-before-aarch64.json`:
Firefox exits 11 after shared-memory permission failures; Chromium exits 191
because its packaged setuid helper has mode 0755 while the selected sandbox
requires root ownership and mode 4755. Chromium's crash handler also reports
missing ptrace. `firefox-shared-memory-aarch64.json` uses the same driver,
engines and root manifest after the shared-memory kernel fix: permission
errors disappear, but rendering times out after 120 seconds and the driver
terminates its process group. Neither run has JavaScript/render proof, and
both controller receipts exit nonzero. Headless graphics probing also reports
missing libpci/libGL; its causal role in the timeout has not been established.

`browsers-x86_64.json` also runs the native x86-64 Firefox and Chromium engines
as UID/GID 1000 with 4 GiB guest RAM and the default sandbox policy. Both version
commands succeed. Firefox's meaningful headless run times out, and Chromium
refuses the mode-0755 sandbox helper and reports unavailable ptrace. Neither
engine produces the required JavaScript/render proof. Its input receipt exits
1; the exact dependency closure, engine bytes and installed modes are published
in `packages-browsers-x86_64.json`, `selected-browsers-x86_64.json` and
`rootfs-browsers-x86_64.json`.

These reports distinguish available browser packages from a qualified browser
workflow. Sandbox isolation, visible windows, portal requests and
install/update/remove remain outstanding checks.

The [generated application regression index](linux-application-coverage.md)
collects browser, office, media, language-runtime, database, server and game
verdicts across both native architectures, including explicit unsupported
architecture/runtime combinations. Its V auditor checks guest context,
architecture, controller-requested cases, report/driver/kernel fingerprints,
unique verdicts and controller exit consistency. It preserves failed and
unsupported dependencies and rejects edited or host receipts. Regenerate or
check it with `build-support/run-v-tool.sh tools/linux-compat/applications`
and `--check`. `--require-complete` still exits 1 because full application
support and the install/update/desktop acceptance gate remain incomplete.

## Seccomp trap signal semantics

Both native architectures now pass a real classic-BPF filter regression with
twenty trapped getpid calls. Linux signal frames report SYS_SECCOMP, exact
filter data 42, syscall number, audit architecture and the saved call address.
The original return register survives the rejected call; the handler writes
4242 to the public ucontext and the syscall returns that value after
rt_sigreturn. Ordinary SIGSYS signals before and after carry no stale trap
metadata. Separate children blocked or ignoring SIGSYS die from that signal,
following Linux's forced synchronous disposition.

This follows [Linux's seccomp trap handling](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L1167)
and [force_sig_seccomp](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c#L1725).
The prior kernel delivered an ordinary signal and overwrote the return
register with ENOSYS; matching `seccomp-trap-before-*` receipts retain the
identical fixture failure. `seccomp-trap-after-*` retains all eight passing
ABI cases plus serial logs on both architectures in the dated results.
The new metadata is stored inline in its triggering thread and consumed
before the private signal frame is built; no allocation lifetime changes.
Per-thread filter ownership, TSYNC, ptrace and full browser/container sandbox
isolation remain unqualified by this regression.

## Seccomp scratch-memory verification

Both native architectures reject classic-BPF scratch reads unless the selected
word was written along every incoming branch. Installation returns `EINVAL`
for uninitialized A/X loads, a store to the wrong word, a conditional branch
that skips initialization, and an unconditional jump over a store. Forty
repeated rejections leave seccomp disabled. Valid A/X stores, stores on both
branches, and a 4096-instruction program install successfully; existing trap
signal tests still pass. The check follows [Linux's classic-BPF verifier](https://github.com/torvalds/linux/blob/v6.12/net/core/filter.c#L868).

The identical fixture fails against both prior kernels because an uninitialized
load is accepted. `seccomp-scratch-before-*` and `seccomp-scratch-after-*` in the
[dated results](../tests/linux-compat/results/2026-10-11/) retain the controller
receipts and serial logs; the updated kernels pass all eight ABI cases.
Generated C keeps the verifier's bounded mask array on the kernel stack and
adds no allocation. The full allocation scan compiles both architectures but
reports existing allowance mismatches, so it is not a clean leak certification.
This regression does not qualify per-thread filters, TSYNC or browser sandbox
isolation.
