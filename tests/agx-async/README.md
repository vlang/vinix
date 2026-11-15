Compile `run.v` with V to an external executable and run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`. Set `AGX_ASYNC_TEST_BINARY` to retain the
ASan/UBSan executable outside Git.

The fixture executes production submission ioctl, immutable command/sync
staging, payload validation, sync objects, completion finish/discard, pending
poller, manager-locked registration and queue dispatch guard. GPU allocation,
publication, completion and shutdown are injected services. It executes no GPU.

The production worker now hands a batch to the manager and clears transferred
pointers using its ownership mask, including immediate metadata retirement.
The native publisher prepares every participating pipe before exposing any
write pointer and returns either no ownership or the complete batch. This
fixture deliberately injects partial transfers as an adversarial backend, so
the existing partial-publication/fault/stop checks continue to stress file-layer
ownership. They do not describe native publication granularity. Actual native
batch/ring/event/reaper behavior is exercised by `tests/agx-job-lifetime`.

Checks cover unsignaled/failed dependencies, independent queues, per-queue FIFO,
compute→render phases, client-signaled output fences, result-object references,
ring backpressure, setup/OOM/copy failures and a concurrent append during a
detached poll. Shutdown is injected between callback setup and registration,
and with compute submitted while render remains prepared. Immediate GPU
retirement frees metadata before the publication method returns; 200 cycles
must leave no pending-node allocation, job record or file/VM pin behind.

Node allocations and callback counts are measured independently of the
sync-object implementation's existing retained fence/object allocations.
These checks validate ownership and host scheduling; native execution and
the modern flat-command ABI remain separate acceptance work.

Native batches accept up to 64 mixed commands. The batch checks exercise all
compute/render orderings, aggregate fence publication, per-command result
references, prior-subqueue barrier indices, both storage allocation failures,
and preparation/callback/shutdown injection at every command position. Reverse
unwind must drop the newest event reservation first. The fake backend's existing
two-command contract is tested independently. Large payload staging uses owned
heap storage and is released before worker execution; its allocation is included
in the allocator accounting above.

Fence observers assert that all callbacks and result references are retired
before notification, including reverse error cancellation. A failed output
installation exposes a binary-sync prefix, then verifies its error notification
runs after node cleanup and after dropping the file lock.

Commands within one native batch can publish together. Explicit
dependencies wait for producer publication at their subqueue-local positions, and
backpressure holds only later commands on the same pipe. Overlap fixtures cover
both completion orders, older barrier targets, blocked heads, independent ring
backpressure, quarantine at publication, a fault with another job still running,
four 64-command reverse-callback batches, shutdown and immediate callbacks.
Later batches preserve publication FIFO; explicit index-zero dependencies use
captured prior-subqueue events in firmware prefixes. Nonzero in-batch
dependencies also configure firmware prefixes before callback registration.
Every setup-failure and stop position is injected independently. Firmware prefixes
wait for execution; the poller does not wait for producer CPU callbacks.

The injected firmware model separates execution from CPU retirement. Four complete
64-command dependency chains must publish before any callback. Out-of-order execution
attempts are blocked; execution then progresses with all callbacks withheld, and
reverse callback delivery must retain the aggregate fence and result references.
Render dependencies wait for fragment rather than vertex completion and can target
an older command. Faulted producers leave published consumers manager-owned until
their injected firmware completion or shutdown. The model checks host scheduling
against an assumed firmware protocol; it does not prove hardware recovery behavior.

Shutdown is injected before and after every command publication in four 64-command
orderings (512 cases), and immediately before the final callback-count load under
four backpressure limits (16 cases). The latter closes the window between checking
manager state and acquiring zero callbacks. Both paths must release caller-owned
prepared metadata before retiring the node or notifying its aggregate fence.

Independent later batches on the same queue now pipeline after older publication.
The new checks run/retire either pipe's later batch first and verify each node's
VM pin, result references and aggregate fence remain independent. They cover two
overlapping batches totaling 127 jobs, partial publication, a concurrent append,
forged user fences, fault/stop, both index-zero bits, and a saturated 128-queue
lookup with overflow deferral and resumption. External input sync dependencies
and unpublished predecessors retain FIFO order. Firmware scheduling remains injected.

Initial-event checks cover idle source subqueues, a dependency on only a later
command in a batch, immutable targets despite newer accepted work, consumers
executing and retiring before producer callbacks, errored input dependencies,
rejected ioctls preserving accepted markers, and capture cleanup on every setup
failure/stop path. Actual event/pin/byte compaction behavior is covered by the
event and lifetime fixtures; this fixture injects firmware execution.

Signaled input fences release scheduling waits even when they carry an error,
matching the packaged DRM scheduler. Eight real-ioctl scenarios permute two
input fences and their signaling order, preserve the original fence snapshot
after userspace replaces a syncobj, and retain the submission's own GPU error
independently of input errno. An errored input never releases another unsignaled
input or a firmware initial-event dependency. Existing producer-fault and stop
cases continue to cancel caller-owned jobs and retain hardware-owned backing.

The queue's own native completion fences are elided as in its per-queue DRM
scheduler entity. Immutable private scalar provenance prevents a generic fence,
another queue, or a recreated queue with the same public handle from eliding
the wait. Tests retain publication FIFO and explicit firmware waits, reverse
retirement and independent errors, and shutdown ownership. The production
context allocator is checked at its final two identities and must remain
exhausted rather than wrap or reuse an identity. No fence retains a queue pointer.

Whole-batch capacity is checked before the first publication and cached as one
scalar across retries. Real-ioctl checks hold 64 new same-pipe commands behind
63 older publications until host retirement, while another queue progresses.
Mixed batches wait intact when any pipe lacks event/ring capacity; publication
backpressure after admission still exercises partial progress without revisiting
transferred pointers. Shutdown during the readiness call must release all
caller-owned metadata in that final poll. Capacity is injected here; the lifetime
fixture exercises the actual native counting, tickets, TVB binding and prefixes.
