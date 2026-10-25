# Fortnite UIStoryboard checkpoint — 2026-10-25

Runtime and test source revision:
`7fbc625130f8696c560a4323c08b39d3e422dff7`.

UIKit now resolves scoped UIStoryboard class and metaclass imports, with
`storyboardWithName:bundle:`, `instantiateInitialViewController` and
`instantiateViewControllerWithIdentifier:`. Advertising work remains skipped.
A fresh Vinix ARM64 QEMU Fortnite probe passes the UIStoryboard import and
stops at the next missing framework class:

```text
iOS: library is not implemented: /System/Library/Frameworks/GameKit.framework/GameKit (_OBJC_CLASS_$_GKGameCenterViewController)
```

The runner exits 1 during linking, before application entry. The probe wrapper
exits 0 because it captured that failure. Rendering, login and gameplay remain
unverified; Fortnite has not started successfully.

## Supported subset and validation

Factories accept nil or the cached main bundle, read source `.storyboard`
resources from `Base.lproj` with bundle-root fallback, and retain immutable
resource snapshots. Initial controllers use XML IDs; named controllers use
`storyboardIdentifier`. Each instantiation creates a fresh controller graph,
including supported custom UIViewController subclasses. Basic UIView,
UIButton and UILabel graphs support frames, background colors, normal button
titles and same-controller `touchUpInside` actions. Application storyboard
loading uses the same bounded parser and controller builder.

The XML reader limits input to 1 MiB, 4096 nodes, depth 64 and 64 attributes per
element. View construction limits depth to 32 and children to 64 per view.
Malformed XML, DTDs, external/unknown entities, text content, unsupported view
properties and invalid controller initialization fail explicitly. Partial
construction releases its graph. Compiled `.storyboardc`/NIB archives, Auto
Layout, custom view classes and creator/coding/copy APIs remain unsupported.

The three supported Objective-C method encodings are `@32@0:8@16@24`,
`@16@0:8` and `@24@0:8@16`, respectively. Compatibility storage is an opaque
8-byte NSObject subclass; native private instance-layout parity was not
measured or claimed.

The assertion-enabled host fixture passes ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 QEMU fixture passes with
child status 0. Coverage includes scoped imports, typed reflection, resource
snapshot ownership, fresh/custom controllers, actions, root fallback, bounded
XML rejection, partial-construction cleanup, two drained runtimes and 20
explicit fatal rejection cases. Runtime object counters balance; ASan leak
detection was disabled, so this does not establish absence of all heap leaks.
The driver, ARM64 fixture, initializer and GLES runner build successfully.
The broader native regression suite and import audits were not rerun.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/storyboard-startup-20261025.tar.zst`.
Archive SHA-256: `6794af77b35b82e2012bf05eaab95f99b3b71c08f93651e905ab4361133401a2`.
Contained manifest SHA-256: `e1eb6c5e32e683131642ad464ebbf9535fec6179837900f8f009cded193e3469`.

The bundle preserves 14 committed source snapshots, 72 selected build-input
hashes and their V inventory helper, generated C, host objects and app,
compiled tools and ARM64 binaries, and complete boot media, initramfs,
firmware variables, Limine configurations and serial logs for both VMs.
All 85 files other than the manifest are checksummed. Local Fortnite assets
remain in external local storage. Compiler, header and host-library closures
are not independently sealed; rebuilding requires the prepared dependencies
in this checkout. Historical evidence checkers are unchanged.

Compression integrity passed. A fresh extraction passed
`storyboard-evidence.v selftest`: full checksum verification, rejection of
missing guest media, an altered host log and an unmanifested file, restoration
of each mutation, and a final complete check. The temporary extraction was
removed after rechecking the archive and manifest hashes to recover disk
space; the original bundle and archive remain preserved.

Build `tests/ios/notification-checks.v`, `notification-vm.v`, `native-checks.v`,
`storyboard-input-inventory.v` and `storyboard-evidence.v` using the frozen
toolchain at `build/ios/fortnite/ns-calendar-checks/toolchain` with
`-nocache -prod -gc none -cc clang`. Set `V_RESOURCE_PATH` to that toolchain
and `V_MACOS_V3_NO_FALLBACK=1`. From the repository, invoke the compiled
notification-checks driver with each mode and a fresh external output
directory: `driver-build`, `storyboard-host`, `build-storyboard`, `build-init`,
`build-run-ios-gles`, `storyboard`, `probe`. Fixture generation preserves
assertions. Commands and exit statuses are recorded in the bundle.

Invoke the inventory helper with repository root, external bundle directory
and tested revision. Copy it to `inventory-inputs.v` and the checker source to
`storyboard-evidence.v` inside the bundle. Run the checker with `seal DIR`
before archiving, then `selftest DIR` on a fresh extraction. Its `hash FILE`
mode computes archive and manifest SHA-256 values.
