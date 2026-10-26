# Foreground supervisor host qualification — 2026-10-26

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
