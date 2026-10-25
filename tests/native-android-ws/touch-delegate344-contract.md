# TouchDelegate344 contract evidence

The qualified342 framework has no `View.getTouchDelegate`, a no-op setter, and a constructor-only `TouchDelegate`. Maps343 reached the missing getter. This report records the official contract used for the focused repair; ART and Maps qualification are separate.

The V capture ran on 2026-10-25 from checkout `3e8a2e5ac4cde0068f05b87c18eedf976ea3483d`. Its exact source is retained as `author.v` (SHA-256 `0a79af9a362bdd88dd80639b6839ad617f72a7162b358d2e485a9bcd027ccbb1`). The bundle retains compiler provenance, input closure, generated C, executable, actual command receipts, raw HTTP responses and decoded sources.

- Bundle: `/Users/alex/.local/state/vinix/android/touch-delegate344-contract-2026-10-25`
- Manifest SHA-256: `f2cb1ae9bf0b75d107b2169606b642cfbebd737a099a455baefdac92420e19ce`
- Complete readback: **PASS, 638 files**, receipt `/Users/alex/.local/state/vinix/android/touch-delegate344-contract-complete-readback-2026-10-25.json`
- Author executable SHA-256: `e7bcb4a7ad5e4ed1aae924b11687e373c61224e160a83b6bb8e8bc24ef9234bd`

AOSP main resolved to `1cdfff555f4a21f71ccc978290e2e212e2f8b168` through recorded `git ls-remote`. The immutable primary sources are [View.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/view/View.java) (blob `d13f0e21bf8059779c9330a5993907ec88c8e781`) and [TouchDelegate.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/view/TouchDelegate.java) (blob `de0f9e5c5cf69d9e9f1f5e2eb05c5dbfa0bfcb77`).

`View` stores the nullable delegate reference directly. Its enabled touch listener can consume the event before `onTouchEvent`. The normal disabled branch returns clickability before delegation; an enabled view offers events to its delegate before its own clickable handling. Thus an enabled nonclickable parent can delegate. Newer AOSP exceptions for disabled clicking are outside this baseline repair.

`TouchDelegate` retains the initial bounds reference and copies/inflates separate slop bounds. DOWN chooses the target; subsequent MOVE, UP and pointer events retain that choice and test slop. CANCEL forwards once and clears the choice. UP does not clear it. Forwarded coordinates become the child's center, or negative twice slop when outside. Dispatch invokes the child's virtual `dispatchTouchEvent` and returns its result; coordinates are not restored. The constructor implicitly rejects null bounds or child through its normal operations.

Independent source review of the new provider found these contracts preserved, including disabled/nonclickable ordering, virtual dispatch, truncation to integer hit coordinates, and UP/CANCEL differences. Accessibility APIs and unrelated input bridge behavior are outside the review scope.

The fixture independently checks identity/replacement/null/per-view storage; enabled nonclickable and disabled routing; listener consumption, virtual overrides and fallback; integer centering, raw coordinates/time, exclusive bounds, slop, cancelled gestures, and the child's false result. Its expected dispatch counts and register limits were reviewed. No source or fixture blocker was found; runtime results remain the responsibility of the separate ART qualification.
