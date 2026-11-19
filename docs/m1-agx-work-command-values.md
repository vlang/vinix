# M1 AGX work-command values

This pass compares the values Vinix writes into G13 render and compute work
commands with Omarchy's pinned Asahi driver
([`queue/render.rs`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs),
[`queue/compute.rs`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs)
at Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`). It covers base M1
(t8103) at firmware 12.3 and 13.5, for commands that arrive through the
packaged UAPI used by Omarchy's Mesa. Four independent comparisons read Vinix
`fb6f5d771` field by field; layouts and offsets were already under test.

## Result

No firmware field value differs on that path. The comparisons confirmed:

- Compute: about 140 values. These include `RunCompute`, all three job
  parameter blocks, the encoder parameters, job metadata, `StartCompute`,
  `FinalizeCompute`, the timestamp ops, barriers and the work-queue message.
- Vertex: about 175 values. These include `RunVertex`, its job parameters
  and preemption buffers, `StartVertex`, `FinalizeVertex`, timestamps, the
  13.5 counters and notifier buffer, and `InitBuffer`'s fields.
- Fragment: about 250 values. These include `RunFragment`, all three job
  parameter blocks, attachments, `StartFragment`, `FinalizeFragment`,
  timestamps and the fragment barrier.
- Shared per-job values: about 100. These include the tiling parameters
  for edge sizes, layers and utile sizes, the buffer-manager limits and
  defaults, scene buffers, stamps and event sequences, barrier encoding and
  ring order, and every microsequence size, recomputed from the Rust
  structures.

## Differences in timing, not values

- **When `InitBuffer` is sent.** Asahi sends it when the TVB slot changed or
  this submission grew the buffer. Vinix sends it whenever the last bind is
  stale. That includes three more cases:
  - after a firmware GrowTVB request;
  - after the VM's page-table root was reinstalled, which
    [slot leases](m1-agx-slot-leases.md) added deliberately because the
    command names the VM slot;
  - after an earlier prepared job that grew the buffer was cancelled.

  The fields inside the command match. Asahi itself sends `InitBuffer` while
  other scenes are active, so the firmware accepts it in that state. A
  firmware trace after a GrowTVB or a root change would settle which rule the
  firmware needs.
- **When the TVB use count is incremented.** Asahi increments
  `Counter.count` in the submit ioctl and never rolls it back; its source
  carries `TODO: handle rollbacks, move to job submit?`. Vinix increments it
  when the job reaches the rings and rolls it back if publication fails. The
  counts agree once work is published.
- **The initial barrier after a cancellation.** Asahi waits on the queue's
  last committed value. Vinix waits on its last prepared ticket and falls back
  to the latest published one if that ticket was cancelled. In normal
  operation the value is the same.

## The legacy UAPI

Vinix also accepts the legacy submit ioctl used by Mesa 25.0.5, which Vinix
shipped before it built Omarchy's Mesa and still builds for the fake G17
renderer.
Asahi has no such path. There, several values come from userspace where the
packaged UAPI path writes Asahi's constants:

- command UUIDs and `encoder_id`;
- `no_preemption`, `no_clear_pipeline_textures` and `msaa_zs`;
- the fragment `isp_ctl`;
- the partial-render depth and stencil addresses.

Legacy jobs also flush stamps on every command and emit timestamp ops for
result buffers. Matched behaviour with Omarchy requires its Mesa and the
packaged UAPI path; see the userspace row in
[M1 AGX parity](m1-agx-parity.md#remaining-differences).

The unused `kernel/gpu/agx/queue` command stubs were removed. Nothing
imported them and the AArch64 build's generated C held none of their
symbols. Both kernel builds, 79 G13 contract test files and all 122 pinned
reference checks passed without them.

No hardware test or reboot occurred. Native M1 validation remains open.
