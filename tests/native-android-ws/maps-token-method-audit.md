# Pinned Maps token requirements

The maintained `maps-token-method-audit.v` at source commit `4f643a127` audits
the actual Maps APK used by this work. Its SHA-256 is
`6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2`;
the retained input is
`/Users/alex/.local/state/vinix/android/maps286-2026-10-25/prelaunch/inputs/build/android-maps/GoogleMaps.apk`.
Its smali source identifies Maps `26.42.01.997557324` (`1068832648`).

The successful run is retained at
`/Users/alex/.local/state/vinix/android/maps-token-method-audit-evidence-2026-10-26-r2`.
The SHA-256 of its complete `sha256.json` inventory is
`2b683f8f48df7a231396ffdf570320995d2bc1d8f0cec6f0c5a76172d16618eb`.
It preserves the executable/source, tools, input hashes before and after the
run, all ten root DEX files, method-table cross-check receipts and selected
caller smali. Line references below are relative to its `smali` directory.

## Measured API use

All ten DEX method tables were reconstructed and cross-checked with baksmali.
The selection includes every exact AccountManager owner method whose name
contains `AuthToken`, exact GoogleAuthUtil references, TokenData descriptors
and methods named `getToken` or `getTokenWithNotification`. It found 21
selected references and 27 canonical invokes. The latter includes unrelated
AndroidX `SplitInfo.getToken`; these totals are not AccountManager call counts.

There are twelve direct AccountManager invokes:

| Operation | Count | Concrete retained callers |
| --- | ---: | --- |
| `getAuthToken(Account,String,Bundle,Activity,Callback,Handler)` | 7 | `classes2.dex/awul.smali:829`, `classes4.dex/nyz.smali:1238`, `classes4.dex/vgj.smali:2010`, `classes5.dex/acbs.smali:2720`, `classes5.dex/asrf.smali:431`, `classes5.dex/awwo.smali:566`, `classes6.dex/bcwq.smali:484` |
| `getAuthToken(Account,String,Bundle,boolean,Callback,Handler)` | 1 | `classes7.dex/cagl.smali:245` |
| `blockingGetAuthToken(Account,String,boolean)` | 3 | `classes2.dex/akjm.smali:1145`, `classes2.dex/aysu.smali:1947`, `classes7.dex/bgud.smali:404` |
| `invalidateAuthToken(String,String)` | 1 | `classes7.dex/cagl.smali:153` |

No direct method-table references to `getAuthTokenByFeatures`, `peekAuthToken`
or `setAuthToken` were found in this Maps APK. This does not replace the
separate GMS audit, which does demonstrate explicit token set/peek use.

`cagl.b(Account,String)` logs `AccountManagerTokenProvider#getTokenWithDetails`.
It passes the account and token type through, with **null options,
notifyAuthFailure=false, null callback and null Handler**. It calls
`getResult(60000, MILLISECONDS)`, reads `authtoken`, and reads
`android.accounts.expiry` as a long. A nonzero expiry becomes
`Instant.ofEpochMilli`; zero means no expiry. `cagl.a(String)` clears the
provided token through `invalidateAuthToken("com.google", token)`.

`bgud.a(Context,Account)` requests the literal
`oauth2:https://www.googleapis.com/auth/webhistory` through the blocking API
with `notifyAuthFailure=false`. `aysu.s(boolean)` logs
`GaiaAuthToken.getTokenFromAccountManager` and forwards its stored account and
token type to that same blocking API.

The Activity callers use null options and dynamic web-login token types.
`awul.a(String)` constructs `weblogin:service=local&continue=` plus an encoded
URL. Its completion method reads `getResult()` and `Bundle.getString("authtoken")`
(`classes2.dex/awul.smali:889`). `awwo` also consumes `authtoken` from the
future result. `nyz` constructs `weblogin:service=` plus its service field,
`&continue=` and an encoded URL. These call sites establish compiled flows;
the audit does not establish which one executes during initial login.

## A separate GMS token service is also compiled in

`classes3.dex/cagp.smali:296` logs
`GoogleGmsCoreTokenProviderImpl#getTokenWithDetails`, calls an obfuscated
TokenData-returning helper, and consumes its token and expiry fields.
`classes2.dex/bedp.smali` selects
`com.google.android.gms.auth.GetToken` in package `com.google.android.gms`.
Its `l(Context,Account,String,Bundle)` normalizes/copies options and calls a
service-binding helper; `k` waits for an IBinder and passes it to a request
object. Its options helper adds `clientPackageName`, `androidPackageName` and
`service_connection_start_time_millis`.

`classes2.dex/bedq.smali` additionally contains a GetTokenRequest/GetTokenResponse
path through `bedx.d`, with a fallback to `bedp.l`. These compiled paths mean
that implementing the AccountManager operation alone cannot establish that
every Maps token provider works. The active provider and actual cross-process
GMS Binder requests still need guest evidence. This audit does not claim a
specific Binder transaction number or wire schema.

## Smallest authenticated AccountManager increment

The current broker request operations cover account enumeration, addition and
interaction redemption. Token requests need a bounded operation carrying the
exact Account name/type and token type, routed to the registered authenticator
and an authorized visible account. Normalize null options and replace caller
identity fields from the kernel peer and registry. The actual GMS
`IAccountAuthenticator.getAuthToken(response,Account,String,Bundle)` must
produce the result through its authenticated response capability.

Preserve real scalar results, including token expiry, and use the existing
opaque interaction route for a real retained authenticator Intent. The public
overloads need pending futures, Handler callbacks, cancellation and timed
results. The blocking wrapper must reject the main Looper. No Activity cannot
be turned into an invented cross-process Intent. Notification support must
fail explicitly until implemented.

GMS declares `customTokens=true`; initially forward each request without a
generic response cache. Invalidation and explicit authenticator token storage
remain separate requirements. Tests must cover account/type forwarding, null
options, trusted caller replacement, real result plus expiry, caller isolation,
timeouts, cancellation, replay and interactive completion. See
`gms-account-store-audit.md` for the GMS-side storage and identity evidence.

The scan proves direct exact-owner DEX references and canonical invoke lines.
Nested extraction is bounded and extension-selected (`.apk`, `.jar`, `.zip`);
this APK contained no such nested archives. Reflection, dynamic downloads,
MethodHandle dispatch and differently named embedded archives are outside the
claim. The run supplied no credentials and did not test or establish login.
