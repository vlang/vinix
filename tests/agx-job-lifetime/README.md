Run `V_C_ERROR_BUG_REPORT_DISABLED=1 v run tests/agx-job-lifetime/run.v`.
Set `AGX_LIFETIME_TEST_BINARY` to retain the executable outside Git.

The V runner extracts the production job records, backing-release helpers,
public discard methods, completion callbacks, reapers and firmware-stopped
cleanup. It uses the real event manager. UAT invalidation, driver allocations,
ring retirement and shared-buffer backing are injected host services.

Sanitizer checks cover caller-owned prepared jobs, cancellation failure and
retry, per-job retirement on a shared stamp, callback ownership and shutdown.
The event fixture separately covers publication order, cancellation rollback,
the 127-value window and physical-slot reuse. Neither fixture executes a GPU.
