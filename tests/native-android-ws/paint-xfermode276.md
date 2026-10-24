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

Source baseline: DST_IN commit `b50aab72d`; rectangle correction:
`9107f214d`. The fixture source and expected oval pixels are unchanged
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

Host receipts are retained in the external 276 bundle under `host/`:

| Receipt | SHA-256 |
| --- | --- |
| `host/fixed/evidence-sha256.txt` | `5e5d272013c48f1a6cb3245d2fa092d0964bbb3870bbd56c81ee24188358750b` |
| `host/fixed-asan/evidence-sha256.txt` | `545302c9b5e110dccdbb83b48437666d8cf96b41c9b2ea83306e25e13d14f24d` |
| `host/old/run.log` | `91fb194d6ef4d065d5a3efafe3efdf21dc0305dd5bd07da557f410663e3e27dc` |

Native-only attempt 276 reused 274's framework JAR and byte-identical signed
fixture APK. Its red reference is the preserved actual 274 execution, which
passed direct DST_IN checks and failed the layered oval; it was not rerun.
With the corrected native library, the unchanged fixture emitted all four
markers: `BOOTSTRAP-PAINT-DST-IN-PASS`, `BOOTSTRAP-PAINT-DST-IN-LAYER-PASS`,
`BOOTSTRAP-PAINT-XFERMODE-PASS` and `BOOTSTRAP-READY`. The suite exited zero
after the natural 30-second observation, with `backend_ready: true`,
`process_exited: false` and `qemu_alive_before_capture: true`.

The raw generic Maps classifier remains `startup_failed`, with
`functional_passed: null`. Its only two failure markers are the diagnostic
lookup of Maps field `bB:Lnge;` on fixture class `org.vinix.bootstrap.Main`
and the caused `ClassNotFoundException: nge`. The fixture's pixel and Paint-state
checks passed; this does not override or rewrite the raw classification.

Retained artifacts are under
`/Users/alex/.local/state/vinix/android/compound276-2026-10-24`.
The strict semantic seal and independent complete inventory check passed
(exit 0); a wrong manifest pin was rejected (exit 1). The initial checker and
its retained-path lookup rejection are preserved in `checker-initial/`; the
correction retains all recorded input hashes and qualification gates. Maintained
276 tooling is committed in `d499c665c`. Final check and wrong-pin receipts are
retained alongside the bundle as `compound276-check.log` and
`compound276-wrong-pin.log`.

| Artifact | SHA-256 |
| --- | --- |
| Complete bundle `sha256.json` | `37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4` |
| Sibling `compound276-check.log` | `0d7a339d0f4009868272035d46e7004c15b21e439b54e6369a24d5e4f010ef83` |
| Sibling `compound276-wrong-pin.log` | `754636cba078b79a0ab5952f2c0e1a6266c91952880fe0474dee33106a5a8991` |
| Framework JAR (unchanged from 274) | `1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6` |
| Native library | `5fe27a87c179b97121c368f417936ceebb75752c4a4204b937312ee28da531ca` |
| Signed fixture APK (unchanged from 274) | `214421dcae1874873e58023080e7746e7e385034f71e0af9a5e56247b1b2f3ed` |
| `run-fixed/results.json` | `829fbea3f9be487e0e8940b2f395e0de227bc922571185dad7e87fad6d734899` |
| `run-fixed/bootstrap-fixture/serial.log` | `49b93c032616dce5b0ec8479a6fd91ac6ce2a34b3fa2bb333189a3ef4b2b4ac9` |
| `prelaunch-sha256.json` | `5e96164db74ee12dd7910818632117ea7746a9b782bda22731c4d70038a70922` |

To recheck the retained evidence without launching a guest, use the repository
working directory and preserve both complete 274 and 276 bundles at their
recorded paths:

```sh
cd /Users/alex/code/vinix
/Users/alex/.local/state/vinix/android/compound276-2026-10-24/checker/canvas-center-evidence check /Users/alex/.local/state/vinix/android/compound276-2026-10-24 37bfa8ec3449adf8a294e0b1f3ff3cabfa49123c228f308d9919cab7531d5fa4
```

The manual Maps search/route flow in [the 274 report](paint-xfermode274.md)
used the earlier 274 runtime in attempt 275. It was not rerun with this rectangle
correction; those manual observations are separate from the 276 fixture checks.
