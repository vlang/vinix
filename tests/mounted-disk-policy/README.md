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

The maintained native guest is V in `diskfixture/core.v`. Its declaration-only
header checks the native directory, device-stat, filesystem-stat, transfer-vector
and scalar layouts. The original 176-line C guest is frozen at
`e51f3fc0ff792d1465ac3f06440663215d14433a` (blob
`bd3a12b132b9dff5527f59c8cdbb3cb9cb1994e5`). Independent comparisons can pass
that Git blob's contents with `--source=/absolute/original-guest.c`.
`--state-dir=/absolute/new-state` retains the actual guest ELF, disk images,
compiler inputs, EXT2-tool logs and complete payload. The state must be fresh.
`--kernel-dir=/absolute/worktree/kernel` copies an existing matching kernel
immutably and disables rebuilding it during the guest run. Without this option,
the existing environment and build behavior apply.

V retains all 72 original source checks: 70 compile on ARM and 64 on AMD.
Failure messages preserve each native line number and C expression. The native
directory entry stays borrowed until the next `readdir`; transfer vectors,
offset outparameters and pipe descriptors remain stack values borrowed by
synchronous libc calls. The permanent 512-byte buffers use static storage.
No V allocator is imported by the native fixture object. The 50 warmup batches,
6,000 measured denials, `after <= old + 16` slab assertion, all source-consumption
and offset checks, 128 writeback operations and original 300-second guest
allowance remain unchanged. `host.py` and `check-generated.py` remain independent
production-policy checks; their embedded C fixtures are a separate migration
scope.

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

The 2026-10-07 guest C-to-V migration passed strict native SDK builds and four
complete QEMU TCG controls: the frozen C guest and maintained V replacement
on each architecture. After all 6,000 denials, each ARM control retained
1584 -> 1584 KiB of Slab and each AMD control retained 1168 -> 1168 KiB. All
four guests reached every policy/writeback marker and `SECUREDISK DONE` with
the original assertions and 300-second allowance, passed `e2fsck -f -n`, and
persisted the identical 65,536-byte `0x59` payload (SHA256
`fe6eacdc96297d25999ecef8aed549094a25a6baa699a0b60cdc5fba75ce5291`).

The actual V guest ELFs match the independently reviewed native SDK artifacts:
ARM `62d6ac59ade22e22f2e87de2c0439981e0a31b9041623ba01a1e0e0fccfaca1d`
and AMD `22495c2a592dcb341e9a34285d18da7735ab2e088acf1a47a1b7fa2b5e1abb26`.
The source, native layout and lifetime review covered all original checks,
stack borrows and descriptor closure order. The unchanged host policy and
generated geometry checks passed ASan/UBSan; leak sanitizer was disabled.

These guest controls reused previously qualified immutable kernels with
unchanged tracked kernel source: ARM SHA256
`05ce36f10282f9ed7263d560fc60b5a4b057e3fdf0158fb07d3fa41a27f048ed`
and AMD SHA256
`b871254e8493566beb5b2e4436a06765a05db7d0f8fae561bb448d135f9c4199`.
This fixture stage made no kernel change and claims no fresh kernel build.
The native guests themselves were not instrumented with sanitizers.

## Limits

The inventory and mounted protections live for the device registry's lifetime;
there is no device-removal or post-unmount revocation protocol. Native Apple
ANS devices do not yet report a physical identity, so their raw block writes
are conservatively prohibited at level 1 while internal filesystem operations
remain available. QEMU exercises VirtIO and AHCI; no live hardware or NVMe
guest coverage is claimed. This change covers mounted-disk policy, rather
than complete OpenBSD securelevel equivalence.
