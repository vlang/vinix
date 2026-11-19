# G13 fault recovery without a halt

When the G13 firmware reports a fault or timeout, Vinix marks the pending
work failed, clears the pending-stamp records, waits up to 100 ms for the
firmware to halt, then clears `halted` and sets `resume`. This follows Asahi's
`mark_pending_events` and `recover`.

The two differed when the firmware did not halt within the 100 ms. Asahi logs
"Cannot recover" and keeps the device: the work is already marked failed, and
there is nothing to resume.
[Asahi recover](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1203-L1236)
Vinix returned failure, and the event worker then marked the whole GPU
failed. A fault the firmware handled without halting would have left the GPU
unusable until reboot, where Asahi would only fail the affected jobs.

Vinix now logs `agx: GPU firmware did not halt (count=N); cannot recover` and
keeps running. It still never sets `resume` without a halt. A halt that
arrives later, with no event queued to explain it, still fails the firmware
health check and stops the device, as before. Truncated Globals still fail
recovery.

## Validation

`tests/agx-g13-failure` checks, for both firmware ABIs, that a fault without a
halt marks and clears the pending work, sets neither flag and leaves the
device running. The previous `g13_recovery.v` fails that assertion. The
sanitizer suite, 79 G13 contract test files, all 122 pinned reference checks
and the AArch64 `PROD` kernel build pass. No hardware test or reboot occurred.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-recover-nohalt-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `931b767df05293a0be122c565d18dd1f27e3106d1b9757769e05843e17f9acb5` |
| `bundle.tar.gz` inventory | `47e29bb8e95ab65daea54c87298fafef0193d21a772a939e87f31d27362b8258` |

## Channel errors without a live queue

Asahi's `handle_channel_error` marks the slot's pending work failed, then
looks for the owning workqueue; when it finds none it logs "Workqueue not
found for this event slot!" and returns.
[Asahi channel errors](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1644-L1726)
Vinix marked the work only after finding the queue and stopped the device
when there was none, or when the firmware named an invalid pipe or slot. A
channel error for work that had already retired would have disabled the GPU.

Vinix now marks the slot first, logs a missing queue or an invalid pipe or
slot, and keeps running. Once a RecoverChannel command has been published, a
failure to see it consumed still stops the device: the command can
dereference the workqueue, which Vinix keeps alive until then. A second
channel error while one recovery is outstanding is also still fatal.

`tests/agx-g13-failure` covers both ABIs: an invalid pipe marks the slot and
publishes nothing, a retired job's queue is not used, and the event worker
completes normally after such an error. The previous `g13_recovery.v` fails
the invalid-pipe assertion. The sanitizer suite, 79 contract test files, all
122 pinned reference checks and the AArch64 `PROD` build pass.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-channel-noqueue-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `56c8cef1b9fd14287864c0946bf74ca623c1d13e345be62c83a6a6f6fec827e9` |
| `bundle.tar.gz` inventory | `43ff7c8a59583a2b48658c73b0718324308b3800a37a3053a7de2b19dd09ad33` |
