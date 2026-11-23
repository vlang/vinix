# Reinstalling on a partitioned disk

The production kernels were built from `5fab77715bbc250f9fcf9fc14812f5e963f3bc42`
with the changes in the retained `installer.patch`. The test disk was a 4 GiB
image with an EFI partition and a Haiku BFS partition type in GPT slot 3.
That slot overlapped the new Vinix root and exercised replacement of the old
AHCI partition device.

- The amd64 desktop ISO replaced the old GPT on SATA under UEFI. Both the
  initial install and a fresh boot with the ISO detached reached the desktop.
- The amd64 probe booted the hybrid installer as a writable SATA disk under
  BIOS. It installed to the separate target and left the installer disk
  byte-for-byte identical to the ISO. The installed disk booted alone under UEFI.
- The arm64 probe preserved the old disk through the blank-disk path and
  preserved both disks when the erase menu was confirmed with two targets.
  With one target it replaced the old GPT and booted from VirtIO alone.
- Both architectures read the file written by the reboot-persistence fixture
  before the installer was detached. The GPT and external ext2/ext4 host tests
  passed.

The desktop ISOs, checksums, and `validation.tar.gz` are retained in
`/Users/alex/.local/state/vinix/iso-reinstall.dGyALV/`. The validation archive SHA-256 is
`d972a6692afd87d5bc82d403c028c5a97f161f20662ab454c087ba7d25bb9d8f`.
