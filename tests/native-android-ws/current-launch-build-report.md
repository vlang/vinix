# Current seven-argument launch executables

The r13 entry, launcher, headless lifecycle controller and account broker
passed the retained-source AArch64 build against the 2,104-class descriptions
framework. The broker captures the real APK authenticator metadata query and
resource parser; all four targets use the retained static zlib dependency.

- Complete bundle: `/Users/alex/.local/state/vinix/android/current-launch-build-2026-10-26-r13`.
- Bundle `sha256.json`: `920ed6f1a5f5d9e705bdcc108937db6266066718fe4203859a6ac8577bd405be`.
- Source revision: `9d5323f685730e4c015eb7fef7d3fa39173fced6`.
- Retained builder source: `6373dd5181bcdea1fc91185c09b79cff222890744ab4e05ac96a822f730c30fa`.
- Descriptions framework `sha256.json`: `d898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021`.
- Original complete zlib producer `sha256.json`: `f2652acfdf8963998d51d767990ac72daae4c54a9ee6e956327cdf2ee462272f`.
- Consumed static zlib archive: `40238b02e19ba4776180f997828faadddc5347f379b70b031ef8629b6e75fee0`.

| Output | SHA-256 |
| --- | --- |
| `bin/vinix-android-native` | `b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d` |
| `bin/run-android` | `1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112` |
| `bin/headless-service-controller` | `70f23b12fb5a770587bfcebcf33ed1320fe050399f08bd256362a037f24eb0b6` |
| `bin/native-account-broker` | `b674064be8d3635ee7433bef2c1894fa5fe045674ed0e98cf7d3215adca66a4d` |

The pinned compiler, r5 dependency input, seven-argument ABI, exact Linux
wait-status correction, source closure, consumed headers, strict declaration
and conversion checks, native signal objects, ELF checks and before/after
input checks follow the policy below. The original complete zlib producer
was revalidated before and after use; the consumer retains its full inventory,
provenance and the exact headers and archive it consumed. The entry is dynamic
and the other three executables are static. Pair these with JNI r16 and account
r6. Host validation does not establish successful Google account sign-in.

## Previous r12 evidence

The current entry, launcher, headless lifecycle controller and production
account broker cross-build and link for AArch64. The retained source revision
is `e9505d350b11fd936401c85aa645cb954bc1f894`; the bundle records the exact
working-tree source closure alongside that revision.

The complete audit bundle is
`/Users/alex/.local/state/vinix/android/current-launch-build-2026-10-26-r12`.
Its `sha256.json` SHA-256 is
`1ed02f160821299531d4617a10387d4bf54d7d3703485565537c07b2f3ac8a1e`.
The maintained builder is `build-current-launch.v`; the retained builder
source SHA-256 is
`b760d34a9a9378de3f4cf25109b397ea5503af27386fbdb8fffd3232d8a4c2b3`.

| Output | SHA-256 |
| --- | --- |
| `bin/vinix-android-native` | `f30ff41c607c72f67e40e979171af7a71d053cc470288cf19a0cd7d568ead2a9` |
| `bin/run-android` | `74be0a389342a95a35ecfd6393e2c1cc00e7d3e9e63522faeb623455f9d64251` |
| `bin/headless-service-controller` | `92db3737fcdaca322ef4e03df68942b094ea00370e1789936077737e7f4a9946` |
| `bin/native-account-broker` | `a821e52ef8fe7a1d2b77cb16a543d14ea8972501bbcf1a8058003d0b7e442cf9` |

The entry uses the seven-argument `vinix_android_native_service_main` ABI.
Its retained `abi/headless.v` SHA-256 is
`c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57`,
matching the JNI source in `current-native-build-2026-10-26-r15`. The entry is
a dynamic ELF executable; the other three executables are static. All four
have valid ELF64 AArch64 program headers.

The build pins these input manifests:

- The 2,102-class framework bundle at
  `combined-account-webview-cache-framework-2026-10-26-r3`, seal
  `f37e13b84b5dfb2c71ad852e2bae5b03fed04e8ee319f44e77fc7605f3b1994a`.
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

