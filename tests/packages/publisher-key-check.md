# Publisher public-key admission

Publisher trust now requires a canonical, non-identity Ed25519 point in the
prime-order subgroup. Previously, the identity encoding (`01` followed by 31
zero bytes) passed the configuration's hex check, and one fabricated signature
authenticated different index sequences without a private key. The retained
baseline control reproduces that behavior against the prior committed module.

The signing dependency exposes a separate publisher-key check. It decodes and
re-encodes the point, excludes the identity, and checks `[L]A = 0` by computing
`[(L - 1)]A + A` with its existing scalar multiplication and point addition.
The group-order constant comes from [RFC 8032](https://www.rfc-editor.org/rfc/rfc8032.html#section-5.1).
This approach is also described by [libsodium's point-validation documentation](https://doc.libsodium.org/advanced/point-arithmetic#point-validation).
The variable-base multiplication table is explicitly owned and freed after its
last read. Signature generation and the upstream verification rules are unchanged.
The [generator](../../tools/packages/vendor-signing.v) and
[provenance](../../tools/packages/signing/provenance.json) record this adaptation.

The package service checks keys before enrollment fetches, on every index
verification, before application/dependency launch planning, and before rollback.
Launch/rollback check each distinct key once per closure. Existing configuration,
state and history readers retain syntax-only admission so an old unusable key
does not prevent reviewed revocation or uninstall. Failed key replacement keeps
the prior configuration, replay floors and active generation. History is never
reset. Ordinary generated publisher keys and existing signed bytes stay valid.

The [functional probe](publisher-key-check.v) covers two forged indexes, refused
first enrollment and replacement, valid reviewed enrollment/install/upgrade,
legacy cached metadata refusal, application/runtime closure refusal, rollback,
reviewed revocation and uninstall with retained history and personal data. It
uses public RFC fixture credentials, which are never release credentials.
The [allocation probe](publisher-key-memory.v) checks 15 independent encodings
240 times with zero retained V allocations, including RFC keys and the
[libsodium point fixtures](https://github.com/jedisct1/libsodium/blob/fbd637d8db5689e7a98a6a6a2e43b35a61e2025c/test/default/core_ed25519.c)
for mixed-order, invalid, boundary and noncanonical points.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/publisher-keys \
  tests/packages/publisher-key-check.v
/tmp/publisher-keys /tmp/new-publisher-key-check
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.' -o /tmp/publisher-key-memory \
  tests/packages/publisher-key-memory.v
/tmp/publisher-key-memory
```

The distribution driver runs both probes. The renewed target suite stages the
functional probe alongside the reference vectors, batched publisher assertions
and 32-publication process. Current receipts contain seven artifacts/logs;
historical six-artifact receipts describe their earlier three-program suite.
Publisher enrollment through an authenticated channel, catalog migration,
graphical session integration and broader runtime/device qualification remain
separate roadmap 14 release gates.

## Recorded results, 2026-10-14

The baseline module tree was captured from `a14d497cb`. The same fabricated
signature authenticated both identity-key indexes there. The fixed functional
probe refuses both and exercises real signed package installation/upgrade,
rejected enrollment/replacement, cached refresh/upgrade refusal, app/dependency
launch refusal, rollback refusal and reviewed legacy revocation/uninstall.
Configuration, existing replay history and personal data remain intact.

All 15 key encodings met their independent expected result in 240 validations
with zero retained bytes. Earlier signing-buffer, table and total-allocation
guards still pass. Twenty-three host regression runners passed: signing, policy,
deployment, publisher workspace, release, index schema, catalog, composition,
administration, service, distribution, history schema, command, context, native profile, document, window, download recovery,
state, review, state schema, snapshot schema and registration.
Signing, policy, deployment, publisher workspace and both new probes also
passed clang ASan/UBSan (leak detection disabled, undefined behavior fatal).
The signed CLI lifecycle, 32-publication process, source mutation/refusal checks
and vendor regeneration passed. The distribution driver compiled. The ledger
records 79 successful compile/run results.

Fresh QEMU TCG runs passed on AArch64 (18.4 seconds) and x86_64
(29.4 seconds), using the retained committed kernels. Both ran all
four programs and shut down inside the 300-second functional allowance. Each
seven-artifact receipt pins the kernel, init, four probes/runners and serial log;
complete generated C and build logs are also hash-pinned. The zero-retention
measurement is a host check; target runs exercise functional admission/recovery.

Lifetime review: key admission owns its canonical encoding, identity/order
bytes, scalar box, variable-base table/digits and result encoding. Each is freed
after its final read. Returned bools and curve field values borrow no retired
array or table storage. Distinct-key maps borrow their caller's installed
provenance strings and are freed within the check. No key-validation cache or
shared retirement is introduced.

Evidence:

- [baseline forgery control](results/2026-10-14/publisher-keys-before.txt)
- [functional admission/recovery](results/2026-10-14/publisher-keys-flow.txt)
- [key allocations](results/2026-10-14/publisher-keys-memory.txt)
- [signing buffers](results/2026-10-14/publisher-keys-buffers.txt)
- [total allocations](results/2026-10-14/publisher-keys-allocation-total.txt)
- [table allocations](results/2026-10-14/publisher-keys-tables.txt)
- [host checks](results/2026-10-14/publisher-keys-host.txt)
- [individual results](results/2026-10-14/publisher-keys-host.json)
- [signed CLI](results/2026-10-14/publisher-keys-cli.txt)
- [sanitizers](results/2026-10-14/publisher-keys-asan.txt)
- [source checks](results/2026-10-14/publisher-keys-source.txt)
- [repeated publication](results/2026-10-14/publisher-keys-host-repeat.txt)
- [compiler/source/artifact ledger](results/2026-10-14/publisher-keys-toolchain.json)
- [aarch64 receipt](results/2026-10-14/publisher-keys-aarch64.json)
- [aarch64 report](results/2026-10-14/publisher-keys-aarch64.txt)
- [aarch64 serial](results/2026-10-14/publisher-keys-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/publisher-keys-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/publisher-keys-x86_64.json)
- [x86_64 report](results/2026-10-14/publisher-keys-x86_64.txt)
- [x86_64 serial](results/2026-10-14/publisher-keys-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/publisher-keys-x86_64.qmp.txt)
