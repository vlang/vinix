# Wine graphics dependency checkpoint, 2026-11-12

Source baseline: `639705bbd05b09ced4f01d756b0fae277655a27b`, plus this
checkpoint's graphics producer, layout admission and evidence controls.

Wine loads FreeType and Fontconfig by name, outside the ELF `DT_NEEDED`
closure. Runtime construction now explicitly copies the pinned distribution's
ordinary `libfreetype.so.6.20.2` and `libfontconfig.so.1.12.1` under their
SONAMEs, traverses their dependencies and includes `/usr/share/fonts`, including
hidden files. Every consumed ELF input is recorded even when a destination
alias has already been copied.

The independent native retainer requires both original ordinary library
inputs, their recorded hashes and exact copied bytes. Both libraries must
come from the same distribution. It checks the complete original/copied font
file sets, exact bytes and recorded provenance, with at least one TrueType
font. Prepared-payload hashes alone cannot substitute for original inputs.
The font tree uses one directory recipe selector. The unchanged 1024-selector
limit still applies; the final runtime has 1013 selectors and 1028 files.
The earlier flat recipe correctly refused with 1028 selectors.

The synthetic layout checker admits its baseline and retry and rejects 13
missing, changed, linked, hidden-file and font-set controls in normal,
production and ASan builds. Synthetic fixture bytes qualify layout/provenance
only. Initial cleanup failures remain preserved; typed string-array cleanup
was corrected before these passing runs. No general allocation-retention
claim is made.

Fresh `prepared-fonts-x86-02` and `prepared-fonts-arm-02` produce signed
console runs `native-fonts-x86-02` and `native-fonts-arm-02`. Both pass the
existing Windows API, W^X, vectored exception, ordinary identity, private
prefix/socket, outside-write refusal, natural exit and lease checks.
The independent retainer admits original and copied baselines in every
control shard. All **59 x86 and 68 fork-safe ARM refusal controls** pass,
including omitted graphics provenance and resealed changed graphics bytes.
The coverage checker verifies exact unique assignment across four shards per
architecture. Its baseline/retry and nine refusal controls also pass.

Complete current raw evidence is retained outside Git at
`/Users/alex/.cache/vinix-wine-gui-20261112`. The qualified collection receipts
are `controls-fonts-02-x86-coverage.json` (SHA-256
`4c4b4a70b885e1c31c9c27387014a33feea389307ab48a953234fd54253c9fcc`)
and `controls-fonts-02-arm-coverage.json` (SHA-256
`7e5bfcda18aa52182d893a4df75de6783181fc12750a220938de463221cfd0cf`).
Both native runs preserve 491 admitted parsed sources with original modes in
their adjacent `native-fonts-*-sources-02` directories. Original namespaces
and the complete [pinned dependency bundle](wine-forksafe-retention-check.md)
remain required by historical auditors. Earlier attempts and the first
matrix's wrong ARM control-input selection remain failed evidence.

This checkpoint repairs missing graphics dependencies; it does not qualify
graphical execution. The calculator now reaches window/control construction
on a real authenticated private Xvfb display, but the current run fails before
returning from `ShowWindow`. Fontconfig cache warnings and Wine startup
diagnostics remain in the logs. A numeric-hostname diagnostic still fails and
is explicitly excluded from ordinary-host qualification. No permission,
kernel policy or Wine instruction change is made here. Window painting,
pointer input, natural graphical close and independent GUI evidence admission
remain open.
