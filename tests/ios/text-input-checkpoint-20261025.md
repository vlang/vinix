# Fortnite text input checkpoint — 2026-10-25

Runtime and test revision: `0fcf758186a6c135c5041bb6b89c9e77ade330fa`.
Advertising work remains skipped.

UIKit now resolves scoped `UITextPosition` and `UITextRange` class/metaclass
imports with their NSObject inheritance. Text ranges expose SDK getter
metadata for `isEmpty`, `start` and `end`. App subclasses supply their own
storage and implementations; native ivar access, BOOL/object returns, saved
getter IMPs and ownership of range endpoints are exercised. Builtin instances
use isa-only shim storage; native private layout parity is not claimed.

Abstract getters and unsupported copy/coding operations require subclass
implementations and fail explicitly otherwise, including saved builtin IMP
and super dispatch. This provides abstract text-input objects, not a complete
text editor or keyboard implementation.

A fresh Vinix ARM64 QEMU Fortnite probe passes the text-input imports and stops at:

```text
iOS: linking /opt/ios/FortniteClient-IOS-Shipping: iOS: framework symbol is not implemented: _OBJC_CLASS_$_UIPanGestureRecognizer
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Rendering, login and gameplay remain
unverified; Fortnite has not started successfully.

Assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with
child status 0: scoped imports, abstract getter metadata, native subclass
storage and dispatch, endpoint ownership, weak zeroing, two drained runtimes
and 20 explicit fatal rejection cases. Runtime object counters balance. ASan
leak detection was disabled; this does not establish absence of all heap
leaks. The driver, ARM64 fixture, initializer and GLES runner build
successfully. The broader native regression suite and import audits were not
rerun.

Archive: `/Users/alex/Library/Caches/vinix-ios/text-input-startup-20261025.tar.zst`.
Archive SHA-256: `1205aeb3815aaba8c4dd99b3cb693e38cb414943fce99ababf0d3a033c1ce1c8`.
Contained manifest SHA-256: `32102b90dd79ba741eaed7cf43cb17bfa563d3783ab4fb41b36c1586d3d8921b`.

The bundle preserves 12 committed source snapshots, both V audit helpers,
73 selected input hashes (including the SDK UITextInput declaration), generated
C, host objects/app, compiled drivers and ARM64 binaries, commands/statuses,
and complete boot media, initramfs, firmware variables, Limine configurations
and serial logs for both VMs. All 72 files other than the manifest are
checksummed. Local Fortnite assets remain in external storage. Compiler,
header and host-library closures are not independently sealed; rebuilding
requires the prepared checkout dependencies. Historical checkers are unchanged.

Compression integrity and original-bundle selftest pass. A fresh extraction at
`/Users/alex/Library/Caches/vinix-ios/text-input-restored-20261025/text-input-20261025`
also passes full checksums, rejection of missing guest media, an altered host
log and an unmanifested file, restoration of each mutation, and final checking.

Reproduce using the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`, `V_RESOURCE_PATH` set to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Build `tests/ios/notification-checks.v`,
`notification-vm.v`, `native-checks.v`, `text-input-input-inventory.v` and
`text-input-evidence.v`. Invoke the notification-checks driver with a fresh
external directory and modes `driver-build`, `text-input-host`,
`build-text-input`, `build-init`, `build-run-ios-gles`, `text-input`, `probe`.
Fixture generation preserves assertions. Invoke the inventory helper with
repository root, bundle directory and tested revision; copy both audit helpers
into the bundle as `inventory-inputs.v` and `text-input-evidence.v`. Use checker
modes `seal DIR`, `selftest DIR` and `hash FILE` to seal, audit and hash it.
