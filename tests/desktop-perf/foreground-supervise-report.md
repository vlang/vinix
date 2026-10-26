# Foreground supervisor and adapter host qualification — 2026-10-26

Latest PASS: `foreground-host10` qualifies the fixed, supervised prepare path
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
Fresh baseline build evidence, its original full check and a new reviewed
profile remain required before staging. Neither original evidence nor its
checker was modified.

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
