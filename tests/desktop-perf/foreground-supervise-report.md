# Foreground supervisor and adapter host qualification — 2026-10-26

## ARM foreground host qualification

PASS: `package-perf-arm-host-20261026-01` qualifies the ARM foreground owner
and adapter on source base `a8fb4cb74fc17a397473c398d8fa611990ac5511`, plus
the already imported hwhost wait-status prerequisite `8f7d7ccca` (excluded
from this change). Normal and production owners each passed the historical
twenty-four controls plus sixteen ARM controls. Normal and production ARM
adapters each passed eighteen controls. Six limit admission controls passed.
This was host-only: no guest compilation, staging, QEMU, guest measurement or
raw kernel bundle consumption occurred.

| Qualified source | SHA256 |
| --- | --- |
| `foreground-supervise.v` | `dfd3c36a9e3d0b85268bc55f29a398afce11e7732e26f3d41e7ffd482bcc46d7` |
| `run-arm.v` | `c63e6e3334357e098ad8bb8bcc6c195fe0b7f3d96b5c57ba891caa78bb0f8080` |
| `arm-init/main.v` (unbuilt guest source) | `bd9ffa5dd8883e68bce16ecafabfb7e9251e31b390e2f3d9f13b442ae578cea9` |
| existing `hwhost/process.v` prerequisite | `1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5` |

