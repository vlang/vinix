# Paint UTF-16 advance widths for Maps

Source baseline: `9a7aa5b5c` (NinePatchDrawable dimensions). This fixes a
concrete Paint API defect found while investigating absent street/place labels
in Maps308. Existing `getTextWidths(String,int,int,float[])` returned a pixel
bounding-box width without filling its output; the other three public overloads
were absent. Maps' DEX contains calls to the String convenience and char-array
overloads, and its native library resolves the exact String convenience
descriptor through JNI. These are static references; they do not establish
which glyph path ran during Maps308 or prove the cause of absent labels.

Paint now provides all four public overloads. String and CharSequence ranges
use an exclusive end; char-array ranges use a count. Return values and output
positions count UTF-16 code units. A surrogate pair assigns its advance to the
leading unit and zero to the trailing unit. Output begins at slot zero and
leaves the suffix untouched. Null, range and capacity validation precede writes,
including zero-count calls, following the primary
[AOSP Paint contract](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/1cdfff555f4a21f71ccc978290e2e212e2f8b168/graphics/java/android/graphics/Paint.java).
The CharSequence overload reads actual characters with TextUtils.getChars.

The two native overloads use the existing selected/default font, text size,
UTF-16 decoder and raw glyph advances used by this backend's measureText and
Canvas rasterizer. Advances are not rounded per slot. Native output is staged
before one SetFloatArrayRegion call, with the temporary allocation freed and
String/char-array inputs released on all acquired paths. The production delta
is one helper registration, two native bindings and one routine in fonts.v.
Existing textScaleX state, complex shaping, drawing, bounds and GLES behavior
are outside this change. The inherited missing-font fallback remains unchanged.

The V-generated fixture calls Maps' exact String convenience descriptor first,
then verifies all four overloads, return counts, proportional advances,
nonzero space advance, repeated-call stability, text-size scaling, selected
monospace font and agreement with the existing measureText total. It covers
supplementary characters, isolated high/low-surrogate ranges for all range
overloads, a custom CharSequence whose toString differs from its content,
untouched output tails, zero ranges, and exact exception classes with output
preservation after failure. It independently requires trace variables absent.
V formatting/compilation and host APK assembly/signature verification passed.

The maintained sourceproof reproduces the DEX and native references from Maps
APK SHA256 `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`.
Its external bundle is
`/Users/alex/.local/state/vinix/android/paint-text-widths-sourceproof-author3`,
manifest SHA256
`f78ec76ceb83ad2c2b8763c06077ca042b2713b95c34c05ad031369febf82c71`.
It retains the exact DEX2/DEX3/native entries, targeted disassembly, command
receipts, before/after tool hashes, and AOSP Paint.java at revision
`1cdfff555f4a21f71ccc978290e2e212e2f8b168`, source SHA256
`05694f46b23451cdf5d817108063d03d7937135f996d1b33b1ceab88e60adb6f`.
Independent complete readback passed all 18 regular files, the exact inventory
and identical tool maps; it also confirmed the native string addresses and
method lookup. The sibling `paint-text-widths-sourceproof-author3-review.json`
retains that review receipt.

Framework312 and Native312 builds passed from sealed309 inputs. The actual DEX
delta is only `android/graphics/Paint.smali`; the native source delta is the
single fonts.v insertion and two generated wrappers (604 to 606 JNI exports).
Independent generated V/C ABI and cleanup readback passed. Native compilation
with `-O2 -Wall -Wextra -Werror` passed. Their complete external bundles are
`/Users/alex/.local/state/vinix/android/paint-text-widths312-framework-build-2026-10-25`
and
`/Users/alex/.local/state/vinix/android/paint-text-widths312-native-build-2026-10-25`,
with manifest SHA256 values
`c4ea45675a661c38278173945c896bc69b4ce7812d054a44e680ef8ca1e23287`
and
`66d1b23301a43bf29c3dbc45b1298a7e15e397c1e5addfb7648c435b560bc417`.
The new framework JAR SHA256 is
`33d231c02740bbb79bdc663f1ac79e142452aadb85348bee5a5165b0a03d674f`.
The new native library SHA256 is
`51280a48fcefd27a49ba7a9b7d9b6d226c0a164af2517d3c851ea1bf3c7cf9de`.
Independent complete readback verified all 6,994 framework files and 2,407
native files against their exact sealed inventories.

