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

## Debug severity

Asahi prints each subring at its own level: subring 0 with `dev_dbg`, then
`dev_info`, `dev_notice`, `dev_warn`, `dev_err` and `dev_crit`. A kernel
without dynamic debug drops `dev_dbg`, so firmware debug messages never reach
the log. It still warns about malformed records on any subring.
[Asahi log polling](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/channel.rs#L493-L542)
Vinix printed every subring with `kprintf`, which writes to the console
synchronously. Frequent firmware debug output would have slowed the event
worker that also handles job completion.

Vinix now consumes and validates subring 0 without printing valid messages.
Subrings 1 to 5 print as before, and malformed records are reported on every
subring. Linux's console level filtering of the other severities is not
reproduced.

`tests/agx-g13-failure` checks that a valid subring 0 message prints nothing,
that subrings 1 to 5 print, and that malformed records print on subring 0. A
`gpu.v` without the subring 0 check fails it. The sanitizer suite, 79
contract test files, all 122 pinned reference checks and the AArch64 `PROD`
build pass. No hardware test or reboot occurred.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-fwlog-debug-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `2647ba2996bceb336dab828c0acae8add7766cc582773161ef71508ac4d4e7c4` |
| `bundle.tar.gz` inventory | `df9b4f059f8f81654f016c48a39d50db7fb0d3f371634466cb6737a9b03e6a6e` |
