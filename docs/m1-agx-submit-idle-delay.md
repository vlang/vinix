# G13 submit idle delay

Omarchy's pinned Asahi modern SUBMIT refreshes the 32-bit firmware Globals
idle-off delay after validating the header and before looking up the queue.
The normal policy sets 2 ms. Asahi debug modes can select 0 ms or 5000 ms.
[Submit ordering](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1374-L1393)
· [Idle delay policy](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1490-L1501)

Vinix restores 2 ms at the same point on both G13 layouts, using offset
`0x11030` on 12.3 and `0x1119c` on 13.5. The first valid modern SUBMIT header
can replace the boot-time delay even if queue lookup fails. The manager lock
protects the backing from shutdown. Vinix uses a 32-bit release store and
skips the refresh if the GPU is stopped or failed, or if the firmware graph
or field backing is unavailable. The Asahi debug overrides remain open.

ARM64 and x86-64 builds, 82 V contract files, three host suites and five
pinned source gates passed for `f15fb602ba5fb1bd5b129e2fc9880b1718e75cef` plus
the archived patch. The sanitized fixtures verify the ioctl ordering and
compare every word of Globals in 21 cases. Omitting the refresh or writing
3 ms triggered the expected assertions. Independent lifetime review and
generated C checks passed. The refresh adds no heap allocations and the
allocation scan reproduced the same 178 baseline discrepancies.

The audit still reports `not_equivalent`. No M1 hardware tests or reboots
occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-submit-idle-delay-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `d92bf985726980dbde10c4d85483eceb8481ae1d2092809b47c719ce05f93c23` |
| `bundle.tar.gz.inventory.txt` | `f4410ae7a6df7302537a9c5fb4ff98193acabdb1c558f08d8bdc5d1da69f61ba` |
