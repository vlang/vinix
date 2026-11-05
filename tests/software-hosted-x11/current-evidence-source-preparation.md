# Current evidence checker source preparation

`prepare-current-proof.v --prepare-evidence` derives the private evidence
checker after verifying the retained proof, controller and retainer host-build
receipts. Its only checker changes update three expected refusal messages:

| Original expectation | Current-profile expectation |
| --- | --- |
| `compact imported receipt differs` | `current imported receipt identity differs` |
| `recorded compact audit header differs` | `current recorded audit header differs` |
| `recorded original complete input path differs` | `current recorded fixed path differs` |

Each replacement has an exact occurrence count and inverse check. All existing
69 plus 20 case implementations remain unchanged. A second fixed executable
reader streams only the qualified 1,155,408-byte `retain-02`; the existing fixed
`check-03` reader and ordinary 1 MiB source/receipt bound remain unchanged.
Earlier preparation-mode bodies remain unchanged.

## Actual source phase, 2026-11-05

The repository revision before this report was
`67c9f5e6a820f1a47b8958e2e7ed03d1bbfe1811`. Complete evidence remains under
`/Users/alex/Library/Caches/vinix-codex/section14/software-launch-options-width-20261105-02/native-consumer-tools-01`.
`current-evidence-bootstrap-01` retains the source, literal bootstrap/run argv,
compiler log and observer-recorded actual statuses. Strict production bootstrap
returned 0 with an empty log. Source preparation returned 0 and its exact
PREPARED marker. These command observations make no native child-group cleanup
claim. Complete frozen old-tool-root checks passed before and after.

`current-evidence-setup-01` retains ordinary independent before/after checker
copies, the full diff, input pins and complete module maps. Independent review
confirmed exactly the three message changes and no case-logic change. Captured
versions are ordinary 0644 files with link count 1 and distinct inodes; the
private checker retains its mode, owner and inode. Before/after module and
complete-tree maps match. Controller, retainer, proof modules, wrappers, consumer
owner and guards retain their prior hashes. Recorded consumer allocation before
the subsequent checker build was 29.515625 MiB, within the existing 40 MiB scope.

| Artifact | SHA-256 |
| --- | --- |
| Maintained/bootstrap/captured preparer source | `65c00af3ece4590d75d4f0089577d3e58fd7ba2e02f9f6d08f0323feb0686a74` |
| Preparer executable | `19de1a84a1e8efaff44837c2d45df80919b071741868f8066432b1dce6b59e79` |
| Original `evidence-before.v` | `842b49a78ae764803837a804c852d270fc3c18691d0c0dd3c94f2cc1f052642d` |
| Prepared `evidence-after.v` and private checker | `dd67796f3273fec73730d6c41957d5ebb5eea1c68942daed29d3ffc62377b921` |
| Both module maps | `710351295e1be60a49b75f84348493ee85cf1f0777991a8b457ac3f4b83201d4` |
| Both complete tree maps | `6f4d28d9cfdc893255031387c3b6879bdf3f5da7286fff078423c45b3fa29712` |
| Source-phase `result.json` | `8afd829a7836974f1a3ba34586f9a6c45925bfe91f068befefdaf297ba7e58a3` |

This report qualifies source preparation only. Checker compilation, all 89
refusal executions, public API behavior, complete consumption checks, imports
and native runtime acceptance require their own results. The source-only
PREPARED marker establishes none of those acceptance claims.
