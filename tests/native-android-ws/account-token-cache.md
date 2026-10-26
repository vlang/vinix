# Explicit AccountManager token storage

`setAuthToken` and `peekAuthToken` now use the selected authenticator's private
SQLite store. Native access requires its authenticated service channel; a
normal app cannot read or write cached values. Only explicit `setAuthToken`
values are stored: authenticator responses and custom tokens are not
automatically cached, and the implementation generates no tokens.

A null value deletes an entry; an empty string remains a valid value. Token
types and values are bounded to 4096 UTF-8 bytes, with at most 64 entries and
64 KiB of token data per account. `setPassword` and `clearPassword` delete
that account's tokens in the same transaction as the password change; a failed
purge rolls back both changes.

`invalidateAuthToken` removes the exact value across accounts of the selected
type, preserving other values and types. A null token is a no-op; an empty
token is invalidated normally. Ordinary apps send bounded operation 5 through
the broker. The selected service verifies the live request capability and
acknowledges durable deletion with an empty result before the caller returns.
This grants no token-reading permission or account visibility.

Implementation revisions are `fc640ffc6` (store), `f49137658` (C ABI bridge),
`732bac4e0` (protocol and broker), `44ab29c57` (decoded feature lifetime),
`52c676fe0` and `7a9390806` (framework APIs and `clearPassword`), and
`78701ae1e` (JNI and service dispatch).

Host validation passed for the maintained `accountstore/tokens_test.v`,
`accountclient/store_token_bridge_test.v`, and the invalidation tests in
`nativeaccountauth`, `accountbroker`, and `accountclient`, under
`build-support/android`. These cover actual SQLite persistence, limits,
password-purge rollback, null versus empty values, exact multi-account
invalidation, wrong types, expired/replayed capabilities, empty acknowledgments
and both store/authenticator close orders. The token store, bridge and request
lifetime suites also passed with `-gc none -manualfree` and AddressSanitizer
(`ASAN_OPTIONS=detect_leaks=0`). Framework source checks are maintained in
`tests/native-android-tools/check-account-token-cache.v`.

Host evidence is retained under `/Users/alex/.local/state/vinix/android`:

| Inventory or binary | SHA-256 |
| --- | --- |
| `accountstore-explicit-token-checksums.sha256` (7 token tests and 12 existing store tests) | `765cb1f572e838c24f3a2533f2aefff73fb6aff5472a0a03a8e7e794707b60b9` |
| `review-dispose-checksums.sha256` (request/authenticator lifetime suites) | `91b838aca13bf3a9ba56d3ac79f79c6e9347820993e3ad0e187773cd6a9ff241` |
| `auth-review-cache-provider-final` (framework source checker) | `9867e6f837233c61c75c567b3d4f643426ddfd4df1cb4aa587d69c4c029b3003` |
| `review-store-token-bridge-test` (3 bridge tests) | `ee504ea6209c6ac920e9ccf39c1e0910c6b2a44c150c9f4bdb96542c8ec99055` |
| `review-store-token-bridge-asan` (3 bridge tests) | `fb52ff88887c86ad47d699c61b883a8d4c1a50f6bffa4ab7c16db4ba1b6e1912` |

The signed ART fixture at source revision `bcd7cc1f4` is retained in
`/Users/alex/.local/state/vinix/android/account-token-fixture-2026-10-26-r5`.
Its `probe.apk` SHA-256 is
`bd79181ffa9fca598189a0382a8de5c40d83fc675318a609be3e2a7ad3ec0042`;
the complete `sha256.json` inventory SHA-256 is
`68812a0b80187d458ee53a8bc6a05634ef901cc680dd6b42fac2f061edaa6702`.
The bundle includes its builder, inputs, generated DEX, manifest and command
receipts. Its cache manifest declares a selected service and a separate normal
app for exercising the real APIs, followed by a service restart for persistence.
The four required markers are `ACCOUNT-TOKEN-CACHE-READY`,
`ACCOUNT-TOKEN-CACHE-CLIENT-PASS`, `ACCOUNT-TOKEN-CACHE-PASS` and
`ACCOUNT-TOKEN-CACHE-PERSIST-PASS`; require the complete marker text in
`build.json`, with no assertion, verifier or uncaught failure.

APK assembly and host tests do not establish ART execution or Google login.
Guest execution of this cache fixture is pending. Actual Google authentication
and Maps' separate GMS GetToken/TokenData path still require runtime evidence;
see [the token method audit](maps-token-method-audit.md) and
[the authenticated token route](account-token-route.md).
