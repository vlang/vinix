# Base-M1 Mesa packets and stamp flushing

The pinned Honeykrisp driver uses serialized G13 queues and selects the
240-byte render prefix before `bg_eot_rsrc_spec_hi`. The ordinary compute
payload is 128 bytes. A host probe compiled against Mesa's C headers built
both records and passed them through Vinix's packet reader. The reader
accepted the mixed packet and rejected a render extension with a nonzero
historical dependency. The check uses Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`.
[Mesa command sizes](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/asahi/lib/agx_device.h#L537-L561)
· [Honeykrisp render size selection](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/asahi/vulkan/hk_drm_render_core.c#L108-L121)
· [G13 queue policy](https://github.com/omacom/mesa/blob/b7b03c5b3b8abe1e040d6056dc62c01b02d3639c/src/asahi/vulkan/hk_queue.c#L1770-L1782)

The modern submission decoder now marks the final command of each engine
after the entire packet validates. The render flag reaches both vertex and
fragment firmware metadata. Linux-Aurora records the last render and compute
indices on its first pass and sets the same flags on the next pass. Software
attachment records can follow the final hardware command. The reference is
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. The tested Vinix
sources are `0a59b2430` plus this patch.
[Linux G13 command counting](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L741-L788)
· [Linux G13 job preparation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L899-L945)

ASan/UBSan checked 16,384 packet commands against the reference field
model and verified one-engine packets, trailing software records and invalid
input. The async ioctl fixture checked the flags at job preparation, including
a 64-command batch with Mesa-sized records. A control that cleared the flags
failed the compute comparison. Both kernel builds, 82 V test files and five
pinned source gates passed. Generated AArch64 code applies both final flag
writes without new allocation calls. The allocation scan reported the same
178 existing allowance findings.

These host checks cover the selected packet sizes and stamp-flush placement.
The packaged Mesa build, physical firmware execution, full scheduler behavior
and published fence reclamation remain open.

The tested patch, native binaries, pinned sources and restored evidence are
under `/Users/alex/.local/state/vinix/omarchy-m1-mesa-packets-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `1b5c3618b37bdde1e43186c370388157586ff8cd18896f0d649e29b05031467e` |
| `bundle.tar.gz.inventory.txt` | `970209d94ac1390890848aa1c36aa8184c98cbd1e0a185b14af3c8f138a25f6f` |
