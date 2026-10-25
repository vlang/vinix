# Maps media exception callers349

Maps347 completed the ten-minute route/preview scenario, but its embedded-video
path rejected `hwv` because superclass `hqa` failed ART verification. The retained
serial log reports `hqa.V(long,long)` at DEX PC `0x4CF`: `copy1 v5<-v3
type=Undefined cat=1` (lines 21202 and 37631). This is a separate video linkage
failure; the evidence does not establish video playback.

The original Maps APK SHA256 is
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
The sourceproof extracts seven unchanged classes from its `classes4.dex`, with
code offsets. In retained `selected/hqa.smali`:

| Location | Evidence |
| --- | --- |
| 2728 | `V(JJ)V`, 35 registers. |
| 6115–6118 | PC `0x4CF` copies `v3` into `v5`. |
| 6131–6139 | Inner handler `0x4D3` executes `move-exception`, then initializes `v3` at `0x4D4`. Its catch type is `MediaCodec$CryptoException`. |
| 6067–6404 | Handler `0x4D3` itself lies inside outer try `[0x4C2,0x534)`, with an `IllegalStateException` handler at `0x784`. |
| 7965–7970 | Handler `0x784` jumps directly to `0x4CF`, without initializing `v3`. |
| 8292; 16694–16713 | Actual calls to `CryptoException.getErrorCode()` and `CodecException.getDiagnosticInfo()`, with `instance-of`/`check-cast` to the latter. |

The pinned ART source explains the extra verifier edge: `MOVE_EXCEPTION` resolves
the caught type (`method_verifier.cc:2130–2143,3772–3791`). An unresolved exception
calls `Fail(VERIFY_ERROR_NO_CLASS)`. In ART's runtime verification branch, this
marks the instruction as throwing and saves its input registers (5444–5478).
The verifier then merges those saved registers into every enclosing handler
(3485–3488,3581–3618). At inner PC `0x4D3`,
this precedes initialization of `v3`; the outer handler returns to `0x4CF` with
that register undefined. Assertions pin the exact extracted instructions and
the source mechanism.

Qualified framework346 JAR SHA256
`b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840`
contains `MediaCodec` but lacks `MediaCodec$CryptoException`,
`MediaCodec$CodecException`, and `MediaCryptoException`. The bundle retains the
JAR, its original complete manifest, and a recorded class-list command. This
supports adding the missing framework exceptions; the bounded runtime test is
to load the original APK's `hqa` and `hwv` using `DexClassLoader` against each
framework. `hqa`, `hgm` and their retained interfaces have no static initializer;
`hwv`'s initializer only fills a static integer array, so class initialization
does not construct a player. The separate contract349 report defines the APIs.

`maps-video-verifier-sourceproof.v` captures the exact extraction argv, selected
classes, original APK reference/manifest, full serial log, official ART source
and HTTPS provenance, pinned tools, V input closure and generated C. It requires
the entire manifest for readback. The 304MB APK stays at its original canonical
path under `maps335-2026-10-25/prelaunch/inputs/build/android-maps/GoogleMaps.apk`;
its bytes are checked before and after extraction. Existing maps348 trace
artifacts and the first callers349 capture remain unchanged.

Final bundle (26MiB, 660 files):
`/Users/alex/.local/state/vinix/android/media-codec-exceptions349-callers-final-2026-10-25`.
Its `sha256.json` SHA256 is
`6661b5348dbd788a7da8f01554c7f27a551e8685225e513284f4de9856e73355`.
Complete own readback passed; receipt
`media-codec-exceptions349-callers-final-own-readback-2026-10-25.json` is beside
the bundle. Independent root readback also passed all 660 original files;
adjacent receipt:
`media-codec-exceptions349-callers-final-root-readback-2026-10-25.json`.
The recorded capture checkout is
`084488d78a2c751997762e26088dcaa775323d45`; the exact author source is retained
with its compilation inputs. Independent source review confirmed the DEX/ART
mechanism and initializer scope. No APK was modified and no video was played by
this proof.

Official pinned [ART verifier source](https://gitlab.com/android_translation_layer/art_standalone/-/blob/e78bf68917bcaaf58fef3960cd88793b3b7f39cc/art/runtime/verifier/method_verifier.cc),
revision `e78bf68917bcaaf58fef3960cd88793b3b7f39cc`, matches
`build-support/android/build-art.sh`. Retained source SHA256:
`b14bd1b86eadbab6f3ed9f161ff24b98ffa9a3214ec177d85d369989a20ca13a`.
