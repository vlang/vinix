# Development, containers and virtualization status

This page records the implementation and acceptance boundaries for
[roadmap section 17](../roadmap.md#17-development-containers-and-virtualization).
The workstream remains incomplete. The new userland tools do not establish
missing kernel isolation, debugger or hardware virtualization interfaces.

| Requirement | Available implementation | Remaining acceptance / implementation |
| --- | --- | --- |
| Installed-system self-hosting | [V build plans](../tools/development/README.md) pin prepared source/tool/SDK inputs, build in a private copy, enforce deadlines and record output hashes. Native kernel, utility, init and package-CLI recipes are documented. [Guest runner checks](../tests/development/README.md) qualify UID 1000 source/link copying, epoch/environment control, matching artifacts and changed-input refusal on both architectures. AArch64 also compiles and executes all four `util-vinix` utilities and `init` in two fresh workspaces with matching binary hashes and full SDK/V/runtime pins, including `lscpu` procfs CPU inspection. | Complete native desktop/dependency/package recipes, init boot/login qualification and the remaining userland workflows; rebuild all four requested layers inside an installed system on both architectures, repeat in fresh workspaces and compare artifact hashes. Basic runner checks use a prebuilt V payload; the utility/init checks use native compilation and version entry points. No full self-hosted rebuild was run here. |
| Toolchains and developer applications | [Project qualification](../tools/development/qualification.md) covers C/C++/V, Node/TypeScript, Rust/Cargo, Go, Java, make/CMake/Ninja, npm, GDB and SQLite. [Native guest checks](../tests/development/README.md) passed the C/C++ thread/file projects and the V file project as UID/GID 1000 on AArch64 with GCC/G++ 11.2.1 and V 0.5.2, retaining SDK/V/compiler hashes and compile/run receipts. Missing tools and failed workflows remain failing gates. | Qualify the remaining profiles and native x86 compiler projects with exact package versions and retained receipts; qualify IDE workflows and broader package ecosystems. Python/Meson execution is excluded by the repository's no-Python rule, so their acceptance stays open. |
| Debugging and diagnostics | Dumpability and authorized `process_vm_readv/writev` already exist. The GDB profile requires a real source breakpoint, backtrace and continued execution. | Native ptrace attach/register/step/events, ELF core generation and output/limit policy, profiler events, process stack sampling and authorized hang/crash reporting. No new kernel tracing implementation is claimed. |
| OCI and rootless containers | Existing mount/PID/IPC/UTS namespaces, resource-group controls and overlay copy-up provide parts of container support; see [resource groups](resource-groups.md) and [compatibility status](linux-posix-compatibility.md). | User ID mapping, user/network namespace ownership, network isolation, complete delegation and OCI security semantics; mainstream-runtime and rootless adversarial qualification. Existing refusal of unsupported isolation stays intact. |
| Practical hardware VM hosting | QEMU provides practical RAM sizes and multiple virtual CPUs. The [VM manager](../tools/development/virtual-machines.md) selects an accelerator explicitly. The native Intel backend supports page-backed RAM up to 1 GiB, with allocation rollback, shared mapping lifetimes and EPT invalidation. | Native Intel still has one vCPU and a real-mode entry API. Larger-memory VM entry requires physical/nested VT-x qualification. AMD SVM, ARM virtualization, interrupts and device integration remain open. QEMU TCG inside Vinix does not satisfy hardware acceleration acceptance. |
| VM integration and lifecycle | Private per-VM qcow2 disks/firmware variables, QMP lifecycle, offline paired snapshots, explicit user networking/loopback SSH forwarding, read-only 9p shares and a guest-agent transport. | Qualify guest OS workflows inside Vinix, provide Vinix guest tools/drivers, qualify shared folders and network behavior, and implement running-state snapshots and crash-atomic snapshot transactions if required. |
| Server/SSH/CI and automation | SQLite transaction/reopen checks and [per-account interval jobs](../tools/development/scheduled-jobs.md) with pinned executables, selected environment, protected credential files and persisted status. [Native x86_64/AArch64 job checks](../tests/development/README.md) qualify UID/GID 1000 execution, private receipts, credential/output isolation and unsafe-file refusal. | Native watcher/deadline/interruption qualification, installed-system service/boot integration and complete database/server, authenticated SSH development and CI project workflows under ordinary-user policy. |

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

Do not check off section 17 until an installed Vinix system builds, debugs,
tests and packages a real project, runs a container with the requested isolation,
and hosts a practical hardware-accelerated guest OS under supported authorization.
