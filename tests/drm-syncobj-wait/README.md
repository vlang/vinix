# Binary syncobj wait snapshots

Compile `run.v` with V into an external executable, then run it. Set
`DRM_SYNCOBJ_WAIT_TEST_BINARY` to retain the ASan/UBSan executable outside Git.

The runner executes the production create/wait/reset/signal ioctl handlers, common
ioctl registration, syncobj module, pending-signal reader and request definitions.
It injects bounded user copies,
thread/process state, locks, atomics, monotonic time and scheduler steps.
Repeated scenarios check empty/signaled
creation, upfront validation, stable fence and handle snapshots, submission
capture, destroy/reuse, timeout/flag behavior and WAIT_ANY/ALL completion.
Registered empty waits preserve the first publication even across immediate
clearing/replacement before the next scheduler step. Private/shared signals
and thread exit interrupt pending waits; masked signals do not. Readiness and
timeout retain their precedence over interruption.
Fixture-only cleanup follows all synchronous callers and scripted actions.

Capture primitive checks cover multiple simultaneous registrations, intrusive
middle/head/tail removal, nil publication, duplicate registration, idempotent
cleanup and exact-lock publication/cancellation interleavings. The ioctl tests
check that no registrations survive validation failure, completion, timeout or
interruption, including publication after the ioctl has returned.

Large-wait cases cover the inline boundary at 64 handles, owned buffers for
65..4096 handles and a ready index of 4095. Geometry probes check aligned,
non-overlapping regions, wide counts and overflow. The allocator starts memory
with nonzero bytes, injects failures and tracks live buffers/bytes. Before each
free, a hook checks that no pending capture points into that allocation.
Every large request must return all owned bytes, including copy/lookup/prepare
errors, timeout and interruption. Huge requests use a fixture-only allocation
ceiling to test ENOMEM without exhausting the host.

Reset cases check the exact 16-byte request and ioctl encoding, zero-count/pad
rejection, one copied handle snapshot and complete lookup before effects.
Counts 1..4096 include duplicate handles, allocation/copy/namespace failures,
and handle destruction/reuse between lookup and replacement. Binary replacement
clears timeline lookup membership while previously captured fences remain valid.
Pending publication registrations survive a nil reset, capture the first later
fence and retain it across another reset. Every allocated reset owner is freed;
reset does not signal the old GPU fence or allocate wait capture nodes.

SIGNAL cases execute the production handler and private completion allocator.
They check fresh context/sequence-zero successes and timestamps for duplicate
handles, all identities before effects, sequential prefix preservation on OOM,
inline/owned failure cleanup and stable old GPU/timeline/first-publication
captures across replacement and handle reuse. The injected allocator counts
retained fence bytes separately from temporary request storage. Fixture-only
retirement frees those completions after all users and objects are gone;
production still retains published fence metadata. Ordinary first completion
timestamps survive later success/error attempts.

CREATE cases inject both object/stub allocation failures and nested creation at
allocation failure and immediately before namespace publication. Every failed request preserves its
output and existing object identities. Metadata-free hooks verify the namespace
lock is released and no published object/head points into the retiring region.
The allocator tracks object metadata, fence metadata and temporary request
storage separately. After all synchronous consumers finish, fixture cleanup
drops namespaces and frees metadata; production retains published metadata.

Namespace cases cross the former limits with 4,096 objects across four files
and 4,096 in one file. They check high-handle reuse with captured old identities,
capture survival across file close, first/middle/last handle reuse, neighboring
owner blocks, unsigned 64-bit owner keys and 5,000 operations against a bitmap
model. The checked handle-successor helper is tested at UINT32_MAX; a complete
32-bit namespace is not materialized. Published owner/handle keys are immutable:
any future key update must unlink and reinsert the object under the namespace
lock. The current index uses one global lock and linear traversal.

Allocator roles are injected at checked exact production allocation sites in
the copied host source. Object and fence sizes may coincide, so ownership is
tagged explicitly rather than inferred from size. Request allocation/free and
fault counters remain independent of retained object/fence metadata. The
native kernel source and retained generated kernel C use the real allocator.

Opaque descriptor cases execute the production export/import handlers and both
resource wrappers against a reference-counted descriptor fixture. Imports add
names for the same mutable object, across files and repeatedly within one file.
Shared SIGNAL/RESET, stable sync-file snapshots, pending first-publication
captures, source namespace close, alias destruction/reuse, duplicated transport
descriptors and last-descriptor close during lookup are checked. Both wrapper
allocations, both interface-box allocations, file construction, descriptor
installation and alias allocation have failure coverage with unchanged outputs
and exact owner counts. A 4,096-import case verifies complete link retirement.
Only detached imported links are reclaimed natively; objects/fences stay retained.
`DRM_SYNCOBJ_WAIT_TEST_C` optionally retains the host generated C externally.
The descriptor fixture checks ownership contracts; it does not replace native
file-layer concurrency testing. Its atomic decrement snapshots the value before
comparing because direct comparisons of generic mutable parameters can compare
the address in the host compiler.

