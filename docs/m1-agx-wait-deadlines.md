# DRM fence deadline hints

Binary and timeline WAIT apply `WAIT_DEADLINE` once, after initial readiness
and future-point registration and before testing the wait timeout. The hint
uses the captured fences. A poll can still supply a hint, and a point first
submitted after that pass can still satisfy the wait. The sync-file deadline
ioctl supplies the same hint to the fence held by the descriptor.
[Packaged syncobj wait](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c#L1125-L1171)
· [Packaged fence scheduler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/scheduler/sched_fence.c#L152-L181)

G13 queue fences retain the earliest signed deadline, including zero and the
high-bit range. The shared queue forwards hints through immutable chain and
array members without recursion or scratch allocation. When another drainer
is active, it finishes forwarding the queued hint. Linux walks those children
synchronously. Independent lifetime review checked that both ioctls supply
retained fence metadata and that earlier hints and completion can share queue
membership.

The ASan/UBSan checks covered no-hint and ready paths, invalid and missing
points, poll timeouts, future submission, signed minima, descriptor close and
replacement, and 2,048 nested links containing a shared array. All 27,200
sync-file deadline checks passed. The previous dispatch failed the assertion
that the poll recorded a deadline. Both kernel builds, 82 contract tests,
five pinned protocol gates and the AGX async, file-close and DRM wire suites
passed.

Compiler allocation sites stayed at 377 for AArch64 and 289 for x86_64, with
the same 178 existing allowance findings. The AArch64 fence structure grows
from 272 to 288 bytes. Direct fences fit the 384-byte allocation class in both
revisions.

The host comparison uses Vinix `147b3d299` plus this patch and Omarchy's
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. Firmware deadline
consumption and CPU wait boosting remain open, along with legacy timeline
interoperability, capability reporting, fence reclamation, full scheduler
behavior and validation with the matched Mesa stack.

Sources, binaries, logs and a verified restoration are under
`/Users/alex/.local/state/vinix/omarchy-m1-wait-deadlines-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `4d8c37476e692337c69fcef0504a2f4508767d4037f735196c5728c73700ada1` |
| `bundle.tar.gz.inventory.txt` | `26c8e3744a39ce8e7edc9a637bc84a28b13cc609707a8adbbaf99499be067a7c` |
