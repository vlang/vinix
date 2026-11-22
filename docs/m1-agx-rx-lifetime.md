# G13 receive ring teardown

Omarchy's pinned Asahi serializes receive polling under its RX mutex.
Vinix now holds the GPU manager lock while copying and acknowledging each
Event, KTrace or Stats entry. Shutdown uses the same lock to stop firmware
and release the channel backing.
[Asahi receive polling](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L472-L486)

Vinix releases the lock before dispatching from the private event copy.
Fault and channel recovery check running state under the manager lock.
A stale worker error preserves stopped state, and a repeated call to the
shared shutdown method returns once teardown has completed.

ARM64 and x86-64 builds, 82 contract files, three sanitizer suites and five
pinned source gates passed for `9b390e1520dd92ce367ef6dd3743cd26850ade15` plus
the archived patch. The failure fixture covers 18 receive/shutdown
interleavings, six stale fatal events, and two copied TVB payloads at ring
reuse. Three negative controls detected an unlocked acknowledgement, a
stale error overwriting stopped state, and repeated teardown. Independent
lifetime review and generated C checks passed. Receive copies stay on the
stack. The allocation scan reported one fewer ARM64 allocation site and
178 existing allowance discrepancies.

At this revision the audit reported `not_equivalent`, with open differences
in RTKit crash-log buffer ownership and G17 worker teardown. No hardware tests
or reboots occurred. [RTKit crash-log follow-up](m1-agx-rtkit-snapshot.md)

Evidence is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-rx-lifetime-20261118/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `920780fbce555cf7ee5ee3ef752a031dc60bdc3b6a6fc1f26c2e3cc9932b3a76` |
| `bundle.tar.gz.inventory.txt` | `06e07bf5b10cb94af57ff9d1bdadd71bd70ac4abbad6a54f2ffcc7eac8e0bdc3` |

## ASC mailbox receive during shutdown

The G13 worker now holds the manager lock while checking running state and
reading one ASC mailbox message. Shutdown takes the same lock before it
marks the manager stopped and stops the ASC. The worker releases the lock
before it dispatches the copied message.

The sanitizer fixture reproduced a FIFO pop racing shutdown on
`9fc17b7d32564db6895d7d0fa6a2156c8c246100`. Six cases passed across both
G13 firmware ABIs. Shutdown before a receive preserves both queued messages.
Shutdown after the first receive suppresses its power-state update and
preserves the second message. A later poll on a stopped manager leaves the
FIFO untouched.

AArch64 and x86-64 builds, the job-lifetime suite, 79 local contract tests,
and 122 pinned-reference checks passed. Generated AArch64 C keeps the FIFO
read within the manager lock. The allocation scan matched the 176 baseline
findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-rx-shutdown-20261119.N4nx89/`.
The `bundle.tar.gz` SHA-256 is
`4f12c50cc8e2addfa865aca3652cb981d36f7685707b0db47807c8e76c736af9`.
Native M1 firmware validation remains open.

## ASC stop confirmation before G13 teardown

G13 now reads back the ASC RUN bit after the stop write and its MMIO
barrier. Probe cleanup and runtime shutdown mask both claimed IRQs and
retain firmware-visible backing if the stop write or readback fails.
Runtime shutdown keeps the manager available for a later attempt. It
publishes stopped and retires UAT roots only after RUN has cleared.
A failed probe remains unpublished and retains its backing.

The sanitizer fixture reproduced premature RTKit buffer release on
`5d517cea2b49a21ec9df85a4ed499ad2e06cfa78`. Four cases passed across the
two G13 firmware ABIs with an injected stop failure in probe cleanup or
runtime shutdown. They check backing retention, IRQ masking and lock
release on failure, then verify cleanup after a successful stop.

AArch64 and x86-64 builds, the job-lifetime suite, 79 local contract tests
and 122 pinned-reference checks passed. Generated AArch64 C confirms the
readback and early return before release. The allocation scan matched the
176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-stop-readback-20261119.ErG0D4/`.
The `bundle.tar.gz` SHA-256 is
`936adb04e917cd00455624653cdc132816b364f0bda0da854f82c43968fc7e09`.
Native M1 firmware validation remains open.

