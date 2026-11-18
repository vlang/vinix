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

The audit remains `not_equivalent`. RTKit crash-log buffer ownership and
G17 worker teardown remain open. No hardware tests or reboots occurred.

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rx-lifetime-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `920780fbce555cf7ee5ee3ef752a031dc60bdc3b6a6fc1f26c2e3cc9932b3a76` |
| `bundle.tar.gz.inventory.txt` | `06e07bf5b10cb94af57ff9d1bdadd71bd70ac4abbad6a54f2ffcc7eac8e0bdc3` |
