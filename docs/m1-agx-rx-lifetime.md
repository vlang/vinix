# G13 receive ring teardown

Omarchy's pinned Asahi serializes receive polling under its RX mutex.
Vinix now holds the GPU manager lock while copying and acknowledging each
Event, KTrace or Stats entry. Shutdown uses the same lock to stop firmware
and release the channel backing.
[Asahi receive polling](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L472-L486)

Vinix releases the lock before dispatching from the private event copy.
Fault and channel recovery check running state under the manager lock.
A stale worker error preserves stopped state, and a repeated call to the
shared shutdown method returns once teardown has completed.

ARM64 and x86-64 builds, 82 contract files, three sanitizer suites and five
pinned source gates passed for `9b390e1520dd92ce367ef6dd3743cd26850ade15` plus
the archived patch. The failure fixture covers 18 receive/shutdown
interleavings, six stale fatal events, and two copied TVB payloads at ring
reuse. Three negative controls detected an unlocked acknowledgement, a
stale error overwriting stopped state, and repeated teardown. Independent
lifetime review and generated C checks passed. Receive copies stay on the
stack. The allocation scan reported one fewer ARM64 allocation site and
178 existing allowance discrepancies.

At this revision the audit reported `not_equivalent`, with open differences
in RTKit crash-log buffer ownership and G17 worker teardown. No hardware tests
or reboots occurred. [RTKit crash-log follow-up](m1-agx-rtkit-snapshot.md)

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rx-lifetime-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `920780fbce555cf7ee5ee3ef752a031dc60bdc3b6a6fc1f26c2e3cc9932b3a76` |
| `bundle.tar.gz.inventory.txt` | `06e07bf5b10cb94af57ff9d1bdadd71bd70ac4abbad6a54f2ffcc7eac8e0bdc3` |

## ASC mailbox receive during shutdown

The G13 worker now holds the manager lock while checking running state and
reading one ASC mailbox message. Shutdown takes the same lock before it
marks the manager stopped and stops the ASC. The worker releases the lock
before it dispatches the copied message.

The sanitizer fixture reproduced a FIFO pop racing shutdown on
`9fc17b7d32564db6895d7d0fa6a2156c8c246100`. Six cases passed across both
G13 firmware ABIs. Shutdown before a receive preserves both queued messages.
Shutdown after the first receive suppresses its power-state update and
preserves the second message. A later poll on a stopped manager leaves the
FIFO untouched.

AArch64 and x86-64 builds, the job-lifetime suite, 79 local contract tests,
and 122 pinned-reference checks passed. Generated AArch64 C keeps the FIFO
read within the manager lock. The allocation scan matched the 176 baseline
findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-rx-shutdown-20261119.N4nx89/`.
The `bundle.tar.gz` SHA-256 is
`4f12c50cc8e2addfa865aca3652cb981d36f7685707b0db47807c8e76c736af9`.
Native M1 firmware validation remains open.

## ASC stop confirmation before G13 teardown

G13 now reads back the ASC RUN bit after the stop write and its MMIO
barrier. Probe cleanup and runtime shutdown mask both claimed IRQs and
retain firmware-visible backing if the stop write or readback fails.
Runtime shutdown keeps the manager available for a later attempt. It
publishes stopped and retires UAT roots only after RUN has cleared.
A failed probe remains unpublished and retains its backing.

The sanitizer fixture reproduced premature RTKit buffer release on
`5d517cea2b49a21ec9df85a4ed499ad2e06cfa78`. Four cases passed across the
two G13 firmware ABIs with an injected stop failure in probe cleanup or
runtime shutdown. They check backing retention, IRQ masking and lock
release on failure, then verify cleanup after a successful stop.

AArch64 and x86-64 builds, the job-lifetime suite, 79 local contract tests
and 122 pinned-reference checks passed. Generated AArch64 C confirms the
readback and early return before release. The allocation scan matched the
176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-stop-readback-20261119.ErG0D4/`.
The `bundle.tar.gz` SHA-256 is
`936adb04e917cd00455624653cdc132816b364f0bda0da854f82c43968fc7e09`.
Native M1 firmware validation remains open.