The retained host14 production bootstrap
`ffd49d0425b4893bd2d134c3626140ddfc010c13b5e6b08d6d6e1d5274547248`
first qualified the new supervisor. Its production binary then ran
`qualify-arm-owner`, `qualify-arm-adapter` and `limitcheck` in fresh states.
The complete selected V binary is
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v`, SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
Each compiler invocation cleared inherited tool choices and used coherent V
markers, private temporary/module/cache directories, `-nocache -keepc`,
inventoried absolute clang and an explicit SDKROOT. Complete selected compiler
and source maps, host compiler/SDK metadata, argv, environments, generated C,
binaries, raw logs and actual process status are retained. The installed
loader and whole SDK dependency closure are not claimed hermetic.

| Final receipt, relative to the host root | SHA256 |
| --- | --- |
| `supervisorbootstrap01/qualification.json` | `4d763a865418155a4259c59c4cfc3046132a052c9b14de412b21b45be48ce599` |
| `owner03/qualification.json` | `b61e11ce4c7f207cb213cf15f019078af24014251c3b369d7c0a6b9a68bdee30` |
| owner equal complete before/after maps | `dfdc585017b968139ae9c7eab05f2ce5692a52480552d7962880be0d759d5ba0` |
| `adapter03/qualification.json` | `38c2c6aa1ce3fc56007e816f7af0954b091d91df74f2c2df6e86b33574172a3c` |
| adapter equal complete before/after maps | `dcc07a25ed742d730d2f5d41970deb088cc5d4d914afc5ad8e664b979ba322a2` |
| `limits01/result.json` | `c22f702a133b26c151f8acf9d54c94fb7bf278767ca1308a65a68464dc7a5462` |

| Qualified executable | Normal SHA256 | Production SHA256 |
| --- | --- | --- |
| foreground owner | `c302b4f9fc135a0e7bf503fd47376fc7604d8901341b8b8abec41ab76f1b2c5d` | `5cc7bd764b37287f948e9c217a2c958d891cab5c866a01a699e6d545ae3dcaa4` |
| ARM adapter | `54957e58919cd2bceb8aa9027a47c0eb000570e9a32791191903bc39321aadc6` | `76e42323890d12e92ba9f3579bcfc6e7a973d9ea0379e0e56d84d823eb56c2d3` |

All host phases used a clean fixed outer environment and GNU timeout with
TERM, a ten-second kill grace and a 300-second deadline; inner qualification
commands retained their 120-second and 4 MiB bounds. Actual outer statuses
were zero for bootstrap (108.200 seconds), final adapter (18.117 seconds),
final owner (30.143 seconds) and limits (2.092 seconds). The adapter's original
and first compatibility attempt both exited 1 with retained compiler errors:
`string.index` returns an Option. The final compiler-only selfcheck patch
unwraps both indices with explicit missing-module errors before comparing
their order; its complete diff and all earlier sources and attempts remain
in the host bundle. Earlier owner attempts passed but do not replace the
final source-bound owner03 result.

The limit controls admitted 524288, 2097152, 2097153 and 4718592 KiB at actual
low usage, and refused 524287 and 4718593. They did not allocate to those
limits. Fresh admission measured 17048 KiB allocated and 15301 KiB apparent
across the worktree, host and external seal roots, with 52967380 KiB free.
Adding the 294912 KiB growth reserve projected 311960 KiB under the inclusive
512 MiB limit; admission required 2 GiB free and continued execution 1 GiB.
Automatic direct-tool observations targeted two-second intervals, with a
five-second maximum. Every actual start interval across host controls,
seal and check was at most 2006 ms. Each running observation retained exact wrapper
pgrep, df, allocated `du -skl`, apparent `du -skAl`, log-size probe commands,
raw stdout/stderr and status. No budget, probe or interval refusal occurred.

The immutable host root is
`/Users/alex/Library/Caches/vinix-codex/section14/package-perf-arm-host-20261026-01`.
The adjacent `package-perf-arm-host-20261026-01-seal-01` retains seal/check
logs outside that root and `complete/inventory.json`, SHA256
`ca493daf62c93f17f2b3e653e5d3bf921766ab5d4155f9ee024fe3335865f460`.
The unchanged original full checker binary SHA256 is
`fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`
and its source SHA256 is
`8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4`.
Full sealing passed with actual status zero in 12.109 seconds under a
600-second bound; the separate original check passed in 4.099 seconds under
a 300-second bound. Root independently repeated the unchanged original full
check against the same manifest and received actual status zero.
Final inclusive worktree/host/seal usage was 148896 KiB allocated and
135725 KiB apparent, with 43765876 KiB free. No host file changed after
freezing for the full seal. Source copies bind the pre-report documentation;
these documentation updates do not change the qualified code bytes.

Independent source and receipt review approved the final compatibility diff,
normal/production results, generated C, private environments, equal maps,
actual outer exits and ECHILD retirement. Guest PID1/measure compilation,
a reviewed preparation profile, runtime disk admission, staging, actual
PCI firmware boot, six-scenario results and allocation-site symbolization
remain pending. The historical candidate input table in `run-arm.md` is
not runtime authority.

## Earlier budget ceiling host qualification

Earlier host PASS: `foreground-host14` qualifies the narrow charged-budget
ceiling extension from 2 GiB to 4.5 GiB. The default stays 512 MiB; the
2 GiB admission and 1 GiB continued free-space floors, process owner, live
watcher and adapter are unchanged. Source SHA256 is
`1d550994c511dcd83cfe1a0a6d293a20ce8d72558714ed695aa362605f2a3d2d`.
Normal and production builds each passed the existing 24 controls, with
actual outer status zero in 39.50 seconds and equal complete input maps
`35c0d36efb386824affcf24abbc3c0f9fe39626af6fdd670eb64f002afce513b`.
The production binary SHA256 is
`ffd49d0425b4893bd2d134c3626140ddfc010c13b5e6b08d6d6e1d5274547248`.
The qualification SHA256 is
`3429c21fa8f93a67eced1095d43fedece2af61d5411d53db36440ecef3d05b2c`.

Six limit controls passed: 524288, 2097152, 2097153 and 4718592 KiB
were admitted at actual low usage; 524287 and 4718593 were refused.
These controls do not allocate up to the accepted limits. The receipt
`foreground-host14/limits01/result.json` has SHA256
`3949f5321eb75855b55c3296e27fbe3aca31a64f2cc28d6a425eed19d4c7e82f`.
The original full metadata inventory is
`foreground-host14-seal01/complete/inventory.json`, SHA256
`0a3cf0b82a3a1a2cbdafaeff58f80e7ca176ee2be253ea233c388b8078e37bc7`;
a separate unchanged original check and an independent root invocation both
passed with actual status zero. Worktree plus qualification
occupied about 44 MiB, below its reviewed 512 MiB budget. No staging or
guest execution occurred during this qualification.

## Fresh baseline preparation

PASS: `foreground-phase12` completed one baseline preparation with actual
status zero in 22.88 seconds. The original refused baseline described below
remains unchanged. A separately approved fresh frame-only build used frozen
worktree HEAD `b262bf48f44b6cd1e9f3b73a7d8b0a079bc98943`, controller SHA256
`20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd`
and bootstrap SHA256
`39108da8f5726becc6e36bba74fbe2489f4a80ca2b4dba7353d69282080ad44b`.
It completed with actual status zero in 156.22 seconds under its reviewed
512 MiB inclusive worktree/build budget and 900/1100-second build/outer
bounds. Equal complete source maps have SHA256
`3f73b192d63460a827f0dcafce95521f4cd7dae847c310d0c3857b9715c61dd1`.

The new authority is
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-device33-20261026/`.
Its original complete metadata manifest, under the adjacent
`frame-peer-baseline-device33-20261026-seal-01/complete/inventory.json`, has
SHA256 `b826fe4f36b1599c3bbb31c3d5749cae3e32b6944f2220f20ea14d60672b8fe9`.
Two independent invocations of the unchanged original checker passed.
Qualification SHA256 is
`82b27fdc3cfb948db51dd88c9169a1a2031dc6f3bb6ac622575dd166ba041a9a`;
x86 ELF SHA256 is
`ca807b0d800c4f5ff13b8ca1e12dad4af022a49851f54f239af8d99ef969636e`.
The fresh ELF bytes match the refused historical build, but this new complete
bundle supplies the qualification without replacing the older refusal.

