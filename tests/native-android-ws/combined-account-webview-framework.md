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

The auth profile adds account token requests and native cookie clearing over the
sealed store profile above. The builder self-test, provider compilation,
assembly, canonical disassembly, exact method/class delta checks, and complete
retained-bundle verification passed. Exactly 2102 classes remain: AccountManager
adds five token methods without changing any existing method; CookieManager
changes its four clear APIs and adds `nativeClear(Z)Z`. All unrelated methods,
class/field metadata, other classes and non-DEX JAR members retain their content.
The original store bundle is verified before and after construction.

- Builder implementation commit: `b509163bf`.
- Token provider commit: `34cf9e5dc`; cookie clear provider commit: `ef43a13db`.
- Build source revision: `9bdaf6e1f39fd87da4029a52ab7c745cf75fb4f5`.
- Retained builder source SHA256: `7f92305c250f8c75b752474cea8a96ef3ed24943bd112a16fbe0578e88eb5f29`.
- Retained token provider SHA256: `dd96c9c2b63f4a9fbf04cf4f12ee1978d410e93b1a51cb8dfd675f211ac7267e`.
- Retained cookie clear provider SHA256: `fa8a3979ae381a9f57346f8d05065bf919f62b43fd42b607bebe083eb25e345a`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-auth-framework-2026-10-26`.
- Bundle manifest SHA256: `1299ddd064ebe89bae35cafd4c509794894c7466fda0bfaee2dfb85cf404d309`.
- Output `api-impl.jar` SHA256: `c677808eb55f58845b4ce3dd5c72be481d4ca585fd4980cec18266271d4740bf`.
- Output DEX SHA256: `f41992bf7dc921c00d869b7500096ebf7b97b766e18e41d91b3cc708633a5ba0`.

The auth driver was compiled with the same pinned compiler using
`-nocache -cc cc`. Its `--auth` invocation requires the exact store bundle and
manifest/JAR pins above. The bundle retains compiler and provider source
closures, executable/tool hashes, command receipts, both canonical inventories,
and output hashes; host SDK and dynamic libraries remain environmental inputs.
The maintained WebView checker also passed clear-all/session mode, backend
Boolean, caller Handler ordering, null callback, error propagation, idempotence,
malformed input and smali assembly checks. These checks establish framework
construction, not guest execution or successful Google account login.

The cache profile supplies the three token-cache APIs invoked by Maps and GMS:
`peekAuthToken`, `setAuthToken`, and `invalidateAuthToken`, plus the Java
`clearPassword(Account)` wrapper which calls `setPassword(account, null)`.
The `--cache` builder requires the exact sealed auth baseline above. Its self-tests, provider build,
assembly, canonical disassembly, strict method/class and JAR-member comparisons,
and a separate complete-bundle integrity check passed. All 2102 classes remain;
only `AccountManager` changes, adding exactly three public native methods and
one Java wrapper while changing zero existing methods. The baseline seal is
verified before and after construction.

- Builder implementation commits: `d5dc257d0`, `a45944940`; provider commit: `7a9390806`.
- Build source revision: `4dfcbdad505dd119da8149d5f3067c69d4079ae3`.
- Retained builder source SHA256: `4f39bd39a079ad06fd59aff0e9727a971a318e23f11a278c3393c8cbedd7acd9`.
- Retained cache provider SHA256: `7e52ef398747efad6c6885c4ef45f3faa6f2a6133e82b96f67ebbc7f439eac6b`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-cache-framework-2026-10-26-r3`.
- Bundle manifest SHA256: `f37e13b84b5dfb2c71ad852e2bae5b03fed04e8ee319f44e77fc7605f3b1994a`.
- Output `api-impl.jar` SHA256: `3a590476c53e3f05533c327c5935e395c55694eacb7895b02940feaf888c56d0`.
- Output DEX SHA256: `8cffe19b26057c8810065c0e137364b573a50e36a596ce7a3b34391511133902`.

The earlier three-native-method r2 bundle remains sealed at its original
location; r3 supersedes it by adding the missing password-clear wrapper.

