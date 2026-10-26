# Combined account and WebView framework

The maintained V builder is `combined-account-webview-build.v`. Its `--self-test`
rejects unrelated class changes, omissions, substitutions, missing required
changes/additions, JAR member changes, and malformed or duplicate helper inputs.

The 2026-10-26 build passed assembly and canonical disassembly checks: 2098
baseline classes became 2101 classes, with exactly eight changed classes and
three additions. Every other class and every non-DEX JAR member retained its
SHA256. This validates framework construction; it does not establish ART
execution or Google account login.

- Source revision: `82bb77facbd9d784af11267c7d72880ac54b6941`.
- Builder source SHA256: `67d6094f355dd378e7f6432ef63138854ad6db13bcf855655a7e98317e81a773`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-framework-2026-10-26`.
- Bundle manifest SHA256: `798b574b811203313b185480ddfd9349bfc5b7e1863d96e99d9c1afca3be4dd2`.
- Output `api-impl.jar` SHA256: `296cb0bd9d16801322a18d40bca0facfb0593e50be47d424f199d02ceeb7e15f`.

The bundle retains builder/provider source closures, tool JARs, executable and
input hashes, command receipts, both canonical class inventories, and output
hashes. `combined-account-webview-build --check BUNDLE MANIFEST_SHA256` verifies
the complete retained file set. The pinned baseline is
`account-contract-authenticator-base-network-build-2026-10-26`, with manifest
`36a472320e71eb459896c1d52a8f211f475362fb2c6dada682870bf43b6a2b7b` and JAR
`9e643451d4d82fc3839c91415947f04d3726aa81967a784d4d26db63e2c88cb1`.

The subsequent interaction build also passed assembly, canonical disassembly,
and full retained-bundle verification. It produces 2102 classes from the same
2098-class baseline, with exactly eleven changed classes and four additions.
The new `VinixAccountInteraction` extractor uses three accessors appended to
`PendingIntent`, `AccountAuthenticatorResponse`, and `Bundle`; removing each
accessor leaves its baseline canonical class unchanged. All remaining classes
and non-DEX JAR members retain their original SHA256. Builder self-tests reject
missing, duplicate, malformed and preexisting accessors, and unrelated method or
superclass changes. These are host construction checks; ART execution and Google
account login remain separate validation.

- Builder implementation commit: `88e12dc5a`.
- Build source revision: `a03cd9975048693643652fc8415ab700cf18c5a5`.
- Retained builder source SHA256: `7f331e4a68824d40ed9b5c7a82c5f669ca4f5a49bd3027ffd91fa579ecb38835`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-interaction-framework-2026-10-26`.
- Bundle manifest SHA256: `dc5c0470c4cdc7a075ded61680e4ac89cef056dbcb515ce55a32f74bf82aef87`.
- Output `api-impl.jar` SHA256: `86278c9cbe1f25904b760250f34f859206d719cbb23cf5ff5411a75c480ac36f`.
- Output DEX SHA256: `7b7684d768573672a47b3a26d3cf82e9ee0f87feecdccf429e6fe053ae93e0ba`.

The account store profile passed the builder self-test, assembly, canonical
disassembly, and complete retained-bundle verification. The `--store` mode
requires exactly the sealed interaction baseline and its pins above. It applies
the committed AccountManager storage provider (`230ddc24f`) to a fresh copy:
2102 classes remain, with only `AccountManager` changed. Exactly four existing
methods change and eight methods are added; unrelated methods, class/field
metadata, other classes, and non-DEX JAR members retain their content. The full
original baseline seal is verified before construction and again afterward.

- Builder implementation commit: `97490a023`.
- Build source revision: `9a3ebced53c7367d42b310d7f5b694657a7ce542`.
- Retained builder source SHA256: `9c6186716dd99ab76e3d5161e35bf76dd6f03cac04a8e3ca9e692be94b99f418`.
- Retained store provider SHA256: `427f412c37e46a977c068ae56fffa489c3d8087c952b76c03b5b00c3ead5fbd1`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-store-framework-2026-10-26`.
- Bundle manifest SHA256: `7cc408299a3a7d37578735e79b31c5c2ff96dbd1de00a2d7dd0d1e149b156690`.
- Output `api-impl.jar` SHA256: `9e89db595defb905b0322183f176613f2b42f951ec1b51d4ceb91431876c3c8e`.
- Output DEX SHA256: `b93c8b664c313c7dca70e5adf5e8f6f6a21b831161700ea3be9e0a265766f9f8`.

The driver was compiled with the frozen compiler
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, using
`-gc none -nocache -cc cc`; the compiler SHA256 is
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
The bundle retains the driver and provider source closures, full helper input,
compiler executable, smali tool JARs, commands and executable hashes, before/after
class inventories, and output hashes. Host SDK and dynamic libraries remain
environmental dependencies. These host checks establish framework construction;
guest execution and Google account login require separate evidence.
