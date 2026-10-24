# Paint bitmap DST_IN masks (274)

Maps' suggestion icon container `pev` draws its children into a hardware layer,
then draws a cached black oval bitmap with `PorterDuffXfermode(DST_IN)`.
`myf` case 7 supplies that mask. Ignoring the transfer mode painted the mask
over the icon as a solid black disk. The existing View layer implementation
already supplies the required transparent ARGB offscreen target.

The bitmap compositor now uses source alpha, including Paint alpha, to multiply
destination alpha for DST_IN. Straight RGB survives while alpha is nonzero;
fully cleared pixels become transparent black. ALPHA_8 targets and opaque
desktop targets retain their respective storage conventions. Existing affine,
device, path and quadrilateral clips apply, and pixels outside the bitmap's
destination rectangle remain unchanged. Paint's Java and native transfer mode
state stays synchronized through copy, set, reset and null/default setters.

Source baseline: `e4999db88` (path fill-rule fix 272); DST_IN source commit:
`b50aab72d`. Frozen build inputs and retained evidence
are under `/Users/alex/.local/state/vinix/android/compound274-2026-10-24`.

Validation completed:

- The maintained `paint-xfermode-host.v` runner passed normally and under
  AddressSanitizer against the frozen production functions. Its six markers
  cover the 125 ARGB alpha combinations, ARGB/ALPHA_8 source and target pairs,
  opaque surfaces, transformed and intersected clips, source-over behavior,
  overlapping source snapshots and native Paint cloning. The existing path
  regression also passed against the combined 274 inputs.
- The AArch64 native library and framework JAR built successfully. Independent
  review verified the generated `(JI)V` setter and its exported JNI symbol,
  Java copy/reset behavior, and native pixel/lifetime handling.
- The maintained JNI fixture assembled and signed. It covers Java identity,
  copied/self-set/reset Paint, explicit SRC_OVER restoration, bitmap formats,
  affine clipping, and the Maps child/layer/oval-mask flow with repeated draws.
  The subsequent paired execution confirmed the 272 baseline's expected direct
  pixel failure. Fixed 274 passed the direct bitmap checks, then failed the
  layered oval at pixel 5: `0xffeecc88` instead of `0xff336699`. This exposed a
  separate rectangle edge rounding bug; see [the 276 follow-up](paint-xfermode276.md).
  The failed 274 evidence is retained without alteration. No complete synthetic
  JNI fixture runtime PASS is claimed for 274.
- Actual Maps attempt 275 used the built 274 runtime. Manual observations
  showed nine outline suggestion pins in place of the black disks, followed
  by Skip, Paris search, Eiffel Tower origin selection, route overview,
  Preview and Next. The route map populated after waiting; the app and QEMU
  remained alive through the natural 420-second observation window.

Maps 275's raw classifier nevertheless reports `startup_failed`, with
`functional_passed: null`, because it retains four gRPC ClassNotFoundException
markers for `JndiResourceResolverFactory` and `ContextStorageOverride` and their
causes. Manual UI observations do not override that classification. The
lower-right location/control rendering remains incomplete; GPS, sign-in,
voice and long-duration use were not validated. The retained Maps evidence,
seals and manual observations are recorded in [the Maps 275 report](maps275.md).

The complete failed 274 archive is sealed by `failed-attempt-sha256.json`.
Its integrity check passed with status `UNQUALIFIED`; the original positive
qualification checker still rejects the layered assertion failure, retained
in `qualification-rejected.log`. The later 276 fixture success does not change
274's failed result.

Retained SHA-256 pins:

| Artifact | SHA-256 |
| --- | --- |
| `failed-attempt-sha256.json` | `78d8d38f8e855e42cceed3054944641a622d5ceecda1cb5e826953d6bf5b9e22` |
| Framework JAR | `1a026975748c693f11c09c7fc080f8b72c20c0638c01996f226698cc740f92f6` |
| Native library | `27f1ec2604f93f55d8b3557fb7e34dc754daedde854a6041939503cb72cf12a7` |
| Paired fixture APK | `214421dcae1874873e58023080e7746e7e385034f71e0af9a5e56247b1b2f3ed` |
| Fixture source | `3a156ee99b4371ab7f85555eaa2d43edfac1064a1ea4c9f6e6f2d696cd49ca0d` |
| `prelaunch/host-normal/evidence-sha256.txt` | `ab93bba41ea4c6568bedbe3aebce78b02c44807847ede84f2ca77bfa90191fe8` |
| `prelaunch/host-asan/evidence-sha256.txt` | `ccb8adbbec758c6d6cb8ecf70b98190f96e901f3d48e0c68009a3424ca5de268` |
| `prelaunch/host-path/evidence-sha256.txt` | `00e6c500455c84cc416e4c308f15187bb354a00af9ccae6cef48b2b3c9161c2c` |

The host regression can be rerun with the repository's V compiler:

```sh
/Users/alex/code/v/v_old run tests/native-android-ws/paint-xfermode-host.v out=/external/fresh-host-normal
/Users/alex/code/v/v_old run tests/native-android-ws/paint-xfermode-host.v out=/external/fresh-host-asan asan=true
```
