# WebView provider-package fixture

The API-28 fixture checks the nullable Android provider-package query without
inventing a package identity for the native renderer. Reflection requires
WebView.getCurrentWebViewPackage() to be public, static and non-native, declared
by WebView with no parameters and exact PackageInfo return type.

The success path calls the real getter 224 times in seven batches of 32: cold on
the Activity thread, on a plain worker, after that worker, after construction and
settings acquisition, after changing JavaScript state, after static loadData,
and after destruction. Every result must be null because this runtime has no
selected or loaded Android WebView provider package.

The worker verifies that it differs from the Activity thread and has no Android
Looper. It only calls the static getter. Its completion and captured Throwable
are volatile fields. The daemon thread has an eight-second join; exceptional
cleanup interrupts it and joins for at most one additional second, preserving
the original failure. No worker accesses a WebView instance.

The UI smoke uses the existing WebView constructor and cached WebSettings. It
checks settings identity and JavaScript state around repeated queries, changes
the setting to its opposite value, and checks that the query preserves it.
One local text/html loadData call exercises the existing static-data path with
no network or browser descriptor requirement. Finally cleanup restores and
checks the exact original JavaScript value, attempts destruction even if
restoration fails, and preserves an original failure if cleanup also fails.
A final batch runs after normal destruction.

Only org.vinix.bootstrap.Main is supplied; it is also the worker Runnable. There
is no platform stub, fabricated PackageInfo, provider installation, UID constant
or runtime-path dependency. The fixture does not verify page callbacks, physical
or visual rendering, browser-engine availability, Google module completion,
Maps, an account or authentication. Exceptional cleanup paths are source
reviewed; a successful ARM run would exercise normal cleanup.

The source generators are `webviewpackagefixture/main.v` and
`webviewpackagefixture/sources.v`. Independent complete source/register/catch
review passed at hashes
`b563291b14d59b28d6b74b175e61f23d957b5061e9b81969f908b092d3673b27`
and `c07aa935e7454fad5aec5bf388345957b1f0f4e9ab7afd3b9f58e5e0220d0cb2`.
The first guarded host compile and signed production attempts passed. Fresh
error-free API-28 assembly/reassembly, two matching canonical trees containing
exactly one application class, v3 signing with one signer, minSdk 28 and exact
signed-DEX extraction/readback all passed. The immutable build receipt records
source revision `63e1e4374dbae1589ec89d979499ae79a01568ff`.

Complete generated evidence remains outside Git under
`S/webview-package-fixture-2026-11-03-r1` and
`S/webview-package-fixture-controls-2026-11-03-r1`, where
`S=/Users/alex/.local/state/vinix/android`. Historical bundles remain intact.

| Qualified artifact | SHA-256 |
| --- | --- |
| Signed probe.apk | `896cd9dbec8ccde28d3e0363c1a77ad593708c3ef7e73cf57001e2ae19327579` |
| Build receipt | `46ec037dca28702e448d90a389e17294fa98d82637c44d6dfa68028a7534b335` |
| Production / signed-extracted DEX | `3ebf53943e5aacda89600f20a0ec6b29cb454af3f4f304c40d8445c629966c2a` |
| Roundtrip DEX | `c2fab9b8e2ca5bd126c8b37bb78faa06efd6f88e4f3212815a4a3f217ca18e61` |
| Both canonical Main classes | `32220969ee8a128afd5f3752f8f797fbaddef254fb6382e4baf82c6395085d40` |

Production and roundtrip DEX hashes differ; the complete canonical trees match.
Streaming classes.dex directly from the signed APK reproduces the production
hash. Current, precompile-frozen and production-frozen sources retain the
reviewed source hashes above. Framework manifest/build/JAR/DEX were rehashed
before and after production with identical results. The new paired JAR from
`S/combined-account-webview-webview-package-framework-2026-11-03-r1` is
`0e5e2632bc64ad9d548379491c59ed4e8a91d42fcfa6677b75aae4798dfeb7a9`.

Both guard and child exits were zero, reasons empty and cleanup complete. Compile
took 2.214 seconds, sampled aggregate RSS 332,726,272 bytes, detailed maximum
366,215,168 bytes and observed shared-volume growth 5,767,168 bytes. Production
took 9.332 seconds, sampled aggregate RSS 100,139,008 bytes, detailed maximum
95,125,504 bytes and observed growth 218,120,192 bytes. Detailed logs report zero
swaps. Limits remained 600 MiB aggregate RSS, 300 seconds, 512 MiB observed
growth, 1 GiB reserve, 4 MiB output and shell file-size cap 16777216. The compiler
and Java lane was released after actual production completion. Host qualification
does not establish ART execution; the signed fixture requires its first ARM run.

The exact success marker is:

```text
WEBVIEW-PACKAGE-PASS public-static nullable-no-provider cold-repeat off-ui bounded-worker settings-identity javascript-preserved static-data-smoke destroyed-requery
```
