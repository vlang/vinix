# Omarchy's packaged Mesa on Vinix

Omarchy ships its Mesa prebuilt (`mesa-aurora` and `vulkan-aurora`, built from
`omacom/mesa` `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`) for Arch Linux ARM.
These tools run that Mesa, unmodified, on Vinix in QEMU. Nothing is built from
source, so no meson is needed.

## Staging the root

```
v run tests/omarchy-mesa/stage.v --state NEW_DIR [--cache DIR]
```

This reads Omarchy's aarch64 edge repository and Arch Linux ARM's `core`,
`extra` and `alarm` repositories, and resolves the dependencies of
`filesystem`, `mesa-aurora`, `vulkan-aurora`, `libdrm`, `mesa-utils` and
`vulkan-tools` the way pacman would. `pacmandb/` reads the sync databases,
including the older layout with a separate `depends` file, and compares
versions as libalpm does. Every package is checked against its database's size
and SHA-256, then extracted into `NEW_DIR/root`.
`NEW_DIR/manifest.tsv` lists what was chosen and `NEW_DIR/db/SHA256SUMS` lists
the databases it came from. A `--cache` directory supplies packages already
downloaded, if their checksums match.

Arch Linux ARM moves on, so a later run may choose newer packages than the
manifest of an earlier one. The default mirror is
`https://de3.mirror.archlinuxarm.org`: the HTTPS certificate of
`mirror.archlinuxarm.org` does not match its name, and some networks refuse
plain HTTP.

The root differs from a pacman installation in three ways:

- Package install scripts are not run, so there is no `ld.so.cache`.
- Documentation, terminfo and the netfilter headers are left out. Some of
  their paths differ only in case, which a macOS volume cannot hold. Any other
  such pair stops the staging.
- Files that extraction as an ordinary user left unreadable to their owner are
  made readable, so that mke2fs can copy them; `NEW_DIR/made-readable.txt`
  lists them (dbus's setuid helper).

## Running it in QEMU

```
VINIX_AARCH64_SYSROOT=... tests/omarchy-mesa/run --kernel-dir KERNEL \
    --root NEW_DIR/root --state ANOTHER_NEW_DIR [--timeout SECONDS]
```

The runner (`tests/native-guest-tools/omarchy-mesa-main.v`) writes the root to
an ext2 image with the features of the QEMU data disks, attaches it read-only,
and boots `guest.c` as init with 3 GiB of memory. The init mounts the disk,
mounts `/proc`, `/sys`, `/dev` and two tmpfs inside it, and chroots there. It
then checks that:

- every library of the Gallium and Honeykrisp drivers, of the EGL vendor
  library and of `vulkaninfo`, `eglinfo` and `peglgears` resolves
  (`ld.so --list`);
- the Vulkan loader loads Honeykrisp and creates an instance, and Honeykrisp
  finds no GPU, since QEMU has none;
- `eglinfo` gets GL 4.6 and GLES 3.2 contexts from llvmpipe with LLVM 23, and
  the version string names the pinned Mesa commit;
- the EGL device platform lists only the software device. libdrm lists only
  DRM devices with a parent, and QEMU's framebuffer has none;
- `peglgears` draws frames.

It prints `OMARCHY-MESA PASS`, or `OMARCHY-MESA INCOMPLETE problems=N`.
Without an Apple GPU, the Asahi Gallium driver and Honeykrisp only load. Their
submissions need the M1.
