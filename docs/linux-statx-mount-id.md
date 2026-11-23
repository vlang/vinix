# Native statx mount identity

`statx` reports the mount attachment selected by its pathname lookup or open
file description. `STATX_MNT_ID` matches `/proc/self/fdinfo` and the mount's
entry in `/proc/self/mountinfo`. `STATX_MNT_ID_UNIQUE` selects the 64-bit ID
above the legacy ID range. When the caller requests both forms, the result
selects the unique ID. `STATX_ATTR_MOUNT_ROOT` identifies the root inode of the
selected attachment. [Linux 6.12.51 statx implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/stat.c#L248)

Bind aliases can report different mount IDs for the same inode. Relative
pathname queries retain the directory descriptor's route, including when `..`
leaves an alias. Empty-path queries and procfs descriptor links report the
attachment retained by an open descriptor. Lazy detach or replacing a bind
mount changes future pathname lookups and leaves retained descriptors on the
original attachment.

Mount namespace copies get fresh public IDs. Existing descriptors keep their
original attachments. The mount table keeps an internal identity to map saved
directory routes into the namespace copy. IDs identify mounts within one boot.

Anonymous descriptions without mount records still omit mount fields. DMA-BUF
continues to report the ID of its internal filesystem. `statmount` and
`listmount` remain separate, unimplemented interfaces.

## Qualification

The same probe ELF per architecture passed on Vinix and Linux 6.12.51. The
probe checks mount-root attributes, both ID masks, bind aliases, relative
descriptor paths, symlinks, and agreement with `fdinfo` and `mountinfo`.
It verifies that mount namespace copies and replacement mounts receive fresh
IDs and that inherited and lazily detached descriptors keep their IDs. The
previous Vinix kernels omitted the mount ID on the initial root query.

An initial AArch64 run captured an intermediate kernel before the final link
and failed the namespace-copy check. The final AArch64 run used the same
kernel as the regressions. Production builds used `c18df774b` plus the
archived source patch. Independent review found no new lifetime issues.
The allocation checker reported the same existing failures and the same
306 AArch64 and 254 x86-64 allocation sites as the baseline.

The `statx`, `statabi`, `namespace`, `clonefsns`, and `open` regressions
passed on both architectures.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `ce54cba326991b93` | `17f5f44f91d771cb` | `f998ad8180718c90` | `65948dec84d0c88f` |
| x86-64 | `06c6569a2c994587` | `fbd4a40182a3b3ae` | `03fc55cb7fa3aee5` | `648c126c7bbc90ca` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/statx-mount-id/qualification.tar.zst`, with SHA-256
`7d27e264ded3350bbb28d194be010041d8eee97393b133cd1432b9352c6623f4`.
