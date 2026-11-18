# G13 firmware receive order

Both G13 firmware ABIs handle `MSG_RX_DOORBELL` on `EP_FIRMWARE` in
mailbox order. The worker drains FWLog, KTrace, Stats and Event in the
same order as pinned Asahi before reading the next RTKit message. In
particular, the diagnostic ring entries are consumed before an event can
trigger recovery or teardown. [Asahi receive callback](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L472-L486)

The polling fallback uses the same ring order when the ASC has no valid
doorbell. A fatal event exits the mailbox drain and the worker proceeds
to stop firmware before releasing backing. Each ring read copies and
acknowledges its entry under the manager lock. Recovery still runs from
the private event copy. [Receive ring teardown](m1-agx-rx-lifetime.md)

ARM64 and x86-64 builds and 82 contract test files passed for
`c8026faae60253f172890a0488651b7587013685` plus the archived patch. The
sanitizer fixture passed ten transcripts covering both ABIs, valid and
invalid doorbells, fatal events, later mailbox traffic and fallback
polling. Five negative controls caught an ignored doorbell, reversed
ring order, the wrong endpoint, a read past failure and reversed
fallback order. Generated ARM64 C confirms the same protected reader and
stack copies. The allocation scan reproduced 178 baseline findings.

The pinned receive-order gate passed. The full audit remains
`not_equivalent`. Vinix uses the polling worker. Connecting the mailbox
interrupt to the AIC and validating timing on the M1 remain open. No
hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rx-doorbell-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `f9df758df8e0c1f16aa905110234e1118264b7675c2afd534c2fae2137ee5f9a` |
| `bundle.tar.gz.inventory.txt` | `e8a7d0441e959ce7e0e1fe1941e89464cf3f2790056834a4dee14725669c192e` |
