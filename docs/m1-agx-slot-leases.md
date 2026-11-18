# G13 UAT slot leases

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` keeps a
binding active while submission users hold it and prefers a cached root
on reuse. The reference documents that the ASC flushes its translations
and cache on a context switch. [Asahi VM bindings](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1147-L1183)
· [Asahi handoff and cache ordering](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1490-L1535)

Each prepared Vinix G13 render and compute job holds its hardware slot
until backing cleanup, including quarantine and firmware-stop cleanup.
Vinix reuses a VM's cached root, takes an empty slot when available, and
otherwise replaces the oldest eligible idle root. The handoff lock
protects the firmware's current slot and outstanding flush records from
replacement. Both new root words are visible before ASID invalidation.

File mapping flushes resolve the VM's slot under the GPU manager lock.
A render queue emits a fresh TVB initialization after a root change even
when it retains the same TVB slot. G17 keeps its eager binding policy.

Both kernel builds, 82 V contract test files, eight host suites and five
pinned source gates passed for Vinix `55364dc30` plus the archived patch.
The host tests cover all 63 user slots, overlapping jobs, oldest idle reuse,
cleanup retries, a rebound TVB and eviction before a file flush. Four
negative controls failed at their intended assertions. Independent review
and generated C confirmed the locking and lease release order. The
allocation scan reproduced its prior allowance discrepancies.

When every candidate is held or excluded by the handoff checks, Vinix
returns `ENOMEM`. Asahi waits interruptibly for a slot. The pinned audit
reports `not_equivalent`. The firmware cache-switch behavior still needs
physical verification. No hardware tests or reboots occurred.
[Asahi slot wait](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/slotalloc.rs#L245-L285)

The tested patch, references, generated C and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-slot-leases-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `3228f306f753c10b41f96062f482534524b0cd64bc64778e31af609ac8c5e746` |
| `bundle.tar.gz.inventory.txt` | `8ae6b89907033bd34ffbd6fd869aa730e6f42a9f8e54fe4ea9cb21602b745176` |
