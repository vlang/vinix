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

Shared file-offset atomicity across a whole vector, immutable iovec imports,
Linux stream short-read/message behavior and translated/ELF32 variants remain
unqualified. The three broad Linux/POSIX acceptance gates stay open.
