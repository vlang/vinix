# Verified block roots

`build.py` appends a SHA-256 Merkle tree to a completed filesystem image.
Its import and command-line interface forwards geometry, policy parsing, hashing,
image construction and verification to the native V `verityimage` module.
`build-support/run-v-tool.sh` selects the compiler; the temporary installed
query executable is private to its Python process and removed at exit. The
kernel's verified-root profile reads this image through a read-only block view
and verifies each requested data block, including its path to the trusted root,
before returning its bytes. A checksum calculated only at boot would not
provide this property.

The root hash, data block count and selected device must come from an
authenticated policy. The [verified UEFI builder](../verified-boot/README.md)
pins them in the command line inside its signed, configuration-enrolled Limine
loader. A hash next to an unsigned image, an unauthenticated command line, or
an attacker-supplied JSON file does not authenticate the root.

## Build and sign

Prepare an ext2 image from trusted, reviewed inputs. The existing image
builders use 4096-byte filesystem blocks, 128-byte inodes and a limited ext2
feature set. For example, with e2fsprogs installed and `build/root-staging`
already populated, create a new 128 MiB image:

```sh
python3 -c 'with open("build/root.ext2", "xb") as image: image.truncate(128 << 20)'
mke2fs -q -F -t ext2 -b 4096 -I 128 \
    -O filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum \
    -d build/root-staging build/root.ext2
python3 build-support/ext2-set-root-owner.py build/root.ext2

python3 tools/verified-root/build.py build \
    --data build/root.ext2 --output build/root.verity > build/root.verity.json
```

Finish ownership changes and unmount the source before building its tree.
All later modifications require a new tree and signed boot policy. The source
remains unchanged; output must be a new file. On macOS, e2fsprogs may provide
`mke2fs` under `/opt/homebrew/opt/e2fsprogs/sbin/`.

The build prints JSON containing `data_blocks` and `root_hash`. Keep these
values with the trusted build output and supply them separately when checking
an image or signing the boot bundle:

```sh
python3 tools/verified-root/build.py verify build/root.verity \
    --data-blocks 32768 --root-hash TRUSTED_64_LOWERCASE_HEX_DIGITS

python3 tools/verified-boot/build.py build --arch aarch64 \
    --loader build/verified-limine-aarch64/BOOTAA64.EFI \
    --kernel kernel/bin/vinix --initramfs build/bootstrap.tar \
    --verity-root build/root.verity --verity-device /dev/vda \
    --verity-data-blocks 32768 --verity-root-hash TRUSTED_64_LOWERCASE_HEX_DIGITS \
    --key /private/signing/db.key --certificate /private/signing/db.crt \
    --output build/verified-root-boot
```

Replace the hash placeholder with the actual trusted build result. The boot
builder copies and fully verifies the image before signing. Its verifier
checks the image against the root and geometry pinned by the signed policy;
it never obtains authority from a neighboring metadata file. Normal signing
key and firmware trust deployment requirements still apply.

`boot/verity-root.img` in the bundle is a deployment artifact, not a Limine
module or a filename that the kernel opens. Deploy its exact bytes as the raw
contents of the device or partition named in the policy. For an ARM QEMU
virtio block root, for example, attach the image as:

```sh
-drive if=none,id=verifiedroot,format=raw,readonly=on,file=build/verified-root-boot/boot/verity-root.img \
-device virtio-blk-device,drive=verifiedroot
```

The name `/dev/vda` is valid only if this is the first enumerated virtio block
device. On x86 an IDE disk may instead be `/dev/ata0`; disk and partition
names depend on the configured controller and enumeration order. Pin the
actual device when signing. The kernel does not scan disks or fall back to an
ordinary root if the selected device is absent or fails verification. The
ordinary disk installation and persistence selectors are rejected in this
profile. Before creating the tree, provide plain directories `/dev`, `/proc`,
`/sys`, `/tmp` and `/run`, and a regular executable `/sbin/init` in the verified
filesystem. Symlink mountpoints are rejected. Optional `/var` and `/root` must
also be plain directories when present. `/tmp`, `/run`, and those optional
directories receive empty writable RAM filesystems; any files underneath them
in the disk image are hidden by the mounts. `/dev` and `/proc` retain the
kernel's device and process mounts, and `/sys` receives the platform mount.
The disk system root remains read-only. The authenticated bootstrap initramfs
is deliberately not extracted in this profile, so it cannot override system
files or supply a missing init program.

## Exact format

The image is the headerless, unsalted dm-verity format version 1 with SHA-256,
4096-byte data and hash blocks, and both devices represented by one image:

- Data occupies blocks `0 .. N-1`; its exposed size is exactly `N * 4096`.
- Each hash block holds 128 consecutive, raw 32-byte digests. Unused digest
  slots are zero. Hashes cover the entire block, including this padding.
- Each leaf digest is `SHA256(data_block)`. Parent digests are
  `SHA256(child_hash_block)`; there is no salt or metadata header.