## Cleanup retry for an unpublished G13 probe

An unconfirmed ASC stop now returns a distinct probe result. The driver
retains that manager privately and retries its cleanup on shutdown or
before another initialization can replace the UAT. Repeated stop failures
retain the same owner and backing. A confirmed stop runs the probe cleanup
and clears the driver's private reference. Only a successful probe
publishes the GPU manager and registers DRM.

Sanitizer cases for both firmware ABIs cover an initial stop failure,
another failed cleanup attempt, successful release and an idempotent
subsequent call. A negative control that dropped the private reference
after a failed retry was detected. Both kernel builds, the job-lifetime
suite, 79 local contract tests and 122 pinned-reference checks passed
against `83ba6486d5111364333a58d298a4cde22206d4f3` plus the archived
patch. The allocation scan matched the 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-asc-probe-cleanup-20261119.8UnNGo/`.
The `bundle.tar.gz` SHA-256 is
`e74e764202e8af6375c28f44530cbd936a6fb61e21330ba90e35d624446af028`.
Native M1 firmware validation remains open.

## Cleanup after DRM registration failure

The AGX driver publishes the global manager after DRM registration succeeds.
If registration fails after firmware startup, the driver runs the normal
GPU shutdown path. An unconfirmed G13 ASC stop leaves the unregistered
manager under driver ownership. Shutdown or the next initialization can
retry before a new probe replaces the UAT.

Six sanitizer cases across both firmware ABIs cover registration success,
failure cleanup, and a failed stop followed by successful cleanup. Three
negative controls detected early publication, missing cleanup and shutdown
that skipped an unregistered manager. Both kernel builds, the job-lifetime
suite, 79 local contract tests and 122 pinned-reference checks passed
against `41c9ed349e0ad7f148a074723e3990afb5a83ba4` plus the archived patch.
The allocation scan matched the 176 baseline findings.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-agx-drm-registration-20261119.YnIjzc/`.
The `bundle.tar.gz` SHA-256 is
`763ee40f2c3608a19a10328fcfea00e5659078bf5407e70d4356f7c14209e5d8`.
Native M1 firmware validation remains open.

## DRM node readiness

DRM publishes readiness after installing the driver context, requested
card and render nodes, and registry entry. An open that reaches a node
before publication or after unregister returns `ENODEV`. Successful opens
return the resource already installed in devtmpfs.

The DRM wire sanitizer fixture covers card-only and card-plus-render
registration, opens during node creation, unregister, and an injected
render-node creation failure. Negative controls caught early publication
and an open that skipped the readiness check. The AGX file-close and G13
failure sanitizer suites, both kernel builds, 79 local contract tests
and 122 pinned-reference checks passed against
`51094f779c9777e828a90088fc215835d85e0547` plus the archived patch.
The allocation scan returned 176 findings. Its only change was the
existing node interface allocation classified as an explicit cast.
Generated AArch64 C confirms there is no allocation in the open callback.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-node-readiness-20261119.tR6HXk/`.
The `bundle.tar.gz` SHA-256 is
`91b99cd17e3be58222a84513e5eb1e7b3207f936fb4a2fc3cdf3b2a428bf0270`.
Native M1 validation remains open.

## DRM device name removal and slot reuse

Unregister marks the device inactive, detaches its card and render names,
and releases its slot under the registry lock. A stale unregister checks
the device pointer against the slot's current owner. Old open files keep
their original device identity. A failed render-node creation detaches
the staged card node, and DRM activity reports the number of live slots.

The DRM wire sanitizer fixture filled 64 active slots and reused a freed
slot 70 times while retaining the old card and render objects. It checked
that stale unregister leaves the replacement active and existing opens
cannot address it. Negative controls caught missing teardown, missing
registration rollback and a missing owner check. Both AGX sanitizer
suites and kernel builds passed, along with 79 local contract tests and
122 pinned-reference checks. The allocation scan matched the 176 baseline
findings. The tested base was `a7da85a72ebcc34c753f3942b5f5168c362e6e52`.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-slot-reuse-20261119.qpJ3ja/`.
The `bundle.tar.gz` SHA-256 is
`cc7c683c3b7fd6f3abb052b45935e671867559d2ce72ff6e874c8abc4db0b5ef`.
Native M1 validation remains open.

