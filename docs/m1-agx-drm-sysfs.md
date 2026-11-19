# DRM devices in sysfs

Linux gives every DRM minor a directory under its parent device, with
`/sys/class/drm/<name>` and `/sys/dev/char/226:<minor>` linking to it.
libdrm's `drmGetDevices2()` and `drmGetDevice2()` find GPUs this way, and so
does the Mesa that Omarchy packages, unpatched. Vinix had no such entries, so
its Mesa carries a patch that names `/dev/dri/renderD128` directly.

The DRM core now publishes them when a device registers and removes them when
it unregisters. Both run with no DRM lock held, since sysfs calls may sleep.

## What each minor gets

```
/sys/devices/platform/soc/206400000.gpu/drm/card1/
    dev        226:1
    uevent     MAJOR=226 MINOR=1 DEVNAME=dri/card1 DEVTYPE=drm_minor
    device     -> ../../../206400000.gpu
    subsystem  -> ../../../../../../class/drm
/sys/class/drm/card1    -> ../../devices/platform/soc/206400000.gpu/drm/card1
/sys/dev/char/226:1     -> ../../devices/platform/soc/206400000.gpu/drm/card1
```

The render node gets the same, as `renderD129` and `226:129`. The links are
relative and written as Linux writes them.

## The M1 GPU's device

A driver names its device's directory in `DrmDriver.sysfs_parent` and
publishes that directory's own files. The AGX driver does so on base M1:
`devices/platform/soc/206400000.gpu`, named as Linux names the platform device
of the device-tree node `gpu@206400000`. The unit address is the node's first
register range, the ASC, not the SGX range the driver maps; the first version of
the `agx_stats` directory used the SGX base and would have been
`204000000.gpu`. Vinix builds the name from the ASC base whichever device tree
it booted with.

Beside `agx_stats` and `gpu_memory` the directory has what libdrm reads:

```
uevent     DRIVER=asahi
           OF_NAME=gpu
           OF_FULLNAME=/soc/gpu@206400000
           OF_COMPATIBLE_0=apple,agx-t8103
           OF_COMPATIBLE_1=apple,agx-g13g
           OF_COMPATIBLE_N=2
           MODALIAS=of:NgpuT(null)Capple,agx-t8103Capple,agx-g13g
modalias   of:NgpuT(null)Capple,agx-t8103Capple,agx-g13g
subsystem  -> ../../../../bus/platform
```

So on M1, libdrm reports the GPU as a platform device with Linux's bus info and
compatible strings. Vinix's own Mesa still names the render node directly.

## DRM debugfs

Linux's DRM core also gives every device a debugfs directory, named after its
parent device (`dev->unique`), with a link to it per minor. Drivers add their
debug files there. Vinix has no debugfs filesystem, so the core publishes that
part of it in /sys, at the path where Linux mounts debugfs:

```
/sys/kernel/debug/dri/206400000.gpu/
    asahi_stats    added by the AGX driver; root-only
/sys/kernel/debug/dri/0    -> 206400000.gpu
/sys/kernel/debug/dri/128  -> 206400000.gpu
```

