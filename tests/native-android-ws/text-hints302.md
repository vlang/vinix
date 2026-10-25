# Maps hints and ripple radius

Android source baseline: `edcaecd7a` (PathOps296). All evidence is retained
outside Git under `/Users/alex/.local/state/vinix/android/`.

Fresh Maps300 reproduced a current-location button crash after onboarding:
`NoSuchMethodError: getRadius()I in Ldvu;`, followed by `System.exit(10)`.
The APK's `dvu` extends `android.graphics.drawable.RippleDrawable`.
The framework had an empty radius setter and no getter. Radius state now
defaults to `RADIUS_AUTO = -1`, remains independent per instance, is readable
through subclasses, and invalidates the drawable callback on every setter call.
This preserves the existing ripple drawing fallback.

Empty search fields also lacked hints. EditText stored native hint text but
never drew it; base TextView discarded hints and returned a constant `HINT`.
Both now retain immutable hint snapshots, preserve null and spans in API state,
and pass a plain rendering copy to WS. Hint setters request layout and
invalidation without changing actual text or notifying TextWatchers.
Rendering selects the hint only while actual text is empty, using hint colors
resolved against drawable state. A null hint color list follows current text
color; an unmatched state resolves to zero. Constructor hint colors honor
TextAppearance and direct attributes. Measurement includes hint width and
multiline height even while text is present. EditText cursor placement uses
actual text width. These contracts follow
[Android 11 TextView](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/core/java/android/widget/TextView.java)
and [RippleDrawable](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-11.0.0_r1/graphics/java/android/graphics/drawable/RippleDrawable.java).

The new V fixture generates smali and signs one APK for both old and new
runtime variants. Its assertions cover API snapshots and spans, resource
dispatch, XML hints, positive and negative bitmap pixels, stateful and null
colors, hint/text geometry and measurement, cursor placement, and inherited
radius state and callback invalidation. The baseline branch recognizes the
specific former hint stubs; the changed branch must pass every marker.
The clean launcher, other runtime files, classifier, APK and initial media
remain identical. Each variant boots an independent media clone.

The first guest comparison exposed a fixture error: EditText always paints
an underline, so requiring its entire bitmap to contain no visible ink was
incorrect. The corrected fixture requires every ARGB pixel of a transparent
hint to equal the same widget's null-hint baseline. Positive opaque-hint
checks remain, and TextView separately requires no visible ink. The failed
comparison is retained as `text-hint302-fixture-2026-10-25`, manifest SHA256
`6ebca2f735a835a2c86403fa39be40e8f8c9acf213f83b01bdb9690dc882563e`;
independent complete readback passed all 598 files. It contains the failure
and no passing changed-runtime receipt.

The frozen builds preserve the qualified296 source inputs except the hint
renderer/JNI changes and two new framework helpers. Actual DEX comparison
changes only TextView, EditText and RippleDrawable. Native JNI exports add
only TextView.native_setHint and TextView.getCurrentTextColor (600 to 602).
The original PathOps sources and launcher remain unchanged. Production and
test-tooling reviews found no remaining blockers after correcting unmatched
hint-color state fallback to zero.

Maps300 failure evidence: `maps300-2026-10-25`, manifest SHA256
`a057de6a1985810275ef2947725f3f7f9e0177b7cc09dd740b39f31c2d6fa36a`.
Independent complete readback passed all 22,646 entries. The failure stack is
at serial lines 8396/8411; exit status 10 is at line 8456.

Framework302: `text-hint302-framework-build-2026-10-25`, manifest SHA256
`746aa9e4a01e3ea63684ef172b00dc2e934c6eb34fd707cb060958a12a2cce1b`;
JAR SHA256 `570b88718c3520aacf7f462f01230e0fd880770ac888a8743e949d2ef970fd44`.

Native302: `text-hint302-native-build-2026-10-25`, manifest SHA256
`ab9a6378dcfc117bf485d4fccf2b8253c907b5dbc9185841c67456b9fe1b0dae`;
library SHA256 `f31fb4916ef7983aabcfb03ad0f21ffb7d84cf7cd433cd6c3568ce75def82f7e`.

Independent complete readback passed all 6,961 framework-build files and
2,406 native-build files. Both builders retain their consumed V closure,
generated sources, commands, compiler and runtime inputs. Native compilation
passed AArch64 `-O2 -Wall -Wextra -Werror` with no `v_fixed_index` references.

Fresh fixture305 uses signed APK SHA256
`64d3dfe6a10f79d44d0ef1b17d953388b572591a0df84bd307dd0b79d37aa3e4`
for both variants. The old runtime recognizes the specific former stubs.
The changed runtime passes API, bitmap, color-state, measurement, cursor and
inherited radius assertions, followed by the final success and ready markers.
Both variants independently confirm that trace environment variables are absent.
The sealed bundle is `text-hint305-fixture-2026-10-25`, manifest SHA256
`c8d333681b80386d16c48faf540c84ff4e464e45c098a4e1ee96d9de92c79b7a`.
Complete readback verifies all 602 files. Both raw suite classifiers report
`window_observed`; the separate semantic receipts establish the assertions.

Fresh Maps304 leaves onboarding and displays the previously missing
"Search here" hint. The current-location click survives the former missing
`getRadius` crash. Paris search returns suggestions and a populated place
card; a manually selected Eiffel Tower origin produces a 15-minute driving
route to Paris and a 1-hour 3-minute walking route. Screenshots were
independently viewed. Opening Route Options then exits Maps with
`NoSuchMethodError: Drawable.getOpticalInsets()Landroid/graphics/Insets;`
from `SwitchCompat.onMeasure` (serial lines 14071–14150). Preview was not
reached, and this run ended before the 600-second observation target.
The outer harness exit code is zero, but the raw classifier correctly
reports `startup_failed` and the APK exit code is one.

Maps304 evidence is `maps304-2026-10-25`, manifest SHA256
`0575e5e50abb3a6d5228e6137bb99c0401c4639a934298e44e9a658f7c1458c2`;
complete typed-manifest readback passed all 22,802 entries. Runtime
comparison changes exactly the framework JAR and native library, preserving
the other 107 regular payload files.

There is still no location provider: selecting "Your location" leaves the
route origin empty. No GPS position was injected. Local street labels are
also absent in the route screenshot; this change does not diagnose that gap.
