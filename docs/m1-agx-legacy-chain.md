# G13 timeline interoperability

Native G13 legacy and modern submissions use the same cumulative fence chain
as the DRM syncobj ioctls. Legacy inputs capture the current fence at point
zero, resolve nonzero points by chain sequence, and accept retired prefixes.
Legacy outputs accept zero, repeated and decreasing points under the same
sequence rules as modern outputs. Staging validates the full legacy output
list and reserves its chain nodes before job setup. Failure releases each
unpublished reservation and held syncobj reference. Publication uses the
captured object even if userspace removes or reuses its handle.

The comparison uses Vinix `e9519cc81` plus this patch and Omarchy's
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. Asahi resolves
inputs with `chain_find_seqno`, allocates output chains after parsing, and
adds them to the same DRM syncobj used by the core ioctls.
[Asahi sync staging](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L166-L246)
· [Asahi G13 output publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L983-L1007)

The native AGX sanitizer fixture ran producers and consumers through both
submission ioctls on two queues. Retiring the later producer first kept the
cumulative prefix pending. The DRM fixture verified timeline WAIT, sync-file
export and import, and publication after handle reuse. Fault injection
covered each reservation in a three-record list and a later job-storage
failure. The old dispatch accepted a submission when the regression required
`ENOMEM` from its output reservation. The independent lifetime review,
file-close suite, 82 V contract tests, five pinned source gates, and AArch64
and x86_64 kernel builds passed.

Compiler-reported allocation sites stayed at 377 on AArch64 and 289 on
x86_64, with the same 178 existing findings. The generated AArch64 frames
for the legacy ioctl and its staging routine sum to 9,472 bytes, down from
15,344 bytes with the preceding build. Each published timeline output adds
one retained chain node. Published fence reclamation remains open.

The fake AGX backend uses its sparse map. Generic timeline capability
reporting, matched Mesa and full scheduler qualification remain open. In
the pinned G13 driver, the scheduler's finished fence records deadline hints
and the underlying job fence implements the two naming callbacks. G13
inherits the default empty CPU wait hint. The CPU hint override belongs to
G17. All validation for this increment ran on the host.
[G13 hardware fence callbacks](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L190-L201)
· [Default CPU wait hint](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L330-L333)
· [G17 CPU wait hint](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/g17/mod.rs#L1485-L1494)

The patch, binaries, generated C, logs and complete restored evidence are
under `/Users/alex/.local/state/vinix/omarchy-m1-legacy-chain-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `8e802ca89608b8ce1bff7a85d7b779c085bfdfb6a2ffdeed66356cc81bda628a` |
| `bundle.tar.gz.inventory.txt` | `4e7722247dca2aad914a8bfca1064abef58aa61dc200950354a0e0f850d49f02` |
