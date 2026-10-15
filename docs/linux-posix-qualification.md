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

## Futex wake counts

Both native architectures pass 108 timed pthread waits with exact wake counts.
Eight twelve-thread rounds check that requests for one, two and three wake
only those numbers, with the remaining threads blocked until subsequent calls.
The original futex ABI's zero/negative requests wake one when waiters exist.
WAKE_OP checks independent queue limits, true/false comparisons and the
unchanged atomic OR-zero target. Listener compaction preserves the remaining
timed waits and reuses the existing overflow storage cleanup; the added code
allocates nothing. See [Linux's wake implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/waitwake.c#L148).

`futex-count-before-*` receipts retain both prior kernels returning twelve for
a request of one. `futex-count-after-*` retain the same fixture and all nine
passing ABI cases on both architectures in the [dated results](../tests/linux-compat/results/2026-10-11/).
Bitset filtering and real requeue behavior remain unqualified by these checks.

## Futex private and shared keys

Both architectures pass twenty timed pthread waits using one memfd mapped at
two shared addresses and one private address. A private wake through another
alias must return zero and leave the waiter blocked; the matching virtual
address wakes exactly one. Shared waiters wake through another shared alias.
Private and shared calls at the same virtual address select distinct queues
on both shared and private mappings. The explicit flag is passed through
ordinary WAIT/WAIT_BITSET, WAKE/WAKE_BITSET and both WAKE_OP queues; kernel
internal callers retain their non-private key selection. References and
waiter storage retain their existing ownership. See
[Linux's key selection](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/core.c#L185).

`futex-keys-before-*` retains both prior kernels incorrectly waking a private
waiter through a different alias. `futex-keys-after-*` retains the same fixture
and all ten passing native ABI cases in the
[dated results](../tests/linux-compat/results/2026-10-11/).
These checks do not qualify priority-inheritance keys, cross-process shared
file page eviction, bitset filtering or real requeue behavior.

## Futex bitset selection

Both architectures pass 36 timed and twelve untimed pthread waits with three
distinct masks. A nonintersecting wake must return zero and leave every waiter
blocked. Selective calls wake exactly the requested number from the matching
group, preserving the other groups and overflow listeners. Combined masks
drain the remaining matching groups. Plain WAIT uses MATCH_ANY, including the
highest mask bit. Both bitset operations reject zero masks with EINVAL after
narrowing val3 to the Linux u32 argument. See
[Linux's bitset matching](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/waitwake.c#L148).

In those dated kernels the mask lived in the thread object during its wait,
published under the event lock and cleared after listener teardown. The later
requeue implementation below stores it in a stable syscall-frame queue node.
Generic event broadcasts retain their existing behavior.

`futex-bits-before-*` retains both prior kernels incorrectly waking a
nonmatching waiter. `futex-bits-after-*` retains the same fixture and all eleven
passing native ABI cases in the
[dated results](../tests/linux-compat/results/2026-10-11/).
Those bitset checks do not qualify requeue, PI interaction or shared-file page
eviction; requeue has its own later receipts below.

## Native x86-64 language runtimes

The native x86-64 guest now compiles and runs the existing Go application as
UID 1000/GID 1000. Go 1.23.9 passes files, symlinks, directory enumeration,
goroutines/channels/WaitGroup, timers, subprocess execution, hashing, random
bytes and a TCP loopback exchange. The generated executable's digest is
recorded by the guest alongside the compiler command and its application
output; that temporary executable is not exported from the guest.

OpenJDK 21.0.10 passes javac compilation, threaded/NIO/TCP execution, JAR
creation and execution from the saved JAR. All five commands come from the
same complete JDK. This run uses UID 0 and VINIX_ALLOW_WX for HotSpot's code
cache, with a 128 MiB application heap; it does not qualify ordinary-user JIT
launch policy or package/desktop installation.

Both receipts use disposable 2048 MiB QEMU guests and a 600-second child
deadline, and record actual successful command exits without timeouts or
truncated output. `go-x86_64` and `java-x86_64` reports, controller inputs and
serial logs are in the [dated results](../tests/linux-compat/results/2026-10-11/).
The shared root manifest, APK/index hashes and the V acquisition script retain
the exact input provenance. The auditor verifies every unchanged prepared
file and resolves executable links inside the guest root; PID 1's replacement
is checked separately against the built init. These inputs were extracted for
runtime diagnosis; no APK install scripts or signature validation were run.
The earlier unsupported catalog receipts remain available, and the application
index now selects these completed native runtime workloads.

## Futex WAKE_OP comparisons and errors

Both architectures pass all six signed comparison encodings with 24 timed
waiters, comparing negative, equal, zero and positive word values against -1.
False comparisons leave the second queue blocked until a separate wake;
true comparisons release its waiter. SET, ADD, OR, ANDN and XOR produce the
expected target values. Shift operands are masked to five bits, including
negative and out-of-range values, as in Linux's original ABI.

Unsupported atomic operations return ENOSYS without changing the word. An
unsupported comparison returns ENOSYS after its supported atomic operation
takes effect and before either queue wakes. See
[Linux's operation decoder](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/waitwake.c#L194).
No allocation or ownership change is introduced.

`futex-op-before-*` retains both prior kernels using LE for the GE encoding
and incorrectly waking on -2 compared with -1. `futex-op-after-*` retains the
same fixture and all twelve passing native ABI cases in the
[dated results](../tests/linux-compat/results/2026-10-11/).
These WAKE_OP checks do not qualify requeue or PI interaction.

## Futex address and timeout errors

Both architectures pass 38 checks of exact errors and precedence. Unaligned
words return EINVAL. Unknown command bits and unsupported clock modifiers
return ENOSYS. The operation is narrowed to Linux's C int. Private wakes on
canonical unmapped addresses can return zero; shared wakes must resolve their
word and return EFAULT on missing mappings. WAKE_OP validates both keys before
decoding its operation or changing the target.

A supplied timeout is copied and validated before command-specific bitset
and address checks, including recognized unsupported wait commands. Invalid
pointers return EFAULT; negative seconds or invalid nanoseconds return EINVAL.
An expired absolute deadline still compares the word: a mismatch returns
EAGAIN, an inaccessible word returns EFAULT and a matching word returns
ETIMEDOUT. See [Linux's syscall validation order](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/syscalls.c#L150)
and [key validation](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/core.c#L185).

`futex-errors-before-*` retains both prior kernels returning EAGAIN for an
unaligned WAIT. `futex-errors-after-*` retains the matching fixture and all
thirteen passing native ABI cases in the
[dated results](../tests/linux-compat/results/2026-10-11/).
These changes introduce no allocation or ownership change. Read-only WAKE_OP
targets, page eviction and PI interactions remain unqualified. Requeue has
separate receipts below.

## Futex requeue and shared word offsets

Both native architectures pass REQUEUE and CMP_REQUEUE with 164 raw pthread
waiters and 240 musl condition-variable waits. A comparison mismatch returns
EAGAIN without waking or moving anything, including an empty queue. Negative
counts return EINVAL; arguments are narrowed to Linux's signed C int. Both
keys are validated. Read-only comparison words work without requiring write
permission. See [Linux's requeue contract](https://github.com/torvalds/linux/blob/v6.12/kernel/futex/requeue.c#L345).

Transfers wake at most the requested number, move at most the second count
and return their sum. Existing target waiters remain blocked. Requeued waits
retain bitsets and their original timers. Tests cover private/shared keys,
shared aliases, same-key counting, multiple transfers, timeout and signal
cleanup, and repeated condition broadcasts while the mutex remains locked.
Shared keys now include the word's offset within the native 4 KiB or 16 KiB
page; neighboring shared words no longer alias one queue.

Each wait owns a stack node with a stable event, plus one reference to its
current futex. Requeue transfers that reference under the queue lock. Wake,
timeout and signal cleanup serialize there, with an already-selected wake
taking precedence. Event listeners detach before the frame can leave. The
generated C confirms stack storage for the node/event list and no additional
heap allocation for either. Word comparisons use a readable atomic load
under the pagemap lock; missing-page resolution happens outside the queue
lock. Repeated page-in races are bounded and can return EAGAIN after sixteen
attempts. This does not qualify backing-page eviction or PI requeue.

The [2026-10-12 results](../tests/linux-compat/results/2026-10-12/) retain the
same fixture on both prior kernels accepting a mismatching comparison,
the intermediate kernels colliding neighboring shared words, and all
fourteen passing ABI cases on the final kernels. The native x86-64 Go workload
also compiles and runs as UID/GID 1000; OpenJDK passes compilation, threaded
file/TCP tests and JAR create/reopen with the existing privileged JIT policy.
Their input manifests, package hashes, reports and logs are retained there.
These extracted runtime inputs do not qualify package installation.

Firefox 128.14.0esr was rerun as UID/GID 1000 in the same native x86-64 kernel,
with 2048 MiB guest memory and its normal sandbox policy. It still times out
without JavaScript/PNG proof, and this run reports ENOMEM when forking its tab
process. The failed report, controller receipt, prepared-root manifest,
package hashes and raw log remain visible alongside the passes. This result
does not identify the cause of that allocation failure or qualify browsers,
portals or the complete application lifecycle.

## Browser allocation and timeout diagnostics

The workload driver now retains bounded guest proc snapshots in each command
receipt. Starting counters and failure counters expose physical memory and
kernel resource reservations. Timeout/output-limit snapshots also record the
child's status, up to 32 KiB of maps and slab counts before process-group
cleanup. Read errors and truncation remain explicit. Host-only runs do not
collect these snapshots. Three reader/failure tests and the three existing
runner tests pass, and the static driver builds for both architectures.

The [2048 MiB report](../tests/linux-compat/results/2026-10-12/pressure-firefox-2g-x86_64.json)
and [4096 MiB report](../tests/linux-compat/results/2026-10-12/pressure-firefox-4g-x86_64.json)
use the same native x86-64 kernel and Firefox 128.14.0esr executable as
UID/GID 1000, with normal sandbox policy and 120-second command deadlines.
The smaller run reports a failed fork, exits 11, and retains three kernel
resource denials with 1,365,480 KiB of physical memory free after exit.
The larger run times out without a fork warning, with zero resource denials,
3,037,984 KiB free and 53 threads in the sleeping browser parent.
This supports investigating resource accounting separately from the remaining
browser startup issue; it does not prove either failure's complete cause.
Neither run executes the nonce-bearing page or renders its PNG. Reports,
controller receipts, source/build hashes, prepared-root manifests and logs
remain alongside the other qualification artifacts.

## Sparse fork page-table reservations

Fork now leaves a private shadow pagemap without a root until its first
resident page requires one. Read-only lookups of an empty pagemap return
no entry; allocating lookups reserve and create the root through the existing
fallible accounting path. This also applies to WIPEONFORK mappings. Existing
locks and disposal paths retain ownership; no new allocation lifetime is
introduced. The production-helper host test covers an empty lookup, quota
denial, retry, root reuse and complete charge release. Generated C on both
architectures confirms that the mutable lookup alias adds no allocation.

The native fixture reserves 512 private 64 MiB mappings and touches one page
in every sixteenth mapping. It measures physical allocation while the child
is stopped on a pipe, then checks resident copy-on-write, independent zero
pages on first access after fork, WIPEONFORK and unmapping in both processes.
The memory bounds are an isolated-guest regression contract, rather than a
general Linux conformance threshold.

| Native architecture | Prior fork allocation | Fixed fork allocation |
| --- | ---: | ---: |
| x86-64, 4 KiB pages | 4,247,552 bytes | 1,732,608 bytes |
| AArch64, 16 KiB pages | 11,288,576 bytes | 3,440,640 bytes |

The [dated results](../tests/linux-compat/results/2026-10-12/) retain matching
before/after fixture hashes and all fifteen passing native ABI cases on the
fixed kernels. Both kernels build, the resource-accounting host suite and
four coverage-generator tests pass, and the generated inventory is current.
Native x86-64 Go passes compilation and its file/thread/timer/exec/TCP workload
as UID/GID 1000. OpenJDK passes compilation, threaded file/TCP tests and JAR
create/reopen under its previously qualified privileged JIT policy. Their
reports, acquisition/package hashes and prepared-root manifest remain there;
these extracted inputs do not qualify package installation.

Firefox on the same fixed x86-64 kernel still times out as UID/GID 1000 in a
2048 MiB guest, reports a failed fork and retains four resource denials. Its
[failed report](../tests/linux-compat/results/2026-10-12/sparse-firefox-2g-x86_64.json)
includes bounded proc diagnostics. This fix reduces sparse-fork allocation;
it does not qualify browser startup or establish the cause of the remaining
resource denials.

## Seccomp capability query flags

SECCOMP_GET_ACTION_AVAIL now rejects nonzero flags with EINVAL before reading
its action argument, matching [Linux's syscall validation](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L1943).
An unsupported action retains EOPNOTSUPP, and an inaccessible action pointer
with valid flags retains EFAULT. Queries do not install filters or require
privileged credentials.

The native fixture runs as UID/GID 1000, queries all seven recognized actions,
checks seven invalid flag bits with valid and invalid pointers, verifies
unsigned-int narrowing of operation/flags and checks unchanged input and
guard words. The [dated results](../tests/linux-compat/results/2026-10-12/)
retain both prior kernels accepting flags=1, both fixed query passes and the
existing filter/trap regression on each architecture. Both kernels build and
the generated coverage inventory is current. Linux per-thread filter ownership,
TSYNC and complete browser sandbox qualification remain open.

## Kernel resource denial reasons

`/proc/kernel-resources` now splits kernel-budget denials into invalid/stale
requests, account exhaustion, object exhaustion, global bytes, owner bytes and
cgroup admission. It retains the latest rejected owner slot/generation, resource
kind, byte request and global/owner usage before rollback. The existing quota,
validation order and allocation lifetimes are preserved. These counters cover
kernel-budget admission, rather than physical-memory exhaustion or every
possible ENOMEM/EAGAIN source. Snapshots before the first rejection omit the
last-denial fields.

The production-helper host suite passes concurrent accounting, surviving owners,
all six denial categories, growth failures and rollback. Both native guest
tests exhaust an ordinary user's mapping allowance, receive ENOMEM with the
correct owner-limit evidence, release one mapping for the kernel's read scratch
reservation, and inspect the retained pre-rollback usage with fixed buffers.
They unmap the remaining reservations and verify allocation recovers. Existing
mmap and sparse-fork cases also pass on both final kernels. Matching prior
kernels lack the diagnostic fields; all before/after receipts and logs are in
the [dated results](../tests/linux-compat/results/2026-10-12/).
Both kernels build and the four coverage-generator tests and inventory check
pass. Generated C confirms scalar accounting updates without allocation.

The [Firefox rerun](../tests/linux-compat/results/2026-10-12/budget-firefox-2g-x86_64.json)
uses the same Firefox 128.14.0esr input, UID/GID 1000, 2048 MiB guest and normal
sandbox policy. It still times out without page/PNG proof. All three recorded
kernel-budget denials are global-byte refusals; the other five categories stay
at zero. The latest rejected scratch reservation requests 139,520 bytes at
190,897,484 bytes globally charged against a 190,904,320-byte ceiling. Its
owner holds 92,975,726 bytes, below the 95,452,160-byte owner ceiling. At the
timeout snapshot, rollback has reduced total reservations to 116,926,552 bytes
and 1,075,996 KiB of physical memory is free. This identifies the budget gate
behind these three refusals; it does not establish every startup failure's
cause. Reports, immutable input hashes, prepared-root manifest and raw log
remain visible.

## Mapping metadata storage reservations

Mapping aliases now reserve the allocator bound for their local object rather
than a fixed 8 KiB allowance. Global mappings separately own their embedded
shadow map and alias vector; standalone page maps own their object and mapping
vector. Capacity growth admits both old and new buffers before allocation,
then retires the old buffer's reservation after V frees it. Retained capacity
stays charged after unmapping. Fork rollback vectors are sized under the parent
map lock and admitted before allocation. Split and shared-remap callers handle
refused growth before publishing an alias. Object, vector and table storage is
freed before its saved reservation is released.

The bound covers heap/array headers, slab rounding and large allocations'
rounded data pages plus their full metadata page. That metadata page is 16 KiB
on AArch64. Host tests exercise both page geometries, overflow, real-array
growth refusal without mutation, retry, capacity reuse and growth after the
creator account closes. Generated C and a separate lifetime review verify the
allocation and retirement order.

The ordinary-user native fixture reserves 1024 untouched 64 MiB private spans,
splits 512 with PROT_NONE, forks, checks independent zero pages and changed
protections, unmaps, then repeats. Matching prior kernels fail the bound;
both final kernels pass all 18 ABI cases. Reservations for the first mapping
cycle are:

| Native architecture | Prior kernel | Storage-accounted kernel |
| --- | ---: | ---: |
| AArch64, 16 KiB pages | 8,519,680 bytes | 1,883,904 bytes |
| x86-64, 4 KiB pages | 8,519,680 bytes | 1,859,328 bytes |

All 32 files for this change were re-audited with V assertions enabled using
`-nocache -cflags -O2`. The current V3 compiler removes assertions in `-prod`
builds. The [revalidation record](../tests/linux-compat/results/2026-10-12/metadata-revalidation.json)
includes the assertion failure control, compiler/auditor hashes and matching
published output hashes; the original guest verdicts are preserved.

The [dated receipts and logs](../tests/linux-compat/results/2026-10-12/)
include `metadata-storage-before/after-*.json`, the 200-cycle paging regression
with every reported slab-class delta zero, and all seven memory-lock suites
on each final kernel. Ordinary-user pressure still returns ENOMEM with the
correct owner-limit evidence and recovers after unmapping. Native x86-64
[Go](../tests/linux-compat/results/2026-10-12/metadata-go-x86_64.json) and
[OpenJDK](../tests/linux-compat/results/2026-10-12/metadata-java-x86_64.json)
workloads pass; Java retains its recorded privileged launch policy.

The same 2 GiB, UID/GID 1000
[Firefox rerun](../tests/linux-compat/results/2026-10-12/metadata-firefox-2g-x86_64.json)
has zero kernel-budget denials and no fork-allocation error, but still times out
without page/PNG proof. Its snapshot reports 147,934,476 bytes charged against
190,899,712 and 885,136 KiB of free physical memory. Browser startup and the
installation/sandbox acceptance gate remain open. This change does not qualify
all VM metadata: existing PagedPage nodes remain uncharged, and heap allocation
can still fail after budget admission. A fixed shared remap can remove its
destination before a later reservation fails. The flat paging measurement
does not replace the broader kernel operations/churn leak audit.

## Production task diagnostics

An explicit root request through `/proc/sysrq-trigger` now sends the x86-64
task dump to serial as well as the graphical console. AArch64 already sent
these dumps to serial; its path is retained without a duplicate report.
The thread-list lock is attempted before reading process state. A busy list
reports an unknown state instead of waiting for that lock. The process-table
and console locks still apply, so this does not qualify general deadlock
recovery.

The same native fixture receives EACCES as UID/GID 1000 and then issues two
root requests. The controller requires actual serial task rows in addition to
the fixture's verdict. The prior production x86-64 kernel passes the writes
but times out with no serial rows; the prior AArch64 kernel passes. Both final
kernels pass the diagnostic, namespace-discovery and seccomp-query cases.
The existing process-inspection fixture also passes all six groups on each
kernel, including concurrent exec/exit and mapping changes. All seven
compatibility host test files and the generated inventory check pass.

The [dated receipts, raw logs and assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/sysrq-audit.v)
record the before/after controls and inspection results. The auditor verifies
49 inventory inputs against both isolated build trees, the generated lock
ordering and architecture-specific serial calls, and the frozen test artifacts.

## Administrator-approved native JIT runtimes

The workload controller now accepts `--jit-runtimes firefox` or `java` for
selected native workloads running as UID/GID 1000. PID 1 approves only the
runtime's executable directory with a read-only `nosuid,nodev,wxallowed`
self-bind. The driver remains outside it and sends VINIX_ALLOW_WX only to
runtime children. Their report requires and records the actual most-specific
mountinfo entry. Each helper exec still receives the kernel's existing
authorization check; the global W^X policy and resource limits remain in force.

The new native conformance fixture passes on both architectures. An ordinary
user cannot remount the runtime or write its otherwise-writable file; setuid
and setgid bits do not change effective credentials through the approved
`nosuid` mount. Exec with an explicit request outside approval returns EPERM.
Approved children can make RWX mappings and protection changes; a child
without the request retains EOPNOTSUPP. Administrator revocation rejects new
requests. The [AArch64](../tests/linux-compat/results/2026-10-12/jit-policy-aarch64.json)
and [x86-64](../tests/linux-compat/results/2026-10-12/jit-policy-x86_64.json)
receipts bind these checks to the unchanged production kernels.

Firefox 128.14.0esr passes its native x86-64 ordinary-user regression in a
4096 MiB guest. The [report](../tests/linux-compat/results/2026-10-12/jit-firefox-x86_64.json)
records successful version and headless commands, the scoped runtime mount,
a nonce-bearing JavaScript result of 42 and a rendered PNG hash. No browser
sandbox-disable environment or flag is used. This qualifies that default
browser workload, including JIT setup; complete seccomp thread ownership and
sandbox isolation still require separate work. OpenGL/libpci are absent in
this headless root, so GPU and ordinary windowed desktop use remain unqualified.

An earlier approved 2048 MiB diagnostic run still reached the kernel's global
and owner resource budgets. Its last refusal was a 139,520-byte scratch
request against an owner already charged 95,440,210 of 95,443,456 bytes, with
905,048 KiB physical memory free. The passing run uses the existing limits
derived from 4096 MiB of guest memory. This does not establish a general
minimum memory requirement or qualify the 2048 MiB workload.

OpenJDK 21.0.10_p7 passes all five native commands as UID/GID 1000 on
[AArch64](../tests/linux-compat/results/2026-10-12/jit-java-aarch64.json) and
[x86-64](../tests/linux-compat/results/2026-10-12/jit-java-x86_64.json), in
2048 MiB guests. Each uses the complete JDK's direct entry points through its
read-only approved mount: version discovery, javac, application execution,
JAR creation and execution from that JAR. The existing application verifies
NIO file roundtrip, SHA-256, threaded TCP loopback and the native architecture.
The package closures and both roots use pinned Alpine 3.21 musl 1.2.5 inputs;
they have not run APK installation or alternative-registration scripts.

The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/jit-audit.v)
checks a failing assertion control, native permissions, input/package hashes,
all prepared-root entries and explicit controller overlays, frozen kernel,
init/archive/ISO, driver build, literal command vectors and JavaScript proof.
The builder generates without V's module cache so a cached host declaration
cannot replace a target runtime definition. Installation signatures/scripts,
updates and approval persistence remain separate from these extracted roots.

The application index also verifies passing browser proof explicitly: an
ordinary identity bound to the controller receipt, the exact nonce-bearing
JavaScript result, page/render hashes, matching successful version and headless
commands, and enabled sandbox settings. A [negative control](../tests/linux-compat/results/2026-10-12/browser-audit-before.log)
reproduces the previous acceptance of a resealed report changed from 42 to 41.
The [fixed audit tests](../tests/linux-compat/results/2026-10-12/browser-audit-after.log)
reject that report, a bad PNG hash, root or mismatched identities, timeout,
version-only invocation, and sandbox-disable flags or environment. These are
host checks of guest receipts, with no additional guest qualification claim.

The [AArch64 Firefox report](../tests/linux-compat/results/2026-10-12/jit-firefox-aarch64.json)
also passes version discovery, the exact JavaScript callback and PNG rendering
as UID/GID 1000 in a 4096 MiB guest. It uses the same production kernel as the
native permission fixture, with 16 KiB pages, the same maintained driver source
and explicit read-only runtime approval. A separately acquired Alpine 3.21
Firefox 128.14.0esr dependency closure includes DejaVu fonts. The
[assertion-enabled ARM auditor](../tests/linux-compat/results/2026-10-12/jit-firefox-aarch64-audit.v)
binds every prepared-root entry, controller overlay, package input and frozen
boot artifact to this result, and reconstructs the nonce-bearing HTML to check
the page hash. The index now retains passing default-settings Firefox results
on both native architectures while preserving Chromium's failure and the
broader installation, GPU, portal and sandbox-isolation gaps.

The ARM receipt was reproduced on persistent storage after the original RAM
artifact volume disappeared. The surviving native kernel and driver were
verified against their existing published receipts. The driver's original
generated C is unavailable locally; its prior audited build receipt is reused
and that limitation is recorded explicitly in the new evidence.

## prctl option width and no_new_privs argument validation

PR_GET_NO_NEW_PRIVS now rejects every nonzero argument with EINVAL;
PR_SET_NO_NEW_PRIVS requires value 1 and zero reserved arguments before
changing state. The prctl selector is narrowed to a C int in both the extended
and base handlers, while these arguments retain their full native width.
This follows [Linux 6.12's prctl implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/sys.c#L2478).
The native V fixture checks 34 exact refusals, high argument bits, high selector
bits, preserved state after invalid requests, and idempotent valid setting.
These argument-validation receipts do not qualify per-thread ownership; the
later [task-local no_new_privs results](#task-local-no_new_privs) cover that flag.
Seccomp filter ownership remains unqualified.

The before-controls on [AArch64](../tests/linux-compat/results/2026-10-12/nnp-before-aarch64.json)
and [x86-64](../tests/linux-compat/results/2026-10-12/nnp-before-x86_64.json)
return success for an invalid query. Both rebuilt kernels pass the unchanged
fixture plus seccomp queries/trap delivery and approved JIT permission checks:
[AArch64 results](../tests/linux-compat/results/2026-10-12/nnp-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/nnp-after-x86_64.json).
The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/nnp-audit.v)
checks source/inventory hashes, the isolated builds and frozen guest artifacts.

## Task-local no_new_privs

no_new_privs now belongs to each Thread on both architectures. Setting it
cannot change an existing sibling; new tasks inherit the calling thread's
flag. The replacement thread after exec retains that caller's flag even when
a nonleader execs with a different flag from its leader. Seccomp installation
authorization and the exec capability ceiling read the calling thread's state.
This follows the [Linux no_new_privs contract](https://docs.kernel.org/userspace-api/no_new_privs.html).

Procfs reads the selected task's atomic flag under the process table lock.
A diagnostic leader copy preserves status after that thread retires, including
zombies; it is never used for authorization or inheritance. Attachment resets
that copy when exec creates a new leader. The change adds scalar fields and
introduces no allocations, frees or retained pointers. A separate kernel
lifetime/concurrency review found no blocker in the borrowed reads or handoff.

The unchanged ordinary-user V fixture fails on the original process-wide
implementation, where a clear nonleader incorrectly retains its set leader's
flag after exec: [AArch64 control](../tests/linux-compat/results/2026-10-12/nnpthread-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/nnpthread-before-x86_64.json).
Both isolated final builds pass sibling independence, clone/fork/exec,
direct nonleader exec, the then-current seccomp authorization probe and
live/zombie procfs checks. They also pass the existing 34-error prctl test,
seccomp queries/trap delivery, approved JIT permissions and TLS/atomic/SIMD
runtime checks: [AArch64](../tests/linux-compat/results/2026-10-12/nnpthread-after-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/nnpthread-after-x86_64.json).

Six existing capability-exec groups pass on the same kernels, including
repeated root exec without capability regain, low/high permitted bits,
mixed credentials and nonroot ambient capabilities:
[AArch64](../tests/linux-compat/results/2026-10-12/nnpthread-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/nnpthread-cap-x86_64.json).
All eight host test files pass. The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/nnpthread-audit.v)
requires its deliberate failing assertion to exit nonzero, verifies the
53-input inventory and isolated source changes, and rehashes frozen kernels,
fixtures, generated C, binaries, ISOs, serial logs and receipts.

The original authorization probe expected EACCES for an unreadable header
when no_new_privs was clear. That error oracle was incorrect; the
[installation qualification](#seccomp-installation-error-precedence) corrects
the reusable fixture and verifies the caller's permission with a readable
valid-length header. These historical receipts retain their original sources.

These results qualify task-local flag behavior and the stated capability
checks. Seccomp filters remain process-wide; TSYNC, setuid/file-capability
execution, LSM transition behavior and complete application sandbox isolation
remain unqualified. The larger roadmap gates stay open.

## KEEPCAPS value validation

PR_SET_KEEPCAPS now accepts only unsigned-long values 0 and 1, returning
EINVAL before changing the flag for any other value. This follows
[Linux 6.12's capability prctl implementation](https://github.com/torvalds/linux/blob/v6.12/security/commoncap.c#L1253).
The V fixture checks 24 exact errors as root and UID/GID 1000, including
upper register bits and all bits set, with the flag both clear and set.
Valid setting/clearing is reversible and idempotent. Four child execs check
fork inheritance, exec reset and the parent's retained state.

The unchanged fixture detects placeholder acceptance of value 2 on both
previous kernels: [AArch64 control](../tests/linux-compat/results/2026-10-12/keepcaps-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/keepcaps-before-x86_64.json).
Both isolated builds pass it plus the no_new_privs argument and thread checks:
[AArch64 results](../tests/linux-compat/results/2026-10-12/keepcaps-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/keepcaps-after-x86_64.json).
The six existing capability-exec groups also pass on the same kernels:
[AArch64](../tests/linux-compat/results/2026-10-12/keepcaps-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/keepcaps-cap-x86_64.json).

All eight host test files pass. The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/keepcaps-audit.v)
checks the negative assertion control, 53-input inventory, unchanged fixtures,
isolated one-file kernel change and frozen artifacts. This change introduces
no allocations or frees. Securebits locking and per-thread capability
credentials were not qualified by these value checks. The later securebits
results below qualify its flags and locks; capability sets remain process-wide.

## Securebits policy and task ownership

PR_SET_SECUREBITS now applies Linux's four behavior/lock pairs and refuses
unknown mask bits, changes to locked behaviors, removed locks, and callers
without CAP_SETPCAP with EPERM. This includes uid 0 after dropping that
capability. KEEP_CAPS is the same task-local bit exposed through
PR_SET/GET_KEEPCAPS, whose invalid-value EINVAL precedes its locked-bit EPERM.
The behavior follows [Linux 6.12's capability implementation](https://github.com/torvalds/linux/blob/v6.12/security/commoncap.c#L1222)
and [securebits definitions](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/securebits.h).

NOROOT suppresses root capability magic during an exec without file
capabilities. NO_SETUID_FIXUP retains capability sets across the tested real,
effective and saved UID transitions. NO_CAP_AMBIENT_RAISE prevents future
raises without deleting existing ambient capabilities; lowering and clearing
remain permitted. A complete root-to-user transition without NO_SETUID_FIXUP
clears ambient capabilities even when KEEP_CAPS retains permitted capabilities.
Exec clears KEEP_CAPS and preserves its lock and every other flag.

Flags belong to each Thread. Existing siblings stay independent, while clone,
fork and exec inherit the caller's flags. Direct execs from nonleaders with
different flags from their leader check both KEEP_CAPS clearing and retention
of NO_CAP_AMBIENT_RAISE. Borrowed constructor/current-task reads retain no
pointers, and a separate lifetime/concurrency review found no blocker in either
generated kernel. The new helper paths allocate and free nothing.

The unchanged V fixture detects the original placeholder success for an
unknown mask on both native architectures:
[AArch64 control](../tests/linux-compat/results/2026-10-12/securebits-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/securebits-before-x86_64.json).
Both final builds pass all lock pairs in both states, five privilege/UID/ambient
policy cases, sibling and descendant checks, and eleven exec probes. They also
pass the existing KEEPCAPS and no_new_privs thread regressions:
[AArch64 results](../tests/linux-compat/results/2026-10-12/securebits-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/securebits-after-x86_64.json).
Six existing capability-exec groups pass on the same kernels:
[AArch64](../tests/linux-compat/results/2026-10-12/securebits-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/securebits-cap-x86_64.json).
All eight host test files pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/securebits-audit.v)
checks the negative assertion control, 54-input inventory, isolated sources,
unchanged fixtures, generated helper C and frozen guest artifacts.

Capability sets remain process-wide. These receipts qualify the task flags
and the stated single-thread capability effects; concurrent per-thread
credential isolation, file capabilities, fsuid-specific fixups, LSM behavior
and complete application sandbox isolation remain unqualified. The three
larger roadmap gates stay open.

## Ambient capability argument validation

PR_CAP_AMBIENT now rejects nonzero fourth/fifth arguments for every command
and a nonzero third argument for CLEAR_ALL with EINVAL. The full native
unsigned-long width is checked before mutation or a raise's permission test,
following [Linux 6.12's capability implementation](https://github.com/torvalds/linux/blob/v6.12/security/commoncap.c#L1267).
Previously, queries, raises and lowers ignored reserved arguments; a malformed
CLEAR_ALL could erase the ambient set and return success.

The V fixture raises a real CAP_CHOWN ambient bit, checks all four commands
with reserved values 1, 2^32 and ULONG_MAX, and queries the state after each
error. It repeats with the bit lowered and after dropping to UID/GID 1000.
All 81 malformed requests must return EINVAL without changing state. Valid
query/raise/lower/clear calls still work, while an ordinary user's valid raise
without the required permitted/inheritable capability returns EPERM.

The same fixture source detects the ignored argument on both earlier kernels:
[AArch64 control](../tests/linux-compat/results/2026-10-12/ambient-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/ambient-before-x86_64.json).
Both fixed kernels pass the ambient case and the existing securebits,
KEEPCAPS and task-local no_new_privs cases:
[AArch64 results](../tests/linux-compat/results/2026-10-12/ambient-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/ambient-after-x86_64.json).
Capability-exec also passes on both kernels:
[AArch64](../tests/linux-compat/results/2026-10-12/ambient-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/ambient-cap-x86_64.json).
All eight host test files pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/ambient-audit.v)
checks the failure control, source inventory, isolated builds, frozen sources,
ELF/image/kernel hashes and guest logs. The build uses an isolated V compiler
and library snapshot rather than the changing shared compiler checkout.

The new validation allocates and frees nothing. Capability sets remain
process-wide; these argument checks do not qualify per-thread credentials,
file capabilities or complete application sandbox isolation.

## Capability bounding-set permission precedence

PR_CAPBSET_DROP now checks effective CAP_SETPCAP before validating the
capability number, following [Linux 6.12's cap_prctl_drop](https://github.com/torvalds/linux/blob/v6.12/security/commoncap.c#L1160).
A caller without that capability receives EPERM even for an invalid number.
Privileged invalid drops and all invalid READ requests retain EINVAL.

The V fixture checks six invalid numbers, including values above 2^32 whose
low bits could name a valid capability, for privileged root, root with
CAP_SETPCAP removed only from the effective set, and UID/GID 1000. It checks
all 41 bounding bits after each pair of failures, and valid-number drops
without permission must also return EPERM. All 42 errors leave state intact.
Valid low/high drops succeed repeatedly and leave the current effective,
permitted and inheritable sets intact. A forked child's additional drop stays
private, and an exec retains the parent's low/high bounding drops.

The unchanged fixture exposes the original EINVAL/EPERM mismatch on both
earlier kernels:
[AArch64 control](../tests/linux-compat/results/2026-10-12/capbset-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/capbset-before-x86_64.json).
The fixed kernels pass the bounding-set case and the ambient, securebits,
KEEPCAPS and task-local no_new_privs regressions:
[AArch64 results](../tests/linux-compat/results/2026-10-12/capbset-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/capbset-after-x86_64.json).
The same builds pass capability-exec:
[AArch64](../tests/linux-compat/results/2026-10-12/capbset-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/capbset-cap-x86_64.json).
All eight host test files pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/capbset-audit.v)
checks the failure control, 54 source fingerprints, isolated sources, frozen
guest artifacts and the actual permission-before-validation order in each
generated kernel. The reordered checks allocate and free nothing.

Capability sets remain process-wide. These selected error/transition checks
do not qualify per-thread credentials, file capabilities or full sandbox
isolation; the broader roadmap acceptance gates remain open.

## Capset inheritable bounds and privilege

New capset inheritable bits must belong to the bounding set. Bits already
inherited may survive a later bounding drop. A caller with effective
CAP_SETPCAP may add bounded inheritable bits outside its old permitted set;
without that capability, additions must also come from old permitted.
Authorization uses the old effective set, including when the successful
request itself drops CAP_SETPCAP. The behavior follows
[Linux 6.12's cap_capset](https://github.com/torvalds/linux/blob/v6.12/security/commoncap.c#L228).
The earlier implementation omitted the bounding restriction and applied the
old-permitted restriction even to callers with CAP_SETPCAP.

The V fixture runs six isolated root cases for each of CAP_CHOWN and
CAP_CHECKPOINT_RESTORE, plus an ordinary-user case. It checks bounding
exclusions with and without effective CAP_SETPCAP, bounded additions outside
old permitted, authorization before dropping CAP_SETPCAP, and preservation
of existing inherited bits after bounding/permitted drops. Failed requests
preserve the effective, permitted and inheritable sets, permitted cannot
regrow, and effective cannot exceed permitted. Removing permitted bits clears
their ambient counterparts. The parent's capability/bounding/ambient state
remains intact after each root case.

The unchanged fixture exposes six mismatches on each earlier kernel,
including acceptance of new inheritable bits excluded by the bounding set:
[AArch64 control](../tests/linux-compat/results/2026-10-12/capset-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/capset-before-x86_64.json).
Both fixed kernels pass all 13 cases and the bounding-set, ambient, securebits,
KEEPCAPS and task-local no_new_privs regressions:
[AArch64 results](../tests/linux-compat/results/2026-10-12/capset-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/capset-after-x86_64.json).
Capability-exec also passes:
[AArch64](../tests/linux-compat/results/2026-10-12/capset-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/capset-cap-x86_64.json).
All eight host test files pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/capset-audit.v)
checks both controls, 54 source fingerprints, isolated sources, generated
guards, frozen guest artifacts and stack-only fixture helpers.

The additional scalar checks allocate and free nothing. Capability sets
remain process-wide; these rules do not qualify concurrent per-thread
credentials, file capabilities or complete sandbox isolation. The broad
roadmap acceptance gates remain open.

## Capset caller PID validation

capset accepts header.pid equal to zero or the caller's namespace-visible
thread ID. Other IDs return EPERM before reading capability data, including
negative IDs, missing IDs and siblings in the same process. This follows
[Linux 6.12's capset syscall](https://github.com/torvalds/linux/blob/v6.12/kernel/capability.c#L221).
The earlier implementation looked up targets, returned ESRCH for missing
IDs and accepted any thread belonging to the caller's process.

The V fixture checks all three capability versions with readable, null and
bad data pointers. It exercises root and UID 1000 leaders and siblings,
including a sibling's use of its group leader's ID. Valid zero/self requests
accept unchanged version-3 data; valid IDs with bad data and unreadable
headers return EFAULT. All 236 errors preserve the effective, permitted and
inheritable sets. Release/acquire stage notifications and pthread_join keep
borrowed fixture stack contexts alive until the worker finishes.

The unchanged fixture detects ESRCH in place of EPERM on both earlier kernels:
[AArch64 control](../tests/linux-compat/results/2026-10-12/cappid-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/cappid-before-x86_64.json).
The fixed kernels pass this case and the capset, bounding-set, ambient,
securebits, KEEPCAPS and task-local no_new_privs regressions:
[AArch64 results](../tests/linux-compat/results/2026-10-12/cappid-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/cappid-after-x86_64.json).
Capability-exec also passes:
[AArch64](../tests/linux-compat/results/2026-10-12/cappid-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/cappid-cap-x86_64.json).
All eight host test files pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/cappid-audit.v)
checks the controls, 55 source fingerprints, isolated sources, frozen guest
artifacts, and generated PID validation before data access with no target
lookup. The new guard allocates and frees nothing.

These receipts qualify argument validation in the initial PID namespace.
Nested PID-namespace workflows and per-thread credential isolation remain
unqualified. Capability sets still belong to the process; the broad roadmap
acceptance gates remain open.

## Zero-length pipe and FIFO reads

The pipe resource now returns zero for a zero-byte read before acquiring its
queue lock or checking whether data is present. Previously an empty blocking
pipe waited for input, while a nonblocking pipe returned EAGAIN. This follows
Linux's [pipe reader](https://github.com/torvalds/linux/blob/v6.12/fs/pipe.c#L263),
which handles zero length before locking. Descriptor/access-mode and native
MAC checks still precede the resource call. The early return changes no queue,
poll state or event generation and allocates nothing.

The native V `pipezero` fixture passes seven isolated UID/GID 1000 groups on
AArch64 and x86-64. Tests cover blocking/nonblocking empty anonymous pipes,
populated/full pipes, buffered and drained writer hangup, zero writes after
reader close, and a named FIFO with both ends open. Three buffer forms—null,
unmapped address 1 and a PROT_NONE page—prove that zero-byte calls copy nothing.
Repeated calls preserve FIONREAD and poll readiness. Nonzero reads retain the
queued byte; empty nonblocking reads and full writes retain EAGAIN, EOF returns
zero, and invalid/closed/wrong-access descriptors return EBADF. Each child has
a five-second non-restarting alarm, which must not fire on a passing path.
Root prepares a writable fixture directory before dropping credentials.

Both unchanged-fixture controls on the prior production kernel wait until
the alarm and return `-1/EINTR(4)` for an empty zero-byte read. Both changed
production kernels pass eight cases: pipe I/O, syscall selectors, descriptor
access, constrained opens, runtime primitives, fatal seccomp actions,
seccomp trap/verifier and futex queues. All eight host test files and the
isolated generated inventory check pass.

`pipezero-before-*` and `pipezero-after-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain
controls, frozen fixture/kernel hashes and serial verdicts. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/pipezero-audit.v)
checks the negative controls, every artifact and all seven groups. The source
inventory now includes the pipe implementation, with 61 fingerprints.
The isolated e13e66b1 worktrees change only three lines in the pipe reader;
the coverage generator also records that source. No ownership or reclamation
path changes.

The broader AArch64 ops/churn/cache sweep passes on this same frozen pipe
kernel. All 36 syscall rows retain zero bytes per operation over 200 calls;
true, sleep, curl and BusyBox awk each retain zero bytes per run across 300
executions. The 32 MiB cache workload also completes. The initial two-round
600-second run timed out with only 21 operation rows. Its incomplete report
and raw log are retained alongside the complete one-round run with a
2400-second deadline. The
[storage auditor](../tests/linux-compat/results/2026-10-12/pipezero-storage-audit.v)
requires the complete set of operations, churn and cache results and
deliberately rejects the timed-out report as qualification. Frozen kernel,
generated C, controller, input and report hashes are recorded. These
scenarios run without the desktop; they do not qualify desktop readiness.

Directory read errors, native ELF32/translated pipe entry and complete
section-15 application acceptance remain separate.

## Capability ABI discovery and data format

capget/capset validate the four-byte version word before reading PID or
capability data. An unknown version writes back version 3 without changing
the PID word. A null-data capget discovery probe then succeeds, including
when PID is negative or inaccessible; other unknown-version requests return
EINVAL. Failed preferred-version writes return EFAULT. This follows
[Linux 6.12's version negotiation and syscall order](https://github.com/torvalds/linux/blob/v6.12/kernel/capability.c#L70).

Version 1 transfers one 12-byte entry and clears the unrepresented high word
on capset. Versions 2/3 transfer two entries. Reserved bits above CAP_LAST_CAP
are masked before permission checks, matching
[Linux's capability conversion](https://github.com/torvalds/linux/blob/v6.12/kernel/capability.c#L184).
The previous implementation read an entire header before discovery, returned
EINVAL for successful discovery, ignored preferred-version write faults,
omitted capset writeback, and rejected reserved bits instead of masking them.

The unchanged V fixture detects the old discovery error on both earlier
kernels:
[AArch64 control](../tests/linux-compat/results/2026-10-12/capabi-before-aarch64.json),
[x86-64 control](../tests/linux-compat/results/2026-10-12/capabi-before-x86_64.json).
Both fixed kernels pass root and UID 1000 discovery/writeback checks, unchanged
PID words, readonly faults, four-byte headers before PROT_NONE, partial version
words, exact data sizes and reserved-bit masks. Six isolated children check
data/state behavior for each version, including legacy truncation. Native
page sizes are 16 KiB on AArch64 and 4 KiB on x86-64.
The same builds pass the seven earlier capability/thread cases:
[AArch64 results](../tests/linux-compat/results/2026-10-12/capabi-after-aarch64.json),
[x86-64 results](../tests/linux-compat/results/2026-10-12/capabi-after-x86_64.json).
Capability-exec also passes:
[AArch64](../tests/linux-compat/results/2026-10-12/capabi-cap-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-12/capabi-cap-x86_64.json).
All eight host test files pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/capabi-audit.v)
checks the controls, 55 source fingerprints, isolated sources, frozen guest
artifacts, generated four-byte version handling and masks, and fixture helpers
without V allocation/indexing runtime calls. The new kernel helper keeps its
version word on the stack and allocates/frees nothing on either architecture.

These are native ELF64 tests of the three capability data formats. They do
not qualify a 32-bit application runtime, per-thread capability storage or
file capabilities. The broad roadmap acceptance gates remain open.

## Task-local seccomp and TSYNC

The native musl ELF64 `seccompthread` fixture passes on AArch64 and x86-64.
Filters belong to each task; clone, fork and exec inherit the caller's chain.
A nonleader exec preserves its own chain while retiring a differently filtered
leader. Procfs selects the requested live task and keeps scalar leader state
after its Thread is reclaimed. Eleven isolated cases cover these transitions,
concurrent thread creation/synchronization, and the exact 32768-instruction
path bound (four extra instructions per predecessor, none for the new leaf).

TSYNC validates every live sibling before publishing anything. Disabled tasks
and ancestors of the caller's chain can synchronize; a descendant, divergent
chain or independently installed identical program cannot. A failure returns
the offending namespace-visible TID, or ESRCH with TSYNC_ESRCH, and leaves
filters and no_new_privs unchanged. Successful synchronization propagates a
set caller flag and preserves existing sibling flags when the privileged
caller has not set its own. This follows
[Linux's reference, ancestry and synchronization implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L438).

Both baseline kernels fail the same unchanged V fixture because a peer's
filter incorrectly changes an unfiltered caller's mode and getpid result.
`seccompthread-before-*` and `seccompthread-after-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain
controls, receipts and serial logs. Final production kernels pass eight cases:
task seccomp, trap/verifier, action discovery, no_new_privs, securebits,
capability ABI, TLS/atomics/SIMD/JIT/page sizes and futex queues. The existing
capability-exec suite and all eight host test files also pass.

Each immutable filter holds a reference to its predecessor; each task holds
its head. Evaluation takes the filter lock through the bounded interpreter
and creates no heap object. Attachment allocates outside publication locks;
failed attachment leaves instruction ownership with the syscall caller.
Natural final reaping and quiescent forced sibling retirement release heads,
including exec's stopped leader. A separate lifetime review checked the V
sources and generated C on both architectures. The assertion-enabled
[auditor](../tests/linux-compat/results/2026-10-12/seccompthread-audit.v) checks
60 source fingerprints, frozen artifacts, generated stack storage, exact
errors, both storage cohorts and the preexisting validation failures.
Kernel fingerprints and the generated inventory describe isolated 71d666c4
worktrees with the twelve seccomp changes; concurrent shared-checkout procfs
net/dev edits were excluded from these builds and receipts.

Two cohorts create 400 naturally exiting threads with 1600 filters and 200
forced nonleader exec groups with another 1600 filters. After warmup and grace
periods, all 32/64/96/128-byte live-object counts stay flat on both native
architectures; the 80-byte header uses class 96 and the four-instruction
buffer uses class 64. An additional ALLOC_TRACK=1 AArch64 run also passes both
cohorts. The broader AArch64 ops/churn/cache run passes: all 36 syscall rows
retain zero bytes per operation, and true, sleep, curl and BusyBox awk each
retain zero bytes per run over 300 runs.

Two limits surfaced during verification and remain explicit. Procfs pruning
removes task/process names but retains backing trees; the storage cohorts
therefore use raw mode/syscall queries and a fixed executable path after the
functional procfs cases. This qualifies filter storage, not procfs reclamation.
The frozen V f6358ec compiler's allocation-allowance check fails on both the
unmodified baseline and changed sources; the changed inventory adds no sites
and removes two reported sites per architecture. Baseline/current logs are
retained, and the existing allowance failure is not reported as passing.
Desktop idle/apps/drag validation with the cached live desktop fails before
readiness on both kernels with the same startup error. Those receipts remain
failed; this change does not qualify desktop readiness.

At this snapshot, strict-mode and KILL_THREAD signal scope remained unqualified;
the following qualifications cover those paths and installation error ordering.
User notifications, full sandbox isolation, nested PID-namespace TSYNC failures
and procfs tree reclamation remain separate work. The three broad section-15
acceptance gates remain open.

## Seccomp fatal action scope

The native musl ELF64 `seccompkill` fixture passes eleven isolated UID/GID 1000
cases on AArch64 and x86-64. KILL_THREAD, including nonzero action data, kills
only the triggering task with SIGSYS. Strict-mode forbidden getpid and
exit_group kill that task with SIGKILL. Its sibling remains able to make
syscalls, catches no SIGSYS, observes CHILD_CLEARTID and gets ESRCH for the
retired TID. KILL_PROCESS and unknown actions still kill the entire group.
When the killed task is the last one, wait reports the original SIGSYS or
SIGKILL instead of converting it into an ordinary exit code. This follows
[Linux's strict-mode enforcement](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L962)
and [fatal filter actions](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L1230).

Additional cases execute strict-mode read, write and raw SYS_exit, deliver a
caught SIGUSR1 and return through the architecture's actual signal trampoline.
A strict sibling prevents TSYNC with a positive offending TID or ESRCH,
without changing the caller's mode. The V fixture calls musl's unchanged
`__clone` trampoline through an external declaration; its public clone wrapper
refuses CLONE_THREAD/CLEARTID before reaching the kernel. No C implementation
was added. A separate lifetime review checked the kernel's generated C and
the fixture's borrowed Task frame: successful retirement precedes stack unmap,
and a failure after cloning exits the group before returning from that frame.

Both baseline kernels kill the entire group in the first KILL_THREAD case.
The unchanged fixture records outcome 31 where the surviving sibling should
exit normally. `seccompkill-before-*` and `seccompkill-after-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain
the controls, receipts and raw serial logs. Final production kernels pass
seven regression cases: task/group termination, task ownership/TSYNC,
trap/verifier, action discovery, no_new_privs, TLS/atomics/SIMD/JIT/page sizes
and futex queues. Both 3200-filter storage cohorts retain flat
32/64/96/128-byte slab classes. All eight host test files pass.

The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/seccompkill-audit.v)
checks the negative controls, frozen sources/artifacts, eleven verdicts,
retirement markers, storage cohorts and allocation-free outcome wrappers in
both generated kernels. The 60 source fingerprints describe isolated
1c2e33ce worktrees with the three kernel changes; concurrent shared-checkout
edits were excluded from the qualification builds.

Core dumps, foreign/ELF32 execution, libc pthread cancellation/unwinding and
complete application sandbox isolation remain unqualified. This closes the
tested native fatal-action semantics; the three broad section-15 acceptance
gates remain open.

## Seccomp installation error precedence

Native musl ELF64 syscall/prctl installation follows the Linux validation
order: copy the complete sock_fprog header, validate its instruction count,
check the calling task's no_new_privs/CAP_SYS_ADMIN, then copy and verify the
instruction program. An unreadable header returns EFAULT and a zero or
over-4096 count returns EINVAL even for an unauthorized task. With a readable
valid-length header, an unauthorized task gets EACCES before instructions are
read; authorized tasks get EFAULT for unreadable instructions or EINVAL for
invalid bytecode. This follows
[Linux's user-header copy and filter preparation](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L618).
Unknown syscall flags still return EINVAL before reading the header.

The V `seccompinstall` fixture passes 446 checked calls in each of five
isolated groups on both architectures: root with CAP_SYS_ADMIN, root without
that capability, UID 1000 with a clear flag, UID 1000 with no_new_privs and
root without CAP_SYS_ADMIN with no_new_privs. Its 2230 checks include null,
bad and partial-page pointers, readonly headers, exact eight-byte instruction
boundaries, unaligned headers and ignored sock_fprog padding. Rejections
preserve mode and no_new_privs, including 400 repeated invalid-program calls
per group. Valid ALLOW programs prove both capability and NNP authorization.
The fixtures record AArch64's 16384-byte and x86-64's 4096-byte native pages.

Both baseline kernels fail the same unchanged fixture: after the privileged
group passes, a root task without CAP_SYS_ADMIN gets EACCES instead of EFAULT
for an unreadable header. `seccompinstall-before-*` and `seccompinstall-after-*`
in the [dated results directory](../tests/linux-compat/results/2026-10-12/)
retain the exact diagnostics, receipts and serial logs. The reusable
`nnpthread` probe now checks header EFAULT in both flag states, then checks
EACCES/EFAULT using a readable valid-length header with unreadable instructions.
Both syscall interfaces retain the caller's state across independent siblings,
clone, fork, exec and direct nonleader exec. The previous malformed-header
authorization oracle and its historical receipts are explicitly superseded.

Both production kernels pass eight regression cases: installation errors,
thread NNP/inheritance, NNP argument errors, task seccomp/TSYNC, fatal action
scope, trap/verifier, action discovery and TLS/atomics/SIMD/JIT/page sizes.
The 3200-filter natural/forced-retirement cohorts keep all four measured slab
classes flat. All eight host test files and the isolated generated-inventory
check pass. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/seccompinstall-audit.v)
checks the controls, 60 fingerprints, frozen artifacts, emitted validation
order, stack-local header, unchanged instruction cleanup and verdicts.
These isolated 1d4080c8 worktrees change only the installation helper; no
allocation or reclamation implementation was added.

Allocation-pressure behavior, user notifications, foreign/ELF32 execution and
complete sandbox isolation remain unqualified. The three broad section-15
acceptance gates remain open.

## Seccomp fallible instruction storage

Seccomp installation now allocates instruction bytes through the fallible
kernel allocator and returns ENOMEM for a nil result. The previous V array
constructor could enter its panic-on-OOM allocation path. Header, length and
permission validation still precede allocation; instruction copying follows
the nil check. The raw allocation is wrapped in a stack-local array header
with `.nogrow`, explicitly clearing V's managed-array metadata flag. Failed
copy, verification or attachment frees the raw pointer once; successful
attachment transfers it into the existing immutable ref-counted filter chain.

The unchanged V `seccompalloc` fixture records four root/UID 1000 syscall/prctl
cohorts on each architecture. Both ordinary baseline and new production
kernels accept its valid 4095-instruction ALLOW program. Separate test builds
using `VFLAGS='-d seccomp_alloc_selftest'` inject a nil result at the allocation
boundary and require ENOMEM, even with an unreadable instruction pointer.
Failure preserves mode/no_new_privs, and a subsequent small filter and getpid
must succeed. The injection is compiled out of production. This tests the
allocator-nil branch; it does not simulate exhaustion of all physical memory.

Each cohort warms 128 rejected copies, waits for reclamation, then repeats
128 calls and checks unchanged large-allocation page counts. These buffers
use the big allocator, including a metadata page: three 16 KiB AArch64 pages
or nine 4 KiB x86-64 pages. They do not use a 32768-byte slab class. The
3200-filter natural/forced-retirement cohorts also keep 32/64/96/128-byte
live-object counts flat on both production and injection builds. Four-instruction
programs now use a raw 32-byte allocation; filter headers still
use class 96. Large-copy measurements qualify rejected-buffer cleanup; small
filter cohorts separately qualify published-chain retirement.

Both production kernels pass eight regression cases, and both injection
kernels pass allocation handling plus task/TSYNC retirement. All eight host
test files and the isolated generated inventory check pass. A separate
lifetime review checked all four generated kernels and the identical V fixture
C: stack headers/data remain live through synchronous copying, `.nogrow`
selects raw-pointer freeing, and no hidden fixture heap allocation occurs.
The frozen compiler reports the same 406 AArch64 and 297 x86-64 allocation
sites before and after; its existing allowance failures remain explicit.

`seccompalloc-before-*`, `seccompalloc-after-*` and `seccompalloc-fault-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain the
ordinary controls, production/injection receipts and serial logs. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/seccompalloc-audit.v)
checks the outcomes independently and deliberately rejects treating a
production-success transcript as an allocation-failure transcript. It verifies
60 source fingerprints, frozen guest artifacts, emitted header flags/free
paths, page/object retention and unchanged allocation-site counts. These
isolated a11caa1b worktrees change only the kernel installation helper; the
inventory includes the physical allocator.

The broader AArch64 ops/churn/cache run also passes: all 36 syscall rows retain
zero bytes per operation, and true, sleep, curl and BusyBox awk each retain
zero bytes per run over 300 runs. Desktop idle/apps/drag with the same frozen
cached binary fails before readiness on both baseline and changed kernels.
Both empty measurement reports, raw failure logs and the binary input hash
are retained. That existing startup failure remains an open qualification.

Physical OOM recovery, exhaustive allocation/error precedence, notifications
and foreign/ELF32 execution remain unqualified. The broad section-15 acceptance
gates remain open.

## Native syscall selectors and private verdict dispatch

Native dispatch now uses the low 32 bits of the syscall-number register and
records the signed C-int value for syscall metadata. This follows Linux's
[x86-64 entry](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/common.c#L38)
and [AArch64 entry](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/kernel/syscall.c#L68).
The unsigned dispatch index also keeps negative selectors outside AArch64's
assembly table bounds. Saved registers retain all 64 bits for signal frames
and restart. On x86-64, seccomp TRAP restores the original number register,
following Linux's [rollback before SIGSYS](https://github.com/torvalds/linux/blob/v6.12/kernel/seccomp.c#L1167).

Number 511 is an internal verdict slot, rather than a Linux syscall. Ordinary
requests now return ENOSYS instead of zero or a stale prior filter result.
Seccomp still inspects unknown syscall numbers: an actual ERRNO(0), EACCES or
TRAP verdict may select the internal handler. ALLOW/LOG on number 511 reaches
ENOSYS. Only real verdicts may access the private slot.

The native V `sysnr` fixture passes seven isolated UID/GID 1000 groups on each
architecture. Four prefixes exercise raw 64-bit selector registers: zero,
one high bit, a mixed high word and all high bits. Tests cover unknown,
negative and x32-tagged numbers; getpid/gettid/getuid/getgid; filtered unknown
calls; refusal after a stale errno result; eight caught SIGSYS traps; strict
read/write/exit; and a blocked read interrupted by SA_RESTART. Trap checks
include architecture, syscall metadata, call address, original register and
handler-changed return value. The strict case uses a primed pipe; it does not
qualify zero-length reads from an empty pipe.

Both unchanged-fixture controls on the previous production kernel fail at
number 511, returning `0/0` instead of `-1/ENOSYS(38)`. Both changed kernels
pass eight regression cases, including filter ownership/TSYNC, fatal actions,
NNP, runtime primitives and futex queues. The 3200-filter natural/forced
retirement cohorts keep their four measured object classes flat. Separate
four-CPU job-control suites pass group stops, blocked message restart, caught
handler restart/EINTR, teardown and 400 stop/continue storage cycles. All eight
host test files and the isolated generated inventory check pass.

`sysnr-before-*`, `sysnr-after-*` and `sysnr-jobs-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain
controls, artifacts, verdicts and serial logs. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/sysnr-audit.v)
checks 60 input fingerprints, frozen kernels/fixtures, the emitted integer
casts, private dispatch guards and original-register preservation. The
isolated ee6a8aae worktrees change four scalar/control-flow kernel files and
introduce no allocation or reclamation. These native ELF64 checks do not
qualify native ELF32/x32 or translated ABI entry. The three broad section-15
acceptance gates remain open.

## Scalar directory read errors

Scalar read(2) now rejects directory handles with EISDIR at zero and nonzero
counts. The old tmpfs-backed directory path reported an empty successful
read. Directory handles now fail after descriptor/access/native MAC checks
without reading backing bytes or advancing the offset. Nonzero user ranges
are validated before the directory type, while destination probing and
scratch allocation follow it. Thus a valid-range unmapped or protected
destination still gets EISDIR without being accessed, and a range outside
userspace gets EFAULT. This follows Linux's
[VFS validation](https://github.com/torvalds/linux/blob/v6.12/fs/read_write.c#L518)
and [directory read operation](https://github.com/torvalds/linux/blob/v6.12/fs/libfs.c#L209).
The kernel-buffer read path also refuses directory byte reads; directory
enumeration continues to use getdents.

The native V `readerror` fixture passes 64 checks each as root and UID/GID
1000 on both architectures. Root, tmpfs, procfs and sysfs directories are
read with zero, one and 4096 bytes using valid, unmapped and PROT_NONE
buffers, plus a null zero-length destination and an invalid nonzero range.
Failed reads leave directory offsets intact. Invalid and wrong-access
descriptors retain EBADF. Ordinary regular files retain zero-read offsets,
byte contents and EOF behavior. Root prepares a writable test directory,
and each credential phase creates its own file.

Both unchanged-fixture controls on the previous production kernel fail the
first zero-length directory read with `0/0` instead of `-1/EISDIR(21)`.
Both changed production kernels pass eight regression cases: directory
reads, pipes, syscall selectors, descriptor access, constrained opens,
runtime primitives, seccomp trap/verifier and futex queues. All eight host
test files and the isolated generated inventory check pass.

`readerror-before-*` and `readerror-after-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain
negative controls, artifacts and serial verdicts. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/readerror-audit.v)
verifies all 61 fingerprints, frozen fixture/kernel hashes, 128 checked
results per architecture and the emitted validation order. The isolated
08316b06 worktrees change only two directory guards in the handle layer;
no allocation, ownership or reclamation path is added. Vectored, O_PATH,
later usercopy faults and foreign/ELF32 read semantics remain separate.
The three broad section-15 application acceptance gates remain open.

## O_PATH and vector access errors

pread/pwrite now reject O_PATH before directory/FIFO type errors, retaining
the existing descriptor reference through the early EBADF return. Scalar
read/write already refuse O_PATH through the native access-mode mask, which
includes O_PATH; those paths did not require a new guard. Vector read/write
now validate descriptor existence, O_PATH and read/write mode before importing
iovecs, including empty/all-zero vectors. Previously an empty O_PATH vector
could report successful zero-byte I/O, and an invalid vector could mask EBADF
with EFAULT. This follows Linux's
[vector access checks](https://github.com/torvalds/linux/blob/v6.12/fs/read_write.c#L950)
and [documented O_PATH contract](https://man7.org/linux/man-pages/man2/open.2.html).

At this qualification revision, the vector helper snapshots flags while its
lookup reference is live, then releases that reference and uses only the scalar
access bits. It creates no
object and retains no pointer. The existing I/O paths continue to acquire
their own references; descriptor identity during concurrent close/reuse across
an entire vector remains separate work. The permission check also replaces
the previous empty-vector descriptor lookups.

The native V `pathio` fixture passes 240 checks each in root and UID/GID 1000
children on both architectures. Tests cover O_PATH handles for a regular
file, directory, FIFO and unfollowed symlink, and duplicate descriptors.
Zero/one-byte scalar and positioned reads, zero writes, nonempty reads,
empty/all-zero vectors and unreadable iovec pointers require EBADF. Metadata
and O_PATH status flags remain usable. Ordinary opens of a root-owned
mode-0600 file require EACCES; existing scalar I/O refusal remains intact.
Additional controls check invalid and wrong-access descriptors before iovec
faults, valid two-iovec regular file I/O and successful zero vectors.

Both unchanged-fixture controls fail as UID 1000 at the empty O_PATH readv,
returning `0/0` instead of `-1/EBADF(9)`. Both changed production kernels pass
eight regression cases: O_PATH/vector access, directory reads, pipes,
constrained opens, shared-memory metadata, runtime primitives, seccomp
trap/verifier and futex queues. All eight host test files and the isolated
inventory check pass. The inventory now fingerprints the resource access-mode
constants as well, for 62 inputs.

`pathio-before-*` and `pathio-after-*` in the
[dated results directory](../tests/linux-compat/results/2026-10-12/) retain
controls and serial verdicts. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-12/pathio-audit.v)
checks frozen kernels/fixtures, all 480 outcomes per architecture and emitted
validation/reference order. An independent lifetime review checked both
generated kernels and the fixed fixture buffers: one transient lookup release,
no pointer use afterward, existing deferred releases on positioned error
returns, and stack/mapping lifetimes through synchronous calls. The isolated
4f30c2944 worktrees change two kernel files and the inventory generator;
no allocation or reclamation implementation is added.

Other O_PATH APIs, complete positioned-vectored/error ordering,
foreign/ELF32 paths and full application acceptance
remain unqualified. The broad section-15 gates remain open.
Concurrent descriptor identity is qualified by the later change below.

## Vectored I/O descriptor lifetime

readv and writev now retain one descriptor lookup reference until the complete
call returns, matching Linux's
[single open-description reference](https://github.com/torvalds/linux/blob/v6.1/fs/read_write.c#L888).
Previously readv looked up the number for each iovec and writev looked it up
for each buffer flush. A concurrent close or dup2 could therefore redirect
the remainder to a replacement file, fail with EBADF after partial I/O, or
release an original pipe endpoint before the vector completed. The VFS helpers
borrow the retained descriptor and preserve access checks, MAC/device policy,
file accounting and inotify events. Scalar read/write retain their existing
lookup and deferred release around those same helpers.

The V `iovpin` fixture qualifies 32 blocked readv and 24 multi-chunk writev
calls per native architecture, split between root and UID/GID 1000 children.
Read tests replace the descriptor with another pipe, a regular file, a
write-only endpoint or leave it closed. After removing the only user reader,
the original writer must lack POLLERR: the blocked syscall's reference keeps
the old endpoint alive. Only then does the peer supply the two original bytes.
Replacement contents and regular-file offsets must remain untouched.

Write tests send 1,052,673 bytes through two iovecs, crossing the 1,048,577-byte
kernel buffer bound. Queued bytes in the original pipe prove that its first
write has entered and blocked before the descriptor is replaced with another
writer, a read-only endpoint or closed. The peer verifies every byte on the
original pipe and drains to EOF. The replacement receives no bytes, and EOF
also proves that the final syscall reference is released.

All 56 concurrency cases fail on each unchanged production kernel: pipe/file
read replacements yield `41,58` instead of `41,42`, closed/wrong-mode read
descriptors return one byte, replacement writers receive the final 4096 bytes,
and closed/wrong-mode writers return only 1,048,577 bytes. Both changed kernels
pass all cases. Each credential group also runs 32 warmup and 200 measured
pipe/vector cycles covering success, empty vectors, invalid counts/headers,
invalid payload pointers and wrong access modes. Every live slab class stays
flat, and big pages stay at 63/63 on ARM and 160/160 on x86. These measurements
cover the scoped vector workload, rather than a whole-desktop retention test.

The [dated receipts](../tests/linux-compat/results/2026-10-13/) and
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovpin-audit.v)
retain both native controls, kernel/fixture/init/ISO/source hashes, raw logs,
and nine regression cases per architecture. The auditor retains and rejects an earlier
fixture compilation failure as a native control and checks the actual slab
counts independently. All eight host test files and the 62-input isolated
inventory check pass. An independent review of both generated kernels and
fixtures verified paired FD/Handle ownership, all error/partial returns,
borrowed notification paths, stack snapshots, worker join and failure exits.

Shared file-offset atomicity across a whole vector,
Linux stream short-read/message behavior and translated/ELF32 variants remain
unqualified. The three broad Linux/POSIX acceptance gates stay open.
Immutable headers have later qualification below.

## Immutable iovec imports

readv/writev now copy all iovec headers once, before resource I/O, following
Linux's [header import contract](https://github.com/torvalds/linux/blob/v6.12/lib/iov_iter.c#L1314).
The earlier validation pass copied headers only to check them, then each I/O
step copied its header again. A peer could change a later buffer address after
validation, or protect/unmap the array while the first pipe operation waited.
Reads could then consume data into another destination or return EFAULT after
consuming their first byte; writes could send another source's bytes or return
a short success after writing their first chunk.

Up to eight headers borrow 128 bytes allocated in the syscall frame. Larger
vectors own one raw allocation bounded to 16 KiB, with a scratch reservation
through the existing allocator-geometry helper. In particular, ARM allocations
can need a 16 KiB metadata page as well as rounded data pages; a simple twice-
payload reservation undercovers some requests. Admission precedes allocation,
allocator nil reports ENOMEM, copy/aggregate-length failures release storage,
and every successful import releases its owner on all final I/O outcomes.
Descriptor references continue to cover the whole call.

The V `iovimport` fixture runs 40 readv and 40 multi-chunk writev cases per
architecture, split between root and UID/GID 1000 children. It imports readonly
2/8/9/513/1024-entry arrays, then changes a later address or applies PROT_NONE
while I/O waits. Read tests observe the first read's scratch reservation after
import through a preopened `/proc/kernel-resources`, and verify the original
reader reference with the writer's readiness after closing the user descriptor.
Write tests wait for queued bytes before mutation, then drain to EOF and verify
all 1,052,673 original bytes. These checkpoints also work on the old kernel.
Worker failure paths terminate the isolated child while its borrowed buffers
remain live; successful paths join before releasing mappings or stack data.

All 80 cases fail on each unchanged kernel: changed read addresses receive the
second byte, protected headers cause `-1/EFAULT(14)` after the first byte,
changed write sources produce the wrong final 4096 bytes, and protected write
headers return only 1,048,577 bytes. Both changed kernels pass every case.
Each credential group also runs 32 warmup and 200 measured cycles over all
five vector counts, covering successful and empty vectors, header/payload
faults, wrong modes and aggregate-length rejection. Every slab class remains
flat, with big pages at 63/63 on ARM and 160/160 on x86. The earlier descriptor
race and retention fixture also passes on the new kernels.

Both architectures pass ten regression cases, and all eight Linux compatibility
host tests pass. The maintained mapping-storage host test passes the geometry,
admission, rollback and owner-lifetime checks. The allocation-site audit still
fails its existing allowances: both controls and candidates report 406 ARM and
295 x86 sites, with identical allowance-failure rows. No allowance is increased,
and this audit is not reported as passing. Independent review of both emitted
kernels and all four fixture C captures verified stack borrows, reservation
coverage, raw ownership, partial/error returns, observer option paths and
asynchronous mapping/stack lifetimes.

The [dated results](../tests/linux-compat/results/2026-10-13/) retain
`iovimport-before-*`, `iovimport-after-*`, both allocation-audit logs and host
results. The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovimport-audit.v)
checks frozen kernels, sources and artifacts, actual slab counts, all native
control failures, geometry/reference order, and rejection of a passing run as
a failing control. The inventory retains 62 input fingerprints.

Positioned vectors still use their earlier import path. Linux MAX_RW_COUNT
clamping and complete range/length precedence, shared-offset atomicity, stream
message behavior, actual allocator exhaustion and translated/ELF32 qualification
remain separate work. The broad section-15 gates remain open.

## Native vector ranges and transfer counts

readv/writev now reject malformed payload ranges before resource I/O. Each
length must fit in signed ssize_t, and all such length checks precede range
checks. Every original range, including a zero-length tail beyond userspace,
must pass the canonical address check. The imported total is capped at
`INT_MAX & PAGE_MASK`, with copied lengths truncated to the remaining count.
Linux's single-segment path caps its length before checking its range; multiple
segments check their original ranges, even after reaching the cap. See
[Linux 6.12's importer](https://github.com/torvalds/linux/blob/v6.12/lib/iov_iter.c#L1284),
[range predicate](https://github.com/torvalds/linux/blob/v6.12/include/asm-generic/access_ok.h#L29)
and [count limit](https://github.com/torvalds/linux/blob/v6.12/include/linux/fs.h#L2511).
Existing copied-header ownership and descriptor references cover these errors.

The V `iovrange` fixture checks 215 cases in each root and UID/GID 1000 child,
using 2/8/9/513/1024-entry arrays on regular files, pipes and UNIX stream/datagram
sockets. Invalid later ranges require EFAULT before changing the first buffer,
file offset/content, queued pipe bytes or socket messages. Cases include zero
tails outside userspace, boundary-crossing and wrapping ranges, and a positive
SSIZE_MAX length. Signed-invalid later lengths require EINVAL before an earlier
invalid range. A PROT_NONE destination inside userspace remains a copy-time
fault; a regular read retains its completed first-vector prefix.

Fourteen EOF checks exercise the single/multiple-segment distinction, valid
counts above the cap and invalid tails beyond it. No 2 GiB buffer or transfer
is needed: EOF must succeed when the capped range fits, and an original range
that fails validation must report EFAULT before EOF. The cap is 2,147,467,264
bytes with ARM's 16 KiB pages and 2,147,479,552 with x86's 4 KiB pages.
Fixed MAP_FIXED_NOREPLACE probes measure the active address limit, map/unmap
its last page and require refusal of the next page before retention warmup.
The qualified guests have 47-bit ARM and 56-bit x86 ranges. The first x86
fixture incorrectly assumed 47 bits; its rejected run is preserved separately
and contributes no passing qualification. A corrected x86 attempt passed this
fixture but disk exhaustion interrupted receipt writing; its log is preserved
separately. The fresh x86 run completed seven cases before disk exhaustion
interrupted sharedmem staging. Its original receipt retains that failed row;
four unfinished cases pass in a resumed run against the identical frozen
kernel. The audit verifies both runs and uses only completed passing cases.

Each unchanged kernel fails 121 checks per credential group. It can consume
the first byte before rejecting a later malformed range, accept an invalid
zero tail, and return EINVAL for a positive length whose range requires EFAULT.
Both fixed kernels pass all 430 checks. Each credential group runs 32 warmup
and 200 measured cycles through stack/heap range/length errors and EOF count
boundaries, checking every live slab class and big-page count. Both stay flat.
The earlier header and descriptor race/retention fixtures also pass.

Both architectures pass eleven regression cases; all eight compatibility host
tests and the mapping-storage geometry test pass. Allocation-site audits still
fail the same existing allowances: 406 ARM and 295 x86 sites, with identical
failure rows and no increased allowances. Independent review of the emitted
kernels and fixtures approved cleanup, guarded subtraction and bounded stack
storage, including the new address-probe mappings.

The [dated results](../tests/linux-compat/results/2026-10-13/) publish
`iovrange-before-*`, `iovrange-after-*`, the rejected x86 limit-oracle run,
the interrupted receipt-writing log, `iovrange-resumed-x86_64`, host checks
and both allocation-audit logs. The
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovrange-audit.v)
verifies frozen inputs/artifacts, the native failures, passing regressions,
retention and rejection of passing output as a negative control. The inventory
retains 62 input fingerprints.

Actual transfers at the 2 GiB cap, positioned vectors, tagged ARM pointers,
four-level x86 runs, partial header-copy precedence, shared-offset atomicity,
stream message conformance, allocator exhaustion and translated/ELF32 paths
remain separate qualification work. The three broad section-15 gates stay open.

## Native positioned-vector offsets

Native AArch64/x86-64 preadv, pwritev, preadv2 and pwritev2 now use the complete
signed 64-bit offset in pos_l and ignore pos_h. The old helper combined two
32-bit halves, although that is the compat layout. A native caller's high
offset bits could be discarded, or unrelated pos_h bits could redirect I/O
or create a false negative offset. See [Linux 6.12's native and compat
decoders](https://github.com/torvalds/linux/blob/v6.12/fs/read_write.c#L1060).

v1 now rejects all negative offsets before header/descriptor handling. v2
rejects offsets below -1 before that handling; only its -1 case uses the
current file position through the existing readv/writev path. Previously v1
shared v2's sentinel behavior, while a native v2 -1 with pos_h zero became
the positive offset 4 GiB - 1. No new kernel allocation or lifetime is added.

The V `iovoffset` fixture runs 348 cases in each root and UID/GID 1000 child:
78 explicit-position cases, 252 negative-offset cases and 18 sentinel cases.
Raw calls vary all four syscall numbers and six pos_h values at 4 GiB + 123,
8 GiB - 1 (two iovecs cross the boundary), and 8 GiB + 17. Scalar pread/pwrite
seed and verify distinct bytes at each requested offset and its lower 32-bit
alias. Results must preserve file size, allocated blocks and the shared cursor.
Public musl preadv/pwritev wrappers exercise the same data checks.

Negative cases cover -1, -2, INT64_MIN and INT64_MIN + 123, bad headers/counts
and invalid descriptors; v2 -1 is tested separately. It must read/write at the
current regular-file offset and advance it, and work on nonblocking pipes.
v1 -1 must retain EINVAL without consuming or queuing pipe bytes. Every fixture
borrow is synchronous, and acquired descriptors close on all returns.

Both unchanged kernels fail 60 raw offset cases, 144 negative cases and 14
sentinel cases per credential group. Reads return lower-alias bytes, writes
overwrite those aliases, ignored high-word bits cause EOF or EINVAL, and
sentinel pipe calls return ESPIPE or incorrectly perform v1 I/O. The six public
musl cases already pass on these controls; they are preservation checks, not
evidence of a previously failing musl wrapper. Both fixed kernels pass all
696 cases per architecture.

Each credential group runs 32 warmup and 200 measured cycles through valid
raw/public calls, negative refusals and file/pipe sentinels. Every slab class
and big-page count stays flat: 321/321 on ARM and 4,258/4,258 on x86. The reused
sparse file's page-slot metadata stays live during measurement; this is not
an allocation of the entire 8 GiB payload. The native range fixture also stays
flat. Both architectures pass eight guest regression cases and all eight
compatibility host test files. Allocation-site audits still fail the same
existing allowances, with 406 ARM and 295 x86 sites and identical failure rows;
no allowance is increased.

The [dated results](../tests/linux-compat/results/2026-10-13/) publish
`iovoffset-before-*`, `iovoffset-after-*`, host checks and both allocation-audit
logs. The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovoffset-audit.v)
verifies frozen inputs, kernels, emitted C and init/ISO artifacts, actual
control failures and passing regressions, retention, and rejection of passing
output as a negative control. Independent lifetime review approved both
generated kernels and the synchronous stack/descriptor paths. The inventory
retains 62 input fingerprints.

GNU libc wrappers and ELF32/translated variants need separate qualification.
Positioned header/descriptor lifetime, positive-offset error ordering, flags,
MAX_RW_COUNT, shared-offset atomicity, disk-backed files and allocator
exhaustion remain open. The three broad section-15 gates stay open.

## Native positioned-vector imports and errors

Positive-offset preadv/pwritev and their v2 forms now retain one descriptor
reference and import the headers once through the same bounded owner as
readv/writev. Each segment calls a scalar helper that borrows that descriptor;
it cannot resolve a replacement descriptor number. The scalar wrappers retain
their existing validation and release their reference after the borrowed
helper returns. v2's current-position -1 case delegates directly to the
existing unpositioned path, without a preliminary header scan.

Invalid/O_PATH descriptors return EBADF before header faults or count errors.
Pipe/FIFO/socket positioned calls return ESPIPE before import, including empty
vectors and wrong access modes. Regular-file access errors also precede import.
Every signed length and original canonical range is checked before I/O, with
the existing single-entry versus multiple-entry MAX_RW_COUNT rules. The whole
imported transfer must fit the signed file-position range before any segment
runs. These ordering rules follow [Linux 6.12's positioned and vectored
paths](https://github.com/torvalds/linux/blob/v6.12/fs/read_write.c#L940) and
[its O_PATH-filtering descriptor lookup](https://github.com/torvalds/linux/blob/v6.12/fs/file.c#L1056).

The V `iovposition` fixture runs 396 checks in each root and UID/GID 1000
child: 192 descriptor/access/seek cases, 48 current-position access cases,
100 range/length cases, 20 valid header cases, four payload-prefix cases,
four signed-position-overflow cases and 28 EOF transfer-cap boundaries.
Headers containing 2/8/9/513/1024 entries cover both the syscall stack and
the existing fallible heap import; valid headers are mapped with read
permission only. Refusals must retain file contents, the shared cursor,
destination bytes and pipe/socket queues. PROT_NONE payloads still return
the prefix already copied. Fixed mmap probes measure the native user limit.

Both unchanged kernels fail 148 descriptor cases, 16 current-position cases,
80 range cases and all four signed-position cases per credential group, plus
both 14-check EOF-cap groups. Empty unusable vectors incorrectly return zero;
header errors displace descriptor errors; later malformed ranges can return a
partial result and alter the first byte. Offset overflow can return EOF or
EFBIG instead of EINVAL. RLIMIT_FSIZE=1024 bounds the unchanged write-overflow
control; it never attempts to allocate a file near INT64_MAX. Normal and
payload-prefix controls already pass. Both fixed kernels pass all 792 checks
per architecture, with identical fixture C across each before/after pair.

Each credential group warms 32 cycles and measures 200 cycles of valid,
empty, malformed and overflowing imports. Every slab class stays flat,
as do big-page counts: 66/66 on ARM and 168/168 on x86. Independent source
and generated-C lifetime review verifies importer failure cleanup, one FD
owner, borrowed scalar helpers, release ordering and bounded synchronous
fixture borrows. This is implementation and retention evidence; a
deterministic positioned close/dup2/header-mutation race remains unqualified.

Eleven native guest regressions pass per architecture: positioned imports,
offsets, vector ranges, immutable headers, descriptor pinning, O_PATH access,
openat2, directory errors, zero-byte pipes, runtime and shared memory. Eight
compatibility host test files and mapping-storage geometry checks pass.
Allocation audits still fail the same existing allowances with 406 ARM and
295 x86 sites; only two diagnostic source line numbers move, and no
allowance or site count is increased. The generated inventory retains 62
input fingerprints.

The [dated receipts](../tests/linux-compat/results/2026-10-13/) include
`iovposition-before-*`, `iovposition-after-*`, host/geometry/allocation logs
and the [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovposition-audit.v).
Its negative controls prove assertions execute and passing output is rejected
as a native failure. Clean worktrees pin kernel inputs at `7d01a61b4`; only
the three I/O source files differ. A rebuilt clean V tree pins compiler sources
at `f6358ecff9`. Previous temporary build trees had disappeared, so both
unchanged controls were rebuilt for this comparison.

The broader ARM comparison uses the same cached desktop image and its
extracted 13 MiB desktop binary. All 36 workloads repeat 200 operations and
retain zero bytes on both kernels, including tmpfs and ext2 operations; all
four 300-process churn workloads retain zero memory and slab objects. The
32 MiB cache workload records its expected storage cost. Idle, app startup
and dragging each pass one five-second sample before and after, including
seven measured app/compositor processes. The candidate screenshot was
inspected. The [performance evidence](../tests/linux-compat/results/2026-10-13/iovposition-performance-evidence.json)
and raw `iovposition-perf-*`/`iovposition-desktop-*` logs preserve those runs.
The [V controller](../tests/linux-compat/results/2026-10-13/iovposition-performance.v)
uses the maintained harness while preserving shared cached archives. These
startup and retention checks do not qualify full Linux application lifecycle,
x86 desktop performance or physical hardware.

Flags and character-device positioned I/O, GNU libc wrappers, native ELF32
and translated variants, actual payload transfers at the 2 GiB cap,
disk-backed vector behavior, shared-offset atomicity and allocation exhaustion
remain separate qualification work. The three broad section-15 gates stay open.

## Native vector flags and error precedence

Native preadv2/pwritev2 now check unsupported flags in the consuming helper,
after descriptor/access/seek checks and a complete immutable vector import.
Explicit positive positions also undergo aggregate signed-overflow validation.
Valid empty transfers return zero before flag dispatch, including valid
all-zero arrays; invalid bases on zero-length tails still fail import.
Nonempty unsupported modes check the handle's read/write MAC permission before
returning EOPNOTSUPP. This follows [Linux 6.12's vector import, empty-transfer,
permission and flag order](https://github.com/torvalds/linux/blob/v6.12/fs/read_write.c#L940).
Offsets below -1 continue to fail first, and -1 continues through the existing
current-position path. Public readv/writev wrappers pass flags0 to their
original consuming bodies. The same FD reference and imported-vector owner
cover every return; no new allocation owner is introduced.

The V `iovflags` fixture runs 1,540 checks in each root and UID/GID 1000
child, combining seven descriptor/resource kinds, read/write, explicit/current
position, five raw flag patterns and eleven vector/offset variants. Unknown
bits alone or combined with a recognized bit must preserve earlier EBADF,
ESPIPE, EFAULT and EINVAL errors. Empty 0/1/1024-entry vectors succeed only
after the applicable descriptor and import checks. Nonempty valid requests
return EOPNOTSUPP without changing file contents/cursors, destination bytes
or nonblocking pipe/UNIX stream queues. High-only flag patterns exercise
actual reads/writes and shared-cursor updates, checking the low-32-bit native
flag argument. Negative offsets and high-only controls already pass on both
unchanged kernels; the remaining 1,088 checks per credential group fail there
because an early flag refusal displaces the required result. Both candidates
pass all 3,080 checks per architecture with identical before/after fixture C.

Each credential group warms 32 cycles and measures 200 cycles through empty
0/8/9/1024-entry imports, malformed headers/counts/ranges/positions, unknown
nonempty refusals and flags0 I/O. All slab classes stay flat, with big pages
71/71 on ARM and 186/186 on x86. Independent review of source and final emitted
code confirms synchronous fixture borrows, one descriptor/import per consumer
and vector-before-FD cleanup on permission and flag errors.

Twelve native guest cases pass per architecture: flags, positioned imports,
offsets, ranges, immutable headers, descriptor lifetime, O_PATH access,
openat2, directory errors, zero-byte pipes, runtime and shared memory. Eight
compatibility host test files and mapping-storage geometry checks pass.
Allocation-site audits still fail the same existing allowances at 406 ARM and
295 x86 sites; only diagnostic line numbers move, with no increased allowance.
The generated inventory retains 62 source fingerprints.

The [dated receipts](../tests/linux-compat/results/2026-10-13/) publish
`iovflags-before-*`, `iovflags-after-*`, host/geometry/allocation logs and the
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovflags-audit.v).
Its two negative controls prove assertions execute and passing output cannot
qualify as an unchanged-kernel failure. Private kernel trees pin inputs at
`7e5ad1a49`; only the two vector syscall source files differ. The compiler
still pins clean V sources at `f6358ecff9`.

The broader candidate-only ARM run repeats the maintained retention harness:
all 36 workloads retain zero bytes across 200 operations, and all four
300-process churn workloads retain zero memory/slab objects. The cache
workload records the expected cost of writing 32 MiB. Idle, app startup and
dragging each pass a five-second sample, with seven measured app/compositor
processes and an inspected screenshot. The desktop binary, cached image and
V controller match the preceding positioned-import comparison; those paired
results remain separate runs on separate kernel binaries. The
[performance evidence](../tests/linux-compat/results/2026-10-13/iovflags-performance-evidence.json)
and raw `iovflags-perf-after`/`iovflags-desktop-after` logs preserve this
candidate's runs. These checks cover startup and retention; full Linux
application lifecycle, x86 desktop performance and physical hardware remain
unqualified.

Recognized nonzero RWF modes still return EOPNOTSUPP for nonempty transfers;
this change qualifies unknown-flag behavior and flags0 preservation.
Direct MAC-denial/current-position-overflow checks, character-device
positioned I/O, GNU wrappers and ELF32/translated paths, disk-backed vectors,
deterministic positioned descriptor/header races, shared-offset atomicity and
allocation exhaustion remain separate work. The three broad section-15 gates
stay open.

## Native vector descriptor words

All six native vector syscalls now resolve descriptors through an unsigned
32-bit value, including preadv2/pwritev2's current-position -1 path. The old
lookup kept the complete syscall register and returned EBADF for valid
descriptors with nonzero upper bits. Linux's native vector entry points accept
a word, then call [the unsigned-int fdget/fdget_pos interfaces](https://github.com/torvalds/linux/blob/v6.12/include/linux/file.h#L65).
The change is three casts at the consuming helpers' existing lookups. Vector
counts retain their full native width, and positioned negative-offset checks
continue to precede descriptor lookup.

The V `iovfd` fixture runs 3,080 checks in each root and UID/GID 1000 child.
It combines seven descriptor/resource kinds, read/write, unpositioned/v1/v2
explicit/v2 current-position calls, five upper-word patterns and eleven
vector/offset variants. Raw descriptors have zero, 1, 0x12345678, 0x80000000
or 0xffffffff in the upper word. Valid aliases must preserve actual file and
nonblocking pipe/UNIX stream data and cursor behavior. Invalid/O_PATH and
wrong-access descriptors retain EBADF; positioned streams retain ESPIPE;
header/range/count errors and negative positions retain their earlier errors.
Counts of 2^32+1 must remain invalid, with no transfer from their valid first
entry. Refusals preserve file bytes/cursors, destinations and queued data.

Both unchanged kernels fail 1,144 checks per credential group: the complete
descriptor register displaces valid I/O and import/seek errors with EBADF.
Ordinary descriptors, invalid low descriptors and negative positioned offsets
already pass. Both candidates pass all 6,160 checks per architecture, with
identical before/after fixture C. Each credential group warms 32 cycles and
measures 200 cycles through 0/8/9/1024-entry empty imports, malformed vectors,
negative positions, wide counts and actual I/O. All slab classes stay flat,
with big pages 77/77 on ARM and 210/210 on x86.

Independent review and the auditor compare entire emitted consuming bodies:
only the three descriptor casts differ. All six wrappers, FD/vector reference
and cleanup code remain byte-identical; fixture borrows and alias-safe closes
retain their reviewed lifetimes. Both architectures pass five guest cases:
descriptor words, unknown flags, positioned imports, descriptor-reuse races
and native runtime. Eight host test files and mapping-storage geometry checks
pass. Allocation audits retain the same existing 406 ARM/295 x86 sites and
allowance failures; no allowance is increased. The inventory keeps 62 inputs.

The [dated receipts](../tests/linux-compat/results/2026-10-13/) publish
`iovfd-before-*`, `iovfd-after-*`, host/geometry/allocation logs and the
[assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/iovfd-audit.v).
Both failing controls execute. Private source trees pin `ad4c6f638`; only the
two vector syscall files differ. Baseline binaries, C and allocation logs are
reused from the preceding committed flag qualification and bound to its exact
artifact hashes; the descriptor fixture runs freshly on those binaries.
The clean compiler remains pinned at `f6358ecff9`.

This qualification covers these native vector descriptor words. Scalar and
other FD APIs, GNU wrappers, ELF32/translated variants, deterministic
positioned races, shared-offset atomicity and allocation exhaustion remain
separate work. The three broad section-15 gates stay open.

## Native stream-vector receives

Native readv and preadv2 at offset -1 previously read each nonempty iovec
separately. A two-byte UNIX datagram split across one-byte destinations could
return the first byte of that record and the first byte of the next one,
discarding both tails. A blocking pipe or socket read could receive all
available data in its first destination, then wait for more input for the
second destination while the writer remained open.

Pipe/socket vectors now use one receive of at most 1MiB, then scatter that
piece across the imported destinations. The consuming syscall retains its
single FD and immutable vector owner. The receive helper borrows both, reserves
the allocator's actual slab/page geometry, uses a fallible allocation, and
erases/frees its buffer before releasing its reservation on every post-allocation
return. No new offset lock is held across a blocking stream callback.
Regular files and character devices retain their existing paths.

[Linux v6.12 UNIX receives](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/net/unix/af_unix.c)
copy a selected datagram to the complete iterator and retire that record;
[pipe reads](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/pipe.c)
return received data when the queue empties. The regression covers this
valid-transfer behavior, separately from the destination-fault limits below.

The V `iovstream` fixture checks 220 cases in each root and UID/GID1000 child
on both native architectures. readv and preadv2 at -1 use 2/8/9/513/1024-entry
imports across pipes and UNIX stream/datagram/seqpacket sockets. Checks cover
complete records, truncation, untouched next messages, available-data returns
with the writer open, valid empty vectors, the existing first-destination
precheck and complete 1MiB records. Blocking probes release a stuck baseline
with late input before joining its worker; its borrowed storage remains live.
Unchanged kernels fail 80 checks per cohort: 60 mixed/truncated-record cases,
eight blocking available-data cases and 12 large-record cases. Fixed kernels
pass all 440 checks per architecture.

Two 200-cycle cohorts retain identical live slab objects and big pages:
**212/212 ARM and 725/725 x86**. Stable endpoint pairs and one payload mapping
isolate receive/import storage; each cycle exercises stack/heap imports,
empty/count errors, EAGAIN callback cleanup and full 1MiB record receives.
The first retention stress instead created thousands of endpoint pairs before
their grace periods elapsed. Both diagnostic runs reach `socket 4096 33554432`
with `LastDenied: objects` / `LastDeniedKind: socket`. That failed stress and
the initial candidate aggregate receipts remain published. The corrected
stream-only reruns pass; their complete generated fixture C is identical on
both kernels and architectures, without hidden heap promotions.

Eleven other guest cases pass on both candidates: `iovfd`, `iovflags`,
`iovposition`, `iovoffset`, `iovrange`, `iovimport`, `iovpin`, `pathio`,
`readerror`, `pipezero` and `runtime`. Their success rows remain in the initial
aggregate receipts alongside its failed old stream-retention case; that
aggregate has not been relabeled as passing. The `iovimport` checkpoint now
counts active vector/receive reservations to prove that import completed,
and passes on both unchanged kernels too. Eight host tests, mapping geometry
checks and both kernel builds pass. The existing allocation allowance failures
remain **406 ARM / 295 x86**, with identical `NEW:` rows and no allowance increase.

Fresh AArch64 `ops,churn,cache` comparisons use the same cached archive,
extracted desktop and V controller. All 36 200-operation rows retain zero
bytes before/after. All four 300-process candidate churn rows remain flat.
Baseline curl retains one 16KiB size-32 slab page with **zero additional live
objects**; the other three baseline rows remain flat. This capacity difference
is preserved in the receipts and does not establish a performance improvement.
The 32MiB cache workload reports 20MiB used growth and 16MiB cached. Candidate
idle/apps/drag pass their five-second samples; the seven-process app screenshot
was inspected. These checks do not qualify x86 desktop performance or Linux
application installation/lifecycle.

The [ARM evidence](../tests/linux-compat/results/2026-10-13/iovstream-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/iovstream-x86_64-evidence.json),
[performance evidence](../tests/linux-compat/results/2026-10-13/iovstream-performance-evidence.json)
and [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/iovstream-audit.v)
bind raw logs, frozen source/init/image hashes, kernel binaries, generated C,
the clean `f6358ecff9` compiler and both executed failing controls. Private
trees pin `bced1c4ec`; only `linux_common.v` differs. The tested copy also
retains two concurrent erase-before-free additions in existing writev/sendfile;
those independently owned hunks are excluded from this fix's commit.
Its existing writev C is otherwise identical, and all six syscall wrappers
remain identical. Qualification fingerprints identify these isolated inputs,
separately from concurrent shared-checkout changes. The initial bare fixture
compile failure (`v_fixed_index`) is retained; it was corrected before runtime
qualification. Independent review found no new lifetime blocker.

At this revision, the first inaccessible destination retained Vinix's
queue-preserving precheck, a known divergence from Linux datagram behavior.
The following record-fault qualification closes that native UNIX vector
divergence. Later byte-stream destination faults, within-iovec copied-prefix
reporting and queue rollback still require further work.
GNU wrappers, foreign/translated ABIs, Internet/netlink/character-device paths,
shared regular-file offset atomicity and allocator exhaustion remain unqualified.
The three broad section-15 gates remain open.

## Native UNIX record-vector copy faults

A native readv or current-position preadv2 on a UNIX datagram/seqpacket socket
previously checked its first destination before receiving. An inaccessible
destination left the selected packet queued, even when Linux would consume it.
A fault in a later iovec returned the number of previously copied bytes,
instead of EFAULT; an empty queue or zero-length record could also lose its
correct EAGAIN or zero result to the premature destination check.

The vector receive now borrows a record-boundary query from the pinned
resource. Only UNIX datagram/seqpacket endpoints opt in. It selects one record
before copying, retires it on a copy fault, and reports EFAULT even after a
committed prefix. Empty queues return EAGAIN before destination access; an
empty selected record returns zero without probing payload memory. Complete
header/range/length imports, valid empty vectors and flag refusals still precede
the receive. Short packets do not access unused later destinations.

[Linux v6.12 UNIX receives](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/net/unix/af_unix.c)
select one packet, copy it through the complete iterator, then free the
selected packet and return the copy error. The V fixture exercises this
ordering, queue disposition and copied bytes, beyond the syscall result.

`iovpacket` runs 350 probes in each root and UID/GID1000 child on both native
architectures. readv and preadv2 at -1 use 2/8/9/513/1024-entry immutable
headers. Cases include unmapped, PROT_NONE, read-only, later-entry and
page-crossing destinations; copied prefixes; empty queues/records; valid and
malformed empty vectors; invalid count/header/length/flags; and short records
with inaccessible later destinations. Fresh unchanged kernels fail **140
checks per cohort**. Candidates pass all **700 checks per architecture**.

Two 200-cycle storage cohorts reuse two endpoint pairs and one two-page
mapping, after 32 warm-up cycles. Each cycle makes 210 transfers through
8/9/1024-entry imports and all applicable error/empty/valid paths. All live
slab classes stay flat, with big pages **81/81 ARM and 218/218 x86**. The
fixture borrows its mapping/endpoints synchronously, bounds header scratch to
16KiB per transfer, resets page protections before reuse, and closes/unmaps
only initialized owners on exit. It has no hidden heap promotion in emitted C.

The record query emits an alloca-backed interface whose object pointer is
the existing resource box. It dispatches immediately and returns a scalar;
there is no heap box, escaped scratch pointer, new lock or reference owner.
Independent review confirms this on both architectures. The receive buffer
still erases/frees before charge release, with FD/vector cleanup left to the
consuming caller. Whole generated consuming bodies and six syscall wrappers
are otherwise identical to the baseline.

Seven additional guest cases pass on both candidates: `iovstream`, `iovrange`,
`iovimport`, `iovpin`, `iovflags`, `iovfd` and `runtime`. The stream fixture now
expects record consumption for its first PROT_NONE control while retaining
byte-stream queue preservation and empty-vector controls. Eight host test
files, mapping geometry, both fresh kernel builds and inventory checks pass.
Fresh before/after allocation audits retain **406 ARM / 295 x86** sites and
identical existing allowance failures; no allowance is increased. The source
inventory now fingerprints 63 inputs, including UNIX endpoint behavior.

Host disk exhaustion stopped the first aggregate after five successful ARM
rows and four successful x86 rows. Its failed logs and partial receipts remain
published. Fresh completion suites run the remaining three ARM/four x86 cases
on the identical candidate kernels; the interrupted aggregate is not relabeled
as passing.

[ARM evidence](../tests/linux-compat/results/2026-10-13/iovpacket-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/iovpacket-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/iovpacket-audit.v)
bind raw baseline/candidate logs, frozen fixtures/inits/images, kernel binaries,
generated C, host/geometry/allocation checks and both executed failing controls.
The committed fixture removes trailing blank lines; its freshly emitted C
matches every frozen tested capture, whose original source hashes are retained.
Both baseline kernels are freshly built in private worktrees at `b463fe892`;
only `resource.v` and `linux_common.v` differ in the candidate kernel sources.
The compiler remains the clean `f6358ecff9` snapshot. These isolated semantic
inputs are recorded separately from the public dispatch inventory, which
follows the committed parent plus this fix. Earlier broader performance and
desktop receipts belong to the preceding stream fix and are not reported as
new runs on this kernel.

This qualification covers native UNIX record vector receives. Scalar reads
and recvmsg, Internet/netlink records, later byte-stream faults and queue
rollback, GNU wrappers, ELF32/translated paths, allocator exhaustion, shared
regular-file offsets and complete Linux application installation/compatibility
remain separate work. The three broad section-15 gates remain open.

## Native O_PATH seek access

O_PATH handles retained pathname access but lseek previously accepted them
on files, directories and unfollowed symlinks, or returned ESPIPE for FIFOs
and devices. Invalid offsets/whence could mask the required EBADF error.
The seek syscall now refuses O_PATH immediately after its pinned descriptor
lookup, before policy, handle locking, type checks or cursor calculations.
Its existing defer releases the reference once; no new allocation or lock
owner is introduced. Scalar read/write already reject O_PATH through the
access-mode mask, which includes the pathname bit, and remain unchanged.

[Linux v6.12 descriptor lookup](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/file.c)
filters pathname handles from ordinary fdget operations; its
[lseek path](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/read_write.c)
uses that lookup before examining whence or invoking filesystem seek.
The regression checks exact error precedence and retained descriptor behavior.

The V `opathseek` fixture checks 3,024 raw native seeks in each root and
UID/GID1000 child on both architectures. Six node types cover readable and
private files, a directory, FIFO, unfollowed symlink and character device.
Four requested flag variants exercise ignored write/truncate/append/nonblock
bits; original, dup and F_DUPFD_CLOEXEC descriptors cover shared handles and
descriptor flags. Six signed 64-bit offsets include a position above 4GiB,
-1 and INT64_MIN; seven whence values include ordinary, data/hole, large
invalid and negative selectors. Fresh baseline kernels fail every refusal,
while fixed kernels pass all **6,048 checks per architecture**.

Metadata retains inode, device, size and type before/after each alias cohort.
Readable file bytes remain ABCD despite requested O_TRUNC, and ordinary users
still receive EACCES when opening the root-owned private file for reading.
Ordinary file controls preserve sparse positions above 4GiB/across 8GiB,
relative/end seeks and negative/invalid seek errors with unchanged cursors.
An invalid descriptor still returns EBADF before malformed arguments.

Two 200-cycle retention cohorts keep twelve pathname descriptors live, after
32 warm-up cycles. Each cycle makes 504 refused seeks plus six temporary
dup/seek/close controls. Every slab live count stays flat, with big pages
**63/63 ARM and 160/160 x86** in both credential groups. Opened-count cleanup
closes only initialized owners; stat values and observation buffers stay on
the stack, with two bounded alloca-backed slab snapshots. Complete fixture C
matches both baseline/candidate captures, without hidden heap promotion.

Independent lifetime review confirms the new emitted error branch unrefs its
FD once, returns before MAC/lock acquisition and never dereferences the handle
after release. Removing only the guard and canonicalizing generated return
temporary names leaves the complete seek body identical to baseline. Scalar
read/write/close, positioned I/O and vector consuming bodies remain identical.
Four other guest cases pass on both architectures: pathio, readerror, pipezero
and runtime. Eight host test files, both fresh kernel builds and inventory
checks pass. Fresh allocation audits retain **406 ARM / 295 x86** existing
sites and identical allowance failures; no allowance is increased. The source
inventory fingerprints the same 63 inputs, including the modified seek code.

The first fixture C compilation was rejected on both architectures for a
printf long-long/long format mismatch. It was corrected before runtime tests;
the rejection logs and receipts remain published. The first x86 candidate
aggregate later failed when host disk exhaustion interrupted the runtime
image build, after four passing guest cases. Its failed runtime row has no
image hash and remains failed. A fresh runtime-only completion run passes on
the identical candidate kernel with identical frozen fixture C.

[ARM evidence](../tests/linux-compat/results/2026-10-13/opathseek-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/opathseek-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/opathseek-audit.v)
bind source/init/image hashes, raw logs, kernel binaries/C, allocation and host
checks, compilation rejections, the x86 completion and both executed failing
audit controls. Private kernel trees pin `116ba2c785`; only `fs/vfs.v` changes.
The compiler is the clean `f6358ecff9` snapshot. Semantic receipts identify
those isolated inputs separately from the public dispatch inventory, which
follows the committed parent plus this guard.

Upper-word descriptor/whence decoding, GNU wrappers, foreign/ELF32 paths,
ordinary SEEK_DATA/SEEK_HOLE, shared-position concurrency, disk-backed handles,
allocation exhaustion and complete application installation/sandbox/portal
support remain separate work. The three broad section-15 gates stay open.

## Native scalar syscall argument words

Native read/write/close/lseek dispatched machine-word descriptors directly to
V's 64-bit `int` consumers. pread64/pwrite64 likewise forwarded the complete
descriptor word, and lseek retained the entire whence word. Nonzero unused
upper bits consequently rejected otherwise valid descriptors or selectors.
Four direct adapters now decode lower-32-bit FD/whence arguments; positioned
wrappers apply the same FD cast. Counts remain unsigned 64-bit and offsets
signed 64-bit. The existing consumers retain all descriptor references,
access checks, locks, buffers and cleanup responsibilities.

[Linux v6.12 read/write/seek declarations](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/read_write.c)
use unsigned-int descriptors and whence, full-width size_t counts and signed
offsets; [close](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/open.c)
also takes an unsigned-int descriptor. The regression checks argument widths
and observable results independently of libc's usual argument preparation.

The V `scalarabi` fixture makes 2,795 raw syscall checks in each root and
UID/GID1000 child on both architectures. Five upper-word patterns include
zero, a single high bit, mixed high bits, the sign bit and all high bits.
Seven descriptor classes cover read/write files, invalid and O_PATH handles,
wrong access modes, both pipe directions and UNIX streams. Fresh unchanged
kernels fail **1,528 checks per cohort**; candidates pass all **5,590 checks
per architecture**.

Actual bytes, saved cursors and pipe/socket queue contents are checked after
success and refusal. Zero counts, unmapped destinations/sources, negative
positioned offsets, invalid descriptors and access/ESPIPE errors remain real
controls. lseek tests SET/CUR/END with signed offsets, invalid regular-file
selectors and preserved cursors. Successful close retires the original FD
while its separately retained duplicate remains usable for metadata and final
cleanup. Sparse reads/writes above 4GiB and across 8GiB verify the true position,
unchanged lower-32-bit aliases, size and ordinary cursor. Two 4GiB-count
refusal paths detect accidental count truncation without huge transfers.

Two 200-cycle retention cohorts perform 70 probes per cycle after 32 warm-ups.
Transient descriptor owners are closed on every path; regular inodes are
reused and socket churn is excluded from the storage workload. Every live
slab class stays flat, with big pages **335/335 ARM and 4,308/4,308 x86** in
both credential groups. All four before/after fixture C captures match the
preview byte for byte, without malloc, memdup, array allocation or fixed-array
bounds helpers. The observer uses two bounded stack snapshots and retires its
procfs descriptor on success and failure.

Independent source/C/retention review finds no lifetime blocker. Each new
adapter emits exactly one direct call and return. Reversing those four
adapters and native dispatch entries plus the two positioned FD casts restores
the **entire baseline generated kernel C** on each architecture. No existing
consuming body, reference or lock owner changes.

Four additional guest cases pass on both candidates: opathseek, iovfd, pathio
and runtime. Eight host test files, both fresh kernel builds and inventory
checks pass. Fresh before/after allocation audits retain **406 ARM / 295 x86**
existing sites and identical allowance failures; no allowance is increased.
Host disk exhaustion initially prevented command launch before any new guest
receipt existed. Only this session's rebuildable older images/objects were
retired; older generated C was losslessly archived with byte/hash verification.
The actual baseline and candidate suites then ran to completion.

[ARM evidence](../tests/linux-compat/results/2026-10-13/scalarabi-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/scalarabi-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/scalarabi-audit.v)
bind raw logs, source/init/image hashes, kernel binaries/C, host/allocation
checks and both executed failing controls. Private worktrees pin `53e909df86`;
only three syscall table files differ. The compiler is the clean `f6358ecff9`
snapshot. All 63 isolated semantic source inputs are fingerprinted separately
from the public dispatch inventory, which follows the committed parent plus
this fix. Earlier broader performance/desktop receipts are not new runs on
this kernel.

Other FD APIs, GNU wrappers, foreign/ELF32 paths, regular copy-fault cursor
behavior, actual cap-sized transfers, ordinary SEEK_DATA/SEEK_HOLE, invalid
selector precedence on streams, shared-offset concurrency, disk-backed paths,
allocation exhaustion and complete Linux installation/sandbox/portal/runtime
support remain separate work. The three broad section-15 gates stay open.

## Native seek selector error precedence

Valid pipe/socket/device descriptors previously returned ESPIPE before
examining lseek's selector. The syscall now rejects selectors outside 0..4
immediately after descriptor/O_PATH checks, before policy, locking and
resource-type dispatch. Invalid and pathname-only descriptors retain EBADF.
[Linux v6.12 lseek](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/read_write.c)
checks the descriptor, validates whence against SEEK_MAX, then invokes the
resource's seek behavior. Valid stream selectors still return ESPIPE.

The V `seekerror` fixture makes 3,888 raw checks in each root and UID/GID1000
child. Twelve classes cover regular files, directories, both anonymous pipe
ends, a named FIFO, UNIX stream/datagram/seqpacket, /dev/null, an invalid FD
and O_PATH file/FIFO handles. Original, dup and F_DUPFD_CLOEXEC aliases combine
three upper FD patterns, three upper-selector patterns, four signed64 offsets
and three invalid low selectors. Fresh unchanged kernels fail **2,268 checks
per cohort**; candidates pass all **7,776 checks per architecture**.

Both baseline and candidate retain metadata inode/device/size/type and alias
flags. Ordinary relative/end/sparse file seeks and directory cursor queries
remain valid; all five recognized selectors on streams still refuse with
ESPIPE. Real queued AB bytes survive every malformed seek: FIONREAD and poll
report readable data, a read returns AB, the emptied endpoint returns EAGAIN,
then the same endpoints are replenished. Valid character-device seek behavior
and regular DATA/HOLE semantics are outside this qualification.

Two 200-cycle storage cohorts retain sixteen stable descriptors, after 32
warm-up cycles. Each cycle makes 1,296 invalid seeks plus valid controls and
three transient dup/seek/close operations. Every slab live count stays flat,
with big pages **84/84 ARM and 223/223 x86** in both credential groups. The
fixture initializes owners before setup, closes partial and duplicated owners
on failure, and keeps borrowed handles alive through synchronous controls.
Its handle table and two observer snapshots use bounded alloca. All four
actual fixture C captures match preview without hidden heap promotion.

Independent source/C/retention review finds no lifetime blocker. Generated
early EINVAL releases exactly the pinned FD and returns before MAC/lock checks;
later paths keep their lock-release-before-FD-unref order. Removing the new
guard and canonicalizing generated return temporaries restores the entire
seek body. Replacing only that body restores the complete baseline kernel C.

Four additional cases pass on both candidates: scalarabi, opathseek, pathio
and runtime. Eight host test files, both fresh kernel builds and inventory
checks pass. Before/after allocation audits retain **406 ARM / 295 x86**
existing sites and identical allowance failures; no allowance is increased.

Host disk exhaustion interrupted both original candidate aggregates. ARM's
runtime image exists, but its EFI-vars copy failed before boot, after four
successful cases. The x86 capture is truncated during opathseek, with only
two successful receipt rows. Both unsuccessful aggregates remain published.
Fresh completion suites pass ARM runtime and x86 opathseek/pathio/runtime on
the identical kernels and identical frozen fixture C. These completion results
do not relabel the original aggregates as passing.

[ARM evidence](../tests/linux-compat/results/2026-10-13/seekerror-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/seekerror-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/seekerror-audit.v)
bind raw logs, source/init/image hashes, kernel binaries/C, host/allocation
checks and both executed failing controls. Private trees pin `6e27e8ee3`;
only the two-line guard in `fs/vfs.v` changes. The compiler remains the clean
`f6358ecff9` snapshot. All 63 isolated semantic inputs are fingerprinted
separately from the public committed-parent dispatch inventory.

Regular SEEK_DATA/SEEK_HOLE, valid character-device seek behavior, relative/end
overflow, shared-offset races, GNU wrappers, foreign/ELF32 paths, disk-backed
files, allocation exhaustion and complete Linux installation/sandbox/portal/
runtime support remain separate work. The three broad section-15 gates stay open.

## Generic native data and hole seeks

Regular files previously rejected SEEK_DATA and SEEK_HOLE with EINVAL.
They now use conservative Linux reporting: an in-file offset is data and
the final hole is EOF. Negative positions, empty files and positions at or
beyond EOF return ENXIO without moving the cursor. Invalid/O_PATH descriptors
and unseekable pipes/sockets retain their existing EBADF/ESPIPE ordering.
Directories and other nonregular resources do not acquire generic extents.

[Linux v6.12 generic seek](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/read_write.c)
uses this model, and the [Linux lseek contract](https://raw.githubusercontent.com/mkerrisk/man-pages/master/man2/lseek.2)
permits filesystems to conservatively report zero regions as data. These
results do not claim discovery of physically unallocated extents.

The V `seekextent` fixture checks 9,000 raw/musl calls in each root and
UID/GID1000 child. Five sizes cover empty, four-byte, page-crossing and sparse
files above 4GiB/across 8GiB. Three access modes and original/dup/
F_DUPFD_CLOEXEC aliases combine ten signed64 positions, two selectors, three
upper FD patterns and three upper-selector patterns. Libc calls exercise the
same boundaries. Fresh baseline kernels fail every check; candidates pass
all **18,000 checks per architecture**.

Every probe resets its shared open description and verifies both alias and
original cursors after success or refusal. Metadata inode/device/type/size/
blocks and descriptor flags remain unchanged. Real A/zero/Z bytes at the
beginning/middle/end and untouched EOF buffers retain file contents. Invalid,
pathname and pipe/socket error controls pass both baseline and candidate.

Two 200-cycle storage cohorts keep forty-five descriptors live, after 32
warm-ups. Each cycle makes 900 raw/libc seeks plus three transient alias probes
and metadata/byte controls. Every slab class remains flat, with big pages
**451/451 ARM and 6,308/6,308 x86** in both credential groups. A bounded
backup-style DATA/HOLE walker copies empty, small and page-crossing files,
including zero regions, then compares every byte and the destination size.

The first candidate aggregates remain failed. Their syscall and storage
checks pass in both cohorts and root copies pass, but the ordinary-user copy
attempted creation directly beneath the minimal image's root-owned 0755 /tmp.
The final fixture creates and chmods its own writable copy directory. Fresh
baseline and candidate runs bind that corrected source/C; both credential
copy cohorts then pass on the identical candidate kernels. All checking,
ownership, observer and copy routines otherwise remain byte-identical in
generated C after canonicalizing source-position-derived unused loop-counter
names, except the two target path strings. Original failures remain
published alongside final results.

The original x86 aggregate additionally failed to open its final receipt for
writing after a logged runtime PASS, leaving four recorded rows. A fresh
runtime-only completion receipt passes on the identical kernel with identical
generated fixture C. The original partial receipt remains unchanged.
Its first completion attempt failed before init/image creation when host disk
exhaustion stopped serial-helper C generation; that failure is also preserved.

Independent lifetime review verifies each new error path releases the handle
lock before its one FD unref. Success changes only the scalar cursor under
the existing lock. No allocation, reference or lock owner is added. Removing
the extent branch, equivalent selector constants and generated return-name
changes restores the complete seek body. Replacing that body and removing
two new constants restores the entire baseline generated kernel C. The
fixture uses bounded Handles/Slabs/copy buffers and initialized-owner cleanup;
all final before/after fixture C captures match its final preview.

Four additional cases pass on both candidates: seekerror, opathseek, scalarabi
and runtime. Eight host test files, fresh kernel builds and inventory checks
pass. Existing allocation allowance failures retain **406 ARM / 295 x86**
sites and identical NEW rows; no allowance is increased.

[ARM evidence](../tests/linux-compat/results/2026-10-13/seekextent-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/seekextent-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/seekextent-audit.v)
bind raw original/final logs, source/init/image hashes, kernel binaries/C,
host/allocation checks and both executed failing controls. Private worktrees
pin `001a3b9967`; only `fs/vfs.v` differs. The compiler is the clean
`f6358ecff9` snapshot. All 63 isolated semantic inputs are fingerprinted
separately from the public committed-parent dispatch inventory.

Physical extent discovery, concurrent truncation/shared-offset races,
disk-backed qualification, GNU wrappers, foreign/ELF32 paths, allocation
exhaustion and complete Linux installation/sandbox/portal/runtime support
remain separate work. The three broad section-15 gates stay open.

## Native ftruncate descriptor eligibility

O_PATH descriptors previously reached file growth, including handles to
private files, unfollowed links and FIFOs. Character-device grow stubs could
return success, while directories returned EISDIR. The eligibility check now
rejects O_PATH with EBADF, and nonregular, readonly or access-mode3 handles
with EINVAL before MAC or growth. Negative lengths still return EINVAL before
descriptor lookup. Writable regular-file policy, protected-attribute checks
and growth retain their existing behavior. This ordering follows
[Linux v6.12 ftruncate](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/open.c).
Pathname truncate has its own directory error contract.

The V `truncateaccess` fixture checks 928 raw/musl calls in each root and
UID/GID1000 child, passing **1,856 checks per architecture**. Twenty classes
cover regular readonly/writeonly/readwrite/mode3 handles, public/private
O_PATH files, directories, pipe ends, UNIX streams, null/zero/full devices,
invalid descriptors, unfollowed links and named FIFOs. Original/dup/
F_DUPFD_CLOEXEC aliases combine eight signed64 lengths: zero, small shrink/
unchanged/grow sizes, -1 and INT64_MIN.

Each probe observes the syscall result before restoration, then checks
inode/device/type/UID/GID/size, descriptor flags, original and shared cursors,
file prefixes and zero-filled growth. FIONREAD/poll preserve two queued AB
bytes on pipe/socket/FIFO; final controls drain and compare those real bytes.
Private files remain inaccessible through a new ordinary readonly open. Two
pre-opened readwrite observers are inherited solely to inspect and restore
the normal/private fixtures. Incorrect baseline nonregular O_PATH resizes
are observed before metadata restoration; correct candidates never need
that restoration path.

Unchanged kernels fail **504 ordinary / 432 root checks on ARM**, and **432
in each x86 cohort**. The additional 72 ARM ordinary failures are thirty-six
pipe and thirty-six socket EACCES results from MAC running before type
validation. Every eligible ordinary regular-file resize already passes the
baseline. The auditor checks those exact groups and failure counts; all final
candidate cohorts have zero failures.

Sixty cohort descriptors remain live through 32 warm-ups and 200 measured
cycles. Each cycle performs eighty probes plus three temporary dup/truncate/
close controls. Both credential groups retain every slab live-object count,
with big pages **75/75 ARM and 198/198 x86**. Observer and Handles/Slabs
buffers are bounded stack allocations; no hidden fixture promotion or heap
allocation appears in the generated C.

Initial guest attempts were rejected by strict C compilation: two helpers
needed explicit unsafe fixed-array membership, and conditional pathname
pointers needed explicit char casts. Their original logs/source/C/failed
receipts remain preserved with blank init/image hashes. Fresh baseline and
candidate runs bind the corrected fixture; all four actual generated C
captures equal the final preview exactly.

Independent final lifetime review confirms the Resource pointer remains
borrowed from the pinned handle. Every new refusal releases that FD exactly
once, with no new allocation or lock. Negative-length/lookup prefix and
protected/grow cleanup tail retain their generated bodies; replacing only
the ftruncate body restores the entire baseline kernel C.

Four additional cases pass on both candidates: pathio, sharedmem, seekextent
and runtime. Eight host test files, fresh kernel builds and dispatch inventory
checks pass. Existing allocation allowance failures retain **406 ARM / 295
x86** sites and identical NEW rows; no allowance is increased.

[ARM evidence](../tests/linux-compat/results/2026-10-13/truncateaccess-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/truncateaccess-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/truncateaccess-audit.v)
bind original rejected and final logs, source/init/image hashes, kernel
binaries/C, host/allocation checks and both executed failing controls. Private
worktrees pin `538d93af808`; only `file/file.v` differs. The compiler is the
clean `f6358ecff9` snapshot. All 63 isolated semantic inputs are fingerprinted
separately from the public committed-parent dispatch inventory.

Upper descriptor words, GNU/foreign/ELF32 paths, protected attributes and
privilege-bit clearing, readonly mounts, disk-backed qualification,
concurrent close/truncate, huge growth/allocation exhaustion and complete
Linux installation/sandbox/portal/runtime support remain separate work. The
three broad section-15 gates stay open.

## Native ftruncate descriptor words

Both native syscall tables previously dispatched ftruncate directly to a
handler that treated the complete register word as the descriptor. Valid
lower-32-bit descriptors with nonzero upper bits therefore returned EBADF.
One common native adapter now casts only the descriptor to u32 and preserves
the signed64 length before invoking the existing handler. ARM slot46 and
x86 slot77 use that adapter. Linux defines ftruncate's descriptor as an
unsigned int in [its native syscall declaration](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/open.c).

The V `truncateabi` fixture checks 2,784 calls in each root and UID/GID1000
child, passing **5,568 checks per architecture**. Five raw upper-word patterns
(zero, bit32, all upper bits, the sign bit and DEADBEEF) plus one musl call
combine twenty descriptor classes, original/dup/F_DUPFD_CLOEXEC aliases and
eight signed64 lengths. Valid writeonly/readwrite files actually resize;
readonly/mode3/nonregular/O_PATH/invalid handles retain their real errors.
Negative -1/INT64_MIN still return EINVAL before descriptor validation.

Fresh baseline kernels fail **864 checks in every cohort**, including 144
valid resizes. Every failure is a high-word raw call receiving incorrect
EBADF; zero-word, libc and negative-length controls pass. Candidates have
zero failures. The auditor requires those exact baseline counts and refuses
to accept a passing guest log as a baseline failure.

The fixture checks inode/device/type/UID/GID/size, descriptor flags, real
shrink/grow prefixes and zero-filled tails, both shared cursors, private-open
permissions and FIONREAD/poll on actual queued pipe/socket/FIFO AB bytes.
Final controls drain and compare those bytes. Sixty stable cohort descriptors
plus temporary aliases run 32 warm-ups and 200 measured cycles of eighty
high-word probes plus three duplicate controls. Every slab live-object count
stays flat in both credential groups, with big pages **75/75 ARM and 198/198
x86**.

The first ARM candidate build failed when host disk exhaustion stopped a
dependency-file write. Its failed build log remains published alongside the
successful retry. Only audited rebuildable images/build objects from earlier
owned work areas were retired; kernel binaries, generated C, fixture sources,
init files, logs and receipts remain preserved. The retried build uses the
same implementation and compiler. Both actual before/after fixture C
captures equal the preview without hidden allocation or promotion.

Independent final lifetime review confirms this adapter adds no allocation,
reference or lock. The ftruncate eligibility, pin/cleanup and grow body remain
byte-identical in generated C. Removing the single adapter prototype/body and
restoring one native dispatch assignment restores each entire baseline
kernel C. The length reaches the callee unchanged as i64.

Both candidates additionally pass truncateaccess, scalarabi, pathio and
runtime. Eight host test files, fresh kernel builds and inventory checks
pass. Existing allocation allowance failures retain **406 ARM / 295 x86**
sites and identical NEW rows; no allowance is increased.

[ARM evidence](../tests/linux-compat/results/2026-10-13/truncateabi-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/truncateabi-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/truncateabi-audit.v)
bind original before/after logs, source/init/image hashes, kernel binaries/C,
host/allocation checks, the ARM build failure/retry and both executed failing
controls. Private worktrees pin `7c502af1b`; only three syscall table files
differ. The compiler is the clean `f6358ecff9` snapshot. All 63 isolated
semantic inputs are fingerprinted separately from the public committed-parent
dispatch inventory.

Other FD APIs, huge growth, protected attributes/privilege-bit clearing,
readonly mounts/disk, concurrent close/truncate, allocation exhaustion,
GNU/foreign/ELF32 paths and complete Linux installation/sandbox/portal/runtime
support remain separate work. The three broad section-15 gates stay open.

## Native pathname truncate type errors

Pathname truncate previously allowed nonregular nodes to reach their growth
hooks. Device stubs could return success; FIFO/socket hooks could return an
unrelated prior errno. The handler now checks the resolved inode type before
write policy, attributes, overlay copy-up or growth: directories return
EISDIR, other nonregular types EINVAL. Negative lengths still return EINVAL
before copying or resolving the path. Regular-file policy and growth remain
unchanged. This ordering follows
[Linux v6.12 vfs_truncate](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/open.c).

The V `truncatepath` fixture checks 384 raw/musl calls in each root and
UID/GID1000 child, passing **768 checks per architecture**. Twenty-four classes
cover public/private regular files, directories and FIFOs; null/zero/full
devices and UNIX datagram socket paths; relative/absolute symlink targets;
missing/empty paths, a symlink loop and an inaccessible pointer. Eight signed64
lengths cover zero, small shrink/unchanged/grow sizes, -1 and INT64_MIN.
Private regular paths still require EACCES from ordinary users.

Each call observes the actual result and inode/device/type/UID/GID/size/blocks
before restoring repeatability after an incorrect baseline mutation. Actual
regular-file bytes preserve ABCD prefixes and zero-filled tails. Existing
normal/private aliases retain shared cursors and FD flags. Public/private
FIFO and UNIX datagram FIONREAD/poll retain two AB bytes; both children drain,
compare and replenish those real queues before releasing their inherited
descriptor references. New private opens remain refused despite the inherited
observer authority used to inspect and restore the fixtures.

Initial unseeded baselines fail **121 ordinary / 96 root checks** on each
architecture. Some FIFO errors accidentally match EINVAL because their hooks
reuse an earlier kernel error. The final probe first verifies an ENOENT open
failure, then clears libc errno before the tested call. An unexpectedly
successful seed descriptor is closed. This is the sole fixture source change;
all other generated functions remain identical after normalizing compiler
return and unused-loop names. Original source/C/logs/failed receipts remain
preserved alongside fresh seeded baseline and candidate runs.

The seeded baselines fail **144 checks in every cohort**: 72 device false
successes, 72 root or 48 ordinary stale-ENOENT FIFO/socket refusals, and 24
ordinary private-FIFO EACCES results instead of type errors. Negative, lookup,
directory and eligible regular-file controls pass. All final candidate
cohorts have zero failures.

Ten inherited descriptors survive 32 warm-ups and 200 measured cycles of
eighty-eight raw probes plus three temporary dup/metadata/close controls.
Every slab live-object class remains flat, with big pages **75/75 ARM and
198/198 x86** in both credential groups. Loop and inaccessible-pointer outcome
checks stay outside this repeated loop. Book/Slabs/socket-address storage is
bounded alloca; repeated probe buffers remain on the stack, with no hidden
fixture heap allocation or promotion.

Both first candidate builds failed on host disk exhaustion while writing
dependency files. Their logs and unchanged-source successful retries remain
published. Only audited rebuildable images/objects from owned work areas were
retired; older C captures were losslessly gzip-archived with round-trip/hash
verification and a V restoration helper. Current kernel/C/source/init/logs/
receipts remain retained.

The initial candidate aggregates stopped during the CLI continuation after
four recorded ARM and three x86 successes. Fresh completions qualify only
the missing cases on identical kernel binaries, with matching fixture C.
The first ARM runtime completion failed during image staging on host disk
exhaustion; its failed receipt retains a real init hash and blank image hash.
That log/receipt is preserved separately from the successful fresh completion.

Independent final lifetime review verifies each new error frees the existing
path exactly once. The mode snapshot is scalar from the borrowed node; no
owner, allocation or lock is added. The negative/copy/lookup prefix and
policy/attributes/access/copy-up/grow tail retain their generated bodies,
apart from moving the directory check. Replacing that function body restores
the entire baseline kernel C. All four actual final fixture C captures equal
the final preview; inherited owners and seed/permission/dup/observer cleanup
are complete. The successful parent intentionally keeps ten stable descriptors
while paused until guest teardown.

Both candidates additionally pass truncateabi, seekextent, sharedmem and
runtime across their initial and completion receipts. Eight host test files,
fresh kernel builds and inventory checks pass. Existing allocation allowance
failures retain **406 ARM / 295 x86** sites and identical NEW rows; no allowance
is increased.

[ARM evidence](../tests/linux-compat/results/2026-10-13/truncatepath-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/truncatepath-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/truncatepath-audit.v)
bind original/final/partial/completion logs, source/init/image hashes, kernel
binaries/C, host/allocation checks and both executed failing controls. Private
worktrees pin `dd2c181c1`; only `fs/vfs.v` differs. The compiler is the clean
`f6358ecff9` snapshot. All 63 isolated semantic inputs are fingerprinted
separately from the public committed-parent dispatch inventory.

Disk/readonly mounts/overlays, timestamps, privilege-bit clearing/protected
attributes and restrictive policy combinations, huge sparse growth and
concurrent truncation, allocation exhaustion, GNU/foreign/ELF32 paths and
complete Linux installation/sandbox/portal/runtime support remain separate
work. The three broad section-15 gates stay open.

## Native readlink size words

Native readlinkat previously accepted zero sizes and used the full unsigned
register word for copying. The shared Linux adapter now consumes the low
signed32 size. Nonpositive sizes return EINVAL before pathname copying,
directory-FD lookup, permissions or destination access; positive sizes ignore
the upper register bits. Both native readlinkat dispatches and x86 readlink
use that adapter. This follows
[Linux v6.12 do_readlinkat and syscall declarations](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/stat.c).
The filesystem callee and its allocation/ownership paths remain unchanged.

The V `readlinkabi` fixture passes **4,320 checks on AArch64 and 5,760 on
x86-64** in root and UID/GID1000 children. Sixteen classes cover ordinary and
dangling links, directory-relative and absolute paths with ignored invalid
FDs, invalid/non-directory relative FDs, private search permissions, regular
files/directories, missing/empty paths, null/inaccessible pathname pointers,
a symlink loop and procfs self/exe links. Fifteen size words cover zero,
short/exact/oversized positive copies, INT_MAX, negative low words and several
upper-word patterns. Three destinations are a 64-byte canary array, null and
an inaccessible pointer. AArch64 tests raw readlinkat plus both musl wrappers;
x86 also tests raw readlink.

Copies must return the exact prefix length and bytes, without a NUL or changes
beyond that prefix. Native invalid sizes precede real ENOENT/EFAULT/EACCES/
EBADF/ENOTDIR/ELOOP and nonlink EINVAL controls. Musl's exact zero is distinct:
its wrappers substitute a one-byte scratch buffer, perform lookup, and convert
a positive result to zero. The caller's buffer remains untouched, and real
path errors remain errors. A nonzero size word whose low32 bits are zero still
reaches the native EINVAL check. Captured staged musl source hashes are pinned
in the evidence alongside the guest builder's `/sbin/init` staging contract.

Initial fixture expectations incorrectly treated libc zero as a raw syscall
and assumed `/init` for procfs exe. Those failures, their sources/C and receipts
remain preserved. The intermediate version fixes musl zero; the final version
also fixes the executable target. Only the probe changes. All other generated
functions remain identical after normalizing compiler return/unused-loop names.

| Fixture expectations | ARM baseline UID1000/root failures | x86 baseline UID1000/root failures | Fixed ARM/x86 failures per cohort |
| --- | --- | --- | --- |
| Original | 814 / 820 | 1,088 / 1,096 | 105 / 112 |
| Musl exact-zero corrected | 730 / 736 | 1,004 / 1,012 | 21 / 28 |
| Musl zero and executable target corrected | 712 / 718 | 980 / 988 | 0 / 0 |

Every final baseline failure is an invalid signed32 size or excess copying
caused by upper bits. Original/intermediate candidate failures are confined
to the two expectation mistakes; they remain failed aggregate receipts.
Both aggregates independently pass open/pathio/namespace/runtime with the
same kernel binaries and matching fixture C. Fresh final new-fixture suites
pass on those identical kernels.

Six stable cohort descriptors plus transient directory aliases survive 32
warm-ups and 200 measured cycles of 52 raw probes plus one alias-relative copy
and state controls. Types/sizes, public ABCD bytes, shared regular-file cursors,
FD flags and private search refusals stay correct. All live slab classes remain
flat; big pages stay **63/63 ARM and 160/160 x86** in both cohorts. Loop and
bad pathname-pointer outcomes remain outside the repeated storage loop.
Handles/Slabs use bounded alloca; probe buffers remain on the stack, without
hidden fixture allocation. All child descriptor, transient-alias and observer
paths close their owned references.

The [independent final lifetime review](../tests/linux-compat/results/2026-10-13/readlinkabi-lifetime-review.md)
confirms generated cleanup on every return, synchronous borrowing, matching
final source/C captures and flat retention, with no new kernel ownership.

[ARM evidence](../tests/linux-compat/results/2026-10-13/readlinkabi-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/readlinkabi-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/readlinkabi-audit.v)
bind all original/intermediate/final results, source/init/image hashes,
compiler/controller/kernel binaries/C and both executed failing audit controls.
Both builds, eight host test files and generated inventory checks pass. The
allocation allowance audit still fails with **406 ARM/295 x86** sites and exact
unchanged NEW rows; no allowance is raised. Private trees pin `ddefb845b`; only
three syscall-table files differ. Reversing the adapter, native dispatch and
legacy routing restores the entire baseline kernel C. All 63 isolated semantic
inputs are pinned separately from the public committed-parent inventory.

Empty-path symlink descriptor support, Linux procfs target spelling, link atime,
restrictive MAC/pledge/unveil combinations, concurrent link/FD changes,
partial-copy boundaries, disk/overlays, GNU/translated/ELF32 paths and complete
Linux installation/sandbox/portal/runtime acceptance remain separate work.
The three broad section-15 gates stay open.

## Native empty-path readlink

`readlinkat(fd, "", ...)` now reads the symlink named by an existing description,
including O_PATH|O_NOFOLLOW handles after unlink or private-directory search
permission denial. The descriptor lookup retains both FD and Handle until
the synchronous target helper returns. The Handle pins its node and original
resource; an orphan's parent pin preserves ancestry for policy checks. Every
new return releases the reference. Non-symlink/no-node handles and AT_FDCWD
return ENOENT; invalid descriptors return EBADF. Native signed32 size validation
still runs first. This follows
[Linux v6.12 do_readlinkat's empty-path lookup and type errors](https://raw.githubusercontent.com/torvalds/linux/refs/tags/v6.12/fs/stat.c).

The existing policy/type/procfs/copy tail moves into `readlink_node` without
source changes. Normal pathname handling retains its lookup, permissions,
copy semantics and ownership. The empty-path handler uses the lower signed32
descriptor word, keeps existing pathname ownership and calls that shared tail.
Dynamic target text is freed exactly once after each copy or error.

The V `readlinkempty` fixture passes **7,296 checks per architecture** in root
and UID/GID1000 children. Fourteen classes cover named and dangling symlink
handles, a symlink whose name is removed, a private-directory symlink inherited
before dropping credentials, dynamic procfs self/exe links, ordinary and O_PATH
regular files, directories, `/dev/null`, pipe/socket handles and invalid/FDCWD
arguments. Ordinary links and their deleted/private counterparts hold target
text even when the target is absent. Procfs exe names the staged `/sbin/init`;
self retains Vinix's existing absolute spelling, whose Linux qualification
is separate. Three aliases, eight size words, three raw FD upper-word patterns
and musl controls cover valid/null/inaccessible buffers, signed32 size errors,
exact-zero libc scratch behavior and upper-word decoding.

Both baselines fail **1,197 checks per cohort**: 414 target/scratch copies,
720 destination EFAULT refusals and 63 invalid-FD EBADF expectations all return
ENOENT. Both fixed kernels have zero failures. Copies verify exact target
prefix length/bytes, no NUL and unchanged canaries. Inode/device/mode/size/
UID/GID/nlink, FD flags, shared regular-file cursors and actual ABCD bytes stay
unchanged. The removed name still returns ENOENT; new ordinary-user private
path opens still return EACCES despite the inherited descriptor authority.
Real pipe/socket FIONREAD/poll retain two AB bytes; each child drains, compares
and replenishes those queues.

Each cohort has 38 descriptors, including three child-owned exe-link aliases;
aliases share open-file descriptions. The parent keeps 35 inherited references.
After 32 warm-ups, 200 cycles of 56 raw probes plus three transient dup/copy
controls retain every slab live-object count and **70/70 ARM, 181/181 x86** big
pages. Deleted handles remain usable well beyond the five-second node-reaping
grace period. Handles/Slabs use bounded alloca and other buffers remain on the
stack. Setup failures, child returns, temporary aliases, control opens and
observer paths close their references. The successful parent pauses until
guest teardown.

The [independent final lifetime review](../tests/linux-compat/results/2026-10-13/readlinkempty-lifetime-review.md)
confirms generated cleanup on every return, descriptor-before-node release
ordering, origin-resource and orphan-parent pins, synchronous borrowing,
matching final source/C captures and flat retention. No hidden fixture heap
allocation or promotion is present.

A concurrent cleanup deleted all `/tmp/vinix-*` build/compiler work areas
during the first empty-path candidate builds. The root edits and committed
prior results survived; no empty-path guest verdict existed in the lost area.
Qualification was rebuilt from clean sources in
`/Users/alex/.cache/vinix-linux-compat/readlinkempty-20261013`. The compiler's
first rebuild lacked its untracked TinyCC header/library dependency, and a
bootstrap-controller attempt encountered a segmentation fault. Those host
failures remain preserved separately from successful fresh compiler/controller,
baseline/candidate builds and guest runs. The compiler is the clean pinned
`f6358ecff9` tree. The compiler make inherited a shared VEXE output path; its
rebuilt shared binary matches the same clean source revision, while the native
qualification rebuild writes an explicit separate compiler output.

[ARM evidence](../tests/linux-compat/results/2026-10-13/readlinkempty-aarch64-evidence.json),
[x86 evidence](../tests/linux-compat/results/2026-10-13/readlinkempty-x86_64-evidence.json)
and the [assertion-enabled V auditor](../tests/linux-compat/results/2026-10-13/readlinkempty-audit.v)
bind all before/after logs and source/init/image hashes, compiler/controller/
kernel binaries/C, host incidents, final lifetime review and both executed
failing controls. Both architectures also pass readlinkabi/open/pathio/runtime.
Both builds, eight host test files and generated inventory checks pass. The
allocation allowance audit retains **406 ARM/295 x86** failures with exact
unchanged NEW rows; no allowance is raised. Private trees pin `49cee5ac7`; only
fs/vfs.v differs. Removing the helper and restoring the handler reproduces
the entire baseline kernel C. All 63 isolated semantic inputs are fingerprinted
separately from the public committed-parent inventory.

Linux procfs target spelling, atime, restrictive policy combinations,
concurrent close/unlink/exec, partial-copy boundaries, disk/overlays and
GNU/translated/ELF32 paths, plus complete Linux installation/sandbox/portal/
runtime acceptance, remain separate work. The three broad section-15 gates
stay open.

## Relative procfs self and thread-self links

The native procfs formatter now returns the reader's PID for `self` and
`PID/task/TID` for `thread-self`, relative to the procfs root. Linux uses those
relative targets in [self.c](https://github.com/torvalds/linux/blob/master/fs/proc/self.c)
and [thread_self.c](https://github.com/torvalds/linux/blob/master/fs/proc/thread_self.c).
An absolute `/proc/...` target previously selected the wrong location inside a
chroot without `/proc`; relative targets resolve inside the mounted tree. The
existing view supplies both IDs. Buffer construction, synchronous namespace
borrowing and caller-owned target freeing remain unchanged.

The native musl `procself` guest runs 1,620 raw/libc checks per architecture:
two credential groups, three readers per forked process, three procfs mounts,
two links, five call forms, three positive sizes and three destination classes.
Descriptors are opened before fork and retained through all reader threads;
empty-path reads name the current reader rather than the opening process.
Exact target prefixes, untouched canaries, no NUL and EFAULT refusals are
checked. Named resolution and explicit numeric lookup select equal
inode/device/mode values with the reader's Tgid. A root child opens both status
files inside a chroot containing `/view` and no `/proc`.

| Architecture | Baseline failures per reader | Candidate failures | Root/UID1000 large pages, before/after |
| --- | --- | --- | --- |
| AArch64 | 90 of 270, all six readers; chroot resolution fails | 0 of 1,620; chroot passes | 63/63 in both groups |
| x86-64 | 90 of 270, all six readers; chroot resolution fails | 0 of 1,620; chroot passes | 160/160 in both groups |

After 32 warmups, each credential group runs 200 cycles of 120 target reads and
six status resolutions. Every live slab class stays exact: 18 classes on ARM
and 14 on x86. Both kernels build in isolated worktrees at
`7da8032f9ea39d0d6dacd0c609aebd77f13ff8ed`, with only `kernel/fs/procfs.v`
modified. Restoring the formatter and exact literal-pool symbols/order, then
normalizing only unused-loop source offsets, reproduces the whole baseline C. The legacy unreferenced helper and its comment also use the relative
spelling. Both actual before/after fixture C files match their architecture's
preview. Independent source and generated-C lifetime review checks Text
ownership, both VFS freeing paths, namespace borrowing, inherited descriptors
and stack state through successful joins. A failed join exits without unwinding
state a worker could still access.

Both architectures also pass `readlinkabi`, `readlinkempty`, `open`,
`namespace` and `runtime`; only the two older readlink fixtures' expected procfs
target literals change. The allocation audit still exits 1 with 406 ARM and 295
x86 sites and identical `NEW:` rows; no allowance changes. Eight compatibility
host test files and the 63-input dispatch inventory check pass. Public inventory
fingerprints are generated from the committed parent plus this fix; the evidence
files retain the separate isolated semantic build inputs.

The independent procfs inactive-view reuse suite passes on both architectures,
including PID-namespace target `1`, invisible readers returning ENOENT and
retargeted aliases. The full procfs mount suite fails its existing 16 KiB
retention assertion at diagnostic line 80 on both baseline and candidate.
Those runs are published as failures without changing that bound. They do not
qualify full procfs mount retention.

Initial wider status-file assertions also fail because a nonleader task's
status reports the process PID in its `Pid` field. The initial ARM candidate
already passes all target probes and chroot resolution, while those status
assertions fail. The final target suite checks numeric inode selection and Tgid;
per-task `Pid` reporting remains a separate conformance bug. Original baseline
receipts on both architectures and the failed ARM candidate receipt remain
published. CLI steering interrupted the original-assertion x86 candidate before
it produced a receipt; its partial log/source/C are pinned without claiming a
verdict. Final runs use fresh state directories. An allocation invocation that
overlapped candidate source copying is retained separately; the authoritative
baseline audit was rerun against an immutable worktree.

The assertion-enabled [auditor](../tests/linux-compat/results/2026-10-13/procself-audit.v)
requires baseline failure markers, the exact reader/copy/retention results,
compiled source/ELF/ISO and kernel receipts, generated-C scope, review hashes and
unchanged allocation refusals. Both deliberately failing controls execute:
`assert false` fails, and a passing guest log cannot satisfy baseline checks.
Evidence and raw captures are [AArch64](../tests/linux-compat/results/2026-10-13/procself-evidence-aarch64.json)
and [x86-64](../tests/linux-compat/results/2026-10-13/procself-evidence-x86_64.json),
with [ARM baseline](../tests/linux-compat/results/2026-10-13/procself-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/procself-after-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/procself-before-x86_64.log)
and [x86 candidate](../tests/linux-compat/results/2026-10-13/procself-after-x86_64.log).

This qualifies the native relative-link subset. Symlink atime, restrictive
policy, close/unlink/exec races, partial copying, full mount retention and
glibc/translated/ELF32 installation/sandbox/portal acceptance remain separate.
The three broad section 15 gates stay open.

## Selected task status identities

Native task status now reports the selected TID in `Pid` and `NSpid`, preserving
the process ID in `Tgid`. Linux distinguishes these fields in
[proc task_state](https://github.com/torvalds/linux/blob/master/fs/proc/array.c).
Previously every worker's status used its leader's PID, including the local
entry of a root-view `NSpid`. The existing table lock retains the validated
selected task through `tid_in`, namespace-local ID reads and Text completion.
No pointer escapes and no ownership or allocation path changes.

The extended native musl `procself` fixture retains its 1,620 relative-link
probes per architecture and adds exact `Pid`/`Tgid`/`NSpid` to all 36 selected
status checks across root/UID1000 forked main/pthread readers and three procfs
aliases. A worker reading `self/status` still sees the leader's ID; its
`thread-self/status` identifies the worker. Named and explicit numeric paths
continue to select equal inode/device/mode values.

A separate PID namespace runs a leader and worker against both an inherited
root-view directory and an independently mounted procfs tree. Four status
checks require root-view selected TID/process ID and two `NSpid` entries, or
the own-view local TID/process ID and exactly one entry. The local worker is
TID 2, distinct from PID 1; its outer TID also differs from the outer process ID.
The test reads expected outer identities from the preceding qualified relative
links. Status paths remain in their selected procfs view.

| Architecture | Baseline | Candidate | Large pages before/after, root and UID1000 |
| --- | --- | --- | --- |
| AArch64 | Four worker matrices fail status; both namespace worker views fail; leaders pass | All selected fields and link probes pass | 63/63 in both groups |
| x86-64 | Four worker matrices fail status; both namespace worker views fail; leaders pass | All selected fields and link probes pass | 160/160 in both groups |

After 32 warmups, each credential group performs 200 cycles of 120 link probes
and six status checks. All 18 ARM and 14 x86 live slab classes stay exact.
Namespace construction occurs once before the root sample; these results do
not qualify repeated namespace creation or whole-tree reclamation. Both
architectures also pass `nnpthread`, `seccompthread`, `namespace`, `open` and
`runtime`. The existing per-task security fields retain their separate task
state. Eight host test files pass. Allocation audits still exit 1 with unchanged
406 ARM/295 x86 sites, 657/653 source files and identical `NEW:` rows. No
allowance is raised.

Both baseline and candidate kernels build from isolated worktrees at
`b4337df12f97e7b2ba12df3b3f9613ff9e7600a6`. Only `kernel/proc/proc.v` differs.
Restoring `process_status_text` and normalizing only compiler unused-loop source
offset names reproduces the complete baseline generated C. Both before/after
guest C files equal the final previews. Fixture functions outside status checks
and namespace helpers remain byte-identical to the preceding relative-link
qualification. Independent lifetime review verifies table locking, stack
NamespaceWorker state through successful joins, `_exit` on join failure, and
descriptor cleanup through both forks.

The first namespace test mounted its new view over `/proc`; setup failed before
the namespace field markers, while the ordinary worker status failures were
still reproduced. Both original failed receipts, raw logs and the exact draft
source/C hashes remain published. Final tests keep the inherited root mount
uncovered and mount the new tree separately. Overmounted directory-descriptor
view preservation remains unqualified. A draft declaration placed in the wrong
formatter was corrected before candidate builds.

The assertion-enabled [auditor](../tests/linux-compat/results/2026-10-13/procstatus-audit.v)
requires the baseline's wrong leader IDs, candidate's exact namespace columns,
all compatibility verdicts, source/compiled-source/ELF/ISO/kernel receipts,
generated-C scope, review hashes and flat retention. Both deliberately failing
controls execute. The evidence files bind all 63 isolated semantic inputs and
the compiler/controller/build/C/capture/receipt hashes:
[AArch64](../tests/linux-compat/results/2026-10-13/procstatus-evidence-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-13/procstatus-evidence-x86_64.json),
[ARM baseline](../tests/linux-compat/results/2026-10-13/procstatus-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/procstatus-after-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/procstatus-before-x86_64.log)
and [x86 candidate](../tests/linux-compat/results/2026-10-13/procstatus-after-x86_64.log).
Public inventory fingerprints are regenerated from the committed parent plus
this fix, separately from the tested kernel's input set.

This closes the selected native task `Pid`/`NSpid` gap exposed in the preceding
relative-link work. Nested namespaces beyond Vinix's existing one-level model,
zombie/task retirement, overmount/unmount and concurrent teardown, additional
status/stat fields, full mount retention and glibc/translated/ELF32 or application
installation/sandbox/portal acceptance remain separate. The three broad section
15 gates remain open.

## Selected task stat identity and scheduling

Native `/proc/<pid>/task/<tid>/stat` now uses the validated selected task for
field 1 (namespace TID), field 18 (effective priority), field 40 (real-time
priority) and field 41 (policy). Process paths retain their leader's values.
Linux's [do_task_stat](https://github.com/torvalds/linux/blob/master/fs/proc/array.c)
selects task identity and scheduling for these fields. Previously every worker
used the process leader. The existing process-table lock retains the selected
task through validation, scheduler snapshot, namespace lookup and Text
serialization. No reference ownership, allocation or freeing path changes.

The extended native musl `procself` fixture retains 1,620 link probes per
architecture and selected status identity checks, adding 84 initial stat reads
through named and explicit numeric paths: 72 across root/UID1000 main/pthread
readers and three procfs aliases, eight across namespace leader/worker inherited
root and own procfs views, and four in a chroot without `/proc`. Main and process
paths retain ordinary policy. Workers set FIFO priority 17 and RR priority 33;
the PID-namespace worker sets FIFO priority 23. Pthread getters verify requested
values and targeted raw syscall queries independently supply expected stat
fields. Real-time policies require effective priority `-1 - rt_priority`.
Workers restore ordinary scheduling before returning.

| Architecture | Baseline | Candidate | Large pages before/after, both credential groups |
| --- | --- | --- | --- |
| AArch64 | 28 worker records show leader PID and priority/rtprio/policy 20/0/0 | All 84 initial records and existing link/status controls pass | 63/63 |
| x86-64 | 28 worker records show leader PID and priority/rtprio/policy 20/0/0 | All 84 initial records and existing link/status controls pass | 160/160 |

Each baseline has 12 FIFO17, 12 RR33 and four FIFO23 failures. The existing
status Pid/NSpid and relative-link targets remain correct; leader stat controls
pass. After 32 warmups, each credential group runs 200 cycles containing 120
link probes, six status checks and 12 stat reads. All 18 ARM and 14 x86 live slab
classes stay exact. Namespace creation occurs once before sampling; repeated
namespace creation/reclamation remains separate. Both architectures also pass
`nnpthread`, `seccompthread`, `namespace`, `open` and `runtime`. Eight host test
files and the isolated 63-input dispatch inventory check pass. Allocation
audits retain their existing exit 1: identical `NEW:` rows, 406 ARM/295 x86 sites
and 657/653 source files. No allowance changes.

The first fixture used bundled musl-1.2.5 process-level `sched_setscheduler`,
`sched_getscheduler` and `sched_getparam`, all of which return ENOSYS. Both first
baseline runs exited during setup before matrix markers; their owned QEMUs were
terminated, leaving failed missing-verdict receipts. Diagnostic candidate runs
then show errno 38 from the ordinary-policy setup call on both architectures.
These draft sources, compiled-source hashes, logs and failed receipts remain
published. Final tests use real musl pthread scheduling APIs and raw targeted
queries, and explicitly require the unchanged ENOSYS process-wrapper refusals.
Root sets `RLIMIT_RTPRIO` to 99 before forking both credential groups.

Both kernels build in isolated worktrees at
`21f57bbae976c4165a8b9dca7c431a049f7d9416`; only the formatter and its procfs
callback change. Restoring that formatter body, its prototype/definition
parameter and the single callback, then normalizing only unused-loop source
offset names, reproduces the complete baseline generated C. Actual before and
after guest C equals the final previews. Independent lifetime review verifies
table locking, synchronous stack scheduling/parser borrows, descriptor cleanup
and worker state surviving joins. Failed joins exit before stack state unwinds.

The assertion-enabled [auditor](../tests/linux-compat/results/2026-10-13/procstat-audit.v)
requires exact baseline failures, candidate fields and namespace columns,
all six compatibility verdicts, source/C/ELF/ISO/kernel receipts, review hashes,
generated-C scope, flat retention and unchanged allocation audit failures.
Both deliberately failing controls execute. The evidence binds all 63 isolated
inputs and compiler/controller/build/kernel/C/capture/receipt hashes:
[AArch64](../tests/linux-compat/results/2026-10-13/procstat-evidence-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-13/procstat-evidence-x86_64.json),
[ARM baseline](../tests/linux-compat/results/2026-10-13/procstat-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/procstat-after-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/procstat-before-x86_64.log)
and [x86 candidate](../tests/linux-compat/results/2026-10-13/procstat-after-x86_64.log).
Public inventory fingerprints are regenerated from the committed parent plus
this fix, separately from the semantic build input set.

This qualifies only selected native identity and scheduling fields. At this
qualification CPU/fault accounting, state, nice, start time and command remain
process-wide in the formatter. The following extension qualifies CPU/fault
fields separately. Scheduler timing, task retirement, overmount/unmount races, full
procfs mount retention and glibc/translated/ELF32 or application installation,
sandbox and portal acceptance remain separate. The three broad section 15 gates
remain open.

## Selected task stat CPU and fault accounting

Native task stat now reads the selected thread's minor/major fault counters and
CPU times for fields 10/12/14/15. Process stat retains all siblings' lifetime
totals, including retired threads, and both paths use the existing CPU snapshot
helpers to include unfinished running turns. Linux's
[do_task_stat](https://github.com/torvalds/linux/blob/master/fs/proc/array.c)
distinguishes task counters from thread-group totals. Previously task records
reported process totals and CPU fields read only stored counters. Child fields,
selected identity/scheduling, Text ownership and allocation/free paths remain
unchanged. The table lock retains the validated target throughout; process
snapshots take thread-list then CPU locks, and task snapshots take the CPU lock,
matching existing readers. CPU charging releases that lock before signal delivery.

The native musl fixture brackets every named/numeric stat read with
`getrusage(RUSAGE_THREAD)` or `getrusage(RUSAGE_SELF)` and requires minor/major
faults and 100 Hz user/system ticks within those exact before/after ranges.
Each credential group's leader and two workers reserve 64 MiB, touch 256/32/64
`sysconf`-sized pages, unmap, and require positive minor-fault deltas with
unchanged major counts. Both architectures produce exactly those fault counts.
Measured thread CPU work lasts at least 200/50/100 ms with a printed checksum
preserving the computation. Worker samples require more process faults and at
least ten additional process CPU ticks, ensuring the two views differ.

| Architecture | Baseline | Candidate | Large pages before/after, both credential groups |
| --- | --- | --- | --- |
| AArch64 | 28 task records report process fault/CPU totals | All 84 initial bracketed reads and retention cycles pass | 63/63 |
| x86-64 | 28 task records report process fault/CPU totals | All 84 initial bracketed reads and retention cycles pass | 160/160 |

Each baseline has 12 records exceeding a worker's 32-fault oracle, 12 exceeding
the other worker's 64-fault oracle and four exceeding the namespace worker's
zero-fault oracle. User ticks exceed worker brackets in all 24 ordinary worker
records. Major counts are zero controls; these runs do not qualify nonzero
disk-backed major-fault production. All previous identity/scheduling and 1,620
link probes remain correct. Existing status fields and leader controls pass;
only appended task accounting checks fail.

Candidates retain root/UID1000 main/fork/pthread readers, three proc aliases,
chroot and inherited-root/own-PID namespace views, plus FIFO17/RR33/FIFO23
controls. After 32 warmups, 200 cycles per credential group perform 120 link
probes, six status checks and 12 stat reads per cycle, including the process
totals after worker retirement. All 18 ARM and 14 x86 live slab classes remain
exact. Both architectures also pass `nnpthread`, `seccompthread`, `namespace`,
`open` and `runtime`; eight host test files pass. Allocation audits retain exit
1, identical `NEW:` rows, 406 ARM/295 x86 sites and 657/653 source files. No
allowance changes.

Original small-map baseline runs also expose the bug, but ARM eagerly fills
those mappings and the workers record no positive touch faults. Those failed
receipts, logs and original source/C remain published. Final tests explicitly
use demand reservations on both architectures and verify fault deltas. A draft
MAP_FAILED comparison was corrected before guest compilation.

Both kernels build in isolated worktrees at
`9880153c2832ad17b0b82c162441cdbc45b1b9d9`. Restoring one formatter body and
normalizing only unused-loop source offsets reproduces the complete baseline
generated C. Both actual before/after guest C files equal the final previews.
Independent lifetime review verifies nested lock order, scalar CPU/fault
snapshots, stack rusage/clock buffers, unmapping before later errors, descriptor
closure and worker state through joins. No new ownership transfer occurs.

The assertion-enabled [auditor](../tests/linux-compat/results/2026-10-13/procaccount-audit.v)
requires positive fault/CPU separation, exact baseline failure counts, source
unchanged outside described fixture helpers, all six candidate verdicts,
compiled-source/ELF/ISO/kernel receipts, generated-C scope, review hashes and
flat storage. Both deliberately failing controls execute. Evidence binds all
63 isolated inputs and compiler/controller/build/C/capture/receipt hashes:
[AArch64](../tests/linux-compat/results/2026-10-13/procaccount-evidence-aarch64.json),
[x86-64](../tests/linux-compat/results/2026-10-13/procaccount-evidence-x86_64.json),
[ARM baseline](../tests/linux-compat/results/2026-10-13/procaccount-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/procaccount-after-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/procaccount-before-x86_64.log)
and [x86 candidate](../tests/linux-compat/results/2026-10-13/procaccount-after-x86_64.log).
Public inventory fingerprints are generated from the committed parent plus this
fix, separately from semantic build inputs.

Nonzero disk faults, child-time accounting, overflow, timer/scheduler timing,
nice/start/name fields, repeated namespace creation/reclamation, concurrent
retirement/unmount and glibc/translated/ELF32 or application installation,
sandbox and portal acceptance remain separate. The three broad section 15 gates
remain open.

## Selected procfs task states

Native stat field 3 and status `State` now describe the selected thread.
Process paths select the leader, even while another sibling runs. Linux's
[task_state and do_task_stat](https://github.com/torvalds/linux/blob/master/fs/proc/array.c)
read the selected task for these fields. Previously a sleeping task appeared
running whenever any sibling was running or queued. The existing table lock
retains the validated task while a scalar helper reads exit/dead, completed
job-stop and selected runnable/running-on state. It adds no lock, allocation or
ownership transfer. The unused aggregate wrapper is pruned from this build;
SysRq's unchanged unlocked aggregate helper remains.

The native musl fixture adds a leader and one worker with two shared pipe pairs.
The worker signals readiness and blocks on a command pipe while the leader
reads its files. Then the leader blocks on a report pipe while the worker reads
the leader's files. Each phase settles the actual blocking read before checking
30 records across three procfs mounts, both stat/status formats and self,
thread-self, numeric process, leader-task and worker-task paths. Root/UID1000
cohorts produce 120 initial R/S records. Full status descriptions are compared,
including spaces and the newline. SIGSTOP plus WUNTRACED supplies 24 stopped
process/task controls; SIGKILL plus WNOWAIT supplies 12 zombie process controls
before the child is reaped. Zombie Thread objects are released before wait
publication in Vinix, so zombie task directories remain unqualified.

| Architecture | Baseline | Candidate | Large pages before/after, both credential groups |
| --- | --- | --- | --- |
| AArch64 | 48 sleeping records report R | All 156 initial state records pass | 75/75 |
| x86-64 | 48 sleeping records report R | All 156 initial state records pass | 198/198 |

Each baseline has six failures for a sleeping worker and 18 for a sleeping
leader per credential cohort. There are six failures per format in each path
category: self, numeric process, numeric leader task and numeric worker task.
Running and stopped/zombie controls pass. The preceding 1,620 link probes, 84
identity/scheduling/accounting stat reads, positive 256/32/64 demand faults,
measured CPU work and PID-view/chroot controls remain byte-for-byte unchanged
in their fixture helpers and still pass.

The worker blocks again and remains held with the two pipe pairs through the
32 warmups and 200-cycle storage sample in each cohort. Each cycle runs 120
link probes, six status controls, 12 accounting stat reads and 30 additional
state reads. All 18 ARM and 14 x86 live slab classes remain exact. Joins precede
closing all four pipe descriptors; handshake/join failures exit the child
before stack state can unwind. Child failures kill and reap before returning.
Independent review confirms explicit stack StateWorker storage, local parser
buffers, descriptor cleanup and table-retained scalar kernel reads.

An initial StateWorker local was promoted to heap by V. Both native C compilers
reject its `memdup` call before any ELF/ISO/guest verdict. The final fixture uses
explicit `alloca`; its four bounded stack allocations include the existing
Handles and two Slabs objects. No memdup/malloc/new-array/bounds runtime occurs
in the bare generated C. Draft source/C hashes, error logs and failed receipts
remain published without claiming kernel conformance results.

Each primary candidate run passes five of six requested cases. Host disk
exhaustion prevents the ARM runtime ISO and x86 namespace tool compilation;
the latter also records a failed fallback compiler attempt. Completed verdicts
are preserved. Fresh state directories using the same kernel and source hashes
rerun only `runtime` on ARM and `namespace` on x86, both passing. All six
semantic verdicts (`procself`, `nnpthread`, `seccompthread`, `namespace`, `open`,
`runtime`) therefore pass across primary and recovery receipts. Original
aggregate receipts remain failed, with actual missing-artifact fields.

The first after-allocation scan completes ARM but refuses x86 compilation after
the executable at the shared compiler path changes; it is retained as an
incomplete audit. That path was observed reporting a27079a while its source
worktree remained at f6358ec. A private clean-source f6358ec compiler reproducer
is pinned separately. Its executable differs from the earlier build binary;
it regenerates all four complete baseline/candidate kernel C files byte-for-byte
after the kernel recipe's two exact text edits. Reproduced fixture C differs
only in the compiler's unused stderr-print prelude. Replacing that exact
validated block reproduces original C; both print helpers have no callers.
Actual guest C remains identical to the original corrected previews.
This ties captured C to the private compiler without claiming the earlier
executable is still available. The pinned re-audit restores the unchanged
406 ARM/295 x86 allowance failures, 657/653 source files and identical `NEW:`
rows. Eight host test files and the 63-input inventory check pass with that
private compiler. No allowance changes.

Kernels build in isolated worktrees at
`d0694ccac90d48f78ddd4d6cafdad0813e314aa9`. Only two formatter state calls and
the scalar helper change. Restoring the formatters, removing the new helper and
reinserting the pruned aggregate wrapper at its original prototype/definition
sites reproduces complete baseline C, normalizing only unused-loop source
offset names. Actual before/after guest C equals the corrected previews.

The assertion-enabled [auditor](../tests/linux-compat/results/2026-10-13/procstate-audit.v)
requires exact 48 baseline failures, state/child controls, preceding field
qualification, flat storage, source/C/ELF/ISO/kernel receipts, failed primary
artifacts and same-input recovery verdicts. It also checks the private compiler's
exact regenerated C, source tree, completed allocation re-audit and independent
review hashes. Both deliberately failing assertion controls execute.
[ARM evidence](../tests/linux-compat/results/2026-10-13/procstate-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/procstate-evidence-x86_64.json)
bind all 63 isolated inputs and relevant compiler/controller/build/C/capture
hashes. Raw primary and recovery captures are
[ARM baseline](../tests/linux-compat/results/2026-10-13/procstate-before-aarch64.log),
[ARM primary](../tests/linux-compat/results/2026-10-13/procstate-after-aarch64.log),
[ARM recovery](../tests/linux-compat/results/2026-10-13/procstate-retry-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/procstate-before-x86_64.log),
[x86 primary](../tests/linux-compat/results/2026-10-13/procstate-after-x86_64.log)
and [x86 recovery](../tests/linux-compat/results/2026-10-13/procstate-retry-x86_64.log).
Public inventory fingerprints use the committed parent plus this fix, separately
from the isolated semantic build inputs.

Zombie task directories, leader-only thread exit, D/t/X/I states, stop-transition
windows, cgroup holding, concurrent retirement, full procfs mount retention and
glibc/translated/ELF32 or application installation/sandbox/portal acceptance
remain separate. The three broad section 15 gates remain open.

## Selected procfs task names

Native comm files, stat field 2 and status `Name` now select the requested
thread. Process paths select the leader. Explicit names preserve slash,
bracket, parenthesis, backslash and newline bytes, including an explicitly
empty name. Status escapes newline and backslash; comm/stat retain raw bytes.
Unnamed tasks use the executable basename, bounded to 15 bytes. Linux's
[proc_task_name](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/proc/array.c)
uses the selected task and escapes status separately from stat.

`PR_SET_NAME` now stops at NUL while reading at most 15 user bytes, allowing
short/empty strings terminated at the end of a mapped page and a 15-byte name
without an accessible sixteenth byte. Unterminated short ranges, null,
wrapping and protected pointers return EFAULT before changing either name.
Long names truncate. `PR_GET_NAME` snapshots the selected name and writes all
16 zero-padded bytes, preserving surrounding canaries; null and readonly
destinations return EFAULT. This matches Linux's
[prctl name cases](https://raw.githubusercontent.com/torvalds/linux/master/kernel/sys.c).

Both Thread definitions now distinguish an explicit empty name from an unnamed
task. Both clone implementations inherit that flag with the existing owned
comm copy. Successful PR_SET_NAME replacements and frees hold the same table
lock as procfs readers. New scalar/borrowed-name helpers allocate nothing;
GET copies a complete stack snapshot before releasing the lock and accessing
userspace. Thread-command Text now uses explicit stack storage.

| Architecture | Baseline | Candidate | Large pages before/after, both credential groups |
| --- | --- | --- | --- |
| AArch64 | 378 wrong name records; six boundary controls fail | All 504 records and 20 prctl controls pass | 75/75 |
| x86-64 | 378 wrong name records; six boundary controls fail | All 504 records and 20 prctl controls pass | 198/198 |

Root/UID1000 leader and worker readers produce 360 exact name records: four
45-record phases use three proc mounts, self/thread-self, numeric process and
leader/worker task paths, and comm/stat/status formats. The worker first uses
a distinct nonempty name, then an empty name. Named pthread inheritance is
checked before that replacement. Fork from the empty worker adds 72 records
and empty-name GET controls. Actual exec of the fixture adds 72 records and
requires the reset name `init` through GET_NAME. Twenty API controls cover
page-boundary short/15-byte/empty strings, unchanged names through four SET
fault cases, two GET faults, exact zero padding/canaries and long truncation.

Each baseline fails 306 phase records (120 stat, 120 status, 66 comm), all 72
empty-fork records, the six successful boundary cases and GET_NAME for the
empty worker, inherited empty name and exec reset. Each credential group's
phase failure counts are 36/36/42/39. Existing exec procfs names already pass;
its GET_NAME incorrectly returned the path/pid form. The prior 156 task-state
records, 1,620 link probes, 84 identity/scheduling/accounting stat reads,
positive demand faults/CPU work, PID-view and chroot controls still pass.

Generated C revealed that both legacy 16-byte prctl scratch arrays were
promoted by memdup without freeing. Pointer annotations still promoted them.
The final code uses the kernel's explicit stack allocator; no memdup remains
in prctl. Original, promoted and pointer-annotation C/build captures remain
in the private qualification area. Earlier fixture captures are retained
separately; final before/after receipts use identical source, generated C and
native init ELF. This diagnosis comes from emitted code; baseline semantic
failures prevent a repeated storage verdict on the old kernel.

Each credential cohort performs 32 warmups and 200 measured cycles while the
worker and two pipe pairs remain held. Each cycle performs two SET/GET
roundtrips, 90 name reads, 30 state reads, 120 link probes, six status checks
and 12 accounting stat reads. Every live slab class remains exact: 18 on ARM
and 14 on x86. Explicit scratch storage and thread-command Text remove three
allocation sites: 406/295 baseline sites become 403/292 in 657/653 source files.
The two table escapes disappear and the existing proc escape count falls from
two to one. Other NEW rows remain unchanged; no allowances change.

ARM passes all six related guest cases. The x86 primary passes procself,
nnpthread and seccompthread; host disk exhaustion prevents namespace ISO
creation and open/runtime tool compilation. Its failed receipt and missing
artifact fields remain visible. Fresh same-kernel/source recovery passes
namespace, open and runtime. All six native semantic verdicts therefore pass
across primary/recovery captures. Eight host test files and the inventory
check pass with the same private f6358ec compiler used for both kernel builds.

Kernels build in isolated worktrees at
`708f21f5fe7d79027ad70db692cbc3c77e43a205` with only the six owned kernel paths
changed. The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/proccomm-audit.v)
checks exact baseline failure counts, all positive/error controls, flat
storage, private source isolation, emitted stack/no-allocation helpers,
before/after fixture C/init ELF identity, unchanged allocation refusals and independent
[lifetime review](../tests/linux-compat/results/2026-10-13/proccomm-lifetime-review.md)
hashes. Both deliberately failing assertion controls execute.
[ARM evidence](../tests/linux-compat/results/2026-10-13/proccomm-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/proccomm-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/build/kernel/C/source/
ELF/ISO/capture/review hashes. Raw captures are
[ARM baseline](../tests/linux-compat/results/2026-10-13/proccomm-before-aarch64.log),
[ARM primary](../tests/linux-compat/results/2026-10-13/proccomm-after-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/proccomm-before-x86_64.log),
[x86 primary](../tests/linux-compat/results/2026-10-13/proccomm-after-x86_64.log)
and [x86 recovery](../tests/linux-compat/results/2026-10-13/proccomm-retry-x86_64.log).
Public inventory fingerprints use the committed parent plus this fix,
separately from the isolated semantic build inputs.

Concurrent rename observation timing, exec/retirement races, named zombies,
leader-only exit, writable proc comm, GNU/translated/ELF32 paths and application
installation/sandbox/portal acceptance remain separate. That baseline replaces
process.name outside the table lock; the later exec publication qualification
below covers synchronized replacement. The three broad section 15 gates remain open.

## Procfs metadata publication during exec

Both native exec loaders now replace the owned process name and executable
path under the process table lock used by procfs readers. The new name is
constructed before locking; both old strings are reclaimed and both fields
published before unlocking. Readers finish borrowing the old bytes before
reclamation. Command-line and executable-filesystem installation retain their
existing separate synchronization.

The V `execnames` fixture observes a child through three procfs mounts while
it performs 200 actual exec replacements, alternating two copied native init
ELFs. Root and UID/GID1000 parents read numeric-child comm, stat, status and
exe. Exact allowlists contain the initial name/path and either replacement.
Each read may independently see an old or new generation; multiple files do
not form an atomic snapshot. Dumpability is established after UID changes
and before the initial gate, authorizing same-UID exe reads throughout.

| Architecture / reader | Baseline reads per kind | Candidate reads per kind | Baseline invalid comm/stat/status/exe | Candidate invalid records |
| --- | ---: | ---: | --- | ---: |
| AArch64 UID1000 | 597 | 603 | 0/0/0/0 | 0 |
| AArch64 root | 603 | 603 | 0/0/0/0 | 0 |
| x86-64 UID1000 | 7848 | 8175 | 9/4/3/0 | 0 |
| x86-64 root | 7017 | 7593 | 3/5/3/0 | 0 |

The x86 baseline reproduces 27 invalid-name observations, including empty
comm values. ARM baseline timing did not expose the race; its passing capture
is retained. Scheduling determines read counts. Both candidates require
positive concurrent observations, zero invalid records and a successful child
exit. The same fixture source, generated C and native init ELF run before
and after each architecture's kernel change.

After exec completes, a final pipe gate holds the child alive while the parent
warms up 32 observer cycles and measures another 200. Each cycle reads all
four records through all three mounts. All 18 ARM and 14 x86 live slab classes
remain exact in both credential cohorts; large allocation pages stay 79/79
on ARM and 205/205 on x86. This qualifies observer retention after exec
completes; it does not measure retention across the whole exec sequence.

Both candidates retain procself's 524 name/API checks, 156 selected-state
records, 1620 self/thread-self link calls and 84 stat identity/accounting
records. Native atomics, SIMD, TLS, JIT, page sizes, wide offsets and time64
runtime controls pass. ARM's final suite passes all three cases. The x86
exec receipt passes, but host disk exhaustion prevents writing the procself
receipt after its guest prints PASS. The partial receipt and aggregate error
remain published; a fresh same-kernel/source
[completion suite](../tests/linux-compat/results/2026-10-13/procexec-completion-x86_64.json)
passes procself and runtime. Earlier errno-macro compiler and pre-dumpability
permission-refusal fixture drafts remain in private artifacts. The earlier
ARM runtime ENOSPC [receipt](../tests/linux-compat/results/2026-10-13/procexec-draft-after-aarch64.json)
and [error log](../tests/linux-compat/results/2026-10-13/procexec-draft-after-aarch64.log)
remain separate from the successful final suite.

Kernels build in isolated worktrees at
`23dbc7b5d02c30bbe549fd5ecf29783c79c308af`, changing only two loader sources.
Replacing the candidate exec-loader body with the baseline body reproduces
the entire baseline kernel C, normalizing only unused-loop source-offset
identifiers. The allocation scanner retains 657/653 source files and 403/292
allocation sites for ARM/x86, with identical existing allowance refusals.
No allowances change. Eight host test files and the inventory check pass.

The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/procexec-audit.v)
checks receipt integrity, record outcomes, flat observer storage, existing
procself/runtime controls, source isolation, whole-kernel C scope and
independent [lifetime review](../tests/linux-compat/results/2026-10-13/procexec-lifetime-review.md).
Both failing assertion controls execute, including rejection of a passing
candidate log as baseline failure evidence.
[ARM evidence](../tests/linux-compat/results/2026-10-13/procexec-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/procexec-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/build/kernel/C/fixture/
source/ELF/ISO/capture/audit/review hashes. Captures include
[ARM baseline](../tests/linux-compat/results/2026-10-13/procexec-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/procexec-after-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/procexec-before-x86_64.log),
[x86 interrupted candidate](../tests/linux-compat/results/2026-10-13/procexec-after-x86_64.log)
and [x86 completion](../tests/linux-compat/results/2026-10-13/procexec-completion-x86_64.log).
Public inventory fingerprints use the committed parent plus this fix,
separately from the isolated semantic build inputs.

Sibling exec/exit, retirement races, full procfs ownership, complete exec
allocation retention, GNU/translated/ELF32 paths and application installation,
sandbox and portal requirements remain separate. The three broad section 15
acceptance gates remain open.

## Native statx requests and error precedence

The native statx adapter now validates the reserved request-mask bit,
mutually exclusive synchronization selectors and unknown flag bits before
touching a pathname, descriptor or output buffer. Refusals return EINVAL
and leave valid output untouched. Descriptor/flag/request words use their
lower 32 bits; metadata and pointers retain their native full width. Lookup
errors precede output-copy faults. Valid local metadata queries accept
AS_STAT, FORCE_SYNC, DONT_SYNC, NO_AUTOMOUNT, NOFOLLOW and EMPTY_PATH.
The underlying fstat/fstatat snapshots and 256-byte statx conversion remain
unchanged, with their existing ownership and stack scratch.

NULL with EMPTY_PATH uses the held descriptor path for nonnegative signed
descriptor words; NO_AUTOMOUNT and one sync selector may accompany it.
Negative descriptor words with NULL, including AT_FDCWD, retain EFAULT;
an invalid positive descriptor returns EBADF. NULL plus NOFOLLOW retains
EFAULT. Empty strings retain ordinary descriptor/current-directory lookup.
These distinctions are checked against actual Linux reference kernels,
alongside the [Linux 6.12 stat implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/stat.c)
and [flag definitions](https://raw.githubusercontent.com/torvalds/linux/v6.12/include/uapi/linux/fcntl.h).

| Calls per architecture, across root and UID/GID1000 | Baseline failures | Candidate failures | Linux reference failures |
| --- | ---: | ---: | ---: |
| 3240 raw metadata/argument-word calls | 1680 | 0 | 0 |
| 2880 raw invalid flag/mask/sync calls | 2880 | 0 | 0 |
| 64 raw lookup/output error calls | 14 | 0 | 0 |
| 30 musl wrapper calls | 18 | 0 | 0 |

Each architecture passes all 6214 calls on both Vinix and Linux 6.12.51.
The baseline fails 4592 calls. Three upper-word patterns, five request masks
and all 27 unknown single flag bits cover width/error behavior. Regular
files, directory-relative and absolute names, followed/unfollowed symlinks,
unlinked descriptors and pipes return actual fields matching native fstat.
Every call checks output canaries; refused calls retain the whole writable
output sentinel. File bytes and the preexisting cursor remain unchanged.

Both native candidates pass statx, open and runtime guest suites. The runtime
retains atomics, SIMD, TLS, JIT/page-size and wide-offset/time64 checks.
Each 200-cycle retention cohort issues 18 successful/refused statx calls
per cycle after warmup/grace, using stable descriptors. All 18 ARM and 14
x86 live slab classes remain exact; large pages stay 63/63 and 160/160 in
both credential groups. Allocation scans retain 658/654 source files and
403/292 sites, with identical existing allowance refusals. Eight host test
files and the native inventory check pass; no allowances change.

The maintained [V reference controller](../tests/linux-compat/statx-reference.v)
boots the exact same native musl probe ELF against caller-supplied Linux
kernels, using a V-generated newc archive and a small V exec wrapper. The
`--reference` argument selects the same semantic matrix while omitting
Vinix-specific slab reporting. Dated reference inputs are fixed-release
[Alpine 3.22.2 ARM](https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/netboot-3.22.2/vmlinuz-virt)
and [x86 kernels](https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/netboot-3.22.2/vmlinuz-virt).
Both boot logs identify Linux 6.12.51. Their hashes, QEMU binary/command,
wrapper source/C/ELF, unchanged probe ELF, archive and serial capture are
bound in the reference receipts. ARM uses macOS HVF and x86 uses TCG.

Kernels build in isolated worktrees at
`1940edfc04b77f7937ac03e54f4fe3870c23d787`, changing only linux_common.v.
Replacing the statx definition/prototype and removing three flag constants
reproduces the entire baseline kernel C, ignoring only unused-loop
source-offset identifiers. Independent [lifetime review](../tests/linux-compat/results/2026-10-13/statx-lifetime-review.md)
checks the unchanged descriptor owners and stack borrows against emitted C
and actual native/reference captures.

The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/statx-audit.v)
checks exact baseline failures, candidate/reference outcomes, output/metadata
controls, flat retention, whole-C scope, source isolation and receipt hashes.
Both negative assertion controls execute, including refusal of a passing
candidate log as baseline failure evidence.
[ARM evidence](../tests/linux-compat/results/2026-10-13/statx-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/statx-evidence-x86_64.json)
bind all 63 isolated inputs plus compiler/controller/kernel/C/source/ELF/ISO/
Linux kernel/wrapper/archive/QEMU/capture/build/audit/review hashes. Captures:
[ARM baseline](../tests/linux-compat/results/2026-10-13/statx-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/statx-after-aarch64.log),
[ARM Linux reference](../tests/linux-compat/results/2026-10-13/statx-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/statx-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/statx-after-x86_64.log),
[x86 Linux reference](../tests/linux-compat/results/2026-10-13/statx-reference-x86_64.log).
Initial compiler-alias, kernel-string and negative-NULL expectation drafts
remain in private artifacts with their actual failures. Public inventory
fingerprints use the committed parent plus this fix, separately from semantic
build inputs.

Remote synchronization, actual automount triggers, extended statx fields,
concurrent close/disk metadata, GNU wrappers and translated/ELF32 paths remain
separate. The three broad section 15 acceptance gates remain open.

## Native stat descriptor words and flag errors

The native fstat adapters now consume the lower 32 bits of the descriptor.
Both newfstatat adapters share descriptor/flag narrowing and validation before
pathname, descriptor or output access. Unknown flags return EINVAL and leave
writable output untouched. The 144-byte x86 and 128-byte ARM stat layouts,
checked output copies, stack scratch and VFS descriptor owners stay unchanged.

Linux 6.12 newfstatat accepts the sync selectors, including both bits together;
the statx adapter still rejects that pair. A NULL pathname selects a descriptor
only with exactly AT_EMPTY_PATH and a nonnegative signed descriptor word.
Adding NO_AUTOMOUNT, NOFOLLOW or a sync bit keeps NULL's EFAULT behavior.
Negative NULL descriptors, including AT_FDCWD, return EFAULT; invalid positive
NULL descriptors return EBADF. Empty strings retain ordinary descriptor and
current-directory behavior. The same native musl ELF verifies these distinctions
on actual Linux 6.12.51 reference boots, alongside the
[Linux stat implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/stat.c).

| Calls across root and UID/GID1000 | ARM calls | x86 calls | Baseline failures on each architecture | Candidate/reference failures |
| --- | ---: | ---: | ---: | ---: |
| Raw fstat descriptor/output controls | 108 | 108 | 48 | 0 |
| Successful raw newfstatat metadata/word queries | 696 | 696 | 280 | 0 |
| Unknown flags and NULL queries with extra flags | 2304 | 2304 | 1944 | 0 |
| Lookup/output and x86 legacy stat/lstat controls | 192 | 264 | 18 | 0 |
| Musl fstat/fstatat/stat/lstat controls | 24 | 24 | 2 | 0 |

Each candidate and Linux reference passes all 3324 ARM or 3396 x86 calls;
each baseline fails 2292. Three upper-word patterns and all 27 unknown flag
bits exercise narrowing and precedence. Regular, unfollowed-link, unlinked
and pipe descriptors return actual mode/inode/ownership/link-count/size/block
fields matching fstat. Absolute and directory-relative lookups follow or retain
symlinks as requested. Every call checks output canaries, and errors preserve
the writable stat sentinel. File contents and the held cursor remain exact.
The musl wrapper controls use non-NULL pathnames; NULL is qualified through
raw syscalls because this musl wrapper dereferences its pathname.

Both native candidates pass statabi, statx, open and runtime suites. Each
200-cycle retention cohort performs 21 successful/refused calls per cycle
after warmup and grace, with stable descriptors. All 18 ARM and 14 x86 live
slab classes stay exact, as do 63/63 ARM and 160/160 x86 large pages, in both
credential groups. Eight host test files and the generated inventory check
pass. Allocation scans retain 658/654 source files and 403/292 sites with
identical existing allowance refusals; no allowances change.

The maintained [V reference controller](../tests/linux-compat/statabi-reference.v)
boots the unchanged probe ELF with a caller-supplied Linux kernel. It freezes
inputs, compiles a V exec wrapper, creates a newc archive in V and records the
QEMU command/binary and wrapper/source/C/ELF/archive/serial hashes. The dated
inputs are the same fixed Alpine 3.22.2 kernels used by the statx reference:
both identify Linux 6.12.51. ARM uses macOS HVF; x86 uses TCG. `--reference`
runs the identical semantic matrix while skipping Vinix-specific slab reads.

The isolated kernel worktrees start at
`8fc078a86a6cd540c80ef667d9335afaf7c0230e`, with only the three stat adapter
sources changed. Replacing the two emitted adapter bodies and removing one
shared helper declaration/body restores the whole baseline kernel C, ignoring
only unused-loop source-offset identifiers. Statx, VFS snapshots and stat
conversion bodies remain exact. The independent
[lifetime review](../tests/linux-compat/results/2026-10-13/statabi-lifetime-review.md)
checks stack borrows and descriptor release against source, generated C and
actual native/Linux captures.

The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/statabi-audit.v)
requires exact baseline failures, candidate/reference outcomes, flat retention,
source isolation, whole-C scope and artifact hashes. A deliberately failing
assertion and a passing candidate supplied as baseline evidence both fail.
[ARM evidence](../tests/linux-compat/results/2026-10-13/statabi-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/statabi-evidence-x86_64.json)
bind all 63 isolated inputs and the compiler, controllers, source/C/kernel,
ELF/ISO, Linux kernel/wrapper/archive/QEMU, captures, builds, audit and review.
Captures:
[ARM baseline](../tests/linux-compat/results/2026-10-13/statabi-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/statabi-after-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/statabi-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/statabi-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/statabi-after-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/statabi-reference-x86_64.log).
The initial fixture's invalid musl NULL-wrapper control and its failed native
and Linux captures remain private. Public inventory fingerprints use the
committed parent plus this fix, separately from the isolated semantic builds.

Remote synchronization, automount triggers, concurrent close and disk metadata,
GNU wrappers and translated/ELF32 paths remain separate. The three broad
section 15 acceptance gates remain open.

## Native descriptor duplication errors and words

Native dup and dup3 now consume lower-32-bit descriptor words. The new dup3
adapter validates the lower-32-bit flags before descriptor lookup or target
replacement; only O_CLOEXEC is accepted. Unknown flags return EINVAL even with
an invalid source, target or equal descriptors. X86 dup2 compares normalized
words before deciding whether it is a self call: a valid self call returns
the descriptor and preserves its existing descriptor flags, while an invalid
self call returns EBADF. Dup3 equal words return EINVAL. Ordinary negative
libc targets now return EBADF. Successful copies clear or set CLOEXEC as
requested and share the existing open description.

| Calls across root and UID/GID1000 | ARM calls | x86 calls | ARM baseline failures | x86 baseline failures | Candidate/Linux failures |
| --- | ---: | ---: | ---: | ---: | ---: |
| Raw dup words and invalid descriptors | 48 | 48 | 24 | 24 | 0 |
| Successful raw dup3 queries | 648 | 648 | 576 | 576 | 0 |
| Unknown flags and refusal precedence | 744 | 744 | 558 | 558 | 0 |
| Valid-flag dup3 equality/descriptor errors | 168 | 168 | 60 | 60 | 0 |
| Native x86 dup2 self/replacement/errors | 0 | 276 | 0 | 192 | 0 |
| Musl dup/dup2/dup3 controls | 70 | 70 | 6 | 6 | 0 |

Each Vinix candidate and actual Linux 6.12.51 reference passes all 1678 ARM
or 1954 x86 calls. The baselines fail 1224 ARM and 1416 x86 calls. Independent
three-pattern upper words cover old descriptor, new descriptor and flags;
all 31 unknown single flag bits are refused. Sources include a regular file,
O_PATH file/directory, an unlinked file and both nonblocking pipe endpoints.
Metadata, status flags and requested descriptor flags agree with each source.
Ordinary file aliases move the shared cursor through the new descriptor and
restore it through the source. Every tested request starts with a distinct
seeded target: errors must retain its metadata/CLOEXEC/cursor and the source's
metadata/status/descriptor flags/cursor. File contents and queued AB data
remain exact after both credential cohorts.

Both native candidates pass dupabi, statabi, open and runtime guest suites.
Two 200-cycle retention cohorts perform 15 ARM or 21 x86 raw duplication calls
and three libc target seeds per cycle after warmup and grace. All 18 ARM and
14 x86 live slab classes remain exact, as do 68/68 ARM and 177/177 x86 large
pages, in both credential groups. Eight host test files and the inventory
check pass. Allocation scans retain 659/655 source files and 400/292 sites
with identical existing allowance refusals; no allowances change.

The maintained [V reference controller](../tests/linux-compat/dupabi-reference.v)
boots the exact same native musl ELF with caller-supplied Linux kernels. It
freezes the probe/kernel, compiles a V exec wrapper, creates the initramfs in
V and records wrapper/source/C/ELF/archive/QEMU/serial hashes. These dated
boots use the fixed Alpine 3.22.2 kernels from the statx reference; both logs
identify Linux 6.12.51. ARM uses macOS HVF; x86 uses TCG. `--reference` runs
the same semantic matrix while skipping Vinix-specific allocator reporting.
The native audit still requires all retention rows.

Isolated worktrees start at
`35f1a52fac949a772a5e331b6f3b8cd0b59376ee`, changing only the three native
adapter sources. Restoring the dup/dup2 adapter bodies and one dup3 dispatch,
then removing the new dup3 adapter declaration/body, restores the entire
baseline kernel C after normalizing only unused-loop source offsets.
Generic file duplication, descriptor lookup/refcounts and stat adapters
remain exact. The independent
[lifetime review](../tests/linux-compat/results/2026-10-13/dupabi-lifetime-review.md)
checks unchanged retained owners, stack metadata borrows and cleanup against
source, generated C and actual native/Linux captures.

The [assertion-enabled auditor](../tests/linux-compat/results/2026-10-13/dupabi-audit.v)
requires exact baseline failures, candidate/reference counts/errors, flat
retention, source isolation, whole-C scope and artifact hashes. Its deliberate
assertion and a passing candidate supplied as baseline evidence both fail.
[ARM evidence](../tests/linux-compat/results/2026-10-13/dupabi-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/dupabi-evidence-x86_64.json)
bind all 63 isolated inventory inputs and compiler/controllers/source/C/kernel,
ELF/ISO, Linux kernel/wrapper/archive/QEMU, serial/build/audit/review hashes.
Captures:
[ARM baseline](../tests/linux-compat/results/2026-10-13/dupabi-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/dupabi-after-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/dupabi-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/dupabi-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/dupabi-after-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/dupabi-reference-x86_64.log).
Initial 33-libc-control drafts remain in private artifacts with their real
baseline failures and Linux results. The final frozen probe adds ordinary
negative-target libc controls. Public inventory fingerprints use the committed
parent plus this fix, separately from the isolated semantic inputs.

Descriptor-limit pressure, actual exec inheritance, GNU wrappers and foreign
ABIs remain separate. This dated run left concurrent publication unqualified:
fdnum_dup published its new descriptor before finalizing its flags. Its
completed-call tests do not certify that path. The following qualification
addresses initialization before publication and selected concurrent observers;
actual exec inheritance remains separate. The three broad section 15 acceptance
gates remain open.

## Descriptor flags before publication

`fdnum_dup` now initializes the new descriptor's flags before transferring
ownership to the descriptor table. Once insertion releases the table lock,
another thread may close that descriptor or fork a copy of its flags. The
old successful path wrote through the descriptor pointer after insertion,
allowing a write after concurrent close and exposing copied source flags to
observers. The successful path now uses only the returned descriptor number.
Failure cleanup, source references, handle references and allocations are
unchanged.

Native musl probes run root and UID/GID1000 cohorts on both architectures.
Each cohort performs 128 calls and 16 actual fork snapshots for each of dup,
dup2, dup3 without CLOEXEC, dup3 with CLOEXEC, F_DUPFD and F_DUPFD_CLOEXEC.
The source starts with the opposite descriptor flag to the expected result;
an observer accepts only the requested flags, or EBADF during intentional
holes for dynamic allocation. Completed-call controls require the same
flags before allowing the worker to advance. Each run contains 1536 duplicate
calls and 192 fork checks across both credentials.

Production kernels contain no test hook. A maintained V instrumenter creates
private kernel copies with 32 reschedules immediately after inserting target
63. Both baseline and candidate get the same window. Both baseline credentials
fail all six visibility phases, including bad fork snapshots, while producer
and completed-call controls pass. Baselines intentionally skip close/reuse
after those failures. Both corrected production and instrumented candidates
pass the visibility, fork and close/reuse controls. The same native probe ELF
also passes on actual Linux 6.12.51 for each architecture; reference boots
omit only Vinix allocator reporting.

Each candidate and Linux cohort runs 200 close/reuse rounds: observe source
identity at 63, close it, immediately seed 64 with CLOEXEC, wait for duplicate
completion and check the return value plus the sentinel's inode, mode, size,
cursor and flags. After observing worker completion, the probe takes a fresh
metadata sample before deciding whether publication succeeded. This avoids
rejecting a stale sample taken just before the worker completed. Final source
and seed bytes, cursors and parent descriptor flags remain exact. Instrumented
receipts must show an unfinished producer immediately before close in both
credentials. That timing counter is an observed load, not synchronization
that proves the close itself happened before syscall return.

After the concurrent phases, two sequential 200-cycle storage cohorts retain
all 18 ARM/14 x86 live slab classes and 63/160 large pages exactly. These measurements
qualify sequential retention; they do not claim whole-concurrency retention.
Both production kernels also pass dupabi, open and runtime guest suites,
including native atomics, SIMD, TLS, JIT and page-size checks. Eight host test
files pass. Allocation scanning still reports the existing allowance failures:
659 ARM/655 x86 source files and 400/292 sites are unchanged. This patch adds
no allocation, free, reference-count or locking operations.

Whole generated production and instrumented kernel C restores by replacing
only `file__fdnum_dup`, ignoring only compiler-generated unused-return names.
Instrumented versus production C adds that function's scheduling window and,
on x86, relocates one byte-identical block of 48 literal mmap macros because
of the added sched import. After checking that block, the remaining C matches
with only the function restored. The source and generated-C lifetime review checks ownership transfer,
failure cleanup, source retention, explicit stack worker state and joins.
The probe compiler is pinned separately from the frozen kernel/controller
compiler, and a reconstruction must reproduce the exact tested C and ELF.
Initial stale-sample probe failures on Vinix and Linux and interrupted x86
timing captures remain private; published receipts use the corrected frozen
probe with 16 fork samples per method and a 600-second cohort alarm.

The [V audit](../tests/linux-compat/results/2026-10-13/duppublish-audit.v)
requires complete credential/method rows, real baseline failures, production
and instrumented candidate verdicts, Linux semantics, observed scheduling
overlap, flat storage, whole-C scope and exact artifact hashes. Both a deliberate
assertion and passing evidence supplied as a baseline must fail.
[ARM evidence](../tests/linux-compat/results/2026-10-13/duppublish-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/duppublish-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/source/C/kernel, native
ELF/ISO, Linux kernel/wrapper/archive/QEMU, serial/build/audit/review hashes.
Captures:
[ARM baseline QA](../tests/linux-compat/results/2026-10-13/duppublish-before-qa-aarch64.log),
[ARM production](../tests/linux-compat/results/2026-10-13/duppublish-after-aarch64.log),
[ARM candidate QA](../tests/linux-compat/results/2026-10-13/duppublish-after-qa-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/duppublish-reference-aarch64.log),
[x86 baseline QA](../tests/linux-compat/results/2026-10-13/duppublish-before-qa-x86_64.log),
[x86 production](../tests/linux-compat/results/2026-10-13/duppublish-after-x86_64.log),
[x86 candidate QA](../tests/linux-compat/results/2026-10-13/duppublish-after-qa-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/duppublish-reference-x86_64.log).
Public inventory fingerprints use the committed parent plus this fix,
separately from the isolated semantic inputs.

Actual exec inheritance, concurrent F_SETFD or source close, descriptor-limit
pressure, GNU wrappers and translated/ELF32 paths remain separate. The three
broad section 15 acceptance gates remain open.

## O_PATH fcntl command refusals

The shared fcntl implementation now checks pathname-only access immediately
after retaining the descriptor/open description. Commands outside Linux's
O_PATH allowlist return EBADF before MAC checks, lock/resource operations,
status/ownership changes or user-pointer copies. The new branch releases the
paired FD/Handle hold exactly once before returning; it adds no allocation,
stored pointer or lock. It follows [Linux's command gate](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/fcntl.c).

The five implemented allowed operations remain F_DUPFD, F_DUPFD_CLOEXEC,
F_GETFD, F_SETFD and F_GETFL. Linux's F_DUPFD_QUERY/F_CREATED_QUERY command
numbers also pass the access gate, but their underlying implementation remains
unavailable (EINVAL) and excluded from this qualified subset.

| Root and UID/GID1000 calls | Calls per architecture | Baseline failures | Candidate/Linux failures |
| --- | ---: | ---: | ---: |
| Refused O_PATH commands and unchanged state/buffers | 7776 | 7452 | 0 |
| Allowed getters, descriptor flags and real aliases | 1296 | 0 | 0 |
| Invalid sources, musl and ordinary file controls | 1740 | 864 | 0 |
| Total | 10812 | 8316 | 0 |

Each candidate and actual Linux 6.12.51 reference passes all 10,812 calls with
byte-identical native musl C and ELF. The six O_PATH source classes are a
readable regular file, root-private regular file, directory, FIFO, unfollowed
symlink and unlinked regular file. Every class has original, ordinary dup and
F_DUPFD_CLOEXEC descriptors. Three native word controls independently vary
descriptor and command upper bits. Twenty-four denied commands include status,
owner/signal, classic/OFD lock, pipe capacity, seals, leases, notifications,
write-life hints and unknown commands. NULL, real stack and invalid-address
arguments require EBADF without touching the whole canary-wrapped packet.
Metadata, descriptor flags and status remain unchanged.

Allowed getters/setters preserve the pathname status and metadata; duplication
minima 0/63/127 create actual aliases with the requested CLOEXEC. Each temporary
alias closes, and descriptor flag setters restore the prior flags. Invalid
sources retain EBADF, including pointer commands. Musl controls agree. An
ordinary open description still supports real NONBLOCK changes, reads exact
bytes, returns EFAULT for NULL pointer commands and EINVAL for unknown commands.
The ordinary-user child cannot reopen the private pathname for reading while
its inherited O_PATH handles still support metadata/allowed operations.

After 32 warmup cycles and settling, each credential performs 200 cycles of
two valid aliases and four refused commands. All 18 ARM/14 x86 slab classes
stay flat, with 63/63 ARM and 160/160 x86 large pages. Both production kernels
also pass fcntlabi, open and runtime suites; eight host test files pass.
Allocation scanning keeps the same 659/655 source files, 400/292 allocation
sites and existing allowance failures. The prior fcntlabi candidate kernels,
C and build logs are reused as the exact baseline. The whole-C comparison
restores the original by removing the refusal and two command constant
declarations; only local return temporary numbering and unused-return source
offsets require canonicalization. Everything outside fcntl remains identical.

Independent lifetime review checks paired release, no later descriptor access,
unchanged allowed cleanup, the actual emitted fixture's ten explicit stack
allocations, synchronous pointer borrows and temporary alias/status/observer
cleanup. Initial setup failures still rely on process-exit descriptor cleanup.

The [V audit](../tests/linux-compat/results/2026-10-13/fcntlpath-audit.v)
requires complete exact counts, baseline failures, candidate/reference verdicts,
flat retention, whole-C scope and artifact identities; deliberate assertion
and passing-as-baseline controls must fail. [ARM evidence](../tests/linux-compat/results/2026-10-13/fcntlpath-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/fcntlpath-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/source/C/kernel/native
ELF/ISO, Linux kernel/wrapper/archive/QEMU, serial/build/audit/review hashes.
Captures: [ARM baseline](../tests/linux-compat/results/2026-10-13/fcntlpath-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/fcntlpath-after-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/fcntlpath-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/fcntlpath-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/fcntlpath-after-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/fcntlpath-reference-x86_64.log).
Public inventory fingerprints use the committed parent plus the owned fix;
unrelated shared-checkout edits are excluded.

Descriptor-query extensions, full ordinary advisory/OFD lock/status/ownership/
seal semantics, concurrent close or flag changes, GNU wrappers and foreign
ABIs remain separate. The three broad section 15 gates remain open.

## Native fcntl words and duplicate minima

Both native tables now route fcntl through an adapter that consumes lower-32-bit
descriptor and command words. The third argument depends on the command:
duplicate minima use signed int32 values; supported scalar setters consume
their lower int word; pointer and unknown-command arguments retain all 64 bits.
This follows the native entry and command conversions in
[Linux fcntl](https://raw.githubusercontent.com/torvalds/linux/v6.12/fs/fcntl.c).

F_DUPFD and F_DUPFD_CLOEXEC minima must fit the current soft descriptor limit.
An invalid minimum returns EINVAL after validating the source descriptor, so
an invalid source retains EBADF. This precheck takes and releases a paired
temporary descriptor/handle hold before returning the scalar error. A valid
request with an exhausted table still returns EMFILE. The generic fcntl and
duplication helpers remain unchanged: native dup must continue returning
EMFILE when the soft limit is zero, whereas fcntl's minimum zero is invalid
at that limit. The adapter adds no allocation or stored pointer and uses the
existing lookup lock without nesting another lock.

| Calls across root and UID/GID1000 | Calls per architecture | Baseline failures | Candidate/Linux failures |
| --- | ---: | ---: | ---: |
| Descriptor/status getters | 648 | 576 | 0 |
| Duplicate minima, alias and refusal state | 5184 | 4272 | 0 |
| Descriptor/status/signal setters and pipe identity size | 2700 | 2360 | 0 |
| Full-width flock pointer transport and NULL errors | 72 | 64 | 0 |
| Invalid sources/commands, libc and limit exhaustion | 324 | 76 | 0 |
| Total | 8928 | 7348 | 0 |

Every Vinix candidate and actual Linux 6.12.51 reference passes all 8,928 calls
using the same native musl ELF. Three independent patterns vary each upper
word. Under soft limit 128, minima 0/63/127 succeed, while 128/129, INT_MAX,
INT_MIN and -1 return EINVAL. Six held source classes cover a regular file,
O_PATH file/directory, an unlinked file and both nonblocking pipe endpoints.
Successful aliases have the requested CLOEXEC flag and real source metadata
and status. Regular aliases move the shared offset and restore it through
the source. Errors preserve the source and a distinct seeded descriptor 64,
including metadata, flags and offsets. Libc invalid-minimum controls agree.

Setter checks require exact resulting descriptor flags and selected
APPEND/NONBLOCK status changes. Signals 0/1/64 succeed; 65 and negative int
words return EINVAL without changing the previous signal. Pipe size requests
use each kernel's actual current capacity and retain that capacity and queued
data. Real stack pointers above 32 bits reach F_GETLK, preserve surrounding
canaries and return unlocked type; NULL returns EFAULT. Those controls qualify
pointer transport, rather than full advisory-lock semantics. Full-table and
zero-soft-limit controls distinguish EINVAL, EBADF and EMFILE while retaining
the descriptors that were open before the lower limit. Final source/seed
bytes, parent descriptor flags, restored signals/offsets and queued AB remain
exact.

Both production kernels also pass dupabi, duppublish, open and runtime suites.
Eight host test files pass. After 32 warmup cycles and settling, each native
200-cycle retention cohort issues two high-word aliases and four invalid-minimum
requests per cycle. All 18 ARM/14 x86 live slab classes and 68/177 large pages
stay flat for each credential. Allocation scanning retains the existing
allowance failures: 659/655 source files and 400/292 sites remain unchanged.

The entire candidate kernel C restores by replacing one native fcntl dispatch
assignment, removing the new adapter body/declaration and ignoring only
compiler-generated unused-return source offsets. Generic fcntl, descriptor
lookup/creation/duplication, native dup/dup3 and the lock helper are unchanged.
The new bad-minimum lookup releases its paired hold before EINVAL and never
uses the descriptor afterward. Independent source/C/native/reference lifetime
review checks that release and the probe's explicit stack storage, temporary
aliases, cursor restoration and pressure cleanup. Source, generated C and ELF
remain identical across baseline, candidate and reference probe runs.

The [V audit](../tests/linux-compat/results/2026-10-13/fcntlabi-audit.v)
requires complete counts, precise baseline failures, candidate/reference
verdicts, state controls, flat retention, scope and all artifact hashes. Its
deliberate assertion and passing evidence supplied as a baseline both fail.
[ARM evidence](../tests/linux-compat/results/2026-10-13/fcntlabi-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/fcntlabi-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/source/C/kernel, native
ELF/ISO, Linux kernel/wrapper/archive/QEMU, serial/build/audit/review hashes.
Captures:
[ARM baseline](../tests/linux-compat/results/2026-10-13/fcntlabi-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/fcntlabi-after-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/fcntlabi-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/fcntlabi-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/fcntlabi-after-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/fcntlabi-reference-x86_64.log).
Initial disk-space failures remain private and do not qualify the change.
Completed older ISO/firmware artifacts were losslessly archived with SHA
manifests; restoring gzip copies reproduces their original bytes. Public
inventory fingerprints use the committed parent plus this fix, separately
from the isolated semantic inputs.

O_PATH disallowed commands, full status-flag/ownership/sealing behavior,
dynamic pipe resizing, full lock semantics/concurrency, concurrent RLIMIT
changes, GNU wrappers and translated/ELF32 paths remain separate. The three
broad section 15 acceptance gates remain open.

## Fcntl duplicate-description queries

F_DUPFD_QUERY now compares the retained open descriptions behind two descriptors.
The result is 1 for actual aliases and 0 for distinct descriptions, including
separate opens of the same inode. Either invalid descriptor returns EBADF.
The native adapter consumes the comparison descriptor's lower 32 bits alongside
the existing descriptor/command decoding. It follows the [stable Linux query](https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux/+/refs/tags/v6.12.38/fs/fcntl.c).
Actual Linux 6.12.51 reference boots confirm these errors; the original 6.12
implementation returned 0 for an invalid comparison descriptor.

The existing primary lookup retains its FD and Handle. A successful secondary
lookup retains another paired hold, and a scalar address comparison completes
before releasing the secondary and primary holds. Failed secondary lookup
releases the primary before EBADF. The descriptor-table lock ends at each
lookup; no lock is held across either release. The query allocates no object,
stores no pointer and performs no resource operation.

V's ordinary Handle-pointer equality initially emitted full structural equality
after an address fast path, copying Handle records and reading mutable arrays.
The implementation now explicitly compares void pointers. Whole generated-C
and independent lifetime checks require that direct comparison and forbid
Handle copies, structural equality or array traversal in the new branch.
The initial structural build and fixed-index fixture setup failures are retained
as private diagnostics and excluded from qualified evidence.

| Root and UID/GID1000 controls | Calls per architecture | Baseline failures | Candidate/Linux failures |
| --- | ---: | ---: | ---: |
| Alias versus separate-description matrix | 6144 | 6144 | 0 |
| Invalid descriptors, word and soft-limit errors | 1024 | 848 | 0 |
| Musl, balanced directory references and close/replacement | 1912 | 1904 | 0 |
| Total | 9080 | 8896 | 0 |

Both native candidates and actual Linux 6.12.51 references pass all 9080 controls
with byte-identical native musl C and ELF. Eight source classes each have an
original, ordinary duplicate and CLOEXEC duplicate: regular file, root-private
O_PATH file, O_PATH directory/FIFO/unfollowed symlink, unlinked regular file and
both nonblocking pipe endpoints. Separate opens of the first six classes have
equal selected inode metadata and distinct descriptions; a second pipe has
independent endpoints. Four controls independently vary source, command and
comparison descriptor upper words. Musl calls agree with raw native calls.

The maintained fixture removes one trailing blank line from the exact frozen
tested source. Regenerating both module previews retains byte-identical executed
C; receipts keep the actual frozen-source hash, and the audit separately pins
the maintained source and permits only that exact EOF change.

Held descriptors 64/65 stay usable above lowered soft limits 8 and 0. Invalid
source/target words, closed descriptors and real close/replacement of descriptor
66 require exact outcomes. A directory cohort balances live reference counts
with temporary aliases 68–71 and matching flags while retaining separate opens.
The parent creates the descriptions before fork; both credential children query
the inherited aliases. Every temporary alias closes, and limits restore before
further allocation. All held metadata, descriptor/status flags and cursors stay
exact. A real alias moves its source's cursor while an independent open retains
its own position; the shared cursor restores. File bytes and queued AB/CD remain
unchanged before the parent closes every test descriptor.

After 32 warmup cycles and settling, each credential runs 200 cycles of true,
false, closed-target and negative-target queries. All 18 ARM/14 x86 live slab
classes and 73/194 large pages stay flat. Both production kernels also pass
fcntlpath, open and runtime; eight host test files pass. Allocation scans retain
659/655 source files, 400/292 sites and the same existing allowance failures.

The exact previous fcntlpath candidate kernels, C and build logs serve as the
baseline. Whole C restores by removing the new query branch and its adapter
classification, canonicalizing only compiler temporary names inside fcntl and
unused-return source offsets elsewhere. All remaining code stays identical.
Independent lifetime review checks both releases, the no-later-pointer-use
rule, the eight explicit fixture stack allocations, synchronous borrows and
alias/limit/cursor/observer cleanup. Fatal setup paths rely on process exit.

The [V audit](../tests/linux-compat/results/2026-10-13/fcntlquery-audit.v)
requires exact counts, complete baseline failures, candidate/reference verdicts,
state/retention controls, C scope and artifact identity. Assertion and
passing-as-baseline negative controls must fail. [ARM evidence](../tests/linux-compat/results/2026-10-13/fcntlquery-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/fcntlquery-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/source/C/kernel/native ELF/
ISO, Linux kernel/wrapper/archive/QEMU and serial/build/audit/review hashes.
Captures: [ARM baseline](../tests/linux-compat/results/2026-10-13/fcntlquery-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/fcntlquery-after-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/fcntlquery-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/fcntlquery-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/fcntlquery-after-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/fcntlquery-reference-x86_64.log).
Completed older ISO/firmware files were losslessly archived with verified SHA
manifests; gzip restoration reproduces their original bytes. Public inventory
fingerprints use the committed parent plus this fix, separately from the
isolated semantic inputs and unrelated shared-checkout changes.

F_CREATED_QUERY now has separate receipts below. Concurrent close/table-sharing
races, full ordinary fcntl semantics, GNU wrappers and translated/ELF32 paths
remain separate. The three broad section 15 acceptance gates remain open.

### Fcntl file creation queries

`F_CREATED_QUERY` now returns the actual creation result for the queried open
description. The open path already distinguishes the creator from an existing
file or a competing creator's fallback. It passes that result into the private
new Handle before descriptor publication. The immutable bit occupies existing
padding; ordinary duplication and fork retain the shared description. Generic
resource descriptions default to false. The query ignores its argument, reads
the retained bit and releases its paired descriptor/Handle lookup once.
Invalid descriptors still return EBADF, including on O_PATH-compatible paths.
The behavior follows the [Linux implementation](https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux/+/refs/tags/v6.12.38/fs/fcntl.c).

| Root and UID/GID 1000 controls | Calls per architecture | Baseline failures | Candidate/Linux failures |
| --- | ---: | ---: | ---: |
| Creation-state and native-word matrix | 2304 | 2304 | 0 |
| Invalid descriptors and held aliases above soft limits | 480 | 192 | 0 |
| Musl valid/invalid description queries | 832 | 768 | 0 |
| Real close/replacement/reuse | 192 | 96 | 0 |
| Total | 3808 | 3360 | 0 |

Both production candidates and actual Linux 6.12.51 references pass all 3808
controls using byte-identical native musl C and ELF. Each credential uses 16
description classes with original, ordinary duplicate and CLOEXEC duplicate:
inherited new/existing files; child-owned new, O_CREAT reopen, ordinary reopen
and O_TRUNC reopen; O_PATH with ignored creation/truncation flags; followed
existing and initially dangling symlinks; O_PATH link and directory; an unlinked
created file and its new replacement; and both nonblocking pipe endpoints.
The ordinary child clears supplementary groups and sets UID/GID 1000 before
creating its own files in its owned directory. The parent closes its inherited
descriptors after both credential children exit.

Eight full-width arguments include zero, all-ones, sign/high-word values and an
invalid high address. None is dereferenced or validated. Independent source and
command upper words retain native low-word behavior. Aliases 64/65 remain usable
above soft limits eight and zero; the limit restores before further allocation.
Descriptor 66 moves from closed to a creator alias, to an existing-file alias
and back to closed, requiring exact boolean or EBADF results at each step.
An exclusive reopen reports EEXIST, and O_PATH cannot create a missing name.
Reopened descriptions of one inode retain different creation results.

All 50 held metadata/descriptor/status/cursor snapshots remain exact. An alias
moves its creator's cursor while an independent reopen retains its own position;
the shared cursor restores. Created/reopened/unlinked/replacement file bytes
and queued AB remain exact. All normal-path aliases, observer and test
descriptors close. Fatal setup paths rely on process-exit cleanup. The fixture
uses seven explicit stack allocations and has no hidden heap allocations or
fixed-array indexing helpers in its executed C; synchronous callees retain none
of those borrows.

After warmup and settling, each credential runs 200 cycles querying true, false
and invalid descriptions. All 18 ARM/14 x86 live slab classes and 68/177 large
pages stay flat. Both kernels also pass fcntlquery, fcntlpath, open and runtime;
eight host test files pass. Allocation scans retain 659/655 source files and
400/292 sites, with the same existing allowance failures and no new sites.

The baseline reuses the exact previous F_DUPFD_QUERY production kernels, C and
build logs, after verifying every isolated kernel input against that qualified
source inventory. Whole C restores by removing only the creation-bit field,
the open constructor's parameter/prototype/assignment, its caller's argument
and the new query branch. Only compiler temporary names inside fcntl and source
offsets in unused variable names elsewhere are canonicalized. The rest stays identical.
Independent lifetime review checks publication, default initialization,
dup/fork ownership, the paired query release, stack borrows and cleanup.
Foreign root VFS edits stay outside both isolated semantic builds and this
commit; public inventory fingerprints use the committed parent plus this fix.

The [V audit](../tests/linux-compat/results/2026-10-13/fcntlcreated-audit.v)
requires exact baseline failures and candidate/reference counts, complete guest
verdicts, source/C/ELF identity, state/retention controls, whole-C scope and
independent review hashes. Assertion and passing-as-baseline negative controls
must fail. [ARM evidence](../tests/linux-compat/results/2026-10-13/fcntlcreated-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/fcntlcreated-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/source/C/kernel/native
ELF/ISO, Linux kernel/wrapper/archive/QEMU and serial/build/audit/review hashes.
Captures: [ARM baseline](../tests/linux-compat/results/2026-10-13/fcntlcreated-before-aarch64.log),
[ARM candidate](../tests/linux-compat/results/2026-10-13/fcntlcreated-after-aarch64.log),
[ARM Linux](../tests/linux-compat/results/2026-10-13/fcntlcreated-reference-aarch64.log),
[x86 baseline](../tests/linux-compat/results/2026-10-13/fcntlcreated-before-x86_64.log),
[x86 candidate](../tests/linux-compat/results/2026-10-13/fcntlcreated-after-x86_64.log),
[x86 Linux](../tests/linux-compat/results/2026-10-13/fcntlcreated-reference-x86_64.log).
Older completed ISO/firmware files were losslessly archived with verified SHA
manifests; gzip restoration reproduces their original bytes.

Concurrent creators/close/table sharing, GNU wrappers, O_TMPFILE, overlay/disk
creation, translated/ELF32 paths and full ordinary fcntl semantics remain
separate. The three broad section 15 acceptance gates remain open.

### Fcntl synchronization status preservation

`F_SETFL` preserves the `O_SYNC` and `O_DSYNC` status selected at open. Previously
those bits were mutable, so a request to set nonblocking mode could silently
remove synchronized-write status, and an ordinary open could acquire it through
fcntl. Linux excludes both from its [mutable status mask](https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux/+/refs/tags/v6.12.38/fs/fcntl.c).
Vinix now limits its implemented mutable mask to append and nonblocking bits.
Access and descriptor flags retain their separate behavior.

| Root and UID/GID 1000 controls | Calls per architecture | Baseline failures | Candidate/Linux failures |
| --- | ---: | ---: | ---: |
| Native status/alias/argument matrix | 1728 | 1176 | 0 |
| Bad descriptors and O_PATH refusals | 640 | 0 | 0 |
| Musl setter controls | 592 | 294 | 0 |
| Held descriptors above soft limits and replacement | 512 | 264 | 0 |
| Total | 3472 | 1734 | 0 |

Both strengthened native candidates and actual Linux 6.12.51 references pass
all 3472 controls with byte-identical probe C and native musl ELF. Nine source
classes each have an original, ordinary duplicate and CLOEXEC duplicate:
readonly regular file, writeonly/RDWR O_DSYNC files, RDWR O_SYNC file, ordinary
RDWR reopen, O_SYNC directory, both pipe endpoints and an unlinked O_SYNC file.
Six O_PATH aliases cover regular and directory descriptions. Held 64/65 retain
the synchronized and ordinary RDWR descriptions. The parent opens and aliases
before fork; one child clears supplementary groups and sets UID/GID 1000.

Each credential explicitly verifies the expected initial synchronization and
access modes on all 35 held descriptors before any setter. The O_PATH assertion
uses `O_PATH & O_ACCMODE`, matching the supplied libc mask. Eight requests mix
zero, O_DSYNC, O_SYNC, append/nonblocking and ignored access/creation/descriptor
flags. Four controls independently vary descriptor, command and argument upper
words; musl setters agree with raw native calls. Every status change is visible
through the description's aliases, while independent opens of the same inode
retain their own status. Requests cannot add or remove synchronization status.

All 35 metadata/descriptor/cursor snapshots remain exact during each request,
and all flags restore after each successful setter. Invalid and O_PATH sources
return EBADF without state changes. Existing 64/65 remain usable above soft
limits eight and zero; limits restore before further allocation. Replacement 66
moves through closed, synchronized alias, ordinary alias and closed states, with
a separate valid snapshot for the replacement. A real alias moves its original
cursor while an independent reopen stays at position three; the shared cursor
restores. Parent-side file bytes, original AB and descriptor flags remain exact
before all held descriptors close. Fatal setup paths rely on process exit.

The probe has seven explicit stack allocations, no hidden heap allocations or
fixed-array indexing helpers in executed C, and no retained synchronous borrows.
After warmup and settling, each credential runs 200 cycles of synchronized and
ordinary status changes/restores plus invalid-source refusal. All 18 ARM/14 x86
live slab classes and 68/177 large pages remain flat. This measures status
operations; it does not establish power-loss durability or creation-time
allocation behavior. Eight host test files pass. Allocation scans retain
659/655 files and 400/292 sites with unchanged existing allowance failures.

The kernel baseline reuses the previous qualified production kernels, C and
build logs after verifying every isolated kernel input. Complete generated C
is byte-identical after restoring the single mutable-mask macro; no function,
ownership, locking, adapter or constructor code changes. Independent lifetime
review checks the unchanged kernel ownership and new fixture stack borrows,
status restoration, observer/alias/replacement cleanup and parent waits/closes.

Five guest cases pass on each exact candidate kernel: fcntlsync, fcntlabi,
fcntlpath, open and runtime. [The V composer](../tests/linux-compat/results/2026-10-13/fcntlsync-compose.v)
combines the fresh strengthened sync run with successful unchanged related
cases, verifying kernel/source/ELF/ISO/C/serial identity and recording the original
state for every case. ARM fcntlpath uses the successful retry after its first ISO
build ran out of disk space. Immutable ISO hardlinks preserve the same bytes
without duplicating their storage. Successful unrelated probes were not rerun.
Provisional sync probes, the failed O_PATH access-mask assumption and failed ISO
setup remain diagnostics and are excluded from qualified case selection.
Original/fresh/retry receipts and captures remain visible in the evidence.
Completed historical builds, ISO and firmware files were losslessly compressed
with verified SHA manifests; restoration reproduces the original bytes.

The [V audit](../tests/linux-compat/results/2026-10-13/fcntlsync-audit.v)
requires exact initial checks, baseline failures, candidate/reference counts,
state/retention results, artifact identity, macro-only kernel C scope,
successful-case provenance and independent review hashes. Its assertion and
passing-as-baseline negative controls must fail. [ARM evidence](../tests/linux-compat/results/2026-10-13/fcntlsync-evidence-aarch64.json)
and [x86 evidence](../tests/linux-compat/results/2026-10-13/fcntlsync-evidence-x86_64.json)
bind all 63 isolated inputs and compiler/controller/source/C/kernel/native
ELF/ISO, Linux kernel/wrapper/archive/QEMU and serial/build/composer/audit/review
hashes. Public inventory uses committed inputs plus this fix, excluding other
sessions' dirty kernel inputs.

Direct/noatime/async flags, append-only permissions, physical durability,
concurrent status changes, GNU wrappers and translated/ELF32 paths remain
separate. The three broad section 15 acceptance gates remain open.

## Native open-description record locks

The former OFD shortcut reused process-owned POSIX locks. Separate opens in
one process could silently replace each other's locks, closing any descriptor
could discard OFD locks, and queries omitted the correct owner identity.
Record locks now distinguish process ownership from the retained open
description. POSIX and OFD locks share a conflict domain; flock remains
independent. Final Handle disposal removes its OFD/flock entries before the
resource and Handle are freed. Closing an alias, unrelated open or a parent
after fork keeps locks while another owner reference survives.

The Linux reference also caught the special F_OFD_GETLK/F_UNLCK operation:
it queries this description's own overlapping reader/writer locks. It does
not unlock them. POSIX F_GETLK/F_UNLCK retains EINVAL. This follows the
[pinned Linux 6.12.51 implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/locks.c),
and the actual reference runs exercise both behaviors.

The maintained V fixture performs 464 checks per architecture as root and
UID/GID1000. Each cohort has 74 ownership/alias/flock controls, 44 range
controls, 94 error/query controls, 12 blocking controls and eight fork controls.
Both libc and raw native fcntl calls retain full-width flock pointers while
upper descriptor/command words narrow as Linux C ints. Baselines fail 152 of
424 completed checks; blocking/fork controls are skipped after those failures.
Final candidates and actual Linux 6.12.51 references pass the identical native
C/ELF. GNU wrappers and foreign ABIs are not part of these native musl runs.

Tests cover compatible readers, upgrade conflicts, own/other-owner queries,
POSIX PID versus OFD -1, unchanged no-conflict fields, partial unlocks, bridge
coalescing, write-to-read conversion, negative lengths, CUR/END normalization,
ranges above 4 GiB and length-zero unbounded ranges. Invalid pointers, nonzero
OFD PID, type/whence/range errors and descriptor/access refusals are checked.
File bytes remain intact. A child keeps the inherited description after its
parent closes all aliases, and child exit releases the final lock. Three
independent child opens per credential are observed sleeping in procfs; unlock
and downgrade wake eligible waiters, while non-restarting SIGUSR1 returns EINTR.

Two 200-cycle cohorts repeatedly acquire/split/merge locks, refuse conflicts,
close aliases and release the final description. All 18 ARM/14 x86 slab classes
stay flat, as do 63/63 ARM and 160/160 x86 large pages in each cohort.
Production kernel C changes only the reviewed
lock functions, newly emitted array trim helper and blank separators. The new
own-query branch copies scalar records under the table lock. Replacement
arrays are freed, have noslices, and contain stack value copies. Conflict
records leave the lock as values, and usercopy/PID translation stay outside it.
The fixture emits 14 explicit allocas with no hidden heap/index helpers. Both
allocation scans complete with unchanged 400 ARM/292 x86 sites; preexisting
allowance failures remain visible. An independent
[lifetime review](../tests/linux-compat/results/2026-10-13/ofdlocks-lifetime-review.md)
binds final sources, generated C and measured captures.

Initial probes exposed a UID1000 fixture setup error, host ENOSPC interruptions
and an incorrect Linux unlock-query expectation. Their receipts/captures remain
[diagnostics](../tests/linux-compat/results/2026-10-13/ofdlocks-diagnostic-reference-aarch64.log).
Final kernels were rebuilt after the oracle correction, and all five cases
(ofdlocks, fcntlpath, fcntlsync, open and runtime) ran on the final kernel hashes;
these final receipts are ordinary controller executions. Eight host test files
pass. The V audit verifies matching baseline/candidate/reference source/C/ELF,
real receipt/ISO/kernel identities, exact counts, flat retention and all 64
dispatch/lock source inputs; deliberately failing assertions and passing-as-
baseline controls must fail. Completed private artifacts were losslessly
compressed with verified SHA manifests to recover host space.

- [AArch64 final receipt](../tests/linux-compat/results/2026-10-13/ofdlocks-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-13/ofdlocks-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-13/ofdlocks-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-13/ofdlocks-evidence-aarch64.json).
- [x86-64 final receipt](../tests/linux-compat/results/2026-10-13/ofdlocks-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-13/ofdlocks-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-13/ofdlocks-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-13/ofdlocks-evidence-x86_64.json).
- [Audit source](../tests/linux-compat/results/2026-10-13/ofdlocks-audit.v) and [verdict](../tests/linux-compat/results/2026-10-13/ofdlocks-audit.log); baseline captures, build logs, allocation scans, scope and host checks sit beside these files.

Disk/network/overlay filesystems, signed maximum-end boundaries, POSIX deadlock
detection and concurrent close races, fairness, cancellation/descriptor pressure
and GNU/translated/ELF32 paths remain unqualified. The three broad section 15
semantics/installation/foreign-runtime gates stay open.

## Native signed record-lock ranges

The record-lock normalizer checked an exclusive end against INT64_MAX and
rejected Linux's last valid byte. A lock starting at INT64_MAX with length 1,
or starting one byte earlier with length 2, incorrectly returned EOVERFLOW.
Normalization now validates the inclusive last byte using length-1. An
inclusive INT64_MAX end maps to the existing unbounded sentinel, matching
Linux query output l_len 0; a range ending one byte earlier remains finite.
The endpoint calculation avoids signed overflow. The
[pinned Linux 6.12.51 normalizer/query implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/locks.c)
and actual same-ELF references establish these semantics.

For regular files, POSIX F_GETLK checks query kind before normalization.
OFD queries and all setters normalize before kind validation. Setter access
checks precede OFD PID validation; query PID checks follow normalization.
The syscall imports one normalized scalar LockRange and passes it by value
to the existing get/set helpers under the retained descriptor/Handle.
Ownership, table storage/reclamation and lock ordering stay intact.

The maintained V fixture runs 2,096 controls per architecture, as root and
UID/GID1000. Per credential: 128 setter checks, 64 query checks, 204 range/compound
error checks, 340 retained-range/edge checks and 312 file-state checks. Libc and
raw upper-word descriptor/command calls retain full-width flock pointers.
Sixteen accepted cases and ten refusal cases cover absolute/CUR/END origins,
positive/negative/zero lengths, INT64_MAX, INT64_MIN and real EOVERFLOW/EINVAL.
Additional combinations distinguish early POSIX query-kind errors, range
overflow before invalid kind/PID/access, and setter EBADF before invalid OFD
PID. Full flock bytes remain unchanged on errors and setter calls; successful
queries return exact type/origin/range/PID. Actual locks are queried through
the opposite ownership class, including preserved seeds after failed requests.

Maximum-byte partial unlocks preserve finite prefixes and sentinel suffixes;
bridges coalesce them, last-byte removal restores a finite prefix, and
conversion reports the correct reader range. Aliases preserve the suffix
after a nonfinal close; final close releases it. Bytes, size/mode/ownership,
descriptor flags and shared cursors stay unchanged, including a cursor at
INT64_MAX. Both baselines reproduce 352 failures, with the same counts on
both architectures. Candidates and actual Linux 6.12.51 references pass the
byte-identical corresponding native probe C/ELF. GNU wrappers/foreign ABIs
are outside these native musl controls.

Two 200-cycle cohorts acquire/query/unlock the maximum byte, set a POSIX range
ending there, verify process-close cleanup and acquire/release through an OFD
alias. All 18 ARM/14 x86 live slab classes stay flat; large pages remain 63/63 ARM
and 160/160 x86. The probe emits 10 explicit allocas and no hidden heap/index
helpers. Whole kernel C remains byte-identical after removing exactly the
four reviewed function definitions/prototypes (normalization, get/set record
locks and fcntl_lock); no whitespace or helper normalization is needed.
Allocation scans finish with unchanged 400 ARM/292 x86 sites and existing
allowance refusals. An independent
[lifetime review](../tests/linux-compat/results/2026-10-14/lockrange-lifetime-review.md)
binds scalar lifetime/retained references, sources, generated C and captures.

Both production kernels build. The lockrange, ofdlocks, fcntlpath, open and
runtime cases pass, plus eight host test files. AArch64 uses one ordinary
five-case controller run. Host disk exhaustion interrupted x86 open/runtime
image setup and prevented persistence of its outer aggregate; its
[partial original receipt](../tests/linux-compat/results/2026-10-14/lockrange-original-x86_64.json)
keeps three passed cases and failed open setup visible. Only open/runtime
were recovered in a fresh state. The final x86 receipt explicitly composes
those five successful cases on identical kernel bytes, using the
[maintained V composer](../tests/linux-compat/results/2026-10-14/lockrange-compose.v)
and exact source/C/ELF/ISO/serial provenance. Its aggregate is assembled from
actual case captures; it is not another five-case controller execution.
Completed private artifacts were losslessly compressed with verified SHA
manifests to recover space. The audit checks all 64 dispatch/lock inputs,
exact counts, flat retention, same source/C/ELF and actual kernel/ISO/reference
receipts. Deliberate assertion and passing-as-baseline controls must fail.
The public dispatch inventory is refreshed from committed inputs in an isolated
publication view; these runtime receipts retain their explicit frozen test base.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/lockrange-after-aarch64.json), [native capture](../tests/linux-compat/results/2026-10-14/lockrange-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/lockrange-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/lockrange-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/lockrange-after-x86_64.json), [native capture](../tests/linux-compat/results/2026-10-14/lockrange-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/lockrange-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/lockrange-evidence-x86_64.json), [recovery receipt](../tests/linux-compat/results/2026-10-14/lockrange-recovery-x86_64.json).
- [Audit source](../tests/linux-compat/results/2026-10-14/lockrange-audit.v) and [verdict](../tests/linux-compat/results/2026-10-14/lockrange-audit.log); baseline captures, build/host/scope logs, allocation scans and negative controls sit beside them.

Concurrent CUR/END changes, nonregular/disk/network/overlay filesystems,
arbitrary persistent lock populations, POSIX deadlock detection and close
races, fairness, cancellation/descriptor pressure and GNU/translated/ELF32
paths remain separate. The three broad section 15 acceptance gates stay open.

## Native advisory-lock access and words

Record read locks previously accepted access mode 3, which grants neither
read nor write access. Whole-file flock also accepted that mode and O_PATH
handles, and accepted LOCK_UN combined with SH/EX. Native raw flock calls
interpreted register-sized descriptor/operation values rather than Linux
unsigned-int words, so nonzero upper operation bits incorrectly returned
EINVAL. The handler now narrows both words before validation/lookup, admits
exact SH, EX or UN with optional NB, rejects O_PATH, and requires ordinary
read/write access for acquisition. Mode3 unlock remains a real accepted
operation. Record read acquisition requires O_RDONLY or O_RDWR; queries
and unlock retain their existing rules. Access checks precede OFD PID checks
and follow range/type conversion as previously qualified. The
[pinned Linux 6.12.51 implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/locks.c)
and same-ELF references establish the selected Linux contract. Deprecated
LOCK_MAND compatibility remains outside this qualification.

The maintained V fixture runs 12,720 controls on each architecture as root
and UID/GID1000. Per credential: 2,700 record/header controls, 480 whole-file
error controls and 3,180 lock/file-state controls. All six POSIX/OFD commands
combine reader/writer/unlock types, five range/kind/PID variants, O_RDONLY,
O_WRONLY, O_RDWR, mode3 and O_PATH, original/dup/CLOEXEC aliases and libc/raw
upper-word calls. Sixteen flock operations distinguish exact accepted forms,
invalid unlock combinations, unknown low bits and nonzero ignored high words.
The five record variants exercise valid ranges, PID errors, bad origins,
signed overflow and invalid kinds with real EBADF/EINVAL/EOVERFLOW precedence.

Successful queries report exact conflict headers; errors and setters preserve
all 32 flock bytes. Independent descriptions observe actual acquired ranges
and unchanged seed locks. Whole-file readers/writers distinguish shared,
exclusive and removed locks after acquisition/conversion/unlock, and prove
that rejected unlock combinations preserve the prior exclusive lock. Bytes,
size/mode/UID/GID/inode, status/descriptor flags and actual shared offsets stay
correct. O_PATH metadata/flags are checked without attempting shared seeks.
Both frozen baselines reproduce 1,458 failures in the same counts (per
credential: 48 record, 165 flock and 516 state failures). Candidates and actual
Linux 6.12.51 pass identical respective native probe C/ELF. These are native
musl/raw controls, not GNU-wrapper or foreign-ABI qualification.

Two 200-cycle cohorts combine rejected mode3 read locks, mode3/O_PATH flock
requests and invalid unlock combinations with real OFD/flock alias locks,
queries, unlocks and final close. After 32 warmups and settling, all 18 ARM
and 14 x86 live slab classes stay flat; large pages remain 63/63 ARM and
160/160 x86. Probe C has 11 explicit allocas and no hidden heap/index helpers.
Whole kernel C remains byte-identical after removing exactly the two reviewed
function definitions/prototypes (syscall_flock and fcntl_lock), with no
whitespace or helper normalization. No ownership/table/reclamation/lock-order
change is introduced. Allocation scans retain 400 ARM/292 x86 sites and the
same existing allowance refusals. An independent
[lifetime review](../tests/linux-compat/results/2026-10-14/lockaccess-lifetime-review.md)
binds the retained descriptor, scalar imports, stack buffers and completed
source/C/ELF/capture evidence.

Both production kernels build. Ordinary five-case native controller runs
(lockaccess, lockrange, ofdlocks, open, runtime) pass on each architecture,
plus eight host test files. The audit pins exact counts/failures, flat
storage, all 64 dispatch/lock inputs, actual source/C/ELF/kernel/ISO/reference
receipts and the independent review. Deliberate assertion and passing-as-
baseline controls must fail. Runtime evidence uses frozen commit
`0c12e1656b633b2f7d8365a47361a812414d4eb1` plus the sole reviewed locks.v
change. Public dispatch fingerprints are refreshed from committed inputs in
an isolated publication view, separately from this frozen runtime evidence.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/lockaccess-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/lockaccess-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/lockaccess-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/lockaccess-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/lockaccess-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/lockaccess-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/lockaccess-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/lockaccess-evidence-x86_64.json).
- [Audit source](../tests/linux-compat/results/2026-10-14/lockaccess-audit.v) and [verdict](../tests/linux-compat/results/2026-10-14/lockaccess-audit.log); baseline captures, build/host/scope logs, allocation scans and negative controls sit beside them.

Nonregular/disk/network/overlay filesystems, deprecated LOCK_MAND, restrictive
policy and concurrent close, descriptor pressure/fairness/cancellation, POSIX
deadlock detection and GNU/translated/ELF32 paths remain separate. The three
broad section 15 acceptance gates stay open.

## Same-kind flock ownership

Repeating SH or EX through the same open description previously removed its
held lock before reacquisition. That woke a queued contender and could make
the repeat return EWOULDBLOCK or surrender ownership. Linux checks an
existing same-description/same-kind lock before deleting it. The handler
now scans the table under its existing lock and returns success without
mutation or notification when resource, description, flock class and kind
match. The retained descriptor and existing defer cover this return. Access
and MAC validation still run first; actual conversion and unlock retain
the existing release/reacquisition behavior. See the
[pinned Linux normalizer/locking source](https://github.com/gregkh/linux/blob/v6.12.51/fs/locks.c).

The maintained V probe runs 1,936 counted controls per architecture/run, in
root and UID/GID1000 cohorts. Per credential: 192 repeat results, 192 waiter
continuity checks, 240 contender/file-state controls and 344 sequential
conversion/alias-close controls. Each cohort forks 24 independent contenders
across regular files/directories, SH/EX, original/ordinary/CLOEXEC aliases
and libc/raw upper-word forms. The child signals readiness, closes inherited
owner descriptions, reopens independently and blocks for EX. Parent procfs
and pipe checks establish its waiting state before eight repeated NB calls.
It must stay blocked until explicit unlock; peer SH/EX probes verify the
original held kind, and metadata/flags/bytes/shared regular-file offsets stay
unchanged. Child result/acknowledgment/waitpid enforce clean final release.

Sequential controls exercise blocking and NB repeats through all aliases,
actual SH-to-EX/EX-to-SH conversions, peer reader/writer compatibility,
nonfinal close retention and final close release. They reject a false fix
that treats every request on an already locked description as a no-op.
Directory ownership/mode/inode/flags are checked separately from regular-file
bytes/size/cursors. The same native musl source/C/ELF passes actual Linux
6.12.51, which skips Vinix allocator accounting.

To expose the release window, the maintained V instrumenter adds a private
sched import and 32 reschedules immediately after description-lock release
for NB requests, with no advisory table lock held. Removing that block and
import restores each before/after source exactly. The same-kind branch
precedes the window; real conversion/unlock continues through it. The
[window baseline receipts](../tests/linux-compat/results/2026-10-14/flocksame-before-window-aarch64.json)
and [x86 counterpart](../tests/linux-compat/results/2026-10-14/flocksame-before-window-x86_64.json)
expose 792 ARM/790 x86 failures in their recorded runs. Both ARM credentials
and x86 UID1000 fail 192 repeat, 192 continuity and 12 peer-state controls;
x86 root records 191/191/12. All 344 sequential controls per credential pass.
An uninstrumented baseline is not claimed to fail deterministically.
Ordinary and window candidates pass all 1,936 controls each.

Each candidate profile runs two mixed 200-cycle storage cohorts after 32
warmups and settling: file/directory acquisition, repeated same kind, real
downgrade, peer sharing, unlock and alias/final close. All 18 ARM/14 x86 live
slab classes stay flat; large pages remain 63/63 ARM and 160/160 x86. Probe C
has eleven explicit allocas and no hidden heap/index helpers. Whole ordinary
and whole window kernel C remain byte-identical outside the sole syscall_flock
definition/prototype. Window/ordinary comparison allows that function and,
where required on x86, one relocated 48-line block of byte-identical mmap
literals from the scheduling import. Other generated C remains exact.
Allocation inventories retain 400 ARM/292 x86 sites and existing allowance
refusals. An independent
[lifetime review](../tests/linux-compat/results/2026-10-14/flocksame-lifetime-review.md)
binds the table-read/retained-descriptor path, private yields, stack buffers,
source/C/kernel/ELF/complete captures and measured cleanup.

All eight ordinary/window before/after production builds pass. The ordinary
flocksame/lockaccess/ofdlocks/open/runtime suites pass on each architecture,
as do the separate window probe and eight host test files. The audit pins
all 64 dispatch/lock inputs, exact source/C/ELF/kernel/ISO/Linux-reference
receipts, scope, builds and independent review. Assertion and passing-as-
baseline controls must execute and fail. Runtime evidence freezes commit
`84e6321ed2e61682b3a98ca3e6f9665f1f8e2380` plus the sole locks.v change;
public dispatch fingerprints use the committed publication parent in an
isolated view and remain separate from this runtime snapshot.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/flocksame-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/flocksame-after-aarch64-native.log), [window receipt](../tests/linux-compat/results/2026-10-14/flocksame-after-window-aarch64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/flocksame-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/flocksame-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/flocksame-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/flocksame-after-x86_64-native.log), [window receipt](../tests/linux-compat/results/2026-10-14/flocksame-after-window-x86_64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/flocksame-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/flocksame-evidence-x86_64.json).
- [Audit source](../tests/linux-compat/results/2026-10-14/flocksame-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/flocksame-audit.log), [instrumenter](../tests/linux-compat/flocksame-instrument.v); baseline captures, build/host/scope/allocation logs and negative controls sit beside them.

Restrictive policy, arbitrary concurrent mutation of a shared description,
pressure/fairness/deadlock/cancellation, other filesystems/nonregular types,
deprecated mandatory locks and GNU/translated/ELF32 paths remain separate.
The three broad section 15 acceptance gates stay open.

## Native fcntl signal configuration

The existing native dispatch wrapper already imports F_SETSIG scalar
arguments through low32 before calling the handler. Its 0..64 validation
is equivalent to Linux signed-int validation for these signal numbers.
For example, raw argument `0xabcdef0100000020` sets 32 and F_GETSIG returns
32; invalid low values retain EINVAL without changing configuration.
Missing/O_PATH descriptors retain EBADF before signal validation. This
work adds conformance coverage; the kernel source/C/ELF stay unchanged.
See the pinned [Linux fcntl source](https://github.com/gregkh/linux/blob/v6.12.51/fs/fcntl.c)
and [signal validation](https://github.com/gregkh/linux/blob/v6.12.51/include/linux/signal.h),
whose downloaded bytes are bound in the evidence.

The V probe runs 4,720 controls per architecture in root and UID/GID 1000
cohorts. Per credential, exact counts are 810 ordinary raw setters, 405
invalid/O_PATH raw setters, 243 musl setters, 540 getter controls and 362
limit/replacement/cursor controls. Values include default zero, 1, 32, 64,
65, 127 and signed32 boundaries. Five raw forms vary descriptor, command
and argument upper words; musl controls pass actual signed-int arguments.
Six ordinary classes cover readonly/RDWR regular opens, a directory,
nonblocking pipe reader/writer and a UNIX stream endpoint. Original/dup/
F_DUPFD_CLOEXEC aliases share their actual description setting. Independent
opens of the same inode and the socket peer keep independent configuration.
Six O_PATH aliases and three missing/negative sources preserve real errors.

F_GETSIG ignores all five full-width argument values, including inaccessible
addresses. Held 64/65 remain usable at soft descriptor limits eight and zero.
Reused 66 transitions through missing, regular, socket and closed states
with opposing CLOEXEC. The probe checks all descriptor/status flags, primary
and selected-target metadata/owners/cursors, actual shared cursor movement
and complete final bytes/queued AB. Cohorts use inherited descriptors; the
parent waits and closes all descriptions before removing its fixture paths.
Restore calls keep cases independent. Actual asynchronous notifications are
not enabled or measured by this sequence.

The first unchanged-kernel runs passed every control, disproving the initial
assumption that full-width signal words reached the handler. The local outer
wrapper expected inner exit 1 and therefore asserted after the successful
guest runs; its source and complete passing diagnostic receipts remain
fingerprinted. A redundant handler edit was removed before any changed
kernel build. Fresh corrected wrappers complete exit 0 and qualify five
guest cases per architecture: fcntlsig/fcntlabi/fcntlpath/open/runtime. Actual
Linux 6.12.51 passes identical native probe source/C/ELF. No baseline failure
or kernel bug fix is claimed.

Both initial and fresh native runs include two 200-cycle cohorts after 32
warmups and settling. Accepted/refused setters, real alias duplication/close
and unchanged AB queues retain all 18 ARM/14 x86 slab classes flat. Large
pages stay at 70/70 on AArch64 and 181/181 on x86-64. Generated
probe C has ten explicit allocas and no hidden heap/index helpers. The
frozen kernel source/C/ELF are exactly unchanged, so no allocation, ownership,
reclamation or lock-order change is introduced. Two production builds and
eight host test files pass. The allocation inventory retains 400 ARM/292 x86
sites and existing allowance refusals; it is not a globally passing allowance
audit. An [independent lifetime review](../tests/linux-compat/results/2026-10-14/fcntlsig-lifetime-review.md)
binds live frames, cleanup, unchanged kernels and completed captures.

The maintained audit binds 63 frozen dispatch/source inputs, compiler/C/ELF/
kernel/ISO, complete native/Linux captures, builds and review. Deliberately
failing assertion and passing-as-failure controls must execute. Runtime
evidence freezes `97e2f95bdad3acbf00ec27ada5ae38c09e25c6a6`; public dispatch
fingerprints use the committed publication parent in an isolated view and
remain separate from that frozen runtime snapshot.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/fcntlsig-native-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/fcntlsig-native-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/fcntlsig-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/fcntlsig-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/fcntlsig-native-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/fcntlsig-native-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/fcntlsig-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/fcntlsig-evidence-x86_64.json).
- [Audit source](../tests/linux-compat/results/2026-10-14/fcntlsig-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/fcntlsig-audit.log); passing diagnostic captures, build/host/allocation logs and negative controls sit beside them.

This qualifies signal configuration and exact error behavior. Actual SIGIO
and queued-signal delivery, asynchronous readiness, ownership/security
policy, concurrent mutation/close, GNU wrappers and translated/ELF32 paths
remain unqualified. The three broad section 15 acceptance gates stay open.

## Native fcntl owner commands and target errors

Linux F_SETOWN is command 8 and F_GETOWN command 9. Vinix had these reversed:
ordinary setters executed the getter. The command constants now match Linux;
the existing native wrapper imports descriptor, command and scalar owner
words from their low32 bits while extended owner pointers stay full width.
F_SETOWN(INT_MIN) returns EINVAL before negation. Nonzero missing owner
targets return ESRCH for scalar and extended setters, before any owner
configuration changes. Zero clears ownership. Descriptor/O_PATH EBADF,
extended-copy EFAULT and invalid-kind EINVAL retain Linux precedence.
Compare the pinned [Linux implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/fcntl.c).

The V probe performs 7,190 controls per architecture as root and UID/GID1000.
Per credential counts are 630 ordinary raw scalar setters, 315 missing/O_PATH
raw setters, 189 musl scalar setters, 2,106 extended setters and 355 getter,
limit/replacement and shared-cursor controls. Six classes cover readonly/RDWR
regular files, a directory, nonblocking pipe reader/writer and a UNIX stream
endpoint. Original/dup/CLOEXEC aliases share description state; independent
opens and the socket peer retain their own state. Live self PID/main TID and
self group, zero, missing in-range/out-of-range numbers, signed32 extremes,
invalid kinds and inaccessible full-width pointers exercise real errors.
Raw F_GETOWN positive-PID checks vary upper descriptor/command and ignored
argument words; musl getters also verify zero and negative group results.
The probe restores owner settings between cases and checks owner kind/ID,
signals, metadata, flags, actual shared cursors, complete file bytes and AB
queues. Held 64/65 remain usable at NOFILE soft limits eight/zero; closed 66
is reused for regular/socket descriptions before being closed again.

Both unchanged baselines fail exactly 2,736 of these controls. Patched
Vinix and actual Linux 6.12.51 pass the identical native musl source/C/ELF.
Two 200-cycle cohorts after warmups and settling measure aliases, accepted
owner updates and refused targets; all slab classes and large pages stay
flat. The new existence helper holds pid_lock across namespace/table/group
reads and returns only a scalar. It retains no target pointer and allocates
nothing. Successful fixture paths close all descriptions and remove their
file/directory; fatal setup/reset failures rely on process teardown.

Four production builds, five candidate guest cases per architecture
(fcntlowner/fcntlsig/fcntlabi/open/runtime), eight host test files and
generated coverage checks pass. The source allocation inventory retains
400 ARM/292 x86 sites and existing allowance refusals; this does not establish
a globally passing allowance audit. The assertion-enabled maintained audit
binds 63 frozen source inputs, compiler, generated C, kernels, probe/ISO,
complete captures, builds and an independent lifetime review. Failing
assertion and passing-as-baseline controls execute. Complete generated C
matches outside exactly fcntl/PID-lookup bodies and prototypes plus the two
verified owner-command defines; sixteen explicit probe allocas introduce
no hidden heap/index helpers. Runtime evidence freezes committed parent
6182c530e5bbb6fe7b1cca7db9e4b1c73cbd3106; the public inventory is separately
generated from the committed publication parent plus this change.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/fcntlowner-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/fcntlowner-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/fcntlowner-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/fcntlowner-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/fcntlowner-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/fcntlowner-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/fcntlowner-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/fcntlowner-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/fcntlowner-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/fcntlowner-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/fcntlowner-lifetime-review.md); baseline/build/allocation/host and negative-control logs sit beside them.

This qualifies command mapping and the selected owner-update/refusal behavior.
Actual SIGIO/queued notifications, retained PID identity after exit/recycling,
and restrictive/concurrent policy remain unqualified. Selected PID-kind
getters, non-main-thread targets, leaderless groups and namespace owner
getters have the separate qualification below. GNU/translated/ELF32
paths and the three broad section 15 acceptance gates stay open.

## Native fcntl owner task kinds and namespaces

F_GETOWN/F_GETOWN_EX previously echoed the stored number even when no task
was attached to that owner kind, the target had been reaped, or the caller
could not see that PID namespace. Setters now resolve caller numbers into
kernel numbers; getters map only the attached requested PID/TID/group kind
back into the caller namespace, returning zero for an absent attachment or
invisible number. A non-main TID may be accepted for PID/group configuration
while its getter returns zero, matching the pinned
[Linux implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/fcntl.c).
A group remains visible after its leader is reaped while another member
survives. Zero and the existing exact setter errors retain their behavior.

Each native architecture runs 2,430 raw/musl controls as root and UID/GID1000.
Per credential categories have 405 live PID/TID/child kind checks, 135 child
reap/refusal checks, 135 worker removal/refusal checks, 225 group survival and
last-member checks, and 315 inside/outside one-level namespace checks.
Regular files, nonblocking pipe readers and UNIX stream endpoints each have
original/dup/CLOEXEC aliases. Extended getter pointers stay full width; raw
descriptor/command upper words and ignored scalar arguments are exercised.
Small negative group numbers from the generic libc syscall wrapper receive
the corresponding errno decoding. Metadata, descriptor/status/signal fields,
shared offsets, all file bytes and queued AB remain intact. Namespace children
exchange real owner settings over shared descriptions in both directions.

The worker is observed in fresh task-directory snapshots while alive, joined,
then polled for absence through bounded fresh getdents64 snapshots before
zero/ESRCH checks. Every directory record and terminating byte is bounded;
EOF and successful close are required. This establishes observed settling,
not a universal simultaneous PID-detach barrier. Earlier Linux x86 checks
incorrectly assumed join itself guaranteed detachment and failed one control.
A subsequent pathname predicate exposed Vinix's cached task-path limit:
existing task paths are refreshed on directory listing or missing lookup.
Those earlier receipts/captures remain published as diagnostics. Cached-path
invalidation and exact thread-exit races remain unqualified.

Both unchanged baselines fail exactly 1,290 controls. Native baseline/candidate
source, C and ELF match exactly; patched Vinix and actual Linux 6.12.51 pass
the same native musl ELF. The separate preflight C differs only in stderr
scaffolding, with an identical resulting ELF; its whole-C hashes and raw diff
are published without normalization. Two 200-cycle cohorts
measure alias/update/refusal cleanup while a separate non-main worker stays
alive; all slab classes and large pages stay flat after warmups and settling.
Owner kind/number writes and snapshots use Handle.l, released before table
lookup; setters release pid_lock before acquiring Handle.l. The scalar helpers
hold pid_lock for all target/namespace/group reads, return no borrowed pointer
and allocate nothing. No object, field or retained namespace is added. Fixture
failure paths terminate without returning while a worker borrows the frame;
successful paths join workers, reap children, close descriptors and unlink.

Four completed production builds, five candidate guest cases per architecture
(ownerquery/fcntlowner/fcntlsig/open/runtime), eight host files and coverage
checks pass. Allocation inventory remains 400 ARM/292 x86 sites with existing
allowance refusals. Its copied-source counts grow from 659/655 to 1304/1315
because the preserved obj-persistent/vsrc build snapshot is also traversed;
allocation sites and refusal rows remain identical. Complete generated C is
identical outside precisely fcntl
and the replaced/new scalar PID helpers, their bodies and prototypes. The
assertion-enabled audit executes negative assertion and passing-as-baseline
controls and binds 63 frozen inputs, C/kernels/probe/ISO/captures/builds and
the independent lifetime review. Twenty-six explicit fixture allocas have no
hidden heap/index helpers. Runtime evidence freezes committed parent
905c838513a0939fb8d269786487346fbd62d7a1; the public inventory is generated
separately from the committed publication parent plus this change. The failed
ARM build from host disk exhaustion remains visible; successful rebuild and
completed profiles use a separately verified RAM scratch volume.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/ownerquery-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/ownerquery-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/ownerquery-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/ownerquery-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/ownerquery-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/ownerquery-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/ownerquery-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/ownerquery-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/ownerquery-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/ownerquery-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/ownerquery-lifetime-review.md); superseded diagnostic/build/allocation/host and negative-control logs sit beside them.

The handle still stores a number rather than a retained Linux struct-pid
identity. PID recycling, exact exit/update races, SIGIO/queued notifications,
restrictive ownership/security policy, deeper PID namespaces, cached task-path
invalidation and GNU/translated/ELF32 paths remain unqualified. The three broad
section 15 acceptance gates stay open.

## Cached procfs task-path invalidation

Cached `/proc/PID/task/TID` entries now consult the registered process/thread
tables before resolving an existing child. A removed non-main thread or reaped
main task returns ENOENT through stat, status and directory paths. The selected
task is checked individually: a bulk try-locked thread-list snapshot can omit
live siblings while its lock is busy. Registered main tasks remain reachable
through zombie lifetime, and non-main tasks must belong to the selected process.

The `proctask` native musl fixture runs four cohorts per architecture: root and
UID/GID1000, each in the initial and a one-level PID namespace. Three proc
mounts, self/numeric parent paths and five libc/raw open/openat forms cover
native high argument words and original/dup/CLOEXEC task-directory handles.
Every completed cohort reports the following independent controls twice, from
its own CASES rows and the supervisor's pipe-transferred FINAL rows.

| Controls per cohort | Calls | Baseline failures |
| --- | ---: | ---: |
| Main task and two live worker paths | 270 | 0 |
| Joined worker paths after observed tgkill ESRCH | 180 | 180 |
| Main and surviving sibling paths | 180 | 0 |
| Unrelated child absent from parent's task directory, present in its own | 99 | 0 |
| WNOWAIT zombie main present, then absent after reap | 27 | 18 |
| Retained parent/worker metadata and descriptor flags | 90 | 0 |

Both baselines fail exactly 792 of 3,384 controls per architecture. Both
candidates and actual Linux 6.12.51 pass all controls using the same native
musl ELF bytes. Successful pthread joins are followed by bounded signal-zero
tgkill observations of ESRCH; positive live controls use the same independent
syscall. This records the observed signal-zero boundary rather than a universal
simultaneous PID-table detach barrier. No procfs pathname or directory-list
polling refreshes the cached entry before the removal controls. The child is
forked before workers start.
WNOWAIT records successful exit without reaping; waitpid supplies the separate
reap boundary. Retained stat and directory descriptions remain usable for
fstat/F_GETFD through all three aliases; dev/ino/mode are checked, without
claiming Linux/Vinix detached nlink equivalence. These checks qualify opens
and retained descriptor metadata; stat/status contents and reads through
already-open retired files require separate qualification.

The new predicate holds pid_lock, compares process pointers by identity and
returns only a bool. No thread/process/namespace pointer escapes and no
allocation is added. The table lock is released before the existing procfs
unlink/nlink/unref steps under procfs_lock. Their extracted helper retains the
previous node/resource lifetime even at zero refcount, since path walkers,
cwd/root users and descriptors can still hold the subtree. There is no new
reclamation path. Fixture failures after launch terminate with _exit while
workers still borrow their frame; successful paths join, reap and close all
aliases before unwinding.

Four warm/settled 200-cycle cohorts per architecture repeatedly query missing
and live tasks, reopen child paths and create/close parent aliases. All 18 ARM
and 14 x86 live slab classes remain flat. Large pages stay at 65/65 for initial
ARM views and 71/71 for namespace views; x86 stays at 164/164 and 175/175.
These measurements cover repeated lookups of existing trees, not task/mount churn or
whole-tree reclamation. Four production builds, five candidate guest cases
(proctask/ownerquery/procself/open/runtime), eight host files and coverage
checks pass. Allocation inventory remains 659/655 copied source files and
400 ARM/292 x86 sites with unchanged existing allowance refusals. Complete
generated C differs only in the lookup, prune function, extracted drop helper
and new predicate bodies/prototypes.
The fixture has 21 explicit allocas and no hidden heap/index helpers. The
assertion-enabled audit executes both deliberately failing controls and binds
63 frozen kernel inputs plus C/ELF/ISO/captures/builds and independent review.

The original compiler binary baked a shared source directory that disappeared
during qualification. The exact f6358ec revision was rebuilt in a private
worktree, with compiler sources and host GC/TCC inputs pinned. Final builds
and profiles use this self-contained compiler; earlier successful kernels,
generated C and build logs are retained as diagnostics. Separate preflight
C/ELF bytes match the executed native probe exactly; whole-C comparison logs
are empty, without normalization. Completed temporary artifacts have durable
SHA-verified copies. Runtime evidence freezes parent
1a9c4c4981cb0f0b2a5b31f08504150410226afe; the public
inventory is generated separately from the committed publication parent plus
this fix, excluding other sessions' dirty files.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/proctask-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/proctask-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/proctask-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/proctask-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/proctask-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/proctask-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/proctask-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/proctask-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/proctask-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/proctask-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/proctask-lifetime-review.md); compiler/build/allocation/host and negative-control logs sit beside them.

The earlier ownerquery cached-path diagnostics remain historical captures;
the selected behavior is qualified here separately. PID/TID reuse, exact
concurrent detach after a positive check, leader-only exit, general process-root
cache invalidation, deeper namespaces, retained-tree reclamation/churn and
GNU/translated/ELF32 paths remain unqualified. The three broad section 15
acceptance gates stay open.

## Cached procfs process-root invalidation

An already-cached numeric `/proc/PID` child now checks process registration
before lookup continues. Reaped process paths return ENOENT through stat,
status and directory leaves. Registered live processes and WNOWAIT zombies
remain reachable. The check is restricted to actual proc roots or mounted PID
views, numeric names and process-directory resources; static entries and
dot/dotdot lookups cannot accidentally remove a parent process directory.

The `procpid` native musl fixture runs root and UID/GID1000 in both the initial
and a one-level PID namespace. Three mounts and five libc/raw open/openat forms
exercise native high argument words and original/dup/CLOEXEC root handles.
Each cohort reports the same six rows through local CASES output and the
supervisor's pipe-transferred FINAL output.

| Controls per cohort | Calls | Baseline failures |
| --- | ---: | ---: |
| Self and two live children, three leaf types | 135 | 0 |
| WNOWAIT zombie child | 45 | 0 |
| Reaped child, two successive cached-path sweeps | 90 | 90 |
| Surviving child/self and dot/dotdot/self/thread-self/sys/version | 180 | 0 |
| Missing PID zero and maximum positive signed32 PID | 90 | 0 |
| Retained root/child alias metadata and descriptor flags | 108 | 0 |

Both unchanged baselines fail exactly 360 of 2,592 controls per architecture.
Fixed Vinix and actual Linux 6.12.51 pass every control using the same native
musl ELF bytes. Both children are forked before any threading; private pipe
protocols release each child, WNOWAIT observes successful exit, and waitpid
reaps it. An independent kill-zero ESRCH query precedes the missing-path
checks. No procfs lookup or directory listing polls the retired PID before
those checks. Nine root and eighteen child stat/directory descriptors preserve
dev/ino/mode and descriptor flags before exit, during zombie lifetime, after
reap and after the surviving child is reaped. Detached nlink values, file
contents and relative lookup through retired directory handles are separate.

The existing scalar `task_attached(pid, pid)` predicate holds pid_lock and
returns only a bool. No process/thread/namespace pointer escapes; the lock is
released before the existing directory-removal helper runs under procfs_lock.
The retained node/resource lifetime is unchanged, including at zero refcount.
No field, allocation, pin or reclamation path is added. Complete production
generated C on each architecture differs only in the single lookup body and
its prototype. Independent review also checks the unchanged removal/unref
bodies and the synchronous fixture frame borrows. Normal fixture completion
reaps both children and closes all 27 aliases; child branches use _exit before
returning through copied parent frames.

Four warmed and settled 200-cycle cohorts per architecture repeatedly open
missing/live process paths and create/close root aliases. All 18 ARM and 14 x86
slab classes remain exactly flat. Large pages stay at 74/74 for initial ARM
views and 80/80 for namespace views; x86 stays at 188/188 and 199/199. These are
lookup/alias measurements over finite existing trees, not process/mount churn
or whole-tree reclamation measurements. Four production builds, five candidate
guest cases (procpid/proctask/procself/open/runtime), eight host test files and
coverage checks pass. Allocation inventory remains 661 ARM/657 x86 copied
source files and 400/292 sites, with unchanged existing allowance refusals.
The fixture has 19 explicit allocas and no hidden heap/index helpers.

The assertion-enabled audit executes deliberate assertion failures and rejects
a passing log presented as a failing baseline. It binds 63 frozen kernel inputs, whole C, kernels, native
probes, ISOs, captures, builds and independent review. Separate preflight,
preview and executed native C/ELF bytes match exactly; raw C comparison logs
are empty without normalization. The prior self-contained f6358ec compiler
and its 15,146 source/GC/TCC pins and published recovery record are reused;
this change does not claim another compiler recovery. Runtime evidence freezes
parent a51d6a215d91fe47b84e1d544487f7e62ec1e759. The public dispatch inventory
is generated separately from the committed publication parent plus this fix,
excluding other sessions' dirty sources. Qualification artifacts reside in
durable private storage and published receipts pin their hashes.

The first host compilation failed because slab logging omitted a printf
argument. Those completed diagnostic receipts and captures remain published,
with empty probe/ISO hashes and no guest execution; they are distinct from the
fresh semantic baseline runs above.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/procpid-after-aarch64.json), [capture](../tests/linux-compat/results/2026-10-14/procpid-after-aarch64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/procpid-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/procpid-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/procpid-after-x86_64.json), [capture](../tests/linux-compat/results/2026-10-14/procpid-after-x86_64-native.log), [Linux reference](../tests/linux-compat/results/2026-10-14/procpid-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/procpid-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/procpid-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/procpid-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/procpid-lifetime-review.md); diagnostic/build/allocation/host and negative-control logs sit beside them.

PID reuse and generation identity, exact concurrent reap after a positive
check, inherited retired-directory lookup or file contents, deeper namespace
and mount teardown, retained-tree reclamation/churn, GNU/translated/ELF32
paths and the three broad section 15 acceptance gates remain unqualified.

## Native faccessat2 flag words and pipe owners

Native faccessat2 now imports the lower 32 flag bits before checking known
flags or dispatching permission checks. Upper register bits no longer cause
EINVAL for otherwise valid requests. Unknown lower flag bits still return
EINVAL before pathname lookup. The path pointer remains full width, and the
existing descriptor retention, path copies and permission checks are unchanged.
Linux declares this argument as `int` in its
[syscall definition](https://code.googlesource.com/linux/torvalds/linux/+/2656821f1f202d58224551b71eff41aafd1edf8b/fs/open.c).

Anonymous pipes also initialize inode UID/GID from their creator's effective
IDs before the existing resource-interface copy. Previously an ordinary
user's pipe remained root-owned, so valid empty-path permission queries failed.
The fix adds only two scalar metadata assignments and a synchronous process
borrow; pipe allocation, boxing, references and descriptor publication are
unchanged. Named FIFOs and explicit fsuid/fsgid behavior are separate.

The `accessflags` native musl probe runs root and UID/GID1000 cohorts. Eight
known flag combinations and five upper-word patterns cover F_OK/R_OK/W_OK/
R_OK|W_OK and invalid mode 8. Absolute and relative files, directories, links,
missing paths, bad/non-directory descriptors and a full-width fault pointer
exercise real success, EACCES, ENOENT, EBADF, ENOTDIR and EFAULT. Empty paths
check original/dup/CLOEXEC aliases of regular files, directories, unlinked
O_PATH files and pipes. Four unknown lower flag words require EINVAL without
state changes. Every cohort transfers its counts to the supervisor; CASES
and FINAL rows must agree exactly.

| Controls per cohort | Calls | Root baseline failures | UID1000 baseline failures |
| --- | ---: | ---: | ---: |
| Known flags, argument words and real permission/path errors | 2,800 | 1,792 | 1,828 |
| Unknown lower flags, including fault and descriptor controls | 400 | 0 | 0 |
| Retained aliases, inode owners, flags, bytes, cursor and queued AB | 15 | 0 | 3 |

The unchanged kernels fail 3,623 of 6,430 controls per architecture. Final
Vinix kernels and actual Linux 6.12.51 pass with the identical native probe
C/ELF. The original word-only intermediate fixes all root controls and leaves
180 ordinary-user pipe permission failures; its captures use the earlier
probe without explicit UID/GID metadata assertions. The fresh final probe adds
those assertions and is used for both final baselines and Linux references.
The existing `access` case independently checks low-word pipe ownership and
real/effective permissions for equal UID/GID1000 and real1000/effective0,
across six aliases per child. It closes every alias before _exit and the
parent waits before returning.

Two warmed and settled 200-cycle cohorts per architecture repeatedly check
real permission refusals, missing/fault paths, flags and temporary directory
aliases. All 18 ARM/14 x86 slab classes and large pages stay exactly flat,
at 68/68 ARM and 177/177 x86 for both credentials. These measurements cover
stable resources and alias cleanup; pipe/process creation churn remains separate.
Six completed production builds include the two intermediate kernels. All
five final guest cases (accessflags/access/procpid/open/runtime), eight host
test files and coverage checks pass. The allocation inventory has 662 ARM/658
x86 source files and 400/292 sites, retaining its existing allowance refusals;
before/after site and refusal rows are identical.

Erasing only faccessat2's body/prototype makes baseline and intermediate C
identical; erasing only Pipe.create's body/prototype makes intermediate and
final C identical. The combined change has no other generated-C difference.
Independent review verifies scalar publication before boxing, unchanged
allocation/free paths and synchronous fixture borrows. The native probe has
nine explicit allocas without hidden heap/index helpers. The assertion-enabled
audit rejects a passing log presented as a failing baseline, binds 63 frozen
kernel inputs and all artifact hashes, and reuses the previously pinned
self-contained f6358ec compiler. Final preflight/native/Linux bytes match
without normalization. Runtime evidence freezes committed parent
d00fe874ad9db66c958e35692fbb18c0a18c15bf; the public inventory separately uses
the committed publication parent plus the flags fix.

Initial QMP socket-path failures occurred before guest execution; compact v2
paths are used for final runs. The earlier probe type-check error, original
baselines and word-only failures remain separately published diagnostics.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/accessflags-after-aarch64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/accessflags-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/accessflags-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/accessflags-after-x86_64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/accessflags-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/accessflags-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/accessflags-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/accessflags-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/accessflags-lifetime-review.md).

Concurrent credential changes, filesystem UID/GID extensions, named FIFOs,
restrictive policy, GNU/translated/ELF32 paths and the three broad section 15
acceptance gates remain unqualified.

## Native pipe2 flag words and errors

The native checked pipe2 entry now decodes the lower 32 flag bits before
pointer checks or allocation. Unknown bits return EINVAL even for nil or
inaccessible outputs; upper register bits are ignored and cannot leak into
F_GETFL. Ordinary O_NONBLOCK and O_CLOEXEC behavior is retained. The existing
byte-stream pipe cannot provide O_DIRECT packets, so that mode returns
EOPNOTSUPP. O_EXCL is Linux's O_NOTIFICATION_PIPE and returns ENOPKG because
watch queues are absent. These native refusals publish unsupported dependencies;
they do not qualify packet or notification semantics. Linux's accepted flags
and validation order are defined in its
[pipe implementation](https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/b91872c56940950a6a0852e499d249c3091d4284/fs/pipe.c),
and the [pipe manual](https://man7.org/linux/man-pages/man2/pipe.2.html)
describes packet behavior and ENOPKG for unavailable watch queues.

The `pipeabi` musl probe runs root and UID/GID1000 cohorts. Four ordinary
flag combinations and five upper-register patterns exercise eight output
forms: aligned, unaligned, nil, address one, a full-width bad address,
PROT_NONE, readonly and a buffer crossing into PROT_NONE. Ten invalid lower
words must return EINVAL without changing output canaries. Valid copy faults
may copy a prefix; the probe does not require an untouched output on EFAULT.
Successful aligned/unaligned results are memcpy'd into typed stack storage.
An unexpected success for a bad destination is rejected before dereference.

| Controls per root/UID cohort | Native calls | Baseline failures | Linux reference calls |
| --- | ---: | ---: | ---: |
| Ordinary flags, upper words and result-pointer errors | 160 | 32 | 160 |
| Invalid lower flags, including fault outputs | 1,600 | 1,600 | 1,600 |
| Native packet/notification refusals | 320 | 320 | 0 |
| Retained alias metadata/flags, file bytes/cursor, queued AB and FD slots | 13 | 0 | 13 |

Each architecture's baseline fails 3,904 of 4,186 native controls. Corrected
Vinix kernels pass all native rows. The identical musl ELF passes 3,546
controls on actual Linux6.12.51, deliberately skipping the native-only refusal
row. Child CASES and supervisor FINAL rows agree exactly. Successful pipes
retain original/dup/CLOEXEC handles on each end and check exact libc and raw
64-bit F_GETFL, descriptor flags, FIFO0600 and creator owners, shared inode
identity, EAGAIN, ABC transfers across aliases and EOF after every writer
closes. Nine stable aliases preserve metadata/status flags and descriptor
slots; inherited regular data/cursor and the stable pipe's queued AB survive.
The UID cohort creates its retained regular file before dropping credentials;
its inherited handle remains root-owned, while subsequently created pipes
must be UID/GID1000-owned.

Two warmed and settled 200-cycle cohorts per architecture repeatedly create,
duplicate, transfer through and close ordinary pipes, plus validate scalar
refusals. All 18 ARM/14 x86 slab classes and observed large pages stay exactly
flat: 68/68 ARM and 177/177 x86 in both cohorts. This covers bounded creation
and alias cleanup with available descriptors; it does not qualify exhaustion,
concurrent publication or general process churn.

Four completed production builds use detached sparse worktrees frozen at
09d9bbd210cb89f082a6019d69e508199d9501b7. Erasing only the checked pipe2
wrapper body/prototype makes the entire before/after generated C identical.
Allocation, resource boxing, references and descriptor publication remain
unchanged. The probe has twelve explicit allocas and no hidden heap/index
helpers. Independent lifetime review covers synchronous stack/mapping borrows,
all known pipe aliases and the parent/child count transfer. Both five-case
profiles (pipeabi/accessflags/access/open/runtime), eight host test files and
coverage checks pass. Allocation scans retain 662 ARM/658 x86 source files
and 400/292 sites with identical existing allowance failures.

The assertion-enabled audit rejects a passing capture presented as a failing
baseline and verifies all hashes, source/C/ELF identities and receipts. Its
64 frozen source inputs now include the dispatched pipe usercopy helper,
which was missing from the prior inventory. The public inventory separately
uses the committed publication parent plus this change, excluding unrelated
dirty/staged edits. The prior self-contained f6358ec compiler, 15,146 input
pins and recovery record are reused. Corrected preview, baseline and native
fixture C are byte-identical; preflight/native/Linux ELFs match, and raw
preflight C drift is empty. The first preview's MAP_FAILED V type-check error
occurred before guest execution and is retained only as a diagnostic.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/pipeabi-after-aarch64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipeabi-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipeabi-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/pipeabi-after-x86_64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipeabi-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipeabi-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/pipeabi-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/pipeabi-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/pipeabi-lifetime-review.md).

Packet/watch queues, F_SETFL packet mode, partially constructed pipes under
descriptor exhaustion, concurrent publication/close races, limit-versus-pointer
precedence, concurrent credentials, physical exhaustion, named FIFOs,
GNU/translated/ELF32 paths and the three broad section 15 gates remain open.

## Native pipe construction under descriptor pressure

The native constructor now creates both endpoint descriptors privately. The
reader retains the pipe while the writer is constructed, so another thread
cannot close that private reader and free the object beneath construction.
Writer-construction refusal captures errno and releases the reader. A new
helper holds the descriptor-table lock, finds the two lowest free slots below
the current soft limit, grows the existing table if needed, and adopts both
references together. On refusal it changes neither slots nor output scratch;
the caller preserves errno and releases both private owners.

Previously the reader was installed before the writer was attempted. With
one free slot the writer returned EMFILE, leaving that reader open. The
fix changes constructor ownership and slot publication; existing allocation,
resource boxing, FD/Handle/Pipe unrefs, table growth and checked usercopy
implementations stay unchanged. Linux likewise returns its unused first
slot and both endpoint owners on a second-slot refusal in its
[pipe implementation](https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/b91872c56940950a6a0852e499d249c3091d4284/fs/pipe.c).
Linux copies results before installing the endpoints; Vinix's later usercopy
publication/rollback races are a separate boundary, not closed by this fix.

The `pipepair` musl probe runs root and UID/GID1000 cohorts. Soft limits of
48 and 64 are filled with CLOEXEC aliases, then zero, one, two or three
nonadjacent holes are reopened. Four ordinary pipe flag combinations and
five upper-register patterns exercise aligned, unaligned, address-one,
full-width bad-address, PROT_NONE, readonly and cross-page outputs. Nil is
excluded here because its descriptor-limit precedence remains unqualified.
Immediate table checks occur before repairing the known baseline leak;
only temporary filler holes can be repaired. Every query restores those
filler aliases and verifies the original 64-slot vector.

| Controls per root/UID cohort | Calls | Baseline failures |
| --- | ---: | ---: |
| Return/error, lowest-slot pairs, metadata/flags and real transfers | 1,120 | 0 |
| Immediate table state before cleanup | 1,120 | 280 |
| Applicable output canaries and restored filler aliases | 2,240 | 0 |
| Retained aliases, data/cursor, queued AB and original slots | 13 | 0 |

Both baselines fail 560 of 8,986 controls per architecture. Corrected Vinix
and actual Linux6.12.51 pass every row with the same native probe C/ELF;
child CASES and supervisor FINAL rows agree. Successful pairs temporarily
restore the original soft limit before creating all six original/dup/CLOEXEC
aliases, then verify FIFO0600, creator UID/GID, shared inode identity, exact
libc and raw 64-bit status flags, descriptor flags, nonblocking EAGAIN, ABC
transfers and EOF after every writer closes. Every known alias is closed
before filler restoration. Faulting ordinary copies may commit a prefix;
unchanged-output assertions apply to EMFILE, not EFAULT.

Two warmed and settled 200-cycle cohorts per architecture alternate full and
one-slot refusals, successful pair creation/aliases/transfers/close, and
cross-page copy faults. All 18 ARM/14 x86 slab classes and observed large
pages stay exactly flat: 68/68 ARM and 177/177 x86 for both credentials.
The existing AArch64 desktop harness separately runs ops/churn/cache and
idle/apps/drag on both frozen kernels. Its 36 operation rows and four
300-run churn programs retain zero bytes, and all three desktop scenarios
complete. Actual staged kernel, measurement ELF/source, desktop and config
are captured before VM cleanup; measurement/desktop inputs are identical
across controls. The automatic cache-pruning callback is skipped to protect
other sessions' build artifacts; production measurement, ISO preparation,
guest supervision and report validation remain in use. These are AArch64
memory/startup controls, not new x86 desktop-performance qualification.

Four production builds use detached worktrees at
d6a33ce248887d5dd8e400eb6d3b78d315a6567d. Removing only the constructor
body/prototype and the new pair-helper body/prototype makes entire generated
C identical to baseline. The helper has no new allocation, retention or
destructor, and all existing constructors/unrefs are byte-identical.
Independent review covers private ownership on each failure and synchronous
fixture stack/mapping borrows. The probe has sixteen explicit allocas and
zero hidden heap/index helpers. Both five-case profiles
(pipepair/pipeabi/access/open/runtime), eight host files and the 64-input
inventory pass. Allocation scans retain 400 ARM/292 x86 sites with identical
existing allowance refusals. Preflight/native/Linux ELFs and fixture C match;
the complete raw preflight C drift is empty.

Initial incomplete host preparations, a vanished mounted TMPDIR, an errno
assignment type check and an unavailable bounded-index helper are retained
as diagnostics. Their empty init/ISO hashes and host details do not establish
semantic baselines. Only fresh p4 profiles on private durable TMPDIR qualify
the final fixture. The assertion-enabled auditor rejects a passing capture
presented as a failing baseline, binds the final receipts and evidence, and
reuses the self-contained f6358ec compiler and its 15,146 input pins.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/pipepair-after-aarch64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipepair-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipepair-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/pipepair-after-x86_64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipepair-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipepair-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/pipepair-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/pipepair-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/pipepair-lifetime-review.md).
- [Baseline memory controls](../tests/linux-compat/results/2026-10-14/pipepair-perf-before-ops-result.json), [corrected memory controls](../tests/linux-compat/results/2026-10-14/pipepair-perf-after-ops-result.json), [baseline desktop](../tests/linux-compat/results/2026-10-14/pipepair-perf-before-desktop-result.json), [corrected desktop](../tests/linux-compat/results/2026-10-14/pipepair-perf-after-desktop-result.json).

The measured limits are below the initial 1,024 descriptor slots, so table
growth, its budget refusal and physical exhaustion require separate tests.
Concurrent prlimit/close, copy-before-publication and output-fault rollback
races, nil-versus-limit precedence, packet/watch semantics, GNU/translated/
ELF32 paths and the three broad section 15 gates remain open.

## Native pipe2 null-output error precedence

The native pipe2 wrapper now lets descriptor construction report errors before
checking a nil output destination. Previously a special early nil check
returned EFAULT even with zero or one free descriptor slot. Removing that
check gives EMFILE when two slots are unavailable. With sufficient slots,
the existing checked copy rejects nil and the existing cleanup closes both
endpoints before returning EFAULT. Invalid flag validation stays first.
Linux likewise constructs the endpoints and reserves two descriptor numbers
before copying the output in its
[pipe implementation](https://linux.googlesource.com/linux/kernel/git/torvalds/linux/+/aaed66fadba2d2de8fe0daa0aa3eac827d2076b9/fs/pipe.c).

The `pipenull` musl probe runs root and UID/GID1000 cohorts at soft limits
48 and 64, reopening zero through three nonadjacent holes in a filled table.
Four ordinary flag combinations and five upper-register patterns test eight
aligned, unaligned, inaccessible, readonly, cross-page, noncanonical and nil
destinations. Descriptor state is inspected immediately, before cleanup or
refilling the known holes. Writable successful pairs select the two lowest
holes; original, dup and CLOEXEC aliases verify metadata, creator ownership,
raw/libc status flags, descriptor flags, EAGAIN, ABC transfers and EOF.

| Controls per credential cohort | Calls | Baseline failures |
| --- | ---: | ---: |
| Errors and successful pair behavior | 1,280 | 80 |
| Immediate descriptor table state | 1,280 | 0 |
| Applicable output canaries and restored filler aliases | 2,560 | 0 |
| Retained aliases, data/cursor, queued AB and original slots | 13 | 0 |

Both baselines fail exactly 160 of 10,266 controls per architecture: only
the nil destination with fewer than two slots has the wrong errno. Corrected
Vinix and actual Linux 6.12.51 pass all rows with the same final native ELF.
Child CASES and parent FINAL counters agree. Refused pairs leave the table
unchanged, and every query restores the filler vector. Retained regular
bytes/cursor, nine aliases, metadata/flags, queued AB and all 64 original
descriptor slots survive. Faulting copies may write a prefix; unchanged
output assertions apply to EMFILE, not ordinary EFAULT.

Two warmed and settled 200-cycle cohorts per architecture repeat nil
EMFILE with zero/one free slots, a real pair with transfers/aliases/EOF
with two slots, and both cross-page and nil EFAULT cleanup with three slots.
All 18 ARM/14 x86 slab classes and observed large pages stay exactly flat:
68/68 ARM and 177/177 x86 for both credentials. The final fixture adds
the post-allocation nil cleanup call to the initial cohort; fresh p5
profiles, previews and Linux references bind that strengthened source.

Four production builds use detached worktrees at
d44681e1a45cb23eacfa8c3b85ab4bcc8b7f014b. Complete generated C outside
the checked wrapper body/prototype is byte-identical to baseline on both
architectures. Private pair construction, table adoption, checked-copy
helpers, ownership and destructors remain unchanged. Nil is rejected by
the existing user-range guard before any pagemap operation. The wrapper
keeps its existing synchronous two-i32 scratch; no allocation, observer or
asynchronous borrow is added. Independent review covers both construction
refusal and nil-copy cleanup, plus the final fixture stack/mapping lifetimes.

All six final guest cases (pipenull/pipepair/pipeabi/access/open/runtime),
eight host test files and 64-input inventories pass. Allocation scans retain
400 ARM/292 x86 sites and unchanged existing allowance refusals. The probe
has sixteen explicit allocas and no hidden heap/index helpers. Preview,
baseline, candidate and preflight C/ELF comparisons pass; complete raw
preflight C drift is empty. The assertion-enabled auditor rejects a passing
capture supplied as the failing baseline and binds the completed receipts,
review and reused f6358ec compiler with its 15,146 input pins.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/pipenull-after-aarch64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipenull-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipenull-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/pipenull-after-x86_64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipenull-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipenull-evidence-x86_64.json).
- [Audit](../tests/linux-compat/results/2026-10-14/pipenull-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/pipenull-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/pipenull-lifetime-review.md).

These limits remain below the initial 1,024 descriptor slots. Growth and
constructor-budget injection, concurrent prlimit/close, copy-before-
publication and user-copy rollback races, legacy x86 pipe, GNU/translated/
ELF32 paths and the three broad section 15 gates remain open. This change
adds pressure retention qualification, without new desktop performance claims.

## Native pipe-only fcntl type errors

Native `F_GETPIPE_SZ` and `F_SETPIPE_SZ` now return EBADF on nonpipe
descriptions. The capacity getter also refuses a missing pipe capability with
EBADF. Previously these guards returned EINVAL. Existing descriptor lookup,
O_PATH restrictions, lower-32-bit scalar decoding and final unrefs stay intact.
Linux checks for an actual pipe before dispatching these commands in its
[pipe implementation](https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable.git/+/refs/tags/v5.4.155/fs/pipe.c).

The `pipecmd` musl probe inherits a bank of 29 descriptions in root and
UID/GID1000 child cohorts: linked/unlinked regular files, a directory,
`/dev/null`, a UNIX stream socket, O_PATH, anonymous read/write ends and a
named FIFO. Original, dup and CLOEXEC aliases plus fixed descriptors 64/65
exercise raw and libc commands, five upper-register patterns, ignored getter
arguments, invalid descriptors, reduced soft limits 8/0 and closed/reused 66.
Positive setters request the current capacity, preserving occupied buffers.

| Controls per credential cohort | Calls | Original baseline failures |
| --- | ---: | ---: |
| Nonpipe raw command refusals | 950 | 800 |
| Actual pipe/FIFO getters | 250 | 0 |
| Setters, libc, invalid descriptors, limits and reuse | 338 | 62 |
| Retained metadata/flags/cursors/capacities/data/queues/slots | 48 | 0 |

Both original baselines fail exactly 1,724 of 3,172 checks per architecture.
Corrected Vinix and actual Linux 6.12.51 pass every row with the same final
native ELF. Child CASES and parent FINAL counters agree. Regular XYZ bytes
and cursor 1, queued AB/CD/GH, every alias and the 80-slot vector survive.
The errno correction is committed separately as `98c0df505`.

That intermediate kernel passes all semantics but fails storage: each
200-cycle cohort retains exactly 4,000 size-16 objects. The cycle makes
twenty successful capacity calls, each of which V heap-boxed an optional
`PipeCapacityResource` interface. An allocation-tracked AArch64 diagnostic
records two live call chains of 2,000 × 16 bytes, with zero dropped records;
generated C identifies the getter and setter boxes. Those failed receipts
remain published as diagnostics, separate from the original wrong-errno
baseline and final passing candidate.

Both capacity helpers now borrow local interface wrappers synchronously.
The fcntl lookup retains the underlying Pipe through delegation. Methods
return scalar capacities/options and never receive or retain the wrapper
address. No free, destructor, reference count, buffer allocation or resizing
algorithm is changed. Independent review covers this borrow and the fixture
bank, fork, count-transfer and stack lifetimes.

Final two warmed 200-cycle cohorts repeat alias/query/close operations,
nonpipe and invalid-descriptor errors, unchanged status and queued data.
All 18 ARM/14 x86 slab classes and observed large pages remain exactly flat:
75/75 ARM and 198/198 x86 for both credentials. Six ordinary production
builds in detached worktrees at `f6d7c868c15bee486447baea44d0ea04aaa215cf`
cover original, errno-only and final kernels; one additional tracked build
supplies the diagnostic. Complete generated C changes only the fcntl
body/prototype and two capacity helper bodies/prototypes. Comparing the
errno-only and final kernels confines differences to those two helpers,
which contain local wrappers and no hidden heap allocations.

Both final five-case guest profiles (pipecmd/fcntlabi/fcntlpath/open/runtime),
eight host test files and 64-input dispatch inventories pass. The capability
source is separately pinned in the evidence. Allocation scans retain
400 ARM/292 x86 reported sites and unchanged existing allowance refusals.
The probe has twelve explicit allocas and no hidden heap/index helpers.
Preview, baseline, candidate and preflight source/C/ELF identity passes;
complete raw preflight C drift is empty. Active audit controls reject a
passing capture presented as the failing baseline. The reused f6358ec
compiler and all 15,146 input pins remain bound.

Fresh AArch64 ops/churn/cache controls report zero retained bytes for every
200-call operation and all four 300-run churn workloads. Idle/apps/drag
controls complete with the actual staged corrected kernel, measurement
program, configuration, desktop binary and image hashes recorded.

- [AArch64 receipt](../tests/linux-compat/results/2026-10-14/pipecmd-after-aarch64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipecmd-reference-aarch64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipecmd-evidence-aarch64.json).
- [x86-64 receipt](../tests/linux-compat/results/2026-10-14/pipecmd-after-x86_64.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipecmd-reference-x86_64.json), [evidence](../tests/linux-compat/results/2026-10-14/pipecmd-evidence-x86_64.json).
- [Intermediate ARM storage failure](../tests/linux-compat/results/2026-10-14/pipecmd-errno-only-aarch64-native.log), [x86 storage failure](../tests/linux-compat/results/2026-10-14/pipecmd-errno-only-x86_64-native.log), [named allocation sites](../tests/linux-compat/results/2026-10-14/pipecmd-tracked-named_sites.log).
- [Audit](../tests/linux-compat/results/2026-10-14/pipecmd-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/pipecmd-audit.log), [independent review](../tests/linux-compat/results/2026-10-14/pipecmd-lifetime-review.md).
- [Memory controls](../tests/linux-compat/results/2026-10-14/pipecmd-perf-after-ops-result.json), [desktop controls](../tests/linux-compat/results/2026-10-14/pipecmd-perf-after-desktop-result.json).

The initial Linux reference image omitted `/dev/null`, causing setup failures
before any CASES rows. Adding character device 1:3 fixes the environment;
the native probe ELF is unchanged. Initial host compilation failures and
reference setup failures are not semantic baselines.

Requests that resize buffers, page-ring occupancy behavior, privileged
ceilings and budget injection, FIFO-shaped resources lacking the capability,
concurrent descriptor close/reuse/resize, legacy/GNU/translated/ELF32 paths
and the three broad section 15 gates remain separate.

## Native pipe capacity rounding and capability ceilings

`F_SETPIPE_SZ` now rounds up from the native page size, independently of the
4 KiB `PIPE_BUF` atomic-write limit. It rejects unsigned requests strictly
above 2 GiB with `EINVAL`; exactly 2 GiB reaches the permission check.
The 1 MiB ceiling applies when the normalized capacity grows beyond the
existing capacity and the caller lacks effective `CAP_SYS_RESOURCE`.
Existing oversized capacities can be retained or reduced after that bit is
cleared. These rules follow [Linux's pipe implementation](https://github.com/torvalds/linux/blob/v6.12/fs/pipe.c).
The existing byte-ring allocator, lock, charge rollback, data copy and free
paths are unchanged.

The `pipesize` musl probe runs four independent children: root with and
without the effective resource bit, and UID/GID1000 with and without it.
The ordinary privileged child retains permitted capabilities with
`PR_SET_KEEPCAPS`, then enables only the resource bit. The root child with
the bit cleared keeps its other capabilities, testing the specific authority
instead of treating UID0 or another capability as sufficient.

Each child inherits 29 descriptors: linked and unlinked regular files,
directory, `/dev/null`, UNIX socket, O_PATH, anonymous read/write ends and
named FIFO, each with original/dup/CLOEXEC aliases, plus fixed 64/65.
The five case groups contain 1,000 rounding controls, 722 overflow/type/error
controls, 194 privileged or 240 unprivileged ceiling controls, 28 actual data
controls and 48 final-state controls. Across the four children there are
8,060 checks per architecture.

| Kernel | Native page | Checks | Original failures | Normalization-only failures | Final failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- | --- | --- |
| AArch64 | 16 KiB | 8,060 | 3,144 | 376 | 0 | 0 |
| x86-64 | 4 KiB | 8,060 | 1,404 | 376 | 0 | 0 |

Original AArch64 failures are 435 rounding and 257 overflow failures per
child, plus 188 ceiling failures in each privileged child. Original x86-64
has the same overflow and ceiling failures. The separately committed
normalization fix removes rounding/overflow failures on both architectures;
the capability fix removes the remaining 376 failures. Linux 6.12.51 references
execute the exact final native ELF, with 4 KiB pages on both reference guests.

Controls include raw upper-register patterns and libc calls, bad descriptors,
reduced descriptor limits 8/0 and closed/pipe/regular reuse of descriptor 66.
Nonpipe descriptions retain their `EBADF` precedence. Successful resizing
updates every alias without changing metadata, flags, cursors or queued
AB/CD/GH bytes. Refusals retain the previous capacity and data. A fresh
anonymous pipe and the inherited named FIFO exercise wrapped QRST data
across growth, a full two-page ring's `EBUSY` refusal, and successful shrinking
after only one occupied page remains. Privileged controls grow actual
two-byte queues to 2 MiB; capability removal permits same-capacity requests,
refuses subsequent growth, and permits shrinking below the ceiling.
Exactly 2 GiB is tested without the capability (`EPERM`), avoiding a
privileged multi-gigabyte allocation.

After 32 warmups, each final credential cohort runs 200 resize/alias/close
cycles. All 18 AArch64 and 14 x86-64 slab classes and large-page counts stay
exactly flat. The normalization-only unprivileged cohorts also stay flat;
privileged storage qualification waits for the completed capability fix.
Six production builds, seven native guest cases per architecture
(pipesize/pipecmd/fcntlabi/keepcaps/capset/open/runtime), eight host test files,
64 frozen dispatch inputs and complete generated-C comparisons are bound.
Only normalization and capacity setter bodies/prototypes differ. Allocation
scanning reports 398 AArch64 and 290 x86-64 sites before and after, with the
same existing allowance refusals; the allowance check remains a reported
failure rather than a whole-kernel allocation approval.

The V audit is compiled without `-prod`. Deliberately failing assertions and
a passing-capture-as-failing-baseline control both exit 1, and the real audit
passes. Source, generated C, probe ELF, kernels, Linux wrappers, serial logs,
tool inputs and receipts are SHA256-bound. Independent lifetime review checks
the inherited descriptor/Handle pin, synchronous capability access, locked
ring borrowers, replacement copy before free, charge rollback and stack/mmap
fixture borrowers. Fresh corrected AArch64 ops/churn/cache and idle/apps/drag
controls are bound separately.

Preparation diagnostics are retained separately: the first pointer-type
compile failure, an unavailable generated bounds helper, an unstaged ARM
intermediate build and the earlier probe's uninitialized Bank field.
Their earlier guest captures are diagnostic records; the final semantic
baselines and references use the zero-initialized probe.
An earlier preflight differs only in unused stderr helpers, with identical
probe ELFs. Its raw C drift is retained. Repeating the preflight with the
explicit pinned compiler yields byte-identical raw C and ELFs on both
architectures; the audit binds both records separately.

Linux page-slot occupancy for fragmented small writes, per-user pipe-page
soft/hard accounting, a mutable `/proc/sys/fs/pipe-max-size`, watch queues,
concurrent resize/close, budget-failure injection and privileged requests
above the tested 2 MiB range remain unqualified. The native musl receipts do
not qualify glibc, translated or 32-bit pipe paths or close the broad section 15
semantics, installation/sandbox or architecture acceptance gates.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/pipesize-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/pipesize-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipesize-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/pipesize-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/pipesize-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/pipesize-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/results/2026-10-14/pipesize-audit.v), [verdict](../tests/linux-compat/results/2026-10-14/pipesize-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/pipesize-lifetime-review.md).

## Native scheduler scalar words and error precedence

The six legacy scheduling syscalls decode native PID/policy arguments as
signed 32-bit values. `sched_getparam`, `sched_setparam` and
`sched_setscheduler` reject negative PIDs and NULL parameter pointers with
`EINVAL`; the policy setter also rejects a negative policy first. Setters
import the four-byte priority before target lookup, returning `EFAULT`
for unreadable input even when a nonnegative PID does not exist. Getters
look up the target before copying output. These rules follow
[Linux's scheduler syscall implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).
The existing target locks, copied scheduling parameters, permission checks,
user-copy implementation and queue mutations are unchanged.

Two native musl children, root and UID/GID1000, each run 2,738 checks.
The full matrix has 4,600 kernel-facing/state checks and 876 explicit
`ENOSYS` checks for the bundled musl's four legacy process wrappers.
Those wrappers are deliberate libc stubs; they do not exercise the kernel.
The probe uses real raw syscalls for setup and policy/priority observations,
and the actual musl priority-min/max wrappers for their supported calls.

| Architecture | Checks | Original failures | Error-only failures | Decoded failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- | --- |
| AArch64 | 5,476 | 2,460 | 1,308 | 0 | 0 |
| x86-64 | 5,476 | 2,460 | 1,308 | 0 | 0 |

Each original credential cohort fails 124 low-word error checks and 1,106
upper-word checks. The separately committed error fix removes all low-word
failures and leaves 654 upper-word failures per cohort. Signed argument
decoding removes the remaining failures. Linux 6.12.51 on both architectures
executes the identical final native probe ELF and passes every row.

Six PID classes cover zero, self, negative, minimum signed32, maximum
signed32 and an actually reaped child. Raw arguments use the ordinary
sign extension and four independent PID/policy upper-word patterns.
Nine parameter forms include aligned/unaligned guarded stack storage,
nonzero priority, NULL, address 1, inaccessible and readonly native pages,
cross-page input and a full-width invalid pointer. Other/BATCH transitions
and priority bounds are real calls. Invalid policies use value 8, negative
values and the signed32 minimum. Rejected calls retain observed policy,
priority and buffer guards; successful getters return exactly four bytes.
No arbitrary failed-copy prefix or complete scheduling-state assertion is
made.

After 32 warmups, both error-only and decoded kernels repeat 200 cycles per
credential cohort, including BATCH/OTHER transitions, getters, priority
updates and actual NULL/missing-target/input faults. All 18 AArch64 and 14
x86-64 slab classes and large pages remain exactly flat: 63/63 ARM and
160/160 x86. Six ordinary production builds use detached worktrees frozen
at `108082c1e0513e87559e47fde420471ccc2f15f7`. Complete generated C is
identical outside the three error-handling bodies/prototypes in the first
fix and six legacy scheduling bodies/prototypes in the completed change.
The new locals and existing copy buffers are genuine stack values.

Both decoded five-case native profiles
(schedabi/runtime/capabi/open/fcntlabi), eight host test files and the
64-input frozen inventories pass. Allocation scans report 398 ARM/290 x86
sites before and after with identical existing allowance refusals; they
do not approve the whole kernel's allocation policy. Independent lifetime
review checks synchronous pointer borrows, copied target parameters,
scratch mappings, stack arguments, pipe transfer and child cleanup.
The V auditor is compiled without `-prod`; false assertions and a passing
capture presented as the failing baseline both execute and exit 1.

The existing small scheduler-QoS workload passes on corrected x86-64.
Both original and corrected AArch64 kernels pass its legacy hints/timer
slack stage, then fail CPU 1 affinity with `EINVAL`. Both boot logs report
`skipping SMP (no device tree)` despite QEMU requesting four CPUs.
Their identical QoS probe ELF and separate kernel/input/serial hashes are
published. AArch64 multi-CPU QoS remains unqualified.

Preparation failures are retained separately. The first probe used musl's
stub wrappers for setup and failed before any case rows. A later probe
incorrectly treated policy 7 as invalid: actual Linux recognizes
`SCHED_EXT` for priority bounds and exposed 24 oracle errors per architecture.
The final probe uses invalid policy 8 and fresh original/error-only/decoded/
Linux captures. Earlier preflight C/ELF fingerprints remain visible.

Realtime/deadline mutations, reset-on-fork, capability/RLIMIT permission
rules, SCHED_EXT behavior, namespace/pledge decoding, concurrent target
reuse and general scheduler state remain separate. RR-interval,
attribute and affinity argument/error ABIs, glibc, translation, ELF32 and
the three broad section 15 acceptance gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/schedabi-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/schedabi-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/schedabi-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/schedabi-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/schedabi-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/schedabi-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/schedabi-check.v), [verdict](../tests/linux-compat/results/2026-10-14/schedabi-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/schedabi-lifetime-review.md).
- [x86 QoS receipt](../tests/linux-compat/results/2026-10-14/schedabi-qos-after-x86_64-inputs.json), [AArch64 original failure](../tests/linux-compat/results/2026-10-14/schedabi-qos-before-aarch64-serial.log), [AArch64 decoded failure](../tests/linux-compat/results/2026-10-14/schedabi-qos-after-aarch64-serial.log).

## Native SCHED_EXT priority metadata

`sched_get_priority_min(7)` and `sched_get_priority_max(7)` now return zero,
matching Linux's fixed SCHED_EXT priority metadata. Linux defines policy 7
in its [UAPI](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/sched.h)
and returns these bounds independently of class availability in its
[scheduler queries](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).
This change recognizes that metadata; installing or running a SCHED_EXT/BPF
scheduler remains unsupported, and the setter validation is unchanged.

The native `schext` probe runs independent root and UID/GID1000 children.
Sixteen policies cover ordinary, FIFO, RR, BATCH, IDLE, DEADLINE, EXT,
reserved policy 4, unknown policy 8, negative and signed32 limits, and
RESET_ON_FORK combinations. Each bound uses six raw register-word forms
and the actual musl libc function. Raw calls also pass ignored extra
arguments. FIFO/RR retain their 1/99 range; valid nonrealtime metadata
returns zero and invalid policies return `EINVAL`. Queries leave observed
policy and priority unchanged. The probe makes no scheduling-class
availability inference from a successful metadata query.

Each credential cohort records 180 raw existing/invalid-policy checks,
14 EXT raw/libc checks, 30 other libc checks and one final state control.
Across both children there are 448 bounds queries and two state controls.

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 450 | 28 | 0 | 0 |
| x86-64 | 450 | 28 | 0 | 0 |

Both original kernels fail only the 14 EXT queries per credential cohort.
All other controls pass. Corrected Vinix and actual Linux 6.12.51 references
execute identical architecture-specific probe ELFs and pass every row.
Preview, final preflight and both native phases have byte-identical raw C.

After 32 warmups, two corrected credential cohorts repeat 200 cycles of
raw/libc EXT queries, flagged-policy errors, FIFO bounds and state checks.
All 18 ARM and 14 x86 slab classes stay flat, with large pages 63/63 ARM
and 160/160 x86. Four fresh ordinary production builds use detached
worktrees at `4142e9a49e2a4b317272e73cc98c5b698cad8d4f`. Complete generated C
differs only in the two pure query bodies and one scalar constant macro;
each body adds only the EXT zero-bound predicate. Setters, queue operations,
target lookup, user-copy and allocation code are unchanged.

Both five-case corrected guest profiles
(schext/runtime/schedabi/open/fcntlabi), eight host test files and frozen
64-input inventories pass. Allocation scans retain 398 ARM/290 x86 sites
and the same existing allowance failures; whole-kernel allocation approval
is not claimed. Independent review checks genuine stack scalars, fixed
arrays, synchronous pointer borrows, the 64-byte result-pipe handoff,
descriptor cleanup and child reaping. The V audit executes both a false
assertion and a passing-capture-as-baseline negative control without `-prod`.

The first standalone preflight failed compilation because safe fixed-array
loops emitted an unavailable bounds helper. Its raw C and replayed compiler
errors are retained as preparation evidence. Explicit literal-bounded loops
produce the final C with six allocas and no heap/index helpers. No failed
preflight is counted as a syscall result.

Class registration/BPF programs and runtime behavior, scheduler permissions,
realtime mutations, target races, glibc and translated/ELF32 paths remain
separate. The previously reported AArch64 multi-CPU QoS blocker and all
three broad section 15 acceptance gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/schext-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/schext-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/schext-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/schext-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/schext-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/schext-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/schext-check.v), [verdict](../tests/linux-compat/results/2026-10-14/schext-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/schext-lifetime-review.md).

## Native RR interval PID words and output errors

`sched_rr_get_interval` now decodes the native signed32 `pid_t` before
resolving a task, and resolves that task before accessing its output buffer.
Negative PIDs return `EINVAL`; absent and fully reaped tasks return `ESRCH`,
including when the interval pointer is null or inaccessible. A valid task
with an invalid output pointer returns `EFAULT`. Linux follows this order in
its [RR query implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).
The existing task lookup, copied scheduling parameters, lock scopes and
timespec copy remain unchanged.

The native `rrabi` V probe runs independent root and UID/GID1000 children.
Each child starts with a real RR task at priority1, queries through raw
syscalls and the genuine musl `sched_rr_get_interval` wrapper, and switches
back to OTHER before the guarded error matrix. RR installation happens
while privileged; the ordinary cohort queries its own task after dropping
credentials. The probe does not infer unprivileged RR-install permissions
from successful queries. Unlike musl's obsolete process scheduler wrappers,
this musl function invokes the native syscall.

Six PID targets include implicit and explicit self, two negative signed32
values, a guaranteed absent positive value and a fully reaped child. Each
target uses the ordinary signed word, six varied upper-word patterns and
a libc call. Ten output forms cover aligned/unaligned buffers, an exactly
page-ending timespec, null/address1, read-only and inaccessible pages,
read-only/inaccessible and writable/read-only crossings, and a pointer with
an invalid upper address bit. Guards and read-only bytes remain unchanged;
a valid task's faulting cross-page copy may write its accessible prefix.
Task validation errors must leave even that prefix untouched. All output
pointers retain their full native width.

Each cohort records 60 ordinary-word queries, 360 varied-upper-word queries,
60 libc queries, 16 real RR queries and three final state/guard controls.
The two cohorts total 992 syscall/wrapper checks plus six final controls.

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 998 | 520 | 0 | 0 |
| x86-64 | 998 | 520 | 0 | 0 |

Original kernels have the same per-cohort failure vector `4/240/4/12`.
Their ordinary raw and libc failures expose null-output error precedence;
upper-word and RR failures expose the native PID decoder. Final policy,
priority and buffer controls remain intact. Corrected Vinix and actual
Linux 6.12.51 execute identical architecture-specific probe ELFs and pass
every row. Preview, preflight and both native phases have identical raw C.

Interval duration depends on the scheduler and its configuration. Native
controls retain Vinix's 5ms RR quantum and zero OTHER interval. Linux
references require normalized nonnegative OTHER and positive RR timespecs,
without requiring those durations to match Vinix. Other policy intervals,
fair-task timing and the query's relationship to actual CPU entitlement
need separate qualification.

After 32 warmups, both corrected cohorts repeat 200 cycles of raw/libc self
queries, varied PID words, negative/missing-task precedence, bad-pointer
errors and retained policy/priority. All slab classes and large-page counts
stay flat. The probe holds and closes one slab observer per cohort and
unmaps its three-page guard region before reporting.

The first corrected profiles exhausted host disk space after five completed
cases. ARM's final fcntlabi ISO build explicitly failed with `ENOSPC`; the
x86 driver could not save its aggregate log, leaving five completed receipt
rows. The original receipts, completed probe artifacts and ARM failure log
remain retained and are bound separately as preparation diagnostics. A V
cleaner verified all 108 completed probe files byte-identical before removing
18 disposable boot-staging/NVRAM paths. Fresh corrected profiles in new
directories provide the complete six-case verdicts below.

Four original/final production build captures use isolated worktrees at
`509d83f1903c9b968bd942a487754f16356e2a73`. Two earlier corrected builds,
followed by a source-comment clarification, have identical generated C;
their build logs and C remain retained. Full generated kernel C differs
only in the RR query prototype/body: the PID cast replaces the early null
guard. No allocator, mutation, queue, lookup, lock or user-copy helper changes.
The final standalone probe C has eight allocas and no heap/index helpers.

Both six-case profiles (rrabi/runtime/schedabi/schext/open/fcntlabi), eight
host test files and frozen 64-input inventories pass. Allocation scans retain
398 ARM/290 x86 sites and the same existing allowance failures; this does
not qualify the whole kernel's allocation policy. The maintained V auditor
pins compiler/source/C/ELF/kernel/ISO/capture inputs and executes a false
assertion and a passing-reference-as-baseline refusal without `-prod`.
Independent review checks the existing copied kernel value, synchronous
stack borrows, guarded mapping lifetime, observer cleanup, child reaping and
the exact 64-byte result handoff.

Cross-task permissions/races, namespaces/pledge, realtime/deadline admission
and timing, attribute/affinity ABIs, glibc and translated/ELF32 paths remain
separate. The previously published AArch64 multi-CPU QoS blocker and all
three broad section 15 acceptance gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/rrabi-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/rrabi-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/rrabi-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/rrabi-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/rrabi-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/rrabi-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/rrabi-check.v), [verdict](../tests/linux-compat/results/2026-10-14/rrabi-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/rrabi-lifetime-review.md).

## Native scheduling-attribute query prefixes and errors

`sched_getattr` now decodes the native signed32 `pid_t`, validates null output,
negative PID, flags and the 48..PAGE_SIZE request bounds before lookup, and
copies exactly `min(request_size, 56)` bytes. Thus a 53-byte request receives
53 bytes and a reported size of 53; its remaining buffer stays untouched.
Requests above the native page size return `EINVAL`, rather than succeeding
with a fixed-size copy. Missing/reaped tasks return `ESRCH` before output
faults. The full advertised range must fit the user address half, including
when the actual known prefix is shorter. Existing parameter value copies,
PID-table locks, metadata construction and user-copy helpers are unchanged.
Linux specifies this query and copy order in its
[scheduler implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).

The `attrquery` V probe runs separate root and UID/GID1000 children. Each
installs RR priority1 while privileged, queries it after any credential
drop, switches to BATCH for six controls, then restores OTHER before the
main error matrix. It uses the real musl `syscall` function; this does not
qualify a dedicated glibc or musl scheduling-attribute wrapper. Observed
policy, priority, ordinary nice, flags, deadline fields and returned byte
prefixes are checked. Native fair runtime stays at its existing zero value;
Linux fair slice and clamp defaults depend on its configuration and are
validated separately from native constants.

Six targets include implicit/explicit self, two negative signed32 values,
a guaranteed absent positive PID and a fully reaped child. Sixteen sizes
cover zero, undersized values, every prefix from 48 through 57 bytes, the
native page size, one byte above it and UINT32_MAX. Ten output forms include
aligned/unaligned buffers, an exactly page-ending prefix, null/address1,
read-only and inaccessible pages, two page-crossing faults and a full-width
invalid pointer. Flags0/1 distinguish valid requests from reserved flags.
Canonical words, two upper-PID patterns and separate upper size/flag words
exercise signed32 PID and unsigned32 request arguments without narrowing
output pointers. Prefix guards and read-only bytes stay unchanged. A valid
task's cross-page fault may write its accessible prefix; input/target errors
must leave even that prefix untouched.

Each cohort records 1,920 ordinary-word, 3,840 upper-PID and 1,920 upper
size/flag controls, plus ten RR queries, six BATCH queries, four user-range
controls and three final state/guard checks. This totals 15,400 query calls
and six final controls across both cohorts.

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 15,406 | 3,040 | 0 | 0 |
| x86-64 | 15,406 | 3,040 | 0 | 0 |

Both original kernels have the same per-cohort failure vector
`210/1092/210/8`, including short-prefix, null/size, PID-word and full-range
errors. Corrected kernels and actual Linux 6.12.51 execute identical final
architecture-specific probe ELFs and pass every row. Preview, preflight and
both final native phases have byte-identical C. Native request caps reflect
16 KiB AArch64 and 4 KiB x86 pages; both supplied Linux references use 4 KiB.

Boundary controls map the highest usable page with MAP_FIXED_NOREPLACE,
verify the returned address exactly, and unmap it before storage measurement.
A 56-byte prefix fits at its end; advertising 57 bytes or a full page must
return `EFAULT` without writing that prefix. A missing task still returns
`ESRCH` before checking this range. Vinix selects user limits of `2^47` ARM
and `2^56` x86 in these captures. Linux selects `2^48` ARM and `2^47 - 4096`
x86. Linux x86's
[TASK_SIZE_MAX definition](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/asm/page_64_types.h)
reserves its top page; treating the limit as an unadjusted power of two
caused the first x86 reference to fail boundary setup with `ENOMEM`. Its
receipt, complete serial and aggregate log remain preparation evidence.
The corresponding initial ARM reference passes, but final qualification
uses fresh captures and identical final probe ELFs on both architectures.
Earlier preflight C/ELFs, before exact mapping verification and the reserved
page fallback, remain pinned separately. A setup failure supplies no complete
semantic verdict.

After 32 warmups, both corrected credential cohorts repeat 200 cycles of
53-byte queries, upper PID words, negative/missing-task precedence, null
output, oversized requests and observed state. All 18 ARM and 14 x86 slab
classes stay flat, with large pages 63/63 ARM and 160/160 x86. The observer FD
closes on every nonfatal path, and the three-page guard mapping remains
owned through all checks before being unmapped. Final probe C has eleven
allocas and no heap, dynamic-array or index helpers.

Four fresh original/corrected production builds use isolated worktrees at
`8175c29c1559cad97f58820770d6e88c5befaa38`. Complete generated C differs only
in this getter prototype/body: signed32/input guards, exact prefix length
and the full-range predicate. All other getter work, scheduler setters,
queues, locks, allocator and copy helpers are unchanged. Both six-case
profiles (attrquery/runtime/schedabi/rrabi/open/fcntlabi), eight host test
files and frozen 64-input inventories pass. Allocation scans retain the
same 398 ARM/290 x86 sites and existing allowance failures; whole-kernel
allocation approval is not claimed. A V watchdog retires only completed
unbound boot staging while rechecking every retained probe input hash.

The maintained audit binds compiler/source/C/ELF/kernel/ISO/capture inputs,
actual reference receipts, exact counts and ranges, flat storage, preparation
artifacts and independent lifetime review. Its false assertion and
passing-reference-as-baseline controls execute without `-prod` and require
exit 1. Review checks genuine stack values, synchronous borrows, both mapping
lifetimes, observer cleanup, child reaping and the exact 64-byte result pipe.

Setter semantics, nondefault nice/reset/clamp/deadline state, peer permissions,
races, namespaces/pledge, glibc and translated/ELF32 paths remain separate.
The AArch64 multi-CPU QoS blocker and the three broad section 15 acceptance
gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/attrquery-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/attrquery-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/attrquery-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/attrquery-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/attrquery-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/attrquery-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/attrquery-check.v), [verdict](../tests/linux-compat/results/2026-10-14/attrquery-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/attrquery-lifetime-review.md).

## Native scheduling-attribute import contract

`sched_setattr` now narrows native PIDs to signed32 and returns `EINVAL` for
negative PIDs, null input or reserved syscall flags before accessing input.
It imports attributes before resolving the target. Zero size means the
original 48-byte layout; other sizes below 48 or above the native page limit
return `E2BIG`, with a best-effort writeback of the supported 56-byte size.
Read-only writeback failures retain `E2BIG`, matching Linux's documented
[scheduler copy implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).

Short layouts copy exactly their advertised bytes into a zero-initialized
stack value. Larger layouts must contain only zero bytes after byte 56.
The extension is checked first, using aligned 64-bit reads and masks for
the first/last word, as in Linux's
[copy_struct_from_user](https://github.com/torvalds/linux/blob/v6.12/include/linux/uaccess.h)
and [check_zeroed_user](https://github.com/torvalds/linux/blob/v6.12/lib/usercopy.c).
An early nonzero extension returns `E2BIG` before a later inaccessible word;
an unreadable zero extension returns `EFAULT`. Negative policy values and
clamp flags in layouts shorter than 56 return `EINVAL` before target lookup.
Other existing scheduling validation and mutations retain their prior order.

The `attrimport` V fixture runs separate root and UID/GID1000 children. Six
PID classes cover implicit/explicit self, two signed32 negatives, an absent
positive PID and a fully reaped child. Sixteen sizes cover zero, undersized
values, every length 48..57, PAGE_SIZE, PAGE_SIZE+1 and UINT32_MAX. Twelve
input forms include aligned/unaligned writable storage, read-only storage,
null/address1, inaccessible/full-width invalid pointers, exact and partial
page-ending inputs, nonzero extensions and a nonzero word before a later
inaccessible page. Reserved syscall flags and three upper-word forms qualify
signed32 PID and unsigned32 flag handling without narrowing pointers.

Each call checks its actual errno, BATCH/OTHER policy and priority, retained
known input bytes and the preceding guard. Only writable `E2BIG` inputs may
change their four-byte size; successful imports retain their original header,
including size zero. Extension guards stay unchanged. Successful calls make
real BATCH transitions, which the unchanged legacy setter restores to OTHER.
Thirty-six extra controls per cohort check negative policies, short clamp
layouts and unknown attribute flags across target/upper-word forms; three
final controls check restored state and guards.

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 18,510 | 5,324 | 0 | 0 |
| x86-64 | 18,510 | 5,324 | 0 | 0 |

Counts per cohort are `2304/4608/2304/39`; original failures are
`414/1814/414/20`. Both original and corrected kernels and actual Linux
6.12.51 use identical final architecture-specific probe ELFs. Native size
caps follow 16 KiB ARM and 4 KiB x86 pages; Linux references use 4 KiB pages.
This uses real musl `syscall`, with no dedicated libc wrapper claim.

Both corrected cohorts run 32 warmups followed by 200 import/error/state
cycles, with thirteen-second settling intervals around storage snapshots.
All 18 ARM and 14 x86 slab classes and large-page totals stay exactly flat.
The observer FD closes on every nonfatal path. A four-page mapping owns
guarded inputs through the matrix and observation; only three pages are
accessed, and the entire mapping is unmapped before reporting. Final probe
C has nine explicit allocas and no heap, dynamic-array or index helpers.

Four fresh production builds use isolated worktrees at
`9e884558a291c38cbf550fc85a90052ecdb04e80`. Full generated C differs only in
the setter and the two synchronous scalar import helpers, including their
prototypes. The existing mutation tail matches exactly after removing the
relocated clamp-size guard and normalizing the compiler's two scratch names
for the existing deadline division. Scheduler queues, permissions, locks,
allocator, user-copy helpers and the preceding getter fix are unchanged.
Both seven-case profiles (attrimport/runtime/schedabi/rrabi/attrquery/open/
fcntlabi), eight host files and four frozen inventory checks pass. Allocation
scans retain identical 398 ARM/290 x86 sites and existing allowance refusals;
whole-kernel allocation approval is not claimed.

The first fresh builds failed when concurrent host use exhausted disk space,
including missing generated symlinks. Their full logs remain preparation;
fresh builds after space recovered provide the actual kernels. Initial
Linux references then exposed a fixture expectation error: a PAGE_SIZE input
starting eight bytes into the read-only page reaches the following PROT_NONE
page, so `EFAULT` precedes lookup. Those receipts record 32 failed controls
per architecture. Their native/preflight C and ELFs and full reference logs
are retained separately. The corrected oracle supplies fresh native and
Linux captures; failed preparation supplies no passing semantic verdict.

The maintained V auditor binds compiler/source/C/ELF/kernel/ISO and reference
inputs, complete counts, storage, preparation and independent lifetime review.
Its false assertion and passing-reference-as-baseline controls execute without
`-prod` and require exit 1. Independent review also checks alignment masks,
synchronous stack borrows, guarded mappings, child reaping and descriptor
cleanup. A bounded watchdog retires completed unbound boot staging while
rehashing every retained input.

Nice-value clamping, complete attribute flags/clamps/classes/runtime behavior,
peer permissions, capabilities/RLIMITs, races, namespaces/pledge, glibc and
translated/ELF32 paths remain separate. The existing ARM multi-CPU QoS blocker
and the three broad section 15 acceptance gates stay open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/attrimport-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/attrimport-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/attrimport-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/attrimport-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/attrimport-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/attrimport-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/attrimport-check.v), [verdict](../tests/linux-compat/results/2026-10-14/attrimport-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/attrimport-lifetime-review.md).

## Native affinity masks, argument words and stable-peer permissions

Native `sched_getaffinity` and `sched_setaffinity` now decode PIDs as signed32
and lengths as unsigned32 while retaining full-width buffer pointers. The
getter validates whole-word length and Linux's wrapping unsigned32 bit-count
multiplication before looking up the target. Negative and absent targets
return `ESRCH`; valid targets retain real output `EFAULT` behavior.

The setter imports `min(length, 8)` bytes into a zeroed stack mask before
lookup. Short masks are zero-extended and zero-length masks do not access
their pointer. Target lookup and permission checks precede empty-mask
validation. Stable peers require the caller's effective UID to match the
target's real/effective UID, or an effective `CAP_SYS_NICE`; UID0 alone does
not authorize a different owner. Existing MAC checks and the final locked
mask mutation remain in force. The new permission helper borrows target and
owner pointers only while holding the PID-table lock and returns scalar errno.
This follows Linux's [affinity syscall implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).

The V `affabi` probe runs separate root and UID/GID1000 cohorts. Each owns a
blocked UID/GID1001 peer and a real waiting pthread whose non-main TID is
reported through a pipe. Eight target classes cover implicit/explicit self,
that worker, two signed32 negatives, a guaranteed absent positive PID, a
fully reaped child and the differently owned peer. Nineteen lengths include
zero, every short length, whole-word and larger buffers, unsigned32 wrap
boundaries and UINT32_MAX. Ten buffer forms cover aligned/unaligned storage,
page-ending prefixes, null/address1, inaccessible/read-only pages, crossing
faults and a full-width invalid pointer. Upper PID and length words are tested
separately. Three masks cover empty, the lowest available CPU and an extra
unavailable high bit. Every live operation checks the resulting CPU mask;
successful setters are restored before the next case.

Additional controls toggle only effective capability23, exercise both errno
and successful cross-owner authorization, and call genuine musl affinity wrappers.
The libc getter must return zero and clear the requested unused tail. Three
final mask checks and a full capability snapshot comparison confirm restoration.
Each cohort records `6080/12160/6080/388` checks: 24,608 raw calls, 96 wrapper
calls and four final state controls.

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 49,416 | 27,868 | 0 | 0 |
| x86-64 | 49,416 | 27,868 | 0 | 0 |

Original failure vectors are `3098/8336/2302/198` per cohort. Final native
original/corrected kernels and actual Linux 6.12.51 execute identical probe
ELFs for each architecture. Both native bitmap widths are exactly eight
bytes. The Linux references have eight-byte ARM and 32-byte x86 bitmaps,
despite both exposing only CPU0/CPU1. A bounded 4096-byte discovery query
verifies the returned width, zero higher active-mask words and output guards;
native width is separately required to remain eight. Raw queries then check
exact clipped lengths and zero tails. Imports and page-ending faults follow
the measured width. Only the lowest available CPU is selected: native ARM
reports mask1, native x86 and both references mask3. This leaves the existing
ARM CPU1/QoS blocker unqualified. Native pages are 16 KiB ARM/4 KiB x86;
both references use 4 KiB pages.

An earlier probe assumed eight-byte Linux bitmaps. Its ARM reference passes,
but x86 records 2,304 failures: larger raw queries copy more bytes, and a
nine-byte page-ending input reaches an inaccessible page. Those old native
probe inputs and reference receipts/logs remain preparation. Initial wrapper
preflights also rejected untyped byte pointers; their generated C is retained
and no ELF or semantic verdict exists. Earlier eight-case profiles encountered
host `ENOSPC` after the affinity case passed. Their full receipts/aggregates
retain partial build failures; fresh final profiles provide acceptance.

Both corrected cohorts run 32 warmups and 200 cycles of short-mask mutation,
upper words, cross-owner denial/authorization, empty-mask/missing-target and
getter errors, with settling intervals around storage snapshots. All 18 ARM
and 14 x86 slab classes stay exactly flat, as do large pages 71/71 ARM and
175/175 x86. The slab observer closes on every nonfatal path. The worker's
stack context remains live through `pthread_join`; the peer is released and
reaped, command descriptors close, and the three-page guard mapping is fully
unmapped before reporting. Final probe C has twenty allocas and no heap,
dynamic-array or fixed-index helpers.

Four fresh production builds use isolated worktrees at
`16be6d0a204b509c75d456930af478de0232c36b`. Full generated C differs only in
the two affinity prototypes/bodies, the scalar permission helper/prototype
and capability23 define. CPU filtering, final mutation, scheduler locks and
queues, allocator and user-copy implementations otherwise match exactly.
Both final eight-case profiles (affabi/runtime/schedabi/rrabi/attrquery/
attrimport/open/fcntlabi), eight host files and four frozen inventory checks
pass. Allocation scans retain the same 398 ARM/290 x86 sites and existing
allowance failures, with exactly two existing diagnostic positions shifted
one line by the new constant; whole-kernel allocation approval is not claimed.

The maintained V audit binds compiler/source/C/ELF/kernel/ISO/reference inputs,
complete counts, topology/widths, guards, storage, preparation and independent
lifetime review. Its false assertion and passing-reference-as-baseline controls
execute without `-prod` and require exit1. Completed boot staging is retired
only after hashing and rechecking retained inputs, including failed preparations.

Permission and mutation use separate table-lock intervals. Credential changes,
exit/TID reuse races, independent per-thread capability changes, nested PID/user
namespaces, pledge/MAC denial, cpusets/cgroups, CPU hotplug and masks beyond 64
native CPUs remain unqualified. Physical scheduling placement, migration and
fairness, glibc and translated/ELF32 paths also remain separate. The three
broad section15 acceptance gates stay open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/affabi-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-14/affabi-after-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/affabi-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/affabi-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-14/affabi-after-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/affabi-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/affabi-check.v), [verdict](../tests/linux-compat/results/2026-10-14/affabi-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/affabi-lifetime-review.md).

## Native scheduling-attribute nice normalization and admission

Native `sched_setattr` now clamps imported signed32 nice values to -20..19,
as Linux does during [attribute import](https://github.com/torvalds/linux/blob/v6.12/kernel/sched/syscalls.c).
OTHER/BATCH requests apply the admitted value instead of silently succeeding
without changing nice. Lowering nice requires the target's `RLIMIT_NICE`
soft limit to admit `20 - wanted`, or effective `CAP_SYS_NICE`. The caller's
effective UID must match the target's real/effective UID unless that capability
is effective. Existing MAC checks remain in force. UID0 alone no longer grants
the shared scheduling permission helper's privilege bypass. Native default
nice limits are now soft 0/hard 0, matching the observed Linux references.
IDLE/FIFO/RR requests leave nice unchanged regardless of the attribute value.

Permission checks precede policy mutation. The new scalar helper holds the
PID-table lock while borrowing the target and owner, returning only errno.
Its emitted C has one lock and six compiler-emitted unlock sites, including
the unreachable final defer. These changes add no kernel allocation or free.
Vinix still stores nice on the process; this qualification uses single-thread
process leaders and establishes no Linux per-thread nice contract.

The V `attrnice` fixture runs root and UID/GID1000 cohorts. Each owns blocked
same-UID and UID/GID1001 peers whose nice limits are respectively 20/40 and
40/40. Self soft limits cycle through 0/20/40 with hard 40. Effective capability 23
is toggled independently of UID; the full capability snapshot is checked and
restored. Six target classes cover implicit/explicit self, both peers, an absent
positive PID and a fully reaped child. Twelve signed32 nice values include both
extremes and boundaries around -20 and 19. OTHER/BATCH, four guarded input forms
(aligned, unaligned, read-only and inaccessible), upper PID words and upper
reserved flag words complete the main matrix.

Additional controls cover IDLE/FIFO/RR, the shared legacy scheduling permission
helper, short read-only layouts (size 0/48/49/53/56), signed32 negative PIDs and
NULL/input/flag/policy/priority error precedence. After every live call the
fixture verifies policy, priority, raw getpriority, genuine musl getpriority,
known getattr fields and output guards. Failed calls preserve state; successful
fair calls apply the normalized nice; nonfair calls retain nice 0. Inputs retain
all known bytes and canaries. External targets also leave self state unchanged.
The probe does not assert configuration-dependent fair runtime/clamp defaults.

A privileged UID0 broker restores every live target after both success and
error using real legacy scheduling and setpriority calls. It accepts only the
cohort process and its two registered peers, confirms restored OTHER/priority 0/
nice 0 before acknowledging, and uses synchronous pipe messages backed by stack
storage. This permits the original kernel's broken UID1000 capability path to
finish without silently substituting setup success. Peers close inherited
broker descriptors, are released and reaped, and the three-page guarded mapping
is fully unmapped before case reporting. Cohort children transfer the final
64-byte counts before closing their pipes and being reaped. PR_SET_KEEPCAPS is
used only inside disposable cohort processes; complete process-state restoration
is not claimed. Final probe C has 25 explicit allocas and no heap, dynamic-array
or fixed-index helpers.

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 29,310 | 9,366 | 0 | 0 |
| x86-64 | 29,310 | 9,366 | 0 | 0 |

Each cohort records `3456/6912/3456/831` checks. Original root failures are
`1056/2112/1056/435`; original UID1000 failures are `1080/2160/1080/387` on
both architectures. Original/corrected Vinix and actual Linux 6.12.51 execute
identical final probe ELFs per architecture. Native pages are 16 KiB ARM/4 KiB x86;
Linux references use 4 KiB. The syscall entry is genuine musl `syscall`; dedicated
musl scheduling wrappers retain their separately documented ENOSYS behavior.

Both corrected cohorts run 32 warmups and 200 denial/clamping/peer-admission/
restoration cycles, with thirteen-second settling intervals around snapshots.
All 18 ARM and 14 x86 slab classes remain exactly flat, as do large-page counts
85/85 ARM and 216/216 x86. The observer descriptor closes on every nonfatal path.
These bounded storage receipts include the probe's broker IPC; they do not
establish whole-kernel allocation or process-churn qualification.

Four fresh production builds use isolated worktrees at
`4fd5c605d87b05208b73cf725ba93b59699b4f1c`. Full generated C differs only in
`sched_setattr`, `may_set_sched_params`, `default_rlimits`, the new scalar
helper/prototype and exactly three uses of an existing `proc__find_free_id`
loop identifier per architecture. That identifier embeds the shifted process
source byte offset; normalizing only its declaration/condition/increment leaves
every other generated byte identical. Scheduler queues, allocator, user-copy
and existing affinity/import/query implementations retain their prior code.

Eight cases per architecture (attrnice/runtime/schedabi/rrabi/attrquery/
attrimport/affabi/fcntlabi) pass across primary and completion receipts. Initial
suites persisted five passing cases each, then host file writes failed during
disk pressure. Neither initial aggregate was retained; the original watchdog
stopped after eleven retirement events. Partial ARM attrimport boot files have
no semantic verdict. All 117 retained interrupted files are hashed before
retiring only their unbound ISO staging/firmware variables, then verified
byte-identical. Fresh completion directories supply three ARM passes and two
x86 passes on the same corrected kernel and frozen sources. X86 fcntlabi again
fails while building its ISO, with explicit xorriso ENOSPC in the retained
aggregate, empty ISO hash and no serial log. Its actual source/C/ELF remain
bound; that build supplies no semantic verdict. A fresh one-case recovery
provides the genuine x86 fcntlabi pass with identical source/C/ELF. All 67 p3
regular retained files stay byte-identical after unbound staging retirement,
and its sixteen-event interrupted watchdog remains separate from the final
eighteen-event capture manifest. The auditor requires the
initial aggregates to remain absent; it creates no complete eight-case receipt.
An intervening retry stopped before recording any case receipt or aggregate.
Its 30 regular staging/checkpoint files remain hashed and retained; its socket
is a transport endpoint and supplies no file-content or semantic evidence.
Eight host files and four frozen inventory checks also pass.
Allocation scans retain 398 ARM/290 x86 sites and existing allowance refusals.
Exactly four existing process-source diagnostics move two lines after the default
limit initializer; every other allocation-report byte matches. Whole-kernel
allocation approval is not claimed.

The maintained V auditor binds counts, original cohort failure vectors, topology,
guarded inputs, restoration, storage and compiler/source/C/ELF/kernel/ISO/reference
inputs. Its deliberately false assertion and passing-reference-as-baseline
controls execute without `-prod` and require exit 1. Independent review checks
locked pointer lifetimes, exact source/full-C scope, synchronous broker messages,
descriptor cleanup, mapping cleanup, child reaping and retained input hashes.
The completed-boot watchdog hashes all retained case files before retiring only
unbound ISO staging and firmware variables, then rechecks every retained file.

Permission and final mutation still use separate table-lock intervals; target
exit/reuse and credential/limit/policy changes between those intervals are
unqualified. Per-thread nice, supplementary scheduling ownership/limits,
complete realtime lowering/retention, deadline/reset/clamp/KEEP semantics,
nice/setpriority process/group semantics, namespaces/pledge/MAC-denial, glibc,
translated/ELF32 paths and physical priority/fairness remain separate. This work
does not close the ARM CPU1 QoS blocker or the three broad section 15 gates.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-14/attrnice-evidence-aarch64.json), [primary native receipt](../tests/linux-compat/results/2026-10-14/attrnice-after-aarch64-receipt.json), [completion receipt](../tests/linux-compat/results/2026-10-14/attrnice-completion-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/attrnice-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-14/attrnice-evidence-x86_64.json), [primary native receipt](../tests/linux-compat/results/2026-10-14/attrnice-after-x86_64-receipt.json), [completion/build-failure receipt](../tests/linux-compat/results/2026-10-14/attrnice-completion-x86_64-receipt.json), [descriptor recovery](../tests/linux-compat/results/2026-10-14/attrnice-recovery-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-14/attrnice-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/attrnice-check.v), [verdict](../tests/linux-compat/results/2026-10-14/attrnice-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-14/attrnice-lifetime-review.md).

## Native realtime scheduling admission

The 2026-10-15 qualification covers target-limit admission through native
`sched_setscheduler`, `sched_setparam` and `sched_setattr` for stable,
single-thread process leaders. The existing permission helper incorrectly used
the caller's `RLIMIT_RTPRIO` and rejected retaining/lowering an existing RT
priority above that limit. It also admitted an RT policy switch at target limit
zero when the caller had a nonzero limit. The corrected helper reads the target
process's soft limit and current thread policy/priority under its existing
PID-table lock. Without effective `CAP_SYS_NICE`, changing RT policy at limit
zero returns EPERM; a requested priority above both the current priority and
target limit returns EPERM. Same-policy retention/lowering remains allowed.
Existing owner, MAC, capability, deadline and ordinary-class admission checks
retain their code. UID0 alone supplies no capability bypass.

The primary [Linux v6.12 scheduler implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c)
uses `task_rlimit(p, RLIMIT_RTPRIO)`, the policy-switch/zero-limit check and
`p->rt_priority` for this admission. Its retained SHA-256 is
`a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804`.
Actual Linux 6.12.51 references execute the unchanged native probe ELF on each
architecture. Dedicated musl scheduling wrappers remain subject to their
separately documented ENOSYS behavior; raw entry uses genuine musl `syscall`.

Root and UID/GID1000 cohorts each use self soft limits 0/20/40 with hard 99,
effective capability 23 off/on, a same-owner peer with soft20 and a UID/GID1001
peer with soft40. Peer hard limits are 99. Targets include PID0, self, the two
peers, an absent positive PID and a reaped child, plus signed-negative controls.
Five genuine starting states are OTHER/0, FIFO/20, FIFO/99, RR/40 and RR/99;
compact matrices use OTHER/0, FIFO/20 and RR/40. Five operations cover legacy
FIFO/RR setters, setparam on the existing policy and attribute FIFO/RR setters.

| Cohort group | Controls per cohort | Scope |
| --- | --- | --- |
| 0 | 5,400 | Three self limits, two capability states, six targets, five starting states, six priority boundaries and five operations |
| 1 | 1,440 | Upper PID words on live/missing targets, two limits and capability states, compact starting states and priority boundaries |
| 2 | 7,680 | Read-only aligned/unaligned, inaccessible and NULL inputs; valid/invalid priorities; upper policy/flag words and input/lookup/admission precedence |
| 3 | 1,039 | Signed-negative PID/priority controls, reserved low flags, invalid priorities, initial/final limits, restored states and complete capability snapshot |

| Architecture | Checks | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 31,118 | 1,312 | 0 | 0 |
| x86-64 | 31,118 | 1,312 | 0 | 0 |

Each original root and UID1000 cohort fails `434/74/148/0`, independently on both
architectures. The reference and corrected cohorts record zero failures for
all four groups. Native pages are 16 KiB ARM/4 KiB x86; references use 4 KiB. Every
live call verifies raw getscheduler/getparam/getpriority, genuine musl
getpriority, known sched_attr fields and output canaries. Errors preserve the
real starting state; successes apply the requested policy/priority with nice 0.
Nonself calls also leave self OTHER/0/nice 0. Accessible input bytes and both
eight-byte guards stay unchanged; unaligned input is prepared with memcpy.
Negative PID, NULL and reserved attribute flags give EINVAL before input import;
inaccessible inputs give EFAULT before lookup; absent/reaped targets give ESRCH
before priority validation; invalid priorities give EINVAL before permission.
Upper PID/policy/flag words use their actual narrowed syscall ABI; pointers keep
their full width. setparam's extra policy register is unused.

A privileged broker establishes and verifies the real starting state before
each live operation, then restores OTHER/0/nice 0 after either success or error.
Its new action4 accepts only the registered cohort/peer PIDs and validates
OTHER/0 or FIFO/RR priorities 1..99 before applying setup. Messages and scheduling
parameters stay on the synchronous caller/broker stacks until ACK; target
pointers do not escape their lock. Peers close inherited broker descriptors,
are released and reaped; the three-page guarded mapping is unmapped before
reporting. Counts transfer through the pipe before closing and reaping the
cohort. PR_SET_KEEPCAPS occurs only in disposable children; complete process
state restoration is not claimed. Probe C contains 25 explicit allocas and no
heap, dynamic-array or fixed-index helpers.

Each corrected cohort performs 32 warmups and 200 lowering/zero-limit-switch/
different-target-limit/capability cycles with thirteen-second snapshot settling.
All 18 ARM and 14 x86 slab classes stay exactly flat. Large-page counts remain
85/85 ARM and 216/216 x86, including the broker IPC. This bounded observation
does not qualify whole-kernel allocation or general process churn.

Four fresh production builds use isolated worktrees at
`37cfa0db2a2af906eb621733a3d4c0ead6ac48e9`. After removing only
`table__may_set_sched_params`, every remaining generated C byte matches between
original and corrected builds on both architectures. There is no compiler
identifier normalization, new allocation/free, prototype or pointer escape.
The helper retains one table lock and its existing unlock paths, adding exactly
one guarded early-return unlock. Allocation scans retain 398 ARM/290 x86 sites
with byte-identical reports and existing allowance refusals; whole-kernel
allocation approval is not claimed. Eight host files and four frozen inventory
checks pass. Public dispatch fingerprints use the committed parent plus this
owned change, excluding other sessions' uncommitted source edits.

Eight native cases per architecture pass: rtadmit, runtime, schedabi, rrabi,
attrquery, attrimport, attrnice and fcntlabi. Original/corrected/reference probe
source/C/ELF identities are bound; every native receipt binds its actual kernel,
source, executable, ISO and serial result. The maintained V auditor requires
the exact measured baseline vectors, both cohort topologies, storage outcomes,
all 15,146 pinned compiler inputs, 64 frozen dispatch inputs and independent
lifetime review. A deliberately false assertion and a passing Linux reference
supplied as a failing baseline must actually exit 1 without `-prod`. A bounded
watchdog hashes completed case files before retiring only unbound ISO staging
and firmware variables, then rechecks every retained regular file.

Initial baseline producers and the first allocation scanner failed to open
their output logs during host disk pressure. Their actual producer output was
not retained and cannot be reconstructed; no build/guest/semantic verdict is
assigned to those attempts. Existing generated regular objects were copied
before fresh successful builds/scans. Two first preflight compiler attempts
refused an incorrect private guesthost import before creating state/C/ELF;
the private module symlinks were corrected before successful compilation.
The 310 retained preparation files are pinned separately. Subsequent producer
drivers use bounded log-write retries so actual output is retained.

Permission and mutation still use separate table-lock intervals; target
exit/reuse and credential/limit/policy changes between them remain unqualified.
Worker-thread admission, supplementary ownership, idle-exit/reset/deadline/
KEEP/clamp/timing semantics, namespace/pledge/MAC-denial configurations, glibc,
translated/ELF32 paths and physical priority/fairness remain separate. This
work does not close the ARM CPU1 QoS blocker or the three broad section 15 gates.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/rtadmit-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/rtadmit-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/rtadmit-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/rtadmit-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/rtadmit-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/rtadmit-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/rtadmit-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/rtadmit-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/rtadmit-check.v), [verdict](../tests/linux-compat/results/2026-10-15/rtadmit-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-15/rtadmit-lifetime-review.md).

## Native idle scheduling exit permissions

The 2026-10-15 qualification covers stable single-thread process leaders leaving
SCHED_IDLE through native sched_setscheduler and sched_setattr. Setparam on the
existing IDLE policy remains allowed. The original shared helper admitted exits
without the Linux nice-limit check. The corrected helper requires the target's
current nice to fit its RLIMIT_NICE (`20 - current_nice <= target_limit`) unless
effective CAP_SYS_NICE admits the caller. This applies to OTHER, BATCH and RT
destinations; RT transitions also retain their independently qualified target
RTPRIO admission. The imported requested nice does not replace the current-nice
check. Existing owner/MAC/capability/deadline checks remain, followed by the
existing ordinary/RT rules.

The retained [Linux v6.12 scheduler source](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c)
checks `task_has_idle_policy(p) && !idle_policy(policy)` and
`is_nice_reduction(p, task_nice(p))`. Its SHA-256 is
`a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804`.
Actual Linux 6.12.51 references execute the same final native musl probe ELF per
architecture. Raw entry is genuine musl syscall; dedicated scheduling-wrapper
ENOSYS behavior remains separately documented.

Root and UID/GID1000 cohorts vary caller NICE limits 0/1/20/39/40 with hard 40,
CAP_SYS_NICE off/on and current nice -20/0/19. Same-owner and UID/GID1001 peers
have NICE 20/40 respectively with hard 40 and RTPRIO 1/hard 99; callers separately
use RTPRIO 0/1/hard 99. Targets include zero/self, both peers, absent and reaped
PIDs, plus signed-negative controls. Initial states are IDLE/OTHER/BATCH with
priority 0, established with real privileged broker calls. Seven main operation
choices cover legacy OTHER/BATCH/IDLE, attribute OTHER/BATCH/IDLE and setparam;
four additional choices test legacy/attribute FIFO/RR priority 1.

| Group | Controls per cohort | Qualification |
| --- | --- | --- |
| 0 | 3,780 | Five caller limits, capability off/on, six targets, three old classes/nice values and seven operations |
| 1 | 896 | Upper PID words, current class/nice and owner/limit distinctions |
| 2 | 3,584 | Aligned/unaligned read-only, inaccessible and NULL buffers; upper policy/flag words |
| 3 | 4,244 | 960 RT-limit controls, 672 argument/error controls, 108 flag controls, 336 extreme-priority controls, 2,160 requested/clamped nice controls and eight initial/final observations |

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 25,008 | 632 | 0 | 0 |
| x86-64 | 25,008 | 632 | 0 | 0 |

Each final original cohort fails `76/32/64/144`; both corrected and reference
cohorts record zero. Native ARM pages are 16 KiB, x86 and Linux reference pages
are 4 KiB. Negative PID/NULL/outer flag EINVAL precedes input import, EFAULT
precedes lookup and missing ESRCH precedes priority validation. Failed calls
preserve actual class/priority/nice and input bytes; successes apply the admitted
class/priority and fair attribute nice, preserving nice for other operations.
Raw and genuine musl getpriority verify retained nice for every class. Known
getattr fields and output canaries are checked, including nice for ordinary/IDLE
classes. RT getattr nice is deliberately outside this contract: Linux reports
zero while native currently reports process nice. Nonself operations leave self
OTHER/0/nice 0. Inputs retain their 56 bytes and eight-byte guards; unaligned input
uses memcpy rather than unaligned struct dereferences.

The broker validates positive registered cohort/peer PIDs, an allowed class and
nice -20..19, restores OTHER/0/nice 0, sets actual nice, installs the requested
class and verifies state before ACK. RT setup priority is fixed 1. Message,
parameter, Attr and Counts storage remains live through synchronous syscalls/
pipe I/O. Peers close inherited broker descriptors, are released/reaped, and
the guarded mapping is unmapped before reporting. The cohort transfers counts
before closing its pipes and being reaped. PR_SET_KEEPCAPS is confined to
disposable children; complete process-state restoration is not claimed.
Final probe C has 26 explicit allocas and no heap/dynamic-array/fixed-index helpers.

Two native cohorts perform 32 warmups and 200 current-nice refusal/admission,
different-peer-limit, same-IDLE setparam and privileged RT-exit cycles, with
13-second settling intervals around slab snapshots. All 18 ARM/14 x86 classes
and large-page counts remain exactly flat. These observations include broker
IPC and retained leaders; they do not qualify general process churn or all
kernel allocation paths. Four fresh production builds use isolated worktrees
at `410d7c5e499acbb3c274be54161f84b59514d505`. Whole generated C is byte-identical
after removing only may_set_sched_params, without identifier normalization.
Source changes only the six-line locked guard and its exact internal comment.
The helper retains one lock and adds one guarded unlock (10 to 11), with no
allocation/free or pointer escape. Allocation diagnostics remain byte-identical
at 398 ARM/290 x86 sites with existing allowance refusals; whole-kernel allocation
approval is not claimed. Eight host files and four frozen inventory checks pass.

The eight final cases are idleexit/runtime/schedabi/rrabi/rtadmit/attrimport/
attrnice/fcntlabi, with original/corrected/reference source/C/ELF identities and
actual kernel/ISO/serial receipts bound. The maintained auditor requires exact
cohort counts/vectors, compiler and 64-input inventory pins, guarded state,
storage and independent lifetime review. Its false-assertion and passing-Linux-
as-failing-baseline controls must actually exit 1 without `-prod`. The final
watchdog binds 18 distinct native captures and rechecks every retained regular
file after retiring only unbound ISO staging and firmware variables. Public
dispatch fingerprints use committed-parent sources plus this owned change.
The initial final-capture watcher reaches its 1,200-iteration limit after ten
completed captures. Its actual checkpoint, hashes and timeout output stay
separate; a fresh bounded watcher rehashes/seeds those ten captures and finishes
the remaining retirements. Passing native cases are not rerun. Watch timing
supplies no semantic verdict.

First preflight C compilations failed on an undeclared v_fixed_index emitted
by fixed-array membership outside unsafe. The classifier now uses explicit
scalar equality, with fresh previews/preflight3. First native probes then stop
at broker stage 19 errno 0 before any CASES rows: negative i32 variadic setpriority
setup exposes the separate native signed32-normalization gap. Their two actual
failure receipts/source/C/ELF/ISO/serial/aggregates remain bound, alongside
genuine passing initial Linux references. They supply no final baseline vector.
Final broker setup explicitly widens nice through u64(i64(message.value)),
verifies real state and uses fresh p2 original/corrected/reference identities.
Native setpriority signed32 words, capability/limit permissions and process/
group semantics remain separate work. No setup operation is replaced by success.

Current nice remains process-wide natively, so this qualification covers leaders.
Permission and mutation use separate lock intervals; identity/credential/limit/
policy races remain open. Worker threads, RT getter nice, reset/deadline/KEEP/
clamp/timing, security/namespace configurations, glibc, translated/ELF32 and
physical priority/fairness remain unqualified. This work does not close the
ARM CPU1 QoS blocker or the three broad section 15 gates.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/idleexit-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/idleexit-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/idleexit-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/idleexit-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/idleexit-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/idleexit-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/idleexit-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/idleexit-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/idleexit-check.v), [verdict](../tests/linux-compat/results/2026-10-15/idleexit-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-15/idleexit-lifetime-review.md).

## Native realtime scheduling-attribute queries

The 2026-10-15 qualification covers sched_getattr on stable single-thread
process leaders in OTHER/BATCH/IDLE and FIFO/RR. Linux returns sched_nice zero
for FIFO/RR, independently of the task's actual retained nice. Vinix originally
copied process nice into that field for every class. The corrected initializer
selects zero for FIFO/RR and retains existing values for the other tested classes.
Policy, realtime priority, flags, output size and the underlying nice are unchanged.

The retained [Linux v6.12 scheduler implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c)
initializes kattr, then get_params fills only sched_priority for realtime tasks;
the other branch fills sched_nice. Its SHA-256 is
`a9c89bc6e1eca2587f39518718aa0a53fd8ef646f16927a0252e5fa7f25b5804`.
Actual supplied Linux 6.12.51 kernels execute the same final probe ELF as each
native architecture. The probe uses genuine musl syscall and getpriority calls.
Dedicated scheduling-wrapper ENOSYS behavior remains separately documented.

Root and UID/GID1000 cohorts query with effective CAP_SYS_NICE disabled. Targets
are PID0, self, a same-owner peer and a UID/GID1001 peer. A privileged parent
broker establishes each real policy/priority/nice and verifies it before ACK.
Seven configurations are OTHER/0, BATCH/0, IDLE/0, FIFO/1, FIFO/99, RR/1 and RR/99;
nice values are -20/-1/0/1/19. Raw and genuine musl getpriority verify actual nice,
including the legitimate -1 result with errno zero, before and after queries.

| Cohort group | Controls per cohort | Contract |
| --- | --- | --- |
| 0 | 2,520 | Seven configurations, five actual nice values, four live targets, six sizes and three output forms |
| 1 | 5,040 | The same queries with two distinct upper PID words |
| 2 | 2,520 | The same queries with upper length/flag words |
| 3 | 1,928 | 1,920 argument/error controls and eight default/final state observations |

Each cohort performs 12,008 controls, or 24,016 per architecture. Group 3 uses
OTHER/0, FIFO/1 and RR/99 at actual nice 19; live, absent, reaped and signed-negative
targets; sizes 47/48/page+1/UINT_MAX, flags 0/1 and five output forms, with normal
and upper PID words. Original cohorts each fail `1152/2304/1152/16`; the corrected
and same-ELF Linux cohorts record zero. All CASES/FINAL keys, counts and outcomes
are independently bound.

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 24,016 | 9,248 | 0 | 0 |
| x86-64 | 24,016 | 9,248 | 0 | 0 |

Sizes 48/49/53/55/56/57 receive the exact known prefix, with advertised output size
min(requested, 56). Aligned, unaligned and page-tail outputs retain their canaries.
memcpy avoids unaligned Attr reads. Nice, policy, priority, flags, size and known
non-configuration fields are exact. RT runtime/deadline/period stay zero.
The supplied Linux fair slice and clamp default are configuration fields: fair
runtime is outside this contract and the observed clamp default must be 0 or 1024.
Native values remain exact. Native ARM pages are 16 KiB; x86/reference pages are 4 KiB.

Signed-negative PID, NULL, reserved outer flags and invalid sizes return EINVAL
before lookup. Missing/reaped targets return ESRCH before output faults. Valid
read-only/inaccessible outputs return EFAULT; a crossing read-only page permits
only the existing first 28 bytes to change before EFAULT. Other failed outputs and
all outer/read-only guards remain unchanged. Every live query retains actual
policy, priority and raw/musl nice; nonself queries retain self OTHER/0/nice 0.

The scalar broker Message is 20 bytes, including an explicitly validated priority
1..99 for FIFO/RR and 0 for other classes. Registered positive peer PIDs and nice
-20..19 are checked. Canonical signed64 setpriority setup remains explicit; it
does not qualify native signed32 setpriority words or admission/group semantics.
Setup checks actual nice independently of the RT field under test; matrix output
comparisons always check that field exactly. Message, Attr, parameters and Counts
stay live through synchronous syscall/pipe operations; no pointer crosses a pipe.
Peers close inherited broker handles, block until released, then are reaped.
The mapping is unmapped before the cohort reports; counts transfer before reap.
Disposable PR_SET_KEEPCAPS children do not establish whole process restoration.
Final probe C has 25 explicit allocas and no heap/dynamic-array/fixed-index helpers.

Both native cohorts warm 32 query cycles and run 200 cycles with retained FIFO/RR
leaders at nonzero nice, upper words, guarded short/full outputs and real errors.
The slab observer stays open through two snapshots separated by 13-second settling
intervals. All 18 ARM/14 x86 slab classes stay flat, with 85/85 ARM and 216/216 x86
large pages in both cohorts.
These measurements qualify the repeated query path with retained tasks, excluding
general process churn and whole-kernel allocation.

Four fresh production builds use isolated worktrees at
`7fcfd033b727496f6146c4c67ce47936abc265ab`. Entire generated C is byte-identical
outside syscall_linux_sched_getattr, without compiler identifier normalization.
The one scalar field initializer is the only source change. Existing borrowed
owner/task pointers, stack Attr and usercopy remain unchanged, with one PID-table
lock and two unchanged unlock paths. No allocation/free or pointer escape is added.
Allocation diagnostics are byte-identical at 398 ARM/290 x86 sites, retaining the
existing allowance refusals; this does not approve all kernel allocations.
Eight host files and four frozen inventory checks pass.

The eight corrected cases are attrclass/runtime/schedabi/rrabi/attrquery/attrnice/
rtadmit/idleexit. The maintained V auditor rehashes compiler inputs, 64-source
inventories, builds, source/C/ELF/ISO/kernel/serial and all actual receipts. Its
false-assertion and passing-Linux-as-failing-original controls must actually exit 1
without -prod. The bounded capture watcher records 18 distinct captures, hashes
every retained regular file and rechecks them after retiring only unbound ISO
staging and firmware variables. Independent lifetime/provenance review gates
publication. Public dispatch fingerprints use committed-parent inputs plus the
owned scalar fix; they do not upgrade this dated frozen-kernel qualification.

Native nice remains process-wide, so worker-thread nice is outside this contract.
Getter snapshots span separate lock intervals; target identity/credential/policy
races, reset/deadline/utilization transitions, namespace/security configurations,
glibc and translated/ELF32 paths remain unqualified. Fair scheduling/timing and
the ARM CPU1 QoS blocker remain separate. The three broad section 15 gates stay open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/attrclass-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/attrclass-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/attrclass-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/attrclass-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/attrclass-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/attrclass-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/attrclass-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/attrclass-reference-x86_64-receipt.json).
- [Maintained V audit](../tests/linux-compat/attrclass-check.v), [verdict](../tests/linux-compat/results/2026-10-15/attrclass-audit.log), [independent lifetime review](../tests/linux-compat/results/2026-10-15/attrclass-lifetime-review.md).

## Native priority argument words and missing-target errors

The 2026-10-15 qualification covers PRIO_PROCESS getpriority/setpriority on
stable single-thread process leaders. Both calls now decode which/who as
signed32, and setpriority decodes nice as signed32 before its existing -20..19
clamp. Negative process targets reach the existing guarded process lookup and
return ESRCH; invalid selectors retain EINVAL. Previously full register words
could reject live targets or turn a zero-extended negative nice into positive 19.

The retained [Linux v6.12 implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c)
declares all these syscall arguments as int and starts missing-target lookup
with ESRCH. Supplied Linux 6.12.51 kernels execute each architecture's exact
original native probe ELF. Genuine musl getpriority/setpriority calls remain
passing controls; their signed arguments are widened by musl's syscall macros.
Raw syscall tests exercise seven register forms, including canonical signed64,
zero extension, individual upper selector/target/nice words and two combined
upper patterns. No setup operation is replaced with success.

Root cohorts retain effective CAP_SYS_NICE. UID/GID1000 cohorts have no such
capability and zero soft/hard RLIMIT_NICE. Live targets are PID0, self, a same-owner
peer and a UID/GID1001 peer; absent, reaped, -1 and INT_MIN targets supply errors.
Privileged parent setup uses canonical signed64 words, verifies actual state
and acknowledges only registered positive PIDs. The peers remain live until
explicit release and wait/reap; no pointer crosses the 16-byte Message pipe.

| Group | Controls per cohort | Contract |
| --- | --- | --- |
| 0 | 840 | OTHER/BATCH/IDLE, five actual nice values, eight targets and seven query word forms |
| 1 | 1,512 | Three policies, eight targets, nine requested nice values and seven setter word forms |
| 2 | 4,032 | Four invalid selectors, eight targets, nine nice values, seven word forms and both syscalls |
| 3 | 223 | 216 genuine musl setters and seven initial/final capability, limit and state observations |

The requested nice values are INT_MIN/-21/-20/-1/0/1/19/20/INT_MAX. Every live
control observes actual raw and musl nice, including legitimate -1 with errno
zero, plus retained policy and priority. Nonselected leaders stay OTHER/nice0.
Unprivileged cross-owner setters return EPERM before lowering admission; same-owner
lowering with zero nice limit returns EACCES. Errors preserve actual task state.
Argument decoding is tested independently of these existing bounded conditions.

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 13,214 | 2,898 | 0 | 0 |
| x86-64 | 13,214 | 2,898 | 0 | 0 |

Root original failures are 480/984/0/0, ordinary failures 480/954/0/0. Independent
source derivation matches both actual guest vectors. CASES/FINAL keys and counts
are exact and unique. Successful queries preserve nice and policy; setters apply
the clamped value only after real permission checks. Genuine musl and invalid-
selector controls pass on original kernels as well.

Each corrected native cohort retains all three leaders at nice19, warms 32
cycles, then runs 200 query/setter/error cycles. Slab snapshots bracket the loop
with 13-second settling intervals. All 18 ARM/14 x86 classes and positive large
page counts remain flat in each cohort: 85/85 ARM and 216/216 x86. This measures repeated legacy priority
paths with retained leaders; process churn and whole-kernel allocation are outside
the claim. The observer closes before peer release. The qualifier transfers its
counts before its parent reaps it; the peers have already been released and reaped.

Four fresh production builds use isolated worktrees at
`e72783a88349ac10cd1d3ec405237c9438b94eca`. Whole generated C is identical outside
the two priority definitions and their renamed prototype parameters, without
compiler identifier normalization. The source diff is exactly five signed32
conversions, parameter renaming and removal of the shared negative-target EINVAL
condition. Existing PID-table locks, guarded lookup, borrowed targets, MAC/owner
checks and nice mutation remain unchanged, with no new allocation/free or escape.
Allocation diagnostics remain byte-identical at 398 ARM/290 x86 sites and retain
existing allowance refusals. Eight host files and both frozen before/after
inventories pass; public dispatch fingerprints use committed-parent inputs plus
this owned change and do not upgrade the historical test kernel.

First ARM preflight C compilation failed because V moved four addressed Counts/
Slabs temporaries to memdup. Its actual source, C and failure output remain bound;
it supplies no probe ELF or guest verdict. Fresh preflight2 replaces those four
temporaries with explicit stack allocas. Final preflight/native/reference C/ELF
identities agree; final C has four explicit allocas and no heap/dynamic-array or
fixed-index helpers. Kernel borrowing/lifetimes are unchanged.

Four corrected native cases per architecture are niceabi/runtime/attrclass/attrnice.
The first ARM batch records overall status 1: runtime image assembly encountered
`No space left on device`, leaving source/C/ELF but no ISO or guest serial. The
other three cases pass. A fresh runtime-only retry uses the same corrected kernel,
source/C/ELF and supplies the genuine passing completion receipt. The x86 batch
passes all four together. The failed ARM preparation and its original aggregate
remain bound; no passing guest verdict is reconstructed for it.

The maintained V auditor rehashes compiler inputs, frozen inventories, complete
source/C, kernels, probe ELFs/ISOs, serial logs, receipts and every retained regular
file. The initial watcher rejects the ARM failed-preparation row after four
captures; its actual assertion, log and partial inventory remain retained. The
resumed classifier binds eleven captures: ten completed guests and one failed
preparation, with 97 regular files. It retires only unbound boot staging after
hash and recheck. False-assertion and passing-Linux-as-failing-original controls actually
exit 1 without -prod. Independent lifetime/provenance review gates publication.

Nice remains process-wide natively. Worker-thread nice, target/credential races,
PRIO_PGRP/PRIO_USER, full capability/RLIMIT_NICE admission, root without effective
CAP_SYS_NICE, namespace/security configurations, realtime physical scheduling,
glibc and translated/ELF32 priority paths remain unqualified. The three broad
section 15 gates and the ARM CPU1 QoS blocker stay open.

Probe setup/protocol abort cleanup is outside this qualification: if the count
transfer fails, the parent's short-circuit condition can skip waitpid until the
controller tears down the failed guest. Every qualified failing-original or
passing capture transfers the complete counts and reaps the qualifier normally.
An aborted transfer supplies no qualified success.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/niceabi-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/niceabi-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/niceabi-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/niceabi-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/niceabi-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/niceabi-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/niceabi-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/niceabi-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/niceabi-check.v), [verdict](../tests/linux-compat/results/2026-10-15/niceabi-audit.log), [failed preparation](../tests/linux-compat/results/2026-10-15/niceabi-preflight-failure.log), [independent review](../tests/linux-compat/results/2026-10-15/niceabi-lifetime-review.md).

## Native priority capability and target-limit admission

The 2026-10-15 qualification covers PRIO_PROCESS setpriority on stable native
process leaders. Admission now uses effective CAP_SYS_NICE and the target's
RLIMIT_NICE. UID0 without that effective capability receives the same owner and
nice-lowering checks as an ordinary owner. A non-root caller with the effective
capability can lower nice or update the tested cross-owner peer. Cross-owner
EPERM precedes lowering EACCES; failed admission retains actual task state.

The retained [Linux v6.12 priority implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c)
and [scheduler admission helper](https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sched/syscalls.c)
provide the ownership/error ordering and the target RLIMIT_NICE conversion.
The soft limit must admit `20 - clamped_nice` for an unprivileged reduction.
Equal or increased nice does not require a lowering allowance. The existing
MAC check, signed32 argument decoding, clamp, guarded lookup, PID-table lock
and scalar nice update remain unchanged.

Both UID/GID0 and UID/GID1000 qualifiers exercise capability off/on, with
OTHER/BATCH/IDLE targets at actual nice -20/-1/0/1/19. Live targets are PID0,
explicit self, a same-owner peer and a UID/GID1001 peer. Each requested value
INT_MIN/-21/-20/-1/0/1/19/20/INT_MAX is tested against target soft limits
0/1/20/21/40/infinity with hard infinity. Peer cases install the opposite
caller limit (40 for target0, otherwise0), distinguishing target admission
from a caller-limit shortcut.

| Group | Controls per cohort | Contract |
| --- | --- | --- |
| 0 | 6,480 | Canonical signed64 raw words across both capability modes, three policies, four live targets, five current values, six limits and nine requested values |
| 1 | 6,480 | The same matrix with simultaneous upper selector/target/nice words |
| 2 | 6,480 | The same matrix through genuine musl setpriority calls |
| 3 | 658 | 648 absent/reaped/negative-target and invalid-selector errors plus ten initial/final capability, limit, identity and state observations |

Every live control reads actual raw and musl getpriority, including legitimate
nice -1 with errno zero, and actual policy/priority. Nonselected leaders remain
OTHER/nice0. A privileged parent installs and independently queries each real
target limit, avoiding unprivileged cross-owner prlimit query restrictions. Its
24-byte scalar-only Message protocol whitelists registered positive PIDs,
policies, nice and limits; setup acknowledges only observed actual state. The
qualifier toggles only the effective CAP_SYS_NICE bit and compares the complete
final capability snapshot. Disposable PR_SET_KEEPCAPS and the raised hard limit
are setup state, not a claim of complete process restoration.

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 40,196 | 10,692 | 0 | 0 |
| x86-64 | 40,196 | 10,692 | 0 | 0 |

The original root failure vector is 1377/1377/1377/0; ordinary failures are
2187/2187/2187/0. Independent source derivation matches the captured vectors.
Root failures expose 567 disallowed same-owner reductions and 810 cross-owner
updates per call form while capability is off. Ordinary failures expose 405
permitted unprivileged reductions, 972 privileged same-owner reductions and
810 privileged cross-owner updates per form. Supplied Linux 6.12.51 kernels run
the exact original native ELF for each architecture; no reference oracle is
substituted for execution. CASES/FINAL identities and counts are exact.

Each corrected native cohort warms 32 cycles then runs 200 cycles across both
capability states, all three setter forms and four live targets, plus missing
target errors. The leaders retain nice19 and soft20 during repeated lower/raise
operations. All 18 ARM/14 x86 slab classes and positive large-page counts stay
flat across 13-second settling intervals: 85/85 ARM and 216/216 x86 pages in
both cohorts. This measures repeated admission paths with retained leaders;
process churn and whole-kernel storage are separate.
Peers are released and reaped before count transfer, and the parent always
waits for the qualifier even if the transfer fails.

Four fresh production builds use isolated worktrees at
`9969135689c8ca354631d3ce46257d20b1bd3b20`. Complete generated C differs only in
the existing setpriority body, with no compiler identifier normalization, new
allocation/free or pointer escape. Before/after allocation diagnostics remain
byte-identical at 398 ARM/290 x86 sites, including existing allowance refusals.
Eight host files and both before/after generated inventories pass. The public
dispatch inventory uses the committed parent plus this owned fix; it does not
upgrade the historical guest kernel.

The first ARM preflight ran out of disk space before C/ELF generation. Its
actual stdout and absence of a probe remain bound; it supplies no guest result.
Fresh preflight2 C/ELFs match both native phases and the Linux references, with
five explicit stack allocas and no heap, dynamic-array or fixed-index helpers.
The initial ARM production build's detached stdout is empty; its actual build
log/C/ELF remain retained. Its C is identical to the fresh original C, but the
initial ELF differs in both size and hash. Its declared section table starts
at byte 33,206,288, beyond its 17,776,640-byte file; independent boundary
validation fails, and its third load segment's declared payload also exceeds
the file. It is structurally incomplete, is not a byte prefix of the fresh ELF,
and supplies no qualified guest identity. The fresh original build produces
genuine passing stdout and the complete ELF used by the original native run;
its segment and section boundaries pass. No missing verdict is reconstructed.

Corrected niceadmit/runtime/niceabi/attrnice cases pass on both architectures.
The maintained V auditor checks complete source/C scope, all 15,146 compiler
inputs, frozen inventories, actual build stdout, kernels/probes/ISOs, receipts
and the exact 90-file retained walk of ten completed native captures. Cleanup
retires only disposable staging after hash/recheck. False-assertion and
passing-Linux-as-failing-original controls execute and exit 1 without -prod.
Independent lifetime/provenance review gates publication.

Nice remains process-wide natively. Worker-thread nice, PRIO_PGRP/PRIO_USER,
concurrent target/credential/limit races, user-namespace capability distinctions,
other security configurations, glibc and translated/ELF32 priority paths remain
unqualified. The three broad section 15 gates and ARM CPU1 QoS blocker stay open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/niceadmit-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/niceadmit-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/niceadmit-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/niceadmit-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/niceadmit-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/niceadmit-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/niceadmit-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/niceadmit-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/niceadmit-check.v), [verdict](../tests/linux-compat/results/2026-10-15/niceadmit-audit.log), [initial failed preparation](../tests/linux-compat/results/2026-10-15/niceadmit-preflight1-arm.log), [independent review](../tests/linux-compat/results/2026-10-15/niceadmit-lifetime-review.md).

## Native getrandom flag validation

The 2026-10-15 qualification covers seeded native getrandom calls. Requests
combining GRND_RANDOM and GRND_INSECURE now return EINVAL, with or without
GRND_NONBLOCK. The check precedes zero-count handling, entropy readiness and
user copies. Unknown low-word flag bits retain their existing EINVAL behavior.
The retained [Linux v6.12 implementation](https://raw.githubusercontent.com/torvalds/linux/v6.12/drivers/char/random.c)
validates the same incompatible combination before readiness and buffer import.

Root and UID/GID1000 cohorts each run the following groups through three raw
flag-word forms and genuine musl getrandom: canonical low32, arbitrary upper32,
all-one upper32 and the libc wrapper. Each cohort first demonstrates seeded
readiness through an actual successful 32-byte nonblocking request.

| Group | Controls per cohort | Contract |
| --- | --- | --- |
| 0 | 432 | Flags6/7, four call forms, six destinations and nine counts must return EINVAL without writing |
| 1 | 2,376 | Eleven unknown-bit masks retain EINVAL across the same forms, destinations and counts |
| 2 | 144 | All six accepted flag combinations return zero for count0, including inaccessible destinations |
| 3 | 576 | Six accepted flag combinations, four call forms, six destinations and counts1/255/256/257 preserve success/EFAULT and output guards |

Destinations are aligned and unaligned writable buffers, NULL, address1,
PROT_NONE and a read-only page. Invalid-flag counts include zero, 1, 255, 256,
257, native page/page+1, 2GiB and SIZE_MAX. Writable pages are bounded by a
read-only page and guard pages so even the original erroneous large requests
terminate at a fault. Corrected invalid/error calls preserve all sentinel bytes;
successful controls preserve bytes outside their requested output ranges.
Random output content is not compared with a deterministic oracle.

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 7,056 | 864 | 0 | 0 |
| x86-64 | 7,056 | 864 | 0 | 0 |

Both original cohorts fail exactly group0, with 432 failures each; all other
controls pass. CASES and FINAL match exactly. Supplied Linux 6.12.51 kernels
run the original native probe ELF for each architecture, without rebuilding
or substituting results. Native ARM uses 16KiB pages; the Linux references
and native x86 use 4KiB pages.

Each corrected cohort warms 32 cycles and measures 200 repeated invalid-flag
and valid-zero-count cycles with 13-second settling intervals. All 18 ARM/14
x86 slab classes and positive large-page counts remain flat. The observer
closes and the five-page mapping is unmapped before Counts transfer. The
parent closes the pipe and waits for the qualifier even after failed transfer.
Fatal setup/controller abort cleanup and process churn remain separate.

Four fresh production builds use isolated worktrees at
`f056137579217e5938bb83b500c86c75f7975dce`. Complete generated C differs only
in the getrandom definition; the exact source change is the three-line guard.
The existing bounce-buffer lifetime, erasure and user copies remain unchanged,
with no new allocation/free or compiler-identifier normalization. Artifact
captures read back and verify complete copied bytes before a build passes.
Allocation diagnostics remain byte-identical at 398 ARM/290 x86 existing sites,
including existing allowance refusals. Eight host files and both frozen
before/after 64-input dispatch inventories pass. Public fingerprints use the
committed parent plus this owned change, separately from historical test kernels.

Probe preflight/native/reference C/ELF identities agree. Probe C has four
explicit stack allocas and no heap, dynamic-array or fixed-index helpers.
Corrected randomflags/runtime/niceadmit cases pass on both architectures.
The maintained V auditor checks compiler pins, complete C/source scope,
actual build stdout, receipts and the exact 72-file walk of eight completed
native captures. False-assertion and passing-Linux-as-failing-original controls
execute and exit 1 without -prod; completed staging is retired only after hashes
and rechecks. There is no new kernel pointer lifetime in the early scalar check.

Entropy quality, unseeded blocking/interruption, partial-copy faults, large
valid transfers, glibc and translated/ELF32 getrandom paths remain unqualified.
The three broad section 15 gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/randomflags-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomflags-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomflags-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomflags-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/randomflags-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomflags-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomflags-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomflags-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/randomflags-check.v), [verdict](../tests/linux-compat/results/2026-10-15/randomflags-audit.log).

## Native getrandom partial-copy faults

`getrandom` now returns every byte committed before an output fault, including
a prefix within its 256-byte bounce chunk. Previously a one-byte writable prefix
followed by PROT_NONE returned EFAULT after writing that byte; a 257-byte prefix
returned 256 after writing 257. The counted copy helper now supplies the actual
uncopied suffix. A fault before any output still returns EFAULT. Complete
transfers, zero counts, flag validation and seeded readiness retain their
existing behavior.

The primary [Linux 6.12 random implementation](https://github.com/torvalds/linux/blob/v6.12/drivers/char/random.c)
accumulates the bytes copied to the user iterator and returns EFAULT only when
none were copied. The supplied Linux 6.12.51 reference kernels run the exact
same native musl probe ELFs used with Vinix, rather than rebuilt equivalents.

Each root and UID1000 cohort executes the following groups for PROT_NONE,
read-only and unmapped suffixes, all six accepted flags, three raw register-word
forms and the genuine musl getrandom call:

| Group | Controls per cohort | Behavior |
| --- | --- | --- |
| 0 | 5,472 | Positive short counts bounded by 19 prefixes that are not multiples of 256 |
| 1 | 864 | Existing exact short counts for prefixes 256, 512 and native page size |
| 2 | 6,336 | Successful zero, one-byte, prefix-minus-one and exact-prefix transfers |
| 3 | 1,152 | Zero-count success and first-byte EFAULT for NULL, address1, front guard and fault-page destinations |

The 22 prefix lengths are 1/2/7/15/31/32/33/63/64/65/127/128/129/255/256/
257/511/512/513/page-minus-one/page/page-plus-one. Partial requests extend the
prefix by 1, 17, 257 or page-plus-one bytes. Native AArch64 pages are 16KiB;
native x86-64 and both Linux references use 4KiB pages. The probe checks every
byte outside the accessible output prefix, preserves the read-only-page
sentinel and checks that prefixes of at least 32 bytes contain output. Random
values have no deterministic content oracle and this is not an entropy-quality
qualification.

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 27,648 | 8,064 | 0 | 0 |
| x86-64 | 27,648 | 8,064 | 0 | 0 |

Original failures are confined to group0: 4,032 failures per cohort for
accessible prefixes below 256 returning EFAULT after output. CASES and FINAL
vectors agree. The common native/Linux oracle accepts positive short counts up
to the accessible prefix and checks guards outside that prefix. Each corrected
cohort also warms 32 cycles, then measures 200 repeated
partial-copy/zero-count cycles with 13-second settling intervals. All 18 ARM/14
x86 slab classes and positive large-page counts stay flat. The observer closes
and the five-page mapping is unmapped before Counts transfer; the parent closes
its pipe and waits even after failed transfer. Fatal setup cleanup and process
churn remain separate.

Four fresh production builds use isolated worktrees at
`010468874ce63a2caec7e469bfe37ec4fd866936`. Complete generated C differs only in
the getrandom definition and the exact bodies/declarations of two newly
reachable existing helpers, raw_copy_to_user and raw_copy_user. Their source
matches the frozen committed base. The first scope audit refused these emitted
helpers; its real failure and status remain pinned. The maintained auditor now
checks the two complete helper bodies/declarations and requires exact counted
copy substitution and byte accumulation. There are no added allocations, frees
or kernel pointer lifetimes. Existing bounce ownership and erasure policy are
unchanged. Artifact captures read back and compare complete bytes before a build
passes. Allocation diagnostics remain byte-identical at 398 ARM/290 x86 existing
sites, including existing allowance refusals. Eight host test files and both
frozen before/after 64-input dispatch inventories pass. Public fingerprints use
the committed parent plus this change, separately from historical test kernels.

Probe preflight/native/reference generated C and ELF identities agree. Probe C
has four explicit stack allocas and no heap, dynamic-array or fixed-index
helpers. The repeated native cycle requires exact complete-prefix returns for
lengths 1/255/256/257/page-plus-one; the Linux ABI oracle accepts conservative
short copies. Corrected randomcopy/runtime/randomflags cases pass on both native
architectures. The auditor verifies compiler pins, full source/C scope, actual
build stdout, receipts and the exact 72-file walk of eight completed native
captures. False-assertion and passing-Linux-as-failing-original controls execute
and exit 1 without -prod. Disposable staging is retired only after hash capture
and rechecks.

Two exploratory oracle failures remain visible. The first required the whole
accessible prefix: ARM Linux returned one byte for a two-byte prefix and failed
3,024 group0 controls per cohort. The second accepted shorter counts but required
untouched bytes beyond the return: ARM Linux returned 24 for a 32-byte accessible
prefix while a faulting store committed additional accessible bytes, failing 432
controls per cohort. The [ARM copy routine](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/lib/copy_to_user.S)
uses conservative exception accounting for its [copy template](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/lib/copy_template.S).
The final single oracle permits both architecture behaviors while preserving
guards outside accessible memory, exact success/zero/error controls and the
native complete-prefix storage checks. It has no reference-only semantic branch.
The auditor verifies all 62 first-round and 128 second-round regular-file
identities plus their original receipts and logs; both initial ARM Linux
failures remain failures. Two restart attempts refused already-used initial
directories. Their real refusals are retained, and overwritten aggregate logs
were restored from published hash-identical retained copies. Final references
use fresh p3 directories and the final original native probe ELFs.

Entropy quality, unseeded blocking/interruption, signal interruptions,
canonical-range/wrap policy, huge valid transfers, glibc and translated/ELF32
getrandom paths remain unqualified. This bounded fix leaves the three broad
section 15 gates open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/randomcopy-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomcopy-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomcopy-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomcopy-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/randomcopy-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomcopy-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomcopy-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomcopy-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/randomcopy-check.v), [verdict](../tests/linux-compat/results/2026-10-15/randomcopy-audit.log).
- [Initial scope audit refusal](../tests/linux-compat/results/2026-10-15/randomcopy-audit-producer-first.log).
- [First exploratory identities](../tests/linux-compat/results/2026-10-15/randomcopy-exploratory-inputs.json), [first ARM Linux receipt](../tests/linux-compat/results/2026-10-15/randomcopy-exploratory-reference-arm-receipt.json), [second exploratory identities](../tests/linux-compat/results/2026-10-15/randomcopy-round2-inputs.json), [second ARM Linux receipt](../tests/linux-compat/results/2026-10-15/randomcopy-round2-reference-arm-receipt.json), [aggregate recovery identities](../tests/linux-compat/results/2026-10-15/randomcopy-reference-recovery-inputs.json).

## Native getrandom request ranges

Seeded `getrandom` now caps the requested count at the native page-aligned
MAX_RW_COUNT and checks the complete bounded range before generating output.
A range that crosses the userspace limit returns EFAULT without modifying a
writable prefix. Zero counts also validate the address domain: NULL, address1
and inaccessible userspace mappings still return zero, while the tested
out-of-domain pointers return EFAULT. Existing flag errors retain precedence.
The copy loop uses the capped length and retains counted partial-copy handling.

The primary [Linux import_ubuf implementation](https://github.com/torvalds/linux/blob/v6.12/lib/iov_iter.c)
caps length before access_ok. The [random implementation](https://github.com/torvalds/linux/blob/v6.12/drivers/char/random.c)
uses that importer after readiness handling. Seven primary files are pinned,
including generic bounds and the x86 access/limit definitions. Readiness
ordering and unseeded blocking remain separate from this seeded qualification.

Each root and UID1000 cohort runs these groups with three raw register-word
forms and the genuine musl getrandom call:

| Group | Controls per cohort | Behavior |
| --- | --- | --- |
| 0 | 888 | Six valid flags, four high-arena destinations and eight crossing/large lengths return EFAULT; five out-of-domain zero-count addresses also return EFAULT |
| 1 | 1,800 | Six conflicting/unknown flag masks retain EINVAL across all 15 destinations and zero/short/large counts |
| 2 | 1,440 | Four aligned/unaligned writable destinations preserve bounded success and partial copying; large counts through SIZE_MAX remain usable at the low arena after capping |
| 3 | 1,464 | Valid userspace zero-count controls and first-byte EFAULT for NULL/address1/guard/read-only/out-of-domain destinations retain all guards |

The low five-page arena is fixed at 4GiB with MAP_FIXED_NOREPLACE, keeping its
large capped requests safely inside the address domain. The second arena is
1GiB below a ceiling discovered with exact, non-replacing mmap probes at
candidate address widths. Both have two writable pages, a read-only page and
front/rear guards. No existing mapping is replaced. Requests that have valid
address ranges fault at the read-only page, so the test does not copy gigabytes.
All writable bytes outside the permitted output prefix and both read-only
sentinels are checked. Prefixes of at least 32 bytes must contain output; random
values have no deterministic oracle and entropy quality is not qualified.

| Context | Page size | Observed ceiling | Capped length |
| --- | --- | --- | --- |
| Native AArch64 | 16KiB | 2^47 | 0x7fffc000 |
| Linux AArch64 reference | 4KiB | 2^48 | 0x7ffff000 |
| Native x86-64 | 4KiB | 2^56 | 0x7ffff000 |
| Linux x86-64 reference | 4KiB | 2^47 | 0x7ffff000 |

The identical ELF computes each context's geometry and runs the same predicate;
reference mode only skips native slab measurement. Exact last-user-page policy
and tagged-pointer modes are not covered by these margin-separated ranges.

| Architecture | Controls | Original failures | Corrected failures | Same-ELF Linux failures |
| --- | --- | --- | --- | --- |
| AArch64 | 11,184 | 1,008 | 0 | 0 |
| x86-64 | 11,184 | 1,008 | 0 | 0 |

Original failures are exactly 504 group0 controls per cohort: 384 crossing
requests starting in writable high memory incorrectly return a partial success,
and 120 invalid-address zero counts incorrectly return zero. Other original
controls pass. CASES and FINAL vectors agree. Corrected and supplied Linux
6.12.51 kernels pass the unchanged native probe ELF on both architectures.

Each corrected cohort warms 32 cycles, then measures 200 repeated whole-range
and invalid-zero refusals with 13-second settling intervals. All 18 ARM/14 x86
slab classes and positive large-page counts stay flat. The observer closes and
both arenas are unmapped before Counts transfer; the parent closes its pipe and
waits even after a failed transfer. Setup allocation/churn and fatal-abort
cleanup remain separate.

Four fresh production builds use isolated worktrees at
`c9495f033519d1313520d2b954620671e3db594f`. Complete generated C differs only in
the getrandom definition, without compiler-identifier normalization. The audit
requires the exact scalar cap/range addition and bounded-loop substitution;
counted copies, bounce ownership and existing erasure policy are unchanged.
There are no added allocations, frees or kernel pointer lifetimes. Captures
read back complete copied bytes before reporting build success. Allocation
diagnostics remain byte-identical at 398 ARM/290 x86 existing sites, including
existing allowance refusals. Eight host files and before/after 64-input dispatch
inventories pass. Public fingerprints use the committed parent plus this change,
separately from historical test kernels.

Final probe preflight/native/reference C and ELF identities agree; generated C
has four explicit stack allocas and no heap, dynamic-array or fixed-index
helpers. An initial probe compile rejected a fixed-index helper and printf
format types; its actual diagnostics, C identity and lack of an executable are
retained. That attempt has no guest qualification. Corrected
randomrange/runtime/randomcopy cases pass on both native architectures. The
maintained auditor verifies compiler pins, full C/source scope, real build
stdout, receipts and the exact 72-file walk of eight completed native captures.
False-assertion and passing-Linux-as-failing-original controls execute and exit
1 without -prod. Disposable staging is retired only after capture and rechecks.

Entropy quality, unseeded readiness/error ordering/blocking/interruption,
tagged pointers, exact last-page policy, mapping/range races, full bulk 2GiB
transfers, glibc and translated/ELF32 paths remain unqualified. The three broad
section 15 gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/randomrange-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomrange-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomrange-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomrange-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/randomrange-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomrange-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomrange-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomrange-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/randomrange-check.v), [verdict](../tests/linux-compat/results/2026-10-15/randomrange-audit.log), [primary pins](../tests/linux-compat/results/2026-10-15/randomrange-primary-inputs.json), [initial compile refusal](../tests/linux-compat/results/2026-10-15/randomrange-compilation-attempt1.log).

## Native getrandom signal interruption

Seeded large `getrandom` calls now check for unblocked pending signals and
thread exit between completed native pages. A signal returns the bytes already
copied. The copy loop also gives the scheduler a chance to run between pages,
including on AArch64 platforms that advance timers cooperatively. No generator,
mapping or other resource lock is held across this scheduling point. Requests
that fit in a page complete without that scheduling point; existing flag,
request-range, copy-fault and readiness checks remain unchanged.

The contract follows Linux v6.12's
[get_random_bytes_user](https://github.com/torvalds/linux/blob/v6.12/drivers/char/random.c):
it samples pending signals and calls `cond_resched` after a completed page when
more output remains. This change does not qualify early boot readiness or
blocking before the generator is seeded.

`randomsignal` runs 336 conformance calls per architecture in separate root and
UID/GID 1000 children. Each child covers all six accepted flags, a raw call with
nonzero upper flag bits and the actual musl call, with `SA_RESTART` enabled and
disabled:

| Calls per child | Required behavior |
| --- | --- |
| 24 large transfers | A one-shot 1 ms SIGALRM interrupts an 8 MiB request. The result is a positive native-page multiple below 8 MiB, errno stays zero, exactly one handler runs, and its saved syscall return register equals the reported short count. |
| 24 blocked-signal transfers | SIGALRM is already pending and blocked before a 64 KiB call. The call completes; the signal remains pending and no handler runs until unblocking, then it runs once. |
| 120 short requests | Zero, 1, 32, 255 and 256 byte calls stay complete while a 1 microsecond one-shot timer may expire. |

The first test distinguishes a signal delivered before entering the call from
one that interrupted the transfer: a full result, missing handler, mismatched
saved return register or timeout fails. No retry replaces a failed transfer.
Writable prefix and suffix sentinels are checked on every call; for a short
result every byte beyond that result through the requested buffer and trailing
guard must stay intact. Nontrivial successful output must change some bytes.
The surrounding mapping also has inaccessible outer guard pages. This is a
copy-accounting test, not an entropy-quality test.

Original kernels fail exactly 48 large-transfer checks per architecture,
completing all 8 MiB despite the delivered signal. Corrected kernels and the
identical native probe ELFs under Linux 6.12.51 pass all 336 checks. Native pages
are 16 KiB on AArch64 and 4 KiB on x86-64; both Linux references use 4 KiB.

The first candidate only sampled pending bits. It passed x86-64 but still failed
all 48 large AArch64 checks: without a scheduling point the cooperative timer
had not published the signal while the loop ran. Both real candidate results,
their source, production C/ELF/build identities, receipts, raw logs and hashes
remain in the evidence. The final candidate adds the scheduling point and
avoids it after a completely satisfied request. The first cleanup watcher
correctly refused the failed AArch64 receipt; that refusal remains published.
Early preflight helper setup/launch refusals and an audit-source compile refusal
are also retained as tooling diagnostics, without claiming a guest verdict.

Two warmed 200-cycle native cohorts repeatedly read `page + 1` bytes with a
blocked pending signal through both call forms and six flags. A preopened
`/proc/slabinfo` descriptor measures every live slab class and big-page total
after settling; all remain flat. The actual probe C has four explicit stack
allocas and no allocation, dynamic-array or fixed-index helper calls.

Four production builds qualify the original/final kernels; two additional
production builds produced the retained first candidate. Whole generated C
differs only in `table__syscall_linux_getrandom`, without identifier
normalization. The maintained audit requires the exact source patch and no new
allocation/free calls. The current-thread pointer is borrowed only while the
syscall is alive; it is not retained by another object or used after the
scheduling point. Existing stack bounce ownership and erasure are unchanged.

The shared AArch64 SDK disappeared before the final run could compile its
three probes: each stopped on missing `fcntl.h`, with no init ELF, ISO or guest
log. Those receipts remain failures. The final AArch64 run uses the explicit
V `replay` adapter: it regenerates C, requires byte-identical V source and
generated C, verifies all frozen object and ELF hashes, and copies the original
object/ELF bytes into a fresh state directory. It does not claim a new C
compilation. All three final AArch64 probe ELFs match their already executed
pre-SDK-loss binaries; the signal probe also matches the Linux reference. The
replay source, commands, input/output hashes and header-error receipts are
published. The updated cleanup watcher accepts only the completed final
profiles and preserves the refused attempts.

The runtime and request-range regressions pass on both final kernels. Eight
host test files pass. The frozen 15,146-input compiler inventory, 64-input
dispatch inventories, native source/C/ELF/ISO/kernel receipts and same-ELF Linux
references are checked. Allocation diagnostics are byte-identical before and
after; existing allowance-file refusals remain recorded. Auditor assertions
execute without `-prod`, including deliberate false-assertion and
passing-Linux-as-original negative controls. All eight completed qualification
profiles retain hash-checked regular files before disposable boot staging is
retired.

Entropy quality, unseeded readiness/blocking, exact scheduling latency, ignored
signals, default stop/kill dispositions, thread-group-exit races, full 2 GiB
transfers, GNU libc and translated/ELF32 paths remain unqualified. The three
broad section 15 gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/randomsignal-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomsignal-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomsignal-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomsignal-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/randomsignal-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/randomsignal-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/randomsignal-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/randomsignal-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/randomsignal-check.v), [verdict](../tests/linux-compat/results/2026-10-15/randomsignal-audit.log), [first candidate pins](../tests/linux-compat/results/2026-10-15/randomsignal-exploratory-inputs.json), [first AArch64 result](../tests/linux-compat/results/2026-10-15/randomsignal-exploratory-arm-native.log), [first x86-64 result](../tests/linux-compat/results/2026-10-15/randomsignal-exploratory-x86-native.log).

## Native process group and session argument words

`getpgid`, `getsid` and `setpgid` now import their process/group arguments as
signed 32-bit values. Raw upper register bits cannot turn an ordinary process
ID into a different target or change a negative-ID error. Querying a negative
ID returns `ESRCH`. `setpgid` returns `EINVAL` for a negative group or a negative
PID with group zero, and `ESRCH` for a negative PID with a positive group.
Errors leave existing group/session identities intact.

The error ordering follows Linux v6.12's
[setpgid, getpgid and getsid](https://github.com/torvalds/linux/blob/v6.12/kernel/sys.c).
Linux substitutes the PID when group zero is requested before rejecting a
negative group, while a remaining negative PID fails task lookup. The kernel
change adds scalar argument casts and early errors. Existing process-table
locking, borrowed process references, stack orphan-change descriptor, group
mutation and notification lifetimes are unchanged.

The `groupabi` probe runs 5,760 controls per architecture in root and UID/GID
1000 children. Each cohort creates a private session, keeps two children alive
behind explicit release pipes, establishes a separate child group, and records
an outside-session parent plus a reaped child ID. Seven raw register-word forms
cover zero/sign extension, low/high arbitrary upper bits and upper sign bits;
the eighth form uses genuine musl calls. Setter PID and group words vary
independently, including the real musl setter when both select that form.

| Calls per cohort | Original failures per cohort | Controls |
| --- | --- | --- |
| 160 | 82 | Group/session queries of zero, caller, both held children, the outside-session parent, reaped and missing IDs, and three negative IDs. |
| 192 | 165 | Successful child assignment to the caller group, another child group and its own group through group zero. |
| 2,496 | 990 | Negative group precedence; negative, missing, reaped, self/session-leader and non-child targets; nonexistent groups; negative PID with group zero. |
| 32 | 14 | Both queries while a child is observed with `WNOWAIT`, then after it is reaped. |

Every call also checks the caller, group leader, member and outside parent's
group/session state. Successful setters must put the member in the requested
group without changing its session or any other tracked process. Children are
explicitly released and reaped before the cohort reports its result. The
original kernels fail exactly 2,502 controls per architecture. Corrected kernels
and the identical native ELFs on Linux 6.12.51 pass all 5,760 controls each.

Two warmed 200-cycle cohorts repeat negative queries and setter refusals through
all word forms, plus real alternating child group changes. A preopened
`/proc/slabinfo` descriptor compares every live slab class and big-page total
after settling. Both cohorts stay flat: 18 classes and 75/75 big pages on
AArch64, 14 classes and 182/182 big pages on x86-64. The generated probe C has
four explicit stack allocas and no allocation, dynamic-array or fixed-index
helper calls. Whole production C differs only in the three entry functions and
three group/session helpers, without compiler-identifier normalization or added
allocation/free calls.

Four completed production builds qualify the original and corrected kernels.
The final native `groupabi`, runtime and getrandom signal regressions pass on
both architectures. Eight host test files pass after the inventory change.
Allocation diagnostics remain byte-identical, including their existing
allowance-file refusals. The inventory now includes `proc/job_groups.v` and
`userland/cred.v`; the maintained audit checks the 64 original inputs and 66
corrected inputs, the private SDK and compiler-command receipts, 15,146 pinned
V compiler inputs, source/C/ELF/ISO/kernel identities and actual same-ELF Linux
references. Deliberate false-assertion and passing-Linux-as-original controls
execute without `-prod`. All eight completed qualification profiles retain 84
hash-checked regular files before disposable boot staging is retired.

Three diagnostic conditions remain visible. The first AArch64 link attempt had
no init ELF or guest run because the copied SDK's GCC runtime was not selected
and its separate pthread archive was absent. The explicit V compiler adapter
invokes real Clang with the frozen GCC runtime directory; static musl supplies
the pthread symbols from `libc.a`. All final ARM objects and ELFs are freshly
compiled, with recorded commands and success status. An HTTP 429 fetching the
Linux source is retained; the run reuses the byte-identical, previously pinned
v6.12 source, with its provenance and hash recorded.

The first Linux reference also exposed a probe setup assumption: early PID 1
legitimately has group/session zero. The old precondition rejected that state
before any conformance matrix ran, and the probe exiting as PID 1 caused Linux
to panic. That failed receipt, raw log and probe source remain published. The
final probe allows nonnegative outside identities, requires their session to
differ from the cohort, and prints the observed values. Every syscall
expectation remains the same. Earlier native probe artifacts remain pinned
separately; they do not replace the final same-source, same-ELF qualification.

Worker TIDs, nested PID namespaces, concurrent exec/exit/credential changes,
zombie setters, terminal and job-control signal behavior, PID reuse, GNU libc
and translated/ELF32 paths remain unqualified. The three broad section 15 gates
remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/groupabi-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/groupabi-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/groupabi-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/groupabi-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/groupabi-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/groupabi-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/groupabi-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/groupabi-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/groupabi-check.v), [verdict](../tests/linux-compat/results/2026-10-15/groupabi-audit.log), [SDK inputs](../tests/linux-compat/results/2026-10-15/groupabi-sdk-inputs.json), [diagnostic pins](../tests/linux-compat/results/2026-10-15/groupabi-diagnostic-inputs.json), [initial link refusal](../tests/linux-compat/results/2026-10-15/groupabi-initial-link-refusal.log), [Linux setup refusal](../tests/linux-compat/results/2026-10-15/groupabi-exploratory-reference.log).

## Native worker process group and session lookup

`getpgid` and `getsid` now accept live nonleader TIDs and report their owning
process's group and session. `setpgid` rejects a live nonleader with `EINVAL`
before parent/session/group eligibility checks. Once independently observed
as retired, that TID returns `ESRCH`; negative groups still take `EINVAL`
precedence. Leader lookup remains first, preserving zombie query behavior.
The ordering follows Linux v6.12's
[task lookup and group/session syscalls](https://github.com/torvalds/linux/blob/v6.12/kernel/sys.c).

The new helper borrows a thread and its owner only while the caller retains
the existing process-table lock. It snapshots the owner once, requires that
owner to remain registered and validates namespace visibility against that
snapshot. Exit and exec can switch a thread to the kernel process before
removing its TID; the registration guard rejects that detached identity.
An independent lifetime review found this window in the initial patch and
confirmed the revised guard. No allocation, pin, free or new lock ordering is
introduced. Whole production C differs only in the three group/session helpers
and the new lookup's declaration and body, without identifier normalization.
Existing orphan-change storage and group mutation/notification are retained.

The `grouptid` probe runs 14,464 controls per architecture across four cohorts:
root and UID/GID1000 in the initial and one-level PID namespaces. Each cohort
creates a private session, a held child with its own worker, and two caller
workers. Signal-zero probes independently establish the caller workers' live
and retired boundaries. A release pipe keeps the child and its worker alive
during the matrix. On release, the child joins its worker, exits and is reaped.
Workers publish their TIDs
with release/acquire atomics; one runs calls itself while the leader is idle.

| Calls per cohort | Original failures per cohort | Controls |
| --- | --- | --- |
| 96 | 48 | Group/session queries of zero, caller leader, both workers, child leader and child worker. |
| 960 | 768 | Three live workers with zero, caller, child, missing and negative group arguments; exact `EINVAL` and unchanged leader state. |
| 128 | 0 | Real child assignments to its own group through zero and back to the caller's group. |
| 2,048 | 2,048 | Child-worker group/session queries after every successful assignment. |
| 336 | 0 | Independently retired-worker queries and setters, including missing groups and negative-group precedence. |
| 48 | 24 | Calls from a worker: zero and own-TID queries, process-wide zero setter behavior, and own-TID setter refusal. |

Seven raw register-word forms and genuine musl calls exercise the existing
signed32 import; setter words vary independently. Leader-issued calls check
retained group/session state, and child-worker queries follow actual changes to
its process's group. All worker and child resources are joined/reaped before
the cohort reports completion. Original kernels fail exactly 11,552 controls
per architecture. Corrected kernels and the identical native probe ELFs on
Linux 6.12.51 pass every control on both architectures.

Four warmed 200-cycle cohorts repeat live/retired queries and live-worker
setter refusals. A preopened `/proc/slabinfo` observer compares every live class
and big-page count after settling; all remain flat. AArch64 has 18 live classes
and 73/73 big pages initially, 85/85 in the PID namespace. x86-64 has 14
classes and 179/179 initially, 201/201 in the namespace, in both credential
cohorts. Thread creation and exit are outside the measured interval. The probe
C uses four explicit stack allocas and no allocation, dynamic-array or
fixed-index helper calls.

Four completed production builds qualify original and corrected kernels. Native
runtime and `groupabi` regressions pass on both architectures. Eight host test
files pass. Allocation diagnostics remain byte-identical, including existing
allowance-file refusals. The audit verifies 66 semantic input fingerprints,
15,146 compiler inputs, all 2,014 copied SDK inputs, fresh ARM compiler-command
receipts, source/C/ELF/ISO/kernel identities, Linux references and 84 retained
regular files across eight native qualification profiles. False-assertion and
passing-Linux-as-original controls execute without `-prod`.

The first audit stopped before qualification because its SDK count assertion
incorrectly specified 2,016 files. A complete walk and byte comparison found
exactly the 2,014 regular files in the copied, previously pinned manifest.
The corrected audit verifies that complete set and retains the original
[audit refusal](../tests/linux-compat/results/2026-10-15/grouptid-initial-audit-refusal.log).

Concurrent exit/exec/credential changes, leader-only exit, zombie setters,
namespace nesting and cross-namespace observers, PID reuse, terminal/job-control
signals, GNU libc and translated/ELF32 paths remain unqualified. The three broad
section 15 gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/grouptid-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/grouptid-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/grouptid-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/grouptid-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/grouptid-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/grouptid-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/grouptid-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/grouptid-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/grouptid-check.v), [verdict](../tests/linux-compat/results/2026-10-15/grouptid-audit.log), [SDK inputs](../tests/linux-compat/results/2026-10-15/grouptid-sdk-inputs.json), [lifetime review](../tests/linux-compat/results/2026-10-15/grouptid-lifetime-review.txt).

## Native process group session and exec error precedence

A parent calling `setpgid` on an executed child in another session now receives
`EPERM`. Session eligibility is checked before the executed-child `EACCES`
refusal, following Linux v6.12's
[setpgid ordering](https://github.com/torvalds/linux/blob/v6.12/kernel/sys.c).
Same-session executed children still return `EACCES`, non-children return
`ESRCH`, and negative groups take `EINVAL` precedence. Refusals retain the
existing process groups and sessions.

The change moves an existing scalar session comparison earlier in
`set_process_group`. Existing lookup, table-lock scope, orphan-change stack
storage, group mutation and notification lifetimes are unchanged. Whole
production C differs only in that function's body; the audit requires exact
source changes and unchanged allocation/pin/free call counts, without compiler
identifier normalization.

The `grouporder` probe runs 11,520 controls per architecture across root and
UID/GID1000 cohorts in the initial and one-level PID namespaces. Each cohort
creates a private session and six held targets. Each target sends its
PID/parent/group/session identities through a readiness pipe.
Executed targets re-enter the same ELF through `/proc/self/exe`, publish their
identities from the new entry point, then wait on an inherited release pipe.
Intermediate parents wait for their target children. The cohort releases and
reaps direct children and intermediate parents before reporting completion.

| Calls per cohort | Original failures | Controls |
| --- | --- | --- |
| 448 | 0 | Same-session unexecuted child: real group assignments/restoration, foreign/missing-group `EPERM`, negative-group `EINVAL`. |
| 448 | 0 | Same-session executed child: `EACCES` for nonnegative groups, negative-group `EINVAL`. |
| 448 | 0 | Detached-session unexecuted child: `EPERM` and negative-group `EINVAL`. |
| 448 | 320 | Detached-session executed child: session `EPERM` before exec `EACCES`, preserving negative-group `EINVAL`. |
| 448 | 0 | Same-session unexecuted grandchild: non-child `ESRCH` and negative-group `EINVAL`. |
| 448 | 0 | Detached-session executed grandchild: non-child `ESRCH` before session/exec errors, plus negative-group `EINVAL`. |
| 192 | 0 | Before/after group/session queries of every target. |

Seven group selections include zero, caller and target IDs, a detached-session
leader, a missing positive group and two negative groups. Seven raw register-word
forms and genuine musl calls vary the setter arguments independently. Every
setter checks all held targets' group/session state. The eligible child makes
actual group changes and is restored after each trial. Twelve exec-entry
receipts per architecture are matched to the four cohorts' target identities.
Original kernels fail exactly 1,280 controls each. Corrected kernels and the
identical native probe ELFs on Linux 6.12.51 pass every control on both
architectures.

Four warmed 200-cycle cohorts repeat same-session exec, detached-session child,
non-child and negative-group refusals. Every live slab class and big-page total
stays flat after settling; fork/exec and teardown are outside this interval.
AArch64 retains 18 classes and 111/111 big pages initially, 123/123 in the
PID namespace. x86-64 retains 14 classes and 248/248 initially, 270/270 in the
namespace, for both credential cohorts.
The probe uses five explicit stack allocas and no allocation, dynamic-array or
fixed-index helper calls.

Four completed production builds qualify original and corrected kernels. Native
runtime and worker-TID group/session regressions pass on both architectures;
eight host test files pass. Allocation diagnostics remain byte-identical,
including their existing allowance-file refusals. The audit binds 66 semantic
input fingerprints, 15,146 V compiler inputs, all 2,014 copied SDK files, fresh
ARM compiler-command receipts, source/C/ELF/ISO/kernel identities, Linux
references and 84 retained regular files across eight native profiles.
False-assertion and passing-Linux-as-original controls execute without `-prod`.

The first probe compilation had no guest verdict or init ELF. It lacked the
header defining `unshare`/`CLONE_NEWPID`, and V heap-promoted the state object,
emitting an unavailable `memdup`. The final probe adds that header and uses
explicit stack storage. The audit verifies that exact source transformation
and preserves both architecture compile refusals, their receipts, original
probe source, artifact pins and the initial watcher's missing-ELF refusal.
The syscall expectations are unchanged.

Concurrent exec/exit/credential changes, zombie setters, leader-only exit,
nested/cross-namespace observers, MAC policy, terminal/job-control signals,
PID reuse, GNU libc and translated/ELF32 paths remain unqualified. The three
broad section 15 gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/grouporder-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/grouporder-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/grouporder-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/grouporder-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/grouporder-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/grouporder-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/grouporder-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/grouporder-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/grouporder-check.v), [verdict](../tests/linux-compat/results/2026-10-15/grouporder-audit.log), [initial ARM compile refusal](../tests/linux-compat/results/2026-10-15/grouporder-initial-compile-arm.log), [initial x86-64 compile refusal](../tests/linux-compat/results/2026-10-15/grouporder-initial-compile-x86.log), [initial probe](../tests/linux-compat/results/2026-10-15/grouporder-initial-probe.v).

## Native completed-zombie process groups

`setpgid` now recognizes completed, unreaped children and groups represented
only by completed zombies. Eligible unexecuted same-session children can change
groups until reaping; executed children still receive `EACCES`, detached-session
children `EPERM`, and negative groups take `EINVAL` precedence. After reaping,
queries and positive-group setters targeting the old PID return `ESRCH`, and
an empty former group cannot accept a live child.

Two guards now admit an exiting process only when its `exit_published` flag is
set under the process-table lock. Incomplete teardown remains excluded. This
is a bounded stable-zombie contract; Linux behavior while exit publication or
reaping races a caller remains unqualified. The reference follows Linux v6.12's
[setpgid task/group lookup](https://github.com/torvalds/linux/blob/v6.12/kernel/sys.c)
and is checked with identical native ELFs on Linux 6.12.51.

An independent source lifetime review confirmed that table locking protects
borrowed processes through mutation and serializes reaping. Exit publication
follows sibling, descriptor, namespace and address-space teardown. Zombie
fields and PID-namespace numbering remain usable until reaping; the existing
namespace-release path does not free namespace identity objects or PID maps.
Orphan tracking still ignores zombies as live/stopped members, skips their
former child relationships and retains scalar group/session IDs through
delivery. No allocation, pin or free is added. Whole production C differs only
in the two eligibility conditions within `set_process_group`, without compiler
identifier normalization.

The `groupzombie` probe runs 17,152 controls per architecture in root and
UID/GID1000 cohorts in the initial and one-level PID namespaces. Each cohort
creates four direct children and one held live child. One unexecuted child
starts as its own group leader in the caller's session. Another child executes
in the caller's session; the other two create private sessions, with one also
executing. Executed targets re-enter the same ELF through `/proc/self/exe`.
Release pipes make the first four exit with status zero. `waitid(WNOWAIT)`
confirms `CLD_EXITED`, and pidfd `POLLIN` without `POLLHUP` independently confirms
published exit before the matrix starts. The fifth child stays alive.

| Calls per cohort | Original failures | Controls |
| --- | --- | --- |
| 448 | 320 | Same-session unexecuted zombie: real group creation/moves/restoration, foreign/missing groups and negative-group errors. |
| 448 | 320 | Same-session executed zombie: exact `EACCES` and negative-group `EINVAL`. |
| 448 | 320 | Detached-session unexecuted zombie: exact `EPERM` and negative-group `EINVAL`. |
| 448 | 320 | Detached-session executed zombie: session `EPERM` before exec errors, plus negative-group `EINVAL`. |
| 512 | 64 | Live child joins a zombie-only group before reap; foreign/missing/negative groups; all former-group refusals after reap. |
| 1,984 | 0 | Before/after zombie queries, reaped-target queries and exact reaped setter errors. |

Seven raw register-word forms and genuine musl calls vary setter PID/group
arguments independently. Every attempted mutation checks the caller and all
remaining targets' group/session state. Successful zombie moves also change
`waitid(P_PGID, WNOWAIT)` selection: the child's own group selects that zombie,
while moving it out makes the old group return `ECHILD`. Restoring the zombie
restores that selection. Each successful live join is undone before the next
attempt, leaving only the zombie to establish group existence. The four
zombies are explicitly reaped before old-PID and former-group tests, and the
live child is released/reaped before cohort completion. Eight actual exec
entries, sixteen exit/readiness edges and sixteen reaping edges per
architecture are matched to the reported identities.

Original kernels fail exactly 5,376 controls per architecture. Corrected kernels
and identical native probe ELFs on Linux 6.12.51 pass every control on both
architectures. Four warmed 200-cycle cohorts alternate raw upper-word and real
musl calls. They move/restore the zombie, check wait-group selection, join/leave
its group with the live child, and repeat exec/session/negative-group refusals.
All live slab classes and big-page totals stay flat after settling. Fork, exec,
pidfd setup and final reaping are outside the measured interval. The probe C
uses five explicit stack allocas and no allocation, dynamic-array or fixed-index
helper calls.

AArch64 compares 18 classes and retains 105/105 big pages initially, 117/117
in the PID namespace. x86-64 compares 14 classes and retains 267/267 initially,
289/289 in the namespace, in both credential cohorts.

Four completed production builds qualify original and corrected kernels.
Runtime and session/exec-order regressions pass on both architectures; eight
host test files pass. Allocation diagnostics remain byte-identical, including
existing allowance-file refusals. The audit binds 66 semantic input fingerprints,
15,146 V compiler inputs, all 2,014 copied SDK files, fresh ARM compiler-command
receipts, source/C/ELF/ISO/kernel identities, Linux references, independent
lifetime review and 84 retained regular files across eight native profiles.
False-assertion and passing-Linux-as-original controls execute without `-prod`.

Concurrent teardown/reap/credential changes, zombie descendants, non-parent
mutations, groups retained by live members after leader reap, nested or
cross-namespace observers, MAC policy, terminal/job-control signals, PID reuse,
GNU libc and translated/ELF32 paths remain unqualified. The three broad section
15 gates remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/groupzombie-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/groupzombie-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/groupzombie-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/groupzombie-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/groupzombie-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/groupzombie-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/groupzombie-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/groupzombie-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/groupzombie-check.v), [verdict](../tests/linux-compat/results/2026-10-15/groupzombie-audit.log), [lifetime review](../tests/linux-compat/results/2026-10-15/groupzombie-lifetime-review.txt).

## Native wait selectors and scalar argument words

The native AArch64 and x86-64 `wait4` and `waitid` adapters now import their
Linux scalar arguments from the low 32 register bits. `wait4` sign-extends
`pid_t` and `int` options; `waitid` imports its type/options as signed32 and
retains only the ID's low32 bits before its existing positive/nonnegative
validation. P_ALL continues to ignore the ID. `wait4(INT_MIN)` returns ESRCH
after option validation, so invalid options retain EINVAL priority. Pointer
arguments stay full-width. The patch changes two entry points and adds no
allocation, pin, reclamation, waiter, child-claim or lock changes.

Four fresh production kernels were built from committed base
`6fb03bb2e396a18b64d8795e80be39b660945f59`, with only the owned
`kernel/userland/linux_task.v` patch in the corrected builds. The audit compares
the complete generated C on both architectures: only the two adapter definitions
and their exact declarations differ; no identifier normalization is used.
The unchanged final probe source, C and ELF are bound across original/corrected
Vinix and Linux 6.12.51 reference runs.

Root and UID/GID1000 run in initial and one-level PID namespaces. Each cohort
creates a fresh session and two held direct children: one leads a separate
process group and the other stays in the caller's group. Readiness pipes prove
their reported PID, parent, PGID and SID before testing. Release of the first
child produces a status-37 zombie observed with WNOWAIT. It remains available
through repeated selection and is explicitly reaped before old-ID errors are
tested. The second child is released and reaped with status 38 before completion.
Topology records and four exit/reap edges per architecture bind these phases.

Seven raw register forms cover zero/sign extension and upper words 1,
0x12345678, 0x80000000, 0x7fffffff and 0xffffffff. Genuine musl wait4/waitid
calls are the eighth form. Wait4 independently varies PID/options; waitid
independently varies type/ID/options through all 512 form triples per selector.
Each architecture runs 118,272 controls:

| Per-cohort class | Controls | Original failures |
| --- | ---: | ---: |
| Held-child wait4 selectors, two valid option sets, untouched status/rusage | 1,152 | 948 |
| Invalid wait4 options, including INT_MIN error priority | 576 | 0 |
| Live-child waitid selection/errors and empty-event siginfo/rusage | 8,704 | 5,155 |
| Invalid waitid options before type/ID selection | 8,704 | 0 |
| Zombie WNOWAIT waitid selection and successful siginfo | 8,704 | 5,155 |
| Held-child ignored wait4 outputs, WNOWAIT waitid EFAULT and reaped-ID errors | 1,728 | 1,605 |

Selectors include PID, caller and child process groups, all children, absent
IDs, zero, -1 and INT_MIN. Exact EINVAL/ECHILD/ESRCH/EFAULT behavior is checked.
Valid waitid events verify signo, errno, code, PID and status; empty events also
verify zero UID. Successful-event UID/accounting is outside this qualification.
No-event wait4 ignores inaccessible status/rusage pointers; zombie waitid with
WNOWAIT returns EFAULT for bad info/rusage and independently remains waitable.
Original kernels fail exactly 51,452 controls per architecture. Corrected Vinix
and identical native ELF probes on Linux pass every final control.

The first probe contained two incorrect assumptions. Linux writes waitid's
siginfo fields even for these selector/option errors, and wait4 may consume a
zombie before returning a status/rusage copyout failure. The strict exploratory
Linux runs fail both assumptions and reach ECHILD at the later attempted reap;
their PID1 then exits and Linux panics. Their original source, C, ELF, receipts
and serial logs remain retained and pinned. The final probe compares exact
errors without asserting unchanged error siginfo, and exercises wait4 output
pointers only on a held child with no event. WNOWAIT waitid retention remains
required. **Waitid error copyout and wait4 consumption after copyout failure
remain unsupported semantics**, published separately from this ABI fix. The
diagnostic records are never counted as passing references.

The p2 Linux probes pass, but their controller rejects both receipts because
it retained the previous fixture's expected case counts. A corrected controller
boots the same unchanged ELFs again in p3; the refused receipts are retained.
The first audit also refuses an incorrect estimate of more than 60 diagnostic
files: the complete original walk contains 58 regular files, now checked exactly.
Controller/audit source, binary, log and status identities are retained, and
another audit refuses the old template's missing build-log name before it is
corrected to the actual producer path. These refusals stay pinned and the
final audit passes separately. See the
[controller/audit refusal notes](../tests/linux-compat/results/2026-10-15/waitabi-controller-audit-refusal-note.txt).

Four warmed 200-cycle cohorts alternate upper-word raw and genuine musl calls:
held-child nohang wait4, zombie group WNOWAIT waitid and INT_MIN ESRCH. Slab
objects and big-page totals remain flat after settling. Setup, fork and reap
are outside the measured interval. AArch64 compares 18 classes and retains
78/78 big pages initially and 90/90 in the namespace for both users. x86-64
compares 14 classes and retains 195/195 initially and 217/217 in the namespace,
also for both users. The probe C uses five explicit stack allocas and no
malloc/memdup/dynamic-array/fixed-index calls.

Runtime and completed-zombie group regressions pass on both architectures;
eight host test files pass. Allocation diagnostics are byte-identical, including
existing allowance-file refusals. The audit binds 66 inventory inputs, 15,146
compiler inputs, all 2,014 private SDK files, fresh ARM command receipts,
source/C/ELF/ISO/kernel identities and 84 retained regular files across eight
final native profiles. False-assertion and passing-Linux-as-original controls
execute without `-prod`. The immutable
[Linux v6.12 implementation](https://github.com/torvalds/linux/blob/v6.12/kernel/exit.c)
and its digest are retained with the evidence.

The older inventory input list omits `linux_task.v`; the wait source is pinned
separately against the committed base, both worktrees and complete production C.

P_PIDFD, __WCLONE/__WALL/__WNOTHREAD, ptrace/cross-thread waits, consuming
copyout faults, error siginfo copyout, successful-event UID/accounting,
concurrent group/reap changes, signal restart, GNU libc and translated/ELF32
paths remain outside this bounded contract. The three broad section 15 gates
remain open.

- [AArch64 evidence](../tests/linux-compat/results/2026-10-15/waitabi-evidence-aarch64.json), [native receipt](../tests/linux-compat/results/2026-10-15/waitabi-after-aarch64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/waitabi-before-aarch64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/waitabi-reference-aarch64-receipt.json).
- [x86-64 evidence](../tests/linux-compat/results/2026-10-15/waitabi-evidence-x86_64.json), [native receipt](../tests/linux-compat/results/2026-10-15/waitabi-after-x86_64-receipt.json), [original receipt](../tests/linux-compat/results/2026-10-15/waitabi-before-x86_64-receipt.json), [Linux reference](../tests/linux-compat/results/2026-10-15/waitabi-reference-x86_64-receipt.json).
- [Maintained audit](../tests/linux-compat/waitabi-check.v), [verdict](../tests/linux-compat/results/2026-10-15/waitabi-audit.log), [failed diagnostic notes](../tests/linux-compat/results/2026-10-15/waitabi-diagnostic-note.txt), [diagnostic input pins](../tests/linux-compat/results/2026-10-15/waitabi-diagnostic-inputs.json).
