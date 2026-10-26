# Google Maps account sign-in

Google account sign-in is not supported by the current native Android runtime.
The [Maps372 replay](maps372-qualified-intent-replay.md) verifies anonymous maps,
search and route preview only.

## Reproduced failure

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
refresh path. Companion service support does not supply companion activity
context and result routing.

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