`drm.debugfs_add_file()` is Linux's `drm_debugfs_add_file()`: a read-only
file whose text a callback makes on each read. The core removes the directory,
its files and the links when the device unregisters, before it releases the
card number. Removal waits for any read still running, so the callback's data
need only last until then. Adding a file does not synchronize with
unregistering, so a driver adds its files during its own registration. A
device with no parent gets no directory, and adding a file to it fails. So
does a second device whose parent has a name already taken there, as Linux's
`debugfs_create_dir()` refuses it. Unlike debugfs, these directories can be
listed by anyone; the files in them are root-only. On the M1 the GPU's file is `asahi_stats`
([raw statistics](m1-agx-stats.md#raw-statistics-in-debugfs)).

## QEMU's VirGL GPU

QEMU's virtio-gpu on the VirtIO-MMIO transport now has Linux's place too. On
Linux its DRM device's parent is the virtio device, inside the platform device
of the device-tree node `virtio_mmio@<address>`:

```
/sys/devices/platform/a003e00.virtio_mmio/
    uevent     DRIVER=virtio-mmio, OF_FULLNAME=/virtio_mmio@a003e00,
               OF_COMPATIBLE_0=virtio,mmio, MODALIAS=of:Nvirtio_mmioT(null)Cvirtio,mmio
    subsystem  -> ../../../bus/platform
    virtio31/
        uevent     DRIVER=virtio_gpu, MODALIAS=virtio:d00000010v554D4551
        subsystem  -> ../../../../bus/virtio
        drm/card0, drm/renderD128
```

libdrm 2.4.123's `drmParseSubsystemType()` reads the node's bus from the
virtio device. Finding `virtio` there, it takes the bus of the device's
parent, so it lists the node as a platform device. It names the device from
the virtio device's `MODALIAS`, since there is no OF data there. Mesa 26.3
lists render nodes only through libdrm, so without these entries it would not
find the VirGL node. Linux numbers virtio devices in the order it finds them;
Vinix names the device after its MMIO slot, which nothing reads. A
virtio-gpu on PCI still gets no parent.

`tests/drm-sysfs` publishes such a device and walks it with a port of
libdrm's rule, read from its source. A link one level short, or a uevent
without `MODALIAS`, fails the test. QEMU here has no VirGL device, so the
driver's registration with these entries has not run in a guest.

## Devices without a parent

The QEMU framebuffer and any other driver that names no parent get Linux's
`devices/virtual/drm/<name>`, with no `device` link. libdrm requires
`device/drm` before it lists a node, so it lists them no more than it did
before. Their class and `dev/char` entries, `dev` and `uevent` are there for
anything that reads them directly.

## Validation

- `tests/drm-sysfs/run.v` builds the production publisher against a
  recording `/sys` with the semantics of `sysfs_dynamic.v`, and the AGX
  parent's identity from the production source. A V port of libdrm's lookups
  then walks the result: `drmNodeIsDRM`, the bus from the `subsystem` link,
  `DEVNAME`, `OF_FULLNAME` and the compatibles, which must match the node name,
  unit address and compatible list read from the pinned `t8103.dtsi`. It also
  requires that `driver.v` names the device from the ASC base. Mutants with a
  link one level short, a wrong `device` link, a `dev/char` link left after
  unregister, no compatible count, or the SGX base fail it.
- `tests/drm-sysfs/guest.c` boots both architectures in QEMU and checks every
  `/dev/dri` node's class and `dev/char` links, `dev`, `uevent` and
  `subsystem`, and that libdrm's node check still rejects them.
- `tests/drm-wire` checks that registration publishes once, outside the device
  lock, and only after it succeeds, and that unregistering removes once. A G13
  contract now requires that order.
- An independent lifetime review found no double free, freed literal or
  use-after-free. It found that the paths the publisher builds were never freed,
  now fixed, and that the AGX shutdown removed the device directory, minors
  included, before unregistering the DRM device; the DRM device now goes first,
  so each owner removes its own entries. It also found that a device
  registering while another's entries were being removed could take the same
  card number and lose its entries to that removal. Unregistering now keeps the
  number taken until the entries are gone; `tests/drm-wire` registers a device
  from inside the removal and fails if it gets the retiring number, as the
  earlier order does. One race remains that no caller can reach, since devices
  are handed out only after registration returns: an unregister racing the
  publication would not see the parent path. Evidence for that change:
  `~/.local/state/vinix/omarchy-m1-drm-slot-20261119/bundle.tar.gz`, SHA-256
  `3ec565cda253b095d4ef12e0634e446f12287f533243af05d2e8d65366239714`. The AGX driver's
  parent path string lives as long as its driver definition, which is never
  freed.
- The fdinfo guest test, the AGX stats, failure and async suites, 79 contract
  test files and 122 pinned reference checks pass. Both `PROD` kernels build,
  the allocation scan is unchanged, and the AArch64 kernel boots in QEMU. The
  M1 GPU's own entries were checked on the host only; QEMU has no AGX device.
- The DRM debugfs directory is validated with the raw statistics it was added
  for ([validation](m1-agx-stats.md#validation-of-asahi_stats)); evidence
  under `/Users/alex/.local/state/vinix/omarchy-m1-asahi-stats-20261119/`.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-drm-sysfs-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `54f63eb009f6982889c0cd81fb0687c08caaa25889493088711ed3c963cf93ee` |
| `bundle.tar.gz` inventory | `4d778aa287627199b9a49b6eaf3eb0ffd154f0bda917a2036103e7eba7a808d4` |
