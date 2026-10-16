# Deployment snapshot construction lifetimes

Snapshot construction now owns and retires its JSON encoding buffer, including
capacity growth, while returning an independent string. Saved files append their
LF before the metadata-size check. Their SHA-256 receipts and audit input digests
use the existing hash helper that retires its context, state and checksum.
Output fields, ordering, escaping and exact-byte digest semantics are unchanged.

The installed selection plan now borrows manifests from the decoded installed
state. Its callers already retired only the selection array buffer and separately
closed that state after constructing the independent lock. A normal typed push
implicitly deep-copied each manifest, orphaning its nested allocations. Raw
pointer insertion preserves the intended borrowed lifetime; exported locks still
clone their own fields and survive retirement of the selection buffers.

The retained pre-change assertion measured **144,290 bytes retained by ten
16-package lock exports**, despite closing every returned document. Ten audit
comparisons retained zero bytes. The final tracker checks 1,000 export/encode/hash
cycles, 1,000 comparisons, and 1,000 borrowed selections with successful owned
exports and missing-root refusals. Each scoped measurement must retain zero bytes.
The inclusive metadata boundary, including the optional LF, is tested independently
of semantic admission; overflow retires its growth buffers and returns no string.

Functional assertions cover 4,096 roots and records, an 8,192-row disjoint audit
union, returned-field ownership, repeated close, and public snapshot/save/audit
results with revoked publishers, restricted policy and damaged offline catalog
and replay history. They preserve configuration, activation, state bytes, cache
objects and generation names, and never replace an existing destination.
ASan/UBSan run the construction and ownership assertions as well.

This is **not whole-service memory qualification**. An expanded intermediate
measurement hit the 16,384-record tracker limit. Reducing the combined public
snapshot/save/audit/existing-file-refusal loop to five iterations measured
79,940 retained bytes after the encoding/hash fix and 54,440 after the borrowed
selection fix. Those sources, executables and raw logs remain pinned. The raw
five-iteration logs mistakenly label the loop as 100 iterations; the retained
source establishes the actual count. Remaining allocations elsewhere in the
public paths require separate work; functional public-path tests do not assert
zero whole-service retention.

The signed CLI lifecycle checks withdrawn versions, exact saved bytes and
receipts, sequence-floor matches, missing/changed drift status, ordinary readers
and savers, existing-file refusal and reproduction from newly authenticated
offline media. The maintained audit guest suite also runs the new construction,
size and ownership fixtures on both architectures with frozen kernels. These
checks do not qualify graphical login, catalog migration or broader foreign
runtime compatibility; roadmap 14's wider acceptance gate remains open.

## Recorded results, 2026-10-16

All **38 focused compile/run checks** passed: ten core and three protocol pairs, one native tracked-allocation pair and one ASan/UBSan pair, six CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **25.4 seconds**, x86_64 **22.7 seconds**. These functional deadlines are not performance qualification.

- [baseline regression](results/2026-10-16/deployment-observation-baseline.txt)
- [host results](results/2026-10-16/deployment-observation-host.json)
- [host summary](results/2026-10-16/deployment-observation-host.txt)
- [core assertions](results/2026-10-16/deployment-observation-core.txt)
- [tracked construction allocations](results/2026-10-16/deployment-observation-memory.txt)
- [sanitizers](results/2026-10-16/deployment-observation-asan.txt)
- [signed CLI](results/2026-10-16/deployment-observation-cli.txt)
- [initial fixture attempt](results/2026-10-16/deployment-observation-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/deployment-observation-toolchain.json)
- [aarch64 receipt](results/2026-10-16/deployment-observation-aarch64.json)
- [aarch64 report](results/2026-10-16/deployment-observation-aarch64.txt)
- [aarch64 serial](results/2026-10-16/deployment-observation-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/deployment-observation-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/deployment-observation-x86_64.json)
- [x86_64 report](results/2026-10-16/deployment-observation-x86_64.txt)
- [x86_64 serial](results/2026-10-16/deployment-observation-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/deployment-observation-x86_64.qmp.txt)
