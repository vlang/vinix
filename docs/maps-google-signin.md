# Google Maps account sign-in

Google account sign-in is not supported by the current native Android runtime.
The repaired **Add account** path returns to onboarding without crashing;
it does not open a Google login page. The
[Maps372 replay](maps372-qualified-intent-replay.md) verifies anonymous maps,
search and route preview only.

## Original failure

A separate guest booted the working Maps372 media on 26 October 2026. **Sign in**
opened an account chooser. **Add account** then exited Maps:

```text
java.lang.NoClassDefFoundError: Failed resolution of: Landroid/accounts/AccountManagerCallback;
Caused by: java.lang.ClassNotFoundException: android.accounts.AccountManagerCallback
APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true
```

No login page appeared and no credentials were entered. Successful QMP input
delivery does not establish authentication success. Genuine screenshots record:

| UTC | Action or screenshot |
| --- | --- |
| 06:08:29 | `signin-before.png`: onboarding |
| 06:08:37 | Click Sign in at 360,576 |
| 06:08:43 | `signin-after.png`: Add account / Cancel chooser |
| 06:08:53 | Click Add account at 327,374 |
| 06:09:01 | `signin-add-account-result.png`: APK exited |

The launcher ran at revision `adb0db9620f5c3984d876422f50adc92f326918c`, but the
guest used the existing Framework371 image. This probe does not test subsequent
framework changes. Boot image SHA-256:
`176094564fba09181b1a2f334f240dc49f0e5f25032696a84db12c2316d0445c`.
Working firmware variables SHA-256:
`d3b3f7afddb44de7020b8544270a67791fca44a48864dcd550cefee633463cbf`.
These are working firmware variables, not the historical prelaunch image.

## Authentication dependencies

The native account backend supplies empty account snapshots and update
listeners. It has no authenticator broker, account storage, token issuance or
refresh path. The installed Play Services APK declares a `com.google`
authenticator service, but the framework lacks its authenticator Binder APIs
and dispatch path. Companion service support does not supply companion activity
context and package-aware result routing.

The installed Play Services APK's `BrowserSignInChimeraActivity` constructs a
`CustomWebView`, installs WebView clients, enables JavaScript and loads its login
URL. Native `WebView.loadUrl` throws, and native HTML rendering does not execute
JavaScript. Standalone Firefox has no Android account handoff; browser login
alone would not prove stock Maps received an account or token.

Real login requires those activity, WebView and authenticator paths, plus an
explicit caller/permission model: APKs currently share an ART VM and Unix
identity. Failed futures and empty account stores must not be reported as login
success.

## Credential logging repair

Commit `adb0db962` replaces inherited `addAccountExplicitly` code that logged its
password and userdata before returning false. The replacement throws
`UnsupportedOperationException` without reading or logging arguments. It does
not save credentials or create accounts.

`tests/native-android-tools/check-account-addition.v` passed replacement,
missing-method insertion, unrelated-method preservation and malformed/duplicate
rejection checks; both accepted smali variants assembled. Retained log:
`/Users/alex/.local/state/vinix/android/account-addition-check-2026-10-26.log`,
SHA-256 `94e0721f6f5dd8c7a866f1b2d942636b7198b86d2bf95dfd7b1f78a4afd2e8a1`.
These checks do not establish device authentication.

## Asynchronous API repair

Commit `2d3dfe2b7` supplies `AccountManagerCallback`, `AccountManagerFuture`,
the account exception hierarchy and `AccountManager.addAccount`. With no
registered authenticator, the future is already complete and its result throws
`AuthenticatorException`. A non-null callback is posted through the supplied
Handler or the main Looper. A null account type throws immediately. This repairs
the missing API without creating an account or claiming Google authentication.

The focused transformer checks passed, including assembly of all eight added
classes and the modified `AccountManager`; the existing framework checks also
passed. The maintained ART fixture is
`tests/native-android-ws/account-addition-fixture.v` (commits `2d3dfe2b7` and
`ddc9cf7ac`; build receipts added in `088c57cbf`). It checks queued
main/worker/explicit-Handler callbacks, exactly
one delivery, future identity, completion and cancellation state, repeated and
timed failed results, null arguments, empty account snapshots and rejected
synthetic credential insertion. The runner rejects either synthetic secret
sentinel anywhere in the serial log.

The direct Framework371 rebuild changes only `AccountManager` and those eight
classes (2,084 classes total). Its JAR SHA-256 is
`e7ce08fb1ca26e652e0d4c8e66adf31e2ffd4a2abf778eaa603a60ff3e036971`;
DEX SHA-256 is
`44b5ef444dc961f42169a820a9d1641f7f3ace651449a4128edb351a3dfe83ba`.
Source and disassembled DEX delta checks reject unrelated class changes.

