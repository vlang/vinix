# AccountManager token framework checks

Source commit `34cf9e5dc` adds the Activity, boolean and deprecated
`getAuthToken` overloads, `blockingGetAuthToken`, and the private native token
hook. It reuses the production pending FutureTask and Handler callbacks.
Unsupported notification requests produce a failed future; the blocking
wrapper rejects the main Looper. Real token results must come from the broker.

The maintained `tests/native-android-tools/account-token-source-check.v`
compiles the actual provider and Future generators, applies them to a retained
AccountManager, checks every method delta and assembles the resulting DEX.
The successful run is retained at
`/Users/alex/.local/state/vinix/android/account-token-source-check-evidence-2026-10-26-r2`.
Its `receipt.json` SHA-256 is
`18958e3a8b6eac9d502e16c6603746879902057198dc56772b49b91092119322`.
This checks forwarding, pending fallback, exact native signature, main Looper
guard ordering, idempotence and preservation of unrelated methods.

The ART fixture source is `account-token-fixture.v` at commit `bff87f34b`.
Its successful signed APK build is retained at
`/Users/alex/.local/state/vinix/android/account-token-fixture-2026-10-26-r4`.
The complete `sha256.json` inventory SHA-256 is
`62c9e2c2810099c1c222377b257d64cf5a8c80c692b1feb151e405693407c4d2`;
`probe.apk` SHA-256 is
`592c902398fa740f4c4bcad650e992922a102d5e3dc7ea644e84ba36b0a55193`.

Run that APK against a framework containing the token provider. Set
`VINIX_ANDROID_ACCOUNT_SOCKET` to a verified nonexistent socket path: an unset
variable selects the default broker socket. The probe checks production
no-backend errors and notification rejection, argument validation, inherited
overload delegation, worker blocking results, main Looper rejection and one
callback on the selected Handler with the original Future identity.
Successful values are generated only inside a synthetic subclass.

The expected serial marker is:

```text
ACCOUNT-TOKEN-PASS null-validation boolean-options deprecated-null-options worker-blocking main-looper-guard notify-error unavailable-future callback-identity-handler
```

Require the marker exactly once and no assertion, verifier or uncaught failure.
Only APK assembly has been performed for this bundle; ART execution is pending.
These checks do not establish Google login, authenticator token success or the
separate Maps GMS token-service Binder path documented in
`maps-token-method-audit.md`.
