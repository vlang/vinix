# VectorDrawable fill rules: Maps location glyph

On 2026-10-24 UTC, a paired ARM/JNI regression reproduced and fixed the
missing blue center in Maps' location control. Production commit
`3b0c3204b433ae7fdbd2bb04b04fed98c5b6c040` parses each vector path's XML
`fillType` and applies it to the transformed rendering path. The shared path
is reset to WINDING before handling clip paths because `Path.reset()` preserves
its fill rule.

The signed Maps APK maps `center_location` (`0x7f08036a`) to `res/m5z.xml`.
That vector draws a blue center followed by a white compound ring whose
same-winding contours require `evenOdd`. Ignoring that attribute fills the
hole white. This differs from `location_not_granted` (`res/TF3.xml`), whose
separate gray contours, slash and dot are intentional. The control is not a
compass.

The same signed regression APK and native library ran against the old274 and
fixed278 framework JARs. The baseline failed with
`Vector fill: even_odd center x=12 y=12 actual=-13408615 expected=0` and exit 1.
The fixed run emitted all four markers:

```
BOOTSTRAP-VECTOR-FILL-RULES-PASS
BOOTSTRAP-VECTOR-FILL-STATE-PASS
BOOTSTRAP-VECTOR-LOCATION-GLYPH-PASS
BOOTSTRAP-READY
```

Compiled XML probes cover even-odd, nonzero/default and opposite winding,
mixed rules, transforms, clip-path state after an even-odd path, repeated
same-size cache draws at 24/48 pixels, ConstantState/newDrawable, mutation, and
the Maps location geometry's blue center, white ring and pale background.
The fixed process remained alive for the full 30-second observation. Backend
readiness and QEMU liveness were recorded. Both raw generic suite classifications
remain `startup_failed`/`functional_passed:null` due to the inherited `nge`
field/class diagnostics; the checker preserves those classifications and separately checks
the exact baseline exception and positive regression markers.

| Input | SHA-256 |
| --- | --- |
| Baseline framework | `1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6` |
| Fixed framework | `a1b839c77a575a40ddab8d6e264e92c9abcc9de54ae6c3dcefcc0e725c938eba` |
| Unchanged qualified276 native | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Signed fixture APK | `33c7f7bd2cb541741aa1b596a0b751a131a1e4f2c56c05bd0d1824e3c0824704` |
| Signed Maps APK | `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2` |
| External prelaunch manifest | `aa10e659faf39ab1a9b4bf01d2dde791f4ab1fbb9eff007d71e8226fce370995` |

Build/freeze/run tooling is commit `06c56ad28`. The complete bundle is
`/Users/alex/.local/state/vinix/android/compound278-2026-10-25`, including actual
framework/fixture/compiler/suite receipts, exact source trees, prelaunch media,
both complete raw runs and postrun media, frozen runner/checker inputs, and the
original Maps resource proof. Historical qualification bundles remain unchanged.
Its final complete manifest is
`43da38520c0e5370007dfb30efe72b6f802bfbd434548c01662dabab392cc735`.

The original prelaunch manifest remains unchanged. Its older file walker
omitted one hidden upstream `compound276-2026-10-24/sha256.json` file from
the inventory, although that file was retained and separately pinned in
`frozen-inputs.json` before launch. The corrected checker requires exactly
that omitted path and its original pin, then checks the complete inventory.
The original runner, first failed seal diagnostic and corrected checker are
retained separately; no original evidence was removed.

The maintained resource-proof helper independently extracted DEX and compiled
XML from the actual signed APK and matched the cached class disassembly. Its
separate bundle is
`/Users/alex/.local/state/vinix/android/vector-fill-maps-sourceproof-maintained-r2-2026-10-25`,
manifest `5ef01e5c323d86ae6b4c7b2ea0bf759e981285822cbdc07fde0fa0802a1add91`.
The original immutable proof retained by the regression has manifest
`4fb9e66f8cbfe302f2cf8140572daac750e512a24029f8941c7202ea5e6d45d2`.

Checker commit `d65c22c2c` passed the complete retained-bundle check and seal.
An all-zero manifest pin was rejected with exit 1. The external validation-log
manifest is
`/Users/alex/.local/state/vinix/android/compound278-validation-logs-sha256.json`,
SHA-256 `7d461b2b7689054f70348a52304b642ddbda6844ac32bc1808ce85bd60b78890`.
It pins the seal, successful complete check and wrong-pin rejection logs.

Recheck the retained bundle with its retained checker:

```sh
/Users/alex/.local/state/vinix/android/compound278-2026-10-25/checker/vector-fill-evidence check /Users/alex/.local/state/vinix/android/compound278-2026-10-25 43da38520c0e5370007dfb30efe72b6f802bfbd434548c01662dabab392cc735
```

This qualification covers the regression APK; subsequent real Maps runs must
separately establish the visible location control and application behavior.
