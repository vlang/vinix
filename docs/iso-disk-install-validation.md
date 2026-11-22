# ISO disk installation validation

The amd64 and arm64 production kernels were built from
`172b78f05f2c53644d7e40b578c2ae50c6342b8d` with the installer changes
recorded in `installer-source.patch` in the evidence bundle. The desktop
ISOs reused the November 19 desktop userland archives.

| Architecture | QEMU desktop checks |
| --- | --- |
| amd64 | Default live boot, BIOS live boot, UEFI installation on SATA, and disk-only boots under UEFI/SATA and BIOS/IDE |
| arm64 | UEFI installation on VirtIO, disk-only boot on VirtIO, and live boot with USB input |

All eight checks passed keyboard and pointer input. Both installs passed
the GPT and VJFS checks before their disk-only boots.

The V reboot-persistence fixture wrote and synced a 27-byte file on each
installed system. A fresh QEMU process booted only the installed disk and
read the original bytes. The installer refused a disk with data at 128 MiB
and a repartitioned disk with a stale Vinix backup GPT. Byte comparisons
confirmed that both target disks were unchanged. GPT unit tests and the
external ext2/ext4 host suite passed.

The checked ISOs, `SHA256SUMS`, and `validation.tar.gz` are retained in
`/Users/alex/.local/state/vinix/iso-disk-install.isFgbq/`. The validation archive SHA-256 is
`4edf26015b33562d212664965fe10c9d6d272023bf7ad463fafdfef9f2c5b88c`.
