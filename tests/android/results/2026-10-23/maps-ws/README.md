# Google Maps attempts218–223

Attempt218 still shows the “Make it your map” onboarding screen after Skip. The
interaction waits for native WS readiness, captures the initial screen, invokes
Skip at `(556,134)` with `--settle10`, then captures again after another 15
seconds. The helper delays 10 seconds before mouse-down, 10 seconds with the
button held, and 10 seconds after mouse-up: these attempts use a long-held
button, not a short click followed by a 10-second wait. All three screenshots
retain onboarding. The harness reports
`startup_failed`; map display and search have not passed. The pending Future
was not inspected in this run.

This attempt used native216, launcher200 and the first observer217 framework
(`b544bd1b…`). It predates the subsequent draw-listener merge in
framework217-observer2 (`acd7c4ca…`), whose separate synthetic regression is
recorded in [observer-verify](../observer-verify/README.md).

[Results](attempt218-results.json) retain the result row with only verbose
metadata `badging` strings omitted. The compressed serial, initial/Skip/later
and final screenshots, configuration, harness and interaction logs, build and
diagnostic sources are retained. [Runtime identities](attempt218-runtime-identities.json)
verify the actual staged native library, framework and launcher against their
retained inputs, plus the Maps and companion APK identities. The native218
directory was later reused; the old staged library matches `libnative216.so`.

Kernel and boot-base identities are inherited from the exact earlier receipts
named in the runtime identity record. No pre-run attempt218 boot image/kernel
hash was recorded. The mutable shared boot image and efivars were not rehashed
as proof of this run's inputs. `retain218.v` and `attempt218-retention.log`
record the retention checks. These artifacts establish a failed Maps attempt.

Attempt219 uses the full observer fix and a native Future/queue diagnostic.
Its [later screenshot](attempt219-google-maps-skip-later.png) still shows
onboarding. The Future probe failed to resolve `MapsActivity`, so it established
no Future state. Three bounded queue snapshots contain no synchronization
barriers; they do not prove that no barriers existed between samples. The
operator intentionally quit QEMU through QMP after sample3 and the interaction
screenshots, before the harness could capture its final screenshot.

[Attempt219 results](attempt219-results.json) and [identities](attempt219-runtime-identities.json)
retain this failure and the directly measured original staged native219 library.
The native219 library, diagnostic source and source hash list were overwritten
for the corrected next attempt. They are not claimed as original219 source
evidence. The APK, launcher, harness and inherited kernel/base identities are
shared with attempt218. Attempt219 also fails to demonstrate a working map.

Attempt220 corrects the Future probe and identifies a concrete framework gap:
the completed transition Future throws `NoSuchMethodError` for
`View.getContentCaptureSession()` while attaching the app's next view. The
first two samples return from `Future.get()`; the third exposes that exception.
All [screenshots](attempt220-google-maps-skip-second.png), including the final
harness capture, still show onboarding. Map display and search remain unverified.
The three bounded queue samples contain no observed synchronization barriers.

The operator reports an additional successful click invocation around 13:27
local time. Its empty tool output was not saved as a separate persistent log;
`skip-second.png` is retained. These artifacts do not synchronize that click
with the third sample, so they do not establish which click caused the failed
transition or that any click failed to reach the app.

[Attempt220 results](attempt220-results.json) and
[identities](attempt220-runtime-identities.json) retain the directly measured
staged native220 library and full observer2 framework. The compressed native
source archive is a JSON map from filenames to exact V source text: all 80
files were verified against the retained `native220-sources.json`, and every
hash was checked again after decoding the archive. Shared APK/launcher and
inherited kernel/base identity limits remain the same as above. The missing
capture API is a diagnosed blocker; this attempt does not demonstrate its fix.

Attempt221 uses the content-capture API and narrowed application initialization
lock framework (`b68a2228…`) with native221 (`4f844e7d…`). Input advances beyond
onboarding into Compose semantics, where the main thread throws
`NoClassDefFoundError: android.view.autofill.AutofillValue` and the APK exits
with code 10. The [initial screenshot](attempt221-google-maps-initial.png) shows
onboarding; [Skip](attempt221-google-maps-skip.png) and final screenshots show
“The Android APK has exited.” The later screenshot was not captured because
QEMU closed. The interaction log retains that failure. The same long-held
button timing applies to attempt221; map display and search remain unverified.

[Attempt221 results](attempt221-results.json) and
[runtime receipt](attempt221-runtime-identities.json) retain the serial, three
screenshots and complete result fields apart from verbose badging strings.
[Input identities](attempt221-input-identities.json) verify actual staged
native/framework/launcher hashes. All 80 native V sources and all available
framework sources were archived against their manifests. The exact built
`framework_application.v` source text was unavailable after concurrent edits;
its declared build hash is retained, and that file is excluded from the source
archive. Four relevant classes were freshly disassembled from the actual built
JAR, including `ATLLoadedApp` and the null content-capture getter. The retained
Maps methods show the immediate missing call is
`AutofillValue.forToggle(boolean)`; its wrapper also reads toggle/text values.
Kernel/base identity remains inherited under the same limits as earlier runs.

Attempt222 adds `AutofillValue` in framework `fa6bd916…`, using the same native221.
The input now uses `--settle0.15` for each input phase, followed by an explicit
10-second wait. The [initial](attempt222-google-maps-initial.png) and
[Skip](attempt222-google-maps-skip.png) captures still show onboarding. The
main thread then fails with `NoSuchMethodError` for
`AutofillManager.notifyViewVisibilityChanged(View,int,boolean)` and the APK
exits with code 10. The [final screenshot](attempt222-google-maps-application.png)
shows the exited APK; QEMU closes before the later capture. Map display and
search remain unverified.

[Attempt222 results](attempt222-results.json) and
[runtime receipt](attempt222-runtime-identities.json) preserve that failure.
The [input receipt](attempt222-input-identities.json) verifies the staged
framework, native library and launcher identities. All 102 framework source
files match the build manifest and are archived as exact V source text; the
actual JAR's `AutofillValue` disassembly is also retained. Native221 sources
reuse the verified attempt221 archive. Kernel/base identity remains inherited.

Attempt223 adds the unavailable-autofill notification methods in framework
`ab40d4f8…`, again with native221. After Skip, rendering fails with
`UnsupportedOperationException: Native WS bitmap storage requires ARGB_8888`
in `Bitmap.getSnapshot()`, called while constructing a `Canvas`. The APK exits
with code 1. Its [initial screenshot](attempt223-google-maps-initial.png) shows
onboarding; [Skip](attempt223-google-maps-skip.png) and final captures show the
exited APK. The later capture again fails after QEMU closes. Input uses the
same short-click timing as attempt222. Map display and search remain unverified.

[Attempt223 results](attempt223-results.json) and
[runtime receipt](attempt223-runtime-identities.json) retain the failure.
The [input receipt](attempt223-input-identities.json) verifies the staged
runtime hashes and all 102 exact framework sources. Fresh disassembly from the
actual JAR includes both `AutofillManager` and `AutofillValue`. Native sources
and inherited kernel/base identity limits remain as described above.