## DRM mapping admission after unregister

DRM core now rejects a new mapping with `ENODEV` after its device is
unregistered, including the path for drivers without an admission callback.
It also rejects expansion of an existing mapping on the inactive device.
Existing mappings retain and release backing through the original device
when the slot is reused.

The DRM wire sanitizer fixture reproduced new mapping admission on
`929db3aa5fc9cb4b043238d9fa57703aecd3db3c`. A regression control that
removed the growth check caught expansion after unregister. The revised
fixture checked three callback configurations across slot reuse, including
retaining and releasing old backing and admitting mappings on the new
device. Both AGX sanitizer suites, both kernel builds, 79 local contract
tests and 122 pinned-reference checks passed. Allocation findings matched
the baseline.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-mmap-unregister-20261119.N5W8ab/`.
The `bundle.tar.gz` SHA-256 is
`d9e54898d0e15072a308b69801dd6f211b8e353701373160015c592835bbdb96`.
Native M1 validation remains open.

## Metadata-only DRM handles across unregister

A still-reachable DRM node can be opened with `O_PATH` before device
publication or after unregister. Data opens still require registration and
return `ENODEV` on the inactive device. VFS returns `EBADF` for ioctl calls
on path-only descriptors before dispatch. Closing a DRM path handle drops
its node reference. Data handles retained across unregister still close
through their original driver and release their syncobj owner.
[Linux path-only open](https://github.com/torvalds/linux/blob/v6.12/fs/open.c#L855-L872),
[ioctl descriptor lookup](https://github.com/torvalds/linux/blob/v6.12/fs/ioctl.c#L844-L857),
[descriptor filtering](https://github.com/torvalds/linux/blob/v6.12/fs/file.c#L1044-L1059).

The DRM wire sanitizer fixture verified both open modes, minor-number reuse
and close callbacks. The original open gate and a control with unconditional
close callbacks both failed. The six descriptor-flags cases passed in
AArch64 and x86-64 QEMU guests. The linked-file and directory cases verified
that `fstat` succeeds on `O_PATH` and ioctl returns `EBADF`. An AArch64
kernel with the VFS check omitted failed the new assertion.

Both kernel builds, both AGX sanitizer suites, 79 local contract tests
and 122 pinned-reference checks passed. The allocation scan matched the
176 existing findings. The tested base was
`fcaa2b8cf58560e99657202159539d5e2ad9577b` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-path-handles-20261119.yFoXLl/`.
The `bundle.tar.gz` SHA-256 is
`a4d39ddcfb411d9552c710d06d2a0b09a043b33729dca991826bbc69693ee9b3`.

## DRM name collisions during registration

Devtmpfs checks the card name and any requested render name under one
writer lock before publishing either DRM node. An occupied name returns
`EEXIST`. A non-directory `/dev/dri` returns `ENOTDIR`. Rejection releases
the unpublished device, nodes and resource boxes, leaving the registry
slot available. Data opens become available after the names and registry
entry are installed.

The DRM wire sanitizer fixture covered an unavailable devtmpfs, a
non-directory `dri`, collisions at each leaf, card-only registration
beside an occupied render name, and registry slot reuse. Two controls
caught missing collision checks and card publication before the render
check. The independent lifetime review confirmed that all recoverable
failures precede publication. Generated ARM64 code confirms that the
failure path releases each unpublished allocation.

