# Pinned GMS cookie API audit

The actual Maps test Google Play Services APK contains eight direct invokes of
`android.webkit.CookieManager.flush()V`. It contains no exact method reference
to `android.webkit.CookieSyncManager.sync()V` in the audited DEX files. These
callers require a real `flush` binding; this audit does not establish successful
Google login.

The maintained tool is `gms-cookie-method-audit.v`, source revision
`acbfa0ea438049c8f9a4a1842b3c9de6d51d83b2`. The pinned APK is
`/Users/alex/.local/state/vinix/android/maps286-2026-10-25/prelaunch/inputs/build/android-maps/GooglePlayServices.apk`,
SHA-256 `a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.

The complete audit bundle is
`/Users/alex/.local/state/vinix/android/gms-cookie-method-audit-evidence-2026-10-26-r3`.
Its `sha256.json` inventory has SHA-256
`bfdfc413af353e175b802672efa96475f5e7e07799016b9a19bc136b060954ee`.
It retains the author source and executable, all extracted DEX and nested APKs,
selected smali, pinned baksmali dependencies, per-DEX method-table checks,
command receipts and unchanged input hashes. The retained `author.v` SHA-256 is
`3ca60c974fe76b5404665688a1511e9be0e9e26a1a59c77fbcb026d9b9822ddb`.

All 15 root DEX and 23 DEX inside eight embedded Chimera APKs were inspected.
The embedded APKs are AdsDynamite, CronetDynamite, DynamiteLoader,
DynamiteModulesA, DynamiteModulesC, GoogleCertificates, MapsDynamite and
MeasurementDynamite; exact members are retained in
`nested-archive-members.json`. Only `classes6.dex`, `classes8.dex` and
`classes11.dex` contain the exact `CookieManager.flush()V` method reference.
The parser's relevant method references matched a separate complete baksmali
method-table listing for every DEX. Candidate-only disassembly then established
these actual invokes; paths and line numbers refer to `smali/<DEX>/` in the
bundle.

| DEX | Class | Method | Smali line |
| --- | --- | --- | --- |
| classes6.dex | alka | `call()Ljava/lang/Object;` | 75 |
| classes6.dex | aonm | `call()Ljava/lang/Object;` | 67 |
| classes6.dex | arol | `A()V` | 131 |
| classes6.dex | attu | `run()V` | 55 |
| classes8.dex | crqi | `call()Ljava/lang/Object;` | 69 |
| classes8.dex | cwjj | `onReceiveValue(Ljava/lang/Object;)V` | 65 |
| classes8.dex | cwjx | `onReceiveValue(Ljava/lang/Object;)V` | 99 |
| classes11.dex | com/google/android/gms/signin/activity/ConsentChimeraActivity | `n()V` | 2002 |

The consent activity calls `removeAllCookies(null)` immediately before
`flush()`. The other seven callsites are retained in `callers.json` with their
exact invoke instructions and containing method declarations.

Validation completed with marker
`GMS-COOKIE-AUDIT-PASS dex=38 refs=3 calls=8 nested_archives=8`.
Independent read-only review covered the conservative candidate selector and
bounded nested extraction. Extraction rejects ambiguous names and duplicate
global output keys before writing. Bounds are four nested levels, 64 embedded
archives, 256 DEX, 256 MiB per selected member and 1 GiB total selected bytes.

Scope is exact-owner method references and direct invoke instructions in
`.dex` members, including recursively selected `.apk`, `.jar` and `.zip`
members. It excludes reflective calls, method handles, references encoded with
another owner, dynamically downloaded code and archives with other extensions.
No guest, credentials or account session were used.

To reproduce, compile the maintained V tool with assertions enabled and run it
from the repository root with two arguments: a fresh external evidence directory
and the pinned APK path. The tool uses the retained Android-framework baksmali
JARs and `/opt/homebrew/opt/openjdk@25/bin/java`; all are hashed in the bundle.
