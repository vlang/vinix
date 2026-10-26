# Current seven-argument launch executables

The current entry, launcher and headless lifecycle controller cross-build and
link for AArch64. The retained source revision is
`bddf43de8a2f443e711f24863847f8135658d7d5`. This includes the typed browser
wait-status binding fix and the explicit static startup-object pin.

The complete audit bundle is
`/Users/alex/.local/state/vinix/android/current-launch-build-2026-10-26-r9`.
Its `sha256.json` SHA-256 is
`e94c9fc2262bc1c19857e406e250db739bf106034d36559190215cbfb7399b58`.
The maintained builder is `build-current-launch.v`; the retained builder
source SHA-256 is
`fb0c1700fe60d0b041db97f609dc0726d11ca2bf8b44113886dfdab81c900640`.

| Output | SHA-256 |
| --- | --- |
| `bin/vinix-android-native` | `f8b55b3aacadd45168b13e18fb91b9a58a56da1a73a1749ab0f9873f9c2fdb65` |
| `bin/run-android` | `7f2778c013203581cccd7fd9b5aabf59607d0580c39a3b63876fb3a5926133e1` |
| `bin/headless-service-controller` | `eb30bb51147019c5b77d7a7a7029958efe922fd7a1cef24692d22916d59a0d75` |

The entry uses the seven-argument `vinix_android_native_service_main` ABI.
Its retained `abi/headless.v` SHA-256 is
`c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57`,
matching the JNI source in `current-native-build-2026-10-26-r13`. The entry is
a dynamic ELF executable; the launcher and controller are static ELF
executables. All three have valid ELF64 AArch64 program headers.

The build pins these input manifests:

- The 2,102-class framework bundle at
  `combined-account-webview-interaction-framework-2026-10-26`, seal
  `dc5c0470c4cdc7a075ded61680e4ac89cef056dbcb515ce55a32f74bf82aef87`.
- The native dependency bundle at
  `headless-service-native-build-2026-10-26-r5`, seal
  `d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e`.
- The retained V compiler, SHA-256
  `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.

The bundle retains exact V source lists, module metadata, selected native
sources and headers, compiler binaries, host helper objects, generated C,
separate Unix signal-runtime objects, command receipts and output hashes.
Generation uses the copied compiler and source closure, with its working
directory set to the retained compiler root. The supported exclusion of
`crypto/rand/internal/rand.wasm.v` keeps the target's Linux entropy provider
as the sole implementation. Host helper compilation records and verifies
the actual cached object inputs selected by `-showcc`.

Validation completed:

- Actual target C compilation with implicit-function and integer-conversion
  errors enabled, followed by dynamic/static links as specified above.
- Consumed header and linker-input audits against retained or sealed inputs,
  including `crtbeginT.o`; before-and-after input hashes; full bundle inventory.
- Builder self-tests for dependency parsing, incomplete source closures,
  helper-object paths, the seven-argument ABI and ELF program headers.
- Executed entry parser and ABI checker, including rejection mutations
  (`1e1d8501a`); account/UI lifecycle pump checker with 28 cases and 17
  mutations (`1dc0393f3`).
- Browser process ABI regression (`fb40158df`): real host child-process waits,
  strict ARM64 compilation and rejection of the old conflicting `waitpid`
  declaration. Evidence is retained at
  `/Users/alex/.local/state/vinix/android/browser-process-abi-2026-10-26b`.

This qualifies the executable build and its ABI coupling. The bundle was
handed off for guest execution. Maps login, account persistence and the
requested running screenshot require separate guest evidence.
