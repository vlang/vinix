# Compact native UI driver host qualification

On 2026-11-05 the normal and production host tools compiled with empty strict
compiler logs. Each executed two accepted geometries and 24 explicit refusals,
with the exact marker `COMPACTUI two geometries and24 explicit refusals PASS`.
These are synthetic geometry-reader controls. No compositor, QMP interaction,
real screenshot, original complete audit or guest was executed by this profile.

The driver prepares real device input for the existing compact compositor:
180×220 and 320×240 catalog entry and argument forms, draft preservation across
resize, Add file, Files, both working-folder choices, compact Run, and later
maximization for the original pointer/close checks. Its framebuffer reader
requires 1024×768 RGB, the supported body dimensions and independent inner/outer
edge pixels. Host controls qualify those reader refusals; they do not establish
that these device events reached Software or its signed child. Actual native
argument/file/cwd, painting, pointer, lease, reaping and guest shutdown evidence
remain required.

The tested V files match their independent captured copies byte-for-byte.
Their source hashes identify the edits beyond the prepared historical fixture
base. The common source/tool preparation and its main reference revision are
described in [the compact proof report](../compactproof/QUALIFICATION.md).

| Source or artifact | SHA-256 |
| --- | --- |
| `drive.v` | `69c02b9ed6692b26b9fb0dc8eba1a27b6d897aedf22f13a45cf43709ce88e102` |
| `controls.v` | `25e8b582de50be238b9ad76afddb295850293c25d2cb16edf7c50bb5501639e0` |
| `check/main.v` | `4e0ecb6d6df0dfc787dd993af93cfc779c3a8488abfb0302119ddce0730fd328` |
| normal `compactui-check-normal-01` | `93e4bd807d3eff798d70ff060e2f7cae1929efc7d239bfea14b84280f50ae0bb` |
| production `compactui-check-01` | `81c675fac468a750b8d1362e10da4b8cb1672da5b700005a64734d1a3301279f` |
| normal build receipt | `4043ca5f0f924a05b62047157f4d8c9537d1cdb8b1f90c582d40a8859b28c3e0` |
| production build receipt | `e23a85a4149be475969439212b338c8ab0c41633570ebc32d8ccf873dfbcd8f5` |
| normal control receipt | `faea09dcf48928a2d54f0d7b373237cdb9dc2378ba8592766a9937c801c83ba0` |
| production control receipt | `4c2e0c6b783b5b09aac590755bbcb838500ddf82520ab542f88b7ef23394a311` |
| each control `result.json` | `6f138e1dcdff7557eba5e077ac9374b8b972383db54ac5a9a62fef8d850c8465` |

Raw sources, generated C, executables, commands, logs, statuses and samples are
retained outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02`.
The table's executable/receipt names are relative to
`native-supervision-host-01/`. Each tool has its own `.build.json`; each
`TOOL-controls.run.json` binds the control invocation, result and budget.

The existing `build-supervision-03` sequentially owns the four commands with
the same 120-second child deadline, sampled 550 MiB available-space
admission/floor and 40 MiB host namespace including the 64 KiB final-receipt
reserve. Each command returned actual zero, observed its private group, reaped
its leader, confirmed group absence and ended with wait `-1`/`ECHILD=10`, with
no kills. The final production control receipt records 19,439,616 allocated
bytes before its final tail and 55,490,828 KiB available. These sampled bounds
are neither quotas nor exclusive physical-usage measurements.

All eight imported-module before/after map files match, SHA-256
`7574aa941eeea3b7beb3dc58c14f6c23e57aea93bd5349a09f1aa8a51da9abce`.
They capture `compactproof`, `compactui`, `launchproof`, `optionsfixture` and
`proof`; the builder also compares the complete qualified wait-width compiler
overlay before and after each command. The builder executable/source and
overlay hashes are recorded in the companion proof report and actual receipts.
Normal compilation omits `-prod`; production includes it. Both use
`-nocache -keepc` and Clang with incompatible-pointer errors mandatory and the existing
separate const-discard compatibility exception.

An independent review checked all four cleanup/status receipts, exact control
markers, source equality and every before/after module-map pair. Default host
collection was used; no sanitizer, retained-allocation or hermetic toolchain
claim is made. The host root was subsequently frozen under the complete
read-only inventory described in
[the staging projection](../compact-staging-projection.md); later consumer
outputs use a separate root. These host controls are not claimed as a completely
sealed bundle. The separate [complete inventory qualification](../compactdiagnosis/QUALIFICATION.md),
committed as `e21fc13ec`, retained actual historical refusals and qualified fresh
complete current inventories with the unchanged original auditor. The explicit
profile to consume those inventories, real compact UI interaction and native
execution remain pending.
