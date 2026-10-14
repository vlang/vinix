# Recovery from recorded, unusable publisher keys

An older installation can retain a cached index and replay floor for a key that
fails current publisher curve admission. Revocation previously disabled the key
but left that cache blocking every refresh, repository listing and enrollment.

History migration now permits that snapshot to be superseded only when:

- Its ID/key is disabled in the effective configuration. Enrollment review and
  apply use the same proposed configuration for an explicit key replacement.
- Retained history already contains that exact ID/key and index digest.
- The pinned index has a complete valid shape and exactly the retained sequence.
- The key fails current cryptographic admission. Valid keys still require their
  signatures, including revoked keys and byte-identical cached indexes.

The exception adds no authenticated metadata and never creates, lowers or
removes a replay floor. It does not make the old key eligible again. Review,
listing and enrollment keep the old cached bytes; only a successful refresh
publishes a new cache after history is durable. Missing or changed history,
different index bytes, malformed wrappers and enabled invalid identities still
fail closed. Restore trusted recovery records rather than deleting history.

The [trust assertions](../../tools/packages/pkgcore/trust_recovery_test.v) cover
exact identity/digest/sequence requirements, mirror changes, incomplete and
ambiguous pinned text, valid-key signature refusal, expired legacy metadata and
empty refresh with unrelated floors retained. The
[lifecycle probe](publisher-recovery-check.v) models a legacy installed package
with both invalid- and valid-key history. It exercises read-only review,
reviewed replacement and revocation/re-enrollment, stale reviews, live signature
tampering, refresh, same-version provenance repair, old rollback refusal,
reviewed uninstall and retained personal data. Its credentials are public RFC
fixtures, never release credentials.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/publisher-recovery \
  tests/packages/publisher-recovery-check.v
/tmp/publisher-recovery /tmp/new-publisher-recovery
```

Production publisher enrollment, catalog migration, ordinary graphical session
integration and broader runtime/device qualification remain roadmap 14 gates.

## Recorded results, 2026-10-14

The baseline control captured `6bd608994` and reproduced blocked valid-key
re-enrollment after reviewed revocation, with exact retained invalid-key history
and cache. The new lifecycle probe passed both replacement and revocation/
re-enrollment paths, including missing/mismatched floors, changed cached bytes,
stale reviews, live signature tampering, same-version provenance repair, old
rollback refusal, reviewed uninstall and retained personal data.

Twelve host assertion runners passed: trust recovery, administration, service,
Software view, policy, signed index, history and snapshot schemas, review, state,
deployment and distribution. Trust recovery, administration and the lifecycle
probe also passed clang ASan/UBSan (leak detection disabled; undefined behavior
fatal). The signed CLI lifecycle, existing publisher-key admission probe and
qualification-driver compilation passed. The ledger records 40 successful
compile/run results.

Fresh QEMU TCG runs passed on AArch64 (10.8 seconds) and x86_64 (8.5
seconds), using retained committed kernels. Each ran the trust assertions and
lifecycle probe and shut down inside the 300-second functional allowance. Each
five-artifact receipt pins the kernel, init, both programs and serial log;
generated C and build logs are also recorded. This checks package recovery,
not arbitrary device-power-loss behavior or broader application compatibility.

Lifetime review: the retirement check owns and retires its digest and decoded
index after the final read. It exposes only a bool; retained history and cached
bytes remain caller-owned. No persistent validation cache or public schema
change is introduced.

Evidence:

- [baseline control](results/2026-10-14/publisher-recovery-before.txt)
- [lifecycle probe](results/2026-10-14/publisher-recovery-flow.txt)
- [trust assertions](results/2026-10-14/publisher-recovery-trust.txt)
- [host checks](results/2026-10-14/publisher-recovery-host.txt)
- [individual results](results/2026-10-14/publisher-recovery-host.json)
- [sanitizers](results/2026-10-14/publisher-recovery-asan.txt)
- [signed CLI](results/2026-10-14/publisher-recovery-cli.txt)
- [existing key admission](results/2026-10-14/publisher-recovery-admission.txt)
- [source/artifact ledger](results/2026-10-14/publisher-recovery-toolchain.json)
- [aarch64 receipt](results/2026-10-14/publisher-recovery-aarch64.json)
- [aarch64 report](results/2026-10-14/publisher-recovery-aarch64.txt)
- [aarch64 serial](results/2026-10-14/publisher-recovery-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/publisher-recovery-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/publisher-recovery-x86_64.json)
- [x86_64 report](results/2026-10-14/publisher-recovery-x86_64.txt)
- [x86_64 serial](results/2026-10-14/publisher-recovery-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/publisher-recovery-x86_64.qmp.txt)
