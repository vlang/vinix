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