Binary sync-file import checks follow descriptor-first Linux validation:
invalid or wrong-type descriptors return EINVAL even with a missing destination;
a valid sync-file with no destination returns ENOENT. Failures preserve request
fields, the old fence, timeline membership and captures. Successful imports
publish through aliases, preserve completed/error fence identity, leave old GPU
work untouched and discard previous timeline lookup membership. Scripted last-FD
close and destination destruction/reuse during descriptor lookup distinguish
the required order from an early destination snapshot. A 4,096-import loop
checks that binary imports create no handles or allocations. These are host
ownership/interleaving checks, with native object/fence retention unchanged.

Sync-file poll cases exercise the production readiness method and borrowed
fence-event subscriptions. Pending exports register lazily without allocation;
completion (including an error) makes them readable and advances their resource
event once. Repeated probes, distinct exports, duplicated descriptors, old
snapshots after replacement and source namespace teardown are covered. Exact
fence-lock interleavings let signal or final close win before the other, and
also close the last installed descriptor while a poll lookup keeps it alive.
Before export storage is freed, a hook rejects any node/event still linked from
a retained fence. A primitive case registers 4,096 nodes and checks duplicate
registration, cancellation/re-registration, link clearing and single wakeup.
The shared async event fixture models locked generation changes; these checks
do not run a native blocking poll/epoll syscall or scheduler thread.

These deterministic interleavings do not exercise actual kernel threads, GPU
execution or kernel heap usage. Vinix still polls through its scheduler; Linux
uses sleeping waits and fence callbacks. Timeline waits and deadline scheduling
hints remain separate work. These tests do not qualify multi-CPU races or
syscall restart after actual userspace signal delivery.

Sync-file `FILE_INFO` cases run the production wrapper and query helper with
the 56-byte header and 80-byte leaf record. They check allocation-free count
queries, large capacities, reserved fields, status and first timestamps,
private stub/queue provenance, signed sequence formatting and truncation.
Bounded output copies model null pointers, partial array/header faults,
overlapping ranges and input mutation between outputs. Completion and final
descriptor close between copies test coherent snapshots and wrapper ownership;
source replacement/removal leaves the exported leaf intact. All temporary
detail owners must be freed on success and every error. This covers current
single-leaf exports; merge and containers remain separate work.

Sync-file `SET_DEADLINE` cases execute the 16-byte write-only request against
generic, queue and private-stub leaves, both pending and complete. All deadline
bit patterns are accepted with zero padding; short or faulting copies precede
pad validation. Malformed command encodings and opaque descriptors remain
ENOTTY. The current leaves have no deadline callback, so hints allocate
nothing, write no user bytes and leave status, first timestamps, readiness and
event generations unchanged. Source teardown and final descriptor close during
lookup preserve the syscall reference. These checks do not qualify Linux's
scheduler wrapper metadata/forwarding, fence containers or GPU frequency policy.

Timeline boundary checks execute native Asahi sync-array staging and output
publication alongside direct point lookup. A `UINT64_MAX` output must satisfy
a lower input point when it is the nearest submitted successor. An independent
sorted oracle covers all subsets and insertion permutations of representative
unsigned boundary values. Exact matches still win; later closer publication,
reset and handle reuse leave an already staged fence intact. Lookups allocate
nothing and release the object lock. These cases qualify this selection rule,
not cumulative Linux fence chains, retired-point pruning or timeline wait UAPI.

Export reservation checks execute native reservation, descriptor-create and
pair-create functions against the fixture Process table. Reservations remain
invisible to lookup/close while excluding ordinary opens, specific duplicates
and pairs. The fixture models table growth and its failure; native kernel
budget/slab behavior is not executed. Stack descriptions in primitive checks
are borrowed test values, with table entries cleared before scope exit.
DRM cases use real wrapper/box/description fixture owners and check release
after failed adoption, full-table/OOM precedence, branch-specific missing-source
errors, stable outputs and recovery of the lowest slot. Three sync-file private
creation failure expectations now use Linux's EINVAL; opaque construction still
reports ENOMEM. Native source/C lifetime review covers stack nodes, process
fork/exit/exec and unlock-before-release; these fixtures do not qualify CPU races.
