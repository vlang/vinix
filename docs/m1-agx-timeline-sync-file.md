# DRM timeline sync-file descriptors

Vinix accepts the 24-byte HANDLE_TO_FD and FD_TO_HANDLE requests from
Omarchy's packaged Linux-Aurora. The 16-byte requests zero-extend the
missing point. The timeline flag selects a point for sync-file operations.
Point zero selects the current head on export and replaces it on import.
Opaque descriptors transport the syncobj identity and require a zero point.
[Packaged DRM UAPI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L930-L949)

Export reserves a CLOEXEC descriptor slot before looking up the fence,
including when the point is missing. A retired point exports a completed
stub. Import checks the descriptor type before resolving the destination,
then reserves a chain node before publishing a nonzero point. The node uses
the imported fence and the existing destination prefix. Allocation failure
leaves the destination fence unchanged.
[Packaged syncobj descriptor handlers](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c#L736-L912)

The reference import passes the captured fence to the chain constructor.
Its generic constructor emits a diagnostic for a chain payload. Vinix retains
that captured chain and propagates completion through its existing iterative
notification queue. Independent lifetime review checked that each callback
link belongs to its retained parent and that failed publication frees the
private reservation.
[Packaged chain constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/dma-fence-chain.c#L219-L275)

The sanitizer fixture ran 100 cycles including earlier-point selection,
retired stubs, nested snapshots, FD close, exhaustion and OOM. A control
using the old handlers rejected point export. Restoring the old chain guard
rejected sync-file import of a timeline snapshot. The production wire decoder
passed the 16- and 24-byte tests for both ioctls. The timeline-chain,
DRM syncobj and AGX file-close fixtures also passed.

The AArch64 MP and x86_64 kernels built. All 82 V contract tests and five
pinned source gates passed. The compiler reported the same 377 AArch64 and
289 x86_64 allocation sites and the same 178 allowance findings as the
baseline. The tests drained completion before retiring fixture-owned storage
and verified that allocation failure returned all temporary ownership.

The host checks used Vinix `53edcb405` plus the tested patch and Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Open items include syncobj eventfd
notification, generic timeline capability reporting, WAIT deadline
propagation, published fence reclamation, scheduler behavior and matched Mesa
validation.

Captured inputs, outputs and verified restoration are under
`/Users/alex/.local/state/vinix/omarchy-m1-timeline-sync-file-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `9d0f81a6ddd8640794912cc9bf3c93d48bdf17ac7a5faef07be4053c163625a8` |
| `bundle.tar.gz.inventory.txt` | `61d3bc4bbb550e201df1c520688cf5b0bc9e74a5d91a5657ac753bc0f3524f47` |
