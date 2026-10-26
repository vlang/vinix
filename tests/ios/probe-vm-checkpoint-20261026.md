# Anonymous VM reservation checkpoint — 2026-10-26

Trace revision: `34236511e9311eeceeadcf85a9ce19fadca2098b`.
Fix, fixtures and evidence tools revision:
`5fe30ebc225bc3e4006e018fba399884500eb09f`.
Advertising work remains skipped.

The explicit `--probe-no-ads` VM trace identifies a failed anonymous mapping
immediately after `Using MallocBinned3 allocator.`. The request is 24 GiB
(`0x600000000`), protection `0x3`, flags `0x1042` and descriptor `0xf1000000`.
Darwin uses that descriptor's high byte as VM accounting tag `0xf1`; forwarding
it as a Linux descriptor returns `MAP_FAILED` with `EBADF` (9) in the preserved
guest. The application then deliberately writes 123 to address 3 at preferred
PC `0x10489b4e4`, matching the [previous fault checkpoint](probe-fault-checkpoint-20261026.md).
This trace establishes the rejected request; it does not expose every internal
allocator decision.

The Linux bridge now passes descriptor -1 and offset zero for anonymous
requests with descriptor -1 or a high-byte accounting tag. Nonzero low bits
request additional Darwin VM semantics and remain explicitly unsupported
with errno 45. File-backed descriptors and offsets retain their existing
behavior, as does the ownership guard for fixed mappings. The macOS mapping
path is unchanged.

The same application request now returns `0x8009750c000`. Its logged errno 22
is stale after a successful call, not a failure result. The 24 GiB range is a
virtual reservation; the probe does not touch or commit all of it. Startup
continues through further mappings and stops at the runner's
`V panic: iOS: unsupported block capture disposal`, exiting with status 1
(wait status 256). The panic and another thread's VM trace interleave in the
serial output, so the log is not a complete, ordered record of concurrent calls.

Host ASan/UBSan checks pass with normal and deterministic Swift hashing.
The same fixture passes in the ARM64 Vinix guest. It checks anonymous tag
variants, ignored offsets, rejection of unsupported low bits, file-backed
descriptor/offset behavior and the fixed-mapping ownership guard. The Linux
fixture also reserves and unmaps the exact untouched 24 GiB tagged range.
Existing VM tracing, Mach result, errno, reserve/commit/release and failed
diagnostic-write checks pass.

Budget and native signal fixtures pass before launch: the 64 MiB group charges
and releases memory; a child touching 128 MiB is killed with signal 9 and one
`oom_kill`; a protection fault reports SIGSEGV code 2 and all 31 registers,
and handler restoration passes. The supervisor remains outside the limited
groups. The application runs with `memory.max=2147483648`, completes all nine
Objective-C `+load` methods and prints initializer-stage markers for EOSSDK,
MarketplaceKitWrapper and the main executable. Seven headroom queries return
663,528,358 or 662,995,494 bytes. Its final `oom` and `oom_kill` counters are
zero. Harness status 0 records completion of this diagnostic probe, whose
application exit status is 1.

Initializer completion, application entry, rendering, login and gameplay remain
unverified. The unsupported block capture disposal is the next observed
boundary. `--probe-no-ads` binds SKAdNetwork to nil and changes application
behavior. Both bundles preserve the unchanged executable with SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundles:

| Run | External directory | Source files | Selected inputs | Manifest records |
| --- | --- | ---: | ---: | ---: |
| Rejected reservation | `/Users/alex/Library/Caches/vinix-ios/vm-trace-20261026` | 1,155 | 692 | 1,460 |
| Normalized tags | `/Users/alex/Library/Caches/vinix-ios/vm-tags-20261026` | 1,156 | 692 | 1,462 |

SHA-256 of each `manifest.sha256`, respectively:

```text
9cf12868981d57a142e8b420aa965d1de37e9c69b1431568c442efce482a4de2
37bb2afc7bbc6ce6d6aa66f5e0be12d283f95ce4e56181d6e0533e9559bd4285
```

The bundles retain source snapshots, selected input inventories, helpers,
runners, generated C, host sanitizer objects and TLS archives, command/status
logs, the application and frameworks, and guest boot images, initramfs archives,
firmware variables, Limine configurations and serial logs. Their
`probe-no-ads-state.txt` files select `probe-no-ads-223750` and
`probe-no-ads-567750`, respectively. The prebuilt ARM64 kernel is inventoried;
concurrent kernel edits were not rebuilt. Selected input hashes do not seal
the complete compiler, header or host-library closures.

The baseline uses `probe-vm-evidence.v`; the fixed run uses
`probe-vm-tags-evidence.v`. Each checker requires its complete bundle.
Historical checkers are unchanged. Their `seal`, `check` and `selftest` modes
pass, rejecting missing guest media, altered logs, unmanifested files and
changed VM diagnostics. The fixed-run self-test specifically rejects altered
size/tag, failed or null reservation results and a missing trace, then restores
the bundle and verifies all checksums again.

To reproduce, use the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, set `V_RESOURCE_PATH` there
and `V_MACOS_V3_NO_FALLBACK=1`, and compile helpers with
`-nocache -prod -gc none -cc clang`. Build `notification-checks.v`,
`notification-vm.v`, `image-initializers-input-inventory.v` and the appropriate
evidence checker into a new external bundle; notification-checks and
notification-vm need the `tests/ios` module path. Preserve the application and
selected build inputs described by the inventory. Use notification-checks mode `vm-probe-host`,
then modes `build-init`, `build-vm-probe` and `build-run-ios-gles`, followed
by `probe-no-ads` with `VINIX_IOS_PROBE_MEMORY_MAX=2147483648` and
`VINIX_IOS_VM_GZIP_LEVEL=9`. The baseline predates the guest VM fixture, so
omit `build-vm-probe` there. The VM driver supplies `compat/ios` and
`tests/ios` module paths. Run image-initializers-input-inventory with repository
root, bundle directory and tested revision. Run the evidence checker's
`seal DIR`, `check DIR`, `selftest DIR` and `hash FILE` modes.
