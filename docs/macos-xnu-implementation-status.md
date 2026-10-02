# XNU comparison implementation status

This tracks work against the 49 findings in [the source comparison](macos-xnu-kernel-gap-analysis.md). The comparison remains a dated baseline; this file records changed behavior and remaining work. A partial implementation is not XNU parity.

The environment permits four active agents including the coordinator, so the requested ten specialists run in successive groups of three. Kernel changes are developed in isolated worktrees under `third_party/xnu-implementation`, reviewed, committed, and integrated on `codex/xnu-integration`. Uncommitted work from concurrent sessions is not imported.

## Findings

| ID | Feature | State | Owner | Evidence and remaining work |
| --- | --- | --- | --- | --- |
| SEC1 | Enforcement of noexec/nodev mounts | Implemented; namespace edge case remains | Reviewed mount-policy work | `ee0cd7c8`: noexec/nodev enforcement through exec, interpreters, mappings and retained mount identities. Both guest suites pass, including flat repeated-denial slab measurements. `4074f7ba` also fixes repeated-procfs-mount redirect cycles on both architectures. Nested bind child-mount `..` context remains unresolved. |
| SEC2 | Trusted authorization for W^X/JIT exceptions | Implemented; compatibility scope documented | Coordinator and reviewed mount-policy work | `d24b3ea5`, `48d59b0e`: explicit W^X requests require an effective-root CAP_SYS_ADMIN launcher in the initial user namespace or an administrator-authorized executable mount. ARM64/x86 guest tests pass, including new-user-namespace denial. |
| SEC3 | Executable signatures and fault-time page integrity | Queued | Integrity specialist (queued) | No completed implementation claimed. |
| SEC4 | Mandatory policy hooks and object labels | Queued | Integrity specialist (queued) | No completed implementation claimed. |
| SEC5 | Type-aware heap segregation | Queued | Integrity specialist (queued) | No completed implementation claimed. |
| SEC6 | Protected heap storage for credentials/security state | Queued | Integrity specialist (queued) | No completed implementation claimed. |
| SEC7 | Kernel ARM64 pointer authentication | Queued | CPU specialist (queued) | No completed implementation claimed. |
| SEC8 | Structured security auditing | Partial implementation | Security worker 3 and coordinator | `30ba87a0`, `3649452e`: bounded seccomp records, coherent identity and privileged snapshots. ARM64/x86 ABI, authorization, wrap/drop and allocation tests pass. General events, login/session identity, persistent collection and Linux audit ABI remain. |
| SEC9 | Boot-established system integrity policy | Queued | Integrity specialist (queued) | No completed implementation claimed. |
| SC1 | Process CPU interval timers | Implemented and guest-tested | Reviewed CPU work and Scheduler worker 6 | `95c69c9e`: process-wide virtual/profiling interval timers account CPU across threads and pure loops. Both architecture guest suites pass. `8abeeb4a` fixes x86 coarse-clock user-time starvation using a hardware counter. |
| SC2 | RLIMIT_CPU enforcement | Implemented and guest-tested | Reviewed CPU work and Scheduler worker 6 | `95c69c9e`: inherited CPU limits, repeated SIGXCPU and process-wide hard-limit SIGKILL. Both architecture no-syscall, multithread and inherited-limit guests pass with the CPU-clock correction. |
| SC3 | System V message queues | In progress | IPC worker 7 | Bounded queues, ownership, namespace isolation, blocking/wakeup and message selection pass the first ARM64 guest suite; capability ownership corrections and both-architecture final validation precede integration. |
| SC4 | Pollable stable process handles | Queued | IPC specialist (queued) | No completed implementation claimed. |
| SC5 | Efficient spawn and correct vfork/CLONE_VM semantics | Queued | IPC specialist (queued) | No completed implementation claimed. |
| SC6 | Request-context propagation and delegated charging | Queued | IPC specialist (queued) | No completed implementation claimed. |
| SC7 | Kernel-coordinated userspace workqueues/workloops | Queued | IPC specialist (queued) | No completed implementation claimed. |
| VM1 | Anonymous-memory compression | Queued | VM worker 2 | No completed implementation claimed. |
| VM2 | Disk-backed anonymous paging | Queued | VM worker 2 | No completed implementation claimed. |
| VM3 | Proactive VM-wide reclaim | Partial implementation | VM worker 2 | `2f7e0cd5`: bounded background clean-cache reclaim with a reserve target. Both builds and pressure/recovery guests pass. Anonymous and mapped-page eviction, swap/compression and global OOM remain. |
| VM4 | System pressure levels and notifications | Partial implementation | VM worker 2 | `2f7e0cd5`, `77ae6496`: hysteretic global pressure levels, independent pollable subscriptions and reclaim/failure counters. ARM64/x86 guests cover transitions, recovery, epoll, dup, capacity and reuse. Per-cgroup pressure and PSI remain. |
| VM5 | Global OOM recovery | Queued | VM worker 2 | No completed implementation claimed. |
| VM6 | Explicit huge-page mappings | Queued | CPU specialist (queued) | No completed implementation claimed. |
| VM7 | CPU process address-space-tagged TLB contexts | Queued | CPU specialist (queued) | No completed implementation claimed. |
| PERF1 | CPU-local allocator fast paths | Queued | Scheduler specialist (queued) | No completed implementation claimed. |
| PERF2 | Run-queue scalability | Queued | Scheduler specialist (queued) | No completed implementation claimed. |
| PERF3 | Coordinated workload QoS | Queued | Scheduler specialist (queued) | No completed implementation claimed. |
| PERF4 | Heterogeneous core placement | Queued | Scheduler specialist (queued) | No completed implementation claimed. |
| PERF5 | Blocking-lock priority inheritance | Queued | Scheduler specialist (queued) | No completed implementation claimed. |
| PERF6 | Priority-driven busy-CPU preemption on ordinary enqueue | Implemented for APIC/GIC; platform gaps remain | Scheduler worker 6 | `261bee1c`: bounded CPU rank snapshots and coalesced scheduling interrupts preempt lower-ranked work. ARM64/x86 guests and policy tests pass; x86 median wake latency fell from 4.026 ms to 0.153 ms. Apple AIC targeted interrupts and CPU IDs outside the static supported range retain timer fallback. |
| PERF7 | Deadline-driven idle and coalesced timers | Queued | Scheduler specialist (queued) | No completed implementation claimed. |
| FS1 | Physical persistence through device-cache flushes | Implemented; validation partial | Reviewed storage commit | `ca4676af`: partition sync forwarding; AHCI, NVMe, VirtIO flush/error paths; DMA timeout containment. Host fault tests and both builds pass; ARM64 reboot persistence passes. Power-cut and physical-controller validation remain. |
| FS2 | Dirty tracking and reclaim of mapped file pages | Queued | Filesystem specialist (queued) | No completed implementation claimed. |
| FS3 | Filesystem clones and snapshots | Queued | Filesystem specialist (queued) | No completed implementation claimed. |
| FS4 | Persistent extended attributes | In progress | Filesystem worker 5 | Validated external ext2 attribute blocks, persistent backend dispatch and shared-block COW are being tested. Reboot, error ownership and allocation verification precede integration. |
| FS5 | Filesystem ACL evaluation and inheritance | Queued | Filesystem specialist (queued) | No completed implementation claimed. |
| NET1 | IPv6 and its socket/control path | Partial implementation | Network worker 4 | `fbf31f34`: production lwIP IPv6, ND/SLAAC, dual-stack TCP/UDP, scoped addresses and IPv6 address dumps. Host sanitizers and ARM64/x86 guest ABI tests pass; all live heap classes and slab pages stay exactly flat across 500 exchanges/options/dumps. Route/neighbor mutation, ancillary/error queues, multicast controls and external-driver validation remain. |
| NET2 | Mutable interface and routing configuration | Issue fixed; feature incomplete | Network worker 4 and reviewed transport work | `a3eafc59` returns EOPNOTSUPP for unsupported mutations instead of false success; transport option/linger/budget guests and host sanitizers pass. Actual route/link/address mutation, multiple interfaces and network namespaces remain. |
| NET3 | Stateful packet filtering and NAT control | Queued | Network follow-up | No packet filter, connection tracking or NAT implementation has completed. |
| NET4 | Kernel VPN/tunnel interfaces and IPsec | Queued | Network follow-up | No TUN/TAP, VPN or IPsec implementation has completed. |
| NET5 | Parallel receive/flow processing and queue policy | Queued | Network follow-up | The stack remains serialized by one network lock; no multiqueue/parallel-flow implementation has completed. |
| NET6 | Per-flow network policy and multipath transport | Queued | Network follow-up | Per-flow policy and multipath require usable multiple interfaces/routes and protocol ownership; no implementation has completed. |
| HW1 | Coordinated system sleep and device runtime power | Queued | Power/lifecycle worker 8 | ACPI synchronization and power/lifecycle implementation are under inspection; no completed implementation claimed. |
| HW2 | Hibernation image lifecycle | Queued | Power/lifecycle worker 8 | No completed implementation claimed. |
| HW3 | Common dynamic driver/service lifecycle | Queued | Power/lifecycle worker 8 | No completed implementation claimed. |
| OBS1 | Userspace debugger attach/control | Partial implementation | Inspection worker 1 | `c97fd08c`: authorized process_vm_readv/writev and retained map lifetime; both architecture clean builds/guests pass, including exec/exit and unmap races. Cross-process copies require resident pages; writes cannot resolve COW. Ptrace control/registers/single stepping remain. |
| OBS2 | User core dumps and dumpability | Partial implementation | Inspection worker 1 | `c97fd08c`: real dumpability, effective-credential resets, fork/exec transitions and proc authorization; both guest suites pass. ELF core-file generation remains. |
| OBS3 | Accurate process/resource accounting | Partial implementation | Reviewed CPU work | `95c69c9e`: user/system CPU counters feed getrusage, times and proc text, including reaped-child CPU. Both architecture accounting guests pass with `8abeeb4a`. Fault/RSS/context-switch/I/O counters remain. |
| OBS4 | Buffered/filterable causal tracing | Queued | Profiling follow-up | No completed implementation claimed. |
| OBS5 | CPU counter and sampled-stack profiling | Queued | Profiling follow-up | No completed implementation claimed. |

