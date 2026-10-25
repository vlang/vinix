# Media exception linkage contract349

Primary AOSP source at pinned revision
`1cdfff555f4a21f71ccc978290e2e212e2f8b168` establishes the focused exception
contract used for Maps' codec error handlers:

| Type | Core contract |
| --- | --- |
| `MediaCodec.CodecException` | Public final static nested `IllegalStateException`. Package-private `(int errorCode, int actionCode, String message)` constructor. `getErrorCode()` preserves the supplied integer; `isTransient()` means action 1 and `isRecoverable()` means action 2. `getDiagnosticInfo()` is `android.media.MediaCodec.error_`, then `neg_` for negative error codes, then `Math.abs(int)`. Integer minimum therefore retains Java's overflow behavior. Constants `ERROR_INSUFFICIENT_RESOURCE=1100`, `ERROR_RECLAIMED=1101`. |
| `MediaCodec.CryptoException` | Public final static nested `RuntimeException`. Public `(int errorCode, String message)` constructor and `getErrorCode()` preserve the supplied message/error. Its nine legacy `ERROR_*` constants have values 1–9 in the order listed below. |
| `MediaCryptoException` | Public final checked `Exception`, with a public `String` constructor preserving the supplied message. |

Crypto constant order: `NO_KEY`, `KEY_EXPIRED`, `RESOURCE_BUSY`,
`INSUFFICIENT_OUTPUT_PROTECTION`, `SESSION_NOT_OPENED`, `UNSUPPORTED_OPERATION`,
`INSUFFICIENT_SECURITY`, `FRAME_TOO_LARGE`, `LOST_STATE`.
`MediaCodec.java` aliases these to `MediaDrm.ErrorCodes`; the retained
`MediaDrm.java` establishes their numeric values.

This is a limited legacy exception repair. Modern AOSP also implements
`MediaDrmThrowable` and adds extended DRM constructors/state accessors on the
crypto exceptions. Those APIs are outside this change. Exception linkage and
caller-supplied error values do not establish codecs, DRM or video playback.
This source proof is separate from ART and Maps runtime qualification.

The V author `media-codec-exceptions-sourceproof.v` fetches full official
sources over HTTPS using the fixed revision, validates their Git blob IDs and
checks the contracts above. Raw sources are retained outside Git. Recorded
compilation preserves the complete V input closure, compiler and CC pins,
generated C, exact command, timestamps and exit 0; before/after source hashes
match. Captured checkout revision is
`d66090a3a9548aa71e6c86157e8e8729cf2779c7`.

Bundle:
`/Users/alex/.local/state/vinix/android/media-codec-exceptions349-contract-2026-10-25`.
Its `sha256.json` SHA256 is
`a10200c681499f1237558292eab4186a6b49117678a4b3262758112ffb3211fa`.
Complete own readback passed all 640 original files; the external receipt is
`media-codec-exceptions349-contract-own-readback-2026-10-25.json` beside the
bundle. Independent root readback also passed all 640 files, with receipt
`media-codec-exceptions349-contract-root-readback-2026-10-25.json` beside the
bundle. The checker requires the complete bundle and does not accept missing
sources or build evidence.

Official sources:
[MediaCodec.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/media/java/android/media/MediaCodec.java),
[MediaCryptoException.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/media/java/android/media/MediaCryptoException.java),
[MediaDrm.java](https://android.googlesource.com/platform/frameworks/base/+/1cdfff555f4a21f71ccc978290e2e212e2f8b168/media/java/android/media/MediaDrm.java).
