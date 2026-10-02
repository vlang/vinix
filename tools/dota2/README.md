# Existing game data as a read-only Vinix disk

`ext2_export.py` presents a host directory as a valid ext2 block device over
loopback TCP NBD. It writes only filesystem metadata and indirect block
pointers; regular file payloads are read from their original host paths when
QEMU requests them. A 72 GiB Dota 2 installation needs about 116 MiB of stored
metadata. The large apparent `metadata.ext2` size is sparse and must not be
copied with a tool that materializes holes.

Build a fresh export, optionally merging a Linux depot over the existing game:

```sh
python3 tools/dota2/ext2_export.py build \
  "$HOME/Library/Application Support/Steam/steamapps/common/dota 2 beta" \
  --overlay build/dota2/steamcmd/steamapps/content/app_570/depot_373306 \
  --state build/dota2/linux-export
python3 tools/dota2/ext2_export.py serve \
  --state build/dota2/linux-export --port 10809
```

Overlay directories use the same layout as the original root: for example,
`game/bin/linuxsteamrt64/`. Later overlays replace matching files and merge
matching directories. No source file is modified. The source must stay
installed and unchanged while serving; changed or truncated files fail reads
instead of silently providing mixed versions. Rebuild into a fresh state
directory after any game update. Individual files larger than 4 GiB are refused
because Vinix's ext2 inode read path still uses its 32-bit size field.

Attach the server to QEMU:

```sh
-drive if=none,id=dota-data,file=nbd://127.0.0.1:10809/,format=raw,readonly=on \
-device virtio-blk-device,drive=dota-data
```

Vinix's current QEMU persistence path can mount the export at `/root` if it is
the sole readable ext2 disk and `vinix.qemu_persist=1` is in the kernel command
line. `run-aarch64.sh` requires a local persistent filename; the test runner
supplies an unformatted 16 MiB sparse dummy disk to enable that command line,
then attaches the NBD device using `VINIX_QEMU_EXTRA`. The kernel skips the
dummy disk and mounts the exported one. Remount `/root` read-only before
starting an application and put its writable home/config elsewhere.

Validate the layout and protocol with:

```sh
python3 tests/dota2/export-test.py -v
python3 tests/dota2/export-run.py \
  --source "$HOME/Library/Application Support/Steam/steamapps/common/dota 2 beta" \
  --export-state build/dota2/linux-export \
  --state-dir build/dota2/export-proof
```

The host tests use `e2fsck`, `debugfs`, and the real QEMU NBD client to check
block addressing, overlays, symlinks, EOF padding, write rejection and source
changes. The native AArch64 guest test compares actual VPK byte ranges through
both `pread` and `mmap`, crosses direct/single/double-indirect boundaries, and
checks that the read-only mount rejects writes. It needs an existing AArch64
kernel and musl sysroot; it creates private boot state and leaves existing VM
disks untouched.
