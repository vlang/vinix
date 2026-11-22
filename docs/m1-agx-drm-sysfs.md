# DRM devices in sysfs

Linux gives every DRM minor a directory under its parent device, with
`/sys/class/drm/<name>` and `/sys/dev/char/226:<minor>` linking to it.
libdrm's `drmGetDevices2()` and `drmGetDevice2()` find GPUs this way, and so
does the Mesa that Omarchy packages, unpatched. Vinix had no such entries, so
its Mesa carries a patch that names `/dev/dri/renderD128` directly.

The DRM core now publishes them when a device registers and removes them when
it unregisters. Both run with no DRM lock held, since sysfs calls may sleep.

## DRM class version

`/sys/class/drm/version` is a read-only class attribute with the line
`drm 1.1.0 20060810`, followed by a newline. Sysfs creates it with the
initial tree, so it remains available when individual devices unregister.
[Pinned Linux DRM class initialization](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_sysfs.c#L132-L158)

Both kernel builds used `-O1` for C compilation. ARM64 and x86-64 QEMU
guests under TCG checked the exact bytes and mode `0444` as root and as
UID and GID 65534. The same ARM64 fixture caught the missing file on the
baseline kernel. The debugfs permission probes, ARM64 DRM discovery and
host DRM sysfs sanitizer fixture passed. Independent lifetime review
confirmed that the static attribute survives minor teardown. The allocation
scan reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `f20722c0ff1288da132a5e72e7ba117f40af9f32` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-class-version-20261122.HdTE5b/`.
The `bundle.tar.gz` SHA-256 is
`b7a4f4c690dc642afd14343ee78af18ac6da976aeaf805efea6e162b04593a04`.

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

### Platform bus discovery

`/sys/bus/platform/devices/206400000.gpu` links to
`../../../devices/platform/soc/206400000.gpu`. Software walking the
platform bus can follow that link to the GPU's attributes and DRM minors.
AGX records it only after successful creation and removes it during
shutdown. [Pinned Linux bus device publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/base/bus.c#L583-L595)

The DRM sysfs sanitizer fixture found `renderD129` through the bus
link. It tested collisions at six paths and verified that an occupied bus
entry and a sibling device survived teardown. Two controls caught an
incorrect relative target and deletion of an occupied entry. Independent
lifetime review confirmed that AGX releases the temporary target after
sysfs copies it and retains the successfully published path through teardown.

Both kernel builds used `-O1` for C compilation. The ARM64 DRM discovery
and x86-64 debugfs permission probes passed in QEMU under TCG. The allocation
scan reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `69a3ff55b60d148d5995914f6b17a22f82985335` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-agx-platform-bus-20261122.31dFCc/`.
The `bundle.tar.gz` SHA-256 is
`ac6e418b19e4d8182c7683df7cc77e96f82a212916f3ba3d13124e81bd1956cb`.

### Platform driver binding

The GPU's `driver` link resolves to `/sys/bus/platform/drivers/asahi`.
That directory lists `206400000.gpu` as a link back to the platform
device. AGX creates the driver-to-device link first and rolls it back
if the device-to-driver link fails. Shutdown removes successful pairs
while preserving the shared directories. [Pinned Linux driver binding](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/base/dd.c#L483-L525)

The DRM sysfs sanitizer fixture resolved both links and found the render
node through the driver directory. Nine collision cases covered the
driver directory, both links and the existing AGX entries. Three controls
caught missing rollback, publication after a reverse-link collision and
an incorrect relative target. Independent review confirmed the link
ownership and cleanup order.

Both kernel builds used `-O1` for C compilation. The ARM64 DRM discovery
and x86-64 debugfs permission probes passed in QEMU under TCG. The allocation
scan reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `2223fc6c18a63048a7cf5e3f328b65132d02ae1c` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-agx-driver-binding-20261122.rf6PeC/`.
The `bundle.tar.gz` SHA-256 is
`b911210fd893f76656720c953e7f7f4526fea02c9149c8467275479d428f1914`.

## DRM debugfs

Linux's DRM core also gives every device a debugfs directory, named after its
parent device (`dev->unique`), with a link to it per minor. Drivers add their
debug files there. Vinix has no debugfs filesystem, so the core publishes that
part of it in /sys, at the path where Linux mounts debugfs:

```
/sys/kernel/debug/dri/206400000.gpu/
    name           asahi dev=206400000.gpu unique=206400000.gpu
    clients        open DRM descriptions, oldest first
    gem_names      empty global GEM name table
    asahi_stats    added by the AGX driver, mode 0444
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
`debugfs_create_dir()` refuses it. The debugfs root has Linux's default mode
`0700`. On the M1 AGX adds `asahi_stats`
([raw statistics](m1-agx-stats.md#raw-statistics-in-debugfs)).

### DRM device name

DRM writes the driver's name and the parent device name to the read-only
`name` file before publishing the numeric links. The parent name supplies
both `dev=` and `unique=`. Sysfs keeps its own copy of the line and
removes it when the device's debugfs directory is removed. [Pinned Linux name formatter](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L54-L73)

The DRM sysfs sanitizer fixture checked the exact lines for Asahi and
VirtIO-MMIO, reads through the card and render links, and removal at
unregister. It also verified that a competing directory receives no file
and a driver cannot replace the core file. Two controls caught a missing
file and publication into a competing directory. Independent lifetime
review confirmed that sysfs retains the cloned text for open readers.

Both kernel builds used `-O1` for C compilation. The ARM64 DRM discovery
and x86-64 class version and debugfs permission probes passed in QEMU
under TCG. The DRM wire sanitizer fixture passed, and the allocation scan
reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `fee483573fd4e84cb9b50b840157236bbf5233cd` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-debugfs-name-20261122.dQB93U/`.
The `bundle.tar.gz` SHA-256 is
`64dbb921db254658c8eec3ce7eaf7ba6a09ad7c73c07f47782abd4c45d27d912`.

### Open clients

The read-only `clients` file shows one row per open DRM data description,
oldest first. Both minor links reach the same table. The minor column records
the node used for each open, and the name and ID match that description's
`fdinfo`. Duplicates and inherited descriptors share the row until the last
reference goes away. Metadata-only opens have no row. [Pinned Linux client listing](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L75-L122)

The initial implementation recorded the group leader's command, kernel TGID,
effective UID and `CAP_SYS_ADMIN` check at open. It kept those values after
the opener exited.

The device list borrows open descriptions until final resource close.
Independent lifetime review and generated C confirmed that readers and
close serialize on the list lock. The initial implementation held that lock
while formatting the rows. Its extra inline fields added 48 bytes on each
architecture and kept the description in the 1536-byte slab class.

The DRM sysfs, wire and fdinfo sanitizer fixtures passed. Both standard
kernels passed the client ID and name checks and the 200-cycle procfs
probe under QEMU TCG. The allocation scan reproduced the 150 baseline
findings. Native M1 validation remains open.

The named-device QEMU fixture passed on ARM64 and x86-64. It sets the simple
DRM driver's parent to `devices/platform/drm-clients-fixture` in isolated
builds. It checks the exact header and rows, 64-byte names, duplicate and
fork retention, rollback on `EMFILE` and removal after final close. The
device's parent override is included in the evidence bundle.

The tested base was `abfff7bdd62d79f80758ba013472825a2a12eb3d` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-clients-20261122.bpIpJS/`.
The `bundle.tar.gz` SHA-256 is
`62776282975bb00176acdae1d56ec99aabf901eb097d1a35af670790760fe61a`.

#### Live opener identity

Each row reads the associated process's current group leader command and
effective UID. It shows `<unknown>` and the mapped root UID after that
process is reaped. A stored process generation prevents a recycled PID from
supplying the previous process's command or UID. The reader's PID namespace
governs TGID, and the debugfs opener's user namespace governs UID.
Authentication records the open-time `CAP_SYS_ADMIN` check, and the master
and magic columns report `n` and `0`. [Pinned Linux client listing](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L75-L122)

The reader copies client rows into temporary storage under the device's
list lock. It releases that lock before looking up processes and formatting
the rows. Independent review and generated code confirmed the snapshot holds
values only and is freed after each read. The open description grew by eight
bytes on both architectures and remains in the 1536-byte slab class.

ARM64 and x86-64 QEMU passed the named-device tests. The opener renamed
itself, changed effective UID and passed its descriptor to another process.
The descriptor kept its row after the opener was reaped, and its final
close removed the row. The same guest rejected the previous kernel's static
identity. Both current guests recorded zero peak live-object growth across
200 reads of a populated table. The DRM sanitizer fixtures and 200-cycle
procfs checks passed. The allocation scan reproduced the 150 baseline
findings. Native M1 validation remains open.

The tested base was `c16eeb48ec72f7d5e4869f6bed72cd64d8011c80` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-live-clients-20261122.aP5F6m/`.
The `bundle.tar.gz` SHA-256 is
`a37d84ebbff5839b8351ae07d9d17fa3d5dda07d20d9dd3996e42ba0a6da22de`.

#### Attribution after descriptor transfer

An open description starts with the opening process. The DRM ioctl path
updates attribution to the caller after request validation and input copy,
before invoking the handler. An input fault preserves the prior association.
A handler error can still change attribution. The client ID, name and
open-time authentication belong to the open description across a transfer.
Linux exempts descriptions that have held DRM master. Vinix currently applies
the update to all DRM data descriptions. [Pinned Linux ioctl dispatch](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L800-L819) and [pinned Linux file ownership](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_file.c#L452-L480)

The handle lock serializes the attribution update with the debugfs snapshot.
The ioctl path releases it before the handler runs. The update uses the
existing scalar identity and requires no allocation or process reference.

ARM64 and x86-64 QEMU verified that a client ID survives SCM_RIGHTS transfer.
An unsupported request and an input copy fault preserved the reaped opener's
row. An oversized client name passed input copy, returned `EINVAL` from
the handler and reassigned the row to the caller. The same ARM64 guest
detected the missing handoff on the preceding kernel. The DRM sanitizer
suites and 200-cycle procfs probes passed. Both guests measured zero slab
growth over 200 populated-table reads, and the allocation scan reproduced
the 150 baseline findings. Native M1 validation remains open.

The tested base was `44f5fc30ec967ed1a41dde86c02f49e9e74943bc` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-handoff-20261122.9gyMnR/`.
The `bundle.tar.gz` SHA-256 is
`b7baa16697d6915a30aba3b0e218c523454db19580380f10501923912a1a2e69`.

#### Ioctl admission errors

The DRM dispatcher returns `ENODEV` for an inactive device before it
validates the request type. On an active device, a foreign type returns
`ENOTTY` and an unknown DRM command returns `EINVAL`. These checks run
before input copy and client attribution. [Pinned Linux DRM ioctl admission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L848-L856)

The sanitizer fixture exercised both request types with the device
active and inactive. The preceding dispatcher failed the active
foreign-type case. A control that checked type first returned
`ENOTTY` for the inactive foreign-type case.

The ARM64 and x86-64 QEMU guests verified both active-device errors
through the ioctl syscall and checked that client attribution stayed
intact. The DRM wire and fdinfo sanitizer suites passed. The allocation
scan reproduced the 150 baseline findings. Native M1 validation remains
open.

The tested base was `81b9da473e6c1a4e4d044c9871b9c30d9643420a` plus the
archived patch. The QEMU build used the simple DRM named-device fixture.
Evidence is stored at `/Users/alex/.local/state/vinix/m1-drm-ioctl-type-20261122.mPaR32/`.
The `bundle.tar.gz` SHA-256 is
`3271c5aae18a49a85f7dd8c4696b01c86c2610e36e47e762d6c62b955906140d`.

#### Private ioctl handler selection

The DRM dispatcher resolves command numbers from `0x40` through `0x9f`
against the current driver's ioctl table. If the driver has no matching
command, dispatch returns `EINVAL` before copying input or attributing
the client to the caller. The VirtIO GPU's handler-only entries still
use their shared legacy layouts. Core command numbers use the core
layouts, including the framebuffer's dumb-buffer operations. [Pinned Linux ioctl table selection](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L856-L872)

The sanitizer fixture checks an unregistered private command, a matching
handler-only entry and a driver entry that collides with core `VERSION`.
The preceding dispatcher returned `EFAULT` for the unregistered
command. Both ARM64 and x86-64 QEMU passed the same probe on the simple DRM
device with valid and faulting pointers. Client attribution stayed intact.
The preceding ARM64 kernel failed the guest regression. The DRM wire and
fdinfo sanitizer suites passed, the allocation scan reproduced the 150
baseline findings, and both guests measured zero slab growth over 200
populated-table reads. Native M1 validation remains open.

The tested base was `4182d642ed6048b60bb8656c595066fcf170da07` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-private-ioctl-20261122.nhTti1/`.
The `bundle.tar.gz` SHA-256 is
`74ed4e31de200ffb85cc46d03c2750735a147ac0c5ee599d7872a7b654774302`.

#### VERSION and GET_CAP request sizes

`VERSION` and `GET_CAP` intersect the request's read and write bits with
the core layout. They zero-extend omitted input, return only the requested
output bytes and echo extra input bytes on read/write requests. The
dispatcher copies back the reply after a handler error. [Pinned Linux ioctl transport](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916)

`VERSION` writes its version numbers first, then reports each string's
required length before attempting the bounded copy. A null string pointer
queries the length. A nested copy fault returns the fields reached so far.
The replies use Vinix's existing driver metadata and capability values.
[Pinned Linux VERSION handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L503-L558)

The sanitizer fixture checks short, one-way and extended requests, null
string pointers, nested copy faults and output on a rejected capability.
The preceding dispatcher rejected the short read-only `VERSION` request.
ARM64 and x86-64 QEMU verified short `VERSION`, short and extended
`GET_CAP`, and the error reply through the public ioctl syscall. The
preceding ARM64 kernel failed this guest probe. The allocation scan
reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `87702361f16e25ad85e8136e871932ac4b0a4856` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-query-wire-20261122.xCuv0t/`.
The `bundle.tar.gz` SHA-256 is
`7c01409bbb5ced512b201e47c52d5f02698f2b9185b448e39f335f96f81d9da0`.

#### Monotonic timestamp capability

`DRM_IOCTL_GET_CAP` returns `1` for `DRM_CAP_TIMESTAMP_MONOTONIC`
(`0x06`) regardless of driver features. This reports Linux's monotonic
timestamp convention. [Pinned Linux GET_CAP handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L234-L255) [Pinned DRM UAPI definition](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L714-L725)

The sanitizer fixture queried the capability across framebuffer and
render-driver configurations, including both timeline feature states.
ARM64 and x86-64 QEMU verified the framebuffer reply through the ioctl
syscall. The preceding handler rejected the capability in the sanitizer
fixture and the preceding ARM64 kernel failed the guest probe. The
allocation scan reproduced the 150 baseline findings. Native M1
validation remains open.

The tested base was `a4f8d1ce9b78a86f4d5496851572880198db21d8` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-monotonic-cap-20261122.uTh7xA/`.
The `bundle.tar.gz` SHA-256 is
`7f0dfd15ce48a0f6cdf39c82beda5600a1a4ed04e02585011db66200f0c90cfc`.

#### GEM_CLOSE request sizes

`GEM_CLOSE` uses the shared extensible write-only ioctl layout. A four-byte
request supplies the handle and zero-fills the omitted padding. An extended
write request reaches the close handler, and any requested read direction
is discarded. [Pinned Linux ioctl transport](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916) [Pinned GEM_CLOSE definition](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L1091-L1104)

The host wire fixture checked sizing and all direction combinations. The
G13 fixture also closed four-byte requests before ABI selection and under
both selected ABIs. ARM64 and x86-64 QEMU closed live framebuffer handles
with short and extended requests, verified that a read-only request left
the handle live, and checked that a repeat close failed. The preceding
ARM64 kernel failed the new probe. The allocation scan reproduced the
150 baseline findings. Native M1 validation remains open.

The tested base was `435390c4a0fe14a93f20a9512cfab830419c11d4` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-close-wire-20261122.0XLmdc/`.
The `bundle.tar.gz` SHA-256 is
`6ccadd6358fde61f748655423e0cf6a3f305faaec5c97cbd327a77aab63679c7`.

#### Syncobj create and destroy request sizes

`SYNCOBJ_CREATE` and `SYNCOBJ_DESTROY` use the shared extensible read/write
ioctl layout. Four-byte requests zero-fill the omitted flags or padding
and copy back only the handle. Extended read/write requests echo their
trailing bytes. The dispatcher also copies back the reply when the handler
returns an error. [Pinned Linux ioctl transport](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916) [Pinned syncobj ioctl definitions](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L1260-L1261)

The sanitizer wire and syncobj suites passed. ARM64 and x86-64 QEMU
created and destroyed live syncobjs with short and extended requests and
verified the error reply from a read-only destroy. The preceding ARM64
kernel rejected the short create. The allocation scan reproduced the
150 baseline findings. Native M1 validation remains open.

The tested base was `58294ee862d5d7633f572317046aa61b1b6d2841` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-syncobj-handle-wire-20261122.6M0Rrz/`.
The `bundle.tar.gz` SHA-256 is
`3c56bbd8d50919c7a1518ab49c8e5c4d0904ea4b61563104d6f6848d123f22ba`.

#### Syncobj reset, signal, query and transfer request sizes

`SYNCOBJ_RESET`, `SYNCOBJ_SIGNAL`, `SYNCOBJ_QUERY`, `SYNCOBJ_TRANSFER`
and `SYNCOBJ_TIMELINE_SIGNAL` use the shared extensible read/write ioctl
layout. The dispatcher zero-fills missing input fields, intersects the
direction bits with the registered layout and preserves extra bytes on
read/write requests. [Pinned Linux ioctl transport](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916) [Pinned syncobj ioctl definitions](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L1264-L1276)

The sanitizer wire fixture checked all direction combinations and the
syncobj suite exercised the production handlers. ARM64 and x86-64 QEMU
verified short SIGNAL, TRANSFER, QUERY and RESET, plus extended
TIMELINE_SIGNAL and QUERY. The probe checked points 7 and 11 after the
updates and zero after reset. The preceding ARM64 kernel rejected the
short SIGNAL. The allocation scan reproduced the 150 baseline findings.
Native M1 validation remains open.

The tested base was `87924d76b022c8397ea074ff186daa4ba679ee7e` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-syncobj-update-wire-20261122.goLXVz/`.
The `bundle.tar.gz` SHA-256 is
`0e5d328de8370c629aa695cfe4b40723ae010d596c3df78e8c57a7549167e307`.

#### PRIME import and export request sizes

`PRIME_HANDLE_TO_FD` and `PRIME_FD_TO_HANDLE` use the shared extensible
read/write ioctl layout. The dispatcher zero-fills input omitted from the
12-byte structure, preserves trailing bytes on extended read/write
requests and bounds output to the caller's encoded size. [Pinned Linux ioctl transport](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916) [Pinned PRIME ioctl definitions](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L1144-L1175)

The sanitizer wire and PRIME tests passed. ARM64 and x86-64 QEMU verified
that a short export reached the missing-handle check. They also verified
extended export, an 11-byte import with a zero-extended fd, and extended
reimport returning the same handle. The preceding ARM64 kernel rejected
the short export at dispatch. The allocation scan reproduced the 150
baseline findings. Native M1 validation remains open.

The tested base was `c80fbfb379d16b235c05695d4044c77019c2e00f` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-prime-wire-20261122.Y0UHMf/`.
The `bundle.tar.gz` SHA-256 is
`792bb421159e426e93d9b554b830653a475213ea2f63221ebbcc754eaf59309b`.

#### Dumb-buffer request sizes

`MODE_CREATE_DUMB`, `MODE_MAP_DUMB` and `MODE_DESTROY_DUMB` use the
shared extensible read/write ioctl layout. The dispatcher zero-fills
omitted fields and bounds the reply to the encoded size. Request and
layout direction bits are intersected, so the earlier write-only
`MODE_DESTROY_DUMB` encoding continues to work. [Pinned Linux ioctl transport](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L874-L916) [Pinned dumb-buffer ioctl definitions](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h#L1246-L1248)

The sanitizer wire fixture passed. ARM64 and x86-64 QEMU verified a
24-byte create, an extended map returning a buffer offset, and both
read/write and write-only destroy. A read-only destroy returned the
handler error and copied back the zero handle. The preceding ARM64
kernel rejected the short create. The allocation scan reproduced the
150 baseline findings. Native M1 validation remains open.

The tested base was `4b61334c4198f8ecab205546bafa3ac05b69406c` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored
at `/Users/alex/.local/state/vinix/m1-drm-dumb-wire-20261122.DxBMLG/`.
The `bundle.tar.gz` SHA-256 is
`722b36f7af384d8981b9340d0d10f90386eece5638400e5df35f5ebbe95aa4fc`.

#### Display capability queries on render-only devices

`GET_CAP` answers PRIME, syncobj, timeline syncobj and monotonic timestamp
queries on render-only devices. Other queries on those devices return
`EOPNOTSUPP` with a zero value. Vinix uses the framebuffer driver's
dumb-buffer feature to admit display queries. The framebuffer reports
dumb-buffer support, preferred depth 32 and shadow preference 0, with
`EINVAL` for unknown capabilities. [Pinned Linux GET_CAP handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L234-L310)

The sanitizer wire fixture verified both device classes and reproduced the
old render-only response against the previous source. The ARM64 QEMU
fixture enabled software Asahi and checked the render-node replies through
the ioctl syscall. Software Asahi took `card0` in that boot. The full
framebuffer fixture ran on x86-64 QEMU and verified the display replies.
The allocation scan reproduced the 150 baseline findings. Native M1
validation remains open.

The tested base was `e7a296f420aa0ef6e9a6ee105bda3c18f3546e33` plus the
archived patch and the simple DRM named-device fixture. The ARM64 build
also used the archived software Asahi fixture patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-render-caps-20261122.QfZefI/`.
The `bundle.tar.gz` SHA-256 is
`d916c46ffa1311010dfcf808c4ed716034da429aafc6f7f9e2b1680dfe502924`.

#### Render-node permissions for dumb buffers

Render nodes return `EACCES` for `MODE_CREATE_DUMB`, `MODE_MAP_DUMB` and
`MODE_DESTROY_DUMB`. The dispatcher checks permissions after copying input
and updating client attribution. It still attempts any requested copy-out,
so a copy fault takes precedence over the permission error. [Pinned Linux permissions](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L611-L631) [Pinned dumb-buffer registrations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L708-L710) [Pinned dispatcher](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L900-L916)

The DRM wire and AGX file-close sanitizer suites passed. ARM64 QEMU
verified all three permission errors and the reply from a denied read-only
map through software Asahi. The preceding ARM64 kernel failed the render
probe. The x86-64 QEMU framebuffer suite verified primary-node create,
map and destroy. The allocation scan reproduced the 150 baseline findings.
Native M1 validation remains open.

The tested base was `c4e40d0c3afa9c3cb4aa2aca62a2081e3a329be0` plus the
archived patch and the simple DRM named-device fixture. The ARM64 build
also used the archived software Asahi fixture patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-dumb-render-20261122.gQe6Yl/`.
The `bundle.tar.gz` SHA-256 is
`130ec49a413bf3229f8c8c00c639b22de665e26ce643692efbb828134a974a59`.

#### Primary-node dumb-buffer error replies

DRM returns `ENOSYS` when a primary node has no handler for a dumb-buffer
operation. Failed create requests clear the handle, pitch and size. Failed
map requests clear the offset. The dispatcher copies the resulting fields
back within the requested size and preserves the input fields and any
trailing bytes. [Pinned Linux dumb-buffer handlers](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_dumb_buffers.c#L196-L303)

The wire sanitizer fixture passed. ARM64 QEMU checked `ENOSYS` on the
software Asahi primary node and `EACCES` on its render node. The x86-64
QEMU framebuffer fixture checked the cleared error outputs and successful
create, map and destroy. Both prior kernels failed the new checks with
byte-identical guest probe executables. The allocation scan reproduced
the 150 baseline findings. Native M1 validation remains open.

The tested base was `e2d849099d527963d05c0bb6672d6b842ee15874` plus the
archived patch and the simple DRM named-device fixture. The ARM64 build
also used the archived software Asahi fixture patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-dumb-errors-20261122.BOpfHN/`.
The `bundle.tar.gz` SHA-256 is
`035f4d8a840cf09fdda7e3d878dee13fd570e0c05535538199e987f5618809dd`.

#### UID mapping across descriptor transfer

Opening `clients` retains the opener's user namespace on its open
description. Reads use that namespace's live UID map, including updates
written after open. Duplication, fork and SCM_RIGHTS share the open
description and its namespace reference. Final close and failed descriptor
publication release the reference. The initial namespace uses the identity
map without a reference. [Pinned Linux seq_user_ns](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/linux/seq_file.h#L248-L256)

Independent review checked that the process-table lock serializes the
open-time pin and UID-map access. The syscall retains the description
through the callback. The added pointer keeps the description in the
1536-byte slab class on both architectures.

The named-device probe passed on ARM64 and x86-64 QEMU. It checks an
initial-namespace open inherited by a child, the overflow UID before its
map is written, and the mapped UID after the write. The child duplicates
and passes its own debugfs descriptor to the initial namespace, where a
read after reap still uses the child's map. The preceding ARM64 kernel
failed the inherited-descriptor check.

The DRM sanitizer suites and 200-cycle procfs probes passed. Both guests
measured zero slab growth over 200 populated-table reads. The allocation
scan reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `4b8f4414bddc77047f49fbfabe35626e40e37842` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-userns-20261122.USqHLX/`.
The `bundle.tar.gz` SHA-256 is
`4a5724bc049046c96b62a60d70139d8b6880a51a8dedc3c01428482662a2be6f`.

#### Signed UID formatting

The UID column formats mapped IDs as signed 32-bit decimal with a minimum
width of five. The formatter widens the signed value before taking its
magnitude, so `2147483648` renders as `-2147483648` and `4294967294`
renders as a right-aligned `-2`. UID mapping retains its full unsigned
range. [Pinned Linux client formatter](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L100-L117)

The ARM64 and x86-64 named-device guests compared the full row for both
mappings before and after transferring the debugfs descriptor. The
ordinary mapped UID `1234`, overflow UID `65534`, and initial UID `0`
also passed. The preceding ARM64 kernel failed both signed cases.
The DRM wire and fdinfo sanitizer suites passed, the allocation scan
reproduced the 150 baseline findings, and both guests measured zero slab
growth over 200 populated-table reads. Native M1 validation remains open.

The tested base was `17e6e32fbc04dd2bb7e635a2e194722e34fc716d` plus the
archived patch and the simple DRM named-device fixture. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-signed-uid-20261122.1ITjgJ/`.
The `bundle.tar.gz` SHA-256 is
`3c8adda570144a62e723dc6af23319eeb726e2126809969d7e01450bc851c39b`.

### Global GEM names

`gem_names` presents the legacy global GEM name table through the DRM
device directory and both minor links. The table contains only its
column header because Vinix has no GEM_FLINK namespace. Client-local
GEM handles and DMA-BUF exports use separate namespaces. [Pinned Linux GEM name listing](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L136-L156)

The DRM sysfs sanitizer fixture checked the header byte for byte through
the Asahi card and render links and the VirtIO-MMIO render link. It
verified that the file follows the device directory's ownership and is
removed on unregister. Three controls caught a missing file, altered
spacing and publication into a competing directory. Independent lifetime
review confirmed that sysfs owns the text for the file's lifetime.

Both kernel builds used `-O1` for C compilation. The ARM64 DRM discovery
and x86-64 class version and debugfs permission probes passed in QEMU
under TCG. The allocation scan reproduced the 150 baseline findings.
Native M1 validation remains open.

The tested base was `d1f29ac7377100630b77670090dbe169f7d9234f` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-gem-names-20261122.XWd8qs/`.
The `bundle.tar.gz` SHA-256 is
`485dd5826fda99537243a6f51d2c958cfe0ac1969d3a534f6d61060904fcdd38`.

### Driver file permissions

`debugfs_add_file()` creates files such as `asahi_stats` with mode
`0444`. The `0700` debugfs root gates access through the normal
`/sys/kernel/debug` path. [Pinned Linux DRM file mode](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L460-L482)

The DRM sysfs sanitizer fixture checked the file mode, reads through
both minor links and removal at unregister. The same fixture rejected
the previous `0400` mode.

Both kernel builds used `-O1` for C compilation. ARM64 and x86-64 QEMU
guests under TCG verified that unprivileged traversal of the debugfs root
still returns `EACCES`. The ARM64 DRM discovery probe passed, and the
allocation scan reproduced the 150 baseline findings. Native M1 validation
remains open.

The tested base was `1c1a6efa934dae901c4802862f05cea645a1d63e` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-debugfs-file-mode-20261122.TgKbIb/`.
The `bundle.tar.gz` SHA-256 is
`d0f6bc3d89ec66f5b8a5222ffd30eec22ac853a70150e6abe095681a9ea5950e`.

### Debugfs root permissions

Sysfs creates `/sys/kernel/debug` with owner `0:0` and mode `0700` before
drivers can publish entries there. The VFS checks that mode when opening
the directory and when looking up children. [Pinned Linux default mode](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/fs/debugfs/inode.c#L29-L30)

ARM64 and x86-64 kernel builds used `-O1` for C compilation. QEMU guests
on both architectures verified root access, unprivileged denial and
continued access to `/sys/kernel` and `/sys/class/drm`. The ARM64 baseline
lacked the directory with a virtual DRM device, and an x86-64 control
with mode `0555` failed the permission probe. The ARM64 DRM discovery
probe and host DRM sysfs sanitizer fixture also passed. The allocation
scan reproduced the 150 baseline findings. Native M1 validation remains open.

The tested base was `98517d8b663049da7fbb6c53aaf69d51ae4b8f20` plus the
archived patches. Evidence is stored at
`/Users/alex/.local/state/vinix/m1-drm-debugfs-mode-20261122.rbAmVm/`.
The `bundle.tar.gz` SHA-256 is
`913af439968603d2d1020a7840f79cd818cf5d1b8e631a6cc6cbc79d7153fcc0`.

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
