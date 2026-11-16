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

The fixture also runs production GEM-create, special-object binding and PRIME
export refusal. VM-private objects bind only into their original non-reused
reservation identity; a recreated context with the same numeric ID is refused.
Private import and kernel timestamp bindings are refused without retaining a
new reference, while owner CPU authorization and shareable objects still work.
Four hundred PRIME refusals check both custom and default export reference
release before the injected fd creator. GEM construction and VM creation are
injected here; `tests/gem-private` separately runs the real GEM constructors.
The production global identity allocator runs under its actual locking wrapper;
the pure VM fixture covers exhaustion without wrap or reuse.

Production queue creation runs with the real packed firmware priority builder.
Six hundred LOW/MEDIUM render/compute/mixed queues select bands 3/2, including
the compute override. HIGH, REALTIME and unknown values refuse before queue ID
or resource allocation. Host/GPU construction failures, retained quarantined
failure ownership, repeated close retries and VM destruction before the file
lock pass. Unpublished logical queue metadata is actually allocated and freed;
successful queue metadata is freed only by fixture cleanup after final close,
since the kernel's existing successful-queue metadata retention is unchanged.
GPU resources use a bounded injected pool; this establishes ioctl ownership,
not firmware execution or whole-kernel heap measurements.

Identity lookup cases run production VM destruction, queue creation and queue
destruction. Missing, removed and foreign-file names return ENOENT; malformed
requests retain EINVAL and known busy VMs retain EBUSY. Repeated failures leave
queue output IDs, allocation counters, live VM/queue identities and resource
counts unchanged. A successful queue/VM destruction followed by a repeated
request checks removed identities without double teardown. Fixture cleanup
frees successful logical queue metadata only after every consumer is gone.
