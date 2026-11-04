# UIView clearing-policy checkpoint — 2026-11-04

`e0981b55af69a0db442cfb824ff343908cc011c4` implements UIView's
clearsContextBeforeDrawing getter/setter, per-view configuration and inherited
method metadata. The default is YES. An inverse flag in the existing side
record avoids introducing owned objects or writing private native UIKit ivars.
The property is scoped to UIView instances and their subclasses. The preceding
[timeout checkpoint](session-timeout-checkpoint-20261104.md) remains fully audited.

Native Catalyst tests compare UIView and a custom subclass, including independent
state, hierarchy changes, BOOL argument width, respondsToSelector:, signatures
and typed direct IMP calls. UIWindow's inherited method identities are checked
without creating a native window, which requires an application scene. Vinix
tests exercise UIView, UIWindow and a subclass across two drained runtimes.
Both ASan/UBSan runs and the StoreKit regression runs pass. A new standalone
view-tag guest mode runs the updated fixture: 4096 MiB, four CPUs, child wait
status 0, both view-tag and view-clear markers PASS, with no live objects left.

This implements the configuration API. Generic drawRect: scheduling remains
unsupported, and no drawing or Metal backend is added. The native policy clears
the bounds before drawing when enabled, as described in
[Apple's property documentation](https://developer.apple.com/documentation/uikit/uiview/clearscontextbeforedrawing).
Setting the policy is not itself a drawing operation.

The fresh Fortnite launch gets past setClearsContextBeforeDrawing: and stops at:

```text
V panic: iOS: unimplemented Objective-C method NSOperationQueue mainQueue
```

All 46 game-probe fixtures pass (45 reused plus a fresh StoreKit fixture).
Original cooked content is retained and advertising remains skipped. The probe
uses an 8192 MiB guest, one CPU, a 2 GiB application budget and a 60-second
desktop window; the game exits before controlled closure. The peer records
24 builds, 23 polls, one node, zero images, closed=false, supervisor_kill=false
and wait=256. All six budget event counters are zero. The final budget charge
of 686606 bytes is after exit, not peak footprint. Application exit is 1 and
capture exit is 0. All 339 saved-auditor corruption controls pass.
The unchanged saved auditor passes seal and independent check, including full
resource and guest-binary comparisons. The supplemental StoreKit media check
also passes. The complete capture passes independent verification against its
typed integrity receipt.

Progress remains four of eight observed gates: loading/binding, +load,
initializers and application entry. No frame, menu, login or playable match is
verified; that count is not an estimate of engineering completion. Metal device
creation still returns nil. The next observed startup work is the main operation
queue. These checks use the pinned dictionary-checkpoint kernel, not concurrent
kernel changes.

```text
CACHE: /Users/alex/Library/Caches/vinix-ios
WORK: CACHE/audio-category-20261027-work
Source: e0981b55af69a0db442cfb824ff343908cc011c4
Focused bundle: CACHE/view-clear-validation-20261104-r3
Focused receipt: CACHE/view-clear-validation-20261104-r3.inventory.json
Focused receipt SHA-256: 06494651feaa944fe48962f0129106c3243444abfa51a6ab08590262a01a2587
Source tar SHA-256: ae1045d6cc676ce42111574b59ecc6b4edd3c3035ddafa07867fb609e51c9d20
Capture: CACHE/view-clear-probe-20261104-r1
VM state: probe-no-ads-132916
Manifest SHA-256: 7b2b3e452af80044ccd240e4b23ee50ec1fafcc33263aedd55a23ee00386bbd5
Capture receipt: CACHE/view-clear-probe-20261104-r1.inventory.json
Capture receipt SHA-256: 40a6fc6bfbc80a8b0238896a9a21c7da8addcb5de07392a9a907d346f8330184
Runtime SHA-256: 75595cd47d040deb4475cf8f1df2631cd64131fff1e3b47a2604780726b6cd16
Serial SHA-256: 613de182bffdad5e8830ba887e92946fff5eb409108da077c9e6ede96708349e
Prior: CACHE/dictionary-variadic-20261028
Prior manifest SHA-256: c1163dfbb2bf9b0f096eba6123246028b00a43902ebd9963b115909b999e3dbb
```

The focused bundle passed independent verification against its complete typed
inventory. Both bundles remain expanded in persistent storage outside Git.
No historical checker was relaxed, and complete evidence is still required.
