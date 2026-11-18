# G13 RTKit initial buffer failure handling

Both G13 firmware ABIs keep the RTKit session running after a rejected
initial Crashlog, Syslog, IOReport or OSLog buffer request. Invalid requests
and allocator failures receive no reply or published buffer metadata. A
later valid request can allocate and negotiate normally during the boot
handshake or at runtime. DCP retains its strict initial setup error policy.
[Asahi shared-buffer handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L337-L419)

Once allocation succeeds, a reply timeout logs the failure and retains the
single buffer. Logging endpoints can repeat the request and receive the
original IOVA. On the negotiated crash endpoint, a later type 1 message
still reports a crash. The allocation callback unwinds backing and
unpublished reservations after setup failure. Shutdown stops the ASC
before freeing live buffers.
[Asahi crash receive](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L551-L614)

ARM64 and x86-64 builds, 82 contract test files, five pinned source gates
and independent lifetime review passed for
`0cd75e13be3259ef7ea8563e18735e4bae8ba410` plus the archived patch.
The sanitizer fixture passed eight boot and eight runtime sequences
using the production RTKit handshake and dispatch. Three negative
controls detected fatal invalid requests, fatal allocator refusals and
fatal crash-buffer reply timeouts. Generated ARM64 C confirms that the
policy is enabled only for G13 and adds no implicit allocation. The
allocation scan reproduced the 178 baseline discrepancies.

At this revision the full audit reported `not_equivalent`, with Syslog and
IOReport acknowledgement failure handling still open. No hardware tests or
reboots occurred. [Log acknowledgement follow-up](m1-agx-rtkit-log-ack.md)

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-first-buffer-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `6118567f9a0b033e086e3912da6ac82e15be3c82be6a31ef4894288304d25e9c` |
| `bundle.tar.gz.inventory.txt` | `a3e7ebf5a2aa587d701af77459b071bdab9828e03da4d5d4fc0b772e11833f9f` |
