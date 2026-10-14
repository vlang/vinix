# Signing field temporaries and repeated publication

The pinned signing dependency now discards two redundant carry-result
assignments: field multiplication and squaring mutate their local receiver,
then return its updated limbs. The qualified compiler heap-promoted those locals
when the method result was assigned back to the receiver. Generated C from the
baseline allocates a 40-byte field element per operation; the adapted functions
use stack values. Arithmetic, carry order, encodings and public interfaces retain
their previous behavior. The [vendor generator](../../tools/packages/vendor-signing.v)
requires exactly two matching upstream sites and records the adaptation and
result hash in [provenance](../../tools/packages/signing/provenance.json).

The [allocation probe](signing-allocation-check.v) uses allocation-free V hooks
around cold key generation and signing of the first RFC 8032 reference vector.
The baseline mode requires over 70,000 40-byte requests and 2.9 MB of requested
bytes per operation. The fixed mode requires no 40-byte requests, fewer than
1,000 allocations and fewer than 150,000 requested bytes per operation. Expected
public keys/signatures come from the existing published reference vector.
These are allocation requests, rather than retained heap or physical memory.
Other table/digest/encoding allocations remain; their ownership is separate work.

The [repetition probe](signing-repeat-check.v) performs 16 legacy publications
and 16 complete release exports in one process, verifies every signature, and
requires exact canonical index/signature bytes across all iterations. Each
release uses a new output directory and the same sequence/content, exercising
the supported retry contract. The public `01` seed is only a test fixture.
The [guest controller](signing-repeat-runtime-check.v) also runs the three RFC
reference vectors with tamper/canonical-scalar refusal, and all five publisher
workspace assertions in one process. It requires all completion markers and
clean shutdown within 300 seconds on each architecture. Each receipt pins the
kernel, init, three assertion/probe binaries and serial log.

The [earlier publisher workspace evidence](publisher-workspace-check.md)
retains a fifth-publication allocation panic in one no-fork AArch64 process,
batched assertion failures and the successful per-case process workaround.
The new probe verifies repeated completion after removing the measured field
allocation source. It does not identify every allocator limit or qualify an
unbounded signer lifetime. No kernel or allocator implementation is changed.

```sh
v -nocache -enable-globals -d track_heap -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.' -o /tmp/signing-allocations \
  tests/packages/signing-allocation-check.v
/tmp/signing-allocations
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/signing-repeat \
  tests/packages/signing-repeat-check.v
/tmp/signing-repeat /tmp/new-signing-repetition
V=/path/to/v v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  run tests/packages/signing-repeat-runtime-check.v --arch aarch64 \
  --kernel /build/aarch64/kernel --state-dir /tmp/signing-arm
```

Use new state/work directories and the corresponding kernel for each target.
The maintained distribution driver includes both host probes. Source matching,
reference vectors, sanitizers and target checks must be renewed after changing
the signing adaptation. Broader roadmap 14 release gates remain open.

## Recorded results, 2026-10-14

Cold key generation fell from 74,013 allocations / 3,053,898 requested bytes to
533 / 114,698. Signing fell from 74,349 / 3,069,765 to 602 / 119,885. The 40-byte
requests fell from 73,480 and 73,747 respectively to zero. Both before/after
probes matched the RFC key/signature bytes. The baseline sources were captured
from commit `867e58eb6` in a separate module tree. Generated C excerpts retain
the two baseline allocations and their replacement by stack field elements.

Eight host runners passed: signing reference, policy, deployment, publisher
workspace, release, index schema, catalog and composition. The first four also
passed clang ASan/UBSan with leak detection disabled and undefined behavior
fatal. Source matching passed, including refusal when the adapted carry
assignments were restored; vendor regeneration checks, allocation probes, the
signed CLI lifecycle and 32-publication host probe passed. The maintained
distribution driver compiled. The ledger records 37 successful compile/run
results.

Fresh QEMU TCG runs passed on AArch64 (32.4 seconds) and x86_64
(84.2 seconds) and powered off cleanly within 300 seconds. Both used the same
retained committed kernels as the earlier failing workspace experiment. Each
ran the reference runner, all five workspace assertions in one process, and
32 identical publications/exports plus verification in one process. Receipts
pin six artifacts/logs each; generated C and build logs remain hash-pinned.

The previous fifth-publication AArch64 panic remains linked from the earlier
report. These new runs qualify the exercised 32-publication process lifetime.
They do not establish zero retained heap or an unbounded lifetime; table, digest
and encoding ownership remain separate work. Broader roadmap 14 acceptance
gates remain open.

Evidence:

- [baseline allocation probe](results/2026-10-14/signing-repeat-before.txt)
- [fixed allocation probe](results/2026-10-14/signing-repeat-after.txt)
- [host checks](results/2026-10-14/signing-repeat-host.txt)
- [individual results](results/2026-10-14/signing-repeat-host.json)
- [signed CLI](results/2026-10-14/signing-repeat-cli.txt)
- [sanitizers](results/2026-10-14/signing-repeat-asan.txt)
- [source checks](results/2026-10-14/signing-repeat-source.txt)
- [host repeated publication](results/2026-10-14/signing-repeat-host-repeat.txt)
- [baseline field C](results/2026-10-14/signing-repeat-field-before.c.txt)
- [fixed field C](results/2026-10-14/signing-repeat-field-after.c.txt)
- [compiler/source/artifact ledger](results/2026-10-14/signing-repeat-toolchain.json)
- [aarch64 receipt](results/2026-10-14/signing-repeat-aarch64.json)
- [aarch64 report](results/2026-10-14/signing-repeat-aarch64.txt)
- [aarch64 serial](results/2026-10-14/signing-repeat-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/signing-repeat-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/signing-repeat-x86_64.json)
- [x86_64 report](results/2026-10-14/signing-repeat-x86_64.txt)
- [x86_64 serial](results/2026-10-14/signing-repeat-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/signing-repeat-x86_64.qmp.txt)
