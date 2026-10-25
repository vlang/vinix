# Fortnite feedback checkpoint — 2026-10-25

Notification and selection source revision:
`1d95d1eeb0507f398053205ea7bfb9344be3a52b`.
Impact source revision: `40576a58b46d539d8627e79a543d3ec925bc1283`.
The first evidence snapshot records
`e2a3e40593ad081fe752e36d64c67714ec3126db`, whose iOS sources and selected
test tools are identical to the notification and selection revision. The
`impact/` snapshot records the impact revision directly.

The shim now accepts UIKit feedback requests through `UIFeedbackGenerator`,
`UINotificationFeedbackGenerator`, `UISelectionFeedbackGenerator` and
`UIImpactFeedbackGenerator`. Preparation, notification, selection and impact
requests succeed without producing hardware haptics. `initWithStyle:` returns
its receiver, including for all five impact styles. Advertising work remains
skipped.

Both phases include a fresh Vinix ARM64 QEMU Fortnite probe. Notification and
selection support advances linking to `_OBJC_CLASS_$_UIImpactFeedbackGenerator`;
impact support advances it to `_OBJC_CLASS_$_NSURLSessionDownloadTask`. Both
runner processes exit 1 during linking, before application entry. Harness
`probe: PASS` and `FORTNITE PROBE COMPLETE` markers mean the failure was captured;
Fortnite has not started successfully.

## Validation

Both assertion-enabled host fixtures pass ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. Both focused ARM64 guest fixtures pass with
child status 0. The ARM64 guest initializer and GLES runner build successfully
in both phases.

Coverage includes UIKit-only imports, the class hierarchy, instance-only
selectors, object/void/integer/double calling conventions, method encodings and
signatures, guarded 8-byte caller storage, subclass overrides and saved IMPs.
The impact fixture covers all five styles and floating-point intensities 0,
0.5 and 1. Repeated requests and four concurrent workers exercise the no-op
paths; object and block-reference counters balance across two runtime shutdown
and startup cycles. Leak detection was disabled, so those counters do not prove
absence of all heap leaks.

The 8-byte opaque shim layout and absence of ivars are implementation choices;
native UIKit layout parity was not measured on this macOS host. Copying and
coding remain unsupported and are not advertised. Hardware haptics, the broader
native regression suite and import audits were not verified here. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/feedback-startup-20261025.tar.zst`.
Archive SHA-256: `55fd900180ed5b6bccf50bc165f3595b8dd9f919e510bf2b27018b9f00d3beea`.
Contained manifest SHA-256: `8381c095bf7f8f4cb6102265eb56b16fe9580c77de80807827e61e6c7c289810`.

The bundle retains both source snapshots, selected build-input hashes, generated
C, host objects and apps, compiled tools and ARM64 binaries, command logs and
statuses, and all four VMs' boot images, initramfs archives, firmware variables,
Limine configurations and serial logs. Intermediate failed build attempts are
retained without claiming they passed. The manifest inventories every file
except itself. The archive contains local Fortnite assets and stays in local
storage. Host library and compiler-header closures are not independently
sealed; rebuilding requires the prepared dependencies in this checkout.

The persistent archive passed its compression integrity check. A fresh
extraction reproduced the manifest byte for byte and passed
`tests/ios/feedback-evidence.v selftest`, including complete checksum checks.
The self-test verifies
rejection of missing guest media, a changed host log and an unmanifested file,
restores each mutation, then rechecks the complete bundle.

From either runtime revision, compile `tests/ios/notification-checks.v` and
`tests/ios/notification-vm.v` with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Set `V_RESOURCE_PATH` to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Run from the repository with the compiled drivers in
a fresh external directory:

```sh
"$VINIX_FEEDBACK_OUT/notification-checks" feedback-host "$VINIX_FEEDBACK_OUT"
"$VINIX_FEEDBACK_OUT/notification-checks" build-feedback "$VINIX_FEEDBACK_OUT"
"$VINIX_FEEDBACK_OUT/notification-checks" build-init "$VINIX_FEEDBACK_OUT"
"$VINIX_FEEDBACK_OUT/notification-checks" build-run-ios-gles "$VINIX_FEEDBACK_OUT"
"$VINIX_FEEDBACK_OUT/notification-checks" feedback "$VINIX_FEEDBACK_OUT"
"$VINIX_FEEDBACK_OUT/notification-checks" probe "$VINIX_FEEDBACK_OUT"
```

The host and guest fixture generation retains assertions. To audit a fresh
archive extraction, compile `tests/ios/feedback-evidence.v` with that toolchain
using `-nocache -prod -gc none -cc clang`, then run (the checker uses explicit
error checks):

```sh
"$VINIX_FEEDBACK_CHECKER" check "$VINIX_FEEDBACK_RESTORED/vinix-feedback-20261025"
"$VINIX_FEEDBACK_CHECKER" selftest "$VINIX_FEEDBACK_RESTORED/vinix-feedback-20261025"
```
