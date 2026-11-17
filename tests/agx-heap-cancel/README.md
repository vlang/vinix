# Cancellation of unpublished GPU reservations

`v run tests/agx-heap-cancel/run.v` runs production heap and buffer allocation
code against an independent chronological interval/FIFO model and real UAT page
tables. ASan/UBSan uses `-gc none -manualfree` with fake-stack detection supplied
through `ASAN_OPTIONS=detect_stack_use_after_return=1`.

The 9,216 model cases cover three heap policies and offsets, aligned padding,
both cancellation orders, all four-record release/cancel masks, ignored pending
owners, repeated/unknown cancellation and subsequent reuse. Existing interval
enumeration and chronological-hole helpers check placement, bounded hole ranks,
FIFO ranks, pending bytes and live record addresses independently of production.

The 128 page-table cases prime the first leaf table, then inject failure at the
next 32 MiB boundary. A failure observer verifies two installed leaves before
the third fails. The real map must unwind them and invalidate the TLB before
returning. Physical-free observation requires canceled metadata already poisoned
and the unrelated pending record still live. A live mapping and upper VA pin
survive; subsequent mapping reuses precisely the canceled hole. Both global and
ASID invalidation modes and generic/explicit-GC heaps run across 32 boundaries.
The buffer helper's external page-size binding is renamed in the host fixture
to avoid a V cross-module name collision; its control flow is copied unchanged.

`--case model|rollback` selects a sanitized suite. `--case measure` builds a
separate unsanitized Darwin malloc-statistics probe with the nano zone disabled.
After warmup, three 10,000-operation cancellation rounds must retain zero blocks
and bytes while keeping a pending owner and live pin. This is a host retention
measurement, not a native kernel slab-rate claim.

`AGX_CANCEL_C` and `AGX_CANCEL_BINARY` retain external artifacts. Override inputs
with `--manager-source FILE` and `--allocator-source FILE`. Fixtures are removed
before successful or failed exits. `counterexamples.v RUNNER BASELINE_DIR
FRESH_OUTPUT` compiles eight negative cases. The original manager rollback uses
the current allocator's unchanged release/GC bodies; its new cancellation method
is available for fixture setup but is not called by that rollback. Compilation
failures never count as detected counterexamples.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` verifies one allocation-free
unlink/free, no iterator access after free, deferred unlock, the exact caller
substitution and 24 unchanged heap/backing/barrier/page-table bodies. It resolves
interned strings and consistently renames numbered return/array temporaries.
`--selftest` rejects five mutations. Source guards retain release-only lifetime
checks and reject the old full-GC rollback. Historical inventory, allocation and
x86 whole-C checkers remain unchanged; compiler drift uses a fresh baseline.

Prepare with `tests/agx-heap-pressure/qualify.v STATE` and its checksum-verified
two-job native runner. `evidence.v --seal STATE` validates all results and the
complete bundle's typed inventory and full archive restoration. After the report
records hashes and the feature is committed, `--bind STATE COMMIT` checks exact
paths/bytes. `--cleanup STATE` removes only its two worktrees and verified restore.
See [the report](../../docs/m1-agx-heap-cancel.md) for scope and remaining gaps.
