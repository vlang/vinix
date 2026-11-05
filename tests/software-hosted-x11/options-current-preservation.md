# Launch options source preservation

`preserve-options-current.v` independently copies the selected current sources
before a later profile change. It captures every ordinary file in the five
fixture module trees, all fifteen fixed front/builder/wrapper/supervision
sources, the native guard, recovery guard, qualified wait helper, main binder
and preserver. Symlinks and special files refuse. Each copy preserves its file
mode and must have link count 1. Complete source maps before and after must
match, including every source pinned by the retained `check-02` and `retain-01`
build receipts and their module maps.

The helper records original path, independent capture path, digest and mode for
every file. It verifies the complete final capture namespace and enforces at
most 128 files and 1 MiB per file and in total, including its five JSON records.
This preserves source bytes and modes; it makes no timestamp or complete
historical-bundle metadata claim and contains no process-owner logic.

## Actual qualification, 2026-11-05

The repository revision before this report was
`f8beb965f6b74e07757acb83414fd170decdbeee`. Raw evidence is retained under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
Strict production bootstrap returned actual status 0 with an empty log. Its
literal argv retains the qualified compiler, coherent caller markers and
private cache/module/temp paths. The separate `--preserve` invocation returned
actual status 0 and the exact PRESERVED marker under a 30-second bound.
Bootstrap and command-status records are observations of actual tool results;
they establish no native child-group cleanup claim.
The actual capture status is retained in `preserve-run-01.observer-exit.json`.

`source-before-current-01` contains **32 source copies**, totaling 334,246
logical bytes, plus five records. The complete capture occupies 460 KiB. An
independent reread of all 32 captured files matched the mapping, and their
ordinary 0644 modes and link counts of 1 were checked. The recorded consumer
allocation after this phase was 10,989,568 bytes, within its existing 40 MiB
scope. Source qualification, pre/post maps and final capture checks passed.

| Artifact | SHA-256 |
| --- | --- |
| Maintained/bootstrap-snapshot preserver | `9e4ee8e941235f528c6ab71cdb83606a64832409e826eb2e3a2d8b54ef9b4ab2` |
| `preserve-options-current-01` executable | `02e47bc109d5af25e84f74861f6809a3c4fa1401bcf953eada4cbd4e83fe2e5b` |
| `source-before-current-01/sources-before.json` and `sources-after.json` | `16fe3075ad4a6b39241a3f034848bb0622ec5b17aa42f96958788fddae407b9e` |
| `source-before-current-01/mapping.json` | `79a09c723f8bfb30a57b773576405bf9849544da6fb0882574e86e919b5297e6` |
| `source-before-current-01/capture-tree.json` | `7f1ab6f14fbf79e905b397b9b8b55c6f6e9b5c0591848ae292f228102104d464` |
| `source-before-current-01/result.json` | `01fd31eb692bf53b94e435df2ee20f05410312c5104444284db06f8b8bb5663b` |

Complete frozen-tool-root comparisons matched the previously completed baseline
and the post-copy observation. The nominal before-probe overlapped the brief
copy after its tool call yielded. These receipts establish equality with that
frozen baseline, without establishing an immediately completed pre-copy probe
or continuous observation. The helper's own source pre/post checks independently
matched all qualified source bytes. `preserve-frozen-comparisons-01.json`
retains the actual statuses and ordering limitation.

The capture completed before free space fell below the required 2 GiB admission
floor. The current profile remains uncompiled, and imports and native guest
acceptance remain pending. This preservation claims only source copies and
their checks. Historical build receipts remain unchanged; later profile
changes and native acceptance require their own qualification.