The builder applies one exact compatibility correction to each retained
`os/process_nix.c.v`: `mut cstatus := 0` becomes `mut cstatus := i32(0)`.
This matches the Linux wait-status pointer width. The original is retained
under `compatibility/`; each target's `*-linux-compatibility.json` records
both hashes, and `*-compiled-closure.json` pins the corrected input. The
live compiler library remains unchanged. Self-tests reject source drift or
an already-applied correction.

Validation completed:

- Actual target C compilation with implicit-function and integer-conversion
  errors enabled, followed by dynamic/static links as specified above.
- Consumed header and linker-input audits against retained or sealed inputs,
  including `crtbeginT.o`; before-and-after input hashes; full bundle inventory.
- Builder self-tests for dependency parsing, incomplete source closures,
  helper-object paths, the seven-argument ABI, ELF program headers, exact
  wait-status correction and both executable profiles.
- The retained failed r10/r11 attempts exposed strict poll/execve pointer
  types. Fixes `827f336c7` and `5534dc628` pass strict host control tests and
  this final ARM build without relaxing compiler checks.

Earlier executed entry parser/ABI checks (`1e1d8501a`), account/UI lifecycle
pump checks (`1dc0393f3`) and browser process ABI regression (`fb40158df`)
remain separately retained evidence; they were not rerun by this build.

## Token-cache guest controller

The same builder's single-target profile completed at
`/Users/alex/.local/state/vinix/android/current-token-cache-controller-build-2026-10-26-r1`.
Its `sha256.json` SHA-256 is
`fd979a301fc622dc4e4fd6e08bb97a926083172dfa5c8726f4fcb0fffe651816`.
The only executable, `bin/account-token-cache-controller`, has SHA-256
`eecf2f8055accc1f62b24b0effb4210b5ce17e5601c9a4e3f92ed4648a0a9d36`.
Its receipt kind is `vinix-account-token-cache-controller-v1`, with the
same framework, baseline and compiler pins above. It retains the frozen
controller from `2f5d81cd8`, source SHA-256
`bd5caee4dcbb5530ffd279ffa5d86723d6a71eb3854d64dabdddbd57f3cbc7f2`,
and its complete closure, strict static ARM link and ELF checks.

These receipts qualify executable builds and ABI coupling. They were handed
off for guest execution. Maps login, account persistence and the requested
running screenshot require separate guest evidence.

## UI controller with corrected argument ownership

The standalone `--ui-controller` profile from builder `a3e6718c3` passed its
retained-source AArch64 cross-build and strict static link. It captures the
helper argument ownership fix (`75154c870`): the controller clones borrowed
configuration strings before freeing the temporary argument array. This is
build evidence; the real-helper guest regression remains a separate check.

- Complete retained bundle: `/Users/alex/.local/state/vinix/android/current-ui-controller-build-2026-10-26-r1`.
- Bundle `sha256.json`: `503f4e03edf225311038cc0ecce556b804f6b07a337793ff7a466881fbe0112a`.
- `bin/account-ui-controller`: `5c5d6415f3e97cb2369187a7aa373aca019ae1e085298daf4551789739851f18`.
- Source revision: `c5fc9065af1e624002eaff6e2f927ce79858a06e`.
- Controller source: `3dcc2e60d5082cf7736c2f363a165f4cba33fabd9b0563599d6662dbbd21f5b2`.
- Retained `accountuifd/control.c.v`: `7655f8175951075501cc3cc395bdf38355bbaaf8d50ede416c208758f77a3282`.
- Compiled closure receipt: `61580cfa752889d08e6b9c178b128491bc69324a748d2af9ed2de5196b1b40ba`.
- Descriptions framework `sha256.json`: `d898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021`.

The build receipt kind is `vinix-account-ui-controller-build-v1`; target
profile is `ui-controller`. The pinned compiler, sealed r5 dependency input,
Linux wait-status correction, strict declaration/conversion checks, consumed
headers, native signal object, static ELF program headers, source closure and
before/after input checks match the executable policy above. Builder self-tests
passed. Guest execution must use the retained controller with its paired
helper and actual desktop UID, GID and socket.
