# English NSNumberFormatter profile — 2026-10-25

Source revision: `039f270ba96cf30d8779063daa70565247a5357e`.

`NSNumberFormatter` now resolves through Foundation with Apple's measured
64-byte layout, seven ivars and method encodings. The supported profile covers
English no-style and decimal formatting for `en_US`, `en_GB` and `en_US_POSIX`,
half-even rounding, grouping, integer/fraction padding, exact signed/unsigned
64-bit integers, strict parsing, copied locale state and independent copies.
Reinitialization resets settings and the explicit locale.

Formatting accepts built-in NSNumber values, including signed zero and
nonfinite values. Parsing accepts at most 128 bytes, validates grouping and
supports finite decimal/exponent values with at most 17 significant digits.
Explicit integer digit settings are bounded to 64, fraction digits and grouping
size to 16. Currency, percent and other styles, arbitrary localization,
custom symbols, significant-digit options, integer-only parsing, coding and
custom subclasses fail explicitly. This is a bounded compatibility profile.

Operations pin the receiver and snapshot input before current-locale callbacks.
Copying snapshots settings and retains the locale before constructors can
reenter; source and target pins protect callback lifetimes. Callbacks run
outside the runtime lock. Sidecar state follows allocation ownership, including
caller storage, failed construction and cleanup after an isa replacement.
Active destruction and invalid provenance fail explicitly.

## Validation

The shared fixture passed against Apple Foundation and the V runtime on the
ARM64 Mac under ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. Assertions remained enabled; leak detection was
disabled. Checks cover native metadata, English defaults, symbols, nil inputs,
half-even ties and carry, grouping, padding, integer truncation, exact 64-bit
values, parsing and independent copy lifetime.

Runtime checks cover input snapshots across first-locale callbacks, joined
worker callbacks that mutate/release the copy source, constructor rollback,
guarded caller storage, 32 isa replacements, 192 concurrent roundtrips and
33 explicit rejection cases. Two drained runtimes retain only the current
locale and its identifier; pending-autorelease shutdown finishes with zero
owned objects and weak registrations. These counters do not establish absence
of all heap leaks. The existing NSDateFormatter fixture also passed both host
sanitizer modes, including its 45 rejection cases.

All eighteen ARM64 fixtures and runners built, and the full native regression
driver compiled. The focused QEMU guest passed all fifteen number/date
formatter, lock, recursive lock, map-table, credential, telephony, cache,
calendar and notification fixtures. The full native regression suite was not run.

The fresh Fortnite probe resolves `NSNumberFormatter` and stops during linking
at `_OBJC_CLASS_$_NSBundleResourceRequest`, before application entry. The child
exits 1. The static C++ audit reports 2,932 resolved imports, 72 unresolved strong
and 114 unresolved weak; the C++/GLES/Text audit reports 2,946 resolved,
58 unresolved strong and 114 unresolved weak. Both include optional SQLite.

| Image | Static resolved / strong / weak | GLES resolved / strong / weak |
| --- | ---: | ---: |
| Fortnite executable | 2,092 / 69 / 78 | 2,103 / 58 / 78 |
| EOSSDK | 661 / 3 / 16 | 664 / 0 / 16 |
| MarketplaceKitWrapper | 179 / 0 / 20 | 179 / 0 / 20 |

Each audit resolves one more import and leaves one fewer strong import missing
than the preceding NSLock milestone. These counts measure linker bindings;
resolved diagnostic stubs still stop execution when called.

Audits do not execute app code. No Fortnite initialization, rendering, login
or gameplay was verified. Swift support remains unverified.

## Evidence and reproduction

Archive: `/Users/alex/Library/Caches/vinix-ios/number-formatter-20261025.tar.zst`.
Archive SHA-256: `39d20d755fc718e8d5873bb9bddb37c2c413a8e166bf5bbe93b87152ef27def4`.
Contained manifest SHA-256: `7bb11a49d89cc50735bc3b71377b73c1134c559f36b2b4a5c92b353147519bdc`.

The complete bundle retains committed source snapshots, generated C, host
objects and apps, ARM64 fixtures and runners, command logs and statuses, and
selected build-input hashes. Each of four VM states retains its boot image,
firmware variables, initramfs, Limine configuration and serial log.
`number-formatter-evidence.v` checks the complete inventory, exact result
markers and every manifested file's SHA-256, rejecting extra files.
Historical checkers remain unchanged. Compiler-header and host dynamic-library
closures are not independently sealed. Rebuilding requires the prepared
dependencies used by the V tools.

Sealing and all three rejection self-tests passed: missing guest media,
modified inspection output and an unmanifested file were rejected, with the
bundle restored afterwards. Archive compression integrity, independent
SHA-256 checks and a fresh extraction passed. The restored bundle passed the
complete checker without resealing. The archive and checksum remain on the
persistent filesystem at the path above.

From the source revision above in the repository root, compile the tools into
a fresh external directory. The inspector and generated fixtures retain
assertions; orchestration tools use explicit failure checks in production builds:

```sh
export V_RESOURCE_PATH="$PWD/build/ios/fortnite/ns-calendar-checks/toolchain"
export V_MACOS_V3_NO_FALLBACK=1
export VINIX_NUMBER_OUT=/external/fresh-number-formatter
mkdir -p "$VINIX_NUMBER_OUT"
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NUMBER_OUT/notification-checks" tests/ios/notification-checks.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NUMBER_OUT/notification-vm" tests/ios/notification-vm.v
"$V_RESOURCE_PATH/v" -nocache -prod -gc none -cc clang -o "$VINIX_NUMBER_OUT/number-formatter-evidence" tests/ios/number-formatter-evidence.v
"$V_RESOURCE_PATH/v" -nocache -gc none -cc clang -o "$VINIX_NUMBER_OUT/inspect-user-notifications" tests/ios/inspect-user-notifications.v
"$VINIX_NUMBER_OUT/notification-checks" number-formatter-metadata-inspect "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" number-formatter-host "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" date-formatter-host "$VINIX_NUMBER_OUT/date-host"
"$VINIX_NUMBER_OUT/notification-checks" driver-build "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" build "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" notifications "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" probe "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" audit "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/notification-checks" static-audit "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/number-formatter-evidence" snapshot "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/number-formatter-evidence" seal "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/number-formatter-evidence" selftest "$VINIX_NUMBER_OUT"
"$VINIX_NUMBER_OUT/number-formatter-evidence" archive-zstd "$VINIX_NUMBER_OUT"
```

The wrapper's successful probe/audit status means the guest completed and its
evidence was captured; the child still exits 1. The checker requires that exit
status and the exact linker blocker or audit totals. For a sealed bundle, run
`number-formatter-evidence check DIR` without resealing.

To restore the archive to a fresh external directory:

```sh
mkdir -p /external/restored-number-formatter
/usr/bin/tar --use-compress-program='/opt/homebrew/bin/zstd --long=31 -d' -xf /Users/alex/Library/Caches/vinix-ios/number-formatter-20261025.tar.zst --strip-components=1 -C /external/restored-number-formatter
/external/restored-number-formatter/number-formatter-evidence check /external/restored-number-formatter
```
