# Complete current JNI provider

The full current `atlframework` and `nativews` provider builds and links for
AArch64 against the sealed 2,102-class interaction framework. The snapshot is
at source revision `6d2639b7a0486823456cecd33ef74519a70d8787`, including the
account UI and authenticator stack-argument fixes in `9a695e490` and `6ac0a29da`.

The complete audit bundle is
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-26-r13`.
Its `sha256.json` SHA-256 is
`78a39e3f3830e0671c95a7d42f81f5985e929ababb36951cd1f323a5c2e2a7f6`.
The maintained builder is `build-current-native.v`; the exact retained builder
source SHA-256 is
`50993d22182ae3a5b927b57dc6fcb95bd9dafe32368e0375c5cbddb90d588fb1`.

| Input or output | SHA-256 |
| --- | --- |
| `native/libvinix-android-native.so` | `66ad7731707c9eeb4639d75838a002a680180e19f75aa13ccb75bbe23ef1d371` |
| Framework `sha256.json` | `dc5c0470c4cdc7a075ded61680e4ac89cef056dbcb515ce55a32f74bf82aef87` |
| Sealed r5 dependency `sha256.json` | `d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e` |
| `native/atlframework/headless.v` | `c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57` |

The framework input is
`/Users/alex/.local/state/vinix/android/combined-account-webview-interaction-framework-2026-10-26`.
The dependency input is
`/Users/alex/.local/state/vinix/android/headless-service-native-build-2026-10-26-r5`.
This build replaces the JNI library only. Deployment must pair it with the
current seven-argument service entry executable; the old r5 entry is incompatible.
The executable bundle's retained `abi/headless.v` must match the hash above.

Validation completed:

- Actual `-Wall -Wextra -Werror -shared -fPIC -Wl,--no-undefined` cross-link,
  followed by ELF64 AArch64 shared-library checks. The existing runtime DSOs
  retain their own dependency resolution through `--allow-shlib-undefined`.
- Exact defined-symbol comparison: 702 source exports plus the sealed GCC
  startup exports `_init` and `_fini`, with no missing or extra symbols.
- Every consumed C header checked against copied local headers or the sealed
  cross-toolchain dependency inventory, with hashes checked before and after.
- Binding checker `a03cd9975`: 615 entries and 616 generated exports, including
  exact native signatures, JNI widths and rejection of Java dispatch bindings.
  Final log: `native-bindings-full-check-2102-final.log` in the external state
  directory. The binding spec SHA-256 is
  `52e6b203e945639b954961fa7237feb98c1f328549a778db529248d859520626`.
- Builder self-tests reject malformed header dependencies, incomplete source
  closures, unsupported helper-object paths and concurrent source additions.
- Independent read-only builder review; its source-membership and cached-helper
  input findings were fixed before this successful build.

The bundle retains all provider sources, regenerated bindings, bound framework
smali, generated C, compiler binaries, source dependency copies, native helper
objects, exact command receipts and output hashes. The pinned compiler compiles
the builder and generator from live source paths, guarded by exact source lists
and before/after hashes. These host compilation inputs are copied into the
bundle, including sibling C sources and the actual cached helper objects from
`-showcc`. JNI generation consumes the copied provider snapshot. This policy is
recorded in `build.json`; it is not a claim of an isolated compiler filesystem.

To reproduce with the preserved compiler and dependencies:

```sh
/Users/alex/.local/state/vinix/android/headless-service-native-build-2026-10-26-r5/tools/v_old276 -gc none -nocache -path '@vlib|tests/native-android-tools' -o /Users/alex/.local/state/vinix/android/build-current-native tests/native-android-ws/build-current-native.v
/Users/alex/.local/state/vinix/android/build-current-native --self-test
/Users/alex/.local/state/vinix/android/build-current-native /Users/alex/.local/state/vinix/android/combined-account-webview-interaction-framework-2026-10-26 /Users/alex/.local/state/vinix/android/current-native-build-FRESH
```

Use a fresh output path. This report qualifies the complete native cross-build
and source/binding audits. Guest account interaction, browser input, Maps login
and the requested running screenshot require separate execution evidence.
