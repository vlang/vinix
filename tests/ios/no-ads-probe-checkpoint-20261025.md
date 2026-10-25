# Fortnite no-ads launch probe checkpoint — 2026-10-25

Runtime and test revision: `f0fd266739cd133e273e0a3b16bc2328475a8297`.
Advertising implementation remains skipped.

`run-ios --probe-no-ads PATH` explicitly opts into a diagnostic launch that
binds only `_OBJC_CLASS_$_SKAdNetwork` from the StoreKit framework to nil.
It prints a warning that application behavior is modified. Ordinary launches,
import audits, dynamic lookup, other libraries and other symbols remain strict.
This provides no advertising API implementation or general missing-import
fallback. Startup tracing identifies binding, Objective-C registration,
`+load`, initializer and application entry stages.

Assertion-enabled host tests pass ASan+UBSan at `-O0 -g`, normally and with
`SWIFT_DETERMINISTIC_HASHING=1`. They check exact opt-in binding, nil messaging,
strict audit and dynamic lookup, unrelated imports and runtime reset. ASan leak
detection was disabled; the broader fixture suite was not rerun. The host
fixture, test drivers, ARM64 initializer and GLES runner build successfully.

Three fresh full-IPA Vinix ARM64 QEMU runs establish the following:

- The diagnostic launch binds SKAdNetwork to nil, registers Objective-C
  metadata for EOSSDK and MarketplaceKitWrapper, then stops while registering
  the main executable with `iOS: Swift class metadata is not implemented`.
- The ordinary launch still stops at the unimplemented StoreKit SKAdNetwork
  import during linking.
- The import audit still reports **3003 resolved, 1 unresolved strong and 114
  unresolved weak imports**. Per image, the main executable reports 2160/1/78,
  EOSSDK 664/0/16 and MarketplaceKitWrapper 179/0/20 (resolved/strong/weak).
  SKAdNetwork remains the sole unresolved strong import; audits run no app code.

All three guest processes exit 1 (raw wait status 256); their capture wrappers
exit 0. No run reaches `+load`, initializers or application entry. The next
measured blocker is Swift class metadata support. Rendering, login and gameplay
remain unverified; Fortnite is not playable.

Complete evidence bundle:
`/Users/alex/Library/Caches/vinix-ios/no-ads-probe-20261025`.
Manifest SHA-256:
`a1599354590418d348acfed19841b2f198b742acfd3b3d4112ce230cad5c0c03`.

The manifest seals all 1183 other files, including 1124 committed source
snapshots, 74 selected build input hashes, generated C, host objects and binary,
compiled drivers and ARM64 binaries, commands/statuses, and complete boot
images, initramfs, firmware variables, Limine configurations and serial logs
for all three guest runs. Selected hashes do not seal compiler, header or host
library closures; rebuilding requires prepared checkout dependencies. The
prebuilt kernel is inventoried; concurrent kernel edits were not rebuilt.
Historical checkers are unchanged.

Checksum verification and selftests pass, including rejection of missing guest
media, an altered host log and an unmanifested file, restoration of every
mutation and final verification. No separate archive or restore test was
performed. Helper logs are in the adjacent `no-ads-probe-tools-20261025` directory.

Reproduce using frozen V at
`build/ios/fortnite/ns-calendar-checks/toolchain`, with `V_RESOURCE_PATH` set
there and `V_MACOS_V3_NO_FALLBACK=1`. Compile notification-checks,
notification-vm, no-ads-probe-input-inventory and no-ads-probe-evidence with
`-nocache -prod -gc none -cc clang`. Run notification-checks with a fresh
external output directory and modes `probe-no-ads-host`, `build-init`,
`build-run-ios-gles`, `probe-no-ads`, `probe`, `audit`. Host fixture generation
omits `-prod` to retain assertions; guest runs use `VINIX_IOS_VM_GZIP_LEVEL=9`.
Invoke the inventory with repository root, bundle directory and tested revision;
then use evidence checker modes `seal DIR`, `check DIR`, `selftest DIR` and
`hash FILE`.
