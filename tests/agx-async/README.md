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
the modern general-batch ABI remain separate acceptance work.