The approved phase12 profile SHA256 is
`e00d034c6a2441c9736997a694708fab1660e796f4521e12efc6ac9c58fe5885`;
its read-only selected map is
`15296512f3e31b2f151f294266c027315ff90e4e4b50566d9c15791051e8c54d`.
It binds the new baseline audit, host10 owner and adapter, retained desktop,
complete selected compiler, canonical GNU readelf and literal base manifest
`fcb2e4351b11b733da9b6a1e5fb182097968773a7af71d3ae3274d77c949ea52`.
The installed loader and whole SDK dependency closure are not claimed hermetic.

| Phase12 receipt | SHA256 |
| --- | --- |
| `prepared-baseline01/prepared.json` | `70dfe42594a8c48599430447eb346543158de841ac2bd25943404e8af4434db8` |
| `prepare-owner-baseline01/preparation.json` | `ca832573413bd5dd5c1cf5dd3fa1f064c0da1cecc601c2aebe1cc971d5ef6503` |
| complete equal before/after maps | `2fd213cb17b855eb8124f3e76fa910f82bb23bebdb02dd86398de7d342c21011` |
| `foreground-phase12-seal02/complete/inventory.json` | `a27b7ac892aeae4a20d71ca4b89eb6c19d709fba4487df283c29b6f7b2d8156b` |

The owner preserved actual child status zero and final ECHILD after private
process-group retirement. It used the fixed six-scenario preparation argv;
no QEMU or guest measurement ran. The prepared tree occupies 904,168 KiB;
complete phase12 occupies 911,112 KiB. Final runtime inclusive usage was
1,675,252 KiB, below its approved live 2 GiB limit. The earlier 512 MiB
per-tree estimate understated this tree by 379,880 KiB and cannot justify
fitting another preparation under the same limit. Future profiles must
charge all retained roots and reserve at least 1 GiB per new tree plus growth.

Original seal attempt01 hit its 120-second outer deadline after writing a
manifest and remains incomplete. Fresh attempt02 used the unchanged original
checker, completed with actual status zero in 130.51 seconds, and passed a
separate original check in 84.20 seconds. Root independently repeated the
original check with actual status zero. Both external seals together occupy
about 2 MiB, within the historical limit. No file inside phase12 changed
after successful full capture. This state remains immutable; future guest
execution needs fresh baseline and matched preparations and reviewed profiles.

## Fixed preparation host qualification

PASS: `foreground-host10` qualifies the fixed, supervised prepare path
on source base `249c50cea` plus the exact existing prerequisite `8f7d7ccca`.
Normal and production supervisors each passed 24 controls: the existing six
process and ten run-profile/completion controls, plus eight prepare admission
controls including six refusals. Normal and production adapters each passed
32 selfchecks, including 19 refusals, and 18 clone controls. Four live-budget
boundary controls passed. No real base staging or QEMU execution occurred.

