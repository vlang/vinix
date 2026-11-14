Compile `run.v` with V to an external executable, then run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`.
Set `AGX_LIFETIME_TEST_BINARY` to retain the executable outside Git.

The V runner extracts the production job records, backing-release helpers,
public discard methods, completion callbacks, reapers and firmware-stopped
cleanup. It uses the real event manager. UAT invalidation, driver allocations,
ring retirement and shared-buffer backing are injected host services.

Scene tests execute the production TVB lease and GrowTVB owner selector.
They cover pool exhaustion, overlapping completion, final-owner release,
unchanged and displaced slot hints, oldest-free selection, canceled first bindings, and stale or
mismatched growth ownership. The firmware GrowTVB ACK transport itself is
covered separately by the failure fixture; these checks execute no GPU work.

Sanitizer checks cover caller-owned prepared jobs, cancellation failure and
retry, per-job retirement on a shared stamp, callback ownership and shutdown.
The event fixture separately covers publication order, cancellation rollback,
the 127-value window and physical-slot reuse. Neither fixture executes a GPU.

TPC tests use the production cache allocator/reference helpers and render-buffer
cleanup with kernel allocator semantics (`-gc none`). They cover 500 same-size
reuses, UAT page rounding, growth while older scenes retain backing, last-owner
invalidation, metadata/GPU allocation failure, failed invalidation and retry,
stopped firmware, and zero retained cache metadata after teardown. Queue cleanup
also runs the real public release method to verify quarantine permits teardown
retry without permitting new submissions.
