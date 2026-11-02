# Secure writes, API 28 tile request and retained native

The GMS initialization path writes `nearby_sharing_component` and then requests
Quick Settings listening. The audited bootstrap/argument and APK-minimum-SDK
flow selects API 28. Core `2af821249` therefore adds only
`Settings.Secure.putString(ContentResolver,String,String)` and TileService;
provisional higher-SDK user/status-bar changes are excluded. The
[source report](../native-android-tools/secure-settings-source-check.md) records
the bounded caller and provider contracts.

The writer passes the original nullable name/value as ContentValues to virtual
resolver insertion at Secure.CONTENT_URI. It returns true for a nonnull URI,
false for null or SQLException, and preserves other exceptions. No local store,
persistence claim or permission grant is introduced. TileService follows the
API-28 Intent/action/Parcelable component/SystemUI package/receiver-permission
dispatch. Its constructor calls Service and its binder is unavailable; no tile
UI, callback or status-bar backend is supplied. Existing permission-constrained
broadcast delivery handles the unavailable SystemUI path.

Producer `ecd559062` adds `--secure-settings` over the exact broadcast SDK.
It preserves all ten old Secure methods and metadata, adding one static writer.
The sole new fieldless class contains three TileService methods: 2,111 classes
become 2,112. Independent raw and canonical oracles bind parameter/URI/result
forwarding, SQL catch type/span/handler and exact API-28 tile dispatch. Complete
class/member/metadata and JAR checks preserve all other bytes. Independent
review covered source and complete produced artifacts, including streamed JAR DEX.

| Admitted operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Fresh producer compile r2 | 1.662 | 376,635,392 | 403,144,704 |
| Complete producer self-tests r2 | 0.349 | 10,485,760 | 14,385,152 |
| Complete SDK production | 41.348 | 500,662,272 | 482,361,344 |
| Complete retained-native admission | 1.855 | 51,904,512 | 52,084,736 |

SDK production passed its first attempt. The first producer self-test rejected
its malformed duplicate-member test fixture, whose appended method lacked a
separating newline. Only test construction changed; the provider and refusal
policy stayed intact. The complete original builder r1 remains retained, along
with its provisional source draft; fresh r2 compile/self-tests pass. Admitted
guards/children exit zero, cleanup is complete and swaps are zero. Production
observed 142,217,216 bytes shared disk growth under unchanged 600 MiB RSS,
300-second build/test, 900-second full-audit, 1 GiB reserve, 4 MiB output/file-cap
16777216 limits and 512 MiB/1 GiB tool/SDK growth ceilings.

Paths below use `S=/Users/alex/.local/state/vinix/android`; the complete SDK is
`S/combined-account-webview-secure-settings-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline broadcast SDK manifest | `49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5` |
| New SDK manifest | `0c7485f9a38c52dd6ef6ddd60c936f49d694da267ae30fccf6dea1163a21529b` |
| SDK `build.json` | `d33d5e2cf55ee88b3176f0702b639292db78497f9418812880c2998a08c56fab` |
| Framework JAR | `f7eef1e9b2a2a7730ce0b024823c9cc38dc1d510252dc6dccd30f1ada79f9768` |
| Framework DEX | `c64944f0bf989cab180f6a41686fb897590c59f8e3ef7ba26f67440a1ac0d55c` |
| Raw Secure | `2c8f8fb00e04f01c22c349319ba61d69059be983b4aaa91c9bd97b100cab9032` |
| Canonical Secure | `2fabe675a8e8cfc8c81907481c0a563d2645fc38998bee73e89bf31cbf049b05` |
| Raw TileService | `da380668dee963d39ddd449157f77bf3f6cd3d090f3dc9ba59fd030101c43956` |
| Canonical TileService | `081ded9887866e7e10ecaaab066656068cee3743d5ece44e1363c9994f638f44` |

The immutable SDK receipt records source revision
`ecd559062f2de801a76b2f3dfc7a2e8e4825e6f3`, containing core `2af821249`.
Current, committed and frozen provider/integration/producer pins match. Complete
controls are `S/secure-settings-framework-builder-2026-11-02-r1`, matching `r2`,
and `S/secure-settings-framework-production-2026-11-02-r1`.

Ten complete caller, source/provisional, fixture/provisional and SDK/control
roots passed sealing and a separate fresh-process readback: 7,793 typed entries.
Failed builder r1 and provisional API-33 material remain complete.
The root list is `S/secure-settings-producers-sealed-2026-11-02-r1/roots.txt`;
its `sealed/manifest.json` hashes to
`4a56da489a48061b7fefbe860c88c81ab9d930e509542e2f103512a7d650fe7e`.
Seal/readback took 0.590/0.536 seconds, sampled 27,246,592/22,937,600 bytes RSS
and observed 2,981,888/1,470,464 bytes growth. Guards/children exited zero with
complete cleanup under unchanged 600 MiB/900-second/64 MiB-growth/1 GiB-reserve
limits. The original complete broadcast/native bundles remain separately
required at their prior twelve-root seal,
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.

The retained native manifest remains
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`
and DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`,
with its original broadcast SDK
`49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5`
provenance. Generated native membership does not consume either API class.
Manual ContextImpl native
references remain covered by complete preservation of its fields, methods and
theme/resource/loaded-app ABI.

The full native admission passed all 70 canonical equalities. Exactly two raw
formatting pairs are admitted from the canonical clone; the remaining 68 raw
classes stay equal. No native implementation, binding or provenance changed.

| Consumed class | Original raw SHA-256 | Successor raw SHA-256 |
| --- | --- | --- |
| Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |

The gate checks the complete 91-origin/92-input native source map, 721 exports,
generated JNI/C, all 58 consumed C/header inputs and complete 650/340-entry
builder/generator closures. Its retained bundle remains coupled to the original
broadcast SDK. ContextImpl, UserManager and StatusBarManager remain completely
unchanged; both new/changed API classes remain outside generated membership.
No native rebuild or relink occurred.

Actual admission evidence is
`S/maps-secure-settings-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`d9082607090add2821635a7f17652425dc83a5f3caf16d9b07e0ccd2e90ab219`;
the complete log hashes to
`74b68d6c18ee4556f3973bdfac5debe31cbe0b30275233865af27a09fadb7451`.
Guard/child exits are zero, cleanup is complete, swaps are zero and sampled
disk growth is zero. Current and frozen admission source both hash to
`0ed2db758376a0f93a425b99233b2f810e957831593b029a0066a45927ef69aa`.
Complete media-tool qualification is reported separately. ARM, GMS stability,
authentication and current imagery remain separate runtime checks.
