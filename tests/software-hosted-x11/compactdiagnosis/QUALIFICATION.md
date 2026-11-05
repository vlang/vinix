# Complete compact inventory comparison

`compare.v` reads two complete `frame-page-state-v1` inventories using the
original four-field manifest and twelve-field entry schema. Exact JSON
roundtrips reject omitted, extra or reordered keys and trailing data. Every ordered
entry field is compared. Only `dev`, `inode`, `mtime` and `ctime` may differ;
protected metadata, content, type or namespace differences produce a complete
bounded report and then an error. Invalid schema or a report exceeding 1 MiB
refuses without writing a partial report. Complete inputs remain unchanged.
This module neither captures nor seals a tree and creates no process owner.

## Actual production qualification, 2026-11-05

The repository revision before this report was
`2d55d550f01b43b59e0c2460e2d3d6fa7565b437`. Complete evidence is retained under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02`.
The fixed `compact-import-bootstrap-01/compact-import-04` production profile
passed strict compilation and executed all **23 explicit controls**, including
canonical-schema, protected-field, namespace, report-size and overwrite
refusals. The controls ran in `native-consumer-tools-01/diagnosis-controls-01`.
Their result hash is
`cb197a042a38020b34e073cf80c0e93d7678588082d4ce2c09f5363efff21d2e`.
No separate normal build or standalone frontend execution is claimed.

Bootstrap 03 failed before C generation on the pinned V compiler's private
`os.clean_path`, unavailable `max()` and homogeneous-map requirement. Its argv,
environment, actual exit 1, compiler log and complete module snapshots remain
in `compact-import-bootstrap-01/{compile-03.*,source-03/compactdiagnosis}`.
The reviewed correction uses an equivalent local absolute-component guard,
an explicit upper entry count and the string control count. Failed source
hashes were `2d0161b7a36bb55625ed59c0e2246abf1c2e67c4ba9593d34c5503e8499d1b5a`
and `d10282d5881af51d51bbea441e90d934439b33aebb7f1d13fa4d54f766e2f5e3`.
The failed attempt remains separate from the successful bootstrap 04.

| Qualified artifact | SHA-256 |
| --- | --- |
| `compare.v` and bootstrap 04 snapshot | `a4a3eac9206efd9d85887ba55529263acbd4b934ee405612be5a529fc44a0010` |
| `controls.v` and bootstrap 04 snapshot | `61f80faf63c787dffd98fb4105c6c02d8e19a8e44f3a718ccb4819b37c5bf941` |
| Fixed bootstrap 04 source | `919a40413995a882c494a6d8831750b0d64373cda057487d464214f08932e7a0` |
| Fixed bootstrap 04 executable | `e6c440ef7667b4a52939c8602490dd52c1de239f23131ae9b5d5e6c35df16717` |
| Producer and observer module maps, before and after | `c3e81abb9453a2ff4e31645ef308053bbd6faf4fb8a9dae90da2978af14281a8` |
| Original input maps, before and after | `23d9d0d2b7fa5878e7ffc2cb6364fb9a5c2fe05122b37a5f066679df205e33ed` |
| `compact-current-audit-observer-01/result.json` | `b9d0851a7d89f7f2682eac9ea79b5dee0be383067260bc410b7fcdb77a82fea7` |

The phase with a 120-second limit completed with exit 0 under the existing
inherited process-group owner. Its 87 samples reached at most 53,444,608 allocated bytes;
the final cumulative allocation was 53,501,952 bytes. The owned child was reaped,
its group was empty and the final wait returned ECHILD, with no kills. All
sampled `df` children completed and were retired. Complete frozen old-tool-root
checks passed before and after, and compiled bindings include both module files.

Both unchanged historical complete checks returned exit 1 and the exact
`state inventory mismatch` marker. The same unchanged original auditor then
sealed and separately checked both complete current roots successfully, writing
new evidence only in `compact-current-audit-01`. The complete comparisons found:

| Root | Entries old/new | Metadata field changes | Protected changes | Original inventory SHA-256 | Fresh inventory SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `targets01` | 3,755 / 3,755 | 3,913 | 0 | `8da3c48959340c6f0d0f1aef0ac032a9f398e2ca43b0785cc8532402f5e35999` | `9ab4265863021ce59410851dbeabe4de2cafb86ab07f335f6fe9959a47022753` |
| `target-bootstrap01` | 25 / 25 | 37 | 0 | `577d9f123d39d830d03111f0cabf2cf4128b16153f6975e0d18416173a2c0b99` | `ea4c3b1fb221baeacb97ad9a605841f5d7acf3a7385723fbd792c368c2d74591` |

The full per-field reports are retained as `targets01-differences.json`
(`37477cab9cb0c0885c49d478bbd07c7b4ee15d4811f7efb56816eb02a33a681d`)
and `target-bootstrap01-differences.json`
(`9501c2c8c70345a3392bca095b742cc6c10e8ef7ee4f3ff781c572b80acac15a`).
Both complete original inventory hashes matched before and after. Historical
refusals remain refused; this comparison makes no cause-of-change claim. Compact
imports, guest execution and native Launch options acceptance remain pending.