Both kernel builds, both AGX sanitizer suites, 79 local contract tests
and 122 pinned-reference checks passed. Both QEMU guests passed the
descriptor-flags suite, and the ARM64 guest logged creation of the
simple DRM card. The allocation scan matched the 176 existing findings.
The tested base was `ac5698ad846ad3bcfdc7051e77f924c65b0db8ac` plus
the archived patch. Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-name-publication-20261119.ImjujQ/`.
The `bundle.tar.gz` SHA-256 is
`9f0be0a75fe94380a6f0da660d7d1c0420a55a0320662aabd1646251ceba73ea`.

## DRM registration allocation failures

DRM allocates the device record, each node record and each resource box
with the fallible allocator. Failure returns `ENOMEM`, releases every
allocation made for the unpublished registration, and leaves the names
and registry slot available. Successful devtmpfs publication transfers
ownership before the device starts accepting data opens.

The DRM wire sanitizer fixture injected 64 failures at all five sites
across card-only and card-plus-render registration. Each case checked
the live allocation count, empty namespace and successful retry. Two
controls caught a missing free after box allocation failure and missing
cleanup after a partial construction. The independent lifetime review
and generated ARM64 code confirmed the allocation and cleanup order.

Both kernel builds, both QEMU descriptor-flags suites, both AGX
sanitizer suites, 79 local contract tests and 122 pinned-reference
checks passed. The ARM64 guest logged simple DRM card creation. The
allocation scan found three fewer implicit DRM sites on each
architecture, with 174 existing allowance findings. The tested base
was `29d22abfad57f54834f2c0f01caee9f06ee55a44` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-registration-oom-20261119.fYrPl6/`.
The `bundle.tar.gz` SHA-256 is
`ce232a872e853cca35a24d006040391e2d1ed57e420bf436a2fee64e2d552204`.

## Driver metadata after rejected registration

Native AGX, fake G17, simple DRM and VirtIO GPU transfer their heap driver
descriptors and ioctl tables to DRM registration. Rejection frees the
table and descriptor before returning to the caller. A registered
device keeps both available to files that survive unregister. Driver
private context stays with its caller, so AGX can retain a manager across
an unconfirmed firmware stop.

The DRM wire sanitizer fixture measured the releases across 80 injected
allocation failures, 16 name collisions and a full registry. It also
verified a successful retry and access to its table after unregister.
Two controls caught missing frees. The independent lifetime review and
generated ARM64 code confirmed ownership at each caller.

Both kernel builds, both QEMU descriptor-flags suites, both AGX
sanitizer suites, 79 local contract tests and 122 pinned-reference
checks passed. The allocation scan matched the 174 existing findings.
The tested base was `7ecf4b9787e98eda28b366e681f28ce0dbcf209b` plus
the archived patch. Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-owned-driver-20261119.L80oKk/`.
The `bundle.tar.gz` SHA-256 is
`1e942eece7c13d2d70e6b1d94f80aecc9c24990b1daaf7c6ee8015c18bce4212`.

## Static ioctl tables and fallible driver definitions

Native AGX, fake G17, simple DRM and VirtIO GPU use fixed ioctl tables.
Each registration borrows its table through an allocation-free view and
allocates a private copy of the driver definition with the fallible
allocator. A failed definition allocation returns `ENOMEM`. A later
rejection releases the definition. The fixed table remains available
to other registrations and to files that survive unregister.

The DRM wire sanitizer fixture injected 48 failures across the
definition, device, node and box allocations. It checked live storage,
absence of published names, the static table during retry and table
access after unregister. Two controls caught a leaked definition and a
view missing `.nofree`. The independent lifetime review compared all 48
ioctl entries and confirmed their storage in generated ARM64 code.

Both kernel builds, both QEMU descriptor-flags suites, both AGX
sanitizer suites, the ARM64 modern dispatch checker, 79 local contract
tests and 122 pinned-reference checks passed. The allocation scan found
eight fewer implicit sites on AArch64 and two fewer on x86-64, with 173
existing allowance findings. The tested base was
`8f25fccef5cb2b37a8ac046ad7e71e3c2eb461f7` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-driver-definition-20261119.Gpl3ZL/`.
The `bundle.tar.gz` SHA-256 is
`923255fd53c319b74b103cfe225de8f58b4699264ca299d1414276f91e137a01`.

