# Base M1 G13 RecoverChannel transport

RecoverChannel publishes the command and retains its workqueue before the
send-empty wait can release the manager lock. The sender checks GPU state
after the wait and before touching the device-control ring. Firmware
consumption releases the queue reference. If consumption cannot be
confirmed, the reference survives until shutdown stops the ASC and releases
the queue backing.
[Asahi RecoverChannel path](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1692-L1722)

The host enqueue sequence and current unread count distinguish a consumed
command from a newer command that reused its modulo write index. A
doorbell timeout still allows a completion check because another sender's
doorbell may have notified firmware of the pending entry. The IRQ assists
mailbox transmit. Firmware consumption still uses Vinix's one-second
busy poll. FwCtl transmit remains polled.
[Asahi ring completion wait](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/channel.rs#L181-L208)

ARM64 and x86-64 builds and all 82 contract test files passed for
`f23e557af42f897825630cf67b4959772796d672` plus the archived patch.
The sanitizer fixture exercised 18 recovery cases across both G13 ABIs,
including IRQ and polling routes, delayed consumption, wrap and index
reuse, consumption after send timeout, ring faults, and shutdown during
the wait. Four negative controls caught lost queue references, modulo
completion, and skipping the completion check on send timeout.

The UAT flush, heap GC, context retirement, job lifetime, asynchronous
submission and file-close suites passed. Generated ARM64 C confirms ring
publication, queue retention and release ordering without new allocations
in the path. The allocation scan reproduced 178 baseline findings.
The full source audit remains `not_equivalent`. All checks ran offline.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-recover-channel-irq-20261118/`.
The archive and restored copy passed full inventory verification.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `cc523ca96b7cc8f6511e0e9a5678aa2884458808b355921274db4c9c549400f0` |
| `bundle.tar.gz.inventory.txt` | `aa52e9e33b44e40a78ffcfcf16ea0f55bb28e9b15a96fce7e31f0d6affc0b479` |
| `source.diff` | `e2305f71ead6ca5406a99ef3895188e74a580d0cff654e01bcc2ba897682b7f5` |
| `vinix-aarch64` | `2e8b78b51f86cc2dbbf6363a83b04c564ddd2ff4d152d5afb47f7008bd70d9c6` |
| `vinix-x86_64` | `328ccbaea0175171e25b575fc844e8d05764c06af6006b3907d37a0e49f56925` |

## Validating the tracked write index

An in-range device-control write index equal to the read index could make
an unread RecoverChannel command appear consumed. Vinix now derives the
expected write index from the issued ticket and the number of later host
publications. It checks that index under the TX lock before using the unread
count to decide completion. A mismatch latches a channel fault and retains
the recovery queue reference until stopped-firmware teardown. Later valid
publications can advance or wrap the ring while the doorbell sender waits.

The sanitizer regression reproduced early release on baseline
`b4fdab0cf2276539f285a0bb7a112effcc5edfa4`. The updated fixture passed 24
recovery cases across both G13 ABIs, including valid later publications,
corrupt write indices before and after wrap, and release at shutdown. The
context retirement, heap GC and FwCtl sanitizer suites also passed, along
with 79 local contract tests and 122 archived-reference checks. Isolated
AArch64 and x86-64 production builds passed. The allocation scan reproduced
the same 176 allowance findings with identical counts by file and warning kind.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-recovery-ticket-20261119.4vmenS/`.
The `bundle.tar.gz` SHA-256 is
`ca88801c25404bf97957c6fd88f2a2ec22d7b101be8e1ea0fede66a4a69d5f9c`.
Native M1 firmware validation remains open.
