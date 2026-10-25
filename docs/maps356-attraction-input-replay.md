# Maps356 attraction input replay

Maps356 searches Oasis d'Aboukir directly, opens Directions, accepts Louvre Museum
as the origin and displays a 7-minute, 2.1 km driving route. Its preview advances
to the next instruction. Selecting Walk displays a 16-minute route with an
18-minute alternative, and its preview opens walking instructions. The photo
tiles remain gray; a separate photo viewer and transit route are not established.
The transport controls appear after returning from the driving preview.
Actual travel and GPS navigation are not established.
Both complete canonical readbacks pass. The unchanged classifier reports
`startup_failed` for a missing native symbol, despite the working route UI.

This fresh replay retains the qualified runtime from [Maps355](maps355-attraction-details-replay.md).
The replay uses unchanged production and generator implementations. Independent comparison of
the generated 355 and 356 sources finds only replay labels and paths changed.
Native351, Framework353, Launcher334, the 109 runtime files, exact two-member
native/JAR overlay, five base boot members, external APK inputs, identity,
original classifier and 600-second observation are unchanged; 107 runtime files
remain identical to baseline350. This input path does not establish the cause
of Maps355's unresponsive details page or claim an additional framework fix.

All artifact paths below are under `/Users/alex/.local/state/vinix/android/`
unless marked as repository paths. Native351 is retained in
`text-size351-native-build-2026-10-25`; Framework353's complete canonical clone
is `screen-reader-focusable353-framework-build-2026-10-25`, with its original
`screen-reader-focusable353-2026-10-25` unchanged. The input JSON is
`maps356-pins-2026-10-25.json`, byte-for-byte identical to Maps355's input.

