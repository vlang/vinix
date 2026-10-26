# Authenticator description JNI validation

The native `AccountManager.getAuthenticatorTypes()` binding submits operation 6
to the authenticated account broker and accepts the matching terminal metadata
snapshot. It constructs actual `AuthenticatorDescription` values, including all
four resource IDs and `customTokens`, and bounds the synchronous query to five
seconds. Failures throw; an empty array requires an authenticated empty snapshot.

Production source `build-support/android/nativews/account_authenticators.v` has
SHA-256 `05afd8a239fa8536af965f755e4aa437b9960f769114cf92eacdb1e2b5a1426c`.
Checker revision `b91a7c903` extracts this source into an instrumented host JNI
fixture. The production fixture passed, and all 15 independently compiled
negative mutations were rejected. Coverage includes request identity and kind,
count bounds, borrowed string lifetimes, signed resource bit patterns, allocation
and JNI failures, pending exceptions, local references and client cleanup.

Retained evidence is
`/Users/alex/.local/state/vinix/android/check-account-authenticators-2026-10-26-r1`.
Its `sha256.json` seal is
`e9db80e2b1414779c6787542f8d5ac8865b28d994cab2faa9e021124ddfdf082`;
`evidence.json` is
`191c92c124b3a44330d81e60c24b0b65fc89803fc9307288479718245f012dc8`.
The complete source snapshots, compiler receipts, builds and individual runs are
retained there. These are host behavioral checks; they do not establish an ART
run or successful Google account login.
