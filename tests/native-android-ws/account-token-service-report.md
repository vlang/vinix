# Authenticator token dispatch

Production change: `2aa600176`. Checker: `8091a3d14`.

The service authorizes the exact retained account and requesting package against
the private account store before initializing APK classes. An authorized request
calls the real `IAccountAuthenticator.getAuthToken` with its registered callback,
an `Account`, token type and original scalar options. Denial returns error 7.

Host verification passed:

- Actual-source token copying, authorization, Bundle and Binder dispatch, plus
  12 compiled negative mutations.
- Existing store/query adapter with 11 compiled negative mutations.
- Existing callback continuation, terminal response, replay, cancellation,
  shutdown and scoped identity checks.

Token audit bundle:
`/Users/alex/.local/state/vinix/android/account-token-service-check-2026-10-26-r4`.
Its `sha256.json` hash is
`94754b9d16e4b8b9da83798ebb3946f823e08767baa4b31168a8fcf935a12cc6`.
Tested service source hash:
`fe7b63fbe36d6f0799730612add0c7303dca69d5ad7b8f4f14fdd95ace8a29dd`.

This verifies dispatch and ownership using instrumented host JNI and transport.
It does not establish guest execution or successful Google authentication.
