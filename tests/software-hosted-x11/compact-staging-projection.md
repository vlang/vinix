# Compact staging projection

`compact-projection.v` measures the exact files selected by
`compactproof.import_build`: a complete independent source copy, three generated
C files and the desktop ELF for each architecture. Each file is rounded to
4 KiB and each directory costs 4 KiB. Import selection rejects links and special
files. The separate frozen-tool inventory records every path, metadata, file
digest and link target without following links.

The source-only work remains at
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02`.
No compact import, original audit or native guest was run in this phase.

The first projection retained full 40 MiB writable allowances for both tool
roots. It correctly refused at 275,202,048 bytes, above the unchanged 256 MiB
ceiling. Its report and source/binary/log remain preserved. The old tool root
then became read only; later checks and tools only read it. The historical
40 MiB owner limit and its failed attempts remain unchanged.

The accepted projection charges the complete frozen old root under 31 MiB,
supported by both its 31,797,248 allocated bytes and its 31,952,896 bytes of
rounded apparent data. It reserves the full 40 MiB bound for a new consumer
tool root, 10 MiB for all staging bootstrap attempts, 16 MiB for observers,
audit logs, import manifests and final receipts, and 16 KiB for the new import
root/app directories. Initial/final/admission sample receipts are included in
the observer allowance. Both imports require 164,036,608 rounded bytes.

The resulting total is **265,764,864 bytes (253.453 MiB)**: 573,440 bytes below
the existing 254 MiB pre-final threshold and 2,670,592 bytes below the final
256 MiB ceiling. A later producer still has to pass actual admission and
sampled allocation checks. This forecast does not qualify native behavior.

Retained pins:

| Artifact below the state root | SHA-256 |
| --- | --- |
| `compact-stage-projection-02.json` | `67ae49eeb2f43ffdc16cbd093a43c3dd93e7a8c4933854913c0e7464ececb1e6` |
| `compact-frozen-tools-01.json` | `14a1d04a2288ff548171b8428cabe92582a8ceefc7ea648e25f07f5ef00da579` |
| `compact-import-bootstrap-01/projection-source-02/compact-projection.v` | `372bc38b3fd3dd52995bf0434840eed16d7e02341570f10ffa504ed3e607c857` |
| `compact-import-bootstrap-01/compact-projection-02` | `d5b6902bd3b96051c15b805fbaf10d0c855ea9323e3b16a8fff26fd17d802b78` |

The strict production bootstrap, accepted projection and independent
`--verify-frozen` invocation all exited zero. Their private compiler environment
used the qualified wait-status overlay; stdout and logs are retained in
`compact-import-bootstrap-01`. The first bootstrap retained generated C. The
second projection helper omitted `-keepc`; its source and executable remain.
No historical artifact was removed or rewritten. Future phases must compare
the complete frozen inventory before and after consumption and charge it,
all failed attempts and both tool roots in aggregate allocation checks.
