Compile `run.v` with V to an external executable and run it with
`V_C_ERROR_BUG_REPORT_DISABLED=1`. Set `AGX_ASYNC_TEST_BINARY` to retain the
ASan/UBSan executable outside Git.

The fixture executes production submission ioctl, immutable command/sync
staging, payload validation, sync objects, completion finish/discard, pending
poller, manager-locked registration and queue dispatch guard. GPU allocation,
publication, completion and shutdown are injected services. It executes no GPU.

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

Independent commands within one native batch can publish together. Explicit
barriers wait for internal callbacks at their subqueue-local positions, and
backpressure holds only later commands on the same pipe. Overlap fixtures cover
both completion orders, older barrier targets, blocked heads, independent ring
backpressure, quarantine at publication, a fault with another job still running,
four 64-command reverse-callback batches, shutdown and immediate callbacks.
Later batches on the same queue remain FIFO through retirement. Nonzero in-batch
dependencies also configure firmware prefixes before callback registration.
Every setup-failure and stop position is injected independently. The existing
CPU callback waits remain; firmware-driven scheduling and initial dependencies
across submissions remain separate work.
