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

Production BIND, UNBIND, UNBIND_ALL, GEM-close cleanup, VM destruction and
mapping retirement now run in the same fixture, using the real BO handle
table and VM request validation. Two hundred cycles inject repeated flush
failures before releasing dynamically allocated GEM objects. Failed binds,
partial unbind-all, closed handles, busy VM pins, blocked replacement and close
retries retain backing until invalidation succeeds. Tombstones unmap only once.
The production file-flush wrapper holds the manager lock across transport use
and the stopped decision. Deterministic lock scheduling completes an in-progress
shutdown before retirement can free backing, and confirms a racing bind fails.
Another injection destroys a VM before BIND acquires the file mutation lock;
the ioctl must re-resolve it without touching the destroyed page table.
These injected services establish host ownership and lock order, not actual
firmware invalidation, concurrent hardware behavior or whole-kernel leak rates.

The real BIND ioctl also checks distinct RO, WO and RW permissions against the
injected page-table service. Empty and unknown flags must reject before mapping
or taking a mapping reference. The separate TLB fixture checks the actual UAT
leaf encodings and reprotection transitions with the production page-table code.
