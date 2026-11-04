# Device feedback capability checkpoint — 2026-11-04

`b0318a39e6b6e094f80eb546fafebcbd62b91d72` implements UIDevice's
_feedbackSupportLevel getter and the two measured KVC spellings,
`_feedbackSupportLevel` and `feedbackSupportLevel`. The built-in getter reports
zero because Vinix's existing feedback-generator backend has no actuator.
Lookup returns an autoreleased signed NSNumber and dispatches the getter
normally, preserving private getter overrides. Other device keys fail explicitly;
general NSObject KVC and private ivar access remain unsupported.

The read-only V diagnostic `tests/ios/inspect-objc-key.v` identified the key at
game call site `0x1049f0300`, twelve bytes after a currentDevice call. It handles
the image's chained pointers and ARM64 selector stubs; its output is a static
hint, independently checked against bounded LLVM disassembly. Dynamic values
and control flow remain outside that tool's analysis. Native Catalyst probing
with `tests/ios/inspect-device-feedback.v` measures getter encoding `q16@0:8`,
NSNumber value 0, and objCType `q` for both key spellings. These are measured
private API details, not a public UIKit compatibility guarantee.

Shared native/runtime tests compare the values, NSNumber type and method
encodings. Runtime tests cover instance-only discovery, inherited direct IMP
calls, subclass getter replacement, autorelease ownership, four concurrent
readers and two runtimes drained to zero live objects and heap blocks. Existing
feedback-generator coverage also passes. Both ASan/UBSan host runs (normal and
deterministic hashing), both StoreKit regression runs and the focused guest pass.
The guest uses 4096 MiB and four CPUs, reports child wait status 0 and
`VINIX iOS FEEDBACK: PASS`; its state is
`feedback-guest/feedback-173540326708` in the focused bundle below.

The host driver now selects Catalyst for the feedback fixture. The standalone
`feedback` VM mode builds its fixture and initializer before launching. All
implementation, inspection and tooling sources are V; generated evidence stays
outside Git.

Fortnite gets past the capability query and now stops at:

```text
V panic: iOS: unimplemented Objective-C method UIScreen nativeBounds
```

The preceding [queued notification checkpoint](queued-notification-checkpoint-20261104.md)
remains qualified. The next change needs UIScreen's native pixel rectangle and
its relationship to bounds, scale, orientation and the guest display geometry.
The existing runtime already returns 1 for scale and nativeScale.

All 46 game-probe fixtures pass (45 reused plus freshly rebuilt StoreKit).
Original cooked content is retained and advertising remains skipped. The probe
uses 8192 MiB, one CPU, a 2 GiB application budget and a 60-second desktop window.
The peer records 10 builds, nine polls, one node, zero images, closed=false,
supervisor_kill=false and wait=256. All six budget event counters are zero.
The final charge of 702990 bytes is after exit, not peak footprint. Application
exit is 1 and capture exit is 0.

Progress remains four of eight observed gates: loading/binding, +load,
initializers and application entry. No rendered game frame, menu, login or
playable match is verified. This fraction is not an engineering completion
percentage or time estimate.

The unchanged saved auditor passes inspect, seal, independent check and all 339
corruption controls. Supplemental StoreKit media and guest-result checks pass.
Both complete bundles are retained expanded on persistent storage with external
typed integrity receipts covering every file's bytes, path, type and permissions.
No complete evidence was retired and no historical checker was weakened.

Artifacts under `/Users/alex/Library/Caches/vinix-ios/`:

| Artifact | Location | SHA-256 |
| --- | --- | --- |
| Focused validation | `device-feedback-validation-20261104-r1/` | Receipt below |
| Validation receipt | `device-feedback-validation-20261104-r1.inventory.json` | `2f873cb84ce87af7fe7b5c0feea8961230fbb474f8810e82d98b00c962c35cd5` |
| Validation source | `device-feedback-validation-20261104-r1/source.tar` | `139ba35a70a5b6ece1c6a7d8a83067fef40c5f8a6285f424b56cfe05f7a7f056` |
| Complete capture | `device-feedback-probe-20261104-r1/` | Manifest below |
| Capture manifest | `device-feedback-probe-20261104-r1/manifest.sha256` | `11f10d9c251aebdcb750b715fae3a93601cdf572163235db57cd9039283c9fd3` |
| Capture receipt | `device-feedback-probe-20261104-r1.inventory.json` | `5e997cb7235fb4c95eee5b128d53dfd2ffd7643f15943810e7aa8203ebb8e4c8` |
| Capture source | `device-feedback-probe-20261104-r1/source.tar` | `52eb3b75f85a672d5fb7d8d9ca827b251392ff9d830e5a3cec3c40e9e08b4ebd` |
| Runtime | `device-feedback-probe-20261104-r1/run-ios-gles` | `c73c0d334f748f03241ba47dc10fcd9bcd29a2b85c4a78cfe3e12c3bef746b2b` |
| Serial log | `device-feedback-probe-20261104-r1/probe-no-ads-132916/serial.log` | `80603a1fb150788a5887dc73a6fe2d61878c9468a575008a8877f38c800362a7` |

The focused source pins the implementation commit above; the capture pins
`1ce0e8656aa7647b76789185b51d93dfd525dede`, with identical `compat/ios` and
`tests/ios` sources. Builds use frozen V `c6bb06f` and the dictionary checkpoint's
existing kernel/media, with parent manifest SHA-256
`c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb`.
The unchanged game executable SHA-256 is
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
The focused bundle's `diagnostics/` retains the call-site hint, disassembly,
native oracle and decoder self-test results. Concurrent kernel/Linux/Android
workspace changes are outside this qualification.

Reproduce using the frozen-toolchain drivers `tests/ios/notification-checks.v`
with `feedback-host`, `tests/ios/notification-vm.v` with `feedback`, and StoreKit host mode,
each with a fresh external output directory. VM mode requires
`VINIX_IOS_CHECK_NAME=notification-center-checks`; this run sets
`VINIX_IOS_KERNEL` to the qualified dictionary checkpoint kernel. The game uses
`tests/ios/storekit-operation-probe.v` with `--queue-clone`. Preserve the complete
capture at its recorded path for the saved auditor. Verify external receipts
with `tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT`; integrity
verification does not itself qualify game rendering.
