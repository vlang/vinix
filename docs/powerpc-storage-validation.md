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

The follow-up `/tmp/vinix-ppc-ext2-final-audit` adds replacement of an open
file by a symlink, checks the directory entry type with e2fsck, and uses
borrowed inode pointers to prevent V's automatic heap promotion in the
freestanding kernel. Invalid nonzero block references fail instead of being
read as sparse holes. Base revision: `0bf9a3b04`, with exact sources retained.
Manifest SHA-256:
`165454bd6573532757d2ff80dd7013a5d5565490a3bdf9cc8c27527aa60f4657`.

## Native and desktop qualification

The native PPC musl fixture passes two independent QEMU boots: creation,
exclusive-open errors, CLOEXEC, chmod/statx, 64 KiB direct/indirect data,
64-bit seek, EFAULT, rename, fsync, symlinks/NOFOLLOW, getdents64, nonempty
directory errors, unlink-open retention, stdio readv/writev, getrandom and a
counter retained across process/emulator restart. Both offline fsck runs pass.

The real desktop fixture enters `vinix` / `test123` through USB. It saves the
account without application patches or registration bypasses, verifies the
root-owned 0600 profile and its scrypt hash, checks home folders, restarts QEMU
with the same disk, and reaches `first canvas presented`. Both boot captures
show the desktop; the second does not require registration input. Both fsck
runs pass. The test accounts and private random seeds remain outside Git.

Source base for these bundles: `1dc267a58`, with all exact kernel, firmware,
fixture and runner sources preserved in each bundle. Desktop executable:
`/tmp/vinix-ppc-desktop-native/vinix-desktop`, copied into the image bundle and
bound by its manifest. The desktop cross-build evidence remains at
`/tmp/vinix-ppc-desktop-native`.

| Bundle | SHA-256 of SHA256SUMS |
| --- | --- |
| `/tmp/vinix-ppc-storage-qualified` | `290ae452a9881af1349ab73285fea355834ef565fcfc44f2421081b43c905bc0` |
| `/tmp/vinix-ppc-account-qualified` | `c1e035bfd6c2c504f00303cd5edb55fc4d1c7e1f9266facb1fd640dd16a81863` |
| `/tmp/vinix-ppc-storage-shell-regression` | `cbca350ae63562c95627e7702a08b585fcc58b9c08df8c0a0796ffaaa5c95744` |
| `/tmp/vinix-ppc-storage-runtime-regression` | `6e9acda8b9402e6d572686d035ac24f10219ccde0e104067857366041fcbd010` |

The shell regression uses 128 MiB, nested USB hubs and graphics, and verifies
keyboard/mouse, framebuffer, DHCP/ARP/ICMP and captured USB audio. The musl
regression passes its existing heap/mmap, input wait, TLS and FPU checks.
SHA-256 and ChaCha20 host vectors pass. The native freestanding kernel links
without an allocator; its generated C contains no heap-allocation calls.

These results qualify account persistence and this bounded filesystem in
QEMU, not arbitrary power-loss recovery or physical iMac hardware. Separate
applications still lack process/IPC support; icons are not application tests.
