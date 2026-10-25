# Fortnite capture audio output checkpoint — 2026-10-25

Runtime and test revision: `3d9ee58e164856a15f0170c1109c5bc52571b671`.
Advertising work remains skipped.

The AVFoundation shim now resolves the scoped `AVCaptureAudioDataOutput`
and `AVCaptureOutput` class/metaclass imports. The unconnected audio output
matches native class sizes, inheritance and method encodings, keeps its
delegate weak and its callback queue retained, and supports queue replacement
and clearing. It reports immutable empty connections and nil recommended
settings for ten supported file types. There is no capture backend or audio
sample delivery. Unsupported construction, copying, coding, isa changes,
storage, mutation and observation fail explicitly.

Four concurrent workers exposed an object-map lookup race in constant integer
dispatch. That lookup now takes the existing recursive initialization lock;
the lock is released before method dispatch or native waits.

The native ARM64 Mac Catalyst inspector passes class, selector, ownership,
weak-zeroing and unconnected-result checks. Assertion-enabled shim fixtures
pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Coverage includes scoped imports, saved IMPs,
delegate and queue lifetime/replacement, four workers performing 128 iterations
each, two drained runtimes, and 30 isolated rejection cases. Object counters
balance and runtime object/block maps drain. ASan leak detection was disabled;
these checks do not establish absence of all heap leaks. The broader native
regression suite was not rerun.

Drivers, the ARM64 fixture, initializer and GLES runner build successfully.
The focused Vinix ARM64 QEMU fixture passes with child status 0. A fresh full
Fortnite import audit reports **2980 resolved, 24 unresolved strong and 114
unresolved weak imports**, reducing the preceding strong-import count from
25 to 24. Per image, the main executable reports 2137/24/78, EOSSDK 664/0/16
and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak). The audit does not
execute application code. A separate normal launch probe still stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: library is not implemented: /System/Library/Frameworks/StoreKit.framework/StoreKit (_OBJC_CLASS_$_SKAdNetwork)
```

Both Fortnite runs exit 1 during linking, before application entry; their
wrappers exit 0 after capturing that failure. Rendering, login and gameplay
remain unverified. SKAdNetwork work remains skipped as requested.

Archive: `/Users/alex/Library/Caches/vinix-ios/capture-audio-output-20261025.tar.zst`.
Archive SHA-256: `555b35ab232e943b76b026c800a195e1b88a880ba1aa39f747d44089e6d15d4b`.
Contained manifest SHA-256: `2b38af58505789e9f26fdcf5c6d7570f234976c32abd9b9ccc094906d5249f6f`.

The complete bundle preserves 17 committed source snapshots, both V audit
helpers, 73 selected build input hashes, generated C, host objects/app,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
media, initramfs, firmware variables, Limine configurations and serial logs
for all three VMs. All 90 files other than the manifest are checksummed.
Local Fortnite assets remain in external storage. Compiler, header and host
library closures are not independently sealed; rebuilding requires the
prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle checks/selftest pass. A fresh
extraction at
`/Users/alex/Library/Caches/vinix-ios/capture-audio-output-restored-20261025/capture-audio-output-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.
The original and restored manifest hashes match.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `capture-audio-output-input-inventory.v`
and `capture-audio-output-evidence.v`. Invoke the notification-checks driver
with a fresh external directory and modes `driver-build`,
`capture-audio-output-inspector-build`, `capture-audio-output-inspect`,
`capture-audio-output-host`, `build-capture-audio-output`, `build-init`,
`build-run-ios-gles`, `capture-audio-output`, `probe`, `audit`. Run
`driver-build` first to initialize its directories. Fixture generation
preserves assertions. Invoke the inventory helper with repository root,
bundle directory and tested revision; copy both audit helpers into the bundle
as `inventory-inputs.v` and `capture-audio-output-evidence.v`. Use checker
modes `seal DIR`, `check DIR`, `selftest DIR` and `hash FILE` to seal, audit
and hash it.