The new prepare owner fixes the six-scenario argv, binds the selected tools,
source, kernel, desktop, root mode and approved literal base manifest, and
charges the complete preparation through the existing process owner and live
watcher. The first full base inventory is checked before the prepared state
is created and reused as `base-before.tsv`. Read-only `admit-prepare` emits
the selected map for review; actual prepare requires its approved SHA256.

| Qualified source | SHA256 |
| --- | --- |
| `tests/desktop-perf/foreground-supervise.v` | `17b44764ba9b339c592f85552217d694ee938f8381d5d766488984887732cc7f` |
| `tests/desktop-perf/run-x86.v` | `4eb48699b23b3c784ac9dff1419a76c3d5f4f92a1a697dfc82eceecebcc24509` |
| existing `tests/hardware-platform/hwhost/process.v` prerequisite | `1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5` |

The retained host08 production bootstrap built and ran the new supervisor.
Its raw outer verdict retains the older wording “sixteen controls”; the
new normal and production nested receipts both record the actual 24 controls.
The newly qualified production supervisor then qualified the adapter. Both
qualifications preserve equal complete before/after maps, source copies,
environments, argv, generated C, binaries, process receipts and budgets.
The exact imported hwhost prerequisite is excluded from this change.

| Receipt, relative to the state prefix below | SHA256 |
| --- | --- |
| `foreground-host10/supervisor01/qualification.json` | `88203e5d18462c45f3206304cdbc11e8e3622f2a7ee1e6acaca91ef49cdb3c01` |
| supervisor before/after map | `b06297a4618c8cf5b9d37810abf7947b4fdb1bf2192af97ebdbd7f4ba029f8df` |
| `foreground-host10/adapter02/qualification.json` | `e213a2904450b54c60d56dbccdf529ba78d8a3b81d5e7bd4e923d043b5676ec3` |
| adapter before/after map | `14689d4346b23c0b481b9de106b2540b8498401c6bca7068d0139be69a68e515` |
| `foreground-host10/limits02/result.json` | `6c6b9dbb86893cbf9f30cebc6606463749eb5e8dab61b01ec138da78decb6dfc` |
| `foreground-host10-seal01/inventory.json` | `257cda6491161628a132f47cd1363d26a0cd348a782f435c1e8e5302547f3164` |

| Qualified executable | Normal SHA256 | Production SHA256 |
| --- | --- | --- |
| foreground supervisor | `1ae43bce918d782dbab13dd73373d47b1946effd4364a1f18a966a30b3741b4c` | `2d79ddcecc408af8602dc06e4accfcbbb9c4fd4121f1d9e00cae940934d34144` |
| x86 adapter | `36785be552a57bf687fa72accac7bf9ba98e8f28f088331c7df50f7a18f1c807` | `0087dbc6986bf94ed0816c4d21044c72e40bcd3dbe191d86c65dc15527c201b1` |

Interrupted `adapter01` remains unchanged without a completed build receipt;
`adapter02` is the successful fresh attempt. An existing `limits01` PASS is
also preserved; `limits02` is the fresh observed four-boundary run. The full
quiescent host10 bundle is sealed with the original complete metadata checker.
Two independent invocations of that original checker also passed with actual
exit status zero against the complete retained bundle.

After qualification, df reported 42,200,664 KiB free. The worktree, all retained
foreground01–08/10 roots and seals, preflight09 and its seal, and retained
`guard-baseline01` occupy 672,392 KiB. Adding 512 MiB each for fresh baseline
and matched prepared/supervisor trees and 128 MiB growth projects 1,852,040 KiB,
leaving 245,112 KiB under the named 2 GiB phase limit. The whole historical
state prefix occupies 3,431,252 KiB, outside that named phase; retained base,
kernel, compiler and desktop input audits are separate. Exact fresh profiles,
the selected admission maps and original baseline audit pins still require
review before staging. Guest results remain pending.

## Fresh baseline original check refusal

A later check of `frame-peer-baseline-20261026` against its original complete
inventory `503911b74414ef977bf6453a172ab25b44e5de4466164a66db9bd4d79e61bfcb`
failed with actual exit status 1: `state inventory mismatch`. Its existing
qualification is consequently refused for foreground consumption. No prepare
admission, staging or VM was executed. The initial unapproved profile and
failure are retained under `foreground-phase11`; invocation/result records
explicitly identify themselves as recorded after direct command execution.

