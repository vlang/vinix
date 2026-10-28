# Application restrictions compatibility, 2026-10-28

Commit `2d246cd78efdf511d968a889992186aa362dbe0e` supplies the missing
`UserManager.getApplicationRestrictions(String): Bundle` method found by the
[Maps account-pump run](maps-account-pump-runtime-2026-10-28.md). Every query
constructs a fresh, non-null empty `Bundle`, so a caller's mutation cannot
affect another query. The single-user guest has no application restrictions
policy backend. This implements the unmanaged, no-saved-restrictions case;
managed policy storage and enforcement remain absent.

[Android 10's UserManager contract](https://android.googlesource.com/platform/frameworks/base/+/android10-release/core/java/android/os/UserManager.java)
specifies an empty bundle when no restrictions are saved. The V provider is
[framework_application_restrictions.v](../native-android-tools/androidtools/framework_application_restrictions.v),
source SHA-256
`6ab292b53310c9cbd4451c96490f707867f997fcc687a4fd2f716583d32448b4`.
It accepts the exact six-method baseline `UserManager`, appends one method and
rejects already transformed or structurally unexpected classes.

Artifact paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The producer output is
`combined-account-webview-application-restrictions-framework-2026-10-28-r1`,
with `sha256.json` SHA-256
`8907c1f11d8886b47358b458a8026d8351c6feac44d78346d6d426208b8ffe15`.
Its `build.json` pins source revision, exact compiler/tools and retained source
closures. The baseline is
`combined-account-webview-onboarding-framework-2026-10-27-r1`, inventory
`bfd56090052ec6612179741c5ad88ecfe7fad83027a38cc5949c13892abd1c42`.
The successor preserves all 2,104 classes, fields and existing methods; the
only change is the new `UserManager` method. Output identities are:

- `api-impl.jar`: `d4e8678bf5deda99358defd912e64e4fcba92fec4ad3b87b39fc9f7e9f6ebf32`
- `classes.dex`: `45c25a081702f299ae3f8a883347d624cae6ab4bda3b5f2538be89421cdf32ab`

The retained host `builder` and `checker` are under
`application-restrictions-host-build-2026-10-28-r1`. Their compile guards,
the checker, builder self-test and full framework producer all passed with
zero child/guard exits and complete cleanup. The
[checker](../native-android-tools/check-application-restrictions.v) verifies
the exact new method, preservation of the six original methods, real Bundle
constructor/query APIs and rejection of nine invalid inputs, then assembles
the changed class to DEX. The producer additionally checks the complete
class/JAR delta and DEX roundtrip. These are host assembly checks; ART and
runtime Bundle isolation have not been exercised by this evidence.

Receipts and logs are adjacent
`application-restrictions-{host-compile-builder,compile-checker,check,builder-self-test,framework-build}.{json,log}`.
The full producer took 65.055 seconds, peaked at 501,465,088 bytes sampled
process-tree RSS (490,389,504 bytes from `/usr/bin/time`) and used zero swaps.
Its limits were 600 MiB RSS, 900 seconds, 1 GiB disk reserve, 700 MiB growth
and 4 MiB command output. Host checks peaked below 556 MB sampled RSS.
ARM validation, Google authentication and usable map tiles remain pending.
