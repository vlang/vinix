# Asset locale enumeration fixture host qualification

Host qualification passed on 2026-11-02; ARM execution is pending. This signed,
one-class fixture calls the real `AssetManager.getLocales()` native entry point
against actual AAPT-compiled application resources and the pinned framework
resource APK. No locale results come from the default Java Locale or the JNI
implementation under test.

The build started at revision `c41f9dbc597fe7bf5a8ec8afb7f64fd2d4677f7a`.
Exact generator sources are copied into the evidence bundle:

| Source | SHA-256 |
| --- | --- |
| `assetlocalesfixture/main.v` | `afd20094c35bb5d41364b64f71aff47353af44136793110c12c78c824feb6ce7` |
| `assetlocalesfixture/sources.v` | `7278c0bbfdfbc6a78d1ba44ee11ffbf685deebea68bc9f8a16bfd91ba5fc70f4` |

Complete evidence remains outside Git:

- `/Users/alex/.local/state/vinix/android/asset-locales-fixture-2026-11-02-r1/`
- `/Users/alex/.local/state/vinix/android/asset-locales-fixture-controls-2026-11-02-r1/`

| Artifact | SHA-256 |
| --- | --- |
| Signed `probe.apk` | `03877624fde8928fac5efb3a2c49d9306356f5cb1488c3fa343799a39044a265` |
| `build.json` | `bd4d3d928057de1978885429b9805fd5f4fa8ff87f5736d6a1b9f74a38f9e6a6` |
| Production and signed-extracted `classes.dex` | `23e7f2180c6f67a524e0dc6c15893893f6bae1f500471ad0b7add8e76170677e` |
| `locale-oracle.json` | `e954f32687d3bcc9cffd33712c5faa630df28b687ecdbcb99ba4decc9fbe035c` |

Independent AAPT configuration dumps establish framework locale `{en}` and raw
app locales `{fil, fr, he, iw, sr-Latn, tl, zz-ZZ}`. The generated expected native
set is `{en, fil, fr, he, iw, sr-Latn, zz-ZZ}`. This native API's canonicalization
merges `tl` into `fil`, while `he` and `iw` remain distinct. Both Hebrew resource
keys and both Tagalog/Filipino configurations survived compilation. The unique
`zz-ZZ` control is absent from the framework; `en` is absent from the app. Default
resources add no empty locale. Signed APK configurations exactly match the
unsigned resource table used to generate the expected array.

Runtime checks require the exact unordered set, rejecting missing, additional,
null, empty or duplicate entries. Four native calls across Activity/application
contexts must return pairwise distinct arrays. String and null mutations in two
caller-owned arrays must leave other live snapshots and later queries intact;
later calls must preserve those caller mutations. The default Locale tag must
remain unchanged. Failure messages include actual and expected arrays.

One real Keyguard service query requires `isDeviceSecure()==false` for this
fixed guest without an Android PIN, pattern or password enrollment backend.
Unix login credentials are separate. The fixture does not call or alter legacy
Keyguard methods. All assertions and UI setup precede the sole success marker:

```text
ASSET-LOCALES-PASS framework-app canonical-set fresh-arrays mutation-isolation default-locale device-secure
```

The failure marker is `ASSET-LOCALES-FAIL`; package/Activity are
`org.vinix.bootstrap` and `org.vinix.bootstrap.Main`. `getSystem()` and closed
AssetManager behavior are outside this test. It does not exercise Google
applications, accounts, network access, authentication or native allocator
failure paths. Existing stable-display and PendingIntent fixtures are unchanged.

The builder passed resource compilation/linking, all authored resource-key
checks, independent and signed configuration dumps, error-free API-28 Smali
assembly, two canonical DEX roundtrips, exact source/tool/class closure, v3
signature verification, duplicate/single-DEX ZIP checks, signed DEX extraction
equality and final input readbacks. Independent source reviews passed.
Final builder compilation took 1.698 seconds with a 353,714,176-byte reported
peak RSS; production took 7.874 seconds with a 96,534,528-byte reported peak RSS.
Both exited zero with complete cleanup and zero swaps. Original guards remain
600 MiB aggregate RSS, 300 seconds, 512 MiB disk growth, 1 GiB reserve, 4 MiB
output and `ulimit -f 16777216`. The controls bundle retains the first compile
and its source snapshot before parser hardening, plus the final recompile used
for this APK; neither attempt overwrote earlier evidence.
