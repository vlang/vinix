# DRM devices in sysfs

```sh
v run tests/drm-sysfs/run.v --asahi-linux PATH
tests/kernel-gaps/run-native --source tests/drm-sysfs/guest.c \
  --kernel-dir kernel --arch aarch64 --expect 'VINIX DRM SYSFS: PASS'
```

`run.v` builds `kernel/drm/sysfs.v` and the AGX parent's identity from
`kernel/gpu/agx/driver/sysfs.v` against `fakefs.v`, a recording `/sys` with
the semantics of `kernel/fs/sysfs_dynamic.v`, under address/undefined-behavior
sanitizers. `check.v` publishes the M1 GPU's card and render minors and a
parentless device, then walks the tree with a V port of libdrm's
`drmNodeIsDRM`, `drmParseSubsystemType`, `drmGetDeviceNameFromFd2` and OF bus
and device parsing. The expected node name, unit address and compatibles come
from the pinned `t8103.dtsi`. It also requires that `driver.v` names the device
from the ASC base. It then checks Linux's DRM debugfs directory in
`kernel/debug/dri`: the directory named after the parent, a link per minor, a
root-only driver file read through either link, none for the parentless device,
and removal at unregister. `DRM_SYSFS_SOURCE`, `AGX_SYSFS_SOURCE` and
`AGX_DRIVER_SOURCE` select other sources, for negative controls.

`guest.c` runs on both architectures and checks every `/dev/dri` node's class
and `dev/char` links, `dev`, `uevent` and `subsystem` in the real kernel, and
that libdrm's node check still rejects devices with no parent, which have no
debugfs entry either. Without a checkout-local AArch64 sysroot, set
`VINIX_AARCH64_SYSROOT`.
