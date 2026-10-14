# Installed package trust and policy diagnostics

Software and organization-policy review share a dependency-aware diagnostic
graph. It checks enrollment, publisher-key admission and organization policy,
then propagates a blocked dependency's message to its dependent applications.
Messages identify the failing package and preserve the uninstall path for
unusable trust. Cycles terminate; unrelated applications keep their own status.

Software checks the active installed closure before the displayed candidate.
An available update that removes a blocked runtime cannot hide the current
launch blocker before activation. Expired or unusable cached metadata does not
prevent these read-only installed diagnostics. New catalog applications retain
direct candidate checks; dependency resolution still happens during review.
An empty message is not a payload-integrity scan or proof of runtime/device
compatibility. No protocol fields or authorization rules change.

Publisher-key validation is cached only for each diagnostic graph. Key decoding
uses one owned 32-byte buffer, preserving lowercase canonical admission while
avoiding temporary arrays retained by the pinned hex/bytes validation helpers.
Graph maps, cloned ID edges/queues and independently owned propagated messages
are retired after their last read. Software rows and policy-review rows retain
their own diagnostic text after the temporary graph is closed.

The [view assertions](../../tools/packages/pkgcore/view_test.v) cover revoked,
invalid and mixed-order keys, transitive/cyclic dependencies, independent apps,
runtime permissions, pending update/removal previews, activation and unavailable
catalogs. They also cover canonical key decoding and malformed encodings.
With `-d track_heap -gc none -manualfree`, 128 graph reads/cleanup cycles check
zero retained tracked bytes. This measures the diagnostic helper, not all
package-service allocations.

The [publisher-key lifecycle probe](publisher-key-check.v) checks real installed
state through Software and policy-review APIs, client decoding, implicit runtime
denial, reviewed revocation/uninstall and preserved state/history/personal data.
The [distribution driver](distribution-check.v) includes the allocation check;
the [guest suite](signing-repeat-runtime-check.v) requires both new lifecycle
markers on AArch64 and x86_64.

```sh
v -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/package-diagnostics \
  tools/packages/pkgcore/view_test.v
/tmp/package-diagnostics
```

Production publisher enrollment, catalog migration, graphical session
integration and broader runtime/device qualification remain roadmap 14 release
gates.

## Recorded results, 2026-10-14

Ten core assertion runners passed: view, policy, service, administration, review,
state, resolver search, signed index, trust history and cached snapshot schemas.
View/policy protocol readers and the signed CLI lifecycle also passed. View,
policy and the extended publisher-key lifecycle probe passed clang ASan/UBSan
(leak detection disabled; undefined behavior fatal). The allocation probe
passed all 128 graph reads with zero retained tracked bytes. The qualification
driver compiled. The host ledger records 36 successful compile/run results.

Fresh QEMU TCG runs passed on AArch64 (15.9 seconds) and x86_64 (21.8
seconds) using retained committed kernels. Each ran four programs, including
the extended Software/policy lifecycle probe, and shut down inside the
300-second functional allowance. Each receipt pins seven artifacts, with
generated C and build logs included in the source/artifact ledger. Guest runs
exercise service behavior; the zero-retention measurement is a host check.

Evidence:

- [host checks](results/2026-10-14/diagnostics-host.txt)
- [individual results](results/2026-10-14/diagnostics-host.json)
- [diagnostic allocations](results/2026-10-14/diagnostics-memory.txt)
- [lifecycle probe](results/2026-10-14/diagnostics-flow.txt)
- [sanitizers](results/2026-10-14/diagnostics-asan.txt)
- [signed CLI](results/2026-10-14/diagnostics-cli.txt)
- [source/artifact ledger](results/2026-10-14/diagnostics-toolchain.json)
- [aarch64 receipt](results/2026-10-14/diagnostics-aarch64.json)
- [aarch64 report](results/2026-10-14/diagnostics-aarch64.txt)
- [aarch64 serial](results/2026-10-14/diagnostics-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/diagnostics-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/diagnostics-x86_64.json)
- [x86_64 report](results/2026-10-14/diagnostics-x86_64.txt)
- [x86_64 serial](results/2026-10-14/diagnostics-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/diagnostics-x86_64.qmp.txt)
