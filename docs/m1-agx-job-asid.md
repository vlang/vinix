# G13 firmware slot routing

Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` reads
the ASID from the VM binding before constructing a submission. Its workqueue
records that slot with each submitted item. A hardware fault attributed to
another slot marks the item killed. [Asahi submission binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L718-L719)
· [Asahi fault classification](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs#L222-L229)

Vinix records the published ASID after root binding and uses it in render and
compute commands and microsequences for both G13 firmware layouts. Recovery
uses the recorded ASID. Per-VM mapping invalidations, tiled-buffer growth
and root teardown target the published slot. Dormant mappings still skip
firmware range invalidation.

The host fixtures used different software VM indices and ASIDs to exercise
fault attribution, file unbind, TVB growth and ownership, and clearing both
root words before ASID invalidation. Replaying the old recovery code failed
the render fault assertion. The AArch64 build uses the same slab classes
for the larger job records. The allocation scan reproduced all 178 existing
allowance findings.

Both kernel builds, 82 V contract test files, seven host suites and five
pinned source gates passed for Vinix `418ba5040` plus the archived patch.
The source audit still reports `not_equivalent`. Vinix reserves one of 63
hardware slots for each live VM, while Asahi releases its lease when the
last binding user retires. No hardware tests or reboots were performed.
[Asahi binding lifetime](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1147-L1177)

The tested patch, references, binaries and logs are under
`/Users/alex/.local/state/vinix/omarchy-m1-job-asid-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `b945b1be71313272b4d74211f53b40c21a4412a0788f90e1678aae75b521e259` |
| `bundle.tar.gz.inventory.txt` | `1223c9bc8a5ce18e3ef797932e530626476d41d556eb198f88e13f3a2201895b` |
