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

The original ART fixture source is `account-token-fixture.v` at commit `bff87f34b`.
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

The current fixture source at `bcd7cc1f4` preserves that Main Activity and adds
`TokenCacheService` plus the ordinary `TokenCacheClient` Activity. The signed
APK and complete assembly/signature/manifest receipts are retained at
`/Users/alex/.local/state/vinix/android/account-token-fixture-2026-10-26-r5`.
`probe.apk` SHA-256 is
`bd79181ffa9fca598189a0382a8de5c40d83fc675318a609be3e2a7ad3ec0042`;
the complete `sha256.json` inventory SHA-256 is
`68812a0b80187d458ee53a8bc6a05634ef901cc680dd6b42fac2f061edaa6702`.
Its fixture signer certificate SHA-256, independently checked with
`apksigner verify --print-certs`, is
`12520d3c4783e80927f029e8d0108b9808e3c17fbb9d69647f10527ffe1308f7`.

`account-token-cache-controller.v` runs the cache service with its exact APK,
signer and account-type registry selector, then a normal Activity process using
the production broker. It checks owner denial, null/empty/exact invalidation,
password and clearPassword token purge, multiaccount broker deletion, and
durability after clean service shutdown and restart with the same data directory.
The client uses a private 64×64 native WS surface and a held input pipe; no
desktop interaction is needed. Both service lifetimes must end with unbind and
destroy callbacks and exit zero. Each phase has separate bounded logs, exact
markers, runtime input hashes and a JSON receipt. The controller never selects
Google account data or changes a production authority registry.

After staging the final runtime/controller and provisioning a previously unused
fixture Unix UID/GID 10014, run as root in the guest:

```sh
/opt/vinix-maps-account/bin/account-token-cache-controller /opt/vinix-android-aarch64 /opt/vinix-maps-account/account-token-fixture.apk 10014 10014 /opt/account-cache-r1
```

The output directory must be fresh with root-protected, target-traversable
ancestors and an absolute path of at most 55 bytes. Retain that complete directory externally, including
the receipt and logs. Before exit the controller emits the receipt and three
bounded logs directly to `/dev/console`, using the existing results archive
shape and BEGIN/CHUNK/END framing with the distinct
`VINIX-ACCOUNT-TOKEN-CACHE-RESULTS-1 ` prefix. Retain the serial capture before
stopping QEMU. APKs and app databases stay in the guest. The required final marker is
`ACCOUNT-TOKEN-CACHE-CONTROLLER-PASS real-ART JNI SQLite authenticated-broker ordinary-client password-clear restart-durability`.
Actual ART execution remains pending; host compilation/self-tests and APK
assembly do not establish this marker. See `account-token-cache.md` for the
production cache scope and host validation evidence.
