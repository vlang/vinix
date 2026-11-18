# G13 prior events at UAT admission

Omarchy's pinned Asahi driver snapshots the prior render and compute
events before it binds the VM. Explicit index-zero barriers then refer to
that snapshot. [Asahi event capture](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L706-L719)
· [Asahi barrier selection](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L859-L876)

Both G13 submit ABIs now capture the events their index-zero barriers
request before either VM admission wait. The ioctl owns the snapshot on
its stack. Each installed barrier takes its own physical stamp pin.
The ioctl releases the snapshot after barrier installation or when
submission unwinds. Publication still resolves completed and canceled
tickets against the captured target.

Asahi stores weak pointers in its snapshot. Vinix can retain up to two
counted stamp references during an admission wait. The host tests inject
slot pressure with a live predecessor to exercise this lifetime. A live
predecessor on the same VM normally retains its UAT lease.

ARM64 and x86-64 builds, 82 V contract files, eight host suites and five
pinned source gates passed for `ddf00fb18` plus the archived patch.
Eight injected cases covered both ABIs, with retirement, interruption,
shutdown and pending-storage failure. Two negative controls caught late
capture and missed release. Independent review verified exactly-once pin
release. Generated C storage checks passed on host and ARM64, and the
ARM64 pending record shrank by 80 bytes. The allocation scan reproduced
178 existing allowance discrepancies. The audit still reports
`not_equivalent`. No M1 hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-prior-event-admission-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `ede06faaf8a8b0af25b7b5183b6cc74b1f89e017424ca6817ced2e8d46f261d3` |
| `bundle.tar.gz.inventory.txt` | `2fccfec73cbe1f7d3b1e843f335ef0a5e911f8e6fe209fc0fd2d96f6be7eef6a` |
