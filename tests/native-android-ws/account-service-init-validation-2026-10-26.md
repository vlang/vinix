# Authenticator startup diagnostics, 2026-10-26

The native service startup now emits a bounded diagnostic on failure before
ART starts the authenticator. Stages distinguish descriptor parsing, mutex
initialization, peer syscall/identity checks, library loading, symbol lookup,
authenticator-channel opening and account-store opening. Error codes are
captured before cleanup or `dlerror()` can replace them. Loader text is reduced
to a fixed category; raw paths, symbol names, account values and tokens are
never logged. Successful startup remains silent.

The production source has SHA-256
`5a9af144d2d8f16c1a9a67a452d022892142e8db1711fe5d751310e85837a858`.
Checker source is committed at `32bd5b66e` in
`tests/native-android-ws/check-account-service-init.v`. It extracts the actual
initializer and diagnostic helpers, then instruments native boundaries.
Normal and AddressSanitizer runs passed 45 startup cases, 13 bounded loader
cases and three logger cases. Five compiled negative mutations were rejected.
Tests include errno changes in both `dlerror()` and `close()`, descriptor and
peer rejection, every missing symbol, stage-specific failures and sensitive
loader text. ASAN used `detect_leaks=0`; these checks do not establish leak
freedom. The production change and checker received independent review.

Evidence is retained at
`/Users/alex/.local/state/vinix/android/account-service-init-2026-10-26-r3`.
Its `sha256.json` SHA-256 is
`3874b81c1f92198847fc6791d5319ab260c009882de52260732084a2b9dc36ad`.

The next real guest run must establish which startup stage failed. These host
checks do not establish ART startup or completed Google account login.
