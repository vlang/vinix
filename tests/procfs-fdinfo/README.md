# /proc/<pid>/fdinfo

A static guest init for `tests/kernel-gaps/run-native`:

```sh
tests/kernel-gaps/run-native --source tests/procfs-fdinfo/test.c \
  --kernel-dir kernel --arch aarch64 --expect 'VINIX PROCFS FDINFO: PASS'
```

Repeat with `--arch x86_64` after an x86-64 build. Without a checkout-local
`build-aarch64-userland/sysroot`, point `VINIX_AARCH64_SYSROOT` at an AArch64
musl sysroot.

For a file it checks Linux's four generic lines: the offset, the flags in octal
(the access mode with `O_CLOEXEC` and `O_LARGEFILE`, without the open-time
flags), the mount and the inode. It checks that a duplicate shares the offset
but not close-on-exec, that `F_SETFD` shows, that the directory lists open
descriptors, that a closed one has no entry and that an entry opened before
the close reads as `ENOENT`, and that one open file reads one snapshot, a byte
at a time as at once. For `/dev/dri/card0` it checks
the `drm-driver` and `drm-client-id` lines: stable for one description, shared
by its duplicates, different for each open and never reused, and absent for an
`O_PATH` descriptor. The QEMU guests have no AGX device, so the memory lines are
covered by the host tests.

It then reads `/proc/slabinfo` around 200 cycles each of fdinfo reads,
listings and DRM fdinfo reads, and of entries made and pruned, and requires
every heap size class to stay flat. Opening a DRM file is measured alone so that
only what fdinfo adds is charged. Pruned entries are freed after the five-second
removed-node grace period, so that phase waits eight seconds before measuring,
and warms up for as long as it measures so the removed-node queue has already
grown to its high-water mark.
