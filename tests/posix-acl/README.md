# POSIX ACL checks

Vinix exposes Linux version-2 `system.posix_acl_access` and
`system.posix_acl_default` attributes on tmpfs and ext2 regular files and
directories. ext2 converts them to its version-1 format: named entries occupy
eight bytes, object/mask entries four. ACL namespace entries use an empty
on-disk name and ext2 namespace indices 2 and 3.

Named user and group entries must be canonical, sorted, and unique. Named
entries require a mask. Owner access bypasses the mask; a matching named user
or group that cannot grant the request cannot fall through to `other`. Matching
group grants are evaluated individually rather than combined. Ordinary mode
checks, real/effective credentials, and capability overrides retain their
existing semantics. Invalid stored ACLs and inconsistent ACL/mode pairs return
EIO even when the caller holds CAP_DAC_OVERRIDE.

Setting an access ACL updates the corresponding mode bits. A minimal ACL is
represented by mode bits alone. chmod adjusts owner, mask (or owning group when
no mask exists), and other permissions while preserving named permissions.
Nonmembers of the owning group without CAP_FSETID lose the setgid bit when
setting an access ACL or changing mode. Internal inheritance/copy operations
preserve inherited setgid. Userspace xattr flags are validated; as in Linux,
valid CREATE/REPLACE flags do not impose existence checks on POSIX ACLs.
Removing an absent ACL succeeds, including a default ACL on a regular file.

When a directory has a default ACL, newly created regular files and directories
inherit it, intersecting access permissions with the original requested mode.
Umask applies when there is no default ACL. Child directories also retain a
copy of the default ACL. Symlinks reject ACLs and do not inherit them. ext2
publishes a changed access ACL and mode together through a private EA block and
one inode update; permission checks snapshot ACL/mode/ownership under the same
backend lock. Creation failures remove the partial inode before publishing its
VFS name.

These ACLs do not implement XNU's richer authorization model. Named FIFOs and
mknod device aliases currently use separate Resource backends and do not have
persistent ACL support. ext2 EA capacity is one filesystem block per inode;
large inherited access/default pairs can return ENOSPC. ext2 has no journal:
the transaction avoids mixed ACL/mode publications during normal operation,
and quarantines storage after ambiguous write errors, but does not promise
power-loss atomicity for allocator metadata.

Run host codec, malformed-format, COW, and publication-error tests:

```sh
V=/Users/alex/code/v/v python3 tests/ext2-xattr/host.py
```

Build ARM and run the native permission, inheritance, chmod, capability,
read-only/immutable, concurrency, malformed-disk, rollback, allocation, and
actual reboot checks:

```sh
VEXE=/Users/alex/code/v/v make -C kernel -j4 CC=clang V=/Users/alex/code/v/v ARCH=aarch64 LIMINE_MP=1
VEXE=/Users/alex/code/v/v V=/Users/alex/code/v/v python3 tests/ext2-xattr/run.py \
  --source tests/posix-acl/test.c --acl-fixture --state-dir /tmp/vinix-acl-fresh
```

For named allocation sites, rebuild with `ALLOC_TRACK=1`, run the same native
suite, and pass its serial log to `tests/kernel-allocs/sites.py` with the exact
kernel binary. `PERF-ACL` measures 200 repeated set/get/access/chmod/remove
cycles after warmup. `PERF-ACL-FAILURE` measures 200 repeated failed directory
creations after warmup and node retirement. Both require exactly zero change
in every slab class and in large-allocation pages. No class is exempt. The
kernel must include the committed proc observer and background random reseed
lifetime fixes so the measurement itself and unrelated periodic work retain
nothing. Raw per-class deltas remain in the serial transcript.

The runner saves the exact booted ELF, generated C and source/test hashes in
its fresh state directory. It checks the ELF architecture and boots its saved
copy so an architecture rebuild cannot alter the tested image.
The integration runner also supports `--arch=x86_64 --kernel-dir=...`;
use its ACL fixture option with the matching ACL source. Build each architecture
separately before running it. The runner verifies reboot persistence and runs
`e2fsck -fn` for both.

Implementation references: [Linux POSIX ACL rules](https://github.com/torvalds/linux/blob/master/fs/posix_acl.c),
[ext2 ACL conversion](https://github.com/torvalds/linux/blob/master/fs/ext2/acl.c),
and [userspace xattr dispatch](https://github.com/torvalds/linux/blob/master/fs/xattr.c).
