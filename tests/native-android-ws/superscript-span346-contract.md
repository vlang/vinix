# SuperscriptSpan346 contract evidence

Maps345 reaches a place sheet before `ashh.<clinit>` fails to resolve
`android.text.style.SuperscriptSpan`. The qualified344 framework already provides
`TextPaint.baselineShift` and native `Paint.ascent`. This proof records the
official contract for adding the missing span; ART and Maps results are separate.

The V capture ran on 2026-10-25 from checkout
`3cdf3607706760e422172a05e1fb2ed3510eea65`. Its exact source is retained as
`author.v` (SHA-256
`36102e38ab499dcaf1726f10aa37967cfb3742632cb4c7f274d220ff45f4f239`).
The bundle retains compiler provenance, input closure, generated C, executable,
command receipts, raw HTTP responses and decoded sources.

- Bundle: `/Users/alex/.local/state/vinix/android/superscript-span346-contract-2026-10-25`
- Manifest SHA-256: `d3cbb96a95fc729e1e0d3f6c0f260702c0c914ee64a55619d50425b750363e46`
- Complete readback: **PASS, 642 files**, receipt `/Users/alex/.local/state/vinix/android/superscript-span346-contract-complete-readback-2026-10-25.json`
- Author executable SHA-256: `7ad6aaef1db081e26e07d7fcb6831fa4d9585dac202c62ecee6889432915ba00`

AOSP main resolved through recorded `git ls-remote` to
`1cdfff555f4a21f71ccc978290e2e212e2f8b168`. The immutable primary sources are
[SuperscriptSpan.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/text/style/SuperscriptSpan.java)
(blob `561022352ffd7aff3b46ee0bb3ddd02f4f7d5937`),
[TextPaint.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/text/TextPaint.java)
(blob `73825b13cb6be5a5296025d8c81a95b426915a12`), and
[TextUtils.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/core/java/android/text/TextUtils.java)
(blob `6dc82c40ddc51b25d0cf12fc64f9102fe9c384ca`).

`SuperscriptSpan` extends `MetricAffectingSpan` and implements `ParcelableSpan`.
Both state updates add `(int)(textPaint.ascent()/2)` to the existing integer
baseline shift: floating division precedes truncation toward zero. The public
empty and Parcel constructors retain no state; parcel writes emit no payload and
the Parcel constructor consumes none. The type ID is 14, content flags are zero,
and the current source has the string representation `SuperscriptSpan{}`.

`TextPaint` exposes the integer field and copies it from another TextPaint.
`TextUtils` identifies the span as type 14 and reconstructs it with the Parcel
constructor. Assertions in the V capture check these contracts against the
retained source. This evidence does not establish native baseline rendering,
shaping, or successful application execution.
