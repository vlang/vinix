# Scene notification checkpoint — 2026-10-26

Runtime, fixture and evidence tools revision:
`cc7d9af906b8bfd5344e80f6a8f5a1024408bcf8`.
Advertising work remains skipped.

Fortnite's preceding null read at preferred PC `0x10009b674` dereferenced
the unresolved weak data export at preferred slot `0x10dc981e0`:
`_UISceneWillEnterForegroundNotification`. The runner now resolves it and
`_UISceneDidEnterBackgroundNotification` through the existing locked framework
constant cache. Each export supplies a stable pointer cell containing an
NSString, owned until runtime teardown. Unknown exports remain unsupported;
the loader's unresolved weak-import behavior is unchanged.

A native Catalyst UIKit oracle confirms both exported NSString values equal
their symbol names. The oracle requires the Mac Catalyst target
`arm64-apple-ios14.0-macabi`; an initial ordinary macOS load failed and is
preserved separately. Assertion-enabled runtime fixtures pass ASan+UBSan at
`-O0 -g`, normally and with `SWIFT_DETERMINISTIC_HASHING=1`; leak detection was
disabled. They cover eight concurrent first lookups, pointer-cell stability,
distinct constants, notification delivery using equal but distinct NSStrings,
object filters, observer removal, autorelease-pool survival, unknown-symbol
rejection and two drained runtime cycles.

Both ARM64 macOS host and Vinix ARM64 QEMU probes now pass nine `+load` methods
in order: FIRMessaging, FIRInstallations, GDTCCTUploader, GDTCORFlatFileStorage,
GDTCORLifecycle, GDTCORMetricsController, GDTCORApplication,
iOSConfigRuleProviders and fortConfigRuleProvider. Both print initializer-stage
markers for EOSSDK, MarketplaceKitWrapper and the main executable.

Startup still fails. A dispatch worker reports unsupported
`NSData dataWithContentsOfURL:`; the main initializer path reports unsupported
`NSProcessInfo physicalMemory`. Their log ordering varies with scheduling.
The host exits with status 1 and no sanitizer report. The guest records wait
status 256, process status 1 and the diagnostic completion marker. Harness
status 0 means the probe completed. Initializer completion, application entry,
rendering, login and gameplay remain unverified. `--probe-no-ads` binds
SKAdNetwork to nil and changes application behavior; ordinary launch still
requires SKAdNetwork.
Executable SHA-256:
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/scene-notifications-20261026`.
Manifest SHA-256:
`165d360d7783da1f2ef89e79a13f92932ff9ee27f3cb4d0f129df120853e3d1e`.
The manifest covers 1,234 files, including 1,135 source snapshot files; the
input inventory records 76 selected build-input hashes.
Evidence `seal`, `check` and `selftest` pass. The self-test rejects missing
guest media, a changed fixture log and an unmanifested extra file, then restores
and revalidates the complete bundle.

The bundle preserves the source snapshot, selected build-input hashes, import
inspection, native oracle, fixture app, generated host/guest C, host objects,
compiled runners and helpers, command/status logs, unchanged application and
frameworks, and the complete guest boot image, initramfs, firmware variables,
Limine configuration and serial log. Selected hashes do not seal compiler,
header or host-library closures. The prebuilt kernel is inventoried; concurrent
kernel edits were not rebuilt. The preceding failure and its complete sealed
bundle remain in the [character search checkpoint](string-character-search-checkpoint-20261026.md).

Reproduce with the frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`, `V_RESOURCE_PATH` set there
and `V_MACOS_V3_NO_FALLBACK=1`. Compile the V helpers with
`-gc none -nocache -cc clang`. Run notification-checks modes
`scene-notifications-inspector-build` and `scene-notifications-inspect` for the
native oracle, and `scene-notifications-host` for the runtime fixture, each
into an external directory. Use startup-host `build OUT` then
`probe-no-ads OUT APP_EXECUTABLE` for host diagnostics; use notification-checks
`build-init`, `build-run-ios-gles` and `probe-no-ads` for the guest, with
`VINIX_IOS_VM_GZIP_LEVEL=9` for this run. Exact invocations are in command logs.
Run image-initializers-input-inventory with repository root, bundle directory
and tested revision, then scene-notifications-evidence modes `seal DIR`,
`check DIR`, `selftest DIR` and `hash FILE`. Historical checkers are unchanged.
