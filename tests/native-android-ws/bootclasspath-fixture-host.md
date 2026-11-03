# Platform boot-classpath fixture

The API-28 signed fixture supplies exactly two application classes:
`org.vinix.bootstrap.Main` and `org.vinix.bootstrap.Probe`. Main is the real
Activity and bounded worker Runnable. Probe has no dependency on Main and no
platform implementation or custom ClassLoader override is supplied.

The fixture obtains the actual boot loader from Object.class.getClassLoader(),
the system loader, its own application loader, and two fresh loaders for its own
signed APK: PathClassLoader and DexClassLoader, each parented only by boot.
Object, Context, Bundle and View must have identical Class objects through all
five loaders. Context, Bundle and View must be defined by the boot loader.
Boot and system must each reject Main and Probe. The actual Activity Context and
Main must agree on their application loader, whose parent must be system.

Each isolated loader must define its own Probe, distinct from the application
Probe and from the other isolated Probe. Main reflects the public static
non-native `initializeModuleV2(Context, boolean): Context` method with exact
Context and primitive-boolean parameter classes, then invokes it with the actual
Activity and true. Probe creates and reads a Bundle, links View through boot,
checks that its loader differs from the actual Activity's loader, and returns
the exact supplied Context. Reflection must expose the shared Context return
class and return the identical Activity object.

Resource checks follow this ART runtime's actual discovery rules. The boot path
contains the ten ordered ART core JARs and framework API JAR; it has no manifest
resource. The original system path retains the API JAR and framework-res.apk.
Its manifest enumeration must contain exactly the framework manifest. The
application loader must enumerate framework and its own APK manifests exactly
once, in parent-before-application order. Each deliberately isolated boot-parent
module sees only its own APK manifest. No unexpected or duplicate manifest is
accepted; each enumeration is bounded. The fixture changes no classpath or
loader configuration.

The real Activity and Resources.getSystem() must resolve the same nonempty
android.R.string.ok. Resources.getValue() must report native TypedValue asset
cookie one and TYPE_STRING for that value through both resource objects.
The signed APK contains one generated string resource with a unique fixture
name and exact expected value. Activity resources must discover it with
getIdentifier(), return that value with getString(), and report TYPE_STRING and
asset cookie two with getValue().
These checks exercise the companion resource-discovery and application-parent
behavior rather than assuming non-DEX resource APKs are visible through boot.

The plain daemon worker repeats the complete five-loader identity lookup 32
times, verifies a distinct Thread and absent Looper, and publishes completion or
failure through volatile fields. It never accesses a View. Its join is bounded
to eight seconds; exceptional cleanup interrupts and joins for one additional
second while preserving the primary failure.

The UI thread constructs real View and WebView objects, checks the View's actual
Activity context and ID roundtrip, obtains stable native WebSettings, toggles and
checks JavaScript, and runs one local static-data WebView load. Finally cleanup
restores and verifies the exact original JavaScript state, attempts destruction
even after restoration failure, and preserves any primary exception. A SHA-256
known-answer check for `abc` requires the real VinixNative provider and exact
32-byte digest. The final identity recheck and success marker follow all normal
cleanup. Exceptional branches are source reviewed; a normal ARM pass would not
constitute cleanup fault injection.

The V generators are `bootclasspathfixture/main.v` and
`bootclasspathfixture/sources.v`. Independent register, invocation, exception,
cleanup and report review passed at hashes
`6302868ebb315e14699a5ac992b83d0a7c44059060e0b6080b28d3135e3668ac`
and `cea3623adc3b126f7522bfbe3de68e6531f10461b3ced60119147ffbd6025646`.
The first guarded host compile and signed production attempts passed. The
generated app string compiled and linked without errors. API-28 DEX assembly
and reassembly passed, both canonical trees contain exactly Main and Probe and
match, v3 signing has exactly one signer, and minSdk remains 28. Signed DEX
extraction and direct streaming readback match the checked production DEX.
The signed archive contains resources.arsc. The immutable receipt records source
revision `a16baf6c3a361f3c27cc3368b8be2f795dedc222`.

Complete generated evidence remains outside Git under
`S/bootclasspath-fixture-2026-11-03-r1` and
`S/bootclasspath-fixture-controls-2026-11-03-r1`, where
`S=/Users/alex/.local/state/vinix/android`. Earlier bundles remain intact.

| Qualified artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `bd7384342cb18c6d9d519186f921bba9c6acfe5c0f07b75f3db16dfc650a22e4` |
| Build receipt | `76f42d915da202f10c68c20c2bf0c16e32fb1628bda2f60a9a99f083eef72dea` |
| Production / signed-extracted DEX | `c686c51edfc2d9ec40ec104eb6e7d745b724f0e5c2d9d2a4e0b46a9ea27aafff` |
| Roundtrip DEX | `e68332af077ef0df80e3a42e91eb77399591b6056ce002048711f079cc756ed3` |
| Both canonical Main classes | `2ba70e33596a689a6f7cb43b4ec195da41b452a25f85e83fd97521daf0ec73f8` |
| Both canonical Probe classes | `056d9afafed587768a7e3accfbee77a23e8df0d14678555c353aba80b1cfc7bd` |

Production and roundtrip DEX bytes differ; their complete canonical trees are
equal. Current, precompile-frozen and production-frozen sources match the
reviewed hashes above. SDK manifest/build/JAR/DEX and fresh native
manifest/build/DSO were independently rehashed before and after production and
match. The paired framework JAR from
`S/combined-account-webview-framework-boot-framework-2026-11-03-r1` is
`d9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974`.
The freshly coupled native from
`S/current-native-build-2026-11-03-framework-boot-r1` is
`f3dafa843033f7fb5245cde6007e66eb603ae0fb747fdc1824a33f731ca7088d`.

Both guard and child exits were zero, reasons empty and cleanup complete.
Compile took 1.834 seconds with 309,379,072 bytes sampled aggregate RSS,
349,863,936 bytes detailed maximum RSS and 2,285,568 bytes observed shared-volume
growth. Production took 8.192 seconds with 102,170,624 bytes sampled aggregate
RSS, 97,845,248 bytes detailed maximum and 15,261,696 bytes growth. Both detailed
logs report zero swaps. Limits stayed 600 MiB aggregate RSS, 300 seconds,
512 MiB growth, 1 GiB reserve, 4 MiB output and shell file-size cap 16777216.
The compiler and Java lane was released after actual production completion.

Existing fixtures are unchanged. Host qualification does not establish ART
execution; the signed fixture requires its first ARM run. Visual rendering,
browser-engine availability, the complete Google Cronet module, Maps, accounts
and authentication remain outside this fixture's claim.

The exact success marker is:

```text
BOOTCLASSPATH-PASS shared-platform boot-parent isolated-path-dex reflected-context framework-manifest-once cookie-one native-webview digest bounded-worker
```
