# Development, containers and virtualization status

This page records the implementation and acceptance boundaries for
[roadmap section 17](../roadmap.md#17-development-containers-and-virtualization).
The workstream remains incomplete. The new userland tools do not establish
missing kernel isolation, debugger or hardware virtualization interfaces.

| Requirement | Available implementation | Remaining acceptance / implementation |
| --- | --- | --- |
| Installed-system self-hosting | [V build plans](../tools/development/README.md) pin prepared source/tool/SDK inputs, build in a private copy, enforce deadlines and record output hashes. Native kernel, utility, init and package-CLI recipes are documented. [Guest runner checks](../tests/development/README.md) qualify UID 1000 source/link copying, epoch/environment control, matching artifacts and changed-input refusal on both architectures. AArch64 rebuilds the V C-backend compiler in two fresh workspaces, then uses each rebuilt compiler for the four `util-vinix` utilities, `init` and the package CLI from immutable committed sources. It executes the tools, packs the compiled `lscpu` and signs a consumer release. Generated-C/compiler/executable/payload/manifest/index/signature hashes match; the controller independently verifies the signature and payload metadata with full SDK/V/runtime pins. | Complete native kernel/desktop/dependency recipes, init boot/login qualification and the remaining userland/package workflows; rebuild all four requested layers inside an installed system on both architectures. Basic runner checks use a prebuilt V payload; AArch64 compiler/utility/init/package checks use native compilation. No full self-hosted rebuild was run here. |
| Toolchains and developer applications | [Project qualification](../tools/development/qualification.md) covers C/C++/V, Node/TypeScript, Rust/Cargo, Go, Java, make/CMake/Ninja, npm, GDB and SQLite. A [V compiler stager](../tools/development/stage-v.v) exports committed compiler/library sources, records portable-source adaptations and prepares matching static ELF installations for both architectures. [Native guest checks](../tests/development/README.md) passed C/C++ thread/file projects and the V file project as UID/GID 1000 on AArch64 with GCC/G++ 11.2.1 and V 0.5.2 `f6358ec`. AArch64 also rebuilt the V C-backend compiler twice and used both matching compilers to build reproducible projects and signed packages. Both architectures passed prepared V version/help and bounded diagnostic-log gates; AArch64 verified actual assertion failures with relative source paths. Missing tools and failed workflows remain failing gates. | Qualify the remaining V backends, reference profiles and native x86 compiler projects with exact package versions and retained receipts; qualify IDE workflows and broader package ecosystems. Python/Meson execution is excluded by the repository's no-Python rule, so their acceptance stays open. |
| Debugging and diagnostics | Dumpability and authorized `process_vm_readv/writev` already exist. The GDB profile requires a real source breakpoint, backtrace and continued execution. | Native ptrace attach/register/step/events, ELF core generation and output/limit policy, profiler events, process stack sampling and authorized hang/crash reporting. No new kernel tracing implementation is claimed. |
| OCI and rootless containers | Existing mount/PID/IPC/UTS namespaces, resource-group controls and overlay copy-up provide parts of container support; see [resource groups](resource-groups.md) and [compatibility status](linux-posix-compatibility.md). | User ID mapping, user/network namespace ownership, network isolation, complete delegation and OCI security semantics; mainstream-runtime and rootless adversarial qualification. Existing refusal of unsupported isolation stays intact. |
| Practical hardware VM hosting | QEMU provides practical RAM sizes and multiple virtual CPUs. The [VM manager](../tools/development/virtual-machines.md) selects an accelerator explicitly. The native Intel backend supports page-backed RAM up to 1 GiB, with allocation rollback, shared mapping lifetimes and EPT invalidation. | Native Intel still has one vCPU and a real-mode entry API. Larger-memory VM entry requires physical/nested VT-x qualification. AMD SVM, ARM virtualization, interrupts and device integration remain open. QEMU TCG inside Vinix does not satisfy hardware acceleration acceptance. |
| VM integration and lifecycle | Private per-VM qcow2 disks/firmware variables, QMP lifecycle, offline paired snapshots, explicit user networking/loopback SSH forwarding, read-only 9p shares and a guest-agent transport. | Qualify guest OS workflows inside Vinix, provide Vinix guest tools/drivers, qualify shared folders and network behavior, and implement running-state snapshots and crash-atomic snapshot transactions if required. |
| Server/SSH/CI and automation | SQLite transaction/reopen checks and [per-account interval jobs](../tools/development/scheduled-jobs.md) with pinned executables, selected environment, protected credential files and persisted status. [Native x86_64/AArch64 job checks](../tests/development/README.md) qualify UID/GID 1000 execution, private receipts, credential/output isolation, unsafe-file refusal, deadlines, INT/TERM group retirement, watcher ticks with one PID, concurrent-owner refusal and killed-owner retry/acknowledgement. | Installed-system service/boot integration and complete database/server, authenticated SSH development and CI project workflows under ordinary-user policy. |

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

Do not check off section 17 until an installed Vinix system builds, debugs,
tests and packages a real project, runs a container with the requested isolation,
and hosts a practical hardware-accelerated guest OS under supported authorization.
