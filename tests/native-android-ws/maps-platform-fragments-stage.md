# Platform fragment and Throwable restoration stage

Validated snapshots over revision `355caa04832c2368ae95f384c034ba6221d4af97`
are retained at
`/Users/alex/.local/state/vinix/android/maps-platform-fragments-stage-build-2026-10-29-r1`.
`completed-tool-inputs.sha256` pins both sources and final tools. The framework
provider is commit `05fbcfa9d`; its production report is
[platform-fragments-framework-2026-10-29.md](platform-fragments-framework-2026-10-29.md).
Native Throwable restoration is commit `59879ee0b`.

The explicit stager and `--maps-platform-fragments` kernel profile preserve the
complete Service image `8886ba277d9cb8b834bceaa2cf36dd2b8ee00dadb2589e52edb97a7cc62a0f92`.
They require one seven-file overlay: JAR, DEX, native DSO, three framework/headless
receipts and the Maps deployment receipt. Exactly 56 complete dependency seals,
six deployment input changes, three top-level changes, 26 inherited modules and
27 final modules are required. Original ancestry, TAR inode/mode checks, first
executable DSO inode and historical launch/headless native roles remain pinned.
The headless receipt changes only its JAR input.

The new framework manifest is
`5b452702e033f72f9056f994b94295f7925958c62fcaad039827710368249bfb`,
JAR `6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4`,
DEX `cb705ab384bf4cc057e1fd55c35148151e33a0471d1ea12fc2973f1b9be2fd5d`.
Complete 2,104→2,105 canonical class membership and old post-DEX/new pre-DEX
inventory equality are checked. Exactly Activity, Fragment, FragmentManager and
FragmentTransaction change; VinixFragmentCommit is the sole added class. Complete
successor raw sources equal the canonical baseline clone except those five pinned
outputs. Method/field receipt maps are exact; no text is normalized.

Old native manifest `2c61783de1aab68bbf8177329215b27881e95afaa87d16272f03ba7fda98c401`
remains verified against its exact Service framework. The new coupled native root is
`/Users/alex/.local/state/vinix/android/current-native-build-2026-10-29-exception-restore-r2`,
manifest `6a6410f9d62a2d28174d7cc8213acaabcca89b548402337dbb5e5bed34f99f72`,
DSO `613c6b2c7b1e816a5d7b0694d626a52a5b4df19604a6a224df99ad13055aa74c`.
All 88 source origins remain exact; only account_service.v and account_ui.v change.
JNI, bindings, exports, builder, headless observer, compiler inputs and native
generator helpers remain unchanged. The complete builder closure permits only
the exact framework registration and added platform-fragment provider.
Actual enumeration and the full native/framework audit passed. All 68 consumed
classes remain present; Activity has its separately pinned raw/canonical delta and
the other 67 remain byte-identical. Earlier Service/Binder formatting deltas are
preserved in the sealed ancestry rather than declared as new changes.

Both tools use V's supported serial `-generate-c-project -no-parallel` path,
followed by the exact emitted production C command. No generated C or flags were
edited. Original limits were 600 MiB aggregate RSS, 300 seconds, 512 MiB observed
growth and 1 GiB reserve; every guard and time-reported maximum passed, with zero swaps.

| Phase | Guard seconds | Sampled RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Stager generation | 2.593 | 279445504 | 309821440 |
| Stager C compile | 4.689 | 260521984 | 242860032 |
| Stager self-test | 0.410 | 1245184 | 18448384 |
| Patcher generation | 3.169 | 347914240 | 365920256 |
| Patcher C compile | 7.041 | 345571328 | 333119488 |
| Patcher full self-test | 13.889 | 45416448 | 37044224 |

The full actual input audit and exact helper enumeration passed separately under
the same limits. All historical kernel-profile tests and the new profile's changed,
missing, extra, unsafe-mode and stale-Service-proof rejection cases passed.
The inherited pinned compiler/source closure and C inputs are retained; relevant
flagged C files and include directories compare exactly with the current inputs.
Host SDK/system dynamic libraries remain recorded environmental dependencies.

The complete one-root, 591-entry evidence seal and fresh-process full readback
passed under 600 MiB/900-second/64 MiB growth/1 GiB reserve limits:
`/Users/alex/.local/state/vinix/android/maps-platform-fragments-stage-sealed-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `71c740119d0b362fc57613006e1bdc9894227350ac243fa396bfd3e502aa8c3c`.
Both roots are closed.

Final tools below the build root:

- `stager-project/maps-platform-fragments-stage`: `f409b107368a230314563bb80b93295761b6a88548c45c0815cb9b8f62b795e5`
- `patcher-project/patch-kernel`: `9abd8b80bfe7f541fbd2ca5287fe8c9e416197cece853b4a94869db2e6d26310`

Run `maps-platform-fragments-stage --prepare FRESH_EXTERNAL_OUTPUT`, then clone
the complete sealed image before `patch-kernel --maps-platform-fragments FRESH_CLONE
FROZEN_KERNEL_BUILD BUILD_JSON_SHA256`. Preserve the original preparation/clone/kernel
600 MiB/900-second/4 GiB growth plus 1 GiB reserve and 8 GiB shell file-size limits.
This tool qualification prepared no image or VM. Guest regression, Maps startup,
Google authentication and map rendering require separate runtime evidence.
