# Package model validation memory

Repeated admission of an already decoded manifest and configuration previously
retained scalar byte copies, split version/path components, duplicate maps and
temporary policy containers. The model validators now scan scalar bytes, keep
numeric version components on the stack, release local maps on every return,
and borrow a payload's parent prefix only during map membership checks.
Repository file URLs use the same relative-path rules without copying a suffix.
Accepted metadata, byte limits, version diagnostics and rejection order remain
compatible. Caller-owned metadata stays valid after validation.

The [fixture](../../tools/packages/pkgcore/validation_memory_test.v) checks:

- 64 manifest/configuration validations with zero retained scratch after each.
- Sixteen validations with growing payload/dependency/repository/policy maps,
  128 dependencies and a 1024-byte path containing 510 parent components.
- Late duplicate, invalid path, collision, missing executable, repository,
  policy and version-pin rejection with exact diagnostics and no retained
  scratch after the caller releases the returned error message and box.
- All 256 byte values in identifier, digest, printable and path predicates,
  length boundaries, Unicode paths, dot components and separators.
- Public version component values, caller-owned array retirement, maximum
  numeric components, leading zeros and diagnostic precedence on malformed input.

Heap tracking is enabled on the host with `-gc none -manualfree -d track_heap`.
The [target controller](validation-memory-runtime-check.v) runs the same
functional assertions without heap tracking, followed by the existing signed
[service maintenance probe](state-preflight-check.v). That probe rejects a
generation exceeding the persistent metadata limit before cleanup/acquisition,
preserves active state and recovery data, then installs a smaller requested set.
Host sanitizers check the newly released maps and borrowed path prefixes.

Zero retained model scratch does not mean zero transient allocations: maps and
the public version result still allocate, and returned errors remain owned by
the caller. Decoding, catalog loading and the complete service have separate
lifetimes. This qualification does not close broader catalog memory, publisher
enrollment, graphical session, foreign runtime or device power-cut acceptance.

## Recorded results, 2026-10-14

The paired host control retained 16,587 bytes / 152 allocations per manifest/
configuration validation before the change and zero bytes / zero allocations
afterwards. The final tracked fixture passed all 64 repeated calls, growing maps
and rejected inputs, including public version results retired by their caller.
The existing one-package catalog fixture retained 862 bytes / 11 allocations
per load after retiring its decoded result; remaining reader allocations are
outside this model cleanup.

Thirteen host runners passed: validation memory, catalog ownership, signed index
and snapshot schemas, trust recovery, administration, review, service,
distribution, configuration, policy, stored-state schema and collection limits.
The final validation fixture and signed maintenance probe passed clang ASan/
UBSan with leak detection disabled and undefined behavior fatal. Signed CLI
lifecycle and maintenance checks passed. All 41 compile/run results are retained.

Fresh QEMU TCG runs passed on AArch64 (24.9 seconds) and
x86_64 (122.4 seconds), each running the functional validation
assertions and signed maintenance probe before shutting down within 300 seconds.
These target runs do not enable heap tracking. Retained committed kernels
exclude concurrent kernel edits. Receipts bind kernel, init, both programs and
serial output; generated C/build logs are pinned in the ledger. Broader release
and whole-service memory gates remain open.

Evidence:

- [paired baseline](results/2026-10-14/validation-memory-baseline.txt)
- [host results](results/2026-10-14/validation-memory-host.json)
- [host checks](results/2026-10-14/validation-memory-host.txt)
- [validation and catalog memory assertions](results/2026-10-14/validation-memory-core.txt)
- [signed service probe](results/2026-10-14/validation-memory-probe.txt)
- [sanitizers](results/2026-10-14/validation-memory-asan.txt)
- [signed CLI checks](results/2026-10-14/validation-memory-cli.txt)
- [source/artifact ledger](results/2026-10-14/validation-memory-toolchain.json)
- [aarch64 receipt](results/2026-10-14/validation-memory-aarch64.json)
- [aarch64 report](results/2026-10-14/validation-memory-aarch64.txt)
- [aarch64 serial](results/2026-10-14/validation-memory-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-14/validation-memory-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-14/validation-memory-x86_64.json)
- [x86_64 report](results/2026-10-14/validation-memory-x86_64.txt)
- [x86_64 serial](results/2026-10-14/validation-memory-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-14/validation-memory-x86_64.qmp.txt)
