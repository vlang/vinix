# Nine-patch dimensions for Maps switches

Source baseline: `f3f3c0e43`. Complete evidence bundles are retained outside Git
under `/Users/alex/.local/state/vinix/android/`.

Maps308 survives its 600-second replay, but Route Options switches are invisible.
The retained Maps `SwitchCompat` code measures its nine-patch thumb and track
using `Drawable.getIntrinsicWidth()` and `getIntrinsicHeight()`. NinePatchDrawable
inherits the base getters returning `-1`, producing empty or inverted drawing
bounds. The native bitmap renderer rejects these bounds.

NinePatchDrawable now reports the dimensions of its retained decoded bitmap,
matching the existing BitmapDrawable raw-pixel behavior. A missing native bitmap
still returns `-1`. The getters borrow the existing handle; they add no ownership
or allocation. Target-density scaling and nine-patch stretch-region rendering
remain outside this change.

Framework309 preserves all 133 sealed306 generators except the registration and
new helper. Actual output DEX comparison requires only NinePatchDrawable to
change, with no added or removed classes. Native309 derives from sealed302 and
adds exactly two static `(J)I` JNI getters. All other generated native code and
existing native sources remain byte-identical. The builders retain consumed
source closures, generated C, compiler commands and strict native C flags.

Framework bundle: `nine-patch-dimensions309-framework-build-2026-10-25`, manifest
SHA256 `5b6c177ee9a8baf53379b05cc3d4830b2a7bd6f3609f5bdc21d80bafa71685ae`;
JAR SHA256 `ebb0abb7de8f98a706ea2468f4dd8f970ff6eaeb3e48f52bb43d3b5661f0cef3`.
Independent complete readback passed all 6,992 regular files. Actual DEX changed
only `android/graphics/drawable/NinePatchDrawable.smali`.

Native bundle: `nine-patch-dimensions309-native-build-2026-10-25`, manifest
SHA256 `a6a10c13ca63168931fc95453ef9c05f8a09ec6177ebb707ca494684bdc70b21`;
library SHA256 `148eea867c084dfe56ce8c3fc4070be30cb47968bb64e2cf3c099a616e05e931`.
Independent complete readback passed all 2,402 regular files. Only
`ws_generated.v` changes among 85 native V sources; 84 remain identical. Actual
ELF JNI exports increase from 602 to 604, with only the two dimension getters.
The recorded native C compilation passed `-O2 -Wall -Wextra -Werror`.

The V-generated regression APK uses real aapt2-compiled nine-patches, checking
their PNG dimensions, CRCs and compiled chunks before packaging. Guest assertions
cover resource and file loading, bitmap/chunk construction, null handles,
retained dimensions after Bitmap recycling, selector state changes and positive
switch-like geometry. A real View draws the thumb and track; a separate PNG
decoder counts both expected colors in the retained application screenshot.
Both variants consume the same signed APK, common clean283 launcher and runtime.
The old variant must fail the exact inherited-width assertion; the changed
variant must pass every assertion and show both drawable colors. Trace
environment variables must be absent.

Guest310 bundle: `nine-patch-dimensions310-fixture-2026-10-25`, manifest SHA256
`f19f6b7aa9580e84a18bd59f0a28ff7beb875d0b86d7c7f985a203a9f4a27f87`.
Complete independent readback passed all 620 regular files. The shared signed
APK SHA256 is `5bc81bfe553c262fd59f310e1b0d275153aa487b68dbd9171543729e4d6561ae`.
The old framework306/native302 variant reports `startup_failed` with
`NinePatch dimensions: resource thumb width actual=-1 expected=21`.
The new framework309/native309 variant reports `window_observed`, with every
resource, file, bitmap, selector, geometry, drawing, final PASS and READY marker
present exactly once. Both QEMU guests were stopped after capture.

The new screenshot contains exactly 5,040 blue track pixels at
`(144,190)..(227,249)` and 5,040 red thumb pixels at
`(228,190)..(311,249)`, matching the expected adjacent 84-by-60 rectangles.
Screenshot SHA256:
`195a301e32593d3c73738e652a8175b1e51343daa4179a3ac7e2d1730829dd97`.
Old serial/results SHA256:
`9924ed31dae0216837f79152bbea2b8d4718dba00bb8ba5a95941c3f343802bb` /
`e9e8d23111deb208a8dbd8e800e1f8c7c174c6dbe660e464c8a5e1013d824b2c`.
New serial/results SHA256:
`89bada48e09f54b2f3db2a79f0de0fe3956b2b7472f084b758bd0c3a0be900f9` /
`20cdcd1bbfb75e04735722ccf8efe9d52538382eebcef9d83013ca89df952c5c`.

Maps311 pairs these exact framework/native309 artifacts with the unchanged
Maps/GMS APKs, clean283 launcher and 600-second observation/classifier.
Bundle: `maps311-2026-10-25`, typed manifest SHA256
`e8d8ef1bc3666eefd4a83b5ee474dc79b8a60bb1ed7d5c809e4e01c4fd182ddc`.
Complete independent typed readback passed all 22,878 entries. The raw result
is `window_observed`, with `backend_ready` and `native_maps_observed` true,
`process_exited` false, `qemu_alive_before_capture` true and no failure markers.

Skip advances to the map, the search hint and Paris suggestions render, and
Paris map geometry loads. Delayed search transitions caused retries to hit
the Restaurants chip after Paris loaded. This search then persisted through
the final capture: its close button and search field did not advance the UI;
a map drag collapsed the blank bottom sheet but left the map cyan. No fatal
or linkage failure accompanied the stall. Geographic labels remain absent.
Route Options, checked switch graphics and preview controls were not reached,
so this replay does not qualify those real-app behaviors. Guest310 supplies
the positive generic nine-patch rendering proof; a later replay must still
verify actual Maps switches and preview camera behavior.

Serial SHA256:
`701d1e068e77aa6df7cda90e09921f7d54b393f0c9e70d1538f7281cf6eb2a7a`.
Interaction SHA256:
`07116674e5f60e03cb5f6b0a4dba50c39abe3a3ed7e60a149b0586ad0cd6e346`.
Final application PNG SHA256:
`31466ffaa274cdd2fb7b4e7344d05e52239bf26b9bf4990eaa8f15dce1c856e1`.
