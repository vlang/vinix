# Default network activity SDK tooling checkpoint

## Resume on 2026-11-12

The full SDK retry and a separate fresh-process complete integrity readback
passed. Native production is now blocked by missing historical bundles rather
than disk pressure. This supersedes the pending-SDK status below; the original
2026-11-05 evidence and failures remain required.

Resume source revision: `554908ef4`. The retained producer executable still
matches `7118b8946857569f2d9eb678b1a721974348853726592ea6d3fb6dc018d6a447`.
It produced `S/combined-account-webview-default-network-active-framework-2026-11-05-r5`
with the original predecessor pins and unchanged limits. The narrow producer
passed its preservation checks for 2,117 classes and its complete output seal.

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `17d09d2f20124e3f8badd4b5c1ed30197b26a5bfccc4c46736e4d673dd3effe6` |
| `build.json` | `61b03ed0a81b911a8e17263003a8df02a176fd28fc7615f58ad6c19822457ac6` |
| `api-impl.jar` | `127adcd698a8e95717bafdf74c3ba21c8dee9838efa02c2206d07957ff394fdd` |
| `classes.dex` | `506b38602dce437693517bce13414ba0f6fc4192d0289db70f9988d5fb6a38c3` |

Controls remain in `C` below. `sdk-build-r5.guard.json` records guard/child
0/0, empty reason, complete cleanup, 9,887 ms, 501,039,104 bytes sampled
aggregate RSS and 157,020,160 bytes shared disk growth. Its SHA-256 is
`6be5490c14331482f744e4613d6ef2ffd0ad9dff2890a9cb338f10d26c4b99f4`.
The producer's `--check` ran in a fresh process under the same limits and a
16 MiB file cap; `sdk-readback-2026-11-12-r1.log` records
`COMBINED-FRAMEWORK-INTEGRITY-PASS` for the exact manifest above.
Its guard/child exited 0/0 with complete cleanup in 624 ms; the readback guard
receipt SHA-256 is
`ef1f03071f351a640b9cb37978ad6ae277d1d1f27f63bca0e754c35dc3866e78`.

The retained `current-native-builder-hash-host-r1` was attempted under the
original limits into fresh `S/current-native-build-2026-11-12-default-network-active-r1`.
It failed opening
`S/headless-service-native-build-2026-10-26-r5/tools/v_old276` (ENOENT).
`native-build-2026-11-12-r1.guard.json` records guard/child 1/1 and complete
cleanup; SHA-256 is
`5ae4072ee696786d3284925ff5eb59c696ff23bccdca4b489d7fda78dec91820`.
Preserve that failed root and use a fresh root for the next attempt.

Restore the complete original bundles at their canonical paths before retrying:

| Missing bundle under `S` | Required manifest SHA-256 |
| --- | --- |
| `headless-service-native-build-2026-10-26-r5` | `d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e` |
| `current-native-build-2026-10-27-startup-r1` | `a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20` |
| `current-native-build-2026-11-04-process-packages-r1` | `0b8ad44d408b90824a69fa7d42c9376965eaa34a93dc81b056050ef227bc3d7f` |
| `combined-account-webview-process-packages-framework-2026-11-04-r2` | `4a354ead173048b39fb26cce709922f8954e27e53e2d3a5d92ecdf427db0645d` |

The last two are required by the unchanged native compatibility reader.
No substitute compiler or partial bundle was admitted. Native output pins,
delivery qualification, aggregate evidence sealing and ARM execution remain
pending. CI and guest state were not changed during this resume.

This is a tested source/tooling checkpoint; full SDK production remains
blocked. Checkpoint base revision is
`27401f75b42b243c4c512db6de2774130f036ba7`; exact compiled source bytes and
retained controls are pinned below.

The producer adds `ConnectivityManager.isDefaultNetworkActive()Z` through the
[reviewed adapter](../native-android-tools/default-network-active-source-check.md)
from `90ca8c75ba03d70ecc55f2034cd545ec1e49af4d`. The activity hint returns true
when the framework has no activity/idle monitoring, independently of link or
route state. The new narrow profile permits exactly one public instance Java
method, preserving the previous 28 methods, four fields and two native query
declarations. The class count stays 2,117; all 2,116 other classes must match
before and after API-28 DEX assembly.

Paths use `S=/Users/alex/.local/state/vinix/android`. The predecessor is
`S/combined-account-webview-global-settings-string-framework-2026-11-05-r1`:

| Artifact | SHA-256 |
| --- | --- |
| `sha256.json` | `cadfaa0105eb24580f1cdcef590f707e52aab334e9d7bf164524a403f1b43cbc` |
| `build.json` | `29300cf133e8786b1d7e80a101129d6664a0ce6a0af5315e7eee39ab97d57c37` |
| `api-impl.jar` | `9207dab7a6a37e09fb049bb636ba6ebad3e63e43bfe7fd95821f67fc2aebeeb7` |
| `classes.dex` | `ac3f264e0dc77918845bb6ab2015e8c37724cbfaa47339f86f55e5750f7ccc32` |

The producer also uses macOS CommonCrypto for complete streaming SHA-256
reads, retaining a portable V fallback and all inventory/readback calls.
Independent source review passed at producer SHA-256
`43325b17b321e6059120999e4efde663e36020d2abf129f00d2a4cb4b52c3319`.
Native/portable parity passed over twelve actual files, including empty/abc
known vectors, binary SHA block boundaries and 1 MiB stream boundaries, plus
six missing/directory/symlink refusals. Historical producer self-tests and the
new 20 method, 12 member and six class mutation refusals passed.

