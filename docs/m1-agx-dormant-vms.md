# G13 VM admission and slot assignment

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` reserves a
nonzero file-local VM name during creation and acquires a hardware binding
for a submission. [Asahi VM names](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L575-L585)
· [Asahi submission binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L718-L719)

Vinix G13 now chooses the lowest available public VM name in a growable
per-file table. The first job preparation assigns a free ASID and publishes
the root. Pending submissions count their in-flight pins on the retained
VM record. Queues and mappings keep their internal key when a detached
VM's public name is reused. Slot removal and ASID invalidation complete
before reuse. G17 still binds during creation and rolls back a failed bind.

The sanitizer fixtures exercised 96 dormant VMs in one file, name 65
reuse, allocation failure during table growth, 400 submissions through
existing queues for a detached VM with internal ID 65, and exhaustion and
reuse of all 63 user ASIDs. The old allocator rejected a dormant VM with
all slots occupied.
The 18 ownership controls each failed at the expected assertion.
Independent review and generated C confirmed the pointer-array move and
callback and worker pin order.

Both kernel builds, 82 V contract test files, four sanitizer suites and
five pinned source gates passed for Vinix `0f2d622c7` plus the archived
patch. The allocation scan reproduced its prior allowance discrepancies.
The source audit reports `not_equivalent`. G13 holds a published slot
until VM destruction and returns ENOMEM on first submission when all
hardware slots are occupied. Asahi releases the lease at its last active
user. No hardware tests or reboots occurred. [Asahi binding lifetime](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1147-L1177)

The tested patch, references, generated C and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-dormant-vms-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `546f522042777e255be825d7c056c8c14eedf8e4d9e41995d14880cdd14cf514` |
| `bundle.tar.gz.inventory.txt` | `620db7fa9b4bae3094eab8edab37f522ff9cf15caa86e5a4f5b2f71a4ffbfd46` |
