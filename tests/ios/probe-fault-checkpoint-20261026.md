# Native ARM64 fault checkpoint — 2026-10-26

Runtime, fixtures and evidence tools revision:
`06d317c46fee7a9e3db134acc9c85c5faa55bc8f`.
Advertising work remains skipped.

The explicit `--probe-no-ads` launch now installs a native Linux ARM64
diagnostic handler for SIGSEGV, SIGBUS and SIGILL before the Darwin signal
bridge. It reports the signal, code, address, fault address, PC, SP, PSTATE
and all 31 general registers, then exits with status `128 + signal`.
Reporting uses one bounded stack buffer, constant labels and `write`/`_exit`;
it allocates no heap storage and does not dereference the fault address or PC.
Previous native dispositions are saved and restored. Other launch modes
leave them unchanged. This is not an alternate-stack handler.

Before launch, the guest fixture installs and restores all three dispositions,
checks disabled mode and repeated restoration, and forks a child that writes
to a PROT_NONE mapping. It verifies SIGSEGV code 2, the exact mapping address
in both address fields, nonzero PC/SP, all 31 registers and exit status 139.
The fixture passes. Both guest programs build successfully; their generated
C was inspected for allocations in the signal-reporting path. Host sanitizer
suites were not rerun for this checkpoint.

The existing budget fixtures also pass: a 64 MiB group charges and releases
memory, and a child touching 128 MiB is killed with signal 9 and one
`oom_kill`. The supervisor remains outside the limited groups.

The unchanged Fortnite executable runs with `memory.max=2147483648`, passes
all nine Objective-C `+load` methods and prints initializer-stage markers for
EOSSDK, MarketplaceKitWrapper and the main executable. All four traced
`os_proc_available_memory` calls return 663,520,166 bytes. After
`Using MallocBinned3 allocator.`, the handler captures SIGSEGV code 1 at
address 3 and exits with status 139 (wait status 35584). The application
group's `oom` and `oom_kill` counters are zero. Harness status 0 records
completion of the diagnostic probe.

The recorded main-image mapping translates runtime PC `0x8004426b4e4` to
preferred Mach-O PC `0x10489b4e4` and LR to `0x10489b4ac`. The unchanged
executable contains these instructions at the fault:

```text
0x10489b4dc: mov w8, #3
0x10489b4e0: mov w9, #123
0x10489b4e4: str w9, [x8]
```

The captured x8 and x9 equal 3 and 123. The same routine references backup-pool
and memory-statistics diagnostics and the message
`Ran out of memory allocating %llu bytes with alignment %u. Last error msg: %ls.`
This identifies a deliberate crash in an allocation-failure routine. It does
not establish the failed request's size, alignment or cause. Positive reported
headroom and zero cgroup OOM events do not prove that an allocation can succeed.
Initializer completion, application entry, rendering, login and gameplay remain
unverified. `--probe-no-ads` still binds SKAdNetwork to nil and changes
application behavior. Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/fault-context-20261026`.
The manifest seals 1,324 files; its SHA-256 is
`032d04b9352242ce55b90eec0afabc4899b9beee98b4b5d6fe4640257f50544d`.
The source snapshot contains 1,152 files and the selected input inventory
records 692 hashes, including the disassembler.

Evidence `seal`, `check` and `selftest` pass. The self-test rejects missing
guest boot media, an altered serial log and an unmanifested file, restores
the bundle and verifies every checksum again. Historical checkers are unchanged.

The bundle preserves source snapshots, helpers, runners, generated C, TLS
archives and objects, command/status logs, the unchanged application and
frameworks, fault analysis and bounded disassembly, and both diagnostic
guests' boot images, initramfs archives, firmware variables, Limine
configurations and serial logs. `probe-no-ads-state.txt` selects the successful
`probe-no-ads-492916` run. The preliminary `probe-no-ads-689833` run hung in a
fixture with the wrong native pipe-element width and was terminated; its
media and serial log are retained. The corrected fixture uses 32-bit pipe
descriptors and passes in the selected run. The prebuilt kernel is inventoried;
concurrent kernel edits were not rebuilt. Selected input hashes do not seal
compiler, header or host-library closures. Previous complete evidence remains
in the [memory-budget checkpoint](probe-memory-checkpoint-20261026.md).

To reproduce, use the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, set `V_RESOURCE_PATH` there
and `V_MACOS_V3_NO_FALLBACK=1`, and compile helpers with
`-nocache -gc none -cc clang`. Build `notification-checks.v`,
`notification-vm.v`, `image-initializers-input-inventory.v`,
`inspect-probe-fault.v` and `probe-fault-evidence.v` into a new external bundle.
The inspector needs the repository's `compat/ios` module path. Use
notification-checks modes `build-init` and `build-run-ios-gles`, then
`probe-no-ads` with `VINIX_IOS_PROBE_MEMORY_MAX=2147483648` and
`VINIX_IOS_VM_GZIP_LEVEL=9`. The VM driver supplies `compat/ios` and
`tests/ios` module paths to native-init. Run inspect-probe-fault with the
preserved application executable, selected guest serial log and bundle
directory; it requires `/opt/homebrew/opt/llvm/bin/llvm-objdump`. Run
image-initializers-input-inventory with repository root, bundle directory and
tested revision. Run probe-fault-evidence modes `seal DIR`, `check DIR`,
`selftest DIR` and `hash FILE`.
