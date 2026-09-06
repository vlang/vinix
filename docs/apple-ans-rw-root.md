# M1 ANS: partition writes, durability, and an explicit SSD root

This extends `ans/m1-air` at
`f206531c044022cbccf7e7566a4c1a686547fc6f`. It is an experimental implementation,
not a hardware-qualified storage stack. Host tests and production-C AArch64
cross-compilation have been run; the complete V/kernel build and physical M1
acceptance tests have **not** been run. The V filesystem/syscall integration
therefore remains a bring-up candidate, not a verified boot result.

## Supported behavior

* Opt-in block writes to **one explicitly selected Linux-data GPT partition**.
  The raw namespace and all other partitions remain read-only. Every NVMe Write
  uses FUA; a real namespace Flush completes before a successful write return.
* Byte-granular writes on 512-byte and 4096-byte namespaces, using serialized
  read/modify/write for partial sectors and private DMA/PRP buffers.
* `fsync`, `fdatasync`, `sync`, `syncfs`, and the block `BLKFLSBUF` ioctl reach the
  controller flush path. Errors are not replaced with successful stubs.
* Ordered shutdown: stop accepting I/O, flush, delete I/O queues, normal NVMe
  shutdown, controller disable, RTKit AP quiesce / IOP sleep, stop ASC, then
  remove only driver-owned SART entries. Each wait has both a clock deadline
  and an iteration bound. Failure prevents the normal reboot/poweroff call.
* Explicit read-only ext2 root selection by PARTUUID, before launching
  `/sbin/init`, preserving `/dev` and providing RAM-backed `/tmp` and `/run`.
* A read-only SHA-256 reference-comparison utility for hardware acceptance.

**Not included:** writable ext2/root filesystem support, APFS access, an SSD
installer, formatting/partitioning, TRIM/discard, raw NVMe passthrough, suspend
and resume, crash recovery, or power-loss qualification. Raw writable block
access is not a claim that a writable filesystem has been implemented. The
legacy ext2 allocator is deliberately not used: its allocation/bitmap paths
are not suitable for enabling writes to an internal SSD.

Keep a complete backup and a known-working boot entry without ANS enabled.
Only authorize a disposable test partition. Do not use macOS, Recovery, iSC,
EFI, or another operating system's live filesystem as the write target.

## Build and test

Apply `vinix-m1-ans-rw-root.patch` to a clean checkout of the base commit:

```sh
git switch -c ans-rw-root-test f206531c044022cbccf7e7566a4c1a686547fc6f
git apply --check /path/to/vinix-m1-ans-rw-root.patch
git apply /path/to/vinix-m1-ans-rw-root.patch
CC=clang SANITIZE=1 ./tests/apple-ans/run.sh
CC=gcc ./tests/apple-ans/run.sh
python3 tools/apple-ans/test_verify_reads.py
make -C kernel ARCH=aarch64 CC=clang
```

Retain the V compiler and linker overrides from your working M1 build. The
archive's `source/` directory is an overlay of changed files, not a standalone
Vinix checkout. No deployment or partition-changing command is run by the
patch or tests. Keep the existing m1n1/U-Boot/Limine chain and a bootstrap
initramfs; this patch selects the kernel's filesystem root, not the bootloader.

## Explicit boot policy

First boot with only:

```text
vinix.apple_ans=1
```

This exposes read-only namespace/partition devices and prints partition UUIDs.
Use a separate boot entry for each experiment. Replace UUID placeholders below
with the actual GPT **unique partition GUIDs**, not filesystem UUIDs, type GUIDs,
or device names. The bootloader does not expand shell variables in these lines.

To enable writes while retaining the initramfs root:

```text
vinix.apple_ans=1 vinix.ans_rw=PARTUUID=<scratch-partition-uuid>
```

To select the SSD root without enabling any writes:

```text
vinix.apple_ans=1 vinix.root=PARTUUID=<root-partition-uuid> vinix.rootfstype=ext2 vinix.rootmode=ro
```

Both may be specified, but the root and writable UUIDs must be **different**.
For example, a readonly root and a separate raw scratch partition may share
one namespace. There is no automatic mount of a writable data filesystem.

