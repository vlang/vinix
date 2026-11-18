# Interruptible G13 UAT slot admission

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` acquires
a VM slot before building jobs. When all slots are held, submission
waits interruptibly and reports `ERESTARTSYS` on interruption.
[Asahi submit](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L718-L737)
· [Asahi slot allocator](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/slotalloc.rs#L245-L285)

Both Vinix submit ABIs now wait when all eligible slots are occupied.
The file lock is released during the wait, so job cleanup can release a
slot. A generation check catches releases before listener registration.
A 10 ms timer covers changes the ASC can make without notifying the
host. An unmasked signal, group stop or thread exit unwinds through the
native syscall restart path. Each wake rechecks closed mappings and
device status. The captured queue retains its VM, and a legacy result
buffer stays pinned through job setup even if its handle is closed.
The temporary submission lease ends on ioctl return. Prepared jobs
retain their own leases through physical cleanup.

Asahi holds a sleepable per-queue mutex through the wait and notifies
one waiter when a slot becomes free. Vinix broadcasts releases, and a
concurrent submitter on the same queue can acquire the slot before a
woken submitter. The pinned audit still reports `not_equivalent`.
The physical firmware and scheduler behavior remains unverified.
[Asahi queue lock](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1445-L1458)
· [Asahi wakeup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/slotalloc.rs#L316-L340)

ARM64 and x86-64 builds, 82 V test files, eight host suites and five
pinned source gates passed for Vinix `c4ead3de2` plus the archived
patch. Nineteen admission cases exercised release, timer retry,
interruption, stop, mapping retry and legacy result-handle reuse.
Three negative controls failed at their intended assertions.
Independent lifetime review and generated ARM64 C confirmed wait and
cleanup ordering. The allocation scan reproduced the 178 existing
allowance discrepancies. No hardware tests or reboots occurred.

The tested patch, pinned sources, generated C and logs are retained under
`/Users/alex/.local/state/vinix/omarchy-m1-slot-wait-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `e5796b0543a608b829ae56ba706cf2ee10d8793203f6737f877080359ecb6fcb` |
| `bundle.tar.gz.inventory.txt` | `a132983c12da49712a47cb8b30ccaa4b8bb96bbeaa40da0a51b0557edfa04a0b` |
