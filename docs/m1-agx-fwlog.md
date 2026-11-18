# G13 firmware log channel

Omarchy's pinned Asahi uses six receive subrings with 256 descriptors each.
Each 56-byte descriptor identifies a 216-byte payload in a separate buffer.
The descriptor and payload addresses occupy separate RuntimePointers fields
at offsets `0xe0` and `0x1b0` on both G13 firmware layouts.
[Asahi descriptor and payload layouts](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/channels.rs#L303-L319)
· [Allocation and polling](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/channel.rs#L463-L542)
· [Runtime publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L629-L649)

Vinix now publishes both buffers and copies each bounded payload before
acknowledging its descriptor. The manager lock guards the copy against
teardown. The kernel logger prints the private copy after checking for a
terminator within its 200-byte message field. Vinix emits numbered levels.
Asahi applies Linux console severity filtering. Vinix frees the channel graph
and its backing on setup failure and shutdown.

ARM64 and x86-64 builds, 82 contract files, three sanitizer suites and five
pinned source gates passed for `ce8a3ba08ddbcf70668154248e394c5df1d327e8` plus
the archived patch. The focused fixture checked 24 payloads across wrap and
reuse, 74 injected allocation failures, and two complete releases.
The three negative controls detected an early acknowledgement, a retained
payload allocation and the old descriptor stride. Independent lifetime review
and generated C checks passed. Polling adds no heap allocations. The
allocation scan reported one fewer ARM64 site and 178 existing allowance
discrepancies.

The overall audit still reports `not_equivalent`. No M1 hardware tests or
reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-fwlog-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `0a42c3f476b76ebed6cd2bd0446ecbe68ec1a959742b4df7779b1d4d7b898f41` |
| `bundle.tar.gz.inventory.txt` | `1995eb3a5bb75e5d3a64e01cb0924f4cc9b1f41279ee6ff3a57e734dc6bbe4f0` |
