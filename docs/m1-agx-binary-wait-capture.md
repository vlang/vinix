# Binary DRM WAIT capture ordering

Binary WAIT now snapshots and validates all input fences before registering
for future submissions. If a fence appears and is removed between its
snapshot and registration, the wait observes the current object at
registration. The same lock protects that recheck and the registration, so a
fence still present at registration is captured and the first later
publication is retained across reset or replacement.
[Packaged Linux syncobj implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c#L1070-L1220)

The initial ready check precedes registration, as in the packaged DRM core.
WAIT_ANY returns the first signaled entry observed in the successful pass.
WAIT_ALL carries the initial ready index or UINT32_MAX when every entry was
pending. That mirrors the reference implementation. The UAPI defines
`first_signaled` for WAIT_ANY.
[Packaged UAPI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h)

A lock-injection test publishes and clears a completed fence while the second
object is being snapshotted. The baseline returns early. The fixed handler
reschedules and returns after the subsequent submission completes. The
ASan/UBSan suite passes 6,001 binary wait checks and 5,600 large wait checks
through 4,096 handles, plus publication, cancellation and buffer cleanup
tests. Standalone timeline-chain and DRM framing tests also pass.

AArch64 MP and x86_64 builds, 82 contract tests and five pinned source
protocol gates pass. The original stack or heap buffer still owns the
capture nodes. Deferred cleanup unlinks registered nodes under the object
lock before that storage returns or is freed. Generated C shows no new
allocation calls. The compiler reports the same 377 AArch64 and 289 x86_64
allocation sites and the same 178 allowance findings as the baseline.

This host comparison uses Vinix `b80899d56` plus the tested patch and
Omarchy's Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`.
Open items include WAIT deadline propagation, generic timeline capability
reporting, full scheduler behavior and matched Mesa validation.

Captured inputs, outputs and verified restoration are under
`/Users/alex/.local/state/vinix/omarchy-m1-binary-wait-20261117/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `6fa4a93925869a1b690c88f68693bc49fc5d1fa77dd18863d1fc758a0541a116` |
| `bundle.tar.gz.inventory.txt` | `ca0046203ae2aa9324dd9cfc5b95b3fa9aa9409ab0d1611f98536cd88e8891e5` |
