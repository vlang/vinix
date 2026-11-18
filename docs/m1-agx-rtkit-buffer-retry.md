# G13 RTKit shared-buffer retries

Syslog, IOReport and OSLog now resend the original buffer reply when
firmware repeats the size with either zero or the published IOVA. A changed
size or address gets no reply and the live allocation stays in place. A
mailbox timeout after allocation leaves the same buffer available for a
retry. [Asahi shared-buffer handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L337-L419)

Vinix compares IOVAs in the endpoint's wire format. Syslog and IOReport
encode 44 address bits and a size in 4 KiB units. OSLog encodes a 36-bit
page number and a byte count. The driver retains the full sign-extended
UAT address and holds the manager lock through reply publication.

Vinix still reports invalid first requests and allocator failure to the
caller. This preserves DCP's session failure path if shared-buffer setup
fails. A type 1 message on the crash endpoint still reports a crash once
its buffer exists.

ARM64 and x86-64 kernels built from
`0894aec7a78ddedcd3fe81d4697819eaf50d9d5f` plus the archived patch.
All 82 contract test files, five pinned source gates and independent
lifetime review passed. The sanitizer fixture passed 12 retry sequences
across both G13 ABIs and reran the 22 crash paths and four unknown-message
cases. Three negative controls detected comparison against the
sign-extended address, a fatal reply timeout and a fatal conflict.
Generated ARM64 C confirmed one allocation callback on the first-request
path and no implicit allocation on retries. The allocation scan reproduced
the 178 baseline discrepancies.

At this revision the full audit reported `not_equivalent`, with open
differences in initial failure handling, inherited sessions and DMA setup.
No hardware tests or reboots occurred.
[DMA setup and Syslog follow-up](m1-agx-rtkit-syslog.md)

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-buffer-retry-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `b43762b5352f99615ebbcbe9cc06f04a1fc00b8943bd7cfe53e8c41e19a53d29` |
| `bundle.tar.gz.inventory.txt` | `fd58dc98cadd7015a2fae9268d228791152f827f96d3b2de165db54a8c28014a` |
