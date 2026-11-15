# M1 AGX prepared backlog, 2026-11-15

Status: **incomplete driver parity**. Asahi retains prepared jobs separately from
its 127-event hardware publication window. Vinix previously used a fixed 127-ticket
table for both, so a queue could reject further preparation while older work waited
for input dependencies or retirement. Prepared reservations now grow beyond 127.

The first 127 tickets remain inline; additional scalar-only 127-entry blocks are
allocated on demand. Allocation failure refunds the newest stamp before changing
sequence identities or user counts. Retiring the last ticket in an overflow block
unlinks it before freeing it under the manager lock. Captures retain scalar ticket
identities and physical pins, never addresses inside those blocks. Quarantine and
stopped cleanup retain their existing ownership gates. Owning workqueue state must
not be copied while reservations remain.

The strict published-event spare and host-retirement accounting are unchanged.
Prepared growth is limited by allocation failure and signed-half-counter safety,
checked against both the host-completed prefix and every retained active value.
It does not increase GPU publication credit or bypass batch/FIFO validation.

Offline validation passed:

- Twenty ASan/UBSan cycles prepare 1,024 real event tickets and retire them in
  64-event windows; all eight overflow blocks return each cycle. One hundred
  capture/cancellation cycles free middle/tail blocks, check value reuse without
  serial reuse, and preserve older-publication fallback. Both overflow OOM
  boundaries, targeted half-range guards and prior wrap/slot/pin tests pass.
- Production native publishers and reapers process 512 prepared compute or render
  jobs through eight 64-command batches. Capacity waits, captures across blocks,
  invalidation/quarantine retry, stopped caller/manager ownership and partial
  render preparation OOM return every overflow block and physical event slot.
  Prior 75 transaction, initial-prefix, barrier and TPC regressions pass.
- Real-ioctl async tests queue eight batches behind an unsignaled input while an
  independent queue progresses. FIFO, per-node VM/fence ownership and host-credit
  waits pass; this fixture injects GPU/capacity services. Standalone failure/
  recovery sanitizer regression and three V unit suites pass.
- Selected source/reference gates and all 33 generated ARM helper checks pass.
  The checker requires exactly one owned overflow allocation and matching free
  site, rejecting other temporary allocations, structural copies and missing/
  duplicated/wrong ownership sites. Independent lifetime review approved the
  allocation, unlink/free, capture, quarantine and half-range invariants.
- Isolated ARM and clean ordinary x86 cross-builds pass. Ordinary x86 excludes
  AGX. These checks do not measure whole-kernel heap behavior or execute a GPU.

Build baseline: `06518010bda37b102a17f5f6bd1f6788ddcc7976`, plus the retained event
workqueue overlay. All AGX/syncobj V inputs match the isolated checkout and final
audit snapshot; the overlay matches both retained architecture inputs. The sibling
`completion.txt` binds the feature commit to all 16 implementation/test/source-gate
snapshots; these self-referencing reports are retained separately after commit.

Omarchy head `9e989357f377fe3165aa15c61902963a888ed4b4` was rechecked. Fresh package
head `68ba33eacd652a9d61523cdb69d6e9da95eddbcc` still pins Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-prepared-backlog-20261115/`:
canonical `bundle/`, `inventory.json` and `bundle.tar.gz`. Full extraction and
restored/canonical inventories passed the unchanged inventory checker. Preliminary
free-site checker rejection, the earlier package audit and the first unsealed
staging-copy failure remain diagnostic evidence; none establishes qualification.

| Artifact | SHA-256 |
| --- | --- |
| Inventory receipt | `52c856c99a5a7843c6f1cc5a3694b8d19ad8ac9f5d515edaf003a809d0d948ac` |
| Complete archive | `44e9f008402ab8c2dc8cdb451870c670dcce95ea183f60958926c15a48e38105` |
| ARM ELF | `1dccb7879f6b03b5315af55793f373456552fb8149649f270df3b62580983bfb` |
| x86 ELF | `b9a3732e141136325461b1dcb1212a6e31ed200eaa2c435f55e6c28a3e55d6b5` |

The final audit still returns **not_equivalent** (expected exit 1). This removes
the prepared-ticket cap identified in the [previous report](m1-agx-batch-publication.md).
Modern ABI/VM/GEM/Mesa integration and other unverified driver behavior remain open.
No native GPU execution, Vinix boot, hardware test, reboot or deployment was performed.
