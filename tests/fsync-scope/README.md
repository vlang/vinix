# Descriptor-scoped fsync

The native ARM fixture dirties an ext2 file backed by a QEMU NBD disk that
advertises writable storage but rejects every WRITE. Its fsync, fdatasync and
syncfs must return EIO, and its dirty data
must remain readable. The failure must not affect fsync or fdatasync on an
unrelated tmpfs file, including read-only and directory descriptors. Invalid,
O_PATH and pipe descriptors retain their existing error behavior.

Build an isolated ARM kernel with `LIMINE_MP=1`, then run:

```sh
VINIX_PRUNE_BUILD=0 python3 tests/fsync-scope/run.py \
  --kernel-dir=/path/to/isolated/kernel \
  --runner-root=/path/to/vinix \
  --work=/path/to/vinix/build/fsync-new
```

Use a fresh `--work` directory for each run. The runner needs the ARM musl
sysroot under the runner root, or `VINIX_AARCH64_SYSROOT`, and the existing
QEMU runner dependencies. It captures `serial.log` and `results.json`, which
record the kernel and native fixture hashes and verify the exported host file
is unchanged. The host file stays read-only. Only this test's NBD negotiation
omits READ_ONLY, allowing ext2 to cache dirty data before the device error.
The disk contains only a generated fixture; no physical storage is accessed.

The kernel before the fix passes the initial tmpfs sync, then returns EIO for
the unrelated tmpfs descriptor after the disk failure. A fixed kernel prints
`FSYNC-SCOPE PASS` after completing every check.
