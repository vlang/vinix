# Generation metadata preflight

Install/remove/upgrade and deployment now encode the exact future generation's
persistent state before retiring interrupted stages or acquiring/staging payloads.
Changed reviews perform the same check under their reader lock. The existing
8 MiB state limit remains unchanged; apply writes the encoding it preflighted
and frees its owned scratch on both success and refusal. Generation numbers are
chosen from the actual retained directory names, so their decimal widths count.
No-op plans and rollback keep their existing behavior.

The prior implementation checked state size after downloading and copying every
payload, discarding interrupted work even when the eventual state could never
fit. A bounded signed cache can still resolve to oversized state: persistent
provenance and requested roots add bytes per package. The new diagnostic asks
for a smaller requested set or less package metadata.

The [signed probe](state-preflight-check.v) uses an explicit public fixture key,
32 small data payloads, valid launch arguments, a long repository identity and
calibrated descriptions. Its authenticated cache fits 8 MiB while the resolved installed
state exceeds it. Service and real CLI install/deployment reviews and apply
attempts must refuse without stage/download/copy/activation/completion progress,
cache objects/partials, generation creation, recovery deletion or changes to
active state, catalog or replay history. A smaller reviewed set must subsequently
install and verify. Service requests run in separate children; the bounded retry
replaces the setup process with `exec` so its large fixture heap does not remain
live during later requests. This test does not measure decoded-catalog lifetimes.

[Core assertions](../../tools/packages/pkgcore/generation_metadata_test.v) cover
one byte below, exactly at and one byte above the limit, persistent-reader
round-trips, an extra future counter digit, and early refusal for every operation
using the shared activation boundary. The tracked variant measures encoding
scratch over 64 accepted and eight oversized encodings. The first measurement
found retained buffers in the generic allocating encoder; production now uses
the existing append encoder with an explicitly owned, growing buffer.

```sh
v -nocache -no-skip-unused -gc none -manualfree \
  -path '@vlib|@vmodules|.|tools/accounts' \
  -o /tmp/state-preflight tests/packages/state-preflight-check.v
/tmp/state-preflight /tmp/new-preflight-work /path/to/vinix-package
```

The [target controller](state-preflight-runtime-check.v) runs the core and signed
service probes with retained committed kernels. These checks do not qualify
ordinary graphical sessions, release publisher/catalog enrollment, foreign
runtimes or power-cut durability. Storage can still change after a space check;
the metadata preflight only rejects a deterministically unrepresentable state.

## Recorded results, 2026-10-14

The retained previous implementation (`e500d4938`) accepted the oversized review,
retired interrupted work and downloaded/copied the closure before rejecting its
metadata. The final signed service and real CLI probes rejected install and
deployment reviews/applies before those effects, preserved the exact active state,
catalog, replay history and recovery marker, then installed a bounded subset.

Eight host runners passed: generation metadata, state, state schema, review,
deployment, payload repair, service and removal space. Exact-boundary encodings
round-tripped through the persistent reader. The first encoding implementation
retained scratch in generic json2.encode; the final owned append buffer retained
zero bytes over 64 accepted and eight oversized encodings. Core/public-probe
clang ASan/UBSan passed with leak detection disabled and undefined behavior fatal.
The signed CLI lifecycle passed; 29 host compile/run results are retained. This
does not measure whole-service or decoded-catalog heap lifetimes.

The initial 2048-package fixture exhausted the 1 GiB AArch64 guest during
setup; the initial x86_64 probe exited 139 at that stage. Those retained
failures led to a compact 32-package fixture with valid large arguments and
the same cache/state boundary. The compact variant passed on x86_64;
AArch64 passed its refusal checks but exhausted memory in the later bounded
retry while retaining setup allocations. The final fixture releases the setup
process with exec before that independent request. Broad catalog memory
behavior remains open. A later AArch64 firmware-variable copy failed before
boot while host disk space was low; disposable media were retired and only
that run repeated.

Fresh QEMU TCG runs passed on AArch64 (66.3 seconds) and
x86_64 (63.7 seconds). Each ran core and signed service
assertions and shut down within 300 seconds. Retained committed kernels exclude
concurrent kernel edits. Receipts pin kernel, init, both programs and serial;
generated C and build logs are pinned in the ledger. Graphical sessions and the
broader public catalog/runtime release gates remain separate.

Evidence:

- [previous-implementation control](results/2026-10-14/state-preflight-baseline.txt)
- [host results](results/2026-10-14/state-preflight-host.json)
- [host checks](results/2026-10-14/state-preflight-host.txt)
- [core assertions](results/2026-10-14/state-preflight-core.txt)
- [initial encoding and fixture attempts](results/2026-10-14/state-preflight-initial-attempts.txt)
- [public metadata preflight probe](results/2026-10-14/state-preflight-probe.txt)
- [sanitizers](results/2026-10-14/state-preflight-asan.txt)
- [signed CLI lifecycle](results/2026-10-14/state-preflight-cli.txt)
- [source/artifact ledger](results/2026-10-14/state-preflight-toolchain.json)
- [aarch64 receipt](results/2026-10-14/state-preflight-aarch64.json)
- [aarch64 report](results/2026-10-14/state-preflight-aarch64.txt)
- [aarch64 serial](results/2026-10-14/state-preflight-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/state-preflight-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/state-preflight-x86_64.json)
- [x86_64 report](results/2026-10-14/state-preflight-x86_64.txt)
- [x86_64 serial](results/2026-10-14/state-preflight-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/state-preflight-x86_64.qmp.txt)
