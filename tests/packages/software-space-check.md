# Space-aware Software confirmation

Software previously displayed space counters while offering Confirm even when
the reported free space could not cover the operation and reserve. The proposal
now stays readable and cancellable, with exact additional bytes and filesystem
labels in status, plan/package diagnostics and offline export readers. Confirm
is hidden and direct confirmation events cannot start a worker or administrator
prompt. Free space, cancel the proposal and review again for a fresh estimate.

The shared [SDK helper](../../tools/packages/pkgprotocol/space.v) computes totals
and shortfalls without allocations or wrapped arithmetic. Ordinary zero-cost
reviews are no-ops and keep the service's reserve exemption. Mirror destination
budgets always check the reserve. A separate cache checks its reserve only when
acquisition needs bytes; a shared destination already includes acquisition and
is checked once. The service's `disk_check` uses the same arithmetic, retaining
its existing diagnostics and final check under the transaction lock.

These are reviewed observations, not a promise that space will remain available.
Freeing space requires a new review in Software; a later filesystem change can
still make the service refuse application safely. Estimates, fingerprints,
authorization, persistent package state and SDK-1 wire fields remain unchanged.

The [protocol tests](../../tools/packages/pkgprotocol/space_test.v) cover 125
counter combinations, exact/one-byte-short boundaries, overflow, no-op exemptions
and shared/separate warm/cold caches. Existing
[rollback tests](../../tools/packages/pkgcore/rollback_test.v) verify that actual
reserve refusal preserves activation, previous generations and interrupted work,
and that recovery/retry remains available.

The [UI fixture](software_space_fixture.v) covers all six maintenance operations,
overflow, exact shortfalls, full/compact inspection, cancel/review recovery,
separate destination/cache failures and blocked approval prompts. A measured
1,000-cycle review/load/render/blocked-confirm/cancel mode must retain zero
tracked bytes. An initial formatting expression retained an intermediate string;
the final formatter uses one complete concatenation and passes that measurement.

Run the [host driver](software-space-check.v) with a reviewed compiler and staged
headless ui2 module:

```sh
v -nocache -o /tmp/software-space tests/packages/software-space-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/software-space /build/new-software-space
```

It runs core/protocol checks, the complete Software functional fixture, selected
allocation modes and the signed CLI maintenance suite normally and under ASan/UBSan. The
[native controller](software-space-runtime-check.v) runs arithmetic and rollback
checks on both targets. Host UI-tree checks and native service/protocol checks
do not qualify graphical presentation or the remaining roadmap-14 release gates.

Recorded 2026-10-18 results:

- [All 25 host checks passed](results/2026-10-18/software-space-host.txt), with
  [commands, input hashes and artifact hashes](results/2026-10-18/software-space-host.json).
  Normal and sanitized runs passed the full Software functional fixture, focused
  space cases, catalog/details allocation modes and signed CLI maintenance.
- The focused [normal](results/2026-10-18/software-space-ui-space-memory.txt)
  and [sanitized](results/2026-10-18/software-space-ui-sanitize-space-memory.txt)
  1,000-cycle space modes retained zero tracked bytes. ASan used
  `detect_leaks=0`; allocation claims apply to the explicit tracked scopes.
- Native arithmetic and transaction checks passed on
  [AArch64 in 22.5 seconds](results/2026-10-18/software-space-aarch64.txt) and
  [x86_64 in 20.8 seconds](results/2026-10-18/software-space-x86_64.txt), with
  raw serial logs retained alongside the reports. These used freshly compiled
  fixtures and pinned prebuilt kernels.
- Complete desktop headless typechecks passed for
  [arm64](results/2026-10-18/software-space-desktop-arm64.txt) and
  [amd64](results/2026-10-18/software-space-desktop-amd64.txt), using the staged
  generated Calculator/translation sources. Graphical presentation remains a
  separate acceptance gate.

The compiler was frozen V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [retention helper](software-space-retain.v) verifies inputs and artifacts
before saving the evidence; its `--verify` mode checks the final
[hash ledger](results/2026-10-18/software-space-ledger.json).
