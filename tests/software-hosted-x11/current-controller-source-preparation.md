# Current controller source preparation

`prepare-current-proof.v --prepare-controller` derives a private controller
from the retained compact controller after checking the completed
[guard/provenance qualification](current-proof-host-qualification.md).
Its only controller changes select the current metadata profile:

| Original selection | Prepared selection | Exact replacements |
| --- | --- | --- |
| `compactproof.Audits{}` | `compactproof.CurrentAudits{}` | 1 |
| `compactproof.check_audits` | `compactproof.check_current_audits` | 2 |
| `compactproof.assembled` | `compactproof.current_assembled` | 2 |

Each replacement has an exact occurrence count and inverse check. The new mode
preserves ordinary independent before/after copies and the full diff. It checks
the existing proof build/control/result/cleanup receipts and verifies that all
five proof module trees and other frontends remain unchanged. The original
`--prepare` implementation remains unchanged.

## Actual source phase, 2026-11-05

The repository revision before this report was
`17359ac17ea1da91c96943d9f5eb9f5df6107340`. Complete evidence remains under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
`current-controller-bootstrap-01` retains the source, literal bootstrap/run argv,
compiler log and actual observer-recorded statuses. Strict production bootstrap
returned 0 with an empty log. Source preparation returned 0 and the exact
PREPARED marker. These command observations make no native child-group cleanup
claim. Complete frozen old-tool-root checks passed before and after.

`current-controller-setup-01` retains both controller versions, their full diff,
input pins, complete source/module maps and source-phase result. Independent
review confirmed exactly the five changes above. Original and prepared copies
are ordinary 0644 files with link count 1 and independent inodes. The private
controller retains its original mode, owner and inode while changing only those
source selections. The source maps for all five modules and complete tree maps
match before and after. The retainer, evidence checker, wrappers, consumer build owner, native
guard, recovery guard, historical proof source and selected proof entry retain
their prior hashes. The recorded consumer allocation before the subsequent
controller build was about 15.1 MiB, within the existing 40 MiB scope.

| Artifact | SHA-256 |
| --- | --- |
| Maintained/bootstrap/captured preparer source | `2fc88bb831f5f43f40b35b042defcdbc1523048a56b956bab51ca3d3d21dfc83` |
| Preparer executable | `430de96233effd53746c4f4e9ef5b7fa518e1032619e3b65e96d4570f554478f` |
| Original `check-before.v` | `b524e00ebb8e72601c773ed58e6da4660ea99304459a7991a4f4d5ae29a135a5` |
| Prepared `check-after.v` and private `check.v` | `5f72e85d943ade7d8306fe7db1d05f9651613b22270c1bc3e07888a0d40d890a` |
| Both module maps | `710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4` |
| Both complete tree maps | `6f4d28d9cfdc893255031387c3b6879bdf3f5da7286fff078423c45b3fa29712` |
| Source-phase `result.json` | `676e5f66a8815d4e16a8e2cb5f422b4218786243efc39c225c0f8703bb817af1` |

This report qualifies source preparation only. Controller compilation, generated
C/ABI review, public API integration, actual complete pre/post audits, imports,
retainer qualification and native runtime acceptance require their own results.
No such acceptance is established by the source-only PREPARED marker.
