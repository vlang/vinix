# Mounted block device policy

Securelevel 1 now refuses direct userspace writes to a mounted physical disk
extent and every overlapping partition or device alias. Securelevel 2 refuses
all direct block device writes. Read-only and `O_PATH` opens remain available;
filesystem metadata and page-cache writeback continue through their internal
driver path.

The policy uses capabilities provided by the actual AHCI, NVMe and VirtIO
block resource, with an absolute parent-disk extent for partitions. An inode's
mode, `rdev`, pathname or the mount source string cannot supply this identity.
An `mknod` proxy snapshots its backing resource's identity before applying the
requested inode metadata, including aliases labelled as character devices.
Unknown block identities fail closed at securelevel 1. Filesystems without a
physical identity still mount, preserving the same userspace prohibition.

`open`, `write`, `writev`, `pwrite`, `splice` and `copy_file_range` check the
actual sink resource, so a writable descriptor opened before raising the
level cannot bypass the policy. A refused transfer consumes no source pipe
data and changes no offsets. A successful write holds a scalar inventory
token until its physical operation completes; a mount racing an overlapping
write returns `EBUSY`. Failed mounts release their reservation. No policy lock
is held across a resource lock or potentially sleeping I/O.

Protection intentionally persists after unmount. The current filesystem and
cache lifetimes include detached instances and borrowed references, so
unmount does not establish that writeback has stopped. A write authorized
before raising securelevel may finish; the policy does not revoke already
issued DMA.

## Run

Build tracked production kernels on both architectures, then run:

```sh
V=/path/to/v python3 tests/mounted-disk-policy/host.py
python3 tests/mounted-disk-policy/check-generated.py --arch=aarch64 kernel/obj/blob.c
python3 tests/mounted-disk-policy/check-generated.py --arch=amd64 build-amd64-kernel/obj/blob.c
VINIX_VM_RUNNER_ROOT=/path/to/vinix \
VINIX_KERNEL_DIR="$PWD/kernel" \
VINIX_AARCH64_SYSROOT=/path/to/vinix/build-aarch64-userland/sysroot \
VINIX_QEMU_RT_NO_BUILD=1 VINIX_QEMU_AUDIO=off \
python3 tests/mounted-disk-policy/run.py
VINIX_VM_RUNNER_ROOT=/path/to/vinix \
VINIX_AMD64_KERNEL="$PWD/build-amd64-kernel/bin/vinix" \
VINIX_QEMU_RT_NO_BUILD=1 \
python3 tests/mounted-disk-policy/run.py --arch=amd64
```

Each guest uses disposable 64 MiB EXT2 and 16 MiB raw disks. It tests mounted
disk writes, existing descriptors, `mknod` block and misleading character
aliases, symlinks, unknown block nodes, unrelated raw writes at level 1, and
all raw writes at level 2. It exercises denied splice and file-range copies
with preserved input and offsets, then measures 6,000 denials after warmup.
After the guest syncs, the runner checks the real EXT2 image with `e2fsck -f -n`
and extracts the filesystem's 64 KiB writeback payload with `debugfs` to verify
every byte persisted.

ARM also mounts the existing `qemu-persist` template with a misleading source
path: the actual backing disk remains protected while the named unrelated
disk remains writable. AMD exercises real partition resources with distinct
`rdev` values, including a whole-extent alias of the mounted root. Its spare
disk occupies the final AHCI port.

The host sanitizer fixture compiles the unchanged production V identity and
policy modules. It checks overlapping and disjoint extents, unknown identities,
character aliases, a write/mount interleaving, failed-mount cancellation and
inventory growth while a token is held. The generated-C checker inspects the
actual production dispatch and token bodies for per-call allocations and
transfer guard ordering, then runs their exact geometry helpers under ASan
and UBSan. On AMD it also validates emitted AHCI register sizes and offsets,
all 32 `CAP.NP` and `CAP.NCS` encodings, actual final-slot selection for
controllers with 1 through 32 slots, and partition overflow boundaries.

## AHCI enumeration correction

The two-disk guest exposed existing AHCI enumeration bugs: a 156-byte port
register structure used the wrong stride after port zero, and the zero-based
`CAP.NP` value excluded the last port. `CAP.NCS` similarly excluded the last
command slot and rejected controllers with only one slot. The port structure
is now 128 bytes with four vendor words at offset `0x70`; both capability
counts now include their last entry. These match OpenBSD-current's
`AHCI_PORT_SIZE`, `AHCI_REG_CAP_NP` and `AHCI_REG_CAP_NCS` in
[`sys/dev/ic/ahcireg.h`](https://cvsweb.openbsd.org/src/sys/dev/ic/ahcireg.h?rev=HEAD).

## Recorded validation

Both tracked production builds pass. The host policy fixture and exact
generated-C checks pass under ASan/UBSan. Both real two-disk guests pass all
assertions, verify the persisted 64 KiB payload, and finish with a clean EXT2
check. After 6,000 denied calls, Slab remains 1584 KiB on ARM and 1188 KiB on
AMD. AMD now publishes both `/dev/sd0` and `/dev/sd1`, including their real
partition resources; before the layout/count correction it published only
the first disk.

The allocation-site audit reports 353 ARM and 245 AMD sites. Its existing
allowance file still fails in the same 157 baseline groups, with no new
identity, policy or transfer allocation categories; allowances are unchanged.
The audit's AMD compiler invocation still exits 1 on the known unrelated DRM
module issue while producing its allocation report. Production builds pass.

## Limits

The inventory and mounted protections live for the device registry's lifetime;
there is no device-removal or post-unmount revocation protocol. Native Apple
ANS devices do not yet report a physical identity, so their raw block writes
are conservatively prohibited at level 1 while internal filesystem operations
remain available. QEMU exercises VirtIO and AHCI; no live hardware or NVMe
guest coverage is claimed. This change covers mounted-disk policy, rather
than complete OpenBSD securelevel equivalence.
