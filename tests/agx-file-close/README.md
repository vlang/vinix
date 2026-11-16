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

Binding VM lookup cases cover BIND, UNBIND and UNBIND_ALL. Invalid operation
fields and global VA ranges return EINVAL before VM lookup; well-formed missing,
removed or foreign-file VM names return ENOENT. A found VM's private reservation
and page-table state are checked under the mutation lock. Failures preserve
live mappings, BO references, PTE and firmware-flush counts and neighboring VMs.
Additional BIND ordering cases check its alignment/flag header before BO lookup,
then BO identity/size, global range/permissions, VM identity and private window.
Missing BOs win over later validation failures; all acquired temporary refs are
returned on VM/private-state rejection. Existing mapping adoption and failed-flush
retention checks still run. Modern bind batching and ABI differences remain open.

SINGLE_PAGE cases repeat one BO page across a larger VA range with RO, WO and
RW permissions, including the last complete BO page. Two hundred cycles check
one retained BO reference per full mapping, full-range unbind, busy pins,
malformed requests, map allocation failure and failed-flush retirement/close.
The page-table service is injected here; `tests/agx-tlb` checks the actual
repeated PTEs and allocation rollback. The fake software GPU explicitly refuses
SINGLE_PAGE because its CPU resolver requires contiguous backing.

GEM-create size cases run the production ioctl and shared size validator.
Across 200 cycles, 16,200 requests check zero-size EINVAL, rounding-overflow
EOVERFLOW, maximum safe sizes, exact 16 KiB rounding, shared/private and writeback
flags, header/VM precedence and allocator ENOMEM. Invalid sizes never reach the
injected constructor or change output fields; valid sizes retain allocation
failure behavior. Successful fixture objects are removed and released exactly
once, returning the live count to zero. Huge successful objects have metadata
only in this fixture; they do not qualify physical-memory admission/accounting.

Range UNBIND runs 14,600 ioctl checks across 200 cycles. Already unmapped VA
ranges succeed; requests can cross holes and several BOs or preserve head,
tail and middle fragments. Contiguous and SINGLE_PAGE observations preserve
every leaf outside the cut, and another VM is unaffected. Fault injection
checks reservation OOM before any refs/PTE changes, three retained fragment
owners after failed flush, progress on other overlaps, full tombstone retry,
busy admission, replacement, UNBIND_ALL, GEM_CLOSE and failed close/retry.
The production array reservation runs against fallible host malloc; ASan shadow
checks that every successful raw reservation is freed after final close.
The TLB fixture independently checks exact production survivor PTE words.

BIND replacement runs 27,000 additional ioctl checks. Exact, partial and
multi-BO overlaps preserve outside leaves/permissions and other VMs while the
new mapping changes backing, permissions and SINGLE_PAGE mode. Same-BO retries
retain exact owner counts. Metadata/table-preparation OOM precedes mutation;
failed old invalidation prevents installation, and failed new invalidation
retains the new owner through retry/close. Fresh BIND also uses fallible array
reservation, with checked geometric growth and ASan-verified release. Busy VMs
refuse overlapping replacement while fresh mappings remain admissible.

GET_PARAMS runs 33,600 ioctl checks with the production handler and shared
checked-copy helper. Zero-length queries accept null or invalid pointers;
aligned and unaligned copies stop at the smaller of the input size and
supported response size. Partial faults preserve their written prefix, while
request fields and bytes outside that prefix stay unchanged. Invalid headers
precede manager lookup; a missing manager precedes formatting or copying.
The response formatter and user-copy service are injected, so these cases
qualify copy bounds/error behavior, not response contents, the modern ABI or
native page-fault handling. The fake backend shares the helper and is checked
by source gates/builds; this fixture does not execute a fake GPU guest.

Another 32,800 GET_PARAMS cases run the real manager state snapshot. Error and
stopped states return ENODEV before formatting/copying, including zero-length
queries and invalid pointers; malformed headers still return EINVAL first.
Idle, starting and running states retain ordinary copy behavior. Deterministic
callbacks switch to error before state-lock acquisition or complete an in-progress
shutdown holding that lock. All paths release it; formatting asserts it is free.
The snapshot does not serialize the subsequent user copy with later device loss.
These injected lock schedules do not qualify native multi-CPU crash publication.