## Fallible DRM device leaf publication

DRM formats temporary device names on the stack. Devtmpfs prepares each
requested leaf record and its owned name with fallible allocations before
publishing either entry. An allocation failure returns `ENOMEM` and
releases the prepared storage. The `dri` directory and VFS child map
retain their existing allocation paths.

The DRM wire sanitizer fixture passed 336 injected allocation failures
across the registration entry points. It checked that failed registrations
released their storage, kept the namespace empty and allowed retry. Two
controls caught missing cleanup after a name allocation failure and after
render leaf preparation failed. The independent lifetime review confirmed
ownership through publication and detach. Generated ARM64 code confirmed
stack storage for all three temporary name buffers.

Both kernel builds, both QEMU descriptor-flags suites, both AGX sanitizer
suites, 79 local contract tests and 122 pinned-reference checks passed.
The ARM64 guest logged simple DRM card creation. The allocation scan
matched the 173 existing findings. The tested base was
`b2c1a7765a6b0b5c404dc5c3da5d46985a874167` plus the archived patch.
Native M1 validation remains open.

Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-leaf-staging-20261119.F7Tz4Q/`.
The `bundle.tar.gz` SHA-256 is
`dce6e82d93b18e965c01de043dcf75460c0a757341d74f9abccb4ec0cd3cf031`.

## Paired DRM directory publication

Devtmpfs initializes both DRM leaves before inserting them under one
directory lock. Path lookups and directory snapshots take that lock, so
a reader observes the pair together. Data opens become available after
DRM installs the registry entry.

The DRM wire sanitizer fixture inspected the directory at each unlock.
A control that released the lock between insertions exposed a partial
pair. Generated ARM64 code showed both map insertions between one acquire
and release. The allocation scan matched the 173 baseline findings.

Both kernel builds, the QEMU descriptor-flags suites, both AGX sanitizer
suites and all 79 local contract tests passed. An ARM64 QEMU boot with
the fake G17 driver enabled logged publication of `card0` and
`renderD128`. Native M1 validation remains open.

The tested base was `a77430d795afe96188f9c8283aa70e7e48bd646c` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-paired-publication-20261119.NtAk6Z/`.
The `bundle.tar.gz` SHA-256 is
`c49fc226b8057fc0594c07ec3e7038934fa115e90a2ba2e52ede92418c3dc3ae`.

## DRM registration with a full table

