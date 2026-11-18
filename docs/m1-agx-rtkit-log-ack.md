# G13 RTKit log acknowledgement timeouts

On both G13 ABIs, a mailbox timeout acknowledging a Syslog type 5 or
IOReport type `0x8` or `0xc` notification now leaves the RTKit boot handshake
or running receive loop active. Vinix makes one send attempt with the
original payload and logs a timeout. Syslog checks and reads the record
before acknowledgement. Missing or invalid records still get an
acknowledgement attempt. RTKit clients outside G13 keep their existing
send-error return.
[Asahi IOReport receive](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L618-L637)
[Asahi Syslog receive](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/soc/apple/rtkit.c#L669-L728)

ARM64 and x86-64 builds, 82 contract test files, and five pinned source
gates passed for `a8c40447eb3a249a97ddd0b6b6cd4721e5d2f457` plus the
archived patch. The sanitizer fixture passed 12 boot and runtime sequences
across both ABIs, two timeouts after valid Syslog copies, and three strict
client checks. Four negative controls detected a boot abort, an immediate
retry, a truncated IOReport reply, and a lost strict-client error. The
compiled ARM64 C shows one send and no implicit allocation in the
acknowledgement helper. The allocation scan reproduced the 178 baseline
discrepancies.

The full source audit remains `not_equivalent`. Vinix still uses bounded
mailbox polling for the send. The fixture verifies error propagation and
continued receipt with injected messages. Physical firmware behavior
remains untested. No hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rtkit-notification-ack-20261118/`.
The archive and restored copy passed complete inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `9fef98b9447c0ace6636a2d8c346a5c0e516fe03f89c4f51acd30c3a6b1c04b1` |
| `bundle.tar.gz.inventory.txt` | `3cbc1e50680983fb3a675fadaa9b982ddea99dfdf13bbe242b0fe2ccfd2434a8` |
