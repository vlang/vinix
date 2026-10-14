# Catalog admission ownership

Catalog loading now authenticates and decodes each configured repository's
selected snapshot once, checks its retained replay floor, then transfers decoded
manifests into the result. The signed bytes, wrapper records, history and index
envelopes are temporary. Returned manifests remain owned independently of those
records; configured repository/key strings keep their existing borrowed lifetime.
The public catalog shape, package ordering, identity matching and trust rules
remain unchanged. A failure in a later repository retires earlier transfers.

Previously `load_catalog` verified and decoded every selected index for floor
checking, discarded those decoded values without closing them, then repeated the
same work to build a catalog. Snapshot filtering and catalog growth also retained
unnecessary copies. The new path avoids that duplication, retires its temporary
records and releases partial results on failure.

The [core fixture](../../tools/packages/pkgcore/catalog_ownership_test.v) checks:

- Returned descriptions, arguments, payloads and provenance remain usable after
  their decoded wrappers/index have been retired, including growing a catalog
  beyond its original capacity.
- Later signature, signed JSON syntax/schema, expiry, sequence rollback,
  equivocation, ambiguous ownership, missing snapshot and changed URL failures
  preserve persistent metadata and configured identities.
- Revoked snapshots are ignored, while the same invalid signature is rejected
  for an enrolled publisher.
- After retiring the independently decoded result, 64 repeated loads remain
  within a 12 KiB plus path-length budget and 110 tracked allocations per load.
  This guards the removed duplication; it is not a zero-allocation claim.

The initial paired host measurement, using the same one-package fixture, retained
29,029 bytes / 168 allocations before the change and 10,104 bytes / 93 allocations
afterwards. Validation and other reader allocations remain outside this cleanup.
Whole-service and broad catalog memory qualification remain open; the earlier
1 GiB guest failures are recorded in the
[metadata preflight report](state-preflight-check.md).

The [target controller](catalog-ownership-runtime-check.v) runs these ownership
assertions and the existing signed [service probe](state-preflight-check.v), which
uses a near-limit catalog to exercise reviews, install/deployment refusal and a
bounded retry. It uses retained committed kernels. Host ASan/UBSan checks validate
the new lifetimes. These checks do not qualify graphical sessions, public catalog
enrollment, foreign runtimes or power-cut durability.

## Recorded results, 2026-10-14

The paired earlier fixture revision retained 29029 bytes / 168
allocations before and 10104 bytes / 93 allocations after the change.
Its source, both executables and the previous repository implementation are
pinned. The final maintained fixture passed 64 loads/retirements within its
scratch budget; this does not claim zero allocations or whole-service freedom.

Eight host runners passed: catalog ownership, index schema, snapshot schema,
retired trust recovery, administration, review, service and distribution. Core
ownership/failure checks and the signed near-limit service probe passed clang
ASan/UBSan with leak detection disabled and undefined behavior fatal. The signed
CLI lifecycle and real CLI maintenance probe passed. All 29 host compile/run
results are retained.

Fresh QEMU TCG runs passed on AArch64 (19.7 seconds) and
x86_64 (30.8 seconds), each running the ownership assertions
and signed service maintenance probe before shutting down within 300 seconds.
Retained committed kernels exclude concurrent kernel edits. Five-artifact
receipts pin kernel, init, both programs and serial output; generated C/build
logs are pinned in the ledger. Broader catalog memory, graphical sessions and
foreign runtime release acceptance remain open.

Evidence:

- [paired baseline](results/2026-10-14/catalog-ownership-baseline.txt)
- [host results](results/2026-10-14/catalog-ownership-host.json)
- [host checks](results/2026-10-14/catalog-ownership-host.txt)
- [ownership and memory assertions](results/2026-10-14/catalog-ownership-core.txt)
- [signed service probe](results/2026-10-14/catalog-ownership-probe.txt)
- [sanitizers](results/2026-10-14/catalog-ownership-asan.txt)
- [signed CLI checks](results/2026-10-14/catalog-ownership-cli.txt)
- [source/artifact ledger](results/2026-10-14/catalog-ownership-toolchain.json)
- [aarch64 receipt](results/2026-10-14/catalog-ownership-aarch64.json)
- [aarch64 report](results/2026-10-14/catalog-ownership-aarch64.txt)
- [aarch64 serial](results/2026-10-14/catalog-ownership-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/catalog-ownership-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/catalog-ownership-x86_64.json)
- [x86_64 report](results/2026-10-14/catalog-ownership-x86_64.txt)
- [x86_64 serial](results/2026-10-14/catalog-ownership-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/catalog-ownership-x86_64.qmp.txt)
