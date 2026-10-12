# Development, containers and virtualization status

This page records the implementation and acceptance boundaries for
[roadmap section 17](../roadmap.md#17-development-containers-and-virtualization).
The workstream remains incomplete. The new userland tools do not establish
missing kernel isolation, debugger or hardware virtualization interfaces.

| Requirement | Available implementation | Remaining acceptance / implementation |
| --- | --- | --- |
| Installed-system self-hosting | [V build plans](../tools/development/README.md) pin prepared source/tool/SDK inputs, build in a private copy, enforce deadlines and record output hashes. Native kernel, utility, init and package-CLI recipes are documented. | Complete native desktop/dependency/package recipes, rebuild all four requested layers inside an installed system on both architectures, repeat in fresh workspaces and compare artifact hashes. No full self-hosted rebuild was run here. |
| Toolchains and developer applications | [Project qualification](../tools/development/qualification.md) covers C/C++/V, Node/TypeScript, Rust/Cargo, Go, Java, make/CMake/Ninja, npm, GDB and SQLite. Missing tools and failed workflows remain failing gates. | Run the full suite inside Vinix with exact package versions and retained receipts; qualify IDE workflows and broader package ecosystems. Python/Meson execution is excluded by the repository's no-Python rule, so their acceptance stays open. |
| Debugging and diagnostics | Dumpability and authorized `process_vm_readv/writev` already exist. The GDB profile requires a real source breakpoint, backtrace and continued execution. | Native ptrace attach/register/step/events, ELF core generation and output/limit policy, profiler events, process stack sampling and authorized hang/crash reporting. No new kernel tracing implementation is claimed. |
| OCI and rootless containers | Existing mount/PID/IPC/UTS namespaces, resource-group controls and overlay copy-up provide parts of container support; see [resource groups](resource-groups.md) and [compatibility status](linux-posix-compatibility.md). | User ID mapping, user/network namespace ownership, network isolation, complete delegation and OCI security semantics; mainstream-runtime and rootless adversarial qualification. Existing refusal of unsupported isolation stays intact. |
| Practical hardware VM hosting | QEMU provides practical RAM sizes and multiple virtual CPUs. The [VM manager](../tools/development/virtual-machines.md) selects an accelerator explicitly. The native Intel backend supports page-backed RAM up to 1 GiB, with allocation rollback, shared mapping lifetimes and EPT invalidation. | Native Intel still has one vCPU and a real-mode entry API. Larger-memory VM entry requires physical/nested VT-x qualification. AMD SVM, ARM virtualization, interrupts and device integration remain open. QEMU TCG inside Vinix does not satisfy hardware acceleration acceptance. |
| VM integration and lifecycle | Private per-VM qcow2 disks/firmware variables, QMP lifecycle, offline paired snapshots, explicit user networking/loopback SSH forwarding, read-only 9p shares and a guest-agent transport. | Qualify guest OS workflows inside Vinix, provide Vinix guest tools/drivers, qualify shared folders and network behavior, and implement running-state snapshots and crash-atomic snapshot transactions if required. |
| Server/SSH/CI and automation | SQLite transaction/reopen checks and [per-account interval jobs](../tools/development/scheduled-jobs.md) with pinned executables, selected environment, protected credential files and persisted status. | Installed-system service/boot integration and complete database/server, authenticated SSH development and CI project workflows under ordinary-user policy. |

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

Do not check off section 17 until an installed Vinix system builds, debugs,
tests and packages a real project, runs a container with the requested isolation,
and hosts a practical hardware-accelerated guest OS under supported authorization.
