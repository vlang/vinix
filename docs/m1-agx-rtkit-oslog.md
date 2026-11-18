# G13 RTKit OSLog acknowledgements

Both G13 firmware ABIs now echo the original type 2 OSLog message after
buffer negotiation. Channel zero carries a wrapping 32-bit cumulative
counter. Zero and values beyond the buffer length still receive the exact
echo. Messages with any of bits 32 through 55 set receive no reply. Types 3 through
5 also receive no reply. An ACK send timeout is logged and the session can
process later messages. [Asahi OSLog handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L751-L799)

Pinned Asahi initializes base-M1 AGX with a fresh RTKit session. The t8103
GPU node omits the synchronous-logging property, so the normal OSLog ACK
policy applies. Vinix enables that policy in the G13 manager. Its runtime
lock covers the negotiated-buffer check and mailbox send, so queued
notifications get no reply after shutdown. Acknowledgement reads no log
backing and retains no counter state. [Asahi GPU RTKit construction](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L712-L717)
[Base-M1 device tree](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/arch/arm64/boot/dts/apple/t8103.dtsi#L492-L507)

ARM64 and x86-64 builds, 82 contract test files, five pinned source gates
and independent lifetime review passed for
`3197bc972e372a3723378584624c3334a6cb7abc` plus the archived patch.
The sanitizer fixture covered 78 OSLog notifications on both ABIs.
Four negative controls detected counter truncation, acceptance of a
reserved bit, an ACK before negotiation and fatal timeout handling.
Generated ARM64 C confirms G13 registration and allocation-free notification
handling. The allocation scan reproduced the 178 baseline discrepancies.

The source-retention filter now includes device-tree includes and assembly.
The restored audit retains the exact t8103 device tree and ARM64 memory
attribute assembly used by the checks.

At this revision the audit reported `not_equivalent`, with initial RTKit
failure handling still open and physical device behavior untested. No
hardware tests or reboots occurred.
[Initial buffer failure follow-up](m1-agx-rtkit-first-buffer.md)

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-oslog-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `f241971cc2cc1a227884de871aa338e08d8e8b968eb2c9b3ed5fbd4da62e550b` |
| `bundle.tar.gz.inventory.txt` | `ec08bf39a70a53974f6af653a47bfff6571849dce72eb4de79279455082787a7` |