| Immutable input, tool or gate | SHA-256 |
| --- | --- |
| Native351 complete manifest | `eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Framework353 complete manifest | `22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f` |
| Framework353 JAR | `1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83` |
| Launcher334 | `52e305950821e56d85bb9c4d6ba51a3c5f74ccf2b15b158d1fd47279cb70ef56` |
| Launcher334 complete manifest | `25855fcb5aa5016d7cc5df659017f66b6f3dc5d96e4935d474d691b59de9fc27` |
| Original350 source | `b2d08a2974764b9925d311a7a025fd10eb339fac30c58aa1e48380cce3835d93` |
| Baseline350 prelaunch | `dc30058a943aea4babe5451df20eb0a967262a09caf7df8aed0c88917e987a2c` |
| Classifier | `47f1d9a78bfb2991f9802ebebc95436505160f7e551e1e77d4d95a171c63946b` |
| Recorded generator r2 | `8015d46041e305e5b381837ebd7cf9658978ad2642a2792f4be2aa8b1b218d31` |
| Generator source | `5a0fc62f94bd28b88f19b3116c4b5ad0776fd333a7cc1ca2f605ef0fca6c79db` |
| Recorded receipt332 wrapper | `30edced25287dcf09502a3db11c7023c2eb56d1cc8bdb84166f35a0303c715ca` |
| Receipt wrapper source | `ef464fa8ea251493bc2e9a907a0635e2412074a6e91a5837f9bf11d7c512aee3` |
| Complete flat checker290 | `52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004` |
| Pinned host V | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |
| Input JSON | `52ed4cdb4458fc93fec8375511b9d9f973dacbbfc4fdcd50f0aaeaab1f494009` |
| `maps356-generation-2026-10-25/maps356-run.v` | `ad0e102894effec9e569b86fdc5ad150d9fc84385f5367a2062904aae38fcc6b` |
| Repository `build/android-maps/maps356-run-recorded` | `1a187ad294d714717c9c34e0d2a0c5b9f45f0e349aa0b1084e4bbb435140819c` |
| Repository `build/android-maps/maps356/launch-pins.json` | `5409c3fcda95364cab221174ff01b0378bedff1a8192b4fdd1e42cee7addd19a` |
| `maps356-2026-10-25/prelaunch-sha256.json` | `3138cba49c3ed8f6b9d8d27c058431f59327aa3c053f645050d1ae527a957570` |
| `maps356-prelaunch-peer-review-2026-10-25.json` | `73e1b525cc4ca4c0182df213638b5c6752a54d7e62f49d68bb4ac3c8f893558e` |
| `maps356-generation-2026-10-25/sha256.json` | `4d5544285f500e7524f984129e0a572a7b6a0983bf539c6bc6d756261e5b2eab` |
| `maps356-preparation-receipt-2026-10-25/sha256.json` | `c7915dc67435b410337cb07c7dc56bb7ad3da6be4d9a6019e6880dffd8d1d47c` |
| `maps356-check-receipt-2026-10-25/sha256.json` | `e9f8965f9a94a6d6b00fcb50dda4a6f59c8ae6fe40739f81b0651d6691570e84` |
| `maps356-generation-own-readback-2026-10-25.json` | `6db3547120504f95a1f3cffd91df839520f42cbcb9c0df267cbb667e74696037` |
| `maps356-preparation-own-readback-2026-10-25.json` | `f1cbcffcefe624f2e798652baaefcb66bd3194863791f821f0d7d60458b1b6e6` |
| `maps356-check-own-readback-2026-10-25.json` | `5bafd1fd7b65b0eb19ec2f9a67d589858b57802f7b9d2a3ac347d209191a79ad` |

The generator source is commit `c14368bd4574a68632f03586e91fe9c50fe862ca`;
Native351's text-sizing fix is `3ec341752`, and Framework353's
screen-reader-focusability fix is `2ee9c8d64dcb5fd9c93a1e4c3625606011c9cd47`.
Generation retains the 1536 MiB minimum-space policy. On 2026-10-25 UTC,
the source was generated at 22:01:50; preparation ran 22:03:36–22:08:26,
exit 0; check ran 22:08:57–22:10:46, exit 0 with `MAPS356-GATE-PASS`.
Owner and root complete readbacks pass the 22-file generation bundle and both
9-file receipt envelopes; root receipts use `maps356-{generation,preparation,check}-root-readback-2026-10-25.json`.
Independent prelaunch review completed 22:09:30, exit 0, verifying complete
typed trees, modes/links, all 109 runtime files, the 107 unchanged files,
the exact final overlay, five streamed base boot members, APK inputs and classifier.

Generation explicitly supplied `HOME=/Users/alex`,
`PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin`,
`VROOT=/Users/alex/code/v` and `LANG=C` through `env -i`; the generator itself
sets `VROOT` and `COPYFILE_DISABLE=1` and removes forbidden trace/location keys.
Preparation/check explicitly supplied only `HOME=/Users/alex`,
`PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` and
`VROOT=/Users/alex/code/v` through `env -i`, matching root's run invocation.
Their receipts record four clean entries, no forbidden keys, unchanged pins
and an empty removed-environment list; the fourth entry's identity is not recorded.

## Captured behavior

Root owns all guest/QMP actions and visually reviewed the screenshots below.
Times are capture-command start times in UTC on 2026-10-25; live PNGs and
`interaction.log` are at repository `build/android-maps/attempt356/google-maps/`.
The separate corrected manual Skip helper is `maps-interact-skip355`, binary
`9cf988acb1a256d47fdf9f42bd752c0e9cd8bfb114069de0856f5822eb04f84d`,
source `3fc918dfaf831f268756432c55e83fdf3f6bb32e3ea8f78610834fccf1bf97f6`,
commit `29c72fbab`; it does not replace the frozen baseline helper/runtime.

| Screenshot | Time | Observation |
| --- | --- | --- |
| `map.png` | 22:16:06 | Map after corrected Skip click at 524,134 at 22:15:41 |
| `search-field-ready.png` | 22:16:32 | Search field ready before typing Oasis d'Aboukir Paris at 22:16:37 |
| `oasis-search-result.png` | 22:16:45 | Result selected at 292,196 at 22:16:50 |
| `oasis-details-ready.png` | 22:17:18 | Oasis, 4.6 stars, 98 reviews, Open 24 hours; gray photo tiles |
| `oasis-directions-response.png` | 22:17:54 | Focused Choose start location after Directions at 200,537 at 22:17:28 |
| `louvre-origin-result.png` | 22:18:16 | Louvre Museum result after typing at 22:18:03; selected at 292,196 at 22:18:20 |
| `route-options.png` / `route-settled.png` | 22:18:52 / 22:19:18 | Selected 7-minute default route, 8- and 16-minute alternatives; mode row absent |
| `oasis-route-preview.png` | 22:19:35 | Head southwest on Pl. du Carrousel after Preview at 201,696 at 22:19:25 |
| `google-maps-running.png` | 22:19:50 | 120 m, Slight right to stay on Pl. du Carrousel after next at 565,682 at 22:19:42 |
| `route-after-preview.png` | 22:20:46 | Drive, selected car 7 min, transit 11 min, walking 16 min; route 7 min (2.1 km) |
| `oasis-walking-route.png` / `oasis-walking-settled.png` | 22:23:19 / 22:23:36 | Walk, dotted blue 16-minute route and 18-minute alternative after click 535,604 at 22:22:48 |
| `oasis-walking-preview.png` | 22:24:00 | Route preview, Head toward Rue de l'Amiral de Coligny, 16 min after Preview at 201,696 at 22:23:50 |

These captures establish driving and walking routes, both previews and driving
instruction advancement. The transport controls become visible after returning
from the driving preview; earlier captures do not show them. GPS remains unverified. Gray
photos reproduce on this direct path; no additional photo fix is claimed.

The read-only photo analysis is retained at `maps355-photo-analysis-2026-10-25/audit.md`,
SHA-256 `b2fe5a20b35674e35682eefd6d79bc6e0de26a25230ca5cd2de22b2a21be2a7b`;
its `audit-input-sha256.json` is `8cabc346061667db4b715dad58b3c5152060cc69ec4333b498f30ca9d194a16e`.
It identifies rendering gaps and bounded next diagnostics; no causal photo fix is established.

## Final observation

The raw result records `backend_ready`, `launcher_entered` and
`native_maps_observed` true, `observation_elapsed_seconds=600`,
`process_exited=false`, `qemu_alive_before_capture=true` and
`functional_passed=null`. Its unchanged classifier reports
`outcome="startup_failed"` with exactly one failure marker:
`java.lang.UnsatisfiedLinkError` loading `libAppDataSearch.so` because
`__pwrite_chk` cannot be located. Background AppIndex.API is unavailable.
This failure is preserved; the visually verified route behavior does not
replace the raw classification or establish a clean functional pass.
Serial lines 3821 and 4698 also retain two Google Play Services finalizer
exceptions, `Lock wasn't released correctly` in `dhgc.finalize`; Maps survives them.

