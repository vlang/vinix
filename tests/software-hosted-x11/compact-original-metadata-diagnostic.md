# Original compact-bundle metadata finding

This is a source-only, read-only diagnosis recorded on 2026-11-05. The original
complete checker has not yet been run for this attempt. No original bundle or
historical manifest was changed, and no current complete-audit success is claimed.

The fixed original state is beneath
`/Users/alex/Library/Caches/vinix-codex/section14/compact-launch-entry-20261026`.
Its complete manifests remain checksum-pinned:

| Manifest relative to that state | SHA-256 |
| --- | --- |
| `target-complete-seals01/targets01/inventory.json` | `8da3c48959340c6f0d0f1aef0ac032a9f398e2ca43b0785cc8532402f5e35999` |
| `target-complete-seals01/target-bootstrap01/inventory.json` | `577d9f123d39d830d03111f0cabf2cf4128b16153f6975e0d18416173a2c0b99` |

Direct `lstat` observations at 2026-11-05 05:01:37 UTC, repeated with the same
values at 05:04:40 UTC, already differ from the manifests' root entries:

| Root | Field | Historical manifest | Observed |
| --- | --- | ---: | ---: |
| `targets01` | device | 16777233 | 16777230 |
| `targets01` | mtime, Unix seconds | 1793042380 | 1793075974 |
| `targets01` | ctime, Unix seconds | 1793042380 | 1793075974 |
| `target-bootstrap01` | device | 16777233 | 16777230 |
| `target-bootstrap01` | mtime, Unix seconds | 1793042457 | 1793056662 |
| `target-bootstrap01` | ctime, Unix seconds | 1793042457 | 1793056662 |

The observed `targets01` root has inode 385026717, mode 040755, uid 501, gid 20,
link count 23 and raw directory size 736 bytes. The observed `target-bootstrap01`
root has inode 385018123, mode 040700, uid 501, gid 20, link count 13 and raw
directory size 416 bytes. Both recorded root inodes, modes and owners agree with
these observations. The original checker normalizes directory size to zero and
does not record link count, so those two raw fields are not claimed as audit
differences. The reason for the changed fields has not been established.

The unchanged original checker in
[`tests/kernel-allocs/frame-page-seal.v`](../kernel-allocs/frame-page-seal.v)
compares a complete canonical inventory, including device and timestamps. These
known root differences therefore prevent its current inventory from matching
the historical manifests. The required actual original-checker refusal remains
pending the shared execution lane; this source finding is not that execution.

The complete per-entry drift diagnosis and actual original-checker refusal are
still pending. No complete per-entry difference count, payload-byte equality or
current complete-audit result is claimed here.

The original auditor and historical manifests must remain intact. Any later
fresh complete seal must retain its own provenance and the actual original
refusal; it cannot replace or relabel the historical evidence.