The direct build is retained at
`/Users/alex/.local/state/vinix/android/account-contract-build-2026-10-26`.
Its full 6,280-file read-back passed with `sha256.json` digest
`3c54524bff390fca35570edd81961fc9103c85e5fccf9fac8ae6c8056e760b81`.
The maintained builder is `tests/native-android-ws/account-contract-build.v`
(commit `fcce61bf3`). The independent seal/check tool is
`tests/native-android-ws/account-contract-retain.v` (commit `de2d9b82c`);
its negative checks reject a wrong manifest digest, modification, omission,
addition and symlink substitution. These checks establish artifact integrity,
not authentication.

## ART verification

The isolated ART guest passed the complete maintained fixture on 26 October
2026, including rejection of synthetic credential insertion. The runner
required one exact `ACCOUNT-ASYNC-PASS` marker and ten further seconds without
a fixture assertion, duplicate marker, secret sentinel or APK exit. The PNG
`account-contract-art.png` displays “Unavailable authenticator callback checks
passed.” No account was created.

The unfiltered serial log also contains a caught `NoSuchFieldError` from the
inherited Maps-specific transition diagnostic probing `nge.bB` in the synthetic
fixture activity. That diagnostic is unrelated to the account assertions and
did not terminate the APK. This run establishes the failed account future and
callback contract, not a diagnostic-free general Android runtime.

The stopped guest is retained at
`/Users/alex/.local/state/vinix/android/account-contract-art-2026-10-26`.
Full read-back verified all 110 files; `sha256.json` digest:
`fdbe993fc3e4234e5396e74eac6cc4bb8b9238b250a4e2d6c2e0ed1375bc21bd`.
The tested APK SHA-256 is
`4387e4c652f6df64759fc1d23242dc03f78c1d17ead89d83ba3a6fa700a86f3e`.
The bundle preserves the original reviewed generator and a supplemental build
receipt whose DEX is byte-identical to the tested APK's DEX. It also preserves
the initial prepare rejections and interrupted seal receipts. The maintained
runner is `tests/native-android-ws/account-contract-run.v` (commit `4a8894a49`):
it composes the original modules in Limine order, verifies Framework371 before
replacement and checks the exact runtime file delta and original module hashes.

## Maps retest

A separate guest booted that repaired JAR in the original Maps372 module order
at preparation revision `4a8894a49fc3f9ff98578c88a08127ff92a2c0b0`. Only
`api-impl.jar` changed in the composed runtime. **Sign in → Add account** closed
the chooser and left onboarding intact. The chooser reopened, Cancel worked,
and Skip reached the map screen. No Google login page appeared and no
credentials were entered. The final serial log has no APK exit or missing
callback class exception. This verifies crash recovery and anonymous use.

| UTC, 26 October 2026 | Genuine capture or action |
| --- | --- |
| 06:58:17 | `signin-onboarding.png`: Make it your map |
| 06:58:44 | Click Sign in |
| 06:58:47 | `signin-chooser.png`: Add account / Cancel |
| 06:58:56 | Click Add account |
| 06:59:18 | `signin-add-account-result.png`: onboarding remains |
| 07:03:39 | `signin-chooser-reopened.png`: chooser responsive |
| 07:03:55 | `signin-cancel-recovered.png`: Cancel recovered onboarding |
| 07:04:10 | Click Skip |
| 07:04:55 | `google-maps-running.png`: map tiles and Explore screen |

The genuine map PNG is
`/Users/alex/.local/state/vinix/android/account-contract-maps-retest-2026-10-26/google-maps-running.png`,
SHA-256 `015507675ea14f58baebd83ccc049072f8b7ae30c953c14e58de6e973affcc31`.
The stopped guest bundle retains the complete media, module checks, serial log,
input/capture logs, sources and ownership/stop receipts. Its prepared boot
SHA-256 is `ab57678e6c98bdc74476033f0867dcdebdfb9dfde28f08f49f7c3c56ab7db025`.
Full read-back verified all 108 files; `sha256.json` digest:
`47acb203d9e1fe5242729a23e91581d77193ac68f567cdb3ba70747dab9645ea`.

## Retained evidence

The stopped diagnostic is outside Git at
`/Users/alex/.local/state/vinix/android/maps-signin-probe-2026-10-26`.
Its `sha256.json` digest is
`59ff615b4eea4dda8784ddb3cdafdb3a8cfefef16d4c4b2e5a76b936c7f5833b`.
The seal covers 31 files, including cloned media, launch/ownership/stop
receipts, logs, genuine PNGs, exact launcher and retention sources. Full
read-back verification passed; an incorrect digest was rejected.

The maintained V launcher is `tests/native-android-ws/maps-signin-probe.v`
(commit `2435364cf`); the seal/check tool is
`tests/native-android-ws/maps-signin-retain.v` (commit `02c487a68`). Both verify
guest ownership. The seal requires a stopped guest, and the launcher's negative
test refuses to stop an unrelated process. Preserve this bundle as the original
pre-credential failure when testing later repairs.