When all 64 device slots are occupied, DRM sets `EBUSY` before returning
from the slot search. This matches the exhaustion errno of the pinned
Linux DRM minor allocator. Linux has a larger minor-number range.
[DRM minor allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_drv.c#L143-L161)
[XArray exhaustion](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/lib/xarray.c#L2008-L2032)

The DRM wire sanitizer fixture checked all four registration entry points,
allocation failure before a slot search, ownership cleanup and reuse of
a freed slot. The previous implementation failed the stale errno check.
Both kernel builds, both QEMU descriptor-flags suites, both AGX sanitizer
suites, 79 local contract tests and 122 pinned-reference checks passed.
The allocation scan matched the 173 baseline findings.

The tested base was `538c081ac3a86a5566591c43e6cb43174e78f372` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-registry-full-20261119.BKLVIq/`.
The `bundle.tar.gz` SHA-256 is
`7ca6ef905066d5e7e1dcbc56f72b9d105d9921923caccf2a52c3b6a8a8ec7b10`.

## Paired DRM directory removal

Unregister marks the device inactive, then removes the matching card and
render names under one directory lock. Each removal checks the resource
identity, so a replacement at either name is preserved. Devtmpfs drops
the namespace references after unlocking the directory map. Open handles
keep the detached nodes alive through the existing grace-period retirement.
DRM releases the registry slot after this removal returns.

The DRM wire sanitizer fixture checked both names at the lock boundary,
card-only devices, absent and replaced names, open handles and slot reuse.
Two controls caught a split removal and a missing identity check. The
independent lifetime review and generated ARM64 code confirmed the order
of parent pins, map updates, reference drops and retirement.

Both kernel builds, both QEMU descriptor-flags suites, both AGX sanitizer
suites, 79 local contract tests and 122 pinned-reference checks passed.
The allocation scan matched the 173 baseline findings. Native M1
validation remains open.

The tested base was `cd32b339145c967212b89abc663888f41a3b63a5` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-paired-removal-20261119.xeY3Qw/`.
The `bundle.tar.gz` SHA-256 is
`2eb665a310a839a8308b3361c16c26cd500a73064670e162c2dc3994f5549c0b`.

## First DRM directory creation after staging

Devtmpfs checks an existing `/dev/dri` for type and name collisions before
staging the DRM leaves. When the directory is absent, it creates it after
all requested leaf allocations succeed. A recoverable failure on the first
registration therefore leaves the directory absent.

The DRM wire sanitizer fixture injected 14 first-registration allocation
failures across card-only and paired registration, checked cleanup and an
empty registry, and verified successful retry. The previous implementation
failed the directory absence check. Independent lifetime review and generated
ARM64 code confirmed that staging is private and parent assignment precedes
publication.

Both kernel builds, both AGX sanitizer suites, 79 local contract tests and
122 pinned-reference checks passed. The allocation scan matched the 173
baseline findings. QEMU descriptor-flags checks passed with debug-stripped
copies of both kernels and matching loadable segment layouts. The ARM64
guest reused the previous smoke test ISO with the new kernel and logged
`/dev/dri/card0` creation. Native M1 validation remains open.

The tested base was `fbcdafd462a11362b68b4af30be957d657af48eb` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-initial-directory-20261119.oXyMjn/`.
The `bundle.tar.gz` SHA-256 is
`ed1de8be7a183ce6f14d3590883397578025e164aa62e676559ba9d02b9d6769`.

## Complete `/dev/dri` on first publication

On first registration, devtmpfs initializes the new directory and its dot
entries privately. It inserts the requested DRM leaves, then adds `/dev/dri`
to the devtmpfs root under the same directory lock. A reader can find the
directory as soon as the requested card and optional render name are present.

The DRM wire sanitizer fixture checked the first observable directory for
card-only and paired registration and retained the 14 allocation failure
cases. A control that published the directory early exposed an empty one.
Independent lifetime review and generated code confirmed parent assignment
and map insertion order. The allocation scan matched the 150 findings at
the tested base.

Both kernel builds, the DRM sysfs sanitizer fixture, 79 local contracts and
122 pinned-reference checks passed. The ARM64 QEMU DRM sysfs probe found
the card and its sysfs entries. The x86-64 descriptor-flags smoke test passed.
Native M1 validation remains open.

The tested base was `3fb9fece2acca39e35916eb0ff5ccab49f5a2be0` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-first-publication-20261122.yNE37j/`.
The `bundle.tar.gz` SHA-256 is
`710d641c0d70cb59b3d756700414efc617734e94ec969ad83f0c1668d8a05a0f`.

## Exclusive DRM debugfs directory claims

DRM claims the final debugfs directory name under the VFS and sysfs
locks. Intermediate directories can be shared. Only the successful
claimant publishes debugfs minor links and stores the directory path
for teardown.

The DRM sysfs sanitizer fixture made a competing publisher take the name
immediately before creation. The previous publisher accepted the occupied
directory. The revised publisher rejected the claim and left the winner's
file accessible after the losing device unregistered. Independent review
and generated kernel code confirmed the locking and ownership order.

Both kernel builds, the DRM wire sanitizer fixture, 79 local contracts
and 122 pinned-reference checks passed. The ARM64 QEMU DRM sysfs probe
and x86-64 descriptor-flags smoke test passed. The allocation scan matched
the 150 findings at the tested base. Native M1 validation remains open.

The tested base was `8b4c3f6f32b223deb270a1564667da96dc9d83d3` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-debugfs-claim-20261122.AvqTjQ/`.
The `bundle.tar.gz` SHA-256 is
`73571024f83fcbf7c65979a4ffa1c5e9c460b89709968466372034543d8946a5`.

## DRM debugfs minor link ownership

DRM records successful link creation for the card and render minors
independently. Unregister removes the recorded links and the device's
directory. An occupied numeric path survives a failed link creation and
subsequent unregister. Linux likewise removes the symlink saved at
registration. [Linux DRM debugfs minor lifecycle](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_debugfs.c#L431-L455)

The DRM sysfs sanitizer fixture blocked each minor path in turn and
verified that unregister preserved the occupied directory and removed
the successful link. Controls caught unconditional removal of the card
and render paths. Independent lifetime review and generated ARM64 code
confirmed the per-link ownership checks.

Both kernel builds used `-O1` for C compilation. The ARM64 QEMU DRM sysfs
probe passed with TCG after an HVF assertion in virtio-net initialization.
The x86-64 descriptor-flags smoke test, DRM wire sanitizer fixture,
79 local contracts and 122 pinned-reference checks passed. The allocation
scan matched the 150 baseline findings. Native M1 validation remains open.

The tested base was `1d9cb26010811116cf53058dec5696885a50ee8b` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-debugfs-links-20261122.uj7ZJa/`.
The `bundle.tar.gz` SHA-256 is
`29908e1c5dd7da82f5d78c81c4881ed76683aec6dbea97172f55fe2d9010813e`.

## DRM sysfs minor ownership

Each DRM minor claims its sysfs directory exclusively. After the claim,
DRM records creation of the class and character-device links separately.
Unregister removes the recorded links and directory. Occupied paths and
their contents survive partial publication and teardown.

The DRM sysfs sanitizer fixture blocked each of the three paths for both
card and render minors. It verified that the sibling minor stayed available
through publication and that teardown removed the entries DRM owned. Three
controls caught reuse of an occupied directory and unconditional removal of
either link. Independent lifetime review and generated ARM64 code confirmed
the ownership checks. The allocation scan matched the 150 baseline findings.

Both kernel builds used `-O1` for C compilation. The ARM64 QEMU DRM sysfs
probe passed with TCG, and the x86-64 descriptor-flags smoke test passed.
The DRM wire sanitizer fixture, 79 local contracts and 122 pinned-reference
checks passed. Native M1 validation remains open.

The tested base was `ffd253d20e83089d58b02422d855b5540c4835c5` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-minor-sysfs-20261122.iRMg3j/`.
The `bundle.tar.gz` SHA-256 is
`e439641bdaa916b326ccc5397b4ce24f249b66d9ae3294e95978193ea84bca2d`.

## DRM readiness after core sysfs publication

DRM reserves the card number and publishes its devtmpfs entries before
running the core sysfs publisher. During that interval, metadata-only opens
can reach the nodes. Data opens and registry lookups become available when
the publisher returns. The registry lock serializes both readiness changes
with the GPU activity count and driver list, which omit pending and retiring
devices.

The DRM wire sanitizer fixture paused card-only and paired registration at
the publication boundary. It checked metadata and data opens, registry
lookup, a second registration, an unregister attempt, and the GPU activity
report during setup and teardown. Controls caught early readiness and
activity that counted reserved slots. Independent lifetime review and
generated code confirmed the lock and publication order.

Both kernel builds used `-O1` for C compilation. The ARM64 QEMU DRM sysfs
probe passed with TCG and the x86-64 descriptor-flags smoke test passed.
The DRM sysfs sanitizer fixture, 79 local contracts and 122 pinned-reference
checks passed. The allocation scan matched the 150 baseline findings.
Native M1 validation remains open.

The tested base was `06f322926e381d197ef00fc7190adb5574a21ad5` plus the
archived patch. Evidence is stored at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-sysfs-readiness-20261122.AQvL4K/`.
The `bundle.tar.gz` SHA-256 is
`99363127ae80162a221cc0779cdfcdf9c5b8fe9c402cb7c4c8ece2b8472bc3d1`.