Same-APK guest comparison313 passed. The old309 framework/native combination
throws the exact uncaught
`NoSuchMethodError: No virtual method getTextWidths(Ljava/lang/String;[F)I`
at the first convenience call; the historical suite classifies it as
`startup_failed`. With312, all six assertion groups, final PASS and READY appear
exactly once, and the suite reports `window_observed`. Both suite commands
exited zero. The checker separately verifies those semantic outcomes, trace
absence, common runtime/media/launcher inputs and the shared signed APK SHA256
`7c06d707ea484ec101be4da1e80172a4577062c123b02f2d23de5fec36c6751f`.
Only the framework jar and native library differ between variants. The complete
stopped-guest bundle is
`/Users/alex/.local/state/vinix/android/paint-text-widths313-fixture-2026-10-25`,
manifest SHA256
`ea40e7026cfb606156aca1c0af2ce23b1b9e7af6a92170858921d76ef67bda2a`.
This qualifies the Paint API behavior; Maps314 below assesses its visible
effect in the application.

Maps314 replayed the exact312 artifacts with source committed as `a5dd635fd`.
The unchanged Maps/GMS APKs, clean283 launcher and 600-second classifier were
retained. The complete bundle is
`/Users/alex/.local/state/vinix/android/maps314-2026-10-25`, typed manifest
SHA256 `36f69cfdcf35e81eb853e6a16ad31e31998e70c69a04d9b69d88ad5cdc2d73b7`.
Both the replay runner and independent root readback verified all 23,090
entries. The raw outcome is `window_observed`, with 600 seconds observed,
backend/native maps ready, no process exit, QEMU alive before capture and no
failure markers. Independent screenshot authentication also passed.

Skip advances to a labelled continent map. Country/state names and Hudson Bay
are visible; these geographic labels were absent in311. Google Maps attribution
is also visible. Paris search then loads a place card, photos and
city/street/neighbourhood labels.
Directions accepts a manual Eiffel Tower origin and loads driving and walking
routes to Paris, including the selected blue path, alternatives and travel
times. The first fast origin entry lost characters; clearing it and entering
with pauses produced the verified complete suggestion. Current-location
selection still supplies no usable GPS position, so this run does not qualify
navigation from the guest's current position.

Trip options now show circular switch thumbs, absent in308. Each avoid row
moves its thumb from x540 to x566 when enabled; a second ferries click moves it
back. The toll-price toggle moves in the opposite direction when disabled.
Walking wheelchair/ferries toggles also move from left to right. Tracks and
checked-state tint remain too faint to qualify visually. Returning to the
driving screen shows the selected route and Avoid tolls/Avoid highways chips.

Driving preview Next changes the instruction and, after 10.5 seconds without
intervening input, moves the camera from the Eiffel area to Pont de l'Alma.
Previous restores the first instruction and Eiffel-area camera. Walking
preview opens with a dotted route; its initially beige base map finishes
loading park/road geometry and labels before the final application capture.
The timed guest then stops. A subsequent walking Next attempt fails because
the QMP socket is gone; walking Next/Previous are not qualified by314.

Serial SHA256:
`eafc82ad9ab84c97a25efc6669146ca36d141ad02cbdf8a37b6f9aacade798f0`.
Interaction SHA256:
`50101bce883594811699e4fd5fb283ff57b649a7089c6e1eafb2e6dd6ba8b8dd`.
Final application PNG SHA256:
`cee4e7dfa320a9bf4bb3b42d95c06e734c80283d95c3eda4f44e1892376d8f29`.

The two failed commands attempted after shutdown, their complete output
streams, and the extended interaction log are preserved separately by
`maps-post-stop-preserve.v`. The original sealed interaction is authenticated
and must be an exact prefix. The qualified supplement is
`/Users/alex/.local/state/vinix/android/maps314-post-stop-supplement-v2-2026-10-25`,
manifest SHA256
`f0c4575e3b5e7a009686bd16e8b162bdb56c93b5db0f91622714c386da2eb0ab`.
Independent read-only verification passed all 20 typed entries. Its sibling
receipt SHA256 is
`e009db6fac28c1ee6e1a5f92a68d7f66cbe08daf2c5dc1687006867dca038b05`.
The earlier supplement without `-v2` remains unchanged and unqualified: it
wrote a readback receipt after its inventory inside the bundle. The corrected
helper keeps receipts outside the sealed root and verifies the exact inventory.
