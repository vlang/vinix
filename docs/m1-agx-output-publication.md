# G13 output fence publication

Omarchy's pinned Asahi driver commits and arms a submission, pushes it to
the scheduler, then replaces binary syncobj fences and adds timeline points.
It reserves the timeline nodes during input staging.
[Asahi submit order](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L975-L1008)
· [Asahi timeline reservations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L238-L250)

Both Vinix G13 submit ABIs allocate and number the finished fence once the
manager accepts the batch. The enqueue callback sets the fence before making
the pending node visible and returns the retained fence to the ioctl. The
ioctl publishes the staged outputs outside the manager lock. Completion or
shutdown can free the pending node before that publication. A rejection
preserves the existing output fences and consumes no queue sequence number.
Fence allocation now runs under the manager lock with the existing fatal
allocation policy. Published fence metadata reclamation remains open.

ARM64 and x86-64 builds, 82 V contract files, four host suites and five
pinned source gates passed for `66b494ca9` plus the archived patch.
Twelve ASan/UBSan ioctl cases covered both ABIs and binary and timeline
outputs across registration refusal, early completion and shutdown after
acceptance. Negative controls detected early output replacement and a read
through the freed node. Independent lifetime review and pending-storage
checks passed. The allocation scan reproduced 178 existing allowance
discrepancies. The broader generated C checker reported the same sync-file
info allocation failure on the baseline and the patch.

The source audit still reports `not_equivalent`. No M1 hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-output-publication-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `d166eed907e42505c6bfd4724cf385f549b7a36bf31a097cb69469007c9df9f9` |
| `bundle.tar.gz.inventory.txt` | `80c34d2eb7d563c96a30088fc27dcabb1e07fe239d07e9efb18ded20fc0f9b47` |
