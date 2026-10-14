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
loop. Concurrent unshare/setns remains unsynchronized; inode-based creation
and copied-root writable-open checks outside this pivot path remain open.
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
