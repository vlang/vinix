# Browser cookie snapshots

`browsercookies` stores a complete cookie enumeration supplied by the real WebKit
engine. It preserves session cookies, exact UTF-8 strings, expiry, secure,
HttpOnly and SameSite attributes. WebKit remains responsible for cookie policy.

`open` requires a canonical private directory owned by the current UID. `replace`
commits an atomic complete snapshot, including an empty list, using SQLite DELETE
journaling and verified synchronous=EXTRA. Errors propagate to the caller.
Snapshots are bounded to 4096 cookies, 64 KiB per field and 4 MiB total payload.
SQLite loads dynamically; `required_symbols()` declares its audited symbol set.

`load` returns owned strings and an owned array. Call `dispose_cookies` exactly
once after the engine has copied them. `dispose` requires sole Store ownership.

The implementation and 14-case suite were validated at source commit `29c50ef22`;
the related account-store lock correction is `0b1c5730d`. Current and older V
compilers passed with `-gc none`; AddressSanitizer passed with leak detection
disabled. Actual AArch64 generated test fixtures passed GCC checks with
incompatible pointers, implicit declarations and integer conversions treated as
errors. Existing unrelated compiler warnings remain. Independent source review
covered dynamic ABI, ownership, filesystem checks and transaction durability.

Source snapshots, hashes, commands and observations are retained outside Git at
`/Users/alex/.local/state/vinix/android/browsercookies-audit-2026-10-26-bundle`.
The `audit.json` SHA-256 is
`a2abecc73aa4979a86285cfd0eac146698ed39ee4911164eaef63d0f9f9083c1`.
These checks cover the store; they do not establish successful Google login or
replace guest WebKit integration tests.
