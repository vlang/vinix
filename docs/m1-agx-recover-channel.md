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

## Timeouts no longer stop the GPU

Asahi logs a RecoverChannel that the firmware has not consumed within its
one-second wait and keeps the GPU running. Vinix used to stop the GPU at that
point. It now logs `agx: timed out waiting for RecoverChannel; its queue stays
pinned` and keeps running, as Asahi does.
[Asahi timeout](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1717-L1722)

Unlike Asahi, which drops its workqueue reference when the handler returns,
Vinix keeps the queue pinned until the firmware consumes the command or
stops. Pins live in a table of 255 entries, one for each device-control
entry that can hold an unconsumed command. The event worker releases consumed
pins on every healthy pass. A new channel error also releases them before it
publishes, so a command the ring accepts always finds a free entry. A second
channel error while a command is pending now publishes another RecoverChannel
instead of stopping the GPU. A corrupt ring index still stops it, and so does
a full ring, where Asahi instead waits for space indefinitely.

The device-control ring is first-in, first-out. While the firmware leaves a
RecoverChannel unconsumed, later cache flushes and context invalidations on
that ring also time out after a second each, in Asahi as in Vinix. In Vinix the
pinned queue, its file's mappings and any context whose invalidation timed
out then stay allocated until the firmware catches up or the GPU shuts down.

The command is staged in manager storage rather than a local. Storing the
returned ticket in the table otherwise led V to move the local, which holds a
fixed array, to the heap for good: 48 bytes per channel error.

The sanitizer fixture now expects both timeout cases to keep the GPU running
with the queue pinned. It publishes a second command while the first is
pending and releases each pin as the firmware consumes it. Three mutants fail
it: a fatal timeout, a worker that never releases, and publication without
first releasing consumed pins. The G13 contracts require the worker release,
the table order and its capacity. An independent lifetime review found no
use-after-free, double release or table overflow; it raised the comment and
the ring stall described above.

The G13 failure suite passes under ASan/UBSan, as do 79 contract test files and
122 pinned reference checks. Both `PROD` kernels build. The allocation scan
matches the previous 427 findings, and the generated RecoverChannel path has no
`memdup`. The AArch64 kernel boots in QEMU and passes the mount-lifecycle
`descflags` case. The worker suite (`tests/agx-worker`) already failed to
compile on the base revision because its fixture lacks four manager methods; this
change adds a fifth. No M1 hardware test or reboot occurred.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-recover-timeout-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `76883d8cc683e006971708db27b482746a7a60b6f6f81155615842af5eab5a5c` |
| `bundle.tar.gz` inventory | `ca9b5a4de8e5d1d110456b723b81d1d2f5a03d4a07c4a97cf9d7f60b0edacd8e` |