The maintained V diagnostic `state-inventory-diff.v` requires the exact full
canonical inventory schema and compares every header, entry, field and order.
Its eleven synthetic controls passed, including all eleven entry metadata
fields, path membership, header/order differences and schema refusals. Source
SHA256 is `f6739b47a72c316b36b7f6cc0bf1c6b4330b082c916de294aaa7848ed09d65df`;
the normal host binary is
`67b1b0f82d1bb6e498c353fe80283822816a95a5f72d2a797e42d8003ddadafa`.
This diagnostic supplies no replacement qualification.

The original retained sealer captured a separate diagnostic inventory,
`foreground-phase11/baseline-diagnostic01/inventory.json`, SHA256
`a9c63e2eefb400024ce21217142702611a7f5091e7a526e8ae5b26461356793e`.
Full comparison found 1,754 entries in each inventory and 1,754 device-field
changes, with zero missing/extra entries and every other recorded field,
header and entry order equal. For example, the root device changed from
16777232 to 16777233 while its inode, mode, ownership and times match.
Device renumbering is a plausible cause; the original checker remains strict.
The complete field delta `foreground-phase11/baseline-field-diff01.json` has
SHA256 `0b4e3bb8a26e76e2881aa02de6334eb4a7619e6808ddce93612423f14b9837c1`.
The preserved phase11 failure/diagnostic bundle has full metadata inventory
`foreground-phase11-seal01/inventory.json`, SHA256
`46e046c94230306ed38a389dbadca313b81954b72f1fec5103d477c8d31f5b57`.
The subsequent fresh baseline and phase12 preparation above use a new
complete authority. Neither this refused original evidence nor its checker
was modified.

## Earlier adapter host qualification

PASS: `foreground-host08` rebuilt the foreground supervisor in normal
and production modes, passing sixteen controls each. Its newly built
production supervisor then rebuilt the maintained x86 adapter in both modes;
each passed 26 selfchecks and 18 clone controls. Four budget-limit admission
controls passed. No staging operation, QEMU or guest measurement was run.

The source base is `513a49b20`, plus the qualified foreground source and the
existing main-branch prerequisite `8f7d7ccca` for the hwhost i32 wait status.
That prerequisite was copied exactly into the isolated worktree before the
successful attempt; it is not a new change in this report's commit.

| Input | SHA256 |
| --- | --- |
| `tests/desktop-perf/foreground-supervise.v` | `37c8062538841fb7f638998b1e9f6463cdf2ede2aab26fb7569aeb27a6cfba54` |
| `tests/hardware-platform/hwhost/process.v` | `1cefdf1ce196bbe4f05813969107144dd2c123662c56815124da56c92dc5e5d5` |
| `tools/sourcecommand/core.v` | `5b5ba4be07027e508ff881602a9a9f100491f0c65164607b39ee58e987117212` |
| supervisor before/after input map | `dc0bf03da766a9c755442eab19e818229da425ba98f2bcbf0341183faf77e837` |
| adapter before/after input map | `7a8502a87819ac15e0fbd143669a10603c99510e142339a832f993ab03406772` |

The complete selected compiler and bounded compiler environment remain those
described below. The adapter maps include `plainiso` and `linuxkpi/hosttest`
along with the other imported maintained source roots. The five source roots
are retained with literal links, file bytes and modes. Before/after maps were
equal. This binds the selected compiler and recorded host compiler/SDK
metadata; it does not claim a hermetic installed loader or SDK closure.
Independent review checked all 145 retained source entries against the map,
the exact prerequisite, all process/adapter receipts and all four new original
metadata inventories. The checks passed; successful and nonzero children
preserve actual status, and refusals record it as unavailable.

All paths below use the state prefix documented below.

