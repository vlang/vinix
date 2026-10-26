# Complete current JNI provider

The r17 provider adds numeric browser transport startup diagnostics from
`16f020ef0` to the descriptions framework build. The strict AArch64 compile,
shared link, exact source export comparison and consumed-header checks pass.
The source and compiler dependency policy remains unchanged.

- Complete retained bundle: `/Users/alex/.local/state/vinix/android/current-native-build-2026-10-26-r17`.
- Bundle `sha256.json`: `77503d184cc53fe3527f1949f7b88648b5a6bacd1e6b74bd82acb82fec222419`.
- `native/libvinix-android-native.so`: `70b8db58c59d769f4f4ae4e6775fb7c3a2c4c9af42cfd3f14076092ec14818c0`.
- Source revision: `13783410eccce99c8903c38cd2defee2b7353d75`.
- Retained `native/atlframework/webview.v`: `a41bacd6b18a0332daca5e0ccd2beb324d1f6ac5f2acccd81feba695607f7859`.
- Retained builder source: `1f68bc792e31031f9312ea2d9b26fb2dedf060c58c59f6357eb57476cdaf1015`.
- Descriptions framework `sha256.json`: `d898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021`.

The independent `build-bundle-check.v` check verifies all 1,196 retained files
against the exact manifest. Receipt:
`/Users/alex/.local/state/vinix/android/current-native-build-r17-audit.json`,
SHA-256 `70349433df94dba32db2f5c6d3c83de8f39b982feb7b5783101fd8dc9b676793`.
The maintained builder self-test passed before this build. These results do
not establish guest browser startup or successful Google account sign-in.

## Previous r16 evidence

The r16 complete `atlframework` and `nativews` provider passed the strict
AArch64 shared build against the 2,104-class descriptions framework. It adds
the real `getAuthenticatorTypes` adapter from `56cdb03c0`, converting bounded
broker metadata into `AuthenticatorDescription` objects and preserving the
existing account cache and authenticator dispatch.

- Complete retained bundle: `/Users/alex/.local/state/vinix/android/current-native-build-2026-10-26-r16`.
- Bundle `sha256.json`: `1859b2df1af3e5140284ec6d19a2d4378d6193c29c872f280b129713a5d5982f`.
- `native/libvinix-android-native.so`: `b2f88fd605c03eaa1cc37c7d29bdb3657110d9f7eebef43f155a6c0351555bac`.
- Source revision: `f324182c30ce9997d06323582fc9f86566a2f85c`.
- Descriptions framework `sha256.json`: `d898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021`.
- Retained binding spec: `60b590a07c627bd3ff8d57f1edaf5c0bd2e06c44124c7f808c6f5701f5bb3bbe`.
- Regenerated JNI bindings: `3961844aee7e624ec9d746b4a6c16d83e691bef4188d6e42e070c8ae5e36af00`.
- Retained descriptions adapter: `05afd8a239fa8536af965f755e4aa437b9960f769114cf92eacdb1e2b5a1426c`.

The builder self-test passed, followed by the actual strict compile/link,
ELF, consumed-header, source membership and before/after input checks. All
715 source exports plus `_init` and `_fini` match exactly; 628 binding entries
produce 629 generated exports. The seven-argument `headless.v` ABI remains
`c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57`.
The compiler and r5 dependency policy below is unchanged. Pair this JNI output
with the descriptions framework, r6 account library and rebuilt broker and
launcher. These host checks do not establish guest authenticator discovery or
successful Google account sign-in.

## Previous r15 evidence

The full current `atlframework` and `nativews` provider passes the strict
AArch64 shared build against the 2,102-class cache framework. It includes
`peekAuthToken`, `setAuthToken`, broker-acknowledged `invalidateAuthToken`,
owner checks, nullable token handling and the authenticator native dispatch.

