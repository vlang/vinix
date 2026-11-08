# PowerPC writable storage validation

The allocation-free ext2 implementation supports one block group, 4 KiB
blocks, 128-byte inodes, direct and single-indirect file data, directories,
fast symlinks, modes, file replacement, unlink-open files and explicit flush.
Unsupported feature bits and layouts are refused. Directory moves and files
larger than 4,243,456 bytes are not implemented. This is non-journaled ext2:
completed flushes provide persistence; interrupted metadata operations may
require an offline filesystem check.

The host fixture uses the same filesystem implementation as the PPC kernel.
It checks indirect I/O, exclusive creation, permissions, replacement, symlink
resolution and loops, unlink-open lifetimes, space reclamation, remount and
negative path cases. `e2fsck -fn` independently checks the resulting disk.

Run from the repository root with V and e2fsprogs installed:

```sh
v run tests/powerpc/ext2-check.v /external/fresh-ext2-audit
```

The initial passing bundle is `/tmp/vinix-ppc-ext2-audit`, built from
`6e3de2ba9` plus the complete sources preserved in that bundle. It includes
the formatter, fixture, disk, logs, source copies and SHA-256 manifest.
Manifest SHA-256:
`d63555590d38e0ddbf6d4a4e69326de50f7d59382a70d66ddb976d0dd8093950`.