- Hash levels start at block `N`, stored root first. Each level's blocks are
  ordered by increasing child index. A level has `ceil(children / 128)`
  blocks; repeat until there is one root block.
- For `N = 1` there is no hash tree and the root is `SHA256(data_block_0)`.
  For larger images, the trusted root is `SHA256(top_hash_block)`.
- A generated image is exactly the data plus all hash blocks. Geometry must
  fit within signed 64-bit byte offsets. The host verifier rejects extra bytes
  and truncation. A deployed raw device may have unused capacity beyond the
  image; the kernel hides that capacity and rejects a device too short for the
  authenticated geometry.

For example, `N=129` has the top block at 129 and two leaf hash blocks at
130 and 131. `layout(129)` returns `[(130, 2), (129, 1)]`, leaf level first.
This order lets callers walk up from data while retaining the physical
root-first layout.

The exact authenticated token is:

```text
vinix.verity=1,/dev/vda,N,64_lowercase_hex_root_hash
```

`command-line --device /dev/vda --data-blocks N --root-hash HASH` formats a
canonical token. The signed boot builder requires its dedicated four flags
and generates the token itself, rejecting manual injection, duplicate policy
and conflicting root selectors.

General data must be nonempty and 4096-byte aligned. `--pad` explicitly allows
zero-padding a final partial block; its full padded block is authenticated.
Use an aligned, completed ext2 image for bootable roots. The tool does not
check filesystem structure, application safety, ownership policy or whether
trusted build inputs themselves were compromised.

## Validation and limits

```sh
build-support/run-v-tool.sh tools/verified-root/verityimage/core_test.v
python3 tests/verified-root/test.py
python3 tests/verified-root/run-host.py
# On Linux with cryptsetup's real veritysetup available:
python3 tests/verified-root/test.py --veritysetup /usr/sbin/veritysetup
```

The tests cover tree-depth boundaries, data and every hash level, padding,
truncation, extra bytes, mismatched roots and geometry, input bounds and
command-line policy. The optional Linux check compares complete tree bytes
and root hashes with authentic `veritysetup`, then has it verify our images.
Host image tests are separate from kernel runtime enforcement tests.
The verifier in `kernel/block/verity/primitives.v` reuses the kernel's
allocation-free SHA-256 implementation. Its C ABI regression runs normal
and address/undefined-sanitized builds,
independent SHA-256 and geometry comparisons, every data block at tree-depth
boundaries, corrupt paths and short/error reads. It also checks the production
object has no heap allocator imports.

The runtime regression boots a real kernel on a 32 MiB ext2 fixture. For
example, after building the ARM kernel and genuine Limine loader:

```sh
python3 tests/verified-root/runtime.py --arch aarch64 \
    --kernel kernel/bin/vinix \
    --loader build/verified-limine-aarch64/BOOTAA64.EFI \
    --firmware-code /path/to/edk2-aarch64-code.fd \
    --firmware-vars /path/to/edk2-arm-vars.fd \
    --logs /tmp/vinix-verified-root-test
```

It needs QEMU, a static musl cross compiler and e2fsprogs. `--mke2fs` and
`--debugfs` select tools outside `PATH`; `--accel hvf` enables ARM hardware
acceleration on supported Macs. Use `--arch x86_64`, the corresponding kernel,
loader and firmware for x86. The fixture pins `/dev/vda` on ARM and `/dev/ata0`
on x86 and attaches those specific controllers.

The guest checks read-only open, rename, unlink, attributes, shared mappings,
permission upgrades, remount and mount aliases, writable RAM directories and
bootstrap exclusion. Slab measurements compare every live allocation class
and large-allocation page count across 1000 verified-device reads and 1000
shared read-only fault/unmap cycles after warmup. The harness changes an
authenticated payload block after boot: cached authenticated bytes stay
intact, while direct reads and reads after cache eviction return `EIO`.
Separate boots reject corrupted metadata,
init data, every tree level, truncation, root mismatch, malformed or conflicting
policies, and a correctly hashed root missing a required mountpoint.

Add `--secure-boot --virt-fw-vars /path/to/virt-fw-vars` with a Secure Boot
firmware image to sign the fixture and enroll its temporary certificate in a
copied VM variable store. This checks the full firmware-to-root chain: actual
firmware must reject an unsigned loader and a modified signed loader before
the valid signed root may pass. It never modifies host
firmware. Without that option the test exercises kernel enforcement with
firmware Secure Boot disabled, and does not establish the firmware trust
anchor. Fixture keys are temporary and removed after successful runs.

This is read-only integrity, without encryption, writable authenticated
storage, FEC, antirollback, attestation or signing-key management. Writable
RAM mounts and any separately deployed writable storage need their own
operational policy. Privileged kernel compromise remains outside a block
integrity boundary.

The [Linux dm-verity documentation](https://docs.kernel.org/admin-guide/device-mapper/verity.html)
describes the authenticated root requirement, root-first format and failure
of reads that cannot be verified. The
[Linux target implementation](https://github.com/torvalds/linux/blob/master/drivers/md/dm-verity-target.c)
also specifies the single-data-block case and level offsets.
