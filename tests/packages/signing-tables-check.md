# Signing table and digit ownership

Lookup tables now belong to the operation that builds them. Fixed-base
multiplication frees its 32-entry affine table and scalar digits on return.
Verification constructs its two NAF tables in explicitly owned allocations and
frees both tables and digit arrays on return. Point addition/subtraction use the
updated local receivers directly, avoiding unnecessary compiler heap promotion.

The old `Once` wrappers were allocated afresh for every invocation, so they
rebuilt the tables each time. The replacement preserves that construction and
arithmetic order without introducing a shared cache. Returned points contain
field values, rather than references into these tables. Scalar digit methods
return new arrays, and no reader outlives the multiplication call. These lifetime
changes are recorded by the [vendor generator](../../tools/packages/vendor-signing.v)
and [source provenance](../../tools/packages/signing/provenance.json).

The [host probe](signing-tables-check.v) uses the existing allocation tracker
around cold key generation, signing and verification. It checks RFC 8032 key and
signature bytes, then verifies the signature another 32 times. Every fixed
measurement must retain no allocation of at least 1,024 bytes. Total live-byte
budgets are 4,096 for key generation and 8,192 for signing/verification. Returned
key/signature buffers are included in the first two measurements. The baseline
mode requires each operation to exceed its budget with a retained large block.

These are live V allocation requests, including array overhead, rather than
process RSS or kernel retention. Small encoding, scalar and digest allocations
remain; this change does not establish a zero-allocation or leak-free signing
API. The [existing total-allocation probe](signing-allocation-check.v) continues
to guard against reintroducing the earlier field-temporary allocation problem.

The [maintained guest suite](signing-repeat-runtime-check.v) rebuilds the
reference-vector runner, all five publisher workspace assertions in one process,
and 32 publications/exports plus signature verification in one process. Both
architectures must finish every marker and power off within 300 seconds. Each
receipt pins the kernel, init, three runner/probe binaries and serial log.
Source matching must also refuse a copy with table cleanup removed. Sanitizers
exercise the new frees and the existing package policy/deployment paths.

```sh
v -nocache -no-skip-unused -d track_heap -gc none -manualfree \
  -path '@vlib|@vmodules|.' -o /tmp/signing-tables \
  tests/packages/signing-tables-check.v
/tmp/signing-tables
```

The distribution driver runs this probe alongside existing signing checks.
Broader roadmap 14 release enrollment, catalog migration, graphical integration
and application/runtime qualification remain separate acceptance work.

## Recorded results, 2026-10-14

The baseline module tree was captured from commit `347c1b623`. Measured live
bytes after key generation fell from 114,698 to 1,452; signing fell from 119,885
to 6,639; verification fell from 21,714 to 3,644. Live allocations of at least
1,024 bytes fell from one, one and three respectively to zero. Another 32
verification calls each met the same budget. Returned buffers are included for
key/signing measurements; these totals do not claim all remaining live bytes
are leaks. The RFC key/signature bytes and verification acceptance matched.

Eight host regression runners passed: signing, policy, deployment, publisher
workspace, release, index schema, catalog and composition. The first four also
passed clang ASan/UBSan with leak detection disabled and undefined behavior
fatal. Source matching refused removal of the table cleanup, vendor regeneration
passed, the total-allocation budget stayed satisfied, and both the signed CLI
lifecycle and 32-publication host probe passed. The maintained distribution
driver compiled. The ledger records 39 successful compile/run results.

Renewed QEMU TCG runs passed on AArch64 (24.5 seconds) and x86_64
(75.9 seconds), including reference vectors, batched workspace assertions and
32 publications/exports in one process. Both powered off within the maintained
300-second functional allowance using retained committed kernels. Each receipt
pins six artifacts/logs. The complete generated C and build logs are hash-pinned.

Lifetime review: each affine table and digit array comes from a fresh allocation
returned to its caller. Both NAF tables are allocated explicitly by verification
and used only during that call. Deferred cleanup runs after the last table/digit
read; the returned Point holds scalar field values without borrowed pointers.
Point additions use copies of their inputs and updated local receivers. No
shared cache, reader outside the call, or cross-thread table retirement is
introduced. Sanitizers and both target runs exercise these new frees.

Small scalar/digest/encoding ownership and broader roadmap 14 acceptance gates
remain open. These checks do not qualify an unbounded signer lifetime.

Evidence:

- [baseline live allocations](results/2026-10-14/signing-tables-before.txt)
- [fixed live allocations](results/2026-10-14/signing-tables-after.txt)
- [total allocation budget](results/2026-10-14/signing-tables-allocation-total.txt)
- [host checks](results/2026-10-14/signing-tables-host.txt)
- [individual results](results/2026-10-14/signing-tables-host.json)
- [signed CLI](results/2026-10-14/signing-tables-cli.txt)
- [sanitizers](results/2026-10-14/signing-tables-asan.txt)
- [source checks](results/2026-10-14/signing-tables-source.txt)
- [host repeated publication](results/2026-10-14/signing-tables-host-repeat.txt)
- [compiler/source/artifact ledger](results/2026-10-14/signing-tables-toolchain.json)
- [aarch64 receipt](results/2026-10-14/signing-tables-aarch64.json)
- [aarch64 report](results/2026-10-14/signing-tables-aarch64.txt)
- [aarch64 serial](results/2026-10-14/signing-tables-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/signing-tables-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/signing-tables-x86_64.json)
- [x86_64 report](results/2026-10-14/signing-tables-x86_64.txt)
- [x86_64 serial](results/2026-10-14/signing-tables-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/signing-tables-x86_64.qmp.txt)
