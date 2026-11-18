# G13 firmware operation ownership

Omarchy's pinned Asahi driver holds one firmware operation per queue
submission. It acquires the guard before VM binding when input syncs
are present and when the scheduler runs the job otherwise. The guard
increments the firmware's pending counter and wakes the GPU. Dropping
the guard decrements the counter. [Asahi early acquire](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L700-L719)
· [Asahi dispatch acquire](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L375-L379)
· [Asahi counter acquire](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1276-L1291)
· [Asahi counter release](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1800-L1806)

Both Vinix G13 submit ABIs now count one operation for the entire batch.
The ioctl uses the original input sync count to start before VM admission
and transfers ownership when it registers the pending batch. An ioctl
failure before registration releases the operation. With zero input
syncs, the native publisher acquires the operation after ring preflight.
The worker keeps the operation through the final callbacks and releases
it after signaling the aggregate fence. Asahi releases its guard on
scheduler job drop. Vinix shutdown releases the counter with the
firmware graph under the manager lock.

ARM64 and x86-64 builds, 82 V contract files, eight host suites and five
pinned source gates passed for `f0c83532c` plus the archived patch.
Ten focused ioctl cases covered both ABIs across dependency and ring
waits, mixed-command retirement, wake failure, post-wait allocation
failure and shutdown. The native publisher and reapers passed 81 ring
transactions. Two negative controls caught late acquisition and a missed
release. Independent lifetime review and generated C storage checks
passed. The allocation scan reproduced 178 existing allowance
discrepancies with the same allocation site counts on both architectures.
The audit still reports `not_equivalent`. No M1 hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-operation-ownership-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `7ea59c09661f17f36bdaa8aa15f92407197ac2d2ef42e5b7b8a489abafb8021d` |
| `bundle.tar.gz.inventory.txt` | `bd640b453a5cf8a6e53c92e6ec2ba043374dbcd2ca109847bbbe4abac314702d` |
