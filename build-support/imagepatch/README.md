# Native image mutations

`build-support/ext2-set-root-owner IMAGE` clears the low and high UID/GID
halves of every ext2 inode. It retains the previous tool's rejection of 64-bit
and checksummed images, handles revision-zero inode sizes and partial final
groups, and diagnoses truncated descriptors and inode tables. Geometry is
bounds-checked before table allocation and offset multiplication.

`build-support/patch-elf-interpreter BINARY OLD NEW` replaces exactly one
NUL-terminated interpreter path, pads a shorter path with zeros and retains
the binary's size and permissions. Missing or duplicate paths and longer
replacements fail before writing the image.

Both commands compile and run V directly, using ordinary `V` or
`VINIX_V_COMPILER` selection. Image builders and verified-root preparation
invoke these commands without Python.

```sh
v -cc cc test build-support/imagepatch
bash tests/storage/test-qemu-storage.sh
```

Qualification compared the removed Python tools against native ARM and Rosetta
x86 binaries for 21 ext2 cases and ten interpreter cases. Four ext2 cases used
real mke2fs images with 1 KiB/4 KiB blocks and 128/256/512-byte inodes. Complete
image bytes, error status and ext2 diagnostics matched; repeated ownership
fixes were idempotent. These are host image checks, not guest-boot evidence.
