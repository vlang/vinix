# G13 queue admission and slot wakeups

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` holds the
queue mutex while a submission waits for a UAT slot. Returning a slot
notifies one allocator waiter. [Asahi queue submit](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1445-L1458)
· [Asahi slot release](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/slotalloc.rs#L316-L340)

Both Vinix G13 submit ABIs acquire a queue-local gate before UAT admission.
The active submitter keeps the gate while it sleeps for a slot and drops it
under the file lock after registration or cancellation. Other queues and the
worker can continue because the wait releases the file lock. Last-user slot
release and G13 root removal now notify one waiting submitter. The existing
10 ms timer prompts rechecks after silent ASC transitions or when the selected
waiter cannot take the released slot.

Vinix gate waits can return the native syscall restart status on interruption.
The gate serializes active owners, and contenders can race to enter after
release. Asahi uses its ordinary queue mutex. Full source parity remains open
and the offline audit reports `not_equivalent`. Native M1 scheduling and
firmware behavior require physical validation.

Both kernel builds, 82 V contract test files, eight host suites and five
pinned source gates passed for `f90d1db1b` plus the archived patch. The
host cases cover both ioctl ABIs, interrupted contenders, and progress on
another queue during the wait. Two negative controls detected a bypassed
queue gate and a slot wake broadcast. The independent lifetime review and
generated ARM64 C verified gate release and timer cleanup. The allocation
scan reproduced 178 existing allowance discrepancies. No hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-queue-admission-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `ae33b9c1fe43f4d5cccf86dd376273e860682abfac064617118aa8025ed00ae7` |
| `bundle.tar.gz.inventory.txt` | `fc42ed12ba4df234bd239dbd8221c05cb368e32f8a4c674104f26e8311e60997` |