The complete audit bundle is
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-26-r15`.
Its `sha256.json` SHA-256 is
`540a2cfa43ed7867ca5eebc14ff1577ca49081ce31788558b8784c0ea763325f`.
The captured revision is `827f336c71e8d2b35578ead28c43511d138fe6df`;
the exact retained sources and working-tree receipt describe the snapshot.
The maintained builder is `build-current-native.v`, retained source SHA-256
`50993d22182ae3a5b927b57dc6fcb95bd9dafe32368e0375c5cbddb90d588fb1`.

| Input or output | SHA-256 |
| --- | --- |
| `native/libvinix-android-native.so` | `a175fe79b8aadc634c44294c423dd380f1c4141f6561a8e329e71226b76b4d86` |
| Cache framework `sha256.json` | `f37e13b84b5dfb2c71ad852e2bae5b03fed04e8ee319f44e77fc7605f3b1994a` |
| Sealed r5 dependency `sha256.json` | `d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e` |
| `native/atlframework/headless.v` | `c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57` |
| `native/atlframework/account_client.v` | `6336469822cf308f3ce595dfa47db4ed01cc08444668dc4230cdd16c477da96a` |

The framework is
`/Users/alex/.local/state/vinix/android/combined-account-webview-cache-framework-2026-10-26-r3`.
The dependency input is
`/Users/alex/.local/state/vinix/android/headless-service-native-build-2026-10-26-r5`.
Deployment must pair this JNI library with a seven-argument service entry
whose retained `abi/headless.v` matches the hash above.

Validation completed:

- Actual `-Wall -Wextra -Werror -shared -fPIC -Wl,--no-undefined` cross-link
  and ELF64 AArch64 shared-library checks. Existing runtime DSOs retain
  their own dependency resolution through `--allow-shlib-undefined`.
- Exact defined-symbol comparison: 714 source exports plus `_init` and
  `_fini`, with no missing or extra symbols.
- Every consumed C header checked against copied local headers or the
  sealed cross-toolchain inventory, with before-and-after hashes.
- Binding checker: 627 entries and 628 generated exports against the final
  framework. Spec SHA-256
  `6af30e63b6c849372ea1d2a4e3e30e225b24142c5bbe58fc1accdb02d1ce4320`;
  generated bindings SHA-256
  `149e738ab0419f724d7cf79ee8ebb901607753ac74121f45efedc512ee4ade7e`.
- Store and token-service native checkers execute production adapter code
  and reject 20 and 15 mutations respectively. Their complete bundles are
  `account-store-cache-native-check-2026-10-26-r2` (seal
  `ea2bd7525681b7df2a3268eda78aa2b7a3c320e691843104f23a6a3cb7320a1d`)
  and `account-cache-token-service-check-2026-10-26-r1` (seal
  `641fdda469552d85e7bdc534b87bf74244dc0d4cd2dc00dbfd174797091b7bfa`)
  under the external state directory.
- Builder self-tests reject malformed header dependencies, incomplete
  source closures, unsupported helper objects and source membership drift.

The previous r14 attempt is preserved: old V emitted an unavailable
`memdup` for an escaping fixed-size interaction ticket. The r15 source
uses explicit checked allocation and deferred cleanup on every return;
the callback and redemption encoder borrow the buffer synchronously.
Independent lifetime review passed. Checker `41f1ae89a` executes the
production body with ticket-only allocation and cleanup spies: allocation
failure, success, partial callback failure and redemption failure all pass
normal and ASAN runs. Its complete bundle is
`/Users/alex/.local/state/vinix/android/review-account-client-ticket-r15b`,
whose `sha256.txt` SHA-256 is
`c7546378c8ed101871f587b2f07b796475565f8daf2aa2610d7a6c5e9e9d3ec7`.
Ordinary `memset` before `free` is not a guarantee of a non-optimizable wipe.

The bundle retains all provider sources, regenerated bindings, framework
smali, generated C, compiler binaries, dependency copies, helper objects
and command receipts. Host builder/generator compilation uses guarded
live source paths with exact listings and before-and-after hashes;
JNI generation consumes copied provider inputs. This is the recorded
source policy, rather than an isolated compiler-filesystem claim.

Reproduce with the preserved compiler and fresh external output:

```sh
/Users/alex/.local/state/vinix/android/headless-service-native-build-2026-10-26-r5/tools/v_old276 -gc none -nocache -path '@vlib|tests/native-android-tools' -o /Users/alex/.local/state/vinix/android/build-current-native tests/native-android-ws/build-current-native.v
/Users/alex/.local/state/vinix/android/build-current-native --self-test
/Users/alex/.local/state/vinix/android/build-current-native /Users/alex/.local/state/vinix/android/combined-account-webview-cache-framework-2026-10-26-r3 /Users/alex/.local/state/vinix/android/current-native-build-FRESH
```

This qualifies the complete native cross-build and adapter audits. Guest
account persistence, Maps Google login and the running screenshot require
separate execution evidence.
