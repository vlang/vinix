# Current account transport and store library, 2026-10-26

The retained-source AArch64 account library build passed, including the SQLite
account store, token cache and synchronous token invalidation. This is build
and host behavior evidence; Google account login needs separate guest evidence.

The complete audit bundle is outside Git:

`/Users/alex/.local/state/vinix/android/current-account-build-2026-10-26-r5`

- `sha256.json`: `bbeed05835e6d90741cf9a396bafc85df36ea5c790eee2b64f6e60c9dccee1ff`.
- `lib/libvinix-android-account.so`: `4f8f4befd59ffe90432df24b040f696c186ecbf829814a59e96379610e90f0c9`.
- `lib/libsqlite3.so.0`: `5a228127ca3ffa0c88bcae0aa5f7ab10e15b383dfb46822c573013105628bbaa`.
- Source revision: `bcd7cc1f4e8834d7436e2a7266cd56caba46525f`.
- Retained `build-current-launch.v` source: `32e511836b18abe6680c76748bf2f3f8ef40e52852dcf52b79c595c4e3109f7b`.
- Compiler: `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
  from `/Users/alex/code/v-tccbin-bootstrap-20261026/v` and its paired V library.
- Native dependency bundle: `headless-service-native-build-2026-10-26-r5`, seal
  `d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e`.

The snapshot contains the committed core cache (`fc640ffc6`), account-client
bridge (`f49137658`), operation-5 protocol (`732bac4e0`) and decoded request
ownership fix (`44ab29c57`). Password changes purge cached tokens. The library
exports the explicit peek/set/invalidate ABI, authenticated session invalidation
and its acknowledgement, token request construction and Activity redemption.
All 69 public functions declared by the frozen client sources are present as
defined text symbols. This checks ABI completeness, not exclusive symbol scope.

`build-current-launch.v --account FRESH_OUTPUT` retains and recompiles its own
builder source closure, then captures the account source closure. Generation
uses retained compiler/source copies. Native compilation enables implicit
declaration and integer conversion errors; the PIC shared link uses `-z defs`.
ELF64 AArch64 shared output, SQLite dependency, consumed headers, toolchain
objects, source membership and before/after input hashes all passed validation.
Exact commands, generated C, link receipts, compiler/helper inputs and all
output hashes remain in the complete bundle. Host SDK and dynamic libraries
remain environmental inputs.

The SQLite core passed seven new normal/AddressSanitizer cases and twelve
existing cases. Its retained inventory is
`/Users/alex/.local/state/vinix/android/accountstore-explicit-token-checksums.sha256`,
SHA-256 `765cb1f572e838c24f3a2533f2aefff73fb6aff5472a0a03a8e7e794707b60b9`.
The decoded request, authenticator and disposal regressions passed normally and
under AddressSanitizer, with inventory
`/Users/alex/.local/state/vinix/android/review-dispose-checksums.sha256`,
SHA-256 `91b838aca13bf3a9ba56d3ac79f79c6e9347820993e3ad0e187773cd6a9ff241`.

The actual JNI cache adapters passed maintained host checkers (`0cd01c098`)
with 35 compiled negative mutations. Store coverage includes ownership,
nullable and empty tokens, exact session identity, durable invalidation ACKs,
wrong replies, failure and timeout. Service coverage verifies native operation
5 bypass without copying token secrets into Java. Their retained bundles are:

- `/Users/alex/.local/state/vinix/android/account-store-cache-native-check-2026-10-26-r2`,
  seal `ea2bd7525681b7df2a3268eda78aa2b7a3c320e691843104f23a6a3cb7320a1d`.
- `/Users/alex/.local/state/vinix/android/account-cache-token-service-check-2026-10-26-r1`,
  seal `641fdda469552d85e7bdc534b87bf74244dc0d4cd2dc00dbfd174797091b7bfa`.

Install the account library and retained SQLite library together under
`/opt/vinix-android-aarch64/usr/lib/`, paired with JNI containing `78701ae1e`
and the final cache framework. Preserve the frozen headless staging baseline
and use a separate additive overlay. Older pre-store r3 evidence remains at
its original external location. This cross-build did not exercise credentials
or establish successful Maps sign-in.