The suite receipt records 22:13:21–22:24:31 UTC, exit 0. Root and peer visually
reviewed the automatic final `application.png`: Walk, a dotted 16-minute route,
an 18-minute alternative, origin and destination remain visible.

The run wrapper records 22:11:39–22:26:27 UTC, exit 0, four clean environment
entries, no forbidden keys, unchanged input pins and an empty removed-environment
list. The complete nine-file run envelope passes root readback, retained as
`maps356-run-root-readback-2026-10-25.json`.
Root and independent complete canonical readbacks both exit 0 with all 64,480
typed entries checked and the manifest unchanged. Their identical logs,
`maps356-root-canonical-readback-2026-10-25.log` and
`maps356-peer-canonical-readback-2026-10-25.log`, record
`MAPS356-COMPLETED-READBACK-PASS entries=64480`.

| Final sealed evidence | SHA-256 |
| --- | --- |
| `maps356-2026-10-25/sha256.json` | `0f7bd335774c7ed77a12a8bcbec6fbdd1573e8ae673030f382f4f05000eac14d` |
| `maps356-run-receipt-2026-10-25/sha256.json` | `db0339566a2bd4d54d34445e5e1e0bab98999d4144a4241d9c08255d826d03e7` |
| `maps356-run-root-readback-2026-10-25.json` | `62949bd5832a0789bba0458e74171a998b3f0b225a91ae8d5b1a7f47be0a523e` |
| Root/peer canonical readback logs | `bb6bc35d2fa44e7070960970267bbaf2b86704222c563a7fa50b740d5320212c` |
| `application.png` | `b1bb2f8622890b66466e63c870c6605d574718e1fac8346b5b66cfdb30867b55` |
| `google-maps-running.png` | `4a00e26a88b9c6c12453d24fa57490dd90ebf95fa6a8745f9a007947042c961e` |
| `oasis-walking-preview.png` | `fa0c677a3785fc9b350b7fb7d0afb3013919eb5b8f34998f99acdadba5b85033` |
| `serial.log` | `3c4ef772777e2765a1f14050b5c9b7717a332d48f950d79cfb829ea459e70b3d` |
| `interaction.log` | `b98e3cec0fa89a73260e1b038f7a67457c777c3e4b505e087fafc00d2b17ef4f` |
| `results.json` | `6bae059cb79b1757d09c11e76485bf2d08da277acc39480f0a57c89da7d73883` |

The six individual artifacts compare byte-for-byte with the live collection.
They are under `maps356-2026-10-25/results/attempt356/google-maps/`, except
`results.json`, which is directly under `results/attempt356/`.
Repeat the complete typed readback with
`build/android-maps/maps356-run-recorded verify 0f7bd335774c7ed77a12a8bcbec6fbdd1573e8ae673030f382f4f05000eac14d`.
Historical evidence remains unchanged.