The compiler and retained-input policy match the auth profile. These are host
construction checks; execution of the paired JNI implementation and Google
account sign-in require separate guest evidence.

The descriptions profile adds the real `AccountManager.getAuthenticatorTypes`
native API and the `AuthenticatorDescription` Parcelable with its creator over
the sealed r3 cache framework. The builder self-test, assembly, canonical
disassembly, exact delta checks, and complete retained-bundle verification
passed. Exactly one method is added to `AccountManager`, with no existing
method changed, and exactly two classes are added: 2102 classes become 2104.
All other classes and non-DEX JAR members retain their content. Both the
baseline and output complete file sets are checked.

- Builder implementation commit: `b97039546`; provider commit: `0a52b1112`.
- Build source revision: `a3e6718c3cc5e203e5ec3ecbdb197bd097c8d68a`.
- Retained builder source SHA256: `f5cee2f726d04edbe4280e671ba29ff4377c60ed23a17fbd8f00406452d78faf`.
- Retained descriptions provider SHA256: `0e960fc476dcd165a2e0b5152cfb1be5089f7e8a55968aec8f5607b2efc0ba91`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-descriptions-framework-2026-10-26-r1`.
- Bundle manifest SHA256: `d898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021`.
- Output `api-impl.jar` SHA256: `71d05c6e6288978de66a5c71279e8cb27d92c9166950813ddbf0c33ff86e1d0d`.
- Output DEX SHA256: `447731834498597a51d47ff08bfe18837fa6587d841b247d5feb626d5d907d28`.

The profile retains the same pinned compiler and input policy as the cache
profile. These host construction checks require paired JNI and account-broker
guest validation before establishing authenticator discovery or Google login.

The protected-storage profile (`--protected-storage`) extends exactly the sealed
2104-class descriptions baseline above. Its self-tests, provider compilation,
assembly, canonical disassembly, exact member/class comparisons and complete
bundle integrity checks passed. No classes are added or removed. Only these
four classes change:

| Class | Existing methods changed | Methods added | Fields added |
| --- | ---: | ---: | ---: |
| `ApplicationInfo` | 1 (copy constructor) | 1 (`vinixSetDataDirectory`) | 2 public String fields |
| `Context` | 2 (`<clinit>`, `getDataDirFile`) | 0 | 0 |
| `ATLLoadedAppManager` | 2 (application metadata loaders) | 0 | 0 |
| `ContextImpl` | 1 (`createConfigurationContext`) | 0 | 0 |

The two fields are `credentialProtectedDataDir` and `deviceProtectedDataDir`.
Every unrelated method, class/field declaration, other class and non-DEX JAR
member retains its content. Mutation tests reject missing/duplicate/preexisting
fields, changed field access, class substitutions and missing required
class/method changes. Historical 2102-class profile checks remain strict.

- Provider implementation commit: `2045b466e2a032586a699d67379be3daec61dc15`.
- Build source revision: `8fa48d6081fbc1fa95e3e335b0c1e04bf288bc97`.
- Retained builder source SHA256: `1ee342ad30e1f18c0e115faf5e597810d6ad4c3f3eba8e5e176abc94cc81d373`.
- Retained provider SHA256: `860607d9f13a74dff4a1ef93bfb47614fdab096f9fd7bee450b374b22fec4772`.
- Complete retained bundle: `/Users/alex/.local/state/vinix/android/combined-account-webview-protected-storage-framework-2026-10-27-r2`.
- Bundle manifest SHA256: `67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938`.
- Output `api-impl.jar` SHA256: `a8ba34eb79be2473f89042c8ee940ab1994dbc902c3d45143877f8891d3b428b`.
- Output DEX SHA256: `2739569a157276b76da82ed51ce41ef805457f95c01fe23ec524b5666bd486c6`.

This narrow host build retains the pinned compiler/source closure policy above,
uses APFS clones of canonical baseline smali, and caps each smali JVM at 512 MiB
with two workers. Device-protected storage is a distinct private child directory
within Vinix's app root; there is no separate Android encryption/unlock lifecycle.
These checks establish framework construction. Paired native execution, the
storage fixture in ART and actual Google account sign-in need guest validation.