| Receipt | SHA256 |
| --- | --- |
| `foreground-host08/supervisor01/qualification.json` | `f6221d13c73158c9a66efc60a37eeb1029952c44be44c53684f3c32502df9ed1` |
| `foreground-host08/adapter01/qualification.json` | `ec60aba48c65ab5cdb9c2353c345bc7a31b156270aa3cbcea2c430e007d06bf4` |
| `foreground-host08/limit01/result.json` | `3d70710f71b4678c6814aa2c52671d6c795911198c2fae499072fb79b76fa259` |
| `foreground-host08-seal01/inventory.json` | `95d8586ece219b097b674ada0dfbfa45638b1e0794024c86d572226cfec4b1ca` |

| Qualified executable | Normal SHA256 | Production SHA256 |
| --- | --- | --- |
| foreground supervisor | `f51bc0cf2923f01907644a662f3d8dfb26f0739484f08b7ac2821a00819fd5ca` | `77c80951ad2cdb6667be4326217332ba159ab32cef3c20a18b2d8e708c532178` |
| x86 adapter | `012aeaadd487f1e56fa7890172a6002049d50a629c43d9553c91224727440328` | `18da221cdbd413f14064f72ce1efc662ccc6ded7bedc10f8a22dee6312ae4c45` |

The four limit controls admit 524288 and 2097152 KiB at the actual low usage
of their test state, and refuse 524287 and 2097153. They check the accepted
range and actual df/du admission; they do not allocate up to either limit.
The default remains 512 MiB; a reviewed named phase may select at most 2 GiB.

The incomplete intervening attempts are retained with complete metadata
inventories, without supplying successful adapter qualification:

| State | Outcome | Separate inventory SHA256 |
| --- | --- | --- |
| `foreground-host05` | bootstrap only; no qualification | `81b342025ebc49fd5f6444b614363f1ab82580e9a86987d55e52ed8bbb7ff6e2` |
| `foreground-host06` | limit controls passed; adapter build interrupted without final receipt | `33820937b78e6685c35b63f37fe7152212df7c0dbd121414589191a22dcda2a5` |
| `foreground-host07` | intentionally cancelled after finding the stale hwhost prerequisite; child status unavailable | `d2a17431b3b52af716b59fe7c119bb151abd96c5ef00473a329b8d61f1826bdb` |

After qualification, df reported 42,942,284 KiB free. The isolated worktree,
all eight foreground attempt roots and seals, and retained `guard-baseline01`
occupied 630,844 KiB. Reserving 512 MiB each for fresh baseline and matched
prepared/supervisor trees, plus 128 MiB growth, projects 1,810,492 KiB under
the named 2 GiB phase limit. The entire historical state prefix occupied
3,389,724 KiB, so it is not claimed to fit that named phase. Retained kernel,
compiler and desktop audit inputs outside the declared foreground roots must
also be reported separately. Fresh prepared receipts, exact kernel pins,
reviewed profiles and guest measurements remain required. This report was
updated after the unchanged maps and quiescent seals were complete.

The qualified production adapter subsequently passed its read-only input
check against matched build05 x86 kernel SHA256
`b70d1e316d29cbc22368695667b41311ec88dd6aa75362e014f64d973033e6e4`
and retained desktop SHA256
`259613b8f95ddde359a70f338baeca27bd96f0ae2b56391f6d6c3cc35de67a83`.
The proposed flags were `--scenarios=ops,churn,cache,idle,apps,drag`,
`--settle=3 --seconds=5 --rounds=1 --mem=3072 --timeout=2400`.
The maintained checker admitted the guest ELF dependency closure and pinned
the compiler, source, firmware, QEMU and staging tools. Actual exit status
was zero; the proposed output state remains absent. The log is
`foreground-preflight09/matched-check.log`, SHA256
`e5db949c6ca070d8e25a46dd4296172770b642bb050e0f39b90b2a516618e1ab`;
the original metadata inventory is
`foreground-preflight09-seal01/inventory.json`, SHA256
`0e30f76aa4b649233cb9c38cce8cb87761d88495f8c9ddd66c9fe0c9a4ac355c`.
Its explicit invocation was recorded after execution, not intercepted.
Independent artifact checks passed. The two new roots occupy 32 KiB within
the growth reserve above; no prepare or VM execution is implied.

## Earlier foreground supervisor qualification

PASS: normal and production builds each passed six real process controls and
ten prepared-profile/completion-receipt controls. No QEMU, target kernel
build, staging operation or guest performance measurement was run.

