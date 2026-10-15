# Bounded deployment document decoding

Deployment review, apply, direct deploy, audit and locked offline mirror export
now share the existing bounded metadata reader. It parses formats 1 and 2 once,
retains independently owned strings and retires partial fields on syntax, schema
and service validation failures. Root and pin arrays release growth buffers;
sorting reuses their storage. The core preserves its existing public lock types
and transfers parsed string ownership when converting wire pins. Version checks
use fixed-size scratch storage.

The retained pre-change executable measured **86,300 retained bytes over 100
format-1/2 decode/close cycles**. The corrected tracked runner retains **zero
bytes over 1,000 success/refusal cycles**, all truncated prefixes, four reads of
a 512-pin document and four reads of 4,096 roots. Inputs are prepared before
measurement and remain caller-owned. The tracker has 16,384 live records, fewer
than the strings legitimately owned by a complete 4,096-pin closure, so that
maximum closure is checked functionally outside the tracked interval. This is
decoder allocation qualification, not whole-service memory qualification.

Admission keeps the existing 8 MiB document and 4,096-root/pin limits, enforcing
them while parsing rather than after allocating unbounded decoded arrays.
Fields retain their established domain bounds: IDs/repository names 128 bytes,
versions 29, architectures 16, keys/digests 64. Tests cover maximum and one-over
collections, both target architectures and `all` pins, empty deployments,
reordered and escaped keys, duplicate/escaped duplicate and missing fields,
unknown fields, nested arrays, null/coerced values, full-width unsigned sequences,
overflow, noncanonical numbers/versions, invalid Unicode/UTF-8 and trailing data.
Format 1 forbids locked records; format 2 requires their explicit array.
Canonical writer bytes, package digests, signing and trust/policy checks remain
covered by the existing lifecycle assertions.

The public wire decoder checks structure and bounds, independently of package
trust. Core validation additionally checks identities, canonical versions,
digests, positive sequences, unique roots/pins and the configured architecture.
Planning still authenticates exact catalog manifests, publisher sequence floors,
dependency/runtime closure and current policy. A decoded document grants no
deployment authority.

The signed CLI fixture exercises seven malformed locks against review, apply,
direct deployment, audit and mirror review/apply. All 42 refusals preserve exact
configuration/catalog/history/state bytes, activation, object/generation names
and a recovery-stage sentinel, without creating the mirror's parent directory.
The full existing offline deployment, reviewed activation, rollback and publisher
revocation lifecycle also runs. Core assertions cover saved snapshots and audit
on both configured architectures.

Both fresh administrator guests require the new bounded-reader marker. Ordinary
administrator and standard users can review a valid empty format-1 deployment
and refuse malformed format-2 deployment/mirror reviews without changing the
installed set or configuration. The guest checks also decode an owned wire lock
and close it twice. Frozen kernels are used; no kernel source is rebuilt. This
does not qualify graphical login, broader application catalogs or foreign APIs.
Roadmap 14 remains open for those distribution acceptance tasks.

The initial expanded test fixture freed its root strings explicitly and then
called a typed array destructor that freed them again. ASan located that fixture
double-free; cleanup now frees only the array buffer after its strings. Initial
failure logs, generated C and source are retained separately. Final native and
ASan/UBSan runs pass; sanitizer leak detection is disabled and retained bytes
are measured with the explicit tracker.

Run the maintained allocation assertions with the reviewed V toolchain:

```sh
V_MACOS_V3_NO_FALLBACK=1 V_C_ERROR_BUG_REPORT_DISABLED=1 /path/to/v \
  -nocache -no-skip-unused -gc none -manualfree -d track_heap \
  -path '@vlib|@vmodules|.|tools/accounts' -o /tmp/deployment-memory \
  tools/packages/pkgcore/deployment_decode_test.v
/tmp/deployment-memory
```

## Recorded results, 2026-10-16

All **30 focused compile/run checks** passed: nine core and one protocol compile/run pairs, native allocation and ASan/UBSan pairs, four CLI/driver checks and two guest-tool builds.

Both fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **35.51 seconds**, x86_64 **40.905 seconds**. These are functional deadlines, not performance qualification.

- [baseline regression](results/2026-10-16/deployment-decoder-baseline.txt)
- [host results](results/2026-10-16/deployment-decoder-host.json)
- [host summary](results/2026-10-16/deployment-decoder-host.txt)
- [core assertions](results/2026-10-16/deployment-decoder-core.txt)
- [tracked allocations](results/2026-10-16/deployment-decoder-memory.txt)
- [sanitizers](results/2026-10-16/deployment-decoder-asan.txt)
- [signed CLI](results/2026-10-16/deployment-decoder-cli.txt)
- [initial attempts](results/2026-10-16/deployment-decoder-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/deployment-decoder-toolchain.json)
- [aarch64 receipt](results/2026-10-16/deployment-decoder-aarch64.json)
- [aarch64 report](results/2026-10-16/deployment-decoder-aarch64.txt)
- [aarch64 serial](results/2026-10-16/deployment-decoder-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/deployment-decoder-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/deployment-decoder-x86_64.json)
- [x86_64 report](results/2026-10-16/deployment-decoder-x86_64.txt)
- [x86_64 serial](results/2026-10-16/deployment-decoder-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/deployment-decoder-x86_64.qmp.txt)
