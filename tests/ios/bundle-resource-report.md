# NSBundleResourceRequest constructor profile — 2026-10-25

Source revision: `b25b5f1e017e53d99a11ff34b05cbcef823f1654`.

`NSBundleResourceRequest` now resolves through Foundation with Apple's measured
48-byte layout, five ivars and six constructor/property encodings. The bounded
profile supports `initWithTags:`, `initWithTags:bundle:`, `tags`, `bundle`,
`loadingPriority` and `setLoadingPriority:`. Priority starts at 0.5 and finite
values clamp to 0–1.

Nil tags stay nil; an empty set stays empty. Built-in immutable or mutable sets
are copied shallowly to an immutable set, retaining their string members. The
input set can change or be released independently; mutable member identity is
preserved. Inputs are bounded to 4,096 tags and 65,536 UTF-8 bytes per tag,
including embedded NUL bytes. The implicit bundle is the retained main bundle;
the explicit initializer accepts that bundle or preserves an explicit nil.

Construction snapshots and pins inputs before application constructors can
reenter. Constructors run outside the runtime lock; destination provenance is
checked again before publishing state. Failure releases staged ownership.
Allocation ownership governs cleanup after isa replacement, including guarded
caller storage. Unsupported custom subclasses, nonfinite priorities, progress,
resource access/completion, copying and coding fail explicitly. There is no
on-demand resource provider or download implementation.

## Validation

Apple Foundation metadata and five native behavior modes were inspected. The
shared fixture passed against Foundation and the V runtime on the ARM64 Mac
under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Assertions remained enabled; leak detection was
disabled. Native parity covers layout, encodings, nil/empty/UTF-8/NUL tags,
shallow set copying, retained bundles, explicit nil bundles and priority clamping.

Runtime checks cover constructor rollback and joined worker reentry, snapshots
surviving input release, 400 concurrent priority roundtrips, guarded caller
storage, 32 isa replacements and 37 explicit rejection cases. Two drained
runtimes retain only the main bundle; shutdown finishes with zero owned objects
and weak registrations. These counters do not establish absence of all heap
leaks.

All 19 ARM64 targets built: 16 assertion-enabled regression fixtures, the guest
initializer, and static and GLES runners. All 16 fixtures exited successfully in
the Vinix QEMU guest, including the resource-request fixture and its 37 rejection
cases. The broader native-ABI suite was not rerun.

The fresh Fortnite probe resolves `NSBundleResourceRequest` and stops during
linking at `_OBJC_CLASS_$_ASIdentifierManager` in
`/System/Library/Frameworks/AdSupport.framework/AdSupport`, before application
entry. Both import audits completed with these measured totals:

| Runner | Resolved | Unresolved strong | Unresolved weak |
| --- | ---: | ---: | ---: |
| Static C++ | 2,933 | 71 | 114 |
| C++/GLES/Text | 2,947 | 57 | 114 |

Audits measure linker bindings and do not execute app code. Resolved diagnostic
stubs still stop execution when called. No Fortnite initialization, rendering,
login or gameplay was verified. Swift support remains unverified.

## Evidence and reproduction

Archive: `/Users/alex/Library/Caches/vinix-ios/bundle-resource-20261025.tar.zst`.
Archive SHA-256: `e495e3d7fff9f498062cf186a81a6855cf5d2c8e8d3589b98209ae44345ff5b7`.
Contained manifest SHA-256: `f056671379726432ac412d47f9c978a24af6366258cc2d729be4d6fc9513f730`.

The complete bundle retains committed source snapshots, generated C, host
objects and app, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`bundle-resource-evidence.v` checks the complete inventory, exact result markers
and every manifested file's SHA-256, rejecting extra files. Historical checkers
remain unchanged. Compiler-header and host dynamic-library closures are not
independently sealed. Rebuilding requires the prepared dependencies used by the
V tools.

Sealing, complete inventory checks and checker selftests passed. The selftests
rejected missing guest media, a changed log and an extra unmanifested file, then
verified the restored original bundle. The persistent archive's SHA-256 matched
the original, and `zstd --long=31 -t` passed. A fresh extraction into
`/private/tmp/vinix-bundle-resource-restored-20261025.P2VX8c` passed its contained
`bundle-resource-evidence check` without resealing; its manifest SHA-256 matches
the value above.

From the source revision above in the repository root, compile the tools into
a fresh external directory. The inspectors and generated fixtures retain
assertions; orchestration tools use explicit failure checks in production builds:

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_RESOURCE_OUT=/external/fresh-bundle-resource
mkdir -p "$VINIX_RESOURCE_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_RESOURCE_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_RESOURCE_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_RESOURCE_OUT/bundle-resource-evidence" tests/ios/bundle-resource-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_RESOURCE_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_RESOURCE_OUT/inspect-bundle-resource" tests/ios/inspect-bundle-resource.v
"$VINIX_RESOURCE_OUT/notification-checks" bundle-resource-metadata-inspect "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" bundle-resource-inspect "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" bundle-resource-host "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" driver-build "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" build "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" notifications "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" probe "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" audit "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/notification-checks" static-audit "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/bundle-resource-evidence" snapshot "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/bundle-resource-evidence" seal "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/bundle-resource-evidence" selftest "$VINIX_RESOURCE_OUT"
"$VINIX_RESOURCE_OUT/bundle-resource-evidence" archive-zstd "$VINIX_RESOURCE_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and the exact linker blocker or audit totals. For a sealed bundle, run
`bundle-resource-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-bundle-resource
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/bundle-resource-20261025.tar.zst --strip-components=1 -C /external/restored-bundle-resource
/external/restored-bundle-resource/bundle-resource-evidence check /external/restored-bundle-resource
```
