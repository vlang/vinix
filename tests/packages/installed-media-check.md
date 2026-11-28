# Receipt-bound offline media on an installed disk

The fixture starts with a blank 4 GiB disk and uses the normal VJFS installer.
The installed root contains the production package CLI, the reviewed consumer
configuration and the ISO package receipt. The host attaches the signed release
bundle on a separate ext2 disk during the second boot. Every boot runs with
networking disabled and verifies that the package CLI and configuration are on
the installed root.

| Boot | Required behavior |
| --- | --- |
| 1 | Start from the installer-selected disk with no package state. Prepare a destination owned by UID 1000. |
| 2 | Mount the separate media read-only. Refuse a mismatched receipt digest without publishing trusted catalog state or caching objects. Import the approved media and save its exact lock as UID 1000. Package activation stays empty. |
| 3 | Boot with the media disconnected. UID 1000 refuses an incorrect lock digest and reviews the exact seven application roots and ten locked packages. A separate approved apply installs from the cache. Coverage matches every locked package, and payload verification succeeds. |
| 4 | Boot again with the media disconnected. Recheck the saved lock's digest and ownership, exact installed generation, coverage and payload integrity. |

The controller requires four guest shutdowns, verifies from QEMU's actual
argument lists that the release disk was attached only for boot 2, and checks
that the source media image and pinned inputs keep their original hashes.
[Guest assertions](installed-media-guest/main.v)

## Reproduce

Supply a current [mixed release bundle](signed-legacy-routing-check.md#mixed-signed-release-approval)
with its target ISO receipt and exact reviewed consumer configuration.
The media directory contains `_deployment.json` and exactly the publishers in
the receipt. Use the [hardware test prerequisites](../hardware-platform/README.md)
and the `mke2fs` and `debugfs` from the same e2fsprogs installation. Set
`VINIX_MKE2FS` if the formatter is outside `PATH`. For x86-64, use
`VINIX_PLAIN_ISO_LIMINE` for the raw-initramfs fixture loader.

```sh
v -prod -no-skip-unused -enable-globals -path '@vlib|@vmodules|.|tools/accounts|tests/hardware-platform' \
  -o /tmp/installed-media-runtime-check tests/packages/installed-media-runtime-check.v
VINIX_HWTEST_TCG=1 /tmp/installed-media-runtime-check ARCH KERNEL MEDIA RECEIPT CONFIG NEW_WORK
```

The boot kernel and initramfs are supplied by fixture boot media. The release
bundle is a separate disk. This qualification covers package acquisition and
persistence on the installed root using a disposable publisher and the CLI.
Production publisher enrollment, graphical presentation and runtime execution
have separate acceptance checks.

## Qualification, 2026-11-28

At `b137bca5618452dd86624871b8e9690a8e8cd10a` both QEMU TCG guests passed.
AArch64 took 313.215 seconds and x86-64 took 226.420 seconds. Each run recorded
four guest-initiated shutdowns and attached its ext2 release disk exclusively
on boot 2. The controlling host also refused a receipt for the other target,
a different consumer configuration and mismatched media before creating a
work directory.

The runs used paired ISO receipts and the original reviewed configurations
with the retained signed mixed release. Both used previously qualified VJFS
kernels and freshly built static package CLIs. Earlier attempts recorded the
strict directory-ownership refusal, a consumer configuration with an uncached
additional publisher and the missing x86-64 serial routing. The accepted runs
use guest-root-owned media directories, receipt-matched configurations and
explicit serial routing.

The two installed disks and the two media images decoded to their original
SHA-256 values. The independent archive checker verified 4,491 sealed entries,
including those compressed images, the signed inputs, builds and both guests'
serial and QMP logs. Use `zstd -dc` with the `*.zst` images and compare their
decoded SHA-256 values with the corresponding `*.raw-sha256` files. The archive
SHA-256 is `a6ecf8ffff118837e04c8679c5fb80661cd978dfd6552d0062ea41acdcaaf9b0`.
[Qualification archive](/Users/alex/.local/state/vinix/mdisk.Zv3ZqN/qualification.tar.gz)
