# Fortnite URL session task checkpoint — 2026-10-25

Runtime and test source revision:
`e78a1ebea11b7a5e5babdcee78e0e9718b6ba93f`.

The shim now imports `NSURLSessionTask`, `NSURLSessionDownloadTask`,
`NSURLSessionDataTask` and `NSURLSessionUploadTask` through Foundation, with
their measured hierarchy and a base property subset. Initialization preserves
identity; copying retains the same object. Task descriptions are copied,
client byte expectations preserve signed values, and priority uses the float
calling convention, including measured handling of out-of-range and nonfinite
inputs. Advertising work remains skipped.

A fresh Vinix ARM64 QEMU Fortnite probe passes the task class imports and stops
at the next missing library/class:

```text
iOS: library is not implemented: /System/Library/Frameworks/GameController.framework/GameController (_OBJC_CLASS_$_GCController)
```

The runner exits 1 during linking, before application entry. Harness
`probe: PASS` and `FORTNITE PROBE COMPLETE` mean the failure was captured;
Fortnite has not started successfully.

## Validation and limits

Sixty native macOS Foundation inspections measure four classes across
metadata and fourteen operations. The native measurements establish a 720-byte
instance size and fourteen public-property backing ivars exposed by the shim;
other native private ivars are not implemented. Native iOS layout parity was
not measured.

The assertion-enabled host fixture passes ASan+UBSan at `-O0 -g`, normally and
with `SWIFT_DETERMINISTIC_HASHING=1`. The focused ARM64 guest fixture passes
with child status 0. The ARM64 initializer and GLES runner also build.
Coverage includes Foundation-only imports, hierarchy, method encodings and
ivars, float ABI and saved IMPs, copied descriptions, signed counts, eight
concurrent readers/writers, guarded caller storage, weak cleanup, `isa`
changes, subclass overrides and two drained runtime cycles. Fourteen rejection
cases cover unsupported operations, invalid descriptions/copies, custom
subclass construction and spoofed storage. Object and block-reference counters
balance; ASan leak detection was disabled, so this does not prove absence of
all heap leaks.

Task transfers and session association, `resume`, `suspend`, cancellation,
delegates, progress, coding, mutable copying and construction of custom task
subclasses remain unsupported. Native lifecycle diagnostics use allocated,
uninitialized objects and are not evidence that initialized task lifecycle
operations are safe. The shim rejects these operations explicitly unless an
application override handles them. Private byte-count writers observed on the
host are also unsupported.

The broader native regression suite and import audits were not rerun. Swift
support, Fortnite initialization, rendering, login and gameplay remain
unverified. Historical evidence checkers and their requirements are unchanged.

## Preserved evidence

Archive: `/Users/alex/Library/Caches/vinix-ios/session-task-startup-20261025.tar.zst`.
Archive SHA-256: `5e7ba7ed85176739aa5fc4f5b36a955293022c5fa844bfc8cb939c5a767e24e8`.
Contained manifest SHA-256: `763f51653225525d93900c423955d2b23b5a0882634acd823ad2bb14190241a3`.

The bundle contains the committed runtime and selected test source, native
inspection logs and statuses, selected build-input hashes and their V inventory
helper, generated C, host objects and app, compiled tools and ARM64 binaries,
and complete boot images, initramfs archives, firmware variables, Limine
configurations and serial logs for both VMs. Every file except the manifest
itself is checksummed. The archive contains local Fortnite assets and stays in
local storage. Compiler, header and host-library closures are not independently
sealed; rebuilding requires the prepared dependencies in this checkout.

The archive passed its compression integrity check. A fresh extraction
reproduced the manifest and passed `session-task-evidence.v selftest`: full
checksum verification, rejection of missing guest media, a changed host log
and an unmanifested file, restoration of each mutation, and a final complete
check.

Compile `tests/ios/notification-checks.v` and `tests/ios/notification-vm.v`
with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, using
`-nocache -prod -gc none -cc clang`. Compile
`tests/ios/inspect-session-task.v` and `tests/ios/inspect-user-notifications.v`
into the same fresh external output directory with `-nocache -gc none -cc clang`
to preserve their assertions. Set `V_RESOURCE_PATH` to that toolchain and
`V_MACOS_V3_NO_FALLBACK=1`. Run from the repository:

```sh
"$VINIX_TASK_OUT/notification-checks" session-task-inspect "$VINIX_TASK_OUT"
"$VINIX_TASK_OUT/notification-checks" session-task-host "$VINIX_TASK_OUT"
"$VINIX_TASK_OUT/notification-checks" build-session-task "$VINIX_TASK_OUT"
"$VINIX_TASK_OUT/notification-checks" build-init "$VINIX_TASK_OUT"
"$VINIX_TASK_OUT/notification-checks" build-run-ios-gles "$VINIX_TASK_OUT"
"$VINIX_TASK_OUT/notification-checks" session-task "$VINIX_TASK_OUT"
"$VINIX_TASK_OUT/notification-checks" probe "$VINIX_TASK_OUT"
```

Host and guest fixture generation preserves assertions. To audit a fresh
extraction, compile `tests/ios/session-task-evidence.v` with the frozen toolchain
using `-nocache -prod -gc none -cc clang`, then run (the checker uses explicit
error checks):

```sh
"$VINIX_TASK_CHECKER" check "$VINIX_TASK_RESTORED/session-task-20261025"
"$VINIX_TASK_CHECKER" selftest "$VINIX_TASK_RESTORED/session-task-20261025"
```
