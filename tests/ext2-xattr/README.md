# Extended attributes on ext2

`kernel/fs/ext2/xattr.v` stores attributes in the ext2 external attribute
block addressed by `i_file_acl`. The namespace indexes, sorted entries,
alignment, reference counts and hashes follow the [Linux ext2 format](https://github.com/torvalds/linux/blob/master/fs/ext2/xattr.h).
Linux-created shared attribute blocks are copied before mutation; removing
the last attribute or deleting its inode releases the block. Short symlinks
remain readable when their sector count includes an attribute block.

The syscall layer supports `user.*`, `trusted.*` and `security.*` on tmpfs
and ext2. User attributes require file permissions and apply only to regular
files/directories, with owner checks on sticky directories. Trusted attributes
require `CAP_SYS_ADMIN` and disappear from unprivileged reads/listings.
Security writes require `CAP_SYS_ADMIN`, or `CAP_SETFCAP` for
`security.capability`. These stores do not implement a security policy engine
or interpret capability payloads. Unsupported `system.*` names remain rejected;
POSIX ACL enforcement is a separate feature.

ext2 values and descriptors together must fit in one filesystem block;
oversized updates return `ENOSPC` without replacing the previous value.
Filesystem blocks from 1 KiB through 64 KiB are handled. Attributes participate
in the common metadata cache and `fsync`/shutdown flush. ext2 has no journal:
this does not add atomic recovery from interrupted multi-block metadata writes.
An ambiguous inode-publication error quarantines a new block instead of
reusing space that a published inode pointer might still address.

Run the production codec and I/O fault tests on the host:

```sh
V=/path/to/v VEXE=/path/to/v python3 tests/ext2-xattr/host.py
```

Build the ARM64 kernel, then run the native test with an existing musl sysroot:

```sh
VEXE=/path/to/v make -C kernel -j4 CC=clang V=/path/to/v ARCH=aarch64 LIMINE_MP=1
python3 tests/ext2-xattr/run.py
```

The guest checks binary and empty values, create/replace/remove flags, size
queries, listings, namespace permissions, maximum names, capacity failures,
and retained heap objects over 200 iterations on both backends. A second
thread removes and reinserts lower-layer attributes while overlay copy-up
copies their names and values into 64 upper-layer files. It then
restarts itself and checks persisted attributes and a short symlink. After
QEMU exits, `e2fsck -fn` must pass and `debugfs` must read the attributes.
The retained-object check permits at most two transient objects per class;
an allocation retained once per operation exceeds this tolerance. All raw
deltas are printed, including overhead from reading `/proc/slabinfo` itself.
`--state-dir` keeps the disk and serial log for inspection and requires a
fresh disk to prevent a previous marker from skipping the initial checks.
