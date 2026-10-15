# Development, containers and virtualization status

This page records the implementation and acceptance boundaries for
[roadmap section 17](../roadmap.md#17-development-containers-and-virtualization).
The workstream remains incomplete. The new userland tools do not establish
missing kernel isolation, debugger or hardware virtualization interfaces.

| Requirement | Available implementation | Remaining acceptance / implementation |
| --- | --- | --- |
| Installed-system self-hosting | [V build plans](../tools/development/README.md) pin prepared source/tool/SDK inputs, build in a private copy, enforce deadlines and record output hashes. Native kernel, utility, init and package-CLI recipes are documented. [Guest runner checks](../tests/development/README.md) qualify UID 1000 source/link copying, epoch/environment control, matching artifacts and changed-input refusal on both architectures. AArch64 rebuilds the V C-backend compiler in two fresh workspaces, then uses each rebuilt compiler for the four `util-vinix` utilities, `init` and the package CLI from immutable committed sources. It executes the tools, packs the compiled `lscpu` and signs a consumer release. Generated-C/compiler/executable/payload/manifest/index/signature hashes match; the controller independently verifies the signature and payload metadata with full SDK/V/runtime pins. | Complete native kernel/desktop/dependency recipes, init boot/login qualification and the remaining userland/package workflows; rebuild all four requested layers inside an installed system on both architectures. Basic runner checks use a prebuilt V payload; AArch64 compiler/utility/init/package checks use native compilation. No full self-hosted rebuild was run here. |
| Toolchains and developer applications | [Project qualification](../tools/development/qualification.md) covers C/C++/V, Node/TypeScript, Rust/Cargo, Go, Java, make/CMake/Ninja, npm, GDB and SQLite. A [V compiler stager](../tools/development/stage-v.v) exports committed compiler/library sources, records portable-source adaptations and prepares matching static ELF installations for both architectures. [Native guest checks](../tests/development/README.md) passed C/C++ thread/file projects and the V file project as UID/GID 1000 on AArch64 with GCC/G++ 11.2.1 and V 0.5.2 `f6358ec`. AArch64 also rebuilt the V C-backend compiler twice and used both matching compilers to build reproducible projects and signed packages. Both architectures passed prepared V version/help and bounded diagnostic-log gates; AArch64 verified actual assertion failures with relative source paths. Missing tools and failed workflows remain failing gates. | Qualify the remaining V backends, reference profiles and native x86 compiler projects with exact package versions and retained receipts; qualify IDE workflows and broader package ecosystems. Python/Meson execution is excluded by the repository's no-Python rule, so their acceptance stays open. |
| Debugging and diagnostics | Dumpability and authorized `process_vm_readv/writev` already exist. The GDB profile requires a real source breakpoint, backtrace and continued execution. The existing bounded security-event ring now uses stack-backed producer records; [native checks](../tests/overlay-rename/security-events.md) cover both producers, copied labels, ring counters and live authorization of inherited report descriptors. | Native ptrace attach/register/step/events, ELF core generation and output/limit policy, profiler events, process stack sampling and authorized hang/crash reporting. No new kernel tracing interface is claimed. |
| OCI and rootless containers | Existing mount/PID/IPC/UTS namespaces, resource-group controls and overlay copy-up provide parts of container support; see [resource groups](resource-groups.md) and [compatibility status](linux-posix-compatibility.md). | User ID mapping, user/network namespace ownership, network isolation, complete delegation and OCI security semantics; mainstream-runtime and rootless adversarial qualification. Existing refusal of unsupported isolation stays intact. |
| Practical hardware VM hosting | QEMU provides practical RAM sizes and multiple virtual CPUs. The [VM manager](../tools/development/virtual-machines.md) selects an accelerator explicitly. The native Intel backend supports page-backed RAM up to 1 GiB, with allocation rollback, shared mapping lifetimes and EPT invalidation. | Native Intel still has one vCPU and a real-mode entry API. Larger-memory VM entry requires physical/nested VT-x qualification. AMD SVM, ARM virtualization, interrupts and device integration remain open. QEMU TCG inside Vinix does not satisfy hardware acceleration acceptance. |
| VM integration and lifecycle | Private per-VM qcow2 disks/firmware variables, QMP lifecycle, offline paired snapshots, explicit user networking/loopback SSH forwarding, read-only 9p shares and a guest-agent transport. | Qualify guest OS workflows inside Vinix, provide Vinix guest tools/drivers, qualify shared folders and network behavior, and implement running-state snapshots and crash-atomic snapshot transactions if required. |
| Server/SSH/CI and automation | Native SQLite transaction/rollback/reopen/integrity and authenticated HTTP/CGI projects on both architectures. AArch64 also passes two scheduled native Go CI builds with matching artifacts, isolated credentials and refusal of an existing output. [Per-account interval jobs](../tools/development/scheduled-jobs.md) use pinned executables, selected environment, protected credential files and durably reserved attempts for fresh outputs. [Native x86_64/AArch64 job checks](../tests/development/README.md) qualify ordinary-account execution, private receipts, credential/output isolation, unsafe-file refusal, deadlines, INT/TERM group retirement, watcher ticks with one PID, concurrent-owner refusal and killed-owner retry/acknowledgement. The [VFS rename regression](../tests/vfs-rename/README.md) covers the reproduced watcher-state publication race. | Installed-system service/boot integration, wider database/server/TLS/load qualification, authenticated SSH development, native x86 CI and broader CI/deployment workflows. A retained x86 HTTP connection-aborted run still needs investigation. |

Validation on 12 October 2026 used the Darwin ARM host, V 0.5.2 `f6358ec`,
QEMU 11.1.1 and the installed musl cross-compilers. All checks below passed:

```
v -cc cc test tools/development/devcore
v -cc cc test tools/development/qualcore
v -enable-globals -cc cc test tools/development/vmcore
v -enable-globals -cc cc test tools/development/jobcore
v -cc cc test tools/qmpclient
```

The host project run passed C, C++, V, Node, GNU make, CMake, Ninja, npm offline
packing/install/resolution and SQLite commit/rollback/reopen checks. The VM suite
ran real QEMU with two vCPUs and checked lifecycle, concurrent-owner refusal,
disk writes/snapshot restoration and independent firmware state. The job suite
checked actual execution, protected credentials, deadlines, interrupted state and
repeated watcher execs. These are host results, not installed-Vinix receipts.

The V [stager](../tools/development/stage.v) built all four commands as static
little-endian ELF64 for AArch64 and x86_64 and checked each ELF machine ID. Local
staging receipts and binaries are retained in
`/tmp/vinix-dev-aarch64-20261012-c` and `/tmp/vinix-dev-x86_64-20261012-c`;
the host project receipt is in `/tmp/vinix-development-qualification-20261012-a`.
These paths are local evidence, not dependencies of the maintained commands.

Native hypervisor memory validation on the same date built isolated kernels
from `1c2e33ce` plus the memory changes. The x86 memory fixture allocated and
released 1 GiB, checked EPT entries and zeroed frames, injected failures through
VMCS/table/RAM/FPU allocation, and restored exact free-page counts after 100
VM lifetimes. The public API also created a 1 GiB VM and accessed its final
byte. Another 100 sessions checked unaligned I/O, shared mappings after close
and fork, concurrent creation, private/out-of-bounds mapping refusal and
ordinary-user permissions. Slab snapshots after the retirement grace remained
within the fixture's four-object allowance for timer/thread noise. New kernel
lifetimes received an independent source and generated-C review.

The V [memory controller](../tests/hypervisor/README.md#guest-memory-and-session-lifetime)
retains kernel, fixture and ISO SHA-256s, QEMU arguments and a passing receipt
at `/tmp/vinix-hv-memory-guest-20261012-i/receipt.json`, with the serial transcript
beside it. Production kernels built and booted on x86_64 and AArch64 with the
test tags disabled. The ABI/VMX ASan/UBSan and optimized assembly checks passed,
including INVEPT operand order and immediate status capture; the four checker
test files also passed. Actual INVEPT and hardware guest entry were not run:
the x86 host backend here is QEMU TCG, and ARM has no native backend.

The AArch64 desktop harness passed `idle,apps,drag` and `ops,churn,cache` using
the isolated production kernel. All 36 cohorts of 200 system calls reported
zero retained bytes per operation; all four programs run 300 times each
reported zero retained bytes. The cache scenario retained 16 MiB of cache
after writing 32 MiB. Results are in `/tmp/vinix-hv-memory-desktop-full.json`
and `/tmp/vinix-hv-memory-retention.json`. These broad AArch64 regressions
complement the x86 hypervisor memory fixture.

`tests/kernel-allocs/run.sh` still fails its existing allocation-site allowlist
on both the unchanged `1c2e33ce` baseline and the ownership refactor. Comparing
the 215 file/kind counts showed no increases. The global allowlist was not
expanded to conceal those baseline failures; they remain a separate failing
gate, alongside the hardware VM-entry and wider section 17 acceptance work.

Native package validation on 13 October 2026 used isolated production kernels
from `776b9f0d3`, the development commands in
`build/development17-20261013/tools-arm-budget`, GCC/G++ 11.2.1 (20211120),
BusyBox 1.36.1 and V compiler sources at
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`. Both architecture compiler stages
completed with musl GCC 14.2.0 and `VINIX_V_COPT=-O0`. The source adaptations
are recorded in their receipts, including relative assertion diagnostics for
reproducible builds. The native failure project still exits 1 and reports its
file, line, expression and panic; no assertion-disable flag is used.

The AArch64 HVF run passed all 19 steps in each fresh workspace as UID/GID 1000,
including native package compilation, packing and signing. Its independently
validated 14-record receipt and transcript are retained in
`build/development17-20261013/guest-arm-package-assertions`. The committed source
revision is `49070d4e39f4d4c64c7658a7f1e03492297b2ea0`; the prepared source pin,
including the generated assertion fixture, is
`08e2fa118cb5eefd23ed5d13a096e55527d7f02d34c26dd88b155419da59f2d5`.
The copied SDK pin is
`ad1baf20e589e88e753cccbe863127d5e8e1cc9782d228dc956eaaff79ab8717`
and V installation pin is
`45468219a77a74bfb970078509adc707c46fc6df067483f828f0434c9cff55da`.
The x86 TCG startup/help and account/job/build regression passed in
`build/development17-20261013/guest-x86-v-assertions`; no native x86 GCC SDK was
supplied. The signed fixture uses a public synthetic zero seed. It proves
ordinary-user native package publication; enrollment, installed-app execution,
compiler rebuilding and complete kernel/desktop builds were outside that run.

The later AArch64 HVF compiler-rebuild gate on 13 October 2026 passed all 23
steps in each fresh workspace, recorded `selfhost_v: true` and retained 14
independently validated records in
`build/development17-20261013/guest-arm-selfhost-v-m`. The ordinary account
rebuilt V's C-backend compiler, checked its pinned revision and used that exact
executable for all subsequent V project builds. Those builds disable caches
and select the separately pinned `/usr/lib/vlang` installation with `VINIX_V_ROOT`.
The generated C and rebuilt compiler matched across workspaces, as did every
project binary and signed package artifact. Selected hashes and complete tool
versions are recorded in [the guest qualification evidence](../tests/development/README.md).
The source revision was `116ba2c7850ca331a5bf9851470f1bae4a9136d3`, source
pin `73b14d03f8e7ec87fbb27143f96e6b9ce67c471910d5d6b86d85d2d1695bffe1`
and V installation pin
`d4b98ffc143c42d97437d9848000920daa7eb99a8e0568fd679f8cad5a834de4`.

The isolated kernel used `776b9f0d3` plus `116ba2c78`, which scales the bounded
metadata budget for larger development machines. This resolves the measured
per-creator mapping-budget denial during native compiler assembly while retaining
the RAM fraction, resource-group admission and cleanup reserves. Production
kernels built on both architectures, and exact-budget exhaustion/recovery
passed in native V fixtures on both. The larger existing C resource fixture
still fails its mapping-array bound on both unchanged and updated kernels;
[that baseline failure remains recorded](kernel-resources.md).

The updated x86 TCG compiler startup/help and account/job/build regression
passed in `build/development17-20261013/guest-x86-v-pinned`. Both architecture
runs also verified the first and last blocks of bounded command logs as UID
1000. No native x86 GCC SDK was supplied. Full kernel/desktop self-hosting,
x86 compiler/project rebuilding and the wider toolchain gates remain open.

Native job lifecycle validation on 13 October 2026 passed on both architecture
kernels above using the staged public scheduler as UID/GID 1000. The fixture
checked a real job and descendant through a one-second deadline, SIGINT and
SIGTERM, confirmed eventual PID removal, refused concurrent runners and repeated
watcher ticks under one owner PID. Killing the owner left the interrupted job
blocked until its live group was retired and the account acknowledged it; one
successful recovery then completed. The controller independently checked six
additional state records and their exact plan pins. The passing 12-record
receipts are retained in `build/development17-20261013/guest-arm-job-control-d`
and `build/development17-20261013/guest-x86-job-control-d`. Installed services
and complete database/server/SSH/CI workflows remain open.

The job-control work exposed ordinary signal authorization losing the target's
user-namespace identity during exit. Both architecture baselines reproduced
`EPERM` for UID 1000 probing its own unreaped child. Ordinary signals now consult
the existing saved namespace identity under the process-table lock, matching
pidfd authorization through namespace retirement. The UID, capability, session
and mandatory security checks remain enforced. Both isolated production kernels
built, and the native regression passed 100 authorized zombie probes/signals,
foreign-account refusal and `ESRCH` after reap. The account, job-control and build
gates also passed in `build/development17-20261013/guest-arm-signal-fixed` and
`build/development17-20261013/guest-x86-signal-fixed`. This fixes exit-time signal
identity; it does not implement the remaining debugger or container interfaces.

The additional [reference-SDK gate](../tests/development/README.md) imports a
prepared native prefix, independently pins its runtime and selects explicit
`make,cmake,ninja,sqlite,node,go,java,http` workflows. It runs pinned versions and real
projects through the build runner twice as UID/GID 1000, validating exact plan,
input and executed-command pins and matching produced artifacts. On 13 October
2026 AArch64 passed GNU make 4.4.1 and the Ninja-compatible Samurai CLI with
GCC 11.2.1, plus SQLite 3.53.4. x86_64 passed SQLite 3.53.4. Native transaction,
rollback, reopen and integrity checks produced matching database files on both
architectures. The 17-record receipts and complete versions remain in
`build/development17-20261013/guest-arm-reference-buildtools-c` and
`build/development17-20261013/guest-x86-reference-sqlite-c`. The existing
[SQLite package qualification](../tests/packages/sqlite-profile-check.md)
separately covers WAL and signed application/runtime lifecycle workflows.
Node reference gates, native x86 build systems, other language/IDE profiles
and complete server/SSH/CI projects remain open.

The later AArch64 CMake reference gate also passed on 13 October 2026 using the
maintained [SDK stager](../tools/development/stage-cmake.v). CMake 3.31.1 and its
module/library closure configured and built the C project, then executed the
exact resulting binary in both workspaces. The stager preserves the compiler's
musl/libgcc inputs, resolving the measured older-linker rejection of a newer
library's `.relr.dyn` sections. Its complete stage is retained in
`build/development17-20261013/reference-arm-cmake-maintained`, and the passing
17-record guest receipt is in
`build/development17-20261013/guest-arm-reference-cmake-maintained-c`.
SDK/module/runtime pins and matching program hashes are recorded in the guest
documentation. Wider CMake project/platform support and the remaining language,
IDE, server, container and hardware-VM gates remain open.

The maintained [Go SDK stager](../tools/development/stage-go.v) and reference
gate also passed Go 1.23.9 on AArch64 HVF on 13 October 2026. The pinned native
compiler built and executed the goroutine/channel/file project in two fresh
UID/GID 1000 workspaces. Both program and readback hashes matched. Go uses a
private cache, local toolchain, offline resolution, trimmed paths and no VCS
stamping; no permission override was needed. All 17 native receipt records and
the account/job/build gates passed in
`build/development17-20261013/guest-arm-reference-go-d`.
The SDK/runtime/tool and matching artifact hashes are recorded in the guest
documentation. This qualifies the pure-Go reference project through Vinix's
Linux ABI. Native x86 Go, cgo, wider module/network/server projects and the
remaining section 17 gates stay open. Completed image, firmware and redundant
SDK imports may be pruned; qualification receipts and serial logs remain.

The maintained [OpenJDK SDK stager](../tools/development/stage-java.v) and
explicit Java JIT reference gate passed OpenJDK/`javac`/`jar` 25.0.4 on AArch64
HVF on 13 October 2026. UID/GID 1000 compiled, packed and ran the thread/file
project in two fresh workspaces, producing identical class/JAR/data files.
The JAR entry timestamp is fixed to the reference epoch. The disposable guest
uses the existing administrator-controlled `wxallowed` policy on only the
pinned, read-only `nosuid,nodev` JDK mount. It verifies denied requests before
approval, outside that mount and after revocation, plus ordinary-user
remount/write refusal. Native reports preserve each actual child request;
the qualifier itself never grants production approval. All 17 receipt records
passed in `build/development17-20261013/guest-arm-reference-java-jit-b`.
Exact SDK/JDK/runtime and matching artifact pins are recorded in the guest
documentation. Native x86 Java and wider JVM/IDE/debugger, network/TLS/module
and production-server workloads remain open.

The updated qualifier also retained the matching Go project artifacts with
JIT disabled, and the x86_64 account/job/build regression passed using the
updated fixture. These receipts remain in
`build/development17-20261013/guest-arm-reference-go-jit-regression-a` and
`build/development17-20261013/guest-x86-java-fixture-regression-a`.

The maintained [minimal HTTP server builder](../tools/development/build-http.v),
[SDK stager](../tools/development/stage-http.v) and HTTP reference gate passed
on AArch64 HVF and x86_64 TCG on 13 October 2026. Each native run served real
requests from the V client and executed the pinned V CGI fixture in two fresh
UID/GID 1000 workspaces. Missing/wrong credentials left the data artifact
absent; GET/HEAD, missing/private paths, encoded traversal and 16 repeated
requests matched their expected results. Configuration/data files stayed
private to the account, and the owner retired each server group. Public case
records and artifacts matched across workspaces; each host controller validated
all 19 records alongside the account/job/build regressions. Final receipts
and serial logs remain in
`build/development17-20261013/guest-arm-reference-http-g` and
`build/development17-20261013/guest-x86-reference-http-g`.

The BusyBox 1.36.1 builder records and applies a HEAD correction before native
compilation. The unadapted server sent a file body with HEAD and failed the
gate. Two fresh source builds per architecture with musl GCC 14.2.0 produced
identical server binaries/configurations. Earlier prepared binaries also failed
for a missing x86 HTTP applet and an AArch64 startup SIGSEGV. Those failed
receipts remain evidence; acceptance applies only to the new pinned tuples.
Full source, SDK, runtime and executable pins are recorded in
[the guest qualification evidence](../tests/development/README.md).
TLS, production load, service boot integration and SSH/CI remain open.

The scheduled native Go CI reference gate passed on AArch64 HVF on
13 October 2026. A pinned `vinix-jobs` schedule dispatched `vinix-build` twice
as UID/GID 1000, compiling and executing the Go 1.23.9 goroutine/channel/file
project in distinct reserved-attempt workspaces. Program/data/account-proof
artifacts matched. The private CI credential reached only the selected
coordinator; a pinned child verified that it and unselected parent credentials
were absent from build commands. A third attempt refused an existing output,
preserved its sentinel and recorded failure with attempt/completion counts
advanced to three. The controller independently validated all 22 records in
`build/development17-20261013/guest-arm-reference-ci-d`.

The scheduler reserves attempt numbers before execution and keeps them across
owner acknowledgement. Host tests cover literal/expanded arguments, legacy
receipt migration, interrupted-output preservation and counter exhaustion.
Build/qualifier CLIs now propagate INT/TERM through their active owned groups,
with nested shutdown windows inside the scheduler's eight-second fallback.
Host tests interrupted the actual CLI chain with a compiler and descendant
that ignore TERM, requiring both to retire before the build owner returned.
Native x86 HTTP/account/job/build regressions passed with these tools in
`build/development17-20261013/guest-x86-ci-cancellation-c` (19 records).
An earlier x86 attempt run failed the watcher-state read assertion; a focused
guest test subsequently reproduced a VFS replacement gap and unsynchronized
map changes. The [rename fix and native regression](../tests/vfs-rename/README.md)
pass 8,000 replacements per architecture with concurrent listings and old
descriptors retained beyond the grace period. Its final kernels passed the
AArch64 scheduled Go CI and x86 HTTP/account/job gates. An earlier HTTP run on
the final x86 kernel failed with a connection-aborted error; its failed receipt
is retained separately. The separate [overlay rename qualification](../tests/overlay-rename/README.md)
passes 2,000 concurrent replacements per architecture, preserves both paths on
an ext2 backend error, replaces whiteouts, verifies directory parent link counts
and checks regular upper files after volume remount. Both kernels also pass the
native authenticated HTTP/account/job/build gate with 19 validated records each.
The [durable whiteout qualification](../tests/overlay-rename/whiteouts.md) adds real
ext2 0/0 whiteouts for lower-file deletion, lower-directory removal and
lower-source rename. Hidden paths survive clean volume and overlay remounts;
recreation replaces the marker only after metadata setup and the backing rename
succeed. Private staging validates the work directory, preserves final-parent
identity and refuses further operations after work-directory removal.
The [directory-opacity qualification](../tests/overlay-rename/opacity.md) adds
persistent ext2 markers for recreated and renamed directories, preserving
hidden lower children through clean remounts. Repeated actual `ENOSPC` failures
preserve the whiteout and restore exact disk block/inode counts; recovery and
four read-only filesystem checks pass on both architectures. A separate ext2
fix persists the destination parent's link count when a staged whiteout replaces
an upper directory. Trusted-attribute authorization remains enforced.
The earlier slab samples exposed overlay-node retention on repeated replacement.
Allocation tracking attributes the four small objects across two further
failed creations to the existing `statfs` measurement-interface allocation.
The [filesystem-stat correction](../tests/overlay-rename/statfs.md) removes
that wrapper allocation: 2,000 pathname/descriptor calls and the repeated
storage-failure samples stay flat on both architectures, with consistent
backing values and all four read-only filesystem checks clean.
The [overlay retirement correction](../tests/overlay-rename/retention.md) counts
backing-node ownership, retains exact resource snapshots and retires removed
aliases after descriptor, cwd and grace checks. Managed layer arrays retain
their complete headers until V's destructor runs. Socket creation and resource
adoption share a VFS transaction, transferring the entry's resource pin while
preventing a competing unlink from retiring the placeholder twice.
The [persistent UNIX socket correction](../tests/overlay-rename/sockets.md) keeps
the filesystem inode resource behind a bound endpoint. Direct ext2 and overlay
upper unlink/rebind, replacement, held descriptors, live stream connections,
hardlinks and cross-parent moves pass as UID/GID 1000 on both architectures.
Protected-directory and read-only binds remain refused. Repeated workloads
retain no live allocation growth, removed names stay absent after remount, and
all four read-only filesystem checks are clean.
Closing a separate metadata-only `O_PATH` description also preserves the live
listener; the extended native socket tests qualify this release behavior and
balanced retirement on both architectures.
The [socket metadata authorization checks](../tests/overlay-rename/socket-access.md)
also reject socket operations through `O_PATH` handles before reaching endpoint
state. Native tests cover 16 operations, untouched outputs and pending
connections, and permitted `SCM_RIGHTS` transfer after the sending descriptor
closes. Both architectures pass the same probe binary in Linux reference guests;
the persistent ext2/overlay workloads retain flat live allocations.
The [pathname-open correction](../tests/overlay-rename/socket-open.md) prevents
ordinary `open()` calls from acquiring a live socket transport, preserving
permission/type errors and metadata-only access.
The [pathname transport permission correction](../tests/overlay-rename/socket-permissions.md)
requires write permission for UNIX connections and addressed datagrams. Native
and identical Linux probes cover refusals without queue/peer changes, write-only
sockets, record/datagram traffic and abstract lookup.
The [backing ACL correction](../tests/overlay-rename/socket-acl.md) forwards
permission snapshots and metadata updates to a named socket's retained inode.
Native tmpfs/ext2/overlay checks cover inherited ACL denials/grants, chmod masks,
ownership rollback and metadata persistence; pathname and transport operations
retain their targets through backing callbacks. The
[pathname xattr correction](../tests/overlay-rename/socket-xattrs.md) exposes a
live socket's backing ACL through pathname calls while preserving mount,
owner/capability and descriptor restrictions. Native tmpfs/ext2/overlay checks
and identical Linux probes pass; full socket/path metadata separation and the
broader authorization matrix remain open. The
[socket creation-mask correction](../tests/overlay-rename/socket-umask.md)
applies umask before pathname ACL inheritance. Five masks across stream,
record and datagram sockets pass on both native architectures and identical
Linux probes, with masked ext2/overlay ACL metadata preserved after remount.
The [overlay xattr preflight correction](../tests/overlay-rename/xattr-preflight.md)
validates input and checks the original inode before copy-up, preventing an
immutable lower inode from becoming writable through its new upper copy.
Ordinary-account native tests cover authorization and input refusals without
upper-file creation, successful copy-up and flat allocation counts on both
architectures. Concurrent metadata changes and the broader container
authorization matrix remain open.
The [UNIX descriptor ownership correction](../tests/overlay-rename/socket-ownership.md)
initializes unnamed/pair metadata from creator credentials and accepted metadata
from the accepting account. Ordinary-account metadata changes and acceptance of
an inherited root listener pass with preserved peer credentials on both native
architectures and identical Linux probes.
The [ext2 inode-flag loading correction](../tests/overlay-rename/ext2-flags.md)
restores persisted immutable and append-only protections for files, directories
and the volume root after remount. A separate direct-ext2 native probe checks
both architectures without invoking overlay flag updates.
The [overlay inode-flag correction](../tests/overlay-rename/inode-flags.md)
routes authorized flag updates to upper copies, leaving the lower layer intact.
Copy-up refuses removed or replaced lower-only aliases under its lock, preserving
whiteouts and replacement names while held upper aliases remain supported.
Native authorization, retention and remount checks cover both architectures.
The [generic copy-up protection correction](../tests/overlay-rename/protected-copyup.md)
installs supported immutable and append-only bits on the prepared upper inode
before switching the merged alias. Ordinary-account metadata, append and child
creation checks cover tmpfs, ext2 and stacked overlays on both architectures,
with unchanged lower state, preserved restrictions and persisted upper flags.
Direct raw-upper visibility during preparation remains an existing limitation.
The [stacked-directory population correction](../tests/overlay-rename/stacked-population.md)
prepares a lazy inner overlay's children before collecting the outer view,
preserving an existing lower child without copying the inner directory up.
Mount admission caps backing depth at eight before staging or publication;
native deepest-layer reads and repeated lower/upper/work-depth refusals pass
with flat live allocation counts on both architectures.
Mounted views retain cached backing references after unmount; complete mount
teardown remains open. The stacked copy-up probe uses a private stable lower
subtree and records unrelated lower-mutation/teardown failures separately.
The [mount lifecycle checks](../tests/mount-lifecycle/README.md) cover explicit
refusal of unsupported force/expiry unmount modes and cycle-safe mount moves,
including namespace copies and holders whose ancestors were reparented. Moves
reserve a step within the existing bounded mount cursor before publication
and check existing descendant attachments against the resulting depth.
The [attachment identity checks](../tests/mount-lifecycle/identities.md) qualify
unmount, remount and move refusal through detached/foreign mount descriptors
and cwd, while valid local operations remain available. Retained read-only
descriptions refuse creation, writable opens and truncation even after their
namespace retires. Native ARM/x86 runs and Linux references use the same probe
ELFs; capability denial still precedes attachment validation.
The [new mount admission checks](../tests/mount-lifecycle/admission.md) also
cover new filesystem/devpts destinations and bind sources/targets reached
through detached or foreign fds and cwd. Checks precede backend construction,
and valid local fd-based mounts/binds pass in original and copied namespaces
on both architectures and Linux with shared probe ELFs. Concurrent publication,
propagation and independent PTY namespaces remain open.
The [propagation request checks](../tests/mount-lifecycle/propagation.md) qualify
mount-root/detachment checks, single-mode flag validation and bind-before-
propagation dispatch on both native architectures and the same-ELF Linux
reference. Valid mounted roots still accept propagation requests, including
directory/file bind roots and privileged foreign roots; namespace propagation
effects and their complete authorization model remain unimplemented.
The [pivot-root admission checks](../tests/mount-lifecycle/pivot.md) require
active caller-namespace identities for both roots and the old-root destination,
and follow current mount parents when checking ancestry. A shared inode through
another bind alias cannot authorize the destination. The VFS writer lock covers
resolution, admission and existing publication; nested destinations record their
own containing mount. Native ARM/x86 and same-ELF Linux checks cover repeated
refusals, capability denial and valid tmpfs/bind/nested pivots.
The [pivot lifecycle checks](../tests/mount-lifecycle/pivot-lifecycle.md) qualify
moving the existing old/new mount records, updating their parent routes and
epochs, extracting the new root from its former attachment, and lazy removal
of the old-root attachment subtree while retaining the new root. Held old-root
fds observe subsequent remount policy and the new parent, including across a
second pivot. Tmpfs roots, nested destinations and directory bind roots pass
on both architectures and Linux with the same probe ELFs. Lazy teardown follows
mount identity ancestry rather than inode ancestry. Cursor-depth admission,
namespace-root self mounts and same-directory pivot stacking still need runtime
qualification; publication and namespace-switching concurrency remain open.
The [pivot alias checks](../tests/mount-lifecycle/pivot-aliases.md) qualify
matching mount identity as well as the inode when updating roots and cwd.
Synchronized processes using separate bind aliases retain their paths and
read-only policy while references through the pivoted attachment move. The
caller's private `CLONE_FS` state and a shared sibling thread pass the same
checks on both architectures and Linux with shared probe ELFs.
The [private thread pivot checks](../tests/mount-lifecycle/pivot-threads.md)
extend that traversal to every owned thread view in the caller's namespace,
including when the shared process namespace differs. Separate bind aliases and
copied namespaces retain their root/cwd identity and read-only policy. A full
process-table-locked pass preserves fork inheritance ordering; a busy thread
list is waited for outside that lock using a pinned process, then the traversal
restarts. Independent source/generated-C lifetime review and native ARM/x86
plus same-ELF Linux checks cover the change and a thread-view creation/retirement
loop. Concurrent unshare/setns remains unsynchronized.
The [bind attachment policy checks](../tests/mount-lifecycle/bind-policy.md)
qualify writable opens, truncating opens, `O_CREAT` and `mkdirat` through separate
read-only/writable aliases of the same inode. Explicit path routes select the
attachment while backend read-only state and existing authorization still
apply. Retained fds, copied namespaces, chroot/cwd aliases and private thread
views pass on both architectures and the same-ELF Linux reference. Internal
inode-only creators keep their conservative fallback. The subsequent checks
extend coverage to metadata, hard links, rename, descriptor truncation, `mknodat`
and access queries;
broader policy combinations still need qualification.
The [writer lifetime checks](../tests/mount-lifecycle/writer-policy.md) qualify
regular-file descriptions holding a writer count on their actual mount object.
A read-only bind remount returns `EBUSY` until the shared description's final
release, including dup, fork and mmap retention. Temporary pins cover copy-up,
truncation and descriptor construction, with failed-open rollback. Namespace
copies start with no writers; inherited fds still address their original mount
and may truncate after the copied mount becomes read-only. Both architectures
and same-ELF Linux checks cover size/data/error semantics and inherited-fd
authority after dropping privileges, while pathname access and remount remain
denied. Independent lifetime/generated-C review covers lock ordering and
balanced pins. General mutation/remount serialization, divergent inherited-fd
policy lookup, filesystem-wide remount semantics and persistent/overlay
integration remain open.
The [`mknodat` checks](../tests/mount-lifecycle/mknod-policy.md) carry the selected
directory attachment through special-file lookup and read-only admission, and
through the regular-file branch's second creation walk. Both architectures and
the same-ELF Linux reference cover writable/read-only binds, namespace copies,
chroot/cwd, symlinked parents and detached/retired directory descriptors. Regular
files, FIFOs and zero-device-number character/block nodes retain mode/umask,
ownership and identity semantics; ordinary users remain subject to directory
permissions and device-creation capability checks. Backend construction and
publication are unchanged. Persistent/overlay device integration, general
mutation/remount serialization and complete OCI semantics remain open.
The [access-query checks](../tests/mount-lifecycle/access-policy.md) preserve
mount routes for `faccessat`/`faccessat2` pathname, empty-path descriptor and cwd
queries. Regular-file execution observes `noexec`; nonspecial-file write queries
observe read-only policy after existing permission checks. Device/FIFO/socket
queries keep their special-file exception. Both architectures and same-ELF Linux
checks cover all permission combinations, bind/retained/copied routes, symlink
no-follow and real/effective credential selection without metadata changes.
These remain advisory queries; divergent inherited-FD flags, concurrent mount
changes and broader policy/backend combinations need separate qualification.
The [filesystem-statistics checks](../tests/mount-lifecycle/statfs-policy.md)
report the selected attachment's flags in `statfs` and the actual saved mount's
flags in `fstatfs`. A namespace copy can change pathname reports without
changing inherited descriptor reports. Both architectures and the same Linux
probe cover supported read-only, privilege/device/execution and atime flags,
bind remounts, detached/retired mounts and unprivileged metadata queries.
Existing authorization and descriptor release paths remain. Concurrent remount
snapshots, other inherited-descriptor policy lookups and persistent/overlay
integration remain open.
The [descriptor metadata checks](../tests/mount-lifecycle/descriptor-metadata.md)
extend saved-mount policy to `fchmod`, `fchown` and empty-path `fchownat`.
Inherited writable descriptions remain usable after the copied mount becomes
read-only; inherited read-only descriptions cannot gain mutation authority
when the copy becomes writable. Native ARM/x86 and the same Linux executables
cover regular/directory/unlinked descriptions, dup/fork retention and
unprivileged ownership checks. Existing MAC, attributes, ownership/capability,
copy-up, persistence and release paths are retained. Other metadata families,
concurrent remount serialization and persistent/overlay integration remain open.
The [descriptor timestamp checks](../tests/mount-lifecycle/descriptor-timestamp.md)
apply the same saved-mount policy to `futimens` and empty-path `utimensat`.
Pathname and empty-cwd updates retain their namespace-aware policy. Native
ARM/x86 and the same Linux executables cover opposite copied-mount flags,
regular/directory/unlinked targets, dup/fork retention, ordinary owners,
explicit/current times and omission of either field. Existing authorization,
attribute checks, resource pins, persistence rollback and release remain.
Concurrent remount serialization and the other inherited-descriptor policy
families remain open.
The [descriptor xattr checks](../tests/mount-lifecycle/descriptor-xattr.md)
extend saved-mount policy to `fsetxattr` and `fremovexattr`. Existing path-target
ownership distinguishes namespace-aware pathname checks from descriptor checks;
overlay target copies preserve that distinction. Native ARM/x86 and the same
Linux executables cover opposite copied-mount flags, regular/directory/unlinked
targets, dup/fork retention, binary/empty values, create/replace/remove rules
and ordinary-user/trusted-attribute permissions. MAC, attributes, backend
read-only state, capabilities, copy-up and resource release remain. Concurrent
remount serialization, broader policy combinations and persistent/overlay
integration remain open.
The [descriptor inode-flag checks](../tests/mount-lifecycle/descriptor-flags.md)
extend saved-mount policy to `FS_IOC_SETFLAGS`, including requests that repeat
the current bits. Inherited descriptions retain their original authority when
a copied mount becomes writable or read-only. Native checks exercise regular
files, directories, unlinked files, dup/fork retention, immutable/append-only
transitions and unprivileged capability denials. Existing MAC, argument,
backend, capability, securelevel, copy-up and persistence checks remain.
These flag payloads remain outside the portable Linux reference suite;
filesystem-backed Linux comparison and concurrent remount serialization remain
open.
The [descriptor mapping checks](../tests/mount-lifecycle/descriptor-mmap.md)
use the saved mount's `noexec` policy for private/shared file mappings and
subsequent execute upgrades with `mprotect`. A copied namespace's opposite
flags do not grant or revoke an inherited description's authority. Native
ARM/x86 checks and the same probe executables on Linux cover linked/unlinked
files, ordinary owners, fork inheritance and closed descriptors. Shared mappings
of descriptors opened for reading retain their write restriction. MAC,
mapping/resource pins, maximum protections, fork inheritance and releases remain
unchanged. Concurrent remount timing, broader policy combinations and other
backends remain open.
The [descriptor access checks](../tests/mount-lifecycle/descriptor-access.md)
keep empty-path `faccessat2` queries on the descriptor's saved mount for
read-only and `noexec` flags. Fresh descriptions and pathname queries follow
the namespace copy. Native ARM/x86 and same-executable Linux checks cover
ordinary and `O_PATH` descriptions, unlinked files, directories and a forked
ordinary owner. Existing authorization and error ordering remain unchanged;
these advisory queries do not replace authorization at a later operation.
Concurrent remounts, broader policy combinations and backend integration
remain open.
The [descriptor executable-loading checks](../tests/mount-lifecycle/descriptor-exec.md)
keep direct empty-path `execveat` on the description's saved `noexec` mount.
Pathname requests and recursive interpreter/translator loads retain their
namespace route. Native ARM/x86 and same-executable Linux probes cover actual
image execution through ordinary/`O_PATH` descriptions, unlinked ELFs, ordinary
owners and scripts, plus fresh descriptors and relative/absolute pathname
requests. Existing authorization, W^X and descriptor lifetimes remain.
Concurrent remounts, dynamic interpreters, runtime translation,
divergent paths relative to inherited directory descriptors
and broader backend integration remain open.
The [descriptor W^X checks](../tests/mount-lifecycle/descriptor-wx.md) keep
empty-path executable descriptions on their saved attachment's `wxallowed`
approval. Both directions of approval changes in a copied namespace are
covered for linked/unlinked native ELFs, ordinary owners, root without
`CAP_SYS_ADMIN` and scripts. Successful images check actual RWX `mmap` and
`mprotect` policy, also after fork. The explicit environment request, default
W^X and initial-namespace privileged override remain enforced. This policy is
Vinix-specific and excluded from the portable Linux suite. Broader runtime,
backend and concurrent-remount qualification remains open.
The [execveat validation checks](../tests/mount-lifecycle/exec-flags.md) reject
unsupported flag bits with `EINVAL` and report `ELOOP` for final symlinks left
unfollowed, including `O_PATH` link descriptions. Native ARM/x86 and the same
probe executables on Linux cover absolute, relative, empty-path and unlinked
descriptions, legal flags, ignored upper register bits, ordinary UID/GID 1000
and selected path/flag/descriptor error precedence. Existing mount, MAC, W^X,
credential and image-loading checks remain in place. General relative-directory
mount routing and broader combined-error qualification remain open.
The [execveat descriptor ABI checks](../tests/mount-lifecycle/exec-fd.md)
normalize `dirfd` as a signed 32-bit argument before direct-image lookup,
directory lookup and synthesized script-name construction. Both architecture
implementations ignore unused register bits while preserving the selected
descriptor, its mount and authorization. The fixture covers linked/unlinked
native images, read-only/`O_PATH` descriptions, scripts, ordinary UID/GID 1000,
relative directories, `AT_FDCWD`, invalid descriptors and `noexec` refusal.
General inherited-directory mount routing remains open.
The [close-on-exec script checks](../tests/mount-lifecycle/exec-cloexec.md)
refuse empty-path execution of valid scripts through `FD_CLOEXEC` descriptors
with `ENOENT` before interpreter launch. ELF execution, flag clearing and
duplicate-descriptor independence remain usable; existing authorization and
descriptor releases remain in place. Relative pathname scripts through
close-on-exec directory descriptions are covered separately by the
[directory-relative script checks](../tests/mount-lifecycle/exec-relative.md).
Those checks provide descriptor-rooted interpreter names, pin the directory
through image loading, and refuse scripts whose names would become inaccessible
at exec. Renamed directories, cwd decoys, nested interpreters, ordinary users,
absolute/`AT_FDCWD` requests, native ELF and lookup/authorization errors are
covered. Divergent inherited-directory mount flags remain open.
The [pathname truncation checks](../tests/mount-lifecycle/truncate-policy.md)
also require a writable resolved attachment before changing size or copying up
an overlay. Lookup retains the node and original resource under the VFS lock,
and releases both after the complete operation, including denied requests and
backend errors. Both native architectures and same-ELF Linux checks cover bind
aliases, namespace copies, chroot/cwd, detached roots and retired namespaces,
with preserved data and UID/GID 1000 denial. Concurrent remount and namespace
switching remain outside this qualification.
The [mode and ownership checks](../tests/mount-lifecycle/metadata-policy.md)
extend attachment-based read-only policy to `fchmod`, `fchmodat`, `fchown` and
both pathname and empty-path `fchownat`. Path operations preserve the starting
directory's mount and existing target/resource pins; descriptor operations use
the description's saved mount. Both architectures and same-ELF Linux checks
cover actual mode/UID/GID changes, symlink no-follow behavior, retained read-only
paths and UID/GID 1000 denial. Ownership, capabilities, MAC and attribute checks
remain before mutation. Other metadata paths
still need complete attachment-policy coverage.
The [timestamp checks](../tests/mount-lifecycle/timestamp-policy.md) extend that
policy to `utimensat` and its descriptor/legacy forms. Path and empty-path cwd
operations preserve their starting mount; descriptors supply their saved route.
Both native architectures and same-ELF Linux checks cover explicit and current
times, one omitted timestamp, symlink no-follow, detached/retired descriptions,
cwd aliases and UID/GID 1000 denial. Both-omit short-circuit semantics, invalid
input error ordering and concurrent mount/cwd changes remain outside this
qualification.
The [extended-attribute checks](../tests/mount-lifecycle/xattr-policy.md) retain
the final attachment in pathname and descriptor targets, including overlay
target copies. Authorization checks its policy before copy-up or backend writes
and preserves existing pins, capabilities, MAC and inode protections. Both
architectures and same-ELF Linux checks cover set/remove, get/list, binary and
empty values, symlink no-follow, detached/retired mounts and inherited fds after
namespace copies with unchanged flags. Divergent inherited-fd remount policy,
overlay/persistent-backend integration and concurrent mount changes remain open.
The [inode-flag checks](../tests/mount-lifecycle/inode-flags-policy.md) extend
the descriptor's saved route to `FS_IOC_SETFLAGS`, including authorized unchanged
values. Native regular-file and directory probes cover separate bind policies,
namespace copies, chroot/cwd, detached and retired mounts, and unprivileged
denial. Existing capability/MAC/securelevel and overlay checks keep their order.
The flag payloads are native-only; filesystem-backed Linux flag comparisons and
error-order parity remain open.
The [symlink creation checks](../tests/mount-lifecycle/symlink-policy.md) extend
destination attachment policy to `symlinkat`. The destination's directory and
mount route are captured together and retained while resolving its parent;
the stored link target remains literal. Native and same-ELF Linux probes cover
both bind-policy directions, copied namespaces, root/cwd aliases, parent
symlinks, detached and retired descriptions, and UID/GID 1000 denial. Internal
kernel callers keep their conservative fallback. Persistent backend integration,
concurrent mount changes and broader link/rename qualification remain open.
The [removal checks](../tests/mount-lifecycle/unlink-policy.md) extend attachment
policy to `unlinkat` and its `AT_REMOVEDIR` form. Both native architectures and
same-ELF Linux probes cover regular files, symlinks and empty directories through
bind aliases, copied namespaces, root/cwd aliases, detached and retired mounts.
Denied operations preserve entries and parent metadata; successful removal
preserves held descriptions and symlink targets. Existing authorization,
backend failure handling, orphan pins and grace-period cleanup are unchanged.
Broader backend integration, error ordering and concurrent mount changes remain
outside this qualification.
The [hard-link checks](../tests/mount-lifecycle/link-policy.md) preserve both
`linkat` routes, resolve followed source symlinks before comparing mounts, and
require a writable destination attachment. Separate bind mounts and inherited
versus newly copied namespace mounts return `EXDEV` even when they share a
backing filesystem. Both native architectures and same-ELF Linux probes cover
regular sources, followed source symlinks, detached/retired routes, link counts,
UID/GID 1000 directory denial and protected-hardlink refusal. Existing MAC,
attribute, budget and backend checks remain. Internal inode-only links,
non-followed symlink backend behavior, `AT_EMPTY_PATH`, wider error ordering,
concurrent changes and persistent/overlay integration remain unqualified.
The [rename checks](../tests/mount-lifecycle/rename-policy.md) carry both routes
through `renameat` and `renameat2`. Read-only admission uses the selected
attachments; distinct writable bind and copied-namespace mounts return `EXDEV`.
Native ARM/x86 and same-ELF Linux probes cover regular files, literal symlinks,
directories, replacement, no-replace, exchange, permissions, retained routes and
held descriptions. Directory moves preserve `..`, and mounted entries remain
busy. Existing backend hooks, map publication, orphan pins and grace cleanup are
unchanged. Internal callers keep conservative read-only inference. Combined-error
ordering, concurrent changes and persistent/overlay integration remain outside
this qualification.
Mount reclamation, busy-reference accounting and full OCI acceptance remain open.
The overlay-depth refusal measurements also exposed an event-record allocation per call.
The separate [security event producer correction](../tests/overlay-rename/security-events.md)
keeps temporary records on the producer's stack before copying them into the
fixed ring. Both producers now pass repeated native allocation checks; report
authorization and bounded ring/label semantics remain covered.
Crash consistency, full OCI/rootless-runtime acceptance and broader server-load
qualification remain open. Full pins and native CI
instructions are recorded in [the guest evidence](../tests/development/README.md).
Boot services, remote CI, deployment, broader projects and SSH remain open.

Do not check off section 17 until an installed Vinix system builds, debugs,
tests and packages a real project, runs a container with the requested isolation,
and hosts a practical hardware-accelerated guest OS under supported authorization.