## Validation

- `tests/kernel-gaps/run.py`: real static Linux/musl PID 1 programs on ARM64 and x86-64, with mandatory verdicts, failure detection, serial logs and isolated state. Host runner rejection tests and both-architecture guest smoke pass (`71574e19`).
- `tests/block-storage/run.py`: three host fault-model suites pass. These exercise native driver functions; they do not establish real-device power-loss durability.
- `tests/reboot-persistence/run.sh`: ARM64 VirtIO write/sync/reboot/read-back passes.
- `tests/security-audit/test.c`: ARM64 and x86-64 security auditing tests pass. Measured retained slab delta is 96 bytes after 10,000 producers and 96 bytes after 1,000 collectors, traced to an existing metric-reader Text wrapper leak rather than the audit ring; the previous seccomp evaluator retained 64 bytes per filtered syscall.

- `fbf31f34` fixes the measured metric-reader, ChaCha scratch, netlink reply-transfer and socket-query leaks. Exact flatness is established for the IPv6 test paths; earlier audit/xattr measurements need repetition with these fixes before claiming their observer overhead is gone.

- `tests/kernel-allocs/run.sh` with the explicitly pinned V/VEXE currently fails: the available compiler reports many pre-existing allocation kinds beyond the checked-in allowances and exits nonzero for its x86 scratch-tree scan. The allowance file was not broadly refreshed. This is an unresolved validation failure, not a pass.
- VM worker measurements ran `ops,churn,cache` against the small base initramfs at 2 GiB. Existing unrelated retained allocations remain; without a matched baseline these runs establish observability, not a leak-free kernel.

- `tests/kernel-cpu/check.c`: ARM64/x86 process timers, summed limits, pure-user-loop delivery, SIMD restoration, child accounting and user/system separation pass.
- `tests/mount-policy/test.c`: ARM64/x86 mount, mapping, W^X authorization and repeated-procfs namespace regressions pass.
- `tests/process-inspection/test.c`: ARM64/x86 dumpability, credentials, authorized vector copies, partial/error paths, exec/exit/unmap races and cgroup allocation restrictions pass.

## Completion rules

A row becomes implemented only after its real behavior, error paths, lifetimes and relevant ABI tests pass. Cross-architecture builds, allocation measurements, and guest tests are recorded separately from host models. Hardware-specific features require a supported platform and restoration/persistence testing. Darwin-specific architectures, signing keys, authenticated-root formats and hibernation boot contracts need explicit native designs; placeholder APIs cannot resolve those findings.
