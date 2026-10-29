# Platform fragment framework successor, 2026-10-29

The explicit `--platform-fragments` profile builds the platform fragment provider
from `05fbcfa9d` over the sealed Service lifecycle framework. It adds retained
tag lookup, queued commits and host-driven fragment lifecycle state. Exactly four
existing classes change, and one `VinixFragmentCommit` Runnable is added:
2,104→2,105 classes. This is host production and DEX-roundtrip evidence; it does
not establish the original GMS NPE's cause, a successful ART regression, Maps
rendering or Google authentication.

Artifacts remain under `/Users/alex/.local/state/vinix/android` (`S`):

- Builder, frozen source/compiler and command controls (`B`):
  `S/platform-fragments-framework-builder-2026-10-29-r1`.
- Closed framework output (`P`):
  `S/combined-account-webview-platform-fragments-framework-2026-10-29-r1`.
- Complete two-root seal and fresh readback (`F`):
  `S/platform-fragments-framework-sealed-2026-10-29-r1`.

The baseline is
`S/combined-account-webview-service-lifecycle-framework-2026-10-29-r1`, manifest
`9453286e07d3bd727782355413d4fa8059bd1332e89850748fb4db02680c9488`,
JAR `7017b4845f91cb1c37057f6e8da07476b9b1b44c523827acaf00baad2432fe74`.
The producer records revision `4d1cbec06d095c6c7668d051fb82468c2b838c89`
and exact working builder SHA-256
`0e0fcabfd5a69a70c1bf41b78915780c3bee9bbc046f9f27162bb8a62341e5e2`.
Provider SHA-256 is
`838192c98ee5f782b926bb167756d589f5baf86e32f47b35913c29bdf9dfa7a0`;
the retained `framework.v` registration/helper input is
`26ad5000db6790de88312d81af055abd915858122f32117c36450c159fcbc31f`.
All three were rehashed unchanged after production. Exact compiler, source
closures, smali tools and complete input/output inventories are retained.

| Existing class | Changed methods | Added methods | Added fields |
| --- | ---: | ---: | ---: |
| Activity | 13 | 0 | 1 |
| Fragment | 0 | 5 | 4 |
| FragmentManager | 4 | 8 | 6 |
| FragmentTransaction | 3 | 2 | 3 |
| Total | 20 | 15 | 14 |

The producer preserves all other methods, existing fields and class metadata.
Allowed method headers have explicit access/static/native checks before and
after DEX roundtrip. Activity's native `onStart`, `onStop` and `onDestroy`
declarations stay unchanged. The helper has exact class/superclass/interface,
field and method headers, with no native methods. Selftests reject incorrect
flags, missing/duplicate/unapproved fields, changed retained members, helper ABI
changes, substituted classes, incorrect counts and missing required deltas.
The canonical JAR-cloning pipeline and historical profiles remain unchanged;
only the JAR's `classes.dex` member may change.

Activity belongs to the native producer's consumed classes. This output therefore
requires a fresh matching native build and the stage's explicit Activity delta;
the previous Service native artifact's compatibility is not asserted here.

| Check | Seconds | Peak sampled aggregate RSS, bytes |
| --- | ---: | ---: |
| Builder compile | 1.420 | 329,220,096 |
| Complete builder selftest | 0.267 | 10,207,232 |
| Full narrow producer | 41.651 | 495,173,632 |
| Complete seal and inline check | 0.823 | 23,953,408 |
| Fresh-process complete readback | 0.752 | 24,526,848 |

All guards and children exited zero with complete cleanup. Time reports record
zero swaps; their largest process maximum was 481,214,464 bytes for production.
Limits remained 600 MiB aggregate RSS and a 1 GiB reserve. Compile/selftest used
300 seconds and 512 MiB observed-growth caps; production used 300 seconds and
1 GiB growth; seal/readback used 900 seconds and 64 MiB growth. Production waited
until its full growth-plus-reserve budget was backed. Initial/minimum free space
was 4,879,343,616/4,727,418,880 bytes, with 151,924,736 bytes observed global
growth. Shared-volume changes do not isolate producer allocation. No failed
executable attempt or cap increase occurred in this producer run.

| Retained artifact | SHA-256 |
| --- | --- |
| `B/tools/builder` | `efb23b1a4c71b8cbdded9bfe0fa0c0d29a9f5243761b5429a6075ad102b2a297` |
| `P/sha256.json` | `5b452702e033f72f9056f994b94295f7925958c62fcaad039827710368249bfb` |
| `P/build.json` | `b6365978bad4c2c74ab0e7588b82cdfc8ef6323d7cddee97036160f491c13b7a` |
| `P/api-impl.jar` | `6970582da55b15dd30391491d2be2213abe665fe0256167f45cccdd3de25bcd4` |
| `P/classes.dex` | `cb705ab384bf4cc057e1fd55c35148151e33a0471d1ea12fc2973f1b9be2fd5d` |

| Class | Raw source SHA-256 | Post-DEX SHA-256 |
| --- | --- | --- |
| Activity | `16546cc49fa0bdbb74ec4b0d1554bacac9850446dce25bbd5e9a5b2b2d516e18` | `8a0bba8b9b2837522a51f18a5f9889c6865f224ce5655577458b3c74690ff54a` |
| Fragment | `1f2cdb322b9f89cbf1d85aef4f700bc62e28e960b99c53ad07fd336ba3bb5928` | `13527f959769c19d30177c0992a4487c98693c6532d3b3ecb7faea91dc3b5138` |
| FragmentManager | `465c4f8b486c9259be557927238d4d63a2b25b81da44fcc3c29307e22023df83` | `b0288c3305b50a1a626589a92f2116d6ead1dbb0cbade0fd8ad2968b460ae802` |
| FragmentTransaction | `a9a27718d75e502fe78e295772e3d420d902b509883594c028d82e454ce2270a` | `8ca0812c9d83251eed4befb750309afe6a6c4ef72f06099d2b315d74e1859798` |
| VinixFragmentCommit | `9c1b575f2fd9d254ccf068948b52b0229e1b1d3435bc97fe7702b6e6d80fcd2a` | `445b9ed0be07cbe8f8018d357f9ce277b560dd545fdae039a71193eca4223011` |

Both closed roots and all 7,491 entries are bound by
`F/sealed/manifest.json`, SHA-256
`3e7f9cc3d044bd3e202ecc8a9f52730341f70409c6b5f82a0ee52f1bb3844f85`.
The seal's inline verification and a separate fresh-process complete readback
passed. Keep all original complete bundles unchanged; this report does not
replace the evidence.
