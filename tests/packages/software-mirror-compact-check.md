# Compact offline-export authoring

At 320×240 and 400×300, Software provides an editable export destination,
selected/installed/deployment scope, deployment source navigation and Review.
A saved deployment's source is displayed read-only and retains its receipt
SHA-256. Smaller canvases provide Back, review Stop/Cancel or publication wait;
enlarging is required for editing and full publication confirmation.

The implementation changes `desktop/software_mirror.v`; the focused maintained
fixture is `software_mirror_compact_fixture.v`, driven by
`software-mirror-compact-check.v`. Validation starts from revision
`981cee1689a9596ce8d6809ac2ff088dcf3f004b`; the source inventory binds the actual
modified source bytes, rather than claiming that revision includes the change.

## Reproduce

Compile the maintained driver with `-prod -backend c -nocache -cc CLANG -o CHECK`.
Use the same V executable for the driver and fixtures, with compiler fallback
disabled (`V`, `VEXE` and `V_MACOS_V3_CALLER_VEXE` set to that executable;
`V_MACOS_V3_NO_FALLBACK=1`). Invoke:

```
CHECK V_EXECUTABLE CLANG_EXECUTABLE UI_MODULE_DIRECTORY NEW_EXTERNAL_OUTPUT
```

The UI module directory must contain `ui2/v.mod`. The output parent must exist;
the output itself must be new and outside the checkout. Every build and fixture
run requires actual `/bin/df -k` Available ≥1,048,576 KiB. Post-step
`/usr/bin/du -sk` observations cover the whole dedicated output parent, including
earlier attempts and the driver, and must remain ≤102,400 KiB. These observations
are not a hard quota on compiler writes. Failures are retained and stop the
driver. Successful generated C is retained as `.c.gz`; complete decompression
must equal the original bytes before the owned raw generated copy is removed.

## Qualification

PASS: all five focused host modes, both production target C-generation checks
and the supplementary historical normal Software fixture. No target guest or
image is involved. The final bundle is:

`/Users/alex/Library/Caches/vinix-codex/section14/software-mirror-compact-20261026/run-05`

Its `result.json` SHA-256 is
`594daf9be4f0efc7d3ef294dd891c4ec67ffcfa17d6f0f0afbc34bd3d321660d`.
The project source inventory (`sources.json`, 319 files) SHA-256 is
`405b0cba49b6522b25b32f482c59be848ec68aa6f6c796db95a9d01d844d49e2`;
`artifacts.json` is
`5d056101b94e9fbe376bd0aaca68b068e2b09b23abd81cc3ec854dd760040724`.
The final observed whole-parent size was 90,864 KiB (90,828 KiB before writing
the receipt); each retained build/run space log passed the actual-df gate.

The tested production file SHA-256 is
`9cc3e481814c18d748c364916562d0d3b4034ed33981a0d26723bcf21fcf187f`,
the fixture is
`f5f3078c3c1d0c2b7ff2865628761dab9a2699c7cbf5d0ceaf8214dcbd94fc46`,
and the maintained driver is
`4b93c86aba962dc07d5718c7b09ca10d55dd01fb3481acaf824290a6bbd4fce4`.
The parent `run-05.argv.json` records the literal invocation. It uses V
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`
and Clang 23
`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`;
their canonical executable paths and actual command arrays are retained.

The focused entry uses explicit error checks and checked child barriers under
normal, production, tracked normal, tracked production and ASan/UBSan builds.
It checks six canvas sizes (320×240, 400×300, 180×96, 319×239, 319×240,
320×239), field/scope navigation, invalid-paste retention, literal Unicode and
shell-looking argv, captured source/SHA binding, malformed/diagnostic/changed
source recovery, exact partial and complete-before-exit review cancellation,
Stop/reaping, and a live approved publication that refuses cancellation. The
compact reader cannot mark full-review paths visited or expose confirmation.
Linux arm64/amd64 production C generation supplements host behavior; it does
not link or execute target code. The historical full Software fixture runs
once in normal mode because it contains assertion side effects.

Tracked checks include a positive 37-byte/one-record allocation and balanced
free control, then measure 1,000 warmed steady draft/navigation cycles (12,000
trees) per tracked mode. This bounds steady rendering, not complete child
lifecycle allocations or all Software paths.

Original project/UI source and staged adapters are inventoried separately and
rehash-checked after execution; V/Clang executable digests are also checked.
The staged historical fixture uses its flat 28-pixel headless field helper,
instead of the native nested 30-pixel mounted control. These checks qualify
Software control geometry and handlers, not native field rendering, compositor
screenshots or full section 14 acceptance. UI headless compatibility guards are
confined to the staged module. The compiler's vlib/thirdparty, headers, linker
and transitive tools remain external; this is not a hermetic build.

Earlier attempts 01–04 remain diagnostic evidence: a fixture compile refusal,
two incorrect fixture expectations about retained diagnostic pages, and an
invalid fake progress message. Their source snapshots, argv and logs remain.
`preserved-generated.json` in the output parent binds losslessly compressed
owned generated C/binaries to original and compressed SHA-256 values; every
copy passed a complete byte comparison before removal. That earlier ledger
captures content, not filesystem metadata: restore a failed-attempt executable
to its original name and use mode 0755 when needed. The maintained optional
`CHECK preserve-generated NEW_EXTERNAL_RECEIPT GENERATED_PATH...` mode also
records actual permission bits in decimal, exercised by
`preserved-generated-modes.json`. Restore those with V
`os.chmod(path, recorded_decimal.int())`, or convert the mode to octal before
using shell `chmod`. These compressed diagnostics do not replace any input
required by a historical checker.