Final frozen producer tool sources are under
`S/default-network-active-sdk-tools-2026-11-05-r3` (`T`); controls are under
`S/default-network-active-sdk-controls-2026-11-05-r3` (`C`). The adapter pin is
`fc459a6cba2efacf8183de5945e9d12ea741d2deccc745da97d72a2cfd9bf51e`;
ordinary integration pin is
`23b8cd3a0f0f1b45909be0000c532691bd9ce8243d06495691dd66ee1b1fcbf7`.
`T/producer-project-r2` preserves the emitted C, exact `build_command.txt`,
unmodified `build.sh` and resulting executable. Its C SHA-256 is
`efe95b3feca3f93bebd9a770b9aa47504aa54834d54feb004b1bda7459a54bd2`;
executable SHA-256 is
`7118b8946857569f2d9eb678b1a721974348853726592ea6d3fb6dc018d6a447`.

`sdk-producer-inputs.v` discovers the actual emitted C preprocessor dependencies
and requires `CommonCrypto/CommonDigest.h`. Its source pin is
`a5ed3ab8c0c568de7e1b0291f27976f8be470cbd515436774f985cd471f54798`.
Sixteen malformed-command refusal controls passed. `T/c-discovery` retains
the exact compiler argv and 372 discovered files. The qualified capture tool
consumed that complete list, both V compiler input lists and the explicit
provenance list, producing `T/c-closure` with 659 original/copy/resolution
entries. Independent complete readbacks passed before and after exact C
compilation. The capture manifest pins are:

| Manifest | SHA-256 |
| --- | --- |
| `inputs.json` | `3191c4548f8cecd498a25afa1ab12811d8123681d15548c3ed497095b8e1dd4a` |
| `resolved.json` | `2d7ce3764d55e39413b0cd222be60436ab013cbc8fb2a218f1d92e35d18ea2c4` |

Independent source and captured-membership reviews passed. The exact captured
CommonDigest header resolves to `MacOSX27.2.sdk` and has SHA-256
`83a9705bbc8d44f27ee61801064ee99288496a038d623f152aa30db6819e9ca6`.
The actual discovery helper executable is pinned at
`215b680fefa4023ac3e4f6ad7e21c5b85635dd12aa07e3ddc419ce07984c93b3`;
hash-parity receipt `T/hash-controls/receipt.json` is pinned at
`34071da00d36f40b57398c4bfd56110e64e5f07f2ee834a28915933f2693f36e`.
Passed controls report guard/child status 0/0, empty reasons and complete
cleanup:

| Phase | Elapsed ms | Sampled RSS bytes | Shared growth bytes |
| --- | ---: | ---: | ---: |
| Emitted C generation retry | 22,866 | 305,102,848 | 129,449,984 |
| Discovery helper compile | 12,925 | 422,625,280 | 40,058,880 |
| C dependency discovery | 398 | 41,009,152 | 233,472 |
| Input capture | 4,206 | 9,142,272 | 157,638,656 |
| Capture precheck | 3,125 | 11,796,480 | 3,944,448 |
| Exact emitted C compile | 1,724 | 148,619,264 | 3,203,072 |
| Capture postcheck retry | 4,318 | 12,058,624 | 2,899,968 |
| Native/portable file parity | 900 | 14,155,776 | 13,094,912 |
| Producer self-tests | 467 | 15,958,016 | 48,590,848 |

Every SDK compile, test, capture and production attempt retained 600 MiB
aggregate RSS, 300 seconds, 512 MiB observed shared growth, 1 GiB disk reserve
and 4 MiB output. Outer compile/test phases used a 16 MiB shell file cap;
capture and full SDK phases retained the original 8 GiB cap because they copy
the pinned 29,572,292-byte V compiler and other existing inputs. No inventory,
audit, file read or hash was skipped or cached.

Retain the unqualified SDK `r1` through `r4` roots and their tool/control roots.
The first two SDK runs stopped for observed shared growth (561,025,024 and
552,251,392 bytes). The accelerated producer's `r3` and `r4` attempts stopped
for host shared growth of 1,224,462,336 and 1,145,458,688 bytes after 17,913 and
29,971 ms. All guards stopped descendants with complete cleanup. Earlier
emitted-C generation and one post-compile input readback also stopped for
shared growth; fresh retries passed under the same limits. These failed
attempts establish no usable SDK artifact, even where an output manifest was
written.

Three read-only 20-second probes, supervising only `/bin/sleep`, also stopped
for observed shared growth after 5,638, 11,824 and 13,292 ms (1,116,250,112,
864,223,232 and 1,100,099,584 bytes). These controls show that the host bursts
recur without SDK writes. No CI process or VM was stopped to obtain a quieter
window.

Full SDK production remains pending a successful unchanged-limit run.
Aggregate evidence sealing and separate fresh readback also remain pending;
the original complete raw bundles and their recorded checksums remain required.
ConnectivityManager belongs to the native-consumed 70-class set, so a fresh
coupled native build and narrow complete readback are required before delivery.
No successor ARM, GMS stability or Maps result is established here.
