# Authenticated AccountManager token route

The bounded request operation `get_auth_token` carries the exact account name,
account type, token type and scalar options. It preserves the existing query,
addition and interaction-redemption wire formats. The broker forwards the
kernel-authenticated caller and issues a fresh response capability.

Before calling APK code, the selected authenticator checks the retained
session, its five-minute deadline, the exact account and the caller package's
current persisted visibility. It then calls the real
`IAccountAuthenticator.getAuthToken(response, Account, String, Bundle)`.
Only a callback authenticated by the original session capability can complete
the caller's future. Scalar token and expiry values pass through unchanged.
Interactive token responses use the existing single-use opaque redemption
route and require the requesting Activity.

The separate normal-library builder export is
`vinix_android_account_token_request(id, name, type, token_type)`; all text is
copied before return. The service additionally requires
`vinix_android_authenticator_account_name` and
`vinix_android_account_store_token_authorized`. The latter returns zero only
for an authorized live request. Native binding commit `190f80a4c` matches the
provider in `34cf9e5dc`; service dispatch and its actual-source checks are in
`2aa600176` and `8091a3d14`.

Validation covers bounded decoding and every truncation, UTF-8 identity,
reserved caller options, real SQLite visibility and revocation, expired and
retired sessions, wrong response capabilities, exact scalar forwarding and
single-use token interaction redemption. The native client checker executes
the extracted production entry and lifecycle functions, including optional
Activity ownership, callbacks, cancellation, timeout and shutdown. Its result
is retained at
`/Users/alex/.local/state/vinix/android/account-token-client-check-2026-10-26-r2`,
including the production source, checker, generated harness, log and checksum
inventory. The account client token tests also pass with `-gc none -manualfree`
and AddressSanitizer.
The maintained test sources are `nativeaccountauth/token_test.v`,
`accountbroker/token_test.v`, `accountbroker/interaction_test.v`,
`accountclient/token_test.v` and `check-account-client.v`.

This route performs no token caching or synthetic token generation. Failure
notifications, token invalidation/storage APIs and Maps' separate GMS
GetToken/TokenData service path remain separate work. Host fixture success
does not establish a Google login. Real guest interaction and an actual GMS
response still need to be observed without recording credentials or tokens.