Optional, explicit recovery fallback:

```text
vinix.rootfallback=initramfs
```

Without this option, a requested root that cannot be resolved, read, validated,
or prepared stops boot before userspace. A malformed or contradictory policy
is rejected before probing. A syntactically valid but missing/ambiguous UUID
can only be detected after read-only discovery; it enables no writes.
`vinix.rootmode=rw` is rejected, not silently downgraded. `vinix.apple_ans=0`
overrides a probe enable; it is an error to combine that disable with an SSD
root or write request. `-d no_apple_ans` still compiles out hardware probing.

A write selection additionally requires:

* One unique GUID match across all exposed namespaces.
* Linux filesystem-data type `0fc63daf-8483-4772-8e79-3d69d8477de4`.
* Valid, mutually consistent primary and backup GPT headers and byte-identical
  partition arrays. A one-copy recovery GPT is adequate only for reads.
* No hybrid MBR and no GPT read-only attribute on the selected partition.

Policy is established once per boot. `BLKROSET`, admin passthrough, and namespace
writes cannot bypass it. Namespace/partition geometry and the final submission
path both enforce the permitted extent. No kernel address supplied by a caller
is used as a device PRP: DMA stays in the driver's private arena.

## Write and flush semantics

The V wrapper holds the ANS controller lock across the complete operation,
including any leading/trailing sector read/modify/write. The low-level command
authorizer also checks the namespace, LBA range, FUA bit, transfer limit, PRPs,
and opcode immediately before submission. A block-device write may return a
short successful count for requests larger than 1 MiB; callers must handle it.
An attempted write extending past the selected partition is rejected before
sending data.

A successful write means the controller completed all constituent FUA writes
and the final Flush. This relies on the device honoring NVMe semantics; it is
**not** evidence of physical power-loss durability. Multi-command writes are
not transactions. A failed/timed-out request may already have changed some
sectors. The driver reports failure, stops I/O, does not automatically replay
the request, and retains DMA allocations to prevent late DMA into reused RAM.

`fsync` and `fdatasync` validate the descriptor and reject non-file/non-block
objects and O_PATH descriptors. `syncfs` validates its descriptor. These ARM64
handlers flush all ANS namespaces: ANS is the only persistent backend enabled
by this path; tmpfs has no durable writeback. They are not a generic cache
framework for future storage drivers. libc's `sync()` has a void interface;
use `fsync()`/`fdatasync()` or an explicit flush ioctl to observe errors.
Applications must also flush their own userspace buffers.

The current Process model has no credentials/capabilities. The reboot handler
therefore permits **PID 1 only**, checks Linux reboot magic values and supported
commands, and calls PSCI only after successful ANS shutdown. This is not an
implementation of CAP_SYS_BOOT. Normal init should stop applications before
requesting reboot/poweroff; a non-PID-1 forced reboot request returns EPERM.
If PSCI returns, the syscall reports EIO rather than claiming poweroff worked.
No forced-reset bypass is provided after a failed storage shutdown.

## Filesystem and root contract

The new byte-oriented C reader loads the ext2 superblock at **byte 1024**,
independently of the SSD's sector size. It supports clean-flagged Linux ext2
revision 0/1 images, 1/2/4 KiB blocks, classic direct/single/double/triple block
pointers, sparse regular files, large-file sizes, and inline/block symlinks.
Common 128-byte and 256-byte inodes are tested. Mode/executable bits, ownership,
link counts, sizes, and classic timestamps are preserved.

The feature allowlist covers ext_attr, resize_inode, dir_index, FILETYPE,
sparse_super and large_file. Journaling/recovery, extents, 64-bit group formats,
metadata checksums, compressed/encrypted/inline-data encodings and unsupported
features are rejected. This is not a filesystem checker or repair tool. Block
and inode references, group-table extents, directory record lengths, names and
all partition-relative reads are bounded. Directory cycles/aliases, duplicate
names, and invalid dot entries fail preparation.

