# Browser transport shared library, 2026-10-26

The maintained `build-current-launch.v --browser FRESH_ROOT` role now emits
`lib/libvinix-android-browser.so`. The native WebView bridge already loads this
library by name; previous current-build roles did not produce or package it.
The role retains its compiler, source closure, native inputs, generated C,
header inventories, strict shared-link command and consumed inputs, and checks
the four public browser symbols against both frozen source and linked exports.

The builder and public ABI regression are committed in `acd253f1a`. Cross-building
found a local `poll` variable shadowing the C `poll` function in generated C;
`1c6a46a51dcb1b342c3d6aaea4f0f532a28e6adc` renames it to `watched` without
changing polling or descriptor ownership. That full revision is the successful
build's recorded source revision. Both changes received independent review.

The successful role is
`/Users/alex/.local/state/vinix/android/current-browser-build-2026-10-26-r2`:

- `sha256.json`: `af2373af972966cc72b2b8eb8ba90d73063fad5d24a4a76b29ce8daff78062f3`.
- `lib/libvinix-android-browser.so`: `ad55dfd4d1e7fd11e092ef75bada71eb4c176845451b80dc023eb98c20a2935b`.
- Pinned V compiler: `0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`.
- Native baseline: `headless-service-native-build-2026-10-26-r5`, manifest
  `d99195272b8af813679cf54fed9f1e0341e6f1115804ac09c1cd2d5a8f942e3e`.

The AArch64 build passed the maintained builder's self-test, frozen source and
dependency checks, strict C compilation and shared linking with `-z defs`, and
exact four-symbol ABI verification. It uses the retained static zlib producer
and requires no additional dynamic runtime dependency. The independent
`build-bundle-check.v` audit verified all 815 retained files and exact membership;
its external `current-browser-build-r2-audit.json` receipt has SHA256
`ceb82974f9061a4e944b70d53c44e74b865f9f4a284360b81cfd73f6cac06676`.

All five host regression functions passed after the rename, including public
ABI cookie roundtrip, borrowed payload handling and closing the owned socket.
An explicit fresh `-new-compiler` build and execution of the test file also
passed. Its retained executable has SHA256
`71574d85c5b0baee53f78adf4033fe1474e10b658c1bcdf77e8ea5fd56e27d88`.

Complete execution evidence remains outside Git under
`/Users/alex/.local/state/vinix/android`. The full unsuccessful
`current-browser-build-2026-10-26-r1` and its driver log are preserved alongside
the successful r2, host test logs, test executable, builder and independent
auditor. These quiescent roots are bound in place by
`current-browser-evidence-2026-10-26-r1/manifest.json`, SHA256
`60d879adbed73d007eb2a5afea611d0c83609178d9e4e843376e6aa80bf034e4`
(13 roots, 1,854 typed entries). The committed generic inventory machinery in
`tests/linux-compat/pidfdwait-seal.v` created and rechecked this seal; its format
name establishes no guest execution claim. This build evidence does not prove
successful Google account login; the fresh staged guest must exercise that flow.

The packaging change is committed in
`3b0b2befacff7ae74c495bbbe4baa77364051eb7`. The Maps stager and coupled request
refresher now require a separate `browser_client` reference, retain its receipts
at appended input index 8, and copy the selected library into runtime `/usr/lib`.
The existing `browser` reference continues to select the WebKit helper. The
checker verifies the exact ABI, selected account runtime dependencies, frozen
compiler commands, canonical link trace and consumed input agreement, and
complete header listings. Existing role indices and sealed r4 evidence remain
unchanged. The final packaging diff received independent review.

All five staging module test files, both tool self-tests, and the actual browser
r2 plus account r7 audit passed. Negative controls cover missing or mismatched
references, ABI and outputs, commands and receipts, dependency selection, ELF
contracts, and removed or injected link/header inputs. The ready host tools are
`maps-account-stage-browser-2026-10-27-r1` (SHA256
`041fc5d8673654eef86d8f518d3223f894a3ab6d0a4a48bd4a72feb662d0b6a0`)
and `refresh-coupled-browser-2026-10-27-r1` (SHA256
`52ab628560dcc471ec98f0ef47b350a8dd5c23f42a98c2276d2a8536b91efab1`)
under the same external state directory.

The complete packaging validation seal is
`browser-client-stage-validation-complete-2026-10-27-r1/manifest.json`, SHA256
`04662a8385756b0a2e0f1d731fd62542ce27480ab2aa70455eb478747ceaeeea`
(19 roots, 2,747 typed entries). It binds the complete original browser r2,
account r7 and static-zlib producer bundles, source snapshots, all retained
successful and failed compile/test logs, binaries and refresher fixtures. Its
validation record also records the initial console-only mutable-vlib compiler
mismatch. The final module test log is
`browser-client-stage-module-tests-2026-10-27-r3.log`, SHA256
`98f99c182611b34a5444693ff7bae9615d435a782c4c84430ffaf9223842bf54`.
