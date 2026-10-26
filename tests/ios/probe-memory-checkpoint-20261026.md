# Enforced memory-budget checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`42c99514e69ae170691b853b291dcd88ff0964dd`.
Advertising work remains skipped.

The notification VM harness now accepts `VINIX_IOS_PROBE_MEMORY_MAX` for
`probe-no-ads`. The value must be positive decimal bytes, aligned to 4,096 and
within signed 64-bit range. The supervisor mounts a private cgroup2 hierarchy,
verifies enforcement, then starts the application in a separate finite group
before exec. It stays outside both groups and records final memory events.
Unset configuration explicitly clears any budget inherited from the base
initramfs; the default launch remains unmanaged.

Before the application launch, the ARM64 guest verifies a 64 MiB limit:
touching 8 MiB raises `memory.current` from 5,469,796 to 13,915,876 bytes,
and unmapping restores 5,469,796 bytes. A second child touching 128 MiB is
killed with signal 9 and records one `oom_kill`. Both groups become empty,
the supervisor's membership stays unchanged, and enforcement checks pass.

The unchanged Fortnite executable then runs with `memory.max=2147483648`.
It passes all nine Objective-C `+load` methods and prints initializer-stage
markers for EOSSDK, MarketplaceKitWrapper and the main executable. All four
traced `os_proc_available_memory` calls return 663,462,822 bytes. It prints
`Using MallocBinned3 allocator.`, then exits with signal 11, wait status 35584
and process status 139. The application group's `oom` and `oom_kill` counters
are both zero. Harness status 0 records completion of the diagnostic probe.

The crash persists with positive headroom in all observed memory API calls.
This run does not identify the faulting instruction or establish the crash's cause.
Initializer completion, application entry, rendering, login and gameplay
remain unverified. The memory API reports remaining enforced group headroom;
no positive value is fabricated from physical/free RAM or address-space limits.
`--probe-no-ads` still binds SKAdNetwork to nil and changes application behavior.
Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

The budget parser tests pass for valid limits and malformed, zero, unaligned,
unlimited and overflowing values. The VM driver rejects a budget in another
mode and rejects `max`. The memory API's bounded hierarchy parser and errno
fixture pass ASan+UBSan normally and with `SWIFT_DETERMINISTIC_HASHING=1`.
They cover calls before runtime initialization and with tracing off/on;
tracing uses a bounded stack buffer. Leak detection is disabled. This host
run leaves the optional Mach-O fixture unset; the earlier concurrent image
load/unload checks are not rerun here. Both guest programs build successfully.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/mmap-allocator-20261026`.
The manifest seals 1,476 files; its SHA-256 is
`d695d52ace6dae31952e1314f51edb36a5a5eed999b122a7bfbae76703929993`.
The source snapshot contains 1,148 files and the selected input inventory
records 691 hashes.

Evidence `seal`, `check` and `selftest` pass. The self-test rejects missing
guest boot media, an altered host fixture log and an unmanifested file, then
restores the bundle and verifies every checksum again.

The bundle preserves source snapshots, compiled helpers and runners, generated
C, host fixture objects and binary, TLS archives and objects, command/status
logs, the unchanged application and frameworks, and all three diagnostic
guests' boot images, initramfs archives, firmware variables, Limine
configurations and serial logs. `probe-no-ads-state.txt` selects the final run.
The prebuilt kernel is inventoried; concurrent kernel edits were not rebuilt.
Selected input hashes do not seal compiler, header or host-library closures.
The preceding complete sealed evidence remains in the
[Foundation HTTP checkpoint](foundation-http-checkpoint-20261026.md).

To reproduce, use the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, set `V_RESOURCE_PATH` there
and `V_MACOS_V3_NO_FALLBACK=1`, and compile helpers with
`-nocache -gc none -cc clang`. Build `notification-checks.v`,
`notification-vm.v`, `image-initializers-input-inventory.v` and
`probe-memory-evidence.v` into a new external bundle. Compile and run
`probebudget/budget_test.v`; run notification-checks mode `proc-memory-host`
into its own subdirectory. Use notification-checks modes `build-init` and
`build-run-ios-gles`, then `probe-no-ads` with
`VINIX_IOS_PROBE_MEMORY_MAX=2147483648` and `VINIX_IOS_VM_GZIP_LEVEL=9`.
Run image-initializers-input-inventory with repository root, bundle directory
and tested revision. Run probe-memory-evidence modes `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE`. Historical evidence checkers are unchanged.
