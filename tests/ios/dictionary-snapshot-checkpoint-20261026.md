# Dictionary snapshot checkpoint — 2026-10-26

Tested fix and evidence tools revision:
`b05cd0c0e49e49de5db0434e0dc3e58e9767e77c`. Advertising work remains skipped.

`NSDictionary`, `NSMutableDictionary` and registered constant dictionaries now
implement `allKeys` and `allValues`. Each returned array retains its elements
independently of its dictionary. The shared native Apple Foundation/runtime
fixture passes under ASan/UBSan with normal and deterministic Swift hashing.
It covers empty/populated dictionaries, unordered keys, duplicate value
identities, selector scope and retained snapshots surviving dictionary mutation,
owner release and an autorelease-pool drain. Twenty runtime iterations finish
with no live runtime objects. Existing constant-dictionary validation passes.

The ARM64 Vinix snapshot, Blocks capture, VM/tag, signal-context and memory-budget
fixtures pass before the application launch. All five guest build targets pass.
The unchanged Fortnite 42.30.1 executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The explicit `--probe-no-ads` diagnostic binds SKAdNetwork to nil and changes
application behavior. All three images bind and register, all nine Objective-C
`+load` methods finish, and three initializer-stage markers appear. The exact
24 GiB tagged virtual reservation succeeds at `0x800a23a4000`; errno 22 is stale
after success. This does not commit 24 GiB of physical memory.

The former `NSMutableDictionary allKeys` panic is gone. Startup now stops with
SIGSEGV at runtime PC `0x8004106a900`, preferred image PC `0x1006b2900` and
preferred LR `0x1006b2e5c`. The independent fault inspector verifies these bytes
from the executable immediately around the fault:

```text
68d03bd5  mrs x8, TPIDRRO_EL0
08f17d92  and x8, x8, #0xfffffffffffffff8
080140f9  ldr x8, [x8]
```

The fault address and x8 are zero. This sequence points to a direct Darwin
thread-data access needing ABI support beyond an imported function adapter.
The application exits 139 (wait status 35584), while the completed diagnostic
harness exits 0. The final application cgroup has zero `oom` and `oom_kill`
events with `memory.max=2147483648`. Seven headroom queries return 663,479,206
or 662,946,342 bytes. Both recorded faults include all 31 ARM64 registers;
the first belongs to the deliberate protection-fault fixture.

Progress remains **2 of 8 observable gates (25% of this checklist)**: image
loading/binding and all `+load` calls pass. Initializer completion, application
entry, a rendered frame, an interactive menu, login and a playable match remain
unverified. This fraction does not estimate remaining engineering effort or time.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/dictionary-snapshots-20261026`.
It contains 1,160 source records, 692 selected input records and 1,485 manifest
records, including application/frameworks, generated C, host sanitizer objects
and TLS archives, runners/tools, command/status logs, fault analysis/disassembly
and complete guest media. `probe-no-ads-state.txt` selects
`probe-no-ads-3425000`. SHA-256 of `manifest.sha256`:

```text
bdd91cefc770baac51e3d5445143b61ad722a0ac8c82dce76408f36e3af5544d
```

`dictionary-snapshot-evidence.v` seal, independent check and selftest pass.
The checker rejects missing media, changed reservation size/tag/results/traces,
missing snapshot validation, changed fault/exit boundaries, unexpected panics,
altered logs and unmanifested files. Historical checkers remain unchanged.
The prebuilt ARM64 kernel is inventoried; concurrent kernel edits were not
rebuilt. Selected hashes do not seal the complete compiler, header or
host-library closures.

Reproduce with the frozen toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, setting `V_RESOURCE_PATH`
there and `V_MACOS_V3_NO_FALLBACK=1`. Compile `notification-checks.v`,
`notification-vm.v`, `image-initializers-input-inventory.v`,
`dictionary-snapshot-evidence.v` and `inspect-dictionary-snapshot-fault.v` with
`-nocache -prod -gc none -cc clang`; the first two need the `tests/ios` module
path, and the inspector needs `compat/ios`. Use the wrapper's
`dictionary-snapshot-host` mode, then guest builds `build-init`,
`build-dictionary-snapshot`, `build-block-byref`, `build-vm-probe` and
`build-run-ios-gles`. Run `probe-no-ads` with
`VINIX_IOS_PROBE_MEMORY_MAX=2147483648` and `VINIX_IOS_VM_GZIP_LEVEL=9`.
Preserve the application, run the fault inspector with executable/serial/output
paths, capture the source/input inventory, then run the evidence tool's
`seal DIR`, `check DIR`, `selftest DIR` and `hash FILE` modes.
