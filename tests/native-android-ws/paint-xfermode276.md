# Center-sampled rectangle bounds (276)

The unchanged layered JNI fixture exposed a second rendering bug after fix
274's direct DST_IN checks passed. Its 8×8 oval should cover pixel `(5,0)`,
but the composite retained the background there. `drawOval(RectF, Paint)`
delegates to the rounded rectangle renderer, whose first scanline spans
`[2.063508, 5.936492)`. The axis-aligned rectangle fast path truncated that
to `[2,5)`, dropping pixel 5 even though its center is inside the oval. Other
scanlines also gained pixels outside the circle.

The fast path now selects the integer range
`[ceil(left - 0.5), ceil(right - 0.5))`, and likewise for the vertical edges.
This matches its existing inverse-affine path's half-open pixel-center rule.
Integer-aligned rectangles retain their pixels. Transformed edges are clamped
to the clip before integer conversion; unordered or collapsed transformed
bounds produce no writes. The inverse-affine branch and object lifetimes are
unchanged.

Source baseline: DST_IN commit `b50aab72d`. This report accompanies the subsequent
rectangle correction. The fixture source and expected oval pixels are unchanged
(`paint-xfermode-fixture.v` SHA-256
`3a156ee99b4371ab7f85555eaa2d43edfac1064a1ea4c9f6e6f2d696cd49ca0d`).

The maintained host test extracts the production rectangle and rounded rectangle
functions. Frozen 274 numerically fails a fractional rectangle at `(0,1)`;
the corrected source passes normally and under AddressSanitizer. All eight
markers pass, covering the existing DST_IN cases plus fractional/half-pixel
edges, negative coordinates and scale, shear, translation and scale, large
clipped coordinates, finite transform overflow, NaN and collapsed bounds. The
oval regression verifies every mask, isolated layer and final composite pixel
for two draws using the original JNI fixture's circle oracle. Independent
reviews cleared the math, clip bounds and unchanged lifetimes.

Host receipts are retained in ignored local result directories pending their
copy into the fresh external 276 qualification bundle:

| Receipt | SHA-256 |
| --- | --- |
| `results/xfermode276-rect-fixed/evidence-sha256.txt` | `5e5d272013c48f1a6cb3245d2fa092d0964bbb3870bbd56c81ee24188358750b` |
| `results/xfermode276-rect-fixed-asan/evidence-sha256.txt` | `545302c9b5e110dccdbb83b48437666d8cf96b41c9b2ea83306e25e13d14f24d` |
| `results/xfermode276-rect-old/run.log` | `91fb194d6ef4d065d5a3efafe3efdf21dc0305dd5bd07da557f410663e3e27dc` |

Fresh native-only attempt 276 will reuse 274's framework JAR and byte-identical
signed fixture APK, with the preserved failing 274 runtime as its baseline.
Its guest result and complete external evidence seal are pending at this
source checkpoint; no 276 JNI runtime PASS is claimed here.

The manual Maps search/route flow in [the 274 report](paint-xfermode274.md)
used the earlier 274 runtime in attempt 275. It was not rerun with this rectangle
correction; those manual observations are separate from the 276 fixture checks.