Prepare the root image on a known-working OS. It must contain an executable,
Vinix-compatible ARM64 `/sbin/init` (or a resolvable symlink), its interpreter
and libraries, and ordinary directories `/dev`, `/tmp`, and `/run`. Use an init
that supports a readonly root and RAM-backed runtime directories. On-disk
special devices, FIFOs and sockets are not supported; keep `/dev` empty because
the existing devtmpfs is reused. No assumptions are made that the current full
userland image's init is already compatible with these restrictions.

The tree is prepared before publication, with limits of 32 directory levels,
32,768 nodes and 64 MiB of directory data. The VFS follows symlinks with a shared
bounded recursion budget. Init is checked **after staging the runtime overlays**
and must still resolve to the SSD filesystem, not to old initramfs or a hidden
runtime file. Preparation failure restores the original root when the explicit
fallback option permits it; it never selects a different SSD partition.

Reads and private file-backed mappings support program loading. The root
resource owns immutable source pages, which the existing VM copies for private
mappings. Shared mappings are rejected. The simple source-page cache and tree
have boot lifetime and no eviction/reclamation policy yet; failed tree
preparation also retains its bounded allocations until reboot. This is a
bring-up limitation, not a production memory-management design.

VFS creates, symlinks, links, unlink/rmdir, rename, chmod, writable opens and
truncation paths reject this immutable tree; resource writes/grows independently
return EROFS. `/tmp`, `/run`, and devtmpfs remain RAM-writable. No unsupported
ext2 mutation is routed to the writable scratch partition.

## Physical acceptance: read-only first

The supplied verifier never opens the source for writing. It compares a
manifest from a user-trusted reference OS with reads under Vinix using 513,
4096 and 65521-byte chunks and repeated passes. It handles short reads and
rejects malformed manifests, duplicate/overlapping ranges, overflow and EOF.
Manifest creation uses a new regular file with exclusive creation: an existing
device, regular file or symlink cannot be truncated.

On a known-working OS, with the selected partition **unmounted and unchanged**:

```sh
python3 tools/apple-ans/verify_reads.py record /path/to/reference-partition ans-reference.json \
    --label 'Known-working OS; unmounted dedicated ext2 test partition' \
    --range 0:1048576 --range 1048577:65536
```

Choose additional disjoint ranges near the middle and end using that
partition's known geometry. Copy the manifest and utility into your bootstrap
userland. With Python 3 available under Vinix, target the same partition view
(offsets are relative to the partition, not the namespace):

```sh
python3 tools/apple-ans/verify_reads.py check /dev/ans0n1pN ans-reference.json --passes 3
```

The utility reports a **reference comparison**, not independent proof that a
particular physical device was reached. Regular-file host tests are explicitly
labeled as such. No M1 result is supplied with this patch. Record the hardware,
firmware/boot chain, kernel commit, geometry and output alongside a real run.

Only after repeatable reference reads should you test writes on a backed-up,
disposable partition. Test partial sectors, sector/page boundaries and transfers
larger than one PRP page; verify surrounding bytes and untouched partitions
against the reference OS. Test Flush failure reporting and orderly reboot.
Then compare data after a cold boot and inspect the filesystem from the known-
working OS. A host model or a same-boot readback is not a substitute for this
acceptance run. Abrupt-power-loss testing is not implemented or automated.

## Validation supplied

* 27 ANS host groups, including the original 18, partition policy, 512/4096-byte
  RMW writes, PRP authorization, failed writes/flushes, shutdown order/timeouts,
  GPT redundancy/hybrid exclusion, and ANS DMA-to-ext2 partition-boundary tests.
* 7 standalone readonly-ext2 groups, including all indirection levels, sparse
  files, symlinks, unsupported/unclean formats and 10,000 superblock mutations.
* 7 Python verification-tool tests using regular-file fixtures only.
* Clang ASan/UBSan and optimized GCC C runs; freestanding AArch64 compilation.

The original namespace/GPT mutation tests remain in the ANS suite. All tests
operate on allocated fake media or temporary regular files. There is no
hardware, complete V/kernel build, boot, writable-filesystem or persistence
claim in these results.