Source base: `95bd8b6a0`, plus the following qualified source SHA256 pins:

| File | SHA256 |
| --- | --- |
| `tests/desktop-perf/foreground-supervise.v` | `9a49622507cb0c834f53b85b25a404884cf36bc10039ca5a30dfb78a25a0468b` |
| `tools/sourcecommand/core.v` | `5b5ba4be07027e508ff881602a9a9f100491f0c65164607b39ee58e987117212` |

Complete selected V executable:
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v`, SHA256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
The maintained qualifier rebuilt both binaries with coherent compiler
markers, private temp/module/cache directories, `-nocache`, an inventoried
absolute clang and explicit SDKROOT. Before/after complete compiler and
source maps, with recorded host tool/SDK metadata, were equal; map SHA256
`dc28829b4c4e7f4a857910dd9be4f4a49be9eedccc6ff11262027bfb82030867`.
The installed loader and SDK dependency closure were not claimed hermetic.

The retained state prefix is
`/Users/alex/Library/Caches/vinix-codex/section14/package-perf-x86-20261026/`.
The final qualification is `foreground-host04/complete01/qualification.json`,
SHA256 `c82c3fc0b6cd56ab939d81369d5f39e318c114202a85b21447c6d1c7db197ea6`.

| Build | Executable SHA256 | Control receipt SHA256 |
| --- | --- | --- |
| normal | `b624cbc18c0cc92b8d5898d4d62e9520fd0db2c248e13ed7d4af97ff0e3cc4ef` | `d7c565f48a0e86132d51e239502b9746bfc1e08eac6e17610d35f8dfe2513657` |
| production | `e0ee598ebe97df876f549d05ce4436a5beb79626505b56b89aa161ad0da28b47` | `70d6c9a019c20024cfb258ad695ec79af00f198cbc0480c99f95b84e15569154` |

Success and exit 23 preserve their real status. Timeout, output-cap and
SIGTERM controls preserve the expected refusal and accepted output prefix;
their child exit status is explicitly unavailable. All six process cases
required final group absence and ECHILD. Exact stderr retention and a hard
64 KiB log cap were checked. Normal timeout retired in 2.032 seconds, the
same-group inherited-pipe descendant in 2.053 seconds, and production
SIGTERM in 0.035 seconds. These observations do not guarantee arbitrary
escaped-descendant cleanup. Independent final ownership/lifetime review
passed after exact-compiler and whole-state charging corrections.

The final quiescent `foreground-host04` bundle is sealed by
`foreground-host04-seal01/inventory.json`, SHA256
`f78a2431061285f1543bb5240066176f6825c20ece5cd8b71f7289a571765bd4`.
It retains the complete successful state, source copies, generated C,
binaries, environments, argv, logs, budgets and receipts. The V sealer is
the maintained `tests/kernel-allocs/frame-page-seal.v`; the invoked executable
SHA256 was `fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6`.

Earlier attempts are retained separately, without claiming the final scope:

| State | Outcome | Separate inventory SHA256 |
| --- | --- | --- |
| `foreground-host01` | exploratory descendant expectation failed; partial evidence | `84598ccf94f669b3b764e49540fcc427cac5687721281c6d6d54c813830904c9` |
| `foreground-host02` | controls passed before final qualifier corrections | `2ccdf99c58f10482636b0649aacd09a1cc3eab6e082a596c6951d60863fb700a` |
| `foreground-host03` | bootstrap failed before qualification: direct clang lacked SDKROOT | `f5bc4df171848996c1ca0d39b045f0b2d70b7d2b5c2924c7f311ec03ff78b810` |

Each inventory is under the corresponding `STATE-seal01` directory. Earlier
exploratory state does not supply the complete successful qualification.
The final usage and report documents were added around qualification; this
report was written after the unchanged before/after maps were complete.

Actual post-qualification df reported 57,064,328 KiB free. The worktree,
four attempt directories and their four seals occupied 77,384 KiB total,
below 512 MiB. Live qualifiers charged the entire state, including private
compiler caches and sibling controls, with 2 GiB admission and 1 GiB continued
free-space floors. Fresh baseline and matched six-scenario guest runs still
need separate prepared receipts, reviewed inclusive projections and actual
measurements.
