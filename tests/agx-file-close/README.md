Build `run.v` with V to an external executable, then run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`. Set `AGX_CLOSE_TEST_BINARY` to retain the
sanitizer executable outside Git.

The fixture executes production handle release, file close, and deferred
retirement code. Queue invalidation, VM teardown, logical queues and GEM
objects are injected services. It checks that live jobs and failed queue
release preserve every VM/mapping, that partial success is retryable, and
that the final retry tears down objects exactly once. The intrusive pending
list uses fields in the retained file and allocates no retirement metadata.
Multi-file passes verify bounded retry and link updates. A deterministic shutdown
between failed close and registration executes the production manager-locked
registration method and proves synchronous cleanup after the worker exits.
The failure fixture separately executes the worker callback dispatcher with
a lock-taking callback to enforce its outside-manager-lock contract.
