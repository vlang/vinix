# Maps343 touch-delegate caller contract

Investigation baseline: `17609fafc5c35f1a264d6063eec3a65269d56786`.
Actual Maps APK SHA256:
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
This is an app dependency analysis, not qualification of Framework344.

Maps343's place-row screen fails during layout with
`NoSuchMethodError: View.getTouchDelegate()Landroid/view/TouchDelegate;` at
`serial.log:15238`, `bgdt.a:7` → `ndt.e:115` → `ndt.onSizeChanged:1` →
`View.setFrame`. The log is under
`/Users/alex/.local/state/vinix/android/maps343-2026-10-25/results/attempt343/google-maps/`.
The failure occurs while installing a delegate, before touch forwarding is
exercised. It does not demonstrate an actual delegated gesture failure.

The selected actual app requires these methods:

| Method | Selected callsite |
| --- | --- |
| `View.getTouchDelegate()TouchDelegate` | `bgdt.smali:124`, `ndt.smali:579` |
| `View.setTouchDelegate(TouchDelegate)V` | `bgdt.smali:190` |
| `TouchDelegate.<init>(Rect,View)V` | `bgdt.smali:26`, `ndt.smali:569` |
| `TouchDelegate.onTouchEvent(MotionEvent)Z` | `bgdt.smali:257` |
| `MotionEvent.obtain(MotionEvent)MotionEvent`, `recycle()V` | `bgdt.smali:249`, `:265` |

`ndt` extends FrameLayout. Its size callback obtains its hit rectangle and,
when either dimension is below its minimum, unions it with a minimum-sized
rectangle positioned by Gravity. It climbs parent Views, offsetting the
rectangle into their coordinates, until an ancestor contains the expanded
area. It constructs `TouchDelegate(expandedRect, this)` and calls `bgdt.a`
with that ancestor, this target and the new delegate. It saves the ancestor's
returned delegate identity. On detach, it removes this target from the saved
wrapper's map (`ndt.smali:801`).

`bgdt` extends TouchDelegate. Its constructor calls the base constructor with
an empty Rect and the ancestor View, retains a previous delegate and creates
a LinkedHashMap of target Views to delegates. Its registration helper reuses
an existing `bgdt` returned by the getter or constructs a wrapper around the
previous delegate; it adds/replaces this target's entry and installs the
wrapper through the setter when needed. Getter identity therefore matters.

`bgdt.onTouchEvent` tries the previous delegate first, then its child delegates
in insertion order, returning on the first true result. Each attempt clones
the input MotionEvent, invokes the delegate's virtual `onTouchEvent`, and
recycles the copy. The wrapper itself overrides the base method: forwarding
must preserve virtual dispatch, and each leaf receives an independent event.

A separate accessibility method exists, but was not in the failure stack.
`bgdt.getTouchDelegateInfo` calls its superclass when its child map is empty.
Otherwise it obtains each leaf's TouchDelegateInfo, asserts one region, reads
`getRegionAt(0)`, and constructs `AccessibilityNodeInfo$TouchDelegateInfo(Map)`.
The selected synthetic outline confirms the direct methods
`TouchDelegate.getTouchDelegateInfo()TouchDelegateInfo`,
`TouchDelegateInfo.getRegionCount()I` and `getRegionAt(I)Region`. This is a
bounded dependency finding, not evidence that accessibility ran in Maps343.

The [recorded selector](maps-attractions-select.v) and its
[retained build/origin](maps-attractions-binding337.md) selected only `bgdt`,
`ndt` and `aac$$ExternalSyntheticApiModelOutline0` into:

`/Users/alex/.local/state/vinix/android/touch-delegate344-caller-actual-selected-2026-10-25`

Manifest SHA256:
`0a798947bb902266920f55aee99f4a0f48e3b1aad8d5b339a8c5b759b0daaa65`.
The unchanged complete checker290 verified the exact 36-file set and every
hash. Sibling receipt:
`touch-delegate344-caller-actual-selected-readback-2026-10-25.json`.
The initial two-class selection remains separately sealed and unchanged.
No framework mutation, guest input or QMP was used in this inspection.
