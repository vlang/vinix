# Touch delegates for Google Maps place controls

Maps343 reaches the Paris map, photos and Attractions results with qualified
LocaleSpan342, feature revision `b37f14933`. Opening a place then fails during
layout with
`View.getTouchDelegate()Landroid/view/TouchDelegate;` missing, at
`bgdt.a → ndt.e → ndt.onSizeChanged`. The actual app wraps an existing delegate,
retains it through the getter/setter, and combines real `TouchDelegate(Rect,View)`
instances in a subclass that overrides `onTouchEvent`.

The framework previously had a no-op setter and a constructor-only TouchDelegate.
The repair stores the nullable delegate on each View and dispatches virtually to
it for enabled views before their own clickable handling. Existing touch-listener
ordering and disabled clickable consumption remain intact. TouchDelegate now
captures gestures within its bounds, applies touch slop, forwards centered or
outside coordinates through the target's virtual dispatch method, resets capture
on cancellation, and returns the target's result. The verified primary-source
contract is retained in [the source proof](touch-delegate344-contract.md).

The regression uses one signed APK on actual ART with both frameworks. Its first
new API call is the exact Maps getter, so the old framework must fail with that
specific NoSuchMethodError before any success marker. The fixed run checks
default, identity, replacement, clearing and per-view isolation; virtual subclass
dispatch and decline; enabled/nonclickable and disabled/clickable routing;
consuming and declining touch listeners; ordinary click fallback; expanded bounds
and exclusive edges; slop and outside coordinates; exact integer-half centers for
odd target sizes; preserved raw coordinates and down time; cancellation; and a
target that returns false.

The test exercises the current single-pointer WS input path. Pointer-action
branches follow the verified Android implementation but are not exercised here.
TouchDelegate accessibility metadata is outside this repair. Passing this fixture
does not by itself establish a successful Google Maps replay.

The runner derives the complete frozen compiler, V closure, C inputs and assets
from qualified342. Preparation passed on its first attempt, with the same 638 V
input pins before and after compilation. The complete generated DEX comparison
keeps 2069 classes: only View and TouchDelegate change; the other 2067 classes are
identical after disassembly. The duplicate-application guard rejects a second
application without mutation. The framework JAR is the only guest runtime delta.

Prepared artifacts are retained at
`/Users/alex/.local/state/vinix/android/touch-delegate344-2026-10-25`:

| Artifact | SHA-256 |
| --- | --- |
| Baseline342 framework JAR | `79023bd51618bc54f069fe6fd85c812679a81f6db70268f78bca38053b2d1972` |
| Fixed344 framework JAR | `12c5d03030f5f081415bda5c51e32279e70a17aead822c06925512ed6226ef8f` |
| Same signed four-class fixture APK | `c2e8b112c209d27a25a5cf6847fdcab2b3dbd2966adbe41a64147307c96fc3a1` |
| Executed checked runner | `4f1023d7126dd3df64c070c5c7dad5444ef339b1ef2c9e534015549f0532b319` |
| Executed frozen runner source | `bca436844f638f9abe14fb7c9e319f4c00110c0e723c18901b3ba13fe477367a` |

Both actual ART runs pass their semantic checks. The old framework fails exactly
once at the getter with the expected activity-start wrapper and no success
markers. The fixed framework prints all four success markers and remains alive
through the 35-second observation window, with no failure markers. Its signed APK
pin matches the old run. The old raw serial SHA-256 is
`494b25959f60ef6a2a0aa4d7fda1ea2b2183aed75135133d981f135d70e2c972`;
the fixed raw serial is
`910da9c00c89d8b529f9ec2dcd92d944e03b6e977987079cdeea7913e349e383`.

The final bundle contains 8,542 files, sealed by `sha256.json` with SHA-256
`f900b1506d71bb6d6560a6729031b3965274d5c5a50d3b2cab753c5d110b4501`.
Complete readback passed independently for the runner, root review, and peer
review. Their receipts are retained beside the bundle as
`touch-delegate344-complete-readback-2026-10-25.json`,
`touch-delegate344-root-readback-2026-10-25.json`, and
`touch-delegate344-peer-readback-2026-10-25.json`.
